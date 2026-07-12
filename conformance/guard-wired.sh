#!/bin/sh
# guard-wired.sh — verify the agent runtime guard is ACTUALLY wired in a project.
#
# The kit's runtime safety rests on the .claude/ PreToolUse guard hook. This check
# fails closed if the guard isn't wired, so a project — especially a brownfield repo
# with prod credentials already configured — cannot run agents unprotected. Run
# anytime; also invoked by inception-done.sh (the Inception gate). See docs/adoption/brownfield.md.
#
# Beyond presence, it STRUCTURALLY validates (via jq) that the PreToolUse hook whose
# command runs guard.sh has a matcher that ADMITS the mutating tools (Bash/Write/Edit/
# NotebookEdit). A matcher like "Read" would leave the guard DARK for mutating calls
# while still "mentioning" guard.sh — the false-green this check now closes. jq-absent
# is honest UNVERIFIED (exit 2), never a silent pass — matching verify.sh's three-state
# contract (and the guard hook itself requires jq, so jq-absent means the guard can't run).
#
#   sh conformance/guard-wired.sh [project-dir]   (default: .)
#   sh conformance/guard-wired.sh --selftest
# Exit: 0 = wired · 1 = NOT wired (dark) · 2 = UNVERIFIED (jq absent). POSIX sh; dash-clean.
set -eu

# Mutating tools the matcher MUST admit (mirror .claude/settings.json + guard.sh deny_if_mutating).
# guard.sh classifies mcp__* as mutating, so a matcher that omits the mcp__ branch (e.g. the older
# brownfield snippet) would leave the whole delete/deploy/exfil MCP class DARK — that must FAIL.
# TWO divergent MCP tokens (different server AND action) force a genuine mcp__* wildcard: an
# over-narrow matcher like mcp__server__.* or mcp__.*__action admits one but not the other -> FAIL.
MUTATING_TOOLS='Bash Write Edit NotebookEdit mcp__alpha__read mcp__beta__write'

check_dir() {
  dir="$1"
  S="$dir/.claude/settings.json"
  H="$dir/.claude/hooks/guard.sh"
  fail=0
  unverified=0

  if [ ! -f "$S" ]; then
    echo "FAIL: $S missing — no .claude/ settings to register the guard"; fail=1
  elif ! grep -q 'PreToolUse' "$S" || ! grep -qE '"command".*guard\.sh' "$S"; then
    # require guard.sh inside a "command" value (an actually-invoked hook), not a stray
    # mention elsewhere in the JSON — closes a false-pass on a guard.sh reference in prose.
    echo "FAIL: $S does not register the guard (need a PreToolUse hook whose command runs guard.sh)"; fail=1
  else
    echo "PASS: guard registered as a PreToolUse hook in settings.json"
    # STRUCTURAL: the matcher of the guard.sh hook must admit the mutating tools. A green
    # "guard wired" must not be possible with a matcher (e.g. "Read") that never routes a
    # mutating call to the hook. Use the matcher as an ERE and require each tool to match it.
    if command -v jq >/dev/null 2>&1; then
      matcher=$(jq -r '.hooks.PreToolUse[]? | select(any(.hooks[]?; (.command // "") | test("guard\\.sh"))) | .matcher // empty' "$S" 2>/dev/null | head -n1)
      if [ -z "$matcher" ]; then
        echo "FAIL: could not resolve the matcher of the PreToolUse hook that runs guard.sh"; fail=1
      else
        missing=''
        # Anchored full-match (^(...)$) mirrors Claude's tool-name matching, so a degenerate
        # matcher like '.' can't false-pass and '.*' (admits all) correctly passes.
        for t in $MUTATING_TOOLS; do
          printf '%s\n' "$t" | grep -Eq "^($matcher)$" 2>/dev/null || missing="$missing $t"
        done
        if [ -n "$missing" ]; then
          echo "FAIL: guard matcher '$matcher' does not admit mutating tool(s):$missing — the guard would be DARK for them"; fail=1
        else
          echo "PASS: guard matcher '$matcher' admits the mutating tools (Bash/Write/Edit/NotebookEdit/mcp__*)"
        fi
      fi
    else
      echo "UNVERIFIED: jq absent — cannot structurally confirm the matcher admits mutating tools; install jq"
      unverified=1
    fi
  fi

  if [ ! -f "$H" ]; then
    echo "FAIL: $H missing — the guard hook script is absent"; fail=1
  elif ! sh -n "$H" 2>/dev/null; then
    echo "FAIL: $H is not a valid sh script"; fail=1
  else
    echo "PASS: guard hook present and parses"
  fi

  if [ "$fail" -ne 0 ]; then
    echo "guard-wired: FAIL — the runtime guard is NOT active; agents would run unprotected (see docs/adoption/brownfield.md)" >&2
    return 1
  fi
  if [ "$unverified" -ne 0 ]; then
    echo "guard-wired: UNVERIFIED — presence OK but the matcher was not structurally confirmed (install jq)" >&2
    return 2
  fi
  echo "guard-wired: OK (PreToolUse guard hook registered, matcher admits mutating tools, hook present)"
  return 0
}

# mktemp fixtures; outcomes asserted. Fixtures LEFT in place (no rm -rf; 7e guard).
selftest() {
  st=0
  base=$(mktemp -d)

  # mk <dir> <matcher>: a project whose PreToolUse guard.sh hook uses <matcher> + a valid guard.sh
  mk() {
    _d="$1"; _m="$2"; mkdir -p "$_d/.claude/hooks"
    printf '{"hooks":{"PreToolUse":[{"matcher":"%s","hooks":[{"type":"command","command":"sh .claude/hooks/guard.sh"}]}]}}\n' "$_m" > "$_d/.claude/settings.json"
    printf '#!/bin/sh\nexit 0\n' > "$_d/.claude/hooks/guard.sh"
  }

  d="$base/full"; mk "$d" 'Bash|Write|Edit|NotebookEdit|mcp__.*'
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest PASS: full matcher -> wired"; else echo "selftest FAIL: full matcher should be wired"; st=1; fi

  d="$base/wild"; mk "$d" '.*'
  if check_dir "$d" >/dev/null 2>&1; then echo "selftest PASS: .* matcher -> wired"; else echo "selftest FAIL: .* matcher should be wired"; st=1; fi

  # the older brownfield snippet (named tools, no mcp__ branch) must FAIL — the MCP class is dark
  d="$base/nomcp"; mk "$d" 'Bash|Write|Edit|NotebookEdit'
  if check_dir "$d" >/dev/null 2>&1; then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ]; then echo "selftest PASS: no-mcp matcher -> FAIL (MCP class dark)"; else echo "selftest FAIL: no-mcp matcher should FAIL (got $rc)"; st=1; fi

  # a degenerate single-char matcher must FAIL (anchored full-match, not substring)
  d="$base/degenerate"; mk "$d" '.'
  if check_dir "$d" >/dev/null 2>&1; then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ]; then echo "selftest PASS: '.' matcher -> FAIL (anchored, not substring)"; else echo "selftest FAIL: '.' matcher should FAIL (got $rc)"; st=1; fi

  # an over-narrow mcp matcher (one server only) must FAIL — needs a true mcp__* wildcard
  d="$base/narrowmcp"; mk "$d" 'Bash|Write|Edit|NotebookEdit|mcp__github__.*'
  if check_dir "$d" >/dev/null 2>&1; then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ]; then echo "selftest PASS: narrow-mcp matcher -> FAIL (needs mcp__* wildcard)"; else echo "selftest FAIL: narrow-mcp should FAIL (got $rc)"; st=1; fi

  d="$base/dark"; mk "$d" 'Read'
  if check_dir "$d" >/dev/null 2>&1; then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ]; then echo "selftest PASS: Read-only matcher -> FAIL (dark)"; else echo "selftest FAIL: Read-only matcher should FAIL (got $rc)"; st=1; fi

  d="$base/partial"; mk "$d" 'Bash'
  if check_dir "$d" >/dev/null 2>&1; then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ]; then echo "selftest PASS: Bash-only matcher -> FAIL (Write/Edit dark)"; else echo "selftest FAIL: Bash-only matcher should FAIL (got $rc)"; st=1; fi

  d="$base/empty"; mkdir -p "$d"
  if check_dir "$d" >/dev/null 2>&1; then rc=0; else rc=$?; fi
  if [ "$rc" -eq 1 ]; then echo "selftest PASS: no settings -> FAIL"; else echo "selftest FAIL: no settings should FAIL (got $rc)"; st=1; fi

  if [ "$st" -ne 0 ]; then echo "guard-wired --selftest: FAIL" >&2; return 1; fi
  echo "guard-wired --selftest: OK (full/wildcard wired; no-mcp/degenerate/Read-only/partial/missing fail; fixtures left in $base)"
  return 0
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *)          check_dir "${1:-.}"; exit $? ;;
esac
