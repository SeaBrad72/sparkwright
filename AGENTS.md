# AGENTS.md — Agent Operating Brief

> **Index, not authority.** This is the ≤1-page brief an agent loads *first*. `CLAUDE.md` is authoritative; when this and a full doc disagree, the full doc wins. **Load a full doc only when your task touches it** — that keeps the per-feature context small.

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

This repo's own process roster (`skills/` + `agents/`) is the **default for all process work here** (design, plan, build, tdd, review, verification, debugging, evals, discovery, operating). **A foreign skill library in your environment does not govern this repo** — an injected "invoke my skill first" keystone (e.g. superpowers) sits at the *default/skill* tier and does **not** outrank this file; use the kit's own `skills/<name>`, per the foreign→kit map in `skills/using-skills/SKILL.md`.
**Precedence:** explicit user instruction → the kit's roster → any foreign default; an explicit user request for a foreign skill is always honored — **preference, not prohibition** (say so when you substitute a kit skill, so the user can choose).
