# Skill-spine brick #4 — the kit's own `review` skill (code review)

**Date:** 2026-06-28
**Epic / slice:** E3 → **skill-spine brick #4** (the kit's own code-review skill). Fourth brick of the kit's fresh-authored skill spine, toward the [[self-hosting-commitment]] (replace external superpowers; E10 = build a slice using only the kit's own roster + skills).
**Status:** Design converged — **designed by dogfooding `skills/design/SKILL.md`** (3rd self-host use), owner-ratified 2026-06-28. Ready for the implementation plan (which will dogfood `skills/plan/SKILL.md`).
**Tracked here** because the skill spine + the E10 self-host test depend on the convention, and it must be resumable cold.

**Reads-first for a cold resume:** [[self-hosting-commitment]], brick #3's design doc (`docs/architecture/2026-06-28-tdd-skill-design.md`, the convention this mirrors), the shipped skills (`skills/design|plan|tdd/SKILL.md`), the shared verifier (`conformance/orchestrator-loop-wired.sh`), and the seat this wires (`agents/reviewer.agent.md`).

## 0. Why this slice (the decision trail)

Bricks #1–2 wired the Orchestrator's Architect hat (design + plan); brick #3 wired the Engineer (tdd). Brick #4 is the next spine piece superpowers supplies — `requesting-code-review` → a kit-authored `review` skill — and it wires the **Reviewer** seat (the seat that reviews).

### Scope decision (owner-ratified 2026-06-28): `skills/review/` = the reviewing CRAFT, wired to the Reviewer
Superpowers `requesting-code-review` bundles two things: the *requesting* side (a controller dispatches a reviewer + acts on feedback) and the *reviewing craft* (how to review a change well). The kit splits them by the agents-vs-skills rule: the *requesting/dispatch* side is already the **Orchestrator's** responsibility ("convene Reviewer + Security"), so it is not a new skill; brick #4 is the **reviewing craft**, invoked by the **Reviewer** seat (and the security-reviewer as the security lens). This parallels brick #3 (tdd craft → Engineer) and keeps one-skill-one-responsibility. A combined `skills/code-review/` wired to the Orchestrator was rejected: it would blur requester-vs-reviewer and overlap the Orchestrator's existing convene responsibility.

### Intent (unchanged): FULL REPLACEMENT, not enhancement
Zero runtime dependency on superpowers; acceptance = E10.

## 1. What this slice is
Author the kit's **fourth own skill — `review`**: the craft of reviewing a change well, invoked by the Reviewer seat (and referenced by the security-reviewer as the security lens). **FLOOR-only** (invoke-by-read).

## 2. The skill's content — where the kit *improves on* superpowers (the real value)

`skills/review/SKILL.md` is **not a copy** of superpowers' `requesting-code-review` (which is mostly the *requester's* dispatch mechanics). It keeps the proven review-craft spine — review early/often; review a crafted diff (not session history); group findings by severity with `file:line` + a concrete fix; fix Critical/Important, note Minor; push back with reasoning if the reviewer is wrong — and **bakes in the kit's own hard-won disciplines as first-class steps:**

- **Adversarially VERIFY each finding before reporting.** The kit's non-vacuity/adversarial discipline applied to review: try to *refute* a finding (does it actually reproduce? is the path real?) before raising it. A finding you cannot substantiate is noise. (This is the connective tissue — the review-level instance of the same law brick #3 frames at the unit-test level.)
- **Confidence-based filtering.** Report only findings you are confident matter — signal over style-nitpicks and bikeshedding. A review drowning in Minors hides the Critical.
- **Builder ≠ reviewer + dual review.** Independence (DEVELOPMENT-PROCESS §12) — an agent never reviews-and-merges its own work; the reviewer + security-reviewer two-lens pattern (security is a distinct lens of the same craft).
- **Review the diff — behaviour, not style.** Scope to the change; DEVELOPMENT-STANDARDS §2 (security) / §5 (code quality) + the §14 CI gates are the rubric; assert behaviour, not implementation detail.
- **Severity rubric + honest single verdict.** Critical / Important / Minor, each `file:line` + a concrete fix; end with one clear verdict — **APPROVE** or **NEEDS-FIXES**. Never rubber-stamp; NEEDS-FIXES on any real Critical/Important.

This is "take inspiration, improve, make it inherent": review reframed around adversarial verification + confidence-filtering (the kit's own bar), not the requester's dispatch mechanics.

## 3. Wiring (mirrors #3, on the Reviewer)
- **Reviewer def (gated):** make "judges it fresh" concrete — "follow the kit's own `skills/review/SKILL.md`." Edit `agents/reviewer.agent.md` (FLOOR) + `.claude/agents/reviewer.md` (native). The verifier asserts the Reviewer def references the skill.
- **Security-reviewer def (ungated consistency):** a one-line reference — security review is the same craft through a security lens. Edit `agents/security.agent.md` + `.claude/agents/security-reviewer.md`.
- **Guard:** none — `skills/*` already in `is_control_plane_path` + both shell-redirect regexes; `skills/review/SKILL.md` is agent-immutable for free (confirm-don't-add).

## 4. Conformance (right-weighted — no new gate, no new claim)
- **Extend the `skill-spine` claim** text → "design + plan + tdd + review skills … bricks #1–4 …".
- **Extend `conformance/orchestrator-loop-wired.sh`:** add `check_review_skill "$REVIEW_SKILL_FILE" "$REVIEWER_DEF"` asserting the skill exists + ASCII-safe kit-distinctive markers + the **Reviewer** def references it. Candidate markers (locked at plan time, `grep -qF`, ASCII-only): `name: review`, `## When to use`, `Confidence`, `adversarial`, `builder`, `NEEDS-FIXES`. A generic requesting-code-review paraphrase fails.
- **New selftest case 9** (marker teeth: drop a marker → exit 1) + **case 10** (Reviewer omits the reference → exit 1 — the reference-teeth pattern brick #3's case 8 established).
- Update cases 1–8 fixtures so each builds a conformant review skill + Reviewer reference. Wired via the existing orchestrator-loop entries — no new registration surface.

## 5. Honest ceiling & scope (named, not built)
- **Provided + structurally-proven; quality un-gateable** — correct for a skill.
- **Bootstrap** — superpowers' `requesting-code-review` authored its own replacement; the kit's design + plan skills produced this slice (3rd dogfood). **Recursion to note:** the dual review *of this very slice* exercises the craft the skill encodes — a live proof-of-use.
- **FLOOR-only-first** — formal `skills` adapter dimension still deferred.
- **Requesting/dispatch side not duplicated** — it stays the Orchestrator's convene responsibility.
- **Spine remaining after #4** — using-git-worktrees, verification-before-completion, the META discovery skill (`using-superpowers`-equiv) → then E10.

## 6. Build approach
Control-plane slice (new `skills/review/SKILL.md`; reviewer defs ×2 gated + security defs ×2 ungated; `conformance/orchestrator-loop-wired.sh` + `claims.tsv` + `docs/operations/orchestration.md`; version finishing **3.59.0 → 3.60.0**) → **AMBER `apply.py`**, clone dry-run incl. shellcheck + `verify --require` → **dual review** (reviewer: is the skill genuinely the kit's review craft + the conformance non-vacuous incl. case 10; security: low surface — read-only guidance, confirm `skills/` immutability holds) → **light 5-lens meta-control panel #11** (A5) → **fold the governance close INTO the feature PR** (standing process). Subagent-driven build; the human applies/merges/release-tags (run `release-tag.sh` only after `git checkout main && git pull`).

## 7. Convergence record (owner-ratified 2026-06-28)
Designed by dogfooding `skills/design/SKILL.md` (3rd self-host use). `skills/review/` = reviewing craft wired to the Reviewer (agents-vs-skills + 1:1 + cohesion overrode a combined `skills/code-review/` on the Orchestrator). The skill reframes review around **adversarial verification + confidence-filtering** (the kit's bar) atop the proven severity/verdict spine. Right-weighted conformance (extend the shared verifier + the one `skill-spine` claim; +case 9 marker-teeth + case 10 reference-teeth). FLOOR-only. **Next: the implementation plan, dogfooding `skills/plan/SKILL.md`.**
