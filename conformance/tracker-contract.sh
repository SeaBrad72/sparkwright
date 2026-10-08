#!/bin/sh
# tracker-contract.sh — verify a Jira instance satisfies the §6 work-item contract (Slice 9h; --deep 10;
# TBG-TRACKER-CONF T4). The jira PREFLIGHT VERIFIER (design §7 F4) — transitional and deliberately NOT
# a second parser: it reads .kit/tracker.conf THROUGH scripts/tracker-conf.sh, never re-parsing the
# grammar itself. The transport is scripts/tracker-jira.sh contract-read (the one jira-HTTP primitive).
# Three-state, like branch-protection.sh:
#   creds (a valid .kit/tracker.conf pins base_url; KIT_TRACKER_USER/KIT_TRACKER_TOKEN or legacy
#     JIRA_EMAIL/JIRA_TOKEN supply the token) -> live REST check -> PASS/FAIL
#   no creds                                         -> UNVERIFIED (exit 2; never a silent pass)
#   --selftest                                       -> run the contract logic on fixtures (CI-safe)
# Base run checks the six §6 states + Size/Risk fields. With --deep, ALSO grades THIS project's own workflows
# (the adapter's one bulk workflows read, never a site-wide search) and reports the tier it PROVED: every
# transition into In Progress carries an exclusive Only-Assignee condition (server-enforced) · a team-managed
# project with none (convention, rc 0) · a company-managed gap (FAIL) · unreadable / Data Center (UNVERIFIED, rc 2).
# `flavour=cloud` selects REST v3, `flavour=datacenter` selects REST v2 (design §6a S-9).
# `--discover` prints the id<->name status map for the connected instance (design §6b R3) — a LOCAL
# read run under the developer's own token; it proves nothing about a live host in --selftest.
# T5 (design §6 threat T5): the token never reaches curl's argv. Auth is fed to `curl -K -` on STDIN
# (a config line `user = "<email>:<token>"`), never as a `-u` command-line argument and never written
# to disk. No `set -x`; failure sentences carry no header/body text (shape never content).
# Zero-dependency core (grep-based); curl only on the live path. POSIX sh; dash-clean.
# Exit: 0 = satisfied · 1 = a gap · 2 = UNVERIFIED / bad usage.
set -eu

REQUIRED="Backlog Ready In-Progress In-Review Released Done Blocked Size Risk"

# TC_SH: the ONE place the .kit/tracker.conf grammar lives (F4 — never re-parsed here). TJ_SH: the
# ONE place the curl-to-jira transport lives (T3b — this file calls it, it does not re-implement
# it). Both resolved relative to this script so they work whether invoked as
# `sh conformance/tracker-contract.sh` or via an absolute path.
# shellcheck disable=SC1007  # CDPATH= intentionally clears CDPATH to avoid cd side-effects
_TC_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TC_SH="$_TC_ROOT/scripts/tracker-conf.sh"
TJ_SH="$_TC_ROOT/scripts/tracker-jira.sh"

# check_blob <file>: every required name must appear as an EXACT quoted value (whitespace-insensitive).
check_blob() {
  bf=$1; f=0
  if [ ! -f "$bf" ]; then echo "FAIL: missing $bf"; return 1; fi
  norm=$(tr -s '[:space:]' '-' < "$bf")
  for name in $REQUIRED; do
    if printf '%s' "$norm" | grep -qF -- "\"$name\""; then
      echo "PASS: contract names '$name'"
    else
      echo "FAIL: contract omits '$name'"; f=1
    fi
  done
  return $f
}

# --- T3b: the ONE curl-to-jira implementation lives in scripts/tracker-jira.sh (contract-read) ---
# _tc_curl_authed <resource> <outfile> [args...]: a thin call-through — this file never builds a
# URL or touches curl itself. Appends the adapter's stdout to <outfile>; the adapter's own stderr
# sentences are fixed and are NOT discarded here (S-6 clean; shape-never-content is already the
# adapter's job). SD-7c: `_TJ_CURL_BIN` (a test-only curl-binary override the adapter itself may
# honour) is explicitly unset in this subshell so a leaked test override never reaches a live call.
_tc_curl_authed() {
  _tca_res=$1; _tca_out=$2; shift 2
  ( unset _TJ_CURL_BIN
    sh "$TJ_SH" contract-read "$BASE" "$FLAVOUR" "$_tca_res" "$@" >> "$_tca_out" )
}

# REST_BASE <flavour>: cloud -> v3, datacenter -> v2 (design §6a S-9). Unknown/empty -> cloud (v3);
# flavour itself is validated by tracker-conf.sh before this is ever reached.
rest_base() {
  case "${1:-cloud}" in
    datacenter) printf '/rest/api/2' ;;
    *)          printf '/rest/api/3' ;;
  esac
}

# live_check <base-url> <rest-base>: fetch statuses + fields (via the adapter), run check_blob.
live_check() {
  base=$1; rb=$2; tmp=$(mktemp)
  _tc_curl_authed status "$tmp" || {
    echo "FAIL: could not reach $base$rb/status"; rm -f "$tmp"; return 1; }
  _tc_curl_authed field "$tmp" || {
    echo "FAIL: could not reach $base$rb/field"; rm -f "$tmp"; return 1; }
  if check_blob "$tmp"; then rc=0; else rc=1; fi
  rm -f "$tmp"; return $rc
}

# --- --deep (TRACKER-CONTRACT-HONEST-TIER): grade THIS project's own workflows, never a site-wide read -------
# The adapter's project-workflows op does the grading in jq and prints closed-grammar `wf` lines; this side only
# resolves the conf's in-progress status ids, filters the lines and words the verdict. rc 0 = PASS or the
# convention tier (a supported tier, not a gap) · 1 = a gap · 2 = UNVERIFIED (the tier is attested, not proven).
_dl_unv() { echo "UNVERIFIED: deep — $1; the tier is attested, not proven"; }

# _dl_ids <dir> <key>: the conf's state.in-progress names -> status ids (from project-statuses), space-joined.
_dl_ids() {
  _di_names=$(sh "$TC_SH" get-all state.in-progress "$CONF" 2>/dev/null || true)
  [ -n "$_di_names" ] || _di_names="In Progress"
  _di_ids=""
  while IFS= read -r _di_n; do
    _di_one=$(awk -F'\t' -v n="$_di_n" '$1 == "status" && $3 == n { print $2 }' "$1/s" | tr '\n' ' ')
    if [ -z "$_di_one" ]; then
      echo "FAIL: deep — the conf's state.in-progress '$_di_n' is not a status of $2 (run --discover, then fix state.in-progress in $CONF)"; return 1
    fi
    _di_ids="$_di_ids $_di_one"
  done <<EOF_DI
$_di_names
EOF_DI
}

# _dl_verdict <dir> <key> <style> <ids>: the in-progress transitions' verdicts -> PASS / TIER / FAIL lines.
_dl_verdict() {
  _dv_hits=$(awk -F'\t' -v ids="$4" 'BEGIN { n = split(ids, a, " "); for (i = 1; i <= n; i++) want[a[i]] = 1 } $1 == "wf" && ($4 in want)' "$1/w")
  if [ -z "$_dv_hits" ]; then
    echo "FAIL: deep — no transition into the conf's in-progress status in $2's workflows (the claim cannot be server-enforced)"; return 1
  fi
  _dv_bad=$(printf '%s\n' "$_dv_hits" | awk -F'\t' '$5 != "enforced" { printf "FAIL: deep — convention tier: transition \047%s\047 into In Progress in workflow \047%s\047 lacks an exclusive Only-Assignee condition reachable through ALL groups (JIRA-SETUP.md §3)\n", $3, $2 }')
  if [ -z "$_dv_bad" ]; then
    DEEP_VERIFIED=1
    echo "PASS: deep — server-enforced claim (Only-Assignee on every transition into In Progress in $(printf '%s\n' "$_dv_hits" | cut -f2 | sort -u | wc -l | tr -d ' ') workflow(s))"
    return 0
  fi
  if [ "$3" = next-gen ] && ! printf '%s\n' "$_dv_hits" | grep -q '	enforced$'; then
    echo "TIER: convention — Jira's UI offers no Only-Assignee restriction on a team-managed project, so $2 is on the convention tier; --deep grades what the workflow actually carries (see JIRA-SETUP.md §3). board claim still assigns and transitions, last-writer-wins."
    return 0
  fi
  printf '%s\n' "$_dv_bad"; return 1
}

# deep_live <base-url> <rest-base>: project -> statuses -> one workflows read per issue type -> verdict. A 401 on
# the workflows read is disambiguated with `myself` (200 = the token lacks the permission, not a bad credential).
deep_live() {
  if [ "$FLAVOUR" = datacenter ]; then
    _dl_unv "Data Center exposes no REST read of workflow transition conditions"; return 2
  fi
  _dl_key=$(sh "$TC_SH" get project "$CONF")
  _dl_dir=$(mktemp -d) || { _dl_unv "a scratch directory could not be created"; return 2; }
  trap 'rm -rf "$_dl_dir"' EXIT
  trap 'rm -rf "$_dl_dir"; exit 130' INT
  trap 'rm -rf "$_dl_dir"; exit 143' TERM
  _dl_rc=0
  _dl_run "$_dl_dir" "$_dl_key" || _dl_rc=$?
  rm -rf "$_dl_dir"; trap - EXIT INT TERM; return "$_dl_rc"
}

_dl_run() {
  _tc_curl_authed project "$1/p" "$2" && _tc_curl_authed project-statuses "$1/s" "$2" \
    || { _dl_unv "the project's style or statuses could not be read"; return 2; }
  _dl_ids "$1" "$2" || return 1
  _dr_types=$(awk -F'\t' '$1 == "type" { print $2 }' "$1/s" | tr '\n' ' ')
  _dr_rc=0
  # shellcheck disable=SC2086  # the word split IS the issue-type id list
  _tc_curl_authed project-workflows "$1/w" "$(awk -F'\t' '$1 == "id" { print $2 }' "$1/p")" $_dr_types || _dr_rc=$?
  if [ "$_dr_rc" -eq 4 ]; then
    _dr_my=0; _tc_curl_authed myself "$1/m" || _dr_my=$?
    case $_dr_my in
      0) _dl_unv "the token cannot read this project's workflows (Administer Jira is required for company-managed workflows)" ;;
      4) _dl_unv "the credential was rejected by Jira (check KIT_TRACKER_USER / KIT_TRACKER_TOKEN)" ;;
      *) _dl_unv "could not check the credential (Jira did not answer the identity probe)" ;;
    esac
    return 2
  fi
  [ "$_dr_rc" -eq 0 ] && [ -s "$1/w" ] || { _dl_unv "the project's workflows could not be read"; return 2; }
  _dl_verdict "$1" "$2" "$(awk -F'\t' '$1 == "style" { print $2 }' "$1/p")" "$_di_ids"
}

# --- --discover (design §6b R3): print the id<->name status map --------------------------------
# Read through the adapter's project-statuses op (jq): the old site-wide /status grep paired a team-managed
# status's nested scope.project.id as a status id, and listed every project's statuses on a multi-project site.
# tc_discover <base> <rest-base>: live fetch (via the adapter) + print. Returns 1 when it cannot read.
tc_discover() {
  base=$1; rb=$2; tmp=$(mktemp)
  if _tc_curl_authed project-statuses "$tmp" "$(sh "$TC_SH" get project "$CONF")"; then
    echo "id	name"
    awk -F'\t' '$1 == "status" { print $2 "\t" $3 }' "$tmp"
    rm -f "$tmp"; return 0
  fi
  echo "FAIL: could not read $base$rb/project statuses"; rm -f "$tmp"; return 1
}

# --- --fields / the create-coherence leg (BOARD-CREATE-HONOURS-FIELD-MAP) ----------------------------
# Field ids are PER ISSUE TYPE on a team-managed project; `board create` writes Size/Risk through the
# conf's ONE field.size/field.risk, so the mapping must be on the create screen of the type it creates.
# Both read through the adapter's create-meta op (this file never builds a URL), as a local read under
# the developer's own token. tc_cm_get <project> [<type>]: the adapter's create-meta lines on stdout.
tc_cm_get() {
  ( unset _TJ_CURL_BIN
    sh "$TJ_SH" create-meta "$BASE" "$FLAVOUR" "$1" ${2:+"$2"} )
}

# tc_fields_render <meta-file>: `issuetype<TAB>Size<TAB>Risk` per type, `-` when a type has no such field.
tc_fields_render() {
  awk -F'\t' '
    !($1 in seen) { seen[$1] = 1; order[++n] = $1; sz[$1] = "-"; rk[$1] = "-" }
    $2 ~ /^customfield_/ && tolower($4) == "size" && sz[$1] == "-" { sz[$1] = $2 }
    $2 ~ /^customfield_/ && tolower($4) == "risk" && rk[$1] == "-" { rk[$1] = $2 }
    END { print "issuetype\tSize\tRisk"; for (i = 1; i <= n; i++) print order[i] "\t" sz[order[i]] "\t" rk[order[i]] }' "$1"
}

# tc_fields <meta-file> <create-type>: the table, then the conf lines to paste for the create type.
tc_fields() {
  tc_fields_render "$1"
  echo "paste into .kit/tracker.conf for create.issuetype=$2:"
  tc_fields_render "$1" | awk -F'\t' -v t="$2" '$1 == t { if ($2 != "-") print "field.size=" $2; if ($3 != "-") print "field.risk=" $3; found = 1 }
    END { if (!found) print "# (no such type in this project: set create.issuetype to one of the rows above)" }'
}

# tc_coherence <name:size|risk> <mapping> <type> <meta-file>: one PASS/FAIL line; return 1 on incoherence.
# customfield_N must be on the create type's screen; label:<p> must not leave a same-NAMED select unused
# (the reader would count labels nobody sets). none/description/unset is not this leg's business.
tc_coherence() {
  _co_sel=$(awk -F'\t' -v n="$1" '$2 ~ /^customfield_/ && tolower($4) == n { print $2; exit }' "$4")
  _co_opt=$(awk -F'\t' -v n="$1" '$2 ~ /^customfield_/ && $3 == "option" && tolower($4) == n { print $2; exit }' "$4")
  case "$2" in
    customfield_*)
      _co_st=$(awk -F'\t' -v f="$2" '$2 == f { print $3; exit }' "$4")
      if [ -n "$_co_st" ] && [ "$_co_st" != option ] && [ "$_co_st" != string ]; then
        echo "FAIL: field.$1=$2 has schema type '$_co_st'; board create writes only a select (option) or string field - map a select field"; return 1
      elif [ -n "$_co_st" ]; then
        echo "PASS: field.$1=$2 is on the create screen of '$3'"
      elif [ -n "$_co_sel" ]; then
        echo "FAIL: field.$1=$2 is not on the create screen of '$3'; its own field is $_co_sel - set field.$1=$_co_sel in .kit/tracker.conf"; return 1
      else
        echo "FAIL: field.$1=$2 is not on the create screen of '$3' and that type has no field named '$1' (run --fields)"; return 1
      fi ;;
    label:*)
      if [ -n "$_co_opt" ]; then
        echo "FAIL: field.$1=$2 but '$3' has a $1 select ($_co_opt) the readers would not count - set field.$1=$_co_opt in .kit/tracker.conf"; return 1
      fi
      echo "PASS: field.$1=$2 has no same-named select on '$3' to disagree with" ;;
    *) : ;;
  esac
}

# tc_coherence_live: the base run's coherence leg for the conf's create type (default Task). A type the
# project lacks, or an unreadable create-meta, is a FAIL (never a silent pass).
tc_coherence_live() {
  _cl_type=$(sh "$TC_SH" get create.issuetype "$CONF" 2>/dev/null || printf 'Task')
  _cl_size=$(sh "$TC_SH" get field.size "$CONF" 2>/dev/null || true)
  _cl_risk=$(sh "$TC_SH" get field.risk "$CONF" 2>/dev/null || true)
  _cl_meta=$(mktemp); _rq_dir=$(mktemp -d)
  trap 'rm -rf "$_cl_meta" "$_rq_dir"' EXIT
  trap 'rm -rf "$_cl_meta" "$_rq_dir"; exit 130' INT
  trap 'rm -rf "$_cl_meta" "$_rq_dir"; exit 143' TERM
  # the required-field leg runs FIRST, so an unmapped size/risk (the early return below) can never skip it
  _cl_rc=0
  echo "Required create fields (issue type '$_cl_type'):"
  if tc_req_load "$_cl_type"; then tc_req_check || _cl_rc=1; else _cl_rc=1; fi
  case "$_cl_size$_cl_risk" in
    *customfield_*|*label:*) : ;;
    *) echo "NOTE: field.size/field.risk are not mapped to a customfield or label - 'board create' cannot write Size/Risk (map them per JIRA-SETUP.md section 4)."
       rm -rf "$_cl_meta" "$_rq_dir"; trap - EXIT INT TERM; return "$_cl_rc" ;;
  esac
  if ! tc_cm_get "$(sh "$TC_SH" get project "$CONF")" "$_cl_type" > "$_cl_meta"; then
    echo "FAIL: could not read the create-meta of issue type '$_cl_type' (is create.issuetype a type of this project? run --fields)"; rm -rf "$_cl_meta" "$_rq_dir"; trap - EXIT INT TERM; return 1
  fi
  echo "Create coherence (issue type '$_cl_type'):"
  tc_coherence size "$_cl_size" "$_cl_type" "$_cl_meta" || _cl_rc=1
  tc_coherence risk "$_cl_risk" "$_cl_type" "$_cl_meta" || _cl_rc=1
  rm -rf "$_cl_meta" "$_rq_dir"; trap - EXIT INT TERM; return "$_cl_rc"
}

# --- required create fields (TRACKER-REQUIRED-FIELDS-DISCOVERY, design 2026-10-03 §6, §15) ------------------------
# Read through the adapter (`required-fields`, `writable-create-keys`: this file never builds a URL) plus the conf's
# create.<id> keys. The no-flag leg prints field ID and NAME only - never allowed values (S-6, §15e: it runs in CI
# logs); only --fields, run by a developer on their own token, prints them.
_TC_TAB=$(printf '\t')
# tc_req_load <type>: needs $_rq_dir (the caller's temp dir). Fills $_rq_dir/{rf,cp}, $_rq_wk, $_rq_size, $_rq_risk.
tc_req_load() {
  _rq_wk=$( ( unset _TJ_CURL_BIN; sh "$TJ_SH" writable-create-keys ) 2>/dev/null ) || _rq_wk=''
  [ -n "$_rq_wk" ] || { echo "FAIL: could not read the adapter's writable create keys"; return 1; }
  if ! ( unset _TJ_CURL_BIN; sh "$TJ_SH" required-fields "$BASE" "$FLAVOUR" "$(sh "$TC_SH" get project "$CONF")" "$1" ) > "$_rq_dir/rf" 2>/dev/null; then
    echo "FAIL: could not read the required fields of issue type '$1' (is create.issuetype a type of this project? run --fields)"; return 1
  fi
  sh "$TC_SH" get-prefix create. "$CONF" > "$_rq_dir/cp" 2>/dev/null || { echo "FAIL: could not read the create.<id> keys of $CONF"; return 1; }
  _rq_size=$(sh "$TC_SH" get field.size "$CONF" 2>/dev/null || true)
  _rq_risk=$(sh "$TC_SH" get field.risk "$CONF" 2>/dev/null || true)
}
# tc_writable <id>: is it in the adapter's closed writable set (customfield_N stands for any customfield_<digits>)?
tc_writable() {
  case "$1" in
    customfield_*)
      _tw_n=${1#customfield_}
      case "$_tw_n" in ''|*[!0-9]*) return 1 ;; esac
      [ "${#_tw_n}" -le 10 ] || return 1
      printf '%s\n' "$_rq_wk" | grep -qxF 'customfield_N' ;;
    *) printf '%s\n' "$_rq_wk" | grep -qxF "$1" ;;
  esac
}
# tc_req_classify <id> <kind>: sets _rq_st = flag | unsupported | nowrite | covered | prompt | mapped | unmapped.
# description/parent are filled per card by board create's own flags - never by a conf create. line.
tc_req_classify() {
  case "$1" in description|parent) _rq_st=flag; return 0 ;; esac
  if [ "$2" = unsupported ]; then _rq_st=unsupported; return 0; fi
  if ! tc_writable "$1"; then _rq_st=nowrite; return 0; fi
  if [ "$1" = "$_rq_size" ] || [ "$1" = "$_rq_risk" ]; then _rq_st=covered; return 0; fi
  case $(awk -F'\t' -v k="create.$1" '$1 == k { print $2; exit }' "$_rq_dir/cp") in
    '') _rq_st=unmapped ;; prompt) _rq_st=prompt ;; *) _rq_st=mapped ;;
  esac
}
# tc_req_dropped: the adapter's `#dropped<TAB><n>` sentinel (n required fields it could not name) is a FAIL - the
# create cannot be proven complete. rc 0 = none dropped.
tc_req_dropped() {
  _rd_n=$(awk -F'\t' '$1 == "#dropped" { print $2; exit }' "$_rq_dir/rf")
  case "$_rd_n" in ''|0|*[!0-9]*) return 0 ;; esac
  echo "FAIL: the tracker reported $_rd_n required field(s) the kit cannot name - give them a default value in Jira or take them off the create screen"
  return 1
}
# tc_req_check: one PASS/FAIL line per required field and per out-of-set create.<id> key; return 1 on any FAIL.
tc_req_check() {
  _rq_rc=0
  tc_req_dropped || _rq_rc=1
  while IFS="$_TC_TAB" read -r _rq_id _rq_kind _rq_name _rq_rest; do
    case "$_rq_id" in ''|'#'*) continue ;; esac
    tc_req_classify "$_rq_id" "$_rq_kind"
    _rq_what="required create field $_rq_id ($_rq_name)"
    case "$_rq_st" in
      flag) echo "PASS: $_rq_what is filled per card by board create --$_rq_id" ;;
      covered) echo "PASS: $_rq_what is covered by field.size/field.risk" ;;
      mapped) echo "PASS: $_rq_what is set by create.$_rq_id" ;;
      prompt) echo "PASS: $_rq_what is create.$_rq_id=prompt (prompt: the agent supplies it per card)" ;;
      unsupported) echo "FAIL: $_rq_what has a field type the kit cannot fill - give it a default value in Jira (field configuration) or take it off the create screen"; _rq_rc=1 ;;
      nowrite) echo "FAIL: $_rq_what is not one of the adapter's writable create keys ($(printf '%s' "$_rq_wk" | tr '\n' ' ')) - give it a default value in Jira or take it off the create screen"; _rq_rc=1 ;;
      *) echo "FAIL: $_rq_what is not mapped - add create.$_rq_id=<value> to $CONF (the value is your team's: read the project CLAUDE.md, and if it is silent ask the owner; use create.$_rq_id=prompt for a per-card value; run tracker-contract.sh --fields to see the allowed values)"; _rq_rc=1 ;;
    esac
  done < "$_rq_dir/rf"
  while IFS="$_TC_TAB" read -r _rq_key _rq_rest; do
    [ -n "$_rq_key" ] || continue
    tc_writable "${_rq_key#create.}" || { echo "FAIL: $_rq_key is not a writable create key (the adapter writes only: $(printf '%s' "$_rq_wk" | tr '\n' ' '))"; _rq_rc=1; }
  done < "$_rq_dir/cp"
  return "$_rq_rc"
}
# tc_req_fields: the REQUIRED section of --fields (allowed values ARE printed here) and paste lines for the unmapped.
tc_req_fields() {
  tc_tr_load || return 1
  echo "REQUIRED (create screen of '$1'):"
  printf 'id\tkind\tname\tallowed\trequired-by\n'
  _rq_paste=''
  while IFS="$_TC_TAB" read -r _rq_id _rq_kind _rq_name _rq_rest; do
    case "$_rq_id" in ''|'#'*) continue ;; esac
    # awk, not read: a tab IFS collapses the EMPTY allowed column and would shift completeness into it
    _rq_allowed=$(awk -F'\t' -v i="$_rq_id" '$1 == i { print $4; exit }' "$_rq_dir/rf")
    printf '%s\t%s\t%s\t%s\tcreate\n' "$_rq_id" "$_rq_kind" "$_rq_name" "$_rq_allowed"
    # an id the field.size/field.risk paste above already suggests is covered: never also a create.<id> paste (R2)
    if printf '%s\n' "${_rq_sugg:-}" | grep -qxF "$_rq_id"; then _rq_st=covered; else tc_req_classify "$_rq_id" "$_rq_kind"; fi
    case "$_rq_st" in
      unmapped) _rq_paste="$_rq_paste""create.$_rq_id=<value>
" ;;
      unsupported|nowrite) _rq_paste="$_rq_paste""# $_rq_id: the kit cannot fill it - give it a default value in Jira or take it off the create screen
" ;;
    esac
  done < "$_rq_dir/rf"
  [ -z "$ISSUE" ] || awk -F'\t' '{ print $2 "\t" $3 "\t" $4 "\t\ttransition-to-" $1 }' "$_rq_dir/tf"
  [ -z "$_rq_paste" ] || { echo "paste for the unmapped required fields (the value is your team's: read the project CLAUDE.md, and if it is silent ask the owner; use prompt for a per-card value):"; printf '%s' "$_rq_paste"; }
  tc_req_dropped; _rq_dr=$?
  if [ -z "$ISSUE" ]; then
    echo "NOTE: pass --issue <KEY> to list the required screen fields of that card's available transitions"
    return "$_rq_dr"
  fi
  echo "NOTE: workflow validators are not visible to the screen read; board move diagnoses a refused transition when Jira refuses it"
  return "$_rq_dr"
}
# tc_tr_load: with --issue, the card's transitions' required screen fields (adapter op `transition-fields`) into
# $_rq_dir/tf; an adapter failure is a FAIL, never a silent pass.
tc_tr_load() {
  [ -z "$ISSUE" ] && return 0
  if ! ( unset _TJ_CURL_BIN; sh "$TJ_SH" transition-fields "$BASE" "$FLAVOUR" "$ISSUE" ) > "$_rq_dir/tf" 2>/dev/null; then
    echo "FAIL: could not read the transitions of $ISSUE (is it a card of this project?)"; return 1
  fi
}

# tc_fields_live: --fields — every non-subtask type's ids, plus the paste lines for the create type, then the
# create type's REQUIRED fields.
tc_fields_live() {
  _fl_meta=$(mktemp); _rq_dir=$(mktemp -d)
  trap 'rm -rf "$_fl_meta" "$_rq_dir"' EXIT
  trap 'rm -rf "$_fl_meta" "$_rq_dir"; exit 130' INT
  trap 'rm -rf "$_fl_meta" "$_rq_dir"; exit 143' TERM
  _fl_type=$(sh "$TC_SH" get create.issuetype "$CONF" 2>/dev/null || printf 'Task')
  if ! tc_cm_get "$(sh "$TC_SH" get project "$CONF")" > "$_fl_meta"; then
    echo "FAIL: could not read the project's create-meta"; rm -rf "$_fl_meta" "$_rq_dir"; trap - EXIT INT TERM; return 1
  fi
  tc_fields "$_fl_meta" "$_fl_type"
  _rq_sugg=$(tc_fields_render "$_fl_meta" | awk -F'\t' -v t="$_fl_type" '$1 == t { if ($2 != "-") print $2; if ($3 != "-") print $3 }')
  if tc_req_load "$_fl_type" && tc_req_fields "$_fl_type"; then _fl_rc=0; else _fl_rc=1; fi
  rm -rf "$_fl_meta" "$_rq_dir"; trap - EXIT INT TERM; return "$_fl_rc"
}

# --- --preflight (TRACKER-PREFLIGHT-TIER-CARD, design 2026-10-03 §4/§14): the tier card ---------------------------------
# One line per rollout question, `name<TAB>verdict<TAB>text`, verdict in PASS FAIL TIER INFO ASK UNVERIFIED; rc 1 on any FAIL,
# else 2 on any UNVERIFIED, else 0. Every read goes through the adapter's contract-read set (this file never builds a URL);
# every printed value is a fixed sentence, a closed enum or a gated integer (S-6): no tracker body byte reaches the card.
# D: ONE source for the by-hand runner check; JIRA-SETUP §0 and the profile's CI notice repeat these words verbatim.
_PF_REACH_CI='CI reachability is measured on the runner, not here: once JIRA-SETUP §4 and §5 are merged, open Actions → Adopter Tracker Gates → Run workflow; its preflight step reports whether the runner can reach the site'
_PF_RUNNER_CURE='if CI cannot reach it either, set the repository variable KIT_TRACKER_RUNNER to a self-hosted runner label inside your network (JIRA-SETUP §0)'
_PF_FAILS=0; _PF_UNVS=0; _PF_RC=0
# _pf_line <name> <verdict> <text>: one card line; FAIL and UNVERIFIED are counted for the CARD line and the rc.
_pf_line() {
  case "$2" in FAIL) _PF_FAILS=$((_PF_FAILS + 1)) ;; UNVERIFIED) _PF_UNVS=$((_PF_UNVS + 1)) ;; esac
  printf '%s\t%s\t%s\n' "$1" "$2" "$3"
}
# _pf_end: the last line, and the rc.
_pf_end() {
  _pe_v=PASS; _PF_RC=0
  if [ "$_PF_UNVS" -gt 0 ]; then _pe_v=UNVERIFIED; _PF_RC=2; fi
  if [ "$_PF_FAILS" -gt 0 ]; then _pe_v=FAIL; _PF_RC=1; fi
  printf 'CARD\t%s\t%s FAIL · %s UNVERIFIED · run once with each credential (--as ci with the CI reader, --as dev with a developer'"'"'s)\n' "$_pe_v" "$_PF_FAILS" "$_PF_UNVS"
}
# _pf_get <file> <key>: the value of the first `key<TAB>value` line.
_pf_get() { awk -F'\t' -v k="$2" '$1 == k { print $2; exit }' "$1"; }
# _pf_enum <value> <word…>: the value when it is one of the words, else `unknown` (S-6: nothing else is ever printed).
_pf_enum() {
  _pn_v=$1; shift
  for _pn_w in "$@"; do
    if [ "$_pn_v" = "$_pn_w" ]; then printf '%s' "$_pn_v"; return 0; fi
  done
  printf 'unknown'
}
# _pf_num <value>: digits only, at most 9 of them, else `unknown`.
_pf_num() {
  case "$1" in
    ''|*[!0-9]*) printf 'unknown' ;;
    *) if [ "${#1}" -le 9 ]; then printf '%s' "$1"; else printf 'unknown'; fi ;;
  esac
}
# _pf_read <resource> <outfile> [args…]: one adapter read into a fresh file; stderr is dropped (the card has its own fixed words).
_pf_read() { : > "$2"; _tc_curl_authed "$@" 2>/dev/null; }
# _pf_perm <NAME>: yes / no / unknown from the perms read.
_pf_perm() { _pf_enum "$(_pf_get "$PFD/perms" "$1")" yes no unknown; }
# _pf_perms_line <role>: the permissions line.
_pf_perms_line() {
  _pp_rc=0; _pf_read perms "$PFD/perms" "$PF_KEY" || _pp_rc=$?
  [ "$_pp_rc" -eq 0 ] || : > "$PFD/perms"
  _pp_no=''; _pp_unk=''; _pp_over=''
  if [ "$1" = ci ]; then
    case $(_pf_perm BROWSE_PROJECTS) in
      no) _pf_line permissions FAIL "the CI reader cannot browse the project; grant Browse Projects"; return 0 ;;
      unknown) _pf_line permissions UNVERIFIED "the browse permission could not be read"; return 0 ;;
    esac
    for _pp_p in CREATE_ISSUES EDIT_ISSUES TRANSITION_ISSUES ASSIGN_ISSUES ADMINISTER_PROJECTS; do
      case $(_pf_perm "$_pp_p") in
        yes) _pp_over="$_pp_over${_pp_over:+, }$_pp_p" ;;
        unknown) _pp_unk=1 ;;
      esac
    done
    if [ -n "$_pp_over" ]; then _pf_line permissions FAIL "over-privileged: the CI reader holds $_pp_over; JIRA-SETUP §5a"; return 0; fi
    if [ -n "$_pp_unk" ]; then _pf_line permissions UNVERIFIED "could not read whether the CI reader holds write or admin permissions"; return 0; fi
    _pf_line permissions PASS "browse only"; return 0
  fi
  for _pp_p in BROWSE_PROJECTS CREATE_ISSUES TRANSITION_ISSUES ASSIGN_ISSUES; do
    case $(_pf_perm "$_pp_p") in
      no) _pp_no="$_pp_no${_pp_no:+, }$_pp_p" ;;
      unknown) _pp_unk=1 ;;
    esac
  done
  if [ -n "$_pp_no" ]; then _pf_line permissions FAIL "missing $_pp_no; the project admin grants them (Project settings → Access, or the permission scheme)"; return 0; fi
  if [ -n "$_pp_unk" ]; then _pf_line permissions UNVERIFIED "a needed permission could not be read"; return 0; fi
  _pf_line permissions PASS "browse · create · transition · assign"
}
# _pf_claim_line <style>: ONE line for the claim tier; the --deep engine (conf mode, classic only) is collapsed to it.
_pf_claim_line() {
  case "$1" in
    next-gen) _pf_line claim-tier TIER "convention (team-managed: Jira offers no Only-Assignee condition; see --deep)"; return 0 ;;
    classic) : ;;
    *) _pf_line claim-tier UNVERIFIED "the project style is unknown, so the claim tier could not be graded"; return 0 ;;
  esac
  if [ "$PF_NOCONF" -eq 1 ]; then _pf_line claim-tier INFO "run --deep after JIRA-SETUP §4 maps state.in-progress"; return 0; fi
  _pc_rc=0; _pc_out=$(deep_live "$BASE" "$REST" 2>/dev/null) || _pc_rc=$?
  _pc_k=$(printf '%s\n' "$_pc_out" | grep -c '^FAIL: deep — convention tier' || true)
  _pc_n=$(printf '%s\n' "$_pc_out" | sed -n 's/.* in \([0-9][0-9]*\) workflow(s)).*/\1/p' | sed -n 1p)
  if [ "$_pc_rc" -eq 0 ] && [ "$(_pf_num "$_pc_n")" != unknown ]; then _pf_line claim-tier PASS "server-enforced ($_pc_n workflow(s))"
  elif [ "$_pc_rc" -eq 1 ] && [ "$_pc_k" -gt 0 ]; then _pf_line claim-tier FAIL "$_pc_k transition(s) into In Progress lack Only-Assignee; detail: --deep"
  elif [ "$_pc_rc" -eq 2 ] && printf '%s' "$_pc_out" | grep -qF 'Administer Jira is required'; then _pf_line claim-tier ASK "ask an admin to run --deep"
  else _pf_line claim-tier UNVERIFIED "the claim tier could not be graded; run --deep for the detail"
  fi
}
# _pf_required_line: the create-field count through tc_req_* (conf mode only; a no-conf run has no create type to read).
_pf_required_line() {
  if [ "$1" = ci ]; then _pf_line required INFO "required create fields need Create issues, which the CI reader must not hold; run --preflight --as dev with a developer's credential"; return 0; fi
  if [ "$PF_NOCONF" -eq 1 ]; then _pf_line required INFO "run --fields after JIRA-SETUP §4"; return 0; fi
  mkdir -p "$PFD/rq"
  _pq_type=$(sh "$TC_SH" get create.issuetype "$CONF" 2>/dev/null || printf 'Task')
  _pq_rc=0
  _pq_out=$( ( _rq_dir="$PFD/rq"; tc_req_load "$_pq_type" >/dev/null || exit 9; tc_req_check ) 2>/dev/null ) || _pq_rc=$?
  if [ "$_pq_rc" -gt 1 ]; then _pf_line required UNVERIFIED "the required create fields could not be read; run --fields"; return 0; fi
  _pq_n=$(printf '%s\n' "$_pq_out" | grep -c '^FAIL' || true)
  if [ "$_pq_n" -eq 0 ]; then _pf_line required PASS "0 required create fields unmapped"; return 0; fi
  _pf_line required FAIL "$_pq_n required-field problem(s) on the create screen; run tracker-contract.sh with no flag for each one and its cure"
}
# _pf_epic_line / _pf_visibility_line: the two measured-fact lines.
_pf_epic_line() {
  _pg_rc=0; _pf_read epic-model "$PFD/epic" || _pg_rc=$?
  [ "$_pg_rc" -eq 0 ] || : > "$PFD/epic"
  case $(_pf_enum "$(_pf_get "$PFD/epic" epic)" parent epic-link both none) in
    parent|both) _pf_line epic-model PASS "parent" ;;
    epic-link) _pf_line epic-model INFO "the site exposes only Epic Link; --epic uses parent" ;;
    none) _pf_line epic-model INFO "no epic field" ;;
    *) _pf_line epic-model UNVERIFIED "the epic model could not be read" ;;
  esac
}
_pf_visibility_line() {
  _pv_rc=0; _pf_read visibility "$PFD/vis" "$PF_KEY" || _pv_rc=$?
  [ "$_pv_rc" -eq 0 ] || : > "$PFD/vis"
  _pv_v=$(_pf_num "$(_pf_get "$PFD/vis" visible)"); _pv_t=$(_pf_num "$(_pf_get "$PFD/vis" total)"); _pv_l=$(_pf_num "$(_pf_get "$PFD/vis" levels)")
  if [ "$_pv_v" = unknown ] || [ "$_pv_t" = unknown ]; then
    _pf_line visibility INFO "visible $_pv_v; total not readable"; return 0
  fi
  if [ "$_pv_v" -gt "$_pv_t" ]; then
    _pf_line visibility INFO "$_pv_v visible exceeds the total $_pv_t (count lag); re-run later"; return 0
  fi
  if [ "$_pv_v" -lt "$_pv_t" ]; then
    _pf_line visibility ASK "$((_pv_t - _pv_v)) of $_pv_t issues not visible to this account: an issue-security level, archived issues, or count lag; ask the admin which"; return 0
  fi
  [ "$_pv_l" != unknown ] || _pv_l='unknown (needs project admin)'
  _pf_line visibility PASS "$_pv_v of $_pv_t issues visible; $_pv_l issue-security levels"
}
# _pf_head <role>: the lines up to and including auth. rc 1 = the card stops here (the stop line has been printed).
_pf_head() {
  _ph_rc=0; _pf_read probe "$PFD/probe" || _ph_rc=$?
  if [ "$_ph_rc" -ne 0 ]; then _pf_line reach-here UNVERIFIED "the reachability probe could not be read"; return 1; fi
  case $(_pf_enum "$(_pf_get "$PFD/probe" reach)" ok unreachable redirect error proxy-refused) in
    ok) : ;;
    proxy-refused) _pf_line reach-here FAIL "HTTPS_PROXY or NO_PROXY carries a value the adapter refuses (letters, digits and : / @ . _ % + - only; percent-encode a proxy password's other characters)"; return 1 ;;
    unreachable) _pf_line reach-here FAIL "the site did not answer from this machine (network, VPN, IP allowlist or an egress proxy: set HTTPS_PROXY); $_PF_RUNNER_CURE"; return 1 ;;
    redirect) _pf_line reach-here FAIL "the site redirected (an SSO or proxy interstitial); point base_url at the site itself"; return 1 ;;
    error) _pf_line reach-here UNVERIFIED "the site answered with an error or a rate limit; retry later"; return 1 ;;
    *) _pf_line reach-here UNVERIFIED "the reachability probe returned an unreadable answer"; return 1 ;;
  esac
  _pf_deployment_line
  case $(_pf_enum "$(_pf_get "$PFD/probe" via)" proxy direct) in
    proxy) _ph_via=" (via a proxy)" ;;
    direct) _ph_via=" (direct)" ;;
    *) _ph_via="" ;;
  esac
  _pf_line reach-here PASS "the API answers from this machine$_ph_via"
  _pf_line reach-ci INFO "$_PF_REACH_CI"
  case $(_pf_enum "$(_pf_get "$PFD/probe" auth)" ok 401 403 unknown) in
    ok) _pf_line auth PASS "the site accepted the credential (basic auth, site URL)" ;;
    401) _pf_line auth FAIL "the site refused the credential: a wrong or revoked token, or a scoped token the kit does not route yet (see JIRA-SETUP §5)"; return 1 ;;
    403) _pf_line auth FAIL "the account cannot use the REST API (org token policy or product access); ask the site admin"; return 1 ;;
    *) _pf_line auth UNVERIFIED "the credential check was inconclusive"; return 1 ;;
  esac
  if [ "$1" = ci ]; then
    _ph_t=$(_pf_enum "$(_pf_get "$PFD/probe" type)" atlassian app customer unknown)
    _pf_line account INFO "$_ph_t account; use a dedicated account for the CI reader so a leaver does not break the gate"
  fi
}
# _pf_deployment_line: from server-info; a conf flavour that disagrees with the measured one FAILs.
_pf_deployment_line() {
  if [ "$(_pf_enum "$(_pf_get "$PFD/probe" auth)" ok 401 403 unknown)" != ok ]; then
    _pf_line deployment INFO "not readable until the site accepts the credential"; return 0
  fi
  _pd_rc=0; _pf_read server-info "$PFD/server" || _pd_rc=$?
  [ "$_pd_rc" -eq 0 ] || : > "$PFD/server"
  _pd_g=$(_pf_enum "$(_pf_get "$PFD/server" deployment)" cloud datacenter unknown)
  _pd_b=$(_pf_num "$(_pf_get "$PFD/server" build)")
  if [ "$_pd_g" = unknown ]; then _pf_line deployment UNVERIFIED "the site did not report its deployment type"; return 0; fi
  if [ "$_pd_g" != "$FLAVOUR" ]; then _pf_line deployment FAIL "the conf says $FLAVOUR, the site is $_pd_g; set flavour=$_pd_g in .kit/tracker.conf"; return 0; fi
  _pd_n=Cloud; [ "$_pd_g" = cloud ] || _pd_n='Data Center'
  [ "$_pd_b" = unknown ] || _pd_n="$_pd_n (build $_pd_b)"
  _pf_line deployment PASS "$_pd_n"
}
# pf_live <role> <project-key>: the whole card; the rc is left in _PF_RC. The host line goes out BEFORE any adapter read.
pf_live() {
  PF_KEY=$2
  _pl_host=${BASE#https://}; _pl_host=${_pl_host%/}
  _pf_line card INFO "$_pl_host · project $2 · as $1 · read-only"
  if _pf_head "$1"; then
    _pf_line token-expiry INFO "the API does not expose token expiry; check id.atlassian.com → Security → API tokens and your org's token policy"
    _pl_rc=0; _pf_read project "$PFD/proj" "$2" || _pl_rc=$?
    _pl_style=$(_pf_enum "$(_pf_get "$PFD/proj" style)" next-gen classic)
    [ "$_pl_rc" -eq 0 ] || _pl_style=unknown
    case $_pl_style in
      next-gen) _pf_line project PASS "team-managed" ;;
      classic) _pf_line project PASS "company-managed" ;;
      *) _pf_line project UNVERIFIED "the project style could not be read" ;;
    esac
    _pf_perms_line "$1"
    _pf_claim_line "$_pl_style"
    _pf_required_line "$1"
    _pf_epic_line
    _pf_visibility_line
    _pf_line automation ASK "automation rules are not readable without admin; ask the project admin which rules fire on the mapped statuses"
  fi
  _pf_end
}
# pf_noconf_conf: the no-conf inputs (--base, --project) -> a temporary conf in $PFD, validated by tracker-conf.sh; rc 2 and a
# fixed sentence BEFORE any adapter call on a refusal. The base is whole-string ^https://[a-z0-9][a-z0-9-]*\.atlassian\.net/?$ (H-1,
# design §14c): no path, port, userinfo, query or trailing dot - so the host can only be an Atlassian Cloud site named on argv.
pf_noconf_conf() {
  LC_ALL=C; export LC_ALL
  _pn_b=${PF_BASE%/}; _pn_name=${_pn_b#https://}; _pn_name=${_pn_name%.atlassian.net}
  case "$PF_BASE" in
    https://*.atlassian.net|https://*.atlassian.net/) : ;;
    *) _pn_name='' ;;
  esac
  case "$_pn_name" in
    ''|-*|*[!a-z0-9-]*)
      echo "refused: --base must be https://<name>.atlassian.net (an Atlassian Cloud site: no path, port, credentials or query); for Data Center or a custom domain, stamp .kit/tracker.conf first (JIRA-SETUP §4) and run --preflight with it" >&2
      return 2 ;;
  esac
  case "$PF_PROJECT" in
    [A-Z]*) : ;;
    *) echo "refused: --project must be a Jira project key (uppercase letters, digits and underscore, starting with a letter)" >&2; return 2 ;;
  esac
  case "$PF_PROJECT" in
    *[!A-Z0-9_]*) echo "refused: --project must be a Jira project key (uppercase letters, digits and underscore, starting with a letter)" >&2; return 2 ;;
  esac
  printf 'version=1\nbackend=jira\nbase_url=%s\nflavour=cloud\nauth=basic\nproject=%s\n' "$_pn_b" "$PF_PROJECT" > "$PFD/tracker.conf"
  if ! sh "$TC_SH" "$PFD/tracker.conf" >/dev/null 2>&1; then
    echo "refused: the --base and --project do not satisfy the tracker-conf grammar" >&2; return 2
  fi
}

# --- arg parse: --deep, --discover, --fields and --selftest combine in any order; --conf overrides the path ---
_TC_USAGE="usage: tracker-contract.sh [--deep] [--discover] [--fields [--issue <KEY>]] [--conf <path>] [--selftest] | --preflight [--as ci|dev] [--conf <path> | --base <url> --project <KEY>]"
DEEP=0; SELFTEST=0; DISCOVER=0; FIELDS=0; ISSUE=''; CONF=".kit/tracker.conf"
PREFLIGHT=0; PF_AS=dev; PF_AS_SET=0; PF_BASE=''; PF_BASE_SET=0; PF_PROJECT=''; PF_PROJECT_SET=0; CONF_GIVEN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --preflight) PREFLIGHT=1; shift ;;
    --as) [ $# -ge 2 ] || { echo "$_TC_USAGE" >&2; exit 2; }
          case "$2" in ci|dev) PF_AS=$2; PF_AS_SET=1; shift 2 ;; *) echo "$_TC_USAGE" >&2; exit 2 ;; esac ;;
    --base) [ $# -ge 2 ] || { echo "$_TC_USAGE" >&2; exit 2; }; PF_BASE=$2; PF_BASE_SET=1; shift 2 ;;
    --project) [ $# -ge 2 ] || { echo "$_TC_USAGE" >&2; exit 2; }; PF_PROJECT=$2; PF_PROJECT_SET=1; shift 2 ;;
    --deep) DEEP=1; shift ;;
    --discover) DISCOVER=1; shift ;;
    --fields) FIELDS=1; shift ;;
    --issue) [ $# -ge 2 ] || { echo "$_TC_USAGE" >&2; exit 2; }
             case "$2" in ''|*[!A-Za-z0-9_-]*) echo "$_TC_USAGE" >&2; exit 2 ;; esac
             ISSUE=$2; shift 2 ;;
    --selftest) SELFTEST=1; shift ;;
    --conf) [ $# -ge 2 ] || { echo "$_TC_USAGE" >&2; exit 2; }; CONF=$2; CONF_GIVEN=1; shift 2 ;;
    "") shift ;;
    *) echo "$_TC_USAGE" >&2; exit 2 ;;
  esac
done
[ -z "$ISSUE" ] || [ "$FIELDS" -eq 1 ] || { echo "$_TC_USAGE" >&2; exit 2; }
# --preflight: --as/--base/--project belong to it alone; --base and --project come as a pair and never beside a --conf; it does not mix
# with --deep/--fields/--discover (the card runs its own, collapsed, deep read).
if [ "$SELFTEST" -eq 0 ]; then
  if [ "$PREFLIGHT" -eq 0 ] && [ $((PF_AS_SET + PF_BASE_SET + PF_PROJECT_SET)) -gt 0 ]; then echo "$_TC_USAGE" >&2; exit 2; fi
  if [ "$PREFLIGHT" -eq 1 ] && [ $((DEEP + FIELDS + DISCOVER)) -gt 0 ]; then echo "$_TC_USAGE" >&2; exit 2; fi
  if [ "$PF_BASE_SET" -ne "$PF_PROJECT_SET" ] || { [ "$PF_BASE_SET" -eq 1 ] && [ "$CONF_GIVEN" -eq 1 ]; }; then echo "$_TC_USAGE" >&2; exit 2; fi
fi

if [ "$SELFTEST" -eq 1 ]; then
  sfail=0
  okf=$(mktemp); printf '"Backlog" "Ready" "In Progress" "In Review" "Released" "Done" "Blocked" "Size" "Risk"\n' > "$okf"
  if check_blob "$okf" >/dev/null 2>&1; then echo "PASS: selftest — conformant config passes"; else echo "FAIL: selftest — conformant wrongly rejected"; sfail=1; fi
  gapf=$(mktemp); printf '"Backlog" "Ready" "In Progress" "In Review" "Released" "Done" "Blocked" "Size"\n' > "$gapf"
  if check_blob "$gapf" >/dev/null 2>&1; then echo "FAIL: selftest — gap (missing Risk) not detected"; sfail=1; else echo "PASS: selftest — gap detected"; fi
  nmf=$(mktemp); printf '"Backlog" "Ready for Dev" "In Progress" "In Review" "Released" "Done" "Blocked" "Size" "Risk"\n' > "$nmf"
  if check_blob "$nmf" >/dev/null 2>&1; then echo "FAIL: selftest — loose 'Ready for Dev' wrongly accepted"; sfail=1; else echo "PASS: selftest — near-miss status name rejected"; fi
  tmpd=$(mktemp -d); trap 'rm -rf "$tmpd"' EXIT INT TERM

  # --- (e) flavour=datacenter selects REST v2 ---------------------------------------------------
  [ "$(rest_base cloud)" = "/rest/api/3" ] && echo "PASS: selftest — flavour=cloud selects REST v3" \
    || { echo "FAIL: selftest — flavour=cloud did not select REST v3"; sfail=1; }
  [ "$(rest_base datacenter)" = "/rest/api/2" ] && echo "PASS: selftest — flavour=datacenter selects REST v2" \
    || { echo "FAIL: selftest — flavour=datacenter did not select REST v2"; sfail=1; }

  # shellcheck disable=SC1007  # CDPATH= intentionally clears CDPATH to avoid cd side-effects
  _self=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/$(basename -- "$0")

  # === T3b: a fake-adapter tree — proves the CONTRACT calls tracker-jira.sh contract-read and
  # ONLY that, never curl itself. Built once, reused by every leg below; logs reset per leg. The
  # fake adapter's body and the confs below are FIXTURE FILES (conformance/fixtures/tracker-jira/,
  # outside conformance-mass-budget.sh's scope — its own header, ~L18 — same convention as
  # proportional-gate-wired.sh's fixture confs) so the SELFTEST TEXT stays out of the ratchet. ===
  fxdir="$_TC_ROOT/conformance/fixtures/tracker-jira"
  fadir="$tmpd/fa"; mkdir -p "$fadir/conformance" "$fadir/scripts"
  cp "$_TC_ROOT/conformance/tracker-contract.sh" "$fadir/conformance/tracker-contract.sh"
  cp "$_TC_ROOT/scripts/tracker-conf.sh" "$fadir/scripts/tracker-conf.sh"
  cp "$fxdir/contract-fake-adapter.sh" "$fadir/scripts/tracker-jira.sh"
  chmod +x "$fadir/scripts/tracker-jira.sh"
  faargv="$fadir/argv.log"; faenv="$fadir/env.log"; fainvoked="$fadir/invoked"; farc="$fadir/rc"
  fastatusbody="$fadir/status-body"
  # FA_* are read by the fixture adapter itself (fixed paths under this leg's own $tmpd); exported
  # once, for the whole selftest run.
  FA_ARGVLOG=$faargv; FA_ENVLOG=$faenv; FA_INVOKED=$fainvoked; FA_RC=$farc; FA_STATUSBODY=$fastatusbody; FA_FXDIR=$fxdir
  export FA_ARGVLOG FA_ENVLOG FA_INVOKED FA_RC FA_STATUSBODY FA_FXDIR
  fa_reset() { : > "$faargv"; : > "$faenv"; rm -f "$fainvoked" "$farc" "$fastatusbody"; }

  # _fa_run <conf> <tag> [contract-args…] (S-4 / redundancy fold): the repeated run+record-rc
  # block shared by F7, rc -> FAIL, --discover and H-1 (and the new S-4a leg below) — invokes the
  # fake tree's contract with <conf> and any extra args, capturing stdout/stderr/rc under
  # $tmpd/<tag>-{out,err,rc}. fa_reset (and any per-leg log/farc/fastatusbody setup) stays the
  # CALLER's job, done before wrapping its OWN subshell around the call so its env exports stay
  # scoped to that one call only.
  _fa_run() {
    _far_conf=$1; _far_tag=$2; shift 2
    if sh "$fadir/conformance/tracker-contract.sh" --conf "$_far_conf" "$@" >"$tmpd/${_far_tag}-out" 2>"$tmpd/${_far_tag}-err"; then
      echo 0 > "$tmpd/${_far_tag}-rc"
    else
      echo $? > "$tmpd/${_far_tag}-rc"
    fi
  }

  f7conf="$fxdir/contract-conf-basic.conf"

  # --- S-4(a): the fake tree's contract, given an http:// conf + creds -> rc 1, the exact
  # tracker-conf.sh grammar-refusal sentence, and the fake adapter NEVER invoked — exercises the
  # CONTRACT itself (not tracker-conf.sh alone), still through the REAL scripts/tracker-conf.sh
  # copied into the fake tree (F4 never re-parses the grammar here either). ---
  bc="$tmpd/bad.conf"; cat > "$bc" <<'EOF'
version=1
backend=jira
base_url=http://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
EOF
  fa_reset
  ( unset JIRA_EMAIL JIRA_TOKEN 2>/dev/null
    KIT_TRACKER_USER="s4a-user@example.com"; KIT_TRACKER_TOKEN="s4a-tok"
    export KIT_TRACKER_USER KIT_TRACKER_TOKEN
    _fa_run "$bc" s4a
  )
  s4arc=$(cat "$tmpd/s4a-rc" 2>/dev/null || printf '?')
  s4aout=$(cat "$tmpd/s4a-out" 2>/dev/null || true)
  s4aerr=$(cat "$tmpd/s4a-err" 2>/dev/null || true)
  if [ "$s4arc" = "1" ] && printf '%s%s' "$s4aout" "$s4aerr" | grep -qF "does not satisfy the tracker-conf grammar" \
     && [ ! -f "$fainvoked" ]; then
    echo "PASS: selftest — the contract refuses an http:// conf via tracker-conf.sh, rc 1, and never invokes the adapter (S-4a / F4)"
  else
    echo "FAIL: selftest — S-4a: rc=$s4arc out='$s4aout' err='$s4aerr' invoked=$([ -f "$fainvoked" ] && echo yes || echo no)"; sfail=1
  fi

  # --- S-4(b) DRY: the contract reads the conf THROUGH tracker-conf.sh, never re-parsing — a
  # logging wrapper (fixture contract-conf-logger.sh) stands in for scripts/tracker-conf.sh in a
  # SECOND fake tree, execs the REAL parser copied beside it, and records every call; the
  # contract must call it with 'get base_url'. ---
  fadir2="$tmpd/fa2"; mkdir -p "$fadir2/conformance" "$fadir2/scripts"
  cp "$_TC_ROOT/conformance/tracker-contract.sh" "$fadir2/conformance/tracker-contract.sh"
  cp "$_TC_ROOT/scripts/tracker-conf.sh" "$fadir2/scripts/tracker-conf.sh.real"
  cp "$fxdir/contract-conf-logger.sh" "$fadir2/scripts/tracker-conf.sh"
  cp "$fxdir/contract-fake-adapter.sh" "$fadir2/scripts/tracker-jira.sh"
  chmod +x "$fadir2/scripts/tracker-conf.sh" "$fadir2/scripts/tracker-jira.sh"
  faconflog="$tmpd/conf.log"; : > "$faconflog"
  FA_CONFLOG=$faconflog; export FA_CONFLOG
  fa_reset
  ( unset JIRA_EMAIL JIRA_TOKEN 2>/dev/null
    KIT_TRACKER_USER="s4b-user@example.com"; KIT_TRACKER_TOKEN="s4b-tok"
    export KIT_TRACKER_USER KIT_TRACKER_TOKEN
    sh "$fadir2/conformance/tracker-contract.sh" --conf "$f7conf" >/dev/null 2>&1 || true
  )
  if grep -qF "get base_url" "$faconflog" 2>/dev/null; then
    echo "PASS: selftest — the contract reads base_url THROUGH tracker-conf.sh, calling it with 'get base_url' (S-4b / F4, DRY)"
  else
    echo "FAIL: selftest — the contract did not call tracker-conf.sh with 'get base_url': $(cat "$faconflog" 2>/dev/null)"; sfail=1
  fi

  # --- F7/T5/I-1 (rework, folded): the contract calls the adapter for status then field, with
  # ONLY KIT_TRACKER_USER/KIT_TRACKER_TOKEN set and JIRA_* unset (I-1 folded here — this setup IS
  # I-1's own precondition, asserted explicitly below); the token stays off argv and reaches the
  # adapter only via env; _TJ_CURL_BIN is unset in the call-through subshell ---
  fa_reset
  ( unset JIRA_EMAIL JIRA_TOKEN 2>/dev/null
    KIT_TRACKER_USER="fa-user@example.com"; KIT_TRACKER_TOKEN="fa-s3cret-tok"
    export KIT_TRACKER_USER KIT_TRACKER_TOKEN
    # S-1/T3b-Q1: poison _TJ_CURL_BIN in THIS subshell's own environment before invoking the
    # contract — the fake's env.log must still show "unset", proving the call-through's own
    # `unset _TJ_CURL_BIN` actively scrubs a leaked value, not merely that none was ever set.
    _TJ_CURL_BIN=/nonexistent/canary; export _TJ_CURL_BIN
    if sh "$fadir/conformance/tracker-contract.sh" --conf "$f7conf" >"$tmpd/f7-out" 2>"$tmpd/f7-err"; then _f7rc=0; else _f7rc=$?; fi
    echo "$_f7rc" > "$tmpd/f7-rc"
  )
  f7rc=$(cat "$tmpd/f7-rc" 2>/dev/null || printf '?')
  f7out=$(cat "$tmpd/f7-out" 2>/dev/null || true)
  f7argv=$(cat "$faargv" 2>/dev/null || true)
  f7env=$(cat "$faenv" 2>/dev/null || true)
  f7line1=$(printf '%s\n' "$f7argv" | sed -n '1p')
  f7line2=$(printf '%s\n' "$f7argv" | sed -n '2p')
  if [ "$f7rc" = "0" ] && printf '%s' "$f7out" | grep -q "OK: Jira satisfies the §6 contract" \
     && [ "$f7line1" = "contract-read https://ex.atlassian.net cloud status" ] \
     && [ "$f7line2" = "contract-read https://ex.atlassian.net cloud field" ] \
     && ! printf '%s' "$f7argv" | grep -Fq "fa-s3cret-tok" \
     && printf '%s' "$f7env" | grep -Fq "fa-s3cret-tok" \
     && printf '%s' "$f7env" | grep -q "_TJ_CURL_BIN=unset" \
     && printf '%s' "$f7env" | grep -q "JIRA_EMAIL= JIRA_TOKEN="; then
    echo "PASS: selftest — the contract calls the adapter (contract-read) for status then field with ONLY KIT_TRACKER_USER/KIT_TRACKER_TOKEN set and JIRA_* unset (I-1); the token stays off argv, reaches the adapter only via env, and _TJ_CURL_BIN is unset in the call-through (F7/T5/I-1, T3b)"
  else
    echo "FAIL: selftest — F7/T5/I-1 rework: rc=$f7rc out='$f7out' argv='$f7argv' env='$f7env'"; sfail=1
  fi

  # --- TRACKER-CONTRACT-HONEST-TIER: --deep grades THIS project's own workflows, through the adapter's project-
  # scoped reads (recorded adapter output, proven byte-for-byte by tracker-jira.sh --selftest). One row per leg:
  # name:conf:project:statuses:workflow:wf-rc:myself-rc:want-rc:want-project-workflows-reads:want-text. Whole-output
  # oracles on EVERY row: "incl. the verified Only-Assignee claim" appears iff PASS; no site-wide read is ever asked. ---
  for _dl in "team-managed:basic:team:team:team:::0:1:TIER: convention — Jira's UI offers no Only-Assignee restriction on a team-managed project, so AB is on the convention tier; --deep grades what the workflow actually carries" \
             "team-enforced:basic:team:team:team-enforced:::0:1:PASS: deep — server-enforced claim (Only-Assignee on every transition into In Progress in 1 workflow(s))" \
             "company-enforced:basic:company:company:builds:::0:1:PASS: deep — server-enforced claim (Only-Assignee on every transition into In Progress in 1 workflow(s))" \
             "company-any:basic:company:company:any:::1:1:FAIL: deep — convention tier: transition 'Start Progress' into In Progress in workflow 'Builds Workflow'" \
             "company-extra-allowance:basic:company:company:extra:::1:1:FAIL: deep — convention tier: transition 'Start Progress' into In Progress in workflow 'Builds Workflow'" \
             "company-missing:basic:company:company:missing:::1:1:FAIL: deep — convention tier: transition 'Start Progress' into In Progress in workflow 'Builds Workflow'" \
             "company-one-of-two:basic:company:company:one-of-two:::1:1:FAIL: deep — convention tier: transition 'Start Progress' into In Progress in workflow 'Second Workflow'" \
             "global-unconditioned:basic:company:company:global:::1:1:FAIL: deep — convention tier: transition 'Anyone Start' into In Progress in workflow 'Builds Workflow'" \
             "no-permission:basic:company:company:builds:4:0:2:1:UNVERIFIED: deep — the token cannot read this project's workflows (Administer Jira is required for company-managed workflows); the tier is attested, not proven" \
             "no-credential:basic:company:company:builds:4:4:2:1:UNVERIFIED: deep — the credential was rejected by Jira" \
             "no-check:basic:company:company:builds:4:2:2:1:UNVERIFIED: deep — could not check the credential" \
             "missing-workflow:basic:company:company:builds:2::2:1:UNVERIFIED: deep — the project's workflows could not be read" \
             "dc:dc:team:team:team:::2:0:UNVERIFIED: deep — Data Center exposes no REST read of workflow transition conditions; the tier is attested, not proven" \
             "in-progress-unknown:doing:company:company:builds:::1:0:FAIL: deep — the conf's state.in-progress 'Doing' is not a status of AB"; do
    _dln=${_dl%%:*}; _dl=${_dl#*:}; _dlc=${_dl%%:*}; _dl=${_dl#*:}; _dlp=${_dl%%:*}; _dl=${_dl#*:}
    _dls=${_dl%%:*}; _dl=${_dl#*:}; _dlw=${_dl%%:*}; _dl=${_dl#*:}; _dlwr=${_dl%%:*}; _dl=${_dl#*:}
    _dlmr=${_dl%%:*}; _dl=${_dl#*:}; _dlrc=${_dl%%:*}; _dl=${_dl#*:}; _dlrd=${_dl%%:*}; _dlt=${_dl#*:}
    fa_reset
    ( unset JIRA_EMAIL JIRA_TOKEN 2>/dev/null
      KIT_TRACKER_USER="deep-user@example.com"; KIT_TRACKER_TOKEN="deep-tok"
      FA_PROJECT="$fxdir/contract-project-$_dlp.txt"; FA_PSTATUSES="$fxdir/contract-pstatuses-$_dls.txt"; FA_WF="$fxdir/contract-wf-$_dlw.txt"
      FA_WF_RC=$_dlwr; FA_MYSELF_RC=$_dlmr; FA_SITEWIDE="$fxdir/contract-wf-builds.txt"
      export KIT_TRACKER_USER KIT_TRACKER_TOKEN FA_PROJECT FA_PSTATUSES FA_WF FA_WF_RC FA_MYSELF_RC FA_SITEWIDE
      _fa_run "$fxdir/contract-conf-$_dlc.conf" "deep-$_dln" --deep
    )
    _dlgot=$(cat "$tmpd/deep-$_dln-rc" 2>/dev/null || printf '?'); _dlout=$(cat "$tmpd/deep-$_dln-out" 2>/dev/null || true)
    _dlreads=$(grep -c ' project-workflows ' "$faargv" || true)
    _dlsum=0; printf '%s' "$_dlout" | grep -q 'incl. the verified Only-Assignee claim' && _dlsum=1
    _dlpass=0; printf '%s' "$_dlout" | grep -q 'PASS: deep' && _dlpass=1
    if [ "$_dlgot" = "$_dlrc" ] && [ "$_dlreads" = "$_dlrd" ] && printf '%s' "$_dlout" | grep -qF "$_dlt" \
       && [ "$_dlsum" = "$_dlpass" ] && ! grep -q ' workflow$' "$faargv"; then
      echo "PASS: selftest — deep/$_dln: rc $_dlrc, $_dlrd project-workflows read(s), the contract text carries the tier verdict, the verified claim only on PASS, no site-wide read"
    else
      echo "FAIL: selftest — deep/$_dln: rc=$_dlgot want $_dlrc, reads=$_dlreads want $_dlrd, verified-summary=$_dlsum pass=$_dlpass out='$_dlout'"; sfail=1
    fi
    case $_dln in
      team-managed) grep -qx 'contract-read https://ex.atlassian.net cloud project-workflows 10000 10001 10002 10003 10004' "$faargv" \
        && grep -qx 'contract-read https://ex.atlassian.net cloud project AB' "$faargv" \
        || { echo "FAIL: selftest — deep/team-managed: the reads asked were not project, project-statuses, then project-workflows for every issue type: $(cat "$faargv")"; sfail=1; } ;;
      company-one-of-two) ! printf '%s' "$_dlout" | grep -qF "workflow 'Builds Workflow'" \
        || { echo "FAIL: selftest — deep/company-one-of-two: named the ENFORCED workflow too: $_dlout"; sfail=1; } ;;
    esac
  done
  # deep/site-wide-ignored (the cold-test regression): the fake offers a site-wide ENFORCED workflow beside a
  # team-managed project whose own workflow is unconditioned; only the project's own read is graded -> never a PASS.
  fa_reset
  ( unset JIRA_EMAIL JIRA_TOKEN 2>/dev/null
    KIT_TRACKER_USER="deep-user@example.com"; KIT_TRACKER_TOKEN="deep-tok"; FA_SITEWIDE="$fxdir/contract-wf-builds.txt"
    export KIT_TRACKER_USER KIT_TRACKER_TOKEN FA_SITEWIDE
    _fa_run "$f7conf" sitewide --deep
  )
  if grep -q 'TIER: convention' "$tmpd/sitewide-out" && ! grep -q 'PASS: deep' "$tmpd/sitewide-out" && ! grep -q ' workflow$' "$faargv" \
     && grep -q ' project-workflows ' "$faargv"; then
    echo "PASS: selftest — deep/site-wide-ignored: a site-wide enforced workflow cannot turn a team-managed project's own unconditioned workflow into a PASS"
  else
    echo "FAIL: selftest — deep/site-wide-ignored: $(cat "$tmpd/sitewide-out" 2>/dev/null) argv=$(cat "$faargv")"; sfail=1
  fi

  # --- SD-3 (new): KIT_TRACKER_AUTH comes from the CONF, never the ambient environment ----------
  sd3conf_b="$fxdir/contract-conf-basic.conf"
  sd3conf_noauth="$fxdir/contract-conf-noauth.conf"
  _sd3_run() {
    fa_reset
    ( KIT_TRACKER_AUTH=bearer; KIT_TRACKER_USER="sd3-user@example.com"; KIT_TRACKER_TOKEN="sd3-tok"
      export KIT_TRACKER_AUTH KIT_TRACKER_USER KIT_TRACKER_TOKEN
      sh "$fadir/conformance/tracker-contract.sh" --conf "$1" >/dev/null 2>&1 || true
    )
    cat "$faenv" 2>/dev/null || true
  }
  sd3a_env=$(_sd3_run "$sd3conf_b")
  sd3b_env=$(_sd3_run "$sd3conf_noauth")
  if printf '%s' "$sd3a_env" | grep -q "KIT_TRACKER_AUTH=basic"; then
    echo "PASS: selftest — SD-3(a): a conf pinning auth=basic wins over an ambient KIT_TRACKER_AUTH=bearer"
  else
    echo "FAIL: selftest — SD-3(a): expected KIT_TRACKER_AUTH=basic in env.log, got '$sd3a_env'"; sfail=1
  fi
  if printf '%s' "$sd3b_env" | grep -q "KIT_TRACKER_AUTH=basic"; then
    echo "PASS: selftest — SD-3(b): a conf with no auth= line defaults to basic, ignoring an ambient KIT_TRACKER_AUTH=bearer"
  else
    echo "FAIL: selftest — SD-3(b): expected KIT_TRACKER_AUTH=basic in env.log, got '$sd3b_env'"; sfail=1
  fi
  # RED note (trimmed, mass fold): the load-bearing mutant is the conf-derived ASSIGNMENT, not the
  # bare `export` keyword (POSIX export stays sticky across a plain reassignment — equivalent).

  # --- SD-3 pin-export (new): NO ambient KIT_TRACKER_AUTH at all, conf auth=bearer -> the adapter
  # sees bearer. This is the ONE case where the production `export KIT_TRACKER_AUTH` line is itself
  # load-bearing (no prior ambient export exists to keep the attribute sticky): removing the export
  # keyword here strands the value as a LOCAL shell variable, invisible to the child. -------------
  sd3conf_bearer="$fxdir/contract-conf-bearer.conf"
  fa_reset
  ( unset KIT_TRACKER_AUTH JIRA_EMAIL JIRA_TOKEN 2>/dev/null
    KIT_TRACKER_USER="pin-user@example.com"; KIT_TRACKER_TOKEN="pin-tok"
    export KIT_TRACKER_USER KIT_TRACKER_TOKEN
    sh "$fadir/conformance/tracker-contract.sh" --conf "$sd3conf_bearer" >/dev/null 2>&1 || true
  )
  sd3pin_env=$(cat "$faenv" 2>/dev/null || true)
  if printf '%s' "$sd3pin_env" | grep -q "KIT_TRACKER_AUTH=bearer"; then
    echo "PASS: selftest — SD-3 pin-export: with NO ambient KIT_TRACKER_AUTH, a conf pinning auth=bearer still reaches the adapter (the export line is load-bearing here)"
  else
    echo "FAIL: selftest — SD-3 pin-export: expected KIT_TRACKER_AUTH=bearer in env.log, got '$sd3pin_env'"; sfail=1
  fi

  # --- rc -> FAIL (new): the adapter exits non-zero -> contract rc 1, the exact FAIL sentence ---
  fa_reset; printf '2\n' > "$farc"
  ( unset JIRA_EMAIL JIRA_TOKEN 2>/dev/null
    KIT_TRACKER_USER="rc-user@example.com"; KIT_TRACKER_TOKEN="rc-tok"
    export KIT_TRACKER_USER KIT_TRACKER_TOKEN
    _fa_run "$f7conf" rcf
  )
  rcfrc=$(cat "$tmpd/rcf-rc" 2>/dev/null || printf '?')
  rcfout=$(cat "$tmpd/rcf-out" 2>/dev/null || true)
  if [ "$rcfrc" = "1" ] && printf '%s\n' "$rcfout" | grep -qF "FAIL: could not reach https://ex.atlassian.net/rest/api/3/status"; then
    echo "PASS: selftest — a non-zero adapter rc yields contract rc 1 and the exact FAIL sentence (rc -> FAIL)"
  else
    echo "FAIL: selftest — rc -> FAIL: rc=$rcfrc out='$rcfout'"; sfail=1
  fi

  # --- --discover: THIS project's statuses (project-statuses), one aligned `id<TAB>name` row each; the real body's
  # nested scope.project.id / statusCategory.id never become a row; the site-wide /status is never read. ---
  fa_reset
  ( unset JIRA_EMAIL JIRA_TOKEN 2>/dev/null
    KIT_TRACKER_USER="disc-user@example.com"; KIT_TRACKER_TOKEN="disc-tok"
    export KIT_TRACKER_USER KIT_TRACKER_TOKEN
    _fa_run "$f7conf" disc --discover
  )
  discrc=$(cat "$tmpd/disc-rc" 2>/dev/null || printf '?')
  if [ "$discrc" = "0" ] && cmp -s "$tmpd/disc-out" "$fxdir/contract-discover-expected.txt" \
     && [ "$(cat "$faargv")" = "contract-read https://ex.atlassian.net cloud project-statuses AB" ]; then
    echo "PASS: selftest — discover/team-managed: 10000 Backlog ... 10006 Blocked, aligned, from project-statuses only"
  else
    echo "FAIL: selftest — discover/team-managed: rc=$discrc out='$(cat "$tmpd/disc-out")' argv='$(cat "$faargv")'"; sfail=1
  fi
  if [ "$(awk -F'\t' 'NR > 1' "$tmpd/disc-out" | wc -l | tr -d ' ')" = 7 ] \
     && [ -z "$(awk -F'\t' 'NR > 1 && ($2 == "" || NF != 2 || $1 !~ /^1000[0-6]$/)' "$tmpd/disc-out")" ]; then
    echo "PASS: selftest — discover/nested-scope: exactly 7 rows, each a status id with its own name; no nested project/category id leaks"
  else
    echo "FAIL: selftest — discover/nested-scope: $(cat "$tmpd/disc-out")"; sfail=1
  fi

  # --- SD-2 H-1 (rework): no conf + ambient JIRA_BASE_URL=http://attacker... + creds -> rc 2 AND
  # the fake adapter is NEVER invoked (fa/invoked absent) -------------------------------------
  fa_reset
  ( unset JIRA_BASE_URL KIT_TRACKER_USER KIT_TRACKER_TOKEN JIRA_EMAIL JIRA_TOKEN 2>/dev/null
    JIRA_BASE_URL="http://attacker.example.invalid/"; JIRA_EMAIL="u"; JIRA_TOKEN="t"
    export JIRA_BASE_URL JIRA_EMAIL JIRA_TOKEN
    _fa_run "$tmpd/no-such.conf" h1
  )
  h1rc=$(cat "$tmpd/h1-rc" 2>/dev/null || printf '?')
  if [ "$h1rc" = "2" ] && [ ! -f "$fainvoked" ]; then
    echo "PASS: selftest — JIRA_BASE_URL with no conf UNVERIFIES (rc 2) and the adapter is never invoked (SD-2 H-1)"
  else
    echo "FAIL: selftest — SD-2 H-1: rc=$h1rc, invoked=$([ -f "$fainvoked" ] && echo yes || echo no), err=$(cat "$tmpd/h1-err" 2>/dev/null)"; sfail=1
  fi

  # --- SD-1 L-1 (rework, REAL adapter): a quote in the credential refuses BEFORE any connection,
  # even against an unreachable host — proven against the REAL tree, not the fake, since the
  # refusal itself lives in the real adapter's jira_curl_authed. -------------------------------
  # shellcheck disable=SC2089,SC2090  # the literal quote is DELIBERATE test data (an attempted
  # config-injection payload), not shell quoting to be respected — that is the whole point of L-1.
  ( BASE="https://127.0.0.1:9"; FLAVOUR="cloud"
    unset KIT_TRACKER_USER KIT_TRACKER_TOKEN KIT_TRACKER_AUTH 2>/dev/null
    JIRA_EMAIL='u"; url=https://evil.example.invalid'; JIRA_TOKEN='t'
    export JIRA_EMAIL JIRA_TOKEN
    rm -f "$tmpd/l1-out"
    if _tc_curl_authed status "$tmpd/l1-out"; then _l1rc=0; else _l1rc=$?; fi
    echo "$_l1rc" > "$tmpd/l1-rc"
  ) 2>"$tmpd/l1-err"
  l1rc=$(cat "$tmpd/l1-rc" 2>/dev/null || printf '?')
  l1err=$(cat "$tmpd/l1-err" 2>/dev/null || true)
  if [ "$l1rc" != "0" ] && printf '%s' "$l1err" | grep -qF "refused: credential (user) outside the allowed charset" \
     && [ ! -s "$tmpd/l1-out" ]; then
    echo "PASS: selftest — a quote in the credential refuses before any connection is attempted, even to an unreachable host (SD-1 L-1)"
  else
    echo "FAIL: selftest — SD-1 L-1: rc=$l1rc err='$l1err' out-size=$(wc -c < "$tmpd/l1-out" 2>/dev/null || echo '?')"; sfail=1
  fi

  # --- BOARD-CREATE-HONOURS-FIELD-MAP: --fields and the create-coherence leg, through the fake adapter's
  # create-meta op (recorded adapter output: the fixtures contract-createmeta-*.txt). One helper runs a conf
  # against a meta body; each leg then checks rc + the load-bearing text. The FAIL legs are the negatives:
  # with the coherence leg removed the contract would exit 0 on them. ---
  _cm_run() {  # <tag> <conf> <meta-fixture> <required-fields-fixture|-> [contract-args…]
    _cmr_tag=$1; _cmr_conf=$2; _cmr_meta=$3; _cmr_rf=$4; shift 4
    fa_reset
    ( unset JIRA_EMAIL JIRA_TOKEN 2>/dev/null
      KIT_TRACKER_USER="cm-user@example.com"; KIT_TRACKER_TOKEN="cm-tok"; FA_CMBODY="$fxdir/$_cmr_meta"
      FA_RFBODY=""; [ "$_cmr_rf" = "-" ] || FA_RFBODY="$fxdir/$_cmr_rf"
      FA_TFBODY="${_cmr_tf:-}"
      export KIT_TRACKER_USER KIT_TRACKER_TOKEN FA_CMBODY FA_RFBODY FA_TFBODY
      _fa_run "$_cmr_conf" "$_cmr_tag" "$@"
    )
    _cmr_rc=$(cat "$tmpd/$_cmr_tag-rc" 2>/dev/null || printf '?')
    _cmr_out=$(cat "$tmpd/$_cmr_tag-out" 2>/dev/null || true)
  }
  _cm_run flds "$f7conf" contract-createmeta-all.txt contract-rf-golden.txt --fields
  if [ "$_cmr_rc" = "0" ] && cmp -s "$tmpd/flds-out" "$fxdir/contract-fields-expected.txt"; then
    echo "PASS: selftest — fields/expected: --fields prints each non-subtask type's Size/Risk ids and the conf lines to paste, exactly the recorded text"
  else
    echo "FAIL: selftest — fields/expected: rc=$_cmr_rc out='$_cmr_out'"; sfail=1
  fi
  # R2 load-bearing negative: no id is BOTH in the field.size/field.risk paste and in a create.<id>=<value> paste
  _r2f=$(sed -n 's/^field\.[a-z]*=//p' "$tmpd/flds-out"); _r2c=$(sed -n 's/^create\.\(.*\)=<value>$/\1/p' "$tmpd/flds-out"); _r2bad=0
  for _r2id in $_r2f; do printf '%s\n' "$_r2c" | grep -qxF "$_r2id" && _r2bad=1; done
  if [ "$_r2bad" = 0 ] && [ -n "$_r2f" ] && [ -n "$_r2c" ]; then
    echo "PASS: selftest — fields/no-double-paste: an id suggested as field.size/field.risk is never also pasted as create.<id>"
  else
    echo "FAIL: selftest — fields/no-double-paste: field='$_r2f' create='$_r2c'"; sfail=1
  fi
  # --fields --issue: the card's transitions' required screen fields, through the adapter's transition-fields op
  _cmr_tf="$fxdir/contract-tf-issue.txt"
  _cm_run fldsi "$f7conf" contract-createmeta-all.txt contract-rf-golden.txt --fields --issue AB-1
  if [ "$_cmr_rc" = "0" ] && cmp -s "$tmpd/fldsi-out" "$fxdir/contract-fields-issue-expected.txt" \
     && grep -q '^transition-fields https://ex.atlassian.net cloud AB-1$' "$faargv"; then
    echo "PASS: selftest — fields/issue: --fields --issue lists each available transition's required screen fields (required-by transition-to-<state>), exactly the recorded text"
  else
    echo "FAIL: selftest — fields/issue: rc=$_cmr_rc out='$_cmr_out'"; sfail=1
  fi
  _cmr_tf="$tmpd/absent-tf.txt"
  _cm_run fldsx "$f7conf" contract-createmeta-all.txt contract-rf-golden.txt --fields --issue AB-1
  if [ "$_cmr_rc" = "1" ] && printf '%s' "$_cmr_out" | grep -qF "FAIL: could not read the transitions of AB-1" \
     && ! printf '%s' "$_cmr_out" | grep -qF "transition-to-"; then
    echo "PASS: selftest — fields/issue-unreadable: an adapter failure is a FAIL (rc 1), never a silent pass"
  else
    echo "FAIL: selftest — fields/issue-unreadable: rc=$_cmr_rc out='$_cmr_out'"; sfail=1
  fi
  _cmr_tf=""
  # TRACKER-REQUIRED-FIELDS-DISCOVERY rows (the `req-` ones) add the required-fields fixture (field 4, `-` = none:
  # a type that requires nothing). Every row also proves the allowed values (the ZQALLOWED tokens in the fixtures)
  # NEVER reach the no-flag output (S-6, design §15e); the --fields golden above is the positive anchor that
  # the same tokens DO print there.
  for _coh in "ok:coh-ok:all:-:0:OK: Jira satisfies" \
              "label-vs-select:coh-label:all:-:1:field.size=customfield_10046" \
              "wrong-type:coh-wrongtype:all:-:1:field.size=customfield_10043" \
              "schema-number:coh-number:all:-:1:schema type 'number'" \
              "label-no-select:coh-label:plain:-:0:OK: Jira satisfies" \
              "req-unmapped:coh-ok:all:contract-rf-team.txt:1:create.customfield_10070=<value>" \
              "req-covered:req-default:all:contract-rf-team.txt:0:covered by field.size" \
              "req-default:req-default:all:contract-rf-team.txt:0:set by create.customfield_10070" \
              "req-prompt:req-prompt:all:contract-rf-team.txt:0:(prompt: the agent supplies it per card)" \
              "req-unsupported:coh-ok:all:contract-rf-unsupported.txt:1:cannot fill" \
              "req-nowrite:coh-ok:all:contract-rf-nowrite.txt:1:writable create keys" \
              "req-badkey:req-badkey:all:contract-rf-team.txt:1:create.assignee is not a writable create key" \
              "req-early:basic:all:contract-rf-team.txt:1:create.customfield_10070=<value>" \
              "req-unreadable:coh-ok:all:contract-rf-absent.txt:1:could not read the required fields" \
              "req-flag:coh-ok:all:contract-rf-flag.txt:0:filled per card by board create --parent" \
              "req-dropped:coh-ok:all:contract-rf-dropped.txt:1:the tracker reported 1 required field(s) the kit cannot name" \
              "req-badcf:req-badcf:all:contract-rf-team.txt:1:create.customfield_1x is not a writable create key"; do
    _cohname=${_coh%%:*}; _coh=${_coh#*:}; _cohconf=${_coh%%:*}; _coh=${_coh#*:}
    _cohmeta=${_coh%%:*}; _coh=${_coh#*:}; _cohrf=${_coh%%:*}; _coh=${_coh#*:}
    _cohrc=${_coh%%:*}; _cohwant=${_coh#*:}
    _cm_run "coh-$_cohname" "$fxdir/contract-conf-$_cohconf.conf" "contract-createmeta-$_cohmeta.txt" "$_cohrf"
    _cohcm=0; [ "$_cohconf" = basic ] || grep -q '^create-meta https://ex.atlassian.net cloud AB ' "$faargv" || _cohcm=1
    if [ "$_cmr_rc" = "$_cohrc" ] && printf '%s' "$_cmr_out" | grep -qF "$_cohwant" && [ "$_cohcm" = 0 ] \
       && grep -q '^required-fields https://ex.atlassian.net cloud AB ' "$faargv" \
       && ! printf '%s' "$_cmr_out" | grep -qF ZQALLOWED; then
      echo "PASS: selftest — coherence/$_cohname: rc $_cohrc and the contract text carries '$_cohwant' (required-fields was asked; no allowed value printed)"
    else
      echo "FAIL: selftest — coherence/$_cohname: rc=$_cmr_rc want $_cohrc out='$_cmr_out'"; sfail=1
    fi
  done
  # R1 negative: a required description/parent is flag-filled - the contract never tells the adopter to add a create. line for them
  _cm_run cohflag "$fxdir/contract-conf-coh-ok.conf" contract-createmeta-all.txt contract-rf-flag.txt
  if [ "$_cmr_rc" = 0 ] && ! printf '%s' "$_cmr_out" | grep -qF -e 'create.description' -e 'create.parent' && printf '%s' "$_cmr_out" | grep -qF 'filled per card by board create --description'; then
    echo "PASS: selftest — coherence/req-flag-negative: a required description/parent never gets a create. cure"
  else
    echo "FAIL: selftest — coherence/req-flag-negative: rc=$_cmr_rc out='$_cmr_out'"; sfail=1
  fi
  # R3: --fields shows the dropped sentinel too (a FAIL, rc 1), never hides it
  _cm_run fldsd "$f7conf" contract-createmeta-all.txt contract-rf-dropped.txt --fields
  if [ "$_cmr_rc" = 1 ] && printf '%s' "$_cmr_out" | grep -qF 'the tracker reported 1 required field(s) the kit cannot name'; then
    echo "PASS: selftest — fields/dropped: --fields shows the #dropped sentinel as a FAIL (rc 1)"
  else
    echo "FAIL: selftest — fields/dropped: rc=$_cmr_rc out='$_cmr_out'"; sfail=1
  fi

  # --- TRACKER-PREFLIGHT-TIER-CARD: --preflight prints the tier card, `name<TAB>verdict<TAB>text` per line (design
  # 2026-10-03 §4/§14; plan interfaces B/C/D). Every leg runs the fake-adapter tree: the card reads answer from
  # recorded adapter output (FA_PF_*), never a network. pf_* shell variables select the fixtures for ONE _pfr run. ---
  pf_probe=''; pf_server=''; pf_perms=''; pf_vis=''; pf_epic=''; pf_rf=''; pf_proj=''; pf_pst=''; pf_wf=''; pf_wfrc=''; pf_myrc=''
  pf_proberc=''; pf_permsrc=''; pf_epicrc=''; pf_serverrc=''; pf_nocreds=0
  _pfr() {  # <tag> [contract-args…]: one run of the fake tree's contract; result in _pfrc/_pfout, files $tmpd/<tag>-*
    _pft=$1; shift; fa_reset
    ( unset JIRA_EMAIL JIRA_TOKEN KIT_TRACKER_USER KIT_TRACKER_TOKEN 2>/dev/null
      if [ "$pf_nocreds" -eq 0 ]; then KIT_TRACKER_USER="pf-user@example.com"; KIT_TRACKER_TOKEN="pf-s3cret-tok"; export KIT_TRACKER_USER KIT_TRACKER_TOKEN; fi
      [ -z "$pf_probe" ] || FA_PF_PROBE="$fxdir/contract-pf-$pf_probe.txt"
      [ -z "$pf_server" ] || FA_PF_SERVER="$fxdir/contract-pf-server-$pf_server.txt"
      [ -z "$pf_perms" ] || FA_PF_PERMS="$fxdir/contract-pf-perms-$pf_perms.txt"
      [ -z "$pf_vis" ] || FA_PF_VIS="$fxdir/contract-pf-vis-$pf_vis.txt"
      [ -z "$pf_epic" ] || FA_PF_EPIC="$fxdir/contract-pf-epic-$pf_epic.txt"
      [ -z "$pf_rf" ] || FA_RFBODY="$fxdir/$pf_rf"
      [ -z "$pf_proj" ] || FA_PROJECT="$fxdir/contract-project-$pf_proj.txt"
      [ -z "$pf_pst" ] || FA_PSTATUSES="$fxdir/contract-pstatuses-$pf_pst.txt"
      [ -z "$pf_wf" ] || FA_WF="$fxdir/contract-wf-$pf_wf.txt"
      [ -z "$pf_wfrc" ] || FA_WF_RC=$pf_wfrc
      [ -z "$pf_myrc" ] || FA_MYSELF_RC=$pf_myrc
      [ -z "$pf_proberc" ] || FA_PF_PROBE_RC=$pf_proberc
      [ -z "$pf_permsrc" ] || FA_PF_PERMS_RC=$pf_permsrc
      [ -z "$pf_epicrc" ] || FA_PF_EPIC_RC=$pf_epicrc
      [ -z "$pf_serverrc" ] || FA_PF_SERVER_RC=$pf_serverrc
      export FA_PF_PROBE FA_PF_SERVER FA_PF_PERMS FA_PF_VIS FA_PF_EPIC FA_RFBODY FA_PROJECT FA_PSTATUSES FA_WF FA_WF_RC FA_MYSELF_RC FA_PF_PROBE_RC FA_PF_PERMS_RC FA_PF_EPIC_RC FA_PF_SERVER_RC
      if sh "$fadir/conformance/tracker-contract.sh" "$@" >"$tmpd/$_pft-out" 2>"$tmpd/$_pft-err"; then echo 0 > "$tmpd/$_pft-rc"; else echo $? > "$tmpd/$_pft-rc"; fi
    )
    _pfrc=$(cat "$tmpd/$_pft-rc" 2>/dev/null || printf '?'); _pfout=$(cat "$tmpd/$_pft-out" 2>/dev/null || true)
    pf_probe=''; pf_server=''; pf_perms=''; pf_vis=''; pf_epic=''; pf_rf=''; pf_proj=''; pf_pst=''; pf_wf=''; pf_wfrc=''; pf_myrc=''
    pf_proberc=''; pf_permsrc=''; pf_epicrc=''; pf_serverrc=''; pf_nocreds=0
  }
  # oracles over the last run: _pfl name verdict fragment (a card line) · _pfa name (no such line) · _pfok rc
  _pfl() { awk -F'\t' -v n="$1" -v v="$2" -v t="$3" '$1 == n && $2 == v && index($3, t) > 0 { f = 1 } END { exit !f }' "$tmpd/$_pft-out"; }
  _pfa() { ! awk -F'\t' -v n="$1" '$1 == n { f = 1 } END { exit !f }' "$tmpd/$_pft-out"; }
  _pfok() { [ "$_pfrc" = "$1" ]; }
  _pfn() { [ "$(awk -F'\t' -v n="$1" '$1 == n' "$tmpd/$_pft-out" | wc -l | tr -d ' ')" = "$2" ]; }
  _pffirst() { [ "$(sed -n 1p "$tmpd/$_pft-out")" = "$1" ]; }
  _pflast() { [ "$(sed -n '$p' "$tmpd/$_pft-out" | cut -f1)" = "$1" ]; }
  _pforder() { [ "$(cut -f1 "$tmpd/$_pft-out" | tr '\n' ' ')" = "$1" ]; }
  _pfgram() { awk -F'\t' 'NF != 3 || $1 == "" || $3 == "" || index(" PASS FAIL TIER INFO ASK UNVERIFIED ", " " $2 " ") == 0 { bad = 1 } END { exit bad }' "$tmpd/$_pft-out"; }
  _pfargv() {
    _pfa_got=$(awk '$1 == "contract-read" { printf "%s ", $4; next } { printf "%s ", $1 }' "$faargv" | sed 's/ $//')
    [ "$_pfa_got" = "$1" ] || { echo "ARGV-GOT: $_pfa_got"; return 1; }
  }
  _pfhas() { grep -qF -e "$1" "$tmpd/$_pft-out"; }
  _pfnot() { ! grep -qF -e "$1" "$tmpd/$_pft-out" "$tmpd/$_pft-err"; }
  _pfcalls() { [ "$(wc -l < "$faargv" | tr -d ' ')" = "$1" ]; }
  _pfsilent() { [ ! -s "$faargv" ] && [ ! -f "$fainvoked" ]; }
  _pfrefused() { [ "$_pfrc" = 2 ] && _pfsilent; }
  _pfv() {  # <label> <oracle…>
    _pfvl=$1; shift
    if "$@"; then echo "PASS: selftest — preflight/$_pfvl"; else echo "FAIL: selftest — preflight/$_pfvl: rc=$_pfrc out='$_pfout'"; sfail=1; fi
  }
  _pf_ph=$(printf '%s → %s → %s' 'Actions' 'Adopter Tracker Gates' 'Run workflow'); _pf_tk=$(printf '%s_%s' KIT_TRACKER RUNNER)
  _pf_tab=$_TC_TAB
  # the all-good card (dev, conf mode, team-managed): every line, in order, grammar, rc 0, the token never printed
  _pfr pfhappy --preflight --conf "$f7conf"
  _pfv happy/rc _pfok 0
  _pfv happy/header-first _pffirst "card${_pf_tab}INFO${_pf_tab}ex.atlassian.net · project AB · as dev · read-only"
  _pfv happy/order _pforder "card deployment reach-here reach-ci auth token-expiry project permissions claim-tier required epic-model visibility automation CARD "
  _pfv happy/grammar _pfgram
  _pfv happy/deployment _pfl deployment PASS "Cloud (build 100294)"
  _pfv happy/reach-here _pfl reach-here PASS "the API answers from this machine (direct)"
  _pfv happy/reach-ci _pfl reach-ci INFO "$_pf_ph"
  _pfv happy/auth _pfl auth PASS "the site accepted the credential (basic auth, site URL)"
  _pfv happy/no-account-for-dev _pfa account
  _pfv happy/token-expiry _pfl token-expiry INFO "the API does not expose token expiry"
  _pfv happy/project _pfl project PASS "team-managed"
  _pfv happy/permissions _pfl permissions PASS "browse · create · transition · assign"
  _pfv happy/claim-tier _pfl claim-tier TIER "convention (team-managed: Jira offers no Only-Assignee condition; see --deep)"
  _pfv happy/required _pfl required PASS "0 required create fields unmapped"
  _pfv happy/epic-model _pfl epic-model PASS "parent"
  _pfv happy/visibility _pfl visibility PASS "16 of 16 issues visible; 0 issue-security levels"
  _pfv happy/automation _pfl automation ASK "automation rules are not readable without admin"
  _pfv happy/card _pfl CARD PASS "0 FAIL · 0 UNVERIFIED · run once with each credential (--as ci with the CI reader, --as dev with a developer's)"
  _pfv happy/card-last _pflast CARD
  _pfv happy/token-never-printed _pfnot pf-s3cret-tok
  _pfv happy/argv-closed-list _pfargv "probe server-info project perms writable-create-keys required-fields epic-model visibility"
  _pfv happy/probe-first [ "$(sed -n 1p "$faargv")" = "contract-read https://ex.atlassian.net cloud probe" ]
  # --- reach-here: unreachable / redirect stop the card with the cure; an error is UNVERIFIED and stops too ---
  pf_probe=probe-unreach; _pfr pfunreach --preflight --conf "$f7conf"
  _pfv unreachable/fail-with-runner-cure _pfl reach-here FAIL "the site did not answer from this machine (network, VPN, IP allowlist or an egress proxy: set HTTPS_PROXY); if CI cannot reach it either, set the repository variable $_pf_tk to a self-hosted runner label inside your network (JIRA-SETUP §0)"
  _pfv unreachable/stops _pfa auth
  _pfv unreachable/no-deployment-line _pfa deployment
  _pfv unreachable/header-still-first _pffirst "card${_pf_tab}INFO${_pf_tab}ex.atlassian.net · project AB · as dev · read-only"
  _pfv unreachable/card-last _pfl CARD FAIL "1 FAIL · 0 UNVERIFIED"
  _pfv unreachable/rc _pfok 1
  _pfv unreachable/one-adapter-call _pfcalls 1
  # --- reach-here names the route: via a proxy / direct; an absent or hostile `via` renders no parenthesis ---
  pf_probe=probe-via-proxy; _pfr pfviaproxy --preflight --conf "$f7conf"
  _pfv via/proxy _pfl reach-here PASS "the API answers from this machine (via a proxy)"
  _pfv via/proxy-order _pforder "card deployment reach-here reach-ci auth token-expiry project permissions claim-tier required epic-model visibility automation CARD "
  pf_probe=probe-proxy-refused; _pfr pfproxyrefused --preflight --conf "$f7conf"
  _pfv proxy-refused/fail _pfl reach-here FAIL "HTTPS_PROXY or NO_PROXY carries a value the adapter refuses (letters, digits and : / @ . _ % + - only; percent-encode a proxy password's other characters)"
  _pfv proxy-refused/stops _pfa auth
  _pfv proxy-refused/no-deployment-line _pfa deployment
  _pfv proxy-refused/rc _pfok 1
  _pfv proxy-refused/card-last _pfl CARD FAIL "1 FAIL · 0 UNVERIFIED"
  pf_probe=probe-via-absent; _pfr pfviaabsent --preflight --conf "$f7conf"
  _pfv via/absent-no-parenthesis _pfl reach-here PASS "the API answers from this machine"
  _pfv via/absent-no-parenthesis-negative _pfnot "answers from this machine ("
  pf_probe=probe-via-hostile; _pfr pfviahostile --preflight --conf "$f7conf"
  _pfv via/hostile-no-parenthesis _pfnot "answers from this machine ("
  _pfv via/hostile-never-echoed _pfnot ZQHOSTILE
  _pfv via/hostile-still-passes _pfl reach-here PASS "the API answers from this machine"
  pf_probe=probe-redirect; _pfr pfredirect --preflight --conf "$f7conf"
  _pfv redirect/fail _pfl reach-here FAIL "the site redirected (an SSO or proxy interstitial); point base_url at the site itself"
  _pfv redirect/stops _pfa auth
  pf_probe=probe-error; _pfr pferror --preflight --conf "$f7conf"
  _pfv error/unverified-stops _pfl reach-here UNVERIFIED "retry later"
  _pfv error/rc _pfok 2
  _pfv error/stops _pfa auth
  pf_proberc=2; _pfr pfproberc --preflight --conf "$f7conf"
  _pfv probe-unreadable/unverified _pfl reach-here UNVERIFIED "could not be read"
  _pfv probe-unreadable/rc _pfok 2
  # --- auth: 401 / 403 FAIL and stop; a hostile enum is UNVERIFIED and never echoed (S-6) ---
  pf_probe=probe-401; _pfr pf401 --preflight --conf "$f7conf"
  _pfv auth-401/fail _pfl auth FAIL "the site refused the credential: a wrong or revoked token, or a scoped token the kit does not route yet (see JIRA-SETUP §5)"
  _pfv auth-401/stops _pfa project
  _pfv auth-401/reach-before _pfl reach-here PASS ""
  _pfv auth-401/rc _pfok 1
  _pfv auth-401/deployment-info _pfl deployment INFO "not readable until the site accepts the credential"
  pf_probe=probe-401; pf_serverrc=2; _pfr pf401srv --preflight --conf "$f7conf"
  _pfv auth-401/deployment-info-server-failing _pfl deployment INFO "not readable until the site accepts the credential"
  _pfv auth-401/no-server-info-read [ "$(grep -c server-info "$faargv" || true)" = 0 ]
  _pfv auth-401/card-one-fail-zero-unverified _pfl CARD FAIL "1 FAIL · 0 UNVERIFIED"
  _pfv auth-401/server-failing-rc1 _pfok 1
  pf_probe=probe-403; pf_serverrc=2; _pfr pf403srv --preflight --conf "$f7conf"
  _pfv auth-403/deployment-info-server-failing _pfl deployment INFO "not readable until the site accepts the credential"
  _pfv auth-403/no-server-info-read [ "$(grep -c server-info "$faargv" || true)" = 0 ]
  _pfv auth-403/card-one-fail-zero-unverified _pfl CARD FAIL "1 FAIL · 0 UNVERIFIED"
  _pfv auth-403/server-failing-rc1 _pfok 1
  pf_probe=probe-403; _pfr pf403 --preflight --conf "$f7conf"
  _pfv auth-403/fail _pfl auth FAIL "the account cannot use the REST API (org token policy or product access); ask the site admin"
  _pfv auth-403/stops _pfa project
  pf_probe=probe-hostile; _pfr pfhostile --preflight --conf "$f7conf"
  _pfv auth-hostile/unverified _pfl auth UNVERIFIED ""
  _pfv auth-hostile/never-echoed _pfnot ZQHOSTILE
  _pfv auth-hostile/rc _pfok 2
  # --- role: ci (browse only is PASS; any write or admin is over-privileged) / dev (the four needed) ---
  pf_perms=browse-only; _pfr pfci --preflight --as ci --conf "$f7conf"
  _pfv ci/header-role _pffirst "card${_pf_tab}INFO${_pf_tab}ex.atlassian.net · project AB · as ci · read-only"
  _pfv ci/account _pfl account INFO "atlassian account; use a dedicated account for the CI reader so a leaver does not break the gate"
  _pfv ci/order _pforder "card deployment reach-here reach-ci auth account token-expiry project permissions claim-tier required epic-model visibility automation CARD "
  _pfv ci/browse-only-pass _pfl permissions PASS "browse only"
  _pfv ci/rc _pfok 0
  _pfv ci/required-info-no-createmeta _pfl required INFO "required create fields need Create issues, which the CI reader must not hold; run --preflight --as dev with a developer's credential"
  _pfv ci/no-createmeta-reads [ "$(grep -c -e required-fields -e writable-create-keys "$faargv" || true)" = 0 ]
  _pfv ci/happy-argv-closed-list _pfargv "probe server-info project perms epic-model visibility"
  pf_perms=ci-unknown; _pfr pfciunk --preflight --as ci --conf "$f7conf"
  _pfv ci/perms-unknown-unverified _pfl permissions UNVERIFIED "could not read whether the CI reader holds write or admin permissions"
  _pfv ci/perms-unknown-rc2 _pfok 2
  pf_perms=all-yes; _pfr pfciover --preflight --as ci --conf "$f7conf"
  _pfv ci/over-privileged _pfl permissions FAIL "over-privileged: the CI reader holds CREATE_ISSUES, EDIT_ISSUES, TRANSITION_ISSUES, ASSIGN_ISSUES, ADMINISTER_PROJECTS; JIRA-SETUP §5a"
  _pfv ci/over-privileged-rc _pfok 1
  pf_perms=dev-missing; _pfr pfcipart --preflight --as ci --conf "$f7conf"
  _pfv ci/over-privileged-names-only-held _pfl permissions FAIL "the CI reader holds EDIT_ISSUES, TRANSITION_ISSUES; JIRA-SETUP §5a"
  pf_perms=no-browse; _pfr pfcinob --preflight --as ci --conf "$f7conf"
  _pfv ci/browse-missing _pfl permissions FAIL "the CI reader cannot browse the project; grant Browse Projects"
  pf_perms=dev-missing; _pfr pfdevmiss --preflight --conf "$f7conf"
  _pfv dev/missing _pfl permissions FAIL "missing CREATE_ISSUES, ASSIGN_ISSUES; the project admin grants them (Project settings → Access, or the permission scheme)"
  _pfv dev/missing-rc _pfok 1
  pf_perms=browse-only; _pfr pfdevbo --preflight --as dev --conf "$f7conf"
  _pfv dev/browse-only-missing-three _pfl permissions FAIL "missing CREATE_ISSUES, TRANSITION_ISSUES, ASSIGN_ISSUES;"
  pf_perms=unknown; _pfr pfdevunk --preflight --conf "$f7conf"
  _pfv dev/unknown-unverified _pfl permissions UNVERIFIED ""
  _pfv dev/unknown-rc2 _pfok 2
  _pfv dev/unknown-card _pfl CARD UNVERIFIED "0 FAIL · 1 UNVERIFIED"
  pf_permsrc=2; _pfr pfpermsrc --preflight --conf "$f7conf"
  _pfv perms-unreadable/unverified _pfl permissions UNVERIFIED ""
  # --- project / claim-tier ---
  pf_proj=unknown; _pfr pfprojunk --preflight --conf "$f7conf"
  _pfv project-unknown/project-unverified _pfl project UNVERIFIED ""
  _pfv project-unknown/claim-tier-unverified _pfl claim-tier UNVERIFIED ""
  _pfv project-unknown/never-echoed _pfnot ZQHOSTILE
  pf_proj=company; pf_pst=company; pf_wf=builds; _pfr pfclassicok --preflight --conf "$f7conf"
  _pfv claim-tier/classic-conf-pass _pfl claim-tier PASS "server-enforced (1 workflow(s))"
  _pfv claim-tier/classic-project-line _pfl project PASS "company-managed"
  _pfv claim-tier/one-line _pfn claim-tier 1
  pf_proj=company; pf_pst=company; pf_wf=any; _pfr pfclassicbad --preflight --conf "$f7conf"
  _pfv claim-tier/classic-fail-collapsed _pfl claim-tier FAIL "1 transition(s) into In Progress lack Only-Assignee; detail: --deep"
  _pfv claim-tier/collapsed-one-line _pfn claim-tier 1
  _pfv claim-tier/fail-rc _pfok 1
  _pfv claim-tier/no-per-transition-text _pfnot "Start Progress"
  pf_proj=company; pf_pst=company; pf_wf=builds; pf_wfrc=4; pf_myrc=0; _pfr pfclassicask --preflight --conf "$f7conf"
  _pfv claim-tier/permission-ask _pfl claim-tier ASK "ask an admin to run --deep"
  _pfv claim-tier/permission-ask-rc0 _pfok 0
  pf_proj=company; pf_pst=company; pf_wf=builds; pf_wfrc=2; _pfr pfclassicunv --preflight --conf "$f7conf"
  _pfv claim-tier/engine-failure-unverified _pfl claim-tier UNVERIFIED ""
  _pfv claim-tier/engine-failure-rc2 _pfok 2
  pf_proj=company; _pfr pfnoconfclassic --preflight --base https://ex.atlassian.net --project AB
  _pfv claim-tier/classic-no-conf-info _pfl claim-tier INFO "run --deep after JIRA-SETUP §4 maps state.in-progress"
  _pfv claim-tier/no-conf-no-workflow-read-argv [ "$(grep -c project-workflows "$faargv" || true)" = 0 ]
  # --- required ---
  pf_rf=contract-rf-team.txt; _pfr pfreq2 --preflight --conf "$f7conf"
  _pfv required/unmapped-count _pfl required FAIL "2 required-field problem(s) on the create screen; run tracker-contract.sh with no flag for each one and its cure"
  _pfv required/rc _pfok 1
  pf_rf=contract-rf-team.txt; _pfr pfreqmapped --preflight --conf "$fxdir/contract-conf-req-default.conf"
  _pfv required/mapped-is-zero _pfl required PASS "0 required create fields unmapped"
  pf_rf=contract-rf-absent.txt; _pfr pfreqrd --preflight --conf "$f7conf"
  _pfv required/unreadable-unverified _pfl required UNVERIFIED ""
  _pfr pfnoconfreq --preflight --base https://ex.atlassian.net --project AB
  _pfv required/no-conf-info _pfl required INFO "run --fields after JIRA-SETUP §4"
  _pfv required/no-conf-no-reads [ "$(grep -c -e required-fields -e writable-create-keys "$faargv" || true)" = 0 ]
  # --- epic-model / visibility / automation ---
  pf_epic='link'; _pfr pfepl --preflight --conf "$f7conf"
  _pfv epic/epic-link-info _pfl epic-model INFO "the site exposes only Epic Link; --epic uses parent"
  pf_epic=both; _pfr pfepb --preflight --conf "$f7conf"
  _pfv epic/both-pass _pfl epic-model PASS "parent"
  pf_epic=none; _pfr pfepn --preflight --conf "$f7conf"
  _pfv epic/none-info _pfl epic-model INFO "no epic field"
  pf_epic=hostile; _pfr pfeph --preflight --conf "$f7conf"
  _pfv epic/hostile-unverified _pfl epic-model UNVERIFIED ""
  _pfv epic/hostile-never-echoed _pfnot ZQHOSTILE
  pf_epicrc=2; _pfr pfepr --preflight --conf "$f7conf"
  _pfv epic/unreadable-unverified _pfl epic-model UNVERIFIED ""
  pf_vis=hidden; _pfr pfvh --preflight --conf "$f7conf"
  _pfv visibility/hidden-ask _pfl visibility ASK "2 of 16 issues not visible to this account: an issue-security level, archived issues, or count lag; ask the admin which"
  _pfv visibility/hidden-never-fails _pfok 0
  pf_vis=equal-nolevels; _pfr pfvl --preflight --conf "$f7conf"
  _pfv visibility/levels-unreadable _pfl visibility PASS "16 of 16 issues visible; unknown (needs project admin) issue-security levels"
  pf_vis=exceeds; _pfr pfvex --preflight --conf "$f7conf"
  _pfv visibility/visible-exceeds-total-info _pfl visibility INFO "18 visible exceeds the total 16 (count lag); re-run later"
  _pfv visibility/visible-exceeds-total-rc0 _pfok 0
  pf_vis=nototal; _pfr pfvn --preflight --conf "$f7conf"
  _pfv visibility/total-unreadable-info _pfl visibility INFO "visible 16; total not readable"
  pf_vis=hostile; _pfr pfvx --preflight --conf "$f7conf"
  _pfv visibility/hostile-gated _pfl visibility INFO "visible unknown; total not readable"
  _pfv visibility/hostile-never-echoed _pfnot ZQHOSTILE
  _pfv visibility/overlong-digits-never-echoed _pfnot 1234567890123
  # --- deployment: Data Center, and a conf that disagrees with the site ---
  pf_server=dc; _pfr pfdc --preflight --conf "$fxdir/contract-conf-dc.conf"
  _pfv deployment/dc-pass _pfl deployment PASS "Data Center (build 9000)"
  _pfv deployment/dc-auth-line _pfl auth PASS ""
  pf_server=dc; _pfr pfmismatch --preflight --conf "$f7conf"
  _pfv deployment/flavour-mismatch-fails _pfl deployment FAIL "the conf says cloud, the site is datacenter; set flavour=datacenter in .kit/tracker.conf"
  _pfv deployment/flavour-mismatch-rc _pfok 1
  # --- the rc model: FAIL beats UNVERIFIED (1), UNVERIFIED alone is 2, PASS/TIER/INFO/ASK is 0 ---
  pf_perms=all-yes; pf_epic=hostile; _pfr pfmixed --preflight --as ci --conf "$f7conf"
  _pfv rc/fail-and-unverified-is-1 _pfok 1
  _pfv rc/card-verdict-fail _pfl CARD FAIL "1 FAIL · 1 UNVERIFIED"
  _pfv rc/unverified-only-is-2 [ "$(cat "$tmpd/pfdevunk-rc")" = 2 ]
  _pfv rc/pass-with-tier-info-ask-is-0 [ "$(cat "$tmpd/pfhappy-rc")" = 0 ]
  # --- no-conf mode: the host is echoed first; a refused base or project is rc 2 BEFORE any adapter call ---
  _pfr pfnoconf --preflight --base https://ex.atlassian.net/ --project AB
  _pfv no-conf/rc _pfok 0
  _pfv no-conf/host-echoed-first _pffirst "card${_pf_tab}INFO${_pf_tab}ex.atlassian.net · project AB · as dev · read-only"
  _pfv no-conf/probe-first-call [ "$(sed -n 1p "$faargv")" = "contract-read https://ex.atlassian.net cloud probe" ]
  _pfv no-conf/claim-tier-team-tier _pfl claim-tier TIER "convention"
  _pfv no-conf/grammar _pfgram
  for _pfb in 'https://ex.atlassian.net/jira' 'https://ex.atlassian.net:8443' 'https://ex.atlassian.net.' 'https://ex.example.com' \
              'https://ex.atlassian.net.attacker.com' 'http://ex.atlassian.net' 'https://user@ex.atlassian.net' 'https://ex.atlassian.net?x=1' \
              'https://EX.atlassian.net' 'https://.atlassian.net' 'https://a.b.atlassian.net' 'https://ex.atlassian.net//' ''; do
    _pfr pfbadbase --preflight --base "$_pfb" --project AB
    _pfv "no-conf/refuses-base-[$_pfb]" _pfrefused
  done
  for _pfp in 'ab' '1AB' 'AB-C' 'AB C' "$(printf 'AB\nauth=bearer')" ''; do
    _pfr pfbadkey --preflight --base https://ex.atlassian.net --project "$_pfp"
    _pfv "no-conf/refuses-project-[$(printf '%s' "$_pfp" | tr '\n' '|')]" _pfrefused
  done
  # --- usage: every refusal is rc 2 with the adapter never invoked ---
  _pfu() { _pfl2=$1; shift; _pfr pfusage "$@"; _pfv "usage/$_pfl2" _pfrefused; }
  _pfu base-without-preflight --base https://ex.atlassian.net --project AB
  _pfu project-without-preflight --project AB
  _pfu as-without-preflight --as ci
  _pfu bad-role --preflight --as root --conf "$f7conf"
  _pfu base-without-project --preflight --base https://ex.atlassian.net
  _pfu project-without-base --preflight --project AB --conf "$f7conf"
  _pfu base-with-conf --preflight --base https://ex.atlassian.net --project AB --conf "$f7conf"
  _pfu with-deep --preflight --deep --conf "$f7conf"
  _pfu with-fields --preflight --fields --conf "$f7conf"
  _pfu with-discover --preflight --discover --conf "$f7conf"
  pf_nocreds=1; _pfr pfnocreds --preflight --conf "$f7conf"
  _pfv no-credentials/unverified-rc2 _pfok 2
  _pfv no-credentials/stamp-sentence _pfhas "UNVERIFIED: stamp"
  _pfv no-credentials/adapter-never-invoked _pfsilent
  pf_nocreds=1; _pfr pfnocredsbase --preflight --base https://ex.atlassian.net --project AB
  _pfv no-credentials/no-conf-names-the-real-path _pfhas "UNVERIFIED: stamp .kit/tracker.conf"
  _pfv no-credentials/no-conf-adapter-never-invoked _pfsilent
  # --- D (one source, three places): the click path and the runner variable agree in the card, the template and the profile ---
  _pfr pfmsg --preflight --conf "$f7conf"
  _pfv messaging/card-carries-click-path _pfl reach-ci INFO "$_pf_ph"
  for _pff in conformance/tracker-contract.sh templates/JIRA-SETUP-TEMPLATE.md profiles/adopter-tracker-gates.yml; do
    if grep -qF -e "$_pf_ph" "$_TC_ROOT/$_pff" && grep -qF -e "$_pf_tk" "$_TC_ROOT/$_pff"; then
      echo "PASS: selftest — preflight/messaging/$_pff names the click path and $_pf_tk"
    else
      echo "FAIL: selftest — preflight/messaging/$_pff must name both '$_pf_ph' and '$_pf_tk' verbatim (D: one source, three places)"; sfail=1
    fi
  done

  # --- No second implementation (S-3): scan the WHOLE file EXCEPT the selftest block (from the
  # `if [ "$SELFTEST" -eq 1 ]` line to its matching `fi`, both unindented at column 0, per this
  # file's own convention — every if/fi NESTED inside the selftest block is indented) for a bare
  # `curl` WORD (the `_tc_curl_authed` call-through's NAME is exempt — it is not an implementation,
  # it is the thing that proves there is only one). Fails CLOSED if either boundary line is not
  # found (an empty grep result must never silently pass a `NR<lim`/`,$p` range to sed/awk). The
  # scan must ALSO be positively proven to have seen real code (not an accidentally-empty range):
  # it must contain `_tc_curl_authed` itself. Needle built from pieces so this line does not
  # self-match. ---
  _nsi_needle=$(printf '%s%s' cu rl)
  _nsi_ifline=$(grep -n '^if \[ "\$SELFTEST" -eq 1 \]' "$_self" | head -1 | cut -d: -f1)
  _nsi_filine=""
  if [ -n "$_nsi_ifline" ]; then
    _nsi_filine=$(awk -v start="$_nsi_ifline" 'NR>start && /^fi$/ { print NR; exit }' "$_self")
  fi
  if [ -z "$_nsi_ifline" ] || [ -z "$_nsi_filine" ]; then
    echo "FAIL: selftest — no second implementation: could not find the selftest block's if/fi boundary (if=$_nsi_ifline fi=$_nsi_filine) (S-3)"; sfail=1
  else
    _nsi_outside=$(awk -v s="$_nsi_ifline" -v e="$_nsi_filine" 'NR<s || NR>e' "$_self")
    _nsi_nocomment=$(printf '%s\n' "$_nsi_outside" | grep -v '^[[:space:]]*#')
    if ! printf '%s\n' "$_nsi_nocomment" | grep -q '_tc_curl_authed' || ! printf '%s\n' "$_nsi_nocomment" | grep -q 'live_check "\$BASE"'; then
      echo "FAIL: selftest — no second implementation: the scanned (outside-selftest) text never mentions _tc_curl_authed AND live_check \"\$BASE\" — the scan range is wrong (a mis-found fi may have swallowed the conf-read block), not proven to have seen real code (S-3)"; sfail=1
    elif printf '%s\n' "$_nsi_nocomment" | grep -Eqi "(^|[^A-Za-z0-9_])${_nsi_needle}([^A-Za-z0-9_]|\$)"; then
      echo "FAIL: selftest — a second curl implementation exists outside the selftest block (no second implementation) (S-3)"; sfail=1
    else
      echo "PASS: selftest — no second curl implementation outside the selftest block; scripts/tracker-jira.sh is the ONE place (S-3 / no second implementation)"
    fi
  fi

  rm -f "$okf" "$gapf" "$nmf"
  rm -rf "$tmpd"; trap - EXIT INT TERM
  [ "$sfail" -eq 0 ] && { echo "OK: tracker-contract selftest"; exit 0; } || { echo "FAIL: tracker-contract selftest"; exit 1; }
fi

# security H-1: base_url comes ONLY from the pinned conf — NO env fallback. Design §5 states
# `JIRA_BASE_URL` is deliberately NOT honoured (an env base URL is unpinned: a compromised
# environment could repoint the host — and, before this fix, without even an https/host check —
# to an attacker-controlled endpoint and receive the live token). There is no legacy path here;
# a tree without a conf is UNVERIFIED, not silently pointed elsewhere.
BASE=''; FLAVOUR='cloud'
# --preflight: a trap-cleaned scratch dir for the card's reads; with --base/--project, the temporary conf is built and validated HERE,
# before any credential is looked at and before any adapter call.
PFD=''; PF_NOCONF=0; _TC_CONF_SHOWN=$CONF
if [ "$PREFLIGHT" -eq 1 ]; then
  PFD=$(mktemp -d) || { echo "UNVERIFIED: a scratch directory could not be created" >&2; exit 2; }
  trap 'rm -rf "$PFD"' EXIT
  trap 'rm -rf "$PFD"; exit 130' INT
  trap 'rm -rf "$PFD"; exit 143' TERM
  if [ "$PF_BASE_SET" -eq 1 ]; then
    pf_noconf_conf || exit 2
    PF_NOCONF=1; CONF="$PFD/tracker.conf"
  fi
fi
if [ -f "$CONF" ]; then
  _tc_refusal=$(mktemp)
  if ! sh "$TC_SH" "$CONF" >"$_tc_refusal" 2>&1; then
    cat "$_tc_refusal" >&2; rm -f "$_tc_refusal"
    echo "FAIL: $CONF does not satisfy the tracker-conf grammar (see above)" >&2
    exit 1
  fi
  rm -f "$_tc_refusal"
  BASE=$(sh "$TC_SH" get base_url "$CONF")
  FLAVOUR=$(sh "$TC_SH" get flavour "$CONF" 2>/dev/null || printf 'cloud')
fi

REST=$(rest_base "$FLAVOUR")

# reviewer I-1 / security M-1: KIT_TRACKER_USER/KIT_TRACKER_TOKEN are the PRIMARY backend-neutral
# credential pair (design §5); JIRA_EMAIL/JIRA_TOKEN are legacy aliases. KIT_TRACKER_* wins when
# both are set (never silently mixed — the newer, backend-neutral pair is authoritative).
JIRA_EMAIL=${KIT_TRACKER_USER:-${JIRA_EMAIL:-}}
JIRA_TOKEN=${KIT_TRACKER_TOKEN:-${JIRA_TOKEN:-}}

# SD-7(a): this gate requires BOTH a user and a token even under auth=bearer (which only needs a
# token) — a token-only bearer conf stays deliberately UNVERIFIED here, never auto-verified.
if [ -n "$BASE" ] && [ -n "${JIRA_EMAIL:-}" ] && [ -n "${JIRA_TOKEN:-}" ]; then
  # SD-3: KIT_TRACKER_AUTH is read from the PINNED CONF only, on the live path — never inherited
  # from the ambient environment (an unpinned KIT_TRACKER_AUTH could silently downgrade/upgrade the
  # auth scheme underneath a verified conf). Absent `auth=` in the conf -> basic.
  KIT_TRACKER_AUTH=$(sh "$TC_SH" get auth "$CONF" 2>/dev/null || printf 'basic')
  export KIT_TRACKER_AUTH
  if [ "$PREFLIGHT" -eq 1 ]; then
    pf_live "$PF_AS" "$(sh "$TC_SH" get project "$CONF")"; exit "$_PF_RC"
  fi
  if [ "$DISCOVER" -eq 1 ]; then
    tc_discover "$BASE" "$REST"; exit $?
  fi
  if [ "$FIELDS" -eq 1 ]; then
    tc_fields_live; exit $?
  fi
  echo "Jira contract check (live: $BASE, flavour=$FLAVOUR):"
  ok=0
  if live_check "$BASE" "$REST"; then :; else ok=1; fi
  unv=0; DEEP_VERIFIED=0
  if [ "$DEEP" -eq 1 ]; then
    echo "Deep: Only-Assignee transition condition (this project's own workflows):"
    _dp_rc=0; deep_live "$BASE" "$REST" || _dp_rc=$?
    [ "$_dp_rc" -ne 1 ] || ok=1
    [ "$_dp_rc" -ne 2 ] || unv=1
  else
    echo "ATTESTED (not auto-verified): confirm the Only-Assignee condition, or re-run with --deep to verify it — see JIRA-SETUP.md."
  fi
  if tc_coherence_live; then :; else ok=1; fi
  if [ "$ok" -eq 0 ]; then
    [ "$unv" -eq 0 ] || { echo "UNVERIFIED: the §6 contract holds, but the Only-Assignee tier is attested, not proven (see above)"; exit 2; }
    if [ "$DEEP_VERIFIED" -eq 1 ]; then echo "OK: Jira satisfies the §6 contract (incl. the verified Only-Assignee claim)"; else echo "OK: Jira satisfies the §6 contract"; fi
    exit 0
  else
    echo "FAIL: Jira does not satisfy the §6 contract (see above)"; exit 1
  fi
else
  echo "UNVERIFIED: stamp $_TC_CONF_SHOWN (base_url comes ONLY from the pinned conf — see JIRA-SETUP.md) and set KIT_TRACKER_USER + KIT_TRACKER_TOKEN (or legacy JIRA_EMAIL/JIRA_TOKEN) to verify a live Jira (exit 2, not a pass)."
  echo "  Configure per JIRA-SETUP.md; this is the kit's honest 'cannot run != pass' (conformance/README.md)."
  exit 2
fi
