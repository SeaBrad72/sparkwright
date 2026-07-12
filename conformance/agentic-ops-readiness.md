# Conformance Check — Agent-Ops Readiness

Proves an **agentic** project has its **agent-run observability** discipline in place: a trace schema is adopted, traces are emitted to a sink, and (for the MP-3b behavior loop, when present) the process-conformance window + autonomy-tier linkage are recorded. **Checklist-type**, run at the **Review / agent-ops readiness gate** (`DEVELOPMENT-PROCESS.md` §7/§13) and as **recurring maintenance** (§15). **Conditional:** non-agentic projects mark the whole check **N/A — no agent runs to trace**. Implements the trace contract in `docs/operations/agentic-ops.md`; anchored on OpenTelemetry GenAI semantic conventions.

> **What the Auto row proves — and doesn't.** `agentops-ready.sh` confirms the posture is *recorded* (an `Agent-ops:` trace record in RUNBOOK §8). It does **not** verify that traces *actually* emit, that they are *complete* (all required-core fields populated), or that the agent's *behavior conforms* over time. Those are the **Manual** rows, signed off with operator evidence. **A green script is necessary, not sufficient.**

## How to use
Copy this file into your project (or your reliability record). For each item: mark **Applies? (Y / N+reason)** and give **Evidence**. Items tagged *(documented)* are auto-checkable via `sh conformance/agentops-ready.sh`; items tagged *(verified)* require operator evidence from real agent runs. The reviewer signs off only when every applicable item has evidence.

## Checklist (blank)

| # | Item | Applies? | Evidence (where/how) | Check |
|---|------|----------|----------------------|-------|
| 1 | Trace discipline recorded — `Agent-ops:` in RUNBOOK §8 (schema + emitter + sink) *(documented)* | | | **Auto:** `agentops-ready.sh` |
| 2 | Required-core fields present in a real trace — identity keys, timing, cost, outcome, gates, tool-steps *(verified)* | | | Manual |
| 3 | Traces actually emit per agent-run — a real run's trace is viewable in the sink *(verified)* | | | Manual |
| 4 | Multi-agent keying holds — concurrent runs have distinct `(agent.id, run.id)`; `parent.run.id` builds the spawn tree *(verified)* | | | Manual |
| 5 | Guard denials captured — a `tool.outcome: denied` step appears when the §13 guard blocks an action *(verified)* | | | Manual |
| 6a | Behavior-scorecard discipline declared — agent traces scored over a window (`scripts/agent-scorecard.sh`) *(documented)* | | | Manual (no auto check asserts scorecard discipline yet) |
| 6b | Tier directives actually drive moves — a downgrade tightened / a ratified raise loosened a real agent's tier *(verified)* | | | Manual |

## Worked example — a project built by an agent (the kit dogfooding itself)

| # | Item | Applies? | Evidence | Check |
|---|------|----------|----------|-------|
| 1 | Trace discipline recorded *(documented)* | Y | RUNBOOK §8 "Agent-ops: trace=OTel-GenAI subset · emitter=CC-transcript · sink=`traces/`" | Auto ✅ |
| 2 | Required-core present *(verified)* | Y | a sampled `traces/<run>.json` shows agent.id/run.id/work_item.id, tokens, outcome, gates, tool-steps | Manual ✅ |
| 3 | Traces emit per run *(verified)* | Y | every merged PR's build run has a corresponding trace file | Manual ✅ |
| 4 | Multi-agent keying *(verified)* | Y | two parallel sub-agent runs show distinct run.ids + shared parent.run.id | Manual ✅ |
| 5 | Guard denials captured *(verified)* | Y | a blocked `rm -rf` shows `tool.outcome: denied` in the trace | Manual ✅ |
| 6a | Behavior-scorecard discipline declared *(documented)* | Y | scorecard run in CI weekly over `traces/` (`scripts/agent-scorecard.sh`); discipline noted in RUNBOOK §8 | Manual ✅ |
| 6b | Tier directives actually drive moves *(verified)* | Y | a regressed agent's tier was lowered via the platform policy after receiving an auto-downgrade directive | Manual ✅ |

> A non-agentic project (a plain library/CLI with no agent actor) marks the whole check **N/A — no agent runs to trace**; `agentops-ready.sh` skip-passes it automatically.
