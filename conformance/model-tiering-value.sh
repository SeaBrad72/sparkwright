#!/bin/sh
# model-tiering-value.sh — KW20(b) Slice 3 (B): the VALUE ANALYSIS MODEL is non-vacuous over a trace.
# scripts/tier-value.sh reads an OTel run trace and reports the fan-out value in RELATIVE deep-equivalent
# units (Σ tokens × static tier-weight), splitting the BUILDER tier-discount (agent:engineer/explorer
# spans priced below their all-deep baseline) from the orchestrator's REASSEMBLY tax (agent.id=orchestrator
# spans, e.g. gate:integration) — reported as SEPARATE figures, plus a crude within-trace net
# (builder_discount − reassembly_cost, which CAN GO NEGATIVE), a speed + quality-proxy axis, and a verdict.
#
# SCOPE — a green run proves the model COMPUTES the analysis non-vacuously over a trace (tier-aware
# discount, a real reassembly tax, a within-trace net that can flip NEGATIVE when the tax exceeds the
# discount, mixed≠all-deep). It does NOT prove the actual token numbers (NATIVE — a real Workflow run
# supplies them) nor that the quality-proxy IS quality (rework is a proxy). Crucially it does NOT compute a
# TRUE net-of-tax verdict: that needs comparing a mixed-tier RUN against an all-deep baseline RUN (the
# separate vehicle experiment) — a single trace cannot express the counterfactual, only the decomposed
# pieces + a crude within-trace combination. No dollars, no live rate lookup — the only economics input is
# the static WEIGHT_* config in .kit/budget.conf.
# What it changes: read-only — builds throwaway fixture traces in mktemp files and analyses them; mutates no tracked file.
# Guardrails: read-only against the tree; fixtures + the mutated-script copies live in temp files only;
#   two load-bearing negatives (ignore-tier collapses the builder discount; ignore-rework hides the
#   reassembly tax), PLUS a sign-discrimination lock (a rework-disaster fixture whose reassembly tax
#   exceeds the builder discount yields a NEGATIVE within-trace net, DISTINCT from a clean-cheap fixture's
#   positive net) make the assertions depend on the analyzer's real behaviour, not on an always-true shape.
# Usage: sh conformance/model-tiering-value.sh [--selftest]
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPTS="$ROOT/scripts"
TV="$SCRIPTS/tier-value.sh"
BUDGET="$ROOT/.kit/budget.conf"

# ── fixture builders (only CHILD spans are analysed; the root carries the trace) ──

# all-deep, no rework: root + two deep builders (tokens=1000 each). Baseline == actual -> savings 0.
build_all_deep() {
  _f="$1"; printf '' > "$_f"; _tid=$(sh "$SCRIPTS/otel-trace.sh" new-trace)
  _root=$(sh "$SCRIPTS/otel-trace.sh" span --trace "$_tid" --name "orchestrator-run" --status OK \
            --sink "$_f" --attr "agent.id=orchestrator")
  sh "$SCRIPTS/otel-trace.sh" span --trace "$_tid" --parent "$_root" --name "agent:engineer" --status OK \
     --start 1000 --end 2000 --sink "$_f" --attr "agent.id=engineer" --attr "slice=alpha" \
     --attr "model.tier=deep" --attr "tokens=1000" >/dev/null
  sh "$SCRIPTS/otel-trace.sh" span --trace "$_tid" --parent "$_root" --name "agent:engineer" --status OK \
     --start 2000 --end 3000 --sink "$_f" --attr "agent.id=engineer" --attr "slice=beta" \
     --attr "model.tier=deep" --attr "tokens=1000" >/dev/null
}

# mixed fast builders WITH a gate:integration rework span (the orchestrator's reassembly tax).
build_mixed_rework() {
  _f="$1"; printf '' > "$_f"; _tid=$(sh "$SCRIPTS/otel-trace.sh" new-trace)
  _root=$(sh "$SCRIPTS/otel-trace.sh" span --trace "$_tid" --name "orchestrator-run" --status OK \
            --sink "$_f" --attr "agent.id=orchestrator")
  sh "$SCRIPTS/otel-trace.sh" span --trace "$_tid" --parent "$_root" --name "agent:engineer" --status OK \
     --start 1000 --end 2000 --sink "$_f" --attr "agent.id=engineer" --attr "slice=alpha" \
     --attr "model.tier=fast" --attr "tokens=1000" >/dev/null
  sh "$SCRIPTS/otel-trace.sh" span --trace "$_tid" --parent "$_root" --name "agent:engineer" --status OK \
     --start 2000 --end 3000 --sink "$_f" --attr "agent.id=engineer" --attr "slice=beta" \
     --attr "model.tier=fast" --attr "tokens=1000" >/dev/null
  # reassembly: the orchestrator reworks the fan-out (gate:integration) -> a real assembly tax + a conflict.
  sh "$SCRIPTS/otel-trace.sh" span --trace "$_tid" --parent "$_root" --name "gate:integration" --status ERROR \
     --start 3000 --end 3500 --sink "$_f" --attr "agent.id=orchestrator" --attr "tokens=500" \
     --attr "kit.conflict=true" --attr "review.rounds=1" >/dev/null
}

# clean-cheap: two fast builders (discount 1400) + a SMALL reassembly tax (100 tokens deep -> cost 100).
# within-trace net = 1400 - 100 = +1300 -> POSITIVE (fanning out clearly paid off within this trace).
build_clean_cheap() {
  _f="$1"; printf '' > "$_f"; _tid=$(sh "$SCRIPTS/otel-trace.sh" new-trace)
  _root=$(sh "$SCRIPTS/otel-trace.sh" span --trace "$_tid" --name "orchestrator-run" --status OK \
            --sink "$_f" --attr "agent.id=orchestrator")
  sh "$SCRIPTS/otel-trace.sh" span --trace "$_tid" --parent "$_root" --name "agent:engineer" --status OK \
     --start 1000 --end 2000 --sink "$_f" --attr "agent.id=engineer" --attr "slice=alpha" \
     --attr "model.tier=fast" --attr "tokens=1000" >/dev/null
  sh "$SCRIPTS/otel-trace.sh" span --trace "$_tid" --parent "$_root" --name "agent:engineer" --status OK \
     --start 2000 --end 3000 --sink "$_f" --attr "agent.id=engineer" --attr "slice=beta" \
     --attr "model.tier=fast" --attr "tokens=1000" >/dev/null
  sh "$SCRIPTS/otel-trace.sh" span --trace "$_tid" --parent "$_root" --name "gate:integration" --status OK \
     --start 3000 --end 3200 --sink "$_f" --attr "agent.id=orchestrator" --attr "tokens=100" >/dev/null
}

# rework-disaster: same two fast builders (discount 1400) but a HUGE reassembly tax (5000 tokens deep ->
# cost 5000). within-trace net = 1400 - 5000 = -3600 -> NEGATIVE: the reassembly tax swamped the fan-out
# discount. This is the finding the value model was previously BLIND to (it could only ever report the
# builder discount as "net savings"), so it locks the exact discrimination that was missing.
build_rework_disaster() {
  _f="$1"; printf '' > "$_f"; _tid=$(sh "$SCRIPTS/otel-trace.sh" new-trace)
  _root=$(sh "$SCRIPTS/otel-trace.sh" span --trace "$_tid" --name "orchestrator-run" --status OK \
            --sink "$_f" --attr "agent.id=orchestrator")
  sh "$SCRIPTS/otel-trace.sh" span --trace "$_tid" --parent "$_root" --name "agent:engineer" --status OK \
     --start 1000 --end 2000 --sink "$_f" --attr "agent.id=engineer" --attr "slice=alpha" \
     --attr "model.tier=fast" --attr "tokens=1000" >/dev/null
  sh "$SCRIPTS/otel-trace.sh" span --trace "$_tid" --parent "$_root" --name "agent:engineer" --status OK \
     --start 2000 --end 3000 --sink "$_f" --attr "agent.id=engineer" --attr "slice=beta" \
     --attr "model.tier=fast" --attr "tokens=1000" >/dev/null
  # the orchestrator burns 5000 deep-tokens reassembling the fan-out -> a tax that dwarfs the discount.
  sh "$SCRIPTS/otel-trace.sh" span --trace "$_tid" --parent "$_root" --name "gate:integration" --status ERROR \
     --start 3000 --end 6000 --sink "$_f" --attr "agent.id=orchestrator" --attr "tokens=5000" \
     --attr "kit.conflict=true" --attr "review.rounds=3" >/dev/null
}

# jq field of tier-value.sh --json output
jval() { printf '%s' "$1" | jq -r "$2" 2>/dev/null || echo "?"; }
# verdict line of the default (human) report
verdict() { sh "$TV" "$1" 2>/dev/null | grep -i '^verdict:' || echo "verdict:?"; }

selftest() {
  fail=0
  [ -x "$TV" ] || [ -f "$TV" ] || { echo "FAIL: scripts/tier-value.sh does not exist (RED — build it)"; echo "model-tiering-value --selftest: FAIL" >&2; exit 1; }

  di=$(mktemp); build_all_deep "$di"
  mi=$(mktemp); build_mixed_rework "$mi"
  jd=$(sh "$TV" --json "$di") || { echo "FAIL: tier-value.sh --json errored on the all-deep fixture"; echo "model-tiering-value --selftest: FAIL" >&2; exit 1; }
  jm=$(sh "$TV" --json "$mi") || { echo "FAIL: tier-value.sh --json errored on the mixed fixture"; echo "model-tiering-value --selftest: FAIL" >&2; exit 1; }

  # POSITIVE 1 — all-deep, no rework: builder tier-discount ≈ 0 AND no reassembly tax AND within-trace net ≈ 0.
  if [ "$(jval "$jd" '(.builder_discount|fabs) < 0.001')" = "true" ] && [ "$(jval "$jd" '.reassembly_cost == 0')" = "true" ] \
     && [ "$(jval "$jd" '(.within_trace_net|fabs) < 0.001')" = "true" ]; then
    echo "PASS: all-deep trace -> builder discount≈0, no reassembly tax, within-trace net≈0 (discount=$(jval "$jd" .builder_discount))"
  else
    echo "FAIL: all-deep trace should net ~0 discount + 0 reassembly + ~0 within-trace net (discount=$(jval "$jd" .builder_discount), reassembly=$(jval "$jd" .reassembly_cost), net=$(jval "$jd" .within_trace_net))"; fail=1
  fi

  # POSITIVE 2 — mixed+rework: a non-zero BUILDER tier-discount AND a non-zero REASSEMBLY tax (separate figures).
  if [ "$(jval "$jm" '.builder_discount > 0')" = "true" ] && [ "$(jval "$jm" '.reassembly_cost > 0')" = "true" ]; then
    echo "PASS: mixed+rework -> builder discount>0 ($(jval "$jm" .builder_discount)) AND reassembly tax>0 ($(jval "$jm" .reassembly_cost))"
  else
    echo "FAIL: mixed+rework should show builder discount>0 + reassembly tax>0 (builder_discount=$(jval "$jm" .builder_discount), reassembly=$(jval "$jm" .reassembly_cost))"; fail=1
  fi

  # POSITIVE 2b — LOAD-BEARING sign discrimination (THE finding): a rework-disaster trace whose reassembly
  # tax (5000) EXCEEDS the builder discount (1400) yields a NEGATIVE within-trace net (-3600), DISTINCT from
  # a clean-cheap trace whose within-trace net is POSITIVE (+1300). Before the fix the headline was blind to
  # the reassembly tax and could never express a net loss — this locks that the tool now CAN.
  cc=$(mktemp); build_clean_cheap "$cc"; jc=$(sh "$TV" --json "$cc")
  rd=$(mktemp); build_rework_disaster "$rd"; jr=$(sh "$TV" --json "$rd")
  if [ "$(jval "$jr" '.within_trace_net < 0')" = "true" ] && [ "$(jval "$jc" '.within_trace_net > 0')" = "true" ] \
     && [ "$(jval "$jr" .within_trace_net)" != "$(jval "$jc" .within_trace_net)" ]; then
    echo "PASS: sign-discrimination — reassembly-tax>discount -> NEGATIVE within-trace net ($(jval "$jr" .within_trace_net)) vs clean-cheap POSITIVE ($(jval "$jc" .within_trace_net))"
  else
    echo "FAIL: sign-discrimination — a tax-swamped trace should net NEGATIVE and differ from a clean-cheap POSITIVE (disaster net=$(jval "$jr" .within_trace_net), clean net=$(jval "$jc" .within_trace_net))"; fail=1
  fi
  # the rework-disaster report must NOT claim it "saved" (the misleading verdict is gone).
  if sh "$TV" "$rd" 2>/dev/null | grep -qiE '\bsaved\b'; then
    echo "FAIL: sign-discrimination — the report still claims it 'saved' on a net-negative trace"; fail=1
  else
    echo "PASS: sign-discrimination — the net-negative report no longer claims it 'saved'"
  fi
  rm -f "$cc" "$rd"

  # POSITIVE 3 — the two traces yield DIFFERENT verdicts.
  vd=$(verdict "$di"); vm=$(verdict "$mi")
  if [ "$vd" != "$vm" ]; then
    echo "PASS: the two traces yield DIFFERENT verdicts (all-deep != mixed+rework)"
  else
    echo "FAIL: the two traces yielded the SAME verdict — the model is not discriminating (both: $vd)"; fail=1
  fi

  # NEGATIVE (a) LOAD-BEARING — ignore model.tier (constant weight): the tier-weight override line
  # (marker KWTIER) is removed -> every span is priced at WEIGHT_DEEP -> the mixed trace's builder
  # tier-discount (the ONLY signal that fanning out to a cheaper tier paid off) collapses from >0 to exactly
  # 0, whereas the real analyzer reports 1400. Proves the builder-discount verdict DEPENDS on tier-awareness
  # (a constant-weight analyzer cannot tell all-deep from cheaper-fanned-out builders).
  notier=$(mktemp); grep -vF 'KWTIER' "$TV" > "$notier"
  jm_nt=$(TIER_VALUE_BUDGET="$BUDGET" sh "$notier" --json "$mi" 2>/dev/null || echo '{}')
  if [ "$(jval "$jm" '.builder_discount > 0')" = "true" ] && [ "$(jval "$jm_nt" '.builder_discount == 0')" = "true" ]; then
    echo "PASS: non-vacuity — ignoring model.tier collapses the builder discount from >0 to 0 (tier-awareness is load-bearing)"
  else
    echo "FAIL: non-vacuity — a tier-BLIND analyzer still showed a builder discount (assertion not load-bearing): real=$(jval "$jm" .builder_discount) blind=$(jval "$jm_nt" .builder_discount)"; fail=1
  fi

  # NEGATIVE (b) LOAD-BEARING — ignore rework: the reassembly-classification line (marker KWREASM) is
  # removed -> orchestrator spans are no longer counted as reassembly -> the tax vanishes to 0 on the
  # mixed+rework trace. Proves the reassembly axis is load-bearing (the assembly tax is not free-riding).
  norework=$(mktemp); grep -vF 'KWREASM' "$TV" > "$norework"
  jm_nr=$(TIER_VALUE_BUDGET="$BUDGET" sh "$norework" --json "$mi" 2>/dev/null || echo '{}')
  if [ "$(jval "$jm_nr" '.reassembly_cost == 0')" = "true" ]; then
    echo "PASS: non-vacuity — ignoring rework makes the reassembly tax invisible (0) on a trace that has one"
  else
    echo "FAIL: non-vacuity — a rework-BLIND analyzer still reported a reassembly tax (assertion not load-bearing): $(jval "$jm_nr" .reassembly_cost)"; fail=1
  fi

  rm -f "$di" "$mi" "$notier" "$norework"
  [ "$fail" -eq 0 ] && { echo "model-tiering-value --selftest: OK (all-deep≈0; mixed discount+reassembly-tax; NEGATIVE within-trace net when tax>discount vs clean-cheap POSITIVE; distinct verdicts; ignore-tier + ignore-rework non-vacuity)"; exit 0; } \
                    || { echo "model-tiering-value --selftest: FAIL" >&2; exit 1; }
}

# real-run: analyse a demo orchestrator trace end-to-end (proves the model runs on the reference loop).
# IDEMPOTENCY: invoke orchestrator-run.sh with NO ARGS -> its self-isolating demo() runs the loop in a
# THROWAWAY git repo (mktemp) and never touches the host repo. (Passing the literal word "demo" is wrong:
# it is dispatched as a SLICE name, creating an e3a/demo branch in the CURRENT repo that makes a second
# run hard-fail with "a branch named 'e3a/demo' already exists".) The no-arg form leaves no branch debris,
# so this check is safely re-runnable.
run_check() {
  [ -f "$TV" ] || { echo "model-tiering-value: FAIL — scripts/tier-value.sh missing"; return 1; }
  tr=$(sh "$SCRIPTS/orchestrator-run.sh" 2>/dev/null | tail -1)
  if [ -n "$tr" ] && [ -f "$tr" ] && sh "$TV" --json "$tr" >/dev/null 2>&1; then
    echo "PASS: tier-value.sh analyses a real orchestrator-run demo trace (isolated; idempotent)"; rm -f "$tr"; return 0
  else
    echo "FAIL: tier-value.sh could not analyse a demo trace"; return 1
  fi
}

case "${1:-}" in
  --selftest) selftest ;;
  *) if run_check; then echo "model-tiering-value: OK"; else echo "model-tiering-value: FAIL"; exit 1; fi ;;
esac
