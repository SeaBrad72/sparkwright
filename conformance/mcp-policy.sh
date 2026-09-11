#!/bin/sh
# mcp-policy.sh — proves the MCP capability gate's classification (Slice 11a).
# The corpus IS the test: drives guard_check_mcp directly with fixture allowlists/overrides.
# Sources the deny-matrix core (override with KIT_GUARD_CORE for pre-apply validation).
#   sh conformance/mcp-policy.sh
# Exit: 0 = all cases correct · 1 = a case wrong. POSIX sh; dash-clean.
set -eu

CORE="${KIT_GUARD_CORE:-.claude/hooks/guard-core.sh}"
[ -f "$CORE" ] || { echo "FAIL: guard-core not found ($CORE)"; exit 1; }
# shellcheck disable=SC1090  # dynamic source path; guarded by the [ -f ] check above
. "$CORE"

fail=0
deny()  { if guard_check_mcp "$2" "$3" "$4" >/dev/null 2>&1; then echo "FAIL (wanted deny):  $1"; fail=1; else echo "PASS deny:  $1"; fi; }
allow() { if guard_check_mcp "$2" "$3" "$4" >/dev/null 2>&1; then echo "PASS allow: $1"; else echo "FAIL (wanted allow): $1"; fail=1; fi; }
# deny_reason: must DENY *and* the reason (captured) must contain each of the trailing needles.
# The reason is on stdout (guard_check_mcp printf's it); 2>&1 folds stderr in so a stray write
# still surfaces. Mirrors deny()'s rc contract, adds a substring assertion on the reason text.
deny_reason() {
  _label=$1; _tool=$2; _al=$3; _ov=$4; shift 4
  if _out=$(guard_check_mcp "$_tool" "$_al" "$_ov" 2>&1); then
    echo "FAIL (wanted deny):  $_label"; fail=1; return
  fi
  for _needle in "$@"; do
    if ! printf '%s' "$_out" | grep -qF -- "$_needle"; then
      echo "FAIL (reason missing [$_needle]):  $_label"; fail=1; return
    fi
  done
  echo "PASS deny+reason:  $_label"
}

# deny-by-default destructive/egress (empty policy)
deny  "fs delete"          "mcp__filesystem__delete_file"  "" ""
deny  "db drop"            "mcp__postgres__drop_table"     "" ""
deny  "cloud deploy"       "mcp__vercel__deploy_project"   "" ""
deny  "vcs write"          "mcp__github__createIssue"      "" ""
deny  "msg send (egress)"  "mcp__slack__post_message"      "" ""
deny  "export (exfil)"     "mcp__reports__export_csv"      "" ""
deny  "fail-closed verb"   "mcp__weird__frobnicate"        "" ""
# allow read-only by default
allow "db read"            "mcp__postgres__query"          "" ""
allow "list"               "mcp__github__list_issues"      "" ""
# read-prefixed compounds: legit read nouns stay read; destructive verb tokens downgrade to deny
allow "compound read noun" "mcp__deploy__list_deployments" "" ""
allow "get_updates noun"   "mcp__feed__get_updates"        "" ""
deny  "read+destructive"   "mcp__fs__get_and_delete"       "" ""
deny  "camelCase exfil"    "mcp__rep__fetchAndExport"      "" ""
deny  "camelCase getDelete" "mcp__fs__getDelete"           "" ""
# non-verb lookalikes are not read VERBS -> fail-closed (getter != get, counter != count)
deny  "getter not a verb"  "mcp__x__getter"                "" ""
deny  "counter not a verb" "mcp__x__counter"               "" ""
# secret.read (A8 family 6) is deny-by-default even when a read verb leads: by action-noun...
deny  "secret in action"   "mcp__aws__get_secret_value"    "" ""
deny  "credential action"  "mcp__x__getCredential"         "" ""
deny  "api_key action"     "mcp__x__read_api_key"          "" ""
# ...or by known secret-store server on a read
deny  "vault server read"  "mcp__vault__read"              "" ""
deny  "1password server"   "mcp__1password__get_item"      "" ""
# MCP-SECRET-READ-CLASSIFIER: six measured stores that ALLOWed before this slice (2026-09-06)
deny  "aws parameter store"  "mcp__aws__get_parameter"     "" ""
deny  "ssm parameters"       "mcp__ssm__get_parameters"    "" ""
deny  "azure key vault"      "mcp__azure__get_key"         "" ""
deny  "bitwarden item"       "mcp__bitwarden__get_item"    "" ""
deny  "conjur variable"      "mcp__conjur__read_variable"  "" ""
deny  "cyberark account"     "mcp__cyberark__get_account"  "" ""
# a benign read on a non-secret server with no secret noun stays read (no over-deny)
allow "benign get_item"    "mcp__store__get_item"          "" ""
# secret.read honors the allowlist/override escape hatches (explicit human intent)
allow "secret allowlisted" "mcp__vault__read"              "mcp__vault__read" ""
allow "secret override"    "mcp__vault__read"              "" "mcp__vault__read=read"
allow "param allowlisted"  "mcp__aws__get_parameter"  "mcp__aws__get_parameter"  ""
# allowlist + override escape hatches
allow "allowlisted exact"  "mcp__filesystem__delete_file"  "mcp__filesystem__delete_file" ""
allow "override to read"   "mcp__reports__export_csv"      "" "mcp__reports__export_csv=read"
# F2 (slice 3d): action-anchored, server-agnostic key mcp__*__<action> — a per-ACTION trust decision
# that survives a server rename. The all-tools wildcard mcp__server__* / mcp__*__* is REJECTED by
# name (a wildcard admitting every tool on a server is no longer an allow — it falls through to
# classification). The action anchor is EXACT on the trailing segment (no prefix/substring bypass).
allow "action anchor server A" "mcp__claude_ai_Github_MCP__create_pull_request" "mcp__*__create_pull_request" ""
allow "action anchor server B" "mcp__github__create_pull_request"               "mcp__*__create_pull_request" ""
deny  "action anchor exact"    "mcp__claude_ai_Github_MCP__delete_repository"   "mcp__*__create_pull_request" ""
deny  "action anchor no prefix" "mcp__x__create_pull_request_and_delete"        "mcp__*__create_pull_request" ""
deny  "server wildcard rejected" "mcp__claude_ai_Github_MCP__delete_repository" "mcp__claude_ai_Github_MCP__*" ""
deny  "all-tools wildcard rejected" "mcp__anything__delete_repository"          "mcp__*__*" ""
# ...and the rejection denies BY NAME with a migration reason (design F2 pt2 / plan T1 2b): a tool
# that WOULD have been admitted by a now-dead server wildcard must be told, in the deny reason, that
# the wildcard entry no longer grants and to allowlist the action-anchored form mcp__*__<action>.
# Not a decision change — reads still classify-allow, destructive still denies; only the reason grows.
deny_reason "server wildcard names the action anchor" \
  "mcp__github__delete_repository" "mcp__github__*" "" \
  "mcp__github__*" "mcp__*__delete_repository"
deny_reason "all-tools wildcard names the action anchor" \
  "mcp__anything__delete_repository" "mcp__*__*" "" \
  "mcp__*__*" "mcp__*__delete_repository"
# F2-1 (slice 3d sec-fix): the SHAPE GATE. A well-formed tool name is mcp__<srv>__<act> with a
# NON-EMPTY srv and act and act != '*'. A tool literally NAMED like a wildcard entry must NOT be
# admitted by the exact-match line — so "the all-tools wildcard is rejected" is literally true, not
# only via the removed wildcard branch. A tool with an EMPTY action segment is malformed and skips
# the allowlist entirely (deny-by-default). Both fall through to classification and deny.
deny  "tool named like server wildcard" "mcp__github__*"  "mcp__github__*" ""
deny  "tool with empty action segment"  "mcp__github__"   "mcp__*__"       ""

# the gate must be WIRED, not just correct: assert a Claude PreToolUse matcher routes mcp__*.
# Without this, classification could pass while the live hook never sees MCP calls (green-while-dark).
# STRUCTURAL check: extract PreToolUse matchers with jq (so a mcp__ matcher mis-placed under
# PostToolUse can't fail-open the check), then test each FUNCTIONALLY — a matcher is Claude's
# tool-name selector applied as an anchored ERE, so the gate is wired iff some matcher MATCHES a
# representative mcp tool name (^(matcher)$ vs mcp__server__action). This mirrors guard-wired.sh
# rather than grepping for a literal "mcp__" substring: a broad matcher like ".*" (or ".+") routes
# every tool — mcp included — and correctly PASSES, while a dark matcher like "Read" or the
# non-routing "mcp__nothing" correctly FAILS (neither full-matches the probe).
# jq-absent is honest UNVERIFIED (exit 2), never a false PASS.
SETTINGS="${KIT_GUARD_SETTINGS:-.claude/settings.json}"
unverified=0

# Does any PreToolUse matcher, as an anchored ERE, route a representative mcp tool call?
# set -f while word-splitting the matcher list so a matcher's own '*' (e.g. ".*", "mcp__.*")
# is not glob-expanded against the cwd; matchers carry no spaces, so IFS splitting is safe.
mcp_matcher_wired() {
  _probe='mcp__server__action'
  _rc=1
  set -f
  for _m in $(jq -r '.hooks.PreToolUse[]?.matcher // empty' "$1" 2>/dev/null); do
    if printf '%s\n' "$_probe" | grep -Eq "^(${_m})$" 2>/dev/null; then _rc=0; fi
  done
  set +f
  return "$_rc"
}

if [ ! -f "$SETTINGS" ]; then
  echo "FAIL (gate dark): $SETTINGS missing — cannot confirm a PreToolUse mcp__ matcher is wired"; fail=1
elif ! command -v jq >/dev/null 2>&1; then
  # jq-absent must NOT exit 0 (a PASS code), or automation reading the exit status sees green
  # while the wiring was never structurally confirmed — the honesty must live in the exit code,
  # not only in stdout. Exit 2 (UNVERIFIED), matching verify.sh's three-state contract.
  echo "UNVERIFIED wired: jq absent — cannot structurally confirm the PreToolUse mcp__ matcher ($SETTINGS); install jq"; unverified=1
elif mcp_matcher_wired "$SETTINGS"; then
  echo "PASS wired: a PreToolUse matcher routes mcp__* ($SETTINGS)"
else
  echo "FAIL (gate dark): no PreToolUse matcher routes mcp__* — classification would pass while the hook is dark ($SETTINGS)"; fail=1
fi

if [ "$fail" -ne 0 ]; then echo "FAIL: mcp-policy"; exit 1; fi
if [ "$unverified" -ne 0 ]; then echo "UNVERIFIED: mcp-policy (classification correct; wiring unconfirmed — jq absent)"; exit 2; fi
echo "OK: MCP capability gate classifies correctly and is wired"; exit 0
