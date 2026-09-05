# Review Record

**The recorded independent review + ratification for one change** — the solo lane's evidence that
`builder ≠ reviewer` was satisfied without a second human (`../docs/operations/review-lane.md`).
⚠️ THE NEXT SENTENCE MUST STAY ON ONE LINE — `conformance/review-lane.sh` refuses a record that still
carries it (`RL-RECORD-IS-TEMPLATE`), and it matches the phrase with `grep -F`, so a line wrap disarms
the check silently. It was wrapped until 2026-09-04 and the marker never fired on the real file.
Copy into your project (or attach to the PR/audit record), one per change. **Default-tier** changes need the
top three sections; **high-risk** changes (control-plane · security/auth boundary · data/schema
migration · prod deploy · money/irreversible) ALSO need the **Acknowledgments** section.

| Field | Value |
|-------|-------|
| Change / PR | #___ |
| Risk tier | `default` \| `high-risk` — trigger: ___ |
| Builder | ___ |
| Independent review by | the kit's `reviewer` (+ `security-reviewer` if a security/auth/data/AI boundary) subagent — findings recorded below |

---

## THE GRADED SHAPE (`conformance/review-lane.sh`)

Everything from here to *Attestation* is **machine-graded**. Copy this record to
`docs/reviews/<date>-<row-slug>.md`, name it in the head commit's `Kit-Review:` trailer, and delete
nothing below — an absent section is a refusal, not a silence. The sections **after** this block are
the older, un-graded lane material and are kept: they are what a human reviewer actually fills in.

The two identity lines are read with `grep -m1 '^Builder:'` / `'^Reviewer:'`, so the shape example
below is INDENTED — an example at column 0 would be the first match and the grader would read the
placeholder instead of your value (measured, 2026-09-04):

```
  Builder: <seat/model/identity>
  Reviewer: <seat/model/identity>        ← MUST differ from Builder
```

Builder: ___
Reviewer: ___

## Rounds
One row per review round. Every `commit` must be inside this PR (an ancestor of the head, and not
already in the base). The **last** round must be `APPROVE`, and every commit after it must be
bookkeeping only (`docs/reviews/`, `docs/plans/`, `BACKLOG.md`) — a code commit after the approval
re-opens the round, because nobody has reviewed it.

| commit | reviewer seat | verdict (APPROVE\|NEEDS-FIXES) | findings (n) |
|---|---|---|---|
| ___ | ___ | ___ | ___ |

## Findings
Every row needs a disposition **in the grammar**: `fixed <sha>` · `accepted — <reason>` ·
`waived — WAIVER-<id>` (the id must exist in `WAIVER-REGISTER.md`). A `fixed <sha>` must name a commit
**inside this PR** — a real commit, an ancestor of the head and not already in the base, or the gate
refuses it (`RL-FIX-OUTSIDE`): a fix that lives outside the PR is a fix this PR does not carry, and an
unchecked sha disposes of a finding with a string. An empty table is legal and means *no findings* — a
recordable result.

| id | file:line | severity | disposition |
|---|---|---|---|

## Design-promised controls
Carried from the plan record's table of the same name. Each row resolves to `path::test-name` — where
the token appears on an **executable line**, not a comment — or says `not built, because <reason>`.

| control (from the design) | discharged by |
|---|---|
| ___ | `path::test-name` |

## Security review
`D-240904-1`: the diff security review is the default. One of:

- `ran — seat <…>, verdict: <…>` (findings go in the table above), or
- `waived — no-untrusted-input · no-new-permission · no-control-plane-surface · no-operator-shell`
  (all four criteria, verbatim, or it is not a waiver).

ran — seat ___, verdict: ___

> **The non-self-attested half needs nothing from you here.** The reviewer types no attestation: a
> plain non-author **Approve** on the graded head *is* the attestation (`D-240904-2`). Since
> `REVIEW-LANE-WAITING-IS-GREEN` (2026-09-05) **branch protection** is what enforces it — a non-author
> approval, dismissed by any later push, from someone who did not push the head — and `review-lane`
> grades this file only. There is no line to paste and no `## Attestation` section — if you are working
> from an older copy of this template, delete it.

---

## Quality-lens rubric (what to check)
> Applied at the §7 Review gate alongside the correctness + security review. A reviewer (human or agent)
> marks each dimension — this is judgment, not a gate: flag concerns, don't rubber-stamp. The results go
> in *Agent-review findings* below. See `../docs/operations/code-quality.md`.

- [ ] **Readability** — a new reader follows it without the author present.
- [ ] **Simplicity (DRY / YAGNI)** — no needless abstraction; no copy-paste that should be one unit.
- [ ] **Function size & single-purpose** — small; one job; early returns over deep nesting.
- [ ] **Naming** — meaningful, intention-revealing (no throwaway names except loop counters).
- [ ] **Comment quality** — explains *why* / intent, not narration; no stale/rotted comments.
- [ ] **Type / interface design** — strong invariants + encapsulation; illegal states hard to represent.
- [ ] **Cohesion / coupling** — one responsibility; internal changes don't ripple to consumers.
- [ ] **Error handling** — structured, with codes; no swallowed errors / silent fallbacks.
- [ ] **No dead code · no debug output · no hardcoded values** that belong in config.
- [ ] **Tests** — meaningful (assert behavior, not implementation); critical paths covered.

## Agent-review findings
*(Paste the reviewer subagent's findings — correctness/quality, and security where applicable — each with a verdict. "No findings at severity X" is a valid, recordable result.)*

- ___

## Human ratification
- **Ratified by:** ___ *(≠ builder where a second human with write access exists; solo: the accountable maintainer, recorded)*
- **Date:** ___
- **Disposition:** findings addressed · accepted-with-reason · waived *(cite exception ID in `WAIVER-REGISTER.md`)*

## High-risk acknowledgments  *(REQUIRED for the high-risk tier — the anti-theater requirement)*
For **each material finding**, a *specific* acknowledgment tied to it — never a bare "approved":

- Finding ___ → *I reviewed this; resolved by ___ / accepted because ___.*
- Control-plane / security obligation ___ → *acknowledged: ___.*

## Compensating control (solo)
This bundle — a **recorded independent agent-review** + an **accountable recorded human ratification** +
the **automated gates** (CI, the `agent-boundary` control-plane gate, the guard) — is the legitimate
compensating control for true two-human segregation of duties at solo scale. Recorded from day one, the
evidence carries over with **zero rework** when a second human with write access joins: their non-author
approval satisfies the required-review rule, and a single **`enforce_admins: true`** flip then enforces
real two-human SoD (that flip is what removes the owner `--admin` bypass). See
`../docs/operations/review-lane.md`.

> **Honest ceiling.** This record is *process discipline, not a fail-closed gate* — a solo human can
> skip writing it (mechanically blocking it requires a second actor the solo case lacks). The kit makes
> it the path of least resistance and audit-visible; the `agent-boundary` CI gate still forces
> ratification on any control-plane diff regardless.
