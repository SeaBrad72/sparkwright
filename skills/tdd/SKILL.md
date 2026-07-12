---
name: tdd
description: Use when implementing any feature, bug fix, refactor, or behaviour change — BEFORE writing production code. The kit's own test-driven-development skill (replaces, does not depend on, superpowers test-driven-development). Red-green-refactor framed as the kit's non-vacuity law, plus coverage, testing-pyramid, and AI-eval disciplines.
---

# TDD — red-green-refactor as the kit's non-vacuity law, applied to code

The kit's own TDD skill: the Engineer's build craft. Write the test first, watch it fail, write minimal code to pass, refactor. Replaces (does not depend on) superpowers `test-driven-development`.

<!-- The frontmatter and discipline headings below are conformance-load-bearing:
     conformance/orchestrator-loop-wired.sh greps this file for kit-distinctive markers
     (name: tdd, ## When to use, Red-Green-Refactor, non-vacuity, critical path, evals).
     Edits that drop or rename them can turn the skill-spine lock RED. -->

## The Iron Law
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST. Wrote code before the test? Delete it and start fresh from the test — don't keep it as "reference", don't adapt it. If you didn't watch the test fail, you don't know it tests the right thing.

## When to use
Implementing any feature, bug fix, refactor, or behaviour change. Exceptions (ask the owner): throwaway prototypes, generated code, config files. "Skip TDD just this once" is a rationalization — stop.

## Red-Green-Refactor (the proven cycle)
1. **RED — write one failing test.** One behaviour, a clear name, real code (no mocks unless unavoidable). It demonstrates the desired API.
2. **Verify RED — watch it fail for the RIGHT reason.** Mandatory, never skipped. The test must FAIL (not error on a typo) and fail because the feature is missing. A test that passes immediately, or that cannot fail, proves nothing.
3. **GREEN — minimal code to pass.** Just enough; no extra features, no speculative options (YAGNI).
4. **Verify GREEN — watch it pass, output pristine.** This test passes, all others still pass, no warnings.
5. **REFACTOR — clean up while green.** Remove duplication, improve names, extract helpers; add no behaviour.

## The kit's testing disciplines (what makes this MORE than generic TDD — apply to EVERY cycle)
- **"Watch it fail" IS non-vacuity.** Verify-RED is the same law the kit applies to every conformance lock: a proof needs a positive liveness anchor AND a load-bearing negative — a dead or always-pass test must fail. TDD is that law at the unit-test level. If a test cannot fail, it is not a test.
- **Coverage floor.** 80%+ line coverage is the floor, not the ceiling; **100% on critical paths** (auth, payments, money/calculations). Coverage of the right code beats a high number over getters and setters.
- **Test at the right layer.** The testing pyramid — unit → integration → api/route → contract → e2e. Pick the layer that matches the behaviour under test. Mock at boundaries, never internals; test behaviour, not implementation, so tests survive refactors.
- **AI features → evals.** For AI behaviour, the eval IS the failing-test-first: write the eval, watch it fail, make it pass. Evals gate like tests and must not regress. (Deep eval methodology is the kit's eval-driven-dev guidance.)
- **Self-verify to the done-bar.** Before returning a slice, run its tests green with pristine output — the Engineer seat's done-bar (tests green + zero out-of-slice edits + a self-verify report). This skill is the craft; the seat def owns the done-bar.

## When stuck
Hard to test = hard to use — listen to the test and simplify the interface. Must mock everything = too coupled; use dependency injection. Don't know how to test = write the wished-for API or the assertion first, or ask the owner.

## Rationalizations & red flags — STOP and start over
These thoughts mean you are about to skip TDD. Each is a STOP, not a judgement call:

| Excuse | Reality |
|--------|---------|
| "I'll write the tests after" | Tests-after pass immediately and prove nothing — you never watched them catch the bug. |
| "Too simple to test" | Simple code breaks; the test costs 30 seconds. |
| "I already manually tested it" | Ad-hoc ≠ systematic — no record, can't re-run on the next change. |
| "Deleting working code is wasteful" | Sunk cost. The unverified code IS the debt — delete it and rebuild from the test. |
| "Keep it as reference while I write the test" | You will adapt it — that is testing after. Delete means delete. |
| "TDD is dogmatic; I'm being pragmatic" | TDD is the pragmatic path: faster than debugging in production. |

Red flags — any of these means delete the code and restart from a failing test: code written before its test · a test that passed on its first run · you cannot say why the test failed · "tests added later" · "it's the spirit, not the ritual."

## Terminal state
Production code that exists only because a test required it, all green with pristine output, handed back to the Engineer's done-bar and on to code review. Never fix a bug without a failing test that reproduces it first.
