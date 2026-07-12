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

if [ "${1:-}" = "--selftest" ]; then
  d=$(mktemp -d); st=0
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

[ -f "$CI_WF" ] || { echo "FAIL: ci workflow not found: $CI_WF"; exit 1; }
if enforcing_present "$CI_WF"; then
  echo "OK: ci.yml enforces the conformance aggregate (real 'verify.sh --require' run step)"; exit 0
fi
echo "FAIL: ci.yml does not run a real 'verify.sh --require' step — the aggregate is renderer-only (--selftest)"; exit 1
