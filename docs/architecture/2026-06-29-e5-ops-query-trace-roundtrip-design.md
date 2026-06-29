# E5-ops-query — queryable-backend trace round-trip (operator finds the trace)

**Date:** 2026-06-29
**Status:** Approved (owner-ratified design gate)
**Epic:** E5 (live observability / operate-loop). First of the two E5-ops sub-slices. After E5-log (3.70.0), E5-trace (3.71.0), E5-metrics (3.72.0), E5-backend (3.73.0 — *receipt* at a collector). This slice proves the next operate-loop rung: **query/retrieval** — an operator can *find* a trace by id in a real queryable backend.

## Why this is its own slice (decomposition)

"E5-ops" is two cohesive sub-slices. Bundling them makes one ~14-file change spanning two registration patterns (a skill brick **and** a heavy new CI claim) — heavier than anything shipped in one slice, and it conflates the cheap craft skill with the heavier query infra. So:

- **E5-ops-query (this slice)** — the queryable-backend round-trip. Concrete behaviour, ~11 files, the E5-backend shape. Proves "the operator can find the trace."
- **E5-ops-skill (next slice)** — the `operating` skill brick (the operate-phase craft: investigate telemetry → triage → decide *safely*), carrying the **blast-radius discipline** (advisory-not-actuating; the human commands the catastrophic action; high-risk actions route through the escalation seam). Ops/SRE is the Orchestrator's **hat**, not a standing seat (the kit has no live system of its own to operate; the seat is demand-gated on a live system **+** distinct prod authority — a clean future promotion). It *points at* the capability this slice proves.

Build order is proven-not-prescribed: prove the capability (query), then write the craft that uses it.

## Decision (owner-ratified)

Prove the **storage + query round-trip** against **Jaeger all-in-one** — one gradient past E5-backend (which proved *receipt* at a debug-exporter collector). POST the booted app's spans via the **existing** `scripts/otlp-export.sh` real path to Jaeger's OTLP/HTTP ingest, then **retrieve the exact emitted `trace_id` via Jaeger's query API** and assert the trace is returned with a span.

Forks resolved at the design gate:

1. **Backend = Jaeger all-in-one** (not Tempo). Single SHA-pinned container, in-memory storage, OTLP/HTTP ingest on `:4318`, a trivial query-by-id API (`GET /api/traces/{traceID}`) on `:16686`, no config file. Tempo needs a storage config and has higher ingest→queryable latency = more eventual-consistency polling = more CI flake for no added proof value. On a high-criticality craft, a flaky proof is worse than no proof.

2. **Portability via the OTLP standard, not via shipping configs.** `otlp-export.sh` speaks vendor-neutral OTLP/HTTP; the CI proof picks one concrete backend, the seam stays neutral (exactly as E5-backend did with the OTel Collector). The shipped "provided" surface is the documented Jaeger `docker run` + a vendor-neutral note: *point `OTEL_EXPORTER_OTLP_ENDPOINT` at any OTLP backend — Tempo, Honeycomb, Grafana Cloud, Datadog*. **No second maintained backend config** (avoids the append-drift anti-pattern; only one backend is ever CI-proven).

3. **`server.ts` and `otlp-export.sh` unchanged** — again. The slice queries the far end of the same seam E5-trace/E5-backend already proved on the near end.

## Mechanism — new `trace-query` job in `.github/workflows/golden-path.yml`

A sibling job (re-incepts the reference stack, like `otlp-backend`/`containment-audit`):

1. Scaffold a temp adopter project (`incept.sh`), `docker build` the reference image, boot the app (`docker run -d --name gp -p 3000:3000`), `wait_live` on `/healthz`.
2. Capture spans: `docker logs gp 2>&1 | grep -F '"trace_id"' > gp_spans.ndjson`; `[ -s gp_spans.ndjson ]`. Record `EMITTED=$(tail -1 gp_spans.ndjson | jq -r .trace_id)`; validate `^[0-9a-f]{32}$`.
3. Boot Jaeger: `docker run -d --name jaeger -e COLLECTOR_OTLP_ENABLED=true -p 4318:4318 -p 16686:16686 jaegertracing/all-in-one@sha256:<PINNED>`; poll until both the OTLP port (`:4318`) and the query port (`:16686/`) answer (bounded ~30s).
4. **Real POST (the existing seam):** `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 sh scripts/otlp-export.sh gp_spans.ndjson` — no `--dry-run`.
5. **Query round-trip (the new proof):** poll `GET http://localhost:16686/api/traces/$EMITTED` (bounded ~15× 1s, for ingest→queryable consistency) until the response has `.data | length > 0`. **Assert (non-vacuous):** `.data[0].traceID` equals `$EMITTED` (case-insensitive) **AND** `[.data[0].spans[]] | length > 0`. A backend that received nothing returns `.data == []` → fails; the random 32-hex id cannot be fabricated by an empty store.
6. `trap` cleanup `docker rm -f gp jaeger`; on failure dump `docker logs jaeger` + `gp`. Echo `trace-query: OK — app spans POSTed via otlp-export.sh and RETRIEVED by trace_id from a real Jaeger query API`.

**Build-time de-risk (mirrors E5-backend's local round-trip):** before relying on CI, run the round-trip locally against the pinned Jaeger image and confirm the exact query-API response shape (Jaeger's `traceID` casing / leading-zero handling, the `.data[0].spans` path). If the pinned version's response shape differs, adjust the jq assertion and record it. Docker is available locally.

## Provided (vendor-neutral, no new maintained config)

Jaeger all-in-one needs no config file, so this slice ships **no new config artifact**. The provided reference is documentation: a short "see your traces locally" block (the Jaeger `docker run` + the `otlp-export.sh` POST + the query URL) plus the vendor-neutral swap note, added to the existing observability reference (the `profiles/typescript-node/scaffold/observability/` README or `docs/operations/operate-loop.md` — chosen at plan time to sit with the E5-backend collector reference). This keeps "provided" honest: one CI-proven local backend + standard-OTLP guidance for any vendor.

## Conformance

New `conformance/trace-query-wired.sh` + claim `trace-query` (claims +1), mirroring `otlp-backend`/`app-tracing`:

- `check_wf`: the golden-path `trace-query` job carries the round-trip assertion. Tokens: `trace-query: OK`, the exact real-POST line `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 sh scripts/otlp-export.sh gp_spans.ndjson` (anchored `grep -qE` end-of-line, per the E5-backend lesson — the real POST, not `--dry-run`), the Jaeger query path `/api/traces/`, and the image `jaegertracing/all-in-one`.
- `--selftest`: load-bearing good/bad fixtures — a job whose POST carries `--dry-run` → FAIL; a job missing the `/api/traces/` query assertion → FAIL; a job missing `trace-query: OK` → FAIL.
- **Kit-self carve** (export-ignored): `golden-path.yml` is export-stripped, so `trace-query-wired.sh` is carved from the adopter export in BOTH `adopter-export.sh` loops (mirrors `otlp-backend`).
- 6-point registration: `claims.tsv` · `claims-registry.sh` `REQUIRED_IDS` · `verify.sh` · `ci.yml` `--selftest` · `adopter-export.sh` carve (both loops).

## Honest ceiling

- Proves **storage + query round-trip** on the reference app: app-emitted spans, sent through the real `otlp-export.sh` POST path, are **stored in and retrievable by `trace_id` from a real Jaeger backend's query API**.
- **Not** in scope: production storage durability, sampling, multi-tenant/retention, a live vendor query API, log/metric query (this slice is traces — the seam `otlp-export.sh` serves), and the **operate craft** (triage/decide-safely) — that is E5-ops-skill.
- Jaeger is the CI-proven local reference; any OTLP backend works via the standard (vendor swap is the adopter's).

## Scope & build model — AMBER

Files (~11, the E5-backend shape; no `server.ts`/`otlp-export.sh` change, no new shipped config): `.github/workflows/golden-path.yml` (new `trace-query` job) · `conformance/trace-query-wired.sh` (new) · `conformance/claims.tsv` · `conformance/claims-registry.sh` · `conformance/verify.sh` · `.github/workflows/ci.yml` · `scripts/adopter-export.sh` (×2 loops) · the observability reference doc (the Jaeger run + swap note) · `VERSION`/`README.md`/`CHANGELOG.md` (3.73.0→3.74.0). One idempotent `apply.py`, clone-proven, human-applied, version finishing folded in. Built test-first (the `--selftest` fixtures + the local Jaeger round-trip de-risk before CI), dual-reviewed (Security: the new POST is localhost-only and `otlp-export.sh` is unchanged; Jaeger's query/UI ports are CI-local only — confirm no auth/secret surface and that the query API exposure is not shipped to adopters as an open endpoint).
