# The Discovery Loop — from raw signal to Ready (optional, upstream)

> **Optional layer.** Sparkwright's engine starts at a **Ready** backlog. If you already have product
> and design figured out, **skip this entirely** — go to [START-HERE.md](../../START-HERE.md) and build.
> This layer is the *front porch* for turning raw signals into Ready work; it is never a turnstile.

## The whole loop at a glance

A product moves through six stages. Each stage names an **owner**, what it **absorbs** (the legacy
activities it replaces), its **ART** (human turns — where a person decides), its **AI** (the tasks AI
does), a **gate**, and **loop-backs** (a later stage routing deliberately back — *change, not noise*).

| # | Stage | Owner | Gate | Where it lives |
|---|-------|-------|------|----------------|
| 1 | **FRAME** | Product | Frame approved | this layer → the **FRAME** section below |
| 2 | **SHAPE** | Design | Direction chosen | this layer → the **SHAPE** section below |
| 3 | **PLAN** | Product | Ready | **Sparkwright engine** — `DEVELOPMENT-PROCESS.md` §5–6 + FEATURE-REQUEST/SPEC + Definition of Ready |
| 4 | **BUILD** | Engineering | (build) | **Sparkwright engine** — the loop |
| 5 | **SHIP** | Engineering | Merge & ship | **Sparkwright engine** — Review/Release |
| 6 | **OBSERVE** | Product+Eng | (loop back) | **Sparkwright engine** — Operate |

**Stages 3–6 already are Sparkwright's loop** (Plan → Build → Review/Release → Operate). They are
shown here only to place FRAME and SHAPE; they are unchanged by this layer.

> **FRAME/SHAPE vs. the loop's "Discover" (§5).** The core loop's `DEVELOPMENT-PROCESS.md` §5 Discovery
> is the *light* intake — it validates a candidate that already has a problem and a sponsor. FRAME and
> SHAPE are the **richer expansion upstream of it**: they're how a *raw* signal becomes that validated,
> shaped candidate in the first place. Same territory, more structure — not a competing stage. Skip
> them and §5 still works exactly as written.

## FRAME — turn raw signals into a framed problem

**Owner:** Product · **Gate:** Frame approved · **Absorbs:** intake · research · requirements planning

FRAME is where a raw signal (an idea, a stakeholder ask, research, a support trend) becomes a
**framed problem** worth pursuing — with evidence and a target outcome — *before* anyone designs or
builds. Output: an **[Opportunity Brief](../../templates/OPPORTUNITY-BRIEF-TEMPLATE.md)** that clears
the *Frame approved* gate.

### Human turns (ART) — where you decide
- **Frame the problem** — what, for whom, why now; the pain in one sentence.
- **Target outcome / OKR** — the measurable change you want (a hypothesis, not a feature).
- **Big ideas** — the candidate directions worth shaping.
- **Frame approved** — the gate: this is real and worth Design's time. (Owner decision.)

### AI tasks — where AI helps
- **Normalize intake** — turn messy signals (tickets, notes, transcripts) into a structured brief.
- **Research synthesis** — summarize evidence, prior art, comparable solutions.
- **Draft requirements** — propose a first-cut problem statement + outcome for you to sharpen.

### Loop-backs
From SHAPE or later: if shaping reveals the problem was mis-framed, route back here deliberately —
re-frame, don't paper over it.

## SHAPE — turn a framed problem into a chosen direction

**Owner:** Design · **Gate:** Direction chosen · **Absorbs:** concept · design · architecture exploration · reviews

SHAPE takes a Frame-approved problem and explores **how** to solve it — concept, design intent, and a
viable architecture approach — far enough to commit a direction, *not* to final pixels or code.
Output: a **[Shaping Doc](../../templates/SHAPING-DOC-TEMPLATE.md)** that clears *Direction chosen* and
feeds PLAN.

### Human turns (ART) — where you decide
- **Concept direction** — the approach you're committing to.
- **Design intent** — the experience and the non-negotiables (incl. the a11y obligation the DoD checks).
- **Architecture approach** — the shape of the solution; feasibility and big risks named.
- **Direction chosen** — the gate: enough to plan and slice. (Owner decision.)

### AI tasks — where AI helps
- **Rapid prototypes** — generate low-fidelity options to react to.
- **Design explorations** — variations, comparisons, edge-case probing.
- **Option synthesis** — pull the explorations into a small set of real choices + tradeoffs.

### Loop-backs
From PLAN/BUILD: if planning or building invalidates the direction, route back here — re-shape, then
re-enter PLAN. From FRAME: a re-frame restarts shaping.

## The seam: Ready

FRAME produces an **Opportunity Brief** ([template](../../templates/OPPORTUNITY-BRIEF-TEMPLATE.md));
SHAPE produces a **Shaping Doc** ([template](../../templates/SHAPING-DOC-TEMPLATE.md)). Together they
feed PLAN, which produces a **Ready** story via the existing FEATURE-REQUEST/SPEC templates and the
**Definition of Ready**. That gate is the handoff into the engine — the layer touches nothing downstream.

## Where AI assists vs. where the human decides

Across all stages, the rule is the same: **AI does the tasks; the human takes the turns that carry
judgment, accountability, or a gate.** AI normalizes, synthesizes, drafts, prototypes, scores; the
human frames the problem, chooses direction, sets priorities, and approves each gate. The per-stage
split is in the **FRAME** and **SHAPE** sections of this page. It is **guidance, not an automated gate** —
discovery is judgment work.

## Honesty

A green `conformance/discovery-complete.sh` means this layer is **present and wired** — not that your
discovery was good or your problem truly validated. The guard and gates remain the safety net.
