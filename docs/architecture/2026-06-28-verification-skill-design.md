# Skill-spine brick #6 — the kit's own `verification` (verification-before-completion) skill

**Date:** 2026-06-28
**Epic / slice:** E3 → **skill-spine brick #6** (the kit's own verification-before-completion skill). Sixth brick of the kit's fresh-authored skill spine, toward the [[self-hosting-commitment]] (replace external superpowers; E10 = build a slice using only the kit's own roster + skills).
**Status:** Design converged — **designed by dogfooding `skills/design/SKILL.md`** (5th self-host use), owner-ratified 2026-06-28. Ready for the implementation plan (which will dogfood `skills/plan/SKILL.md`).
**Tracked here** because the skill spine + the E10 self-host test depend on the convention, and it must be resumable cold.

**Reads-first for a cold resume:** [[self-hosting-commitment]], brick #5's design doc (`docs/architecture/2026-06-28-worktrees-skill-design.md`, the convention this mirrors), the shipped skills (`skills/{design,plan,tdd,review,worktrees}/SKILL.md`), the shared verifier (`conformance/orchestrator-loop-wired.sh`), and the two seats this wires (`agents/engineer.agent.md`, `agents/orchestrator.agent.md`).

## 0. Why this slice (the decision trail)

Bricks #1–5 wired the Orchestrator's Architect hat (design+plan), the Engineer (tdd), the Reviewer (review), and the Orchestrator's isolation (worktrees). Brick #6 is the next spine piece superpowers supplies — `verification-before-completion` → a kit-authored `verification` skill. It is the keystone's prerequisite: the evidence-before-claims discipline this whole self-hosting effort has lived (confabulation-proofing twice in the brick-#5 session alone).

### The fork (owner-ratified 2026-06-28): DUAL-SEAT (Engineer + Orchestrator)
Unlike bricks #1–5, each of which had one clean owning seat, verification-before-completion is **cross-cutting** — every seat verifies before claiming done. The design wires it to the **two seats whose verification GATES are genuinely distinct**, not the same act twice:
- **Engineer** — "self-verify before returning" sharpened into *evidence-before-claims*: run the verification command fresh in this turn, read the exit code, count failures, before any success word. The Engineer is the primary done-claimer.
- **Orchestrator** — "integrate the returned diffs" / "never trust agent-supplied data" sharpened into *confabulation-proofing*: a subagent can report "done" for files it never wrote; verify on the VCS diff / a clone dry-run (the clone + `verify --require` gate is confabulation-proof). This is the controller's gate, distinct from the Engineer's.
The **Reviewer** is left as-is — its "adversarially verify each finding" (the `review` skill) already covers the review instance; re-wiring it would duplicate.

### First-principles audit (owner asked: does dual-seat break a kit principle?)
Checked explicitly; **no first principle is violated**, and the kit's spirit favors dual-seat:
- **Agents-vs-skills** ("few agents, many skills") — dual-seat creates **no new seat**; it is one skill referenced by two existing seats. This principle governs seat *creation*. Not engaged.
- **One-skill-one-responsibility** — the skill has ONE responsibility (evidence before claims), invoked at two distinct *moments*. One discipline, two gates — not two responsibilities.
- **Non-vacuity** — dual-seat *requires* proving each ref-leg independently (3 selftest cases, below), strengthening non-vacuity rather than weakening it.
- **Honest ceiling** — forcing single-seat would *under-represent* the Orchestrator's confabulation-proofing gate (the kit's most-bitten v-b-c lesson). Hiding it to preserve a pattern would be the dishonest move.
- **Right-weight** (the one real tension) — is the 2nd asserted reference ceremony? **No:** the Orchestrator is the seat that integrates subagent work; if its def does not reference the verification skill, the seat that most needs "verify the diff, don't trust the report" is not wired to it — a real gap. What dual-seat breaks is the *single-seat convention* (emergent across #1–5), not a stated rule.

### Intent (unchanged): FULL REPLACEMENT, not enhancement
Zero runtime dependency on superpowers; acceptance = E10.

## 1. What this slice is
Author the kit's **sixth own skill — `verification`**: the craft of proving work is actually done before claiming it, invoked by the Engineer (evidence-before-claims) and the Orchestrator (confabulation-proofing). **FLOOR-only** (invoke-by-read).

### Name: `verification`
Short, parallels design/plan/tdd/review/worktrees. No collision with `conformance/verify.sh` (different namespace — a skill dir vs a script).

## 2. The skill's content — where the kit *improves on* superpowers (the real value)

`skills/verification/SKILL.md` keeps the proven spine — the **Iron Law** (no completion claim without fresh verification evidence), the gate function (identify → run → read → verify → only then claim), the rationalization + red-flag tables — and bakes in the kit's hardest-won, *most distinctive* lessons (the ones a superpowers paraphrase lacks):

- **Confabulation-proofing.** Never trust a subagent's "done" report on file artifacts — a subagent can report success for files it never wrote. Verify on disk / via a **clone dry-run**; the clone + `verify --require` gate is confabulation-proof. (Lived twice in the brick-#5 session.)
- **Evidence before claims.** Run the command fresh in *this* turn; read the exit code and count failures before any success word. A prior run, "should pass", or an agent's word is not evidence.
- **Tagless-clone fidelity.** `git clone .` is NOT a faithful CI sim — it carries tags `actions/checkout` does not fetch; validate any tag-reading check on a *tagless* clone (the release-coherence lesson).
- **The non-vacuity tie-in.** A green check must *mean* something; verification is how you know the check is live, not drifted-green.

This is "take inspiration, improve, make it inherent": evidence-before-claims reframed around confabulation-proofing + clone-dry-run + tagless-clone fidelity (the kit's own scar tissue), not just the generic Iron Law.

## 3. Wiring (DUAL-SEAT — Engineer + Orchestrator)
- **Engineer def:** sharpen "Self-verify … before returning" → reference the kit's own `skills/verification/SKILL.md` (evidence-before-claims). Edit `agents/engineer.agent.md` (FLOOR) + `.claude/agents/engineer.md` (native).
- **Orchestrator def:** sharpen "Integrate the returned diffs" → reference `skills/verification/SKILL.md` (confabulation-proofing: verify subagent work on the diff/clone, never the report). Edit `agents/orchestrator.agent.md` (FLOOR) + `.claude/agents/orchestrator.md` (native).
- **Guard:** none — `skills/*` already in `is_control_plane_path` + both shell-redirect regexes; `skills/verification/SKILL.md` is agent-immutable for free (confirm-don't-add).

## 4. Conformance (right-weighted — no new gate, no new claim)
- **Extend the `skill-spine` claim** text → "… + verification skill (`skills/verification/SKILL.md`) … referenced by the engineer (evidence-before-claims) + orchestrator (confabulation-proofing) … bricks **#1–6** …".
- **Extend `conformance/orchestrator-loop-wired.sh`:** add `check_vbc_skill "$VBC_SKILL_FILE" "$ENGINEER_DEF" "$ORCH_DEF"` asserting the skill exists + ASCII-safe kit-distinctive markers + **both** the Engineer and Orchestrator defs reference it. Candidate markers (locked at plan time, `grep -qF`, ASCII-only): `name: verification`, `confabulation`, `clone dry-run`, `evidence before claims`, `fresh`. A verbatim superpowers `verification-before-completion` copy fails (it has neither `confabulation` nor `clone dry-run`).
- **Non-vacuity — 3 new cases (dual-seat honestly costs one extra):** **case 13** (drop a marker → exit 1), **case 14** (Engineer omits the reference → exit 1), **case 15** (Orchestrator omits the reference → exit 1). Proving only one ref-leg would leave the other grep potentially vacuous, so each gets a load-bearing negative.
- Update cases 1–12 fixtures so each builds a conformant verification skill + both refs. Wired via the existing orchestrator-loop entries — no new registration surface.
- **Extend `docs/operations/orchestration.md`** — add the verification line ("the Engineer and Orchestrator both follow `skills/verification/SKILL.md` … bricks #1–6").

## 5. Honest ceiling & scope (named, not built)
- **Provided + structurally-proven; quality un-gateable** — correct for a skill. The check proves the skill exists, is kit-distinctive, and both seats reference it; it cannot prove an agent *obeys* the Iron Law at runtime (the conformance/clone gates are the enforcement; this skill is the human/agent-facing craft).
- **Dual-seat, deliberately bounded** — Engineer + Orchestrator only; the Reviewer instance lives in the `review` skill (no duplication).
- **Bootstrap** — the kit's design + plan skills produced this slice (5th dogfood).
- **FLOOR-only-first** — formal `skills` adapter dimension still deferred.
- **Spine remaining after #6** — only the META discovery skill (`using-superpowers`-equivalent, the keystone — invoke-by-read floor made kit-native) → then **E10 zero-superpowers acceptance**.

## 6. Build approach
Control-plane slice (new `skills/verification/SKILL.md`; engineer defs ×2 + orchestrator defs ×2; `conformance/orchestrator-loop-wired.sh` + `conformance/claims.tsv` + `docs/operations/orchestration.md`; version finishing **3.61.0 → 3.62.0**) → **AMBER `apply.py`**, clone dry-run incl. shellcheck + `verify --require` → **dual review** (reviewer: is the skill genuinely the kit's verification craft + the conformance non-vacuous incl. cases 14/15; security: low surface — read-only guidance, confirm `skills/` immutability holds) → **light 5-lens meta-control panel #13** (A5) → **fold the governance close INTO the feature PR** (standing process). Subagent-driven build; the human applies/merges/release-tags (run `release-tag.sh` only after `git checkout main && git pull`).

## 7. Convergence record (owner-ratified 2026-06-28)
Designed by dogfooding `skills/design/SKILL.md` (5th self-host use). DUAL-SEAT (Engineer evidence-before-claims + Orchestrator confabulation-proofing) — owner-challenged against first principles and confirmed not to break any (no new seat; one responsibility / two gates; non-vacuity strengthened; honest-ceiling favors it; right-weight justified by the Orchestrator's real integration gate). The skill reframes verification around **confabulation-proofing + clone-dry-run + tagless-clone fidelity** atop the proven Iron-Law spine. Right-weighted conformance (extend the shared verifier + the one `skill-spine` claim; +case 13 marker-teeth + cases 14/15 dual reference-teeth). FLOOR-only. **Next: the implementation plan, dogfooding `skills/plan/SKILL.md`.**
