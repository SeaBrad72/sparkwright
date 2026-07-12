# Field Report — end-of-dogfood synthesis

> **Template.** The **END-OF-DOGFOOD** synthesis — the "what did we learn" doc, distinct from the running `KIT-FEEDBACK.md` log. Write it once a dogfood (a build on a real or synthetic vehicle) is done: turn the raw friction rows into a verdict and a prioritized harvest the kit's backlog can absorb. Keep the same stamp as the feedback log so the report is attributable to a kit version + vehicle + harness.

## Stamp

| Field | Value |
|-------|-------|
| **Kit version** | `[e.g. 3.119.0]` (`cat VERSION` at adoption) |
| **Vehicle** | `[product / repo name]` |
| **Harness** | `[claude-code / codex / …]` |
| **Track** | `[solo / team]` |
| **Period** | `[YYYY-MM-DD → YYYY-MM-DD]` |
| **Feedback log** | `[link to the KIT-FEEDBACK.md this synthesizes]` |

## 1. Verdict

> Two or three sentences: did the kit hold? What is the single biggest thing it got right, and the single biggest gap? Be honest — a flattering report is a wasted dogfood.

[...]

## 2. Prioritized harvest

> The findings from `KIT-FEEDBACK.md`, ranked for the backlog. Group by severity; name the K-id so a reader can trace it back to the live row. Call out any root cause that explains multiple findings (Relay's K7 "provided but not wired" explained five).

| Rank | K-id(s) | Finding | Severity | Proposed backlog item |
|------|---------|---------|----------|-----------------------|
| 1 | K.. | [the finding] | [high] | [KW.. / new item] |
| 2 | | | | |

## 3. What the review / guardrail layer caught

> The kit's differentiator is the review + guardrail core. Name the author-blind bugs an independent reviewer, a conformance check, or a fail-closed default caught that the builder shipped as passing — this is the evidence the layer works (or didn't).

- `[e.g. dual review caught H1 vacuous/green-because-skipped gate — PR #NN]`

## 4. What never ran

> The honest ceiling: which kit capabilities were **built + conformance-checked but never exercised** on this vehicle (e.g. the orchestrator, ops-in-anger, the AI/eval path). "Provided but not proven" is a finding, not a pass.

- `[e.g. the orchestrator fan-out never ran — single-agent path throughout]`

## 5. Wins to keep

> What worked and must not regress. These become guardrails, not just praise.

- `[...]`
