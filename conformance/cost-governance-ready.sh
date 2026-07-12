#!/bin/sh
# cost-governance-ready.sh — conditional, three-state cost-governance posture check (H3b).
#
# A PreToolUse guard cannot see token counts, so the kit does NOT enforce a spend cap — it ships a
# reference (docs/operations/cost-governance.md: a per-run budget-contract + stop discipline) and
# references the REAL enforcement (Anthropic API usage limits / a harness budget setting). This check
# verifies the posture is DECLARED + ATTESTED, mirroring containment-ready.sh / egress-policy.sh.
#
# ONE aspect, keyed on a RUNBOOK line; applicable when the project has a deploy/integration surface
# (where metered LLM/external spend lands) OR uses a metered LLM/AI feature (evals dir, AI System
# Card, or an Agentic:yes declaration) — even a CLI-only project that makes metered LLM calls:
#   Cost governance:  per-run budget + platform spend-cap (LLM/metered-API spend bounded)
#
# THREE-STATE:
#   exit 0 — PASS (declared + attested) OR N/A (no surface / RUNBOOK line records N/A)
#   exit 1 — FAIL (applicable surface, posture undeclared)
#   exit 2 — UNVERIFIED (declared but not attested) — NOT a pass.
# Escalation: under CI (CI env set) or --require, UNVERIFIED becomes exit 1.
#
# DECLARED = a RUNBOOK 'Cost governance:' line names a mechanism; ATTESTED = the line records
# 'enforced: <ISO date>' (not the [date] placeholder); N/A = the line records 'N/A — <reason>'.
#
# SCOPE — a green run proves the posture is DECLARED + ATTESTED, NOT that spend was actually capped
# (the cap is platform-owned). Necessary, not sufficient.
#
# Usage:
#   sh conformance/cost-governance-ready.sh [project-dir] [--require]   (default dir: .)
#   sh conformance/cost-governance-ready.sh --selftest
set -eu

REQUIRE="${REQUIRE:-0}"
[ -n "${CI:-}" ] && REQUIRE=1
DIR=.
for a in "$@"; do
  case "$a" in
    --require)  REQUIRE=1 ;;
    --selftest) ;;  # dispatched below
    -*) echo "usage: cost-governance-ready.sh [project-dir] [--require] | --selftest" >&2; exit 2 ;;
    *)  DIR="$a" ;;
  esac
done

# Metered-LLM / AI-feature surface? Returns 0 (true) if any AI-feature signal exists:
#   - an evals/ directory (metered evaluation runs)
#   - a filled AI System Card (AI-SYSTEM-CARD.md)
#   - a RUNBOOK.md or CLAUDE.md line matching 'Agentic: yes' (case-insensitive)
has_ai_surface() {
  _d="$1"
  [ -d "$_d/evals" ] && return 0
  [ -f "$_d/AI-SYSTEM-CARD.md" ] && return 0
  for _f in "$_d/RUNBOOK.md" "$_d/CLAUDE.md"; do
    if [ -f "$_f" ]; then
      grep -iqE '^[-*[:space:]]*Agentic:[-*[:space:]]*yes' "$_f" && return 0
    fi
  done
  return 1
}

# Deploy/integration surface? (Dockerfile or any GitHub workflow — where metered spend lands.)
# Also triggers for any metered-LLM / AI feature (has_ai_surface).
has_surface() {
  _d="$1"
  [ -f "$_d/Dockerfile" ] && return 0
  if [ -d "$_d/.github/workflows" ]; then
    for wf in "$_d"/.github/workflows/*.yml "$_d"/.github/workflows/*.yaml; do
      [ -f "$wf" ] && return 0
    done
  fi
  if has_ai_surface "$_d"; then return 0; fi
  return 1
}

# classify the one aspect -> echoes PASS | UNVERIFIED | FAIL | NA
classify_aspect() {
  _rb="$1"; _key="$2"
  _present=0; _is_na=0; _attested=0
  # Anchor the key to the START of a (optionally bulleted) line so a prose mention mid-line does
  # not count as a declaration.
  _pre="^[[:space:]]*[-*]?[[:space:]]*$_key:"
  if [ -f "$_rb" ]; then
    if grep -Eiq "${_pre}[[:space:]]*n/?a([^[:alnum:]]|\$)" "$_rb"; then _is_na=1; fi
    if grep -Eiq "$_pre" "$_rb"; then _present=1; fi
    if grep -Eiq "$_pre.*enforced:[[:space:]]*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" "$_rb"; then _attested=1; fi
  fi
  if [ "$_is_na" = "1" ]; then echo NA; return 0; fi
  if [ "$_present" = "0" ]; then echo FAIL; return 0; fi
  if [ "$_attested" = "1" ]; then echo PASS; return 0; fi
  echo UNVERIFIED
}

check_dir() {
  dir="$1"
  if ! has_surface "$dir"; then
    echo "N/A: $dir has no deploy/integration surface and no metered-LLM/AI feature (no Dockerfile / GitHub workflow / evals dir / AI System Card / Agentic:yes) — no metered LLM/external spend to govern"
    return 0
  fi
  rb="$dir/RUNBOOK.md"
  s=$(classify_aspect "$rb" "cost governance")
  echo "  Cost governance: $s"
  case "$s" in
    NA)
      echo "cost-governance-ready: OK — Cost governance N/A (no metered external/LLM spend)."
      return 0 ;;
    PASS)
      echo "cost-governance-ready: OK — Cost governance DECLARED + ATTESTED. NOTE: does NOT prove spend was actually capped (the cap is platform-owned — Anthropic usage limits / harness budget; docs/operations/cost-governance.md)."
      return 0 ;;
    FAIL)
      echo "FAIL: $dir has a deploy/integration surface or metered-LLM/AI feature but no Cost-governance posture — declare a per-run budget + platform spend-cap (or N/A with reason) per docs/operations/cost-governance.md"
      return 1 ;;
    UNVERIFIED)
      msg="$dir declares Cost governance but does not ATTEST enforcement (need 'enforced: <date>' on the line)"
      if [ "$REQUIRE" = "1" ]; then echo "FAIL: $msg — and attestation is required (CI/--require)."; return 1; fi
      echo "UNVERIFIED: $msg — attest in RUNBOOK. (NOT a pass.)"
      return 2 ;;
  esac
}

selftest() {
  st_fail=0
  base=$(mktemp -d)
  rc_of() { ( check_dir "$1" ) >/dev/null 2>&1 && echo 0 || echo $?; }
  expect() { # label dir want [require]
    _lbl="$1"; _dir="$2"; _want="$3"; _req="${4:-0}"
    _got=$( REQUIRE="$_req"; rc_of "$_dir" )
    if [ "$_got" = "$_want" ]; then echo "selftest PASS: $_lbl -> exit $_got"; else echo "selftest FAIL: $_lbl want $_want got $_got"; st_fail=1; fi
  }
  L='- Cost governance: per-run budget + Anthropic usage cap — enforced: 2026-06-01'

  d="$base/na-nosurface"; mkdir -p "$d"; printf '# a CLI tool\n' > "$d/README.md"
  expect "no-surface -> N/A" "$d" 0

  d="$base/fail-bare"; mkdir -p "$d"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n## Deploy\n- (no cost records)\n' > "$d/RUNBOOK.md"
  expect "surface, nothing declared -> FAIL" "$d" 1

  d="$base/pass"; mkdir -p "$d"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n## Deploy\n%s\n' "$L" > "$d/RUNBOOK.md"
  expect "declared + dated -> PASS" "$d" 0

  d="$base/unv-placeholder"; mkdir -p "$d"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n## Deploy\n- Cost governance: per-run budget — enforced: [date]\n' > "$d/RUNBOOK.md"
  expect "placeholder -> UNVERIFIED" "$d" 2

  d="$base/pass-na"; mkdir -p "$d"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n## Deploy\n- Cost governance: N/A — no metered external or LLM spend\n' > "$d/RUNBOOK.md"
  expect "N/A line -> PASS" "$d" 0

  # a substring heading must not satisfy the key
  d="$base/fail-substring"; mkdir -p "$d"; printf 'FROM scratch\n' > "$d/Dockerfile"
  printf '# RUNBOOK\n## Deploy\n- No cost governance yet: TODO — enforced: 2026-06-01\n' > "$d/RUNBOOK.md"
  expect "substring 'No cost governance' not a match -> FAIL" "$d" 1

  expect "declared-not-attested + require -> FAIL" "$base/unv-placeholder" 1 1

  # --- New AI-surface fixtures ---

  # evals/ dir only — no Dockerfile/workflow, no posture → APPLICABLE → FAIL (exit 1)
  d="$base/ai-evals-noposture"; mkdir -p "$d/evals"
  printf '# a CLI LLM tool\n' > "$d/README.md"
  expect "evals-only, no posture -> FAIL" "$d" 1

  # evals/ dir + RUNBOOK with declared+attested posture → PASS (exit 0)
  d="$base/ai-evals-pass"; mkdir -p "$d/evals"
  printf '# RUNBOOK\n## Cost\n%s\n' "$L" > "$d/RUNBOOK.md"
  expect "evals-only + declared+attested -> PASS" "$d" 0

  # AI-SYSTEM-CARD.md only — no other surface, no posture → APPLICABLE → FAIL (exit 1)
  d="$base/ai-card-noposture"; mkdir -p "$d"
  printf '# AI System Card\n' > "$d/AI-SYSTEM-CARD.md"
  expect "AI-SYSTEM-CARD only, no posture -> FAIL" "$d" 1

  # evals/ dir + N/A escape → PASS (exit 0) — N/A path still reachable
  d="$base/ai-evals-na"; mkdir -p "$d/evals"
  printf '# RUNBOOK\n## Cost\n- Cost governance: N/A — no metered spend (evals use local models)\n' > "$d/RUNBOOK.md"
  expect "evals-only + N/A escape -> PASS" "$d" 0

  # Agentic:yes in CLAUDE.md — no other surface, no posture → APPLICABLE → FAIL (exit 1)
  d="$base/ai-agentic-flag"; mkdir -p "$d"
  printf '# CLAUDE.md\nAgentic: yes\n' > "$d/CLAUDE.md"
  expect "Agentic:yes in CLAUDE.md, no posture -> FAIL" "$d" 1

  # Bulleted/bold form '- **Agentic:** yes' in CLAUDE.md — no other surface, no posture → APPLICABLE → FAIL
  d="$base/ai-agentic-bulleted"; mkdir -p "$d"
  printf '# CLAUDE.md\n- **Agentic:** yes\n' > "$d/CLAUDE.md"
  expect "bulleted Agentic:**yes in CLAUDE.md, no posture -> FAIL" "$d" 1

  if [ "$st_fail" -ne 0 ]; then echo "cost-governance-ready --selftest: FAIL" >&2; return 1; fi
  echo "cost-governance-ready --selftest: OK (na/bare-fail/pass/placeholder-unv/na-pass/substring-fail/escalation all behaved; ai-evals-noposture/ai-evals-pass/ai-card-noposture/ai-evals-na/ai-agentic-flag/ai-agentic-bulleted all behaved; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *)          check_dir "$DIR"; exit $? ;;
esac
