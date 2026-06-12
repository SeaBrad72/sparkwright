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

## Emitters (tool/harness-neutral)

The schema is the **portable contract**; an emitter is a **thin per-harness adapter** that maps a harness's native record to it — the same "portable contract + adapter" split as the §13 guard.

- **Dev-time (reference adapter):** Claude Code writes a JSONL session transcript (tool calls, outcomes, token usage). A transcript→trace emitter derives the schema from it. The **working reference emitter is MP-3a.2**; until then, derive traces manually or document the mapping. A Gemini-CLI / Codex / Aider shop writes its own equivalent adapter against the same schema.
- **Runtime (product agent):** emit OpenTelemetry GenAI spans (or Langfuse) directly from the running agent; the spans already carry most required-core fields.

## Declaration & conformance

Record the posture in **RUNBOOK §8** (`Agent-ops:` — schema + emitter + sink) and the project `CLAUDE.md` config (alongside autonomy-tier defaults, PROCESS §73). Verified by `conformance/agentops-ready.sh` (conditional on `Agentic: yes`); the readiness checklist is `conformance/agentic-ops-readiness.md`.

> **Honesty.** A green `agentops-ready.sh` proves the posture is **declared** — not that traces emit, are complete, or that the agent behaved. Those are Manual rows. Necessary, not sufficient.

## Roadmap

- **MP-3a (this):** the trace contract + conformance trio + declaration wiring.
- **MP-3a.2:** the working Claude Code dev-time emitter (transcript→trace) — turns the kit's own session transcripts into the corpus that calibrates MP-3b.
- **MP-3b:** the behavior-conformance rubric (scored over a window, per agent) → autonomy-tier feedback; thresholds set against real MP-3a.2 traces.
