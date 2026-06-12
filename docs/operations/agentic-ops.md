# Agentic-Ops — Agent-Run Observability & Behavior

How to observe and govern an agent's *own work* — distinct from the kit's existing layers: the §13 guard *prevents* harm, §7 evals judge a *feature's* output, §2 tracks *spend*. Agentic-ops observes the **execution**: which tools an agent called, retries, latency, cost-per-task, gates hit/skipped, and (via MP-3b) whether behavior conforms over time.

## The model — sensor → actuator

Agent-ops is a **sensor** (a stack/harness-neutral trace of how each agent worked) feeding an **actuator** (per-agent §13 autonomy tiers). Three layers:

1. **Prevention stays fail-closed, unchanged** — harm (§13 guard), broken code (CI gates), unreviewed merges (branch protection) are already gated. Agent-ops adds **no new blocking gate**; re-gating these is redundant and gating *soft* signals trains gaming.
2. **The trace is pure observation** — every agent-run emits a structured record. Zero blocking; agents flow at machine speed. This is the flight recorder.
3. **Behavior is trend-scored, not run-gated** (MP-3b) — behavior is evaluated over a window, per agent; a crossed threshold **moves the agent's autonomy tier** (earned trust → longer leash → faster; drift → shorter leash → safer), it never blocks a single PR.

The payoff: the speed/safety tradeoff becomes data-driven and **self-adjusting per agent**, not a fixed heavy gate on everyone.

## Multi-agent principle (load-bearing)

- **Identity-keyed traces** — every run is keyed by `(agent.id, run.id, work_item.id, parent.run.id)`. Concurrent agents' traces never collide; `parent.run.id` builds the sub-agent spawn tree; `work_item.id` links the atomic backlog claim (§6).
- **Per-agent tiers, never global** — a shared tier would let one drifting agent rein in all of them. Per-agent tiers keep trustworthy agents fast while a drifting sibling alone is reined in.

Done this way, agent-ops **enables** safe parallelism rather than limiting it.

## The trace schema (the contract)

Anchored on **OpenTelemetry GenAI semantic conventions** (`gen_ai.*`) as a neutral subset — not vendor-locked. The contract is **fields + meaning, not transport**.

### Required core — every agent-run trace MUST carry

| Field | Meaning |
|---|---|
| `agent.id` · `run.id` · `work_item.id` · `parent.run.id` (nullable) | Multi-agent identity; spawn tree; atomic backlog-claim linkage (§6) |
| `start` · `end` · `tokens.in` · `tokens.out` · `cost` | Per-run timing + spend (makes §2 cost governance per-task) |
| `outcome` (completed / blocked / handoff / error) · `pr.ref` · `review.rounds` | Result + mergeable-PR signal |
| `gates.hit[]` · `gates.skipped[]` · `tests.written` | The process-conformance signals MP-3b scores |
| tool-step list: `tool.name` · `tool.outcome` (ok / error / **denied**) · `retries` | The execution trace; `denied` captures §13-guard blocks (a safety signal) |

### Recommended (not required)

Per-step `latency`, `decision`/rationale notes, `task.intent` / `acceptance_ref`, `model` id. Ship the core; let these earn their place per project.

> **The `unknown` sentinel.** An emitter that cannot derive a field records the literal `unknown` (or `null` for `parent.run.id`) rather than guessing — honesty over false precision. MP-3b treats `unknown` as missing, not as a value.

## Emitters (tool/harness-neutral)

The schema is the **portable contract**; an emitter is a **thin per-harness adapter** that maps a harness's native record to it — the same "portable contract + adapter" split as the §13 guard.

- **Dev-time (reference adapter):** Claude Code writes a JSONL session transcript (tool calls, outcomes, token usage). **`scripts/agent-trace.sh`** derives an MP-3a-schema trace from it — transcript-native fields (timing, tokens, cost, the tool-step sequence with `ok`/`error`/`denied` outcomes) are solid; `gh`/`git`-correlated fields (`pr.ref`, `review.rounds`, `outcome`, gates/tests) are **best-effort, set to `unknown` when not derivable** (never fabricated). Run `scripts/agent-trace.sh --latest --stdout` for this repo's newest session, or pass a transcript path. A Gemini-CLI / Codex / Aider shop writes its own equivalent adapter against the same schema.
- **Runtime (product agent):** emit OpenTelemetry GenAI spans (or Langfuse) directly from the running agent; the spans already carry most required-core fields.

## Declaration & conformance

Record the posture in **RUNBOOK §8** (`Agent-ops:` — schema + emitter + sink) and the project `CLAUDE.md` config (alongside autonomy-tier defaults, PROCESS §73). Verified by `conformance/agentops-ready.sh` (conditional on `Agentic: yes`); the readiness checklist is `conformance/agentic-ops-readiness.md`.

> **Honesty.** A green `agentops-ready.sh` proves the posture is **declared** — not that traces emit, are complete, or that the agent behaved. Those are Manual rows. Necessary, not sufficient.

## Behavior → autonomy-tier loop (MP-3b)

`scripts/agent-scorecard.sh` reads a window of traces, groups by `agent.id`, and computes
the trace-derivable behavior metrics — `denial_rate`, `error_blocked_rate`, `retry_rate`,
`review_rounds_mean` (the risk metrics). `gate_skip_rate`
is `unknown` in v1 (a non-run isn't observable from a transcript). It classifies each agent
against its **own trailing baseline** (older half vs recent half of the window):

- **regressed** — a risk metric jumped past the baseline by ≥ the margin → a **fail-safe
  auto-downgrade directive** (tighten the agent's tier; no ratification needed).
- **earned** — sustained improvement to clean → a **raise recommendation** routed to the
  **Security owner** to ratify a tier raise (§13).
- **steady** (incl. `< --min-runs`) — no directive.

**The kit emits directives; it never actuates** — it never mutates `.claude/`, the guard, or
any tier store; the adopter wires the directive into their enforcement plane. **`unknown` is
treated as missing, never zero** — an agent is never downgraded on absent data. Thresholds are
**relative to the agent's own history**, calibrated **locally** from the adopter's own traces;
the kit ships only sensitivity defaults and **never pools or phones home** any agent data.

## Roadmap

- **MP-3a (this):** the trace contract + conformance trio + declaration wiring.
- **MP-3a.2 (done):** `scripts/agent-trace.sh` — the working Claude Code dev-time emitter (transcript→trace); turns the kit's own session transcripts into the corpus that calibrates MP-3b.
- **MP-3b (done):** `scripts/agent-scorecard.sh` — the behavior scorecard tool; reads a trace dir, computes risk metrics per agent, classifies regressed/steady/earned, and emits the asymmetric tier directive.
