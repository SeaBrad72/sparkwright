# The decision record — [Project Name]

> **Template.** `scripts/incept.sh` stamps this to `docs/governance/DECISIONS.md`, empty, at Inception. Delete this line and start recording.

Your project's ledger of rulings. The entry contract (§1 of your project guide) tells every agent to
search this file before changing a surface — so a ruling that lives only in a chat transcript does
not exist.

**Status:** empty — no rulings recorded yet.

---

## 1. Why this file exists

Most artifacts record **conclusions** and discard the **decision record**: who decided, when, on what
basis, what it supersedes, and what would reverse it. Conclusions stripped of their reasoning read as
confident, cannot be defended when challenged, and get silently re-derived by the next session or the
next agent. The people who were in the room become the only durable store.

This file is the index the rest point into — the single answer to *"what was already decided about
this?"* ADRs, design docs and promotion records all cite into it.

## 2. How to use it

- **Before proposing anything that reverses, deletes, defers or re-sequences work — or that proposes
  a new mechanism on a surface an earlier ruling already touched — search this file.** A mechanism
  proposal counts: the failure is not only "reversing a ruling", it is re-deriving one from scratch.
- **Every entry carries a verbatim quote and a citation** (a path, a heading, or a commit SHA) so any
  row can be spot-checked in seconds. A row you cannot verify from its citation is a defect — say so.
- **`REVISIT-CONDITION` is load-bearing.** A ruling whose condition is unmet is not available to be
  scheduled. Scheduling it anyway is how a settled question gets re-opened by accident.
- **Reversing a ruling requires a new entry that names the one it overturns.** Silent contradiction
  is rejected. The old entry stays: the record is append-only, because its value is the history.

## 3. The grammar of a ruling

Each ruling is one block. The **header line starts at column 1** and opens with the id in backticks —
that is what tooling matches, so keep the shape exactly:

```markdown
**`D-YYMMDD-N` · <kind> · <the ruling, in one sentence, as a decided thing.>**

**BASIS:** what the decision rests on — the evidence, the measurement, the trade-off accepted.
**SUPERSEDES:** the id(s) this overturns, or `none`.
**REVISIT-CONDITION:** the fact that would make this worth re-opening, or `none`.
```

- **id** — `D-` then the date as six digits (`YYMMDD`), then `-` and a number that restarts each day.
  Sub-points of one ruling are `.1`, `.2` on the same id; they never get their own header.
- **kind** — `ruling` · `greenlight` · `deletion` · `supersession` · `deferral` · `re-confirmation`.
- **one sentence** — write the DECISION, not the discussion. If it needs a paragraph, the paragraph
  goes in `BASIS`.
- **who and when** — the date is in the id; the ratifier is whoever the project's Definition of Done
  names. Record the name if more than one person can ratify.

## 4. Rulings

*(None yet. Add the newest at the top, so the current state is the first thing read.)*
