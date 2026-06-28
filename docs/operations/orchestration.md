# Orchestration — the thin 4-seat loop (E3a)

**Status:** E3a reference capability — the *thin* slice of the kit's agent-orchestration epic. It ships the **Orchestrator + Engineer×N + Reviewer + Security** loop as fresh-authored, harness-neutral, conformance-held capability. Wider roster + hardened containment land in later E3 slices (see `docs/architecture/2026-06-22-e3-agentic-orchestration-design.md` and `…-2026-06-26-e3a-orchestrator-loop-design.md`).

## What it is

A founder hands the **Orchestrator** an epic. It slices the epic into disjoint, independently-testable increments, **fans out** an Engineer per slice (each in an isolated git worktree), **meters** every step through the runaway kill-switch, **integrates** the diffs, convenes **Reviewer + Security** on the merged result, and emits an OTel trace the operate-loop scorecard reads. The guardrails are what let you floor it: many agents at once *because* nothing escapes the rails.

## Who drives, what's mechanical

- **The LLM Orchestrator drives.** It follows `agents/orchestrator.agent.md` (Claude binding: `.claude/agents/orchestrator.md`) and makes the judgment calls — slicing, fan-out width, conflict resolution — dispatching **real** Engineer subagents.
- **Harness-neutral shell mechanics** are the substrate the Orchestrator calls: `scripts/orchestrator-run.sh` (worktree-per-agent + the `runaway-guard.sh step` meter + bracketed span emission + clean-merge integration).

## The roster & lifecycle

One **standing** Orchestrator; the specialists are **ephemeral** subagents — dispatched fresh with a Task-Context-Contract, run to completion, return one artifact, context discarded. An agent's **span = its lifetime**.

| Seat | Skills | Spun up | Spun down |
|---|---|---|---|
| **Orchestrator** | slicing (INVEST), fan-out, worktree mechanics, integration | run start (standing) | run end |
| **Engineer ×N** | TDD red→green, self-verify | fan-out, one per slice (parallel worktrees) | returns its diff |
| **Reviewer** | code-review, §14 gates | after integration | on verdict |
| **Security** | threat-model (early, if sensitive) **+** security-review (Ship) | per hat | on verdict |

`builder ≠ reviewer` is enforced by the spin model — Reviewer/Security are spun *fresh*, never a reused Engineer. The fix-loop (NEEDS-FIXES) re-spins a fresh Engineer with the findings in its TCC — no state carried (which is why ephemeral subagents suffice; persistent agent-memory is a later slice).

## How to invoke

- **Live (Claude):** dispatch the `orchestrator` subagent on an epic; it drives the loop, dispatching real `engineer` subagents.
- **Mechanics directly:** `sh scripts/orchestrator-run.sh sliceA sliceB` drives the loop in the current repo (the Orchestrator's `ROLE_RUNNER` is a real engineer dispatch; the default is the deterministic fixture).
- **Representative demo / CI:** `sh scripts/orchestrator-run.sh` runs a self-isolating demo (throwaway git repo) printing a trace path; `--selftest` runs the assertions. The golden-path `orchestrator-loop` job exercises both.

## Honest ceiling (the §10 containment status for E3a)

E3a proves the loop's **mechanics**, not that an LLM writes good code (not a gate-able property). What is **and isn't** hardened yet:

| §10 item | E3a status | Owner |
|---|---|---|
| Per-agent FS scope (worktree) | **used, not enforced** — real worktrees, isolation-as-convention | E4 (harness-sandbox; E3b declined) |
| Cost ceiling + kill-switch | **proven** — `runaway-guard.sh` wired at the loop | E3a |
| Conflict-safe parallel writes | **proven** — overlap detected + refused before integration (`kit.conflict`); no silent corruption | E3b ✅ |
| Guard at fleet scale | **out of scope** — 2 agents, not a fleet | E4 |
| Egress · scoped tokens · prod-SoD | **inherited** — E4a / E4a′ / E4e | done |

## Self-host trajectory

E3a is brick one of the kit's own superpowers-equivalent: we progressively shift the kit's own build onto this roster, dropping the external dependency incrementally. The **E10 capstone acceptance test** is "build a real slice using only the kit's own roster — zero superpowers." See `self-hosting` in the design doc §2.

## Design (Architect hat) — the kit's own skill
The Orchestrator follows the kit's own `skills/design/SKILL.md` then `skills/plan/SKILL.md` for design/planning (the Architect hat), the Engineer follows the kit's own `skills/tdd/SKILL.md` for test-driven build, and the Reviewer follows the kit's own `skills/review/SKILL.md` for code review, and the Orchestrator follows the kit's own `skills/worktrees/SKILL.md` for isolation, and the Engineer and Orchestrator both follow the kit's own `skills/verification/SKILL.md` for verification-before-completion (evidence-before-claims + confabulation-proofing) — bricks #1-6 of the kit's own skill spine.
