# Onboarding On-Ramp — Design

**Status:** approved (brainstorm), ready for implementation planning
**Release:** MINOR → **2.59.0**
**Scope:** a fluency-aware on-ramp that meets developers across the full experience spectrum (no-experience "vibe coder" → senior/principal), teaches *the system around the code*, and lets the AI adapt how it helps. Deliberately **orchestrates existing kit assets** (WALKTHROUGH, GLOSSARY, the standards docs) and adds only what's genuinely absent — no duplication of the standards.

---

## 1. Thesis (the spine)

> **Vibe coders treat software engineering as *just coding*. Coding is the task; software engineering is everything that has to go *around* the code for an enterprise.** The kit *is* that "everything around it."

The on-ramp's job: make a newcomer **see** that surrounding scaffolding as essential (not bureaucracy), **teach** what they're missing (TDD, 15-factor, security, governance, environments/scale, observability) by **motivating + routing to canonical sources** (never re-explaining), and have the **AI adapt** its assistance to where they are — without patronizing the practitioner.

**Success criterion (qualitative):** a newcomer reaches a safe first feature — *functional and not dangerous*. This is **not** mechanically gated (see §6 Honesty); the guard + gates are the enforced safety net, the on-ramp is the teaching.

**The axis is enterprise-SDLC awareness breadth**, not coding skill — a vibe coder may write fine code but not know that tests/threat-models/environments/observability are part of the job at all. The on-ramp teaches *the surrounding system*, staying out of "learn to code" territory.

## 2. Decisions (from brainstorm)

- **Form:** both a human-facing on-ramp **and** an agent-behavior layer, built as one integrated slice, sequenced (human layer first, thin AI layer alongside). (Q1 = C)
- **Entry:** **self-select a track** (front door), with the learning content written in a **layered "skip if you know this"** style so readers self-pace. (Q2 = A + light C)
- **Teaching nature:** **connective tissue + one worked demonstration**, explicitly **not** concept primers that duplicate the standards (DRY). (Q3 = B + C, not A)
- **Tracks:** **three** — Novice / Adjacent / Practitioner — defined by self-recognizable gut-checks; non-punitive to switch. The middle ("Adjacent") is the career product/PM/BA who's been *around* delivery but never practiced the disciplines. (Q4 = B)
- **AI knows level via:** **declared + refined** — a declared operator-fluency line seeds it; the agent refines lightly by observation. Anchored on declared. (Q5 = C)
- **Walkthrough:** narrative spine + one concrete TDD inset — **but the spine already exists** as `WALKTHROUGH.md`; we add only the concrete red-green-refactor beat. (Q6 = C, reconciled against existing assets)

## 3. The two axes (architecture)

The kit routes on **role** today (START-HERE "Who are you?": PO/Designer/QA/DevOps/Engineer). We add an **experience/fluency** axis, **sequential not competing**:

```
ONBOARDING.md  (NEW — outermost front door, experience axis)
   │  "How familiar are you with enterprise software delivery?"
   ├─ Practitioner ─────────► START-HERE.md (role routing + Inception) ──► the loop
   ├─ Adjacent ──┐
   └─ Novice  ───┴► Learning lane (thesis + connective tissue + WALKTHROUGH + TDD beat) ──► START-HERE ──► the loop
```

Experience first → role/Inception second. ONBOARDING.md hands off to START-HERE; no overlapping tables. The Practitioner lane is a fast-forward ("you know this — here's the contract, go").

## 4. Components

### 4.1 `ONBOARDING.md` (root, NEW) — the front door
- **The thesis** (§1) up top — names the coding≠engineering gap.
- **3-lane self-select** with self-recognizable gut-checks, non-punitive to switch ("feels too basic? jump up a lane"):
  - **Novice / Coding-first** — *"I can make code work (often with AI), but tests, environments, security, governance are new to me."*
  - **Adjacent** — *"I've worked in/around software delivery — I know these practices exist but haven't done them myself."*
  - **Practitioner / Fluent** — *"I've shipped enterprise software; route me to the contract."*
- **Learning lane** (Novice + Adjacent): the **connective tissue** — per pillar (TDD · 15-factor · security · governance · environments/scale · observability): *why an enterprise needs it → **go learn it for real** (a curated canonical source, e.g. 12factor.net, a canonical TDD reference, OWASP) → where the kit applies it (pointer into the existing kit doc)*. Layered with skip-if-you-know markers. **Never re-explains the pillar** (DRY).
- **Practitioner lane:** a few lines → START-HERE + the contract.
- Links to `WALKTHROUGH.md` (whole-loop story) and `docs/onboarding/first-feature-tdd.md` (the code beat).

### 4.2 `docs/onboarding/first-feature-tdd.md` (NEW) — the one missing demonstration
- A focused zoom into the **Build** step: real reference-stack (typescript-node) **red → green → refactor**, flagged "illustrative — your `profiles/<stack>.md` has the exact commands."
- Does **not** re-tell the whole loop — `WALKTHROUGH.md` Part 2 already does. A one-line pointer is added to `WALKTHROUGH.md` Part 2 ("TDD per the profile → see first-feature-tdd.md").

### 4.3 Operator-fluency mechanism (the AI layer)
- **`templates/PROJECT-CLAUDE-TEMPLATE.md`** — a declared line: `Operator fluency: Novice | Adjacent | Practitioner` (travels with the project like every other declaration).
- **`docs/operations/operator-fluency.md`** (NEW) — how the agent **adapts** per level:
  - *Novice/Adjacent* → explain the *why*, surface what's about to happen, **confirm before irreversible steps**, teach-as-you-go, link to the on-ramp.
  - *Practitioner* → terse, assume competence.
  - **Refine by observation** — declared seed; self-heals if clearly wrong (a declared-Novice who's plainly fluent, or vice-versa). Never overrides the §13 guard or gates (adaptation is *communication style*, not *permission*).
- **`AGENTS.md`** — one pointer line → `operator-fluency.md` (respecting its `agents-brief.sh` line-bound).

### 4.4 `scripts/incept.sh` changes
- **No-fluency nudge:** when run without a declared fluency, print one line — *"New to enterprise SDLC? → ONBOARDING.md. Already fluent? → continue"* — then proceed (a nudge, not a wall).
- **`--operator-fluency <novice|adjacent|practitioner>`** flag (a.k.a. the repeat-user bypass): stamps the chosen fluency into the new project's CLAUDE.md and skips the nudge.
- Verify `conformance/inception-done.sh` still passes after the change.

### 4.5 Wiring
- README front-door link to `ONBOARDING.md`; START-HERE cross-link back to ONBOARDING for the experience axis; `GLOSSARY.md` entry for "operator fluency."

## 5. First-run funnel vs repeat-clone bypass

Two use cases: first-time-ever adopter, and the user who clones the kit per-project repeatedly.

- **First-run:** soft funnel — ONBOARDING.md is the prominent README front door; `incept.sh` nudges (not walls) toward it when no fluency is declared.
- **Repeat-user bypass:** the **Practitioner lane IS the bypass**, plus `incept.sh --operator-fluency practitioner` — one command, straight to Inception.
- **Deliberately NOT:** machine-global "I already onboarded" state — it cuts against the kit's stateless, project-scoped, no-phone-home grain, doesn't travel across machines, and buys little given the guard/gates backstop.

**Why a bypass is safe:** the on-ramp is *not* the safety mechanism — the **§13 guard and the §7/§14 gates are**, and they run regardless of whether anyone read the on-ramp. A bypasser misses the *teaching*, not the *protection*. That is what lets us offer a bypass without betraying "functional and not dangerous."

## 6. Conformance & honesty

- **`conformance/onboarding-complete.sh`** (NEW control, mirrors `persona-artifacts.sh`): structural — verifies ONBOARDING.md exists with the 3 named lanes; the `Operator fluency:` field is in `PROJECT-CLAUDE-TEMPLATE.md`; `operator-fluency.md` exists and is referenced from `AGENTS.md`; `first-feature-tdd.md` exists. Binary pass/fail (always applies to the kit — not conditional). `--selftest` (clean fixture passes, a fixture missing a lane fails). Registered in `verify.sh` + `conformance/README.md`.
- **Wired into the pipeline** — as the first new check born after the coverage meta-check (#87), it gets its own real-run CI step (control-plane hand-apply), and `ci-selftest-coverage.sh` will flag it if forgotten. (Drift-closure working as intended.)
- **Honesty:** green = the on-ramp *exists, is structurally complete, and is wired* — **not** that anyone learned anything or that the teaching "works." Stated plainly in the doc and the check.

## 7. Doc-budget

**Nothing touches the core-3** (CLAUDE/PROCESS/STANDARDS stay 900/900). All new material is uncapped: root `ONBOARDING.md`, `docs/onboarding/first-feature-tdd.md`, `docs/operations/operator-fluency.md`, the `templates/` fluency line. `AGENTS.md` gets one pointer line (within its `agents-brief.sh` line-bound). Run `doc-budget.sh` after any edit that could touch a capped file — it MUST still read 900/900. No `TOTAL_BUDGET` change.

## 8. Slicing

One coherent slice, internally ordered:
1. `ONBOARDING.md` + fluency declaration in `PROJECT-CLAUDE-TEMPLATE.md` + `incept.sh` (nudge + flag) + `onboarding-complete.sh` + README/START-HERE/GLOSSARY wiring.
2. `docs/onboarding/first-feature-tdd.md` + `docs/operations/operator-fluency.md` + `AGENTS.md` pointer + `WALKTHROUGH.md` Part 2 pointer.

May split into two PRs if the plan gets heavy. Independent review (builder ≠ reviewer) before the PR; the security-owner lens on the `incept.sh` + AGENTS.md changes. Bradley merges. Required control-plane follow-up: the `onboarding-complete.sh` CI step (colon-free `name:`).

## 9. Out of scope

- Re-teaching the pillars (DRY — connective tissue + canonical links only).
- A second whole-loop narrative (`WALKTHROUGH.md` already is it).
- Persisted cross-clone onboarding state.
- A runnable tutorial repo.
- Any change to the role-map (START-HERE "Who are you?").
- The Product/Design + pre-story/discovery work (the next roadmap item, separate).

## 10. Definition of Done

- `ONBOARDING.md` (thesis + 3 self-select lanes + layered Learning lane with motivate→canonical-source→kit-pointer per pillar + Practitioner fast lane).
- `docs/onboarding/first-feature-tdd.md` (concrete red-green-refactor in the reference stack) + `WALKTHROUGH.md` Part 2 pointer.
- Operator-fluency: declared line in `PROJECT-CLAUDE-TEMPLATE.md` + `docs/operations/operator-fluency.md` (adapt-per-level + refine-by-observation + never-overrides-guard) + `AGENTS.md` pointer.
- `incept.sh` nudge + `--operator-fluency` flag + fluency stamped into project CLAUDE.md; `inception-done.sh` still green.
- `conformance/onboarding-complete.sh` (+ `--selftest`) registered in `verify.sh` + README; shellcheck-clean; dash-clean.
- README/START-HERE/GLOSSARY wiring; all links resolve (`check-links.sh`).
- core-3 doc-budget 900/900 held; `verify.sh` RESULT OK; independent review → SHIP; ratified PR; **2.59.0** release.
- Required follow-up logged: the `onboarding-complete.sh` CI step (control-plane hand-apply).
