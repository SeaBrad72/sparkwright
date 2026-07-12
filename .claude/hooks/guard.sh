#!/bin/sh
# guard.sh — Claude Code PreToolUse adapter over guard-core.sh (the deny-matrix).
# Intentionally THIN: parse the Claude tool-call JSON, call the shared core, emit a
# Claude permission decision. ALL deny logic lives in guard-core.sh (single source of
# truth), reused by hooks/pre-push and scripts/kit-guard. Requires jq; jq-absent or
# non-JSON input denies mutating tools (fail closed). See docs/operations/runtime-guards.md.
set -eu

. "$(dirname "$0")/guard-core.sh"

INPUT=$(cat)

# escape for a JSON double-quoted value (backslash + quote; reasons have no control chars)
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
emit_deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$(json_escape "$1")"
  exit 0
}
emit_ask() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$(json_escape "$1")"
  exit 0
}

allow() { exit 0; }

tool_name_grep() {
  printf '%s' "$INPUT" | tr -d '\n' | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}
deny_if_mutating() {
  case "$1" in
    Bash|Write|Edit|NotebookEdit|mcp__*)
      emit_deny "agent-guard: $2 (DEVELOPMENT-PROCESS.md 13). Mutating tools are denied until resolved." ;;
    *) allow ;;
  esac
}

if ! command -v jq >/dev/null 2>&1; then
  deny_if_mutating "$(tool_name_grep)" "jq is required to evaluate tool safety; install jq"
fi
if ! TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null); then
  emit_deny "agent-guard: tool input is not valid JSON — cannot verify safety; denying (DEVELOPMENT-PROCESS.md 13)."
fi

case "$TOOL" in
  Bash)
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || printf '')
    if reason=$(guard_check_command "$CMD"); then allow; else emit_deny "$reason"; fi ;;
  Write|Edit|NotebookEdit)
    FP=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null || printf '')
    if reason=$(guard_check_path "$FP"); then allow; else emit_deny "$reason"; fi ;;
  Read)
    FP=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || printf '')
    if reason=$(guard_check_read "$FP"); then allow; else emit_deny "$reason"; fi ;;
  mcp__*)
    POL="$(dirname "$0")/../mcp-policy.json"
    AL=""; OV=""
    if [ -f "$POL" ]; then
      AL=$(jq -r '.allow[]? // empty' "$POL" 2>/dev/null || printf '')
      OV=$(jq -r '(.classOverride // {}) | to_entries[] | "\(.key)=\(.value)"' "$POL" 2>/dev/null || printf '')
    fi
    if reason=$(guard_check_mcp "$TOOL" "$AL" "$OV"); then allow; else emit_deny "$reason"; fi ;;
  Skill)
    SK=$(printf '%s' "$INPUT" | jq -r '.tool_input.skill // .tool_input.name // empty' 2>/dev/null || printf '')
    v=$(guard_check_skill "$SK"); tok=$(printf '%s' "$v" | head -n1); reason=$(printf '%s' "$v" | sed -n '2,$p')
    case "$tok" in
      ask)  emit_ask "$reason" ;;
      deny) emit_deny "$reason" ;;
      *)    allow ;;
    esac ;;
  *)
    allow ;;
esac
