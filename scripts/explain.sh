#!/bin/sh
# explain.sh — learner-facing "why does this gate exist?" reader.
# Adds no enforcement; pure teaching/surfacing over rationale that already exists
# (docs/why-gates.md is the single source of truth; this is a convenience reader).
# READ-ONLY, ADVISORY, MODE-BLIND: it never reads the process mode or any declaration,
# and teaches identically in every mode. POSIX sh; dash-clean.
#
# Usage:
#   sparkwright explain <topic>     # print one topic's rationale block
#   sparkwright explain --list      # list every topic + its "Applies IF" line
#   sparkwright explain             # usage + list (exit 2)
#   sparkwright explain --selftest  # render-contract self-test (deterministic, fixture-backed)
set -eu
here=$(dirname "$0")
DOC="${EXPLAIN_DOC:-$here/../docs/why-gates.md}"

list_topics() {
  # "<slug> — <Applies IF value>" per topic, in document order.
  awk '
    /^## /        { slug = substr($0, 4); have = 1; next }
    have && /^Applies IF:/ { print slug "  —  " substr($0, 13); have = 0 }
  ' "$DOC"
}

render() {  # $1 = slug ; prints the block, returns 1 if not found
  _t=$1
  _out=$(awk -v t="$_t" '
    $0 == "## " t { f = 1; print "▸ " substr($0, 4); next }
    /^## /        { if (f) exit }
    f             { print "    " $0 }
  ' "$DOC")
  [ -n "$_out" ] || return 1
  printf '%s\n' "$_out"
}

usage() {
  echo "usage: sparkwright explain <topic> | --list" >&2
  echo "" >&2
  echo "topics:" >&2
  list_topics | sed 's/^/  /' >&2
}

selftest() {
  sfail=0
  _fx=$(mktemp)
  trap 'rm -f "$_fx"' EXIT INT TERM
  cat > "$_fx" <<'FX'
# Why these gates exist (fixture)

## threat-model
Applies IF: you declare Confidential/Restricted data
Why: naming the attacker's goal before you build is cheaper than finding it in prod.
Enforced by: conformance/privacy-ready.sh
Read more: DEVELOPMENT-STANDARDS.md §2

## evals
Applies IF: you add an evals/ dir or declare an AI feature
Why: without a regression threshold, model quality silently drifts.
Enforced by: conformance/eval-ready.sh
Read more: DEVELOPMENT-PROCESS.md §7
FX
  export EXPLAIN_DOC="$_fx"

  # known topic → all four labels render
  out=$(sh "$0" threat-model) || { echo "explain --selftest: FAIL (known topic non-zero)"; sfail=1; out=""; }
  for _lbl in "Applies IF:" "Why:" "Enforced by:" "Read more:"; do
    printf '%s\n' "$out" | grep -Fq "$_lbl" || { echo "explain --selftest: FAIL (missing label: $_lbl)"; sfail=1; }
  done
  printf '%s\n' "$out" | grep -Fq "privacy-ready.sh" || { echo "explain --selftest: FAIL (enforcer not rendered)"; sfail=1; }

  # --list enumerates both fixture slugs
  lst=$(sh "$0" --list) || { echo "explain --selftest: FAIL (--list non-zero)"; sfail=1; lst=""; }
  printf '%s\n' "$lst" | grep -Fq "threat-model" || { echo "explain --selftest: FAIL (--list missing threat-model)"; sfail=1; }
  printf '%s\n' "$lst" | grep -Fq "evals"        || { echo "explain --selftest: FAIL (--list missing evals)"; sfail=1; }

  # unknown topic → exit 2 (negative assertion via if-block; set -e safe)
  if sh "$0" no-such-topic >/dev/null 2>&1; then echo "explain --selftest: FAIL (unknown topic did not exit non-zero)"; sfail=1; fi
  rc=0; sh "$0" no-such-topic >/dev/null 2>&1 || rc=$?; [ "$rc" = "2" ] || { echo "explain --selftest: FAIL (unknown topic exit $rc, want 2)"; sfail=1; }

  # no-arg → exit 2
  rc=0; sh "$0" >/dev/null 2>&1 || rc=$?; [ "$rc" = "2" ] || { echo "explain --selftest: FAIL (no-arg exit $rc, want 2)"; sfail=1; }

  rm -f "$_fx"
  [ "$sfail" -eq 0 ] && { echo "explain --selftest: OK (render + list + unknown + no-arg)"; return 0; }
  echo "explain --selftest: FAIL"; return 1
}

# --selftest sets its own EXPLAIN_DOC fixture; handle it before the doc guard below.
if [ "${1:-}" = "--selftest" ]; then selftest; exit $?; fi

# A missing rationale doc is an install error, not a crash: fail cleanly with a clear
# message (and never run awk on a nonexistent file — which would both trip `set -e` on
# the unpiped --list path and leak awk's "can't open file" to stderr).
[ -f "$DOC" ] || { echo "explain: rationale source not found: $DOC" >&2; exit 2; }

case "${1:-}" in
  --list)     list_topics; exit 0 ;;
  "")         usage; exit 2 ;;
  -*)         echo "explain: unknown flag '$1'" >&2; usage; exit 2 ;;
  *)
    if render "$1"; then exit 0; fi
    echo "explain: no such topic '$1'" >&2
    echo "" >&2; echo "available topics:" >&2
    list_topics | sed 's/^/  /' >&2
    exit 2
    ;;
esac
