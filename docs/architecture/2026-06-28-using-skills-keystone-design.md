# Skill-spine brick #7 (the KEYSTONE) — the kit's own `using-skills` discovery skill

**Date:** 2026-06-28
**Epic / slice:** E3 → **skill-spine brick #7, the discovery KEYSTONE** (the kit's own `using-superpowers`-equivalent). The final brick of the kit's fresh-authored skill spine — after it, the spine is complete and **E10 zero-superpowers acceptance** is unblocked. See [[self-hosting-commitment]].
**Status:** Design converged — **designed by dogfooding `skills/design/SKILL.md`** (6th self-host use), owner-ratified 2026-06-28 (scope = discipline+index; index name-all-6 coupling; single-seat Orchestrator). Ready for the implementation plan (which dogfoods `skills/plan/SKILL.md`).
**Tracked here** because the skill spine + the E10 self-host test depend on the convention, and it must be resumable cold.

**Reads-first for a cold resume:** [[self-hosting-commitment]] (the keystone is the zero-dependency seed), brick #6's design doc (`docs/architecture/2026-06-28-verification-skill-design.md`, the convention this mirrors), the 6 shipped skills (`skills/{design,plan,tdd,review,worktrees,verification}/SKILL.md`), the shared verifier (`conformance/orchestrator-loop-wired.sh`), and the seat this wires (`agents/orchestrator.agent.md`). The source it replaces is superpowers `using-superpowers` (the discovery meta-skill).

## 0. Why this slice (the decision trail)

Bricks #1–6 fresh-authored the kit's content skills (design, plan, tdd, review, worktrees, verification). But [[self-hosting-commitment]] is explicit: *"replacing the content skills alone is NOT zero-dependency; the discovery meta-skill must be kit-native too."* Today the kit's skill discovery is **hardcoded per seat** (each agent def directly names the skills it uses) — there is no kit-native equivalent of superpowers' `using-superpowers` (the "how to find and use skills, check before acting" meta-skill that the harness injects at session start). Brick #7 is that keystone. After it, no part of the kit's own loop depends on superpowers, and E10 (build a slice using only the kit's roster + skills) can run.

### Scope (owner-ratified 2026-06-28): discipline + index (full using-superpowers equivalent)
The keystone is BOTH halves: (a) the **discovery discipline** (check `skills/` before acting; invoke-by-read; follow rigid skills exactly; skills override defaults but explicit user instructions win) AND (b) the **index** — the map of the 6 spine skills with when-to-use. Discipline-only was rejected (leaves no single map; loses the index teeth); index-only was rejected (documentation, not the discovery meta-skill — under-delivers the keystone's whole point).

### Wiring (owner-ratified): single-seat Orchestrator
The Orchestrator is the standing session that "convenes the right cast per phase" — the natural discovery driver and entry seat. Discovery is the conductor's entry, NOT two distinct gates (contrast brick #6's dual-seat). So single-seat: the Orchestrator def references the keystone; the verifier asserts that.

### Index coupling (owner-ratified): the keystone names all 6 spine skills
The verifier requires the keystone to name every spine skill — a keystone that forgets one fails. This is a deliberate coupling: the index must be exhaustive. Because this is the LAST brick, the spine is complete at 6 content skills + the keystone, so the index is stable.

### Intent (unchanged): FULL REPLACEMENT, not enhancement
Zero runtime dependency on superpowers; acceptance = E10.

## 1. What this slice is
Author the kit's **seventh own skill — `using-skills`**, the discovery KEYSTONE: the meta-skill that establishes how the kit's skills are found and invoked, and indexes the 6 spine skills. **FLOOR-only** (invoke-by-read).

### Name: `using-skills`
Parallels superpowers `using-superpowers`; clearly the meta-entry. (`skills/using-skills/SKILL.md`.)

## 2. The skill's content — where the kit *improves on* superpowers (the real value)

`skills/using-skills/SKILL.md` is **not a copy** of superpowers' `using-superpowers` (which is Claude-Code-specific — it names the Skill tool, subagents, per-platform tool maps). It keeps the proven spine — check for a relevant skill BEFORE any response/action (even a 1% chance); announce "using [skill] to [purpose]"; rigid skills are followed exactly; process-skills before implementation-skills; the red-flags/rationalization table — and bakes in the kit's own model:

- **Invoke-by-read FLOOR.** The kit's universal discovery mechanism is *read `skills/<name>/SKILL.md` and follow it* — harness-neutral, no Skill-tool dependency. (This is the FLOOR established by brick #1, now made the explicit discipline.)
- **The index of the kit's own 6 skills** with when-to-use: `design` (idea → owner-approved spec), `plan` (spec → build-ready plan), `tdd` (build a slice test-first), `review` (judge a diff before merge), `worktrees` (isolate parallel fan-out), `verification` (evidence before any "done" claim). Names every spine skill — the distinctive *index* tooth a generic paraphrase cannot have.
- **Instruction priority.** Skills override default behaviour, but **explicit user instructions (CLAUDE.md / direct requests) always win** — kept verbatim from the proven spine because it is load-bearing and correct.
- **Process-before-implementation ordering** — design before build, verify before claiming done — pointing into the kit's own spine.

This is "take inspiration, improve, make it inherent": discovery reframed around the kit's invoke-by-read FLOOR + an index of the kit's own spine, harness-neutral, not the Claude-Code-specific Skill-tool mechanics.

## 3. Wiring (single-seat — Orchestrator)
- **Orchestrator def (the standing session / discovery driver):** add a "start here" reference — when convening the cast per phase, consult the kit's own discovery keystone `skills/using-skills/SKILL.md` to find the right skill. Edit `agents/orchestrator.agent.md` (FLOOR) + `.claude/agents/orchestrator.md` (native). The verifier asserts the Orchestrator def references the keystone.
- **Guard:** none — `skills/*` already in `is_control_plane_path` + both shell-redirect regexes; `skills/using-skills/SKILL.md` is agent-immutable for free (confirm-don't-add).

## 4. Conformance (right-weighted — no new gate, no new claim)
- **Extend the `skill-spine` claim** text → "… + the `using-skills` discovery keystone (`skills/using-skills/SKILL.md`) indexing the 6 spine skills, referenced by the orchestrator (discovery) … bricks **#1–7** — the kit's own skill spine fully replacing superpowers (content + discovery)".
- **Extend `conformance/orchestrator-loop-wired.sh`:** add `check_keystone "$KEYSTONE_FILE" "$ORCH_DEF"` asserting the skill exists + **names all 6 spine skills** (`grep -qF` each of `skills/design`, `skills/plan`, `skills/tdd`, `skills/review`, `skills/worktrees`, `skills/verification`) + discipline markers (`name: using-skills`, `invoke by reading`, `before acting`, `user instructions`) + the Orchestrator def references `skills/using-skills/SKILL.md`. A generic `using-superpowers` paraphrase fails (names none of the kit's 6 skills; no invoke-by-read).
- **Non-vacuity — 2 new cases:** **case 16** (index teeth: emit a keystone MISSING one spine-skill name, e.g. drop `skills/verification` → exit 1) + **case 17** (Orchestrator omits the keystone reference → exit 1). Cases 1–15 fixtures each gain a conformant keystone naming all 6 + the Orchestrator ref.
- **Extend `docs/operations/orchestration.md`** — add the keystone + the **entry-point convention** note (the Orchestrator/session consults the keystone first; on the FLOOR this is convention, NATIVE can auto-surface).

## 5. Honest ceiling & scope (named, not built — the keystone's crux)
- **Content fully kit-owned; entry-point is the ceiling.** The kit owns the discovery discipline + index completely. But on a neutral FLOOR the kit **cannot force a harness to auto-load** the keystone (that would be Claude-Code-specific, exactly what superpowers does and what neutrality forbids). So first-contact is a **documented convention** — the Orchestrator/standing session reads it first (`orchestration.md` states it) — NOT an enforced auto-injection. The NATIVE `.claude/` binding can auto-surface it for Claude Code as a bonus. This is the honest gap: provided + structurally-proven (exists, indexes the spine, the conductor references it); auto-load is harness-local, not a FLOOR guarantee.
- **Provided + structurally-proven; runtime obedience un-gateable** — correct for a skill (the check proves the keystone exists, indexes all 6, and the Orchestrator references it; it cannot prove an agent actually consults it at runtime).
- **Index coupling is intentional** — exhaustive by design; stable because the spine is complete at brick #7.
- **Bootstrap honesty** — the kit's design+plan skills produced this slice (6th dogfood); the keystone is the last piece that lets E10 run with zero superpowers.
- **Spine remaining after #7: NONE.** This completes the spine. Next is **E10 — build a real slice using only the kit's own roster + skills, zero superpowers** (the acceptance test).

## 6. Build approach
Control-plane slice (new `skills/using-skills/SKILL.md`; orchestrator defs ×2 — FLOOR + native; `conformance/orchestrator-loop-wired.sh` + `conformance/claims.tsv` + `docs/operations/orchestration.md`; version finishing **3.62.0 → 3.63.0**) → **AMBER `apply.py`**, clone dry-run incl. shellcheck + `verify --require` → **dual review** (reviewer: is the keystone genuinely the kit's discovery craft + the index non-vacuous incl. cases 16/17; security: low surface — read-only guidance, confirm `skills/` immutability holds) → **light 5-lens meta-control panel #14** (A5) → **fold the governance close INTO the feature PR** (standing process). Subagent-driven build; the human applies/merges/release-tags (run `release-tag.sh` only after `git checkout main && git pull`).

## 7. Convergence record (owner-ratified 2026-06-28)
Designed by dogfooding `skills/design/SKILL.md` (6th self-host use). The discovery KEYSTONE = the kit's own `using-superpowers`-equivalent: scope = discipline + index (full equivalent); single-seat Orchestrator (discovery is the conductor's entry, not dual gates); the index names all 6 spine skills (exhaustive-by-design coupling, stable because final). The skill reframes discovery around the kit's **invoke-by-read FLOOR + an index of the kit's own spine**, harness-neutral, atop the proven check-before-acting + instruction-priority spine. Honest ceiling named: content kit-owned, **entry-point is a documented convention** (auto-load is harness-local, not a FLOOR guarantee). Right-weighted conformance (extend the shared verifier + the one `skill-spine` claim; +case 16 index-teeth + case 17 reference-teeth). FLOOR-only. **This completes the spine — next is E10 zero-superpowers acceptance.** Next step: the implementation plan, dogfooding `skills/plan/SKILL.md`.
