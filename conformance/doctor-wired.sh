#!/bin/sh
# doctor-wired.sh — regression-lock: scripts/doctor.sh + scripts/sparkwright exist,
# doctor --selftest exits 0, the dispatcher routes 'sparkwright doctor --selftest',
# and 'sparkwright bogus' exits 2 (rejects unknown commands).
# Paths are overridable via KIT_DOCTOR_DIR (default: scripts) so --selftest can
# point at a fixture directory — mirrors how other checks parameterize their targets.
#   sh conformance/doctor-wired.sh [--selftest]
# Exit: 0 = contract holds · 1 = a regression · 2 = usage. POSIX sh; dash-clean.
set -eu

KIT_DOCTOR_DIR="${KIT_DOCTOR_DIR:-scripts}"

# check_wired <dir>: assert doctor.sh + sparkwright exist, selftests pass, dispatcher
# rejects unknown commands. Prints PASS/FAIL per assertion; returns 1 on any failure.
check_wired() {
  _dir=$1
  _fail=0

  # 1. files exist
  if [ -f "$_dir/doctor.sh" ]; then
    echo "PASS: $_dir/doctor.sh exists"
  else
    echo "FAIL: $_dir/doctor.sh missing"; _fail=1
  fi

  if [ -f "$_dir/sparkwright" ]; then
    echo "PASS: $_dir/sparkwright exists"
  else
    echo "FAIL: $_dir/sparkwright missing"; _fail=1
  fi

  # bail early — cannot run selftests without the files
  [ "$_fail" = "0" ] || return 1

  # 2. doctor --selftest exits 0
  if sh "$_dir/doctor.sh" --selftest >/dev/null 2>&1; then
    echo "PASS: sh $_dir/doctor.sh --selftest exits 0"
  else
    echo "FAIL: sh $_dir/doctor.sh --selftest returned non-zero"; _fail=1
  fi

  # 3. sparkwright doctor --selftest exits 0 (dispatcher routes correctly)
  if sh "$_dir/sparkwright" doctor --selftest >/dev/null 2>&1; then
    echo "PASS: sh $_dir/sparkwright doctor --selftest exits 0 (dispatcher routes)"
  else
    echo "FAIL: sh $_dir/sparkwright doctor --selftest returned non-zero (dispatcher broken)"; _fail=1
  fi

  # 4. sparkwright bogus exits 2 (rejects unknown commands)
  _bogus_rc=0
  sh "$_dir/sparkwright" bogus >/dev/null 2>&1 || _bogus_rc=$?
  if [ "$_bogus_rc" = "2" ]; then
    echo "PASS: sh $_dir/sparkwright bogus exits 2 (unknown command rejected)"
  else
    echo "FAIL: sh $_dir/sparkwright bogus exited $_bogus_rc (expected 2)"; _fail=1
  fi

  return $_fail
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  tmp=$(mktemp -d)

  # --- FIXTURE A: "gap" tree — dispatcher does NOT route 'doctor' ---
  # sparkwright exists but routes to exit 1 for everything (broken dispatcher)
  mkdir -p "$tmp/gap"
  printf '#!/bin/sh\necho "stub doctor.sh"\nsh conformance/verify.sh 2>/dev/null || true\necho "POSTURE"\necho "  conformance   PASS"\necho "  claims        PASS"\necho "  git OK [branch=test; clean; tagged=v0.0.0]"\necho ""\necho "Overall: PASS"\necho "drift-self-check.md"\n' > "$tmp/gap/doctor.sh"
  chmod +x "$tmp/gap/doctor.sh"
  # broken dispatcher — does not route 'doctor', exits 1 for all
  printf '#!/bin/sh\necho "broken dispatcher" >&2; exit 1\n' > "$tmp/gap/sparkwright"
  chmod +x "$tmp/gap/sparkwright"

  # The gap fixture must FAIL (dispatcher broken)
  if KIT_DOCTOR_DIR="$tmp/gap" sh "$0" >/dev/null 2>&1; then
    echo "FAIL: selftest — gap fixture (broken dispatcher) wrongly passed"; sfail=1
  else
    echo "PASS: selftest — gap fixture correctly detected (broken dispatcher)"
  fi

  # --- FIXTURE B: "complete" tree — real doctor.sh + correct sparkwright ---
  mkdir -p "$tmp/ok"
  # Minimal doctor.sh that passes its own --selftest: output required sections + handle --selftest
  cat > "$tmp/ok/doctor.sh" <<'DOCTOR_EOF'
#!/bin/sh
set -eu
if [ "${1:-}" = "--selftest" ]; then
  out=$(sh "$0" 2>&1) || true
  sfail=0
  printf '%s\n' "$out" | grep -q "POSTURE"              || { echo "FAIL (no POSTURE)"; sfail=1; }
  printf '%s\n' "$out" | grep -q "conformance"          || { echo "FAIL (no conformance)"; sfail=1; }
  printf '%s\n' "$out" | grep -q "claims"               || { echo "FAIL (no claims)"; sfail=1; }
  printf '%s\n' "$out" | grep -qE 'git[[:space:]]+(OK|WARN)' || { echo "FAIL (no git row)"; sfail=1; }
  printf '%s\n' "$out" | grep -q "Overall:"             || { echo "FAIL (no Overall)"; sfail=1; }
  printf '%s\n' "$out" | grep -q "drift-self-check.md"  || { echo "FAIL (no footer)"; sfail=1; }
  [ "$sfail" -eq 0 ] && { echo "doctor --selftest: OK"; exit 0; } || exit 1
fi
echo "sparkwright doctor"
echo "------------------"
printf 'branch: main  sha: abc1234  VERSION: 0.0.0  latest-tag: v0.0.0\n'
echo ""
echo "POSTURE"
echo "-------"
printf '  %-14s %s\n' "conformance" "PASS"
printf '  %-14s %s\n' "claims" "PASS"
printf '  %-14s OK    [%s]\n' "git" "branch=main; clean; tagged=v0.0.0"
echo ""
echo "Overall: PASS"
echo ""
echo "Note: doctor automates the mechanizable drift axes (D claim-integrity, E git ground-truth"
echo "from docs/operations/drift-self-check.md) but does NOT detect semantic drift."
exit 0
DOCTOR_EOF
  chmod +x "$tmp/ok/doctor.sh"

  # Correct dispatcher — routes 'doctor', exits 2 for unknown
  cat > "$tmp/ok/sparkwright" <<'SW_EOF'
#!/bin/sh
set -eu
here=$(dirname "$0")
case "${1:-}" in
  doctor) shift; exec sh "$here/doctor.sh" "$@" ;;
  ""|-h|--help) echo "usage: sparkwright <command>; commands: doctor" >&2; exit 2 ;;
  *) echo "sparkwright: unknown command '$1'; commands: doctor" >&2; exit 2 ;;
esac
SW_EOF
  chmod +x "$tmp/ok/sparkwright"

  # The complete fixture must PASS
  if KIT_DOCTOR_DIR="$tmp/ok" sh "$0" >/dev/null 2>&1; then
    echo "PASS: selftest — complete fixture correctly passed"
  else
    echo "FAIL: selftest — complete fixture wrongly failed"; sfail=1
  fi

  # --- FIXTURE C: "missing" tree — files absent ---
  mkdir -p "$tmp/empty"
  if KIT_DOCTOR_DIR="$tmp/empty" sh "$0" >/dev/null 2>&1; then
    echo "FAIL: selftest — missing-files fixture wrongly passed"; sfail=1
  else
    echo "PASS: selftest — missing-files fixture correctly detected"
  fi

  [ "$sfail" -eq 0 ] && { echo "OK: doctor-wired selftest"; exit 0; } || { echo "FAIL: doctor-wired selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: doctor-wired.sh [--selftest]" >&2; exit 2 ;;
esac

echo "Doctor wiring check (dir: $KIT_DOCTOR_DIR):"
if check_wired "$KIT_DOCTOR_DIR"; then
  echo "OK: doctor posture command is wired (dispatcher routes it; --selftest green)"
  exit 0
else
  echo "FAIL: doctor wiring regression (see above)"
  exit 1
fi
