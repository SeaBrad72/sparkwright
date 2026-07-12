#!/bin/sh
# onboarding-complete.sh — completeness drift-guard for the onboarding on-ramp.
# Asserts the on-ramp EXISTS and is WIRED: (a) ONBOARDING.md present + names the 3 fluency
# lanes; (b) the PROJECT-CLAUDE template carries an `Operator fluency` field; (c) the
# operator-fluency adaptation doc exists and AGENTS.md points at it; (d) the TDD walkthrough
# exists. Completeness, NOT content quality — green means the on-ramp is structurally whole and
# wired, NOT that anyone learned anything (the guard + gates are the enforced safety net).
#   sh conformance/onboarding-complete.sh [--selftest]
# Exit: 0 = complete · 1 = a gap · 2 = bad usage. POSIX sh; dash-clean.
set -eu

LANES="Novice Adjacent Practitioner"

# check_tree <root>: print PASS/FAIL per requirement; return 1 if any gap.
check_tree() {
  root=$1; f=0
  onramp="$root/ONBOARDING.md"
  tmpl="$root/templates/PROJECT-CLAUDE-TEMPLATE.md"
  fluency="$root/docs/operations/operator-fluency.md"
  brief="$root/AGENTS.md"
  tdd="$root/docs/onboarding/first-feature-tdd.md"
  if [ -f "$onramp" ]; then
    for lane in $LANES; do
      if grep -q "$lane" "$onramp"; then echo "PASS: ONBOARDING.md names lane $lane"; else echo "FAIL: ONBOARDING.md omits lane $lane"; f=1; fi
    done
  else echo "FAIL: missing $onramp"; f=1; fi
  if [ -f "$tmpl" ] && grep -q "Operator fluency" "$tmpl"; then echo "PASS: PROJECT-CLAUDE template carries Operator fluency"; else echo "FAIL: PROJECT-CLAUDE template lacks 'Operator fluency'"; f=1; fi
  if [ -f "$fluency" ]; then echo "PASS: operator-fluency.md exists"; else echo "FAIL: missing $fluency"; f=1; fi
  if [ -f "$brief" ] && grep -q "operator-fluency" "$brief"; then echo "PASS: AGENTS.md points at operator-fluency"; else echo "FAIL: AGENTS.md omits operator-fluency pointer"; f=1; fi
  if [ -f "$tdd" ]; then echo "PASS: first-feature-tdd.md exists"; else echo "FAIL: missing $tdd"; f=1; fi
  start="$root/START-HERE.md"
  if [ -f "$start" ] && grep -q "You do not need to read all of this" "$start" && grep -qi "pull-not-push" "$start"; then
    echo "PASS: START-HERE.md carries the progressive-disclosure front door (first-5 + pull-not-push)"
  else echo "FAIL: START-HERE.md missing the progressive-disclosure front door"; f=1; fi
  return $f
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  # gap tree: empty -> must be detected
  g=$(mktemp -d); mkdir -p "$g/templates" "$g/docs/operations" "$g/docs/onboarding"
  if check_tree "$g" >/dev/null 2>&1; then
    echo "FAIL: selftest — gap not detected"; sfail=1
  else
    echo "PASS: selftest — missing on-ramp artifacts detected"
  fi
  # complete tree: all present -> must pass
  ok=$(mktemp -d); mkdir -p "$ok/templates" "$ok/docs/operations" "$ok/docs/onboarding"
  printf '# Onboarding\nNovice\nAdjacent\nPractitioner\n' > "$ok/ONBOARDING.md"
  printf 'Operator fluency: x\n' > "$ok/templates/PROJECT-CLAUDE-TEMPLATE.md"
  printf '# fluency\n' > "$ok/docs/operations/operator-fluency.md"
  printf 'see docs/operations/operator-fluency.md\n' > "$ok/AGENTS.md"
  printf '# tdd\n' > "$ok/docs/onboarding/first-feature-tdd.md"
  printf '# START\nYou do not need to read all of this\npull-not-push map\n' > "$ok/START-HERE.md"
  if check_tree "$ok" >/dev/null 2>&1; then
    echo "PASS: selftest — complete on-ramp passes"
  else
    echo "FAIL: selftest — complete on-ramp wrongly rejected"; sfail=1
  fi
  [ "$sfail" -eq 0 ] && { echo "OK: onboarding-complete selftest (fixtures left in $g, $ok)"; exit 0; } || { echo "FAIL: onboarding-complete selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: onboarding-complete.sh [--selftest]" >&2; exit 2 ;;
esac

echo "Onboarding on-ramp completeness:"
if check_tree "."; then
  echo "OK: on-ramp present + wired (3 lanes, fluency field, adaptation doc + AGENTS pointer, TDD walkthrough)"
  exit 0
else
  echo "FAIL: on-ramp incomplete (see above)"
  exit 1
fi
