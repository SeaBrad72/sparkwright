#!/bin/sh
# provenance-precondition.sh — lock that EVERY SLSA provenance job's `if:` is gated on repo visibility.
#
# GitHub's build-provenance attestations API is UNAVAILABLE on user-owned PRIVATE repos — the single most
# common solo-adopter starting config. The dogfood found that an ungated `provenance` / `image-provenance`
# job makes `main` RED on first merge there, with no in-repo explanation. The fix gates each provenance
# job's `if:` on `github.event.repository.private == false || …owner.type == 'Organization'` (run at full
# strength on public/org repos; skip on user-owned private). This check asserts EACH such job-level `if:`
# carries the guard — per job-if, not merely somewhere in the file — so a half-gated profile (one job
# guarded, the other not) cannot slip through.
#
# SCOPE: a STRUCTURAL lock — every provenance job's if-condition contains the guard. The runtime behavior
# (the job actually skips on user-owned private and runs on public/org) is validated by a real push (the
# living-reference adopter project / the G2 golden-path CI run), not here; a workflow `if:` cannot be
# unit-tested without a real event.
#   sh conformance/provenance-precondition.sh [--selftest]
# Exit: 0 = every provenance job-if is gated · 1 = an ungated provenance job-if · 2 = setup.
# POSIX sh; dash-clean.
set -eu

ROOT="${PROV_ROOT:-.}"
TOK_PRIV='github.event.repository.private == false'
TOK_ORG="github.event.repository.owner.type == 'Organization'"

# check_file <ci.yml>: N/A (0) if no provenance job; else assert EVERY 4-space job-level `if:` gating a
# push-to-main job (the provenance + image-provenance jobs) carries BOTH guard tokens. PER-LINE, so one
# guarded + one ungated job-if FAILS. 8-space step-level ifs are not matched (only `    if: ` job-level).
check_file() {
  f=$1
  grep -q 'attest-build-provenance' "$f" 2>/dev/null || { echo "N/A: $f (no provenance job)"; return 0; }
  rc=0; n=0
  while IFS= read -r line; do
    case "$line" in
      "    if: "*"refs/heads/main"*)
        n=$((n + 1))
        _ok=1
        case "$line" in *"$TOK_PRIV"*) : ;; *) _ok=0 ;; esac
        case "$line" in *"$TOK_ORG"*) : ;; *) _ok=0 ;; esac
        if [ "$_ok" -eq 0 ]; then
          echo "FAIL: $f has a push-to-main job-if NOT gated on repo visibility:"
          echo "      $line"
          rc=1
        fi
        ;;
    esac
  done < "$f"
  if [ "$n" -eq 0 ]; then
    echo "FAIL: $f ships a provenance action but no push-to-main job-if was found to gate (unexpected)"
    return 1
  fi
  [ "$rc" -eq 0 ] && echo "PASS: $f — all $n provenance job-if(s) gated on repo visibility"
  return "$rc"
}

if [ "${1:-}" = "--selftest" ]; then
  d=$(mktemp -d); sf=0
  GATE="(github.event.repository.private == false || github.event.repository.owner.type == 'Organization')"
  # fully gated (provenance + image-provenance both guarded) -> PASS
  {
    printf 'jobs:\n  provenance:\n'
    printf "    if: github.ref == 'refs/heads/main' && %s\n" "$GATE"
    printf '    steps:\n      - uses: actions/attest-build-provenance@v1\n'
    printf '  image-provenance:\n'
    printf "    if: github.ref == 'refs/heads/main' && needs.ci.outputs.has_dockerfile == 'true' && %s\n" "$GATE"
    printf '    steps:\n      - uses: actions/attest-build-provenance@v1\n'
  } > "$d/ok.yml"
  if check_file "$d/ok.yml" >/dev/null 2>&1; then echo "selftest PASS: both job-ifs gated -> PASS"; else echo "selftest FAIL: fully-gated wrongly failed"; sf=1; fi
  # HALF-gated: provenance guarded, image-provenance NOT -> must FAIL (the reviewer's gap)
  {
    printf 'jobs:\n  provenance:\n'
    printf "    if: github.ref == 'refs/heads/main' && %s\n" "$GATE"
    printf '    steps:\n      - uses: actions/attest-build-provenance@v1\n'
    printf '  image-provenance:\n'
    printf "    if: github.ref == 'refs/heads/main' && needs.ci.outputs.has_dockerfile == 'true'\n"
    printf '    steps:\n      - uses: actions/attest-build-provenance@v1\n'
  } > "$d/half.yml"
  if check_file "$d/half.yml" >/dev/null 2>&1; then echo "selftest FAIL: half-gated (one job-if ungated) NOT caught"; sf=1; else echo "selftest PASS: half-gated -> FAIL (per-job-if enforcement)"; fi
  # no provenance job -> N/A
  printf 'jobs:\n  ci:\n    steps:\n      - run: echo hi\n' > "$d/na.yml"
  if check_file "$d/na.yml" >/dev/null 2>&1; then echo "selftest PASS: no provenance -> N/A"; else echo "selftest FAIL: N/A wrongly failed"; sf=1; fi
  [ "$sf" -eq 0 ] && { echo "OK: provenance-precondition selftest"; exit 0; } || { echo "FAIL: provenance-precondition selftest"; exit 1; }
fi

case "${1:-}" in "") : ;; *) echo "usage: provenance-precondition.sh [--selftest]" >&2; exit 2 ;; esac

fail=0; found=0
for f in "$ROOT"/profiles/*/ci.yml; do
  [ -f "$f" ] || continue
  found=1
  check_file "$f" || fail=1
done
[ "$found" -eq 1 ] || { echo "provenance-precondition: no profile ci.yml found under $ROOT" >&2; exit 2; }
if [ "$fail" -eq 0 ]; then echo "OK: every provenance job-if is gated on repo visibility/ownership"; exit 0; fi
echo "FAIL: an ungated provenance job-if (see above) — would red a user-owned private repo's main on first merge"; exit 1
