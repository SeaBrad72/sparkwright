#!/bin/sh
# operate-loop-wired.sh — regression-lock: scripts/postmortem.sh exists AND
# sh scripts/postmortem.sh --selftest exits 0 AND
# sh scripts/sparkwright postmortem --selftest routes correctly (exits 0).
# Paths are overridable via KIT_OLOOP_DIR (default: scripts) so --selftest can
# point at a fixture directory — mirrors how doctor-wired parameterises targets.
#   sh conformance/operate-loop-wired.sh [--selftest]
# Exit: 0 = contract holds · 1 = a regression · 2 = usage. POSIX sh; dash-clean.
set -eu

KIT_OLOOP_DIR="${KIT_OLOOP_DIR:-scripts}"

# check_wired <dir>: assert postmortem.sh + sparkwright exist, selftests pass,
# dispatcher routes 'postmortem', rejects unknown. Prints PASS/FAIL; returns 1 on failure.
check_wired() {
  _dir=$1
  _fail=0

  # 1. files exist
  if [ -f "$_dir/postmortem.sh" ]; then
    echo "PASS: $_dir/postmortem.sh exists"
  else
    echo "FAIL: $_dir/postmortem.sh missing"; _fail=1
  fi

  if [ -f "$_dir/sparkwright" ]; then
    echo "PASS: $_dir/sparkwright exists"
  else
    echo "FAIL: $_dir/sparkwright missing"; _fail=1
  fi

  # bail early — cannot run selftests without the files
  [ "$_fail" = "0" ] || return 1

  # 2. postmortem --selftest exits 0
  if sh "$_dir/postmortem.sh" --selftest >/dev/null 2>&1; then
    echo "PASS: sh $_dir/postmortem.sh --selftest exits 0"
  else
    echo "FAIL: sh $_dir/postmortem.sh --selftest returned non-zero"; _fail=1
  fi

  # 3. sparkwright postmortem --selftest exits 0 (dispatcher routes correctly)
  if sh "$_dir/sparkwright" postmortem --selftest >/dev/null 2>&1; then
    echo "PASS: sh $_dir/sparkwright postmortem --selftest exits 0 (dispatcher routes)"
  else
    echo "FAIL: sh $_dir/sparkwright postmortem --selftest returned non-zero (dispatcher broken)"; _fail=1
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

  # --- FIXTURE A: "gap" tree — dispatcher does NOT route 'postmortem' ---
  # postmortem.sh exists + passes its own --selftest, but dispatcher is broken
  mkdir -p "$tmp/gap"
  cat > "$tmp/gap/postmortem.sh" <<'PM_EOF'
#!/bin/sh
set -eu
if [ "${1:-}" = "--selftest" ]; then
  echo "postmortem --selftest: OK"
  exit 0
fi
exit 0
PM_EOF
  chmod +x "$tmp/gap/postmortem.sh"
  # broken dispatcher — does not route 'postmortem', exits 1 for all
  printf '#!/bin/sh\necho "broken dispatcher" >&2; exit 1\n' > "$tmp/gap/sparkwright"
  chmod +x "$tmp/gap/sparkwright"

  # The gap fixture must FAIL (dispatcher broken)
  if KIT_OLOOP_DIR="$tmp/gap" sh "$0" >/dev/null 2>&1; then
    echo "FAIL: selftest — gap fixture (broken dispatcher) wrongly passed"; sfail=1
  else
    echo "PASS: selftest — gap fixture correctly detected (broken dispatcher)"
  fi

  # --- FIXTURE B: "complete" tree — real postmortem.sh + correct sparkwright ---
  mkdir -p "$tmp/ok"
  cat > "$tmp/ok/postmortem.sh" <<'PM_OK_EOF'
#!/bin/sh
set -eu
if [ "${1:-}" = "--selftest" ]; then
  echo "postmortem --selftest: OK"
  exit 0
fi
exit 0
PM_OK_EOF
  chmod +x "$tmp/ok/postmortem.sh"

  # Correct dispatcher — routes 'postmortem', exits 2 for unknown
  cat > "$tmp/ok/sparkwright" <<'SW_EOF'
#!/bin/sh
set -eu
here=$(dirname "$0")
case "${1:-}" in
  doctor)     shift; exec sh "$here/doctor.sh" "$@" ;;
  postmortem) shift; exec sh "$here/postmortem.sh" "$@" ;;
  ""|-h|--help) echo "usage: sparkwright <command>; commands: doctor, postmortem" >&2; exit 2 ;;
  *) echo "sparkwright: unknown command '$1'; commands: doctor, postmortem" >&2; exit 2 ;;
esac
SW_EOF
  chmod +x "$tmp/ok/sparkwright"

  # The complete fixture must PASS
  if KIT_OLOOP_DIR="$tmp/ok" sh "$0" >/dev/null 2>&1; then
    echo "PASS: selftest — complete fixture correctly passed"
  else
    echo "FAIL: selftest — complete fixture wrongly failed"; sfail=1
  fi

  # --- FIXTURE C: "missing" tree — files absent ---
  mkdir -p "$tmp/empty"
  if KIT_OLOOP_DIR="$tmp/empty" sh "$0" >/dev/null 2>&1; then
    echo "FAIL: selftest — missing-files fixture wrongly passed"; sfail=1
  else
    echo "PASS: selftest — missing-files fixture correctly detected"
  fi

  [ "$sfail" -eq 0 ] && { echo "OK: operate-loop-wired selftest"; exit 0; } || { echo "FAIL: operate-loop-wired selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: operate-loop-wired.sh [--selftest]" >&2; exit 2 ;;
esac

echo "Operate-loop wiring check (dir: $KIT_OLOOP_DIR):"
if check_wired "$KIT_OLOOP_DIR"; then
  echo "OK: postmortem generator/parser is wired (sparkwright postmortem routes; --selftest green)"
  exit 0
else
  echo "FAIL: operate-loop wiring regression (see above)"
  exit 1
fi
