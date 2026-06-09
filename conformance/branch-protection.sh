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

run() {
  have_gh || unverifiable "gh not installed"
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
  [ -n "$REPO" ] || unverifiable "no GitHub repo context"
  PROT=$(gh api "repos/$REPO/branches/$BRANCH/protection" 2>/dev/null || true)
  if [ -z "$PROT" ] || printf '%s' "$PROT" | grep -q '"Branch not protected"'; then
    echo "FAIL: $BRANCH on $REPO has no branch protection."
    exit 1
  fi
  if printf '%s' "$PROT" | grep -Eq '"status":[[:space:]]*"40[13]"|Not Found|Resource not accessible'; then
    unverifiable "branch-protection not readable (token lacks repo-admin) on $REPO"
  fi
  ok=0
  printf '%s' "$PROT" | grep -q '"required_pull_request_reviews"' || { echo "FAIL: required PR reviews not enabled on $BRANCH"; ok=1; }
  printf '%s' "$PROT" | grep -q '"required_status_checks"' || { echo "FAIL: required status checks not enabled on $BRANCH"; ok=1; }
  [ "$ok" -eq 0 ] && echo "OK: $BRANCH on $REPO is protected (PR reviews + status checks required)."
  exit "$ok"
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
  [ "$st" = "0" ] && echo "branch-protection --selftest: OK"
  return "$st"
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *) run ;;
esac
