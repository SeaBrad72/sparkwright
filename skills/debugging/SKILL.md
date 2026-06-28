---
name: debugging
description: Use when encountering ANY bug, test failure, unexpected behaviour, or build/integration failure — BEFORE proposing a fix. The kit's own root-cause-first debugging skill (replaces, does not depend on, superpowers systematic-debugging). Reframes debugging so a bug always becomes a red→green regression test, chained to the kit's own tdd + verification skills.
---

# Debugging — find the root cause first, then make the bug a failing test

The kit's own debugging skill: the craft of finding a bug's *root cause* before touching a fix, and turning that bug into a regression test that goes red before the fix and green after. Keeps the proven systematic-debugging spine (the Iron Law, reproduce, controlled experiments) and bakes in the kit's connective tissue — debugging chains into the kit's own `skills/tdd/SKILL.md` and `skills/verification/SKILL.md`, so a fix isn't "done" until a test that reproduces the bug flips red→green with evidence. Replaces (does not depend on) superpowers `systematic-debugging`, which is harness-specific (it names the Skill tool + superpowers sibling skills); this skill is harness-neutral and invokes the kit's own spine by reading.

<!-- The frontmatter and the discipline phrases below are conformance-load-bearing:
     conformance/orchestrator-loop-wired.sh greps this file for kit-distinctive markers
     (name: debugging, root cause, reproduce, regression test, one hypothesis).
     Edits that drop or rename them can turn the skill-spine lock RED. -->

## When to use
ANY bug, test failure, unexpected behaviour, or build/integration failure — invoke this BEFORE proposing or writing a fix. Use it ESPECIALLY when it is tempting NOT to: under time pressure, when "just one quick fix" looks obvious, or after a previous fix did not work. A simple-looking bug has a root cause too; the process is fast for simple bugs and the only thing that works for hard ones.

## The Iron Law — no fix without root cause first
```
NO FIX WITHOUT ROOT-CAUSE INVESTIGATION FIRST
```
A symptom patch is failure. Before you change a single line:
- **Read the actual error / stack trace completely.** The message often contains the answer — line numbers, file paths, error codes. Do not skim past it or paraphrase it from memory; read the real output.
- **Find the true cause, not the surface.** State *what* is wrong and *why* it happens. "Seeing the symptom" is not "understanding the `root cause`." If you cannot explain why the bug occurs, you are not ready to fix it.
- **Check recent changes.** What changed that could cause this — `git diff`, recent commits, new dependencies, config/env differences? Trace a bad value backward to where it originates and fix it at the source, not where it surfaces.

If you have not found the root cause, you cannot propose a fix.

## Reproduce it — reliably, before theorising
**`reproduce`** the bug on demand: what are the exact steps, does it happen every time, what inputs/state trigger it? A bug you cannot trigger is a bug you cannot prove fixed.
- If it is **not reproducible**, gather more data — add logging, instrument the component boundaries in a multi-part system, widen the inputs — **don't guess**. Guessing at an intermittent bug produces a fix you cannot verify.
- A reliable reproduction is the raw material for the next step: it becomes the failing test.

## ★ The bug becomes a failing test FIRST (the distinctive kit framing)
This is where the kit's debugging differs from a generic checklist. **Reproduce the bug as a `regression test` that goes RED before the fix and GREEN after.** The fix is not "done" until that test flips red→green — this is the kit's **non-vacuity law applied to bug-fixing**: a fix with no failing test that reproduces the bug proves nothing.

The discipline chains across the spine:
1. **Write the failing test** following the kit's own `skills/tdd/SKILL.md` — capture the bug as the smallest test that fails *for the right reason*. Watch it go RED first; a test that was never red proves nothing (the tdd non-vacuity rule).
2. **Find + fix the root cause** (the Iron Law above) — the minimal change that makes the red test pass.
3. **Prove it GREEN with evidence** following the kit's own `skills/verification/SKILL.md` — run the test fresh in this turn, read the actual exit code and failure count, and make no "fixed" claim without that evidence (evidence before claims; no confabulation).

The regression test stays in the suite forever, so this exact bug can never silently return.

## Controlled experiments — one hypothesis at a time
Debug like a scientist, not a slot machine.
- **Form a single, specific hypothesis:** "I think X is the root cause because Y." Write it down. Gather evidence *before* theorising, not after.
- **Test `one hypothesis` at a time — change one thing.** Make the smallest possible change to test it. Never bundle several fixes or a "while I'm here" refactor — if it works you won't know which change did it, and you may mask a second bug.
- **Verify, then continue.** Worked? Move to the fix + regression test. Didn't work? Form a NEW hypothesis from what you learned — don't stack another change on top.
- **When you don't know, say so.** "I don't understand X" beats pretending. Research or ask rather than guessing.

## Bounded, then escalate — don't thrash
Debugging has a budget. After repeated failed hypotheses, **step back instead of flailing**:
- Count your attempts. If a fix doesn't work after 2–3 honest hypotheses, **STOP** — do not attempt fix #4 on instinct.
- Repeated failures that each reveal a new problem in a different place are a signal the *architecture* is wrong, not the latest line. Raise it; question the pattern.
- This ties to the kit's runaway-guard + escalation discipline: **raise, don't barrel through.** Surface the wall to a human with what you tried and what you learned — escalation is the correct move, not a failure.

## Red flags — STOP and return to root-cause
| If you catch yourself thinking… | Reality |
|---|---|
| "Quick fix now, investigate later" | First fix sets the pattern. Find the root cause first. |
| "Just try changing X and see" | That is guessing. Form one hypothesis, gather evidence. |
| "I'll skip the test and verify by hand" | An untested fix doesn't stick — make it a red→green `regression test`. |
| "Change several things, then run tests" | You can't tell what worked. Change `one hypothesis` at a time. |
| "It's probably X, let me fix that" | Seeing a symptom ≠ understanding the `root cause`. |
| "One more fix attempt" (after 2+ failures) | 3+ failures = architecture problem. Stop and escalate. |
| "It's intermittent, I'll just retry-loop it" | If you can't `reproduce` it, gather data — don't paper over it. |

## Honest ceiling
This skill makes the *discipline* explicit and wires it to the kit's tdd + verification skills; it cannot make an agent actually investigate. The conformance check proves the skill exists, is kit-distinctive, and the Engineer references it — it cannot prove root-cause rigour at runtime. The red→green regression test is the one mechanical guarantee: no test that reproduces the bug, no "fixed."

## Terminal state
A fix is done when: the root cause is understood and stated; a regression test reproduces the bug and was seen RED, then GREEN with fresh evidence (`skills/verification/SKILL.md`); exactly one root-cause change was made; and no other test regressed. Otherwise it is not done.
