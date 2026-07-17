#!/bin/sh
# verify-enforced-wired.sh — assert ci.yml ENFORCES the aggregate (runs verify.sh --require), not just
# the renderer (--selftest). Closes the per-PR control-enforcement gap durably: a future edit reverting
# ci.yml to --selftest-only fails this lock (T4-B1).
#   usage: sh conformance/verify-enforced-wired.sh [--selftest]
# Exit: 0 = real enforcing call present · 1 = renderer-only / missing · POSIX sh; dash-clean.
set -eu
CI_WF="${VERIFY_ENFORCED_WF:-.github/workflows/ci.yml}"

# enforcing_present <file>: 0 iff a REAL (uncommented, unsuppressed) `run:` step invokes
# verify.sh --require. Comments — whole-line AND trailing `# …` — and a `… || true`-suppressed call do
# NOT count, so the lock fails when enforcement is actually gone. (Assumes a single-line `run:`
# invocation; a block-scalar refactor would fail SAFE/over-strict — prompting a lock update, never a
# false pass.)
enforcing_present() {
  grep -vE '^[[:space:]]*#' "$1" \
    | grep -E '^[[:space:]]*run:[[:space:]].*conformance/verify\.sh' \
    | sed 's/#.*//' \
    | grep -- '--require' \
    | grep -vq '|| true'
}

# _wf_disposition <wf_exists:0|1> <must_have:0|1> -> RUN | NA | FAIL  (P0-FU — mirrors proportional-gate-wired.sh)
# ci.yml is export-ignored: incept installs profiles/<stack>/ci.yml, so a PRE-INCEPT export has no
# workflow to enforce yet. But a tree that MUST have it (incepted adopter OR the kit repo) missing its
# ci.yml is a real regression. By ARGUMENTS, never env (an env-redirectable control-plane path is the
# vacuity we forbid). Fail-CLOSED: the only silent path (NA) requires BOTH "no workflow" AND "raw export".
_wf_disposition() {
  [ "$1" = 1 ] && { echo RUN; return; }
  [ "$2" = 1 ] && { echo FAIL; return; }
  echo NA
}
# _must_have_workflow [root] -> 1 iff incepted adopter (ENGINEERING-PRINCIPLES.md) OR the kit repo (kit-only
# markers; golden-path.yml is control-plane + export-ignored, un-spoofable). A raw export has none -> 0.
# Parameterized on <root> (default cwd) so the selftest can lock both branches against fixtures (a marker
# rename returning 0 on an incepted tree would fail-OPEN the gate to a silent NA — that must fail a test).
_must_have_workflow() {
  _mhr=${1:-.}
  { [ -f "$_mhr/ENGINEERING-PRINCIPLES.md" ] || [ -f "$_mhr/docs/ROADMAP-KIT.md" ] || [ -f "$_mhr/.github/workflows/golden-path.yml" ]; } \
    && echo 1 || echo 0
}

if [ "${1:-}" = "--selftest" ]; then
  d=$(mktemp -d); st=0
  # P0-FU disposition (by arguments; load-bearing — always-RUN reddens the raw-export case, always-NA greens incepted):
  [ "$(_wf_disposition 1 0)" = RUN ]  || { echo "FAIL: disposition — ci.yml present must RUN"; st=1; }
  [ "$(_wf_disposition 1 1)" = RUN ]  || { echo "FAIL: disposition — ci.yml present (must-have) must RUN"; st=1; }
  [ "$(_wf_disposition 0 0)" = NA ]   || { echo "FAIL: disposition — raw pre-incept export must be N/A"; st=1; }
  [ "$(_wf_disposition 0 1)" = FAIL ] || { echo "FAIL: disposition — kit/incepted tree missing ci.yml must FAIL (fail-closed)"; st=1; }
  # Lock the marker-detection half too (a rename returning 0 on an incepted tree would fail-OPEN to NA):
  _mh=$(mktemp -d)
  [ "$(_must_have_workflow "$_mh")" = 0 ] || { echo "FAIL: _must_have_workflow — markerless tree (raw export) must be 0"; st=1; }
  for _mk in ENGINEERING-PRINCIPLES.md docs/ROADMAP-KIT.md .github/workflows/golden-path.yml; do
    mkdir -p "$_mh/$(dirname "$_mk")"; : > "$_mh/$_mk"
    [ "$(_must_have_workflow "$_mh")" = 1 ] || { echo "FAIL: _must_have_workflow — marker '$_mk' present must be 1 (fail-closed)"; st=1; }
    rm -f "$_mh/$_mk"
  done
  rm -rf "$_mh" 2>/dev/null || true
  printf '      - name: enforce\n        run: sh conformance/verify.sh --require\n      - name: render\n        run: sh conformance/verify.sh --selftest\n' > "$d/ok.yml"
  printf '      - name: render only\n        run: sh conformance/verify.sh --selftest\n' > "$d/bad.yml"
  printf '# historical: we used to run sh conformance/verify.sh --require here\n        run: sh conformance/verify.sh --selftest\n' > "$d/comment.yml"
  printf '      - name: suppressed\n        run: sh conformance/verify.sh --require || true\n' > "$d/suppressed.yml"
  printf '      - name: trailing\n        run: sh conformance/verify.sh --selftest  # not --require\n' > "$d/trailing.yml"
  enforcing_present "$d/ok.yml"         || { echo "FAIL: selftest — real enforcing step missed"; st=1; }
  enforcing_present "$d/bad.yml"        && { echo "FAIL: selftest — selftest-only wrongly passed"; st=1; }
  enforcing_present "$d/comment.yml"    && { echo "FAIL: selftest — commented --require wrongly passed"; st=1; }
  enforcing_present "$d/suppressed.yml" && { echo "FAIL: selftest — '|| true'-suppressed --require wrongly passed"; st=1; }
  enforcing_present "$d/trailing.yml"   && { echo "FAIL: selftest — trailing-comment --require wrongly passed"; st=1; }
  if [ "$st" = 0 ]; then echo "OK: verify-enforced-wired selftest (comment + '|| true' bypasses rejected)"; exit 0; fi
  exit 1
fi

case "$(_wf_disposition "$([ -f "$CI_WF" ] && echo 1 || echo 0)" "$(_must_have_workflow)")" in
  NA)   echo "N/A: verify-enforced — pre-incept export (incept installs $CI_WF; nothing to enforce yet)"; exit 0 ;;
  FAIL) echo "FAIL: ci workflow not found in a kit/incepted tree: $CI_WF"; exit 1 ;;
esac
if enforcing_present "$CI_WF"; then
  echo "OK: ci.yml enforces the conformance aggregate (real 'verify.sh --require' run step)"; exit 0
fi
echo "FAIL: ci.yml does not run a real 'verify.sh --require' step — the aggregate is renderer-only (--selftest)"; exit 1
