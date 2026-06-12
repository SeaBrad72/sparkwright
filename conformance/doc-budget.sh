#!/bin/sh
# doc-budget.sh — ratchet the core governing-doc size so they cannot silently re-bloat (Slice 9k-b).
# Asserts each core doc (and the core-3 total) is at/under a line budget set at the post-trim size
# (plus small headroom). Raising a budget is a DELIBERATE, ratified change — edit the constants below
# in a reviewed PR (the same governed-bump pattern as the coverage ratchet). This prevents drift; it
# does not forbid growth.
#   sh conformance/doc-budget.sh [--selftest]
# Exit: 0 = within budget · 1 = over budget · 2 = bad usage. POSIX sh; dash-clean.
set -eu

# Per-doc line budgets (post-9k-b sizes rounded up to the next 10). "<path>:<max-lines>".
BUDGETS="CLAUDE.md:120 DEVELOPMENT-PROCESS.md:470 DEVELOPMENT-STANDARDS.md:320"
TOTAL_BUDGET=900

# check_one <path> <max>: print PASS/FAIL; return 1 if over budget or missing.
check_one() {
  p=$1; max=$2
  if [ ! -f "$p" ]; then echo "FAIL: missing $p"; return 1; fi
  n=$(awk 'END{print NR}' "$p")
  if [ "$n" -le "$max" ]; then echo "PASS: $p $n/$max lines"; return 0; fi
  echo "FAIL: $p $n lines > budget $max (re-bloat — tighten, or raise the budget in a ratified PR)"; return 1
}

run_budgets() {
  f=0; total=0
  for entry in $BUDGETS; do
    p=${entry%:*}; max=${entry#*:}
    check_one "$p" "$max" || f=1
    n=$(awk 'END{print NR}' "$p" 2>/dev/null || echo 0); total=$((total + n))
  done
  if [ "$total" -le "$TOTAL_BUDGET" ]; then echo "PASS: core-3 total $total/$TOTAL_BUDGET lines"; else echo "FAIL: core-3 total $total > $TOTAL_BUDGET (re-bloat)"; f=1; fi
  return $f
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  d=$(mktemp -d); printf 'a\nb\nc\n' > "$d/doc.md"   # 3 lines
  if check_one "$d/doc.md" 2 >/dev/null 2>&1; then echo "FAIL: selftest — over-budget not detected"; sfail=1; else echo "PASS: selftest — over-budget detected"; fi
  if check_one "$d/doc.md" 5 >/dev/null 2>&1; then echo "PASS: selftest — within-budget passes"; else echo "FAIL: selftest — within-budget wrongly rejected"; sfail=1; fi
  [ "$sfail" -eq 0 ] && { echo "OK: doc-budget selftest"; exit 0; } || { echo "FAIL: doc-budget selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: doc-budget.sh [--selftest]" >&2; exit 2 ;;
esac

echo "Core-doc budget:"
if run_budgets; then
  echo "OK: core docs within budget"
  exit 0
else
  echo "FAIL: a core doc is over budget (see above)"
  exit 1
fi
