#!/bin/sh
# model-tiering-plan-wired.sh — KW20(b) Slice 2a: the model-tier decision discipline is WIRED into the
# neutral surfaces (TCC carries a Model-tier field; skills/plan prescribes surfacing a per-task tier for
# human approval; the Orchestrator agent resolves+surfaces+dispatches it).
# SCOPE — proves the discipline + contract field are DOCUMENTED/wired; NOT that any Build Plan obeyed it
# (declared != obeyed — same ceiling as the skill-spine lock + the TCC template), and NOT that a harness
# bound a model (Slice 2b / NATIVE, un-gateable). Necessary, not sufficient.
# What it changes: read-only — greps three tracked docs for the wiring markers; mutates nothing.
# Guardrails: read-only; no writes/network; additive lint. --selftest mutates a runtime temp COPY only.
# Usage: sh conformance/model-tiering-plan-wired.sh [--selftest]
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)

check() {  # check FILE REGEX LABEL -> 0 present / 1 absent
  if grep -Eq "$2" "$1" 2>/dev/null; then echo "PASS: $3"; return 0
  else echo "FAIL: $3 (marker absent in $1)"; return 1; fi
}

scan() {  # scan DIR -> 0 iff all three wiring markers present under DIR
  _d=$1; f=0
  check "$_d/templates/TASK-CONTEXT-CONTRACT-TEMPLATE.md" 'Model tier \(dispatch\)'    "TCC carries a Model-tier field" || f=1
  check "$_d/skills/plan/SKILL.md"          'Model-tier per Builder/Explorer task'     "skills/plan prescribes surfacing a per-task tier" || f=1
  check "$_d/agents/orchestrator.agent.md"  'model-tier\.sh resolve'                    "orchestrator resolves the tier at dispatch" || f=1
  return $f
}

selftest() {
  fail=0
  if scan "$ROOT" >/dev/null 2>&1; then echo "PASS: real tree wired"; else echo "FAIL: real tree not wired"; fail=1; fi
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  # non-vacuity: stripping EACH marker in turn MUST fail the scan — all three check()s are load-bearing,
  # not just the TCC one (a regex that silently went always-true in any of them would be caught here).
  for pair in \
    "templates/TASK-CONTEXT-CONTRACT-TEMPLATE.md:Model tier (dispatch)" \
    "skills/plan/SKILL.md:Model-tier per Builder/Explorer task" \
    "agents/orchestrator.agent.md:model-tier.sh resolve"; do
    rel=${pair%%:*}; marker=${pair#*:}
    rm -rf "$tmp/t"; mkdir -p "$tmp/t/templates" "$tmp/t/skills/plan" "$tmp/t/agents"
    cp "$ROOT/templates/TASK-CONTEXT-CONTRACT-TEMPLATE.md" "$tmp/t/templates/"
    cp "$ROOT/skills/plan/SKILL.md" "$tmp/t/skills/plan/"
    cp "$ROOT/agents/orchestrator.agent.md" "$tmp/t/agents/"
    grep -vF "$marker" "$ROOT/$rel" > "$tmp/t/$rel" || true   # strip the marker line(s) from this file's copy
    if scan "$tmp/t" >/dev/null 2>&1; then echo "FAIL: non-vacuity — stripping '$marker' still passed"; fail=1
    else echo "PASS: non-vacuity — stripping '$marker' fails the scan"; fi
  done
  [ "$fail" -eq 0 ] && { echo "model-tiering-plan-wired: ALL PASS"; exit 0; } || { echo "model-tiering-plan-wired: FAILURES"; exit 1; }
}

case "${1:-}" in
  --selftest) selftest ;;
  *) if scan "$ROOT"; then echo "model-tiering-plan-wired: OK"; else echo "model-tiering-plan-wired: FAIL"; exit 1; fi ;;
esac
