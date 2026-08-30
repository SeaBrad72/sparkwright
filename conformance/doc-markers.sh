#!/bin/sh
# doc-markers.sh — the TABLE-DRIVEN doc-marker checker (CONFORMANCE-DOC-FAMILIES-MERGE, D-240828-4).
#
# WHAT IT REPLACES. Four single-purpose checks (artifact-lineage-ready, gate-eval-secrets-ready,
# feedback-link-lifecycle-documented, validation-terminal-state-documented) each grepped a tracked
# document for marker phrases and, in --selftest, stripped each marker from a fixture copy and
# required RED with that marker's label. One shape, four copies. The shape lives here; the SUBJECT
# lives in conformance/doc-markers.tsv, so a new marker is a table row and the mutation discipline is
# generated rather than re-typed.
#
# HONEST CEILING (unchanged by the fold): a green run proves the document is PRESENT and still
# carries its marker phrases — not that the marked fields are FILLED, that the surrounding prose is
# true, or that anyone obeys the doctrine documented. Per-case ceilings are in the table.
#
# Usage:
#   sh conformance/doc-markers.sh <case>              real run: assert every row of <case>
#   sh conformance/doc-markers.sh --selftest [case]   liveness + one labelled mutant per row
#   sh conformance/doc-markers.sh <case> --selftest   the same (either argument order)
# Exit: 0 = markers present, or N/A (a `kit`-scope case off the kit tree) · 1 = a marker missing, a
#       mutant survived, or the table is malformed · 2 = usage. POSIX sh; dash-clean.
set -eu

HERE=$(CDPATH='' cd "$(dirname "$0")" && pwd)
cd "$HERE/.." 2>/dev/null || true
TSV="$HERE/doc-markers.tsv"
TAB=$(printf '\t')

# EXPECTED ROW COUNT PER CASE. A row silently lost (malformed, mis-cased case name, a stray edit)
# used to change only how many mutants the sweep reported — a number nobody reads. Pinned here, it
# changes the VERDICT instead. A case absent from this list is itself a FAIL, so a new case cannot
# land without its count.
DM_EXPECT='artifact-lineage:6 gate-eval-secrets:5 feedback-link-lifecycle:3 validation-terminal-state:8'

# dm_lint: the table is well-formed, or the check FAILS LOUDLY. A parser that skips what it cannot
# understand turns a malformed row into an unchecked marker and reports nothing — the one place this
# fold could have traded a real property for tidiness. Exactly 5 fields per row; every `file` cell
# repo-relative with no `..` (a table cell must not reach outside the tree); every `label` unique
# WITHIN its case, since the label is the kill identity the selftest asserts on and a duplicate makes
# two mutants indistinguishable.
dm_lint() {
  awk -F'\t' -v t="$TSV" -v x="$DM_EXPECT" '
    /^#/ || /^[[:space:]]*$/ { next }
    NF!=5 { printf "FAIL: doc-markers — malformed row %s:%d (%d fields, expected 5)\n", t, NR, NF; e=1; next }
    $2 ~ /\.\./ || $2 ~ /^\// { printf "FAIL: doc-markers — unsafe file cell %s:%d (%s)\n", t, NR, $2; e=1 }
    seen[$1 "\t" $4]++ { printf "FAIL: doc-markers — duplicate label %s:%d (case %s, label %s)\n", t, NR, $1, $4; e=1 }
    { n[$1]++ }
    END { for (c in n) { if (index(x, c ":" n[c] " ") == 0 && x !~ c ":" n[c] "$")
            { printf "FAIL: doc-markers — case %s has %d row(s); DM_EXPECT does not declare that count\n", c, n[c]; e=1 } }
          exit e }' "$TSV"
}

# dm_rows <case>: emit this case's rows as `file<TAB>regex<TAB>label<TAB>scope`.
dm_rows() { awk -F'\t' -v c="$1" 'BEGIN{OFS="\t"} /^#/{next} NF!=5{next} $1==c {print $2,$3,$4,$5}' "$TSV"; }

# dm_cases: emit each case name once, in table order.
dm_cases() { awk -F'\t' '/^#/{next} NF!=5{next} !seen[$1]++ {print $1}' "$TSV"; }

want() {  # want <file> <regex> <label>
  if grep -Eq "$2" "$1" 2>/dev/null; then echo "PASS: $3"; return 0; fi
  echo "FAIL: $3 (missing in $1)"; return 1
}

run() {  # run <case> <root> — assert every row of <case> against the tree at <root>
  _c=$1; _r=${2:-.}
  dm_lint >&2 || return 1
  _rows=$(dm_rows "$_c")
  if [ -z "$_rows" ]; then
    echo "FAIL: doc-markers — no table rows for case '$_c' (conformance/doc-markers.tsv)"; return 1
  fi

  # KIT-SCOPE N/A LATCH — keyed on the KIT MARKER ALONE, deliberately. A `kit`-scope case marks a
  # document the kit owns and export-prunes, so on an adopter tree (no docs/ROADMAP-KIT.md) there is
  # nothing to check and the case declines and says so. ON A KIT TREE IT BINDS: an ABSENT document
  # is a FAIL, which is what the retired checks did and what an "and the doc is missing too" clause
  # would have silently given away — a deleted template would have rendered N/A instead of RED.
  if printf '%s\n' "$_rows" | cut -f4 | grep -qx kit && [ ! -f "$_r/docs/ROADMAP-KIT.md" ]; then
    echo "$_c: N/A -- kit-self check (the marked document is the kit's own; not applicable outside the kit repo)"
    return 0
  fi

  _f=0; _n=0
  while IFS="$TAB" read -r _file _rx _lab _scope; do
    [ -n "$_file" ] || continue
    _n=$((_n+1))
    want "$_r/$_file" "$_rx" "$_lab" || _f=1
  done <<DM_RUN_EOF
$_rows
DM_RUN_EOF
  if [ "$_f" = 0 ]; then
    echo "$_c: OK -- $_n load-bearing marker(s) present. NOTE: markers being PRESENT is not the marked fields being FILLED, nor the documented doctrine being obeyed."
    return 0
  fi
  echo "FAIL: $_c -- a load-bearing marker is missing (see above)."
  return 1
}

# ── --selftest — the NON-VACUITY heart, GENERATED from the table. Per case: the row count matches
#    DM_EXPECT (a lost row changes the verdict); a liveness anchor on an unmutated fixture; one
#    mutant per row, stripping that row's regex and requiring RED WITH THAT ROW'S LABEL (Slice-3
#    scar: assert the message, not the exit code); and for a `kit`-scope case, both halves of the
#    N/A latch — off-kit declines, on-kit binds.
#
#    ORACLE-REGION DISCIPLINE (non-vacuity.sh / MARK): the meta-sweep mutates only lines BEFORE the
#    `selftest()` marker (the check-logic region: dm_lint/dm_rows/want/run) and emits everything
#    at/after it VERBATIM. The kill assertions therefore MUST live at/after this marker — so `_stage`
#    and `_mutate` are defined BELOW selftest() (POSIX resolves their calls at dispatch time).
#    Placing them above let the sweep neuter their own `return 1`, making the selftest vacuous. ──
selftest() {
  st=0
  if ! dm_lint >&2; then echo "SELFTEST FAIL: doc-markers — the table is malformed (see above)"; return 1; fi
  SELFBASE=$(mktemp -d) || { echo "SELFTEST FAIL: mktemp -d failed"; return 1; }
  # shellcheck disable=SC2064 # expand SELFBASE now — fixed for the life of the process (no disk leak)
  trap "rm -rf '$SELFBASE'" EXIT INT TERM

  _cases=${1:-}
  [ -n "$_cases" ] || _cases=$(dm_cases)
  _total=0
  for _case in $_cases; do
    _rows=$(dm_rows "$_case")
    if [ -z "$_rows" ]; then
      echo "SELFTEST FAIL: unknown case '$_case' (no rows in $TSV)"; st=1; continue
    fi

    # (0) row-count lock — the table still carries every row this case is supposed to have.
    _have=$(printf '%s\n' "$_rows" | grep -c '')
    _want=$(printf '%s' " $DM_EXPECT " | tr ' ' '\n' | awk -F: -v c="$_case" '$1==c {print $2}')
    if [ "$_have" = "$_want" ]; then
      echo "SELFTEST PASS: $_case row count $_have == DM_EXPECT"
    else
      echo "SELFTEST FAIL: $_case has $_have row(s), DM_EXPECT declares '${_want:-none}'"; st=1
    fi

    if _stage "$_case" "$SELFBASE/$_case/live"; then
      if _out=$(run "$_case" "$SELFBASE/$_case/live" 2>&1); then
        echo "SELFTEST PASS: $_case liveness — unmutated fixture GREEN"
      else
        echo "SELFTEST FAIL: $_case liveness — unmutated fixture RED: $_out"; st=1
      fi
    else
      echo "SELFTEST FAIL: $_case liveness — could not stage fixture"; st=1
    fi

    _i=0
    while IFS="$TAB" read -r _file _rx _lab _scope; do
      [ -n "$_file" ] || continue
      _i=$((_i+1)); _total=$((_total+1))
      _mutate "$_case" "$_i" "$_file" "$_rx" "$_lab" || st=1
    done <<DM_SELF_EOF
$_rows
DM_SELF_EOF

    # (2) the N/A latch, BOTH halves — the arm the staged fixtures cannot reach, because they always
    #     carry the kit marker. Off-kit must DECLINE; on-kit-with-the-doc-gone must BIND.
    if printf '%s\n' "$_rows" | cut -f4 | grep -qx kit; then
      _lat="$SELFBASE/$_case/latch"; mkdir -p "$_lat/adopter" "$_lat/kit/docs"
      : > "$_lat/kit/docs/ROADMAP-KIT.md"
      if _out=$(run "$_case" "$_lat/adopter" 2>&1) && printf '%s\n' "$_out" | grep -q "^$_case: N/A -- kit-self"; then
        echo "SELFTEST PASS: $_case latch — no kit marker, doc absent -> N/A"
      else
        echo "SELFTEST FAIL: $_case latch — off-kit tree did not render the N/A line: $_out"; st=1
      fi
      if _out=$(run "$_case" "$_lat/kit" 2>&1); then
        echo "SELFTEST FAIL: $_case latch — kit marker present + doc ABSENT still PASSED (the latch fails open): $_out"; st=1
      else
        echo "SELFTEST PASS: $_case latch — kit marker present, doc absent -> RED (binds on the kit tree)"
      fi
      _total=$((_total+2))
    fi
  done

  if [ "$st" = 0 ]; then
    echo "SELFTEST OK: doc-markers — $_total table-row mutant(s)/latch arm(s) killed, row counts pinned, liveness green on every case"
    return 0
  fi
  echo "SELFTEST FAIL: doc-markers — a mutant survived, a row count moved, or a liveness anchor broke"
  return 1
}

_stage() {  # <case> <destdir> — copy every distinct file of <case> into <destdir> at its rel path
  _sc=$1; _sd=$2
  mkdir -p "$_sd/docs" || return 1
  # The fixture carries the KIT MARKER, so a `kit`-scope case BINDS inside it rather than latching to
  # N/A — without this every mutant below would pass vacuously through the latch.
  : > "$_sd/docs/ROADMAP-KIT.md" || return 1
  dm_rows "$_sc" | cut -f1 | sort -u | while IFS= read -r _sf; do
    [ -n "$_sf" ] || continue
    mkdir -p "$_sd/$(dirname "$_sf")" || exit 1
    cp "$_sf" "$_sd/$_sf" || exit 1
  done
}

_mutate() {  # <case> <n> <file-rel> <regex> <expected-FAIL-label>
  _mc=$1; _mn=$2; _mf=$3; _mrx=$4; _mlab=$5
  _fx="$SELFBASE/$_mc/mut$_mn"
  _stage "$_mc" "$_fx" || { echo "SELFTEST FAIL: $_mc mutant $_mn — could not stage fixture"; return 1; }
  grep -Ev "$_mrx" "$_fx/$_mf" > "$_fx/$_mf.tmp" && mv "$_fx/$_mf.tmp" "$_fx/$_mf"
  if grep -Eq "$_mrx" "$_fx/$_mf"; then
    echo "SELFTEST FAIL: $_mc mutant $_mn setup — marker '$_mrx' still present after strip"; return 1
  fi
  if _out=$(run "$_mc" "$_fx" 2>&1); then
    echo "SELFTEST FAIL: $_mc mutant $_mn — check still PASSED after stripping '$_mrx' (VACUOUS): $_out"; return 1
  fi
  if printf '%s\n' "$_out" | grep -qF "FAIL: $_mlab"; then
    echo "SELFTEST PASS: $_mc mutant $_mn — stripping '$_mrx' -> RED via '$_mlab'"; return 0
  fi
  echo "SELFTEST FAIL: $_mc mutant $_mn — went RED but WITHOUT the '$_mlab' FAIL label: $_out"; return 1
}

_usage() { echo "usage: doc-markers.sh <case> [--selftest] | --selftest [case]   (takes no project-dir)" >&2; exit 2; }

[ -f "$TSV" ] || { echo "FAIL: doc-markers — the marker table is missing ($TSV)" >&2; exit 1; }

case "${1:-}" in
  --selftest) selftest "${2:-}"; exit $? ;;
  ""|-*)      _usage ;;
  *)          case "${2:-}" in
                --selftest) selftest "$1"; exit $? ;;
                "")         run "$1" "."; exit $? ;;
                *)          _usage ;;
              esac ;;
esac
