#!/bin/sh
# model-tiering-legible.sh — KW20(b) Slice 3 (A): the resolved MODEL tier is LEGIBLE — each agent's
# tier is stamped on the OTel run trace (orchestrator-run.sh) and surfaces through the scorecard
# mapping (otel-to-scorecard.sh) into the per-agent record.
#
# SCOPE — a green run proves the tier is CARRIED on the span and RENDERED into the record; it does
# NOT prove any subagent actually ran at that tier (NATIVE, Slice 2b / un-gateable). Necessary, not
# sufficient. The proof is a mixed-tier trace in -> mixed tiers out, with two load-bearing negatives.
# What it changes: read-only — builds throwaway fixture traces in mktemp files and maps them; mutates no tracked file.
# Guardrails: read-only against the tree; fixtures + the stripped-mapping copy live in temp files only;
#   non-vacuity teeth (liveness + strip-the-mapping) make the assertion load-bearing, not always-true.
# Usage: sh conformance/model-tiering-legible.sh [--selftest]
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPTS="$ROOT/scripts"

# build_trace FILE TIER1 TIER2 — a root orchestrator span + two agent:engineer children carrying
# model.tier=TIER1 / model.tier=TIER2 (only child spans become scorecard records).
build_trace() {
  _f="$1"; _t1="$2"; _t2="$3"; printf '' > "$_f"
  _tid=$(sh "$SCRIPTS/otel-trace.sh" new-trace)
  _root=$(sh "$SCRIPTS/otel-trace.sh" span --trace "$_tid" --name "orchestrator-run" --status OK \
            --sink "$_f" --attr "agent.id=orchestrator")
  sh "$SCRIPTS/otel-trace.sh" span --trace "$_tid" --parent "$_root" --name "agent:engineer" --status OK \
     --sink "$_f" --attr "agent.id=engineer" --attr "slice=alpha" --attr "model.tier=$_t1" >/dev/null
  sh "$SCRIPTS/otel-trace.sh" span --trace "$_tid" --parent "$_root" --name "agent:engineer" --status OK \
     --sink "$_f" --attr "agent.id=engineer" --attr "slice=beta" --attr "model.tier=$_t2" >/dev/null
}

tiers_seen() { printf '%s' "$1" | jq -r '[.[]["model.tier"]] | unique | join(",")' 2>/dev/null || echo "?"; }

# has_both RECORDS T1 T2 -> 0 iff BOTH tiers appear as a .["model.tier"] across the records.
has_both() {
  printf '%s' "$1" | jq -e --arg a "$2" --arg b "$3" \
    'any(.[]; .["model.tier"]==$a) and any(.[]; .["model.tier"]==$b)' >/dev/null 2>&1
}

# run_check — the positive lock: a mixed (deep,fast) trace, mapped by the REAL otel-to-scorecard.sh,
# must render BOTH tiers into the records. FAILS on the current tree (mapping not present yet -> unknown).
run_check() {
  _tr=$(mktemp); build_trace "$_tr" deep fast
  _recs=$(sh "$SCRIPTS/otel-to-scorecard.sh" "$_tr"); rm -f "$_tr"
  if has_both "$_recs" deep fast; then
    echo "PASS: mixed-tier trace renders both tiers (deep, fast) in the scorecard records"; return 0
  else
    echo "FAIL: model.tier not surfaced in scorecard records (tiers seen: $(tiers_seen "$_recs"))"; return 1
  fi
}

selftest() {
  fail=0
  tr=$(mktemp); build_trace "$tr" deep fast
  recs=$(sh "$SCRIPTS/otel-to-scorecard.sh" "$tr")
  # POSITIVE: mixed-in -> mixed-out.
  if has_both "$recs" deep fast; then echo "PASS: positive — mixed tiers surface in the records"
  else echo "FAIL: positive — mixed tiers not surfaced (tiers seen: $(tiers_seen "$recs"))"; fail=1; fi

  # NEGATIVE (a) LIVENESS: a single-constant-tier trace must NOT satisfy the mixed (deep AND fast)
  # assertion — proves the assertion is live, not vacuously always-true.
  trc=$(mktemp); build_trace "$trc" deep deep
  recsc=$(sh "$SCRIPTS/otel-to-scorecard.sh" "$trc")
  if has_both "$recsc" deep fast; then
    echo "FAIL: liveness — a constant-tier (deep,deep) trace wrongly satisfied the mixed assertion"; fail=1
  else echo "PASS: liveness — a constant-tier trace does not satisfy the mixed assertion"; fi

  # NEGATIVE (b) LOAD-BEARING: strip the model.tier mapping from otel-to-scorecard.sh -> the tiers
  # collapse to "unknown" -> the mixed assertion must FAIL. Proves the check depends on the mapping.
  stripped=$(mktemp)
  grep -vF '.attributes["model.tier"]' "$SCRIPTS/otel-to-scorecard.sh" > "$stripped"
  recss=$(sh "$stripped" "$tr")
  if has_both "$recss" deep fast; then
    echo "FAIL: non-vacuity — stripping the model.tier mapping still surfaced both tiers (assertion not load-bearing)"; fail=1
  else echo "PASS: non-vacuity — stripping the model.tier mapping makes the tiers vanish (RED)"; fi

  rm -f "$tr" "$trc" "$stripped"
  [ "$fail" -eq 0 ] && { echo "model-tiering-legible --selftest: OK (mixed in->out; liveness; strip-mapping non-vacuity)"; exit 0; } \
                    || { echo "model-tiering-legible --selftest: FAIL" >&2; exit 1; }
}

case "${1:-}" in
  --selftest) selftest ;;
  *) if run_check; then echo "model-tiering-legible: OK"; else echo "model-tiering-legible: FAIL"; exit 1; fi ;;
esac
