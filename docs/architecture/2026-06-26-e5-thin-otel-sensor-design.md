# E5-thin — OTel-shaped orchestrator trace → one real scorecard (design)

**Status:** Design ratified (brainstorm, 2026-06-26). Next: implementation plan.
**Slice:** E5-thin — the second of the two thin inputs (E1-thin ✅ v3.50.0 / E5-thin) that lead E3, per meta-control panel #4 (`docs/architecture/2026-06-26-meta-control-4.md`).
**Target version:** 3.51.0 (MINOR — feature slice).

---

## 1. Why this slice exists

Panel #4 ratified that **E3 is the spine, led by the thin inputs it consumes**: E1 is the *oracle* (does a run pass?) and E5 is the *sensor* (what did a run do?). Building E1/E5 *through* E3 would invert that dependency — the F5 "build-ahead-of-need" error one level up. E1-thin shipped the oracle (v3.50.0). **E5-thin is the matching sensor, and the last input gate before E3a can start.**

### What already exists (the honest starting point)

The operate-loop has three reference scripts:

- `scripts/agent-trace.sh` — parses a finished Claude-Code JSONL transcript into a custom **MP-3a** schema (one **flat** trace per agent run, post-hoc, harness-specific).
- `scripts/agent-scorecard.sh` — scores MP-3a traces, classifies each agent vs its own trailing baseline, emits autonomy-tier directives. **Proven (`--selftest`); used by `tier-advice.sh`.**
- `scripts/tier-advice.sh` — renders the decision view over the scorecard.

Two honest gaps remain (panel #4 V1b CONFIRMED):

1. **The trace is post-hoc and flat.** It is not emitted at runtime and not OTel-shaped — no nested span tree. E3's orchestrator fans out *N agents within a phase*; that is a trace-with-child-spans, precisely OTel's data model.
2. **No real run has ever closed the loop.** `traces/` and `scorecards/` are empty; the scorecard has only ever scored a fixture.

## 2. Goal & scope

Close the sensor loop on **real, non-fixture data for the first time**, in the span shape E3a will emit into, **with a real enterprise-integration seam**.

One reference orchestrator run **emits** an OTel-shaped trace → adapter → the **unchanged** scorecard produces one real scorecard → proven end-to-end in CI. The same emitted trace can **export to any OTLP-compatible backend** through an opt-in reference exporter.

### Explicitly NOT in this slice

Owned by E5-full / E3 / E6:

- Live OTLP export proven against a **vendor backend** (we prove *valid OTLP is produced and POSTed*; the adopter supplies the endpoint + auth).
- App-level request tracing — `server.ts` stays `/healthz`-only (E5-full).
- The **real** orchestrator loop — we ship a **labelled stand-in**; E3a replaces its body.
- Regression **classification** — one run stays `steady` / no directive (needs ≥5 runs; fail-safe by design).

## 3. The cross-cutting principle this slice establishes

**Integration-capability / no-dead-ends lens** (banked as a standing review lens, alongside progressive-disclosure):

> Any kit feature that touches an industry standard (OTel traces here; SBOM/SARIF/provenance/SLSA already; DORA/cost-gov candidates) must ship a **real, documented export/integration seam to enterprise platforms** — not a self-contained demo.

The OTel emitter is the live test of this lens. The architecture realises it via a **pluggable sink**: the same NDJSON trace feeds two consumers off one seam — the kit-internal scorecard *and* the enterprise OTLP exporter. E3a later emits **once**, and both the kit's autonomy-tier feedback loop and the adopter's observability backend light up from the same emission — no duplicate instrumentation.

## 4. Architecture & components

| Piece | Status | Single purpose |
|-------|--------|----------------|
| `scripts/otel-trace.sh` | **new** | Zero-dep OTel-shaped span emitter with a **pluggable sink** (default: NDJSON file). Span lifecycle verbs append one span per line. `--selftest`. The runtime emission primitive E3a calls. |
| `scripts/orchestrator-trace-demo.sh` | **new** | The **labelled stand-in**: a tiny reference run emitting a root span + ~3 child agent/gate spans via `otel-trace.sh`. The thing E3a replaces. Runnable reference (not buried in CI YAML). |
| `scripts/otel-to-scorecard.sh` | **new** | Thin **adapter**: flattens the OTel trace's child spans → the MP-3a per-agent records `agent-scorecard.sh` already consumes. `--selftest`. Doubles as the documented OTel→scorecard mapping. |
| `scripts/otlp-export.sh` | **new (opt-in)** | Reference **exporter**: NDJSON spans → schema-valid OTLP/JSON `resourceSpans` envelope → POST `$OTEL_EXPORTER_OTLP_ENDPOINT`. `--selftest` asserts **valid OTLP** without a live collector. |
| `scripts/agent-scorecard.sh` | **unchanged** | Proven scoring logic stays untouched (the reason the adapter exists). |
| `conformance/agentops-sensor-wired.sh` | **new (control-plane)** | Behaviour lock: emitter + adapter + exporter `--selftest`s pass AND the golden-path emit→score job is wired. New claim `agentops-sensor`. |
| `docs/operations/agentic-ops.md` | **extended** | Integration section: the enterprise path + standard OTel env vars. |

### Isolation check (each unit, independently understandable)

- **otel-trace.sh** — *does:* emit OTel spans to a sink. *used by:* the stand-in (and E3a later). *depends on:* sh + jq + a portable nano/id helper.
- **orchestrator-trace-demo.sh** — *does:* produce one representative orchestrator trace. *used by:* the golden-path proof. *depends on:* otel-trace.sh.
- **otel-to-scorecard.sh** — *does:* map OTel spans → MP-3a records. *used by:* the golden-path proof + adopters. *depends on:* the OTel span shape only.
- **otlp-export.sh** — *does:* turn the NDJSON trace into OTLP/JSON and POST it. *used by:* enterprise adopters (opt-in). *depends on:* the OTel span shape + curl + an endpoint.

## 5. The span shape (resolved: OTel-semantic, kit NDJSON envelope)

One span per NDJSON line:

```json
{"trace_id":"…","span_id":"…","parent_span_id":null,"name":"orchestrator-run",
 "start_unix_nano":…,"end_unix_nano":…,
 "attributes":{"agent.id":"engineer","steps":4},"status":{"code":"OK"}}
```

Fields map **1:1 to OTLP** so the exporter (and a future E5-full live integration) wraps them without reshaping the emitter. Honest claim = **OTel-shaped**, not "OTLP-exporting from the core" (export is the opt-in branch).

**Known implementation detail for the plan:** nanosecond timestamps + random trace/span IDs must be **portable** — macOS `date` has no `%N`, and `/dev/urandom` via `od` is the portable id source. Resolve with a small helper (prefer `date +%s%N`; fall back to `seconds × 1e9` when `%N` is unsupported). Flagged now so it is not a build surprise.

## 6. Data flow

```
orchestrator-trace-demo.sh   (the stand-in — E3a replaces this)
   │  calls otel-trace.sh span verbs (pluggable sink)
   ▼
traces/<run>.ndjson          ← OTel-shaped spans, one per line
   │
   ├─ (default) otel-to-scorecard.sh ─▶ MP-3a records ─▶ agent-scorecard.sh (UNCHANGED) ─▶ scorecards/<window>.json   [proven core]
   │
   └─ (opt-in) otlp-export.sh ─▶ OTLP/JSON resourceSpans ─▶ POST $OTEL_EXPORTER_OTLP_ENDPOINT ─▶ Datadog / Honeycomb / Tempo / Jaeger / Collector
```

## 7. The genuine semantic choice (build-time, owner's hand on the design)

The **adapter's span→record mapping rules** are the real design decision in this slice, to be written during build (~5–10 lines):

- How `status.code` maps to MP-3a `outcome`: `OK → ok`, `ERROR → error`, and **what signals `denied`** (a guard-denial is behaviourally distinct from an error and drives the scorecard's `denial_rate`). Candidate: a span attribute `denied:true` or a status convention — to be chosen at build.
- Whether nested sub-spans become `steps` (or `steps` stays an attribute on the agent span for the thin slice).

This is deliberately left for Bradley to shape rather than decided silently.

## 8. Conformance & behaviour proof

**Behaviour proof — a new `agentops-sensor` job in `.github/workflows/golden-path.yml`:** run the stand-in → `otel-to-scorecard.sh` → `agent-scorecard.sh`, then assert the scorecard's metrics are **derived from the emitted spans** (non-vacuous). Concretely: the stand-in emits one `denied` span, and the assertion checks the scorecard's `denial_rate` reflects it — a dead emitter cannot produce that number. Mirrors the `runtime-security` / `image-vuln` non-vacuous idiom.

**Control-plane lock — `conformance/agentops-sensor-wired.sh`** (new claim `agentops-sensor`, registered in `conformance/claims.tsv`): asserts the three `--selftest`s pass (emitter / adapter / exporter), the scripts exist and are executable, and the golden-path job is present and runs the emit→score loop. Wired into `verify.sh` (`--require`), `ci.yml`, `drift-watch`, and `doctor`. Mirrors `golden-path-wired` / `runtime-security`.

> Distinct from the existing **`agentops-ready`** doc-check (posture). New `agentops-sensor` is **behaviour** ("the sensor ran on real data"). Declaration vs behaviour, kept honestly separate — the same split as `test-layers-ready` (presence) vs `feature-flags-wired` (behaviour).

## 9. Honest ceiling (what is / is NOT proven)

**Proven:** OTel-shaped span emission runs; a real (non-fixture) trace is produced by a reference orchestrator run; the adapter maps it; the unchanged scorecard computes real metrics from it; the loop runs end-to-end in CI; the exporter produces **valid OTLP** and POSTs it.

**Not proven / out of scope:** no assertion against a **live vendor backend** (adopter's endpoint + auth); the orchestrator is a **labelled stand-in** (E3a wires the real fan-out); classification needs ≥5 runs so `tier-advice` stays `steady`/no-directive on one trace (fail-safe); this is the **agent-ops** sensor, not app-level OTel (E5-full); the app scaffold stays `/healthz`-only.

This is the kit's established **FLOOR + opt-in NATIVE binding** pattern (mirrors E4c's opt-in OWASP ZAP reference, E4e's FLOOR+NATIVE SoD).

## 10. Release mechanics — with the durable process fix

**AMBER slice** (the conformance lock is control-plane → the guard blocks shell edits → built in scratchpad, dry-run on a clone, Bradley applies via `apply.py`).

**★ This is the first slice where `apply.py` also performs the version finishing** (per `[[release-finishing-in-apply-py]]` — the VERSION bump has been skipped 3× : v3.49.0 / .1 / 3.50.0, each costing a fix-forward + tag-move). `apply.py` will, in addition to materialising the control-plane files:

- bump `VERSION` 3.50.0 → **3.51.0**,
- update the README version badge,
- prepend the CHANGELOG entry (agent drafts the text),
- update `docs/ROADMAP-KIT.md` (mark E5-thin done; advance "NEXT" to E3a).

So the human handoff becomes: `python3 apply.py` → commit → push → PR → (CI green) → merge → tag. **No separate finishing step to skip a 4th time.** Recovery runbook kept handy: `git tag -d vX && git push origin :refs/tags/vX && git tag -a vX -m "…" && git push origin vX`.

## 11. Testing & review

- `otel-trace.sh --selftest` — emits known spans; asserts OTel field shape + `parent_span_id` linkage + sink output.
- `otel-to-scorecard.sh --selftest` — known OTel trace → expected MP-3a records (incl. the `denied` mapping).
- `otlp-export.sh --selftest` — known trace → schema-valid OTLP/JSON envelope (no live collector).
- `agent-scorecard.sh --selftest` — unchanged; proves **no regression** in the proven scorer.
- golden-path `agentops-sensor` job — the real emit→score loop, non-vacuous metric assertion.

**Dual review** (builder ≠ reviewer + security-reviewer). Security themes:

- **Filename path-safety** on `run.id` / span names written to `traces/` (mirror `agent-trace.sh`'s `tr -c 'A-Za-z0-9._-' '_'` slug).
- **JSON built by jq, never hand-built** — untrusted attribute values can't break the envelope.
- **Exporter:** `$OTEL_EXPORTER_OTLP_ENDPOINT` / `$OTEL_EXPORTER_OTLP_HEADERS` handled safely (no header/log injection; secrets not echoed).

## 12. Summary

E5-thin closes the operate-loop on real data for the first time, in the OTel-shaped span-tree form E3a needs, with a real opt-in path to any OTLP backend — establishing the integration-capability lens for the whole kit. Thin-but-enterprise-real: one cohesive vertical (emit → score, export as a first-class branch off the same seam), built AMBER with the version-finishing folded into `apply.py`.
