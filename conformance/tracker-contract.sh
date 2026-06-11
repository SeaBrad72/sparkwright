#!/bin/sh
# tracker-contract.sh — verify a Jira instance satisfies the §6 work-item contract (Slice 9h; --deep 10).
# Three-state, like branch-protection.sh:
#   creds (JIRA_BASE_URL + JIRA_EMAIL + JIRA_TOKEN) -> live REST check -> PASS/FAIL
#   no creds                                         -> UNVERIFIED (exit 2; never a silent pass)
#   --selftest                                       -> run the contract logic on fixtures (CI-safe)
# Base run checks the six §6 states + Size/Risk fields. With --deep, ALSO introspects the workflow
# (/rest/api/3/workflow/search?expand=transitions.rules) to VERIFY the In-Progress transition carries
# an assignee-restriction condition (the Only-Assignee atomic claim) — turning "attested" into
# "verified". The deep matcher is best-effort: Jira workflow JSON shape varies (Cloud/Server), so it
# matches a broad assignee-restriction marker; the parse logic is proven in --selftest on a fixture.
# Zero-dependency core (grep-based); curl only on the live path. POSIX sh; dash-clean.
# Exit: 0 = satisfied · 1 = a gap · 2 = UNVERIFIED / bad usage.
set -eu

REQUIRED="Backlog Ready In-Progress In-Review Released Done Blocked Size Risk"

# check_blob <file>: every required name must appear as an EXACT quoted value (whitespace-insensitive).
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

# deep_check <file>: the workflow JSON must carry an assignee-restriction condition. Best-effort,
# broad matcher (the In-Progress transition's Only-Assignee rule). Return 1 if absent.
deep_check() {
  bf=$1
  if [ ! -f "$bf" ]; then echo "FAIL: missing $bf"; return 1; fi
  if grep -Eiq 'onlyassignee|assignee[^"]*condition|"is[_-]?assignee"' "$bf"; then
    echo "PASS: deep — workflow carries an assignee-restriction condition (Only-Assignee → server-enforced claim)"
    return 0
  fi
  echo "FAIL: deep — no assignee-restriction condition found (the atomic claim is NOT server-enforced — see JIRA-SETUP.md §3)"
  return 1
}

# live_check <base-url>: fetch statuses + fields, run check_blob (no attest line — caller handles deep/attest).
live_check() {
  base=$1; tmp=$(mktemp)
  curl -fsS -u "$JIRA_EMAIL:$JIRA_TOKEN" "$base/rest/api/3/status" >> "$tmp" 2>/dev/null || {
    echo "FAIL: could not reach $base/rest/api/3/status"; rm -f "$tmp"; return 1; }
  curl -fsS -u "$JIRA_EMAIL:$JIRA_TOKEN" "$base/rest/api/3/field" >> "$tmp" 2>/dev/null || {
    echo "FAIL: could not reach $base/rest/api/3/field"; rm -f "$tmp"; return 1; }
  if check_blob "$tmp"; then rc=0; else rc=1; fi
  rm -f "$tmp"; return $rc
}

# deep_live <base-url>: fetch the workflow with transition rules, run deep_check.
deep_live() {
  base=$1; tmp=$(mktemp)
  curl -fsS -u "$JIRA_EMAIL:$JIRA_TOKEN" "$base/rest/api/3/workflow/search?expand=transitions.rules" >> "$tmp" 2>/dev/null || {
    echo "FAIL: could not reach $base/rest/api/3/workflow/search"; rm -f "$tmp"; return 1; }
  if deep_check "$tmp"; then rc=0; else rc=1; fi
  rm -f "$tmp"; return $rc
}

# --- arg parse: --deep and --selftest combine in any order ---
DEEP=0; SELFTEST=0
for a in "$@"; do
  case "$a" in
    --deep) DEEP=1 ;;
    --selftest) SELFTEST=1 ;;
    "") : ;;
    *) echo "usage: tracker-contract.sh [--deep] [--selftest]" >&2; exit 2 ;;
  esac
done

if [ "$SELFTEST" -eq 1 ]; then
  sfail=0
  okf=$(mktemp); printf '"Backlog" "Ready" "In Progress" "In Review" "Released" "Done" "Blocked" "Size" "Risk"\n' > "$okf"
  if check_blob "$okf" >/dev/null 2>&1; then echo "PASS: selftest — conformant config passes"; else echo "FAIL: selftest — conformant wrongly rejected"; sfail=1; fi
  gapf=$(mktemp); printf '"Backlog" "Ready" "In Progress" "In Review" "Released" "Done" "Blocked" "Size"\n' > "$gapf"
  if check_blob "$gapf" >/dev/null 2>&1; then echo "FAIL: selftest — gap (missing Risk) not detected"; sfail=1; else echo "PASS: selftest — gap detected"; fi
  nmf=$(mktemp); printf '"Backlog" "Ready for Dev" "In Progress" "In Review" "Released" "Done" "Blocked" "Size" "Risk"\n' > "$nmf"
  if check_blob "$nmf" >/dev/null 2>&1; then echo "FAIL: selftest — loose 'Ready for Dev' wrongly accepted"; sfail=1; else echo "PASS: selftest — near-miss status name rejected"; fi
  # deep fixtures: a workflow WITH the Only-Assignee condition must pass; one WITHOUT must fail.
  okd=$(mktemp); printf '{"values":[{"transitions":[{"name":"In Progress","rules":{"conditions":[{"type":"OnlyAssigneeCondition"}]}}]}]}\n' > "$okd"
  if deep_check "$okd" >/dev/null 2>&1; then echo "PASS: selftest — deep accepts Only-Assignee condition"; else echo "FAIL: selftest — deep wrongly rejected the condition"; sfail=1; fi
  gapd=$(mktemp); printf '{"values":[{"transitions":[{"name":"In Progress","rules":{"conditions":[]}}]}]}\n' > "$gapd"
  if deep_check "$gapd" >/dev/null 2>&1; then echo "FAIL: selftest — deep missed an absent condition"; sfail=1; else echo "PASS: selftest — deep detects an absent condition"; fi
  rm -f "$okf" "$gapf" "$nmf" "$okd" "$gapd"
  [ "$sfail" -eq 0 ] && { echo "OK: tracker-contract selftest"; exit 0; } || { echo "FAIL: tracker-contract selftest"; exit 1; }
fi

if [ -n "${JIRA_BASE_URL:-}" ] && [ -n "${JIRA_EMAIL:-}" ] && [ -n "${JIRA_TOKEN:-}" ]; then
  echo "Jira contract check (live: $JIRA_BASE_URL):"
  ok=0
  if live_check "$JIRA_BASE_URL"; then :; else ok=1; fi
  if [ "$DEEP" -eq 1 ]; then
    echo "Deep: Only-Assignee transition condition (workflow introspection):"
    if deep_live "$JIRA_BASE_URL"; then :; else ok=1; fi
  else
    echo "ATTESTED (not auto-verified): confirm the Only-Assignee condition, or re-run with --deep to verify it — see JIRA-SETUP.md."
  fi
  if [ "$ok" -eq 0 ]; then
    if [ "$DEEP" -eq 1 ]; then echo "OK: Jira satisfies the §6 contract (incl. the verified Only-Assignee claim)"; else echo "OK: Jira satisfies the §6 contract"; fi
    exit 0
  else
    echo "FAIL: Jira does not satisfy the §6 contract (see above)"; exit 1
  fi
else
  echo "UNVERIFIED: set JIRA_BASE_URL + JIRA_EMAIL + JIRA_TOKEN to verify a live Jira (exit 2, not a pass)."
  echo "  Configure per JIRA-SETUP.md; this is the kit's honest 'cannot run != pass' (conformance/README.md)."
  exit 2
fi
