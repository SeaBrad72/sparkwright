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
| 1 | **FRAME** | Product | Frame approved | this layer → [frame.md](frame.md) |
| 2 | **SHAPE** | Design | Direction chosen | this layer → [shape.md](shape.md) |
| 3 | **PLAN** | Product | Ready | **Sparkwright engine** — `DEVELOPMENT-PROCESS.md` §5–6 + FEATURE-REQUEST/SPEC + Definition of Ready |
| 4 | **BUILD** | Engineering | (build) | **Sparkwright engine** — the loop |
| 5 | **SHIP** | Engineering | Merge & ship | **Sparkwright engine** — Review/Release |
| 6 | **OBSERVE** | Product+Eng | (loop back) | **Sparkwright engine** — Operate |

**Stages 3–6 already are Sparkwright's loop** (Plan → Build → Review/Release → Operate). They are
shown here only to place FRAME and SHAPE; they are unchanged by this layer.

## The seam: Ready

FRAME produces an **Opportunity Brief** ([template](../../templates/OPPORTUNITY-BRIEF-TEMPLATE.md));
SHAPE produces a **Shaping Doc** ([template](../../templates/SHAPING-DOC-TEMPLATE.md)). Together they
feed PLAN, which produces a **Ready** story via the existing FEATURE-REQUEST/SPEC templates and the
**Definition of Ready**. That gate is the handoff into the engine — the layer touches nothing downstream.

## Where AI assists vs. where the human decides

Across all stages, the rule is the same: **AI does the tasks; the human takes the turns that carry
judgment, accountability, or a gate.** AI normalizes, synthesizes, drafts, prototypes, scores; the
human frames the problem, chooses direction, sets priorities, and approves each gate. The per-stage
split is in [frame.md](frame.md) and [shape.md](shape.md). It is **guidance, not an automated gate** —
discovery is judgment work.

## Honesty

A green `conformance/discovery-complete.sh` means this layer is **present and wired** — not that your
discovery was good or your problem truly validated. The guard and gates remain the safety net.
