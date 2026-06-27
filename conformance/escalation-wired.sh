#!/bin/sh
# escalation-wired.sh -- wiring-lock for the E3-escalation human-in-the-loop seam.
# Asserts: (a) scripts/escalate.sh exists, is executable, and declares raise/await/resolve;
# (b) the loop wires escalate-on-breach (calls escalate.sh + stamps kit.escalated);
# (c) the agent def documents the escalation discipline; (d) the golden-path job runs the
# escalation selftest. Behaviour (pause/resume/fail-closed) is proven by escalate.sh --selftest
# and the extended orchestrator-run.sh --selftest. SCOPE: kit-self.
# Usage: sh conformance/escalation-wired.sh [--selftest]
set -eu

ESC_SCRIPT="${ESC_WIRED_SCRIPT:-scripts/escalate.sh}"
LOOP_SCRIPT="${ESC_WIRED_LOOP:-scripts/orchestrator-run.sh}"
AGENT_DEF="${ESC_WIRED_AGENT:-agents/orchestrator.agent.md}"
GP="${ESC_WIRED_GP:-.github/workflows/golden-path.yml}"

check_script() {  # escalate.sh exists, executable, declares the three verbs
  f=$1; miss=0
  [ -f "$f" ] || { echo "FAIL: missing escalate script $f"; return 1; }
  [ -x "$f" ] || { echo "FAIL: escalate script not executable: $f"; miss=1; }
  for v in raise await resolve; do
    grep -Eq "^[[:space:]]*$v\)" "$f" || { echo "FAIL: $f missing verb '$v'"; miss=1; }
  done
  return $miss
}

check_loop() {  # the loop wires escalate-on-breach + the trusted-escalation span
  f=$1; miss=0
  [ -f "$f" ] || { echo "FAIL: missing loop script $f"; return 1; }
  grep -qF "escalate.sh" "$f"  || { echo "FAIL: $f does not call escalate.sh (escalation not wired)"; miss=1; }
  grep -qF "kit.escalated" "$f" || { echo "FAIL: $f does not stamp 'kit.escalated' (trusted span not wired)"; miss=1; }
  return $miss
}

check_agent() {  # the orchestrator FLOOR def documents the escalation discipline
  f=$1
  [ -f "$f" ] || { echo "FAIL: missing agent def $f"; return 1; }
  grep -qF "## Escalation discipline" "$f" || { echo "FAIL: $f missing '## Escalation discipline' heading"; return 1; }
  return 0
}

check_gp() {  # the golden-path job runs the escalation selftest (comments stripped)
  f=$1
  [ -f "$f" ] || { echo "FAIL: golden-path workflow not found: $f"; return 1; }
  gp_code=$(sed 's/#.*//' "$f" 2>/dev/null || true)
  printf '%s\n' "$gp_code" | grep -qF "escalate.sh --selftest" \
    || { echo "FAIL: $f golden-path does not run 'escalate.sh --selftest'"; return 1; }
  return 0
}

if [ "${1:-}" = "--selftest" ]; then
  sf=0; d=$(mktemp -d)
  _good_script() { printf '#!/bin/sh\ncase "$1" in\n raise) : ;;\n await) : ;;\n resolve) : ;;\nesac\n'; }
  _good_loop()   { printf '#!/bin/sh\nsh escalate.sh raise x\nkit.escalated=true\n'; }
  _good_agent()  { printf '## Role\nx\n## Escalation discipline\nraise on breach; verdicts are human-ratified\n'; }
  _good_gp()     { printf 'steps:\n  - run: sh scripts/escalate.sh --selftest\n'; }

  # case 1: fully wired -> exit 0
  mkdir -p "$d/1"; _good_script > "$d/1/escalate.sh"; chmod +x "$d/1/escalate.sh"
  _good_loop > "$d/1/loop.sh"; _good_agent > "$d/1/agent.md"; _good_gp > "$d/1/gp.yml"
  c1=0; (ESC_WIRED_SCRIPT="$d/1/escalate.sh" ESC_WIRED_LOOP="$d/1/loop.sh" ESC_WIRED_AGENT="$d/1/agent.md" ESC_WIRED_GP="$d/1/gp.yml" sh "$0" >/dev/null 2>&1) || c1=1
  [ "$c1" -eq 0 ] && echo "selftest PASS: fully wired -> exit 0" || { echo "selftest FAIL: wired fixture wrongly non-zero"; sf=1; }

  # case 2 (TEETH): loop missing the escalate.sh call -> exit 1
  mkdir -p "$d/2"; _good_script > "$d/2/escalate.sh"; chmod +x "$d/2/escalate.sh"
  printf '#!/bin/sh\nkit.escalated=true\n# missing the escalation call\n' > "$d/2/loop.sh"
  _good_agent > "$d/2/agent.md"; _good_gp > "$d/2/gp.yml"
  c2=0; (ESC_WIRED_SCRIPT="$d/2/escalate.sh" ESC_WIRED_LOOP="$d/2/loop.sh" ESC_WIRED_AGENT="$d/2/agent.md" ESC_WIRED_GP="$d/2/gp.yml" sh "$0" >/dev/null 2>&1) || c2=1
  [ "$c2" -eq 1 ] && echo "selftest PASS: unwired loop (teeth) -> exit 1" || { echo "selftest FAIL: unwired loop NOT caught (vacuous)"; sf=1; }

  # case 3 (TEETH): escalate.sh missing the 'resolve' verb -> exit 1
  mkdir -p "$d/3"; printf '#!/bin/sh\ncase "$1" in\n raise) : ;;\n await) : ;;\nesac\n' > "$d/3/escalate.sh"; chmod +x "$d/3/escalate.sh"
  _good_loop > "$d/3/loop.sh"; _good_agent > "$d/3/agent.md"; _good_gp > "$d/3/gp.yml"
  c3=0; (ESC_WIRED_SCRIPT="$d/3/escalate.sh" ESC_WIRED_LOOP="$d/3/loop.sh" ESC_WIRED_AGENT="$d/3/agent.md" ESC_WIRED_GP="$d/3/gp.yml" sh "$0" >/dev/null 2>&1) || c3=1
  [ "$c3" -eq 1 ] && echo "selftest PASS: missing 'resolve' verb (teeth) -> exit 1" || { echo "selftest FAIL: missing verb NOT caught"; sf=1; }

  rm -rf "$d"
  [ "$sf" -eq 0 ] && { echo "OK: escalation-wired selftest"; exit 0; } || { echo "FAIL: escalation-wired selftest"; exit 1; }
fi

case "${1:-}" in "") : ;; *) echo "usage: escalation-wired.sh [--selftest]" >&2; exit 2 ;; esac

# kit-self scope: N/A outside the kit (golden-path is the kit's own pipeline).
if [ ! -f "docs/ROADMAP-KIT.md" ] && [ ! -f "$GP" ]; then
  echo "escalation-seam: N/A -- kit-self check (not applicable outside the kit repo)"; exit 0
fi

fail=0
check_script "$ESC_SCRIPT" || fail=1
check_loop   "$LOOP_SCRIPT" || fail=1
check_agent  "$AGENT_DEF"   || fail=1
check_gp     "$GP"          || fail=1
[ "$fail" -eq 0 ] && { echo "OK: escalation wired (escalate.sh verbs + loop escalate-on-breach + agent discipline + golden-path)"; exit 0; }
echo "FAIL: escalation under-wired"; exit 1
