#!/bin/sh
# sparkwright-verbs.sh — regression-lock for the `sparkwright start` ROUTE and the router's
# exit-code contract. ONE PLACE PER ROUTE (C9): the doctor / tier-advice / explain routes are locked
# by their own *-wired.sh checks; this file owns ONLY the `start` arm and the generic router
# properties (unknown verb -> 2, usage names `start`). It does not re-assert the other routes.
#
#   sh conformance/sparkwright-verbs.sh [--selftest]
# Exit: 0 = the contract holds · 1 = a regression · 2 = usage. POSIX sh; dash-clean. Run from the
# repo root. Paths are overridable via KIT_VERBS_DIR (default: scripts) so --selftest can point at a
# fixture directory — the same seam the sibling *-wired.sh checks use.
set -eu

KIT_VERBS_DIR="${KIT_VERBS_DIR:-scripts}"

# check_wired <dir>: assert scripts/sparkwright + start.sh exist, the dispatcher ROUTES `start`
# (start --selftest exits 0), an unknown verb exits 2, and the usage string NAMES `start`.
check_wired() {
  _dir=$1
  _fail=0

  if [ -f "$_dir/sparkwright" ]; then echo "PASS: $_dir/sparkwright exists"; else echo "FAIL: $_dir/sparkwright missing"; _fail=1; fi
  if [ -f "$_dir/start.sh" ];    then echo "PASS: $_dir/start.sh exists";    else echo "FAIL: $_dir/start.sh missing";    _fail=1; fi
  # bail early — cannot run the route without the files
  [ "$_fail" = "0" ] || return 1

  # 1. the dispatcher ROUTES `start` to start.sh (start.sh --selftest exits 0 through the router)
  if sh "$_dir/sparkwright" start --selftest >/dev/null 2>&1; then
    echo "PASS: sh $_dir/sparkwright start --selftest exits 0 (dispatcher routes 'start' -> start.sh)"
  else
    echo "FAIL: sh $_dir/sparkwright start --selftest returned non-zero (route missing or start.sh broken)"; _fail=1
  fi

  # 2. an unknown verb exits 2 (the router rejects, it does not dispatch)
  _bogus_rc=0; sh "$_dir/sparkwright" bogus >/dev/null 2>&1 || _bogus_rc=$?
  if [ "$_bogus_rc" = "2" ]; then
    echo "PASS: sh $_dir/sparkwright bogus exits 2 (unknown verb rejected)"
  else
    echo "FAIL: sh $_dir/sparkwright bogus exited $_bogus_rc (expected 2)"; _fail=1
  fi

  # 3. the usage string (empty invocation) exits 2 AND names `start`, so the route is discoverable
  _usage_rc=0; _usage_out=$(sh "$_dir/sparkwright" 2>&1) || _usage_rc=$?
  if [ "$_usage_rc" = "2" ]; then
    echo "PASS: sh $_dir/sparkwright (empty) exits 2 (usage)"
  else
    echo "FAIL: sh $_dir/sparkwright (empty) exited $_usage_rc (expected 2)"; _fail=1
  fi
  case "$_usage_out" in
    *start*) echo "PASS: the usage string names 'start' (the route is discoverable)" ;;
    *)       echo "FAIL: the usage string does not name 'start'"; _fail=1 ;;
  esac

  return $_fail
}

if [ "${1:-}" = "--selftest" ]; then
  sfail=0
  tmp=$(mktemp -d)
  trap '{ rm -rf "$tmp" 2>/dev/null; } || true' EXIT INT TERM

  # A start.sh stub that passes its own --selftest — the fixtures share it.
  st_stub_body='#!/bin/sh
[ "${1:-}" = "--selftest" ] && { echo "start --selftest: OK"; exit 0; }
echo "start stub"; exit 0
'

  # --- FIXTURE A: "gap" — sparkwright does NOT route `start` (the regression this check exists for) -
  mkdir -p "$tmp/gap"
  printf '%s' "$st_stub_body" > "$tmp/gap/start.sh"; chmod +x "$tmp/gap/start.sh"
  cat > "$tmp/gap/sparkwright" <<'SW_EOF'
#!/bin/sh
set -eu
here=$(dirname "$0")
case "${1:-}" in
  doctor) shift; exec sh "$here/doctor.sh" "$@" ;;
  ""|-h|--help) echo "usage: sparkwright <command>; commands: doctor" >&2; exit 2 ;;
  *) echo "sparkwright: unknown command '$1'; commands: doctor" >&2; exit 2 ;;
esac
SW_EOF
  chmod +x "$tmp/gap/sparkwright"
  if KIT_VERBS_DIR="$tmp/gap" sh "$0" >/dev/null 2>&1; then
    echo "FAIL: selftest — gap fixture (router does not route 'start') wrongly passed"; sfail=1
  else
    echo "PASS: selftest — gap fixture correctly detected (route missing / usage silent on 'start')"
  fi

  # --- FIXTURE B: "complete" — start.sh + a router that routes it and names it in usage ------------
  mkdir -p "$tmp/ok"
  printf '%s' "$st_stub_body" > "$tmp/ok/start.sh"; chmod +x "$tmp/ok/start.sh"
  cat > "$tmp/ok/sparkwright" <<'SW_EOF'
#!/bin/sh
set -eu
here=$(dirname "$0")
case "${1:-}" in
  start) shift; exec sh "$here/start.sh" "$@" ;;
  ""|-h|--help) echo "usage: sparkwright <command>; commands: start" >&2; exit 2 ;;
  *) echo "sparkwright: unknown command '$1'; commands: start" >&2; exit 2 ;;
esac
SW_EOF
  chmod +x "$tmp/ok/sparkwright"
  if KIT_VERBS_DIR="$tmp/ok" sh "$0" >/dev/null 2>&1; then
    echo "PASS: selftest — complete fixture correctly passed"
  else
    echo "FAIL: selftest — complete fixture wrongly failed"; sfail=1
  fi

  # --- FIXTURE C: "missing" — files absent ---------------------------------------------------------
  mkdir -p "$tmp/empty"
  if KIT_VERBS_DIR="$tmp/empty" sh "$0" >/dev/null 2>&1; then
    echo "FAIL: selftest — missing-files fixture wrongly passed"; sfail=1
  else
    echo "PASS: selftest — missing-files fixture correctly detected"
  fi

  [ "$sfail" -eq 0 ] && { echo "OK: sparkwright-verbs selftest"; exit 0; } || { echo "FAIL: sparkwright-verbs selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: sparkwright-verbs.sh [--selftest]" >&2; exit 2 ;;
esac

echo "sparkwright 'start' route check (dir: $KIT_VERBS_DIR):"
if check_wired "$KIT_VERBS_DIR"; then
  echo "OK: the 'start' verb is wired (dispatcher routes it; usage names it; --selftest green)"
  exit 0
else
  echo "FAIL: 'start' verb wiring regression (see above)"
  exit 1
fi
