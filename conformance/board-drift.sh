#!/bin/sh
# board-drift.sh — CP-10 DETECT: a board row in `In Review` must not bear a MERGED PR.
#
# THE DEFECT. The Done transition drifts. CP-10's own board row recorded it: "three consecutive slices
# left a merged item sitting in `In Review` — the Done transition is drifting, which is why
# backlog-presence keeps firing." It is not hypothetical and it is not rare: CP-9 shipped in v3.126.0 /
# v3.127.0 and then sat in `In Review` (AND in `Ready`) for two further slices, silently, until someone
# happened to look. A board that lies about what is done is worse than no board — every decision taken
# from it is taken on stale information.
#
# WHY A CRON CHECK, NOT A PR GATE. Same constraint as release-tagged.sh: the answer only becomes knowable
# AFTER the merge. A PR-time gate cannot ask "was this PR merged?" of a PR that is, by definition, not yet
# merged. Detect it where the question is answerable — drift-watch, weekly.
#
# CEILING (stated, not glossed): a green run proves NO `In Review` row bears a merged PR. It does NOT
# prove the `Done` entry is accurate, honest, or written at all — only that the row MOVED. This is the
# same ceiling backlog-presence.sh already carries, and it must not be overclaimed.
#
# What it changes: nothing (read-only; one GitHub API read per In-Review row). Guardrails: none needed.
#
# Usage:
#   sh conformance/board-drift.sh [<dir>]    # 0 = no drift · 1 = DRIFT · 2 = cannot determine
#   sh conformance/board-drift.sh --selftest
#
# BOARD_DRIFT_PR_STATE: an injectable probe printing a PR's state ("MERGED"/"OPEN"/"CLOSED") given a PR
# number as $1. Exists so --selftest runs OFFLINE. SECURITY: it is eval'd via `sh -c` — set it only from
# trusted config, NEVER from repo/PR input. (Same posture, and the same warning, as
# scripts/release-tag.sh's RELEASE_TAG_CI_PROBE.)
#
# NOT registered in conformance/verify.sh, deliberately — it needs network + a board, and the PORTABLE
# battery runs on the incepted artifact (no PRs, no history). Same call as release-tagged.sh. Honest
# consequence: it is therefore NOT reached by the non-vacuity mutation sweep; its teeth come from
# --selftest below, mutation-tested by hand at authoring time.
set -eu
cd "$(dirname "$0")/.." 2>/dev/null || true

# The board parser is the SINGLE SOURCE OF TRUTH (backlog-lib.sh) — the same one backlog-presence.sh and
# backlog-current.sh use. Never re-derive "a row" or "the PR column" here: two parsers WILL drift, and
# then the gates disagree about what the board even says.
. conformance/backlog-lib.sh

# pr_state <n> -> print MERGED / OPEN / CLOSED / empty (unknown).
pr_state() {
  if [ -n "${BOARD_DRIFT_PR_STATE:-}" ]; then
    sh -c "$BOARD_DRIFT_PR_STATE $1" 2>/dev/null || true
    return 0
  fi
  command -v gh >/dev/null 2>&1 || return 0
  gh pr view "$1" --json state -q .state 2>/dev/null || true
}

# check <dir> -> 0 no drift · 1 DRIFT · 2 cannot determine.
check() {
  _d=${1:-.}
  _bl="$_d/BACKLOG.md"
  [ -f "$_bl" ] || { echo "UNVERIFIED: no BACKLOG.md in $_d" >&2; return 2; }

  _rows=$(mktemp); _drift=0; _seen=0; _unknown=0
  section_rows "$_bl" "In Review" > "$_rows" 2>/dev/null || true
  if [ ! -s "$_rows" ]; then
    rm -f "$_rows"
    echo "OK: board-drift — no 'In Review' rows to check"
    return 0
  fi

  _hdr=$(head -1 "$_rows")
  _idx=$(col_index "$_hdr" "PR")
  if [ -z "$_idx" ]; then
    rm -f "$_rows"
    echo "UNVERIFIED: the 'In Review' section has no PR column" >&2
    return 2
  fi

  _n=0
  while IFS= read -r _row; do
    _n=$((_n + 1))
    [ "$_n" -eq 1 ] && continue          # header row, not data (parity with backlog-presence)
    is_sep_row "$_row" && continue
    _cell=$(cell "$_row" "$_idx")
    # Extract every #<digits> token in the PR cell. A cell bound by BRANCH NAME (P1-CI 2/2) yields no
    # number — correctly, since an unopened/unmerged branch cannot have drifted into "merged".
    for _pr in $(printf '%s' "$_cell" | grep -oE '#[0-9]+' | tr -d '#'); do
      _seen=$((_seen + 1))
      _st=$(pr_state "$_pr")
      case "$_st" in
        MERGED)
          echo "FAIL: PR #$_pr is MERGED but its board row is still in 'In Review' — move it to Done." >&2
          _drift=1 ;;
        OPEN|CLOSED)
          : ;;                            # open = legitimately in review; closed-unmerged = not drift
        *)
          echo "UNVERIFIED: cannot determine the state of PR #$_pr" >&2
          _unknown=1 ;;
      esac
    done
  done < "$_rows"
  rm -f "$_rows"

  [ "$_drift" = 0 ] || return 1
  # "Cannot determine" is NOT a pass. In the kit's own weekly cron, an unanswerable question is a finding
  # — never collapse it into a silent 0 (green-while-dark).
  [ "$_unknown" = 0 ] || return 2
  echo "OK: board-drift — no merged PR is still sitting in 'In Review' ($_seen row(s) checked)"
  return 0
}

# ── selftest : load-bearing in BOTH directions. A detector that never fires certifies the hole; one that
#    always fires gets muted.
selftest() {
  st=0; t=$(mktemp -d)

  # _board <dir> <pr-cell> : a board whose In Review section carries one row with the given PR cell.
  _board() {
    mkdir -p "$1"
    { printf '# B\n\n## In Review\n\n| Item | Reviewer | PR |\n|------|----------|----|\n'
      printf '| thing | r | %s |\n' "$2"
    } > "$1/BACKLOG.md"
  }
  _rc() { _x=0; ( BOARD_DRIFT_PR_STATE="$2"; check "$1" ) >/dev/null 2>&1 || _x=$?; echo $_x; }

  # A (TEETH — the CP-9 defect): a MERGED PR still in In Review -> DRIFT (rc 1).
  d="$t/a"; _board "$d" '#308'
  [ "$(_rc "$d" 'printf MERGED')" = "1" ] \
    && echo "PASS: a MERGED PR still in 'In Review' -> DRIFT (the CP-9 defect)" \
    || { echo "FAIL: A — a merged PR sitting in In Review went undetected"; st=1; }

  # B (LIVENESS anchor): an OPEN PR in In Review is CORRECT -> rc 0. Without this, a check that always
  # fires would pass A and be worthless — it would fire on every legitimately-in-review PR and get muted.
  d="$t/b"; _board "$d" '#309'
  [ "$(_rc "$d" 'printf OPEN')" = "0" ] \
    && echo "PASS: an OPEN PR in 'In Review' -> no drift (the gate does not cry wolf)" \
    || { echo "FAIL: B — an open PR was reported as drift; the check would be muted within a week"; st=1; }

  # C: a BRANCH-NAME binding (P1-CI 2/2) yields no PR number -> no drift. A branch that has not even been
  # opened as a PR cannot have been merged.
  d="$t/c"; _board "$d" 'fix/cp10-release-tag-integrity'
  [ "$(_rc "$d" 'printf MERGED')" = "0" ] \
    && echo "PASS: a branch-name binding -> no drift (no PR number to judge)" \
    || { echo "FAIL: C — a branch-bound row was misjudged"; st=1; }

  # D: an unknown PR state -> UNVERIFIED (rc 2). NOT a pass.
  d="$t/d"; _board "$d" '#999'
  [ "$(_rc "$d" 'true')" = "2" ] \
    && echo "PASS: an undeterminable PR state -> UNVERIFIED (rc 2), never a silent pass" \
    || { echo "FAIL: D — an unknown state was reported as OK (green-while-dark)"; st=1; }

  # E: a CLOSED-but-unmerged PR is not drift (abandoned work legitimately parked).
  d="$t/e"; _board "$d" '#306'
  [ "$(_rc "$d" 'printf CLOSED')" = "0" ] \
    && echo "PASS: a CLOSED (unmerged) PR -> no drift" \
    || { echo "FAIL: E — a closed-unmerged PR was reported as drift"; st=1; }

  rm -rf "$t"
  [ "$st" = 0 ] && echo "board-drift --selftest: OK" || { echo "board-drift --selftest: FAIL" >&2; return 1; }
  return "$st"
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  *)          check "${1:-.}"; exit $? ;;
esac
