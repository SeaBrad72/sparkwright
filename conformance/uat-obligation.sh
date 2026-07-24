#!/bin/sh
# Why this gate: sparkwright explain uat
# uat-obligation.sh — HITL obligation: a change-set touching a user-facing TASTE surface (UI:
# components/views/pages/screens/templates/frontend/styles) MUST carry a filled UAT-SIGNOFF record,
# else FAIL. Diff-level, riding the shipped obligation engine (same as threat-obligation.sh); the
# HITL-3 board Done-edge flag is the discipline layer — THIS gate is the hard backstop.
#
# SCOPE (honest ceiling): green = a UAT-SIGNOFF record EXISTS and is FILLED for a triggered change —
# NOT that a human actually engaged their taste / exercised the surface, nor that the acceptance
# judgment is sound (UAT sign-off + review backstop that). N-A = the change-set touches no taste
# surface (trigger-absence), exactly like threat-obligation.sh. CONSERVATIVE by design: clear-UI globs
# ONLY — ambiguous/non-UI files are N-A and false-negatives are accepted (the only 'uncertain' source
# is a derive-failure, which fails CLOSED). Better to miss a borderline surface than to nag on prose.
#
# Usage:
#   sh conformance/uat-obligation.sh                 (derive change-set: merge-base HEAD origin/main)
#   sh conformance/uat-obligation.sh --changed FILE  (fixture path list; honored ONLY under
#                                                      --selftest / the KIT_OBL_TEST env flag — ignored in production)
#   sh conformance/uat-obligation.sh --selftest
set -eu
# shellcheck disable=SC1007 # `CDPATH= cd` is the correct idiom: it clears CDPATH for this one command so
# a user's CDPATH cannot redirect the cd; the empty assignment is intentional, not a mistyped value.
DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
# Tell the engine it is being SOURCED (not executed directly), so its --selftest dispatch stays inert
# here: without this, `sh uat-obligation.sh --selftest` would run the LIB's selftest (the sourced lib
# sees $1=--selftest) instead of this obligation's 5-leg selftest. Value is 'yes' (NOT a numeric flag) so
# the non-vacuity sweep — which neuters a pre-marker numeric-flag assignment — cannot flip it; this line
# carries no mutable idiom, so run_uat_obligation stays the (idiomless) mutation region and this file's
# verdict is unchanged. A $0-basename guard would not survive the sweep renaming the lib's copy to .nv-mut-*.
OBL_LIB_SOURCED=yes
. "$DIR/conformance/obligation-lib.sh"

# The obligation: clear-UI taste-surface globs + UAT-SIGNOFF record.
run_uat_obligation() {   # args: forwarded (--changed FILE | none)
  obligation_gate \
    --name "uat" \
    --surface-globs '*/components/*|*/views/*|*/pages/*|*/screens/*|*/templates/*|*/ui/*|*/frontend/*|*/styles/*|*.tsx|*.jsx|*.vue|*.svelte|*.css|*.scss|*.less' \
    --record "UAT-SIGNOFF.md" \
    --template-marker "templates/UAT-SIGNOFF-TEMPLATE.md" \
    "$@"
}

# ---- selftest() marker: the non-vacuity sweep mutates ONLY lines ABOVE here ----
selftest() {
  _tmp="$(mktemp -d "${TMPDIR:-/tmp}/uat-st.XXXXXX")"; trap 'rm -rf "$_tmp"' EXIT INT TERM
  export KIT_OBL_TEST=1   # honor the fixture flags (--changed/--root/--force-uncertain) only in-test (M1)
  rc=0
  # LEG 1 (liveness/negative): taste surface touched, NO record -> RED
  printf 'src/components/Login.tsx\n' > "$_tmp/changed"
  if run_uat_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
    echo "SELFTEST FAIL: taste surface with no UAT-SIGNOFF did not FAIL"; rc=1
  fi
  # LEG 2 (positive): no taste surface -> green (N-A)
  printf 'docs/README.md\n' > "$_tmp/changed"
  if ! run_uat_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
    echo "SELFTEST FAIL: non-UI change did not pass (N-A)"; rc=1
  fi
  # LEG 3 (fail-safe, simulated): --force-uncertain simulates the uncertain band (the conservative posture
  # has no per-file uncertain heuristic; the REAL uncertain trigger is a derive-failure — LEG 4). NO record -> RED
  printf 'config/settings.yaml\n' > "$_tmp/changed"
  if run_uat_obligation --changed "$_tmp/changed" --root "$_tmp" --force-uncertain >/dev/null 2>&1; then
    echo "SELFTEST FAIL: uncertain surface with no record did not FAIL (fail-safe broken)"; rc=1
  fi
  # LEG 4 (REAL derive-failure, C1/H1): a change-set that CANNOT be derived (no resolvable base) must fail
  # CLOSED — route to uncertain and require the record. Throwaway repo with NO origin/main and NO 'main'
  # branch, so both merge-base probes fail: a REAL derive-failure, not the --force-uncertain simulation.
  _dr="$_tmp/derive"; mkdir -p "$_dr"
  git -C "$_dr" init -q >/dev/null 2>&1
  git -C "$_dr" config user.email obl@test.local
  git -C "$_dr" config user.name obl-test
  : > "$_dr/file.txt"; git -C "$_dr" add file.txt; git -C "$_dr" commit -qm init >/dev/null 2>&1
  git -C "$_dr" branch -m obl-st-nobase >/dev/null 2>&1   # rename so neither 'main' nor 'master' resolves
  if ( cd "$_dr" && run_uat_obligation --root "$_dr" ) >/dev/null 2>&1; then
    echo "SELFTEST FAIL: underivable change-set (no resolvable base) did not FAIL (derive fail-open)"; rc=1
  fi
  # LEG 5 (positive, false-positive guard): taste surface touched, a GENUINELY-FILLED UAT-SIGNOFF whose
  # banner is deleted and whose Decision is 'accept' -> must be treated as FILLED and PASS. The template's
  # own '> **Template.**' banner is absent and no unfilled bracket stub remains, so the engine's
  # obl_is_placeholder must NOT flag it. This kills a regression that would wrongly FAIL a filled record.
  printf 'src/components/Login.tsx\n' > "$_tmp/changed"
  printf '# UAT Sign-off\n\n| Field | Value |\n|-------|-------|\n| Gate | UAT |\n| Feature / story | https://github.com/x/y/issues/42 |\n| Acceptance criteria verdict | met |\n| Test-plan reference | docs/sign-offs/test-plan.md |\n| Evidence | https://x/y demo, screenshots attached |\n| Decision | accept |\n| Signer (role) | Jane Roe (QA) |\n| Date | 2026-07-24 |\n| Notes | Clean run, no gaps. |\n' > "$_tmp/UAT-SIGNOFF.md"
  if ! run_uat_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
    echo "SELFTEST FAIL: a genuinely-filled UAT-SIGNOFF (banner deleted, Decision=accept) was wrongly FAILed as a placeholder"; rc=1
  fi
  [ "$rc" = 0 ] && echo "OK (uat-obligation: 5 legs)"; return $rc
}

# dispatch — BELOW the selftest() definition so the function is defined before it is called
# (POSIX sh executes top-to-bottom; a forward reference to selftest fails with 'command not found').
# The non-vacuity marker is the selftest() line above, so the check-logic region (run_uat_obligation)
# is still mutated; this dispatch sits after the marker and is emitted verbatim by the sweep.
if [ "${1:-}" = "--selftest" ]; then selftest; exit $?; fi
run_uat_obligation "$@"; exit $?
