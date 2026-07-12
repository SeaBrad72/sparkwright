#!/bin/sh
# engineer-fixture.sh — deterministic null-LLM Engineer for the orchestrator-loop proof.
# Makes a checkable, slice-scoped edit in the assigned worktree and commits it. Real git
# work, no LLM. Disjoint file per slice => integration merges cleanly by construction.
# Usage: engineer-fixture.sh <slice-name> <worktree-path>
set -eu
slice="${1:?slice name required}"; wt="${2:?worktree path required}"
[ -d "$wt" ] || { echo "engineer-fixture: worktree missing: $wt" >&2; exit 1; }
# FIXTURE_RENAME_SRC: rename a shared source file to a slice-specific target (for the dueling-rename
# conflict proof — two slices renaming the same source to different targets must still be detected).
if [ -n "${FIXTURE_RENAME_SRC:-}" ]; then
  ( cd "$wt" && git mv "${FIXTURE_RENAME_SRC}" "renamed-by-${slice}.txt" \
      && git commit -q -m "build(${slice}): fixture rename ${FIXTURE_RENAME_SRC}" )
  echo "engineer-fixture: ${slice} renamed ${FIXTURE_RENAME_SRC} -> renamed-by-${slice}.txt"
  exit 0
fi
name="built-by-${slice}.txt"
[ -n "${FIXTURE_CONFLICT_FILE:-}" ] && name="${FIXTURE_CONFLICT_FILE}"
f="$wt/$name"
printf 'slice %s built deterministically\n' "$slice" > "$f"
( cd "$wt" && git add "$name" && git commit -q -m "build(${slice}): fixture engineer artifact" )
echo "engineer-fixture: ${slice} -> ${f}"
