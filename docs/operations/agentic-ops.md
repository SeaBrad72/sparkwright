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

## Enterprise observability — OTLP export

This section documents two complementary paths that share a single trace emission: the kit-internal scorecard loop, and an opt-in export path that forwards traces to any OTLP-compatible backend.

### The sensor loop on real data (kit-internal)

The operate-loop feedback path:

1. `scripts/orchestrator-run.sh` — emits an OTel-shaped NDJSON trace representing an orchestrator run. **This is a labelled stand-in**: it produces the same schema that E3a (the real multi-agent orchestrator, a future slice) will emit when it runs. Use it now to exercise the downstream tools against realistic data.
2. `scripts/otel-to-scorecard.sh` — adapter that reads the OTel NDJSON and maps it to the MP-3a trace schema the scorecard expects. This is the seam between the OTel shape and the kit-internal format.
3. `scripts/agent-scorecard.sh` — the behavior scorecard tool (unchanged). Reads the adapted trace directory, computes risk metrics per agent, classifies regressed/steady/earned, and emits the tier directive. No modification needed; the adapter keeps this tool harness-neutral.

The result: orchestrator traces flow into the same tier-advice loop as Claude Code dev-time traces — one scoring tool, multiple emitter shapes, the adapter absorbs the difference.

### The opt-in enterprise export path

The same OTel NDJSON that drives the scorecard can be forwarded to an external observability backend without re-instrumenting anything:

1. `scripts/otel-trace.sh` — emits the OTel-shaped NDJSON trace (the same format as `orchestrator-run.sh`, usable directly or as the source when integrating a real harness).
2. `scripts/otlp-export.sh` — reads the NDJSON and POSTs it to the configured OTLP HTTP endpoint. The exporter appends `/v1/traces` to `OTEL_EXPORTER_OTLP_ENDPOINT`.

**Concrete backends the export path targets:**

| Backend | Notes |
|---|---|
| **Datadog** | set endpoint to your Datadog OTLP ingest URL; use `OTEL_EXPORTER_OTLP_HEADERS` for the `DD-API-KEY` header |
| **Honeycomb** | set endpoint to `https://api.honeycomb.io`; pass `x-honeycomb-team` in headers |
| **Grafana Tempo** | set endpoint to your Tempo OTLP HTTP receiver; use bearer auth in headers |
| **Jaeger** | set endpoint to your Jaeger OTLP receiver (default port 4318) |
| **OpenTelemetry Collector** | the recommended hub: the Collector receives, enriches, and fans out to multiple backends from one endpoint |

### Standard environment variables

| Variable | Purpose |
|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Base URL of the collector or backend. The exporter appends `/v1/traces`. Example: `https://api.honeycomb.io` |
| `OTEL_EXPORTER_OTLP_HEADERS` | Vendor auth and routing headers in `key=value,key=value` form. Consumed by the exporter; never logged. |

These are the standard OpenTelemetry environment variables; `scripts/otlp-export.sh` reads them directly. See the [OpenTelemetry environment variable specification](https://opentelemetry.io/docs/specs/otel/protocol/exporter/) for details.

### The pluggable-sink design

One emission feeds both consumers off a single seam — no duplicate instrumentation:

```
otel-trace.sh (emits NDJSON)
        │
        ├── otel-to-scorecard.sh → agent-scorecard.sh  (kit-internal tier loop)
        └── otlp-export.sh → POST /v1/traces             (enterprise backend)
```

`orchestrator-run.sh` exercises this same graph with stand-in data today; E3a replaces it with real orchestrator spans at the same seam when it ships.

### Honest ceiling

The exporter produces and POSTs valid OTLP/HTTP JSON to the configured endpoint. What this kit does **not** assert:

- **Live vendor backend delivery** — the adopter supplies the endpoint URL and auth credentials; the kit cannot verify delivery against a vendor that it does not connect to. Confirm receipt in your backend's UI after a test run.
- **`orchestrator-run.sh` is a stand-in** — it emits realistic, schema-valid traces, but it is not a real orchestrator. E3a (the multi-agent orchestrator, a future slice) replaces it at the same seam.
- **This is agent-ops sensor tracing, not app-level request tracing** — these traces record *how agents worked* (tool calls, gates, cost, outcome). They are not distributed traces of end-user HTTP requests, which your application stack instruments separately.

### Design reference

Architecture and design-decision rationale: [`docs/architecture/2026-06-26-e5-thin-otel-sensor-design.md`](../architecture/2026-06-26-e5-thin-otel-sensor-design.md)

---

## See also

- [`drift-self-check.md`](./drift-self-check.md) — the **agent-side complement** to this observation layer: agentic-ops *observes* the run (trace + scorecard, after the fact); the drift self-check is the agent **correcting itself within** the run, at a checkpoint, before any gate sees the drift.
- **`sparkwright tier-advice`** — renders the **decision view** over this
  layer's emitted directives: which agents have a pending autonomy-tier recommendation and the
  human-ratified apply path for each (auto-downgrade is fail-safe; a raise routes to the Security
  owner, §13). It composes the scorecard + DORA (delivery-health context only); it emits, never actuates.
