#!/bin/sh
# author-not-approver-wired.sh — locks the E4e separation-of-duties FLOOR+NATIVE wiring.
# Proves (behaviour): scripts/sod-check.sh --selftest passes (the neutral logic).
# Locks (static): the contract doc, the GitHub reference workflow (wires sod-check.sh +
#   parses under actionlint when available), and the GitLab native-rule pointer all ship.
# Mode-blind (reads no process mode). No export-carve (all paths ship to adopters).
#   usage: sh conformance/author-not-approver-wired.sh [--selftest]
#   exit 0 = wired · 1 = a gap · 2 = bad usage. POSIX sh; dash-clean.
set -eu

ROOT="${SOD_WIRED_ROOT:-.}"
CORE="$ROOT/scripts/sod-check.sh"
DOC="$ROOT/docs/operations/separation-of-duties.md"
WF="$ROOT/docs/operations/sod-gate.github.yml"
GITLAB="$ROOT/docs/operations/gitlab-adoption.md"

check() {
  rc=0
  [ -f "$CORE" ] || { echo "FAIL: missing $CORE"; return 1; }
  sh "$CORE" --selftest >/dev/null 2>&1 || { echo "FAIL: sod-check.sh --selftest did not pass"; rc=1; }
  [ -f "$DOC" ] || { echo "FAIL: missing contract doc $DOC"; rc=1; }
  [ -f "$WF" ] || { echo "FAIL: missing reference workflow $WF"; rc=1; }
  if [ -f "$WF" ]; then
    grep -q 'sod-check.sh' "$WF" || { echo "FAIL: reference workflow does not invoke sod-check.sh"; rc=1; }
    if command -v actionlint >/dev/null 2>&1; then
      actionlint "$WF" >/dev/null 2>&1 || { echo "FAIL: reference workflow does not parse (actionlint)"; rc=1; }
    else
      echo "NOTE: actionlint absent — skipped parse-validation of $WF (not a pass of that sub-check)."
    fi
  fi
  if [ -f "$GITLAB" ]; then
    grep -q 'Prevent approval by author' "$GITLAB" || { echo "FAIL: gitlab-adoption.md missing the native SoD-rule pointer"; rc=1; }
  else
    echo "FAIL: gitlab-adoption.md missing the native SoD-rule pointer"
    rc=1
  fi
  [ "$rc" = 0 ] && echo "author-not-approver-wired: OK (FLOOR proven + GitHub/GitLab bindings present)."
  return "$rc"
}

selftest() {
  st=0
  d=$(mktemp -d)
  mkdir -p "$d/scripts" "$d/docs/operations"
  # a stub core that passes --selftest (the real logic is proven by sod-check's own --selftest in CI)
  # shellcheck disable=SC2016
  printf '#!/bin/sh\n[ "$1" = "--selftest" ] && { echo OK; exit 0; }\nexit 0\n' > "$d/scripts/sod-check.sh"
  chmod +x "$d/scripts/sod-check.sh"
  printf 'contract\n' > "$d/docs/operations/separation-of-duties.md"
  printf 'on: push\njobs:\n  x:\n    runs-on: ubuntu-latest\n    steps:\n      - run: sh scripts/sod-check.sh --require\n' > "$d/docs/operations/sod-gate.github.yml"
  printf 'Prevent approval by author\n' > "$d/docs/operations/gitlab-adoption.md"
  ( cd "$d" && SOD_WIRED_ROOT="$d" check ) >/dev/null 2>&1 && g=0 || g=$?
  if [ "$g" = 0 ]; then echo "selftest PASS: complete fixture -> wired"; else echo "selftest FAIL: complete fixture should pass (got $g)"; st=1; fi
  rm -f "$d/docs/operations/separation-of-duties.md"
  ( cd "$d" && SOD_WIRED_ROOT="$d" check ) >/dev/null 2>&1 && g=0 || g=$?
  if [ "$g" = 1 ]; then echo "selftest PASS: missing doc -> FAIL"; else echo "selftest FAIL: missing doc should fail (got $g)"; st=1; fi
  printf 'contract\n' > "$d/docs/operations/separation-of-duties.md"
  printf 'on: push\njobs:\n  x:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo hi\n' > "$d/docs/operations/sod-gate.github.yml"
  ( cd "$d" && SOD_WIRED_ROOT="$d" check ) >/dev/null 2>&1 && g=0 || g=$?
  if [ "$g" = 1 ]; then echo "selftest PASS: unwired workflow -> FAIL"; else echo "selftest FAIL: unwired workflow should fail (got $g)"; st=1; fi
  rm -rf "$d"
  [ "$st" = 0 ] && echo "author-not-approver-wired --selftest: OK"
  return "$st"
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *) check ;;
esac
