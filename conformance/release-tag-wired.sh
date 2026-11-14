#!/bin/sh
# release-tag-wired.sh — locks the release-tag FLOOR + the OPT-IN forge reference bindings.
# The release-tag.sh decision logic (--selftest) is graded by its own verify row, release-tag-selftest (SWAS-420B).
# Locks (static): the GitHub reference (docs/operations/release-tag.github.yml — a copy-and-enable
#   auto-tag binding: push:main trigger, contents: write, invokes release-tag.sh, parses under
#   actionlint), the GitLab reference, and the doc all ship. The kit itself tags MANUALLY
#   (sh scripts/release-tag.sh after merge); the auto bindings are opt-in references, never live here.
# Mode-blind. Every asserted path SHIPS to adopters -> no kit-self N/A-skip, no carve.
#   usage: sh conformance/release-tag-wired.sh [--selftest]   exit 0 wired · 1 gap · 2 usage.
set -eu

check() {
  _root="${RELEASE_TAG_WIRED_ROOT:-.}"
  _core="$_root/scripts/release-tag.sh"
  _ghref="$_root/docs/operations/release-tag.github.yml"
  _gitlab="$_root/docs/operations/release-tag.gitlab-ci.yml"
  _doc="$_root/docs/operations/release-tag.md"
  rc=0
  [ -f "$_core" ] || { echo "FAIL: missing $_core"; return 1; }
  [ -f "$_ghref" ] || { echo "FAIL: missing GitHub reference $_ghref"; rc=1; }
  if [ -f "$_ghref" ]; then
    grep -q 'release-tag.sh' "$_ghref" || { echo "FAIL: $_ghref does not invoke release-tag.sh"; rc=1; }
    grep -Eq 'contents:[[:space:]]*write' "$_ghref" || { echo "FAIL: $_ghref lacks contents: write"; rc=1; }
    grep -Eq 'branches:[[:space:]]*\[[[:space:]]*main' "$_ghref" || { echo "FAIL: $_ghref not triggered on push to main"; rc=1; }
    if command -v actionlint >/dev/null 2>&1; then
      actionlint "$_ghref" >/dev/null 2>&1 || { echo "FAIL: $_ghref does not parse (actionlint)"; rc=1; }
    else
      echo "NOTE: actionlint absent — skipped parse-validation of $_ghref (not a pass of that sub-check)."
    fi
  fi
  { [ -f "$_gitlab" ] && grep -q 'release-tag.sh' "$_gitlab"; } || { echo "FAIL: missing/empty GitLab reference $_gitlab"; rc=1; }
  [ -f "$_doc" ] || { echo "FAIL: missing doc $_doc"; rc=1; }
  [ "$rc" = 0 ] && echo "release-tag-wired: OK (FLOOR present, its selftest graded by release-tag-selftest + opt-in GitHub/GitLab references + doc present)."
  return "$rc"
}

selftest() {
  st=0; d=$(mktemp -d)
  mkdir -p "$d/scripts" "$d/docs/operations"
  : > "$d/scripts/release-tag.sh"; chmod +x "$d/scripts/release-tag.sh"
  printf 'name: release-tag\non:\n  push:\n    branches: [main]\npermissions:\n  contents: write\njobs:\n  release-tag:\n    runs-on: ubuntu-latest\n    steps:\n      - run: sh scripts/release-tag.sh\n' > "$d/docs/operations/release-tag.github.yml"
  printf 'release-tag:\n  script:\n    - sh scripts/release-tag.sh\n' > "$d/docs/operations/release-tag.gitlab-ci.yml"
  printf 'doc\n' > "$d/docs/operations/release-tag.md"
  ( RELEASE_TAG_WIRED_ROOT="$d" check ) >/dev/null 2>&1 && g=0 || g=$?
  [ "$g" = 0 ] && echo "selftest PASS: complete fixture -> wired" || { echo "selftest FAIL: complete should pass (got $g)"; st=1; }
  # break: GitHub reference without contents: write -> FAIL (proves the reference is really checked)
  printf 'name: release-tag\non:\n  push:\n    branches: [main]\npermissions:\n  contents: read\njobs:\n  release-tag:\n    runs-on: ubuntu-latest\n    steps:\n      - run: sh scripts/release-tag.sh\n' > "$d/docs/operations/release-tag.github.yml"
  ( RELEASE_TAG_WIRED_ROOT="$d" check ) >/dev/null 2>&1 && g=0 || g=$?
  [ "$g" = 1 ] && echo "selftest PASS: no contents:write -> FAIL" || { echo "selftest FAIL: should fail (got $g)"; st=1; }
  # break: the release-tag.sh FLOOR itself missing -> FAIL (proves the presence check is real)
  rm -f "$d/scripts/release-tag.sh"
  ( RELEASE_TAG_WIRED_ROOT="$d" check ) >/dev/null 2>&1 && g=0 || g=$?
  [ "$g" = 1 ] && echo "selftest PASS: missing release-tag.sh -> FAIL" || { echo "selftest FAIL: missing core should fail (got $g)"; st=1; }
  rm -rf "$d"
  [ "$st" = 0 ] && echo "release-tag-wired --selftest: OK"
  return "$st"
}

case "${1:-}" in --selftest) selftest; exit $? ;; *) check ;; esac
