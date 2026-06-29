# Meta-control panel #21 — E5-log (structured request logging), v3.70.0

**Date:** 2026-06-29 · **Cadence:** per-slice light 5-lens (condition A5) · **Basis:** fresh-clone evidence + dual review.
**Slice:** E5-log — the reference `server.ts` emits a structured JSON line per request; first slice of epic E5 (live observability / operate-loop). Design: `docs/architecture/2026-06-29-e5-log-structured-logging-design.md`.

## The 5 lenses

1. **Correctness / proof.** PASS. Behavioural red→green proven via `tsx` on the real reference server: the pre-logging app emits no `"requestId"` line (RED); the new logger emits one structured line per request with all 8 fields (`ts/level/service/requestId/method/path/status/latencyMs`, status+latency typed numeric) (GREEN). Golden-path asserts the same on the booted container via `jq` (non-vacuous — old app fails it). Conformance lock `--selftest` good/bad fixtures load-bearing. Fresh tagless clone: `verify --require` **32 controls / 0 failed** (+1), shellcheck **105** clean (+1).
2. **Scope / right-weight.** PASS. 11 files, all mirroring the proven `runtime-security`/E4c pattern (no new gate *type* — extends golden-path + the claims registry). New claim `structured-logging` ratified by the owner over overloading `runtime-security`. Zero-dependency logger (no pino).
3. **Security / trust.** PASS (security seat, verified a real `git archive` export). Injection-safe doubly: inbound `x-request-id` regex-bounded (`^[A-Za-z0-9._-]{1,128}$`) + all fields through `JSON.stringify`; no PII/secrets/headers logged; carve correct (adopter gets the logging scaffold, not the kit-self claim); no DoS amplification. One Low (query-string-in-`path` redaction note) folded into the `server.ts` comment + design Honest Ceiling.
4. **Honesty / ceiling.** PASS. Design states the floor plainly: reference app only (INFO-level request logs), adopters still pick their logger, log shipping/tracing/metrics are later E5 slices, behavioural docker truth is CI's (local green ≠ docker green). Justification corrected mid-design to the kit's OWN `DEVELOPMENT-STANDARDS §3` (not maintainer-personal context) — a harness-neutrality boundary the owner caught.
5. **Process / coherence.** PASS. Full loop on the kit's own spine (design→plan→tdd→verification→review), builder ≠ reviewer (two seats), AMBER apply.py idempotent + anchor-preflighted + clone-proven (11/11). All six claim registration/carve points consistent (verified by the reviewer). Standing process lessons applied (version-finishing in apply.py; close folded into the PR; release-tag after CI green).

## Verdict: **GO**

No conditions. The one security Low was folded before ship. E5 epic now underway; E5-log is the foundational observability primitive (seeds E5-trace's correlation id).

## Routed to backlog
- E5 next slices: E5-trace (request spans + export seam) · E5-metrics · E5-backend (live OTLP proof) · E5-ops (Ops/SRE seat).
- Marker to advance: `3.69.0 GO` → **`3.70.0 GO`** (human-authored per M2-S5, with the pipe-table log row).
