#!/bin/sh
# runaway-guard.sh — E4d executable runaway circuit-breaker (harness-neutral).
#
# The kit cannot MEASURE tokens (the harness/LLM-API does); it ENFORCES a ceiling on REPORTED
# usage at the orchestration seam and halts the loop. The platform LLM-API cap is the hard ceiling
# ABOVE this. The ceiling config (.kit/budget.conf) + this script are control-plane (agent-immutable);
# the tally is best-effort runtime state (platform cap is the backstop if defeated).
#
# ONE TALLY PER REPO, ONE CEILING PER ROW (B4-CROSS-SESSION-BUDGET, docs/architecture/2026-09-15-b4-
# cross-session-budget-design.md; RUNAWAY-CEILING-PER-SLICE, docs/plans/2026-09-28-runaway-ceiling-per-
# slice.md). The tally used to be `.kit-run/tally`, RELATIVE TO $PWD and gitignored — so N parallel
# sessions in N worktrees each got their own silent ceiling, which is N times the ceiling the owner
# declared. There is now ONE `tally.v2` per repo, at $HOME/.local/state/sparkwright/runaway/<root-commit>/
# (keyed by the repo's root commit, so every worktree of the repo shares it), anchored on $HOME only (no
# XDG_STATE_HOME: git ignores that variable, so honouring it would be a third, unbannered redirection
# route that costs an agent nothing). Every line carries the SESSION KEY of the worktree that wrote it
# and the ROW it was charged to; EACH ROW IS GRADED ALONE against its own ceiling, so a second slice's
# normal work never trips the first one's. `reset` is retired (a new row starts at zero). `check` with
# no --row lists the rows and flags never-claimed ones; a raise for one row is a `RAISE <ROW> ...`
# line in the config.
#
# Usage:
#   runaway-guard.sh step  --row ROW --tokens N --agents N   # record this step's usage against ROW, grade ROW alone
#                          (--row is required, no env fallback; prints `metered: ROW tokens(n/N) agents(n/N)`)
#   runaway-guard.sh check --row ROW               # ROW's verdict, the same rc as `step` would give, writes nothing
#   runaway-guard.sh check                         # list every row of this repo (rc 1 if any is at its ceiling), then
#                                                  # ONE `git ls-remote` (outside the lock) flags `never claimed: ROW`
#   runaway-guard.sh meter --row ROW               # READ-ONLY: `metered: ROW tokens(n/N) agents(n/N) lines=k` (rc 0 under its
#                                                  # ceiling, rc 1 at/past it) or `unmetered: ROW ...` (rc 3: never metered)
#   runaway-guard.sh reset                         # RETIRED (rc 2): the budget is per slice, a new row starts at zero
#   runaway-guard.sh wip   --count N               # is another slice already in flight? (MAX_WIP)
# Exit: 0 continue (WARN on stderr at >=WARN_PCT) | 1 STOP (ceiling breached) | 2 UNVERIFIED (bad
#       config / poisoned tally / hostile state dir / lock timeout / a refused override) | 3 (`meter` only)
#       the row was never metered.
# What it changes: Appends to the PER-REPO runaway tally at $HOME/.local/state/sparkwright/runaway/<root-commit>/tally.v2 (serialized by a mkdir lock beside it; the v1 file runaway/tally is never read or written; `reset` is retired and writes nothing); reads the ceiling config (default .kit/budget.conf, resolved from this script's own root, never $PWD) and, to compare it with its committed copy, `git show HEAD:<conf>`; `check` with no --row also makes ONE NETWORK READ, `git ls-remote ${BOARD_CLAIM_REMOTE:-origin}`, OUTSIDE the lock, and writes nothing. `wip` reads only the config.
# Guardrails: Fail-closed (exit 2) on a missing/bad config, a tally line that is not the five-field grammar, a tally past the line cap, a shallow clone or a repo with no commit (no stable repo key), a symlinked or foreign-owned state dir, a non-absolute $HOME, or a lock it cannot take within its bounded 30s spin (a dead holder's lock is broken only when its `<pid> <epoch>` token is also older than 2s, so a stale read cannot rename a live holder's lock away); the summed usage CLAMPS toward the ceiling so an overflow can never read as under-budget; both redirection routes (--tally/RUNAWAY_TALLY, --config/RUNAWAY_BUDGET_CONFIG) are REFUSED unless the human dial KIT_RUNAWAY_SANDBOX names a directory the path canonicalizes under, and every sandboxed invocation BANNERS on stderr; exit 1 (STOP) when ONE ROW's own ceiling is breached (each row is graded alone, so a second slice's normal work is silent); a `RAISE <ROW> MAX_TOKENS=<n> MAX_AGENTS=<n> MAX_STEPS=<n>` config line (any subset, at least one) lifts that row only and a malformed one is rc 2 naming the line; an edited base MAX_* (bytes differ from HEAD's committed copy) is honoured but WARNs on every step and check ("unscoped raise"); an unreachable claim remote never changes the grading rc (`claims UNVERIFIED`); `reset` is rc 2; the config is control-plane (agent-immutable), the platform LLM-API cap is the hard backstop above it.
set -eu
umask 077
# CONTROL — THE C LOCALE PIN (security F1). Do not remove. It gives BYTE semantics to the tally grammar
# (the write/read parity of R1/H3: a bracket class or awk range must judge a byte the same on the write
# side and the read side, whatever locale the caller has), and it keeps `kill`'s EPERM text
# untranslated for the S2 foreign-uid check in rg_pid_dead (glibc localizes strerror; this is
# reasoning, not a test). Removing it re-opens both. Side effect: NBSP around `=` in budget.conf is no
# longer accepted (stricter, fail-closed).
LC_ALL=C; export LC_ALL

RG_HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
RG_DEFAULT_CONFIG="$RG_HERE/../.kit/budget.conf"
RG_LINE_CAP=100000
RG_CLAMP=1000000000000000      # 10^15 — the sum clamps here, toward the ceiling, never wrapping
# ⚠️ 300 x 0.1s = a 30-SECOND bound, raised from 5s after CI measured the old one (B4 CI round).
# The contenders SERIALIZE by construction, so the bound must cover N holders, not one: 20 parallel
# steps on a 2-vCPU ubuntu runner exceeded 5s and a correct fail-closed timeout was then read by the
# leg as a lost append. Still bounded, still rc 2 on expiry — design decision 3 is honoured, not
# traded. RG_LOCK_MIN_AGE is the ABA gate: a lock younger than this is never broken.
RG_LOCK_TRIES=300
RG_LOCK_MIN_AGE=2

die2() { printf '%s\n' "$*" >&2; exit 2; }

# ── overrides: both redirection routes are refused unless the human dial vouches for the path ─────
CONFIG="$RG_DEFAULT_CONFIG"; TALLY=""
rg_cfg_via=""; rg_tally_via=""
if [ -n "${RUNAWAY_BUDGET_CONFIG:-}" ]; then CONFIG="$RUNAWAY_BUDGET_CONFIG"; rg_cfg_via="RUNAWAY_BUDGET_CONFIG"; fi
if [ -n "${RUNAWAY_TALLY:-}" ];         then TALLY="$RUNAWAY_TALLY";         rg_tally_via="RUNAWAY_TALLY"; fi

# rg_canon <path> -> the canonical absolute path (the DIRECTORY is resolved with `cd … && pwd -P`;
# the leaf is appended verbatim). Returns 1 when the directory does not exist.
rg_canon() {
  _rc_d=$(dirname -- "$1"); _rc_b=$(basename -- "$1")
  _rc_p=$(CDPATH='' cd -- "$_rc_d" 2>/dev/null && pwd -P) || return 1
  [ -n "$_rc_p" ] || return 1
  case "$_rc_b" in
    .)  printf '%s\n' "$_rc_p" ;;
    ..) dirname -- "$_rc_p" ;;
    *)  case "$_rc_p" in /) printf '/%s\n' "$_rc_b" ;; *) printf '%s/%s\n' "$_rc_p" "$_rc_b" ;; esac ;;
  esac
}

# rg_vet_override <what> <spelling> <path> — REFUSE unless KIT_RUNAWAY_SANDBOX is set AND the path
# canonicalizes under it. Both sides are canonicalized and the prefix carries a trailing slash, so
# /tmp/x never vouches for /tmp/xy; a symlinked leaf is refused outright (it is a hop out of the dir).
rg_vet_override() {
  if [ -z "${KIT_RUNAWAY_SANDBOX:-}" ]; then
    printf 'runaway-guard: REFUSED (2) — %s was redirected via %s.\n' "$1" "$2" >&2
    printf '               A second tally or a second config is a SECOND CEILING, which is the exact\n' >&2
    printf '               defect this guard exists to close. Redirection is a human act: set\n' >&2
    printf '               KIT_RUNAWAY_SANDBOX=<dir> and pass a path under it (every such run banners).\n' >&2
    exit 2
  fi
  _vo_s=$(CDPATH='' cd -- "$KIT_RUNAWAY_SANDBOX" 2>/dev/null && pwd -P) \
    || die2 "runaway-guard: REFUSED (2) — KIT_RUNAWAY_SANDBOX='$KIT_RUNAWAY_SANDBOX' is not a directory."
  [ -L "$3" ] && die2 "runaway-guard: REFUSED (2) — $1 '$3' is a symlink; a sandboxed path may not hop out of the sandbox." || :
  _vo_p=$(rg_canon "$3") \
    || die2 "runaway-guard: REFUSED (2) — $1 '$3' does not resolve (its directory does not exist)."
  case "$_vo_p" in
    "$_vo_s"/*) : ;;
    *) die2 "runaway-guard: REFUSED (2) — $1 '$_vo_p' is OUTSIDE the sandbox '$_vo_s' ($2)." ;;
  esac
}

# ── the per-machine state dir ────────────────────────────────────────────────────────────────────
# Anchored on $HOME only. Refuses a non-absolute $HOME, and refuses a `sparkwright/`, `runaway/`,
# tally or lock that is a SYMLINK or is not owned by the invoking uid — the tally is a file other
# local processes can reach, so a redirected component must never be written THROUGH. The
# check-then-write window is inside the same-uid honest ceiling (docs/operations/runaway-killswitch.md).
rg_state_dir() {
  case "${HOME:-}" in
    /*) : ;;
    *)  die2 "runaway-guard: REFUSED (2) — \$HOME ('${HOME:-}') is not an absolute path; the per-machine tally has nowhere to live." ;;
  esac
  # ⚠️ EVERY ANCESTOR IS VETTED, NOT JUST THE LAST TWO (R1/L1). `mkdir -p` FOLLOWS a symlinked
  # `.local` or `.local/state`, so the tally landed outside $HOME while the hygiene checks below —
  # which only ever looked at `sparkwright/` and `runaway/` — reported clean. Each component is
  # created and checked in turn, so no `-p` ever traverses a link this function has not judged.
  rg_safe_dir "$HOME/.local"
  rg_safe_dir "$HOME/.local/state"
  _sd="$HOME/.local/state/sparkwright"
  rg_safe_dir "$_sd"
  _sd="$_sd/runaway"
  rg_safe_dir "$_sd"
  # ⚠️ THE PER-REPO LEVEL IS VETTED LIKE EVERY OTHER (RUNAWAY-CEILING-PER-SLICE R8). $RG_KEY was set
  # by rg_repo_key in the CALLER's shell (a global, never an echo), and is 40/64-char hex by then, so
  # it is safe as a path component; rg_safe_dir still refuses a symlinked or foreign-owned <key>/.
  [ -n "${RG_KEY:-}" ] || die2 "runaway-guard: REFUSED (2) — no repo key was derived (internal: rg_repo_key must run first)."
  _sd="$_sd/$RG_KEY"
  rg_safe_dir "$_sd"
  printf '%s\n' "$_sd"
}

# ── the repo key: the first-parent ROOT COMMIT of $PWD's repo ────────────────────────────────────
# Stable across ssh/https/local-path clones, worktrees, dev-clones and merges of unrelated histories,
# and it needs no remote. A SHALLOW repo's "root" is the shallow boundary, which moves with every
# fetch, so it is refused (rc 2) rather than keyed. Validated as 40- or 64-char lowercase hex before
# it is ever a path component. ⚠️ SETS THE GLOBAL RG_KEY, IT DOES NOT ECHO: a die2 inside `$(…)` would
# only exit the SUBSHELL (the R1/L6 note on the step arm). The pipeline below is the one place a
# status is swallowed, so its output is captured first and judged after.
rg_repo_key() {
  RG_KEY=""
  _rks=$(git -C "$PWD" rev-parse --is-shallow-repository 2>/dev/null) \
    || die2 "runaway-guard: REFUSED (2) — \$PWD is not inside a git work tree, so this run has no repo key."
  [ "$_rks" != true ] \
    || die2 "runaway-guard: REFUSED (2) — this is a SHALLOW clone: its root commit is the shallow boundary and moves with every fetch, so the per-repo tally has no stable key. Run 'git fetch --unshallow' and retry."
  _rkall=$(git -C "$PWD" rev-list --max-parents=0 --first-parent HEAD 2>/dev/null) \
    || die2 "runaway-guard: REFUSED (2) — this repository has no commit, so it has no repo key."
  _rk=$(printf '%s\n' "$_rkall" | tail -1)
  case "$_rk" in
    ''|*[!0123456789abcdef]*) die2 "runaway-guard: REFUSED (2) — the root commit is not lowercase hex; refusing to use it as a path component." ;;
  esac
  case "${#_rk}" in
    40|64) : ;;
    *) die2 "runaway-guard: REFUSED (2) — the root commit is not a 40- or 64-character hash; refusing to use it as a path component." ;;
  esac
  RG_KEY="$_rk"
}

# rg_row_ok <ROW> — the board's row grammar, [A-Z0-9][A-Z0-9-]*, at most 64 characters.
rg_row_ok() {
  case "${1:-}" in
    ''|[!ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789]*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ] || return 1
  return 0
}

rg_safe_dir() {
  [ -L "$1" ] && die2 "runaway-guard: REFUSED (2) — '$1' is a symlink; refusing to write the tally THROUGH a redirected state directory." || :
  if [ ! -d "$1" ]; then
    mkdir "$1" 2>/dev/null || die2 "runaway-guard: REFUSED (2) — cannot create '$1'."
  fi
  # shellcheck disable=SC3067  # `-O` is outside POSIX test, and MEASURED present on every shell this
  # runs under (dash 0.5.12, bash 3.2 on macOS, the /bin/sh of the CI ubuntu image). A shell that
  # lacked it would make `[` fail, which lands on die2 — the fail-CLOSED direction, by construction.
  [ -O "$1" ] || die2 "runaway-guard: REFUSED (2) — '$1' is not owned by this user; refusing to share a tally with another uid."
}

rg_safe_file() {   # the tally itself: never a symlink, never someone else's file
  # ⚠️ `-L` FIRST: `-e` FOLLOWS the link, so a symlink pointing at a path that does not exist yet
  # (the dangling-symlink plant — the append CREATES the target) reads as "absent" and sails through.
  [ -L "$1" ] && die2 "runaway-guard: REFUSED (2) — the tally '$1' is a symlink; refusing to write THROUGH it." || :
  [ -e "$1" ] || return 0          # not there yet: the append creates it, under this run's umask 077
  # shellcheck disable=SC3067  # see the note in rg_safe_dir: measured-present, and fail-closed if not.
  [ -O "$1" ] || die2 "runaway-guard: REFUSED (2) — the tally '$1' is not owned by this user."
  return 0
}

# ── the session key ──────────────────────────────────────────────────────────────────────────────
# The sanitized work-tree root of $PWD. §5 rule 1 already binds ONE WORKTREE PER SESSION, so the
# worktree IS the session and no new identity mechanism is invented here.
# ⚠️ B2-SESSION-IDENTITY-LEDGER DECLINED THE SUPERSESSION (decision 9, 2026-09-16), and the earlier
# note here that B2's declared `session.id` "supersedes this additively" is withdrawn. B4 permitted
# it; B2 measured what it would cost. The key would CHANGE MID-RUN — a run starts, then `claim` mints
# the id — and every line already tallied under the worktree key would be ORPHANED, counting toward
# their row's ceiling until a human deletes the file. That fails toward STOP, which is the right
# direction, but it is a footgun with no consumer asking for it. Revisit when one does (a B3/B5
# design sitting wanting per-session tally attribution). Sanitized before it is ever a field, a
# `case` pattern or a path
# component. Outside a work tree there is no key, and that is rc 2, not a shared bucket.
rg_session_key() {
  _sk=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null) \
    || die2 "runaway-guard: REFUSED (2) — \$PWD is not inside a git work tree, so this run has no session key."
  [ -n "$_sk" ] || die2 "runaway-guard: REFUSED (2) — \$PWD is not inside a git work tree, so this run has no session key."
  printf '%s' "$_sk" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-128
}

# ── the lock: mkdir-only, one code path, stale-break by atomic rename ────────────────────────────
# `flock` is absent on macOS (measured), and a two-implementation lock has one path macOS never
# exercises and one CI never exercises. `mkdir` is atomic on every POSIX filesystem. A lock dir with
# NO pid file is the holder's creation window and counts as LIVE; a token that is not exactly
# `<pid> <epoch>`, both [0-9]{1,10}, counts as LIVE (never as dead — `kill -0 -1` would otherwise
# succeed forever); only a validated, dead pid whose lock is ALSO at least RG_LOCK_MIN_AGE seconds
# old is broken, and the break is a RENAME of the TOKEN FILE so exactly one of two simultaneous breakers
# wins it. The dir at the lock path is never renamed, moved or restored by anyone — EXCEPT the holder moving
# its OWN dir at release (A9, rg_unlock). An abandoned takeover (no pid, one dead `pid.dead.<b>`; A7) is adopted by
# an atomic `mv` of that file, and an orphan empty dir (a taker killed between mkdir and ln; A8) is `rmdir`ed.
#
# ⚠️ THE EPOCH IS THE ABA DEFENCE, AND THE ABA IS REAL (found by inspection at review): a contender
# reads holder A's pid; A finishes and releases; B mkdir's the lock and writes ITS pid; the
# contender's `kill -0 A` now says "dead" and it moves B's LIVE token away — two holders, both
# appending. A recycled lock always carries a FRESH epoch, so an age gate makes a stale read
# unable to break a fresh holder. The post-move re-read closes the residual window: if what we
# moved is not the exact token we judged, we moved somebody else's token and we put it back.
RG_LOCK=""; RG_LOCK_HELD=0
# rg_num10 — the lock token's field grammar, [0-9]{1,10}, applied to BOTH fields. Anything else is
# read as LIVE, never as dead: fail-closed is a lock nobody breaks, not a lock anybody may break.
rg_num10() {
  case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac
  [ "${#1}" -le 10 ] || return 1
  return 0
}
# rg_pid_dead — true only when the pid is KNOWN dead. ⚠️ A NON-ZERO `kill -0` IS NOT "DEAD" (security
# S2): a pid owned by ANOTHER UID answers EPERM ("Operation not permitted"), which proves the process
# EXISTS. Reading that as dead let a token like `1 <old-epoch>` — init, or any root process — break a
# lock. Existence unknown must fall to LIVE, the fail-closed side.
rg_pid_dead() {
  if kill -0 "$1" 2>/dev/null; then return 1; fi          # answered: alive
  _kd=$(kill -0 "$1" 2>&1) || :
  case "$_kd" in
    *[Nn]"ot permitted"*|*EPERM*) return 1 ;;             # exists, owned by someone else -> LIVE
  esac
  return 0
}
# rg_pidless_probe — the lock dir has NO pid. Sets _lnd = how many `pid.dead.*` it holds; and, ONLY when there is at
# least one and EVERY suffix <b> passes rg_num10 and names a DEAD pid (EPERM counts as alive), _lsrc = the ONE with the
# numerically LOWEST suffix (deterministic, so two contenders pick the same file and the atomic `mv` arbitrates) and
# _lsrcp = its token line (A7: an abandoned takeover — a breaker SIGKILLed between moving the token out and publishing
# its own, possibly twice over; the caller then gates the token itself on dead + old before adopting it). ANY alive or
# malformed <b> (a takeover in progress) leaves _lsrc empty: LIVE, no action.
# The OTHER dead files are left where they are: the adopter now HOLDS the dir, so it is non-empty by design, and
# the release (A9) moves the whole dir away and deletes it, leftovers included.
# ⚠️ THIS PROBE READS THE TOKEN INSIDE EVERY `pid.dead.*`, NOT ONLY THE ADOPTED ONE (F1). A dead SUFFIX does not make the
# token in that file dead: a live holder's token can be moved aside by an ABA breaker that is then SIGKILLed, and beside
# an older leftover whose suffix is also dead. Judged by suffix alone, the probe adopted the leftover's dead token and
# took over while the live holder still held the lock (a double hold). So EVERY file must pass BOTH tests — the suffix
# is a dead pid AND the token's own pid (`<pid> <epoch>`, parsed as the break arm parses it) is a dead pid, EPERM counting
# as live — and any file that is live, EPERM, malformed, empty or unreadable leaves _lsrc empty: LIVE, fail-closed.
rg_pidless_probe() {
  _lnd=0; _lsrc=""; _lsrcp=""; _llow=""
  for _lf in "$RG_LOCK"/pid.dead.*; do
    [ -e "$_lf" ] || continue
    _lnd=$((_lnd + 1))
    _lbp=${_lf##*/pid.dead.}
    _lfl=$(head -1 "$_lf" 2>/dev/null || true)
    _lfp=""
    case "$_lfl" in *' '*) _lfp=${_lfl%% *} ;; esac
    if rg_num10 "$_lbp" && rg_pid_dead "$_lbp" && rg_num10 "$_lfp" && rg_pid_dead "$_lfp"; then
      if [ -z "$_llow" ] || [ "$_lbp" -lt "$_llow" ]; then _llow="$_lbp"; _lsrc="$_lf"; fi
    else
      _lsrc=""; return 0
    fi
  done
  [ -z "$_lsrc" ] || _lsrcp=$(head -1 "$_lsrc" 2>/dev/null || true)
  return 0
}
# rg_orphan_old — A8: true only when the lock dir is older than RG_LOCK_ORPHAN_AGE seconds (digits only, else 10).
# The age is the dir's mtime read with `find -maxdepth 0 -mmin +N` (BSD and GNU `stat` differ; -mmin is in both),
# so the effective age is MINUTES with a floor of 1: an orphan is reaped after at least a minute, never sooner.
# If find cannot answer, the output is empty and nothing is reaped: fail closed.
# ⚠️ ACCEPTED RESIDUAL (M3, noted in the review record): a taker stalled for >= RG_LOCK_ORPHAN_AGE inside its
# mkdir -> `ln` window (e.g. under SIGSTOP) can, after a reap, publish into a live holder's set-aside window (an ABA
# put-back, or a killed breaker), giving a double hold. It needs a stall of at least a minute; it is not closed here.
# Same family (SEC-3): a TERM landing after a failed `ln` publish but before HELD=0 makes the trap's release move
# whatever dir is at the lock path. That dir is foreign only after an A8 reap plus a stall of at least a minute.
# Accepted. The optional closure (remember our token and compare it at unlock) is noted for a future hardening row.
rg_orphan_old() {
  _oa="${RG_LOCK_ORPHAN_AGE:-10}"
  case "$_oa" in ''|*[!0-9]*) _oa=10 ;; esac
  [ "${#_oa}" -le 9 ] || _oa=10
  _om=$(( _oa / 60 )); [ "$_om" -ge 1 ] || _om=1
  [ -n "$(find "$RG_LOCK" -maxdepth 0 -mmin "+$_om" 2>/dev/null)" ]
}
# rg_unlock — release by the ONE permitted move of the lock dir: the HOLDER moves ITS OWN dir away, THEN deletes
# it (A9). An in-place `rm -rf` left a window where a breaker could publish a token into the dir before the rm
# reached the old one, and the breaker would then believe it held a dir that was being deleted. After the move a
# breaker's `ln` into the lock path is ENOENT (a lost take). If the move fails the dir is already gone: never
# `rm` the lock path itself.
rg_unlock() {
  # ⚠️ THE FLAG IS CLEARED BEFORE THE MOVE, NOT AFTER (N1). The signal traps run this again: a TERM landing while the
  # `rm` below runs re-entered the release with HELD still 1, and by then a FOREIGN holder may own the lock path — the
  # second `mv` moved ITS live dir. Cleared first, a re-entry is a no-op. The cost: a TERM between the clear and the
  # `mv` leaves this process's own token in place, which is a dead pid's token once it exits; the age gate
  # (RG_LOCK_MIN_AGE) breaks that, so the result is fail-safe, never a wedge. A half-done `rel.$$` is removed by rg_cleanup.
  if [ "$RG_LOCK_HELD" = 1 ]; then
    RG_LOCK_HELD=0
    mv "$RG_LOCK" "$RG_LOCK.rel.$$" 2>/dev/null && { rm -rf "$RG_LOCK.rel.$$" || :; }
  fi
  return 0
}
# ⚠️ THE SIGNAL TRAPS EXIT; THE EXIT TRAP ONLY CLEANS UP (R1/H1). A single
# `trap 'rg_unlock' EXIT INT TERM` releases the lock on SIGINT/SIGTERM and then RESUMES the
# interrupted flow — so a step killed mid-spin carried on to record() and check_verdict() with
# RG_LOCK_HELD=0, i.e. an UNLOCKED APPEND reported as rc 0. Interrupted means UNVERIFIED, always.
# N2: everything the claims read starts (the git process `_cp`, its watchdog `_cs`, the claims temp file `_cf`)
# and rg_unscoped_warn's temp file (`_uw_tmp`) live in GLOBALS so ONE cleanup, run by BOTH traps, can reach
# them: an interrupted or aborted check must leave no temp file and no armed sleeper. Each is cleared the
# moment its owner is done with it, so the cleanup never signals a recycled pid or removes a stranger's file.
_cp=""; _cs=""; _cf=""; _uw_tmp=""; _lk_tok=""
rg_cleanup() {
  [ -z "$_lk_tok" ] || rm -f "$_lk_tok"
  # A9: a release interrupted between its move and its delete leaves this process's own moved-away dir
  { [ -z "$RG_LOCK" ] || [ ! -e "$RG_LOCK.rel.$$" ] || rm -rf "$RG_LOCK.rel.$$"; } || :
  [ -z "$_cs" ] || kill "$_cs" 2>/dev/null || :
  [ -z "$_cp" ] || kill "$_cp" 2>/dev/null || :
  [ -z "$_cf" ] || rm -f "$_cf"
  [ -z "$_uw_tmp" ] || rm -f "$_uw_tmp"
  return 0
}
trap 'rg_cleanup; rg_unlock' EXIT
trap 'rg_cleanup; rg_unlock; exit 2' INT TERM

rg_lock() {
  RG_LOCK="$1"
  [ -L "$RG_LOCK" ] && die2 "runaway-guard: REFUSED (2) — the lock path '$RG_LOCK' is a symlink." || :
  _lt=0
  while [ "$_lt" -lt "$RG_LOCK_TRIES" ]; do
    if mkdir "$RG_LOCK" 2>/dev/null; then
      # ⚠️ HELD IS SET BY THE mkdir, NOT BY THE PID WRITE (R1/M1). Between the two, a failed pid
      # write aborts under `set -eu` — and with HELD still 0 the EXIT trap leaves a PID-LESS lock
      # dir behind, which every contender correctly reads as LIVE forever: one failed write wedges
      # the machine. Ownership begins at the atomic mkdir; the pid file is only the liveness token.
      RG_LOCK_HELD=1
      # ⚠️ THE PUBLISH IS THE OWNERSHIP ARBITER, AND IT MAY LOSE (b4/breakers flake, RUNAWAY-CEILING-PER-
      # SLICE T2). Between the mkdir and the publish the slot can change hands; a lost publish is a lost
      # take, never an abort (under `set -e` an abort left an unowned pid-less dir that reads as LIVE
      # forever): not held, count a try, spin on. `rmdir` (never `rm -rf`) removes the dir only if it is
      # still empty, i.e. still a pid-less creation window nobody owns.
      # THE DIR AT THE LOCK PATH IS NEVER RENAMED, MOVED OR RESTORED BY ANYONE (EXCEPT THE HOLDER MOVING ITS OWN
      # DIR AT RELEASE, rg_unlock); ONLY THE TOKEN FILE MOVES.
      # The token is written to a private side file first and PUBLISHED with `ln` (no `-f`): it links only
      # if `pid` does not exist, so a publish can never overwrite or follow into somebody else's slot.
      _lk_tok="$RG_LOCK.tok.$$"
      rm -f "$_lk_tok"
      if ( set -C; printf '%s %s\n' "$$" "$(date -u +%s)" > "$_lk_tok" ) 2>/dev/null \
         && ln "$_lk_tok" "$RG_LOCK/pid" 2>/dev/null; then
        rm -f "$_lk_tok"; _lk_tok=""
        return 0
      fi
      rm -f "$_lk_tok"; _lk_tok=""
      RG_LOCK_HELD=0
      rmdir "$RG_LOCK" 2>/dev/null || :
      _lt=$((_lt + 1))
      continue
    fi
    _lp=""; _ls="$RG_LOCK/pid"
    [ -f "$RG_LOCK/pid" ] && _lp=$(head -1 "$RG_LOCK/pid" 2>/dev/null || true) || :
    # A7 + A8: with NO pid, the dir is either an abandoned takeover (one pid.dead.<b>, adopted below) or
    # an orphan creation window (no pid.dead.* at all, reaped after RG_LOCK_ORPHAN_AGE).
    if [ ! -e "$RG_LOCK/pid" ]; then
      rg_pidless_probe
      if [ "$_lnd" = 0 ] && rg_orphan_old && rmdir "$RG_LOCK" 2>/dev/null; then
        _lt=$((_lt + 1))
        continue
      fi
      [ -z "$_lsrc" ] || { _ls="$_lsrc"; _lp="$_lsrcp"; }
    fi
    _lpid=""; _lage=""
    case "$_lp" in
      *' '*) _lpid=${_lp%% *}; _lage=${_lp#* } ;;   # both fields, or it is not a token at all
    esac
    if rg_num10 "$_lpid" && rg_num10 "$_lage" && rg_pid_dead "$_lpid" \
       && [ "$(( $(date -u +%s) - _lage ))" -ge "$RG_LOCK_MIN_AGE" ]; then
      # dead holder, and the lock is old enough that it cannot be a pid we misread across a
      # release/re-take. Break by renaming the TOKEN FILE aside (never `rm` in place — a late breaker
      # would delete a fresh live token, and never touch the DIR: the slot is never free during a break,
      # so no taker can mkdir into it). Exactly one of two simultaneous `mv`s wins; the loser gets ENOENT
      # and re-spins.
      # ⚠️ THE BREAK COSTS A TRY (R1/H2). This `continue` used to skip both the counter and the
      # sleep, so whenever the break itself could not succeed — a dead-pid lock in a state dir
      # that is no longer writable — the loop span at 100% CPU forever instead of failing closed.
      # A bounded spin that can be made unbounded by a filesystem error is not bounded.
      if mv "$_ls" "$RG_LOCK/pid.dead.$$" 2>/dev/null; then
        # ⚠️ RE-READ WHAT WE ACTUALLY MOVED. Between the judgment and the `mv` the lock can have been
        # released and RE-TAKEN; then this `mv` moved a LIVE holder's token. If it is not the token we
        # judged, put it back with `ln` (no `-f`: atomic, and it links only into an empty slot).
        # ⚠️ NEVER REMOVE OR RENAME A LOCK DIR WHOSE TOKEN IS NOT YOURS (security S1). The only dir a
        # process ever removes is the one at the lock path while it HOLDS it, or a dead publisher's dir it
        # has just taken over. The dir at the lock path is never renamed, moved or restored by anyone (bar
        # the holder's own release); only the token file moves, so the slot is never free during a break.
        # `_ls` is the file we moved: `pid`, or (A7) the adopted `pid.dead.<b>`; a put-back returns it THERE.
        _lb=$(head -1 "$RG_LOCK/pid.dead.$$" 2>/dev/null || true)
        if [ -z "$_lb" ]; then
          : # the holder's unlock is tearing the dir down under us: nothing to take over or put back
        elif [ "$_lb" != "$_lp" ]; then
          # ABA: we moved somebody else's token. Atomic put-back; the newer holder's ownership continues.
          # SEC-2: delete the set-aside token ONLY once the put-back landed. On failure it stays in place: a
          # `pid.dead.*` whose content is live reads as LIVE to the probe and the holder's A9 release sweeps it, so
          # the guard fails safe instead of deleting a live holder's token. (`a && b` as a statement is set -e safe.)
          ln "$RG_LOCK/pid.dead.$$" "$_ls" 2>/dev/null && rm -f "$RG_LOCK/pid.dead.$$"
        else
          # the dead token is confirmed: take over IN PLACE. The dir stays (pid-less, holding the renamed-
          # aside dead token) until our own token is published, so no taker can mkdir into the slot.
          _lk_tok="$RG_LOCK.tok.$$"
          rm -f "$_lk_tok"
          # M1: the WRITE gates the publish, as in the take arm. A failed write must never publish (an empty or
          # partial side file would become a garbage token); it falls through to the put-back below.
          if ( set -C; printf '%s %s\n' "$$" "$(date -u +%s)" > "$_lk_tok" ) 2>/dev/null; then
            RG_LOCK_HELD=1   # immediately before the publish: a signal between the two must still clean up
            if ln "$_lk_tok" "$RG_LOCK/pid" 2>/dev/null; then
              rm -f "$RG_LOCK/pid.dead.$$" "$_lk_tok"; _lk_tok=""
              return 0
            fi
          fi
          # a failed publish: put the dead token back so the lock stays breakable (never an orphan)
          RG_LOCK_HELD=0
          # SEC-2: as at the ABA put-back above — the token is deleted only once it was put back; a failed put-back
          # leaves it in place (a live-content `pid.dead.*` reads LIVE, the holder's A9 release sweeps it).
          ln "$RG_LOCK/pid.dead.$$" "$_ls" 2>/dev/null && rm -f "$RG_LOCK/pid.dead.$$"
          rm -f "$_lk_tok"; _lk_tok=""
        fi
      fi
      _lt=$((_lt + 1))
      continue
    fi
    sleep 0.1
    _lt=$((_lt + 1))
  done
  die2 "runaway-guard: UNVERIFIED (2) — could not take the tally lock '$RG_LOCK' within $RG_LOCK_TRIES tries (~$((RG_LOCK_TRIES / 10))s). Refusing to append UNLOCKED (a lost line reads as under-budget). If no session is running, remove that directory."
}

# ── the config ───────────────────────────────────────────────────────────────────────────────────
# cfg_file FILE KEY -> first matching value (KEY=VALUE, ignores # comments); empty if absent. The regex
# is anchored at the line start (after blanks) on KEY, so a `RAISE <ROW> MAX_TOKENS=<n>` line — which
# starts with RAISE — can never match: a raise cannot masquerade as a base value.
cfg_file() {
  [ -f "$1" ] || return 1
  sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*\([^#[:space:]]*\).*/\1/p" "$1" | head -1
}
cfg() { cfg_file "$CONFIG" "$1"; }   # cfg KEY

# rg_read_raises — parse the `RAISE <ROW> [MAX_TOKENS=<n>] [MAX_AGENTS=<n>] [MAX_STEPS=<n>]` lines (strict: a line
# starting with RAISE at column 0, single-space separated, a board-grammar row, at least one key, each
# key at most once, a 1-12 digit value with no leading zero and never 0). Anything else that mentions RAISE is refused rc 2, naming the
# LINE NUMBER (never the bytes). Sets RG_RAISES to normalized `ROW T A S` lines ('-' = key absent). No ERE
# intervals (mawk). Sets a global, never echoes (a die2 inside $(...) would only exit the subshell).
rg_read_raises() {
  RG_RAISES=""
  _rz=$(awk '
    /^[ \t]*RAISE([ \t]|$)/ {
      ok = 1; t = "-"; a = "-"; s = "-"
      if (substr($0, 1, 6) != "RAISE ") ok = 0
      if (ok && (NF < 3 || NF > 5)) ok = 0
      if (ok) { j = $1; for (i = 2; i <= NF; i++) j = j " " $i; if ($0 != j) ok = 0 }
      if (ok && ($2 !~ /^[A-Z0-9][A-Z0-9-]*$/ || length($2) > 64)) ok = 0
      for (i = 3; ok && i <= NF; i++) {
        p = index($i, "="); if (p == 0) { ok = 0; break }
        k = substr($i, 1, p - 1); v = substr($i, p + 1)
        if (v !~ /^[1-9][0-9]*$/ || length(v) > 12) { ok = 0; break }
        if (k == "MAX_TOKENS" && t == "-") t = v
        else if (k == "MAX_AGENTS" && a == "-") a = v
        else if (k == "MAX_STEPS" && s == "-") s = v
        else ok = 0
      }
      if (!ok) { bad = NR; exit 0 }
      out = out $2 " " t " " a " " s "\n"
    }
    # F3: good records are ACCUMULATED and printed only when no line was bad, so a good line ahead of a bad
    # one can never mask the refusal; the sentinel `!BAD` can never start a row id (a row may be named BAD).
    END { if (bad) printf "!BAD %d\n", bad; else printf "%s", out }' "$CONFIG")
  case "$_rz" in
    "!BAD "*) die2 "runaway-guard: REFUSED (2) — budget config '$CONFIG' has a malformed RAISE line at line ${_rz#!BAD } (want \`RAISE <ROW> MAX_TOKENS=<n> MAX_AGENTS=<n> MAX_STEPS=<n>\`, each key optional, at least one). The bytes are NOT echoed." ;;
  esac
  RG_RAISES="$_rz"
}

# rg_effective <ROW> — sets EFF_T EFF_A EFF_S: the base ceilings, overridden for THIS ROW ONLY by its RAISE
# lines (per key, the last line that names the key wins). `($1 "") == (row "")` is a STRING compare, so
# 7 and 007 stay different rows (a strnum would compare numerically).
rg_effective() {
  EFF_T=$MAX_TOKENS; EFF_A=$MAX_AGENTS; EFF_S=$MAX_STEPS
  _ev=$(printf '%s\n' "$RG_RAISES" | awk -v row="$1" '
    ($1 "") == (row "") { if ($2 != "-") t = $2; if ($3 != "-") a = $3; if ($4 != "-") s = $4 }
    END { print (t == "" ? "-" : t), (a == "" ? "-" : a), (s == "" ? "-" : s) }')
  _et=${_ev%% *}; _er=${_ev#* }; _ea=${_er%% *}; _es=${_er#* }
  [ "$_et" = "-" ] || EFF_T=$_et
  [ "$_ea" = "-" ] || EFF_A=$_ea
  [ "$_es" = "-" ] || EFF_S=$_es
}

# rg_unscoped_warn — outside the lock. When the config is not byte-equal to its committed copy AND a base
# MAX_* differs from HEAD's, every step/check WARNs (the raise applies to EVERY row metered from this
# conf). Byte comparison is `cmp -s`, never `git diff`. A conf with no committed copy (not in a work
# tree, `git show` fails, or a sandboxed override) prints one note and never fails.
rg_unscoped_warn() {
  _uw_note="runaway-guard: budget config $CONFIG (no committed copy)"
  if [ -n "$rg_cfg_via" ]; then printf '%s\n' "$_uw_note" >&2; return 0; fi
  _uw_abs=$(rg_canon "$CONFIG") || { printf '%s\n' "$_uw_note" >&2; return 0; }
  _uw_note="runaway-guard: budget config $_uw_abs (no committed copy)"   # M7: the RESOLVED path
  _uw_top=$(git -C "$(dirname -- "$_uw_abs")" rev-parse --show-toplevel 2>/dev/null) || _uw_top=""
  # M4: no work tree (rev-parse failed or printed nothing) -> the note, BEFORE the `case` (an empty
  # $_uw_top would make the pattern "/*" match every absolute path)
  [ -n "$_uw_top" ] || { printf '%s\n' "$_uw_note" >&2; return 0; }
  case "$_uw_abs" in
    "$_uw_top"/*) _uw_rel=${_uw_abs#"$_uw_top"/} ;;
    *) printf '%s\n' "$_uw_note" >&2; return 0 ;;
  esac
  _uw_tmp=$(mktemp "${TMPDIR:-/tmp}/rg-head.XXXXXX") || { printf '%s\n' "$_uw_note" >&2; return 0; }
  if ! git -C "$_uw_top" show "HEAD:$_uw_rel" > "$_uw_tmp" 2>/dev/null; then
    rm -f "$_uw_tmp"; _uw_tmp=""; printf '%s\n' "$_uw_note" >&2; return 0
  fi
  if cmp -s "$_uw_tmp" "$CONFIG"; then rm -f "$_uw_tmp"; _uw_tmp=""; return 0; fi
  for _uw_k in MAX_TOKENS MAX_STEPS MAX_AGENTS; do
    eval "_uw_v=\${$_uw_k}"
    _uw_h=$(cfg_file "$_uw_tmp" "$_uw_k" || true)
    # shellcheck disable=SC2154
    [ "$_uw_v" != "$_uw_h" ] || continue
    printf 'WARN: unscoped raise: %s=%s (HEAD: %s) applies to every row metered from %s (charging %s)\n' \
      "$_uw_k" "$_uw_v" "${_uw_h:-unset}" "$_uw_abs" "${RG_ROW:-every row}" >&2
  done
  rm -f "$_uw_tmp"; _uw_tmp=""
  return 0
}

load_config() {
  [ -f "$CONFIG" ] || die2 "2: config missing: $CONFIG (fail-closed)"
  MAX_TOKENS=$(cfg MAX_TOKENS || true)
  MAX_STEPS=$(cfg MAX_STEPS || true)
  MAX_AGENTS=$(cfg MAX_AGENTS || true)
  WARN_PCT=$(cfg WARN_PCT || true);          WARN_PCT="${WARN_PCT:-80}"
  COST_PER_1K=$(cfg COST_PER_1K_USD || true); COST_PER_1K="${COST_PER_1K:-0}"
  for v in MAX_TOKENS MAX_STEPS MAX_AGENTS WARN_PCT; do
    eval "_val=\${$v:-}"
    # shellcheck disable=SC2154
    case "$_val" in ''|*[!0-9]*) die2 "2: config $v not a non-negative integer: '$_val' (fail-closed)";; esac
  done
  rg_read_raises
}

# ── the tally: a strict, bounded grammar, refused at read ────────────────────────────────────────
# `<epoch> <session-key> <ROW> <tokens> <agents>` (grammar v2, tally.v2): three 1–12-digit integers, a
# [A-Za-z0-9._-]{1,128} key and a [A-Z0-9][A-Z0-9-]* row of at most 64 characters, single-space
# separated. ANYTHING else — the v1 four-field shape, an empty line, a CR, an
# over-long integer — is refused (rc 2) naming the path and the LINE NUMBER, never the bytes (the
# tally is written by whoever can reach the file: control characters and log injection). The file is
# refused past RG_LINE_CAP lines so a multi-gigabyte tally cannot hold the lock through every spin.
# The awk sum CLAMPS at RG_CLAMP and prints with %.0f: an overflow may never read as under-budget.
# No ERE intervals ({1,12}) anywhere — mawk 1.3.3 on some CI images does not support them.
# ⚠️ THIS SETS GLOBALS, IT DOES NOT ECHO. A refusal must abort the PROCESS, and `die2` inside a
# command substitution only ever exits the SUBSHELL — the caller would sail on with an empty verdict.
rg_read_sums() {  # sets RG_T RG_S RG_A; exits 2 on a poisoned or oversized tally
  RG_T=0; RG_S=0; RG_A=0; RG_ROWS=""
  if [ ! -f "$TALLY" ]; then return 0; fi
  # `wc -l` counts NEWLINES, so a final unterminated line is invisible to it — the one line a
  # crashed writer is most likely to leave (R1/L4). awk counts RECORDS, which is what the cap means.
  _sn=$(awk 'END{print NR}' "$TALLY")
  if [ "$_sn" -gt "$RG_LINE_CAP" ]; then
    die2 "runaway-guard: REFUSED (2) — the tally '$TALLY' has $_sn lines, past the $RG_LINE_CAP-line cap. Archive it (it is best-effort runtime state): cd to its directory and run 'mv $(basename "$TALLY") $(basename "$TALLY").<date>', then re-run. ⚠️ That resets every row of this repo to zero."
  fi
  # RG_ROW (validated by the caller: no backslash, no quote) selects the lines to SUM; every line is
  # still GRAMMAR-CHECKED, so a poisoned line in another row refuses too. An EMPTY RG_ROW is the listing
  # mode: one `ROW tokens agents lines` line per row (clamped), into RG_ROWS, sorted.
  _sout=$(awk -v cap="$RG_CLAMP" -v row="${RG_ROW:-}" '
    {
      if (NF != 5 || $0 != $1 " " $2 " " $3 " " $4 " " $5) { bad = NR; exit }
      if ($1 !~ /^[0-9]+$/ || length($1) > 12) { bad = NR; exit }
      if ($2 !~ /^[A-Za-z0-9._-]+$/ || length($2) > 128) { bad = NR; exit }
      if ($3 !~ /^[A-Z0-9][A-Z0-9-]*$/ || length($3) > 64) { bad = NR; exit }
      if ($4 !~ /^[0-9]+$/ || length($4) > 12) { bad = NR; exit }
      if ($5 !~ /^[0-9]+$/ || length($5) > 12) { bad = NR; exit }
      if (row == "") { r = $3 ""; LT[r] += $4; RA[r] += $5; RN[r]++; next }   # listing mode (string key: 7 and 007 differ)
      if (($3 "") != row) next   # string compare: `7` and `007` are different rows (a strnum compares numerically)
      t += $4; a += $5; n++
    }
    END {
      if (bad > 0) { printf "!BAD %d\n", bad; exit 0 }   # `!` can never start a row id (a row may be named BAD)
      if (row == "") {
        for (r in LT) {
          x = LT[r]; y = RA[r]; z = RN[r]
          if (x > cap) x = cap
          if (y > cap) y = cap
          if (z > cap) z = cap
          printf "%s %.0f %.0f %.0f\n", r, x + 0, y + 0, z + 0
        }
        exit 0
      }
      if (t > cap) t = cap
      if (a > cap) a = cap
      if (n > cap) n = cap
      printf "%.0f %.0f %.0f\n", t + 0, n + 0, a + 0
    }' "$TALLY")
  case "$_sout" in
    "!BAD "*)
      die2 "runaway-guard: REFUSED (2) — the tally '$TALLY' is poisoned at line ${_sout#!BAD } (it is not the \`<epoch> <session-key> <ROW> <tokens> <agents>\` grammar). The bytes are NOT echoed. Archive the file (it is best-effort runtime state): cd to its directory and run 'mv $(basename "$TALLY") $(basename "$TALLY").<date>', then re-run. ⚠️ That resets every row of this repo to zero." ;;
  esac
  if [ -z "${RG_ROW:-}" ]; then
    RG_ROWS=$(printf '%s\n' "$_sout" | sort | sed '/^$/d')   # `sort` under LC_ALL=C: byte order, one order everywhere
    return 0
  fi
  RG_T=${_sout%% *}; _srest=${_sout#* }; RG_S=${_srest%% *}; RG_A=${_srest##* }
  return 0
}

record() { printf '%s %s %s %s %s\n' "$(date -u +%s)" "$1" "$2" "$3" "$4" >> "$TALLY"; }   # <key> <ROW> <tokens> <agents>

# rg_grade <tokens> <steps> <agents> — grade ONE row's sums against its EFFECTIVE ceilings (EFF_T/EFF_S/
# EFF_A, set by rg_effective). Sets breach / warn to ` dim(cur/max)` lists.
rg_grade() {
  breach=""; warn=""
  for d in "tokens $1 $EFF_T" "steps $2 $EFF_S" "agents $3 $EFF_A"; do
    # shellcheck disable=SC2086
    set -- $d; nm=$1; cur=$2; max=$3
    [ "$max" -gt 0 ] || continue                 # max=0 disables the dimension
    if [ "$cur" -ge "$max" ]; then breach="$breach $nm($cur/$max)"
    elif [ $(( cur * 100 )) -ge $(( max * WARN_PCT )) ]; then warn="$warn $nm($cur/$max)"; fi
  done
}

# check_verdict — RG_ROW's verdict (step: after the append; check --row: read only). RG_METER=1 prints the
# `metered:` line FIRST, so it is visible on WARN and STOP too.
check_verdict() {
  rg_read_sums; cur_t=$RG_T; cur_s=$RG_S; cur_a=$RG_A
  rg_effective "$RG_ROW"
  rg_grade "$cur_t" "$cur_s" "$cur_a"
  # F6: steps appear only when the effective MAX_STEPS is > 0; disabled (0) keeps the line byte-identical.
  _msteps=""; [ "$EFF_S" -gt 0 ] && _msteps=" steps($cur_s/$EFF_S)"
  [ "$RG_METER" != 1 ] || printf 'metered: %s tokens(%s/%s) agents(%s/%s)%s\n' "$RG_ROW" "$cur_t" "$EFF_T" "$cur_a" "$EFF_A" "$_msteps" >&2
  if [ -n "$breach" ]; then
    printf 'STOP: %s runaway:%s [~$%s]\n' "$RG_ROW" "$breach" \
      "$(awk -v t="$cur_t" -v r="$COST_PER_1K" 'BEGIN{printf "%.4f", (t/1000)*r}')" >&2
    exit 1
  fi
  [ "$WARN_PCT" -gt 0 ] && [ -n "$warn" ] && printf 'WARN: %s approaching ceiling (>=%s%%):%s\n' "$RG_ROW" "$WARN_PCT" "$warn" >&2
  exit 0
}

# rg_list_rows — `check` with no --row: every row of this repo's tally, sorted, each graded against ITS
# effective ceiling. Sets RG_LIST_RC (1 if any row is at/past its ceiling). Read under the lock by the
# caller; the network read happens AFTER the lock is released.
rg_list_rows() {
  rg_read_sums; RG_LIST_RC=0
  [ -n "$RG_ROWS" ] || return 0
  # a here-doc, not a pipe: the loop must run in THIS shell so RG_LIST_RC survives it (dash/bash 3.2)
  while read -r _lr _lt _la _ln; do
    rg_effective "$_lr"; rg_grade "$_lt" "$_ln" "$_la"
    _lf=""
    if [ -n "$breach" ]; then _lf=" STOP"; RG_LIST_RC=1
    elif [ "$WARN_PCT" -gt 0 ] && [ -n "$warn" ]; then _lf=" WARN"; fi
    printf '%s tokens=%s agents=%s%s\n' "$_lr" "$_lt" "$_la" "$_lf"
  done <<EOF
$RG_ROWS
EOF
  return 0
}

# rg_claims_check — outside the lock. ONE `git ls-remote` over both claim namespaces; a listed row with
# NEITHER exact ref name (refs/claims/<ROW>, refs/claims-log/<ROW>; whole names, never a substring) is
# flagged. Any failure prints `claims UNVERIFIED` and changes nothing else (the grading rc stands).
#
# THE READ IS BOUNDED (I1). It is non-interactive (no terminal or credential prompt, ssh BatchMode, a
# connect timeout, a low-speed abort — `credential.helper` is deliberately NOT cleared: a private repo needs it
# to verify a claim) AND wall-clock bounded: `git` runs in the background writing to a temp file while a
# sleeper kills it after RG_CLAIMS_TIMEOUT seconds (digits only, else 20). A timeout or any non-zero rc is
# `claims UNVERIFIED`; the grading rc never changes. An EMPTY tally makes no network read at all (M5).
rg_claims_check() {
  [ -n "$RG_ROWS" ] || return 0
  _cr=${BOARD_CLAIM_REMOTE:-origin}
  _cu=$(printf 'claims UNVERIFIED (%s unreachable or timed out)' "$_cr")
  case "$_cr" in
    -*) printf '%s\n' "$_cu"; return 0 ;;   # never an option to git
  esac
  _ct=${RG_CLAIMS_TIMEOUT:-20}
  case "$_ct" in ''|*[!0-9]*) _ct=20 ;; esac
  [ "$_ct" -gt 0 ] || _ct=20
  _cf=$(mktemp "${TMPDIR:-/tmp}/rg-claims.XXXXXX") || { printf '%s\n' "$_cu"; return 0; }
  # `exec` makes $! the git process itself, so the sleeper's kill reaches git and not just a wrapper subshell
  ( exec env GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never \
      GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes -o ConnectTimeout=10" \
      git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=15 -C "$PWD" ls-remote -- "$_cr" 'refs/claims/*' 'refs/claims-log/*' ) \
    > "$_cf" 2>/dev/null < /dev/null &
  _cp=$!
  # N1: the sleeper OWNS its `sleep`: the TERM trap kills it, so `kill $_cs` (a normal finish, or rg_cleanup)
  # never orphans a `sleep $RG_CLAIMS_TIMEOUT`. The trap is armed BEFORE the sleep starts (a fast-failing
  # remote returns in milliseconds, and a TERM that beat the trap would leave the sleep behind).
  ( _z=""; trap '[ -z "$_z" ] || kill "$_z" 2>/dev/null; exit 0' TERM
    sleep "$_ct" & _z=$!
    wait "$_z"; kill "$_cp" 2>/dev/null ) > /dev/null 2>&1 &
  _cs=$!
  if wait "$_cp" 2>/dev/null; then _cok=1; else _cok=0; fi
  kill "$_cs" 2>/dev/null || :
  _cp=""; _cs=""   # done: never let rg_cleanup signal a pid that has since been recycled
  _cout=$(cat "$_cf"); rm -f "$_cf"; _cf=""
  if [ "$_cok" != 1 ]; then printf '%s\n' "$_cu"; return 0; fi
  while read -r _cw _x _x _x; do
    if printf '%s\n' "$_cout" | awk -v a="refs/claims/$_cw" -v b="refs/claims-log/$_cw" '$2 == a || $2 == b { f = 1 } END { exit !f }'; then :
    else printf 'never claimed: %s\n' "$_cw"; fi
  done <<EOF
$RG_ROWS
EOF
  return 0
}

# ── argument parsing ─────────────────────────────────────────────────────────────────────────────
cmd="${1:-}"; [ $# -gt 0 ] && shift || :
tokens=0; agents=0; count=""; RG_ROW=""; RG_KEY=""; RG_METER=0; RG_ROWS=""; RG_RAISES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --row)    [ $# -ge 2 ] || die2 "2: --row requires a value";    RG_ROW="$2"; shift 2 ;;
    --tokens) [ $# -ge 2 ] || die2 "2: --tokens requires a value"; tokens="$2"; shift 2 ;;
    --agents) [ $# -ge 2 ] || die2 "2: --agents requires a value"; agents="$2"; shift 2 ;;
    --count)  [ $# -ge 2 ] || die2 "2: --count requires a value";  count="$2";  shift 2 ;;
    --config) [ $# -ge 2 ] || die2 "2: --config requires a value"; CONFIG="$2"; rg_cfg_via="--config"; shift 2 ;;
    --tally)  [ $# -ge 2 ] || die2 "2: --tally requires a value";  TALLY="$2";  rg_tally_via="--tally"; shift 2 ;;
    *) die2 "2: unknown arg: $1" ;;
  esac
done

# THE BANNER REACHES AN OPERATOR (release-tag.sh's F2 precedent): every invocation under the dial
# says so on stderr, whether or not it ends up using an override.
if [ -n "${KIT_RUNAWAY_SANDBOX:-}" ]; then
  printf 'runaway-guard: SANDBOX override active (%s)\n' "$KIT_RUNAWAY_SANDBOX" >&2
fi
[ -n "$rg_cfg_via" ]   && rg_vet_override "the ceiling config" "$rg_cfg_via" "$CONFIG" || :
[ -n "$rg_tally_via" ] && rg_vet_override "the tally" "$rg_tally_via" "$TALLY" || :

case "$cmd" in
  step|check|meter)
    # --row is REQUIRED for `step` and `meter` (no env fallback) and optional for `check` (absent = the
    # listing); when given it is grammar-checked here, before it can become a field or an awk -v value.
    if [ -n "$RG_ROW" ] || [ "$cmd" = step ] || [ "$cmd" = meter ]; then
      rg_row_ok "$RG_ROW" || die2 "2: which slice is this? pass --row <ROW-ID> ([A-Z0-9][A-Z0-9-]*, at most 64 characters)"
    fi
    if [ -z "$TALLY" ]; then
      rg_repo_key
      RG_STATE=$(rg_state_dir); TALLY="$RG_STATE/tally.v2"
      rg_safe_file "$TALLY"
    else
      RG_STATE=$(dirname -- "$TALLY")
    fi ;;
esac

case "$cmd" in
  step)
    # belt only — no non-ASCII digit was found to pass `[!0-9]` on bash 3.2/dash
    case "$tokens" in ''|*[!0123456789]*) die2 "2: --tokens/--agents must be non-negative integers";; esac
    case "$agents" in ''|*[!0123456789]*) die2 "2: --tokens/--agents must be non-negative integers";; esac
    # ⚠️ THE WRITE PATH IS BOUND BY THE SAME GRAMMAR THE READ PATH ENFORCES (R1/H3, security HIGH).
    # Without this, `step --tokens 9999999999999` — an ALLOWED agent Bash call needing no dial —
    # appended a 13-digit field that rg_read_sums then refuses FOREVER: one call permanently poisons
    # the machine-wide tally and STOPs every session on it until a human deletes the file. A writer
    # that can write what the reader must refuse is not a grammar, it is a denial-of-service.
    [ "${#tokens}" -le 12 ] || die2 "2: --tokens must be at most 12 digits (the tally grammar refuses more, so writing it would poison the tally)"
    [ "${#agents}" -le 12 ] || die2 "2: --agents must be at most 12 digits (the tally grammar refuses more, so writing it would poison the tally)"
    # R1/L6 (reviewer NOTE-10): `key=$(rg_session_key)` and `RG_STATE=$(rg_state_dir)` above are safe
    # ONLY because die2's exit status propagates out of the command substitution to the ASSIGNMENT,
    # which `set -e` then aborts on. Turn either into a pipeline (`$(rg_session_key | tr …)`) and the
    # status becomes the LAST element's — the refusal would be swallowed and the caller would carry on.
    key=$(rg_session_key)
    load_config
    rg_unscoped_warn                # outside the lock: it reads git, not the tally
    rg_lock "$RG_STATE/lock"
    rg_read_sums                    # validate the file BEFORE appending to it
    record "$key" "$RG_ROW" "$tokens" "$agents"
    RG_METER=1
    check_verdict ;;                # reads under the lock; the EXIT trap releases it
  check)
    load_config
    rg_unscoped_warn                # outside the lock
    rg_lock "$RG_STATE/lock"
    [ -n "$RG_ROW" ] && check_verdict || :   # check --row R: R's verdict + rc, exits; nothing is written
    rg_list_rows
    rg_unlock                       # the network read below is OUTSIDE the lock
    rg_claims_check
    exit "$RG_LIST_RC" ;;
  meter)
    # RUNAWAY-METERING-LANDING-GATE T1: was this row EVER metered, and what has it spent? READ-ONLY: the
    # existing reader under the existing lock, no append. rc 0 metered and under its ceiling | 1 metered AND
    # at/past it (rg_grade, exactly as `check --row`) | 3 no line for the row or no tally | 2 every refusal
    # `check` has, plus a tally that exists but cannot be read (else awk dies under `set -e` with an
    # awk-dependent rc). The line goes to STDOUT (the landing gate reads it); refusals stay on stderr.
    load_config
    rg_unscoped_warn                # outside the lock
    rg_lock "$RG_STATE/lock"
    [ ! -e "$TALLY" ] || [ -f "$TALLY" ] || die2 "runaway-guard: REFUSED (2) — the tally '$TALLY' is not a regular file."
    [ ! -f "$TALLY" ] || [ -r "$TALLY" ] || die2 "runaway-guard: REFUSED (2) — the tally '$TALLY' exists but is not readable by this user."
    rg_read_sums
    rg_effective "$RG_ROW"
    rg_grade "$RG_T" "$RG_S" "$RG_A"
    if [ "$RG_S" -eq 0 ]; then
      printf 'unmetered: %s tokens(0/%s) agents(0/%s) lines=0\n' "$RG_ROW" "$EFF_T" "$EFF_A"
      exit 3
    fi
    printf 'metered: %s tokens(%s/%s) agents(%s/%s) lines=%s\n' "$RG_ROW" "$RG_T" "$EFF_T" "$RG_A" "$EFF_A" "$RG_S"
    [ -z "$breach" ] || exit 1
    exit 0 ;;
  reset)
    # RETIRED: the budget is per slice. It writes nothing and takes no lock, so it stays above the state dir.
    die2 "runaway-guard: reset is retired — the budget is per slice (row); a new row starts at zero and there is nothing to reset. See docs/operations/runaway-killswitch.md." ;;
  wip)
    # WIP is BOARD state, not run usage, so it is its own verb and touches neither tally nor lock.
    # An adopter with no budget.conf (or no MAX_WIP, or MAX_WIP=0) keeps `claim` working: N/A, rc 0.
    case "$count" in ''|*[!0-9]*) die2 "2: wip requires --count <non-negative integer>";; esac
    if [ ! -f "$CONFIG" ]; then echo "wip: N/A (MAX_WIP undeclared)"; exit 0; fi
    _mw=$(cfg MAX_WIP || true)
    case "$_mw" in
      ''|0) echo "wip: N/A (MAX_WIP undeclared)"; exit 0 ;;
      *[!0-9]*) die2 "2: config MAX_WIP not a non-negative integer: '$_mw' (fail-closed)" ;;
    esac
    if [ "$count" -ge "$_mw" ]; then
      printf 'STOP: wip(%s/%s) — this machine already carries %s claimed slice(s); MAX_WIP is %s.\n' \
        "$count" "$_mw" "$count" "$_mw" >&2
      exit 1
    fi
    echo "wip: OK ($count/$_mw)"
    exit 0 ;;
  *) die2 "2: usage: runaway-guard.sh step --row ROW [--tokens N] [--agents N] | check [--row ROW] | meter --row ROW | wip --count N" ;;
esac
