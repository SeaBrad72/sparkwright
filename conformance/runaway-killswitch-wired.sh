#!/bin/sh
# runaway-killswitch-wired.sh — E4d: the runaway circuit-breaker is installed + has teeth.
#
# Proves: scripts/runaway-guard.sh exists, is executable, and ENFORCES each ceiling
# (tokens / steps / agents), warns before breach, and fails closed on a bad config.
# A green run does NOT prove a hard LLM-API spend cap (platform-owned) or a tamper-proof
# tally (best-effort) — see docs/operations/runaway-killswitch.md. Necessary, not sufficient.
#
# Usage: sh conformance/runaway-killswitch-wired.sh [--require] | --selftest
set -eu
GUARD="scripts/runaway-guard.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

selftest() {
  [ -f "$GUARD" ] || fail "missing $GUARD"
  [ -x "$GUARD" ] || fail "$GUARD not executable"
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  cfg="$tmp/c"; tally="$tmp/t"
  mkcfg() { printf 'MAX_TOKENS=%s\nMAX_STEPS=%s\nMAX_AGENTS=%s\nWARN_PCT=%s\nCOST_PER_1K_USD=0.003\n' "$1" "$2" "$3" "$4" >"$cfg"; }
  R() { _c=$1; shift; sh "$GUARD" "$_c" --config "$cfg" --tally "$tally" "$@"; }   # subcommand-first; defaults before caller args so caller --config wins (last-wins; script reads subcommand as $1 BEFORE the option loop)
  expect() { _w=$1; shift; "$@" >/dev/null 2>&1 && _g=0 || _g=$?; [ "$_g" = "$_w" ] || fail "$_desc (want $_w, got $_g)"; }

  _desc="under-budget continues"; mkcfg 1000 10 5 80; : >"$tally"; expect 0 R step --tokens 100 --agents 1
  _desc="token breach stops";     mkcfg 1000 10 5 80; : >"$tally"; expect 1 R step --tokens 1000 --agents 0
  _desc="step breach stops";      mkcfg 999999 2 99 80; : >"$tally"; R step --tokens 1 --agents 0 >/dev/null 2>&1; expect 1 R step --tokens 1 --agents 0
  _desc="agent breach stops";     mkcfg 999999 99 2 80; : >"$tally"; expect 1 R step --tokens 1 --agents 2
  _desc="warn continues";         mkcfg 1000 10 5 80; : >"$tally"; expect 0 R step --tokens 800 --agents 1
  _desc="breach names the dim";   mkcfg 1000 10 5 80; : >"$tally"; case "$(R step --tokens 1000 --agents 0 2>&1 >/dev/null)" in *tokens*) : ;; *) fail "breach must name the dimension";; esac
  _desc="missing config -> 2";    expect 2 R check --config "$tmp/nope"
  _desc="malformed config -> 2";  printf 'MAX_TOKENS=x\n' >"$cfg"; expect 2 R check
  _desc="reset clears";           mkcfg 1000 10 5 80; : >"$tally"; R step --tokens 500 --agents 1 >/dev/null 2>&1; R reset --tally "$tally" >/dev/null 2>&1; expect 0 R check
  _desc="missing flag value -> 2"; mkcfg 1000 10 5 80; : >"$tally"; expect 2 R step --tokens
  _desc="empty flag value -> 2";   mkcfg 1000 10 5 80; : >"$tally"; expect 2 R step --tokens "" --agents 1
  echo "runaway-killswitch-wired: selftest OK"
}

case "${1:-}" in
  --selftest) selftest ;;
  --require|"") selftest ;;   # no project-state aspect; the teeth ARE the selftest
  *) echo "usage: runaway-killswitch-wired.sh [--require] | --selftest" >&2; exit 2 ;;
esac
