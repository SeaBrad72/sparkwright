# Resilience Verification — Reference

How to **prove** a service survives failure and load, rather than asserting it. Stack-neutral; tooling is a project/Org choice. Verifies the principles in `DEVELOPMENT-STANDARDS.md` §4 (resilience) and §6 (load-test before launch). Aligns with chaos-engineering (Principles of Chaos) / SRE reliability practice. This is the "how" behind the Resilience-readiness check (`conformance/resilience-readiness.md`).

> **Do no harm — inject faults in staging, never production.** Fault-injection and load/soak run against an **isolated / staging environment**, never live traffic. The point is to learn how the system fails *before* users do.

## Fault-injection drill
Kill or degrade a dependency (database, cache, downstream API) in staging and observe:
1. **Retries back off** — the client retries with exponential backoff + jitter, not a thundering herd.
2. **Circuit breaker trips** — after the failure threshold the breaker opens and fast-fails, sparing the dependency; it half-opens and recovers when the dependency returns.
3. **Graceful degradation** — the service serves a fallback (cached/stale data, a reduced feature, a clear error) and **does not crash or cascade**.
Record the date and what you observed in RUNBOOK §8.

## Load / soak test
1. Drive **sustained, realistic load** (model real traffic shape, not just a flat curve).
2. Watch **latency (p95/p99), error rate, and resource trends** (CPU, memory, connections).
3. Find the **knee** — the load where latency/errors break the §6 performance budget. Know your headroom.
4. **Soak** — hold moderate load for hours to surface memory leaks, connection exhaustion, and slow latency creep.
Record the date and the actuals vs. the §6 budget in RUNBOOK §8.

## What "passed" means
- Fault-injection: breaker/retry/degradation all behaved; no crash or cascade.
- Load/soak: stayed within the §6 budget at expected load, with known headroom and no leak.
- Recording a date is the **floor**; a *passed* drill (the Manual rows in `conformance/resilience-readiness.md`) is the **bar**. A recorded date alone does not prove resilience.

## Cadence
- **Pre-launch** (§6) for any public-facing service, and after any change to a dependency or the failure-handling path.
- Periodically thereafter (recurring maintenance, §15).

## Tooling (Org-owned)
Load generators (k6, Locust, Gatling, JMeter, vegeta, artillery) and fault-injection (toxiproxy, a chaos-engineering tool, or a manual dependency-kill in staging) are platform choices. The kit standardizes the **practice and the proof**, not the tool.
