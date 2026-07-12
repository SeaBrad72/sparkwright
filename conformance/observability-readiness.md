# Conformance Check — Observability Readiness

Proves a service is **observable in production**: SLOs are declared, telemetry (metrics + distributed traces + health signals — Factor 14) is wired, alerts fire on SLO breach, and the error budget is tracked. **Checklist-type**, run at the **Observability readiness gate** (`DEVELOPMENT-PROCESS.md` §7) and as **recurring maintenance** (§15). **Conditional:** non-deployable projects (library, CLI, batch) mark the whole check **N/A — no running service to set SLOs on or emit telemetry from**. Verifies the principles asserted in `DEVELOPMENT-STANDARDS.md` Factor 14 (Telemetry) and §3 (Observability). Aligns with Google SRE (SLOs, error budgets) and the OpenTelemetry observability model.

> **What the Auto rows prove — and don't.** `observability-ready.sh` confirms the posture is *recorded* (an SLO target and a telemetry signal set in RUNBOOK §8). It does **not** verify the system is *actually* observable — that the signals emit in prod, the alerts fire on breach, or the error budget is tracked over time. Those are the **Manual** rows, signed off by the operator with evidence. **A green script is necessary, not sufficient.**

## How to use
Copy this file into your project (or your reliability record). For each item: mark **Applies? (Y / N+reason)** and give **Evidence**. Items tagged *(documented)* are auto-checkable via `sh conformance/observability-ready.sh`; items tagged *(verified)* require the operator's evidence from the running system. The reviewer signs off only when every applicable item has evidence.

## Checklist (blank)

| # | Item | Applies? | Evidence (where/how) | Check |
|---|------|----------|----------------------|-------|
| 1 | SLOs declared — availability / latency / error budget (RUNBOOK §8) *(documented)* | | | **Auto:** `observability-ready.sh` |
| 2 | Telemetry wired — metrics + traces + health recorded (RUNBOOK §8) *(documented)* | | | **Auto:** `observability-ready.sh` |
| 3 | Metrics actually emit in prod — dashboard shows live signal *(verified)* | | | Manual |
| 4 | Distributed traces actually emit — a real request trace is viewable *(verified)* | | | Manual |
| 5 | Health/readiness endpoint live — probe returns real status *(verified)* | | | Manual |
| 6 | Alert fires on SLO breach — tested with a synthetic breach *(verified)* | | | Manual |
| 7 | Error budget tracked over time — burn-rate visible, drives decisions *(verified)* | | | Manual |

## Worked example — a deployable HTTP service

| # | Item | Applies? | Evidence | Check |
|---|------|----------|----------|-------|
| 1 | SLOs declared *(documented)* | Y | RUNBOOK §8 "SLOs: 99.9% avail, p95 < 200ms, error budget 0.1%" | Auto ✅ |
| 2 | Telemetry wired *(documented)* | Y | RUNBOOK §8 "Telemetry wired: Prometheus + OTel traces + /healthz" | Auto ✅ |
| 3 | Metrics emit *(verified)* | Y | Grafana dashboard shows live RPS/latency/error series | Manual ✅ |
| 4 | Traces emit *(verified)* | Y | a sampled request trace viewable end-to-end (Tempo/Jaeger) | Manual ✅ |
| 5 | Health endpoint live *(verified)* | Y | `/healthz` returns 200 + dependency status; probe wired | Manual ✅ |
| 6 | Alert fires on breach *(verified)* | Y | injected latency > SLO → page fired to on-call (alert log) | Manual ✅ |
| 7 | Error budget tracked *(verified)* | Y | burn-rate panel + monthly budget review drives release pace | Manual ✅ |

> A library or CLI marks the whole check **N/A — no running service to set SLOs on or emit telemetry from**; `observability-ready.sh` skip-passes such a project automatically.
