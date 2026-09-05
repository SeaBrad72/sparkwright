# Plan record — `<ROW-ID>`

**The plan stage's artifact.** Copy into your project as `docs/plans/<date>-<row-slug>.md` — that path
is the ONE convention (`skills/plan/SKILL.md`), and the head commit of the PR names it in a
`Kit-Plan:` trailer. `conformance/review-lane.sh` refuses a sensitive/control-plane PR (and any
non-docs-only ordinary one) whose head carries no `Kit-Plan` pointing at a tracked, non-stub file.

| Field | Value |
|-------|-------|
| Row | `___` |
| Design of record | `docs/architecture/<date>-<slug>-design.md` |
| Change class (derived, never self-asserted) | `ordinary` \| `sensitive` \| `control-plane` |
| Seats | builder ___ · reviewer ___ · security ___ |

## Task list
*(The slice, INVEST-sliced into steps you will actually follow. The review record's Rounds table cites
the commits these produce.)*

1. ___
2. ___

## Design-promised controls
**Carried forward from the design, verbatim — this table is the SOURCE for the review record's table of
the same name.** Every promise the design makes about a control that will exist gets a row here, and at
review time each row must resolve to `path::test-name` or be recorded as `not built, because <reason>`.
A design promise with no row here is how a control quietly stops being built.

| control (from the design) | expected discharge |
|---|---|
| ___ | `path::test-name` |

## Ceremony budget
One line, derived from the change class, so the owner can veto it in a sentence: ___

## Verification plan
What will be run before the push, and what a green from each actually proves: ___
