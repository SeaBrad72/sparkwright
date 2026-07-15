#!/bin/sh
# doctor.sh — adopter-facing POSTURE report. Composes existing conformance checks into one
# "am I conformant + have I drifted?" summary. Automates the *mechanizable* half of
# docs/operations/drift-self-check.md (axes D claim-integrity + E git ground-truth).
#
# Four posture dimensions:
#   conformance [GATING]   — sh conformance/verify.sh
#   claims      [GATING]   — sh conformance/claims-registry.sh
#   git         [ADVISORY] — branch, dirty-tree, tag alignment (WARN-only; never hard-fails alone)
#   kit-update  [ADVISORY] — is the kit you ADOPTED behind the current release? (conformance/kit-current.sh)
#
# WHY kit-update IS HERE (P1.2/T7). The kit's own recurring failure — its board calls it KW21 — is a
# capability that is built, conformance-checked, and INVISIBLE IN PRACTICE. P1.2 built an updater; an
# updater nobody is ever PROMPTED to run IS that failure. doctor is the adopter's decision point: the
# moment they are already asking "what is my posture?". So the answer to "you are three releases behind,
# and here is what it would cost to move" belongs HERE and nowhere else.
# It is ADVISORY on purpose, and both halves matter: BEING BEHIND IS NOT A DEFECT (a pinned project is a
# legitimate choice, so this can never fail a build — a gate that cried wolf on the happy path would be
# ignored within a month), and an UP-TO-DATE ADOPTER IS NEVER NAGGED (one quiet OK line).
#
# Exit policy (mirrors verify.sh):
#   exit 1  — a GATING dimension FAILs, or UNVERIFIED when --require/CI
#   exit 0  — PASS or WARN (git advisory warnings do not cause exit 1)
#
# Usage: sh scripts/doctor.sh [--require] | --selftest
# POSIX sh; dash-clean.
# What it changes: Read-only — composes conformance + claims checks into a posture report; mutates nothing.
# Guardrails: exit 1 when a GATING dimension FAILs or is UNVERIFIED under --require/CI; the git dimension is advisory (WARN-only, never hard-fails alone).
set -eu
cd "$(dirname "$0")/.."

if [ "${1:-}" = "--selftest" ]; then
  # Verify the render contract using LIGHTWEIGHT STUBS — no real conformance/
  # claims scripts are invoked. 'true' always exits 0 (PASS); 'false' always
  # exits 1 (FAIL). Both are POSIX built-ins, so the selftest is fast and
  # deterministic regardless of repo state.
  sfail=0

  # — render contract (6 required sections/labels) ——————————————————————————
  out=$(DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true sh "$0" --selftest-e2e 2>&1) || true
  printf '%s\n' "$out" | grep -q "POSTURE"             || { echo "doctor --selftest: FAIL (no POSTURE section)"; sfail=1; }
  printf '%s\n' "$out" | grep -q "conformance"         || { echo "doctor --selftest: FAIL (no conformance dimension)"; sfail=1; }
  printf '%s\n' "$out" | grep -q "claims"              || { echo "doctor --selftest: FAIL (no claims dimension)"; sfail=1; }
  printf '%s\n' "$out" | grep -qE 'git[[:space:]]+(OK|WARN)' || { echo "doctor --selftest: FAIL (no git dimension row)"; sfail=1; }
  printf '%s\n' "$out" | grep -qE 'kit-update[[:space:]]+(OK|WARN|N/A)' || { echo "doctor --selftest: FAIL (no kit-update dimension row)"; sfail=1; }
  printf '%s\n' "$out" | grep -q "Overall:"            || { echo "doctor --selftest: FAIL (no Overall verdict)"; sfail=1; }
  printf '%s\n' "$out" | grep -q "drift-self-check.md" || { echo "doctor --selftest: FAIL (no drift-self-check.md footer)"; sfail=1; }

  # — T7 SURFACING: the kit-update dimension, driven by STUBS (no network, no fixtures — the real
  #   behaviour is proven in conformance/kit-current.sh --selftest; what is proven HERE is that doctor
  #   RENDERS each of its answers, and renders them DIFFERENTLY). Each stub exits with the rc the real
  #   check would, and prints the line it would print.
  #
  #   THE STUBS ARE FILES, not `sh -c '...'` strings. DOCTOR_*_CMD is invoked UNQUOTED (deliberately — it
  #   is how `true`/`false` above work), so the shell WORD-SPLITS it and quoting inside the string is not
  #   honoured: an `sh -c 'echo "a b"; exit 1'` stub arrives shredded into words and never runs. A stub
  #   file invoked as `sh <path>` is two words, so it survives the split intact. (Found the hard way.)
  stubd=$(mktemp -d)
  mkstub() {  # <name> <rc> <first-line>
    printf '#!/bin/sh\necho "%s"\nexit %s\n' "$3" "$2" > "$stubd/$1"
  }
  mkstub behind 1 "kit-current: BEHIND — your kit-base is v1.0.0; the current release is v2.0.0."
  mkstub uptodate 0 "kit-current: OK — up to date (kit-base v2.0.0 == the current release v2.0.0)."
  mkstub na 3 "kit-current: N/A — not an adopted tree (no kit-base branch)."
  mkstub unver 2 "kit-current: UNVERIFIED — could not read a release tag from the kit source."

  #   1. BEHIND -> the adopter is TOLD, and told WHAT TO RUN. This is the whole slice. A doctor that
  #      swallowed a BEHIND would be the KW21 failure recurring inside the very fix for it.
  behind_stub="sh $stubd/behind"
  bout=$(DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true DOCTOR_KITCURRENT_CMD="$behind_stub" sh "$0" --selftest-e2e 2>&1) || true
  printf '%s\n' "$bout" | grep -qE 'kit-update[[:space:]]+WARN' || { echo "doctor --selftest: FAIL (a BEHIND kit did not surface as a kit-update WARN)"; sfail=1; }
  printf '%s\n' "$bout" | grep -q 'v1.0.0'          || { echo "doctor --selftest: FAIL (BEHIND row does not name the adopted version)"; sfail=1; }
  printf '%s\n' "$bout" | grep -q 'kit-update.sh'   || { echo "doctor --selftest: FAIL (BEHIND row does not name the command to run)"; sfail=1; }
  #   ...and it must NOT fail their build. Being behind is a choice, not a defect.
  brc=0
  DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true DOCTOR_KITCURRENT_CMD="$behind_stub" sh "$0" --selftest-e2e >/dev/null 2>&1 || brc=$?
  [ "$brc" = "0" ] || { echo "doctor --selftest: FAIL (a BEHIND kit set exit $brc — the dimension is ADVISORY and must never gate)"; sfail=1; }

  #   2. NO FALSE ALARM — equally load-bearing. An up-to-date adopter gets OK, and the word 'BEHIND'
  #      appears NOWHERE. A tool that cries wolf destroys the trust it exists to create.
  ok_stub="sh $stubd/uptodate"
  oout=$(DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true DOCTOR_KITCURRENT_CMD="$ok_stub" sh "$0" --selftest-e2e 2>&1) || true
  printf '%s\n' "$oout" | grep -qE 'kit-update[[:space:]]+OK' || { echo "doctor --selftest: FAIL (an up-to-date kit did not render OK)"; sfail=1; }
  printf '%s\n' "$oout" | grep -qi 'BEHIND' && { echo "doctor --selftest: FAIL (an up-to-date adopter was told it was BEHIND — doctor cries wolf)"; sfail=1; } || true

  #   3. N/A WITH A REASON, never a silent skip and never a false OK. rc 3 (not an adopted tree) must
  #      render N/A — and must NOT inflate the verdict (an inapplicable check is not a warning).
  na_stub="sh $stubd/na"
  nout=$(DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true DOCTOR_KITCURRENT_CMD="$na_stub" sh "$0" --selftest-e2e 2>&1) || true
  printf '%s\n' "$nout" | grep -qE 'kit-update[[:space:]]+N/A' || { echo "doctor --selftest: FAIL (rc 3 did not render an N/A row)"; sfail=1; }
  printf '%s\n' "$nout" | grep -q 'no kit-base'  || { echo "doctor --selftest: FAIL (the N/A row does not carry the check's REASON — a silent skip)"; sfail=1; }
  printf '%s\n' "$nout" | grep -qE 'kit-update[[:space:]]+OK' && { echo "doctor --selftest: FAIL (an N/A tree was rendered as OK — a false green)"; sfail=1; } || true
  #   ...and a genuine N/A must NOT nag: no WARN row, and no "go run kit-update" advice line. NB this is
  #   asserted on the ROW, deliberately, and NOT on 'Overall:' — the git dimension warns independently
  #   (dirty tree, detached HEAD in CI), so an Overall assertion would be brittle AND, worse, VACUOUS
  #   whenever git had already saturated the verdict to WARN. The row is the observable contract.
  printf '%s\n' "$nout" | grep -qE 'kit-update[[:space:]]+WARN' && { echo "doctor --selftest: FAIL (an INAPPLICABLE check raised a WARN — the wolf-crying this avoids)"; sfail=1; } || true
  printf '%s\n' "$nout" | grep -q 'see the delta' && { echo "doctor --selftest: FAIL (an N/A tree was told to run kit-update)"; sfail=1; } || true

  #   4. UNVERIFIED (offline) must NEVER read as up-to-date. It is an unknown, and it is surfaced as one.
  un_stub="sh $stubd/unver"
  uout=$(DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true DOCTOR_KITCURRENT_CMD="$un_stub" sh "$0" --selftest-e2e 2>&1) || true
  printf '%s\n' "$uout" | grep -qE 'kit-update[[:space:]]+N/A' || { echo "doctor --selftest: FAIL (UNVERIFIED did not render an N/A row)"; sfail=1; }
  printf '%s\n' "$uout" | grep -qE 'kit-update[[:space:]]+OK' && { echo "doctor --selftest: FAIL (an UNREACHABLE source rendered as OK — absence of evidence read as currency)"; sfail=1; } || true
  rm -rf "$stubd" 2>/dev/null || true

  # — exit logic: all-pass stubs → exit 0 ——————————————————————————————————
  DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true sh "$0" --selftest-e2e >/dev/null 2>&1
  _pass_rc=$?
  [ "$_pass_rc" = "0" ] || {
    echo "doctor --selftest: FAIL (all-pass stubs produced exit $_pass_rc, expected 0)"
    sfail=1
  }

  # — exit logic: verify FAIL stub → gate triggers → exit 1 ————————————————
  _fail_rc=0
  DOCTOR_VERIFY_CMD=false DOCTOR_CLAIMS_CMD=true sh "$0" --selftest-e2e >/dev/null 2>&1 || _fail_rc=$?
  [ "$_fail_rc" = "1" ] || {
    echo "doctor --selftest: FAIL (verify-fail stub produced exit $_fail_rc, expected 1)"
    sfail=1
  }

  # — T2a: --full output contains METRICS heading and non-gating label ———————
  full_out=$(DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true DOCTOR_NONVACUITY_CMD=true sh "$0" --selftest-e2e --full 2>&1) || true
  printf '%s\n' "$full_out" | grep -q "METRICS"              || { echo "doctor --selftest: FAIL (--full: no METRICS section)"; sfail=1; }
  printf '%s\n' "$full_out" | grep -q "does not affect exit" || { echo "doctor --selftest: FAIL (--full: no 'does not affect exit' label)"; sfail=1; }

  # — T2b: forced-failing metrics must NOT change the exit code —————————————
  posture_rc=0
  DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true sh "$0" --selftest-e2e >/dev/null 2>&1 || posture_rc=$?
  forced_rc=0
  DOCTOR_VERIFY_CMD=true DOCTOR_CLAIMS_CMD=true DOCTOR_DORA_CMD=false DOCTOR_SCORECARD_CMD=false DOCTOR_META_CONTROL_CMD=false DOCTOR_NONVACUITY_CMD=false sh "$0" --selftest-e2e --full >/dev/null 2>&1 || forced_rc=$?
  [ "$forced_rc" = "$posture_rc" ] || {
    echo "doctor --selftest: FAIL (non-gating invariant broken: forced-failing metrics changed exit from $posture_rc to $forced_rc)"
    sfail=1
  }

  # — FLAG-NOT-ENV: a REAL run (no seam flag) IGNORES an ambient DOCTOR_*_CMD ————————————————
  # The DOCTOR_*_CMD injection seams are honored ONLY under the internal --selftest-e2e flag that THIS
  # selftest's child invocations pass. In an adopter's real `doctor` run the ambient environment must not
  # be able to redirect a check: `DOCTOR_KITCURRENT_CMD=true doctor` would otherwise render a clean OK
  # without ever running kit-current.sh — the KW21 failure recurring inside its own fix. A check the
  # environment can redirect is not a check. Marker technique (mirrors preflight's PREFLIGHT_GIT_VERSION_CMD
  # proof): point the seam at a command that touches a marker; in a REAL run the marker must NOT appear.
  # A SINGLE real invocation (no --selftest-e2e flag) with all three ambient seams pointed at distinct
  # markers: none may appear. The invocation targets an ISOLATED COPY of this script in a bare temp tree
  # with no conformance/ siblings — a faithful real run (SEAMS=0, no seam flag) that exercises the exact
  # seam-gating path, but whose dimensions fall to their cheap "not present" branch. That isolation is
  # load-bearing: a real doctor run in THIS tree invokes conformance/verify.sh, which runs doctor-wired.sh,
  # which runs `doctor --selftest` — so a marker run against the in-tree script would recurse without end.
  # Pre-fix the seams are honored (cheap `touch` stubs run); post-fix they are ignored. Either way: fast,
  # deterministic, no recursion.
  _sd=$(mktemp -d); _rd=$(mktemp -d); mkdir -p "$_rd/scripts"; cp "$0" "$_rd/scripts/doctor.sh"
  DOCTOR_KITCURRENT_CMD="touch $_sd/kc" DOCTOR_VERIFY_CMD="touch $_sd/vf" DOCTOR_CLAIMS_CMD="touch $_sd/cl" \
    sh "$_rd/scripts/doctor.sh" >/dev/null 2>&1 || true
  [ -e "$_sd/kc" ] && { echo "doctor --selftest: FAIL (an AMBIENT DOCTOR_KITCURRENT_CMD was honored in a real run — env, not flag)"; sfail=1; } || true
  [ -e "$_sd/vf" ] && { echo "doctor --selftest: FAIL (an AMBIENT DOCTOR_VERIFY_CMD was honored in a real run — env, not flag)"; sfail=1; } || true
  [ -e "$_sd/cl" ] && { echo "doctor --selftest: FAIL (an AMBIENT DOCTOR_CLAIMS_CMD was honored in a real run — env, not flag)"; sfail=1; } || true
  rm -rf "$_sd" "$_rd" 2>/dev/null || true

  [ "$sfail" -eq 0 ] && { echo "doctor --selftest: OK"; exit 0; } || exit 1
fi

REQUIRE=0
FULL=0
SEAMS=0
[ -n "${CI:-}" ] && REQUIRE=1
for _arg in "$@"; do
  case "$_arg" in
    --require) REQUIRE=1 ;;
    --full)    FULL=1    ;;
    # --selftest-e2e: INTERNAL. Turns the DOCTOR_*_CMD injection seams live so `--selftest`'s battery can
    # feed pass/fail fixtures through the REAL body. Deliberately absent from any usage line: the flag IS
    # the authorization. Mirrors preflight.sh's --selftest-e2e / PREFLIGHT_GIT_VERSION_CMD gating.
    --selftest-e2e) SEAMS=1 ;;
  esac
done

# Variable-indirected gating + metrics commands — override in tests/selftest to inject pass/fail without
# touching the real scripts. FLAG-NOT-ENV: the seams are honored ONLY when the internal --selftest-e2e
# flag authorized them (SEAMS=1). In a real adopter run (SEAMS=0) every seam is forced empty, so the
# ambient environment cannot redirect ANY dimension — `DOCTOR_KITCURRENT_CMD=true doctor` can no longer
# fake a clean kit-update OK without running kit-current.sh. A check the environment can redirect is not a
# check (the same rule preflight's PREFLIGHT_GIT_VERSION_CMD and `incept --date` honor). The [ -f ] guard
# downstream is applied only on the default path; an overridden command is invoked directly.
if [ "$SEAMS" -eq 1 ]; then
  DOCTOR_VERIFY_CMD="${DOCTOR_VERIFY_CMD:-}"
  DOCTOR_CLAIMS_CMD="${DOCTOR_CLAIMS_CMD:-}"
  DOCTOR_DORA_CMD="${DOCTOR_DORA_CMD:-}"
  DOCTOR_SCORECARD_CMD="${DOCTOR_SCORECARD_CMD:-}"
  DOCTOR_META_CONTROL_CMD="${DOCTOR_META_CONTROL_CMD:-}"
  DOCTOR_NONVACUITY_CMD="${DOCTOR_NONVACUITY_CMD:-}"
  DOCTOR_KITCURRENT_CMD="${DOCTOR_KITCURRENT_CMD:-}"
else
  DOCTOR_VERIFY_CMD=""
  DOCTOR_CLAIMS_CMD=""
  DOCTOR_DORA_CMD=""
  DOCTOR_SCORECARD_CMD=""
  DOCTOR_META_CONTROL_CMD=""
  DOCTOR_NONVACUITY_CMD=""
  DOCTOR_KITCURRENT_CMD=""
fi

gate_fail=0
warns=0

# — HEADER ——————————————————————————————————————————————————————————————————
_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
_sha=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
_version=$(tr -d '[:space:]' < VERSION 2>/dev/null || echo "unknown")
_latest_tag=$(git tag --list 'v*' --sort=-version:refname 2>/dev/null | head -1 || echo "none")

echo "sparkwright doctor"
echo "------------------"
printf 'branch: %s  sha: %s  VERSION: %s  latest-tag: %s\n' \
  "$_branch" "$_sha" "$_version" "$_latest_tag"
echo ""

# — POSTURE ——————————————————————————————————————————————————————————————————
echo "POSTURE"
echo "-------"

# 1. conformance [GATING]
if [ -n "$DOCTOR_VERIFY_CMD" ]; then
  # overridden (selftest/test path) — invoke stub directly, no [ -f ] guard
  if _vout=$($DOCTOR_VERIFY_CMD 2>&1); then _vrc=0; else _vrc=$?; fi
  case "$_vrc" in
    0) _vstatus="PASS" ;;
    2) _vstatus="UNVERIFIED" ;;
    *) _vstatus="FAIL" ;;
  esac
  printf '  %-14s %s\n' "conformance" "$_vstatus"
  case "$_vstatus" in
    FAIL)       gate_fail=1 ;;
    UNVERIFIED) [ "$REQUIRE" = "1" ] && gate_fail=1 || true ;;
  esac
elif [ -f "conformance/verify.sh" ]; then
  _args=""
  [ "$REQUIRE" = "1" ] && _args="--require"
  # shellcheck disable=SC2086
  if _vout=$(sh conformance/verify.sh $_args 2>&1); then _vrc=0; else _vrc=$?; fi
  case "$_vrc" in
    0) _vstatus="PASS" ;;
    2) _vstatus="UNVERIFIED" ;;
    *) _vstatus="FAIL" ;;
  esac
  printf '  %-14s %s\n' "conformance" "$_vstatus"
  case "$_vstatus" in
    FAIL)       gate_fail=1 ;;
    UNVERIFIED) [ "$REQUIRE" = "1" ] && gate_fail=1 || true ;;
  esac
else
  printf '  %-14s UNVERIFIED (not present)\n' "conformance"
  warns=$((warns+1))
  [ "$REQUIRE" = "1" ] && gate_fail=1 || true
fi

# 2. claims [GATING]
if [ -n "$DOCTOR_CLAIMS_CMD" ]; then
  # overridden (selftest/test path) — invoke stub directly, no [ -f ] guard
  if _cout=$($DOCTOR_CLAIMS_CMD 2>&1); then _crc=0; else _crc=$?; fi
  case "$_crc" in
    0) _cstatus="PASS" ;;
    *) _cstatus="FAIL" ;;
  esac
  printf '  %-14s %s\n' "claims" "$_cstatus"
  [ "$_cstatus" = "FAIL" ] && gate_fail=1 || true
elif [ -f "conformance/claims-registry.sh" ]; then
  if _cout=$(sh conformance/claims-registry.sh 2>&1); then _crc=0; else _crc=$?; fi
  case "$_crc" in
    0) _cstatus="PASS" ;;
    *) _cstatus="FAIL" ;;
  esac
  printf '  %-14s %s\n' "claims" "$_cstatus"
  [ "$_cstatus" = "FAIL" ] && gate_fail=1 || true
else
  printf '  %-14s UNVERIFIED (not present)\n' "claims"
  warns=$((warns+1))
  [ "$REQUIRE" = "1" ] && gate_fail=1 || true
fi

# 3. git [ADVISORY — WARN-only; never sets gate_fail]
_git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
_git_dirty=$(git status --porcelain 2>/dev/null || true)
_git_tag_for_ver=$(git tag --list "v$_version" 2>/dev/null || true)

_git_warn=0
_git_notes=""

case "$_git_branch" in
  HEAD|detached)
    _git_notes="${_git_notes}WARN: detached HEAD; "
    _git_warn=1
    ;;
  *)
    _git_notes="${_git_notes}branch=${_git_branch}; "
    ;;
esac

if [ -n "$_git_dirty" ]; then
  _git_notes="${_git_notes}WARN: dirty working tree; "
  _git_warn=1
else
  _git_notes="${_git_notes}clean; "
fi

if [ -z "$_git_tag_for_ver" ]; then
  _git_notes="${_git_notes}WARN: v${_version} untagged/unreleased"
  _git_warn=1
else
  _git_notes="${_git_notes}tagged=v${_version}"
fi

if [ "$_git_warn" = "1" ]; then
  warns=$((warns+1))
  printf '  %-14s WARN  [%s]\n' "git" "$_git_notes"
else
  printf '  %-14s OK    [%s]\n' "git" "$_git_notes"
fi

# 4. kit-update [ADVISORY — WARN-only; never sets gate_fail]
# THE SURFACING (P1.2/T7). conformance/kit-current.sh answers one question — "is the kit you adopted
# behind the current release?" — and this is the moment the adopter is already looking.
#
# Its exit codes are DISTINCT on purpose, because the three not-BEHIND answers are NOT the same answer and
# collapsing them is how a check turns into a lie:
#   0 = CURRENT/AHEAD -> OK    (one quiet line; an up-to-date adopter is NEVER nagged)
#   1 = BEHIND        -> WARN  (the surfacing; advisory — it can never fail their build)
#   2 = UNVERIFIED    -> N/A   (offline / unreachable source: staleness UNKNOWN, and NOT assumed OK)
#   3 = N/A           -> N/A   (not an adopted tree — the kit's own repo; decided with NO network)
# N/A prints its REASON (the check's own first line). A silent skip would be indistinguishable from a
# check that quietly did nothing — which is the exact failure this dimension exists to kill.
if [ -n "$DOCTOR_KITCURRENT_CMD" ]; then
  if _kout=$($DOCTOR_KITCURRENT_CMD 2>&1); then _krc=0; else _krc=$?; fi
elif [ -f "conformance/kit-current.sh" ]; then
  if _kout=$(sh conformance/kit-current.sh 2>&1); then _krc=0; else _krc=$?; fi
else
  _kout="kit-current: N/A — conformance/kit-current.sh is not present in this tree."
  _krc=3
fi
# The check's own first line IS the note — doctor never re-states its verdict in its own words (that
# would be a second source of truth about staleness, free to drift from the check that computed it).
_knote=$(printf '%s\n' "$_kout" | sed -n '1p' | sed 's/^kit-current: *//')
#
# WHICH STATES RAISE A WARN, AND WHY THE SPLIT IS NOT PEDANTRY:
#   BEHIND (1)     -> WARN. A fact was ESTABLISHED. This is the one thing this dimension has earned the
#                    right to make noise about.
#   UNVERIFIED (2) -> N/A row + WARN. A check that COULD NOT RUN is an unknown, and doctor already treats
#                    every unknown that way. Silence here would let a permanently-unreachable source
#                    masquerade as "fine".
#   N/A (3)        -> N/A row, NO warn. It genuinely DOES NOT APPLY (the kit's own repo is not an adopter).
#                    Warning about an inapplicable check is exactly the wolf-crying this dimension is
#                    built to avoid — and it would leave the kit's own doctor permanently yellow.
case "$_krc" in
  1)
    warns=$((warns+1))
    printf '  %-14s WARN  [%s]\n' "kit-update" "$_knote"
    printf '  %-14s       -> see the delta before deciding: sh scripts/kit-update.sh --from <kit source>  (it REPORTS; it writes nothing)\n' ""
    ;;
  0) printf '  %-14s OK    [%s]\n' "kit-update" "$_knote" ;;
  2)
    warns=$((warns+1))
    printf '  %-14s N/A   [%s]\n' "kit-update" "$_knote"
    ;;
  *) printf '  %-14s N/A   [%s]\n' "kit-update" "$_knote" ;;
esac

# — VERDICT ——————————————————————————————————————————————————————————————————
echo ""
if [ "$gate_fail" = "1" ]; then
  echo "Overall: FAIL  (a gating dimension failed — fix conformance/claims before shipping)"
elif [ "$warns" != "0" ]; then
  echo "Overall: WARN  (review above — gating dimension(s) unverified or git advisory warnings present)"
else
  echo "Overall: PASS"
fi

# — FOOTER (honest ceiling) ——————————————————————————————————————————————————
echo ""
echo "Note: doctor automates the mechanizable drift axes (D claim-integrity, E git ground-truth"
echo "from docs/operations/drift-self-check.md) but does NOT detect semantic drift (intent,"
echo "scope, or overclaim) — that remains an agent/human judgment check."

# — METRICS (informational — does not affect exit) ————————————————————————————
if [ "$FULL" = "1" ]; then
  echo ""
  echo "METRICS (informational — does not affect exit)"
  echo "-----------------------------------------------"

  # dora
  if [ -n "$DOCTOR_DORA_CMD" ]; then
    # overridden (test path) — run directly, discard rc
    _dora_out=$($DOCTOR_DORA_CMD 2>&1) || true
    printf '%s\n' "$_dora_out"
  elif [ -f "scripts/dora.sh" ]; then
    _dora_out=$(sh scripts/dora.sh 2>&1) || true
    printf '%s\n' "$_dora_out"
  else
    echo "  dora:           N/A (not present)"
  fi

  # agent-scorecard
  if [ -n "$DOCTOR_SCORECARD_CMD" ]; then
    # overridden (test path) — run directly, discard rc
    _sc_out=$($DOCTOR_SCORECARD_CMD 2>&1) || true
    printf '%s\n' "$_sc_out"
  elif [ -f "scripts/agent-scorecard.sh" ]; then
    _sc_out=$(sh scripts/agent-scorecard.sh 2>&1) || true
    printf '%s\n' "$_sc_out"
  else
    echo "  agent-scorecard: N/A (not present)"
  fi

  # non-vacuity (advisory surfacing of the mutation-testing backstop; NEVER gates doctor).
  # Variable-indirected like the other metrics so the selftest stubs it (the real live sweep is
  # slow — it belongs in weekly drift-watch, not in every doctor --full / per-PR selftest run).
  if [ -n "$DOCTOR_NONVACUITY_CMD" ]; then
    _nv_out=$($DOCTOR_NONVACUITY_CMD 2>&1) || true
    printf '%s\n' "$_nv_out" | tail -1
  elif [ -f "conformance/non-vacuity.sh" ]; then
    _nv_out=$(sh conformance/non-vacuity.sh 2>&1) || true
    printf '%s\n' "$_nv_out" | tail -1
  else
    echo "  non-vacuity: N/A (not present)"
  fi

  # meta-control freshness (M2 — advisory surfacing of the cadence circuit-breaker; NEVER gates doctor)
  if [ -n "$DOCTOR_META_CONTROL_CMD" ]; then
    _mc_out=$($DOCTOR_META_CONTROL_CMD 2>&1) || true
    printf '%s\n' "$_mc_out"
  elif [ -f "conformance/meta-control-fresh.sh" ]; then
    _mc_out=$(sh conformance/meta-control-fresh.sh 2>&1) || true
    printf '%s\n' "$_mc_out"
  else
    echo "  meta-control-fresh: N/A (not present)"
  fi
fi

[ "$gate_fail" = "1" ] && exit 1 || exit 0
