#!/bin/sh
# dor-defined.sh — completeness drift-guard for the Definition of Ready (Slice 9i-b).
# Asserts the DoR is a first-class, wired entry gate:
#   (a) CLAUDE.md carries a Definition of "Ready" block;
#   (b) DEVELOPMENT-PROCESS.md (the gate doc) references the DoR;
#   (c) templates/FEATURE-REQUEST-TEMPLATE.md carries a Definition of Ready section.
# Completeness, NOT content-equality. The DoR must be enumerated, referenced by the gate
# doc, and carried by the intake template — or this fails.
#   sh conformance/dor-defined.sh [--selftest]
# Exit: 0 = wired · 1 = a gap · 2 = bad usage. POSIX sh; dash-clean.
set -eu

PRINCIPLES="CLAUDE.md"
GATE_DOC="DEVELOPMENT-PROCESS.md"
INTAKE="templates/FEATURE-REQUEST-TEMPLATE.md"

# check_tree <principles> <gate-doc> <intake>: print PASS/FAIL; return 1 on any gap.
check_tree() {
  pf=$1; gf=$2; itf=$3; f=0
  if [ -f "$pf" ] && grep -q 'Definition of "Ready"' "$pf"; then
    echo "PASS: $pf carries the Definition of \"Ready\" block"
  else
    echo "FAIL: $pf has no Definition of \"Ready\" block"; f=1
  fi
  if [ -f "$gf" ] && grep -q 'Definition of Ready' "$gf"; then
    echo "PASS: $gf references the DoR gate"
  else
    echo "FAIL: $gf does not reference the DoR"; f=1
  fi
  if [ -f "$itf" ] && grep -q 'Definition of Ready' "$itf"; then
    echo "PASS: $itf carries a Definition of Ready section"
  else
    echo "FAIL: $itf has no Definition of Ready section"; f=1
  fi
  return $f
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  # gap tree: none of the three markers present -> must be detected
  g=$(mktemp -d)
  printf '# principles\nno ready block here\n' > "$g/CLAUDE.md"
  printf '# proc\nno gate ref\n' > "$g/proc.md"
  printf '# intake\nno dor section\n' > "$g/intake.md"
  if check_tree "$g/CLAUDE.md" "$g/proc.md" "$g/intake.md" >/dev/null 2>&1; then
    echo "FAIL: selftest — gap not detected"; sfail=1
  else
    echo "PASS: selftest — missing DoR block / gate ref / intake section detected"
  fi
  # complete tree: all three markers present -> must pass
  ok=$(mktemp -d)
  printf '# principles\n## Definition of "Ready"\n- acceptance criteria\n' > "$ok/CLAUDE.md"
  printf '# proc\nDefinition of Ready gate\n' > "$ok/proc.md"
  printf '# intake\n## Definition of Ready\n- [ ] acceptance criteria\n' > "$ok/intake.md"
  if check_tree "$ok/CLAUDE.md" "$ok/proc.md" "$ok/intake.md" >/dev/null 2>&1; then
    echo "PASS: selftest — complete set passes"
  else
    echo "FAIL: selftest — complete set wrongly rejected"; sfail=1
  fi
  [ "$sfail" -eq 0 ] && { echo "OK: dor-defined selftest"; exit 0; } || { echo "FAIL: dor-defined selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: dor-defined.sh [--selftest]" >&2; exit 2 ;;
esac

echo "Definition-of-Ready wiring:"
if check_tree "$PRINCIPLES" "$GATE_DOC" "$INTAKE"; then
  echo "OK: DoR is enumerated in CLAUDE.md, referenced by the gate doc, and carried by the intake template"
  exit 0
else
  echo "FAIL: DoR wiring incomplete (see above)"
  exit 1
fi
