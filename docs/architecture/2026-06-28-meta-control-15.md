# Meta-control panel #15 — skill-spine brick #8, the kit's own `debugging` skill (Phase 2, brick #1)

**Date:** 2026-06-28
**Trigger:** per-slice M verdict (condition A5) for skill-spine brick #8 (v3.64.0) — first brick of Skill-Spine Phase 2.
**Profile:** light (5-lens).
**Verdict:** **GO** — panel found GO-WITH-CONDITIONS (1 High, H1); **H1 was resolved in-slice before ship** (see §H1), so the slice ships as GO. 0 blockers.

Brick #8 = the kit's own `debugging` skill (`skills/debugging/SKILL.md`) — root-cause-first debugging reframed so a bug always becomes a red→green regression test, chaining `debugging → skills/tdd → skills/verification` (the kit's non-vacuity law applied to bug-fixing). Harness-neutral, FLOOR-only invoke-by-read, wired single-seat to the **Engineer**. Designed + planned by dogfooding the kit's own design/plan skills (7th self-host). Built AMBER; dual-reviewed (reviewer APPROVE + security-reviewer PASS); independently proven on a fresh clone (apply idempotent, SHA-256 payload match, shellcheck clean, selftest 19/19, `verify --require` 31 controls / 0 failed). Generic + adversarial `systematic-debugging`-paraphrase rejection reproduced; case 18 (marker teeth) flip-proven live; case 19 (reference teeth) non-vacuity substantiated by function-symmetry + env-wiring + call-site (live flip guard-blocked = guard working as designed).

## ★ H1 — the headline finding, and its in-slice resolution (the panel earning its keep)

**The panel caught a cross-brick coherence defect that both dual reviewers missed** (per-slice review is structurally local; catching global drift is exactly the panel's remit — the 2026-06-23 course-correction). Brick #8 grew the spine to a 7th content skill **without updating the brick-#7 discovery keystone** (`skills/using-skills/SKILL.md`), which still claimed it indexes "all six… exhaustive… stable because the spine is complete." Three coupled defects: **honesty** (a false self-claim — panel #14's "SPINE COMPLETE" framing was itself an over-claim Phase 2 falsified one slice later), **discoverability** (an agent consulting the keystone "before acting" would not be routed to the debugging skill), and **green-while-dark** (`check_keystone` had no assertion that the index covers the grown spine).

**Resolved in-slice (owner-ratified fix-now over fix-forward — honesty outranks batching):** the same `apply.py` now adds a `debugging` row to the keystone index, changes "six → seven" across the keystone, replaces the false "stable because the spine is complete" with "the index is exhaustive by design, and `check_keystone` enforces it, so every new skill brick must add its row here," and adds `skills/debugging` to `check_keystone`'s index loop (now 7 paths; case 16 index-teeth re-proven load-bearing). **A focused re-review then caught a follow-on** — the same false "six" survived one line over in `docs/operations/orchestration.md` + two verifier comments — also fixed (the ops-doc line made **count-neutral** to stop the drift at its source). Re-verified on a fresh clone: no stale spine-"six" anywhere, selftest 19/19, `verify --require` 0 failed, idempotent.

## The 5 lenses

| Lens | Verdict | Evidence |
|------|---------|----------|
| Scope-coherence & proportion | GREEN | 8th steady-state slice: 1 SKILL + extend the shared verifier (`check_debugging_skill` + cases 18/19) + extend the one `skill-spine` claim + surgical Engineer-def inserts + version finishing — no new gate/claim/guard (`skills/*` already control-plane). Single-seat Engineer correct (integration-triage is still root-cause debugging; the Orchestrator's "don't trust the report" lives in `verification`). Regression-test-first framing is genuinely distinctive (chains debugging→tdd→verification), not a repackaged checklist. |
| Honesty & over-claim | GREEN (after H1 fix) | Brick-#8 claims honest (honest ceiling names existence/distinctiveness/reference vs un-gateable runtime rigour; "replaces, does not depend on" gated on E10; no live superpowers runtime read). **H1 (the keystone's false "six/complete" claim across 4 surfaces — keystone, claim row [already neutral], ops doc, verifier comments) found and fixed in-slice.** |
| Enforcement integrity (green-while-dark) | GREEN (after H1 fix) | Cases 18/19 load-bearing (18 flip-proven live; 19 substantiated by symmetry — live flip guard-blocked). Generic + adversarial paraphrase rejected; teeth on high-entropy markers (`name: debugging`, `regression test`, `one hypothesis`). The keystone index drift hole (H1) is closed for debugging (`check_keystone` now enforces 7 paths; case 16 re-proven); the **structural** fix (`check_keystone` self-checks against every on-disk `skills/*`) is banked for brick #10. |
| Direction & sequencing | GREEN | Debugging is the right Phase-2 brick #1 (highest-confidence, cheapest loop-coverage gap; `tdd` ≠ root-cause craft). The loop-coverage thesis holds on execution. Phase-2 arc (debugging → evals → discovery → E10) sound; nothing to resequence. |
| Right-weighting & adoptability | GREEN | ~72-line FLOOR markdown, progressive disclosure intact, invisible to a vibe-coder until a bug; not bloat — covers a distinct loop phase at zero new infrastructure. |

Standing "integration-capability / no-dead-ends" lens: **N/A** — pure-markdown FLOOR skill + verifier extension.

## Findings

- **0 blockers.**
- **H1 (High) — discovery keystone not synced to the grown spine — RESOLVED IN-SLICE** (see §H1). Found by the panel, fixed in the same `apply.py`, follow-on caught by re-review and also fixed, independently re-verified on a clone.
- **Banked (not this slice):**
  - **Structural anti-drift (→ brick #10):** make `check_keystone` assert the index covers every on-disk `skills/*/SKILL.md`, so the index can never drift green as the spine grows — path-by-path enforcement is a stopgap.
  - **Standing rule:** *every spine brick updates the keystone index + its conformance tooth in the same slice* — the keystone is a cross-brick coupling point. Add to the skill-brick checklist / `MAINTAINING.md`.
  - **Cosmetic (display-only):** apply.py prints "changed 18 path(s)" (9 keystone string-swaps each append the same path to the CHANGED list); distinct files = 10. No extra files touched; left as-is to avoid churning proven apply logic.
  - **Process note:** the kit's own guard now reliably blocks the panel's/reviewer's *live* mutation probes of control-plane teeth — substantiate non-vacuity via symmetry + static analysis + the live-proven sibling case (guard working as designed, not a proof gap).
- **Standing caveat (not a finding):** FLOOR declaration-check ceiling — a hollow stub stuffing the marker strings passes; intrinsic, identical to bricks #1–7, named in the skill's honest ceiling. Real enforcement is the conformance/clone gate.

## Two ledgers

**Ledger 1 — verified-as-quality (ship with confidence):** apply clean + idempotent on a fresh clone (re-run no-op, VERSION 3.64.0); SHA-256 applied==reviewed source; shellcheck clean; selftest 19/19 (case 18 flip-proven, case 19 + case 16 substantiated); `verify --require` 31 controls / 0 failed; generic + adversarial paraphrase rejected; regression-test-first chain (debugging→tdd→verification) distinctive; no live superpowers runtime read; **H1 keystone-sync + ops-doc/verifier follow-on resolved and re-verified (no stale spine-"six" anywhere)**; honest ceiling consistent across SKILL/CHANGELOG/claim/keystone.

**Ledger 2 — fix-forward (ranked):** (1) structural `check_keystone` self-check against `skills/*` → brick #10; (2) bank the standing rule "every spine brick updates the keystone index + tooth in-slice"; (3) low/banked — FLOOR declaration-check ceiling; (4) low/banked/pre-existing — rename the `docs/superpowers/specs|plans` artifact-dir residue in design/plan SKILLs.

## Retro

- **The panel earned its keep on its 15th outing** — it caught a global-coherence drift invisible to all 19 green selftest cases and both dual reviewers (per-slice review is local; the panel is the "adjust" step). Panel #14's confident "SPINE COMPLETE / exhaustive / stable because complete" was an over-claim Phase 2 falsified the very next slice. **Lesson: declaring a structure "complete" embeds a brittle claim the next slice must actively maintain — prefer count-neutral / self-checking framings over hard-coded numbers.** The fix replaced the false claim with an enforcement claim, and the ops-doc line was made count-neutral.
- **Fix-now beat fix-forward** — for an honesty defect, shipping a known-false claim (even briefly) violates the kit's #1 principle; the in-slice fix kept main coherent.
- **The re-review caught the fix-of-the-fix** — the H1 correction itself missed a surface; builder ≠ reviewer + a focused re-review caught the same false "six" one line over. Cross-surface claims are drift magnets; the durable answers are count-neutral wording + the structural self-check (banked).
- **Steady-state economics held an 8th time** (zero new gates/claims/guards) — H1 is the cost of the cheap seam: cross-brick coupling (the keystone index) was not yet mechanically enforced and drifted.
- **The regression-test-first reframing is the spine's strongest "improve, don't copy" move** — debugging is a first-class producer of the non-vacuity law. Template for brick #9 (evals): chain into the existing spine, don't stand alone.
- **Standing process held:** AMBER apply.py with version finishing folded in; dual review before the panel; governance close folds INTO the feature PR; release-tag only after `git checkout main && git pull`.

**Next: Phase-2 brick #9 (`evals`).** Brick #10 (`discovery`) carries the structural `check_keystone` self-check. No resequencing of the Phase-2 arc.
