#!/bin/sh
# eval-ready.sh — conditional, fail-closed eval-discipline-declared check (gate parity, Slice 1).
#
# Companion to conformance/eval-readiness.md (the §7 Eval gate readiness; DEVELOPMENT-PROCESS.md §7).
# For an AI FEATURE it asserts the eval discipline is DECLARED: an EVAL-PLAN with a recorded
# regression threshold and a located harness/gate (not the [threshold]/[harness] placeholders).
# Non-AI projects (no model/prompt) are N/A (skip-pass).
#
# SCOPE — a green run proves the eval discipline is DECLARED, NOT that the evals PASS. The actual
# pass/regression is the §7 Eval gate (the suite runs in CI). Red-team + judge-independence are
# Manual rows in eval-readiness.md. A green run is necessary, not sufficient.
#
# Usage:
#   sh conformance/eval-ready.sh [project-dir]   (default: .)
#   sh conformance/eval-ready.sh --selftest
# Exit: 0 = OK or N/A · 1 = FAIL (AI feature with the discipline undeclared). POSIX sh; dash-clean.
set -eu

# Is $1 an AI feature? (any of: an evals/ dir, an EVAL-PLAN, or a RUNBOOK/CLAUDE 'AI feature: yes')
is_ai_feature() {
  _d="$1"
  [ -d "$_d/evals" ] && return 0
  for p in "$_d/EVAL-PLAN.md" "$_d/docs/EVAL-PLAN.md" "$_d/docs/sign-offs/EVAL-PLAN.md" "$_d/evals/EVAL-PLAN.md"; do
    [ -f "$p" ] && return 0
  done
  for m in "$_d/RUNBOOK.md" "$_d/CLAUDE.md"; do
    # tolerate markdown between the key and the value (e.g. '**AI feature:** yes') so a bold
    # marker is not silently missed (an AI feature escaping the gate is the worse direction).
    [ -f "$m" ] && grep -Eiq 'ai feature:[^[:alnum:]]*(yes|true)' "$m" && return 0
  done
  return 1
}

# Echo the EVAL-PLAN path if one exists, else empty.
find_plan() {
  for p in "$1/EVAL-PLAN.md" "$1/docs/EVAL-PLAN.md" "$1/docs/sign-offs/EVAL-PLAN.md" "$1/evals/EVAL-PLAN.md"; do
    [ -f "$p" ] && { printf '%s' "$p"; return 0; }
  done
  return 1
}

check_dir() {
  dir="$1"
  if ! is_ai_feature "$dir"; then
    echo "N/A: $dir is not an AI feature (no evals/ dir, no EVAL-PLAN, no 'AI feature: yes' marker) — no eval gate to declare"
    return 0
  fi
  fail=0
  plan=$(find_plan "$dir" || true)
  if [ -z "$plan" ]; then
    echo "FAIL: $dir is an AI feature but has no EVAL-PLAN.md — create one from templates/EVAL-PLAN-TEMPLATE.md"
    return 1
  fi
  # Record strings below must stay in sync with templates/EVAL-PLAN-TEMPLATE.md.
  # Placeholder detection keys on the literal [threshold]/[harness] tokens (robust to the
  # template's **bold** keys, which put `**` between the colon and the value).
  if ! grep -Eiq 'regression threshold:' "$plan"; then
    echo "FAIL: $plan has no 'Regression threshold:' — record the §7 Eval gate bar"; fail=1
  elif grep -Eiq 'regression threshold:.*\[threshold\]' "$plan"; then
    echo "FAIL: 'Regression threshold:' still holds the [threshold] placeholder — record a real bar"; fail=1
  fi
  if ! grep -Eiq 'harness:' "$plan"; then
    echo "FAIL: $plan has no 'Harness:' — locate the eval suite + how the gate runs it"; fail=1
  elif grep -Eiq 'harness:.*\[harness\]' "$plan"; then
    echo "FAIL: 'Harness:' still holds the [harness] placeholder — locate the real harness/gate"; fail=1
  fi
  if [ "$fail" -ne 0 ]; then return 1; fi
  echo "eval-ready: OK — eval discipline is DECLARED (EVAL-PLAN present, threshold + harness recorded). NOTE: does NOT run the evals or prove they pass — that is the §7 Eval gate in CI; red-team/judge-independence are Manual (eval-readiness.md)."
  return 0
}

# mktemp fixtures; assert each outcome. Fixtures LEFT in place (no rm -rf; 7e guard).
selftest() {
  st=0
  base=$(mktemp -d)
  PLAN_OK='# Eval Plan\n- **Regression threshold:** score >= 0.85, no metric drops > 2pts\n- **Harness:** evals/run.py, pytest-driven, run in CI on model/prompt change\n'

  d="$base/not-ai"; mkdir -p "$d"; printf '# a CLI tool\n' > "$d/README.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest PASS: non-AI -> N/A"; else echo "selftest FAIL: non-AI should be N/A"; st=1; fi

  d="$base/ai-evalsdir-noplan"; mkdir -p "$d/evals"; printf 'x\n' > "$d/evals/run.py"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest FAIL: AI(evals/) + no plan should FAIL"; st=1; else echo "selftest PASS: AI(evals/) + no plan -> FAIL"; fi

  d="$base/ai-marker-complete"; mkdir -p "$d"
  printf '# RUNBOOK\nAI feature: yes\n' > "$d/RUNBOOK.md"
  printf '%b' "$PLAN_OK" > "$d/EVAL-PLAN.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest PASS: AI(marker) + complete plan -> OK"; else echo "selftest FAIL: complete plan should pass"; st=1; fi

  # a BOLD marker ('**AI feature:** yes') must still bind (not slip to N/A): no plan -> FAIL
  d="$base/ai-boldmarker-noplan"; mkdir -p "$d"
  printf '# RUNBOOK\n- **AI feature:** yes\n' > "$d/RUNBOOK.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest FAIL: bold marker should bind -> FAIL (no plan)"; st=1; else echo "selftest PASS: bold marker binds -> FAIL (no plan)"; fi

  d="$base/ai-plan-threshold-placeholder"; mkdir -p "$d"
  printf '# Eval Plan\n- **Regression threshold:** [threshold]\n- **Harness:** evals/run.py\n' > "$d/EVAL-PLAN.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest FAIL: [threshold] placeholder should FAIL"; st=1; else echo "selftest PASS: [threshold] placeholder -> FAIL"; fi

  d="$base/ai-plan-harness-placeholder"; mkdir -p "$d"
  printf '# Eval Plan\n- **Regression threshold:** score >= 0.9\n- **Harness:** [harness]\n' > "$d/EVAL-PLAN.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest FAIL: [harness] placeholder should FAIL"; st=1; else echo "selftest PASS: [harness] placeholder -> FAIL"; fi

  if [ "$st" -ne 0 ]; then echo "eval-ready --selftest: FAIL" >&2; return 1; fi
  echo "eval-ready --selftest: OK (non-ai/no-plan/complete/threshold-placeholder/harness-placeholder all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *)          check_dir "${1:-.}"; exit $? ;;
esac
