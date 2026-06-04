# Agentic SDLC Kit

A complete, **stack-agnostic** software development lifecycle designed for teams working with AI agents — from idea through released, operating software. Drop it into a new project, choose your stack, and go.

It is opinionated about *how to build well with agents* and deliberately neutral about *what you build it with*.

## Who it's for
Any team — humans, agents, or both — starting a new project who wants production-grade discipline without inventing a process from scratch. Adopt it as-is, or hand it to a team and let them tailor it.

## What's inside

| File | What it is |
|------|-----------|
| **`START-HERE.md`** | Run first — walks you through Inception, including choosing your stack. |
| **`WALKTHROUGH.md`** | A narrative of the kit in motion — one feature from idea to operating software. |
| **`CLAUDE.md`** | Principles + Definition of Done. Authoritative. |
| **`DEVELOPMENT-PROCESS.md`** | The agentic SDLC: Inception → Discover → Plan → Build → Review → Release → Done → Operate ↺. |
| **`DEVELOPMENT-STANDARDS.md`** | The universal, stack-neutral quality bar. |
| **`profiles/`** | Per-stack specifics. `typescript-node.md` reference profile + `_TEMPLATE.md` to generate your own for *any* stack. |
| **`templates/`** | `PROJECT-CLAUDE-TEMPLATE.md`, `BACKLOG-TEMPLATE.md`. |
| **`docs/`** | `ADR-000-EXAMPLE.md` — worked stack-decision record. |

## Quickstart (drop-in & go)
1. Copy this kit into your new project repo.
2. Open **`START-HERE.md`** and work through Inception (Phase 0).
3. At stack selection: pick a ready profile **or** generate one from `profiles/_TEMPLATE.md` for your stack — recorded as **ADR-000**.
4. Pass the **Inception Done** gate → enter the loop at **Discover**.

## The core ideas
- **Governing lens:** rituals that *manage human effort* die; rituals that *clarify intent or improve quality* get stronger. Agent effort is cheap; human attention and integration risk are the scarce resources.
- **Flow, not sprints:** WIP-limited kanban; humans are the pacing metronome at the gates.
- **Closed loop:** production feeds the next idea; every retro exits into an artifact (the "adjust" step).
- **Agent governance:** autonomy tiers by risk × reversibility; irreversible actions are human-gated; autonomy is earned by metrics.
- **Universal + profile:** standards stay stack-neutral; the one stack-specific layer is a swappable profile.

## Adapting it
Everything is meant to be tailored. Stack-specific → a profile. Project-specific → the project's own `CLAUDE.md`. Org-specific (stakeholder cadence, spend thresholds, SLO gating) → the configuration hooks the docs call out. Keep the universal files universal.

## License
[Choose a license before distributing.]
