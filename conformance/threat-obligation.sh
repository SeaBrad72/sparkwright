#!/bin/sh
# Why this gate: sparkwright explain threat-model
# threat-obligation.sh — HITL obligation: a change-set touching a sensitive/regulated-data
# surface MUST carry a filled THREAT-MODEL record, else FAIL. Diff-level (vs privacy-ready.sh's
# project-level declaration) — they compose, not collide.
#
# SCOPE (honest ceiling): green = a THREAT-MODEL record EXISTS and is FILLED for a triggered change —
# NOT that it is fresh-for-this-change, nor that the threat analysis is sound (review backstops).
# N-A = the change-set touches no sensitive surface (trigger-absence), exactly like privacy-ready.sh.
#
# Usage:
#   sh conformance/threat-obligation.sh                 (derive change-set: merge-base HEAD origin/main)
#   sh conformance/threat-obligation.sh --changed FILE  (fixture path list; honored ONLY under
#                                                         --selftest / the KIT_OBL_TEST env flag — ignored in production)
#   sh conformance/threat-obligation.sh --selftest
set -eu
# shellcheck disable=SC1007 # `CDPATH= cd` is the correct idiom: it clears CDPATH for this one command so
# a user's CDPATH cannot redirect the cd; the empty assignment is intentional, not a mistyped value.
DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
# Tell the engine it is being SOURCED (not executed directly), so its --selftest dispatch stays inert
# here: without this, `sh threat-obligation.sh --selftest` would run the LIB's selftest (the sourced
# lib sees $1=--selftest) instead of this obligation's 5-leg selftest. Value is 'yes' (NOT '=1') so the
# non-vacuity sweep — which neuters a pre-marker <var>=1 — cannot flip it; this line carries no mutable
# idiom, so run_threat_obligation stays the (idiomless) mutation region and this file's verdict is
# unchanged. A $0-basename guard would not survive the sweep renaming the lib's copy to .nv-mut-*.
OBL_LIB_SOURCED=yes
. "$DIR/conformance/obligation-lib.sh"

# The obligation: sensitive-surface globs + THREAT-MODEL record.
run_threat_obligation() {   # args: forwarded (--changed FILE | none)
  obligation_gate \
    --name "threat-model" \
    --surface-globs '*secret*|*auth*|*password*|*payment*|*migrations/*|*.env' \
    --record "THREAT-MODEL.md" \
    --template-marker "templates/THREAT-MODEL-TEMPLATE.md" \
    "$@"
}

# ---- selftest() marker: the non-vacuity sweep mutates ONLY lines ABOVE here ----
selftest() {
  _tmp="$(mktemp -d "${TMPDIR:-/tmp}/threat-st.XXXXXX")"; trap 'rm -rf "$_tmp"' EXIT INT TERM
  export KIT_OBL_TEST=1   # honor the fixture flags (--changed/--root/--force-uncertain) only in-test (M1)
  rc=0
  # LEG 1 (liveness/negative): sensitive surface touched, NO record -> RED
  printf 'src/auth/login.js\n' > "$_tmp/changed"
  if run_threat_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
    echo "SELFTEST FAIL: sensitive surface with no THREAT-MODEL did not FAIL"; rc=1
  fi
  # LEG 2 (positive): no sensitive surface -> green (N-A)
  printf 'docs/README.md\n' > "$_tmp/changed"
  if ! run_threat_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
    echo "SELFTEST FAIL: non-sensitive change did not pass (N-A)"; rc=1
  fi
  # LEG 3 (fail-safe, simulated): --force-uncertain simulates the uncertain band (the derived path has no
  # per-file uncertain heuristic; the REAL uncertain trigger is a derive-failure — LEG 4). NO record -> RED
  printf 'config/settings.yaml\n' > "$_tmp/changed"
  if run_threat_obligation --changed "$_tmp/changed" --root "$_tmp" --force-uncertain >/dev/null 2>&1; then
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
  if ( cd "$_dr" && run_threat_obligation --root "$_dr" ) >/dev/null 2>&1; then
    echo "SELFTEST FAIL: underivable change-set (no resolvable base) did not FAIL (derive fail-open)"; rc=1
  fi
  # LEG 5 (L1 regression guard, false-positive): sensitive surface touched, a GENUINELY-FILLED record whose
  # only brackets are markdown links / citations ([STRIDE], [design doc](…), [1]) — NO template stubs, NO
  # banner -> must be treated as FILLED and PASS. The pre-fix arbitrary-`[...]` >=3 count wrongly FAILed such
  # a record as an unfilled placeholder; this leg kills a regression of that exact false-positive.
  printf 'src/auth/login.js\n' > "$_tmp/changed"
  printf '# Threat Model\n\nAssets analyzed per [STRIDE]; rationale in the [design doc](https://x/y).\nSpoofing mitigated by MFA and token validation; see ref [1]. Data classification: confidential (customer PII).\n' > "$_tmp/THREAT-MODEL.md"
  if ! run_threat_obligation --changed "$_tmp/changed" --root "$_tmp" >/dev/null 2>&1; then
    echo "SELFTEST FAIL: filled THREAT-MODEL with markdown links/citations was wrongly FAILed as a placeholder"; rc=1
  fi
  [ "$rc" = 0 ] && echo "OK (threat-obligation: 5 legs)"; return $rc
}

# dispatch — BELOW the selftest() definition so the function is defined before it is called
# (POSIX sh executes top-to-bottom; a forward reference to selftest fails with 'command not found').
# The non-vacuity marker is the selftest() line above, so the check-logic region (run_threat_obligation)
# is still mutated; this dispatch sits after the marker and is emitted verbatim by the sweep.
if [ "${1:-}" = "--selftest" ]; then selftest; exit $?; fi
run_threat_obligation "$@"; exit $?
