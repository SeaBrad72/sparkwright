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
# a benign read on a non-secret server with no secret noun stays read (no over-deny)
allow "benign get_item"    "mcp__store__get_item"          "" ""
# secret.read honors the allowlist/override escape hatches (explicit human intent)
allow "secret allowlisted" "mcp__vault__read"              "mcp__vault__read" ""
allow "secret override"    "mcp__vault__read"              "" "mcp__vault__read=read"
# allowlist + wildcard + override escape hatches
allow "allowlisted exact"  "mcp__filesystem__delete_file"  "mcp__filesystem__delete_file" ""
allow "allowlisted wild"   "mcp__filesystem__write_file"   "mcp__filesystem__*" ""
allow "override to read"   "mcp__reports__export_csv"      "" "mcp__reports__export_csv=read"

# the gate must be WIRED, not just correct: assert a Claude PreToolUse matcher routes mcp__*.
# Without this, classification could pass while the live hook never sees MCP calls (green-while-dark).
# STRUCTURAL check: extract PreToolUse matchers with jq (so a mcp__ matcher mis-placed under
# PostToolUse can't fail-open the check), then require a wildcard form (mcp__.* / mcp__* / bare
# mcp__ at an alternation boundary) so a non-routing matcher like "mcp__nothing" doesn't satisfy it.
# jq-absent is honest UNVERIFIED (exit 2), never a false PASS.
SETTINGS="${KIT_GUARD_SETTINGS:-.claude/settings.json}"
unverified=0
if [ ! -f "$SETTINGS" ]; then
  echo "FAIL (gate dark): $SETTINGS missing — cannot confirm a PreToolUse mcp__ matcher is wired"; fail=1
elif ! command -v jq >/dev/null 2>&1; then
  # jq-absent must NOT exit 0 (a PASS code), or automation reading the exit status sees green
  # while the wiring was never structurally confirmed — the honesty must live in the exit code,
  # not only in stdout. Exit 2 (UNVERIFIED), matching verify.sh's three-state contract.
  echo "UNVERIFIED wired: jq absent — cannot structurally confirm the PreToolUse mcp__ matcher ($SETTINGS); install jq"; unverified=1
elif jq -r '.hooks.PreToolUse[]?.matcher // empty' "$SETTINGS" 2>/dev/null | grep -Eq 'mcp__(\.\*|\.\+|\*|\||$)'; then
  echo "PASS wired: a PreToolUse matcher routes mcp__* ($SETTINGS)"
else
  echo "FAIL (gate dark): no PreToolUse matcher routes mcp__* — classification would pass while the hook is dark ($SETTINGS)"; fail=1
fi

if [ "$fail" -ne 0 ]; then echo "FAIL: mcp-policy"; exit 1; fi
if [ "$unverified" -ne 0 ]; then echo "UNVERIFIED: mcp-policy (classification correct; wiring unconfirmed — jq absent)"; exit 2; fi
echo "OK: MCP capability gate classifies correctly and is wired"; exit 0
