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
# CLAUDE.md 120 -> 135 and the total 945 -> 960: OWNER-RATIFIED for the §1 entry contract (A1). The
# alternative on offer was to pay a CONTENT ratchet in FORMATTING characters — the entry contract had
# been fitted under 120 by deleting all 7 of CLAUDE.md's `---` thematic breaks, taking it to 0 against
# 17 in DEVELOPMENT-PROCESS.md and 16 in DEVELOPMENT-STANDARDS.md. That defeats the signal this ratchet
# exists to send (see the header above: it prevents drift, it "does not forbid growth"), so the breaks
# are restored and the budget is raised deliberately instead.
# ⚠️ GOVERNED BUMP REQUESTED AT C9 (CITATION-LIVE, 2026-08-15): DEVELOPMENT-STANDARDS.md 345 -> 350 and
# the total 960 -> 965, both +5, to seat the ratified §11 "Citation discipline" subsection (design
# §6.6 — the doctrine lands WITH its gate). Measured after the edit: 349/350 and 963/965, so the
# ratchet keeps its 1-2 line bite. This is a CONSTANT edit in a reviewed PR — the mechanism this
# header prescribes — and it is called out in the build record so the ratifier judges it explicitly
# rather than discovering it in a diff.
BUDGETS="CLAUDE.md:135 DEVELOPMENT-PROCESS.md:480 DEVELOPMENT-STANDARDS.md:350"
TOTAL_BUDGET=965

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
  # Live-entry legs (ten-lens eval, 2026-09-01): the composite mutant proved check_one is observed, but
  # run_budgets' own two f=1 sites — the per-doc propagation and the core-3 TOTAL — were UNOBSERVED by
  # a selftest that only ever called the leaf. Both are driven here on fixture globals, in a subshell.
  printf 'a\nb\n' > "$d/two.md"   # 2 lines
  if ( BUDGETS="$d/doc.md:5 $d/two.md:5"; TOTAL_BUDGET=4; run_budgets >/dev/null 2>&1 ); then echo "FAIL: selftest — core-3 total over budget not detected"; sfail=1; else echo "PASS: selftest — core-3 total over budget detected"; fi
  if ( BUDGETS="$d/doc.md:2 $d/two.md:5"; TOTAL_BUDGET=99; run_budgets >/dev/null 2>&1 ); then echo "FAIL: selftest — per-doc over budget not propagated by run_budgets"; sfail=1; else echo "PASS: selftest — per-doc over budget propagated by run_budgets"; fi
  if ( BUDGETS="$d/doc.md:5 $d/two.md:5"; TOTAL_BUDGET=99; run_budgets >/dev/null 2>&1 ); then echo "PASS: selftest — run_budgets within budget passes"; else echo "FAIL: selftest — run_budgets wrongly rejected a within-budget set"; sfail=1; fi
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
