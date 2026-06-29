# Meta-control panel #22 — E5-trace (app-level request tracing), v3.71.0

**Date:** 2026-06-29 · **Cadence:** per-slice light 5-lens (condition A5) · **Basis:** fresh-clone evidence + dual review.
**Slice:** E5-trace — the reference `server.ts` emits a zero-dep OTel-semantic span per request, converted by the existing `otlp-export.sh` seam; second slice of epic E5. Design: `docs/architecture/2026-06-29-e5-trace-request-spans-design.md`.

## The 5 lenses

1. **Correctness / proof.** PASS. Behavioural red→green via `tsx`: pre-trace app emits no `"trace_id"` line (RED); the new emitter produces a schema-valid span (32-hex trace / 16-hex span, real non-zero duration, http attrs, `request_id` correlation) that **converts through the real `otlp-export.sh --dry-run` seam** to valid OTLP (GREEN). Golden-path asserts the same on the booted container (non-vacuous). Fresh tagless clone: `verify --require` **33 controls / 0 failed** (+1), shellcheck **106** clean (+1).
2. **Scope / right-weight.** PASS. 11 files mirroring the proven E5-log/runtime-security pattern (no new gate type — extends golden-path + claims registry; **reuses** the existing OTLP seam rather than adding one). Zero-dep (`node:crypto`/`node:fs`), as owner-ratified over the OTel SDK.
3. **Security / trust.** PASS (security seat, tested 5 injection payloads through the seam). No NDJSON/field injection (`JSON.stringify` escaping, layered behind Node's CR/LF-encoding of `req.url`); query string stripped from the span name (secret hygiene); closed allow-list of attributes (method/status/request_id); OTLP seam stays jq-only, no POST on `--dry-run`; carve correct (both loops + REQUIRED_IDS). No findings.
4. **Honesty / ceiling.** PASS. Design states the floor: single root span per request, emission + OTLP-convertibility proven; child spans / context propagation / auto-instrumentation are the adopter's (OTel SDK), live backend round-trip is E5-backend; doubled stdout disclosed. Reviewer's Minor (nanosecond precision) folded → `*_unix_nano` now emitted as exact OTLP-canonical decimal strings.
5. **Process / coherence.** PASS. Full loop on the kit's own spine (design→plan→tdd→verification→review), builder ≠ reviewer (two seats), AMBER apply.py idempotent + anchor-preflighted + clone-proven (11/11). Verified `otlp-export.sh` survives incept into GP_DIR before wiring the seam-proof (no dead path). Standing process lessons applied.

## Verdict: **GO**

No conditions. The one reviewer Minor (nanos fidelity) was folded before ship. E5 progressing: E5-log → E5-trace shipped; next E5-metrics → E5-backend → E5-ops.

## Routed to backlog
- E5 next: E5-metrics · E5-backend (live OTLP backend round-trip in CI) · E5-ops (Ops/SRE seat).
- Marker to advance: `3.70.0 GO` → **`3.71.0 GO`** (human-authored per M2-S5, with the pipe-table log row).
