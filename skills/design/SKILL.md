---
name: design
description: Use BEFORE any creative or feature work — turning an idea, request, or epic into a validated, owner-approved design/spec. The kit's own design+brainstorm skill (replaces, does not depend on, superpowers brainstorming). Establishes intent, requirements, approaches, and an approved design before any implementation.
---

# Design — turn an idea into a validated, honestly-scoped design

The kit's own design skill: take an idea → a design the owner has approved, through collaborative dialogue plus the kit's design disciplines. Replaces (does not depend on) superpowers `brainstorming`.

<HARD-GATE>
Do NOT write code, scaffold a project, or take any implementation action until you have presented a design and the owner has approved it. Every slice, however simple. A "simple" change gets a short design — but it is still presented and approved.
</HARD-GATE>

## When to use
Before any feature, component, behaviour change, or new project — the moment implementation would otherwise begin.

## The flow (the proven spine)
1. **Explore context first** — read the codebase, the kit's principles (`CLAUDE.md` / `DEVELOPMENT-STANDARDS.md`), recent commits, the relevant design docs. Never design from assumptions.
2. **Clarify — one question at a time** (multiple-choice where possible): purpose, constraints, success criteria. Do not batch questions.
3. **Propose 2-3 approaches** with trade-offs; lead with a recommendation and why.
4. **Present the design in sections** scaled to complexity; get approval per section.
5. **HARD GATE — owner approval before any implementation.**
6. **Write the spec** to `docs/architecture/<date>-<topic>-design.md` (tracked, cold-resumable) or `docs/superpowers/specs/` (local); commit it.
7. **Self-review the spec** — placeholders, internal consistency, scope, ambiguity; fix inline.
8. **Owner reviews the written spec**, then hand to the **plan** skill. Do NOT start implementation from this skill.

## The kit's design disciplines (what makes this MORE than generic brainstorming — apply to EVERY design)
- **Architecture-first.** Design and trade-offs before code; hand the owner the 5-10 lines of meaningful business logic, not boilerplate.
- **Design-intent lens — default-KEEP.** "Low usage / few references" is NOT a cut reason; cut only what is genuinely redundant (content exists elsewhere) or dead. Front-load rigor.
- **Is the provable thing the MEANINGFUL thing?** Before committing a slice, ask whether the proof you can build establishes the thing that matters or an easier adjacent thing. If the only harness-neutral proof is a tautology, or it re-proves an existing slice, or the value is mostly future/declarative → **RE-SELECT the slice.** (Proven-not-prescribed applies to slice *selection*, not just execution.)
- **Agents-vs-skills rule.** A standing agent (seat) is earned only by a distinct skill AND (distinct tools OR must-run-parallel/independent); otherwise it is a skill a seat invokes. Few agents, many skills.
- **Honest ceiling.** Name what is behaviourally provable versus attestation. Never let a green check imply more than it proves; state the ceiling in the design.
- **Non-vacuity.** Every proof needs a positive liveness anchor AND a load-bearing negative — a dead or always-pass mechanism must fail the test.
- **Right-weight / anti-ceremony.** Prefer extending an existing gate to adding one; defer build-ahead (no infrastructure for needs that do not exist yet).
- **Progressive disclosure.** Make the rigorous path the default, surfaced progressively — a novice is not crushed, an expert is not constrained.

## Decompose if too large
If the request spans multiple independent subsystems, decompose into sub-projects first and design the first through this flow. Each sub-project gets its own design → plan → build cycle.

## Terminal state
A committed, owner-approved spec, handed to the **plan** skill. This skill never starts implementation.
