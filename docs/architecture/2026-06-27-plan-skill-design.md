# Skill-spine brick #2 — the kit's own `plan` skill (planning / writing-plans)

**Date:** 2026-06-27
**Epic / slice:** E3 → **skill-spine brick #2** (the kit's own planning skill). Second brick of the kit's fresh-authored skill spine, toward the [[self-hosting-commitment]] (replace external superpowers; E10 = build a slice using only the kit's own roster + skills).
**Status:** Design converged — **designed by dogfooding `skills/design/SKILL.md`** (the first real use of the kit's own design skill = self-hosting milestone), owner-ratified 2026-06-27. Ready for the implementation plan.
**Tracked here** (not `docs/superpowers/specs/`) because the skill spine + the E10 self-host test depend on the convention, and it must be resumable cold by a fresh instance.

**Reads-first for a cold resume:** [[self-hosting-commitment]] (the why), brick #1's design doc (`docs/architecture/2026-06-27-design-skill-design.md`, the convention this mirrors), the design skill itself (`skills/design/SKILL.md`), the shared verifier (`conformance/orchestrator-loop-wired.sh`), and the orchestrator the skill plugs into (`agents/orchestrator.agent.md` — its "Design (Architect hat)" section already name-drops the plan skill).

## 0. Why this slice (the decision trail)

Brick #1 shipped the kit's own `design` skill and established the **skill-invocation FLOOR** ("invoke by reading `skills/<name>/SKILL.md`"). Brick #2 is the next piece of the spine the kit's flow borrows from superpowers — `writing-plans` → a kit-authored `plan` skill. The handoff designated this as the first action of the session **and** required it be **designed by dogfooding the design skill** — the first real use of the kit's own skill, which both proves the design skill works and starts dropping the superpowers dependency in practice, not just in principle.

### Intent (unchanged from brick #1): FULL REPLACEMENT, not enhancement
Zero runtime dependency on superpowers; the kit's own process served entirely by kit-authored, harness-neutral skills. "Improves on superpowers" = the quality bar for the re-authoring (make it better, don't clone), NOT "enhance while still depending." Acceptance is **E10: build a real slice using only the kit's own roster + skills.**

## 1. What this slice is
Author the kit's **second own skill — `plan`** (a writing-plans-equivalent): turn an owner-approved design into an INVEST-sliced, TDD, build-ready implementation plan, invoked by the Orchestrator (Architect hat) in the Plan activity, BEFORE fan-out. **FLOOR-only** (invoke-by-read), mirroring brick #1.

## 2. Scope decision (owner-ratified 2026-06-27): FLOOR-only again
Brick #1 earmarked the formal `skills` adapter dimension + native per-harness bindings for "brick #2." On grounding against the design skill's own **right-weight / defer-build-ahead** discipline, that earmark was **re-decided**: two skills still work fine invoked-by-read (the FLOOR), and a formal adapter dimension for two read-only guidance files is build-ahead for a need that does not yet exist. **Decision: stay FLOOR-only.** The formal `skills` dimension + native bindings + lying-native proof are deferred again — to whenever the spine is richer or a genuine harness-native need is real. (This is itself the design skill earning its keep: the "is the provable thing meaningful / right-weight" lens overrode a stale plan.)

## 3. The skill's content — where the kit *improves on* superpowers (the real value)

`skills/plan/SKILL.md` is **not a copy** of superpowers' `writing-plans`. It keeps the proven spine (map the file structure → bite-sized TDD tasks [write failing test → run-fail → implement → run-pass → commit] → no-placeholders → self-review → execution handoff) and **bakes in the kit's own hard-won disciplines as first-class steps:**

- **INVEST slicing + the parallel-safety rule** — two tasks are safely parallel only when they have **disjoint file sets, no shared mutable state, and are each independently testable** (the orchestrator's fan-out rule). The plan marks which tasks may fan out.
- **Control-plane → AMBER `apply.py`.** When a task touches control-plane (guard, CI, conformance, claims, agents, skills, governance markers), it does NOT land as a silent agent commit — it is delivered as an `apply.py` a human reviews and applies. The plan identifies control-plane tasks and routes them to AMBER. (This is the kit's signature; superpowers has no equivalent.)
- **Conformance-lock-per-claim + non-vacuity.** Every new capability gets a conformance lock + a claim, wired into verify.sh / CI / drift-watch / doctor, each with a positive liveness anchor AND a load-bearing negative (a dead or always-pass mechanism must fail its `--selftest`). The plan includes the lock task.
- **Version-finishing folded into `apply.py`** ([[release-finishing-in-apply-py]]) — the VERSION bump + README badge + CHANGELOG stub live INSIDE the slice's apply.py so the human cannot skip them (the 3× premature-/skipped-bump fumble).
- **Dual-review handoff** — builder ≠ reviewer; hand the built slice to the Reviewer + Security-Reviewer, not a self-review (DEVELOPMENT-PROCESS §12). superpowers' handoff is self-review + subagent execution only.
- **Honest-ceiling per task** — name what each task's proof actually establishes vs. attests; never let a green check imply more than it proves.

This is "take inspiration, improve, make it inherent" made concrete: the plan skill encodes the exact planning judgment exercised across the E-series (AMBER apply.py, conformance non-vacuity, version-finishing, dual review).

## 4. Wiring (mirrors brick #1)
- **Orchestrator def:** the "Design (Architect hat)" section already references "the plan skill" in prose (`agents/orchestrator.agent.md:60`). Make it concrete — point at `skills/plan/SKILL.md` (small edit in both `agents/orchestrator.agent.md` and the native `.claude/agents/orchestrator.md`).
- **Guard:** none needed. `skills/*` is already in `is_control_plane_path` (`.claude/hooks/guard-core.sh:24`) AND both shell matchers (lines 82, 85), so `skills/plan/SKILL.md` is agent-immutable for free. (Confirms the control-plane-completeness discipline was satisfied by brick #1's glob — the next author should NOT have to re-touch the guard for an additional file under `skills/`.)

## 5. Conformance (right-weighted — no new gate, no new claim)
- **Extend the `skill-spine` claim** to "the kit ships its own `design` + `plan` skills (`skills/design/SKILL.md`, `skills/plan/SKILL.md`), referenced by the Orchestrator — bricks #1–#2 of the kit's own skill spine, toward self-hosting." (Right-weight: it is *the spine* — one claim, not one-per-brick.)
- **Extend `conformance/orchestrator-loop-wired.sh`:** add `check_plan_skill "$PLAN_SKILL_FILE" "$ORCH_DEF"` asserting `skills/plan/SKILL.md` exists + carries kit-distinctive markers + the orchestrator references `skills/plan/SKILL.md`. A generic `writing-plans` paraphrase lacking the kit's disciplines **fails** here. **Markers must be ASCII-safe** (the verifier uses `grep -qF`, like brick #1's plain-ASCII markers — avoid glyphs such as `≠`). Candidate set: `name: plan`, `## When to use`, `INVEST`, `AMBER` (the control-plane apply.py discipline), `conformance lock`, `dual review` (builder-is-not-reviewer). Exact final set locked at plan time.
- **New selftest case 6** (non-vacuity): a `plan` skill missing a kit-distinctive marker → exit 1. Keeps the existing 5 cases.
- Wired via the existing orchestrator-loop entries (verify/CI/drift-watch/doctor) — no new registration surface.

## 6. The two carried fold-ins (from the handoff)
- **(a) Control-plane-completeness discipline → `skills/design/SKILL.md`.** Add a discipline bullet: *"When a slice makes a path control-plane, lock it in BOTH guard matchers (`is_control_plane_path` AND the two shell-redirect regexes) AND add an agent-autonomy fixture per mutation form (Write/Edit, `>` redirect, `sed -i`)."* The two-matcher gap recurred **3×** (escalate.sh, M2-S5, skills/), each caught only by security review — encoding it in the *design* skill prompts the next author BEFORE the gap. (This re-touches the design skill; its greped markers are preserved, so the verifier stays green.)
- **(c) Cosmetics.** apply.py docstring notes the gitignored plan-path convention; an inline "this prose is conformance-load-bearing — edits here can fail `orchestrator-loop-wired.sh`" note near the greped markers in both SKILLs.

## 7. Honest ceiling & scope (named, not built)
- **Provided + structurally-proven; quality un-gateable** — correct for a skill, since a skill *is* authored guidance; encoding the kit's own planning disciplines is a real improvement over generic writing-plans.
- **Bootstrap** — superpowers' `writing-plans` is being used to author its kit-native replacement, and the kit's own `design` skill was used to design it. That is self-hosting in motion.
- **FLOOR-only-first (again)** — the formal `skills` adapter dimension + native bindings + lying-native proof remain deferred (§2).
- **Spine remaining** — build/TDD, review, worktrees, verification-before-completion, and the META discovery skill (`using-superpowers`-equivalent) follow, each its own proven slice. E10 is the eventual zero-superpowers acceptance.

## 8. Build approach
Control-plane slice (new `skills/plan/SKILL.md`; edits to `skills/design/SKILL.md` + `agents/orchestrator.agent.md` + `.claude/agents/orchestrator.md` + `conformance/orchestrator-loop-wired.sh` + `claims.tsv`/registry + `verify.sh` if needed + adopter-export carve; version finishing folded in) → **AMBER `apply.py`**, clone dry-run incl. shellcheck + `verify --require` → **dual review** (reviewer: is the plan-skill content genuinely the kit's planning disciplines + the conformance non-vacuous; security: low surface — read-only guidance, confirm `skills/` immutability still holds for the new file) → **light 5-lens meta-control panel #9** (A5 — expect a hard look at "is the plan skill genuinely improving on writing-plans or restating it") → version finishing folded in. Async; the human applies/merges (`commit → push → PR → merge → sh scripts/release-tag.sh`).

## 9. Convergence record (owner-ratified 2026-06-27)
Designed by dogfooding `skills/design/SKILL.md` (first real use — self-hosting milestone). FLOOR-only again (right-weight overrode the brick-#1 adapter-dimension earmark). The plan skill encodes the kit's own planning disciplines (AMBER apply.py · conformance-lock non-vacuity · version-finishing · INVEST/parallel-safety · dual-review · honest-ceiling) — the improvement on superpowers. Right-weighted conformance (extend the shared verifier + the one `skill-spine` claim, no new gate/claim). Two fold-ins: (a) control-plane-completeness discipline → design skill; (c) cosmetics. **Next: the implementation plan.** Chicken-and-egg note — the kit's own `plan` skill does not exist yet (it is what this slice builds), so the planning step itself is bootstrapped on superpowers `writing-plans` one last time. From the *next* slice on, the kit's own `plan` skill can author its own plans — that shift is the brick paying off.
