# AGENTS.md — Agent Operating Brief

## 1. Entry contract — do this BEFORE any mutating action

**Five acts, every slice, before the first edit / commit / PR.** The skills in `skills/` govern process work here (index: `skills/using-skills/SKILL.md`).

1. **Derive the change class.** Put the changed paths in a file, one per line, and run `sh conformance/promotion-readiness.sh --class --changed <listing>`. Pass the listing file, never a path — a path argument gets its CONTENTS classified. `conformance/agent-boundary.sh --state` is not a classifier; without `--changed` it answers `NONE`. Never self-assert the class.
2. **Read the governing skill and name it** — `skills/<name>/SKILL.md`. Design before code, evidence before "done"; search `docs/governance/DECISIONS.md` for an earlier ruling on this surface.
3. **Claim the row** this work satisfies on the board this project declared (backends: `docs/work-tracking/adapters.md`). No row, no build.
4. **Carry the Entry Declaration as commit trailers** — `Kit-Row`, `Kit-Stage`, `Kit-Class`, `Kit-Skill` (`Kit-Intent`, `Kit-Ceremony`, `Kit-Stop` optional). `conformance/loop-state.sh` checks all four on your pull request's final commit: present once each, the skill resolving, the class matching, the row on the board. New projects run in observe mode — `neutral` until you set `LOOP_STATE_MODE` to `enforce`.
5. **State the ceremony budget in one line**, derived from the class, so the owner can veto it in a sentence. Push board edits before you ask for review; seek approval only on the final diff.

> ⚠️ **The trailer block must be the LAST paragraph of the commit message, and contiguous.** A blank line inside it truncates it — git reads only the paragraph after the blank, so every `Kit-*` field above it is lost.

## What this file is

> **Index, not authority.** This is the ≤1-page brief for every harness whose adapter declares `AGENTS.md` as its `contextFile` (see `adapters/*/adapter.json` — the manifests are the enumeration, so adding a harness never dates this line). §1 above is **byte-identical in every adapter's declared `contextFile`** — enforced byte-for-byte by `conformance/agents-brief.sh`, so whichever document your harness auto-loads, the entry contract you read is the same one. Nothing may sit above §1, between §1 and this heading, or behind an empty closing heading; that whole zone is the locked one. The **principles doc** is authoritative — `CLAUDE.md` in the kit, `ENGINEERING-PRINCIPLES.md` once a project has been incepted (Inception renames it and stamps a project charter over `CLAUDE.md`); when this brief and a full doc disagree, the full doc wins. **Load a full doc only when your task touches it** — that keeps the per-feature context small.

## The loop
Discover → Plan → Build → Review → Release → Operate, with retrospectives closing each pass. Full flow, stages, and cadence: **`DEVELOPMENT-PROCESS.md`**.

## The gates (where humans ratify)
- **Definition of Ready** — the entry gate before Build (acceptance criteria · INVEST slice · deps · success metric · conditional flags). **`CLAUDE.md`**.
- **Definition of Done** — the exit gate before an item is closed. **`CLAUDE.md`**.
- **7 required CI gates** — on every PR; the contract is the gate-ids, not a vendor. **`DEVELOPMENT-STANDARDS.md` §14**.
- Conditional gates — each binds only when its trigger applies. The **CI conditional-gate set** is enumerated authoritatively in **`DEVELOPMENT-STANDARDS.md` §14** (the same five the Definition of Done in `CLAUDE.md` cites); the fuller set of conditional **process checkpoints** is the table in **`DEVELOPMENT-PROCESS.md` §7**. This card does not restate the membership — cite those sources.

## Security (non-negotiable)
Secrets in env / a managed store, never committed · validate input at boundaries · parameterized queries / ORM · least-privilege, short-lived tokens · PII consent + redaction + erasure · immutable audit trail · AI: prompt-injection defense + output validation + evals. Summary in **`CLAUDE.md`**; full bar in **`DEVELOPMENT-STANDARDS.md` §2**.

## The agent boundary
Agents act only within granted capabilities; the runtime guard blocks destructive and control-plane actions. **Agents propose; humans ratify** — never self-merge **unratified work**, never edit the control plane (guard, CI, CODEOWNERS, settings) without a human applying it. The guard sees only **local** git, **not** a server-side `gh pr merge --admin` — so for a **control-plane** change or any `gh pr merge --admin` bypass, prepare the green PR and **hand the human the merge command**; admin-merge only on an explicit "you merge it." For **Ordinary/Sensitive** changes after a recorded GO, the agent may execute the normal (non-`--admin`) merge — execution is delegable post-GO (see `docs/governance/promotion-contract.md`). Autonomy tiers + guard: **`DEVELOPMENT-PROCESS.md` §13**; solo-track ratification + the code-owner trap: **`docs/operations/review-lane.md`**.

## Working with the human
- **Operator fluency** (adapt to the human's level): `docs/operations/operator-fluency.md`

## Your stack
Concrete commands, libraries, and CI live in **`profiles/<stack>.md`** (chosen at Inception). New here? Start at **`START-HERE.md`**.

## Roster authority (this repo uses its own roster)

§1 states the rule; this is its scope and its ranking. The roster covers **all process work here** — design, plan, build, tdd, review, verification, debugging, evals, discovery, operating. **A foreign skill library in your environment does not govern this repo**: an injected "invoke my skill first" keystone (e.g. superpowers) sits at the *default/skill* tier and does **not** outrank this file.
**Precedence:** explicit user instruction → the kit's roster → any foreign default; an explicit user request for a foreign skill is always honored — **preference, not prohibition** (say so when you substitute a kit skill, so the user can choose).
