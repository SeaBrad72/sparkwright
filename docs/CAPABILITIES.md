# Capabilities — the agent team, governance, and rigor

This page goes one level deeper than the README on *how* Sparkwright runs work: who the agents are, how the
loop is governed, how models are tiered, and why the gates are trustworthy. It is deliberately **honest about
what is enforced versus advisory versus declared** — that candor is the point. For the full narrative (with
the CI/CD, ephemeral-environment, and enterprise-governance surface) see `docs/positioning/`.

---

## 0. First — the methodology the agents execute

Sparkwright is a **software-development methodology first, an agentic engine second.** The machinery below
exists to carry out a disciplined lifecycle, not to replace it. The foundation lives in `CLAUDE.md`
(principles + Definition of Done), `DEVELOPMENT-PROCESS.md` (the loop, gates, ceremonies), and
`DEVELOPMENT-STANDARDS.md` (the quality bar):

- **Non-negotiable principles** — production-grade from day one; **test-driven** (tests + evals written *with*
  the code; TDD as a Build-stage skill); **architecture before implementation**, including a binding-but-
  conditional **15-Factor** contract for deployable services (`conformance/15-factor-checklist.md`, enforced at
  the Review gate); security & governance foundational.
- **The governing lens** — *"rituals that manage or forecast human effort die or transform; rituals that
  clarify intent or improve quality get stronger."* Estimation/velocity/sprints/standups are dropped; Definition of Ready,
  acceptance, demos, retrospectives, and adversarial review are strengthened.
- **The loop** — Inception → Discover → Plan → Build → Review → Release → Done → Operate ↺, WIP-limited and
  pulled, humans as the pacing metronome at the gates, Operate's signals feeding Discover.
- **The improvement engine** — nested retrospectives (L0 reflection-in-action → L1 per-item → L2 milestone →
  L3 process-retro that edits the governing docs), where **every "adjust" exits into an artifact** (PR, memory,
  backlog, or doc).

Everything that follows — the agent team, separation of duties, model tiering, the conformance rigor — is
*how* that methodology is executed and enforced. See `docs/positioning/sparkwright-overview.md` for the full
foundation-first account.

## 1. The agent team & their hats

A small **standing team of agents** does the building between the gates — *few agents, many skills, by design*
(a standing seat is earned only by a distinct skill **and** distinct tools or must-run-in-parallel; everything
else is a skill a seat invokes):

| Seat | Role |
|---|---|
| **Orchestrator** | Lead/EM. Slices the epic, assigns each task its model tier + fan-out, spawns builders in isolated worktrees, integrates, convenes the reviewers, emits the run trace. Metered by a runaway kill-switch. |
| **Engineer** | Builds one assigned slice via TDD inside its own worktree; never touches another slice's files; returns a diff + a self-verify report. |
| **Reviewer** | Independent correctness/standards review of the diff (builder ≠ reviewer). |
| **Security** | The security lens — threat model, injection, authz, secret handling, prompt-injection — on any trust/data/AI boundary. |

The **design, plan, verification, TDD, operating, evals, discovery** roles are **skills** the orchestrator or a
seat invokes (`skills/`), not standing agents. The orchestrator *assigns* work and tiers; it never reviews or
ratifies its own output.

## 2. Separation of duties — enforced, not just advised

- **Builder ≠ reviewer ≠ ratifier.** The agent that wrote the change cannot be its sole reviewer or its
  ratifier.
- **Control-plane ratification.** A change to the kit's own control plane (the guard, CI, conformance,
  governance) requires an **independent ratifier**; the gate blocks the merge until a non-author approval is
  recorded. On GitHub this is a required check; where a platform can't express it, the kit says so (an
  auditable N/A) rather than pretending.
- **The judgment is the control, not the keystroke.** The human's load-bearing act is a recorded, informed,
  proportional **GO/NO-GO** — not the merge button. On that GO the **agent actuates** the mechanics
  (merge/tag/promote), **bound to the reviewed SHA**, and re-verifies that **what shipped == what was
  approved** by *tree equality*. That is a stronger guarantee than a keystroke, which never checked the merge
  target was the reviewed commit.
- **Honest labels.** Solo single-party judgment with delegated mechanics is never relabeled as dual control.

## 3. Model tiering & fan-out economics

The kit reasons in **abstract tiers** — `apex > deep > fast > light` — never concrete model names:

- **Judgment/verification seats are pinned** to the top proven tier (reviewer, security, orchestrator,
  verification always run `deep`); **builders may run cheaper** where the task allows; **high-stakes work is
  floored** (control-plane/sensitive/critical-path force `deep`, and can never be escalated to the expensive
  `apex` tier). `apex` (e.g. a frontier model) is opt-in, per-task, ratified at plan approval — never
  automatic.
- **You bind the tiers to your provider's models** in one adopter-owned file (`.kit/model-map.conf`) — the
  reference binds `deep=opus`/`fast=sonnet`/`light=haiku`; a Codex/Gemini/Cursor adopter maps the same tiers to
  their own model ladder. Opinionated about *structure*, neutral about *which model*.
- **Fan-out economics are measured, not asserted.** A value-analysis model prices each run in *relative
  tier-weight units* ("deep-equivalents"), splitting the builder tier-discount from the orchestrator's
  reassembly tax, so cheaper fan-out is only counted as a win *net of* the integration cost. In one recorded
  experiment the mixed-tier run was **~52% cheaper** than an all-top-tier run for a small wall-clock cost —
  **directional only, not a benchmark**: a single mixed-vs-baseline run-pair across 4 disjoint slices, noisy
  wall-clock, relative units not dollars, conservative weights (so 52% is if anything understated). It shows
  the shape of the trade-off, not a repeatable number.

**Honest ceiling:** the kit *declares* the tier and the intended model; whether a harness actually runs a
subagent on that model is **native to the harness and un-gateable** from the kit. On a single-model harness,
tiering degrades to advisory (one model), never a failure. *Declared ≠ obeyed ≠ bound.*

## 4. Neutral on three axes — stack · harness · model

Every point where a project gets concrete is a swappable axis, chosen by fit and disclosed honestly (no axis
defaults silently to "the proven/rich path"):

- **Stack** — stack-neutral standards + a per-stack profile (10 reference profiles; generate your own for any
  stack against the same conformance bar).
- **Harness** — Claude Code is the reference adapter; any `AGENTS.md`-reading agent works via the `generic`
  adapter; bring your own. The enforcement floor (guard + pre-push hook + CI `agent-boundary` gate) holds
  **regardless of which harness issued the action**.
- **Model** — the abstract tiers above, bound per provider.

## 5. Rigor you can verify — contract → reference → conformance → non-vacuity

Every capability is three parts: a **contract** (the binding requirement), a **reference implementation** (you
own it, rewrite freely), and a **conformance check** (proof it still satisfies the contract). What's rarer:
**the checks are themselves mutation-tested.** A "non-vacuity" sweep neuters a check's failure path and
proves it goes red — so a gate that *can't fail* (a green that can never turn red) is caught and fixed, not
shipped (with an honest `UNCOVERED` bucket for checks that are structurally un-mutation-testable in place). The kit is **built with its own loop** and held to its own Definition of Done — it dogfoods every
gate it gives you.

## 6. Orchestration at scale

The orchestrator fans engineers into **isolated git worktrees** (no cross-slice file contention), runs each
under an independent review, integrates through a serial merge queue, and **meters the whole run with a
runaway kill-switch** (token/step/agent ceilings; raising one is a ratified act). It emits an OTel run trace
that the value-analysis and agent-ops tooling read. *Scaling this further — parallel epics, a worker pool, a
merge queue at scale — is the roadmap's V2/Axis-B work; today's orchestration is proven at task-level fan-out,
and the conductor (the serial review/integrate tail) is the measured bottleneck it will attack.*

## 7. Honest ceilings (read this before trusting a green)

The kit states, per capability, what is **enforced** (a live gate blocks it), **advisory** (a nudge, doesn't
block), or **declared** (an attestation the kit can't observe at runtime):

- The inline guard is a **speed bump**; the **git and CI chokepoints are the real boundary**, equal across
  harnesses — stated plainly, not hidden.
- Model tiering is **declared, not obeyed** (§3).
- Maturity is a **stage, not a version** (`MATURITY.md`): the kit is at `release-candidate`, reaching
  `adopted` when an external team ships real software through the loop — adoption is a maturity stage, not a
  version reset (the kit versions its own releases on its own cadence; the stage story is authoritative in
  `MATURITY.md`).
- A green conformance run proves controls hold **and that DR/resilience safety is documented** — *not that
  those procedures were tested*; the aggregate says so in its own footer.

A kit that tells you exactly what's enforced versus advisory versus declared is more trustworthy than one that
claims magic. That is the design intent, applied to a genuinely governed multi-agent system.
