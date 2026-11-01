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
  _rc=0; _o=$(PREFLIGHT_GH_CMD='printf {"isPrivate":true,"isInOrganization":false}' sh "$PF" --selftest 2>&1) || _rc=$?
  printf '%s\n' "$_o" | grep -q 'repo-class warn leaves miss untouched' || { echo "FAIL: repo-class WARN-only invariant not asserted by preflight selftest"; rc=1; }
  printf '%s\n' "$_o" | grep -q 'codeowners warn leaves miss untouched'  || { echo "FAIL: codeowners WARN-only invariant not asserted"; rc=1; }
  printf '%s\n' "$_o" | grep -q 'workflow warn leaves miss untouched'    || { echo "FAIL: workflow WARN-only invariant not asserted"; rc=1; }
  # a red run must never read green through ANY output: it needs exit 0 AND the whole line (a FAIL message that merely quotes the text does not count)
  if [ "$_rc" -ne 0 ] || ! printf '%s\n' "$_o" | grep -qx 'OK: preflight selftest'; then echo "FAIL: preflight selftest did not pass (exit $_rc; the exit must be 0 and the whole line 'OK: preflight selftest' present)"; rc=1; fi

  [ "$rc" -eq 0 ] && echo "PASS: adopter-preflight section wired + advisory"
  return $rc
}

stub_cells() {  # drives run() through the PF seam with stub preflights in $_tmp; sets _cs_fail (0 = every cell held)
  _cs_fail=0
  _stub() {  # <label> <stub's exit code> <stub's last output line> <pass|fail: what the lock must say>
    { printf '%s\n' '# Adopter environment check_repo_class check_codeowners_placeholders check_workflows_valid' '# if is_github_repo; then'
      printf '%s\n' 'echo "PASS: repo-class warn leaves miss untouched"; echo "PASS: codeowners warn leaves miss untouched"; echo "PASS: workflow warn leaves miss untouched"'
      printf 'echo "%s"\nexit %s\n' "$3" "$2"; } > "$_tmp/stub.sh"
    PF="$_tmp/stub.sh"; _sr=0; _so=$(run 2>&1) || _sr=$?; PF="$_saved_pf"
    case "$4:$_sr" in
      pass:0) ;;
      fail:0) echo "adopter-preflight-wired --selftest: FAIL (cell $1: the lock passed a run it must refuse)"; _cs_fail=1 ;;
      pass:*) echo "adopter-preflight-wired --selftest: FAIL (cell $1: the lock refused a green run: $_so)"; _cs_fail=1 ;;
      *) printf '%s\n' "$_so" | grep -q 'preflight selftest did not pass' || { echo "adopter-preflight-wired --selftest: FAIL (cell $1: refused for the wrong reason: $_so)"; _cs_fail=1; } ;;
    esac
  }
  _stub green 0 'OK: preflight selftest' pass
  _stub contains-only 0 'FAIL: a cell quoting OK: preflight selftest in its message' fail   # exit 0 and the substring, but never the whole line
  _stub nonzero-rc 1 'OK: preflight selftest' fail                                          # the whole line, but a non-zero exit
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
  # SWAS-487: the verdict needs BOTH preflight's exit 0 AND the whole line `OK: preflight selftest`; a red run must never read green through its output. Stub cells + a mutant each.
  stub_cells; sfail=$((sfail + _cs_fail))
  # The stub cells are reached ONLY through a throwaway COPY whose final `run` line is rewritten into the stub entry: the shipped script has no flag or variable that skips its real leg.
  mut_run() {  # <sed expr> -> _mt = noapply | noparse | survived | killed (a copy so mutated runs the stub cells; killed = they fail)
    mkdir -p "$_tmp/conformance"; sed "$1" "$0" > "$_tmp/conformance/mut0.sh"
    if cmp -s "$0" "$_tmp/conformance/mut0.sh"; then _mt=noapply; return 0; fi
    sed '$s/^run$/_tmp=$(mktemp -d); _saved_pf=$PF; stub_cells; rm -rf "$_tmp"; exit "$_cs_fail"/' "$_tmp/conformance/mut0.sh" > "$_tmp/conformance/mut.sh"
    if ! sh -n "$_tmp/conformance/mut.sh" 2>/dev/null; then _mt=noparse; return 0; fi
    if sh "$_tmp/conformance/mut.sh" >/dev/null 2>&1; then _mt=survived; else _mt=killed; fi
  }
  mut_try() {  # <name> <sed expr over the verdict line>: the mutant must be killed; one that did not apply or does not parse is a FAIL, never a kill
    mut_run "$2"; [ "$_mt" = killed ] || { echo "adopter-preflight-wired --selftest: FAIL (mutant $1: $_mt)"; sfail=1; }
  }
  mut_try anchor-dropped '/^  if \[ "\$_rc"/s/grep -qx/grep -q/'
  mut_try rc-ignored '/^  if \[ "\$_rc"/s/\[ "\$_rc" -ne 0 \] || //'
  mut_run '$s/^run$/if/'; [ "$_mt" = noparse ] || { echo "adopter-preflight-wired --selftest: FAIL (an unparseable mutant read as $_mt, not noparse)"; sfail=1; }
  # no argv skips the real leg: an unknown argument (the retired internal --stub-cells included) is a usage error (rc 2), never ignored; a mutant that re-adds the branch must red this
  _ur=0; sh "$0" --stub-cells >/dev/null 2>&1 || _ur=$?
  [ "$_ur" -eq 2 ] || { echo "adopter-preflight-wired --selftest: FAIL (--stub-cells was not rejected: exit $_ur)"; sfail=1; }
  mkdir -p "$_tmp/conformance"; sed 's/^\[ \$# -eq 0 \] || /[ "${1:-}" = --stub-cells ] || [ $# -eq 0 ] || /' "$0" > "$_tmp/conformance/mut.sh"
  if cmp -s "$0" "$_tmp/conformance/mut.sh"; then echo "adopter-preflight-wired --selftest: FAIL (mutant stub-flag-readded did not apply)"; sfail=1
  else _ur=0; sh "$_tmp/conformance/mut.sh" --stub-cells >/dev/null 2>&1 || _ur=$?
    [ "$_ur" -ne 2 ] || { echo "adopter-preflight-wired --selftest: FAIL (mutant stub-flag-readded survived)"; sfail=1; }
  fi
  rm -rf "$_tmp"
  [ "$sfail" -eq 0 ] && { echo "adopter-preflight-wired --selftest: OK"; exit 0; } || exit 1
fi
[ $# -eq 0 ] || { echo "usage: adopter-preflight-wired.sh [--selftest]" >&2; exit 2; }   # no other argument: nothing may skip the real leg

run
