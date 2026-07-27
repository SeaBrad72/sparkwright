# AGENTS.md — Agent Operating Brief

## 1. Entry contract — do this BEFORE any mutating action

**Five acts, every slice, before the first edit / commit / PR.** Process work here is governed by this repo's own roster (`skills/` + `agents/`) — a foreign skill library in your environment does not govern it; use the kit's own `skills/<name>`, per the foreign→kit map in `skills/using-skills/SKILL.md`.

1. **Derive the change class** — `sh conformance/promotion-readiness.sh --class --changed <listing>`, where `<listing>` is a file *containing* the changed paths, one per line. **Passing a path directly classifies that file's CONTENTS, not its path** — always pass a listing. That classifier is guard-core-only and under-detects adapter-declared paths, so run the union-aware check too: `sh conformance/agent-boundary.sh --changed <listing> --ratified 0` (rc 1 = an unratified control-plane path). `--state` is **not** a classifier — it emits a ratification-state label, and with no `--changed` it answers `NONE` for every path on earth. Class is derived, never self-asserted.
2. **Read the governing kit skill, and name it** — `skills/<name>/SKILL.md`; index + foreign→kit map at `skills/using-skills/SKILL.md`. Design before code; evidence before "done".
3. **Claim the backlog row** this work satisfies — in whichever backend this project declared (`docs/work-tracking/adapters.md` maps them; the kit's own is `BACKLOG.md`). No row, no build; board it first.
4. **Carry the Entry Declaration** as commit trailers — `Kit-Row`, `Kit-Stage`, `Kit-Class`, `Kit-Skill`, plus advisory `Kit-Intent`, `Kit-Ceremony`, `Kit-Stop`. **Declared now; gate-checked once `conformance/loop-state.sh` lands (B1)** — enforced / advisory / declared, stated honestly.
5. **State the ceremony budget in one line**, derived from the class, so the owner can veto it in a sentence instead of discovering it hours later.

> ⚠️ **The trailer block must be the LAST paragraph of the commit message, and contiguous.** A blank line before `Co-Authored-By:` silently drops every `Kit-*` field — git parses no trailers at all, while a grep-based check still passes the commit (measured).

## What this file is

> **Index, not authority.** This is the ≤1-page brief for every harness whose adapter declares `AGENTS.md` as its `contextFile` (see `adapters/*/adapter.json` — the manifests are the enumeration, so adding a harness never dates this line). §1 above is **byte-identical in every adapter's declared `contextFile`** — enforced byte-for-byte by `conformance/agents-brief.sh`, so whichever document your harness auto-loads, the entry contract you read is the same one. Nothing may sit above §1, between §1 and this heading, or behind an empty closing heading; that whole zone is the locked one. The **principles doc** is authoritative — `CLAUDE.md` in the kit, `ENGINEERING-PRINCIPLES.md` once a project has been incepted (Inception renames it and stamps a project charter over `CLAUDE.md`); when this brief and a full doc disagree, the full doc wins. **Load a full doc only when your task touches it** — that keeps the per-feature context small.

## The loop
Discover → Plan → Build → Review → Release → Operate, with retrospectives closing each pass. Full flow, stages, and cadence: **`DEVELOPMENT-PROCESS.md`**.

## The gates (where humans ratify)
- **Definition of Ready** — the entry gate before Build (acceptance criteria · INVEST slice · deps · success metric · conditional flags). **`CLAUDE.md`**.
- **Definition of Done** — the exit gate before an item is closed. **`CLAUDE.md`**.
- **7 required CI gates** — on every PR; the contract is the gate-ids, not a vendor. **`DEVELOPMENT-STANDARDS.md` §14**.
- Conditional gates (threat-model, eval, compliance, deployable, DR readiness) — **`DEVELOPMENT-PROCESS.md` §7**.

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
