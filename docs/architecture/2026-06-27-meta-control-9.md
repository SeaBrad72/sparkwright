# Meta-control panel #9 — skill-spine brick #2 (the kit's own `plan` skill)

**Date:** 2026-06-27
**Trigger:** per-slice M verdict (condition A5) for skill-spine brick #2 (v3.58.0).
**Profile:** light (5-lens).
**Verdict:** **GO.**

Brick #2 = the kit's own `plan` skill (`skills/plan/SKILL.md`), a harness-neutral writing-plans-equivalent, FLOOR-only (invoke-by-read), referenced by the Orchestrator (Architect hat). **Designed by dogfooding `skills/design/SKILL.md`** — the first real use of the kit's own design skill (self-hosting milestone). Built AMBER; dual-reviewed (reviewer APPROVE + security-reviewer PASS); independently proven on a clone (verifier 6/6, `verify --require` 31 controls / 0 failed, idempotent, design markers preserved).

## The 5 lenses

| Lens | Verdict | Evidence |
|------|---------|----------|
| Honesty / no-overclaim | GREEN | Claim text scoped to "structural"; methodology-quality ceiling named (design §7). Bootstrap (superpowers used to author its own replacement) stated honestly. |
| Right-weight / anti-ceremony | GREEN | FLOOR-only; **zero** new gate/claim/guard/registry/export edits — reused brick #1's `skills/*` glob + the `skill-spine` claim. 11 files, +120/−26. Overrode brick #1's adapter-dimension earmark as build-ahead (right-weight beat a stale plan — the design skill earning its keep). |
| Enforcement-integrity / non-vacuity | GREEN | `check_plan_skill` keyed on `AMBER` (kit-signature marker a generic writing-plans copy lacks); selftest case 6 load-bearing (drops `AMBER` → exit 1, proven). Cases 1–5 still isolate their original defects (case 5 still fails design teeth). |
| Harness-neutrality | GREEN | Pure-markdown SKILL, invoke-by-read floor; native `.claude/agents` mirror is a bonus, not required. |
| Is-the-provable-thing-meaningful | GREEN | Reviewer adversarially judged the skill genuinely kit-distinctive (real INVEST/parallel-safety, control-plane→AMBER, conformance-non-vacuity, version-finishing, dual-review, honest-ceiling) — not a relabel. The dogfood (design skill used for real) is the meaningful thing. |

Standing "integration-capability / no-dead-ends" lens: **N/A** — no industry-standard integration surface in this slice.

## Findings

- **0 blockers · 0 High.**
- **1 Low — FIXED pre-ship:** the control-plane-completeness discipline text (folded into `skills/design/SKILL.md`) said "BOTH guard matchers (`is_control_plane_path` AND the two shell-redirect regexes)" — naming three locations as "both," the exact miscount the discipline exists to prevent. Corrected to "all three guard matchers" (security-reviewer Low). Re-proven on clone.
- **1 Low — BANKED (follow-on):** `check_plan_skill` (and pre-existing `check_skill`) has no negative selftest for the *orchestrator-reference* branch — proven live by the real CI run, so a non-vacuity completeness nit, not a hole. Add a case where the skill is conformant but the orchestrator def omits the reference → exit 1.

## Retro

- The design skill's right-weight lens overrode a prior-brick earmark (adapter dimension) — evidence the kit's own disciplines change real decisions when followed, not just decorate them.
- The two-brick spine now shows compounding payoff: brick #1's one-time `skills/*` guard glob + `skill-spine` claim made brick #2 need zero guard/registry/export work. Marginal cost of each future spine brick ≈ author the SKILL.md + one verifier check — which keeps the zero-superpowers E10 acceptance tractable.
- **Process note (release hygiene):** `scripts/release-tag.sh` was first run on the feature branch (pre-checkout of merged main), tagging the feature commit off-main; corrected by moving the tag onto the merge commit. Reinforces the "run release-tag.sh only after `git checkout main && git pull`" step in the release runbook.

**Next spine brick: #3 = the build/TDD skill** (test-driven-development-equivalent).
