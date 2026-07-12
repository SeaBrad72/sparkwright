#!/bin/sh
# responsible-ai-ready.sh — conditional, fail-closed AI-governance-declared check (RAI-1).
#
# Companion to conformance/responsible-ai-readiness.md (the §7 AI System Card gate;
# DEVELOPMENT-PROCESS.md §7). For an AI FEATURE it asserts the governance is DECLARED: an
# AI-SYSTEM-CARD with a recorded US risk classification and a named human-oversight mechanism
# (not the [classification]/[mechanism] placeholders). Non-AI projects are N/A (skip-pass).
#
# SCOPE — a green run proves the card is PRESENT + CLASSIFIED + OVERSIGHT-NAMED, NOT that the
# classification is correct, the AI is fair, or it is compliant. Those are Manual security/
# compliance-owner rows in responsible-ai-readiness.md. The good-citizen lines (prohibited-use,
# data-minimization, review/appeal path) are recommended defaults this check does NOT enforce.
# A green run is necessary, not sufficient.
#
# Usage:
#   sh conformance/responsible-ai-ready.sh [project-dir]   (default: .)
#   sh conformance/responsible-ai-ready.sh --selftest
# Exit: 0 = OK or N/A · 1 = FAIL (AI feature with the governance undeclared). POSIX sh; dash-clean.
set -eu

# Is $1 an AI feature? (evals/ dir, EVAL-PLAN, AI-SYSTEM-CARD, or RUNBOOK/CLAUDE 'AI feature: yes')
is_ai_feature() {
  _d="$1"
  [ -d "$_d/evals" ] && return 0
  for p in "$_d/EVAL-PLAN.md" "$_d/docs/EVAL-PLAN.md" "$_d/docs/sign-offs/EVAL-PLAN.md" "$_d/evals/EVAL-PLAN.md" \
           "$_d/AI-SYSTEM-CARD.md" "$_d/docs/AI-SYSTEM-CARD.md" "$_d/docs/sign-offs/AI-SYSTEM-CARD.md"; do
    [ -f "$p" ] && return 0
  done
  for m in "$_d/RUNBOOK.md" "$_d/CLAUDE.md"; do
    # tolerate markdown between key and value (e.g. '**AI feature:** yes') — bold must still bind.
    [ -f "$m" ] && grep -Eiq 'ai feature:[^[:alnum:]]*(yes|true)' "$m" && return 0
  done
  return 1
}

# Echo the AI-SYSTEM-CARD path if one exists, else empty.
find_card() {
  for p in "$1/AI-SYSTEM-CARD.md" "$1/docs/AI-SYSTEM-CARD.md" "$1/docs/sign-offs/AI-SYSTEM-CARD.md"; do
    [ -f "$p" ] && { printf '%s' "$p"; return 0; }
  done
  return 1
}

check_dir() {
  dir="$1"
  if ! is_ai_feature "$dir"; then
    echo "N/A: $dir is not an AI feature (no evals/ dir, no EVAL-PLAN, no AI-SYSTEM-CARD, no 'AI feature: yes' marker) — no AI governance to declare"
    return 0
  fi
  fail=0
  card=$(find_card "$dir" || true)
  if [ -z "$card" ]; then
    echo "FAIL: $dir is an AI feature but has no AI-SYSTEM-CARD.md — create one from templates/AI-SYSTEM-CARD-TEMPLATE.md"
    return 1
  fi
  # Record strings must stay in sync with templates/AI-SYSTEM-CARD-TEMPLATE.md.
  # Placeholder detection keys on the literal [classification]/[mechanism] tokens (robust to the
  # template's **bold** keys, which put `**` between the colon and the value).
  if ! grep -Eiq 'risk classification:' "$card"; then
    echo "FAIL: $card has no 'Risk classification:' — record the US risk classification (consequential / children's / prohibited)"; fail=1
  elif grep -Eiq 'risk classification:.*\[classification\]' "$card"; then
    echo "FAIL: 'Risk classification:' still holds the [classification] placeholder — record a real classification"; fail=1
  fi
  if ! grep -Eiq 'human oversight:' "$card"; then
    echo "FAIL: $card has no 'Human oversight:' — name the override/halt mechanism"; fail=1
  elif grep -Eiq 'human oversight:.*\[mechanism\]' "$card"; then
    echo "FAIL: 'Human oversight:' still holds the [mechanism] placeholder — name a real oversight mechanism"; fail=1
  fi
  if [ "$fail" -ne 0 ]; then return 1; fi
  echo "responsible-ai-ready: OK — AI System Card is PRESENT, classified, and oversight-named. NOTE: does NOT verify the classification is correct, the AI is fair, or it is compliant — those are Manual rows (responsible-ai-readiness.md). Good-citizen lines are recommended, not enforced."
  return 0
}

# mktemp fixtures; assert each outcome. Fixtures LEFT in place (no rm -rf; 7e guard).
selftest() {
  st=0
  base=$(mktemp -d)
  CARD_OK='# AI System Card\n- **Risk classification:** low-risk — none triggered\n- **Human oversight:** lead engineer can halt; standard human review\n'

  d="$base/not-ai"; mkdir -p "$d"; printf '# a CLI tool\n' > "$d/README.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest PASS: non-AI -> N/A"; else echo "selftest FAIL: non-AI should be N/A"; st=1; fi

  d="$base/ai-evalsdir-nocard"; mkdir -p "$d/evals"; printf 'x\n' > "$d/evals/run.py"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest FAIL: AI(evals/) + no card should FAIL"; st=1; else echo "selftest PASS: AI(evals/) + no card -> FAIL"; fi

  d="$base/ai-card-complete"; mkdir -p "$d"
  printf '%b' "$CARD_OK" > "$d/AI-SYSTEM-CARD.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest PASS: AI(card) + complete -> OK"; else echo "selftest FAIL: complete card should pass"; st=1; fi

  d="$base/ai-card-classification-placeholder"; mkdir -p "$d"
  printf '# AI System Card\n- **Risk classification:** [classification]\n- **Human oversight:** lead can halt\n' > "$d/AI-SYSTEM-CARD.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest FAIL: [classification] placeholder should FAIL"; st=1; else echo "selftest PASS: [classification] placeholder -> FAIL"; fi

  d="$base/ai-card-oversight-placeholder"; mkdir -p "$d"
  printf '# AI System Card\n- **Risk classification:** low-risk\n- **Human oversight:** [mechanism]\n' > "$d/AI-SYSTEM-CARD.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest FAIL: [mechanism] placeholder should FAIL"; st=1; else echo "selftest PASS: [mechanism] placeholder -> FAIL"; fi

  # a BOLD 'AI feature' marker must bind (not slip to N/A): no card -> FAIL
  d="$base/ai-boldmarker-nocard"; mkdir -p "$d"
  printf '# RUNBOOK\n- **AI feature:** yes\n' > "$d/RUNBOOK.md"
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest FAIL: bold marker should bind -> FAIL (no card)"; st=1; else echo "selftest PASS: bold marker binds -> FAIL (no card)"; fi

  if [ "$st" -ne 0 ]; then echo "responsible-ai-ready --selftest: FAIL" >&2; return 1; fi
  echo "responsible-ai-ready --selftest: OK (non-ai/no-card/complete/classification-placeholder/oversight-placeholder/bold-marker all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *)          check_dir "${1:-.}"; exit $? ;;
esac
