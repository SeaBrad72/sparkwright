---
name: continuous-discovery
description: Use BEFORE design shapes a solution — at the front of the loop, when a problem or outcome is assumed rather than validated, or a slice carries an untested assumption. The kit's own problem-space product-discovery craft (a kit-original; superpowers has no equivalent). The human↔AI discovery partner: structure the opportunity space, surface and test the riskiest assumption, keep work honest to outcomes over output — before any solution is designed.
---

# Continuous discovery — interrogate the problem before designing the solution

The kit's own problem-space discovery craft: take a felt need → a *validated* problem, a measurable outcome, and the riskiest assumption tested — before `design` shapes any solution. This is the **front of the loop** (Discover), the partner to `skills/design/SKILL.md`'s solution-space. Continuous discovery is Teresa Torres' practice made workable for a human↔AI pair; it is a kit-original (superpowers has no discovery skill — its `brainstorming` is solution-space, the kit's `design`).

> **Not to be confused with the discovery *keystone*.** `skills/using-skills/SKILL.md` is *skill*-discovery ("which skill applies?"). This skill is *product* discovery ("which problem, and is it the right one?"). Different axis entirely.

<!-- The frontmatter and the discipline markers below are conformance-load-bearing:
     conformance/orchestrator-loop-wired.sh greps this file for kit-distinctive markers
     (name: continuous-discovery, discovery partner, outcome over output,
     opportunity solution tree, riskiest assumption, small bet).
     Edits that drop or rename them can turn the skill-spine lock RED. -->

## When to use
At the **front of the loop**, before `design`: when the problem is taken for granted, when a slice's value rests on an assumption no one has tested, or when "what we'll build" is clear but "what outcome it changes, and for whom" is not. Every non-trivial slice deserves a discovery pass — a small one for a well-understood problem, a deliberate one when the problem is fuzzy or the bet is large.

## The discovery partner — not the decider
The **discovery partner** is the kit's framing of the human↔AI relationship here, and it is the load-bearing constraint of this whole skill: **the human is the PO.** The agent does *not* decide what to build or declare a problem worth solving. The agent makes continuous discovery *accessible and honest*: it structures the space, asks the sharp question, names the assumption everyone is gliding past, and designs the cheap test — then hands the judgment back to the human. A partner that quietly starts deciding has stopped being a partner; that is the failure mode this skill exists to prevent. There is no Product *seat* for the same reason — the human owns the decision; the Orchestrator merely *wears the Product hat* to invoke this craft.

## The flow (the proven spine)
1. **Anchor on the outcome, not the feature — `outcome over output`.** Before anything, ask what customer or business *outcome* this work would change, and how we'd measure it. Frame the work by the outcome it moves, never by the feature shipped. A slice with no outcome hypothesis is output theatre — surface that out loud. (This is the Definition-of-Ready "success metric / hypothesis" item, made a craft.)
2. **Map the `opportunity solution tree`.** Build the tree *with* the human: the outcome at the root → the **opportunities** beneath it (the problems, needs, and desires that, if addressed, move the outcome) → candidate solution ideas → the experiments that would test them. The point is to make the chosen opportunity *explicit and compared*, not the first idea that arrived. Breadth before depth.
3. **Surface and rank the `riskiest assumption`.** Every chosen opportunity and solution bets on assumptions — desirability (do they want it?), viability (does it work for the business?), feasibility (can we build it?), usability (can they use it?). Name them, then rank the **riskiest assumption**: the one that, if false, wastes the most work. That is what gets tested first — not the easiest thing to test.
4. **Design the `small bet`.** Design the cheapest experiment that would prove or kill the riskiest assumption *before* a slice is built — a `small bet`, not a big-bang study. Continuous, not one-shot: small, frequent tests on a cadence beat a single upfront discovery phase. Define in advance what result would change the decision; a test whose outcome changes nothing is theatre.
5. **Hand off to `design`.** Discovery's terminal state is a validated problem + a measurable outcome + the riskiest assumption tested — handed to `skills/design/SKILL.md` to shape the solution. This skill never starts a solution; designing is `design`'s job, building is the Engineer's.

## What this craft points at (it does not duplicate the infra)
- Capture the validated problem + outcome in `templates/FEATURE-REQUEST-TEMPLATE.md` (incl. its success-metric / hypothesis fields).
- The Definition-of-Ready "success metric / hypothesis" item is the outcome bar this craft feeds; `conformance/discovery-complete.sh` is the gate that checks the artifact exists.
- Prove any claim made during discovery with `skills/verification/SKILL.md` (evidence before assertions — a test result is a claim until you've seen it).
- Hand the validated problem to `skills/design/SKILL.md`; the loop continues plan → build → review from there.

## Honest ceiling
Discovery *quality* is un-gateable — there is no CI check that an opportunity tree is good or an assumption well-chosen, just as there is none for design quality. The structural proof is only that this craft is provided, kit-distinctive, and wired to the conductor; the honest enforcement of *outcome rigor* is the Definition-of-Ready success-metric item and `discovery-complete.sh`, which this craft feeds. Name that ceiling; never let a green check imply the discovery was actually good.

## Rationalizations to refuse
| Rationalization | Why it fails |
|---|---|
| "The problem is obvious, just build it." | Obvious problems hide the `riskiest assumption`. Name it and design a `small bet` before building — that is the cheap insurance. |
| "We agreed on the feature, discovery is done." | A feature is an output. Until you can state the `outcome over output` and how you'd measure it, discovery is not done. |
| "I'll run discovery and tell the human what to build." | You are the **discovery partner**, not the decider. The human is the PO; structure and surface, then hand back the judgment. |
| "Let's just pick the first solution." | An `opportunity solution tree` exists so the chosen opportunity is compared, not defaulted. Breadth before depth. |
| "We'll validate it after we ship." | Continuous discovery tests the riskiest assumption with a `small bet` *before* the build — post-hoc validation is the waste it prevents. |

## Terminal state
A validated problem, a measurable outcome (`outcome over output`), an explicit `opportunity solution tree`, and the `riskiest assumption` tested with a `small bet` — captured in the feature request and handed to `skills/design/SKILL.md`. The human made every call; the discovery partner kept it honest. This skill never starts implementation.
