#!/bin/sh
# agent-scorecard.sh — per-agent behavior scorecard over a window of traces (MP-3b).
# Reads MP-3a-schema traces (scripts/agent-trace.sh output), groups by agent.id,
# computes trace-derivable behavior metrics over a window, classifies each agent
# regressed|steady|earned vs its OWN trailing baseline, and emits a scorecard +
# the asymmetric tier directive (auto-downgrade on regression / ratified-raise
# recommendation on earned). It EMITS directives; it NEVER actuates (never touches
# .claude/, the guard, or any tier store). sh + jq, mirroring scripts/agent-trace.sh.
#
# Honesty: "unknown" trace fields are EXCLUDED from a metric (never coerced to 0).
# Thin data (< --min-runs) or absent data -> steady, no directive (fail-safe).
# A green --selftest proves correct COMPUTATION on a fixture, not that any real
# agent behaved. It is a tool, not a gate; it fails no PR.
#
# Usage:
#   scripts/agent-scorecard.sh [--traces DIR] [--window N] [--min-runs N] \
#       [--margin F] [--cost-margin F] [--out DIR] [--stdout]
#   scripts/agent-scorecard.sh --selftest
# What it changes: Writes per-agent scorecard files to --out DIR (default scorecards/), or stdout with --stdout; reads traces only.
# Guardrails: Emits tier directives but NEVER actuates (never touches .claude/, the guard, or any tier store); thin/unknown data fails safe to "steady"; not a gate.
set -eu

TRACES="traces"; WINDOW=20; MIN_RUNS=5; MARGIN="0.15"; COSTMARGIN="0.25"; OUTDIR="scorecards"; STDOUT=0
DO_SELFTEST=0

# --- arg parsing ---
while [ $# -gt 0 ]; do
  case "$1" in
    --selftest)  DO_SELFTEST=1; shift ;;
    --traces)    TRACES="${2:?--traces needs a dir}"; shift 2 ;;
    --window)    WINDOW="${2:?--window needs a value}"; shift 2 ;;
    --min-runs)  MIN_RUNS="${2:?--min-runs needs a value}"; shift 2 ;;
    --margin)    MARGIN="${2:?--margin needs a value}"; shift 2 ;;
    --cost-margin) COSTMARGIN="${2:?--cost-margin needs a value}"; shift 2 ;;
    --out)       OUTDIR="${2:?--out needs a dir}"; shift 2 ;;
    --stdout)    STDOUT=1; shift ;;
    -*)          printf 'unknown flag: %s\n' "$1" >&2; exit 2 ;;
    *)           printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

# The scorecard jq program. `score` scores ONE agent's run-array (`.`); the trailer
# groups all traces by agent.id and maps `score` over each group — so agent ids never
# transit shell word-splitting (a spaced id can't spawn phantom cards). No apostrophes
# in any string (the program is single-quoted in sh). No JSON is parsed in sh.
SCORECARD_JQ='
  def denial($a): ($a | [.[].steps[]?.outcome] | if length==0 then 0
                   else (map(select(.=="denied")) | length) / length end);
  def errrate($a): ($a | if length==0 then 0
                   else (map(select(.outcome=="error" or .outcome=="blocked")) | length)/length end);
  def retry($a): ($a | if length==0 then 0 else (map([.steps[]?.retries] | add // 0) | add / length) end);
  def costmean($a): ($a | [.[].cost | select(type=="number")] | if length==0 then null else add/length end);
  def evalmean($a): ($a | [.[]["eval.score"] | select(type=="number")] | if length==0 then null else add/length end);
  def reviews($a): ($a | [.[]."review.rounds" | select(type=="number")]
                   | if length==0 then null else (add/length) end);
  def tiers($a): ($a | [.[]["model.tier"] | select(. != null and . != "unknown")] | unique);
  def score($window; $minruns; $margin; $costmargin):
    (sort_by(.start) | (if length > $window then .[-$window:] else . end)) as $runs
    | ($runs | length) as $n
    | ($runs[: ($n/2 | floor)]) as $base
    | ($runs[($n/2 | floor):]) as $rec
    | {
        "agent.id": ($runs[0]["agent.id"] // "unknown"),
        runs: $n,
        metrics: { denial_rate: denial($runs), error_blocked_rate: errrate($runs),
                   retry_rate: retry($runs), review_rounds_mean: reviews($runs),
                   cost_per_run: costmean($runs), eval_score_mean: evalmean($runs),
                   model_tiers: tiers($runs),
                   gate_skip_rate: "unknown" },
        baseline: {denial: denial($base), err: errrate($base), cost: costmean($base), eval: evalmean($base)},
        recent:   {denial: denial($rec), err: errrate($rec), cost: costmean($rec), eval: evalmean($rec)}
      }
    | .classification = (
        if $n < $minruns then "steady"
        elif (.recent.denial - .baseline.denial) >= $margin
             or (.recent.err - .baseline.err) >= $margin
             or (.recent.cost != null and .baseline.cost != null and .baseline.cost > 0
                 and (.recent.cost > .baseline.cost * (1 + $costmargin)))
             or (.recent.eval != null and .baseline.eval != null
                 and (.baseline.eval - .recent.eval >= $margin)) then "regressed"
        elif (.recent.denial == 0 and .recent.err == 0)
             and (.baseline.denial > 0 or .baseline.err > 0) then "earned"
        else "steady" end )
    | .directive = (
        if .classification == "regressed" then
          {action:"auto-downgrade", reason:"recent risk/cost/quality metrics exceed trailing baseline by >= margin",
           recommend:"lower the agent autonomy tier one level (fail-safe; no ratification needed)"}
        elif .classification == "earned" then
          {action:"raise-recommendation", reason:"sustained improvement vs trailing baseline",
           recommend:"route to the Security owner to ratify a one-level autonomy-tier raise (see section 13)"}
        else null end );
  group_by(."agent.id") | map(score($window; $minruns; $margin; $costmargin))
'

# run_all: collect valid traces (skip + warn on an unparseable file — never silently
# zero the report), then group + score entirely in jq. Emits a JSON array.
run_all() {
  _dir="$1"
  [ -d "$_dir" ] || { printf '[]'; return 0; }
  # Per-file parse so one corrupt trace cannot abort the whole stream (and drop a real
  # agent). Valid objects go to stdout (collected); unparseable files warn on stderr.
  _stream=$(for _f in "$_dir"/*.json; do
    [ -f "$_f" ] || continue
    if _obj=$(jq -c . "$_f" 2>/dev/null); then
      printf '%s\n' "$_obj"
    else
      printf 'agent-scorecard: skipping unparseable trace %s\n' "$_f" >&2
    fi
  done)
  [ -n "$_stream" ] || { printf '[]'; return 0; }
  printf '%s\n' "$_stream" | jq -s \
    --argjson window "$WINDOW" --argjson minruns "$MIN_RUNS" --argjson margin "$MARGIN" \
    --argjson costmargin "$COSTMARGIN" \
    "$SCORECARD_JQ"
}

selftest() {
  st_fail=0
  fx="$(dirname "$0")/fixtures/scorecard"
  WINDOW=6; MIN_RUNS=2; MARGIN="0.15"; COSTMARGIN="0.25"
  out=$(run_all "$fx")
  _cls() { printf '%s' "$out" | jq -r --arg a "$1" '.[] | select(."agent.id"==$a) | .classification'; }
  [ "$(_cls good-bot)" = "earned" ]     || { echo "selftest FAIL: good-bot should be earned (got $(_cls good-bot))"; st_fail=1; }
  [ "$(_cls bad-bot)" = "regressed" ]   || { echo "selftest FAIL: bad-bot should be regressed (got $(_cls bad-bot))"; st_fail=1; }
  [ "$(_cls thin-bot)" = "steady" ]     || { echo "selftest FAIL: thin-bot should be steady (got $(_cls thin-bot))"; st_fail=1; }
  # directive presence matches classification
  [ "$(printf '%s' "$out" | jq -r '.[]|select(."agent.id"=="bad-bot")|.directive.action')" = "auto-downgrade" ] \
      || { echo "selftest FAIL: bad-bot needs an auto-downgrade directive"; st_fail=1; }
  [ "$(printf '%s' "$out" | jq -r '.[]|select(."agent.id"=="good-bot")|.directive.action')" = "raise-recommendation" ] \
      || { echo "selftest FAIL: good-bot needs a raise-recommendation"; st_fail=1; }
  [ "$(printf '%s' "$out" | jq -r '.[]|select(."agent.id"=="thin-bot")|.directive')" = "null" ] \
      || { echo "selftest FAIL: thin-bot must have no directive"; st_fail=1; }
  # honesty: gate_skip_rate stays unknown (never coerced to a number)
  [ "$(printf '%s' "$out" | jq -r '.[0].metrics.gate_skip_rate')" = "unknown" ] \
      || { echo "selftest FAIL: gate_skip_rate must be unknown"; st_fail=1; }
  # cost/quality regression dims: a >25% cost spike and a >=margin eval drop each -> regressed + auto-downgrade
  [ "$(_cls cost-spike-bot)" = "regressed" ] \
      || { echo "selftest FAIL: cost-spike-bot should be regressed (got $(_cls cost-spike-bot))"; st_fail=1; }
  [ "$(printf '%s' "$out" | jq -r '.[]|select(."agent.id"=="cost-spike-bot")|.directive.action')" = "auto-downgrade" ] \
      || { echo "selftest FAIL: cost-spike-bot needs an auto-downgrade directive"; st_fail=1; }
  [ "$(_cls quality-drop-bot)" = "regressed" ] \
      || { echo "selftest FAIL: quality-drop-bot should be regressed (got $(_cls quality-drop-bot))"; st_fail=1; }
  [ "$(printf '%s' "$out" | jq -r '.[]|select(."agent.id"=="quality-drop-bot")|.directive.action')" = "auto-downgrade" ] \
      || { echo "selftest FAIL: quality-drop-bot needs an auto-downgrade directive"; st_fail=1; }
  # exclude-unknown honesty: an agent with NO cost/eval fields reports null (NOT 0) and is not falsely regressed
  [ "$(printf '%s' "$out" | jq -r '.[]|select(."agent.id"=="thin-bot")|.metrics.cost_per_run')" = "null" ] \
      || { echo "selftest FAIL: thin-bot cost_per_run must be null (exclude-unknown, not 0)"; st_fail=1; }
  [ "$(printf '%s' "$out" | jq -r '.[]|select(."agent.id"=="thin-bot")|.metrics.eval_score_mean')" = "null" ] \
      || { echo "selftest FAIL: thin-bot eval_score_mean must be null (exclude-unknown, not 0)"; st_fail=1; }
  if [ "$st_fail" -ne 0 ]; then echo "agent-scorecard --selftest: FAIL" >&2; return 1; fi
  echo "agent-scorecard --selftest: OK (earned/regressed/steady + cost/quality regression + directives + exclude-unknown honesty all match the fixtures)"
  return 0
}

# --- dispatch ---
if [ "$DO_SELFTEST" -eq 1 ]; then
  selftest; exit $?
fi

result=$(run_all "$TRACES")

if [ "$STDOUT" -eq 1 ]; then
  printf '%s\n' "$result"
else
  mkdir -p "$OUTDIR"
  # Write each agent's card to its own file; slug agent-id for filesystem safety.
  printf '%s' "$result" | jq -c '.[]' | while IFS= read -r card; do
    _aid=$(printf '%s' "$card" | jq -r '."agent.id" // "unknown"')
    _slug=$(printf '%s' "$_aid" | tr -c 'A-Za-z0-9._-' '_')
    printf '%s\n' "$card" | jq . > "$OUTDIR/$_slug.json"
    printf 'agent-scorecard: wrote %s/%s.json\n' "$OUTDIR" "$_slug"
  done
fi
