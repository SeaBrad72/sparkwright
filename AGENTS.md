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
Agents act only within granted capabilities; the runtime guard blocks destructive and control-plane actions. **Agents propose; humans ratify** — never self-merge, never edit the control plane (guard, CI, CODEOWNERS, settings) without a human applying it. The guard sees only **local** git, **not** a server-side `gh pr merge --admin` — so for a merge/ratification, prepare the green PR and **hand the human the merge command**; admin-merge only on an explicit "you merge it." Autonomy tiers + guard: **`DEVELOPMENT-PROCESS.md` §13**; solo-track ratification + the code-owner trap: **`docs/operations/review-lane.md`**.

## Working with the human
- **Operator fluency** (adapt to the human's level): `docs/operations/operator-fluency.md`

## Your stack
Concrete commands, libraries, and CI live in **`profiles/<stack>.md`** (chosen at Inception). New here? Start at **`START-HERE.md`**.
