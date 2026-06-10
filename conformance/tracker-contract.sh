#!/bin/sh
# tracker-contract.sh — verify a Jira instance satisfies the §6 work-item contract (Slice 9h).
# Three-state, like branch-protection.sh:
#   creds (JIRA_BASE_URL + JIRA_EMAIL + JIRA_TOKEN) -> live REST check -> PASS/FAIL
#   no creds                                         -> UNVERIFIED (exit 2; never a silent pass)
#   --selftest                                       -> run the contract logic on fixtures (CI-safe)
# The six §6 states + Size/Risk fields are checked live; the "Only Assignee" transition CONDITION is
# reported ATTESTED (basic REST cannot cheaply introspect workflow conditions — green != verified).
# Zero-dependency core (grep-based); curl only on the live path. POSIX sh; dash-clean.
# Exit: 0 = contract satisfied · 1 = a gap · 2 = UNVERIFIED / bad usage.
set -eu

# Six §6 states (+ Blocked) and the two required custom fields, as single shell words
# (spaces normalized to hyphens below so "In Progress" matches "In-Progress").
REQUIRED="Backlog Ready In-Progress In-Review Released Done Blocked Size Risk"

# check_blob <file>: every required name must appear as an EXACT quoted value (whitespace-insensitive).
# Matching the quoted JSON value ("In Progress" -> "In-Progress") avoids loose substring over-passes —
# e.g. a status "Ready for Dev" must NOT satisfy the "Ready" requirement. Return 1 on any miss.
check_blob() {
  bf=$1; f=0
  if [ ! -f "$bf" ]; then echo "FAIL: missing $bf"; return 1; fi
  norm=$(tr -s '[:space:]' '-' < "$bf")
  for name in $REQUIRED; do
    if printf '%s' "$norm" | grep -qF -- "\"$name\""; then
      echo "PASS: contract names '$name'"
    else
      echo "FAIL: contract omits '$name'"; f=1
    fi
  done
  return $f
}

# live_check <base-url>: fetch statuses + fields, run check_blob; attest the transition condition.
live_check() {
  base=$1; tmp=$(mktemp)
  curl -fsS -u "$JIRA_EMAIL:$JIRA_TOKEN" "$base/rest/api/3/status" >> "$tmp" 2>/dev/null || {
    echo "FAIL: could not reach $base/rest/api/3/status"; rm -f "$tmp"; return 1; }
  curl -fsS -u "$JIRA_EMAIL:$JIRA_TOKEN" "$base/rest/api/3/field" >> "$tmp" 2>/dev/null || {
    echo "FAIL: could not reach $base/rest/api/3/field"; rm -f "$tmp"; return 1; }
  if check_blob "$tmp"; then rc=0; else rc=1; fi
  rm -f "$tmp"
  echo "ATTESTED (not auto-verified): confirm the In-Progress transition has the Only-Assignee condition — see JIRA-SETUP.md."
  return $rc
}

case "${1:-}" in
  --selftest)
    sfail=0
    # fixtures mimic Jira REST JSON (quoted "name" values), exercising the exact-quoted match.
    okf=$(mktemp); printf '"Backlog" "Ready" "In Progress" "In Review" "Released" "Done" "Blocked" "Size" "Risk"\n' > "$okf"
    if check_blob "$okf" >/dev/null 2>&1; then echo "PASS: selftest — conformant config passes"; else echo "FAIL: selftest — conformant wrongly rejected"; sfail=1; fi
    gapf=$(mktemp); printf '"Backlog" "Ready" "In Progress" "In Review" "Released" "Done" "Blocked" "Size"\n' > "$gapf"   # missing "Risk"
    if check_blob "$gapf" >/dev/null 2>&1; then echo "FAIL: selftest — gap (missing Risk) not detected"; sfail=1; else echo "PASS: selftest — gap detected"; fi
    # near-miss fixture: a "Ready for Dev" status must NOT satisfy the exact "Ready" requirement.
    nmf=$(mktemp); printf '"Backlog" "Ready for Dev" "In Progress" "In Review" "Released" "Done" "Blocked" "Size" "Risk"\n' > "$nmf"
    if check_blob "$nmf" >/dev/null 2>&1; then echo "FAIL: selftest — loose 'Ready for Dev' wrongly accepted as 'Ready'"; sfail=1; else echo "PASS: selftest — near-miss status name rejected"; fi
    rm -f "$okf" "$gapf" "$nmf"
    [ "$sfail" -eq 0 ] && { echo "OK: tracker-contract selftest"; exit 0; } || { echo "FAIL: tracker-contract selftest"; exit 1; }
    ;;
  "") : ;;
  *) echo "usage: tracker-contract.sh [--selftest]" >&2; exit 2 ;;
esac

if [ -n "${JIRA_BASE_URL:-}" ] && [ -n "${JIRA_EMAIL:-}" ] && [ -n "${JIRA_TOKEN:-}" ]; then
  echo "Jira contract check (live: $JIRA_BASE_URL):"
  if live_check "$JIRA_BASE_URL"; then
    echo "OK: Jira names the six §6 states + Size/Risk fields"
    exit 0
  else
    echo "FAIL: Jira does not satisfy the §6 contract (see above)"
    exit 1
  fi
else
  echo "UNVERIFIED: set JIRA_BASE_URL + JIRA_EMAIL + JIRA_TOKEN to verify a live Jira (exit 2, not a pass)."
  echo "  Configure per JIRA-SETUP.md; this is the kit's honest 'cannot run != pass' (conformance/README.md)."
  exit 2
fi
