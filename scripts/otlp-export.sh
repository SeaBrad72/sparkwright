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
# build_header_config HEADERS_STR OUTFILE
#   Writes curl config lines "header = "k: v"" (one per k=v pair) to OUTFILE.
#   Parsing is done entirely in shell with IFS=','; values are written verbatim
#   as quoted strings inside the curl config file — never passed as argv to
#   curl, so there is no shell word-split injection and no ps/argv exposure of
#   auth tokens.
#
#   Security: rejects any pair whose key or value contains a double-quote (")
#   or a newline, and any pair with an empty key. Either character would allow
#   an attacker-controlled OTEL_EXPORTER_OTLP_HEADERS value to break out of
#   the "header = "..." line and inject arbitrary curl config directives
#   (e.g. output = "/tmp/pwned"). We fail-closed (exit 2) rather than attempt
#   escaping — escaping curl config syntax is error-prone and untestable at
#   every curl version. The value is NOT echoed to stderr to avoid leaking
#   auth secrets in logs.
# ---------------------------------------------------------------------------
build_header_config() {
  _h_str="$1"; _h_out="$2"
  OLDIFS=$IFS; IFS=','
  for _pair in $_h_str; do
    _key="${_pair%%=*}"
    _val="${_pair#*=}"
    # --- config-injection guard (fail-closed) ---
    [ -n "$_key" ] || { echo "otlp-export: refusing header with empty key (config-injection guard)" >&2; IFS=$OLDIFS; exit 2; }
    case "$_key$_val" in
      *'"'*) echo "otlp-export: refusing header containing a double-quote (config-injection guard)" >&2; IFS=$OLDIFS; exit 2 ;;
    esac
    # Detect embedded newline: printf adds a sentinel char after the value; if the
    # sentinel ends up on a second line after read, the value contains a newline.
    # (Command substitution strips trailing newlines, so we can't use $(...) directly.)
    _val_check=$(printf '%s|' "$_val")
    case "$_val_check" in
      *"
"*) echo "otlp-export: refusing header containing a newline (config-injection guard)" >&2; IFS=$OLDIFS; exit 2 ;;
    esac
    printf 'header = "%s: %s"\n' "$_key" "$_val" >> "$_h_out"
  done
  IFS=$OLDIFS
}

# ---------------------------------------------------------------------------
# selftest — validates OTLP envelope shape AND header injection safety; NO network.
# ---------------------------------------------------------------------------
selftest() {
  fix="$(dirname "$0")/fixtures/otel-trace-sample.ndjson"
  doc=$(to_otlp "$fix")
  st_fail=0

  # --- OTLP envelope shape ---
  [ "$(printf '%s' "$doc" | jq -e 'has("resourceSpans")')" = "true" ] || { echo "FAIL: no resourceSpans"; st_fail=1; }
  n=$(printf '%s' "$doc" | jq '[.resourceSpans[0].scopeSpans[0].spans[]]|length')
  [ "$n" = "4" ] || { echo "FAIL: expected 4 OTLP spans, got $n"; st_fail=1; }

  # --- OTLP camelCase keys + string nanos + KV-array attributes ---
  sp=$(printf '%s' "$doc" | jq '.resourceSpans[0].scopeSpans[0].spans[0]')
  for k in traceId spanId name startTimeUnixNano endTimeUnixNano attributes status; do
    [ "$(printf '%s' "$sp" | jq -e "has(\"$k\")")" = "true" ] || { echo "FAIL: OTLP key $k"; st_fail=1; }
  done
  [ "$(printf '%s' "$sp" | jq -r '.startTimeUnixNano|type')" = "string" ] || { echo "FAIL: nanos must be string in OTLP"; st_fail=1; }
  [ "$(printf '%s' "$sp" | jq -e '.attributes|type=="array"')" = "true" ] || { echo "FAIL: OTLP attributes must be KV array"; st_fail=1; }

  # --- status.code: must be numeric; ERROR span must be 2 ---
  [ "$(printf '%s' "$sp" | jq -r '.status.code|type')" = "number" ] || { echo "FAIL: status.code must be numeric"; st_fail=1; }
  # Span index 3 is gate:guard (ERROR); fixture has exactly one ERROR span.
  err_sp=$(printf '%s' "$doc" | jq '.resourceSpans[0].scopeSpans[0].spans[3]')
  err_code=$(printf '%s' "$err_sp" | jq '.status.code')
  [ "$err_code" = "2" ] || { echo "FAIL: ERROR span (gate:guard) must have status.code==2, got $err_code"; st_fail=1; }

  # --- Injection-safety: benign flag-like-token value must be ACCEPTED (not over-broad) ---
  # A value containing spaces/flags (e.g. "--output /tmp/pwned") has NO double-quote
  # and NO newline, so it must be confined to a single "header = ..." line — not split.
  _inj_tmp=$(mktemp)
  chmod 600 "$_inj_tmp"
  build_header_config 'x-api-key=abc --output /tmp/pwned' "$_inj_tmp"
  _inj_line=$(cat "$_inj_tmp")
  rm -f "$_inj_tmp"
  # Expected output: header = "x-api-key: abc --output /tmp/pwned"
  # The dangerous tokens must appear inside the quoted value, NOT as standalone curl flags.
  case "$_inj_line" in
    'header = "x-api-key: abc --output /tmp/pwned"')
      : ;;  # safe — entire value in quoted header line
    *)
      echo "FAIL: injection-safety: benign flag-like-token value not contained in quoted config line; got: $_inj_line"
      st_fail=1 ;;
  esac

  # --- Injection-safety: embedded double-quote must be REJECTED (config-injection guard) ---
  # A value like: abc"<newline>output = "/tmp/pwned breaks out of the quoted header line.
  # The guard must reject this with exit 2 BEFORE writing anything to the config file.
  # build_header_config calls exit 2 on rejection, so we invoke it in a subshell.
  _malicious=$(printf 'x-api-key=abc"\noutput = "/tmp/pwned')
  _inj_tmp2=$(mktemp)
  chmod 600 "$_inj_tmp2"
  if ( build_header_config "$_malicious" "$_inj_tmp2" ) 2>/dev/null; then
    echo "FAIL: injection-safety: malicious header with embedded quote was NOT rejected (should have exited non-zero)"
    st_fail=1
  else
    : # correctly rejected
  fi
  rm -f "$_inj_tmp2"

  [ "$st_fail" -eq 0 ] || { echo "otlp-export --selftest: FAIL" >&2; return 1; }
  echo "otlp-export --selftest: OK (valid OTLP/JSON envelope + injection-safety + status.code assertions; no network)"
  return 0
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
  # Headers carry vendor auth secrets (e.g. API keys). To prevent:
  #   (a) arg-injection: a header value containing spaces/flags is word-split into
  #       curl flags when passed via $_hdrs in argv (e.g. "abc --output /tmp/leak").
  #   (b) ps/argv exposure: header args in curl's argv are visible to `ps aux`.
  # Fix: write headers to a curl config file (chmod 600, mktemp). curl parses the
  # file itself — values are never shell-word-split and never appear in curl's argv.
  # The payload still flows via stdin (--data-binary @-); only the endpoint URL
  # remains in argv (it is not a secret).
  _cfg=$(mktemp)
  chmod 600 "$_cfg"
  # Trap ensures the temp file is removed even if curl fails.
  # shellcheck disable=SC2064  # intentional: $_cfg is expanded NOW to capture the value
  trap "rm -f '$_cfg'" EXIT

  printf 'silent\nshow-error\nrequest = POST\n' > "$_cfg"
  printf 'header = "Content-Type: application/json"\n' >> "$_cfg"
  printf 'data-binary = @-\n' >> "$_cfg"
  printf 'url = "%s"\n' "${OTEL_EXPORTER_OTLP_ENDPOINT%/}/v1/traces" >> "$_cfg"

  if [ -n "${OTEL_EXPORTER_OTLP_HEADERS:-}" ]; then
    build_header_config "$OTEL_EXPORTER_OTLP_HEADERS" "$_cfg"
  fi

  printf '%s' "$doc" | curl --config "$_cfg"
  rm -f "$_cfg"
  # Cancel trap after explicit cleanup so it doesn't fire again on normal exit.
  trap - EXIT
}

# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------
case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *)          main "$@" ;;
esac
