#!/bin/sh
# orchestrator-loop-wired.sh -- behaviour-lock for the E3a/E3b thin orchestration loop.
# Asserts the roster agent-defs have the required six-heading structure, that the loop
# script wires the runaway kill-switch (A2: runaway-guard.sh step), the trusted-denial
# span (kit.denied), and the conflict-safe wiring (kit.conflict + git diff --name-only),
# that each kit-own spine skill ships + carries its kit-distinctive markers + is referenced
# by the owning seat(s), that the using-skills discovery keystone indexes every on-disk
# spine skill (structural -- enumerated, not a hardcoded list), and that the golden-path CI
# job exercising the loop is present.
#
# DATA-DRIVEN: the 10 uniform spine-skill checks are expressed as rows of spine_table()
# consumed by one generic check_spine_skill. The 4 structurally-distinct checks
# (check_roster, check_loop, check_gp, check_keystone) stay bespoke. A new spine brick is a
# single spine_table() row (+ one skill_path() case if it is a new env-var). The 27-case
# behaviour is preserved -- proven by the scratchpad differential harness (old vs new across
# the full fixture matrix) and the table-generated --selftest below.
#
# This locks the WIRING; behaviour (the loop actually halts on guard STOP, emits a denied
# span, and detects conflicts) is proven by orchestrator-run.sh --selftest and the
# golden-path job.
# SCOPE: kit-self lock (the golden-path job is the kit's OWN pipeline).
# Usage: sh conformance/orchestrator-loop-wired.sh [--selftest]
set -eu

TAB=$(printf '\t')

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

# The four discovery-discipline markers the keystone must carry (kept in sync with
# check_keystone's literal list below; one place the keystone selftest also reads).
KEYSTONE_MARKERS="name: using-skills|invoke by reading|before acting|user instructions"

# ---- the spine table (the data that drives the 10 uniform skill checks) ----------------------
# One row per spine skill: <name> TAB <markers(pipe-separated)> TAB <refs(;-separated; each dk:label)>
#   name   -- the skills/<name>/ directory; resolved to a (possibly-overridden) path by skill_path().
#   markers-- kit-distinctive phrases ALL of which must appear (a generic paraphrase fails).
#   refs   -- owning seat(s): dk in {orch,eng,rev,sec} + the verbatim "not wired" label.
# NOTE: labels must not contain ',' (check_spine_skill splits refs on ',') or ';'/':'.
#       markers may contain spaces and ',' (split only on '|'); never a TAB or '|'.
spine_table() {
cat <<TABLE
design${TAB}name: design|<HARD-GATE>|## When to use|Design-intent lens|RE-SELECT|Honest ceiling${TAB}orch:Architect hat not wired
plan${TAB}name: plan|## When to use|INVEST|AMBER|Conformance lock|Dual review${TAB}orch:plan skill not wired
tdd${TAB}name: tdd|## When to use|Red-Green-Refactor|non-vacuity|critical path|evals${TAB}eng:tdd skill not wired to the Engineer
review${TAB}name: review|## When to use|Confidence|adversarial|builder|NEEDS-FIXES${TAB}rev:review skill not wired to the Reviewer
worktrees${TAB}name: worktrees|disjoint file sets|--no-renames|out-of-slice|native${TAB}orch:Isolation not wired to the Orchestrator
verification${TAB}name: verification|confabulation|clone dry-run|evidence before claims|fresh${TAB}eng:evidence-before-claims not wired to the Engineer;orch:confabulation-proofing not wired to the Orchestrator
debugging${TAB}name: debugging|root cause|reproduce|regression test|one hypothesis${TAB}eng:root-cause debugging not wired to the Engineer
evals${TAB}name: evals|eval-driven|judge|red-team|threshold${TAB}eng:eval-driven build not wired to the Engineer;sec:red-team/safety lens not wired to the Security-reviewer
continuous-discovery${TAB}name: continuous-discovery|discovery partner|outcome over output|opportunity solution tree|riskiest assumption|small bet${TAB}orch:Product hat not wired
operating${TAB}name: operating|blast radius|advisory, not actuating|the human commands the catastrophic action|autonomy tier|surface, don't actuate${TAB}orch:Ops hat not wired to the Orchestrator
TABLE
}

# name -> the (possibly-overridden) skill-file path
skill_path() {
  case $1 in
    design) echo "$SKILL_FILE" ;;
    plan) echo "$PLAN_SKILL_FILE" ;;
    tdd) echo "$TDD_SKILL_FILE" ;;
    review) echo "$REVIEW_SKILL_FILE" ;;
    worktrees) echo "$WORKTREES_SKILL_FILE" ;;
    verification) echo "$VBC_SKILL_FILE" ;;
    debugging) echo "$DEBUGGING_SKILL_FILE" ;;
    evals) echo "$EVALS_SKILL_FILE" ;;
    continuous-discovery) echo "$DISCOVERY_SKILL_FILE" ;;
    operating) echo "$OPERATING_SKILL_FILE" ;;
    *) echo "" ;;
  esac
}

# seat key -> the (possibly-overridden) agent-def path
def_path() {
  case $1 in
    orch) echo "$ORCH_DEF" ;;
    eng) echo "$ENGINEER_DEF" ;;
    rev) echo "$REVIEWER_DEF" ;;
    sec) echo "$SECURITY_DEF" ;;
    *) echo "" ;;
  esac
}

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

check_spine_skill() {  # <skill_file> <markers(|-sep)> <refs(;-sep; each: defpath,refpath,label)>
  # Generic spine-skill lock: file exists, carries every kit-distinctive marker, and each
  # owning seat references it. Drives the 10 uniform checks from spine_table(). The keystone
  # (structural index) is NOT one of these -- it stays bespoke in check_keystone.
  s=$1; markers=$2; refs=$3; miss=0
  [ -f "$s" ] || { echo "FAIL: missing skill $s"; return 1; }
  set -f                         # the splits below are intentional; suppress globbing
  OLD_IFS=$IFS
  IFS='|'
  for m in $markers; do
    # grep -qF -- : markers may begin with '-' (e.g. --no-renames); '--' ends grep options.
    grep -qF -- "$m" "$s" || { echo "FAIL: $s missing kit-distinctive marker '$m' (generic copy?)"; miss=1; }
  done
  IFS=';'
  for r in $refs; do
    [ -n "$r" ] || continue
    d=${r%%,*}; rest=${r#*,}; rp=${rest%%,*}; lbl=${rest#*,}
    [ -f "$d" ] || { echo "FAIL: missing def $d"; miss=1; continue; }
    grep -qF "$rp" "$d" || { echo "FAIL: $d does not reference $rp ($lbl)"; miss=1; }
  done
  IFS=$OLD_IFS
  set +f
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
  for dd in "$skills_dir"/*/; do
    [ -f "$dd/SKILL.md" ] || continue          # only real skills (filters a literal no-match glob too)
    name=$(basename "$dd")
    [ "$name" = "using-skills" ] && continue   # the keystone need not index itself
    grep -qF "skills/$name" "$s" || { echo "FAIL: $s does not index on-disk spine skill 'skills/$name' (index not exhaustive)"; miss=1; }
  done
  [ -f "$o" ] || { echo "FAIL: missing orchestrator def $o"; return 1; }
  grep -qF "skills/using-skills/SKILL.md" "$o" || { echo "FAIL: $o does not reference skills/using-skills/SKILL.md (discovery start-here not wired to the Orchestrator)"; miss=1; }
  return $miss
}

# ============================ selftest (table-driven) =========================================
if [ "${1:-}" = "--selftest" ]; then
  d=$(mktemp -d); trap 'rm -rf "$d"' EXIT INT TERM
  table=$(spine_table)
  ALL_SKILLS=$(printf '%s\n' "$table" | cut -f1 | tr '\n' ' ')

  st_defbase() { case $1 in orch) echo orchestrator.agent.md ;; eng) echo engineer.agent.md ;; rev) echo reviewer.agent.md ;; sec) echo security.agent.md ;; esac; }

  # Build a fully-conformant fixture tree at $1 from the SAME spine_table().
  st_build() {
    t=$1
    mkdir -p "$t/agents" "$t/scripts" "$t/gh" "$t/skills"
    for f in $ROSTER_FILES; do
      printf '## Role\nx\n## Responsibilities\nx\n## Stance\nx\n## Task-Context-Contract\nx\n## Tools needed\nx\n## Success criteria\nx\n' > "$t/agents/$f"
    done
    printf '#!/bin/sh\nrunaway-guard.sh step\nkit.denied=true\nkit.conflict=false\ngit diff --name-only HEAD\n' > "$t/scripts/orchestrator-run.sh"
    chmod +x "$t/scripts/orchestrator-run.sh"
    printf 'jobs:\n  orchestrator-loop:\n    steps:\n      - run: sh scripts/orchestrator-run.sh\n' > "$t/gh/gp.yml"
    printf '%s\n' "$table" | while IFS="$TAB" read -r name markers refs; do
      [ -n "$name" ] || continue
      mkdir -p "$t/skills/$name"
      {
        printf -- '---\nname: %s\n---\n' "$name"
        printf '%s\n' "$markers" | tr '|' '\n' | while IFS= read -r m; do
          [ "$m" = "name: $name" ] && continue   # the name marker lives in the frontmatter above
          printf '%s\n' "$m"
        done
      } > "$t/skills/$name/SKILL.md"
      printf '%s\n' "$refs" | tr ';' '\n' | while IFS= read -r r; do
        [ -n "$r" ] || continue
        printf 'skills/%s/SKILL.md\n' "$name" >> "$t/agents/$(st_defbase "${r%%:*}")"
      done
    done
    mkdir -p "$t/skills/using-skills"
    {
      printf -- '---\nname: using-skills\n---\n'
      printf '%s\n' "$KEYSTONE_MARKERS" | tr '|' '\n' | while IFS= read -r m; do
        [ "$m" = "name: using-skills" ] && continue
        printf '%s\n' "$m"
      done
      for s in $ALL_SKILLS; do printf 'skills/%s\n' "$s"; done
    } > "$t/skills/using-skills/SKILL.md"
    printf 'skills/using-skills/SKILL.md\n' >> "$t/agents/orchestrator.agent.md"
  }

  # Run THIS script's main-path against the fixture tree $1; echo its exit code.
  # '|| rc=$?' both captures the (often-intentionally-nonzero) code AND neutralizes set -e.
  st_run() {
    t=$1; rc=0
    ORCH_LOOP_ROSTER_DIR="$t/agents" ORCH_LOOP_SCRIPT="$t/scripts/orchestrator-run.sh" ORCH_LOOP_GP="$t/gh/gp.yml" \
    ORCH_LOOP_SKILL="$t/skills/design/SKILL.md" ORCH_LOOP_PLAN_SKILL="$t/skills/plan/SKILL.md" ORCH_LOOP_TDD_SKILL="$t/skills/tdd/SKILL.md" \
    ORCH_LOOP_REVIEW_SKILL="$t/skills/review/SKILL.md" ORCH_LOOP_WORKTREES_SKILL="$t/skills/worktrees/SKILL.md" ORCH_LOOP_VBC_SKILL="$t/skills/verification/SKILL.md" \
    ORCH_LOOP_KEYSTONE="$t/skills/using-skills/SKILL.md" ORCH_LOOP_DEBUGGING_SKILL="$t/skills/debugging/SKILL.md" ORCH_LOOP_EVALS_SKILL="$t/skills/evals/SKILL.md" \
    ORCH_LOOP_DISCOVERY_SKILL="$t/skills/continuous-discovery/SKILL.md" ORCH_LOOP_OPERATING_SKILL="$t/skills/operating/SKILL.md" \
    ORCH_LOOP_ORCH_DEF="$t/agents/orchestrator.agent.md" ORCH_LOOP_ENGINEER_DEF="$t/agents/engineer.agent.md" \
    ORCH_LOOP_REVIEWER_DEF="$t/agents/reviewer.agent.md" ORCH_LOOP_SECURITY_DEF="$t/agents/security.agent.md" \
    sh "$0" >/dev/null 2>&1 || rc=$?
    echo "$rc"
  }

  st_drop() { grep -vxF -- "$2" "$1" > "$1.t" 2>/dev/null || true; mv "$1.t" "$1"; }

  # assert exit code; record any failure to a file (subshell-proof accumulation)
  st_expect() {
    got=$(st_run "$d/fx")
    if [ "$got" = "$2" ]; then echo "selftest PASS: $1"; else echo "selftest FAIL: $1 (expected $2, got $got)"; echo x >> "$d/sf.fail"; fi
  }
  fresh() { rm -rf "$d/fx"; st_build "$d/fx"; }

  # -- liveness anchor: fully conformant -> exit 0 --
  fresh; st_expect "conformant fixture -> exit 0" 0

  # -- bespoke negatives (roster heading + A2 kill-switch + conflict teeth) --
  fresh; st_drop "$d/fx/agents/orchestrator.agent.md" "## Stance"; st_expect "missing '## Stance' heading -> exit 1" 1
  fresh; st_drop "$d/fx/scripts/orchestrator-run.sh" "runaway-guard.sh step"; st_expect "missing 'runaway-guard.sh step' (A2 teeth) -> exit 1" 1
  fresh; st_drop "$d/fx/scripts/orchestrator-run.sh" "kit.conflict=false"; st_expect "missing 'kit.conflict' (conflict teeth) -> exit 1" 1

  # -- per-skill marker teeth + reference teeth (table-driven) --
  # One representative marker-drop per skill proves the marker loop is load-bearing (matches the
  # original's one-marker-per-skill coverage). EXHAUSTIVE per-marker teeth are the build-time
  # differential harness's job (scratchpad/orch-loop-refactor/diff-harness.sh), not CI's.
  # Every seat reference IS exercised (refs are few; each must independently fail when omitted).
  printf '%s\n' "$table" | while IFS="$TAB" read -r name markers refs; do
    [ -n "$name" ] || continue
    # representative = the first body marker (the one after the frontmatter "name:" marker)
    m=$(printf '%s\n' "$markers" | tr '|' '\n' | sed -n '2p')
    fresh; st_drop "$d/fx/skills/$name/SKILL.md" "$m"
    st_expect "$name skill missing kit-distinctive marker '$m' -> exit 1" 1
    printf '%s\n' "$refs" | tr ';' '\n' | while IFS= read -r r; do
      [ -n "$r" ] || continue
      base=$(st_defbase "${r%%:*}")
      fresh; st_drop "$d/fx/agents/$base" "skills/$name/SKILL.md"
      st_expect "$name reference omitted from $base -> exit 1" 1
    done
  done

  # -- keystone teeth: each discipline marker + the orchestrator reference + the structural index --
  printf '%s\n' "$KEYSTONE_MARKERS" | tr '|' '\n' | while IFS= read -r m; do
    fresh; st_drop "$d/fx/skills/using-skills/SKILL.md" "$m"
    st_expect "keystone missing discipline marker '$m' -> exit 1" 1
  done
  fresh; st_drop "$d/fx/agents/orchestrator.agent.md" "skills/using-skills/SKILL.md"; st_expect "Orchestrator omits keystone reference -> exit 1" 1
  fresh; mkdir -p "$d/fx/skills/zzz-probe"; printf -- '---\nname: zzz-probe\n---\nx\n' > "$d/fx/skills/zzz-probe/SKILL.md"; st_expect "on-disk skill not indexed in keystone (structural teeth) -> exit 1" 1

  if [ -f "$d/sf.fail" ]; then
    echo "FAIL: orchestrator-loop-wired selftest"; exit 1
  fi
  echo "OK: orchestrator-loop-wired selftest (data-driven: roster + loop + golden-path + spine table + keystone)"; exit 0
fi
# ============================ end selftest ====================================================

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
# (d) every uniform spine skill ships + carries its markers + is referenced by its owning seat(s)
while IFS="$TAB" read -r name markers refs; do
  [ -n "$name" ] || continue
  sfile=$(skill_path "$name")
  rarg=""
  OLD_IFS=$IFS; IFS=';'
  for r in $refs; do
    IFS=$OLD_IFS
    [ -n "$r" ] || { IFS=';'; continue; }
    dk=${r%%:*}; lbl=${r#*:}
    rarg="${rarg}$(def_path "$dk"),skills/${name}/SKILL.md,${lbl};"
    IFS=';'
  done
  IFS=$OLD_IFS
  check_spine_skill "$sfile" "$markers" "$rarg" || fail=1
done <<TABLE
$(spine_table)
TABLE
# (e) the using-skills discovery keystone indexes every on-disk spine skill + is referenced by the Orchestrator
check_keystone "$KEYSTONE_FILE" "$ORCH_DEF" || fail=1

[ "$fail" -eq 0 ] && { echo "OK: orchestrator-loop wired (roster headings + A2 kill-switch + trusted-denial + conflict-safe + spine-table skills + using-skills-keystone + golden-path job)"; exit 0; }
echo "FAIL: orchestrator-loop under-wired"; exit 1
