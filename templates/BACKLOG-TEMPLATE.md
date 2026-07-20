# [Project Name] — Backlog (Flow Board)

> **Template.** The tactical work-item queue that runs the loop (DEVELOPMENT-PROCESS.md §6). Ordered, not a pile. This is the `BACKLOG.md` backend; swap for GitHub Issues/Linear/Jira per the project `CLAUDE.md` if chosen.

**Created:** [date] · **Backlog backend:** BACKLOG.md (repo-native)

## How to use
- Every item has: **intent** (why) · **acceptance criteria** · **size** (one-flow small) · **risk/complexity tag** · **owner** (human or agent) · **links** (spec/PR/milestone).
- **Order** by value × urgency ÷ effort-risk — the intent owner ranks; the lead breaks ties on risk/deps. No story points.
- Work types share one board and are prioritized against each other: **feature · bug · tech-debt · spike · recurring**. Tech-debt gets a standing paydown share each cycle.
- Move items down the states as they flow. Entering **In Progress** is an atomic ownership claim (no double-claims).
- **Empty section?** Keep its header table with zero rows (the canonical form shown below), **or** write a bare `None.` — `backlog-current.sh` accepts either as an empty state. A section with any *content* always needs its schema table (so no item is ever tracked without its traceability column).
- A failure/blocked item referencing a `KIT-FEEDBACK.md` finding must `cite the finding by its plain K-id until the synthesis commit tracks` the log; a Markdown link is safe only after that commit (`check-links` resolves against `git ls-files`).

---

## Ready
> Passed the Definition of Ready (the enumerated entry gate in `CLAUDE.md`). Safe to start.

| Item | Intent (why) | Acceptance criteria | Size | Risk | Type | Owner | Links |
|------|--------------|---------------------|------|------|------|-------|-------|
| [title] | [why] | [testable criteria] | S | low | feature | [who] | [spec] |

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
