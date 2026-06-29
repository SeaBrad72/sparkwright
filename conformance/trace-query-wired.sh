#!/bin/sh
# trace-query-wired.sh — lock that the reference app's spans are RETRIEVABLE from a real queryable backend:
# the golden-path `trace-query` job POSTs them via the existing scripts/otlp-export.sh REAL path (no
# --dry-run) to a real Jaeger backend and asserts the exact emitted trace_id is returned by Jaeger's query
# API (GET /api/traces/{id}). STATIC (no docker); the live proof is the golden-path trace-query job. SCOPE:
# proves the reference query round-trip is WIRED — NOT that an adopter's backend retrieves (kit-self lock;
# carved from the adopter export, mirrors otlp-backend). Basis: the kit's zero-dep OTLP seam
# (scripts/otlp-export.sh) + a real Jaeger query API. Usage: [--selftest]
set -eu
ROOT="${TRACE_QUERY_ROOT:-.}"
WF="${GOLDEN_PATH_WF:-$ROOT/.github/workflows/golden-path.yml}"

check_wf() {  # <golden-path.yml> — the trace-query job does a REAL POST + asserts query-API retrieval
  f=$1; miss=0
  # The exact real-POST invocation (no --dry-run on this line). grep -qE end-anchored: 'gp_spans.ndjson --dry-run'
  # does NOT match; the real job line ends at gp_spans.ndjson so it DOES. Escaped dots = literal. (grep -qF is
  # VACUOUS here — the real-POST token is a substring of the --dry-run line.)
  grep -qE -- 'OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 sh scripts/otlp-export\.sh gp_spans\.ndjson[[:space:]]*$' "$f" \
    || { echo "FAIL: golden-path missing the real (non-dry-run) otlp-export POST"; miss=1; }
  # /api/traces/ proves the QUERY round-trip (retrieval), not merely receipt — the discriminator vs otlp-backend.
  for t in 'trace-query: OK' '/api/traces/' 'jaegertracing/all-in-one'; do
    grep -qF -- "$t" "$f" || { echo "FAIL: golden-path missing trace-query assertion: $t"; miss=1; }
  done
  return $miss
}

if [ "${1:-}" = "--selftest" ]; then
  d=$(mktemp -d); sf=0
  REAL='OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 sh scripts/otlp-export.sh gp_spans.ndjson'
  printf '%s\ntrace-query: OK\n/api/traces/\njaegertracing/all-in-one\n' "$REAL" > "$d/wf_ok.yml"
  printf '%s --dry-run\ntrace-query: OK\n/api/traces/\njaegertracing/all-in-one\n' "$REAL" > "$d/wf_bad_dry.yml"  # POST is dry-run
  printf '%s\ntrace-query: OK\njaegertracing/all-in-one\n' "$REAL" > "$d/wf_bad_query.yml"   # missing /api/traces/ (no query proof)
  printf '%s\n/api/traces/\njaegertracing/all-in-one\n' "$REAL" > "$d/wf_bad_assert.yml"     # missing 'trace-query: OK'
  if check_wf "$d/wf_ok.yml"         >/dev/null 2>&1; then echo "selftest PASS: wf real-POST+query -> PASS"; else echo "selftest FAIL: wf_ok wrongly failed"; sf=1; fi
  if check_wf "$d/wf_bad_dry.yml"    >/dev/null 2>&1; then echo "selftest FAIL: dry-run POST NOT caught"; sf=1; else echo "selftest PASS: dry-run POST -> FAIL"; fi
  if check_wf "$d/wf_bad_query.yml"  >/dev/null 2>&1; then echo "selftest FAIL: missing query assertion NOT caught"; sf=1; else echo "selftest PASS: missing /api/traces/ -> FAIL"; fi
  if check_wf "$d/wf_bad_assert.yml" >/dev/null 2>&1; then echo "selftest FAIL: missing OK assertion NOT caught"; sf=1; else echo "selftest PASS: missing assertion -> FAIL"; fi
  [ "$sf" -eq 0 ] && { echo "OK: trace-query selftest"; exit 0; } || { echo "FAIL: trace-query selftest"; exit 1; }
fi

case "${1:-}" in "") : ;; *) echo "usage: trace-query-wired.sh [--selftest]" >&2; exit 2 ;; esac

# Kit-self (mirrors otlp-backend): verifies the kit's OWN golden-path round-trip. On an adopter tree the
# golden-path workflow is export-ignored/stripped -> nothing to verify -> N/A. Fail-closed on the kit:
# ROADMAP-KIT.md remains even if golden-path is deleted, so the [ -f "$WF" ] check below still FAILs.
if [ ! -f "$ROOT/docs/ROADMAP-KIT.md" ] && [ ! -f "$WF" ]; then echo "trace-query: N/A — kit-self check (not applicable outside the kit repo)"; exit 0; fi
fail=0
[ -f "$WF" ] || { echo "FAIL: golden-path workflow not found: $WF"; fail=1; }
[ "$fail" = 0 ] && { check_wf "$WF" || fail=1; }
[ "$fail" = 0 ] && { echo "OK: golden-path proves a real Jaeger query round-trip (trace retrievable by id)"; exit 0; }
echo "FAIL: trace-query under-wired"; exit 1
