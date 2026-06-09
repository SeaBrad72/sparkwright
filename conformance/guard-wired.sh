#!/bin/sh
# guard-wired.sh — verify the agent runtime guard is ACTUALLY active in a project.
#
# The kit's runtime safety rests on the .claude/ PreToolUse guard hook. This check
# fails closed if the guard isn't wired, so a project — especially a brownfield repo
# with prod credentials already configured — cannot run agents unprotected. Run
# anytime; also invoked by inception-done.sh (the Inception gate).
# See docs/adoption/brownfield.md.
set -eu

DIR="${1:-.}"
S="$DIR/.claude/settings.json"
H="$DIR/.claude/hooks/guard.sh"
fail=0

if [ ! -f "$S" ]; then
  echo "FAIL: $S missing — no .claude/ settings to register the guard"; fail=1
elif ! grep -q 'PreToolUse' "$S" || ! grep -qE '"command".*guard\.sh' "$S"; then
  # require guard.sh inside a "command" value (an actually-invoked hook), not a stray
  # mention elsewhere in the JSON — closes a false-pass on a guard.sh reference in prose.
  echo "FAIL: $S does not register the guard (need a PreToolUse hook whose command runs guard.sh)"; fail=1
else
  echo "PASS: guard registered as a PreToolUse hook in settings.json"
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
  exit 1
fi
echo "guard-wired: OK (PreToolUse guard hook registered and present)"
exit 0
