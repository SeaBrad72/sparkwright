#!/bin/sh
# tracker-read.sh — the backend-neutral trusted reader (TBG-JIRA-READER, design
# docs/architecture/2026-09-19-tracker-backed-governance-design.md §4.3, §6a S-2/S-6/S-10, §8).
# THE ONLY code in the kit that ever holds the tracker credential. Reads .kit/tracker.conf
# THROUGH scripts/tracker-conf.sh (F4 — never a second parser); resolves the credential
# (KIT_TRACKER_USER/KIT_TRACKER_TOKEN, JIRA_* aliases); compares the local pin against the
# origin/<default> copy (S-2) and refuses to send the token on a mismatch; dispatches by backend
# token to scripts/tracker-<backend>.sh (J1 — carries no jira string itself); validates the
# adapter's return against the closed §4.3 grammar and writes the read record.
#
# What it changes: writes ONLY to the record path given as an explicit argument (never inherited
# from env, S-10) — never touches the board, never writes anywhere else; truncated at entry, even
# on a refused run; refuses a record path that is the conf or not a record.
#
# Guardrails: S-2 trust-on-first-use pin compare refuses the token send on mismatch (no request);
# S-6 failure sentences carry no tracker text (a status id, never a name); S-10 --selftest refuses
# when a token env var is set and never writes a caller-supplied path, bounded against recursion
# even under a mutant that removes the refusal (L-2); §8 every emitted id is grammar-checked
# (never a bare C0/DEL strip-and-pass — a grammar failure REFUSES, it never silently launders the
# bytes into a bound record, M-3); L-8 an unresolvable state yields verdict unverified, never
# bound; H-1 the adapter's env-steerable HTTP-client override is unset before every dispatch; H-3 a
# failed/unparsable credential probe writes `credential unverified` and downgrades the verdict to
# unverified — never `ok`+`bound` by default; M-2 the state map is read from the PINNED CONF's
# own `state.*` keys, never from an environment variable (an env-steered map would let a caller
# rewrite the meaning of a tracker response without touching the conf, defeating S-10/T9); the
# `pin` digests the FULL VALIDATED CONF CONTENTS, not just base_url (reviewer M1).
#
# Usage:
#   tracker-read.sh <conf-file> <origin-conf-file-or-'-'> <record-path> <requested-id> <head-sha> [state...]
#   tracker-read.sh --selftest
set -eu
# 0a (T5a1 carried M-1): a caller's locale must not change a grammar check's verdict.
LC_ALL=C; export LC_ALL

TR_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TR_CONF_SH="$TR_ROOT/scripts/tracker-conf.sh"
TR_STATES="backlog ready in-progress in-review released done blocked cancelled"
# P-1: the seam refuses a record over 512 lines/64 KiB (backlog-lib.sh M-2) — this reader's own
# budget catches it FIRST, before the record is even written.
TR_ROW_BUDGET=480
# T5bc fix1 B1(b)/T5d step 0: a byte cap BELOW the seam's own 64 KiB, DECORATION-AWARE now that
# dor-risk has landed — closes the case where the LINE count (and the pre-decoration byte count)
# stay in budget but the DECORATED bytes bust the seam's own 512-line/64 KiB cap (backlog-lib.sh
# M-2) after tr_apply_flags runs. Arithmetic (every figure the max the grammar allows):
#   header (8 lines, 64-hex pin+head, a 32-char id, "credential over-privileged") = 282 B
#   (T10-harden-A R1: "over-privileged" is 5 B longer than "unverified" — that IS a
#   reachable credential value on a bound record, S-11/T5, so it is the true worst case)
#   the subject's own row (32-char id, "in-progress", claimed+4 dor-*=yes)   = 127 B
#   fixed total                                                             = 409 B
#   decoration on up to 480 non-subject ready rows, 4 dor-*=yes (60 B/row)  = 28,800 B
#   64 KiB (65,536 B) - 409 B - 28,800 B = 36,327 B is the MOST the pre-decoration
#   rows+lists blob can be. Set to 36000 B, a 327 B margin.
TR_ROW_BYTE_BUDGET=36000

# --- §8: keep only printable ASCII — SENTENCE USE ONLY (never to launder an id into a bound
# record). Step 0 (security Low): also strips C1/high bytes (0x80-0xFF), which the prior
# C0/DEL-only strip left untouched.
tr_strip_c0() {
  printf '%s' "$1" | tr -cd '\040-\176'
}

# step 0 (security Low): the "outside §4.1" sentence — when stripping CHANGED the value (a hostile
# byte could make it look valid), omit the token and say control bytes were removed instead.
tr_state_outside_sentence() {
  _tsos_raw=$1; _tsos_stripped=$(tr_strip_c0 "$_tsos_raw")
  if [ "$_tsos_stripped" = "$_tsos_raw" ]; then
    printf "refused: state '%s' outside §4.1" "$_tsos_stripped"
  else
    printf 'refused: state outside §4.1 (control bytes removed)'
  fi
}

# --- credential resolution --------------------------------------------------------------------
tr_resolve_user() { printf '%s' "${KIT_TRACKER_USER:-${JIRA_EMAIL:-}}"; }
tr_resolve_token() { printf '%s' "${KIT_TRACKER_TOKEN:-${JIRA_TOKEN:-}}"; }

# --- S-2: local pin vs origin/<default> pin compare. Refuses to send the token on a mismatch. --
tr_pin_check() {
  _local=$1; _origin=$2
  [ "$_origin" = "-" ] && return 0
  [ -f "$_origin" ] || return 0
  _lb=$(sh "$TR_CONF_SH" get base_url "$_local" 2>/dev/null || true)
  _lp=$(sh "$TR_CONF_SH" get project "$_local" 2>/dev/null || true)
  _ob=$(sh "$TR_CONF_SH" get base_url "$_origin" 2>/dev/null || true)
  _op=$(sh "$TR_CONF_SH" get project "$_origin" 2>/dev/null || true)
  if [ "$_lb" != "$_ob" ] || [ "$_lp" != "$_op" ]; then
    echo "refused: local .kit/tracker.conf pin diverges from origin's — token not sent (S-2)" >&2
    return 1
  fi
  return 0
}

# --- §4.3 grammar checks --------------------------------------------------------------------
tr_valid_id() {
  # M-3 hardening: a shell glob bracket-class matches exactly ONE character; the trailing `*`
  # after `[A-Z0-9-]` is an INDEPENDENT wildcard matching anything at all, not "repeat this
  # class" — so `[A-Z0-9][A-Z0-9-]*` alone wrongly accepted "AB-1<ESC><DEL>". The first-char
  # check below is safe (single bracket class); completeness needs the NEGATED whole-string form.
  case "$1" in
    [A-Z0-9]*) : ;;
    *) return 1 ;;
  esac
  case "$1" in
    *[!A-Z0-9-]*) return 1 ;;
  esac
  return 0
}
tr_valid_state() {
  # F-2: a whole-token grammar gate BEFORE membership — the membership check below is a substring
  # match over the space-joined vocabulary, so an arg spanning two adjacent words (e.g. 'ready
  # in-progress', one caller-quoted argument) would otherwise match as a literal substring of the
  # list. Reject anything that is not itself a single lowercase-hyphen token first.
  case "$1" in ''|*[!a-z-]*) return 1 ;; esac
  case " $TR_STATES " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}
# H-2/F-11: the head-sha grammar — exactly 40 or 64 lowercase hex chars, not all-zero. The head is
# a CALLER ASSERTION the reader cannot verify (it binds the read to a sha, it does not prove
# tracker-state-at-that-sha); only the trusted job may assert it (N-3).
tr_valid_head() {
  _v=$1
  _l=${#_v}
  [ "$_l" -eq 40 ] || [ "$_l" -eq 64 ] || return 1
  case "$_v" in *[!0-9a-f]*) return 1 ;; esac
  case "$_v" in *[!0]*) : ;; *) return 1 ;; esac
  return 0
}
# a bounded, printable-ASCII charset for a tracker-reported status NAME (before it is compared
# against the conf's own state.* values) — apostrophe admitted (a default Jira status is
# literally "Won't Do", mirroring tracker-conf.sh's L-7 carve-out), quote/backslash/control not.
tr_valid_statusname() {
  _v=$1
  [ -n "$_v" ] || return 1
  _l=${#_v}
  [ "$_l" -le 60 ] || return 1
  _noapos=$(printf '%s' "$_v" | tr -d "'")
  case "$_noapos" in *[!A-Za-z0-9" "_-]*) return 1 ;; esac
  return 0
}

# --- L-1: the backend token grammar — the WHOLE string, not just its first character -----------
tr_valid_backend() {
  case "$1" in ''|*[!a-z0-9_-]*) return 1 ;; *) return 0 ;; esac
}

# --- dispatch by backend token to scripts/tracker-<backend>.sh (J1 — neutral) ------------------
tr_adapter_path() {
  tr_valid_backend "$1" || return 1
  printf '%s/scripts/tracker-%s.sh' "$TR_ROOT" "$1"
}

# --- M-2: resolve a tracker status NAME to a §4.1 state token from the PINNED CONF's own
# state.<kit-state>=<jira-name> lines — never from an environment variable (S-10/T9). -----------
tr_state_from_name() {
  _conf=$1; _name=$2
  tr_valid_statusname "$_name" || return 1
  for _s in $TR_STATES; do
    _v=$(sh "$TR_CONF_SH" get "state.$_s" "$_conf" 2>/dev/null || true)
    if [ -n "$_v" ] && [ "$_v" = "$_name" ]; then
      printf '%s' "$_s"
      return 0
    fi
  done
  return 1
}

# --- H-3/S-11: the credential probe, fails CLOSED. Prints ok|over-privileged|unverified. --------
tr_probe_credential() {
  # 0e (m-2): unset first — this helper can be called directly, not only via tr_read's own unset.
  unset _TJ_CURL_BIN 2>/dev/null || true
  _adapter=$1; _base=$2; _flavour=$3; _project=$4
  _permout=$(sh "$_adapter" permissions "$_base" "$_flavour" "$_project" 2>/dev/null) || _permout=unverified
  case "$_permout" in
    over-privileged) printf 'over-privileged' ;;
    ok) printf 'ok' ;;
    *) printf 'unverified' ;;
  esac
}

# --- reviewer M1: the pin digest covers the FULL validated conf contents, not just base_url -----
tr_pin_digest() {
  _conf=$1
  { command -v sha256sum >/dev/null 2>&1 && sha256sum || shasum -a 256; } < "$_conf" | awk '{print $1}'
}

# --- T5b1 leg 1: assignee-present -> claimed=yes|no, a CLOSED case — anything else (absent,
# malformed) omits the flag entirely rather than defaulting (F-10; the required-mutant guard on
# leg 1c pins this: an absent field must never fall through to "yes").
tr_claimed_value() {
  case "$1" in
    true) printf 'yes' ;;
    false) printf 'no' ;;
    *) printf '' ;;
  esac
}

# --- T5b1/T5bc: appends "<name>=<value>" to the accumulated header-row token string with a single
# ASCII space, empty <value> a no-op — the ONE join point for every subject-row token (claimed,
# dor-acceptance, dor-metric, dor-size), extracted so tr_read stays under the line guideline (item 13).
# tr_append_hdrflag <existing> <name> <value>
tr_append_hdrflag() {
  _tahf_existing=$1; _tahf_name=$2; _tahf_value=$3
  [ -n "$_tahf_value" ] || { printf '%s' "$_tahf_existing"; return 0; }
  if [ -n "$_tahf_existing" ]; then
    printf '%s %s=%s' "$_tahf_existing" "$_tahf_name" "$_tahf_value"
  else
    printf '%s=%s' "$_tahf_name" "$_tahf_value"
  fi
}

# --- M-2/L-8: resolve the status NAME to a §4.1 token from the PINNED CONF's own state.* map —
# never from an environment variable. An unresolvable name -> unverified, never bound. Sets
# $_state/$_verdict DIRECTLY (called directly, never via $(...) — mirrors tr_load_conf's own
# convention). Extracted so tr_read stays under the line guideline (item 13).
# tr_resolve_verdict <conf> <statusname> <statusid>
tr_resolve_verdict() {
  _trv_conf=$1; _trv_statusname=$2; _trv_statusid=$3
  if _state=$(tr_state_from_name "$_trv_conf" "$_trv_statusname"); then
    _verdict=bound
  else
    echo "unverified: status id $_trv_statusid resolves to no known state" >&2
    _verdict=unverified
    _state=""
  fi
  return 0
}

# --- H-3/S-11: the credential probe, folded into the same batched read (one probe per run). A
# failed/unparsable probe writes credential=unverified AND downgrades the verdict — a `bound`
# record must never coexist with an unverified credential. Sets $_cred and may downgrade $_verdict
# DIRECTLY. Extracted so tr_read stays under the line guideline (item 13).
# T5b1 debugging note: this function's LAST statement must never be a bare `[ cond ] && cmd` whose
# condition can be false — under `set -e`, a FUNCTION CALLED as a plain statement aborts the whole
# script if its OWN return status (= its last command's status) is non-zero, even though the exact
# same `[ cond ] && cmd` line was previously safe INLINE (the -e AND-OR-list exemption applies
# per-statement, but a function call's overall exit status is not exempt) — measured live: this
# regressed ~19 unrelated legs when first extracted without the explicit `return 0` below.
# tr_resolve_cred <adapter> <base> <flavour> <project>
tr_resolve_cred() {
  _cred=$(tr_probe_credential "$1" "$2" "$3" "$4")
  [ "$_cred" = "unverified" ] && _verdict=unverified
  return 0
}

# --- the §4.3 record writer, extracted so tr_read stays under the line guideline (item 13) ------
# T5a2L: ${11} is the raw tr_read_lists/tr_filter_list_races blob (T5a2M: R4/R6 already gated its
# list lines upstream); any row for the SAME key as the header is dropped (design §3b: the subject
# never gets a second row). T5b1: ${12} is the subject's own extra header-row tokens (claimed=,
# dor-size=), space-joined, appended after `state=` — empty when none resolved.
tr_write_record() {
  _record=$1; _backend=$2; _pindigest=$3; _head=$4; _reqid=$5; _day=$6; _cred=$7; _verdict=$8; _key=$9; _state=${10}; _extra=${11:-}; _hdrflags=${12:-}
  _wr_filtered=""
  if [ -n "$_extra" ]; then
    # Q5 (quality m5): rc 1 (no match — every extra line was the subject's own, correctly dropped)
    # is fine; any OTHER rc means grep itself errored — refuse rather than silently write nothing.
    # T5a2M leg 9: 2>/dev/null — grep's own diagnostic on a hostile key never reaches stderr.
    _wr_filtered=$(printf '%s\n' "$_extra" | grep -v "^row $_key " 2>/dev/null); _wr_grc=$?
    case "$_wr_grc" in
      0|1) ;;
      *) echo "refused: tr_write_record could not filter the subject's row (grep rc=$_wr_grc)" >&2; return 1 ;;
    esac
  fi
  {
    echo "kit-tracker-read 1"
    echo "backend $_backend"
    echo "pin sha256:$_pindigest"
    echo "head $_head"
    echo "requested $_reqid"
    echo "read-day $_day"
    echo "credential $_cred"
    echo "verdict $_verdict"
    if [ "$_verdict" = "bound" ]; then
      if [ -n "$_hdrflags" ]; then
        printf 'row %s state=%s %s\n' "$_key" "$_state" "$_hdrflags"
      else
        echo "row $_key state=$_state"
      fi
      [ -n "$_wr_filtered" ] && printf '%s\n' "$_wr_filtered"
    fi
  } > "$_record"
  return 0
}

# H-2/F-11/§4.1: validate the head-sha grammar and the requested states (TR_STATES membership, no
# duplicates) BEFORE any conf load or adapter dispatch. Extracted so tr_read stays closer to the
# line guideline (item 13's convention, mirroring tr_write_record's own extraction above).
# tr_validate_head_states <head-sha> [state...]
tr_validate_head_states() {
  _vhs_head=$1; shift
  tr_valid_head "$_vhs_head" || { echo "refused: malformed head grammar" >&2; return 1; }
  _vhs_seen=""
  for _vhs_st in "$@"; do
    tr_valid_state "$_vhs_st" || { tr_state_outside_sentence "$_vhs_st" >&2; echo >&2; return 1; }
    case " $_vhs_seen " in
      *" $_vhs_st "*) echo "refused: duplicate state '$(tr_strip_c0 "$_vhs_st")'" >&2; return 1 ;;
    esac
    _vhs_seen="$_vhs_seen $_vhs_st"
  done
  return 0
}

# F-5 hardening: refuse — WITHOUT touching the file — BEFORE F-10's truncate-at-entry, when the
# record path equals (as a string) the conf/origin-conf path, or already holds non-record content
# (a non-empty file whose first line isn't the §4.3 magic). Extracted so tr_read stays at its line
# guideline.
# T4 re-review N-1: the equality check above is a STRING comparison — it catches only an identical
# spelling of the conf/origin-conf path. An alias of the same file reached by a different string
# (a relative path, a symlink, a hardlink) is NOT caught by that comparison; it is caught instead,
# independently, by the not-a-record check below (an alias of a valid conf can never start with
# the record's own magic line, `kit-tracker-read 1`, since a valid conf's first line is `version=1`
# or a comment/blank).
# tr_record_safe <record> <conf> <origin-or-'-'>
tr_record_safe() {
  _rs_record=$1; _rs_conf=$2; _rs_origin=$3
  if [ "$_rs_record" = "$_rs_conf" ] || { [ "$_rs_origin" != "-" ] && [ "$_rs_record" = "$_rs_origin" ]; }; then
    echo "refused: record path is the conf (or origin-conf) path" >&2; return 1
  fi
  if [ -s "$_rs_record" ] && [ "$(head -n 1 "$_rs_record" 2>/dev/null || true)" != "kit-tracker-read 1" ]; then
    echo "refused: record path holds non-record content — refusing to truncate" >&2; return 1
  fi
  return 0
}

# --- conf-load helper: validates the conf, loads its fields, resolves the credential, and
# pin-checks it — extracted so tr_read stays under the line guideline (T4 M-2 condition). Sets
# the globals _backend/_base/_project/_flavour/_auth/_user/_token DIRECTLY on success (fix1
# I-1/I-2/I-3: called directly by tr_read, never inside a $(...) command substitution — a packed
# TAB-joined line handed through IFS=<TAB> read collapses an empty field, per POSIX field-splitting
# rules a run of IFS *whitespace* characters, tab included, delimits as ONE separator regardless of
# what IFS is set to — so an empty user field silently shifted the token into the user slot; and
# routing the fields through a $(...)/here-doc round trip put the token on disk on macOS sh = bash
# 3.2, which materializes here-doc bodies as temp files). Mirrors tr_read's own rc contract on
# refusal (1 = refused, 2 = unverified/no-token).
# tr_load_conf <conf> <origin-conf|->
tr_load_conf() {
  _lc_conf=$1; _lc_origin=$2
  if ! sh "$TR_CONF_SH" "$_lc_conf" >/dev/null 2>&1; then
    echo "refused: no pin — .kit/tracker.conf is missing or invalid" >&2
    return 1
  fi
  _backend=$(sh "$TR_CONF_SH" get backend "$_lc_conf" 2>/dev/null || true)
  _base=$(sh "$TR_CONF_SH" get base_url "$_lc_conf" 2>/dev/null || true)
  _project=$(sh "$TR_CONF_SH" get project "$_lc_conf" 2>/dev/null || true)
  _flavour=$(sh "$TR_CONF_SH" get flavour "$_lc_conf" 2>/dev/null || echo cloud)
  _auth=$(sh "$TR_CONF_SH" get auth "$_lc_conf" 2>/dev/null || echo basic)

  _user=$(tr_resolve_user); _token=$(tr_resolve_token)
  if [ -z "$_token" ]; then
    echo "unverified: no token — KIT_TRACKER_TOKEN not set" >&2
    return 2
  fi

  # S-2: refuse to send the token at all on a pin mismatch — checked BEFORE any dispatch.
  tr_pin_check "$_lc_conf" "$_lc_origin" || return 1
  return 0
}

# --- adapter-read helper: dispatches get-issue and returns its three §4.3 fields, grammar-checked
# (M-3/H-5) — extracted so tr_read stays under the line guideline (T4 M-2 condition). Sets the
# globals _key/_statusid/_statusname DIRECTLY on success (fix1 I-1/I-2: called directly by
# tr_read, never inside a $(...) substitution — see tr_load_conf's own comment for why). The
# unset (0e) lives in the function itself, first statement, below.
# tr_adapter_read <adapter> <base> <flavour> <project> <reqid>
tr_adapter_read() {
  # 0e (m-2): unset first — this helper can be called directly, not only via tr_read's own unset.
  unset _TJ_CURL_BIN 2>/dev/null || true
  _ar_adapter=$1; _ar_base=$2; _ar_flavour=$3; _ar_project=$4; _ar_reqid=$5

  _ar_out=$(sh "$_ar_adapter" get-issue "$_ar_base" "$_ar_flavour" "$_ar_project" "$_ar_reqid" 2>/dev/null) || {
    _ar_rc=$?
    if [ "$_ar_rc" -eq 2 ]; then echo "unverified: adapter could not verify the read" >&2; return 2; fi
    echo "refused: adapter refused the read" >&2; return 1
  }
  _key=$(printf '%s\n' "$_ar_out" | awk -F'\t' '$1=="key"{print $2}')
  _statusid=$(printf '%s\n' "$_ar_out" | awk -F'\t' '$1=="status-id"{print $2}')
  _statusname=$(printf '%s\n' "$_ar_out" | awk -F'\t' '$1=="status-name"{print $2}')
  # T5b1 leg 1: assignee-present is OPTIONAL on the adapter's own output — absent/malformed never
  # defaults to a value, tr_claimed_value's closed case below omits the flag instead (F-10).
  _assignpresent=$(printf '%s\n' "$_ar_out" | awk -F'\t' '$1=="assignee-present"{print $2}')

  # M-3: grammar-check the adapter-returned key. A grammar failure REFUSES outright — the C0/DEL
  # strip helper is for SENTENCE text only, never to launder a hostile key into a bound record.
  if ! tr_valid_id "$_key"; then
    echo "refused: adapter returned a key that failed the id grammar" >&2
    return 1
  fi
  # H-5: status id itself must be grammar-clean too (defence in depth on top of the adapter's own
  # check) before it is ever used in a sentence.
  case "$_statusid" in
    ''|*[!0-9]*) echo "unverified: adapter returned a status id that failed grammar" >&2; return 2 ;;
  esac
  return 0
}

# --- 0c (L-3): validate a whole status-ids catalogue (adapter TSV: id<TAB>name per line) before
# any of it is trusted — every id passes the closed gate (^[1-9][0-9]*$, no leading zero) AND no
# id carries two different names (a corrupt/ambiguous catalogue refuses outright). Extracted so
# tr_resolve_state_ids stays under the line guideline.
# tr_valid_statusids <catalogue-tsv>
tr_valid_statusids() {
  printf '%s\n' "$1" | awk -F'\t' '$1!~/^[1-9][0-9]*$/{exit 1}' || return 1
  printf '%s\n' "$1" | awk -F'\t' '{ k=$1 SUBSEP; if ((k in seen) && (seen[k] "") != ($2 "")) exit 1; seen[k]=$2 "" }' || return 1
  return 0
}

# --- F-4: multi-status resolution — a kit state may map onto one or more tracker status names
# (tracker-conf.sh get-all state.<kit>); resolve EVERY mapped name to an id via ONE status-ids
# read. stdout = the ids, one per line, `LC_ALL=C sort -n`.
# tr_resolve_state_ids <conf> <adapter> <base> <flavour> <project> <state>
tr_resolve_state_ids() {
  # 0e (m-2) fix1 F2: unset as OUR OWN first statement, before any validation or dispatch — this
  # helper can be called directly, not only via tr_read's own unset.
  unset _TJ_CURL_BIN 2>/dev/null || true
  _rsi_conf=$1; _rsi_adapter=$2; _rsi_base=$3; _rsi_flavour=$4; _rsi_project=$5; _rsi_state=$6
  # 0d (m-1): validate the state grammar BEFORE it reaches a conf key or a sentence — a hostile
  # byte (e.g. ESC) must never be echoed raw.
  tr_valid_state "$_rsi_state" || { tr_state_outside_sentence "$_rsi_state" >&2; echo >&2; return 1; }
  _rsi_names=$(sh "$TR_CONF_SH" get-all "state.$_rsi_state" "$_rsi_conf" 2>/dev/null) || {
    echo "unverified: no state.$_rsi_state mapping in the conf" >&2
    return 2
  }
  _rsi_statusids=$(sh "$_rsi_adapter" status-ids "$_rsi_base" "$_rsi_flavour" "$_rsi_project" 2>/dev/null) || {
    echo "unverified: adapter status-ids failed" >&2
    return 2
  }
  # H-5-style defence in depth: the WHOLE catalogue must pass the closed-gate + no-ambiguity check
  # before any of it is trusted — even for a name this state does not itself need — mirroring
  # tr_adapter_read's own status-id grammar check on the single-issue path.
  tr_valid_statusids "$_rsi_statusids" || {
    echo "unverified: adapter returned an invalid status-ids catalogue" >&2
    return 2
  }
  _rsi_ids=""
  while IFS= read -r _rsi_wantname; do
    [ -n "$_rsi_wantname" ] || continue
    # R3 (fix1 I-4): a team-managed Jira project can expose two DIFFERENT ids under the SAME
    # status name — emit EVERY matching id, never just the first (no `exit` after the match).
    # 0b (L-2): a quoted 3-arg string compare — awk's own numeric-string coercion would otherwise
    # treat '010' and '10' as the equal NUMBER 10.
    _rsi_id=$(printf '%s\n' "$_rsi_statusids" | awk -F'\t' -v n="$_rsi_wantname" '($2 "")==(n ""){print $1}')
    if [ -z "$_rsi_id" ]; then
      echo "unverified: state.$_rsi_state maps to a status name absent from status-ids" >&2
      return 2
    fi
    _rsi_ids="$_rsi_ids
$_rsi_id"
  done <<EOF_RSI_NAMES
$_rsi_names
EOF_RSI_NAMES
  # M-2 (fix1): a conf may repeat the SAME mapped name for a state (get-all returns it verbatim,
  # once per line, no dedup) — dedup here so a repeated value doesn't emit its id twice.
  printf '%s\n' "$_rsi_ids" | grep -v '^$' | LC_ALL=C sort -n -u
  return 0
}

# --- R4: re-check every listed key before it is trusted — tr_valid_id AND the project's own id
# grammar (another project's key, or a leading zero e.g. AB-07, fails). Extracted so tr_read_lists
# stays under the line guideline.
# tr_list_keys_ok <project> <keys-blob>
tr_list_keys_ok() {
  _tlk_project=$1; _tlk_keys=$2
  _tlk_seen=""
  while IFS= read -r _tlk_id; do
    [ -n "$_tlk_id" ] || continue
    tr_valid_id "$_tlk_id" || return 1
    # T5bc fix1 B1(a) (security Medium): bound an id to <=32 chars — 480 rows of unbounded keys
    # can blow the seam's own byte cap and lose the subject's bind entirely.
    [ "${#_tlk_id}" -le 32 ] || return 1
    case "$_tlk_id" in
      "$_tlk_project"-[1-9]*) _tlk_suf=${_tlk_id#"$_tlk_project"-} ;;
      *) return 1 ;;
    esac
    case "$_tlk_suf" in *[!0-9]*) return 1 ;; esac
    # K2: a key repeated within ONE state's own blob (subject included) — R6's dup pool excludes
    # the subject, so it alone would miss this; refuse here instead.
    case " $_tlk_seen " in *" $_tlk_id "*) return 1 ;; esac
    _tlk_seen="$_tlk_seen $_tlk_id"
  done <<EOF_TLK
$_tlk_keys
EOF_TLK
  return 0
}

# --- processes ONE requested state (F-4/F-10/F-6/R4/Q2) — extracted so tr_read_lists stays under
# the line guideline. Prints its `row`/`list` lines on success; a resolvable omission (F-4, a failed
# tracker query F-10/F-6, or a re-check failure R4) is a NORMAL return (rc 0, no output) — only a
# grammar-invalid state (Q4/L5) propagates its rc, refusing the WHOLE read.
# tr_read_one_state <conf> <adapter> <base> <flavour> <project> <cap> <state>
tr_read_one_state() {
  _tros_conf=$1; _tros_adapter=$2; _tros_base=$3; _tros_flavour=$4; _tros_project=$5
  _tros_cap=$6; _tros_state=$7
  _tros_ids=$(tr_resolve_state_ids "$_tros_conf" "$_tros_adapter" "$_tros_base" "$_tros_flavour" "$_tros_project" "$_tros_state" 2>/dev/null) && _tros_rc=0 || _tros_rc=$?
  case "$_tros_rc" in
    0) : ;;
    2) echo "omitted: list $_tros_state (the state could not be resolved, F-4)" >&2; return 0 ;;
    # Q3/L2: the 2>/dev/null above swallows tr_resolve_state_ids' own sentence too — a direct
    # (tr_read-bypassing) call must still refuse with ONE fixed sentence, never silently.
    *) tr_state_outside_sentence "$_tros_state" >&2; echo >&2; return "$_tros_rc" ;;
  esac
  set --
  while IFS= read -r _tros_id; do
    [ -n "$_tros_id" ] || continue
    set -- "$@" "$_tros_id"
  done <<EOF_TROS_IDS
$_tros_ids
EOF_TROS_IDS
  # Q3: zero ids resolved (e.g. a state mapped to no names) omits too — say so, never silently.
  [ $# -ge 1 ] || { echo "omitted: list $_tros_state (no ids resolved for the state)" >&2; return 0; }
  if ! _tros_keys=$(sh "$_tros_adapter" list-in-states "$_tros_base" "$_tros_flavour" "$_tros_project" "$_tros_cap" "$@" 2>/dev/null); then
    echo "omitted: list $_tros_state (the tracker query failed, F-10/F-6)" >&2
    return 0
  fi
  # K1: normalise ONCE, here, at capture — a blank line (leading or interior) is dropped so the
  # R4 re-check and both emitters (the space-joined `list` line and the `row` loop) see the same
  # bytes; left raw, a blank would double-space the `list` line and desync checked from emitted.
  _tros_keys=$(printf '%s\n' "$_tros_keys" | grep -v '^$' || true)
  if ! tr_list_keys_ok "$_tros_project" "$_tros_keys"; then
    echo "omitted: list $_tros_state (a listed key failed the re-check, R4)" >&2
    return 0
  fi
  # Q2: a legal EMPTY read (rc 0, zero ids) still writes `list <state>` (no trailing space) — or the
  # seam can never tell "present, zero ids" from "never read" (H-3).
  if [ -n "$_tros_keys" ]; then
    _tros_lineids=$(printf '%s' "$_tros_keys" | tr '\n' ' '); _tros_lineids=${_tros_lineids% }
    printf 'list %s %s\n' "$_tros_state" "$_tros_lineids"
  else
    printf 'list %s\n' "$_tros_state"
  fi
  printf '%s\n' "$_tros_keys" | grep -v '^$' | while IFS= read -r _tros_key; do
    printf 'row %s state=%s\n' "$_tros_key" "$_tros_state"
  done
  return 0
}

# --- the §3b lists arm (T5a2L): per requested state, resolve its ids then ONE list-in-states call
# (tr_read_one_state) with ALL of them and the conf's list_cap. stdout = every `row` line, THEN
# every `list` line, both in state-request order — the caller (tr_write_record) filters the
# subject's own row; this helper does not know the subject id, so it never filters anything itself.
# tr_read_lists <conf> <adapter> <base> <flavour> <project> <state>...
tr_read_lists() {
  unset _TJ_CURL_BIN 2>/dev/null || true
  _trl_conf=$1; _trl_adapter=$2; _trl_base=$3; _trl_flavour=$4; _trl_project=$5; shift 5
  # R5 (T5a2M leg 5): list_cap absent omits EVERY list — never a silent default (a default would
  # widen what a bound record trusts without the conf saying so).
  if ! _trl_cap=$(sh "$TR_CONF_SH" get list_cap "$_trl_conf" 2>/dev/null); then
    echo "omitted: every list (no list_cap in the conf, R5)" >&2
    printf ''
    return 0
  fi
  # C1: the adapter only accepts 1..99999 — gate BEFORE any dispatch (never let an out-of-range
  # value fail per state, one at a time, in the adapter itself).
  # step 0b (security Low): a length gate BEFORE any numeric compare — an overflowing value (e.g.
  # 23 digits) reaching `[ … -le 99999 ]` leaks a `[: … integer expression expected`/`Illegal
  # number` diagnostic to stderr on sh/dash; 99999 is 5 digits, so anything longer is already out
  # of range and can be rejected on length alone, never reaching the numeric compare.
  case "$_trl_cap" in
    ''|*[!0-9]*) _trl_cap_ok=0 ;;
    *)
      if [ "${#_trl_cap}" -le 5 ]; then
        [ "$_trl_cap" -ge 1 ] && [ "$_trl_cap" -le 99999 ] && _trl_cap_ok=1 || _trl_cap_ok=0
      else
        _trl_cap_ok=0
      fi ;;
  esac
  if [ "$_trl_cap_ok" -eq 0 ]; then
    echo "omitted: every list (list_cap outside 1..99999, R5)" >&2
    printf ''
    return 0
  fi
  _trl_raw=""
  # Q4 (security L5): iterate "$@" directly — a captured $* re-split via `for x in $var` would let a
  # single argument with an embedded space silently become two words.
  for _trl_state in "$@"; do
    _trl_chunk=$(tr_read_one_state "$_trl_conf" "$_trl_adapter" "$_trl_base" "$_trl_flavour" "$_trl_project" "$_trl_cap" "$_trl_state") || return $?
    _trl_raw="$_trl_raw
$_trl_chunk"
  done
  _trl_rows=$(printf '%s\n' "$_trl_raw" | grep '^row ' || true)
  _trl_lists=$(printf '%s\n' "$_trl_raw" | grep '^list ' || true)
  printf '%s\n%s\n' "$_trl_rows" "$_trl_lists" | grep -v '^$' || true
  return 0
}

# --- R6 helper: computes the poisoned-state set — a NON-subject id appearing on more than one
# `list` line (a race between two queries), or the subject id appearing under a state that is not
# its own (its own state's list, if present, is never poisoned by this alone). Extracted for the
# line guideline; reads no globals, prints the poison set space-prefixed on stdout.
# tr_race_poison_states <reqid> <reqstate> <list-lines-blob>
tr_race_poison_states() {
  _rps_reqid=$1; _rps_reqstate=$2; _rps_lists=$3
  _rps_poison=""
  _rps_dups=$(printf '%s\n' "$_rps_lists" | cut -d' ' -f2- | tr ' ' '\n' | grep -v '^$' | grep -vx "$_rps_reqid" | LC_ALL=C sort | LC_ALL=C uniq -d)
  while IFS= read -r _rps_ll; do
    [ -n "$_rps_ll" ] || continue
    _rps_rest=${_rps_ll#list }; _rps_st=${_rps_rest%% *}
    _rps_ids=${_rps_rest#* }; [ "$_rps_ids" = "$_rps_rest" ] && _rps_ids=""
    for _rps_id in $_rps_ids; do
      _rps_bad=0
      if [ -n "$_rps_dups" ] && printf '%s\n' "$_rps_dups" | grep -qx "$_rps_id"; then _rps_bad=1; fi
      if [ "$_rps_id" = "$_rps_reqid" ] && [ "$_rps_st" != "$_rps_reqstate" ]; then _rps_bad=1; fi
      if [ "$_rps_bad" -eq 1 ]; then
        case " $_rps_poison " in *" $_rps_st "*) : ;; *) _rps_poison="$_rps_poison $_rps_st" ;; esac
      fi
    done
  done <<EOF_RPS
$_rps_lists
EOF_RPS
  printf '%s' "$_rps_poison"
  return 0
}

# --- R6: a race between list queries — drop a poisoned state's `list` line and its non-subject
# rows entirely (never a partial list); one fixed sentence names the poisoned states. The record
# still round-trips (the subject's own bind is untouched — it lives in the header row, not here).
# tr_filter_list_races <reqid> <reqstate> <raw-blob>
tr_filter_list_races() {
  _tfr_reqid=$1; _tfr_reqstate=$2; _tfr_raw=$3
  [ -n "$_tfr_raw" ] || { printf ''; return 0; }
  _tfr_lists=$(printf '%s\n' "$_tfr_raw" | grep '^list ' || true)
  _tfr_poison=$(tr_race_poison_states "$_tfr_reqid" "$_tfr_reqstate" "$_tfr_lists")
  [ -n "$_tfr_poison" ] || { printf '%s\n' "$_tfr_raw"; return 0; }
  echo "omitted: list$_tfr_poison (a race between list queries, R6)" >&2
  printf '%s\n' "$_tfr_raw" | awk -v poison="$_tfr_poison" '
    BEGIN { n = split(poison, arr, " "); for (i = 1; i <= n; i++) bad[arr[i]] = 1 }
    /^list / { if ($2 in bad) next; print; next }
    /^row /  { st = $3; sub(/^state=/, "", st); if (st in bad) next; print; next }
    { print }
  '
  return 0
}

# T5a2L: the §3b lists arm gate — requested states + a bound subject only; zero states or an
# unbound subject stays exactly today's shape (backward compatible, leg 5/leg 9). T5a2M: also runs
# the R6 race filter over the gathered lists. T5bc (P-1): also enforces the row budget over the
# filtered result. Extracted so tr_read stays under the line guideline.
# tr_read_maybe_lists <conf> <adapter> <base> <flavour> <project> <verdict> <reqid> <reqstate> [state...]
tr_read_maybe_lists() {
  _trml_conf=$1; _trml_adapter=$2; _trml_base=$3; _trml_flavour=$4; _trml_project=$5; _trml_verdict=$6
  _trml_reqid=$7; _trml_reqstate=$8
  shift 8
  if [ $# -ge 1 ] && [ "$_trml_verdict" = "bound" ]; then
    _trml_raw=$(tr_read_lists "$_trml_conf" "$_trml_adapter" "$_trml_base" "$_trml_flavour" "$_trml_project" "$@") || return $?
    _trml_filtered=$(tr_filter_list_races "$_trml_reqid" "$_trml_reqstate" "$_trml_raw")
    tr_enforce_row_budget "$_trml_filtered"
  else
    printf ''
  fi
}

# --- P-1: over TR_ROW_BUDGET row lines (this blob's own LISTED rows — the subject's own header
# row is added separately, by tr_write_record, and is never counted here) omits EVERY list and
# non-subject row (never first-come-first-kept), one sentence naming list_cap — the seam's own
# 512-line/64 KiB cap (backlog-lib.sh M-2) would otherwise refuse the WHOLE record, loop-state
# included. T5bc fix1 B1(b): ALSO measures the blob's own bytes against TR_ROW_BYTE_BUDGET — a
# line count in budget does not bound the BYTES an unbounded-length key set could still carry.
# tr_enforce_row_budget <raw-blob>
tr_enforce_row_budget() {
  _terb_raw=$1
  _terb_rows=$(printf '%s\n' "$_terb_raw" | grep -c '^row ' || true)
  _terb_bytes=$(printf '%s' "$_terb_raw" | wc -c | tr -d ' ')
  if [ "$_terb_rows" -gt "$TR_ROW_BUDGET" ] || [ "$_terb_bytes" -gt "$TR_ROW_BYTE_BUDGET" ]; then
    echo "omitted: every list (over the row budget, list_cap)" >&2
    printf ''
    return 0
  fi
  printf '%s\n' "$_terb_raw"
  return 0
}

# --- T5d: classifies a field.<x> conf VALUE by kind, never by which flag (design §3b/§4.2's
# closed dispatch) — the ONE branch every DoR flag routes through: customfield_N/description ->
# field-empty; label:<prefix> -> label-counts; the literal `none` -> `none` (F-7, silent); anything
# else -> `unrecognized` (omitted with a sentence naming the key, never a dispatch, never n/a).
# tr_field_kind <value>
tr_field_kind() {
  case "$1" in
    ''|none) printf 'none'; return 0 ;;
    description) printf 'field-empty'; return 0 ;;
    label:*) printf 'label-counts'; return 0 ;;
  esac
  case "$1" in
    customfield_*)
      _tfk_suffix=${1#customfield_}
      case "$_tfk_suffix" in
        ''|*[!0-9]*) printf 'unrecognized' ;;
        *) printf 'field-empty' ;;
      esac ;;
    *) printf 'unrecognized' ;;
  esac
  return 0
}

# --- T5b1 leg 2: the ready id set to query — every id already carrying a `state=ready` row token in
# the raw extra blob, PLUS the subject itself when its OWN resolved state is ready (design §3b: "and
# on the subject when it is ready" — independent of whether 'ready' was itself requested). Deduped,
# LC_ALL=C sorted for a deterministic dispatch.
# tr_ready_ids <extra-blob> <reqid> <reqstate>
tr_ready_ids() {
  _tri_extra=$1; _tri_reqid=$2; _tri_reqstate=$3
  _tri_ids=$(printf '%s\n' "$_tri_extra" | awk '/^row /{for(i=3;i<=NF;i++) if($i=="state=ready"){print $2; break}}')
  if [ "$_tri_reqstate" = "ready" ]; then
    case " $_tri_ids " in
      *" $_tri_reqid "*) : ;;
      *) _tri_ids="$_tri_ids
$_tri_reqid" ;;
    esac
  fi
  printf '%s\n' "$_tri_ids" | grep -v '^$' | LC_ALL=C sort -u
}

# --- T5bc: applies <flag>=yes|no to every `row ... state=ready` line — membership in the
# field-empty answer (id present -> the field is empty -> no, otherwise yes; every ready id is
# always definitive, unlike dor-size's count ambiguity). <empty> travels via ENVIRON, never `awk -v`
# (the same macOS multi-line trap tr_apply_labelcount_tokens's own comment names).
# tr_apply_field_empty_tokens <extra-blob> <empty-ids> <flag>
tr_apply_field_empty_tokens() {
  _tafet_extra=$1; _tafet_empty=$2; _tafet_flag=$3
  _TAFET_ENV_EMPTY="$_tafet_empty" _TAFET_ENV_FLAG="$_tafet_flag" awk '
    BEGIN {
      flag = ENVIRON["_TAFET_ENV_FLAG"]
      n = split(ENVIRON["_TAFET_ENV_EMPTY"], earr, "\n")
      for (i = 1; i <= n; i++) if (earr[i] != "") empty[earr[i]] = 1
    }
    /^row / {
      isready = 0
      for (i = 3; i <= NF; i++) if ($i == "state=ready") isready = 1
      if (isready) { v = ($2 in empty) ? "no" : "yes"; print $0 " " flag "=" v; next }
      print $0; next
    }
    { print }
  ' <<EOF_TAFET
$_tafet_extra
EOF_TAFET
}

# --- T5d: dispatches ONE field-empty call for <flag> over <ids> (design §3b/§3g), called by
# tr_apply_dor_flag once the kind is known field-empty. Sets $_extra (decorated) and $_subjfieldval
# DIRECTLY — called directly, never via $(...), so the $_extra reassignment lands in THIS shell. A
# failed/unparsable query (F-10) leaves $_extra untouched.
# tr_dispatch_field_empty <adapter> <base> <flavour> <project> <reqid> <reqstate> <spec> <flag> <ids>
tr_dispatch_field_empty() {
  # T10-harden-A R2 (defence in depth): unconditionally FIRST, so both protections apply even on a
  # direct call that bypasses tr_apply_dor_flag's own bound check and never reaches a dispatch.
  unset _TJ_CURL_BIN 2>/dev/null || true
  [ "$_verdict" = bound ] || return 0
  _tdfe_adapter=$1; _tdfe_base=$2; _tdfe_flavour=$3; _tdfe_project=$4
  _tdfe_reqid=$5; _tdfe_reqstate=$6; _tdfe_spec=$7; _tdfe_flag=$8; _tdfe_ids=$9
  set -f
  # shellcheck disable=SC2086 # ids are grammar-checked single tokens (state=ready row ids / reqid)
  if ! _tdfe_answer=$(sh "$_tdfe_adapter" field-empty "$_tdfe_base" "$_tdfe_flavour" "$_tdfe_project" "$_tdfe_spec" $_tdfe_ids 2>/dev/null); then
    set +f
    echo "omitted: $_tdfe_flag (the tracker query failed, F-10)" >&2
    return 0
  fi
  set +f
  if ! tr_answer_ok "$_tdfe_project" "$_tdfe_ids" "$_tdfe_answer" subset; then
    echo "omitted: $_tdfe_flag (the tracker query failed, F-10)" >&2
    return 0
  fi
  _extra=$(tr_apply_field_empty_tokens "$_extra" "$_tdfe_answer" "$_tdfe_flag")
  [ "$_tdfe_reqstate" = "ready" ] || return 0
  _tdfe_pad=" $(printf '%s\n' "$_tdfe_answer" | tr '\n' ' ')"
  case "$_tdfe_pad" in
    *" $_tdfe_reqid "*) _subjfieldval=no ;;
    *) _subjfieldval=yes ;;
  esac
  return 0
}

# --- T5d: the ONE dispatch table every DoR flag routes through (design §4.2's closed set),
# classifying <confkey>'s value by KIND, never by which flag (never per-flag code): customfield_N /
# description -> field-empty; label:<prefix> -> label-counts; `none` OR an absent key -> silently
# omitted (F-7 — an unmapped field is exactly as legal as an explicit `none`, never a sentence,
# preserves every pre-T5d conf that maps only a subset of the four fields); a PRESENT value that is
# none of the above -> omitted with a fixed sentence naming the key, never n/a. Sets $_extra
# (decorated) and $_subjfieldval DIRECTLY — called directly, never via $(...).
# tr_apply_dor_flag <conf> <adapter> <base> <flavour> <project> <reqid> <reqstate> <confkey> <flag>
tr_apply_dor_flag() {
  unset _TJ_CURL_BIN 2>/dev/null || true
  _tadf_conf=$1; _tadf_adapter=$2; _tadf_base=$3; _tadf_flavour=$4; _tadf_project=$5
  _tadf_reqid=$6; _tadf_reqstate=$7; _tadf_confkey=$8; _tadf_flag=$9
  _subjfieldval=""
  # never dispatch a flag query after the credential probe downgraded the verdict.
  [ "$_verdict" = bound ] || return 0
  _tadf_spec=$(sh "$TR_CONF_SH" get "$_tadf_confkey" "$_tadf_conf" 2>/dev/null) || return 0
  _tadf_kind=$(tr_field_kind "$_tadf_spec")
  case "$_tadf_kind" in
    none) return 0 ;;
    unrecognized)
      echo "omitted: $_tadf_flag ($_tadf_confkey is not a recognized field mapping)" >&2
      return 0 ;;
  esac
  _tadf_ids=$(tr_ready_ids "$_extra" "$_tadf_reqid" "$_tadf_reqstate")
  [ -n "$_tadf_ids" ] || return 0
  if [ "$_tadf_kind" = field-empty ]; then
    tr_dispatch_field_empty "$_tadf_adapter" "$_tadf_base" "$_tadf_flavour" "$_tadf_project" \
      "$_tadf_reqid" "$_tadf_reqstate" "$_tadf_spec" "$_tadf_flag" "$_tadf_ids"
  else
    tr_dispatch_labelcounts "$_tadf_adapter" "$_tadf_base" "$_tadf_flavour" "$_tadf_project" \
      "$_tadf_reqid" "$_tadf_reqstate" "${_tadf_spec#label:}" "$_tadf_flag" "$_tadf_ids"
  fi
  return 0
}

# --- T5d: runs the four §4.2 DoR fields through the ONE dispatch table above, in the design's own
# example-row order, then builds $_hdrflags. Called DIRECTLY (never via $(...)) so every downstream
# $_extra reassignment lands in the caller's shell; extracted so tr_read stays under the line
# guideline.
# tr_apply_flags <conf> <adapter> <base> <flavour> <project> <reqid> <reqstate>
tr_apply_flags() {
  tr_apply_dor_flag "$1" "$2" "$3" "$4" "$5" "$6" "$7" field.acceptance dor-acceptance
  _subjacceptance=$_subjfieldval
  tr_apply_dor_flag "$1" "$2" "$3" "$4" "$5" "$6" "$7" field.metric dor-metric
  _subjmetric=$_subjfieldval
  tr_apply_dor_flag "$1" "$2" "$3" "$4" "$5" "$6" "$7" field.size dor-size
  _subjdorsize=$_subjfieldval
  tr_apply_dor_flag "$1" "$2" "$3" "$4" "$5" "$6" "$7" field.risk dor-risk
  _subjrisk=$_subjfieldval
  _hdrflags=$(tr_append_hdrflag "" claimed "$_claimed")
  _hdrflags=$(tr_append_hdrflag "$_hdrflags" dor-acceptance "$_subjacceptance")
  _hdrflags=$(tr_append_hdrflag "$_hdrflags" dor-metric "$_subjmetric")
  _hdrflags=$(tr_append_hdrflag "$_hdrflags" dor-size "$_subjdorsize")
  _hdrflags=$(tr_append_hdrflag "$_hdrflags" dor-risk "$_subjrisk")
  return 0
}

# --- T5d (generalised from T5b1 leg 2/F-8 on <flag>, never hardcoded to dor-size): applies
# <flag>=yes|no to every `row ... state=ready` line whose id has a count of exactly 0 or 1 in
# <counts> (key<TAB>count per line); a count >=2 or an id absent from <counts> leaves the row
# untouched (F-8: ambiguous/unqueried, never first-wins, never a token). <counts> travels via
# ENVIRON, never `awk -v` — a multi-line -v value errors "newline in string" on macOS's bundled awk
# (mirrors backlog-lib.sh's own _seam_bijection_scan comment on this exact trap).
# tr_apply_labelcount_tokens <extra-blob> <counts-tsv> <flag>
tr_apply_labelcount_tokens() {
  _talt_extra=$1; _talt_counts=$2; _talt_flag=$3
  _TALT_ENV_COUNTS="$_talt_counts" _TALT_ENV_FLAG="$_talt_flag" awk '
    BEGIN {
      flag = ENVIRON["_TALT_ENV_FLAG"]
      n = split(ENVIRON["_TALT_ENV_COUNTS"], carr, "\n")
      for (i = 1; i <= n; i++) { split(carr[i], kv, "\t"); if (kv[1] != "") cnt[kv[1]] = kv[2] }
    }
    /^row / {
      isready = 0
      for (i = 3; i <= NF; i++) if ($i == "state=ready") isready = 1
      if (isready && ($2 in cnt)) {
        if (cnt[$2] == "0") { print $0 " " flag "=no"; next }
        if (cnt[$2] == "1") { print $0 " " flag "=yes"; next }
      }
      print $0; next
    }
    { print }
  ' <<EOF_TALT
$_talt_extra
EOF_TALT
}

# --- fix1 V1 (security Medium + quality 5) + T5bc step 0: a reusable tracker-answer validator,
# reused by mode `exact` (label-counts: id<TAB>count, the key set byte-equal to the asked ids each
# exactly once) and mode `subset` (field-empty: a bare id per line, no TAB field, the key set a
# SUBSET of the asked ids, no duplicates, nothing outside — the legal empty answer accepted). Fails
# closed on ANY violation: the expected field count per line, the value in a closed grammar (step
# 0d: count canonical `^(0|[1-9][0-9]*)$`, so '01'/'00' no longer pass), every key through
# tr_valid_id + the project rule (tr_list_keys_ok, which also catches a repeated key).
# tr_answer_ok <project> <asked-ids> <answer-tsv> <mode>
tr_answer_ok() {
  _tao_project=$1; _tao_asked=$2; _tao_answer=$3; _tao_mode=$4
  case "$_tao_mode" in exact|subset) ;; *) return 1 ;; esac
  _tao_lines=$(printf '%s\n' "$_tao_answer" | grep -v '^$' || true)
  if [ "$_tao_mode" = exact ]; then
    [ -n "$_tao_lines" ] || return 1
    printf '%s\n' "$_tao_lines" | awk -F'\t' 'NF!=2{exit 1} $2!~/^(0|[1-9][0-9]*)$/{exit 1}' || return 1
    _tao_keys=$(printf '%s\n' "$_tao_lines" | awk -F'\t' '{print $1}')
  else
    if [ -n "$_tao_lines" ]; then
      # T5bc fix1 B6: defence in depth, not the primary gate — a TAB-carrying key is already
      # refused below by tr_list_keys_ok's own tr_valid_id call.
      printf '%s\n' "$_tao_lines" | awk -F'\t' 'NF!=1{exit 1}' || return 1
    fi
    _tao_keys=$_tao_lines
  fi
  tr_list_keys_ok "$_tao_project" "$_tao_keys" || return 1
  _tao_asked_sorted=$(printf '%s\n' "$_tao_asked" | grep -v '^$' | LC_ALL=C sort)
  if [ "$_tao_mode" = exact ]; then
    _tao_keys_sorted=$(printf '%s\n' "$_tao_keys" | LC_ALL=C sort)
    [ "$_tao_asked_sorted" = "$_tao_keys_sorted" ] || return 1
    return 0
  fi
  [ -n "$_tao_keys" ] || return 0
  while IFS= read -r _tao_k; do
    [ -n "$_tao_k" ] || continue
    printf '%s\n' "$_tao_asked_sorted" | grep -qx "$_tao_k" || return 1
  done <<EOF_TAO
$_tao_keys
EOF_TAO
  return 0
}

# --- T5d (generalised from T5b1 leg 2/4 on <flag>, never hardcoded to dor-size): the ONE
# label-counts dispatch over <ids> (design §3b/§3c), called by tr_apply_dor_flag once the kind is
# known label-counts. Sets $_extra (decorated) and $_subjfieldval DIRECTLY — called directly, never
# via $(...), so the $_extra reassignment lands in THIS shell. A failed/unparsable query (F-10)
# leaves $_extra untouched, with one fixed sentence naming <flag>.
# tr_dispatch_labelcounts <adapter> <base> <flavour> <project> <reqid> <reqstate> <prefix> <flag> <ids>
tr_dispatch_labelcounts() {
  # T10-harden-A R2 (defence in depth): unconditionally FIRST, so both protections apply even on a
  # direct call that bypasses tr_apply_dor_flag's own bound check and never reaches a dispatch.
  unset _TJ_CURL_BIN 2>/dev/null || true
  [ "$_verdict" = bound ] || return 0
  _tdlc_adapter=$1; _tdlc_base=$2; _tdlc_flavour=$3; _tdlc_project=$4
  _tdlc_reqid=$5; _tdlc_reqstate=$6; _tdlc_prefix=$7; _tdlc_flag=$8; _tdlc_ids=$9
  set -f
  # shellcheck disable=SC2086 # ids are grammar-checked single tokens (state=ready row ids / reqid)
  if ! _tdlc_counts=$(sh "$_tdlc_adapter" label-counts "$_tdlc_base" "$_tdlc_flavour" "$_tdlc_project" "$_tdlc_prefix" $_tdlc_ids 2>/dev/null); then
    set +f
    echo "omitted: $_tdlc_flag (the tracker query failed, F-10)" >&2
    return 0
  fi
  set +f
  # fix1 V1 (carried): validate the answer before trusting it — ANY failure (dup key,
  # missing/extra id, an extra TAB field, a non-numeric count) omits <flag> EVERYWHERE with the
  # SAME F-10 sentence.
  if ! tr_answer_ok "$_tdlc_project" "$_tdlc_ids" "$_tdlc_counts" exact; then
    echo "omitted: $_tdlc_flag (the tracker query failed, F-10)" >&2
    return 0
  fi
  _extra=$(tr_apply_labelcount_tokens "$_extra" "$_tdlc_counts" "$_tdlc_flag")
  # leg 6 (carried, defence in depth, mirrors H-5): only ever attribute a count to the SUBJECT
  # header row when the subject's OWN resolved state is ready — an adapter that answered with an
  # id beyond what it was asked for (never legal for the real adapter, S-4/exact-match) must not
  # leak a value onto a non-ready subject.
  [ "$_tdlc_reqstate" = "ready" ] || return 0
  _tdlc_subjcount=$(printf '%s\n' "$_tdlc_counts" | awk -F'\t' -v k="$_tdlc_reqid" '$1==k{print $2}')
  case "$_tdlc_subjcount" in
    0) _subjfieldval=no ;;
    1) _subjfieldval=yes ;;
    *) _subjfieldval="" ;;
  esac
  return 0
}

# --- the read: writes the §4.3 record to $3 --------------------------------------------------
# tr_read <conf> <origin-conf|-> <record-path> <requested-id> <head-sha> [state...]
tr_read() {
  _conf=$1; _origin=$2; _record=$3; _reqid=$4; _head=$5
  shift 5
  # F-5/F-10: refuse (never touching the file) an unsafe record path, then truncate FIRST.
  tr_record_safe "$_record" "$_conf" "$_origin" || return 1
  : > "$_record"
  tr_validate_head_states "$_head" "$@" || return 1

  tr_load_conf "$_conf" "$_origin" || return $?
  tr_valid_id "$_reqid" || { echo "refused: malformed id grammar" >&2; return 1; }
  _adapter=$(tr_adapter_path "$_backend") || { echo "refused: malformed backend token" >&2; return 1; }
  if [ ! -f "$_adapter" ]; then
    echo "unverified: no adapter for backend (rc 3, not enforced)" >&2
    return 3
  fi

  export KIT_TRACKER_USER="$_user" KIT_TRACKER_TOKEN="$_token" KIT_TRACKER_AUTH="$_auth"
  # H-1: never let an inherited env override steer the adapter's HTTP-client binary — unset it in
  # THIS shell, before the FIRST dispatch, so it stays unset for every dispatch below (get-issue
  # via tr_adapter_read, permissions via tr_probe_credential) rather than only inside one helper's
  # own now-removed subshell (fix1 I-1/I-2).
  unset _TJ_CURL_BIN 2>/dev/null || true
  tr_adapter_read "$_adapter" "$_base" "$_flavour" "$_project" "$_reqid" || return $?
  # T5b1 leg 1: claimed on the subject, a closed mapping — absent/malformed omits (never defaults).
  _claimed=$(tr_claimed_value "$_assignpresent")

  # M-2/L-8: sets $_state/$_verdict directly (never via $(...) — see the function's own header).
  tr_resolve_verdict "$_conf" "$_statusname" "$_statusid"

  # H-3/S-11: sets $_cred and downgrades $_verdict directly (never via $(...)).
  tr_resolve_cred "$_adapter" "$_base" "$_flavour" "$_project"

  _pindigest=$(tr_pin_digest "$_conf")
  _day=$(date -u +%Y-%m-%d)

  # T5a2M leg 7 (R6)/T5bc (P-1): tr_read_maybe_lists also runs the race filter and the row budget
  # over the gathered lists.
  _extra=$(tr_read_maybe_lists "$_conf" "$_adapter" "$_base" "$_flavour" "$_project" "$_verdict" "$_reqid" "$_state" "$@") || return $?

  # T5b1/T5bc: dor-acceptance, dor-metric, dor-size on ready rows + the subject when it is itself
  # ready, and the subject's own header-row tokens (claimed first) — builds $_hdrflags directly
  # (called DIRECTLY, never via $(...), so every downstream $_extra reassignment lands here).
  tr_apply_flags "$_conf" "$_adapter" "$_base" "$_flavour" "$_project" "$_reqid" "$_state"

  tr_write_record "$_record" "$_backend" "$_pindigest" "$_head" "$_reqid" "$_day" "$_cred" "$_verdict" "$_key" "$_state" "$_extra" "$_hdrflags" || return $?
  return 0
}

# --- selftest --------------------------------------------------------------------------------
_tr_selftest() {
  # L-2: bound recursion even under a mutant that removes the S-10 refusal below — this depth
  # guard is a SEPARATE mechanism from that refusal, so a mutant killing one still gets caught by
  # the other rather than hanging forever.
  _depth=${KIT_TR_SELFTEST_DEPTH:-0}
  if [ "$_depth" -ge 2 ]; then
    echo "FAIL: selftest — recursion depth exceeded (L-2 guard fired; the S-10 refusal below should have caught this first)" >&2
    exit 1
  fi
  sfail=0
  # S-10: refuse to run when a token env var is set.
  if [ -n "${KIT_TRACKER_TOKEN:-}${KIT_TRACKER_USER:-}${JIRA_TOKEN:-}${JIRA_EMAIL:-}" ]; then
    echo "FAIL: selftest — --selftest must run with no token env var set (S-10)"; exit 1
  fi
  tmpd=$(mktemp -d) || { echo "FAIL: could not create temp dir"; exit 1; }
  trap 'rm -rf "$tmpd"; [ "${sfail:-1}" -eq 0 ] || exit 1' EXIT INT TERM

  # a fake adapter dispatched by backend token (J1 — proves neutrality; the reader never opens
  # this file itself, only sh's it by a path built from the conf's backend value).
  fakeadapter="$tmpd/tracker-fixture.sh"
  cat > "$fakeadapter" <<'EOF'
#!/bin/sh
case "$1" in
  get-issue)
    case "$KIT_TRF_MODE" in
      hostile-id) printf 'key\tAB-1\033\177\n'; printf 'status-id\t3\n'; printf 'status-name\tIn Progress\n' ;;
      unmapped) printf 'key\tAB-1\n'; printf 'status-id\t999\n'; printf 'status-name\tSome Unmapped Status\n' ;;
      bad-statusid) printf 'key\tAB-1\n'; printf 'status-id\tnot-numeric\n'; printf 'status-name\tIn Progress\n' ;;
      *) printf 'key\tAB-1\n'; printf 'status-id\t3\n'; printf 'status-name\tIn Progress\n' ;;
    esac
    exit 0 ;;
  permissions) echo ok; exit 0 ;;
esac
EOF
  chmod +x "$fakeadapter"
  fakedir="$tmpd/scripts"; mkdir -p "$fakedir"
  cp "$fakeadapter" "$fakedir/tracker-fixture.sh"
  fakeroot="$tmpd"
  TR_ROOT="$fakeroot"
  cp "$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)/scripts/tracker-conf.sh" "$fakedir/tracker-conf.sh"
  TR_CONF_SH="$fakedir/tracker-conf.sh"

  conf="$tmpd/tracker.conf"
  cat > "$conf" <<'EOF'
version=1
backend=fixture
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
state.in-progress=In Progress
EOF
  record="$tmpd/record.txt"

  export KIT_TRACKER_USER="user@example.com"
  export KIT_TRACKER_TOKEN="s3cr3t"

  # H-2/F-11 (T4): a fixed, valid, non-zero head-sha for every pre-existing leg below that does not
  # itself test head-sha grammar — those legs get their own head/state fixtures further down.
  _h40="1111111111111111111111111111111111111111"
  _h64="1111111111111111111111111111111111111111111111111111111111111111"

  # --- positive: a good fixture writes a bound record, state resolved from the CONF's map (M-2) ---
  rc=0
  KIT_TRF_MODE=good tr_read "$conf" "-" "$record" AB-1 "$_h40" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 0 ] && grep -q '^verdict bound$' "$record" 2>/dev/null && grep -q 'state=in-progress' "$record" 2>/dev/null; then
    echo "PASS: selftest — a good fixture writes a bound §4.3 record, state resolved from the conf's state.* map (M-2)"
  else
    echo "FAIL: selftest — a good fixture did not write a bound record with the conf-resolved state (rc=$rc, record: $(cat "$record" 2>/dev/null))"; sfail=1
  fi
  if grep -q '^credential ok$' "$record" 2>/dev/null; then
    echo "PASS: selftest — a browse-only mypermissions probe folds through as 'credential ok' (S-11/T5)"
  else
    echo "FAIL: selftest — the record did not carry 'credential ok' (record: $(cat "$record" 2>/dev/null))"; sfail=1
  fi

  # --- M-2 negative: an env-supplied state map is NOT consulted; only the conf's own map is ---
  rc=0
  : > "$record"
  KIT_TRACKER_STATE_MAP="3	blocked" KIT_TRF_MODE=good tr_read "$conf" "-" "$record" AB-1 "$_h40" >/dev/null 2>&1 || rc=$?
  if grep -q 'state=in-progress' "$record" 2>/dev/null && ! grep -q 'state=blocked' "$record" 2>/dev/null; then
    echo "PASS: selftest — an env-supplied KIT_TRACKER_STATE_MAP is ignored; only the conf's state.* map is consulted (M-2)"
  else
    echo "FAIL: selftest — an env-supplied state map was honored (M-2 regression): $(cat "$record" 2>/dev/null)"; sfail=1
  fi

  # --- fix1 I-1/I-2/I-3: the step-0 split's TAB-packed line + here-doc round trip is NOT
  # behaviour-neutral: an empty field collapses under IFS=<TAB> read (the token shifts into the
  # user field); the helpers ran inside $(...), so H-1's unset only reached that subshell; the
  # packed fields travelled through a here-doc (macOS sh = bash 3.2 writes here-doc bodies to
  # /private/var/tmp — the token on disk). ------------------------------------------------------

  # leg (a): KIT_TRACKER_USER (and JIRA_EMAIL) unset, token set, auth=bearer -> the fake adapter
  # sees user=[] and token=<token> for get-issue AND permissions. The log path is baked into the
  # adapter's own body (env -i does not apply to the fake, so it cannot be an env-carried path).
  bearerconf="$tmpd/bearer.conf"
  cat > "$bearerconf" <<'EOF'
version=1
backend=fixture
base_url=https://ex.atlassian.net
flavour=cloud
auth=bearer
project=AB
state.in-progress=In Progress
EOF
  credlog="$tmpd/cred.log"
  cat > "$fakedir/tracker-fixture.sh" <<EOF
#!/bin/sh
printf '%s user=[%s] token=[%s]\n' "\$1" "\$KIT_TRACKER_USER" "\$KIT_TRACKER_TOKEN" >> "$credlog"
case "\$1" in
  get-issue) printf 'key\tAB-1\n'; printf 'status-id\t3\n'; printf 'status-name\tIn Progress\n'; exit 0 ;;
  permissions) echo ok; exit 0 ;;
esac
EOF
  chmod +x "$fakedir/tracker-fixture.sh"
  : > "$credlog"; : > "$record"
  rc=0
  (unset KIT_TRACKER_USER JIRA_EMAIL; KIT_TRACKER_TOKEN=s3cr3t tr_read "$bearerconf" "-" "$record" AB-1 "$_h40") >/dev/null 2>&1 || rc=$?
  if grep -q '^get-issue user=\[\] token=\[s3cr3t\]$' "$credlog" 2>/dev/null && grep -q '^permissions user=\[\] token=\[s3cr3t\]$' "$credlog" 2>/dev/null; then
    echo "PASS: selftest — an unset KIT_TRACKER_USER + auth=bearer reaches every dispatch as an empty user field, token intact (fix1 I-1/I-2)"
  else
    echo "FAIL: selftest — the empty-user field did not travel correctly to every dispatch (rc=$rc, credlog: $(cat "$credlog" 2>/dev/null))"; sfail=1
  fi

  # leg (b): an exported _TJ_CURL_BIN reaches NO adapter op tr_read (or tr_resolve_state_ids,
  # T5a2L: or tr_read_lists) dispatches — captured for get-issue, permissions, status-ids, AND
  # (T5a2L leg 6) list-in-states.
  curlbinlog="$tmpd/curlbin.log"
  # fix1 V4 (drift lock): get-issue/label-counts read from files (never an inline printf of
  # adapter output inside the fake adapter body) — this leg's backend is the neutral `fixture`
  # token (not jira), so there is no adapter-proven ops/ file to reuse; written into $tmpd instead.
  _t5b1v4_curlbin_getissue="$tmpd/curlbin-get-issue.out"
  cat > "$_t5b1v4_curlbin_getissue" <<'EOF'
key	AB-1
status-id	3
status-name	In Progress
EOF
  _t5b1v4_curlbin_labelcounts="$tmpd/curlbin-label-counts.out"
  cat > "$_t5b1v4_curlbin_labelcounts" <<'EOF'
AB-1	0
EOF
  cat > "$fakedir/tracker-fixture.sh" <<EOF
#!/bin/sh
if [ -n "\${_TJ_CURL_BIN+x}" ]; then
  printf '%s SET=[%s]\n' "\$1" "\$_TJ_CURL_BIN" >> "$curlbinlog"
else
  printf '%s UNSET\n' "\$1" >> "$curlbinlog"
fi
case "\$1" in
  get-issue) cat "$_t5b1v4_curlbin_getissue"; exit 0 ;;
  permissions) echo ok; exit 0 ;;
  status-ids) printf '3\tIn Progress\n'; exit 0 ;;
  list-in-states) printf 'AB-1\n'; exit 0 ;;
  label-counts) cat "$_t5b1v4_curlbin_labelcounts"; exit 0 ;;
  field-empty) printf 'AB-1\n'; exit 0 ;;
esac
EOF
  chmod +x "$fakedir/tracker-fixture.sh"
  # T5a2L leg 6: a standalone conf carrying list_cap (defined here, ahead of the later `lconf`
  # used by legs 2-4, so tr_read_lists can resolve list_cap and reach the list-in-states dispatch).
  # T5b1 leg 7: field.size=label:size added so tr_apply_dor_flag's label-counts branch is
  # reachable too. T5bc fix1 B4: field.acceptance=description added so its field-empty branch is
  # reachable too.
  curlbinconf="$tmpd/curlbin.conf"
  cat > "$curlbinconf" <<'EOF'
version=1
backend=fixture
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
list_cap=200
state.in-progress=In Progress
field.size=label:size
field.acceptance=description
EOF
  : > "$curlbinlog"; : > "$record"
  (export _TJ_CURL_BIN=/evil/curl; tr_read "$conf" "-" "$record" AB-1 "$_h40") >/dev/null 2>&1 || true
  (export _TJ_CURL_BIN=/evil/curl; tr_resolve_state_ids "$conf" "$fakedir/tracker-fixture.sh" https://ex.atlassian.net cloud AB in-progress) >/dev/null 2>&1 || true
  # tr_read_lists unsets _TJ_CURL_BIN as its OWN first statement (mirrors tr_resolve_state_ids above).
  (export _TJ_CURL_BIN=/evil/curl; tr_read_lists "$curlbinconf" "$fakedir/tracker-fixture.sh" https://ex.atlassian.net cloud AB in-progress) >/dev/null 2>&1 || true
  # T5b1 leg 7/T5d: tr_apply_dor_flag unsets _TJ_CURL_BIN as its OWN first statement too — called
  # DIRECTLY (it reads/writes the caller's own $_extra global, never via $(...)); seed $_extra with
  # one ready row so its own label-counts dispatch is actually reached. T5bc step 0c: $_verdict is
  # set explicitly here (never relying on a prior leg's leftover value) so this leg does not depend
  # on leg order.
  (_verdict=bound; _extra="row AB-1 state=ready"; export _TJ_CURL_BIN=/evil/curl; tr_apply_dor_flag "$curlbinconf" "$fakedir/tracker-fixture.sh" https://ex.atlassian.net cloud AB AB-1 in-progress field.size dor-size) >/dev/null 2>&1 || true
  # T5bc fix1 B4 (security Low 2): the SAME dispatch's field-empty branch unsets _TJ_CURL_BIN too —
  # called DIRECTLY, same convention as the label-counts leg just above.
  (_verdict=bound; _extra="row AB-1 state=ready"; export _TJ_CURL_BIN=/evil/curl; tr_apply_dor_flag "$curlbinconf" "$fakedir/tracker-fixture.sh" https://ex.atlassian.net cloud AB AB-1 in-progress field.acceptance dor-acceptance) >/dev/null 2>&1 || true
  if grep -q '^get-issue UNSET$' "$curlbinlog" 2>/dev/null && grep -q '^permissions UNSET$' "$curlbinlog" 2>/dev/null \
     && grep -q '^status-ids UNSET$' "$curlbinlog" 2>/dev/null && grep -q '^list-in-states UNSET$' "$curlbinlog" 2>/dev/null \
     && grep -q '^label-counts UNSET$' "$curlbinlog" 2>/dev/null && grep -q '^field-empty UNSET$' "$curlbinlog" 2>/dev/null; then
    echo "PASS: selftest — an exported _TJ_CURL_BIN reaches no dispatch: get-issue, permissions, status-ids, list-in-states, label-counts, field-empty all see it unset (fix1 I-1/I-2, H-1, T5a2L leg 6, T5b1 leg 7, T5bc fix1 B4)"
  else
    echo "FAIL: selftest — _TJ_CURL_BIN leaked to a dispatch (curlbinlog: $(cat "$curlbinlog" 2>/dev/null))"; sfail=1
  fi

  # --- 0e (T5a1 carried m-2): tr_adapter_read and tr_probe_credential each unset _TJ_CURL_BIN as
  # their OWN first statement — proven by calling them DIRECTLY (bypassing tr_read's own unset).
  : > "$curlbinlog"
  (export _TJ_CURL_BIN=/evil/curl; tr_adapter_read "$fakedir/tracker-fixture.sh" https://ex.atlassian.net cloud AB AB-1) >/dev/null 2>&1 || true
  (export _TJ_CURL_BIN=/evil/curl; tr_probe_credential "$fakedir/tracker-fixture.sh" https://ex.atlassian.net cloud AB) >/dev/null 2>&1 || true
  if grep -q '^get-issue UNSET$' "$curlbinlog" 2>/dev/null && grep -q '^permissions UNSET$' "$curlbinlog" 2>/dev/null; then
    echo "PASS: selftest — tr_adapter_read and tr_probe_credential unset _TJ_CURL_BIN as their OWN first statement, called directly (0e/m-2)"
  else
    echo "FAIL: selftest — _TJ_CURL_BIN leaked into a direct tr_adapter_read/tr_probe_credential call (curlbinlog: $(cat "$curlbinlog" 2>/dev/null))"; sfail=1
  fi
  cp "$fakeadapter" "$fakedir/tracker-fixture.sh"

  # leg (c) (I-3, a STRUCTURAL pin, not a behavioural one): no credential value travels through a
  # here-doc or a packed TAB-joined text line anywhere in tracker-read.sh's own logic.
  _fix1_src=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)/scripts/tracker-read.sh
  _fix1_logic=$(awk '/^# --- selftest /{exit} {print}' "$_fix1_src")
  _fix1_heredoc_hit=$(printf '%s\n' "$_fix1_logic" | grep -n '<<' | grep -E '_token|_user' || true)
  _fix1_packed_hit=$(printf '%s\n' "$_fix1_logic" | grep -nE "printf '%s\\\\t%s" | grep '_token' || true)
  if [ -z "$_fix1_heredoc_hit" ] && [ -z "$_fix1_packed_hit" ]; then
    echo "PASS: selftest — no credential value travels through a here-doc or a packed TAB line (fix1 I-3, structural pin, not behavioural)"
  else
    echo "FAIL: selftest — a credential value still travels through a here-doc or packed TAB line (fix1 I-3): heredoc='$_fix1_heredoc_hit' packed='$_fix1_packed_hit'"; sfail=1
  fi

  # --- S-11/T5: an over-privileged mypermissions probe folds through as 'credential over-privileged' ---
  cat > "$fakedir/tracker-fixture.sh" <<'EOF'
#!/bin/sh
case "$1" in
  get-issue) printf 'key\tAB-1\n'; printf 'status-id\t3\n'; printf 'status-name\tIn Progress\n'; exit 0 ;;
  permissions) echo over-privileged; exit 0 ;;
esac
EOF
  chmod +x "$fakedir/tracker-fixture.sh"
  : > "$record"
  tr_read "$conf" "-" "$record" AB-1 "$_h40" >/dev/null 2>&1 || true
  if grep -q '^credential over-privileged$' "$record" 2>/dev/null; then
    echo "PASS: selftest — an over-privileged mypermissions probe folds through as 'credential over-privileged' (S-11/T5)"
  else
    echo "FAIL: selftest — the record did not carry 'credential over-privileged' (record: $(cat "$record" 2>/dev/null))"; sfail=1
  fi

  # --- H-3 negative: a probe that fails/is unparsable -> credential unverified, verdict NEVER bound ---
  cat > "$fakedir/tracker-fixture.sh" <<'EOF'
#!/bin/sh
case "$1" in
  get-issue) printf 'key\tAB-1\n'; printf 'status-id\t3\n'; printf 'status-name\tIn Progress\n'; exit 0 ;;
  permissions) exit 5 ;;
esac
EOF
  chmod +x "$fakedir/tracker-fixture.sh"
  : > "$record"
  tr_read "$conf" "-" "$record" AB-1 "$_h40" >/dev/null 2>&1 || true
  if grep -q '^credential unverified$' "$record" 2>/dev/null && grep -q '^verdict unverified$' "$record" 2>/dev/null && ! grep -q '^verdict bound$' "$record" 2>/dev/null; then
    echo "PASS: selftest — a failed credential probe writes credential unverified AND downgrades verdict, never bound (H-3)"
  else
    echo "FAIL: selftest — a failed credential probe did not fail closed (record: $(cat "$record" 2>/dev/null))"; sfail=1
  fi
  cp "$fakeadapter" "$fakedir/tracker-fixture.sh"

  # --- J1 neutrality: grep the reader's OWN LOGIC (not this selftest's fixture prose, which
  # legitimately uses a realistic example host) for jira-specific strings. Everything above the
  # "--- selftest" marker is the reader itself; the marker line is the boundary. ONE disclosed,
  # narrow exception: the H-1 defensive `unset _TJ_CURL_BIN` line names a specific adapter's
  # internal env var by design (it is the exact name the coordinator's fix asked to clear before
  # every dispatch) — a genuinely neutral reader cannot know every future adapter's internal
  # override names, so this is a real, disclosed neutrality leak, not swept under the rug: a
  # future non-jira adapter with its own env-steerable override needs its own such line (or a
  # shared naming convention) rather than assuming this one unset covers it.
  _srcfile=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)/scripts/tracker-read.sh
  _logic_lines=$(awk '/^# --- selftest /{exit} {print}' "$_srcfile" | grep -v '_TJ_CURL_BIN')
  if printf '%s' "$_logic_lines" | grep -Eiq 'curl|jql|atlassian|/rest/api'; then
    echo "FAIL: selftest — tracker-read.sh's own logic contains jira-specific text (J1/G2 neutrality)"; sfail=1
  else
    echo "PASS: selftest — tracker-read.sh's own logic carries no jira-specific string (J1/G2 neutrality)"
  fi

  # --- L-8: an unmapped status name -> verdict unverified, never bound ---
  rc=0
  : > "$record"
  KIT_TRF_MODE=unmapped tr_read "$conf" "-" "$record" AB-1 "$_h40" >/dev/null 2>&1 || rc=$?
  if grep -q '^verdict unverified$' "$record" 2>/dev/null && ! grep -q '^verdict bound$' "$record" 2>/dev/null; then
    echo "PASS: selftest — an unresolvable status name yields verdict unverified, never bound (L-8)"
  else
    echo "FAIL: selftest — an unresolvable status name did not yield unverified (record: $(cat "$record" 2>/dev/null))"; sfail=1
  fi

  # --- H-5 negative: a non-numeric status id from the adapter -> unverified, never bound ---
  rc=0
  : > "$record"
  KIT_TRF_MODE=bad-statusid tr_read "$conf" "-" "$record" AB-1 "$_h40" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] && ! grep -q '^verdict bound$' "$record" 2>/dev/null \
    && echo "PASS: selftest — a non-numeric status id is refused/unverified before use (H-5)" \
    || { echo "FAIL: selftest — a non-numeric status id was not cleanly refused (rc=$rc)"; sfail=1; }

  # --- M-3: a hostile key (C0/DEL) is REFUSED outright, never stripped-and-bound ---
  rc=0
  : > "$record"
  export KIT_TRF_MODE=hostile-id
  tr_read "$conf" "-" "$record" AB-1 "$_h40" >/dev/null 2>&1 || rc=$?
  unset KIT_TRF_MODE
  if [ "$rc" -eq 1 ] && ! grep -q '^verdict bound$' "$record" 2>/dev/null; then
    echo "PASS: selftest — a hostile key (C0/DEL) is refused outright, never stripped-and-bound (M-3)"
  else
    echo "FAIL: selftest — a hostile key was not refused outright (rc=$rc, record: $(cat "$record" 2>/dev/null))"; sfail=1
  fi

  # --- S-2: a mismatched origin conf refuses to send the token (no adapter dispatch) ---
  originconf="$tmpd/origin.conf"
  cat > "$originconf" <<'EOF'
version=1
backend=fixture
base_url=https://different.atlassian.net
flavour=cloud
auth=basic
project=ZZ
EOF
  rc=0
  dispatchlog="$tmpd/dispatch.count"
  : > "$dispatchlog"
  cat > "$fakedir/tracker-fixture.sh" <<EOF
#!/bin/sh
echo x >> "$dispatchlog"
case "\$1" in
  get-issue) printf 'key\tAB-1\n'; printf 'status-id\t3\n'; printf 'status-name\tIn Progress\n'; exit 0 ;;
  permissions) echo ok; exit 0 ;;
esac
EOF
  chmod +x "$fakedir/tracker-fixture.sh"
  tr_read "$conf" "$originconf" "$record" AB-1 "$_h40" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -ne 0 ] && [ ! -s "$dispatchlog" ]; then
    echo "PASS: selftest — a pin mismatch refuses before any dispatch, token never sent (S-2)"
  else
    echo "FAIL: selftest — a pin mismatch did not refuse before dispatch (rc=$rc dispatched=$(cat "$dispatchlog" 2>/dev/null))"; sfail=1
  fi
  cp "$fakeadapter" "$fakedir/tracker-fixture.sh"

  # --- reviewer M1: the pin digest changes when the conf CONTENTS change, even with base_url same ---
  conf2="$tmpd/tracker2.conf"
  cat > "$conf2" <<'EOF'
version=1
backend=fixture
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
state.in-progress=In Progress
list_cap=50
EOF
  : > "$record"; r1="$tmpd/r1.txt"; r2="$tmpd/r2.txt"
  KIT_TRF_MODE=good tr_read "$conf" "-" "$r1" AB-1 "$_h40" >/dev/null 2>&1 || true
  KIT_TRF_MODE=good tr_read "$conf2" "-" "$r2" AB-1 "$_h40" >/dev/null 2>&1 || true
  p1=$(awk '/^pin /{print}' "$r1" 2>/dev/null)
  p2=$(awk '/^pin /{print}' "$r2" 2>/dev/null)
  if [ -n "$p1" ] && [ "$p1" != "$p2" ]; then
    echo "PASS: selftest — the pin digest covers the full conf contents, not just base_url (reviewer M1)"
  else
    echo "FAIL: selftest — the pin digest did not change when non-base_url conf content changed (p1='$p1' p2='$p2')"; sfail=1
  fi

  # --- S-6: a failure sentence carries a status id, not a tracker status NAME ---
  : > "$record"
  export KIT_TRF_MODE=unmapped
  err=$(tr_read "$conf" "-" "$record" AB-1 "$_h40" 2>&1 >/dev/null) || true
  unset KIT_TRF_MODE
  case "$err" in
    *"status id 999"*) echo "PASS: selftest — the failure sentence names a status id, not a tracker name (S-6)" ;;
    *) echo "FAIL: selftest — failure sentence did not name a status id: $err"; sfail=1 ;;
  esac

  # --- malformed id refused ---
  rc=0
  tr_read "$conf" "-" "$record" "lowercase-id" "$_h40" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 1 ] && echo "PASS: selftest — a malformed id is refused" \
    || { echo "FAIL: selftest — a malformed id was not refused (rc=$rc)"; sfail=1; }

  # --- L-1: a backend token with a bad SECOND (not just first) character is refused ---
  badbackendconf="$tmpd/badbackend.conf"
  cat > "$badbackendconf" <<'EOF'
version=1
backend=fixture
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
EOF
  # tracker-conf.sh itself already refuses a non-lowercase backend value at the conf-grammar
  # layer; L-1 is about tr_adapter_path's OWN check being full-string, not first-character-only —
  # proven directly against the function rather than through a conf round-trip.
  if tr_adapter_path "fx;rm-rf" >/dev/null 2>&1; then
    echo "FAIL: selftest — tr_adapter_path accepted a backend token with a bad non-first character (L-1)"; sfail=1
  else
    echo "PASS: selftest — tr_adapter_path refuses a backend token with a bad non-first character (L-1)"
  fi

  # --- S-10: --selftest refuses (as a SEPARATE subprocess) when a token env var is set ---
  # N-3: this subprocess must carry the INCREMENTED depth, or a mutant that removes the S-10
  # refusal below turns this into an infinite recursion (this call spawns another --selftest with
  # the SAME leaked token, which would spawn another, ...) instead of a clean RC failure — the
  # L-2 guard exists precisely to bound that, but only if it actually SEES the depth grow.
  _self=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)/scripts/tracker-read.sh
  rc=0
  KIT_TR_SELFTEST_DEPTH=$((_depth + 1)) KIT_TRACKER_TOKEN="leaked" sh "$_self" --selftest >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ] && echo "PASS: selftest — --selftest refuses when a token env var is set (S-10)" \
    || { echo "FAIL: selftest — --selftest ran to completion with a token env var set (S-10)"; sfail=1; }

  # --- H-2/F-11 (T4): head-sha argument legs — the reader takes <head> as its 5th positional arg,
  # not derived internally via `git rev-parse HEAD` (H-2 closes the replay hole). ------------------

  # leg 1: a 40-hex head -> exit 0, record's head line is that sha verbatim.
  rc=0
  : > "$record"
  KIT_TRF_MODE=good tr_read "$conf" "-" "$record" AB-1 "$_h40" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 0 ] && grep -q "^head $_h40\$" "$record" 2>/dev/null; then
    echo "PASS: selftest — a 40-hex head is accepted and written verbatim to the record's head line (H-2/F-11)"
  else
    echo "FAIL: selftest — a 40-hex head was not accepted/written verbatim (rc=$rc, record: $(cat "$record" 2>/dev/null))"; sfail=1
  fi

  # leg 2: a 64-hex head -> accepted, verbatim.
  rc=0
  : > "$record"
  KIT_TRF_MODE=good tr_read "$conf" "-" "$record" AB-1 "$_h64" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 0 ] && grep -q "^head $_h64\$" "$record" 2>/dev/null; then
    echo "PASS: selftest — a 64-hex head is accepted and written verbatim (H-2/F-11)"
  else
    echo "FAIL: selftest — a 64-hex head was not accepted/written verbatim (rc=$rc, record: $(cat "$record" 2>/dev/null))"; sfail=1
  fi

  # --- head/state grammar negatives: each proves rc 1 AND no adapter dispatch (validated before any
  # request). The call-log path is BAKED into the fake adapter's own body (not env-carried — env
  # does not reach it) so a mutant that drops an env var still gets caught. ------------------------
  _h0_40="0000000000000000000000000000000000000000"
  _h0_64="0000000000000000000000000000000000000000000000000000000000000000"
  hslog="$tmpd/hs-dispatch.count"
  cat > "$fakedir/tracker-fixture.sh" <<EOF
#!/bin/sh
echo x >> "$hslog"
case "\$1" in
  get-issue) printf 'key\tAB-1\n'; printf 'status-id\t3\n'; printf 'status-name\tIn Progress\n'; exit 0 ;;
  permissions) echo ok; exit 0 ;;
esac
EOF
  chmod +x "$fakedir/tracker-fixture.sh"

  # leg 3: an all-zero 40-hex head -> rc 1, no adapter call.
  rc=0
  : > "$hslog"; : > "$record"
  tr_read "$conf" "-" "$record" AB-1 "$_h0_40" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$hslog" ]; then
    echo "PASS: selftest — an all-zero 40-hex head is refused (rc 1), no adapter dispatch (H-2/F-11)"
  else
    echo "FAIL: selftest — an all-zero 40-hex head was not cleanly refused before dispatch (rc=$rc, dispatched=$(cat "$hslog" 2>/dev/null))"; sfail=1
  fi

  # leg 4: an all-zero 64-hex head -> rc 1, no adapter call.
  rc=0
  : > "$hslog"; : > "$record"
  tr_read "$conf" "-" "$record" AB-1 "$_h0_64" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$hslog" ]; then
    echo "PASS: selftest — an all-zero 64-hex head is refused (rc 1), no adapter dispatch (H-2/F-11)"
  else
    echo "FAIL: selftest — an all-zero 64-hex head was not cleanly refused before dispatch (rc=$rc, dispatched=$(cat "$hslog" 2>/dev/null))"; sfail=1
  fi

  # leg 5: a malformed head (short token, upper-case hex, 39 chars) -> rc 1, no adapter call.
  for _badhead in abc "111111111111111111111111111111111111111A" "111111111111111111111111111111111111111"; do
    rc=0
    : > "$hslog"; : > "$record"
    tr_read "$conf" "-" "$record" AB-1 "$_badhead" >/dev/null 2>&1 || rc=$?
    if [ "$rc" -eq 1 ] && [ ! -s "$hslog" ]; then
      echo "PASS: selftest — a malformed head '$_badhead' is refused (rc 1), no adapter dispatch (H-2/F-11)"
    else
      echo "FAIL: selftest — a malformed head '$_badhead' was not cleanly refused before dispatch (rc=$rc, dispatched=$(cat "$hslog" 2>/dev/null))"; sfail=1
    fi
  done

  # leg 6: a state outside §4.1 ('readyy') -> rc 1, no adapter call.
  rc=0
  : > "$hslog"; : > "$record"
  tr_read "$conf" "-" "$record" AB-1 "$_h40" readyy >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$hslog" ]; then
    echo "PASS: selftest — a state outside §4.1 ('readyy') is refused (rc 1), no adapter dispatch"
  else
    echo "FAIL: selftest — a state outside §4.1 was not cleanly refused before dispatch (rc=$rc, dispatched=$(cat "$hslog" 2>/dev/null))"; sfail=1
  fi

  # leg 7: a duplicate state ('ready ready') -> rc 1, no adapter call.
  rc=0
  : > "$hslog"; : > "$record"
  tr_read "$conf" "-" "$record" AB-1 "$_h40" ready ready >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$hslog" ]; then
    echo "PASS: selftest — a duplicate state ('ready ready') is refused (rc 1), no adapter dispatch"
  else
    echo "FAIL: selftest — a duplicate state was not cleanly refused before dispatch (rc=$rc, dispatched=$(cat "$hslog" 2>/dev/null))"; sfail=1
  fi

  # F-2: tr_valid_state matched any run of ADJACENT vocabulary words (substring on the
  # space-joined list), not a single whole token — so a single caller arg spanning two states
  # wrongly passed membership, and a duplicate hidden inside such a multi-word arg wrongly passed
  # the dup check too (each is a distinct arg to the dup-tracker, not a re-seen single token).

  # leg 7a: a single arg spanning two adjacent vocabulary words ('ready in-progress') -> rc 1, no
  # adapter call (it is not itself a §4.1 state token, whole-token).
  rc=0
  : > "$hslog"; : > "$record"
  tr_read "$conf" "-" "$record" AB-1 "$_h40" "ready in-progress" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$hslog" ]; then
    echo "PASS: selftest — a single-arg run of two adjacent states ('ready in-progress') is refused, no adapter dispatch (F-2)"
  else
    echo "FAIL: selftest — a single-arg run of two adjacent states was not cleanly refused before dispatch (rc=$rc, dispatched=$(cat "$hslog" 2>/dev/null))"; sfail=1
  fi

  # leg 7b: a real state plus the same multi-word arg hides a duplicate ('ready' + 'ready
  # in-progress') -> rc 1, no adapter call.
  rc=0
  : > "$hslog"; : > "$record"
  tr_read "$conf" "-" "$record" AB-1 "$_h40" ready "ready in-progress" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$hslog" ]; then
    echo "PASS: selftest — 'ready' plus 'ready in-progress' is refused, no adapter dispatch (F-2)"
  else
    echo "FAIL: selftest — 'ready' plus 'ready in-progress' was not cleanly refused before dispatch (rc=$rc, dispatched=$(cat "$hslog" 2>/dev/null))"; sfail=1
  fi

  # leg 7c (F-4/F-12, step 0 Low): an ESC-byte state -> rc 1, the FIXED sentence (no misleading
  # stripped token); the exact-string match proves no stray byte reaches stderr (od -c, evidence log).
  _step0_expected="refused: state outside §4.1 (control bytes removed)"
  rc=0
  : > "$hslog"; : > "$record"
  _escstate=$(printf 'read\033y')
  _escerr=$(tr_read "$conf" "-" "$record" AB-1 "$_h40" "$_escstate" 2>&1 >/dev/null) || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$hslog" ] && [ "$_escerr" = "$_step0_expected" ]; then
    echo "PASS: selftest — a state carrying an ESC byte is refused with the fixed sentence, no non-printable byte on stderr (F-4/F-12, step 0)"
  else
    echo "FAIL: selftest — a state carrying an ESC byte was not cleanly/safely refused (rc=$rc, stderr='$_escerr')"; sfail=1
  fi

  # step 0 (security Low, new leg): a C1/high byte (0x85, outside 0x20-0x7E) is ALSO stripped — the
  # prior tr_strip_c0 (`tr -d '\000-\037\177'`) left 0x80-0xFF untouched; same shape as the ESC leg.
  rc=0
  : > "$hslog"; : > "$record"
  _c1state=$(printf 'read\205y')
  _c1err=$(tr_read "$conf" "-" "$record" AB-1 "$_h40" "$_c1state" 2>&1 >/dev/null) || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$hslog" ] && [ "$_c1err" = "$_step0_expected" ]; then
    echo "PASS: selftest — a state carrying a C1/high byte (0x85) is refused with the fixed sentence, no non-printable byte on stderr (step 0)"
  else
    echo "FAIL: selftest — a state carrying a C1/high byte was not cleanly/safely refused (rc=$rc, stderr='$_c1err')"; sfail=1
  fi

  # leg 7d (F-5): the record path EQUALS the conf path -> rc 1, and the conf is byte-identical
  # afterward (never touched, not even truncated).
  rc=0
  confbefore=$(cat "$conf")
  tr_read "$conf" "-" "$conf" AB-1 "$_h40" >/dev/null 2>&1 || rc=$?
  confafter=$(cat "$conf")
  if [ "$rc" -eq 1 ] && [ "$confbefore" = "$confafter" ]; then
    echo "PASS: selftest — a record path equal to the conf path is refused, conf left untouched (F-5)"
  else
    echo "FAIL: selftest — a record path equal to the conf path was not cleanly refused/left the conf untouched (rc=$rc)"; sfail=1
  fi

  # leg 7d2 (F-5): ISOLATE the equality check from the not-a-record check — a "conf" whose content
  # already looks like a §4.3 record (first line 'kit-tracker-read 1') would otherwise sail past the
  # not-a-record check, so refusal here can ONLY come from the record==conf equality test itself.
  reclikeconf="$tmpd/reclike.conf"
  printf 'kit-tracker-read 1\nbackend fixture\n' > "$reclikeconf"
  rc=0
  reclikebefore=$(cat "$reclikeconf")
  tr_read "$reclikeconf" "-" "$reclikeconf" AB-1 "$_h40" >/dev/null 2>&1 || rc=$?
  reclikeafter=$(cat "$reclikeconf")
  if [ "$rc" -eq 1 ] && [ "$reclikebefore" = "$reclikeafter" ]; then
    echo "PASS: selftest — record==conf is refused even when the conf looks record-shaped, isolating the equality check (F-5)"
  else
    echo "FAIL: selftest — record==conf (record-shaped conf) was not cleanly refused/left untouched (rc=$rc)"; sfail=1
  fi

  # leg 7e (F-5): a non-empty file at the record path that is NOT a §4.3 record (first line isn't
  # 'kit-tracker-read 1') -> rc 1, file left byte-identical (never truncated).
  rc=0
  printf 'not a tracker record\nsome other content\n' > "$record"
  notrecbefore=$(cat "$record")
  tr_read "$conf" "-" "$record" AB-1 "$_h40" >/dev/null 2>&1 || rc=$?
  notrecafter=$(cat "$record")
  if [ "$rc" -eq 1 ] && [ "$notrecbefore" = "$notrecafter" ]; then
    echo "PASS: selftest — a non-record file at the record path is refused, left untouched (F-5)"
  else
    echo "FAIL: selftest — a non-record file at the record path was not cleanly refused/left untouched (rc=$rc)"; sfail=1
  fi

  # leg 8: a pre-seeded BOUND record at the path is EMPTY after a refused run (F-10).
  printf 'kit-tracker-read 1\nverdict bound\nrow AB-1 state=in-progress\n' > "$record"
  rc=0
  tr_read "$conf" "-" "$record" AB-1 "$_h0_40" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -ne 0 ] && [ ! -s "$record" ]; then
    echo "PASS: selftest — a pre-seeded bound record is emptied by a refused run (F-10)"
  else
    echo "FAIL: selftest — a pre-seeded bound record was not emptied by a refused run (rc=$rc, record: $(cat "$record" 2>/dev/null))"; sfail=1
  fi

  cp "$fakeadapter" "$fakedir/tracker-fixture.sh"

  # T5a2L leg 1 (Q1 rebuild): the fake selects its ops file BY STATE (via the status id) — drift
  # lock: still a `cat` of the adapter-proven per-state fixtures, never an inline printf.
  _t5a2l_realroot=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
  _t5a2l_ops="$_t5a2l_realroot/conformance/fixtures/tracker-jira/ops"
  listargvlog="$tmpd/list-argv.log"
  cat > "$fakedir/tracker-fixture.sh" <<EOF
#!/bin/sh
case "\$1" in
  get-issue) printf 'key\tAB-1\n'; printf 'status-id\t10002\n'; printf 'status-name\tIn Dev\n'; exit 0 ;;
  permissions) echo ok; exit 0 ;;
  list-in-states)
    shift
    printf '%s\n' "\$*" >> "$listargvlog"
    case "\$*" in
      *10001*) cat "$_t5a2l_ops/list-cloud-ready.out" ;;
      *10002*|*10003*) cat "$_t5a2l_ops/list-cloud-inprogress.out" ;;
      *) cat "$_t5a2l_ops/list-cloud-empty.out" ;;
    esac
    exit 0 ;;
esac
EOF
  chmod +x "$fakedir/tracker-fixture.sh"

  rc=0
  : > "$listargvlog"
  t5a2l_out=$(sh "$fakedir/tracker-fixture.sh" list-in-states https://ex.atlassian.net cloud AB 200 10001 2>/dev/null) || rc=$?
  t5a2l_expected=$(cat "$_t5a2l_ops/list-cloud-ready.out")
  if [ "$rc" -eq 0 ] && [ "$t5a2l_out" = "$t5a2l_expected" ] && [ -s "$listargvlog" ]; then
    echo "PASS: selftest — T5a2L leg 1: the fake adapter's list-in-states selects ops/list-cloud-ready.out for the ready status id, argv logged (Q1)"
  else
    echo "FAIL: selftest — T5a2L leg 1: ready-state list-in-states did not match ops/list-cloud-ready.out or log argv (rc=$rc, out='$t5a2l_out')"; sfail=1
  fi

  rc=0
  : > "$listargvlog"
  t5a2l_out=$(sh "$fakedir/tracker-fixture.sh" list-in-states https://ex.atlassian.net cloud AB 200 10002 10003 2>/dev/null) || rc=$?
  t5a2l_expected=$(cat "$_t5a2l_ops/list-cloud-inprogress.out")
  if [ "$rc" -eq 0 ] && [ "$t5a2l_out" = "$t5a2l_expected" ] && [ -s "$listargvlog" ]; then
    echo "PASS: selftest — T5a2L leg 1: the fake adapter's list-in-states selects ops/list-cloud-inprogress.out for the in-progress status ids, argv logged (Q1)"
  else
    echo "FAIL: selftest — T5a2L leg 1: in-progress-state list-in-states did not match ops/list-cloud-inprogress.out or log argv (rc=$rc, out='$t5a2l_out')"; sfail=1
  fi

  cp "$fakeadapter" "$fakedir/tracker-fixture.sh"

  # T5a2L legs 2-4 (Q1 rebuild): a BY-STATE fake gives ready/in-progress DISJOINT ids; backend=jira
  # so SEAM_ROOT (design §3h) can bind — its .kit/tracker.conf IS this lconf (the M-1 pin matches).
  _t5a2l_statusids="$_t5a2l_ops/status-ids-cloud.out"
  _t5a2l_seamroot="$tmpd/seamroot"; mkdir -p "$_t5a2l_seamroot/.kit"
  lconf="$_t5a2l_seamroot/.kit/tracker.conf"
  cat > "$lconf" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
list_cap=200
state.in-progress=In Dev
state.in-progress=In Review
state.ready=Selected
EOF
  cat > "$_t5a2l_seamroot/CLAUDE.md" <<'EOF'
- **Backlog backend**: Jira
EOF
  # H-1 (design §3h): the seam's own record loader, sourced once for legs 2-4's round-trip checks
  # and the Q1 negative below.
  . "$_t5a2l_realroot/conformance/backlog-lib.sh"

  cat > "$fakedir/tracker-jira.sh" <<EOF
#!/bin/sh
case "\$1" in
  get-issue) printf 'key\tAB-1\n'; printf 'status-id\t10002\n'; printf 'status-name\tIn Dev\n'; exit 0 ;;
  permissions) echo ok; exit 0 ;;
  status-ids) cat "$_t5a2l_statusids"; exit 0 ;;
  list-in-states)
    shift
    printf '%s\n' "\$*" >> "$listargvlog"
    case "\$*" in
      *10001*) cat "$_t5a2l_ops/list-cloud-ready.out" ;;
      *10002*|*10003*) cat "$_t5a2l_ops/list-cloud-inprogress.out" ;;
      *) cat "$_t5a2l_ops/list-cloud-empty.out" ;;
    esac
    exit 0 ;;
esac
EOF
  chmod +x "$fakedir/tracker-jira.sh"

  # leg 2 (Q1 fix1): states `ready in-progress` -> disjoint `list`/`row` lines matching the
  # per-state fixtures byte-for-byte, PLUS the H-1 round trip: the seam's own loader binds it.
  _t5a2l_pin=$(tr_pin_digest "$lconf")
  _t5a2l_day=$(date -u +%Y-%m-%d)
  leg2exp="$tmpd/leg2.expected"
  cat > "$leg2exp" <<EOF
kit-tracker-read 1
backend jira
pin sha256:$_t5a2l_pin
head $_h40
requested AB-1
read-day $_t5a2l_day
credential ok
verdict bound
row AB-1 state=in-progress
row AB-2 state=ready
row AB-3 state=ready
row AB-4 state=in-progress
list ready AB-2 AB-3
list in-progress AB-1 AB-4
EOF
  rc=0
  : > "$record"
  tr_read "$lconf" "-" "$record" AB-1 "$_h40" ready in-progress >/dev/null 2>&1 || rc=$?
  SEAM_ROOT="$_t5a2l_seamroot"; SEAM_RECORD="$record"; SEAM_HEAD="$_h40"
  _t5a2l_seamrc=0; _seam_record_load >/dev/null 2>&1 || _t5a2l_seamrc=$?
  if [ "$rc" -eq 0 ] && cmp -s "$record" "$leg2exp" && [ "$_t5a2l_seamrc" -eq 0 ]; then
    echo "PASS: selftest — T5a2L leg 2: states 'ready in-progress' write disjoint list+row lines matching the expected record byte-for-byte, and round-trip through the seam's own loader (rc 0, H-1)"
  else
    echo "FAIL: selftest — T5a2L leg 2: record or round-trip mismatch (rc=$rc, seam-rc=$_t5a2l_seamrc): $(diff "$leg2exp" "$record" 2>&1)"; sfail=1
  fi

  # Q1 negative (superseded by R6, T5a2M leg 7): the OLD shape — an adapter answering every state
  # with the SAME ids used to reach the seam raw and be refused there (§3b). The reader's own R6
  # race filter now catches this BEFORE writing — both lists omitted, the record still binds.
  cat > "$fakedir/tracker-jira.sh" <<EOF
#!/bin/sh
case "\$1" in
  get-issue) printf 'key\tAB-1\n'; printf 'status-id\t10002\n'; printf 'status-name\tIn Dev\n'; exit 0 ;;
  permissions) echo ok; exit 0 ;;
  status-ids) cat "$_t5a2l_statusids"; exit 0 ;;
  list-in-states) cat "$_t5a2l_ops/list-cloud-ready.out"; exit 0 ;;
esac
EOF
  chmod +x "$fakedir/tracker-jira.sh"
  rc=0
  oldrecord="$tmpd/oldshape-record.txt"
  : > "$oldrecord"
  tr_read "$lconf" "-" "$oldrecord" AB-1 "$_h40" ready in-progress >/dev/null 2>&1 || rc=$?
  SEAM_ROOT="$_t5a2l_seamroot"; SEAM_RECORD="$oldrecord"; SEAM_HEAD="$_h40"
  _t5a2l_oldrc=0; _seam_record_load >/dev/null 2>&1 || _t5a2l_oldrc=$?
  if [ "$rc" -eq 0 ] && [ "$_t5a2l_oldrc" -eq 0 ] && ! grep -q '^list ' "$oldrecord" 2>/dev/null \
     && grep -q '^verdict bound$' "$oldrecord" 2>/dev/null; then
    echo "PASS: selftest — T5a2L Q1 negative (superseded by R6): the OLD shape is now caught by the reader's own race filter before it ever reaches the seam — both lists omitted, round-trips (rc 0)"
  else
    echo "FAIL: selftest — T5a2L Q1 negative: the OLD-shape record was not handled by the R6 race filter (read-rc=$rc, seam-rc=$_t5a2l_oldrc, record: $(cat "$oldrecord" 2>/dev/null))"; sfail=1
  fi

  cat > "$fakedir/tracker-jira.sh" <<EOF
#!/bin/sh
case "\$1" in
  get-issue) printf 'key\tAB-1\n'; printf 'status-id\t10002\n'; printf 'status-name\tIn Dev\n'; exit 0 ;;
  permissions) echo ok; exit 0 ;;
  status-ids) cat "$_t5a2l_statusids"; exit 0 ;;
  list-in-states)
    shift
    printf '%s\n' "\$*" >> "$listargvlog"
    case "\$*" in
      *10001*) cat "$_t5a2l_ops/list-cloud-ready.out" ;;
      *10002*|*10003*) cat "$_t5a2l_ops/list-cloud-inprogress.out" ;;
      *) cat "$_t5a2l_ops/list-cloud-empty.out" ;;
    esac
    exit 0 ;;
esac
EOF
  chmod +x "$fakedir/tracker-jira.sh"

  # leg 3 (F-4): 'in-progress' is mapped to TWO names (In Dev/In Review, ids 10002/10003) — the
  # adapter's list-in-states must be dispatched ONCE, with BOTH ids, plus the H-1 round trip.
  rc=0
  : > "$record"; : > "$listargvlog"
  tr_read "$lconf" "-" "$record" AB-1 "$_h40" in-progress >/dev/null 2>&1 || rc=$?
  _t5a2l_lisargvlines=$(wc -l < "$listargvlog" | tr -d ' ')
  SEAM_ROOT="$_t5a2l_seamroot"; SEAM_RECORD="$record"; SEAM_HEAD="$_h40"
  _t5a2l_seamrc=0; _seam_record_load >/dev/null 2>&1 || _t5a2l_seamrc=$?
  if [ "$rc" -eq 0 ] && [ "$_t5a2l_lisargvlines" = "1" ] \
     && grep -q '10002' "$listargvlog" && grep -q '10003' "$listargvlog" \
     && [ "$_t5a2l_seamrc" -eq 0 ]; then
    echo "PASS: selftest — T5a2L leg 3: a multi-status state dispatches list-in-states ONCE with BOTH ids and round-trips through the seam (F-4, H-1)"
  else
    echo "FAIL: selftest — T5a2L leg 3: multi-status did not dispatch once with both ids or round-trip (rc=$rc, lines=$_t5a2l_lisargvlines, seam-rc=$_t5a2l_seamrc, log: $(cat "$listargvlog" 2>/dev/null))"; sfail=1
  fi

  # leg 4 (F-3): the subject (AB-1) resolves to its OWN requested state ('in-progress') and the
  # fixture's list includes it — it appears in that `list` line with EXACTLY ONE `row` (its own
  # header row; tr_write_record's filter drops tr_read_lists' would-be second one), plus the H-1
  # round trip.
  rc=0
  : > "$record"
  tr_read "$lconf" "-" "$record" AB-1 "$_h40" in-progress >/dev/null 2>&1 || rc=$?
  _t5a2l_subjrows=$(grep -c '^row AB-1 ' "$record" 2>/dev/null || true)
  SEAM_ROOT="$_t5a2l_seamroot"; SEAM_RECORD="$record"; SEAM_HEAD="$_h40"
  _t5a2l_seamrc=0; _seam_record_load >/dev/null 2>&1 || _t5a2l_seamrc=$?
  if [ "$rc" -eq 0 ] && [ "$_t5a2l_subjrows" = "1" ] \
     && grep -q '^row AB-1 state=in-progress$' "$record" 2>/dev/null \
     && grep -q '^list in-progress AB-1 AB-4$' "$record" 2>/dev/null \
     && [ "$_t5a2l_seamrc" -eq 0 ]; then
    echo "PASS: selftest — T5a2L leg 4: the subject listed in its own state appears in that list with exactly ONE row, and round-trips through the seam (F-3, H-1)"
  else
    echo "FAIL: selftest — T5a2L leg 4: subject row/list mismatch or round-trip failure (rc=$rc, subject-rows=$_t5a2l_subjrows, seam-rc=$_t5a2l_seamrc, record: $(cat "$record" 2>/dev/null))"; sfail=1
  fi

  # Q2: a state that reads ZERO ids (legal) must still write `list <state>` (no trailing space) —
  # dropping the line leaves that state UNVERIFIED forever (H-3). Fresh conf: 'ready' -> 0 bytes.
  _t5a2l_emptyroot="$tmpd/emptyroot"; mkdir -p "$_t5a2l_emptyroot/.kit"
  emptyconf="$_t5a2l_emptyroot/.kit/tracker.conf"
  cat > "$emptyconf" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
list_cap=200
state.in-progress=In Progress
state.ready=Selected
EOF
  cat > "$_t5a2l_emptyroot/CLAUDE.md" <<'EOF'
- **Backlog backend**: Jira
EOF
  cat > "$fakedir/tracker-jira.sh" <<EOF
#!/bin/sh
case "\$1" in
  get-issue) printf 'key\tAB-1\n'; printf 'status-id\t3\n'; printf 'status-name\tIn Progress\n'; exit 0 ;;
  permissions) echo ok; exit 0 ;;
  status-ids) cat "$_t5a2l_statusids"; exit 0 ;;
  list-in-states) cat "$_t5a2l_ops/list-cloud-empty.out"; exit 0 ;;
esac
EOF
  chmod +x "$fakedir/tracker-jira.sh"

  rc=0
  emptyrecord="$tmpd/empty-record.txt"
  : > "$emptyrecord"
  tr_read "$emptyconf" "-" "$emptyrecord" AB-1 "$_h40" ready >/dev/null 2>&1 || rc=$?
  # shellcheck disable=SC2034 # all three read by backlog-lib.sh's sourced seam functions
  SEAM_ROOT="$_t5a2l_emptyroot"
  # shellcheck disable=SC2034
  SEAM_RECORD="$emptyrecord"
  # shellcheck disable=SC2034
  SEAM_HEAD="$_h40"
  _t5a2l_emptyseamrc=0; _seam_record_load >/dev/null 2>&1 || _t5a2l_emptyseamrc=$?
  # WB-FIX-A A1: the seam's rows-in-state ANSWER for this exact shape is asserted in
  # conformance/loop-state.sh's T6b section (WB-FIX-A Q2 leg), not here — a public seam call from
  # this file made board-parser-drift clause (c) treat the reader as a seam-routed board consumer,
  # and it names curl (D-240919-4: never allowlist curl, move the seam call instead).
  if [ "$rc" -eq 0 ] && grep -q '^list ready$' "$emptyrecord" 2>/dev/null \
     && [ "$_t5a2l_emptyseamrc" -eq 0 ]; then
    echo "PASS: selftest — Q2: a state that read EMPTY still writes 'list ready' (no trailing space) and round-trips (rc 0, H-3) — the answer half lives in loop-state.sh's T6b section (WB-FIX-A Q2)"
  else
    echo "FAIL: selftest — Q2: the legal-empty state was not preserved (rc=$rc, seam-rc=$_t5a2l_emptyseamrc, record: $(cat "$emptyrecord" 2>/dev/null))"; sfail=1
  fi

  cp "$fakeadapter" "$fakedir/tracker-fixture.sh"

  # Q4 (security L5): a single argument with an embedded space must stay ONE invalid token, never
  # split into two states — only reachable direct (tr_read's own CLI layer refuses it first).
  rc=0
  tr_read_lists "$lconf" "$fakedir/tracker-jira.sh" https://ex.atlassian.net cloud AB "ready in-progress" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 1 ]; then
    echo "PASS: selftest — Q4: tr_read_lists refuses a single joined argument ('ready in-progress') as one invalid state token, never silently splitting it into two (L5)"
  else
    echo "FAIL: selftest — Q4: tr_read_lists did not refuse the joined single-argument state (rc=$rc) — a \$*-based re-split would silently treat it as two valid states"; sfail=1
  fi

  # leg 9 (Q3: legs 0/5 DELETED — their "golden" was the mutable code's OWN output, so a mutant
  # was vacuous against it; this leg is the real, literal pin): zero states -> today's 9-line shape.
  rc=0
  : > "$record"
  KIT_TRF_MODE=good tr_read "$conf" "-" "$record" AB-1 "$_h40" >/dev/null 2>&1 || rc=$?
  _rlc=$(wc -l < "$record" | tr -d ' ')
  if [ "$rc" -eq 0 ] && [ "$_rlc" = "9" ] && ! grep -q '^list ' "$record" 2>/dev/null \
     && grep -q '^row AB-1 state=in-progress$' "$record" 2>/dev/null; then
    echo "PASS: selftest — zero states yields today's record shape plus the head line, no list line (backward compatible, Q3 pin)"
  else
    echo "FAIL: selftest — zero states did not yield today's shape (rc=$rc, lines=$_rlc, record: $(cat "$record" 2>/dev/null))"; sfail=1
  fi

  # Q5 (quality m5): tr_write_record's grep -v must distinguish "no match" (rc 1, fine — every
  # extra line matched the subject's own key and was correctly dropped) from grep ERRORING (rc 2+,
  # e.g. a key carrying a regex-special byte) — never fold an error into a silent write.
  rc=0
  q5record="$tmpd/q5-record.txt"
  : > "$q5record"
  tr_write_record "$q5record" fixture deadbeef "$_h40" AB-1 "$_t5a2l_day" ok bound 'AB-1[' in-progress 'row AB-2 state=ready' 2>/dev/null || rc=$?
  if [ "$rc" -eq 1 ] && [ ! -s "$q5record" ]; then
    echo "PASS: selftest — Q5: tr_write_record refuses (rc 1, record left untouched) when grep -v itself errors on a hostile key, rather than silently swallowing the error (m5)"
  else
    echo "FAIL: selftest — Q5: tr_write_record did not refuse a grep error cleanly (rc=$rc, record: $(cat "$q5record" 2>/dev/null))"; sfail=1
  fi

  # leg 10: four positional args (the old, pre-head-arg form) -> usage refusal, rc 2.
  _self=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)/scripts/tracker-read.sh
  rc=0
  _oldform_err=$(sh "$_self" "$conf" - "$record" AB-1 2>&1 >/dev/null) || rc=$?
  if [ "$rc" -eq 2 ]; then
    case "$_oldform_err" in
      *"usage: tracker-read.sh"*)
        echo "PASS: selftest — four positional args (the old form) is refused with usage, rc 2" ;;
      *)
        # F-1: under dash, an unbound $5 inside tr_read ALSO exits rc 2 (set -eu), so rc alone
        # cannot tell that clean usage refusal from this crash — require the usage text too.
        echo "FAIL: selftest — four positional args (the old form) exited rc 2 but printed no usage text (F-1; stderr: $_oldform_err)"; sfail=1 ;;
    esac
  else
    echo "FAIL: selftest — four positional args (the old form) was not refused with rc 2 (rc=$rc, stderr: $_oldform_err)"; sfail=1
  fi

  # --- 0a (T5a1 carried M-1): tr_valid_head must refuse the same way regardless of the caller's
  # locale — proven with a fresh sh AND dash process under LC_ALL=en_US.UTF-8 (T2a's locale-leg
  # pattern in tracker-jira.sh).
  _tr_cli_line=$(grep -n '^# --- CLI' "$0" | head -1 | cut -d: -f1)
  _tr_locale_check="$tmpd/locale-check-head.sh"
  head -n $((_tr_cli_line - 1)) "$0" > "$_tr_locale_check"
  printf 'tr_valid_head "$1"; exit $?\n' >> "$_tr_locale_check"
  _badhead_upper="111111111111111111111111111111111111111A"
  rc=0
  LC_ALL=en_US.UTF-8 sh "$_tr_locale_check" "$_badhead_upper" >/dev/null 2>&1 || rc=$?
  loc_sh_ok=0; [ "$rc" -eq 1 ] && loc_sh_ok=1
  loc_dash_note=""
  if command -v dash >/dev/null 2>&1; then
    rc=0
    LC_ALL=en_US.UTF-8 dash "$_tr_locale_check" "$_badhead_upper" >/dev/null 2>&1 || rc=$?
    loc_dash_ok=0; [ "$rc" -eq 1 ] && loc_dash_ok=1
  else
    loc_dash_ok=1
    loc_dash_note=" (dash arm SKIPPED — UNVERIFIED: no dash on PATH)"
  fi
  # fix1 F4 (corrected, 0b): bash 5.2/ubuntu:24.04 already refuses this under en_US.UTF-8
  # (globasciiranges) — only macOS bash 3.2 has the bug, so this arm pins the fix there.
  loc_bash_note=""
  if command -v bash >/dev/null 2>&1; then
    rc=0
    LC_ALL=en_US.UTF-8 bash "$_tr_locale_check" "$_badhead_upper" >/dev/null 2>&1 || rc=$?
    loc_bash_ok=0; [ "$rc" -eq 1 ] && loc_bash_ok=1
  else
    loc_bash_ok=1
    loc_bash_note=" (bash arm SKIPPED — UNVERIFIED: no bash on PATH)"
  fi
  loc_locale_note=""
  if ! command -v locale >/dev/null 2>&1 || ! locale -a 2>/dev/null | grep -qi '^en_us\.utf-\?8$'; then
    loc_locale_note=" (locale UNVERIFIED — en_US.UTF-8 not in \`locale -a\`)"
  fi
  if [ "$loc_sh_ok" -eq 1 ] && [ "$loc_dash_ok" -eq 1 ] && [ "$loc_bash_ok" -eq 1 ]; then
    echo "PASS: selftest — a head ending in uppercase 'A' refuses (rc 1) under LC_ALL=en_US.UTF-8 on a fresh sh AND dash AND bash process (0a/M-1)${loc_dash_note}${loc_bash_note}${loc_locale_note}"
  else
    echo "FAIL: selftest — the uppercase-A head was not refused under LC_ALL=en_US.UTF-8 (sh_ok=$loc_sh_ok dash_ok=$loc_dash_ok bash_ok=$loc_bash_ok)"; sfail=1
  fi

  # --- F-4 (T5a1): tr_resolve_state_ids — multi-status resolution. Drift lock: the fake adapter's
  # status-ids op serves the REAL fixture file the real adapter is proven to produce (T2a,
  # conformance/fixtures/tracker-jira/ops/status-ids-cloud.out) via `cat`, never an inline printf of
  # a status catalogue — so a drift between what the real adapter emits and what this selftest
  # assumes would show up here too, not just in tracker-jira.sh's own selftest. The two deliberately
  # MALFORMED modes below (fail/bad-id) are exempt from that rule by design: they exist to prove
  # this reader's own defence-in-depth against an adapter that misbehaves, not to stand in for the
  # real catalogue.
  _rsi_realroot=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
  _rsi_fixture="$_rsi_realroot/conformance/fixtures/tracker-jira/ops/status-ids-cloud.out"
  _rsi_fixture_dupname="$_rsi_realroot/conformance/fixtures/tracker-jira/ops/status-ids-dupname.out"
  sconf="$tmpd/state-ids.conf"
  cat > "$sconf" <<EOF
version=1
backend=fixture
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
state.in-progress=In Dev
state.in-progress=In Review
state.ready=Selected
state.done=NotInList
state.released=selected
state.backlog=Sel'ected
state.cancelled=In Progress
state.in-review=Selected
state.in-review=Selected
EOF
  cat > "$fakedir/tracker-fixture.sh" <<EOF
#!/bin/sh
case "\$1" in
  get-issue) printf 'key\tAB-1\n'; printf 'status-id\t3\n'; printf 'status-name\tIn Progress\n'; exit 0 ;;
  permissions) echo ok; exit 0 ;;
  status-ids)
    case "\$KIT_TRF_SI_MODE" in
      fail) printf '10001\tSelected\n'; exit 2 ;;
      bad-id) printf '3\tIn Progress\n10001\tSelected\nabc\tGarbage\n' ;;
      numeric-name) printf '3\t010\n' ;;
      leadingzero) printf '007\t10\n' ;;
      twonames) printf '3\tIn Progress\n3\tSelected\n' ;;
      twonames-numeric) printf '3\t10\n3\t010\n' ;;
      twonames-numeric-e) printf '3\t1e1\n3\t10\n' ;;
      dupname)
        # 0f (drift lock, R3): the adapter-proven ops/status-ids-dupname.out — never an inline
        # printf. Team-managed Jira projects legitimately expose TWO DIFFERENT status ids sharing
        # the SAME name — orchestrator ruling R3: a conf name maps to EVERY id with that name
        # (design §3c); refusing would permanently break such a project, and picking one silently
        # makes a partial list (F-4).
        cat "$_rsi_fixture_dupname" ;;
      *) cat "$_rsi_fixture" ;;
    esac
    exit 0 ;;
esac
EOF
  chmod +x "$fakedir/tracker-fixture.sh"

  # leg 1: a state mapped to two names, BOTH present in status-ids-cloud.out -> both ids, sorted.
  rc=0
  rsiout=$(tr_resolve_state_ids "$sconf" "$fakedir/tracker-fixture.sh" https://ex.atlassian.net cloud AB in-progress 2>/dev/null) || rc=$?
  if [ "$rc" -eq 0 ] && [ "$rsiout" = "10002
10003" ]; then
    echo "PASS: selftest — a state mapped to two names resolves both ids, sorted (F-4 leg 1)"
  else
    echo "FAIL: selftest — a state mapped to two names did not resolve both ids sorted (rc=$rc, out='$rsiout')"; sfail=1
  fi

  # leg 2: a state mapped to ONE name -> its one id, rc 0.
  rc=0
  rsiout=$(tr_resolve_state_ids "$sconf" "$fakedir/tracker-fixture.sh" https://ex.atlassian.net cloud AB ready 2>/dev/null) || rc=$?
  if [ "$rc" -eq 0 ] && [ "$rsiout" = "10001" ]; then
    echo "PASS: selftest — a state mapped to one name resolves its one id (F-4 leg 2)"
  else
    echo "FAIL: selftest — a state mapped to one name did not resolve its one id (rc=$rc, out='$rsiout')"; sfail=1
  fi

  # leg 3: a mapped name ABSENT from the status-ids output -> rc 2, stdout EMPTY (never partial).
  rc=0
  rsiout=$(tr_resolve_state_ids "$sconf" "$fakedir/tracker-fixture.sh" https://ex.atlassian.net cloud AB "done" 2>/dev/null) || rc=$?
  if [ "$rc" -eq 2 ] && [ -z "$rsiout" ]; then
    echo "PASS: selftest — an unmatched mapped name refuses that state's whole list, rc 2, empty stdout (F-4 leg 3)"
  else
    echo "FAIL: selftest — an unmatched mapped name did not cleanly refuse (rc=$rc, out='$rsiout')"; sfail=1
  fi

  # leg 4: a kit state with NO state.<kit> mapping in the conf -> rc 2, stdout empty.
  rc=0
  rsiout=$(tr_resolve_state_ids "$sconf" "$fakedir/tracker-fixture.sh" https://ex.atlassian.net cloud AB blocked 2>/dev/null) || rc=$?
  if [ "$rc" -eq 2 ] && [ -z "$rsiout" ]; then
    echo "PASS: selftest — a kit state with no state.<kit> mapping in the conf refuses, rc 2, empty stdout (F-4 leg 4)"
  else
    echo "FAIL: selftest — a kit state with no conf mapping did not cleanly refuse (rc=$rc, out='$rsiout')"; sfail=1
  fi

  # leg 5: the adapter's status-ids op fails (rc 2) -> rc 2, stdout empty. M-1: call with errexit
  # OFF inside the leg's own substitution (`set +e` FIRST, before the function call) — otherwise
  # dash's own abort-on-unguarded-failing-assignment semantics coincidentally produce rc 2 even
  # after the production `|| { ...; return 2; }` guard is deleted, hiding that deletion from this
  # leg under dash (though not under bash, which is lenient there); `set +e` disables that
  # coincidental protection too, so only the EXPLICIT guard can make this leg pass, in EVERY shell.
  rc=0
  export KIT_TRF_SI_MODE=fail
  rsiout=$(set +e; tr_resolve_state_ids "$sconf" "$fakedir/tracker-fixture.sh" https://ex.atlassian.net cloud AB ready 2>/dev/null) || rc=$?
  unset KIT_TRF_SI_MODE
  if [ "$rc" -eq 2 ] && [ -z "$rsiout" ]; then
    echo "PASS: selftest — a failed adapter status-ids op refuses, rc 2, empty stdout (F-4 leg 5)"
  else
    echo "FAIL: selftest — a failed adapter status-ids op did not cleanly refuse (rc=$rc, out='$rsiout')"; sfail=1
  fi

  # leg 6 (defence in depth): the adapter returns a line whose id is NOT digits -> rc 2, empty
  # stdout — even though the wanted name ('Selected') IS present and would otherwise resolve.
  rc=0
  rsiout=$(KIT_TRF_SI_MODE=bad-id tr_resolve_state_ids "$sconf" "$fakedir/tracker-fixture.sh" https://ex.atlassian.net cloud AB ready 2>/dev/null) || rc=$?
  if [ "$rc" -eq 2 ] && [ -z "$rsiout" ]; then
    echo "PASS: selftest — an adapter line with a non-digit id refuses, rc 2, empty stdout (F-4 leg 6)"
  else
    echo "FAIL: selftest — an adapter line with a non-digit id did not cleanly refuse (rc=$rc, out='$rsiout')"; sfail=1
  fi

  # leg 7: name matching is EXACT — a conf name differing only in case from the tracker's -> rc 2.
  # state.released=selected (lowercase) vs the .out file's "Selected" (capital S) — same word, wrong
  # case, must NOT match.
  rc=0
  rsiout=$(tr_resolve_state_ids "$sconf" "$fakedir/tracker-fixture.sh" https://ex.atlassian.net cloud AB released 2>/dev/null) || rc=$?
  if [ "$rc" -eq 2 ] && [ -z "$rsiout" ]; then
    echo "PASS: selftest — a conf name differing only in case from the tracker's is refused, rc 2 (F-4 leg 7)"
  else
    echo "FAIL: selftest — a case-only-differing name was not cleanly refused (rc=$rc, out='$rsiout')"; sfail=1
  fi

  # leg 8: a refusal sentence carries no status NAME — state.backlog maps to a hostile-looking
  # (apostrophe-bearing) name absent from the .out file; stderr must carry none of its bytes.
  rc=0
  rsierr=$(tr_resolve_state_ids "$sconf" "$fakedir/tracker-fixture.sh" https://ex.atlassian.net cloud AB backlog 2>&1 >/dev/null) || rc=$?
  if [ "$rc" -eq 2 ] && ! printf '%s' "$rsierr" | grep -qF "Sel'ected"; then
    echo "PASS: selftest — the refusal sentence carries no status name bytes (F-4 leg 8)"
  else
    echo "FAIL: selftest — the refusal sentence leaked the status name (rc=$rc, stderr: $rsierr)"; sfail=1
  fi

  # leg 9 (drift lock): the resolved ids for state.in-progress equal the ids computed straight from
  # the REAL fixture file for those exact names — computed here, not hard-coded — so a future
  # rename in the real fixture would break this leg rather than silently drift apart from it.
  rc=0
  rsiout=$(tr_resolve_state_ids "$sconf" "$fakedir/tracker-fixture.sh" https://ex.atlassian.net cloud AB in-progress 2>/dev/null) || rc=$?
  rsiexpected=$(awk -F'\t' '$2=="In Dev"||$2=="In Review"{print $1}' "$_rsi_fixture" | LC_ALL=C sort -n)
  if [ "$rc" -eq 0 ] && [ "$rsiout" = "$rsiexpected" ] && [ -n "$rsiexpected" ]; then
    echo "PASS: selftest — the resolved ids equal ids computed straight from the real fixture file (F-4 leg 9, drift lock)"
  else
    echo "FAIL: selftest — resolved ids diverged from the real-fixture-computed expectation (got '$rsiout', expected '$rsiexpected')"; sfail=1
  fi

  # --- fix1 I-4 (ruling R3) / 0f (drift lock): the awk lookup's trailing `exit` after the first
  # match silently dropped every OTHER id sharing that same status name. Team-managed Jira
  # projects legitimately expose two DIFFERENT ids under the SAME status name; a mapped name must
  # resolve to EVERY matching id, not just the first. Expected ids are computed straight from the
  # adapter-proven ops/status-ids-dupname.out (0f), not hard-coded, so a future rename there breaks
  # this leg instead of silently drifting apart from it (mirrors F-4 leg 9's drift lock). --------
  rc=0
  rsiout=$(KIT_TRF_SI_MODE=dupname tr_resolve_state_ids "$sconf" "$fakedir/tracker-fixture.sh" https://ex.atlassian.net cloud AB cancelled 2>/dev/null) || rc=$?
  dupexpected=$(awk -F'\t' '$2=="In Progress"{print $1}' "$_rsi_fixture_dupname" | LC_ALL=C sort -n)
  if [ "$rc" -eq 0 ] && [ "$rsiout" = "$dupexpected" ] && [ -n "$dupexpected" ]; then
    echo "PASS: selftest — a duplicate status NAME with two different ids resolves BOTH, not just the first, from the adapter-proven fixture (fix1 I-4, R3, 0f)"
  else
    echo "FAIL: selftest — a duplicate status name did not resolve every id (rc=$rc, out='$rsiout', expected='$dupexpected')"; sfail=1
  fi

  # --- fix1 M-2 (duplicate conf values printed twice): a conf mapping a kit state to the SAME
  # name twice (get-all emitting that value twice) must resolve that one id ONCE, not twice. ---
  rc=0
  rsiout=$(tr_resolve_state_ids "$sconf" "$fakedir/tracker-fixture.sh" https://ex.atlassian.net cloud AB in-review 2>/dev/null) || rc=$?
  if [ "$rc" -eq 0 ] && [ "$rsiout" = "10001" ]; then
    echo "PASS: selftest — a duplicate conf value ('Selected' mapped twice) resolves the id ONCE (fix1 M-2)"
  else
    echo "FAIL: selftest — a duplicate conf value resolved the id more than once (rc=$rc, out='$rsiout')"; sfail=1
  fi

  # --- 0b (T5a1 carried L-2): the awk name match must compare as STRINGS — a numeric-looking
  # catalogue name ('010') must NOT match a conf mapping of '10' (awk's numeric-string coercion
  # would otherwise compare them as equal numbers).
  numconf="$tmpd/num.conf"
  cat > "$numconf" <<'EOF'
version=1
backend=fixture
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
state.ready=10
EOF
  rc=0
  rsiout=$(KIT_TRF_SI_MODE=numeric-name tr_resolve_state_ids "$numconf" "$fakedir/tracker-fixture.sh" https://ex.atlassian.net cloud AB ready 2>/dev/null) || rc=$?
  if [ "$rc" -eq 2 ] && [ -z "$rsiout" ]; then
    echo "PASS: selftest — a catalogue name '010' does not match a conf mapping of '10' (string, not numeric, compare) (0b/L-2)"
  else
    echo "FAIL: selftest — '010' wrongly matched '10' (numeric compare regression) (rc=$rc, out='$rsiout')"; sfail=1
  fi

  # --- 0c (T5a1 carried L-3, part 1): the catalogue id gate tightens to ^[1-9][0-9]*$ — a
  # leading-zero id ('007') must refuse, not silently pass a digits-only check.
  rc=0
  rsiout=$(KIT_TRF_SI_MODE=leadingzero tr_resolve_state_ids "$numconf" "$fakedir/tracker-fixture.sh" https://ex.atlassian.net cloud AB ready 2>/dev/null) || rc=$?
  if [ "$rc" -eq 2 ] && [ -z "$rsiout" ]; then
    echo "PASS: selftest — a leading-zero catalogue id ('007') refuses, rc 2, empty stdout (0c/L-3)"
  else
    echo "FAIL: selftest — a leading-zero catalogue id was not cleanly refused (rc=$rc, out='$rsiout')"; sfail=1
  fi

  # --- 0c (T5a1 carried L-3, part 2): one id under TWO different names is a corrupt/ambiguous
  # catalogue — refuse the whole read, rc 2, empty stdout, never pick either name.
  rc=0
  rsiout=$(KIT_TRF_SI_MODE=twonames tr_resolve_state_ids "$sconf" "$fakedir/tracker-fixture.sh" https://ex.atlassian.net cloud AB ready 2>/dev/null) || rc=$?
  if [ "$rc" -eq 2 ] && [ -z "$rsiout" ]; then
    echo "PASS: selftest — one id under two different names refuses the whole read, rc 2, empty stdout (0c/L-3)"
  else
    echo "FAIL: selftest — one id under two different names was not cleanly refused (rc=$rc, out='$rsiout')"; sfail=1
  fi

  # --- fix1 F1: tr_valid_statusids's id->name dedup must compare as STRINGS — '10'/'010' (and
  # '1e1'/'10') are numeric-equal, so a numeric compare would miss one id under two such names.
  # 0b: assert the fixed sentence on the WHOLE stderr (not just rc), as the 0d leg does below.
  _f1_expected="unverified: adapter returned an invalid status-ids catalogue"
  rc=0
  rsierr=$(KIT_TRF_SI_MODE=twonames-numeric tr_resolve_state_ids "$numconf" "$fakedir/tracker-fixture.sh" https://ex.atlassian.net cloud AB ready 2>&1 >/dev/null) || rc=$?
  if [ "$rc" -eq 2 ] && [ "$rsierr" = "$_f1_expected" ]; then
    echo "PASS: selftest — one id under two numeric-looking names ('10'/'010') refuses with the fixed sentence, rc 2 (fix1 F1, 0b)"
  else
    echo "FAIL: selftest — '10'/'010' under one id was not cleanly refused with the fixed sentence (rc=$rc, stderr='$rsierr')"; sfail=1
  fi

  rc=0
  rsierr=$(KIT_TRF_SI_MODE=twonames-numeric-e tr_resolve_state_ids "$numconf" "$fakedir/tracker-fixture.sh" https://ex.atlassian.net cloud AB ready 2>&1 >/dev/null) || rc=$?
  if [ "$rc" -eq 2 ] && [ "$rsierr" = "$_f1_expected" ]; then
    echo "PASS: selftest — one id under two numeric-looking names ('1e1'/'10') refuses with the fixed sentence, rc 2 (fix1 F1, 0b)"
  else
    echo "FAIL: selftest — '1e1'/'10' under one id was not cleanly refused with the fixed sentence (rc=$rc, stderr='$rsierr')"; sfail=1
  fi

  # --- 0d (T5a1 carried m-1, fix1 F3; step 0 security Low updates the expected text): tr_resolve_
  # state_ids validates <state> with tr_valid_state FIRST — an ESC-bearing state must refuse with
  # the fixed whole-stderr sentence (a silent `return 1` would still pass an ESC-absence-only check,
  # so pin the exact text too); the stripped value is misleading ('ready'), so it is omitted.
  rc=0
  _escstate2=$(printf 'read\033y')
  _d0_expected="refused: state outside §4.1 (control bytes removed)"
  rsierr=$(tr_resolve_state_ids "$sconf" "$fakedir/tracker-fixture.sh" https://ex.atlassian.net cloud AB "$_escstate2" 2>&1 >/dev/null) || rc=$?
  if [ "$rc" -ne 0 ] && [ "$rsierr" = "$_d0_expected" ]; then
    echo "PASS: selftest — an ESC-bearing state refuses with the fixed whole-stderr sentence, no raw ESC (0d/m-1, fix1 F3)"
  else
    echo "FAIL: selftest — an ESC-bearing state was not cleanly refused (rc=$rc, stderr='$rsierr', expected='$_d0_expected')"; sfail=1
  fi

  # --- T5a2M leg 1/2 setup: the fake adapter's list-in-states can be told to exit 2 or 1 on demand
  # (globally, or for ONLY the state whose ids include 10001/ready — F-10/F-6), and to leak hostile
  # stderr (leg 8), so the later legs can drive tr_read_lists' own failure-tolerance without
  # touching real tracker text.
  cat > "$fakedir/tracker-jira.sh" <<EOF
#!/bin/sh
case "\$1" in
  get-issue) printf 'key\tAB-1\n'; printf 'status-id\t10002\n'; printf 'status-name\tIn Dev\n'; exit 0 ;;
  permissions) echo ok; exit 0 ;;
  status-ids)
    case "\$KIT_TRF_LIS_MODE" in
      missing-ready-name) grep -v Selected "$_t5a2l_statusids" ;;
      *) cat "$_t5a2l_statusids" ;;
    esac
    exit 0 ;;
  list-in-states)
    case "\$KIT_TRF_LIS_MODE" in
      rc2) exit 2 ;;
      rc1) exit 1 ;;
    esac
    shift
    printf '%s\n' "\$*" >> "$listargvlog"
    case "\$KIT_TRF_LIS_MODE:\$*" in
      fail-ready-rc2:*10001*) exit 2 ;;
      fail-ready-rc1:*10001*) exit 1 ;;
      stderr-leak:*10001*) echo "curl: (6) Could not resolve host: ex.atlassian.net" >&2; exit 2 ;;
      bad-key-project:*10001*) printf 'AB-2\nXY-5\n'; exit 0 ;;
      bad-key-leadingzero:*10001*) printf 'AB-2\nAB-07\n'; exit 0 ;;
      combo:*10004*) exit 2 ;;
      combo:*10001*) printf 'AB-2\nXY-5\n'; exit 0 ;;
      race-dup:*10001*) printf 'AB-2\nAB-9\n'; exit 0 ;;
      race-dup:*10002*|race-dup:*10003*) printf 'AB-4\nAB-9\n'; exit 0 ;;
      race-subject:*10001*) printf 'AB-2\nAB-1\n'; exit 0 ;;
      race-subject:*10002*|race-subject:*10003*) cat "$_t5a2l_ops/list-cloud-inprogress.out"; exit 0 ;;
      blank-interior:*10001*) printf 'AB-2\n\nAB-3\n'; exit 0 ;;
      blank-leading:*10001*) printf '\nAB-2\nAB-3\n'; exit 0 ;;
      dup-subject:*10002*|dup-subject:*10003*) printf 'AB-1\nAB-1\nAB-4\n'; exit 0 ;;
    esac
    case "\$*" in
      *10001*) cat "$_t5a2l_ops/list-cloud-ready.out" ;;
      *10002*|*10003*) cat "$_t5a2l_ops/list-cloud-inprogress.out" ;;
      *) cat "$_t5a2l_ops/list-cloud-empty.out" ;;
    esac
    exit 0 ;;
esac
EOF
  chmod +x "$fakedir/tracker-jira.sh"

  rc=0
  KIT_TRF_LIS_MODE=rc2 sh "$fakedir/tracker-jira.sh" list-in-states https://ex.atlassian.net cloud AB 200 10001 >/dev/null 2>&1 || rc=$?
  t5a2m_rc2ok=0; [ "$rc" -eq 2 ] && t5a2m_rc2ok=1
  rc=0
  KIT_TRF_LIS_MODE=rc1 sh "$fakedir/tracker-jira.sh" list-in-states https://ex.atlassian.net cloud AB 200 10001 >/dev/null 2>&1 || rc=$?
  t5a2m_rc1ok=0; [ "$rc" -eq 1 ] && t5a2m_rc1ok=1
  if [ "$t5a2m_rc2ok" -eq 1 ] && [ "$t5a2m_rc1ok" -eq 1 ]; then
    echo "PASS: selftest — T5a2M leg 1: the fake adapter's list-in-states exits 2 and 1 on demand (KIT_TRF_LIS_MODE)"
  else
    echo "FAIL: selftest — T5a2M leg 1: list-in-states did not exit 2/1 as requested (rc2ok=$t5a2m_rc2ok rc1ok=$t5a2m_rc1ok)"; sfail=1
  fi

  # --- T5a2M leg 2 (F-10/F-6): a failed list-in-states call on ONE state omits only that state's
  # list line and its non-subject rows; a sibling state's list is still written, verdict unchanged,
  # and the record still round-trips through the seam.
  for t5a2m_mode in fail-ready-rc2 fail-ready-rc1; do
    rc=0
    t5a2m_record="$tmpd/leg2-$t5a2m_mode-record.txt"
    : > "$t5a2m_record"
    t5a2m_l2err=$(KIT_TRF_LIS_MODE=$t5a2m_mode tr_read "$lconf" "-" "$t5a2m_record" AB-1 "$_h40" ready in-progress 2>&1 >/dev/null) || rc=$?
    SEAM_ROOT="$_t5a2l_seamroot"; SEAM_RECORD="$t5a2m_record"; SEAM_HEAD="$_h40"
    t5a2m_seamrc=0; _seam_record_load >/dev/null 2>&1 || t5a2m_seamrc=$?
    t5a2m_l2expected="omitted: list ready (the tracker query failed, F-10/F-6)"
    if [ "$rc" -eq 0 ] && [ "$t5a2m_seamrc" -eq 0 ] && [ "$t5a2m_l2err" = "$t5a2m_l2expected" ] \
       && grep -q '^verdict bound$' "$t5a2m_record" \
       && ! grep -q '^list ready' "$t5a2m_record" \
       && ! grep -q 'state=ready' "$t5a2m_record" \
       && grep -q '^list in-progress AB-1 AB-4$' "$t5a2m_record"; then
      echo "PASS: selftest — T5a2M leg 2 ($t5a2m_mode): a failed list-in-states call omits only 'ready' with the fixed sentence, 'in-progress' still written, round-trips (F-10/F-6)"
    else
      echo "FAIL: selftest — T5a2M leg 2 ($t5a2m_mode): the adapter failure was not tolerated (rc=$rc, seam-rc=$t5a2m_seamrc, stderr='$t5a2m_l2err', record: $(cat "$t5a2m_record" 2>/dev/null))"; sfail=1
    fi
  done

  # --- T5a2M leg 3 (F-4): a mapped name absent from status-ids omits ONLY that state's list; a
  # sibling state's list is still written, verdict unchanged, round-trips through the seam.
  rc=0
  t5a2m_l3record="$tmpd/leg3-record.txt"
  : > "$t5a2m_l3record"
  t5a2m_l3err=$(KIT_TRF_LIS_MODE=missing-ready-name tr_read "$lconf" "-" "$t5a2m_l3record" AB-1 "$_h40" ready in-progress 2>&1 >/dev/null) || rc=$?
  SEAM_ROOT="$_t5a2l_seamroot"; SEAM_RECORD="$t5a2m_l3record"; SEAM_HEAD="$_h40"
  t5a2m_seamrc=0; _seam_record_load >/dev/null 2>&1 || t5a2m_seamrc=$?
  t5a2m_l3expected="omitted: list ready (the state could not be resolved, F-4)"
  if [ "$rc" -eq 0 ] && [ "$t5a2m_seamrc" -eq 0 ] && [ "$t5a2m_l3err" = "$t5a2m_l3expected" ] \
     && grep -q '^verdict bound$' "$t5a2m_l3record" \
     && ! grep -q '^list ready' "$t5a2m_l3record" \
     && grep -q '^list in-progress AB-1 AB-4$' "$t5a2m_l3record"; then
    echo "PASS: selftest — T5a2M leg 3: a mapped name absent from status-ids omits only 'ready' with the fixed sentence, 'in-progress' still written, round-trips (F-4)"
  else
    echo "FAIL: selftest — T5a2M leg 3: the unmapped name was not tolerated (rc=$rc, seam-rc=$t5a2m_seamrc, stderr='$t5a2m_l3err', record: $(cat "$t5a2m_l3record" 2>/dev/null))"; sfail=1
  fi

  # --- T5a2M leg 4 (R4): a listed key that fails the re-check (another project's key, or a leading
  # zero) omits ONLY that state's list; a sibling state's list is still written, round-trips.
  for t5a2m_badkey in bad-key-project bad-key-leadingzero; do
    rc=0
    t5a2m_l4record="$tmpd/leg4-$t5a2m_badkey-record.txt"
    : > "$t5a2m_l4record"
    t5a2m_l4err=$(KIT_TRF_LIS_MODE=$t5a2m_badkey tr_read "$lconf" "-" "$t5a2m_l4record" AB-1 "$_h40" ready in-progress 2>&1 >/dev/null) || rc=$?
    SEAM_ROOT="$_t5a2l_seamroot"; SEAM_RECORD="$t5a2m_l4record"; SEAM_HEAD="$_h40"
    t5a2m_seamrc=0; _seam_record_load >/dev/null 2>&1 || t5a2m_seamrc=$?
    # S1: the whole stderr must be the fixed sentence — no key text (AB-2/XY-5/AB-07) anywhere.
    t5a2m_l4expected="omitted: list ready (a listed key failed the re-check, R4)"
    if [ "$rc" -eq 0 ] && [ "$t5a2m_seamrc" -eq 0 ] && [ "$t5a2m_l4err" = "$t5a2m_l4expected" ] \
       && grep -q '^verdict bound$' "$t5a2m_l4record" \
       && ! grep -q '^list ready' "$t5a2m_l4record" \
       && grep -q '^list in-progress AB-1 AB-4$' "$t5a2m_l4record"; then
      echo "PASS: selftest — T5a2M leg 4 ($t5a2m_badkey): a listed key failing the re-check omits only 'ready' with the fixed sentence carrying no key text, round-trips (R4)"
    else
      echo "FAIL: selftest — T5a2M leg 4 ($t5a2m_badkey): the bad key was not re-checked (rc=$rc, seam-rc=$t5a2m_seamrc, stderr='$t5a2m_l4err', record: $(cat "$t5a2m_l4record" 2>/dev/null))"; sfail=1
    fi
  done

  # --- T5a2M leg 5 (R5): list_cap absent from the conf omits EVERY list, one fixed sentence naming
  # list_cap (no invented default); the subject row and verdict are unchanged.
  t5a2m_nocaproot="$tmpd/nocaproot"; mkdir -p "$t5a2m_nocaproot/.kit"
  t5a2m_nocapconf="$t5a2m_nocaproot/.kit/tracker.conf"
  cat > "$t5a2m_nocapconf" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
state.in-progress=In Dev
state.in-progress=In Review
state.ready=Selected
EOF
  cat > "$t5a2m_nocaproot/CLAUDE.md" <<'EOF'
- **Backlog backend**: Jira
EOF
  rc=0
  t5a2m_l5record="$tmpd/leg5-record.txt"
  : > "$t5a2m_l5record"
  t5a2m_l5err=$(tr_read "$t5a2m_nocapconf" "-" "$t5a2m_l5record" AB-1 "$_h40" ready in-progress 2>&1 >/dev/null) || rc=$?
  SEAM_ROOT="$t5a2m_nocaproot"; SEAM_RECORD="$t5a2m_l5record"; SEAM_HEAD="$_h40"
  t5a2m_seamrc=0; _seam_record_load >/dev/null 2>&1 || t5a2m_seamrc=$?
  t5a2m_l5expected="omitted: every list (no list_cap in the conf, R5)"
  if [ "$rc" -eq 0 ] && [ "$t5a2m_seamrc" -eq 0 ] && [ "$t5a2m_l5err" = "$t5a2m_l5expected" ] \
     && grep -q '^verdict bound$' "$t5a2m_l5record" \
     && ! grep -q '^list ' "$t5a2m_l5record" \
     && grep -q '^row AB-1 state=in-progress$' "$t5a2m_l5record"; then
    echo "PASS: selftest — T5a2M leg 5: list_cap absent omits EVERY list with one fixed sentence, subject row and verdict unchanged, round-trips (R5)"
  else
    echo "FAIL: selftest — T5a2M leg 5: a missing list_cap was not handled (rc=$rc, seam-rc=$t5a2m_seamrc, stderr='$t5a2m_l5err', record: $(cat "$t5a2m_l5record" 2>/dev/null))"; sfail=1
  fi

  # --- T5a2M fix1 C1: list_cap outside the adapter's own 1..99999 range must never reach a
  # dispatch — gated before any state loop, one sentence naming list_cap, no per-state F-10 spam.
  t5a2m_badcaproot="$tmpd/badcaproot"; mkdir -p "$t5a2m_badcaproot/.kit"
  t5a2m_badcapconf="$t5a2m_badcaproot/.kit/tracker.conf"
  cat > "$t5a2m_badcapconf" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
list_cap=100000
state.in-progress=In Dev
state.in-progress=In Review
state.ready=Selected
EOF
  cat > "$t5a2m_badcaproot/CLAUDE.md" <<'EOF'
- **Backlog backend**: Jira
EOF
  rc=0
  : > "$listargvlog"
  t5a2m_c1record="$tmpd/c1-record.txt"
  : > "$t5a2m_c1record"
  t5a2m_c1err=$(tr_read "$t5a2m_badcapconf" "-" "$t5a2m_c1record" AB-1 "$_h40" ready in-progress 2>&1 >/dev/null) || rc=$?
  SEAM_ROOT="$t5a2m_badcaproot"; SEAM_RECORD="$t5a2m_c1record"; SEAM_HEAD="$_h40"
  t5a2m_seamrc=0; _seam_record_load >/dev/null 2>&1 || t5a2m_seamrc=$?
  t5a2m_c1expected="omitted: every list (list_cap outside 1..99999, R5)"
  if [ "$rc" -eq 0 ] && [ "$t5a2m_seamrc" -eq 0 ] && [ "$t5a2m_c1err" = "$t5a2m_c1expected" ] \
     && [ ! -s "$listargvlog" ] \
     && grep -q '^verdict bound$' "$t5a2m_c1record" \
     && ! grep -q '^list ' "$t5a2m_c1record" \
     && grep -q '^row AB-1 state=in-progress$' "$t5a2m_c1record"; then
    echo "PASS: selftest — T5a2M fix1 C1: list_cap outside 1..99999 omits EVERY list with one sentence, never dispatches, round-trips"
  else
    echo "FAIL: selftest — T5a2M fix1 C1: an out-of-range list_cap was not gated before dispatch (rc=$rc, seam-rc=$t5a2m_seamrc, stderr='$t5a2m_c1err', argvlog='$(cat "$listargvlog" 2>/dev/null)', record: $(cat "$t5a2m_c1record" 2>/dev/null))"; sfail=1
  fi

  # --- T5a2M leg 6: four omission causes fire in ONE read (bad key, adapter failure, an unmapped
  # name, and a normal state) — the subject row is present exactly once regardless.
  t5a2m_comboroot="$tmpd/comboroot"; mkdir -p "$t5a2m_comboroot/.kit"
  t5a2m_comboconf="$t5a2m_comboroot/.kit/tracker.conf"
  cat > "$t5a2m_comboconf" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
list_cap=200
state.in-progress=In Dev
state.in-progress=In Review
state.ready=Selected
state.done=Done
state.blocked=NoSuchStatus
EOF
  cat > "$t5a2m_comboroot/CLAUDE.md" <<'EOF'
- **Backlog backend**: Jira
EOF
  rc=0
  t5a2m_l6record="$tmpd/leg6-record.txt"
  : > "$t5a2m_l6record"
  t5a2m_l6err=$(KIT_TRF_LIS_MODE=combo tr_read "$t5a2m_comboconf" "-" "$t5a2m_l6record" AB-1 "$_h40" ready in-progress "done" blocked 2>&1 >/dev/null) || rc=$?
  SEAM_ROOT="$t5a2m_comboroot"; SEAM_RECORD="$t5a2m_l6record"; SEAM_HEAD="$_h40"
  t5a2m_seamrc=0; _seam_record_load >/dev/null 2>&1 || t5a2m_seamrc=$?
  t5a2m_subjcount=$(grep -c '^row AB-1 ' "$t5a2m_l6record" 2>/dev/null || true)
  # S1: the whole stderr is exactly the three fixed sentences (ready/R4, done/F-10-F-6, blocked/F-4),
  # one per omission, in request order — no other text.
  t5a2m_l6expected="omitted: list ready (a listed key failed the re-check, R4)
omitted: list done (the tracker query failed, F-10/F-6)
omitted: list blocked (the state could not be resolved, F-4)"
  if [ "$rc" -eq 0 ] && [ "$t5a2m_seamrc" -eq 0 ] && [ "$t5a2m_subjcount" = "1" ] \
     && [ "$t5a2m_l6err" = "$t5a2m_l6expected" ] \
     && grep -q '^row AB-1 state=in-progress$' "$t5a2m_l6record" \
     && ! grep -q '^list ready' "$t5a2m_l6record" \
     && ! grep -q '^list done' "$t5a2m_l6record" \
     && ! grep -q '^list blocked' "$t5a2m_l6record" \
     && grep -q '^list in-progress AB-1 AB-4$' "$t5a2m_l6record"; then
    echo "PASS: selftest — T5a2M leg 6: four omission causes fire together with their fixed sentences, the subject row appears exactly once, round-trips"
  else
    echo "FAIL: selftest — T5a2M leg 6: the subject row was not preserved across combined omissions (rc=$rc, seam-rc=$t5a2m_seamrc, subj-count=$t5a2m_subjcount, stderr='$t5a2m_l6err', record: $(cat "$t5a2m_l6record" 2>/dev/null))"; sfail=1
  fi

  # --- T5a2M leg 7 (R6): a race between list queries. (a) a non-subject id returned under TWO
  # requested states poisons BOTH — neither list line survives. (b) the subject returned under a
  # state that is not its own poisons only THAT list — its own true state's list survives intact.
  # Both round-trip through the seam (the subject's bind survives).
  rc=0
  t5a2m_l7arecord="$tmpd/leg7-dup-record.txt"
  : > "$t5a2m_l7arecord"
  t5a2m_l7aerr=$(KIT_TRF_LIS_MODE=race-dup tr_read "$lconf" "-" "$t5a2m_l7arecord" AB-1 "$_h40" ready in-progress 2>&1 >/dev/null) || rc=$?
  SEAM_ROOT="$_t5a2l_seamroot"; SEAM_RECORD="$t5a2m_l7arecord"; SEAM_HEAD="$_h40"
  t5a2m_seamrc=0; _seam_record_load >/dev/null 2>&1 || t5a2m_seamrc=$?
  # S1: the whole stderr names BOTH poisoned states in one fixed sentence.
  t5a2m_l7aexpected="omitted: list ready in-progress (a race between list queries, R6)"
  if [ "$rc" -eq 0 ] && [ "$t5a2m_seamrc" -eq 0 ] && [ "$t5a2m_l7aerr" = "$t5a2m_l7aexpected" ] \
     && grep -q '^verdict bound$' "$t5a2m_l7arecord" \
     && ! grep -q '^list ready' "$t5a2m_l7arecord" \
     && ! grep -q '^list in-progress' "$t5a2m_l7arecord" \
     && grep -q '^row AB-1 state=in-progress$' "$t5a2m_l7arecord"; then
    echo "PASS: selftest — T5a2M leg 7a: a non-subject id duplicated across two states' lists poisons BOTH with the fixed sentence, round-trips (R6)"
  else
    echo "FAIL: selftest — T5a2M leg 7a: the duplicate-id race was not caught (rc=$rc, seam-rc=$t5a2m_seamrc, stderr='$t5a2m_l7aerr', record: $(cat "$t5a2m_l7arecord" 2>/dev/null))"; sfail=1
  fi

  rc=0
  t5a2m_l7brecord="$tmpd/leg7-subject-record.txt"
  : > "$t5a2m_l7brecord"
  t5a2m_l7berr=$(KIT_TRF_LIS_MODE=race-subject tr_read "$lconf" "-" "$t5a2m_l7brecord" AB-1 "$_h40" ready in-progress 2>&1 >/dev/null) || rc=$?
  # shellcheck disable=SC2034 # all three read by backlog-lib.sh's sourced seam functions
  SEAM_ROOT="$_t5a2l_seamroot"
  # shellcheck disable=SC2034
  SEAM_RECORD="$t5a2m_l7brecord"
  # shellcheck disable=SC2034
  SEAM_HEAD="$_h40"
  t5a2m_seamrc=0; _seam_record_load >/dev/null 2>&1 || t5a2m_seamrc=$?
  t5a2m_l7bexpected="omitted: list ready (a race between list queries, R6)"
  if [ "$rc" -eq 0 ] && [ "$t5a2m_seamrc" -eq 0 ] && [ "$t5a2m_l7berr" = "$t5a2m_l7bexpected" ] \
     && grep -q '^verdict bound$' "$t5a2m_l7brecord" \
     && ! grep -q '^list ready' "$t5a2m_l7brecord" \
     && grep -q '^list in-progress AB-1 AB-4$' "$t5a2m_l7brecord" \
     && grep -q '^row AB-1 state=in-progress$' "$t5a2m_l7brecord"; then
    echo "PASS: selftest — T5a2M leg 7b: the subject wrongly listed under 'ready' poisons only that list with the fixed sentence; its own true state's list survives, round-trips (R6)"
  else
    echo "FAIL: selftest — T5a2M leg 7b: the subject-wrong-state race was not caught (rc=$rc, seam-rc=$t5a2m_seamrc, stderr='$t5a2m_l7berr', record: $(cat "$t5a2m_l7brecord" 2>/dev/null))"; sfail=1
  fi

  # --- T5a2M leg 8 (security L3): the list-in-states dispatch gets 2>/dev/null like its siblings —
  # a hostile adapter's own stderr text (curl's own diagnostic) never reaches the reader's stderr;
  # the omission sentence is the ONLY output.
  rc=0
  t5a2m_l8record="$tmpd/leg8-record.txt"
  : > "$t5a2m_l8record"
  t5a2m_l8err=$(KIT_TRF_LIS_MODE=stderr-leak tr_read "$lconf" "-" "$t5a2m_l8record" AB-1 "$_h40" ready in-progress 2>&1 >/dev/null) || rc=$?
  t5a2m_l8expected="omitted: list ready (the tracker query failed, F-10/F-6)"
  if [ "$rc" -eq 0 ] && [ "$t5a2m_l8err" = "$t5a2m_l8expected" ]; then
    echo "PASS: selftest — T5a2M leg 8: a hostile adapter's stderr never leaks — the fixed omission sentence is the only output (security L3)"
  else
    echo "FAIL: selftest — T5a2M leg 8: hostile adapter stderr leaked (rc=$rc, stderr='$t5a2m_l8err', expected='$t5a2m_l8expected')"; sfail=1
  fi

  # --- T5a2M leg 9 (carried T5a2L fix1 security Low): tr_write_record's own grep -v pipeline gets
  # 2>/dev/null — grep's own diagnostic on a hostile key never reaches stderr; the fixed sentence
  # (leg Q5's same hostile key) is the ONLY line.
  rc=0
  t5a2m_l9record="$tmpd/leg9-record.txt"
  t5a2m_l9errfile="$tmpd/leg9-err.txt"
  : > "$t5a2m_l9record"
  # the call is protected by its OWN || (mirrors Q5/tr_read's own calling convention) — calling it
  # inside a bare $(...) instead would let set -e abort mid-function, before its own case/echo runs.
  tr_write_record "$t5a2m_l9record" fixture deadbeef "$_h40" AB-1 "$_t5a2l_day" ok bound 'AB-1[' in-progress 'row AB-2 state=ready' >/dev/null 2>"$t5a2m_l9errfile" || rc=$?
  t5a2m_l9err=$(cat "$t5a2m_l9errfile" 2>/dev/null)
  t5a2m_l9lines=$(printf '%s\n' "$t5a2m_l9err" | grep -c '.' || true)
  if [ "$rc" -eq 1 ] && [ "$t5a2m_l9lines" = "1" ] \
     && printf '%s' "$t5a2m_l9err" | grep -q "^refused: tr_write_record could not filter the subject's row (grep rc="; then
    echo "PASS: selftest — T5a2M leg 9: grep's own diagnostic on a hostile key never reaches stderr — the fixed sentence is the only line"
  else
    echo "FAIL: selftest — T5a2M leg 9: grep's own diagnostic leaked (rc=$rc, lines=$t5a2m_l9lines, stderr='$t5a2m_l9err')"; sfail=1
  fi

  # --- T5a2M fix1 K1: a blank line among the raw list-in-states keys (interior or leading) must
  # not desync the checked ids from the emitted `list` line bytes — normalise once at capture.
  for t5a2m_f1_mode in blank-interior blank-leading; do
    rc=0
    t5a2m_k1record="$tmpd/k1-$t5a2m_f1_mode-record.txt"
    : > "$t5a2m_k1record"
    # T5b1 step 0a: stderr captured SEPARATELY and asserted EMPTY — a blank is dropped silently by
    # design (quality fG: a leaked `dup key <id>` on this path must go RED here).
    t5a2m_k1err=$(KIT_TRF_LIS_MODE=$t5a2m_f1_mode tr_read "$lconf" "-" "$t5a2m_k1record" AB-1 "$_h40" ready in-progress 2>&1 >/dev/null) || rc=$?
    SEAM_ROOT="$_t5a2l_seamroot"; SEAM_RECORD="$t5a2m_k1record"; SEAM_HEAD="$_h40"
    t5a2m_seamrc=0; _seam_record_load >/dev/null 2>&1 || t5a2m_seamrc=$?
    if [ "$rc" -eq 0 ] && [ "$t5a2m_seamrc" -eq 0 ] && [ -z "$t5a2m_k1err" ] \
       && grep -q '^verdict bound$' "$t5a2m_k1record" \
       && ! grep -q '  ' "$t5a2m_k1record" \
       && grep -q '^list ready AB-2 AB-3$' "$t5a2m_k1record"; then
      echo "PASS: selftest — T5a2M fix1 K1 ($t5a2m_f1_mode): a blank raw key is dropped once at capture, checked==emitted, stderr EMPTY, round-trips"
    else
      echo "FAIL: selftest — T5a2M fix1 K1 ($t5a2m_f1_mode): a blank raw key desynced checked from emitted or leaked stderr (rc=$rc, seam-rc=$t5a2m_seamrc, stderr='$t5a2m_k1err', record: $(cat "$t5a2m_k1record" 2>/dev/null))"; sfail=1
    fi
  done

  # --- T5a2M fix1 K2: the subject repeated within its OWN state's list passes R6 (R6's dup pool
  # excludes the subject) — a key seen twice in one state's blob, subject included, is an R4
  # omission.
  rc=0
  t5a2m_k2record="$tmpd/k2-record.txt"
  : > "$t5a2m_k2record"
  # T5b1 step 0a: stderr captured SEPARATELY and asserted to be the WHOLE fixed R4 sentence — a
  # leaked tracker id (quality fG: `dup key <id>`) must go RED here.
  t5a2m_k2err=$(KIT_TRF_LIS_MODE=dup-subject tr_read "$lconf" "-" "$t5a2m_k2record" AB-1 "$_h40" ready in-progress 2>&1 >/dev/null) || rc=$?
  t5a2m_k2expected="omitted: list in-progress (a listed key failed the re-check, R4)"
  # shellcheck disable=SC2034 # all three read by backlog-lib.sh's sourced seam functions
  SEAM_ROOT="$_t5a2l_seamroot"
  # shellcheck disable=SC2034
  SEAM_RECORD="$t5a2m_k2record"
  # shellcheck disable=SC2034
  SEAM_HEAD="$_h40"
  t5a2m_seamrc=0; _seam_record_load >/dev/null 2>&1 || t5a2m_seamrc=$?
  if [ "$rc" -eq 0 ] && [ "$t5a2m_seamrc" -eq 0 ] && [ "$t5a2m_k2err" = "$t5a2m_k2expected" ] \
     && grep -q '^verdict bound$' "$t5a2m_k2record" \
     && grep -q '^row AB-1 state=in-progress$' "$t5a2m_k2record" \
     && ! grep -q '^list in-progress' "$t5a2m_k2record" \
     && grep -q '^list ready AB-2 AB-3$' "$t5a2m_k2record"; then
    echo "PASS: selftest — T5a2M fix1 K2: a key repeated within one state's own blob (subject included) is refused as an R4 omission, stderr is exactly the one sentence, round-trips"
  else
    echo "FAIL: selftest — T5a2M fix1 K2: a self-duplicated key was not caught or leaked stderr (rc=$rc, seam-rc=$t5a2m_seamrc, stderr='$t5a2m_k2err', record: $(cat "$t5a2m_k2record" 2>/dev/null))"; sfail=1
  fi

  # --- T5a2M fix1 Q3a: a direct tr_read_lists call (bypassing tr_read's own head/state grammar
  # gate) with a bad state token must not refuse silently — one fixed sentence, not empty stderr.
  rc=0
  t5a2m_q3a_err=$(tr_read_lists "$lconf" "$fakedir/tracker-jira.sh" https://ex.atlassian.net cloud AB BAD 2>&1 >/dev/null) || rc=$?
  t5a2m_q3a_expected="refused: state 'BAD' outside §4.1"
  if [ "$rc" -eq 1 ] && [ "$t5a2m_q3a_err" = "$t5a2m_q3a_expected" ]; then
    echo "PASS: selftest — T5a2M fix1 Q3a: a direct tr_read_lists call with a bad state token prints one fixed sentence, not silence"
  else
    echo "FAIL: selftest — T5a2M fix1 Q3a: a bad state token was silently refused (rc=$rc, stderr='$t5a2m_q3a_err')"; sfail=1
  fi

  # --- T5a2M fix1 Q3b: a state resolving to zero ids (tr_resolve_state_ids succeeds, empty ids)
  # must not omit silently either — one fixed sentence naming the state.
  t5a2m_q3b_err=$(
    tr_resolve_state_ids() { printf ''; return 0; }
    tr_read_one_state "$lconf" "$fakedir/tracker-jira.sh" https://ex.atlassian.net cloud AB 200 ready 2>&1 >/dev/null
  )
  rc=$?
  t5a2m_q3b_expected="omitted: list ready (no ids resolved for the state)"
  if [ "$rc" -eq 0 ] && [ "$t5a2m_q3b_err" = "$t5a2m_q3b_expected" ]; then
    echo "PASS: selftest — T5a2M fix1 Q3b: a state resolving to zero ids omits with one fixed sentence, not silence"
  else
    echo "FAIL: selftest — T5a2M fix1 Q3b: a zero-id resolution was silently omitted (rc=$rc, stderr='$t5a2m_q3b_err')"; sfail=1
  fi

  # --- T5b1 step 0 (T5a2M security L4, MIRROR leg): tr_list_keys_ok's per-id project grammar is a
  # second copy of the seam's own _seam_id_matches_project (conformance/backlog-lib.sh) — run BOTH
  # on the same id set and assert identical accept/refuse so the two can never silently drift.
  _srb_project=AB
  for _t5b1_mid in AB-7 ZZ-7 AB-07 AB- ABC-1 ab-1; do
    tr_list_keys_ok AB "$_t5b1_mid" >/dev/null 2>&1 && _t5b1_tlk_rc=0 || _t5b1_tlk_rc=$?
    _seam_id_matches_project "$_t5b1_mid" >/dev/null 2>&1 && _t5b1_seam_rc=0 || _t5b1_seam_rc=$?
    _t5b1_tlk_ok=0; [ "$_t5b1_tlk_rc" -eq 0 ] && _t5b1_tlk_ok=1
    _t5b1_seam_ok=0; [ "$_t5b1_seam_rc" -eq 0 ] && _t5b1_seam_ok=1
    if [ "$_t5b1_tlk_ok" -eq "$_t5b1_seam_ok" ]; then
      echo "PASS: selftest — T5b1 step 0 MIRROR ($_t5b1_mid): tr_list_keys_ok and _seam_id_matches_project agree (accept=$_t5b1_tlk_ok)"
    else
      echo "FAIL: selftest — T5b1 step 0 MIRROR ($_t5b1_mid): tr_list_keys_ok=$_t5b1_tlk_ok _seam_id_matches_project=$_t5b1_seam_ok DRIFT"; sfail=1
    fi
  done

  # --- T5bc fix1 B1(a) (security Medium): an id over 32 chars is refused by tr_list_keys_ok — 480
  # rows of long keys must never reach the seam's own byte cap and lose the subject's bind.
  _b1a_id33="AB-999999999999999999999999999999"
  if tr_list_keys_ok AB "$_b1a_id33" >/dev/null 2>&1; then
    echo "FAIL: selftest — T5bc fix1 B1(a): tr_list_keys_ok accepted a 33-char id (${#_b1a_id33} chars)"; sfail=1
  else
    echo "PASS: selftest — T5bc fix1 B1(a): tr_list_keys_ok refuses a 33-char id (${#_b1a_id33} chars, direct call)"
  fi

  # --- T5b1 step 0b (T5a2M fix1 security Low): an overflowing list_cap (23 digits) must not leak
  # a `[: ... integer expression expected`/`Illegal number` diagnostic — length-gate before any
  # numeric compare; stderr is exactly the one R5 sentence, the record still round-trips.
  _t5b1_bigcaproot="$tmpd/bigcaproot"; mkdir -p "$_t5b1_bigcaproot/.kit"
  _t5b1_bigcapconf="$_t5b1_bigcaproot/.kit/tracker.conf"
  cat > "$_t5b1_bigcapconf" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
list_cap=12345678901234567890123
state.in-progress=In Dev
EOF
  cat > "$_t5b1_bigcaproot/CLAUDE.md" <<'EOF'
- **Backlog backend**: Jira
EOF
  rc=0
  _t5b1_bigcaprecord="$tmpd/bigcap-record.txt"
  : > "$_t5b1_bigcaprecord"
  _t5b1_bigcaperr=$(tr_read "$_t5b1_bigcapconf" "-" "$_t5b1_bigcaprecord" AB-1 "$_h40" in-progress 2>&1 >/dev/null) || rc=$?
  _t5b1_bigcapexpected="omitted: every list (list_cap outside 1..99999, R5)"
  if [ "$rc" -eq 0 ] && [ "$_t5b1_bigcaperr" = "$_t5b1_bigcapexpected" ] && grep -q '^verdict bound$' "$_t5b1_bigcaprecord" 2>/dev/null; then
    echo "PASS: selftest — T5b1 step 0b: a 23-digit list_cap is length-gated before any numeric compare, stderr is exactly the one R5 sentence, no integer-expression leak, round-trips"
  else
    echo "FAIL: selftest — T5b1 step 0b: an overflowing list_cap leaked a diagnostic or was not gated (rc=$rc, stderr='$_t5b1_bigcaperr', record: $(cat "$_t5b1_bigcaprecord" 2>/dev/null))"; sfail=1
  fi

  # --- T5b1 leg 1: `claimed` on the subject from get-issue's assignee-present — drift lock: the
  # fake `cat`s the two adapter-proven ops files, never an inline printf. ZERO states requested
  # too (the subject row still gains `claimed=`, and the record still round-trips through the
  # seam's own loader). backend=jira (not the bare `fixture` token) so resolve_backend/CLAUDE.md
  # agree and the seam's own pin/backend checks bind (design §3h) — a dedicated root whose
  # .kit/tracker.conf byte-matches the conf tr_read is given.
  _t5b1_claimroot="$tmpd/claimroot"; mkdir -p "$_t5b1_claimroot/.kit"
  _t5b1_claimconf="$_t5b1_claimroot/.kit/tracker.conf"
  cat > "$_t5b1_claimconf" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
state.in-progress=In Progress
EOF
  cat > "$_t5b1_claimroot/CLAUDE.md" <<'EOF'
- **Backlog backend**: Jira
EOF
  cat > "$fakedir/tracker-jira.sh" <<EOF
#!/bin/sh
case "\$1" in
  get-issue)
    case "\$KIT_TRF_MODE" in
      assigned) cat "$_t5a2l_ops/get-issue-assigned.out" ;;
      unassigned) cat "$_t5a2l_ops/get-issue-unassigned.out" ;;
      noflag) printf 'key\tAB-7\n'; printf 'status-id\t3\n'; printf 'status-name\tIn Progress\n' ;;
    esac
    exit 0 ;;
  permissions) echo ok; exit 0 ;;
esac
EOF
  chmod +x "$fakedir/tracker-jira.sh"

  rc=0
  t5b1_l1arecord="$tmpd/l1-assigned-record.txt"
  : > "$t5b1_l1arecord"
  KIT_TRF_MODE=assigned tr_read "$_t5b1_claimconf" "-" "$t5b1_l1arecord" AB-7 "$_h40" >/dev/null 2>&1 || rc=$?
  SEAM_ROOT="$_t5b1_claimroot"; SEAM_RECORD="$t5b1_l1arecord"; SEAM_HEAD="$_h40"
  t5b1_l1a_seamrc=0; _seam_record_load >/dev/null 2>&1 || t5b1_l1a_seamrc=$?
  if [ "$rc" -eq 0 ] && [ "$t5b1_l1a_seamrc" -eq 0 ] \
     && grep -q '^row AB-7 state=in-progress claimed=yes$' "$t5b1_l1arecord" 2>/dev/null; then
    echo "PASS: selftest — T5b1 leg 1a: assignee-present=true on the subject writes claimed=yes, zero states requested, round-trips"
  else
    echo "FAIL: selftest — T5b1 leg 1a: assignee-present=true did not write claimed=yes (rc=$rc, seam-rc=$t5b1_l1a_seamrc, record: $(cat "$t5b1_l1arecord" 2>/dev/null))"; sfail=1
  fi

  rc=0
  t5b1_l1brecord="$tmpd/l1-unassigned-record.txt"
  : > "$t5b1_l1brecord"
  KIT_TRF_MODE=unassigned tr_read "$_t5b1_claimconf" "-" "$t5b1_l1brecord" AB-7 "$_h40" >/dev/null 2>&1 || rc=$?
  SEAM_ROOT="$_t5b1_claimroot"; SEAM_RECORD="$t5b1_l1brecord"; SEAM_HEAD="$_h40"
  t5b1_l1b_seamrc=0; _seam_record_load >/dev/null 2>&1 || t5b1_l1b_seamrc=$?
  if [ "$rc" -eq 0 ] && [ "$t5b1_l1b_seamrc" -eq 0 ] \
     && grep -q '^row AB-7 state=in-progress claimed=no$' "$t5b1_l1brecord" 2>/dev/null; then
    echo "PASS: selftest — T5b1 leg 1b: assignee-present=false on the subject writes claimed=no, round-trips"
  else
    echo "FAIL: selftest — T5b1 leg 1b: assignee-present=false did not write claimed=no (rc=$rc, seam-rc=$t5b1_l1b_seamrc, record: $(cat "$t5b1_l1brecord" 2>/dev/null))"; sfail=1
  fi

  # required mutant guard: an absent assignee-present field must OMIT claimed, never default yes.
  rc=0
  t5b1_l1crecord="$tmpd/l1-noflag-record.txt"
  : > "$t5b1_l1crecord"
  KIT_TRF_MODE=noflag tr_read "$_t5b1_claimconf" "-" "$t5b1_l1crecord" AB-7 "$_h40" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 0 ] && grep -q '^row AB-7 state=in-progress$' "$t5b1_l1crecord" 2>/dev/null \
     && ! grep -q 'claimed=' "$t5b1_l1crecord" 2>/dev/null; then
    echo "PASS: selftest — T5b1 leg 1c: an absent assignee-present field omits claimed entirely, never defaults to yes"
  else
    echo "FAIL: selftest — T5b1 leg 1c: an absent assignee-present field did not omit claimed (rc=$rc, record: $(cat "$t5b1_l1crecord" 2>/dev/null))"; sfail=1
  fi

  # fix1 V5: the "loop-state --selftest stays rc 0" check removed here — it ran loop-state's OWN
  # records and could never be reddened by any tracker-read.sh mutant (it was also the one Docker
  # failure, an environment limitation of loop-state.sh's own change-class-derivation leg under a
  # bare read-only mount, unrelated to this file). The real pin on the record round-trip touching a
  # claimed=/dor-size= token is the `_seam_record_load` checks already run by legs 1a/1b/2/6 above
  # (t5b1_l1a_seamrc/t5b1_l1b_seamrc/t5b1_l2_seamrc/t5b1_l6_seamrc) — those ARE the non-vacuous pin.

  # --- T5b1 leg 2: `dor-size` on `ready` rows AND on the subject when IT is ready, from ONE
  # label-counts call over the combined ready id set — count 0 -> no, 1 -> yes, >=2 -> the token
  # OMITTED (F-8, never first-wins). The subject (AB-1) is itself ready.
  # fix1 V4 (drift lock): label-counts is now a bare `cat` of the real, adapter-proven
  # label-counts.out — AB-1 (subject)/AB-2/AB-3/AB-4 is exactly that file's own id set, so no
  # filtering is needed and all three F-8 branches (0/1/>=2) are exercised from real bytes.
  _t5b1_sizeroot="$tmpd/sizeroot"; mkdir -p "$_t5b1_sizeroot/.kit"
  _t5b1_sizeconf="$_t5b1_sizeroot/.kit/tracker.conf"
  cat > "$_t5b1_sizeconf" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
list_cap=200
state.ready=Selected
field.size=label:size
EOF
  cat > "$_t5b1_sizeroot/CLAUDE.md" <<'EOF'
- **Backlog backend**: Jira
EOF
  # fix1 V4: no ops file has a READY-state get-issue shape (get-issue-assigned/unassigned.out are
  # both fixed to "In Progress") — written into $tmpd (never an inline printf inside the fake
  # adapter body itself) and `cat`'d, a scratch shape per the brief's own carve-out.
  _t5b1_getissue_readyab1="$tmpd/get-issue-ready-ab1.out"
  cat > "$_t5b1_getissue_readyab1" <<'EOF'
key	AB-1
status-id	10001
status-name	Selected
EOF
  t5b1_lclog="$tmpd/label-counts-argv.log"
  cat > "$fakedir/tracker-jira.sh" <<EOF
#!/bin/sh
case "\$1" in
  get-issue) cat "$_t5b1_getissue_readyab1"; exit 0 ;;
  permissions) echo ok; exit 0 ;;
  status-ids) cat "$_t5a2l_statusids"; exit 0 ;;
  list-in-states)
    shift
    case "\$*" in
      *10001*) printf 'AB-1\nAB-2\nAB-3\nAB-4\n' ;;
      *) printf '' ;;
    esac
    exit 0 ;;
  label-counts)
    shift
    printf '%s\n' "\$*" >> "$t5b1_lclog"
    cat "$_t5a2l_ops/label-counts.out"
    exit 0 ;;
esac
EOF
  chmod +x "$fakedir/tracker-jira.sh"

  rc=0
  : > "$t5b1_lclog"
  t5b1_l2record="$tmpd/l2-record.txt"
  : > "$t5b1_l2record"
  tr_read "$_t5b1_sizeconf" "-" "$t5b1_l2record" AB-1 "$_h40" ready >/dev/null 2>&1 || rc=$?
  SEAM_ROOT="$_t5b1_sizeroot"; SEAM_RECORD="$t5b1_l2record"; SEAM_HEAD="$_h40"
  t5b1_l2_seamrc=0; _seam_record_load >/dev/null 2>&1 || t5b1_l2_seamrc=$?
  t5b1_l2_lccalls=$(wc -l < "$t5b1_lclog" | tr -d ' ')
  if [ "$rc" -eq 0 ] && [ "$t5b1_l2_seamrc" -eq 0 ] && [ "$t5b1_l2_lccalls" = "1" ] \
     && grep -q '^row AB-1 state=ready dor-size=yes$' "$t5b1_l2record" 2>/dev/null \
     && grep -q '^row AB-2 state=ready$' "$t5b1_l2record" 2>/dev/null \
     && ! grep -q '^row AB-2 .*dor-size' "$t5b1_l2record" 2>/dev/null \
     && grep -q '^row AB-3 state=ready dor-size=no$' "$t5b1_l2record" 2>/dev/null \
     && grep -q '^row AB-4 state=ready dor-size=no$' "$t5b1_l2record" 2>/dev/null; then
    echo "PASS: selftest — T5b1 leg 2: dor-size on ready rows and the ready subject from ONE label-counts call (0->no, 1->yes, >=2 omitted), round-trips"
  else
    echo "FAIL: selftest — T5b1 leg 2: dor-size was not applied correctly (rc=$rc, seam-rc=$t5b1_l2_seamrc, label-counts-calls=$t5b1_l2_lccalls, record: $(cat "$t5b1_l2record" 2>/dev/null))"; sfail=1
  fi

  # --- T5b1 leg 3 (F-7): field.size=none -> no dor-size= token anywhere, NEVER n/a, no label-counts
  # dispatch at all.
  _t5b1_noneconf="$_t5b1_sizeroot/.kit/tracker-none.conf"
  cat > "$_t5b1_noneconf" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
list_cap=200
state.ready=Selected
field.size=none
EOF
  rc=0
  : > "$t5b1_lclog"
  t5b1_l3record="$tmpd/l3-record.txt"
  : > "$t5b1_l3record"
  tr_read "$_t5b1_noneconf" "-" "$t5b1_l3record" AB-1 "$_h40" ready >/dev/null 2>&1 || rc=$?
  t5b1_l3_lccalls=$(wc -l < "$t5b1_lclog" | tr -d ' ')
  if [ "$rc" -eq 0 ] && [ "$t5b1_l3_lccalls" = "0" ] \
     && grep -q '^row AB-1 state=ready$' "$t5b1_l3record" 2>/dev/null \
     && ! grep -q 'dor-size' "$t5b1_l3record" 2>/dev/null \
     && ! grep -q 'n/a' "$t5b1_l3record" 2>/dev/null; then
    echo "PASS: selftest — T5b1 leg 3 (F-7): field.size=none omits dor-size everywhere, never n/a, no label-counts dispatch"
  else
    echo "FAIL: selftest — T5b1 leg 3 (F-7): field.size=none was not fully omitted (rc=$rc, lc-calls=$t5b1_l3_lccalls, record: $(cat "$t5b1_l3record" 2>/dev/null))"; sfail=1
  fi

  # --- T5b1 leg 4 (F-10): label-counts rc 2 -> dor-size absent on every row, verdict bound, a fixed
  # sentence naming dor-size; rc 1 -> the same.
  for t5b1_l4_rc in 1 2; do
    cat > "$fakedir/tracker-jira.sh" <<EOF
#!/bin/sh
case "\$1" in
  get-issue) cat "$_t5b1_getissue_readyab1"; exit 0 ;;
  permissions) echo ok; exit 0 ;;
  status-ids) cat "$_t5a2l_statusids"; exit 0 ;;
  list-in-states)
    shift
    case "\$*" in
      *10001*) printf 'AB-1\nAB-2\nAB-3\n' ;;
      *) printf '' ;;
    esac
    exit 0 ;;
  label-counts) exit $t5b1_l4_rc ;;
esac
EOF
    chmod +x "$fakedir/tracker-jira.sh"
    rc=0
    t5b1_l4record="$tmpd/l4-$t5b1_l4_rc-record.txt"
    : > "$t5b1_l4record"
    t5b1_l4err=$(tr_read "$_t5b1_sizeconf" "-" "$t5b1_l4record" AB-1 "$_h40" ready 2>&1 >/dev/null) || rc=$?
    t5b1_l4expected="omitted: dor-size (the tracker query failed, F-10)"
    if [ "$rc" -eq 0 ] && [ "$t5b1_l4err" = "$t5b1_l4expected" ] \
       && grep -q '^verdict bound$' "$t5b1_l4record" 2>/dev/null \
       && ! grep -q 'dor-size' "$t5b1_l4record" 2>/dev/null; then
      echo "PASS: selftest — T5b1 leg 4 (F-10): label-counts rc $t5b1_l4_rc omits dor-size on every row, verdict bound, one fixed sentence naming dor-size"
    else
      echo "FAIL: selftest — T5b1 leg 4 (F-10): label-counts rc $t5b1_l4_rc was not handled (rc=$rc, stderr='$t5b1_l4err', record: $(cat "$t5b1_l4record" 2>/dev/null))"; sfail=1
    fi
  done

  # === fix1 V1 (security Medium + quality 5): tr_answer_ok validates the label-counts answer — ANY
  # violation omits dor-size EVERYWHERE with the SAME F-10 sentence, never a partial/silent drop. A
  # dedicated 2-id ready set (AB-1 subject + AB-2) keeps each hostile shape small and self-contained.
  for _t5b1v1_case in dupkey missingid extrafield outsideset nonnumeric; do
    _t5b1v1_answer="$tmpd/v1-$_t5b1v1_case.out"
    case "$_t5b1v1_case" in
      dupkey)
        cat > "$_t5b1v1_answer" <<'EOF'
AB-1	0
AB-1	1
AB-2	0
EOF
        ;;
      missingid)
        cat > "$_t5b1v1_answer" <<'EOF'
AB-1	0
EOF
        ;;
      extrafield)
        cat > "$_t5b1v1_answer" <<'EOF'
AB-1	0	XX
AB-2	1	YY
EOF
        ;;
      outsideset)
        cat > "$_t5b1v1_answer" <<'EOF'
AB-1	0
AB-2	1
AB-9	0
EOF
        ;;
      nonnumeric)
        cat > "$_t5b1v1_answer" <<'EOF'
AB-1	yes
AB-2	1
EOF
        ;;
    esac
    cat > "$fakedir/tracker-jira.sh" <<EOF
#!/bin/sh
case "\$1" in
  get-issue) cat "$_t5b1_getissue_readyab1"; exit 0 ;;
  permissions) echo ok; exit 0 ;;
  status-ids) cat "$_t5a2l_statusids"; exit 0 ;;
  list-in-states)
    shift
    case "\$*" in
      *10001*) printf 'AB-1\nAB-2\n' ;;
      *) printf '' ;;
    esac
    exit 0 ;;
  label-counts) cat "$_t5b1v1_answer"; exit 0 ;;
esac
EOF
    chmod +x "$fakedir/tracker-jira.sh"
    rc=0
    _t5b1v1_record="$tmpd/v1-$_t5b1v1_case-record.txt"
    : > "$_t5b1v1_record"
    _t5b1v1_err=$(tr_read "$_t5b1_sizeconf" "-" "$_t5b1v1_record" AB-1 "$_h40" ready 2>&1 >/dev/null) || rc=$?
    _t5b1v1_expected="omitted: dor-size (the tracker query failed, F-10)"
    if [ "$rc" -eq 0 ] && [ "$_t5b1v1_err" = "$_t5b1v1_expected" ] \
       && grep -q '^verdict bound$' "$_t5b1v1_record" 2>/dev/null \
       && ! grep -q 'dor-size' "$_t5b1v1_record" 2>/dev/null; then
      echo "PASS: selftest — fix1 V1 ($_t5b1v1_case): a hostile label-counts answer omits dor-size EVERYWHERE with the F-10 sentence, never a partial/silent drop"
    else
      echo "FAIL: selftest — fix1 V1 ($_t5b1v1_case): the hostile label-counts answer was not rejected (rc=$rc, stderr='$_t5b1v1_err', record: $(cat "$_t5b1v1_record" 2>/dev/null))"; sfail=1
    fi
  done

  # fix1 V1 finding: the exact-set equality check alone cannot distinguish a grammatically invalid
  # key from a valid one that HAPPENS to string-match the asked set (any real content difference is
  # already caught by that check) — so tr_list_keys_ok's own grammar/project rule only has
  # independent teeth when a hostile/malformed id string appears on BOTH sides alike. Pinned
  # directly on tr_answer_ok: a leading-zero id (AB-07) fails the project rule even though it
  # matches "asked" verbatim.
  if tr_answer_ok AB "AB-07" "AB-07	1" exact; then
    echo "FAIL: selftest — fix1 V1 finding: tr_answer_ok accepted a leading-zero id (AB-07) even though it string-matched the asked set (tr_list_keys_ok's project rule not enforced)"; sfail=1
  else
    echo "PASS: selftest — fix1 V1 finding: tr_answer_ok refuses a leading-zero id via tr_list_keys_ok's project rule even when it string-matches the asked set exactly (direct call)"
  fi

  # === T5bc step 0: tr_answer_ok mode `subset` (field-empty's own answer shape — a bare id per
  # line, no TAB field) extends the SAME validator (never a second one): a proper subset and the
  # legal empty answer accept; a duplicate key, an extra TAB field, and an id outside the asked set
  # all refuse.
  _t5bc0_asked="AB-1
AB-2
AB-3"
  if tr_answer_ok AB "$_t5bc0_asked" "AB-2" subset \
     && tr_answer_ok AB "$_t5bc0_asked" "" subset \
     && ! tr_answer_ok AB "$_t5bc0_asked" "AB-2
AB-2" subset \
     && ! tr_answer_ok AB "$_t5bc0_asked" "AB-2	x" subset \
     && ! tr_answer_ok AB "$_t5bc0_asked" "AB-9" subset; then
    echo "PASS: selftest — T5bc step 0: tr_answer_ok mode subset accepts a proper subset and the legal empty answer, refuses a duplicate key, an extra TAB field, and an id outside the asked set (direct calls)"
  else
    echo "FAIL: selftest — T5bc step 0: tr_answer_ok mode subset did not validate correctly (direct calls)"; sfail=1
  fi

  # T5bc step 0d: the count grammar becomes canonical ^(0|[1-9][0-9]*)$ — a leading-zero count
  # ("01") must now be refused (today it passes and drops dor-size WITHOUT the F-10 sentence).
  if tr_answer_ok AB "AB-1
AB-2" "AB-1	01
AB-2	1" exact; then
    echo "FAIL: selftest — T5bc step 0d: tr_answer_ok exact accepted a leading-zero count ('01') (direct call)"; sfail=1
  else
    echo "PASS: selftest — T5bc step 0d: tr_answer_ok exact refuses a leading-zero count ('01') via the canonical grammar (direct call)"
  fi

  # === fix1 V2 (quality 3 + security Low 2): a failed credential probe (H-3 downgrades $_verdict)
  # must gate off the label-counts dispatch entirely — a Ready subject, zero calls, no flag sentence.
  cat > "$fakedir/tracker-jira.sh" <<EOF
#!/bin/sh
case "\$1" in
  get-issue) cat "$_t5b1_getissue_readyab1"; exit 0 ;;
  permissions) exit 5 ;;
  label-counts) echo x >> "$tmpd/v2-lc.log"; printf 'AB-1\t0\n'; exit 0 ;;
esac
EOF
  chmod +x "$fakedir/tracker-jira.sh"
  rc=0
  : > "$tmpd/v2-lc.log"
  _t5b1v2_record="$tmpd/v2-record.txt"
  : > "$_t5b1v2_record"
  _t5b1v2_err=$(tr_read "$_t5b1_sizeconf" "-" "$_t5b1v2_record" AB-1 "$_h40" 2>&1 >/dev/null) || rc=$?
  _t5b1v2_calls=$(wc -l < "$tmpd/v2-lc.log" | tr -d ' ')
  if [ "$_t5b1v2_calls" = "0" ] && ! printf '%s' "$_t5b1v2_err" | grep -q 'dor-size' \
     && grep -q '^verdict unverified$' "$_t5b1v2_record" 2>/dev/null; then
    echo "PASS: selftest — fix1 V2: a failed credential probe gates off label-counts entirely (zero calls, no flag sentence, Ready subject)"
  else
    echo "FAIL: selftest — fix1 V2: label-counts was dispatched after a failed credential probe (calls=$_t5b1v2_calls, stderr='$_t5b1v2_err', record: $(cat "$_t5b1v2_record" 2>/dev/null))"; sfail=1
  fi

  # === fix1 V3 (quality 1 — the subject's own count mapping unpinned). Leg 2 above already pins
  # count 1 -> dor-size=yes on the SUBJECT (AB-1); this pins count >= 2 -> the token OMITTED on the
  # subject too (quality mutants rB `*) _subjdorsize=yes` and rC `1) _subjdorsize=no` both go RED).
  _t5b1v3_getissue="$tmpd/get-issue-ready-ab2.out"
  cat > "$_t5b1v3_getissue" <<'EOF'
key	AB-2
status-id	10001
status-name	Selected
EOF
  cat > "$fakedir/tracker-jira.sh" <<EOF
#!/bin/sh
case "\$1" in
  get-issue) cat "$_t5b1v3_getissue"; exit 0 ;;
  permissions) echo ok; exit 0 ;;
  label-counts)
    shift
    awk -F'\t' -v ids="\$*" 'BEGIN{n=split(ids,a," "); for(i=1;i<=n;i++) want[a[i]]=1} (\$1 in want)' "$_t5a2l_ops/label-counts.out"
    exit 0 ;;
esac
EOF
  chmod +x "$fakedir/tracker-jira.sh"
  rc=0
  _t5b1v3_record="$tmpd/v3-record.txt"
  : > "$_t5b1v3_record"
  tr_read "$_t5b1_sizeconf" "-" "$_t5b1v3_record" AB-2 "$_h40" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 0 ] && grep -q '^row AB-2 state=ready$' "$_t5b1v3_record" 2>/dev/null \
     && ! grep -q '^row AB-2 .*dor-size' "$_t5b1v3_record" 2>/dev/null; then
    echo "PASS: selftest — fix1 V3: a ready SUBJECT with count >= 2 omits its own dor-size token"
  else
    echo "FAIL: selftest — fix1 V3: a ready subject with count >= 2 did not omit dor-size (rc=$rc, record: $(cat "$_t5b1v3_record" 2>/dev/null))"; sfail=1
  fi

  # --- T5b1 leg 5 (F-9): blocked-by-open / outcome-recorded are NEVER emitted in any record this
  # selftest wrote, across every leg run in this whole battery. Scoped to files whose FIRST LINE is
  # the §4.3 magic (an actual written record) — a raw tree-wide grep also hits this very leg's own
  # source text once a locale-check copy of tracker-read.sh's own source lands under $tmpd (0a).
  _t5b1_f9bad=""
  # shellcheck disable=SC2044 # $tmpd is our own mktemp tree; every filename here is self-chosen
  # (no spaces/globs/newlines) by this selftest, so the split-on-find is safe.
  for _t5b1_f9f in $(find "$tmpd" -type f 2>/dev/null); do
    [ "$(head -n 1 "$_t5b1_f9f" 2>/dev/null)" = "kit-tracker-read 1" ] || continue
    if grep -q -e 'blocked-by-open' -e 'outcome-recorded' "$_t5b1_f9f" 2>/dev/null; then
      _t5b1_f9bad="$_t5b1_f9bad $_t5b1_f9f"
    fi
  done
  if [ -z "$_t5b1_f9bad" ]; then
    echo "PASS: selftest — T5b1 leg 5 (F-9): blocked-by-open/outcome-recorded never appear in any record written this run"
  else
    echo "FAIL: selftest — T5b1 leg 5 (F-9): a forbidden F-9 token leaked into a written record:$_t5b1_f9bad"; sfail=1
  fi

  # --- T5b1 leg 6: non-ready rows carry no dor-* token; the subject carries claimed whatever its
  # own state. A DEDICATED root/conf (never the shared `lconf`, which carries no field.size and is
  # reused by many earlier legs) — AB-7 subject in-progress, AB-2/AB-3 ready.
  # fix1 V4 (drift lock): get-issue and label-counts now read the adapter-proven ops files instead
  # of an inline printf — AB-7/In Progress is get-issue-assigned.out's OWN id/state (reused
  # verbatim); label-counts is an awk-filtered READ of the real label-counts.out (never invented
  # values) — a bare cat would leak AB-1/AB-4's counts, which fix1 V1's exact-set check now refuses.
  _t5b1_l6root="$tmpd/l6root"; mkdir -p "$_t5b1_l6root/.kit"
  _t5b1_l6conf="$_t5b1_l6root/.kit/tracker.conf"
  cat > "$_t5b1_l6conf" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
list_cap=200
state.in-progress=In Progress
state.ready=Selected
field.size=label:size
EOF
  cat > "$_t5b1_l6root/CLAUDE.md" <<'EOF'
- **Backlog backend**: Jira
EOF
  cat > "$fakedir/tracker-jira.sh" <<EOF
#!/bin/sh
case "\$1" in
  get-issue) cat "$_t5a2l_ops/get-issue-assigned.out"; exit 0 ;;
  permissions) echo ok; exit 0 ;;
  status-ids) cat "$_t5a2l_statusids"; exit 0 ;;
  list-in-states)
    shift
    case "\$*" in
      *10001*) cat "$_t5a2l_ops/list-cloud-ready.out" ;;
      # the subject (AB-7) must appear in its OWN state's list — a real "in-progress" query would
      # return it too (backlog-lib.sh's bijection "iff" rule) — never the real ops file verbatim
      # here (it has no AB-7), so an inline printf naming the subject plus one decoy (AB-4).
      # T5bc step 0d: matches the trailing status-id argument EXACTLY (never a bare '*3*', which
      # would also match e.g. a future '10003' cap/id sharing that digit).
      *" 3") printf 'AB-7\nAB-4\n' ;;
      *) cat "$_t5a2l_ops/list-cloud-empty.out" ;;
    esac
    exit 0 ;;
  label-counts)
    shift
    awk -F'\t' -v ids="\$*" 'BEGIN{n=split(ids,a," "); for(i=1;i<=n;i++) want[a[i]]=1} (\$1 in want)' "$_t5a2l_ops/label-counts.out"
    exit 0 ;;
esac
EOF
  chmod +x "$fakedir/tracker-jira.sh"
  rc=0
  t5b1_l6record="$tmpd/l6-record.txt"
  : > "$t5b1_l6record"
  tr_read "$_t5b1_l6conf" "-" "$t5b1_l6record" AB-7 "$_h40" ready in-progress >/dev/null 2>&1 || rc=$?
  # shellcheck disable=SC2034 # all three read by backlog-lib.sh's sourced seam functions
  SEAM_ROOT="$_t5b1_l6root"
  # shellcheck disable=SC2034
  SEAM_RECORD="$t5b1_l6record"
  # shellcheck disable=SC2034
  SEAM_HEAD="$_h40"
  t5b1_l6_seamrc=0; _seam_record_load >/dev/null 2>&1 || t5b1_l6_seamrc=$?
  if [ "$rc" -eq 0 ] && [ "$t5b1_l6_seamrc" -eq 0 ] \
     && grep -q '^row AB-7 state=in-progress claimed=yes$' "$t5b1_l6record" 2>/dev/null \
     && ! grep -q '^row AB-7 .*dor-size' "$t5b1_l6record" 2>/dev/null \
     && grep -q '^row AB-4 state=in-progress$' "$t5b1_l6record" 2>/dev/null \
     && ! grep -q '^row AB-4 .*dor-size' "$t5b1_l6record" 2>/dev/null \
     && grep -q '^row AB-2 state=ready$' "$t5b1_l6record" 2>/dev/null \
     && ! grep -q '^row AB-2 .*dor-size' "$t5b1_l6record" 2>/dev/null \
     && grep -q '^row AB-3 state=ready dor-size=no$' "$t5b1_l6record" 2>/dev/null; then
    echo "PASS: selftest — T5b1 leg 6: non-ready rows carry no dor-* token; the subject carries claimed whatever its own state"
  else
    echo "FAIL: selftest — T5b1 leg 6: a non-ready row gained dor-size, or the subject's claimed was missing (rc=$rc, seam-rc=$t5b1_l6_seamrc, record: $(cat "$t5b1_l6record" 2>/dev/null))"; sfail=1
  fi

  # fix1 V4 finding: post-V1, tr_answer_ok's exact-set check means label-counts can never
  # legitimately answer with a non-ready id's count, so the isready gate inside
  # tr_apply_labelcount_tokens is now unreachable through the FULL pipeline (leg 6 above can no
  # longer exercise it — its own asked-id set never includes AB-1/AB-4). Pin it directly instead,
  # since it is still a real defence-in-depth control worth keeping.
  _t5b1v4_extra='row AB-1 state=in-progress
row AB-2 state=ready'
  _t5b1v4_counts="AB-1	1
AB-2	0"
  _t5b1v4_out=$(tr_apply_labelcount_tokens "$_t5b1v4_extra" "$_t5b1v4_counts" dor-size)
  if printf '%s\n' "$_t5b1v4_out" | grep -q '^row AB-2 state=ready dor-size=no$' \
     && ! printf '%s\n' "$_t5b1v4_out" | grep -q '^row AB-1 .*dor-size'; then
    echo "PASS: selftest — fix1 V4 finding: tr_apply_labelcount_tokens's isready gate pinned directly (unreachable through the full pipeline once V1 lands)"
  else
    echo "FAIL: selftest — fix1 V4 finding: tr_apply_labelcount_tokens applied dor-size to a non-ready row (direct call): $_t5b1v4_out"; sfail=1
  fi

  # === T5bc fix1 B2 (quality blocking 1 — the `bound` gate on field-empty unpinned): a failed
  # credential probe (H-3 downgrades $_verdict) must gate off the field-empty dispatch entirely,
  # exactly as it already does for label-counts (fix1 V2 above) — a Ready subject, zero field-empty
  # calls, verdict unverified (pins the quality seat's qNoBound mutant).
  _b2_root="$tmpd/b2root"; mkdir -p "$_b2_root/.kit"
  cat > "$_b2_root/CLAUDE.md" <<'EOF'
- **Backlog backend**: Jira
EOF
  _b2_conf="$_b2_root/.kit/tracker.conf"
  cat > "$_b2_conf" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
list_cap=200
state.ready=Selected
field.acceptance=description
EOF
  _b2_felog="$tmpd/b2-fe.log"
  : > "$_b2_felog"
  cat > "$fakedir/tracker-jira.sh" <<EOF
#!/bin/sh
case "\$1" in
  get-issue) cat "$_t5b1_getissue_readyab1"; exit 0 ;;
  permissions) exit 5 ;;
  field-empty) echo x >> "$_b2_felog"; printf ''; exit 0 ;;
esac
EOF
  chmod +x "$fakedir/tracker-jira.sh"
  rc=0
  _b2_record="$tmpd/b2-record.txt"
  : > "$_b2_record"
  _b2_err=$(tr_read "$_b2_conf" "-" "$_b2_record" AB-1 "$_h40" 2>&1 >/dev/null) || rc=$?
  _b2_calls=$(wc -l < "$_b2_felog" | tr -d ' ')
  if [ "$_b2_calls" = "0" ] && ! printf '%s' "$_b2_err" | grep -q 'dor-acceptance' \
     && grep -q '^verdict unverified$' "$_b2_record" 2>/dev/null; then
    echo "PASS: selftest — T5bc fix1 B2: a failed credential probe gates off field-empty entirely (zero calls, no flag sentence, Ready subject)"
  else
    echo "FAIL: selftest — T5bc fix1 B2: field-empty was dispatched after a failed credential probe (calls=$_b2_calls, err='$_b2_err', record: $(cat "$_b2_record" 2>/dev/null))"; sfail=1
  fi

  # === T5bc leg 1: dor-acceptance / dor-metric on ready rows (and the subject when ready) — conf
  # field.acceptance=description, field.metric=customfield_10077; ONE field-empty call per field
  # over the ready ids (drift lock: cats the real ops/field-empty.out, unfiltered — its own id set
  # AB-2/AB-3 is already a subset of the asked AB-1/AB-2/AB-3/AB-4) — an id IN the empty set ->
  # dor-<x>=no, otherwise yes.
  _t5bc_l1root="$tmpd/l1root"; mkdir -p "$_t5bc_l1root/.kit"
  _t5bc_l1conf="$_t5bc_l1root/.kit/tracker.conf"
  cat > "$_t5bc_l1root/CLAUDE.md" <<'EOF'
- **Backlog backend**: Jira
EOF
  cat > "$_t5bc_l1conf" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
list_cap=200
state.ready=Selected
field.acceptance=description
field.metric=customfield_10077
field.size=label:size
EOF
  t5bc_l1felog="$tmpd/l1-field-empty-argv.log"
  cat > "$fakedir/tracker-jira.sh" <<EOF
#!/bin/sh
case "\$1" in
  get-issue) cat "$_t5b1_getissue_readyab1"; exit 0 ;;
  permissions) echo ok; exit 0 ;;
  status-ids) cat "$_t5a2l_statusids"; exit 0 ;;
  list-in-states)
    shift
    case "\$*" in
      *10001*) printf 'AB-1\nAB-2\nAB-3\nAB-4\n' ;;
      *) printf '' ;;
    esac
    exit 0 ;;
  label-counts)
    shift
    awk -F'\t' -v ids="\$*" 'BEGIN{n=split(ids,a," "); for(i=1;i<=n;i++) want[a[i]]=1} (\$1 in want)' "$_t5a2l_ops/label-counts.out"
    exit 0 ;;
  field-empty)
    shift
    printf '%s\n' "\$*" >> "$t5bc_l1felog"
    cat "$_t5a2l_ops/field-empty.out"
    exit 0 ;;
esac
EOF
  chmod +x "$fakedir/tracker-jira.sh"
  rc=0
  : > "$t5bc_l1felog"
  t5bc_l1record="$tmpd/l1-record.txt"
  : > "$t5bc_l1record"
  tr_read "$_t5bc_l1conf" "-" "$t5bc_l1record" AB-1 "$_h40" ready >/dev/null 2>&1 || rc=$?
  SEAM_ROOT="$_t5bc_l1root"; SEAM_RECORD="$t5bc_l1record"; SEAM_HEAD="$_h40"
  t5bc_l1_seamrc=0; _seam_record_load >/dev/null 2>&1 || t5bc_l1_seamrc=$?
  t5bc_l1_fecalls=$(wc -l < "$t5bc_l1felog" | tr -d ' ')
  if [ "$rc" -eq 0 ] && [ "$t5bc_l1_seamrc" -eq 0 ] && [ "$t5bc_l1_fecalls" = "2" ] \
     && grep -q 'description' "$t5bc_l1felog" && grep -q 'customfield_10077' "$t5bc_l1felog" \
     && grep -q '^row AB-1 state=ready dor-acceptance=yes dor-metric=yes dor-size=yes$' "$t5bc_l1record" 2>/dev/null \
     && grep -q '^row AB-2 state=ready dor-acceptance=no dor-metric=no$' "$t5bc_l1record" 2>/dev/null \
     && grep -q '^row AB-3 state=ready dor-acceptance=no dor-metric=no dor-size=no$' "$t5bc_l1record" 2>/dev/null \
     && grep -q '^row AB-4 state=ready dor-acceptance=yes dor-metric=yes dor-size=no$' "$t5bc_l1record" 2>/dev/null; then
    echo "PASS: selftest — T5bc leg 1: dor-acceptance/dor-metric on ready rows and the ready subject from ONE field-empty call per field, membership derives no/yes, round-trips"
  else
    echo "FAIL: selftest — T5bc leg 1: dor-acceptance/dor-metric not applied correctly (rc=$rc, seam-rc=$t5bc_l1_seamrc, fe-calls=$t5bc_l1_fecalls, log: $(cat "$t5bc_l1felog" 2>/dev/null), record: $(cat "$t5bc_l1record" 2>/dev/null))"; sfail=1
  fi

  # === T5bc leg 2 (F-7): field.metric=none -> no dor-metric= token anywhere, NEVER n/a, no
  # field-empty dispatch for metric at all — dor-acceptance and dor-size (still mapped) keep
  # working, proving the omission is PER FIELD, never global.
  _t5bc_l2conf="$_t5bc_l1root/.kit/tracker.conf"
  cat > "$_t5bc_l2conf" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
list_cap=200
state.ready=Selected
field.acceptance=description
field.metric=none
field.size=label:size
EOF
  rc=0
  : > "$t5bc_l1felog"
  t5bc_l2record="$tmpd/l2-record.txt"
  : > "$t5bc_l2record"
  tr_read "$_t5bc_l2conf" "-" "$t5bc_l2record" AB-1 "$_h40" ready >/dev/null 2>&1 || rc=$?
  t5bc_l2_fecalls=$(wc -l < "$t5bc_l1felog" | tr -d ' ')
  if [ "$rc" -eq 0 ] && [ "$t5bc_l2_fecalls" = "1" ] && grep -q description "$t5bc_l1felog" \
     && ! grep -q customfield_10077 "$t5bc_l1felog" \
     && ! grep -q 'dor-metric' "$t5bc_l2record" 2>/dev/null \
     && ! grep -q 'n/a' "$t5bc_l2record" 2>/dev/null \
     && grep -q '^row AB-1 state=ready dor-acceptance=yes dor-size=yes$' "$t5bc_l2record" 2>/dev/null \
     && grep -q '^row AB-2 state=ready dor-acceptance=no$' "$t5bc_l2record" 2>/dev/null; then
    echo "PASS: selftest — T5bc leg 2 (F-7): field.metric=none omits dor-metric everywhere, never n/a, no field-empty dispatch for metric, dor-acceptance/dor-size unaffected"
  else
    echo "FAIL: selftest — T5bc leg 2 (F-7): field.metric=none was not fully omitted (rc=$rc, fe-calls=$t5bc_l2_fecalls, log: $(cat "$t5bc_l1felog" 2>/dev/null), record: $(cat "$t5bc_l2record" 2>/dev/null))"; sfail=1
  fi

  # === T5bc fix1 B5 (security Low 3 — the legal empty answer as a record-level positive): a
  # field-empty answer of rc 0 with ZERO ids means nothing is empty — every ready row (and the
  # subject) gets dor-acceptance=yes / dor-metric=yes, round-trips.
  _b5conf="$_t5bc_l1root/.kit/tracker.conf"
  cat > "$_b5conf" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
list_cap=200
state.ready=Selected
field.acceptance=description
field.metric=customfield_10077
EOF
  cat > "$fakedir/tracker-jira.sh" <<EOF
#!/bin/sh
case "\$1" in
  get-issue) cat "$_t5b1_getissue_readyab1"; exit 0 ;;
  permissions) echo ok; exit 0 ;;
  status-ids) cat "$_t5a2l_statusids"; exit 0 ;;
  list-in-states)
    shift
    case "\$*" in
      *10001*) printf 'AB-1\nAB-2\n' ;;
      *) printf '' ;;
    esac
    exit 0 ;;
  field-empty) printf ''; exit 0 ;;
esac
EOF
  chmod +x "$fakedir/tracker-jira.sh"
  rc=0
  _b5record="$tmpd/b5-record.txt"
  : > "$_b5record"
  tr_read "$_b5conf" "-" "$_b5record" AB-1 "$_h40" ready >/dev/null 2>&1 || rc=$?
  SEAM_ROOT="$_t5bc_l1root"; SEAM_RECORD="$_b5record"; SEAM_HEAD="$_h40"
  _b5_seamrc=0; _seam_record_load >/dev/null 2>&1 || _b5_seamrc=$?
  if [ "$rc" -eq 0 ] && [ "$_b5_seamrc" -eq 0 ] \
     && grep -q '^row AB-1 state=ready dor-acceptance=yes dor-metric=yes$' "$_b5record" 2>/dev/null \
     && grep -q '^row AB-2 state=ready dor-acceptance=yes dor-metric=yes$' "$_b5record" 2>/dev/null; then
    echo "PASS: selftest — T5bc fix1 B5: a legal empty field-empty answer (rc 0, zero ids) means every ready row is dor-acceptance=yes/dor-metric=yes, round-trips"
  else
    echo "FAIL: selftest — T5bc fix1 B5: the legal empty field-empty answer was not treated as all-yes (rc=$rc seamrc=$_b5_seamrc record: $(cat "$_b5record" 2>/dev/null))"; sfail=1
  fi

  # === T5bc leg 3 (F-10): field-empty rc 2 (and rc 1) -> dor-acceptance absent on EVERY row,
  # verdict bound, ONE fixed sentence naming the flag (whole-stderr assert). field.metric/size=none
  # keeps this leg's ONLY dispatch isolated to acceptance, so the sentence is unambiguous.
  _t5bc_l3root="$tmpd/l3root"; mkdir -p "$_t5bc_l3root/.kit"
  _t5bc_l3conf="$_t5bc_l3root/.kit/tracker.conf"
  cat > "$_t5bc_l3root/CLAUDE.md" <<'EOF'
- **Backlog backend**: Jira
EOF
  cat > "$_t5bc_l3conf" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
list_cap=200
state.ready=Selected
field.acceptance=description
field.metric=none
field.size=none
EOF
  for t5bc_l3_rc in 1 2; do
    cat > "$fakedir/tracker-jira.sh" <<EOF
#!/bin/sh
case "\$1" in
  get-issue) cat "$_t5b1_getissue_readyab1"; exit 0 ;;
  permissions) echo ok; exit 0 ;;
  status-ids) cat "$_t5a2l_statusids"; exit 0 ;;
  list-in-states)
    shift
    case "\$*" in
      *10001*) printf 'AB-1\nAB-2\n' ;;
      *) printf '' ;;
    esac
    exit 0 ;;
  field-empty) exit $t5bc_l3_rc ;;
esac
EOF
    chmod +x "$fakedir/tracker-jira.sh"
    rc=0
    t5bc_l3record="$tmpd/l3-$t5bc_l3_rc-record.txt"
    : > "$t5bc_l3record"
    t5bc_l3err=$(tr_read "$_t5bc_l3conf" "-" "$t5bc_l3record" AB-1 "$_h40" ready 2>&1 >/dev/null) || rc=$?
    t5bc_l3expected="omitted: dor-acceptance (the tracker query failed, F-10)"
    if [ "$rc" -eq 0 ] && [ "$t5bc_l3err" = "$t5bc_l3expected" ] \
       && grep -q '^verdict bound$' "$t5bc_l3record" 2>/dev/null \
       && ! grep -q 'dor-acceptance' "$t5bc_l3record" 2>/dev/null; then
      echo "PASS: selftest — T5bc leg 3 (F-10): field-empty rc $t5bc_l3_rc omits dor-acceptance on every row, verdict bound, one fixed sentence naming the flag"
    else
      echo "FAIL: selftest — T5bc leg 3 (F-10): field-empty rc $t5bc_l3_rc was not handled (rc=$rc, stderr='$t5bc_l3err', record: $(cat "$t5bc_l3record" 2>/dev/null))"; sfail=1
    fi
  done

  # === T5bc step 0 (class rule extension): tr_answer_ok validates the field-empty answer too — ANY
  # violation (dup key, an extra TAB field, an id outside the asked set) omits the flag EVERYWHERE
  # with the SAME F-10 sentence (mirrors fix1 V1's label-counts battery). A dedicated 2-id ready set
  # (AB-1 subject + AB-2) keeps each hostile shape small and self-contained.
  for _t5bc3_case in dupkey extrafield outsideset; do
    _t5bc3_answer="$tmpd/l3-hostile-$_t5bc3_case.out"
    case "$_t5bc3_case" in
      dupkey) printf 'AB-2\nAB-2\n' > "$_t5bc3_answer" ;;
      extrafield) printf 'AB-2\tx\n' > "$_t5bc3_answer" ;;
      outsideset) printf 'AB-2\nAB-9\n' > "$_t5bc3_answer" ;;
    esac
    cat > "$fakedir/tracker-jira.sh" <<EOF
#!/bin/sh
case "\$1" in
  get-issue) cat "$_t5b1_getissue_readyab1"; exit 0 ;;
  permissions) echo ok; exit 0 ;;
  status-ids) cat "$_t5a2l_statusids"; exit 0 ;;
  list-in-states)
    shift
    case "\$*" in
      *10001*) printf 'AB-1\nAB-2\n' ;;
      *) printf '' ;;
    esac
    exit 0 ;;
  field-empty) cat "$_t5bc3_answer"; exit 0 ;;
esac
EOF
    chmod +x "$fakedir/tracker-jira.sh"
    rc=0
    _t5bc3_record="$tmpd/l3-hostile-$_t5bc3_case-record.txt"
    : > "$_t5bc3_record"
    _t5bc3_err=$(tr_read "$_t5bc_l3conf" "-" "$_t5bc3_record" AB-1 "$_h40" ready 2>&1 >/dev/null) || rc=$?
    _t5bc3_expected="omitted: dor-acceptance (the tracker query failed, F-10)"
    if [ "$rc" -eq 0 ] && [ "$_t5bc3_err" = "$_t5bc3_expected" ] \
       && grep -q '^verdict bound$' "$_t5bc3_record" 2>/dev/null \
       && ! grep -q 'dor-acceptance' "$_t5bc3_record" 2>/dev/null; then
      echo "PASS: selftest — T5bc step 0 ($_t5bc3_case): a hostile field-empty answer omits dor-acceptance EVERYWHERE with the F-10 sentence"
    else
      echo "FAIL: selftest — T5bc step 0 ($_t5bc3_case): the hostile field-empty answer was not rejected (rc=$rc, stderr='$_t5bc3_err', record: $(cat "$_t5bc3_record" 2>/dev/null))"; sfail=1
    fi
  done

  # === T5bc leg 4 (P-1): a `ready` list of 481 ids -> NO list line for any state, the subject row
  # kept, one sentence naming list_cap, the record <= 512 lines. Built from a file generated INTO
  # $tmpd (never a real ops file — 481 unique ids stress the budget, the shape itself is already
  # pinned by ops/list-cloud.out).
  _t5bc_l4root="$tmpd/l4root"; mkdir -p "$_t5bc_l4root/.kit"
  _t5bc_l4conf="$_t5bc_l4root/.kit/tracker.conf"
  cat > "$_t5bc_l4root/CLAUDE.md" <<'EOF'
- **Backlog backend**: Jira
EOF
  cat > "$_t5bc_l4conf" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
list_cap=200
state.in-progress=In Progress
state.ready=Selected
EOF
  _t5bc_l4ready="$tmpd/ready-481.out"
  _t5bc4_i=2
  : > "$_t5bc_l4ready"
  while [ "$_t5bc4_i" -le 482 ]; do
    echo "AB-$_t5bc4_i" >> "$_t5bc_l4ready"
    _t5bc4_i=$((_t5bc4_i + 1))
  done
  cat > "$fakedir/tracker-jira.sh" <<EOF
#!/bin/sh
case "\$1" in
  get-issue) printf 'key\tAB-1\n'; printf 'status-id\t3\n'; printf 'status-name\tIn Progress\n'; exit 0 ;;
  permissions) echo ok; exit 0 ;;
  status-ids) cat "$_t5a2l_statusids"; exit 0 ;;
  list-in-states)
    shift
    case "\$*" in
      *10001*) cat "$_t5bc_l4ready" ;;
      *) printf '' ;;
    esac
    exit 0 ;;
esac
EOF
  chmod +x "$fakedir/tracker-jira.sh"
  rc=0
  t5bc_l4record="$tmpd/l4-record.txt"
  : > "$t5bc_l4record"
  t5bc_l4err=$(tr_read "$_t5bc_l4conf" "-" "$t5bc_l4record" AB-1 "$_h40" ready 2>&1 >/dev/null) || rc=$?
  SEAM_ROOT="$_t5bc_l4root"; SEAM_RECORD="$t5bc_l4record"; SEAM_HEAD="$_h40"
  t5bc_l4_seamrc=0; _seam_record_load >/dev/null 2>&1 || t5bc_l4_seamrc=$?
  t5bc_l4_lines=$(wc -l < "$t5bc_l4record" | tr -d ' ')
  t5bc_l4expected="omitted: every list (over the row budget, list_cap)"
  if [ "$rc" -eq 0 ] && [ "$t5bc_l4_seamrc" -eq 0 ] && [ "$t5bc_l4err" = "$t5bc_l4expected" ] \
     && [ "$t5bc_l4_lines" -le 512 ] \
     && ! grep -q '^list ' "$t5bc_l4record" 2>/dev/null \
     && grep -q '^row AB-1 state=in-progress$' "$t5bc_l4record" 2>/dev/null \
     && [ "$(grep -c '^row ' "$t5bc_l4record")" = "1" ]; then
    echo "PASS: selftest — T5bc leg 4 (P-1): a 481-id ready list omits every list line, keeps only the subject row, one sentence naming list_cap, record <= 512 lines"
  else
    echo "FAIL: selftest — T5bc leg 4 (P-1): the row budget was not enforced (rc=$rc, seam-rc=$t5bc_l4_seamrc, lines=$t5bc_l4_lines, stderr='$t5bc_l4err', rows=$(grep -c '^row ' "$t5bc_l4record" 2>/dev/null))"; sfail=1
  fi

  # === T5bc fix1 B1(b) (security Medium continued): tr_enforce_row_budget ALSO measures the
  # would-be record's bytes against TR_ROW_BYTE_BUDGET (~35 KiB / 36,000 B, WB-FIX-A A2: NOT ~48
  # KiB — see tracker-read.sh:38-56's own arithmetic) — a list UNDER the 480-row line cap but OVER
  # the byte cap is dropped with the SAME sentence. Long (unrealistic-length) keys are used deliberately here: this
  # pins the byte gate as an INDEPENDENT layer, defense in depth for the id-length gate above (which
  # already keeps a real 480-row list well under this ceiling) and for future per-row content.
  _b1b_root="$tmpd/b1broot"; mkdir -p "$_b1b_root/.kit"
  cat > "$_b1b_root/CLAUDE.md" <<'EOF'
- **Backlog backend**: Jira
EOF
  _b1b_conf="$_b1b_root/.kit/tracker.conf"
  cat > "$_b1b_conf" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
list_cap=200
EOF
  _b1b_longid="AB-9999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999"
  _b1b_n=0; _b1b_rows=""; _b1b_ids=""
  while [ "$_b1b_n" -lt 400 ]; do
    _b1b_rows="${_b1b_rows}row $_b1b_longid state=ready
"
    _b1b_ids="${_b1b_ids:+$_b1b_ids }$_b1b_longid"
    _b1b_n=$((_b1b_n + 1))
  done
  _b1b_raw="${_b1b_rows}list ready $_b1b_ids"
  _b1b_rowcount=$(printf '%s\n' "$_b1b_raw" | grep -c '^row ' || true)
  _b1b_bytes=$(printf '%s' "$_b1b_raw" | wc -c | tr -d ' ')
  : > "$tmpd/b1b.err"
  _b1b_out=$(tr_enforce_row_budget "$_b1b_raw" 2>"$tmpd/b1b.err")
  _b1b_err=$(cat "$tmpd/b1b.err" 2>/dev/null)
  _b1b_expected="omitted: every list (over the row budget, list_cap)"
  _b1b_pindigest=$(tr_pin_digest "$_b1b_conf")
  _b1b_record="$tmpd/b1b-record.txt"
  : > "$_b1b_record"
  _b1b_wrc=0
  tr_write_record "$_b1b_record" jira "$_b1b_pindigest" "$_h40" AB-1 "$_t5a2l_day" ok bound AB-1 ready "$_b1b_out" "" >/dev/null 2>&1 || _b1b_wrc=$?
  SEAM_ROOT="$_b1b_root"; SEAM_RECORD="$_b1b_record"; SEAM_HEAD="$_h40"
  _b1b_seamrc=0; _seam_record_load >/dev/null 2>&1 || _b1b_seamrc=$?
  if [ "$_b1b_rowcount" -le 480 ] && [ "$_b1b_bytes" -gt 49152 ] && [ -z "$_b1b_out" ] \
     && [ "$_b1b_err" = "$_b1b_expected" ] && [ "$_b1b_wrc" -eq 0 ] && [ "$_b1b_seamrc" -eq 0 ]; then
    echo "PASS: selftest — T5bc fix1 B1(b): a $_b1b_rowcount-row/$_b1b_bytes-byte long-key list under the 480-row line cap but over the ~35 KiB (36,000 B) byte cap is omitted with the SAME sentence, round-trips"
  else
    echo "FAIL: selftest — T5bc fix1 B1(b): the byte budget was not enforced (rows=$_b1b_rowcount bytes=$_b1b_bytes out='$_b1b_out' err='$_b1b_err' wrc=$_b1b_wrc seamrc=$_b1b_seamrc)"; sfail=1
  fi

  # === T5bc fix1 B3 (quality blocking 2 — the "kept" side of the budget unpinned): EXACTLY
  # TR_ROW_BUDGET (480) ready rows -> the list is KEPT (not omitted, `480` is not `-gt 480`),
  # round-trips (pins the quality seat's qBudget10 mutant, which today reds nothing).
  _b3root="$tmpd/b3root"; mkdir -p "$_b3root/.kit"
  cat > "$_b3root/CLAUDE.md" <<'EOF'
- **Backlog backend**: Jira
EOF
  _b3conf="$_b3root/.kit/tracker.conf"
  cat > "$_b3conf" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
list_cap=200
state.in-progress=In Progress
state.ready=Selected
EOF
  _b3ready="$tmpd/ready-480.out"
  _b3i=2; : > "$_b3ready"
  while [ "$_b3i" -le 481 ]; do
    echo "AB-$_b3i" >> "$_b3ready"
    _b3i=$((_b3i + 1))
  done
  cat > "$fakedir/tracker-jira.sh" <<EOF
#!/bin/sh
case "\$1" in
  get-issue) printf 'key\tAB-1\n'; printf 'status-id\t3\n'; printf 'status-name\tIn Progress\n'; exit 0 ;;
  permissions) echo ok; exit 0 ;;
  status-ids) cat "$_t5a2l_statusids"; exit 0 ;;
  list-in-states)
    shift
    case "\$*" in
      *10001*) cat "$_b3ready" ;;
      *) printf '' ;;
    esac
    exit 0 ;;
esac
EOF
  chmod +x "$fakedir/tracker-jira.sh"
  rc=0
  _b3record="$tmpd/b3-record.txt"
  : > "$_b3record"
  _b3err=$(tr_read "$_b3conf" "-" "$_b3record" AB-1 "$_h40" ready 2>&1 >/dev/null) || rc=$?
  SEAM_ROOT="$_b3root"; SEAM_RECORD="$_b3record"; SEAM_HEAD="$_h40"
  _b3_seamrc=0; _seam_record_load >/dev/null 2>&1 || _b3_seamrc=$?
  _b3_lines=$(wc -l < "$_b3record" | tr -d ' ')
  _b3_bytes=$(wc -c < "$_b3record" | tr -d ' ')
  _b3_rows=$(grep -c '^row ' "$_b3record" 2>/dev/null || true)
  if [ "$rc" -eq 0 ] && [ "$_b3_seamrc" -eq 0 ] && [ -z "$_b3err" ] \
     && grep -q '^list ready ' "$_b3record" 2>/dev/null \
     && [ "$_b3_rows" = "481" ]; then
    echo "PASS: selftest — T5bc fix1 B3: EXACTLY 480 ready rows stays in budget, the list is KEPT (lines=$_b3_lines bytes=$_b3_bytes), round-trips"
  else
    echo "FAIL: selftest — T5bc fix1 B3: an in-budget 480-row list was not kept (rc=$rc seamrc=$_b3_seamrc err='$_b3err' rows=$_b3_rows lines=$_b3_lines)"; sfail=1
  fi

  # === T5bc leg 5: the FULL GOLDEN — states in-progress/in-review/ready, both state.in-progress
  # names, all four field.* set (field.risk=none, F-7) — the record equals ops/record-full.expected
  # byte for byte except read-day (normalised). Drift-locked to the real ops files it draws on:
  # get-issue-assigned.out (subject AB-7), status-ids-cloud.out, list-cloud-ready/inprogress/empty.out,
  # label-counts.out (awk-filtered to the ready ids, as leg 6/leg 1 do), field-empty.out (a valid
  # subset of the ready ids for BOTH specs, as the real adapter's own T3b-core legs 1/2 pin).
  # T5bc fix1 B6: considered widening the ready set to add a `yes` here (e.g. list-cloud.out's
  # AB-5) — declined: AB-5's only real source, list-cloud.out, also repeats AB-1/AB-4 (already
  # in-progress), which would R6-poison the ready list instead of adding a row, and label-counts.out
  # carries no AB-5 entry, which would fail tr_answer_ok's exact-set check and drop dor-size from
  # EVERY ready row — not a one-line change without breaking drift-lock provenance. Leg 1/B5 above
  # already pin the `yes` case at the record level.
  _t5bc_l5root="$tmpd/l5root"; mkdir -p "$_t5bc_l5root/.kit"
  _t5bc_l5conf="$_t5bc_l5root/.kit/tracker.conf"
  cat > "$_t5bc_l5root/CLAUDE.md" <<'EOF'
- **Backlog backend**: Jira
EOF
  cat > "$_t5bc_l5conf" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
list_cap=200
state.in-progress=In Progress
state.in-progress=In Dev
state.in-review=In Review
state.ready=Selected
field.acceptance=description
field.metric=customfield_10077
field.size=label:size
field.risk=none
EOF
  cat > "$fakedir/tracker-jira.sh" <<EOF
#!/bin/sh
case "\$1" in
  get-issue) cat "$_t5a2l_ops/get-issue-assigned.out"; exit 0 ;;
  permissions) echo ok; exit 0 ;;
  status-ids) cat "$_t5a2l_statusids"; exit 0 ;;
  list-in-states)
    shift
    case "\$*" in
      *" 3 10002") cat "$_t5a2l_ops/list-cloud-inprogress.out"; printf 'AB-7\n' ;;
      *" 10003") cat "$_t5a2l_ops/list-cloud-empty.out" ;;
      *" 10001") cat "$_t5a2l_ops/list-cloud-ready.out" ;;
      *) printf '' ;;
    esac
    exit 0 ;;
  label-counts)
    shift
    awk -F'\t' -v ids="\$*" 'BEGIN{n=split(ids,a," "); for(i=1;i<=n;i++) want[a[i]]=1} (\$1 in want)' "$_t5a2l_ops/label-counts.out"
    exit 0 ;;
  field-empty)
    shift
    cat "$_t5a2l_ops/field-empty.out"
    exit 0 ;;
esac
EOF
  chmod +x "$fakedir/tracker-jira.sh"
  rc=0
  t5bc_l5record="$tmpd/l5-record.txt"
  : > "$t5bc_l5record"
  tr_read "$_t5bc_l5conf" "-" "$t5bc_l5record" AB-7 "$_h40" in-progress in-review ready >/dev/null 2>&1 || rc=$?
  # shellcheck disable=SC2034 # all three read by backlog-lib.sh's sourced seam functions
  SEAM_ROOT="$_t5bc_l5root"
  # shellcheck disable=SC2034
  SEAM_RECORD="$t5bc_l5record"
  # shellcheck disable=SC2034
  SEAM_HEAD="$_h40"
  t5bc_l5_seamrc=0; _seam_record_load >/dev/null 2>&1 || t5bc_l5_seamrc=$?
  t5bc_l5norm="$tmpd/l5-record-normalised.txt"
  sed 's/^read-day .*/read-day NORMALIZED/' "$t5bc_l5record" > "$t5bc_l5norm"
  if [ "$rc" -eq 0 ] && [ "$t5bc_l5_seamrc" -eq 0 ] \
     && cmp -s "$t5bc_l5norm" "$_t5a2l_ops/record-full.expected"; then
    echo "PASS: selftest — T5bc leg 5: the full golden record matches ops/record-full.expected byte-for-byte (read-day normalised), round-trips"
  else
    echo "FAIL: selftest — T5bc leg 5: the full golden record mismatched (rc=$rc, seam-rc=$t5bc_l5_seamrc): $(diff "$_t5a2l_ops/record-full.expected" "$t5bc_l5norm" 2>&1)"; sfail=1
  fi

  # --- T5bc leg 6 (F-9): blocked-by-open / outcome-recorded are NEVER emitted in any record this
  # selftest wrote, across every leg run so far INCLUDING T5bc's own new field-empty/row-budget/
  # golden legs (mirrors T5b1 leg 5's own scan, re-run here so the new dispatch is covered too).
  _t5bc_f9bad=""
  # shellcheck disable=SC2044 # $tmpd is our own mktemp tree; every filename here is self-chosen
  for _t5bc_f9f in $(find "$tmpd" -type f 2>/dev/null); do
    [ "$(head -n 1 "$_t5bc_f9f" 2>/dev/null)" = "kit-tracker-read 1" ] || continue
    if grep -q -e 'blocked-by-open' -e 'outcome-recorded' "$_t5bc_f9f" 2>/dev/null; then
      _t5bc_f9bad="$_t5bc_f9bad $_t5bc_f9f"
    fi
  done
  if [ -z "$_t5bc_f9bad" ]; then
    echo "PASS: selftest — T5bc leg 6 (F-9): blocked-by-open/outcome-recorded never appear in any record written this run, including the new field-empty/row-budget/golden legs"
  else
    echo "FAIL: selftest — T5bc leg 6 (F-9): a forbidden F-9 token leaked into a written record:$_t5bc_f9bad"; sfail=1
  fi

  # === T5d step 0 (security Low, carried from T5bc fix1 B1(b)): the row-byte budget must be
  # DECORATION-AWARE. Arithmetic (every figure the max the grammar allows):
  #   header (8 lines, 64-hex pin+head, a 32-char id, "credential over-privileged") = 282 B
  #   the subject's own row (32-char id, "in-progress", claimed+4 dor-*=yes)   = 127 B
  #   fixed total                                                             = 409 B
  #   decoration on up to 480 non-subject ready rows, 4 dor-*=yes (60 B/row)  = 28,800 B
  #   64 KiB (65,536 B) - 409 B - 28,800 B = 36,327 B is the MOST the pre-decoration
  #   rows+lists blob can be. TR_ROW_BYTE_BUDGET must be <= that (set to 36000, a 327 B margin).
  _t5d_b0root="$tmpd/t5d-b0root"; mkdir -p "$_t5d_b0root/.kit"
  cat > "$_t5d_b0root/CLAUDE.md" <<'EOF'
- **Backlog backend**: Jira
EOF
  _t5d_b0conf="$_t5d_b0root/.kit/tracker.conf"
  cat > "$_t5d_b0conf" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
list_cap=1000
state.ready=Selected
field.acceptance=description
field.metric=customfield_10099
field.size=label:size
field.risk=label:risk
EOF
  # ids must satisfy the REAL project grammar (tr_list_keys_ok, R4: "AB-" + digits only, no
  # leading zero) as well as the 32-char cap, so a full tr_read round-trip reaches the row budget
  # rather than being rejected earlier by the listed-key re-check.
  _t5d_b0subject="AB-99999999999999999999999999999"
  _t5d_b0ready="$tmpd/t5d-b0-ready.out"
  : > "$_t5d_b0ready"
  _t5d_b0i=2
  while [ "$_t5d_b0i" -le 480 ]; do
    printf 'AB-1000000000000000000000000%04d\n' "$_t5d_b0i" >> "$_t5d_b0ready"
    _t5d_b0i=$((_t5d_b0i + 1))
  done
  _t5d_b0rows=$(wc -l < "$_t5d_b0ready" | tr -d ' ')
  cat > "$fakedir/tracker-jira.sh" <<EOF
#!/bin/sh
case "\$1" in
  get-issue) printf 'key\t$_t5d_b0subject\n'; printf 'status-id\t10001\n'; printf 'status-name\tSelected\n'; printf 'assignee-present\ttrue\n'; exit 0 ;;
  permissions) echo ok; exit 0 ;;
  status-ids) cat "$_t5a2l_statusids"; exit 0 ;;
  list-in-states)
    shift
    case "\$*" in
      *10001*) cat "$_t5d_b0ready"; printf '%s\n' "$_t5d_b0subject" ;;
      *) printf '' ;;
    esac
    exit 0 ;;
  field-empty) printf ''; exit 0 ;;
  label-counts)
    shift 5
    for _t5d_b0lcid in \$*; do printf '%s\t1\n' "\$_t5d_b0lcid"; done
    exit 0 ;;
esac
EOF
  chmod +x "$fakedir/tracker-jira.sh"
  rc=0
  _t5d_b0record="$tmpd/t5d-b0-record.txt"
  : > "$_t5d_b0record"
  _t5d_b0err=$(tr_read "$_t5d_b0conf" "-" "$_t5d_b0record" "$_t5d_b0subject" "$_h40" ready 2>&1 >/dev/null) || rc=$?
  SEAM_ROOT="$_t5d_b0root"; SEAM_RECORD="$_t5d_b0record"; SEAM_HEAD="$_h40"
  _t5d_b0_seamrc=0; _seam_record_load >/dev/null 2>&1 || _t5d_b0_seamrc=$?
  _t5d_b0_bytes=$(wc -c < "$_t5d_b0record" | tr -d ' ')
  _t5d_b0_haslist=0
  grep -q '^list ready ' "$_t5d_b0record" 2>/dev/null && _t5d_b0_haslist=1
  # either outcome is legal (the brief's own escape valve): the decorated list fits and is KEPT, or
  # the budget catches it first and every list is omitted with its sentence — never a record the
  # seam itself has to refuse for being oversized.
  if [ "$rc" -eq 0 ] && [ "$_t5d_b0_seamrc" -eq 0 ] && [ "$_t5d_b0_bytes" -le 65536 ] \
     && { [ "$_t5d_b0_haslist" -eq 1 ] || printf '%s' "$_t5d_b0err" | grep -q 'over the row budget'; }; then
    echo "PASS: selftest — T5d step 0: the worst-case $_t5d_b0rows x 32-char-id ready record ($_t5d_b0_bytes B, list kept=$_t5d_b0_haslist) round-trips inside the seam's 64 KiB cap — passes by omission today (list kept=0; T10-harden-A R1 below pins the KEPT side)"
  else
    echo "FAIL: selftest — T5d step 0: the worst-case record busted the seam's cap or failed to round-trip (rc=$rc seamrc=$_t5d_b0_seamrc bytes=$_t5d_b0_bytes err='$_t5d_b0err')"; sfail=1
  fi

  # === T10-harden-A R1 (BLOCKING-class pin, carried T10-CI-PARITY items 10-12): the leg above
  # accepts EITHER outcome (kept or omitted), so it stays green under a mutant that widens
  # TR_ROW_BYTE_BUDGET past its safe ceiling. This leg pins the KEPT side for real (480 ready rows
  # of 28-char ids, all four dor-* mapped, blob ~35,530 B pre-decoration) AND pins the constant
  # itself against the corrected 36,327 B ceiling, so TR_ROW_BYTE_BUDGET=37800 goes RED here.
  _r1root="$tmpd/r1root"; mkdir -p "$_r1root/.kit"
  cat > "$_r1root/CLAUDE.md" <<'EOF'
- **Backlog backend**: Jira
EOF
  _r1conf="$_r1root/.kit/tracker.conf"
  cat > "$_r1conf" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
list_cap=1000
state.ready=Selected
field.acceptance=description
field.metric=customfield_10099
field.size=label:size
field.risk=label:risk
EOF
  # 28-char ids ("AB-" + a leading 1 + 24 digits — R4 refuses a leading zero after the hyphen):
  # the subject is id 1, the 479 non-subject ready rows are ids 2..480 — 480 ready rows total,
  # exactly at TR_ROW_BUDGET, mirroring T5d step 0's own shape.
  _r1subject=$(printf 'AB-1%024d' 1)
  _r1ready="$tmpd/r1-ready.out"
  : > "$_r1ready"
  _r1i=2
  while [ "$_r1i" -le 480 ]; do
    printf 'AB-1%024d\n' "$_r1i" >> "$_r1ready"
    _r1i=$((_r1i + 1))
  done
  _r1rows=$(wc -l < "$_r1ready" | tr -d ' ')
  cat > "$fakedir/tracker-jira.sh" <<EOF
#!/bin/sh
case "\$1" in
  get-issue) printf 'key\t$_r1subject\n'; printf 'status-id\t10001\n'; printf 'status-name\tSelected\n'; printf 'assignee-present\ttrue\n'; exit 0 ;;
  permissions) echo ok; exit 0 ;;
  status-ids) cat "$_t5a2l_statusids"; exit 0 ;;
  list-in-states)
    shift
    case "\$*" in
      *10001*) cat "$_r1ready"; printf '%s\n' "$_r1subject" ;;
      *) printf '' ;;
    esac
    exit 0 ;;
  field-empty) printf ''; exit 0 ;;
  label-counts)
    shift 5
    for _r1lcid in \$*; do printf '%s\t1\n' "\$_r1lcid"; done
    exit 0 ;;
esac
EOF
  chmod +x "$fakedir/tracker-jira.sh"
  rc=0
  _r1record="$tmpd/r1-record.txt"
  : > "$_r1record"
  _r1err=$(tr_read "$_r1conf" "-" "$_r1record" "$_r1subject" "$_h40" ready 2>&1 >/dev/null) || rc=$?
  SEAM_ROOT="$_r1root"; SEAM_RECORD="$_r1record"; SEAM_HEAD="$_h40"
  _r1_seamrc=0; _seam_record_load >/dev/null 2>&1 || _r1_seamrc=$?
  _r1_bytes=$(wc -c < "$_r1record" | tr -d ' ')
  _r1_haslist=0
  grep -q '^list ready ' "$_r1record" 2>/dev/null && _r1_haslist=1
  # strict: the list MUST be kept (no "or omitted" escape) AND the constant must not exceed the
  # corrected ceiling — either failing catches a widened TR_ROW_BYTE_BUDGET (T10-CI-PARITY 10-12).
  if [ "$rc" -eq 0 ] && [ "$_r1_seamrc" -eq 0 ] && [ "$_r1_bytes" -le 65536 ] \
     && [ "$_r1_haslist" -eq 1 ] && [ "$TR_ROW_BYTE_BUDGET" -le 36327 ]; then
    echo "PASS: selftest — T10-harden-A R1: an in-budget $_r1rows x 28-char-id ready list ($_r1_bytes B) is genuinely KEPT, round-trips, and TR_ROW_BYTE_BUDGET stays inside the corrected 36,327 B ceiling"
  else
    echo "FAIL: selftest — T10-harden-A R1: the in-budget record was not kept, failed to round-trip, or TR_ROW_BYTE_BUDGET exceeds the ceiling (rc=$rc seamrc=$_r1_seamrc bytes=$_r1_bytes haslist=$_r1_haslist budget=$TR_ROW_BYTE_BUDGET err='$_r1err')"; sfail=1
  fi

  # === T5d leg 2: field.risk=customfield_10088 -> dor-risk from field-empty (design §4.2's closed
  # set — the same field-empty dispatch acceptance/metric already use, generic on the kind of the
  # conf value, never a risk-specific code path).
  _t5d_l2root="$tmpd/t5d-l2root"; mkdir -p "$_t5d_l2root/.kit"
  cat > "$_t5d_l2root/CLAUDE.md" <<'EOF'
- **Backlog backend**: Jira
EOF
  _t5d_l2conf="$_t5d_l2root/.kit/tracker.conf"
  cat > "$_t5d_l2conf" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
list_cap=200
state.ready=Selected
field.risk=customfield_10088
EOF
  _t5d_l2felog="$tmpd/l2-field-empty-argv.log"
  cat > "$fakedir/tracker-jira.sh" <<EOF
#!/bin/sh
case "\$1" in
  get-issue) cat "$_t5b1_getissue_readyab1"; exit 0 ;;
  permissions) echo ok; exit 0 ;;
  status-ids) cat "$_t5a2l_statusids"; exit 0 ;;
  list-in-states)
    shift
    case "\$*" in
      *10001*) printf 'AB-1\nAB-2\nAB-3\nAB-4\n' ;;
      *) printf '' ;;
    esac
    exit 0 ;;
  field-empty)
    shift
    printf '%s\n' "\$*" >> "$_t5d_l2felog"
    cat "$_t5a2l_ops/field-empty.out"
    exit 0 ;;
esac
EOF
  chmod +x "$fakedir/tracker-jira.sh"
  rc=0
  : > "$_t5d_l2felog"
  _t5d_l2record="$tmpd/l2-record.txt"
  : > "$_t5d_l2record"
  tr_read "$_t5d_l2conf" "-" "$_t5d_l2record" AB-1 "$_h40" ready >/dev/null 2>&1 || rc=$?
  SEAM_ROOT="$_t5d_l2root"; SEAM_RECORD="$_t5d_l2record"; SEAM_HEAD="$_h40"
  _t5d_l2_seamrc=0; _seam_record_load >/dev/null 2>&1 || _t5d_l2_seamrc=$?
  _t5d_l2_fecalls=$(wc -l < "$_t5d_l2felog" | tr -d ' ')
  if [ "$rc" -eq 0 ] && [ "$_t5d_l2_seamrc" -eq 0 ] && [ "$_t5d_l2_fecalls" = "1" ] \
     && grep -q 'customfield_10088' "$_t5d_l2felog" \
     && grep -q '^row AB-1 state=ready dor-risk=yes$' "$_t5d_l2record" 2>/dev/null \
     && grep -q '^row AB-2 state=ready dor-risk=no$' "$_t5d_l2record" 2>/dev/null \
     && grep -q '^row AB-3 state=ready dor-risk=no$' "$_t5d_l2record" 2>/dev/null \
     && grep -q '^row AB-4 state=ready dor-risk=yes$' "$_t5d_l2record" 2>/dev/null; then
    echo "PASS: selftest — T5d leg 2: field.risk=customfield_10088 -> dor-risk from field-empty (yes/no per membership), round-trips"
  else
    echo "FAIL: selftest — T5d leg 2: dor-risk via field-empty not applied correctly (rc=$rc, seam-rc=$_t5d_l2_seamrc, fe-calls=$_t5d_l2_fecalls, log: $(cat "$_t5d_l2felog" 2>/dev/null), record: $(cat "$_t5d_l2record" 2>/dev/null))"; sfail=1
  fi

  # === T5d leg 3: field.risk=label:risk -> dor-risk from label-counts (0/1/>=2), the SAME dispatch
  # dor-size already uses, generic on the kind of the conf value.
  _t5d_l3root="$tmpd/t5d-l3root"; mkdir -p "$_t5d_l3root/.kit"
  cat > "$_t5d_l3root/CLAUDE.md" <<'EOF'
- **Backlog backend**: Jira
EOF
  _t5d_l3conf="$_t5d_l3root/.kit/tracker.conf"
  cat > "$_t5d_l3conf" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
list_cap=200
state.ready=Selected
field.risk=label:risk
EOF
  _t5d_l3lclog="$tmpd/l3-label-counts-argv.log"
  cat > "$fakedir/tracker-jira.sh" <<EOF
#!/bin/sh
case "\$1" in
  get-issue) cat "$_t5b1_getissue_readyab1"; exit 0 ;;
  permissions) echo ok; exit 0 ;;
  status-ids) cat "$_t5a2l_statusids"; exit 0 ;;
  list-in-states)
    shift
    case "\$*" in
      *10001*) printf 'AB-1\nAB-2\nAB-3\nAB-4\n' ;;
      *) printf '' ;;
    esac
    exit 0 ;;
  label-counts)
    shift
    printf '%s\n' "\$*" >> "$_t5d_l3lclog"
    awk -F'\t' -v ids="\$*" 'BEGIN{n=split(ids,a," "); for(i=1;i<=n;i++) want[a[i]]=1} (\$1 in want)' "$_t5a2l_ops/label-counts.out"
    exit 0 ;;
esac
EOF
  chmod +x "$fakedir/tracker-jira.sh"
  rc=0
  : > "$_t5d_l3lclog"
  _t5d_l3record="$tmpd/l3-record.txt"
  : > "$_t5d_l3record"
  tr_read "$_t5d_l3conf" "-" "$_t5d_l3record" AB-1 "$_h40" ready >/dev/null 2>&1 || rc=$?
  SEAM_ROOT="$_t5d_l3root"; SEAM_RECORD="$_t5d_l3record"; SEAM_HEAD="$_h40"
  _t5d_l3_seamrc=0; _seam_record_load >/dev/null 2>&1 || _t5d_l3_seamrc=$?
  _t5d_l3_lccalls=$(wc -l < "$_t5d_l3lclog" | tr -d ' ')
  if [ "$rc" -eq 0 ] && [ "$_t5d_l3_seamrc" -eq 0 ] && [ "$_t5d_l3_lccalls" = "1" ] \
     && grep -q '^row AB-1 state=ready dor-risk=yes$' "$_t5d_l3record" 2>/dev/null \
     && grep -q '^row AB-2 state=ready$' "$_t5d_l3record" 2>/dev/null \
     && ! grep -q '^row AB-2 .*dor-risk' "$_t5d_l3record" 2>/dev/null \
     && grep -q '^row AB-3 state=ready dor-risk=no$' "$_t5d_l3record" 2>/dev/null \
     && grep -q '^row AB-4 state=ready dor-risk=no$' "$_t5d_l3record" 2>/dev/null; then
    echo "PASS: selftest — T5d leg 3: field.risk=label:risk -> dor-risk from label-counts (0/1/>=2 per row, >=2 omitted), round-trips"
  else
    echo "FAIL: selftest — T5d leg 3: dor-risk via label-counts not applied correctly (rc=$rc, seam-rc=$_t5d_l3_seamrc, lc-calls=$_t5d_l3_lccalls, record: $(cat "$_t5d_l3record" 2>/dev/null))"; sfail=1
  fi

  # === T5d leg 4: field.risk absent from the conf -> omitted everywhere, NEVER n/a — the SAME
  # silent F-7 path `none` already takes (an unmapped field is exactly as legal as an explicit
  # `none`; a sentence here would break every pre-T5d conf that maps only a subset of the four
  # fields — see the T5d evidence log for the measured regression this choice avoids).
  _t5d_l4root="$tmpd/t5d-l4root"; mkdir -p "$_t5d_l4root/.kit"
  cat > "$_t5d_l4root/CLAUDE.md" <<'EOF'
- **Backlog backend**: Jira
EOF
  _t5d_l4conf="$_t5d_l4root/.kit/tracker.conf"
  cat > "$_t5d_l4conf" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
list_cap=200
state.ready=Selected
EOF
  cat > "$fakedir/tracker-jira.sh" <<EOF
#!/bin/sh
case "\$1" in
  get-issue) cat "$_t5b1_getissue_readyab1"; exit 0 ;;
  permissions) echo ok; exit 0 ;;
  status-ids) cat "$_t5a2l_statusids"; exit 0 ;;
  list-in-states)
    shift
    case "\$*" in
      *10001*) printf 'AB-1\nAB-2\n' ;;
      *) printf '' ;;
    esac
    exit 0 ;;
  label-counts) echo "T5D-L4-UNEXPECTED-DISPATCH" >&2; exit 1 ;;
  field-empty) echo "T5D-L4-UNEXPECTED-DISPATCH" >&2; exit 1 ;;
esac
EOF
  chmod +x "$fakedir/tracker-jira.sh"
  rc=0
  _t5d_l4record="$tmpd/l4-record.txt"
  : > "$_t5d_l4record"
  _t5d_l4err=$(tr_read "$_t5d_l4conf" "-" "$_t5d_l4record" AB-1 "$_h40" ready 2>&1 >/dev/null) || rc=$?
  SEAM_ROOT="$_t5d_l4root"; SEAM_RECORD="$_t5d_l4record"; SEAM_HEAD="$_h40"
  _t5d_l4_seamrc=0; _seam_record_load >/dev/null 2>&1 || _t5d_l4_seamrc=$?
  if [ "$rc" -eq 0 ] && [ "$_t5d_l4_seamrc" -eq 0 ] && [ -z "$_t5d_l4err" ] \
     && ! grep -q 'dor-risk' "$_t5d_l4record" 2>/dev/null \
     && ! grep -q 'n/a' "$_t5d_l4record" 2>/dev/null; then
    echo "PASS: selftest — T5d leg 4: field.risk absent from the conf omits dor-risk everywhere, never n/a, no label-counts/field-empty dispatch"
  else
    echo "FAIL: selftest — T5d leg 4: an absent field.risk was not fully omitted (rc=$rc, seam-rc=$_t5d_l4_seamrc, err='$_t5d_l4err', record: $(cat "$_t5d_l4record" 2>/dev/null))"; sfail=1
  fi

  # === T5d leg 4b (defence in depth, unreachable via a real conf — tracker-conf.sh's OWN field.*
  # grammar already refuses any value outside customfield_N/label:<prefix>/none/description
  # upstream of tr_read ever running, so the dispatch table's `unrecognized` branch can never fire
  # from a valid conf; pinned directly on the classifier, same convention as fix1 V4's own
  # unreachable-through-the-pipeline leg above). Also the "map risk by the wrong kind" mutant's home.
  if [ "$(tr_field_kind customfield_10077)" = field-empty ] && [ "$(tr_field_kind description)" = field-empty ] \
     && [ "$(tr_field_kind label:size)" = label-counts ] && [ "$(tr_field_kind none)" = none ] \
     && [ "$(tr_field_kind '')" = none ] && [ "$(tr_field_kind customfield_)" = unrecognized ] \
     && [ "$(tr_field_kind customfield_abc)" = unrecognized ] && [ "$(tr_field_kind garbage-value)" = unrecognized ]; then
    echo "PASS: selftest — T5d leg 4b: tr_field_kind classifies every §4.2 value kind correctly, including the unrecognized case a real conf can never produce (direct calls)"
  else
    echo "FAIL: selftest — T5d leg 4b: tr_field_kind misclassified a value (direct calls)"; sfail=1
  fi

  # === T5d leg 6: a record with all four dor-*=yes on the subject round-trips through the SAME,
  # unmodified seam arm (_seam_tracker_row_flag, backlog-lib.sh) that already answers dor-acceptance
  # etc — proving the reader+seam round trip end-to-end for dor-risk. backlog-current.sh's own
  # Ready-gate DECISION still wires only dor-metric today (its own header, ~line 355) — wiring all
  # four dor-* into that gate's grading is T9's work, not this reader-only lane; this leg's scope is
  # the seam round-trip, not the gate. The full gate-level assertion the brief's own leg 6 names
  # belongs to T10's integration run, once T9 lands here.
  _t5d_l6root="$tmpd/t5d-l6root"; mkdir -p "$_t5d_l6root/.kit"
  cat > "$_t5d_l6root/CLAUDE.md" <<'EOF'
- **Backlog backend**: Jira
EOF
  _t5d_l6conf="$_t5d_l6root/.kit/tracker.conf"
  cat > "$_t5d_l6conf" <<'EOF'
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
list_cap=200
state.ready=Selected
field.acceptance=description
field.metric=customfield_10077
field.size=label:size
field.risk=customfield_10088
EOF
  cat > "$fakedir/tracker-jira.sh" <<EOF
#!/bin/sh
case "\$1" in
  get-issue) printf 'key\tAB-1\n'; printf 'status-id\t10001\n'; printf 'status-name\tSelected\n'; printf 'assignee-present\ttrue\n'; exit 0 ;;
  permissions) echo ok; exit 0 ;;
  status-ids) cat "$_t5a2l_statusids"; exit 0 ;;
  list-in-states) printf 'AB-1\n'; exit 0 ;;
  label-counts)
    shift
    printf 'AB-1\t1\n'
    exit 0 ;;
  field-empty) printf ''; exit 0 ;;
esac
EOF
  chmod +x "$fakedir/tracker-jira.sh"
  rc=0
  _t5d_l6record="$tmpd/l6-record.txt"
  : > "$_t5d_l6record"
  tr_read "$_t5d_l6conf" "-" "$_t5d_l6record" AB-1 "$_h40" ready >/dev/null 2>&1 || rc=$?
  # shellcheck disable=SC2034 # all three read by backlog-lib.sh's sourced seam functions
  SEAM_ROOT="$_t5d_l6root"
  # shellcheck disable=SC2034
  SEAM_RECORD="$_t5d_l6record"
  # shellcheck disable=SC2034
  SEAM_HEAD="$_h40"
  _t5d_l6_seamrc=0; _seam_record_load >/dev/null 2>&1 || _t5d_l6_seamrc=$?
  # WB-FIX-A A1: the seam's row-flag ANSWER for dor-risk/dor-acceptance on this exact shape is
  # asserted in conformance/loop-state.sh's T6b section (WB-FIX-A T5d-leg6), not here — see the Q2
  # leg's own comment above for why (board-parser-drift clause c / D-240919-4).
  if [ "$rc" -eq 0 ] && [ "$_t5d_l6_seamrc" -eq 0 ] \
     && grep -q '^row AB-1 state=ready claimed=yes dor-acceptance=yes dor-metric=yes dor-size=yes dor-risk=yes$' "$_t5d_l6record" 2>/dev/null; then
    echo "PASS: selftest — T5d leg 6: all four dor-*=yes round-trips and parses (rc 0) — the answer half lives in loop-state.sh's T6b section (WB-FIX-A T5d leg6; the full backlog-current.sh GATE decision wiring all four dor-* is T9's work, deferred to T10's integration run)"
  else
    echo "FAIL: selftest — T5d leg 6: the all-four-yes record did not round-trip through the seam (rc=$rc, seam-rc=$_t5d_l6_seamrc, record: $(cat "$_t5d_l6record" 2>/dev/null))"; sfail=1
  fi

  # === T10-harden-A R2 (T5d security Low 2, defence in depth): tr_dispatch_field_empty and
  # tr_dispatch_labelcounts each refuse BEFORE any adapter dispatch when $_verdict is not 'bound' —
  # the caller (tr_apply_dor_flag) already gates this, but a direct call bypasses that gate.
  _r2log="$tmpd/r2-adapter-calls.log"
  : > "$_r2log"
  cat > "$fakedir/tracker-jira.sh" <<EOF
#!/bin/sh
echo "\$1" >> "$_r2log"
exit 0
EOF
  chmod +x "$fakedir/tracker-jira.sh"
  _verdict=unverified
  _extra="row AB-1 state=ready"
  _subjfieldval="PRE"
  _TJ_CURL_BIN="poison"
  tr_dispatch_field_empty "$fakedir/tracker-jira.sh" base cloud AB AB-1 ready description dor-acceptance AB-1 >/dev/null 2>&1
  _r2fe_rc=$?
  _r2fe_calls=$(wc -l < "$_r2log" | tr -d ' ')
  _r2fe_extra=$_extra
  _r2fe_subjfieldval=$_subjfieldval
  _r2fe_curlbin=${_TJ_CURL_BIN:-unset}
  : > "$_r2log"
  _verdict=unverified
  _extra="row AB-1 state=ready"
  _subjfieldval="PRE"
  _TJ_CURL_BIN="poison"
  tr_dispatch_labelcounts "$fakedir/tracker-jira.sh" base cloud AB AB-1 ready size dor-size AB-1 >/dev/null 2>&1
  _r2lc_rc=$?
  _r2lc_calls=$(wc -l < "$_r2log" | tr -d ' ')
  _r2lc_extra=$_extra
  _r2lc_subjfieldval=$_subjfieldval
  _r2lc_curlbin=${_TJ_CURL_BIN:-unset}
  if [ "$_r2fe_rc" -eq 0 ] && [ "$_r2fe_calls" -eq 0 ] && [ "$_r2fe_extra" = "row AB-1 state=ready" ] \
     && [ "$_r2fe_subjfieldval" = "PRE" ] && [ "$_r2fe_curlbin" = unset ] \
     && [ "$_r2lc_rc" -eq 0 ] && [ "$_r2lc_calls" -eq 0 ] && [ "$_r2lc_extra" = "row AB-1 state=ready" ] \
     && [ "$_r2lc_subjfieldval" = "PRE" ] && [ "$_r2lc_curlbin" = unset ]; then
    echo "PASS: selftest — T10-harden-A R2: tr_dispatch_field_empty/tr_dispatch_labelcounts refuse before ANY adapter dispatch when \$_verdict is not bound (direct call, defence in depth), and unset _TJ_CURL_BIN as their own first statement"
  else
    echo "FAIL: selftest — T10-harden-A R2: a direct call with _verdict=unverified still dispatched the adapter, mutated state, or left _TJ_CURL_BIN set (fe: rc=$_r2fe_rc calls=$_r2fe_calls extra='$_r2fe_extra' subj='$_r2fe_subjfieldval' curl=$_r2fe_curlbin; lc: rc=$_r2lc_rc calls=$_r2lc_calls extra='$_r2lc_extra' subj='$_r2lc_subjfieldval' curl=$_r2lc_curlbin)"; sfail=1
  fi

  # === T10-harden-A R3 (T5d quality minor): tr_apply_dor_flag's `unrecognized)` branch (direct
  # call, a garbage field.* spec) emits the ONE fixed sentence and dispatches nothing. A real conf
  # can never produce this (tracker-conf.sh's own field.* grammar is a closed set, mirroring T5d
  # leg 4b's own finding for tr_field_kind) — reachable only by stubbing $TR_CONF_SH itself.
  _r3conf="$tmpd/r3-conf-placeholder"
  : > "$_r3conf"
  _r3confsh="$tmpd/r3-fake-tracker-conf.sh"
  cat > "$_r3confsh" <<'EOF'
#!/bin/sh
case "$1" in
  get) printf 'garbage\n'; exit 0 ;;
esac
exit 1
EOF
  chmod +x "$_r3confsh"
  _r3log="$tmpd/r3-adapter-calls.log"
  : > "$_r3log"
  cat > "$fakedir/tracker-jira.sh" <<EOF
#!/bin/sh
echo "\$1" >> "$_r3log"
exit 0
EOF
  chmod +x "$fakedir/tracker-jira.sh"
  _verdict=bound
  _extra="row AB-1 state=ready"
  _subjfieldval="PRE"
  _r3_realconfsh=$TR_CONF_SH
  TR_CONF_SH=$_r3confsh
  # called DIRECTLY, never via $(...) — tr_apply_dor_flag sets $_subjfieldval on the caller's own
  # shell (mirrors its own header comment); stderr is captured through a file instead.
  _r3errfile="$tmpd/r3-stderr.txt"
  tr_apply_dor_flag "$_r3conf" "$fakedir/tracker-jira.sh" base cloud AB AB-1 ready field.acceptance dor-acceptance >/dev/null 2>"$_r3errfile"
  _r3rc=$?
  TR_CONF_SH=$_r3_realconfsh
  _r3err=$(cat "$_r3errfile" 2>/dev/null)
  _r3calls=$(wc -l < "$_r3log" | tr -d ' ')
  if [ "$_r3rc" -eq 0 ] && [ "$_r3calls" -eq 0 ] \
     && [ "$_r3err" = "omitted: dor-acceptance (field.acceptance is not a recognized field mapping)" ] \
     && [ -z "$_subjfieldval" ]; then
    echo "PASS: selftest — T10-harden-A R3: tr_apply_dor_flag's unrecognized branch (direct call, a garbage field.* spec via a stubbed \$TR_CONF_SH) emits the one fixed sentence and dispatches nothing"
  else
    echo "FAIL: selftest — T10-harden-A R3: the unrecognized branch did not fire cleanly (rc=$_r3rc calls=$_r3calls err='$_r3err' subj='$_subjfieldval')"; sfail=1
  fi

  cat > "$fakedir/tracker-jira.sh" <<EOF
#!/bin/sh
case "\$1" in
  get-issue) printf 'key\tAB-1\n'; printf 'status-id\t10002\n'; printf 'status-name\tIn Dev\n'; exit 0 ;;
  permissions) echo ok; exit 0 ;;
  status-ids) cat "$_t5a2l_statusids"; exit 0 ;;
  list-in-states)
    shift
    printf '%s\n' "\$*" >> "$listargvlog"
    case "\$*" in
      *10001*) cat "$_t5a2l_ops/list-cloud-ready.out" ;;
      *10002*|*10003*) cat "$_t5a2l_ops/list-cloud-inprogress.out" ;;
      *) cat "$_t5a2l_ops/list-cloud-empty.out" ;;
    esac
    exit 0 ;;
esac
EOF
  chmod +x "$fakedir/tracker-jira.sh"

  rm -rf "$tmpd"; trap - EXIT INT TERM
  [ "$sfail" -eq 0 ] && { echo "OK: tracker-read selftest"; return 0; } || { echo "FAIL: tracker-read selftest"; return 1; }
}

# --- CLI ---------------------------------------------------------------------------------------
case "${1:-}" in
  --selftest) _tr_selftest; exit $? ;;
  '') echo "usage: tracker-read.sh <conf> <origin-conf|-> <record-path> <requested-id> <head-sha> [state...] | --selftest" >&2; exit 2 ;;
  *)
    [ $# -ge 5 ] || { echo "usage: tracker-read.sh <conf> <origin-conf|-> <record-path> <requested-id> <head-sha> [state...] | --selftest" >&2; exit 2; }
    tr_read "$@"; exit $? ;;
esac
