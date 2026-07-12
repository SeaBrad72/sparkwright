#!/bin/sh
# persona-artifacts.sh — completeness drift-guard for the SDLC-persona artifacts (Slice 9i / R9).
# Asserts: (a) the three per-gate templates exist; (b) DEVELOPMENT-PROCESS.md §2 names each.
# Completeness, NOT content-equality. A persona artifact must be both shipped and referenced
# in the persona table, or this fails.
#   sh conformance/persona-artifacts.sh [--selftest]
# Exit: 0 = complete · 1 = a gap · 2 = bad usage. POSIX sh; dash-clean.
set -eu

TEMPLATES_DIR="templates"
PERSONA_DOC="DEVELOPMENT-PROCESS.md"
ARTIFACTS="TEST-PLAN UAT-SIGNOFF A11Y-SIGNOFF"

# check_tree <templates-dir> <persona-doc>: print PASS/FAIL; return 1 if any gap.
check_tree() {
  tdir=$1; doc=$2; f=0
  if [ ! -f "$doc" ]; then echo "FAIL: missing $doc"; return 1; fi
  for a in $ARTIFACTS; do
    tfile="$tdir/${a}-TEMPLATE.md"
    if [ -f "$tfile" ]; then echo "PASS: template $tfile exists"; else echo "FAIL: missing template $tfile"; f=1; fi
    if grep -q "$a" "$doc"; then echo "PASS: persona table names $a"; else echo "FAIL: $doc omits $a"; f=1; fi
  done
  return $f
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  # gap tree: no template files + doc names only one artifact -> must be detected
  g=$(mktemp -d); mkdir -p "$g/templates"
  printf '# proc\n| QA | TEST-PLAN |\n' > "$g/proc.md"
  if check_tree "$g/templates" "$g/proc.md" >/dev/null 2>&1; then
    echo "FAIL: selftest — gap not detected"; sfail=1
  else
    echo "PASS: selftest — missing templates / table refs detected"
  fi
  # complete tree: all three templates + all three names -> must pass
  ok=$(mktemp -d); mkdir -p "$ok/templates"
  for a in $ARTIFACTS; do printf '# %s\n' "$a" > "$ok/templates/${a}-TEMPLATE.md"; done
  printf '# proc\n| QA | TEST-PLAN -> UAT-SIGNOFF |\n| Designer | A11Y-SIGNOFF |\n' > "$ok/proc.md"
  if check_tree "$ok/templates" "$ok/proc.md" >/dev/null 2>&1; then
    echo "PASS: selftest — complete set passes"
  else
    echo "FAIL: selftest — complete set wrongly rejected"; sfail=1
  fi
  [ "$sfail" -eq 0 ] && { echo "OK: persona-artifacts selftest"; exit 0; } || { echo "FAIL: persona-artifacts selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: persona-artifacts.sh [--selftest]" >&2; exit 2 ;;
esac

echo "Persona-artifact completeness:"
if check_tree "$TEMPLATES_DIR" "$PERSONA_DOC"; then
  echo "OK: persona artifacts present + named in the §2 table"
  exit 0
else
  echo "FAIL: persona artifacts incomplete (see above)"
  exit 1
fi
