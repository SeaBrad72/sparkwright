#!/bin/sh
# tracker-cred.sh - the tracker credential lookup library (SECRETS-INJECTION-AT-LAUNCH, SWAS-101;
# design docs/architecture/2026-10-10-secrets-injection-at-launch-design.md D1 to D4).
# What it changes: nothing on disk. Sourced, it defines two functions and a few plain variables.
# It reads at most the macOS login Keychain, through two fixed /usr/bin/security calls. It never
# prints a credential, never puts one on argv, and never writes one to a file.
# Guardrails: read-only on disk; the design D1 controls, in brief:
#   - ONE choke point: only tracker-jira.sh calls tracker_cred_resolve (inside its one curl path).
#     Every other entry point asks the presence question, tracker_cred_available, which never
#     reads the secret (its store argv never carries -w).
#   - The environment wins, as a pair. If any of KIT_TRACKER_USER, KIT_TRACKER_TOKEN, JIRA_EMAIL
#     or JIRA_TOKEN is set (non-empty), the store is not consulted: sources are never mixed.
#   - Host binding: the item service is sparkwright-tracker:HOST, the HOST parsed from the base
#     url (letters, digits, dots and hyphens only: no userinfo, no port). A base url changed to
#     another host finds no item, so the token cannot be sent to a different site.
#   - Every store call is bounded (stdin from /dev/null, a background-and-kill timer, 10 seconds)
#     and every failure ends in one fixed sentence with no store output echoed.
#   - The security binary is HARDCODED here. _TCR_SEC_BIN is never read from the environment: a
#     --selftest run reassigns this plain shell variable in-process (the _TJ_CURL_BIN pattern).
#   - Resolved values land in plain (unexported) shell variables of the CALLING process, so a
#     command substitution inherits them and a child process does not.
#   - Non-macOS (no /usr/bin/security): the lookup answers not-found quietly, so the environment
#     path is unchanged.
#
# Usage (sourced):
#   . scripts/tracker-cred.sh
#   tracker_cred_resolve BASE_URL    rc 0 = nothing more to do (env set, or user and token resolved)
#                                    rc 1 = no credential found (one sentence on stderr)
#   tracker_cred_available BASE_URL  rc 0 = a credential is present, nothing is read.
#                                    Sets TRACKER_CRED_SOURCE (env, keychain or none) and
#                                    TRACKER_CRED_WHY (a fixed sentence, empty when quiet).
# Usage (executed):
#   sh scripts/tracker-cred.sh --selftest

# Hardcoded: assigned unconditionally, so an ambient variable of the same name is overwritten.
_TCR_SEC_BIN=/usr/bin/security
_TCR_TIMEOUT=10
_TCR_TRIED=""
_TCR_TRIED_RC=1
_TCR_BOUND_SRC=""
_TCR_BOUND_HOST=""
TRACKER_CRED_SOURCE=""
TRACKER_CRED_WHY=""

# _tcr_env_set: true when any of the four environment variables is non-empty.
_tcr_env_set() {
  [ -n "${KIT_TRACKER_USER:-}" ] && return 0
  [ -n "${KIT_TRACKER_TOKEN:-}" ] && return 0
  [ -n "${JIRA_EMAIL:-}" ] && return 0
  [ -n "${JIRA_TOKEN:-}" ] && return 0
  return 1
}

# _tcr_cred_ok VALUE: the positive allowlist (the twin of tracker-jira.sh _tj_cred_ok). A value
# outside this charset could inject a second directive into the curl config, so it is refused.
_tcr_cred_ok() {
  _tcr_set='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789@._+/=:-'
  case "$1" in
    '') return 1 ;;
    *[!$_tcr_set]*) return 1 ;;
    *) : ;;
  esac
  [ "${#1}" -le 512 ]
}

# _tcr_acct_ok VALUE: an email-ish account, a narrower set than a token.
_tcr_acct_ok() {
  _tcr_aset='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789@._+-'
  case "$1" in
    '') return 1 ;;
    *[!$_tcr_aset]*) return 1 ;;
    *) : ;;
  esac
  [ "${#1}" -le 254 ]
}

# _tcr_parse_host BASE_URL: sets _tcr_hostv, or returns 1 for anything but https://HOST[/...] with
# a plain DNS-shaped host (no userinfo, no port, no query).
_tcr_parse_host() {
  _tcr_hset='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-'
  case "$1" in
    https://*) _tcr_h=${1#https://} ;;
    *) return 1 ;;
  esac
  _tcr_h=${_tcr_h%%/*}
  case "$_tcr_h" in
    '') return 1 ;;
    *[!$_tcr_hset]*) return 1 ;;
    [.-]*) return 1 ;;
    *[.-]) return 1 ;;
    *) : ;;
  esac
  [ "${#_tcr_h}" -le 253 ] || return 1
  _tcr_hostv=$_tcr_h
  return 0
}

# _tcr_cancel_sleeper: the timer subshell trap. The call finished in time, so stop the sleeper.
_tcr_cancel_sleeper() {
  if [ -n "$_tcr_sl" ]; then kill "$_tcr_sl" 2>/dev/null; fi
  exit 0
}

# _tcr_call ARGS...: one bounded call of the security binary. stdin is /dev/null, stderr is
# dropped (it is never shown), stdout is captured in memory. Sets _tcr_val (stdout minus one
# trailing newline) and _tcr_rc (the exit status, 143 when the timer killed it).
_tcr_call() {
  _tcr_raw=$(
    "$_TCR_SEC_BIN" "$@" </dev/null 2>/dev/null &
    _tcr_p=$!
    ( _tcr_sl=""
      trap _tcr_cancel_sleeper TERM
      sleep "$_TCR_TIMEOUT" & _tcr_sl=$!
      wait "$_tcr_sl"
      kill "$_tcr_p" 2>/dev/null ) >/dev/null 2>&1 &
    _tcr_s=$!
    _tcr_r=0
    wait "$_tcr_p" || _tcr_r=$?
    kill "$_tcr_s" 2>/dev/null || true
    wait "$_tcr_s" 2>/dev/null || true
    printf '\n%s' "$_tcr_r"
  )
  _tcr_nl='
'
  _tcr_rc=${_tcr_raw##*"$_tcr_nl"}
  _tcr_val=${_tcr_raw%"$_tcr_nl"*}
  _tcr_val=${_tcr_val%"$_tcr_nl"}
  _tcr_raw=""
  case "$_tcr_rc" in
    ''|*[!0-9]*) _tcr_rc=1 ;;
    *) : ;;
  esac
  return 0
}

# _tcr_why RC: map a security exit status onto the fixed sentence and the source class.
_tcr_why() {
  TRACKER_CRED_SOURCE=keychain
  case "$1" in
    44) TRACKER_CRED_SOURCE=none; TRACKER_CRED_WHY="no token stored for $_tcr_hostv" ;;
    36) TRACKER_CRED_WHY="the Keychain is locked" ;;
    51) TRACKER_CRED_WHY="access was cancelled" ;;
    143) TRACKER_CRED_WHY="the Keychain did not answer in ${_TCR_TIMEOUT}s (a dialog may be waiting)" ;;
    *) TRACKER_CRED_WHY="the Keychain read failed (rc $1)" ;;
  esac
}

# _tcr_prepare BASE_URL: no store on this platform is a quiet not-found; a bad host is a sentence.
_tcr_prepare() {
  TRACKER_CRED_SOURCE=none
  TRACKER_CRED_WHY=""
  [ -x "$_TCR_SEC_BIN" ] || return 1
  if ! _tcr_parse_host "${1:-}"; then
    TRACKER_CRED_WHY="the tracker base url has no host usable for a Keychain lookup"
    return 1
  fi
  _tcr_svc="sparkwright-tracker:$_tcr_hostv"
  # the login keychain is named explicitly (the trailing keychain argument), never the default search list
  if [ -z "${HOME:-}" ]; then
    TRACKER_CRED_WHY="HOME is not set, so the login Keychain path is unknown"
    return 1
  fi
  _tcr_kc="$HOME/Library/Keychains/login.keychain-db"
  return 0
}

# _tcr_lookup_account: the attribute-only call (no -w), reading the item account. Sets _tcr_acct.
_tcr_lookup_account() {
  _tcr_call find-generic-password -s "$_tcr_svc" "$_tcr_kc"
  if [ "$_tcr_rc" -ne 0 ]; then
    _tcr_why "$_tcr_rc"
    _tcr_val=""
    return 1
  fi
  _tcr_acct=$(printf '%s\n' "$_tcr_val" | sed -n -e 's/^[[:space:]]*"acct"[^=]*="\(.*\)"[[:space:]]*$/\1/p' | sed -n 1p)
  _tcr_val=""
  if ! _tcr_acct_ok "$_tcr_acct"; then
    TRACKER_CRED_SOURCE=keychain
    TRACKER_CRED_WHY="the stored item has no readable account"
    return 1
  fi
  return 0
}

# _tcr_report: one fixed sentence on stderr when the lookup failed loudly (never a store byte).
_tcr_report() {
  [ -n "$TRACKER_CRED_WHY" ] || return 0
  echo "tracker credential: $TRACKER_CRED_WHY" >&2
  [ "$TRACKER_CRED_SOURCE" = none ] || return 0
  echo "tracker credential: store a token once, see templates/JIRA-SETUP-TEMPLATE.md section 5b" >&2
}

# tracker_cred_available BASE_URL: the presence question. Reads attributes only, never the secret.
tracker_cred_available() {
  TRACKER_CRED_SOURCE=""
  TRACKER_CRED_WHY=""
  if _tcr_env_set; then
    TRACKER_CRED_SOURCE="env"
    [ -n "${KIT_TRACKER_TOKEN:-${JIRA_TOKEN:-}}" ] && return 0
    TRACKER_CRED_WHY="the environment credential has no token"
    return 1
  fi
  _tcr_prepare "${1:-}" || return 1
  _tcr_lookup_account || return 1
  TRACKER_CRED_SOURCE=keychain
  return 0
}

# tracker_cred_resolve BASE_URL: called by tracker-jira.sh alone, just before it reads the
# credential. The environment wins; otherwise the Keychain item bound to the host is read, once
# per process (a failure is remembered too, so a later call stays silent and cheap).
tracker_cred_resolve() {
  # xtrace is switched off for the whole resolve (the token is assigned in here) and restored on every return
  _tcr_xt=$-
  case "$_tcr_xt" in
    *x*) set +x ;;
    *) : ;;
  esac
  _tcr_rr=0
  _tcr_resolve_inner "${1:-}" || _tcr_rr=$?
  case "$_tcr_xt" in
    *x*) set -x ;;
    *) : ;;
  esac
  return "$_tcr_rr"
}

_tcr_resolve_inner() {
  if _tcr_env_set; then
    # a credential this library resolved belongs to the host it was read for: another host gets none
    [ "$_TCR_BOUND_SRC" = keychain ] || return 0
    if _tcr_parse_host "${1:-}" && [ "$_tcr_hostv" = "$_TCR_BOUND_HOST" ]; then return 0; fi
    unset KIT_TRACKER_USER KIT_TRACKER_TOKEN
    _TCR_BOUND_SRC=""
    _TCR_BOUND_HOST=""
    return 1
  fi
  # the memo is keyed on the HOST, so a request url and a base url of the same site share one lookup
  _tcr_key=none
  if _tcr_parse_host "${1:-}"; then _tcr_key=$_tcr_hostv; fi
  if [ "$_TCR_TRIED" = "$_tcr_key" ]; then return "$_TCR_TRIED_RC"; fi
  _TCR_TRIED=$_tcr_key
  _TCR_TRIED_RC=1
  TRACKER_CRED_SOURCE=""
  TRACKER_CRED_WHY=""
  if ! _tcr_prepare "${1:-}"; then _tcr_report; return 1; fi
  if ! _tcr_lookup_account; then _tcr_report; return 1; fi
  _tcr_call find-generic-password -s "$_tcr_svc" -a "$_tcr_acct" -w "$_tcr_kc"
  if [ "$_tcr_rc" -ne 0 ]; then
    _tcr_why "$_tcr_rc"
    _tcr_val=""
    _tcr_report
    return 1
  fi
  if ! _tcr_cred_ok "$_tcr_val"; then
    _tcr_val=""
    TRACKER_CRED_SOURCE=keychain
    TRACKER_CRED_WHY="the stored credential is outside the allowed charset"
    _tcr_report
    return 1
  fi
  unset KIT_TRACKER_USER KIT_TRACKER_TOKEN
  KIT_TRACKER_USER=$_tcr_acct
  KIT_TRACKER_TOKEN=$_tcr_val
  _tcr_val=""
  TRACKER_CRED_SOURCE=keychain
  _TCR_BOUND_SRC=keychain
  _TCR_BOUND_HOST=$_tcr_hostv
  _TCR_TRIED_RC=0
  return 0
}

# --- selftest -----------------------------------------------------------------------------------
# Runs only when this file is EXECUTED as tracker-cred.sh with --selftest. A stub security binary
# (a throwaway script) stands in for /usr/bin/security, so the legs run on Linux CI too.

# _tcr_st_mkstub DIR: write DIR/security. Its behaviour comes from DIR/mode (ok, rc44, rc36, rc51,
# rc99, hang, hangw, badtoken, newtoken) and DIR/itemhost (the one host that has an item).
_tcr_st_mkstub() {
  {
    printf '#!/bin/sh\nd=%s\n' "$1"
    cat <<'STUB'
printf '%s\n' "$*" >> "$d/log"
in=$(cat)
printf '%s' "${#in}" > "$d/stdin"
mode=$(cat "$d/mode")
svc=""
acct=""
want_w=0
prev=""
for a in "$@"; do
  if [ "$prev" = "-s" ]; then svc=$a; fi
  if [ "$prev" = "-a" ]; then acct=$a; fi
  if [ "$a" = "-w" ]; then want_w=1; fi
  prev=$a
done
if [ "$mode" = "hang" ]; then exec sleep 30; fi
if [ "$mode" = "rc44" ]; then exit 44; fi
if [ "$mode" = "rc36" ]; then exit 36; fi
if [ "$mode" = "rc51" ]; then exit 51; fi
if [ "$mode" = "rc99" ]; then exit 99; fi
if [ "$svc" != "sparkwright-tracker:$(cat "$d/itemhost")" ]; then exit 44; fi
if [ "$want_w" -eq 0 ]; then
  printf 'keychain: "/Users/x/Library/Keychains/login.keychain-db"\nclass: "genp"\nattributes:\n'
  printf '    "acct"\074blob\076="%s"\n' "$(cat "$d/acct")"
  printf '    "svce"\074blob\076="%s"\n' "$svc"
  exit 0
fi
if [ "$mode" = "hangw" ]; then exec sleep 30; fi
if [ "$acct" != "$(cat "$d/acct")" ]; then exit 44; fi
if [ "$mode" = "badtoken" ]; then printf 'bad"tok\n'; exit 0; fi
if [ "$mode" = "newtoken" ]; then printf 'line1\nline2\n'; exit 0; fi
printf '%s\n' "TOKMARKER7c1e9"
exit 0
STUB
  } > "$1/security"
  chmod +x "$1/security"
}

# _tcr_st_set MODE ITEMHOST [ACCT]: arm the stub and truncate its log.
_tcr_st_set() {
  printf '%s' "$1" > "$_tcr_sd/mode"
  printf '%s' "$2" > "$_tcr_sd/itemhost"
  printf '%s' "${3:-agent@example.com}" > "$_tcr_sd/acct"
  : > "$_tcr_sd/log"
}

# _tcr_st_run BASE_URL: resolve in a subshell with the env the legs ask for through ST_U, ST_T,
# ST_JE and ST_JT. The resolver stdout and stderr go to the combined capture files (for the
# marker negative), and stderr of the latest run also to last.err. Prints "user|token|rc" so the
# leg sees what the calling process would see.
_tcr_st_run() {
  (
    unset KIT_TRACKER_USER KIT_TRACKER_TOKEN JIRA_EMAIL JIRA_TOKEN
    [ -z "$ST_U" ] || KIT_TRACKER_USER=$ST_U
    [ -z "$ST_T" ] || KIT_TRACKER_TOKEN=$ST_T
    [ -z "$ST_JE" ] || JIRA_EMAIL=$ST_JE
    [ -z "$ST_JT" ] || JIRA_TOKEN=$ST_JT
    if [ "$ST_EMPTYEXP" = 1 ]; then KIT_TRACKER_USER=; export KIT_TRACKER_USER; fi
    _TCR_TRIED=""
    tracker_cred_resolve "$1" >> "$_tcr_sd/all.out" 2> "$_tcr_sd/last.err"
    _r=$?
    cat "$_tcr_sd/last.err" >> "$_tcr_sd/all.err"
    printf '%s|%s|%s' "${KIT_TRACKER_USER:-}" "${KIT_TRACKER_TOKEN:-}" "$_r"
  )
}

_tcr_st_clear() { ST_U=""; ST_T=""; ST_JE=""; ST_JT=""; ST_EMPTYEXP=0; }
_tcr_st_pass() { echo "PASS: selftest - $1"; }
_tcr_st_fail() { echo "FAIL: selftest - $1"; _tcr_sf=1; }

_tcr_selftest() {
  set -u
  _tcr_sf=0
  _tcr_default_bin=$_TCR_SEC_BIN
  _tcr_sd=$(mktemp -d) || { echo "FAIL: selftest - could not create a scratch directory"; return 1; }
  trap 'rm -rf "$_tcr_sd"' EXIT
  : > "$_tcr_sd/all.out"
  : > "$_tcr_sd/all.err"
  _tcr_st_mkstub "$_tcr_sd"
  HOME="$_tcr_sd/home"; export HOME
  _TCR_SEC_BIN="$_tcr_sd/security"
  _TCR_TIMEOUT=1
  _tcr_st_clear
  _tcr_host=ex.atlassian.net
  _tcr_base="https://$_tcr_host"
  _tcr_good="agent@example.com|TOKMARKER7c1e9|0"

  # the production binary path is the absolute system path, and an ambient variable cannot move it
  if [ "$_tcr_default_bin" = "/usr/bin/security" ]; then _tcr_st_pass "the hardcoded store binary is /usr/bin/security"; else _tcr_st_fail "the store binary default is $_tcr_default_bin"; fi
  _tcr_st_set ok "$_tcr_host"
  : > "$_tcr_sd/canary.log"
  printf '#!/bin/sh\necho x >> %s/canary.log\nexit 44\n' "$_tcr_sd" > "$_tcr_sd/canary"
  chmod +x "$_tcr_sd/canary"
  # the credential variables are cleared inside the child, so the resolver really reaches its store call
  _TCR_SEC_BIN="$_tcr_sd/canary" sh -c 'unset KIT_TRACKER_USER KIT_TRACKER_TOKEN JIRA_EMAIL JIRA_TOKEN
. "$1" && tracker_cred_resolve https://selftest.invalid' _ "$0" >/dev/null 2>&1 || true
  if [ ! -s "$_tcr_sd/canary.log" ]; then _tcr_st_pass "an ambient _TCR_SEC_BIN is ignored by a real subprocess (never read from the environment)"; else _tcr_st_fail "an ambient _TCR_SEC_BIN was honoured"; fi

  # the env pair wins: the store is never consulted
  _tcr_st_set ok "$_tcr_host"; ST_U=env-user@example.com; ST_T=env-token
  _tcr_out=$(_tcr_st_run "$_tcr_base"); _tcr_st_clear
  if [ "$_tcr_out" = "env-user@example.com|env-token|0" ] && [ ! -s "$_tcr_sd/log" ]; then _tcr_st_pass "the env pair wins and the stub log is empty"; else _tcr_st_fail "env pair: out=$_tcr_out log=$(cat "$_tcr_sd/log")"; fi

  # no mixing: a user alone in the env means the store is not consulted and the token stays unset
  _tcr_st_set ok "$_tcr_host"; ST_U=env-user@example.com
  _tcr_out=$(_tcr_st_run "$_tcr_base"); _tcr_st_clear
  if [ "$_tcr_out" = "env-user@example.com||0" ] && [ ! -s "$_tcr_sd/log" ]; then _tcr_st_pass "only KIT_TRACKER_USER set: no store read and no stored token mixed in"; else _tcr_st_fail "user-only: out=$_tcr_out"; fi
  _tcr_st_set ok "$_tcr_host"; ST_T=env-token
  _tcr_out=$(_tcr_st_run "$_tcr_base"); _tcr_st_clear
  if [ "$_tcr_out" = "|env-token|0" ] && [ ! -s "$_tcr_sd/log" ]; then _tcr_st_pass "only KIT_TRACKER_TOKEN set: no store read and no stored account mixed in"; else _tcr_st_fail "token-only: out=$_tcr_out"; fi

  # the legacy pair behaves the same
  _tcr_st_set ok "$_tcr_host"; ST_JE=old@example.com; ST_JT=old-token
  _tcr_out=$(_tcr_st_run "$_tcr_base"); _tcr_st_clear
  if [ "$_tcr_out" = "||0" ] && [ ! -s "$_tcr_sd/log" ]; then _tcr_st_pass "the legacy JIRA pair also wins without a store read"; else _tcr_st_fail "legacy pair: out=$_tcr_out"; fi
  _tcr_st_set ok "$_tcr_host"; ST_JT=old-token
  _tcr_out=$(_tcr_st_run "$_tcr_base"); _tcr_st_clear
  if [ "$_tcr_out" = "||0" ] && [ ! -s "$_tcr_sd/log" ]; then _tcr_st_pass "only JIRA_TOKEN set: no store read"; else _tcr_st_fail "legacy token-only: out=$_tcr_out"; fi

  # an exported but EMPTY variable (tracker-read.sh exports empties) does not count as set
  _tcr_st_set ok "$_tcr_host"; ST_EMPTYEXP=1
  _tcr_out=$(_tcr_st_run "$_tcr_base"); _tcr_st_clear
  if [ "$_tcr_out" = "$_tcr_good" ]; then _tcr_st_pass "an exported empty KIT_TRACKER_USER still lets the store answer"; else _tcr_st_fail "empty export: out=$_tcr_out"; fi

  # the Keychain success path: the exact argv of both calls, in order, no -w on the first
  _tcr_st_set ok "$_tcr_host"
  _tcr_out=$(_tcr_st_run "$_tcr_base")
  _tcr_kcp="$HOME/Library/Keychains/login.keychain-db"
  _tcr_want=$(printf 'find-generic-password -s sparkwright-tracker:%s %s\nfind-generic-password -s sparkwright-tracker:%s -a agent@example.com -w %s' "$_tcr_host" "$_tcr_kcp" "$_tcr_host" "$_tcr_kcp")
  if [ "$_tcr_out" = "$_tcr_good" ]; then _tcr_st_pass "the stored account and token resolve into the calling process"; else _tcr_st_fail "keychain success: out=$_tcr_out"; fi
  if [ "$(cat "$_tcr_sd/log")" = "$_tcr_want" ]; then _tcr_st_pass "the exact argv of both store calls (attributes only, then account and -w)"; else _tcr_st_fail "argv: $(cat "$_tcr_sd/log")"; fi
  _tcr_st_set ok "$_tcr_host"
  _tcr_out=$(_tcr_st_run "$_tcr_base/some/path")
  if [ "$_tcr_out" = "$_tcr_good" ]; then _tcr_st_pass "a base url with a path resolves the same host"; else _tcr_st_fail "path base: out=$_tcr_out"; fi

  # stdin of the store call is /dev/null even when the stdin of the caller carries data
  _tcr_st_set ok "$_tcr_host"
  printf 'STDIN-DATA' | _tcr_st_run "$_tcr_base" >/dev/null
  if [ "$(cat "$_tcr_sd/stdin")" = "0" ]; then _tcr_st_pass "the store call reads an empty stdin"; else _tcr_st_fail "stdin bytes seen by the store call: $(cat "$_tcr_sd/stdin")"; fi

  # account parsing: a quoted email is taken; a plus-addressed one too; hex and odd forms refused
  _tcr_st_set ok "$_tcr_host" "first.last+tag@example.co.uk"
  _tcr_out=$(_tcr_st_run "$_tcr_base")
  if [ "$_tcr_out" = "first.last+tag@example.co.uk|TOKMARKER7c1e9|0" ]; then _tcr_st_pass "account parse takes a plus-addressed email"; else _tcr_st_fail "acct parse: out=$_tcr_out"; fi
  _tcr_st_set ok "$_tcr_host" 'a b@example.com'
  _tcr_out=$(_tcr_st_run "$_tcr_base")
  if [ "$_tcr_out" = "||1" ] && [ "$(wc -l < "$_tcr_sd/log" | tr -d ' ')" = "1" ]; then _tcr_st_pass "an account outside the email charset is refused before the token is requested"; else _tcr_st_fail "odd acct: out=$_tcr_out log=$(cat "$_tcr_sd/log")"; fi

  # failures: each exit status has its own fixed sentence, rc 1, and no variable left set
  for _tcr_f in "rc44:no token stored for $_tcr_host" "rc36:the Keychain is locked" "rc51:access was cancelled" "rc99:the Keychain read failed (rc 99)" "hang:did not answer in" "hangw:did not answer in"; do
    _tcr_fm=${_tcr_f%%:*}; _tcr_fs=${_tcr_f#*:}
    _tcr_st_set "$_tcr_fm" "$_tcr_host"
    _tcr_out=$(_tcr_st_run "$_tcr_base")
    if [ "$_tcr_out" = "||1" ] && grep -qF -- "$_tcr_fs" "$_tcr_sd/last.err"; then _tcr_st_pass "failure $_tcr_fm: rc 1, variables unset, the fixed sentence is on stderr"; else _tcr_st_fail "failure $_tcr_fm: out=$_tcr_out err=$(cat "$_tcr_sd/last.err")"; fi
  done

  # a failure is remembered: a second resolve in the same process does not read the store again
  _tcr_st_set rc44 "$_tcr_host"
  (
    unset KIT_TRACKER_USER KIT_TRACKER_TOKEN JIRA_EMAIL JIRA_TOKEN
    _TCR_TRIED=""
    tracker_cred_resolve "$_tcr_base" >/dev/null 2>&1
    tracker_cred_resolve "$_tcr_base" >/dev/null 2>&1
    ( tracker_cred_resolve "$_tcr_base" >/dev/null 2>&1 )
  )
  if [ "$(wc -l < "$_tcr_sd/log" | tr -d ' ')" = "1" ]; then _tcr_st_pass "a failed lookup is remembered: one store call across three resolves"; else _tcr_st_fail "failure memo: log=$(cat "$_tcr_sd/log")"; fi

  # one store read per adapter invocation: after a success, further resolves (and a command
  # substitution that inherits the shell variables) find the credential and read nothing
  _tcr_st_set ok "$_tcr_host"
  _tcr_sub=$(
    unset KIT_TRACKER_USER KIT_TRACKER_TOKEN JIRA_EMAIL JIRA_TOKEN
    _TCR_TRIED=""
    tracker_cred_resolve "$_tcr_base" >/dev/null 2>&1
    tracker_cred_resolve "$_tcr_base" >/dev/null 2>&1
    inner=$( tracker_cred_resolve "$_tcr_base" >/dev/null 2>&1; printf '%s' "${KIT_TRACKER_USER:-}" )
    printf '%s' "$inner"
  )
  if [ "$_tcr_sub" = "agent@example.com" ] && [ "$(wc -l < "$_tcr_sd/log" | tr -d ' ')" = "2" ]; then _tcr_st_pass "one store read (two calls) across repeated resolves and a command substitution"; else _tcr_st_fail "one read: sub=$_tcr_sub log=$(cat "$_tcr_sd/log")"; fi

  # per-request host binding (Security L1): a credential resolved for host A is not handed to host B in the same process.
  # The stub holds an item for A only. B gets no credential, the variables are cleared, and the store is not asked for B.
  _tcr_st_set ok "$_tcr_host"
  _tcr_bind=$(
    unset KIT_TRACKER_USER KIT_TRACKER_TOKEN JIRA_EMAIL JIRA_TOKEN
    _TCR_TRIED=""
    tracker_cred_resolve "$_tcr_base" >/dev/null 2>&1
    _a="${KIT_TRACKER_USER:-}"
    _b=0
    tracker_cred_resolve "https://other.example.net/rest/api" >/dev/null 2>&1 || _b=$?
    printf '%s|%s|%s|%s' "$_a" "$_b" "${KIT_TRACKER_USER:-}" "${KIT_TRACKER_TOKEN:-}"
  )
  if [ "$_tcr_bind" = "agent@example.com|1||" ] && [ "$(wc -l < "$_tcr_sd/log" | tr -d ' ')" = "2" ]; then _tcr_st_pass "host A resolved, then a request to host B: B gets no credential, the variables are cleared, no store call for B"; else _tcr_st_fail "per-request binding: out=$_tcr_bind log=$(cat "$_tcr_sd/log")"; fi

  # xtrace (Security L3): under set -x the token assignment inside the resolver is not traced, so the marker never
  # reaches stderr. The trace is non-empty (the call line itself), so the leg is not vacuous.
  _tcr_st_set ok "$_tcr_host"
  (
    unset KIT_TRACKER_USER KIT_TRACKER_TOKEN JIRA_EMAIL JIRA_TOKEN
    _TCR_TRIED=""
    set -x
    tracker_cred_resolve "$_tcr_base" >/dev/null
  ) 2> "$_tcr_sd/xtrace.err"
  if [ -s "$_tcr_sd/xtrace.err" ] && ! grep -qF 'TOKMARKER7c1e9' "$_tcr_sd/xtrace.err"; then _tcr_st_pass "under set -x the token never reaches the trace on stderr"; else _tcr_st_fail "xtrace leg: trace bytes=$(wc -c < "$_tcr_sd/xtrace.err" | tr -d ' ') marker=$(grep -cF 'TOKMARKER7c1e9' "$_tcr_sd/xtrace.err")"; fi

  # the resolved values are plain shell variables: a child process does not inherit them
  _tcr_st_set ok "$_tcr_host"
  _tcr_child=$(
    unset KIT_TRACKER_USER KIT_TRACKER_TOKEN JIRA_EMAIL JIRA_TOKEN
    _TCR_TRIED=""
    tracker_cred_resolve "$_tcr_base" >/dev/null 2>&1
    sh -c 'printf "%s%s" "${KIT_TRACKER_USER:-}" "${KIT_TRACKER_TOKEN:-}"'
  )
  if [ -z "$_tcr_child" ]; then _tcr_st_pass "a child process of the resolver does not see the credential"; else _tcr_st_fail "the resolved credential leaked into a child environment"; fi

  # host binding: a base url naming another host asks for that host's service and finds no item
  _tcr_st_set ok "$_tcr_host"
  _tcr_out=$(_tcr_st_run "https://other.example.net")
  if [ "$_tcr_out" = "||1" ] && grep -qF 'sparkwright-tracker:other.example.net' "$_tcr_sd/log" && ! grep -qF -- '-w' "$_tcr_sd/log" && ! grep -qF "sparkwright-tracker:$_tcr_host" "$_tcr_sd/log"; then _tcr_st_pass "host binding: another host looks up its own service and never gets this host's item"; else _tcr_st_fail "host binding: out=$_tcr_out log=$(cat "$_tcr_sd/log")"; fi
  for _tcr_bad in "http://ex.atlassian.net" "https://user@ex.atlassian.net" "https://ex.atlassian.net:8443" "https://ex.atlassian.net?x=1" "https://-bad.example.com" "ex.atlassian.net" ""; do
    _tcr_st_set ok "$_tcr_host"
    _tcr_out=$(_tcr_st_run "$_tcr_bad")
    if [ "$_tcr_out" = "||1" ] && [ ! -s "$_tcr_sd/log" ]; then _tcr_st_pass "an unusable base url is refused with no store call: $_tcr_bad"; else _tcr_st_fail "bad base url [$_tcr_bad]: out=$_tcr_out"; fi
  done

  # a stored value outside the credential charset is refused (a quote, or a newline that would start a new curl directive)
  for _tcr_bt in badtoken newtoken; do
    _tcr_st_set "$_tcr_bt" "$_tcr_host"
    _tcr_out=$(_tcr_st_run "$_tcr_base")
    if [ "$_tcr_out" = "||1" ]; then _tcr_st_pass "a stored value with a quote or a newline is refused ($_tcr_bt)"; else _tcr_st_fail "$_tcr_bt accepted: out=$_tcr_out"; fi
  done

  # non-macOS: no store binary means a quiet not-found and an unchanged env path
  _tcr_savebin=$_TCR_SEC_BIN
  _TCR_SEC_BIN="$_tcr_sd/no-such-security"
  _tcr_out=$(_tcr_st_run "$_tcr_base")
  if [ "$_tcr_out" = "||1" ] && [ ! -s "$_tcr_sd/last.err" ]; then _tcr_st_pass "no store binary (non-macOS): a quiet not-found"; else _tcr_st_fail "non-macOS: out=$_tcr_out err=$(cat "$_tcr_sd/last.err")"; fi
  _TCR_SEC_BIN=$_tcr_savebin

  # tracker_cred_available: attribute-only, never -w, never a value
  _tcr_st_set ok "$_tcr_host"
  _tcr_av=$( unset KIT_TRACKER_USER KIT_TRACKER_TOKEN JIRA_EMAIL JIRA_TOKEN; tracker_cred_available "$_tcr_base" >> "$_tcr_sd/all.out" 2>> "$_tcr_sd/all.err"; printf '%s|%s|%s' "$?" "$TRACKER_CRED_SOURCE" "${KIT_TRACKER_TOKEN:-}" )
  if [ "$_tcr_av" = "0|keychain|" ] && [ "$(wc -l < "$_tcr_sd/log" | tr -d ' ')" = "1" ] && ! grep -qF -- '-w' "$_tcr_sd/log"; then _tcr_st_pass "available: present, one attribute-only call, no -w, no token set"; else _tcr_st_fail "available: $_tcr_av log=$(cat "$_tcr_sd/log")"; fi
  for _tcr_am in "rc44:none" "rc36:keychain" "rc51:keychain" "hang:keychain"; do
    _tcr_st_set "${_tcr_am%%:*}" "$_tcr_host"
    _tcr_av=$( unset KIT_TRACKER_USER KIT_TRACKER_TOKEN JIRA_EMAIL JIRA_TOKEN; tracker_cred_available "$_tcr_base" >> "$_tcr_sd/all.out" 2>> "$_tcr_sd/all.err"; printf '%s|%s' "$?" "$TRACKER_CRED_SOURCE" )
    if [ "$_tcr_av" = "1|${_tcr_am#*:}" ] && ! grep -qF -- '-w' "$_tcr_sd/log"; then _tcr_st_pass "available: ${_tcr_am%%:*} answers not-present as ${_tcr_am#*:}, still no -w"; else _tcr_st_fail "available ${_tcr_am%%:*}: $_tcr_av"; fi
  done
  _tcr_st_set ok "$_tcr_host"
  _tcr_av=$( unset JIRA_EMAIL JIRA_TOKEN; KIT_TRACKER_USER=u; KIT_TRACKER_TOKEN=t; tracker_cred_available "$_tcr_base"; printf '%s|%s' "$?" "$TRACKER_CRED_SOURCE" )
  if [ "$_tcr_av" = "0|env" ] && [ ! -s "$_tcr_sd/log" ]; then _tcr_st_pass "available: the env pair answers present with no store call"; else _tcr_st_fail "available env: $_tcr_av"; fi

  # LOAD-BEARING NEGATIVE: the token marker never appears on stdout or stderr of any path above.
  # It kills an echo mutant (a resolver that prints, logs or warns with the value it just read).
  # The positive control below proves the marker really was reachable, so the negative is not vacuous.
  if [ -s "$_tcr_sd/all.out" ] || [ -s "$_tcr_sd/all.err" ]; then
    if grep -qF 'TOKMARKER7c1e9' "$_tcr_sd/all.out" "$_tcr_sd/all.err"; then _tcr_st_fail "the token marker appeared on stdout or stderr"; else _tcr_st_pass "the token marker never appeared on stdout or stderr of any path"; fi
  else
    _tcr_st_pass "the token marker never appeared on stdout or stderr (no output at all)"
  fi
  if [ "$_tcr_good" = "agent@example.com|TOKMARKER7c1e9|0" ] && grep -qF 'TOKMARKER7c1e9' "$_tcr_sd/security"; then _tcr_st_pass "positive control: the marker is what the stub returns, and the success leg saw it in the variable"; else _tcr_st_fail "marker control"; fi

  if [ "$_tcr_sf" -eq 0 ]; then echo "tracker-cred --selftest: OK"; return 0; fi
  echo "tracker-cred --selftest: FAIL"
  return 1
}

# Executed (not sourced) as tracker-cred.sh: run the selftest. Sourced, $0 is the caller's name.
case "${0##*/}" in
  tracker-cred.sh)
    if [ "${1:-}" = "--selftest" ]; then
      _tcr_selftest
      exit $?
    fi
    echo "usage: sh scripts/tracker-cred.sh --selftest   (a library: source it to use the functions)" >&2
    exit 2 ;;
  *) : ;;
esac
