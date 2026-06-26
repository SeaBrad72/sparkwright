#!/bin/sh
# orchestrator-trace-demo.sh — REFERENCE STAND-IN for the E3 orchestrator (E5-thin).
# Emits one representative orchestrator trace: a root span with three child spans
# (engineer, reviewer, and a guard-DENIED gate). This is the shape E3a will emit;
# E3a REPLACES this script's body with the real fan-out loop. Not a gate.
set -eu
here=$(dirname "$0")
emit() { sh "$here/otel-trace.sh" span "$@"; }

selftest() {
  out=$(mktemp)
  main --out "$out" >/dev/null
  st_fail=0
  [ "$(wc -l < "$out" | tr -d ' ')" = "4" ] || { echo "FAIL: expected 4 spans"; st_fail=1; }
  # exactly one root (null parent), three children
  [ "$(jq -s '[.[]|select(.parent_span_id==null)]|length' "$out")" = "1" ] || { echo "FAIL: not exactly 1 root"; st_fail=1; }
  # the denied span carries the kit.denied signal (the contract the adapter reads)
  [ "$(jq -s '[.[]|select(.attributes["kit.denied"]=="true")]|length' "$out")" = "1" ] || { echo "FAIL: no denied span"; st_fail=1; }
  rm -f "$out"
  [ "$st_fail" -eq 0 ] || { echo "orchestrator-trace-demo --selftest: FAIL" >&2; return 1; }
  echo "orchestrator-trace-demo --selftest: OK (root+3 children, one denied)"; return 0
}

main() {
  OUT=""
  while [ $# -gt 0 ]; do case "$1" in --out) OUT="$2"; shift 2;; *) shift;; esac; done
  tid=$(sh "$here/otel-trace.sh" new-trace)
  : "${OUT:=$(mktemp)}"
  : > "$OUT"
  export OTEL_TRACE_FILE="$OUT"
  root=$(emit --trace "$tid" --name orchestrator-run --status OK --attr "agent.id=orchestrator")
  emit --trace "$tid" --parent "$root" --name "agent:engineer" --status OK  --attr "agent.id=engineer" --attr "steps=4" >/dev/null
  emit --trace "$tid" --parent "$root" --name "agent:reviewer" --status OK  --attr "agent.id=reviewer" --attr "steps=2" >/dev/null
  # a guard-denied gate step — the non-vacuous signal the scorecard must reflect
  emit --trace "$tid" --parent "$root" --name "gate:guard"   --status ERROR --attr "agent.id=engineer" --attr "kit.denied=true" >/dev/null
  printf '%s\n' "$OUT"
}

case "${1:-}" in --selftest) selftest; exit $? ;; *) main "$@" ;; esac
