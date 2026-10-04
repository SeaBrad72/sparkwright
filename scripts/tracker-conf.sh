#!/bin/sh
# tracker-conf.sh — the ONE place the `.kit/tracker.conf` grammar lives (TBG-TRACKER-CONF, design
# §5 of docs/architecture/2026-09-19-tracker-backed-governance-design.md).
# What it changes: read-only. Validates a conf file against the strict `key=value` grammar and,
# on `get`/`get-all`, prints the value(s). Never writes, never touches the network, never sees a token (the
# file carries no secret — credentials are env-only, KIT_TRACKER_USER/KIT_TRACKER_TOKEN).
# Guardrails: fail-closed (an unknown key or a malformed value REFUSES the whole file, not just
# the line); https-only (no `http://`, no userinfo, no query — the host is the pin); every
# refusal names the offending key, the violation, and the fix (F5); POSIX sh; the one `sed`
# call (inline-comment stripping) is a read-only BRE substitution, identical on macOS and CI.
#
# Usage:
#   tracker-conf.sh <conf-file>            — validate; prints nothing on success (rc 0),
#                                             refusal sentences on stderr on failure (rc 1)
#   tracker-conf.sh get <key> <conf-file>  — validate, then print the FIRST value for <key>
#                                             (rc 1 if invalid or the key is absent)
#   tracker-conf.sh get-all <key> <conf-file> — validate, then print EVERY value for <key>, one
#                                             per line, in file order (rc 1 if invalid or the key
#                                             is absent). F-4: `state.<kit>` is repeatable (a kit
#                                             state can map onto more than one tracker status);
#                                             `get` keeps returning only the FIRST (the `move`
#                                             target), get-all is the multi-status reader's
#                                             accessor (tracker-read.sh's tr_resolve_state_ids).
#   tracker-conf.sh get-prefix <prefix> <conf-file> — validate, then print every `<prefix>*` line as
#                                             `key<TAB>value` in file order (create.issuetype excluded;
#                                             no match = rc 0, no output). Callers enumerate `create.`
#                                             defaults this way.
#   tracker-conf.sh check-create <token> <value> — the create.<token>=<value> grammar applied to a pair
#                                             not in the conf (board.sh --field); rc 0 / rc 1 + sentence
#   tracker-conf.sh --selftest             — run the fixture battery (CI-safe, no filesystem
#                                             state outside a temp dir)
set -eu
# S1: the grammar's bracket ranges ([a-z0-9.-] etc.) are locale-collated, not byte ranges — under
# LC_ALL=en_US.UTF-8 on macOS sh/bash an uppercase byte can fall inside [a-z] and wrongly pass.
# Pin the locale for THIS process (and every `sh "$0"` child the selftest spawns) so the grammar
# means the same thing regardless of the caller's environment.
LC_ALL=C; export LC_ALL

# --- grammar helpers -------------------------------------------------------------------------

# _tc_say_refusal <sentence>: T3b step 0a item 3 — the ONE place a refusal sentence reaches
# stderr. A refusal can embed an attacker-controlled key/value (S-6 — a control byte, e.g. ESC,
# must never land raw on a terminal/log); stripped here before printing, via `printf` (never
# `echo`, whose dash builtin can reinterpret a backslash sequence in the sentence). S2: a POSITIVE
# printable-ASCII allowlist (belt), not a `[:cntrl:]` strip (which misses a C1 byte like 0x9B or a
# bare 0xFF outright) — the per-fragment `_tc_disp` braces below is the primary fix.
_tc_say_refusal() {
  printf '%s\n' "$(printf '%s' "$1" | tr -cd '\40-\176')" >&2
}

# _tc_disp <untrusted-fragment>: T3b-0 fix1 S2/S3 — a sanitised, length-bounded DISPLAY copy for a
# fragment about to be interpolated into a refusal sentence (the `_tj_target_disp` pattern,
# tracker-jira.sh). NEVER use this value for a grammar decision — only `_tc_say_refusal`'s already
# fail-closed reason string prints it. Positive printable-ASCII allowlist first (S2: a C1 byte or
# 0xFF must never reach the log), then a hard length bound (S3: an unbounded fragment produced an
# unbounded stderr line) — bounding AFTER the fix so a huge fragment cannot push a trailing "fix:"
# clause out of the printed sentence.
_tc_disp() {
  printf '%s' "$1" | tr -cd '\40-\176' | cut -c1-64
}

# _tc_is_https_url <value> <key>: sets $_tc_reason on failure, returns 1. Every interpolated value
# below is a SANITISED display copy (`_tc_disp`, S2/S3) — the grammar decisions above use the raw
# `$_u`/`$_host`/etc., never the display copy.
_tc_is_https_url() {
  _u=$1; _k=$2
  case "$_u" in
    https://*) : ;;
    http://*) _tc_reason="refused: $_k must be https:// (got http://...)"; return 1 ;;
    *) _tc_reason="refused: $_k must start with https:// (got '$(_tc_disp "$_u")')"; return 1 ;;
  esac
  _rest=${_u#https://}
  [ -n "$_rest" ] || { _tc_reason="refused: $_k must name a host after https:// (got '$(_tc_disp "$_u")')"; return 1; }
  # split off the path (first '/'), if any
  case "$_rest" in
    */*) _hostport=${_rest%%/*}; _path=${_rest#*/} ;;
    *)   _hostport=$_rest; _path='' ;;
  esac
  case "$_hostport" in
    *'@'*) _tc_reason="refused: $_k must not carry userinfo (got '$(_tc_disp "$_u")') - put credentials in KIT_TRACKER_USER/KIT_TRACKER_TOKEN, never in the conf"; return 1 ;;
  esac
  case "$_u" in
    *'?'*) _tc_reason="refused: $_k must not carry a query string (got '$(_tc_disp "$_u")') - the host is the pin, drop everything after '?'"; return 1 ;;
  esac
  case "$_u" in
    *'#'*) _tc_reason="refused: $_k must not carry a fragment (got '$(_tc_disp "$_u")')"; return 1 ;;
  esac
  [ -n "$_hostport" ] || { _tc_reason="refused: $_k must name a host after https:// (got '$(_tc_disp "$_u")')"; return 1; }
  case "$_hostport" in
    *:*) _host=${_hostport%%:*}; _port=${_hostport#*:} ;;
    *)   _host=$_hostport; _port='' ;;
  esac
  # security M-1/reviewer M-1: LOWERCASE only. The host is the pin (byte-for-byte); §5's own grammar
  # and every refusal sentence say `[a-z0-9.-]`, so an uppercase byte must refuse rather than silently
  # widen the pin to a case-variant host.
  case "$_host" in
    ''|*[!a-z0-9.-]*) _tc_reason="refused: $_k host must be lowercase ASCII [a-z0-9.-] (punycode stays visible; no IDN decode; uppercase refused - the host is the pin, byte-for-byte) - got '$(_tc_disp "$_host")'"; return 1 ;;
  esac
  if [ -n "$_port" ]; then
    case "$_port" in
      ''|*[!0-9]*) _tc_reason="refused: $_k port must be digits only (got ':$(_tc_disp "$_port")')"; return 1 ;;
    esac
  fi
  # security M-4: the path prefix is admitted, but its CHARSET is bounded — no space/tab/CR, which
  # would otherwise ride into a curl URL argument unbounded.
  case "$_path" in
    *[!A-Za-z0-9._~/%-]*) _tc_reason="refused: $_k path prefix must match [A-Za-z0-9._~/%-]+ (no space/tab/control char) - got '/$(_tc_disp "$_path")'"; return 1 ;;
  esac
  return 0
}

# _tc_create_token_ok <create.token>: the token after `create.` is ^[A-Za-z][A-Za-z0-9_]{0,63}$ —
# backend-neutral (no tracker field names here; which tokens a backend can WRITE is the adapter's
# `writable-create-keys`, asked at use). Sets $_tc_reason on failure.
_tc_create_token_ok() {
  _ct=${1#create.}
  case "$_ct" in
    [ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz]*) : ;;
    *) _tc_reason="refused: $(_tc_disp "$1") token must start with a letter (^[A-Za-z][A-Za-z0-9_]{0,63}\$)"; return 1 ;;
  esac
  case "$_ct" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_]*) _tc_reason="refused: $(_tc_disp "$1") token must match ^[A-Za-z][A-Za-z0-9_]{0,63}\$ (letters, digits, underscore only)"; return 1 ;;
  esac
  [ "${#_ct}" -le 64 ] || { _tc_reason="refused: $(_tc_disp "$1") token must be at most 64 bytes (got ${#_ct})"; return 1; }
  return 0
}

# _tc_create_value_ok <create.token> <value>: `prompt`, `id:<1-18 digits>`, or a literal — printable
# ASCII, 1-80 bytes, no tab, no `|` (the allowed-values separator), no leading/trailing space.
# Each rule has its own sentence. Sets $_tc_reason on failure.
_tc_create_value_ok() {
  _ck=$1; _cv=$2
  case "$_cv" in
    '') _tc_reason="refused: $(_tc_disp "$_ck") must not be empty (use a value, id:<digits>, or prompt)"; return 1 ;;
    prompt) return 0 ;;
    id:*)
      _cid=${_cv#id:}
      case "$_cid" in
        '') _tc_reason="refused: $(_tc_disp "$_ck") id: needs digits (id:<1-18 digits>)"; return 1 ;;
        *[!0123456789]*) _tc_reason="refused: $(_tc_disp "$_ck") id: must be digits only (got '$(_tc_disp "$_cv")')"; return 1 ;;
      esac
      [ "${#_cid}" -le 18 ] || { _tc_reason="refused: $(_tc_disp "$_ck") id: must be at most 18 digits (got ${#_cid})"; return 1; }
      return 0 ;;
  esac
  case "$_cv" in
    *"$(printf '\t')"*) _tc_reason="refused: $(_tc_disp "$_ck") value must not contain a tab"; return 1 ;;
  esac
  [ -z "$(printf '%s' "$_cv" | tr -d '\40-\176')" ] || { _tc_reason="refused: $(_tc_disp "$_ck") value must be printable ASCII only (got '$(_tc_disp "$_cv")')"; return 1; }
  case "$_cv" in
    *'|'*) _tc_reason="refused: $(_tc_disp "$_ck") value must not contain '|' (it separates a field's allowed values)"; return 1 ;;
    ' '*) _tc_reason="refused: $(_tc_disp "$_ck") value must not start with a space"; return 1 ;;
    *' ') _tc_reason="refused: $(_tc_disp "$_ck") value must not end with a space"; return 1 ;;
  esac
  [ "${#_cv}" -le 80 ] || { _tc_reason="refused: $(_tc_disp "$_ck") value must be at most 80 bytes (got ${#_cv})"; return 1; }
  return 0
}

# _tc_validate_line <key> <value>: sets $_tc_reason on failure, returns 1. Fail-closed default:
# an unknown key refuses.
_tc_validate_line() {
  _k=$1; _v=$2
  case "$_k" in
    version)
      [ "$_v" = "1" ] || { _tc_reason="refused: version must be '1' (got '$(_tc_disp "$_v")')"; return 1; } ;;
    backend)
      # security M-2: closed, tight ASCII grammar — a stray `;`, `!`, or uppercase byte in the
      # adapter-selecting key must refuse, not silently pass with a lowercase FIRST character only.
      case "$_v" in
        ''|*[!a-z0-9_-]*) _tc_reason="refused: backend must match ^[a-z0-9_-]+\$ (got '$(_tc_disp "$_v")')"; return 1 ;;
      esac ;;
    base_url)
      _tc_is_https_url "$_v" base_url || return 1 ;;
    flavour)
      case "$_v" in
        cloud|datacenter) : ;;
        *) _tc_reason="refused: flavour must be 'cloud' or 'datacenter' (got '$(_tc_disp "$_v")')"; return 1 ;;
      esac ;;
    auth)
      case "$_v" in
        basic|bearer) : ;;
        *) _tc_reason="refused: auth must be 'basic' or 'bearer' (got '$(_tc_disp "$_v")')"; return 1 ;;
      esac ;;
    project)
      case "$_v" in
        '') _tc_reason="refused: project must not be empty"; return 1 ;;
        [A-Z]*)
          case "$_v" in
            *[!A-Z0-9_]*) _tc_reason="refused: project must match ^[A-Z][A-Z0-9_]*\$ (got '$(_tc_disp "$_v")')"; return 1 ;;
          esac ;;
        *) _tc_reason="refused: project must match ^[A-Z][A-Z0-9_]*\$ (got '$(_tc_disp "$_v")')"; return 1 ;;
      esac ;;
    state.*)
      # security M-4/L-2: the state NAME is a closed set (design §4.1's eight tokens) — a typo like
      # `state.doen` must refuse, not silently become "an unmapped kit state is legal" (that clause
      # covers an OMITTED state, never a misspelled one). The VALUE is bounded ASCII, no quote/
      # backslash/control byte (it rides into a printed table and, later, a tracker API call).
      _sn=${_k#state.}
      # shellcheck disable=SC2194  # deliberate closed-set membership idiom (case " list " in *" $x "*)
      case " backlog ready in-progress in-review released done blocked cancelled " in
        *" $_sn "*) : ;;
        *) _tc_reason="refused: $(_tc_disp "$_k") names an unknown kit state '$(_tc_disp "$_sn")' (must be one of: backlog ready in-progress in-review released done blocked cancelled)"; return 1 ;;
      esac
      case "$_v" in
        '') _tc_reason="refused: $(_tc_disp "$_k") must not be empty"; return 1 ;;
      esac
      # security L-7: `'` (apostrophe) is ADMITTED in the value only — a default Jira Cloud status
      # name is literally "Won't Do", and refusing it would be a real adopter blocker for zero safety
      # gain: S-8 resolves state names to ids server-side BEFORE any JQL is built, so this value never
      # reaches a raw query. `"`, `\`, control bytes and the length bound stay refused. Tested by
      # STRIPPING apostrophes into a throwaway copy before the charset check, rather than adding `'`
      # into the bracket expression literally (a literal `'` inside a case pattern is a shell quoting
      # hazard, not just a grammar one) — the original `$_v` is what is stored and returned by `get`.
      _sv_noapos=$(printf '%s' "$_v" | tr -d "'")
      case "$_sv_noapos" in
        *[!A-Za-z0-9" "_-]*) _tc_reason="refused: $(_tc_disp "$_k") must match ^[A-Za-z0-9 '_-]{1,40}\$ (no double-quote/backslash/control byte) - got '$(_tc_disp "$_v")'"; return 1 ;;
      esac
      _sl=${#_v}
      [ "$_sl" -le 40 ] || { _tc_reason="refused: $(_tc_disp "$_k") must be at most 40 characters (got $_sl)"; return 1; } ;;
    field.*)
      # security M-4: the field NAME is bounded ASCII; the VALUE is a CLOSED set (never an arbitrary
      # bareword) — customfield_NNNNN | label:<lowercase prefix> | none | description ("description"
      # kept: §5's own example maps a dor-* flag onto the description field, handled server-side S-7).
      _fn=${_k#field.}
      case "$_fn" in
        [a-z]*)
          case "$_fn" in
            *[!a-z0-9-]*) _tc_reason="refused: $(_tc_disp "$_k") field name must match ^[a-z][a-z0-9-]*\$ (got '$(_tc_disp "$_fn")')"; return 1 ;;
          esac ;;
        *) _tc_reason="refused: $(_tc_disp "$_k") field name must match ^[a-z][a-z0-9-]*\$ (got '$(_tc_disp "$_fn")')"; return 1 ;;
      esac
      case "$_v" in
        none|description) : ;;
        customfield_*)
          _fnum=${_v#customfield_}
          case "$_fnum" in
            ''|*[!0-9]*) _tc_reason="refused: $(_tc_disp "$_k") customfield id must be digits (got '$(_tc_disp "$_v")')"; return 1 ;;
          esac ;;
        label:*)
          _flab=${_v#label:}
          case "$_flab" in
            ''|*[!a-z]*) _tc_reason="refused: $(_tc_disp "$_k") label: prefix must match ^[a-z]+\$ (got '$(_tc_disp "$_v")')"; return 1 ;;
          esac ;;
        *) _tc_reason="refused: $(_tc_disp "$_k") must be customfield_NNNNN, label:<lowercase-prefix>, none, or description (got '$(_tc_disp "$_v")')"; return 1 ;;
      esac ;;
    create.issuetype)
      # BOARD-CREATE-HONOURS-FIELD-MAP: the issue type `board create` makes (default Task when absent).
      # A bounded name: it rides into a create-meta lookup and a JSON body (built with jq --arg, never
      # interpolated), so no quote/backslash/control byte and a length bound; the first char is a letter.
      case "$_v" in
        '') _tc_reason="refused: create.issuetype must not be empty (omit the key to get the default, Task)"; return 1 ;;
        [ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz]*) : ;;
        *) _tc_reason="refused: create.issuetype must start with a letter (got '$(_tc_disp "$_v")')"; return 1 ;;
      esac
      case "$_v" in
        *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" "_-]*) _tc_reason="refused: create.issuetype must match ^[A-Za-z][A-Za-z0-9 _-]{0,39}\$ (no quote/backslash/control byte) - got '$(_tc_disp "$_v")'"; return 1 ;;
      esac
      _cl=${#_v}
      [ "$_cl" -le 40 ] || { _tc_reason="refused: create.issuetype must be at most 40 characters (got $_cl)"; return 1; } ;;
    create.*)
      # TRACKER-REQUIRED-FIELDS-DISCOVERY: a per-project create default (after create.issuetype, which
      # keeps its own arm above). Neutral grammar; the adapter owns which tokens it can write.
      _tc_create_token_ok "$_k" || return 1
      _tc_create_value_ok "$_k" "$_v" || return 1 ;;
    list_cap)
      # reviewer M-2: no leading zero on a multi-digit value (00/01 are not a canonical positive int).
      case "$_v" in
        ''|*[!0-9]*|0) _tc_reason="refused: list_cap must be a positive integer with no leading zero (got '$(_tc_disp "$_v")')"; return 1 ;;
        0*) _tc_reason="refused: list_cap must not have a leading zero (got '$(_tc_disp "$_v")')"; return 1 ;;
      esac ;;
    proxy)
      _tc_is_https_url "$_v" proxy || return 1 ;;
    ca_file)
      # security M-4: an absolute path, bounded ASCII charset (it is handed to curl's --cacert).
      case "$_v" in
        /*)
          case "$_v" in
            *[!A-Za-z0-9._/-]*) _tc_reason="refused: ca_file must match ^/[A-Za-z0-9._/-]+\$ (got '$(_tc_disp "$_v")')"; return 1 ;;
          esac ;;
        *) _tc_reason="refused: ca_file must be an absolute path matching ^/[A-Za-z0-9._/-]+\$ (got '$(_tc_disp "$_v")')"; return 1 ;;
      esac ;;
    cloud_id)
      case "$_v" in
        ''|*[!A-Za-z0-9-]*) _tc_reason="refused: cloud_id must match ^[A-Za-z0-9-]+\$ (got '$(_tc_disp "$_v")')"; return 1 ;;
      esac ;;
    *)
      _tc_reason="refused: unknown key '$(_tc_disp "$_k")' (see docs/architecture/2026-09-19-tracker-backed-governance-design.md section 5 for the supported grammar) - fix: remove it or use a supported key"
      return 1 ;;
  esac
  return 0
}

# _tc_validate_field_key <key> <value> : T3b step 0a item 1's field.* singleton check + T10-harden-A
# C3's cross-key duplicate-VALUE check (two DIFFERENT field.* keys must never share the same value —
# one tracker field would silently decide two DoR flags; 'none' is exempt, since it names NO field
# and several DoR flags legitimately share it). Mutates $_tc_seen/$_tc_fieldvals_seen and sets
# $_tc_reason on refusal — called DIRECTLY by _tc_validate_file, never via $(...), mirroring this
# file's own convention for state-mutating helpers. Extracted so _tc_validate_file stays closer to
# the line guideline.
_tc_validate_field_key() {
  _k=$1; _v=$2
  case "$_tc_seen" in
    *" $_k "*) _tc_reason="refused: $(_tc_disp "$_k") is set more than once (a duplicate field.* mapping can silently repoint a dor-* flag - remove all but one)"; return 1 ;;
  esac
  _tc_seen="$_tc_seen$_k "
  [ "$_v" = none ] && return 0
  case "$_tc_createtoks_seen" in
    *" $_v "*) _tc_reason="refused: $(_tc_disp "$_k") maps to '$(_tc_disp "$_v")', which a create.$(_tc_disp "$_v") default also targets (the field would be written twice - drop one)"; return 1 ;;
  esac
  case "$_tc_fieldvals_seen" in
    *" $_v "*) _tc_reason="refused: $(_tc_disp "$_k") repeats the value another field.* key already uses (one tracker field would silently decide two DoR flags)"; return 1 ;;
  esac
  _tc_fieldvals_seen="$_tc_fieldvals_seen$_v "
  return 0
}

# _tc_validate_create_key <key> <value>: a create.<token> default (not create.issuetype, which has its
# own singleton entry): each token at most once, and a token equal to any field.* id value is refused
# (the kit already writes that field via --size/--risk; a second default would overwrite or double it).
# The mirror check — field.* declared AFTER the create line — lives in _tc_validate_field_key.
_tc_validate_create_key() {
  _k=$1
  _ctok=${_k#create.}
  case "$_tc_seen" in
    *" $_k "*) _tc_reason="refused: $(_tc_disp "$_k") is set more than once (a second default for one field is ambiguous - remove all but one)"; return 1 ;;
  esac
  _tc_seen="$_tc_seen$_k "
  case "$_tc_fieldvals_seen" in
    *" $_ctok "*) _tc_reason="refused: $(_tc_disp "$_k") targets the same field id a field.* key already maps (the kit writes that field via --size/--risk; drop the create. line)"; return 1 ;;
  esac
  _tc_createtoks_seen="$_tc_createtoks_seen$_ctok "
  return 0
}

# _tc_validate_file <conf-file>: reads $1 line by line; sets $_tc_reason and returns 1 on the
# FIRST violation (fail-closed: the whole file is refused, not just the bad line). On success,
# populates the newline-separated $_tc_kv (each entry "key<TAB>value") for `get`/`get-all` to scan.
_tc_validate_file() {
  _f=$1
  [ -f "$_f" ] || { _tc_reason="refused: no such conf file '$(_tc_disp "$_f")'"; return 1; }
  _tc_kv=''
  # security M-3: a duplicate SINGLETON key silently repoints the pin on the second line (`get`
  # already returns the first, so a stamped/edited conf carrying two `base_url=` lines LOOKS
  # consistent to a human diff while a second reader could disagree) — refuse the 2nd occurrence.
  _tc_seen=' '
  _tc_fieldvals_seen=' '
  _tc_createtoks_seen=' '
  # security M-4/L-6 core-key requirement: version/backend/base_url/project must each appear
  # exactly once; an EMPTY state map is still legal ( --existing).
  _saw_version=0; _saw_backend=0; _saw_base_url=0; _saw_project=0
  while IFS= read -r _line || [ -n "$_line" ]; do
    case "$_line" in
      ''|'#'*) continue ;;
    esac
    case "$_line" in
      *=*) _k=${_line%%=*}; _v=${_line#*=} ;;
      *) _tc_reason="refused: malformed line (expected key=value): '$(_tc_disp "$_line")'"; return 1 ;;
    esac
    # security L-6: an inline `# comment` after a value is admitted (design §5's own example uses
    # one) — strip it here, ONE place, before any grammar check sees the value. Only a `#` preceded
    # by whitespace counts as a comment lead-in (a bare `#` glued to the value is data, not prose).
    case "$_v" in
      *' #'*|*"$(printf '\t')#"*) _v=$(printf '%s' "$_v" | sed -E 's/[ 	]+#.*$//') ;;
    esac
    # shellcheck disable=SC2194  # deliberate closed-set membership idiom (case " list " in *" $x "*)
    case " version backend base_url flavour auth project list_cap proxy ca_file cloud_id create.issuetype " in
      *" $_k "*)
        case "$_tc_seen" in
          *" $_k "*) _tc_reason="refused: $_k is set more than once (a duplicate singleton key can silently repoint the pin - remove all but one)"; return 1 ;;
        esac
        _tc_seen="$_tc_seen$_k "
        case "$_k" in
          version) _saw_version=1 ;;
          backend) _saw_backend=1 ;;
          base_url) _saw_base_url=1 ;;
          project) _saw_project=1 ;;
        esac ;;
    esac
    # T3b step 0a item 1 / T10-harden-A C3: field.<x>'s own singleton + cross-key duplicate-VALUE
    # checks, extracted so this function stays closer to the line guideline.
    case "$_k" in
      field.*) _tc_validate_field_key "$_k" "$_v" || return 1 ;;
      create.issuetype) : ;;
      create.*) _tc_validate_create_key "$_k" || return 1 ;;
    esac
    if ! _tc_validate_line "$_k" "$_v"; then return 1; fi
    _tc_kv="${_tc_kv}${_k}	${_v}
"
  done < "$_f"
  [ "$_saw_version" -eq 1 ]  || { _tc_reason="refused: version is required and was not set"; return 1; }
  [ "$_saw_backend" -eq 1 ]  || { _tc_reason="refused: backend is required and was not set"; return 1; }
  [ "$_saw_base_url" -eq 1 ] || { _tc_reason="refused: base_url is required and was not set"; return 1; }
  [ "$_saw_project" -eq 1 ]  || { _tc_reason="refused: project is required and was not set"; return 1; }
  return 0
}

# --- selftest ----------------------------------------------------------------------------------

_tc_selftest() {
  sfail=0
  tmpd=$(mktemp -d) || { echo "FAIL: selftest could not create a temp dir"; exit 1; }
  # security NV-1 defence in depth: an EXIT trap runs on ANY termination of this function/script,
  # including an unhandled abort under `set -u`/`set -e` — and on macOS's /bin/sh (bash 3.2) that
  # abort's own exit status is REPLACED by whatever this trap itself exits with (0, by default),
  # turning a crash into a silent pass. If this trap fires while `sfail` is anything but a clean 0,
  # it now exits 1 itself, so a crash can never read back as green. The primary fix (below, in
  # _assert_refused) is what stops the crash from happening at all; this is the belt to that braces.
  trap 'rm -rf "$tmpd"; [ "${sfail:-1}" -eq 0 ] || exit 1' EXIT INT TERM

  ok="$tmpd/ok.conf"
  cat > "$ok" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net/jira
flavour=cloud
auth=basic
project=AB_C
state.in-progress=In Progress
state.in-progress=Doing
state.cancelled=Won't Do
field.size=label:size
field.acceptance=customfield_10077
list_cap=200
proxy=https://proxy.example.com:8080
ca_file=/etc/ssl/certs/ca.pem
cloud_id=abc-123
EOF

  # --- positive anchor ---
  if sh "$0" "$ok" >/dev/null 2>&1; then
    echo "PASS: selftest — a well-formed conf parses"
  else
    echo "FAIL: selftest — a well-formed conf was wrongly refused"; sfail=1
  fi
  gv=$(sh "$0" get base_url "$ok" 2>/dev/null || true)
  [ "$gv" = "https://ex.atlassian.net/jira" ] && echo "PASS: selftest — get base_url echoes it" \
    || { echo "FAIL: selftest — get base_url returned '$gv'"; sfail=1; }
  gp=$(sh "$0" get project "$ok" 2>/dev/null || true)
  [ "$gp" = "AB_C" ] && echo "PASS: selftest — project=AB_C accepted" \
    || { echo "FAIL: selftest — project=AB_C rejected (got '$gp')"; sfail=1; }
  gs=$(sh "$0" get state.in-progress "$ok" 2>/dev/null || true)
  [ "$gs" = "In Progress" ] && echo "PASS: selftest — the FIRST state.in-progress is the move target" \
    || { echo "FAIL: selftest — expected the first state.in-progress ('In Progress'), got '$gs'"; sfail=1; }
  # F-4: get-all returns EVERY value for a repeatable state.<kit> key, one per line, in file order —
  # `get` (above) keeps answering the FIRST only (the `move` target); get-all is the multi-status
  # reader's accessor (tracker-read.sh's tr_resolve_state_ids, T5).
  ga=$(sh "$0" get-all state.in-progress "$ok" 2>/dev/null || true)
  [ "$ga" = "In Progress
Doing" ] && echo "PASS: selftest — get-all returns EVERY state.in-progress value, in file order (F-4)" \
    || { echo "FAIL: selftest — get-all expected both values, got '$ga'"; sfail=1; }
  gs1=$(sh "$0" get-all project "$ok" 2>/dev/null || true)
  [ "$gs1" = "AB_C" ] && echo "PASS: selftest — get-all on a singleton returns its one value" \
    || { echo "FAIL: selftest — get-all singleton got '$gs1'"; sfail=1; }
  # reviewer MINOR: judge the absent-key refusal by EXACT rc (never just non-zero — a mutant that
  # exits 2 instead of 1, or that drops the "no such key" sentence, must go RED) and by stderr text.
  if ga_abs_out=$(sh "$0" get-all state.done "$ok" 2>/dev/null); then
    ga_abs_rc=0
  else
    ga_abs_rc=$?
  fi
  ga_abs_err=$(sh "$0" get-all state.done "$ok" 2>&1 >/dev/null || true)
  if [ "$ga_abs_rc" -eq 1 ] && [ -z "$ga_abs_out" ]; then
    case "$ga_abs_err" in
      *"no such key"*) echo "PASS: selftest — get-all on an absent key refuses: rc=1, no stdout, stderr names it" ;;
      *) echo "FAIL: selftest — get-all absent-key stderr missing 'no such key' (got '$ga_abs_err')"; sfail=1 ;;
    esac
  else
    echo "FAIL: selftest — get-all on an absent key must refuse with rc 1 and no stdout (got rc=$ga_abs_rc, stdout='$ga_abs_out')"; sfail=1
  fi
  # reviewer IMPORTANT (mutant M2): the get-all arm's dependency on _tc_validate_file is otherwise
  # untested — `_tc_validate_file "$file" || true` would still pass every leg above (they only ever
  # feed $ok, a valid conf). Build an INVALID conf (a second base_url= line, placed AFTER the state
  # lines so the duplicate is caught by the same validation pass that produces $_tc_kv, not by an
  # early per-line bail before the state lines are even read) and assert BOTH get-all and get refuse
  # it — rc 1, zero stdout — rather than silently scanning stale/partial $_tc_kv.
  badconf="$tmpd/badconf.conf"
  cat > "$badconf" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net/jira
flavour=cloud
auth=basic
project=AB_C
state.in-progress=In Progress
state.in-progress=Doing
state.cancelled=Won't Do
base_url=https://second.example.com
field.size=label:size
field.acceptance=customfield_10077
list_cap=200
proxy=https://proxy.example.com:8080
ca_file=/etc/ssl/certs/ca.pem
cloud_id=abc-123
EOF
  if ga_bad_out=$(sh "$0" get-all state.in-progress "$badconf" 2>/dev/null); then
    ga_bad_rc=0
  else
    ga_bad_rc=$?
  fi
  if [ "$ga_bad_rc" -eq 1 ] && [ -z "$ga_bad_out" ]; then
    echo "PASS: selftest — get-all refuses an invalid conf (duplicate base_url after the state lines) before scanning: rc=1, no stdout"
  else
    echo "FAIL: selftest — get-all on an invalid conf must refuse with rc 1 and no stdout (got rc=$ga_bad_rc, stdout='$ga_bad_out')"; sfail=1
  fi
  if g_bad_out=$(sh "$0" get state.in-progress "$badconf" 2>/dev/null); then
    g_bad_rc=0
  else
    g_bad_rc=$?
  fi
  if [ "$g_bad_rc" -eq 1 ] && [ -z "$g_bad_out" ]; then
    echo "PASS: selftest — get refuses the same invalid conf: rc=1, no stdout"
  else
    echo "FAIL: selftest — get on an invalid conf must refuse with rc 1 and no stdout (got rc=$g_bad_rc, stdout='$g_bad_out')"; sfail=1
  fi
  # BOARD-CREATE-HONOURS-FIELD-MAP: create.issuetype admits a name with a space and reads back as written.
  cit_ok="$tmpd/cit-ok.conf"
  printf 'version=1\nbackend=jira\nbase_url=https://ex.atlassian.net\nproject=AB\ncreate.issuetype=Sub Task_2-x  # the type\n' > "$cit_ok"
  cit_got=$(sh "$0" get create.issuetype "$cit_ok" 2>/dev/null || true)
  [ "$cit_got" = "Sub Task_2-x" ] && echo "PASS: selftest — create.issuetype=Sub Task_2-x parses and reads back (BOARD-CREATE-HONOURS-FIELD-MAP)" \
    || { echo "FAIL: selftest — create.issuetype was rejected or mis-read (got '$cit_got')"; sfail=1; }
  # TRACKER-REQUIRED-FIELDS-DISCOVERY: create.<token> defaults — each value form parses and get-prefix
  # reads them back in file order as key<TAB>value, create.issuetype excluded.
  cr_ok="$tmpd/create-ok.conf"
  printf 'version=1\nbackend=jira\nbase_url=https://ex.atlassian.net\nproject=AB\ncreate.issuetype=Task\nfield.size=customfield_10046\ncreate.priority=High\ncreate.customfield_10100=prompt\ncreate.customfield_10200=id:10033\ncreate.components=Web team  # note\n' > "$cr_ok"
  cr_want=$(printf 'create.priority\tHigh\ncreate.customfield_10100\tprompt\ncreate.customfield_10200\tid:10033\ncreate.components\tWeb team')
  cr_got=$(sh "$0" get-prefix create. "$cr_ok" 2>/dev/null || true)
  [ "$cr_got" = "$cr_want" ] && echo "PASS: selftest — create.<token> defaults (prompt, id:N, literal) parse; get-prefix reads them in file order, create.issuetype excluded" \
    || { echo "FAIL: selftest — get-prefix create. returned '$cr_got'"; sfail=1; }
  cr_none=$(sh "$0" get-prefix create. "$ok" 2>/dev/null) && cr_none_rc=0 || cr_none_rc=$?
  [ "$cr_none_rc" -eq 0 ] && [ -z "$cr_none" ] && echo "PASS: selftest — get-prefix on a conf with no create.<token> line prints nothing, rc 0" \
    || { echo "FAIL: selftest — get-prefix with no match (rc=$cr_none_rc out='$cr_none')"; sfail=1; }
  # the shared value/token check board.sh calls for --field: same grammar, one place
  if sh "$0" check-create customfield_10046 id:10028 2>/dev/null && ! sh "$0" check-create 1bad x 2>/dev/null && ! sh "$0" check-create size 'a|b' 2>/dev/null; then
    echo "PASS: selftest — check-create applies the create.<token> grammar to a --field pair"
  else
    echo "FAIL: selftest — check-create did not apply the grammar"; sfail=1
  fi
  # security L-7 positive: a default Jira Cloud status name ("Won't Do") carries an apostrophe and
  # must parse — refusing it would be a real adopter blocker for zero safety gain (state names are
  # resolved to ids server-side, S-8, before any query is built; the value never reaches raw JQL).
  gc=$(sh "$0" get state.cancelled "$ok" 2>/dev/null || true)
  [ "$gc" = "Won't Do" ] && echo "PASS: selftest — state.cancelled=Won't Do parses (L-7: apostrophe admitted)" \
    || { echo "FAIL: selftest — state.cancelled=Won't Do was rejected or mis-read (got '$gc')"; sfail=1; }

  # --- load-bearing negatives — each a distinct mutant; every refusal must differ from every other ---
  n=0
  _assert_refused() {  # <label> <conf-body>
    n=$((n + 1))
    f="$tmpd/neg-$n.conf"
    printf '%s\n' "$2" > "$f"
    if out=$(sh "$0" "$f" 2>&1 >/dev/null); then
      echo "FAIL: selftest — '$1' was wrongly accepted"; sfail=1
      # security NV-1: this branch MUST still set _neg_$n. Under `set -u`, the assert-differs loop
      # below dereferences EVERY _neg_$n unconditionally; leaving one unset made the loop itself
      # abort with "unbound variable" — and on macOS /bin/sh (bash 3.2) that abort is swallowed by
      # the `trap ... EXIT` cleanup, which then exits 0. The result: a wrongly-accepted mutant
      # printed its own FAIL line to stdout, the verdict line never printed, and rc was 0 (a false
      # GREEN on the very platform this file is built and reviewed on). Each wrong-accept gets its
      # OWN distinct sentinel (assert-differs must still catch two DIFFERENT broken rules that both
      # happen to wrongly accept — a shared constant here would silently defeat that).
      eval "_neg_$n=\"WRONGLY-ACCEPTED-$n\""
    else
      echo "PASS: selftest — '$1' refused: $out"
      eval "_neg_$n=\$out"
    fi
  }
  # BASE: a fully valid, required-keys-complete conf — every negative below starts from this and
  # changes/adds EXACTLY one line, so a mutant that silently accepts the bad field would otherwise
  # produce an ACCEPTED, fully valid file (caught as "wrongly accepted"), not a refusal for some
  # unrelated missing-key reason. Confounding a negative with the required-key check would let a
  # broken per-field rule hide behind an unrelated "required key" refusal (measured while building
  # this round — the first draft's single-line fixtures did exactly that).
  _base='version=1
backend=jira
base_url=https://ex.atlassian.net
project=AB'
  # a base carrying no base_url line at all, so a bad base_url can be appended as the ONLY base_url
  # line (never a SECOND one — that would trip the M-3 duplicate-key check instead and mislabel the
  # test as proving duplicate detection rather than the URL grammar under test).
  _base_nourl='version=1
backend=jira
project=AB'

  _assert_refused "http not https" "$_base_nourl
base_url=http://ex.atlassian.net"
  _assert_refused "userinfo in base_url" "$_base_nourl
base_url=https://u@ex.atlassian.net"
  _assert_refused "query in base_url" "$_base_nourl
base_url=https://ex.atlassian.net/?x=1"
  _assert_refused "illegal host char" "$_base_nourl
base_url=https://H_OST"
  _assert_refused "unknown key" "$_base
frobnicate=1"
  _assert_refused "bad project grammar" "version=1
backend=jira
base_url=https://ex.atlassian.net
project=ab1"
  _assert_refused "empty project value" "version=1
backend=jira
base_url=https://ex.atlassian.net
project="
  _assert_refused "non-https proxy" "$_base
proxy=http://proxy.example.com"
  _assert_refused "malformed line" "$_base
this-has-no-equals"
  # security M-2: backend grammar is a closed ASCII set — an uppercase byte or a shell metacharacter
  # must refuse, not pass on a lowercase FIRST character alone.
  _assert_refused "backend uppercase+metachar" "version=1
backend=Jira;x
base_url=https://ex.atlassian.net
project=AB"
  _assert_refused "backend all-metachar" "version=1
backend=!!!
base_url=https://ex.atlassian.net
project=AB"
  # security M-3: a duplicate singleton key can silently repoint the pin (get returns the first).
  _assert_refused "duplicate base_url" "$_base
base_url=https://b.example.com"
  # security M-4/L-2: a state name outside the closed §4.1 set (a typo) must refuse.
  _assert_refused "unknown state name" "$_base
state.doen=Done"
  # security M-4: a quote/backslash in a state value must refuse (it rides into a printed table and,
  # later, a tracker API call).
  _assert_refused "state value carries a quote" "$_base
state.done=Done\"; DROP TABLE x --"
  # security L-7: the apostrophe carve-out is narrow — a double-quote or backslash must STILL refuse.
  _assert_refused "state value carries a backslash (L-7 boundary)" "$_base
state.done=Done\\\\evil"
  # security M-4: the field VALUE is a closed set — an arbitrary bareword must refuse.
  _assert_refused "field value not in the closed set" "$_base
field.risk=arbitrary-bareword"
  # security M-4: the field NAME grammar — a name starting with a digit must refuse.
  _assert_refused "field name starts with a digit" "$_base
field.2fa=none"
  # security NV-1 (Fable's ten-mutant sweep, round 2): the label: prefix charset had NO negative —
  # measured to SURVIVE a mutant that dropped the `[a-z]+` check on the label: prefix entirely.
  _assert_refused "field label: prefix uppercase" "$_base
field.size=label:Size"
  # security M-4: ca_file must be an absolute path.
  _assert_refused "ca_file relative path" "$_base
ca_file=relative/path.pem"
  # security M-4: cloud_id charset is bounded (no underscore).
  _assert_refused "cloud_id illegal char" "$_base
cloud_id=abc_123"
  # reviewer M-1/M-2: leading zero on a multi-digit list_cap.
  _assert_refused "list_cap leading zero" "$_base
list_cap=01"
  # BOARD-CREATE-HONOURS-FIELD-MAP: create.issuetype is a bounded name — a quote, a leading digit, an
  # over-long value, an empty value and a repeat each refuse, each with its own sentence.
  _assert_refused "create.issuetype carries a quote" "$_base
create.issuetype=Ta\"sk"
  _assert_refused "create.issuetype starts with a digit" "$_base
create.issuetype=1Task"
  _assert_refused "create.issuetype over 40 characters" "$_base
create.issuetype=Abcdefghijabcdefghijabcdefghijabcdefghija"
  _assert_refused "create.issuetype empty" "$_base
create.issuetype="
  _assert_refused "create.issuetype repeated" "$_base
create.issuetype=Task
create.issuetype=Story"
  # TRACKER-REQUIRED-FIELDS-DISCOVERY: create.<token> — each rule refuses with its OWN sentence.
  _assert_refused "create token starts with a digit" "$_base
create.1abc=x"
  _assert_refused "create token has an illegal byte" "$_base
create.a-b=x"
  _assert_refused "create token over 64 bytes" "$_base
create.Abcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghij=x"
  _assert_refused "create value empty" "$_base
create.priority="
  _assert_refused "create value carries a tab" "$_base
create.priority=a$(printf '\t')b"
  _assert_refused "create value carries a pipe" "$_base
create.priority=a|b"
  _assert_refused "create value has a leading space" "$_base
create.priority= High"
  _assert_refused "create value has a trailing space" "$_base
create.priority=High "
  _assert_refused "create value over 80 bytes" "$_base
create.priority=Abcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghij"
  _assert_refused "create value is non-ASCII" "$_base
create.priority=H$(printf '\303\251')gh"
  _assert_refused "create id: with non-digits" "$_base
create.customfield_10100=id:12ab"
  _assert_refused "create id: empty" "$_base
create.customfield_10100=id:"
  _assert_refused "create id: over 18 digits" "$_base
create.customfield_10100=id:1234567890123456789"
  _assert_refused "create.<token> repeated" "$_base
create.priority=High
create.priority=Low"
  _assert_refused "create.<id> collides with an earlier field.size id" "$_base
field.size=customfield_10046
create.customfield_10046=XS"
  _assert_refused "create.<id> collides with a later field.risk id" "$_base
create.customfield_10047=Low
field.risk=customfield_10047"
  # security L-6/M-4: a required core key (project) missing entirely must refuse, even though every
  # OTHER line is well-formed and an empty state map (--existing) is separately legal.
  _assert_refused "missing required key (project)" 'version=1
backend=jira
base_url=https://ex.atlassian.net'
  # reviewer M-1: a lowercase-only host — an UPPERCASE byte must refuse even with no other defect.
  _assert_refused "uppercase host byte" "$_base_nourl
base_url=https://EX.atlassian.net"

  # assert-differs: every negative's refusal sentence is distinct from every other (cmp -s style —
  # a mutant that produces the SAME sentence as another proves nothing about the specific rule).
  i=1
  while [ "$i" -le "$n" ]; do
    j=$((i + 1))
    while [ "$j" -le "$n" ]; do
      eval "vi=\$_neg_$i"; eval "vj=\$_neg_$j"
      if [ "${vi:-}" = "${vj:-}" ] && [ -n "${vi:-}" ]; then
        echo "FAIL: selftest — negatives $i and $j produced the IDENTICAL refusal sentence (mutants must differ)"; sfail=1
      fi
      j=$((j + 1))
    done
    i=$((i + 1))
  done

  # security L-6: an inline `# comment` after a value is stripped, not refused (design §5's own
  # example: `base_url=https://h  # note`).
  cmf="$tmpd/comment.conf"
  cat > "$cmf" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net/jira   # our instance
project=AB
EOF
  cv=$(sh "$0" get base_url "$cmf" 2>/dev/null || true)
  [ "$cv" = "https://ex.atlassian.net/jira" ] && echo "PASS: selftest — an inline '# comment' after a value is stripped, not refused (L-6)" \
    || { echo "FAIL: selftest — inline-comment stripping did not produce the expected base_url (got '$cv')"; sfail=1; }

  # F5: refusals name the offending key + the fix.
  eval "http_msg=\$_neg_1"
  # shellcheck disable=SC2154  # assigned via eval above; shellcheck cannot see that indirection
  case "$http_msg" in
    *"base_url"*"https://"*) echo "PASS: selftest — refusal names the key + the fix (F5)" ;;
    *) echo "FAIL: selftest — refusal did not name the offending key/fix: $http_msg"; sfail=1 ;;
  esac

  # --- T3b step 0a item 1 (T1 seat L-1): field.<x> joins the duplicate-singleton refusal — a
  # SECOND field.size= line can silently repoint a dor-* flag onto a different tracker field.
  dupfield="$tmpd/dupfield.conf"
  cat > "$dupfield" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
project=AB
field.size=label:size
field.size=customfield_10099
EOF
  if sh "$0" "$dupfield" >/dev/null 2>&1; then
    echo "FAIL: selftest — a duplicate field.size= line was wrongly accepted (T3b step 0a item 1)"; sfail=1
  else
    echo "PASS: selftest — a duplicate field.size= line is refused (T3b step 0a item 1)"
  fi

  # --- T10-harden-A C3 (T5d security Low 3): two DIFFERENT field.* keys sharing the SAME value —
  # one tracker field would silently decide two DoR flags.
  samevalfield="$tmpd/samevalfield.conf"
  cat > "$samevalfield" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
project=AB
field.acceptance=customfield_10077
field.metric=customfield_10077
EOF
  if sh "$0" "$samevalfield" >/dev/null 2>&1; then
    echo "FAIL: selftest — two field.* keys sharing the same value were wrongly accepted (T10-harden-A C3)"; sfail=1
  else
    echo "PASS: selftest — two field.* keys sharing the same value are refused (T10-harden-A C3)"
  fi
  # 'none' is exempt — several DoR flags legitimately map to NO tracker field at once (a real conf
  # this codebase already ships, T5bc leg 3's own fixture: field.metric=none + field.size=none).
  noneokfield="$tmpd/noneokfield.conf"
  cat > "$noneokfield" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
project=AB
field.metric=none
field.size=none
EOF
  if sh "$0" "$noneokfield" >/dev/null 2>&1; then
    echo "PASS: selftest — two field.* keys BOTH set to 'none' stay accepted (T10-harden-A C3 exemption)"
  else
    echo "FAIL: selftest — two field.*=none keys were wrongly refused (T10-harden-A C3 exemption)"; sfail=1
  fi

  # --- T3b step 0a item 2 (T1 seat L-2): get's fallback must use an EXACT key match, not the key
  # as a regex — 'versio.' (a '.' glob-matches the 'n' in 'version') must never resolve to version.
  gdot_rc=0
  gdot_out=$(sh "$0" get 'versio.' "$ok" 2>/dev/null) || gdot_rc=$?
  if [ "$gdot_rc" -eq 1 ] && [ -z "$gdot_out" ]; then
    echo "PASS: selftest — get 'versio.' refuses, rc 1, no stdout (T3b step 0a item 2)"
  else
    echo "FAIL: selftest — get 'versio.' wrongly resolved (rc=$gdot_rc out='$gdot_out') (T3b step 0a item 2)"; sfail=1
  fi

  # --- T3b step 0a item 3 (T1 seat L-3): a refusal sentence must never carry a raw control byte
  # (an attacker-controlled key/value can embed one) — stripped in ONE place, printed via printf.
  escconf="$tmpd/esc.conf"
  printf 'version=1\nbackend=jira\nbase_url=https://ex.atlassian.net\nproject=AB\nunkn\033own=1\n' > "$escconf"
  esc_rc=0
  esc_err=$(sh "$0" "$escconf" 2>&1 >/dev/null) || esc_rc=$?
  esc_byte=$(printf '\033')
  if [ "$esc_rc" -eq 1 ] && ! printf '%s' "$esc_err" | grep -qF "$esc_byte"; then
    echo "PASS: selftest — a control byte in a refusal sentence is stripped before it reaches stderr (T3b step 0a item 3)"
  else
    echo "FAIL: selftest — a control byte leaked onto stderr (rc=$esc_rc err='$esc_err') (T3b step 0a item 3)"; sfail=1
  fi

  # --- T3b-0 fix1 S1: the grammar's [a-z]/[A-Z] bracket ranges are locale-collated, not byte
  # ranges — under a real caller's LC_ALL=en_US.UTF-8 an uppercase byte can fall inside [a-z] and
  # wrongly pass. Fork a FRESH process per shell (never inherited) so this pins the fix, not the
  # harness's own locale. SKIP (not FAIL) a shell this box does not have.
  s1host="$tmpd/s1-uphost.conf"
  cat > "$s1host" <<'EOF'
version=1
backend=jira
base_url=https://EX.atlassian.net
project=AB
EOF
  s1field="$tmpd/s1-upfield.conf"
  cat > "$s1field" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
project=AB
field.size=label:Size
EOF
  for _s1sh in sh dash bash; do
    if ! command -v "$_s1sh" >/dev/null 2>&1; then
      echo "SKIP: selftest — S1 locale leg: $_s1sh not present on this box"
      continue
    fi
    if env LC_ALL=en_US.UTF-8 "$_s1sh" "$0" "$s1host" >/dev/null 2>&1; then
      echo "FAIL: selftest — S1: $_s1sh under LC_ALL=en_US.UTF-8 wrongly accepted an uppercase host"; sfail=1
    else
      echo "PASS: selftest — S1: $_s1sh under LC_ALL=en_US.UTF-8 refuses an uppercase host"
    fi
    if env LC_ALL=en_US.UTF-8 "$_s1sh" "$0" "$s1field" >/dev/null 2>&1; then
      echo "FAIL: selftest — S1: $_s1sh under LC_ALL=en_US.UTF-8 wrongly accepted an uppercase label: prefix"; sfail=1
    else
      echo "PASS: selftest — S1: $_s1sh under LC_ALL=en_US.UTF-8 refuses an uppercase label: prefix"
    fi
  done

  # --- T3b-0 fix1 S2 (security Medium — the strip): a key carrying an invalid byte (\377) or a raw
  # C1 byte (0x9B) must not truncate the sentence or leak `tr: Illegal byte sequence` — the fix
  # clause must survive, and no byte outside printable ASCII must reach stderr.
  s2conf1="$tmpd/s2-377.conf"
  printf 'version=1\nbackend=jira\nbase_url=https://ex.atlassian.net\nproject=AB\nunk\377n=1\n' > "$s2conf1"
  s2conf2="$tmpd/s2-9b.conf"
  printf 'version=1\nbackend=jira\nbase_url=https://ex.atlassian.net\nproject=AB\nunk\233n=1\n' > "$s2conf2"
  for _s2f in "$s2conf1" "$s2conf2"; do
    s2_rc=0
    s2_err=$(sh "$0" "$_s2f" 2>&1 >/dev/null) || s2_rc=$?
    # E1: the FAIL branch below must never echo `$s2_err` raw either — a broken fix means it MAY
    # still carry the very byte (ESC/0x9B/0xFF) this leg exists to keep off a terminal/log, so the
    # diagnostic uses the same printable-ASCII-cleaned copy the assertion itself computes.
    s2_clean=$(printf '%s' "$s2_err" | tr -cd '\40-\176')
    s2_clean_len=$(printf '%s' "$s2_clean" | wc -c)
    s2_raw_len=$(printf '%s' "$s2_err" | wc -c)
    if [ "$s2_rc" -eq 1 ] \
      && printf '%s' "$s2_err" | grep -qF 'fix: remove it' \
      && ! printf '%s' "$s2_err" | grep -qF 'tr:' \
      && [ "$s2_clean_len" -eq "$s2_raw_len" ]; then
      echo "PASS: selftest — S2: a key carrying an invalid/C1 byte ($_s2f) refuses, rc 1, fix clause intact, no tr: leak, no byte outside printable ASCII"
    else
      echo "FAIL: selftest — S2: bad-byte key ($_s2f) rc=$s2_rc err(cleaned)='$s2_clean'"; sfail=1
    fi
  done

  # --- T3b-0 fix1 S3 (security Low — length): an unbounded interpolated fragment must not produce
  # an unbounded stderr line (a 200 KB key previously produced a ~200 KB line).
  s3key=$(awk 'BEGIN{for(i=0;i<200000;i++) printf "a"}')
  s3conf="$tmpd/s3-longkey.conf"
  printf 'version=1\nbackend=jira\nbase_url=https://ex.atlassian.net\nproject=AB\n%s=1\n' "$s3key" > "$s3conf"
  s3_rc=0
  s3_err=$(sh "$0" "$s3conf" 2>&1 >/dev/null) || s3_rc=$?
  s3_len=$(printf '%s' "$s3_err" | wc -c)
  if [ "$s3_rc" -eq 1 ] && [ "$s3_len" -lt 1000 ]; then
    echo "PASS: selftest — S3: a 200 KB key produces a BOUNDED refusal line ($s3_len bytes), not a ~200 KB line"
  else
    echo "FAIL: selftest — S3: a 200 KB key produced an unbounded refusal line (rc=$s3_rc len=$s3_len)"; sfail=1
  fi

  # --- T3b-core step 0b (carried T3b-0 fix1 quality minor): `_tc_say_refusal`'s printable-ASCII
  # strip runs over the WHOLE sentence, including the kit's OWN authored text — a duplicate-key
  # refusal's own dash must survive untouched, not be stripped along with an untrusted fragment's bytes.
  dupconf="$tmpd/dup-base-url.conf"
  printf 'version=1\nbackend=jira\nbase_url=https://ex.atlassian.net\nbase_url=https://ex2.atlassian.net\nproject=AB\n' > "$dupconf"
  dup_err=$(sh "$0" "$dupconf" 2>&1 >/dev/null) || true
  dup_exp="refused: base_url is set more than once (a duplicate singleton key can silently repoint the pin - remove all but one)"
  if [ "$dup_err" = "$dup_exp" ]; then
    echo "PASS: selftest — the kit's own fixed-sentence dash survives a refusal untouched (T3b-core step 0b)"
  else
    echo "FAIL: selftest — the kit's own fixed-sentence dash did not survive (got '$dup_err')"; sfail=1
  fi

  # --- T3b-core step 0b (carried T3b-0 fix1 quality minor): `_tc_disp` truncates ANY fragment to 64
  # bytes — right for a tracker-controlled key/value, wrong for the CALLER's own conf file PATH
  # (not untrusted the same way) — a long path must appear in full in a "no such key" refusal.
  longdir="$tmpd/a-rather-long-directory-name-chosen-to-exceed-the-sixty-four-char-bound"
  mkdir -p "$longdir"
  longconf="$longdir/tracker.conf"
  printf 'version=1\nbackend=jira\nbase_url=https://ex.atlassian.net\nproject=AB\n' > "$longconf"
  longpath_err=$(sh "$0" get missing_key "$longconf" 2>&1 >/dev/null) || true
  if printf '%s' "$longpath_err" | grep -qF "$longconf"; then
    echo "PASS: selftest — the caller's own (long) conf path is never truncated in a refusal (T3b-core step 0b)"
  else
    echo "FAIL: selftest — a long conf path was truncated in the refusal (got '$longpath_err')"; sfail=1
  fi

  rm -rf "$tmpd"; trap - EXIT INT TERM
  [ "$sfail" -eq 0 ] && { echo "OK: tracker-conf selftest"; return 0; } || { echo "FAIL: tracker-conf selftest"; return 1; }
}

# --- CLI ---------------------------------------------------------------------------------------

case "${1:-}" in
  --selftest)
    _tc_selftest; exit $? ;;
  get)
    [ $# -eq 3 ] || { echo "usage: tracker-conf.sh get <key> <conf-file>" >&2; exit 2; }
    key=$2; file=$3
    if ! _tc_validate_file "$file"; then _tc_say_refusal "$_tc_reason"; exit 1; fi
    # T3b step 0a item 2: an EXACT key match — a prior `grep` fallback treated $key as a REGEX
    # (a bare '.' glob-matches any byte), so `get 'versio.'` wrongly resolved via 'version'. A
    # found-flag (the get-all idiom below) replaces it; a found-but-empty first value must still
    # print (rc 0), never fall through to the absent-key refusal.
    got=''; _tc_g_found=0
    while IFS="	" read -r k v; do
      [ -n "$k" ] || continue
      if [ "$k" = "$key" ] && [ "$_tc_g_found" -eq 0 ]; then got=$v; _tc_g_found=1; fi
    done <<EOF_KV
$_tc_kv
EOF_KV
    if [ "$_tc_g_found" -eq 1 ]; then
      printf '%s\n' "$got"; exit 0
    fi
    # T3b-core step 0b: $file is the CALLER's own path, not a tracker/PR-controlled fragment —
    # `_tc_disp`'s 64-char bound belongs on $key only; a long, legitimate path must show in full.
    _tc_say_refusal "refused: no such key '$(_tc_disp "$key")' in $file"; exit 1 ;;
  get-all)
    # F-4: same arity + validation as `get`, but print EVERY value whose key matches, one per
    # line, in file order (never just the first) — the multi-status reader's accessor.
    [ $# -eq 3 ] || { echo "usage: tracker-conf.sh get-all <key> <conf-file>" >&2; exit 2; }
    key=$2; file=$3
    if ! _tc_validate_file "$file"; then _tc_say_refusal "$_tc_reason"; exit 1; fi
    _tc_ga_found=0
    while IFS="	" read -r k v; do
      [ -n "$k" ] || continue
      if [ "$k" = "$key" ]; then printf '%s\n' "$v"; _tc_ga_found=1; fi
    done <<EOF_KV
$_tc_kv
EOF_KV
    if [ "$_tc_ga_found" -eq 1 ]; then exit 0; fi
    _tc_say_refusal "refused: no such key '$(_tc_disp "$key")' in $file"; exit 1 ;;
  get-prefix)
    # TRACKER-REQUIRED-FIELDS-DISCOVERY: every validated `<prefix>*` line as `key<TAB>value`, in file
    # order, create.issuetype excluded (it is the type, not a field default). No match is NOT an error
    # (rc 0, nothing printed): "this project sets no create defaults" is a normal state.
    [ $# -eq 3 ] || { echo "usage: tracker-conf.sh get-prefix <prefix> <conf-file>" >&2; exit 2; }
    prefix=$2; file=$3
    if ! _tc_validate_file "$file"; then _tc_say_refusal "$_tc_reason"; exit 1; fi
    while IFS="	" read -r k v; do
      [ -n "$k" ] || continue
      [ "$k" != create.issuetype ] || continue
      case "$k" in "$prefix"*) printf '%s\t%s\n' "$k" "$v" ;; esac
    done <<EOF_KV
$_tc_kv
EOF_KV
    exit 0 ;;
  check-create)
    # The ONE create.<token>=<value> grammar, offered to a caller that validates a pair that is not in
    # the conf (board.sh --field). rc 0 ok; rc 1 + the refusal sentence on stderr.
    [ $# -eq 3 ] || { echo "usage: tracker-conf.sh check-create <token> <value>" >&2; exit 2; }
    if _tc_create_token_ok "create.$2" && _tc_create_value_ok "create.$2" "$3"; then exit 0; fi
    _tc_say_refusal "$_tc_reason"; exit 1 ;;
  '')
    echo "usage: tracker-conf.sh <conf-file> | get <key> <conf-file> | get-all <key> <conf-file> | get-prefix <prefix> <conf-file> | check-create <token> <value> | --selftest" >&2; exit 2 ;;
  *)
    [ $# -eq 1 ] || { echo "usage: tracker-conf.sh <conf-file> | get <key> <conf-file> | get-all <key> <conf-file> | get-prefix <prefix> <conf-file> | check-create <token> <value> | --selftest" >&2; exit 2; }
    if _tc_validate_file "$1"; then exit 0; else _tc_say_refusal "$_tc_reason"; exit 1; fi ;;
esac
