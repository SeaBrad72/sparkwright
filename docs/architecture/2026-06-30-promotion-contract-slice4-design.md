# Proportional Promotion Contract — Slice 4: relax agent-commit + delegable execution post-GO

**Date:** 2026-06-30
**Status:** Owner-approved (design gate passed 2026-06-30)
**Epic:** Proportional Promotion Contract (`docs/governance/promotion-contract.md`); epic design `2026-06-29-proportional-promotion-contract-design.md`.
**Slice:** 4 of 4 — the LAST enforcement slice. Prior: Slice 1 model/standards keystone (v3.76.0), Slice 2 advisory classifier (v3.81.0), Slice 3 proportional gates + state label (v3.82.0).
**Change-class:** Control-plane (governing docs + a conformance lock) → human-ratified; built AMBER.

---

## Problem (what this slice closes)

The epic's model (Slice 1) documented that *"GO/NO-GO is a recorded judgment, not a keystroke; execution delegable post-GO"* — but flagged it **"not yet operative — slices 3–4."** Slice 3 shipped the proportional gate + honest state label. Slice 4 makes the **delegable-execution rule operative**: it states, coherently and in one canonical place, exactly which execution tasks an agent may perform after a recorded human GO, and which stay human — and locks that statement so it can't drift into a fox/henhouse gap.

## The key finding that shapes this slice (from the boundary map)

1. **"Relax agent-commit" is already true mechanically.** The guard already allows `git commit` + feature-branch push (`agent-autonomy.sh:34-36`); it blocks only push-to-main and force-push. There is almost no "commit" left to relax.
2. **The real restriction is the merge/tag ceremony**, and its deepest form — `gh pr merge --admin` — is **server-side, outside the guard's reach** by design (the "honesty boundary," `runtime-guards.md`). The boundary on *who merges* is GitHub branch protection + agent discipline, never the guard.
3. **The kit's own work has no live consumer for delegable execution.** The kit is a governance kit: almost every change it makes is **control-plane**, which stays human-executed forever (locked by `promotion-contract-documented.sh` — the Control-plane column can never document "agent autonomous"). Delegable execution applies only to **Ordinary/Sensitive** changes — adopter territory.

**Therefore Slice 4 is a documentation + coherence-lock slice, not a mechanism build.** Building an agent-auto-merge machine would be textbook build-ahead (no consumer), and the only honest enforcement point (the guard) cannot reach the action anyway. This is the right-weight, no-build-ahead reading — consistent with how Slice 1 shipped (mostly authoring + a doc-coherence lock).

## Goal

Document the operative delegable-execution contract as three clear tiers, reconcile every prose surface to it, and extend the existing lock so the control-plane-human invariant and the "after-GO" precondition can never be euphemism-evaded.

---

## The contract (owner-approved 2026-06-30) — the three tiers

**Tier 1 — Agent CAN, always (within-rung / build phase):** read/analyze/draft; write code+tests on a feature branch; `git commit`/`--amend` (reversible); `git push origin feature/x`; open a PR (`gh pr create`); author the AMBER `apply.py`; run conformance/verify/clone-proofs. *(Already permitted by the guard; Slice 4 states it as the operative rule.)*

**Tier 2 — Agent CAN, only after an explicit recorded human GO (Ordinary/Sensitive only):** execute a **normal, branch-protection-permitted merge** of an Ordinary/Sensitive PR; run the tag/release step for an Ordinary release. The judgment stayed with the human; only the keystroke is delegated.

**Tier 3 — HUMAN-PROTECTED, never delegable at any rung:**
- Rendering the **GO/NO-GO judgment** itself (bedrock — agents propose, humans ratify; no GO record → no execution).
- Any **Control-plane** promotion (merge/tag/apply of the kit's own guardrails/CI/conformance/governing docs) — human-executed forever (fox/henhouse; locked).
- **`gh pr merge --admin`** (the branch-protection *bypass* merge) — human; server-side, outside the guard; bypassing protection is a human act.
- **Push to main/master directly** and **force-push/history rewrite** — blocked mechanically by the guard.
- **Deploy to production · delete data · rotate secrets · incur spend** — always human-gated regardless of tier.
- **Self-promotion without a recorded GO** — never unilateral at a promotion.

**The decisive line is `is_control_plane_path` (change-class), not the keystroke.** Because the kit's own surface *is* the control-plane, Tier 2 is structurally inapplicable to the kit's own work — the maintainer keeps running kit ship steps, enforced by the invariant, not merely by preference.

---

## Mechanics — surfaces touched (all control-plane → AMBER)

### 1. Canonical rule → `docs/governance/promotion-contract.md`
Make mechanic #4 (delegable execution) **operative** and add the three-tier breakdown as the canonical statement (the lock's grep target): Tier-2 delegable-post-GO for Ordinary/Sensitive; Tier-3 control-plane + `--admin` + irreversible stay human; never-unilateral-at-promotion. Flip the build-status table (Slice 4 `planned` → shipped) and the intro note ("the relaxed agent-commit rule is slice 4" → shipped).

### 2. Prose reconciliation (reference the canonical rule; flip "not yet operative")
- **`DEVELOPMENT-PROCESS.md §13`** — "execution delegable post-GO; *enforcement lands in slices 3–4 — not yet operative*" → "now operative"; add the Tier-2/Tier-3 carve-out reference (Ordinary/Sensitive delegable post-GO; control-plane + `--admin` human).
- **`AGENTS.md`** — "prepare the green PR and hand the human the merge command" → keep for **control-plane and any `--admin` bypass**, but state that for **Ordinary/Sensitive after a recorded GO the agent may execute the (normal) merge**. Preserve the honesty boundary verbatim.
- **`docs/operations/review-lane.md`** ("Solo + agent-authored PRs") — same reconciliation; `--admin` stays human (unchanged), normal Ordinary/Sensitive merge delegable post-GO.
- **`CLAUDE.md:92` (DoD)** — closes routed **L1**: drop the now-stale "enforcement lands in slices 3–4" (both shipped) — the sentence points to the contract doc, which is now authoritative.

### 3. Lock → extend `conformance/promotion-contract-documented.sh` (no new claim)
Extend the existing euphemism-gate (which already forbids a Control-plane "agent autonomous" disposition) to also assert the delegable-execution rule is documented coherently:
- **Positive anchors:** the contract documents delegable execution **post-GO** for Ordinary/Sensitive.
- **Load-bearing negative:** a doc that states execution is delegable but **drops the control-plane-human carve-out** OR the **"after-GO" precondition** must FAIL the selftest (the fox/henhouse euphemism — mirrors Slice 1's negative). Prove the flip in the selftest.
- Update the `promotion-contract` claim row description in `claims.tsv` to mention delegable-execution.

### 4. Version finishing folded into `apply.py`
VERSION minor bump (3.82.0 → 3.83.0), README badge, CHANGELOG entry.

**Explicitly NOT touched:** `guard-core.sh` / `guard.sh` (commit + feature-push already allowed; main/force-push already blocked; server-side merge un-guardable — no guard change is honest and lowest-risk, avoids the #2-watch file). No new agent-auto-merge mechanism. No change to `agent-boundary.sh` (Slice 3's gate already enforces control-plane ratification at merge).

---

## Honest ceiling (stated up front)

- **This slice documents + locks the CONTRACT; it does not add mechanical enforcement of agent execution behaviour.** The lock proves the rule is *documented coherently* (same ceiling as `promotion-contract-documented.sh` today — doc-coherence, not behaviour). It does not, and cannot, mechanically stop an agent from running an Ordinary merge without a GO — the server-side merge is un-guardable, exactly as `runtime-guards.md` already states.
- The enforcement that *does* hold is the existing floor: the guard blocks push-to-main/force-push (mechanical); the `agent-boundary` CI gate (Slice 3) forces control-plane ratification at merge (harness-independent); the doc invariant is locked here. Slice 4 adds no new enforcement mechanism because none is honest or needed (no consumer; un-guardable action).
- Judgment quality stays un-gateable (same ceiling as the whole epic).

---

## Build & review plan

- **Build:** subagent-driven (engineer) against the plan; dogfood the `plan` skill. AMBER `apply.py`, clone-proven. Even though this is docs-centric, it edits control-plane governing docs + a conformance lock → AMBER + dual review stand.
- **Review:** dual — `reviewer` (coherence/no-contradiction/no-placeholder; does any prose now contradict another surface?) + `security-reviewer` (the fox/henhouse lens — can the documented relaxation be read to permit an agent-autonomous control-plane or `--admin` merge? is the euphemism-negative load-bearing?).
- **Meta-control:** per-slice panel #34; governance close as a separate human-run `governance-close.py` (M2-S5).
- **Ship:** standard flow — apply.py → governance close → commit (`git show --stat` all files) → push → PR → green conformance → `gh pr merge --squash --admin --delete-branch` (solo control-plane PR red by design) → `git checkout main && git pull && sh scripts/release-tag.sh`.

## Acceptance criteria

1. `docs/governance/promotion-contract.md` documents the three-tier delegable-execution rule operatively (Tier-2 Ordinary/Sensitive delegable post-GO; Tier-3 control-plane + `--admin` + irreversible human; never-unilateral-at-promotion); build-status Slice 4 → shipped.
2. `DEVELOPMENT-PROCESS.md §13`, `AGENTS.md`, `review-lane.md` reconciled to the rule; no surface contradicts another; the honesty boundary (`--admin` server-side, human) preserved verbatim.
3. `CLAUDE.md:92` no longer says "enforcement lands in slices 3–4" (L1 closed).
4. `conformance/promotion-contract-documented.sh --selftest` passes and is **non-vacuous**: dropping the control-plane-human carve-out OR the after-GO precondition from the delegable-execution rule flips the selftest to FAIL. Existing control-plane-never-agent-autonomous negative still holds.
5. Fresh-clone `verify --require` green; claim count unchanged (extend `promotion-contract`, no new claim); CHANGELOG/VERSION/README coherent at ship; `guard-core.sh` untouched.

## Honest ceilings (recap)
1. Doc-coherence lock, not behaviour enforcement (the merge action is un-guardable server-side; no consumer to wire).
2. Control-plane execution stays human at every rung — the non-negotiable invariant, locked.
3. The relaxation is inapplicable to the kit's own (control-plane) work by construction.
