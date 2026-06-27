#!/bin/sh
# release-tag-wired.sh — locks the auto-tag-on-merge FLOOR+NATIVE wiring.
# Proves (behaviour): scripts/release-tag.sh --selftest passes (the neutral decision logic).
# Locks (static): the GitHub binding (.github/workflows/release-tag.yml — push:main trigger,
#   contents: write, invokes release-tag.sh, parses under actionlint), the GitLab reference
#   binding, and the doc all ship. Mode-blind. Kit-self N/A-skip outside the kit repo.
#   usage: sh conformance/release-tag-wired.sh [--selftest]   exit 0 wired · 1 gap · 2 usage.
set -eu
ROOT="${RELEASE_TAG_WIRED_ROOT:-.}"
WF="$ROOT/.github/workflows/release-tag.yml"  # used by the kit-self N/A-skip below; check() re-derives its own

check() {
  # Re-derive paths so the function works correctly when called from a subshell
  # that re-sets RELEASE_TAG_WIRED_ROOT (e.g. in --selftest fixtures).
  _root="${RELEASE_TAG_WIRED_ROOT:-.}"
  _core="$_root/scripts/release-tag.sh"
  _wf="$_root/.github/workflows/release-tag.yml"
  _gitlab="$_root/docs/operations/release-tag.gitlab-ci.yml"
  _doc="$_root/docs/operations/release-tag.md"
  rc=0
  [ -f "$_core" ] || { echo "FAIL: missing $_core"; return 1; }
  sh "$_core" --selftest >/dev/null 2>&1 || { echo "FAIL: release-tag.sh --selftest did not pass"; rc=1; }
  [ -f "$_wf" ] || { echo "FAIL: missing GitHub binding $_wf"; rc=1; }
  if [ -f "$_wf" ]; then
    grep -q 'release-tag.sh' "$_wf" || { echo "FAIL: $_wf does not invoke release-tag.sh"; rc=1; }
    grep -Eq 'contents:[[:space:]]*write' "$_wf" || { echo "FAIL: $_wf lacks contents: write"; rc=1; }
    grep -Eq 'branches:[[:space:]]*\[[[:space:]]*main' "$_wf" || { echo "FAIL: $_wf not triggered on push to main"; rc=1; }
    if command -v actionlint >/dev/null 2>&1; then
      actionlint "$_wf" >/dev/null 2>&1 || { echo "FAIL: $_wf does not parse (actionlint)"; rc=1; }
    else
      echo "NOTE: actionlint absent — skipped parse-validation of $_wf (not a pass of that sub-check)."
    fi
  fi
  { [ -f "$_gitlab" ] && grep -q 'release-tag.sh' "$_gitlab"; } || { echo "FAIL: missing/empty GitLab reference $_gitlab"; rc=1; }
  [ -f "$_doc" ] || { echo "FAIL: missing doc $_doc"; rc=1; }
  [ "$rc" = 0 ] && echo "release-tag-wired: OK (FLOOR proven + GitHub/GitLab bindings + doc present)."
  return "$rc"
}

selftest() {
  st=0; d=$(mktemp -d)
  mkdir -p "$d/scripts" "$d/.github/workflows" "$d/docs/operations"
  # shellcheck disable=SC2016
  printf '#!/bin/sh\n[ "$1" = "--selftest" ] && { echo OK; exit 0; }\nexit 0\n' > "$d/scripts/release-tag.sh"; chmod +x "$d/scripts/release-tag.sh"
  printf 'name: release-tag\non:\n  push:\n    branches: [main]\npermissions:\n  contents: write\njobs:\n  release-tag:\n    runs-on: ubuntu-latest\n    steps:\n      - run: sh scripts/release-tag.sh\n' > "$d/.github/workflows/release-tag.yml"
  printf 'release-tag:\n  script:\n    - sh scripts/release-tag.sh\n' > "$d/docs/operations/release-tag.gitlab-ci.yml"
  printf 'doc\n' > "$d/docs/operations/release-tag.md"
  ( RELEASE_TAG_WIRED_ROOT="$d" check ) >/dev/null 2>&1 && g=0 || g=$?
  [ "$g" = 0 ] && echo "selftest PASS: complete fixture -> wired" || { echo "selftest FAIL: complete should pass (got $g)"; st=1; }
  # break: workflow without contents: write -> FAIL
  printf 'name: release-tag\non:\n  push:\n    branches: [main]\npermissions:\n  contents: read\njobs:\n  release-tag:\n    runs-on: ubuntu-latest\n    steps:\n      - run: sh scripts/release-tag.sh\n' > "$d/.github/workflows/release-tag.yml"
  ( RELEASE_TAG_WIRED_ROOT="$d" check ) >/dev/null 2>&1 && g=0 || g=$?
  [ "$g" = 1 ] && echo "selftest PASS: no contents:write -> FAIL" || { echo "selftest FAIL: should fail (got $g)"; st=1; }
  rm -rf "$d"
  [ "$st" = 0 ] && echo "release-tag-wired --selftest: OK"
  return "$st"
}

# Kit-self N/A-skip: outside the kit repo (no ROADMAP-KIT.md) AND no workflow present -> N/A.
if [ "${1:-}" != "--selftest" ]; then
  if [ ! -f "$ROOT/docs/ROADMAP-KIT.md" ] && [ ! -f "$WF" ]; then
    echo "release-tag-wired: N/A — kit-self check (not applicable outside the kit repo)"; exit 0
  fi
fi
case "${1:-}" in --selftest) selftest; exit $? ;; *) check ;; esac
