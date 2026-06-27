#!/bin/sh
# escalate.sh — E3-escalation human-in-the-loop seam (harness-neutral FLOOR).
# On a governed breach the orchestration loop RAISES a plain-language, role-addressed
# escalation record and PAUSES; it resumes only on a human-ratified verdict, FAIL-CLOSED
# on none/invalid. The TRUSTED caller (orchestrator-run.sh) stamps the verdict/ratifier
# onto the trace from the verdict FILE — never from agent data. sh + jq. Not a gate.
#
#   escalate.sh raise   <id> <trigger> <ratifier_role> <summary>  -> writes pending record; prints path
#   escalate.sh await   <id>                                      -> rc 0 if a verdict file exists, else 1
#   escalate.sh resolve <id>                                      -> prints option (rc 0) | fail-closed (rc 1)
#   escalate.sh --selftest                                        -> self-isolating assertions
#
# Record + verdict live under $KIT_ESCALATION_DIR (default .kit-run/escalations).
set -eu

_esc_dir() { printf '%s' "${KIT_ESCALATION_DIR:-${KIT_RUN_DIR:-.kit-run}/escalations}"; }

now() { _n=$(date +%s%N 2>/dev/null); case "$_n" in *N|"") printf '%s000000000' "$(date +%s)";; *) printf '%s' "$_n";; esac; }
slug() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'; }

# Allowed verdict options per trigger. The only WIRED trigger is runaway-breach.
# B-ready: a future trigger (e.g. tier-exceeded) adds a case here with its own option set.
_options_for() {
  case "$1" in
    runaway-breach) printf 'raise-ceiling abort amend' ;;
    *)              printf '' ;;   # unknown trigger -> empty set -> resolve fail-closes
  esac
}

raise() {  # <id> <trigger> <ratifier_role> <summary>
  [ "$#" -eq 4 ] || { echo "escalate raise: need <id> <trigger> <ratifier_role> <summary>" >&2; return 2; }
  id=$(slug "$1"); trigger=$2; role=$3; summary=$4
  esc_dir=$(_esc_dir)
  mkdir -p "$esc_dir"
  rec="$esc_dir/$id.json"
  opts=$(_options_for "$trigger")
  optjson=$(printf '%s' "$opts" | tr ' ' '\n' | grep -v '^$' | jq -R . | jq -cs .)
  jq -n --arg id "$id" --arg trigger "$trigger" --arg role "$role" --arg summary "$summary" \
        --arg created "$(now)" --argjson options "$optjson" \
    '{id:$id, state:"pending", trigger:$trigger, ratifier_role:$role,
      summary:$summary, detail:"", risk:"", reversibility:"", recommendation:"",
      options:$options, context_ref:"", created_unix_nano:($created|tonumber)}' > "$rec"
  printf '%s\n' "$rec"
}

await() {  # <id> -> rc 0 iff a verdict file exists
  id=$(slug "$1"); esc_dir=$(_esc_dir); [ -f "$esc_dir/$id.verdict" ]
}

resolve() {  # <id> -> prints option on success; fail-closed (rc 1) otherwise
  id=$(slug "$1"); esc_dir=$(_esc_dir); rec="$esc_dir/$id.json"; vf="$esc_dir/$id.verdict"
  [ -f "$rec" ] || { echo "escalate resolve: no record for $id — fail-closed" >&2; return 1; }
  [ -f "$vf" ]  || { echo "escalate resolve: no verdict for $id — fail-closed (stay halted)" >&2; return 1; }
  opt=$(jq -r '.option // empty'      "$vf" 2>/dev/null || true)
  rat=$(jq -r '.ratifier_id // empty' "$vf" 2>/dev/null || true)
  [ -n "$opt" ] || { echo "escalate resolve: verdict has no option — fail-closed" >&2; return 1; }
  [ -n "$rat" ] || { echo "escalate resolve: verdict has no ratifier_id — fail-closed" >&2; return 1; }
  jq -e --arg o "$opt" '.options | index($o) != null' "$rec" >/dev/null 2>&1 \
    || { echo "escalate resolve: option '$opt' not in record.options — fail-closed" >&2; return 1; }
  # single-use: consume the verdict so a one-time human approval cannot be REPLAYED on a later
  # re-run of the same (deterministic) escalation id. await() keys on $vf, so a consumed verdict
  # forces a fresh pause + a fresh human ratification next time. Renamed (not deleted) for audit.
  # FAIL-CLOSED if the consume fails: the dir was writable when raise() wrote the record, so a
  # non-writable dir here is anomalous — refuse to ratify rather than leave a replayable verdict.
  mv "$vf" "$vf.consumed" || { echo "escalate resolve: could not consume verdict (replay risk) — fail-closed" >&2; return 1; }
  printf '%s\n' "$opt"
}

selftest() {
  fail=0; d=$(mktemp -d); export KIT_ESCALATION_DIR="$d"
  # raise writes a pending record with the required fields + non-empty summary + the option set
  rec=$(raise "t1.alpha" runaway-breach security-owner "Ceiling hit building 'alpha'. Raise/abort/amend?")
  [ -f "$rec" ] || { echo "FAIL: raise did not write a record"; fail=1; }
  [ "$(jq -r '.state' "$rec")" = "pending" ] || { echo "FAIL: state not pending"; fail=1; }
  [ -n "$(jq -r '.summary' "$rec")" ] || { echo "FAIL: empty summary"; fail=1; }
  [ "$(jq -r '.ratifier_role' "$rec")" = "security-owner" ] || { echo "FAIL: ratifier_role not set"; fail=1; }
  [ "$(jq -c '.options' "$rec")" = '["raise-ceiling","abort","amend"]' ] || { echo "FAIL: wrong option set"; fail=1; }
  # await: no verdict yet -> rc 1 (paused)
  await "t1.alpha" && { echo "FAIL: await true with no verdict (not fail-closed)"; fail=1; }
  # resolve with no verdict -> fail-closed
  resolve "t1.alpha" >/dev/null 2>&1 && { echo "FAIL: resolve succeeded with no verdict"; fail=1; }
  # place a VALID verdict -> await rc 0, resolve prints the option
  printf '{"option":"raise-ceiling","note":"ok","ratifier_id":"owner@x"}' > "$d/t1.alpha.verdict"
  await "t1.alpha" || { echo "FAIL: await false after a verdict written"; fail=1; }
  [ "$(resolve "t1.alpha")" = "raise-ceiling" ] || { echo "FAIL: resolve did not print raise-ceiling"; fail=1; }
  # DISALLOWED option -> fail-closed
  printf '{"option":"delete-prod","ratifier_id":"owner@x"}' > "$d/t1.alpha.verdict"
  resolve "t1.alpha" >/dev/null 2>&1 && { echo "FAIL: disallowed option accepted"; fail=1; }
  # MISSING ratifier -> fail-closed
  printf '{"option":"abort"}' > "$d/t1.alpha.verdict"
  resolve "t1.alpha" >/dev/null 2>&1 && { echo "FAIL: missing ratifier accepted"; fail=1; }
  rm -rf "$d"
  [ "$fail" -eq 0 ] && { echo "OK: escalate --selftest (raise schema + await pause + resolve + fail-closed x3)"; return 0; }
  echo "FAIL: escalate --selftest"; return 1
}

case "${1:-}" in
  raise)      shift; raise "$@" ;;
  await)      shift; await "$@" ;;
  resolve)    shift; resolve "$@" ;;
  --selftest) selftest; exit $? ;;
  *) echo "usage: escalate.sh raise|await|resolve <id> ... | --selftest" >&2; exit 2 ;;
esac
