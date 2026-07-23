#!/bin/sh
# conditional-gates.sh — assert the CONDITIONAL gates are named WITH their trigger in the process doc.
# The honest-demote: these are first-class but conditional (trigger-bound), not universal. They live in
# TWO homes: the §7 gate table (a11y/eval/resilience/SAST/license) AND the §13 platform-conditional
# control-plane-ratification gate (GitHub check-runs — GitLab has no check-runs / pull_request_review,
# so §13 is N/A-with-reason there; conformance/proportional-gate-wired.sh cites this declaration).
# `check_doc` greps the WHOLE document, so a marker in either section matches; a future accidental row
# removal (e.g. reverting a row) fails the guard — not just a bare-word match some prose could satisfy.
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
SAST** *(first-party code)*
License compliance** *(when an SBOM is produced)*
Control-plane ratification** *(GitHub check-runs)*
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
  # §13 gap tree: all five §7 rows present but the §13 platform-conditional declaration MISSING ->
  # a reverted §13 declaration must be caught, exactly as a reverted §7 row is (gap tree above).
  g13=$(mktemp -d)
  printf '# proc\n| **Accessibility** *(user-facing UI)* | x |\n| **Eval gate** *(AI features)* | x |\n| **Resilience readiness** *(deployable services)* | x |\n| **SAST** *(first-party code)* | x |\n| **License compliance** *(when an SBOM is produced)* | x |\n' > "$g13/proc.md"
  if check_doc "$g13/proc.md" >/dev/null 2>&1; then
    echo "FAIL: selftest — missing §13 platform-conditional declaration not detected"; sfail=1
  else
    echo "PASS: selftest — missing §13 platform-conditional declaration detected"
  fi
  ok=$(mktemp -d)
  printf '# proc\n| **Accessibility** *(user-facing UI)* | x |\n| **Eval gate** *(AI features)* | x |\n| **Resilience readiness** *(deployable services)* | x |\n| **SAST** *(first-party code)* | x |\n| **License compliance** *(when an SBOM is produced)* | x |\n**Control-plane ratification** *(GitHub check-runs)*\n' > "$ok/proc.md"
  if check_doc "$ok/proc.md" >/dev/null 2>&1; then
    echo "PASS: selftest — complete set passes"
  else
    echo "FAIL: selftest — complete set wrongly rejected"; sfail=1
  fi
  [ "$sfail" -eq 0 ] && { echo "OK: conditional-gates selftest"; exit 0; } || { echo "FAIL: conditional-gates selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: conditional-gates.sh [--selftest]" >&2; exit 2 ;;
esac

echo "Conditional-gate rows (name + trigger — §7 gate table + §13 platform-conditional):"
if check_doc "$GATE_DOC"; then
  echo "OK: conditional gates named with their trigger (§7 a11y/eval/resilience/SAST/license + §13 control-plane ratification)"
  exit 0
else
  echo "FAIL: a conditional-gate row is missing from the process doc (see above)"
  exit 1
fi
