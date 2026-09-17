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
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  cfg="$tmp/c"; tally="$tmp/t"
  # B4: `--config` / `--tally` are REFUSED without the human sandbox dial (a second tally is a second
  # ceiling), so this fixture declares its own throwaway sandbox. Everything the legs redirect lives
  # under it; the legs that exercise the DEFAULT per-machine path unset the dial and fake $HOME.
  KIT_RUNAWAY_SANDBOX="$tmp"; export KIT_RUNAWAY_SANDBOX
  mkcfg() { printf 'MAX_TOKENS=%s\nMAX_STEPS=%s\nMAX_AGENTS=%s\nWARN_PCT=%s\nCOST_PER_1K_USD=0.003\n' "$1" "$2" "$3" "$4" >"$cfg"; }
  R() { _c=$1; shift; sh "$GUARD" "$_c" --config "$cfg" --tally "$tally" "$@"; }   # subcommand-first; defaults before caller args so caller --config wins (last-wins; script reads subcommand as $1 BEFORE the option loop)
  expect() { _w=$1; shift; "$@" >/dev/null 2>&1 && _g=0 || _g=$?; [ "$_g" = "$_w" ] || fail "$_desc (want $_w, got $_g)"; }

  _desc="under-budget continues"; mkcfg 1000 10 5 80; : >"$tally"; expect 0 R step --tokens 100 --agents 1
  _desc="token breach stops";     mkcfg 1000 10 5 80; : >"$tally"; expect 1 R step --tokens 1000 --agents 0
  _desc="step breach stops";      mkcfg 999999 2 99 80; : >"$tally"; R step --tokens 1 --agents 0 >/dev/null 2>&1; expect 1 R step --tokens 1 --agents 0
  _desc="agent breach stops";     mkcfg 999999 99 2 80; : >"$tally"; expect 1 R step --tokens 1 --agents 2
  _desc="warn continues";         mkcfg 1000 10 5 80; : >"$tally"; expect 0 R step --tokens 800 --agents 1
  _desc="breach names the dim";   mkcfg 1000 10 5 80; : >"$tally"; case "$(R step --tokens 1000 --agents 0 2>&1 >/dev/null)" in *tokens*) : ;; *) fail "breach must name the dimension";; esac
  _desc="missing config -> 2";    expect 2 R check --config "$tmp/nope"
  _desc="malformed config -> 2";  printf 'MAX_TOKENS=x\n' >"$cfg"; expect 2 R check
  _desc="reset clears";           mkcfg 1000 10 5 80; : >"$tally"; R step --tokens 500 --agents 1 >/dev/null 2>&1; R reset --tally "$tally" >/dev/null 2>&1; expect 0 R check
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
  # One ceiling per MACHINE: the tally moved to $HOME/.local/state/sparkwright/runaway/, its line
  # grammar became `<epoch> <session-key> <tokens> <agents>`, the read path refuses anything else,
  # the appends are serialized by a mkdir lock, and both override routes are refused without the
  # KIT_RUNAWAY_SANDBOX dial. Design: docs/architecture/2026-09-15-b4-cross-session-budget-design.md.
  b4_legs
  echo "runaway-killswitch-wired: selftest OK"
}

# ── ORACLE MARKER: b4_legs() and everything below is the non-vacuity oracle region ───────────────
# (same discipline as scripts/board-claim.sh's marker: the mutation sweep mutates the lines ABOVE
# the `selftest()` marker, so the assertions themselves cannot be neutered by a mutant.)

# b4_legs — the B4-CROSS-SESSION-BUDGET legs. Every fixture lives under the selftest's own $tmp and
# every invocation that reaches the STATE DIR does so with a $HOME inside $tmp: NOTHING here may
# touch the real $HOME/.local/state/sparkwright, which is this machine's live cross-session tally.
b4_legs() {
  b4_guard=$(pwd -P)/$GUARD
  b4_sand="$tmp/sand"; mkdir -p "$b4_sand" "$tmp/hsafe"
  b4_cfg="$b4_sand/c"; b4_tally="$b4_sand/t"
  KIT_RUNAWAY_SANDBOX="$b4_sand"; export KIT_RUNAWAY_SANDBOX
  b4_mkcfg 999999999 0 0 0

  git init -q "$tmp/repoA" 2>/dev/null
  git init -q "$tmp/repoB" 2>/dev/null

  # ---- (A) poisoned line refused — the read path fails CLOSED on anything but the grammar --------
  # `<epoch> <session-key> <tokens> <agents>`: three 1–12-digit integers and a [A-Za-z0-9._-]{1,128}
  # key, single-space separated. The refusal names the absolute path and the LINE NUMBER — never the
  # bytes (control characters and log injection: the tally is a file any local process can write).
  for b4_bad in '100 1' '' '1757900000 k 1234567890123 1' '1757900000 a b 2 3' '1757900000 k 1 1 ' \
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
  printf '1757900000 keyA 100 1\n' > "$b4_tally"
  b4_run check --config "$b4_cfg" --tally "$b4_tally"
  b4_expect 0 "b4/poison-anchor: a well-formed four-field line is ACCEPTED -> rc 0"
  # line cap: a tally past 100000 lines is refused rather than held through every lock spin.
  awk 'BEGIN{for(i=0;i<100001;i++) print "1757900000 keyA 1 0"}' > "$b4_tally"
  b4_run check --config "$b4_cfg" --tally "$b4_tally"
  b4_expect 2 "b4/line-cap: a tally past the 100000-line cap -> rc 2"
  b4_has "b4/line-cap: the refusal names the cap" "100000"
  # …and the cap counts RECORDS, not NEWLINES (R2/2). Exactly 100000 terminated lines plus ONE
  # UNTERMINATED record is 100001 records and must be refused; `wc -l` sees 100000 and lets it
  # through. The unterminated last line is precisely what a writer killed mid-append leaves, so this
  # is the shape the cap most needs to see — and until this leg, reverting to `wc -l` left the
  # suite green.
  awk 'BEGIN{for(i=0;i<100000;i++) print "1757900000 keyA 1 0"; printf "1757900000 keyA 1 0"}' > "$b4_tally"
  b4_run check --config "$b4_cfg" --tally "$b4_tally"
  b4_expect 2 "b4/line-cap: 100000 terminated lines + one UNTERMINATED record is over the cap -> rc 2"
  b4_has "b4/line-cap: the refusal counts records, naming the cap" "100000"

  # ---- (B) sum clamps toward the ceiling — overflow may never read as under-budget ---------------
  # 1001 lines of 999999999999 tokens sum past 10^15; the sum CLAMPS to 10^15 (never wraps), so the
  # STOP names the clamp. On an unclamped %d sum this is a wrapped (possibly negative) number.
  awk 'BEGIN{for(i=0;i<1001;i++) print "1757900000 keyA 999999999999 0"}' > "$b4_tally"
  b4_mkcfg 900000000000000 0 0 0
  b4_run check --config "$b4_cfg" --tally "$b4_tally"
  b4_expect 1 "b4/clamp: a sum past 10^15 STOPs (never wraps into under-budget) -> rc 1"
  b4_has "b4/clamp: the STOP names the CLAMPED sum, not a wrapped one" "tokens(1000000000000000/900000000000000)"

  # ---- (C) state dir hygiene — the tally is per MACHINE, under $HOME, and refuses a hostile dir ---
  # These legs pass NO override, so they exercise the REAL default path ($HOME/.local/state/
  # sparkwright/runaway/tally) and the REAL default config — with $HOME pointed inside $tmp.
  b4_h="$tmp/home1"; mkdir -p "$b4_h"
  b4_run_home "$b4_h" step --tokens 1 --agents 0
  b4_expect 0 "b4/state-dir: a step with no override records under \$HOME/.local/state -> rc 0"
  [ -f "$b4_h/.local/state/sparkwright/runaway/tally" ] \
    || fail "b4/state-dir: no tally at \$HOME/.local/state/sparkwright/runaway/tally after a step"
  b4_run_home "relative/home" step --tokens 1 --agents 0
  b4_expect 2 "b4/state-dir: a non-absolute \$HOME -> rc 2 (fail-closed)"
  b4_has "b4/state-dir: the refusal names HOME" "HOME"
  b4_h2="$tmp/home2"; mkdir -p "$b4_h2/.local/state/sparkwright"
  ln -s "$tmp" "$b4_h2/.local/state/sparkwright/runaway"
  b4_run_home "$b4_h2" step --tokens 1 --agents 0
  b4_expect 2 "b4/state-dir: a SYMLINKED runaway/ dir -> rc 2, nothing written"
  b4_has "b4/state-dir: the refusal names the symlink" "symlink"
  [ -f "$tmp/tally" ] && fail "b4/state-dir: the symlinked dir was written THROUGH" || :
  b4_h3="$tmp/home3"; mkdir -p "$b4_h3/.local/state/sparkwright/runaway"
  ln -s "$tmp/elsewhere" "$b4_h3/.local/state/sparkwright/runaway/tally"
  b4_run_home "$b4_h3" step --tokens 1 --agents 0
  b4_expect 2 "b4/state-dir: a SYMLINKED tally -> rc 2, nothing written"
  [ -f "$tmp/elsewhere" ] && fail "b4/state-dir: the symlinked tally was written THROUGH" || :

  # ---- (D) combined ceiling stops — two session keys, ONE ceiling -------------------------------
  # The defect this slice closes: N worktrees used to get N silent ceilings. Each repo is its own
  # session key; `check` sums ALL keys, so the SECOND session STOPs on the combined total.
  : > "$b4_tally"; b4_mkcfg 1500 0 0 0
  b4_run_in "$tmp/repoA" step --tokens 1000 --agents 0
  b4_expect 0 "b4/combined: session A alone (1000/1500) -> rc 0"
  b4_run_in "$tmp/repoB" step --tokens 1000 --agents 0
  b4_expect 1 "b4/combined: session B's step crosses the COMBINED ceiling -> rc 1"
  b4_has "b4/combined: the STOP names the tokens dimension" "tokens(2000/1500)"
  [ "$(wc -l < "$b4_tally" | tr -d ' ')" = 2 ] || fail "b4/combined: expected 2 tally lines"
  [ "$(awk '{print $2}' "$b4_tally" | sort -u | wc -l | tr -d ' ')" = 2 ] \
    || fail "b4/combined: the two sessions did not record DISTINCT session keys"
  # a session key is REQUIRED: outside a git work tree there is no key, and the step is refused.
  b4_run_in "$tmp" step --tokens 1 --agents 0
  b4_expect 2 "b4/session-key: a step from outside any git work tree -> rc 2"

  # ---- (E) reset scopes to own key — one session's reset must not clear another's ---------------
  b4_run_in "$tmp/repoA" reset --config "$b4_cfg" --tally "$b4_tally"
  b4_expect 0 "b4/reset-scope: A resets -> rc 0"
  [ "$(wc -l < "$b4_tally" | tr -d ' ')" = 1 ] \
    || fail "b4/reset-scope: A's reset did not leave exactly B's one line; tally=[$(cat "$b4_tally")]"
  b4_has_b4key=$(awk '{print $2}' "$b4_tally")
  b4_run_in "$tmp/repoB" step --config "$b4_cfg" --tally "$b4_tally" --tokens 600 --agents 0
  b4_expect 1 "b4/reset-scope: B's OWN 1000 tokens SURVIVED A's reset, so B's next 600 breaches -> rc 1"
  b4_has "b4/reset-scope: the surviving total is B's alone (1600), not the combined 2600" "tokens(1600/1500)"
  case "$b4_has_b4key" in
    *_repoB) : ;;
    *) fail "b4/reset-scope: the surviving line is not B's key (key=[$b4_has_b4key])" ;;
  esac

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
      if HOME="$tmp/hsafe" KIT_RUNAWAY_SANDBOX="$b4_sand" sh "$b4_guard" step \
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
  [ "$(awk '{t+=$3} END{printf "%d", t}' "$b4_tally")" = 140 ] \
    || fail "b4/serialize: the 20 parallel steps do not sum to 140 tokens"
  [ -e "$b4_sand/lock" ] && fail "b4/serialize: a lock dir survived the fan-out (not released)" || :
  b4_stale=$(ls -d "$b4_sand"/lock.stale.* 2>/dev/null | wc -l | tr -d ' ')
  [ "$b4_stale" = 0 ] || fail "b4/serialize: $b4_stale lock.stale.* residue left behind by the fan-out"
  rm -rf "$b4_rundir"

  # ---- (G) two breakers one winner — a DEAD holder's lock is broken by rename, exactly once ------
  # A lock dir with NO pid file is the creation window and counts as LIVE; an unparseable pid counts
  # as LIVE (never as dead: `kill -0 -1` would otherwise succeed forever); only a validated, dead pid
  # is broken, and the break is `mv lock lock.stale.$$` so one of two breakers wins the rename.
  # ⚠️ THE TOKEN IS `<pid> <epoch>` (CI round / ABA): a breaker needs a dead pid AND a lock older than
  # RG_LOCK_MIN_AGE, so these fixtures carry a deliberately OLD epoch. A bare pid — which is what this
  # fixture used to write — is now correctly read as LIVE, which is the fail-closed direction.
  : > "$b4_tally"; b4_mkcfg 0 0 0 0
  b4_dead=$( sh -c 'echo $$' )
  b4_old=$(( $(date -u +%s) - 3600 ))
  mkdir -p "$b4_sand/lock"; printf '%s %s\n' "$b4_dead" "$b4_old" > "$b4_sand/lock/pid"
  ( cd "$tmp/repoA" && HOME="$tmp/hsafe" KIT_RUNAWAY_SANDBOX="$b4_sand" sh "$b4_guard" step \
      --config "$b4_cfg" --tally "$b4_tally" --tokens 1 --agents 0 >/dev/null 2>&1 ) &
  ( cd "$tmp/repoB" && HOME="$tmp/hsafe" KIT_RUNAWAY_SANDBOX="$b4_sand" sh "$b4_guard" step \
      --config "$b4_cfg" --tally "$b4_tally" --tokens 1 --agents 0 >/dev/null 2>&1 ) &
  wait
  [ "$(wc -l < "$b4_tally" | tr -d ' ')" = 2 ] \
    || fail "b4/breakers: two contenders on a DEAD holder's lock did not both land a line"
  [ -d "$b4_sand/lock" ] && fail "b4/breakers: the lock dir survived the run (not released)" || :
  # ⚠️ THE "TREATED AS LIVE" LEGS ASSERT THE LOCK IS STILL THERE, THEY DO NOT WAIT OUT THE BOUND.
  # With the bound at 30s, three legs that each sat until expiry would add 90s to every run. Observing
  # that the lock SURVIVES a contender — and that the tally is still empty — is the direct assertion
  # ("it was not broken"), and it is strictly stronger than an rc that only says "something refused".
  # The bound's own expiry is proven quickly by b4/spin-bound below (an unbreakable lock, no sleeps).
  : > "$b4_tally"
  b4_notbroken() {   # <label> — a contender must NOT break the lock it is pointed at
    ( cd "$tmp/repoA" && exec env HOME="$tmp/hsafe" KIT_RUNAWAY_SANDBOX="$b4_sand" \
        sh "$b4_guard" step --config "$b4_cfg" --tally "$b4_tally" --tokens 1 --agents 0 \
        >/dev/null 2>&1 ) &
    b4_np=$!
    sleep 2
    [ -d "$b4_sand/lock" ] || fail "$1: the lock was BROKEN by a contender that must have treated it as live"
    [ "$(wc -c < "$b4_tally" | tr -d ' ')" = 0 ] || fail "$1: the contender APPENDED while the lock was held"
    kill -TERM "$b4_np" 2>/dev/null || :
    if wait "$b4_np"; then b4_rc=0; else b4_rc=$?; fi
    [ "$b4_rc" = 2 ] || fail "$1: the interrupted contender exited $b4_rc, not 2"
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
  # (S1) NO CODE PATH REMOVES A LOCK THIS PROCESS DOES NOT OWN. The post-rename restore arm used to
  # `rm -rf` on mismatch — a dir that may by then be another holder's LIVE lock — and to `mv` it back
  # behind a TOCTOU `-e` test. The mismatch arm is not reachable deterministically from outside (it
  # needs the token to change between the guard's judgment and its rename, a microsecond window), so
  # what is asserted here is the INVARIANT that arm exists to protect: after a contender has run
  # against a live-token lock, the lock dir and its token are BYTE-IDENTICAL and no `lock.stale.*`
  # residue exists anywhere. Stated plainly: this leg would not have caught the deleted-live-lock
  # bug in the race itself; it catches any future path that removes or rewrites a lock it does not own.
  printf '%s %s\n' "$$" "$b4_old" > "$b4_sand/lock/pid"
  b4_tok0=$(cat "$b4_sand/lock/pid")
  b4_notbroken "b4/aba-restore: a LIVE-token lock is never removed by a contender"
  [ "$(cat "$b4_sand/lock/pid" 2>/dev/null)" = "$b4_tok0" ] \
    || fail "b4/aba-restore: the live holder's token was REWRITTEN by a contender (was [$b4_tok0], now [$(cat "$b4_sand/lock/pid" 2>/dev/null)])"
  b4_res=$(ls -d "$b4_sand"/lock.stale.* 2>/dev/null | wc -l | tr -d ' ')
  [ "$b4_res" = 0 ] || fail "b4/aba-restore: $b4_res lock.stale.* residue left beside a live lock"
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
  printf '1757900000 keyA 1 0\n' > "$b4_sand/../outside-$$/t"
  b4_run check --config "$b4_cfg" --tally "$b4_sand/../outside-$$/t"
  b4_expect 2 "b4/override: a '..' path that leaves the sandbox -> rc 2"
  b4_has "b4/override: the refusal names the sandbox it is outside of" "OUTSIDE the sandbox"
  ln -s "$b4_sand/../outside-$$/t" "$b4_sand/link-out"
  b4_run check --config "$b4_cfg" --tally "$b4_sand/link-out"
  b4_expect 2 "b4/override: a SYMLINKED leaf inside the sandbox (a hop out) -> rc 2"
  b4_has "b4/override: the refusal names the symlink" "symlink"
  # …and the sibling-prefix negative: /tmp/x must never vouch for /tmp/xy (trailing-slash match).
  mkdir -p "${b4_sand}y"; printf '1757900000 keyA 1 0\n' > "${b4_sand}y/t"
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
  # machine-wide tally permanently: every later read refuses and every session on the machine STOPs.
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
      sh "$b4_guard" step --config "$b4_cfg" --tally "$b4_tally" --tokens 5 --agents 0 \
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

# --- b4 leg helpers (oracle region) -------------------------------------------------------------
b4_mkcfg() { printf 'MAX_TOKENS=%s\nMAX_STEPS=%s\nMAX_AGENTS=%s\nWARN_PCT=%s\nCOST_PER_1K_USD=0.003\n' "$1" "$2" "$3" "$4" > "$b4_cfg"; }
# ⚠️ BOTH RUNNERS PIN $HOME INSIDE $tmp. The default tally is the REAL cross-session tally of the
# machine running this selftest; a leg that forgets an override must still be unable to touch it.
# b4_run_in also INJECTS the sandbox --config/--tally for the same reason (belt and braces: the leg
# that omitted them once did write to the developer's live tally before this was here).
b4_run()  { if b4_out=$(HOME="$tmp/hsafe" KIT_RUNAWAY_SANDBOX="$b4_sand" sh "$b4_guard" "$@" 2>&1); then b4_rc=0; else b4_rc=$?; fi; }
b4_run_in() {
  _d=$1; _c=$2; shift 2
  if b4_out=$( cd "$_d" && HOME="$tmp/hsafe" KIT_RUNAWAY_SANDBOX="$b4_sand" sh "$b4_guard" "$_c" \
                 --config "$b4_cfg" --tally "$b4_tally" "$@" 2>&1 ); then b4_rc=0; else b4_rc=$?; fi
}
# b4_run_home — NO override at all: the REAL default state dir + the REAL default config, with $HOME
# pointed inside the selftest's $tmp. The dial is UNSET so these legs also prove the default path.
b4_run_home() { _h=$1; shift; if b4_out=$( unset KIT_RUNAWAY_SANDBOX; HOME="$_h" sh "$b4_guard" "$@" 2>&1 ); then b4_rc=0; else b4_rc=$?; fi; }
# b4_run_nodial / b4_run_nodial_env — the dial UNSET. The env spellings are set on the command line
# rather than exported so the refusal under test is the one this leg names, and nothing leaks on.
b4_run_nodial() { if b4_out=$( unset KIT_RUNAWAY_SANDBOX; HOME="$tmp/hsafe" sh "$b4_guard" "$@" 2>&1 ); then b4_rc=0; else b4_rc=$?; fi; }
# b4_run_in2 — like b4_run_in but with the config and tally chosen per call (the R1/H2 leg needs its
# own read-only directory, which cannot be the shared fixture tally).
b4_run_in2() {
  _d=$1; _c=$2; _t=$3; _s=$4; shift 4
  if b4_out=$( cd "$_d" && HOME="$tmp/hsafe" KIT_RUNAWAY_SANDBOX="$b4_sand" sh "$b4_guard" "$_s" \
                 --config "$_c" --tally "$_t" "$@" 2>&1 ); then b4_rc=0; else b4_rc=$?; fi
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
