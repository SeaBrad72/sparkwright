# The Proportional Promotion Contract — redesigning the human↔AI handoff

**Date:** 2026-06-29
**Status:** Draft for owner ratification (design gate)
**Scope:** A kit-level standards/process change to the human↔AI handoff model. Itself control-plane/governance → human-ratified; built as an epic of governed slices.

## Problem (what we're fixing)

The kit already scales rigor by consequence on **one** axis — *who acts* (the L0–L3 autonomy tiers, governed by risk × reversibility × blast radius). But everywhere else the rigor is **uniform and keystroke-centered**:

- **Uniform gate rigor.** All 7 required gates run on every PR regardless of consequence; a one-line docs fix bears the same ceremony as a security-critical change. Proportionality lives in the autonomy axis but not the gate/ceremony axis.
- **Keystroke-centered ratification.** "Human merges / tags / runs `apply.py` / commits the marker" is a *keystroke* that *implies* a judgment happened. When the judgment is reflexive (or skipped), the keystroke is a **false sense of security** *and* friction at once.
- **A permanently-amber gate.** `control-plane-ratification` always-amber solo (admin-merge is the ratification) trains override-reflex — uniform rigor that's always bypassed.

The goal: enable **high-capacity, low-friction agentic engineering** in the safe space, with **human judgment concentrated where blast radius is real**, such that an entry-level ("vibe-plus") author and an expert engineer can *both* have their work safely progressed — without constant manual intervention, and without ever letting the agent do irreversible harm. This is the kit becoming **self-consistent with its own principles** (proportional autonomy, surface-don't-actuate, honest-ceiling, agents-propose-humans-ratify), not new dogma.

## The model — rigor = f(rung × change-class), modulated by trust

Two legible axes the kit already has, finally connected and proportioned; plus one modulator.

- **Axis A — the rung (how far you're promoting):** Spike → Integration → Release-candidate → Staging/UAT → Production. *How close to real users / how big the blast radius.* Modernized: ephemeral preview envs per PR at Integration; canary/blue-green progressive delivery at Production (uses the kit's existing `preview-environments` + `progressive-delivery` docs). UAT≡Staging bucket.
- **Axis B — the change-class (what's changing):** **Ordinary** (app code, docs, tests) · **Sensitive** (security boundary, data, money, anything irreversible) · **Control-plane** (the kit's own guardrails, standards, gates, governance marker — the meta-level).
- **Modulator — trust (earned track-record):** the agent's scorecard (rework / review-rejection / escalation rates) tunes *where the auto-GO line sits within the Ordinary cells* — healthy track record relaxes, a regression auto-tightens. It is a dial, **not** a third matrix axis (a 3-D matrix breaks the "anyone can walk in" requirement).

**One-sentence mental model:** *How much ceremony? It scales with how far you're promoting and how dangerous the change is — and a trusted agent earns a lighter touch in the safe zone.*

## The contract matrix

| | **Ordinary** (code/docs/tests) | **Sensitive** (security/data/money/irreversible) | **Control-plane** (kit's own guardrails) |
|---|---|---|---|
| **Spike** (ephemeral/throwaway) | Agent autonomous (L3); cheap gates advisory; **no human gate** ← *the relaxation win* | Human-gated (always) | Human-authored (always) |
| **Integration** (PR + ephemeral preview) | Automated gates (lint/type/test/secret-scan) required; agent self-review; **GO lightweight/delegable** (auto when trust is healthy) | High-risk review lane; human GO | AMBER apply + control-plane-ratification |
| **Release candidate** (merged, Definition-of-Deployable) | **The meaningful go/no-go** — human renders explicit GO against a *promotion-readiness surfacing*; builder≠reviewer; DoD + acceptance-criteria checked; regression/coherence check | full dual review + human GO | human ratify + meta-control |
| **Staging/UAT** | smoke + acceptance sign-off | + threat/privacy re-check | N/A — control-plane doesn't deploy |
| **Production** (canary/blue-green) | **human-commanded**; progressive rollout; rollback ready | human-commanded; irreversible-gated | N/A — control-plane doesn't deploy |

The cells are the kit's *existing* pieces connected: autonomy tiers fill the "agent autonomous" cells, environment promotion is the rungs, review-lane Default/High-risk is Ordinary/Sensitive, the control-plane guard + AMBER + M2-S5 is the right column, the go/no-go is the human GO at RC/Prod. **"N/A" = not applicable** (control-plane is a governance artifact: its lifecycle is author→ratify→merge; it does not deploy to runtime rungs), **not** "not available."

## Change-class definitions + fail-safe derivation

- **Control-plane** — *path-derived* (the guard's `is_control_plane_path` already detects it): guard, CI, `conformance/`, governing docs, agent/skill defs, governance marker, release/escalation scripts.
- **Sensitive** — path-heuristic (`auth/`, `payments/`, `migrations/`, secret/key handling) **+** declared **+** reviewer-confirmable; also the DoR conditional flags (threat-model/privacy, eval, compliance) ride here as sub-flags.
- **Ordinary** — everything else (the default for the relaxed path).
- **Fail-safe:** when classification is uncertain, default to the **higher** class. Classification is **derived, not self-asserted** wherever possible, and **verified at the promotion gate** — a change cannot relax itself by mislabeling. The classifier gets the non-vacuity treatment: a load-bearing test that a mislabeled Sensitive change is caught at promotion.

## The promotion contract — mechanics

1. **Within a rung:** the agent moves freely at the rung's autonomy tier — commit, iterate, build, no per-action gate. (For Ordinary work this is most of the development time.)
2. **Relaxation = deferral, not waiver.** A change that skipped ceremony at Spike carries **no relaxation upward**. The instant it's *promoted* toward a consequential rung, the **destination rung's gates fire — on the whole accumulated change**, not the delta. You don't pay the tax while it's a throwaway; you pay it in full the moment it heads toward users. **Rigor ratchets at every promotion** — that is how nothing harmful rides upward.
3. **Promotion-readiness surfacing:** at each promotion the agent produces a structured surfacing — *what changed, change-class, blast radius, what's proven vs. attested, DoD + acceptance-criteria status (tracker-sourced), what could regress.* It re-classifies and re-checks against the destination bar — a re-evaluation, not a rubber stamp.
4. **GO/NO-GO judgment, not keystroke:** the human renders an explicit GO whose *depth* equals the cell's rigor (lightweight/auto for Ordinary-low; a real recorded judgment for Sensitive/Control-plane/RC/Prod). **Execution after GO is delegable** to either party — the agent may merge/tag/apply *after* the human's GO. The keystroke stops being the (false) control; the judgment is the control.
5. **DoD + acceptance criteria are the *content* of the RC go/no-go** (frame vs content): the RC promotion-readiness pulls the story's acceptance criteria (from the tracker — Jira/ADO/`BACKLOG.md`) and the kit's Definition of Done, and cross-checks "did it meet the criteria," not merely "does it not break." This gives the existing DoR/DoD + `tracker-contract` a home.

## What stays human-governed (unchanged)

The **Control-plane column stays human-ratified at every applicable rung.** The meta-level — the kit changing its own guardrails/standards/gates/governance marker — must not be agent-self-governable (fox/henhouse). The redesign does **not** relax this; it relaxes the *Ordinary* class where the ceremony is currently miscalibrated.

## Solo vs. team — same model

The model is **team-ready by construction.** Solo, the human holds all ratifier roles; with a team, the existing ratification-RBAC roles distribute and `control-plane-ratification` becomes a *real* second-reviewer gate. The gate emits a **truthful state label** rather than a lying binary:
- `RATIFIED-BY-SECOND-REVIEWER` (team — SoD genuinely satisfied), vs.
- `SOLO-ADMIN-OVERRIDE-LOGGED` (solo — SoD satisfied by the *compensating control*, the immutable admin-merge audit trail; honestly weaker, and the label says so).

It never claims a protection that wasn't exercised. Solo SoD genuinely cannot be satisfied (GitHub forbids self-approval); the model **names** that, doesn't fake it. (Changing the solo behavior is *not* in scope — the team experiment comes later.)

## Honest ceilings (what this does NOT claim)

1. **Judgment quality is un-gateable.** We can *inform* it (the surfacing), *record* it (auditable GO), and *measure its outcomes* (the scorecard — rework/escape/incident rates feeding the loop). We cannot CI-prove a GO was a *good* judgment. (Same ceiling as the `operating` skill.)
2. **The classifier is fail-safe, not omniscient.** Safe-default + path-derivation + promotion-gate verification, not perfect detection.
3. **Solo SoD cannot be truly satisfied** — named via the state label, not faked green.

## Build model — an epic of ~4 governed slices

This is a multi-slice epic, not one slice. Most of it is *connecting/proportioning/documenting what exists* (default-KEEP / right-weight), not new machinery. Each slice runs the full loop (design→plan→build→dual-review→ratify); control-plane parts are AMBER apply.

1. **Model + standards (keystone slice).** Document the proportional promotion contract — matrix, change-class definitions, the deferral-not-waiver ratchet, the promotion-readiness + GO/NO-GO contract, DoD/acceptance-criteria-as-content — into `DEVELOPMENT-PROCESS.md` (extend §13 + Environments), a new model doc, and the CLAUDE.md DoR/DoD references; + a conformance check that the model is documented coherently and consistently with the existing tiers. *Mostly authoring; low code. Unblocks the rest.*
2. **Change-class derivation + promotion-readiness surfacing.** A `promotion-readiness.sh` that classifies (reusing the guard's path logic) and emits the surfacing (incl. tracker acceptance-criteria pull where wired). *Medium; + a conformance lock with a load-bearing fail-safe-classifier negative.*
3. **Proportional gates.** Make the gate/keystroke requirements conditional on (class × rung) — relax the human-keystroke for Ordinary-at-Integration, keep full for Sensitive/Control-plane; make `control-plane-ratification` emit the team/solo state label. *Medium-high — touches CI + the always-amber gate.*
4. **Relax agent-commit + delegable execution.** Update the merge/tag/agent-commit rule to "free within rung after explicit GO; execution delegable post-GO; never unilateral at a promotion." *Medium, most careful — touches the guard's hard boundaries.*

Slice 1 is highest-leverage (the spec everything implements) and goes first; the enforcement slices (3, 4) carry the real risk and are sequenced deliberately, with appetite decided after slice 1.

## Open questions for plan-time

- The exact gate set relaxed at Ordinary×Integration (which automated gates stay mandatory vs. advisory).
- How `promotion-readiness.sh` sources acceptance criteria across trackers (Jira/ADO/`BACKLOG.md`) via the existing tracker adapters.
- Whether trust-modulation auto-GO is in scope for slice 3 or deferred (it depends on the scorecard being live).
