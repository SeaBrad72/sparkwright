# Cost / token governance — reference

How to bound agent and runtime spend without pretending the kit can mechanically stop it. Like the
containment reference (`containment.md`), this ships a **contract** and points at the **platform
control** that actually enforces — because a PreToolUse guard **cannot see token counts**, so an
in-guard token circuit-breaker is impossible. `conformance/cost-governance-ready.sh` verifies the
posture is **declared + attested**; it does **not** verify spend was capped.

## The two layers

1. **Contract (the kit ships this).** A per-run **budget** — a token/$ ceiling declared *before* the
   work starts — plus a **stop discipline**: as cumulative spend approaches the ceiling, the agent
   **stops and escalates** rather than silently blowing through. Declared per task in the
   **[Task Context Contract](../../templates/TASK-CONTEXT-CONTRACT-TEMPLATE.md)** `Budget` field, and
   per project in the RUNBOOK `Cost governance:` line.
2. **Platform cap (the real enforcement — kit references this).** The hard stop is **platform-owned**:
   - **Anthropic API usage limits** — set org/workspace/key **spend limits** in the console; a key that
     hits its cap stops minting completions regardless of what any agent intends.
   - **Harness budget setting** — where the runtime exposes a max-cost/max-tokens per session, set it.
   The kit cannot cap spend; the platform can — exactly as containment ships the read-only compose
   reference but the *host* enforces the mount.

## The monitor (already shipping)
`docs/operations/agentic-ops.md` already records `tokens.in` · `tokens.out` · `cost` per run (extracted
by `scripts/agent-trace.sh`; `scripts/agent-scorecard.sh` consumes those traces) — that is the
**measurement** the budget compares against. Cost
governance closes the loop: **measure (agent-scorecard) → compare to the declared budget → stop /
escalate**, with the platform cap as the backstop.

## How to attest (what the check reads)
Record one line in `RUNBOOK.md` (deploy/security section). The phrase + date are what
`cost-governance-ready.sh` keys on:

```
Cost governance: per-run budget + platform spend-cap <Anthropic usage limit | harness budget> — enforced: 2026-06-01
```
No metered external/LLM spend (a pure offline CLI/library)? Replace the line with `Cost governance:
N/A — <reason>`.

**Applicability — deploy surface OR metered-LLM/AI feature (as of 3.17.0).** `cost-governance-ready.sh` previously triggered only on a deploy surface (Dockerfile / workflow). A metered LLM CLI or library with no deploy surface silently escaped to N/A. The check now also triggers when the project has a metered-LLM/AI feature: an `evals/` directory, a filled AI System Card (`templates/AI-SYSTEM-CARD-TEMPLATE.md`), or `Agentic: yes` in the project `CLAUDE.md`. This closes the LLM-CLI-with-no-Dockerfile gap. The N/A escape remains valid for genuinely-unmetered projects (offline computation, no LLM calls).

## The ceiling (honest)
A green `cost-governance-ready.sh` proves the posture is **declared + attested**, **never** that spend
was actually capped — that is the platform layer's job, and a Manual row in any audit. The kit's
guard is blind to tokens; the budget is a **contract** (process discipline, like the high-risk
self-review in `review-lane.md`), and the **real stop is the platform spend limit**. Ties to
`DEVELOPMENT-STANDARDS.md` §2 (cost management / rate-limiting external + LLM spend) and the
`../enterprise/platform-safety-boundary.md` "enforcement is platform-owned" pattern.
