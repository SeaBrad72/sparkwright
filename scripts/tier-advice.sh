#!/bin/sh
# tier-advice.sh — render the autonomy-tier DECISION view from agent-scorecard's
# already-emitted directives, with DORA delivery-health as labeled context.
#
# READ-ONLY and ADVISORY. Composes scripts/agent-scorecard.sh (the per-agent behavior
# classifier, which already emits the asymmetric tier directive) and scripts/dora.sh
# (delivery-health report) into one human-facing view answering "which agents have a
# PENDING autonomy-tier recommendation, and what must a human do about it?". It adds NO
# classification logic of its own, and NEVER actuates — it never touches .claude/, the
# guard, or any tier store; the human applies the recommendation in their own enforcement
# plane (docs/operations/agentic-ops.md, DEVELOPMENT-PROCESS.md section 13).
#
# DORA is delivery-health CONTEXT, never an input to the tier recommendation (the
# recommendation is driven solely by agent-scorecard; DEVELOPMENT-PROCESS.md section 13).
#
# Always exits 0 on the report path (advisory; never fails a pipeline), like dora.sh.
#
# Usage:
#   scripts/tier-advice.sh [--traces DIR] [--window N] [--min-runs N] [--margin F] [--no-dora]
#   scripts/tier-advice.sh --selftest
set -eu

TRACES="traces"; WINDOW=20; MIN_RUNS=5; MARGIN="0.15"; NO_DORA=0; DO_SELFTEST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --selftest) DO_SELFTEST=1; shift ;;
    --traces)   TRACES="${2:?--traces needs a dir}"; shift 2 ;;
    --window)   WINDOW="${2:?--window needs a value}"; shift 2 ;;
    --min-runs) MIN_RUNS="${2:?--min-runs needs a value}"; shift 2 ;;
    --margin)   MARGIN="${2:?--margin needs a value}"; shift 2 ;;
    --no-dora)  NO_DORA=1; shift ;;
    -*)         printf 'unknown flag: %s\n' "$1" >&2; exit 2 ;;
    *)          printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

# Locked governance framing — conformance/tier-advice-wired.sh asserts these literals verbatim.
DORA_CONTEXT_LABEL="Delivery-health context — NOT an input to the tier recommendation above."
APPLY_DOWNGRADE="FAIL-SAFE — lower this agent's tier one level now; NO ratification required (section 13). You apply it in your enforcement plane; the kit never actuates."
APPLY_RAISE="RATIFY — route to the Security owner to approve a one-level raise (section 13). Do NOT self-apply."

# scorecard_json: emit the scorecard's JSON cards. Overridable test seam (deterministic
# selftest + CI; never touches the network). Tolerates absence -> empty (report degrades).
scorecard_json() {
  if [ -n "${TIER_ADVICE_SCORECARD_CMD:-}" ]; then
    eval "$TIER_ADVICE_SCORECARD_CMD" 2>/dev/null || true
  elif [ -f scripts/agent-scorecard.sh ]; then
    sh scripts/agent-scorecard.sh --stdout --traces "$TRACES" --window "$WINDOW" \
       --min-runs "$MIN_RUNS" --margin "$MARGIN" 2>/dev/null || true
  fi
}

# dora_report: emit the DORA report text. Overridable test seam. Degrades to a note.
dora_report() {
  if [ -n "${TIER_ADVICE_DORA_CMD:-}" ]; then
    eval "$TIER_ADVICE_DORA_CMD" 2>&1 || true
  elif [ -f scripts/dora.sh ]; then
    sh scripts/dora.sh 2>&1 || true
  else
    echo "  dora: N/A (scripts/dora.sh not present)"
  fi
}

report() {
  echo "sparkwright tier-advice — autonomy-tier decision view"
  echo "====================================================="
  echo ""
  echo "PENDING AUTONOMY-TIER RECOMMENDATIONS"
  echo "-------------------------------------"

  cards="$(scorecard_json)"
  if [ -z "$cards" ] || ! printf '%s' "$cards" | jq -e . >/dev/null 2>&1; then
    echo "  unavailable (agent-scorecard produced no parseable output; needs jq + traces)"
  else
    n="$(printf '%s' "$cards" | jq '[.[] | select(.directive != null)] | length' 2>/dev/null || echo 0)"
    if [ "${n:-0}" = "0" ]; then
      echo "  No pending autonomy-tier recommendations (all agents steady / thin data)."
    else
      printf '%s' "$cards" \
        | jq -r 'map(select(.directive != null)) | sort_by(."agent.id")[]
                 | [."agent.id", .classification, .directive.action, (.directive.reason // "")]
                 | @tsv' \
        | while IFS="$(printf '\t')" read -r aid cls action reason; do
            printf '  * %s · %s · %s\n' "$aid" "$cls" "$action"
            case "$action" in
              auto-downgrade)       printf '      APPLY PATH: %s\n' "$APPLY_DOWNGRADE" ;;
              raise-recommendation) printf '      APPLY PATH: %s\n' "$APPLY_RAISE" ;;
              *)                    printf '      APPLY PATH: (unrecognized directive; review agent-scorecard output)\n' ;;
            esac
            [ -n "$reason" ] && printf '      reason: %s\n' "$reason"
          done
    fi
  fi

  if [ "$NO_DORA" = "0" ]; then
    echo ""
    echo "$DORA_CONTEXT_LABEL"
    echo "------------------------------------------------------------------"
    dora_report
  fi

  echo ""
  echo "Honest ceiling: recommendations derive from each agent's own trailing baseline over the"
  echo "trace window; thin/absent data yields no directive (an agent is never downgraded on missing"
  echo "data). The kit EMITS; the human APPLIES — there is no actuation. DORA is context, not a tier"
  echo "driver. For project posture see 'sparkwright doctor'. See docs/operations/agentic-ops.md and DEVELOPMENT-PROCESS.md section 13."
}

selftest() {
  sfail=0
  _d="$(dirname "$0")"
  fx="$_d/fixtures/scorecard"
  # Deterministic seams: classify the fixture corpus with the window the fixtures were
  # designed for (matches agent-scorecard --selftest: WINDOW=6 MIN_RUNS=2), and a fixed
  # DORA stub so no network/gh is touched.
  export TIER_ADVICE_SCORECARD_CMD="sh \"$_d/agent-scorecard.sh\" --stdout --traces \"$fx\" --window 6 --min-runs 2"
  export TIER_ADVICE_DORA_CMD="printf 'DORA metrics (stub) — Release cadence: 1 release\\n'"

  if out="$(sh "$0")"; then :; else echo "tier-advice --selftest: FAIL (report non-zero exit)"; sfail=1; out=""; fi

  # bad-bot regressed -> auto-downgrade + fail-safe text
  if printf '%s\n' "$out" | grep -q "bad-bot" && printf '%s\n' "$out" | grep -q "auto-downgrade"; then :; \
    else echo "FAIL: bad-bot auto-downgrade line missing"; sfail=1; fi
  if printf '%s\n' "$out" | grep -q "NO ratification required"; then :; \
    else echo "FAIL: fail-safe apply text missing"; sfail=1; fi
  # good-bot earned -> raise + Security owner
  if printf '%s\n' "$out" | grep -q "good-bot" && printf '%s\n' "$out" | grep -q "raise-recommendation"; then :; \
    else echo "FAIL: good-bot raise-recommendation line missing"; sfail=1; fi
  if printf '%s\n' "$out" | grep -q "Security owner"; then :; \
    else echo "FAIL: Security-owner apply text missing"; sfail=1; fi
  # thin-bot steady -> NO recommendation line (negative assertion — set -e safe if-block)
  if printf '%s\n' "$out" | grep -q "thin-bot"; then echo "FAIL: thin-bot must not appear (steady)"; sfail=1; fi
  # DORA context label present
  if printf '%s\n' "$out" | grep -q "NOT an input to the tier recommendation"; then :; \
    else echo "FAIL: DORA context label missing"; sfail=1; fi
  # --no-dora suppresses the DORA block (negative assertion — if-block)
  out_nd="$(sh "$0" --no-dora)" || true
  if printf '%s\n' "$out_nd" | grep -q "NOT an input to the tier recommendation"; then
    echo "FAIL: --no-dora did not suppress the DORA block"; sfail=1; fi

  [ "$sfail" -eq 0 ] && { echo "tier-advice --selftest: OK (regressed/earned/steady + apply paths + DORA label + --no-dora)"; return 0; }
  echo "tier-advice --selftest: FAIL"; return 1
}

if [ "$DO_SELFTEST" -eq 1 ]; then selftest; exit $?; fi
report
exit 0
