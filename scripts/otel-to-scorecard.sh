#!/bin/sh
# otel-to-scorecard.sh — adapter: OTel NDJSON spans -> MP-3a records for agent-scorecard.sh.
# Each CHILD span (parent_span_id != null) becomes one per-agent run record. The
# proven scorecard is UNCHANGED; this script is the documented OTel->scorecard mapping.
#
# Owner-decided mapping (spec §7):
#   run-level .outcome : status.code=="ERROR" -> "error", else "ok"
#   step .outcome      : kit.denied=="true"   -> "denied"; else mirror run outcome
#   retries            : attributes.retries (default 0)
#   review.rounds      : attributes["review.rounds"] (default 0)
#
# Usage:
#   scripts/otel-to-scorecard.sh TRACE.ndjson   # prints records array to stdout
#   scripts/otel-to-scorecard.sh --selftest
# sh + jq. No JSON hand-built. Zero deps beyond sh and jq.
# What it changes: Read-only — maps OTel NDJSON spans to MP-3a records on stdout; mutates nothing.
# Guardrails: All JSON is built by jq (no hand-built/interpolated JSON); zero deps beyond sh + jq; a documented mapping, not a gate.
set -eu

# map_trace FILE -> prints a JSON array of MP-3a records (one per child span)
map_trace() {
  # ── ★ Owner decision point (spec §7): status.code + kit.denied -> MP-3a outcome ──
  # default mapping:
  #   run-level .outcome : ERROR -> "error", else "ok"
  #   step .outcome      : kit.denied==true -> "denied"; else mirror run outcome
  # start/end are stringified nanos (19-digit). Lexical sort == numeric sort at exactly 19 digits,
  # so the scorecard sort_by(.start) is safe. E3a should keep nanos numeric/19-digit to stay sort-safe.
  jq -s '
    [ .[] | select(.parent_span_id != null)
      | (.attributes["kit.denied"] == "true") as $denied
      | (if .["status"].code == "ERROR" then "error" else "ok" end) as $run
      | {
          "agent.id": (.attributes["agent.id"] // "unknown"),
          "run.id": .span_id,
          start: (.start_unix_nano | tostring),
          end: (.end_unix_nano | tostring),
          outcome: $run,
          "review.rounds": ((.attributes["review.rounds"] // "0") | tonumber? // 0),
          steps: [ { outcome: (if $denied then "denied" else $run end),
                     retries: ((.attributes.retries // "0") | tonumber? // 0) } ]
        }
      # exclude-unknown: merge .cost / .["eval.score"] ONLY when the attribute is present and numeric.
      # Omit the key entirely when absent — never default to 0 (honesty rule, agent-scorecard.sh).
      + (if (.attributes["gen_ai.usage.cost"] | (. != null and (tonumber? != null)))
           then {cost: (.attributes["gen_ai.usage.cost"] | tonumber)} else {} end)
      + (if (.attributes["eval.score"] | (. != null and (tonumber? != null)))
           then {"eval.score": (.attributes["eval.score"] | tonumber)} else {} end)
      ]' "$1"
}

selftest() {
  fix="$(dirname "$0")/fixtures/otel-trace-sample.ndjson"
  out=$(map_trace "$fix")
  st_fail=0
  # child spans only (root excluded): 3 records
  [ "$(printf '%s' "$out" | jq 'length')" = "3" ] || { echo "FAIL: expected 3 records"; st_fail=1; }
  # the denied span -> a record whose steps carry outcome "denied"
  [ "$(printf '%s' "$out" | jq '[.[]|select(.steps[].outcome=="denied")]|length')" -ge 1 ] || { echo "FAIL: denied not mapped"; st_fail=1; }
  # every record has the scorecard's required fields
  for k in '"agent.id"' '"outcome"' '"steps"' '"start"'; do
    [ "$(printf '%s' "$out" | jq "all(has($k))")" = "true" ] || { echo "FAIL: missing $k"; st_fail=1; }
  done
  # exclude-unknown mapping: a span carrying gen_ai.usage.cost / eval.score -> record has .cost + .["eval.score"];
  # a span WITHOUT those attributes OMITS the keys entirely (never coerced to 0).
  [ "$(printf '%s' "$out" | jq '[.[]|select((.cost|type=="number") and (.["eval.score"]|type=="number"))]|length')" -ge 1 ] \
      || { echo "FAIL: cost/eval.score not mapped when present"; st_fail=1; }
  [ "$(printf '%s' "$out" | jq '[.[]|select((has("cost")|not) and (has("eval.score")|not))]|length')" -ge 1 ] \
      || { echo "FAIL: cost/eval.score not omitted when absent (exclude-unknown violated)"; st_fail=1; }
  # (the REAL scorecard end-to-end proof lives in Step 4, not the selftest)
  [ "$st_fail" -eq 0 ] || { echo "otel-to-scorecard --selftest: FAIL" >&2; return 1; }
  echo "otel-to-scorecard --selftest: OK (3 child records, denied mapped, required fields, cost/eval exclude-unknown)"; return 0
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  -*|"") printf 'usage: otel-to-scorecard.sh TRACE.ndjson  # prints records array to stdout\n' >&2; exit 2 ;;
  *) map_trace "$1" ;;
esac
