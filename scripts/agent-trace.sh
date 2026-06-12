#!/bin/sh
# agent-trace.sh — reference dev-time trace emitter (MP-3a.2).
# Turns a Claude Code JSONL transcript into an MP-3a-schema trace
# (docs/operations/agentic-ops.md). Transcript-native fields are solid; gh/git-
# correlated fields are best-effort (-> "unknown" when not derivable). It is a
# REFERENCE ADAPTER, not a conformance gate: it makes the trace exist, it does not
# judge behavior (that is MP-3b). sh + jq + gh, mirroring scripts/dora.sh.
#
# Usage:
#   scripts/agent-trace.sh <transcript.jsonl> [--agent-id ID] [--work-item ID] \
#       [--parent RUN_ID] [--price "IN,OUT"] [--out DIR] [--stdout] [--no-correlate]
#   scripts/agent-trace.sh --latest [flags]
#   scripts/agent-trace.sh --selftest
set -eu

AGENT_ID="claude-code"; WORK_ITEM="unknown"; PARENT="null"
PRICE=""; OUTDIR="traces"; STDOUT=0; CORRELATE=1; LATEST=0; TRANSCRIPT=""
DO_SELFTEST=0

# --- arg parsing ---
while [ $# -gt 0 ]; do
  case "$1" in
    --selftest)     DO_SELFTEST=1; shift ;;
    --latest)       LATEST=1; shift ;;
    --agent-id)     AGENT_ID="${2:?--agent-id needs a value}"; shift 2 ;;
    --work-item)    WORK_ITEM="${2:?--work-item needs a value}"; shift 2 ;;
    --parent)       PARENT="$2"; shift 2 ;;
    --price)        PRICE="${2:?--price needs IN,OUT}"; shift 2 ;;
    --out)          OUTDIR="${2:?--out needs a dir}"; shift 2 ;;
    --stdout)       STDOUT=1; shift ;;
    --no-correlate) CORRELATE=0; shift ;;
    -*)             printf 'unknown flag: %s\n' "$1" >&2; exit 2 ;;
    *)              TRANSCRIPT="$1"; shift ;;
  esac
done

# --- group-A extraction: tokens + timing (streaming; tiny awk aggregation) ---
extract_tokens_timing() {
  # echoes: "<in> <out> <cache_read> <start> <end>"
  _tok=$(jq -r 'select(.message.usage) | [
      (.message.usage.input_tokens // 0),
      (.message.usage.output_tokens // 0),
      (.message.usage.cache_read_input_tokens // 0)] | @tsv' "$1" \
    | awk '{i+=$1; o+=$2; c+=$3} END{printf "%d %d %d", i, o, c}')
  _times=$(jq -r 'select(.timestamp) | .timestamp' "$1" | sort)
  _start=$(printf '%s\n' "$_times" | head -1)
  _end=$(printf '%s\n' "$_times" | tail -1)
  printf '%s %s %s' "$_tok" "$_start" "$_end"
}

# --- group-A extraction: tool steps (two-stage: stream-extract -> slurp-join) ---
# Stage 1 streams the big transcript into two small NDJSON streams; stage 2 slurps
# (small) and joins tool_use to tool_result by id, preserving tool_use order.
extract_steps() {
  _uses=$(jq -c 'select(.message.content) | .message.content[]?
      | select(.type=="tool_use") | {id, name}' "$1")
  _results=$(jq -c 'select(.message.content) | .message.content[]?
      | select(.type=="tool_result")
      | {tid: .tool_use_id, err: (.is_error // false),
         denied: ((.is_error // false) and
                  ((.content|tostring|ascii_downcase) | test("denied")) and
                  ((.content|tostring|ascii_downcase) | test("guard|control-plane|deny")))}' "$1")
  # join: build a {tid: {err,denied}} map from results, map over uses in order.
  _map=$(mktemp) || _map="/tmp/_at_map.$$"
  printf '%s\n' "$_results" | jq -s '
      (reduce .[] as $r ({}; .[$r.tid] = {err:$r.err, denied:$r.denied})) as $m
      | $m' > "$_map" 2>/dev/null || printf '{}' > "$_map"
  printf '%s\n' "$_uses" | jq -s --slurpfile m "$_map" '
      ($m[0] // {}) as $res
      | [ .[] | . as $u | ($res[$u.id] // {err:false,denied:false}) as $r
          | {name: $u.name,
             outcome: (if $r.denied then "denied" elif $r.err then "error" else "ok" end),
             retries: 0} ]'
  rm -f "$_map" 2>/dev/null || true
}

compute_cost() {  # $1=in $2=out ; cost only when --price "IN,OUT" (per-Mtok) is given.
  # No built-in model->price table: prices drift and baking them into the kit is
  # maintenance debt. Tokens are always emitted (the objective fact); cost is
  # "unknown" unless the caller supplies --price. (YAGNI; honest over stale.)
  [ -n "$PRICE" ] || { printf 'unknown'; return; }
  _pin=${PRICE%,*}; _pout=${PRICE#*,}
  awk -v i="$1" -v o="$2" -v pi="$_pin" -v po="$_pout" \
    'BEGIN{printf "%.4f", (i/1000000*pi)+(o/1000000*po)}'
}

correlate() {  # best-effort gh/git; never fail the run
  command -v gh >/dev/null 2>&1 || return 0
  _br=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return 0
  _j=$(gh pr view "$_br" --json number,url,reviews 2>/dev/null) || return 0
  [ -n "$_j" ] || return 0
  _pr=$(printf '%s' "$_j" | jq -r '.url // "unknown"')
  _reviews=$(printf '%s' "$_j" | jq -r '.reviews | length | tostring')
  _state=$(gh pr view "$_br" --json state --jq '.state' 2>/dev/null || printf '')
  case "$_state" in MERGED) _outcome="completed";; OPEN) _outcome="handoff";; *) _outcome="unknown";; esac
}

# --- assemble the trace JSON (jq builds it; never hand-build JSON in sh) ---
emit() {
  _t="$1"
  # Pad with empty trailing fields so $4/$5 stay bound under `set -u` even when the
  # transcript has no timestamps (start/end collapse to empty — compacted transcripts).
  set -- $(extract_tokens_timing "$_t") "" "" ""
  _in=${1:-0}; _out=${2:-0}; _cache=${3:-0}; _start=${4:-}; _end=${5:-}
  _steps=$(extract_steps "$_t")
  _run=$(jq -r 'select(.sessionId) | .sessionId' "$_t" | head -1)
  [ -n "$_run" ] || _run=$(basename "$_t" .jsonl)
  _cost=$(compute_cost "$_in" "$_out")    # echoes a number or the string unknown

  # correlation (group B) — best-effort; "unknown" unless --correlate succeeds
  _pr="unknown"; _reviews="unknown"; _outcome="unknown"
  if [ "$CORRELATE" -eq 1 ]; then correlate; fi   # sets _pr/_reviews/_outcome

  jq -n \
    --arg agent "$AGENT_ID" --arg run "$_run" --arg wi "$WORK_ITEM" \
    --arg parent "$PARENT" \
    --arg start "$_start" --arg end "$_end" \
    --argjson tin "$_in" --argjson tout "$_out" --argjson tcache "$_cache" \
    --arg cost "$_cost" \
    --arg pr "$_pr" --arg reviews "$_reviews" --arg outcome "$_outcome" \
    --argjson steps "$_steps" '
    {
      "agent.id": $agent, "run.id": $run, "work_item.id": $wi,
      "parent.run.id": (if $parent == "null" then null else $parent end),
      start: $start, end: $end,
      tokens: {in: $tin, out: $tout, cache_read: $tcache},
      cost: ($cost | (tonumber? // .)),
      outcome: $outcome, "pr.ref": $pr, "review.rounds": ($reviews | (tonumber? // .)),
      "gates.hit": [], "gates.skipped": "unknown", "tests.written": "unknown",
      steps: $steps
    }'
}

selftest() {
  st_fail=0
  fixture="$(dirname "$0")/fixtures/agent-trace-sample.jsonl"
  CORRELATE=0
  out=$(emit "$fixture")
  # token sums (fixture: in=150, out=30, cache=5)
  [ "$(printf '%s' "$out" | jq -r '.tokens.in')" = "150" ]  || { printf 'selftest FAIL: tokens.in\n'; st_fail=1; }
  [ "$(printf '%s' "$out" | jq -r '.tokens.out')" = "30" ]  || { printf 'selftest FAIL: tokens.out\n'; st_fail=1; }
  [ "$(printf '%s' "$out" | jq -r '.tokens.cache_read')" = "5" ] || { printf 'selftest FAIL: cache\n'; st_fail=1; }
  # required-core keys present
  for k in '"run.id"' '"agent.id"' '"start"' '"end"' '"outcome"' '"steps"'; do
    [ "$(printf '%s' "$out" | jq -e "has(${k})" 2>/dev/null)" = "true" ] || { printf 'selftest FAIL: missing %s\n' "$k"; st_fail=1; }
  done
  # step outcomes: 4 steps, ok/ok/error/denied in order
  [ "$(printf '%s' "$out" | jq -r '.steps | length')" = "4" ] || { printf 'selftest FAIL: step count\n'; st_fail=1; }
  [ "$(printf '%s' "$out" | jq -r '.steps[2].outcome')" = "error" ]  || { printf 'selftest FAIL: error step\n'; st_fail=1; }
  [ "$(printf '%s' "$out" | jq -r '.steps[3].outcome')" = "denied" ] || { printf 'selftest FAIL: denied step\n'; st_fail=1; }
  [ "$(printf '%s' "$out" | jq -r '.["run.id"]')" = "sess-FIXTURE-001" ] || { printf 'selftest FAIL: run.id\n'; st_fail=1; }
  if [ "$st_fail" -ne 0 ]; then printf 'agent-trace --selftest: FAIL\n' >&2; return 1; fi
  printf 'agent-trace --selftest: OK (tokens/steps/outcomes/run.id all match the fixture)\n'
  return 0
}

# --- resolve --latest ---
resolve_latest() {
  _slug=$(pwd | sed 's|/|-|g' | sed 's|^-||')
  _dir="${CLAUDE_PROJECT_DIR:-$HOME/.claude/projects/$_slug}"
  _f=$(ls -t "$_dir"/*.jsonl 2>/dev/null | head -1) || true
  [ -n "$_f" ] || { printf 'agent-trace: no transcripts found in %s\n' "$_dir" >&2; exit 1; }
  printf '%s' "$_f"
}

# --- dispatch ---
if [ "$DO_SELFTEST" -eq 1 ]; then
  selftest; exit $?
fi

if [ "$LATEST" -eq 1 ]; then
  TRANSCRIPT=$(resolve_latest)
fi

[ -n "$TRANSCRIPT" ] || { printf 'usage: agent-trace.sh <transcript.jsonl> [flags] | --latest [flags] | --selftest\n' >&2; exit 2; }
[ -f "$TRANSCRIPT" ] || { printf 'agent-trace: transcript not found: %s\n' "$TRANSCRIPT" >&2; exit 1; }

if [ "$STDOUT" -eq 1 ]; then
  emit "$TRANSCRIPT"
else
  mkdir -p "$OUTDIR"
  _outrun=$(jq -r 'select(.sessionId) | .sessionId' "$TRANSCRIPT" | head -1)
  [ -n "$_outrun" ] || _outrun=$(basename "$TRANSCRIPT" .jsonl)
  # Slug the filename: sessionId is untrusted-ish — a '../' or '/' must not escape $OUTDIR.
  # (The trace's run.id field still carries the true, unslugged sessionId.)
  _outrun=$(printf '%s' "$_outrun" | tr -c 'A-Za-z0-9._-' '_')
  emit "$TRANSCRIPT" > "$OUTDIR/$_outrun.json"
  printf 'agent-trace: wrote %s/%s.json\n' "$OUTDIR" "$_outrun"
fi
