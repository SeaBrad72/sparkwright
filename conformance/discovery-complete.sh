#!/bin/sh
# discovery-complete.sh — completeness drift-guard for the OPT-IN discovery layer (FRAME + SHAPE).
# Asserts the layer is present + wired: (a) discovery-loop.md names all six loop stages; (b) it carries
# the FRAME + SHAPE stage-guide SECTIONS (folded in — T3c consolidation; previously separate
# frame.md/shape.md files); (c) the two upstream templates exist; (d) START-HERE.md links the discovery
# door by its FULL path (FRONT-DOOR-ONE-ROUTER folded ONBOARDING.md in; the full path, never the bare
# `docs/discovery` directory, so an unrelated mention cannot satisfy the door). Completeness only — green means present + wired, NOT that any actual discovery was good
# (discovery is judgment work; the guard + gates remain the safety net).
#   sh conformance/discovery-complete.sh [--selftest]
# Exit: 0 = complete · 1 = a gap · 2 = bad usage. POSIX sh; dash-clean.
set -eu

STAGES="FRAME SHAPE PLAN BUILD SHIP OBSERVE"

# check_tree <root>: print PASS/FAIL per requirement; return 1 if any gap.
check_tree() {
  root=$1; f=0
  loop="$root/docs/discovery/discovery-loop.md"
  brief="$root/templates/OPPORTUNITY-BRIEF-TEMPLATE.md"
  shaping="$root/templates/SHAPING-DOC-TEMPLATE.md"
  onb="$root/START-HERE.md"
  if [ -f "$loop" ]; then
    for s in $STAGES; do
      # require the stage as a bolded token (**STAGE**) — a real loop entry, not an incidental
      # substring (so PLAN can't be satisfied by "PLANNING", SHIP by "SHIPPED", etc.)
      if grep -q "\*\*$s\*\*" "$loop"; then echo "PASS: discovery-loop names $s"; else echo "FAIL: discovery-loop omits $s"; f=1; fi
    done
    # FRAME + SHAPE are now SECTIONS of discovery-loop.md (folded in — T3c), not separate files.
    # Assert each section HEADING is present. `^## FRAME` is a heading, distinct from the `**FRAME**`
    # overview-table token checked above — so the overview alone can NOT satisfy this vacuously (the
    # per-stage guide content must actually be present).
    if grep -q '^## FRAME' "$loop"; then echo "PASS: discovery-loop has the FRAME stage-guide section"; else echo "FAIL: discovery-loop missing the FRAME stage-guide section"; f=1; fi
    if grep -q '^## SHAPE' "$loop"; then echo "PASS: discovery-loop has the SHAPE stage-guide section"; else echo "FAIL: discovery-loop missing the SHAPE stage-guide section"; f=1; fi
  else echo "FAIL: missing $loop"; f=1; fi
  if [ -f "$brief" ]; then echo "PASS: OPPORTUNITY-BRIEF template exists"; else echo "FAIL: missing $brief"; f=1; fi
  if [ -f "$shaping" ]; then echo "PASS: SHAPING-DOC template exists"; else echo "FAIL: missing $shaping"; f=1; fi
  if [ -f "$onb" ] && grep -qF 'docs/discovery/discovery-loop.md' "$onb"; then echo "PASS: START-HERE links the discovery door"; else echo "FAIL: START-HERE omits the discovery door (full docs/discovery/discovery-loop.md path)"; f=1; fi
  return $f
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  # gap: an empty tree must fail
  g=$(mktemp -d); mkdir -p "$g/docs/discovery" "$g/templates"
  if check_tree "$g" >/dev/null 2>&1; then echo "FAIL: selftest — gap not detected"; sfail=1; else echo "PASS: selftest — missing discovery artifacts detected"; fi
  # missing-sections (load-bearing RED): a loop that names the six stages as **tokens** and has the
  # templates + the START-HERE door but LACKS the ## FRAME / ## SHAPE sections must STILL fail — proves the
  # section check is not satisfied by the overview table alone (the green-while-dark guard).
  ms=$(mktemp -d); mkdir -p "$ms/docs/discovery" "$ms/templates"
  printf '# loop\n**FRAME** **SHAPE** **PLAN** **BUILD** **SHIP** **OBSERVE**\n' > "$ms/docs/discovery/discovery-loop.md"
  printf '# brief\n' > "$ms/templates/OPPORTUNITY-BRIEF-TEMPLATE.md"
  printf '# shaping\n' > "$ms/templates/SHAPING-DOC-TEMPLATE.md"
  printf 'see docs/discovery/discovery-loop.md\n' > "$ms/START-HERE.md"
  if check_tree "$ms" >/dev/null 2>&1; then echo "FAIL: selftest — missing FRAME/SHAPE sections not detected"; sfail=1; else echo "PASS: selftest — missing FRAME/SHAPE sections detected"; fi
  # ok: stages named AND the two sections present (+ templates + the START-HERE door)
  ok=$(mktemp -d); mkdir -p "$ok/docs/discovery" "$ok/templates"
  printf '# loop\n**FRAME** **SHAPE** **PLAN** **BUILD** **SHIP** **OBSERVE**\n\n## FRAME — x\nguide\n\n## SHAPE — y\nguide\n' > "$ok/docs/discovery/discovery-loop.md"
  printf '# brief\n' > "$ok/templates/OPPORTUNITY-BRIEF-TEMPLATE.md"
  printf '# shaping\n' > "$ok/templates/SHAPING-DOC-TEMPLATE.md"
  printf 'see docs/discovery/discovery-loop.md\n' > "$ok/START-HERE.md"
  # door RED leg: the same complete tree whose door names only the DIRECTORY must still fail — proves
  # the assert anchors on the full path, not on an incidental `docs/discovery` mention.
  bd=$(mktemp -d); cp -R "$ok/." "$bd/"
  printf 'see docs/discovery/ for the optional upstream layer\n' > "$bd/START-HERE.md"
  if check_tree "$bd" >/dev/null 2>&1; then echo "FAIL: selftest — directory-only door not detected"; sfail=1; else echo "PASS: selftest — directory-only door detected"; fi
  if check_tree "$ok" >/dev/null 2>&1; then echo "PASS: selftest — complete layer passes"; else echo "FAIL: selftest — complete layer wrongly rejected"; sfail=1; fi
  [ "$sfail" -eq 0 ] && { echo "OK: discovery-complete selftest (fixtures left in $g, $ms, $ok, $bd)"; exit 0; } || { echo "FAIL: discovery-complete selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: discovery-complete.sh [--selftest]" >&2; exit 2 ;;
esac

echo "Discovery layer completeness:"
if check_tree "."; then
  echo "OK: discovery layer present + wired (loop overview + FRAME/SHAPE sections + 2 templates + START-HERE door)"
  exit 0
else
  echo "FAIL: discovery layer incomplete (see above)"
  exit 1
fi
