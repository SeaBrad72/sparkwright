#!/bin/sh
# script-disclosure.sh — conformance gate: every human-run kit script discloses, in its
# header comments, WHAT IT CHANGES and its GUARDRAILS. Enforces two pinned labels —
#   ^#[[:space:]]*What it changes:   AND   ^#[[:space:]]*Guardrails:   (case-sensitive)
# in the leading comment block (up to the first code line) of every shebang-bearing script
# in scripts/ (scripts/*.sh + the extensionless scripts/kit-guard & scripts/sparkwright),
# MINUS a sourced-only-helper allowlist (a library `.`/`source`d by others and never run
# standalone). Enforce-by-default: a non-allowlisted script missing either label FAILs,
# naming the script + the missing label.
# HONEST CEILING: proves the labels are PRESENT in the header — NOT that their prose is
# accurate or complete. Accuracy stays the reviewer's / owner's Go/No-Go.
#   sh conformance/script-disclosure.sh            # real scan of the in-scope scripts
#   sh conformance/script-disclosure.sh --selftest # fixtures (good passes, 2 bad fail)
# scan() takes its target directory as an ARGUMENT (never an env override): the real run passes
#   the pinned "scripts", and the selftest aims scan() at a runtime mktemp fixture (never a committed
#   fixture dir under conformance/, which would poison the self-scanning gates).
# Exit: 0 = pass · 1 = a script fails disclosure (or a selftest expectation) · 2 = usage.
# What it changes: read-only — inspects script headers; mutates nothing.
# Guardrails: read-only; no network, no writes; additive lint — never weakens a gate.
set -eu

HERE=$(CDPATH='' cd "$(dirname "$0")" && pwd)
FIXDIR="$HERE/fixtures/script-disclosure"
cd "$HERE/.." 2>/dev/null || true    # repo root — for the real scan's scripts/*.sh globs
SCAN_DIR="scripts"

CHANGES_RE='^#[[:space:]]*What it changes:'
GUARD_RE='^#[[:space:]]*Guardrails:'

# is_allowlisted <basename> — sourced-only helper libraries only (`.`/`source`d by others,
# never run by a human, so they carry no standalone "what it changes / guardrails").
# CURRENTLY EMPTY: an exhaustive
#   grep -rlE '(\.|source)[[:space:]]+[^ ]*scripts/<name>'
# across the repo returns nothing — every script (incl. otel-trace.sh, runaway-guard.sh)
# is invoked via `sh "$here/..."` as a subprocess and carries its own CLI + --selftest,
# so all are in-scope. The `case` is the documented home for any future sourced-only lib.
is_allowlisted() {
  case "$1" in
    # <future-sourced-only-helper>.sh) return 0 ;;  # basename only ($1 is 'scripts/'-stripped); none today
    *) return 1 ;;
  esac
}

check_file() {  # <path> -> 0 discloses both labels · 1 missing >=1 (prints which)
  # Scan the whole leading comment block (shebang + comments + blanks, up to the first
  # code line) — robust to header length; a fixed line window missed labels in long headers.
  f=$1; hdr=$(awk 'NR==1&&/^#!/{next} /^#/{print;next} /^[[:space:]]*$/{next} {exit}' "$f"); miss=""
  printf '%s\n' "$hdr" | grep -Eq "$CHANGES_RE" || miss="What it changes:"
  printf '%s\n' "$hdr" | grep -Eq "$GUARD_RE"   || miss="${miss:+$miss + }Guardrails:"
  [ -z "$miss" ] && return 0
  echo "FAIL: $f — missing '$miss'"; return 1
}

scan() {  # <dir> — real scan of the in-scope scripts in <dir> (default $SCAN_DIR)
  _sdir=${1:-$SCAN_DIR}
  fail=0; n=0
  # Scan by SHEBANG, not a hardcoded name list: any file in <dir> whose first line is a
  # shebang (`#!`) is a runnable entrypoint and is in-scope — covers scripts/*.sh, the
  # extensionless scripts/kit-guard AND scripts/sparkwright, and any future extensionless one.
  for f in "$_sdir"/*; do
    [ -f "$f" ] || continue
    IFS= read -r _l < "$f" 2>/dev/null || continue
    case "$_l" in '#!'*) : ;; *) continue ;; esac
    base=${f##*/}
    if is_allowlisted "$base"; then continue; fi
    n=$((n+1))
    check_file "$f" || fail=1
  done
  # A scan that inspected NOTHING must never PASS — zero in-scope scripts is a vacuous
  # green (an empty/miss-aimed dir), not a clean bill of health. Fail it explicitly.
  if [ "$n" = 0 ]; then
    echo "FAIL: the scan evaluated nothing — 0 in-scope (shebang-bearing) scripts found in '$_sdir'."
    return 1
  fi
  if [ "$fail" = 0 ]; then
    echo "OK: script-disclosure — $n in-scope scripts declare 'What it changes:' + 'Guardrails:'"
    echo "HONEST CEILING: proves the two labels are PRESENT — not that their prose is accurate/complete (reviewer/owner Go/No-Go owns accuracy)."
    return 0
  fi
  echo "FAIL: one or more in-scope scripts do not disclose what-they-change and/or guardrails (see above)."
  return 1
}

selftest() {  # fixtures — check_file's leaf AND scan()'s real-run accumulator (fail=1)
  st=0
  _expect good.sh 0 "good discloses both labels -> PASS (load-bearing +ve)"
  _expect missing-changes.sh 1 "no 'What it changes:' -> FAIL (load-bearing -ve)"
  _expect missing-guardrails.sh 1 "no 'Guardrails:' -> FAIL (load-bearing -ve)"
  # ── drive the REAL-RUN function. These make scan()'s fail=1 + n=0 guard load-bearing. ──
  _expect_scan good  0 "OK: script-disclosure — 1 in-scope scripts" "scan() over a compliant dir -> PASS, counts 1 (notes.txt skipped)"
  _expect_scan bad   1 "FAIL: one or more in-scope scripts"         "scan() over a non-compliant dir -> FAIL (kills fail=1)"
  _expect_scan empty 1 "the scan evaluated nothing"                 "scan() over a dir with no shebang scripts -> FAIL (no vacuous pass)"
  if [ "$st" = 0 ]; then echo "OK: script-disclosure selftest"; return 0; else echo "FAIL: script-disclosure selftest"; return 1; fi
}

# ── ORACLE — everything below the ^selftest() marker; the mutation harness never neuters it,
#    so the oracle's own st=1 accumulator can never be flipped (defect (A) closed). ──
_expect() {  # <fixture> <expected-rc> <label>  — drives check_file over a committed fixture
  if check_file "$FIXDIR/$1" >/dev/null 2>&1; then _rc=0; else _rc=$?; fi
  if [ "$_rc" = "$2" ]; then
    echo "PASS: selftest — $3 (rc $_rc)"
  else
    echo "FAIL: selftest — $3 expected $2 got $_rc"; st=1
  fi
}

_mkscan() {  # <good|bad|empty> -> echoes a freshly-built mktemp dir (no committed fixtures)
  _d=$(mktemp -d)
  printf 'not a script\n' > "$_d/notes.txt"          # non-shebang: scan must SKIP it
  case "$1" in
    good) printf '#!/bin/sh\n# What it changes: nothing\n# Guardrails: read-only\n' > "$_d/a.sh" ;;
    bad)  printf '#!/bin/sh\n# What it changes: nothing\n# Guardrails: read-only\n' > "$_d/a.sh"
          printf '#!/bin/sh\n# undisclosed\n' > "$_d/b.sh" ;;
    empty) : ;;                                       # only notes.txt -> zero in-scope scripts
  esac
  printf '%s\n' "$_d"
}

_expect_scan() {  # <good|bad|empty> <expected-rc> <needle> <label>  — drives the REAL scan()
  _d=$(_mkscan "$1")
  if _out=$(scan "$_d" 2>&1); then _rc=0; else _rc=$?; fi
  if [ "$_rc" = "$2" ] && printf '%s\n' "$_out" | grep -qF "$3"; then
    echo "PASS: selftest — $4 (rc $_rc)"
  else
    echo "FAIL: selftest — $4 expected rc $2 + '$3'; got rc $_rc out=[$_out]"; st=1
  fi
  rm -rf "$_d"
}

# CP-3: scan the scripts the kit SHIPS as well as the ones it IS. incept copies
# profiles/<stack>/scaffold/scripts/* into the adopter's scripts/, where THIS check scopes them — so
# an undisclosed scaffold script reddens every adopter's `verify.sh --require` while the kit's own CI
# never sees it. Each dir is scanned by the same real scan() (incl. its zero-in-scope vacuity guard).
scan_all() {
  _rc=0
  scan "$SCAN_DIR" || _rc=1
  for _sd in profiles/*/scaffold/scripts; do
    [ -d "$_sd" ] || continue
    scan "$_sd" || _rc=1
  done
  return $_rc
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "")         scan_all; exit $? ;;
  *) echo "usage: script-disclosure.sh [--selftest]" >&2; exit 2 ;;
esac
