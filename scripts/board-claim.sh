#!/bin/sh
# board-claim.sh — entering In Progress is a FORGE-SERIALIZED claim, not a sentence
# (BOARD-CLAIM-MECHANISM; docs/architecture/2026-09-04-board-claim-mechanism-design.md).
#
# THE DEFECT THIS CLOSES. `DEVELOPMENT-PROCESS.md` §6/§12, `docs/work-tracking/adapters.md` and
# BACKLOG.md's own "How to use" all say entering In Progress is an ATOMIC ownership claim. For the
# BACKLOG.md backend the mechanism behind that sentence was: the row move is a commit on a feature
# branch, and git serializes two such commits at the SECOND SQUASH-MERGE — days after both sessions
# started, when the loser has already built. `conformance/backlog-current.sh` is offline by contract,
# so a second In Progress row on another branch is invisible to it. That is MERGE-TIME serialization
# described as claim-time serialization.
#
# THE MECHANISM. A claim is a git ref on the forge: `refs/claims/<ROW-ID>` on origin, pointing at a
# small ORPHAN commit whose single file `CLAIM` records `row`, `claimant`, `branch`, `claimed-at`.
# Creating it is one `git push origin <sha>:refs/claims/<ROW-ID>` WITHOUT a leading `+`. The forge's
# non-fast-forward rule is the server-side compare-and-swap: a second push of an UNRELATED commit is
# rejected, and this verb then reads the existing claim and names its holder. Release deletes the ref
# under a `--force-with-lease` old-value. Nothing touches a branch: no PR, no admin bypass, no
# branch-protection interaction, and hooks/pre-push returns 0 for every non-`refs/heads/*` ref.
#
#   sh scripts/board-claim.sh claim   <ROW-ID> [--branch <name>] [--links <text>] [--dry-run]
#                                              [--board-already-moved]
#   sh scripts/board-claim.sh release <ROW-ID> [--stale]
#   sh scripts/board-claim.sh check   [<ROW-ID> | --all]
#   sh scripts/board-claim.sh --selftest
#
# EXIT CODES (a silent 0 is never an answer here):
#   claim   : 0 claimed · 2 usage / bad row id / board refusal / REMOTE UNREACHABLE · 3 ALREADY CLAIMED
#   release : 0 released · 1 no claim to release / not the holder (without --stale) · 2 usage /
#             REMOTE UNREACHABLE
#   check   : 0 a claim exists · 1 no claim · 2 usage / REMOTE UNREACHABLE
#
# HONEST CEILING — read this before quoting the word "atomic" anywhere:
#   * The claim stops ACCIDENTAL double-work between cooperating sessions. An actor with push rights
#     OVERWRITES OR DELETES `refs/claims/*` AT WILL, and — MEASURED at fix round 1, not assumed —
#     `--force` is not even needed for the overwrite: a claim commit that is a CHILD of the existing
#     one is a fast-forward, so a plain push replaces the holder. A cooperating client refuses
#     (`fetch first`); an actor with push rights overwrites with or without `--force`. The refs are
#     unprotected today. WHETHER ANY OF THAT LEAVES A TRACE IS FORGE-DEPENDENT: on an organisation
#     with git-event audit logging the pusher is recorded; on a PERSONAL repository — which is what
#     this kit's own origin is — there is no git-event audit log and branch activity covers only
#     `refs/heads/*`, so a deleted claim ref leaves no trace at all. This is ONE TIER above merge-time
#     serialization and BELOW a server-enforced transition condition. A ruleset protecting
#     `refs/claims/**` (the `history-refs-immutable` shape) would raise it, and that is an owner
#     keystroke, named not done.
#   * Claimant identity is the claim commit's COMMITTER — self-set, forgeable, exactly like every
#     other `[committer]` label in the kit. This records identity; it does not authenticate it.
#   * The board move is MECHANICAL and lossy by schema: the Ready table carries nine columns and the
#     In Progress table four, so the moved row keeps its Item cell verbatim and takes Owner/Started/
#     Links from this verb. Intent, acceptance criteria, size, risk, type and success metric are NOT
#     carried across — the same loss a human move makes, made visibly and in one act. The verb does
#     NOT commit the edit; the slice's first commit carries it, and the reviewer reads the diff.
#   * A stale claim after an abandoned session is released by hand (`release --stale`) and is visible
#     in `check --all`. Nothing here proves the claimant is still working.
#
# POSIX sh; dash-clean (no `local`, no bashisms). Transaction discipline is COPIED, not reinvented,
# from scripts/promotion-verify.sh's `_pv_sync_in`: `git ls-remote --exit-code` is the probe that
# splits "absent" (rc 2) from "unreachable" (anything else), because a bare `git fetch` exits 128 for
# BOTH and its rc therefore cannot be read as an answer.
# What it changes: `claim` PUSHES a new ref `refs/claims/<ROW-ID>` to origin and REWRITES BACKLOG.md
#   in place (moving one row Ready -> In Progress, uncommitted); `release` DELETES that ref on origin
#   under a compare-and-swap old-value; `check` is read-only. Nothing else on the remote is touched —
#   no branch, no tag, no note.
# Guardrails: the row id is validated against `[A-Z0-9][A-Z0-9-]*` BEFORE it becomes a ref name and
#   before any network call, so `/`, `..`, whitespace, control bytes and lowercase are refused
#   offline; the push carries NO leading `+` (the forge's non-fast-forward rejection IS the
#   compare-and-swap); `release` uses `--force-with-lease=<ref>:<observed-sha>` so it can only ever
#   delete the claim it read, and refuses a claim held by someone else unless `--stale` is given
#   (naming the holder either way); a fetched `CLAIM` file is UNTRUSTED TEXT — parsed by fixed field
#   names, never `eval`'d, and sanitised with `tr -d '[:cntrl:]'` before it reaches a terminal; an
#   unreachable remote REFUSES (rc 2) and is never reported as "no claim"; the scratch ref every read
#   fetches into is PID-scoped, fetched `--depth=1`, and dropped by an EXIT trap; the CLAIM blob is
#   read through `head -c 4096` and a blob carrying no `claimant:` field inside that bound is REFUSED
#   as malformed rather than parsed into a holder sentence; and `claim` REFUSES to touch BACKLOG.md
#   at all when the project's `CLAUDE.md` declares a non-md backlog backend (S-L5).
set -eu

BC_REMOTE="${BOARD_CLAIM_REMOTE:-origin}"
BC_BOARD="${BOARD_CLAIM_BOARD:-BACKLOG.md}"

# The scratch ref a claim is READ through. PID-scoped for the same reason promotion-verify.sh's is:
# concurrency is the exact condition this tool exists to handle, so a fixed name would let two
# invocations fetch into and delete each other's scratch.
BC_SCRATCH="refs/kit/claim-scratch-$$"
bc_drop_scratch() { git update-ref -d "$BC_SCRATCH" >/dev/null 2>&1 || true; }
# S-L3 — the selftest's `mktemp -d` fixture tree is removed on EVERY exit path, not just the happy
# one. Each run builds a bare remote plus two clones; leaving them behind on the first failing leg is
# how a CI runner's disk fills up one red at a time (the disk-safety lesson, paid for once already).
# `bc_base` is only ever set by selftest(), so the guard is what keeps this trap a no-op for the verbs.
bc_cleanup() {
  bc_drop_scratch
  [ -n "${bc_base:-}" ] && rm -rf "$bc_base"
  return 0
}
trap 'bc_cleanup' EXIT INT TERM

bc_usage() {
  echo "usage:" >&2
  echo "  board-claim.sh claim   <ROW-ID> [--branch <name>] [--links <text>] [--dry-run] [--board-already-moved]" >&2
  echo "  board-claim.sh release <ROW-ID> [--stale]" >&2
  echo "  board-claim.sh check   [<ROW-ID> | --all]" >&2
  echo "  board-claim.sh --selftest" >&2
}

# ── ROW-ID GRAMMAR — THE FIRST THING THAT RUNS, BEFORE ANY NETWORK OR BOARD READ ────────────────
# The row id becomes a REF NAME (`refs/claims/<ROW-ID>`), so it is validated at the front door
# against the board's own backticked-identifier shape: an initial [A-Z0-9] then [A-Z0-9-]. That
# refuses `/` (ref escape), `..` (illegal ref component), whitespace, control bytes, `~^:?*[`,
# a leading `-` (option injection) and lowercase, offline, with no partially-composed refspec.
# ⚠️ THIS IS A DELIBERATE SECOND COPY of `conformance/backlog-lib.sh::row_id_ok`, for the reason
# the board-read block at :210-224 gives: this script must run before and independently of the
# conformance tree. The copy is GATED, not merely disclosed — `backlog-current.sh --selftest`'s
# `rid/twin` leg compares the two `case` bodies byte for byte and reds on any drift. Edit one, edit
# both, or that leg will say so.
bc_row_ok() {
  case "$1" in
    '')            return 1 ;;
    [!A-Z0-9]*)    return 1 ;;
    *[!A-Z0-9-]*)  return 1 ;;
  esac
  return 0
}
bc_require_row() {
  if bc_row_ok "$1"; then return 0; fi
  echo "board-claim: invalid row id '$(printf '%s' "$1" | tr -d '[:cntrl:]')' — a row id must match [A-Z0-9][A-Z0-9-]* (it becomes a ref name)." >&2
  return 2
}

# ── THE REMOTE PROBE — absent and unreachable are DIFFERENT ANSWERS ─────────────────────────────
# `git ls-remote --exit-code <remote> <ref>`: 0 = present · 2 = the remote ANSWERED and does not have
# it · anything else = the remote did not answer. `git fetch` exits 128 for both of the last two, so
# its rc cannot split them — the measured lesson from promotion-verify.sh's record transaction,
# reused rather than rediscovered. Echoes the claim's sha on rc 0.
bc_probe() { # <ref> -> stdout sha (when present); rc 0 present · 2 absent · 3 unreachable
  # ⚠️ `$?` IS CAPTURED IN THE `else` BRANCH, NEVER AFTER `fi`. POSIX gives an `if` with no
  # else-clause the status 0 when its condition FAILS, so `if cmd; then …; fi; rc=$?` reads 0 for a
  # command that just failed — every unreachable remote would have been reported as "present". The
  # same class (R-1) bit the previous slice; the shape below is the cure, and it is not optional.
  if _bc_out=$(git ls-remote --exit-code "$BC_REMOTE" "$1" 2>/dev/null); then
    printf '%s\n' "$_bc_out" | awk '{print $1; exit}'
    return 0
  else
    _bc_rc=$?
  fi
  if [ "$_bc_rc" = 2 ]; then return 2; fi
  return 3
}

bc_unreachable() { # <ref>
  echo "board-claim: cannot reach $BC_REMOTE — 'git ls-remote $BC_REMOTE $1' did not answer." >&2
  echo "             A claim decision taken against a remote this process cannot read is exactly the" >&2
  echo "             race this mechanism exists to end, so proceeding blind is REFUSED (rc 2)." >&2
}

# bc_read_claim <ref> -> print the CLAIM blob. The ref is fetched into the PID-scoped scratch (never
# forced: nothing may be discarded here) and dropped again immediately.
# ⚠️ BOUNDED, BECAUSE THE BLOB IS WRITTEN BY WHOEVER HELD THE REF (S-L4). `--depth=1` fetches the one
# orphan commit and nothing behind it, and the blob is SIZED BEFORE IT IS READ so a multi-megabyte
# `CLAIM` cannot be slurped into a shell variable by anyone with push rights. A blob that carries no
# `claimant:` field inside that bound is MALFORMED and is refused out loud — never parsed into a
# holder sentence, because "CLAIMED by  at  on " is a worse answer than a named refusal.
# ⚠️ AND THE SIZING IS ALSO THE EXISTENCE TEST, WHICH IS WHY IT IS `git cat-file -s` AND NOT A PIPE.
# Reviewer R-10 at fix round 2: this used to be `if _bc_txt=$(git show …:CLAIM | head -c N)`, whose
# status is HEAD's and never git's — `head` succeeds on an empty stream, so a claim ref carrying no
# CLAIM file at all took the `then` arm with an empty variable, the `else` arm was unreachable code,
# and the caller was told the blob was MALFORMED when the truth was that there was no blob at all.
# Two different broken states must not print the same sentence: the MISSING case now returns quietly
# (the caller says "unreadable") and only a PRESENT, fieldless blob is called MALFORMED.
# ⚠️ AND EVERY CALL SITE LETS THAT REFUSAL THROUGH: they used to read `$(bc_read_claim … 2>/dev/null)`,
# which swallowed the MALFORMED line and made "refused out loud" false. Leg (l) caught it.
BC_CLAIM_MAX_BYTES=4096
bc_read_claim() {
  bc_drop_scratch
  git fetch --no-tags --depth=1 "$BC_REMOTE" "$1:$BC_SCRATCH" >/dev/null 2>&1 || return 1
  if _bc_size=$(git cat-file -s "$BC_SCRATCH:CLAIM" 2>/dev/null); then
    :
  else
    bc_drop_scratch; return 1
  fi
  case "$_bc_size" in
    ''|*[!0-9]*) bc_drop_scratch; return 1 ;;
  esac
  if [ "$_bc_size" -gt "$BC_CLAIM_MAX_BYTES" ]; then
    bc_drop_scratch
    echo "board-claim: the CLAIM blob at $1 is $_bc_size bytes, past the $BC_CLAIM_MAX_BYTES-byte" >&2
    echo "             bound. Refusing to read a holder out of it." >&2
    return 1
  fi
  _bc_txt=$(git show "$BC_SCRATCH:CLAIM" 2>/dev/null)
  bc_drop_scratch
  case "$_bc_txt" in
    *"claimant: "*) ;;
    *)
      echo "board-claim: the CLAIM blob at $1 is MALFORMED — no 'claimant:' field in its first" >&2
      echo "             $BC_CLAIM_MAX_BYTES bytes. Refusing to read a holder out of it." >&2
      return 1 ;;
  esac
  printf '%s\n' "$_bc_txt"
  return 0
}

# bc_field <claim-text> <name> — read ONE field by FIXED NAME. The CLAIM file is untrusted text from
# a ref anyone with push rights can write, so it is never `eval`'d, never sourced, and every value is
# stripped of control bytes before it can reach a terminal.
bc_field() {
  printf '%s\n' "$1" | grep "^$2: " | head -1 | cut -d' ' -f2- | tr -d '[:cntrl:]'
}

# bc_holder_line <claim-text> — the one-line holder sentence every refusal prints.
bc_holder_line() {
  printf 'CLAIMED by %s at %s on %s\n' \
    "$(bc_field "$1" claimant)" "$(bc_field "$1" claimed-at)" "$(bc_field "$1" branch)"
}

# ── BOARD READS — A SECOND COPY OF backlog-lib.sh's PARSER, AND THE DRIFT IS UNGATED ────────────
# Say it plainly (reviewer R-4 at fix round 1 struck the sentence that used to sit here, which
# claimed this file read the board "through backlog-lib.sh's parser, never a second one" while the
# next thirty lines inlined a copy of it). What is duplicated: the section/fence semantics of
# `section_rows`, `cell` and `col_index`. WHY, and it is a real reason rather than a shrug: this
# script must run BEFORE and INDEPENDENTLY of the conformance tree — its own selftest drives it
# inside throwaway clones that carry a BACKLOG.md and nothing else, so sourcing a library that lives
# under `conformance/` would make the verb untestable in the only fixture that proves it. The
# `bc_row_line` copy is additionally EXTENDED (it returns the file line number the edit needs, which
# `section_rows` does not expose), so it could not be a call even from the repo root.
# ⚠️ THE COST, STATED: nothing greps these two implementations against each other. A change to
# backlog-lib.sh's fence handling or cell trimming does NOT red anything here. `backlog-presence.sh`
# carries the same disclosure about its own reuse boundary at its `inprogress_hints` note — CROSS-CITE
# `conformance/backlog-presence.sh:248`. Folding the three parsers into one gated library is a
# follow-up on the board, not a thing this slice did.
# bc_row_section <board> <ROW-ID> -> the section heading the row sits under, or empty.
bc_row_section() {
  for _bs in "Ready" "In Progress" "In Review" "Blocked" "Released" "Done"; do
    if [ -n "$(bc_row_line "$1" "$_bs" "$2")" ]; then printf '%s\n' "$_bs"; return 0; fi
  done
  return 0
}

# bc_row_line <board> <section> <ROW-ID> -> the 1-based FILE line number of that row, or empty.
# Same section/fence semantics as backlog-lib.sh's section_rows (fenced examples are documentation,
# not live rows), extended only with the line number the edit needs.
bc_row_line() {
  awk -F'|' -v sec="$2" -v want="$3" '
    /^[[:space:]]*```/ { infence = !infence; next }
    infence { next }
    $0 ~ "^## " sec "[[:space:]]*$" { inseg = 1; next }
    inseg && /^## / { inseg = 0 }
    inseg && /^[[:space:]]*\|/ {
      c = $2; gsub(/^[ \t]+|[ \t]+$/, "", c)
      if (match(c, /`[^`]+`/)) {
        id = substr(c, RSTART + 1, RLENGTH - 2)
        if (id == want) { print NR; exit }
      }
    }
  ' "$1"
}

# bc_section_bounds <board> <section> -> "<header-line> <last-row-line>" (0 0 when the table is absent).
bc_section_bounds() {
  awk -F'|' -v sec="$2" '
    /^[[:space:]]*```/ { infence = !infence; next }
    infence { next }
    $0 ~ "^## " sec "[[:space:]]*$" { inseg = 1; next }
    inseg && /^## / { inseg = 0 }
    inseg && /^[[:space:]]*\|/ { if (hdr == 0) hdr = NR; last = NR }
    END { print hdr + 0, last + 0 }
  ' "$1"
}

# bc_cell <row> <1-based index> — backlog-lib.sh's cell(), inlined so this script stays runnable from
# any cwd without sourcing a library that expects the repo root. Same awk, same trim.
bc_cell() { printf '%s' "$1" | awk -F'|' -v i="$2" '{v=$(i+1); gsub(/^[ \t]+|[ \t]+$/,"",v); print v}'; }

# bc_col_index <header-row> <column-name> -> the 1-based column index, or EMPTY when the table has no
# such column. backlog-lib.sh's col_index, inlined for the reason stated at the top of this block.
# This exists so nothing here ever greps a WHOLE ROW LINE for a value that belongs to one cell: an
# Item cell that happens to mention a branch name is not a Links cell that names it (reviewer R-2).
bc_col_index() {
  printf '%s' "$1" | awk -F'|' -v want="$2" '
    {
      for (i = 2; i <= NF; i++) {
        h = $i; gsub(/^[ \t]+|[ \t]+$/, "", h)
        if (h == want) { print i - 1; exit }
      }
    }'
}

# ── THE DECLARED BACKEND — `claim` EDITS BACKLOG.md, SO IT MUST NOT EDIT SOMEBODY ELSE'S BOARD ───
# S-L5. `claim`'s second half REWRITES BACKLOG.md in place. On a project whose CLAUDE.md declares
# `jira` (or any other hosted backend) a BACKLOG.md left in the tree is a STRAY — a template stub, an
# archived board, a merge leftover — and silently editing it would move a row on a board nobody reads
# while the real tracker says nothing. Refuse instead, and name what was declared.
# Same resolution SHAPE as conformance/backlog-lib.sh's `resolve_backend` (field-leading line, cut the
# annotation, lowercase, canonical token) — and it is a THIRD parse site, disclosed for the same
# reason and with the same ungated-drift caveat as the board parser above. It is not a call because
# this verb's own selftest runs it inside throwaway clones that carry no `conformance/` tree at all.
# UNDECLARED IS PERMISSIVE: no CLAUDE.md, no field, or an unfilled placeholder -> proceed. Only a
# RECOGNIZED non-md backend refuses; the gate's job is to catch a declared mismatch, not to require a
# declaration this verb never needed before.
bc_backend() { # <dir> -> md|github|jira|ado|linear|gitlab, or empty (undeclared)
  _bkc="$1/CLAUDE.md"
  [ -f "$_bkc" ] || return 0
  _bkl=$(grep -Ei '^[-*[:space:]]*\**backlog backend\**[^:]*:' "$_bkc" 2>/dev/null | head -1) || true
  [ -n "$_bkl" ] || return 0
  _bkv=${_bkl#*:}
  _bkv=$(printf '%s' "$_bkv" | sed 's/—.*$//; s/ (.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//' \
           | tr '[:upper:]' '[:lower:]')
  case "$_bkv" in
    '')                 return 0 ;;
    *'['*'/'*']'*)      return 0 ;;   # unfilled choice-list placeholder -> undeclared
    md|markdown)        printf 'md\n'; return 0 ;;
    *backlog.md*)       printf 'md\n'; return 0 ;;
  esac
  printf '%s' "$_bkv" | grep -Eo 'github|jira|ado|linear|gitlab' | head -1 || true
  return 0
}

# bc_new_row <target-header-row> <item-cell> <owner> <started> <links> — compose the In Progress row
# BY COLUMN NAME from the target table's own header, never by hardcoded position: a board whose
# schema gains a column must not silently shift every value one cell to the left.
bc_new_row() {
  printf '%s' "$1" | awk -F'|' -v item="$2" -v owner="$3" -v started="$4" -v links="$5" '
    {
      out = "|"
      for (i = 2; i < NF; i++) {
        h = $i; gsub(/^[ \t]+|[ \t]+$/, "", h)
        v = "—"
        if (h == "Item")    v = item
        if (h == "Owner")   v = owner
        if (h == "Started") v = started
        if (h == "Links")   v = links
        out = out " " v " |"
      }
      print out
    }'
}

# ── claim ───────────────────────────────────────────────────────────────────────────────────────
do_claim() {
  _row=""; _branch=""; _links=""; _dry=0; _moved=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --branch)              [ $# -ge 2 ] || { echo "claim: --branch needs a value" >&2; return 2; }; _branch=$2; shift 2 ;;
      --links)               [ $# -ge 2 ] || { echo "claim: --links needs a value" >&2; return 2; }; _links=$2; shift 2 ;;
      --dry-run)             _dry=1; shift ;;
      --board-already-moved) _moved=1; shift ;;
      -*)                    echo "claim: unknown option '$1'" >&2; bc_usage; return 2 ;;
      *)                     [ -z "$_row" ] || { echo "claim: one row id, not two" >&2; return 2; }; _row=$1; shift ;;
    esac
  done
  bc_require_row "$_row" || return 2
  _ref="refs/claims/$_row"

  [ -n "$_branch" ] || _branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "(detached)")

  # BOARD PRECONDITION — refuse before touching the network. `claim` is the act of ENTERING In
  # Progress, so the row must exist and sit in Ready. `--board-already-moved` is the ONE exception
  # and it is not a bypass: the row must ALREADY sit In Progress AND its Links cell must name this
  # exact branch. It exists because this mechanism's own first live claim is made from a branch whose
  # design commit moved the row before the verb existed to do it.
  if [ ! -f "$BC_BOARD" ]; then
    echo "claim: no board at $BC_BOARD (run from the project root, or set BOARD_CLAIM_BOARD)." >&2
    return 2
  fi
  # S-L5 — the declared backend gates the edit, and it gates it BEFORE the network for the same
  # reason the row grammar does: a refusal that has already pushed a ref is not a refusal.
  _bkdir=$(dirname -- "$BC_BOARD")
  _bktok=$(bc_backend "$_bkdir")
  if [ -n "$_bktok" ] && [ "$_bktok" != md ]; then
    echo "claim: this project declares backlog backend '$_bktok', not BACKLOG.md — REFUSED." >&2
    echo "       \`claim\` rewrites $BC_BOARD in place, and a BACKLOG.md sitting beside a '$_bktok'" >&2
    echo "       tracker is a stray file, not the board anyone reads. Claim the item in '$_bktok'." >&2
    return 2
  fi
  _sec=$(bc_row_section "$BC_BOARD" "$_row")
  if [ "$_moved" = 1 ]; then
    if [ "$_sec" != "In Progress" ]; then
      echo "claim: --board-already-moved was given but \`$_row\` sits in '${_sec:-no section}', not In Progress." >&2
      return 2
    fi
    # R-1/R-2 — THE LINKS CELL, PARSED BY COLUMN. This was a whole-line `grep -Fq` with NO leg: the
    # reviewer's `if false` mutant left the suite 68/68 green, and an Item cell that merely MENTIONED
    # the branch satisfied it. The column index comes from the In Progress table's OWN header, so a
    # board whose schema gains a column does not shift the check onto a neighbouring cell.
    _ipline=$(bc_row_line "$BC_BOARD" "In Progress" "$_row")
    _ipbounds=$(bc_section_bounds "$BC_BOARD" "In Progress")
    _iphdrline=${_ipbounds% *}
    _iphdrtxt=$(awk -v n="$_iphdrline" 'NR==n' "$BC_BOARD")
    _iplinkcol=$(bc_col_index "$_iphdrtxt" "Links")
    if [ -z "$_iplinkcol" ]; then
      echo "claim: --board-already-moved was given but the In Progress table on $BC_BOARD has no \`Links\` column to read the branch out of." >&2
      return 2
    fi
    _iprowtxt=$(awk -v n="$_ipline" 'NR==n' "$BC_BOARD")
    _iplinks=$(bc_cell "$_iprowtxt" "$_iplinkcol")
    # R-11 — ANCHORED ON THE CANONICAL FORM THE VERB ITSELF WRITES, `` branch `<name>` ``, and not on
    # a bare substring. A substring match makes every branch a prefix-match of its own descendants:
    # a Links cell naming `feat/x-2` satisfied `--branch feat/x`, so the flag bound the claim to a
    # DIFFERENT branch than the one the board records. The backticks are the delimiters, so the match
    # is exact at both ends without the check having to know the rest of the cell's punctuation.
    case "$_iplinks" in
      *'branch `'"$_branch"'`'*) ;;
      *)
        echo "claim: --board-already-moved was given but the In Progress \`Links\` cell for \`$_row\` does not name branch \`$_branch\` in the canonical form (branch \`<name>\`) (Links = [$_iplinks])." >&2
        echo "       Only the Links cell counts: a branch named in the Item cell is prose, not a binding." >&2
        return 2 ;;
    esac
  else
    if [ -z "$_sec" ]; then
      echo "claim: no row \`$_row\` on $BC_BOARD — a claim binds to a board row, and there is none." >&2
      return 2
    fi
    if [ "$_sec" != "Ready" ]; then
      echo "claim: row \`$_row\` sits in '$_sec', not Ready — only a Ready row can be claimed into In Progress." >&2
      return 2
    fi
  fi

  # IDENTITY IS RESOLVED BEFORE THE PROBE, not after it. It is an offline precondition (a missing
  # git identity refuses without a network round-trip), and — the reason it MOVED here at fix round 1
  # — the refusal branch below cannot tell "held by someone else" from "held by ME" without it.
  _name=$(git config user.name  2>/dev/null || true)
  _email=$(git config user.email 2>/dev/null || true)
  if [ -z "$_name" ] || [ -z "$_email" ]; then
    echo "claim: no git identity (user.name / user.email) — the claim's committer IS the claimant." >&2
    return 2
  fi
  _me="$_name <$_email>"
  _when=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # THE FORGE PROBE. Present -> someone holds it; absent -> proceed; no answer -> refuse.
  if _held=$(bc_probe "$_ref"); then
    _txt=$(bc_read_claim "$_ref" || true)
    # ── SELF-CLAIM IS A RESUME, NOT A COLLISION (reviewer R-5) ──────────────────────────────────
    # Re-running `claim` for a row THIS identity already holds ON THIS BRANCH used to be refused as
    # foreign — so the documented recovery from a partial failure (ref pushed, board edit lost) was
    # to release your own live claim and re-take it, which is the one operation this mechanism exists
    # to make dangerous. Both halves must match: a different branch under the same name is a second
    # session belonging to the same human, and that IS the double-claim.
    if [ -n "$_txt" ] \
       && [ "$(bc_field "$_txt" claimant)" = "$_me" ] \
       && [ "$(bc_field "$_txt" branch)" = "$_branch" ]; then
      echo "claim: held by you since $(bc_field "$_txt" claimed-at) — \`$_row\` on branch '$_branch' ($_held)."
      echo "       Nothing pushed, board NOT edited. This is the resume path, not a new claim."
      return 0
    fi
    if [ -n "$_txt" ]; then
      echo "claim: $(bc_holder_line "$_txt")" >&2
    else
      echo "claim: $_ref exists on $BC_REMOTE at $_held but its CLAIM could not be read." >&2
    fi
    echo "       Row \`$_row\` is ALREADY CLAIMED. Release it (\`board-claim.sh release $_row --stale\`) or take another row." >&2
    return 3
  else
    _prc=$?
    if [ "$_prc" != 2 ]; then bc_unreachable "$_ref"; return 2; fi
  fi

  if [ "$_dry" = 1 ]; then
    echo "claim: DRY RUN — would push a claim on $_ref as '$_name <$_email>' from branch '$_branch' at $_when; board untouched."
    return 0
  fi

  # THE ORPHAN CLAIM COMMIT — built with plumbing, so no checkout, no index and no working tree is
  # disturbed. hash-object -> mktree -> commit-tree, exactly three objects.
  _blob=$(printf 'row: %s\nclaimant: %s <%s>\nbranch: %s\nclaimed-at: %s\n' \
            "$_row" "$_name" "$_email" "$_branch" "$_when" | git hash-object -w --stdin)
  _tree=$(printf '100644 blob %s\tCLAIM\n' "$_blob" | git mktree)
  _commit=$(printf 'claim %s\n' "$_row" | git commit-tree "$_tree")

  # NO LEADING '+'. The forge's non-fast-forward rejection is the SERVER-SIDE COMPARE-AND-SWAP that
  # makes this a claim rather than a note; a forced refspec would overwrite the very thing being
  # checked and turn the last writer into the winner.
  if ! git push "$BC_REMOTE" "$_commit:$_ref" >/dev/null 2>&1; then
    # Rejected. Either someone claimed it between the probe and the push (the race this exists for),
    # or the push itself failed. Read the ref and say which.
    _txt=$(bc_read_claim "$_ref" || true)
    if [ -n "$_txt" ]; then
      echo "claim: $(bc_holder_line "$_txt")" >&2
      echo "       The push was REJECTED (non-fast-forward): row \`$_row\` was claimed between this" >&2
      echo "       process's probe and its push. That rejection is the mechanism working." >&2
      return 3
    fi
    echo "claim: pushing $_ref to $BC_REMOTE failed and no claim could be read back. Nothing was moved." >&2
    return 2
  fi
  echo "claim: OK — \`$_row\` claimed on $BC_REMOTE as $_ref ($_commit)"
  echo "       claimant '$_name <$_email>' · branch '$_branch' · at $_when"

  if [ "$_moved" = 1 ]; then
    echo "claim: board NOT edited — --board-already-moved: \`$_row\` already sits In Progress naming '$_branch'."
    return 0
  fi

  # ── THE ROW MOVE (design fold 1: claim and row move are ONE act, never two that can diverge) ──
  _rline=$(bc_row_line "$BC_BOARD" "Ready" "$_row")
  _rowtxt=$(awk -v n="$_rline" 'NR==n' "$BC_BOARD")
  _item=$(bc_cell "$_rowtxt" 1)
  _bounds=$(bc_section_bounds "$BC_BOARD" "In Progress")
  _iphdr=${_bounds% *}; _iplast=${_bounds#* }
  if [ "$_iphdr" = 0 ]; then
    echo "claim: the claim ref is PUSHED, but $BC_BOARD has no In Progress table to move the row into." >&2
    echo "       Move the row by hand, or release the claim (\`board-claim.sh release $_row\`)." >&2
    return 2
  fi
  _hdrtxt=$(awk -v n="$_iphdr" 'NR==n' "$BC_BOARD")
  # ── THE LINKS CELL NAMES THE BRANCH, ALWAYS (reviewer R-5) ─────────────────────────────────────
  # As first built this wrote `N/A — claimed; design link follows` and nothing else, so the verb's own
  # output FAILED its own `--board-already-moved` precondition: re-running claim on a row this verb had
  # just moved was refused because the Links cell named no branch. The branch is now written first and
  # unconditionally, and any `--links` value is appended after it rather than replacing it.
  if [ -n "$_links" ]; then
    _links="branch \`$_branch\` · $_links"
  else
    _links="branch \`$_branch\` · N/A — claimed; design link follows"
  fi
  _new=$(bc_new_row "$_hdrtxt" "$_item" "$_name" "$(date -u +%Y-%m-%d)" "$_links")

  _tmp="$BC_BOARD.board-claim.$$"
  awk -v del="$_rline" -v ins="$_iplast" -v newrow="$_new" '
    NR == del { next }
    { print }
    NR == ins { print newrow }
  ' "$BC_BOARD" > "$_tmp" && mv "$_tmp" "$BC_BOARD"

  echo "claim: board edited (UNCOMMITTED — the slice's first commit carries it):"
  echo "-$_rowtxt"
  echo "+$_new"
  return 0
}

# ── release ─────────────────────────────────────────────────────────────────────────────────────
do_release() {
  _row=""; _stale=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --stale) _stale=1; shift ;;
      -*)      echo "release: unknown option '$1'" >&2; bc_usage; return 2 ;;
      *)       [ -z "$_row" ] || { echo "release: one row id, not two" >&2; return 2; }; _row=$1; shift ;;
    esac
  done
  bc_require_row "$_row" || return 2
  _ref="refs/claims/$_row"

  if _sha=$(bc_probe "$_ref"); then
    :
  else
    _prc=$?
    if [ "$_prc" = 2 ]; then
      echo "release: no claim on \`$_row\` at $BC_REMOTE ($_ref does not exist) — nothing to release." >&2
      return 1
    fi
    bc_unreachable "$_ref"; return 2
  fi

  _txt=$(bc_read_claim "$_ref" || true)
  _holder=$(bc_field "$_txt" claimant)
  _name=$(git config user.name 2>/dev/null || true)
  _email=$(git config user.email 2>/dev/null || true)
  _me="$_name <$_email>"
  # THE SAME SPLIT do_claim MAKES (reviewer R-12). An unreadable or malformed CLAIM yields an EMPTY
  # `_holder`, and an empty holder must never be dressed up as one: "is held by ''" is a pair of
  # quotes standing in for a fact nobody has. Unreadable is its own refusal, named as such — and it
  # is still a refusal, because a claim that cannot be proven to be yours is not yours.
  if [ -n "$_txt" ]; then
    echo "release: $(bc_holder_line "$_txt")"
    if [ "$_holder" != "$_me" ] && [ "$_stale" != 1 ]; then
      echo "release: REFUSED — \`$_row\` is held by '$_holder', not by you ('$_me')." >&2
      echo "         Releasing another session's live claim is a deliberate act: pass --stale, and say why." >&2
      return 1
    fi
  else
    echo "release: $_ref exists on $BC_REMOTE at $_sha but its CLAIM is unreadable or malformed."
    if [ "$_stale" != 1 ]; then
      echo "release: REFUSED — \`$_row\` carries a claim whose holder cannot be read, so it cannot be" >&2
      echo "         shown to be yours ('$_me'). Deleting it is a deliberate act: pass --stale, and say why." >&2
      return 1
    fi
  fi

  # COMPARE-AND-SWAP ON THE DELETE. The lease's old-value is the sha this process OBSERVED, so a
  # claim that moved between the read and the delete is left ALONE — the delete can only ever remove
  # the exact claim that was inspected, never a newer one someone else has since taken.
  if git push "$BC_REMOTE" --force-with-lease="$_ref:$_sha" ":$_ref" >/dev/null 2>&1; then
    echo "release: OK — $_ref deleted on $BC_REMOTE (was $_sha)"
    return 0
  fi
  echo "release: FAILED — could not delete $_ref at $BC_REMOTE (the lease on $_sha did not hold, or the push was refused)." >&2
  return 1
}

# ── check ───────────────────────────────────────────────────────────────────────────────────────
do_check() {
  _all=0; _row=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --all) _all=1; shift ;;
      -*)    echo "check: unknown option '$1'" >&2; bc_usage; return 2 ;;
      *)     [ -z "$_row" ] || { echo "check: one row id, not two" >&2; return 2; }; _row=$1; shift ;;
    esac
  done
  if [ "$_all" = 1 ]; then
    if _out=$(git ls-remote "$BC_REMOTE" 'refs/claims/*' 2>/dev/null); then :; else
      bc_unreachable 'refs/claims/*'; return 2
    fi
    if [ -z "$_out" ]; then echo "check: no claims on $BC_REMOTE"; return 1; fi
    _n=0
    # A TEMP FILE, NOT A PIPE: POSIX runs a pipeline's `while` body in a SUBSHELL, so the counter
    # would come back zero. mktemp, NOT a predictable /tmp/<name>.$$ — a guessable path in a
    # world-writable directory is a symlink-swap surface, and this tool is control-plane.
    # `IFS= read` is command-scoped — never a global IFS assignment (semgrep: ifs-tampering).
    _reflist=$(mktemp)
    printf '%s\n' "$_out" | awk '{print $2}' > "$_reflist"
    while IFS= read -r _r; do
      [ -n "$_r" ] || continue
      _n=$((_n + 1))
      _t=$(bc_read_claim "$_r" || true)
      if [ -n "$_t" ]; then
        printf 'check: %s — %s\n' "$_r" "$(bc_holder_line "$_t")"
      else
        printf 'check: %s — (claim present; CLAIM unreadable)\n' "$_r"
      fi
    done < "$_reflist"
    rm -f "$_reflist"
    echo "check: $_n claim(s) on $BC_REMOTE"
    return 0
  fi
  [ -n "$_row" ] || { echo "check: a row id or --all is required" >&2; bc_usage; return 2; }
  bc_require_row "$_row" || return 2
  _ref="refs/claims/$_row"
  # Same `else`-branch rc capture as bc_probe — see the R-1 note there.
  if _sha=$(bc_probe "$_ref"); then
    _txt=$(bc_read_claim "$_ref" || true)
    if [ -n "$_txt" ]; then
      echo "check: $(bc_holder_line "$_txt") ($_sha)"
      # ── THE MACHINE-READABLE FACE, and it exists for exactly one consumer.
      # conformance/backlog-presence.sh's `--claims` arm has to compare the claim's BRANCH with the
      # PR's head branch. Parsing the human sentence for it would make a prose line a contract; these
      # three fixed-name lines are the contract instead. Values are already control-byte-stripped by
      # bc_field. ⚠️ CROSS-CITE: backlog-presence.sh greps `^claim-branch: ` — change one, read the other.
      printf 'claim-holder: %s\n' "$(bc_field "$_txt" claimant)"
      printf 'claim-branch: %s\n' "$(bc_field "$_txt" branch)"
      printf 'claim-at: %s\n'     "$(bc_field "$_txt" claimed-at)"
    else
      echo "check: $_ref exists at $_sha (CLAIM unreadable)"
    fi
    return 0
  else
    _prc=$?
  fi
  if [ "$_prc" = 2 ]; then echo "check: no claim on \`$_row\` ($_ref absent from $BC_REMOTE)"; return 1; fi
  bc_unreachable "$_ref"; return 2
}

# ── ORACLE MARKER: selftest() and everything below is the non-vacuity oracle region. ─────────────
selftest() {
  bc_st_fail=0
  bc_base=$(mktemp -d)
  # HERMETIC BY CONSTRUCTION (conformance/selftest-hermetic.sh face (a)): no global/system git config
  # is read, HOME is inside the workdir, and every identity is set locally per clone. Real pushes to a
  # real bare remote — no simulation.
  # ⚠️ NO INITIAL-BRANCH PIN, AND NONE IS NEEDED — the prose here used to claim one and there was no
  # `-b` anywhere (security S-L2). Nothing below reads or asserts a branch NAME: the fixtures push and
  # read `refs/claims/*` only, and the `branch:` field in a CLAIM is whatever `--branch` was given.
  # `init.defaultBranch` therefore cannot change a verdict, and a claim that it is pinned would be the
  # kind of unearned hermeticity assertion this comment block exists to make checkable.
  HOME="$bc_base/home"; mkdir -p "$HOME"
  export HOME
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
  unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL 2>/dev/null || true

  bc_remote_dir="$bc_base/remote.git"
  git init -q --bare "$bc_remote_dir"
  bc_mkclone A "Session A" a@example.com
  bc_mkclone B "Session B" b@example.com

  # ---- leg (a): A claims a Ready row -> ref exists AND the board row moved with Owner/Started ----
  bc_run "$bc_base/A" claim ROW-1 --branch feat/a --links 'design docs/x.md'
  bc_expect_rc 0 "leg a/claim: A claims a Ready row -> rc 0"
  bc_has "leg a/claim: the OK line names the ref" "refs/claims/ROW-1"
  if git --git-dir="$bc_remote_dir" rev-parse --verify -q refs/claims/ROW-1 >/dev/null; then
    bc_pass "leg a/ref: refs/claims/ROW-1 EXISTS on the bare remote (a real push, not a simulation)"
  else
    bc_fail "leg a/ref: refs/claims/ROW-1 absent from the remote after a claimed rc 0"
  fi
  bc_board="$bc_base/A/BACKLOG.md"
  if bc_ip_row=$(awk '/^## In Progress/{s=1;next} s&&/^## /{exit} s&&/`ROW-1`/{print}' "$bc_board") \
     && [ -n "$bc_ip_row" ]; then
    bc_pass "leg a/row-moved: \`ROW-1\` now sits under ## In Progress"
  else
    bc_fail "leg a/row-moved: \`ROW-1\` is not under ## In Progress after a successful claim"
  fi
  case "$bc_ip_row" in
    *"Session A"*) bc_pass "leg a/owner: the moved row's Owner cell names the claimant" ;;
    *) bc_fail "leg a/owner: Owner cell does not name the claimant; row=[$bc_ip_row]" ;;
  esac
  case "$bc_ip_row" in
    *"$(date -u +%Y-%m-%d)"*) bc_pass "leg a/started: the moved row's Started cell carries today's date" ;;
    *) bc_fail "leg a/started: Started cell carries no date; row=[$bc_ip_row]" ;;
  esac
  case "$bc_ip_row" in
    *"design docs/x.md"*) bc_pass "leg a/links: the moved row's Links cell carries --links verbatim" ;;
    *) bc_fail "leg a/links: Links cell lost the --links value; row=[$bc_ip_row]" ;;
  esac
  # R-5 — THE VERB'S OWN OUTPUT MUST SATISFY THE VERB'S OWN RESUME PRECONDITION. Without the branch
  # in Links, re-running claim with --board-already-moved on a row this verb had just moved is refused.
  case "$bc_ip_row" in
    *"feat/a"*) bc_pass "leg a/links-branch: the moved row's Links cell NAMES the claiming branch" ;;
    *) bc_fail "leg a/links-branch: Links cell does not name branch feat/a; row=[$bc_ip_row]" ;;
  esac
  if awk '/^## Ready/{s=1;next} s&&/^## /{exit} s&&/`ROW-1`/{f=1} END{exit !f}' "$bc_board"; then
    bc_fail "leg a/ready-cleared: \`ROW-1\` is STILL under ## Ready — the move duplicated the row"
  else
    bc_pass "leg a/ready-cleared: \`ROW-1\` is gone from ## Ready (moved, not copied)"
  fi

  # ---- leg (b): a SECOND claimant is refused, rc 3, NAMING the holder's identity and time -------
  bc_run "$bc_base/B" claim ROW-1 --branch feat/b
  bc_expect_rc 3 "leg b/second-claimant: B claims a held row -> rc 3 (ALREADY CLAIMED)"
  bc_has "leg b/second-claimant: the refusal NAMES the first claimant" "Session A <a@example.com>"
  bc_has "leg b/second-claimant: the refusal carries the claim TIME" "at 20"
  bc_has "leg b/second-claimant: the refusal names A's BRANCH" "on feat/a"
  if awk '/^## In Progress/{s=1;next} s&&/^## /{exit} s&&/`ROW-1`/{f=1} END{exit !f}' "$bc_base/B/BACKLOG.md"; then
    bc_fail "leg b/no-board-edit: B's board was edited despite the refusal"
  else
    bc_pass "leg b/no-board-edit: B's board is UNTOUCHED by the refused claim"
  fi

  # ---- leg (c): release refuses a non-holder; the holder releases; B can then claim -------------
  bc_run "$bc_base/B" release ROW-1
  bc_expect_rc 1 "leg c/non-holder: B releases A's claim without --stale -> rc 1 (refused)"
  bc_has "leg c/non-holder: the refusal NAMES the holder" "held by 'Session A <a@example.com>'"
  if git --git-dir="$bc_remote_dir" rev-parse --verify -q refs/claims/ROW-1 >/dev/null; then
    bc_pass "leg c/non-holder-noop: the refused release did NOT delete the ref"
  else
    bc_fail "leg c/non-holder-noop: the refused release deleted the ref anyway"
  fi
  bc_run "$bc_base/A" release ROW-1
  bc_expect_rc 0 "leg c/holder: A (the holder) releases -> rc 0"
  if git --git-dir="$bc_remote_dir" rev-parse --verify -q refs/claims/ROW-1 >/dev/null; then
    bc_fail "leg c/holder-deleted: refs/claims/ROW-1 survived the holder's release"
  else
    bc_pass "leg c/holder-deleted: refs/claims/ROW-1 is GONE from the remote"
  fi
  bc_run "$bc_base/B" claim ROW-1 --branch feat/b
  bc_expect_rc 0 "leg c/reclaim: B claims the released row -> rc 0"
  bc_run "$bc_base/A" release ROW-1 --stale
  bc_expect_rc 0 "leg c/stale: --stale lets a non-holder release B's claim -> rc 0"
  bc_has "leg c/stale: the --stale release still NAMES the holder it removed" "Session B <b@example.com>"

  # ---- leg (d): check --all lists holders; an UNREACHABLE remote is rc 2, never a silent 0 ------
  bc_run "$bc_base/A" claim ROW-2 --branch feat/a
  bc_expect_rc 0 "leg d/setup: A claims ROW-2 for the check legs"
  bc_run "$bc_base/A" check --all
  bc_expect_rc 0 "leg d/all: check --all with one live claim -> rc 0"
  bc_has "leg d/all: check --all names the ref" "refs/claims/ROW-2"
  bc_has "leg d/all: check --all names the holder" "Session A <a@example.com>"
  bc_run "$bc_base/A" check ROW-2
  bc_expect_rc 0 "leg d/one-present: check <ROW> on a held row -> rc 0"
  bc_run "$bc_base/A" check ROW-9
  bc_expect_rc 1 "leg d/one-absent: check <ROW> with no claim -> rc 1 (absent), never 0"
  bc_has "leg d/one-absent: the absent verdict says so plainly" "no claim on"
  # THE LOAD-BEARING NEGATIVE: origin points at a path that does not exist. A gate that reads
  # "unreachable" as "absent" would hand out a claim on a remote it cannot see — the exact race this
  # mechanism exists to end. Every verb must refuse, and none may return 0.
  bc_run_badremote "$bc_base/A" check ROW-2
  bc_expect_rc 2 "leg d/unreachable-check: an unreachable remote -> rc 2 (NOT 0, NOT 1/absent)"
  bc_has "leg d/unreachable-check: the refusal names the unreachable remote" "cannot reach"
  bc_run_badremote "$bc_base/A" check --all
  bc_expect_rc 2 "leg d/unreachable-all: check --all on an unreachable remote -> rc 2"
  # …from clone B, whose board still carries ROW-2 in Ready: the board precondition PASSES there, so
  # the refusal that follows is unambiguously the REMOTE one and not the board one.
  bc_run_badremote "$bc_base/B" claim ROW-2 --branch feat/b
  bc_expect_rc 2 "leg d/unreachable-claim: claim on an unreachable remote -> rc 2 (refuses blind)"
  bc_has "leg d/unreachable-claim: the claim refusal says proceeding blind is refused" "proceeding blind is REFUSED"
  bc_run_badremote "$bc_base/A" release ROW-2
  bc_expect_rc 2 "leg d/unreachable-release: release on an unreachable remote -> rc 2, never 'nothing to release'"

  # ---- leg (e): the row-id grammar refuses BEFORE any network -----------------------------------
  # Each of these runs against the BAD remote. If the grammar ran after the probe the verdict would
  # be the unreachable refusal; asserting the GRAMMAR token proves the order.
  # `-ROW` is refused one step EARLIER, by the option parser, and that is the correct refusal for an
  # option-injection shape — so it asserts ITS OWN token rather than being folded into the grammar
  # message. Both refusals are offline; neither reaches a refspec.
  for bc_pair in 'refs/heads/x|GRAMMAR' '../evil|GRAMMAR' 'ROW 1|GRAMMAR' 'row-1|GRAMMAR' \
                 'ROW~1|GRAMMAR' 'ROW:1|GRAMMAR' 'ROW*|GRAMMAR' '|GRAMMAR' '-ROW|OPTION' ; do
    bc_bad=${bc_pair%|*}; bc_kind=${bc_pair##*|}
    bc_run_badremote "$bc_base/A" claim "$bc_bad"
    bc_expect_rc 2 "leg e/grammar: claim '$bc_bad' -> rc 2"
    if [ "$bc_kind" = GRAMMAR ]; then
      bc_has "leg e/grammar: '$bc_bad' is refused BY GRAMMAR, before any network" "must match [A-Z0-9][A-Z0-9-]*"
    else
      bc_has "leg e/grammar: '$bc_bad' is refused as an OPTION, before any network" "unknown option"
    fi
    bc_hasnt "leg e/grammar: '$bc_bad' never reached the remote (no unreachable message)" "cannot reach"
  done

  # ---- leg (f): a row that is not in Ready cannot be claimed ------------------------------------
  bc_run "$bc_base/B" claim ROW-DONE --branch feat/b
  bc_expect_rc 2 "leg f/not-ready: a row sitting in Done -> rc 2 (refused)"
  bc_has "leg f/not-ready: the refusal names the section the row actually sits in" "sits in 'Done', not Ready"
  bc_run "$bc_base/B" claim ROW-NOPE --branch feat/b
  bc_expect_rc 2 "leg f/no-row: a row id that is on no board row at all -> rc 2"
  bc_has "leg f/no-row: the refusal says the claim binds to a board row" "a claim binds to a board row"
  if git --git-dir="$bc_remote_dir" rev-parse --verify -q refs/claims/ROW-DONE >/dev/null; then
    bc_fail "leg f/no-push: a board-refused claim PUSHED a ref anyway"
  else
    bc_pass "leg f/no-push: a board-refused claim pushed NOTHING (the board check precedes the network)"
  fi
  # --board-already-moved: allowed ONLY when the row already sits In Progress naming this branch.
  bc_run "$bc_base/B" claim ROW-DONE --branch feat/b --board-already-moved
  bc_expect_rc 2 "leg f/already-moved-wrong-section: --board-already-moved on a Done row -> rc 2"
  bc_has "leg f/already-moved-wrong-section: the refusal names the section" "not In Progress"

  # ---- leg (h): --board-already-moved READS THE LINKS CELL, BY COLUMN (reviewer R-1 + R-2) -------
  # R-1: as first built this branch check had NO leg at all — the reviewer's `if false` mutant left
  # the suite 68/68 green, which is to say the flag's whole safety property was unasserted.
  # R-2: and the check greped the WHOLE ROW LINE, so a branch name that happened to appear in the
  # ITEM cell satisfied a precondition that is about the LINKS cell. h1 is exactly that shape: the
  # Item cell says `feat/x`, the Links cell says `—`. It must be REFUSED.
  bc_fixture_board_moved "$bc_base/B/BACKLOG.md" '(picked up on feat/x)' '—'
  bc_run "$bc_base/B" claim ROW-MOVED --branch feat/x --board-already-moved
  bc_expect_rc 2 "leg h/links-not-item: Item cell mentions 'feat/x', Links is '—' -> rc 2 (refused)"
  bc_has "leg h/links-not-item: the refusal says the LINKS cell does not name the branch" "does not name branch"
  bc_has "leg h/links-not-item: the refusal prints the Links cell it actually read" "Links = [—]"
  if git --git-dir="$bc_remote_dir" rev-parse --verify -q refs/claims/ROW-MOVED >/dev/null; then
    bc_fail "leg h/no-push: a Links-refused --board-already-moved claim PUSHED a ref anyway"
  else
    bc_pass "leg h/no-push: the Links refusal precedes the network — nothing was pushed"
  fi
  # h2 — THE LIVENESS ANCHOR. Without it every leg above passes on a flag that always refuses.
  bc_fixture_board_moved "$bc_base/B/BACKLOG.md" '' 'branch `feat/x` · design docs/y.md'
  bc_run "$bc_base/B" claim ROW-MOVED --branch feat/x --board-already-moved
  bc_expect_rc 0 "leg h/links-names-branch: the Links cell names 'feat/x' -> rc 0 (claimed)"
  bc_has "leg h/links-names-branch: the board is explicitly NOT edited" "board NOT edited"

  # ---- leg (i): RE-CLAIMING A ROW YOU ALREADY HOLD IS A RESUME, NOT A COLLISION (R-5) ------------
  # B holds ROW-MOVED on feat/x from h2. The same identity on the same branch must be told so and
  # get rc 0; the same identity on a DIFFERENT branch is a second session and is still rc 3.
  bc_run "$bc_base/B" claim ROW-MOVED --branch feat/x --board-already-moved
  bc_expect_rc 0 "leg i/self-resume: re-claiming your own row on your own branch -> rc 0, not refused"
  bc_has "leg i/self-resume: the verdict says the claim is already yours" "held by you since"
  bc_has "leg i/self-resume: it says plainly that nothing was pushed" "Nothing pushed"
  # ⚠️ THIS LEG GRADES THE LINKS PRECONDITION, NOT THE SELF-CLAIM DISCRIMINATION — reviewer R-9 at
  # fix round 2. It used to be named `leg i/self-other-branch` and was read as the assertion that a
  # different branch under the same identity is refused; it is not. `--board-already-moved` with
  # `--branch feat/other` is refused at the Links-cell precondition ABOVE, before the probe ever
  # runs, which is why its rc is 2 and not 3. The rc and the sentence now agree. The discrimination
  # itself is graded by leg (k) below, which reaches the probe.
  bc_run "$bc_base/B" claim ROW-MOVED --branch feat/other --board-already-moved
  bc_expect_rc 2 "leg i/other-branch-links-precondition: --board-already-moved naming a branch the Links cell does not carry -> rc 2, at the board precondition"
  bc_has "leg i/other-branch-links-precondition: it is the LINKS refusal that fires, not a claim verdict" "does not name branch"
  # R-11 — and the Links match is ANCHORED: a cell naming a DESCENDANT branch (`feat/x-2`) must not
  # satisfy `--branch feat/x`. Under the old substring match this claimed rc 0 against the wrong row.
  bc_fixture_board_moved "$bc_base/B/BACKLOG.md" '' 'branch `feat/x-2` · design docs/y.md'
  bc_run "$bc_base/B" claim ROW-MOVED --branch feat/x --board-already-moved
  bc_expect_rc 2 "leg i/links-prefix: a Links cell naming branch \`feat/x-2\` does NOT satisfy --branch feat/x -> rc 2"
  bc_has "leg i/links-prefix: the refusal names the canonical form it wanted" "in the canonical form"
  bc_run "$bc_base/B" release ROW-MOVED
  bc_expect_rc 0 "leg i/cleanup: the holder releases ROW-MOVED"

  # ---- leg (j): the verb REFUSES to edit BACKLOG.md when it is not the declared backend (S-L5) ---
  # A hosted-tracker project with a stray BACKLOG.md in the tree: editing it would move a row on a
  # board nobody reads while the real tracker says nothing. The refusal is OFFLINE and BEFORE the push.
  bc_fixture_board "$bc_base/B/BACKLOG.md"
  printf '# Fixture project\n\n- **Backlog backend**: Jira (project KIT)\n' > "$bc_base/B/CLAUDE.md"
  bc_run "$bc_base/B" claim ROW-1 --branch feat/b
  bc_expect_rc 2 "leg j/foreign-backend: CLAUDE.md declares jira + a stray BACKLOG.md -> rc 2"
  bc_has "leg j/foreign-backend: the refusal names the DECLARED backend" "declares backlog backend 'jira'"
  if git --git-dir="$bc_remote_dir" rev-parse --verify -q refs/claims/ROW-1 >/dev/null; then
    bc_fail "leg j/no-push: a backend-refused claim PUSHED a ref anyway (the refusal must precede the network)"
  else
    bc_pass "leg j/no-push: the backend refusal is OFFLINE — nothing was pushed"
  fi
  if awk '/^## Ready/{s=1;next} s&&/^## /{exit} s&&/`ROW-1`/{f=1} END{exit !f}' "$bc_base/B/BACKLOG.md"; then
    bc_pass "leg j/no-edit: \`ROW-1\` is still in Ready — the stray board was NOT edited"
  else
    bc_fail "leg j/no-edit: the stray board was edited despite the backend refusal"
  fi
  # …and the md declaration that the kit itself carries must NOT refuse (the vacuity guard: without
  # this leg the refusal above could be unconditional and every assertion would still pass).
  printf '# Fixture project\n\n- **Backlog backend**: BACKLOG.md (repo-native)\n' > "$bc_base/B/CLAUDE.md"
  bc_run "$bc_base/B" claim ROW-1 --branch feat/b --dry-run
  bc_expect_rc 0 "leg j/md-backend: the same board with an md declaration is accepted -> rc 0 (dry run)"

  # ---- leg (k): THE SELF-CLAIM DISCRIMINATION, REACHED AT THE PROBE (reviewer R-9) ---------------
  # The self-claim resume has TWO halves — same claimant AND same branch — and until this leg the
  # branch half was unasserted: mutating it to `&& true` left the whole suite green, because the only
  # leg that looked like it graded it (leg i) was refused earlier, by the board precondition. This
  # leg reaches the probe: the row sits in READY on the claimant's own board (so no precondition
  # fires) while the remote already carries THAT SAME IDENTITY's claim from ANOTHER branch. That is a
  # second session belonging to one human, which is precisely the double-claim the mechanism exists
  # to refuse — so it must be rc 3 and the FOREIGN sentence, never the resume.
  bc_run "$bc_base/B" claim ROW-1 --branch feat/b
  bc_expect_rc 0 "leg k/setup: B claims Ready row ROW-1 on feat/b -> rc 0"
  # Put ROW-1 back in Ready on B's own board: the claim above moved it, and this leg must be graded
  # by the PROBE, not by the Ready precondition. The remote's claim is untouched by this.
  bc_fixture_board "$bc_base/B/BACKLOG.md"
  bc_run "$bc_base/B" claim ROW-1 --branch feat/b2
  bc_expect_rc 3 "leg k/same-identity-other-branch: the SAME identity claiming from another branch -> rc 3 (ALREADY CLAIMED)"
  bc_has "leg k/same-identity-other-branch: the verdict is the FOREIGN holder sentence" "CLAIMED by"
  bc_has "leg k/same-identity-other-branch: it names the holding BRANCH, which is not this one" "on feat/b"
  bc_hasnt "leg k/same-identity-other-branch: it is NOT reported as a resume" "held by you"
  if awk '/^## In Progress/{s=1;next} s&&/^## /{exit} s&&/`ROW-1`/{f=1} END{exit !f}' "$bc_base/B/BACKLOG.md"; then
    bc_fail "leg k/no-board-edit: the refused cross-branch claim edited the board anyway"
  else
    bc_pass "leg k/no-board-edit: the refused cross-branch claim left the board alone"
  fi
  # …and the LIVENESS anchor for the same site: the same identity on the SAME branch, reached at the
  # same probe, IS the resume. Without this the discrimination above could be an unconditional rc 3.
  bc_run "$bc_base/B" claim ROW-1 --branch feat/b
  bc_expect_rc 0 "leg k/same-identity-same-branch: the same identity on the holding branch -> rc 0 (resume)"
  bc_has "leg k/same-identity-same-branch: the verdict says the claim is already yours" "held by you since"
  bc_run "$bc_base/B" release ROW-1
  bc_expect_rc 0 "leg k/cleanup: the holder releases ROW-1"

  # ---- leg (l): a claim ref whose CLAIM cannot be read is NOT the same as a MALFORMED one (R-10) --
  # `git show <ref>:CLAIM | head -c N` reports HEAD's status, never git's, so a ref carrying no CLAIM
  # file at all used to reach the fieldless-blob arm and be announced as MALFORMED. Two distinct
  # broken states, one sentence. These two legs are the discriminator: one ref with NO CLAIM, one
  # with a CLAIM that is present but carries no `claimant:`.
  bc_mkclaimref ROW-NOBLOB NOTACLAIM 'this orphan commit carries no CLAIM file at all'
  bc_run "$bc_base/A" check ROW-NOBLOB
  bc_expect_rc 0 "leg l/no-blob: check on a claim ref with no CLAIM file -> rc 0 (the ref IS there)"
  bc_has "leg l/no-blob: the verdict says the CLAIM could not be read" "CLAIM unreadable"
  bc_hasnt "leg l/no-blob: a MISSING blob is never announced as a malformed one" "MALFORMED"
  bc_mkclaimref ROW-BADCLAIM CLAIM 'row: ROW-BADCLAIM'
  bc_run "$bc_base/A" check ROW-BADCLAIM
  bc_expect_rc 0 "leg l/fieldless: check on a CLAIM with no claimant: field -> rc 0"
  bc_has "leg l/fieldless: a PRESENT but fieldless blob IS announced as MALFORMED" "MALFORMED"
  git --git-dir="$bc_remote_dir" update-ref -d refs/claims/ROW-NOBLOB
  git --git-dir="$bc_remote_dir" update-ref -d refs/claims/ROW-BADCLAIM

  # ---- leg (m): THE SIZE BOUND IS A CONTROL, SO IT GETS A LEG (reviewer R-13) -------------------
  # BC_CLAIM_MAX_BYTES exists because the CLAIM blob is written by whoever holds the ref: an attacker
  # with push rights could otherwise make every reader slurp a multi-megabyte blob into a shell
  # variable. Until this leg the refusal was unlegged — `if false` in front of it left the suite
  # 102/102 green. The fixture's oversize CLAIM carries a WELL-FORMED `claimant:` on its first line,
  # so the only thing that can refuse it is the bound; and because that name would print if the blob
  # were read, the `hasnt` below is the assertion that it was NOT read, not merely that it was
  # complained about.
  bc_mkclaimref ROW-HUGE CLAIM "claimant: OVERSIZE HOLDER <over@size.example>
$(awk 'BEGIN{p="";while(length(p)<5000)p=p "x";print p}')"
  bc_run "$bc_base/A" check ROW-HUGE
  bc_expect_rc 0 "leg m/oversize: check on an oversize CLAIM -> rc 0 (the ref IS there)"
  bc_has "leg m/oversize: the refusal names the byte bound" "past the $BC_CLAIM_MAX_BYTES-byte"
  bc_hasnt "leg m/oversize: the blob was NOT read — no holder is printed from it" "OVERSIZE HOLDER"
  git --git-dir="$bc_remote_dir" update-ref -d refs/claims/ROW-HUGE

  # ---- leg (n): release on an UNREADABLE claim names it, and never prints empty fields (R-12) ----
  # `_holder` is empty when the CLAIM cannot be read, so the non-holder refusal used to read
  # "is held by '', not by you" — an empty pair of quotes standing in for a fact nobody has. Same
  # split as do_claim's: readable -> the holder sentence; unreadable -> a NAMED refusal.
  bc_mkclaimref ROW-UNREADABLE NOTACLAIM 'no CLAIM file here either'
  bc_run "$bc_base/A" release ROW-UNREADABLE
  bc_expect_rc 1 "leg n/unreadable-release: release on an unreadable claim is refused, rc 1"
  bc_has "leg n/unreadable-release: the refusal NAMES the unreadable claim" "unreadable or malformed"
  bc_hasnt "leg n/unreadable-release: no empty-quoted holder is ever printed" "held by ''"
  git --git-dir="$bc_remote_dir" update-ref -d refs/claims/ROW-UNREADABLE

  if [ "$bc_st_fail" -ne 0 ]; then
    echo "board-claim --selftest: FAIL" >&2
    return 1
  fi
  echo "board-claim --selftest: OK (fixtures under $bc_base, removed by the EXIT trap — S-L3)"
  return 0
}

# --- selftest-only helpers, BELOW the marker so the mutation harness cannot neuter the oracle ----
bc_pass() { echo "selftest PASS: $1"; }
bc_fail() { echo "selftest FAIL: $1"; bc_st_fail=1; }

# bc_mkclone <name> <user.name> <user.email> — a clone of the bare remote with a fixture board.
bc_mkclone() {
  git clone -q "$bc_remote_dir" "$bc_base/$1" 2>/dev/null
  (
    cd "$bc_base/$1"
    git config user.name "$2"
    git config user.email "$3"
    git config commit.gpgsign false
  )
  bc_fixture_board "$bc_base/$1/BACKLOG.md"
}

# bc_fixture_board <path> — a board in the SHIPPED schema: a nine-column Ready table, a four-column
# In Progress table, and a Done row (so leg (f) has a real not-Ready row to be refused on).
bc_fixture_board() {
  cat > "$1" <<'BOARD_EOF'
# Fixture — Backlog

## Ready

| Item | Intent (why) | Acceptance criteria | Size | Risk | Type | Owner | Links | Success metric / hypothesis |
|------|--------------|---------------------|------|------|------|-------|-------|-----------------------------|
| `ROW-1` — the claimable row | because | it is claimed | S | low | feature | agent | — | a claim serializes |
| `ROW-2` — a second claimable row | because | it is claimed | S | low | feature | agent | — | a claim serializes |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|

## Done

| Item | Closed | Retro/outcome |
|------|--------|---------------|
| `ROW-DONE` — already shipped | 2026-09-03 | L1 retro. Disposition: none — fixture. |
BOARD_EOF
}

# bc_fixture_board_moved <path> <item-suffix> <links-cell> — a board whose ONLY row ALREADY sits In
# Progress, with the Item suffix and the Links cell chosen SEPARATELY by the caller. That separation
# is the whole point: reviewer R-2's defect was a whole-line grep, under which a branch named in the
# ITEM cell satisfied a precondition that is about the LINKS cell. A fixture that put the branch in
# both cells could not tell the two implementations apart.
bc_fixture_board_moved() {
  cat > "$1" <<BOARD_MOVED_EOF
# Fixture — Backlog

## Ready

| Item | Intent (why) | Acceptance criteria | Size | Risk | Type | Owner | Links | Success metric / hypothesis |
|------|--------------|---------------------|------|------|------|-------|-------|-----------------------------|

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|
| \`ROW-MOVED\` — moved by hand $2 | agent | 2026-09-04 | $3 |
BOARD_MOVED_EOF
}

# bc_mkclaimref <row> <filename> <content> — push a HAND-BUILT claim ref carrying <filename> instead
# of a well-formed CLAIM. It exists so leg (l) can tell "no CLAIM blob" from "a CLAIM blob with no
# claimant:" — two states the verb must not describe with one sentence. Built with the same plumbing
# the verb uses, so the fixture is a real ref on the real bare remote, not a simulation.
bc_mkclaimref() {
  (
    cd "$bc_base/A" || exit 1
    _mk_blob=$(printf '%s\n' "$3" | git hash-object -w --stdin)
    _mk_tree=$(printf '100644 blob %s\t%s\n' "$_mk_blob" "$2" | git mktree)
    _mk_commit=$(printf 'hand-built claim %s\n' "$1" | git commit-tree "$_mk_tree")
    git push -q origin "$_mk_commit:refs/claims/$1"
  )
}

# bc_run <clone-dir> <args...> — run THIS script inside the clone, capturing rc + merged output.
bc_run() {
  _bd=$1; shift
  if bc_out=$( cd "$_bd" && sh "$BC_SELF" "$@" 2>&1 ); then bc_rc=0; else bc_rc=$?; fi
}
# bc_run_badremote — the same, with origin pointed at a path that does not exist. THE honest way to
# make a remote unreachable: no stub pretending to fail, a genuinely absent remote.
bc_run_badremote() {
  _bd=$1; shift
  if bc_out=$( cd "$_bd" && BOARD_CLAIM_REMOTE="$bc_base/no-such-remote.git" sh "$BC_SELF" "$@" 2>&1 ); then bc_rc=0; else bc_rc=$?; fi
}
bc_expect_rc() { # <want> <label>
  if [ "$bc_rc" -eq "$1" ]; then bc_pass "$2"
  else bc_fail "$2 (rc=$bc_rc, wanted $1); out=[$bc_out]"; fi
}
bc_has() { # <label> <needle>
  case "$bc_out" in
    *"$2"*) bc_pass "$1" ;;
    *) bc_fail "$1 (output does not carry '$2'); out=[$bc_out]" ;;
  esac
}
bc_hasnt() { # <label> <needle> — graded on what a refusal does NOT say as much as what it does
  case "$bc_out" in
    *"$2"*) bc_fail "$1 (output wrongly carries '$2'); out=[$bc_out]" ;;
    *) bc_pass "$1" ;;
  esac
}

BC_SELF=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/$(basename -- "$0")

bc_cmd="${1:-}"
[ $# -gt 0 ] && shift || true
case "$bc_cmd" in
  claim)     if do_claim   "$@"; then bc_rc_main=0; else bc_rc_main=$?; fi ;;
  release)   if do_release "$@"; then bc_rc_main=0; else bc_rc_main=$?; fi ;;
  check)     if do_check   "$@"; then bc_rc_main=0; else bc_rc_main=$?; fi ;;
  --selftest) if selftest;       then bc_rc_main=0; else bc_rc_main=$?; fi ;;
  -h|--help) bc_usage; bc_rc_main=2 ;;
  *)         bc_usage; bc_rc_main=2 ;;
esac
exit "$bc_rc_main"
