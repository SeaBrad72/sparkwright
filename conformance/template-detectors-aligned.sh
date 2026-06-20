#!/bin/sh
# template-detectors-aligned.sh — lock the kit's conformance DETECTORS to the kit's own TEMPLATE output.
#
# The dogfood found detectors that SILENTLY SKIP a project declaring sensitive / agentic / AI data in the
# exact format the PROJECT-CLAUDE and AI-SYSTEM-CARD templates produce — a Confidential project bypassing
# its own DPIA gate, an agentic project skipping its agent-ops gate, an AI System Card under docs/sign-offs/
# (the location the template recommends) reported as missing. Silent-skip (N/A) is worse than a loud FAIL:
# the gate looks satisfied. This check stamps a fixture project using the templates' OWN declaration format
# and asserts every detector FIRES (does not silent-skip). It goes red if a detector's regex/path drifts
# from the template it ships.
#
#   sh conformance/template-detectors-aligned.sh [--selftest]
# Exit: 0 = every detector fires on the template's own format · 1 = a detector silent-skips · 2 = setup.
# POSIX sh; dash-clean. (--selftest is an alias for the normal run — the check IS a self-contained test.)
set -eu

ROOT="${TDA_ROOT:-.}"
CONF="$ROOT/conformance"
TPL="$ROOT/templates/PROJECT-CLAUDE-TEMPLATE.md"

note() { printf '%s\n' "$*"; }

# (1) Drift guard: the format markers this check stamps MUST still exist in the shipped template, so the
# fixture below can never quietly diverge from what adopters are actually told to write.
check_template_markers() {
  _rc=0
  if [ ! -f "$TPL" ]; then note "FAIL: template missing: $TPL"; return 1; fi
  grep -Eiq 'data classification[^:]*:' "$TPL" || { note "FAIL: PROJECT-CLAUDE template lost its 'Data classification' field"; _rc=1; }
  grep -Eiq '^[-*[:space:]]*agentic[^:]*:' "$TPL" || { note "FAIL: PROJECT-CLAUDE template lacks a structured 'Agentic:' field (prose marker won't be detected)"; _rc=1; }
  return $_rc
}

# (2) Stamp a fixture project that DECLARES sensitive + agentic + an AI feature, in the templates' format.
stamp_fixture() {
  _d="$1"
  mkdir -p "$_d/docs/sign-offs"
  {
    printf '# Project CLAUDE\n\n'
    printf -- '- **Data classification** (§privacy): Confidential — the highest tier this project handles.\n'
    printf -- '- **Agentic** *(does this project run autonomous agents?)*: yes\n'
  } > "$_d/CLAUDE.md"
  # RUNBOOK WITHOUT an Agent-ops record, so agentops-ready must FIRE (FAIL), proving it detected agentic.
  printf '# RUNBOOK\n\n## 8. Monitoring & alerting\n- Error tracking: Sentry\n' > "$_d/RUNBOOK.md"
  # AI System Card + Eval Plan under docs/sign-offs/ — the location the AI-SYSTEM-CARD template recommends.
  printf '# AI System Card\n- **Risk classification:** limited risk\n- **Human oversight:** the lead can halt the feature\n' > "$_d/docs/sign-offs/AI-SYSTEM-CARD.md"
  printf '# Eval Plan\n- **Regression threshold:** score >= 0.85\n- **Harness:** evals/run.py, run in CI\n' > "$_d/docs/sign-offs/EVAL-PLAN.md"
}

# assert_fires <label> <detector-output> : FAIL if the detector silent-skipped (printed an N/A line).
assert_not_na() {
  _label="$1"; _out="$2"
  if printf '%s\n' "$_out" | grep -Eq '(^|[^A-Za-z])N/A'; then
    note "FAIL: $_label SILENTLY SKIPPED the template-format declaration (N/A) — gate bypassed:"
    printf '       %s\n' "$_out"
    return 1
  fi
  if ! printf '%s\n' "$_out" | grep -Eq 'FAIL|OK'; then
    note "FAIL: $_label produced no recognizable verdict (FAIL/OK) — output: $_out"
    return 1
  fi
  note "PASS: $_label fires on the template's own format"
  return 0
}

run() {
  fail=0
  check_template_markers || fail=1

  d=$(mktemp -d)
  stamp_fixture "$d"

  out=$(sh "$CONF/privacy-ready.sh" "$d" 2>&1 || true)
  assert_not_na "privacy-ready (Confidential)" "$out" || fail=1

  out=$(sh "$CONF/agentops-ready.sh" "$d" 2>&1 || true)
  assert_not_na "agentops-ready (Agentic: yes)" "$out" || fail=1

  out=$(sh "$CONF/responsible-ai-ready.sh" "$d" 2>&1 || true)
  assert_not_na "responsible-ai-ready (AI System Card @ docs/sign-offs/)" "$out" || fail=1

  out=$(sh "$CONF/eval-ready.sh" "$d" 2>&1 || true)
  assert_not_na "eval-ready (EVAL-PLAN @ docs/sign-offs/)" "$out" || fail=1

  if [ "$fail" -eq 0 ]; then
    note "OK: every conformance detector fires on the kit's own template format (no silent skips)"
    return 0
  fi
  note "FAIL: a detector silently skips the kit's own template format (see above) — a declared project would bypass its gate"
  return 1
}

case "${1:-}" in
  ""|--selftest) run ;;
  *) echo "usage: template-detectors-aligned.sh [--selftest]" >&2; exit 2 ;;
esac
exit $?
