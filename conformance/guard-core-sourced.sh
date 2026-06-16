#!/bin/sh
# guard-core-sourced.sh — assert every guard consumer sources the SINGLE deny-matrix
# core (no forked/duplicated matrix). Makes single-source-of-truth executable: a
# divergence becomes a CI failure, not a code-review hope. DEVELOPMENT-PROCESS.md §13.
set -eu

CORE=".claude/hooks/guard-core.sh"
[ -f "$CORE" ] || { echo "FAIL: missing $CORE"; exit 1; }

fail=0
for consumer in ".claude/hooks/guard.sh" "hooks/pre-push" "scripts/kit-guard"; do
  if [ ! -f "$consumer" ]; then echo "FAIL: missing consumer $consumer"; fail=1; continue; fi
  # Require BOTH a reference to the core AND an actual POSIX source command (`. ` or `source `).
  # A mere comment mentioning guard-core.sh is not enough; an inlined/forked matrix has no
  # source line and fails. (Consumers may source indirectly via `. "$CORE"`, so we don't
  # require the path on the source line itself — the anti-redefinition check below closes the gap.)
  if grep -Eq 'guard-core\.sh' "$consumer" && grep -Eq '^[[:space:]]*(\.|source)[[:space:]]' "$consumer"; then
    echo "PASS: $consumer sources guard-core.sh"
  else
    echo "FAIL: $consumer does not source guard-core.sh (matrix may be forked)"; fail=1
  fi
done
# anti-fork: a consumer must NOT redefine the core's matrix functions.
for consumer in "hooks/pre-push" "scripts/kit-guard" ".claude/hooks/guard.sh"; do
  [ -f "$consumer" ] || continue
  if grep -Eq '^[[:space:]]*guard_check_(command|path|push)\(\)' "$consumer"; then
    echo "FAIL: $consumer redefines a guard_check_* function (forked matrix)"; fail=1
  fi
done

if [ "$fail" -ne 0 ]; then echo "FAIL: guard consumers are not all sourcing one core"; exit 1; fi
echo "OK: all guard consumers source the single deny-matrix core"
exit 0
