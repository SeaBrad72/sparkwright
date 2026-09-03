#!/bin/sh
# guard.sh — Claude Code PreToolUse adapter over guard-core.sh (the deny-matrix).
# Intentionally THIN: parse the Claude tool-call JSON, call the shared core, emit a
# Claude permission decision. ALL deny logic lives in guard-core.sh (single source of
# truth), reused by hooks/pre-push and scripts/kit-guard. Requires jq; jq-absent or
# non-JSON input denies mutating tools (fail closed). See docs/operations/runtime-guards.md.
set -eu

. "$(dirname "$0")/guard-core.sh"

# CP-8c: the protected repo root = the tree holding this hook (<root>/.claude/hooks/guard.sh).
# Physically resolved to match guard_dev_clone_relaxable. Empty if unresolvable => no
# relaxation (fail-safe). Unforgeable: the agent cannot move the live repo, and $0 comes
# from control-plane config.
PROTECTED_ROOT=$(CDPATH='' cd "$(dirname "$0")/../.." 2>/dev/null && pwd -P || printf '')

INPUT=$(cat)

# escape for a JSON double-quoted value (backslash + quote; reasons have no control chars)
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
emit_deny() {
  # ⚠️⚠️ ORDER IS A SECURITY PROPERTY (C1b, review round 1) — THE DECISION IS PRINTED FIRST.
  # The first cut logged BEFORE this printf, which meant a logging pathology could preempt the
  # verdict entirely: with a FIFO planted at the log path the `>>` blocked forever and the deny JSON
  # was NEVER EMITTED — the hook hung instead of denying. Logging is an observation and must never
  # sit on the critical path of a decision, so it runs after the verdict is on stdout and before the
  # exit. `guard_log_deny` swallows every failure and always returns 0. $TOOL is unset only on the
  # jq-absent / non-JSON paths that run before it is assigned — `${TOOL:--}` logs those as tool `-`.
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$(json_escape "$1")"
  guard_log_deny pretooluse "$1" "${TOOL:--}" || :
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
    Bash|Write|Edit|NotebookEdit|MultiEdit|mcp__*)
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
    # GUARD-CWD-CONFIDENCE-UNKNOWN Face C. `cwd` is a TOP-LEVEL PreToolUse field (a sibling of
    # `tool_name`), not part of `tool_input` — which is the whole reason it is trustworthy here: the
    # model authors `tool_input` and the harness authors this. Still no deny logic in the adapter:
    # it forwards a string and the core decides. Absent ⇒ empty ⇒ the core's pre-slice behaviour.
    CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || printf '')
    if reason=$(guard_check_command "$CMD" "$CWD"); then allow; else emit_deny "$reason"; fi ;;
  Write|Edit|NotebookEdit|MultiEdit)
    # MultiEdit folded in (C5 GUARD-TOOL-COVERAGE, design §2 Part A / vet Q2): its write surface is a
    # single .tool_input.file_path (+ an edits[] array, no multi-target), the same field Edit writes,
    # so guard_check_path covers it completely — a DIFFERENT tool name reaching the SAME write route.
    FP=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null || printf '')
    if reason=$(guard_check_path "$FP" "$PROTECTED_ROOT"); then allow; else emit_deny "$reason"; fi ;;
  Grep|Glob)
    # C5 GUARD-TOOL-COVERAGE-GREP-GLOB — the content-search family. Route the secret-TARGETING
    # spellings through guard_check_read (the same read-half-of-exfil deny the Read arm uses): a
    # path OR glob NAMING a secret file/pattern (.env, *.env, *.pem, …) is denied. HONEST RESIDUAL
    # (design §4 ★): guard_check_read matches secret FILENAMES, while Grep's `path` is a search ROOT —
    # so a directory- or cwd-rooted content Grep (no path, or path:".") is NOT backstopped here; it is
    # a DISCLOSED residual, marked residual-family in sanctioned-commands.tsv and handed off to the
    # platform egress/FS boundary (docs/operations/runtime-guards.md). An empty field is SKIPPED so an
    # ordinary directory/cwd search stays ALLOW — only a NAMED secret target denies. Glob returns
    # filenames not content, so guarding its path/glob is defense-in-depth, not a content-exfil fix.
    RGPATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.path // empty' 2>/dev/null || printf '')
    RGGLOB=$(printf '%s' "$INPUT" | jq -r '.tool_input.glob // empty' 2>/dev/null || printf '')
    if [ -n "$RGPATH" ] && ! reason=$(guard_check_read "$RGPATH" "$PROTECTED_ROOT"); then emit_deny "$reason"; fi
    if [ -n "$RGGLOB" ] && ! reason=$(guard_check_read "$RGGLOB" "$PROTECTED_ROOT"); then emit_deny "$reason"; fi
    allow ;;
  Read)
    FP=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || printf '')
    # MEDIUM-1: pass PROTECTED_ROOT so the read-side hardlink-alias check uses the authoritative root.
    if reason=$(guard_check_read "$FP" "$PROTECTED_ROOT"); then allow; else emit_deny "$reason"; fi ;;
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
