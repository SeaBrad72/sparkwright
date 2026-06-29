# E5-log — structured request logging on the reference app

**Date:** 2026-06-29
**Status:** Approved (owner-ratified design gate)
**Epic:** E5 (live observability / operate-loop) — first slice. The agent operate-loop is already closed on the real orchestrator (golden-path `agentops-sensor` runs `scripts/orchestrator-run.sh`); E5's remaining surface is the reference app's **own** observability. E5-log is the foundational primitive; later slices (E5-trace, E5-metrics, E5-backend, E5-ops) build on it.

## Justification (kit-internal — corrected basis)

The kit's **own** stack-neutral standards prescribe this, independent of any maintainer-personal context:
- `DEVELOPMENT-STANDARDS.md` §3 Observability: *"Structured logging (machine-parseable in production; human-readable in dev). Every entry: timestamp, level, message, request/correlation ID, service."* + *"Log levels used correctly: ERROR · WARN · INFO · DEBUG."*
- `CLAUDE.md` Quality standards: *"Observability — structured logs, error tracking, performance monitoring."*

These are **prescribed-only today** — the reference `server.ts` emits no structured logs. E5-log makes §3 **proven** on the reference app. This is the E-series thesis (*declaration → behaviour*) applied to the kit's own §3.

> **Authority note (harness-neutrality).** The justification is the kit's own committed docs (`DEVELOPMENT-STANDARDS.md` §3), which every adopter receives — **not** any maintainer-private, harness-loaded file. A kit feature must self-justify from the shipped product, never from maintainer context an adopter never sees.

## The change — `server.ts` (zero-dep structured request logging)

Add a structured logger + per-request wrapper to `profiles/typescript-node/scaffold/src/server.ts`:

- `import { randomUUID } from 'node:crypto';` (Node built-in — **no dependency**, consistent with the kit's zero-dep references `flags.ts` / `health.ts` / the security headers).
- A `log(fields)` helper: `console.log(JSON.stringify({ ts: ISO, level: 'info', service, ...fields }))` — one JSON line per event, machine-parseable (§3).
- Per request: capture `process.hrtime.bigint()` start; resolve `requestId` (honor an incoming `x-request-id` header, else `randomUUID()` — seeds E5-trace correlation later); on `res.on('finish')` emit `{ requestId, method, path, status, latencyMs }`.
- **Never logs** bodies/headers/PII/secrets (§2 + §3) — only method/path/status/latency/requestId.
- `service` from `process.env.SERVICE_NAME ?? 'reference-app'`.

**Zero-dep, not pino** — production-grade structured logging is `JSON.stringify` to stdout; staying zero-dep honors the kit's dependency-justification standard and keeps the reference portable.

## The proof (behavioural + non-vacuous)

Mirror E4c (runtime-security) exactly — a static lock + a booted-app golden-path assertion:

1. **Golden-path behavioural assertion** (`.github/workflows/golden-path.yml`, in the existing Boot-1 block after `wait_live` has already issued `/healthz` requests): capture `docker logs gp`, isolate the structured request line (`grep -F '"requestId"' | tail -1`), and `jq -e` that it is valid JSON with **all** required fields — `requestId`, `method`, `path`, `status` (number), `latencyMs` (number), `level`, `service`, `ts`. Echo `structured-logging: OK`.
   - **Non-vacuity:** the old app emits no `"requestId"` line → RED; a logger missing a field → `jq -e` fails → RED. A dead app can't produce the line.
2. **Static conformance lock** `conformance/structured-logging-wired.sh` (claim `structured-logging`), mirroring `runtime-security.sh`:
   - `check_server`: `server.ts` emits the structured fields (greps stable tokens: `randomUUID`, `requestId`, `latencyMs`, `JSON.stringify`).
   - `check_wf`: golden-path carries the `structured-logging: OK` assertion + the field checks.
   - `--selftest`: good/bad fixtures for both (a server missing `latencyMs` → FAIL; a wf missing the assertion → FAIL) — load-bearing teeth.
   - Kit-self carve (export-ignored, mirrors `runtime-security.sh`'s `docs/ROADMAP-KIT.md` N/A guard).

## Right-weight call (owner-ratified)

A **new claim** `structured-logging` (registry +1), not overloading `runtime-security`. Justified: it is a distinct booted-app behavioural property (observability ≠ security headers), and it follows the kit's proven one-claim-per-capability pattern. Owner ratified the new claim over reuse.

## Honest ceiling

- Proves the structured-logging FLOOR on the **reference app only**; an adopter still selects their stack's logger — the kit ships the **pattern + the proof it works**, not a universal logging framework.
- **INFO-level request logging** only; ERROR/WARN/DEBUG per-event are the adopter's choice (the standard names the levels; this slice proves the request-log floor).
- No log shipping/retention/aggregation (infra, not this slice). No app-level tracing/metrics (E5-trace / E5-metrics).
- **`path` query-string redaction (folded from security review Low).** The logged `path` is the full `req.url` including any query string. The reference app's routes carry no query secrets, but an adopter whose query params can carry tokens/PII must redact `path` before logging — stated in the `server.ts` logger comment so the adopter sees it at the code site.
- Behavioural truth (the app actually emits the line) is proven on **CI docker** via golden-path — local green ≠ docker green (the kit's standing lesson); the conformance `--selftest` is the local red→green for the lock's teeth.

## Scope & build model — AMBER

Files: `server.ts` (scaffold) · `.github/workflows/golden-path.yml` · `conformance/structured-logging-wired.sh` (new) · `conformance/claims.tsv` (+1) · plus version finishing (`VERSION` 3.69.0→3.70.0, `README` badge, `CHANGELOG`). All control-plane edits + the scaffold edit folded into one idempotent `apply.py`, clone-proven, human-applied. Built test-first (conformance `--selftest` red→green), dual-reviewed (Reviewer + Security — Security to confirm no PII/secret in the log fields + requestId header handling is injection-safe in the NDJSON line).
