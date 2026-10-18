#!/bin/sh
# template-detectors-aligned.sh — lock the kit's conformance DETECTORS to the kit's own TEMPLATE output.
#
# The dogfood found detectors that SILENTLY SKIP a project declaring sensitive / agentic / AI data in the
# exact format the PROJECT-CLAUDE and AI-SYSTEM-CARD templates produce — a Confidential project bypassing
# its own DPIA gate, an agentic project skipping its agent-ops gate, an AI System Card under docs/sign-offs/
# (the location the template recommends) reported as missing. Silent-skip (N/A) is worse than a loud FAIL:
# the gate looks satisfied. This check stamps a fixture project using the templates' OWN declaration format
# and asserts every detector FIRES (does not silent-skip). It goes red if a detector's regex/path drifts
# from the template it ships. It is TWO-POLARITY: it also asserts each detector DECLINES (N/A) on the
# template's own not-applicable value (Agentic: no, Data classification: Public/Internal), with fixtures
# GENERATED from the shipped template line (guidance tail included), not hand-typed — the gap that let
# a filled `no`/`Public` read the guidance prose as the value (SWAS-213).
#
#   sh conformance/template-detectors-aligned.sh [--selftest]
# Exit: 0 = every detector fires on the template's own format and declines on its N/A value · 1 = a detector silent-skips or misfires · 2 = setup.
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

# assert_na <label> <detector-output> : FAIL unless the detector DECLINED (printed an N/A line).
assert_na() {
  _label="$1"; _out="$2"
  if printf '%s\n' "$_out" | grep -Eq '(^|[^A-Za-z])N/A'; then
    note "PASS: $_label declines (N/A)"
    return 0
  fi
  note "FAIL: $_label did not decline on the template's own not-applicable value — output: $_out"
  return 1
}

# assert_fail <label> <detector-output> <sentence> : FAIL unless the detector FAILed carrying <sentence>.
assert_fail() {
  _label="$1"; _out="$2"; _sent="$3"
  if printf '%s\n' "$_out" | grep -q 'FAIL' && printf '%s\n' "$_out" | grep -qF -e "$_sent"; then
    note "PASS: $_label FAILs naming '$_sent'"
    return 0
  fi
  note "FAIL: $_label did not FAIL naming '$_sent' — output: $_out"
  return 1
}

# decl_fixture <dir> <agentic|privacy> <value|empty>: CLAUDE.md = the shipped template's OWN line for
# the field, the choice-list placeholder replaced by <value> (empty = the template line untouched, the
# fresh-tree state). RUNBOOK carries no Agent-ops record and there is no PRIVACY-REVIEW.md.
decl_fixture() {
  mkdir -p "$1"
  if [ "$2" = agentic ]; then
    _l=$(grep -Ei -e '^[-*[:space:]]*agentic[^:]*:' "$TPL" | head -1); _ph='\[yes / no\]'
  else
    _l=$(grep -Ei -e 'data classification[^:]*:' "$TPL" | head -1); _ph='\[Public / Internal / Confidential / Restricted\]'
  fi
  if [ -n "$3" ]; then
    _l=$(printf '%s\n' "$_l" | sed "s|$_ph|$3|")
    if printf '%s\n' "$_l" | grep -Fq -e "[yes / no]" -e "/ Restricted]"; then
      note "FAIL: fixture setup — placeholder survived substitution"
      return 1
    fi
  fi
  printf '# Project CLAUDE\n\n%s\n' "$_l" > "$1/CLAUDE.md"
  printf '# RUNBOOK\n\n## 8. Monitoring & alerting\n- Error tracking: Sentry\n' > "$1/RUNBOOK.md"
}

# tda_case <label> <check> <agentic|privacy> <value|empty> <na|fail> [sentence]
tda_case() {
  _cd=$(mktemp -d "${TMPDIR:-/tmp}/tda.XXXXXX")
  [ -n "$_cd" ] || { note "FAIL: $1 — mktemp -d returned no directory"; return 1; }
  decl_fixture "$_cd" "$3" "$4" || { rm -rf "$_cd"; return 1; }
  _co=$(sh "$CONF/readiness.sh" "$2" "$_cd" 2>&1 || true)
  rm -rf "$_cd"
  if [ "$5" = na ]; then assert_na "$1" "$_co"; else assert_fail "$1" "$_co" "$6"; fi
}

# polarity_cells: A1-A3 (agentops-ready) and P1-P3 (privacy-ready), template-generated, both polarities.
polarity_cells() {
  _pr=0
  tda_case "A1 agentops-ready (fresh tree: template untouched)" agentops-ready agentic "" na || _pr=1
  tda_case "A2 agentops-ready (Agentic: no, full template line)" agentops-ready agentic "no" na || _pr=1
  tda_case "A3 agentops-ready (Agentic: yes, no Agent-ops record)" agentops-ready agentic "yes" fail "Agent-ops:" || _pr=1
  tda_case "P1 privacy-ready (fresh tree: template untouched)" privacy-ready privacy "" na || _pr=1
  tda_case "P2 privacy-ready (Public, full template line)" privacy-ready privacy "Public" na || _pr=1
  tda_case "P2b privacy-ready (Internal, full template line)" privacy-ready privacy "Internal" na || _pr=1
  tda_case "P3 privacy-ready (Restricted [phi/hipaa], no PRIVACY-REVIEW)" privacy-ready privacy "Restricted [phi/hipaa]" fail "PRIVACY-REVIEW" || _pr=1
  return $_pr
}

# pick_utf8_locale: read a `locale -a` listing on stdin, print the first C / en_US UTF-8 locale NAME as
# listed. Case-insensitive with the dash optional: macOS lists C.UTF-8 / en_US.UTF-8, glibc lists
# C.utf8 / en_US.utf8.
pick_utf8_locale() {
  grep -i -x -e 'c\.utf-\{0,1\}8' -e 'en_us\.utf-\{0,1\}8' | head -1
}

# utf8_matcher_leg: the matcher accepts the macOS and glibc spellings and rejects plain C.
utf8_matcher_leg() {
  _mr=0
  for _ml in C.utf8 C.UTF-8 en_US.utf8; do
    _mg=$(printf 'C\nPOSIX\n%s\n' "$_ml" | pick_utf8_locale)
    if [ "$_mg" = "$_ml" ]; then
      note "PASS: utf8 locale matcher accepts $_ml"
    else
      note "FAIL: utf8 locale matcher did not accept $_ml (got '$_mg')"; _mr=1
    fi
  done
  _mg=$(printf 'C\nPOSIX\n' | pick_utf8_locale)
  if [ -z "$_mg" ]; then
    note "PASS: utf8 locale matcher rejects plain C"
  else
    note "FAIL: utf8 locale matcher accepted a non-UTF-8 list (got '$_mg')"; _mr=1
  fi
  return $_mr
}

# locale_cells (L1): the em-dash cut matches a 3-byte sequence, so the same cells must give the same
# verdicts under LC_ALL=C and under a UTF-8 locale.
locale_cells() {
  _lr=0
  _utf=$(locale -a 2>/dev/null | pick_utf8_locale)
  [ -n "$_utf" ] || { note "FAIL: L1 no UTF-8 locale (C.UTF-8 / en_US.UTF-8) available to run the locale cell"; return 1; }
  for _loc in C "$_utf"; do
    note "L1 locale LC_ALL=$_loc"
    ( LC_ALL="$_loc"; export LC_ALL; polarity_cells ) || _lr=1
  done
  return $_lr
}

run() {
  fail=0
  check_template_markers || fail=1

  d=$(mktemp -d)
  stamp_fixture "$d"

  out=$(sh "$CONF/readiness.sh" privacy-ready "$d" 2>&1 || true)
  assert_not_na "privacy-ready (Confidential)" "$out" || fail=1

  out=$(sh "$CONF/readiness.sh" agentops-ready "$d" 2>&1 || true)
  assert_not_na "agentops-ready (Agentic: yes)" "$out" || fail=1

  out=$(sh "$CONF/readiness.sh" responsible-ai-ready "$d" 2>&1 || true)
  assert_not_na "responsible-ai-ready (AI System Card @ docs/sign-offs/)" "$out" || fail=1

  out=$(sh "$CONF/readiness.sh" eval-ready "$d" 2>&1 || true)
  assert_not_na "eval-ready (EVAL-PLAN @ docs/sign-offs/)" "$out" || fail=1

  polarity_cells || fail=1
  utf8_matcher_leg || fail=1
  locale_cells || fail=1

  if [ "$fail" -eq 0 ]; then
    note "OK: every conformance detector fires on the kit's own template format and declines on its N/A value (no silent skips)"
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
