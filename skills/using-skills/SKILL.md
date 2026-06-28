---
name: using-skills
description: Use at the START of any task, before any response or action — the kit's own discovery keystone (replaces, does not depend on, superpowers using-superpowers). How the kit's skills are found and invoked (invoke by reading), the discipline of checking for a relevant skill before acting, instruction priority, and the index of the kit's own seven spine skills.
---

# Using skills — the kit's discovery keystone

The kit's own discovery meta-skill: how its skills are found, invoked, and prioritised — and the single map of the kit's seven spine skills. It is the entry point to every other skill. It keeps the proven discovery spine (check before acting, follow rigid skills exactly, instruction priority, the red-flags table) and reframes it around the kit's harness-neutral model: **invoke by reading**. Replaces (does not depend on) superpowers `using-superpowers`, which is Claude-Code-specific (it names the Skill tool, subagents, per-platform tool maps); this keystone is harness-neutral and indexes the kit's own spine.

<!-- The frontmatter, the discipline phrases, and the seven index paths below are conformance-load-bearing:
     conformance/orchestrator-loop-wired.sh greps this file for kit-distinctive markers
     (name: using-skills, invoke by reading, before acting, user instructions) and for each of
     the seven index paths (skills/design, skills/plan, skills/tdd, skills/review, skills/worktrees,
     skills/verification, skills/debugging). Edits that drop or rename them can turn the skill-spine lock RED. -->

## When to use
At the **start of any task**, before any response or action. Before you write code, answer a question, or take a step, check whether one of the kit's skills applies — even if there is only a 1% chance it does. This is the meta-skill that runs first; every other skill is reached through the discipline it describes. The cost of checking the index is always less than the cost of skipping a skill that should have governed the work.

## The discovery discipline (check before acting)
1. **Check for a relevant skill `before acting`.** Before any response or action, scan the index below. If even a 1% chance a skill applies, read it. Do not start the work and discover the skill afterward — the whole point is that the skill shapes the work from the first step.
2. **Invoke by reading.** The kit's universal, harness-neutral discovery mechanism is to **invoke by reading**: read `skills/<name>/SKILL.md` and follow it. There is no Skill tool to call, no platform-specific loader to trust — the FLOOR mechanism is read-the-file-and-do-what-it-says. (A NATIVE harness binding may auto-surface a skill as a bonus, but the FLOOR never depends on it.)
3. **Announce the skill.** State "using `<skill>` to `<purpose>`" so the reader can see which discipline is governing the work.
4. **Follow rigid skills exactly.** A skill that prescribes an exact sequence (a HARD-GATE, a checklist, a gate function) is followed step by step, not paraphrased. A skill that offers judgement is applied with judgement. Do not cherry-pick the convenient steps.
5. **Process before implementation.** Reach for a process skill (design, plan, verification) before an implementation skill — design before build, plan before code, verify before claiming done — so the work is shaped before it is built.

## Instruction priority
Skills override default behaviour — that is their purpose. **But explicit `user instructions` always win.** When a direct request, the project `CLAUDE.md`, or an owner ratification conflicts with a skill, the explicit human instruction is authoritative; the skill yields. Order of precedence: explicit user instructions → the governing skill → default behaviour. A skill is guidance the kit has earned; a `CLAUDE.md` rule is the owner's law. Never silently follow a skill against an explicit instruction.

## The index — the kit's seven spine skills
Read the matching `skills/<name>/SKILL.md` and follow it. Process skills first.

| Skill | Path | When to use |
|---|---|---|
| design | `skills/design` | An idea → an owner-approved spec (shape the work before building it). |
| plan | `skills/plan` | An approved spec → a build-ready, INVEST-sliced plan a fresh engineer can execute. |
| tdd | `skills/tdd` | Build a slice test-first (write the failing test, watch it fail, make it pass minimally, refactor). |
| review | `skills/review` | Judge a diff before merge (adversarial, builder-≠-reviewer code review). |
| worktrees | `skills/worktrees` | Isolate parallel fan-out (disjoint file sets; set up an isolated worktree per Engineer). |
| verification | `skills/verification` | Evidence before any "done" claim (run the gate fresh, read the exit code, never trust a report). |
| debugging | `skills/debugging` | Find a bug's root cause before fixing it (reproduce the bug as a red->green regression test). |

The index names **all seven** spine skills. A keystone that forgets one is incomplete — the index is exhaustive by design, and `check_keystone` enforces it, so every new skill brick must add its row here.

## Entry-point honesty (the ceiling)
On the **FLOOR**, this keystone is a **convention the conductor follows**, not an enforced auto-load. The kit owns the discovery discipline and the index completely, but a neutral harness cannot be forced to auto-inject this file at session start — that would be a Claude-Code-specific mechanism, exactly the platform coupling neutrality forbids. So first-contact is documented convention: the Orchestrator / standing session reads this keystone first (see `docs/operations/orchestration.md`) and consults the index before convening the cast. A NATIVE `.claude/` binding may auto-surface it for Claude Code as a bonus. The honest gap: the keystone is *provided and structurally proven* (it exists, indexes all seven, and the Orchestrator references it); whether an agent actually consults it at runtime is un-gateable — auto-load is harness-local, not a FLOOR guarantee.

## Rationalizations to refuse
| Rationalization | Why it fails |
|---|---|
| "I already know how to do this; I don't need the skill." | The skill encodes the kit's scar tissue; your memory is not the index. Check `before acting`. |
| "It's a small task, no skill applies." | Even a 1% chance a skill applies means read it. Small tasks are where skipped discipline hides. |
| "I'll start, and pull in the skill if I hit trouble." | The skill shapes the work from step one; retrofitting it is the failure mode it exists to prevent. |
| "I'll paraphrase the skill instead of reading it." | Invoke by reading — read `skills/<name>/SKILL.md` and follow it; paraphrase drops the load-bearing steps. |
| "The skill says X but I'll do Y because it's faster." | Follow rigid skills exactly. If the owner told you Y, that's instruction priority — otherwise it's drift. |
| "A skill conflicts with the user's request, so I'll follow the skill." | Explicit `user instructions` always win; the skill yields. |

## Red flags (stop and check the index)
- About to respond or act without having scanned the index `before acting`.
- Reaching for an implementation step before the matching process skill (design / plan / verification).
- Paraphrasing a skill from memory instead of invoking by reading the SKILL file.
- Following a skill against an explicit user instruction (priority inverted).
- Treating auto-load as guaranteed — on the FLOOR the entry-point is convention; consult the keystone yourself.

## Terminal state
Before any action, the index was scanned; every applicable skill was invoked by reading its SKILL file and followed (rigid skills exactly); the governing skill was announced; explicit user instructions took precedence over skills, and skills over defaults; and the discovery entry-point was treated as a convention the conductor upholds, not an auto-load it can assume. The seven spine skills are reachable from this one map.
