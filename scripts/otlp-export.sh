#!/bin/sh
# otlp-export.sh — opt-in reference exporter: kit NDJSON spans -> OTLP/JSON ->
# POST $OTEL_EXPORTER_OTLP_ENDPOINT/v1/traces. Proves the integration is REAL;
# the live vendor backend (endpoint+auth) is the adopter's. sh + jq + curl.
#
# Usage:
#   scripts/otlp-export.sh TRACE.ndjson [--dry-run]
#   scripts/otlp-export.sh --selftest
#
# Env:
#   OTEL_EXPORTER_OTLP_ENDPOINT  — e.g. https://api.honeycomb.io (no path)
#   OTEL_EXPORTER_OTLP_HEADERS   — comma-separated "k=v,k=v" (never echoed)
set -eu

# ---------------------------------------------------------------------------
# to_otlp FILE -> OTLP/JSON resourceSpans document
#   camelCase keys, string nanos, KV-array attributes, numeric status code.
#   All JSON built by jq — no untrusted values ever interpolated into shell.
# ---------------------------------------------------------------------------
to_otlp() {
  jq -s '
    def kv: to_entries | map({key:.key, value:{stringValue:(.value|tostring)}});
    { resourceSpans: [ {
        resource: { attributes: [ {key:"service.name", value:{stringValue:"sparkwright"}} ] },
        scopeSpans: [ {
          scope: { name: "sparkwright.agentops" },
          spans: [ .[] | {
            traceId: .trace_id, spanId: .span_id,
            parentSpanId: (.parent_span_id // ""),
            name: .name,
            startTimeUnixNano: (.start_unix_nano|tostring),
            endTimeUnixNano: (.end_unix_nano|tostring),
            attributes: (.attributes | kv),
            status: { code: (if .["status"].code=="ERROR" then 2 else 1 end) }
          } ]
        } ]
      } ] }' "$1"
}

# ---------------------------------------------------------------------------
# selftest — validates OTLP envelope shape; NO network.
# ---------------------------------------------------------------------------
selftest() {
  fix="$(dirname "$0")/fixtures/otel-trace-sample.ndjson"
  doc=$(to_otlp "$fix")
  st_fail=0
  # OTLP envelope shape
  [ "$(printf '%s' "$doc" | jq -e 'has("resourceSpans")')" = "true" ] || { echo "FAIL: no resourceSpans"; st_fail=1; }
  n=$(printf '%s' "$doc" | jq '[.resourceSpans[0].scopeSpans[0].spans[]]|length')
  [ "$n" = "4" ] || { echo "FAIL: expected 4 OTLP spans, got $n"; st_fail=1; }
  # OTLP camelCase keys + string nanos + KV-array attributes
  sp=$(printf '%s' "$doc" | jq '.resourceSpans[0].scopeSpans[0].spans[0]')
  for k in traceId spanId name startTimeUnixNano endTimeUnixNano attributes status; do
    [ "$(printf '%s' "$sp" | jq -e "has(\"$k\")")" = "true" ] || { echo "FAIL: OTLP key $k"; st_fail=1; }
  done
  [ "$(printf '%s' "$sp" | jq -r '.startTimeUnixNano|type')" = "string" ] || { echo "FAIL: nanos must be string in OTLP"; st_fail=1; }
  [ "$(printf '%s' "$sp" | jq -e '.attributes|type=="array"')" = "true" ] || { echo "FAIL: OTLP attributes must be KV array"; st_fail=1; }
  [ "$st_fail" -eq 0 ] || { echo "otlp-export --selftest: FAIL" >&2; return 1; }
  echo "otlp-export --selftest: OK (valid OTLP/JSON envelope; no network)"; return 0
}

# ---------------------------------------------------------------------------
# main — parse args, build doc, dry-run or POST
# ---------------------------------------------------------------------------
main() {
  DRY=0; TRACE=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) DRY=1; shift ;;
      -*)        echo "unknown flag $1" >&2; exit 2 ;;
      *)         TRACE="$1"; shift ;;
    esac
  done
  [ -n "$TRACE" ] || { echo "usage: otlp-export.sh TRACE.ndjson [--dry-run]" >&2; exit 2; }
  [ -f "$TRACE" ] || { echo "otlp-export: file not found: $TRACE" >&2; exit 2; }

  doc=$(to_otlp "$TRACE")

  if [ "$DRY" -eq 1 ] || [ -z "${OTEL_EXPORTER_OTLP_ENDPOINT:-}" ]; then
    printf '%s\n' "$doc"
    [ -z "${OTEL_EXPORTER_OTLP_ENDPOINT:-}" ] && \
      echo "otlp-export: no \$OTEL_EXPORTER_OTLP_ENDPOINT — printed payload, did not POST" >&2
    return 0
  fi

  # opt-in POST — parse headers from $OTEL_EXPORTER_OTLP_HEADERS ("k=v,k=v").
  # Headers carry vendor auth secrets; we build curl -H args but never echo them.
  _hdrs=""
  if [ -n "${OTEL_EXPORTER_OTLP_HEADERS:-}" ]; then
    OLDIFS=$IFS; IFS=',';
    for h in $OTEL_EXPORTER_OTLP_HEADERS; do
      _hdrs="$_hdrs -H ${h%%=*}:${h#*=}"
    done
    IFS=$OLDIFS
  fi

  # Payload flows via stdin to curl — never an argument (prevents shell history/ps leaks).
  # SC2086: _hdrs is intentionally word-split into separate -H args (no quoting by design).
  # shellcheck disable=SC2086
  printf '%s' "$doc" | curl -sS -X POST \
    -H 'Content-Type: application/json' \
    $_hdrs \
    --data-binary @- \
    "${OTEL_EXPORTER_OTLP_ENDPOINT%/}/v1/traces"
}

# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------
case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *)          main "$@" ;;
esac
