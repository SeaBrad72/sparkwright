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
#   sh scripts/board-claim.sh status
#   sh scripts/board-claim.sh claim-ref   <ROW-ID> [--branch <name>] [--then <shell-command>]
#   sh scripts/board-claim.sh release-ref <ROW-ID> [--stale] [--then <shell-command>]
#   sh scripts/board-claim.sh --selftest
#
# claim-ref / release-ref (TBG-SEAM-CONSUMERS-DERIVED T4, §6a S-5) — BACKEND-AGNOSTIC ref-only
# primitives: the git ref IS the lock on every backend, so unlike `claim`/`release` they never read
# or write a board of any kind. Lane 2's `board.sh` CALLS these (it does not edit this file) to
# sequence a tracker-side write around the ref: `claim-ref ROW --then '<tracker write>'` takes the
# ref FIRST (the non-fast-forward rejection is the atomic lock) and, if `--then`'s command fails,
# COMPENSATES by deleting the ref it just pushed (under `--force-with-lease` on the sha it pushed)
# before exiting non-zero — so a tracker-write failure never leaves an orphaned claim behind.
# `release-ref ROW --then '<tracker write>'` runs the REVERSE order: `--then` runs FIRST (the
# tracker-side release), and the ref is deleted only once it succeeds; if `--then` fails the ref is
# left untouched (nothing to compensate — the release never started) AND NOTHING IS LOGGED; if
# `--then` SUCCEEDS but the ref-delete then fails, that is a FAILED COMPENSATION and it exits non-zero
# NAMING the recovery verb (`release-ref ROW` again, with no `--then`, to retry just the delete) —
# never a silent half-state. With `--stale`, the release record (`refs/claims-log/<ROW>`) is written
# AFTER `--then` succeeds and BEFORE the delete — never before `--then`, so a failed tracker-side step
# never leaves a log entry asserting a release that did not happen (security fix round, M-2).
#
# EXIT CODES (a silent 0 is never an answer here):
#   claim   : 0 claimed / resumed · 2 usage / bad row id / bad branch / session-state refusal /
#             board refusal / REMOTE UNREACHABLE / a rejected resume push · 3 ALREADY CLAIMED
#   release : 0 released · 1 no claim to release / not the holder (without --stale) / --stale with
#             NO PROOF of staleness · 2 usage / REMOTE UNREACHABLE / a short force reason / a
#             release record that could not be written
#   check   : 0 a claim exists · 1 no claim · 2 usage / REMOTE UNREACHABLE
#   status  : 0 rendered · 1 no claims · 2 usage / REMOTE UNREACHABLE
#   claim-ref   : 0 claimed (and, with --then, the following step succeeded) · 1 --then failed and
#                 was compensated (ref deleted), OR --then failed AND the compensation itself failed
#                 (named, non-zero) · 2 usage / bad row id / bad branch / REMOTE UNREACHABLE ·
#                 3 ALREADY CLAIMED
#   release-ref : 0 released (and, with --then, the following step succeeded first) · 1 --then failed
#                 (ref untouched) / no claim to release / not the holder (without --stale) / --stale
#                 with no proof · 2 usage / REMOTE UNREACHABLE / a short force reason / a release
#                 record that could not be written · non-zero, NAMING `release-ref` as the recovery
#                 verb, when --then succeeded but the compensating ref-delete then failed
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
#   * A stale claim is released by `release --stale`, which now REFUSES unless staleness is PROVEN
#     (P2/P3 below — "branch absent" is evidence, not a proof), and is visible in `check --all` and
#     `status`. Nothing here proves the
#     claimant is still working — `status` reads LIVE for "not provably dead", which is a weaker
#     statement than it looks.
#
# HONEST CEILING, B2-SESSION-IDENTITY-LEDGER ADDITIONS (decisions 2/3/4) — read these too:
#   * `session:` IS DECLARED, NEVER AUTHENTICATED. It is minted by this verb into
#     `<toplevel>/.kit-run/session.id` and is an input to NOTHING that authorizes anything. Two LIVE
#     sessions of one human on one branch look exactly like a cold resume, and the resume names the
#     previous session rather than judging it. An adopter may write a harness's own id into that
#     file (it is the seam) — which is why the READ grammar is wider than the MINT grammar.
#   * `BOARD_CLAIM_REMOTE` / `BOARD_CLAIM_BOARD` REACH EVERY VERB BY AN EXPORTED VARIABLE. That is
#     pre-existing (since this verb shipped) and it is not a hole this slice opened, but say it
#     plainly: `git remote set-url` is guard-denied and an `export` is not, so an agent can point
#     these verbs at another remote or another board. Nothing downstream re-derives them.
#   * THE PROOF SET IS **P2 AND P3 ONLY**, and "branch absent on origin" (the old P1) IS NOT ONE.
#     Withdrawn at fix round 1 on live acceptance: under `ONE-PUSH-PER-PR` every in-build slice's
#     branch is absent from origin until its final push, so that test is true of the HEALTHY case —
#     it rated this kit's own live claim releasable mid-build. It was also manufacturable (pushing a
#     branch deletion is an allowed agent call; `D-240819-4` makes deletion a human act BY RULING,
#     guard face boarded as `GUARD-PUSH-DELETE-BRANCH-UNCOVERED`). It is printed as EVIDENCE, with
#     the sentence saying so, and it decides nothing.
#   * A DEAD SESSION WHOSE WORK NEVER REACHED ORIGIN HAS NO AUTOMATIC PROOF, and that is deliberate:
#     it is the human dial's case (`KIT_CLAIM_FORCE_RELEASE`), logged to `refs/claims-log/<ROW>`.
#   * P2/P3 ARE THE FORGE PR AND THE **md BOARD**. ⚠️ RETIRED (TBG-SEAM-CONSUMERS-DERIVED T3, F5):
#     `claim` used to REFUSE to run at all on a declared non-md backend (S-L5, `bc_backend`), on the
#     theory that "no claim primitive to reclaim" there. `claim-ref`/`release-ref` below are the
#     backend-agnostic ref-only primitives that theory was blocking — the git ref is the lock on
#     EVERY backend, so the claim path no longer resolves a backend to refuse non-md. P3 (the md
#     board) stays an md-SPECIFIC proof `release --stale`/`status` may print when a board exists
#     (`bc_ev_row` degrades to `unknown` when one does not); it is no longer gated on a backend
#     declaration, only on whether a `BACKLOG.md` blob is actually there to read.
#   * READS NEVER SHALLOW-POISON THE CALLER'S CLONE. Every read bounds its fetch with `--depth`, and
#     a `--depth` fetch writes `.git/shallow` into the repo it fetches into; a repo carrying
#     `.git/shallow` has its next push REJECTED by a remote that enforces `receive.shallowUpdate`
#     (ubuntu git does; macOS git 2.48 does not, which hid this for two rounds). So every bounded
#     read runs in an ISOLATED throwaway git dir, never the caller's clone — the operator's own
#     `git push` is never at risk from having run a claim verb.
#   * `refs/claims-log/*` IS APPEND-ONLY, AND ITS **LAST** ENTRY IS THE TRUTH. The record is pushed
#     BEFORE the delete (a release that leaves no trace is what it exists to prevent), so a delete
#     that then FAILS would leave an entry asserting a release that never happened — measured real,
#     not theoretical: the delete is refused under `kit-guard install-shims` by the force-push rule.
#     A failed delete therefore appends a COMPENSATING `<proof>-FAILED` entry with
#     `released-sha: (not deleted)`. Read the last entry for a row, never the first.
#   * `refs/claims-log/*` IS A TRACE, NOT TAMPER-EVIDENCE. It is one more unprotected ref namespace:
#     anyone with push rights deletes an entry exactly as they delete a claim. It exists because the
#     terminal banner on a FORCED release is not a control; a durable line a human reads later is
#     one tier better, and one tier only.
#   * THE FORCE DIAL'S REACH IS MEASURED, NOT ASSERTED. The in-line `KIT_CLAIM_FORCE_RELEASE=` prefix
#     over the in-tree script is DENIED to an agent under the guard (the unvetted-prefix rule, same
#     as B4's `KIT_RUNAWAY_SANDBOX`); `export` as its own call, a COPIED script and an agent-authored
#     `make` wrapper are MEASURED-UNCOVERED wherever the tool shell persists env, and are pinned as
#     such beside the deny in `conformance/agent-autonomy.sh`. The sentence "not reachable from an
#     agent" is NOT made here.
#   * THE GUARD ARM IS HARNESS-LOCAL. Raw `refs/claims/*` and `refs/claims-log/*` pushes are denied
#     to an agent under the Claude PreToolUse guard (and under `kit-guard install-shims`); this
#     verb's own pushes pass by exporting `KIT_CLAIM_FRONT_DOOR=1` into the guard's PROCESS
#     environment. It does not bind an actor with push rights and a plain terminal. The forge
#     ruleset that would (`refs/claims/**`, `refs/claims-log/**`) is an owner keystroke, named not done.
#
# POSIX sh; dash-clean (no `local`, no bashisms). Transaction discipline is COPIED, not reinvented,
# from scripts/promotion-verify.sh's `_pv_sync_in`: `git ls-remote --exit-code` is the probe that
# splits "absent" (rc 2) from "unreachable" (anything else), because a bare `git fetch` exits 128 for
# BOTH and its rc therefore cannot be read as an answer.
# What it changes: `claim` MINTS `<toplevel>/.kit-run/session.id` when absent, PUSHES a new ref
#   `refs/claims/<ROW-ID>` to origin (or a CHILD commit on it when a new session resumes the row) and
#   REWRITES BACKLOG.md in place (moving one row Ready -> In Progress, uncommitted); `release`
#   DELETES that ref on origin under a compare-and-swap old-value and, for a `--stale` release,
#   PUSHES a record to `refs/claims-log/<ROW-ID>` first; `check` and `status` are read-only. Nothing
#   else on the remote is touched — no branch, no tag, no note.
# Guardrails: the row id is validated against `[A-Z0-9][A-Z0-9-]*` BEFORE it becomes a ref name and
#   before any network call, so `/`, `..`, whitespace, control bytes and lowercase are refused
#   offline; the push carries NO leading `+` (the forge's non-fast-forward rejection IS the
#   compare-and-swap); `release` uses `--force-with-lease=<ref>:<observed-sha>` so it can only ever
#   delete the claim it read, and refuses a claim held by someone else unless `--stale` is given
#   (naming the holder either way); a fetched `CLAIM` file is UNTRUSTED TEXT — parsed by fixed field
#   names, never `eval`'d, and sanitised with `tr -d '[:cntrl:]'` before it reaches a terminal; an
#   unreachable remote REFUSES (rc 2) and is never reported as "no claim"; a `branch:` value is held
#   to `git check-ref-format --branch` at WRITE and at every READ and is only ever passed onward as a
#   full refspec or as `--head=<b>`, never as a bare argument; `<toplevel>/.kit-run/session.id` is
#   refused (rc 2, naming the path) unless its directory and itself are real, non-symlink,
#   link-count-1, uid-owned, and its content is one line of [A-Za-z0-9._-]{1,64} read through
#   `head -c 256`; `release --stale` REFUSES without a forge-visible proof of staleness and logs
#   every non-holder release to `refs/claims-log/<ROW-ID>` BEFORE it deletes anything; the scratch ref every read
#   fetches into is PID-scoped, fetched `--depth=1`, and dropped by an EXIT trap; the CLAIM blob is
#   read through `head -c 4096` and a blob carrying no `claimant:` field inside that bound is REFUSED
#   as malformed rather than parsed into a holder sentence; `claim` refuses when no BACKLOG.md is
#   present at all (regardless of any declared backend — RETIRED S-L5/`bc_backend`, T3); and
#   `claim-ref`/`release-ref` are backend-agnostic ref-only primitives that never touch a board.
set -eu

BC_REMOTE="${BOARD_CLAIM_REMOTE:-origin}"
BC_BOARD="${BOARD_CLAIM_BOARD:-BACKLOG.md}"

# ⚠️ A BACKSTOP ONLY, SINCE FIX ROUND 2. Reads no longer fetch into the caller's clone at all (they
# use isolated throwaway dirs — see below), so these PID-scoped scratch refs are never created here
# any more. This removes any left by an INTERRUPTED run of an older build in the same clone; it is
# defensive, not load-bearing, and deletes refs that on a current build simply do not exist.
BC_SCRATCH="refs/kit/claim-scratch-$$"
bc_drop_scratch() {
  git update-ref -d "$BC_SCRATCH" >/dev/null 2>&1 || true
  git update-ref -d "refs/kit/claim-board-$$" >/dev/null 2>&1 || true
  git update-ref -d "refs/kit/claim-log-$$" >/dev/null 2>&1 || true
}

# ── ISOLATED READS — A `--depth` FETCH NEVER TOUCHES THE CALLER'S OWN CLONE (fix round 2) ────────
# THE BUG THIS CLOSES, and it is production, not a selftest artefact. Every read here bounds the
# fetch with `--depth` (against a maliciously deep-history claim ref, the M4 hardening). Fetching a
# ref `--depth=N` writes `.git/shallow` into the repository it fetches INTO — and a repository that
# carries `.git/shallow` is refused BY THE REMOTE on its next push (`receive.shallowUpdate` is off
# by default: "shallow update not allowed"). So a `claim`/`check`/`status`/`release` that read a
# claim into the CALLER'S working clone left it shallow, and the operator's very next `git push`
# (their own branch, the claim itself, anything) was rejected. MEASURED: ubuntu git 2.43/2.48
# enforces it and the kit's CI went red on exactly this; macOS git 2.48 ALLOWS the push, which is
# why it passed locally for two rounds. The cure is not to drop the depth bound — it is to do the
# bounded fetch in a THROWAWAY git dir the caller never pushes from, and delete it. The dir being
# shallow is fine: nothing the operator relies on is ever shallow, and a CHILD-commit push (resume,
# claims-log) from a throwaway shallow dir whose parent the remote already has is accepted (MEASURED
# on ubuntu — only ORPHAN/disconnected pushes from a shallow repo are refused, and those paths never
# fetch, so their throwaway dir is not shallow).
#
# The remote is resolved to a URL/path ONCE, because a throwaway `git init` dir has no `origin`
# remote to name — a named remote must become the URL it points at; a value that is already a
# path/URL (the selftest's `BOARD_CLAIM_REMOTE`) is used as-is.
bc_remote_url() { git remote get-url "$BC_REMOTE" 2>/dev/null || printf '%s' "$BC_REMOTE"; }

# All throwaway dirs live under ONE root, removed by the EXIT trap so an interrupted read leaks
# nothing (the disk-safety lesson again).
# ⚠️ THE ROOT IS CREATED HERE, IN THE PARENT SHELL, NOT LAZILY INSIDE bc_iso_dir — and that is not a
# style choice. bc_iso_dir is always called as `x=$(bc_iso_dir)`, i.e. in a command-substitution
# SUBSHELL; a `BC_ISO_ROOT=$(mktemp -d)` there would set the root in the subshell only, the parent's
# EXIT trap would see it empty, and every throwaway dir would leak. Every verb performs at least one
# isolated read, so eager creation is never wasted; if mktemp fails the root is empty and bc_iso_dir
# degrades (rc 1), which every caller already handles as "unreadable".
BC_ISO_ROOT=$(mktemp -d 2>/dev/null || echo '')
# bc_iso_dir -> echoes a fresh throwaway git dir carrying the caller's identity (so a child-commit
# path can `commit-tree` in it), or empty + rc 1 on failure.
bc_iso_dir() {
  [ -n "$BC_ISO_ROOT" ] || return 1
  _iso=$(mktemp -d "$BC_ISO_ROOT/gd.XXXXXX") || return 1
  if ! git init -q "$_iso" >/dev/null 2>&1; then rm -rf "$_iso"; return 1; fi
  git -C "$_iso" config user.name  "$(git config user.name  2>/dev/null || echo kit)" >/dev/null 2>&1 || true
  git -C "$_iso" config user.email "$(git config user.email 2>/dev/null || echo kit@local)" >/dev/null 2>&1 || true
  git -C "$_iso" config commit.gpgsign false >/dev/null 2>&1 || true
  printf '%s\n' "$_iso"
}
# S-L3 — the selftest's `mktemp -d` fixture tree is removed on EVERY exit path, not just the happy
# one. Each run builds a bare remote plus two clones; leaving them behind on the first failing leg is
# how a CI runner's disk fills up one red at a time (the disk-safety lesson, paid for once already).
# `bc_base` is only ever set by selftest(), so the guard is what keeps this trap a no-op for the verbs.
# ⚠️ EVERY LINE HERE IS BEST-EFFORT, AND THAT IS LOAD-BEARING (fix round 3). This is an EXIT trap,
# and in dash a command that FAILS inside an EXIT trap OVERRIDES the script's `exit 0` — so a
# cleanup step that cannot complete would report a SUCCESSFUL verb as failed. That is not
# hypothetical: under `kit-guard install-shims` (a supported adopter mode) `rm` is shimmed and the
# guard BLOCKS `rm -rf` ("recursive rm is irreversible - human-gated"), so the round-2 `rm -rf
# "$BC_ISO_ROOT"` turned every claim/check/status/release under shims into an rc-1 "failure" on top
# of a "claim: OK". So each destructive step is wrapped so it can NEVER change the exit code, and
# `2>/dev/null` also swallows the guard's block message so a normal shimmed run stays quiet. The
# leaked temp dir under a blocked `rm` is the correct trade: a false failure is worse than a temp
# dir the OS reaps, and a guarded runtime is exactly where deleting things is meant to be hard.
bc_cleanup() {
  bc_drop_scratch 2>/dev/null || true
  { [ -n "${BC_ISO_ROOT:-}" ] && rm -rf "$BC_ISO_ROOT" 2>/dev/null; } || true
  { [ -n "${bc_base:-}" ] && rm -rf "$bc_base" 2>/dev/null; } || true
  return 0
}
trap 'bc_cleanup' EXIT INT TERM

bc_usage() {
  echo "usage:" >&2
  echo "  board-claim.sh claim   <ROW-ID> [--branch <name>] [--links <text>] [--dry-run] [--board-already-moved]" >&2
  echo "  board-claim.sh release <ROW-ID> [--stale]" >&2
  echo "  board-claim.sh check   [<ROW-ID> | --all]" >&2
  echo "  board-claim.sh status" >&2
  echo "  board-claim.sh claim-ref   <ROW-ID> [--branch <name>] [--then <shell-command>]" >&2
  echo "  board-claim.sh release-ref <ROW-ID> [--stale] [--then <shell-command>]" >&2
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

# ── THE DECLARED SESSION — `<toplevel>/.kit-run/session.id` (B2 decision 1) ─────────────────────
# ONE id per worktree, for the life of the worktree: minted by `claim` when absent, read by
# everything else. It is DECLARED, NEVER AUTHENTICATED — a coordination mechanism so `status` and
# `resume` can say which session holds a row, and an input to NOTHING that authorizes anything. A
# file rather than an env var because an inherited variable follows a `cd` into another worktree;
# that removes the ACCIDENTAL route, and nothing more (B4 decision 2's sentence still stands).
#
# ⚠️ HYGIENE IS NOT DECORATION HERE [sec-1, HIGH]. Writes under `.kit-run/` are NOT control-plane to
# the guard, so a planted `.kit-run/session.id -> hooks/pre-push` would turn the next `claim` — the
# OWNER'S own, from `!` — into a truncating write onto the control plane, and `-> /dev/zero` would
# hang the read. So this follows `scripts/runaway-guard.sh`'s state-dir discipline exactly (the
# `rg_safe_dir`/`rg_safe_file` shapes, re-derived here because this script must run without it):
# refuse (rc 2, NAMING the path) unless `.kit-run` is a real non-symlink uid-owned directory and the
# file is absent, or a regular non-symlink LINK-COUNT-1 uid-owned file. `-L` is tested BEFORE `-e`
# for the dangling-symlink plant (the append would CREATE the target). The read is bounded by
# `head -c 256` before the grammar runs, and a malformed file is REFUSED, never sanitized into a
# value: half a session id is a worse answer than a named refusal.
BC_SESSION_MAX_BYTES=256
bc_session_file() { # -> <toplevel>/.kit-run/session.id, or empty outside a work tree
  _bstop=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  [ -n "$_bstop" ] || return 0
  printf '%s/.kit-run/session.id\n' "$_bstop"
}
bc_session_refuse() { # <path> <why>
  echo "board-claim: REFUSED (2) — '$1' $2." >&2
  echo "             The declared session id is per-worktree state; a planted or malformed one is" >&2
  echo "             refused, never followed and never sanitized into a value. Remove or fix the file." >&2
  return 2
}
# bc_session_read <file> -> echo the id (empty when the file is absent); rc 0 ok · 2 refused
bc_session_read() {
  [ -L "$1" ] && { bc_session_refuse "$1" "is a symlink; refusing to read or write THROUGH it"; return 2; }
  [ -e "$1" ] || return 0
  [ -f "$1" ] || { bc_session_refuse "$1" "is not a regular file"; return 2; }
  # shellcheck disable=SC3067  # `-O` is outside POSIX test and MEASURED present on every shell this
  # runs under (dash 0.5.12, bash 3.2 on macOS, the CI ubuntu /bin/sh); a shell lacking it makes `[`
  # fail, which lands on the refusal — the fail-CLOSED direction, by construction.
  [ -O "$1" ] || { bc_session_refuse "$1" "is not owned by this user"; return 2; }
  _bsln=$(ls -ld -- "$1" 2>/dev/null | awk '{print $2}')
  if [ "$_bsln" != 1 ]; then
    bc_session_refuse "$1" "has link count $_bsln, not 1 (a hard-linked state file is a plant)"; return 2
  fi
  _bsraw=$(head -c "$BC_SESSION_MAX_BYTES" -- "$1" 2>/dev/null || true)
  # Command substitution strips TRAILING newlines, so a well-formed one-line file leaves NO newline
  # in `_bsraw`; any embedded newline means the file carries a second line.
  # ⚠️ THE PATTERN IS A LITERAL NEWLINE IN SINGLE QUOTES, NOT `$(printf '\n')` — and that was a real
  # bug, caught RED by this leg's own fixtures: command substitution strips the trailing newline from
  # `printf '\n'` too, so the pattern collapsed to the EMPTY STRING and `*""*` matched every file.
  # Every well-formed session id was refused as "more than one line".
  _bsnl='
'
  case "$_bsraw" in
    *"$_bsnl"*) bc_session_refuse "$1" "carries more than one line"; return 2 ;;
  esac
  case "$_bsraw" in
    '')                       bc_session_refuse "$1" "is empty"; return 2 ;;
    *[!A-Za-z0-9._-]*)        bc_session_refuse "$1" "is not [A-Za-z0-9._-]{1,64}"; return 2 ;;
  esac
  if [ "${#_bsraw}" -gt 64 ]; then
    bc_session_refuse "$1" "is longer than 64 characters"; return 2
  fi
  printf '%s\n' "$_bsraw"
  return 0
}
# bc_session_id [--mint] -> echo the id, or `unknown` when there is no work tree; rc 0 · 2 refused
# The mint is `mktemp` inside `.kit-run` + `mv` under `umask 077`: a RENAME replaces a planted link
# rather than following it, and the file is never world-readable for a moment.
bc_session_id() {
  _bsmint=0; [ "${1:-}" = --mint ] && _bsmint=1
  _bsf=$(bc_session_file)
  [ -n "$_bsf" ] || { printf 'unknown\n'; return 0; }
  _bsdir=$(dirname -- "$_bsf")
  if [ -L "$_bsdir" ]; then
    bc_session_refuse "$_bsdir" "is a symlink; refusing to keep session state in a redirected directory"
    return 2
  fi
  if [ -e "$_bsdir" ]; then
    [ -d "$_bsdir" ] || { bc_session_refuse "$_bsdir" "is not a directory"; return 2; }
    # shellcheck disable=SC3067  # see the note in bc_session_read: measured-present, fail-closed if not.
    [ -O "$_bsdir" ] || { bc_session_refuse "$_bsdir" "is not owned by this user"; return 2; }
  fi
  if _bsid=$(bc_session_read "$_bsf"); then :; else return 2; fi
  if [ -n "$_bsid" ]; then printf '%s\n' "$_bsid"; return 0; fi
  if [ "$_bsmint" != 1 ]; then printf 'unknown\n'; return 0; fi
  [ -d "$_bsdir" ] || (umask 077; mkdir -p "$_bsdir") || {
    bc_session_refuse "$_bsdir" "could not be created"; return 2; }
  _bsnew="s-$(date -u +%Y%m%d)-$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
  _bstmp=$(umask 077; mktemp "$_bsdir/session.XXXXXX") || {
    bc_session_refuse "$_bsf" "could not be minted (mktemp failed in its directory)"; return 2; }
  (umask 077; printf '%s\n' "$_bsnew" > "$_bstmp") && mv -f "$_bstmp" "$_bsf" || {
    rm -f "$_bstmp" 2>/dev/null || true
    bc_session_refuse "$_bsf" "could not be minted (the atomic rename failed)"; return 2; }
  printf '%s\n' "$_bsnew"
  return 0
}

# ── BRANCH GRAMMAR — VALIDATED AT WRITE **AND** AT EVERY READ (B2 decision 2, sec-2) ────────────
# A branch name reaches `git fetch`, `git ls-remote` and `gh` in later verbs. `do_claim` used to
# write `branch:` unvalidated and `bc_field` strips control bytes only, so a front-door claim with
# `--branch '--upload-pack=<cmd>'` was a LEGITIMATE claim whose value a later reader would hand to
# git as a bare argument — remote command execution on the next reader's machine, the owner's
# included. Two layers, and the offline one runs FIRST because `git check-ref-format --branch` would
# itself parse a leading `-` as an option (and expands `@{-1}`):
#   (a) an offline charset/shape refusal: non-empty, no leading `-`, only [A-Za-z0-9._/-], no `@{`;
#   (b) git's own `check-ref-format --branch`, which owns the rest of the ref grammar (`..`, `//`,
#       trailing `.lock`, a lone `@`, control bytes).
# Every verb that passes a branch onward passes it as a FULL REFSPEC (`refs/heads/<b>:…`) or as
# `--head=<b>` to `gh` — a `refs/heads/` prefix cannot be an option, and `--head=` is one token.
bc_branch_ok() {
  case "$1" in
    '')                    return 1 ;;
    -*)                    return 1 ;;
    *[!A-Za-z0-9._/-]*)    return 1 ;;
    *'@{'*)                return 1 ;;
  esac
  git check-ref-format --branch "$1" >/dev/null 2>&1 || return 1
  return 0
}
bc_require_branch() { # <value> <where>
  if bc_branch_ok "$1"; then return 0; fi
  echo "board-claim: '$(printf '%s' "$1" | tr -d '[:cntrl:]' | cut -c1-80)' is not a valid branch name ($2)." >&2
  echo "             A branch value becomes an argument to git and gh, so it is held to" >&2
  echo "             [A-Za-z0-9._/-] plus git's own check-ref-format --branch, at write AND at read." >&2
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

# bc_read_claim <ref> -> print the CLAIM blob. The ref is fetched into an ISOLATED THROWAWAY git dir
# (fix round 2 — never the caller's clone, whose `.git/shallow` would then have the operator's next
# push rejected; see the isolated-reads block above) and the dir is removed immediately.
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
  _rc_gd=$(bc_iso_dir) || return 1
  if ! git -C "$_rc_gd" fetch --no-tags --depth=1 "$(bc_remote_url)" "$1:refs/scratch" >/dev/null 2>&1; then
    rm -rf "$_rc_gd"; return 1
  fi
  if _bc_size=$(git -C "$_rc_gd" cat-file -s refs/scratch:CLAIM 2>/dev/null); then
    :
  else
    rm -rf "$_rc_gd"; return 1
  fi
  case "$_bc_size" in
    ''|*[!0-9]*) rm -rf "$_rc_gd"; return 1 ;;
  esac
  if [ "$_bc_size" -gt "$BC_CLAIM_MAX_BYTES" ]; then
    rm -rf "$_rc_gd"
    echo "board-claim: the CLAIM blob at $1 is $_bc_size bytes, past the $BC_CLAIM_MAX_BYTES-byte" >&2
    echo "             bound. Refusing to read a holder out of it." >&2
    return 1
  fi
  _bc_txt=$(git -C "$_rc_gd" show refs/scratch:CLAIM 2>/dev/null)
  rm -rf "$_rc_gd"
  case "$_bc_txt" in
    *"claimant: "*) ;;
    *)
      echo "board-claim: the CLAIM blob at $1 is MALFORMED — no 'claimant:' field in its first" >&2
      echo "             $BC_CLAIM_MAX_BYTES bytes. Refusing to read a holder out of it." >&2
      return 1 ;;
  esac
  # ⚠️ THE BRANCH IS VALIDATED HERE, AT THE READ, FOR EVERY CALLER (B2 decision 2, sec-2). The CLAIM
  # blob is written by whoever holds the ref; a `branch:` that is an option string would otherwise be
  # handed to `git`/`gh` by `status`, `release --stale` and `resume`. A blob carrying one is MALFORMED
  # and is refused out loud, exactly like a fieldless one — never parsed into a holder sentence.
  _bc_br=$(printf '%s\n' "$_bc_txt" | grep '^branch: ' | head -1 | cut -d' ' -f2- | tr -d '[:cntrl:]')
  if [ -n "$_bc_br" ] && ! bc_branch_ok "$_bc_br"; then
    echo "board-claim: the CLAIM blob at $1 is MALFORMED — its 'branch:' field is not a valid branch" >&2
    echo "             name. Refusing to read a holder out of it (the value would reach git as an" >&2
    echo "             argument on this machine)." >&2
    return 1
  fi
  printf '%s\n' "$_bc_txt"
  return 0
}

# bc_field <claim-text> <name> — read ONE field by FIXED NAME. The CLAIM file is untrusted text from
# a ref anyone with push rights can write, so it is never `eval`'d, never sourced, and every value is
# stripped of control bytes before it can reach a terminal.
bc_field() {
  printf '%s\n' "$1" | grep "^$2: " | head -1 | cut -d' ' -f2- | tr -d '[:cntrl:]'
}

# bc_claim_session <claim-text> — the DECLARED session id off a CLAIM, or `unknown`. The blob writes
# `session: <id> (declared)`, so the annotation is cut and only the id itself is returned; a value
# that is not in the read grammar reads `unknown` rather than reaching a terminal, because this field
# is DISPLAY ONLY and an unparseable one must not look like a fact.
bc_claim_session() {
  _bcs=$(bc_field "$1" session); _bcs=${_bcs%% *}
  case "$_bcs" in
    '')                  printf 'unknown\n'; return 0 ;;
    *[!A-Za-z0-9._-]*)   printf 'unknown\n'; return 0 ;;
  esac
  [ "${#_bcs}" -le 64 ] || { printf 'unknown\n'; return 0; }
  printf '%s\n' "$_bcs"
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
# not live rows), extended only with the line number the edit needs. The Item cell (field 1) is read
# with the SAME odd-backslash-run join rule as bc_cell/bc_col_index (BOARD-PIPE-ESCAPE T4), so an
# escaped pipe ahead of the row's id inside the Item cell does not truncate it against a naive `$2`.
# A row whose escaping is malformed enough to still hide its id from this join is fail-CLOSED — claim
# refuses rather than acting on a row it cannot see — which is acceptable (design §6.5).
bc_row_line() {
  awk -F'|' -v sec="$2" -v want="$3" '
    /^[[:space:]]*```/ { infence = !infence; next }
    infence { next }
    $0 ~ "^## " sec "[[:space:]]*$" { inseg = 1; next }
    inseg && /^## / { inseg = 0 }
    inseg && /^[[:space:]]*\|/ {
      c = ""
      for (j = 2; j <= NF; j++) {
        c = (c == "") ? $j : c "|" $j
        t = c; run = 0
        while ((L = length(t)) > 0 && substr(t, L, 1) == "\\") { run++; t = substr(t, 1, L - 1) }
        if (run % 2 == 1) continue
        break
      }
      gsub(/^[ \t]+|[ \t]+$/, "", c)
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
# any cwd without sourcing a library that expects the repo root (see the block comment above). Same
# GFM-exact odd-backslash-run join rule as the library's cell() (BOARD-PIPE-ESCAPE T4): a `|` delimits
# a cell iff it is NOT preceded by an odd-length run of `\` — so `\|` keeps joining (an escaped pipe)
# while `\\|` (an even run — a literal trailing backslash, THEN a real delimiter) does not. RAW value
# returned, backslashes preserved (§6.7 of the design).
bc_cell() {
  printf '%s' "$1" | awk -F'|' -v i="$2" '
    {
      n=0; s=""
      for (j=2; j<=NF; j++) {
        s = (s=="") ? $j : s "|" $j
        t=s; run=0
        while ((L=length(t)) > 0 && substr(t,L,1)=="\\") { run++; t=substr(t,1,L-1) }
        if (run % 2 == 1) continue                        # odd backslash run -> the pipe was escaped, keep joining
        if (j==NF && s ~ /^[ \t]*$/) break                 # the trailing artifact after a closing "|" is not a column
        n++
        if (n==i) { v=s; gsub(/^[ \t]+|[ \t]+$/,"",v); print v; exit }
        s=""
      }
    }'
}

# bc_col_index <header-row> <column-name> -> the 1-based column index, or EMPTY when the table has no
# such column. backlog-lib.sh's col_index, inlined for the reason stated at the top of this block, and
# reconciled to the SAME odd-backslash-run rule as bc_cell (BOARD-PIPE-ESCAPE T4): an escaped pipe in
# a header cell must not shift every later column's resolved index by one.
# This exists so nothing here ever greps a WHOLE ROW LINE for a value that belongs to one cell: an
# Item cell that happens to mention a branch name is not a Links cell that names it (reviewer R-2).
bc_col_index() {
  printf '%s' "$1" | awk -F'|' -v want="$2" '
    {
      n=0; s=""
      for (j=2; j<=NF; j++) {
        s = (s=="") ? $j : s "|" $j
        t=s; run=0
        while ((L=length(t)) > 0 && substr(t,L,1)=="\\") { run++; t=substr(t,1,L-1) }
        if (run % 2 == 1) continue
        if (j==NF && s ~ /^[ \t]*$/) break
        n++
        v=s; gsub(/^[ \t]+|[ \t]+$/,"",v)
        if (v==want) { print n; exit }
        s=""
      }
    }'
}

# ── THE DECLARED BACKEND — RETIRED (TBG-SEAM-CONSUMERS-DERIVED T3, F5) ────────────────────────────
# `bc_backend` used to be a THIRD parse site duplicating conformance/backlog-lib.sh's `resolve_backend`
# (field-leading line, cut the annotation, lowercase, canonical token), so `claim` could refuse on a
# declared non-md backend (S-L5: a stray BACKLOG.md beside a `jira` declaration was a leftover nobody
# reads). It is retired: `claim-ref`/`release-ref` below are backend-agnostic (the git ref is the lock
# on EVERY backend), so the claim path no longer resolves a backend to refuse non-md at all. `claim`'s
# own board-move half still refuses when NO `BACKLOG.md` is present (`[ -f "$BC_BOARD" ]`, unchanged) —
# that is a real-file check, not a backend parse, so a stray board on a hosted-tracker project is no
# longer caught by a declaration read here. This is a disclosed behavioural narrowing, not an
# oversight: the row's own text names it ("the claim path no longer resolves a backend to refuse
# non-md"), and it trades a rare stray-file edge case for one fewer duplicated backend parser.

# bc_new_row <target-header-row> <item-cell> <owner> <started> <links> — compose the In Progress row
# BY COLUMN NAME from the target table's own header, never by hardcoded position: a board whose
# schema gains a column must not silently shift every value one cell to the left.
# BOARD-PIPE-ESCAPE T5 (C1): the four cell-derived values are passed via ENVIRON, NEVER `awk -v`.
# `-v` runs awk's OWN escape-sequence processing on the assigned string, so a source `\|` (an escaped
# pipe under the GFM-exact rule bc_cell/bc_col_index implement) is silently rewritten to a bare `|`
# before it ever reaches the `out` string — a byte the caller never asked to change, and one that adds
# a phantom column to the board the moment it is written. `ENVIRON[...]` reads the process environment
# verbatim; no escape processing happens on the way in.
bc_new_row() {
  printf '%s' "$1" | env BC_NR_ITEM="$2" BC_NR_OWNER="$3" BC_NR_STARTED="$4" BC_NR_LINKS="$5" \
    awk -F'|' '
    {
      out = "|"
      for (i = 2; i < NF; i++) {
        h = $i; gsub(/^[ \t]+|[ \t]+$/, "", h)
        v = "—"
        if (h == "Item")    v = ENVIRON["BC_NR_ITEM"]
        if (h == "Owner")   v = ENVIRON["BC_NR_OWNER"]
        if (h == "Started") v = ENVIRON["BC_NR_STARTED"]
        if (h == "Links")   v = ENVIRON["BC_NR_LINKS"]
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
  # THE BRANCH GRAMMAR RUNS HERE — before the board read, before the WIP count, before any network,
  # for the same reason the row grammar does: a refusal that has already pushed is not a refusal.
  # `(detached)` is the one non-ref value this verb mints itself and it is not a branch; it is held
  # to the same grammar as everything else (parentheses are refused), so a detached HEAD must name
  # its branch explicitly rather than have an unusable value written into the CLAIM.
  bc_require_branch "$_branch" "claim --branch" || return 2

  # THE DECLARED SESSION — minted here, offline, before the board read and before any network, for
  # the same reason the two grammars above run here: a hygiene refusal that has already pushed a ref
  # or rewritten the board is not a refusal. `claim` is the ONE verb that mints; every other reads.
  if _session=$(bc_session_id --mint); then :; else return 2; fi

  # BOARD PRECONDITION — refuse before touching the network. `claim` is the act of ENTERING In
  # Progress, so the row must exist and sit in Ready. `--board-already-moved` is the ONE exception
  # and it is not a bypass: the row must ALREADY sit In Progress AND its Links cell must name this
  # exact branch. It exists because this mechanism's own first live claim is made from a branch whose
  # design commit moved the row before the verb existed to do it.
  if [ ! -f "$BC_BOARD" ]; then
    echo "claim: no board at $BC_BOARD (run from the project root, or set BOARD_CLAIM_BOARD;" >&2
    echo "       or, on a hosted tracker, use \`claim-ref\` / \`sparkwright board claim\`)." >&2
    return 2
  fi
  # RETIRED (T3, F5): the declared-backend refusal (S-L5, `bc_backend`) used to sit here. A real
  # BACKLOG.md at $BC_BOARD is now the only precondition, regardless of any declared backend — see
  # the retirement note above `bc_backend`'s old definition.
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
        echo "claim: --board-already-moved was given but the In Progress \`Links\` cell for \`$_row\` does not name branch \`$_branch\` in the canonical form (branch \`<name>\`) (Links = [$(printf '%s' "$_iplinks" | tr -d '[:cntrl:]' | cut -c1-200)])." >&2
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

  # ── WIP — COUNTED FROM THE ORIGIN CLAIM REFS, NEVER FROM THE LOCAL BOARD (B4-CROSS-SESSION-BUDGET)
  # A parallel session's In Progress row lives on ITS branch and is invisible on the local board (the
  # header block records exactly this), and the local board is agent-writable besides — so a local
  # count would let three sessions each see one row and all claim under MAX_WIP=2, failing OPEN
  # against the very sessions it bounds. `refs/claims/*` on origin is the machine-truthful count.
  # ⚠️ IT RUNS BEFORE THE PROBE, and EXCLUDES the row being claimed. Both halves are load-bearing:
  # counted after the probe, the resume path would never reach it; counting the row's own ref, a
  # resume would be refused by the ceiling its own claim contributes to.
  # ⚠️ AND AN UNREACHABLE REMOTE REFUSES: a count of zero read off a remote this process cannot see is
  # the same blind decision the probe refuses to make.
  # A stale claim overcounts, conservatively; `release --stale` is the remedy.
  if [ -f "$BC_GUARD" ]; then
    if _bc_refs=$(git ls-remote "$BC_REMOTE" 'refs/claims/*' 2>/dev/null); then :; else
      bc_unreachable 'refs/claims/*'; return 2
    fi
    _wipn=$(printf '%s\n' "$_bc_refs" | awk -v me="$_ref" '$2 != "" && $2 != me { n++ } END { print n + 0 }')
    if _wipout=$(sh "$BC_GUARD" wip --count "$_wipn" 2>&1); then :; else
      # ANY non-zero refuses — rc 1 (over the ceiling) and rc 2 (a malformed MAX_WIP, a missing
      # value) are both answers that say "do not start a second slice", and neither is a green.
      echo "claim: REFUSED — this machine is at its work-in-progress ceiling." >&2
      printf '%s\n' "$_wipout" | sed 's/^/       /' >&2
      echo "       WIP is counted from \`refs/claims/*\` on $BC_REMOTE (excluding \`$_row\`), against" >&2
      echo "       MAX_WIP in .kit/budget.conf. Finish or release a slice (\`board-claim.sh release\`)," >&2
      echo "       or raise MAX_WIP — which is a ratified act, like every other ceiling in that file." >&2
      echo "       — if this row is held by another session, board-claim.sh check $_row will say so." >&2
      return 2
    fi
  fi

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
      _wassess=$(bc_claim_session "$_txt")
      if [ "$_wassess" = "$_session" ]; then
        echo "claim: held by you since $(bc_field "$_txt" claimed-at) — \`$_row\` on branch '$_branch' ($_held)."
        echo "       Nothing pushed, board NOT edited. This is the resume path, not a new claim."
        return 0
      fi
      # ── A COLD RESUME: SAME CLAIMANT, SAME BRANCH, A NEW SESSION (B2 decision 2) ───────────────
      # The claim ref becomes a small CHAIN — a CHILD commit of the claim that was read, oldest
      # first — so `status` and `resume` can say which sessions have held the row. A child IS a
      # fast-forward (the header's measured face), so NO leading `+`; and the push carries
      # `--force-with-lease=<ref>:<observed>` [sec-8] so it can only ever extend the claim this
      # process actually read. A claim that moved in between is LEFT ALONE.
      # ⚠️ STATED CEILING: two LIVE sessions of one human on one branch look exactly like a resume.
      # Nothing here proves the previous session is dead — it is named, and that is all.
      if [ "$_dry" = 1 ]; then
        echo "claim: DRY RUN — would extend the claim on $_ref with a child commit for session '$_session' (was '$_wassess'); nothing pushed."
        return 0
      fi
      # THE CHILD IS BUILT AND PUSHED FROM AN ISOLATED THROWAWAY DIR (fix round 2), never the
      # caller's clone: the `--depth=1` fetch of the parent would otherwise leave the operator's
      # clone shallow and get their next push rejected. Building the child here needs the parent
      # object present, which the fetch brings in; pushing a child whose parent the remote already
      # has is accepted even from a shallow dir (MEASURED on ubuntu). The dir carries the caller's
      # identity (bc_iso_dir), so `commit-tree` has a committer.
      _rc_gd=$(bc_iso_dir) || { echo "claim: could not create a scratch area to extend the claim." >&2; return 2; }
      if ! git -C "$_rc_gd" fetch --no-tags --depth=1 "$(bc_remote_url)" "$_ref:refs/scratch" >/dev/null 2>&1; then
        rm -rf "$_rc_gd"
        echo "claim: could not fetch the claim at $_ref to extend it; the existing claim is left untouched." >&2
        return 2
      fi
      _rblob=$(printf 'row: %s\nclaimant: %s <%s>\nbranch: %s\nclaimed-at: %s\nsession: %s (declared)\nresumed-at: %s\n' \
                 "$_row" "$_name" "$_email" "$_branch" "$(bc_field "$_txt" claimed-at)" \
                 "$_session" "$_when" | git -C "$_rc_gd" hash-object -w --stdin)
      _rtree=$(printf '100644 blob %s\tCLAIM\n' "$_rblob" | git -C "$_rc_gd" mktree)
      _rcommit=$(printf 'claim %s resumed by session %s\n' "$_row" "$_session" | git -C "$_rc_gd" commit-tree "$_rtree" -p "$_held")
      if KIT_CLAIM_FRONT_DOOR=1 git -C "$_rc_gd" push "$(bc_remote_url)" --force-with-lease="$_ref:$_held" "$_rcommit:$_ref" >/dev/null 2>&1; then
        rm -rf "$_rc_gd"
        echo "claim: OK — \`$_row\` RESUMED on $BC_REMOTE; session '$_wassess' -> '$_session' ($_rcommit)."
        echo "       The claim ref now carries both sessions as a chain; the board is NOT edited."
        echo "       Nothing here proves the previous session is gone — it is named, not judged."
        return 0
      fi
      rm -rf "$_rc_gd"
      echo "claim: REFUSED — the resume push on $_ref was rejected (the lease on $_held did not hold," >&2
      echo "       or the forge refused the update). The existing claim is left untouched." >&2
      echo "       Re-run: this verb re-reads the claim and will extend whatever is there now." >&2
      return 2
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
  # `session:` is DECLARED, never authenticated — the field says so in the blob itself, so a reader
  # of the raw ref cannot mistake it for an identity assertion (B2 decision 1).
  _blob=$(printf 'row: %s\nclaimant: %s <%s>\nbranch: %s\nclaimed-at: %s\nsession: %s (declared)\n' \
            "$_row" "$_name" "$_email" "$_branch" "$_when" "$_session" | git hash-object -w --stdin)
  _tree=$(printf '100644 blob %s\tCLAIM\n' "$_blob" | git mktree)
  _commit=$(printf 'claim %s\n' "$_row" | git commit-tree "$_tree")

  # NO LEADING '+'. The forge's non-fast-forward rejection is the SERVER-SIDE COMPARE-AND-SWAP that
  # makes this a claim rather than a note; a forced refspec would overwrite the very thing being
  # checked and turn the last writer into the winner.
  # KIT_CLAIM_FRONT_DOOR=1 — THE FRONT-DOOR SENTINEL, ON EVERY PUSH THIS SCRIPT MAKES (B2 decision
  # 5). The guard arm denies any push whose refspec destination is `refs/claims/` or
  # `refs/claims-log/`; under `kit-guard install-shims` every child `git` is graded, so without this
  # the arm would deny the exact door its own deny message points at. It is honoured ONLY from the
  # guard's PROCESS environment (typed into a command's text it is refused), and it is a DRIFT
  # CONTROL, not a boundary — an actor who can set the guard's environment can set this too.
  if ! KIT_CLAIM_FRONT_DOOR=1 git push "$BC_REMOTE" "$_commit:$_ref" >/dev/null 2>&1; then
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
  # BOARD-PIPE-ESCAPE T5 (C1): `del`/`ins` are line NUMBERS (safe through `-v`); `newrow` is the
  # COMPOSED ROW TEXT and goes through `ENVIRON` instead, for the same byte-preservation reason as
  # `bc_new_row` above — `-v` would re-run awk's escape processing on the row and turn a source `\|`
  # into a raw `|`, adding a phantom column to the board on every write.
  env BC_NEWROW="$_new" awk -v del="$_rline" -v ins="$_iplast" '
    NR == del { next }
    { print }
    NR == ins { print ENVIRON["BC_NEWROW"] }
  ' "$BC_BOARD" > "$_tmp" && mv "$_tmp" "$BC_BOARD"

  # C3 (§6.3): sanitize what is ECHOED here, never what was WRITTEN above — `_rowtxt`/`_new` already
  # reached the board with their exact bytes; this is display only.
  echo "claim: board edited (UNCOMMITTED — the slice's first commit carries it):"
  echo "-$(printf '%s' "$_rowtxt" | tr -d '[:cntrl:]' | cut -c1-200)"
  echo "+$(printf '%s' "$_new" | tr -d '[:cntrl:]' | cut -c1-200)"
  return 0
}

# ── STALENESS IS PROVEN, OR IT IS NOT CLAIMED (B2 decision 4) ───────────────────────────────────
# TWO forge-visible proofs, plus one line of EVIDENCE that used to be a third and is not:
#   P1  ⚠️ WITHDRAWN AT FIX ROUND 1 (2026-09-16), BY MEASUREMENT. "The claim's branch is ABSENT on
#       origin" was a proof in the first build. Live acceptance falsified it: under `ONE-PUSH-PER-PR`
#       a slice pushes ONCE, at the end, so from `claim` until that push the branch is absent for
#       EVERY HEALTHY IN-BUILD SLICE — `status` rated this kit's own live claim STALE-PROVABLE (P1)
#       and `resume` printed the `--stale` remedy for a slice that was being built at that moment.
#       A test that is true of the healthy case proves nothing. (It was ALSO manufacturable: pushing
#       a branch deletion is an allowed agent call, `D-240819-4` makes deletion a human act by
#       RULING, and the guard face is boarded as `GUARD-PUSH-DELETE-BRANCH-UNCOVERED`.) It is now an
#       EVIDENCE LINE, printed with the sentence that says it is not a verdict. A dead session whose
#       work never reached origin is the human dial's case — by design, not by accident.
#   P2  a PR from that head is MERGED, is NOT cross-repository, and NO PR from that head is OPEN
#       [sec-3]. CLOSED-unmerged is NOT a proof: the branch still exists and one allowed
#       `gh pr close` mints it.
#   P3  the row sits in `## Done` on the DEFAULT BRANCH's board. An agent can push to neither, so a
#       Done row gets there only through a merged, approved PR.
# "No commits since" is NOT a proof — a parked slice is silent and alive — and is never printed as one.
BC_LOG_NS="refs/claims-log"

# The DEFAULT BRANCH is learned from the remote's own HEAD symref, never from `origin/HEAD` — a
# dev-clone's local `origin/HEAD` can mis-point (measured), and every proof below would then be read
# off the wrong branch.
bc_default_branch() {
  _dbo=$(git ls-remote --symref "$BC_REMOTE" HEAD 2>/dev/null) || return 1
  printf '%s\n' "$_dbo" \
    | awk '$1 == "ref:" && $3 == "HEAD" { sub(/^refs\/heads\//, "", $2); print $2; exit }'
}

# EVIDENCE 1 — is the claim's branch on origin? yes | no | unknown (unreachable).
# ⚠️ EVIDENCE ONLY, AND IT DECIDES NOTHING (fix round 1, H2). It was P1 until live acceptance showed
# that `no` is the NORMAL state of a healthy in-build slice under one-push-per-PR. Printed, never
# proved on.
# The branch reaches git as a FULL REF, never as a bare argument: `refs/heads/` cannot be an option.
bc_ev_branch() {
  bc_branch_ok "$1" || { printf 'unknown\n'; return 0; }
  # ⚠️ THE rc IS CAPTURED IN THE `else` BRANCH, NEVER AFTER `fi` — the R-1 class this file already
  # carries a warning about at bc_probe, and it bit again here while this leg was RED: POSIX gives an
  # `if` with no else-clause status 0 when its condition FAILS, so `_evrc=$?` after `fi` read 0 and
  # every ABSENT branch was reported `unknown` — which silently disabled what was then the P1 proof
  # and is now this evidence line.
  if git ls-remote --exit-code "$BC_REMOTE" "refs/heads/$1" >/dev/null 2>&1; then
    printf 'yes\n'; return 0
  else
    _evrc=$?
  fi
  [ "$_evrc" = 2 ] && { printf 'no\n'; return 0; }
  printf 'unknown\n'
}

# EVIDENCE 2 — the PR state for that head. `gh` absent or failing reads `unknown`, NEVER `none`:
# "there is no PR" and "I could not ask" are different facts and only one of them is evidence.
# `--head=<b>` is one token, so the branch can never be read as an option. No `--limit`: a capped
# list could hide the OPEN PR that must refuse.
# bc_gh_repo -> OWNER/REPO for $BC_REMOTE, or empty when it cannot be derived. [fix round 1, L7]
# WITHOUT THIS, `gh pr list` RESOLVES THE REPOSITORY FROM THE CWD's OWN REMOTES — which is not
# necessarily the remote these verbs are reading. A claim read from `$BOARD_CLAIM_REMOTE` could then
# be "proved" stale by a MERGED PR in a DIFFERENT repository (a fork, or whatever `origin` happens
# to be in the directory the verb was run from). Unparseable or non-GitHub reads EMPTY and the
# caller degrades to `unknown` — never a guess, because a guessed repository is how P2 becomes a
# proof about somebody else's work.
bc_gh_repo() {
  _ghu=$(git remote get-url "$BC_REMOTE" 2>/dev/null || printf '%s' "$BC_REMOTE")
  [ -n "$_ghu" ] || return 0
  printf '%s' "$_ghu" \
    | sed -n 's|^.*github\.com[:/]\([A-Za-z0-9._-][A-Za-z0-9._-]*\)/\([A-Za-z0-9._-][A-Za-z0-9._-]*\)$|\1/\2|p' \
    | sed 's/\.git$//' | head -1
}

bc_ev_pr() { # <branch> -> "<display> <p2:yes|no>"
  bc_branch_ok "$1" || { printf 'unknown no\n'; return 0; }
  command -v gh >/dev/null 2>&1 || { printf 'unknown no\n'; return 0; }
  _ghrepo=$(bc_gh_repo)
  [ -n "$_ghrepo" ] || { printf 'unknown no\n'; return 0; }
  if _prf=$(gh pr list --repo "$_ghrepo" --head="$1" --state all --json state,isCrossRepository \
              --jq '.[] | "\(.state) \(.isCrossRepository)"' 2>/dev/null); then :; else
    printf 'unknown no\n'; return 0
  fi
  _prf=$(printf '%s\n' "$_prf" | grep -E '^(OPEN|CLOSED|MERGED) (true|false)$' || true)
  [ -n "$_prf" ] || { printf 'none no\n'; return 0; }
  if printf '%s\n' "$_prf" | grep -q '^OPEN '; then printf 'OPEN no\n'; return 0; fi
  if printf '%s\n' "$_prf" | grep -q '^MERGED false$'; then printf 'MERGED yes\n'; return 0; fi
  if printf '%s\n' "$_prf" | grep -q '^MERGED '; then printf 'MERGED-CROSSREPO no\n'; return 0; fi
  printf 'CLOSED no\n'
}

# EVIDENCE 3 — the row's section on the DEFAULT BRANCH's board. RETIRED the `bc_backend` early-out
# (T3, F5): a project with no real board blob on the default branch already reads `unknown` via the
# `cat-file -s` miss below (the fetch/read degrades naturally), so the backend parse was an
# optimization, never a behavioural requirement — removing it costs one extra fetch on a genuinely
# board-less tree and nothing else. The board blob is fetched into a PID-scoped scratch ref,
# `--depth=1 --no-tags`, and read through a byte bound like every other untrusted blob.
bc_ev_row() { # <row> -> Ready|In Progress|In Review|Blocked|Released|Done|absent|unknown
  _evdb=$(bc_default_branch) || { printf 'unknown\n'; return 0; }
  [ -n "$_evdb" ] || { printf 'unknown\n'; return 0; }
  bc_branch_ok "$_evdb" || { printf 'unknown\n'; return 0; }
  # ISOLATED (fix round 2): the default-branch board is fetched `--depth=1` into a throwaway dir, not
  # the caller's clone, so this read never leaves the operator shallow.
  _ev_gd=$(bc_iso_dir) || { printf 'unknown\n'; return 0; }
  if ! git -C "$_ev_gd" fetch --no-tags --depth=1 "$(bc_remote_url)" "refs/heads/$_evdb:refs/scratch" >/dev/null 2>&1; then
    rm -rf "$_ev_gd"; printf 'unknown\n'; return 0
  fi
  _evbn=$(basename -- "$BC_BOARD")
  if _evsz=$(git -C "$_ev_gd" cat-file -s refs/scratch:"$_evbn" 2>/dev/null); then :; else
    rm -rf "$_ev_gd"; printf 'unknown\n'; return 0
  fi
  case "$_evsz" in ''|*[!0-9]*) rm -rf "$_ev_gd"; printf 'unknown\n'; return 0 ;; esac
  if [ "$_evsz" -gt 1048576 ]; then
    rm -rf "$_ev_gd"; printf 'unknown\n'; return 0
  fi
  _evtmp=$(mktemp)
  git -C "$_ev_gd" show refs/scratch:"$_evbn" > "$_evtmp" 2>/dev/null || true
  rm -rf "$_ev_gd"
  _evsec=$(bc_row_section "$_evtmp" "$1")
  rm -f "$_evtmp"
  printf '%s\n' "${_evsec:-absent}"
}

# THE DURABLE TRACE. Every NON-HOLDER release — proof-backed or forced — pushes an entry to
# `refs/claims-log/<ROW>` BEFORE the delete, as a child of the previous entry when one exists, so
# the namespace reads as a chain per row. It exists because the terminal banner is NOT the control:
# the in-line `KIT_CLAIM_FORCE_RELEASE=` prefix is denied to an agent, but `export` as its own call,
# a copied script and a `make` wrapper are MEASURED-UNCOVERED (pinned as such in
# conformance/agent-autonomy.sh), so a forced release must leave something behind that a human reads
# later. ⚠️ STATED CEILING: `refs/claims-log/*` is one more UNPROTECTED ref. It is a TRACE, NOT
# TAMPER-EVIDENCE — anyone with push rights can delete it, exactly as they can the claim itself.
# The glob B4's WIP count reads (`refs/claims/*`) does not match this namespace (legged).
bc_log_release() { # <row> <proof> <reason> <released-sha> -> rc 0 logged · 1 could not log
  _lgref="$BC_LOG_NS/$1"
  _lgwho="$(git config user.name 2>/dev/null || true) <$(git config user.email 2>/dev/null || true)>"
  _lgreason=$(printf '%s' "$3" | tr -d '[:cntrl:]' | cut -c1-200)
  # ISOLATED (fix round 2): built and pushed from a throwaway dir. When a previous entry exists it is
  # fetched `--depth=1` (the parent, so the log stays a chain) — which leaves THAT dir shallow, but
  # the child's parent is already on the remote, so the push is accepted (MEASURED on ubuntu). The
  # first entry does no fetch, so its dir is not shallow and the orphan push is accepted. Either way
  # the caller's clone is never touched.
  _lg_gd=$(bc_iso_dir) || return 1
  _lgblob=$(printf 'row: %s\nreleased-by: %s\nat: %s\nproof: %s\nreason: %s\nreleased-sha: %s\n' \
              "$1" "$_lgwho" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$2" "$_lgreason" "$4" \
            | git -C "$_lg_gd" hash-object -w --stdin) || { rm -rf "$_lg_gd"; return 1; }
  _lgtree=$(printf '100644 blob %s\tLOG\n' "$_lgblob" | git -C "$_lg_gd" mktree) || { rm -rf "$_lg_gd"; return 1; }
  if git -C "$_lg_gd" fetch --no-tags --depth=1 "$(bc_remote_url)" "$_lgref:refs/scratch" >/dev/null 2>&1; then
    _lgparent=$(git -C "$_lg_gd" rev-parse refs/scratch 2>/dev/null || true)
  else
    _lgparent=""
  fi
  if [ -n "$_lgparent" ]; then
    _lgcommit=$(printf 'release %s (%s)\n' "$1" "$2" | git -C "$_lg_gd" commit-tree "$_lgtree" -p "$_lgparent") || { rm -rf "$_lg_gd"; return 1; }
  else
    _lgcommit=$(printf 'release %s (%s)\n' "$1" "$2" | git -C "$_lg_gd" commit-tree "$_lgtree") || { rm -rf "$_lg_gd"; return 1; }
  fi
  if KIT_CLAIM_FRONT_DOOR=1 git -C "$_lg_gd" push "$(bc_remote_url)" "$_lgcommit:$_lgref" >/dev/null 2>&1; then
    rm -rf "$_lg_gd"
    return 0
  fi
  rm -rf "$_lg_gd"
  return 1
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

  # ── --stale IS A PROOF OBLIGATION, NOT A WORD (B2 decision 4) ─────────────────────────────────
  # A `--stale` release is the one route that removes SOMEONE ELSE's claim, so it must show its work.
  # The proofs are gathered and PRINTED whether they hold or not: a refusal that does not say what it
  # looked at cannot be argued with, and the human dial below has to be an informed act.
  _proof=""
  if [ "$_stale" = 1 ]; then
    _sbranch=$(bc_field "$_txt" branch)
    _evb=$(bc_ev_branch "$_sbranch")
    _evp=$(bc_ev_pr "$_sbranch"); _evpdisp=${_evp% *}; _evp2=${_evp##* }
    _evr=$(bc_ev_row "$_row")
    echo "release: evidence for \`$_row\` (branch '$_sbranch'):"
    echo "         branch on origin: $_evb"
    echo "         pr: $_evpdisp"
    echo "         board: $_evr"
    # `if`, not `[ … ] && …`: under `set -e` a false test is a failing simple command and the verb
    # would exit mid-decision (measured in `status`, fixed in both places).
    # ⚠️ "BRANCH ABSENT" IS EVIDENCE, NOT A PROOF (fix round 1, H2 — falsified by live acceptance).
    # Under `ONE-PUSH-PER-PR` a slice pushes ONCE, at the end, so from `claim` until that push the
    # branch is absent from origin for EVERY HEALTHY IN-BUILD SLICE — and this verb duly rated this
    # kit's own live claim releasable while the builder was mid-build. A test that is true of the
    # healthy case cannot be a proof of death. It stays printed, because it is the fact a human
    # needs; it no longer decides anything. The proofs are exactly P2 and P3.
    if [ "$_evp2" = yes ];                       then _proof=P2; fi
    if [ -z "$_proof" ] && [ "$_evr" = Done ];   then _proof=P3; fi
    if [ "$_evb" = no ]; then
      echo "         (an absent branch is NOT a proof: under one-push-per-PR every in-build slice's"
      echo "          branch is absent from origin until its final push. Evidence, not a verdict.)"
    fi
    _force="${KIT_CLAIM_FORCE_RELEASE:-}"
    if [ -z "$_proof" ] && [ -n "$_force" ]; then
      if [ "${#_force}" -lt 10 ]; then
        echo "release: REFUSED — KIT_CLAIM_FORCE_RELEASE must carry a reason of at least 10 characters." >&2
        echo "         The reason is written to $BC_LOG_NS/$_row and read by a human later; 'x' is not one." >&2
        return 2
      fi
      _proof=FORCED
    fi
    if [ -z "$_proof" ]; then
      echo "release: REFUSED — nothing here PROVES \`$_row\` is stale, and a claim that cannot be" >&2
      echo "         shown to be dead is treated as alive. ('No commits since' is not a proof: a" >&2
      echo "         parked slice is silent and alive.)" >&2
      echo "         If you know the holder is gone, say so and it is recorded:" >&2
      echo "           KIT_CLAIM_FORCE_RELEASE=\"<reason, 10+ chars>\" sh scripts/board-claim.sh release $_row --stale" >&2
      return 1
    fi
    if [ "$_proof" = FORCED ]; then
      echo "release: ⚠️  FORCED — released with NO proof of staleness, on the stated reason:"
      echo "         \"$(printf '%s' "$_force" | tr -d '[:cntrl:]' | cut -c1-200)\""
      echo "         This is recorded in $BC_LOG_NS/$_row, because a terminal banner is not a control."
    else
      echo "release: proof $_proof — proceeding."
    fi
    # THE LOG IS WRITTEN BEFORE THE DELETE, and a log that cannot be written REFUSES the release: an
    # untraceable removal of someone else's claim is exactly the act this entry exists to make loud.
    if bc_log_release "$_row" "$_proof" "${_force:-stale claim released on proof $_proof}" "$_sha"; then
      echo "release: logged to $BC_LOG_NS/$_row (proof $_proof)."
    else
      echo "release: REFUSED — could not write the release record to $BC_LOG_NS/$_row, so the claim is" >&2
      echo "         left alone. A non-holder release that leaves no trace is the thing this record exists" >&2
      echo "         to prevent; fix the push (or release by hand and say so on the board)." >&2
      return 2
    fi
  fi

  # COMPARE-AND-SWAP ON THE DELETE. The lease's old-value is the sha this process OBSERVED, so a
  # claim that moved between the read and the delete is left ALONE — the delete can only ever remove
  # the exact claim that was inspected, never a newer one someone else has since taken.
  if KIT_CLAIM_FRONT_DOOR=1 git push "$BC_REMOTE" --force-with-lease="$_ref:$_sha" ":$_ref" >/dev/null 2>&1; then
    echo "release: OK — $_ref deleted on $BC_REMOTE (was $_sha)"
    return 0
  fi
  # ⚠️ THE RECORD WAS ALREADY PUSHED, SO A FAILED DELETE MUST BE COMPENSATED (fix round 1, M3).
  # The log is written BEFORE the delete on purpose — a release that leaves no trace is what the
  # record exists to prevent — but that ordering means a delete which then FAILS leaves
  # `refs/claims-log/<ROW>` asserting a release that never happened. MEASURED REAL, not theoretical:
  # `shim-coverage.sh` case 5 shows the delete being refused under `install-shims` (the force-push
  # rule), so the first build produced exactly that false record on a real run. The log is
  # append-only by design, so the cure is a COMPENSATING ENTRY rather than an edit: `<proof>-FAILED`
  # with `released-sha: (not deleted)`. A reader who sees only the first entry is wrong; a reader
  # who reads the last one is right, which is the property `status` and `resume` rely on.
  if [ "$_stale" = 1 ] && [ -n "${_proof:-}" ]; then
    if bc_log_release "$_row" "$_proof-FAILED" "delete refused after the record was written: $_ref left in place" "(not deleted)"; then
      echo "release: a compensating $_proof-FAILED entry was appended to $BC_LOG_NS/$_row." >&2
    else
      echo "release: ⚠️  AND the compensating record could not be written either — $BC_LOG_NS/$_row" >&2
      echo "         still claims a release that did NOT happen. Correct it by hand." >&2
    fi
  fi
  echo "release: FAILED — could not delete $_ref at $BC_REMOTE (the lease on $_sha did not hold, or the push was refused)." >&2
  echo "         ⚠️  A release record was already written to $BC_LOG_NS/$_row BEFORE this delete was" >&2
  echo "         attempted (that ordering is deliberate); the claim ref is UNCHANGED." >&2
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
      # B2: the DECLARED session that holds the row. Additive — a claim written before this field
      # existed reads `unknown`, and `backlog-presence.sh --claims` reads `^claim-branch: ` only, so
      # the extra line is inert to it (proven by running that arm, not by reading it).
      printf 'claim-session: %s\n' "$(bc_claim_session "$_txt")"
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

# ── status — WHO HOLDS WHAT, RIGHT NOW, WITH ITS EVIDENCE (B2 decision 3) ───────────────────────
# One block per claim on origin. `check --all` stays the terse view; this is the one a conductor
# runs at a cold start, so every fact NAMES ITS SOURCE or reads `unknown`, and the reading is LIVE
# unless one of decision 4's proofs fires. It is READ-ONLY: no ref, no board, no file is written.
# ⚠️ THE CHAIN WALK IS BOUNDED (`-n 32`). A claim ref is unprotected — anyone with push rights can
# extend it — so an unbounded walk would make the cold-start verb the cheapest denial of service in
# the kit. 32 sessions of one row is already far past anything real.
BC_CHAIN_MAX=32
# ⚠️ AND IT MUST BE DEFINED BEFORE `bc_session_chain` AND `bc_last_log` USE IT AS A FETCH DEPTH —
# the walk bound and the transfer bound are now the same number on purpose (M4).
bc_session_chain() { # <ref> -> "s1 -> s2 -> s3" (oldest first), or unknown
  # ⚠️ `--depth=$BC_CHAIN_MAX` DOES TWO JOBS (fix round 1, M4), and the fetch is now ISOLATED into a
  # throwaway dir (fix round 2) so it never leaves the caller's clone shallow.
  #   (a) IT BOUNDS THE TRANSFER — anyone with push rights could otherwise make the cold-start verb
  #       download an arbitrarily long history to print 32 lines.
  #   (b) IT DEEPENS relative to the depth=1 reads: with the fetch isolated, this dir is fresh and
  #       the depth-32 fetch simply brings the top 32 commits — no interaction with any earlier
  #       shallow boundary (fix round 1 fought that in the shared clone; there is no shared clone
  #       now). The walk is bounded to `$BC_CHAIN_MAX` for the same reason as the fetch.
  _sc_gd=$(bc_iso_dir) || { printf 'unknown\n'; return 0; }
  if ! git -C "$_sc_gd" fetch --no-tags --depth="$BC_CHAIN_MAX" "$(bc_remote_url)" "$1:refs/scratch" >/dev/null 2>&1; then
    rm -rf "$_sc_gd"; printf 'unknown\n'; return 0
  fi
  _chain=""
  for _cc in $(git -C "$_sc_gd" log -n "$BC_CHAIN_MAX" --format=%H refs/scratch 2>/dev/null); do
    _cct=$(git -C "$_sc_gd" show "$_cc:CLAIM" 2>/dev/null | head -c "$BC_CLAIM_MAX_BYTES" || true)
    _ccs=$(bc_claim_session "$_cct")
    if [ -z "$_chain" ]; then _chain="$_ccs"; else _chain="$_ccs -> $_chain"; fi
  done
  rm -rf "$_sc_gd"
  printf '%s\n' "${_chain:-unknown}"
}

# bc_last_log <row> -> the last claims-log entry for the row as one line, or empty.
bc_last_log() {
  _ll_gd=$(bc_iso_dir) || return 0
  if ! git -C "$_ll_gd" fetch --no-tags --depth=1 "$(bc_remote_url)" "$BC_LOG_NS/$1:refs/scratch" >/dev/null 2>&1; then
    rm -rf "$_ll_gd"; return 0
  fi
  _lltxt=$(git -C "$_ll_gd" show refs/scratch:LOG 2>/dev/null | head -c "$BC_CLAIM_MAX_BYTES" || true)
  rm -rf "$_ll_gd"
  [ -n "$_lltxt" ] || return 0
  printf 'released by %s at %s, proof %s — %s\n' \
    "$(bc_field "$_lltxt" released-by)" "$(bc_field "$_lltxt" at)" \
    "$(bc_field "$_lltxt" proof)" "$(bc_field "$_lltxt" reason)"
}

do_status() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -*) echo "status: unknown option '$1'" >&2; bc_usage; return 2 ;;
      *)  echo "status: takes no arguments (it renders every claim on $BC_REMOTE)" >&2; return 2 ;;
    esac
  done
  if _stout=$(git ls-remote "$BC_REMOTE" 'refs/claims/*' 2>/dev/null); then :; else
    bc_unreachable 'refs/claims/*'; return 2
  fi
  if [ -z "$_stout" ]; then echo "status: no claims on $BC_REMOTE"; return 1; fi
  # A TEMP FILE, NOT A PIPE — POSIX runs a pipeline's `while` body in a subshell, so the counter
  # would come back zero (the same shape `check --all` uses, for the same reason).
  _streflist=$(mktemp)
  printf '%s\n' "$_stout" | awk '{print $2}' > "$_streflist"
  _stn=0
  while IFS= read -r _stref; do
    [ -n "$_stref" ] || continue
    _strow=${_stref#refs/claims/}
    bc_row_ok "$_strow" || continue
    _stn=$((_stn + 1))
    _sttxt=$(bc_read_claim "$_stref" 2>/dev/null || true)
    echo ""
    echo "claim: \`$_strow\` ($_stref)"
    if [ -z "$_sttxt" ]; then
      echo "  holder:        (CLAIM unreadable or malformed — refused at read)"
      echo "  reading:       unknown (nothing here can be read, so nothing is judged)"
      continue
    fi
    _stbranch=$(bc_field "$_sttxt" branch)
    echo "  holder:        $(bc_field "$_sttxt" claimant)"
    echo "  session chain: $(bc_session_chain "$_stref")  (declared, never authenticated)"
    echo "  branch:        $_stbranch"
    echo "  claimed-at:    $(bc_field "$_sttxt" claimed-at)"
    _stresumed=$(bc_field "$_sttxt" resumed-at)
    # ⚠️ `if`, NOT `[ … ] && echo`: under `set -e` a false test IS a failing simple command and the
    # whole verb exits mid-block. Measured — it truncated every rendering at this line.
    if [ -n "$_stresumed" ]; then echo "  resumed-at:    $_stresumed"; fi
    _stevb=$(bc_ev_branch "$_stbranch")
    _stevp=$(bc_ev_pr "$_stbranch"); _stevpd=${_stevp% *}; _stevp2=${_stevp##* }
    _stevr=$(bc_ev_row "$_strow")
    echo "  branch on origin: $_stevb"
    echo "  pr: $_stevpd"
    echo "  board: $_stevr"
    # `if`, not `[ … ] && …`, for the same `set -e` reason as the resumed-at line above.
    # ⚠️ P1 IS GONE FROM THIS DECISION (fix round 1, H2). This rendering is the one a conductor reads
    # at a cold start, and with "branch absent" as a proof it rated every mid-build slice — including
    # this kit's own, measured at live acceptance — `STALE-PROVABLE`, beside an instruction to delete
    # its claim. A reading that names a release command is a suggestion; it must never be made about
    # a healthy slice. Branch-absent now reads LIVE, *with its reason*, and prints no instruction.
    _stproof=""
    if [ "$_stevp2" = yes ];                         then _stproof=P2; fi
    if [ -z "$_stproof" ] && [ "$_stevr" = Done ];   then _stproof=P3; fi
    if [ -n "$_stproof" ]; then
      echo "  reading:       STALE-PROVABLE ($_stproof) — \`board-claim.sh release $_strow --stale\` will release it"
    elif [ "$_stevb" = no ]; then
      echo "  reading:       LIVE (branch not on origin — normal before the slice's push; not a proof)"
    else
      echo "  reading:       LIVE (nothing on the forge proves the holder is gone)"
    fi
    _stlog=$(bc_last_log "$_strow")
    if [ -n "$_stlog" ]; then echo "  last release:  $_stlog"; fi
  done < "$_streflist"
  rm -f "$_streflist"
  echo ""
  echo "status: $_stn claim(s) on $BC_REMOTE"
  return 0
}

# ── claim-ref ───────────────────────────────────────────────────────────────────────────────────
# Backend-agnostic ref-only claim (T4, §6a S-5): takes `refs/claims/<ROW-ID>` and NEVER reads or
# writes a board — no BC_BOARD check, no row-section precondition, no board-move. The non-fast-
# forward rejection on the push IS the atomic lock, on every backend, because a git ref is the one
# thing every backend equally has none of an opinion about. Deliberately SIMPLER than `claim`'s own
# probe: it does not distinguish a self-resume from a foreign hold — ANY existing ref refuses here
# (rc 3), even one this identity already holds. A resume is `claim`'s concern (the board-bound verb,
# which a human/agent still uses directly on `md`); `claim-ref`'s contract is "the ref is the lock,
# full stop" and re-claiming is `release-ref` then `claim-ref` again.
do_claim_ref() {
  _row=""; _branch=""; _then=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --branch) [ $# -ge 2 ] || { echo "claim-ref: --branch needs a value" >&2; return 2; }; _branch=$2; shift 2 ;;
      --then)   [ $# -ge 2 ] || { echo "claim-ref: --then needs a value" >&2; return 2; }; _then=$2; shift 2 ;;
      -*)       echo "claim-ref: unknown option '$1'" >&2; bc_usage; return 2 ;;
      *)        [ -z "$_row" ] || { echo "claim-ref: one row id, not two" >&2; return 2; }; _row=$1; shift ;;
    esac
  done
  bc_require_row "$_row" || return 2
  _ref="refs/claims/$_row"

  [ -n "$_branch" ] || _branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "(detached)")
  bc_require_branch "$_branch" "claim-ref --branch" || return 2

  if _session=$(bc_session_id --mint); then :; else return 2; fi

  _name=$(git config user.name  2>/dev/null || true)
  _email=$(git config user.email 2>/dev/null || true)
  if [ -z "$_name" ] || [ -z "$_email" ]; then
    echo "claim-ref: no git identity (user.name / user.email) — the claim's committer IS the claimant." >&2
    return 2
  fi
  _when=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # THE FORGE PROBE (same else-branch rc capture as bc_probe's own R-1 note — see that function).
  if _held=$(bc_probe "$_ref"); then
    _txt=$(bc_read_claim "$_ref" || true)
    if [ -n "$_txt" ]; then
      echo "claim-ref: $(bc_holder_line "$_txt")" >&2
    else
      echo "claim-ref: $_ref exists on $BC_REMOTE at $_held but its CLAIM could not be read." >&2
    fi
    echo "           Row \`$_row\` is ALREADY CLAIMED (ref-only). Release it (\`release-ref $_row --stale\`) or take another row." >&2
    return 3
  else
    _prc=$?
    if [ "$_prc" != 2 ]; then bc_unreachable "$_ref"; return 2; fi
  fi

  _blob=$(printf 'row: %s\nclaimant: %s <%s>\nbranch: %s\nclaimed-at: %s\nsession: %s (declared)\n' \
            "$_row" "$_name" "$_email" "$_branch" "$_when" "$_session" | git hash-object -w --stdin)
  _tree=$(printf '100644 blob %s\tCLAIM\n' "$_blob" | git mktree)
  _commit=$(printf 'claim-ref %s\n' "$_row" | git commit-tree "$_tree")

  if ! KIT_CLAIM_FRONT_DOOR=1 git push "$BC_REMOTE" "$_commit:$_ref" >/dev/null 2>&1; then
    _txt=$(bc_read_claim "$_ref" || true)
    if [ -n "$_txt" ]; then
      echo "claim-ref: $(bc_holder_line "$_txt")" >&2
      echo "           The push was REJECTED (non-fast-forward): row \`$_row\` was claimed between this" >&2
      echo "           process's probe and its push. That rejection is the mechanism working." >&2
      return 3
    fi
    echo "claim-ref: pushing $_ref to $BC_REMOTE failed and no claim could be read back. Nothing was moved." >&2
    return 2
  fi
  echo "claim-ref: OK — \`$_row\` claimed on $BC_REMOTE as $_ref ($_commit)"
  echo "           claimant '$_name <$_email>' · branch '$_branch' · at $_when"

  [ -n "$_then" ] || return 0

  # ── ORDER + COMPENSATION (§6a S-5): the ref is taken FIRST; a FAILURE of the FOLLOWING step
  # (the tracker-side write lane 2's `board.sh` runs) is compensated by deleting the ref we just
  # pushed, under a lease on the EXACT sha we pushed, so a failed tracker write never leaves an
  # orphaned claim ref behind that nothing else will ever clean up.
  # SECURITY: `--then`'s value is `sh -c`'d, exactly like board-drift.sh's `BOARD_DRIFT_PR_STATE`
  # probe and release-tag.sh's `RELEASE_TAG_CI_PROBE` — set it only from a trusted CALLER (lane 2's
  # `board.sh`, a script, not board/PR-sourced text), never from repo/PR input.
  if sh -c "$_then"; then
    echo "claim-ref: OK — the following step succeeded; \`$_row\` stays claimed."
    return 0
  else
    _then_rc=$?
  fi
  echo "claim-ref: the following step FAILED (rc=$_then_rc) — compensating by deleting $_ref." >&2
  if KIT_CLAIM_FRONT_DOOR=1 git push "$BC_REMOTE" --force-with-lease="$_ref:$_commit" ":$_ref" >/dev/null 2>&1; then
    echo "claim-ref: compensated — $_ref deleted (was $_commit). The claim is fully undone." >&2
    return 1
  fi
  echo "claim-ref: FAILED — the following step failed AND the compensating delete of $_ref also failed." >&2
  echo "           The claim ref is LEFT IN PLACE at $_commit. Run \`board-claim.sh release-ref $_row\` by" >&2
  echo "           hand to finish the compensation." >&2
  return 1
}

# ── release-ref ─────────────────────────────────────────────────────────────────────────────────
# Backend-agnostic ref-only release (T4, §6a S-5): the reverse of claim-ref, and reversed ORDER too
# when `--then` is given — see the header note. Reuses `release`'s holder-check and `--stale`
# machinery verbatim in shape, but its PROOF SET is narrower than `release --stale`'s: P2 (a merged,
# non-cross-repo, non-open PR) only. `release --stale`'s P3 (the md board's Done section) is
# deliberately NOT reused here — it is an md-specific fact, and this verb's whole contract is
# backend-agnosticism; leaning on a board read here would smuggle an md assumption back into the one
# primitive that is supposed to have none.
do_release_ref() {
  _row=""; _stale=0; _then=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --stale) _stale=1; shift ;;
      --then)  [ $# -ge 2 ] || { echo "release-ref: --then needs a value" >&2; return 2; }; _then=$2; shift 2 ;;
      -*)      echo "release-ref: unknown option '$1'" >&2; bc_usage; return 2 ;;
      *)       [ -z "$_row" ] || { echo "release-ref: one row id, not two" >&2; return 2; }; _row=$1; shift ;;
    esac
  done
  bc_require_row "$_row" || return 2
  _ref="refs/claims/$_row"

  if _sha=$(bc_probe "$_ref"); then
    :
  else
    _prc=$?
    if [ "$_prc" = 2 ]; then
      echo "release-ref: no claim on \`$_row\` at $BC_REMOTE ($_ref does not exist) — nothing to release." >&2
      return 1
    fi
    bc_unreachable "$_ref"; return 2
  fi

  _txt=$(bc_read_claim "$_ref" || true)
  _holder=$(bc_field "$_txt" claimant)
  _name=$(git config user.name 2>/dev/null || true)
  _email=$(git config user.email 2>/dev/null || true)
  _me="$_name <$_email>"
  if [ -n "$_txt" ]; then
    echo "release-ref: $(bc_holder_line "$_txt")"
    if [ "$_holder" != "$_me" ] && [ "$_stale" != 1 ]; then
      echo "release-ref: REFUSED — \`$_row\` is held by '$_holder', not by you ('$_me')." >&2
      echo "             Releasing another session's live claim is a deliberate act: pass --stale, and say why." >&2
      return 1
    fi
  else
    echo "release-ref: $_ref exists on $BC_REMOTE at $_sha but its CLAIM is unreadable or malformed."
    if [ "$_stale" != 1 ]; then
      echo "release-ref: REFUSED — \`$_row\` carries a claim whose holder cannot be read, so it cannot be" >&2
      echo "             shown to be yours ('$_me'). Deleting it is a deliberate act: pass --stale, and say why." >&2
      return 1
    fi
  fi

  # ⚠️ PROOF IS EVALUATED HERE (a pure read, no side effect), BUT NOT YET LOGGED (security fix round,
  # M-2). Logging used to happen in THIS block, before `--then` ran below — so a `--then` failure
  # (the tracker-side step) still returned refused, but `refs/claims-log/<ROW>` already carried an
  # entry ASSERTING a release that never happened, with no `-FAILED` compensation (the exact class
  # `bc_log_release`'s own header exists to prevent, just reached via a NEW ordering bug). The write
  # is moved to AFTER `--then` succeeds, below; refusing here (no proof, or a too-short force reason)
  # still happens BEFORE `--then` ever runs, so a doomed release never touches the tracker either.
  _proof=""
  if [ "$_stale" = 1 ]; then
    _sbranch=$(bc_field "$_txt" branch)
    _evb=$(bc_ev_branch "$_sbranch")
    _evp=$(bc_ev_pr "$_sbranch"); _evpdisp=${_evp% *}; _evp2=${_evp##* }
    echo "release-ref: evidence for \`$_row\` (branch '$_sbranch'):"
    echo "             branch on origin: $_evb"
    echo "             pr: $_evpdisp"
    if [ "$_evp2" = yes ]; then _proof=P2; fi
    if [ "$_evb" = no ]; then
      echo "             (an absent branch is NOT a proof — evidence, not a verdict, same as \`release --stale\`.)"
    fi
    _force="${KIT_CLAIM_FORCE_RELEASE:-}"
    if [ -z "$_proof" ] && [ -n "$_force" ]; then
      if [ "${#_force}" -lt 10 ]; then
        echo "release-ref: REFUSED — KIT_CLAIM_FORCE_RELEASE must carry a reason of at least 10 characters." >&2
        echo "             The reason is written to $BC_LOG_NS/$_row and read by a human later; 'x' is not one." >&2
        return 2
      fi
      _proof=FORCED
    fi
    if [ -z "$_proof" ]; then
      echo "release-ref: REFUSED — nothing here PROVES \`$_row\` is stale (the ref-only proof set is P2 only)." >&2
      echo "             If you know the holder is gone, say so and it is recorded:" >&2
      echo "               KIT_CLAIM_FORCE_RELEASE=\"<reason, 10+ chars>\" sh scripts/board-claim.sh release-ref $_row --stale" >&2
      return 1
    fi
    if [ "$_proof" = FORCED ]; then
      echo "release-ref: ⚠️  FORCED — released with NO proof of staleness, on the stated reason:"
      echo "             \"$(printf '%s' "$_force" | tr -d '[:cntrl:]' | cut -c1-200)\""
    else
      echo "release-ref: proof $_proof — proceeding."
    fi
  fi

  # ── ORDER + COMPENSATION, REVERSED (§6a S-5): unlike claim-ref, the FOLLOWING step here (the
  # tracker-side release lane 2's `board.sh` runs) goes FIRST — this ref is the LOCK and must only be
  # dropped once that release has actually happened. A `--then` failure leaves the ref UNTOUCHED
  # (nothing was released yet, so nothing to compensate, and NOTHING IS LOGGED -- M-2); a `--then`
  # SUCCESS followed by a FAILED ref-delete is a failed compensation and exits non-zero naming the
  # recovery verb.
  if [ -n "$_then" ]; then
    if sh -c "$_then"; then
      :
    else
      _then_rc=$?
      echo "release-ref: the following (tracker-side) step FAILED (rc=$_then_rc) — $_ref is left UNTOUCHED (nothing was released, nothing was logged)." >&2
      return 1
    fi
  fi

  # THE LOG IS WRITTEN HERE, ONLY NOW (M-2): AFTER any `--then` step has already succeeded, and
  # BEFORE the delete below -- the "log precedes the delete" invariant `bc_log_release`'s own header
  # states still holds; what moved is "log precedes a `--then` that might still fail", which is gone.
  if [ "$_stale" = 1 ]; then
    if bc_log_release "$_row" "$_proof" "${_force:-stale claim released on proof $_proof}" "$_sha"; then
      echo "release-ref: logged to $BC_LOG_NS/$_row (proof $_proof)."
    else
      echo "release-ref: REFUSED — could not write the release record to $BC_LOG_NS/$_row, so the claim is" >&2
      echo "             left alone." >&2
      return 2
    fi
  fi

  if KIT_CLAIM_FRONT_DOOR=1 git push "$BC_REMOTE" --force-with-lease="$_ref:$_sha" ":$_ref" >/dev/null 2>&1; then
    echo "release-ref: OK — $_ref deleted on $BC_REMOTE (was $_sha)"
    return 0
  fi
  if [ -n "$_then" ]; then
    echo "release-ref: FAILED — the tracker-side step SUCCEEDED but deleting $_ref then failed (the lease" >&2
    echo "             on $_sha did not hold, or the push was refused). This is a FAILED COMPENSATION:" >&2
    echo "             the tracker already shows the release; run \`board-claim.sh release-ref $_row\` by" >&2
    echo "             hand (no --then) to retry just the ref delete." >&2
    return 1
  fi
  if [ "$_stale" = 1 ] && [ -n "${_proof:-}" ]; then
    if bc_log_release "$_row" "$_proof-FAILED" "delete refused after the record was written: $_ref left in place" "(not deleted)"; then
      echo "release-ref: a compensating $_proof-FAILED entry was appended to $BC_LOG_NS/$_row." >&2
    else
      echo "release-ref: ⚠️  AND the compensating record could not be written either — $BC_LOG_NS/$_row" >&2
      echo "             still claims a release that did NOT happen. Correct it by hand." >&2
    fi
  fi
  echo "release-ref: FAILED — could not delete $_ref at $BC_REMOTE (the lease on $_sha did not hold, or the push was refused)." >&2
  return 1
}

# ── ORACLE MARKER: selftest() and everything below is the non-vacuity oracle region. ─────────────
selftest() {
  bc_st_fail=0

  # ---- leg (parser): bc_cell/bc_col_index/bc_row_line are GFM-exact on the odd-backslash-run rule
  # (BOARD-PIPE-ESCAPE T4) — no fixture clone needed, these are pure text functions. Expected values
  # are hand-derived from the SAME rule backlog-lib.sh's cell()/col_index() implement (GFM spec: a `|`
  # delimits a cell iff it is NOT preceded by an odd-length run of `\`); the behavioural bc_cell≡cell()
  # drift gate is a separate task (T6) — this leg only proves bc_cell is correct in isolation.
  if [ "$(bc_cell '| x | a\|b | y |' 2)" = 'a\|b' ]; then
    bc_pass "leg parser/bc_cell: a single escaped pipe (odd run) keeps joining the cell"
  else
    bc_fail "leg parser/bc_cell: a single escaped pipe wrongly split the cell — got [$(bc_cell '| x | a\|b | y |' 2)]"
  fi
  if [ "$(bc_cell '| x | a\\|b | y |' 2)" = 'a\\' ] && [ "$(bc_cell '| x | a\\|b | y |' 3)" = 'b' ]; then
    bc_pass "leg parser/bc_cell: a doubled backslash (even run) before a pipe is a REAL delimiter"
  else
    bc_fail "leg parser/bc_cell: a doubled backslash before a pipe was wrongly treated as escaping the pipe"
  fi
  if [ "$(bc_cell '| x | a\\\|b | y |' 2)" = 'a\\\|b' ]; then
    bc_pass "leg parser/bc_cell: a triple backslash (odd run) before a pipe escapes it again"
  else
    bc_fail "leg parser/bc_cell: a triple backslash run was not recognized as escaping the pipe — got [$(bc_cell '| x | a\\\|b | y |' 2)]"
  fi
  if [ "$(bc_cell '| x | y\\ |' 2)" = 'y\\' ]; then
    bc_pass "leg parser/bc_cell: a trailing backslash at the end of the LAST cell is preserved, not dropped"
  else
    bc_fail "leg parser/bc_cell: a trailing backslash in the last cell was mishandled — got [$(bc_cell '| x | y\\ |' 2)]"
  fi
  if [ "$(bc_cell '| x | y\|z |' 2)" = 'y\|z' ]; then
    bc_pass "leg parser/bc_cell: an escaped pipe inside the LAST cell does not spill into a phantom column"
  else
    bc_fail "leg parser/bc_cell: an escaped pipe in the last cell was mis-split — got [$(bc_cell '| x | y\|z |' 2)]"
  fi
  if [ "$(bc_col_index '| Item | A\|B | Owner |' Owner)" = 3 ]; then
    bc_pass "leg parser/bc_col_index: an escaped pipe in a HEADER cell does not shift a later column's index"
  else
    bc_fail "leg parser/bc_col_index: header escaping shifted the resolved index — got [$(bc_col_index '| Item | A\|B | Owner |' Owner)] (want 3)"
  fi
  bc_ptmp=$(mktemp -d)
  printf '## Ready\n| Item | Owner |\n|---|---|\n| \\|early`ROW-9`text | — |\n' > "$bc_ptmp/BACKLOG.md"
  if [ "$(bc_row_line "$bc_ptmp/BACKLOG.md" Ready ROW-9)" = 4 ]; then
    bc_pass "leg parser/bc_row_line: an escaped pipe ahead of the id in the Item cell does not hide the row"
  else
    bc_fail "leg parser/bc_row_line: a row with an escaped pipe before its id was not found (fail-closed miss) — got [$(bc_row_line "$bc_ptmp/BACKLOG.md" Ready ROW-9)]"
  fi
  rm -rf "$bc_ptmp"

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

  # ⚠️ THE BARE REMOTE'S PATH IS GITHUB-SHAPED ON PURPOSE (fix round 1, L7). `bc_gh_repo` derives
  # `OWNER/REPO` from the remote's URL so `gh pr list` is pinned with `--repo` instead of resolving
  # whatever repository the CWD happens to point at. A fixture remote at `$bc_base/remote.git` would
  # make that derivation return EMPTY, and every P2 leg would then be exercising the
  # `unknown`-degradation path while appearing to test the proof. Putting the bare repo under a real
  # `github.com/<owner>/<repo>.git` directory path exercises the REAL derivation on a REAL url
  # string, with real pushes — no stubbing of the thing under test.
  bc_remote_dir="$bc_base/github.com/fixture-owner/fixture-repo.git"
  mkdir -p "$(dirname -- "$bc_remote_dir")"
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

  # ---- leg (a2): A READ MUST NOT SHALLOW-POISON THE CALLER'S CLONE (fix round 2, the CI red) -----
  # THE NON-VACUITY ANCHOR THE OTHER LEGS LACKED. Every read (`check`/`status`/`release`/`claim`)
  # bounds its fetch with `--depth`, and a `--depth` fetch writes `.git/shallow` into the repo it
  # fetches INTO. When that repo was the caller's own clone, its NEXT push was rejected by a remote
  # that enforces `receive.shallowUpdate` ("shallow update not allowed") — ubuntu git DOES; macOS
  # git 2.48 does NOT, which is the whole reason this shipped green twice and only died on CI. So:
  # after A has read a claim (leg a already ran `check`-shaped reads through the claim path), A's
  # clone must NOT be shallow, and A's NEXT push must SUCCEED. Both halves — a `.git/shallow`
  # absence check a mutant could satisfy vacuously, and a real push that a mutant cannot.
  bc_run "$bc_base/A" check ROW-1
  bc_expect_rc 0 "leg a2/shallow: a check reads the claim -> rc 0"
  if [ "$(git -C "$bc_base/A" rev-parse --is-shallow-repository 2>/dev/null)" = false ] \
     && [ ! -f "$bc_base/A/.git/shallow" ]; then
    bc_pass "leg a2/shallow: the caller's clone is NOT shallow after a read (no .git/shallow)"
  else
    bc_fail "leg a2/shallow: the read left the caller's clone SHALLOW — its next push will be rejected on a strict remote"
  fi
  # THE REAL ANCHOR: an ORPHAN-commit push from A after the reads — the EXACT shape `claim` uses and
  # the exact op that the CI red died on. The selftest clones carry no branch commits (they push
  # plumbing orphans), so HEAD is unborn; a fresh orphan built with mktree/commit-tree is the honest
  # equivalent. On a shallow-poisoned clone against a bare remote this push is rejected on ubuntu.
  _probe_ci=$( cd "$bc_base/A" && printf 'probe after read\n' | git commit-tree "$(printf '' | git mktree)" )
  if ( cd "$bc_base/A" && git push origin "$_probe_ci:refs/heads/probe-after-read" >/dev/null 2>&1 ); then
    bc_pass "leg a2/push-after-read: A's clone can still push an orphan after reading a claim (shallow-poison is gone)"
  else
    bc_fail "leg a2/push-after-read: A's push was REJECTED after a read — the shallow-poison bug is live"
  fi
  git --git-dir="$bc_remote_dir" update-ref -d refs/heads/probe-after-read 2>/dev/null || true

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
  # ⚠️ BEHAVIOUR CHANGED BY B2-SESSION-IDENTITY-LEDGER (decision 4), and this leg is where it shows:
  # `--stale` no longer deletes a claim on the word "stale". It refuses unless staleness is PROVEN
  # (legs s/* below), and the human dial is the one command that overrides — which is what this leg
  # now drives, so the fixture reaches the same state by the route a human would actually take.
  # ⚠️ RE-TAKEN AT FIX ROUND 1 (H2). This leg used to release on "the branch is absent from origin",
  # which was P1 — and P1 IS NO LONGER A PROOF. Under ONE-PUSH-PER-PR every in-build slice's branch
  # is absent from origin until its FINAL push, so "branch absent" describes a healthy mid-build
  # claim, and this very slice's own live claim was rated stale by it (measured at live acceptance).
  # B's `feat/b` has never been pushed, so the refusal is what must happen here; the human dial is
  # how the fixture reaches the next state, which is also the honest route for a dead session whose
  # work never left the machine.
  bc_run "$bc_base/A" release ROW-1 --stale
  bc_expect_rc 1 "leg c/stale: a branch-absent claim with no P2/P3 is REFUSED -> rc 1"
  bc_has "leg c/stale: the refusal still NAMES the holder" "Session B <b@example.com>"
  bc_run_force "$bc_base/A" 'fixture teardown by the selftest' release ROW-1 --stale
  bc_expect_rc 0 "leg c/stale: the human dial releases the same claim -> rc 0"
  bc_has "leg c/stale: the forced release names the holder it removed" "Session B <b@example.com>"

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

  # ---- leg (j): RETIRED S-L5 (TBG-SEAM-CONSUMERS-DERIVED T3, F5) — `claim` no longer resolves a
  # backend to refuse non-md. This used to assert the OPPOSITE (a foreign-backend refusal); it now
  # proves the retirement directly: a project declaring `jira`, with a real BACKLOG.md present and
  # the row sitting in Ready, is accepted exactly like an md-declared project. `--dry-run` so it
  # never mutates the board this fixture needs clean for leg (k).
  bc_fixture_board "$bc_base/B/BACKLOG.md"
  printf '# Fixture project\n\n- **Backlog backend**: Jira (project KIT)\n' > "$bc_base/B/CLAUDE.md"
  bc_run "$bc_base/B" claim ROW-1 --branch feat/b --dry-run
  bc_expect_rc 0 "leg j/backend-retired: a declared jira backend no longer refuses claim -> rc 0 (dry run)"
  bc_hasnt "leg j/backend-retired: no backend-declaration refusal is printed" "declares backlog backend"
  rm -f "$bc_base/B/CLAUDE.md"

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

  # ---- leg (o): WIP IS COUNTED AT CLAIM, FROM THE ORIGIN CLAIM REFS (B4-CROSS-SESSION-BUDGET) ----
  # A parallel session's In Progress row lives on ITS branch and is invisible on the local board
  # (the header block above says so), and the local board is agent-writable besides — so a
  # local-board WIP count would fail OPEN against exactly the sessions it bounds. The machine-
  # truthful count is `refs/claims/*` on origin, which this verb already reads. The ceiling is
  # MAX_WIP in .kit/budget.conf, compared by `runaway-guard.sh wip --count <n>` (control-plane,
  # ratified). ⚠️ The count EXCLUDES the row being claimed, so a RESUME of your own claim is never
  # refused by the ceiling your own claim contributes to — legs o3/o4 are that pair.
  bc_run "$bc_base/A" release ROW-2
  bc_expect_rc 0 "leg o/setup: A releases ROW-2 so the WIP count starts from a known state"
  # ⚠️ THE CEILING IS READ FROM THE CONFIG THIS VERB'S GUARD ACTUALLY USES — NEVER HARD-CODED (R1/H4).
  # MAX_WIP is a RATIFIABLY RAISABLE ceiling and this selftest is a required CI step for adopters, so
  # a leg asserting the literal `wip(2/2)` turns a governed raise into a red build: the test would
  # forbid the act it exists to support. The legs below scale to whatever value is declared.
  bc_wipcfg=$(dirname -- "$BC_GUARD")/../.kit/budget.conf
  # ⚠️ THE GUARD'S OWN GRAMMAR (R2/1): `cfg()` tolerates whitespace around `=`, so `MAX_WIP = 3` is a
  # valid ratified ceiling. Parsed with a stricter key this leg silently degraded to N/A — the worst
  # failure a leg has, since it keeps the suite green while measuring nothing.
  bc_maxwip=$(sed -n 's/^[[:space:]]*MAX_WIP[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$bc_wipcfg" 2>/dev/null | head -1)
  case "$bc_maxwip" in ''|*[!0-9]*) bc_maxwip=0 ;; esac
  if [ "$bc_maxwip" -lt 1 ]; then
    bc_pass "leg o/over-wip: N/A — $bc_wipcfg declares no positive MAX_WIP, so there is no ceiling to breach"
  else
  bc_i=1
  while [ "$bc_i" -le "$bc_maxwip" ]; do
    bc_mkclaimref "ROW-W$bc_i" CLAIM "row: ROW-W$bc_i
claimant: Foreign $bc_i <f$bc_i@example.com>
branch: feat/f$bc_i
claimed-at: 2026-09-15T00:00:00Z"
    bc_i=$((bc_i + 1))
  done
  bc_run "$bc_base/B" claim ROW-1 --branch feat/b
  bc_expect_rc 2 "leg o/over-wip: $bc_maxwip foreign claims on origin at MAX_WIP=$bc_maxwip -> rc 2 (refused)"
  bc_has "leg o/over-wip: the refusal carries the guard's own wip verdict" "wip($bc_maxwip/$bc_maxwip)"
  if git --git-dir="$bc_remote_dir" rev-parse --verify -q refs/claims/ROW-1 >/dev/null; then
    bc_fail "leg o/over-wip: a WIP-refused claim PUSHED a ref anyway"
  else
    bc_pass "leg o/over-wip: the WIP refusal precedes the network — nothing was pushed"
  fi
  if awk '/^## In Progress/{s=1;next} s&&/^## /{exit} s&&/`ROW-1`/{f=1} END{exit !f}' "$bc_base/B/BACKLOG.md"; then
    bc_fail "leg o/over-wip: the WIP-refused claim edited the board anyway"
  else
    bc_pass "leg o/over-wip: the WIP-refused claim left the board UNTOUCHED"
  fi
  # o2 — THE LIVENESS ANCHOR: one fewer foreign claim is under the ceiling, so the claim proceeds.
  git --git-dir="$bc_remote_dir" update-ref -d "refs/claims/ROW-W$bc_maxwip"
  bc_fixture_board "$bc_base/B/BACKLOG.md"
  bc_run "$bc_base/B" claim ROW-1 --branch feat/b
  bc_expect_rc 0 "leg o/under-wip: $((bc_maxwip - 1)) foreign claim(s) against MAX_WIP=$bc_maxwip -> rc 0, the claim proceeds"
  # o3 — OWN-REF EXCLUSION: B now holds ROW-1, so origin carries exactly MAX_WIP refs (the remaining
  # foreign ones plus ROW-1). Re-claiming ROW-1 is a RESUME, and the row's own ref must not count
  # toward the ceiling it is measured against — without the exclusion this is refused at the ceiling.
  bc_fixture_board "$bc_base/B/BACKLOG.md"
  bc_run "$bc_base/B" claim ROW-1 --branch feat/b --dry-run
  bc_expect_rc 0 "leg o/own-ref-excluded: the row's OWN claim ref is excluded from the WIP count -> rc 0"
  bc_hasnt "leg o/own-ref-excluded: the resume is not refused as over-WIP" "wip("
  # o4 — and an UNREACHABLE origin refuses (rc 2) rather than counting zero claims and sailing on.
  bc_run_badremote "$bc_base/B" claim ROW-2 --branch feat/b
  bc_expect_rc 2 "leg o/unreachable: a WIP count against an unreachable origin -> rc 2, never 0 claims"
  bc_has "leg o/unreachable: the refusal names the unreachable remote" "cannot reach"
  bc_run "$bc_base/B" release ROW-1
  bc_expect_rc 0 "leg o/cleanup: B releases ROW-1"
  bc_i=1
  while [ "$bc_i" -le "$bc_maxwip" ]; do
    git --git-dir="$bc_remote_dir" update-ref -d "refs/claims/ROW-W$bc_i" 2>/dev/null || true
    bc_i=$((bc_i + 1))
  done
  fi

  # ---- leg (p): ANY non-zero from the guard REFUSES — including rc 2 (R1/L2) ---------------------
  # `wip` fail-closes on a malformed MAX_WIP, and `claim` must treat that as "do not start a second
  # slice" exactly like rc 1. The guard's config is pointed at a fixture through the SANDBOX DIAL —
  # the same human-vouched route the guard requires of everybody, which is why the fixture has to
  # declare it rather than quietly redirecting the ceiling.
  bc_fixture_board "$bc_base/B/BACKLOG.md"
  printf 'MAX_TOKENS=0\nMAX_STEPS=0\nMAX_AGENTS=0\nMAX_WIP=two\n' > "$bc_base/badwip.conf"
  bc_run_wipcfg "$bc_base/B" "$bc_base/badwip.conf" claim ROW-1 --branch feat/b
  bc_expect_rc 2 "leg p/malformed-ceiling: a MALFORMED MAX_WIP -> claim refuses (rc 2), never proceeds"
  bc_has "leg p/malformed-ceiling: the refusal names the work-in-progress ceiling" "work-in-progress ceiling"
  bc_has "leg p/malformed-ceiling: it carries the guard's own fail-closed line" "MAX_WIP not a non-negative integer"
  if git --git-dir="$bc_remote_dir" rev-parse --verify -q refs/claims/ROW-1 >/dev/null; then
    bc_fail "leg p/malformed-ceiling: a guard-refused claim PUSHED a ref anyway"
  else
    bc_pass "leg p/malformed-ceiling: nothing was pushed"
  fi
  # …liveness anchor for the same route: a WELL-FORMED fixture ceiling with room still claims.
  printf 'MAX_TOKENS=0\nMAX_STEPS=0\nMAX_AGENTS=0\nMAX_WIP=9\n' > "$bc_base/okwip.conf"
  bc_run_wipcfg "$bc_base/B" "$bc_base/okwip.conf" claim ROW-1 --branch feat/b --dry-run
  bc_expect_rc 0 "leg p/liveness: a well-formed fixture ceiling with room -> rc 0 (the refusal is not unconditional)"

  # ---- leg (q/branch-grammar): THE BRANCH IS A REF NAME AT WRITE **AND** AT READ (B2 D2, sec-2) ---
  # `do_claim` used to write `branch:` unvalidated, and `bc_field` strips control bytes only. A
  # front-door claim with `--branch '--upload-pack=<cmd>'` is a LEGITIMATE claim, and any later verb
  # that hands that value to `git fetch`/`ls-remote`/`gh` as a BARE argument executes it on the next
  # reader's machine — the owner's included. Two faces, both graded here: refused at write, before
  # any network (asserted against the BAD remote, so the grammar's PRECEDENCE is what is measured),
  # and refused at READ, so a claim ref planted by anyone with push rights cannot arm a later verb.
  bc_fixture_board "$bc_base/A/BACKLOG.md"
  for bc_badbr in '--upload-pack=touch /tmp/pwned' '-o' 'feat/..' 'feat/x y' 'feat/x~1'; do
    bc_run_badremote "$bc_base/A" claim ROW-1 --branch "$bc_badbr"
    bc_expect_rc 2 "leg q/branch-grammar: claim --branch '$bc_badbr' -> rc 2"
    bc_has "leg q/branch-grammar: '$bc_badbr' is refused BY GRAMMAR" "is not a valid branch name"
    bc_hasnt "leg q/branch-grammar: '$bc_badbr' never reached the remote" "cannot reach"
  done
  # …the liveness anchor: an ordinary branch name is NOT refused by the same gate.
  bc_run "$bc_base/A" claim ROW-1 --branch feat/ok-1.2 --dry-run
  bc_expect_rc 0 "leg q/branch-grammar: a well-formed branch name is accepted (the refusal is not unconditional)"
  # …and at READ: a planted CLAIM whose `branch:` is an option string is MALFORMED, out loud, for
  # every reader — never parsed into a holder sentence that a later verb would act on.
  bc_mkclaimref ROW-BADBRANCH CLAIM 'row: ROW-BADBRANCH
claimant: Planter <p@example.com>
branch: --upload-pack=touch /tmp/pwned
claimed-at: 2026-09-16T00:00:00Z'
  bc_run "$bc_base/A" check ROW-BADBRANCH
  bc_expect_rc 0 "leg q/branch-grammar: check on a planted bad-branch CLAIM -> rc 0 (the ref IS there)"
  bc_has "leg q/branch-grammar: the planted branch is announced MALFORMED at read" "MALFORMED"
  bc_hasnt "leg q/branch-grammar: the option string never reaches a holder sentence" "upload-pack"
  git --git-dir="$bc_remote_dir" update-ref -d refs/claims/ROW-BADBRANCH

  # ---- leg (q/session-minted): THE SESSION IS MINTED BY `claim`, CARRIED, AND PRINTED (B2 D1) ----
  # `.kit-run/session.id` is the per-worktree declared session token. `claim` mints it when absent;
  # everything else reads it. It is an input to NOTHING that authorizes — it is how `status` and
  # `resume` can say WHICH session holds a row, and the CLAIM file labels it declared.
  bc_mkclone C "Session C" c@example.com
  rm -rf "$bc_base/C/.kit-run"
  bc_run "$bc_base/C" claim ROW-1 --branch feat/c
  bc_expect_rc 0 "leg q/session-minted: a claim from a worktree with no session file -> rc 0"
  bc_sid=$(cat "$bc_base/C/.kit-run/session.id" 2>/dev/null || echo '')
  case "$bc_sid" in
    s-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f])
      bc_pass "leg q/session-minted: the minted id matches s-<YYYYMMDD>-<8 hex> ($bc_sid)" ;;
    *) bc_fail "leg q/session-minted: minted id is not in the mint grammar; got [$bc_sid]" ;;
  esac
  # mktemp + mv under umask 077 — the file is never world-readable and never written THROUGH a link.
  case "$(ls -l "$bc_base/C/.kit-run/session.id" | cut -c1-10)" in
    -rw-------) bc_pass "leg q/session-minted: the minted file is mode 0600 (umask 077 at the mint)" ;;
    *) bc_fail "leg q/session-minted: minted file is not 0600; got [$(ls -l "$bc_base/C/.kit-run/session.id" | cut -c1-10)]" ;;
  esac
  bc_run "$bc_base/C" check ROW-1
  bc_expect_rc 0 "leg q/session-minted: check on the row C just claimed -> rc 0"
  bc_has "leg q/session-minted: the machine face carries claim-session:" "claim-session: $bc_sid"
  # …and a LEGACY claim, written before this field existed, reads `unknown` — never an empty value
  # dressed up as one, and never a refusal (the field is additive).
  bc_run "$bc_base/C" release ROW-1
  bc_expect_rc 0 "leg q/session-minted: C releases ROW-1"
  bc_mkclaimref ROW-LEGACY CLAIM 'row: ROW-LEGACY
claimant: Old Session <old@example.com>
branch: feat/old
claimed-at: 2026-09-01T00:00:00Z'
  bc_run "$bc_base/C" check ROW-LEGACY
  bc_expect_rc 0 "leg q/session-minted: check on a legacy CLAIM with no session: -> rc 0"
  bc_has "leg q/session-minted: a legacy CLAIM reads claim-session: unknown" "claim-session: unknown"
  git --git-dir="$bc_remote_dir" update-ref -d refs/claims/ROW-LEGACY

  # ---- leg (q/session-hygiene): THE STATE FILE IS A PLANT SURFACE, SO IT GETS THE TALLY'S RULES ---
  # [sec-1, HIGH] Writes under `.kit-run/` are NOT control-plane to the guard, so a planted
  # `.kit-run/session.id -> hooks/pre-push` would turn the next `claim` — the OWNER'S own, from `!` —
  # into a truncating write onto the control plane, and `-> /dev/zero` would hang the read side.
  # So the mint and the read follow `scripts/runaway-guard.sh`'s state-dir hygiene exactly: refuse
  # (rc 2, NAMING the path) unless `.kit-run` is a real non-symlink uid-owned directory and the file
  # is absent or a regular, non-symlink, LINK-COUNT-1, uid-owned file whose content is one line of
  # [A-Za-z0-9._-]{1,64}. Each face gets its own fixture, and each asserts the TARGET IS UNTOUCHED.
  bc_kitrun="$bc_base/C/.kit-run"
  bc_victim="$bc_base/victim.txt"
  # (i) a SYMLINKED session.id — the truncating-write plant
  printf 'DO NOT TRUNCATE ME\n' > "$bc_victim"
  rm -rf "$bc_kitrun"; mkdir -p "$bc_kitrun"; ln -s "$bc_victim" "$bc_kitrun/session.id"
  bc_fixture_board "$bc_base/C/BACKLOG.md"
  bc_run "$bc_base/C" claim ROW-1 --branch feat/c
  bc_expect_rc 2 "leg q/session-hygiene: a SYMLINKED session.id -> rc 2 (refused)"
  bc_has "leg q/session-hygiene: the refusal NAMES the path it refused" ".kit-run/session.id"
  bc_has "leg q/session-hygiene: the refusal says it is a symlink" "symlink"
  if [ "$(cat "$bc_victim")" = "DO NOT TRUNCATE ME" ]; then
    bc_pass "leg q/session-hygiene: the symlink TARGET is untouched (nothing was written through it)"
  else
    bc_fail "leg q/session-hygiene: the symlink target was written through — the plant worked"
  fi
  if git --git-dir="$bc_remote_dir" rev-parse --verify -q refs/claims/ROW-1 >/dev/null; then
    bc_fail "leg q/session-hygiene: a hygiene-refused claim PUSHED a ref anyway"
  else
    bc_pass "leg q/session-hygiene: the hygiene refusal is OFFLINE — nothing was pushed"
  fi
  # (ii) a HARD-LINKED session.id (link count 2) — the same plant without a symlink to spot
  rm -rf "$bc_kitrun"; mkdir -p "$bc_kitrun"
  if ln "$bc_victim" "$bc_kitrun/session.id" 2>/dev/null; then
    bc_run "$bc_base/C" claim ROW-1 --branch feat/c
    bc_expect_rc 2 "leg q/session-hygiene: a HARD-LINKED session.id (link count 2) -> rc 2"
    bc_has "leg q/session-hygiene: the hardlink refusal names the path" ".kit-run/session.id"
    bc_has "leg q/session-hygiene: the hardlink refusal names the link count" "link count"
  else
    bc_fail "leg q/session-hygiene: could not build the hard-link fixture (the leg measured nothing)"
  fi
  # (iii) a SYMLINKED .kit-run directory
  rm -rf "$bc_kitrun"; mkdir -p "$bc_base/elsewhere"; ln -s "$bc_base/elsewhere" "$bc_kitrun"
  bc_run "$bc_base/C" claim ROW-1 --branch feat/c
  bc_expect_rc 2 "leg q/session-hygiene: a SYMLINKED .kit-run directory -> rc 2"
  bc_has "leg q/session-hygiene: the directory refusal names the directory" ".kit-run"
  # (iv) a TWO-LINE file and (v) an OUT-OF-GRAMMAR file — refused, never sanitized into a value
  rm -rf "$bc_kitrun"; mkdir -p "$bc_kitrun"
  printf 's-20260916-deadbeef\nsecond line\n' > "$bc_kitrun/session.id"
  bc_run "$bc_base/C" claim ROW-1 --branch feat/c
  bc_expect_rc 2 "leg q/session-hygiene: a TWO-LINE session.id -> rc 2"
  bc_has "leg q/session-hygiene: the two-line refusal names the path" ".kit-run/session.id"
  printf 'evil; rm -rf /\n' > "$bc_kitrun/session.id"
  bc_run "$bc_base/C" claim ROW-1 --branch feat/c
  bc_expect_rc 2 "leg q/session-hygiene: an OUT-OF-GRAMMAR session.id -> rc 2"
  bc_has "leg q/session-hygiene: the grammar refusal names the path" ".kit-run/session.id"
  bc_hasnt "leg q/session-hygiene: the malformed value is never echoed back as a session" "session: evil"
  # …the liveness anchor: an ADOPTER-WRITTEN well-formed id (the file is the seam — the read grammar
  # is deliberately wider than the mint grammar) is accepted and carried verbatim onto the CLAIM.
  printf 'harness.run_42-B\n' > "$bc_kitrun/session.id"
  bc_fixture_board "$bc_base/C/BACKLOG.md"
  bc_run "$bc_base/C" claim ROW-1 --branch feat/c
  bc_expect_rc 0 "leg q/session-hygiene: a well-formed adopter-written id is accepted -> rc 0"
  bc_run "$bc_base/C" check ROW-1
  bc_has "leg q/session-hygiene: the adopter's own id is carried onto the CLAIM verbatim" "claim-session: harness.run_42-B"
  bc_run "$bc_base/C" release ROW-1
  bc_expect_rc 0 "leg q/session-hygiene: cleanup — C releases ROW-1"

  # ---- leg (r/resume-child): A NEW SESSION ON THE SAME ROW EXTENDS THE CLAIM, UNDER A LEASE ------
  # Same claimant, same branch, DIFFERENT session = a cold resume of a parked slice. The claim ref
  # becomes a small CHAIN: a CHILD claim commit whose parent is the claim that was read, pushed
  # WITHOUT a leading `+` (a child is a fast-forward — the face the mechanism's own header measured,
  # used here for its honest purpose) and under `--force-with-lease=<ref>:<observed>` so it can only
  # ever extend the claim this process actually read [sec-8]. Same session = nothing is pushed at all.
  bc_fixture_board "$bc_base/C/BACKLOG.md"
  rm -rf "$bc_base/C/.kit-run"
  bc_run "$bc_base/C" claim ROW-1 --branch feat/c
  bc_expect_rc 0 "leg r/resume-child: setup — C claims ROW-1 under a freshly minted session"
  bc_sha1=$(git --git-dir="$bc_remote_dir" rev-parse refs/claims/ROW-1)
  bc_sid1=$(cat "$bc_base/C/.kit-run/session.id")
  # same session, same branch -> the pre-existing resume path: NOTHING is pushed.
  bc_fixture_board "$bc_base/C/BACKLOG.md"
  bc_run "$bc_base/C" claim ROW-1 --branch feat/c
  bc_expect_rc 0 "leg r/resume-child: the SAME session re-claiming its own row -> rc 0"
  bc_has "leg r/resume-child: the same-session verdict is the unchanged resume sentence" "held by you since"
  if [ "$(git --git-dir="$bc_remote_dir" rev-parse refs/claims/ROW-1)" = "$bc_sha1" ]; then
    bc_pass "leg r/resume-child: the SAME session pushed NOTHING (the ref is byte-identical)"
  else
    bc_fail "leg r/resume-child: the same session moved the claim ref — a no-op became a write"
  fi
  # a DIFFERENT session, same claimant and branch -> a CHILD commit, and the chain records both.
  printf 's-20260916-cafebabe\n' > "$bc_base/C/.kit-run/session.id"
  bc_fixture_board "$bc_base/C/BACKLOG.md"
  bc_run "$bc_base/C" claim ROW-1 --branch feat/c
  bc_expect_rc 0 "leg r/resume-child: a DIFFERENT session on the same claimant+branch -> rc 0"
  bc_has "leg r/resume-child: the verdict says the claim was RESUMED by a new session" "RESUMED"
  bc_has "leg r/resume-child: the verdict names the session that held it before" "$bc_sid1"
  bc_sha2=$(git --git-dir="$bc_remote_dir" rev-parse refs/claims/ROW-1)
  if [ "$bc_sha2" != "$bc_sha1" ]; then
    bc_pass "leg r/resume-child: the claim ref MOVED to a new commit"
  else
    bc_fail "leg r/resume-child: the claim ref did not move — the resume pushed nothing"
  fi
  if [ "$(git --git-dir="$bc_remote_dir" rev-parse "$bc_sha2^" 2>/dev/null)" = "$bc_sha1" ]; then
    bc_pass "leg r/resume-child: the new claim commit is a CHILD of the one that was read (a chain, not a replacement)"
  else
    bc_fail "leg r/resume-child: the new claim commit is not a child of the observed claim"
  fi
  bc_run "$bc_base/C" check ROW-1
  bc_has "leg r/resume-child: the CLAIM now carries the NEW session" "claim-session: s-20260916-cafebabe"
  if git --git-dir="$bc_remote_dir" show "$bc_sha2:CLAIM" | grep -q '^resumed-at: '; then
    bc_pass "leg r/resume-child: the resumed CLAIM carries a resumed-at: field"
  else
    bc_fail "leg r/resume-child: the resumed CLAIM has no resumed-at: field"
  fi
  # …AND THE REFUSAL HALF. A claim that moved between the read and the push must NOT be replaced.
  # The forge's rejection is the same event in both shapes (a non-fast-forward child, or a lease that
  # no longer holds), so the fixture makes the remote reject the update outright — what the verb owes
  # is a refusal that leaves the existing claim exactly as it found it.
  printf '#!/bin/sh\nexit 1\n' > "$bc_remote_dir/hooks/pre-receive"
  chmod +x "$bc_remote_dir/hooks/pre-receive"
  printf 's-20260916-0badf00d\n' > "$bc_base/C/.kit-run/session.id"
  bc_fixture_board "$bc_base/C/BACKLOG.md"
  bc_run "$bc_base/C" claim ROW-1 --branch feat/c
  bc_expect_rc 2 "leg r/resume-child: a REJECTED resume push -> rc 2 (refused), never a silent 0"
  bc_has "leg r/resume-child: the refusal says the existing claim was left alone" "left untouched"
  if [ "$(git --git-dir="$bc_remote_dir" rev-parse refs/claims/ROW-1)" = "$bc_sha2" ]; then
    bc_pass "leg r/resume-child: the rejected resume replaced NOTHING — the claim is still the one it read"
  else
    bc_fail "leg r/resume-child: a rejected resume changed the claim ref anyway"
  fi
  rm -f "$bc_remote_dir/hooks/pre-receive"
  bc_run "$bc_base/C" release ROW-1
  bc_expect_rc 0 "leg r/resume-child: cleanup — C releases ROW-1"

  # ---- legs (s/*) + (t/force-dial): --stale RELEASES ON PROOF, OR NOT AT ALL (B2 decision 4) -----
  # `release --stale` used to delete any claim on the word "stale". The eight stale refs of
  # 2026-09-15 say what that cost; the risk it carries is the opposite one — deleting a LIVE claim.
  # So it now refuses unless staleness is PROVEN by one of TWO forge-visible facts:
  #   P2 a non-cross-repo PR from that head is MERGED and no PR from it is OPEN · P3 the row sits in
  #   `## Done` on the DEFAULT BRANCH's board.
  # "No commits since" is NOT a proof — a parked slice is silent and alive — and NEITHER IS "the
  # branch is absent from origin" (the old P1, withdrawn at fix round 1: it is the normal state of
  # every in-build slice under one-push-per-PR). Both are printed as evidence and decide nothing.
  # The fixture below gives the bare remote a real default branch carrying a real board, because P3
  # is read off the forge, not off the local tree.
  bc_fixture_board "$bc_base/A/BACKLOG.md"
  ( cd "$bc_base/A" && git add BACKLOG.md >/dev/null 2>&1 \
      && git commit -q -m 'fixture board' >/dev/null 2>&1 \
      && git push -q origin HEAD:refs/heads/main >/dev/null 2>&1 )
  git --git-dir="$bc_remote_dir" symbolic-ref HEAD refs/heads/main
  # a real branch for the claim to point at, so the branch evidence line is PRESENT-by-fact
  ( cd "$bc_base/A" && git push -q origin HEAD:refs/heads/feat/live >/dev/null 2>&1 )

  # (s/stale-refused) — branch present, no MERGED PR, row not Done: REFUSED, and the ref survives.
  bc_fixture_board "$bc_base/B/BACKLOG.md"
  bc_run "$bc_base/B" claim ROW-1 --branch feat/live
  bc_expect_rc 0 "leg s/stale-refused: setup — B claims ROW-1 on a branch that EXISTS on origin"
  # a clean slate for the claims-log assertion: leg (c) already exercised the dial on this row.
  git --git-dir="$bc_remote_dir" update-ref -d refs/claims-log/ROW-1 2>/dev/null || true
  bc_run "$bc_base/A" release ROW-1 --stale
  bc_expect_rc 1 "leg s/stale-refused: --stale with no proof of staleness -> rc 1 (refused)"
  bc_has "leg s/stale-refused: evidence line 1 — the branch is on origin" "branch on origin: yes"
  bc_has "leg s/stale-refused: evidence line 2 — the PR state is reported" "pr: "
  bc_has "leg s/stale-refused: evidence line 3 — the row's section on the default board" "board:"
  bc_has "leg s/stale-refused: the refusal prints the exact human dial sentence" "KIT_CLAIM_FORCE_RELEASE="
  if git --git-dir="$bc_remote_dir" rev-parse --verify -q refs/claims/ROW-1 >/dev/null; then
    bc_pass "leg s/stale-refused: the unproven --stale deleted NOTHING"
  else
    bc_fail "leg s/stale-refused: the unproven --stale deleted the claim anyway"
  fi
  if git --git-dir="$bc_remote_dir" rev-parse --verify -q refs/claims-log/ROW-1 >/dev/null 2>&1; then
    bc_fail "leg s/stale-refused: a REFUSED release wrote a claims-log entry (a refusal is not an event)"
  else
    bc_pass "leg s/stale-refused: a refused release writes NO claims-log entry"
  fi

  # (s/stale-p2-merged) — P2 through a STUB gh on PATH. Never the real forge, and the stub is the
  # only way to drive the three shapes the seat's condition [sec-3] cares about:
  #   MERGED + not cross-repo -> a proof · any OPEN PR -> REFUSE (a newer agent-opened-and-closed PR
  #   must not shadow a live one) · CLOSED-unmerged -> NOT a proof (the branch still exists and one
  #   allowed `gh pr close` mints it).
  mkdir -p "$bc_base/ghstub"
  bc_ghstub 'CLOSED false'
  bc_run_gh "$bc_base/A" release ROW-1 --stale
  bc_expect_rc 1 "leg s/stale-p2-merged: a CLOSED-unmerged PR is NOT a proof -> rc 1"
  bc_has "leg s/stale-p2-merged: the evidence names the CLOSED state" "pr: CLOSED"
  bc_ghstub 'MERGED false
OPEN false'
  bc_run_gh "$bc_base/A" release ROW-1 --stale
  bc_expect_rc 1 "leg s/stale-p2-merged: an OPEN PR on the same head REFUSES even beside a MERGED one"
  bc_has "leg s/stale-p2-merged: the evidence names the OPEN state" "pr: OPEN"
  bc_ghstub 'MERGED true'
  bc_run_gh "$bc_base/A" release ROW-1 --stale
  bc_expect_rc 1 "leg s/stale-p2-merged: a CROSS-REPOSITORY MERGED PR is not a proof -> rc 1"
  bc_ghstub 'MERGED false'
  bc_run_gh "$bc_base/A" release ROW-1 --stale
  bc_expect_rc 0 "leg s/stale-p2-merged: a same-repo MERGED PR with no OPEN sibling IS a proof -> rc 0"
  # ⚠️ AND THE QUERY NAMES THE REPOSITORY (fix round 1, L7). `gh pr list` without `--repo` resolves
  # from the CWD's own git remotes, which is NOT necessarily `$BOARD_CLAIM_REMOTE` — so a claim read
  # against one remote could be "proved" stale by a MERGED PR in a DIFFERENT repository (a fork, or
  # whatever `origin` happens to be in the directory the verb was run from). The repo is now derived
  # from the remote URL this verb is actually talking to. The stub records its argv, so this asserts
  # the flag REACHED gh rather than that the code contains it.
  case "$(cat "$bc_base/ghstub/argv" 2>/dev/null || echo '')" in
    *"--repo fixture-owner/fixture-repo"*) bc_pass "leg s/stale-p2-merged: the PR query passes --repo with the OWNER/REPO derived from the remote URL" ;;
    *) bc_fail "leg s/stale-p2-merged: gh pr list was called with NO --repo; argv=[$(cat "$bc_base/ghstub/argv" 2>/dev/null)]" ;;
  esac
  bc_has "leg s/stale-p2-merged: the release names the proof it acted on" "proof P2"
  if git --git-dir="$bc_remote_dir" rev-parse --verify -q refs/claims/ROW-1 >/dev/null; then
    bc_fail "leg s/stale-p2-merged: the proven release did not delete the claim"
  else
    bc_pass "leg s/stale-p2-merged: the proven release deleted the claim ref"
  fi
  bc_logtxt=$(git --git-dir="$bc_remote_dir" show refs/claims-log/ROW-1:LOG 2>/dev/null || echo '')
  case "$bc_logtxt" in
    *"proof: P2"*) bc_pass "leg s/stale-p2-merged: the claims-log entry names the proof" ;;
    *) bc_fail "leg s/stale-p2-merged: no claims-log entry naming P2; got [$bc_logtxt]" ;;
  esac
  case "$bc_logtxt" in
    *"released-by: Session A <a@example.com>"*) bc_pass "leg s/stale-p2-merged: the log entry names WHO released it" ;;
    *) bc_fail "leg s/stale-p2-merged: the log entry does not name the releasing committer; got [$bc_logtxt]" ;;
  esac

  # (s/stale-branch-absent-not-proof) — ⚠️ THE LEG THAT CHANGED SIDES AT FIX ROUND 1 (H2). It used
  # to be `s/stale-p1-branch-gone` and asserted that an absent branch RELEASES. Live acceptance
  # falsified that: under `ONE-PUSH-PER-PR` a slice pushes ONCE, at the end, so from `claim` until
  # that push the branch is absent from origin for every healthy in-build slice — and `status` duly
  # rated THIS slice's own live claim `STALE-PROVABLE (P1)` while the builder was working on it.
  # An "evidence line that is true of the healthy case" is not a proof. P1 is demoted to evidence;
  # the proofs are P2 and P3 only, and a dead session whose work never left the machine is the human
  # dial's case, by design rather than by accident.
  bc_fixture_board "$bc_base/B/BACKLOG.md"
  bc_run "$bc_base/B" claim ROW-1 --branch feat/vanished
  bc_expect_rc 0 "leg s/stale-branch-absent-not-proof: setup — B claims on a branch origin has never seen"
  bc_run "$bc_base/A" release ROW-1 --stale
  bc_expect_rc 1 "leg s/stale-branch-absent-not-proof: an absent branch is NOT a proof -> rc 1 (refused)"
  bc_has "leg s/stale-branch-absent-not-proof: the evidence line still reports the branch" "branch on origin: no"
  bc_has "leg s/stale-branch-absent-not-proof: …and says in words that it is not a proof" "not a proof"
  bc_hasnt "leg s/stale-branch-absent-not-proof: no P1 proof is ever claimed" "proof P1"
  if git --git-dir="$bc_remote_dir" rev-parse --verify -q refs/claims/ROW-1 >/dev/null; then
    bc_pass "leg s/stale-branch-absent-not-proof: the claim ref is INTACT — a mid-build slice is not released"
  else
    bc_fail "leg s/stale-branch-absent-not-proof: the claim was released on an absent branch alone"
  fi
  # …the dial is the route out, and its entry CHAINS onto the P2 entry from the leg above.
  bc_run_force "$bc_base/A" 'holder machine confirmed gone' release ROW-1 --stale
  bc_expect_rc 0 "leg s/stale-branch-absent-not-proof: the dial releases it -> rc 0"
  if [ -n "$(git --git-dir="$bc_remote_dir" rev-parse -q --verify 'refs/claims-log/ROW-1^' 2>/dev/null)" ]; then
    bc_pass "leg s/stale-branch-absent-not-proof: the second claims-log entry is a CHILD of the first (a chain, not a replacement)"
  else
    bc_fail "leg s/stale-branch-absent-not-proof: the claims-log entry replaced the previous one instead of extending it"
  fi

  # (s/stale-p3-row-done) — the row sits in `## Done` on the DEFAULT BRANCH's board. An agent cannot
  # push to that branch nor change which branch is default, so a Done row reaches it only through a
  # merged, approved PR — which is why every `land`/`actuate` release is P3-provable by construction.
  bc_fixture_board "$bc_base/B/BACKLOG.md"
  bc_run "$bc_base/B" claim ROW-DONE --branch feat/live --board-already-moved
  bc_expect_rc 2 "leg s/stale-p3-row-done: (a Done row cannot be claimed through the front door)"
  bc_mkclaimref ROW-DONE CLAIM "row: ROW-DONE
claimant: Gone Session <gone@example.com>
branch: feat/live
claimed-at: 2026-09-01T00:00:00Z
session: s-20260901-11112222 (declared)"
  bc_run "$bc_base/A" release ROW-DONE --stale
  bc_expect_rc 0 "leg s/stale-p3-row-done: a row in ## Done on the default board IS a proof -> rc 0"
  bc_has "leg s/stale-p3-row-done: the release names P3" "proof P3"
  bc_has "leg s/stale-p3-row-done: the evidence names the row's section on the default board" "board: Done"
  case "$(git --git-dir="$bc_remote_dir" show refs/claims-log/ROW-DONE:LOG 2>/dev/null || echo '')" in
    *"proof: P3"*) bc_pass "leg s/stale-p3-row-done: the claims-log entry names P3" ;;
    *) bc_fail "leg s/stale-p3-row-done: no claims-log entry naming P3" ;;
  esac

  # (s/stale-delete-failed) — ⚠️ A FAILED DELETE MUST NOT LEAVE A LOG ENTRY SAYING IT SUCCEEDED
  # (fix round 1, M3). The record is pushed BEFORE the delete, on purpose — a release that leaves no
  # trace is the thing the record exists to prevent — but that ordering means a delete which then
  # FAILS leaves `refs/claims-log/<ROW>` asserting a release that never happened. This is not
  # theoretical: `shim-coverage.sh` case 5 MEASURES the delete being refused under `install-shims`
  # (the force-push rule), so the first build produced exactly that false record on a real run. The
  # cure is a compensating entry, because the log is append-only by design: `<proof>-FAILED`, with
  # `released-sha: (not deleted)`. The fixture rejects pushes to `refs/claims/*` ONLY, so the log
  # push still lands and the leg measures the delete, not the log.
  bc_fixture_board "$bc_base/B/BACKLOG.md"
  bc_run "$bc_base/B" claim ROW-1 --branch feat/live
  bc_expect_rc 0 "leg s/stale-delete-failed: setup — B holds ROW-1 on a branch that is on origin"
  printf '#!/bin/sh\nwhile read -r o n r; do case "$r" in refs/claims/*) exit 1 ;; esac; done\nexit 0\n' \
    > "$bc_remote_dir/hooks/pre-receive"
  chmod +x "$bc_remote_dir/hooks/pre-receive"
  bc_run_force "$bc_base/A" 'holder is gone, delete will fail' release ROW-1 --stale
  bc_expect_rc 1 "leg s/stale-delete-failed: a delete the forge refuses -> rc 1, never a silent 0"
  bc_has "leg s/stale-delete-failed: the failure says a record was ALREADY written" "record was already written"
  bc_logtxt=$(git --git-dir="$bc_remote_dir" show refs/claims-log/ROW-1:LOG 2>/dev/null || echo '')
  case "$bc_logtxt" in
    *"proof: FORCED-FAILED"*) bc_pass "leg s/stale-delete-failed: the log's LAST entry records the FAILURE, not a release" ;;
    *) bc_fail "leg s/stale-delete-failed: the log still claims a successful release; got [$bc_logtxt]" ;;
  esac
  case "$bc_logtxt" in
    *"released-sha: (not deleted)"*) bc_pass "leg s/stale-delete-failed: …and says plainly that nothing was deleted" ;;
    *) bc_fail "leg s/stale-delete-failed: the compensating entry does not say the ref survived; got [$bc_logtxt]" ;;
  esac
  rm -f "$bc_remote_dir/hooks/pre-receive"
  if git --git-dir="$bc_remote_dir" rev-parse --verify -q refs/claims/ROW-1 >/dev/null; then
    bc_pass "leg s/stale-delete-failed: the claim ref really did survive (the leg measured a real failure)"
  else
    bc_fail "leg s/stale-delete-failed: the ref is gone — the fixture did not refuse the delete"
  fi
  bc_run_force "$bc_base/A" 'fixture teardown after the failed delete' release ROW-1 --stale
  bc_expect_rc 0 "leg s/stale-delete-failed: cleanup — the same release succeeds once the forge allows it"

  # (s/stale-unreachable) — a remote this process cannot read is rc 2. Nothing deleted, nothing
  # logged: a proof nobody could look up is not a proof, and neither is its absence.
  bc_run_badremote "$bc_base/A" release ROW-2 --stale
  bc_expect_rc 2 "leg s/stale-unreachable: --stale against an unreachable remote -> rc 2"
  bc_has "leg s/stale-unreachable: the refusal names the unreachable remote" "cannot reach"

  # (s/wip-glob-excludes-log) — B4 counts WIP from `refs/claims/*`. A claims-log entry must NOT
  # count toward that ceiling, or every released row would keep consuming a slot forever.
  bc_globn=$(git ls-remote "$bc_remote_dir" 'refs/claims/*' 2>/dev/null | grep -c 'refs/claims-log/' || true)
  if [ "$bc_globn" = 0 ]; then
    bc_pass "leg s/wip-glob-excludes-log: the glob \`refs/claims/*\` matches NO refs/claims-log/* ref"
  else
    bc_fail "leg s/wip-glob-excludes-log: \`refs/claims/*\` matched $bc_globn claims-log refs — released rows would consume WIP forever"
  fi
  if [ -n "$(git ls-remote "$bc_remote_dir" 'refs/claims-log/*' 2>/dev/null)" ]; then
    bc_pass "leg s/wip-glob-excludes-log: (the fixture really does carry claims-log refs, so the check above measured something)"
  else
    bc_fail "leg s/wip-glob-excludes-log: no claims-log refs exist — the glob assertion was vacuous"
  fi

  # (t/force-dial) — the human dial. The in-line `KIT_CLAIM_FORCE_RELEASE=` prefix over the in-tree
  # script is DENIED to an agent under the guard (the unvetted-prefix rule); `export` as its own
  # call, a copied script and a `make` wrapper are MEASURED-UNCOVERED and pinned as such in
  # conformance/agent-autonomy.sh. Because the terminal banner is therefore not the control, every
  # forced release is made loud somewhere durable: a FORCED claims-log entry carrying the reason.
  bc_fixture_board "$bc_base/B/BACKLOG.md"
  bc_run "$bc_base/B" claim ROW-1 --branch feat/live
  bc_expect_rc 0 "leg t/force-dial: setup — B holds a LIVE, unprovably-stale claim"
  bc_run_force "$bc_base/A" short release ROW-1 --stale
  bc_expect_rc 2 "leg t/force-dial: a reason under 10 characters -> rc 2 (refused)"
  bc_has "leg t/force-dial: the refusal says why the reason was rejected" "at least 10 characters"
  if git --git-dir="$bc_remote_dir" rev-parse --verify -q refs/claims/ROW-1 >/dev/null; then
    bc_pass "leg t/force-dial: the short-reason refusal deleted nothing"
  else
    bc_fail "leg t/force-dial: a refused forced release deleted the claim anyway"
  fi
  bc_run_force "$bc_base/A" 'holder confirmed gone by the owner' release ROW-1 --stale
  bc_expect_rc 0 "leg t/force-dial: a reason of 10+ characters releases -> rc 0"
  bc_has "leg t/force-dial: the forced release prints a BANNER, not a quiet ok" "FORCED"
  bc_logtxt=$(git --git-dir="$bc_remote_dir" show refs/claims-log/ROW-1:LOG 2>/dev/null || echo '')
  case "$bc_logtxt" in
    *"proof: FORCED"*) bc_pass "leg t/force-dial: the claims-log entry records the release as FORCED" ;;
    *) bc_fail "leg t/force-dial: the forced release left no FORCED log entry; got [$bc_logtxt]" ;;
  esac
  case "$bc_logtxt" in
    *"reason: holder confirmed gone by the owner"*) bc_pass "leg t/force-dial: the log entry carries the human's REASON verbatim" ;;
    *) bc_fail "leg t/force-dial: the log entry lost the reason; got [$bc_logtxt]" ;;
  esac

  # ---- leg (u/status): WHO HOLDS WHAT, RIGHT NOW, WITH EVIDENCE (B2 decision 3) ------------------
  # `check --all` is the terse view and is unchanged. `status` is the one that answers the question a
  # conductor actually asks at a cold start: for every claim on origin, WHO holds it, which SESSIONS
  # have held it, and whether anything on the forge says it is dead. Every fact names its source or
  # reads `unknown`; the reading is LIVE unless a proof from decision 4 fires.
  bc_run "$bc_base/A" status
  bc_expect_rc 1 "leg u/status: status with NO claims on origin -> rc 1, never a silent 0"
  bc_has "leg u/status: the empty verdict says so plainly" "no claims"
  bc_fixture_board "$bc_base/B/BACKLOG.md"
  bc_run "$bc_base/B" claim ROW-1 --branch feat/live
  bc_expect_rc 0 "leg u/status: setup — B holds ROW-1 on a branch that exists on origin"
  bc_run "$bc_base/B" status
  bc_expect_rc 0 "leg u/status: status with a live claim -> rc 0"
  bc_has "leg u/status: the block names the row" "ROW-1"
  bc_has "leg u/status: the block names the holder" "Session B <b@example.com>"
  bc_has "leg u/status: the block names the branch" "feat/live"
  bc_has "leg u/status: the block carries the branch evidence line" "branch on origin: yes"
  bc_has "leg u/status: the block carries the pr evidence line" "pr:"
  bc_has "leg u/status: the block carries the board evidence line" "board:"
  bc_has "leg u/status: an unprovable claim READS AS LIVE" "reading:       LIVE"
  bc_has "leg u/status: the block names the session chain" "session chain:"
  # …a STALE-PROVABLE claim reads as such AND names the proof — the discrimination, not a constant.
  # ⚠️ THE FIXTURE IS P3, NOT P1, SINCE FIX ROUND 1 (H2): "branch absent from origin" is true of
  # every healthy mid-build slice under ONE-PUSH-PER-PR, so it can no longer produce this reading.
  bc_mkclaimref ROW-DONE CLAIM "row: ROW-DONE
claimant: Gone Session <gone@example.com>
branch: feat/live
claimed-at: 2026-09-01T00:00:00Z
session: s-20260901-33334444 (declared)"
  bc_run "$bc_base/B" status
  bc_has "leg u/status: a claim whose ROW IS DONE on the default board reads STALE-PROVABLE, naming the proof" "reading:       STALE-PROVABLE (P3)"
  # …and the branch-absent claim reads LIVE, WITH the reason, and offers NO release instruction:
  # naming `--stale` beside a mid-build slice is how a conductor gets talked into deleting live work.
  bc_mkclaimref ROW-2 CLAIM "row: ROW-2
claimant: Mid Build <mid@example.com>
branch: feat/vanished
claimed-at: 2026-09-01T00:00:00Z
session: s-20260901-55556666 (declared)"
  bc_run "$bc_base/B" status
  bc_has "leg u/status: a branch-absent claim reads LIVE, naming why" "branch not on origin"
  bc_hasnt "leg u/status: a branch-absent claim is NEVER rated stale" "STALE-PROVABLE (P1)"
  if printf '%s\n' "$bc_out" | awk '/`ROW-2`/{f=1} f && /release ROW-2 --stale/{found=1} /`ROW-DONE`/{f=0} END{exit !found}'; then
    bc_fail "leg u/status: the branch-absent block printed a --stale instruction beside a LIVE claim"
  else
    bc_pass "leg u/status: no release instruction is printed for a branch-absent (mid-build) claim"
  fi
  # …a LEGACY claim (no session: field) renders `unknown`, never an empty value dressed as a fact.
  bc_mkclaimref ROW-LEGACY2 CLAIM 'row: ROW-LEGACY2
claimant: Old Session <old@example.com>
branch: feat/vanished
claimed-at: 2026-09-01T00:00:00Z'
  bc_run "$bc_base/B" status
  bc_has "leg u/status: a legacy CLAIM with no session: renders unknown" "session chain: unknown"
  # …the last claims-log entry for a row is printed beside it (the durable trace of decision 4).
  bc_has "leg u/status: the last claims-log entry is printed for a row that has one" "last release:"
  # …AND THE CHAIN WALK IS BOUNDED. A claim ref is an unprotected ref anyone with push rights can
  # extend, so an unbounded walk is a denial-of-service on the one verb a conductor runs at a cold
  # start. The fixture builds a 40-deep chain by plumbing; `status` must read at most 32 of it.
  bc_deepsha=''; bc_deep1=''
  bc_i=1
  while [ "$bc_i" -le 40 ]; do
    bc_deepsha=$(bc_mkchainlink ROW-DEEP "$bc_i" "$bc_deepsha")
    [ "$bc_i" = 1 ] && bc_deep1=$bc_deepsha
    bc_i=$((bc_i + 1))
  done
  ( cd "$bc_base/A" && git push -q origin "$bc_deepsha:refs/claims/ROW-DEEP" )
  bc_run "$bc_base/B" status
  bc_chaincount=$(printf '%s\n' "$bc_out" | grep 'session chain:' | grep -c 's-19700101-00000001' || true)
  if [ "$bc_chaincount" = 0 ]; then
    bc_pass "leg u/status: the chain walk is BOUNDED — the 40th-oldest session is not in the rendering"
  else
    bc_fail "leg u/status: the chain walk reached a 40-deep claim's oldest link (unbounded)"
  fi
  bc_has "leg u/status: …and the bounded walk still renders the NEWEST session of that chain" "s-19700101-00000040"
  # …AND THE *FETCH* IS BOUNDED TOO, not just the walk (fix round 1, M4). Bounding `log -n 32` while
  # fetching the whole chain moves the cost rather than removing it: the objects still cross the
  # network and land in the caller's odb, so an attacker with push rights makes the cold-start verb
  # download an arbitrarily long history to print 32 lines. The fetch now carries
  # `--depth=$BC_CHAIN_MAX`, and this asserts it where it shows — the 40th-oldest OBJECT must not be
  # in the clone at all after a full `status`.
  # ⚠️ NON-VACUITY FIRST, AND IT CAUGHT A REAL BUG (fix round 1, M4). The bound-assertion below
  # PASSED against the unfixed code — for the wrong reason. MEASURED: `bc_read_claim` fetches the
  # claim `--depth=1`, which marks the ref SHALLOW in the caller's clone, and a later fetch WITHOUT
  # `--depth` does NOT deepen a shallow ref. So the chain walk saw exactly ONE commit no matter how
  # long the chain was: `status` rendered a single session and called it the chain. `--depth=32`
  # both DEEPENS past the shallow boundary and bounds the transfer. This leg asserts the chain
  # really does render more than its tip, so the bound can never again be satisfied by a walk that
  # fetches nothing.
  bc_chainout=$bc_out
  bc_chainn=$(printf '%s\n' "$bc_chainout" | grep 'session chain:' | grep -c 's-19700101-' || true)
  if [ "$bc_chainn" -ge 1 ]; then
    bc_pass "leg u/status: the chain walk really reaches BEYOND the tip (the bound is not vacuous)"
  else
    bc_fail "leg u/status: the rendered chain carries no chained session at all — the walk fetched nothing"
  fi
  bc_has "leg u/status: …and it renders a session from the MIDDLE of the chain, not only its head" "s-19700101-00000039"
  if git -C "$bc_base/B" cat-file -e "$bc_deep1" 2>/dev/null; then
    bc_fail "leg u/status: the whole 40-deep chain was FETCHED (the oldest object is in the clone) — the walk is bounded, the fetch is not"
  else
    bc_pass "leg u/status: the fetch is BOUNDED — the 40th-oldest claim object never reached the clone"
  fi
  git --git-dir="$bc_remote_dir" update-ref -d refs/claims/ROW-DEEP
  git --git-dir="$bc_remote_dir" update-ref -d refs/claims/ROW-LEGACY2
  git --git-dir="$bc_remote_dir" update-ref -d refs/claims/ROW-2
  git --git-dir="$bc_remote_dir" update-ref -d refs/claims/ROW-DONE
  bc_run "$bc_base/B" release ROW-1
  bc_expect_rc 0 "leg u/status: cleanup — B releases ROW-1"
  bc_run_badremote "$bc_base/B" status
  bc_expect_rc 2 "leg u/status: status against an unreachable remote -> rc 2, never 'no claims'"

  # ---- leg (v): BOARD-PIPE-ESCAPE T5 — the WRITE path preserves cell bytes byte-for-byte ---------
  # C1 (§5/§6.3 of the design): `bc_new_row`/the compose-write `awk` used to pass cell-derived text
  # through `awk -v`, which processes ITS OWN escape grammar on the assigned value — a source `\|`
  # is written back as a raw `|` (platform-dependently). A Ready row's Item cell carrying an escaped
  # pipe therefore came out of `claim` with an EXTRA column, corrupting the board and misaligning
  # every later column-by-name read (including the presence gate's Links read). This leg claims three
  # Ready rows whose Item cells carry `\|`, `\\|` and `\\\|`, and asserts the In-Progress Item cell is
  # BYTE-EQUAL to the original and the written row's column count matches the header's.
  bc_vboard() {
    cat > "$1" <<'V_BOARD_EOF'
# Fixture — Backlog

## Ready

| Item | Intent (why) | Acceptance criteria | Size | Risk | Type | Owner | Links | Success metric / hypothesis |
|------|--------------|---------------------|------|------|------|-------|-------|-----------------------------|
| `ROW-V1` — has a\|b escaped pipe | because | it is claimed | S | low | feature | agent | — | ok |
| `ROW-V2` — has a\\|b doubled backslash | because | it is claimed | S | low | feature | agent | — | ok |
| `ROW-V3` — has a\\\|b tripled backslash | because | it is claimed | S | low | feature | agent | — | ok |

## In Progress

| Item | Owner | Started | Links |
|------|-------|---------|-------|

## Done

| Item | Closed | Retro/outcome |
|------|--------|---------------|
V_BOARD_EOF
  }
  bc_mkclone V "Session V" v@example.com
  bc_vboard "$bc_base/V/BACKLOG.md"
  for bc_vrow in ROW-V1 ROW-V2 ROW-V3; do
    bc_vrline=$(bc_row_line "$bc_base/V/BACKLOG.md" Ready "$bc_vrow")
    bc_vrawrow=$(awk -v n="$bc_vrline" 'NR==n' "$bc_base/V/BACKLOG.md")
    bc_vbefore=$(bc_cell "$bc_vrawrow" 1)
    # the reference column count is the IN PROGRESS header's (the table the row is written INTO —
    # `bc_new_row` composes by that header's own columns), not the Ready table's.
    bc_vipbounds=$(bc_section_bounds "$bc_base/V/BACKLOG.md" "In Progress")
    bc_vhdrline=${bc_vipbounds% *}
    bc_vhdrtxt=$(awk -v n="$bc_vhdrline" 'NR==n' "$bc_base/V/BACKLOG.md")
    bc_vhdrn=$(bc_v_ncols "$bc_vhdrtxt")
    bc_run "$bc_base/V" claim "$bc_vrow" --branch "feat/$bc_vrow"
    bc_vip_line=$(bc_row_line "$bc_base/V/BACKLOG.md" "In Progress" "$bc_vrow")
    bc_vip_raw=$(awk -v n="$bc_vip_line" 'NR==n' "$bc_base/V/BACKLOG.md")
    bc_vafter=$(bc_cell "$bc_vip_raw" 1)
    bc_vafter_n=$(bc_v_ncols "$bc_vip_raw")
    if [ "$bc_vbefore" = "$bc_vafter" ]; then
      bc_pass "leg v/$bc_vrow: the In-Progress Item cell is BYTE-EQUAL to the original Ready Item cell"
    else
      bc_fail "leg v/$bc_vrow: byte mismatch — before=[$bc_vbefore] after=[$bc_vafter]"
    fi
    if [ "$bc_vafter_n" = "$bc_vhdrn" ]; then
      bc_pass "leg v/$bc_vrow: the written In-Progress row's column count equals the header's ($bc_vhdrn)"
    else
      bc_fail "leg v/$bc_vrow: the written row has $bc_vafter_n columns, not the header's $bc_vhdrn — row=[$bc_vip_raw]"
    fi
    # release immediately — MAX_WIP is 2, and three rows are claimed on the SAME clone in this loop.
    bc_run "$bc_base/V" release "$bc_vrow"
  done

  # ---- legs (w)-(z2): claim-ref / release-ref (T4, §6a S-5) --------------------------------------
  # bc_mk_race_script <out-file> <ref> — writes a small script that, when run, pushes a CHILD commit
  # onto <ref> (a genuine fast-forward, no lease needed) using clone R's own git. Used to force a
  # REAL lease mismatch between claim-ref's/release-ref's own push and its later compensating
  # delete — a stand-in for a real concurrent update landing in that narrow window, not a simulation
  # of the lease check itself (the delete below is the SAME --force-with-lease call the verb makes).
  bc_mk_race_script() {
    cat > "$1" <<RACE_EOF
#!/bin/sh
set -e
git -C "$bc_base/R" fetch -q "$bc_remote_dir" "$2:refs/kit/race-parent" || exit 1
_zp=\$(git -C "$bc_base/R" rev-parse refs/kit/race-parent)
_zt=\$(git -C "$bc_base/R" mktree </dev/null)
_zc=\$(printf 'racing child\n' | git -C "$bc_base/R" commit-tree "\$_zt" -p "\$_zp")
git -C "$bc_base/R" push -q "$bc_remote_dir" "\$_zc:$2"
git -C "$bc_base/R" update-ref -d refs/kit/race-parent >/dev/null 2>&1 || true
RACE_EOF
  }

  bc_mkclone R "Session R" r@example.com

  # leg (w): the basics — claim-ref never touches a board; the ref is real; a second claimant is
  # refused (no self-resume discrimination); the holder's own release-ref deletes the ref.
  bc_run "$bc_base/R" claim-ref ROW-CR1 --branch feat/cr1
  bc_expect_rc 0 "leg w/claim-ref: claim-ref on a fresh row -> rc 0"
  bc_has "leg w/claim-ref: the OK line names the ref" "refs/claims/ROW-CR1"
  if git --git-dir="$bc_remote_dir" rev-parse --verify -q refs/claims/ROW-CR1 >/dev/null; then
    bc_pass "leg w/claim-ref: refs/claims/ROW-CR1 EXISTS on the bare remote (a real push)"
  else
    bc_fail "leg w/claim-ref: refs/claims/ROW-CR1 absent from the remote after a claimed rc 0"
  fi
  if awk '/^## In Progress/{s=1;next} s&&/^## /{exit} s&&/ROW-CR1/{f=1} END{exit !f}' "$bc_base/R/BACKLOG.md"; then
    bc_fail "leg w/no-board: claim-ref edited the board — it must never read or write one"
  else
    bc_pass "leg w/no-board: claim-ref never touches a board"
  fi
  bc_run "$bc_base/R" claim-ref ROW-CR1 --branch feat/other
  bc_expect_rc 3 "leg w/second-claimant: claim-ref on an already-claimed row -> rc 3"
  bc_has "leg w/second-claimant: the refusal names the holder" "Session R <r@example.com>"
  bc_run "$bc_base/R" release-ref ROW-CR1
  bc_expect_rc 0 "leg w/release-ref: the holder releases -> rc 0"
  if git --git-dir="$bc_remote_dir" rev-parse --verify -q refs/claims/ROW-CR1 >/dev/null; then
    bc_fail "leg w/release-ref-deleted: refs/claims/ROW-CR1 survived release-ref"
  else
    bc_pass "leg w/release-ref-deleted: refs/claims/ROW-CR1 is GONE from the remote"
  fi

  # leg (x): release-ref's holder check and its narrower (P2-only) --stale proof set + the human dial.
  bc_run "$bc_base/R" claim-ref ROW-CR2 --branch feat/cr2
  bc_expect_rc 0 "leg x/setup: R claims ROW-CR2 via claim-ref"
  bc_mkclone S "Session S" s@example.com
  bc_run "$bc_base/S" release-ref ROW-CR2
  bc_expect_rc 1 "leg x/non-holder: S releases R's ref without --stale -> rc 1"
  bc_has "leg x/non-holder: the refusal names the holder" "Session R <r@example.com>"
  if git --git-dir="$bc_remote_dir" rev-parse --verify -q refs/claims/ROW-CR2 >/dev/null; then
    bc_pass "leg x/non-holder-noop: the refused release-ref did NOT delete the ref"
  else
    bc_fail "leg x/non-holder-noop: the refused release-ref deleted the ref anyway"
  fi
  bc_run "$bc_base/S" release-ref ROW-CR2 --stale
  bc_expect_rc 1 "leg x/stale-no-proof: no P2 proof and no force -> rc 1 (the ref-only proof set is P2 only)"
  bc_run_force "$bc_base/S" 'fixture teardown for claim-ref legs' release-ref ROW-CR2 --stale
  bc_expect_rc 0 "leg x/forced: the human dial releases the same ref -> rc 0"
  bc_has "leg x/forced: the forced release names the holder it removed" "Session R <r@example.com>"

  # leg (y): claim-ref --then, both directions — a succeeding step leaves the claim; a failing step
  # is COMPENSATED (the just-pushed ref is deleted) and the verb exits non-zero.
  bc_run "$bc_base/R" claim-ref ROW-CR3 --branch feat/cr3 --then "true"
  bc_expect_rc 0 "leg y/then-ok: claim-ref --then a succeeding step -> rc 0"
  if git --git-dir="$bc_remote_dir" rev-parse --verify -q refs/claims/ROW-CR3 >/dev/null; then
    bc_pass "leg y/then-ok: the ref survives a successful --then step"
  else
    bc_fail "leg y/then-ok: the ref vanished despite --then succeeding"
  fi
  bc_run "$bc_base/R" release-ref ROW-CR3
  bc_expect_rc 0 "leg y/then-ok-cleanup: release the row"
  bc_run "$bc_base/R" claim-ref ROW-CR4 --branch feat/cr4 --then "false"
  bc_expect_rc 1 "leg y/then-fail: claim-ref --then a FAILING step -> rc 1 (compensated)"
  bc_has "leg y/then-fail: the output says it compensated" "compensated"
  if git --git-dir="$bc_remote_dir" rev-parse --verify -q refs/claims/ROW-CR4 >/dev/null; then
    bc_fail "leg y/then-fail: the ref SURVIVED a failed --then step — compensation did not run"
  else
    bc_pass "leg y/then-fail: the ref was deleted (compensated) after --then failed"
  fi

  # leg (z): a FAILED COMPENSATION on claim-ref — the --then step (which also fails, forcing
  # compensation) first races a REAL child commit onto the same ref, so the lease claim-ref captured
  # from its OWN push no longer matches by the time it tries to delete. The compensating delete must
  # then fail loudly, name release-ref as the recovery verb, and leave the (now-raced) ref in place —
  # never silently drop the caller's problem.
  bc_mk_race_script "$bc_base/z-race.sh" refs/claims/ROW-CR5
  bc_run "$bc_base/R" claim-ref ROW-CR5 --branch feat/cr5 --then "sh $bc_base/z-race.sh && exit 1"
  bc_expect_rc 1 "leg z/failed-compensation: --then fails after racing the ref -> rc 1"
  bc_has "leg z/failed-compensation: the output NAMES the recovery verb" "release-ref ROW-CR5"
  if git --git-dir="$bc_remote_dir" rev-parse --verify -q refs/claims/ROW-CR5 >/dev/null; then
    bc_pass "leg z/failed-compensation: the ref (now the racing child) is STILL there — the compensation really failed"
  else
    bc_fail "leg z/failed-compensation: the ref vanished despite the compensating delete supposedly failing"
  fi
  git --git-dir="$bc_remote_dir" update-ref -d refs/claims/ROW-CR5 >/dev/null 2>&1 || true

  # leg (z2): a FAILED COMPENSATION on release-ref — the reverse shape. `--then` (standing in for the
  # caller's tracker-side release) SUCCEEDS, but the ref it races out from under release-ref means the
  # compensating delete (the actual ref release) then fails; release-ref must exit non-zero naming
  # itself as the recovery verb, and the ref must SURVIVE.
  bc_run "$bc_base/R" claim-ref ROW-CR6 --branch feat/cr6
  bc_expect_rc 0 "leg z2/setup: claim ROW-CR6 via claim-ref"
  bc_mk_race_script "$bc_base/z2-race.sh" refs/claims/ROW-CR6
  bc_run "$bc_base/R" release-ref ROW-CR6 --then "sh $bc_base/z2-race.sh"
  bc_expect_rc 1 "leg z2/failed-compensation: --then succeeds but the delete then fails -> rc 1"
  bc_has "leg z2/failed-compensation: the output NAMES release-ref as the recovery verb" "release-ref ROW-CR6"
  if git --git-dir="$bc_remote_dir" rev-parse --verify -q refs/claims/ROW-CR6 >/dev/null; then
    bc_pass "leg z2/failed-compensation: the ref (now the racing child) SURVIVES — nothing silently dropped"
  else
    bc_fail "leg z2/failed-compensation: the ref vanished despite the delete supposedly failing"
  fi
  git --git-dir="$bc_remote_dir" update-ref -d refs/claims/ROW-CR6 >/dev/null 2>&1 || true

  # leg (z3), M-2 (security fix round): `release-ref --stale --then false`, forced. Before the fix the
  # release record was written BEFORE `--then` ran, so a `--then` failure still left
  # `refs/claims-log/ROW-CR7` asserting a release that never happened, with no `-FAILED` compensation
  # (there was nothing TO compensate — the log write itself was the premature act). Now: the ref
  # SURVIVES (R still holds it) and the log carries NO entry at all for this row.
  bc_run "$bc_base/R" claim-ref ROW-CR7 --branch feat/cr7
  bc_expect_rc 0 "leg z3/setup: R claims ROW-CR7 via claim-ref"
  bc_run_force "$bc_base/S" 'fixture leg z3 — proving the log no longer precedes a failing --then' release-ref ROW-CR7 --stale --then false
  bc_expect_rc 1 "leg z3/then-fails-before-log: release-ref --stale --then false, forced -> rc 1"
  bc_has "leg z3/then-fails-before-log: the refusal says nothing was logged" "nothing was logged"
  if git --git-dir="$bc_remote_dir" rev-parse --verify -q refs/claims/ROW-CR7 >/dev/null; then
    bc_pass "leg z3/then-fails-before-log: the ref SURVIVES — release-ref never reached the delete"
  else
    bc_fail "leg z3/then-fails-before-log: the ref vanished despite --then having failed"
  fi
  _z3log=$(
    _ll_gd2=$(bc_iso_dir) || true
    if [ -n "${_ll_gd2:-}" ] && git -C "$_ll_gd2" fetch --no-tags --depth=1 "$bc_remote_dir" "$BC_LOG_NS/ROW-CR7:refs/scratch" >/dev/null 2>&1; then
      git -C "$_ll_gd2" show refs/scratch:LOG 2>/dev/null
    fi
    [ -n "${_ll_gd2:-}" ] && rm -rf "$_ll_gd2"
  )
  if [ -z "$_z3log" ]; then
    bc_pass "leg z3/then-fails-before-log: refs/claims-log/ROW-CR7 carries NO entry (M-2 — the log never preceded the failing --then)"
  else
    bc_fail "leg z3/then-fails-before-log: a log entry exists for ROW-CR7 despite --then having failed first; entry=[$_z3log]"
  fi
  bc_run "$bc_base/R" release-ref ROW-CR7
  bc_expect_rc 0 "leg z3/cleanup: R releases ROW-CR7"

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
# bc_v_ncols <row-line> -> the number of columns a GFM-exact split (SAME odd-backslash-run rule as
# bc_cell/bc_col_index) produces for that raw row line. Test-only: leg (v) uses it to prove the
# WRITE path never changes a row's column count (BOARD-PIPE-ESCAPE T5, §6.1 leg 5).
bc_v_ncols() {
  printf '%s' "$1" | awk -F'|' '
    {
      n=0; s=""
      for (j=2; j<=NF; j++) {
        s = (s=="") ? $j : s "|" $j
        t=s; run=0
        while ((L=length(t)) > 0 && substr(t,L,1)=="\\") { run++; t=substr(t,1,L-1) }
        if (run % 2 == 1) continue
        if (j==NF && s ~ /^[ \t]*$/) break
        n++
        s=""
      }
      print n
    }'
}

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

# bc_mkchainlink <row> <n> <parent-sha> -> echo a claim commit for session s-19700101-<8-digit n>,
# chained onto <parent-sha> when one is given. Built with the same plumbing the verb uses, so the
# 40-deep fixture leg (u/status) drives is a REAL chain of real claim commits.
bc_mkchainlink() {
  (
    cd "$bc_base/A" || exit 1
    _cl_sess=$(printf 's-19700101-%08d' "$2")
    _cl_blob=$(printf 'row: %s\nclaimant: Deep Session <deep@example.com>\nbranch: feat/vanished\nclaimed-at: 2026-09-01T00:00:00Z\nsession: %s (declared)\n' \
                 "$1" "$_cl_sess" | git hash-object -w --stdin)
    _cl_tree=$(printf '100644 blob %s\tCLAIM\n' "$_cl_blob" | git mktree)
    if [ -n "$3" ]; then
      printf 'chain %s\n' "$2" | git commit-tree "$_cl_tree" -p "$3"
    else
      printf 'chain %s\n' "$2" | git commit-tree "$_cl_tree"
    fi
  )
}

# bc_run <clone-dir> <args...> — run THIS script inside the clone, capturing rc + merged output.
bc_run() {
  _bd=$1; shift
  if bc_out=$( cd "$_bd" && sh "$BC_SELF" "$@" 2>&1 ); then bc_rc=0; else bc_rc=$?; fi
}
# bc_run_badremote — the same, with origin pointed at a path that does not exist. THE honest way to
# make a remote unreachable: no stub pretending to fail, a genuinely absent remote.
# bc_run_wipcfg <clone-dir> <budget-conf> <args…> — run the verb with the runaway guard's ceiling
# config pointed at a fixture. The guard REFUSES a redirected config unless KIT_RUNAWAY_SANDBOX
# vouches for it, so the dial is declared here (pointing at the selftest's own fixture root) exactly
# as a human would have to declare it. The verb itself is unchanged; only the ceiling it reads moves.
bc_run_wipcfg() {
  _bd=$1; _bcfg=$2; shift 2
  if bc_out=$( cd "$_bd" && KIT_RUNAWAY_SANDBOX="$bc_base" RUNAWAY_BUDGET_CONFIG="$_bcfg" \
                 sh "$BC_SELF" "$@" 2>&1 ); then bc_rc=0; else bc_rc=$?; fi
}
# bc_ghstub <lines> — write a STUB `gh` whose `pr list` prints the given "<state> <isCross>" lines.
# The P2 proof is the one evidence line that needs a forge, and a selftest must never touch the real
# one: the stub is the honest fixture, and it is the ONLY way to drive the CLOSED / OPEN-shadow /
# cross-repository shapes the security seat's condition [sec-3] is about.
bc_ghstub() {
  printf '%s\n' "$1" > "$bc_base/ghstub/prlist"
  # The stub RECORDS ITS ARGV as well as answering, so a leg can assert what actually reached `gh`
  # (the `--repo` derivation, L7) instead of asserting that the script contains a flag.
  cat > "$bc_base/ghstub/gh" <<'GHSTUB_EOF'
#!/bin/sh
printf '%s\n' "$*" > "$(dirname "$0")/argv"
case "$1" in
  pr) cat "$(dirname "$0")/prlist" ;;
  *)  exit 1 ;;
esac
GHSTUB_EOF
  chmod +x "$bc_base/ghstub/gh"
}
# bc_run_gh — the verb with the stub `gh` FIRST on PATH.
bc_run_gh() {
  _bd=$1; shift
  if bc_out=$( cd "$_bd" && PATH="$bc_base/ghstub:$PATH" sh "$BC_SELF" "$@" 2>&1 ); then bc_rc=0; else bc_rc=$?; fi
}
# bc_run_force <clone> <reason> <args…> — the human dial, declared exactly as a human declares it.
bc_run_force() {
  _bd=$1; _breason=$2; shift 2
  if bc_out=$( cd "$_bd" && KIT_CLAIM_FORCE_RELEASE="$_breason" sh "$BC_SELF" "$@" 2>&1 ); then bc_rc=0; else bc_rc=$?; fi
}
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
# The WIP ceiling is the runaway guard's to enforce (it owns .kit/budget.conf). Resolved from THIS
# script's own directory, never $PWD. A tree without the guard simply has no WIP ceiling — `claim`
# keeps working, which is the upgrade path for an adopter who has not taken the guard.
BC_GUARD=$(dirname -- "$BC_SELF")/runaway-guard.sh

bc_cmd="${1:-}"
[ $# -gt 0 ] && shift || true
case "$bc_cmd" in
  claim)       if do_claim       "$@"; then bc_rc_main=0; else bc_rc_main=$?; fi ;;
  release)     if do_release     "$@"; then bc_rc_main=0; else bc_rc_main=$?; fi ;;
  check)       if do_check       "$@"; then bc_rc_main=0; else bc_rc_main=$?; fi ;;
  status)      if do_status      "$@"; then bc_rc_main=0; else bc_rc_main=$?; fi ;;
  claim-ref)   if do_claim_ref   "$@"; then bc_rc_main=0; else bc_rc_main=$?; fi ;;
  release-ref) if do_release_ref "$@"; then bc_rc_main=0; else bc_rc_main=$?; fi ;;
  --selftest)  if selftest;            then bc_rc_main=0; else bc_rc_main=$?; fi ;;
  -h|--help) bc_usage; bc_rc_main=2 ;;
  *)         bc_usage; bc_rc_main=2 ;;
esac
exit "$bc_rc_main"
