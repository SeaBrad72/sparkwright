# E5-trace — app-level request tracing (zero-dep OTel spans)

**Date:** 2026-06-29
**Status:** Approved (owner-ratified design gate)
**Epic:** E5 (live observability / operate-loop) — second slice, after E5-log. Consumes E5-log's `requestId` as the trace correlation key.

## Decision (owner-ratified)

**Zero-dep OTel-semantic spans**, not the OpenTelemetry SDK. The kit already ships this idiom for *agent* telemetry — `scripts/otel-trace.sh` emits zero-dep OTel-semantic NDJSON spans and `scripts/otlp-export.sh` converts them to OTLP/JSON. E5-trace applies the same idiom to *app HTTP requests*, reusing the existing export seam. Consistent with the kit's zero-dep references + dependency-justification standard; an adopter wanting auto-instrumentation/distributed context swaps in the OTel SDK (noted, not built).

## Change — `server.ts` (zero-dep span per request)

In addition to the E5-log structured line, emit one OTel-semantic **span** line per request in the exact `otel-trace.sh` schema (`{trace_id, span_id, parent_span_id, name, start_unix_nano, end_unix_nano, attributes, status}`):
- `trace_id` = `randomBytes(16).toString('hex')` (32 hex); `span_id` = `randomBytes(8).toString('hex')` (16 hex); `parent_span_id: null` (root span). `node:crypto` — no dependency.
- `name` = `` `${method} ${pathWithoutQuery}` `` — strip the query string (span-name cardinality + the same secret-hygiene reason as E5-log's `path` note).
- `start_unix_nano`/`end_unix_nano` = wall-clock (`Date.now()` × 1e6) anchored at request start + `process.hrtime.bigint()` delta on finish → a **real non-zero duration** (improves on `otel-trace.sh`'s documented zero-duration agent spans). Emitted as **exact decimal strings** (folded from review Minor): OTLP/JSON canonically represents `*_unix_nano` as strings, and a JS `Number` would lose precision past ~9e15 (unix nanos are ~1.8e18); the golden-path duration check compares via `|tonumber`.
- `attributes`: `{ 'http.request.method': method, 'http.response.status_code': String(status), 'request_id': requestId }`. `request_id` correlates the span to the E5-log line; snake_case so it does not collide with E5-log's `"requestId"` golden-path grep.
- `status: { code: status >= 500 ? 'ERROR' : 'OK' }`.
- Sink: honor `OTEL_TRACE_FILE` if set, else stdout (mirrors `otel-trace.sh`). In the golden-path container it is stdout → captured by `docker logs`.

Emitted on `res.on('finish')` alongside the E5-log line.

## Proof (behavioural + non-vacuous + real seam)

Golden-path, in the existing Boot-1 block (the booted container has already served requests via `wait_live`):
1. Extract the span line: `docker logs gp | grep -F '"trace_id"' | tail -1`. `[ -n ]` (non-vacuous: the pre-trace app emits no such line → RED).
2. `jq -e` it is schema-valid: `trace_id` is 32-hex, `span_id` is 16-hex, `(.end_unix_nano > .start_unix_nano)` (real duration), `.attributes["http.request.method"]`, `.attributes.request_id`, `.status.code`.
3. **Real export seam:** write the span line to a file and run `sh scripts/otlp-export.sh <file> --dry-run`; assert the output `has("resourceSpans")` and a span with `traceId`/`spanId`. Proves the app's spans flow through the existing OTLP converter (the no-dead-ends / real-integration-seam principle).
4. Echo `app-tracing: OK`.

## Conformance

New `conformance/app-tracing-wired.sh` + claim `app-tracing`, mirroring `structured-logging`/`runtime-security`:
- `check_server`: `server.ts` emits the span (tokens: `trace_id`, `span_id`, `start_unix_nano`, `randomBytes`).
- `check_wf`: golden-path carries the assertion (`app-tracing: OK`, `"trace_id"`, `otlp-export.sh`, `--dry-run`).
- `--selftest`: good/bad fixtures (server missing `start_unix_nano` → FAIL; wf missing the `otlp-export --dry-run` proof → FAIL) — load-bearing.
- Kit-self carve (export-ignored; mirrors `runtime-security` N/A guard).
- 6-point registration: claims.tsv · claims-registry.sh REQUIRED_IDS · verify.sh · ci.yml `--selftest` · adopter-export.sh carve (both loops).

## Honest ceiling

- Proves zero-dep span **emission + OTLP-convertibility via the real seam** on the reference app — a **single root span per request** with a real duration.
- **Not** in scope: child spans, cross-service context propagation, auto-instrumentation (adopter swaps in the OTel SDK); no live OTLP backend round-trip (E5-backend).
- Doubles per-request stdout volume (log line + span line) — the standard 12-factor "emit events to stdout, the collector routes by structure" pattern.

## Scope & build model — AMBER

Files (~11, mirrors E5-log): `server.ts` · `.github/workflows/golden-path.yml` · `conformance/app-tracing-wired.sh` (new) · `conformance/claims.tsv` · `conformance/claims-registry.sh` · `conformance/verify.sh` · `.github/workflows/ci.yml` · `scripts/adopter-export.sh` (×2 loops) · `VERSION`/`README.md`/`CHANGELOG.md` (3.70.0→3.71.0). One idempotent `apply.py`, clone-proven, human-applied. Built test-first (behavioural tsx span emission + `otlp-export --dry-run` + lock `--selftest`), dual-reviewed (Security: confirm no PII/secret in span attrs; `request_id`/`path` hygiene carried from E5-log; `name` strips query).
