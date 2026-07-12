---
name: demonstrate
description: Use at a notable increment with a taste-surface, before a human Go/No-Go — the kit's own increment-demonstration craft (a kit-original; superpowers has no demonstrate craft). Proactively surface a working, observable increment for the human's taste/judgment, frame the specific judgment call, and record the verdict in a UAT sign-off. Distinct from review (agent→agent correctness) and verification (agent→self evidence).
---

# Demonstrate — surface a working increment for human taste/judgment (the informed half of Go/No-Go)

The kit's own increment-demonstration craft: at a notable increment (slice / sub-slice / epic) that carries a **taste-surface** — a place where *correct ≠ good* — proactively produce a working, observable thing for the human to *react to*, frame the exact judgment call, and record the verdict. This is the **"informed" half** of the promotion Go/No-Go: the human cannot render a good GO on UX/flow/working-functionality they never saw. An existing seat (Engineer / Reviewer / Orchestrator) invokes this craft — it is a **skill, not a new seat** (agents-vs-skills: the kit adds a discipline, not a standing role).

**Distinct discipline** (why it earns a skill slot): different *audience* and *purpose* than its neighbours. `review` is agent→agent, judging **correctness**. `verification` is agent→self, producing **evidence** before a done-claim. `demonstrate` is **agent→human**, surfacing **taste/UX judgment** — the class of question a green test can never answer ("does this flow *feel* right?").

<!-- The frontmatter and the discipline phrases below are conformance-load-bearing:
     conformance/orchestrator-loop-wired.sh greps this file for these exact kit-distinctive
     markers (each quoted — preserve them verbatim, none may contain a pipe char or a TAB):
       "name: demonstrate"  "## When to use"  "taste-surface"
       "demonstrable increment"  "frame the specific judgment call"
       "visually-observable-first"  "verdict recorded in a UAT sign-off"
     Edits that drop or rename any of them can turn the skill-spine lock RED. -->

## When to use
At **each notable increment** (a slice, a sub-slice, or an epic) that has a **taste-surface** — UI, UX, a user flow, working functionality, a rendered data table: anything where *correct ≠ good* — **before the human Go/No-Go**. If the increment is pure plumbing with no taste-surface (a refactor behind a stable interface, a conformance-lock edit), there is nothing to demonstrate — skip it honestly. The trigger is the taste-surface, not the calendar.

## The craft — the flow
1. **Detect the taste-surface.** Scan the increment for the place where *correct ≠ good*: a screen, a flow, a table, a piece of working functionality a person would form an opinion about. No taste-surface → nothing to demonstrate.
2. **Produce the observable — a thing to react to, not a description.** Spin up an instance, capture a screenshot, render the table, run the flow end to end. The output is a **demonstrable increment** the human can *look at and judge*, never a paragraph claiming it works. A description is what `verification` produces for correctness; `demonstrate` produces the artifact itself.
3. **Frame the specific judgment call.** Ask the real question — "does this checkout flow feel right?", "is this table scannable?", "would you ship this empty state?" — never "LGTM?". A blind nod is the K16 hole wearing a UX hat; **frame the specific judgment call** so the human engages the actual taste question, not a rubber stamp.
4. **Record the verdict.** The **verdict recorded in a UAT sign-off** — the existing `templates/UAT-SIGNOFF-TEMPLATE.md` (accept / reject + the demonstrated evidence + signer + date). Reuse it; do **not** invent a parallel artifact.
5. **Ordering rule — visually-observable-first.** When task sequencing is otherwise indifferent, build the **visually-observable-first**: put the thing a human can react to earliest, so there is something to engage with while the rest is still forming. Early observability turns a late surprise into an early course-correction.

## Autonomy coupling (KW20) — density scales with human distance
Autonomy modulates *demonstrate density*. When you **fan out N agents** with the human out of the loop, a demonstrable increment is the human's **only** window onto taste — so demonstrable increments are **mandatory and frequent**; the observable substitutes for the absent human glance. On a **small, human-proximate build** where the human is already watching the work, the touch is **lighter** — the human's live attention already covers much of what a formal demonstration would surface. Same rigor, different composition: the further the human is from the keyboard, the more the taste-check must be paid in demonstrated artifacts rather than over-the-shoulder glances.

## Honest ceiling
Whether the human **actually looks** is un-gateable — no CI check proves a person engaged their taste. The provable **FLOOR** is *increment demonstrated + judgment call framed + verdict recorded in a UAT sign-off*; that is the harness-neutral core this skill guarantees. A NATIVE harness that auto-launches the instance or embeds the screenshot is a **bonus**, never the FLOOR. This slice ships the discipline **advisory**: the promotion-readiness surfacing raises the obligation at every RC promotion, and `build` / `review` reference it — but a *hard* "taste-surface touched + no record → fail CI" gate (a bespoke taste-surface detector) is deliberately **not** built here; it rides the KW7 generic obligation-trigger mechanism as a co-follow, so the trigger is designed once, not twice.

## Rationalizations to refuse
| Rationalization | Why it fails |
|---|---|
| "The tests are green, so it's good." | Green proves *correct*, not *good*. A taste-surface is exactly where *correct ≠ good* — demonstrate it and let a human judge. |
| "I'll describe what it does instead of showing it." | Produce the **demonstrable increment** — a thing to react to. A description is `verification` evidence; taste needs the artifact itself. |
| "I'll just ask 'LGTM?'." | **Frame the specific judgment call** — "does this flow feel right?", not a blind nod. A rubber stamp is the K16 hole in a UX hat. |
| "The reviewer already approved it." | `review` is agent→agent correctness; it does not surface taste to the human. Different audience, different purpose — both are needed. |
| "I'll note it in the PR body; no need for a sign-off." | The **verdict recorded in a UAT sign-off** is the auditable record — reuse `templates/UAT-SIGNOFF-TEMPLATE.md`; PR prose is not the record. |
| "We're fanning out ten agents; I'll demo at the very end." | Autonomy raises demonstrate density — fan-out means demonstrable increments are **mandatory and frequent**, the human's only window. Demo per increment, not once at the end. |
| "I'll build the observable thing last, after the plumbing." | **visually-observable-first** when ordering is indifferent — early observability turns a late surprise into an early course-correction. |

## Terminal state
For each notable increment carrying a taste-surface: the taste-surface was detected, a **demonstrable increment** was produced (an observable thing to react to, not a description), the **specific judgment call** was framed for the human, and the **verdict recorded in a UAT sign-off** (`templates/UAT-SIGNOFF-TEMPLATE.md`) — with the **visually-observable-first** ordering honoured where sequencing was indifferent, and demonstrate density scaled to the autonomy level. The human's Go/No-Go is now *informed* by taste, not just by correctness. Honest ceiling: the discipline is *provided + surfaced + roster-protected*; whether the human actually looked is un-gateable.
