---
name: build
description: Use AFTER a plan is owner-approved and BEFORE integration — the kit's own subagent-driven execution craft: drive an INVEST-sliced plan to a built, reviewed, integrated branch. Successor to `skills/plan`.
---

# Build — drive an owner-approved plan to a reviewed, integrated branch (subagent-driven)

The kit's own execution craft: take an owner-approved, INVEST-sliced plan → a built, reviewed, integrated branch, by dispatching each task to a fresh executor and gating each diff with an independent reviewer. This is the conductor's loop between `skills/plan` and integration — the one that was hand-coded before it became a skill. It is the successor named by `skills/plan`'s terminal state ("handed to the build skill").

<!-- The frontmatter and the discipline phrases below are conformance-load-bearing:
     conformance/orchestrator-loop-wired.sh greps this file for these exact kit-distinctive
     markers (each quoted — preserve them verbatim, none may contain a pipe char or a TAB):
       "name: build"  "fresh executor per task"  "task brief as a file"
       "review between tasks"  "durable ledger"  "whole-branch review"
     Edits that drop or rename any of them can turn the skill-spine lock RED. -->

## When to use
After the plan skill's terminal state — an approved, INVEST-sliced plan whose tasks each carry their own test cycle — and before integration and verification. This is the conductor's craft for *running* that plan across all its tasks. Do **not** invoke it to build a single task test-first: that is `skills/tdd`, which a dispatched executor uses *within* one task. Build orchestrates across tasks; tdd builds one task.

## The loop (the discipline)
Read the owner-approved plan end to end (file structure, task order, which tasks may fan out, which are control-plane). Then run the loop task by task:

1. **Hand the task off as a file.** Each task's Task-Context-Contract is handed off as a **task brief as a file** — never pasted into a shared context window that compaction can erase. The file is the durable, resumable unit of work; the shared window is not.
2. **Dispatch a fresh executor per task.** Dispatch a **fresh executor per task** — the kit's `engineer` agent, with no accumulated context and no cross-task contamination. Each executor reads its brief file and builds its one task via `skills/tdd` (write the failing test, watch it fail, make it pass minimally, refactor).
3. **Review between tasks.** After each task, an independent reviewer gates the diff before the next task starts — **review between tasks**, builder ≠ reviewer. The executor is never the sole reviewer of its own work.
4. **Fix-loop until green.** Reviewer findings route back to a *fresh* executor (not the original's stale context) and are re-reviewed until the gate passes. Findings are **resolved, not waived**.
5. **Keep a durable ledger.** Record progress — tasks done / in-review / blocked — in a **durable ledger** file that survives context compaction, so the loop can be resumed cold by another conductor. The ledger is a file, not a memory of the run.
6. **Fan out only what is parallel-safe.** Dispatch tasks concurrently *only* when their file sets are disjoint and they share no mutable state. Defer to `skills/worktrees` for the parallel-safety rule and workspace isolation — do not restate it here.
7. **Final whole-branch review.** After all tasks integrate, run a final adversarial **whole-branch review** of the branch as a whole. Per-task green does not imply the branch is coherent — the integrated diff can drift, duplicate, or conflict in ways no single task's gate could see.
8. **Control-plane → GREEN brick + AMBER apply.py, actuated on the recorded GO.** Any task touching control-plane (guard / CI / conformance / claims / agent-or-skill defs / governance markers) is authored GREEN in `scratchpad/` as an idempotent `apply.py`; the agent **never silently commits control-plane** (never *without* a recorded GO). On the human's recorded **GO** the **agent runs it** — apply → commit → push → open PR → tag → `scripts/promotion-verify.sh record` → `check`; the **human** does the **GO** and — solo, control-plane only — the single `gh pr merge --admin` (the kill-switch the guard denies the agent). Ordinary/team work: the agent merges too, so the human does zero mechanical keystrokes. Version finishing (VERSION bump + README badge + CHANGELOG entry) folds into that apply.py so the release step cannot be skipped.

## build composes tdd
Different altitudes, no overlap. **`build`** orchestrates *across* all tasks of a slice — dispatch, review, integrate. **`tdd`** builds *one* task test-first *within* a dispatched executor. `build` invokes `tdd` once per task; the two never do each other's job. This is why naming the skill `build` does not collide with `tdd`: the scope (whole plan vs. one task) is the boundary.

## Git hygiene
- **Pre-branch `git fetch origin main`.** Refresh the trunk before cutting a feature branch, so the branch is not born stale.
- **A conflicting PR skips CI** — a green badge on a branch that conflicts with `main` means nothing (the checks never ran the merge). Re-check after rebasing onto current `main`.
- **Verify trunk after merge.** Run the conformance suite on `main` post-merge, not only on the branch — a branch-green slice can still land a red trunk.

## Honest ceiling
- **What is provable (structural):** the craft is *provided* — this SKILL.md exists, carries every load-bearing marker byte-identically, is indexed by `skills/using-skills/SKILL.md`, and is referenced by the owning seat (the Orchestrator). A generic subagent-driven-development paraphrase lacks the markers, so the non-vacuity check KILLs a generic copy. The agents-vs-skills rule is respected: `build` is a conductor *hat*, not a new standing seat.
- **What is NOT provable (un-gateable):** whether an agent actually *runs the loop* at runtime. Dispatch is harness-specific (the Agent/Task tool of a given platform), so the **FLOOR** is "invoke by reading the discipline" — read this file and follow it. A NATIVE harness binding that auto-dispatches is a **bonus**, never a FLOOR guarantee. Same ceiling as `skills/using-skills` and `skills/operating`: **provided + structurally proven; runtime loop-adherence un-gateable.** The discipline is kept harness-neutral (file handoffs, a fresh executor per task, review gates, a durable ledger) precisely so it holds on any harness even though concrete dispatch is platform-local.

## Rationalizations to refuse
| Rationalization | Why it fails |
|---|---|
| "I'll just keep the same context for the next task." | A **fresh executor per task** — no accumulated context. Cross-task contamination is how a later task inherits an earlier task's stale assumptions. |
| "I'll paste the task context into the chat instead of a file." | Hand each task off as a **task brief as a file**; a shared context window is erased by compaction and cannot be resumed cold. |
| "I built it, so I'll review my own diff." | **Review between tasks**, builder ≠ reviewer. A self-review is not an independent gate. |
| "I'll just remember where the run is up to." | Keep a **durable ledger** file — memory does not survive compaction; the ledger is what lets the loop resume cold. |
| "Every task passed its own gate, so the branch is done." | Run the final **whole-branch review** — per-task green does not imply the integrated branch is coherent. |
| "I'll fan these out; they're basically independent." | Fan out only disjoint-file-set / no-shared-mutable-state tasks; defer to `skills/worktrees` for the parallel-safety rule — otherwise serialize. |
| "I'll commit the conformance edit directly to save a round-trip." | Control-plane never lands as a silent agent commit — author it GREEN in scratchpad as an idempotent `apply.py`; the agent runs it (apply → commit → push → PR → tag → record → check) only **on the human's recorded GO**, and solo the human keeps the one `gh pr merge --admin` keystroke. |

## Terminal state
Every plan task built (each via `skills/tdd` by a **fresh executor per task**, dispatched with a **task brief as a file**), gated by an independent **review between tasks** (builder ≠ reviewer, findings resolved not waived), progress recorded in a **durable ledger** that survives compaction, all tasks integrated, and a final **whole-branch review** passed. Any control-plane change is authored as an idempotent `apply.py` (version finishing folded in) that the **agent runs on the human's recorded GO** — apply → commit → push → PR → tag → record → check — the human doing the GO and, solo, the single `gh pr merge --admin`. A built, reviewed, integrated branch — with **nothing control-plane silently committed by the agent** (nothing without a recorded GO). Before the human Go/No-Go, if an increment carries a taste-surface (UI/UX/flow/working functionality/table), invoke `skills/demonstrate` — surface the working increment for the human's taste judgment and record the verdict in a UAT sign-off. On the human's recorded GO the terminal handoff is **approve→execute→log**: provide the means and wait, then on the recorded GO actuate the merge/tag (ordinary/team: the agent merges; **solo control-plane: the human does the single `gh pr merge --admin`**, the agent doing everything else), log the approval (`scripts/promotion-verify.sh record`), and verify `shipped == approved` (`scripts/promotion-verify.sh check`) — `builder ≠ ratifier`. Opening the PR moves the backlog item **`In Progress → In Review`** — the board edge where the conformance gate mandates a PR reference. On landing, the backlog item moves **`In Review → Done`** with the PR link.

**Capture friction at the boundary.** At every slice boundary (and again at an epic boundary), record any kit friction you hit — expected vs. happened, severity, where — to the project's `KIT-FEEDBACK.md` (from `templates/KIT-FEEDBACK-TEMPLATE.md`), stamped with the kit version and vehicle. This is an obligation, not a courtesy: capture it now, at the moment of friction, because a friction log reconstructed weeks later loses the cause. Relay's entire harvest exists only because this log was written live.
