#!/bin/sh
# tier-value.sh — the VALUE ANALYSIS MODEL for model-tiering (KW20(b) Slice 3 B).
# Reads an OTel run trace (NDJSON spans from orchestrator-run.sh) and DECOMPOSES the economics of fanning
# out to cheaper builders — in RELATIVE deep-equivalent units (NOT dollars, no live rate lookup). Per child
# span: cost = tokens × WEIGHT_<tier>, tier from attributes["model.tier"] (default deep), weight from
# .kit/budget.conf (default 1.0). BUILDER cost = agent:engineer/agent:explorer spans; REASSEMBLY cost =
# agent.id=orchestrator spans (gate:integration, synthesis). Baseline = the same tokens all priced at
# WEIGHT_DEEP. Reports, as SEPARATE figures: the BUILDER TIER-DISCOUNT (builder-side saving from cheaper
# tiers), the REASSEMBLY TAX, a crude WITHIN-TRACE NET (builder_discount − reassembly_cost, which goes
# NEGATIVE when the tax exceeds the discount), plus speed (Σ wall-clock) and a quality-proxy
# (Σ review.rounds + retries + conflicts), and a one-line verdict.
#
# HONEST CEILING: proves the value analysis is COMPUTED non-vacuously over a trace. It does NOT prove the
# actual token numbers (NATIVE — a real Workflow run supplies them via the span `tokens` attr) nor that
# the quality-proxy IS quality (rework is a proxy). Crucially it does NOT emit a TRUE net-of-tax verdict:
# because the orchestrator's reassembly spans are always `deep`, they cancel out of baseline−total, so the
# single-trace figure could only ever be the builder-side discount — it structurally cannot express a net
# LOSS. A TRUE net-of-tax verdict requires comparing a MIXED-TIER run against an ALL-DEEP baseline RUN (the
# separate vehicle experiment); one trace cannot compute that counterfactual. This tool therefore reports
# the decomposed pieces (builder tier-discount, reassembly tax) plus a clearly-labeled CRUDE within-trace
# combination. Relative units only; the only economics input is the static WEIGHT_* config.
# What it changes: read-only — analyses a trace file and prints a report (or --json) to stdout; mutates nothing.
# Guardrails: read-only; no network, no writes; weights read from agent-immutable .kit/budget.conf via the
#   KEY=VALUE cfg() pattern; graceful degradation (absent weights -> 1.0 advisory; absent tokens -> 0, cost advisory).
#   The headline is the DECOMPOSED builder tier-discount + reassembly tax (never a single "net savings" that
#   silently drops the tax); within_trace_net is a crude approximation, NOT a true net-of-counterfactual.
# Usage: sh scripts/tier-value.sh TRACE.ndjson   |   --json TRACE   |   --selftest
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CONFIG="${TIER_VALUE_BUDGET:-$ROOT/.kit/budget.conf}"

cfg() {  # cfg KEY -> first matching value (KEY=VALUE, ignores # comments); empty if absent
  [ -f "$CONFIG" ] || return 1
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\([^#[:space:]]*\).*/\1/p" "$CONFIG" | head -1
}

# resolve a weight, graceful-degrading to 1.0 (absent / non-numeric => advisory raw-token pricing)
weight_or_default() {
  _w=$(cfg "$1" 2>/dev/null || true); _w="${_w:-1.0}"
  case "$_w" in ''|*[!0-9.]*|*.*.*) _w="1.0" ;; esac
  printf '%s' "$_w"
}

# analyse TRACE -> a one-line JSON summary object on stdout (jq-built; no hand-rolled JSON)
analyse() {
  _f="$1"
  [ -f "$_f" ] || { echo "tier-value: trace not found: $_f" >&2; return 2; }
  WA=$(weight_or_default WEIGHT_APEX)
  WD=$(weight_or_default WEIGHT_DEEP)
  WF=$(weight_or_default WEIGHT_FAST)
  WL=$(weight_or_default WEIGHT_LIGHT)
  jq -s --argjson wa "$WA" --argjson wd "$WD" --argjson wf "$WF" --argjson wl "$WL" '
    [ .[] | select(.parent_span_id != null) ]
    | map(
        (.attributes["model.tier"] // "deep") as $t
        | ((.attributes.tokens // "0") | tonumber? // 0) as $tok
        | $wd as $w
        | (if $t=="apex" then $wa elif $t=="fast" then $wf elif $t=="light" then $wl else $wd end) as $w   # KWTIER: tier-weight override (remove -> constant WEIGHT_DEEP)
        | "other" as $role
        | (if (.name=="agent:engineer" or .name=="agent:explorer") then "builder" else $role end) as $role
        | (if (.attributes["agent.id"]=="orchestrator") then "reassembly" else $role end) as $role   # KWREASM: reassembly classification (remove -> tax vanishes)
        | {
            role: $role,
            has_tokens: (.attributes.tokens != null),
            cost: ($tok * $w),
            basecost: ($tok * $wd),
            wall: (((.end_unix_nano // 0) - (.start_unix_nano // 0)) | if . < 0 then 0 else . end),
            q: ((( .attributes["review.rounds"] // "0") | tonumber? // 0)
                + ((.attributes.retries // "0") | tonumber? // 0)
                + (if .attributes["kit.conflict"]=="true" then 1 else 0 end))
          }
      )
    | {
        spans:           length,
        total_cost:      ((map(.cost)     | add) // 0),
        baseline_cost:   ((map(.basecost) | add) // 0),
        builder_cost:    ((map(select(.role=="builder").cost)     | add) // 0),
        builder_base:    ((map(select(.role=="builder").basecost) | add) // 0),
        reassembly_cost: ((map(select(.role=="reassembly").cost)  | add) // 0),
        speed_ns:        ((map(.wall) | add) // 0),
        quality_proxy:   ((map(.q)    | add) // 0),
        tokens_missing:  (any(.[]; .has_tokens | not) // false)
      }
    | . + { builder_discount:  (.builder_base - .builder_cost) }        # builder-side tier discount (was the mislabeled "net savings"; blind to the reassembly tax)
    | . + { within_trace_net:  (.builder_discount - .reassembly_cost) } # CRUDE within-trace combination; CAN GO NEGATIVE when the tax exceeds the discount. NOT a true net-of-counterfactual.
  ' "$_f"
}

report() {  # human-readable report + a one-line verdict:
  _f="$1"; _j=$(analyse "$_f") || return $?
  printf '%s' "$_j" | jq -r '
    "Value analysis (relative deep-equivalent units; NOT dollars) — \(.spans) builder/reassembly span(s)",
    "  total cost           : \(.total_cost)   (baseline all-deep: \(.baseline_cost))",
    "  builder cost         : \(.builder_cost)   (baseline \(.builder_base))",
    "  builder tier-discount: \(.builder_discount) deep-equiv   (builder-side saving from cheaper tiers — NOT a net of the reassembly tax)",
    "  reassembly tax       : \(.reassembly_cost) deep-equiv   (the orchestrator reassembly cost — a SEPARATE figure)",
    "  within-trace net     : \(.within_trace_net) deep-equiv   (builder tier-discount − reassembly tax; CRUDE within-trace approximation, NOT a true net-of-counterfactual; goes NEGATIVE when the tax exceeds the discount)",
    "  speed (Σ wall)       : \(.speed_ns) ns",
    "  quality-proxy        : \(.quality_proxy) (Σ review.rounds + retries + conflicts — a PROXY, not quality)"
      + (if .tokens_missing then "   [cost axis ADVISORY: some spans carry no tokens]" else "" end),
    "NOTE: a TRUE net-of-tax verdict requires comparing a mixed-tier RUN against an all-deep baseline RUN",
    "      (the vehicle experiment). A single trace CANNOT compute it — the figures above are the decomposed",
    "      pieces (builder tier-discount, reassembly tax) plus a crude within-trace combination.",
    "verdict: builder tier-discount \(.builder_discount), reassembly tax \(.reassembly_cost); within-trace net \(.within_trace_net) deep-equiv (crude within-trace approximation, NOT a true net-of-counterfactual)"
  '
}

selftest() {
  st=0; d=$(mktemp)
  tid=$(sh "$(dirname "$0")/otel-trace.sh" new-trace)
  root=$(sh "$(dirname "$0")/otel-trace.sh" span --trace "$tid" --name orchestrator-run --status OK --sink "$d" --attr "agent.id=orchestrator")
  sh "$(dirname "$0")/otel-trace.sh" span --trace "$tid" --parent "$root" --name "agent:engineer" --status OK \
     --start 1000 --end 2000 --sink "$d" --attr "agent.id=engineer" --attr "model.tier=fast" --attr "tokens=1000" >/dev/null
  sh "$(dirname "$0")/otel-trace.sh" span --trace "$tid" --parent "$root" --name "gate:integration" --status ERROR \
     --start 2000 --end 2500 --sink "$d" --attr "agent.id=orchestrator" --attr "tokens=400" --attr "kit.conflict=true" >/dev/null
  j=$(analyse "$d")
  # a fast builder priced below deep -> a positive builder tier-discount; an orchestrator span -> a reassembly tax.
  [ "$(printf '%s' "$j" | jq -r '.builder_discount > 0')" = "true" ] || { echo "FAIL: selftest — no builder tier-discount on a fast builder"; st=1; }
  [ "$(printf '%s' "$j" | jq -r '.reassembly_cost > 0')" = "true" ]  || { echo "FAIL: selftest — reassembly tax not counted"; st=1; }
  [ "$(printf '%s' "$j" | jq -r '.quality_proxy >= 1')" = "true" ]   || { echo "FAIL: selftest — conflict not counted in quality-proxy"; st=1; }
  # within_trace_net is the crude combination of the two; here discount(700) > tax(400) -> positive.
  [ "$(printf '%s' "$j" | jq -r '.within_trace_net == (.builder_discount - .reassembly_cost)')" = "true" ] \
     || { echo "FAIL: selftest — within_trace_net != builder_discount − reassembly_cost"; st=1; }
  # a tax-swamped trace makes within_trace_net go NEGATIVE (the finding: the tool CAN now express a net loss).
  dn=$(mktemp); tidn=$(sh "$(dirname "$0")/otel-trace.sh" new-trace)
  rn=$(sh "$(dirname "$0")/otel-trace.sh" span --trace "$tidn" --name orchestrator-run --status OK --sink "$dn" --attr "agent.id=orchestrator")
  sh "$(dirname "$0")/otel-trace.sh" span --trace "$tidn" --parent "$rn" --name "agent:engineer" --status OK \
     --start 1000 --end 2000 --sink "$dn" --attr "agent.id=engineer" --attr "model.tier=fast" --attr "tokens=1000" >/dev/null
  sh "$(dirname "$0")/otel-trace.sh" span --trace "$tidn" --parent "$rn" --name "gate:integration" --status ERROR \
     --start 2000 --end 5000 --sink "$dn" --attr "agent.id=orchestrator" --attr "tokens=5000" >/dev/null
  [ "$(analyse "$dn" | jq -r '.within_trace_net < 0')" = "true" ] || { echo "FAIL: selftest — within_trace_net not NEGATIVE when reassembly tax > builder discount"; st=1; }
  report "$dn" | grep -qiE '\bsaved\b' && { echo "FAIL: selftest — report still claims 'saved' on a net-negative trace"; st=1; } || true
  rm -f "$dn"
  # the human report carries a one-line verdict.
  report "$d" | grep -qi '^verdict:' || { echo "FAIL: selftest — report emits no verdict line"; st=1; }
  # graceful degradation: a token-less span -> tokens_missing flag set, no crash.
  d2=$(mktemp); tid2=$(sh "$(dirname "$0")/otel-trace.sh" new-trace)
  r2=$(sh "$(dirname "$0")/otel-trace.sh" span --trace "$tid2" --name orchestrator-run --status OK --sink "$d2" --attr "agent.id=orchestrator")
  sh "$(dirname "$0")/otel-trace.sh" span --trace "$tid2" --parent "$r2" --name "agent:engineer" --status OK --sink "$d2" --attr "agent.id=engineer" --attr "model.tier=deep" >/dev/null
  [ "$(analyse "$d2" | jq -r '.tokens_missing')" = "true" ] || { echo "FAIL: selftest — tokens_missing not flagged"; st=1; }
  rm -f "$d" "$d2"
  [ "$st" -eq 0 ] && { echo "tier-value --selftest: OK (builder tier-discount, reassembly tax, within-trace net (incl. NEGATIVE when tax>discount, no 'saved'), quality-proxy, verdict, tokens-missing degrade)"; exit 0; } \
                  || { echo "tier-value --selftest: FAIL" >&2; exit 1; }
}

case "${1:-}" in
  --selftest) selftest ;;
  --json) [ $# -ge 2 ] || { echo "usage: tier-value.sh --json TRACE" >&2; exit 2; }; analyse "$2" ;;
  ""|-*) echo "usage: tier-value.sh TRACE.ndjson | --json TRACE | --selftest" >&2; exit 2 ;;
  *) report "$1" ;;
esac
