#!/bin/sh
# drift-watch-wired.sh — the drift-watcher must not itself drift. Asserts the scheduled D1b workflow
# exists, is actually scheduled (+ manually dispatchable), and runs the full drift payload
# (verify.sh + claims-registry.sh + check-links.sh). Catches the irony of the drift-watch silently
# rotting — e.g. someone drops a payload line or the schedule trigger.
#   sh conformance/drift-watch-wired.sh [--selftest]
# Exit: 0 = wired · 1 = missing / gutted · 2 = usage. POSIX sh; dash-clean.
set -eu

WF="${KIT_DRIFT_WF:-.github/workflows/drift-watch.yml}"
PAYLOAD="conformance/verify.sh conformance/claims-registry.sh conformance/check-links.sh"

check() {
  _wf=$1; f=0
  [ -f "$_wf" ] || { echo "FAIL: missing $_wf"; return 1; }
  grep -q '^[[:space:]]*schedule:' "$_wf" || { echo "FAIL: $_wf has no schedule: trigger"; f=1; }
  grep -q 'cron:' "$_wf"                  || { echo "FAIL: $_wf has no cron: schedule"; f=1; }
  grep -q 'workflow_dispatch:' "$_wf"     || { echo "FAIL: $_wf is not manually dispatchable"; f=1; }
  for _c in $PAYLOAD; do
    grep -q "$_c" "$_wf" || { echo "FAIL: $_wf does not run $_c"; f=1; }
  done
  [ "$f" -eq 0 ] && echo "PASS: drift-watch scheduled (+ dispatchable) and runs the full payload"
  return $f
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  d=$(mktemp -d)
  # GOOD fixture: schedule + cron + dispatch + all 3 payload checks
  {
    echo "on:"; echo "  schedule:"; echo "    - cron: '0 6 * * 1'"; echo "  workflow_dispatch:"
    echo "    - run: sh conformance/verify.sh --require"
    echo "    - run: sh conformance/claims-registry.sh"
    echo "    - run: sh conformance/check-links.sh"
  } > "$d/good.yml"
  if check "$d/good.yml" >/dev/null 2>&1; then echo "PASS: selftest — wired workflow passes"; else echo "FAIL: selftest — wired workflow wrongly rejected"; sfail=1; fi
  # GUTTED: drop the claims-registry payload line -> must FAIL
  grep -v 'claims-registry.sh' "$d/good.yml" > "$d/gut1.yml"
  if check "$d/gut1.yml" >/dev/null 2>&1; then echo "FAIL: selftest — dropped payload check not caught"; sfail=1; else echo "PASS: selftest — gutted payload detected"; fi
  # GUTTED: drop the schedule trigger -> must FAIL
  grep -v 'cron:' "$d/good.yml" | grep -v 'schedule:' > "$d/gut2.yml"
  if check "$d/gut2.yml" >/dev/null 2>&1; then echo "FAIL: selftest — missing schedule not caught"; sfail=1; else echo "PASS: selftest — missing schedule detected"; fi
  [ "$sfail" -eq 0 ] && { echo "OK: drift-watch-wired selftest"; exit 0; } || { echo "FAIL: drift-watch-wired selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: drift-watch-wired.sh [--selftest]" >&2; exit 2 ;;
esac

echo "Drift-watch wiring:"
if check "$WF"; then echo "OK: scheduled drift-watch is present + runs the payload"; exit 0; else echo "FAIL: drift-watch missing or gutted (see above)"; exit 1; fi
