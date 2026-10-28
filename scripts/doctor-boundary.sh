#!/bin/sh
# doctor-boundary.sh — `sparkwright doctor --boundary`: the agent-boundary STATIC leg (SWAS-355, slice 352c part a;
# design docs/architecture/2026-10-25-352c-doctor-boundary-design.md). One verdict composed from the two readers the kit already ships:
#   * scripts/preflight.sh --boundary-only       — the per-scope key reader (managed > local > project > user), the leg labels, the opt-out
#                                                  declaration read from ORIGIN'S DEFAULT BRANCH (never the working tree) and graded; STALE is judged here
#   * conformance/guard-wired.sh --boundary-only — the closed-schema grader of the committed and effective settings
# It parses and grades nothing itself: one parser per concern, this script only composes and decides the exit.
# What it reads: settings files (keys only; no value is printed) and one blob from origin's default branch. What it writes: NOTHING.
# What it changes: nothing. Read-only: it composes the two readers' verdicts and decides the exit; no project file, setting or ref is written (one scratch file per leg in $TMPDIR, removed).
# Guardrails: fails closed (UNDECLARED, malformed, UNTRUSTED, an unreadable declaration while a part is OFF, and grader FAIL exit 1; UNVERIFIED exits 2, or 1 under --require or CI with no TTY); no setting value is ever printed; test seams only under --selftest-e2e.
# What it does NOT prove: a static read is a declaration, not a proof of what the shell can do. The probe leg (canary reads and an off-list connect,
# run from the agent's own Bash tool) follows in v3.243 (SWAS-417); until then every line here is labelled [static] or [declared].
# Usage: sh scripts/doctor-boundary.sh [--require] [--boundary-offline] | --selftest     (reached as `sh scripts/doctor.sh --boundary`)
# Exit: 0 = judged, no UNDECLARED opt-out · 1 = an UNDECLARED opt-out, a malformed declaration, an UNTRUSTED declaration, an unreadable declaration while a part is OFF (unless --boundary-offline was typed on the command line), or a grader FAIL · 2 = UNVERIFIED (1 under --require or CI with no TTY; --boundary-offline always reads UNVERIFIED, never PASS).
# POSIX sh; dash-clean. FLAG-NOT-ENV: the DOCTOR_BOUNDARY_* seams are honoured only under --selftest-e2e.
set -eu

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REQUIRE=0; SEAMS=0; OFFLINE=0
# S25: a run is CI only when CI or GITHUB_ACTIONS is set AND no terminal is attached (decided after the arguments, where the seam flag is known). CI set WITH a TTY is
# judged as a human terminal (this script prints the WARN; m1). PREFLIGHT_TTY_SEAM=1|0 is live ONLY under --selftest-e2e; unset there it reads "no TTY". No real-run override.
# m1: the TTY is decided ONCE, here (stdin, stdout, stderr of THIS process). _db_leg redirects the child's stdout and stderr to a file, so a preflight child would decide
# again with a narrower view and, in CI mode, could PASS while a local opt-out is OFF. So when a terminal is attached the preflight leg runs under `env -u CI -u GITHUB_ACTIONS`
# (a human terminal, judged in full) and this script prints the CI+TTY WARN itself. The real [ -t ] branch is not measured by the selftest (only the seam is).
_db_tty() {
  if [ "$SEAMS" -eq 1 ]; then [ "${PREFLIGHT_TTY_SEAM:-0}" = 1 ]; return $?; fi
  [ -t 0 ] || [ -t 1 ] || [ -t 2 ]   # S32: stderr counts too
}

# _db_leg <script> <title> <flag...>: runs one reader, prints its lines under a title, leaves its exit code in _db_rc. A missing reader is UNVERIFIED (2).
_db_leg() {
  _db_s=$1; _db_title=$2; shift 2
  echo "$_db_title"
  [ -z "${_db_pre:-}" ] || printf '%s\n' "$_db_pre"
  if [ ! -f "$_db_s" ]; then echo "  UNVERIFIED: $_db_s is absent, so this leg could not be judged"; _db_rc=2; return 0; fi
  _db_t=$(mktemp 2>/dev/null) || { echo "  UNVERIFIED: no scratch file could be created"; _db_rc=2; return 0; }
  _db_rc=0
  if [ "${_db_unci:-0}" -eq 1 ]; then   # MUT-DBUNCI
    env -u CI -u GITHUB_ACTIONS sh "$_db_s" "$@" > "$_db_t" 2>&1 || _db_rc=$?
  else
    sh "$_db_s" "$@" > "$_db_t" 2>&1 || _db_rc=$?
  fi
  awk '{ if (substr($0, 1, 2) == "  ") print; else print "  " $0 }' "$_db_t"
  rm -f "$_db_t"
  case "$_db_rc" in
    0|1|2) ;;
    *) _db_rc=2 ;;   # a reader that could not run (127), was killed or gave an unknown code is UNVERIFIED, never a FAIL and never a pass
  esac
}

# run_boundary -> prints the composed block and returns the exit code (0 / 1 / 2; 2 becomes 1 under --require).
run_boundary() {
  _db_pf=$HERE/preflight.sh; _db_gw=$HERE/../conformance/guard-wired.sh
  if [ "$SEAMS" -eq 1 ]; then
    _db_pf=${DOCTOR_BOUNDARY_PF_SCRIPT:-$_db_pf}; _db_gw=${DOCTOR_BOUNDARY_GW_SCRIPT:-$_db_gw}
  fi
  echo "sparkwright doctor --boundary (static leg: settings read across scopes, the opt-out declaration read from origin's default branch; nothing is probed or written)"
  # A seam run says so (S2): the banner opens the block and the Overall line carries the words, so a seam run is never read as a report on this machine.
  _db_sf=""; _db_sn=""
  if [ "$SEAMS" -eq 1 ]; then
    _db_sf=--selftest-e2e; _db_sn=" (test seams live)"   # MUT-SEAMNOTE
    echo "NOTE: doctor-boundary test seams live — not a report on this machine"   # MUT-SEAMBANNER
  fi
  _db_of=""; [ "$OFFLINE" -eq 0 ] || _db_of=--boundary-offline
  _db_unci=0; _db_pre=""
  if _db_tty; then   # m1: one TTY decision. A terminal is attached: the preflight leg is a human terminal, whatever CI says (the WARN is printed here)
    _db_unci=1
    if [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
      _db_pre='  WARN boundary: CI is set in an interactive terminal; judged as a human terminal
  Remedy: on a CI runner that allocates a TTY, run `sh scripts/preflight.sh </dev/null 2>&1 | cat` (CI runners only; this gives CI mode, which reads only the committed project block)'
    fi
  fi
  # shellcheck disable=SC2086  # $_db_sf and $_db_of are empty or the one flag
  _db_leg "$_db_pf" "boundary lines (scripts/preflight.sh --boundary-only):" --boundary-only $_db_sf $_db_of
  _db_prc=$_db_rc
  _db_unci=0; _db_pre=""
  _db_leg "$_db_gw" "settings grade (conformance/guard-wired.sh --boundary-only):" --boundary-only .
  _db_grc=$_db_rc
  _db_out=2
  case "$_db_prc$_db_grc" in
    *1*) _db_out=1 ;;
    00) _db_out=0 ;;
    *) if [ "$REQUIRE" -eq 1 ]; then _db_out=1; fi ;;
  esac
  case "$_db_out" in
    0) echo "Overall: PASS - no UNDECLARED opt-out, no grader FAIL (static: settings were read, not proven; the probe leg follows in v3.243, SWAS-417)$_db_sn" ;;
    1) echo "Overall: FAIL - an UNDECLARED opt-out, a malformed declaration, an UNTRUSTED declaration, an unreadable declaration while a part is off (retry online, or type --boundary-offline), a grader FAIL, or (under --require or CI) a part that could not be judged is listed above$_db_sn" ;;
    *) echo "Overall: UNVERIFIED - at least one part could not be judged here (see the warn lines above); unverifiable is never a pass$_db_sn" ;;
  esac
  return "$_db_out"
}

selftest() {
  st=0
  _t=$(mktemp -d)
  _pass() { echo "doctor-boundary --selftest PASS: $1"; }
  _fail() { echo "doctor-boundary --selftest FAIL: $1"; st=1; }
  _has() {  # <label> <substring>: _o holds it
    case "$_o" in
      *"$2"*) _pass "$1 prints '$2'" ;;
      *) _fail "$1 did not print '$2' ($_o)" ;;
    esac
  }
  _no() {  # <label> <substring>: _o does not hold it
    case "$_o" in
      *"$2"*) _fail "$1 printed '$2' ($_o)" ;;
      *) _pass "$1 does not print '$2'" ;;
    esac
  }
  _rcis() {  # <label> <want>
    if [ "$_rc" -eq "$2" ]; then _pass "$1 exits $2"; else _fail "$1 exited $_rc, expected $2 ($_o)"; fi
  }
  # Fixtures. The project / local / user / managed seams and the origin seam are preflight's (honoured only under --selftest-e2e); the project dir is where guard-wired reads.
  mkdir -p "$_t/proj/.claude" "$_t/noclaim/.claude" "$_t/badgrade/.claude" "$_t/home"
  printf '{"sandbox":{"enabled":true,"filesystem":{"denyRead":["**/.env","~/.ssh"],"denyWrite":["./.claude","~/.claude/settings.json"]}},"permissions":{"deny":["WebFetch"]}}\n' > "$_t/full.json"
  printf '{"sandbox":{"enabled":false}}\n' > "$_t/off.json"
  printf '{"env":{"KIT_TRACKER_TOKEN":"kit-PLANTEDSECRET-placeholder-token"},"sandbox":{"network":{"strictAllowlist":true}}}\n' > "$_t/user-strict.json"
  printf '{"permissions":{}}\n' > "$_t/noclaim/.claude/settings.json"
  printf '{"sandbox":{"enabled":true,"filesystem":{"denyRead":["**/.env"]}}}\n' > "$_t/badgrade/.claude/settings.json"
  printf 'part=all reason=maintainers lost=an agent can read .env since=2026-10-23\n' > "$_t/d-all.conf"
  _seam="PREFLIGHT_SANDBOX_LOCAL=/nonexistent-local PREFLIGHT_SANDBOX_MANAGED=/nonexistent-managed PREFLIGHT_SANDBOX_OS=Darwin PREFLIGHT_SANDBOX_TOOLS=sandbox-exec PREFLIGHT_SANDBOX_BWRAP_OK=1"
  _ev=""
  _run() {  # <dir> <args>: the REAL script in <dir> with CI, GITHUB_ACTIONS and the session marker cleared; env words in $_ev; leaves _o and _rc
    _rc=0
    # shellcheck disable=SC2086  # $_ev is a list of NAME=value words and $2 a short flag list
    _o=$( cd "$1" && env -u CI -u GITHUB_ACTIONS -u SANDBOX_RUNTIME $_ev sh "$HERE/doctor-boundary.sh" $2 2>&1 ) || _rc=$?
  }

  # The exit composition (stub readers): any 1 -> 1; else any 2 -> 2 (1 under --require); an unknown code is UNVERIFIED, never a FAIL; 0 and 0 -> 0.
  for _c in '0 0 --selftest-e2e 0 PASS' '1 0 --selftest-e2e 1 FAIL' '0 1 --selftest-e2e 1 FAIL' '2 0 --selftest-e2e 2 UNVERIFIED' '0 2 --selftest-e2e 2 UNVERIFIED' '2 1 --selftest-e2e 1 FAIL' '127 0 --selftest-e2e 2 UNVERIFIED' '2 0 --require 1 FAIL'; do
    # shellcheck disable=SC2086  # the case list is split into words on purpose
    set -- $_c
    printf '#!/bin/sh\necho stub-reader\nexit %s\n' "$1" > "$_t/pf.sh"; printf '#!/bin/sh\necho stub-grader\nexit %s\n' "$2" > "$_t/gw.sh"
    _ev="DOCTOR_BOUNDARY_PF_SCRIPT=$_t/pf.sh DOCTOR_BOUNDARY_GW_SCRIPT=$_t/gw.sh"
    _fl=$3; [ "$3" != --require ] || _fl="--selftest-e2e --require"
    _run "$_t/proj" "$_fl"
    _rcis "compose [pf=$1 gw=$2 $3]" "$4"
    _has "compose [pf=$1 gw=$2 $3]" "Overall: $5"
    _has "compose [pf=$1 gw=$2 $3]" 'stub-reader'
    _has "compose [pf=$1 gw=$2 $3]" 'stub-grader'
  done
  # An absent reader is UNVERIFIED, not a crash and not a pass; an unknown argument is a usage error.
  _ev="DOCTOR_BOUNDARY_PF_SCRIPT=$_t/nope.sh"; _run "$_t/proj" "--selftest-e2e"
  _rcis "absent reader" 2
  _has "absent reader" 'UNVERIFIED: '
  _ev=""; _run "$_t/proj" "--bogus"
  _rcis "unknown argument" 2
  _has "unknown argument" 'usage: sh scripts/doctor-boundary.sh'

  # 30 WIRED: the real readers through the real `doctor.sh --boundary` router, so a defined-but-uncalled leg cannot pass. The fixture turns the sandbox off (nothing
  # declares it) and holds a committed settings.json that claims the boundary and fails the grader: BOTH legs must speak, and the exit is 1.
  _ev="PREFLIGHT_SANDBOX_SETTINGS=$_t/off.json PREFLIGHT_SANDBOX_USER=/nonexistent-user PREFLIGHT_BOUNDARY_OPTOUT=@absent $_seam"
  # doctor.sh runs from its own project root (cd ..), so the fixture is a small tree with copies of the four scripts and a committed settings.json that fails the grader.
  mkdir -p "$_t/tree/scripts" "$_t/tree/conformance" "$_t/tree/.claude"
  cp "$HERE/doctor.sh" "$HERE/doctor-boundary.sh" "$HERE/preflight.sh" "$_t/tree/scripts/"; cp "$HERE/../conformance/guard-wired.sh" "$_t/tree/conformance/"
  cp "$_t/badgrade/.claude/settings.json" "$_t/tree/.claude/settings.json"
  _rc=0; _o=$( cd "$_t/proj" && env -u CI -u GITHUB_ACTIONS -u SANDBOX_RUNTIME $_ev sh "$_t/tree/scripts/doctor.sh" --boundary --selftest-e2e 2>&1 ) || _rc=$?
  _rcis "wired [doctor.sh --boundary]" 1
  _has "wired [doctor.sh --boundary]" 'sparkwright doctor --boundary (static leg'
  _has "wired [preflight leg]" 'FAIL boundary: OFF and UNDECLARED [static]'
  _has "wired [grader leg]" 'FAIL: boundary: denyRead lacks'
  _has "wired [overall]" 'Overall: FAIL'
  _no "wired [overall]" 'Universal prerequisites'
  # M1 (R2): run from INSIDE scripts/ with a relative path, so a doctor.sh that forgot to cd to the project root before it routes would fail here
  _rc=0; _o=$( cd "$_t/tree/scripts" && env -u CI -u GITHUB_ACTIONS -u SANDBOX_RUNTIME $_ev sh doctor.sh --boundary --selftest-e2e 2>&1 ) || _rc=$?
  _rcis "wired [relative doctor.sh from scripts/]" 1
  _has "wired [relative doctor.sh from scripts/]" 'sparkwright doctor --boundary (static leg'
  # m4: the flag pass-through. doctor.sh --boundary --boundary-offline reaches this script and preflight (the WARN line); without the flag it does not.
  _ev="PREFLIGHT_SANDBOX_SETTINGS=$_t/off.json PREFLIGHT_SANDBOX_USER=/nonexistent-user PREFLIGHT_BOUNDARY_OPTOUT=@unreadable $_seam"
  _rc=0; _o=$( cd "$_t/proj" && env -u CI -u GITHUB_ACTIONS -u SANDBOX_RUNTIME $_ev sh "$_t/tree/scripts/doctor.sh" --boundary --boundary-offline --selftest-e2e 2>&1 ) || _rc=$?
  _has "m4 [doctor.sh --boundary --boundary-offline]" 'WARN boundary: declaration not verified (--boundary-offline typed on the command line'
  _rc=0; _o=$( cd "$_t/proj" && env -u CI -u GITHUB_ACTIONS -u SANDBOX_RUNTIME $_ev sh "$_t/tree/scripts/doctor.sh" --boundary --selftest-e2e 2>&1 ) || _rc=$?
  _no "m4 [doctor.sh --boundary without the flag]" 'declaration not verified'
  # S25 through the router: CI set WITH a TTY is not handed to the boundary leg as --require (only a TYPED --require is)
  cp "$_t/noclaim/.claude/settings.json" "$_t/tree/.claude/settings.json"
  _rc=0; _o=$( cd "$_t/proj" && env -u GITHUB_ACTIONS -u SANDBOX_RUNTIME CI=true PREFLIGHT_TTY_SEAM=1 $_ev sh "$_t/tree/scripts/doctor.sh" --boundary --boundary-offline --selftest-e2e 2>&1 ) || _rc=$?
  _rcis "s25 [doctor.sh router, CI=true + TTY + offline]" 2
  sed '/MUT-DOCREQ/s/REQUIRE_TYPED/REQUIRE/' "$_t/tree/scripts/doctor.sh" > "$_t/tree/scripts/doctor-mut.sh"
  _rc=0; _o=$( cd "$_t/proj" && env -u GITHUB_ACTIONS -u SANDBOX_RUNTIME CI=true PREFLIGHT_TTY_SEAM=1 $_ev sh "$_t/tree/scripts/doctor-mut.sh" --boundary --boundary-offline --selftest-e2e 2>&1 ) || _rc=$?
  if [ "$_rc" -eq 2 ]; then _fail "mutant router-hands-CI-as-require survived (still exits 2)"; else _pass "mutant router-hands-CI-as-require is killed (exit $_rc)"; fi
  rm -f "$_t/tree/scripts/doctor-mut.sh"
  _ev="PREFLIGHT_SANDBOX_SETTINGS=$_t/full.json PREFLIGHT_SANDBOX_USER=$_t/user-strict.json PREFLIGHT_BOUNDARY_OPTOUT=@absent $_seam"; _run "$_t/noclaim" "--selftest-e2e"
  _rcis "all part ON, grader N/A" 0
  _has "all part ON, grader N/A" 'ok   boundary: ON [static]'
  _has "all part ON, grader N/A" 'N/A: boundary default'
  _has "all part ON, grader N/A" 'Overall: PASS'
  _no "token never printed (DC7)" 'PLANTEDSECRET'
  # DC6: a declared opt-out is loud and does not fail the doctor leg; its unreadable declaration is UNVERIFIED (2), and 1 under --require.
  _ev="PREFLIGHT_SANDBOX_SETTINGS=$_t/off.json PREFLIGHT_SANDBOX_USER=/nonexistent-user PREFLIGHT_BOUNDARY_OPTOUT=$_t/d-all.conf $_seam"; _run "$_t/noclaim" "--selftest-e2e"
  _rcis "declared opt-out" 0
  _has "declared opt-out" 'WARN boundary: OFF [static] (opted out 2026-10-23, declared in .kit/boundary-optout.conf)'
  _ev="PREFLIGHT_SANDBOX_SETTINGS=$_t/off.json PREFLIGHT_SANDBOX_USER=/nonexistent-user PREFLIGHT_BOUNDARY_OPTOUT=@unreadable $_seam"; _run "$_t/noclaim" "--selftest-e2e"
  _rcis "unreadable declaration while a part is OFF" 1   # S20 ("355a: B revised"): gates from a terminal
  _has "unreadable declaration while a part is OFF" 'Overall: FAIL'
  _has "unreadable declaration while a part is OFF" 'type --boundary-offline'
  _run "$_t/noclaim" "--selftest-e2e --boundary-offline"
  _rcis "unreadable declaration with --boundary-offline" 2   # S26: offline reads UNVERIFIED (never PASS); a plain preflight still exits 0
  _has "unreadable declaration with --boundary-offline" 'WARN boundary: declaration not verified (--boundary-offline typed on the command line; anyone can pass it: a visible act, not a control; the gate is not judged this run)'
  _has "unreadable declaration with --boundary-offline" 'Overall: UNVERIFIED'
  _no "unreadable declaration with --boundary-offline" 'Overall: PASS'
  _run "$_t/noclaim" "--selftest-e2e --require"
  _rcis "unreadable declaration under --require" 1
  _run "$_t/noclaim" "--selftest-e2e --require --boundary-offline"
  _rcis "unreadable declaration under --require --boundary-offline" 1
  _has "unreadable declaration under --require --boundary-offline" 'Overall: FAIL'
  # S25: CI or GITHUB_ACTIONS set is CI only with NO TTY. The TTY comes through PREFLIGHT_TTY_SEAM (live only under --selftest-e2e; unset there it reads "no TTY").
  _runci() {  # <dir> <args>: like _run, with CI=true set; env words in $_ev
    _rc=0
    # shellcheck disable=SC2086  # $_ev is a list of NAME=value words and $2 a short flag list
    _o=$( cd "$1" && env -u GITHUB_ACTIONS -u SANDBOX_RUNTIME CI=true $_ev sh "$HERE/doctor-boundary.sh" $2 2>&1 ) || _rc=$?
  }
  _s25w='WARN boundary: CI is set in an interactive terminal; judged as a human terminal'
  _ev="HOME=$_t/home PREFLIGHT_TTY_SEAM=1 PREFLIGHT_SANDBOX_SETTINGS=$_t/full.json PREFLIGHT_SANDBOX_USER=$_t/user-strict.json PREFLIGHT_BOUNDARY_OPTOUT=@unreadable $_seam"; _runci "$_t/noclaim" "--selftest-e2e"
  _rcis "s25 [CI=true + TTY, fully ON]" 0
  _has "s25 [CI=true + TTY, fully ON]" "$_s25w"
  _has "s25 [CI=true + TTY, fully ON]" 'ok   boundary: ON [static]'
  _no "s25 [CI=true + TTY, fully ON]" '[declared]'
  _ev="HOME=$_t/home PREFLIGHT_TTY_SEAM=1 PREFLIGHT_SANDBOX_SETTINGS=$_t/off.json PREFLIGHT_SANDBOX_USER=/nonexistent-user PREFLIGHT_BOUNDARY_OPTOUT=@unreadable $_seam"; _runci "$_t/noclaim" "--selftest-e2e"
  _rcis "s25 [CI=true + TTY, opted out, declaration unreadable]" 1
  _has "s25 [CI=true + TTY, opted out, declaration unreadable]" "$_s25w"
  _has "s25 [CI=true + TTY, opted out, declaration unreadable]" 'FAIL boundary: declaration UNVERIFIED'
  _ev="HOME=$_t/home PREFLIGHT_TTY_SEAM=0 PREFLIGHT_SANDBOX_SETTINGS=$_t/off.json PREFLIGHT_SANDBOX_USER=/nonexistent-user PREFLIGHT_BOUNDARY_OPTOUT=@unreadable $_seam"; _runci "$_t/noclaim" "--selftest-e2e"
  _rcis "s25 [CI=true, no TTY: the CI behaviour]" 1
  _has "s25 [CI=true, no TTY: the CI behaviour]" 'the declaration is not read in CI'
  _no "s25 [CI=true, no TTY: the CI behaviour]" "$_s25w"
  # CI + TTY + --boundary-offline reads UNVERIFIED (2): a human terminal does not take --require from CI.
  _ev="HOME=$_t/home PREFLIGHT_TTY_SEAM=1 PREFLIGHT_SANDBOX_SETTINGS=$_t/off.json PREFLIGHT_SANDBOX_USER=/nonexistent-user PREFLIGHT_BOUNDARY_OPTOUT=@unreadable $_seam"; _runci "$_t/noclaim" "--selftest-e2e --boundary-offline"
  _rcis "s25 [CI=true + TTY + offline: no --require from CI]" 2
  _has "s25 [CI=true + TTY + offline: no --require from CI]" 'Overall: UNVERIFIED'
  # m1: the TTY is decided once. With a terminal attached the preflight leg runs WITHOUT CI / GITHUB_ACTIONS (a stub reader prints what it sees); with none it sees CI.
  printf '#!/bin/sh\necho "stub-pf-sees-ci=${CI:-unset}${GITHUB_ACTIONS:-}"\nexit 0\n' > "$_t/pfenv.sh"; printf '#!/bin/sh\necho stub-grader\nexit 0\n' > "$_t/gw.sh"
  _ev="PREFLIGHT_TTY_SEAM=1 DOCTOR_BOUNDARY_PF_SCRIPT=$_t/pfenv.sh DOCTOR_BOUNDARY_GW_SCRIPT=$_t/gw.sh"; _runci "$_t/noclaim" "--selftest-e2e"
  _has "m1 [CI=true + TTY: preflight leg runs without CI]" 'stub-pf-sees-ci=unset'
  _has "m1 [CI=true + TTY: preflight leg runs without CI]" "$_s25w"
  _has "m1 [CI=true + TTY: preflight leg runs without CI]" '`sh scripts/preflight.sh </dev/null 2>&1 | cat`'
  _ev="PREFLIGHT_TTY_SEAM=0 DOCTOR_BOUNDARY_PF_SCRIPT=$_t/pfenv.sh DOCTOR_BOUNDARY_GW_SCRIPT=$_t/gw.sh"; _runci "$_t/noclaim" "--selftest-e2e"
  _has "m1 [CI=true, no TTY: preflight leg sees CI]" 'stub-pf-sees-ci=true'
  _no "m1 [CI=true, no TTY: preflight leg sees CI]" "$_s25w"
  _mm=$(mktemp -d); sed '/MUT-DBUNCI/s/-eq 1/-eq 99/' "$HERE/doctor-boundary.sh" > "$_mm/doctor-boundary.sh"
  if cmp -s "$HERE/doctor-boundary.sh" "$_mm/doctor-boundary.sh"; then _fail "mutant tty-leg-keeps-ci did not apply"
  elif ! sh -n "$_mm/doctor-boundary.sh" 2>/dev/null; then _fail "mutant tty-leg-keeps-ci does not parse"
  else
    _ev="PREFLIGHT_TTY_SEAM=1 DOCTOR_BOUNDARY_PF_SCRIPT=$_t/pfenv.sh DOCTOR_BOUNDARY_GW_SCRIPT=$_t/gw.sh"; _rc=0
    # shellcheck disable=SC2086  # $_ev is a list of NAME=value words
    _o=$( cd "$_t/noclaim" && env -u GITHUB_ACTIONS -u SANDBOX_RUNTIME CI=true $_ev sh "$_mm/doctor-boundary.sh" --selftest-e2e 2>&1 ) || _rc=$?
    case "$_o" in
      *'stub-pf-sees-ci=unset'*) _fail "mutant tty-leg-keeps-ci survived (the preflight leg still ran without CI)" ;;
      *) _pass "mutant tty-leg-keeps-ci is killed" ;;
    esac
  fi
  rm -rf "$_mm"
  # CI=true with an EMPTY HOME: the declared tier, the run reaches its end, nothing is read from the home (the exit is the declared tier's, 1 under CI's --require for an OFF part).
  _ev="HOME=$_t/home CI=true PREFLIGHT_SANDBOX_SETTINGS=$_t/full.json PREFLIGHT_SANDBOX_USER=/nonexistent-user PREFLIGHT_BOUNDARY_OPTOUT=@unreadable $_seam"
  _rc=0; _o=$( cd "$_t/noclaim" && env -u GITHUB_ACTIONS -u SANDBOX_RUNTIME $_ev sh "$HERE/doctor-boundary.sh" --selftest-e2e 2>&1 ) || _rc=$?
  _rcis "CI=true, empty HOME, ON" 0
  _has "CI=true, empty HOME, ON" 'ok   boundary: ON [declared] (CI set: local and user scopes not read)'
  _has "CI=true, empty HOME, ON" 'egress: N/A [declared]'
  _ev="HOME=$_t/home CI=true PREFLIGHT_SANDBOX_SETTINGS=$_t/off.json PREFLIGHT_SANDBOX_USER=/nonexistent-user PREFLIGHT_BOUNDARY_OPTOUT=$_t/d-all.conf $_seam"
  _rc=0; _o=$( cd "$_t/noclaim" && env -u GITHUB_ACTIONS -u SANDBOX_RUNTIME $_ev sh "$HERE/doctor-boundary.sh" --selftest-e2e 2>&1 ) || _rc=$?
  _rcis "CI=true, empty HOME, OFF" 1
  _has "CI=true, empty HOME, OFF" 'the declaration is not read in CI'
  _no "CI=true, empty HOME, OFF" 'opted out'
  # A jq that prints a partial result and then fails: every leg reads UNVERIFIED (2), never ON, never a pass, never an abort.
  _js=$(mktemp -d); printf '%s\n' '#!/bin/sh' 'echo "{\"e\":"' 'exit 2' > "$_js/jq"; chmod +x "$_js/jq"
  _ev="PREFLIGHT_SANDBOX_SETTINGS=$_t/full.json PREFLIGHT_SANDBOX_USER=$_t/user-strict.json PREFLIGHT_BOUNDARY_OPTOUT=@absent $_seam"
  _rc=0
  # shellcheck disable=SC2086  # $_ev is a list of NAME=value words; PATH is exported, never word-split into env (an entry may hold a space)
  _o=$( PATH="$_js:$PATH"; export PATH; cd "$_t/badgrade" && env -u CI -u GITHUB_ACTIONS -u SANDBOX_RUNTIME $_ev sh "$HERE/doctor-boundary.sh" --selftest-e2e 2>&1 ) || _rc=$?
  _rcis "failing jq" 2
  _has "failing jq" 'UNVERIFIED'
  _no "failing jq" 'boundary: ON'
  _has "failing jq" 'Overall: UNVERIFIED'
  rm -rf "$_js"
  # WRITES NOTHING: the project tree and the home are byte-identical before and after a run.
  _before=$(cd "$_t" && find . -type f -exec cksum {} + 2>/dev/null | sort | cksum)
  _ev="PREFLIGHT_SANDBOX_SETTINGS=$_t/off.json PREFLIGHT_SANDBOX_USER=/nonexistent-user PREFLIGHT_BOUNDARY_OPTOUT=@absent $_seam"; _run "$_t/badgrade" "--selftest-e2e"
  _after=$(cd "$_t" && find . -type f -exec cksum {} + 2>/dev/null | sort | cksum)
  if [ "$_before" = "$_after" ]; then _pass "writes nothing"; else _fail "a run changed files under the fixture tree"; fi
  # Mutants: a sed mutation of a COPY must turn the wired cell red (the readers must be CALLED, and their codes must decide the exit).
  _mut() {  # <name> <sed expr> <want substring the ORIGINAL prints> : the mutated copy, beside the real readers, must not print it
    _mm=$(mktemp -d); mkdir -p "$_mm/scripts" "$_mm/conformance"
    sed "$2" "$HERE/doctor-boundary.sh" > "$_mm/scripts/doctor-boundary.sh"
    cp "$HERE/preflight.sh" "$_mm/scripts/preflight.sh"; cp "$HERE/../conformance/guard-wired.sh" "$_mm/conformance/guard-wired.sh"
    if cmp -s "$HERE/doctor-boundary.sh" "$_mm/scripts/doctor-boundary.sh"; then _fail "mutant $1 did not apply (the sed expression matched nothing)"; rm -rf "$_mm"; return 0; fi
    if ! sh -n "$_mm/scripts/doctor-boundary.sh" 2>/dev/null; then _fail "mutant $1 does not parse (a mutant that cannot run would read as killed)"; rm -rf "$_mm"; return 0; fi
    _ev="PREFLIGHT_SANDBOX_SETTINGS=$_t/off.json PREFLIGHT_SANDBOX_USER=/nonexistent-user PREFLIGHT_BOUNDARY_OPTOUT=@absent $_seam"
    _rc=0; _o=$( cd "$_t/badgrade" && env -u CI -u GITHUB_ACTIONS -u SANDBOX_RUNTIME $_ev sh "$_mm/scripts/doctor-boundary.sh" --selftest-e2e 2>&1 ) || _rc=$?
    case "$_o" in
      *"$3"*) _fail "mutant $1 survived (it still prints '$3')" ;;
      *) _pass "mutant $1 is killed" ;;
    esac
    rm -rf "$_mm"
  }
  # S2: a seam run opens with the NOTE and its Overall line says so; a mutant that drops either is killed.
  _ev="PREFLIGHT_SANDBOX_SETTINGS=$_t/full.json PREFLIGHT_SANDBOX_USER=$_t/user-strict.json PREFLIGHT_BOUNDARY_OPTOUT=@absent $_seam"; _run "$_t/noclaim" "--selftest-e2e"
  _has "seam run [banner]" 'NOTE: doctor-boundary test seams live — not a report on this machine'
  _has "seam run [overall]" 'Overall: PASS'
  _has "seam run [overall]" '(test seams live)'
  _mut seam-banner-dropped '/MUT-SEAMBANNER/d' 'NOTE: doctor-boundary test seams live'
  _mut seam-overall-note-dropped '/MUT-SEAMNOTE/s/" (test seams live)"/""/' '(test seams live)'
  _mut grader-leg-uncalled 's/^  _db_leg "\$_db_gw" .*$/  _db_rc=0/' 'FAIL: boundary:'
  _mut preflight-leg-uncalled 's/^  _db_leg "\$_db_pf" .*$/  _db_rc=0/' 'OFF and UNDECLARED'
  _mut exit-ignores-readers 's/\*1\*) _db_out=1 ;;/*1*) _db_out=0 ;;/' 'Overall: FAIL'
  # S25 mutant: CI + TTY takes --require from CI (the TTY is ignored). The CI + TTY + offline run must then read FAIL, not UNVERIFIED.
  _mm=$(mktemp -d); mkdir -p "$_mm/scripts" "$_mm/conformance"
  sed '/MUT-DBCITTY/s/&& ! _db_tty; then/\&\& true; then/' "$HERE/doctor-boundary.sh" > "$_mm/scripts/doctor-boundary.sh"
  cp "$HERE/preflight.sh" "$_mm/scripts/preflight.sh"; cp "$HERE/../conformance/guard-wired.sh" "$_mm/conformance/guard-wired.sh"
  if cmp -s "$HERE/doctor-boundary.sh" "$_mm/scripts/doctor-boundary.sh"; then _fail "mutant ci-tty-ignored did not apply"
  elif ! sh -n "$_mm/scripts/doctor-boundary.sh" 2>/dev/null; then _fail "mutant ci-tty-ignored does not parse"
  else
    _ev="HOME=$_t/home PREFLIGHT_TTY_SEAM=1 PREFLIGHT_SANDBOX_SETTINGS=$_t/off.json PREFLIGHT_SANDBOX_USER=/nonexistent-user PREFLIGHT_BOUNDARY_OPTOUT=@unreadable $_seam"
    _rc=0
    # shellcheck disable=SC2086  # $_ev is a list of NAME=value words
    _o=$( cd "$_t/noclaim" && env -u GITHUB_ACTIONS -u SANDBOX_RUNTIME CI=true $_ev sh "$_mm/scripts/doctor-boundary.sh" --selftest-e2e --boundary-offline 2>&1 ) || _rc=$?
    case "$_o" in
      *'Overall: UNVERIFIED'*) _fail "mutant ci-tty-ignored survived (it still reads UNVERIFIED)" ;;
      *) _pass "mutant ci-tty-ignored is killed" ;;
    esac
  fi
  rm -rf "$_mm"
  rm -rf "$_t"
  [ "$st" -eq 0 ] && { echo "doctor-boundary --selftest: OK"; return 0; }
  echo "doctor-boundary --selftest: FAIL"; return 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --require) REQUIRE=1 ;;
    --boundary-offline) OFFLINE=1 ;;   # typed on the command line (anyone can pass it: a visible act, not a control), passed to preflight; never read from the environment
    --selftest) selftest; exit $? ;;
    # --selftest-e2e: INTERNAL. Turns the DOCTOR_BOUNDARY_* seams live and passes the same flag on to preflight (the flag IS the authorization).
    --selftest-e2e) SEAMS=1 ;;
    *) echo "usage: sh scripts/doctor-boundary.sh [--require] [--boundary-offline] | --selftest" >&2; exit 2 ;;
  esac
  shift
done
if { [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; } && ! _db_tty; then REQUIRE=1; fi   # MUT-DBCITTY
if run_boundary; then exit 0; else exit $?; fi
