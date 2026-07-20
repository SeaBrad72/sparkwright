#!/bin/sh
# feedback-link-lifecycle-documented.sh — CP-7 Slice 8 / K13.
# Verifies the KIT-FEEDBACK live-log link lifecycle is documented UPSTREAM so operators never
# author a link that check-links.sh must reject. The friction log stays live-but-untracked until
# the end-of-run synthesis commit, yet check-links resolves relative links against the tracked set
# (git ls-files); a BACKLOG/field-report entry linking the log before that commit is a broken link.
# The fix is doctrine, not a check change: reference findings by plain K-id text until the log is
# tracked. This locks that doctrine on two surfaces:
#   templates/KIT-FEEDBACK-TEMPLATE.md — the log's own link-lifecycle note (KF-1 + KF-2)
#   templates/BACKLOG-TEMPLATE.md      — the "How to use" citation guidance (BL-1)
# HONEST CEILING: proves the doctrine is documented + non-vacuously locked; it does NOT prove an
# operator obeys it live (un-gateable) — check-links.sh remains the runtime backstop.
# What it changes: read-only — greps two tracked templates for the link-lifecycle markers; mutates
#                  nothing.
# Guardrails: non-vacuous — --selftest strips each load-bearing marker from a fixture copy and
#             requires RED with the specific FAIL label (not just a non-zero exit — Slice-3 scar).
# Usage: sh conformance/feedback-link-lifecycle-documented.sh [--selftest]
# Exit: 0 = documented · 1 = a marker missing / a mutant survived · 2 = bad usage. POSIX sh; dash-clean.
set -eu

# Anchor at repo root so the relative surface paths resolve regardless of caller cwd.
HERE=$(CDPATH='' cd "$(dirname "$0")" && pwd)
cd "$HERE/.." 2>/dev/null || true

FEEDBACK="templates/KIT-FEEDBACK-TEMPLATE.md"
BACKLOG="templates/BACKLOG-TEMPLATE.md"

# The three load-bearing markers (exact substrings — the doctrine prose carries them verbatim).
KF1='untracked until the end-of-run synthesis commit'
KF2='cite it by its K-id as plain text, never a Markdown link'
BL1='cite the finding by its plain K-id until the synthesis commit tracks'

want() {  # want <file> <fixed-substring> <label>
  if grep -Fq "$2" "$1" 2>/dev/null; then echo "PASS: $3"; return 0; fi
  echo "FAIL: $3 (missing in $1)"; return 1
}

run() {  # run <root> — assert both templates carry the link-lifecycle markers under <root>
  _r="${1:-.}"; f=0
  want "$_r/$FEEDBACK" "$KF1" "feedback: log untracked-until-synthesis-commit marker" || f=1
  want "$_r/$FEEDBACK" "$KF2" "feedback: cite-by-K-id-not-a-link marker"              || f=1
  want "$_r/$BACKLOG"  "$BL1" "backlog: cite-plain-K-id-until-synthesis marker"       || f=1
  return $f
}

# ── --selftest — the NON-VACUITY heart: strip ONE load-bearing marker line from a fixture copy of
#    the relevant template and require the check goes RED with the SPECIFIC FAIL label (Slice-3
#    scar: assert the message, not just the exit code, so a usage/other non-zero exit cannot fake a
#    kill). Each mutation targets exactly one marker line; the load-bearing property is proven by
#    commenting out a want() and confirming the matching mutant then SURVIVES.
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

  # Liveness anchor: an UNMUTATED copy of both templates must be GREEN (rc 0) — proves the check
  # CAN pass, so a RED mutant below is a real kill and not a staging artifact.
  _stage "$SELFBASE/live" || { echo "SELFTEST FAIL: liveness — could not stage fixture"; return 1; }
  if _out=$(run "$SELFBASE/live" 2>&1); then
    echo "SELFTEST PASS: liveness — unmutated fixture GREEN"
  else
    echo "SELFTEST FAIL: liveness — unmutated fixture RED: $_out"; st=1
  fi

  _mutate A "$FEEDBACK" "$KF1" "feedback: log untracked-until-synthesis-commit marker" || st=1
  _mutate B "$FEEDBACK" "$KF2" "feedback: cite-by-K-id-not-a-link marker"              || st=1
  _mutate C "$BACKLOG"  "$BL1" "backlog: cite-plain-K-id-until-synthesis marker"       || st=1

  if [ "$st" = 0 ]; then
    echo "SELFTEST OK: 3 mutants killed, liveness green"; return 0
  fi
  echo "SELFTEST FAIL: feedback-link-lifecycle — a mutant survived or liveness broke"; return 1
}

_stage() {  # <destdir> — copy both templates into <destdir> at their relative paths
  _d=$1
  mkdir -p "$_d/templates" || return 1
  cp "$FEEDBACK" "$_d/$FEEDBACK" || return 1
  cp "$BACKLOG"  "$_d/$BACKLOG"  || return 1
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
        echo "OK: feedback-link-lifecycle — KIT-FEEDBACK link-lifecycle doctrine documented on both surfaces."
        exit 0
      fi
      echo "FAIL: feedback-link-lifecycle — a load-bearing marker is missing (see above)."; exit 1 ;;
  *)  echo "usage: feedback-link-lifecycle-documented.sh [--selftest]" >&2; exit 2 ;;
esac
