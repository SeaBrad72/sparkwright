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
#   sh conformance/board-drift.sh [<dir>]           # 0 = no drift · 1 = DRIFT · 2 = cannot determine
#   sh conformance/board-drift.sh --merged-rows [<dir>]   # print merged_rows()'s pairs; 0 = answered · 2 = cannot enumerate
#   sh conformance/board-drift.sh --selftest
#
# BOARD_DRIFT_PR_STATE: an injectable probe printing a PR's state ("MERGED"/"OPEN"/"CLOSED") given a PR
# number as $1. Exists so --selftest runs OFFLINE. SECURITY: it is eval'd via `sh -c` — set it only from
# trusted config, NEVER from repo/PR input. (Same posture, and the same warning, as
# scripts/release-tag.sh's RELEASE_TAG_CI_PROBE.)
#
# BOARD_DRIFT_MERGED_ROWS (§4.5 tracker-arm INVERSION, design 2026-09-26-tbg-wire-local §9): an
# injectable probe printing, one per line, "<pr-number> <Kit-Row key>" for every PR merged in the
# drift window — the forge enumeration the tracker-arm needs, offline-mirrored the same way
# BOARD_DRIFT_PR_STATE mirrors `gh pr view`. SECURITY: same posture as BOARD_DRIFT_PR_STATE — it is
# eval'd via `sh -c`; set it only from trusted config, NEVER from repo/PR input.
#
# NOT registered in conformance/verify.sh, deliberately — it needs network + a board, and the PORTABLE
# battery runs on the incepted artifact (no PRs, no history). Same call as release-tagged.sh. Honest
# consequence: it is therefore NOT reached by the non-vacuity mutation sweep; its teeth come from
# --selftest below, mutation-tested by hand at authoring time.
set -eu
# merged_rows()'s temp file: defence-in-depth for an abnormal exit of the shell (e.g. a `set -e` exit
# mid-loop) — this file has no other trap to conflict with (verified: none existed before this line).
# No leg drives this trap: every normal and refusal path already removes the file itself. Signals are
# NOT covered — an EXIT-only trap under dash does not run on SIGINT/SIGTERM.
trap 'rm -f "${_mr_tmp:-}" "${_bd_zmut:-}"' EXIT
cd "$(dirname "$0")/.." 2>/dev/null || true

# The board parser is the SINGLE SOURCE OF TRUTH (backlog-lib.sh) — the same one backlog-presence.sh and
# backlog-current.sh use. Never re-derive "a row" or "the PR column" here: two parsers WILL drift, and
# then the gates disagree about what the board even says.
. conformance/backlog-lib.sh

# bd_safe_id <text> -> strips C0/DEL control bytes before any diagnostic use. TBG-SEAM-CONSUMERS-
# DERIVED (D-240919-3 §8 L1): board-drift becomes a NEW seam consumer this slice (it now calls
# seam_backend/seam_rows_in_state below), so any id it ever prints must be sanitized exactly as
# not_enforced_notice already sanitizes the backend token and loop-state's ls_safe sanitizes ids —
# a board Item cell is attacker-influenceable text (anyone can open a PR).
bd_safe_id() {
  printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177'
}

# pr_state <n> -> print MERGED / OPEN / CLOSED / empty (unknown).
pr_state() {
  if [ -n "${BOARD_DRIFT_PR_STATE:-}" ]; then
    sh -c "$BOARD_DRIFT_PR_STATE $1" 2>/dev/null || true
    return 0
  fi
  command -v gh >/dev/null 2>&1 || return 0
  gh pr view "$1" --json state -q .state 2>/dev/null || true
}

# merged_rows -> print "<pr-number> <Kit-Row key>" pairs, one per line, for PRs merged in the
# drift window (§4.5 tracker-arm INVERSION). Empty stdout + rc0 is a legal answer ("no PRs merged
# in the window"). A NON-ZERO rc (2) means "cannot enumerate" (no `gh`, gh failed, the listing hit
# the 1000 ceiling, a shallow clone, or the date computation failed) — a DISTINCT outcome from
# "answered: none merged", never collapsed into it.
# Collapsing the two used to fail OPEN: a gh-less/broken environment read as a silent rc0-empty
# "OK: no PRs merged", the same false green a tracker adopter with no gh (or an Alpine cron image)
# would get every single run while merged-but-in-flight rows went undetected forever. See
# BOARD_DRIFT_MERGED_ROWS's header above for the security posture.
# PRODUCTION PATH (mirrors pr_state's gh fallback): `gh pr list --state merged --limit 1000` over a
# 7-day window (this runs under a scheduled job — the tracker profile runs it daily; the kit's own
# drift-watch weekly) gives each merged PR's number + merge-
# commit sha; the PR's Kit-Row key is read off that merge commit's OWN trailer via
# `git log --format=%(trailers:...)`, the same source loop-state's entry-declaration gate treats
# as authoritative — a BOUND, not an authentication. THE CEILING (security fix-round 2, L-1): on a
# GitHub squash-merge the default merge-commit message IS the PR title+body, so a PR AUTHOR CAN
# place a `Kit-Row:` line there. This is BOUNDED, not eliminated: `row_id_ok`, `bd_safe_id`, and
# the exact-line `grep -qxF` match this file already applies to whatever the trailer names hold
# the worst case to a false-DRIFT report on a key the author does not own, or evasion of drift
# detection for their own row — a false-red or a missed detection, never a write, a merge, or a
# credential read. A PR whose merge commit
# carries no Kit-Row trailer is silently skipped — it never entered the loop board and so cannot
# drift against it.
# RESIDUAL, UPDATED (TRACKER-DRIFT-SCHEDULED-WIRING): a total `gh` failure (missing
# `pull-requests: read`, auth, rate limit) and a truncated listing (>= 1000 results, the search-API
# ceiling) are now UNVERIFIED (rc 2), never a silent "no PRs merged" green — gh's own exit code is
# captured before parsing, and the result count is checked against the ceiling before it is trusted.
# Partial-page loss INSIDE an otherwise-successful gh call under that ceiling stays a stated ceiling,
# not a cure. A merge commit that is otherwise resolvable but whose sha is NOT PRESENT in this clone
# (security-seat ruling B) is SKIPPED, not fatal — it is disclosed by PR number in one NOTE line on
# stderr, never by sha or key. A SHALLOW clone cannot resolve merge commits at all and refuses (rc 2)
# before attempting the loop.
# WINDOW CEILING (stated, not configurable): 7 days must be >= the cadence of a scheduled job (the
# tracker profile runs it daily; the kit's own drift-watch weekly). A skipped or delayed run leaves
# merged-but-stale rows outside this window
# PERMANENTLY unchecked — there is no catch-up mechanism. Widening the window is the only lever;
# this file deliberately does not expose it as a knob (CEILING, not a feature).
merged_rows() {
  if [ -n "${BOARD_DRIFT_MERGED_ROWS:-}" ]; then
    # PROPAGATE the stub's own exit rc: a stub that `exit 2` models "cannot enumerate"; a stub
    # that prints nothing and `exit 0` models "answered: none merged". Collapsing both to `true`
    # (the old behaviour) is exactly the fail-open bug this arm now refuses to reproduce.
    _mr_rc=0
    sh -c "$BOARD_DRIFT_MERGED_ROWS" 2>/dev/null || _mr_rc=$?
    return "$_mr_rc"
  fi
  command -v gh >/dev/null 2>&1 || return 2
  _mr_since=$(date -u -d '-7 days' +%Y-%m-%d 2>/dev/null || date -u -v-7d +%Y-%m-%d 2>/dev/null) || return 2
  # Capture gh's OWN exit code before parsing (the fail-open #705 shipped: `gh ... | while ..`
  # discards gh's rc, so a PRESENT-BUT-FAILING gh -- missing `pull-requests: read`, auth, rate
  # limit -- printed nothing and read as "no PRs merged" -> a silent green, forever). `--limit 1000`
  # is the search-API ceiling; hitting it means the listing may be truncated, so this refuses rather
  # than silently dropping the rest.
  _mr_tmp=$(mktemp) || return 2
  _mr_rc=0
  gh pr list --state merged --search "merged:>=$_mr_since" --limit 1000 --json number,mergeCommit \
    -q '.[] | "\(.number) \(.mergeCommit.oid)"' > "$_mr_tmp" 2>/dev/null || _mr_rc=$?
  if [ "$_mr_rc" != 0 ]; then
    rm -f "$_mr_tmp"
    return 2
  fi
  _mr_lines=$(wc -l < "$_mr_tmp" 2>/dev/null | tr -d ' ')
  if [ -n "$_mr_lines" ] && [ "$_mr_lines" -ge 1000 ] 2>/dev/null; then
    rm -f "$_mr_tmp"
    echo "UNVERIFIED: merged-PR listing hit the 1000-result API ceiling — refusing a truncated sweep" >&2
    return 2
  fi
  # A shallow clone cannot resolve arbitrary merge-commit shas via `git log` -- refuse up front
  # rather than skip every row and report a misleadingly clean "no drift".
  if [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
    rm -f "$_mr_tmp"
    echo "UNVERIFIED: shallow clone cannot resolve merge commits — fetch-depth: 0 / git fetch --unshallow" >&2
    return 2
  fi
  _mr_skip=0
  _mr_skipped=""
  while IFS=' ' read -r _mr_n _mr_sha; do
    [ -n "$_mr_n" ] || continue
    [ -n "$_mr_sha" ] || continue
    _mr_key=$(git log -1 --format='%(trailers:key=Kit-Row,valueonly)' "$_mr_sha" 2>/dev/null) || { _mr_skip=$((_mr_skip + 1)); _mr_skipped="$_mr_skipped $_mr_n"; continue; }
    [ -n "$_mr_key" ] || continue
    # security L-1: a merge commit carrying MORE THAN ONE Kit-Row trailer (or a folded continuation
    # line git's own trailers:valueonly parser joins onto one) must never forge a pair — take the
    # first line ONLY to decide whether to skip, and skip+disclose by PR number (parity with the
    # trusted job's "multiple Kit-Row trailers -> refuse"), the SAME NOTE mechanism an unresolvable
    # commit already uses. Never emit a pair for it, and never let the SECOND line's content
    # (e.g. AB-3) reach stdout.
    _mr_key_lc=$(printf '%s\n' "$_mr_key" | wc -l | tr -d ' ')
    if [ -n "$_mr_key_lc" ] && [ "$_mr_key_lc" -gt 1 ] 2>/dev/null; then
      _mr_skip=$((_mr_skip + 1)); _mr_skipped="$_mr_skipped $_mr_n"; continue
    fi
    printf '%s %s\n' "$_mr_n" "$_mr_key"
  done < "$_mr_tmp"
  rm -f "$_mr_tmp"
  if [ "$_mr_skip" -gt 0 ]; then
    _mr_skip_msg="NOTE: board-drift skipped $_mr_skip merged PR(s) whose Kit-Row could not be read (merge commit not in this clone, or more than one Kit-Row value):"
    for _mr_x in $_mr_skipped; do
      case "$_mr_x" in
        ''|*[!0-9]*) continue ;;
      esac
      _mr_skip_msg="$_mr_skip_msg #$_mr_x"
    done
    echo "$_mr_skip_msg" >&2
  fi
  return 0
}

# check <dir> -> 0 no drift · 1 DRIFT · 2 cannot determine · 3 NOT ENFORCED (a declared non-md
# backend with no ratified board-governance waiver -- TBG-SEAM-CONSUMERS-DERIVED F3/§4.5: this used
# to read rc 2 ("no BACKLOG.md in $_d") on a non-md tree, which is indistinguishable from a genuinely
# broken md board. Routed through the seam so the two cases say two different things.
check() {
  _d=${1:-.}
  # shellcheck disable=SC2034  # SEAM_ROOT is read by the sourced seam_* functions (backlog-lib.sh).
  SEAM_ROOT="$_d"
  _tok=$(seam_backend)
  case "$_tok" in
    unrecognized:*)
      # A filled but unknown backend token. FAIL-CLOSED like every other board-bound gate's
      # equivalent branch (backlog-current.sh/backlog-presence.sh) -- never silently N/A.
      echo "UNVERIFIED: backlog backend '$(bd_safe_id "${_tok#unrecognized:}")' is not recognised — cannot determine board-drift" >&2
      return 2 ;;
  esac
  if [ -n "$_tok" ] && [ "$_tok" != "md" ]; then
    # §4.5 TRACKER-ARM INVERSION (design 2026-09-26-tbg-wire-local §9): a recognised non-md backend
    # WITH a SET SEAM_RECORD inverts the direction — the forge is now the source of "merged", and
    # the TRACKER is what must have caught up. Gated exactly like loop-state's check_row: a set
    # SEAM_RECORD routes here, NEVER through not_enforced_notice/the waiver ladder below (an
    # UNSET SEAM_RECORD keeps everything below byte-identical -- H-4's "no adopter green->red").
    if seam_tracker_record_set; then
      # MULTI-ROW in-flight set (TBG-WIRE-LOCAL T3 fix): seam_row_state/seam_rows_in_state's
      # single-subject arm (_seam_tracker_answer) refuses any id != the record's one `requested`
      # subject, so per-key lookups can resolve AT MOST one merged PR per cron run. The record's
      # multi-row path — seam_rows_in_state, backed by the record's `list <state> <ids>` lines with
      # NO single-subject gate (_seam_tracker_rows_in_state) — is the one that can actually name the
      # WHOLE in-flight set. Either call refusing (rc != 0: no record, an unbound record, or a
      # missing `list` line) makes the WHOLE check UNVERIFIED — never a silent pass built on half
      # the in-flight set.
      _inflight=$(mktemp)
      _bd_rc1=0; seam_rows_in_state in-progress >> "$_inflight" 2>/dev/null || _bd_rc1=$?
      _bd_rc2=0; seam_rows_in_state in-review >> "$_inflight" 2>/dev/null || _bd_rc2=$?
      if [ "$_bd_rc1" != 0 ] || [ "$_bd_rc2" != 0 ]; then
        rm -f "$_inflight"
        echo "UNVERIFIED: cannot determine the tracker's in-flight rows (in-progress/in-review) — refusing" >&2
        return 2
      fi
      _bd_drift=0; _bd_n=0
      _mrows=$(mktemp)
      _mr_rc=0
      merged_rows > "$_mrows" || _mr_rc=$?
      if [ "$_mr_rc" != 0 ]; then
        # merged_rows CANNOT ENUMERATE (no gh, or the window's date computation failed) — this is
        # an unanswerable question, never a silent "no PRs merged" green (the fail-open this arm
        # exists to close). Mirrors the md-arm's own unanswerable-question posture (:224-226).
        rm -f "$_mrows" "$_inflight"
        echo "UNVERIFIED: cannot enumerate merged PRs for the drift window (no gh, gh failed, the listing hit the 1000 ceiling, a shallow clone, or the date computation failed) — refusing" >&2
        return 2
      fi
      if [ ! -s "$_mrows" ]; then
        rm -f "$_mrows" "$_inflight"
        echo "OK: board-drift (tracker) — no PRs merged in the window"
        return 0
      fi
      while IFS=' ' read -r _mpr _mkey; do
        [ -n "$_mpr" ] || continue
        [ -n "$_mkey" ] || continue
        # security twin of the NOTE filter: _mpr must be a bare PR number (^[0-9]+$) — anything else
        # is never printed and never matched (defence-in-depth; merged_rows() is the only producer
        # of this stream and never emits a non-numeric first field, but check() does not trust that).
        case "$_mpr" in
          ''|*[!0-9]*) continue ;;
        esac
        # A crafted merge-commit trailer ("Kit-Row: AB-1 x") must not evade the exact-match below
        # by smuggling extra tokens into the key: take only the FIRST whitespace token, then
        # validate it against the ONE grammar (row_id_ok, backlog-lib.sh) before ever matching it.
        # A key that fails the grammar is skipped — it cannot legally be a tracker key anyway.
        _mkey=${_mkey%% *}
        row_id_ok "$_mkey" || continue
        _bd_n=$((_bd_n + 1))
        _smpr=$(bd_safe_id "$_mpr")
        _smkey=$(bd_safe_id "$_mkey")
        # A sanitized key can become empty (an all-control-byte key) -- an empty _smkey must never
        # match an empty line via `grep -qxF ""`.
        [ -n "$_smkey" ] || continue
        # Matched on the SANITIZED key (record ids are grammar-checked control-byte-free already,
        # §4.3) — a hostile control byte inside a merged key must not defeat-by-mismatch OR leak
        # into the diagnostic; sanitizing first makes both true at once.
        if grep -qxF "$_smkey" "$_inflight" 2>/dev/null; then
          echo "FAIL: $_smkey merged (PR #$_smpr) but still in-flight on the tracker — move it to done." >&2
          _bd_drift=1
        fi
      done < "$_mrows"
      rm -f "$_mrows" "$_inflight"
      [ "$_bd_drift" = 0 ] || return 1
      echo "OK: board-drift (tracker) — no merged PR is still in-flight on the tracker ($_bd_n checked)"
      return 0
    fi
    # NON-MD-BACKEND-NEVER-SILENT: rc 3 NOT ENFORCED (or rc 0 if a ratified board-governance waiver
    # covers it), never a bare "no BACKLOG.md" rc 2 -- the two are different findings.
    _bd_ne=0
    not_enforced_notice "$_tok" "$_d" "conformance/waivers-valid.sh" || _bd_ne=$?
    return "$_bd_ne"
  fi
  _bl="$_d/BACKLOG.md"
  [ -f "$_bl" ] || { echo "UNVERIFIED: no BACKLOG.md in $_d" >&2; return 2; }

  # The backend DECISION above is the seam route this slice adds (F3); the PR-CELL extraction below
  # still reads the board directly via the shared parser (section_rows/cell), reached ONLY once the
  # seam has already confirmed the backend supports it. `seam_rows_in_state` cannot substitute here:
  # it silently drops any row whose Item cell carries no backticked id (by design -- §4.2's row-id
  # seam), while board-drift must catch drift on EVERY In-Review row regardless of id convention. A
  # PR number also has no seam analogue (a GitHub concept with no tracker-portable equivalent, the
  # same non-portability the `pr-bound` carve-out already names, D-240919-3 (b)) -- this stays a
  # scoped, gated md-arm read, unchanged in behaviour from the pre-route version (byte-identical).
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
    # The row's own id, sanitized (bd_safe_id) before it ever reaches a diagnostic -- the L1
    # obligation above. Named in FAIL/UNVERIFIED only; the happy-path "OK" line is unchanged.
    _rid=$(bd_safe_id "$(backtick_id "$(cell "$_row" 1)")")
    # Extract every #<digits> token in the PR cell. A cell bound by BRANCH NAME (P1-CI 2/2) yields no
    # number — correctly, since an unopened/unmerged branch cannot have drifted into "merged".
    for _pr in $(printf '%s' "$_cell" | grep -oE '#[0-9]+' | tr -d '#'); do
      _seen=$((_seen + 1))
      _st=$(pr_state "$_pr")
      case "$_st" in
        MERGED)
          echo "FAIL: PR #$_pr is MERGED but its board row (${_rid:-?}) is still in 'In Review' — move it to Done." >&2
          _drift=1 ;;
        OPEN|CLOSED)
          : ;;                            # open = legitimately in review; closed-unmerged = not drift
        *)
          echo "UNVERIFIED: cannot determine the state of PR #$_pr (row ${_rid:-?})" >&2
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

  # F (TBG-SEAM-CONSUMERS-DERIVED F3/§4.5): a declared NON-md backend with no ratified waiver ->
  # rc 3 NOT ENFORCED, never the old bare "no BACKLOG.md" rc 2 (a different finding).
  d="$t/f"; mkdir -p "$d"
  printf '# Fixture\n\n- **Backlog backend**: GitHub Issues\n' > "$d/CLAUDE.md"
  _x=0; check "$d" >/dev/null 2>&1 || _x=$?
  [ "$_x" = "3" ] \
    && echo "PASS: a declared non-md backend, unwaived -> NOT ENFORCED (rc 3), not the old rc 2" \
    || { echo "FAIL: F — non-md backend did not read rc 3 (got rc=$_x)"; st=1; }

  # G: the SAME non-md tree, plus a ratified board-governance waiver -> rc 0 (waived, with the notice).
  d="$t/g"; mkdir -p "$d"
  printf '# Fixture\n\n- **Backlog backend**: GitHub Issues\n' > "$d/CLAUDE.md"
  _d0=$(date -u -d "+0 days" +%Y-%m-%d 2>/dev/null || date -u -v+0d +%Y-%m-%d)
  _dexp=$(date -u -d "+60 days" +%Y-%m-%d 2>/dev/null || date -u -v+60d +%Y-%m-%d)
  printf '## Active waivers\n\n| Gate | Reason | Owner | Opened | Expires | Remediation plan | Ratified-by |\n|--|--|--|--|--|--|--|\n| board-governance | the kit reads BACKLOG.md only | @jdoe | %s | %s | adopt TRACKER-BACKED-GOVERNANCE | @sec |\n' "$_d0" "$_dexp" \
    > "$d/WAIVER-REGISTER.md"
  _x=0; check "$d" >/dev/null 2>&1 || _x=$?
  [ "$_x" = "0" ] \
    && echo "PASS: a declared non-md backend WITH a ratified board-governance waiver -> rc 0" \
    || { echo "FAIL: G — a ratified waiver did not clear the non-md route (got rc=$_x)"; st=1; }

  # H: a mistyped/unrecognized backend -> UNVERIFIED (rc 2), fail-closed like every other board-bound
  # gate's equivalent branch — never a silent N/A for an md-board owner who fat-fingers the field.
  d="$t/h"; mkdir -p "$d"
  printf '# Fixture\n\n- **Backlog backend**: markdow\n' > "$d/CLAUDE.md"
  _x=0; check "$d" >/dev/null 2>&1 || _x=$?
  [ "$_x" = "2" ] \
    && echo "PASS: a mistyped backend -> UNVERIFIED (rc 2), never a silent pass" \
    || { echo "FAIL: H — a mistyped backend was not reported UNVERIFIED (got rc=$_x)"; st=1; }

  # I (D-240919-3 §8 L1, non-vacuity): a MERGED PR whose row's Item cell carries a raw control byte
  # (BEL, 0x07) inside the backticked id must not leak that byte into the printed diagnostic — the
  # sanitized id (or its `?` fallback) is all that may appear on stderr.
  d="$t/i"; mkdir -p "$d"
  _ctrl=$(printf '\007')
  { printf '# B\n\n## In Review\n\n| Item | Reviewer | PR |\n|------|----------|----|\n'
    printf '| `HOSTILE%sID` | r | #308 |\n' "$_ctrl"
  } > "$d/BACKLOG.md"
  _out=$(BOARD_DRIFT_PR_STATE='printf MERGED'; export BOARD_DRIFT_PR_STATE; check "$d" 2>&1) || true
  _stripped=$(printf '%s' "$_out" | LC_ALL=C tr -d '\000-\037\177')
  [ "$_out" = "$_stripped" ] \
    && echo "PASS: a control byte in the row's Item cell never reaches the printed diagnostic (L1)" \
    || { echo "FAIL: I — a raw control byte leaked into board-drift's own output"; st=1; }

  # ── §4.5 tracker-arm INVERSION (design 2026-09-26-tbg-wire-local §9) — legs J-N. Reuses the
  # TBG-RECORD-GATES-BIND deliverable fixture tree (a `jira`-declaring tree with no BACKLOG.md at
  # all -- the treeless proof) exactly as loop-state.sh's own tracker-arm legs do; the SEAM_RECORD
  # content is generated HERE, at test time, never a tracked file (its read-day/pin/head fields
  # must stay fresh/consistent with whatever tracker.conf bytes that fixture tree carries).
  _bd_trk="conformance/fixtures/tbg-record-gates-bind/tracker-jira"
  _bd_trkconf="$_bd_trk/.kit/tracker.conf"
  _bd_trkpin=$( { command -v sha256sum >/dev/null 2>&1 && sha256sum || shasum -a 256; } < "$_bd_trkconf" 2>/dev/null | awk '{print $1}')
  _bd_trkhead="1111111111111111111111111111111111111111"
  _bd_trktoday=$(date -u +%Y-%m-%d)

  # _bd_mkrec <state> -> writes+prints the path to a good tracker record whose one row is
  # `AB-1 state=<state>` (requested == AB-1, matching the fixture's `project=AB`), plus BOTH
  # `list in-progress`/`list in-review` lines the multi-row tracker arm now reads (empty unless
  # <state> is that very state — the record's own bijection rule exempts the subject row from
  # needing to appear in any list at all, so a terminal state needs no list line of its own).
  # A record's per-line tokenizer refuses a trailing space (M-6) -- an EMPTY `list <state>` line
  # must therefore carry no trailing space at all, just the bare keyword+state.
  _bd_listline() {
    [ -n "$2" ] && echo "list $1 $2" || echo "list $1"
  }

  _bd_mkrec() {
    _bmr_f="$t/tracker-record.txt"
    _bmr_ip=""; _bmr_ir=""
    [ "$1" = "in-progress" ] && _bmr_ip="AB-1"
    [ "$1" = "in-review" ] && _bmr_ir="AB-1"
    {
      echo "kit-tracker-read 1"
      echo "backend jira"
      echo "pin sha256:$_bd_trkpin"
      echo "head $_bd_trkhead"
      echo "requested AB-1"
      echo "read-day $_bd_trktoday"
      echo "credential ok"
      echo "verdict bound"
      echo "row AB-1 state=$1"
      _bd_listline in-progress "$_bmr_ip"
      _bd_listline in-review "$_bmr_ir"
    } > "$_bmr_f"
    printf '%s' "$_bmr_f"
  }

  # _bd_mkrec_missinglist <state> -> the SAME record as _bd_mkrec, but omits the `list in-review`
  # line entirely (leg L: a required list line absent -> UNVERIFIED, never a silent pass).
  _bd_mkrec_missinglist() {
    _bmr_f="$t/tracker-record.txt"
    _bmr_ip=""
    [ "$1" = "in-progress" ] && _bmr_ip="AB-1"
    {
      echo "kit-tracker-read 1"
      echo "backend jira"
      echo "pin sha256:$_bd_trkpin"
      echo "head $_bd_trkhead"
      echo "requested AB-1"
      echo "read-day $_bd_trktoday"
      echo "credential ok"
      echo "verdict bound"
      echo "row AB-1 state=$1"
      echo "list in-progress $_bmr_ip"
    } > "$_bmr_f"
    printf '%s' "$_bmr_f"
  }

  # J (TEETH — the §4.5 inversion anchor): a PR merged, mapped to a tracker key the record's
  # `list in-progress` line still carries -> DRIFT (rc 1). Without this leg, the inverted direction
  # could be entirely unbuilt and every existing leg (A-I, the md-arm) would still pass.
  _bd_rec=$(_bd_mkrec in-progress)
  _x=0
  ( SEAM_RECORD="$_bd_rec"; SEAM_HEAD="$_bd_trkhead"
    BOARD_DRIFT_MERGED_ROWS='printf "500 AB-1\n"'
    check "$_bd_trk" ) >/dev/null 2>&1 || _x=$?
  [ "$_x" = "1" ] \
    && echo "PASS: a merged PR whose tracker key is still listed 'in-progress' -> DRIFT (rc 1, the multi-row §4.5 inversion)" \
    || { echo "FAIL: J — a merged-but-in-progress tracker row went undetected (got rc=$_x)"; st=1; }

  # K (LIVENESS anchor, no-drift negative): the SAME merged PR, but the tracker key sits in NEITHER
  # in-flight list (a terminal state, 'done') -> rc 0. Without this leg, a tracker-arm that always
  # fires would pass J and be worthless.
  _bd_rec=$(_bd_mkrec "done")
  _x=0
  ( SEAM_RECORD="$_bd_rec"; SEAM_HEAD="$_bd_trkhead"
    BOARD_DRIFT_MERGED_ROWS='printf "500 AB-1\n"'
    check "$_bd_trk" ) >/dev/null 2>&1 || _x=$?
  [ "$_x" = "0" ] \
    && echo "PASS: a merged PR whose tracker key sits in neither in-flight list -> no drift (rc 0)" \
    || { echo "FAIL: K — a merged+done tracker row was misjudged as drift (got rc=$_x)"; st=1; }

  # L (UNVERIFIED negative): the record is missing a required `list in-review` line -> rc 2, never
  # a silent pass built on half the in-flight set.
  _bd_rec=$(_bd_mkrec_missinglist in-progress)
  _x=0
  ( SEAM_RECORD="$_bd_rec"; SEAM_HEAD="$_bd_trkhead"
    BOARD_DRIFT_MERGED_ROWS='printf "500 AB-1\n"'
    check "$_bd_trk" ) >/dev/null 2>&1 || _x=$?
  [ "$_x" = "2" ] \
    && echo "PASS: a record missing a required 'list in-review' line -> UNVERIFIED (rc 2), never a silent pass" \
    || { echo "FAIL: L — a record missing a required list line was not reported UNVERIFIED (got rc=$_x)"; st=1; }

  # M (L1 sanitisation, tracker-arm): a raw control byte (BEL, 0x07) inside a merged PR's Kit-Row
  # key must never leak into the printed diagnostic -- same posture as leg I's md-arm coverage,
  # extended to the new tracker-arm's own diagnostic lines.
  _bd_rec=$(_bd_mkrec in-progress)
  _out=$(SEAM_RECORD="$_bd_rec"; SEAM_HEAD="$_bd_trkhead"
    BOARD_DRIFT_MERGED_ROWS='printf "500 AB-\0071\n"'
    check "$_bd_trk" 2>&1) || true
  _stripped=$(printf '%s' "$_out" | LC_ALL=C tr -d '\000-\037\177')
  [ "$_out" = "$_stripped" ] \
    && echo "PASS: a control byte in a merged PR's Kit-Row key never reaches the printed diagnostic (tracker-arm L1)" \
    || { echo "FAIL: M — a raw control byte leaked into board-drift's tracker-arm output"; st=1; }

  # N (md unchanged, TBG-WIRE-LOCAL T3 non-regression): the pre-existing md-arm legs (A-I above)
  # still pass byte-identically -- the tracker-arm addition touches ONLY the non-md branch of
  # check(), never the BACKLOG.md PR-cell read (D-240919-3). Re-run leg A's anchor as the guard.
  d="$t/n"; _board "$d" '#308'
  [ "$(_rc "$d" 'printf MERGED')" = "1" ] \
    && echo "PASS: the md-arm's PR-cell read is unchanged by the §4.5 tracker-arm addition (D-240919-3)" \
    || { echo "FAIL: N — the md-arm regressed after adding the tracker-arm"; st=1; }

  # O (TEETH — cannot-enumerate never fails open): the injectable stub `exit 2`s (models "no gh"/
  # "date computation failed") -> UNVERIFIED (rc 2), NEVER rc 0. Without this leg, collapsing
  # "cannot enumerate" into "answered: none merged" (the fail-open this arm exists to close) would
  # still pass every other leg.
  _bd_rec=$(_bd_mkrec in-progress)
  _x=0
  ( SEAM_RECORD="$_bd_rec"; SEAM_HEAD="$_bd_trkhead"
    BOARD_DRIFT_MERGED_ROWS='exit 2'
    check "$_bd_trk" ) >/dev/null 2>&1 || _x=$?
  [ "$_x" = "2" ] \
    && echo "PASS: merged_rows cannot enumerate (no gh / date failure) -> UNVERIFIED (rc 2), never a silent OK" \
    || { echo "FAIL: O — a cannot-enumerate merged-rows answer did not read rc 2 (got rc=$_x)"; st=1; }

  # P (crafted-trailer evasion, MINOR #2): a merge-commit trailer value carrying a trailing token
  # ("AB-1 x") must not evade the exact match against the in-flight key "AB-1" — the key is
  # normalised to its first whitespace token before matching, so this merged PR IS caught as
  # drift. Without this leg, `grep -qxF "AB-1 x"` silently missing "AB-1" would pass unnoticed.
  _bd_rec=$(_bd_mkrec in-progress)
  _x=0
  ( SEAM_RECORD="$_bd_rec"; SEAM_HEAD="$_bd_trkhead"
    BOARD_DRIFT_MERGED_ROWS='printf "500 AB-1 x\n"'
    check "$_bd_trk" ) >/dev/null 2>&1 || _x=$?
  [ "$_x" = "1" ] \
    && echo "PASS: a crafted merge-commit trailer ('AB-1 x') is normalised to its first token and still DRIFTs" \
    || { echo "FAIL: P — a crafted trailer with a trailing token evaded the in-flight match (got rc=$_x)"; st=1; }

  # ── §3.3 (TRACKER-DRIFT-SCHEDULED-WIRING) — legs Q-U: `--merged-rows` CLI mode + the two
  # merged_rows() fail-opens (silent gh failure, silent truncation) this slice closes.

  # Q (TEETH, --merged-rows happy path): the stub's pairs print verbatim on stdout, rc 0.
  # (rc captured INSIDE the substitution via a temp file -- an assignment `_x=$(cmd); _x=$?` would
  # itself trip `set -e` on a non-zero cmd before the rc could ever be read.)
  _bd_rcf="$t/rc-q"
  _out=$(
    _bdq_rc=0
    BOARD_DRIFT_MERGED_ROWS='printf "7 AB-1\n"' sh "$0" --merged-rows 2>&1 || _bdq_rc=$?
    printf '%s' "$_bdq_rc" > "$_bd_rcf"
  )
  _x=$(cat "$_bd_rcf")
  [ "$_out" = "7 AB-1" ] && [ "$_x" = "0" ] \
    && echo "PASS: --merged-rows prints the stub's pairs verbatim (rc 0)" \
    || { echo "FAIL: Q — --merged-rows did not print the stub's pairs (out='$_out' rc=$_x)"; st=1; }

  # R (TEETH, --merged-rows cannot-enumerate): a stub that exit 2s propagates rc 2, never rc 0.
  _x=0
  BOARD_DRIFT_MERGED_ROWS='exit 2' sh "$0" --merged-rows >/dev/null 2>&1 || _x=$?
  [ "$_x" = "2" ] \
    && echo "PASS: --merged-rows propagates a cannot-enumerate stub as rc 2" \
    || { echo "FAIL: R — --merged-rows did not propagate rc 2 (got rc=$_x)"; st=1; }

  # S (TEETH — the fail-open #705 shipped): a present-but-failing gh must refuse (rc 2), never read
  # as "no PRs merged" (the old silent green). Covers both merged_rows() directly and check() end to
  # end on the tracker fixture, so the fix is proven at both the unit and the wired level.
  # merged_rows() reads the AMBIENT repo (no dir arg), so — exactly as leg T does — both halves must
  # run against a throwaway NON-shallow repo via GIT_DIR/GIT_WORK_TREE rather than the ambient
  # checkout: a shallow ambient checkout (e.g. CI's `actions/checkout`) would trip the shallow-clone
  # refusal (rc 2, "UNVERIFIED") for its OWN reason, leaving this leg vacuously green even with the
  # gh-rc capture removed entirely. The extra `grep -qv` below asserts the refusal is the gh failure,
  # not a masked shallow-clone refusal.
  _bd_trepo_s="$t/leg-s-repo"; mkdir -p "$_bd_trepo_s"
  git init -q "$_bd_trepo_s"
  git -C "$_bd_trepo_s" config user.email "test@example.invalid"
  git -C "$_bd_trepo_s" config user.name "test"
  git -C "$_bd_trepo_s" commit -q --allow-empty -m "a commit"
  _bd_fakebin_s="$t/fakebin-s"; mkdir -p "$_bd_fakebin_s"
  printf '#!/bin/sh\nexit 1\n' > "$_bd_fakebin_s/gh"
  chmod +x "$_bd_fakebin_s/gh"
  _x=0
  ( PATH="$_bd_fakebin_s:$PATH"; unset BOARD_DRIFT_MERGED_ROWS
    export GIT_DIR="$_bd_trepo_s/.git" GIT_WORK_TREE="$_bd_trepo_s"
    merged_rows >/dev/null 2>&1 ) || _x=$?
  _bd_rec=$(_bd_mkrec in-progress)
  _bd_rcf="$t/rc-s"
  _out=$(
    PATH="$_bd_fakebin_s:$PATH"; unset BOARD_DRIFT_MERGED_ROWS
    export GIT_DIR="$_bd_trepo_s/.git" GIT_WORK_TREE="$_bd_trepo_s"
    SEAM_RECORD="$_bd_rec"; SEAM_HEAD="$_bd_trkhead"
    _bds_rc=0
    check "$_bd_trk" 2>&1 || _bds_rc=$?
    printf '%s' "$_bds_rc" > "$_bd_rcf"
  )
  _x2=$(cat "$_bd_rcf")
  [ "$_x" = "2" ] && [ "$_x2" = "2" ] && printf '%s' "$_out" | grep -q "UNVERIFIED" \
    && ! printf '%s' "$_out" | grep -qF "shallow clone cannot resolve merge commits" \
    && echo "PASS: a present-but-failing gh refuses (rc 2, UNVERIFIED) — never the old silent 'none merged' green" \
    || { echo "FAIL: S — a failing gh did not refuse (merged_rows rc=$_x check rc=$_x2 out='$_out')"; st=1; }

  # T (TEETH — the truncation fail-open #705 shipped): exactly 1000 result lines refuses (rc 2, the
  # search-API ceiling); 999 lines (unknown shas) still answers rc 0 — the boundary liveness anchor
  # proving T's negative isn't just "always refuse". merged_rows() reads the AMBIENT repo (no dir
  # arg), so this must run against a throwaway NON-shallow repo via GIT_DIR/GIT_WORK_TREE (leg W's
  # technique) rather than the ambient checkout — a shallow ambient checkout (e.g. CI's
  # `actions/checkout`) would trip the shallow-clone refusal BEFORE the ceiling check on the 999-line
  # case, misreporting rc 2 for the wrong reason and masking a real boundary regression.
  _bd_trepo_t="$t/leg-t-repo"; mkdir -p "$_bd_trepo_t"
  git init -q "$_bd_trepo_t"
  git -C "$_bd_trepo_t" config user.email "test@example.invalid"
  git -C "$_bd_trepo_t" config user.name "test"
  git -C "$_bd_trepo_t" commit -q --allow-empty -m "a commit"
  _bd_fakebin_t1="$t/fakebin-t1"; mkdir -p "$_bd_fakebin_t1"
  {
    printf '#!/bin/sh\n'
    printf 'i=1\nwhile [ "$i" -le 1000 ]; do printf "%%s 0000000000000000000000000000000000000000\\n" "$i"; i=$((i+1)); done\n'
  } > "$_bd_fakebin_t1/gh"
  chmod +x "$_bd_fakebin_t1/gh"
  _bd_terrf1="$t/t-err-1"
  _x=0
  ( PATH="$_bd_fakebin_t1:$PATH"; unset BOARD_DRIFT_MERGED_ROWS
    export GIT_DIR="$_bd_trepo_t/.git" GIT_WORK_TREE="$_bd_trepo_t"
    merged_rows >/dev/null 2>"$_bd_terrf1" ) || _x=$?
  _bd_terr1=$(cat "$_bd_terrf1")
  _bd_fakebin_t2="$t/fakebin-t2"; mkdir -p "$_bd_fakebin_t2"
  {
    printf '#!/bin/sh\n'
    printf 'i=1\nwhile [ "$i" -le 999 ]; do printf "%%s 0000000000000000000000000000000000000000\\n" "$i"; i=$((i+1)); done\n'
  } > "$_bd_fakebin_t2/gh"
  chmod +x "$_bd_fakebin_t2/gh"
  _x2=0
  ( PATH="$_bd_fakebin_t2:$PATH"; unset BOARD_DRIFT_MERGED_ROWS
    export GIT_DIR="$_bd_trepo_t/.git" GIT_WORK_TREE="$_bd_trepo_t"
    merged_rows >/dev/null 2>&1 ) || _x2=$?
  [ "$_x" = "2" ] && [ "$_x2" = "0" ] && printf '%s' "$_bd_terr1" | grep -qF "1000-result API ceiling" \
    && echo "PASS: exactly 1000 result lines refuses (rc 2, the ceiling named); 999 lines still answers (rc 0, boundary liveness)" \
    || { echo "FAIL: T — the 1000-line truncation boundary was misjudged (1000-line rc=$_x err='$_bd_terr1' 999-line rc=$_x2)"; st=1; }

  # U (production-parse anchor): one real gh-shaped line, resolved through a throwaway git repo whose
  # HEAD commit carries the Kit-Row trailer -> --merged-rows prints "7 AB-1". This is the anchor that
  # makes S and T's negatives meaningful: it proves the production parse still works end to end.
  _bd_grepo="$t/anchor-repo"; mkdir -p "$_bd_grepo"
  git init -q "$_bd_grepo"
  git -C "$_bd_grepo" config user.email "test@example.invalid"
  git -C "$_bd_grepo" config user.name "test"
  git -C "$_bd_grepo" commit -q --allow-empty -m "$(printf 'a commit\n\nKit-Row: AB-1\n')"
  _bd_gsha=$(git -C "$_bd_grepo" rev-parse HEAD)
  _bd_fakebin_u="$t/fakebin-u"; mkdir -p "$_bd_fakebin_u"
  { printf '#!/bin/sh\n'; printf 'printf "7 %s\\n"\n' "$_bd_gsha"; } > "$_bd_fakebin_u/gh"
  chmod +x "$_bd_fakebin_u/gh"
  _bd_rcf="$t/rc-u"
  _out=$(
    _bdu_rc=0
    PATH="$_bd_fakebin_u:$PATH" sh "$0" --merged-rows "$_bd_grepo" 2>&1 || _bdu_rc=$?
    printf '%s' "$_bdu_rc" > "$_bd_rcf"
  )
  _x=$(cat "$_bd_rcf")
  [ "$_out" = "7 AB-1" ] && [ "$_x" = "0" ] \
    && echo "PASS: the production parse (one real gh-shaped line + a real trailer commit) still resolves to '7 AB-1'" \
    || { echo "FAIL: U — the production parse broke (out='$_out' rc=$_x)"; st=1; }

  # V (TEETH, security-seat ruling B -- unresolvable-sha skip+disclose): a two-PR fake gh listing
  # (line 1 = a real commit whose merge commit carries `Kit-Row: AB-1`, line 2 = an unrelated PR
  # number paired with an unknown 40-hex sha) resolved through a throwaway git repo -> --merged-rows
  # (CLI, NOT under `||`) prints ONLY the resolvable row, rc 0, and discloses the unresolvable one
  # by PR NUMBER ONLY on stderr -- never the sha.
  _bd_grepo_v="$t/leg-v-repo"; mkdir -p "$_bd_grepo_v"
  git init -q "$_bd_grepo_v"
  git -C "$_bd_grepo_v" config user.email "test@example.invalid"
  git -C "$_bd_grepo_v" config user.name "test"
  git -C "$_bd_grepo_v" commit -q --allow-empty -m "$(printf 'a commit\n\nKit-Row: AB-1\n')"
  _bd_vsha=$(git -C "$_bd_grepo_v" rev-parse HEAD)
  _bd_unknown_sha="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  _bd_fakebin_v="$t/fakebin-v"; mkdir -p "$_bd_fakebin_v"
  { printf '#!/bin/sh\n'; printf 'printf "7 %s\\n42 %s\\n"\n' "$_bd_vsha" "$_bd_unknown_sha"; } > "$_bd_fakebin_v/gh"
  chmod +x "$_bd_fakebin_v/gh"
  _bd_vout="$t/v-out"; _bd_verr="$t/v-err"
  _x=0
  PATH="$_bd_fakebin_v:$PATH" sh "$0" --merged-rows "$_bd_grepo_v" >"$_bd_vout" 2>"$_bd_verr" || _x=$?
  _out_v=$(cat "$_bd_vout")
  _err_v=$(cat "$_bd_verr")
  _v_ok=1
  [ "$_out_v" = "7 AB-1" ] || _v_ok=0
  [ "$_x" = "0" ] || _v_ok=0
  printf '%s' "$_err_v" | grep -qF "skipped 1 merged PR(s)" && printf '%s' "$_err_v" | grep -qF "#42" || _v_ok=0
  printf '%s' "$_err_v" | grep -qF "$_bd_unknown_sha" && _v_ok=0
  [ "$_v_ok" = 1 ] \
    && echo "PASS: V — an unresolvable merge-commit sha is skipped and disclosed by PR number only, the resolvable row still prints (rc 0)" \
    || { echo "FAIL: V — out='$_out_v' rc=$_x err='$_err_v'"; st=1; }

  # W (TEETH -- the 2>/dev/null drop in check()): the SAME two-PR fake gh (leg V) resolved through a
  # clean tracker record (AB-1 in state 'done', not in-flight) via check() -> rc 0, and the NOTE
  # line the tracker arm's merged_rows() call now surfaces (no `2>/dev/null` swallowing it inside
  # check()) appears in the combined output.
  # check()'s own board/tracker-conf reads assume cwd stays the repo root (a relative
  # `conformance/..` lookup inside backlog-lib.sh) -- so git must be pointed at leg V's throwaway
  # repo via GIT_DIR/GIT_WORK_TREE, never via `cd`, or every seam read below breaks.
  _bd_rec_w=$(_bd_mkrec "done")
  _bd_wout="$t/w-out"
  _x=0
  ( PATH="$_bd_fakebin_v:$PATH"; SEAM_RECORD="$_bd_rec_w"; SEAM_HEAD="$_bd_trkhead"
    export GIT_DIR="$_bd_grepo_v/.git" GIT_WORK_TREE="$_bd_grepo_v"
    check "$_bd_trk" ) >"$_bd_wout" 2>&1 || _x=$?
  _out_w=$(cat "$_bd_wout")
  _w_note=0
  if printf '%s' "$_out_w" | grep -qF "NOTE: board-drift skipped 1 merged PR(s)" \
      && printf '%s' "$_out_w" | grep -qF "#42"; then
    _w_note=1
  fi
  [ "$_x" = "0" ] && [ "$_w_note" = "1" ] \
    && echo "PASS: W — the tracker arm's NOTE (skipped-PR disclosure) reaches check()'s combined output, proving the 2>/dev/null drop" \
    || { echo "FAIL: W — out='$_out_w' rc=$_x"; st=1; }

  # X (TEETH -- shallow refusal, security-seat ruled): a `--depth 1` clone of a throwaway two-commit
  # repo cannot be trusted to resolve merge commits -> a fake gh listing one pair through the shallow
  # clone -> --merged-rows refuses (rc 2), stderr names "shallow clone", regardless of whether the
  # particular sha happens to be present.
  _bd_srcrepo="$t/x-src"; mkdir -p "$_bd_srcrepo"
  git init -q "$_bd_srcrepo"
  git -C "$_bd_srcrepo" config user.email "test@example.invalid"
  git -C "$_bd_srcrepo" config user.name "test"
  git -C "$_bd_srcrepo" commit -q --allow-empty -m "first"
  git -C "$_bd_srcrepo" commit -q --allow-empty -m "$(printf 'second\n\nKit-Row: AB-1\n')"
  _bd_xsha=$(git -C "$_bd_srcrepo" rev-parse HEAD)
  _bd_shallow="$t/x-shallow"
  git clone -q --depth 1 "file://$_bd_srcrepo" "$_bd_shallow"
  _bd_fakebin_x="$t/fakebin-x"; mkdir -p "$_bd_fakebin_x"
  { printf '#!/bin/sh\n'; printf 'printf "9 %s\\n"\n' "$_bd_xsha"; } > "$_bd_fakebin_x/gh"
  chmod +x "$_bd_fakebin_x/gh"
  _bd_xerrf="$t/x-err"
  _x=0
  PATH="$_bd_fakebin_x:$PATH" sh "$0" --merged-rows "$_bd_shallow" >/dev/null 2>"$_bd_xerrf" || _x=$?
  _err_x=$(cat "$_bd_xerrf")
  case "$_err_x" in
    *"shallow clone"*) _x_shallow_named=1 ;;
    *) _x_shallow_named=0 ;;
  esac
  [ "$_x" = "2" ] && [ "$_x_shallow_named" = "1" ] \
    && echo "PASS: X — a shallow clone refuses (rc 2), naming 'shallow clone' rather than silently skipping every row" \
    || { echo "FAIL: X — rc=$_x err='$_err_x'"; st=1; }

  # Y (temp-file hygiene, private TMPDIR is empty after the run): run leg V's CLI invocation with a
  # freshly-created EMPTY directory as its private TMPDIR, then assert that directory is empty
  # afterward. This is NOT a proof the EXIT trap fired -- the normal success path already `rm -f`s
  # the scratch file on its own, so this leg passes even with the trap line deleted. It only proves
  # merged_rows() does not otherwise scatter files into its TMPDIR.
  _bd_ytmp="$t/ytmp"; mkdir -p "$_bd_ytmp"
  _x=0
  TMPDIR="$_bd_ytmp" PATH="$_bd_fakebin_v:$PATH" sh "$0" --merged-rows "$_bd_grepo_v" >/dev/null 2>&1 || _x=$?
  _bd_yleft=$(ls -A "$_bd_ytmp" 2>/dev/null | wc -l | tr -d ' ')
  [ "$_x" = "0" ] && [ "$_bd_yleft" = "0" ] \
    && echo "PASS: Y — temp-file hygiene (private TMPDIR is empty after the run)" \
    || { echo "FAIL: Y — rc=$_x private TMPDIR not empty after the run ($_bd_yleft entries left)"; st=1; }

  # Z (security L-1, RULE): a merge commit carrying TWO Kit-Row trailers must never forge a pair —
  # --merged-rows prints NO pair for it, rc 0, and the NOTE names its PR number (parity with the
  # trusted job's own "multiple Kit-Row trailers -> refuse", D-240919-2(3)). AB-3 (the second
  # trailer's value) must never reach stdout.
  _bd_grepo_z1="$t/leg-z1-repo"; mkdir -p "$_bd_grepo_z1"
  git init -q "$_bd_grepo_z1"
  git -C "$_bd_grepo_z1" config user.email "test@example.invalid"
  git -C "$_bd_grepo_z1" config user.name "test"
  git -C "$_bd_grepo_z1" commit -q --allow-empty -m "$(printf 'a commit\n\nKit-Row: AB-1\nKit-Row: AB-3\n')"
  _bd_z1sha=$(git -C "$_bd_grepo_z1" rev-parse HEAD)
  _bd_fakebin_z1="$t/fakebin-z1"; mkdir -p "$_bd_fakebin_z1"
  { printf '#!/bin/sh\n'; printf 'printf "9 %s\\n"\n' "$_bd_z1sha"; } > "$_bd_fakebin_z1/gh"
  chmod +x "$_bd_fakebin_z1/gh"
  _bd_z1out="$t/z1-out"; _bd_z1err="$t/z1-err"
  _x=0
  PATH="$_bd_fakebin_z1:$PATH" sh "$0" --merged-rows "$_bd_grepo_z1" >"$_bd_z1out" 2>"$_bd_z1err" || _x=$?
  _out_z1=$(cat "$_bd_z1out")
  _err_z1=$(cat "$_bd_z1err")
  _z1_ok=1
  [ -z "$_out_z1" ] || _z1_ok=0
  [ "$_x" = "0" ] || _z1_ok=0
  printf '%s' "$_err_z1" | grep -qF "skipped 1 merged PR(s)" && printf '%s' "$_err_z1" | grep -qF "#9" || _z1_ok=0
  printf '%s' "$_out_z1$_err_z1" | grep -qF "AB-3" && _z1_ok=0
  [ "$_z1_ok" = 1 ] \
    && echo "PASS: Z1 — a merge commit carrying TWO Kit-Row trailers prints NO pair (rc 0), the NOTE names its PR number, and AB-3 never reaches stdout/stderr" \
    || { echo "FAIL: Z1 — out='$_out_z1' rc=$_x err='$_err_z1'"; st=1; }

  # Z2: the FOLDED-continuation variant (`Kit-Row: AB-1` then an indented `  77 AB-3`, which git's
  # own trailer parser joins into the SAME multi-line value) — same shape as Z1.
  _bd_grepo_z2="$t/leg-z2-repo"; mkdir -p "$_bd_grepo_z2"
  git init -q "$_bd_grepo_z2"
  git -C "$_bd_grepo_z2" config user.email "test@example.invalid"
  git -C "$_bd_grepo_z2" config user.name "test"
  git -C "$_bd_grepo_z2" commit -q --allow-empty -m "$(printf 'a commit\n\nKit-Row: AB-1\n  77 AB-3\n')"
  _bd_z2sha=$(git -C "$_bd_grepo_z2" rev-parse HEAD)
  # liveness: confirm git's own trailer parser actually folds this into a MULTI-LINE Kit-Row value —
  # if a future git stopped folding it, this leg would silently stop testing anything.
  _bd_z2_kvlc=$(git -C "$_bd_grepo_z2" log -1 --format='%(trailers:key=Kit-Row,valueonly)' "$_bd_z2sha" | wc -l | tr -d ' ')
  if [ -z "$_bd_z2_kvlc" ] || [ "$_bd_z2_kvlc" -le 1 ] 2>/dev/null; then
    echo "FAIL: Z2 setup — git did not fold the continuation line into a multi-line Kit-Row value (liveness); this leg proves nothing"; st=1
  fi
  _bd_fakebin_z2="$t/fakebin-z2"; mkdir -p "$_bd_fakebin_z2"
  { printf '#!/bin/sh\n'; printf 'printf "11 %s\\n"\n' "$_bd_z2sha"; } > "$_bd_fakebin_z2/gh"
  chmod +x "$_bd_fakebin_z2/gh"
  _bd_z2out="$t/z2-out"; _bd_z2err="$t/z2-err"
  _x=0
  PATH="$_bd_fakebin_z2:$PATH" sh "$0" --merged-rows "$_bd_grepo_z2" >"$_bd_z2out" 2>"$_bd_z2err" || _x=$?
  _out_z2=$(cat "$_bd_z2out")
  _err_z2=$(cat "$_bd_z2err")
  _z2_ok=1
  [ -z "$_out_z2" ] || _z2_ok=0
  [ "$_x" = "0" ] || _z2_ok=0
  printf '%s' "$_err_z2" | grep -qF "skipped 1 merged PR(s)" && printf '%s' "$_err_z2" | grep -qF "#11" || _z2_ok=0
  printf '%s' "$_out_z2$_err_z2" | grep -qF "AB-3" && _z2_ok=0
  [ "$_z2_ok" = 1 ] \
    && echo "PASS: Z2 — a FOLDED continuation line under Kit-Row prints NO pair (rc 0), the NOTE names its PR number, and AB-3 never reaches stdout/stderr" \
    || { echo "FAIL: Z2 — out='$_out_z2' rc=$_x err='$_err_z2'"; st=1; }

  # Z-teeth: on a scratch copy with the >1-line branch removed (the exact 10-line block this fix
  # added, located dynamically by its own comment text so a later edit cannot silently misalign the
  # deleted range), re-running Z1's scenario forges a pair and leaks AB-3 to stdout — proving Z1/Z2
  # have teeth, not just a happy-path shape.
  _bd_zl1=$(grep -n 'security L-1: a merge commit carrying MORE THAN ONE Kit-Row trailer' "$0" | head -1 | cut -d: -f1)
  if [ -n "$_bd_zl1" ]; then
    _bd_zl1end=$((_bd_zl1 + 9))
    # written under conformance/.nv-* (untracked, gitignore-matched, the harness's own established
    # mutant/ctl scratch convention — see N-3's comment above) so its own top-of-file
    # `cd "$(dirname "$0")/.."` self-relocation still lands on THIS repo's root, not a bare tmp dir.
    _bd_zmut=$(mktemp conformance/.nv-zmut-XXXXXX)
    sed "${_bd_zl1},${_bd_zl1end}d" "$0" > "$_bd_zmut"
    if cmp -s "$_bd_zmut" "$0"; then
      echo "FAIL: Z-teeth setup — the planted copy did not differ from its source"; st=1
    fi
    _bd_zmout="$t/zmut-out"
    _x=0
    PATH="$_bd_fakebin_z1:$PATH" sh "$_bd_zmut" --merged-rows "$_bd_grepo_z1" >"$_bd_zmout" 2>&1 || _x=$?
    _out_zmut=$(cat "$_bd_zmout")
    case "$_out_zmut" in
      *AB-3*)
        echo "PASS: Z-teeth — removing the >1-line branch lets AB-3 leak onto stdout (a forged pair), proving Z1/Z2 have teeth" ;;
      *)
        echo "FAIL: Z-teeth — the mutant still did not leak AB-3 (out='$_out_zmut' rc=$_x) — Z1/Z2 may not have teeth"; st=1 ;;
    esac
    rm -f "$_bd_zmut"
  else
    echo "FAIL: Z-teeth setup — could not locate the >1-line branch by its own comment text"; st=1
  fi

  unset -f _bd_mkrec _bd_mkrec_missinglist _bd_listline

  rm -rf "$t"
  [ "$st" = 0 ] && echo "board-drift --selftest: OK" || { echo "board-drift --selftest: FAIL" >&2; return 1; }
  return "$st"
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  --merged-rows)
    _bd_mr_dir=${2:-.}
    cd "$_bd_mr_dir" || exit 2
    merged_rows
    exit $? ;;
  *)          check "${1:-.}"; exit $? ;;
esac
