#!/bin/sh
# agents-brief.sh — keep AGENTS.md a real load-first brief, not a fourth standards doc (Slice 9k).
# Asserts: (a) AGENTS.md exists; (b) it points at each canonical doc; (c) it stays within the line bound.
#   sh conformance/agents-brief.sh [--selftest]
# Exit: 0 = ok · 1 = a gap · 2 = bad usage. POSIX sh; dash-clean.
set -eu

BRIEF="AGENTS.md"
MAX_LINES=80
REFS="CLAUDE.md DEVELOPMENT-PROCESS.md DEVELOPMENT-STANDARDS.md"

# check_brief <brief> <max-lines>: print PASS/FAIL; return 1 on any gap.
check_brief() {
  bf=$1; max=$2; f=0
  if [ ! -f "$bf" ]; then echo "FAIL: missing $bf"; return 1; fi
  n=$(awk 'END{print NR}' "$bf")
  if [ "$n" -le "$max" ]; then
    echo "PASS: $bf is $n lines (<= $max)"
  else
    echo "FAIL: $bf is $n lines (> $max — keep it a brief)"; f=1
  fi
  for r in $REFS; do
    if grep -q "$r" "$bf"; then echo "PASS: $bf points at $r"; else echo "FAIL: $bf does not reference $r"; f=1; fi
  done
  return $f
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  # gap A — over-bound ONLY (all refs present, but exceeds the tiny bound)
  ga=$(mktemp -d)
  printf 'CLAUDE.md\nDEVELOPMENT-PROCESS.md\nDEVELOPMENT-STANDARDS.md\n' > "$ga/AGENTS.md"
  if check_brief "$ga/AGENTS.md" 2 >/dev/null 2>&1; then
    echo "FAIL: selftest — over-bound not detected"; sfail=1
  else
    echo "PASS: selftest — over-bound detected"
  fi
  # gap B — missing-ref ONLY (within bound, but lacks a canonical-doc ref)
  gb=$(mktemp -d)
  printf 'CLAUDE.md\nDEVELOPMENT-PROCESS.md\n' > "$gb/AGENTS.md"
  if check_brief "$gb/AGENTS.md" 80 >/dev/null 2>&1; then
    echo "FAIL: selftest — missing ref not detected"; sfail=1
  else
    echo "PASS: selftest — missing ref detected"
  fi
  # complete tree: refs present, within bound
  ok=$(mktemp -d)
  printf '# brief\nsee CLAUDE.md\nsee DEVELOPMENT-PROCESS.md\nsee DEVELOPMENT-STANDARDS.md\n' > "$ok/AGENTS.md"
  if check_brief "$ok/AGENTS.md" 80 >/dev/null 2>&1; then
    echo "PASS: selftest — complete brief passes"
  else
    echo "FAIL: selftest — complete brief wrongly rejected"; sfail=1
  fi
  [ "$sfail" -eq 0 ] && { echo "OK: agents-brief selftest"; exit 0; } || { echo "FAIL: agents-brief selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: agents-brief.sh [--selftest]" >&2; exit 2 ;;
esac

echo "AGENTS.md brief check:"
if check_brief "$BRIEF" "$MAX_LINES"; then
  echo "OK: AGENTS.md exists, points at the canonical docs, and is within the line bound"
  exit 0
else
  echo "FAIL: AGENTS.md brief incomplete (see above)"
  exit 1
fi
