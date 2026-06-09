#!/bin/sh
# branch-protection.sh — verify `main` is actually protected on the remote
# (DEVELOPMENT-STANDARDS.md §14 / DEVELOPMENT-PROCESS.md §12). THREE-STATE contract:
#   exit 0  — verified protected (PR reviews + status checks required)
#   exit 1  — verified NOT protected / a required setting missing (FAIL)
#   exit 2  — COULD NOT VERIFY (no gh, unauthenticated, or no GitHub remote) — NOT a pass.
# A silent pass when unverifiable is false assurance; this returns a distinct status.
# Escalation: in CI (CI env set) or with --require, "could not verify" becomes exit 1 —
# in a gate the check MUST be runnable. Requires `gh` authenticated to verify.
#   usage: sh conformance/branch-protection.sh [BRANCH] [--require] | --selftest
set -eu

REQUIRE="${REQUIRE:-0}"
[ -n "${CI:-}" ] && REQUIRE=1
BRANCH=main
for a in "$@"; do
  case "$a" in
    --require) REQUIRE=1 ;;
    --selftest) ;;  # dispatched below
    -*) echo "usage: branch-protection.sh [BRANCH] [--require] | --selftest" >&2; exit 2 ;;
    *) BRANCH="$a" ;;
  esac
done

# Unverifiable: exit 2 normally; exit 1 (FAIL) under CI/--require (a gate must be runnable).
unverifiable() {
  if [ "$REQUIRE" = "1" ]; then
    echo "FAIL: branch-protection could not verify ($1) and verification is required (CI/--require)."
    exit 1
  fi
  echo "UNVERIFIED: $1 — run in CI or authenticate gh. (NOT a pass.)"
  exit 2
}

have_gh() {
  [ "${BP_FORCE_NO_GH:-0}" = "1" ] && return 1
  command -v gh >/dev/null 2>&1
}

# classify RC BODY — decide PASS/FAIL/UNVERIFIED from the HTTP outcome, NOT body substrings.
# Only a genuine HTTP 200 (gh exit 0) is allowed to reach the required-settings check, so a
# non-200 ERROR body that merely *names* the settings can never read as protected.
classify() {
  rc=$1; body=$2
  if [ "$rc" = "0" ]; then
    # HTTP 200: this IS the live protection config — verify the required settings are present.
    ok=0
    printf '%s' "$body" | grep -q '"required_pull_request_reviews"' || { echo "FAIL: required PR reviews not enabled on $BRANCH"; ok=1; }
    printf '%s' "$body" | grep -q '"required_status_checks"' || { echo "FAIL: required status checks not enabled on $BRANCH"; ok=1; }
    [ "$ok" -eq 0 ] && echo "OK: $BRANCH on ${REPO:-?} is protected (PR reviews + status checks required)."
    exit "$ok"
  fi
  # Non-200. A definitive "no protection" (404) is a real FAIL; anything else (403 admin-rights,
  # 401, rate-limit, empty/transient body) is NOT determinable here -> UNVERIFIED (never a pass).
  if printf '%s' "$body" | grep -q 'Branch not protected'; then
    echo "FAIL: $BRANCH on ${REPO:-?} has no branch protection."; exit 1
  fi
  unverifiable "protection endpoint returned non-200 (token may lack repo-admin, or transient/empty) on ${REPO:-?}"
}

run() {
  # selftest stub seam: inject a canned (rc, body) without touching the network or gh.
  [ -n "${BP_STUB_RC:-}" ] && classify "$BP_STUB_RC" "${BP_STUB_BODY:-}"
  have_gh || unverifiable "gh not installed"
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
  [ -n "$REPO" ] || unverifiable "no GitHub repo context"
  PROT=$(gh api "repos/$REPO/branches/$BRANCH/protection" 2>/dev/null) && rc=0 || rc=$?
  classify "$rc" "$PROT"
}

selftest() {
  st=0
  out=$(CI= REQUIRE=0 BP_FORCE_NO_GH=1 sh "$0" 2>&1) && rc=0 || rc=$?
  if [ "$rc" = "2" ]; then echo "selftest PASS: no-gh local -> exit 2 (UNVERIFIED)"; else echo "selftest FAIL: no-gh local should be exit 2 (got $rc)"; st=1; fi
  printf '%s' "$out" | grep -q UNVERIFIED || { echo "selftest FAIL: missing UNVERIFIED message"; st=1; }
  out=$(CI=true BP_FORCE_NO_GH=1 sh "$0" 2>&1) && rc=0 || rc=$?
  if [ "$rc" = "1" ]; then echo "selftest PASS: no-gh + CI -> exit 1 (FAIL escalation)"; else echo "selftest FAIL: no-gh+CI should be exit 1 (got $rc)"; st=1; fi
  out=$(CI= BP_FORCE_NO_GH=1 sh "$0" --require 2>&1) && rc=0 || rc=$?
  if [ "$rc" = "1" ]; then echo "selftest PASS: no-gh + --require -> exit 1"; else echo "selftest FAIL: no-gh+--require should be exit 1 (got $rc)"; st=1; fi
  # HTTP-status-based parse (stub seam): only a real 200 with both settings is a pass.
  out=$(CI= BP_STUB_RC=0 BP_STUB_BODY='{"required_pull_request_reviews":{},"required_status_checks":{}}' sh "$0" 2>&1) && rc=0 || rc=$?
  if [ "$rc" = "0" ]; then echo "selftest PASS: 200 + both settings -> exit 0"; else echo "selftest FAIL: 200+both should pass (got $rc)"; st=1; fi
  out=$(CI= BP_STUB_RC=0 BP_STUB_BODY='{}' sh "$0" 2>&1) && rc=0 || rc=$?
  if [ "$rc" = "1" ]; then echo "selftest PASS: 200 + missing settings -> exit 1"; else echo "selftest FAIL: 200+missing should fail (got $rc)"; st=1; fi
  out=$(CI= BP_STUB_RC=1 BP_STUB_BODY='{"message":"Branch not protected","status":"404"}' sh "$0" 2>&1) && rc=0 || rc=$?
  if [ "$rc" = "1" ]; then echo "selftest PASS: 404 not-protected -> exit 1"; else echo "selftest FAIL: 404 should fail (got $rc)"; st=1; fi
  out=$(CI= BP_STUB_RC=1 BP_STUB_BODY='{"message":"Must have admin rights to Repository."}' sh "$0" 2>&1) && rc=0 || rc=$?
  if [ "$rc" = "2" ]; then echo "selftest PASS: 403 admin-rights -> exit 2 (UNVERIFIED)"; else echo "selftest FAIL: 403 should be UNVERIFIED (got $rc)"; st=1; fi
  # the spoof: a non-200 error body that NAMES the settings must NOT read as a pass.
  out=$(CI= BP_STUB_RC=1 BP_STUB_BODY='{"message":"validation failed","errors":["required_pull_request_reviews","required_status_checks"]}' sh "$0" 2>&1) && rc=0 || rc=$?
  if [ "$rc" = "2" ]; then echo "selftest PASS: non-200 spoof body -> exit 2 (NOT a false pass)"; else echo "selftest FAIL: spoof body must not pass (got $rc)"; st=1; fi
  [ "$st" = "0" ] && echo "branch-protection --selftest: OK"
  return "$st"
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *) run ;;
esac
