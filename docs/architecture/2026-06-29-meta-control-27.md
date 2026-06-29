# Meta-control panel #27 — Promotion-Contract Slice 1 (model + standards keystone), v3.76.0

**Trigger:** per-slice M verdict (A5). **Profile:** light (5-lens). **Date:** 2026-06-29.
**Slice:** the keystone of the Proportional Promotion Contract epic — documents the `rigor = f(rung × change-class)` handoff model + adds one doc-coherence lock. Design: `2026-06-29-proportional-promotion-contract-design.md`; plan: `2026-06-29-promotion-contract-slice1-plan.md`.

## Verdict: **GO**

Documentation + a documentation-drift guard; no runtime/enforcement change. Clone-proven green; the new lock's teeth are non-vacuous; additive-only.

## The 5 lenses

1. **Enforcement-integrity / teeth.** `promotion-contract-documented.sh` is non-vacuous: its `--selftest` flips four fixtures — complete→PASS, missing-marker→FAIL, **Control-plane-column-relaxed-to-"agent autonomous"→FAIL** (the load-bearing negative), and prose-mask→FAIL (final-cell-wins, copied from `assurance-tiers.sh`'s un-gameable discipline). A dead/always-pass check fails the relaxed-cell case. The lock encodes the design's hardest invariant (control-plane stays human-ratified) **structurally**, not as word-presence.
2. **Harness-neutrality.** The model doc + §9/§13 + CLAUDE.md edits justify from the kit's OWN committed docs (the autonomy tiers §13, the environment tiers §9, the DoR/DoD); no leak of maintainer-personal `~/.claude/CLAUDE.md` context. The model is tool-neutral (one contract, many runtimes).
3. **Right-weight.** No new gate, no enforcement, no behavior change — it documents what exists and connects two axes the kit already implied. §9/§13 footprint deliberately minimal (detail lives in the model doc). The one structural addition — a doc-budget raise (470→480, 900→910) — is a **ratified, sanctioned bump** (the gate's own message offers it) for genuine new governance content, not a cover for weakening anything.
4. **Honest-ceiling.** The doc and the check both state the ceiling: this proves the model is *documented coherently*, NOT that anyone follows it (enforcement = slices 2–4); judgment quality stays un-gateable; the classifier is fail-safe not omniscient; solo SoD is named (state label), not faked. The claim text is scoped to "documented," never "enforced."
5. **Agent-governance / adopter-proportion.** The Control-plane column stays human-ratified at every rung (locked). The slice changes NO current agent-commit/merge boundary (those are slices 3–4) — so nothing an agent may self-govern is loosened here. AMBER routing correct: control-plane edits land via the human-run `apply.py`; the marker/verdict-log close is the separate human M2-S5 step.

## Evidence (clone-proven, tagless clone)
- `promotion-contract` PASS (live doc, 16 assertions) + `--selftest` 4/4 (incl. the load-bearing negative).
- shellcheck 110 clean · check-links OK (once model doc tracked) · doc-budget PASS (DEVELOPMENT-PROCESS.md 476/480; core-3 908/910).
- claims-registry 45/45 PASS incl. `promotion-contract` · `verify.sh --require` 37 control · 13 doc · 0 unverified · **0 failed**.
- `apply.py` idempotent (second run all-skipped; empty `git diff --stat`).

## Dual review (builder ≠ reviewer, §12)
- **Reviewer: APPROVE-WITH-NITS** (skill verdict APPROVE) — ran the check + selftest; confirmed clause-for-clause fidelity to the design, the L0–L3/§9/§13 cross-refs resolve, lock non-vacuous, apply.py idempotent + AMBER-correct, budgets within ceiling.
- **Security: PASS-WITH-NOTES** — decoded both base64 blobs and byte-matched them to the diff; per-file removal scan confirms **additive-only** (no gate/claim/required-id dropped or relaxed); doc-budget raise honest; apply.py touches no guard/marker.
- **Both reviewers independently caught the same hardening gap** (security Medium / reviewer Minor #2): the lock's teeth accepted a euphemistic Control-plane relaxation ("agent merges; human notified"). **FOLDED IN-SLICE:** negative-token list broadened to reject agent-actuation phrasings (`agent (merge|commit|apply|tag|push|actuat)`, `auto`, `self-govern`, `delegat`) + positive tightened to require an explicit human-actuation disposition (bare `human` no longer rescues); 2 new selftest fixtures (euphemism, auto-merge+human) → both FAIL. Selftest now 6/6.
- **Also folded:** security Low (§13/DoD "execution delegable post-GO" now carries "*enforcement lands in slices 3–4 — not yet operative*"); reviewer Nit #4 (Spike Control-plane cell "Human-authored (always)" matches design).
- **Non-blocking, accepted:** reviewer Minor #1 (plan doc untracked — `git add -A` captures it at ship); Nit #3 (core-3 headroom 908/910 — tight, flagged).

## Banked / follow-ons
- Slices 2–4 (classifier + proportional gates + relaxed agent-commit) carry the real risk; appetite decided post-Slice-1 per the design.
- (Carried) `guard-dev-clone-affordance`; T4 `export-ignore docs/architecture/` (the plan/design docs ship to adopters until that lands — unchanged here).

## Marker
- Marker to advance: `3.75.0 GO` → **`3.76.0 GO`** (human-authored per M2-S5, with the pipe-table log row, folded into this slice's ship).
