#!/bin/sh
# conditional-gates.sh — assert the a11y/load/eval CONDITIONAL gates are named in §7 (Slice 9j).
# The honest-demote: these are first-class but conditional (trigger-bound), not universal.
# Asserts DEVELOPMENT-PROCESS.md §7 carries each gate's row WITH its trigger annotation, so a
# future accidental row removal (e.g. reverting the Accessibility row) fails the guard — not just
# a bare-word match that some unrelated prose could satisfy.
#   sh conformance/conditional-gates.sh [--selftest]
# Exit: 0 = ok · 1 = a gap · 2 = bad usage. POSIX sh; dash-clean.
set -eu

GATE_DOC="DEVELOPMENT-PROCESS.md"

# check_doc <doc>: print PASS/FAIL per gate row marker; return 1 on any gap.
# Markers are the §7 table cells (name + trigger), matched as FIXED strings (-F), so the
# literal '*' and '**' are not globs and a reverted row is genuinely caught.
check_doc() {
  d=$1; f=0
  if [ ! -f "$d" ]; then echo "FAIL: missing $d"; return 1; fi
  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    if grep -qF "$pat" "$d"; then echo "PASS: $d names — $pat"; else echo "FAIL: $d omits — $pat"; f=1; fi
  done <<'EOF'
Accessibility** *(user-facing UI)*
Eval gate** *(AI features)*
Resilience readiness** *(deployable services)*
EOF
  return $f
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  g=$(mktemp -d)
  # gap tree: Eval + Resilience markers present, Accessibility row MISSING -> must be detected
  printf '# proc\n| **Eval gate** *(AI features)* | x |\n| **Resilience readiness** *(deployable services)* | x |\n' > "$g/proc.md"
  if check_doc "$g/proc.md" >/dev/null 2>&1; then
    echo "FAIL: selftest — missing conditional-gate row not detected"; sfail=1
  else
    echo "PASS: selftest — missing conditional-gate row detected"
  fi
  ok=$(mktemp -d)
  printf '# proc\n| **Accessibility** *(user-facing UI)* | x |\n| **Eval gate** *(AI features)* | x |\n| **Resilience readiness** *(deployable services)* | x |\n' > "$ok/proc.md"
  if check_doc "$ok/proc.md" >/dev/null 2>&1; then
    echo "PASS: selftest — complete trio passes"
  else
    echo "FAIL: selftest — complete trio wrongly rejected"; sfail=1
  fi
  [ "$sfail" -eq 0 ] && { echo "OK: conditional-gates selftest"; exit 0; } || { echo "FAIL: conditional-gates selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: conditional-gates.sh [--selftest]" >&2; exit 2 ;;
esac

echo "Conditional-gate rows (§7, name + trigger):"
if check_doc "$GATE_DOC"; then
  echo "OK: a11y / load / eval are named as conditional gates in §7"
  exit 0
else
  echo "FAIL: a conditional-gate row is missing from §7 (see above)"
  exit 1
fi
