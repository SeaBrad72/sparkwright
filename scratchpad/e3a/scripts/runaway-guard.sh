#!/bin/sh
# runaway-guard.sh — E4d executable runaway circuit-breaker (harness-neutral).
#
# The kit cannot MEASURE tokens (the harness/LLM-API does); it ENFORCES a ceiling on REPORTED
# usage at the orchestration seam and halts the loop. The platform LLM-API cap is the hard ceiling
# ABOVE this. The ceiling config (.kit/budget.conf) + this script are control-plane (agent-immutable);
# the tally (.kit-run/tally) is best-effort runtime state (platform cap is the backstop if defeated).
#
# Usage:
#   runaway-guard.sh step  --tokens N --agents N   # record this step's usage, then check
#   runaway-guard.sh check                         # verdict only
#   runaway-guard.sh reset                         # start a fresh run (clear tally)
# Exit: 0 continue (WARN on stderr at >=WARN_PCT) | 1 STOP (ceiling breached) | 2 UNVERIFIED (bad config).
set -eu

CONFIG="${RUNAWAY_BUDGET_CONFIG:-.kit/budget.conf}"
TALLY="${RUNAWAY_TALLY:-.kit-run/tally}"

die2() { printf '%s\n' "$*" >&2; exit 2; }

cfg() {  # cfg KEY -> first matching value (KEY=VALUE, ignores # comments); empty if absent
  [ -f "$CONFIG" ] || return 1
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\([^#[:space:]]*\).*/\1/p" "$CONFIG" | head -1
}

load_config() {
  [ -f "$CONFIG" ] || die2 "2: config missing: $CONFIG (fail-closed)"
  MAX_TOKENS=$(cfg MAX_TOKENS || true)
  MAX_STEPS=$(cfg MAX_STEPS || true)
  MAX_AGENTS=$(cfg MAX_AGENTS || true)
  WARN_PCT=$(cfg WARN_PCT || true);          WARN_PCT="${WARN_PCT:-80}"
  COST_PER_1K=$(cfg COST_PER_1K_USD || true); COST_PER_1K="${COST_PER_1K:-0}"
  for v in MAX_TOKENS MAX_STEPS MAX_AGENTS WARN_PCT; do
    eval "_val=\${$v:-}"
    # shellcheck disable=SC2154
    case "$_val" in ''|*[!0-9]*) die2 "2: config $v not a non-negative integer: '$_val' (fail-closed)";; esac
  done
}

record() { mkdir -p "$(dirname "$TALLY")"; printf '%s %s\n' "$1" "$2" >> "$TALLY"; }

sums() {  # echoes "TOKENS STEPS AGENTS"
  if [ -f "$TALLY" ]; then awk '{t+=$1; a+=$2; n++} END{printf "%d %d %d\n", t+0, n+0, a+0}' "$TALLY"
  else echo "0 0 0"; fi
}

check() {
  load_config
  # shellcheck disable=SC2046
  set -- $(sums); cur_t=$1; cur_s=$2; cur_a=$3
  breach=""; warn=""
  for d in "tokens $cur_t $MAX_TOKENS" "steps $cur_s $MAX_STEPS" "agents $cur_a $MAX_AGENTS"; do
    # shellcheck disable=SC2086
    set -- $d; nm=$1; cur=$2; max=$3
    [ "$max" -gt 0 ] || continue                 # max=0 disables the dimension
    if [ "$cur" -ge "$max" ]; then breach="$breach $nm($cur/$max)"
    elif [ $(( cur * 100 )) -ge $(( max * WARN_PCT )) ]; then warn="$warn $nm($cur/$max)"; fi
  done
  if [ -n "$breach" ]; then
    printf 'STOP: runaway ceiling breached:%s [~$%s]\n' "$breach" \
      "$(awk -v t="$cur_t" -v r="$COST_PER_1K" 'BEGIN{printf "%.4f", (t/1000)*r}')" >&2
    exit 1
  fi
  [ "$WARN_PCT" -gt 0 ] && [ -n "$warn" ] && printf 'WARN: approaching ceiling (>=%s%%):%s\n' "$WARN_PCT" "$warn" >&2
  exit 0
}

cmd="${1:-}"; [ $# -gt 0 ] && shift
tokens=0; agents=0
while [ $# -gt 0 ]; do
  case "$1" in
    --tokens) [ $# -ge 2 ] || die2 "2: --tokens requires a value"; tokens="$2"; shift 2 ;;
    --agents) [ $# -ge 2 ] || die2 "2: --agents requires a value"; agents="$2"; shift 2 ;;
    --config) [ $# -ge 2 ] || die2 "2: --config requires a value"; CONFIG="$2"; shift 2 ;;
    --tally)  [ $# -ge 2 ] || die2 "2: --tally requires a value";  TALLY="$2";  shift 2 ;;
    *) die2 "2: unknown arg: $1" ;;
  esac
done

case "$cmd" in
  step)
    case "$tokens" in ''|*[!0-9]*) die2 "2: --tokens/--agents must be non-negative integers";; esac
    case "$agents" in ''|*[!0-9]*) die2 "2: --tokens/--agents must be non-negative integers";; esac
    record "$tokens" "$agents"; check ;;
  check) check ;;
  reset) rm -f "$TALLY" ;;
  *) die2 "2: usage: runaway-guard.sh step|check|reset [--tokens N] [--agents N]" ;;
esac
