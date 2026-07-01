# The Proportional Promotion Contract — the human↔AI handoff model

**Status:** Canonical model (ratified 2026-06-29). The single source of truth for *how much ceremony a change carries on its way to users.* `DEVELOPMENT-PROCESS.md` §9 (Environments) and §13 (Agent Governance) reference this doc; `CLAUDE.md`'s Definition of Ready/Done point here for the promotion judgment. Design rationale: `docs/architecture/2026-06-29-proportional-promotion-contract-design.md`.

> **What this doc does:** it *documents the model* — the matrix, the change-classes, the deferral ratchet, the GO/NO-GO contract. **What it does not do:** it adds no new enforcement. The `promotion-readiness.sh` classifier (slice 2), the proportional gates (slice 3), and the relaxed agent-commit / delegable-execution rule (slice 4) have all shipped; the existing gates run unchanged and the delegable-execution contract below is now operative. This is the kit becoming self-consistent with its own principles (proportional autonomy, surface-don't-actuate, honest-ceiling, agents-propose-humans-ratify), not new dogma.

---

## The model

**rigor = f(rung × change-class)**, modulated by trust.

The kit already scales rigor by consequence on **one** axis — *who acts* (the L0–L3 autonomy tiers in §13, governed by risk × reversibility × blast radius). The promotion contract adds the second axis the kit already implies but never connected, and proportions the two:

- **Axis A — the rung (how far you're promoting):** Spike → Integration → Release candidate → Staging/UAT → Production. *How close to real users / how big the blast radius.* These are the same promotion tiers as `DEVELOPMENT-PROCESS.md` §9 (Dev/QA/UAT/Prod), named by intent.
- **Axis B — the change-class (what's changing):** **Ordinary** (app code, docs, tests) · **Sensitive** (security boundary, data, money, anything irreversible) · **Control-plane** (the kit's own guardrails, standards, gates, governance marker — the meta-level).
- **Modulator — trust (earned track-record):** the agent's scorecard (`scripts/agent-scorecard.sh` — rework / review-rejection / escalation rates) tunes *where the auto-GO line sits within the Ordinary cells*. It is a **dial, not a third matrix axis** — a 3-D matrix would break the "anyone can walk in" requirement.

**One-sentence mental model:** *How much ceremony? It scales with how far you're promoting and how dangerous the change is — and a trusted agent earns a lighter touch in the safe zone.*

---

## The contract matrix

| Rung | **Ordinary** (code/docs/tests) | **Sensitive** (security/data/money/irreversible) | **Control-plane** (kit's own guardrails) |
|---|---|---|---|
| **Spike** (ephemeral/throwaway) | Agent autonomous (L3); cheap gates advisory; no human gate ← *the relaxation win* | Human-gated (always) | Human-authored (always) |
| **Integration** (PR + ephemeral preview) | Automated gates (lint/type/test/secret-scan) required; agent self-review; GO lightweight/delegable (auto when trust is healthy) | High-risk review lane; human GO | AMBER apply + control-plane-ratification |
| **Release candidate** (merged, Definition-of-Deployable) | The meaningful go/no-go — human renders explicit GO against a promotion-readiness surfacing; builder≠reviewer; DoD + acceptance-criteria checked | full dual review + human GO | human ratify + meta-control |
| **Staging/UAT** | smoke + acceptance sign-off | + threat/privacy re-check | N/A |
| **Production** (canary/blue-green) | human-commanded; progressive rollout; rollback ready | human-commanded; irreversible-gated | N/A |

The cells are the kit's *existing* pieces connected: the autonomy tiers (§13) fill the "agent autonomous" cells, the environment promotion (§9) is the rungs, the review-lane Default/High-risk is Ordinary/Sensitive, the control-plane guard + AMBER + M2-S5 is the right column, and the human GO at Release-candidate/Production is the go/no-go. **"N/A" = not applicable** — the control-plane is a governance artifact whose lifecycle is author→ratify→merge; it does not deploy to runtime rungs — **not** "not available."

---

## Change-class definitions + fail-safe derivation

- **Control-plane** — *path-derived* (the guard's `is_control_plane_path` already detects it): the guard, CI, `conformance/`, governing docs, agent/skill defs, the governance marker, release/escalation scripts.
- **Sensitive** — path-heuristic (`auth/`, `payments/`, `migrations/`, secret/key handling) **+** declared **+** reviewer-confirmable. The Definition-of-Ready conditional flags (threat-model/privacy, eval, compliance) ride here as sub-flags.
- **Ordinary** — everything else (the default for the relaxed path).
- **Fail-safe:** when classification is uncertain, **default to the higher class.** Classification is **derived, not self-asserted** wherever possible, and **verified at the promotion gate** — a change cannot relax itself by mislabeling. (The classifier gets the non-vacuity treatment in slice 2: a load-bearing test that a mislabeled Sensitive change is caught at promotion.)

---

## The promotion contract — mechanics

1. **Within a rung:** the agent moves freely at the rung's autonomy tier — commit, iterate, build, no per-action gate. For Ordinary work this is most of development time.
2. **Relaxation = deferral, not a waiver.** A change that skipped ceremony at Spike carries **no relaxation upward.** The instant it is *promoted* toward a consequential rung, the **destination rung's gates fire — on the whole accumulated change**, not the delta. You don't pay the tax while it's a throwaway; you pay it in full the moment it heads toward users. **Rigor ratchets at every promotion** — that is how nothing harmful rides upward.
3. **Promotion-readiness surfacing:** at each promotion the agent produces a structured surfacing — *what changed, change-class, blast radius, what's proven vs. attested, DoD + acceptance-criteria status (tracker-sourced), what could regress.* It re-classifies and re-checks against the destination bar — a re-evaluation, not a rubber stamp.
4. **GO/NO-GO judgment, not a keystroke:** the human renders an explicit GO whose *depth* equals the cell's rigor (lightweight/auto for Ordinary-low; a real recorded judgment for Sensitive / Control-plane / Release-candidate / Production). **Execution after GO is delegable** to either party — the agent may merge/tag/apply *after* the human's GO. The keystroke stops being the (false) control; the **judgment is the control.**
5. **DoD + acceptance criteria are the *content* of the Release-candidate go/no-go** (frame vs. content): the RC promotion-readiness pulls the story's acceptance criteria (from the tracker — Jira / ADO / `BACKLOG.md`) and the kit's Definition of Done, and cross-checks "did it meet the criteria," not merely "does it not break."

---

## What stays human-governed (unchanged)

The **Control-plane column stays human-ratified at every applicable rung.** The meta-level — the kit changing its own guardrails / standards / gates / governance marker — must not be agent-self-governable (fox/henhouse). This redesign does **not** relax it; it relaxes the *Ordinary* class where the ceremony is currently miscalibrated. This invariant is locked by `conformance/promotion-contract-documented.sh` (the Control-plane column of this matrix can never document an "agent autonomous" disposition).

## Delegable execution — who may run the keystroke (operative)

Execution of a promotion's keystrokes (merge, tag, release) is **delegable after an explicit recorded human GO** — the judgment is the control, not the keystroke. What is delegable depends on the change-class:

- **Tier 1 — always (build phase, within a rung):** the agent reads/drafts, writes code + tests on a feature branch, `git commit`s (reversible), pushes feature branches, opens PRs, authors the AMBER `apply.py`. No per-action gate.
- **Tier 2 — delegable only after a recorded GO (Ordinary/Sensitive):** the agent may execute a normal, branch-protection-permitted merge of an Ordinary/Sensitive PR and run the tag/release step for an Ordinary release. Never before the GO; **never unilateral at a promotion.**
- **Tier 3 — human-executed, never delegable at any rung:** rendering the GO/NO-GO judgment itself; any Control-plane promotion — **Control-plane execution stays human at every rung** (merge/tag/apply); the `gh pr merge --admin` branch-protection bypass (server-side, outside the guard — the honesty boundary; a human act); push-to-main / force-push (guard-blocked); deploy-to-prod / delete-data / rotate-secrets / incur-spend.

The decisive line is `is_control_plane_path` (change-class), not the keystroke: because the kit's own surface *is* the control-plane, Tier 2 is inapplicable to the kit's own work — the maintainer runs kit ship steps, enforced by the invariant, not merely by preference.

**Honest ceiling:** this is the documented contract. The server-side merge is un-guardable (`docs/operations/runtime-guards.md` honesty boundary); live enforcement remains the guard (push-to-main / force-push) + the `agent-boundary` CI gate (control-plane ratification at merge). No agent auto-execution mechanism is wired — there is no live consumer.


---

## Solo vs. team — same model, honest label

The model is **team-ready by construction.** Solo, the human holds all ratifier roles; with a team, the existing ratification-RBAC roles distribute and `control-plane-ratification` becomes a *real* second-reviewer gate. The gate emits a **truthful state label** rather than a lying binary:

- **`RATIFIED-BY-SECOND-REVIEWER`** — team; separation-of-duties genuinely satisfied.
- **`SOLO-ADMIN-OVERRIDE-LOGGED`** — solo; SoD satisfied by the *compensating control* (the immutable admin-merge audit trail). Honestly weaker, and the label says so.

It never claims a protection that wasn't exercised. Solo SoD genuinely cannot be satisfied (the forge forbids self-approval); the model **names** that, it doesn't fake it. (Emitting this label is slice 3; changing the solo behavior is out of scope — the team experiment comes later.)

---

## Honest ceilings (what this does NOT claim)

1. **Judgment quality is un-gateable.** We can *inform* it (the surfacing), *record* it (an auditable GO), and *measure its outcomes* (the scorecard — rework / escape / incident rates feeding the loop). We cannot CI-prove a GO was a *good* judgment. (Same ceiling as the `operating` skill.)
2. **The classifier is fail-safe, not omniscient.** Safe-default + path-derivation + promotion-gate verification — not perfect detection.
3. **Solo SoD cannot be truly satisfied** — named via the state label, not faked green.

---

## Build status — an epic of ~4 governed slices

| Slice | Scope | Status |
|---|---|---|
| **1. Model + standards (keystone)** | This doc + §9/§13 + DoR/DoD references + the coherence lock. | **this slice** |
| **2. Change-class derivation + promotion-readiness surfacing** | `promotion-readiness.sh` classifies (reusing `is_control_plane_path`) + emits the surfacing; load-bearing fail-safe-classifier negative. | **v3.81.0** |
| **3. Proportional gates** | Gate/keystroke requirements conditional on (class × rung); `control-plane-ratification` emits the team/solo state label. | **v3.82.0** |
| **4. Relax agent-commit + delegable execution** | "Free within rung after explicit GO; execution delegable post-GO; never unilateral at a promotion." | **v3.83.0** |

Slice 1 is the spec everything else implements; all four slices have now shipped (the delegable-execution contract above is the last), each sequenced deliberately with appetite decided after the prior one.
