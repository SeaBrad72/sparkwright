#!/bin/sh
# golden-path-filter-parity.sh — assert the golden-path workflow's `paths:` TRIGGER FILTER covers
# every script its jobs INVOKE, so a change to an exercised script can never silently skip the
# end-to-end proof. Closes the parity-drift class where a job gains an `sh scripts/foo.sh` (or
# `sh conformance/foo.sh`) invocation but the hand-kept `paths:` list is not updated.
#
# Parity is ONE-DIRECTIONAL: invoked ⊆ filter. An over-broad filter (an entry never invoked) is
# conservative — it only makes golden-path run more often, never the silent-skip bug — so dead
# filter entries are NOT flagged (that would be YAGNI). Membership is glob-aware: a filter entry
# ending in `/**` covers files under its prefix, so the check survives a rewrite of the literal
# list into directory globs.
#
# EXTRACTION SCOPE (honest limits): an invocation is detected by a literal `scripts/`|`conformance/`
# `.sh` token on a single, non-comment line. A `cd <dir> && sh <bare>.sh`, a variable-indirected
# path, or a command assembled across lines is NOT detected — these are coverage gaps (a missed
# re-trigger), never a destructive action. The real golden-path jobs invoke each script on its own
# prefixed line, so the lock is non-vacuous today; widen the extractor if that convention changes.
#   sh conformance/golden-path-filter-parity.sh [--selftest]
# Exit: 0 = parity holds (or N/A outside the kit) · 1 = an invoked script missing from the filter
#       · 2 = usage. POSIX sh; dash-clean.
set -eu
cd "$(dirname "$0")/.." 2>/dev/null || true

WF="${GOLDEN_PATH_WF:-.github/workflows/golden-path.yml}"

# filter_set <file>: one filter path per line (single-quoted tokens from the `paths:` lines).
filter_set() { grep 'paths:' "$1" | grep -oE "'[^']*'" | tr -d "'"; }

# invoked_set <file>: one invoked scripts/|conformance/ .sh path per line. The comment strip is
# ANCHORED to whitespace/line-start so a `#` inside a shell string cannot truncate a same-line
# invocation (a bare `s/#.*//` would hide e.g. `echo '#x'; sh scripts/y.sh`). `grep -v 'paths:'`
# excludes the trigger line from the scan — defensive only: a filter entry harvested back as
# "invoked" would be self-satisfying, so this line cannot change a verdict (intent, not teeth).
invoked_set() {
  sed -E 's/(^|[[:space:]])#.*//' "$1" | grep -v 'paths:' \
    | grep -oE '(scripts|conformance)/[A-Za-z0-9._/-]+\.sh' | sort -u
}

# covered <token> <filter-line...>: 0 if token is literally in the filter OR covered by a `/**`
# glob whose prefix is a path-prefix of the token.
covered() {
  _t=$1; shift
  for _e in "$@"; do
    [ "$_e" = "$_t" ] && return 0
    case "$_e" in
      */\*\*) _pfx=${_e%/\*\*}; case "$_t" in "$_pfx"/*) return 0 ;; esac ;;
    esac
  done
  return 1
}

check_parity() {  # <workflow_file>
  _f=$1; _miss=0
  [ -f "$_f" ] || { echo "FAIL: golden-path workflow not found: $_f"; return 1; }
  set -f  # no pathname expansion: a 'scripts/**' filter entry must stay literal, not glob-expand
  # shellcheck disable=SC2046  # filter paths are space-free; word-splitting into params is intended
  set -- $(filter_set "$_f")
  for _inv in $(invoked_set "$_f"); do
    covered "$_inv" "$@" || { echo "FAIL: '$_inv' is invoked by golden-path but absent from the paths: trigger filter"; _miss=1; }
  done
  set +f
  return $_miss
}

selftest() {
  sfail=0; d=$(mktemp -d)
  # dirty: a.sh in filter + invoked; b.sh invoked but NOT in filter -> FAIL naming b.sh
  printf "on:\n  pull_request:\n    paths: ['scripts/a.sh']\njobs:\n  x:\n    steps:\n      - run: sh scripts/a.sh\n      - run: sh scripts/b.sh\n" > "$d/dirty.yml"
  out=$(check_parity "$d/dirty.yml" 2>&1) && { echo "FAIL: selftest — missing file not detected"; sfail=1; } || true
  printf '%s\n' "$out" | grep -q "scripts/b.sh" || { echo "FAIL: selftest — missing file not named"; sfail=1; }
  [ "$sfail" -ne 0 ] || echo "PASS: selftest — missing invoked file detected + named"
  # clean: both in filter -> PASS
  printf "on:\n  pull_request:\n    paths: ['scripts/a.sh', 'scripts/b.sh']\njobs:\n  x:\n    steps:\n      - run: sh scripts/a.sh\n      - run: sh scripts/b.sh\n" > "$d/clean.yml"
  if check_parity "$d/clean.yml" >/dev/null 2>&1; then echo "PASS: selftest — complete filter passes"; else echo "FAIL: selftest — complete filter wrongly failed"; sfail=1; fi
  # glob: filter scripts/** covers scripts/c.sh -> PASS
  printf "on:\n  pull_request:\n    paths: ['scripts/**']\njobs:\n  x:\n    steps:\n      - run: sh scripts/c.sh\n" > "$d/glob.yml"
  if check_parity "$d/glob.yml" >/dev/null 2>&1; then echo "PASS: selftest — glob filter covers"; else echo "FAIL: selftest — glob filter wrongly failed"; sfail=1; fi
  # comment: a real YAML comment invocation of d.sh (whitespace-preceded #) must NOT be required
  printf "on:\n  pull_request:\n    paths: ['scripts/a.sh']\njobs:\n  x:\n    steps:\n      - run: sh scripts/a.sh  # sh scripts/d.sh\n" > "$d/comment.yml"
  if check_parity "$d/comment.yml" >/dev/null 2>&1; then echo "PASS: selftest — commented invocation ignored"; else echo "FAIL: selftest — comment-stripping not load-bearing"; sfail=1; fi
  # hash-in-string: a `#` inside a shell string must NOT hide the same-line invocation of e.sh
  # (e.sh is invoked but absent from the filter -> must be DETECTED; a bare s/#.*// would miss it)
  printf "on:\n  pull_request:\n    paths: ['scripts/a.sh']\njobs:\n  x:\n    steps:\n      - run: echo '#c'; sh scripts/e.sh\n" > "$d/hash.yml"
  out=$(check_parity "$d/hash.yml" 2>&1) && { echo "FAIL: selftest — hash-in-string hid the invocation"; sfail=1; } || true
  printf '%s\n' "$out" | grep -q "scripts/e.sh" || { echo "FAIL: selftest — anchored comment-strip not load-bearing (e.sh not detected)"; sfail=1; }
  [ "$sfail" -ne 0 ] || echo "PASS: selftest — hash-in-string invocation still detected"
  if [ "$sfail" -eq 0 ]; then echo "OK: golden-path-filter-parity selftest"; exit 0; else echo "FAIL: golden-path-filter-parity selftest"; exit 1; fi
}

case "${1:-}" in
  --selftest) selftest ;;
  "")
    # kit-self: golden-path.yml is kit-only (control-plane + export-ignored). N/A in an adopter tree.
    [ -f "$WF" ] || { echo "golden-path-filter-parity: N/A — kit-self check (golden-path workflow absent)"; exit 0; }
    if check_parity "$WF"; then echo "OK: golden-path paths: filter covers every invoked script"; exit 0
    else echo "FAIL: golden-path paths: filter is missing invoked script(s) above — add them so a change re-triggers golden-path"; exit 1; fi ;;
  *) echo "usage: golden-path-filter-parity.sh [--selftest]" >&2; exit 2 ;;
esac
