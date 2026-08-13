# [Project Name] — Backlog (Flow Board)

> **Template.** The tactical work-item queue that runs the loop (DEVELOPMENT-PROCESS.md §6). Ordered, not a pile. This is the `BACKLOG.md` backend; swap for GitHub Issues/Linear/Jira per the project `CLAUDE.md` if chosen.

**Created:** [date] · **Backlog backend:** BACKLOG.md (repo-native)

## How to use
- Every item has: **intent** (why) · **acceptance criteria** · **size** (one-flow small) · **risk/complexity tag** · **owner** (human or agent) · **links** (spec/PR/milestone) · **success metric / hypothesis** (how we'll know it worked).
- **Order** by value × urgency ÷ effort-risk — the intent owner ranks; the lead breaks ties on risk/deps. No story points.
- Work types share one board and are prioritized against each other: **feature · bug · tech-debt · spike · recurring**. Tech-debt gets a standing paydown share each cycle.
- Move items down the states as they flow. Entering **In Progress** is an atomic ownership claim (no double-claims).
- **Empty section?** Keep its header table with zero rows (the canonical form shown below), **or** write a bare `None.` — `backlog-current.sh` accepts either as an empty state. A section with any *content* always needs its schema table (so no item is ever tracked without its traceability column).
- A failure/blocked item referencing a `KIT-FEEDBACK.md` finding must `cite the finding by its plain K-id until the synthesis commit tracks` the log; a Markdown link is safe only after that commit (`check-links` resolves against `git ls-files`).

---

## Ready
> Passed the Definition of Ready (the enumerated entry gate in `CLAUDE.md`). Safe to start.
> **Success metric — enforced.** `backlog-current.sh` grades every Ready row: the **Success metric / hypothesis** cell must carry a real value. A blank, a bare marker (`-`, `N/A`, `TBD`, `none`, `?`) and the `N/A — <reason>` idiom all FAIL — a row that cannot say how we'll know it worked is not Ready. **Demote it, don't fill it:** move it to *Backlog (unrefined)* with a dated note and promote it back when it has a metric. The gate proves the cell is *populated*, never that the metric is *true or measurable* — that judgment is the reviewer's.

| Item | Intent (why) | Acceptance criteria | Size | Risk | Type | Owner | Links | Success metric / hypothesis |
|------|--------------|---------------------|------|------|------|-------|-------|-----------------------------|
| [title] | [why] | [testable criteria] | S | low | feature | [who] | [spec] | [how we'll know it worked] |

## In Progress
> WIP-limited. One atomic claim per item.

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| | | | |

## In Review
> Builder ≠ sole reviewer. Awaiting merge gate.

| Item | Reviewer | PR |
|------|----------|----|
| | | |

## Released
> Deployed; awaiting outcome validation (did it move its metric?).

| Item | Released | Success metric / hypothesis |
|------|----------|------------------------------|
| | | |

## Done
> Definition of Done met, L1 retro written, outcome validated.
> **Taste-surface?** If the item shipped a user-facing taste-surface, tag the **Item** cell with `[taste-surface]` and record a `UAT-SIGNOFF` reference — a link or path to the UAT sign-off (e.g. `docs/uat/UAT-SIGNOFF-<item>.md`) — in the **Retro/outcome** cell. `backlog-current.sh` (HITL-3) enforces the sign-off record on any Done row carrying that flag; an unflagged row is N/A. (Presence of the reference is checked, not that the link resolves — the diff-level backstop is HITL-2's PR-context gate.)
> **L1 retro — enforced.** `backlog-current.sh` (HITL-6) grades every Done row: the **Retro/outcome** cell must carry real substance (a stub like `done` is rejected), and a row whose **Closed** date is on/after `2026-07-24` must additionally contain the marker `L1 retro`. Write what shipped *and* what you learned — e.g. `… ramped with no rollback. **L1 retro:** the thin-slice pattern held; the cost was all ceremony, not build.` A row with an unparseable **Closed** date is treated as recent and asked for the marker (fail-closed), so keep the date in `YYYY-MM-DD`. Rows closed before that date are exempt from the marker only — the substance floor always applies.

| Item | Closed | Retro/outcome |
|------|--------|---------------|

## Blocked
| Item | Blocked on | Since | Event-retro link |
|------|-----------|-------|------------------|

---

## Backlog (unrefined)
> Validated candidates from Discover, not yet Ready. The roadmap/parking-lot lives separately (strategic altitude).

- [ ] [candidate] — [intent] — [risk tag]

**Last Updated:** [date]
