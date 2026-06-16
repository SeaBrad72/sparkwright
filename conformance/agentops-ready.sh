#!/bin/sh
# agentops-ready.sh — conditional, fail-closed agent-ops-record check (MP-3a).
#
# Companion to conformance/agentic-ops-readiness.md (the Agent-ops readiness gate;
# DEVELOPMENT-PROCESS.md §7 / §13). For an AGENTIC project it asserts the agent-ops
# posture is RECORDED: RUNBOOK §8 has an "Agent-ops:" trace record (not the template
# [trace] placeholder). Non-agentic projects are N/A (skip-pass) — no agent runs to trace.
#
# SCOPE — a green run proves the posture was RECORDED, NOT that traces actually emit, are
# complete, or that the agent behaved (process-conformance). Those are Manual rows in
# agentic-ops-readiness.md (operator evidence). Necessary, not sufficient.
#
# Usage:
#   sh conformance/agentops-ready.sh [project-dir]   (default: .)
#   sh conformance/agentops-ready.sh --selftest
set -eu

# Is $1 an agentic project? Cheap declarative marker in CLAUDE.md or RUNBOOK.md.
is_agentic() {
  _d="$1"
  for f in "$_d/CLAUDE.md" "$_d/RUNBOOK.md"; do
    # tolerate list markers + bold (`- **Agentic:** yes`) around the marker.
    [ -f "$f" ] && grep -Eiq '^[-*[:space:]]*agentic:[-*[:space:]]*yes' "$f" && return 0
  done
  return 1
}

check_dir() {
  dir="$1"
  fail=0

  if ! is_agentic "$dir"; then
    echo "N/A: $dir is not declared agentic (no 'Agentic: yes' in CLAUDE.md/RUNBOOK.md) — skipping (no agent runs to trace)"
    return 0
  fi

  rb="$dir/RUNBOOK.md"
  if [ ! -f "$rb" ]; then
    echo "FAIL: $dir is agentic but has no RUNBOOK.md (need the §8 Agent-ops record) — see conformance/agentic-ops-readiness.md"
    return 1
  fi

  # Record string below must stay in sync with templates/RUNBOOK-TEMPLATE.md §8.
  if ! grep -Eiq 'agent-ops:' "$rb"; then
    echo "FAIL: RUNBOOK has no 'Agent-ops:' record — declare the agent-run trace discipline (schema + where emitted); see docs/operations/agentic-ops.md"
    fail=1
  elif grep -Fiq 'agent-ops: [trace]' "$rb"; then
    echo "FAIL: 'Agent-ops:' still holds the [trace] placeholder — record the real trace posture (e.g. emitter + sink)"
    fail=1
  fi

  if [ "$fail" -ne 0 ]; then return 1; fi
  echo "agentops-ready: OK — agent-ops posture is RECORDED (trace discipline declared). NOTE: this does NOT verify traces actually emit, are complete, or that the agent's behavior conforms (process-conformance) — those are Manual rows in agentic-ops-readiness.md requiring operator evidence."
  return 0
}

# Build mktemp fixtures and assert each outcome. Fixtures LEFT in place (no rm -rf; 7e guard).
selftest() {
  st_fail=0
  base=$(mktemp -d)

  d1="$base/na"; mkdir -p "$d1"; printf '# a plain library, no agents\n' > "$d1/README.md"
  if check_dir "$d1" >/dev/null 2>&1; then
    echo "selftest PASS: non-agentic -> N/A (not over-triggered)"
  else
    echo "selftest FAIL: non-agentic should be N/A"; st_fail=1
  fi

  d2="$base/ok"; mkdir -p "$d2"
  printf '# CLAUDE\n\nAgentic: yes\n' > "$d2/CLAUDE.md"
  printf '# RUNBOOK\n\n## 8. Monitoring & alerting\n- Agent-ops: trace=OTel-GenAI subset, emitter=CC-transcript, sink=traces/\n' > "$d2/RUNBOOK.md"
  if check_dir "$d2" >/dev/null 2>&1; then
    echo "selftest PASS: agentic + filled Agent-ops -> OK"
  else
    echo "selftest FAIL: agentic + filled record should pass"; st_fail=1
  fi

  d3="$base/placeholder"; mkdir -p "$d3"
  printf '# CLAUDE\n\nAgentic: yes\n' > "$d3/CLAUDE.md"
  printf '# RUNBOOK\n\n## 8. Monitoring & alerting\n- Agent-ops: [trace]\n' > "$d3/RUNBOOK.md"
  if check_dir "$d3" >/dev/null 2>&1; then
    echo "selftest FAIL: [trace] placeholder should FAIL"; st_fail=1
  else
    echo "selftest PASS: Agent-ops [trace] placeholder -> FAIL as expected"
  fi

  d4="$base/missing"; mkdir -p "$d4"
  printf '# CLAUDE\n\nAgentic: yes\n' > "$d4/CLAUDE.md"
  printf '# RUNBOOK\n\n## 8. Monitoring & alerting\n- Error tracking: Sentry\n' > "$d4/RUNBOOK.md"
  if check_dir "$d4" >/dev/null 2>&1; then
    echo "selftest FAIL: agentic + missing Agent-ops record should FAIL"; st_fail=1
  else
    echo "selftest PASS: missing Agent-ops record -> FAIL as expected"
  fi

  d5="$base/bold"; mkdir -p "$d5"
  printf '# CLAUDE\n\n- **Agentic:** yes\n' > "$d5/CLAUDE.md"
  printf '# RUNBOOK\n\n## 8. Monitoring & alerting\n- Agent-ops: OTel-GenAI subset, emitter=CC-transcript, sink=traces/\n' > "$d5/RUNBOOK.md"
  if check_dir "$d5" >/dev/null 2>&1; then
    echo "selftest PASS: bold '- **Agentic:** yes' marker -> triggers (OK)"
  else
    echo "selftest FAIL: bold Agentic marker should trigger and pass"; st_fail=1
  fi

  if [ "$st_fail" -ne 0 ]; then
    echo "agentops-ready --selftest: FAIL" >&2
    return 1
  fi
  echo "agentops-ready --selftest: OK (na/ok/placeholder/missing/bold all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest ;;
  *)          check_dir "${1:-.}" ;;
esac
exit $?
