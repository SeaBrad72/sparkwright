#!/bin/sh
# runaway-killswitch-wired.sh — E4d: the runaway circuit-breaker is installed + has teeth.
#
# Proves: scripts/runaway-guard.sh exists, is executable, and ENFORCES each ceiling
# (tokens / steps / agents), warns before breach, and fails closed on a bad config.
# A green run does NOT prove a hard LLM-API spend cap (platform-owned) or a tamper-proof
# tally (best-effort) — see docs/operations/runaway-killswitch.md. Necessary, not sufficient.
#
# Usage: sh conformance/runaway-killswitch-wired.sh [--require] | --selftest
set -eu
GUARD="scripts/runaway-guard.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

selftest() {
  [ -f "$GUARD" ] || fail "missing $GUARD"
  [ -x "$GUARD" ] || fail "$GUARD not executable"
  # T2: the invoking user's REAL state is recorded BEFORE any leg overrides HOME, and asserted identical
  # at the very end (rcps_home_end): no leg of this selftest may touch the developer's live tally.
  rcps_home_begin
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  # SENTINEL HOME: from here on the ambient $HOME is a directory nothing may touch. A leg that forgets to
  # pin its own HOME lands its state under it, from ANY cwd; the strict check at the end (rcps_sentinel_end)
  # asserts it is still absent. It also means no leg can lean on the invoking user's global git config.
  mkdir -p "$tmp/sentinel-home"; HOME="$tmp/sentinel-home"; export HOME
  cfg="$tmp/c"; tally="$tmp/t"
  # B4: `--config` / `--tally` are REFUSED without the human sandbox dial (a second tally is a second
  # ceiling), so this fixture declares its own throwaway sandbox. Everything the legs redirect lives
  # under it; the legs that exercise the DEFAULT per-repo path (<key>/tally.v2) unset the dial and fake $HOME.
  KIT_RUNAWAY_SANDBOX="$tmp"; export KIT_RUNAWAY_SANDBOX
  # T1b: a bare `check` makes one `git ls-remote` on the claim remote. HERMETIC: point it at a path that
  # does not exist, so no leg ever reaches the network (or a credential helper) of the repo it runs in.
  BOARD_CLAIM_REMOTE="$tmp/no-such-remote"; export BOARD_CLAIM_REMOTE
  mkcfg() { printf 'MAX_TOKENS=%s\nMAX_STEPS=%s\nMAX_AGENTS=%s\nWARN_PCT=%s\nCOST_PER_1K_USD=0.003\n' "$1" "$2" "$3" "$4" >"$cfg"; }
  R() { _c=$1; shift; [ "$_c" != step ] || set -- --row ROW-T "$@"; sh "$GUARD" "$_c" --config "$cfg" --tally "$tally" "$@"; }   # subcommand-first; defaults before caller args so caller --config wins (last-wins; script reads subcommand as $1 BEFORE the option loop)
  expect() { _w=$1; shift; "$@" >/dev/null 2>&1 && _g=0 || _g=$?; [ "$_g" = "$_w" ] || fail "$_desc (want $_w, got $_g)"; }

  _desc="under-budget continues"; mkcfg 1000 10 5 80; : >"$tally"; expect 0 R step --tokens 100 --agents 1
  _desc="token breach stops";     mkcfg 1000 10 5 80; : >"$tally"; expect 1 R step --tokens 1000 --agents 0
  _desc="step breach stops";      mkcfg 999999 2 99 80; : >"$tally"; R step --tokens 1 --agents 0 >/dev/null 2>&1; expect 1 R step --tokens 1 --agents 0
  _desc="agent breach stops";     mkcfg 999999 99 2 80; : >"$tally"; expect 1 R step --tokens 1 --agents 2
  _desc="warn continues";         mkcfg 1000 10 5 80; : >"$tally"; expect 0 R step --tokens 800 --agents 1
  _desc="breach names the dim";   mkcfg 1000 10 5 80; : >"$tally"; case "$(R step --tokens 1000 --agents 0 2>&1 >/dev/null)" in *tokens*) : ;; *) fail "breach must name the dimension";; esac
  _desc="missing config -> 2";    expect 2 R check --config "$tmp/nope"
  _desc="malformed config -> 2";  printf 'MAX_TOKENS=x\n' >"$cfg"; expect 2 R check
  _desc="missing flag value -> 2"; mkcfg 1000 10 5 80; : >"$tally"; expect 2 R step --tokens
  _desc="empty flag value -> 2";   mkcfg 1000 10 5 80; : >"$tally"; expect 2 R step --tokens "" --agents 1
  # fail-closed: prove fail() actually ABORTS on a false expectation — proves fail()'s `exit 1` is load-bearing.
  # Run a deliberately-false expectation in a SUBSHELL and observe its exit code. The abort here is a direct
  # `exit 1` (oracle region — non-vacuity never neuters it), NOT fail() (routing it through fail() is circular:
  # the mutation neuters fail(), so the detector would be neutered too and the mutant would survive).
  # NOTE: capture the subshell's exit status via the `&&`/`||` idiom (as `expect` itself does above), NOT a
  # bare `cmd; rc=$?` — under `set -eu` a plain failing command aborts the WHOLE script before `rc=$?` is ever
  # reached (verified: dash/bash/sh all exit immediately at the failing simple command), which would silently
  # break --selftest on every ordinary (unmutated) run, not just the mutant.
  ( _desc="fail-closed meta"; expect 0 false ) >/dev/null 2>&1 && _mrc=0 || _mrc=$?
  [ "$_mrc" != 0 ] || { echo "FAIL: fail() did not abort on a false expectation (fail-closed broken)" >&2; exit 1; }

  # ── B4-CROSS-SESSION-BUDGET legs ───────────────────────────────────────────────────────────────
  # The tally lives under $HOME/.local/state/sparkwright/runaway/<root-commit>/tally.v2 (ONE per repo,
  # shared by every worktree of it), its line grammar is `<epoch> <session-key> <ROW> <tokens> <agents>`,
  # each ROW is graded alone, the read path refuses anything else, the appends are serialized by a
  # mkdir lock, and both override routes are refused without the KIT_RUNAWAY_SANDBOX dial.
  # Design: docs/architecture/2026-09-15-b4-cross-session-budget-design.md (the per-machine origin) and
  # docs/architecture/2026-09-28-runaway-ceiling-per-slice-confirming-design.md (per repo, per row).
  b4_legs
  rcps_legs
  rcps_t2_legs
  rmlg_meter_legs
  rcps_awk_names_leg
  rcps_home_end
  rcps_sentinel_end
  echo "runaway-killswitch-wired: selftest OK"
}

# ── ORACLE MARKER: b4_legs() and everything below is the non-vacuity oracle region ───────────────
# (same discipline as scripts/board-claim.sh's marker: the mutation sweep mutates the lines ABOVE
# the `selftest()` marker, so the assertions themselves cannot be neutered by a mutant.)

# b4_legs — the B4-CROSS-SESSION-BUDGET legs (moved onto the v2 per-repo, per-row tally by T1a/T1b/T2).
# Every fixture lives under the selftest's own $tmp and every invocation that reaches the STATE DIR does
# so with a $HOME inside $tmp: NOTHING here may touch the real $HOME/.local/state/sparkwright, which is
# the invoking user's live per-repo tally (asserted by rcps_home_begin/rcps_home_end).
b4_legs() {
  b4_guard=$(pwd -P)/$GUARD
  b4_sand="$tmp/sand"; mkdir -p "$b4_sand" "$tmp/hsafe"
  b4_cfg="$b4_sand/c"; b4_tally="$b4_sand/t"
  KIT_RUNAWAY_SANDBOX="$b4_sand"; export KIT_RUNAWAY_SANDBOX
  b4_mkcfg 999999999 0 0 0

  # T1a: seeded (one commit each) — the default-path legs derive a repo key from the root commit, and
  # CI's checkout is shallow, so they must NOT key off the repo this selftest happens to run in.
  rcps_seed "$tmp/repoA" A
  rcps_seed "$tmp/repoB" B

  # ---- (A) poisoned line refused — the read path fails CLOSED on anything but the grammar --------
  # `<epoch> <session-key> <ROW> <tokens> <agents>` (the v2 five-field grammar): three 1–12-digit
  # integers, a [A-Za-z0-9._-]{1,128} key and a board-grammar ROW, single-space separated (the v1
  # four-field shape is refused too). The refusal names the absolute path and the LINE NUMBER — never the
  # bytes (control characters and log injection: the tally is a file any local process can write).
  for b4_bad in '100 1' '' '1757900000 k ROW-T 1234567890123 1' '1757900000 a ROW-T b 3' '1757900000 a ROW-T 3 b' '1757900000 k 1 1 ' \
                '1757900000 k POISONBYTES 1'; do
    printf '%s\n' "$b4_bad" > "$b4_tally"
    b4_run check --config "$b4_cfg" --tally "$b4_tally"
    b4_expect 2 "b4/poison: a line that is not the grammar ('$b4_bad') -> rc 2"
    b4_has "b4/poison: the refusal names the tally's ABSOLUTE path" "$b4_tally"
    b4_has "b4/poison: the refusal names the LINE NUMBER" "line 1"
  done
  b4_hasnt "b4/poison: the refusal never echoes the offending BYTES" "POISONBYTES"
  # …and the liveness anchor: a WELL-FORMED line is accepted (without it every leg above passes on a
  # read path that refuses everything).
  printf '1757900000 keyA ROW-T 100 1\n' > "$b4_tally"
  b4_run check --config "$b4_cfg" --tally "$b4_tally"
  b4_expect 0 "b4/poison-anchor: a well-formed five-field line is ACCEPTED -> rc 0"
  # line cap: a tally past 100000 lines is refused rather than held through every lock spin.
  awk 'BEGIN{for(i=0;i<100001;i++) print "1757900000 keyA ROW-T 1 0"}' > "$b4_tally"
  b4_run check --config "$b4_cfg" --tally "$b4_tally"
  b4_expect 2 "b4/line-cap: a tally past the 100000-line cap -> rc 2"
  b4_has "b4/line-cap: the refusal names the cap" "100000"
  # …and the cap counts RECORDS, not NEWLINES (R2/2). Exactly 100000 terminated lines plus ONE
  # UNTERMINATED record is 100001 records and must be refused; `wc -l` sees 100000 and lets it
  # through. The unterminated last line is precisely what a writer killed mid-append leaves, so this
  # is the shape the cap most needs to see — and until this leg, reverting to `wc -l` left the
  # suite green.
  awk 'BEGIN{for(i=0;i<100000;i++) print "1757900000 keyA ROW-T 1 0"; printf "1757900000 keyA ROW-T 1 0"}' > "$b4_tally"
  b4_run check --config "$b4_cfg" --tally "$b4_tally"
  b4_expect 2 "b4/line-cap: 100000 terminated lines + one UNTERMINATED record is over the cap -> rc 2"
  b4_has "b4/line-cap: the refusal counts records, naming the cap" "100000"

  # ---- (B) sum clamps toward the ceiling — overflow may never read as under-budget ---------------
  # 1001 lines of 999999999999 tokens sum past 10^15; the sum CLAMPS to 10^15 (never wraps), so the
  # STOP names the clamp. On an unclamped %d sum this is a wrapped (possibly negative) number.
  awk 'BEGIN{for(i=0;i<1001;i++) print "1757900000 keyA ROW-T 999999999999 0"}' > "$b4_tally"
  b4_mkcfg 900000000000000 0 0 0
  b4_run check --row ROW-T --config "$b4_cfg" --tally "$b4_tally"   # T1b: the STOP text is the per-row verdict's
  b4_expect 1 "b4/clamp: a sum past 10^15 STOPs (never wraps into under-budget) -> rc 1"
  b4_has "b4/clamp: the STOP names the CLAMPED sum, not a wrapped one" "tokens(1000000000000000/900000000000000)"
  b4_run check --config "$b4_cfg" --tally "$b4_tally"   # M2: the bare-check LISTING clamps too
  b4_has "b4/clamp: the listing carries the CLAMPED sum" "ROW-T tokens=1000000000000000"

  # ---- (C) state dir hygiene — the tally is per REPO (<key>/tally.v2) under $HOME, and refuses a hostile dir ---
  # These legs pass NO override, so they exercise the REAL default path ($HOME/.local/state/
  # sparkwright/runaway/<root-commit>/tally.v2) and the REAL default config — with $HOME pointed inside $tmp.
  b4_h="$tmp/home1"; mkdir -p "$b4_h"
  b4_run_home "$b4_h" step --tokens 1 --agents 0
  b4_expect 0 "b4/state-dir: a step with no override records under \$HOME/.local/state -> rc 0"
  # T1a: the default path is now per repo. The B4 legs run from the seeded $tmp/repoA (b4_run_home cds
  # there), so the key dir is `<root-commit>/tally.v2`; the byte-exact path is asserted by the rcps/v2-line leg.
  [ "$(ls "$b4_h"/.local/state/sparkwright/runaway/*/tally.v2 2>/dev/null | wc -l | tr -d ' ')" = 1 ] \
    || fail "b4/state-dir: no <key>/tally.v2 under \$HOME/.local/state/sparkwright/runaway after a step"
  b4_run_home "relative/home" step --tokens 1 --agents 0
  b4_expect 2 "b4/state-dir: a non-absolute \$HOME -> rc 2 (fail-closed)"
  b4_has "b4/state-dir: the refusal names HOME" "HOME"
  b4_h2="$tmp/home2"; mkdir -p "$b4_h2/.local/state/sparkwright"
  ln -s "$tmp" "$b4_h2/.local/state/sparkwright/runaway"
  b4_run_home "$b4_h2" step --tokens 1 --agents 0
  b4_expect 2 "b4/state-dir: a SYMLINKED runaway/ dir -> rc 2, nothing written"
  b4_has "b4/state-dir: the refusal names the symlink" "symlink"
  [ -f "$tmp/tally" ] && fail "b4/state-dir: the symlinked dir was written THROUGH" || :
  b4_keyA=$(git -C "$tmp/repoA" rev-list --max-parents=0 --first-parent HEAD | tail -1)
  b4_h3="$tmp/home3"; mkdir -p "$b4_h3/.local/state/sparkwright/runaway/$b4_keyA"
  ln -s "$tmp/elsewhere" "$b4_h3/.local/state/sparkwright/runaway/$b4_keyA/tally.v2"
  b4_run_home "$b4_h3" step --tokens 1 --agents 0
  b4_expect 2 "b4/state-dir: a SYMLINKED tally -> rc 2, nothing written"
  [ -f "$tmp/elsewhere" ] && fail "b4/state-dir: the symlinked tally was written THROUGH" || :

  # ---- (D) ONE slice metered from TWO work trees (two session keys) shares ONE budget -------------
  # The defect this slice closes: N worktrees used to get N silent ceilings. Two work trees of ONE repo
  # are two session keys over ONE `<root-commit>/tally.v2`; a slice metered from both is graded on the sum,
  # so the SECOND tree STOPs on the combined total. The load-bearing NEGATIVE: two DIFFERENT rows from
  # the same two trees do NOT combine (each row is graded alone).
  git -C "$tmp/repoA" worktree add -q --detach "$tmp/repoA-wt" HEAD 2>/dev/null || fail "b4/combined: could not stage the second work tree"
  b4_mkcfg 1500 0 0 0
  b4_hd="$tmp/homeD"; mkdir -p "$b4_hd"
  b4_run_wt "$tmp/repoA" "$b4_hd" step --row ROW-D1 --tokens 1000 --agents 0
  b4_expect 0 "b4/combined: tree A alone on ROW-D1 (1000/1500) -> rc 0"
  b4_run_wt "$tmp/repoA-wt" "$b4_hd" step --row ROW-D1 --tokens 1000 --agents 0
  b4_expect 1 "b4/combined: tree B's step on the SAME row crosses the shared ceiling -> rc 1"
  b4_has "b4/combined: the STOP names the tokens dimension of the shared row" "tokens(2000/1500)"
  b4_dt=$(ls "$b4_hd"/.local/state/sparkwright/runaway/*/tally.v2 2>/dev/null)
  [ "$(printf '%s\n' "$b4_dt" | grep -c .)" = 1 ] || fail "b4/combined: the two work trees did not share ONE tally.v2 (found: [$b4_dt])"
  [ "$(wc -l < "$b4_dt" | tr -d ' ')" = 2 ] || fail "b4/combined: expected 2 tally lines"
  [ "$(awk '{print $2}' "$b4_dt" | sort -u | wc -l | tr -d ' ')" = 2 ] \
    || fail "b4/combined: the two work trees did not record DISTINCT session keys"
  b4_hd2="$tmp/homeD2"; mkdir -p "$b4_hd2"
  b4_run_wt "$tmp/repoA" "$b4_hd2" step --row ROW-D1 --tokens 1000 --agents 0
  b4_expect 0 "b4/combined-negative: ROW-D1 from tree A (1000/1500) -> rc 0"
  b4_run_wt "$tmp/repoA-wt" "$b4_hd2" step --row ROW-D2 --tokens 1000 --agents 0
  b4_expect 0 "b4/combined-negative: a DIFFERENT row from tree B does NOT combine with ROW-D1 (a sum is 2000/1500) -> rc 0"
  b4_has "b4/combined-negative: ROW-D2 is graded on its own 1000" "tokens(1000/1500)"
  # a session key is REQUIRED: outside a git work tree there is no key, and the step is refused.
  b4_run_in "$tmp" step --tokens 1 --agents 0
  b4_expect 2 "b4/session-key: a step from outside any git work tree -> rc 2"

  # ---- (E) DELETED (T1b): `reset` is retired (rc 2), so "reset scopes to its own key" asserts a behaviour
  # that no longer exists. The replacement is rcps leg 10 (reset -> rc 2, the tally byte-identical).

  # ---- (F) concurrent steps serialize — 20 parallel steps, 20 lines, correct sum -----------------
  # ⚠️ EVERY STEP'S EXIT CODE AND STDERR ARE KEPT, BECAUSE A MISSING LINE HAS TWO CAUSES AND THEY ARE
  # OPPOSITES (CI round). `record()` is a plain `>>`, which is atomic for a short line, so the likely
  # cause of 19-of-20 is NOT a lost append at all: it is a contender that hit the spin bound and
  # exited 2 — the guard working exactly as designed — on a slow, loaded runner. The first draft of
  # this leg discarded rc and stderr and called that "an append outside the lock", which is how a
  # correct fail-closed refusal got reported to CI as a concurrency bug. A leg that cannot tell a
  # TIMEOUT from a LOST LINE is not measuring serialization; it is guessing at it.
  : > "$b4_tally"; b4_mkcfg 0 0 0 0
  b4_rundir="$tmp/serialize"; rm -rf "$b4_rundir"; mkdir -p "$b4_rundir"
  b4_i=0
  while [ "$b4_i" -lt 20 ]; do
    # ⚠️ THE rc IS CAPTURED WITH THE `if`/`else` IDIOM, NEVER `cmd; echo $?` — the same trap this
    # file's fail-closed note already records: under `set -e` a failing command aborts the SUBSHELL
    # before the next statement runs, so `echo $?` never executed and every refusing step reported
    # its rc as "missing" (measured, first draft of this leg).
    ( cd "$tmp/repoA" || exit 9
      if HOME="$tmp/hsafe" KIT_RUNAWAY_SANDBOX="$b4_sand" sh "$b4_guard" step --row ROW-T \
           --config "$b4_cfg" --tally "$b4_tally" --tokens 7 --agents 1 \
           >/dev/null 2>"$b4_rundir/$b4_i.err"; then _sr=0; else _sr=$?; fi
      echo "$_sr" > "$b4_rundir/$b4_i.rc" ) &
    b4_i=$((b4_i + 1))
  done
  wait
  b4_i=0
  while [ "$b4_i" -lt 20 ]; do
    b4_src=$(cat "$b4_rundir/$b4_i.rc" 2>/dev/null || echo missing)
    case "$b4_src" in
      0) : ;;
      # the LAST stderr line, not the first: the first is the sandbox banner every dialled run emits,
      # and a diagnostic that quotes the banner instead of the refusal tells the reader nothing.
      2) fail "b4/serialize: step $b4_i TIMED OUT on the lock (rc 2, a correct fail-closed refusal — NOT a lost append). The spin bound is too tight for 20 serialized contenders on this machine. Its stderr: [$(tail -1 "$b4_rundir/$b4_i.err" 2>/dev/null)]" ;;
      *) fail "b4/serialize: step $b4_i exited $b4_src; stderr: [$(tail -1 "$b4_rundir/$b4_i.err" 2>/dev/null)]" ;;
    esac
    b4_i=$((b4_i + 1))
  done
  [ "$(wc -l < "$b4_tally" | tr -d ' ')" = 20 ] \
    || fail "b4/serialize: every step reported rc 0, but the tally holds $(wc -l < "$b4_tally" | tr -d ' ') lines, not 20 — THAT is a lost append (a write outside the lock)"
  [ "$(awk '{t+=$4} END{printf "%d", t}' "$b4_tally")" = 140 ] \
    || fail "b4/serialize: the 20 parallel steps do not sum to 140 tokens"
  [ -e "$b4_sand/lock" ] && fail "b4/serialize: a lock dir survived the fan-out (not released)" || :
  rcps_lk_residue "b4/serialize"   # L6: no lock.tok.*, lock.stale.* or pid.dead.* left by the fan-out
  rm -rf "$b4_rundir"

  # ---- (G) two breakers one winner — a DEAD holder's token is broken by rename, exactly once ------
  # A lock dir with NO pid file is the creation window and counts as LIVE; an unparseable pid counts
  # as LIVE (never as dead: `kill -0 -1` would otherwise succeed forever); only a validated, dead pid
  # is broken, and the break is `mv lock/pid lock/pid.dead.$$` so exactly one of two breakers wins it.
  # ⚠️ THE TOKEN IS `<pid> <epoch>` (CI round / ABA): a breaker needs a dead pid AND a lock older than
  # RG_LOCK_MIN_AGE, so these fixtures carry a deliberately OLD epoch. A bare pid — which is what this
  # fixture used to write — is now correctly read as LIVE, which is the fail-closed direction.
  : > "$b4_tally"; b4_mkcfg 0 0 0 0
  b4_dead=$( sh -c 'echo $$' )
  b4_old=$(( $(date -u +%s) - 3600 ))
  mkdir -p "$b4_sand/lock"; printf '%s %s\n' "$b4_dead" "$b4_old" > "$b4_sand/lock/pid"
  ( cd "$tmp/repoA" && HOME="$tmp/hsafe" KIT_RUNAWAY_SANDBOX="$b4_sand" sh "$b4_guard" step --row ROW-T \
      --config "$b4_cfg" --tally "$b4_tally" --tokens 1 --agents 0 >/dev/null 2>&1 ) &
  ( cd "$tmp/repoB" && HOME="$tmp/hsafe" KIT_RUNAWAY_SANDBOX="$b4_sand" sh "$b4_guard" step --row ROW-T \
      --config "$b4_cfg" --tally "$b4_tally" --tokens 1 --agents 0 >/dev/null 2>&1 ) &
  wait
  [ "$(wc -l < "$b4_tally" | tr -d ' ')" = 2 ] \
    || fail "b4/breakers: one mv of the token wins the break and BOTH contenders land a line (two contenders on a DEAD holder's lock did not)"
  [ -d "$b4_sand/lock" ] && fail "b4/breakers: the lock dir survived the run (not released)" || :
  rcps_lk_residue "b4/breakers"
  # ⚠️ THE "TREATED AS LIVE" LEGS ASSERT THE LOCK IS STILL THERE, THEY DO NOT WAIT OUT THE BOUND.
  # With the bound at 30s, three legs that each sat until expiry would add 90s to every run. Observing
  # that the lock SURVIVES a contender — and that the tally is still empty — is the direct assertion
  # ("it was not broken"), and it is strictly stronger than an rc that only says "something refused".
  # The bound's own expiry is proven quickly by b4/spin-bound below (an unbreakable lock, no sleeps).
  : > "$b4_tally"
  b4_notbroken() {   # <label> — a contender must NOT break the lock it is pointed at
    ( cd "$tmp/repoA" && exec env HOME="$tmp/hsafe" KIT_RUNAWAY_SANDBOX="$b4_sand" \
        sh "$b4_guard" step --row ROW-T --config "$b4_cfg" --tally "$b4_tally" --tokens 1 --agents 0 \
        >/dev/null 2>&1 ) &
    b4_np=$!
    sleep 2
    [ -d "$b4_sand/lock" ] || fail "$1: the lock was BROKEN by a contender that must have treated it as live"
    [ "$(wc -c < "$b4_tally" | tr -d ' ')" = 0 ] || fail "$1: the contender APPENDED while the lock was held"
    kill -TERM "$b4_np" 2>/dev/null || :
    if wait "$b4_np"; then b4_rc=0; else b4_rc=$?; fi
    [ "$b4_rc" = 2 ] || fail "$1: the interrupted contender exited $b4_rc, not 2"
    rcps_lk_residue "$1"
  }
  rm -rf "$b4_sand/lock"; mkdir -p "$b4_sand/lock"   # NO pid file = the creation window = LIVE
  b4_notbroken "b4/breakers: a lock dir with NO pid file is treated as LIVE"
  printf 'not-a-pid\n' > "$b4_sand/lock/pid"
  b4_notbroken "b4/breakers: an UNPARSEABLE pid token is treated as LIVE, never as dead"
  printf '%s\n' "$b4_dead" > "$b4_sand/lock/pid"     # a dead pid but NO epoch field -> not a token
  b4_notbroken "b4/breakers: a one-field token (dead pid, no epoch) is treated as LIVE"
  # (a) THE ABA GATE: a DEAD pid with a FRESH epoch must NOT be broken. This is the read-then-recycle
  # race — the contender judged holder A, A released, B took the lock — and the fresh epoch is what
  # says "this lock is not the one you judged".
  # ⚠️ THE FIXTURE'S EPOCH IS AHEAD OF NOW, AND WHAT THAT PROVES IS NARROWER THAN IT LOOKS. A literal
  # `date +%s` here is only protected for RG_LOCK_MIN_AGE seconds — less time than this leg spends
  # OBSERVING that the lock survived — so the first draft watched the guard break it at t≈2s and
  # reported a failure that was really the leg racing its own gate. SO, PRECISELY: this fixture
  # proves the gate refuses a token it CANNOT AGE OUT; it does NOT exercise the real 0–2 s window a
  # freshly-taken lock lives in, which is the case the ABA actually turns on and which no external
  # fixture can hold still. Leg (b) below is the non-vacuity anchor — same dead pid, old epoch, and
  # the break DOES happen — so the gate cannot be a blanket refusal.
  printf '%s %s\n' "$b4_dead" "$(( $(date -u +%s) + 3600 ))" > "$b4_sand/lock/pid"
  b4_notbroken "b4/aba: a dead pid on a lock younger than the gate is NOT broken"
  # (S2) EPERM IS NOT DEATH. `kill -0 <pid>` against a pid owned by ANOTHER UID answers "Operation
  # not permitted" — which PROVES the process exists — and reading that non-zero rc as "dead" let a
  # token naming pid 1 (init, or any root process) break a live lock. pid 1 exists on every machine
  # this runs on and is never ours, so it is the honest fixture for the EPERM branch.
  printf '1 %s\n' "$b4_old" > "$b4_sand/lock/pid"
  b4_notbroken "b4/eperm: a pid owned by another uid (EPERM, not ESRCH) is treated as LIVE"
  # (S1) NO CODE PATH REMOVES OR RENAMES A LOCK THIS PROCESS DOES NOT OWN. The mismatch (ABA) arm is not
  # reachable deterministically from outside without a staged shim (see rcps_lk_legs L3/L3b), so what is
  # asserted here is the INVARIANT that arm exists to protect: after a contender has run against a
  # live-token lock, the lock dir and its token are BYTE-IDENTICAL and no residue exists anywhere. (The
  # label is kept from the rename-the-dir protocol; the invariant is unchanged.)
  printf '%s %s\n' "$$" "$b4_old" > "$b4_sand/lock/pid"
  b4_tok0=$(cat "$b4_sand/lock/pid")
  b4_notbroken "b4/aba-restore: a LIVE-token lock is never removed by a contender"
  [ "$(cat "$b4_sand/lock/pid" 2>/dev/null)" = "$b4_tok0" ] \
    || fail "b4/aba-restore: the live holder's token was REWRITTEN by a contender (was [$b4_tok0], now [$(cat "$b4_sand/lock/pid" 2>/dev/null)])"
  rcps_lk_residue "b4/aba-restore"
  # (b) …and the liveness anchor for the gate: the same dead pid with an OLD epoch IS broken, so the
  # gate is an age check and not a blanket refusal to ever break anything.
  printf '%s %s\n' "$b4_dead" "$b4_old" > "$b4_sand/lock/pid"
  b4_run_in "$tmp/repoA" step --config "$b4_cfg" --tally "$b4_tally" --tokens 1 --agents 0
  b4_expect 0 "b4/aba: the same dead pid with an OLD epoch IS broken and the step proceeds -> rc 0"
  [ "$(wc -l < "$b4_tally" | tr -d ' ')" = 1 ] || fail "b4/aba: the broken-lock step did not land its line"

  # ---- (H) lock timeout fails closed — a LIVE foreign holder -> rc 2, and NO append --------------
  # This one DOES wait out the bound: it is the canonical "a live holder eventually refuses" claim,
  # and it is the only leg that pays for it.
  : > "$b4_tally"
  rm -rf "$b4_sand/lock"; mkdir -p "$b4_sand/lock"
  printf '%s %s\n' "$$" "$b4_old" > "$b4_sand/lock/pid"   # this very process: unambiguously LIVE
  b4_run_in "$tmp/repoA" step --config "$b4_cfg" --tally "$b4_tally" --tokens 1 --agents 0
  b4_expect 2 "b4/lock-timeout: a LIVE foreign lock -> rc 2 UNVERIFIED, never an unlocked append"
  b4_has "b4/lock-timeout: the refusal names the lock" "lock"
  b4_has "b4/lock-timeout: the refusal states the bound it waited out" "tries"
  [ "$(wc -c < "$b4_tally" | tr -d ' ')" = 0 ] || fail "b4/lock-timeout: the timed-out step appended anyway"
  rm -rf "$b4_sand/lock"

  # ---- (I) override refused without the dial — a second tally IS a second ceiling ----------------
  # All four spellings of the two redirection routes refuse (rc 2) unless KIT_RUNAWAY_SANDBOX names a
  # directory the path canonicalizes under. Stricter than "refused out of repo": an in-repo second
  # tally is still a second ceiling, and zero callers pass an in-repo override.
  : > "$b4_tally"; b4_mkcfg 0 0 0 0
  b4_run_nodial check --config "$b4_cfg"
  b4_expect 2 "b4/override: --config without the dial -> rc 2"
  b4_has "b4/override: the refusal names the dial that WOULD vouch for it" "KIT_RUNAWAY_SANDBOX"
  b4_has "b4/override: the refusal says why (a second ceiling)" "SECOND CEILING"
  b4_run_nodial check --tally "$b4_tally"
  b4_expect 2 "b4/override: --tally without the dial -> rc 2"
  b4_run_nodial_env RUNAWAY_BUDGET_CONFIG "$b4_cfg" check
  b4_expect 2 "b4/override: RUNAWAY_BUDGET_CONFIG without the dial -> rc 2"
  b4_has "b4/override: the refusal names the ENV spelling it refused" "RUNAWAY_BUDGET_CONFIG"
  b4_run_nodial_env RUNAWAY_TALLY "$b4_tally" check
  b4_expect 2 "b4/override: RUNAWAY_TALLY without the dial -> rc 2"
  b4_has "b4/override: the refusal names the ENV spelling it refused" "RUNAWAY_TALLY"
  # with the dial: INSIDE is accepted and BANNERED; outside is refused, `..` included.
  b4_run check --config "$b4_cfg" --tally "$b4_tally"
  b4_expect 0 "b4/override: a path INSIDE the sandbox is accepted -> rc 0"
  b4_has "b4/override: every sandboxed invocation BANNERS on stderr" "SANDBOX override active"
  mkdir -p "$b4_sand/../outside-$$"
  printf '1757900000 keyA ROW-T 1 0\n' > "$b4_sand/../outside-$$/t"
  b4_run check --config "$b4_cfg" --tally "$b4_sand/../outside-$$/t"
  b4_expect 2 "b4/override: a '..' path that leaves the sandbox -> rc 2"
  b4_has "b4/override: the refusal names the sandbox it is outside of" "OUTSIDE the sandbox"
  ln -s "$b4_sand/../outside-$$/t" "$b4_sand/link-out"
  b4_run check --config "$b4_cfg" --tally "$b4_sand/link-out"
  b4_expect 2 "b4/override: a SYMLINKED leaf inside the sandbox (a hop out) -> rc 2"
  b4_has "b4/override: the refusal names the symlink" "symlink"
  # …and the sibling-prefix negative: /tmp/x must never vouch for /tmp/xy (trailing-slash match).
  mkdir -p "${b4_sand}y"; printf '1757900000 keyA ROW-T 1 0\n' > "${b4_sand}y/t"
  b4_run check --config "$b4_cfg" --tally "${b4_sand}y/t"
  b4_expect 2 "b4/override: a SIBLING dir whose name merely PREFIX-matches the sandbox -> rc 2"
  rm -rf "$b4_sand/../outside-$$" "${b4_sand}y" "$b4_sand/link-out"

  # ---- (J) wip leg — WIP is BOARD state, counted at claim, not run usage ------------------------
  # `board-claim.sh claim` counts the claim refs on ORIGIN and passes the number here. Adopters
  # without a budget.conf, or without MAX_WIP, keep `claim` working: N/A, rc 0. A malformed value
  # fails closed. `n >= max` STOPs naming wip(<n>/<max>).
  # ⚠️ THE NUMERIC ASSERTIONS RUN OFF A FIXTURE CONFIG, NOT THE KIT'S LIVE ONE (R1/H4). They used to
  # hard-code `1/2` and `wip(2/2)` against the committed .kit/budget.conf — whose MAX_WIP is a
  # RATIFIABLY RAISABLE ceiling, so raising it to 3 turned this selftest red. A test that forbids a
  # governed act is a test that will be deleted by whoever performs it.
  printf 'MAX_WIP=2\n' > "$b4_cfg"
  b4_run wip --config "$b4_cfg" --count 1
  b4_expect 0 "b4/wip: one slice in flight against a fixture MAX_WIP=2 -> rc 0"
  b4_has "b4/wip: the OK line names the count against the ceiling" "1/2"
  b4_run wip --config "$b4_cfg" --count 2
  b4_expect 1 "b4/wip: --count 2 against a fixture MAX_WIP=2 -> rc 1"
  b4_has "b4/wip: the STOP names the wip dimension and the numbers" "wip(2/2)"
  # …and ONE leg against the LIVE committed config, asserting what must not drift — that a numeric
  # MAX_WIP is DECLARED and that the guard enforces THAT value, whatever the owner has ratified it to.
  # ⚠️ PARSED BY THE GUARD'S OWN GRAMMAR, NOT A STRICTER ONE (R2/1). `^MAX_WIP=` refused the
  # whitespace `cfg()` tolerates, so a ratified raise written `MAX_WIP = 3` left the guard enforcing
  # 3 while this leg hard-failed "declares no numeric MAX_WIP" — CI red for a correctly ratified act.
  # A test that reads the config more strictly than the thing under test is testing its own parser.
  b4_kitwip=$(sed -n 's/^[[:space:]]*MAX_WIP[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' .kit/budget.conf | head -1)
  case "$b4_kitwip" in
    ''|*[!0-9]*) fail "b4/wip-live: .kit/budget.conf declares no numeric MAX_WIP (got '$b4_kitwip')" ;;
  esac
  if [ "$b4_kitwip" -gt 0 ]; then
    b4_run_nodial wip --count "$b4_kitwip"
    b4_expect 1 "b4/wip-live: the kit's own declared MAX_WIP ($b4_kitwip) is enforced at its own value -> rc 1"
    b4_has "b4/wip-live: the STOP names the declared ceiling" "wip($b4_kitwip/$b4_kitwip)"
  fi
  printf 'MAX_TOKENS=0\n' > "$b4_cfg"
  b4_run wip --config "$b4_cfg" --count 9
  b4_expect 0 "b4/wip: a config with no MAX_WIP -> N/A, rc 0 (an adopter's claim keeps working)"
  b4_has "b4/wip: the N/A verdict says which key is undeclared" "MAX_WIP undeclared"
  printf 'MAX_WIP=0\n' > "$b4_cfg"
  b4_run wip --config "$b4_cfg" --count 9
  b4_expect 0 "b4/wip: MAX_WIP=0 disables the dimension -> N/A, rc 0"
  printf 'MAX_WIP=two\n' > "$b4_cfg"
  b4_run wip --config "$b4_cfg" --count 1
  b4_expect 2 "b4/wip: a MALFORMED MAX_WIP -> rc 2 (fail-closed), never a silent pass"
  printf 'MAX_WIP=2\n' > "$b4_cfg"
  b4_run wip --config "$b4_cfg" --count x
  b4_expect 2 "b4/wip: a malformed --count -> rc 2"
  b4_run wip --config "$b4_cfg"
  b4_expect 2 "b4/wip: wip with NO --count at all -> rc 2, never an unbounded pass"
  # the tally/lock are never touched by `wip` (it is board state, not run usage)
  [ -e "$b4_sand/lock" ] && fail "b4/wip: wip took the tally lock" || :

  # ---- (K) R1/H3: the WRITE path is bound by the grammar the READ path enforces ------------------
  # A 13-digit --tokens is an ALLOWED agent Bash call needing no dial. Appended, it poisons the
  # repo's tally permanently: every later read refuses and every session on that repo STOPs.
  : > "$b4_tally"; b4_mkcfg 0 0 0 0
  b4_run_in "$tmp/repoA" step --tokens 9999999999999 --agents 0
  b4_expect 2 "b4/write-grammar: a 13-digit --tokens -> rc 2 (refused at parse)"
  b4_has "b4/write-grammar: the refusal names the grammar it would have violated" "12 digits"
  [ "$(wc -c < "$b4_tally" | tr -d ' ')" = 0 ] \
    || fail "b4/write-grammar: the over-long step APPENDED — the tally is now permanently poisoned"
  b4_run_in "$tmp/repoA" step --tokens 0 --agents 9999999999999
  b4_expect 2 "b4/write-grammar: a 13-digit --agents -> rc 2"
  [ "$(wc -c < "$b4_tally" | tr -d ' ')" = 0 ] || fail "b4/write-grammar: the over-long agents step APPENDED"
  # liveness: a 12-digit value is INSIDE the grammar and is still accepted.
  b4_run_in "$tmp/repoA" step --tokens 999999999999 --agents 0
  b4_expect 0 "b4/write-grammar: a 12-digit --tokens is inside the grammar -> rc 0 (the bound is not a blanket refusal)"

  # ---- (L) R1/H1: INTERRUPTED MEANS UNVERIFIED — a signal may never become an unlocked append -----
  # One `trap … EXIT INT TERM` released the lock on SIGTERM and then RESUMED the interrupted flow, so
  # a step killed mid-spin carried on to record() with the lock released: an unlocked append, rc 0.
  : > "$b4_tally"; b4_mkcfg 0 0 0 0
  mkdir -p "$b4_sand/lock"; printf '%s\n' "$$" > "$b4_sand/lock/pid"      # a LIVE foreign holder
  # `exec` so $! is the GUARD's pid, not a wrapping subshell's — a TERM to the wrapper would never
  # reach the process under test and the leg would pass on a signal nothing received.
  ( cd "$tmp/repoA" && exec env HOME="$tmp/hsafe" KIT_RUNAWAY_SANDBOX="$b4_sand" \
      sh "$b4_guard" step --row ROW-T --config "$b4_cfg" --tally "$b4_tally" --tokens 5 --agents 0 \
      >/dev/null 2>&1 ) &
  b4_kpid=$!
  # ⚠️ THE FOREIGN LOCK IS RELEASED SHORTLY AFTER THE SIGNAL, and that is what makes this leg a
  # DISCRIMINATOR rather than a formality: if the signal merely released our (unheld) lock and let
  # the flow RESUME, the spin would then find the lock free, take it, and APPEND — rc 0. Only a
  # handler that EXITS leaves the tally empty. Without the release, both implementations time out at
  # rc 2 and the leg proves nothing (measured: it passed against the unfixed trap).
  ( sleep 2; rm -rf "$b4_sand/lock" ) &
  b4_cpid=$!
  sleep 1
  kill -TERM "$b4_kpid" 2>/dev/null || :
  if wait "$b4_kpid"; then b4_rc=0; else b4_rc=$?; fi
  wait "$b4_cpid" 2>/dev/null || :
  [ "$b4_rc" = 2 ] \
    || fail "b4/signal: a TERMed step exited $b4_rc, not the script's own 2 (UNVERIFIED) — the signal path does not fail closed"
  [ "$(wc -c < "$b4_tally" | tr -d ' ')" = 0 ] \
    || fail "b4/signal: the TERMed step APPENDED — the signal released the lock and the flow carried on"
  rm -rf "$b4_sand/lock"

  # ---- (M) R1/H2: the bounded spin stays bounded when the BREAK itself cannot succeed -------------
  # A dead-pid lock in a state directory that is no longer writable: mkdir fails, mv fails, and the
  # old `continue` skipped both the counter and the sleep — an unbounded 100%-CPU loop. Bound it.
  b4_ro="$b4_sand/ro"; mkdir -p "$b4_ro/lock"
  : > "$b4_ro/t"
  # a dead pid with an OLD epoch: the guard KEEPS TRYING to break it (and cannot, the dir is not
  # writable), which is the path that used to spin forever — and it is also why this leg expires
  # fast: the break path costs a try but no sleep.
  printf '%s %s\n' "$b4_dead" "$b4_old" > "$b4_ro/lock/pid"
  chmod a-w "$b4_ro"
  b4_t0=$(date +%s)
  b4_run_in2 "$tmp/repoA" "$b4_cfg" "$b4_ro/t" step --tokens 1 --agents 0
  b4_t1=$(date +%s)
  chmod u+w "$b4_ro"
  b4_expect 2 "b4/spin-bound: an unbreakable dead-pid lock -> rc 2 (fail-closed), not a forever loop"
  [ "$((b4_t1 - b4_t0))" -lt 30 ] \
    || fail "b4/spin-bound: the guard span $((b4_t1 - b4_t0))s on an unbreakable lock — the spin is not bounded"
  [ "$(wc -c < "$b4_ro/t" | tr -d ' ')" = 0 ] || fail "b4/spin-bound: the timed-out step appended anyway"
  rm -rf "$b4_ro"

  # ---- (N) R1/L1: a symlinked ANCESTOR redirects the tally out of $HOME ---------------------------
  # `mkdir -p "$HOME/.local/state"` FOLLOWS a symlinked `.local` or `.local/state`, so the tally
  # landed outside $HOME while the hygiene checks (which only looked at sparkwright/ and runaway/)
  # reported clean. Every ancestor is vetted now.
  b4_h4="$tmp/home4"; mkdir -p "$b4_h4/.local"
  ln -s "$tmp" "$b4_h4/.local/state"
  b4_run_home "$b4_h4" step --tokens 1 --agents 0
  b4_expect 2 "b4/ancestor: a SYMLINKED .local/state -> rc 2, the tally is not redirected out of \$HOME"
  b4_has "b4/ancestor: the refusal names the symlink" "symlink"
  [ -e "$tmp/sparkwright" ] && fail "b4/ancestor: the tally tree was created THROUGH the symlinked ancestor" || :
  b4_h5="$tmp/home5"; mkdir -p "$b4_h5"
  ln -s "$tmp" "$b4_h5/.local"
  b4_run_home "$b4_h5" step --tokens 1 --agents 0
  b4_expect 2 "b4/ancestor: a SYMLINKED .local -> rc 2"
}

# rcps_legs — RUNAWAY-CEILING-PER-SLICE T1a: the per-repo v2 tally file. Every leg sets HOME to a temp
# dir and runs in a SEEDED fixture repo (a fresh repo + one commit); nothing touches the real $HOME.
rcps_seed() {   # <dir> <marker> — a repo with exactly one commit; <marker> makes the root commit unique
  git init -q "$1" 2>/dev/null
  git -C "$1" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty -m "seed $2"
}
# rcps_run <dir> <home> <args...> — the default state dir, the dial UNSET, HOME pinned
rcps_run() {
  _rd=$1; _rh=$2; shift 2
  if b4_out=$( cd "$_rd" && env -u KIT_RUNAWAY_SANDBOX HOME="$_rh" sh "$b4_guard" "$@" 2>&1 ); then b4_rc=0; else b4_rc=$?; fi
}
rcps_keys() { ls -d "$1"/.local/state/sparkwright/runaway/*/ 2>/dev/null | wc -l | tr -d ' '; }
rcps_legs() {
  rc_root="$tmp/rcps"; mkdir -p "$rc_root"
  rc_sb="$rc_root/sb"; mkdir -p "$rc_sb"
  rc_base="$rc_root/base"; rcps_seed "$rc_base" base
  rc_key=$(git -C "$rc_base" rev-list --max-parents=0 --first-parent HEAD | tail -1)

  # ---- (1) a v2 line lands in <key>/tally.v2, five fields; the awk sums ONLY the requested row ------
  rc_h1="$rc_root/h1"; mkdir -p "$rc_h1"
  rcps_run "$rc_base" "$rc_h1" step --row ROW-A --tokens 5 --agents 1
  b4_expect 0 "rcps/v2-line: a step with --row lands -> rc 0"
  rc_f="$rc_h1/.local/state/sparkwright/runaway/$rc_key/tally.v2"
  [ -f "$rc_f" ] || fail "rcps/v2-line: no tally.v2 at runaway/<root-commit>/tally.v2"
  [ "$(awk 'NF==5 && $3=="ROW-A" && $4==5 && $5==1 {n++} END{print n+0}' "$rc_f")" = 1 ] \
    || fail "rcps/v2-line: the line is not '<epoch> <key> ROW-A 5 1'; file=[$(cat "$rc_f")]"
  [ -e "$rc_h1/.local/state/sparkwright/runaway/tally" ] && fail "rcps/v2-line: the step wrote the v1 path" || :
  rcps_run "$rc_base" "$rc_h1" step --tokens 5 --agents 1
  b4_expect 2 "rcps/v2-line: a step with NO --row -> rc 2 (a slice must be named)"
  # the sum is per ROW: A at 900 and B at 900 against MAX_TOKENS=1000 is silent; A's next 100 STOPs.
  printf 'MAX_TOKENS=1000\nMAX_STEPS=0\nMAX_AGENTS=0\nWARN_PCT=0\n' > "$rc_sb/c"
  rc_h1b="$rc_root/h1b"; mkdir -p "$rc_h1b"
  rcps_sum() { if b4_out=$( cd "$rc_base" && HOME="$rc_h1b" KIT_RUNAWAY_SANDBOX="$rc_sb" sh "$b4_guard" step --row ROW-T --config "$rc_sb/c" "$@" 2>&1 ); then b4_rc=0; else b4_rc=$?; fi; }
  rcps_sum --row ROW-A --tokens 900 --agents 0; b4_expect 0 "rcps/row-sum: A at 900/1000 -> rc 0"
  rcps_sum --row ROW-B --tokens 900 --agents 0; b4_expect 0 "rcps/row-sum: B at 900 is NOT summed with A (a sum of all rows is 1800 -> STOP) -> rc 0"
  rcps_sum --row ROW-A --tokens 100 --agents 0; b4_expect 1 "rcps/row-sum: A's own 1000/1000 STOPs -> rc 1"
  b4_has "rcps/row-sum: the STOP is A's own sum" "tokens(1000/1000)"

  # ---- (2) the v1 file is byte-identical after a step (NEGATIVE: v1 untouched) ---------------------
  rc_h2="$rc_root/h2"; mkdir -p "$rc_h2/.local/state/sparkwright/runaway"
  printf '1757900000 keyA 100 1\n1757900001 keyB 7 0\n' > "$rc_h2/.local/state/sparkwright/runaway/tally"
  rc_v1a=$(cksum < "$rc_h2/.local/state/sparkwright/runaway/tally")
  rcps_run "$rc_base" "$rc_h2" step --row ROW-A --tokens 1 --agents 0
  b4_expect 0 "rcps/v1-untouched: a step beside a v1 file -> rc 0 (the v1 file is not READ, so it cannot poison)"
  [ "$(cksum < "$rc_h2/.local/state/sparkwright/runaway/tally")" = "$rc_v1a" ] \
    || fail "rcps/v1-untouched: the v1 runaway/tally changed"
  [ -f "$rc_h2/.local/state/sparkwright/runaway/$rc_key/tally.v2" ] || fail "rcps/v1-untouched: the v2 line did not land"

  # ---- (3) two clones of one repo (a path and a file:// URL) share ONE key dir --------------------
  rc_h3="$rc_root/h3"; mkdir -p "$rc_h3"
  git clone -q "$rc_base" "$rc_root/clonep" 2>/dev/null
  git clone -q "file://$rc_base" "$rc_root/cloneu" 2>/dev/null
  rcps_run "$rc_root/clonep" "$rc_h3" step --row ROW-A --tokens 1 --agents 0; b4_expect 0 "rcps/clones: path clone -> rc 0"
  rcps_run "$rc_root/cloneu" "$rc_h3" step --row ROW-A --tokens 1 --agents 0; b4_expect 0 "rcps/clones: file:// clone -> rc 0"
  [ "$(rcps_keys "$rc_h3")" = 1 ] || fail "rcps/clones: two clones of one repo made $(rcps_keys "$rc_h3") key dirs, not 1"
  [ "$(wc -l < "$rc_h3/.local/state/sparkwright/runaway/$rc_key/tally.v2" | tr -d ' ')" = 2 ] \
    || fail "rcps/clones: the two clones' lines did not land in the one file"

  # ---- (4) two different repos make TWO key dirs -------------------------------------------------
  rc_h4="$rc_root/h4"; mkdir -p "$rc_h4"
  rc_other="$rc_root/other"; rcps_seed "$rc_other" other
  rcps_run "$rc_base" "$rc_h4" step --row ROW-A --tokens 1 --agents 0; b4_expect 0 "rcps/repos: repo one -> rc 0"
  rcps_run "$rc_other" "$rc_h4" step --row ROW-A --tokens 1 --agents 0; b4_expect 0 "rcps/repos: repo two -> rc 0"
  [ "$(rcps_keys "$rc_h4")" = 2 ] || fail "rcps/repos: two different repos made $(rcps_keys "$rc_h4") key dirs, not 2"

  # ---- (5) a merge of an UNRELATED history keeps the key ----------------------------------------
  rc_h5="$rc_root/h5"; mkdir -p "$rc_h5"
  rc_m="$rc_root/merged"; git clone -q "$rc_base" "$rc_m" 2>/dev/null
  rcps_run "$rc_m" "$rc_h5" step --row ROW-A --tokens 1 --agents 0; b4_expect 0 "rcps/merge: before the merge -> rc 0"
  git -C "$rc_m" fetch -q "$rc_other" HEAD 2>/dev/null
  git -C "$rc_m" -c user.name=t -c user.email=t@t -c commit.gpgsign=false merge -q --allow-unrelated-histories -m unrelated FETCH_HEAD >/dev/null 2>&1
  [ "$(git -C "$rc_m" rev-list --max-parents=0 HEAD | wc -l | tr -d ' ')" = 2 ] \
    || fail "rcps/merge: the fixture is vacuous — the merged repo does not have two roots"
  rcps_run "$rc_m" "$rc_h5" step --row ROW-A --tokens 1 --agents 0; b4_expect 0 "rcps/merge: after the merge -> rc 0"
  [ "$(rcps_keys "$rc_h5")" = 1 ] || fail "rcps/merge: the merge of an unrelated history CHANGED the key ($(rcps_keys "$rc_h5") key dirs)"

  # ---- (6) a SHALLOW clone is refused, naming the fix (NEGATIVE: the full clone in (3) is accepted) -
  rc_h6="$rc_root/h6"; mkdir -p "$rc_h6"
  git clone -q --depth 1 "file://$rc_m" "$rc_root/shallow" 2>/dev/null
  rcps_run "$rc_root/shallow" "$rc_h6" step --row ROW-A --tokens 1 --agents 0
  b4_expect 2 "rcps/shallow: a --depth 1 clone -> rc 2"
  b4_has "rcps/shallow: the refusal names the fix" "git fetch --unshallow"
  [ "$(rcps_keys "$rc_h6")" = 0 ] || fail "rcps/shallow: a key dir was created for a shallow clone"

  # ---- (7) a SYMLINKED <key> dir is refused — the hygiene reaches the new level -------------------
  rc_h7="$rc_root/h7"; mkdir -p "$rc_h7/.local/state/sparkwright/runaway" "$rc_root/elsewhere7"
  ln -s "$rc_root/elsewhere7" "$rc_h7/.local/state/sparkwright/runaway/$rc_key"
  rcps_run "$rc_base" "$rc_h7" step --row ROW-A --tokens 1 --agents 0
  b4_expect 2 "rcps/key-symlink: a symlinked <key> dir -> rc 2"
  b4_has "rcps/key-symlink: the refusal names the symlink" "symlink"
  [ -e "$rc_root/elsewhere7/tally.v2" ] && fail "rcps/key-symlink: the tally was written THROUGH the link" || :

  # ---- (8)/(9) the read path refuses a v1-shaped or bad-row line, by line number ----------------
  rc_h8="$rc_root/h8"; rc_d8="$rc_h8/.local/state/sparkwright/runaway/$rc_key"; mkdir -p "$rc_d8"
  printf '1757900000 keyA ROW-A 1 0\n1757900000 keyA 100 1\n' > "$rc_d8/tally.v2"
  rcps_run "$rc_base" "$rc_h8" check
  b4_expect 2 "rcps/v1-shaped: a 4-field line in tally.v2 -> rc 2"
  b4_has "rcps/v1-shaped: the refusal names the LINE NUMBER" "line 2"
  printf '1757900000 keyA ROW-A 1 0\n' > "$rc_d8/tally.v2"
  rcps_run "$rc_base" "$rc_h8" check
  b4_expect 0 "rcps/v1-shaped: (anchor) a well-formed five-field line is ACCEPTED -> rc 0"
  rc_long=$(awk 'BEGIN{s="R"; for(i=0;i<64;i++) s=s "X"; print s}')   # 65 chars
  for rc_bad in 'row-a' '-ROW' 'ROW_A' "$rc_long"; do
    printf '1757900000 keyA %s 1 0\n' "$rc_bad" > "$rc_d8/tally.v2"
    rcps_run "$rc_base" "$rc_h8" check
    b4_expect 2 "rcps/bad-row: a row failing the grammar in the file ('$rc_bad') -> rc 2"
    b4_has "rcps/bad-row: the refusal names the LINE NUMBER" "line 1"
  done
  # F2: the write-side refusal, non-vacuously. The tally is ONE valid line whose cksum is taken first;
  # a step with a bad --row must be rc 2 with that line untouched AND the row-grammar message (so the
  # refusal is rg_row_ok's, not a later one). Mutant: delete the rg_row_ok call in `step` -> the row is
  # appended (cksum moves, rc 0) and this leg reds.
  printf '1757900000 keyA ROW-A 1 0\n' > "$rc_d8/tally.v2"
  rc_ck0=$(cksum < "$rc_d8/tally.v2")
  rcps_run "$rc_base" "$rc_h8" step --row 'row-a' --tokens 1 --agents 0
  b4_expect 2 "rcps/bad-row: a --row failing the grammar is refused at write -> rc 2"
  b4_has "rcps/bad-row: the write refusal is the row-grammar one" "which slice is this"
  [ "$(cksum < "$rc_d8/tally.v2")" = "$rc_ck0" ] || fail "rcps/bad-row: a refused step CHANGED the tally"

  # F1/A4: the locale legs. A bad row must be refused under a UTF-8 locale as under C, with the tally
  # byte-identical. Run under bash (a UTF-8 [A-Z] range is where a locale-dependent class misjudges).
  if locale -a 2>/dev/null | grep -qx 'en_US.UTF-8'; then
    printf '1757900000 keyA ROW-A 1 0\n' > "$rc_d8/tally.v2"; cp "$rc_d8/tally.v2" "$tmp/rc-lc0"
    for rc_lcrow in 'ROW-b' 'Abc' 'Aé'; do
      if b4_out=$( cd "$rc_base" && env -u KIT_RUNAWAY_SANDBOX HOME="$rc_h8" LC_ALL=en_US.UTF-8 bash "$b4_guard" step --row "$rc_lcrow" --tokens 1 --agents 0 2>&1 ); then b4_rc=0; else b4_rc=$?; fi
      b4_expect 2 "rcps/locale: --row '$rc_lcrow' under en_US.UTF-8 -> rc 2"
      cmp -s "$tmp/rc-lc0" "$rc_d8/tally.v2" || fail "rcps/locale: --row '$rc_lcrow' under en_US.UTF-8 CHANGED the tally"
    done
  else
    echo "SKIP rcps/locale: en_US.UTF-8 is not installed"
  fi

  # F3/A4: 7 and 007 are DIFFERENT rows. An awk numeric compare reads both strnums as 7 and sums them.
  # Mutant: `$3 != row` (no `""`) -> check --row 7 grades 007's amount too, and the rc flips.
  printf 'MAX_TOKENS=1000\nMAX_STEPS=0\nMAX_AGENTS=0\nWARN_PCT=0\n' > "$rc_sb/c7"
  rcps_chk() { if b4_out=$( cd "$rc_base" && env HOME="$rc_h8" KIT_RUNAWAY_SANDBOX="$rc_sb" sh "$b4_guard" check --config "$rc_sb/c7" "$@" 2>&1 ); then b4_rc=0; else b4_rc=$?; fi; }
  printf '1757900000 keyA 7 600 0\n1757900000 keyA 007 600 0\n' > "$rc_d8/tally.v2"
  rcps_chk --row 7;   b4_expect 0 "rcps/7-007: row 7 grades only its own 600 -> rc 0"
  rcps_chk --row 007; b4_expect 0 "rcps/7-007: row 007 grades only its own 600 -> rc 0"
  printf '1757900000 keyA 7 1000 0\n1757900000 keyA 007 1 0\n' > "$rc_d8/tally.v2"
  rcps_chk --row 7;   b4_expect 1 "rcps/7-007: row 7 at its own 1000/1000 -> rc 1"
  rcps_chk --row 007; b4_expect 0 "rcps/7-007: row 007 at 1 is NOT graded with 7's 1000 -> rc 0"

  # A4: de_DE parity — `check` under de_DE must equal `check` under C (rc and stdout).
  if locale -a 2>/dev/null | grep -qx 'de_DE.UTF-8'; then
    printf '1757900000 keyA ROW-A 600 0\n' > "$rc_d8/tally.v2"
    rc_crc=0; rc_c=$( cd "$rc_base" && env -u KIT_RUNAWAY_SANDBOX HOME="$rc_h8" LC_ALL=C sh "$b4_guard" check 2>&1 ) || rc_crc=$?
    rc_drc=0; rc_d=$( cd "$rc_base" && env -u KIT_RUNAWAY_SANDBOX HOME="$rc_h8" LC_ALL=de_DE.UTF-8 sh "$b4_guard" check 2>&1 ) || rc_drc=$?
    [ "$rc_crc" = "$rc_drc" ] && [ "$rc_c" = "$rc_d" ] || fail "rcps/de_DE: check differs between C (rc $rc_crc) and de_DE.UTF-8 (rc $rc_drc)"
  else
    echo "SKIP rcps/de_DE: de_DE.UTF-8 is not installed"
  fi

  # ---- (10) the oversize refusal says to archive and that it resets EVERY row of this repo --------
  awk 'BEGIN{for(i=0;i<100001;i++) print "1757900000 keyA ROW-A 1 0"}' > "$rc_d8/tally.v2"
  rcps_run "$rc_base" "$rc_h8" check
  b4_expect 2 "rcps/oversize: a tally.v2 past the cap -> rc 2"
  b4_has "rcps/oversize: the refusal names mv (archive, not delete)" "mv tally.v2 tally.v2."
  b4_has "rcps/oversize: the refusal says it resets every row" "every row"
  rcps_ver_legs
}

# rcps_ver_legs — RUNAWAY-CEILING-PER-SLICE T1b: the per-slice verbs. Fixtures are seeded repos; HOME is a
# temp dir; every verdict is judged by RC. rcps_fixture builds a repo that carries a COPY of the guard at
# scripts/runaway-guard.sh and a COMMITTED .kit/budget.conf (40 agents), so the conf resolves beside the
# guard and the unscoped-raise comparison has a HEAD to read.
rcps_fixture() {   # <dir>
  rcps_seed "$1" "fx-$(basename "$1")"
  mkdir -p "$1/scripts" "$1/.kit"
  cp "$b4_guard" "$1/scripts/runaway-guard.sh"
  printf 'MAX_TOKENS=1000000\nMAX_STEPS=0\nMAX_AGENTS=40\nWARN_PCT=80\nCOST_PER_1K_USD=0.003\n' > "$1/.kit/budget.conf"
  git -C "$1" add scripts .kit
  git -C "$1" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m "fixture guard + conf"
}
# rcps_fx <fixture> <home> <args...> — the fixture's own guard copy, the dial UNSET, its committed conf
rcps_fx() {
  _fd=$1; _fh=$2; shift 2
  if b4_out=$( cd "$_fd" && env -u KIT_RUNAWAY_SANDBOX HOME="$_fh" sh scripts/runaway-guard.sh "$@" 2>&1 ); then b4_rc=0; else b4_rc=$?; fi
}
# rcps_sbx <home> <conf> <args...> — the real guard, a SANDBOXED conf, run from the seeded base repo
rcps_sbx() {
  _sh=$1; _sc=$2; shift 2
  if b4_out=$( cd "$rc_base" && env HOME="$_sh" KIT_RUNAWAY_SANDBOX="$rc_sb" sh "$b4_guard" "$@" --config "$_sc" 2>&1 ); then b4_rc=0; else b4_rc=$?; fi
}
rcps_ver_legs() {
  rv_fx="$rc_root/fx"; rcps_fixture "$rv_fx"
  rv_h="$rc_root/hv1"; mkdir -p "$rv_h"

  # ---- (1) THE DEFECT'S NEGATIVE: a second slice's normal work is silent. Mutant: grade ALL rows (drop the
  # per-row `next` in the awk) -> S reads 40/40 and STOPs, so this leg reds.
  rcps_fx "$rv_fx" "$rv_h" step --row ROW-R --agents 39; b4_expect 0 "rcps/per-row: R at 39/40 agents -> rc 0"
  rcps_fx "$rv_fx" "$rv_h" step --row ROW-S --agents 1;  b4_expect 0 "rcps/per-row: S's +1 is NOT graded with R's 39 -> rc 0"
  [ "$b4_out" = "metered: ROW-S tokens(0/1000000) agents(1/40)" ] \
    || fail "rcps/per-row: S's stderr is not exactly its own metered line; out=[$b4_out]"

  # ---- (2) R's own +1 reaches 40 -> STOP naming R. Mutant: the message without the row -> no 'STOP: ROW-R runaway:'.
  rcps_fx "$rv_fx" "$rv_h" step --row ROW-R --agents 1;  b4_expect 1 "rcps/stop: R reaches 40/40 -> rc 1"
  b4_has "rcps/stop: the STOP names the row" "STOP: ROW-R runaway:"
  b4_has "rcps/stop: the metered line is printed on a STOP too" "metered: ROW-R tokens(0/1000000) agents(40/40)"

  # ---- (3) a new row starts at zero. Mutant: seeding a new row from another's total -> agents(1/40) reads wrong.
  rcps_fx "$rv_fx" "$rv_h" step --row ROW-T --tokens 5 --agents 1; b4_expect 0 "rcps/new-row: a new row -> rc 0"
  [ "$b4_out" = "metered: ROW-T tokens(5/1000000) agents(1/40)" ] || fail "rcps/new-row: T did not start at zero; out=[$b4_out]"

  # ---- (4) no env fallback: KIT_RUN_ROW exported, no --row -> rc 2, nothing written. Mutant: read KIT_RUN_ROW.
  rv_n0=$(wc -l < "$rv_h/.local/state/sparkwright/runaway/$(git -C "$rv_fx" rev-list --max-parents=0 --first-parent HEAD | tail -1)/tally.v2" | tr -d ' ')
  if b4_out=$( cd "$rv_fx" && env -u KIT_RUNAWAY_SANDBOX HOME="$rv_h" KIT_RUN_ROW=ROW-R sh scripts/runaway-guard.sh step --agents 1 2>&1 ); then b4_rc=0; else b4_rc=$?; fi
  b4_expect 2 "rcps/no-env: KIT_RUN_ROW exported and no --row -> rc 2"
  [ "$(wc -l < "$rv_h/.local/state/sparkwright/runaway/$(git -C "$rv_fx" rev-list --max-parents=0 --first-parent HEAD | tail -1)/tally.v2" | tr -d ' ')" = "$rv_n0" ] \
    || fail "rcps/no-env: a refused step wrote a line"

  # ---- (5) RAISE lifts ONE row. Mutants: ignore RAISE -> R at 45 STOPs; apply RAISE to every row -> S at 40 is rc 0.
  # M3: two RAISE lines for R BEFORE the base line — the last raise wins (80, not 50), and the `cfg` anchor
  # means a RAISE line never masquerades as the base MAX_AGENTS (which stays 40 for S).
  printf 'MAX_TOKENS=1000000\nMAX_STEPS=0\nRAISE ROW-R MAX_AGENTS=50\nRAISE ROW-R MAX_AGENTS=80\nMAX_AGENTS=40\nWARN_PCT=80\n' > "$rc_sb/c5"
  rv_h5="$rc_root/hv5"; mkdir -p "$rv_h5"
  rcps_sbx "$rv_h5" "$rc_sb/c5" step --row ROW-R --agents 45; b4_expect 0 "rcps/raise: R at 45 under RAISE MAX_AGENTS=80 -> rc 0"
  b4_has "rcps/raise: the metered line shows R's effective /80" "agents(45/80)"
  rcps_sbx "$rv_h5" "$rc_sb/c5" step --row ROW-S --agents 40; b4_expect 1 "rcps/raise: S at 40 from the SAME conf still STOPs -> rc 1"
  b4_has "rcps/raise: S's metered line shows the base /40" "agents(40/40)"

  # ---- (5b) SEC-4: RAISE accepts MAX_STEPS too, per row, last-wins. Mutant: refuse the key -> rc 2 (red today).
  # Two steps each reach the base MAX_STEPS=2 and STOP; the RAISE lifts ROW-R's step ceiling only.
  printf 'MAX_TOKENS=1000000\nMAX_STEPS=2\nMAX_AGENTS=0\nWARN_PCT=80\n' > "$rc_sb/c5b0"
  printf 'MAX_TOKENS=1000000\nMAX_STEPS=2\nRAISE ROW-R MAX_STEPS=3\nRAISE ROW-R MAX_STEPS=5\nMAX_AGENTS=0\nWARN_PCT=80\n' > "$rc_sb/c5b1"
  rv_h5b="$rc_root/hv5b"; mkdir -p "$rv_h5b"
  rcps_sbx "$rv_h5b" "$rc_sb/c5b0" step --row ROW-R --agents 0; b4_expect 0 "rcps/raise-steps: R's first step -> rc 0"
  rcps_sbx "$rv_h5b" "$rc_sb/c5b0" step --row ROW-R --agents 0; b4_expect 1 "rcps/raise-steps: R at the steps ceiling STOPs -> rc 1"
  rcps_sbx "$rv_h5b" "$rc_sb/c5b0" step --row ROW-S --agents 0; rcps_sbx "$rv_h5b" "$rc_sb/c5b0" step --row ROW-S --agents 0
  b4_expect 1 "rcps/raise-steps: S at the steps ceiling STOPs -> rc 1"
  rcps_sbx "$rv_h5b" "$rc_sb/c5b1" check --row ROW-R; b4_expect 0 "rcps/raise-steps: RAISE ROW-R MAX_STEPS lifts R (2 of 5) -> rc 0"
  rcps_sbx "$rv_h5b" "$rc_sb/c5b1" check --row ROW-S; b4_expect 1 "rcps/raise-steps: S from the SAME conf still STOPs -> rc 1"

  # ---- (6) a malformed RAISE -> rc 2 naming the line, nothing written. Mutant: skip validation -> rc 0.
  printf 'MAX_TOKENS=1000000\nMAX_STEPS=0\nMAX_AGENTS=40\nWARN_PCT=80\nRAISE r x\n' > "$rc_sb/c6"
  rv_h6="$rc_root/hv6"; mkdir -p "$rv_h6"
  rcps_sbx "$rv_h6" "$rc_sb/c6" step --row ROW-R --agents 1
  b4_expect 2 "rcps/raise-bad: 'RAISE r x' -> rc 2"
  b4_has "rcps/raise-bad: the refusal names the conf LINE NUMBER" "line 5"
  b4_hasnt "rcps/raise-bad: the refusal never echoes the bytes" "RAISE r x"
  [ -z "$(find "$rv_h6/.local/state/sparkwright/runaway" -name tally.v2 -size +0 2>/dev/null)" ] \
    || fail "rcps/raise-bad: a refused step wrote a line"
  for rv_rb in 'MAX_AGENTS=0' 'MAX_AGENTS=080'; do   # M1: zero and leading zeros are refused
    printf 'MAX_TOKENS=1000000\nMAX_STEPS=0\nMAX_AGENTS=40\nWARN_PCT=80\nRAISE ROW-R %s\n' "$rv_rb" > "$rc_sb/c6"
    rcps_sbx "$rv_h6" "$rc_sb/c6" step --row ROW-R --agents 1
    b4_expect 2 "rcps/raise-bad: 'RAISE ROW-R $rv_rb' -> rc 2"
    b4_has "rcps/raise-bad: '$rv_rb' names the conf LINE NUMBER" "line 5"
  done
  # F3: a GOOD RAISE line ahead of a bad one must not mask the refusal (the awk used to print the good record, then
  # `BAD n`, and the shell matched only when BAD was the FIRST line). Mutant: the old first-line match -> rc 0 here.
  printf 'MAX_TOKENS=1000000\nMAX_STEPS=0\nMAX_AGENTS=40\nWARN_PCT=80\nRAISE ROW-R MAX_STEPS=5\nRAISE r x\n' > "$rc_sb/c6g"
  rcps_sbx "$rv_h6" "$rc_sb/c6g" step --row ROW-R --agents 1
  b4_expect 2 "rcps/raise-bad-after-good: a good RAISE then 'RAISE r x' -> rc 2"
  b4_has "rcps/raise-bad-after-good: the refusal names the BAD line (6), not the good one" "line 6"
  # ...and a row literally named BAD is an ordinary row (the sentinel is `!BAD`, which can never start a row id).
  printf 'MAX_TOKENS=1000000\nMAX_STEPS=0\nMAX_AGENTS=40\nWARN_PCT=80\nRAISE BAD MAX_AGENTS=80\n' > "$rc_sb/c6h"
  rcps_sbx "$rv_h6" "$rc_sb/c6h" step --row BAD --agents 1
  b4_expect 0 "rcps/raise-row-BAD: a row named BAD with a valid RAISE -> rc 0"
  b4_has "rcps/raise-row-BAD: its effective ceiling is the raised /80" "agents(1/80)"
  # F6: the metered line shows steps only when MAX_STEPS > 0 (leg (1) pins the disabled form byte-for-byte).
  printf 'MAX_TOKENS=1000000\nMAX_STEPS=5\nMAX_AGENTS=40\nWARN_PCT=80\n' > "$rc_sb/c6s"
  rcps_sbx "$rv_h6" "$rc_sb/c6s" step --row ROW-STEPS --agents 0
  b4_expect 0 "rcps/steps-metered: MAX_STEPS=5, first step -> rc 0"
  b4_has "rcps/steps-metered: the metered line carries steps(1/5)" "agents(0/40) steps(1/5)"

  # ---- (7) the UNSCOPED-RAISE WARN. Negatives: the unedited conf is silent; a RAISE-only edit (bytes differ,
  # no base MAX_* differs) is silent. Mutant: warn on any byte difference -> the RAISE-only leg reds.
  rv_fx2="$rc_root/fx2"; rcps_fixture "$rv_fx2"; rv_h7="$rc_root/hv7"; mkdir -p "$rv_h7"
  rcps_fx "$rv_fx2" "$rv_h7" step --row ROW-U --agents 1; b4_expect 0 "rcps/unscoped: the unedited conf -> rc 0"
  b4_hasnt "rcps/unscoped: an unedited conf does not WARN" "unscoped raise"
  b4_hasnt "rcps/unscoped: a committed conf is not 'no committed copy'" "no committed copy"
  printf 'RAISE ROW-U MAX_AGENTS=80\n' >> "$rv_fx2/.kit/budget.conf"
  rcps_fx "$rv_fx2" "$rv_h7" step --row ROW-U --agents 1; b4_expect 0 "rcps/unscoped: a RAISE-only edit -> rc 0"
  b4_hasnt "rcps/unscoped: a RAISE-only edit is scoped, so it does not WARN" "unscoped raise"
  git -C "$rv_fx2" show HEAD:.kit/budget.conf | awk '/^MAX_AGENTS=/{print "MAX_AGENTS=80"; next} {print}' > "$rv_fx2/.kit/budget.conf"
  rcps_fx "$rv_fx2" "$rv_h7" step --row ROW-U --agents 1; b4_expect 0 "rcps/unscoped: an edited base MAX_AGENTS -> rc 0 (the rc is unchanged)"
  b4_has "rcps/unscoped: the edited base WARNs" "WARN: unscoped raise: MAX_AGENTS=80 (HEAD: 40)"
  b4_has "rcps/unscoped: the WARN names the row being charged" "(charging ROW-U)"
  b4_hasnt "rcps/unscoped: M7 the WARN prints the RESOLVED conf path, not the ../ spelling" "/../"
  b4_has "rcps/unscoped: M7 the WARN names the conf's resolved path" "$(cd -P "$rv_fx2/.kit" && pwd)/budget.conf"
  rcps_fx "$rv_fx2" "$rv_h7" check; b4_expect 0 "rcps/unscoped: check -> rc 0"
  b4_has "rcps/unscoped: check WARNs too" "WARN: unscoped raise: MAX_AGENTS=80"

  # ---- (8) a sandboxed conf has no committed copy: one note, rc 0. Mutant: fail the step -> rc != 0.
  printf 'MAX_TOKENS=1000000\nMAX_STEPS=0\nMAX_AGENTS=40\nWARN_PCT=80\n' > "$rc_sb/c8"
  rv_h8="$rc_root/hv8"; mkdir -p "$rv_h8"
  rcps_sbx "$rv_h8" "$rc_sb/c8" step --row ROW-R --agents 1; b4_expect 0 "rcps/no-copy: a sandboxed conf -> rc 0"
  b4_has "rcps/no-copy: the note is printed" "(no committed copy)"

  # ---- (9) check: one ls-remote, exact ref names. Rows A, B, C metered; the remote carries refs/claims/ROW-A,
  # refs/claims-log/ROW-B and refs/claims/ROW-C-OLD (a SUBSTRING trap). Only C is flagged. Mutant: substring
  # matching -> ROW-C-OLD vouches for C and the flag vanishes.
  rv_bare="$rc_root/claims.git"; git init -q --bare "$rv_bare" 2>/dev/null
  git -C "$rc_base" push -q "$rv_bare" HEAD:refs/claims/ROW-A HEAD:refs/claims-log/ROW-B HEAD:refs/claims/ROW-C-OLD 2>/dev/null
  rv_h9="$rc_root/hv9"; mkdir -p "$rv_h9"
  for rv_r in ROW-A ROW-B ROW-C; do rcps_fx "$rv_fx" "$rv_h9" step --row "$rv_r" --agents 1; done
  if b4_out=$( cd "$rv_fx" && env -u KIT_RUNAWAY_SANDBOX HOME="$rv_h9" BOARD_CLAIM_REMOTE="$rv_bare" sh scripts/runaway-guard.sh check 2>&1 ); then b4_rc=0; else b4_rc=$?; fi
  b4_expect 0 "rcps/check: three rows under the ceiling -> rc 0"
  b4_has "rcps/check: the listing shows every row" "ROW-A tokens=0 agents=1"
  b4_has "rcps/check: C is flagged" "never claimed: ROW-C"
  b4_hasnt "rcps/check: a refs/claims/ row is not flagged" "never claimed: ROW-A"
  b4_hasnt "rcps/check: a refs/claims-log/ row is not flagged" "never claimed: ROW-B"
  b4_hasnt "rcps/check: a reachable remote is not UNVERIFIED" "UNVERIFIED"
  [ "$(printf '%s\n' "$b4_out" | grep -c '^never claimed:')" = 1 ] || fail "rcps/check: not exactly one row flagged; out=[$b4_out]"
  rcps_fx "$rv_fx" "$rv_h9" step --row ROW-X --agents 40   # ROW-X reaches its ceiling
  if b4_out=$( cd "$rv_fx" && env -u KIT_RUNAWAY_SANDBOX HOME="$rv_h9" BOARD_CLAIM_REMOTE="$rc_root/no-such-remote" sh scripts/runaway-guard.sh check 2>&1 ); then b4_rc=0; else b4_rc=$?; fi
  b4_expect 1 "rcps/check: an unreachable remote does not change the grading rc (ROW-X at 40/40) -> rc 1"
  b4_has "rcps/check: unreachable is reported" "claims UNVERIFIED"
  b4_has "rcps/check: the row at its ceiling is listed STOP" "ROW-X tokens=0 agents=40 STOP"

  # ---- (9b) CI fix 2 M-1: the listing-mode poison sentinel must not collide with a row id. A row may be NAMED
  # `BAD`; the sums awk once printed a bare `BAD <n>` on a poisoned line and the shell matched `BAD *`, so the
  # listing line `BAD 0 1 1` of a legitimate row read as poison (rc 2 "Remove the file"). The sentinel is `!BAD`
  # (a `!` can never start a row id). Positive: rows AAA/BAD/ZZZ list rc 0. Negative: a real poisoned line still rc 2.
  rv_h9b="$rc_root/hv9b"; mkdir -p "$rv_h9b"
  for rv_r in AAA BAD ZZZ; do rcps_fx "$rv_fx" "$rv_h9b" step --row "$rv_r" --agents 1; done
  if b4_out=$( cd "$rv_fx" && env -u KIT_RUNAWAY_SANDBOX HOME="$rv_h9b" BOARD_CLAIM_REMOTE="$rc_root/no-such-remote" sh scripts/runaway-guard.sh check 2>&1 ); then b4_rc=0; else b4_rc=$?; fi
  b4_expect 0 "rcps/bad-row: a row NAMED BAD is a row, not a poison sentinel -> rc 0"
  [ "$(printf '%s\n' "$b4_out" | grep -c ' tokens=')" = 3 ] || fail "rcps/bad-row: not exactly three tokens= listing lines; out=[$b4_out]"
  b4_hasnt "rcps/bad-row: the listing is not refused as poisoned" "poisoned"
  rv_tb="$rv_h9b/.local/state/sparkwright/runaway/$(git -C "$rv_fx" rev-list --max-parents=0 --first-parent HEAD | tail -1)/tally.v2"
  printf 'garbage line\n' >> "$rv_tb"
  if b4_out=$( cd "$rv_fx" && env -u KIT_RUNAWAY_SANDBOX HOME="$rv_h9b" BOARD_CLAIM_REMOTE="$rc_root/no-such-remote" sh scripts/runaway-guard.sh check 2>&1 ); then b4_rc=0; else b4_rc=$?; fi
  b4_expect 2 "rcps/bad-row: a real poisoned line (listing mode) still -> rc 2"
  b4_has "rcps/bad-row: the refusal names the LINE NUMBER, then a space" "line 4 (it"
  b4_has "rcps/bad-row: the poison refusal says to archive (mv, not delete)" "mv tally.v2 tally.v2."
  b4_has "rcps/bad-row: the poison refusal says it resets every row" "every row"
  rv_pn0=$(wc -l < "$rv_tb" | tr -d ' ')
  if b4_out=$( cd "$rv_fx" && env -u KIT_RUNAWAY_SANDBOX HOME="$rv_h9b" BOARD_CLAIM_REMOTE="$rc_root/no-such-remote" sh scripts/runaway-guard.sh step --row BAD --agents 1 2>&1 ); then b4_rc=0; else b4_rc=$?; fi
  b4_expect 2 "rcps/bad-row: a real poisoned line (row mode) still -> rc 2"
  b4_has "rcps/bad-row: the row-mode refusal names the LINE NUMBER" "line 4"
  [ "$(wc -l < "$rv_tb" | tr -d ' ')" = "$rv_pn0" ] || fail "rcps/bad-row: a refused step (row mode) wrote a line"

  # ---- (10) reset is retired: rc 2, the exact text, the tally byte-identical. Mutant: the old reset -> rc 0.
  rv_tf="$rv_h9/.local/state/sparkwright/runaway/$(git -C "$rv_fx" rev-list --max-parents=0 --first-parent HEAD | tail -1)/tally.v2"
  cp "$rv_tf" "$tmp/rv-tally0"
  rcps_fx "$rv_fx" "$rv_h9" reset; b4_expect 2 "rcps/reset: reset is retired -> rc 2"
  [ "$b4_out" = "runaway-guard: reset is retired — the budget is per slice (row); a new row starts at zero and there is nothing to reset. See docs/operations/runaway-killswitch.md." ] \
    || fail "rcps/reset: the retired text is not exact; out=[$b4_out]"
  cmp -s "$tmp/rv-tally0" "$rv_tf" || fail "rcps/reset: the tally changed"

  # ---- (11) I1: the claims read is BOUNDED. The remote is ssh://x/y and GIT_SSH_COMMAND is a stub that sleeps 30,
  # so an unbounded ls-remote hangs. RG_CLAIMS_TIMEOUT=2 must return `claims UNVERIFIED` inside 10s with the
  # grading rc (ROW-X at 40/40 -> 1) untouched. The leg's OWN wait is bounded (15s), so a failure is REPORTED, not hung.
  printf '#!/bin/sh\nexec sleep 30\n' > "$tmp/ssh-hang"; chmod +x "$tmp/ssh-hang"
  rv_t0=$(date +%s)
  ( cd "$rv_fx" && env -u KIT_RUNAWAY_SANDBOX HOME="$rv_h9" BOARD_CLAIM_REMOTE="ssh://x/y" GIT_SSH_COMMAND="$tmp/ssh-hang" RG_CLAIMS_TIMEOUT=2 \
      sh scripts/runaway-guard.sh check ) > "$tmp/hang-out" 2>&1 &
  rv_pid=$!
  ( sleep 15; kill -9 "$rv_pid" 2>/dev/null ) > /dev/null 2>&1 &   # -9: a TERM trap is deferred until its foreground child ends
  rv_wd=$!
  if wait "$rv_pid"; then b4_rc=0; else b4_rc=$?; fi
  kill "$rv_wd" 2>/dev/null || :; wait "$rv_wd" 2>/dev/null || :   # reap it quietly (bash prints "Terminated" otherwise)
  rv_el=$(( $(date +%s) - rv_t0 ))
  b4_out=$(cat "$tmp/hang-out")
  [ "$rv_el" -lt 10 ] || fail "rcps/hang: check took ${rv_el}s against a hanging remote (want < 10s, RG_CLAIMS_TIMEOUT=2); rc $b4_rc; out=[$b4_out]"
  b4_expect 1 "rcps/hang: a hanging remote does not change the grading rc (ROW-X at 40/40) -> rc 1"
  b4_has "rcps/hang: the timeout is reported" "claims UNVERIFIED"

  # ---- (12) M5: an EMPTY tally makes NO network read — no `claims` line at all, even for an unreachable remote.
  rv_h12="$rc_root/hv12"; mkdir -p "$rv_h12"
  if b4_out=$( cd "$rv_fx" && env -u KIT_RUNAWAY_SANDBOX HOME="$rv_h12" BOARD_CLAIM_REMOTE="$rc_root/no-such-remote" sh scripts/runaway-guard.sh check 2>&1 ); then b4_rc=0; else b4_rc=$?; fi
  b4_expect 0 "rcps/empty: an empty tally -> rc 0"
  b4_hasnt "rcps/empty: an empty tally reads no remote, so prints no claims line" "claims"
}

# rcps_awk_names_leg — CI fix 1 (PR #715): macOS awk accepts `RT` as an array name but gawk (CI's awk)
# reserves it (the record terminator) and aborts "attempt to use scalar 'RT' as an array". The class: no
# awk program in the guard may use a gawk-reserved name as an identifier. A whole-word scan of the
# non-comment lines is enough (the guard has no legitimate use of these words); the guard's awk programs
# are inline, so a scan of the file covers them.
#
# CI fix 3 (the CLASS, and the whole class): the scan is TWO scans over BOTH awk-carrying scripts (the guard and
# its twin orchestrator-run.sh), in rcps_awk_names_scan: lines are numbered BEFORE filtering (a FAIL cites the
# real file line), whole-line comments are dropped, and a trailing ` # ...` comment is stripped when the line has
# no quote before that `#` (an APPROXIMATION: a `#` inside a quoted string is kept, a comment after a quote is
# not stripped; both err toward scanning more text, never less).
#  (1) UPPERCASE specials (RT FPAT IGNORECASE PROCINFO ARGIND ERRNO BINMODE LINT TEXTDOMAIN FIELDWIDTHS SYMTAB
#      FUNCTAB PREC ROUNDMODE): whole-word, ANY use (`for (r in RT)`, `split($0, RT, ":")`, `delete RT`,
#      `x = RT[1]`) - gawk aborts on every one, and the guard has no legitimate use of these words.
#  (2) lowercase gawk builtins (and or xor compl lshift rshift strtonum gensub systime strftime mktime asort
#      asorti patsplit isarray typeof fflush): the plain words are all over shell prose, so only IDENTIFIER
#      USE matches - glued `[`/`++`/`--`, the spaces-allowed `=`-family, pre-increment, `getline|delete NAME`,
#      `function NAME(`, `in NAME)`, and NAME as an array argument of split/patsplit/sub/gsub/match/asort/asorti.
#      A bare CALL such as `fflush()` is deliberately not pinned: calling a builtin is only wrong for mawk/BSD
#      awk, and the failure this leg exists for is a gawk-RESERVED name reused as a variable.
# CI exercises gawk; PREPUSH-AWK-MATRIX (a boarded follow-up) will add a local gawk/mawk run.
# rcps_awk_names_scan <file> — prints the hits (`<line>:<text>`), nothing when clean.
rcps_awk_names_scan() {
  _rs_up='RT|FPAT|IGNORECASE|PROCINFO|ARGIND|ERRNO|BINMODE|LINT|TEXTDOMAIN|FIELDWIDTHS|SYMTAB|FUNCTAB|PREC|ROUNDMODE'
  _rs_lo='and|or|xor|compl|lshift|rshift|strtonum|gensub|systime|strftime|mktime|asort|asorti|patsplit|isarray|typeof|fflush'
  _rs_pre='(^|[^A-Za-z0-9_$-])'
  _rs_end='([^A-Za-z0-9_]|$)'
  _rs_use="${_rs_pre}(${_rs_lo})(\\[|\\+\\+|--)"
  _rs_use="${_rs_use}|${_rs_pre}(${_rs_lo})[[:space:]]*(=([^=]|\$)|\\+=|-=|\\*=|/=|%=|\\^=|\\*\\*=)"
  _rs_use="${_rs_use}|(\\+\\+|--)(${_rs_lo})${_rs_end}"
  _rs_use="${_rs_use}|(getline|delete)[[:space:]]+(${_rs_lo})${_rs_end}"
  _rs_use="${_rs_use}|function[[:space:]]+(${_rs_lo})[[:space:]]*\\("
  _rs_use="${_rs_use}|in[[:space:]]+(${_rs_lo})[[:space:]]*\\)"
  _rs_use="${_rs_use}|(split|patsplit|sub|gsub|match|asort|asorti)\\([^)]*,[[:space:]]*(${_rs_lo})[[:space:]]*[,)]"
  grep -n '' "$1" | grep -vE '^[0-9]+:[[:space:]]*#' \
    | sed -e "s/^\\([0-9]*:[^\"']*\\) #.*/\\1/" > "$_rs_tmp"
  grep -wE "$_rs_up" "$_rs_tmp" || :
  grep -E "$_rs_use" "$_rs_tmp" || :
}
rcps_awk_names_leg() {
  _rs_tmp="$tmp/awk-names-scan"
  # Permanent selftest cases (never a silent regression to instance-only): a fixture using RT as a split() array
  # target, a for-in variable and a delete target must each be found; prose and calls must not.
  printf '%s\n' 'n = split($0, RT, ":")' > "$tmp/awk-fx-split"
  printf '%s\n' 'for (r in RT) x++' > "$tmp/awk-fx-forin"
  printf '%s\n' 'delete PROCINFO' 'or[1]=1' 'function and(a)' 'getline xor' > "$tmp/awk-fx-more"
  for _rg_fx in awk-fx-split awk-fx-forin; do
    [ -n "$(rcps_awk_names_scan "$tmp/$_rg_fx")" ] || { printf 'FAIL: rcps/awk-reserved: the scan is blind to its fixture %s (class regressed to instance-only)\n' "$_rg_fx" >&2; exit 1; }
  done
  [ "$(rcps_awk_names_scan "$tmp/awk-fx-more" | wc -l | tr -d ' ')" = 4 ] \
    || { printf 'FAIL: rcps/awk-reserved: the scan missed a lowercase/uppercase fixture line\n' >&2; exit 1; }
  printf '%s\n' 'echo "use --row and --agents"' 'echo "a and/or [b]"' 'x=1 # retry or [skip]' 'fflush()' > "$tmp/awk-fx-clean"
  [ -z "$(rcps_awk_names_scan "$tmp/awk-fx-clean")" ] || { printf 'FAIL: rcps/awk-reserved: the scan false-reds on prose/calls\n' >&2; exit 1; }
  for _rg_f in "$GUARD" "$(dirname "$GUARD")/orchestrator-run.sh"; do
    [ -f "$_rg_f" ] || { printf 'FAIL: rcps/awk-reserved: cannot find %s to scan\n' "$_rg_f" >&2; exit 1; }
    _rg_hits=$(rcps_awk_names_scan "$_rg_f")
    [ -z "$_rg_hits" ] || { printf 'FAIL: rcps/awk-reserved: %s uses a gawk-reserved name (gawk aborts, macOS awk does not):\n%s\n' "$_rg_f" "$_rg_hits" >&2; exit 1; }
  done
}

# ── T2: the invoking user's REAL state must be byte-identical across the selftest ───────────────────
# rcps_home_snap <home> — a sorted listing of <home>/.local/state/sparkwright/runaway with the cksum of every
# file, or the single line `absent`. Read-only. rcps_home_begin is called FIRST in selftest(), before any
# leg overrides HOME; rcps_home_end is its last act. A difference is rc 1 and prints the differing entries.
#
# TOLERANT BACKSTOP (the real user may run a live session while this selftest runs): the lock machinery
# (`*/lock`, `*/lock/*`, `*/lock.rel.*` and its subtree, `*/lock.tok.*`, `*/pid.dead.*`) is excluded; each pre-existing file
# records its size S0 and cksum, and at the end its FIRST S0 bytes must still cksum the same (an append is
# allowed, a rewrite or truncation is not); a NEW file or dir, and a deletion, are flagged. The STRICT check
# is the sentinel HOME (rcps_sentinel_end), which nothing may touch at all.
rcps_home_snap() {
  _hd="${1:-}/.local/state/sparkwright/runaway"
  if [ -z "${1:-}" ] || [ ! -d "$_hd" ]; then echo absent; return 0; fi
  ( cd "$_hd" && find . ! -path '*/lock' ! -path '*/lock/*' ! -path '*/lock.rel.*' ! -path '*/lock.tok.*' ! -path '*/pid.dead.*' \
      | LC_ALL=C sort | while IFS= read -r _hp; do
      if [ -f "$_hp" ]; then printf 'F\t%s\t%s\t%s\n' "$_hp" "$(wc -c < "$_hp" | tr -d ' ')" "$(cksum < "$_hp")"
      else printf 'D\t%s\n' "$_hp"; fi
    done )
}
rcps_home_begin() { rcps_home0=${HOME:-}; rcps_snap0=$(rcps_home_snap "$rcps_home0"); }
# rcps_home_diff — prints one line per violation (nothing when the real state is intact).
rcps_home_diff() {
  printf '%s\n' "$rcps_snap0" | awk -F'\t' '{print $2}' | LC_ALL=C sort > "$tmp/home-paths0"
  printf '%s\n' "$rcps_snap1" | awk -F'\t' '{print $2}' | LC_ALL=C sort > "$tmp/home-paths1"
  diff "$tmp/home-paths0" "$tmp/home-paths1" | grep '^[<>]' | sed 's/^</DELETED/; s/^>/NEW/' || :
  printf '%s\n' "$rcps_snap0" | while IFS='	' read -r _k _p _s _c; do
    [ "$_k" = F ] || continue
    [ -f "$rcps_home0/.local/state/sparkwright/runaway/$_p" ] || continue
    [ "$(head -c "$_s" "$rcps_home0/.local/state/sparkwright/runaway/$_p" | cksum)" = "$_c" ] || printf 'REWRITTEN %s\n' "$_p"
  done
}
rcps_home_end() {
  rcps_snap1=$(rcps_home_snap "$rcps_home0")
  rcps_hd=$(rcps_home_diff)
  [ -n "$rcps_hd" ] || return 0
  printf 'FAIL: rcps/real-home: the selftest CHANGED the invoking user'"'"'s real %s/.local/state/sparkwright/runaway (appends and lock files are tolerated):\n%s\n' \
    "$rcps_home0" "$rcps_hd" >&2
  exit 1
}
# rcps_sentinel_end — the STRICT check: the sentinel HOME (the ambient $HOME during every leg) is untouched.
rcps_sentinel_end() {
  [ ! -e "$tmp/sentinel-home/.local/state/sparkwright" ] \
    || fail "rcps/sentinel-home: a leg wrote state under the ambient \$HOME ($tmp/sentinel-home/.local/state/sparkwright) — it forgot to pin its own HOME"
}

# ── T2: the lock family's STAGED windows, the watchdog hygiene, and the sleeper legs ───────────────
# The race windows of rg_lock cannot be held still from outside, so a `date` SHIM on PATH (an external
# command, NOT a seam in the guard) acts ONCE at the exact moment the guard reads the clock inside each
# window, deterministically. THREE staging points:
#   - the T-window: the take arm has just mkdir'd the lock and is about to write its side token (`$(date)`
#     sits in that printf). P (the lock dir) is pid-less and holds no `pid.dead.*`.
#   - the B-window: the break arm has judged a dead token and is evaluating the age gate. P has a token.
#   - the K-window: the break arm has renamed the dead token aside and is writing its takeover token. P is
#     pid-less and holds `pid.dead.<pid>`.
# An `ln` shim fails the publish once (a lost take).
# THE PROTOCOL UNDER TEST (security ruling, T2 fix round 1a): the dir at the lock path is never renamed,
# moved or restored by anyone; only the token FILE moves (`ln` publishes it, `mv` breaks it, `ln` puts it back).
rcps_t2_legs() {
  t2_root="$tmp/t2"; mkdir -p "$t2_root/shim" "$t2_root/lnshim" "$t2_root/tmp"
  cat > "$t2_root/shim/date" <<'EOF'
#!/bin/sh
if [ -n "${RG_SHIM_LOCK:-}" ] && [ ! -e "$RG_SHIM_FLAG" ] && [ -d "$RG_SHIM_LOCK" ]; then
  case "${RG_SHIM_MODE:-}" in
    take)   # T-window: P is pid-less. Rename it away; optionally a foreign holder mkdirs the slot with a token.
      if [ ! -e "$RG_SHIM_LOCK/pid" ]; then
        : > "$RG_SHIM_FLAG"; mv "$RG_SHIM_LOCK" "$RG_SHIM_LOCK.stolen"
        if [ -n "${RG_SHIM_TOKEN:-}" ]; then mkdir "$RG_SHIM_LOCK"; printf '%s\n' "$RG_SHIM_TOKEN" > "$RG_SHIM_LOCK/pid"; fi
      fi ;;
    swap)   # B-window: P holds a token. Replace it (ABA: the judged holder released and another took the slot).
      if [ -f "$RG_SHIM_LOCK/pid" ]; then
        : > "$RG_SHIM_FLAG"; printf '%s\n' "$RG_SHIM_TOKEN" > "$RG_SHIM_LOCK/pid.swap"; mv -f "$RG_SHIM_LOCK/pid.swap" "$RG_SHIM_LOCK/pid"
      fi ;;
    kwin)   # K-window: the flag is written ONLY if the slot is a dir with no pid but a renamed-aside dead token.
      if [ ! -e "$RG_SHIM_LOCK/pid" ] && ls "$RG_SHIM_LOCK"/pid.dead.* >/dev/null 2>&1; then : > "$RG_SHIM_FLAG"; fi ;;
    kfail)  # K-window, and the takeover's SIDE-FILE WRITE is made to fail: the breaker's own pid is the one suffix on
            # the moved-aside token (pid.dead.<pid>), so pre-create lock.tok.<pid> and the guard's `set -C` write hits it.
      if [ ! -e "$RG_SHIM_LOCK/pid" ] && ls "$RG_SHIM_LOCK"/pid.dead.* >/dev/null 2>&1; then
        for _f in "$RG_SHIM_LOCK"/pid.dead.*; do _g=${_f##*.}; done
        : > "$RG_SHIM_FLAG"; : > "$RG_SHIM_LOCK.tok.$_g"
      fi ;;
  esac
fi
for _d in /bin/date /usr/bin/date; do [ -x "$_d" ] && exec "$_d" "$@"; done
exit 127
EOF
  cat > "$t2_root/lnshim/ln" <<'EOF'
#!/bin/sh
[ -z "${RG_LN_LOG:-}" ] || echo "$*" >> "$RG_LN_LOG"
if [ -n "${RG_LN_FLAG:-}" ] && [ ! -e "$RG_LN_FLAG" ]; then : > "$RG_LN_FLAG"; exit 1; fi
exec "$RG_REAL_LN" "$@"
EOF
  # the rm shim (A9): inert unless RG_RM_FLAG is set; then it records, for every `rm -rf`, whether the lock
  # path still exists at that moment. An unlock that deletes in place logs EXISTS; one that moved away first logs GONE.
  mkdir -p "$t2_root/rmshim"
  cat > "$t2_root/rmshim/rm" <<'EOF'
#!/bin/sh
if [ -n "${RG_RM_FLAG:-}" ] && [ "${1:-}" = "-rf" ]; then
  if [ -e "$RG_SHIM_LOCK" ]; then echo EXISTS >> "$RG_RM_FLAG"; else echo GONE >> "$RG_RM_FLAG"; fi
fi
# the TERM-during-release mode (N1): on the FIRST `rm -rf .../lock.rel.<pid>` it stages a FOREIGN live lock at the lock
# path, TERMs its parent (the guard), and dawdles so the guard's TERM trap runs the release AGAIN while HELD is still set.
if [ -n "${RG_RM_TERM_FLAG:-}" ] && [ ! -e "$RG_RM_TERM_FLAG" ] && [ "${1:-}" = "-rf" ]; then
  case "${2:-}" in
    */lock.rel.*)
      : > "$RG_RM_TERM_FLAG"
      mkdir "$RG_SHIM_LOCK"; printf '%s\n' "$RG_RM_FOREIGN" > "$RG_SHIM_LOCK/pid"
      kill -TERM "$PPID"; sleep 0.5 ;;
  esac
fi
for _d in /bin/rm /usr/bin/rm; do [ -x "$_d" ] && exec "$_d" "$@"; done
exit 127
EOF
  chmod +x "$t2_root/shim/date" "$t2_root/lnshim/ln" "$t2_root/rmshim/rm"
  t2_realln=$(command -v ln)   # resolved BEFORE the PATH override
  t2_lock="$b4_sand/lock"; t2_flag="$t2_root/fired"; t2_lnflag=""; t2_mode=""; t2_tok=""; t2_shimlock="$t2_lock"; t2_rmflag=""; t2_orphan=""; t2_rmterm=""; t2_rmforeign=""; t2_lnlog=""
  b4_mkcfg 0 0 0 0
  rcps_lk_legs

  # ---- (T2-3) N1: a bare `check` with rows returns and leaves NO sleeper behind. 3791 is a value nothing
  # else uses, so `sleep 3791` is THIS check's sleeper. The remote is the (fast-failing) hermetic one, which
  # is the common case: git returns in milliseconds and the watchdog must not outlive it.
  printf '1757900000 keyA ROW-T 1 0\n' > "$b4_tally"
  RG_CLAIMS_TIMEOUT=3791; export RG_CLAIMS_TIMEOUT
  b4_run_in "$tmp/repoA" check
  unset RG_CLAIMS_TIMEOUT
  b4_expect 0 "rcps/no-sleeper: a bare check with rows -> rc 0"
  b4_has "rcps/no-sleeper: the claims read ran (fast-failing remote)" "claims UNVERIFIED"
  t2_sleepers 3791
  # shellcheck disable=SC2086
  [ -z "$t2_sl" ] || { kill $t2_sl 2>/dev/null || :; fail "rcps/no-sleeper: a 'sleep 3791' from a FINISHED check survived (pid $t2_sl)"; }

  # ---- (T2-4) N2: a check interrupted with TERM while its claims read hangs leaves no temp file and no
  # armed sleeper, and is still rc 2. TMPDIR is private to the leg so a leftover file is countable.
  printf '#!/bin/sh\nexec sleep 3793\n' > "$t2_root/ssh-hang"; chmod +x "$t2_root/ssh-hang"
  ( cd "$tmp/repoA" && exec env HOME="$tmp/hsafe" KIT_RUNAWAY_SANDBOX="$b4_sand" TMPDIR="$t2_root/tmp" \
      BOARD_CLAIM_REMOTE="ssh://x/y" GIT_SSH_COMMAND="$t2_root/ssh-hang" RG_CLAIMS_TIMEOUT=3792 \
      sh "$b4_guard" check --config "$b4_cfg" --tally "$b4_tally" >/dev/null 2>&1 ) &
  t2_pid=$!
  t2_i=0
  while [ "$t2_i" -lt 100 ] && [ "$(ls -d "$t2_root/tmp"/rg-claims.* 2>/dev/null | wc -l | tr -d ' ')" = 0 ]; do sleep 0.1; t2_i=$((t2_i + 1)); done
  [ "$t2_i" -lt 100 ] || { kill -9 "$t2_pid" 2>/dev/null || :; fail "rcps/interrupted: the claims read never started (leg is vacuous)"; }
  sleep 0.3   # the sleeper is armed a hair after the temp file exists
  kill -TERM "$t2_pid" 2>/dev/null || :
  if wait "$t2_pid"; then t2_rc=0; else t2_rc=$?; fi
  t2_sleepers 3792; t2_sl92=$t2_sl
  # shellcheck disable=SC2086
  [ -z "$t2_sl92" ] || kill $t2_sl92 2>/dev/null || :
  # the hanging remote stub's own `sleep 3793` (#6) is reaped HERE, by its unique argument; git may start the stub after the TERM (seen under load), so reap until quiet (bounded ~3s)
  t2_rp=0
  while [ "$t2_rp" -lt 30 ]; do
    if pkill -f 'sleep 3793' 2>/dev/null; then :; else t2_pk=$?; [ "$t2_pk" = 1 ] || fail "rcps/interrupted: pkill failed (rc $t2_pk)"; fi
    if ! pgrep -f 'sleep 3793' >/dev/null 2>&1 && [ "$t2_rp" -ge 10 ]; then break; fi
    sleep 0.1
    t2_rp=$((t2_rp + 1))
  done
  t2_sleepers 3793
  [ -z "$t2_sl" ] || fail "rcps/interrupted: the hanging remote stub's 'sleep 3793' survived its reaping (pid $t2_sl)"
  [ "$t2_rc" = 2 ] || fail "rcps/interrupted: a TERMed check exited $t2_rc, not 2 (UNVERIFIED)"
  [ "$(ls -d "$t2_root/tmp"/rg-* 2>/dev/null | wc -l | tr -d ' ')" = 0 ] \
    || fail "rcps/interrupted: a temp file survived the TERMed check: $(ls "$t2_root/tmp")"
  [ -z "$t2_sl92" ] || fail "rcps/interrupted: the TERMed check left its 'sleep 3792' armed"
}

# rmlg_meter_legs — RUNAWAY-METERING-LANDING-GATE T1: the read-only `meter --row ROW` verb. rc 0 metered
# under its ceiling | 1 metered AND at/past it | 3 never metered (no line for the row, or no tally) | 2 every
# refusal `check` has, plus an unreadable tally. Every leg pins its own HOME under $tmp (the dial UNSET),
# runs in a seeded fixture that carries a copy of the guard + a committed conf (1000000 tokens, 40 agents),
# and judges by RC plus the EXACT stdout line. stderr is captured apart, so a WARN never blurs the line.
rmlg_mt() {   # <dir> <home> <args...> -> mt_rc, mt_out (stdout), mt_err (stderr)
  _md=$1; _mh=$2; shift 2
  if mt_out=$( cd "$_md" && env -u KIT_RUNAWAY_SANDBOX HOME="$_mh" sh scripts/runaway-guard.sh meter "$@" 2>"$tmp/rmlg-err" ); then mt_rc=0; else mt_rc=$?; fi
  mt_err=$(cat "$tmp/rmlg-err")
}
rmlg_expect() { [ "$mt_rc" = "$1" ] || fail "$2 (want rc $1, got $mt_rc); out=[$mt_out] err=[$mt_err]"; }
rmlg_line() { [ "$mt_out" = "$1" ] || fail "$2 (stdout is not exactly the line); want=[$1] got=[$mt_out]"; }
rmlg_meter_legs() {
  ml_root="$tmp/rmlg"; mkdir -p "$ml_root"
  ml_fx="$ml_root/fx"; rcps_fixture "$ml_fx"
  ml_key=$(git -C "$ml_fx" rev-list --max-parents=0 --first-parent HEAD | tail -1)
  ml_h="$ml_root/h"; ml_d="$ml_h/.local/state/sparkwright/runaway/$ml_key"; ml_t="$ml_d/tally.v2"
  mkdir -p "$ml_d"

  # ---- metered, under its ceiling: rc 0 and the exact line; ANOTHER row's spend is not summed in ------
  printf '1757900000 keyA ROW-M 100 2\n1757900001 keyB ROW-M 50 1\n1757900002 keyA ROW-O 999 9\n' > "$ml_t"
  rmlg_mt "$ml_fx" "$ml_h" --row ROW-M
  rmlg_expect 0 "rmlg/metered: a row with two lines under its ceiling"
  rmlg_line "metered: ROW-M tokens(150/1000000) agents(3/40) lines=2" "rmlg/metered"

  # ---- breached: rc 1 with the line; a RAISE scoped to THIS row lifts it, another row's raise does not -
  printf '1757900003 keyA ROW-B 1000000 0\n' >> "$ml_t"
  rmlg_mt "$ml_fx" "$ml_h" --row ROW-B
  rmlg_expect 1 "rmlg/breached: a row at its token ceiling"
  rmlg_line "metered: ROW-B tokens(1000000/1000000) agents(0/40) lines=1" "rmlg/breached"
  printf 'RAISE ROW-Z MAX_TOKENS=5000000\n' >> "$ml_fx/.kit/budget.conf"
  rmlg_mt "$ml_fx" "$ml_h" --row ROW-B
  rmlg_expect 1 "rmlg/breached: a RAISE scoped to ANOTHER row does not lift it"
  printf 'RAISE ROW-B MAX_TOKENS=2000000\n' >> "$ml_fx/.kit/budget.conf"
  rmlg_mt "$ml_fx" "$ml_h" --row ROW-B
  rmlg_expect 0 "rmlg/breached: a scoped RAISE ROW-B lifts it"
  rmlg_line "metered: ROW-B tokens(1000000/2000000) agents(0/40) lines=1" "rmlg/breached-raised"
  git -C "$ml_fx" checkout -q -- .kit/budget.conf

  # ---- unmetered: no line for the row -> rc 3; no tally file at all -> rc 3 ---------------------------
  rmlg_mt "$ml_fx" "$ml_h" --row ROW-U
  rmlg_expect 3 "rmlg/unmetered: a row with no line in an existing tally"
  rmlg_line "unmetered: ROW-U tokens(0/1000000) agents(0/40) lines=0" "rmlg/unmetered"
  ml_h2="$ml_root/h2"; mkdir -p "$ml_h2"
  rmlg_mt "$ml_fx" "$ml_h2" --row ROW-M
  rmlg_expect 3 "rmlg/absent: no tally file at all"
  rmlg_line "unmetered: ROW-M tokens(0/1000000) agents(0/40) lines=0" "rmlg/absent"

  # ---- unreadable tally: rc 2 by an EXPLICIT test, not an awk-dependent abort (N/A as root) -----------
  if [ "$(id -u)" = 0 ]; then
    echo "N/A rmlg/unreadable: running as root (chmod 000 is readable)"
  else
    chmod 000 "$ml_t"
    rmlg_mt "$ml_fx" "$ml_h" --row ROW-M
    chmod 600 "$ml_t"
    rmlg_expect 2 "rmlg/unreadable: a present-but-unreadable tally"
    case "$mt_err" in *"not readable"*) : ;; *) fail "rmlg/unreadable: the refusal does not say 'not readable'; err=[$mt_err]" ;; esac
    [ -z "$mt_out" ] || fail "rmlg/unreadable: a refusal must print nothing on stdout; out=[$mt_out]"
  fi

  # ---- poisoned tally, symlinked tally, shallow repo -> rc 2 ---------------------------------------------
  ml_h3="$ml_root/h3"; ml_d3="$ml_h3/.local/state/sparkwright/runaway/$ml_key"; mkdir -p "$ml_d3"
  printf '1757900000 keyA ROW-M 1 0\n1757900000 keyA 100 1\n' > "$ml_d3/tally.v2"
  rmlg_mt "$ml_fx" "$ml_h3" --row ROW-M
  rmlg_expect 2 "rmlg/poisoned: a tally line off the grammar"
  [ -z "$mt_out" ] || fail "rmlg/poisoned: nothing on stdout; out=[$mt_out]"
  ml_h4="$ml_root/h4"; ml_d4="$ml_h4/.local/state/sparkwright/runaway/$ml_key"; mkdir -p "$ml_d4"
  printf '1757900000 keyA ROW-M 1 0\n' > "$ml_root/real-tally"; ln -s "$ml_root/real-tally" "$ml_d4/tally.v2"
  rmlg_mt "$ml_fx" "$ml_h4" --row ROW-M
  rmlg_expect 2 "rmlg/symlink: a symlinked tally"
  case "$mt_err" in *symlink*) : ;; *) fail "rmlg/symlink: the refusal does not name the symlink; err=[$mt_err]" ;; esac
  git clone -q --depth 1 "file://$ml_fx" "$ml_root/shallow" 2>/dev/null
  rmlg_mt "$ml_root/shallow" "$ml_root/h5" --row ROW-M
  rmlg_expect 2 "rmlg/shallow: a --depth 1 clone"
  case "$mt_err" in *"git fetch --unshallow"*) : ;; *) fail "rmlg/shallow: the refusal does not name the fix; err=[$mt_err]" ;; esac

  # ---- a DIRECTORY where the tally file belongs -> rc 2 by an explicit regular-file test (T1 reviewer Minor a) ----
  ml_h6="$ml_root/h6"; ml_d6="$ml_h6/.local/state/sparkwright/runaway/$ml_key"; mkdir -p "$ml_d6/tally.v2"
  rmlg_mt "$ml_fx" "$ml_h6" --row ROW-M
  rmlg_expect 2 "rmlg/dir-tally: a directory at tally.v2"
  case "$mt_err" in *"not a regular file"*) : ;; *) fail "rmlg/dir-tally: the refusal does not say 'not a regular file'; err=[$mt_err]" ;; esac
  [ -z "$mt_out" ] || fail "rmlg/dir-tally: a refusal must print nothing on stdout; out=[$mt_out]"

  # ---- the STEPS dimension: ROW-M has 2 lines; a scoped RAISE MAX_STEPS=2 makes it at-ceiling -> rc 1, and
  #      the stdout line contract is UNCHANGED (T1 reviewer Minor b) ----------------------------------------------
  printf 'RAISE ROW-M MAX_STEPS=2\n' >> "$ml_fx/.kit/budget.conf"
  rmlg_mt "$ml_fx" "$ml_h" --row ROW-M
  rmlg_expect 1 "rmlg/steps: a row at its MAX_STEPS ceiling"
  rmlg_line "metered: ROW-M tokens(150/1000000) agents(3/40) lines=2" "rmlg/steps"
  git -C "$ml_fx" checkout -q -- .kit/budget.conf

  # ---- --row: a bad id and a missing --row are rc 2 -------------------------------------------------------
  for ml_bad in 'row-m' '-ROW' 'ROW_M' 'ROW M'; do
    rmlg_mt "$ml_fx" "$ml_h" --row "$ml_bad"
    rmlg_expect 2 "rmlg/bad-row: --row '$ml_bad'"
  done
  rmlg_mt "$ml_fx" "$ml_h"
  rmlg_expect 2 "rmlg/no-row: meter without --row"
  rmlg_mt "$ml_fx" "$ml_h" --row
  rmlg_expect 2 "rmlg/no-row: --row with no value"

  # ---- meter NEVER WRITES: tally bytes, mtime, and the state dir's entries are unchanged ---------------
  touch -t 200001010000 "$ml_t"
  ml_ck0=$(cksum < "$ml_t"); ml_ls0=$(ls -A "$ml_d" | LC_ALL=C sort | tr '\n' ' ')
  for ml_r in ROW-M ROW-B ROW-U; do rmlg_mt "$ml_fx" "$ml_h" --row "$ml_r"; done
  [ "$(cksum < "$ml_t")" = "$ml_ck0" ] || fail "rmlg/read-only: meter CHANGED the tally bytes"
  [ -n "$(find "$ml_t" -mtime +365 2>/dev/null)" ] || fail "rmlg/read-only: meter touched the tally's mtime"
  [ "$(ls -A "$ml_d" | LC_ALL=C sort | tr '\n' ' ')" = "$ml_ls0" ] || fail "rmlg/read-only: meter left new entries in the state dir: [$(ls -A "$ml_d" | tr '\n' ' ')] (was [$ml_ls0])"
}

# rcps_lk_residue <label> — L6: NO lock.tok.*, NO lock.rel.*, NO lock.stale.*, NO pid.dead.* anywhere under the sandbox.
rcps_lk_residue() {
  _rl=$(find "$b4_sand" \( -name 'lock.tok.*' -o -name 'lock.rel.*' -o -name 'lock.stale.*' -o -name 'pid.dead.*' \) 2>/dev/null | head -3 | tr '\n' ' ')
  [ -z "$_rl" ] || fail "$1: lock residue left behind: $_rl"
}
# t2_sleepers <N> — wait up to ~3s for every `sleep <N>` to vanish; t2_sl is left holding the SURVIVORS' pids (empty =
# none). `pgrep -f` answers rc 1 for none and rc 0 for found; any OTHER rc is a broken probe and fails the leg, because a
# probe that cannot see would make every no-sleeper assertion pass vacuously (the old `ps | awk` did exactly that).
t2_sleepers() {
  t2_i=0
  while :; do
    if t2_sl=$(pgrep -f "sleep $1" 2>/dev/null); then t2_pr=0; else t2_pr=$?; fi
    case "$t2_pr" in
      1) t2_sl=""; return 0 ;;
      0) : ;;
      *) fail "rcps: pgrep failed (rc $t2_pr), so the no-sleeper leg would pass vacuously" ;;
    esac
    t2_i=$((t2_i + 1)); [ "$t2_i" -lt 30 ] || return 0
    sleep 0.1
  done
}
# rcps_backstop_leg — drive rcps_home_snap/rcps_home_diff over a FAKE home: a `lock.rel.x` dir (holding a file) that
# appears between the two snapshots is tolerated; a genuinely new file is still flagged (the exclusion is not a blanket).
rcps_backstop_leg() {
  _bk_h="$tmp/bk-home"; _bk_d="$_bk_h/.local/state/sparkwright/runaway"; mkdir -p "$_bk_d/keyX"
  printf 'x\n' > "$_bk_d/keyX/tally.v2"
  _bk_h0=$rcps_home0; _bk_s0=$rcps_snap0; _bk_s1=${rcps_snap1:-}
  rcps_home0="$_bk_h"; rcps_snap0=$(rcps_home_snap "$_bk_h")
  mkdir "$_bk_d/keyX/lock.rel.x"; printf 'p\n' > "$_bk_d/keyX/lock.rel.x/pid"
  rcps_snap1=$(rcps_home_snap "$_bk_h"); _bk_out=$(rcps_home_diff)
  [ -z "$_bk_out" ] || fail "rcps/M2-backstop: a lock.rel.* dir appearing between the snapshots was flagged: [$_bk_out]"
  printf 'y\n' > "$_bk_d/keyX/stray"
  rcps_snap1=$(rcps_home_snap "$_bk_h"); _bk_out=$(rcps_home_diff)
  [ -n "$_bk_out" ] || fail "rcps/M2-backstop: a genuinely NEW file was not flagged (the exclusion became a blanket)"
  rcps_home0=$_bk_h0; rcps_snap0=$_bk_s0; rcps_snap1=$_bk_s1
  rm -rf "$_bk_h"
}
# t2_cmd — the shimmed step (run in a subshell): the date shim on the lock, the ln shim on the flag.
t2_cmd() {
  cd "$tmp/repoA" || exit 9
  exec env HOME="$tmp/hsafe" KIT_RUNAWAY_SANDBOX="$b4_sand" PATH="$t2_root/shim:$t2_root/lnshim:$t2_root/rmshim:$PATH" \
    RG_SHIM_LOCK="$t2_shimlock" RG_SHIM_FLAG="$t2_flag" RG_SHIM_MODE="$t2_mode" RG_SHIM_TOKEN="$t2_tok" \
    RG_LN_FLAG="$t2_lnflag" RG_REAL_LN="$t2_realln" RG_RM_FLAG="$t2_rmflag" RG_LOCK_ORPHAN_AGE="$t2_orphan" \
    RG_RM_TERM_FLAG="$t2_rmterm" RG_RM_FOREIGN="$t2_rmforeign" RG_LN_LOG="$t2_lnlog" \
    sh "$b4_guard" step --row ROW-T --config "$b4_cfg" --tally "$b4_tally" --tokens 1 --agents 0
}
t2_step() { if b4_out=$( t2_cmd 2>&1 ); then b4_rc=0; else b4_rc=$?; fi; }
t2_reset() {
  t2_mode=""; t2_tok=""; t2_lnflag=""; t2_shimlock="$t2_lock"; t2_rmflag=""; t2_orphan=""; t2_rmterm=""; t2_rmforeign=""; t2_lnlog=""
  : > "$b4_tally"; rm -rf "$t2_lock" "$t2_lock.stolen" "$t2_lock".rel.* "$t2_lock".tok.* "$t2_flag" "$t2_root/lnfired" "$t2_root/rmfired" "$t2_root/rmterm" "$t2_root/lnlog"
}
t2_hold_start() { ( t2_cmd ) >/dev/null 2>&1 & t2_np=$!; sleep 2; }
t2_hold_stop() {   # <label> — TERM the held contender: interrupted means UNVERIFIED, rc 2
  kill -TERM "$t2_np" 2>/dev/null || :
  if wait "$t2_np"; then b4_rc=0; else b4_rc=$?; fi
  [ "$b4_rc" = 2 ] || fail "$1: the interrupted contender exited $b4_rc, not 2"
}
t2_tally_lines() { wc -l < "$b4_tally" | tr -d ' '; }

# rcps_lk_legs — the lock protocol's staged legs (each proves its shim fired, by the flag file).
rcps_lk_legs() {
  t2_dead2=$( sh -c 'echo $$' )
  while [ "$t2_dead2" = "$b4_dead" ]; do t2_dead2=$( sh -c 'echo $$' ); done

  # ---- (T2-1) the T-window with the dir stolen and NOT refilled: the take is lost, not a wedge.
  t2_reset; t2_mode=take
  t2_step
  [ -e "$t2_flag" ] || fail "rcps/take-window: the shim never fired, so this leg proves nothing; out=[$b4_out]"
  [ -d "$t2_lock.stolen" ] || fail "rcps/take-window: the fresh lock dir was not renamed away (leg is vacuous); out=[$b4_out]"
  b4_expect 0 "rcps/take-window: a taker whose fresh lock was renamed away re-takes it -> rc 0"
  [ "$(t2_tally_lines)" = 1 ] || fail "rcps/take-window: the step did not land exactly one line"
  [ -e "$t2_lock" ] && fail "rcps/take-window: a lock dir survived the run" || :
  [ ! -e "$t2_lock.stolen/pid" ] || fail "rcps/take-window: the stolen dir carries a pid token (the publish followed the renamed dir)"
  rcps_lk_residue "rcps/take-window"

  # ---- (L1) DOUBLE HOLD: the dir is renamed away at the T-window and a LIVE foreign holder mkdirs and
  # tokens the slot. The taker's publish must lose against it: it neither appends, nor touches the
  # foreign dir/token, nor leaves a token in the stolen dir; and it stays interruptible.
  t2_reset; t2_mode=take; t2_tok="$$ $b4_old"
  t2_hold_start
  [ -e "$t2_flag" ] || fail "rcps/L1-double-hold: the shim never fired, so this leg proves nothing"
  [ "$(wc -c < "$b4_tally" | tr -d ' ')" = 0 ] || fail "rcps/L1-double-hold: the taker APPENDED beside a live foreign holder"
  [ -d "$t2_lock" ] || fail "rcps/L1-double-hold: the foreign holder's lock dir was removed"
  [ "$(cat "$t2_lock/pid" 2>/dev/null)" = "$t2_tok" ] || fail "rcps/L1-double-hold: the foreign token is not byte-identical (now [$(cat "$t2_lock/pid" 2>/dev/null)])"
  [ "$(ls -A "$t2_lock" | tr '\n' ' ')" = "pid " ] || fail "rcps/L1-double-hold: the foreign dir holds more than its token: $(ls -A "$t2_lock" | tr '\n' ' ')"
  [ ! -e "$t2_lock.stolen/pid" ] || fail "rcps/L1-double-hold: the stolen dir carries a pid token (two holders)"
  t2_hold_stop "rcps/L1-double-hold"
  rcps_lk_residue "rcps/L1-double-hold"
  rm -rf "$t2_lock" "$t2_lock.stolen"

  # ---- (L2) a failed PUBLISH is a lost take, not a wedge: the first `ln` fails, the take is abandoned
  # (dir removed), the retry lands. Mutant: drop the lost-take rmdir -> an unbreakable pid-less orphan.
  t2_reset; t2_shimlock=""; t2_lnflag="$t2_root/lnfired"
  t2_step
  [ -e "$t2_lnflag" ] || fail "rcps/L2-publish-fail: the ln shim never fired, so this leg proves nothing; out=[$b4_out]"
  b4_expect 0 "rcps/L2-publish-fail: a failed publish is a lost take, the retry lands -> rc 0"
  [ "$(t2_tally_lines)" = 1 ] || fail "rcps/L2-publish-fail: the step did not land exactly one line"
  [ -e "$t2_lock" ] && fail "rcps/L2-publish-fail: a lock dir survived the run" || :
  rcps_lk_residue "rcps/L2-publish-fail"

  # ---- (L3) ABA PUT-BACK: a dead-old token judged, then at the B-window REPLACED by a LIVE token of another
  # pid. The breaker's rename moves the live token; it must put it back atomically and leave it be.
  t2_reset; t2_mode=swap; t2_tok="$$ $b4_old"
  mkdir "$t2_lock"; printf '%s %s\n' "$b4_dead" "$b4_old" > "$t2_lock/pid"
  t2_hold_start
  [ -e "$t2_flag" ] || fail "rcps/L3-aba-put-back: the shim never fired, so this leg proves nothing"
  [ -d "$t2_lock" ] || fail "rcps/L3-aba-put-back: the lock dir did not survive a breaker that judged a token since replaced"
  [ "$(cat "$t2_lock/pid" 2>/dev/null)" = "$t2_tok" ] || fail "rcps/L3-aba-put-back: the swapped-in live token was not put back byte-identical (now [$(cat "$t2_lock/pid" 2>/dev/null)])"
  [ "$(ls -A "$t2_lock" | tr '\n' ' ')" = "pid " ] || fail "rcps/L3-aba-put-back: residue inside the lock dir: $(ls -A "$t2_lock" | tr '\n' ' ')"
  [ "$(wc -c < "$b4_tally" | tr -d ' ')" = 0 ] || fail "rcps/L3-aba-put-back: the contender APPENDED while a live holder held the lock"
  t2_hold_stop "rcps/L3-aba-put-back"
  rcps_lk_residue "rcps/L3-aba-put-back"
  rm -rf "$t2_lock"

  # ---- (L3b) …and when the swapped-in token is itself DEAD-old (another pid), it is put back and THEN taken over.
  t2_reset; t2_mode=swap; t2_tok="$t2_dead2 $b4_old"
  mkdir "$t2_lock"; printf '%s %s\n' "$b4_dead" "$b4_old" > "$t2_lock/pid"
  t2_step
  [ -e "$t2_flag" ] || fail "rcps/L3b-aba-then-takeover: the shim never fired, so this leg proves nothing; out=[$b4_out]"
  b4_expect 0 "rcps/L3b-aba-then-takeover: a put-back dead token is then broken and taken over -> rc 0"
  [ "$(t2_tally_lines)" = 1 ] || fail "rcps/L3b-aba-then-takeover: the step did not land exactly one line"
  [ -e "$t2_lock" ] && fail "rcps/L3b-aba-then-takeover: a lock dir survived the run" || :
  rcps_lk_residue "rcps/L3b-aba-then-takeover"

  # ---- (L3c) SEC-2: a FAILED put-back must NOT delete the token it could not return. Same ABA staging as L3, and the
  # ln shim fails the first `ln` (the put-back itself). The moved-aside LIVE token must stay where it is
  # (pid.dead.<breaker>: it reads as LIVE to the probe, and the holder's release sweeps it): nothing appended, TERM -> rc 2.
  t2_reset; t2_mode=swap; t2_tok="$$ $b4_old"; t2_lnflag="$t2_root/lnfired"
  mkdir "$t2_lock"; printf '%s %s\n' "$b4_dead" "$b4_old" > "$t2_lock/pid"
  t2_hold_start
  [ -e "$t2_flag" ] || fail "rcps/L3c-failed-put-back: the swap shim never fired, so this leg proves nothing"
  [ -e "$t2_lnflag" ] || fail "rcps/L3c-failed-put-back: the ln shim never fired (the put-back did not fail), so this leg proves nothing"
  [ "$(cat "$t2_lock/pid.dead.$t2_np" 2>/dev/null)" = "$t2_tok" ] || fail "rcps/L3c-failed-put-back: the live token the put-back could not return was DELETED (pid.dead.$t2_np now [$(cat "$t2_lock/pid.dead.$t2_np" 2>/dev/null)])"
  [ "$(wc -c < "$b4_tally" | tr -d ' ')" = 0 ] || fail "rcps/L3c-failed-put-back: the contender APPENDED while a live token sat in the lock"
  t2_hold_stop "rcps/L3c-failed-put-back"
  rm -rf "$t2_lock"

  # ---- (L4) THE SLOT IS NEVER FREE DURING A BREAK: at the K-window the dir is still there (pid-less, the dead
  # token renamed aside), so no taker can mkdir in. The flag is written by the shim ONLY in that state.
  t2_reset; t2_mode=kwin
  mkdir "$t2_lock"; printf '%s %s\n' "$b4_dead" "$b4_old" > "$t2_lock/pid"
  t2_step
  [ -e "$t2_flag" ] || fail "rcps/L4-slot-held: the K-window was never observed (no pid-less dir holding pid.dead.*), so this leg proves nothing; out=[$b4_out]"
  b4_expect 0 "rcps/L4-slot-held: an in-place takeover of a dead token -> rc 0"
  [ "$(t2_tally_lines)" = 1 ] || fail "rcps/L4-slot-held: the step did not land exactly one line"
  [ -e "$t2_lock" ] && fail "rcps/L4-slot-held: a lock dir survived the run" || :
  rcps_lk_residue "rcps/L4-slot-held"

  # ---- (A7) ADOPT AN ABANDONED TAKEOVER: a breaker SIGKILLed after moving the token out and before publishing its
  # own leaves a dir with NO pid and ONE pid.dead.<b>. If <b> is dead and the token in it is dead + old, one
  # contender adopts it by an atomic mv and takes over in place.
  t2_reset
  mkdir "$t2_lock"; printf '%s %s\n' "$b4_dead" "$b4_old" > "$t2_lock/pid.dead.$t2_dead2"
  { [ -e "$t2_lock/pid.dead.$t2_dead2" ] && [ ! -e "$t2_lock/pid" ]; } || fail "rcps/A7-L1: the staging did not take effect (leg is vacuous)"
  t2_step
  b4_expect 0 "rcps/A7-L1: an abandoned takeover (no pid, one dead pid.dead.<b>) is adopted and taken over -> rc 0"
  [ "$(t2_tally_lines)" = 1 ] || fail "rcps/A7-L1: the step did not land exactly one line"
  [ -e "$t2_lock" ] && fail "rcps/A7-L1: a lock dir survived the run" || :
  rcps_lk_residue "rcps/A7-L1"

  # A7-L2 (negative): <b> is ALIVE (this shell) -> an in-progress takeover -> LIVE.
  # Mutant killed: adopt a live breaker's pid.dead.
  t2_reset
  mkdir "$t2_lock"; printf '%s %s\n' "$b4_dead" "$b4_old" > "$t2_lock/pid.dead.$$"
  t2_hold_start
  [ -f "$t2_lock/pid.dead.$$" ] || fail "rcps/A7-L2: the live breaker's pid.dead was ADOPTED/removed by a contender"
  [ "$(t2_tally_lines)" = 0 ] || fail "rcps/A7-L2: the contender APPENDED beside a live in-progress takeover"
  [ "$(ls -A "$t2_lock" | tr '\n' ' ')" = "pid.dead.$$ " ] || fail "rcps/A7-L2: the lock dir changed: $(ls -A "$t2_lock" | tr '\n' ' ')"
  [ "$(cat "$t2_lock/pid.dead.$$")" = "$b4_dead $b4_old" ] || fail "rcps/A7-L2: the pid.dead token is not byte-identical"
  t2_hold_stop "rcps/A7-L2"
  rm -rf "$t2_lock"

  # A7-L3 (M4): TWO pid.dead.* files whose suffixes are BOTH dead -> an abandoned takeover that was itself re-broken
  # -> the lowest suffix is adopted and the step proceeds. The OTHER dead file rides along in the held dir (it is
  # removed with the whole dir at release), so at the end the lock is absent with no pid.dead.* anywhere.
  t2_reset
  mkdir "$t2_lock"; printf '%s %s\n' "$b4_dead" "$b4_old" > "$t2_lock/pid.dead.$t2_dead2"
  printf '%s %s\n' "$b4_dead" "$b4_old" > "$t2_lock/pid.dead.$b4_dead"
  { [ -e "$t2_lock/pid.dead.$t2_dead2" ] && [ -e "$t2_lock/pid.dead.$b4_dead" ] && [ ! -e "$t2_lock/pid" ]; } || fail "rcps/A7-L3: the staging did not take effect (leg is vacuous)"
  t2_step
  b4_expect 0 "rcps/A7-L3: two pid.dead.* files, both dead -> adopted and taken over -> rc 0"
  [ "$(t2_tally_lines)" = 1 ] || fail "rcps/A7-L3: the step did not land exactly one line"
  [ -e "$t2_lock" ] && fail "rcps/A7-L3: a lock dir survived the run" || :
  rcps_lk_residue "rcps/A7-L3"

  # A7-L3b (negative, M4): TWO pid.dead.* files, ONE suffix alive (this shell) -> a takeover in progress -> LIVE, nothing touched.
  t2_reset
  mkdir "$t2_lock"; printf '%s %s\n' "$b4_dead" "$b4_old" > "$t2_lock/pid.dead.$t2_dead2"
  printf '%s %s\n' "$b4_dead" "$b4_old" > "$t2_lock/pid.dead.$$"
  t2_a7=$(ls -A "$t2_lock" | tr '\n' ' ')
  t2_hold_start
  [ "$(t2_tally_lines)" = 0 ] || fail "rcps/A7-L3b: the contender APPENDED beside a live in-progress takeover (two pid.dead.*, one alive)"
  [ "$(ls -A "$t2_lock" | tr '\n' ' ')" = "$t2_a7" ] || fail "rcps/A7-L3b: the lock dir changed: $(ls -A "$t2_lock" | tr '\n' ' ')"
  [ "$(cat "$t2_lock/pid.dead.$t2_dead2")" = "$b4_dead $b4_old" ] || fail "rcps/A7-L3b: a pid.dead token is not byte-identical"
  [ "$(cat "$t2_lock/pid.dead.$$")" = "$b4_dead $b4_old" ] || fail "rcps/A7-L3b: the live breaker's pid.dead token is not byte-identical"
  t2_hold_stop "rcps/A7-L3b"
  rm -rf "$t2_lock"

  # A7-L3c (negative, F1): TWO pid.dead.* files, BOTH suffixes dead, but the token inside the HIGHER one is LIVE (this
  # shell): a live holder whose token an ABA breaker moved aside, and that breaker was then SIGKILLed. A dead suffix does
  # not make the token inside dead -> LIVE, nothing touched. Mutant killed: judge by the suffix alone (adopts the low one).
  t2_reset
  if [ "$t2_dead2" -lt "$b4_dead" ]; then t2_lo="$t2_dead2"; t2_hi="$b4_dead"; else t2_lo="$b4_dead"; t2_hi="$t2_dead2"; fi
  mkdir "$t2_lock"; printf '%s %s\n' "$b4_dead" "$b4_old" > "$t2_lock/pid.dead.$t2_lo"
  printf '%s %s\n' "$$" "$b4_old" > "$t2_lock/pid.dead.$t2_hi"
  { [ -e "$t2_lock/pid.dead.$t2_lo" ] && [ -e "$t2_lock/pid.dead.$t2_hi" ] && [ ! -e "$t2_lock/pid" ]; } || fail "rcps/A7-L3c: the staging did not take effect (leg is vacuous)"
  t2_a7=$(ls -A "$t2_lock" | tr '\n' ' ')
  t2_hold_start
  [ "$(t2_tally_lines)" = 0 ] || fail "rcps/A7-L3c: the contender APPENDED beside a live token parked in a dead-suffixed pid.dead.*"
  [ "$(ls -A "$t2_lock" | tr '\n' ' ')" = "$t2_a7" ] || fail "rcps/A7-L3c: the lock dir changed: $(ls -A "$t2_lock" | tr '\n' ' ')"
  [ ! -e "$t2_lock/pid" ] || fail "rcps/A7-L3c: a pid appeared (an adoption)"
  [ "$(cat "$t2_lock/pid.dead.$t2_lo")" = "$b4_dead $b4_old" ] || fail "rcps/A7-L3c: the dead-token file is not byte-identical"
  [ "$(cat "$t2_lock/pid.dead.$t2_hi")" = "$$ $b4_old" ] || fail "rcps/A7-L3c: the live-token file is not byte-identical"
  t2_hold_stop "rcps/A7-L3c"
  rm -rf "$t2_lock"

  # ---- (A8) THE ORPHAN-E REAPER: a taker SIGKILLed between its mkdir and its ln leaves an EMPTY dir (no pid, no
  # pid.dead.*). Older than RG_LOCK_ORPHAN_AGE it is rmdir'd (rmdir removes only an EMPTY dir, so a slow live
  # creator merely loses its take). The age is the dir's mtime via find -mmin (minutes: effective age >= 1 minute).
  t2_reset; t2_orphan=1
  mkdir "$t2_lock"; touch -t 200001010000 "$t2_lock"
  [ -n "$(find "$t2_lock" -maxdepth 0 -mmin +1 2>/dev/null)" ] || fail "rcps/A8-L1: the backdating did not take effect (leg is vacuous)"
  t2_step
  b4_expect 0 "rcps/A8-L1: an old empty orphan lock dir is reaped and the step proceeds -> rc 0"
  [ "$(t2_tally_lines)" = 1 ] || fail "rcps/A8-L1: the step did not land exactly one line"
  [ -e "$t2_lock" ] && fail "rcps/A8-L1: a lock dir survived the run" || :
  rcps_lk_residue "rcps/A8-L1"

  # A8-L2 (negative): a FRESH empty dir is the holder's creation window -> LIVE.
  # Mutant killed: reap without the age check.
  t2_reset; t2_orphan=1
  mkdir "$t2_lock"
  t2_hold_start
  [ -d "$t2_lock" ] || fail "rcps/A8-L2: a fresh empty lock dir was reaped (no age check)"
  [ "$(t2_tally_lines)" = 0 ] || fail "rcps/A8-L2: the contender APPENDED beside a fresh creation window"
  t2_hold_stop "rcps/A8-L2"
  rm -rf "$t2_lock"

  # ---- (A9) RENAME-AWAY UNLOCK: the holder moves its own dir away BEFORE deleting it, so a breaker can never
  # publish into a dir that is being deleted. The rm shim proves the lock path is already gone when `rm -rf` runs.
  t2_reset; t2_rmflag="$t2_root/rmfired"; : > "$t2_rmflag"
  t2_step
  b4_expect 0 "rcps/A9-L1: a plain step -> rc 0"
  [ "$(t2_tally_lines)" = 1 ] || fail "rcps/A9-L1: the step did not land exactly one line"
  [ "$(grep -c GONE "$t2_rmflag" || :)" -ge 1 ] || fail "rcps/A9-L1: the rm shim never saw the unlock delete a moved-away dir; log=[$(tr '\n' ' ' < "$t2_rmflag")]"
  [ "$(grep -c EXISTS "$t2_rmflag" || :)" = 0 ] || fail "rcps/A9-L1: unlock deleted the dir IN PLACE (the lock path still existed at rm -rf): [$(tr '\n' ' ' < "$t2_rmflag")]"
  [ -e "$t2_lock" ] && fail "rcps/A9-L1: a lock dir survived the run" || :
  rcps_lk_residue "rcps/A9-L1"

  # ---- (N1) A TERM DURING THE RELEASE MUST NOT RE-ENTER IT. The rm shim, on the release's `rm -rf lock.rel.<pid>`,
  # stages a FOREIGN live lock at the lock path and TERMs the guard; the guard's TERM trap then runs the release again.
  # If HELD is still set, that second release MOVES THE FOREIGN HOLDER'S DIR. The foreign lock must survive byte-identical.
  t2_reset; t2_rmterm="$t2_root/rmterm"; t2_rmforeign="$$ $b4_old"
  t2_step
  [ -e "$t2_rmterm" ] || fail "rcps/N1-term-in-release: the rm shim never fired, so this leg proves nothing; out=[$b4_out]"
  [ -d "$t2_lock" ] || fail "rcps/N1-term-in-release: the foreign holder's lock dir was MOVED by the re-entered release (rc=$b4_rc); out=[$b4_out]"
  [ "$(cat "$t2_lock/pid" 2>/dev/null)" = "$t2_rmforeign" ] || fail "rcps/N1-term-in-release: the foreign token is not byte-identical (now [$(cat "$t2_lock/pid" 2>/dev/null)])"
  [ "$(ls -A "$t2_lock" | tr '\n' ' ')" = "pid " ] || fail "rcps/N1-term-in-release: the foreign dir holds more than its token: $(ls -A "$t2_lock" | tr '\n' ' ')"
  rcps_lk_residue "rcps/N1-term-in-release"
  b4_expect 2 "rcps/N1-term-in-release: a TERMed guard is UNVERIFIED"
  rm -rf "$t2_lock"

  # ---- (M1) THE TAKEOVER'S PUBLISH IS GATED ON ITS SIDE-FILE WRITE. At the K-window the shim pre-creates the
  # breaker's side file, so the `set -C` write FAILS. The takeover must not publish (no pid-less/garbage token): the dead
  # token is PUT BACK (an `ln` whose source is a pid.dead.* file) and the next round breaks it cleanly.
  t2_reset; t2_mode=kfail; t2_lnlog="$t2_root/lnlog"; : > "$t2_lnlog"
  mkdir "$t2_lock"; printf '%s %s\n' "$b4_dead" "$b4_old" > "$t2_lock/pid"
  t2_step
  [ -e "$t2_flag" ] || fail "rcps/M1-write-gates-publish: the K-window shim never fired, so this leg proves nothing; out=[$b4_out]"
  grep -q 'pid\.dead\.' "$t2_lnlog" || fail "rcps/M1-write-gates-publish: after a failed side-file write the dead token was NOT put back (no ln from a pid.dead.* file); ln log=[$(tr '\n' ' ' < "$t2_lnlog")]"
  b4_expect 0 "rcps/M1-write-gates-publish: a failed takeover write falls to the put-back arm, the retry lands -> rc 0"
  [ "$(t2_tally_lines)" = 1 ] || fail "rcps/M1-write-gates-publish: the step did not land exactly one line"
  [ -e "$t2_lock" ] && fail "rcps/M1-write-gates-publish: a lock dir survived the run" || :
  rcps_lk_residue "rcps/M1-write-gates-publish"

  # ---- (M2) THE REAL-STATE BACKSTOP tolerates a live session's release directory: a `lock.rel.<x>` dir (with a file
  # inside) appearing between the two snapshots is NOT a violation, while a genuinely NEW file still is.
  rcps_backstop_leg

  # ---- STRUCTURAL PIN: the ONLY move of the lock dir is the holder's own release (A9); the old rename-the-dir break is gone.
  [ "$(grep -c 'lock\.stale' "$b4_guard" || :)" = 0 ] || fail "rcps/pin: the guard still mentions lock.stale (the rename-the-dir break)"
  [ "$(grep -cF 'mv "$RG_LOCK"' "$b4_guard" || :)" = 1 ] || fail "rcps/pin: the guard must move the lock DIR exactly once (the holder's own release)"
  grep -F 'mv "$RG_LOCK"' "$b4_guard" | grep -qF 'mv "$RG_LOCK" "$RG_LOCK.rel.$$"' || fail "rcps/pin: the one permitted lock-dir move is not the A9 release form"
  t2_reset
}

# --- b4 leg helpers (oracle region) -------------------------------------------------------------
b4_mkcfg() { printf 'MAX_TOKENS=%s\nMAX_STEPS=%s\nMAX_AGENTS=%s\nWARN_PCT=%s\nCOST_PER_1K_USD=0.003\n' "$1" "$2" "$3" "$4" > "$b4_cfg"; }
# ⚠️ BOTH RUNNERS PIN $HOME INSIDE $tmp. The default tally is the invoking user's REAL per-repo tally
# under $HOME; a leg that forgets an override must still be unable to touch it (rcps_home_end asserts it).
# b4_run_in also INJECTS the sandbox --config/--tally for the same reason (belt and braces: the leg
# that omitted them once did write to the developer's live tally before this was here).
b4_run()  { if b4_out=$(HOME="$tmp/hsafe" KIT_RUNAWAY_SANDBOX="$b4_sand" sh "$b4_guard" "$@" 2>&1); then b4_rc=0; else b4_rc=$?; fi; }
b4_run_in() {
  _d=$1; _c=$2; shift 2
  [ "$_c" != step ] || set -- --row ROW-T "$@"    # T1a: step needs a row; every legacy leg meters one row
  if b4_out=$( cd "$_d" && HOME="$tmp/hsafe" KIT_RUNAWAY_SANDBOX="$b4_sand" sh "$b4_guard" "$_c" \
                 --config "$b4_cfg" --tally "$b4_tally" "$@" 2>&1 ); then b4_rc=0; else b4_rc=$?; fi
}
# b4_run_home — NO override at all: the REAL default state dir + the REAL default config, with $HOME
# pointed inside the selftest's $tmp. The dial is UNSET so these legs also prove the default path.
b4_run_home() { _h=$1; shift; [ "${1:-}" != step ] || { _hs=$1; shift; set -- "$_hs" --row ROW-T "$@"; }; if b4_out=$( cd "$tmp/repoA" || exit 9; unset KIT_RUNAWAY_SANDBOX; HOME="$_h" sh "$b4_guard" "$@" 2>&1 ); then b4_rc=0; else b4_rc=$?; fi; }
# b4_run_nodial / b4_run_nodial_env — the dial UNSET. The env spellings are set on the command line
# rather than exported so the refusal under test is the one this leg names, and nothing leaks on.
b4_run_nodial() { if b4_out=$( unset KIT_RUNAWAY_SANDBOX; HOME="$tmp/hsafe" sh "$b4_guard" "$@" 2>&1 ); then b4_rc=0; else b4_rc=$?; fi; }
# b4_run_in2 — like b4_run_in but with the config and tally chosen per call (the R1/H2 leg needs its
# own read-only directory, which cannot be the shared fixture tally).
b4_run_in2() {
  _d=$1; _c=$2; _t=$3; _s=$4; shift 4
  [ "$_s" != step ] || set -- --row ROW-T "$@"
  if b4_out=$( cd "$_d" && HOME="$tmp/hsafe" KIT_RUNAWAY_SANDBOX="$b4_sand" sh "$b4_guard" "$_s" \
                 --config "$_c" --tally "$_t" "$@" 2>&1 ); then b4_rc=0; else b4_rc=$?; fi
}
# b4_run_wt <dir> <home> <args...> — the DEFAULT per-repo tally under <home>, a sandboxed --config ($b4_cfg)
b4_run_wt() {
  _wd=$1; _wh=$2; shift 2
  if b4_out=$( cd "$_wd" && HOME="$_wh" KIT_RUNAWAY_SANDBOX="$b4_sand" sh "$b4_guard" "$@" --config "$b4_cfg" 2>&1 ); then b4_rc=0; else b4_rc=$?; fi
}
b4_run_nodial_env() {
  _n=$1; _v=$2; shift 2
  if b4_out=$( unset KIT_RUNAWAY_SANDBOX; HOME="$tmp/hsafe"; export HOME; eval "export $_n=\"\$_v\""; sh "$b4_guard" "$@" 2>&1 ); then b4_rc=0; else b4_rc=$?; fi
}
b4_expect() { [ "$b4_rc" = "$1" ] || fail "$2 (want $1, got $b4_rc); out=[$b4_out]"; }
b4_has()    { case "$b4_out" in *"$2"*) : ;; *) fail "$1 (output does not carry '$2'); out=[$b4_out]" ;; esac; }
b4_hasnt()  { case "$b4_out" in *"$2"*) fail "$1 (output wrongly carries '$2'); out=[$b4_out]" ;; *) : ;; esac; }

case "${1:-}" in
  --selftest) selftest ;;
  --require|"") selftest ;;   # no project-state aspect; the teeth ARE the selftest
  *) echo "usage: runaway-killswitch-wired.sh [--require] | --selftest" >&2; exit 2 ;;
esac
