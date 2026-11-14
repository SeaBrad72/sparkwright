#!/bin/sh
# provenance-precondition.sh — lock that EVERY SLSA attestation runs only where GitHub allows it, and says so when it skips.
#
# GitHub offers artifact attestations on PUBLIC repositories; on a private or internal one only with GitHub
# Enterprise Cloud (docs.github.com, "Using artifact attestations to establish provenance for builds"). An
# attest step that cannot pass makes `main` RED on first merge with no in-repo explanation. SWAS-813: the plan
# cannot be read from a CI token, so the profiles gate on a DECLARATION instead of on who owns the repo:
#   - the `provenance` job runs when the repo is public OR the repo/org variable KIT_ATTEST_PRIVATE is true;
#   - the `image-provenance` job keeps its job condition (the GHCR image push needs no Enterprise Cloud), and
#     only its attest step (id: gate-image-provenance) carries the public-or-declared `if:` as its next line;
#   - every skip is visible: a notice step under the inverse expression, one as the last step of the `ci` job
#     (build provenance) and one beside the image attest step (image provenance);
#   - no shipped text sends the adopter to another owner type (the banned phrase is assembled in BANNED below, so
#     this file does not carry it): the cure is public, KIT_ATTEST_PRIVATE, or a dated na for gate-provenance
#     (conformance/gate-dispositions.txt).
# This check asserts each of those per job and per step, not merely somewhere in the file, so a half-gated
# profile (one job guarded, the other not) cannot slip through.
#
# SCOPE: a STRUCTURAL lock over profiles/*/ci.yml. The runtime behavior (the job actually skips on a private
# repo without the declaration and runs on a public one) is validated by a real push (the living-reference
# adopter project / the G2 golden-path CI run), not here; a workflow `if:` cannot be unit-tested without a
# real event.
#   sh conformance/provenance-precondition.sh [--selftest]
# Exit: 0 = every provenance job and step is gated, and every skip is announced · 1 = a violation · 2 = setup.
# POSIX sh; dash-clean.
set -eu

ROOT="${PROV_ROOT:-.}"
TOK_PRIV='github.event.repository.private == false'
TOK_DECL="vars.KIT_ATTEST_PRIVATE == 'true'"
TOK_ORG="github.event.repository.owner.type == 'Organization'"
JOB_IF_NEW="($TOK_PRIV || $TOK_DECL)"
STEP_IF="        if: $TOK_PRIV || $TOK_DECL"
NAME_ATTEST='      - name: Attest image provenance (digest-bound)'
TOK_INV="vars.KIT_ATTEST_PRIVATE != 'true'"
BANNED="move it to a git""hub org"   # the old cure; the lock refuses it case-insensitively (assembled so no shipped line carries it)
NOTE_BUILD='::notice::Build provenance skipped: attestations on a private repository need GitHub Enterprise Cloud; set KIT_ATTEST_PRIVATE once you have it'
NOTE_IMAGE='::notice::Image provenance skipped: attestations on a private repository need GitHub Enterprise Cloud; set KIT_ATTEST_PRIVATE once you have it'

# check_file <ci.yml>: N/A (0) if no provenance job; else assert, per job and per step:
#   `provenance` 4-space job-if = the public-or-declared expression, with no owner arm;
#   `image-provenance` 4-space job-if keeps the owner arm (the image push is not gated on attestation);
#   the image attest step's NEXT line is the step-level public-or-declared `if:`;
#   each notice step's own `if:` carries the inverse expression, once per kind that the file ships;
#   no line tells the adopter to move the repo to a GitHub org, and KIT_ATTEST_PRIVATE is named.
# PER-LINE, so one guarded + one ungated job-if FAILS. 8-space step-level ifs are not matched as job-ifs.
check_file() {
  f=$1
  grep -q 'attest-build-provenance' "$f" 2>/dev/null || { echo "N/A: $f (no provenance job)"; return 0; }
  rc=0; n=0; job=""; after_id=0; lastif=""; seen_prov=0; seen_img=0; nb=0; ni=0; na=0; inbp=0; nbp=0; after_bn=0; prev=""
  while IFS= read -r line; do
    if [ "$after_id" -eq 1 ]; then
      after_id=0
      if [ "$line" != "$STEP_IF" ]; then
        echo "FAIL: $f the image attest step (gate-image-provenance) is not followed by the step-level 'if: $TOK_PRIV || $TOK_DECL':"
        echo "      $line"
        rc=1
      fi
    fi
    case "$line" in
      "  "[a-z]*:)
        job=${line#  }; job=${job%%:*}
        if [ "$job" = provenance ]; then seen_prov=1; fi
        if [ "$job" = image-provenance ]; then seen_img=1; fi
        ;;
      "    if: "*"refs/heads/main"*)
        n=$((n + 1))
        _ok=1
        case "$job" in
          provenance)
            case "$line" in *"$JOB_IF_NEW"*) : ;; *) _ok=0 ;; esac
            case "$line" in *"$TOK_ORG"*) _ok=0 ;; *) : ;; esac ;;
          image-provenance)
            case "$line" in *"$TOK_PRIV"*) : ;; *) _ok=0 ;; esac
            case "$line" in *"$TOK_ORG"*) : ;; *) _ok=0 ;; esac ;;
          *) _ok=0 ;;
        esac
        if [ "$_ok" -eq 0 ]; then
          echo "FAIL: $f the push-to-main job-if of '$job' is not the one the lock allows (provenance: public or KIT_ATTEST_PRIVATE and no owner arm; image-provenance: unchanged, so the image push still runs):"
          echo "      $line"
          rc=1
        fi
        ;;
      "      - "*)
        # a new step: the image push step is tracked (it must carry no `if:`), and nothing may follow the build notice in the ci job
        inbp=0
        case "$line" in *"name: Build and push image"*) inbp=1; nbp=$((nbp + 1)) ;; esac
        if [ "$after_bn" -eq 1 ] && [ "$job" = ci ]; then
          echo "FAIL: $f a step follows the build-provenance notice in the ci job (it must be the LAST step of the ci job):"
          echo "      $line"
          rc=1
        fi
        ;;
      "        id: gate-image-provenance"*)
        na=$((na + 1)); after_id=1
        if [ "$prev" != "$NAME_ATTEST" ]; then
          echo "FAIL: $f the image attest step (gate-image-provenance) is not named exactly '- name: Attest image provenance (digest-bound)' (scripts/release-tag.sh finds the step by that name):"
          echo "      $prev"
          rc=1
        fi ;;
      "        if: "*)
        lastif=$line
        if [ "$inbp" -eq 1 ]; then
          echo "FAIL: $f the 'Build and push image' step carries an if: (the image push must run on every private organization repository; only the attest step is gated):"
          echo "      $line"
          rc=1
        fi ;;
    esac
    case "$line" in
      *"$NOTE_BUILD"*)
        nb=$((nb + 1))
        if [ "$job" = ci ]; then after_bn=1; else echo "FAIL: $f the build-provenance notice is not in the ci job"; rc=1; fi
        case "$lastif" in *"$TOK_INV"*) : ;; *) echo "FAIL: $f the build-provenance notice is not under the inverse expression ($TOK_INV)"; rc=1 ;; esac ;;
      *"$NOTE_IMAGE"*)
        ni=$((ni + 1))
        case "$lastif" in *"$TOK_INV"*) : ;; *) echo "FAIL: $f the image-provenance notice is not under the inverse expression ($TOK_INV)"; rc=1 ;; esac ;;
    esac
    prev=$line
  done < "$f"
  if [ "$n" -eq 0 ]; then
    echo "FAIL: $f ships a provenance action but no push-to-main job-if was found to gate (unexpected)"
    return 1
  fi
  if [ "$seen_prov" -eq 1 ] && [ "$nb" -ne 1 ]; then
    echo "FAIL: $f ships a provenance job but $nb build-provenance skip notice step(s) (want exactly 1, the last step of the ci job): a skip must say why"
    rc=1
  fi
  if [ "$seen_img" -eq 1 ] && { [ "$ni" -ne 1 ] || [ "$na" -ne 1 ]; }; then
    echo "FAIL: $f ships an image-provenance job with $na image attest step(s) and $ni image skip notice(s) (want 1 and 1): a skip must say why"
    rc=1
  fi
  if [ "$seen_img" -eq 1 ] && [ "$nbp" -ne 1 ]; then
    echo "FAIL: $f ships an image-provenance job with $nbp 'Build and push image' step(s) (want exactly 1, with no if:)"
    rc=1
  fi
  if grep -qiF "$BANNED" "$f"; then
    echo "FAIL: $f tells the adopter to change the repo's owner type; the cure is public, KIT_ATTEST_PRIVATE (Enterprise Cloud), or a dated na for gate-provenance"
    rc=1
  fi
  grep -q 'KIT_ATTEST_PRIVATE' "$f" || { echo "FAIL: $f never names KIT_ATTEST_PRIVATE"; rc=1; }
  [ "$rc" -eq 0 ] && echo "PASS: $f — all $n provenance job-if(s), the image attest step and every skip notice are in the allowed shape"
  return "$rc"
}

if [ "${1:-}" = "--selftest" ]; then
  d=$(mktemp -d); sf=0
  # The one fully-shaped fixture (provenance + image-provenance, both notices); each mutant below is a sed or an append over it.
  {
    printf '%s\n' 'jobs:' '  ci:' '    steps:' '      - uses: actions/checkout@v4'
    printf '%s\n' '      - name: Build provenance skipped (notice)'
    printf "        if: github.event_name == 'push' && github.event.repository.private != false && %s\n" "$TOK_INV"
    printf '%s\n' '        run: |' "          echo \"$NOTE_BUILD\""
    printf '%s\n' '  provenance:'
    printf "    if: github.ref == 'refs/heads/main' && %s\n" "$JOB_IF_NEW"
    printf '%s\n' '    steps:' '      - uses: actions/attest-build-provenance@v1'
    printf '%s\n' '  image-provenance:'
    printf "    if: github.ref == 'refs/heads/main' && needs.ci.outputs.has_dockerfile == 'true' && (%s || %s)\n" "$TOK_PRIV" "$TOK_ORG"
    printf '%s\n' '    steps:'
    printf '%s\n' '      - name: Build and push image' '        uses: docker/build-push-action@v6'
    printf '%s\n' '      - name: Image provenance skipped (notice)'
    printf "        if: github.event.repository.private != false && %s\n" "$TOK_INV"
    printf '%s\n' '        run: |' "          echo \"$NOTE_IMAGE\""
    printf '%s\n' '      - name: Attest image provenance (digest-bound)' '        id: gate-image-provenance'
    printf '%s\n' "$STEP_IF"
    printf '%s\n' '        uses: actions/attest-build-provenance@v1'
  } > "$d/ok.yml"
  # _mut <name> <sed-script> <expected>: the mutant must differ from ok.yml (an anchor that hit nothing proves nothing) and must FAIL.
  _mut() {
    sed "$2" "$d/ok.yml" > "$d/$1.yml"
    if cmp -s "$d/ok.yml" "$d/$1.yml"; then echo "selftest FAIL: mutant $1 — its anchor hit nothing, so it proves nothing"; sf=1; return 0; fi
    if check_file "$d/$1.yml" >/dev/null 2>&1; then echo "selftest FAIL: mutant $1 NOT caught ($3)"; sf=1; else echo "selftest PASS: mutant $1 -> FAIL ($3)"; fi
  }
  if check_file "$d/ok.yml" >/dev/null 2>&1; then echo "selftest PASS: fully shaped (job-ifs, step-if, both notices) -> PASS"; else echo "selftest FAIL: fully-shaped wrongly failed"; sf=1; fi
  # the org arm restored on the provenance job (every org-owned private repo would run an attest step that cannot pass)
  _mut org-arm-on-provenance "/^  provenance:\$/,/^  image-provenance:\$/s/vars.KIT_ATTEST_PRIVATE == 'true')/github.event.repository.owner.type == 'Organization')/" "org arm restored on provenance"
  # the step-level if dropped from the image attest step (it would run, and fail, on a private org repo)
  _mut step-if-dropped "/^        id: gate-image-provenance\$/{n;d;}" "step-level if dropped"
  # the notices dropped (a skip with no stated cause)
  _mut build-notice-dropped "/Build provenance skipped: attestations/d" "ci-job notice dropped"
  _mut image-notice-dropped "/Image provenance skipped: attestations/d" "image notice dropped"
  # the image job-if loses its owner arm (the image push would stop on org-owned private repos)
  _mut image-job-if-narrowed "/^  image-provenance:\$/,\$s/ || github.event.repository.owner.type == 'Organization')/)/" "image job condition changed"
  # a notice under the wrong expression (it would print on public repos too)
  _mut notice-not-inverse "/Build provenance skipped (notice)/{n;s/vars.KIT_ATTEST_PRIVATE != 'true'/vars.KIT_ATTEST_PRIVATE == 'true'/;}" "notice not under the inverse expression"
  # an if: added to the image push step (the push would stop on a private org repo without the declaration), and a step added after the build notice (it is no longer the last step of the ci job)
  _mutawk() {  # <name> <awk-program> <expected>: ok.yml run through awk; must differ, and must FAIL
    awk "$2" "$d/ok.yml" > "$d/$1.yml"
    if cmp -s "$d/ok.yml" "$d/$1.yml"; then echo "selftest FAIL: mutant $1 — its anchor hit nothing, so it proves nothing"; sf=1; return 0; fi
    if check_file "$d/$1.yml" >/dev/null 2>&1; then echo "selftest FAIL: mutant $1 NOT caught ($3)"; sf=1; else echo "selftest PASS: mutant $1 -> FAIL ($3)"; fi
  }
  _mutawk push-step-gated '{ print } /name: Build and push image/ { print "        if: github.event_name == \"push\"" }' "an if: on the image push step"
  _mutawk build-notice-not-last '{ print } /::notice::Build provenance skipped/ { print "      - run: echo late" }' "a step after the build notice in the ci job"
  # the image attest step renamed (scripts/release-tag.sh finds it by its exact name, so a rename would blind the release-tag probe)
  _mutawk attest-step-renamed '{ sub(/Attest image provenance \(digest-bound\)/, "Attest image provenance"); print }' "image attest step name changed"
  # the removed advice reappears in a comment
  { cat "$d/ok.yml"; printf '# Make the repo public or %s to enable.\n' "$BANNED"; } > "$d/move-text.yml"
  if check_file "$d/move-text.yml" >/dev/null 2>&1; then echo "selftest FAIL: the banned owner-type cure NOT caught"; sf=1; else echo "selftest PASS: the banned owner-type cure -> FAIL"; fi
  # HALF-gated: provenance guarded, image-provenance NOT -> must FAIL (the reviewer's gap)
  {
    printf 'jobs:\n  provenance:\n'
    printf "    if: github.ref == 'refs/heads/main' && %s\n" "$JOB_IF_NEW"
    printf '    steps:\n      - uses: actions/attest-build-provenance@v1\n'
    printf '  image-provenance:\n'
    printf "    if: github.ref == 'refs/heads/main' && needs.ci.outputs.has_dockerfile == 'true'\n"
    printf '    steps:\n      - uses: actions/attest-build-provenance@v1\n'
  } > "$d/half.yml"
  _half_out=$(check_file "$d/half.yml" 2>&1) && _half_rc=0 || _half_rc=$?
  case "$_half_out" in
    *"the push-to-main job-if of 'image-provenance' is not the one the lock allows"*)
      if [ "$_half_rc" -ne 0 ]; then echo "selftest PASS: half-gated -> FAIL naming the image-provenance job-if (per-job-if enforcement)"; else echo "selftest FAIL: half-gated printed the FAIL text but returned 0"; sf=1; fi ;;
    *) echo "selftest FAIL: half-gated did not fail with the image-provenance job-if text (got: $_half_out)"; sf=1 ;;
  esac
  # no provenance job -> N/A
  printf 'jobs:\n  ci:\n    steps:\n      - run: echo hi\n' > "$d/na.yml"
  if check_file "$d/na.yml" >/dev/null 2>&1; then echo "selftest PASS: no provenance -> N/A"; else echo "selftest FAIL: N/A wrongly failed"; sf=1; fi
  rm -rf "$d"
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
if [ "$fail" -eq 0 ]; then echo "OK: every provenance job-if and step is gated on public-or-declared, and every skip says why"; exit 0; fi
echo "FAIL: an ungated or unannounced provenance job or step (see above) — would red a private repo's main on first merge"; exit 1
