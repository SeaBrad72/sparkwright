#!/bin/sh
# sparkwright-verbs.sh — regression-lock for the `sparkwright` ROUTER: the `start` route in full, and
# EVERY route the router declares, derived from the router's own `case` arms (never a hand-list), plus
# the exit-code contract. Per derived route it asserts: the arm forwards a FIXED argv (the target is
# exec'd with `"$@"` and nothing else — the one documented exception is `board-claim.sh status "$@"`),
# the target the arm names exists ($here-relative) — an absent target FAILS as a broken route unless
# the verb is listed in `_pending`, which is the one declared exemption (EMPTY since 2026-09-17: the
# `prepush` engine landed, so that route is asserted live) — and the usage string names the route (both
# directions: no route unlisted, no listed verb without an arm). Residual ceiling: an arm that does not
# match the closed grammar (an uppercase/digit verb, `exec` without `sh`, different indentation) is not
# derived as a route at all, and is caught only if its verb is advertised in the usage string.
# ONE PLACE PER ROUTE (C9) still holds for route BEHAVIOUR — the
# doctor / tier-advice / explain routes keep their own *-wired.sh checks; this file owns the router's
# shape, so a new verb is covered without anyone remembering to add a lock.
#
#   sh conformance/sparkwright-verbs.sh [--selftest]
# Exit: 0 = the contract holds · 1 = a regression · 2 = usage. POSIX sh; dash-clean. Run from the
# repo root. Paths are overridable via KIT_VERBS_DIR (default: scripts) so --selftest can point at a
# fixture directory — the same seam the sibling *-wired.sh checks use.
set -eu

KIT_VERBS_DIR="${KIT_VERBS_DIR:-scripts}"

# _pending: the ONE declared exemption from the target-existence assertion — routes whose engine lands
# in a parallel task, so an absent target is pending rather than broken. THE COMMITTED DEFAULT IS
# EMPTY and that is the normal state: `prepush` was removed on 2026-09-17 when its engine landed, so
# every route is now asserted live. KIT_VERBS_PENDING is the FIXTURE SEAM that keeps the exemption
# branch covered once the committed list is empty — the same seam shape as KIT_VERBS_DIR above, and
# no wider: anyone who can set it can already point the whole check at a fixture tree. A non-empty
# list is announced on stdout on every run, so an exemption can never be silent.
_pending=''
_pending="${KIT_VERBS_PENDING-$_pending}"
[ -z "$_pending" ] || echo "INFO: declared pending exemption(s) — target existence UNVERIFIED for: $_pending"

# derive_routes <dir>: the route list, derived from the router's own `case` arms. The grammar is
# CLOSED — a route is a line `  <verb>) shift; exec sh ...`; anything else in the `case` (the
# usage/`*` arms) is not a route.
derive_routes() {
  grep -E '^  [a-z][a-z-]*\) shift; exec sh ' "$1/sparkwright" 2>/dev/null | sed 's/).*//; s/^ *//'
}

# usage_verbs <dir>: the verbs the usage string advertises (`commands: a, b, c`).
usage_verbs() {
  sh "$1/sparkwright" 2>&1 | sed -n 's/.*commands: //p' | head -1 | tr ',' '\n' \
    | sed 's/^ *//; s/ *$//' | grep -v '^$' || true
}

# routes_derived <dir>: the per-route assertions over the DERIVED route list.
routes_derived() {
  _dir=$1
  _rfail=0
  _routes=$(derive_routes "$_dir")
  _usage=$(usage_verbs "$_dir")
  _n=$(printf '%s\n' "$_routes" | grep -c '[a-z]' || true)
  # shellcheck disable=SC2086 # word-splitting the newline list into one printf arg per route is intended
  echo "INFO: derived routes ($_n): $(printf '%s ' $_routes)"
  if [ "$_n" -lt 1 ]; then
    echo "FAIL: no routes derived from $_dir/sparkwright (the case grammar changed?)"; return 1
  fi

  for _v in $_routes; do
    _arm=$(grep -E "^  $_v\) shift; exec sh " "$_dir/sparkwright")
    _tail=${_arm#*exec sh }
    _tail=${_tail%%;;*}
    _path=${_tail#\"}; _path=${_path%%\"*}
    _rest=${_tail#*\"*\"}
    _rest=$(printf '%s' "$_rest" | sed 's/^ *//; s/ *$//')
    _rel=${_path#\$here/}
    _target=$_dir/$_rel

    # (1) fixed argv — the arm forwards "$@" and nothing else.
    case "$_rest" in
      '"$@"') echo "PASS: route '$_v' forwards a fixed argv ($_path \"\$@\")" ;;
      'status "$@"')
        case "$_rel" in
          board-claim.sh) echo "PASS: route '$_v' forwards a fixed argv (documented exception: board-claim.sh status \"\$@\")" ;;
          *) echo "FAIL: route '$_v' injects the literal 'status' into a target that is not board-claim.sh ($_path)"; _rfail=1 ;;
        esac ;;
      *) echo "FAIL: route '$_v' does not forward a fixed argv — the arm execs '$_path' with [$_rest], expected \"\$@\""; _rfail=1 ;;
    esac

    # (2) the target the arm names exists ($here-relative). Absent => FAIL (a broken route), unless the
    # verb is in the declared `_pending` exemption, where it is N/A with reason — never a silent pass.
    if [ -f "$_target" ]; then
      echo "PASS: route '$_v' target exists ($_target)"
    elif case " $_pending " in *" $_v "*) true ;; *) false ;; esac; then
      echo "N/A: route '$_v' target $_target is not on this branch — existence unverified (reason: declared pending route, engine lands in a parallel task)"
    else
      echo "FAIL: route '$_v' target $_target does not exist (broken route)"; _rfail=1
    fi

    # (3) the route is discoverable — the usage string names it.
    if printf '%s\n' "$_usage" | grep -qxF "$_v"; then
      echo "PASS: route '$_v' is named in the usage string"
    else
      echo "FAIL: route '$_v' is not named in the usage string (undiscoverable)"; _rfail=1
    fi
  done

  # (4) the other direction — every verb the usage string advertises has an arm.
  for _u in $_usage; do
    if printf '%s\n' "$_routes" | grep -qxF "$_u"; then :; else
      echo "FAIL: usage names '$_u' but the case has no arm for it (phantom route)"; _rfail=1
    fi
  done

  # (5) the `prepush` route, live: when the engine is present it answers --help through the router
  # with rc 2; when it is absent (task 1 lands it) the live assertion is N/A with reason.
  if printf '%s\n' "$_routes" | grep -qxF prepush; then
    if [ -f "$_dir/../conformance/prepush-lane.sh" ]; then
      _pp_rc=0; sh "$_dir/sparkwright" prepush --help >/dev/null 2>&1 || _pp_rc=$?
      if [ "$_pp_rc" = "2" ]; then
        echo "PASS: sh $_dir/sparkwright prepush --help exits 2 through the router"
      else
        echo "FAIL: sh $_dir/sparkwright prepush --help exited $_pp_rc (expected 2)"; _rfail=1
      fi
    else
      echo "N/A: live 'prepush --help' unverified — $_dir/../conformance/prepush-lane.sh is not on this branch"
    fi
  fi

  return $_rfail
}

# check_wired <dir>: assert scripts/sparkwright + start.sh exist, the dispatcher ROUTES `start`
# (start --selftest exits 0), an unknown verb exits 2, empty/-h/--help exit 2, and the usage string
# NAMES `start`.
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

  # 4. -h / --help exit 2 as well (the help arms are the usage arm)
  for _h in -h --help; do
    _h_rc=0; sh "$_dir/sparkwright" "$_h" >/dev/null 2>&1 || _h_rc=$?
    if [ "$_h_rc" = "2" ]; then
      echo "PASS: sh $_dir/sparkwright $_h exits 2 (usage)"
    else
      echo "FAIL: sh $_dir/sparkwright $_h exited $_h_rc (expected 2)"; _fail=1
    fi
  done

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

  # mk_router <dir> <usage-list>; the case arms come from stdin. Every fixture carries the start stub
  # so the `start` legs stay green and a leg fails only for ITS reason.
  mk_router() {
    mkdir -p "$1"
    { echo '#!/bin/sh'; echo 'set -eu'; echo 'here=$(dirname "$0")'; echo 'case "${1:-}" in'; cat
      printf '  ""|-h|--help) echo "usage: sparkwright <command>; commands: %s" >&2; exit 2 ;;\n' "$2"
      printf '  *) echo "sparkwright: unknown command; commands: %s" >&2; exit 2 ;;\n' "$2"
      echo 'esac'; } > "$1/sparkwright"
    chmod +x "$1/sparkwright"
    printf '%s' "$st_stub_body" > "$1/start.sh"; chmod +x "$1/start.sh"
  }

  # leg <name> <dir> <pass|fail> [pattern the output must contain]
  leg() {
    _lrc=0; _lout=$(KIT_VERBS_DIR="$2" sh "$0" 2>&1) || _lrc=$?
    if [ "$3" = "pass" ] && [ "$_lrc" != "0" ]; then
      echo "FAIL: selftest — $1: fixture wrongly failed (rc $_lrc)"; sfail=1; return 0
    fi
    if [ "$3" = "fail" ] && [ "$_lrc" = "0" ]; then
      echo "FAIL: selftest — $1: fixture wrongly passed"; sfail=1; return 0
    fi
    if [ -n "${4:-}" ] && ! printf '%s\n' "$_lout" | grep -q "$4"; then
      echo "FAIL: selftest — $1: output did not contain [$4]"; sfail=1; return 0
    fi
    echo "PASS: selftest — $1"
  }

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
  leg "gap fixture (router does not route 'start')" "$tmp/gap" fail "does not name 'start'"

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
  leg "complete fixture" "$tmp/ok" pass

  # --- FIXTURE C: "missing" — files absent ---------------------------------------------------------
  mkdir -p "$tmp/empty"
  leg "missing-files fixture" "$tmp/empty" fail "FAIL: .*/sparkwright missing"

  # --- FIXTURE D: three arms derive exactly three routes (every target present) --------------------
  mk_router "$tmp/three" "start, doctor, explain" <<'SW_EOF'
  start) shift; exec sh "$here/start.sh" "$@" ;;
  doctor) shift; exec sh "$here/doctor.sh" "$@" ;;
  explain) shift; exec sh "$here/explain.sh" "$@" ;;
SW_EOF
  printf '#!/bin/sh\nexit 0\n' > "$tmp/three/doctor.sh"
  printf '#!/bin/sh\nexit 0\n' > "$tmp/three/explain.sh"
  leg "three-arm fixture derives exactly three routes" "$tmp/three" pass "derived routes (3): start doctor explain"

  # --- FIXTURE E: an arm that appends an extra literal argument is NOT a fixed argv ----------------
  mk_router "$tmp/sneaky" "start, x" <<'SW_EOF'
  start) shift; exec sh "$here/start.sh" "$@" ;;
  x) shift; exec sh "$here/x.sh" --sneaky "$@" ;;
SW_EOF
  leg "an arm appending a literal argument fails the fixed-argv assertion" "$tmp/sneaky" fail \
    "route 'x' does not forward a fixed argv"

  # --- FIXTURE F: a verb named in usage with no arm (phantom route) --------------------------------
  mk_router "$tmp/phantom" "start, ghost" <<'SW_EOF'
  start) shift; exec sh "$here/start.sh" "$@" ;;
SW_EOF
  leg "a usage-named verb with no case arm fails" "$tmp/phantom" fail "usage names 'ghost' but the case has no arm"

  # --- FIXTURE G: an arm missing from the usage string (undiscoverable route) ----------------------
  mk_router "$tmp/unlisted" "start" <<'SW_EOF'
  start) shift; exec sh "$here/start.sh" "$@" ;;
  doctor) shift; exec sh "$here/doctor.sh" "$@" ;;
SW_EOF
  leg "a case arm missing from the usage string fails" "$tmp/unlisted" fail \
    "route 'doctor' is not named in the usage string"

  # --- FIXTURE H: an unknown verb that does not exit 2 ---------------------------------------------
  mkdir -p "$tmp/rc"
  printf '%s' "$st_stub_body" > "$tmp/rc/start.sh"; chmod +x "$tmp/rc/start.sh"
  cat > "$tmp/rc/sparkwright" <<'SW_EOF'
#!/bin/sh
set -eu
here=$(dirname "$0")
case "${1:-}" in
  start) shift; exec sh "$here/start.sh" "$@" ;;
  ""|-h|--help) echo "usage: sparkwright <command>; commands: start" >&2; exit 2 ;;
  *) echo "sparkwright: unknown command; commands: start" >&2; exit 0 ;;
esac
SW_EOF
  chmod +x "$tmp/rc/sparkwright"
  leg "an unknown verb that exits 0 fails the reject-by-default assertion" "$tmp/rc" fail \
    "bogus exited 0 (expected 2)"

  # --- FIXTURE I: the `prepush` route — engine present: --help exits 2 through the router; engine
  # absent: the declared-pending route is N/A-with-reason, not FAIL and not a silent pass -----------
  for _v in 2 0 absent; do
    mk_router "$tmp/pp$_v/scripts" "start, prepush" <<'SW_EOF'
  start) shift; exec sh "$here/start.sh" "$@" ;;
  prepush) shift; exec sh "$here/../conformance/prepush-lane.sh" "$@" ;;
SW_EOF
    mkdir -p "$tmp/pp$_v/conformance"
    [ "$_v" = absent ] || printf '#!/bin/sh\nexit %s\n' "$_v" > "$tmp/pp$_v/conformance/prepush-lane.sh"
  done
  _ppo=$(KIT_VERBS_DIR="$tmp/ppabsent/scripts" KIT_VERBS_PENDING=prepush sh "$0" 2>&1) || { echo "FAIL: selftest — a declared-pending route with an absent target wrongly FAILED the run"; sfail=1; }
  case "$_ppo" in *"N/A: route 'prepush' target"*) echo "PASS: selftest — absent target of a DECLARED-pending route is N/A-with-reason, not FAIL and not silent (exemption driven by the KIT_VERBS_PENDING fixture seam; the committed list is empty)" ;; *) echo "FAIL: selftest — the pending-exemption N/A branch was not taken"; sfail=1 ;; esac
  leg "engine present: 'prepush --help' exits 2 through the router" "$tmp/pp2/scripts" pass \
    "PASS: sh .* prepush --help exits 2 through the router"
  leg "engine present but 'prepush --help' exits 0 fails" "$tmp/pp0/scripts" fail \
    "prepush --help exited 0 (expected 2)"

  # --- FIXTURE J: a NON-pending arm whose target is absent — a BROKEN route (FAIL), and the router
  # must not fall through to usage or to another route when it is invoked -------------------------
  mk_router "$tmp/broken" "start, x" <<'SW_EOF'
  start) shift; exec sh "$here/start.sh" "$@" ;;
  x) shift; exec sh "$here/x.sh" "$@" ;;
SW_EOF
  leg "a non-pending route whose target is absent fails (broken route)" "$tmp/broken" fail \
    "FAIL: route 'x' target .* does not exist (broken route)"
  _fo=$(sh "$tmp/broken/sparkwright" x 2>&1 || true)
  case "$_fo" in
    *usage:*|*"start stub"*) echo "FAIL: selftest — absent target fell through ($_fo)"; sfail=1 ;;
    *) echo "PASS: selftest — an absent target does not fall through to usage or another route" ;;
  esac

  [ "$sfail" -eq 0 ] && { echo "OK: sparkwright-verbs selftest"; exit 0; } || { echo "FAIL: sparkwright-verbs selftest"; exit 1; }
fi

case "${1:-}" in
  "") : ;;
  *) echo "usage: sparkwright-verbs.sh [--selftest]" >&2; exit 2 ;;
esac

echo "sparkwright router check (dir: $KIT_VERBS_DIR):"
vfail=0
check_wired "$KIT_VERBS_DIR" || vfail=1
routes_derived "$KIT_VERBS_DIR" || vfail=1
if [ "$vfail" = "0" ]; then
  echo "OK: the router's routes are wired (every derived route forwards a fixed argv and is discoverable; 'start' green)"
  exit 0
else
  echo "FAIL: sparkwright router regression (see above)"
  exit 1
fi
