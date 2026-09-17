#!/bin/sh
# runaway-guard.sh — E4d executable runaway circuit-breaker (harness-neutral).
#
# The kit cannot MEASURE tokens (the harness/LLM-API does); it ENFORCES a ceiling on REPORTED
# usage at the orchestration seam and halts the loop. The platform LLM-API cap is the hard ceiling
# ABOVE this. The ceiling config (.kit/budget.conf) + this script are control-plane (agent-immutable);
# the tally is best-effort runtime state (platform cap is the backstop if defeated).
#
# ONE CEILING PER MACHINE (B4-CROSS-SESSION-BUDGET; docs/architecture/2026-09-15-b4-cross-session-
# budget-design.md). The tally used to be `.kit-run/tally`, RELATIVE TO $PWD and gitignored — so N
# parallel sessions in N worktrees each got their own silent ceiling, which is N times the ceiling
# the owner declared. The tally now lives at $HOME/.local/state/sparkwright/runaway/tally, anchored
# on $HOME only (no XDG_STATE_HOME: git ignores that variable, so honouring it would be a third,
# unbannered redirection route that costs an agent nothing). Every line carries the SESSION KEY of
# the worktree that wrote it, so `check` sums ALL sessions (the combined ceiling) while `reset`
# clears only the caller's own lines.
#
# Usage:
#   runaway-guard.sh step  --tokens N --agents N   # record this step's usage, then check
#   runaway-guard.sh check                         # verdict only
#   runaway-guard.sh reset                         # start a fresh run (clear THIS session's lines)
#   runaway-guard.sh wip   --count N               # is another slice already in flight? (MAX_WIP)
# Exit: 0 continue (WARN on stderr at >=WARN_PCT) | 1 STOP (ceiling breached) | 2 UNVERIFIED (bad
#       config / poisoned tally / hostile state dir / lock timeout / a refused override).
# What it changes: Appends to / rewrites the PER-MACHINE runaway tally at $HOME/.local/state/sparkwright/runaway/tally (serialized by a mkdir lock beside it); reads the ceiling config (default .kit/budget.conf, resolved from this script's own root, never $PWD). `wip` reads only the config.
# Guardrails: Fail-closed (exit 2) on a missing/bad config, a tally line that is not the four-field grammar, a tally past the line cap, a symlinked or foreign-owned state dir, a non-absolute $HOME, or a lock it cannot take within its bounded 30s spin (a dead holder's lock is broken only when its `<pid> <epoch>` token is also older than 2s, so a stale read cannot rename a live holder's lock away); the summed usage CLAMPS toward the ceiling so an overflow can never read as under-budget; both redirection routes (--tally/RUNAWAY_TALLY, --config/RUNAWAY_BUDGET_CONFIG) are REFUSED unless the human dial KIT_RUNAWAY_SANDBOX names a directory the path canonicalizes under, and every sandboxed invocation BANNERS on stderr; exit 1 (STOP) when a ceiling is breached; the config is control-plane (agent-immutable), the platform LLM-API cap is the hard backstop above it.
set -eu
umask 077

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
  printf '%s\n' "$_sd"
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
# the combined ceiling until a human deletes the file. That fails toward STOP, which is the right
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
# old is broken, and the break is a RENAME so exactly one of two simultaneous breakers wins it.
#
# ⚠️ THE EPOCH IS THE ABA DEFENCE, AND THE ABA IS REAL (found by inspection at review): a contender
# reads holder A's pid; A finishes and releases; B mkdir's the lock and writes ITS pid; the
# contender's `kill -0 A` now says "dead" and it renames B's LIVE lock away — two holders, both
# appending. A recycled lock always carries a FRESH epoch, so an age gate makes a stale read
# unable to break a fresh holder. The post-rename re-read closes the residual window: if what we
# renamed is not the exact token we judged, we renamed somebody else's lock and we put it back.
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
rg_unlock() { if [ "$RG_LOCK_HELD" = 1 ]; then rm -rf "$RG_LOCK"; RG_LOCK_HELD=0; fi; return 0; }
# ⚠️ THE SIGNAL TRAPS EXIT; THE EXIT TRAP ONLY CLEANS UP (R1/H1). A single
# `trap 'rg_unlock' EXIT INT TERM` releases the lock on SIGINT/SIGTERM and then RESUMES the
# interrupted flow — so a step killed mid-spin carried on to record() and check_verdict() with
# RG_LOCK_HELD=0, i.e. an UNLOCKED APPEND reported as rc 0. Interrupted means UNVERIFIED, always.
trap 'rg_unlock' EXIT
trap 'rg_unlock; exit 2' INT TERM

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
      printf '%s %s\n' "$$" "$(date -u +%s)" > "$RG_LOCK/pid"
      return 0
    fi
    _lp=""
    [ -f "$RG_LOCK/pid" ] && _lp=$(head -1 "$RG_LOCK/pid" 2>/dev/null || true) || :
    _lpid=""; _lage=""
    case "$_lp" in
      *' '*) _lpid=${_lp%% *}; _lage=${_lp#* } ;;   # both fields, or it is not a token at all
    esac
    if rg_num10 "$_lpid" && rg_num10 "$_lage" && rg_pid_dead "$_lpid" \
       && [ "$(( $(date -u +%s) - _lage ))" -ge "$RG_LOCK_MIN_AGE" ]; then
      # dead holder, and the lock is old enough that it cannot be a pid we misread across a
      # release/re-take. Break by RENAME (never `rm` in place — a late breaker would delete a fresh
      # live lock). The loser of the rename re-spins on ENOENT and takes the lock normally.
      # ⚠️ THE BREAK COSTS A TRY (R1/H2). This `continue` used to skip both the counter and the
      # sleep, so whenever the break itself could not succeed — a dead-pid lock in a state dir
      # that is no longer writable — the loop span at 100% CPU forever instead of failing closed.
      # A bounded spin that can be made unbounded by a filesystem error is not bounded.
      if mv "$RG_LOCK" "$RG_LOCK.stale.$$" 2>/dev/null; then
        # ⚠️ RE-READ WHAT WE ACTUALLY RENAMED. Between the judgment and the rename the lock can have
        # been released and RE-TAKEN; then this rename took a LIVE holder's lock. If the token is not
        # the one we judged, put it back (only when the slot is free — a slot that already refilled
        # belongs to a newer holder and must not be overwritten) and keep spinning.
        # ⚠️ NEVER `rm -rf` OR `mv`-BACK A DIRECTORY YOU DID NOT JUST CREATE (security S1). The first
        # version of this arm restored with `[ ! -e "$RG_LOCK" ] && mv …` and otherwise `rm -rf`'d —
        # and BOTH halves are wrong under a race: the `-e` test is itself TOCTOU, `mv dir existing-dir`
        # moves INTO it on macOS and errors on Linux (leaving residue), and the `rm -rf` arm deletes
        # what by then may be ANOTHER holder's LIVE lock. The atomic `mkdir` is the only honest claim:
        # if it succeeds the slot was free and we restore the renamed-away holder's token IN PLACE
        # (its ownership simply continues — no duplicate is created); if it fails another contender
        # already owns the slot, and we leave `lock.stale.$$` alone rather than touch a dir we do not
        # own. That leftover is harmless: it is not at the lock path, so nobody consults it.
        _lb=$(head -1 "$RG_LOCK.stale.$$/pid" 2>/dev/null || true)
        if [ "$_lb" != "$_lp" ]; then
          if mkdir "$RG_LOCK" 2>/dev/null; then
            mv "$RG_LOCK.stale.$$/pid" "$RG_LOCK/pid" 2>/dev/null || :
            rmdir "$RG_LOCK.stale.$$" 2>/dev/null || :
          fi
        else
          # the MATCH arm: this dir is ours by the rename we just won, so removing it is ours to do.
          rm -rf "$RG_LOCK.stale.$$"
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
cfg() {  # cfg KEY -> first matching value (KEY=VALUE, ignores # comments); empty if absent
  [ -f "$CONFIG" ] || return 1
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\([^#[:space:]]*\).*/\1/p" "$CONFIG" | head -1
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
}

# ── the tally: a strict, bounded grammar, refused at read ────────────────────────────────────────
# `<epoch> <session-key> <tokens> <agents>`: three 1–12-digit integers and a [A-Za-z0-9._-]{1,128}
# key, single-space separated. ANYTHING else — the old two-field shape, an empty line, a CR, an
# over-long integer — is refused (rc 2) naming the path and the LINE NUMBER, never the bytes (the
# tally is written by whoever can reach the file: control characters and log injection). The file is
# refused past RG_LINE_CAP lines so a multi-gigabyte tally cannot hold the lock through every spin.
# The awk sum CLAMPS at RG_CLAMP and prints with %.0f: an overflow may never read as under-budget.
# No ERE intervals ({1,12}) anywhere — mawk 1.3.3 on some CI images does not support them.
# ⚠️ THIS SETS GLOBALS, IT DOES NOT ECHO. A refusal must abort the PROCESS, and `die2` inside a
# command substitution only ever exits the SUBSHELL — the caller would sail on with an empty verdict.
rg_read_sums() {  # sets RG_T RG_S RG_A; exits 2 on a poisoned or oversized tally
  RG_T=0; RG_S=0; RG_A=0
  if [ ! -f "$TALLY" ]; then return 0; fi
  # `wc -l` counts NEWLINES, so a final unterminated line is invisible to it — the one line a
  # crashed writer is most likely to leave (R1/L4). awk counts RECORDS, which is what the cap means.
  _sn=$(awk 'END{print NR}' "$TALLY")
  if [ "$_sn" -gt "$RG_LINE_CAP" ]; then
    die2 "runaway-guard: REFUSED (2) — the tally '$TALLY' has $_sn lines, past the $RG_LINE_CAP-line cap. Remove the file (it is best-effort runtime state) and re-run."
  fi
  _sout=$(awk -v cap="$RG_CLAMP" '
    {
      if (NF != 4 || $0 != $1 " " $2 " " $3 " " $4) { bad = NR; exit }
      if ($1 !~ /^[0-9]+$/ || length($1) > 12) { bad = NR; exit }
      if ($2 !~ /^[A-Za-z0-9._-]+$/ || length($2) > 128) { bad = NR; exit }
      if ($3 !~ /^[0-9]+$/ || length($3) > 12) { bad = NR; exit }
      if ($4 !~ /^[0-9]+$/ || length($4) > 12) { bad = NR; exit }
      t += $3; a += $4; n++
    }
    END {
      if (bad > 0) { printf "BAD %d\n", bad; exit 0 }
      if (t > cap) t = cap
      if (a > cap) a = cap
      if (n > cap) n = cap
      printf "%.0f %.0f %.0f\n", t + 0, n + 0, a + 0
    }' "$TALLY")
  case "$_sout" in
    "BAD "*)
      die2 "runaway-guard: REFUSED (2) — the tally '$TALLY' is poisoned at line ${_sout#BAD } (it is not the \`<epoch> <session-key> <tokens> <agents>\` grammar). The bytes are NOT echoed. Remove the file (it is best-effort runtime state) and re-run." ;;
  esac
  RG_T=${_sout%% *}; _srest=${_sout#* }; RG_S=${_srest%% *}; RG_A=${_srest##* }
  return 0
}

record() { printf '%s %s %s %s\n' "$(date -u +%s)" "$1" "$2" "$3" >> "$TALLY"; }

check_verdict() {
  rg_read_sums; cur_t=$RG_T; cur_s=$RG_S; cur_a=$RG_A
  breach=""; warn=""
  for d in "tokens $cur_t $MAX_TOKENS" "steps $cur_s $MAX_STEPS" "agents $cur_a $MAX_AGENTS"; do
    # shellcheck disable=SC2086
    set -- $d; nm=$1; cur=$2; max=$3
    [ "$max" -gt 0 ] || continue                 # max=0 disables the dimension
    if [ "$cur" -ge "$max" ]; then breach="$breach $nm($cur/$max)"
    elif [ $(( cur * 100 )) -ge $(( max * WARN_PCT )) ]; then warn="$warn $nm($cur/$max)"; fi
  done
  if [ -n "$breach" ]; then
    printf 'STOP: runaway ceiling breached:%s [~$%s]\n' "$breach" \
      "$(awk -v t="$cur_t" -v r="$COST_PER_1K" 'BEGIN{printf "%.4f", (t/1000)*r}')" >&2
    exit 1
  fi
  [ "$WARN_PCT" -gt 0 ] && [ -n "$warn" ] && printf 'WARN: approaching ceiling (>=%s%%):%s\n' "$WARN_PCT" "$warn" >&2
  exit 0
}

# ── argument parsing ─────────────────────────────────────────────────────────────────────────────
cmd="${1:-}"; [ $# -gt 0 ] && shift || :
tokens=0; agents=0; count=""
while [ $# -gt 0 ]; do
  case "$1" in
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
  step|check|reset)
    if [ -z "$TALLY" ]; then
      RG_STATE=$(rg_state_dir); TALLY="$RG_STATE/tally"
      rg_safe_file "$TALLY"
    else
      RG_STATE=$(dirname -- "$TALLY")
    fi ;;
esac

case "$cmd" in
  step)
    case "$tokens" in ''|*[!0-9]*) die2 "2: --tokens/--agents must be non-negative integers";; esac
    case "$agents" in ''|*[!0-9]*) die2 "2: --tokens/--agents must be non-negative integers";; esac
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
    rg_lock "$RG_STATE/lock"
    rg_read_sums                    # validate the file BEFORE appending to it
    record "$key" "$tokens" "$agents"
    check_verdict ;;                # reads under the lock; the EXIT trap releases it
  check)
    load_config
    rg_lock "$RG_STATE/lock"
    check_verdict ;;
  reset)
    key=$(rg_session_key)
    rg_lock "$RG_STATE/lock"
    if [ -f "$TALLY" ]; then
      rg_read_sums                  # a poisoned tally is refused here too: fail-closed, not silently rewritten
      _rtmp="$TALLY.reset.$$"
      awk -v k="$key" '$2 != k' "$TALLY" > "$_rtmp"
      mv "$_rtmp" "$TALLY"
    fi
    exit 0 ;;
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
  *) die2 "2: usage: runaway-guard.sh step|check|reset [--tokens N] [--agents N] | wip --count N" ;;
esac
