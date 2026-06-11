#!/bin/sh
# mcp-policy.sh — proves the MCP capability gate's classification (Slice 11a).
# The corpus IS the test: drives guard_check_mcp directly with fixture allowlists/overrides.
# Sources the deny-matrix core (override with KIT_GUARD_CORE for pre-apply validation).
#   sh conformance/mcp-policy.sh
# Exit: 0 = all cases correct · 1 = a case wrong. POSIX sh; dash-clean.
set -eu

CORE="${KIT_GUARD_CORE:-.claude/hooks/guard-core.sh}"
[ -f "$CORE" ] || { echo "FAIL: guard-core not found ($CORE)"; exit 1; }
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
# allowlist + wildcard + override escape hatches
allow "allowlisted exact"  "mcp__filesystem__delete_file"  "mcp__filesystem__delete_file" ""
allow "allowlisted wild"   "mcp__filesystem__write_file"   "mcp__filesystem__*" ""
allow "override to read"   "mcp__reports__export_csv"      "" "mcp__reports__export_csv=read"

# the gate must be WIRED, not just correct: assert the Claude PreToolUse matcher routes mcp__*.
# Without this, classification could pass while the live hook never sees MCP calls (green-while-dark).
SETTINGS="${KIT_GUARD_SETTINGS:-.claude/settings.json}"
if [ -f "$SETTINGS" ] && grep -q 'PreToolUse' "$SETTINGS" && grep -Eq '"matcher":[[:space:]]*"[^"]*mcp__' "$SETTINGS"; then
  echo "PASS wired: settings.json PreToolUse matcher routes mcp__*"
else
  echo "FAIL (gate dark): settings.json PreToolUse matcher does not route mcp__* ($SETTINGS)"; fail=1
fi

[ "$fail" -eq 0 ] && { echo "OK: MCP capability gate classifies correctly and is wired"; exit 0; } || { echo "FAIL: mcp-policy"; exit 1; }
