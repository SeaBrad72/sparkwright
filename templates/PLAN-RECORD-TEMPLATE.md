# Plan record — `<ROW-ID>`

**The plan stage's artifact.** Copy into your project as `docs/plans/<date>-<row-slug>.md` — that path
is the ONE convention (`skills/plan/SKILL.md`), and the head commit of the PR names it in a
`Kit-Plan:` trailer. `conformance/review-lane.sh` refuses a sensitive/control-plane PR, or an ordinary
one whose row is Size M+ (or whose size it cannot read — unknown is owed), whose head carries no `Kit-Plan`
pointing at a tracked, non-stub file. An ordinary docs-only PR and an XS/S ordinary PR owe none (`D-240930-1`).

| Field | Value |
|-------|-------|
| Row | `___` |
| Design of record | `docs/architecture/<date>-<slug>-design.md` |
| Change class (derived, never self-asserted) | `ordinary` \| `sensitive` \| `control-plane` |

## Team
*(Presented to the human after the design GO and before the build; non-blocking, the build proceeds unless the human changes a row. Name seats and tiers, and the concrete model your project's `.kit/model-map.conf` maps each tier to; the table lives only here. Add a row for any change from the project's defaults.)*

| seat | tier | concrete model | why |
|---|---|---|---|
| conductor | ___ | ___ | ___ |
| builder | ___ | ___ | ___ |
| reviewer | ___ | ___ | ___ |
| security | ___ | ___ | ___ |

## Task list
*(The slice, INVEST-sliced into steps you will actually follow. The review record's Rounds table cites
the commits these produce.)*

1. ___
2. ___

## Ceremony budget
One line, derived from the change class, so the owner can veto it in a sentence: ___

## Verification plan
What will be run before the push, and what a green from each actually proves: ___
