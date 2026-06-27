#!/bin/sh
# engineer-fixture.sh — deterministic null-LLM Engineer for the orchestrator-loop proof.
# Makes a checkable, slice-scoped edit in the assigned worktree and commits it. Real git
# work, no LLM. Disjoint file per slice => integration merges cleanly by construction.
# Usage: engineer-fixture.sh <slice-name> <worktree-path>
set -eu
slice="${1:?slice name required}"; wt="${2:?worktree path required}"
[ -d "$wt" ] || { echo "engineer-fixture: worktree missing: $wt" >&2; exit 1; }
f="$wt/built-by-${slice}.txt"
printf 'slice %s built deterministically\n' "$slice" > "$f"
( cd "$wt" && git add "built-by-${slice}.txt" && git commit -q -m "build(${slice}): fixture engineer artifact" )
echo "engineer-fixture: ${slice} -> ${f}"
