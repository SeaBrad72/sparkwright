# [Feature / Story] — Test Plan

> **Template.** Delete the guidance; fill each section. QA owns this artifact — the test lens of the Reviewer function (`DEVELOPMENT-PROCESS.md` §2/§12). It turns a spec's acceptance criteria into a concrete, traceable test strategy, and is the input the `UAT-SIGNOFF-TEMPLATE.md` record points back to. Tool-neutral — drop it on the PR or store it under `docs/test-plans/`.

**Author (QA):** [name / agent] · **Date:** [date] · **Status:** draft / in review / approved

## How to use
- Every section is required unless marked optional. "None" is a valid, explicit answer.
- The **Cases → acceptance criteria** table is the load-bearing part: it ties each test back to the Product Owner's `FEATURE-REQUEST-TEMPLATE.md` (its *Extended spec* / acceptance criteria) so coverage is auditable, not assumed.
- Entry/exit criteria gate this plan; the exit criteria feed the §9 Dev→QA→**UAT** promotion.

---

## Feature / story
> What is under test, and the source of truth for its behavior. Link the originating `FEATURE-REQUEST-TEMPLATE.md` (and its approved *Extended spec* section, if used).

[...]

## Scope & risk areas
> What this plan covers and where the risk concentrates (critical paths — auth, payments, data integrity — get the most attention).

[...]

## Test levels
> What each level covers **for this feature** specifically.
- **Unit** — [isolated logic / validators / pure functions covered here]
- **Integration** — [service + data boundaries covered here]
- **e2e** — [critical user journeys covered here; "N/A" if none]

[...]

## Cases → acceptance criteria
> One row per test case, mapping it to the acceptance criterion it verifies. This is the traceability tying QA back to the PO's acceptance criteria. Every critical-path criterion must have at least one case.

| Test case | Level | Acceptance criterion verified | Status |
|-----------|-------|-------------------------------|--------|
| [case description] | unit / integration / e2e | [criterion ref] | pass / fail / blocked |

## Environments
> Where each level runs, per the §9 promotion tiers (`DEVELOPMENT-PROCESS.md` §9 — Environments & promotion). Typically Dev for unit/integration, QA for the integration acceptance suite.

[...]

## Entry / exit criteria
> **Entry** — what must be true before testing starts (e.g. spec approved, build deployed to QA). **Exit** — what must be true to call testing complete (e.g. all critical-path cases pass, no open P0/P1). Exit criteria gate the UAT promotion.

[...]

## Out of scope
> What this plan deliberately does **not** test — so reviewers don't flag it as a gap.

[...]
