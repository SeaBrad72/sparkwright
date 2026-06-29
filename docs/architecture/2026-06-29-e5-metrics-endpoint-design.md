# E5-metrics — a `/metrics` endpoint (zero-dep Prometheus exposition)

**Date:** 2026-06-29
**Status:** Approved (owner-ratified design gate)
**Epic:** E5 (live observability / operate-loop) — third slice, after E5-log + E5-trace. Completes Factor 14's telemetry quartet on the reference app.

## Justification (kit-internal)

`DEVELOPMENT-STANDARDS.md` §15-factor **Factor 14 (Telemetry)** (line 198): *"Emit **metrics, distributed traces, and health signals** — not just logs — so the running system is observable."* The reference app already ships **health** (`/healthz`), **logs** (E5-log), and **traces** (E5-trace). **Metrics is the missing quarter** — E5-metrics makes Factor 14 fully proven on the reference app, not partly prescribed.

## Format decision (owner-ratified)

`GET /metrics` in **Prometheus text exposition format** (`text/plain; version=0.0.4`), zero-dep. The universal `/metrics` scrape convention; a real integration seam (Prometheus scrapes it directly); trivially zero-dep (text lines). Not the OpenTelemetry metrics SDK (heavy dependency; `/metrics` is canonically Prometheus regardless — traces→OTel + metrics→Prometheus is the standard real-world combo). Consistent with the kit's zero-dep references and the E5-trace zero-dep precedent.

## Change — `server.ts` (zero-dep)

Two in-memory counters updated in the existing `res.on('finish')` hook, plus a new `/metrics` route:
- `http_requests_total{method,status}` — a counter Map keyed by `method` + `status`, incremented per request. **Labels are method + status only** (bounded cardinality; *not* path — same high-cardinality + secret-hygiene reason as E5-log/E5-trace).
- `http_request_duration_seconds_total` — accumulated request latency in seconds (a counter; gives request rate + average latency via PromQL `rate()`).
- `GET /metrics` → `200`, `Content-Type: text/plain; version=0.0.4`, + `SECURITY_HEADERS`; body = the Prometheus exposition text (`# HELP` / `# TYPE` + one line per `{method,status}` series + the duration counter).
- Label values are restricted to known-safe tokens (method/status are already constrained; method is escaped/validated defensively so a bizarre method cannot break the exposition line).

Recording happens on `res.on('finish')` (alongside the E5-log line + E5-trace span). The `/metrics` response reflects all requests completed before this scrape.

## Proof (behavioural + non-vacuous)

Golden-path, after the booted container has served requests (`wait_live` + the header/log/span curls):
1. `curl -fsS http://localhost:3000/metrics` → capture body.
2. Assert valid Prometheus shape: contains `# TYPE http_requests_total counter` AND a `http_requests_total{method="GET"` series line whose value is `> 0` (the prior `/healthz` requests were counted).
3. Echo `metrics-endpoint: OK`.
   - **Non-vacuous:** the pre-metrics app 404s `/metrics` (no `http_requests_total` output) → RED; a `/metrics` that returns the help text but a zero/missing counter → the `> 0` check fails → RED.

## Conformance

New `conformance/metrics-endpoint-wired.sh` + claim `metrics-endpoint`, mirroring `structured-logging`/`app-tracing`:
- `check_server`: `server.ts` exposes `/metrics` + emits `http_requests_total` + `# TYPE` (the exposition format).
- `check_wf`: golden-path carries the assertion (`metrics-endpoint: OK`, `http_requests_total`, `/metrics`).
- `--selftest`: good/bad fixtures (server missing `http_requests_total` → FAIL; wf missing the assertion → FAIL) — load-bearing.
- Kit-self carve (export-ignored; mirrors `runtime-security` N/A guard).
- 6-point registration: claims.tsv · claims-registry.sh REQUIRED_IDS · verify.sh · ci.yml `--selftest` · adopter-export.sh carve (both loops).

## Honest ceiling

- Proves a zero-dep Prometheus `/metrics` FLOOR on the reference app — the **RED metrics core** (request count by method/status + total duration). Enough for rate, error-ratio, and average latency.
- **Not** in scope: histograms/quantiles/buckets (an adopter adds them), a live Prometheus scrape round-trip, and per-endpoint/path series (deliberately bounded labels).
- `/metrics` is exposed **openly** on the reference app; adopters often restrict it to an internal network or behind auth — noted, not enforced (the reference shows the FLOOR).
- Counts every request including `/metrics` scrapes (standard scrape behaviour).

## Scope & build model — AMBER

Files (~11, mirrors E5-log/E5-trace): `server.ts` · `.github/workflows/golden-path.yml` · `conformance/metrics-endpoint-wired.sh` (new) · `conformance/claims.tsv` · `conformance/claims-registry.sh` · `conformance/verify.sh` · `.github/workflows/ci.yml` · `scripts/adopter-export.sh` (×2 loops) · `VERSION`/`README.md`/`CHANGELOG.md` (3.71.0→3.72.0). One idempotent `apply.py`, clone-proven, human-applied. Test-first (behavioural tsx: curl `/metrics`, assert counter increments + valid exposition format; lock `--selftest`), dual-reviewed (Security: confirm bounded labels / no PII / method-value escaping in the exposition line, and the open-`/metrics` ceiling).
