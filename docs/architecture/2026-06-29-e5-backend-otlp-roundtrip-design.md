# E5-backend — live OTLP backend round-trip (real collector receipt)

**Date:** 2026-06-29
**Status:** Approved (owner-ratified design gate)
**Epic:** E5 (live observability / operate-loop) — fourth app-observability slice, after E5-log (3.70.0), E5-trace (3.71.0), E5-metrics (3.72.0). The first slice proving the app's telemetry reaches a **real OTLP collector**, not just that it is emitted and convertible.

## Decision (owner-ratified)

Prove **receipt at a real collector**: stand up the canonical OpenTelemetry Collector in golden-path CI, POST the booted reference app's spans to it via the **existing** `scripts/otlp-export.sh` real path (not `--dry-run`), and assert the exact emitted `trace_id` was received and decoded.

Three forks resolved at the design gate:

1. **Proof ambition — receipt at a collector** (not a queryable backend). The OTel Collector *is* a real OTLP backend; its OTLP/HTTP ingest endpoint is exactly what a vendor backend (Honeycomb, Grafana Cloud) exposes. The smallest slice that proves *real delivery* with the strongest non-vacuity (exact high-entropy `trace_id` match). **Queryable-in-a-backend** (Jaeger/Tempo + query-API round-trip) is **banked for E5-ops** — it pairs with the Ops/SRE seat that actually queries traces in an incident (roster demand-gating), and it adds storage + eventual-consistency polling that this slice deliberately avoids.

2. **Assertion path — debug exporter → `docker logs`** (not a file exporter). The debug exporter ships in the **core** `otel/opentelemetry-collector` image and writes to stdout as it processes each span — deterministic to assert via a short `docker logs` poll, no volume mount, no file-flush timing. The file exporter (contrib-only) reintroduces the buffer/flush eventual-consistency risk this slice rejected when it declined Jaeger, and a mount reintroduces the host-uid/permission class that bit E4a's `/work`. The "substring vs structured" worry is weak when the matched token is a random 32-hex `trace_id`: the collector can only print it if it received *and decoded* the OTLP payload.

3. **Placement — new dedicated `otlp-backend` job + ship the collector config.** Mirrors the established one-job-per-heavy-dimension pattern (`containment-audit`, `image-vuln`, `agentops-sensor`, `orchestrator-loop`). The log/trace/metrics assertions live in Boot-1 only because they are cheap reads of the already-booted app; E5-backend needs a *second* container with its own lifecycle. Shipping a minimal reference collector config (proven == provided) completes the operate-loop story for the adopter; it is the same file CI runs, so there is zero drift between "the documented config" and "what CI proves."

## Mechanism — new `otlp-backend` job in `.github/workflows/golden-path.yml`

A sibling job (re-incepts the reference stack, like `containment-audit`/`image-vuln`):

1. Scaffold a temp adopter project via `scripts/incept.sh` (reference typescript-node stack).
2. Stage + `docker build` the reference image; boot the app container (`docker run -d --name gp -p 3000:3000`) and `wait_live` on `/healthz` (same idiom as Boot-1). The app emits an OTel span line per served request to stdout.
3. Capture spans: `docker logs gp 2>&1 | grep -F '"trace_id"' > gp_spans.ndjson`; `[ -s gp_spans.ndjson ]` (non-vacuous — the app must have emitted at least one span). Record the emitted id: `EMITTED=$(tail -1 gp_spans.ndjson | jq -r .trace_id)`.
4. Boot the collector: `docker run -d --name otelcol -p 4318:4318 -v <config>:/etc/otelcol/config.yaml <pinned otel/opentelemetry-collector>` using the **shipped scaffold config**; poll until the collector's OTLP/HTTP port answers (bounded, ~30s, same shape as `wait_live`).
5. **Real POST (the seam under test):** `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 sh scripts/otlp-export.sh gp_spans.ndjson` — no `--dry-run`. This exercises `otlp-export.sh`'s POST path (curl → `$endpoint/v1/traces`, OTLP/JSON) for the first time in CI.
6. **Assert receipt (non-vacuous, two-part):** poll `docker logs otelcol` until it shows BOTH the exact `$EMITTED` 32-hex `trace_id` AND a decoded-span marker (the debug exporter's `ResourceSpans`/span output, count > 0). A collector that received nothing, or logged only startup noise, fails. On failure, dump both `docker logs gp` and `docker logs otelcol`; always `docker rm -f gp otelcol` on the way out.
7. Echo `otlp-backend: OK — app spans POSTed via otlp-export.sh and received+decoded by a real OTLP collector`.

### Why `otlp-export.sh` and `server.ts` are unchanged

`server.ts` already emits the span (E5-trace). `otlp-export.sh` already POSTs to `$OTEL_EXPORTER_OTLP_ENDPOINT/v1/traces` — E5-trace exercised only its `--dry-run` (conversion) path. E5-backend exercises the **untested POST path against a real collector**, retroactively validating that the seam was real, not a dry-run prop. If a change to `otlp-export.sh` proves necessary at build time (e.g. the collector rejects a payload detail), that is a finding to surface — the design intent is **zero export-script change**.

## Provided artifact — `profiles/typescript-node/scaffold/observability/otel-collector.yaml`

A minimal reference collector config that travels with the reference stack and is the exact file the golden-path job mounts:

- `receivers: otlp` with the `http` protocol on `:4318` (the OTLP/HTTP endpoint `otlp-export.sh` POSTs to).
- `exporters: debug` with `verbosity: detailed` (received spans → stdout).
- `service.pipelines.traces`: `otlp` receiver → `debug` exporter.

Honest scope note in the file's header comment: this is a **local/CI reference** — an adopter swaps the `debug` exporter for their vendor's OTLP exporter (and points `OTEL_EXPORTER_OTLP_ENDPOINT` at it), exactly as `otlp-export.sh` already documents for the endpoint/headers.

## Conformance

New `conformance/otlp-backend-wired.sh` + claim `otlp-backend` (claims +1), mirroring `app-tracing`/`structured-logging`/`runtime-security`:

- `check_config`: the shipped `otel-collector.yaml` declares the OTLP receiver (`otlp`, `http`, `4318`) and a traces pipeline (tokens: `otlp`, `4318`, `debug`, `traces`).
- `check_wf`: the golden-path `otlp-backend` job carries the round-trip assertion (`otlp-backend: OK`, `otlp-export.sh`, `OTEL_EXPORTER_OTLP_ENDPOINT`, and the **absence** of `--dry-run` on the export invocation — the proof is the real POST).
- `--selftest`: load-bearing good/bad fixtures — config missing the OTLP receiver → FAIL; job whose export call carries `--dry-run` (i.e. not a real POST) → FAIL; job missing the `trace_id` receipt assertion → FAIL.
- **Kit-self carve** (export-ignored): `golden-path.yml` is export-stripped, so `otlp-backend-wired.sh` is carved from the adopter export in BOTH `adopter-export.sh` loops, mirroring `app-tracing`/`runtime-security`. The shipped collector config itself is NOT carved (it is an adopter-facing artifact under `profiles/typescript-node/scaffold/`).
- 6-point registration: `claims.tsv` · `claims-registry.sh` `REQUIRED_IDS` · `verify.sh` · `ci.yml` `--selftest` · `adopter-export.sh` carve (both loops).

## Path filters

`golden-path.yml` already triggers on `profiles/typescript-node/**` (covers the new scaffold config) and `.github/workflows/golden-path.yml` (covers the new job). No `paths:` change needed; if the build finds an edge (e.g. wanting the conformance script in the trigger set), add it then.

## Honest ceiling

- Proves **delivery + ingest-acceptance round-trip** on the reference app: app-emitted spans, sent through the real `otlp-export.sh` POST path, are received and decoded by a real OTLP collector.
- **Not** in scope: long-term storage, trace query/retrieval, a live vendor backend, distributed-context propagation, metrics/logs delivery (this slice is traces — the seam `otlp-export.sh` serves). Adopter swaps the exporter for their vendor.
- **Queryable-in-a-backend** (Jaeger/Tempo + query-API assertion) is banked for **E5-ops**, paired with the Ops/SRE seat per roster demand-gating.

## Scope & build model — AMBER

Files (lighter than the prior E5 slices — no `server.ts`, no `otlp-export.sh` change): `.github/workflows/golden-path.yml` (new job) · `profiles/typescript-node/scaffold/observability/otel-collector.yaml` (new) · `conformance/otlp-backend-wired.sh` (new) · `conformance/claims.tsv` · `conformance/claims-registry.sh` · `conformance/verify.sh` · `.github/workflows/ci.yml` · `scripts/adopter-export.sh` (×2 loops) · `VERSION`/`README.md`/`CHANGELOG.md` (3.72.0→3.73.0). One idempotent `apply.py`, clone-proven, human-applied, with the version finishing folded in. Built test-first (the `--selftest` fixtures + a local collector round-trip dry-run before CI), dual-reviewed (Security: confirm no secret/PII path through the new POST flow — `otlp-export.sh`'s header-injection guard is already proven; the collector config introduces no auth; the round-trip uses a localhost CI endpoint).
