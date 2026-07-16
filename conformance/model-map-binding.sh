#!/bin/sh
# model-map-binding.sh — KW20(b) Slice 2b: proves the claude-code dispatch surface BINDS the abstract
# model tier to a concrete model (reads .kit/model-map.conf + the TCC model_tier, passes model:).
#
# What it changes: nothing (read-only verifier).
# Guardrails: structural proof only. HONEST CEILING — a green run proves the dispatch prose INSTRUCTS
#   the map-read + model:-pass; it does NOT prove the harness ran any subagent on the mapped model
#   (that is NATIVE / un-gateable). On a single-model harness the tier is advisory.
#
# Usage: sh conformance/model-map-binding.sh | --selftest
#   No-arg is the hard live check (native proof calls it with no args). --require is accepted as a
#   silent back-compat alias for no-arg — there is no separate advisory mode, so it is not advertised.
set -eu

# ---- the structural proof --------------------------------------------------------------------
# check_root <root> -> 0 (every binding present) / 1 (any miss). Echoes a PASS/FAIL line per check
# so a live FAILURES line is self-locating.
check_root() {
  _root=$1; _miss=0
  _map="$_root/.kit/model-map.conf"
  _orch="$_root/.claude/agents/orchestrator.md"
  _guard="$_root/.claude/hooks/guard-core.sh"

  # 1. the adopter-owned map declares all three abstract tiers.
  if [ -f "$_map" ] && grep -q '^deep=' "$_map" && grep -q '^fast=' "$_map" && grep -q '^light=' "$_map"; then
    echo "PASS: .kit/model-map.conf declares deep=/fast=/light="
  else
    echo "FAIL: .kit/model-map.conf missing or does not declare all of deep=/fast=/light="
    _miss=1
  fi

  # 2. the claude-code dispatch surface binds tier -> model (three tokens).
  if [ -f "$_orch" ] && grep -q 'model-map\.conf' "$_orch"; then
    echo "PASS: orchestrator.md resolves through .kit/model-map.conf"
  else
    echo "FAIL: orchestrator.md does not name model-map.conf (tier is never resolved to a model)"
    _miss=1
  fi
  if [ -f "$_orch" ] && grep -q 'model:' "$_orch"; then
    echo "PASS: orchestrator.md passes the model: parameter"
  else
    echo "FAIL: orchestrator.md does not pass model: (the resolved model is never dispatched)"
    _miss=1
  fi
  if [ -f "$_orch" ] && grep -qi 'model_tier\|Model tier' "$_orch"; then
    echo "PASS: orchestrator.md reads the TCC model_tier field"
  else
    echo "FAIL: orchestrator.md does not read the TCC model_tier / Model tier field"
    _miss=1
  fi

  # 3. completeness lock (RESOLVES the Task-1 security LOW): the guard keeps model-map.conf
  #    control-plane, so a future edit dropping the guard lock reddens THIS check too.
  if [ -f "$_guard" ] && grep -q 'model-map\.conf' "$_guard"; then
    echo "PASS: guard-core.sh locks .kit/model-map.conf as control-plane"
  else
    echo "FAIL: guard-core.sh does not lock model-map.conf (an agent remap could defeat the pins)"
    _miss=1
  fi

  return "$_miss"
}

# ---- live mode -------------------------------------------------------------------------------
run_live() {
  ROOT=$(cd "$(dirname "$0")/.." && pwd)
  if check_root "$ROOT"; then
    echo "model-map-binding: ALL PASS"
    return 0
  fi
  echo "model-map-binding: FAILURES"
  return 1
}

# ---- selftest (tree-independent; the check must be RED-able) ----------------------------------
# Fixtures are built INSIDE this script at runtime (mktemp -d, printf/grep -v writing temp files),
# so the mutate is invisible to the guard and never touches the real tree. Fixtures LEFT in place
# (no rm -rf; the 7e guard convention). The good fixture is hand-authored (not a copy of the real
# tree), so the selftest proves the CHECK LOGIC decoupled from whether the live tree is wired yet.
selftest() {
  st=0
  base=$(mktemp -d)

  # A minimal, COMPLETE good fixture: each binding token on its own line so a single-token strip
  # isolates exactly one negative.
  mk_good() {
    _d=$1
    mkdir -p "$_d/.kit" "$_d/.claude/agents" "$_d/.claude/hooks"
    printf 'deep=opus\nfast=sonnet\nlight=haiku\n' > "$_d/.kit/model-map.conf"
    # Mirrors the real doc shape: ONE instruction line carries the literal model: token, and a
    # separate honest-ceiling caveat line references the model parameter WITHOUT the literal token.
    # This is what lets Negative D prove the predicate is anchored to the instruction, not the caveat.
    {
      printf 'Native model binding (claude-code).\n'
      printf 'Read the step Task-Context-Contract model_tier field.\n'
      printf 'Resolve the abstract tier through .kit/model-map.conf (deep/fast/light -> model id).\n'
      printf 'Pass the resolved model as the model: parameter to the Task spawn.\n'
      printf 'Honest ceiling: passing the model parameter declares the dispatch intent; native/un-gateable.\n'
    } > "$_d/.claude/agents/orchestrator.md"
    printf '# guard-core\n.kit/model-map.conf is control-plane and guard-locked\n' > "$_d/.claude/hooks/guard-core.sh"
  }

  # in-fixture line strip (temp file -> replace), never the real tree.
  strip() {
    _file=$1; _pat=$2
    grep -v "$_pat" "$_file" > "$_file.tmp"
    mv "$_file.tmp" "$_file"
  }

  # POSITIVE: a complete good fixture must go GREEN.
  mk_good "$base/good"
  if check_root "$base/good" >/dev/null 2>&1; then
    echo "selftest PASS: good fixture -> PASS"
  else
    echo "selftest FAIL: a complete good fixture wrongly reddened"; st=1
  fi

  # NEGATIVE A (load-bearing): strip the model: token from orchestrator.md -> must FAIL.
  mk_good "$base/negA"
  strip "$base/negA/.claude/agents/orchestrator.md" 'model:'
  if check_root "$base/negA" >/dev/null 2>&1; then
    echo "selftest FAIL: orchestrator.md with model: stripped still passed (check is dead)"; st=1
  else
    echo "selftest PASS: model: stripped -> FAIL"
  fi

  # NEGATIVE B (load-bearing): strip the model-map.conf token from orchestrator.md -> must FAIL.
  mk_good "$base/negB"
  strip "$base/negB/.claude/agents/orchestrator.md" 'model-map.conf'
  if check_root "$base/negB" >/dev/null 2>&1; then
    echo "selftest FAIL: orchestrator.md with model-map.conf stripped still passed (check is dead)"; st=1
  else
    echo "selftest PASS: model-map.conf stripped -> FAIL"
  fi

  # NEGATIVE C (load-bearing): remove the guard lock line -> must FAIL (the completeness lock).
  mk_good "$base/negC"
  strip "$base/negC/.claude/hooks/guard-core.sh" 'model-map.conf'
  if check_root "$base/negC" >/dev/null 2>&1; then
    echo "selftest FAIL: guard-core.sh with the model-map.conf lock removed still passed (lock is dead)"; st=1
  else
    echo "selftest PASS: guard lock line removed -> FAIL"
  fi

  # NEGATIVE D (anti-vacuity): remove ONLY the instruction line's model: token; the honest-ceiling
  # caveat (which does NOT carry the literal token) is retained. The predicate must be anchored to
  # the binding INSTRUCTION, so with the instruction gone the check must FAIL even though a caveat
  # line still mentions the model parameter. (Guards against the latent vacuity where a caveat's
  # literal `model:` would keep the check green after the instruction was deleted.)
  mk_good "$base/negD"
  strip "$base/negD/.claude/agents/orchestrator.md" 'model:'
  if check_root "$base/negD" >/dev/null 2>&1; then
    echo "selftest FAIL: instruction model: stripped (caveat kept) still passed (check is vacuous)"; st=1
  else
    echo "selftest PASS: instruction model: stripped (caveat kept) -> FAIL"
  fi

  if [ "$st" = 0 ]; then
    echo "model-map-binding --selftest: OK (fixtures in $base)"
  else
    echo "model-map-binding --selftest: FAIL"
  fi
  return "$st"
}

case "${1:-}" in
  --selftest) selftest ;;
  --require|'') run_live ;;
  *) echo "usage: model-map-binding.sh | --selftest" >&2; exit 2 ;;
esac
