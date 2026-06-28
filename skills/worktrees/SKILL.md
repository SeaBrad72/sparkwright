---
name: worktrees
description: Use BEFORE fanning out parallel Engineers or starting isolated feature work — the kit's own isolation skill (replaces, does not depend on, superpowers using-git-worktrees). The isolation craft, wired to the Orchestrator seat — detect-existing-first, native tools first, the kit's disjoint-set parallel-safety rule, and conflict-safe integration.
---

# Worktrees — isolation as a precondition the Orchestrator checks, not just a directory

The kit's own isolation skill: how to give each fanned-out Engineer a clean, independent workspace and re-integrate the results safely. The Orchestrator seat's craft (it *creates and ensures* isolation; the Engineer *operates within* an assigned worktree). Replaces (does not depend on) superpowers `using-git-worktrees`. Worktrees are the concrete mechanism; **isolation** is the principle.

<!-- The frontmatter and the discipline headings below are conformance-load-bearing:
     conformance/orchestrator-loop-wired.sh greps this file for kit-distinctive markers
     (name: worktrees, disjoint file sets, --no-renames, out-of-slice, native).
     Edits that drop or rename them can turn the skill-spine lock RED. -->

## When to use
Before fan-out (one workspace per parallel Engineer) and before any isolated feature work that must not disturb the main tree. Every fan-out gets isolation — a single-slice run still runs in its own workspace so a failed slice never corrupts the trunk.

## Detect existing isolation first
Check whether you are already isolated before creating anything. **Never nest** a worktree inside a worktree — re-use the current one. Guard against creating a worktree inside a submodule or another repo's tree (resolve the real toplevel first; refuse if it is not the intended repo). Creating-on-top is how phantom, unmanageable workspaces appear.

## Native tools first (never fight the harness)
Prefer the platform's `native` worktree/workspace mechanism when one exists; reach for `git worktree` only as the fallback when no native isolation is available. Using `git worktree add` on a harness that manages workspaces itself creates phantom state the harness cannot see or clean up — the kit's LLM/harness-neutrality stance applied to isolation. Whatever the mechanism, verify the new workspace path is ignored / out of the trunk's way before any Engineer writes to it.

## The kit's parallel-safety rule (the heart of the skill)
This is the Orchestrator's slicing heuristic, made the precondition of fan-out: **two slices are safely parallel only with disjoint file sets, no shared mutable state, and each independently testable.** If two candidate slices touch the same file, share mutable state, or cannot each be tested alone, they are **not** parallel-safe — serialize them. Isolation is something you *check before* fan-out, not merely a directory you hand out afterwards.

## Conflict-safe integration (the other half of isolation)
Isolation that only creates but never guards integration is half a discipline. Before merging a returned branch, detect overlap against the run's cut-point: `git diff --name-only --no-renames` for the integrated set vs. each incoming branch. If the changed-file sets intersect, **refuse fail-closed** — stamp a `kit.conflict` span and route the slice back rather than merging silently. No silent cross-slice corruption; the no-corruption floor is git's, the kit makes it proactive, observable, and locked.

## The Engineer boundary
Each Engineer stays inside its assigned worktree and makes **zero out-of-slice edits** — it returns a diff plus a self-verify report; the Orchestrator integrates (builder ≠ integrator). An out-of-slice edit breaks the disjoint-set guarantee the parallel-safety rule depends on, so it is a boundary violation, not a convenience.

## Metering
Every fanned-out step is metered through the runaway kill-switch — `scripts/runaway-guard.sh step`. A guard STOP halts further fan-out (raise-don't-barrel-through); isolation does not exempt a runaway slice from the budget ceiling.

## Honest ceiling
Isolation **bounds blast-radius; it is NOT a security sandbox.** A worktree limits accidental cross-slice writes — it is not containment, not a trust boundary, and not a defense against malicious code (that is the harness-sandbox concern, named elsewhere). Cleanup of unchanged trees is **best-effort and harness-owned** — do not assume a worktree is torn down for you; leave the trunk clean and let the harness reclaim workspaces.

## Terminal state
Each Engineer dispatched into its own verified-isolated workspace; the parallel-safety rule checked before fan-out; returned branches integrated only after a clean `--no-renames` overlap check, conflicts refused fail-closed. The Orchestrator owns creation and integration; the skill never merges on the Engineer's behalf.
