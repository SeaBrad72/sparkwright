#!/bin/sh
# orchestrator-loop-wired.sh -- behaviour-lock for the E3a/E3b thin orchestration loop.
# Asserts the roster agent-defs have the required six-heading structure, that the loop
# script wires the runaway kill-switch (A2: runaway-guard.sh step), the trusted-denial
# span (kit.denied), and the conflict-safe wiring (kit.conflict + git diff --name-only),
# that the kit's own design skill ships + is referenced (Architect hat),
# that the kit's own plan skill ships + is referenced (Architect hat, brick #2),
# that the kit's own tdd skill ships + is referenced by the Engineer (brick #3),
# that the kit's own review skill ships + is referenced by the Reviewer (brick #4),
# that the kit's own worktrees/isolation skill ships + is referenced by the Orchestrator (brick #5),
# that the kit's own verification skill ships + is referenced by BOTH the Engineer (evidence-before-claims)
#   and the Orchestrator (confabulation-proofing) (brick #6),
# that the kit's own using-skills discovery keystone ships + indexes every on-disk skills/* spine skill
#   (structural -- enumerated, not a hardcoded list) + is referenced
#   by the Orchestrator (discovery start-here) (brick #7; keystone enumeration made structural in this slice),
# that the kit's own debugging skill ships + is referenced by the Engineer (root-cause-first; brick #8),
# that the kit's own evals skill ships + is referenced by BOTH the Engineer (eval-driven build)
#   and the Security-reviewer (red-team/safety lens) (brick #9; AI-native, a kit-original),
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
REVIEW_SKILL_FILE="${ORCH_LOOP_REVIEW_SKILL:-skills/review/SKILL.md}"
WORKTREES_SKILL_FILE="${ORCH_LOOP_WORKTREES_SKILL:-skills/worktrees/SKILL.md}"
VBC_SKILL_FILE="${ORCH_LOOP_VBC_SKILL:-skills/verification/SKILL.md}"
KEYSTONE_FILE="${ORCH_LOOP_KEYSTONE:-skills/using-skills/SKILL.md}"
DEBUGGING_SKILL_FILE="${ORCH_LOOP_DEBUGGING_SKILL:-skills/debugging/SKILL.md}"
EVALS_SKILL_FILE="${ORCH_LOOP_EVALS_SKILL:-skills/evals/SKILL.md}"
DISCOVERY_SKILL_FILE="${ORCH_LOOP_DISCOVERY_SKILL:-skills/continuous-discovery/SKILL.md}"
OPERATING_SKILL_FILE="${ORCH_LOOP_OPERATING_SKILL:-skills/operating/SKILL.md}"
REVIEWER_DEF="${ORCH_LOOP_REVIEWER_DEF:-agents/reviewer.agent.md}"
ENGINEER_DEF="${ORCH_LOOP_ENGINEER_DEF:-agents/engineer.agent.md}"
ORCH_DEF="${ORCH_LOOP_ORCH_DEF:-agents/orchestrator.agent.md}"
SECURITY_DEF="${ORCH_LOOP_SECURITY_DEF:-agents/security.agent.md}"

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

check_review_skill() {  # <review_skill_file> <reviewer_def> -- the kit's own review skill exists, is kit-distinctive, and the Reviewer references it
  s=$1; r=$2; miss=0
  [ -f "$s" ] || { echo "FAIL: missing review skill $s"; return 1; }
  for m in "name: review" "## When to use" "Confidence" "adversarial" "builder" "NEEDS-FIXES"; do
    grep -qF "$m" "$s" || { echo "FAIL: $s missing kit-distinctive marker '$m' (generic copy?)"; miss=1; }
  done
  [ -f "$r" ] || { echo "FAIL: missing reviewer def $r"; return 1; }
  grep -qF "skills/review/SKILL.md" "$r" || { echo "FAIL: $r does not reference skills/review/SKILL.md (review skill not wired to the Reviewer)"; miss=1; }
  return $miss
}

check_worktrees_skill() {  # <worktrees_skill_file> <orch_def> -- the kit's own worktrees/isolation skill exists, is kit-distinctive, and the Orchestrator references it
  s=$1; o=$2; miss=0
  [ -f "$s" ] || { echo "FAIL: missing worktrees skill $s"; return 1; }
  # Kit-distinctive isolation markers: a generic using-git-worktrees paraphrase fails here.
  # NOTE: '--' terminates grep options so the '--no-renames' marker is matched as a pattern, not a flag.
  for m in "name: worktrees" "disjoint file sets" "--no-renames" "out-of-slice" "native"; do
    grep -qF -- "$m" "$s" || { echo "FAIL: $s missing kit-distinctive marker '$m' (generic copy?)"; miss=1; }
  done
  [ -f "$o" ] || { echo "FAIL: missing orchestrator def $o"; return 1; }
  grep -qF "skills/worktrees/SKILL.md" "$o" || { echo "FAIL: $o does not reference skills/worktrees/SKILL.md (Isolation not wired to the Orchestrator)"; miss=1; }
  return $miss
}

check_vbc_skill() {  # <vbc_skill_file> <engineer_def> <orch_def> -- the kit's own verification skill exists, is kit-distinctive, and BOTH the Engineer (evidence-before-claims) and Orchestrator (confabulation-proofing) reference it
  s=$1; e=$2; o=$3; miss=0
  [ -f "$s" ] || { echo "FAIL: missing verification skill $s"; return 1; }
  # Kit-distinctive verification markers: a generic verification-before-completion paraphrase lacking the kit's
  # confabulation-proofing + clone-dry-run disciplines fails here. None begins with '-', so plain grep -qF is safe.
  for m in "name: verification" "confabulation" "clone dry-run" "evidence before claims" "fresh"; do
    grep -qF "$m" "$s" || { echo "FAIL: $s missing kit-distinctive marker '$m' (generic copy?)"; miss=1; }
  done
  [ -f "$e" ] || { echo "FAIL: missing engineer def $e"; return 1; }
  grep -qF "skills/verification/SKILL.md" "$e" || { echo "FAIL: $e does not reference skills/verification/SKILL.md (evidence-before-claims not wired to the Engineer)"; miss=1; }
  [ -f "$o" ] || { echo "FAIL: missing orchestrator def $o"; return 1; }
  grep -qF "skills/verification/SKILL.md" "$o" || { echo "FAIL: $o does not reference skills/verification/SKILL.md (confabulation-proofing not wired to the Orchestrator)"; miss=1; }
  return $miss
}

check_keystone() {  # <keystone> <orch_def> -- the kit's own using-skills discovery keystone exists, carries the discovery discipline markers, indexes every on-disk skills/* spine skill (structural -- enumerated, not a hardcoded list), and the Orchestrator references it (single-seat: discovery is the conductor's entry)
  s=$1; o=$2; miss=0
  [ -f "$s" ] || { echo "FAIL: missing using-skills keystone $s"; return 1; }
  # Discovery-discipline markers: a generic using-superpowers paraphrase lacking the kit's invoke-by-read
  # discipline + instruction-priority fails here. None begins with '-', so plain grep -qF is safe.
  for m in "name: using-skills" "invoke by reading" "before acting" "user instructions"; do
    grep -qF "$m" "$s" || { echo "FAIL: $s missing kit-distinctive discipline marker '$m' (generic copy?)"; miss=1; }
  done
  # Index teeth (STRUCTURAL): enumerate every on-disk skills/*/SKILL.md (excluding the keystone itself) and
  # assert the keystone indexes each. The index is checked against ground truth (the filesystem), not a
  # hardcoded list the verifier author must remember to update -- so the index cannot drift green relative to disk.
  skills_dir=$(dirname "$(dirname "$s")")
  for d in "$skills_dir"/*/; do
    [ -f "$d/SKILL.md" ] || continue          # only real skills (filters a literal no-match glob too)
    name=$(basename "$d")
    [ "$name" = "using-skills" ] && continue   # the keystone need not index itself
    grep -qF "skills/$name" "$s" || { echo "FAIL: $s does not index on-disk spine skill 'skills/$name' (index not exhaustive)"; miss=1; }
  done
  [ -f "$o" ] || { echo "FAIL: missing orchestrator def $o"; return 1; }
  grep -qF "skills/using-skills/SKILL.md" "$o" || { echo "FAIL: $o does not reference skills/using-skills/SKILL.md (discovery start-here not wired to the Orchestrator)"; miss=1; }
  return $miss
}

check_debugging_skill() {  # <debugging_skill_file> <engineer_def> -- the kit's own debugging skill exists, is kit-distinctive (root-cause-first + regression-test framing), and the Engineer references it
  s=$1; e=$2; miss=0
  [ -f "$s" ] || { echo "FAIL: missing debugging skill $s"; return 1; }
  # Kit-distinctive markers: a generic systematic-debugging paraphrase lacking the kit's root-cause-first +
  # bug-becomes-a-regression-test + one-change-at-a-time disciplines fails here. None begins with '-', so plain grep -qF is safe.
  for m in "name: debugging" "root cause" "reproduce" "regression test" "one hypothesis"; do
    grep -qF "$m" "$s" || { echo "FAIL: $s missing kit-distinctive marker '$m' (generic copy?)"; miss=1; }
  done
  [ -f "$e" ] || { echo "FAIL: missing engineer def $e"; return 1; }
  grep -qF "skills/debugging/SKILL.md" "$e" || { echo "FAIL: $e does not reference skills/debugging/SKILL.md (root-cause debugging not wired to the Engineer)"; miss=1; }
  return $miss
}

check_evals_skill() {  # <evals_skill_file> <engineer_def> <security_def> -- the kit's own evals skill exists, is kit-distinctive (eval-driven, pinned independent judge, red-team, threshold), and BOTH the Engineer (eval-driven build) and the Security-reviewer (red-team/safety lens) reference it
  s=$1; e=$2; sec=$3; miss=0
  [ -f "$s" ] || { echo "FAIL: missing evals skill $s"; return 1; }
  # Kit-distinctive markers: a generic eval tutorial lacking the kit's eval-driven probabilistic red->green +
  # pinned-independent-judge + red-team + threshold framing fails here. None begins with '-', so plain grep -qF is safe.
  for m in "name: evals" "eval-driven" "judge" "red-team" "threshold"; do
    grep -qF "$m" "$s" || { echo "FAIL: $s missing kit-distinctive marker '$m' (generic copy?)"; miss=1; }
  done
  [ -f "$e" ] || { echo "FAIL: missing engineer def $e"; return 1; }
  grep -qF "skills/evals/SKILL.md" "$e" || { echo "FAIL: $e does not reference skills/evals/SKILL.md (eval-driven build not wired to the Engineer)"; miss=1; }
  [ -f "$sec" ] || { echo "FAIL: missing security def $sec"; return 1; }
  grep -qF "skills/evals/SKILL.md" "$sec" || { echo "FAIL: $sec does not reference skills/evals/SKILL.md (red-team/safety lens not wired to the Security-reviewer)"; miss=1; }
  return $miss
}

check_discovery_skill() {  # <discovery_skill_file> <orch_def> -- the kit's own continuous-discovery skill exists, is kit-distinctive (problem-space partner craft), and the Orchestrator (Product hat) references it
  s=$1; o=$2; miss=0
  [ -f "$s" ] || { echo "FAIL: missing continuous-discovery skill $s"; return 1; }
  # Kit-distinctive markers: a generic continuous-discovery tutorial lacking the kit's discovery-partner +
  # outcome-over-output framing fails here. None begins with '-', so plain grep -qF is safe.
  for m in "name: continuous-discovery" "discovery partner" "outcome over output" "opportunity solution tree" "riskiest assumption" "small bet"; do
    grep -qF "$m" "$s" || { echo "FAIL: $s missing kit-distinctive marker '$m' (generic copy?)"; miss=1; }
  done
  [ -f "$o" ] || { echo "FAIL: missing orchestrator def $o"; return 1; }
  grep -qF "skills/continuous-discovery/SKILL.md" "$o" || { echo "FAIL: $o does not reference skills/continuous-discovery/SKILL.md (Product hat not wired)"; miss=1; }
  return $miss
}

check_operating_skill() {  # <skill_file> <orchestrator_def>
  s=$1; o=$2; miss=0
  [ -f "$s" ] || { echo "FAIL: missing operating skill $s"; return 1; }
  # Kit-distinctive markers: a generic SRE tutorial lacking the kit's blast-radius-aware advisory-not-actuating
  # operate-phase craft fails here. None begins with '-', so plain grep -qF is safe.
  for m in "name: operating" "blast radius" "advisory, not actuating" \
            "the human commands the catastrophic action" "autonomy tier" "surface, don't actuate"; do
    grep -qF -- "$m" "$s" || { echo "FAIL: operating SKILL.md missing marker: $m"; miss=1; }
  done
  [ -f "$o" ] || { echo "FAIL: missing orchestrator def $o"; return 1; }
  grep -qF -- "skills/operating/SKILL.md" "$o" \
    || { echo "FAIL: $o does not reference skills/operating/SKILL.md (Ops hat not wired to the Orchestrator)"; miss=1; }
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
  # Build a conformant review skill carrying every kit-distinctive marker.
  _review_skill_ok() {
    printf -- '---\nname: review\n---\n## When to use\nx\nConfidence\nadversarial\nbuilder\nNEEDS-FIXES\n'
  }
  # Build a conformant worktrees skill carrying every kit-distinctive marker.
  _worktrees_skill_ok() {
    printf -- '---\nname: worktrees\n---\n## When to use\nx\ndisjoint file sets\n--no-renames\nout-of-slice\nnative\n'
  }
  # Build a conformant verification skill carrying every kit-distinctive marker.
  _vbc_skill_ok() {
    printf -- '---\nname: verification\n---\n## When to use\nx\nconfabulation\nclone dry-run\nevidence before claims\nfresh\n'
  }
  # Build a conformant using-skills keystone: all four discipline markers + every on-disk index path (incl. skills/evals -- the structural check_keystone enumerates the fixture's skills dirs, which now include evals).
  _keystone_ok() {
    printf -- '---\nname: using-skills\n---\n## When to use\nx\ninvoke by reading\nbefore acting\nuser instructions\nskills/design\nskills/plan\nskills/tdd\nskills/review\nskills/worktrees\nskills/verification\nskills/debugging\nskills/evals\nskills/continuous-discovery\nskills/operating\n'
  }
  # Build a conformant debugging skill carrying every kit-distinctive marker.
  _debugging_skill_ok() {
    printf -- '---\nname: debugging\n---\n## When to use\nx\nroot cause\nreproduce\nregression test\none hypothesis\n'
  }
  # Build a conformant evals skill carrying every kit-distinctive marker.
  _evals_skill_ok() {
    printf -- '---\nname: evals\n---\n## When to use\nx\neval-driven\njudge\nred-team\nthreshold\n'
  }
  # Build a conformant continuous-discovery skill carrying every kit-distinctive marker.
  _discovery_skill_ok() {
    printf -- '---\nname: continuous-discovery\n---\n## When to use\nx\ndiscovery partner\noutcome over output\nopportunity solution tree\nriskiest assumption\nsmall bet\n'
  }
  # Build a conformant operating skill carrying every kit-distinctive marker.
  # The single quote in "don't" is shell-escaped with the '"'"' trick in the printf literal.
  _operating_skill_ok() {
    printf -- '---\nname: operating\n---\n## When to use\nx\nblast radius\nadvisory, not actuating\nthe human commands the catastrophic action\nautonomy tier\nsurface, don'"'"'t actuate\n'
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
  mkdir -p "$r1/skills/review"; _review_skill_ok > "$r1/skills/review/SKILL.md"
  printf 'skills/review/SKILL.md\n' >> "$r1/agents/reviewer.agent.md"
  mkdir -p "$r1/skills/worktrees"; _worktrees_skill_ok > "$r1/skills/worktrees/SKILL.md"
  printf 'skills/worktrees/SKILL.md\n' >> "$r1/agents/orchestrator.agent.md"

  mkdir -p "$r1/skills/verification"; _vbc_skill_ok > "$r1/skills/verification/SKILL.md"
  printf 'skills/verification/SKILL.md\n' >> "$r1/agents/engineer.agent.md"
  printf 'skills/verification/SKILL.md\n' >> "$r1/agents/orchestrator.agent.md"
  mkdir -p "$r1/skills/debugging"; _debugging_skill_ok > "$r1/skills/debugging/SKILL.md"
  printf 'skills/debugging/SKILL.md\n' >> "$r1/agents/engineer.agent.md"
  mkdir -p "$r1/skills/evals"; _evals_skill_ok > "$r1/skills/evals/SKILL.md"
  printf 'skills/evals/SKILL.md\n' >> "$r1/agents/engineer.agent.md"
  printf 'skills/evals/SKILL.md\n' >> "$r1/agents/security.agent.md"
  c1_fail=0
  mkdir -p "$r1/skills/using-skills"; _keystone_ok > "$r1/skills/using-skills/SKILL.md"
  printf 'skills/using-skills/SKILL.md\n' >> "$r1/agents/orchestrator.agent.md"
  mkdir -p "$r1/skills/continuous-discovery"; _discovery_skill_ok > "$r1/skills/continuous-discovery/SKILL.md"
  printf 'skills/continuous-discovery/SKILL.md\n' >> "$r1/agents/orchestrator.agent.md"
  mkdir -p "$r1/skills/operating"; _operating_skill_ok > "$r1/skills/operating/SKILL.md"
  printf 'skills/operating/SKILL.md\n' >> "$r1/agents/orchestrator.agent.md"
  (ORCH_LOOP_ROSTER_DIR="$r1/agents" ORCH_LOOP_SCRIPT="$r1/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r1/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r1/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r1/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r1/skills/tdd/SKILL.md" ORCH_LOOP_REVIEW_SKILL="$r1/skills/review/SKILL.md" ORCH_LOOP_WORKTREES_SKILL="$r1/skills/worktrees/SKILL.md" ORCH_LOOP_VBC_SKILL="$r1/skills/verification/SKILL.md" ORCH_LOOP_KEYSTONE="$r1/skills/using-skills/SKILL.md" ORCH_LOOP_DEBUGGING_SKILL="$r1/skills/debugging/SKILL.md" ORCH_LOOP_EVALS_SKILL="$r1/skills/evals/SKILL.md" ORCH_LOOP_DISCOVERY_SKILL="$r1/skills/continuous-discovery/SKILL.md" ORCH_LOOP_OPERATING_SKILL="$r1/skills/operating/SKILL.md" ORCH_LOOP_SECURITY_DEF="$r1/agents/security.agent.md" ORCH_LOOP_ORCH_DEF="$r1/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r1/agents/engineer.agent.md" ORCH_LOOP_REVIEWER_DEF="$r1/agents/reviewer.agent.md" \
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
  mkdir -p "$r2/skills/review"; _review_skill_ok > "$r2/skills/review/SKILL.md"
  printf 'skills/review/SKILL.md\n' >> "$r2/agents/reviewer.agent.md"
  mkdir -p "$r2/skills/worktrees"; _worktrees_skill_ok > "$r2/skills/worktrees/SKILL.md"
  printf 'skills/worktrees/SKILL.md\n' >> "$r2/agents/orchestrator.agent.md"

  mkdir -p "$r2/skills/verification"; _vbc_skill_ok > "$r2/skills/verification/SKILL.md"
  printf 'skills/verification/SKILL.md\n' >> "$r2/agents/engineer.agent.md"
  printf 'skills/verification/SKILL.md\n' >> "$r2/agents/orchestrator.agent.md"
  mkdir -p "$r2/skills/debugging"; _debugging_skill_ok > "$r2/skills/debugging/SKILL.md"
  printf 'skills/debugging/SKILL.md\n' >> "$r2/agents/engineer.agent.md"
  mkdir -p "$r2/skills/evals"; _evals_skill_ok > "$r2/skills/evals/SKILL.md"
  printf 'skills/evals/SKILL.md\n' >> "$r2/agents/engineer.agent.md"
  printf 'skills/evals/SKILL.md\n' >> "$r2/agents/security.agent.md"
  c2_fail=0
  mkdir -p "$r2/skills/using-skills"; _keystone_ok > "$r2/skills/using-skills/SKILL.md"
  printf 'skills/using-skills/SKILL.md\n' >> "$r2/agents/orchestrator.agent.md"
  mkdir -p "$r2/skills/continuous-discovery"; _discovery_skill_ok > "$r2/skills/continuous-discovery/SKILL.md"
  printf 'skills/continuous-discovery/SKILL.md\n' >> "$r2/agents/orchestrator.agent.md"
  mkdir -p "$r2/skills/operating"; _operating_skill_ok > "$r2/skills/operating/SKILL.md"
  printf 'skills/operating/SKILL.md\n' >> "$r2/agents/orchestrator.agent.md"
  (ORCH_LOOP_ROSTER_DIR="$r2/agents" ORCH_LOOP_SCRIPT="$r2/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r2/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r2/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r2/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r2/skills/tdd/SKILL.md" ORCH_LOOP_REVIEW_SKILL="$r2/skills/review/SKILL.md" ORCH_LOOP_WORKTREES_SKILL="$r2/skills/worktrees/SKILL.md" ORCH_LOOP_VBC_SKILL="$r2/skills/verification/SKILL.md" ORCH_LOOP_KEYSTONE="$r2/skills/using-skills/SKILL.md" ORCH_LOOP_DEBUGGING_SKILL="$r2/skills/debugging/SKILL.md" ORCH_LOOP_EVALS_SKILL="$r2/skills/evals/SKILL.md" ORCH_LOOP_DISCOVERY_SKILL="$r2/skills/continuous-discovery/SKILL.md" ORCH_LOOP_OPERATING_SKILL="$r2/skills/operating/SKILL.md" ORCH_LOOP_SECURITY_DEF="$r2/agents/security.agent.md" ORCH_LOOP_ORCH_DEF="$r2/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r2/agents/engineer.agent.md" ORCH_LOOP_REVIEWER_DEF="$r2/agents/reviewer.agent.md" \
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
  mkdir -p "$r3/skills/review"; _review_skill_ok > "$r3/skills/review/SKILL.md"
  printf 'skills/review/SKILL.md\n' >> "$r3/agents/reviewer.agent.md"
  mkdir -p "$r3/skills/worktrees"; _worktrees_skill_ok > "$r3/skills/worktrees/SKILL.md"
  printf 'skills/worktrees/SKILL.md\n' >> "$r3/agents/orchestrator.agent.md"

  mkdir -p "$r3/skills/verification"; _vbc_skill_ok > "$r3/skills/verification/SKILL.md"
  printf 'skills/verification/SKILL.md\n' >> "$r3/agents/engineer.agent.md"
  printf 'skills/verification/SKILL.md\n' >> "$r3/agents/orchestrator.agent.md"
  mkdir -p "$r3/skills/debugging"; _debugging_skill_ok > "$r3/skills/debugging/SKILL.md"
  printf 'skills/debugging/SKILL.md\n' >> "$r3/agents/engineer.agent.md"
  mkdir -p "$r3/skills/evals"; _evals_skill_ok > "$r3/skills/evals/SKILL.md"
  printf 'skills/evals/SKILL.md\n' >> "$r3/agents/engineer.agent.md"
  printf 'skills/evals/SKILL.md\n' >> "$r3/agents/security.agent.md"
  c3_fail=0
  mkdir -p "$r3/skills/using-skills"; _keystone_ok > "$r3/skills/using-skills/SKILL.md"
  printf 'skills/using-skills/SKILL.md\n' >> "$r3/agents/orchestrator.agent.md"
  mkdir -p "$r3/skills/continuous-discovery"; _discovery_skill_ok > "$r3/skills/continuous-discovery/SKILL.md"
  printf 'skills/continuous-discovery/SKILL.md\n' >> "$r3/agents/orchestrator.agent.md"
  mkdir -p "$r3/skills/operating"; _operating_skill_ok > "$r3/skills/operating/SKILL.md"
  printf 'skills/operating/SKILL.md\n' >> "$r3/agents/orchestrator.agent.md"
  (ORCH_LOOP_ROSTER_DIR="$r3/agents" ORCH_LOOP_SCRIPT="$r3/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r3/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r3/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r3/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r3/skills/tdd/SKILL.md" ORCH_LOOP_REVIEW_SKILL="$r3/skills/review/SKILL.md" ORCH_LOOP_WORKTREES_SKILL="$r3/skills/worktrees/SKILL.md" ORCH_LOOP_VBC_SKILL="$r3/skills/verification/SKILL.md" ORCH_LOOP_KEYSTONE="$r3/skills/using-skills/SKILL.md" ORCH_LOOP_DEBUGGING_SKILL="$r3/skills/debugging/SKILL.md" ORCH_LOOP_EVALS_SKILL="$r3/skills/evals/SKILL.md" ORCH_LOOP_DISCOVERY_SKILL="$r3/skills/continuous-discovery/SKILL.md" ORCH_LOOP_OPERATING_SKILL="$r3/skills/operating/SKILL.md" ORCH_LOOP_SECURITY_DEF="$r3/agents/security.agent.md" ORCH_LOOP_ORCH_DEF="$r3/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r3/agents/engineer.agent.md" ORCH_LOOP_REVIEWER_DEF="$r3/agents/reviewer.agent.md" \
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
  mkdir -p "$r4/skills/review"; _review_skill_ok > "$r4/skills/review/SKILL.md"
  printf 'skills/review/SKILL.md\n' >> "$r4/agents/reviewer.agent.md"
  mkdir -p "$r4/skills/worktrees"; _worktrees_skill_ok > "$r4/skills/worktrees/SKILL.md"
  printf 'skills/worktrees/SKILL.md\n' >> "$r4/agents/orchestrator.agent.md"
  mkdir -p "$r4/skills/verification"; _vbc_skill_ok > "$r4/skills/verification/SKILL.md"
  printf 'skills/verification/SKILL.md\n' >> "$r4/agents/engineer.agent.md"
  printf 'skills/verification/SKILL.md\n' >> "$r4/agents/orchestrator.agent.md"
  mkdir -p "$r4/skills/debugging"; _debugging_skill_ok > "$r4/skills/debugging/SKILL.md"
  printf 'skills/debugging/SKILL.md\n' >> "$r4/agents/engineer.agent.md"
  mkdir -p "$r4/skills/evals"; _evals_skill_ok > "$r4/skills/evals/SKILL.md"
  printf 'skills/evals/SKILL.md\n' >> "$r4/agents/engineer.agent.md"
  printf 'skills/evals/SKILL.md\n' >> "$r4/agents/security.agent.md"
  c4_fail=0
  mkdir -p "$r4/skills/using-skills"; _keystone_ok > "$r4/skills/using-skills/SKILL.md"
  printf 'skills/using-skills/SKILL.md\n' >> "$r4/agents/orchestrator.agent.md"
  mkdir -p "$r4/skills/continuous-discovery"; _discovery_skill_ok > "$r4/skills/continuous-discovery/SKILL.md"
  printf 'skills/continuous-discovery/SKILL.md\n' >> "$r4/agents/orchestrator.agent.md"
  mkdir -p "$r4/skills/operating"; _operating_skill_ok > "$r4/skills/operating/SKILL.md"
  printf 'skills/operating/SKILL.md\n' >> "$r4/agents/orchestrator.agent.md"
  (ORCH_LOOP_ROSTER_DIR="$r4/agents" ORCH_LOOP_SCRIPT="$r4/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r4/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r4/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r4/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r4/skills/tdd/SKILL.md" ORCH_LOOP_REVIEW_SKILL="$r4/skills/review/SKILL.md" ORCH_LOOP_WORKTREES_SKILL="$r4/skills/worktrees/SKILL.md" ORCH_LOOP_VBC_SKILL="$r4/skills/verification/SKILL.md" ORCH_LOOP_KEYSTONE="$r4/skills/using-skills/SKILL.md" ORCH_LOOP_DEBUGGING_SKILL="$r4/skills/debugging/SKILL.md" ORCH_LOOP_EVALS_SKILL="$r4/skills/evals/SKILL.md" ORCH_LOOP_DISCOVERY_SKILL="$r4/skills/continuous-discovery/SKILL.md" ORCH_LOOP_OPERATING_SKILL="$r4/skills/operating/SKILL.md" ORCH_LOOP_SECURITY_DEF="$r4/agents/security.agent.md" ORCH_LOOP_ORCH_DEF="$r4/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r4/agents/engineer.agent.md" ORCH_LOOP_REVIEWER_DEF="$r4/agents/reviewer.agent.md" sh "$0" >/dev/null 2>&1) || c4_fail=1
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
  mkdir -p "$r5/skills/review"; _review_skill_ok > "$r5/skills/review/SKILL.md"
  printf 'skills/review/SKILL.md\n' >> "$r5/agents/reviewer.agent.md"
  mkdir -p "$r5/skills/worktrees"; _worktrees_skill_ok > "$r5/skills/worktrees/SKILL.md"
  printf 'skills/worktrees/SKILL.md\n' >> "$r5/agents/orchestrator.agent.md"
  mkdir -p "$r5/skills/verification"; _vbc_skill_ok > "$r5/skills/verification/SKILL.md"
  printf 'skills/verification/SKILL.md\n' >> "$r5/agents/engineer.agent.md"
  printf 'skills/verification/SKILL.md\n' >> "$r5/agents/orchestrator.agent.md"
  mkdir -p "$r5/skills/debugging"; _debugging_skill_ok > "$r5/skills/debugging/SKILL.md"
  printf 'skills/debugging/SKILL.md\n' >> "$r5/agents/engineer.agent.md"
  mkdir -p "$r5/skills/evals"; _evals_skill_ok > "$r5/skills/evals/SKILL.md"
  printf 'skills/evals/SKILL.md\n' >> "$r5/agents/engineer.agent.md"
  printf 'skills/evals/SKILL.md\n' >> "$r5/agents/security.agent.md"
  c5_fail=0
  mkdir -p "$r5/skills/using-skills"; _keystone_ok > "$r5/skills/using-skills/SKILL.md"
  printf 'skills/using-skills/SKILL.md\n' >> "$r5/agents/orchestrator.agent.md"
  mkdir -p "$r5/skills/continuous-discovery"; _discovery_skill_ok > "$r5/skills/continuous-discovery/SKILL.md"
  printf 'skills/continuous-discovery/SKILL.md\n' >> "$r5/agents/orchestrator.agent.md"
  mkdir -p "$r5/skills/operating"; _operating_skill_ok > "$r5/skills/operating/SKILL.md"
  printf 'skills/operating/SKILL.md\n' >> "$r5/agents/orchestrator.agent.md"
  (ORCH_LOOP_ROSTER_DIR="$r5/agents" ORCH_LOOP_SCRIPT="$r5/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r5/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r5/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r5/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r5/skills/tdd/SKILL.md" ORCH_LOOP_REVIEW_SKILL="$r5/skills/review/SKILL.md" ORCH_LOOP_WORKTREES_SKILL="$r5/skills/worktrees/SKILL.md" ORCH_LOOP_VBC_SKILL="$r5/skills/verification/SKILL.md" ORCH_LOOP_KEYSTONE="$r5/skills/using-skills/SKILL.md" ORCH_LOOP_DEBUGGING_SKILL="$r5/skills/debugging/SKILL.md" ORCH_LOOP_EVALS_SKILL="$r5/skills/evals/SKILL.md" ORCH_LOOP_DISCOVERY_SKILL="$r5/skills/continuous-discovery/SKILL.md" ORCH_LOOP_OPERATING_SKILL="$r5/skills/operating/SKILL.md" ORCH_LOOP_SECURITY_DEF="$r5/agents/security.agent.md" ORCH_LOOP_ORCH_DEF="$r5/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r5/agents/engineer.agent.md" ORCH_LOOP_REVIEWER_DEF="$r5/agents/reviewer.agent.md" sh "$0" >/dev/null 2>&1) || c5_fail=1
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
  mkdir -p "$r6/skills/review"; _review_skill_ok > "$r6/skills/review/SKILL.md"
  printf 'skills/review/SKILL.md\n' >> "$r6/agents/reviewer.agent.md"
  mkdir -p "$r6/skills/worktrees"; _worktrees_skill_ok > "$r6/skills/worktrees/SKILL.md"
  printf 'skills/worktrees/SKILL.md\n' >> "$r6/agents/orchestrator.agent.md"
  mkdir -p "$r6/skills/verification"; _vbc_skill_ok > "$r6/skills/verification/SKILL.md"
  printf 'skills/verification/SKILL.md\n' >> "$r6/agents/engineer.agent.md"
  printf 'skills/verification/SKILL.md\n' >> "$r6/agents/orchestrator.agent.md"
  mkdir -p "$r6/skills/debugging"; _debugging_skill_ok > "$r6/skills/debugging/SKILL.md"
  printf 'skills/debugging/SKILL.md\n' >> "$r6/agents/engineer.agent.md"
  mkdir -p "$r6/skills/evals"; _evals_skill_ok > "$r6/skills/evals/SKILL.md"
  printf 'skills/evals/SKILL.md\n' >> "$r6/agents/engineer.agent.md"
  printf 'skills/evals/SKILL.md\n' >> "$r6/agents/security.agent.md"
  c6_fail=0
  mkdir -p "$r6/skills/using-skills"; _keystone_ok > "$r6/skills/using-skills/SKILL.md"
  printf 'skills/using-skills/SKILL.md\n' >> "$r6/agents/orchestrator.agent.md"
  mkdir -p "$r6/skills/continuous-discovery"; _discovery_skill_ok > "$r6/skills/continuous-discovery/SKILL.md"
  printf 'skills/continuous-discovery/SKILL.md\n' >> "$r6/agents/orchestrator.agent.md"
  mkdir -p "$r6/skills/operating"; _operating_skill_ok > "$r6/skills/operating/SKILL.md"
  printf 'skills/operating/SKILL.md\n' >> "$r6/agents/orchestrator.agent.md"
  (ORCH_LOOP_ROSTER_DIR="$r6/agents" ORCH_LOOP_SCRIPT="$r6/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r6/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r6/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r6/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r6/skills/tdd/SKILL.md" ORCH_LOOP_REVIEW_SKILL="$r6/skills/review/SKILL.md" ORCH_LOOP_WORKTREES_SKILL="$r6/skills/worktrees/SKILL.md" ORCH_LOOP_VBC_SKILL="$r6/skills/verification/SKILL.md" ORCH_LOOP_KEYSTONE="$r6/skills/using-skills/SKILL.md" ORCH_LOOP_DEBUGGING_SKILL="$r6/skills/debugging/SKILL.md" ORCH_LOOP_EVALS_SKILL="$r6/skills/evals/SKILL.md" ORCH_LOOP_DISCOVERY_SKILL="$r6/skills/continuous-discovery/SKILL.md" ORCH_LOOP_OPERATING_SKILL="$r6/skills/operating/SKILL.md" ORCH_LOOP_SECURITY_DEF="$r6/agents/security.agent.md" ORCH_LOOP_ORCH_DEF="$r6/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r6/agents/engineer.agent.md" ORCH_LOOP_REVIEWER_DEF="$r6/agents/reviewer.agent.md" sh "$0" >/dev/null 2>&1) || c6_fail=1
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
  mkdir -p "$r7/skills/review"; _review_skill_ok > "$r7/skills/review/SKILL.md"
  printf 'skills/review/SKILL.md\n' >> "$r7/agents/reviewer.agent.md"
  mkdir -p "$r7/skills/worktrees"; _worktrees_skill_ok > "$r7/skills/worktrees/SKILL.md"
  printf 'skills/worktrees/SKILL.md\n' >> "$r7/agents/orchestrator.agent.md"
  mkdir -p "$r7/skills/verification"; _vbc_skill_ok > "$r7/skills/verification/SKILL.md"
  printf 'skills/verification/SKILL.md\n' >> "$r7/agents/engineer.agent.md"
  printf 'skills/verification/SKILL.md\n' >> "$r7/agents/orchestrator.agent.md"
  mkdir -p "$r7/skills/debugging"; _debugging_skill_ok > "$r7/skills/debugging/SKILL.md"
  printf 'skills/debugging/SKILL.md\n' >> "$r7/agents/engineer.agent.md"
  mkdir -p "$r7/skills/evals"; _evals_skill_ok > "$r7/skills/evals/SKILL.md"
  printf 'skills/evals/SKILL.md\n' >> "$r7/agents/engineer.agent.md"
  printf 'skills/evals/SKILL.md\n' >> "$r7/agents/security.agent.md"
  c7_fail=0
  mkdir -p "$r7/skills/using-skills"; _keystone_ok > "$r7/skills/using-skills/SKILL.md"
  printf 'skills/using-skills/SKILL.md\n' >> "$r7/agents/orchestrator.agent.md"
  mkdir -p "$r7/skills/continuous-discovery"; _discovery_skill_ok > "$r7/skills/continuous-discovery/SKILL.md"
  printf 'skills/continuous-discovery/SKILL.md\n' >> "$r7/agents/orchestrator.agent.md"
  mkdir -p "$r7/skills/operating"; _operating_skill_ok > "$r7/skills/operating/SKILL.md"
  printf 'skills/operating/SKILL.md\n' >> "$r7/agents/orchestrator.agent.md"
  (ORCH_LOOP_ROSTER_DIR="$r7/agents" ORCH_LOOP_SCRIPT="$r7/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r7/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r7/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r7/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r7/skills/tdd/SKILL.md" ORCH_LOOP_REVIEW_SKILL="$r7/skills/review/SKILL.md" ORCH_LOOP_WORKTREES_SKILL="$r7/skills/worktrees/SKILL.md" ORCH_LOOP_VBC_SKILL="$r7/skills/verification/SKILL.md" ORCH_LOOP_KEYSTONE="$r7/skills/using-skills/SKILL.md" ORCH_LOOP_DEBUGGING_SKILL="$r7/skills/debugging/SKILL.md" ORCH_LOOP_EVALS_SKILL="$r7/skills/evals/SKILL.md" ORCH_LOOP_DISCOVERY_SKILL="$r7/skills/continuous-discovery/SKILL.md" ORCH_LOOP_OPERATING_SKILL="$r7/skills/operating/SKILL.md" ORCH_LOOP_SECURITY_DEF="$r7/agents/security.agent.md" ORCH_LOOP_ORCH_DEF="$r7/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r7/agents/engineer.agent.md" ORCH_LOOP_REVIEWER_DEF="$r7/agents/reviewer.agent.md" sh "$0" >/dev/null 2>&1) || c7_fail=1
  if [ "$c7_fail" -eq 1 ]; then echo "selftest PASS: tdd skill missing a kit-distinctive marker -> exit 1"; else echo "selftest FAIL: absent tdd-skill marker NOT caught (tdd-skill teeth vacuous)"; sf=1; fi

  # -- case 8: tdd reference teeth -- conformant tdd skill but Engineer def OMITS the reference -> exit 1 --
  r8="$d/case8"; mkdir -p "$r8/agents" "$r8/scripts" "$r8/_gh_/workflows" "$r8/skills/design" "$r8/skills/plan" "$r8/skills/tdd"
  for f in $ROSTER_FILES; do _agent_ok > "$r8/agents/$f"; done
  printf '#!/bin/sh\nrunaway-guard.sh step\nkit.denied=true\nkit.conflict=false\ngit diff --name-only HEAD\n' > "$r8/scripts/orchestrator-run.sh"; chmod +x "$r8/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r8/_gh_/workflows/gp.yml"
  _skill_ok > "$r8/skills/design/SKILL.md"; _plan_skill_ok > "$r8/skills/plan/SKILL.md"; _tdd_skill_ok > "$r8/skills/tdd/SKILL.md"
  printf '\nskills/design/SKILL.md\nskills/plan/SKILL.md\n' >> "$r8/agents/orchestrator.agent.md"
  # NOTE: deliberately do NOT append 'skills/tdd/SKILL.md' to engineer.agent.md -> check_tdd_skill reference branch must fail
  mkdir -p "$r8/skills/review"; _review_skill_ok > "$r8/skills/review/SKILL.md"
  printf 'skills/review/SKILL.md\n' >> "$r8/agents/reviewer.agent.md"
  mkdir -p "$r8/skills/worktrees"; _worktrees_skill_ok > "$r8/skills/worktrees/SKILL.md"
  printf 'skills/worktrees/SKILL.md\n' >> "$r8/agents/orchestrator.agent.md"
  mkdir -p "$r8/skills/verification"; _vbc_skill_ok > "$r8/skills/verification/SKILL.md"
  printf 'skills/verification/SKILL.md\n' >> "$r8/agents/engineer.agent.md"
  printf 'skills/verification/SKILL.md\n' >> "$r8/agents/orchestrator.agent.md"
  mkdir -p "$r8/skills/debugging"; _debugging_skill_ok > "$r8/skills/debugging/SKILL.md"
  printf 'skills/debugging/SKILL.md\n' >> "$r8/agents/engineer.agent.md"
  mkdir -p "$r8/skills/evals"; _evals_skill_ok > "$r8/skills/evals/SKILL.md"
  printf 'skills/evals/SKILL.md\n' >> "$r8/agents/engineer.agent.md"
  printf 'skills/evals/SKILL.md\n' >> "$r8/agents/security.agent.md"
  c8_fail=0
  mkdir -p "$r8/skills/using-skills"; _keystone_ok > "$r8/skills/using-skills/SKILL.md"
  printf 'skills/using-skills/SKILL.md\n' >> "$r8/agents/orchestrator.agent.md"
  mkdir -p "$r8/skills/continuous-discovery"; _discovery_skill_ok > "$r8/skills/continuous-discovery/SKILL.md"
  printf 'skills/continuous-discovery/SKILL.md\n' >> "$r8/agents/orchestrator.agent.md"
  mkdir -p "$r8/skills/operating"; _operating_skill_ok > "$r8/skills/operating/SKILL.md"
  printf 'skills/operating/SKILL.md\n' >> "$r8/agents/orchestrator.agent.md"
  (ORCH_LOOP_ROSTER_DIR="$r8/agents" ORCH_LOOP_SCRIPT="$r8/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r8/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r8/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r8/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r8/skills/tdd/SKILL.md" ORCH_LOOP_REVIEW_SKILL="$r8/skills/review/SKILL.md" ORCH_LOOP_WORKTREES_SKILL="$r8/skills/worktrees/SKILL.md" ORCH_LOOP_VBC_SKILL="$r8/skills/verification/SKILL.md" ORCH_LOOP_KEYSTONE="$r8/skills/using-skills/SKILL.md" ORCH_LOOP_DEBUGGING_SKILL="$r8/skills/debugging/SKILL.md" ORCH_LOOP_EVALS_SKILL="$r8/skills/evals/SKILL.md" ORCH_LOOP_DISCOVERY_SKILL="$r8/skills/continuous-discovery/SKILL.md" ORCH_LOOP_OPERATING_SKILL="$r8/skills/operating/SKILL.md" ORCH_LOOP_SECURITY_DEF="$r8/agents/security.agent.md" ORCH_LOOP_ORCH_DEF="$r8/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r8/agents/engineer.agent.md" ORCH_LOOP_REVIEWER_DEF="$r8/agents/reviewer.agent.md" sh "$0" >/dev/null 2>&1) || c8_fail=1
  if [ "$c8_fail" -eq 1 ]; then echo "selftest PASS: Engineer def omits tdd reference -> exit 1"; else echo "selftest FAIL: missing tdd reference NOT caught (reference teeth vacuous)"; sf=1; fi

  # -- case 9: review-skill teeth -- review skill MISSING a kit-distinctive marker ('adversarial') -> exit 1 --
  r9="$d/case9"; mkdir -p "$r9/agents" "$r9/scripts" "$r9/_gh_/workflows" "$r9/skills/design" "$r9/skills/plan" "$r9/skills/tdd" "$r9/skills/review"
  for f in $ROSTER_FILES; do _agent_ok > "$r9/agents/$f"; done
  printf '#!/bin/sh\nrunaway-guard.sh step\nkit.denied=true\nkit.conflict=false\ngit diff --name-only HEAD\n' > "$r9/scripts/orchestrator-run.sh"; chmod +x "$r9/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r9/_gh_/workflows/gp.yml"
  _skill_ok > "$r9/skills/design/SKILL.md"; _plan_skill_ok > "$r9/skills/plan/SKILL.md"; _tdd_skill_ok > "$r9/skills/tdd/SKILL.md"
  # review skill present + referenced, but MISSING 'adversarial' -> check_review_skill fails
  printf -- '---\nname: review\n---\n## When to use\nx\nConfidence\nbuilder\nNEEDS-FIXES\n' > "$r9/skills/review/SKILL.md"
  printf '\nskills/design/SKILL.md\nskills/plan/SKILL.md\n' >> "$r9/agents/orchestrator.agent.md"
  printf 'skills/tdd/SKILL.md\n' >> "$r9/agents/engineer.agent.md"
  printf 'skills/review/SKILL.md\n' >> "$r9/agents/reviewer.agent.md"
  mkdir -p "$r9/skills/worktrees"; _worktrees_skill_ok > "$r9/skills/worktrees/SKILL.md"
  printf 'skills/worktrees/SKILL.md\n' >> "$r9/agents/orchestrator.agent.md"
  mkdir -p "$r9/skills/verification"; _vbc_skill_ok > "$r9/skills/verification/SKILL.md"
  printf 'skills/verification/SKILL.md\n' >> "$r9/agents/engineer.agent.md"
  printf 'skills/verification/SKILL.md\n' >> "$r9/agents/orchestrator.agent.md"
  mkdir -p "$r9/skills/debugging"; _debugging_skill_ok > "$r9/skills/debugging/SKILL.md"
  printf 'skills/debugging/SKILL.md\n' >> "$r9/agents/engineer.agent.md"
  mkdir -p "$r9/skills/evals"; _evals_skill_ok > "$r9/skills/evals/SKILL.md"
  printf 'skills/evals/SKILL.md\n' >> "$r9/agents/engineer.agent.md"
  printf 'skills/evals/SKILL.md\n' >> "$r9/agents/security.agent.md"
  c9_fail=0
  mkdir -p "$r9/skills/using-skills"; _keystone_ok > "$r9/skills/using-skills/SKILL.md"
  printf 'skills/using-skills/SKILL.md\n' >> "$r9/agents/orchestrator.agent.md"
  mkdir -p "$r9/skills/continuous-discovery"; _discovery_skill_ok > "$r9/skills/continuous-discovery/SKILL.md"
  printf 'skills/continuous-discovery/SKILL.md\n' >> "$r9/agents/orchestrator.agent.md"
  mkdir -p "$r9/skills/operating"; _operating_skill_ok > "$r9/skills/operating/SKILL.md"
  printf 'skills/operating/SKILL.md\n' >> "$r9/agents/orchestrator.agent.md"
  (ORCH_LOOP_ROSTER_DIR="$r9/agents" ORCH_LOOP_SCRIPT="$r9/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r9/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r9/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r9/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r9/skills/tdd/SKILL.md" ORCH_LOOP_REVIEW_SKILL="$r9/skills/review/SKILL.md" ORCH_LOOP_WORKTREES_SKILL="$r9/skills/worktrees/SKILL.md" ORCH_LOOP_VBC_SKILL="$r9/skills/verification/SKILL.md" ORCH_LOOP_KEYSTONE="$r9/skills/using-skills/SKILL.md" ORCH_LOOP_DEBUGGING_SKILL="$r9/skills/debugging/SKILL.md" ORCH_LOOP_EVALS_SKILL="$r9/skills/evals/SKILL.md" ORCH_LOOP_DISCOVERY_SKILL="$r9/skills/continuous-discovery/SKILL.md" ORCH_LOOP_OPERATING_SKILL="$r9/skills/operating/SKILL.md" ORCH_LOOP_SECURITY_DEF="$r9/agents/security.agent.md" ORCH_LOOP_ORCH_DEF="$r9/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r9/agents/engineer.agent.md" ORCH_LOOP_REVIEWER_DEF="$r9/agents/reviewer.agent.md" sh "$0" >/dev/null 2>&1) || c9_fail=1
  if [ "$c9_fail" -eq 1 ]; then echo "selftest PASS: review skill missing a kit-distinctive marker -> exit 1"; else echo "selftest FAIL: absent review-skill marker NOT caught"; sf=1; fi

  # -- case 10: review reference teeth -- conformant review skill but Reviewer def OMITS the reference -> exit 1 --
  r10="$d/case10"; mkdir -p "$r10/agents" "$r10/scripts" "$r10/_gh_/workflows" "$r10/skills/design" "$r10/skills/plan" "$r10/skills/tdd" "$r10/skills/review"
  for f in $ROSTER_FILES; do _agent_ok > "$r10/agents/$f"; done
  printf '#!/bin/sh\nrunaway-guard.sh step\nkit.denied=true\nkit.conflict=false\ngit diff --name-only HEAD\n' > "$r10/scripts/orchestrator-run.sh"; chmod +x "$r10/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r10/_gh_/workflows/gp.yml"
  _skill_ok > "$r10/skills/design/SKILL.md"; _plan_skill_ok > "$r10/skills/plan/SKILL.md"; _tdd_skill_ok > "$r10/skills/tdd/SKILL.md"
  _review_skill_ok > "$r10/skills/review/SKILL.md"
  printf '\nskills/design/SKILL.md\nskills/plan/SKILL.md\n' >> "$r10/agents/orchestrator.agent.md"
  printf 'skills/tdd/SKILL.md\n' >> "$r10/agents/engineer.agent.md"
  # NOTE: deliberately do NOT append 'skills/review/SKILL.md' to reviewer.agent.md -> check_review_skill reference branch must fail
  mkdir -p "$r10/skills/worktrees"; _worktrees_skill_ok > "$r10/skills/worktrees/SKILL.md"
  printf 'skills/worktrees/SKILL.md\n' >> "$r10/agents/orchestrator.agent.md"
  mkdir -p "$r10/skills/verification"; _vbc_skill_ok > "$r10/skills/verification/SKILL.md"
  printf 'skills/verification/SKILL.md\n' >> "$r10/agents/engineer.agent.md"
  printf 'skills/verification/SKILL.md\n' >> "$r10/agents/orchestrator.agent.md"
  mkdir -p "$r10/skills/debugging"; _debugging_skill_ok > "$r10/skills/debugging/SKILL.md"
  printf 'skills/debugging/SKILL.md\n' >> "$r10/agents/engineer.agent.md"
  mkdir -p "$r10/skills/evals"; _evals_skill_ok > "$r10/skills/evals/SKILL.md"
  printf 'skills/evals/SKILL.md\n' >> "$r10/agents/engineer.agent.md"
  printf 'skills/evals/SKILL.md\n' >> "$r10/agents/security.agent.md"
  c10_fail=0
  mkdir -p "$r10/skills/using-skills"; _keystone_ok > "$r10/skills/using-skills/SKILL.md"
  printf 'skills/using-skills/SKILL.md\n' >> "$r10/agents/orchestrator.agent.md"
  mkdir -p "$r10/skills/continuous-discovery"; _discovery_skill_ok > "$r10/skills/continuous-discovery/SKILL.md"
  printf 'skills/continuous-discovery/SKILL.md\n' >> "$r10/agents/orchestrator.agent.md"
  mkdir -p "$r10/skills/operating"; _operating_skill_ok > "$r10/skills/operating/SKILL.md"
  printf 'skills/operating/SKILL.md\n' >> "$r10/agents/orchestrator.agent.md"
  (ORCH_LOOP_ROSTER_DIR="$r10/agents" ORCH_LOOP_SCRIPT="$r10/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r10/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r10/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r10/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r10/skills/tdd/SKILL.md" ORCH_LOOP_REVIEW_SKILL="$r10/skills/review/SKILL.md" ORCH_LOOP_WORKTREES_SKILL="$r10/skills/worktrees/SKILL.md" ORCH_LOOP_VBC_SKILL="$r10/skills/verification/SKILL.md" ORCH_LOOP_KEYSTONE="$r10/skills/using-skills/SKILL.md" ORCH_LOOP_DEBUGGING_SKILL="$r10/skills/debugging/SKILL.md" ORCH_LOOP_EVALS_SKILL="$r10/skills/evals/SKILL.md" ORCH_LOOP_DISCOVERY_SKILL="$r10/skills/continuous-discovery/SKILL.md" ORCH_LOOP_OPERATING_SKILL="$r10/skills/operating/SKILL.md" ORCH_LOOP_SECURITY_DEF="$r10/agents/security.agent.md" ORCH_LOOP_ORCH_DEF="$r10/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r10/agents/engineer.agent.md" ORCH_LOOP_REVIEWER_DEF="$r10/agents/reviewer.agent.md" sh "$0" >/dev/null 2>&1) || c10_fail=1
  if [ "$c10_fail" -eq 1 ]; then echo "selftest PASS: Reviewer def omits review reference -> exit 1"; else echo "selftest FAIL: missing review reference NOT caught (reference teeth vacuous)"; sf=1; fi

  # -- case 11: worktrees-skill teeth -- worktrees skill MISSING a kit-distinctive marker ('disjoint file sets') -> exit 1 --
  r11="$d/case11"; mkdir -p "$r11/agents" "$r11/scripts" "$r11/_gh_/workflows" "$r11/skills/design" "$r11/skills/plan" "$r11/skills/tdd" "$r11/skills/review" "$r11/skills/worktrees"
  for f in $ROSTER_FILES; do _agent_ok > "$r11/agents/$f"; done
  printf '#!/bin/sh\nrunaway-guard.sh step\nkit.denied=true\nkit.conflict=false\ngit diff --name-only HEAD\n' > "$r11/scripts/orchestrator-run.sh"; chmod +x "$r11/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r11/_gh_/workflows/gp.yml"
  _skill_ok > "$r11/skills/design/SKILL.md"; _plan_skill_ok > "$r11/skills/plan/SKILL.md"; _tdd_skill_ok > "$r11/skills/tdd/SKILL.md"; _review_skill_ok > "$r11/skills/review/SKILL.md"
  # worktrees skill present + referenced, but MISSING the 'disjoint file sets' marker -> check_worktrees_skill fails
  printf -- '---\nname: worktrees\n---\n## When to use\nx\n--no-renames\nout-of-slice\nnative\n' > "$r11/skills/worktrees/SKILL.md"
  printf '\nskills/design/SKILL.md\nskills/plan/SKILL.md\nskills/worktrees/SKILL.md\n' >> "$r11/agents/orchestrator.agent.md"
  printf 'skills/tdd/SKILL.md\n' >> "$r11/agents/engineer.agent.md"
  printf 'skills/review/SKILL.md\n' >> "$r11/agents/reviewer.agent.md"
  mkdir -p "$r11/skills/verification"; _vbc_skill_ok > "$r11/skills/verification/SKILL.md"
  printf 'skills/verification/SKILL.md\n' >> "$r11/agents/engineer.agent.md"
  printf 'skills/verification/SKILL.md\n' >> "$r11/agents/orchestrator.agent.md"
  mkdir -p "$r11/skills/debugging"; _debugging_skill_ok > "$r11/skills/debugging/SKILL.md"
  printf 'skills/debugging/SKILL.md\n' >> "$r11/agents/engineer.agent.md"
  mkdir -p "$r11/skills/evals"; _evals_skill_ok > "$r11/skills/evals/SKILL.md"
  printf 'skills/evals/SKILL.md\n' >> "$r11/agents/engineer.agent.md"
  printf 'skills/evals/SKILL.md\n' >> "$r11/agents/security.agent.md"
  c11_fail=0
  mkdir -p "$r11/skills/using-skills"; _keystone_ok > "$r11/skills/using-skills/SKILL.md"
  printf 'skills/using-skills/SKILL.md\n' >> "$r11/agents/orchestrator.agent.md"
  mkdir -p "$r11/skills/continuous-discovery"; _discovery_skill_ok > "$r11/skills/continuous-discovery/SKILL.md"
  printf 'skills/continuous-discovery/SKILL.md\n' >> "$r11/agents/orchestrator.agent.md"
  mkdir -p "$r11/skills/operating"; _operating_skill_ok > "$r11/skills/operating/SKILL.md"
  printf 'skills/operating/SKILL.md\n' >> "$r11/agents/orchestrator.agent.md"
  (ORCH_LOOP_ROSTER_DIR="$r11/agents" ORCH_LOOP_SCRIPT="$r11/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r11/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r11/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r11/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r11/skills/tdd/SKILL.md" ORCH_LOOP_REVIEW_SKILL="$r11/skills/review/SKILL.md" ORCH_LOOP_WORKTREES_SKILL="$r11/skills/worktrees/SKILL.md" ORCH_LOOP_VBC_SKILL="$r11/skills/verification/SKILL.md" ORCH_LOOP_KEYSTONE="$r11/skills/using-skills/SKILL.md" ORCH_LOOP_DEBUGGING_SKILL="$r11/skills/debugging/SKILL.md" ORCH_LOOP_EVALS_SKILL="$r11/skills/evals/SKILL.md" ORCH_LOOP_DISCOVERY_SKILL="$r11/skills/continuous-discovery/SKILL.md" ORCH_LOOP_OPERATING_SKILL="$r11/skills/operating/SKILL.md" ORCH_LOOP_SECURITY_DEF="$r11/agents/security.agent.md" ORCH_LOOP_ORCH_DEF="$r11/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r11/agents/engineer.agent.md" ORCH_LOOP_REVIEWER_DEF="$r11/agents/reviewer.agent.md" sh "$0" >/dev/null 2>&1) || c11_fail=1
  if [ "$c11_fail" -eq 1 ]; then echo "selftest PASS: worktrees skill missing a kit-distinctive marker -> exit 1"; else echo "selftest FAIL: absent worktrees-skill marker NOT caught (worktrees-skill teeth vacuous)"; sf=1; fi

  # -- case 12: worktrees reference teeth -- conformant worktrees skill but Orchestrator def OMITS the reference -> exit 1 --
  r12="$d/case12"; mkdir -p "$r12/agents" "$r12/scripts" "$r12/_gh_/workflows" "$r12/skills/design" "$r12/skills/plan" "$r12/skills/tdd" "$r12/skills/review" "$r12/skills/worktrees"
  for f in $ROSTER_FILES; do _agent_ok > "$r12/agents/$f"; done
  printf '#!/bin/sh\nrunaway-guard.sh step\nkit.denied=true\nkit.conflict=false\ngit diff --name-only HEAD\n' > "$r12/scripts/orchestrator-run.sh"; chmod +x "$r12/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r12/_gh_/workflows/gp.yml"
  _skill_ok > "$r12/skills/design/SKILL.md"; _plan_skill_ok > "$r12/skills/plan/SKILL.md"; _tdd_skill_ok > "$r12/skills/tdd/SKILL.md"; _review_skill_ok > "$r12/skills/review/SKILL.md"
  _worktrees_skill_ok > "$r12/skills/worktrees/SKILL.md"
  printf '\nskills/design/SKILL.md\nskills/plan/SKILL.md\n' >> "$r12/agents/orchestrator.agent.md"
  printf 'skills/tdd/SKILL.md\n' >> "$r12/agents/engineer.agent.md"
  printf 'skills/review/SKILL.md\n' >> "$r12/agents/reviewer.agent.md"
  # NOTE: deliberately do NOT append 'skills/worktrees/SKILL.md' to orchestrator.agent.md -> check_worktrees_skill reference branch must fail
  mkdir -p "$r12/skills/verification"; _vbc_skill_ok > "$r12/skills/verification/SKILL.md"
  printf 'skills/verification/SKILL.md\n' >> "$r12/agents/engineer.agent.md"
  printf 'skills/verification/SKILL.md\n' >> "$r12/agents/orchestrator.agent.md"
  mkdir -p "$r12/skills/debugging"; _debugging_skill_ok > "$r12/skills/debugging/SKILL.md"
  printf 'skills/debugging/SKILL.md\n' >> "$r12/agents/engineer.agent.md"
  mkdir -p "$r12/skills/evals"; _evals_skill_ok > "$r12/skills/evals/SKILL.md"
  printf 'skills/evals/SKILL.md\n' >> "$r12/agents/engineer.agent.md"
  printf 'skills/evals/SKILL.md\n' >> "$r12/agents/security.agent.md"
  c12_fail=0
  mkdir -p "$r12/skills/using-skills"; _keystone_ok > "$r12/skills/using-skills/SKILL.md"
  printf 'skills/using-skills/SKILL.md\n' >> "$r12/agents/orchestrator.agent.md"
  mkdir -p "$r12/skills/continuous-discovery"; _discovery_skill_ok > "$r12/skills/continuous-discovery/SKILL.md"
  printf 'skills/continuous-discovery/SKILL.md\n' >> "$r12/agents/orchestrator.agent.md"
  mkdir -p "$r12/skills/operating"; _operating_skill_ok > "$r12/skills/operating/SKILL.md"
  printf 'skills/operating/SKILL.md\n' >> "$r12/agents/orchestrator.agent.md"
  (ORCH_LOOP_ROSTER_DIR="$r12/agents" ORCH_LOOP_SCRIPT="$r12/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r12/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r12/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r12/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r12/skills/tdd/SKILL.md" ORCH_LOOP_REVIEW_SKILL="$r12/skills/review/SKILL.md" ORCH_LOOP_WORKTREES_SKILL="$r12/skills/worktrees/SKILL.md" ORCH_LOOP_VBC_SKILL="$r12/skills/verification/SKILL.md" ORCH_LOOP_KEYSTONE="$r12/skills/using-skills/SKILL.md" ORCH_LOOP_DEBUGGING_SKILL="$r12/skills/debugging/SKILL.md" ORCH_LOOP_EVALS_SKILL="$r12/skills/evals/SKILL.md" ORCH_LOOP_DISCOVERY_SKILL="$r12/skills/continuous-discovery/SKILL.md" ORCH_LOOP_OPERATING_SKILL="$r12/skills/operating/SKILL.md" ORCH_LOOP_SECURITY_DEF="$r12/agents/security.agent.md" ORCH_LOOP_ORCH_DEF="$r12/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r12/agents/engineer.agent.md" ORCH_LOOP_REVIEWER_DEF="$r12/agents/reviewer.agent.md" sh "$0" >/dev/null 2>&1) || c12_fail=1
  if [ "$c12_fail" -eq 1 ]; then echo "selftest PASS: Orchestrator def omits worktrees reference -> exit 1"; else echo "selftest FAIL: missing worktrees reference NOT caught (reference teeth vacuous)"; sf=1; fi

  # -- case 13: verification-skill marker teeth -- verification skill MISSING a kit-distinctive marker ('confabulation') -> exit 1 --
  r13="$d/case13"; mkdir -p "$r13/agents" "$r13/scripts" "$r13/_gh_/workflows" "$r13/skills/design" "$r13/skills/plan" "$r13/skills/tdd" "$r13/skills/review" "$r13/skills/worktrees" "$r13/skills/verification"
  for f in $ROSTER_FILES; do _agent_ok > "$r13/agents/$f"; done
  printf '#!/bin/sh\nrunaway-guard.sh step\nkit.denied=true\nkit.conflict=false\ngit diff --name-only HEAD\n' > "$r13/scripts/orchestrator-run.sh"; chmod +x "$r13/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r13/_gh_/workflows/gp.yml"
  _skill_ok > "$r13/skills/design/SKILL.md"; _plan_skill_ok > "$r13/skills/plan/SKILL.md"; _tdd_skill_ok > "$r13/skills/tdd/SKILL.md"; _review_skill_ok > "$r13/skills/review/SKILL.md"; _worktrees_skill_ok > "$r13/skills/worktrees/SKILL.md"
  # verification skill present + both refs, but MISSING the 'confabulation' marker -> check_vbc_skill fails
  printf -- '---\nname: verification\n---\n## When to use\nx\nclone dry-run\nevidence before claims\nfresh\n' > "$r13/skills/verification/SKILL.md"
  printf '\nskills/design/SKILL.md\nskills/plan/SKILL.md\nskills/worktrees/SKILL.md\nskills/verification/SKILL.md\n' >> "$r13/agents/orchestrator.agent.md"
  printf 'skills/tdd/SKILL.md\nskills/verification/SKILL.md\n' >> "$r13/agents/engineer.agent.md"
  printf 'skills/review/SKILL.md\n' >> "$r13/agents/reviewer.agent.md"
  mkdir -p "$r13/skills/debugging"; _debugging_skill_ok > "$r13/skills/debugging/SKILL.md"
  printf 'skills/debugging/SKILL.md\n' >> "$r13/agents/engineer.agent.md"
  mkdir -p "$r13/skills/evals"; _evals_skill_ok > "$r13/skills/evals/SKILL.md"
  printf 'skills/evals/SKILL.md\n' >> "$r13/agents/engineer.agent.md"
  printf 'skills/evals/SKILL.md\n' >> "$r13/agents/security.agent.md"
  c13_fail=0
  mkdir -p "$r13/skills/using-skills"; _keystone_ok > "$r13/skills/using-skills/SKILL.md"
  printf 'skills/using-skills/SKILL.md\n' >> "$r13/agents/orchestrator.agent.md"
  mkdir -p "$r13/skills/continuous-discovery"; _discovery_skill_ok > "$r13/skills/continuous-discovery/SKILL.md"
  printf 'skills/continuous-discovery/SKILL.md\n' >> "$r13/agents/orchestrator.agent.md"
  mkdir -p "$r13/skills/operating"; _operating_skill_ok > "$r13/skills/operating/SKILL.md"
  printf 'skills/operating/SKILL.md\n' >> "$r13/agents/orchestrator.agent.md"
  (ORCH_LOOP_ROSTER_DIR="$r13/agents" ORCH_LOOP_SCRIPT="$r13/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r13/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r13/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r13/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r13/skills/tdd/SKILL.md" ORCH_LOOP_REVIEW_SKILL="$r13/skills/review/SKILL.md" ORCH_LOOP_WORKTREES_SKILL="$r13/skills/worktrees/SKILL.md" ORCH_LOOP_VBC_SKILL="$r13/skills/verification/SKILL.md" ORCH_LOOP_KEYSTONE="$r13/skills/using-skills/SKILL.md" ORCH_LOOP_DEBUGGING_SKILL="$r13/skills/debugging/SKILL.md" ORCH_LOOP_EVALS_SKILL="$r13/skills/evals/SKILL.md" ORCH_LOOP_DISCOVERY_SKILL="$r13/skills/continuous-discovery/SKILL.md" ORCH_LOOP_OPERATING_SKILL="$r13/skills/operating/SKILL.md" ORCH_LOOP_SECURITY_DEF="$r13/agents/security.agent.md" ORCH_LOOP_ORCH_DEF="$r13/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r13/agents/engineer.agent.md" ORCH_LOOP_REVIEWER_DEF="$r13/agents/reviewer.agent.md" sh "$0" >/dev/null 2>&1) || c13_fail=1
  if [ "$c13_fail" -eq 1 ]; then echo "selftest PASS: verification skill missing a kit-distinctive marker -> exit 1"; else echo "selftest FAIL: absent verification-skill marker NOT caught (marker teeth vacuous)"; sf=1; fi

  # -- case 14: verification Engineer-reference teeth -- conformant skill + Orchestrator ref present, but ENGINEER def OMITS the reference -> exit 1 --
  r14="$d/case14"; mkdir -p "$r14/agents" "$r14/scripts" "$r14/_gh_/workflows" "$r14/skills/design" "$r14/skills/plan" "$r14/skills/tdd" "$r14/skills/review" "$r14/skills/worktrees" "$r14/skills/verification"
  for f in $ROSTER_FILES; do _agent_ok > "$r14/agents/$f"; done
  printf '#!/bin/sh\nrunaway-guard.sh step\nkit.denied=true\nkit.conflict=false\ngit diff --name-only HEAD\n' > "$r14/scripts/orchestrator-run.sh"; chmod +x "$r14/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r14/_gh_/workflows/gp.yml"
  _skill_ok > "$r14/skills/design/SKILL.md"; _plan_skill_ok > "$r14/skills/plan/SKILL.md"; _tdd_skill_ok > "$r14/skills/tdd/SKILL.md"; _review_skill_ok > "$r14/skills/review/SKILL.md"; _worktrees_skill_ok > "$r14/skills/worktrees/SKILL.md"
  _vbc_skill_ok > "$r14/skills/verification/SKILL.md"
  printf '\nskills/design/SKILL.md\nskills/plan/SKILL.md\nskills/worktrees/SKILL.md\nskills/verification/SKILL.md\n' >> "$r14/agents/orchestrator.agent.md"
  printf 'skills/tdd/SKILL.md\n' >> "$r14/agents/engineer.agent.md"
  printf 'skills/review/SKILL.md\n' >> "$r14/agents/reviewer.agent.md"
  # NOTE: deliberately do NOT append 'skills/verification/SKILL.md' to engineer.agent.md -> check_vbc_skill Engineer-reference branch must fail
  mkdir -p "$r14/skills/debugging"; _debugging_skill_ok > "$r14/skills/debugging/SKILL.md"
  printf 'skills/debugging/SKILL.md\n' >> "$r14/agents/engineer.agent.md"
  mkdir -p "$r14/skills/evals"; _evals_skill_ok > "$r14/skills/evals/SKILL.md"
  printf 'skills/evals/SKILL.md\n' >> "$r14/agents/engineer.agent.md"
  printf 'skills/evals/SKILL.md\n' >> "$r14/agents/security.agent.md"
  c14_fail=0
  mkdir -p "$r14/skills/using-skills"; _keystone_ok > "$r14/skills/using-skills/SKILL.md"
  printf 'skills/using-skills/SKILL.md\n' >> "$r14/agents/orchestrator.agent.md"
  mkdir -p "$r14/skills/continuous-discovery"; _discovery_skill_ok > "$r14/skills/continuous-discovery/SKILL.md"
  printf 'skills/continuous-discovery/SKILL.md\n' >> "$r14/agents/orchestrator.agent.md"
  mkdir -p "$r14/skills/operating"; _operating_skill_ok > "$r14/skills/operating/SKILL.md"
  printf 'skills/operating/SKILL.md\n' >> "$r14/agents/orchestrator.agent.md"
  (ORCH_LOOP_ROSTER_DIR="$r14/agents" ORCH_LOOP_SCRIPT="$r14/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r14/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r14/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r14/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r14/skills/tdd/SKILL.md" ORCH_LOOP_REVIEW_SKILL="$r14/skills/review/SKILL.md" ORCH_LOOP_WORKTREES_SKILL="$r14/skills/worktrees/SKILL.md" ORCH_LOOP_VBC_SKILL="$r14/skills/verification/SKILL.md" ORCH_LOOP_KEYSTONE="$r14/skills/using-skills/SKILL.md" ORCH_LOOP_DEBUGGING_SKILL="$r14/skills/debugging/SKILL.md" ORCH_LOOP_EVALS_SKILL="$r14/skills/evals/SKILL.md" ORCH_LOOP_DISCOVERY_SKILL="$r14/skills/continuous-discovery/SKILL.md" ORCH_LOOP_OPERATING_SKILL="$r14/skills/operating/SKILL.md" ORCH_LOOP_SECURITY_DEF="$r14/agents/security.agent.md" ORCH_LOOP_ORCH_DEF="$r14/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r14/agents/engineer.agent.md" ORCH_LOOP_REVIEWER_DEF="$r14/agents/reviewer.agent.md" sh "$0" >/dev/null 2>&1) || c14_fail=1
  if [ "$c14_fail" -eq 1 ]; then echo "selftest PASS: Engineer def omits verification reference -> exit 1"; else echo "selftest FAIL: missing Engineer verification reference NOT caught (Engineer reference teeth vacuous)"; sf=1; fi

  # -- case 15: verification Orchestrator-reference teeth -- conformant skill + Engineer ref present, but ORCHESTRATOR def OMITS the reference -> exit 1 --
  r15="$d/case15"; mkdir -p "$r15/agents" "$r15/scripts" "$r15/_gh_/workflows" "$r15/skills/design" "$r15/skills/plan" "$r15/skills/tdd" "$r15/skills/review" "$r15/skills/worktrees" "$r15/skills/verification"
  for f in $ROSTER_FILES; do _agent_ok > "$r15/agents/$f"; done
  printf '#!/bin/sh\nrunaway-guard.sh step\nkit.denied=true\nkit.conflict=false\ngit diff --name-only HEAD\n' > "$r15/scripts/orchestrator-run.sh"; chmod +x "$r15/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r15/_gh_/workflows/gp.yml"
  _skill_ok > "$r15/skills/design/SKILL.md"; _plan_skill_ok > "$r15/skills/plan/SKILL.md"; _tdd_skill_ok > "$r15/skills/tdd/SKILL.md"; _review_skill_ok > "$r15/skills/review/SKILL.md"; _worktrees_skill_ok > "$r15/skills/worktrees/SKILL.md"
  _vbc_skill_ok > "$r15/skills/verification/SKILL.md"
  printf '\nskills/design/SKILL.md\nskills/plan/SKILL.md\nskills/worktrees/SKILL.md\n' >> "$r15/agents/orchestrator.agent.md"
  printf 'skills/tdd/SKILL.md\nskills/verification/SKILL.md\n' >> "$r15/agents/engineer.agent.md"
  printf 'skills/review/SKILL.md\n' >> "$r15/agents/reviewer.agent.md"
  # NOTE: deliberately do NOT append 'skills/verification/SKILL.md' to orchestrator.agent.md -> check_vbc_skill Orchestrator-reference branch must fail
  mkdir -p "$r15/skills/debugging"; _debugging_skill_ok > "$r15/skills/debugging/SKILL.md"
  printf 'skills/debugging/SKILL.md\n' >> "$r15/agents/engineer.agent.md"
  mkdir -p "$r15/skills/evals"; _evals_skill_ok > "$r15/skills/evals/SKILL.md"
  printf 'skills/evals/SKILL.md\n' >> "$r15/agents/engineer.agent.md"
  printf 'skills/evals/SKILL.md\n' >> "$r15/agents/security.agent.md"
  c15_fail=0
  mkdir -p "$r15/skills/using-skills"; _keystone_ok > "$r15/skills/using-skills/SKILL.md"
  printf 'skills/using-skills/SKILL.md\n' >> "$r15/agents/orchestrator.agent.md"
  mkdir -p "$r15/skills/continuous-discovery"; _discovery_skill_ok > "$r15/skills/continuous-discovery/SKILL.md"
  printf 'skills/continuous-discovery/SKILL.md\n' >> "$r15/agents/orchestrator.agent.md"
  mkdir -p "$r15/skills/operating"; _operating_skill_ok > "$r15/skills/operating/SKILL.md"
  printf 'skills/operating/SKILL.md\n' >> "$r15/agents/orchestrator.agent.md"
  (ORCH_LOOP_ROSTER_DIR="$r15/agents" ORCH_LOOP_SCRIPT="$r15/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r15/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r15/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r15/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r15/skills/tdd/SKILL.md" ORCH_LOOP_REVIEW_SKILL="$r15/skills/review/SKILL.md" ORCH_LOOP_WORKTREES_SKILL="$r15/skills/worktrees/SKILL.md" ORCH_LOOP_VBC_SKILL="$r15/skills/verification/SKILL.md" ORCH_LOOP_KEYSTONE="$r15/skills/using-skills/SKILL.md" ORCH_LOOP_DEBUGGING_SKILL="$r15/skills/debugging/SKILL.md" ORCH_LOOP_EVALS_SKILL="$r15/skills/evals/SKILL.md" ORCH_LOOP_DISCOVERY_SKILL="$r15/skills/continuous-discovery/SKILL.md" ORCH_LOOP_OPERATING_SKILL="$r15/skills/operating/SKILL.md" ORCH_LOOP_SECURITY_DEF="$r15/agents/security.agent.md" ORCH_LOOP_ORCH_DEF="$r15/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r15/agents/engineer.agent.md" ORCH_LOOP_REVIEWER_DEF="$r15/agents/reviewer.agent.md" sh "$0" >/dev/null 2>&1) || c15_fail=1
  if [ "$c15_fail" -eq 1 ]; then echo "selftest PASS: Orchestrator def omits verification reference -> exit 1"; else echo "selftest FAIL: missing Orchestrator verification reference NOT caught (Orchestrator reference teeth vacuous)"; sf=1; fi

  # -- case 16: keystone index teeth -- conformant tree, but the using-skills keystone is MISSING one index path (drop 'skills/verification') -> exit 1 --
  r16="$d/case16"; mkdir -p "$r16/agents" "$r16/scripts" "$r16/_gh_/workflows" "$r16/skills/design" "$r16/skills/plan" "$r16/skills/tdd" "$r16/skills/review" "$r16/skills/worktrees" "$r16/skills/verification" "$r16/skills/using-skills"
  for f in $ROSTER_FILES; do _agent_ok > "$r16/agents/$f"; done
  printf '#!/bin/sh\nrunaway-guard.sh step\nkit.denied=true\nkit.conflict=false\ngit diff --name-only HEAD\n' > "$r16/scripts/orchestrator-run.sh"; chmod +x "$r16/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r16/_gh_/workflows/gp.yml"
  _skill_ok > "$r16/skills/design/SKILL.md"; _plan_skill_ok > "$r16/skills/plan/SKILL.md"; _tdd_skill_ok > "$r16/skills/tdd/SKILL.md"; _review_skill_ok > "$r16/skills/review/SKILL.md"; _worktrees_skill_ok > "$r16/skills/worktrees/SKILL.md"; _vbc_skill_ok > "$r16/skills/verification/SKILL.md"
  # keystone present + referenced, but the index DROPS 'skills/verification' (lists every OTHER on-disk skill, incl. skills/evals) -> check_keystone index branch must fail for that one omission only
  printf -- '---\nname: using-skills\n---\n## When to use\nx\ninvoke by reading\nbefore acting\nuser instructions\nskills/design\nskills/plan\nskills/tdd\nskills/review\nskills/worktrees\nskills/debugging\nskills/evals\nskills/continuous-discovery\n' > "$r16/skills/using-skills/SKILL.md"
  printf '\nskills/design/SKILL.md\nskills/plan/SKILL.md\nskills/worktrees/SKILL.md\nskills/verification/SKILL.md\nskills/using-skills/SKILL.md\n' >> "$r16/agents/orchestrator.agent.md"
  printf 'skills/tdd/SKILL.md\nskills/verification/SKILL.md\n' >> "$r16/agents/engineer.agent.md"
  printf 'skills/review/SKILL.md\n' >> "$r16/agents/reviewer.agent.md"
  mkdir -p "$r16/skills/debugging"; _debugging_skill_ok > "$r16/skills/debugging/SKILL.md"
  printf 'skills/debugging/SKILL.md\n' >> "$r16/agents/engineer.agent.md"
  mkdir -p "$r16/skills/evals"; _evals_skill_ok > "$r16/skills/evals/SKILL.md"
  printf 'skills/evals/SKILL.md\n' >> "$r16/agents/engineer.agent.md"
  printf 'skills/evals/SKILL.md\n' >> "$r16/agents/security.agent.md"
  c16_fail=0
  mkdir -p "$r16/skills/continuous-discovery"; _discovery_skill_ok > "$r16/skills/continuous-discovery/SKILL.md"
  printf 'skills/continuous-discovery/SKILL.md\n' >> "$r16/agents/orchestrator.agent.md"
  mkdir -p "$r16/skills/operating"; _operating_skill_ok > "$r16/skills/operating/SKILL.md"
  printf 'skills/operating/SKILL.md\n' >> "$r16/agents/orchestrator.agent.md"
  (ORCH_LOOP_ROSTER_DIR="$r16/agents" ORCH_LOOP_SCRIPT="$r16/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r16/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r16/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r16/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r16/skills/tdd/SKILL.md" ORCH_LOOP_REVIEW_SKILL="$r16/skills/review/SKILL.md" ORCH_LOOP_WORKTREES_SKILL="$r16/skills/worktrees/SKILL.md" ORCH_LOOP_VBC_SKILL="$r16/skills/verification/SKILL.md" ORCH_LOOP_KEYSTONE="$r16/skills/using-skills/SKILL.md" ORCH_LOOP_DEBUGGING_SKILL="$r16/skills/debugging/SKILL.md" ORCH_LOOP_EVALS_SKILL="$r16/skills/evals/SKILL.md" ORCH_LOOP_DISCOVERY_SKILL="$r16/skills/continuous-discovery/SKILL.md" ORCH_LOOP_OPERATING_SKILL="$r16/skills/operating/SKILL.md" ORCH_LOOP_SECURITY_DEF="$r16/agents/security.agent.md" ORCH_LOOP_ORCH_DEF="$r16/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r16/agents/engineer.agent.md" ORCH_LOOP_REVIEWER_DEF="$r16/agents/reviewer.agent.md" sh "$0" >/dev/null 2>&1) || c16_fail=1
  if [ "$c16_fail" -eq 1 ]; then echo "selftest PASS: keystone missing an index path -> exit 1"; else echo "selftest FAIL: keystone with an incomplete index NOT caught (index teeth vacuous)"; sf=1; fi

  # -- case 17: keystone reference teeth -- conformant keystone (every on-disk index path), but the Orchestrator def does NOT reference the keystone -> exit 1 --
  r17="$d/case17"; mkdir -p "$r17/agents" "$r17/scripts" "$r17/_gh_/workflows" "$r17/skills/design" "$r17/skills/plan" "$r17/skills/tdd" "$r17/skills/review" "$r17/skills/worktrees" "$r17/skills/verification" "$r17/skills/using-skills"
  for f in $ROSTER_FILES; do _agent_ok > "$r17/agents/$f"; done
  printf '#!/bin/sh\nrunaway-guard.sh step\nkit.denied=true\nkit.conflict=false\ngit diff --name-only HEAD\n' > "$r17/scripts/orchestrator-run.sh"; chmod +x "$r17/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r17/_gh_/workflows/gp.yml"
  _skill_ok > "$r17/skills/design/SKILL.md"; _plan_skill_ok > "$r17/skills/plan/SKILL.md"; _tdd_skill_ok > "$r17/skills/tdd/SKILL.md"; _review_skill_ok > "$r17/skills/review/SKILL.md"; _worktrees_skill_ok > "$r17/skills/worktrees/SKILL.md"; _vbc_skill_ok > "$r17/skills/verification/SKILL.md"
  _keystone_ok > "$r17/skills/using-skills/SKILL.md"
  printf '\nskills/design/SKILL.md\nskills/plan/SKILL.md\nskills/worktrees/SKILL.md\nskills/verification/SKILL.md\n' >> "$r17/agents/orchestrator.agent.md"
  printf 'skills/tdd/SKILL.md\nskills/verification/SKILL.md\n' >> "$r17/agents/engineer.agent.md"
  printf 'skills/review/SKILL.md\n' >> "$r17/agents/reviewer.agent.md"
  # NOTE: deliberately do NOT append 'skills/using-skills/SKILL.md' to orchestrator.agent.md -> check_keystone reference branch must fail
  mkdir -p "$r17/skills/debugging"; _debugging_skill_ok > "$r17/skills/debugging/SKILL.md"
  printf 'skills/debugging/SKILL.md\n' >> "$r17/agents/engineer.agent.md"
  mkdir -p "$r17/skills/evals"; _evals_skill_ok > "$r17/skills/evals/SKILL.md"
  printf 'skills/evals/SKILL.md\n' >> "$r17/agents/engineer.agent.md"
  printf 'skills/evals/SKILL.md\n' >> "$r17/agents/security.agent.md"
  c17_fail=0
  mkdir -p "$r17/skills/continuous-discovery"; _discovery_skill_ok > "$r17/skills/continuous-discovery/SKILL.md"
  printf 'skills/continuous-discovery/SKILL.md\n' >> "$r17/agents/orchestrator.agent.md"
  mkdir -p "$r17/skills/operating"; _operating_skill_ok > "$r17/skills/operating/SKILL.md"
  printf 'skills/operating/SKILL.md\n' >> "$r17/agents/orchestrator.agent.md"
  (ORCH_LOOP_ROSTER_DIR="$r17/agents" ORCH_LOOP_SCRIPT="$r17/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r17/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r17/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r17/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r17/skills/tdd/SKILL.md" ORCH_LOOP_REVIEW_SKILL="$r17/skills/review/SKILL.md" ORCH_LOOP_WORKTREES_SKILL="$r17/skills/worktrees/SKILL.md" ORCH_LOOP_VBC_SKILL="$r17/skills/verification/SKILL.md" ORCH_LOOP_KEYSTONE="$r17/skills/using-skills/SKILL.md" ORCH_LOOP_DEBUGGING_SKILL="$r17/skills/debugging/SKILL.md" ORCH_LOOP_EVALS_SKILL="$r17/skills/evals/SKILL.md" ORCH_LOOP_DISCOVERY_SKILL="$r17/skills/continuous-discovery/SKILL.md" ORCH_LOOP_OPERATING_SKILL="$r17/skills/operating/SKILL.md" ORCH_LOOP_SECURITY_DEF="$r17/agents/security.agent.md" ORCH_LOOP_ORCH_DEF="$r17/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r17/agents/engineer.agent.md" ORCH_LOOP_REVIEWER_DEF="$r17/agents/reviewer.agent.md" sh "$0" >/dev/null 2>&1) || c17_fail=1
  if [ "$c17_fail" -eq 1 ]; then echo "selftest PASS: Orchestrator def omits keystone reference -> exit 1"; else echo "selftest FAIL: missing keystone reference NOT caught (reference teeth vacuous)"; sf=1; fi

  # -- case 18: debugging marker teeth -- conformant tree, but the debugging skill is MISSING one marker (drop 'regression test') -> exit 1 --
  r18="$d/case18"; mkdir -p "$r18/agents" "$r18/scripts" "$r18/_gh_/workflows" "$r18/skills/design" "$r18/skills/plan" "$r18/skills/tdd" "$r18/skills/review" "$r18/skills/worktrees" "$r18/skills/verification" "$r18/skills/using-skills" "$r18/skills/debugging"
  for f in $ROSTER_FILES; do _agent_ok > "$r18/agents/$f"; done
  printf '#!/bin/sh\nrunaway-guard.sh step\nkit.denied=true\nkit.conflict=false\ngit diff --name-only HEAD\n' > "$r18/scripts/orchestrator-run.sh"; chmod +x "$r18/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r18/_gh_/workflows/gp.yml"
  _skill_ok > "$r18/skills/design/SKILL.md"; _plan_skill_ok > "$r18/skills/plan/SKILL.md"; _tdd_skill_ok > "$r18/skills/tdd/SKILL.md"; _review_skill_ok > "$r18/skills/review/SKILL.md"; _worktrees_skill_ok > "$r18/skills/worktrees/SKILL.md"; _vbc_skill_ok > "$r18/skills/verification/SKILL.md"; _keystone_ok > "$r18/skills/using-skills/SKILL.md"
  printf '\nskills/design/SKILL.md\nskills/plan/SKILL.md\nskills/worktrees/SKILL.md\nskills/verification/SKILL.md\nskills/using-skills/SKILL.md\n' >> "$r18/agents/orchestrator.agent.md"
  printf 'skills/tdd/SKILL.md\nskills/verification/SKILL.md\n' >> "$r18/agents/engineer.agent.md"
  printf 'skills/review/SKILL.md\n' >> "$r18/agents/reviewer.agent.md"
  # debugging skill present + Engineer references it, but the skill is MISSING the 'regression test' marker -> check_debugging_skill marker branch must fail
  printf -- '---\nname: debugging\n---\n## When to use\nx\nroot cause\nreproduce\none hypothesis\n' > "$r18/skills/debugging/SKILL.md"
  printf 'skills/debugging/SKILL.md\n' >> "$r18/agents/engineer.agent.md"
  mkdir -p "$r18/skills/evals"; _evals_skill_ok > "$r18/skills/evals/SKILL.md"
  printf 'skills/evals/SKILL.md\n' >> "$r18/agents/engineer.agent.md"
  printf 'skills/evals/SKILL.md\n' >> "$r18/agents/security.agent.md"
  c18_fail=0
  mkdir -p "$r18/skills/continuous-discovery"; _discovery_skill_ok > "$r18/skills/continuous-discovery/SKILL.md"
  printf 'skills/continuous-discovery/SKILL.md\n' >> "$r18/agents/orchestrator.agent.md"
  mkdir -p "$r18/skills/operating"; _operating_skill_ok > "$r18/skills/operating/SKILL.md"
  printf 'skills/operating/SKILL.md\n' >> "$r18/agents/orchestrator.agent.md"
  (ORCH_LOOP_ROSTER_DIR="$r18/agents" ORCH_LOOP_SCRIPT="$r18/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r18/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r18/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r18/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r18/skills/tdd/SKILL.md" ORCH_LOOP_REVIEW_SKILL="$r18/skills/review/SKILL.md" ORCH_LOOP_WORKTREES_SKILL="$r18/skills/worktrees/SKILL.md" ORCH_LOOP_VBC_SKILL="$r18/skills/verification/SKILL.md" ORCH_LOOP_KEYSTONE="$r18/skills/using-skills/SKILL.md" ORCH_LOOP_DEBUGGING_SKILL="$r18/skills/debugging/SKILL.md" ORCH_LOOP_EVALS_SKILL="$r18/skills/evals/SKILL.md" ORCH_LOOP_DISCOVERY_SKILL="$r18/skills/continuous-discovery/SKILL.md" ORCH_LOOP_OPERATING_SKILL="$r18/skills/operating/SKILL.md" ORCH_LOOP_SECURITY_DEF="$r18/agents/security.agent.md" ORCH_LOOP_ORCH_DEF="$r18/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r18/agents/engineer.agent.md" ORCH_LOOP_REVIEWER_DEF="$r18/agents/reviewer.agent.md" sh "$0" >/dev/null 2>&1) || c18_fail=1
  if [ "$c18_fail" -eq 1 ]; then echo "selftest PASS: debugging skill missing a kit-distinctive marker -> exit 1"; else echo "selftest FAIL: absent debugging-skill marker NOT caught (marker teeth vacuous)"; sf=1; fi

  # -- case 19: debugging reference teeth -- conformant debugging skill, but the ENGINEER def does NOT reference the skill -> exit 1 --
  r19="$d/case19"; mkdir -p "$r19/agents" "$r19/scripts" "$r19/_gh_/workflows" "$r19/skills/design" "$r19/skills/plan" "$r19/skills/tdd" "$r19/skills/review" "$r19/skills/worktrees" "$r19/skills/verification" "$r19/skills/using-skills" "$r19/skills/debugging"
  for f in $ROSTER_FILES; do _agent_ok > "$r19/agents/$f"; done
  printf '#!/bin/sh\nrunaway-guard.sh step\nkit.denied=true\nkit.conflict=false\ngit diff --name-only HEAD\n' > "$r19/scripts/orchestrator-run.sh"; chmod +x "$r19/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r19/_gh_/workflows/gp.yml"
  _skill_ok > "$r19/skills/design/SKILL.md"; _plan_skill_ok > "$r19/skills/plan/SKILL.md"; _tdd_skill_ok > "$r19/skills/tdd/SKILL.md"; _review_skill_ok > "$r19/skills/review/SKILL.md"; _worktrees_skill_ok > "$r19/skills/worktrees/SKILL.md"; _vbc_skill_ok > "$r19/skills/verification/SKILL.md"; _keystone_ok > "$r19/skills/using-skills/SKILL.md"
  _debugging_skill_ok > "$r19/skills/debugging/SKILL.md"
  printf '\nskills/design/SKILL.md\nskills/plan/SKILL.md\nskills/worktrees/SKILL.md\nskills/verification/SKILL.md\nskills/using-skills/SKILL.md\n' >> "$r19/agents/orchestrator.agent.md"
  printf 'skills/tdd/SKILL.md\nskills/verification/SKILL.md\n' >> "$r19/agents/engineer.agent.md"
  printf 'skills/review/SKILL.md\n' >> "$r19/agents/reviewer.agent.md"
  # NOTE: deliberately do NOT append 'skills/debugging/SKILL.md' to engineer.agent.md -> check_debugging_skill reference branch must fail
  mkdir -p "$r19/skills/evals"; _evals_skill_ok > "$r19/skills/evals/SKILL.md"
  printf 'skills/evals/SKILL.md\n' >> "$r19/agents/engineer.agent.md"
  printf 'skills/evals/SKILL.md\n' >> "$r19/agents/security.agent.md"
  c19_fail=0
  mkdir -p "$r19/skills/continuous-discovery"; _discovery_skill_ok > "$r19/skills/continuous-discovery/SKILL.md"
  printf 'skills/continuous-discovery/SKILL.md\n' >> "$r19/agents/orchestrator.agent.md"
  mkdir -p "$r19/skills/operating"; _operating_skill_ok > "$r19/skills/operating/SKILL.md"
  printf 'skills/operating/SKILL.md\n' >> "$r19/agents/orchestrator.agent.md"
  (ORCH_LOOP_ROSTER_DIR="$r19/agents" ORCH_LOOP_SCRIPT="$r19/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r19/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r19/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r19/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r19/skills/tdd/SKILL.md" ORCH_LOOP_REVIEW_SKILL="$r19/skills/review/SKILL.md" ORCH_LOOP_WORKTREES_SKILL="$r19/skills/worktrees/SKILL.md" ORCH_LOOP_VBC_SKILL="$r19/skills/verification/SKILL.md" ORCH_LOOP_KEYSTONE="$r19/skills/using-skills/SKILL.md" ORCH_LOOP_DEBUGGING_SKILL="$r19/skills/debugging/SKILL.md" ORCH_LOOP_EVALS_SKILL="$r19/skills/evals/SKILL.md" ORCH_LOOP_DISCOVERY_SKILL="$r19/skills/continuous-discovery/SKILL.md" ORCH_LOOP_OPERATING_SKILL="$r19/skills/operating/SKILL.md" ORCH_LOOP_SECURITY_DEF="$r19/agents/security.agent.md" ORCH_LOOP_ORCH_DEF="$r19/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r19/agents/engineer.agent.md" ORCH_LOOP_REVIEWER_DEF="$r19/agents/reviewer.agent.md" sh "$0" >/dev/null 2>&1) || c19_fail=1
  if [ "$c19_fail" -eq 1 ]; then echo "selftest PASS: Engineer def omits debugging reference -> exit 1"; else echo "selftest FAIL: missing debugging reference NOT caught (reference teeth vacuous)"; sf=1; fi

  # -- case 20: structural-enumeration teeth -- fully conformant tree, PLUS an EXTRA on-disk skill with a NOVEL
  #    name ('zzz-probe', in no hardcoded list) that the keystone does NOT index -> exit 1.
  #    A hardcoded-list check would miss zzz-probe; the structural enumeration catches it. This is the load-bearing
  #    proof that the index is checked against disk, not a static list.
  r20="$d/case20"; mkdir -p "$r20/agents" "$r20/scripts" "$r20/_gh_/workflows" "$r20/skills/design" "$r20/skills/plan" "$r20/skills/tdd" "$r20/skills/review" "$r20/skills/worktrees" "$r20/skills/verification" "$r20/skills/using-skills" "$r20/skills/debugging"
  for f in $ROSTER_FILES; do _agent_ok > "$r20/agents/$f"; done
  printf '#!/bin/sh\nrunaway-guard.sh step\nkit.denied=true\nkit.conflict=false\ngit diff --name-only HEAD\n' > "$r20/scripts/orchestrator-run.sh"; chmod +x "$r20/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r20/_gh_/workflows/gp.yml"
  _skill_ok > "$r20/skills/design/SKILL.md"; _plan_skill_ok > "$r20/skills/plan/SKILL.md"; _tdd_skill_ok > "$r20/skills/tdd/SKILL.md"; _review_skill_ok > "$r20/skills/review/SKILL.md"; _worktrees_skill_ok > "$r20/skills/worktrees/SKILL.md"; _vbc_skill_ok > "$r20/skills/verification/SKILL.md"; _debugging_skill_ok > "$r20/skills/debugging/SKILL.md"
  # keystone indexes every standard skill (conformant) -- but NOT the novel zzz-probe added below
  _keystone_ok > "$r20/skills/using-skills/SKILL.md"
  printf '\nskills/design/SKILL.md\nskills/plan/SKILL.md\nskills/worktrees/SKILL.md\nskills/verification/SKILL.md\nskills/using-skills/SKILL.md\n' >> "$r20/agents/orchestrator.agent.md"
  printf 'skills/tdd/SKILL.md\nskills/verification/SKILL.md\nskills/debugging/SKILL.md\n' >> "$r20/agents/engineer.agent.md"
  printf 'skills/review/SKILL.md\n' >> "$r20/agents/reviewer.agent.md"
  # EXTRA on-disk skill with a NOVEL name, deliberately NOT indexed by the keystone above
  mkdir -p "$r20/skills/zzz-probe"; printf 'x\n' > "$r20/skills/zzz-probe/SKILL.md"
  mkdir -p "$r20/skills/evals"; _evals_skill_ok > "$r20/skills/evals/SKILL.md"
  printf 'skills/evals/SKILL.md\n' >> "$r20/agents/engineer.agent.md"
  printf 'skills/evals/SKILL.md\n' >> "$r20/agents/security.agent.md"
  c20_fail=0
  mkdir -p "$r20/skills/continuous-discovery"; _discovery_skill_ok > "$r20/skills/continuous-discovery/SKILL.md"
  printf 'skills/continuous-discovery/SKILL.md\n' >> "$r20/agents/orchestrator.agent.md"
  mkdir -p "$r20/skills/operating"; _operating_skill_ok > "$r20/skills/operating/SKILL.md"
  printf 'skills/operating/SKILL.md\n' >> "$r20/agents/orchestrator.agent.md"
  (ORCH_LOOP_ROSTER_DIR="$r20/agents" ORCH_LOOP_SCRIPT="$r20/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r20/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r20/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r20/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r20/skills/tdd/SKILL.md" ORCH_LOOP_REVIEW_SKILL="$r20/skills/review/SKILL.md" ORCH_LOOP_WORKTREES_SKILL="$r20/skills/worktrees/SKILL.md" ORCH_LOOP_VBC_SKILL="$r20/skills/verification/SKILL.md" ORCH_LOOP_KEYSTONE="$r20/skills/using-skills/SKILL.md" ORCH_LOOP_DEBUGGING_SKILL="$r20/skills/debugging/SKILL.md" ORCH_LOOP_EVALS_SKILL="$r20/skills/evals/SKILL.md" ORCH_LOOP_DISCOVERY_SKILL="$r20/skills/continuous-discovery/SKILL.md" ORCH_LOOP_OPERATING_SKILL="$r20/skills/operating/SKILL.md" ORCH_LOOP_SECURITY_DEF="$r20/agents/security.agent.md" ORCH_LOOP_ORCH_DEF="$r20/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r20/agents/engineer.agent.md" ORCH_LOOP_REVIEWER_DEF="$r20/agents/reviewer.agent.md" sh "$0" >/dev/null 2>&1) || c20_fail=1
  if [ "$c20_fail" -eq 1 ]; then echo "selftest PASS: structural enumeration catches an unindexed on-disk skill -> exit 1"; else echo "selftest FAIL: novel on-disk skill unindexed NOT caught (structural enumeration vacuous -- a hardcoded list would miss it)"; sf=1; fi

  # -- case 21: evals marker teeth -- conformant tree, but the evals skill is MISSING one marker (drop 'red-team') -> exit 1 --
  r21="$d/case21"; mkdir -p "$r21/agents" "$r21/scripts" "$r21/_gh_/workflows" "$r21/skills/design" "$r21/skills/plan" "$r21/skills/tdd" "$r21/skills/review" "$r21/skills/worktrees" "$r21/skills/verification" "$r21/skills/using-skills" "$r21/skills/debugging" "$r21/skills/evals"
  for f in $ROSTER_FILES; do _agent_ok > "$r21/agents/$f"; done
  printf '#!/bin/sh\nrunaway-guard.sh step\nkit.denied=true\nkit.conflict=false\ngit diff --name-only HEAD\n' > "$r21/scripts/orchestrator-run.sh"; chmod +x "$r21/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r21/_gh_/workflows/gp.yml"
  _skill_ok > "$r21/skills/design/SKILL.md"; _plan_skill_ok > "$r21/skills/plan/SKILL.md"; _tdd_skill_ok > "$r21/skills/tdd/SKILL.md"; _review_skill_ok > "$r21/skills/review/SKILL.md"; _worktrees_skill_ok > "$r21/skills/worktrees/SKILL.md"; _vbc_skill_ok > "$r21/skills/verification/SKILL.md"; _debugging_skill_ok > "$r21/skills/debugging/SKILL.md"; _keystone_ok > "$r21/skills/using-skills/SKILL.md"
  printf '\nskills/design/SKILL.md\nskills/plan/SKILL.md\nskills/worktrees/SKILL.md\nskills/verification/SKILL.md\nskills/using-skills/SKILL.md\n' >> "$r21/agents/orchestrator.agent.md"
  printf 'skills/tdd/SKILL.md\nskills/verification/SKILL.md\nskills/debugging/SKILL.md\n' >> "$r21/agents/engineer.agent.md"
  printf 'skills/review/SKILL.md\n' >> "$r21/agents/reviewer.agent.md"
  # evals skill present + BOTH refs, but the skill is MISSING the 'red-team' marker -> check_evals_skill marker branch must fail
  printf -- '---\nname: evals\n---\n## When to use\nx\neval-driven\njudge\nthreshold\n' > "$r21/skills/evals/SKILL.md"
  printf 'skills/evals/SKILL.md\n' >> "$r21/agents/engineer.agent.md"
  printf 'skills/evals/SKILL.md\n' >> "$r21/agents/security.agent.md"
  c21_fail=0
  mkdir -p "$r21/skills/continuous-discovery"; _discovery_skill_ok > "$r21/skills/continuous-discovery/SKILL.md"
  printf 'skills/continuous-discovery/SKILL.md\n' >> "$r21/agents/orchestrator.agent.md"
  mkdir -p "$r21/skills/operating"; _operating_skill_ok > "$r21/skills/operating/SKILL.md"
  printf 'skills/operating/SKILL.md\n' >> "$r21/agents/orchestrator.agent.md"
  (ORCH_LOOP_ROSTER_DIR="$r21/agents" ORCH_LOOP_SCRIPT="$r21/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r21/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r21/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r21/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r21/skills/tdd/SKILL.md" ORCH_LOOP_REVIEW_SKILL="$r21/skills/review/SKILL.md" ORCH_LOOP_WORKTREES_SKILL="$r21/skills/worktrees/SKILL.md" ORCH_LOOP_VBC_SKILL="$r21/skills/verification/SKILL.md" ORCH_LOOP_KEYSTONE="$r21/skills/using-skills/SKILL.md" ORCH_LOOP_DEBUGGING_SKILL="$r21/skills/debugging/SKILL.md" ORCH_LOOP_EVALS_SKILL="$r21/skills/evals/SKILL.md" ORCH_LOOP_DISCOVERY_SKILL="$r21/skills/continuous-discovery/SKILL.md" ORCH_LOOP_OPERATING_SKILL="$r21/skills/operating/SKILL.md" ORCH_LOOP_SECURITY_DEF="$r21/agents/security.agent.md" ORCH_LOOP_ORCH_DEF="$r21/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r21/agents/engineer.agent.md" ORCH_LOOP_REVIEWER_DEF="$r21/agents/reviewer.agent.md" sh "$0" >/dev/null 2>&1) || c21_fail=1
  if [ "$c21_fail" -eq 1 ]; then echo "selftest PASS: evals skill missing a kit-distinctive marker -> exit 1"; else echo "selftest FAIL: absent evals-skill marker NOT caught (marker teeth vacuous)"; sf=1; fi

  # -- case 22: evals Engineer-reference teeth -- conformant skill + Security ref present, but the ENGINEER def does NOT reference the skill -> exit 1 --
  r22="$d/case22"; mkdir -p "$r22/agents" "$r22/scripts" "$r22/_gh_/workflows" "$r22/skills/design" "$r22/skills/plan" "$r22/skills/tdd" "$r22/skills/review" "$r22/skills/worktrees" "$r22/skills/verification" "$r22/skills/using-skills" "$r22/skills/debugging" "$r22/skills/evals"
  for f in $ROSTER_FILES; do _agent_ok > "$r22/agents/$f"; done
  printf '#!/bin/sh\nrunaway-guard.sh step\nkit.denied=true\nkit.conflict=false\ngit diff --name-only HEAD\n' > "$r22/scripts/orchestrator-run.sh"; chmod +x "$r22/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r22/_gh_/workflows/gp.yml"
  _skill_ok > "$r22/skills/design/SKILL.md"; _plan_skill_ok > "$r22/skills/plan/SKILL.md"; _tdd_skill_ok > "$r22/skills/tdd/SKILL.md"; _review_skill_ok > "$r22/skills/review/SKILL.md"; _worktrees_skill_ok > "$r22/skills/worktrees/SKILL.md"; _vbc_skill_ok > "$r22/skills/verification/SKILL.md"; _debugging_skill_ok > "$r22/skills/debugging/SKILL.md"; _keystone_ok > "$r22/skills/using-skills/SKILL.md"; _evals_skill_ok > "$r22/skills/evals/SKILL.md"
  printf '\nskills/design/SKILL.md\nskills/plan/SKILL.md\nskills/worktrees/SKILL.md\nskills/verification/SKILL.md\nskills/using-skills/SKILL.md\n' >> "$r22/agents/orchestrator.agent.md"
  printf 'skills/tdd/SKILL.md\nskills/verification/SKILL.md\nskills/debugging/SKILL.md\n' >> "$r22/agents/engineer.agent.md"
  printf 'skills/review/SKILL.md\n' >> "$r22/agents/reviewer.agent.md"
  # Security def references the evals skill, but deliberately do NOT append 'skills/evals/SKILL.md' to engineer.agent.md -> check_evals_skill Engineer-reference branch must fail
  printf 'skills/evals/SKILL.md\n' >> "$r22/agents/security.agent.md"
  c22_fail=0
  mkdir -p "$r22/skills/continuous-discovery"; _discovery_skill_ok > "$r22/skills/continuous-discovery/SKILL.md"
  printf 'skills/continuous-discovery/SKILL.md\n' >> "$r22/agents/orchestrator.agent.md"
  mkdir -p "$r22/skills/operating"; _operating_skill_ok > "$r22/skills/operating/SKILL.md"
  printf 'skills/operating/SKILL.md\n' >> "$r22/agents/orchestrator.agent.md"
  (ORCH_LOOP_ROSTER_DIR="$r22/agents" ORCH_LOOP_SCRIPT="$r22/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r22/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r22/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r22/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r22/skills/tdd/SKILL.md" ORCH_LOOP_REVIEW_SKILL="$r22/skills/review/SKILL.md" ORCH_LOOP_WORKTREES_SKILL="$r22/skills/worktrees/SKILL.md" ORCH_LOOP_VBC_SKILL="$r22/skills/verification/SKILL.md" ORCH_LOOP_KEYSTONE="$r22/skills/using-skills/SKILL.md" ORCH_LOOP_DEBUGGING_SKILL="$r22/skills/debugging/SKILL.md" ORCH_LOOP_EVALS_SKILL="$r22/skills/evals/SKILL.md" ORCH_LOOP_DISCOVERY_SKILL="$r22/skills/continuous-discovery/SKILL.md" ORCH_LOOP_OPERATING_SKILL="$r22/skills/operating/SKILL.md" ORCH_LOOP_SECURITY_DEF="$r22/agents/security.agent.md" ORCH_LOOP_ORCH_DEF="$r22/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r22/agents/engineer.agent.md" ORCH_LOOP_REVIEWER_DEF="$r22/agents/reviewer.agent.md" sh "$0" >/dev/null 2>&1) || c22_fail=1
  if [ "$c22_fail" -eq 1 ]; then echo "selftest PASS: Engineer def omits evals reference -> exit 1"; else echo "selftest FAIL: missing Engineer evals reference NOT caught (Engineer reference teeth vacuous)"; sf=1; fi

  # -- case 23: evals Security-reference teeth -- conformant skill + Engineer ref present, but the SECURITY def does NOT reference the skill -> exit 1 --
  r23="$d/case23"; mkdir -p "$r23/agents" "$r23/scripts" "$r23/_gh_/workflows" "$r23/skills/design" "$r23/skills/plan" "$r23/skills/tdd" "$r23/skills/review" "$r23/skills/worktrees" "$r23/skills/verification" "$r23/skills/using-skills" "$r23/skills/debugging" "$r23/skills/evals"
  for f in $ROSTER_FILES; do _agent_ok > "$r23/agents/$f"; done
  printf '#!/bin/sh\nrunaway-guard.sh step\nkit.denied=true\nkit.conflict=false\ngit diff --name-only HEAD\n' > "$r23/scripts/orchestrator-run.sh"; chmod +x "$r23/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r23/_gh_/workflows/gp.yml"
  _skill_ok > "$r23/skills/design/SKILL.md"; _plan_skill_ok > "$r23/skills/plan/SKILL.md"; _tdd_skill_ok > "$r23/skills/tdd/SKILL.md"; _review_skill_ok > "$r23/skills/review/SKILL.md"; _worktrees_skill_ok > "$r23/skills/worktrees/SKILL.md"; _vbc_skill_ok > "$r23/skills/verification/SKILL.md"; _debugging_skill_ok > "$r23/skills/debugging/SKILL.md"; _keystone_ok > "$r23/skills/using-skills/SKILL.md"; _evals_skill_ok > "$r23/skills/evals/SKILL.md"
  printf '\nskills/design/SKILL.md\nskills/plan/SKILL.md\nskills/worktrees/SKILL.md\nskills/verification/SKILL.md\nskills/using-skills/SKILL.md\n' >> "$r23/agents/orchestrator.agent.md"
  printf 'skills/tdd/SKILL.md\nskills/verification/SKILL.md\nskills/debugging/SKILL.md\n' >> "$r23/agents/engineer.agent.md"
  printf 'skills/review/SKILL.md\n' >> "$r23/agents/reviewer.agent.md"
  # Engineer def references the evals skill, but deliberately do NOT append 'skills/evals/SKILL.md' to security.agent.md -> check_evals_skill Security-reference branch must fail
  printf 'skills/evals/SKILL.md\n' >> "$r23/agents/engineer.agent.md"
  c23_fail=0
  mkdir -p "$r23/skills/continuous-discovery"; _discovery_skill_ok > "$r23/skills/continuous-discovery/SKILL.md"
  printf 'skills/continuous-discovery/SKILL.md\n' >> "$r23/agents/orchestrator.agent.md"
  mkdir -p "$r23/skills/operating"; _operating_skill_ok > "$r23/skills/operating/SKILL.md"
  printf 'skills/operating/SKILL.md\n' >> "$r23/agents/orchestrator.agent.md"
  (ORCH_LOOP_ROSTER_DIR="$r23/agents" ORCH_LOOP_SCRIPT="$r23/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r23/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r23/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r23/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r23/skills/tdd/SKILL.md" ORCH_LOOP_REVIEW_SKILL="$r23/skills/review/SKILL.md" ORCH_LOOP_WORKTREES_SKILL="$r23/skills/worktrees/SKILL.md" ORCH_LOOP_VBC_SKILL="$r23/skills/verification/SKILL.md" ORCH_LOOP_KEYSTONE="$r23/skills/using-skills/SKILL.md" ORCH_LOOP_DEBUGGING_SKILL="$r23/skills/debugging/SKILL.md" ORCH_LOOP_EVALS_SKILL="$r23/skills/evals/SKILL.md" ORCH_LOOP_DISCOVERY_SKILL="$r23/skills/continuous-discovery/SKILL.md" ORCH_LOOP_OPERATING_SKILL="$r23/skills/operating/SKILL.md" ORCH_LOOP_SECURITY_DEF="$r23/agents/security.agent.md" ORCH_LOOP_ORCH_DEF="$r23/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r23/agents/engineer.agent.md" ORCH_LOOP_REVIEWER_DEF="$r23/agents/reviewer.agent.md" sh "$0" >/dev/null 2>&1) || c23_fail=1
  if [ "$c23_fail" -eq 1 ]; then echo "selftest PASS: Security def omits evals reference -> exit 1"; else echo "selftest FAIL: missing Security evals reference NOT caught (Security reference teeth vacuous)"; sf=1; fi

  # -- case 24: continuous-discovery marker teeth -- conformant tree, but the continuous-discovery skill is MISSING one marker (drop 'outcome over output') -> exit 1 --
  r24="$d/case24"; mkdir -p "$r24/agents" "$r24/scripts" "$r24/_gh_/workflows" "$r24/skills/design" "$r24/skills/plan" "$r24/skills/tdd" "$r24/skills/review" "$r24/skills/worktrees" "$r24/skills/verification" "$r24/skills/using-skills" "$r24/skills/debugging" "$r24/skills/evals" "$r24/skills/continuous-discovery" "$r24/skills/operating"
  for f in $ROSTER_FILES; do _agent_ok > "$r24/agents/$f"; done
  printf '#!/bin/sh\nrunaway-guard.sh step\nkit.denied=true\nkit.conflict=false\ngit diff --name-only HEAD\n' > "$r24/scripts/orchestrator-run.sh"; chmod +x "$r24/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r24/_gh_/workflows/gp.yml"
  _skill_ok > "$r24/skills/design/SKILL.md"; _plan_skill_ok > "$r24/skills/plan/SKILL.md"; _tdd_skill_ok > "$r24/skills/tdd/SKILL.md"; _review_skill_ok > "$r24/skills/review/SKILL.md"; _worktrees_skill_ok > "$r24/skills/worktrees/SKILL.md"; _vbc_skill_ok > "$r24/skills/verification/SKILL.md"; _debugging_skill_ok > "$r24/skills/debugging/SKILL.md"; _evals_skill_ok > "$r24/skills/evals/SKILL.md"; _keystone_ok > "$r24/skills/using-skills/SKILL.md"
  printf '\nskills/design/SKILL.md\nskills/plan/SKILL.md\nskills/worktrees/SKILL.md\nskills/verification/SKILL.md\nskills/using-skills/SKILL.md\nskills/continuous-discovery/SKILL.md\nskills/operating/SKILL.md\n' >> "$r24/agents/orchestrator.agent.md"
  printf 'skills/tdd/SKILL.md\nskills/verification/SKILL.md\nskills/debugging/SKILL.md\nskills/evals/SKILL.md\n' >> "$r24/agents/engineer.agent.md"
  printf 'skills/review/SKILL.md\n' >> "$r24/agents/reviewer.agent.md"
  printf 'skills/evals/SKILL.md\n' >> "$r24/agents/security.agent.md"
  # operating skill is conformant (only continuous-discovery is broken in this case)
  _operating_skill_ok > "$r24/skills/operating/SKILL.md"
  # continuous-discovery skill present + Orchestrator references it, but the skill is MISSING the 'outcome over output' marker -> check_discovery_skill marker branch must fail
  printf -- '---\nname: continuous-discovery\n---\n## When to use\nx\ndiscovery partner\nopportunity solution tree\nriskiest assumption\nsmall bet\n' > "$r24/skills/continuous-discovery/SKILL.md"
  c24_fail=0
  (ORCH_LOOP_ROSTER_DIR="$r24/agents" ORCH_LOOP_SCRIPT="$r24/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r24/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r24/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r24/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r24/skills/tdd/SKILL.md" ORCH_LOOP_REVIEW_SKILL="$r24/skills/review/SKILL.md" ORCH_LOOP_WORKTREES_SKILL="$r24/skills/worktrees/SKILL.md" ORCH_LOOP_VBC_SKILL="$r24/skills/verification/SKILL.md" ORCH_LOOP_KEYSTONE="$r24/skills/using-skills/SKILL.md" ORCH_LOOP_DEBUGGING_SKILL="$r24/skills/debugging/SKILL.md" ORCH_LOOP_EVALS_SKILL="$r24/skills/evals/SKILL.md" ORCH_LOOP_DISCOVERY_SKILL="$r24/skills/continuous-discovery/SKILL.md" ORCH_LOOP_OPERATING_SKILL="$r24/skills/operating/SKILL.md" ORCH_LOOP_SECURITY_DEF="$r24/agents/security.agent.md" ORCH_LOOP_ORCH_DEF="$r24/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r24/agents/engineer.agent.md" ORCH_LOOP_REVIEWER_DEF="$r24/agents/reviewer.agent.md" sh "$0" >/dev/null 2>&1) || c24_fail=1
  if [ "$c24_fail" -eq 1 ]; then echo "selftest PASS: continuous-discovery skill missing a kit-distinctive marker -> exit 1"; else echo "selftest FAIL: absent continuous-discovery-skill marker NOT caught (marker teeth vacuous)"; sf=1; fi

  # -- case 25: continuous-discovery reference teeth -- conformant skill, but the ORCHESTRATOR def does NOT reference the skill -> exit 1 --
  r25="$d/case25"; mkdir -p "$r25/agents" "$r25/scripts" "$r25/_gh_/workflows" "$r25/skills/design" "$r25/skills/plan" "$r25/skills/tdd" "$r25/skills/review" "$r25/skills/worktrees" "$r25/skills/verification" "$r25/skills/using-skills" "$r25/skills/debugging" "$r25/skills/evals" "$r25/skills/continuous-discovery" "$r25/skills/operating"
  for f in $ROSTER_FILES; do _agent_ok > "$r25/agents/$f"; done
  printf '#!/bin/sh\nrunaway-guard.sh step\nkit.denied=true\nkit.conflict=false\ngit diff --name-only HEAD\n' > "$r25/scripts/orchestrator-run.sh"; chmod +x "$r25/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r25/_gh_/workflows/gp.yml"
  _skill_ok > "$r25/skills/design/SKILL.md"; _plan_skill_ok > "$r25/skills/plan/SKILL.md"; _tdd_skill_ok > "$r25/skills/tdd/SKILL.md"; _review_skill_ok > "$r25/skills/review/SKILL.md"; _worktrees_skill_ok > "$r25/skills/worktrees/SKILL.md"; _vbc_skill_ok > "$r25/skills/verification/SKILL.md"; _debugging_skill_ok > "$r25/skills/debugging/SKILL.md"; _evals_skill_ok > "$r25/skills/evals/SKILL.md"; _keystone_ok > "$r25/skills/using-skills/SKILL.md"; _discovery_skill_ok > "$r25/skills/continuous-discovery/SKILL.md"; _operating_skill_ok > "$r25/skills/operating/SKILL.md"
  printf '\nskills/design/SKILL.md\nskills/plan/SKILL.md\nskills/worktrees/SKILL.md\nskills/verification/SKILL.md\nskills/using-skills/SKILL.md\nskills/operating/SKILL.md\n' >> "$r25/agents/orchestrator.agent.md"
  printf 'skills/tdd/SKILL.md\nskills/verification/SKILL.md\nskills/debugging/SKILL.md\nskills/evals/SKILL.md\n' >> "$r25/agents/engineer.agent.md"
  printf 'skills/review/SKILL.md\n' >> "$r25/agents/reviewer.agent.md"
  printf 'skills/evals/SKILL.md\n' >> "$r25/agents/security.agent.md"
  # NOTE: deliberately do NOT append 'skills/continuous-discovery/SKILL.md' to orchestrator.agent.md -> check_discovery_skill reference branch must fail
  c25_fail=0
  (ORCH_LOOP_ROSTER_DIR="$r25/agents" ORCH_LOOP_SCRIPT="$r25/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r25/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r25/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r25/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r25/skills/tdd/SKILL.md" ORCH_LOOP_REVIEW_SKILL="$r25/skills/review/SKILL.md" ORCH_LOOP_WORKTREES_SKILL="$r25/skills/worktrees/SKILL.md" ORCH_LOOP_VBC_SKILL="$r25/skills/verification/SKILL.md" ORCH_LOOP_KEYSTONE="$r25/skills/using-skills/SKILL.md" ORCH_LOOP_DEBUGGING_SKILL="$r25/skills/debugging/SKILL.md" ORCH_LOOP_EVALS_SKILL="$r25/skills/evals/SKILL.md" ORCH_LOOP_DISCOVERY_SKILL="$r25/skills/continuous-discovery/SKILL.md" ORCH_LOOP_OPERATING_SKILL="$r25/skills/operating/SKILL.md" ORCH_LOOP_SECURITY_DEF="$r25/agents/security.agent.md" ORCH_LOOP_ORCH_DEF="$r25/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r25/agents/engineer.agent.md" ORCH_LOOP_REVIEWER_DEF="$r25/agents/reviewer.agent.md" sh "$0" >/dev/null 2>&1) || c25_fail=1
  if [ "$c25_fail" -eq 1 ]; then echo "selftest PASS: Orchestrator def omits continuous-discovery reference -> exit 1"; else echo "selftest FAIL: missing continuous-discovery reference NOT caught (reference teeth vacuous)"; sf=1; fi

  # -- case 26: operating marker-teeth -- conformant tree, but the operating skill is MISSING one marker (drop 'autonomy tier') -> exit 1 --
  r26="$d/case26"; mkdir -p "$r26/agents" "$r26/scripts" "$r26/_gh_/workflows" "$r26/skills/design" "$r26/skills/plan" "$r26/skills/tdd" "$r26/skills/review" "$r26/skills/worktrees" "$r26/skills/verification" "$r26/skills/using-skills" "$r26/skills/debugging" "$r26/skills/evals" "$r26/skills/continuous-discovery" "$r26/skills/operating"
  for f in $ROSTER_FILES; do _agent_ok > "$r26/agents/$f"; done
  printf '#!/bin/sh\nrunaway-guard.sh step\nkit.denied=true\nkit.conflict=false\ngit diff --name-only HEAD\n' > "$r26/scripts/orchestrator-run.sh"; chmod +x "$r26/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r26/_gh_/workflows/gp.yml"
  _skill_ok > "$r26/skills/design/SKILL.md"; _plan_skill_ok > "$r26/skills/plan/SKILL.md"; _tdd_skill_ok > "$r26/skills/tdd/SKILL.md"; _review_skill_ok > "$r26/skills/review/SKILL.md"; _worktrees_skill_ok > "$r26/skills/worktrees/SKILL.md"; _vbc_skill_ok > "$r26/skills/verification/SKILL.md"; _debugging_skill_ok > "$r26/skills/debugging/SKILL.md"; _evals_skill_ok > "$r26/skills/evals/SKILL.md"; _keystone_ok > "$r26/skills/using-skills/SKILL.md"; _discovery_skill_ok > "$r26/skills/continuous-discovery/SKILL.md"
  printf '\nskills/design/SKILL.md\nskills/plan/SKILL.md\nskills/worktrees/SKILL.md\nskills/verification/SKILL.md\nskills/using-skills/SKILL.md\nskills/continuous-discovery/SKILL.md\nskills/operating/SKILL.md\n' >> "$r26/agents/orchestrator.agent.md"
  printf 'skills/tdd/SKILL.md\nskills/verification/SKILL.md\nskills/debugging/SKILL.md\nskills/evals/SKILL.md\n' >> "$r26/agents/engineer.agent.md"
  printf 'skills/review/SKILL.md\n' >> "$r26/agents/reviewer.agent.md"
  printf 'skills/evals/SKILL.md\n' >> "$r26/agents/security.agent.md"
  # operating skill present + Orchestrator references it, but the skill is MISSING the 'autonomy tier' marker -> check_operating_skill marker branch must fail
  printf -- '---\nname: operating\n---\n## When to use\nx\nblast radius\nadvisory, not actuating\nthe human commands the catastrophic action\nsurface, don'"'"'t actuate\n' > "$r26/skills/operating/SKILL.md"
  c26_fail=0
  (ORCH_LOOP_ROSTER_DIR="$r26/agents" ORCH_LOOP_SCRIPT="$r26/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r26/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r26/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r26/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r26/skills/tdd/SKILL.md" ORCH_LOOP_REVIEW_SKILL="$r26/skills/review/SKILL.md" ORCH_LOOP_WORKTREES_SKILL="$r26/skills/worktrees/SKILL.md" ORCH_LOOP_VBC_SKILL="$r26/skills/verification/SKILL.md" ORCH_LOOP_KEYSTONE="$r26/skills/using-skills/SKILL.md" ORCH_LOOP_DEBUGGING_SKILL="$r26/skills/debugging/SKILL.md" ORCH_LOOP_EVALS_SKILL="$r26/skills/evals/SKILL.md" ORCH_LOOP_DISCOVERY_SKILL="$r26/skills/continuous-discovery/SKILL.md" ORCH_LOOP_OPERATING_SKILL="$r26/skills/operating/SKILL.md" ORCH_LOOP_SECURITY_DEF="$r26/agents/security.agent.md" ORCH_LOOP_ORCH_DEF="$r26/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r26/agents/engineer.agent.md" ORCH_LOOP_REVIEWER_DEF="$r26/agents/reviewer.agent.md" sh "$0" >/dev/null 2>&1) || c26_fail=1
  if [ "$c26_fail" -eq 1 ]; then echo "selftest PASS: operating skill missing a kit-distinctive marker -> exit 1"; else echo "selftest FAIL: absent operating-skill marker NOT caught (marker teeth vacuous)"; sf=1; fi

  # -- case 27: operating reference teeth -- conformant skill, but the ORCHESTRATOR def does NOT reference the skill -> exit 1 --
  r27="$d/case27"; mkdir -p "$r27/agents" "$r27/scripts" "$r27/_gh_/workflows" "$r27/skills/design" "$r27/skills/plan" "$r27/skills/tdd" "$r27/skills/review" "$r27/skills/worktrees" "$r27/skills/verification" "$r27/skills/using-skills" "$r27/skills/debugging" "$r27/skills/evals" "$r27/skills/continuous-discovery" "$r27/skills/operating"
  for f in $ROSTER_FILES; do _agent_ok > "$r27/agents/$f"; done
  printf '#!/bin/sh\nrunaway-guard.sh step\nkit.denied=true\nkit.conflict=false\ngit diff --name-only HEAD\n' > "$r27/scripts/orchestrator-run.sh"; chmod +x "$r27/scripts/orchestrator-run.sh"
  printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$r27/_gh_/workflows/gp.yml"
  _skill_ok > "$r27/skills/design/SKILL.md"; _plan_skill_ok > "$r27/skills/plan/SKILL.md"; _tdd_skill_ok > "$r27/skills/tdd/SKILL.md"; _review_skill_ok > "$r27/skills/review/SKILL.md"; _worktrees_skill_ok > "$r27/skills/worktrees/SKILL.md"; _vbc_skill_ok > "$r27/skills/verification/SKILL.md"; _debugging_skill_ok > "$r27/skills/debugging/SKILL.md"; _evals_skill_ok > "$r27/skills/evals/SKILL.md"; _keystone_ok > "$r27/skills/using-skills/SKILL.md"; _discovery_skill_ok > "$r27/skills/continuous-discovery/SKILL.md"; _operating_skill_ok > "$r27/skills/operating/SKILL.md"
  printf '\nskills/design/SKILL.md\nskills/plan/SKILL.md\nskills/worktrees/SKILL.md\nskills/verification/SKILL.md\nskills/using-skills/SKILL.md\nskills/continuous-discovery/SKILL.md\n' >> "$r27/agents/orchestrator.agent.md"
  printf 'skills/tdd/SKILL.md\nskills/verification/SKILL.md\nskills/debugging/SKILL.md\nskills/evals/SKILL.md\n' >> "$r27/agents/engineer.agent.md"
  printf 'skills/review/SKILL.md\n' >> "$r27/agents/reviewer.agent.md"
  printf 'skills/evals/SKILL.md\n' >> "$r27/agents/security.agent.md"
  # NOTE: deliberately do NOT append 'skills/operating/SKILL.md' to orchestrator.agent.md -> check_operating_skill reference branch must fail
  c27_fail=0
  (ORCH_LOOP_ROSTER_DIR="$r27/agents" ORCH_LOOP_SCRIPT="$r27/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$r27/_gh_/workflows/gp.yml" ORCH_LOOP_SKILL="$r27/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$r27/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$r27/skills/tdd/SKILL.md" ORCH_LOOP_REVIEW_SKILL="$r27/skills/review/SKILL.md" ORCH_LOOP_WORKTREES_SKILL="$r27/skills/worktrees/SKILL.md" ORCH_LOOP_VBC_SKILL="$r27/skills/verification/SKILL.md" ORCH_LOOP_KEYSTONE="$r27/skills/using-skills/SKILL.md" ORCH_LOOP_DEBUGGING_SKILL="$r27/skills/debugging/SKILL.md" ORCH_LOOP_EVALS_SKILL="$r27/skills/evals/SKILL.md" ORCH_LOOP_DISCOVERY_SKILL="$r27/skills/continuous-discovery/SKILL.md" ORCH_LOOP_OPERATING_SKILL="$r27/skills/operating/SKILL.md" ORCH_LOOP_SECURITY_DEF="$r27/agents/security.agent.md" ORCH_LOOP_ORCH_DEF="$r27/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$r27/agents/engineer.agent.md" ORCH_LOOP_REVIEWER_DEF="$r27/agents/reviewer.agent.md" sh "$0" >/dev/null 2>&1) || c27_fail=1
  if [ "$c27_fail" -eq 1 ]; then echo "selftest PASS: Orchestrator def omits operating reference -> exit 1"; else echo "selftest FAIL: missing operating reference NOT caught (reference teeth vacuous)"; sf=1; fi

  rm -rf "$d"
  if [ "$sf" -eq 0 ]; then echo "OK: orchestrator-loop-wired selftest (conflict-safe + design-skill + plan-skill + tdd-skill + review-skill + worktrees-skill + verification-skill + using-skills-keystone + debugging-skill + evals-skill + continuous-discovery-skill + operating-skill)"; exit 0
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
# (g) the kit's own review skill ships + is referenced by the Reviewer (brick #4)
check_review_skill "$REVIEW_SKILL_FILE" "$REVIEWER_DEF" || fail=1
# (h) the kit's own worktrees/isolation skill ships + is referenced by the Orchestrator (brick #5)
check_worktrees_skill "$WORKTREES_SKILL_FILE" "$ORCH_DEF" || fail=1
# (i) the kit's own verification skill ships + is referenced by BOTH the Engineer + Orchestrator (brick #6)
check_vbc_skill "$VBC_SKILL_FILE" "$ENGINEER_DEF" "$ORCH_DEF" || fail=1
# (j) the kit's own using-skills discovery keystone ships + indexes every on-disk spine skill + is referenced by the Orchestrator (brick #7)
check_keystone "$KEYSTONE_FILE" "$ORCH_DEF" || fail=1
# (k) the kit's own debugging skill ships + is referenced by the Engineer (root-cause-first; brick #8)
check_debugging_skill "$DEBUGGING_SKILL_FILE" "$ENGINEER_DEF" || fail=1
# (l) the kit's own evals skill ships + is referenced by BOTH the Engineer (eval-driven build) + the Security-reviewer (red-team/safety) (brick #9)
check_evals_skill "$EVALS_SKILL_FILE" "$ENGINEER_DEF" "$SECURITY_DEF" || fail=1
# (m) the kit's own continuous-discovery skill ships + is referenced by the Orchestrator (Product hat; brick #10)
check_discovery_skill "$DISCOVERY_SKILL_FILE" "$ORCH_DEF" || fail=1
# (n) the kit's own operating skill ships + is referenced by the Orchestrator (Ops hat; brick #11)
check_operating_skill "$OPERATING_SKILL_FILE" "$ORCH_DEF" || fail=1

[ "$fail" -eq 0 ] && { echo "OK: orchestrator-loop wired (roster headings + A2 kill-switch + trusted-denial + conflict-safe + design-skill + plan-skill + tdd-skill + review-skill + worktrees-skill + verification-skill + using-skills-keystone + debugging-skill + evals-skill + continuous-discovery-skill + operating-skill + golden-path job)"; exit 0; }
echo "FAIL: orchestrator-loop under-wired"; exit 1
