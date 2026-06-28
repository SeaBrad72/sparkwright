#!/bin/sh
# orchestrator-loop-wired.sh -- behaviour-lock for the E3a/E3b thin orchestration loop.
# Asserts the roster agent-defs have the required six-heading structure, that the loop
# script wires the runaway kill-switch (A2: runaway-guard.sh step), the trusted-denial
# span (kit.denied), and the conflict-safe wiring (kit.conflict + git diff --name-only),
# that the kit's own design skill ships + is referenced (Architect hat),
# that the kit's own plan skill ships + is referenced (Architect hat, brick #2),
# that the kit's own tdd skill ships + is referenced by the Engineer (brick #3),
# and that the golden-path CI job exercising the loop is present.
# This locks the WIRING; behaviour (the loop actually halts on guard STOP, emits a
# denied span, and detects conflicts) is proven by orchestrator-run.sh --selftest and
# the golden-path job.
# SCOPE: kit-self lock (the golden-path job is the kit's OWN pipeline).
# Usage: sh conformance/orchestrator-loop-wired.sh [--selftest]
set -eu

# Path variables -- overridable so --selftest can point at a fixture tree.
ROSTER_DIR="${ORCH_LOOP_ROSTER_DIR:-agents}"
LOOP_SCRIPT="${ORCH_LOOP_SCRIPT:-scripts/orchestrator-run.sh}"
GP="${ORCH_LOOP_GP:-.github/workflows/golden-path.yml}"
SKILL_FILE="${ORCH_LOOP_SKILL:-skills/design/SKILL.md}"
PLAN_SKILL_FILE="${ORCH_LOOP_PLAN_SKILL:-skills/plan/SKILL.md}"
TDD_SKILL_FILE="${ORCH_LOOP_TDD_SKILL:-skills/tdd/SKILL.md}"
ENGINEER_DEF="${ORCH_LOOP_ENGINEER_DEF:-agents/engineer.agent.md}"
ORCH_DEF="${ORCH_LOOP_ORCH_DEF:-agents/orchestrator.agent.md}"

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

check_loop() {  # <loop_script> -- exists, executable, wires runaway kill-switch + trusted-denial span + conflict-safe wiring
  f=$1; miss=0
  [ -f "$f" ] || { echo "FAIL: missing loop script $f"; return 1; }
  [ -x "$f" ] || { echo "FAIL: loop script not executable: $f"; miss=1; }
  grep -Eq 'runaway-guard\.sh"?[[:space:]]+step' "$f" || { echo "FAIL: $f does not contain 'runaway-guard.sh step' (A2 kill-switch not wired)"; miss=1; }
  grep -qF "kit.denied" "$f"            || { echo "FAIL: $f does not contain 'kit.denied' (trusted-denial span not wired)"; miss=1; }
  grep -qF "kit.conflict" "$f"          || { echo "FAIL: $f does not stamp 'kit.conflict' (conflict-safe integration not wired)"; miss=1; }
  grep -qF "git diff --name-only" "$f"  || { echo "FAIL: $f has no 'git diff --name-only' overlap check (conflict detection not wired)"; miss=1; }
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

check_skill() {  # <skill_file> <orch_def> -- the kit's own design skill exists, is kit-distinctive, and the orchestrator references it
  s=$1; o=$2; miss=0
  [ -f "$s" ] || { echo "FAIL: missing design skill $s"; return 1; }
  # Kit-distinctive markers: a generic superpowers paraphrase lacking the kit's disciplines fails here.
  for m in "name: design" "<HARD-GATE>" "## When to use" "Design-intent lens" "RE-SELECT" "Honest ceiling"; do
    grep -qF "$m" "$s" || { echo "FAIL: $s missing kit-distinctive marker '$m' (generic copy?)"; miss=1; }
  done
  [ -f "$o" ] || { echo "FAIL: missing orchestrator def $o"; return 1; }
  grep -qF "skills/design/SKILL.md" "$o" || { echo "FAIL: $o does not reference skills/design/SKILL.md (Architect hat not wired)"; miss=1; }
  return $miss
}

check_plan_skill() {  # <plan_skill_file> <orch_def> -- the kit's own plan skill exists, is kit-distinctive, and the orchestrator references it
  s=$1; o=$2; miss=0
  [ -f "$s" ] || { echo "FAIL: missing plan skill $s"; return 1; }
  # Kit-distinctive markers: a generic writing-plans paraphrase lacking the kit's planning disciplines fails here.
  for m in "name: plan" "## When to use" "INVEST" "AMBER" "Conformance lock" "Dual review"; do
    grep -qF "$m" "$s" || { echo "FAIL: $s missing kit-distinctive marker '$m' (generic copy?)"; miss=1; }
  done
  [ -f "$o" ] || { echo "FAIL: missing orchestrator def $o"; return 1; }
  grep -qF "skills/plan/SKILL.md" "$o" || { echo "FAIL: $o does not reference skills/plan/SKILL.md (plan skill not wired)"; miss=1; }
  return $miss
}

check_tdd_skill() {  # <tdd_skill_file> <engineer_def> -- the kit's own tdd skill exists, is kit-distinctive, and the Engineer references it
  s=$1; e=$2; miss=0
  [ -f "$s" ] || { echo "FAIL: missing tdd skill $s"; return 1; }
  # Kit-distinctive markers: a generic test-driven-development paraphrase lacking the kit's disciplines fails here.
  for m in "name: tdd" "## When to use" "Red-Green-Refactor" "non-vacuity" "critical path" "evals"; do
    grep -qF "$m" "$s" || { echo "FAIL: $s missing kit-distinctive marker '$m' (generic copy?)"; miss=1; }
  done
  [ -f "$e" ] || { echo "FAIL: missing engineer def $e"; return 1; }
  grep -qF "skills/tdd/SKILL.md" "$e" || { echo "FAIL: $e does not reference skills/tdd/SKILL.md (tdd skill not wired to the Engineer)"; miss=1; }
  return $miss
}

if [ "${1:-}" = "--selftest" ]; then
  sf=0; d=$(mktemp -d)

  # Build a conformant agent file with all six headings.
  _agent_ok() {
    printf '## Role\ntest\n## Responsibilities\ntest\n## Stance\ntest\n## Task-Context-Contract\ntest\n## Tools needed\ntest\n## Success criteria\ntest\n'
  }
  # Build a conformant design skill carrying every kit-distinctive marker.
  _skill_ok() {
    printf -- '---\nname: design\n---\n<HARD-GATE>\nx\n## When to use\nx\nDesign-intent lens\nRE-SELECT\nHonest ceiling\n'
  }
  # Build a conformant plan skill carrying every kit-distinctive marker.
  _plan_skill_ok() {
    printf -- '---\nname: plan\n---\n## When to use\nx\nINVEST\nAMBER\nConformance lock\nDual review\n'
  }
  # Build a conformant tdd skill carrying every kit-distinctive marker.
  _tdd_skill_ok() {
    printf -- '---\nname: tdd\n---\n## When to use\nx\nRed-Green-Refactor\nnon-vacuity\ncritical path\nevals\n'
  }

  # -- case 1: fully conformant fixture -> exit 0 --
  r1="$d/case1"
  mkdir -p "$r1/agents" "$r1/scripts" "$r1/_gh_/workflows" "$r1/skills/design" "$r1/skills/plan"
  for f in $ROSTER_FILES; do _agent_ok > "$r1/agents/$f"; done
  printf '#!/bin/sh\n# wires the kill-switch\nrunaway-guard.sh step\nkit.denied=true\nkit.conflict=false\ngit diff --name-only HEAD\n' > "$r1/scripts/orchestrator-run.sh"
  chmod +x "$r1/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r1/_gh_/workflows/gp.yml"
  _skill_ok > "$r1/skills/design/SKILL.md"; printf '\nskills/design/SKILL.md\n' >> "$r1/agents/orchestrator.agent.md"
  mkdir -p "$r1/skills/plan"; _plan_skill_ok > "$r1/skills/plan/SKILL.md"
  printf 'skills/plan/SKILL.md\n' >> "$r1/agents/orchestrator.agent.md"
  mkdir -p "$r1/skills/tdd"; _tdd_skill_ok > "$r1/skills/tdd/SKILL.md"
  printf 'skills/tdd/SKILL.md\n' >> "$r1/agents/engineer.agent.md"

  c1_fail=0
  (ORCH_LOOP_ROSTER_DIR="$r1/agents" ORCH_LOOP_SCRIPT="$r1/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r1/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r1/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r1/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r1/skills/tdd/SKILL.md" ORCH_LOOP_ORCH_DEF="$r1/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r1/agents/engineer.agent.md" \
    sh "$0" >/dev/null 2>&1) || c1_fail=1
  if [ "$c1_fail" -eq 0 ]; then
    echo "selftest PASS: conformant fixture -> exit 0"
  else
    echo "selftest FAIL: conformant fixture wrongly returned non-zero"
    sf=1
  fi

  # -- case 2: missing heading fixture -> exit 1 --
  r2="$d/case2"
  mkdir -p "$r2/agents" "$r2/scripts" "$r2/_gh_/workflows" "$r2/skills/design" "$r2/skills/plan"
  for f in $ROSTER_FILES; do _agent_ok > "$r2/agents/$f"; done
  # Drop '## Stance' from orchestrator.agent.md
  printf '## Role\ntest\n## Responsibilities\ntest\n## Task-Context-Contract\ntest\n## Tools needed\ntest\n## Success criteria\ntest\n' \
    > "$r2/agents/orchestrator.agent.md"
  printf '#!/bin/sh\nrunaway-guard.sh step\nkit.denied=true\nkit.conflict=false\ngit diff --name-only HEAD\n' > "$r2/scripts/orchestrator-run.sh"
  chmod +x "$r2/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r2/_gh_/workflows/gp.yml"
  _skill_ok > "$r2/skills/design/SKILL.md"; printf '\nskills/design/SKILL.md\n' >> "$r2/agents/orchestrator.agent.md"
  mkdir -p "$r2/skills/plan"; _plan_skill_ok > "$r2/skills/plan/SKILL.md"
  printf 'skills/plan/SKILL.md\n' >> "$r2/agents/orchestrator.agent.md"
  mkdir -p "$r2/skills/tdd"; _tdd_skill_ok > "$r2/skills/tdd/SKILL.md"
  printf 'skills/tdd/SKILL.md\n' >> "$r2/agents/engineer.agent.md"

  c2_fail=0
  (ORCH_LOOP_ROSTER_DIR="$r2/agents" ORCH_LOOP_SCRIPT="$r2/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r2/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r2/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r2/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r2/skills/tdd/SKILL.md" ORCH_LOOP_ORCH_DEF="$r2/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r2/agents/engineer.agent.md" \
    sh "$0" >/dev/null 2>&1) || c2_fail=1
  if [ "$c2_fail" -eq 1 ]; then
    echo "selftest PASS: missing '## Stance' heading -> exit 1"
  else
    echo "selftest FAIL: missing heading NOT caught (should have exited 1)"
    sf=1
  fi

  # -- case 3: A2-teeth -- orchestrator-run.sh WITHOUT 'runaway-guard.sh step' -> exit 1 --
  r3="$d/case3"
  mkdir -p "$r3/agents" "$r3/scripts" "$r3/_gh_/workflows" "$r3/skills/design" "$r3/skills/plan"
  for f in $ROSTER_FILES; do _agent_ok > "$r3/agents/$f"; done
  # The loop script is present and executable but has NO 'runaway-guard.sh step' string.
  printf '#!/bin/sh\n# missing the kill-switch metering call\nkit.denied=true\nkit.conflict=false\ngit diff --name-only HEAD\necho loop ran\n' > "$r3/scripts/orchestrator-run.sh"
  chmod +x "$r3/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r3/_gh_/workflows/gp.yml"
  _skill_ok > "$r3/skills/design/SKILL.md"; printf '\nskills/design/SKILL.md\n' >> "$r3/agents/orchestrator.agent.md"
  mkdir -p "$r3/skills/plan"; _plan_skill_ok > "$r3/skills/plan/SKILL.md"
  printf 'skills/plan/SKILL.md\n' >> "$r3/agents/orchestrator.agent.md"
  mkdir -p "$r3/skills/tdd"; _tdd_skill_ok > "$r3/skills/tdd/SKILL.md"
  printf 'skills/tdd/SKILL.md\n' >> "$r3/agents/engineer.agent.md"

  c3_fail=0
  (ORCH_LOOP_ROSTER_DIR="$r3/agents" ORCH_LOOP_SCRIPT="$r3/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r3/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r3/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r3/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r3/skills/tdd/SKILL.md" ORCH_LOOP_ORCH_DEF="$r3/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r3/agents/engineer.agent.md" \
    sh "$0" >/dev/null 2>&1) || c3_fail=1
  if [ "$c3_fail" -eq 1 ]; then
    echo "selftest PASS: missing 'runaway-guard.sh step' (A2 teeth) -> exit 1"
  else
    echo "selftest FAIL: absent kill-switch NOT caught -- A2 assertion is vacuous (load-bearing failure)"
    sf=1
  fi

  # -- case 4: conflict-safe teeth -- loop WITHOUT 'kit.conflict' -> exit 1 --
  r4="$d/case4"; mkdir -p "$r4/agents" "$r4/scripts" "$r4/_gh_/workflows" "$r4/skills/design" "$r4/skills/plan"
  for f in $ROSTER_FILES; do _agent_ok > "$r4/agents/$f"; done
  printf '#!/bin/sh\nrunaway-guard.sh step\nkit.denied=true\ngit diff --name-only HEAD\n# conflict stamp intentionally absent\n' > "$r4/scripts/orchestrator-run.sh"
  chmod +x "$r4/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r4/_gh_/workflows/gp.yml"
  _skill_ok > "$r4/skills/design/SKILL.md"; printf '\nskills/design/SKILL.md\n' >> "$r4/agents/orchestrator.agent.md"
  mkdir -p "$r4/skills/plan"; _plan_skill_ok > "$r4/skills/plan/SKILL.md"
  printf 'skills/plan/SKILL.md\n' >> "$r4/agents/orchestrator.agent.md"
  mkdir -p "$r4/skills/tdd"; _tdd_skill_ok > "$r4/skills/tdd/SKILL.md"
  printf 'skills/tdd/SKILL.md\n' >> "$r4/agents/engineer.agent.md"
  c4_fail=0
  (ORCH_LOOP_ROSTER_DIR="$r4/agents" ORCH_LOOP_SCRIPT="$r4/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r4/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r4/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r4/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r4/skills/tdd/SKILL.md" ORCH_LOOP_ORCH_DEF="$r4/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r4/agents/engineer.agent.md" sh "$0" >/dev/null 2>&1) || c4_fail=1
  if [ "$c4_fail" -eq 1 ]; then echo "selftest PASS: missing 'kit.conflict' (conflict teeth) -> exit 1"; else echo "selftest FAIL: absent conflict wiring NOT caught"; sf=1; fi

  # -- case 5: skill teeth -- design skill MISSING a kit-distinctive marker ('## When to use') -> exit 1 --
  r5="$d/case5"; mkdir -p "$r5/agents" "$r5/scripts" "$r5/_gh_/workflows" "$r5/skills/design" "$r5/skills/plan"
  for f in $ROSTER_FILES; do _agent_ok > "$r5/agents/$f"; done
  printf '#!/bin/sh\nrunaway-guard.sh step\nkit.denied=true\nkit.conflict=false\ngit diff --name-only HEAD\n' > "$r5/scripts/orchestrator-run.sh"; chmod +x "$r5/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r5/_gh_/workflows/gp.yml"
  # skill present + orchestrator refs it, but the skill is MISSING the '## When to use' marker -> check_skill fails
  printf -- '---\nname: design\n---\n<HARD-GATE>\nDesign-intent lens\nRE-SELECT\nHonest ceiling\n' > "$r5/skills/design/SKILL.md"
  printf '\nskills/design/SKILL.md\n' >> "$r5/agents/orchestrator.agent.md"
  # plan skill is conformant so check_plan_skill passes; only check_skill fails
  mkdir -p "$r5/skills/plan"; _plan_skill_ok > "$r5/skills/plan/SKILL.md"
  printf 'skills/plan/SKILL.md\n' >> "$r5/agents/orchestrator.agent.md"
  mkdir -p "$r5/skills/tdd"; _tdd_skill_ok > "$r5/skills/tdd/SKILL.md"
  printf 'skills/tdd/SKILL.md\n' >> "$r5/agents/engineer.agent.md"
  c5_fail=0
  (ORCH_LOOP_ROSTER_DIR="$r5/agents" ORCH_LOOP_SCRIPT="$r5/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r5/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r5/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r5/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r5/skills/tdd/SKILL.md" ORCH_LOOP_ORCH_DEF="$r5/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r5/agents/engineer.agent.md" sh "$0" >/dev/null 2>&1) || c5_fail=1
  if [ "$c5_fail" -eq 1 ]; then echo "selftest PASS: design skill missing a kit-distinctive marker -> exit 1"; else echo "selftest FAIL: absent skill marker NOT caught (skill teeth vacuous)"; sf=1; fi

  # -- case 6: plan-skill teeth -- plan skill MISSING a kit-distinctive marker ('AMBER') -> exit 1 --
  r6="$d/case6"; mkdir -p "$r6/agents" "$r6/scripts" "$r6/_gh_/workflows" "$r6/skills/design" "$r6/skills/plan"
  for f in $ROSTER_FILES; do _agent_ok > "$r6/agents/$f"; done
  printf '#!/bin/sh\nrunaway-guard.sh step\nkit.denied=true\nkit.conflict=false\ngit diff --name-only HEAD\n' > "$r6/scripts/orchestrator-run.sh"; chmod +x "$r6/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r6/_gh_/workflows/gp.yml"
  _skill_ok > "$r6/skills/design/SKILL.md"
  # plan skill present + referenced, but MISSING the 'AMBER' marker -> check_plan_skill fails
  printf -- '---\nname: plan\n---\n## When to use\nx\nINVEST\nConformance lock\nDual review\n' > "$r6/skills/plan/SKILL.md"
  printf '\nskills/design/SKILL.md\nskills/plan/SKILL.md\n' >> "$r6/agents/orchestrator.agent.md"
  mkdir -p "$r6/skills/tdd"; _tdd_skill_ok > "$r6/skills/tdd/SKILL.md"
  printf 'skills/tdd/SKILL.md\n' >> "$r6/agents/engineer.agent.md"
  c6_fail=0
  (ORCH_LOOP_ROSTER_DIR="$r6/agents" ORCH_LOOP_SCRIPT="$r6/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r6/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r6/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r6/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r6/skills/tdd/SKILL.md" ORCH_LOOP_ORCH_DEF="$r6/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r6/agents/engineer.agent.md" sh "$0" >/dev/null 2>&1) || c6_fail=1
  if [ "$c6_fail" -eq 1 ]; then echo "selftest PASS: plan skill missing a kit-distinctive marker -> exit 1"; else echo "selftest FAIL: absent plan-skill marker NOT caught (plan-skill teeth vacuous)"; sf=1; fi

  # -- case 7: tdd-skill teeth -- tdd skill MISSING a kit-distinctive marker ('non-vacuity') -> exit 1 --
  r7="$d/case7"; mkdir -p "$r7/agents" "$r7/scripts" "$r7/_gh_/workflows" "$r7/skills/design" "$r7/skills/plan" "$r7/skills/tdd"
  for f in $ROSTER_FILES; do _agent_ok > "$r7/agents/$f"; done
  printf '#!/bin/sh\nrunaway-guard.sh step\nkit.denied=true\nkit.conflict=false\ngit diff --name-only HEAD\n' > "$r7/scripts/orchestrator-run.sh"; chmod +x "$r7/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r7/_gh_/workflows/gp.yml"
  _skill_ok > "$r7/skills/design/SKILL.md"; _plan_skill_ok > "$r7/skills/plan/SKILL.md"
  # tdd skill present + referenced, but MISSING the 'non-vacuity' marker -> check_tdd_skill fails
  printf -- '---\nname: tdd\n---\n## When to use\nx\nRed-Green-Refactor\ncritical path\nevals\n' > "$r7/skills/tdd/SKILL.md"
  printf '\nskills/design/SKILL.md\nskills/plan/SKILL.md\n' >> "$r7/agents/orchestrator.agent.md"
  printf 'skills/tdd/SKILL.md\n' >> "$r7/agents/engineer.agent.md"
  c7_fail=0
  (ORCH_LOOP_ROSTER_DIR="$r7/agents" ORCH_LOOP_SCRIPT="$r7/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r7/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r7/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r7/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r7/skills/tdd/SKILL.md" ORCH_LOOP_ORCH_DEF="$r7/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r7/agents/engineer.agent.md" sh "$0" >/dev/null 2>&1) || c7_fail=1
  if [ "$c7_fail" -eq 1 ]; then echo "selftest PASS: tdd skill missing a kit-distinctive marker -> exit 1"; else echo "selftest FAIL: absent tdd-skill marker NOT caught (tdd-skill teeth vacuous)"; sf=1; fi

  # -- case 8: tdd reference teeth -- conformant tdd skill but Engineer def OMITS the reference -> exit 1 --
  r8="$d/case8"; mkdir -p "$r8/agents" "$r8/scripts" "$r8/_gh_/workflows" "$r8/skills/design" "$r8/skills/plan" "$r8/skills/tdd"
  for f in $ROSTER_FILES; do _agent_ok > "$r8/agents/$f"; done
  printf '#!/bin/sh\nrunaway-guard.sh step\nkit.denied=true\nkit.conflict=false\ngit diff --name-only HEAD\n' > "$r8/scripts/orchestrator-run.sh"; chmod +x "$r8/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r8/_gh_/workflows/gp.yml"
  _skill_ok > "$r8/skills/design/SKILL.md"; _plan_skill_ok > "$r8/skills/plan/SKILL.md"; _tdd_skill_ok > "$r8/skills/tdd/SKILL.md"
  printf '\nskills/design/SKILL.md\nskills/plan/SKILL.md\n' >> "$r8/agents/orchestrator.agent.md"
  # NOTE: deliberately do NOT append 'skills/tdd/SKILL.md' to engineer.agent.md -> check_tdd_skill reference branch must fail
  c8_fail=0
  (ORCH_LOOP_ROSTER_DIR="$r8/agents" ORCH_LOOP_SCRIPT="$r8/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r8/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r8/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r8/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r8/skills/tdd/SKILL.md" ORCH_LOOP_ORCH_DEF="$r8/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r8/agents/engineer.agent.md" sh "$0" >/dev/null 2>&1) || c8_fail=1
  if [ "$c8_fail" -eq 1 ]; then echo "selftest PASS: Engineer def omits tdd reference -> exit 1"; else echo "selftest FAIL: missing tdd reference NOT caught (reference teeth vacuous)"; sf=1; fi

  rm -rf "$d"
  if [ "$sf" -eq 0 ]; then echo "OK: orchestrator-loop-wired selftest (conflict-safe + design-skill + plan-skill + tdd-skill)"; exit 0
  else echo "FAIL: orchestrator-loop-wired selftest"; exit 1; fi
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
# (b) loop wires the A2 kill-switch (runaway-guard.sh step) + trusted-denial span (kit.denied) + conflict-safe wiring
check_loop "$LOOP_SCRIPT"  || fail=1
# (c) golden-path CI job exercising the loop is present
check_gp   "$GP"           || fail=1
# (d) the kit's own design skill ships + is referenced by the orchestrator (Architect hat)
check_skill "$SKILL_FILE" "$ORCH_DEF" || fail=1
# (e) the kit's own plan skill ships + is referenced by the orchestrator (Architect hat, brick #2)
check_plan_skill "$PLAN_SKILL_FILE" "$ORCH_DEF" || fail=1
# (f) the kit's own tdd skill ships + is referenced by the Engineer (brick #3)
check_tdd_skill "$TDD_SKILL_FILE" "$ENGINEER_DEF" || fail=1

[ "$fail" -eq 0 ] && { echo "OK: orchestrator-loop wired (roster headings + A2 kill-switch + trusted-denial + conflict-safe + design-skill + plan-skill + tdd-skill + golden-path job)"; exit 0; }
echo "FAIL: orchestrator-loop under-wired"; exit 1
