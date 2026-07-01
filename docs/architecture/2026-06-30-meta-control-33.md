# Meta-Control Panel #33 — Proportional Promotion Contract, Slice 3

**Slice:** proportional gates + honest team/solo SoD state label
**Version:** 3.81.0 → 3.82.0 · **Trigger:** per-slice (A5) · **Profile:** light (5-lens) · **Date:** 2026-06-30

## VERDICT: **GO**

0 blockers · 0 highs · 3 Low fix-forward. The verified path holds; every headline claim is proven or honestly ceiling-qualified; no guardrail weakened; no new control-plane path.

> **Owner disposition (2026-06-30):** the panel rendered GO with **L2** (the `rc=1` double-fault class contradiction) *banked* to Slice 4. The owner ratified **folding L2 in-slice** instead — it is the same defect class already ratified for in-slice fix (a display contradicting the gate), and the fix is one line (`rc=1` is definitionally control-plane → the arm hard-sets `class=control-plane`). L1 and L3 remain routed/accepted as below.

---

## Independent cross-check (beyond the two reviews + integrator)

- **All 11 apply anchors exist and are unique in the live tree** (agent-boundary `run()`/`--selftest`/terminal `case`; ci.yml `case "$rc"` + end-marker + edit-2; promotion-readiness `--class`/`--no-verify`; registry uniqueness; verify.sh anchor; promotion-contract.md rows; §13 anchor at 476 lines → budget-safe). Apply is well-formed and idempotent-guarded per edit.
- **The coherence guarantee that makes the fix sound (traced independently):** `--state` (`ratification_state`) and the gate's `run()`/`boundary_decide` derive control-plane-presence from the **identical** union predicate `is_control_plane_path(_p) OR path_in_union(_p)`. Therefore `state=NONE ⟺ rc=0`, and they **can never disagree on control-plane-ness**. Only the *display* value `--class` (guard-core-only, a subset of the union) could diverge — which the `ci.yml` reconciliation (`state != NONE → control-plane; elif class==control-plane → sensitive`) repairs. The reconciliation only ever **raises** the display to match the broader union authority or clamps an empty-diff fail-safe artifact; **no real control-plane change can be downgraded.** The correctness finding is genuinely, completely closed.

---

## The 5 lenses

1. **Scope/altitude — PASS.** Right-weighted; extends existing surfaces (pure `ratification_state()` + `--state` seam; enriched check-run; one new lock/claim). No new gate (teeth unchanged), no new guard path (`conformance/` auto-immutable; `guard-core.sh` untouched). Auto-GO correctly deferred (scorecard-live). Matches epic Slice-3 intent exactly — "make the gate tell the truth," not new machinery.
2. **Proof integrity / non-vacuity — PASS.** Four load-bearing, flip-proven teeth (always-team → solo + identical-labels FAIL; removed `--class` call → the *tightened* `promotion-readiness.sh --class` anchor FAILs — a self-caught vacuity; stripped legibility sentence → anchor FAILs; deleted reconciliation guard → `state" != NONE` anchor FAILs). Label derivation runs in-process; the YAML-embedded ci.yml composition is grep-locked (the standard disclosed ceiling, consistent with `promotion-readiness-wired`/`golden-path`). No green-while-dark risk.
3. **Honest ceiling — PASS.** Pre-merge-projection framing honest and repeated across ≥4 surfaces (design, CHANGELOG, §13, the `action_required` summary). Every `rc`/`state` combination renders a truthful sentence; the team/`success` branch is reachable only when a non-author actually approved. No surface over-claims. Solo behaviour unchanged.
4. **Coherence/drift — PASS-WITH-NIT.** `promotion-contract.md` build-status, lead/closing notes, §13, CHANGELOG/VERSION/README move coherently. One introduced nit: `CLAUDE.md:92` "enforcement lands in slices 3–4" now mildly inconsistent with the updated contract doc — it under-claims, no gate greps it, safe to defer but explicitly routed (L1).
5. **Ship-readiness — PASS.** Version finishing folded (VERSION + README badge + CHANGELOG `[3.82.0]`); 3-edit registry set complete; claim +1 (37→38, `verify --require` 0 failed); apply idempotent; all files land; governance close correctly a separate human step (M2-S5). Solo control-plane PR renders `SOLO-ADMIN-OVERRIDE-LOGGED`/`action_required` → red by design → admin-merge (expected).

---

## Ledger 1 — verified-as-quality
Union-predicate coherence guarantee (`--state` and the gate cannot disagree); reconciliation safe-direction-only (never downgrades a real control-plane change); exit-code/three-state contract untouched; four non-vacuity flips proven + the `--class`-in-comment vacuity self-caught and hardened; no new control-plane path, `guard-core.sh` untouched; honest projection ceiling on ≥4 surfaces; idempotent apply; claim +1; version finishing folded.

## Ledger 2 — fix-forward (ranked)
- **L1 (Low, routed → Slice 4):** `CLAUDE.md:92` "enforcement lands in slices 3–4" is stale vs the updated `promotion-contract.md`. Fold the one-word fix ("slice 4") into Slice 4's `apply.py` (its natural home; edits these surfaces anyway). Roadmap fallback if Slice 4 slips.
- **L2 (Low) — FOLDED IN-SLICE per owner ratification.** On the degenerate double-fault (`--state`→`NONE` while `rc=1`), reconciliation had yielded `class=sensitive`, contradicting the arm's "a control-plane change." Since `rc=1` is definitionally control-plane-present, the `rc=1` arm now hard-sets `class=control-plane`. (Panel had banked this; owner elected to close it now — same defect class as the ratified correctness fix.)
- **L3 (Low, accept — record only):** the team/`success` CI *rendering* branch is unexercised live on the solo kit (only the derivation is selftested; the rendering is grep-locked). Inherent pre-merge-projection ceiling, disclosed. No action.

## Retro (the adjust step)
The Slice 1→2→3 arc teaches one durable lesson: **reconcile every derived *display* to the union-aware gate authority (`is_control_plane_path ∪ adapter union`), never to the guard-core-only subset** — the Slice-3 correctness finding was precisely a guard-core display contradicting a union verdict. Plus the re-confirmed standing rule: **anchor the actual call, not a prose token** (the `--class`-in-comment vacuity). Routes to Slice 4 design (any class display it introduces must reconcile against the union authority). No divergence from the plan — Slice 4 (relax agent-commit + delegable execution) remains the correct, and last, next thing.
