# [Feature Name] — Spec (PRD)

> **Template.** The design/PRD produced at the **Plan** stage (`DEVELOPMENT-PROCESS.md` §4, the Loop) and signed off at the **spec gate** (§7, Gates & Checkpoints), from a validated `FEATURE-REQUEST` (or direct Discovery). Tool-neutral — if you use the superpowers brainstorming flow, that produces an equivalent spec; this is the manual form. A reviewer signs off before Build begins.

**Author:** [name / agent] · **Intent owner:** [who accepts it] · **Date:** [date] · **Status:** draft / in review / approved

## How to use
- Every section is required unless marked optional. "Could be interpreted two ways" means pick one and write it down.
- Acceptance criteria must be **testable** — they become the tests and the Reviewer's checklist.
- Approved spec → Build. Scope changes after approval are a new revision, noted here.

---

## Context & problem
> The problem and why now. Link the originating `FEATURE-REQUEST` if there is one.

[...]

## Goals & non-goals
> What this delivers; what it explicitly does **not** (the YAGNI fence).

[...]

## Users & personas
> Who uses this and in what role (see the persona map, `DEVELOPMENT-PROCESS.md` §2).

[...]

## Functional requirements
> Numbered, specific behaviors the system must exhibit.

[...]

## Acceptance criteria (testable)
> Pass/fail conditions. Each maps to at least one test. 100% on critical paths (auth, payments, data integrity).

[...]

## UX & accessibility notes
> Flows, states, designer handoff links. WCAG 2.1 AA obligations for any user-facing UI.

[...]

## Data & privacy considerations
> What data is touched; PII/consent/retention/children's-data implications (`DEVELOPMENT-STANDARDS.md` §2 + the enterprise privacy family in `docs/enterprise/compliance-crosswalk.md`). "None" is a valid, explicit answer.

[...]

## Risks & mitigations
> What could go wrong technically or operationally, and the mitigation.

[...]

## Out of scope
> Deferred or explicitly excluded — so reviewers don't flag them as gaps.

[...]
