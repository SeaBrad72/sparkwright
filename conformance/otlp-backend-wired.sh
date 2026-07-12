#!/bin/sh
# otlp-backend-wired.sh — lock that the reference app's spans REACH a real OTLP backend: the golden-path
# `otlp-backend` job POSTs them via the existing scripts/otlp-export.sh REAL path (no --dry-run) to a real
# OpenTelemetry Collector and asserts receipt+decode of the exact emitted trace_id. STATIC (no docker); the
# live proof is the golden-path otlp-backend job. SCOPE: proves the reference round-trip is WIRED — NOT that
# an adopter's backend ingests (kit-self lock; carved from the adopter export, mirrors app-tracing). Basis:
# the kit's own zero-dep OTLP seam (scripts/otlp-export.sh) + the shipped reference collector config. Usage: [--selftest]
set -eu
ROOT="${OTLP_BACKEND_ROOT:-.}"
CONFIG="${OTLP_BACKEND_CONFIG:-$ROOT/profiles/typescript-node/scaffold/observability/otel-collector.yaml}"
WF="${GOLDEN_PATH_WF:-$ROOT/.github/workflows/golden-path.yml}"
# The collector config must declare an OTLP/HTTP receiver on :4318 and a traces pipeline to the debug exporter.
CONFIG_TOKENS="otlp 4318 debug traces"

check_config() {  # <otel-collector.yaml> — OTLP receiver + traces->debug pipeline
  f=$1; miss=0
  for t in $CONFIG_TOKENS; do
    grep -qF -- "$t" "$f" || { echo "FAIL: $f missing collector-config token: $t"; miss=1; }
  done
  return $miss
}

check_wf() {  # <golden-path.yml> — the otlp-backend job does a REAL POST + asserts receipt
  f=$1; miss=0
  # The exact real-POST invocation (no --dry-run on this line) — this single token IS the "real delivery" proof.
  # grep -qE with end-of-line anchor: 'gp_spans.ndjson --dry-run' does NOT match (extra content after token);
  # the actual golden-path line ends at gp_spans.ndjson so it DOES match. Escaped dots = literal dots.
  # NOTE: the job line must end at gp_spans.ndjson with no trailing comment or line-continuation split.
  grep -qE -- 'OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 sh scripts/otlp-export\.sh gp_spans\.ndjson[[:space:]]*$' "$f" \
    || { echo "FAIL: golden-path missing the real (non-dry-run) otlp-export POST"; miss=1; }
  for t in 'otlp-backend: OK' 'docker logs otelcol' 'otel/opentelemetry-collector'; do
    grep -qF -- "$t" "$f" || { echo "FAIL: golden-path missing otlp-backend assertion: $t"; miss=1; }
  done
  return $miss
}

if [ "${1:-}" = "--selftest" ]; then
  d=$(mktemp -d); sf=0
  printf 'receivers:\n  otlp:\n    protocols:\n      http:\n        endpoint: 0.0.0.0:4318\nexporters:\n  debug:\nservice:\n  pipelines:\n    traces:\n      receivers: [otlp]\n      exporters: [debug]\n' > "$d/cfg_ok.yml"
  printf 'exporters:\n  debug:\nservice:\n  pipelines:\n    traces: 4318\n' > "$d/cfg_bad.yml"   # missing the otlp receiver
  REAL='OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 sh scripts/otlp-export.sh gp_spans.ndjson'
  printf '%s\notlp-backend: OK\ndocker logs otelcol\notel/opentelemetry-collector\n' "$REAL" > "$d/wf_ok.yml"
  printf '%s --dry-run\notlp-backend: OK\ndocker logs otelcol\notel/opentelemetry-collector\n' "$REAL" > "$d/wf_bad_dry.yml"  # POST is dry-run, not real
  printf '%s\ndocker logs otelcol\notel/opentelemetry-collector\n' "$REAL" > "$d/wf_bad_assert.yml"   # missing 'otlp-backend: OK'
  if check_config "$d/cfg_ok.yml"  >/dev/null 2>&1; then echo "selftest PASS: config all tokens -> PASS"; else echo "selftest FAIL: cfg_ok wrongly failed"; sf=1; fi
  if check_config "$d/cfg_bad.yml" >/dev/null 2>&1; then echo "selftest FAIL: missing otlp receiver NOT caught"; sf=1; else echo "selftest PASS: missing receiver -> FAIL"; fi
  if check_wf "$d/wf_ok.yml"        >/dev/null 2>&1; then echo "selftest PASS: wf real-POST -> PASS"; else echo "selftest FAIL: wf_ok wrongly failed"; sf=1; fi
  if check_wf "$d/wf_bad_dry.yml"   >/dev/null 2>&1; then echo "selftest FAIL: dry-run POST NOT caught"; sf=1; else echo "selftest PASS: dry-run POST -> FAIL"; fi
  if check_wf "$d/wf_bad_assert.yml" >/dev/null 2>&1; then echo "selftest FAIL: missing receipt assertion NOT caught"; sf=1; else echo "selftest PASS: missing assertion -> FAIL"; fi
  [ "$sf" -eq 0 ] && { echo "OK: otlp-backend selftest"; exit 0; } || { echo "FAIL: otlp-backend selftest"; exit 1; }
fi

case "${1:-}" in "") : ;; *) echo "usage: otlp-backend-wired.sh [--selftest]" >&2; exit 2 ;; esac

# Kit-self (mirrors app-tracing): verifies the kit's OWN golden-path round-trip. On an adopter tree the
# golden-path workflow is export-ignored/stripped → nothing to verify → N/A. Fail-closed on the kit:
# ROADMAP-KIT.md remains even if golden-path is deleted, so the [ -f "$WF" ] check below still FAILs.
if [ ! -f "$ROOT/docs/ROADMAP-KIT.md" ] && [ ! -f "$WF" ]; then echo "otlp-backend: N/A — kit-self check (not applicable outside the kit repo)"; exit 0; fi
fail=0
[ -f "$CONFIG" ] || { echo "FAIL: reference collector config not found: $CONFIG"; fail=1; }
[ -f "$WF" ]     || { echo "FAIL: golden-path workflow not found: $WF"; fail=1; }
[ "$fail" = 0 ] && { check_config "$CONFIG" || fail=1; check_wf "$WF" || fail=1; }
[ "$fail" = 0 ] && { echo "OK: reference collector config ships + golden-path proves a real OTLP round-trip"; exit 0; }
echo "FAIL: otlp-backend under-wired"; exit 1
