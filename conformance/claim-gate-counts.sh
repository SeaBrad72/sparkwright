#!/bin/sh
# claim-gate-counts.sh — semantic-drift check: the "N required" / "N conditional" gate COUNT words
# in the governing docs must equal the ENUMERATED gates. Catches "added/removed a gate but left the
# number word." Scoped with awk to DEVELOPMENT-STANDARDS.md §14 so unrelated tables/bullets cannot
# skew the count. The phrasings it keys on ("seven required gates", "Five further gates") are the
# stable headline wordings; a deliberate reword should update this check (that is the point — a
# reworded claim must be re-verified).
#   sh conformance/claim-gate-counts.sh [--selftest]
# Exit: 0 = claims match the enumeration · 1 = drift · 2 = usage. POSIX sh; dash-clean.
set -eu

STD="${KIT_STANDARDS:-DEVELOPMENT-STANDARDS.md}"
PRIN="${KIT_PRINCIPLES:-CLAUDE.md}"

# rows in the §14 required-gates table: | N | **Gate** | …
count_required() {
  awk '/^## 14\./{s=1;next} s&&/^## /{exit} s&&/^\| [0-9]+ \| \*\*/{n++} END{print n+0}' "$1"
}
# "- **…**" bullets in the conditional-gates subsection (between "Five further gates" and "deliberately")
count_conditional() {
  awk '/Five further gates/{s=1;next} s&&/deliberately/{exit} s&&/^- \*\*/{n++} END{print n+0}' "$1"
}

check() {
  _std=$1; _prin=$2; f=0
  [ -f "$_std" ]  || { echo "FAIL: missing $_std"; return 1; }
  [ -f "$_prin" ] || { echo "FAIL: missing $_prin"; return 1; }
  _rq=$(count_required "$_std"); _cd=$(count_conditional "$_std")
  if [ "$_rq" -eq 0 ]; then
    echo "FAIL: required gates — §14 table not found (the '## 14.' anchor or table shape changed; this is a CHECK-SCOPE problem, not a gate-count drift — update claim-gate-counts.sh)"; f=1
  elif [ "$_rq" -eq 7 ] && grep -q "seven required gates" "$_std" && grep -q "7 required gates" "$_prin"; then
    echo "PASS: required gates — 7 enumerated == 'seven'/'7' claimed"
  else
    echo "FAIL: required gates — enumerated=$_rq; expected 7 with matching 'seven' ($_std) + '7 required gates' ($_prin)"; f=1
  fi
  if [ "$_cd" -eq 0 ]; then
    echo "FAIL: conditional gates — 'Five further gates' subsection not found (anchor/phrase changed; CHECK-SCOPE problem, not a drift — update claim-gate-counts.sh)"; f=1
  elif [ "$_cd" -eq 5 ] && grep -q "Five further gates" "$_std"; then
    echo "PASS: conditional gates — 5 enumerated == 'Five' claimed"
  else
    echo "FAIL: conditional gates — enumerated=$_cd; expected 5 with matching 'Five further gates' ($_std)"; f=1
  fi
  return $f
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  d=$(mktemp -d)
  # a GOOD fixture: 7 required rows + "seven", 5 conditional bullets + "Five", principles "7 required gates"
  {
    echo "## 14. CI/CD"
    echo "must run seven required gates before merge."
    echo "| # | Gate | Req |"
    echo "|---|------|-----|"
    i=1; while [ "$i" -le 7 ]; do echo "| $i | **Gate$i** | x |"; i=$((i+1)); done
    echo ""
    echo "Five further gates are conditional —"
    echo "- **A** x"; echo "- **B** x"; echo "- **C** x"; echo "- **D** x"; echo "- **E** x"
    echo "deliberately not universal."
    echo "## 15. Next"
  } > "$d/good-std.md"
  printf 'the 7 required gates pass\n' > "$d/good-prin.md"
  if check "$d/good-std.md" "$d/good-prin.md" >/dev/null 2>&1; then echo "PASS: selftest — good set verifies"; else echo "FAIL: selftest — good set wrongly rejected"; sfail=1; fi
  # BAD: 8 required rows but still "seven" -> must FAIL
  sed 's/| 7 | \*\*Gate7\*\* | x |/| 7 | **Gate7** | x |\n| 8 | **Gate8** | x |/' "$d/good-std.md" > "$d/bad-std.md"
  if check "$d/bad-std.md" "$d/good-prin.md" >/dev/null 2>&1; then echo "FAIL: selftest — count drift (8 vs 'seven') not caught"; sfail=1; else echo "PASS: selftest — required-count drift detected"; fi
  # BAD: principles missing the "7 required gates" claim -> must FAIL
  printf 'no claim here\n' > "$d/bad-prin.md"
  if check "$d/good-std.md" "$d/bad-prin.md" >/dev/null 2>&1; then echo "FAIL: selftest — missing principles claim not caught"; sfail=1; else echo "PASS: selftest — cross-doc claim absence detected"; fi
  [ "$sfail" -eq 0 ] && { echo "OK: claim-gate-counts selftest"; exit 0; } || { echo "FAIL: claim-gate-counts selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: claim-gate-counts.sh [--selftest]" >&2; exit 2 ;;
esac

echo "Gate-count claim consistency:"
if check "$STD" "$PRIN"; then echo "OK: gate-count claims match the enumeration"; exit 0; else echo "FAIL: gate-count claim drift (see above)"; exit 1; fi
