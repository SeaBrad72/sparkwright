#!/bin/sh
# orchestrator-loop-wired.sh -- behaviour-lock for the E3a thin orchestration loop.
# Asserts the roster agent-defs have the required six-heading structure, that the loop
# script wires the runaway kill-switch (A2: runaway-guard.sh step) and the trusted-denial
# span (kit.denied), and that the golden-path CI job exercising the loop is present.
# This locks the WIRING; behaviour (the loop actually halts on guard STOP and emits a
# denied span) is proven by the orchestrator-run.sh --selftest and the golden-path job.
# SCOPE: kit-self lock (the golden-path job is the kit's OWN pipeline).
# Usage: sh conformance/orchestrator-loop-wired.sh [--selftest]
set -eu

# Path variables -- overridable so --selftest can point at a fixture tree.
ROSTER_DIR="${ORCH_LOOP_ROSTER_DIR:-agents}"
LOOP_SCRIPT="${ORCH_LOOP_SCRIPT:-scripts/orchestrator-run.sh}"
GP="${ORCH_LOOP_GP:-.github/workflows/golden-path.yml}"

ROSTER_FILES="orchestrator.agent.md engineer.agent.md reviewer.agent.md security.agent.md"

check_roster() {  # <roster_dir> -- each of the four agent files has all six required headings
  dir=$1; miss=0
  for f in $ROSTER_FILES; do
    path="$dir/$f"
    [ -f "$path" ] || { echo "FAIL: missing roster file $path"; miss=1; continue; }
    for h in "## Role" "## Responsibilities" "## Stance" "## Task-Context-Contract" "## Tools needed" "## Success criteria"; do
      grep -qF "$h" "$path" || { echo "FAIL: $path missing heading '$h'"; miss=1; }
    done
  done
  return $miss
}

check_loop() {  # <loop_script> -- exists, executable, wires runaway kill-switch + trusted-denial span
  f=$1; miss=0
  [ -f "$f" ] || { echo "FAIL: missing loop script $f"; return 1; }
  [ -x "$f" ] || { echo "FAIL: loop script not executable: $f"; miss=1; }
  grep -Eq 'runaway-guard\.sh"?[[:space:]]+step' "$f" || { echo "FAIL: $f does not contain 'runaway-guard.sh step' (A2 kill-switch not wired)"; miss=1; }
  grep -qF "kit.denied" "$f"           || { echo "FAIL: $f does not contain 'kit.denied' (trusted-denial span not wired)"; miss=1; }
  return $miss
}

check_gp() {  # <golden-path.yml> -- contains the orchestrator-loop job name (CI proof)
  f=$1; miss=0
  [ -f "$f" ] || { echo "FAIL: golden-path workflow not found: $f"; return 1; }
  # Strip line-comments before matching so a token only in a comment cannot satisfy the lock.
  gp_code=$(sed 's/#.*//' "$f" 2>/dev/null || true)
  printf '%s\n' "$gp_code" | grep -qF "orchestrator-loop" \
    || { echo "FAIL: $f has no 'orchestrator-loop' job (loop not exercised in CI)"; miss=1; }
  return $miss
}

if [ "${1:-}" = "--selftest" ]; then
  sf=0; d=$(mktemp -d)

  # Build a conformant agent file with all six headings.
  _agent_ok() {
    printf '## Role\ntest\n## Responsibilities\ntest\n## Stance\ntest\n## Task-Context-Contract\ntest\n## Tools needed\ntest\n## Success criteria\ntest\n'
  }

  # -- case 1: fully conformant fixture -> exit 0 --
  r1="$d/case1"
  mkdir -p "$r1/agents" "$r1/scripts" "$r1/_gh_/workflows"
  for f in $ROSTER_FILES; do _agent_ok > "$r1/agents/$f"; done
  printf '#!/bin/sh\n# wires the kill-switch\nrunaway-guard.sh step\nkit.denied=true\n' > "$r1/scripts/orchestrator-run.sh"
  chmod +x "$r1/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r1/_gh_/workflows/gp.yml"

  c1_fail=0
  (ORCH_LOOP_ROSTER_DIR="$r1/agents" ORCH_LOOP_SCRIPT="$r1/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r1/_gh_/workflows/gp.yml" \
    sh "$0" >/dev/null 2>&1) || c1_fail=1
  if [ "$c1_fail" -eq 0 ]; then
    echo "selftest PASS: conformant fixture -> exit 0"
  else
    echo "selftest FAIL: conformant fixture wrongly returned non-zero"
    sf=1
  fi

  # -- case 2: missing heading fixture -> exit 1 --
  r2="$d/case2"
  mkdir -p "$r2/agents" "$r2/scripts" "$r2/_gh_/workflows"
  for f in $ROSTER_FILES; do _agent_ok > "$r2/agents/$f"; done
  # Drop '## Stance' from orchestrator.agent.md
  printf '## Role\ntest\n## Responsibilities\ntest\n## Task-Context-Contract\ntest\n## Tools needed\ntest\n## Success criteria\ntest\n' \
    > "$r2/agents/orchestrator.agent.md"
  printf '#!/bin/sh\nrunaway-guard.sh step\nkit.denied=true\n' > "$r2/scripts/orchestrator-run.sh"
  chmod +x "$r2/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r2/_gh_/workflows/gp.yml"

  c2_fail=0
  (ORCH_LOOP_ROSTER_DIR="$r2/agents" ORCH_LOOP_SCRIPT="$r2/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r2/_gh_/workflows/gp.yml" \
    sh "$0" >/dev/null 2>&1) || c2_fail=1
  if [ "$c2_fail" -eq 1 ]; then
    echo "selftest PASS: missing '## Stance' heading -> exit 1"
  else
    echo "selftest FAIL: missing heading NOT caught (should have exited 1)"
    sf=1
  fi

  # -- case 3: A2-teeth -- orchestrator-run.sh WITHOUT 'runaway-guard.sh step' -> exit 1 --
  r3="$d/case3"
  mkdir -p "$r3/agents" "$r3/scripts" "$r3/_gh_/workflows"
  for f in $ROSTER_FILES; do _agent_ok > "$r3/agents/$f"; done
  # The loop script is present and executable but has NO 'runaway-guard.sh step' string.
  printf '#!/bin/sh\n# missing the kill-switch metering call\nkit.denied=true\necho loop ran\n' > "$r3/scripts/orchestrator-run.sh"
  chmod +x "$r3/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r3/_gh_/workflows/gp.yml"

  c3_fail=0
  (ORCH_LOOP_ROSTER_DIR="$r3/agents" ORCH_LOOP_SCRIPT="$r3/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r3/_gh_/workflows/gp.yml" \
    sh "$0" >/dev/null 2>&1) || c3_fail=1
  if [ "$c3_fail" -eq 1 ]; then
    echo "selftest PASS: missing 'runaway-guard.sh step' (A2 teeth) -> exit 1"
  else
    echo "selftest FAIL: absent kill-switch NOT caught -- A2 assertion is vacuous (load-bearing failure)"
    sf=1
  fi

  rm -rf "$d"
  [ "$sf" -eq 0 ] && { echo "OK: orchestrator-loop-wired selftest"; exit 0; } \
                  || { echo "FAIL: orchestrator-loop-wired selftest"; exit 1; }
fi

case "${1:-}" in "") : ;; *) echo "usage: orchestrator-loop-wired.sh [--selftest]" >&2; exit 2 ;; esac

# Kit-self scope check: if this is not the kit repo (no docs/ROADMAP-KIT.md) and the
# golden-path workflow is also absent, this check is N/A (adopter tree).
if [ ! -f "docs/ROADMAP-KIT.md" ] && [ ! -f "$GP" ]; then
  echo "orchestrator-loop: N/A -- kit-self check (golden-path is the kit own pipeline; not applicable outside the kit repo)"
  exit 0
fi

fail=0
# (a) roster section-structure -- four agent defs each carry the six required headings
check_roster "$ROSTER_DIR" || fail=1
# (b) loop wires the A2 kill-switch (runaway-guard.sh step) + trusted-denial span (kit.denied)
check_loop "$LOOP_SCRIPT"  || fail=1
# (c) golden-path CI job exercising the loop is present
check_gp   "$GP"           || fail=1

[ "$fail" -eq 0 ] && { echo "OK: orchestrator-loop wired (roster headings + A2 kill-switch + trusted-denial + golden-path job)"; exit 0; }
echo "FAIL: orchestrator-loop under-wired"; exit 1
