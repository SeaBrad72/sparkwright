#!/bin/sh
# adopter-export.sh — produce a clean adopter distribution of the kit via `git archive`
# (honors .gitattributes export-ignore; excludes gitignored scratch/node_modules automatically,
# since an archive contains only committed tracked files). Optionally prunes unused stack profiles.
#   sh scripts/adopter-export.sh <dest-dir> [--profile <stack>] [--selftest]
# Operates on committed HEAD. NEVER writes inside the kit repo. Exit: 0 ok · 1 runtime · 2 usage.
# POSIX sh; dash-clean.
set -eu

ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)

usage() { echo "usage: adopter-export.sh <dest-dir> [--profile <stack>] [--selftest]" >&2; exit 2; }

known_profiles() { ls -d "$ROOT"/profiles/*/ 2>/dev/null | sed 's#.*/profiles/##; s#/$##'; }

do_export() {  # <dest> <profile-or-empty>  — returns nonzero on bad dest/profile
  _dest=$1; _prof=${2:-}
  [ -n "$_dest" ] || { echo "adopter-export: missing dest" >&2; return 2; }
  if [ -e "$_dest" ] && [ -n "$(ls -A "$_dest" 2>/dev/null)" ]; then
    echo "adopter-export: dest '$_dest' exists and is not empty — refusing to clobber" >&2; return 1
  fi
  if [ -n "$_prof" ] && ! known_profiles | grep -qxF -- "$_prof"; then
    echo "adopter-export: unknown profile '$_prof' (known: $(known_profiles | tr '\n' ' '))" >&2; return 1
  fi
  mkdir -p "$_dest"
  # --worktree-attributes: honor the working-tree .gitattributes (so export-ignore applies even
  # before it is committed, and after a clean clone where worktree == HEAD). Archive content is HEAD.
  _ar=$(mktemp) || { echo "adopter-export: mktemp failed" >&2; return 1; }
  if ! ( cd "$ROOT" && git archive --worktree-attributes HEAD ) > "$_ar"; then
    echo "adopter-export: git archive failed (is '$ROOT' a git repo with a committed HEAD?)" >&2
    rm -f "$_ar"; return 1
  fi
  tar -x -C "$_dest" < "$_ar"
  rm -f "$_ar"
  # --- S3b: carve maintainer-only claims whose verified workflows are export-ignored ---
  # .github/workflows/{drift-watch,golden-path}.yml are export-ignored (maintainer-only CI), but
  # their claims + wired-checks ship; the claims' real-workflow verifiers would FAIL in the adopter's
  # claims-registry. Strip those claims from the adopter's COPY of claims.tsv + REQUIRED_IDS (the kit's
  # own registry is untouched). The wired-check scripts stay — their --selftest in the adopter ci.yml
  # is self-contained and passes. If a new maintainer-only workflow+claim is added without carving it,
  # conformance/adopter-export-wired.sh goes RED (it runs the adopter's full claims-registry).
  # adopter-export is ALSO carved: it is a kit-self check (an adopter has no reason to verify the kit's
  # OWN export mechanism), AND keeping it would recurse (claims-registry -> adopter-export-wired.sh ->
  # claims-registry -> ...). The kit still verifies adopter-export in its own CI.
  _ct="$_dest/conformance/claims.tsv"; _cr="$_dest/conformance/claims-registry.sh"
  if [ -f "$_ct" ] && [ -f "$_cr" ]; then
    _tab=$(printf '\t')
    for _c in drift-watch golden-path adopter-export feature-flags-wired containment-audit; do
      grep -v "^${_c}${_tab}" "$_ct" > "$_ct.$$.s3b" && mv "$_ct.$$.s3b" "$_ct"
      sed "s/ ${_c}\\([\"[:space:]]\\)/\\1/" "$_cr" > "$_cr.$$.s3b" && mv "$_cr.$$.s3b" "$_cr"
    done
  fi
  # R3/C2: the kit's root .gitignore ignores /src/ and /test/ (stray KIT dogfooding output); an
  # adopter puts product source there, so strip those two EXACT lines from the EXPORTED .gitignore
  # (the kit's own .gitignore is untouched). `grep -vx` matches whole lines only, so an adopter path
  # like `my/src/lib` or `/src/foo` is never clobbered. Idempotent.
  _gi="$_dest/.gitignore"
  if [ -f "$_gi" ]; then
    grep -vxE '/(src|test)/' "$_gi" > "$_gi.$$.r3c2" 2>/dev/null || true
    mv "$_gi.$$.r3c2" "$_gi"
  fi
  _pruned=0
  if [ -n "$_prof" ]; then
    for _p in $(known_profiles); do
      [ "$_p" = "$_prof" ] && continue
      if [ -d "$_dest/profiles/$_p" ]; then rm -rf "$_dest/profiles/$_p"; _pruned=$((_pruned + 1)); fi
      [ -f "$_dest/profiles/$_p.md" ] && rm -f "$_dest/profiles/$_p.md"
    done
    # docs/STACK-SELECTION.md links to every profiles/<stack>.md; after a single-profile prune
    # those 9 links dangle (check-links FAILS on the adopter's first push). Replace it with a stub
    # that links only to the KEPT selected profile, so the exported tree is link-clean. The file
    # still exists, so inbound links (README, START-HERE, the kept profile doc) stay valid.
    # Emit via printf with $_prof as a %s ARGUMENT (never interpreted) — closes any heredoc/sed
    # interpolation class even if a future profile dir name contained shell/regex metacharacters.
    if [ -f "$_dest/docs/STACK-SELECTION.md" ]; then
      {
        printf '# Stack selection\n\n'
        printf 'This export was created for the **%s** profile — see [the profile guide](../profiles/%s.md).\n\n' "$_prof" "$_prof"
        printf 'The full multi-stack comparison matrix lives in the upstream Sparkwright kit\n'
        printf '(`docs/STACK-SELECTION.md`); it is omitted here because the other stack profiles\n'
        printf 'are not included in a single-profile export.\n'
      } > "$_dest/docs/STACK-SELECTION.md"
    fi
  fi
  _src_n=$( ( cd "$ROOT" && git ls-files | wc -l ) | tr -d ' ' )
  _out_n=$(find "$_dest" -type f | wc -l | tr -d ' ')
  echo "adopter-export: exported $_out_n files to $_dest (kit HEAD tracked $_src_n; pruned $_pruned unused profile(s))"
  return 0
}

if [ "${1:-}" = "--selftest" ]; then
  fail=0
  _t=$(mktemp -d)
  _d="$_t/exp"
  do_export "$_d" typescript-node >/dev/null || { echo "FAIL: export errored"; fail=1; }
  # export-ignored → ABSENT
  for p in docs/ROADMAP-KIT.md .github/workflows/golden-path.yml .github/workflows/drift-watch.yml; do
    [ -e "$_d/$p" ] && { echo "FAIL: export-ignored path present: $p"; fail=1; } || echo "PASS: absent $p"
  done
  # kept → PRESENT (scripts/fixtures now SHIPS — the tier-advice/agent-scorecard selftests in the
  # adopter ci.yml depend on scripts/fixtures/scorecard/)
  for p in MAINTAINING.md CHANGELOG.md WALKTHROUGH.md conformance templates profiles/_TEMPLATE.md profiles/typescript-node scripts/fixtures/scorecard; do
    [ -e "$_d/$p" ] && echo "PASS: present $p" || { echo "FAIL: kept path missing: $p"; fail=1; }
  done
  # STACK-SELECTION stubbed on --profile: exists + no link to a pruned profile (e.g. go)
  if [ -f "$_d/docs/STACK-SELECTION.md" ] && ! grep -Fq '](../profiles/go.md)' "$_d/docs/STACK-SELECTION.md"; then
    echo "PASS: STACK-SELECTION stubbed (no pruned-profile link)"
  else echo "FAIL: STACK-SELECTION still links a pruned profile (or missing)"; fail=1; fi
  # R3/C2: the exported .gitignore must NOT ignore /src/ or /test/ (an adopter's source goes there)
  if grep -qxE '/(src|test)/' "$_d/.gitignore" 2>/dev/null; then
    echo "FAIL: exported .gitignore still ignores /src/ or /test/ (adopter source un-committable)"; fail=1
  else echo "PASS: exported .gitignore does not ignore /src/ or /test/"; fi
  # S3b: the maintainer-only claims are carved from the export's registry copies
  # (feature-flags-wired is kit-self: it greps the export-ignored golden-path.yml — E2)
  for p in drift-watch golden-path adopter-export feature-flags-wired containment-audit; do
    if grep -q "^$p$(printf '\t')" "$_d/conformance/claims.tsv"; then echo "FAIL: claim $p not carved from claims.tsv"; fail=1
    else echo "PASS: $p carved from claims.tsv"; fi
    if grep -qE '[" ]'"$p"'[ "]' "$_d/conformance/claims-registry.sh"; then echo "FAIL: $p not carved from REQUIRED_IDS"; fail=1
    else echo "PASS: $p carved from REQUIRED_IDS"; fi
  done
  # pruned profile → ABSENT
  [ -e "$_d/profiles/go" ] && { echo "FAIL: pruned profile present: go"; fail=1; } || echo "PASS: pruned profiles/go"
  [ -e "$_d/profiles/go.md" ] && { echo "FAIL: pruned profile doc present: go.md"; fail=1; } || echo "PASS: pruned profiles/go.md"
  # R3/C2 bare-export path: export WITHOUT a profile arg must also strip /src/ and /test/
  _d2="$_t/exp2"
  do_export "$_d2" >/dev/null 2>&1 || { echo "FAIL: bare export errored"; fail=1; }
  if grep -qxE '/(src|test)/' "$_d2/.gitignore" 2>/dev/null; then
    echo "FAIL: bare-export .gitignore still ignores /src/ or /test/"; fail=1
  else echo "PASS: bare-export .gitignore clean"; fi
  # unknown profile → nonzero
  if ( do_export "$_t/exp3" nonsuch >/dev/null 2>&1 ); then echo "FAIL: unknown profile accepted"; fail=1; else echo "PASS: unknown profile rejected"; fi
  # non-empty dest → nonzero
  mkdir -p "$_t/full"; : > "$_t/full/x"
  if ( do_export "$_t/full" >/dev/null 2>&1 ); then echo "FAIL: non-empty dest accepted"; fail=1; else echo "PASS: non-empty dest rejected"; fi
  # exactly one stack profile dir remains
  _np=$(find "$_d/profiles" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
  [ "$_np" = "1" ] && echo "PASS: exactly one stack profile dir remains" || { echo "FAIL: $_np profile dirs remain (expected 1)"; fail=1; }
  # export is non-empty
  _tot=$(find "$_d" -type f | wc -l | tr -d ' ')
  [ "$_tot" -gt 0 ] && echo "PASS: export non-empty ($_tot files)" || { echo "FAIL: export empty"; fail=1; }
  rm -rf "$_t"
  [ "$fail" -eq 0 ] && { echo "OK: adopter-export selftest"; exit 0; } || { echo "FAIL: adopter-export selftest"; exit 1; }
fi

# — main —
DEST=""; PROFILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) [ $# -ge 2 ] || usage; PROFILE=$2; [ -n "$PROFILE" ] || { echo "adopter-export: --profile requires a non-empty stack name" >&2; usage; }; shift 2 ;;
    -h|--help) usage ;;
    --*) echo "adopter-export: unknown flag $1" >&2; usage ;;
    *) [ -z "$DEST" ] || usage; DEST=$1; shift ;;
  esac
done
[ -n "$DEST" ] || usage
do_export "$DEST" "$PROFILE"
