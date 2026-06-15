#!/bin/sh
# discovery-complete.sh — completeness drift-guard for the OPT-IN discovery layer (FRAME + SHAPE).
# Asserts the layer is present + wired: (a) discovery-loop.md names all six loop stages; (b) the
# frame.md + shape.md stage guides exist; (c) the two upstream templates exist; (d) ONBOARDING.md
# links the discovery door. Completeness only — green means present + wired, NOT that any actual
# discovery was good (discovery is judgment work; the guard + gates remain the safety net).
#   sh conformance/discovery-complete.sh [--selftest]
# Exit: 0 = complete · 1 = a gap · 2 = bad usage. POSIX sh; dash-clean.
set -eu

STAGES="FRAME SHAPE PLAN BUILD SHIP OBSERVE"

# check_tree <root>: print PASS/FAIL per requirement; return 1 if any gap.
check_tree() {
  root=$1; f=0
  loop="$root/docs/discovery/discovery-loop.md"
  frame="$root/docs/discovery/frame.md"
  shape="$root/docs/discovery/shape.md"
  brief="$root/templates/OPPORTUNITY-BRIEF-TEMPLATE.md"
  shaping="$root/templates/SHAPING-DOC-TEMPLATE.md"
  onb="$root/ONBOARDING.md"
  if [ -f "$loop" ]; then
    for s in $STAGES; do
      # require the stage as a bolded token (**STAGE**) — a real loop entry, not an incidental
      # substring (so PLAN can't be satisfied by "PLANNING", SHIP by "SHIPPED", etc.)
      if grep -q "\*\*$s\*\*" "$loop"; then echo "PASS: discovery-loop names $s"; else echo "FAIL: discovery-loop omits $s"; f=1; fi
    done
  else echo "FAIL: missing $loop"; f=1; fi
  if [ -f "$frame" ]; then echo "PASS: frame.md exists"; else echo "FAIL: missing $frame"; f=1; fi
  if [ -f "$shape" ]; then echo "PASS: shape.md exists"; else echo "FAIL: missing $shape"; f=1; fi
  if [ -f "$brief" ]; then echo "PASS: OPPORTUNITY-BRIEF template exists"; else echo "FAIL: missing $brief"; f=1; fi
  if [ -f "$shaping" ]; then echo "PASS: SHAPING-DOC template exists"; else echo "FAIL: missing $shaping"; f=1; fi
  if [ -f "$onb" ] && grep -q "docs/discovery" "$onb"; then echo "PASS: ONBOARDING links the discovery door"; else echo "FAIL: ONBOARDING omits the discovery door"; f=1; fi
  return $f
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  g=$(mktemp -d); mkdir -p "$g/docs/discovery" "$g/templates"
  if check_tree "$g" >/dev/null 2>&1; then echo "FAIL: selftest — gap not detected"; sfail=1; else echo "PASS: selftest — missing discovery artifacts detected"; fi
  ok=$(mktemp -d); mkdir -p "$ok/docs/discovery" "$ok/templates"
  printf '# loop\n**FRAME** **SHAPE** **PLAN** **BUILD** **SHIP** **OBSERVE**\n' > "$ok/docs/discovery/discovery-loop.md"
  printf '# frame\n' > "$ok/docs/discovery/frame.md"
  printf '# shape\n' > "$ok/docs/discovery/shape.md"
  printf '# brief\n' > "$ok/templates/OPPORTUNITY-BRIEF-TEMPLATE.md"
  printf '# shaping\n' > "$ok/templates/SHAPING-DOC-TEMPLATE.md"
  printf 'see docs/discovery/discovery-loop.md\n' > "$ok/ONBOARDING.md"
  if check_tree "$ok" >/dev/null 2>&1; then echo "PASS: selftest — complete layer passes"; else echo "FAIL: selftest — complete layer wrongly rejected"; sfail=1; fi
  [ "$sfail" -eq 0 ] && { echo "OK: discovery-complete selftest (fixtures left in $g, $ok)"; exit 0; } || { echo "FAIL: discovery-complete selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: discovery-complete.sh [--selftest]" >&2; exit 2 ;;
esac

echo "Discovery layer completeness:"
if check_tree "."; then
  echo "OK: discovery layer present + wired (loop overview + FRAME/SHAPE guides + 2 templates + ONBOARDING door)"
  exit 0
else
  echo "FAIL: discovery layer incomplete (see above)"
  exit 1
fi
