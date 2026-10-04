#!/bin/sh
# guard.sh — Claude Code PreToolUse adapter over guard-core.sh (the deny-matrix).
# Intentionally THIN: parse the Claude tool-call JSON, call the shared core, emit a
# Claude permission decision. ALL deny logic lives in guard-core.sh (single source of
# truth), reused by hooks/pre-push and scripts/kit-guard. Requires jq; jq-absent or
# non-JSON input denies mutating tools (fail closed). See docs/operations/runtime-guards.md.
set -eu

# ⚠️ EXIT CONTRACT (GUARD-RUNTIME-ERROR-FAIL-OPEN): this hook exits 0 WITH a decision or 2. Claude Code
# blocks only on 2; any other code is a NON-blocking error and the tool call PROCEEDS. A fault in the
# core under bash-as-sh exits 1, so an undecided exit must be turned into 2. The trap is keyed on a
# completion sentinel, NOT `$?`: under bash 3.2 `$?` in an EXIT trap after a fatal shell error is not
# the failure status, and a `$?` trap was measured turning those faults into a silent rc 0 ALLOW.
# The variable is assigned BEFORE the trap so an exported value cannot pre-arm it. The `|| :` keeps a
# failed stderr write from exiting non-2 under `set -e`.
_GUARD_DECIDED=''
trap '[ "$_GUARD_DECIDED" = yes ] || { printf "%s\n" "agent-guard: the guard failed before reaching a decision - failing closed; the tool call is blocked (see docs/operations/runtime-guards.md, exit contract)." >&2 || :; exit 2; }' EXIT

# GUARD-QUOTED-EXEC-INTERMITTENT: the fault channel from inside a subshell (see `_guard_fault` in guard-core.sh).
# The handler clears the sentinel FIRST, so even if `allow()` already set `_GUARD_DECIDED=yes` the EXIT trap
# above sees an undecided hook and exits 2; then it exits 2 itself. `_GUARD_FAULTED` is the belt: `allow()`
# refuses while it is set. Armed BEFORE the core is sourced and before any check runs; `_GUARD_USR1` tells the
# core the trap exists. CEILING: if the hook was started with USR1 ignored, or blocked in the inherited signal
# mask, `trap` cannot take it (POSIX) and this channel is silently absent; the other layers still stand.
_GUARD_FAULTED=''
_guard_usr1() { _GUARD_FAULTED=yes; _GUARD_DECIDED=''; exit 2; }
trap '_guard_usr1' USR1
_GUARD_USR1=1

. "$(dirname "$0")/guard-core.sh"

# CP-8c: the protected repo root = the tree holding this hook (<root>/.claude/hooks/guard.sh).
# Physically resolved to match guard_dev_clone_relaxable. Empty if unresolvable => no
# relaxation (fail-safe). Unforgeable: the agent cannot move the live repo, and $0 comes
# from control-plane config.
PROTECTED_ROOT=$(CDPATH='' cd "$(dirname "$0")/../.." 2>/dev/null && pwd -P || printf '')

INPUT=$(cat) || _guard_fault input-read
# A harness call is never blank; a blank INPUT is a failed read (the `cat` fork), and every later read of it
# would then come back empty and look like "nothing to judge". Fork-free test.
case $INPUT in *[![:space:]]*) : ;; *) _guard_fault input-read ;; esac

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
  # The flag is set AFTER the logger, so a logger fault blocks (exit 2) rather than proceeds.
  _GUARD_DECIDED=yes; exit 0
}
emit_ask() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$(json_escape "$1")"
  _GUARD_DECIDED=yes; exit 0
}

# GUARD-QUOTED-EXEC-INTERMITTENT §3b — EVERY allow passes through this one function, and each begins with a
# known-answer fork: if `$(printf k)` does not come back `k`, forks are failing RIGHT NOW and whatever "safe"
# verdict was just reached may have been computed from empty substitutions, so fault instead of allowing.
# Defence in depth behind the chokepoint faults (`_guard_fault` in guard-core.sh); it cannot see a failure that
# had already cleared by this point. A fault here exits 2 with `_GUARD_DECIDED` unset, so the trap also yields 2.
allow() {
  [ -z "$_GUARD_FAULTED" ] || _guard_fault allow-after-fault
  [ "$(printf k)" = k ] || _guard_fault allow-probe
  # A USR1 that arrived during the probe's own fork is handled at the next command boundary, i.e. here:
  [ -z "$_GUARD_FAULTED" ] || _guard_fault allow-after-fault
  _GUARD_DECIDED=yes; exit 0
}

# _guard_read <site> <jq-expr>: read one jq expression over $INPUT into $_GR (trailing newlines stripped, as
# `$(…)` always did). A failed read FAULTS instead of becoming "" — an empty value is indistinguishable from
# "nothing dangerous". The expression is wrapped to emit a trailing `x`, so a read that ran and found an empty
# value (`""`, `"\n"`, an absent field) is told apart from one that never ran (no output at all, e.g. the
# producer fork failed and jq read an empty stdin). $_GR_RAW keeps the value exactly (newlines included).
# TYPE: only a string, or null/absent (read as ""), is a value the guard can judge. Any other JSON type (an array
# `["rm","-rf","conformance"]`, a number, an object) FAULTS at site `input-type` — `tostring` used to turn an array
# into compact JSON text that no deny rule matched, an allow where main denied. jq's runtime error is rc 5.
# ONE jq read per field, with its own rc check and `x` sentinel. The trailing-newline strip is NOT a shell loop
# (O(n^2) in agent-controlled newlines: 64k newlines took 117 s on bash 3.2); see `_guard_read`.
_GR_NORM='if type == "string" then . elif . == null then "" else error("type") end'
_guard_read_one() {   # <site> <full-jq-program>  -> sets $_gr_x (value + trailing x)
  _gr_rc=0; _gr_x=$(printf '%s' "$INPUT" | jq -r "$2" 2>/dev/null) || _gr_rc=$?
  [ "$_gr_rc" != 5 ] || _guard_fault input-type
  [ "$_gr_rc" = 0 ] || _guard_fault "$1"
  [ -n "$_gr_x" ] || _guard_fault "$1"
}
_guard_read() {
  _guard_read_one "$1" "($2) | $_GR_NORM | . + \"x\""
  _GR_RAW=${_gr_x%x}
  # ONE jq per field. The stripped form comes from the shell: a command substitution removes trailing newlines
  # exactly as main's `$(jq …)` did, in linear time (printf is a builtin; the substitution is the only fork, and
  # its failure is a non-zero rc). Empty here is legitimate for a whitespace-only value, so rc is the test.
  _GR=$(printf '%s' "$_GR_RAW") || _guard_fault "$1"
}

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
  # GUARD-QUOTED-EXEC-INTERMITTENT: a failed (or empty) tool-name read used to fall into deny_if_mutating's
  # `*) allow`. A real call always names its tool, so an empty read here is a fault, never "not mutating".
  _gq_name=$(tool_name_grep) || _guard_fault tool-name-read
  [ -n "$_gq_name" ] || _guard_fault tool-name-read
  deny_if_mutating "$_gq_name" "jq is required to evaluate tool safety; install jq"
fi
if ! TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null); then
  emit_deny "agent-guard: tool input is not valid JSON — cannot verify safety; denying (DEVELOPMENT-PROCESS.md 13)."
fi
# The jq read above exits 0 with "" when its producer fork failed (jq saw an empty stdin) — and "" reaches
# the `*) allow` arm. A harness event always names its tool: an empty name is a fault.
[ -n "$TOOL" ] || _guard_fault tool-name-read

case "$TOOL" in
  Bash)
    _guard_read command-read '.tool_input.command // ""'
    # An EMPTY command is a fault, not an allow: Claude Code never sends one, so an empty value is only ever a
    # failed read (it cannot be told apart from "" by value). A whitespace-only command ("\n", " ", "\t") is a
    # real, non-empty value and is judged as before — the guard allows it, and $_GR already holds it trimmed.
    [ -n "$_GR_RAW" ] || _guard_fault command-read-empty
    CMD=$_GR
    # GUARD-CWD-CONFIDENCE-UNKNOWN Face C. `cwd` is a TOP-LEVEL PreToolUse field (a sibling of
    # `tool_name`), not part of `tool_input` — which is the whole reason it is trustworthy here: the
    # model authors `tool_input` and the harness authors this. Still no deny logic in the adapter:
    # it forwards a string and the core decides. Absent ⇒ empty ⇒ the core's pre-slice behaviour.
    _guard_read cwd-read '.cwd // ""'
    CWD=$_GR
    if reason=$(guard_check_command "$CMD" "$CWD"); then allow; else emit_deny "$reason"; fi ;;
  Write|Edit|NotebookEdit|MultiEdit)
    # MultiEdit folded in (C5 GUARD-TOOL-COVERAGE, design §2 Part A / vet Q2): its write surface is a
    # single .tool_input.file_path (+ an edits[] array, no multi-target), the same field Edit writes,
    # so guard_check_path covers it completely — a DIFFERENT tool name reaching the SAME write route.
    _guard_read file-path-read '.tool_input.file_path // .tool_input.notebook_path // ""'
    FP=$_GR
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
    _guard_read grep-path-read '.tool_input.path // ""'
    RGPATH=$_GR
    _guard_read grep-glob-read '.tool_input.glob // ""'
    RGGLOB=$_GR
    if [ -n "$RGPATH" ] && ! reason=$(guard_check_read "$RGPATH" "$PROTECTED_ROOT"); then emit_deny "$reason"; fi
    if [ -n "$RGGLOB" ] && ! reason=$(guard_check_read "$RGGLOB" "$PROTECTED_ROOT"); then emit_deny "$reason"; fi
    allow ;;
  Read)
    _guard_read file-path-read '.tool_input.file_path // ""'
    FP=$_GR
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
    _guard_read skill-read '.tool_input.skill // .tool_input.name // ""'
    SK=$_GR
    # guard_check_skill ALWAYS prints a token first (`allow`, `ask` or `deny`), so an empty token is a failed fork.
    v=$(guard_check_skill "$SK") || _guard_fault skill-check
    tok=$(printf '%s' "$v" | head -n1) || _guard_fault skill-token
    [ -n "$tok" ] || _guard_fault skill-token
    reason=$(printf '%s' "$v" | sed -n '2,$p')
    case "$tok" in
      ask)  emit_ask "$reason" ;;
      deny) emit_deny "$reason" ;;
      *)    allow ;;
    esac ;;
  *)
    allow ;;
esac
