---
name: plan
description: Use AFTER a design is owner-approved and BEFORE any build — turning an approved design/spec into an INVEST-sliced, TDD, build-ready implementation plan. The kit's own planning skill (replaces, does not depend on, superpowers writing-plans). Produces bite-sized tasks an engineer with zero codebase context can execute.
---

# Plan — turn an approved design into a build-ready, honestly-scoped plan

The kit's own planning skill: take an owner-approved design → a task-by-task implementation plan a fresh engineer (human or agent) can execute without prior context. Keeps the proven writing-plans spine and bakes in the kit's planning disciplines. Replaces (does not depend on) superpowers `writing-plans`.

<!-- The frontmatter and the discipline headings below are conformance-load-bearing:
     conformance/orchestrator-loop-wired.sh greps this file for kit-distinctive markers
     (name: plan, ## When to use, INVEST, AMBER, Conformance lock, Dual review).
     Edits that drop or rename them can turn the skill-spine lock RED. -->

## When to use
After the design skill's terminal state (a committed, owner-approved spec) and before any implementation. Every slice gets a plan — a simple slice gets a short plan, but it is still written and self-reviewed. Assume the engineer is skilled but has zero context for this codebase and does not know its toolset.

## The flow (the proven spine)
1. **Scope check** — if the design spans multiple independent subsystems, split into one plan per subsystem; each must produce working, testable software on its own.
2. **Map the file structure first** — list every file created/modified and its single responsibility before writing tasks. Files that change together live together; prefer small, focused files.
3. **Decompose into bite-sized tasks** — each task is the smallest unit that carries its own test cycle and is worth a fresh reviewer's gate, ending in an independently testable deliverable. Fold setup/config/docs into the task whose deliverable needs them.
4. **Write each task as TDD steps** — write the failing test → run it (confirm it fails) → minimal implementation → run (confirm it passes) → commit. Each step is one 2-5 minute action.
5. **No placeholders** — every step carries the actual content (real code, exact paths, exact commands + expected output). "Add error handling" / "handle edge cases" / "write tests for the above" are plan failures.
6. **Self-review the plan** against the spec — spec coverage (point each requirement to a task), placeholder scan, type/name consistency; fix inline.
7. **Execution handoff** — hand to the build skill (a fresh agent per task) with the dual-review gate (below).

## The kit's planning disciplines (what makes this MORE than generic writing-plans — apply to EVERY plan)
- **INVEST slicing + the parallel-safety rule.** Slice into small, Independent, Negotiable, Valuable, Estimable, Small, Testable vertical increments. Two tasks are safely parallel ONLY when they have disjoint file sets, no shared mutable state, and are each independently testable — mark which tasks may fan out and which must serialize.
- **Control-plane → AMBER apply.py.** When a task touches control-plane (guard, CI, conformance, claims, agent/skill defs, governance markers), it does NOT land as a silent agent commit. Author it under `scratchpad/`, assemble an idempotent `apply.py`, prove it on a clone dry-run, and hand it to a human to apply. Identify control-plane tasks up front and route them to AMBER.
- **Conformance lock per claim + non-vacuity.** Every new capability ships a conformance lock + a claim, wired into verify.sh / CI / drift-watch / doctor. Every lock has a positive liveness anchor AND a load-bearing negative — a `--selftest` case that a dead or always-pass mechanism fails.
- **Version finishing folded into apply.py.** The VERSION bump + README badge + CHANGELOG entry live INSIDE the slice's apply.py so the release step cannot be skipped.
- **Dual review — the builder is never the sole reviewer.** The plan ends by handing the built slice to an independent Reviewer + (for any trust/security boundary) a Security-Reviewer. Never a self-review.
- **Honest ceiling per task.** State what each task's proof actually establishes versus attests; never let a green check imply more than it proves.

## Plan document header
Every plan starts with: **Goal** (one sentence), **Architecture** (2-3 sentences), **Tech Stack**, **Global Constraints** (project-wide requirements copied verbatim from the spec), and the **build model** (AMBER if any task is control-plane).

## Terminal state
A saved, self-reviewed plan (`docs/superpowers/plans/<date>-<name>.md`, or the project's plan location), handed to the build skill. This skill never starts implementation.
