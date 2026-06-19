#!/bin/sh
# named-adapters.sh — regression-lock: every shipped named third-party adapter
# (codex, cursor, gemini) conforms to the boundary contract. COMPOSES
# conformance/harness-adapter.sh against each adapters/<h>/ — never reimplements it.
# THREE-STATE: 0 ok . 1 a named adapter is missing/non-conformant . 2 UNVERIFIED
# (jq absent); 2 escalates to 1 under CI/--require. POSIX sh; dash-clean. Run from repo root.
#   sh conformance/named-adapters.sh [--require] | --selftest
set -eu

REQUIRE="${REQUIRE:-0}"
[ -n "${CI:-}" ] && REQUIRE=1
ADAPTERS_DIR="${KIT_ADAPTERS_DIR:-adapters}"
NAMED="codex cursor gemini"
MODE="run"
while [ $# -gt 0 ]; do
  case "$1" in
    --require)  REQUIRE=1; shift ;;
    --selftest) MODE="selftest"; shift ;;
    *)          echo "usage: named-adapters.sh [--require] | --selftest" >&2; exit 2 ;;
  esac
done

unverifiable() {
  if [ "$REQUIRE" = "1" ]; then echo "FAIL: named-adapters could not verify ($1) — required (CI/--require)."; exit 1; fi
  echo "UNVERIFIED: $1 — (NOT a pass)."; exit 2
}

check_named() {
  _dir=$1; _fail=0
  command -v jq >/dev/null 2>&1 || unverifiable "jq not installed (manifests are JSON)"
  for _h in $NAMED; do
    _a="$_dir/$_h"
    if [ ! -d "$_a" ]; then echo "FAIL: named adapter missing: $_a"; _fail=1; continue; fi
    if sh conformance/harness-adapter.sh "$_a" >/dev/null 2>&1; then
      echo "PASS: $_h adapter conforms to the boundary contract"
    else
      echo "FAIL: $_h adapter does NOT conform (run: sh conformance/harness-adapter.sh $_a)"; _fail=1
    fi
  done
  return $_fail
}

selftest() {
  st=0
  base=$(mktemp -d)   # fixtures left in place (no rm; control-plane guard blocks recursive rm)
  mkad() { mkdir -p "$1"; printf '%s\n' "$2" > "$1/adapter.json"; }
  VALID='{"harness":"FX","controlPlanePaths":[".github/workflows/","AGENTS.md"],"bindingFiles":["AGENTS.md"],"dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"review-roles":{"level":"floor"},"mcp-gate":{"level":"n-a"}}}'
  MALFORMED='{"harness":"FX","controlPlanePaths":[".github/workflows/","AGENTS.md"],"bindingFiles":["AGENTS.md"],"dimensions":{"context-binding":{"level":"floor"},"command-guard":{"level":"floor"},"history-protection":{"level":"floor"},"mcp-gate":{"level":"n-a"}}}'

  # OK fixture: all three valid -> exit 0
  for h in codex cursor gemini; do mkad "$base/ok/$h" "$VALID"; done
  ( KIT_ADAPTERS_DIR="$base/ok" sh "$0" ) >/dev/null 2>&1 && g=0 || g=$?
  if [ "$g" = "0" ]; then echo "selftest PASS: all-conformant -> 0"; else echo "selftest FAIL: ok want 0 got $g"; st=1; fi

  # GAP fixture: cursor missing the review-roles dimension -> exit 1
  mkad "$base/gap/codex" "$VALID"; mkad "$base/gap/cursor" "$MALFORMED"; mkad "$base/gap/gemini" "$VALID"
  ( KIT_ADAPTERS_DIR="$base/gap" sh "$0" ) >/dev/null 2>&1 && g=0 || g=$?
  if [ "$g" = "1" ]; then echo "selftest PASS: malformed cursor detected -> 1"; else echo "selftest FAIL: gap want 1 got $g"; st=1; fi

  # MISSING fixture: gemini absent -> exit 1
  mkad "$base/missing/codex" "$VALID"; mkad "$base/missing/cursor" "$VALID"
  ( KIT_ADAPTERS_DIR="$base/missing" sh "$0" ) >/dev/null 2>&1 && g=0 || g=$?
  if [ "$g" = "1" ]; then echo "selftest PASS: missing gemini detected -> 1"; else echo "selftest FAIL: missing want 1 got $g"; st=1; fi

  [ "$st" = "0" ] && { echo "named-adapters --selftest: OK"; return 0; }
  echo "named-adapters --selftest: FAIL"; return 1
}

case "$MODE" in
  selftest) selftest; exit $? ;;
  *) echo "Named-adapters check (dir: $ADAPTERS_DIR):"
     if check_named "$ADAPTERS_DIR"; then echo "OK: named codex/cursor/gemini adapters conform to the boundary contract"; exit 0; fi
     echo "named-adapters: FAIL (see above)"; exit 1 ;;
esac
