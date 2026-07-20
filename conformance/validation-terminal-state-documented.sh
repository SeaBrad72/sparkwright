#!/bin/sh
# validation-terminal-state-documented.sh — CP-7 Slice 6 / K6.
# Verifies the review loop documents the FAITHFUL-FAILURE third terminal state and that the
# two load-bearing surfaces stay cross-surface coherent: skills/review/SKILL.md (the reviewing
# craft) and templates/TASK-CONTEXT-CONTRACT-TEMPLATE.md (the declared-class structural input).
# HONEST CEILING: proves the doctrine is documented + cross-surface-coherent + non-vacuously
# locked; it does NOT prove a live reviewer applies FAITHFUL-FAILURE correctly (un-gateable).
# What it changes: read-only — greps two tracked surfaces for the FAITHFUL-FAILURE review
#                  terminal-state doctrine + the TCC validation-class declaration; mutates nothing.
# Guardrails: non-vacuous — --selftest strips each load-bearing marker from a fixture copy and
#             requires RED with the specific FAIL label (not just a non-zero exit — Slice-3 scar).
# Usage: sh conformance/validation-terminal-state-documented.sh [--selftest]
# Exit: 0 = documented · 1 = a marker missing / a mutant survived · 2 = bad usage. POSIX sh; dash-clean.
set -eu

# Anchor at repo root so the relative surface paths resolve regardless of caller cwd.
HERE=$(CDPATH='' cd "$(dirname "$0")" && pwd)
cd "$HERE/.." 2>/dev/null || true

REVIEW="skills/review/SKILL.md"
TCC="templates/TASK-CONTEXT-CONTRACT-TEMPLATE.md"

want() {  # want <file> <regex> <label>
  if grep -Eq "$2" "$1" 2>/dev/null; then echo "PASS: $3"; return 0; fi
  echo "FAIL: $3 (missing in $1)"; return 1
}

run() {  # run <root> — assert both surfaces carry the doctrine markers under <root>
  _r="${1:-.}"; f=0
  want "$_r/$REVIEW" 'terminal state — FAITHFUL-FAILURE'         "review: FAITHFUL-FAILURE terminal state"    || f=1
  want "$_r/$REVIEW" 'subject-under-test'                        "review: anti-contamination clause"          || f=1
  want "$_r/$REVIEW" 'originating backlog'                       "review: route-to-originating-backlog"       || f=1
  want "$_r/$REVIEW" 'faithful methodology is the precondition'  "review: faithful-methodology precondition"  || f=1
  want "$_r/$REVIEW" 'validation / field-test'                   "review: gated on declared TCC class"        || f=1
  want "$_r/$REVIEW" 'Task Context Contract'                     "review: names the TCC as the class source"  || f=1
  want "$_r/$TCC"    'validation / field-test'                   "tcc: validation class declared"             || f=1
  want "$_r/$TCC"    'subject-under-test'                        "tcc: subject-under-test prohibition"        || f=1
  return $f
}

# ── --selftest — the NON-VACUITY heart: strip ONE load-bearing marker from a fixture copy of
#    BOTH surfaces and require the check goes RED with the SPECIFIC FAIL label (Slice-3 scar:
#    assert the message, not just the exit code, so a usage/other non-zero exit cannot fake a
#    kill). Each mutation targets exactly one marker line; the load-bearing property is proven
#    by commenting out a want() and confirming the matching mutant then SURVIVES.
#
#    ORACLE-REGION DISCIPLINE (non-vacuity.sh / MARK): the meta-sweep mutates only lines BEFORE
#    the `selftest()` marker (the check-logic region: want/run) and emits everything at/after it
#    VERBATIM. The kill assertions therefore MUST live at/after this marker — so `_stage` and
#    `_mutate` are defined BELOW selftest() (POSIX resolves their calls at dispatch time). Placing
#    them above the marker let the sweep neuter their own `return 1`, making the selftest vacuous. ──
selftest() {
  st=0
  SELFBASE=$(mktemp -d) || { echo "SELFTEST FAIL: mktemp -d failed"; return 1; }
  # shellcheck disable=SC2064 # expand SELFBASE now — fixed for the life of the process (no disk leak)
  trap "rm -rf '$SELFBASE'" EXIT

  # Liveness anchor: an UNMUTATED copy of both surfaces must be GREEN (rc 0) — proves the check
  # CAN pass, so a RED mutant below is a real kill and not a staging artifact.
  _stage "$SELFBASE/live" || { echo "SELFTEST FAIL: liveness — could not stage fixture"; return 1; }
  if _out=$(run "$SELFBASE/live" 2>&1); then
    echo "SELFTEST PASS: liveness — unmutated fixture GREEN"
  else
    echo "SELFTEST FAIL: liveness — unmutated fixture RED: $_out"; st=1
  fi

  _mutate A "$REVIEW" 'subject-under-test'                       "review: anti-contamination clause"          || st=1
  _mutate B "$REVIEW" 'faithful methodology is the precondition' "review: faithful-methodology precondition"  || st=1
  _mutate C "$REVIEW" 'originating backlog'                      "review: route-to-originating-backlog"       || st=1
  _mutate D "$TCC"    'validation / field-test'                  "tcc: validation class declared"             || st=1
  _mutate E "$REVIEW" 'terminal state — FAITHFUL-FAILURE'        "review: FAITHFUL-FAILURE terminal state"     || st=1
  _mutate F "$REVIEW" 'validation / field-test'                  "review: gated on declared TCC class"         || st=1
  _mutate G "$REVIEW" 'Task Context Contract'                    "review: names the TCC as the class source"   || st=1
  _mutate H "$TCC"    'subject-under-test'                       "tcc: subject-under-test prohibition"         || st=1

  if [ "$st" = 0 ]; then
    echo "SELFTEST OK: 8 mutants killed, liveness green"; return 0
  fi
  echo "SELFTEST FAIL: validation-terminal-state — a mutant survived or liveness broke"; return 1
}

_stage() {  # <destdir> — copy both surfaces into <destdir> at their relative paths
  _d=$1
  mkdir -p "$_d/skills/review" "$_d/templates" || return 1
  cp "$REVIEW" "$_d/$REVIEW" || return 1
  cp "$TCC"    "$_d/$TCC"    || return 1
}

_mutate() {  # <id> <file-rel> <strip-marker> <expected-FAIL-label>
  _id=$1; _mf=$2; _strip=$3; _label=$4
  _fx="$SELFBASE/mut$_id"
  _stage "$_fx" || { echo "SELFTEST FAIL: mutant $_id — could not stage fixture"; return 1; }
  grep -vF "$_strip" "$_fx/$_mf" > "$_fx/$_mf.tmp" && mv "$_fx/$_mf.tmp" "$_fx/$_mf"
  if grep -qF "$_strip" "$_fx/$_mf"; then
    echo "SELFTEST FAIL: mutant $_id setup — marker '$_strip' still present after strip"; return 1
  fi
  if _out=$(run "$_fx" 2>&1); then
    echo "SELFTEST FAIL: mutant $_id — check still PASSED after stripping '$_strip' (VACUOUS): $_out"; return 1
  fi
  if printf '%s\n' "$_out" | grep -qF "FAIL: $_label"; then
    echo "SELFTEST PASS: mutant $_id — stripping '$_strip' -> RED via '$_label'"; return 0
  fi
  echo "SELFTEST FAIL: mutant $_id — went RED but WITHOUT the '$_label' FAIL label: $_out"; return 1
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "") if run "."; then
        echo "OK: validation-terminal-state — FAITHFUL-FAILURE doctrine documented + cross-surface-coherent."
        exit 0
      fi
      echo "FAIL: validation-terminal-state — a load-bearing marker is missing (see above)."; exit 1 ;;
  *)  echo "usage: validation-terminal-state-documented.sh [--selftest]" >&2; exit 2 ;;
esac
