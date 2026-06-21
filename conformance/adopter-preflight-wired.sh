#!/bin/sh
# adopter-preflight-wired.sh — regression-lock for the S2 "Adopter environment" preflight section.
# Asserts scripts/preflight.sh surfaces the three adopter-environment advisories and that they stay
# ADVISORY (WARN-only: a warn must never set `miss`, so preflight's exit code is unaffected). This is
# the external lock (mirrors doctor-wired.sh); preflight's own --selftest proves the per-check states.
#   sh conformance/adopter-preflight-wired.sh [--selftest]
# Exit: 0 = wired + advisory · 1 = a check is missing/regressed · 2 = setup. POSIX sh; dash-clean.
set -eu
cd "$(dirname "$0")/.."

PF="${ADOPTER_PREFLIGHT_FILE:-scripts/preflight.sh}"

run() {
  rc=0
  [ -f "$PF" ] || { echo "FAIL: $PF not found"; return 1; }

  # 1. the three check functions + the section header are present
  for _needle in 'Adopter environment' 'check_repo_class' 'check_codeowners_placeholders' 'check_workflows_valid' 'is_github_repo'; do
    grep -q "$_needle" "$PF" || { echo "FAIL: $PF missing '$_needle'"; rc=1; }
  done

  # 2. the section is dispatched only behind is_github_repo
  grep -q 'if is_github_repo; then' "$PF" || { echo "FAIL: section not gated behind is_github_repo"; rc=1; }

  # 3. each check actually fires + is WARN-only (driven via preflight's own selftest seams)
  _o=$(PREFLIGHT_GH_CMD='printf {"isPrivate":true,"isInOrganization":false}' sh "$PF" --selftest 2>&1) || true
  printf '%s\n' "$_o" | grep -q 'repo-class warn leaves miss untouched' || { echo "FAIL: repo-class WARN-only invariant not asserted by preflight selftest"; rc=1; }
  printf '%s\n' "$_o" | grep -q 'codeowners warn leaves miss untouched'  || { echo "FAIL: codeowners WARN-only invariant not asserted"; rc=1; }
  printf '%s\n' "$_o" | grep -q 'workflow warn leaves miss untouched'    || { echo "FAIL: workflow WARN-only invariant not asserted"; rc=1; }
  printf '%s\n' "$_o" | grep -q 'OK: preflight selftest'                 || { echo "FAIL: preflight selftest did not pass"; rc=1; }

  [ "$rc" -eq 0 ] && echo "PASS: adopter-preflight section wired + advisory"
  return $rc
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  # positive: the real preflight passes
  run >/dev/null 2>&1 || { echo "adopter-preflight-wired --selftest: FAIL (real preflight not green)"; sfail=1; }
  # negative: a stripped copy (section removed) must FAIL the lock. Strip from $PF (not a hardcoded
  # path) so the selftest is exercisable in flat scratch (ADOPTER_PREFLIGHT_FILE=/tmp/.../preflight.sh)
  # AND in the real repo (default scripts/preflight.sh).
  _tmp=$(mktemp -d)
  grep -v 'Adopter environment' "$PF" > "$_tmp/preflight.sh"
  _saved_pf="$PF"; PF="$_tmp/preflight.sh"
  _neg_rc=0; _neg=$(run 2>&1) || _neg_rc=$?
  if [ "$_neg_rc" -eq 0 ]; then
    echo "adopter-preflight-wired --selftest: FAIL (stripped preflight still passed)"; sfail=1
  elif ! printf '%s\n' "$_neg" | grep -q "missing 'Adopter environment'"; then
    echo "adopter-preflight-wired --selftest: FAIL (stripped preflight failed for the wrong reason: $_neg)"; sfail=1
  fi
  PF="$_saved_pf"
  rm -rf "$_tmp"
  [ "$sfail" -eq 0 ] && { echo "adopter-preflight-wired --selftest: OK"; exit 0; } || exit 1
fi

run
