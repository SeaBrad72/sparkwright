#!/bin/sh
# ci-selftest-coverage.sh — every selftest-capable kit check has its `--selftest` wired into CI.
# Closes the drift class where a conformance script ships a `--selftest` but is never referenced
# in .github/workflows/ci.yml, so a regression in that CHECKER'S OWN LOGIC would never be caught
# on push. This regression-locks the checker's logic; it does NOT by itself prove the checker's
# verdict runs against the kit repo — that is the check's own real-path CI step (or a Review/Manual
# row; see conformance/README.md). Scans the kit's own checks (conformance/*.sh, scripts/*.sh,
# hooks/pre-push); any that support `--selftest` MUST be referenced by basename in ci.yml.
# Fail-closed: lists every unwired check.
#
# Self-exclusion: this script excludes ITSELF from the scan. Its own presence in ci.yml is a
# one-time maintainer bootstrap (a meta-check can't non-circularly verify its own wiring); if it
# were not in ci.yml, nothing here would run on push anyway, so the point is moot. See
# conformance/README.md.
#   sh conformance/ci-selftest-coverage.sh [--selftest]
# Exit: 0 = all wired · 1 = an unwired selftest-capable check · 2 = bad usage. POSIX sh; dash-clean.
set -eu
cd "$(dirname "$0")/.."

CI_FILE="${KIT_CI_FILE:-.github/workflows/ci.yml}"
SELF=ci-selftest-coverage.sh

# scan <ci_file> <file>...: for each file that contains "--selftest" (and is not SELF), assert its
# basename appears in <ci_file>. Prints WIRED/UNWIRED per file; returns 1 if any is unwired.
scan() {
  _ci=$1; shift
  _miss=0
  for f in "$@"; do
    [ -f "$f" ] || continue
    _base=$(basename "$f")
    [ "$_base" = "$SELF" ] && continue
    # "Ships a --selftest" means it HANDLES the flag, not merely mentions it: strip comments
    # first, so a doc comment like "(no --selftest)" in a sourced helper isn't miscounted.
    sed 's/#.*//' "$f" | grep -q -- '--selftest' || continue
    # "Wired" means the basename appears in an EXECUTION context, not merely mentioned: strip
    # comments and `name:` label lines first, so a step titled after a script (or a commented-out
    # step) is never mistaken for one that actually runs it.
    if sed 's/#.*//' "$_ci" 2>/dev/null | grep -vE '^[[:space:]]*-?[[:space:]]*name:' | grep -Fq "$_base"; then
      echo "WIRED:   $_base"
    else
      echo "UNWIRED: $_base"; _miss=1
    fi
  done
  return $_miss
}

run() {
  [ -f "$CI_FILE" ] || { echo "ci-selftest-coverage: CI file not found ($CI_FILE)"; return 1; }
  if scan "$CI_FILE" conformance/*.sh scripts/*.sh hooks/pre-push; then
    echo "ci-selftest-coverage: OK (every selftest-capable check is wired into CI; self-excluded)"
    return 0
  fi
  echo "ci-selftest-coverage: FAIL — the UNWIRED check(s) above ship a --selftest but are absent"
  echo "  from $CI_FILE. Add a CI step that runs each (e.g. 'sh conformance/<name>.sh --selftest')."
  return 1
}

selftest() {
  sfail=0
  d=$(mktemp -d)
  printf '#!/bin/sh\necho run --selftest\n' > "$d/foo-check.sh"
  printf '#!/bin/sh\necho run --selftest\n' > "$d/bar-check.sh"
  printf '#!/bin/sh\necho no flag here\n'    > "$d/plain.sh"
  # dirty: foo wired, bar NOT -> must FAIL naming bar
  printf 'jobs:\n  x:\n    steps:\n      - run: sh conformance/foo-check.sh --selftest\n' > "$d/ci-bad.yml"
  if scan "$d/ci-bad.yml" "$d/foo-check.sh" "$d/bar-check.sh" >/dev/null 2>&1; then
    echo "FAIL: selftest — unwired check not detected"; sfail=1
  else
    echo "PASS: selftest — unwired check detected"
  fi
  # clean: both wired -> must PASS
  printf 'jobs:\n  x:\n    steps:\n      - run: sh foo-check.sh\n      - run: sh bar-check.sh\n' > "$d/ci-ok.yml"
  if scan "$d/ci-ok.yml" "$d/foo-check.sh" "$d/bar-check.sh" >/dev/null 2>&1; then
    echo "PASS: selftest — all-wired passes"
  else
    echo "FAIL: selftest — all-wired wrongly failed"; sfail=1
  fi
  # a script WITHOUT --selftest is ignored (not required in ci)
  if scan "$d/ci-ok.yml" "$d/plain.sh" >/dev/null 2>&1; then
    echo "PASS: selftest — non-selftest script ignored"
  else
    echo "FAIL: selftest — non-selftest script wrongly required"; sfail=1
  fi
  echo "ci-selftest-coverage --selftest: fixtures left in $d"
  [ "$sfail" -eq 0 ] && { echo "OK: ci-selftest-coverage selftest"; exit 0; } || { echo "FAIL: ci-selftest-coverage selftest"; exit 1; }
}

case "${1:-}" in
  --selftest) selftest ;;
  "")
    # Kit-repo detector (C1 / R3): this check only has meaning inside the kit's own repo.
    # OR-of-markers is fail-closed: golden-path.yml is control-plane + export-ignored (un-spoofable);
    # deleting only the unprotected ROADMAP-KIT.md marker cannot make the kit skip its own checks.
    # N/A-skip only when BOTH are absent (true adopter tree). When either is present, run full.
    if [ ! -f "docs/ROADMAP-KIT.md" ] && [ ! -f ".github/workflows/golden-path.yml" ]; then
      echo "ci-selftest-coverage: N/A — kit-self check (not applicable outside the kit repo)"; exit 0
    fi
    run ;;
  *)          echo "usage: ci-selftest-coverage.sh [--selftest]" >&2; exit 2 ;;
esac
exit $?
