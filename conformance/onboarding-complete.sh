#!/bin/sh
# onboarding-complete.sh — completeness drift-guard for the onboarding on-ramp.
# Asserts the on-ramp EXISTS and is WIRED: (a) START-HERE.md carries the experience-lane SECTION
# (FRONT-DOOR-ONE-ROUTER folded ONBOARDING.md in) + names the 3 fluency lanes INSIDE that file —
# the `^## ` heading anchor is load-bearing: a bare lane-word grep over a 190-line living doc would
# drift green on incidental prose; (b) the PROJECT-CLAUDE template carries an `Operator fluency` field; (c) the
# operator-fluency adaptation doc exists and AGENTS.md points at it; (d) the TDD walkthrough
# exists. Completeness, NOT content quality — green means the on-ramp is structurally whole and
# wired, NOT that anyone learned anything (the guard + gates are the enforced safety net).
#   sh conformance/onboarding-complete.sh [--selftest]
# Exit: 0 = complete · 1 = a gap · 2 = bad usage. POSIX sh; dash-clean.
set -eu

LANES="Novice Adjacent Practitioner"
LANE_HEADING="## New to enterprise SDLC?"

# check_tree <root>: print PASS/FAIL per requirement; return 1 if any gap.
check_tree() {
  root=$1; f=0
  onramp="$root/START-HERE.md"
  tmpl="$root/templates/PROJECT-CLAUDE-TEMPLATE.md"
  fluency="$root/docs/operations/operator-fluency.md"
  brief="$root/AGENTS.md"
  tdd="$root/docs/onboarding/first-feature-tdd.md"
  if [ -f "$onramp" ] && grep -q "^$LANE_HEADING" "$onramp"; then
    echo "PASS: START-HERE.md carries the '$LANE_HEADING' experience-lane section"
    # Lane words are asserted INSIDE the section body (heading to next '## '), not file-wide —
    # a stray "Practitioner" elsewhere in a living 200-line doc must never satisfy this (PR 8 seat L-2).
    _sect=$(awk -v h="$LANE_HEADING" 'index($0,h)==1{f=1;next} /^## /{f=0} f' "$onramp")
    for lane in $LANES; do
      if printf '%s\n' "$_sect" | grep -q "$lane"; then echo "PASS: START-HERE.md lane section names $lane"; else echo "FAIL: START-HERE.md lane section omits $lane"; f=1; fi
    done
  else echo "FAIL: $onramp missing or lacks the '$LANE_HEADING' experience-lane section"; f=1; fi
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
  printf 'Operator fluency: x\n' > "$ok/templates/PROJECT-CLAUDE-TEMPLATE.md"
  printf '# fluency\n' > "$ok/docs/operations/operator-fluency.md"
  printf 'see docs/operations/operator-fluency.md\n' > "$ok/AGENTS.md"
  printf '# tdd\n' > "$ok/docs/onboarding/first-feature-tdd.md"
  printf '# START\nYou do not need to read all of this\npull-not-push map\n\n%s\n\nNovice\nAdjacent\nPractitioner\n' "$LANE_HEADING" > "$ok/START-HERE.md"
  if check_tree "$ok" >/dev/null 2>&1; then
    echo "PASS: selftest — complete on-ramp passes"
  else
    echo "FAIL: selftest — complete on-ramp wrongly rejected"; sfail=1
  fi
  # missing-section (load-bearing RED): the 3 lane words present as bare prose but NO `## ` heading
  # must STILL fail — the anchor, not the words, is what proves the fold landed as a real section.
  ms=$(mktemp -d); cp -R "$ok/." "$ms/"
  printf '# START\nYou do not need to read all of this\npull-not-push map\nNovice Adjacent Practitioner\n' > "$ms/START-HERE.md"
  if check_tree "$ms" >/dev/null 2>&1; then echo "FAIL: selftest — missing lane section not detected"; sfail=1; else echo "PASS: selftest — missing lane section detected"; fi
  [ "$sfail" -eq 0 ] && { echo "OK: onboarding-complete selftest (fixtures left in $g, $ok, $ms)"; exit 0; } || { echo "FAIL: onboarding-complete selftest"; exit 1; }
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
