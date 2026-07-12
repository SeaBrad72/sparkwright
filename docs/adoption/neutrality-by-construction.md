# Neutrality by Construction

**The recipe for making a new concretization axis neutral by construction.**

A *concretization axis* is any place the kit forces a real-world choice — which stack, which deploy target, which agent harness, which model. Left unguarded, every such choice drifts toward the familiar ("we always use X") instead of the fitting. This doc is the reusable recipe that makes a new axis neutral **by construction**: comparable options, a fit-derived choice, an honest maturity disclosure, and a machine gate that rejects bias-appeal. It is the operational companion to the standing requirement in [DEVELOPMENT-STANDARDS.md](../../DEVELOPMENT-STANDARDS.md) §1.

Three axes ship as worked examples and are the canonical references throughout:

- **stack** — [docs/STACK-SELECTION.md](../STACK-SELECTION.md), gated by `conformance/stack-decision-integrity.sh`.
- **deploy-target** — [docs/adoption/DEPLOYMENT-ENVIRONMENT.md](DEPLOYMENT-ENVIRONMENT.md), gated by `conformance/deploy-decision-integrity.sh`.
- **harness** — [docs/operations/harness-adapters.md](../operations/harness-adapters.md), gated by `conformance/harness-decision-integrity.sh` (instance #3; see §5).

---

## 1. The four obligations

Every axis MUST satisfy all four. They are operational, not aspirational — each maps to something you write down and something a check enforces.

1. **Comparable cards** — every option is recorded with the *same* fields, side by side. No favourite gets a richer entry, a friendlier tone, or an extra paragraph of reassurance. Uniform structure is what makes "compare, don't guess" possible.
2. **Fit-driven selection** — the choice is *derived* from the problem's dimensions (workload shape, team, constraints), not from familiarity, reputation, or "it's the default." The derivation is written in the decision artifact so a reviewer can retrace it.
3. **Fit-vs-maturity disclosure + owner ratification** — the recommendation states *both* the best-fit option *and* its maturity tier (e.g. first-class / experimental). When best-fit and best-supported diverge, the owner ratifies the trade-off **explicitly** — the kit never silently downgrades fit to maturity or vice versa.
4. **Anti-bias gate** — a conformance check on the decision artifact rejects bias-appeal ("it's the proven default," "everyone uses it") and *requires* a cited fit reason drawn from a defined fit-dimension vocabulary. If the artifact can't name a fit dimension, it doesn't pass.

---

## 2. Comparable-card template

Every option's card carries the same uniform field set. Do **not** create a separate template file — the shipped worked examples *are* the template by example; copy their column/field structure for a new axis.

| Field | What it captures |
|-------|------------------|
| **Name** | The option's canonical identifier. |
| **Best for** | The workload/problem shapes this option fits. |
| **Avoid when** | The dimensions where it is the wrong choice (every card must have honest limits). |
| **Maturity tier** | Support level in the kit (e.g. first-class / experimental) — the input to obligation 3. |
| **Key fit dimensions** | The problem dimensions that drive selection toward or away from this option. |

Canonical instances of this template:

- **stack** — the comparison matrix in [docs/STACK-SELECTION.md](../STACK-SELECTION.md) (`Stack · Maturity · Best for · Avoid when · Typical domain/runtime`).
- **deploy-target** — the topology comparison in [docs/adoption/DEPLOYMENT-ENVIRONMENT.md](DEPLOYMENT-ENVIRONMENT.md).
- **harness** — the maturity cards in [docs/operations/harness-adapters.md](../operations/harness-adapters.md) (`Name · Best for · Avoid when · Maturity tier · Key fit dimensions`).

The point is uniformity, not the exact column names: pick a field set, then apply it identically to *every* option on the axis.

---

## 3. Standing up an anti-bias gate — checklist

To make a new axis enforceable, stand up a `decision-integrity`-style gate. As of KW9-B the gate is a **config row in the shared engine** (`conformance/decision-integrity.sh`, see §5) — read `conformance/harness-decision-integrity.sh` (a two-line shim over the engine) plus the engine's `stack`/`deploy`/`harness` axis config before you start; you are adding a config, not cloning a script.

1. **Pick the decision artifact + its target heading + heading/stop level.** Choose *which* file records the decision (e.g. an ADR, an adapter doc) and the exact heading whose body carries the fit rationale (e.g. `## Fit rationale`). Fix the heading level and the stop level (the next heading level that ends the scanned block) so the gate reads exactly the intended region.
2. **Author the fit-dimension vocabulary.** Define the set of allowed fit tokens for this axis (the dimensions a valid choice may cite). This vocabulary is the gate's positive signal — the artifact must cite at least one.
3. **Add fixtures.** Provide four:
   - **good** — cites a real fit dimension → expect **GREEN**.
   - **missing** — no fit rationale present → expect **RED**.
   - **bias-only** — appeals only to proven-ness/popularity, no fit dimension → expect **RED**.
   - **placeholder** — unfilled template/sentinel → expect **N/A** (not yet a decision).
4. **Register the gate.** Add it to `verify.sh` and add a `ci.yml` selftest step so it runs on every push. A gate that isn't wired into CI isn't enforced.

---

## 4. ★ Vocabulary rule (load-bearing — the twice-recurring foot-gun)

**A fit-dimension token MUST NOT be a substring of a word likely to appear in the artifact's own prose.**

The gate left-anchors tokens generically (it matches token boundaries, not naive substrings), but authors still must choose collision-resistant tokens — prefer distinctive stems over short common fragments. A token that hides inside ordinary prose produces a **false PASS**: the gate "finds" the fit dimension in a word that has nothing to do with the decision.

This has bitten three times; record it so the fourth author doesn't repeat it:

- `gc` ⊂ "logic" — caught in **KW4-L1**.
- `edge` ⊂ "acknowledge" — caught in **KW5**.
- `ml` ⊂ "html" — a latent false-PASS, closed in **KW19**.

When picking vocabulary for a new axis, scan the candidate tokens against the words the artifact naturally uses and reject any that collide.

---

## 5. The `decision-integrity` engine (KW9-B) — built

Originally each axis shipped its own copy of the gate (`stack-decision-integrity.sh`, `deploy-decision-integrity.sh`) — behavior-identical, config-different. **KW9-B builds the shared, config-driven `decision-integrity` engine** (`conformance/decision-integrity.sh`): stack and deploy-target are migrated onto it **behavior-preserving** (their existing fixtures stay GREEN/RED/N/A exactly as before), and **harness is added as neutrality instance #3.** The engine takes a small per-axis config:

- **target heading** — which heading's body carries the rationale.
- **heading / stop level** — where the scanned block begins and ends.
- **sentinel** — the placeholder marker that means "not yet decided" → N/A.
- **vocabulary** — the axis's fit-dimension token set.
- **default path** — the decision artifact's location.

Each axis is now a **config row**, not a copy: `stack-decision-integrity.sh` and `deploy-decision-integrity.sh` are thin shims that call the engine, and `harness-decision-integrity.sh` is the new shim over the `harness` config. Adding the next axis is a config extraction, not a rewrite — this checklist is precisely what the engine parameterizes.

### Model — subsumed by harness

There is **no standalone model axis** and no separate model gate. The model is chosen *as part of* the harness decision, not on its own: a harness's **model-family** is one of its fit dimensions, and the harness maturity cards in [docs/operations/harness-adapters.md](../operations/harness-adapters.md) already record which model support is verified versus experimental. Model neutrality is therefore satisfied by the harness card + harness gate — no model decision artifact, no model fixtures, no fourth gate. (Single-sourcing the concrete model-id string across the kit is a separate config-hygiene cleanup, tracked as **KW15** — not a neutrality axis.)
