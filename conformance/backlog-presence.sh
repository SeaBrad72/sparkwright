#!/bin/sh
# backlog-presence.sh — KW6-A2 board-presence merge-gate.
# Asserts that a gated-change-class PR's number appears in the `PR` cell of some board row. Reuses
# backlog-lib.sh's board parser (single source of truth) rather than re-deriving "a row". The real
# run takes the PR number + change-set listing BY ARGUMENT (never the environment — an env target lets
# a decoy redirect a control-plane check). Surfaces:
#   sh conformance/backlog-presence.sh --selftest                     # fixtures (the non-vacuity oracle)
#   sh conformance/backlog-presence.sh --dir <d> --pr <n> --changed <listing>   # the CI real run
#   ... [--branch <name>] [--claims]   # --claims adds the BOARD-CLAIM-MECHANISM arm (CI PR job only)
# check_pr is NOT dead code: selftest() drives it BY ARGUMENT (KW27's root cause was a selftest that
# could reach only the leaf beneath the real function) and the ci.yml PR-time job calls it live. There
# is no `backlog-presence-run` verify.sh companion — the real run needs a PR number, which exists only
# in PR context, so the tagless-clone dry-run structurally cannot exercise it (spec §5).
# What it changes: read-only — inspects a project's BACKLOG.md + two shipped classifier seams; mutates
#   nothing.
# Guardrails: read-only; no writes. NO NETWORK **EXCEPT** under the opt-in `--claims` arm, which
#   reads `refs/claims/*` from origin through scripts/board-claim.sh (BOARD-CLAIM-MECHANISM §3.2) —
#   that qualifier is stated here rather than left for a reader to discover, and the arm is off unless
#   the flag is passed (the CI PR job passes it; hooks/pre-push does not). Targets by argument, never env — the two classifier
#   seams are invoked with KIT_ADAPTERS_DIR / KIT_GUARD_CORE / CI SCRUBBED so a decoy env cannot
#   redirect a control-plane check onto empty adapters (spec §7). jq (agent-boundary's union tool) is
#   a fail-CLOSED dependency: absent jq -> every change-set gated. The CI runner ships jq, so the gate
#   runs at full resolution there; on a jq-less machine it is conservative, never permissive. HONEST
#   CEILING: a green run proves a `PR` cell bears this number as a whole token — NOT that the row
#   describes the work, that its state is accurate, or that a human put it there. The reviewer reading
#   the board diff is the adversary with standing to say no; the gate only makes the binding a legible
#   diff. SINCE SLICE-CLOSES-IN-ONE-PR a DONE row's `Retro/outcome` cell can carry that token too, and
#   the two bindings do NOT age alike: a PR NUMBER never decays (numbers are unique, so a stale row
#   citing #627 binds only the already-merged #627), while a BRANCH NAME CAN — branch names recur, so
#   a Done row citing `feat/x` could otherwise satisfy a LATER `--pr 0 --branch feat/x` pre-push run
#   for unrelated work. FIXED (TIER0-LOCKS-OWED a): the branch form now binds ONLY for a Done row
#   ABSENT from the BASE board's Done section (the board at `--base-board`, hooks/pre-push extracts
#   origin/main's BACKLOG.md there) — i.e. a row genuinely NEW to this push's change-set, keyed on
#   the row-id token. An unreadable/absent base board never binds by branch (fail-safe); PR-NUMBER
#   binding is unconditional and was never affected. See row_bears_pr for the mechanism.
set -eu
cd "$(dirname "$0")/.."
. conformance/backlog-lib.sh

# gate_class <changed-file> -> prints `gated` for a control-plane OR sensitive change-set, else
# `ordinary`. Two shipped seams, consulted in order:
#   - agent-boundary.sh --state : the union-aware authority on control-plane-ness.
#   - promotion-readiness.sh --class : supplies `sensitive` (auth/, secrets, migrations, ...).
# ⚠️ THIS HEADER'S CLAIM WAS RE-DERIVED 2026-08-17 AND IT NO LONGER HOLDS AS WRITTEN. It used to say
# `--state` "catches adapter-declared paths (e.g. AGENTS.md) that the guard-core-only --class
# UNDER-DETECTS as ordinary", and it cited the ratification job's reconciliation as the thing this
# order mirrors. Both halves have since stopped being true:
#   * `--class` is no longer guard-core-only. GUARD-PATH-ENUMERATION-INCOMPLETE S1 graduated
#     `AGENTS.md` into guard-core's curated set and S2 made `--class` consult the SAME adapter union
#     `--state` does, so neither seam under-detects the other's paths any more.
#   * the ratification job's reconciliation arms this order "mirrors" were DELETED by S2 as redundant
#     (arm 1) and as a fabrication (arm 2) — so the thing being mirrored is gone.
# WHY BOTH SEAMS ARE STILL CONSULTED, honestly: not because either catches paths the other misses,
# but because they carry DIFFERENT FAIL POSTURES over the same manifests — with the union underivable
# `--class` fail-safes UP to control-plane while `--state` degrades to the guard-core floor — and
# because `--class` is the only seam that answers `sensitive` at all. Two seams, one of them a second
# opinion. Do not read the pair as "one covers the other's blind spot"; that blind spot is closed.
# FAIL-SAFE, and it must NEVER fail open: an unreadable change-set or a crashed seam routes to `gated`.
# The ratification job writes `|| echo NONE`, which FAILS OPEN — a crashed seam then yields NONE, read as
# "no control-plane change". That is safe THERE because that job's verdict comes from rc, not the label;
# here the verdict IS the label, so copying the idiom would INVERT the fail-safe. We branch on rc.
gate_class() {
  _changed="$1"
  [ -f "$_changed" ] || { echo gated; return 0; }          # unreadable change-set -> fail-safe gated
  # jq is the tool agent-boundary.sh's UNION detection needs to read adapters/*/adapter.json. If it is
  # absent, the union collapses to empty and AGENTS.md-class control-plane paths go undetected. A missing
  # tool must NEVER widen what passes, so fail CLOSED: no jq -> every change-set is gated. On a machine
  # without jq this gate is maximally conservative by design (the CI runner ships jq; see the header).
  command -v jq >/dev/null 2>&1 || { echo gated; return 0; }
  # Both seam calls SCRUB the classifier-config environment: KIT_ADAPTERS_DIR / KIT_GUARD_CORE (and CI)
  # come from arguments/constants, never the caller's env (spec §7). Otherwise a decoy pointing
  # KIT_ADAPTERS_DIR at an empty dir would empty the union and fail this control-plane check open.
  # ⚠️ KIT_UNION_LIB ADDED 2026-08-17 (GUARD-PATH-ENUMERATION-INCOMPLETE S2, review REV-I1): the
  # union's DERIVATION and MATCHER moved into conformance/union-lib.sh, resolved through that
  # variable, so it is a third env-borne route to the same decoy — pointing it at a nonexistent file
  # takes the adapter half out of BOTH seams. A scrub list that covers two of three routes reads as
  # exhaustive and is not; extend it whenever either child grows an input.
  # --state is exit-0-by-contract; a NON-zero rc means the seam itself broke -> fail-safe gated.
  if ! _state=$(env -u KIT_ADAPTERS_DIR -u KIT_GUARD_CORE -u KIT_UNION_LIB CI= sh conformance/agent-boundary.sh --changed "$_changed" --state 2>/dev/null); then
    echo gated; return 0
  fi
  if [ "$_state" != NONE ]; then echo gated; return 0; fi   # union-aware control-plane -> gated
  if ! _cls=$(env -u KIT_ADAPTERS_DIR -u KIT_GUARD_CORE -u KIT_UNION_LIB CI= sh conformance/promotion-readiness.sh --class --no-verify --changed "$_changed" 2>/dev/null); then
    echo gated; return 0
  fi
  case "$_cls" in ordinary) echo ordinary ;; *) echo gated ;; esac  # sensitive|unexpected -> gated
}

# row_bears_pr <board> <pr> -> rc0 iff some row's `PR` cell bears `#<pr>` as a whole token.
# Sections without a `PR` column are skipped (only `In Review` carries one in the shipped schema) —
# the SCHEMA locates the PR, so this function never reads a state. Uses the SAME parser sequence as
# backlog-current.sh's check_section (section_rows -> header line -> col_index by name, header row 1
# skipped as data), so the two gates cannot drift over what "a row" or "the PR column" means.
# PRECONDITION: <board> must exist. Callers guard with `[ -f "$board" ]` (check_pr does) because
# `set -eu` + section_rows' awk on a MISSING file (rc 2) would abort the whole script.
# ── BRANCH-NAME BINDING (P1-CI 2/2) ────────────────────────────────────────────────────────────
# A row may be bound by the PR number `#123` OR by the BRANCH NAME. Both are accepted; either satisfies
# the gate.
#
# WHY. The PR number CANNOT EXIST before the PR is opened. So a gate that only accepts `#<pr>` makes it
# physically impossible to bind the row in the PR-opening commit — every gated PR is FORCED into a second
# push, and therefore a second full CI run. Forever. That is not an oversight anyone made; it is designed
# in, and it taxed every slice identically until this change. The branch name, by contrast, exists BEFORE
# the PR does, so the row can land in the very first commit.
#
# IS IT WEAKER? No. This gate's ceiling was always "a `PR` cell bears this token — NOT that the row
# describes the work, that its state is accurate, or that a human put it there" (see the header). A branch
# name is exactly as strong an assertion as a number: both are a token an author wrote into the cell. The
# gate proves REPRESENTATION ON THE BOARD, and it proves precisely that either way.
#
# esc_ere <s> : escape ERE metacharacters, so a branch containing `.` or `+` matches literally and can
# never be read as a pattern. A branch name is attacker-influenceable (anyone can open a PR from a
# branch), so it is untrusted input to a regex — never interpolate it raw.
esc_ere() { printf '%s' "$1" | sed 's/[][\.^$*+?(){}|\\/]/\\&/g'; }

# BRANCH_CHARS: the boundary class for a whole-token branch match. Any char legal INSIDE a git ref must
# be a NON-boundary, or `fix/p1-ci` would spuriously match a cell bearing `fix/p1-ci-path-scope`.
BRANCH_CHARS='A-Za-z0-9._/-'

# gov_row_id <row> -> the row's column-1 backticked identifier (the same extraction inprogress_hints
# uses), or empty if the cell carries none. Used to key "is this row new to the change-set".
gov_row_id() {
  _gri_c=$(cell "$1" 1)
  case "$_gri_c" in
    *'`'*) _gri_id=${_gri_c#*\`}; _gri_id=${_gri_id%%\`*}; printf '%s' "$_gri_id" ;;
    *) printf '' ;;
  esac
}

# base_row_in_done <base-board> <row-id> -> rc0 iff <row-id> appears as a column-1 backticked
# identifier in the BASE board's Done section (i.e. the row was ALREADY Done before this push —
# not new to the change-set). Scoped to Done only: a row that just MOVED to Done this push (present
# elsewhere in the base board, e.g. In Progress) is still new-to-Done and must bind.
base_row_in_done() {
  # COLUMN-1 SCOPED (first-live-run, CONTROL-PLANE-COVERAGE 2026-09-10): compare against each base
  # Done row's COLUMN-1 backticked identifier via gov_row_id — NOT a `grep` for the id anywhere in
  # the section. A `grep` over the whole Done section false-positives on a row-id merely CITED in a
  # prior row's Retro/outcome (every `**Disposition:** row \`X\`` names the next slice), so a
  # genuinely new row whose id was named in an earlier disposition would read as "already Done" and
  # its branch form would never bind. Measured on this slice's own row: `CONTROL-PLANE-COVERAGE`
  # appears in slice 3b's disposition on main, so the whole-section grep returned true for a row
  # that was Ready, not Done, on the base. Read from a temp file — a `| while` runs the body in a
  # POSIX subshell, so a `break`/return inside it cannot set this function's result.
  _brid_target="$2"
  _brid_f=$(mktemp)
  section_rows "$1" "Done" > "$_brid_f" 2>/dev/null || { rm -f "$_brid_f"; return 1; }
  _brid_hit=1
  while IFS= read -r _brid_row; do
    _brid_id=$(gov_row_id "$_brid_row")
    if [ -n "$_brid_id" ] && [ "$_brid_id" = "$_brid_target" ]; then _brid_hit=0; break; fi
  done < "$_brid_f"
  rm -f "$_brid_f"
  return "$_brid_hit"
}

row_bears_pr() {
  _bl="$1"; _pr="$2"; _br="${3:-}"; _basebl="${4:-}"; _rows_f=$(mktemp)
  [ -n "$_br" ] && _bre=$(esc_ere "$_br") || _bre=""
  # S-6 RELAY (security review, 2026-09-10): set whenever a Done row's branch token LITERALLY
  # MATCHED but the match was suppressed because the base board was unreadable (_base_ok != 1 below)
  # — never on a genuine no-match. The caller (check_pr) reads this AFTER the call to distinguish
  # "no candidate row" from "a candidate existed but binding was never evaluated", so its refusal can
  # say so instead of implying the Done form was checked and failed. Not reset by the caller between
  # sections/rows within this one call — it is a whole-call "did suppression happen at all" flag.
  _rbp_base_suppressed=0
  # ── TIER0-LOCKS-OWED (a): DONE-ARM BRANCH BINDING BOUNDED TO CHANGE-SET-NEW ROWS ─────────────
  # The branch form decays (a Done row citing `feat/x` binds a LATER unrelated push reusing that
  # name). Bound it: a Done row's branch token binds ONLY when that row is ABSENT from the BASE
  # board's Done section (i.e. it is new to this push's change-set) — keyed on the row-id token
  # (column 1's backticked identifier), not on the retro text. PR-NUMBER binding is UNAFFECTED
  # (unconditional, as before) — numbers never decay.
  # FAIL DIRECTION: an unreadable/absent base board (no arg, missing file, or no Done section —
  # e.g. an unfetched ref) means the branch form does NOT bind for ANY Done row: mirrors the
  # underivable-class fail-safe posture at hooks/pre-push (the "could not evaluate" route never
  # widens what passes). The caller (hooks/pre-push) relays "base board unreadable, branch
  # binding not evaluated" when this is why a genuine new row failed to bind.
  _base_ok=0
  if [ -n "$_basebl" ] && [ -f "$_basebl" ]; then
    _base_done_probe=$(section_rows "$_basebl" "Done" 2>/dev/null) || _base_done_probe=""
    [ -n "$_base_done_probe" ] && _base_ok=1
  fi
  for _sec in "Ready" "In Progress" "In Review" "Blocked" "Released" "Done"; do
    # NO `section_rows … | while read` — POSIX runs a pipeline's while-body in a SUBSHELL, so a
    # success-return inside it would exit only the subshell and this function would fall through to
    # its final failure path — a check that can NEVER find anything. Redirect from a temp file instead.
    section_rows "$_bl" "$_sec" > "$_rows_f"
    [ -s "$_rows_f" ] || continue
    _hdr=$(head -1 "$_rows_f")                 # the section's header row (same use as check_section)
    _idx=$(col_index "$_hdr" "PR")             # 1-based index of the `PR` column, resolved BY NAME
    # ── THE DONE ARM (SLICE-CLOSES-IN-ONE-PR §4.2) ────────────────────────────────────────────
    # A slice now closes in ONE PR: the row moves to Done on the push that is expected to merge,
    # so for a section with NO `PR` column but a `Retro/outcome` one (Done in the shipped schema)
    # the SAME whole-token matcher reads the RETRO cell instead. The schema is NOT changed — adding
    # a `PR` column to Done would shift the arity of every shipped row.
    # SCOPE IS EPOCH-BOUND (security vet H1) and that is load-bearing: the live Done table carries
    # 281 `#N` tokens and 96 rows naming two or more branches/ids, because retros routinely cite
    # prior work. An arm over ALL Done rows would let a STALE row satisfy presence for a slice it
    # never described. Only rows Closed on/after HITL6_DISPO_EPOCH are read; an unparseable or
    # absent Closed date is CONSIDERED (fail-closed, leg-2's posture).
    # ⚠️ THE TWO BINDINGS DECAY DIFFERENTLY, AND ONLY ONE OF THEM DID (review M1):
    #   • PR NUMBER never decays. Numbers are unique per repo and monotonic, so a Done row citing
    #     #627 can satisfy exactly one PR — #627, which is already merged. Age is irrelevant.
    #   • BRANCH NAME COULD decay. Branch names RECUR (`feat/fix-board`, `chore/release` are reused
    #     freely), so a Done row closed under this rule citing `feat/x` could satisfy a LATER
    #     `--pr 0 --branch feat/x` pre-push run for unrelated work. FIXED (TIER0-LOCKS-OWED a): the
    #     branch form below is bounded to rows ABSENT from the base board's Done section — see the
    #     `_base_ok` / `_is_done_retro` gating above and in the match block below.
    # WHAT IT IS AND IS NOT: the branch form is reachable only from the PRE-PUSH SPEED BUMP, which
    # `--no-verify` and an uninstalled hook already bypass. The REQUIRED CI CONTEXT runs with
    # `--pr N` (a number exists by then) and is unaffected — the binding that gates the merge never
    # decayed. The epoch bounds the population but cannot bound it to THIS push; the real fix bounds
    # the arm to rows NEW in the pushed change-set, via the base board hooks/pre-push now supplies.
    _ridx=""; _cidx=""; _is_done_retro=0
    if [ -z "$_idx" ]; then
      _is_done_retro=1
      _ridx=$(col_index "$_hdr" "Retro/outcome")
      [ -n "$_ridx" ] || continue              # neither a `PR` nor a `Retro/outcome` column -> skip
      _cidx=$(col_index "$_hdr" "Closed")
      [ -n "$_cidx" ] || continue              # no `Closed` column -> the epoch scope is underivable
    fi
    _n=0
    while IFS= read -r _row; do
      _n=$((_n + 1))
      [ "$_n" -eq 1 ] && continue              # row 1 is the section header, not data (parity w/ check_section)
      is_sep_row "$_row" && continue
      if [ -n "$_idx" ]; then
        _c=$(cell "$_row" "$_idx")
      else
        # out of the one-PR rule's scope -> this row's retro binds nothing (H1).
        # gfm_cell, NOT cell: an escaped pipe left of this column shifts a raw split, and the epoch
        # test fail-closes on an unparseable date — the `B8` shape measured live on this board.
        closed_pre_epoch "$(gfm_cell "$_row" "$_cidx")" "$HITL6_DISPO_EPOCH" && continue
        _c=$(retro_cell "$_row" "$_hdr" "$_ridx")
      fi
      # whole-token match: kills the #28 substring AND the #2800 superstring collision.
      # ⚠️ `--pr 0` IS NOT A PR NUMBER (security S3). The pre-push caller passes 0 to mean "no PR
      # exists yet"; there is no PR #0 on any forge. Matching it would let a row whose cell literally
      # bears `#0` — a placeholder, a typo, a dash-and-zero — satisfy the gate for EVERY branch at
      # once, which is the one binding this gate must never accept. With 0 the branch is the only
      # key, and if no branch was supplied there is nothing left to match.
      if [ "$_pr" != 0 ] && printf '%s' "$_c" | grep -Eq "(^|[^0-9])#${_pr}([^0-9]|$)"; then
        rm -f "$_rows_f"; return 0
      fi
      # ...OR the BRANCH NAME as a whole token. Same boundary discipline as the number: `fix/p1-ci` must
      # NOT match a cell bearing `fix/p1-ci-path-scope`, so every char legal in a git ref is a non-boundary.
      if [ -n "$_bre" ] && printf '%s' "$_c" | grep -Eq "(^|[^${BRANCH_CHARS}])${_bre}([^${BRANCH_CHARS}]|\$)"; then
        # TIER0-LOCKS-OWED (a): in the Done arm, the branch form binds ONLY for a row absent from
        # the base board's Done section (change-set-new), keyed on the row-id token. An unreadable
        # base board (_base_ok=0) never binds — fail-safe.
        if [ "$_is_done_retro" = 1 ]; then
          if [ "$_base_ok" != 1 ]; then
            _rbp_base_suppressed=1  # base board unreadable -> this row's branch form does not bind; keep scanning.
          else
            _rid=$(gov_row_id "$_row")
            # security review, 2026-09-10: an ID-LESS Done row must NOT bind by branch. The staleness
            # check is KEYED ON THE ROW-ID (base_row_in_done "$_basebl" "$_rid"); with no id there is
            # nothing to look up, so `[ -n "$_rid" ] && base_row_in_done ...` was simply FALSE and fell
            # through to the `else` (bind) arm — fail-OPEN on the one shape it could not verify. An
            # unverifiable row is treated the same as an unreadable base board: does not bind.
            if [ -z "$_rid" ]; then
              : # no row-id token -> change-set-new status cannot be verified; does not bind by branch.
            elif base_row_in_done "$_basebl" "$_rid"; then
              : # row already Done in the base board -> stale/carried, does not bind by branch.
            else
              rm -f "$_rows_f"; return 0
            fi
          fi
        else
          rm -f "$_rows_f"; return 0
        fi
      fi
    done < "$_rows_f"
  done
  rm -f "$_rows_f"; return 1
}

# ── THE STRANGER'S REFUSAL (PRE-PUSH-RUNS-BACKLOG-PRESENCE design §3.4) ────────────────────────
# hooks/pre-push runs this gate LOCALLY, before a PR exists, with `--pr 0`. Two consequences the
# wording has to carry: a literal "PR #0" names nothing and must never be printed, and the reader is
# an operator mid-push with no board context — so the refusal states which row is probably theirs and
# the exact edit that clears it. It is still a READ: this gate never writes the board (a hook that
# edited control-plane state on a push would cross the propose/ratify line).
#
# inprogress_hints <board> — print the backticked identifier of each row sitting In Progress, one per
# line. TBG-SEAM-MD-ARM T-WAVE1B: routed through `seam_rows_in_state in-progress` — a pure state-list
# read, which IS tracker-portable (a tracker lists its In-Progress rows the same way), unlike
# row_bears_pr's PR-number/branch inverse search (left on the shared primitives — no tracker
# analogue, §4.2's pr-bound note: a tracker answers pr-bound from the Kit-Row trailer, never a board
# search). SEAM_ROOT is derived from the board path's directory — every call site here passes
# "$dir/BACKLOG.md", so dirname($1) is exactly the project root the seam is configured with
# elsewhere in this file (mirrors check_pr's own `SEAM_ROOT="$_dir"`).
# ⚠️ A BOARD CELL IS UNTRUSTED TEXT AND A TERMINAL IS A SINK. Every identifier is passed through
# `tr -cd '[:print:]'` (control/escape bytes stripped — a cell carrying an ANSI sequence must not be
# able to repaint the operator's terminal) and emitted with `printf '%s\n'` as an ARGUMENT, never as
# a format string. The board is not attacker-controlled in the ordinary case; it is text of unbounded
# provenance in every other one. seam_rows_in_state's own extraction (backtick_id) is byte-identical
# to the case statement this replaced, so this filter is still the only behavioural change site.
inprogress_hints() {
  SEAM_ROOT=$(dirname "$1")
  _ih_f=$(mktemp)
  seam_rows_in_state in-progress > "$_ih_f" 2>/dev/null || :
  if [ -s "$_ih_f" ]; then
    while IFS= read -r _ih_id; do
      _ih_id=$(printf '%s' "$_ih_id" | tr -cd '[:print:]')
      [ -n "$_ih_id" ] || continue
      printf '%s\n' "$_ih_id"
    done < "$_ih_f"
  fi
  rm -f "$_ih_f"
}

# ── THE CLAIMS ARM (BOARD-CLAIM-MECHANISM design §3.2) ─────────────────────────────────────────
# Entering In Progress is supposed to be an ATOMIC ownership claim. For the BACKLOG.md backend the
# mechanism behind that sentence was merge-time serialization: two branches each move a row, and git
# only notices at the SECOND squash-merge, days after both sessions started. scripts/board-claim.sh
# makes the claim a forge ref (refs/claims/<ROW-ID>) — this arm is what makes the board and the refs
# agree at CI time: every row the PUSHED board carries In Progress must have a LIVE claim ref, and
# that claim must name THIS PR's head branch.
#
# ⚠️ THIS ARM IS THE ONE PART OF THIS GATE THAT USES THE NETWORK, and the header's "no network"
# guardrail is qualified accordingly. It runs ONLY when `--claims` is passed, which ONLY the CI PR job
# does; the pre-push run stays offline (hooks/pre-push never passes it) because a push-time gate that
# needs the forge is a gate that fails on a plane. The local speed bump is `board-claim.sh check`.
#
# WHY IT DELEGATES rather than re-implementing the ref read: board-claim.sh already owns the
# absent-vs-unreachable probe (`ls-remote --exit-code`), the scratch-ref fetch, the untrusted-CLAIM
# parse and the control-byte scrub. A second implementation of that transaction would drift, and the
# drift would be invisible to both files' tests — the same reason backlog-lib.sh exists for the board
# parser. The contract consumed here is the three `claim-*:` lines board-claim.sh's `check` prints.
#
# rc: 0 every In Progress row is claimed by this branch (or there are none) · 1 WAITING (a row with
# no claim — the healthy first-run state, naming the remedy) · 2 REFUSED (a row claimed by ANOTHER
# branch, or a claim that could not be adjudicated at all). REFUSED dominates WAITING.
BP_CLAIM_SH="scripts/board-claim.sh"

check_claims() {
  _cc_dir="$1"; _cc_br="$2"
  _cc_board="$_cc_dir/BACKLOG.md"
  _cc_sh="$(pwd)/$BP_CLAIM_SH"
  [ -f "$_cc_sh" ] || { echo "FAIL: backlog-presence --claims — $BP_CLAIM_SH is missing; the claim arm cannot be adjudicated"; return 2; }
  _cc_f=$(mktemp); _cc_rc=0
  inprogress_hints "$_cc_board" > "$_cc_f"
  while IFS= read -r _cc_row; do
    [ -n "$_cc_row" ] || continue
    if _cc_out=$( cd "$_cc_dir" && sh "$_cc_sh" check "$_cc_row" 2>&1 ); then _cc_r=0; else _cc_r=$?; fi
    if [ "$_cc_r" = 1 ]; then
      echo "FAIL: backlog-presence --claims — row \`$_cc_row\` sits In Progress but NO claim ref exists on origin (refs/claims/$_cc_row). Entering In Progress is a claim; remedy: sh $BP_CLAIM_SH claim $_cc_row --branch '$_cc_br'"
      [ "$_cc_rc" = 2 ] || _cc_rc=1
      continue
    fi
    if [ "$_cc_r" != 0 ]; then
      echo "FAIL: backlog-presence --claims — the claim on row \`$_cc_row\` could not be adjudicated (board-claim.sh check exited $_cc_r; an unreachable remote is rc 2 and is NEVER read as 'no claim')."
      _cc_rc=2
      continue
    fi
    # The claim exists. It must name THIS branch — a live claim held by someone else's branch is the
    # double-claim this whole mechanism exists to refuse, and it is a REFUSAL (rc 2), never a wait.
    _cc_hb=$(printf '%s\n' "$_cc_out" | grep '^claim-branch: ' | head -1)
    _cc_hb=${_cc_hb#claim-branch: }
    # An UNREADABLE / MALFORMED CLAIM yields no `claim-branch:` line at all, and an empty branch is
    # not a branch (reviewer R-12): reporting it as "CLAIMED by '' at  on branch ''" dresses three
    # missing facts as findings. Same refusal rc, named for what it is.
    if [ -z "$_cc_hb" ]; then
      echo "REFUSED: backlog-presence --claims — row \`$_cc_row\` has a claim ref on origin whose CLAIM is unreadable or malformed (no holder, branch or time could be read), so it cannot be shown to belong to this PR's branch '$_cc_br'."
      _cc_rc=2
      continue
    fi
    if [ "$_cc_hb" != "$_cc_br" ]; then
      _cc_ho=$(printf '%s\n' "$_cc_out" | grep '^claim-holder: ' | head -1); _cc_ho=${_cc_ho#claim-holder: }
      _cc_at=$(printf '%s\n' "$_cc_out" | grep '^claim-at: '     | head -1); _cc_at=${_cc_at#claim-at: }
      echo "REFUSED: backlog-presence --claims — row \`$_cc_row\` is CLAIMED by '$_cc_ho' at $_cc_at on branch '$_cc_hb', not by this PR's branch '$_cc_br'. Two branches are working one row."
      _cc_rc=2
      continue
    fi
    echo "OK: backlog-presence --claims — row \`$_cc_row\` is claimed on origin by this branch '$_cc_br'"
  done < "$_cc_f"
  rm -f "$_cc_f"
  return "$_cc_rc"
}

# bp_tracker_presence <head-sha> -> F-1's TRACKER ARM of check_pr's gated/non-md branch (design §3e).
# The Kit-Row trailer on $1 (git's own `valueonly` idiom, mirroring loop-state.sh's decl_field —
# NEVER a grep, which a squash-merge's trailing Co-authored-by line would demote to prose) names
# the ONE row graded — never taken from the record's own `requested` line (a record proves only
# what it read, never which row THIS head is about; seam_row_state's own requested==caller-id check
# enforces that a second time). $SEAM_ROOT already equals the project dir this head's commit lives
# in (check_pr sets it before calling — mirrors loop-state.sh's LS_REPO/LS_BOARDROOT sharing one
# value). Sentences carry only the row id and closed-vocabulary tokens (§4.1/§4.2), never record text.
# rc: 0 bound, In Progress/In Review, claimed (F-1) · 1 the healthy WAIT (absent/malformed trailer,
# wrong state, claimed=no) · 2 the tracker record does not bind this row for this head — UNVERIFIED.
# _btp_valid_head <head> -> rc0 iff a well-formed 40- or 64-hex sha (B3: aligned with the reader's
# and the seam's own tr_valid_head/40|64 grammar) names a real commit in $SEAM_ROOT. Extracted so
# bp_tracker_presence stays under the line ceiling. fix1 Q2 (injection): refuse the grammar BEFORE
# any git call ever reads the value positionally (`--output=<p>` WRITES a file; `--help` mis-execs)
# — spelled-out hex class, no bracket-range locale surprise. Sets _BTP_HEAD_ERR to `grammar` or
# `exists` (B3) so the caller can name the right cause instead of one merged sentence.
_btp_valid_head() {
  _BTP_HEAD_ERR=grammar
  _btp_l=${#1}
  [ "$_btp_l" -eq 40 ] || [ "$_btp_l" -eq 64 ] || return 1
  case "$1" in *[!0123456789abcdef]*) return 1 ;; esac
  _BTP_HEAD_ERR=exists
  git -C "$SEAM_ROOT" cat-file -e "$1^{commit}" 2>/dev/null || return 1
  # WB-FIX-2 item 3: cat-file -e alone can resolve a 64-hex STRING AS A REF NAME in a SHA-1 repo (no
  # SHA-1 object can BE 64 hex chars, so git falls back to a ref lookup) — pin that the value
  # self-resolves to ITSELF, never to some other commit a same-named branch happens to point at.
  [ "$(git -C "$SEAM_ROOT" rev-parse --verify --quiet "$1^{commit}" 2>/dev/null)" = "$1" ]
}

# _btp_seam_call <fn> <args...> -> sets _BTP_VAL to <fn>'s stdout, returns its rc. fix1 Q3: PLAIN
# (no `$( … )` subshell — mirrors inprogress_hints' :301 idiom) so the T89s parse-memo survives
# between bp_tracker_presence's two seam calls; a subshell drops it, forcing a second full parse.
_btp_seam_call() {
  _bsc_f=$(mktemp)
  if "$@" >"$_bsc_f" 2>/dev/null; then _bsc_rc=0; else _bsc_rc=$?; fi
  _BTP_VAL=$(cat "$_bsc_f"); rm -f "$_bsc_f"
  return "$_bsc_rc"
}

bp_tracker_presence() {
  _btp_head="$1"
  _btp_valid_head "$_btp_head" || {
    if [ "$_BTP_HEAD_ERR" = exists ]; then
      echo "FAIL: backlog-presence — the PR head is not a well-formed, existing commit sha (well-formed hex, but names no commit in this repo); refusing (gated change-class, tracker backend)."
    else
      echo "FAIL: backlog-presence — the PR head is not a well-formed, existing commit sha (not 40 or 64 lowercase hex); refusing (gated change-class, tracker backend)."
    fi
    return 2
  }
  _btp_row=$(git -C "$SEAM_ROOT" log -1 --format="%(trailers:key=Kit-Row,valueonly)" "$_btp_head" 2>/dev/null)
  # `grep -c .` rc's 1 on zero matches (an absent trailer) — `|| true` so THAT is never confused
  # with a script bug under set -e (mirrors loop-state.sh's decl_count, same reason).
  _btp_n=$(printf '%s\n' "$_btp_row" | grep -c . || true)
  if [ "$_btp_n" -eq 0 ]; then
    echo "FAIL: backlog-presence — $_btp_head carries no parseable 'Kit-Row' trailer (gated change-class, tracker backend)."
    return 1
  fi
  # fix1 Q4: a SECOND trailer is a distinct defect from a missing one.
  [ "$_btp_n" -eq 1 ] \
    || { echo "FAIL: backlog-presence — $_btp_head must carry exactly one 'Kit-Row' trailer, not $_btp_n (gated change-class, tracker backend)."; return 1; }
  row_id_ok "$_btp_row" \
    || { echo "FAIL: backlog-presence — Kit-Row '$_btp_row' is not a well-formed row id ([A-Z0-9][A-Z0-9-]*)."; return 1; }
  SEAM_HEAD="$_btp_head"
  _btp_seam_call seam_row_state "$_btp_row" \
    || { echo "FAIL: backlog-presence — the tracker record does not bind row \`$_btp_row\` for this head — UNVERIFIED."; return 2; }
  _btp_state="$_BTP_VAL"
  case "$_btp_state" in
    in-progress|in-review) ;;
    *) echo "FAIL: backlog-presence — row \`$_btp_row\` sits '$_btp_state' on the tracker, not In Progress/In Review (gated change-class)."; return 1 ;;
  esac
  _btp_seam_call seam_row_flag "$_btp_row" claimed \
    || { echo "FAIL: backlog-presence — the tracker record carries no 'claimed' flag for row \`$_btp_row\` — UNVERIFIED."; return 2; }
  _btp_claimed="$_BTP_VAL"
  # fix1 Q4: `n/a` (never real for `claimed`; only reachable if mis-wired onto e.g. `pr-bound`)
  # gets its own sentence — "board claim" is the wrong remedy for it.
  [ "$_btp_claimed" != n/a ] \
    || { echo "FAIL: backlog-presence — row \`$_btp_row\` carries no 'claimed' answer on the tracker (n/a) — UNVERIFIED."; return 2; }
  if [ "$_btp_claimed" != yes ]; then
    echo "FAIL: backlog-presence — row \`$_btp_row\` is not claimed; remedy: sparkwright board claim $_btp_row"
    return 1
  fi
  echo "OK: backlog-presence — row \`$_btp_row\` is claimed and $_btp_state on the tracker"
  return 0
}

# check_pr <project-dir> <pr-number> <changed-file> -> the REAL run. Emits a verdict STRING (N/A / OK /
# FAIL) and returns a PARTITIONED rc (B5 rider BACKLOG-PRESENCE-WAITING-PARTITION):
#   rc 0 = pass / N-A · rc 1 = the genuine no-row WAIT (a healthy stage: the poster renders it yellow)
#   rc 2 = MISCONFIGURATION (unrecognized backend; md declared but no BACKLOG.md) — a broken gate, red.
#   rc 3 = NOT ENFORCED (a hosted-tracker backend: this gate reads BACKLOG.md only) — red, and NOT
#     clearable by any edit to this repo's code; the ladder is a ratified `board-governance` waiver
#     or `TRACKER-BACKED-GOVERNANCE`. It is a PARTITION, never a bypass: only hooks/pre-push maps it
#     to allow, and it relays the sentence when it does (NON-MD-BACKEND-NEVER-SILENT, D-240903-1 §3).
# Before the partition all three FAIL routes collapsed to rc 1, so a poster could not tell a waiting
# gate from a broken one. (rc 2 is also the dispatcher's usage rc — both are red, no route conflates
# with the wait.) Targets by ARGUMENT, never the environment.
# The `[ -f "$_bl" ]` guard below is the load-bearing hard precondition for row_bears_pr (see its note):
# without it a declared-md board that is absent would abort under `set -eu`; with it the absence becomes
# the honest FAIL this dark-gate detector exists to raise.
check_pr() {
  _dir="$1"; _pr="$2"; _cf="$3"; _br="${4:-}"; _claims="${5:-0}"; _basebl="${6:-}"; _head="${7:-}"
  # TRACKER-TRUSTED-JOB-REQUIRED-CONTEXT T1: the base checkout + the live required-contexts file,
  # BY ARGUMENT (never the environment) — see bp_tracker_delegated below.
  _bd="${8:-}"; _lc="${9:-}"
  # ── ORDINARY CHANGE-CLASS: PRESENCE IS N/A, A CLAIM IS NOT (reviewer R-6) ──────────────────────
  # As first built the claims arm sat behind BOTH this gate-class return AND the presence pass below,
  # so an ORDINARY PR — a docs tweak, a README fix — never reached it. That is precisely the shape the
  # mechanism has to cover: a row is claimed by ROW ID, and the second session's PR being ordinary
  # says nothing at all about whether two branches are working one row. The arm now runs whenever the
  # PUSHED BOARD CARRIES AT LEAST ONE In Progress ROW, independent of class. For GATED PRs the
  # ordering below is unchanged (presence first — a PR with no bound row is already waiting on an edit
  # to the very table the claims arm reads, and two refusals at once fix neither faster).
  if [ "$(gate_class "$_cf")" != gated ]; then
    echo "N/A: ordinary change-class; board row not required"
    [ "$_claims" = 1 ] || return 0
    SEAM_ROOT="$_dir"
    _otok=$(seam_backend)
    [ "$_otok" = md ] || return 0
    _obl="$_dir/BACKLOG.md"
    [ -f "$_obl" ] || return 0
    if is_pure_template "$_obl"; then return 0; fi
    [ -n "$(inprogress_hints "$_obl")" ] || return 0
    if check_claims "$_dir" "$_br"; then return 0; else return $?; fi
  fi
  SEAM_ROOT="$_dir"
  # TBG-READER-FLAGS-LIST T8 (design §3e, H-4): the ONE site, mirroring loop-state.sh's run_gate —
  # backlog-lib.sh's tracker arm never reads ${KIT_TRACKER_RECORD} itself, only $SEAM_RECORD, set
  # once, here. An unset KIT_TRACKER_RECORD leaves SEAM_RECORD empty, so seam_tracker_record_set
  # below stays false and every byte of today's non-md path (through not_enforced_notice) is unchanged.
  SEAM_RECORD="${KIT_TRACKER_RECORD:-}"
  _tok=$(seam_backend)
  [ -n "$_tok" ] || { echo "N/A: no backlog backend declared"; return 0; }
  # A fat-fingered backend (`markdow`, `TBD`) is signalled `unrecognized:<token>` by resolve_backend so
  # it does NOT fail open. FAIL on it (never collapse into the generic non-md N/A below) — this is the
  # dark-gate class the slice closes, and it mirrors backlog-current.sh:255-261 so the two gates reading
  # one resolve_backend speak with one voice about what an unrecognized backend means. rc 2, not 1: a
  # misconfigured gate is BROKEN (red), never the same yellow as a healthy waiting one (B5 partition).
  case "$_tok" in
    unrecognized:*)
      _bad=${_tok#unrecognized:}
      echo "FAIL: unrecognized backlog backend '$_bad' (known: md github jira ado linear gitlab)"
      return 2 ;;
  esac
  # A NON-MD BACKEND IS NOT AN N/A (NON-MD-BACKEND-NEVER-SILENT). It used to print
  # `N/A: backend '<x>' is not BACKLOG.md` and return 0 — a green light over unverified governance.
  # rc 3 is the NOT ENFORCED partition (see backlog-lib.sh::not_enforced_notice for what it means
  # and what clears it); the CI job enumerates it as red, and hooks/pre-push allows the push with
  # the sentence relayed, because a push-time speed bump is not where a tracker adopter should
  # learn the kit has no seam.
  if [ "$_tok" != md ]; then
    # TBG-READER-FLAGS-LIST T8 (design §3e/§8a "Twins"): a SET SEAM_RECORD switches to the tracker
    # arm — bind (rc0) or refuse per F-1 (rc1/rc2), NEVER waivable, NEVER falling through to
    # not_enforced_notice below (H-4: an UNSET SEAM_RECORD keeps this branch byte-identical to before).
    if seam_tracker_record_set; then
      bp_tracker_presence "$_head"; return $?
    fi
    # TRACKER-TRUSTED-JOB-REQUIRED-CONTEXT T1 (design §2b, RD-2): the step-aside is checked ONLY
    # HERE, strictly AFTER the seam_tracker_record_set branch above has already returned — the
    # trusted job (which sets SEAM_RECORD) is never itself excused by its own required-context
    # wiring (no self-delegation). bp_tracker_delegated reads ONLY $_bd (--base-dir), never $_dir
    # (the head's --dir, attacker-writable on pull_request) — RD-1/L3/L7's load-bearing negative.
    if bp_tracker_delegated "$_bd" "$_lc"; then
      tracker_delegated_notice
      return 0
    fi
    _bp_ne=0
    # $0-RELATIVE, never cwd-relative (security S-L5). This script `cd`s to the repo root at :36 so
    # the bare path happened to work today, but the validator's location is a property of where THIS
    # file lives, not of where the process happens to stand — and a caller that changes directory
    # (or a future edit that drops the cd) would silently read "validator absent" and treat every
    # waiver as missing. backlog-current.sh already resolved it this way; now both do.
    not_enforced_notice "$_tok" "$_dir" "$(dirname "$0")/waivers-valid.sh" \
      "$(tracker_delegated_cure)" \
      || _bp_ne=$?
    return "$_bp_ne"
  fi
  _bl="$_dir/BACKLOG.md"
  [ -f "$_bl" ] || { echo "FAIL: declares an md backend but has no BACKLOG.md"; return 2; }
  if is_pure_template "$_bl"; then echo "N/A: board not yet in use (pristine template)"; return 0; fi
  # The verdict STRINGS are a contract (the selftest asserts them verbatim, and humans read them in CI
  # logs). When no --branch is supplied the message is byte-for-byte what it always was — branch binding
  # is ADDITIVE and must not perturb the existing surface. The branch is named only when it is in play.
  if row_bears_pr "$_bl" "$_pr" "$_br" "$_basebl"; then
    if [ -n "$_br" ] && [ "$_pr" = 0 ]; then
      # The pre-push form: there is no PR yet, so the verdict names the only binding that exists.
      echo "OK: backlog-presence — branch '$_br' is bound to a board row (PR column)"
    elif [ -n "$_br" ]; then
      echo "OK: backlog-presence — PR #$_pr (or branch '$_br') is bound to a board row (PR column)"
    else
      echo "OK: backlog-presence — PR #$_pr is bound to a board row (PR column)"
    fi
    # The claims arm runs ONLY after the presence verdict has PASSED, and only under --claims. A PR
    # with no bound row is already waiting on an edit to the very table the claims arm reads; adding a
    # second refusal there would tell the operator two things at once and fix neither faster.
    if [ "$_claims" = 1 ]; then
      if check_claims "$_dir" "$_br"; then return 0; else return $?; fi
    fi
    return 0
  fi
  # The genuine no-row WAIT: rc 1 (the poster renders it yellow). The trailing sentence is the
  # B6-routed legibility pointer — the B6 probe itself mis-bound a row outside a `PR` column, and
  # nothing on the rendered check-run said where the row has to live.
  # A1-10 — WHEN jq IS ABSENT, SAY SO. gate_class fail-safes EVERY change-set to `gated` without jq
  # (its documented posture), so on a jq-less machine an enforcing pre-push dial can refuse an
  # ordinary change. A refusal that does not name that cause sends the operator to edit a board row
  # when the fix is to install jq. The probe lives here rather than in gate_class deliberately: that
  # function's output is an exact token four selftest legs pin, and it runs in a command substitution
  # whose variables cannot come back (measured — see design amendment A2).
  # ⚠️ THE REFUSAL MUST NAME BOTH BINDINGS (SLICE-CLOSES-IN-ONE-PR §4.4, security vet L1). Under
  # the one-PR close a slice's row goes straight to DONE on the push that is expected to merge, so
  # an operator told only "move your row to In Review" is being sent to the flow this slice
  # replaced. Text only — the matcher above is what actually decides.
  _doneform=" Under the one-PR close the row may instead sit in Done, Closed on/after $HITL6_DISPO_EPOCH, with the token in its Retro/outcome cell."
  _jqnote=""
  command -v jq >/dev/null 2>&1 \
    || _jqnote=" NOTE: jq is not installed, so the change-class was fail-safed to gated — this may not be a gated change at all; install jq for full resolution."
  # S-6 RELAY (security review, 2026-09-10): the sentence above (_doneform) names Done as a valid
  # alternative form, but if row_bears_pr suppressed a Done-row branch match because the base board
  # was unreadable, that alternative was never actually evaluated — saying only "$_doneform" would
  # read as "we checked Done and it doesn't bind" when the truth is "we could not check". Name the
  # cause and the remedy instead (the promise at row_bears_pr's TIER0-LOCKS-OWED-a comment).
  _basenote=""
  [ "${_rbp_base_suppressed:-0}" = 1 ] && _basenote=" NOTE: the base board (origin/main's BACKLOG.md) was unreadable locally, so the Done-form branch binding was NOT evaluated for a candidate row — run 'git fetch origin main' and push again to have it checked."
  if [ -n "$_br" ] && [ "$_pr" = 0 ]; then
    echo "FAIL: backlog-presence — no board row bears branch '$_br' in its PR cell (gated change-class). The row must sit in a section with a \`PR\` column — In Review in the shipped schema.$_doneform$_jqnote$_basenote"
  elif [ -n "$_br" ]; then
    echo "FAIL: backlog-presence — no board row bears PR #$_pr or branch '$_br' in its PR cell (gated change-class). The row must sit in a section with a \`PR\` column — In Review in the shipped schema.$_doneform$_jqnote$_basenote"
  else
    echo "FAIL: backlog-presence — no board row bears PR #$_pr in its PR cell (gated change-class). The row must sit in a section with a \`PR\` column — In Review in the shipped schema.$_doneform$_jqnote$_basenote"
  fi
  # The hint + remedy block, only when a branch is in play (the CI form's reader has the PR page in
  # front of them; the pre-push form's reader has a terminal). At most three rows are named — a
  # refusal that pastes the whole section is the annoyance this replaces, not the teaching one.
  if [ -n "$_br" ]; then
    _hints=$(inprogress_hints "$_bl")
    _hn=0
    [ -n "$_hints" ] && _hn=$(printf '%s\n' "$_hints" | wc -l | tr -d ' ')
    if [ "$_hn" -gt 3 ]; then
      printf '  likely yours: %s rows are sitting in In Progress — move the one that is yours\n' "$_hn"
    elif [ "$_hn" -gt 0 ]; then
      printf '%s\n' "$_hints" | while IFS= read -r _h; do
        printf '  likely yours: `%s` (sitting in In Progress)\n' "$_h"
      done
    fi
    printf "  remedy: move your row to In Review and put \`%s\` in its PR cell — or, under the one-PR close, move it to Done (Closed today) with \`%s\` named in its Retro/outcome cell; commit BACKLOG.md; push again.\n" "$_br" "$_br"
  fi
  return 1
}

# ── ORACLE MARKER: selftest() and everything below is the non-vacuity oracle region. The mutation
#    harness (conformance/non-vacuity.sh) neuters ONLY lines strictly ABOVE this line, so the
#    oracle's own st_fail accumulator can never be flipped. assert_* helpers + fixture writers live
#    BELOW here on purpose (mirrors backlog-current.sh's assert_msg at :1001).
selftest() {
  st_fail=0
  base=$(mktemp -d)

  # ===== T1 — the PR-cell presence assertion (spec §3, §7) =============================

  # a board whose In Review row bears #280 -> PRESENT (rc0). The positive liveness anchor.
  d="$base/t1_present"
  _board "$d" '| KW6-A2 | — | #280 |'
  assert_present "$d" 280 "t1/present: In Review PR cell bears #280 -> rc0 (present)"

  # substring collision: PR cell bears #28, asked for 280 -> ABSENT (rc1).
  d="$base/t1_substring"
  _board "$d" '| KW6-A2 | — | #28 |'
  assert_absent "$d" 280 "t1/substring: #28 must not satisfy #280 -> rc1 (absent)"

  # superstring collision: PR cell bears #2800, asked for 280 -> ABSENT (rc1).
  d="$base/t1_superstring"
  _board "$d" '| KW6-A2 | — | #2800 |'
  assert_absent "$d" 280 "t1/superstring: #2800 must not satisfy #280 -> rc1 (absent)"

  # #280 appears ONLY in a Notes cell, not the PR cell -> ABSENT (rc1). Binds to the column.
  d="$base/t1_notes"
  _notes_board "$d" 'supersedes #280'
  assert_absent "$d" 280 "t1/notes-cell: #280 in a Notes cell must not satisfy -> rc1 (absent)"

  # PR cell empty -> ABSENT (rc1).
  d="$base/t1_empty"
  _board "$d" '| KW6-A2 | — | |'
  assert_absent "$d" 280 "t1/empty: empty PR cell must not satisfy -> rc1 (absent)"

  # ===== T1b — BRANCH-NAME BINDING (P1-CI 2/2) ==========================================
  # The PR number cannot exist before the PR is opened, so a number-only gate FORCES a second push
  # (and a second full CI run) on every gated PR, forever. A branch name exists BEFORE the PR — so a
  # row bound by branch can land in the PR-opening commit. Both bindings are accepted.

  # a row whose PR cell bears the BRANCH NAME, with NO number yet -> PRESENT.
  d="$base/t1b_branch"
  _board "$d" '| P1-CI | — | fix/p1-ci-path-scope |'
  assert_present "$d" 999 "t1b/branch: PR cell bears the branch name (no number yet) -> rc0 (present)" "fix/p1-ci-path-scope"

  # the number still works on its own — branch binding is ADDITIVE, never a replacement.
  d="$base/t1b_number_still"
  _board "$d" '| P1-CI | — | #280 |'
  assert_present "$d" 280 "t1b/number-still-works: number binding unaffected by the branch arg" "some/other-branch"

  # NO branch supplied -> behaves exactly as before (number-only). Regression lock.
  d="$base/t1b_nobranch"
  _board "$d" '| P1-CI | — | fix/p1-ci-path-scope |'
  assert_absent "$d" 280 "t1b/no-branch-arg: a branch cell must NOT satisfy when no --branch was passed"

  # PREFIX COLLISION — the boundary discipline the number match already has. A cell bearing
  # `fix/p1-ci-path-scope` must NOT satisfy the branch `fix/p1-ci`: every char legal in a git ref is a
  # non-boundary, so the trailing `-` blocks the match. Without this, a branch could bind to any row
  # whose cell merely STARTS with its name.
  d="$base/t1b_prefix"
  _board "$d" '| P1-CI | — | fix/p1-ci-path-scope |'
  assert_absent "$d" 999 "t1b/prefix: branch 'fix/p1-ci' must NOT match cell 'fix/p1-ci-path-scope'" "fix/p1-ci"

  # a branch name in a NOTES cell must not satisfy — the binding is to the PR COLUMN, same as the number.
  d="$base/t1b_notes"
  _notes_board "$d" 'see fix/p1-ci-path-scope'
  assert_absent "$d" 999 "t1b/notes-cell: a branch in a Notes cell must not satisfy -> rc1" "fix/p1-ci-path-scope"

  # REGEX-METACHAR SAFETY — a branch name is attacker-influenceable (anyone can open a PR from a branch),
  # so it is UNTRUSTED INPUT TO A REGEX. A branch of `.*` must match literally, never as a wildcard that
  # satisfies every row on the board.
  d="$base/t1b_meta"
  _board "$d" '| P1-CI | — | #280 |'
  assert_absent "$d" 999 "t1b/metachar: a branch of '.*' must not wildcard-match any PR cell" '.*'

  # ===== T1c — THE DONE ARM (SLICE-CLOSES-IN-ONE-PR §4.2) ==============================
  # A slice now closes in ONE PR: the row moves to Done on the push that is expected to merge,
  # so the binding token lives in the Done row's Retro/outcome cell, not in a `PR` column (Done
  # has none, and adding one would shift 228 shipped rows). The SAME whole-token matcher is
  # applied there, read through retro_cell semantics (escaped-pipe-robust).
  # SCOPE IS EPOCH-BOUND (security vet H1): only rows whose `Closed` cell is on/after
  # HITL6_DISPO_EPOCH are considered. The live Done table carries 281 `#N` tokens and 96 rows
  # naming two or more branches/ids in their retros; an arm over all of them would let a STALE
  # row satisfy presence for work it never described. An unparseable/absent Closed date is
  # CONSIDERED (fail-closed, leg-2's posture).

  # a post-epoch Done row whose retro bears #42 -> PRESENT. The positive liveness anchor.
  d="$base/t1c_done_present"
  _done_board "$d" '| `SLICE` | 2026-09-03 | L1 retro. Merged PR #42, all gates green on the first run. |'
  assert_present "$d" 42 "t1c/done-present: post-epoch Done retro bears #42 -> rc0 (present)"

  # ...the same board asked for a DIFFERENT number -> ABSENT. Without this the arm could be a
  # "some Done row exists" check rather than a token match.
  assert_absent "$d" 43 "t1c/done-wrong-number: the same Done retro must not satisfy #43 -> rc1"

  # superstring collision inside a retro cell: #420 must not satisfy #42.
  d="$base/t1c_done_superstring"
  _done_board "$d" '| `SLICE` | 2026-09-03 | L1 retro. Merged PR #420, all gates green on the first run. |'
  assert_absent "$d" 42 "t1c/done-superstring: #420 in a Done retro must not satisfy #42 -> rc1"

  # BRANCH binding in a Done retro — the form the pre-push run (`--pr 0`) actually uses. Row-id is
  # new to the base board's Done section (a fixture-only base with an unrelated row), so it binds
  # under TIER0-LOCKS-OWED (a).
  d="$base/t1c_done_branch"
  _done_board "$d" '| `SLICE` | 2026-09-03 | L1 retro. Shipped from feat/slice-closes on a green first run. |'
  based="$base/t1c_done_branch_base"
  _done_board "$based" '| `UNRELATED` | 2026-09-01 | Some other prior work. |'
  assert_present "$d" 0 "t1c/done-branch: a branch token in a post-epoch Done retro -> rc0" "feat/slice-closes" "$based/BACKLOG.md"

  # ...and the branch boundary discipline holds inside the retro cell too.
  assert_absent "$d" 0 "t1c/done-branch-superstring: 'feat/slice-close' must not match 'feat/slice-closes'" "feat/slice-close" "$based/BACKLOG.md"

  # `--pr 0` MUST NOT bind to a literal `#0` in a Done retro either (security S3 carried into the
  # new arm): 0 means "no PR exists yet", and a `#0` cell would otherwise satisfy every branch.
  d="$base/t1c_done_hash_zero"
  _done_board "$d" '| `SLICE` | 2026-09-03 | L1 retro. A stray #0 placeholder sits in this cell and binds nothing at all. |'
  assert_absent "$d" 0 "t1c/done-hash-zero: a literal '#0' in a Done retro must not satisfy --pr 0" "feat/unbound" "$based/BACKLOG.md"

  # H1 SCOPE, LIVE: the SAME row, Closed one day BEFORE the epoch -> ABSENT. This is the leg that
  # reds a Done arm with no epoch test, and the only one that does.
  d="$base/t1c_done_preepoch"
  _done_board "$d" '| `OLD-ROW` | 2026-09-02 | L1 retro. Merged PR #42 long before this arm existed. |'
  assert_absent "$d" 42 "t1c/done-pre-epoch: a PRE-epoch Done row bearing #42 must NOT satisfy -> rc1"

  # an unparseable Closed cell is CONSIDERED (fail-closed), never skipped.
  d="$base/t1c_done_baddate"
  _done_board "$d" '| `SLICE` | someday | L1 retro. Merged PR #42 with an unparseable Closed cell. |'
  assert_present "$d" 42 "t1c/done-bad-date: an unparseable Closed date is CONSIDERED (fail-closed) -> rc0"

  # ESCAPED PIPE: a GFM-correct `\|` inside the retro shifts a plain cell() parse, so the token
  # after it is invisible to cell() and visible to retro_cell. Derived from the shipped
  # good-done-escaped-pipe fixture in backlog-current.sh, not invented.
  d="$base/t1c_done_escaped"
  _done_board "$d" '| `SLICE` | 2026-09-03 | L1 retro. Shipped the `triggered\|none\|uncertain` detector; merged PR #42. |'
  assert_present "$d" 42 "t1c/done-escaped-pipe: a token AFTER an escaped pipe is still found -> rc0"

  # ===== T1d — TIER0-LOCKS-OWED (a): DONE-ARM BRANCH BINDING BOUNDED TO CHANGE-SET-NEW ROWS ====
  # The Done arm's BRANCH form (not the number form) decays: a stale Done row citing a reused
  # branch would satisfy a later, unrelated push. Bound it to rows ABSENT from the BASE board's
  # Done section (change-set-new), keyed on the row-id token.

  # liveness: a row that is NEW to this push's Done section (absent from the base board entirely)
  # -> branch form binds.
  d="$base/t1d_new"
  _done_board "$d" '| `NEW-ROW` | 2026-09-09 | L1 retro. Shipped from feat/new-row, first push. |'
  based="$base/t1d_new_base"
  _done_board "$based" '| `OTHER-ROW` | 2026-09-08 | Unrelated prior work. |'
  assert_present "$d" 0 "t1d/new: a Done row absent from the base board's Done section binds by branch -> rc0" "feat/new-row" "$based/BACKLOG.md"

  # negative (the decay this closes): a STALE Done row already present in the base board's Done
  # section, citing a branch NOW reused for unrelated work -> does NOT bind.
  d="$base/t1d_stale"
  _done_board "$d" '| `OLD-ROW` | 2026-08-01 | L1 retro. Shipped from feat/reused-name months ago. |'
  based="$base/t1d_stale_base"
  _done_board "$based" '| `OLD-ROW` | 2026-08-01 | L1 retro. Shipped from feat/reused-name months ago. |'
  assert_absent "$d" 0 "t1d/stale: a Done row already present in the base board's Done section must NOT bind by branch -> rc1" "feat/reused-name" "$based/BACKLOG.md"

  # base-present, retro EDITED to add the branch (same row-id, different retro text) -> still does
  # NOT bind: the key is the row-id's presence in base Done, not the retro cell's content.
  d="$base/t1d_edited"
  _done_board "$d" '| `OLD-ROW` | 2026-08-01 | L1 retro, amended to also mention feat/reused-name. |'
  based="$base/t1d_edited_base"
  _done_board "$based" '| `OLD-ROW` | 2026-08-01 | L1 retro, original wording, no branch mentioned. |'
  assert_absent "$d" 0 "t1d/edited-retro: a base-present row-id does not bind even after its retro cell is edited to add the branch -> rc1" "feat/reused-name" "$based/BACKLOG.md"

  # a row that MOVED to Done this push (present in base board elsewhere, e.g. In Progress, but NOT
  # in base's Done section) is still new-to-Done -> binds.
  d="$base/t1d_moved"
  _done_board "$d" '| `MOVED-ROW` | 2026-09-09 | L1 retro. Shipped from feat/moved-row, a green first run. |'
  based="$base/t1d_moved_base"
  mkdir -p "$based"
  cat > "$based/BACKLOG.md" <<'MOVED_EOF'
# Proj — Backlog

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| `MOVED-ROW` | agent | 2026-09-08 | — |

## Done

| Item | Closed | Retro/outcome |
|------|--------|---------------|
| `UNRELATED` | 2026-09-01 | Some other prior work. |
MOVED_EOF
  assert_present "$d" 0 "t1d/moved: a row absent from base's DONE section (present elsewhere) is new-to-Done -> rc0" "feat/moved-row" "$based/BACKLOG.md"

  # FAIL DIRECTION: base board unreadable/absent -> branch form NEVER binds, even for a genuinely
  # new row. Number binding is unaffected (PR-number is unconditional).
  d="$base/t1d_base_unreadable"
  _done_board "$d" '| `NEW-ROW-2` | 2026-09-09 | L1 retro. Shipped from feat/base-missing. |'
  assert_absent "$d" 0 "t1d/base-unreadable-noarg: no --base-board at all -> branch does not bind -> rc1" "feat/base-missing"
  assert_absent "$d" 0 "t1d/base-unreadable-missingfile: a --base-board pointing at a nonexistent file -> branch does not bind -> rc1" "feat/base-missing" "$base/t1d_no_such_file/BACKLOG.md"
  # PR-NUMBER binding is unconditional even with no base board supplied at all.
  d2="$base/t1d_base_unreadable_num"
  _done_board "$d2" '| `NEW-ROW-3` | 2026-09-09 | L1 retro. Merged PR #999, no base board supplied. |'
  assert_present "$d2" 999 "t1d/base-unreadable-number: a PR-number token binds with no --base-board at all -> rc0"

  # base board present but with NO Done section at all (e.g. a fresh/empty board) -> unreadable
  # posture -> branch does not bind.
  d="$base/t1d_base_nodone"
  _done_board "$d" '| `NEW-ROW-4` | 2026-09-09 | L1 retro. Shipped from feat/no-done-section. |'
  based="$base/t1d_base_nodone_base"
  mkdir -p "$based"
  cat > "$based/BACKLOG.md" <<'NODONE_EOF'
# Proj — Backlog

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| `X` | agent | 2026-09-01 | — |
NODONE_EOF
  assert_absent "$d" 0 "t1d/base-no-done-section: a base board with no Done section -> branch does not bind -> rc1" "feat/no-done-section" "$based/BACKLOG.md"

  # t1e (security review, 2026-09-10): an ID-LESS Done row (no backticked identifier in column 1)
  # must NOT bind by branch, even with a READABLE base board (_base_ok=1). base_row_in_done is keyed
  # on the row-id; with no id there is nothing to verify change-set-new status against, and the
  # unverifiable shape must fail the SAME direction as an unreadable base board — never bind.
  d="$base/t1e_no_row_id"
  _done_board "$d" '| No id here | 2026-09-09 | L1 retro. Shipped from feat/no-id-row, a clean run. |'
  based="$base/t1e_no_row_id_base"
  _done_board "$based" '| `UNRELATED` | 2026-09-01 | Unrelated prior work. |'
  assert_absent "$d" 0 "t1e/no-row-id: an id-less Done row does NOT bind by branch, even with a readable base board -> rc1" "feat/no-id-row" "$based/BACKLOG.md"

  # t1f (first-live-run, CONTROL-PLANE-COVERAGE 2026-09-10): a NEW row whose id is merely CITED in a
  # PRIOR base Done row's Retro/outcome (a `**Disposition:** row \`X\`` naming the next slice — the
  # universal shape) but is NOT a column-1 id in base Done -> IS change-set-new -> BINDS by branch.
  # The whole-section grep this replaced returned true here (the id appears in the section text),
  # falsely reading the new row as already-Done. Measured on this slice's own row.
  d="$base/t1f_cited"
  _done_board "$d" '| `NEW-SLICE` | 2026-09-10 | L1 retro. Shipped from feat/new-slice, first push. |'
  based="$base/t1f_cited_base"
  _done_board "$based" '| `PRIOR-SLICE` | 2026-09-08 | L1 retro. Shipped from feat/prior. **Disposition:** row `NEW-SLICE`. |'
  assert_present "$d" 0 "t1f/cited-in-prior-disposition: a new row-id merely cited in a base Done retro still binds by branch -> rc0" "feat/new-slice" "$based/BACKLOG.md"

  # ===== T2 — change-class reconciliation: gate_class (spec §4, §7) ====================
  # gate_class takes a CHANGE-SET LISTING file (newline-delimited paths), by argument.

  # a control-plane path -> gated.
  cf="$base/cf_cp"; printf 'conformance/verify.sh\n' > "$cf"
  assert_gated "$cf" "t2/cp: control-plane path -> gated"

  # a sensitive path (auth/) -> gated. --state says NONE here; --class supplies `sensitive`.
  cf="$base/cf_sensitive"; printf 'src/auth/login.ts\n' > "$cf"
  assert_gated "$cf" "t2/sensitive: src/auth/login.ts -> gated (via --class sensitive)"

  # an ordinary path -> ordinary.
  cf="$base/cf_ordinary"; printf 'README.md\n' > "$cf"
  assert_ordinary "$cf" "t2/ordinary: README.md -> ordinary"

  # ROUTING IS LIVE, fail-safe: an unreadable/nonexistent change-set must NOT fail open.
  assert_gated "$base/cf_nonexistent" "t2/failsafe: unreadable change-set -> gated (never ordinary)"

  # ⚠️ THE "UNDER-DETECTION" FIXTURE — RETAINED, RELABELLED REDUNDANT, AND ITS OLD CLAIM RETRACTED
  # (GUARD-PATH-ENUMERATION-INCOMPLETE S2 fix round, review REV-I3). Same treatment as phase-gate's
  # legT3g/legT3h/legT3i, and for the same reason.
  # WHAT IT USED TO SAY: "--class says `ordinary` for AGENTS.md, --state says control-plane. This
  # fixture goes RED against a gate_class that consults only --class, and GREEN once --state is
  # consulted. It is the proof reconciliation is live rather than decorative. NEVER weaken it."
  # WHY THAT IS NOW FALSE — measured, not reasoned: S1 graduated `AGENTS.md` into guard-core's
  # curated set (2026-08-16) and S2 made `--class` union-aware (2026-08-17), so `--class` answers
  # control-plane for this path on its own. A gate_class consulting ONLY `--class` would pass this
  # fixture, so it no longer discriminates and no longer proves the two-seam order load-bearing.
  # ⚠️ AND THE "NEVER WEAKEN IT" INSTRUCTION IS HONOURED BY NOT PRETENDING: the row is KEPT (a
  # governing harness document must route to `gated`, and that is worth asserting on its own terms),
  # its LABEL is corrected so a green is not over-read, and the retraction is written here rather
  # than left for a reader to discover. Nothing was made easier to pass — the assertion is identical.
  # WHERE THE LOST PROPERTY LIVES NOW: that `--class` really carries the adapter-declared set is the
  # census lock's leg (b) in conformance/promotion-readiness-wired.sh, with a drop-the-union-consult
  # mutant that reds it. If a union-only path ever exists again that `--class` misses, THAT is where
  # it reds — not here.
  cf="$base/cf_agents"; printf 'AGENTS.md\n' > "$cf"
  assert_gated "$cf" "t2/governing-doc: AGENTS.md -> gated (both seams agree since S1+S2; retained-redundant, see note)"

  # ===== T2 — check_pr routes, asserted by VERDICT STRING (spec §4, §5) ================
  # A gated change-set listing (control-plane) drives every non-ordinary route below.
  cfg="$base/cf_gate"; printf 'conformance/verify.sh\n' > "$cfg"
  # an ordinary change-set listing exercises the ordinary N/A route.
  cfo="$base/cf_ord"; printf 'README.md\n' > "$cfo"

  # ordinary change-class -> N/A (no board consulted at all), rc 0.
  d="$base/cp_ordinary"; _proj_md_board "$d" '| KW6-A2 | — | #280 |'
  assert_msg "N/A: ordinary change-class; board row not required" 0 \
    "cp/ordinary-class: ordinary PR -> N/A (board not required), rc 0" "$d" 280 "$cfo"

  # gated + no backend declared -> N/A, rc 0.
  d="$base/cp_nobackend"; mkdir -p "$d"
  assert_msg "N/A: no backlog backend declared" 0 \
    "cp/no-backend: undeclared backend -> N/A, rc 0" "$d" 280 "$cfg"

  # gated + a non-md backend -> NOT ENFORCED, rc 3 (NON-MD-BACKEND-NEVER-SILENT, ruling D-240903-1
  # §3: "governance may never switch off silently"). This USED TO BE `N/A ... rc 0` — three green
  # lights and no governance at all. All FIVE hosted tokens are exercised: the arm is a `case` and
  # a leg on one token cannot see a token dropped from the list.
  for _st_tok in github jira ado linear gitlab; do
    d="$base/cp_nonmd_$_st_tok"; _proj_backend "$d" "$_st_tok"
    assert_msg "NOT ENFORCED: backend '$_st_tok' — board-bound governance is not verified on this tree" 3 \
      "cp/non-md-$_st_tok: $_st_tok backend -> NOT ENFORCED, rc 3 (red), never a silent N/A" "$d" 280 "$cfg"
  done
  # …and the verdict must carry the CURE, or it is a red with no ladder. TRACKER-TRUSTED-JOB-
  # REQUIRED-CONTEXT T1: the stale "adopt TRACKER-BACKED-GOVERNANCE when it ships" (it has shipped)
  # is replaced by the real cure — bind the trusted job as a required context — alongside the two
  # cures that were always there (move the board to BACKLOG.md; ratify a waiver).
  d="$base/cp_nonmd_jira"
  assert_msg "Cure: bind the trusted job as a required context: add tracker-board-gates to REQUIRED-CHECKS.md, then run sh scripts/branch-protection-apply.sh --apply — or move the board to BACKLOG.md, or ratify a board-governance waiver" 3 \
    "cp/non-md-cure: the NOT ENFORCED verdict names the real cure (bind tracker-board-gates), plus the other two" "$d" 280 "$cfg"

  # gated + a non-md backend + a RATIFIED, filled, unexpired board-governance waiver -> rc 0, and
  # the notice still says NOT ENFORCED (the exception is never invisible; §3.5a).
  d="$base/cp_nonmd_waived"; _proj_backend "$d" jira
  # TODAY-RELATIVE dates (security S-M1): a future `Opened` is now refused, because it makes the
  # 90-day maximum nominal — so the 2099 dates this fixture used to carry would make the leg assert
  # the opposite of the rule. GNU then BSD, matching waivers-valid.sh's own dialect pair.
  _bp_d0=$(date -u -d "+0 days" +%Y-%m-%d 2>/dev/null || date -u -v+0d +%Y-%m-%d)
  _bp_d60=$(date -u -d "+60 days" +%Y-%m-%d 2>/dev/null || date -u -v+60d +%Y-%m-%d)
  printf '## Active waivers\n\n| Gate | Reason | Owner | Opened | Expires | Remediation plan | Ratified-by |\n|--|--|--|--|--|--|--|\n| board-governance | the kit reads BACKLOG.md only | @jdoe | %s | %s | adopt TRACKER-BACKED-GOVERNANCE | @sec |\n' "$_bp_d0" "$_bp_d60" \
    > "$d/WAIVER-REGISTER.md"
  assert_msg "NOT ENFORCED: backend 'jira' — waived until $_bp_d60 by @jdoe" 0 \
    "cp/non-md-waived: a ratified board-governance waiver -> rc 0 WITH the notice" "$d" 280 "$cfg"

  # …and an UNFILLED stamp (what incept writes) buys nothing. This is the load-bearing negative for
  # the whole bridge: if a placeholder greened the gate, `incept --backlog jira` would silently
  # waive its own governance.
  d="$base/cp_nonmd_stamp"; _proj_backend "$d" jira
  printf '## Active waivers\n\n| Gate | Reason | Owner | Opened | Expires | Remediation plan | Ratified-by |\n|--|--|--|--|--|--|--|\n| board-governance | the kit reads BACKLOG.md only | [owner] | %s | %s | adopt TRACKER-BACKED-GOVERNANCE | [security-owner] |\n' "$_bp_d0" "$_bp_d60" \
    > "$d/WAIVER-REGISTER.md"
  assert_msg "NOT ENFORCED: backend 'jira' — board-bound governance is not verified on this tree" 3 \
    "cp/non-md-stamp: the UNFILLED incept stamp -> still rc 3 (a stamp is not a ratification)" "$d" 280 "$cfg"

  # ===== T1 (TRACKER-TRUSTED-JOB-REQUIRED-CONTEXT, design §2b + amendment A1 RD-1 arm (a)/RD-2/RD-3)
  # bp_tracker_delegated wiring: the step-aside fires ONLY from the BASE, verified LIVE, and ONLY on
  # the record-unset path. =========================================================================
  _btb="$base/t1_base"; _proj_tracker_base "$_btb"
  _btlive="$base/t1_live.txt"; printf 'ci\ntracker-board-gates\nbacklog-presence\n' > "$_btlive"

  # (a) delegated: base tracker + valid conf + live-contexts lists the context -> rc 0, the delegated N/A.
  d="$base/t1_delegated"; _proj_backend "$d" jira
  assert_msg_ctx "N/A: board governance is delegated to the required context 'tracker-board-gates' (live on the base branch)" 0 \
    "delegate/delegated: base tracker+conf+live-listed -> rc 0, the delegated N/A" "$d" 280 "$cfg" "$_btb" "$_btlive"

  # (b) S-5 (class sweep) — relabelled: THE BACKEND-ONLY NEGATIVE. The HEAD (--dir) declares tracker,
  # the BASE declares md -> still rc 3. This leg alone CANNOT red under a `$_dir` mutant (a predicate
  # that read $_dir's backend instead of $_bd's would ALSO see 'jira' here and still delegate,
  # because the head's declared backend happens to be a tracker too) — it only pins that the base's
  # OWN backend decides over the head's declared token. (c) below (delegate/bypass-head-conf) is the
  # leg that actually kills a `$_dir` swap, because there the head's `.kit/tracker.conf` differs from
  # the base's md declaration.
  _btb_md="$base/t1_base_md"; _proj_backend "$_btb_md" md
  d="$base/t1_head_tracker"; _proj_backend "$d" jira
  assert_msg_ctx "NOT ENFORCED: backend 'jira'" 3 \
    "delegate/bypass-head-tracker: backend-only negative (base decides its OWN backend over the head's) — cannot alone red under a \$_dir mutant" "$d" 280 "$cfg" "$_btb_md" "$_btlive"

  # (c) a head that ALSO plants a valid .kit/tracker.conf on its OWN (--dir) checkout, base still md
  # -> still rc 3 — the predicate never reads $_dir's `.kit/` at all, only $_bd's. THIS is the leg
  # that reds under a `$_dir` mutant (a predicate reading the head's checkout would find a valid
  # tracker.conf here and delegate).
  d="$base/t1_head_conf"; _proj_tracker_base "$d"
  assert_msg_ctx "NOT ENFORCED: backend 'jira'" 3 \
    "delegate/bypass-head-conf: head plants its own tracker.conf on an md base -> rc 3 (reds under a \$_dir mutant)" "$d" 280 "$cfg" "$_btb_md" "$_btlive"

  # (d) base tracker+conf, live-contexts file WITHOUT the line -> rc 3, and the message names the
  # real cure (bind the trusted job), not the stale "when it ships" remedy.
  _btlive_missing="$base/t1_live_missing.txt"; printf 'ci\nbacklog-presence\n' > "$_btlive_missing"
  d="$base/t1_not_live"; _proj_backend "$d" jira
  assert_msg_ctx "Cure: bind the trusted job as a required context" 3 \
    "delegate/not-live: tracker-board-gates absent from the live-contexts file -> rc 3, cure names the bind" "$d" 280 "$cfg" "$_btb" "$_btlive_missing"

  # (e) --live-contexts points at an absent file -> rc 3.
  d="$base/t1_no_live_file"; _proj_backend "$d" jira
  assert_msg_ctx "NOT ENFORCED: backend 'jira'" 3 \
    "delegate/no-live-file: --live-contexts names a file that does not exist -> rc 3 (fail-closed)" "$d" 280 "$cfg" "$_btb" "$base/t1_no_such_file.txt"

  # (f) S-6 (class sweep) — relabelled: DEFENCE IN DEPTH, not independently killed. --base-dir absent
  # (empty) -> rc 3. `[ -n "$_btd_base" ] && [ -d "$_btd_base" ]` is the first guard the predicate
  # runs; an empty _bd also fails `[ -d "" ]` under condition (i)'s own resolve_backend call and
  # under the conf-file existence checks, so removing THIS guard alone would still rc 3 via those
  # later checks — this leg is not the sole witness of any one guard, it is belt-and-suspenders.
  d="$base/t1_no_base_dir"; _proj_backend "$d" jira
  assert_msg_ctx "NOT ENFORCED: backend 'jira'" 3 \
    "delegate/no-base-dir: --base-dir absent -> rc 3 (defence in depth — not independently killed)" "$d" 280 "$cfg" "" "$_btlive"

  # (g) the base declares tracker but its OWN tracker.conf is malformed (http://, not https://) and
  # is refused by that base's own tracker-conf.sh -> rc 3.
  _btb_bad="$base/t1_base_badconf"; _proj_tracker_base "$_btb_bad"
  printf 'version=1\nbackend=jira\nbase_url=http://ex.atlassian.net\nflavour=cloud\nauth=basic\nproject=AB\n' > "$_btb_bad/.kit/tracker.conf"
  d="$base/t1_badconf"; _proj_backend "$d" jira
  assert_msg_ctx "NOT ENFORCED: backend 'jira'" 3 \
    "delegate/malformed-conf: base's own tracker-conf.sh refuses its .kit/tracker.conf -> rc 3" "$d" 280 "$cfg" "$_btb_bad" "$_btlive"

  # (g2) S-4 [SEC] twin: the base's OWN tracker.conf is one the REAL validator accepts, but the
  # base's OWN scripts/tracker-conf.sh is a STUB that unconditionally exit 1s -> rc 3. Pins that
  # bp_tracker_delegated runs the BASE's copy of tracker-conf.sh (`sh "$_btd_base/scripts/tracker-
  # conf.sh" "$_btd_conf"`), never this repo's/cwd's own copy — a predicate that shelled out to the
  # kit's/cwd's validator instead would see a VALID conf and wrongly delegate (rc 0) here, because
  # the conf itself is one the real validator accepts. RED with the predicate calling the kit's/cwd's
  # validator instead of the base's own (scratch tree only; not shipped here).
  _btb_stubconf="$base/t1_base_stubconf"; _proj_tracker_base "$_btb_stubconf"
  printf '#!/bin/sh\nexit 1\n' > "$_btb_stubconf/scripts/tracker-conf.sh"
  d="$base/t1_stubconf"; _proj_backend "$d" jira
  assert_msg_ctx "NOT ENFORCED: backend 'jira'" 3 \
    "delegate/stub-conf-validator: base's OWN tracker-conf.sh is a stub that exit 1s beside a conf the real validator accepts -> rc 3 (pins the BASE's validator is the one run)" "$d" 280 "$cfg" "$_btb_stubconf" "$_btlive"

  # (h) RT1-Q1 [SEC]: a live-contexts file holding ONLY 'tracker-board-gates (pull_request_target)'
  # (a SUBSTRING match dropping the exact-line requirement would false-delegate on the event-suffixed
  # spelling forges sometimes report) -> rc 3, never the delegated N/A. Pins bp_tracker_delegated's
  # `grep -Fxq` (exact line), not `-Fq` (substring) — verified RED with -x removed in a scratch tree
  # (build-time check, not shipped here).
  _btlive_suffix="$base/t1_live_suffix.txt"; printf 'ci\ntracker-board-gates (pull_request_target)\nbacklog-presence\n' > "$_btlive_suffix"
  d="$base/t1_suffix"; _proj_backend "$d" jira
  assert_msg_ctx "NOT ENFORCED: backend 'jira'" 3 \
    "delegate/live-suffix: live-contexts holding only the event-suffixed spelling must not satisfy -> rc 3 (kills a dropped -x)" "$d" 280 "$cfg" "$_btb" "$_btlive_suffix"

  # (h2) RT1-Q1 [SEC] continued: a live-contexts file holding ONLY 'tracker-board-gates-shadow' (a
  # SUPERSTRING with a trailing suffix) -> rc 3, same -x pin from the other direction.
  _btlive_shadow="$base/t1_live_shadow.txt"; printf 'ci\ntracker-board-gates-shadow\nbacklog-presence\n' > "$_btlive_shadow"
  d="$base/t1_shadow"; _proj_backend "$d" jira
  assert_msg_ctx "NOT ENFORCED: backend 'jira'" 3 \
    "delegate/live-shadow: live-contexts holding only a suffixed superstring must not satisfy -> rc 3 (kills a dropped -x)" "$d" 280 "$cfg" "$_btb" "$_btlive_shadow"

  # (i) RT1-Q2: an EMPTY live-contexts file (present, zero bytes, never missing) -> rc 3.
  _btlive_empty="$base/t1_live_empty.txt"; : > "$_btlive_empty"
  d="$base/t1_empty_live"; _proj_backend "$d" jira
  assert_msg_ctx "NOT ENFORCED: backend 'jira'" 3 \
    "delegate/empty-live: an EMPTY --live-contexts file -> rc 3 (fail-closed)" "$d" 280 "$cfg" "$_btb" "$_btlive_empty"

  # (j) S-3 [SEC]: bp_tracker_delegated's condition (i) — the BASE's OWN backend declaration must be
  # a hosted tracker, never md/undeclared/unrecognized — pinned from THIS caller, not just the
  # function's own scratch-tree witness (S-3, class sweep). Two legs: the base carries a VALID
  # tracker.conf + its own scripts/tracker-conf.sh (a live-contexts file listing tracker-board-gates
  # is present too), but its CLAUDE.md declares md (j1) or declares no backend at all (j2). Since
  # condition (i) fails first, the malformed/absent conf never matters — both must still rc 3, never
  # the delegated N/A. RED with condition (i)'s `case "$_btd_tok" in ''|md|unrecognized:*) return 1
  # ;; esac` deleted from a scratch copy of bp_tracker_delegated (scratch tree only; not shipped
  # here — backlog-lib.sh's production logic is untouched by this fix round).
  _btb_basemd="$base/t1_base_declares_md"; _proj_tracker_base "$_btb_basemd"; _proj_backend "$_btb_basemd" md
  d="$base/t1_base_declares_md_head"; _proj_backend "$d" jira
  assert_msg_ctx "NOT ENFORCED: backend 'jira'" 3 \
    "delegate/base-declares-md: base carries a valid tracker conf but its OWN backend declaration is md -> rc 3 (condition (i))" "$d" 280 "$cfg" "$_btb_basemd" "$_btlive"

  _btb_basenone="$base/t1_base_no_backend"; _proj_tracker_base "$_btb_basenone"
  printf '# Proj\n' > "$_btb_basenone/CLAUDE.md"
  d="$base/t1_base_no_backend_head"; _proj_backend "$d" jira
  assert_msg_ctx "NOT ENFORCED: backend 'jira'" 3 \
    "delegate/base-no-backend: base carries a valid tracker conf but declares NO backend at all -> rc 3 (condition (i))" "$d" 280 "$cfg" "$_btb_basenone" "$_btlive"

  # gated + declares md but has NO BACKLOG.md -> FAIL, rc 2 (MISCONFIGURATION, red — never the same
  # yellow as a healthy waiting gate; B5 rider BACKLOG-PRESENCE-WAITING-PARTITION).
  d="$base/cp_noboard"; _proj_backend "$d" md
  assert_msg "FAIL: declares an md backend but has no BACKLOG.md" 2 \
    "cp/declared-no-board: md declared, board absent -> FAIL, rc 2 (red)" "$d" 280 "$cfg"

  # gated + md + pristine template -> N/A (board not yet in use), rc 0.
  d="$base/cp_template"; _proj_template "$d"
  assert_msg "N/A: board not yet in use (pristine template)" 0 \
    "cp/pristine: untouched template -> N/A, rc 0" "$d" 280 "$cfg"

  # gated + md + board bears the PR -> OK, rc 0.
  d="$base/cp_present"; _proj_md_board "$d" '| KW6-A2 | — | #280 |'
  assert_msg "OK: backlog-presence — PR #280 is bound to a board row (PR column)" 0 \
    "cp/present: gated PR bound to a row -> OK, rc 0" "$d" 280 "$cfg"

  # gated + md + board does NOT bear the PR -> the genuine WAIT, rc 1 (yellow), and the verdict must
  # carry the legibility pointer (B6-routed: the probe itself mis-bound a row outside a PR column).
  d="$base/cp_absent"; _proj_md_board "$d" '| KW6-A2 | — | #99 |'
  assert_msg "FAIL: backlog-presence — no board row bears PR #280 in its PR cell (gated change-class). The row must sit in a section with a \`PR\` column — In Review in the shipped schema." 1 \
    "cp/absent: gated PR with no matching row -> FAIL, rc 1 (yellow wait) + PR-column pointer" "$d" 280 "$cfg"

  # ===== I-1 — the classifier-config environment must NOT redirect the seams (spec §7) =====
  # gate_class consults agent-boundary.sh, whose union-detection reads adapters/*/adapter.json.
  # A decoy that points KIT_ADAPTERS_DIR at an empty dir, OR strips jq, would make an AGENTS.md
  # change-set (genuinely control-plane) collapse to `ordinary` -> the gate silently vanishes.
  # Targets come from the repo's real adapters/, never the environment: both must stay `gated`.
  cf="$base/cf_agents_env"; printf 'AGENTS.md\n' > "$cf"

  # a hostile KIT_ADAPTERS_DIR (empty) must be scrubbed on the seam call -> still gated.
  emptydir=$(mktemp -d)
  assert_gated_env "KIT_ADAPTERS_DIR=$emptydir" "$cf" \
    "i1/env-adapters: hostile KIT_ADAPTERS_DIR=empty must not fail-open AGENTS.md -> gated"

  # jq absent from PATH must fail CLOSED (a missing tool never widens what passes) -> gated.
  assert_gated_nojq "$cf" \
    "i1/no-jq: jq absent from PATH must fail closed -> gated (never ordinary)"

  # ===== I-2 — a fat-fingered backend must FAIL, not collapse to a non-md N/A (dark gate) =====
  # resolve_backend signals a mistyped field as `unrecognized:<token>` precisely so it does NOT
  # fail open. check_pr must FAIL on it — mirroring backlog-current.sh:255-261 — not route it into
  # the generic non-md N/A. A real board binding no PR proves it is the TOKEN, not board-absence.
  d="$base/cp_typo"; _proj_backend "$d" markdow; _board "$d" '| KW6-A2 | — | #99 |'
  assert_msg "FAIL: unrecognized backlog backend 'markdow' (known: md github jira ado linear gitlab)" 2 \
    "i2/typo-backend: 'markdow' declared + real board -> FAIL, rc 2 (red misconfiguration, not N/A, not the wait-yellow)" "$d" 280 "$cfg"

  # ===== T3 — THE STRANGER'S REFUSAL (PRE-PUSH-RUNS-BACKLOG-PRESENCE design §3.4, Δ2) ==========
  # hooks/pre-push runs this gate locally with `--pr 0` (no PR exists yet at push time), so the
  # verdict is read by an operator with no board context, in a terminal, mid-push. Three properties:
  # the branch-only wording (a literal "PR #0" is noise that names nothing), a `likely yours:` hint
  # drawn from the rows already sitting In Progress, and a `remedy:` naming the exact edit.

  # b1 — one In Progress row: branch-only wording, the hint names THAT row, the remedy is present,
  # and "PR #0" appears nowhere. The hint is the leg a hint-loop mutant reds.
  d="$base/t3_one"; _proj_ip_board "$d" 1
  br_run "$d" 0 "$cfg" feat/prepush-presence
  br_expect_rc 1 "t3/one: --pr 0 with no bound row -> rc 1 (the genuine wait)"
  br_has "t3/one: the FAIL line names the BRANCH" "no board row bears branch 'feat/prepush-presence'"
  br_hasnt "t3/one: the --pr 0 form never prints a meaningless 'PR #0'" "PR #0"
  br_has "t3/one: the hint names the row sitting In Progress" "likely yours: \`ROW-1\` (sitting in In Progress)"
  br_has "t3/one: the remedy names the exact edit" "remedy: move your row to In Review"
  br_has "t3/one: the remedy names the branch to write into the PR cell" "feat/prepush-presence"
  # vet L1 — the refusal must ALSO name the Done form, or an operator working under the one-PR
  # close is sent to the flow this slice replaced. Two legs: the diagnostic sentence and the remedy.
  br_has "t3/one: the refusal names the Done-retro binding too (vet L1)" "the row may instead sit in Done, Closed on/after"
  br_has "t3/one: the remedy names the Done-retro edit too (vet L1)" "named in its Retro/outcome cell"
  # ...and with jq PRESENT the verdict must NOT mention jq: the jq sentence is a fail-safe
  # DISCLOSURE, and a disclosure that prints unconditionally tells the reader nothing (b4's pair).
  br_hasnt "t3/one: with jq present the verdict does not mention jq" "jq"
  # control: no Done-row branch candidate existed at all here, so nothing was suppressed — the S-6
  # NOTE must not fire on the ordinary no-row wait (no false positive).
  br_hasnt "t3/one: no base-board suppression occurred -> the S-6 NOTE is absent" "base board (origin/main's BACKLOG.md) was unreadable"

  # b1b — S-6 RELAY (security review, 2026-09-10): a Done row's branch token LITERALLY MATCHES, but
  # no --base-board was supplied (unreadable/absent) -> row_bears_pr suppresses the bind (fail-safe,
  # unchanged) AND check_pr's refusal must now NAME the cause + remedy, not merely repeat "$_doneform"
  # as if Done had been checked and found wanting.
  d="$base/t3_base_suppressed"; _done_board "$d" '| `NEW-ROW-S6` | 2026-09-09 | L1 retro. Shipped from feat/s6-relay, a green first run. |'
  _proj_backend "$d" md
  br_run "$d" 0 "$cfg" feat/s6-relay
  br_expect_rc 1 "t3/base-suppressed: a Done-row branch candidate exists but no base board was supplied -> rc 1"
  br_has "t3/base-suppressed: the refusal names the cause (base board unreadable)" "the base board (origin/main's BACKLOG.md) was unreadable locally"
  br_has "t3/base-suppressed: the refusal names the remedy (git fetch origin main)" "git fetch origin main"

  # b1c — control: the SAME candidate row, but a REAL, readable base board is supplied and the row is
  # genuinely new to it (binds) -> rc 0, and (since nothing was suppressed) the S-6 NOTE never fires.
  based="$base/t3_base_suppressed_base"; _done_board "$based" '| `OTHER-ROW` | 2026-09-01 | Unrelated prior work. |'
  br_run_base "$d" 0 "$cfg" feat/s6-relay "$based/BACKLOG.md"
  br_expect_rc 0 "t3/base-readable-binds: the same row with a READABLE base board -> binds normally -> rc 0"

  # b1d — control: a readable base board that DOES carry the row (genuinely stale, TIER0-LOCKS-OWED a)
  # -> still rc 1 (correctly declined, not suppressed), and the S-6 NOTE must NOT fire — this refusal
  # is a real "no" from an evaluated base board, not an unevaluated one.
  based2="$base/t3_base_stale_base"; _done_board "$based2" '| `NEW-ROW-S6` | 2026-09-01 | L1 retro. Shipped from feat/s6-relay months ago. |'
  br_run_base "$d" 0 "$cfg" feat/s6-relay "$based2/BACKLOG.md"
  br_expect_rc 1 "t3/base-readable-stale: a readable base board that already carries the row -> correctly declines -> rc 1"
  br_hasnt "t3/base-readable-stale: a REAL evaluated 'no' must not carry the unevaluated NOTE" "was unreadable locally"

  # b2 — FOUR In Progress rows: the count form, not four hint lines. A refusal that pastes the whole
  # section is the annoyance this design replaced, not the teaching one.
  d="$base/t3_many"; _proj_ip_board "$d" 4
  br_run "$d" 0 "$cfg" feat/prepush-presence
  br_expect_rc 1 "t3/many: four In Progress rows -> still rc 1"
  br_has "t3/many: the count form replaces the per-row listing" "4 rows are sitting in In Progress"
  br_hasnt "t3/many: no per-row hint line survives the count form" "likely yours: \`ROW-1\`"

  # b3 — the PASS side of the same surface: a row whose PR cell bears the BRANCH satisfies `--pr 0`,
  # and the OK line is branch-only too (a green saying "PR #0 is bound" would be a lie in the log).
  d="$base/t3_bound"; _proj_md_board "$d" '| `PRE-PUSH` | — | feat/prepush-presence |'
  br_run "$d" 0 "$cfg" feat/prepush-presence
  br_expect_rc 0 "t3/bound: a PR cell bearing the branch satisfies --pr 0 -> rc 0"
  br_has "t3/bound: the OK line names the branch" "branch 'feat/prepush-presence' is bound"
  br_hasnt "t3/bound: the OK line carries no 'PR #0' either" "PR #0"

  # b3b (security S3) — A LITERAL `#0` CELL MUST NOT BIND. `--pr 0` means "no PR exists yet", not
  # "PR number zero"; a row whose PR cell bears `#0` would otherwise satisfy the gate for every
  # branch on the board at once. The board here carries `#0` and the branch is NOT in any cell.
  d="$base/t3_hash_zero"; _proj_md_board "$d" '| `PRE-PUSH` | — | #0 |'
  br_run "$d" 0 "$cfg" feat/prepush-presence
  br_expect_rc 1 "t3/hash-zero: a literal '#0' PR cell must NOT satisfy --pr 0 -> rc 1"
  # ...while a real PR number still binds, so the guard above narrowed nothing else.
  d="$base/t3_number_ok"; _proj_md_board "$d" '| `PRE-PUSH` | — | #280 |'
  br_run "$d" 280 "$cfg" feat/prepush-presence
  br_expect_rc 0 "t3/number-still-binds: a real PR number is unaffected by the --pr 0 guard"

  # b4 (A1-10) — jq ABSENT. gate_class fail-safes every change-set to `gated` without jq, so under an
  # enforcing push dial this gate can REFUSE an ordinary change on a jq-less machine. The refusal must
  # NAME THAT CAUSE; otherwise the operator is told to fix a board row when the real fix is `brew
  # install jq`. Paired with b1's negative, so the sentence cannot be unconditional boilerplate.
  d="$base/t3_nojq"; _proj_ip_board "$d" 1
  br_run_nojq "$d" 0 "$cfo" feat/prepush-presence
  br_expect_rc 1 "t3/no-jq: an ORDINARY change-set is fail-safed to gated without jq -> rc 1"
  br_has "t3/no-jq: the refusal names jq as the cause of the fail-safe" "jq"

  # ===== T4 — THE CLAIMS ARM, legs (g) (BOARD-CLAIM-MECHANISM design §3.4 leg g) ================
  # A real bare remote and a real clone, real refs — no simulation. The board carries `ROW-1` In
  # Progress and an In Review row bound to the branch, so PRESENCE passes in every leg below and the
  # only thing under test is the claim.

  # g1 — In Progress with NO claim ref -> rc 1 WAITING, naming the row AND the remedy verb.
  d=$(_claims_fixture "" )
  br_run_claims "$d" 0 "$cfg" feat/claims
  br_expect_rc 1 "t4/g1-missing: an In Progress row with no claim ref -> rc 1 (WAITING)"
  br_has "t4/g1-missing: the refusal names the ROW" "row \`ROW-1\` sits In Progress but NO claim ref exists"
  br_has "t4/g1-missing: the refusal names the REMEDY verb" "scripts/board-claim.sh claim ROW-1"

  # ...and WITHOUT --claims the SAME fixture passes. The regression lock: the arm must be reachable
  # only through the flag, or the pre-push run (which never passes it) starts needing the network.
  br_run "$d" 0 "$cfg" feat/claims
  br_expect_rc 0 "t4/g1-off: the same board with NO --claims -> rc 0 (the arm is opt-in, not ambient)"
  br_hasnt "t4/g1-off: without --claims nothing about claims is printed" "claim ref"

  # g2 — the claim ref exists but names ANOTHER branch -> rc 2 REFUSED, naming holder, branch, time.
  d=$(_claims_fixture "other/branch")
  br_run_claims "$d" 0 "$cfg" feat/claims
  br_expect_rc 2 "t4/g2-other-branch: a claim held by another branch -> rc 2 (REFUSED, not a wait)"
  br_has "t4/g2-other-branch: the refusal names the HOLDER" "CLAIMED by 'Other Session <other@example.com>'"
  br_has "t4/g2-other-branch: the refusal names the holding BRANCH" "on branch 'other/branch'"
  br_has "t4/g2-other-branch: the refusal carries the claim TIME" "at 2026-09-04T00:00:00Z"
  br_has "t4/g2-other-branch: the refusal says plainly what is wrong" "Two branches are working one row"

  # g3 — the claim ref names THIS branch -> rc 0. The positive liveness anchor: without it every leg
  # above could pass on a gate that simply always refuses.
  d=$(_claims_fixture "feat/claims")
  br_run_claims "$d" 0 "$cfg" feat/claims
  br_expect_rc 0 "t4/g3-this-branch: a claim held by THIS branch -> rc 0"
  br_has "t4/g3-this-branch: the OK line names the row and the branch" "row \`ROW-1\` is claimed on origin by this branch 'feat/claims'"

  # g4 (reviewer R-6) — AN ORDINARY-CLASS PR WITH In Progress ROWS MUST STILL REACH THE ARM. Presence
  # is genuinely N/A for an ordinary change; the claim is not, because a row is claimed by ROW ID and
  # the class of the second session's diff says nothing about whether two branches hold one row. The
  # verdict must carry BOTH sentences: the N/A for presence and the WAITING for the claim.
  d=$(_claims_fixture "")
  br_run_claims "$d" 0 "$cfo" feat/claims
  br_expect_rc 1 "t4/g4-ordinary: an ORDINARY-class PR with an unclaimed In Progress row -> rc 1 (WAITING)"
  br_has "t4/g4-ordinary: presence is still N/A for an ordinary change" "N/A: ordinary change-class"
  br_has "t4/g4-ordinary: and the claims arm still names the row" "row \`ROW-1\` sits In Progress but NO claim ref exists"

  # …and the ordinary path keeps its opt-in lock too: no --claims, no network, byte-identical N/A.
  br_run "$d" 0 "$cfo" feat/claims
  br_expect_rc 0 "t4/g4-ordinary-off: the same ordinary PR with NO --claims -> rc 0"
  br_hasnt "t4/g4-ordinary-off: without --claims nothing about claims is printed" "claim ref"

  # …and an ordinary PR whose board carries NO In Progress row must not reach the arm at all — the
  # trigger is the board's contents, not the flag alone. Without this leg the arm could be running on
  # every ordinary PR in the fleet and every assertion above would still pass.
  d="$base/t4_ord_empty"; _proj_md_board "$d" '| `X` | — | #280 |'
  br_run_claims "$d" 0 "$cfo" feat/claims
  br_expect_rc 0 "t4/g4-no-rows: an ordinary PR whose board has NO In Progress row -> rc 0"
  br_hasnt "t4/g4-no-rows: the arm did not run (nothing claim-shaped is printed)" "backlog-presence --claims"

  # ===== SEAM — TBG-SEAM-MD-ARM T1 non-vacuity (`seam_row_state` / `seam_rows_in_state` /
  # `seam_row_flag`, the three seam functions this gate does not route in production this wave —
  # `seam_backend` is already exercised live, through check_pr, above). Each leg sets SEAM_ROOT to
  # a fixture project dir and calls the seam function directly, exactly as a future routed call
  # site would, proving behaviour independent of check_pr/check_claims's own control flow.

  # seam_row_state — positive anchor: the row `X` sits in In Review -> `in-review`.
  d="$base/seam_state_present"; _proj_md_board "$d" '| `X` | — | #280 |'
  SEAM_ROOT="$d"
  _seam_v=$(seam_row_state X) && _seam_rc=0 || _seam_rc=$?
  if [ "$_seam_rc" = 0 ] && [ "$_seam_v" = "in-review" ]; then :; else
    echo "selftest FAIL: seam/row-state-present: seam_row_state X -> rc=$_seam_rc v='$_seam_v', wanted rc0 'in-review'"; st_fail=1
  fi
  # ...load-bearing negative: an id absent from the board -> refused (rc 1), never a guessed state.
  _seam_v=$(seam_row_state NOPE 2>/dev/null) && _seam_rc=0 || _seam_rc=$?
  if [ "$_seam_rc" = 1 ]; then :; else
    echo "selftest FAIL: seam/row-state-absent: seam_row_state NOPE -> rc=$_seam_rc, wanted rc1 (refused)"; st_fail=1
  fi
  # ...a SECOND load-bearing negative, mutant-shaped: the id sits on TWO rows (AMBIGUOUS) -> refused
  # (rc 1), never a guessed state from whichever section the scan reaches first. This is the leg that
  # specifically exercises the `row_count ... = 1` guard — the id-absent leg above falls through to
  # the same rc 1 via the loop's own exhaustion and would not catch that guard being dropped.
  d="$base/seam_state_ambiguous"
  mkdir -p "$d"
  cat > "$d/BACKLOG.md" <<'EOF'
# Proj — Backlog

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| `DUP` | — | #1 |

## Blocked

| Item | Reason |
|------|--------|
| `DUP` | duplicate on purpose |
EOF
  SEAM_ROOT="$d"
  _seam_v=$(seam_row_state DUP 2>/dev/null) && _seam_rc=0 || _seam_rc=$?
  if [ "$_seam_rc" = 1 ]; then :; else
    echo "selftest FAIL: seam/row-state-ambiguous: seam_row_state DUP (on two rows) -> rc=$_seam_rc v='$_seam_v', wanted rc1 (refused)"; st_fail=1
  fi
  SEAM_ROOT="$base/seam_state_present"

  # seam_rows_in_state — positive anchor: the same board's `in-review` list carries exactly `X`.
  _seam_v=$(seam_rows_in_state in-review) && _seam_rc=0 || _seam_rc=$?
  if [ "$_seam_rc" = 0 ] && [ "$_seam_v" = "X" ]; then :; else
    echo "selftest FAIL: seam/rows-in-state-present: seam_rows_in_state in-review -> rc=$_seam_rc v='$_seam_v', wanted rc0 'X'"; st_fail=1
  fi
  # ...load-bearing negative: a state this board has no rows in -> LEGAL empty (rc 0), the one
  # carve-out — proves the function does not silently fall back to some OTHER section's rows.
  _seam_v=$(seam_rows_in_state blocked) && _seam_rc=0 || _seam_rc=$?
  if [ "$_seam_rc" = 0 ] && [ -z "$_seam_v" ]; then :; else
    echo "selftest FAIL: seam/rows-in-state-empty: seam_rows_in_state blocked -> rc=$_seam_rc v='$_seam_v', wanted rc0 ''"; st_fail=1
  fi

  # seam_row_flag pr-bound — positive anchor: row `X`'s PR cell bears `#280` -> yes.
  _seam_v=$(seam_row_flag X pr-bound) && _seam_rc=0 || _seam_rc=$?
  if [ "$_seam_rc" = 0 ] && [ "$_seam_v" = "yes" ]; then :; else
    echo "selftest FAIL: seam/row-flag-yes: seam_row_flag X pr-bound -> rc=$_seam_rc v='$_seam_v', wanted rc0 'yes'"; st_fail=1
  fi
  # ...load-bearing negative: an EMPTY PR cell -> no, never yes (proves the check reads the cell's
  # content, not merely the column's presence).
  d="$base/seam_flag_empty"; _proj_md_board "$d" '| `Y` | — | |'
  SEAM_ROOT="$d"
  _seam_v=$(seam_row_flag Y pr-bound) && _seam_rc=0 || _seam_rc=$?
  if [ "$_seam_rc" = 0 ] && [ "$_seam_v" = "no" ]; then :; else
    echo "selftest FAIL: seam/row-flag-no: seam_row_flag Y pr-bound -> rc=$_seam_rc v='$_seam_v', wanted rc0 'no'"; st_fail=1
  fi
  # ...an unimplemented flag on the md arm -> refused (rc 1), never a guessed answer.
  _seam_v=$(seam_row_flag Y dor-acceptance 2>/dev/null) && _seam_rc=0 || _seam_rc=$?
  if [ "$_seam_rc" = 1 ]; then :; else
    echo "selftest FAIL: seam/row-flag-unimplemented: seam_row_flag Y dor-acceptance -> rc=$_seam_rc, wanted rc1 (refused)"; st_fail=1
  fi

  # SEAM_ROOT FAIL-CLOSED (TBG-SEAM-MD-ARM WAVE 3) — an UNSET SEAM_ROOT is a caller bug (every
  # routed gate sets it before calling), never a legitimate "board at cwd" default. Every seam_*
  # function must refuse (rc 2, UNVERIFIED) rather than silently resolve an empty root. Load-bearing:
  # exercises the guard against every one of the five functions, on stdout AND rc, with the
  # one-line refusal on stderr.
  unset SEAM_ROOT
  for _seam_fn in seam_backend "seam_row_count X" "seam_row_state X" "seam_rows_in_state ready" "seam_row_flag X pr-bound"; do
    _seam_err=$(eval "$_seam_fn" 2>&1 >/dev/null) && _seam_rc=0 || _seam_rc=$?
    case "$_seam_err" in
      *"SEAM_ROOT is unset"*) _seam_msg_ok=1 ;;
      *)                      _seam_msg_ok=0 ;;
    esac
    if [ "$_seam_rc" = 2 ] && [ "$_seam_msg_ok" = 1 ]; then :; else
      echo "selftest FAIL: seam/root-unset: '$_seam_fn' with SEAM_ROOT unset -> rc=$_seam_rc err='$_seam_err', wanted rc2 + the refusal"; st_fail=1
    fi
  done
  SEAM_ROOT="$base/seam_state_present"   # restore, so nothing later in this function inherits unset

  # seam/backend-grep-fault (SEAM-BACKEND-DECL-GREP-FOLD, T4) — a CLAUDE.md that EXISTS but a grep
  # EXEC FAULT (unreadable file, rc>=2) prevents reading it must NOT collapse to the same empty
  # answer as a genuinely absent field ("undeclared"). Root ignores mode bits (a chmod 000 file is
  # still readable as uid 0), so this leg is a NAMED SKIP under root rather than a false pass.
  if [ "$(id -u 2>/dev/null)" = 0 ]; then
    echo "SKIP seam/backend-grep-fault: running as root (uid 0) — chmod 000 does not block root's own read, so the exec fault this leg forces is unreachable. Precondition NAMED and printed rather than silently assumed."
  else
    d="$base/seam_grep_fault"; mkdir -p "$d"
    printf '# Proj\n\n- **Backlog backend** (%s6): md\n' '§' > "$d/CLAUDE.md"
    chmod 000 "$d/CLAUDE.md"
    SEAM_ROOT="$d"
    _seam_v=$(seam_backend) && _seam_rc=0 || _seam_rc=$?
    chmod 644 "$d/CLAUDE.md"   # restore before any later fixture/cleanup touches this tree
    # FIXED TOKEN, EXACT MATCH (security fix-round 2, L-2): the path/value used to be interpolated
    # into the token (repo text reaching a gate's prose) — it no longer is, so the leg now asserts
    # equality, not a prefix.
    case "$_seam_v" in
      unrecognized:evalerror) _seam_msg_ok=1 ;;
      *)                      _seam_msg_ok=0 ;;
    esac
    if [ "$_seam_rc" = 0 ] && [ -n "$_seam_v" ] && [ "$_seam_msg_ok" = 1 ]; then
      echo "selftest PASS: seam/backend-grep-fault: an unreadable CLAUDE.md is signalled diagnosably AND fail-closed (unrecognized:evalerror, exact), never as undeclared"
    else
      echo "selftest FAIL: seam/backend-grep-fault: seam_backend on an unreadable CLAUDE.md -> rc=$_seam_rc v='$_seam_v', wanted the exact 'unrecognized:evalerror' token (fail-closed, NOT empty/undeclared)"; st_fail=1
    fi
    SEAM_ROOT="$base/seam_state_present"
  fi

  # ===== TBG-READER-FLAGS-LIST T8 — the tracker arm round trip (design §3e/§3h, F-1) ===========
  # COPIES of the real reader + conf parser, a fake adapter that `cat`s the SAME
  # conformance/fixtures/tracker-jira/ops/*.out files T2/T3/T5 proved (drift lock — never an
  # inline printf for the shapes those files carry), driven through the reader's PUBLIC CLI onto a
  # THROWAWAY git repo (never this clone's own history — hard rule) whose head commit carries the
  # Kit-Row trailer the gate reads. ADAPTED from the plan's placeholder subject `AB-7`/`AB-9`: the
  # only tracked `list-in-states` fixture with TWO ids is `list-cloud-inprogress.out` (AB-1, AB-4),
  # and the subject must be a member of its OWN state's list (§3b bijection "iff") — AB-7 never
  # appears in any tracked list fixture (only in the get-issue-assigned/unassigned pair, which no
  # list op references), so AB-1/AB-4 is the pair the ops files actually make possible.
  _t8_repo=$(pwd)
  _t8_ops="$_t8_repo/conformance/fixtures/tracker-jira/ops"
  # fix1 Q1: the SHARED fixture stays byte-identical — every leg reads its OWN conf copy (built by
  # _t8_mkconf, defined with the other T8 helpers below), never a line appended to the tracked file.
  _t8_conf_src="$_t8_repo/conformance/fixtures/tbg-record-gates-bind/tracker-jira/.kit/tracker.conf"
  _t8_claude="$_t8_repo/conformance/fixtures/tbg-record-gates-bind/tracker-jira/CLAUDE.md"
  _t8_rr="$base/t8_reader_root"; mkdir -p "$_t8_rr/scripts"
  cp "$_t8_repo/scripts/tracker-read.sh" "$_t8_rr/scripts/tracker-read.sh"
  cp "$_t8_repo/scripts/tracker-conf.sh" "$_t8_rr/scripts/tracker-conf.sh"
  # a dummy credential — the reader's credential PROBE dispatches to the fake adapter's own
  # `permissions` op (always `ok` here); no real network, no real secret, never asserted on.
  export KIT_TRACKER_USER="t8user" KIT_TRACKER_TOKEN="t8token"
  _t8_conf=$(_t8_mkconf)                                # base + list_cap=200 (Q1) — legs 1,2,3,5,6,7,9
  _t8_conf_ready=$(_t8_mkconf "state.ready=Selected")   # leg 4 only, its own private copy

  # leg 1 (F-1 positive): subject AB-1 claimed + in-progress, AB-4 unclaimed + in-progress -> rc0.
  _t8_adapter 3 "In Progress" true
  t8_gr1=$(_t8_gitrepo "Kit-Row: AB-1" leg1); t8_dir1=${t8_gr1% *}; t8_head1=${t8_gr1#* }
  t8_rec1="$base/t8_rec_pos.txt"; : > "$t8_rec1"
  if sh "$_t8_rr/scripts/tracker-read.sh" "$_t8_conf" - "$t8_rec1" AB-1 "$t8_head1" in-progress >/dev/null 2>&1; then t8_r1rc=0; else t8_r1rc=$?; fi
  # fix1 Q1: ASSERT the reader's rc AND the record's actual list content BEFORE grading — never
  # `|| :` on the reader. Without a genuine `list_cap`, this record would hold only the subject row
  # (R5), and a mutant grading EVERY in-progress row would survive vacuously (rc0 either way).
  if [ "$t8_r1rc" -eq 0 ] && grep -qxF 'list in-progress AB-1 AB-4' "$t8_rec1" && grep -qxF 'row AB-4 state=in-progress' "$t8_rec1"; then
    echo "selftest PASS: t8/f1-positive-record: reader rc0, record carries the AB-4 in-progress row (Q1 non-vacuity)"
  else
    echo "selftest FAIL: t8/f1-positive-record: reader rc=$t8_r1rc, record: $(tr '\n' ';' < "$t8_rec1" 2>/dev/null)"; st_fail=1
  fi
  KIT_TRACKER_RECORD="$t8_rec1"
  t8_run "$t8_dir1" "$t8_head1"
  if [ "$t8_rc" -eq 0 ]; then echo "selftest PASS: t8/f1-positive: claimed subject + an unclaimed in-progress row -> rc0"
  else echo "selftest FAIL: t8/f1-positive: wanted rc0, got rc=$t8_rc out='$t8_out'"; st_fail=1; fi

  # (h) TRACKER-TRUSTED-JOB-REQUIRED-CONTEXT T1, RD-2 (no self-delegation): SEAM_RECORD set + all
  # three bp_tracker_delegated conditions true -> the record-set path still returns the TRACKER ARM's
  # own verdict, NEVER the "delegated" N/A line — the trusted job (which sets SEAM_RECORD) is never
  # excused by its own required-context wiring. $_btb/$_btlive are T1's base-tracker fixtures above.
  if t1h_out=$(check_pr "$t8_dir1" 0 "$cfg" "" 0 "" "$t8_head1" "$_btb" "$_btlive" 2>&1); then t1h_rc=0; else t1h_rc=$?; fi
  if [ "$t1h_rc" -eq 0 ]; then echo "selftest PASS: delegate/no-self-delegation-rc: record set + delegation-eligible base+live -> still rc0 (the tracker arm's own verdict)"
  else echo "selftest FAIL: delegate/no-self-delegation-rc: wanted rc0, got rc=$t1h_rc out='$t1h_out'"; st_fail=1; fi
  case "$t1h_out" in
    *"delegated to the required context"*)
      echo "selftest FAIL: delegate/no-self-delegation-verdict: the record-set path printed the delegated N/A line — self-delegation bypass; out='$t1h_out'"; st_fail=1 ;;
    *) echo "selftest PASS: delegate/no-self-delegation-verdict: the record-set path never prints the delegated N/A line" ;;
  esac

  # leg 2: subject claimed=no -> rc1, remedy names 'sparkwright board claim AB-1'.
  _t8_adapter 3 "In Progress" false
  t8_gr2=$(_t8_gitrepo "Kit-Row: AB-1" leg2); t8_dir2=${t8_gr2% *}; t8_head2=${t8_gr2#* }
  t8_rec2="$base/t8_rec_no.txt"; : > "$t8_rec2"
  # T10-harden-A P1: capture (never discard via `|| :`) the reader's own rc — a mutant reader that
  # fails for the wrong reason must not hide behind a coincidentally-matching downstream gate rc.
  if sh "$_t8_rr/scripts/tracker-read.sh" "$_t8_conf" - "$t8_rec2" AB-1 "$t8_head2" >/dev/null 2>&1; then t8_r2rc=0; else t8_r2rc=$?; fi
  KIT_TRACKER_RECORD="$t8_rec2"
  t8_run "$t8_dir2" "$t8_head2"
  case "$t8_out" in
    *"sparkwright board claim AB-1"*) [ "$t8_rc" -eq 1 ] && _t8_ok=1 || _t8_ok=0 ;;
    *) _t8_ok=0 ;;
  esac
  if [ "$_t8_ok" = 1 ] && [ "$t8_r2rc" -eq 0 ]; then echo "selftest PASS: t8/claimed-no: claimed=no -> rc1 naming the remedy (reader rc0)"
  else echo "selftest FAIL: t8/claimed-no: wanted rc1 + remedy + reader rc0, got rc=$t8_rc reader-rc=$t8_r2rc out='$t8_out'"; st_fail=1; fi

  # leg 3 (required mutant fixture): claimed ABSENT (no assignee-present field at all, never "no")
  # -> rc2 UNVERIFIED (M-5: an absent flag is never silently 'yes').
  _t8_adapter 3 "In Progress" ""
  t8_gr3=$(_t8_gitrepo "Kit-Row: AB-1" leg3); t8_dir3=${t8_gr3% *}; t8_head3=${t8_gr3#* }
  t8_rec3="$base/t8_rec_absent.txt"; : > "$t8_rec3"
  # T10-harden-A P1: capture the reader's own rc (never discard via `|| :`).
  if sh "$_t8_rr/scripts/tracker-read.sh" "$_t8_conf" - "$t8_rec3" AB-1 "$t8_head3" >/dev/null 2>&1; then t8_r3rc=0; else t8_r3rc=$?; fi
  KIT_TRACKER_RECORD="$t8_rec3"
  t8_run "$t8_dir3" "$t8_head3"
  if [ "$t8_rc" -eq 2 ] && [ "$t8_r3rc" -eq 0 ]; then echo "selftest PASS: t8/claimed-absent: no assignee-present field -> rc2 (never defaulted to yes) (reader rc0)"
  else echo "selftest FAIL: t8/claimed-absent: wanted rc2 + reader rc0, got rc=$t8_rc reader-rc=$t8_r3rc out='$t8_out'"; st_fail=1; fi

  # leg 4: subject resolves to 'ready' -> rc1 (not In Progress/In Review). Its own conf copy carries
  # `state.ready=Selected` (fix1 Q1: never the shared fixture — legs 1,2,3,5,6,7,9 never need it).
  _t8_adapter 10001 "Selected" true
  t8_gr4=$(_t8_gitrepo "Kit-Row: AB-1" leg4 "$_t8_conf_ready"); t8_dir4=${t8_gr4% *}; t8_head4=${t8_gr4#* }
  t8_rec4="$base/t8_rec_ready.txt"; : > "$t8_rec4"
  # T10-harden-A P1: capture the reader's own rc (never discard via `|| :`).
  if sh "$_t8_rr/scripts/tracker-read.sh" "$_t8_conf_ready" - "$t8_rec4" AB-1 "$t8_head4" >/dev/null 2>&1; then t8_r4rc=0; else t8_r4rc=$?; fi
  KIT_TRACKER_RECORD="$t8_rec4"
  t8_run "$t8_dir4" "$t8_head4"
  if [ "$t8_rc" -eq 1 ] && [ "$t8_r4rc" -eq 0 ]; then echo "selftest PASS: t8/ready: a Ready subject -> rc1, not the F-1 states (reader rc0)"
  else echo "selftest FAIL: t8/ready: wanted rc1 + reader rc0, got rc=$t8_rc reader-rc=$t8_r4rc out='$t8_out'"; st_fail=1; fi

  # leg 5: the record is for ANOTHER head (H-2) -> rc2. Reuses leg 1's bound record but grades a
  # DIFFERENT real commit (same trailer, different sha -> the record's own 'head' field disagrees).
  t8_gr5=$(_t8_gitrepo "Kit-Row: AB-1" leg5); t8_dir5=${t8_gr5% *}; t8_head5=${t8_gr5#* }
  KIT_TRACKER_RECORD="$t8_rec1"
  t8_run "$t8_dir5" "$t8_head5"
  if [ "$t8_rc" -eq 2 ]; then echo "selftest PASS: t8/wrong-head: a record for a DIFFERENT head -> rc2 (H-2)"
  else echo "selftest FAIL: t8/wrong-head: wanted rc2, got rc=$t8_rc out='$t8_out'"; st_fail=1; fi

  # leg 6: the trailer names AB-2 but the record's own 'requested' is AB-1 (the record never names
  # its own subject) -> rc2. The record's head field must equal THIS leg's grading head (H-2 holds).
  _t8_adapter 3 "In Progress" true
  t8_gr6=$(_t8_gitrepo "Kit-Row: AB-2" leg6); t8_dir6=${t8_gr6% *}; t8_head6=${t8_gr6#* }
  t8_rec6="$base/t8_rec_mismatch.txt"; : > "$t8_rec6"
  # T10-harden-A P1: capture the reader's own rc (never discard via `|| :`).
  if sh "$_t8_rr/scripts/tracker-read.sh" "$_t8_conf" - "$t8_rec6" AB-1 "$t8_head6" >/dev/null 2>&1; then t8_r6rc=0; else t8_r6rc=$?; fi
  KIT_TRACKER_RECORD="$t8_rec6"
  t8_run "$t8_dir6" "$t8_head6"
  if [ "$t8_rc" -eq 2 ] && [ "$t8_r6rc" -eq 0 ]; then echo "selftest PASS: t8/trailer-ne-requested: Kit-Row AB-2 vs record requested AB-1 -> rc2 (reader rc0)"
  else echo "selftest FAIL: t8/trailer-ne-requested: wanted rc2 + reader rc0, got rc=$t8_rc reader-rc=$t8_r6rc out='$t8_out'"; st_fail=1; fi

  # leg 7: no Kit-Row trailer at all -> rc1, naming the trailer.
  t8_gr7=$(_t8_gitrepo "" leg7); t8_dir7=${t8_gr7% *}; t8_head7=${t8_gr7#* }
  KIT_TRACKER_RECORD="$t8_rec1"
  t8_run "$t8_dir7" "$t8_head7"
  case "$t8_out" in
    *"Kit-Row"*) [ "$t8_rc" -eq 1 ] && _t8_ok=1 || _t8_ok=0 ;;
    *) _t8_ok=0 ;;
  esac
  if [ "$_t8_ok" = 1 ]; then echo "selftest PASS: t8/no-trailer: a head with no Kit-Row trailer -> rc1 naming it"
  else echo "selftest FAIL: t8/no-trailer: wanted rc1 naming Kit-Row, got rc=$t8_rc out='$t8_out'"; st_fail=1; fi

  # leg 9 (fix1 Q4): TWO Kit-Row trailers -> rc1, the sentence says 'exactly one' (not 'no parseable').
  t8_gr9=$(_t8_gitrepo "Kit-Row: AB-1
Kit-Row: AB-4" leg9); t8_dir9=${t8_gr9% *}; t8_head9=${t8_gr9#* }
  KIT_TRACKER_RECORD="$t8_rec1"
  t8_run "$t8_dir9" "$t8_head9"
  case "$t8_out" in
    *"exactly one"*) [ "$t8_rc" -eq 1 ] && _t8_ok=1 || _t8_ok=0 ;;
    *) _t8_ok=0 ;;
  esac
  if [ "$_t8_ok" = 1 ]; then echo "selftest PASS: t8/two-trailers: two Kit-Row trailers -> rc1 naming 'exactly one'"
  else echo "selftest FAIL: t8/two-trailers: wanted rc1 + 'exactly one', got rc=$t8_rc out='$t8_out'"; st_fail=1; fi

  # leg 11 (B2, quality F3 — pin the 'in-review' arm): the `in-progress|in-review)` case survives a
  # mutant that drops the `|in-review` alternative; leg 1 alone never catches it. Subject state=
  # in-review (a real round trip: state.in-review mapped to the fake adapter's status name) +
  # claimed=yes -> rc0.
  _t8_adapter 10001 "Selected" true
  _t8_conf_inreview=$(_t8_mkconf "state.in-review=Selected")
  t8_gr11=$(_t8_gitrepo "Kit-Row: AB-1" leg11 "$_t8_conf_inreview"); t8_dir11=${t8_gr11% *}; t8_head11=${t8_gr11#* }
  t8_rec11="$base/t8_rec_inreview.txt"; : > "$t8_rec11"
  if sh "$_t8_rr/scripts/tracker-read.sh" "$_t8_conf_inreview" - "$t8_rec11" AB-1 "$t8_head11" >/dev/null 2>&1; then t8_r11rc=0; else t8_r11rc=$?; fi
  if [ "$t8_r11rc" -ne 0 ] || ! grep -q '^row AB-1 state=in-review' "$t8_rec11"; then
    echo "selftest FAIL: t8/f1-inreview setup: reader rc=$t8_r11rc, record: $(tr '\n' ';' < "$t8_rec11" 2>/dev/null)"; st_fail=1
  fi
  KIT_TRACKER_RECORD="$t8_rec11"
  t8_run "$t8_dir11" "$t8_head11"
  if [ "$t8_rc" -eq 0 ]; then echo "selftest PASS: t8/f1-inreview: subject state=in-review + claimed=yes -> rc0 (B2)"
  else echo "selftest FAIL: t8/f1-inreview: wanted rc0, got rc=$t8_rc out='$t8_out'"; st_fail=1; fi

  # leg 10 (fix1 Q3): bp_tracker_presence's two seam calls share ONE record parse (T89s memo) — a
  # PLAIN call in THIS shell (no `$( … )` subshell) so the memo globals survive between them.
  # T10-harden-A P2 (STOPPED, reported rather than fixed): SEAM_TEST_LOAD_COUNT is a plain shell-
  # variable increment (conformance/backlog-lib.sh's `_seam_record_load`) — inherently subshell-
  # blind. If a future regression wraps ONE of seam_row_state/seam_row_flag's OWN internal seam-load
  # calls in `$( … )` (inside backlog-lib.sh, not this file), that increment happens in a subshell
  # and never reaches this leg's counter — the leg would stay green even though a second real parse
  # had crept in. Fixing this needs the counter itself to be subshell-observable (e.g. a scratch-file
  # append per parse) INSIDE backlog-lib.sh, which is outside this task's declared writes — left as
  # is per the brief's own escape valve; boarded for the owner (backlog-lib.sh is out of scope here).
  SEAM_TEST_LOAD_COUNT=0
  SEAM_ROOT="$t8_dir1"; SEAM_RECORD="$t8_rec1"
  bp_tracker_presence "$t8_head1" >/dev/null 2>&1 || :
  if [ "$SEAM_TEST_LOAD_COUNT" -eq 1 ]; then
    echo "selftest PASS: t8/one-parse: bp_tracker_presence's two seam calls share ONE record parse"
  else
    echo "selftest FAIL: t8/one-parse: wanted SEAM_TEST_LOAD_COUNT=1, got $SEAM_TEST_LOAD_COUNT"; st_fail=1
  fi
  unset SEAM_RECORD

  # legs 11-15 (fix1 Q2): --head through the REAL command line (t8h_run/t8h_assert, defined with
  # the other T8 helpers below) — an unvalidated value reaching `git log`/`cat-file` as a positional
  # could be read as a FLAG, never a revision.
  t8h_run
  t8h_assert "t8/head-omitted: --head never passed -> rc2, the one fixed sentence" 2
  t8h_run --head 0000000000000000000000000000000000000000
  t8h_assert "t8/head-allzero: 40 zeros is well-formed hex but names no commit -> rc2" 2
  t8h_run --head 1234567890abcdef1234567890abcdef12345678
  t8h_assert "t8/head-unknown: well-formed hex, no such commit -> rc2" 2
  t8_injected="$base/t8_injected_marker"
  t8h_run --head "--output=$t8_injected"
  t8h_assert "t8/head-output-injection: an option-shaped value is refused, never reaches git" 2
  if [ -e "$t8_injected" ]; then
    echo "selftest FAIL: t8/head-output-injection-nofile: the injected file WAS created"; st_fail=1
  else
    echo "selftest PASS: t8/head-output-injection-nofile: no file was created"
  fi
  t8h_run --head --help
  t8h_assert "t8/head-help: an option-shaped value is refused, never reaches git --help" 2

  # legs 16-19 (B3, security L-1 / quality F8): the head grammar aligned with the reader's and the
  # seam's own 40|64 acceptance (tracker-read.sh::tr_valid_head). A 64-hex head passes the GRAMMAR
  # then fails cat-file -e (this is a SHA-1 repo) -> the EXISTENCE sentence, never the grammar one.
  # 63/65-hex and uppercase are refused by the GRAMMAR itself (never reaching git).
  t8h_run --head 1111111111111111111111111111111111111111111111111111111111111111
  case "$t8h_out" in
    *"well-formed hex, but names no commit"*) _t8_ok=1 ;;
    *) _t8_ok=0 ;;
  esac
  case "$t8h_out" in *"(not 40 or 64 lowercase hex)"*) _t8_ok=0 ;; esac
  if [ "$_t8_ok" = 1 ] && [ "$t8h_rc" -eq 2 ]; then
    echo "selftest PASS: t8/head-64hex: a 64-hex head passes the grammar, fails cat-file -e -> rc2, the EXISTENCE sentence, not the grammar one"
  else
    echo "selftest FAIL: t8/head-64hex: wanted rc2 + the existence sentence, got rc=$t8h_rc out='$t8h_out'"; st_fail=1
  fi

  # WB-FIX-2 item 3 (security R3): a 64-hex string can resolve as a REF NAME, not just as a raw
  # object id — no SHA-1 object can BE 64 hex chars, so `cat-file -e` falls back to a ref lookup and
  # a same-named branch resolves. Create a branch in t8_dir1 whose NAME is a 64-hex string pointing
  # at a REAL commit, then pass that same string as --head: it must still refuse (rc2, the existence
  # sentence), never silently accept a ref-name resolution as if it were the head sha itself.
  _t8_refhead=2222222222222222222222222222222222222222222222222222222222222222
  git -C "$t8_dir1" branch "$_t8_refhead" "$t8_head1" >/dev/null 2>&1
  if ! git -C "$t8_dir1" rev-parse --verify --quiet "refs/heads/$_t8_refhead" >/dev/null; then
    echo "selftest FAIL: t8/head-64hex-refname setup — the 64-hex branch was not created"; st_fail=1
  fi
  t8h_run --head "$_t8_refhead"
  case "$t8h_out" in
    *"well-formed hex, but names no commit"*) _t8_ok=1 ;;
    *) _t8_ok=0 ;;
  esac
  if [ "$_t8_ok" = 1 ] && [ "$t8h_rc" -eq 2 ]; then
    echo "selftest PASS: t8/head-64hex-refname: a 64-hex head that ALSO names a real branch -> rc2, the existence sentence — never a silent ref-name resolution (WB-FIX-2 item 3)"
  else
    echo "selftest FAIL: t8/head-64hex-refname: wanted rc2 + the existence sentence, got rc=$t8h_rc out='$t8h_out'"; st_fail=1
  fi
  git -C "$t8_dir1" branch -D "$_t8_refhead" >/dev/null 2>&1

  t8h_run --head 111111111111111111111111111111111111111111111111111111111111111
  case "$t8h_out" in
    *"(not 40 or 64 lowercase hex)"*) _t8_ok=1 ;;
    *) _t8_ok=0 ;;
  esac
  if [ "$_t8_ok" = 1 ] && [ "$t8h_rc" -eq 2 ]; then
    echo "selftest PASS: t8/head-63hex: a 63-hex head is refused by the GRAMMAR (never the existence sentence)"
  else
    echo "selftest FAIL: t8/head-63hex: wanted rc2 + the grammar sentence, got rc=$t8h_rc out='$t8h_out'"; st_fail=1
  fi

  t8h_run --head 11111111111111111111111111111111111111111111111111111111111111111
  case "$t8h_out" in
    *"(not 40 or 64 lowercase hex)"*) _t8_ok=1 ;;
    *) _t8_ok=0 ;;
  esac
  if [ "$_t8_ok" = 1 ] && [ "$t8h_rc" -eq 2 ]; then
    echo "selftest PASS: t8/head-65hex: a 65-hex head is refused by the GRAMMAR (never the existence sentence)"
  else
    echo "selftest FAIL: t8/head-65hex: wanted rc2 + the grammar sentence, got rc=$t8h_rc out='$t8h_out'"; st_fail=1
  fi

  t8h_run --head A111111111111111111111111111111111111111
  case "$t8h_out" in
    *"(not 40 or 64 lowercase hex)"*) _t8_ok=1 ;;
    *) _t8_ok=0 ;;
  esac
  if [ "$_t8_ok" = 1 ] && [ "$t8h_rc" -eq 2 ]; then
    echo "selftest PASS: t8/head-uppercase: a 40-char head with an uppercase hex digit is refused by the GRAMMAR"
  else
    echo "selftest FAIL: t8/head-uppercase: wanted rc2 + the grammar sentence, got rc=$t8h_rc out='$t8h_out'"; st_fail=1
  fi

  # === T10-harden-A P1: _t8h_pick_shell picks the CURRENT interpreter (BASH_VERSION/ZSH_VERSION),
  # never a hardcoded 'sh' — pinned directly (a real bash/zsh re-invocation isn't reachable from a
  # dash/sh selftest run without those interpreters present as $0's own shell).
  _p1_savebash=${BASH_VERSION:-}; _p1_savezsh=${ZSH_VERSION:-}
  BASH_VERSION="5.0"; ZSH_VERSION=""
  _p1_bash=$(_t8h_pick_shell)
  BASH_VERSION=""; ZSH_VERSION="5.9"
  _p1_zsh=$(_t8h_pick_shell)
  BASH_VERSION=""; ZSH_VERSION=""
  _p1_sh=$(_t8h_pick_shell)
  BASH_VERSION=$_p1_savebash; ZSH_VERSION=$_p1_savezsh
  if [ "$_p1_bash" = bash ] && [ "$_p1_zsh" = zsh ] && [ "$_p1_sh" = sh ]; then
    echo "selftest PASS: t8/p1-shell-selector: t8h_run's shell selector tracks BASH_VERSION/ZSH_VERSION, never a hardcoded 'sh'"
  else
    echo "selftest FAIL: t8/p1-shell-selector: wanted bash/zsh/sh, got '$_p1_bash'/'$_p1_zsh'/'$_p1_sh'"; st_fail=1
  fi

  # leg 16 (H-4): KIT_TRACKER_RECORD unset -> today's rc3 NOT ENFORCED path, byte-identical (same
  # fixture + same string as the pre-existing cp/non-md-jira leg above — the byte-identical proof).
  unset KIT_TRACKER_RECORD
  d="$base/t8_h4_unset"; _proj_backend "$d" jira
  assert_msg "NOT ENFORCED: backend 'jira' — board-bound governance is not verified on this tree" 3 \
    "t8/h4-unset: KIT_TRACKER_RECORD unset stays today's rc3 NOT ENFORCED path, byte-identical (H-4)" "$d" 280 "$cfg"
  unset KIT_TRACKER_USER KIT_TRACKER_TOKEN   # hygiene: nothing later in this function inherits them

  # fix1 Q4 (hygiene): throwaway git repos carry no diagnostic value on FAIL (unlike the board-style
  # fixtures elsewhere in $base, deliberately left for inspection) — remove them explicitly.
  for _t8_d in "$t8_dir1" "$t8_dir2" "$t8_dir3" "$t8_dir4" "$t8_dir5" "$t8_dir6" "$t8_dir7" "$t8_dir9"; do
    [ -n "$_t8_d" ] && [ -d "$_t8_d" ] && rm -rf "$_t8_d"
  done
  # T10-harden-A P1: _t8_mkconf's own copies live OUTSIDE $base (mktemp) — clean them explicitly,
  # the same hygiene convention as the throwaway git repos just above.
  for _t8_mc in ${_t8_mkconf_files:-}; do
    [ -n "$_t8_mc" ] && [ -f "$_t8_mc" ] && rm -f "$_t8_mc"
  done

  if [ "$st_fail" -ne 0 ]; then
    echo "backlog-presence --selftest: FAIL" >&2
    return 1
  fi
  echo "backlog-presence --selftest: OK (fixtures left in $base)"
  return 0
}

# --- selftest-only helpers (defined AFTER the selftest() marker on purpose) --------------
# These live in the ORACLE region so the non-vacuity mutation harness (which mutates only lines
# BEFORE the first ^selftest() marker) cannot neuter the oracle's own failure accumulator
# (st_fail flip). The CHECK logic above the marker stays mutable, as it must.
# assert_present <dir> <pr> <label> : row_bears_pr on <dir>/BACKLOG.md must rc0.
assert_present() {
  if row_bears_pr "$1/BACKLOG.md" "$2" "${4:-}" "${5:-}" >/dev/null 2>&1; then _r=0; else _r=$?; fi
  if [ "$_r" -eq 0 ]; then
    echo "selftest PASS: $3"
  else
    echo "selftest FAIL: $3 (row_bears_pr rc=$_r, wanted 0/present)"; st_fail=1
  fi
}
# assert_absent <dir> <pr> <label> [<branch>] [<base-board-path>] : row_bears_pr on <dir>/BACKLOG.md
# must rc!=0.
assert_absent() {
  if row_bears_pr "$1/BACKLOG.md" "$2" "${4:-}" "${5:-}" >/dev/null 2>&1; then _r=0; else _r=$?; fi
  if [ "$_r" -ne 0 ]; then
    echo "selftest PASS: $3"
  else
    echo "selftest FAIL: $3 (row_bears_pr rc=$_r, wanted !=0/absent)"; st_fail=1
  fi
}
# assert_gated <changed-file> <label> : gate_class must print exactly `gated`.
assert_gated() {
  _g=$(gate_class "$1")
  if [ "$_g" = gated ]; then
    echo "selftest PASS: $2"
  else
    echo "selftest FAIL: $2 (gate_class -> '$_g', wanted gated)"; st_fail=1
  fi
}
# assert_ordinary <changed-file> <label> : gate_class must print exactly `ordinary`.
assert_ordinary() {
  _g=$(gate_class "$1")
  if [ "$_g" = ordinary ]; then
    echo "selftest PASS: $2"
  else
    echo "selftest FAIL: $2 (gate_class -> '$_g', wanted ordinary)"; st_fail=1
  fi
}
# assert_gated_env <VAR=value> <changed-file> <label> : export a HOSTILE classifier-config env var in
# a subshell, then assert gate_class STILL prints `gated`. Proves the seam calls scrub the env rather
# than letting a decoy redirect the real-run targets (spec §7). The export is subshell-local, so it
# cannot leak into any other fixture.
assert_gated_env() {
  _g=$( eval "export $1"; gate_class "$2" )
  if [ "$_g" = gated ]; then
    echo "selftest PASS: $3"
  else
    echo "selftest FAIL: $3 (gate_class -> '$_g' with $1, wanted gated)"; st_fail=1
  fi
}
# assert_gated_nojq <changed-file> <label> : run gate_class under a PATH with EVERY binary except jq,
# then assert it prints `gated`. Proves the fail-CLOSED jq guard: a missing tool must never widen what
# passes. The stripped PATH is subshell-local. _jqless_path builds a symlink farm of the real PATH,
# omitting only jq, so all other tools the seams need remain resolvable.
assert_gated_nojq() {
  _farm=$(_jqless_path)
  _g=$( PATH="$_farm"; export PATH; gate_class "$1" )
  if [ "$_g" = gated ]; then
    echo "selftest PASS: $2"
  else
    echo "selftest FAIL: $2 (gate_class -> '$_g' under jq-less PATH, wanted gated)"; st_fail=1
  fi
}
# _jqless_path -> print a fresh dir that symlinks every executable on the current PATH EXCEPT jq, so
# `command -v jq` fails there while grep/awk/sed/sh/env/... all still resolve.
_jqless_path() {
  _d=$(mktemp -d)
  # `IFS= read` is command-scoped -- never a global IFS assignment (semgrep: ifs-tampering).
  # PATH is ':'-delimited; tr it to newlines and read line-wise.
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    [ -d "$_p" ] || continue
    for _b in "$_p"/*; do
      { [ -f "$_b" ] && [ -x "$_b" ]; } || continue
      _n=${_b##*/}
      [ "$_n" = jq ] && continue
      [ -e "$_d/$_n" ] || ln -s "$_b" "$_d/$_n" 2>/dev/null
    done
  done <<PATH_EOF
$(printf '%s\n' "$PATH" | tr ':' '\n')
PATH_EOF
  printf '%s\n' "$_d"
}
# assert_msg <expected-substring> <expected-rc> <label> <dir> <pr> <changed-file> : drive check_pr BY
# ARGUMENT and assert its VERDICT STRING *and its rc*. The string alone is not enough — B5's rider
# (S8) measured the three-states-collapse: misconfiguration (unrecognized backend, md-declared-but-no-
# board) and the genuine no-row WAIT all returned rc 1, so a poster rendered a broken gate as the same
# yellow as a healthy waiting one. The rc is part of the declared contract now, so the oracle asserts it.
assert_msg() {
  if _out=$(check_pr "$4" "$5" "$6" 2>&1); then _rc=0; else _rc=$?; fi
  _ok=1
  case "$_out" in
    *"$1"*) ;;
    *) _ok=0 ;;
  esac
  [ "$_rc" -eq "$2" ] || _ok=0
  if [ "$_ok" = 1 ]; then
    echo "selftest PASS: $3"
  else
    echo "selftest FAIL: $3 (check_pr rc=$_rc wanted $2; out='$_out', wanted to contain '$1')"; st_fail=1
  fi
}
# assert_msg_ctx <expected-substring> <expected-rc> <label> <dir> <pr> <changed-file> <base-dir>
# <live-contexts-file> : the same oracle as assert_msg, but also drives check_pr's 8th/9th positional
# arguments (TRACKER-TRUSTED-JOB-REQUIRED-CONTEXT T1's --base-dir / --live-contexts) — needed for
# every bp_tracker_delegated leg, which assert_msg's fixed 3-argument call cannot reach.
assert_msg_ctx() {
  if _octx_out=$(check_pr "$4" "$5" "$6" "" 0 "" "" "$7" "$8" 2>&1); then _octx_rc=0; else _octx_rc=$?; fi
  _octx_ok=1
  case "$_octx_out" in
    *"$1"*) ;;
    *) _octx_ok=0 ;;
  esac
  [ "$_octx_rc" -eq "$2" ] || _octx_ok=0
  if [ "$_octx_ok" = 1 ]; then
    echo "selftest PASS: $3"
  else
    echo "selftest FAIL: $3 (check_pr rc=$_octx_rc wanted $2; out='$_octx_out', wanted to contain '$1')"; st_fail=1
  fi
}

# br_run <dir> <pr> <changed-file> <branch> : drive check_pr BY ARGUMENT with a branch and keep BOTH
# the verdict text and the rc for the assertions below. The T3 legs assert several properties of ONE
# verdict (wording present, wording ABSENT, rc), which assert_msg's single-substring shape cannot
# express — a refusal written for a stranger is graded on what it does NOT say as much as what it does.
br_run() {
  if br_out=$(check_pr "$1" "$2" "$3" "$4" 2>&1); then br_rc=0; else br_rc=$?; fi
}
# br_run_base <dir> <pr> <changed-file> <branch> <base-board-path> : the same as br_run, but also
# passes check_pr's 6th positional arg (base-board) — needed to drive the S-6 relay's check_pr-level
# assertions (claims stays off/0, the 5th positional).
br_run_base() {
  if br_out=$(check_pr "$1" "$2" "$3" "$4" 0 "$5" 2>&1); then br_rc=0; else br_rc=$?; fi
}
# br_run_nojq <dir> <pr> <changed-file> <branch> : the same, under a PATH holding every binary EXCEPT
# jq (the symlink farm assert_gated_nojq already uses), so the fail-safe route is the one under test.
br_run_nojq() {
  _farm=$(_jqless_path)
  if br_out=$( PATH="$_farm"; export PATH; check_pr "$1" "$2" "$3" "$4" 2>&1 ); then br_rc=0; else br_rc=$?; fi
}
br_expect_rc() { # <want-rc> <label>
  if [ "$br_rc" -eq "$1" ]; then echo "selftest PASS: $2"
  else echo "selftest FAIL: $2 (check_pr rc=$br_rc, wanted $1); out='$br_out'"; st_fail=1; fi
}
br_has() { # <label> <needle>
  case "$br_out" in
    *"$2"*) echo "selftest PASS: $1" ;;
    *) echo "selftest FAIL: $1 (verdict does not carry '$2'); out='$br_out'"; st_fail=1 ;;
  esac
}
br_run_claims() { # <dir> <pr> <changed-file> <branch> : the same as br_run, with the --claims arm ON.
  if br_out=$(check_pr "$1" "$2" "$3" "$4" 1 2>&1); then br_rc=0; else br_rc=$?; fi
}
# _claims_fixture <claim-branch|""> -> echo a project dir that is a real git clone of a real bare
# remote, declaring an md backend, whose board carries `ROW-1` In Progress and an In Review row bound
# to `feat/claims` (so PRESENCE always passes and only the claim is under test). When <claim-branch>
# is non-empty a REAL claim ref is pushed to that remote for `ROW-1`, held by "Other Session" at a
# FIXED time — built with the same plumbing shape board-claim.sh uses (hash-object -> mktree ->
# commit-tree -> push), deliberately written out here rather than driven through the verb, so this
# oracle does not depend on the verb it is grading.
_claims_fixture() {
  _cx=$(mktemp -d)
  git init -q --bare "$_cx/remote.git"
  git clone -q "$_cx/remote.git" "$_cx/proj" 2>/dev/null
  ( cd "$_cx/proj"
    git config user.name  'This Session'
    git config user.email 'this@example.com'
    git config commit.gpgsign false ) >/dev/null 2>&1
  _proj_backend "$_cx/proj" md
  {
    echo '# Fixture — Backlog'
    echo
    echo '## In Progress'
    echo
    echo '| Item | Owner | Started | Links |'
    echo '|------|-------|---------|-------|'
    echo '| `ROW-1` — the claimed work | agent | 2026-09-04 | — |'
    echo
    echo '## In Review'
    echo
    echo '| Item | Reviewer | PR |'
    echo '|------|----------|----|'
    echo '| `ROW-1` | — | feat/claims |'
  } > "$_cx/proj/BACKLOG.md"
  if [ -n "$1" ]; then
    ( cd "$_cx/proj"
      _b=$(printf 'row: ROW-1\nclaimant: Other Session <other@example.com>\nbranch: %s\nclaimed-at: 2026-09-04T00:00:00Z\n' "$1" | git hash-object -w --stdin)
      _t=$(printf '100644 blob %s\tCLAIM\n' "$_b" | git mktree)
      _c=$(printf 'claim ROW-1\n' | GIT_AUTHOR_NAME='Other Session' GIT_AUTHOR_EMAIL='other@example.com' \
            GIT_COMMITTER_NAME='Other Session' GIT_COMMITTER_EMAIL='other@example.com' git commit-tree "$_t")
      git push origin "$_c:refs/claims/ROW-1" ) >/dev/null 2>&1
  fi
  printf '%s\n' "$_cx/proj"
}
br_hasnt() { # <label> <needle>
  case "$br_out" in
    *"$2"*) echo "selftest FAIL: $1 (verdict wrongly carries '$2'); out='$br_out'"; st_fail=1 ;;
    *) echo "selftest PASS: $1" ;;
  esac
}

# --- fixture writers --------------------------------------------------------------------
# _board <dir> <in-review-row> : write a valid in-use board whose In Review section carries the
# given `| Item | Reviewer | PR |` row. Only In Review carries a PR column (shipped schema).
_board() {
  mkdir -p "$1"
  cat > "$1/BACKLOG.md" <<EOF
# Proj — Backlog

## In Review

| Item | Reviewer | PR |
|------|----------|----|
$2
EOF
}
# _done_board <dir> <done-row> : a board whose only in-use table is Done, in the shipped schema
# `| Item | Closed | Retro/outcome |` — no `PR` column anywhere, which is exactly the shape the
# Done arm must read (SLICE-CLOSES-IN-ONE-PR §4.2).
_done_board() {
  mkdir -p "$1"
  cat > "$1/BACKLOG.md" <<EOF
# Proj — Backlog

## Done

| Item | Closed | Retro/outcome |
|------|--------|---------------|
$2
EOF
}
# _notes_board <dir> <notes-cell> : a board whose In Review row has a real PR (#99) in the PR cell
# and the given text in a trailing Notes cell — so a number appearing only in Notes never satisfies.
_notes_board() {
  mkdir -p "$1"
  cat > "$1/BACKLOG.md" <<EOF
# Proj — Backlog

## In Review

| Item | Reviewer | PR | Notes |
|------|----------|----|-------|
| KW6-A2 | — | #99 | $2 |
EOF
}
# _proj_backend <dir> <token> : a project dir declaring only a Backlog backend field (no board).
_proj_backend() {
  mkdir -p "$1"
  cat > "$1/CLAUDE.md" <<EOF
# Proj

- **Backlog backend** (§6): $2
EOF
}
# _proj_tracker_base <dir> : a BASE checkout bp_tracker_delegated can accept — declares jira, ships
# its OWN copy of the real scripts/tracker-conf.sh (never this process's cwd's copy at call time —
# the predicate reads <base-dir>/scripts/tracker-conf.sh, so the fixture must carry one), and a
# `.kit/tracker.conf` that validator accepts (TRACKER-TRUSTED-JOB-REQUIRED-CONTEXT T1).
_proj_tracker_base() {
  mkdir -p "$1/scripts" "$1/.kit"
  cp "$(pwd)/scripts/tracker-conf.sh" "$1/scripts/tracker-conf.sh"
  _proj_backend "$1" jira
  cat > "$1/.kit/tracker.conf" <<EOF
version=1
backend=jira
base_url=https://ex.atlassian.net
flavour=cloud
auth=basic
project=AB
list_cap=200
state.ready=Selected
state.in-progress=In Progress
field.acceptance=description
field.metric=label:metric
field.size=label:size
field.risk=customfield_10088
EOF
}
# _proj_md_board <dir> <in-review-row> : a project dir declaring an md backend AND carrying a real
# in-use board with the given In Review row.
_proj_md_board() {
  _proj_backend "$1" md
  _board "$1" "$2"
}
# _proj_ip_board <dir> <n> : a project dir declaring md, whose board carries N In Progress rows
# (each a backticked identifier in the Item column, the shipped board's shape) and an In Review
# section bound to an UNRELATED PR — so the presence check genuinely fails while In Progress rows
# exist to be hinted at.
_proj_ip_board() {
  _proj_backend "$1" md
  {
    echo '# Proj — Backlog'
    echo
    echo '## In Progress'
    echo
    echo '| Item | Owner | Started | Links |'
    echo '|------|-------|---------|-------|'
    _ipn=0
    while [ "$_ipn" -lt "$2" ]; do
      _ipn=$((_ipn + 1))
      printf '| `ROW-%s` — some claimed work | agent | 2026-09-02 | — |\n' "$_ipn"
    done
    echo
    echo '## In Review'
    echo
    echo '| Item | Reviewer | PR |'
    echo '|------|----------|----|'
    echo '| `OTHER-ROW` | — | #99 |'
  } > "$1/BACKLOG.md"
}
# _proj_template <dir> : a project dir declaring an md backend whose board is the PRISTINE template
# (carries the `| [title] |` example row and no other real data row) -> is_pure_template rc0 -> N/A.
_proj_template() {
  _proj_backend "$1" md
  cat > "$1/BACKLOG.md" <<EOF
# Proj — Backlog

## In Review

| Item | Reviewer | PR |
|------|----------|----|
| [title] | — | — |
EOF
}

# --- TBG-READER-FLAGS-LIST T8 selftest-only helpers (also live AFTER the marker on purpose) ------
# _t8_adapter <status-id> <status-name> <assignee-present: true|false|""> : (re)writes the fake
# tracker-jira.sh a COPY of the real reader dispatches to (T8's $_t8_rr). Every op EXCEPT get-issue
# `cat`s the SAME tracked conformance/fixtures/tracker-jira/ops/*.out files T2/T3/T5 proved (drift
# lock); get-issue's plain key/status fields are inline here, matching tracker-read.sh's OWN
# selftest convention for scenarios that are not exercising the assignee-present drift itself
# (T5b1's dedicated get-issue-assigned/unassigned.out pair is reserved for THAT drift, and cannot
# also supply the second in-progress id F-1 needs — see the leg-1 comment above).
_t8_adapter() {
  case "$3" in
    true|false) _t8a_extra='assignee-present\t'"$3"'\n' ;;
    *)          _t8a_extra='' ;;
  esac
  cat > "$_t8_rr/scripts/tracker-jira.sh" <<EOF
#!/bin/sh
case "\$1" in
  permissions) echo ok; exit 0 ;;
  status-ids) cat "$_t8_ops/status-ids-cloud.out"; exit 0 ;;
  get-issue) printf 'key\tAB-1\nstatus-id\t$1\nstatus-name\t$2\n$_t8a_extra'; exit 0 ;;
  list-in-states) cat "$_t8_ops/list-cloud-inprogress.out"; exit 0 ;;
esac
EOF
  chmod +x "$_t8_rr/scripts/tracker-jira.sh"
}
# _t8_mkconf [<extra-conf-line>] : a PRIVATE copy of the shared fixture's base conf (fix1 Q1 —
# NEVER the tracked file itself) + `list_cap=200` (so a requested list genuinely reaches the record,
# never the R5 "list_cap absent" omission) + one optional extra line (leg 4's `state.ready=Selected`).
# Prints the new file's path. T10-harden-A P1: unlike $base (deliberately left for inspection), each
# copy lands OUTSIDE $base via `mktemp` — tracked in $_t8_mkconf_files so it can be cleaned explicitly
# (fix1 Q4's own hygiene convention, one line down from here) rather than littering the system tmpdir.
_t8_mkconf() {
  _t8mc_f=$(mktemp)
  _t8_mkconf_files="${_t8_mkconf_files:-} $_t8mc_f"
  cat "$_t8_conf_src" > "$_t8mc_f"
  printf 'list_cap=200\n' >> "$_t8mc_f"
  [ -n "${1:-}" ] && printf '%s\n' "$1" >> "$_t8mc_f"
  printf '%s' "$_t8mc_f"
}
# _t8_gitrepo <trailer-line-or-""> <nonce> [<conf-path>] : a THROWAWAY git repo (never this clone's
# own history — hard rule), seeded with a COPY of <conf-path> (default $_t8_conf — fix1 Q1: a leg
# passes its OWN conf copy so the repo's .kit/tracker.conf pins to whatever conf its record was
# actually read against) + CLAUDE.md, one commit whose message carries <trailer-line> as its own
# final paragraph (or none, when ""). <nonce> (a distinct literal per call site) lands in a
# `.t8-nonce` file so two calls with the SAME trailer text never produce the SAME tree+message+
# timestamp — and so the SAME commit sha (measured live: two such calls one second apart are
# otherwise byte-identical git objects). Prints "<dir> <sha>" on ONE line — never a global (a caller
# capturing $(...) runs this in a SUBSHELL; a global set inside it is invisible back in the parent
# under set -u, measured live) — callers split on the LAST space (neither a mktemp path nor a hex
# sha ever carries one).
_t8_gitrepo() {
  _t8g_dir=$(mktemp -d)
  git -C "$_t8g_dir" init -q
  mkdir -p "$_t8g_dir/.kit"
  cp "${3:-$_t8_conf}" "$_t8g_dir/.kit/tracker.conf"
  cp "$_t8_claude" "$_t8g_dir/CLAUDE.md"
  printf '%s\n' "$2" > "$_t8g_dir/.t8-nonce"
  git -C "$_t8g_dir" add -A
  if [ -n "$1" ]; then
    git -C "$_t8g_dir" -c user.email=t8@example.com -c user.name=T8 commit -q -m "t8 fixture" -m "$1"
  else
    git -C "$_t8g_dir" -c user.email=t8@example.com -c user.name=T8 commit -q -m "t8 fixture, no trailer"
  fi
  _t8g_sha=$(git -C "$_t8g_dir" rev-parse HEAD)
  printf '%s %s\n' "$_t8g_dir" "$_t8g_sha"
}
# t8_run <dir> <head> : drive check_pr's tracker arm BY ARGUMENT (KIT_TRACKER_RECORD already set by
# the caller), keeping both the verdict text and the rc — wrapped in `if` per this file's own
# set -e discipline (mirrors br_run/assert_msg above).
t8_run() {
  if t8_out=$(check_pr "$1" 0 "$cfg" "" 0 "" "$2" 2>&1); then t8_rc=0; else t8_rc=$?; fi
}
# _t8h_pick_shell : T10-harden-A P1 — the interpreter t8h_run re-invokes THIS script under is the
# one the selftest itself is running under (BASH_VERSION/ZSH_VERSION), never a hardcoded 'sh' that
# would silently switch interpreter mid-test when the selftest was launched under a different shell.
_t8h_pick_shell() {
  if [ -n "${BASH_VERSION:-}" ]; then printf 'bash'
  elif [ -n "${ZSH_VERSION:-}" ]; then printf 'zsh'
  else printf 'sh'
  fi
}
# t8h_run [<extra CLI args>...] : fix1 Q2 — invoke THIS SCRIPT'S OWN CLI as a subprocess (not
# check_pr directly), so --head's real argv-parsing path is exercised end to end (t8_dir1/t8_rec1,
# the F-1 positive fixture, already built by leg 1).
t8h_run() {
  _t8h_shell=$(_t8h_pick_shell)
  if t8h_out=$(KIT_TRACKER_RECORD="$t8_rec1" "$_t8h_shell" conformance/backlog-presence.sh --dir "$t8_dir1" --pr 0 --changed "$cfg" "$@" 2>&1); then t8h_rc=0; else t8h_rc=$?; fi
}
# t8h_assert <label> <expected-rc> : t8h_run's rc AND the one fixed head-refusal sentence.
t8h_assert() {
  case "$t8h_out" in
    *"is not a well-formed, existing commit sha"*) _t8h_ok=1 ;;
    *) _t8h_ok=0 ;;
  esac
  [ "$t8h_rc" -eq "$2" ] || _t8h_ok=0
  if [ "$_t8h_ok" = 1 ]; then echo "selftest PASS: $1"
  else echo "selftest FAIL: $1 (rc=$t8h_rc out='$t8h_out')"; st_fail=1; fi
}

case "${1:-}" in
  --selftest)
    selftest; exit $?
    ;;
  --dir|--pr|--changed|--branch|--claims|--base-board|--head|--base-dir|--live-contexts)
    # --branch is OPTIONAL and, like every other target here, comes BY ARGUMENT — never the environment.
    # (An env-supplied target lets a decoy redirect a control-plane check; that pattern was rejected once
    # already and is not coming back.) Absent --branch, the gate behaves exactly as before: PR-number only.
    # --claims is a FLAG (no value) and is OFF unless passed: it is the only arm here that touches the
    # network, so it must be opted into by the caller that has one — the CI PR job — and never by the
    # pre-push hook, which runs on a plane as often as not.
    # --base-board is OPTIONAL (TIER0-LOCKS-OWED a): the path to the BASE board (origin/main's
    # BACKLOG.md at the merge-base) — BY ARGUMENT, never the environment. Absent it, the Done arm's
    # branch form never binds (fail-safe; see row_bears_pr). Only the pre-push caller supplies it
    # today; the CI PR job binds by number and does not need it.
    # --head is OPTIONAL (TBG-READER-FLAGS-LIST T8): the PR head SHA the tracker arm reads its
    # Kit-Row trailer from — BY ARGUMENT, mirroring loop-state.sh's own --head. Only meaningful when
    # KIT_TRACKER_RECORD is also set (bp_tracker_presence); absent it, today's non-md path is unchanged.
    # --base-dir / --live-contexts are OPTIONAL (TRACKER-TRUSTED-JOB-REQUIRED-CONTEXT T1): the base
    # checkout + the live required-contexts file bp_tracker_delegated reads — BY ARGUMENT, never the
    # environment. Absent either, the predicate is false (fail-closed) and today's non-md behaviour
    # is unchanged.
    _dir=""; _pr=""; _cf=""; _br=""; _cl=0; _bb=""; _hd=""; _bd=""; _lc=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --dir)        [ $# -ge 2 ] || { echo "usage: --dir needs a value" >&2; exit 2; }; _dir=$2; shift 2 ;;
        --pr)         [ $# -ge 2 ] || { echo "usage: --pr needs a value" >&2; exit 2; }; _pr=$2; shift 2 ;;
        --changed)    [ $# -ge 2 ] || { echo "usage: --changed needs a value" >&2; exit 2; }; _cf=$2; shift 2 ;;
        --branch)     [ $# -ge 2 ] || { echo "usage: --branch needs a value" >&2; exit 2; }; _br=$2; shift 2 ;;
        --base-board) [ $# -ge 2 ] || { echo "usage: --base-board needs a value" >&2; exit 2; }; _bb=$2; shift 2 ;;
        --head)       [ $# -ge 2 ] || { echo "usage: --head needs a value" >&2; exit 2; }; _hd=$2; shift 2 ;;
        --base-dir)      [ $# -ge 2 ] || { echo "usage: --base-dir needs a value" >&2; exit 2; }; _bd=$2; shift 2 ;;
        --live-contexts) [ $# -ge 2 ] || { echo "usage: --live-contexts needs a value" >&2; exit 2; }; _lc=$2; shift 2 ;;
        --claims)  _cl=1; shift ;;
        *) echo "usage: backlog-presence.sh --dir <d> --pr <n> --changed <listing> [--branch <name>] [--base-board <path>] [--head <sha>] [--base-dir <dir>] [--live-contexts <file>] [--claims]" >&2; exit 2 ;;
      esac
    done
    { [ -n "$_dir" ] && [ -n "$_pr" ] && [ -n "$_cf" ]; } || {
      echo "usage: backlog-presence.sh --dir <d> --pr <n> --changed <listing> [--branch <name>] [--base-board <path>] [--head <sha>] [--base-dir <dir>] [--live-contexts <file>] [--claims]" >&2; exit 2; }
    check_pr "$_dir" "$_pr" "$_cf" "$_br" "$_cl" "$_bb" "$_hd" "$_bd" "$_lc"; exit $?
    ;;
  *)
    echo "usage: backlog-presence.sh --selftest | --dir <d> --pr <n> --changed <listing> [--branch <name>] [--base-board <path>] [--head <sha>] [--base-dir <dir>] [--live-contexts <file>] [--claims]" >&2
    exit 2
    ;;
esac
