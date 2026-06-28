# Skill-spine brick #8 — the kit's own `debugging` skill (Phase 2)

**Date:** 2026-06-28
**Epic / slice:** E3 → **skill-spine brick #8** — the kit's own `systematic-debugging`-equivalent. First brick of **Skill-Spine Phase 2** (the craft gaps the comprehensiveness assessment surfaced: debugging, evals, discovery — completing the loop's coverage beyond the build-middle). Toward [[self-hosting-commitment]] (zero superpowers; E10 acceptance).
**Status:** Design converged — **designed by dogfooding `skills/design/SKILL.md`** (7th self-host use), owner-ratified 2026-06-28 (single-seat Engineer). Ready for the implementation plan (dogfoods `skills/plan/SKILL.md`).
**Tracked here** because the skill spine + the E10 self-host test depend on the convention, and it must be resumable cold.

**Reads-first for a cold resume:** [[reprioritized-backlog]] (the Phase-2 plan + ordering), brick #7's design doc (`docs/architecture/2026-06-28-using-skills-keystone-design.md`, the convention this mirrors), the shipped 7-skill spine (`skills/{design,plan,tdd,review,worktrees,verification,using-skills}/SKILL.md`), the shared verifier (`conformance/orchestrator-loop-wired.sh`), and the seat this wires (`agents/engineer.agent.md`). The source it replaces is superpowers `systematic-debugging`.

## 0. Why this slice (the decision trail)

The 7-skill spine (v3.63.0) covers the loop's BUILD MIDDLE (Plan → Build → Review) but the comprehensiveness assessment (2026-06-28) found the loop's crosscuts and edges covered only by gates/templates/standards, never a craft skill. **`debugging` is the highest-confidence, cheapest gap** — a build-loop crosscut every Engineer needs. `tdd` says "write a test, make it pass"; it does NOT say "this is mysteriously failing / prod is down — find root cause without flailing." superpowers ships `systematic-debugging` as a top-tier process skill and the kit leans on it but ships no equivalent. Brick #8 closes that, Engineer-wired, and is Phase-2 brick #1 (before evals #9, discovery #10, then E10).

### Wiring (owner-ratified 2026-06-28): single-seat Engineer
The Engineer is the seat that debugs (builds + fixes). Single-seat like `tdd` — the Orchestrator's "don't trust the subagent's report" integration instinct already lives in `verification` (confabulation-proofing), so the Orchestrator is not separately wired for debugging. Dual-seat was considered and declined: integration-failure triage is still root-cause debugging (the same craft), not a distinct gate.

### Intent (unchanged): FULL REPLACEMENT, not enhancement
Zero runtime dependency on superpowers; acceptance = E10.

## 1. What this slice is
Author the kit's **eighth own skill — `debugging`**: the craft of finding a bug's root cause before fixing it, invoked by the Engineer. **FLOOR-only** (invoke-by-read).

### Name: `debugging`
Short, parallels the spine. (`skills/debugging/SKILL.md`.) Note: superpowers is `systematic-debugging`; the kit's bare `debugging` is itself a distinctiveness marker (`name: debugging` ≠ `name: systematic-debugging`).

## 2. The skill's content — where the kit *improves on* superpowers (the real value)

`skills/debugging/SKILL.md` keeps the proven spine — the Iron Law (no fix without root-cause investigation first); read the actual error/stack trace; reproduce consistently; check recent changes; controlled one-change-at-a-time experiments — and bakes in the kit's own tie-ins (the connective tissue a generic copy lacks):

- **Root cause, not symptom.** `root cause` first; a symptom patch is failure. Read error messages completely before theorizing.
- **★ A bug becomes a failing test FIRST (the distinctive kit framing).** Reproduce the bug as a **`regression test`** that goes red *before* the fix and green *after*. Debugging feeds the kit's **non-vacuity law**: a fix is not "done" until a test that reproduces the bug flips red→green. This explicitly chains `debugging → skills/tdd/SKILL.md` (write the failing test) → `skills/verification/SKILL.md` (evidence before claiming fixed). The connective tissue across the spine.
- **Controlled experiments — `one hypothesis` at a time.** Change one thing; gather evidence before theorizing (ties to `verification`'s evidence-before-claims — read the actual output, don't assume).
- **Bounded, then escalate (don't thrash).** After repeated failed hypotheses, step back / escalate rather than flail — ties to the kit's runaway-guard + escalation discipline (raise, don't barrel through).

This is "take inspiration, improve, make it inherent": root-cause-first debugging reframed so a bug always produces a red→green regression test (the non-vacuity law applied to bug-fixing), chained to the kit's own tdd + verification skills — not a standalone debugging checklist.

## 3. Wiring (single-seat — Engineer)
- **Engineer def:** add a debugging reference alongside the existing tdd/verification chain — when a test fails or a bug appears, follow the kit's own `skills/debugging/SKILL.md` (root cause first; reproduce as a failing regression test before fixing). Edit `agents/engineer.agent.md` (FLOOR) + `.claude/agents/engineer.md` (native). The verifier asserts the Engineer def references the skill.
- **Guard:** none — `skills/*` already in `is_control_plane_path` + both shell-redirect regexes; `skills/debugging/SKILL.md` is agent-immutable for free (confirm-don't-add).

## 4. Conformance (right-weighted — no new gate, no new claim)
- **Extend the `skill-spine` claim** text → "… + `debugging` skill (`skills/debugging/SKILL.md`) … referenced by the engineer (TDD + evidence-before-claims **+ debugging**) … bricks **#1–8** …".
- **Extend `conformance/orchestrator-loop-wired.sh`:** add `check_debugging_skill "$DEBUGGING_SKILL_FILE" "$ENGINEER_DEF"` asserting the skill exists + ASCII-safe kit-distinctive markers + the Engineer def references it. Candidate markers (locked at plan time, `grep -qF`, ASCII): `name: debugging`, `root cause`, `reproduce`, `regression test`, `one hypothesis`. A verbatim superpowers copy fails (`name: systematic-debugging`; lacks the regression-test/one-hypothesis kit framing).
- **Non-vacuity — 2 new cases:** **case 18** (marker teeth: drop `regression test` → exit 1) + **case 19** (Engineer omits the reference → exit 1). Cases 1–17 fixtures gain a conformant debugging skill + Engineer reference.
- **Extend `docs/operations/orchestration.md`** — the Engineer follows `skills/debugging/SKILL.md` for root-cause debugging — bricks #1–8.

## 5. Honest ceiling & scope (named, not built)
- **Provided + structurally-proven; quality un-gateable** — correct for a skill (the check proves the skill exists, is kit-distinctive, and the Engineer references it; it cannot prove an agent actually debugs systematically at runtime).
- **Single-seat, deliberately** — Engineer only; the Orchestrator's "don't trust the report" instinct is `verification`, not duplicated here.
- **Bootstrap** — the kit's design + plan skills produced this slice (7th dogfood).
- **FLOOR-only-first** — formal `skills` adapter dimension still deferred.
- **Phase-2 position** — brick #1 of 3 (debugging → evals → discovery), then E10. Heavy AI/observability infra (E6/E5) stays separate from these cheap FLOOR craft bricks.

## 6. Build approach
Control-plane slice (new `skills/debugging/SKILL.md`; engineer defs ×2 — FLOOR + native; `conformance/orchestrator-loop-wired.sh` + `conformance/claims.tsv` + `docs/operations/orchestration.md`; version finishing **3.63.0 → 3.64.0**) → **AMBER `apply.py`**, clone dry-run incl. shellcheck + `verify --require` → **dual review** (reviewer: is the skill genuinely the kit's root-cause debugging craft + the conformance non-vacuous incl. cases 18/19; security: low surface — read-only guidance, confirm `skills/` immutability holds) → **light 5-lens meta-control panel #15** (A5) → **fold the governance close INTO the feature PR** (standing process). Subagent-driven build; the human applies/merges/release-tags (run `release-tag.sh` only after `git checkout main && git pull`).

## 7. Convergence record (owner-ratified 2026-06-28)
Designed by dogfooding `skills/design/SKILL.md` (7th self-host use). `debugging` = root-cause-first craft, single-seat Engineer (the builder debugs; the Orchestrator's integration instinct is already `verification`). The skill reframes debugging so a bug always produces a red→green **regression test** (the non-vacuity law applied to bug-fixing), chained to the kit's own tdd + verification skills. Right-weighted conformance (extend the shared verifier + the one `skill-spine` claim; +case 18 marker-teeth + case 19 reference-teeth). FLOOR-only. First brick of Skill-Spine Phase 2. **Next: the implementation plan, dogfooding `skills/plan/SKILL.md`.**
