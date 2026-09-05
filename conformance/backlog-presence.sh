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
#   a Done row citing `feat/x` will satisfy a LATER `--pr 0 --branch feat/x` pre-push run for
#   unrelated work. That fail-open is reachable ONLY from the local pre-push speed bump (which
#   `--no-verify` already bypasses); the REQUIRED CI context runs with `--pr N` and does not decay.
#   Boarded as `PRESENCE-DONE-ARM-BRANCH-DECAY`; the fix bounds the arm to rows NEW in the pushed
#   change-set and touches hooks/pre-push.
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

row_bears_pr() {
  _bl="$1"; _pr="$2"; _br="${3:-}"; _rows_f=$(mktemp)
  [ -n "$_br" ] && _bre=$(esc_ere "$_br") || _bre=""
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
    # ⚠️ THE TWO BINDINGS DECAY DIFFERENTLY, AND ONLY ONE OF THEM DECAYS (review M1):
    #   • PR NUMBER never decays. Numbers are unique per repo and monotonic, so a Done row citing
    #     #627 can satisfy exactly one PR — #627, which is already merged. Age is irrelevant.
    #   • BRANCH NAME CAN decay. Branch names RECUR (`feat/fix-board`, `chore/release` are reused
    #     freely), so a Done row closed under this rule citing `feat/x` will satisfy a LATER
    #     `--pr 0 --branch feat/x` pre-push run for unrelated work. That is a FAIL-OPEN, and it is
    #     disclosed rather than defended here.
    # WHAT IT IS AND IS NOT: the branch form is reachable only from the PRE-PUSH SPEED BUMP, which
    # `--no-verify` and an uninstalled hook already bypass. The REQUIRED CI CONTEXT runs with
    # `--pr N` (a number exists by then) and is unaffected — the binding that gates the merge does
    # not decay. The epoch bounds the population but cannot bound it to THIS push, and a
    # clock-relative window was rejected: a gate whose verdict depends on when it runs is not a
    # gate. The real fix bounds the arm to rows NEW in the pushed change-set (the base board is
    # available to the hook) — boarded as `PRESENCE-DONE-ARM-BRANCH-DECAY`, and it touches
    # hooks/pre-push, which this slice does not.
    _ridx=""; _cidx=""
    if [ -z "$_idx" ]; then
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
        rm -f "$_rows_f"; return 0
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
# line. Uses the SAME parser sequence as row_bears_pr (section_rows -> skip header row 1 -> skip
# separators -> cell), so the two cannot drift over what a row is.
# ⚠️ A BOARD CELL IS UNTRUSTED TEXT AND A TERMINAL IS A SINK. Every identifier is passed through
# `tr -cd '[:print:]'` (control/escape bytes stripped — a cell carrying an ANSI sequence must not be
# able to repaint the operator's terminal) and emitted with `printf '%s\n'` as an ARGUMENT, never as
# a format string. The board is not attacker-controlled in the ordinary case; it is text of unbounded
# provenance in every other one.
inprogress_hints() {
  _ih_f=$(mktemp)
  section_rows "$1" "In Progress" > "$_ih_f" 2>/dev/null || :
  if [ -s "$_ih_f" ]; then
    _ih_n=0
    while IFS= read -r _ih_row; do
      _ih_n=$((_ih_n + 1))
      [ "$_ih_n" -eq 1 ] && continue          # row 1 is the section header, not data
      is_sep_row "$_ih_row" && continue
      _ih_c=$(cell "$_ih_row" 1)
      case "$_ih_c" in
        *'`'*) _ih_id=${_ih_c#*\`}; _ih_id=${_ih_id%%\`*} ;;
        *) continue ;;                        # no backticked identifier -> nothing quotable to hint
      esac
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
  _dir="$1"; _pr="$2"; _cf="$3"; _br="${4:-}"; _claims="${5:-0}"
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
    _otok=$(resolve_backend "$_dir")
    [ "$_otok" = md ] || return 0
    _obl="$_dir/BACKLOG.md"
    [ -f "$_obl" ] || return 0
    if is_pure_template "$_obl"; then return 0; fi
    [ -n "$(inprogress_hints "$_obl")" ] || return 0
    if check_claims "$_dir" "$_br"; then return 0; else return $?; fi
  fi
  _tok=$(resolve_backend "$_dir")
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
    _bp_ne=0
    # $0-RELATIVE, never cwd-relative (security S-L5). This script `cd`s to the repo root at :36 so
    # the bare path happened to work today, but the validator's location is a property of where THIS
    # file lives, not of where the process happens to stand — and a caller that changes directory
    # (or a future edit that drops the cd) would silently read "validator absent" and treat every
    # waiver as missing. backlog-current.sh already resolved it this way; now both do.
    not_enforced_notice "$_tok" "$_dir" "$(dirname "$0")/waivers-valid.sh" || _bp_ne=$?
    return "$_bp_ne"
  fi
  _bl="$_dir/BACKLOG.md"
  [ -f "$_bl" ] || { echo "FAIL: declares an md backend but has no BACKLOG.md"; return 2; }
  if is_pure_template "$_bl"; then echo "N/A: board not yet in use (pristine template)"; return 0; fi
  # The verdict STRINGS are a contract (the selftest asserts them verbatim, and humans read them in CI
  # logs). When no --branch is supplied the message is byte-for-byte what it always was — branch binding
  # is ADDITIVE and must not perturb the existing surface. The branch is named only when it is in play.
  if row_bears_pr "$_bl" "$_pr" "$_br"; then
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
  if [ -n "$_br" ] && [ "$_pr" = 0 ]; then
    echo "FAIL: backlog-presence — no board row bears branch '$_br' in its PR cell (gated change-class). The row must sit in a section with a \`PR\` column — In Review in the shipped schema.$_doneform$_jqnote"
  elif [ -n "$_br" ]; then
    echo "FAIL: backlog-presence — no board row bears PR #$_pr or branch '$_br' in its PR cell (gated change-class). The row must sit in a section with a \`PR\` column — In Review in the shipped schema.$_doneform$_jqnote"
  else
    echo "FAIL: backlog-presence — no board row bears PR #$_pr in its PR cell (gated change-class). The row must sit in a section with a \`PR\` column — In Review in the shipped schema.$_doneform$_jqnote"
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

  # BRANCH binding in a Done retro — the form the pre-push run (`--pr 0`) actually uses.
  d="$base/t1c_done_branch"
  _done_board "$d" '| `SLICE` | 2026-09-03 | L1 retro. Shipped from feat/slice-closes on a green first run. |'
  assert_present "$d" 0 "t1c/done-branch: a branch token in a post-epoch Done retro -> rc0" "feat/slice-closes"

  # ...and the branch boundary discipline holds inside the retro cell too.
  assert_absent "$d" 0 "t1c/done-branch-superstring: 'feat/slice-close' must not match 'feat/slice-closes'" "feat/slice-close"

  # `--pr 0` MUST NOT bind to a literal `#0` in a Done retro either (security S3 carried into the
  # new arm): 0 means "no PR exists yet", and a `#0` cell would otherwise satisfy every branch.
  d="$base/t1c_done_hash_zero"
  _done_board "$d" '| `SLICE` | 2026-09-03 | L1 retro. A stray #0 placeholder sits in this cell and binds nothing at all. |'
  assert_absent "$d" 0 "t1c/done-hash-zero: a literal '#0' in a Done retro must not satisfy --pr 0" "feat/unbound"

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
  # …and the verdict must carry the CURE, or it is a red with no ladder.
  d="$base/cp_nonmd_jira"
  assert_msg "Cure: TRACKER-BACKED-GOVERNANCE, or ratify a board-governance waiver" 3 \
    "cp/non-md-cure: the NOT ENFORCED verdict names both cures" "$d" 280 "$cfg"

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
  if row_bears_pr "$1/BACKLOG.md" "$2" "${4:-}" >/dev/null 2>&1; then _r=0; else _r=$?; fi
  if [ "$_r" -eq 0 ]; then
    echo "selftest PASS: $3"
  else
    echo "selftest FAIL: $3 (row_bears_pr rc=$_r, wanted 0/present)"; st_fail=1
  fi
}
# assert_absent <dir> <pr> <label> : row_bears_pr on <dir>/BACKLOG.md must rc!=0.
assert_absent() {
  if row_bears_pr "$1/BACKLOG.md" "$2" "${4:-}" >/dev/null 2>&1; then _r=0; else _r=$?; fi
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

# br_run <dir> <pr> <changed-file> <branch> : drive check_pr BY ARGUMENT with a branch and keep BOTH
# the verdict text and the rc for the assertions below. The T3 legs assert several properties of ONE
# verdict (wording present, wording ABSENT, rc), which assert_msg's single-substring shape cannot
# express — a refusal written for a stranger is graded on what it does NOT say as much as what it does.
br_run() {
  if br_out=$(check_pr "$1" "$2" "$3" "$4" 2>&1); then br_rc=0; else br_rc=$?; fi
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

case "${1:-}" in
  --selftest)
    selftest; exit $?
    ;;
  --dir|--pr|--changed|--branch|--claims)
    # --branch is OPTIONAL and, like every other target here, comes BY ARGUMENT — never the environment.
    # (An env-supplied target lets a decoy redirect a control-plane check; that pattern was rejected once
    # already and is not coming back.) Absent --branch, the gate behaves exactly as before: PR-number only.
    # --claims is a FLAG (no value) and is OFF unless passed: it is the only arm here that touches the
    # network, so it must be opted into by the caller that has one — the CI PR job — and never by the
    # pre-push hook, which runs on a plane as often as not.
    _dir=""; _pr=""; _cf=""; _br=""; _cl=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --dir)     [ $# -ge 2 ] || { echo "usage: --dir needs a value" >&2; exit 2; }; _dir=$2; shift 2 ;;
        --pr)      [ $# -ge 2 ] || { echo "usage: --pr needs a value" >&2; exit 2; }; _pr=$2; shift 2 ;;
        --changed) [ $# -ge 2 ] || { echo "usage: --changed needs a value" >&2; exit 2; }; _cf=$2; shift 2 ;;
        --branch)  [ $# -ge 2 ] || { echo "usage: --branch needs a value" >&2; exit 2; }; _br=$2; shift 2 ;;
        --claims)  _cl=1; shift ;;
        *) echo "usage: backlog-presence.sh --dir <d> --pr <n> --changed <listing> [--branch <name>] [--claims]" >&2; exit 2 ;;
      esac
    done
    { [ -n "$_dir" ] && [ -n "$_pr" ] && [ -n "$_cf" ]; } || {
      echo "usage: backlog-presence.sh --dir <d> --pr <n> --changed <listing> [--branch <name>] [--claims]" >&2; exit 2; }
    check_pr "$_dir" "$_pr" "$_cf" "$_br" "$_cl"; exit $?
    ;;
  *)
    echo "usage: backlog-presence.sh --selftest | --dir <d> --pr <n> --changed <listing> [--branch <name>] [--claims]" >&2
    exit 2
    ;;
esac
