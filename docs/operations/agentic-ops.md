# Agentic-Ops — Agent-Run Observability & Behavior

How to observe and govern an agent's *own work* — distinct from the kit's existing layers: the §13 guard *prevents* harm, §7 evals judge a *feature's* output, §2 tracks *spend*. Agentic-ops observes the **execution**: which tools an agent called, retries, latency, cost-per-task, gates hit/skipped, and the trace a person reads to judge whether behavior conforms over time.

## The model — a sensor a person reads

Agent-ops is a **sensor**: a stack/harness-neutral trace of how each agent worked. A person reads it when setting per-agent §13 autonomy tiers; the kit moves no tier. Three layers:

1. **Prevention stays fail-closed, unchanged** — harm (§13 guard), broken code (CI gates), unreviewed merges (branch protection) are already gated. Agent-ops adds **no new blocking gate**; re-gating these is redundant and gating *soft* signals trains gaming.
2. **The trace is pure observation** — every agent-run emits a structured record. Zero blocking; agents flow at machine speed. This is the flight recorder.
3. **Behavior is judged over a window, not run-gated** — a person reads an agent's traces over time and decides its autonomy tier (earned trust → longer leash → faster; drift → shorter leash → safer); it never blocks a single PR.

The payoff: the speed/safety tradeoff rests on evidence per agent, not a fixed heavy gate on everyone.

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
| `gates.hit[]` · `gates.skipped[]` · `tests.written` | The process-conformance signals a reader can judge |
| tool-step list: `tool.name` · `tool.outcome` (ok / error / **denied**) · `retries` | The execution trace; `denied` captures §13-guard blocks (a safety signal) |

### Additive-optional

| Field | Meaning |
|---|---|
| `session.id` | The conductor session that holds the work item's claim (`B2-SESSION-IDENTITY-LEDGER`). **Declared, never authenticated** — nothing reads it as an authorization input, and it is an input to no gate. `unknown` when not derivable. It is **not** the same as `run.id`, which is the transcript's own id: one session typically spans several runs. The reference emitter (`scripts/agent-trace.sh`) reads it from `<toplevel>/.kit-run/session.id`, the file `board-claim.sh claim` mints, and **never mints one itself**. |

No new required field and no new gate: an emitter that does not carry it is fully conformant.

### Recommended (not required)

Per-step `latency`, `decision`/rationale notes, `task.intent` / `acceptance_ref`, `model` id. Ship the core; let these earn their place per project.

> **The `unknown` sentinel.** An emitter that cannot derive a field records the literal `unknown` (or `null` for `parent.run.id`) rather than guessing — honesty over false precision. A reader treats `unknown` as missing, never as zero: an agent is never judged on absent data.

> **What the kit does not do.** It never actuates: it never mutates `.claude/`, the guard, or any tier store, and (conduct, not enforced) an agent never moves its own tier. It never pools or phones home any agent data; traces stay local unless you export or commit them.

## Emitters (tool/harness-neutral)

The schema is the **portable contract**; an emitter is a **thin per-harness adapter** that maps a harness's native record to it — the same "portable contract + adapter" split as the §13 guard.

- **Dev-time (reference adapter):** Claude Code writes a JSONL session transcript (tool calls, outcomes, token usage). **`scripts/agent-trace.sh`** derives an MP-3a-schema trace from it — transcript-native fields (timing, tokens, cost, the tool-step sequence with `ok`/`error`/`denied` outcomes) are solid; `gh`/`git`-correlated fields (`pr.ref`, `review.rounds`, `outcome`, gates/tests) are **best-effort, set to `unknown` when not derivable** (never fabricated). Run `scripts/agent-trace.sh --latest --stdout` for this repo's newest session, or pass a transcript path. A Gemini-CLI / Codex / Aider shop writes its own equivalent adapter against the same schema.
- **Runtime (product agent):** emit OpenTelemetry GenAI spans (or Langfuse) directly from the running agent; the spans already carry most required-core fields.

## Declaration & conformance

Record the posture in **RUNBOOK §8** (`Agent-ops:` — schema + emitter + sink) and the project `CLAUDE.md` config (alongside autonomy-tier defaults, PROCESS §73). Verified by `conformance/readiness.sh agentops-ready` (conditional on `Agentic: yes`); the readiness checklist is `conformance/agentic-ops-readiness.md`.

> **Honesty.** A green `readiness.sh agentops-ready` proves the posture is **declared** — not that traces emit, are complete, or that the agent behaved. Those are Manual rows. Necessary, not sufficient.

## Roadmap

- **MP-3a (this):** the trace contract + conformance trio + declaration wiring.
- **MP-3a.2 (done):** `scripts/agent-trace.sh` — the working Claude Code dev-time emitter (transcript→trace); turns the kit's own session transcripts into traces a person can read.

## Enterprise observability — OTLP export

This section documents an opt-in export path that forwards the kit's traces to any OTLP-compatible backend.

### The trace on real data (kit-internal)

`scripts/orchestrator-run.sh` — emits an OTel-shaped NDJSON trace representing an orchestrator run. **This is a labelled stand-in**: it produces the same schema that E3a (the real multi-agent orchestrator, a future slice) will emit when it runs. Use it now to exercise the downstream tools, such as the exporter below, against realistic data.

### The opt-in enterprise export path

The OTel NDJSON the kit emits can be forwarded to an external observability backend without re-instrumenting anything:

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

One emission feeds the export off a single seam — no duplicate instrumentation:

```
otel-trace.sh (emits NDJSON)
        └── otlp-export.sh → POST /v1/traces   (enterprise backend)
```

`orchestrator-run.sh` exercises this same graph with stand-in data today; E3a replaces it with real orchestrator spans at the same seam when it ships.

### Honest ceiling

The exporter produces and POSTs valid OTLP/HTTP JSON to the configured endpoint. What this kit does **not** assert:

- **Live vendor backend delivery** — the adopter supplies the endpoint URL and auth credentials; the kit cannot verify delivery against a vendor that it does not connect to. Confirm receipt in your backend's UI after a test run.
- **`orchestrator-run.sh` is a stand-in** — it emits realistic, schema-valid traces, but it is not a real orchestrator. E3a (the multi-agent orchestrator, a future slice) replaces it at the same seam.
- **This is agent-ops sensor tracing, not app-level request tracing** — these traces record *how agents worked* (tool calls, gates, cost, outcome). They are not distributed traces of end-user HTTP requests, which your application stack instruments separately.

### Design reference

Architecture and design-decision rationale lives in the kit's `docs/architecture/` design history (maintainer-internal; excluded from adopter exports).

---

## See also

- [`drift-self-check.md`](./drift-self-check.md) — the **agent-side complement** to this observation layer: agentic-ops *observes* the run (the trace, after the fact); the drift self-check is the agent **correcting itself within** the run, at a checkpoint, before any gate sees the drift.
