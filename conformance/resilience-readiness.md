# Conformance Check — Resilience Readiness

Proves a service **survives failure and load**: retries back off, circuit breakers trip, the service degrades gracefully, and it holds up under load/soak. **Checklist-type**, run at the **Resilience-readiness gate** (`DEVELOPMENT-PROCESS.md` §7) and as **recurring maintenance** (§15). **Conditional:** non-deployable projects (library, CLI, batch) mark the whole check **N/A — no dependencies to circuit-break or load to soak**. Verifies the principles asserted in `DEVELOPMENT-STANDARDS.md` §4 (resilience) and §6 (load-test before launch). Aligns with chaos-engineering (Principles of Chaos) / SRE reliability practice.

> **What the Auto rows prove — and don't.** `resilience-ready.sh` confirms the drills are *recorded* (a load/soak date and a fault-injection date in RUNBOOK §8). It does **not** verify the system is *actually* resilient — that the breaker tripped, the service degraded gracefully, or it survived the soak. Those are the **Manual** rows, signed off by the on-call/operator with evidence. **A green script is necessary, not sufficient.**

## How to use
Copy this file into your project (or your reliability record). For each item: mark **Applies? (Y / N+reason)** and give **Evidence**. Items tagged *(documented)* are auto-checkable via `sh conformance/resilience-ready.sh`; items tagged *(verified)* require the on-call/operator's evidence from an actual drill. The reviewer signs off only when every applicable item has evidence. How to run the drills: `docs/operations/resilience-verification.md`.

## Checklist (blank)

| # | Item | Applies? | Evidence (where/how) | Check |
|---|------|----------|----------------------|-------|
| 1 | Retry with backoff exercised on a transient failure (§4) *(verified)* | | | Manual |
| 2 | Circuit breaker **trips** when a dependency fails (§4) *(verified)* | | | Manual |
| 3 | Graceful degradation — killed dependency → service degrades, not crashes (§4) *(verified)* | | | Manual |
| 4 | Idempotency verified for retryable operations (§4) *(verified)* | | | Manual |
| 5 | Fault-injection drill **run** — date recorded (RUNBOOK §8) *(documented)* | | | **Auto:** `resilience-ready.sh` |
| 6 | Load test **run** — latency/error within the §6 budget *(verified)* | | | Manual |
| 7 | Soak test clean — no leak / latency creep over time *(verified)* | | | Manual |
| 8 | Load/soak **run** — date recorded (RUNBOOK §8) *(documented)* | | | **Auto:** `resilience-ready.sh` |

## Worked example — a deployable HTTP service with a Postgres dependency

| # | Item | Applies? | Evidence | Check |
|---|------|----------|----------|-------|
| 1 | Retry/backoff *(verified)* | Y | injected 3 transient DB errors; client retried with backoff, no herd (drill log) | Manual ✅ |
| 2 | Breaker trips *(verified)* | Y | killed DB; breaker opened after threshold, fast-failed; recovered on restore | Manual ✅ |
| 3 | Graceful degradation *(verified)* | Y | cache down → served stale within TTL; no 5xx spike | Manual ✅ |
| 4 | Idempotency *(verified)* | Y | duplicate POST with same key → single effect (test) | Manual ✅ |
| 5 | Fault-injection recorded *(documented)* | Y | RUNBOOK §8 "Fault-injection drill: 2026-06-02" | Auto ✅ |
| 6 | Load within budget *(verified)* | Y | 500 rps, p95 180ms (< 200ms §6), error < 0.1% (k6 report) | Manual ✅ |
| 7 | Soak clean *(verified)* | Y | 4h soak, flat memory, no latency creep (Grafana) | Manual ✅ |
| 8 | Load/soak recorded *(documented)* | Y | RUNBOOK §8 "Load/soak tested: 2026-06-01" | Auto ✅ |

> A library or CLI marks the whole check **N/A — no dependencies to circuit-break or load to soak**; `resilience-ready.sh` skip-passes such a project automatically.
