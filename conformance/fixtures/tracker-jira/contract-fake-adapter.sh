#!/bin/sh
# T3b fixture: a fake `scripts/tracker-jira.sh` for tracker-contract.sh's --selftest fake-adapter
# tree. Proves the CONTRACT calls `contract-read` and only that, never curl itself. The caller
# exports FA_ARGVLOG/FA_ENVLOG/FA_INVOKED/FA_RC/FA_STATUSBODY (fixed paths under its own $tmpd)
# before invoking the copy of tracker-contract.sh that resolves TJ_SH to this file.
printf '%s\n' "$*" >> "$FA_ARGVLOG"
_fa_cb='unset'; [ -n "${_TJ_CURL_BIN+x}" ] && _fa_cb='set'
printf 'KIT_TRACKER_USER=%s KIT_TRACKER_TOKEN=%s JIRA_EMAIL=%s JIRA_TOKEN=%s KIT_TRACKER_AUTH=%s _TJ_CURL_BIN=%s\n' \
  "${KIT_TRACKER_USER:-}" "${KIT_TRACKER_TOKEN:-}" "${JIRA_EMAIL:-}" "${JIRA_TOKEN:-}" "${KIT_TRACKER_AUTH:-}" "$_fa_cb" >> "$FA_ENVLOG"
: > "$FA_INVOKED"
if [ -f "$FA_RC" ]; then exit "$(cat "$FA_RC")"; fi
# BOARD-CREATE-HONOURS-FIELD-MAP: `create-meta <base> <flavour> <project> [<type>]` answers from the recorded
# adapter-output file $FA_CMBODY (one line per field, the type in column 1), like the real op: only the
# named type's lines, rc 1 when that type has none.
if [ "$1" = create-meta ]; then
  [ -f "${FA_CMBODY:-}" ] || exit 64
  if [ -n "${5:-}" ]; then _fa_cm=$(awk -F'\t' -v t="$5" '$1 == t' "$FA_CMBODY"); else _fa_cm=$(cat "$FA_CMBODY"); fi
  [ -n "$_fa_cm" ] || exit 3
  # like the real op: a NAMED type is preceded by its numeric id line
  if [ -n "${5:-}" ]; then printf '#type-id\t10003\n'; fi
  printf '%s\n' "$_fa_cm"
  exit 0
fi
# TRACKER-REQUIRED-FIELDS-DISCOVERY: `required-fields <base> <flavour> <project> <type>` answers from the recorded
# adapter output $FA_RFBODY (rc 2 when it names a file that is not there); with no $FA_RFBODY, a type that
# requires nothing. `writable-create-keys` prints the adapter's closed set.
if [ "$1" = required-fields ]; then
  if [ -z "${FA_RFBODY:-}" ]; then printf '#type-id\t10003\n'; exit 0; fi
  [ -f "$FA_RFBODY" ] || exit 2
  cat "$FA_RFBODY"; exit 0
fi
# `transition-fields <base> <flavour> <issue-key>` answers from the recorded adapter output $FA_TFBODY (a file of
# lines; none set = a card whose transitions require nothing; a named file that is not there = rc 2).
if [ "$1" = transition-fields ]; then
  [ -z "${FA_TFBODY:-}" ] && exit 0
  [ -f "$FA_TFBODY" ] || exit 2
  cat "$FA_TFBODY"; exit 0
fi
if [ "$1" = writable-create-keys ]; then
  printf 'customfield_N\npriority\ncomponents\nfixVersions\nduedate\nlabels\nparent\ndescription\n'; exit 0
fi
case "$4" in
  status)
    if [ -f "$FA_STATUSBODY" ]; then cat "$FA_STATUSBODY"
    else printf '"Backlog" "Ready" "In Progress" "In Review" "Released" "Done" "Blocked" "Size" "Risk"\n'
    fi ;;
  field) printf '' ;;
  # TRACKER-CONTRACT-HONEST-TIER: the project-scoped reads answer from recorded ADAPTER OUTPUT (closed grammar,
  # the files the real adapter's selftest proves byte-for-byte). Each call is already counted by $FA_ARGVLOG.
  myself) [ "${FA_MYSELF_RC:-0}" = 0 ] || exit "$FA_MYSELF_RC"; echo ok ;;
  project) cat "${FA_PROJECT:-$FA_FXDIR/contract-project-team.txt}" ;;
  project-statuses) cat "${FA_PSTATUSES:-$FA_FXDIR/contract-pstatuses-team.txt}" ;;
  project-workflows) [ -z "${FA_WF_RC:-}" ] || exit "$FA_WF_RC"; cat "${FA_WF:-$FA_FXDIR/contract-wf-team.txt}" ;;
  # TRACKER-PREFLIGHT-TIER-CARD (interface A): the five card reads answer from recorded adapter output
  # ($FA_PF_<X>, a file; default = the all-good fixture) and exit $FA_PF_<X>_RC when that is set.
  probe) [ -z "${FA_PF_PROBE_RC:-}" ] || exit "$FA_PF_PROBE_RC"; cat "${FA_PF_PROBE:-$FA_FXDIR/contract-pf-probe-ok.txt}" ;;
  server-info) [ -z "${FA_PF_SERVER_RC:-}" ] || exit "$FA_PF_SERVER_RC"; cat "${FA_PF_SERVER:-$FA_FXDIR/contract-pf-server-cloud.txt}" ;;
  perms) [ -z "${FA_PF_PERMS_RC:-}" ] || exit "$FA_PF_PERMS_RC"; cat "${FA_PF_PERMS:-$FA_FXDIR/contract-pf-perms-all-yes.txt}" ;;
  visibility) [ -z "${FA_PF_VIS_RC:-}" ] || exit "$FA_PF_VIS_RC"; cat "${FA_PF_VIS:-$FA_FXDIR/contract-pf-vis-equal.txt}" ;;
  epic-model) [ -z "${FA_PF_EPIC_RC:-}" ] || exit "$FA_PF_EPIC_RC"; cat "${FA_PF_EPIC:-$FA_FXDIR/contract-pf-epic-parent.txt}" ;;
  # a site-wide read does not exist in the real adapter; a leg offers one anyway to prove the contract never asks
  workflow) cat "${FA_SITEWIDE:-/dev/null}" ;;
  *) exit 64 ;;
esac
exit 0
