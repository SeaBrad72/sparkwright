#!/bin/sh
# checkout-lease.sh — lanes sharing ONE main checkout take it and return it themselves, with a lease
# (SWAS-192 slice A, card SWAS-809; design docs/architecture/2026-11-09-checkout-lease-192-design.md,
# errata docs/architecture/2026-11-09-checkout-lease-192a-errata.md, threat model beside them).
#
# THE PROBLEM THIS CLOSES. Every ref or tree write in the main checkout (claim, release, record, land,
# actuate, the fetch and the post-land pull) needed a START, GO, STOP round with the coordinator, who
# checked by hand that the checkout was on main, clean and at origin. Each of those checks is a `git`
# read. This verb makes them, and hands the holder a TOKEN the kit's own verbs check.
#
#   sh scripts/checkout-lease.sh acquire --holder <seat> --purpose <p> --pid <harness-pid> [--note <text>] [--lease checkout]
#   sh scripts/checkout-lease.sh release --lease-token <sha>
#   sh scripts/checkout-lease.sh sync    --lease-token <sha>
#   sh scripts/checkout-lease.sh held    --lease-token <sha>
#   sh scripts/checkout-lease.sh gate    [--lease-token <sha>] [--verb <name>]   (what the kit's verbs call)
#   sh scripts/checkout-lease.sh status  [--lease checkout]
#   sh scripts/checkout-lease.sh break   --reason <text, 20+ chars>
#   sh scripts/checkout-lease.sh acquire --lease land --purpose <land|actuate> --pid <pid> --lease-token <checkout token>   (a laptop)
#   sh scripts/checkout-lease.sh acquire --lease land --holder <seat> --purpose land --run <id>/<attempt> --expect-base <sha>   (CI)
#   sh scripts/checkout-lease.sh release --lease land --lease-token <land token> · status --lease land · break --lease land --reason <text>
#   sh scripts/checkout-lease.sh --selftest
#
# THE LAND LEASE (slice B, card SWAS-839) is the second lease: `refs/leases/land` ON ORIGIN, the one-holder lock for the merge. Taken by a plain
# push of an orphan commit (no `+`: the forge's refusal of a non-fast-forward is the lock) and returned by a leased delete; its log is
# `refs/leases-log/land`. `land` and `actuate` take and return it themselves (promotion-verify.sh); every read of it runs in a throwaway git dir.
# What reaches origin: the seat label, a random machine id (or `ci`), a pid and its start time, a run id, a fixed commit identity and, in the log,
# a proof label and a fixed reason code. Never a hostname, a git name or email, a note or a break's free-text reason (that stays in a local log).
#
# THE STORE. One local ref, `refs/local-lease/checkout`, in the repository's common git dir (worktrees
# share it), pointing at an ORPHAN commit whose single file `LEASE` records the holder blob. Taking it is
# `git update-ref <ref> <commit> <zero oid>`: create-only, so the ref's own compare-and-swap is the lock.
# The log is `refs/local-lease-log/checkout` (append-only; the LAST entry is the truth). The TOKEN is the
# lease commit's sha, printed by `acquire` and passed back to every later act; nothing a lane shares
# (`.kit-run/session.id` is per worktree) can stand in for it.
#
# OFF UNLESS A CHECKOUT OPTS IN. `git config kit.checkoutLease true`, a human act (the guard denies an
# agent's raw `git config` of the key). A checkout that was never enabled runs every verb as before. THE
# KEY FAILS CLOSED: once a lease or a lease-log ref exists here, a missing or false key refuses every
# lease-checking verb (a human restores it, or removes the key AND those refs together to roll back).
#
# EXIT CODES. acquire: 0 held (prints `lease-token: <sha>`) · 2 usage / not enabled / origin unreachable /
#   `--pid` is no ancestor · 3 HELD · 4 STALE (nothing changed) · 5 the checkout is not in a state to hold it.
#   release / sync: 0 · 1 wrong token or no lease · 2 usage / unreachable · 5 a state check failed (the lease
#   stays held). held / gate: 0 · 5 refused. status: 0 held · 1 free. break: 0 broken · 1 refused · 2 usage.
#   --lease land: acquire 0 held · 2 usage / origin unreachable / no stable read / `--run` in an opted-in checkout · 3 HELD ·
#   4 STALE (nothing changed) · 5 the checkout token is missing or wrong, or `--expect-base` is not origin's main. release: 0 · 1 wrong token, no
#   lease or the delete refused (the lease stays) · 2 usage / unreachable. status: 0 held · 1 free · 2 UNKNOWN (never read as free). break: as above.
#
# HONEST CEILING — read before quoting the word "lock".
#   * One holder AMONG COOPERATING CLIENTS. A same-user process is one `update-ref` away from overwriting
#     the ref, and the token is the ref's own sha, so it can read it with `git rev-parse` and replay it. The
#     token stops a lane acting on another lane's lease BY MISTAKE, not on purpose. A child commit of the
#     lease commit is a fast-forward: a plain push of one replaces the holder on origin (cell CL12c).
#   * `--holder` is DECLARED, NEVER AUTHENTICATED. It is read per call, never from a shared file.
#   * THE PID. `acquire` records the HARNESS session's process (`--pid`), never `$$`, which exits with the
#     call. The verb refuses unless `--pid` is an ancestor of itself (walked with `ps -o ppid=`). When the
#     walk CANNOT RUN (`ps` errors, or a parent link is unreadable before PID 1) the lease records
#     `pid: unproven`: usable, but no proof-of-death break is possible, only the human dial
#     KIT_LEASE_FORCE_BREAK. A walk that COMPLETES without meeting `--pid` refuses; it never falls back.
#     A lane that makes `ps` fail on purpose gets an unprovable lease: conduct, bounded by the ttl report
#     and the dial, no worse than a hung live holder.
#   * STALE means past `ttl-s`, which the VERB sets from the purpose. It is reported, never broken
#     silently. `break` needs STALE AND a proof (the holder is on this machine and its process, with its
#     start time, is gone). Age alone is never proof: a holder on another machine, a lost token or a hung
#     live process goes through the human dial KIT_LEASE_FORCE_BREAK, set in the human's own terminal. Its
#     reach is measured like KIT_CLAIM_FORCE_RELEASE's: the in-line prefix is denied to an agent, an
#     `export` as its own call or a copied script is NOT, and is pinned as such, never claimed closed.
#   * THE GUARD ARM IS HARNESS-LOCAL. Raw writes to the lease refs and to the key are denied to an agent
#     (R38); this verb's own writes pass by KIT_LEASE_FRONT_DOOR=1 in the guard's PROCESS environment. A
#     plain terminal is not graded.
#   * A raw `git fetch`, `checkout`, `pull` or an editing script in the main checkout is NOT refused: it is
#     detected at the next hand-over (a dirty tree, a moved HEAD), and is conduct until a seatbelt rule.
#
# POSIX sh; dash-clean. Every git write to a lease ref carries the inline `KIT_LEASE_FRONT_DOOR=1` prefix.
# What it changes: `acquire` writes refs/local-lease/checkout (create-only); `release`, `sync` (on a
#   diverged main) and `break` delete it, `sync` writes refs/local-lease/checkout-synced and runs
#   `git fetch origin main` plus `git merge --ff-only FETCH_HEAD`, `break` appends refs/local-lease-log/checkout
#   first; `status`, `held` and `gate` are read-only. The checkout lease pushes nothing. `--lease land`: `acquire` PUSHES an orphan commit to
#   refs/leases/land on origin, `release` and `break` DELETE it there (a leased delete), `break` and a refused release PUSH an entry to
#   refs/leases-log/land first, `acquire` writes one file `kit-lease-machine` (the random machine id) and `kit-lease-host` (a sha256 of a
#   hardware id, never the id itself and never pushed) in the common git dir and `break` appends a line to `kit-lease-break.log` there; `status` is read-only.
# Land guardrails: no `+` on the push; the delete is `--force-with-lease=<ref>:<observed sha>`, so a lease that moved is left alone; an
#   unreachable origin is never read as free; the fetched commit must equal the sha read; every read runs in a throwaway git dir (the
#   checkout gets no `.git/shallow`, object or FETCH_HEAD); `--run` is refused in a checkout that opted in; a finished run proves a CI holder gone
#   only when it is the train's, on main, not a PR event, created before and finished after the lease; the log entry is pushed before the delete.
# Guardrails: off unless a person sets `git config kit.checkoutLease true`, and fail-closed once the lease has been used; create-only compare-and-swap on the lease ref, every write `update-ref --no-deref`; the token is checked against the ref's own sha; `acquire` refuses off main, on a dirty tree, ahead of or diverged from origin, or with origin unreachable, and re-checks after the write; a `--pid` that is no ancestor is refused; `break` needs STALE plus a proof of death, or the human dial KIT_LEASE_FORCE_BREAK, and is logged first; the LEASE blob is bounded, printable-only and never eval'd; holder, note and hostname are grammar-checked. A same-user process can still replay the token: one holder among cooperating clients, not a lock.
set -eu
LC_ALL=C
export LC_ALL

# SWAS-903: the CI-holder proof below reaches gh. Inside the macOS agent sandbox a bare gh fails TLS (x509 OSStatus -26276); scripts/gh-tls.sh sets the system
# bundle for this process only on that signature (one probe, right before the gh call). A missing library means no probe: today's behaviour. A lease reached
# through promotion-verify.sh already inherits the pin (the probe there returns at once).
_cl_ghtls=$(dirname -- "$0")/gh-tls.sh
# shellcheck source=scripts/gh-tls.sh
if [ -f "$_cl_ghtls" ]; then . "$_cl_ghtls"; fi

CL_REF="refs/local-lease/checkout"
CL_SYNCED="refs/local-lease/checkout-synced"
CL_LOG="refs/local-lease-log/checkout"
CL_USED="refs/local-lease-log/used"
# SWAS-192 slice B (SWAS-839): the LAND lease lives on ORIGIN, not in this repository: `refs/leases/land` (an orphan commit, taken by a
# plain non-`+` push, so the forge's non-fast-forward refusal is the lock) and its log `refs/leases-log/land`. Every read of it goes
# through an ISOLATED throwaway git dir (CL_GD), never the caller's clone, so no `.git/shallow`, object or FETCH_HEAD is written here.
CL_LREF="refs/leases/land"
CL_LLOG="refs/leases-log/land"
CL_TRAIN_WORKFLOW="train"   # the land train's workflow name, the only workflow whose finished run proves a CI holder gone (57d sets the real name)
CL_LNAME=checkout   # which lease this call is about: checkout (local, slice A) or land (origin, slice B)
CL_GD=""            # the throwaway git dir the current land-lease read or write works in; empty = the caller's repository
CL_ISOROOT=""       # the root of those dirs, made in the parent shell by cl_land_init and removed by the EXIT trap

cl_err() { printf 'lease: %s\n' "$1" >&2; }
# Printable ASCII only: a control byte, and any byte from 0x80 up (a bidi override survives a `[:cntrl:]` strip), never reaches a terminal or the log.
cl_clean() { printf '%s' "$1" | LC_ALL=C tr -cd '[:print:]'; }   # MUT-CLEAN
# The hostname, held to the blob's machine grammar at WRITE (a name outside [A-Za-z0-9._-] would make every lease read MALFORMED).
cl_machine() { _hm=$(printf '%s' "$(uname -n)" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_'); printf '%s' "${_hm:-unknown}"; }
cl_usage() {
  echo "usage:" >&2
  echo "  checkout-lease.sh acquire --holder <seat> --purpose <claim|record|land|actuate|sync|prepush|other> --pid <harness-pid> [--note <text>]" >&2
  echo "  checkout-lease.sh release --lease-token <sha>" >&2
  echo "  checkout-lease.sh sync    --lease-token <sha>" >&2
  echo "  checkout-lease.sh held    --lease-token <sha>" >&2
  echo "  checkout-lease.sh gate    [--lease-token <sha>] [--verb <name>]" >&2
  echo "  checkout-lease.sh status" >&2
  echo "  checkout-lease.sh break   --reason <text, 20+ chars>" >&2
  echo "  checkout-lease.sh acquire --lease land --purpose <land|actuate> --pid <pid> --lease-token <checkout token>   (a laptop; the holder is the checkout lease's)" >&2
  echo "  checkout-lease.sh acquire --lease land --holder <seat> --purpose land --run <id>/<attempt> --expect-base <sha>   (CI; a checkout that never opted in)" >&2
  echo "  checkout-lease.sh release|status|break --lease land   (release needs --lease-token <land token>)" >&2
  echo "  checkout-lease.sh --selftest" >&2
}

# The zero object id of this repository's hash (40 or 64 zeros): the old value that makes update-ref create-only.
cl_zero() { printf '' | git hash-object --stdin | tr '0-9a-f' '0'; }

# ── GRAMMARS — every value is checked at the front door and again when read back ─────────────────
cl_token_ok() {
  case "$1" in ''|*[!0-9a-f]*) return 1 ;; esac
  [ "${#1}" -eq 40 ] || [ "${#1}" -eq 64 ]
}
cl_holder_ok() { # [A-Za-z0-9 ._-]{1,40}; a newline or a control byte is outside the set
  case "$1" in
    '') return 1 ;;
    *[!A-Za-z0-9' '._-]*) return 1 ;;
  esac
  [ "${#1}" -le 40 ]
}
cl_lane_ok() { # when .kit/lanes.conf exists (one lane per line, # comments) the name must be one of its lanes
  _lf="$(git rev-parse --show-toplevel 2>/dev/null)/.kit/lanes.conf"
  [ -f "$_lf" ] || return 0
  grep -v '^#' "$_lf" | grep -qxF -- "$1"
}
cl_purpose_ok() { case "$1" in claim|record|land|actuate|sync|prepush|other) return 0 ;; esac; return 1; }
cl_ttl() { case "$1" in actuate) echo 1200 ;; land) echo 2700 ;; prepush) echo 2400 ;; *) echo 600 ;; esac; }

# ── ENABLED? on · off · missing ──────────────────────────────────────────────────────────────────
# `missing` is the fail-closed answer: the checkout used the lease (a lease or a log ref exists) but the key is gone.
cl_state() {
  _kv=$(git config --local --get kit.checkoutLease 2>/dev/null || true)
  if [ "$_kv" = true ]; then echo on; return 0; fi   # MUT-ENABLED
  if [ -n "$(git for-each-ref --count=1 refs/local-lease/ refs/local-lease-log/ 2>/dev/null)" ]; then echo missing; return 0; fi   # MUT-LOGREF
  echo off
}
cl_need_on() { # <verb> -> rc 0 on · 2 refused (sentence printed)
  case "$(cl_state)" in
    on) return 0 ;;
    missing)
      cl_err "$1: REFUSED — kit.checkoutLease is missing in a checkout that has used the lease; a human restores it (git config kit.checkoutLease true), or rolls back by removing the key and every refs/local-lease* ref together."
      return 2 ;;
    *)
      cl_err "$1: REFUSED — the checkout lease is not enabled here. A human opts this checkout in with: git config kit.checkoutLease true"
      return 2 ;;
  esac
}

# ── THE LEASE BLOB — untrusted text: bounded, printable only, fixed field names, never eval'd ─────
cl_f() { printf '%s\n' "$CL_TXT" | sed -n "s/^$1: //p" | head -1; }
# cl_g <git args> -> git in the throwaway dir (CL_GD) when a land-lease call set one, else in the caller's repository
cl_g() { git -C "${CL_GD:-.}" "$@"; }
# cl_run_ok <run> -> rc 0 when it is `<run id>/<attempt>`: [0-9]{1,20}/[0-9]{1,3}, nothing else (it becomes `gh` argv)
cl_run_ok() {
  case "$1" in */*) ;; *) return 1 ;; esac
  _ri=${1%%/*}; _ra=${1#*/}
  case "$_ri" in ''|*[!0-9]*) return 1 ;; esac
  case "$_ra" in ''|*[!0-9]*) return 1 ;; esac
  [ "${#_ri}" -le 20 ] && [ "${#_ra}" -le 3 ]
}
# cl_load <sha> -> sets CL_* from the LEASE blob; rc 1 when it is unreadable or malformed
cl_load() {
  CL_TXT=""
  _sz=$(cl_g cat-file -s "$1:LEASE" 2>/dev/null) || return 1
  case "$_sz" in ''|*[!0-9]*) return 1 ;; esac
  [ "$_sz" -le 4096 ] || return 1   # MUT-SIZE
  CL_TXT=$(cl_g cat-file blob "$1:LEASE" 2>/dev/null | head -c 4096) || return 1
  [ -z "$(printf '%s' "$CL_TXT" | tr -d '[:print:]\n')" ] || return 1
  [ "$(cl_f lease)" = "$CL_LNAME" ] || return 1
  CL_HOLDER=$(cl_f holder); CL_PURPOSE=$(cl_f purpose); CL_MACHINE=$(cl_f machine)
  CL_PID=$(cl_f pid); CL_PIDSTART=$(cl_f pid-start); CL_TTL=$(cl_f ttl-s)
  CL_BEHINDF=$(cl_f behind); CL_NOTE=$(cl_f note); CL_RUN=$(cl_f run)
  cl_holder_ok "$CL_HOLDER" || return 1
  cl_purpose_ok "$CL_PURPOSE" || return 1
  case "$CL_TTL" in ''|*[!0-9]*) return 1 ;; esac
  [ "${#CL_TTL}" -le 6 ] || return 1
  case "$CL_PID" in unproven) ;; ''|*[!0-9]*) return 1 ;; esac
  case "$CL_MACHINE" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
  [ "${#CL_PIDSTART}" -le 64 ] || return 1
  if [ "$CL_LNAME" = land ]; then
    # the land lease: no `behind` field and no `note` on origin; the machine is a 16-hex id or `ci`; a `run` is held to its grammar
    case "$CL_MACHINE" in ci) ;; *[!0-9a-f]*) return 1 ;; *) [ "${#CL_MACHINE}" -eq 16 ] || return 1 ;; esac
    [ -z "$CL_RUN" ] || cl_run_ok "$CL_RUN" || return 1   # MUT-LRUN
    CL_BEHINDF=no
    return 0
  fi
  case "$CL_BEHINDF" in yes|no) ;; *) return 1 ;; esac
  return 0
}
# cl_read -> sets CL_SHA (the ref's commit, empty when no lease) and, when one exists, loads it; CL_MAL=1 when malformed
cl_read() {
  CL_MAL=0
  CL_SHA=$(git rev-parse --verify -q "$CL_REF" 2>/dev/null || true)
  [ -n "$CL_SHA" ] || return 1
  if ! cl_load "$CL_SHA"; then CL_MAL=1; fi
  return 0
}
cl_now() { date +%s; }
cl_ctime() { # <sha> -> the lease commit's date (epoch seconds), 0 when unreadable
  _ctv=$(cl_g show -s --format=%ct "$1" 2>/dev/null) || _ctv=0
  case "$_ctv" in ''|*[!0-9]*) _ctv=0 ;; esac
  printf '%s' "$_ctv"
}
cl_age() { # <sha> -> seconds since the lease commit was written; a commit dated more than 300 s in the future reads as ancient (STALE, age only), never as live forever
  _ct=$(cl_ctime "$1")
  _now=$(cl_now)
  if [ "$_ct" -gt $((_now + 300)) ]; then echo 999999999; return 0; fi   # MUT-FUTURE
  _ag=$((_now - _ct)); [ "$_ag" -ge 0 ] || _ag=0
  echo "$_ag"
}
# The start time is read in UTC (`ps` prints lstart in the caller's time zone, so another TZ would read a live holder as a reused pid).
cl_lstart() { TZ=UTC0 ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed 's/^ //;s/ $//'; }   # MUT-TZ

# cl_proof -> sets CL_PROOF (non-empty = the holder is provably gone, and why) and CL_WHY (why there is no proof)
cl_proof() {
  CL_PROOF=""; CL_WHY=""
  if [ "$CL_LNAME" = land ] && [ -n "$CL_RUN" ]; then cl_ciproof; return 0; fi   # a CI holder: the forge says whether its run is over
  if [ "$CL_MACHINE" != "$(cl_mymachine)" ]; then CL_WHY="the holder is on another machine"; return 0; fi   # MUT-LMACH
  case "$CL_PID" in unproven) CL_WHY="pid unproven"; return 0 ;; esac   # MUT-UNPROVEN
  if [ -z "$(ps -o pid= -p $$ 2>/dev/null)" ]; then CL_WHY="ps cannot be read here"; return 0; fi
  _live=$(ps -o pid= -p "$CL_PID" 2>/dev/null | tr -d ' ')
  if [ -z "$_live" ] && ! kill -0 "$CL_PID" 2>/dev/null; then CL_PROOF="the session process $CL_PID is not running"; return 0; fi
  _ls=$(cl_lstart "$CL_PID")
  # a recorded "(none)" is no start time to compare with: it proves nothing either way
  if [ -n "$_ls" ] && [ "$CL_PIDSTART" != "(none)" ] && [ "$_ls" != "$CL_PIDSTART" ]; then CL_PROOF="pid $CL_PID is running with another start time (a reused pid)"; return 0; fi   # MUT-PIDSTART
  CL_WHY="the session process is still running"
}
# cl_classify -> sets CL_CLASS (LIVE | STALE-AGE | STALE-PROVEN), CL_AGE; needs a loaded, well-formed lease
cl_classify() {
  CL_AGE=$(cl_age "$CL_SHA")
  if [ "$CL_LNAME" = land ]; then
    # B3/B8: a land holder PROVEN gone is stale at any age (its process is dead on this machine, or its CI run has concluded)
    cl_proof
    if [ -n "$CL_PROOF" ]; then CL_CLASS=STALE-PROVEN; return 0; fi   # MUT-LANYAGE
    if [ "$CL_AGE" -le "$CL_TTL" ]; then CL_CLASS=LIVE; else CL_CLASS=STALE-AGE; fi
    return 0
  fi
  if [ "$CL_AGE" -le "$CL_TTL" ]; then CL_CLASS=LIVE; return 0; fi
  cl_proof
  if [ -n "$CL_PROOF" ]; then CL_CLASS=STALE-PROVEN; else CL_CLASS=STALE-AGE; fi
}
cl_held_line() { # the one line a refused lane reads
  printf 'HELD by "%s" (%s, %s min of %s)' "$CL_HOLDER" "$CL_PURPOSE" "$((CL_AGE / 60))" "$((CL_TTL / 60))"
}
# cl_behind -> rc 0 when the loaded lease is still BEHIND (acquired while origin's main was not local main, and not yet synced)
cl_behind() {
  [ "$CL_BEHINDF" = yes ] || return 1   # MUT-BEHIND
  [ "$(git rev-parse --verify -q "$CL_SYNCED" 2>/dev/null || true)" != "$CL_SHA" ]
}

# ── THE STATE CHECKS (design section 3, checks 2-4) ──────────────────────────────────────────────
cl_tree_checks() { # rc 0 ok · 5 refused (sentence printed)
  _br=$(git symbolic-ref --short HEAD 2>/dev/null || true)
  if [ "$_br" != main ]; then
    cl_err "REFUSED — this checkout is on '$(cl_clean "${_br:-a detached HEAD}")', not main. The lease is for the main checkout: switch to main and retry. Nothing was written."
    return 5
  fi
  _st=$(git status --porcelain --untracked-files=normal 2>/dev/null) || { cl_err "REFUSED — git status could not be read. Nothing was written."; return 5; }
  if [ -n "$_st" ]; then   # MUT-DIRTY
    cl_err "REFUSED — the tree is not clean ($(printf '%s\n' "$_st" | wc -l | tr -d ' ') path(s) changed or untracked). Commit, stash or remove them and retry. Nothing was written."
    return 5
  fi
  return 0
}
cl_origin() { # -> sets CL_OSHA, rc 2 when origin's main cannot be read
  CL_OSHA=""
  _o=$(git ls-remote --exit-code origin refs/heads/main 2>/dev/null) || return 2   # MUT-UNREACH
  _o=${_o%%[[:space:]]*}
  case "$_o" in ''|*[!0-9a-f]*) return 2 ;; esac
  CL_OSHA=$_o
}
# cl_origin_check <acquire|release> -> rc 0 ok (sets CL_BEHINDNOW yes|no) · 2 unreachable · 5 refused
cl_origin_check() {
  if ! cl_origin; then
    cl_err "REFUSED — origin is unreachable, or has no main; the lease needs origin's main to be readable. Nothing was written."
    return 2
  fi
  CL_WANT=$CL_OSHA   # MUT-RELBASE
  _lm=$(git rev-parse --verify -q refs/heads/main 2>/dev/null || true)
  CL_BEHINDNOW=no
  if [ "$_lm" = "$CL_WANT" ]; then return 0; fi
  if [ "$1" = release ]; then
    cl_err "REFUSED — local main ($(printf '%.12s' "$_lm")) is not origin's main ($(printf '%.12s' "$CL_OSHA")): run 'sparkwright lease sync --lease-token <token>' first. The lease stays held."
    return 5
  fi
  if git cat-file -e "$CL_OSHA^{commit}" 2>/dev/null; then
    if git merge-base --is-ancestor "$_lm" "$CL_OSHA" 2>/dev/null; then CL_BEHINDNOW=yes; return 0; fi
    cl_err "REFUSED — local main is ahead of origin's main, or has diverged from it. A human repairs that (push it, or reset it) before any lease. Nothing was written."
    return 5
  fi
  # origin's main is not an object here: a fetch is a ref write and needs the lease, so record BEHIND; the first act is `sync`
  CL_BEHINDNOW=yes
  return 0
}

# ── WRITING THE LEASE ────────────────────────────────────────────────────────────────────────────
cl_ct() { # <tree> [<parent>]; the message on stdin; prints the commit
  _cn=$(git config user.name 2>/dev/null || true); [ -n "$_cn" ] || _cn=kit
  _ce=$(git config user.email 2>/dev/null || true); [ -n "$_ce" ] || _ce=kit@local
  # the land lease is readable by everyone who reads origin: a fixed identity, never the person's git name or email (B4)
  if [ "$CL_LNAME" = land ]; then _cn=kit; _ce=kit@lease.invalid; fi   # MUT-LIDENT
  # the dates are set to NOW, so an ambient GIT_COMMITTER_DATE cannot future-date a lease (its age is read from the commit date)
  _cd="$(cl_now) +0000"   # MUT-CTDATE
  if [ -n "${2:-}" ]; then
    GIT_AUTHOR_NAME=$_cn GIT_AUTHOR_EMAIL=$_ce GIT_COMMITTER_NAME=$_cn GIT_COMMITTER_EMAIL=$_ce GIT_AUTHOR_DATE=$_cd GIT_COMMITTER_DATE=$_cd git -C "${CL_GD:-.}" commit-tree "$1" -p "$2"
  else
    GIT_AUTHOR_NAME=$_cn GIT_AUTHOR_EMAIL=$_ce GIT_COMMITTER_NAME=$_cn GIT_COMMITTER_EMAIL=$_ce GIT_AUTHOR_DATE=$_cd GIT_COMMITTER_DATE=$_cd git -C "${CL_GD:-.}" commit-tree "$1"
  fi
}
cl_drop() { # <expected-sha> -> delete the lease and its synced marker, only while the ref still holds that sha
  # --no-deref everywhere: a symbolic ref planted at these names would otherwise be written or deleted THROUGH to its target
  KIT_LEASE_FRONT_DOOR=1 git update-ref --no-deref -d "$CL_REF" "$1" 2>/dev/null || return 1
  KIT_LEASE_FRONT_DOOR=1 git update-ref --no-deref -d "$CL_SYNCED" 2>/dev/null || true
  return 0
}
# cl_log_break <proof> <reason> <released-sha> -> appends one entry to the log (a child of the last), CAS on its tip
cl_log_break() {
  _ltip=$(git rev-parse --verify -q "$CL_LOG" 2>/dev/null || true)
  _lblob=$(printf 'at: %s\nproof: %s\nreason: %s\nold-holder: %s\nold-purpose: %s\nold-machine: %s\nold-pid: %s\nreleased-sha: %s\n' \
             "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$(cl_clean "$2" | cut -c1-200)" "$CL_HOLDER" "$CL_PURPOSE" "$CL_MACHINE" "$CL_PID" "$3" \
           | git hash-object -w --stdin) || return 1
  _ltree=$(printf '100644 blob %s\tLOG\n' "$_lblob" | git mktree) || return 1
  _lcommit=$(printf 'break (%s)\n' "$1" | cl_ct "$_ltree" "$_ltip") || return 1
  KIT_LEASE_FRONT_DOOR=1 git update-ref --no-deref "$CL_LOG" "$_lcommit" "${_ltip:-$(cl_zero)}" 2>/dev/null
}

# ── acquire ──────────────────────────────────────────────────────────────────────────────────────
# cl_acquire_checks -> the tree, then origin, checks (also run again after the write)
cl_acquire_checks() { cl_tree_checks || return $?; cl_origin_check acquire; }
# cl_walk <pid> -> rc 0 it is an ancestor · 1 the walk completed without meeting it · 2 the walk could not run
cl_walk() {
  _wp=$$; _hops=0
  while [ "$_hops" -lt 64 ]; do
    _wpp=$(ps -o ppid= -p "$_wp" 2>/dev/null) || return 2
    _wpp=$(printf '%s' "$_wpp" | tr -d ' ')
    case "$_wpp" in ''|*[!0-9]*) return 2 ;; esac
    if [ "$_wpp" = "$1" ]; then return 0; fi
    if [ "$_wpp" -le 1 ]; then return 1; fi
    _wp=$_wpp; _hops=$((_hops + 1))
  done
  return 2
}
cl_lease_ok() { # <name> -> rc 0 checkout · 2 anything else
  case "$1" in
    checkout) CL_LNAME=checkout; return 0 ;;
    land) CL_LNAME=land; return 0 ;;
    *) cl_err "unknown lease '$(cl_clean "$1")' (checkout)"; return 2 ;;
  esac
}
cl_acquire() {
  _holder=""; _purpose=""; _pidarg=""; _note=""; _run=""; _xbase=""; _ctok=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --run)         [ $# -ge 2 ] || { cl_err "acquire: --run needs a value"; return 2; }; _run=$2; shift 2 ;;
      --expect-base) [ $# -ge 2 ] || { cl_err "acquire: --expect-base needs a value"; return 2; }; _xbase=$2; shift 2 ;;
      --lease-token) [ $# -ge 2 ] || { cl_err "acquire: --lease-token needs a value"; return 2; }; _ctok=$2; shift 2 ;;
      --holder)  [ $# -ge 2 ] || { cl_err "acquire: --holder needs a value"; return 2; }; _holder=$2; shift 2 ;;
      --purpose) [ $# -ge 2 ] || { cl_err "acquire: --purpose needs a value"; return 2; }; _purpose=$2; shift 2 ;;
      --pid)     [ $# -ge 2 ] || { cl_err "acquire: --pid needs a value"; return 2; }; _pidarg=$2; shift 2 ;;
      --note)    [ $# -ge 2 ] || { cl_err "acquire: --note needs a value"; return 2; }; _note=$2; shift 2 ;;
      --lease)   [ $# -ge 2 ] || { cl_err "acquire: --lease needs a value"; return 2; }; cl_lease_ok "$2" || return 2; shift 2 ;;
      *) cl_err "acquire: unknown option '$(cl_clean "$1")'"; cl_usage; return 2 ;;
    esac
  done
  if [ "$CL_LNAME" = land ]; then cl_lacquire; return $?; fi
  if [ -n "$_run$_xbase$_ctok" ]; then cl_err "acquire: --run, --expect-base and --lease-token are for --lease land."; return 2; fi
  if ! cl_holder_ok "$_holder"; then
    cl_err "acquire: --holder must match [A-Za-z0-9 ._-]{1,40} (one line, no control bytes)."; return 2
  fi
  if ! cl_lane_ok "$_holder"; then cl_err "acquire: '$_holder' is not a lane named in .kit/lanes.conf."; return 2; fi
  cl_purpose_ok "$_purpose" || { cl_err "acquire: --purpose is one of claim, record, land, actuate, sync, prepush, other."; return 2; }
  if [ "${#_note}" -gt 80 ] || [ -n "$(printf '%s' "$_note" | tr -d '[:print:]')" ]; then
    cl_err "acquire: --note is at most 80 printable bytes on one line."; return 2
  fi
  case "$_pidarg" in ''|*[!0-9]*) cl_err "acquire: --pid names the harness session's process (digits)."; return 2 ;; esac
  [ "$_pidarg" -gt 1 ] || { cl_err "acquire: --pid must be a process above PID 1."; return 2; }
  cl_need_on acquire || return 2

  _zero=$(cl_zero)
  _crc=0; cl_acquire_checks || _crc=$?
  if [ "$_crc" != 0 ]; then
    # a holder that is working in the tree leaves it dirty: when a lease exists, say HELD rather than the dirt
    if [ "$_crc" = 5 ] && cl_read && [ "$CL_MAL" = 0 ]; then cl_classify; cl_err "$(cl_held_line); retry after it is released, or ask the coordinator if it goes STALE"; [ "$CL_CLASS" = LIVE ] && return 3; return 4; fi
    return "$_crc"
  fi
  _behind=$CL_BEHINDNOW; _base=$CL_OSHA

  # the recorded process is the harness ancestor, never `$$`
  _pidrec=unproven; _pidstart="(none)"
  _wrc=0; cl_walk "$_pidarg" || _wrc=$?
  case "$_wrc" in
    0) _pidrec=$_pidarg; _pidstart=$(cl_lstart "$_pidarg"); [ -n "$_pidstart" ] || _pidstart="(none)" ;;   # MUT-PIDSELF
    1) cl_err "acquire: --pid $_pidarg is not an ancestor of this process; the lease records the harness session's process. Nothing was written."; return 2 ;;   # MUT-NONANC
    *) _pidrec=unproven; _pidstart="(none)" ;;
  esac

  _blob=$( { printf 'lease: checkout\nholder: %s\npurpose: %s\n' "$_holder" "$_purpose"
             [ -z "$_note" ] || printf 'note: %s\n' "$_note"
             printf 'machine: %s\npid: %s\npid-start: %s\nacquired-at: %s\nttl-s: %s\nbase: %s\nbehind: %s\n' \
               "$(cl_machine)" "$_pidrec" "$_pidstart" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(cl_ttl "$_purpose")" "$_base" "$_behind"
           } | git hash-object -w --stdin) || { cl_err "acquire: could not write the lease blob."; return 2; }
  _tree=$(printf '100644 blob %s\tLEASE\n' "$_blob" | git mktree) || { cl_err "acquire: could not write the lease tree."; return 2; }
  _commit=$(printf 'checkout lease: %s (%s)\n' "$_holder" "$_purpose" | cl_ct "$_tree") || { cl_err "acquire: could not write the lease commit."; return 2; }

  # THE COMPARE-AND-SWAP: create-only (the zero oid is the old value), so a second writer is refused by the ref itself
  if KIT_LEASE_FRONT_DOOR=1 git update-ref --no-deref "$CL_REF" "$_commit" "$_zero" 2>/dev/null; then   # MUT-CAS
    # THE "USED" MARKER: a durable ref under refs/local-lease-log/ that release does not delete, so a checkout that only ever acquired
    # and released still reads as "has used the lease" when the key is removed (the fail-closed test looks for any ref there). It is
    # written once the lease is taken; a marker that cannot be written drops the lease and refuses.
    if ! KIT_LEASE_FRONT_DOOR=1 git update-ref --no-deref "$CL_USED" "$_commit" 2>/dev/null; then   # MUT-USED
      cl_drop "$_commit" || true
      cl_err "REFUSED — the 'used' marker $CL_USED could not be written, so the lease was released. Nothing is held."
      return 2
    fi
  else
    if cl_read && [ "$CL_MAL" = 0 ]; then
      cl_classify
      cl_err "$(cl_held_line); retry after it is released, or ask the coordinator if it goes STALE"
      [ "$CL_CLASS" = LIVE ] && return 3
      cl_err "this lease is past its ttl and is reported, never broken silently: 'sparkwright lease status' reads it, 'break' needs a proof of death."   # MUT-AUTOBREAK
      return 4
    fi
    cl_err "REFUSED — a lease exists at $CL_REF but its LEASE is unreadable or malformed; a human clears it. Nothing was changed."
    return 3
  fi
  # THE RE-CHECK (CL5): the tree or origin may have changed between the check and the write
  if ! cl_acquire_checks; then   # MUT-RECHECK
    cl_drop "$_commit" || true
    cl_err "REFUSED — the checkout changed between the check and the write; the lease just taken was released. Retry."
    return 5
  fi
  printf 'lease-token: %s\n' "$_commit"
  printf 'lease: acquired by "%s" for %s (ttl %s min); keep the token, pass it to every act, and release it when done.\n' "$_holder" "$_purpose" "$(( $(cl_ttl "$_purpose") / 60 ))"
  if [ "$_pidrec" = unproven ]; then printf 'lease: pid unproven (the parent chain could not be read): no proof-of-death break is possible for this lease.\n'; fi
  if [ "$_behind" = yes ]; then printf "lease: BEHIND — origin's main moved since this checkout last fetched; run 'sparkwright lease sync --lease-token %s' first.\n" "$_commit"; fi
  return 0
}

# ── token verbs ──────────────────────────────────────────────────────────────────────────────────
# cl_tokarg <verb> <args...> -> sets _tok; rc 2 on a bad option or token
cl_tokarg() {
  _verb=$1; shift; _tok=""; _vname=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --lease-token) [ $# -ge 2 ] || { cl_err "$_verb: --lease-token needs a value"; return 2; }; _tok=$2; shift 2 ;;
      --verb)        [ $# -ge 2 ] || { cl_err "$_verb: --verb needs a value"; return 2; }; _vname=$(cl_clean "$2" | cut -c1-40); shift 2 ;;
      --lease)       [ $# -ge 2 ] || { cl_err "$_verb: --lease needs a value"; return 2; }; cl_lease_ok "$2" || return 2; shift 2 ;;
      *) cl_err "$_verb: unknown option '$(cl_clean "$1")'"; cl_usage; return 2 ;;
    esac
  done
  if [ "$CL_LNAME" = land ]; then
    case "$_verb" in release|status) ;; *) cl_err "$_verb: --lease land is for acquire, release, status and break."; return 2 ;; esac
  fi
  return 0
}
# cl_match <token> -> rc 0 when the token equals the ref's commit
cl_match() { [ "$1" = "$CL_SHA" ]; }   # MUT-TOKEN

cl_release() {
  cl_tokarg release "$@" || return 2
  if [ "$CL_LNAME" = land ]; then cl_lrelease; return $?; fi
  cl_token_ok "$_tok" || { cl_err "release: --lease-token <sha> is required."; return 2; }
  cl_need_on release || return 2
  if ! cl_read; then cl_err "release: no lease is held; nothing to release."; return 1; fi
  if [ "$CL_MAL" = 1 ]; then cl_err "release: the lease's LEASE is unreadable or malformed; a human clears $CL_REF."; return 1; fi
  if ! cl_match "$_tok"; then cl_classify; cl_err "release: REFUSED — that is not the holder's token. $(cl_held_line)."; return 1; fi
  cl_tree_checks || return $?
  cl_origin_check release || return $?
  if cl_drop "$CL_SHA"; then
    printf 'lease: released (%s, was held by "%s").\n' "$CL_PURPOSE" "$CL_HOLDER"
    return 0
  fi
  cl_err "release: FAILED — the lease could not be deleted (the ref moved, or the delete was refused). It is still held."
  return 1
}

cl_sync() {
  cl_tokarg sync "$@" || return 2
  cl_token_ok "$_tok" || { cl_err "sync: --lease-token <sha> is required."; return 2; }
  cl_need_on sync || return 2
  if ! cl_read; then cl_err "sync: no lease is held; run 'sparkwright lease acquire' first."; return 1; fi
  if [ "$CL_MAL" = 1 ]; then cl_err "sync: the lease's LEASE is unreadable or malformed; a human clears $CL_REF."; return 1; fi
  if ! cl_match "$_tok"; then cl_classify; cl_err "sync: REFUSED — that is not the holder's token. $(cl_held_line)."; return 1; fi
  cl_tree_checks || return $?
  if ! git fetch -q origin main 2>/dev/null; then cl_err "sync: origin is unreachable; nothing was changed."; return 2; fi
  if ! git merge -q --ff-only FETCH_HEAD >/dev/null 2>&1; then
    cl_drop "$CL_SHA" || true
    cl_err "sync: REFUSED — local main has diverged from origin's main (a fast-forward is impossible). The lease was released. A human repairs main (push or reset it), then acquires again."
    return 5
  fi
  KIT_LEASE_FRONT_DOOR=1 git update-ref --no-deref "$CL_SYNCED" "$CL_SHA" 2>/dev/null || { cl_err "sync: could not record the sync."; return 2; }
  printf 'lease: synced — local main is origin'"'"'s main (%s).\n' "$(printf '%.12s' "$(git rev-parse --verify -q refs/heads/main)")"
  return 0
}

cl_held() {
  cl_tokarg held "$@" || return 2
  cl_token_ok "$_tok" || { cl_err "held: --lease-token <sha> is required."; return 5; }
  cl_read || return 5
  [ "$CL_MAL" = 0 ] || return 5
  cl_match "$_tok" || return 5
  if cl_behind; then return 5; fi
  return 0
}

# cl_gate — what the kit's ref-writing verbs call first. off -> proceed; on -> the holder's token is required.
cl_gate() {
  cl_tokarg gate "$@" || return 2
  _gv=${_vname:-this act}
  case "$(cl_state)" in
    off) return 0 ;;
    missing)
      cl_err "$_gv: REFUSED — kit.checkoutLease is missing in a checkout that has used the lease; a human restores it (git config kit.checkoutLease true), or rolls back by removing the key and every refs/local-lease* ref together."
      return 5 ;;
  esac
  _next="this act needs the checkout lease's token; run 'sparkwright lease acquire' and pass --lease-token"
  if cl_read && [ "$CL_MAL" = 0 ]; then cl_classify; _holdl="$(cl_held_line). "; else _holdl=""; fi
  if ! cl_token_ok "$_tok"; then cl_err "$_gv: REFUSED — ${_holdl}${_next}."; return 5; fi
  if [ -z "$CL_SHA" ] || [ "$CL_MAL" = 1 ]; then cl_err "$_gv: REFUSED — no readable lease is held; ${_next}."; return 5; fi
  if ! cl_match "$_tok"; then cl_err "$_gv: REFUSED — that is not the holder's token. ${_holdl}${_next}."; return 5; fi
  if cl_behind; then cl_err "$_gv: REFUSED — the lease is BEHIND origin's main; run 'sparkwright lease sync --lease-token <token>' first."; return 5; fi
  return 0
}

# cl_doctor_line — the line `sparkwright doctor` prints: on · off · FAIL (rc 1) when the key is gone beside a lease or lease-log ref
cl_doctor_line() {
  case "$(cl_state)" in
    on) echo "lease: on" ;;
    missing)
      echo "lease: FAIL - kit.checkoutLease is missing in a checkout that has used the lease (a lease or lease-log ref remains). A person restores it (git config kit.checkoutLease true), or rolls back by removing the key and every refs/local-lease* ref together."
      return 1 ;;
    *) echo "lease: off (no key, no lease log)" ;;
  esac
}

# ── status and break ─────────────────────────────────────────────────────────────────────────────
cl_status() {
  cl_tokarg status "$@" || return 2
  if [ "$CL_LNAME" = land ]; then cl_lstatus; return $?; fi
  if [ "$(cl_state)" = missing ]; then cl_err "WARNING — kit.checkoutLease is missing in a checkout that has used the lease; a human restores it."; fi
  if ! cl_read; then echo "lease: FREE (checkout)"; return 1; fi
  if [ "$CL_MAL" = 1 ]; then
    echo "lease: MALFORMED — $CL_REF exists but its LEASE is unreadable, too long, or not plain text; it is not shown. A human clears it."
    return 0
  fi
  cl_classify
  echo "lease: $(cl_held_line)"
  [ -z "$CL_NOTE" ] || echo "  note: $CL_NOTE"
  echo "  machine: $CL_MACHINE · age: ${CL_AGE}s · ttl: ${CL_TTL}s"
  case "$CL_CLASS" in
    LIVE)         echo "  reading: LIVE" ;;
    STALE-AGE)    echo "  reading: STALE (age only: $CL_WHY); a break needs the human dial KIT_LEASE_FORCE_BREAK" ;;
    STALE-PROVEN) echo "  reading: STALE (proven: $CL_PROOF)" ;;
  esac
  if [ "$CL_PID" = unproven ]; then echo "  pid unproven: no proof-of-death break is possible"; fi
  if cl_behind; then echo "  BEHIND: run 'sparkwright lease sync --lease-token <token>' before any other act"; fi
  return 0
}

cl_break() {
  _reason=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --reason) [ $# -ge 2 ] || { cl_err "break: --reason needs a value"; return 2; }; _reason=$2; shift 2 ;;
      --lease)  [ $# -ge 2 ] || { cl_err "break: --lease needs a value"; return 2; }; cl_lease_ok "$2" || return 2; shift 2 ;;
      *) cl_err "break: unknown option '$(cl_clean "$1")'"; cl_usage; return 2 ;;
    esac
  done
  _reason=$(cl_clean "$_reason")
  if [ "${#_reason}" -lt 20 ]; then cl_err "break: --reason must say why, in 20 or more characters; it is written to the log."; return 2; fi
  if [ "$CL_LNAME" = land ]; then cl_lbreak; return $?; fi
  cl_need_on break || return 2
  if ! cl_read; then cl_err "break: no lease is held."; return 1; fi
  if [ "$CL_MAL" = 1 ]; then cl_err "break: the lease's LEASE is unreadable or malformed; a human clears $CL_REF."; return 1; fi
  cl_classify
  _plabel=""; _dial="${KIT_LEASE_FORCE_BREAK:-}"
  case "$CL_CLASS" in
    LIVE) cl_err "break: REFUSED — $(cl_held_line) is within its ttl; it is not stale."; return 1 ;;   # MUT-STALEPRE
    STALE-PROVEN) _plabel=dead ;;
    STALE-AGE)
      if [ "$CL_CLASS" = STALE-AGE ] && [ -z "$_dial" ]; then   # MUT-AGEPROOF
        cl_err "break: REFUSED — $(cl_held_line) is past its ttl but nothing proves the holder is gone ($CL_WHY); age alone is never proof. If you know it is gone, a human sets KIT_LEASE_FORCE_BREAK in their own terminal."
        return 1
      fi
      _plabel=FORCED ;;
  esac
  [ -n "$_plabel" ] || { cl_err "break: REFUSED — no proof."; return 1; }
  # THE LOG IS WRITTEN BEFORE THE DELETE: an untraceable break is what the record exists to prevent
  if ! cl_log_break "$_plabel" "$_reason" "$CL_SHA"; then   # MUT-LOGFIRST
    cl_err "break: REFUSED — the break could not be logged to $CL_LOG, so the lease is left alone."
    return 2
  fi
  if cl_drop "$CL_SHA"; then
    printf 'lease: BROKEN — was %s; proof %s; logged to %s.\n' "$(cl_held_line)" "$_plabel" "$CL_LOG"
    return 0
  fi
  cl_log_break "$_plabel-FAILED" "delete refused after the record was written: $CL_REF left in place" "(not deleted)" || cl_err "break: ALSO the compensating record could not be written; $CL_LOG claims a break that did not happen. Correct it by hand."
  cl_err "break: FAILED — the lease could not be deleted (the ref moved, or the delete was refused); a $_plabel-FAILED entry was appended to $CL_LOG. The lease is unchanged."
  return 1
}

# ── THE LAND LEASE (slice B): one holder of `land` on origin ─────────────────────────────────────
# Taken by a plain push of an orphan commit (no `+`: the forge's non-fast-forward refusal is the lock), returned by a leased delete.
# Nothing is parsed from origin except by fixed field names, and nothing from origin reaches a terminal except through cl_clean.
cl_land_init() { [ -n "$CL_ISOROOT" ] || CL_ISOROOT=$(mktemp -d 2>/dev/null || echo ''); }
cl_iso() { # -> a fresh throwaway git dir (the push and every read run in one, never in the caller's clone)
  [ -n "$CL_ISOROOT" ] || return 1
  _id=$(mktemp -d "$CL_ISOROOT/gd.XXXXXX") || return 1
  git init -q "$_id" >/dev/null 2>&1 || return 1
  # the caller's `url.<base>.insteadOf` rules are copied into the throwaway dir, so the remote URL can be passed as the user wrote it
  git config --get-regexp '^url\..*\.insteadof$' 2>/dev/null | while read -r _ik _iv; do git -C "$_id" config --add "$_ik" "$_iv"; done || true
  printf '%s\n' "$_id"
}
# the remote URL as configured (never expanded): the guard masks a URL origin, and this is the shape real use has (https or ssh)
cl_url() { git config --get remote.origin.url 2>/dev/null; }
# B4: a laptop holder is a random 16-hex id made once per checkout in the common git dir (every worktree shares it); never the hostname.
cl_midfile() { _mg=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd) || return 1; printf '%s/kit-lease-machine' "$_mg"; }
cl_mid_read() { # -> the id when the file holds a well-formed one, else nothing
  _mf=$(cl_midfile) || return 0
  [ -f "$_mf" ] || return 0
  cl_hostok || return 0   # an id file copied from another host (a copied .git) is no id here
  _mv=$(head -c 64 "$_mf" 2>/dev/null | tr -d '\n')
  case "$_mv" in *[!0-9a-f]*) return 0 ;; esac
  if [ "${#_mv}" -eq 16 ]; then printf '%s' "$_mv"; fi
  return 0
}
# S2 (errata item 17): beside the id, a LOCAL-ONLY fingerprint (a salted sha256, never pushed) of a hardware id (macOS IOPlatformUUID; Linux machine-id plus
# the pid namespace; the host name only as the fallback) in the same dir. When it no longer matches or is missing (a copied .git) the id is made again, so two
# hosts never share one id. On ACQUIRE no fingerprint means cl_mid_make returns rc 1 and the acquire refuses (fail closed); a read stays age only.
# cl_hwid -> the input of the fingerprint (errata item 17), NEVER stored, logged or echoed raw: macOS reads the platform UUID from `ioreg`; Linux the machine id
# file MIXED WITH the pid-namespace marker (two containers that share one machine id but have separate pid namespaces are two machines for a pid proof;
# an unreadable marker means no fingerprint at all); only when neither source gives an id does the host NAME stand in (it changes with a network rename,
# which fails safe: a lost proof, never a false one; `uname -n` failing means no fingerprint, never a shared word). rc 1 and nothing when none can be made.
cl_hwid() {
  _hu=""
  if command -v ioreg >/dev/null 2>&1; then _hu=$(ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null | sed -n 's/.*"IOPlatformUUID" = "\([^"]*\)".*/\1/p' | head -n 1); fi
  if [ -z "$_hu" ]; then
    _hu=$(cat /etc/machine-id 2>/dev/null || true)
    if [ -n "$_hu" ]; then
      _ns=$(readlink /proc/self/ns/pid 2>/dev/null || true)   # MUT-LNS
      [ -n "$_ns" ] || return 1
      _hu="$_hu|$_ns"
    fi
  fi
  if [ -z "$_hu" ]; then   # MUT-LHWID
    _un=$(uname -n 2>/dev/null) || return 1
    [ -n "$_un" ] || return 1
    _hu="uname:$_un"   # MUT-LUNAME
  fi
  printf 'kit-lease-v1:%s' "$_hu"
}
cl_hostfp() { # the sha256 of that (salted) input: the only form that is kept, in the common git dir; rc 1 and nothing when there is no fingerprint
  _hw=$(cl_hwid) || return 1
  [ -n "$_hw" ] || return 1
  if command -v sha256sum >/dev/null 2>&1; then printf '%s' "$_hw" | sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then printf '%s' "$_hw" | shasum -a 256 | cut -d' ' -f1
  else printf '%s' "$_hw" | git hash-object --stdin; fi
}
cl_hostfile() { _hg=$(cl_midfile) || return 1; printf '%s/kit-lease-host' "${_hg%/*}"; }
cl_hostok() { # rc 0 only when the id file may be trusted on this host: a fingerprint is recorded beside it and it matches; none recorded, none makeable or another = a mismatch
  _hf=$(cl_hostfile) || return 1
  [ -f "$_hf" ] || return 1
  _hk=$(head -c 80 "$_hf" 2>/dev/null | tr -d '\n')
  _cur=$(cl_hostfp) || return 1
  [ -n "$_cur" ] || return 1
  [ "$_hk" = "$_cur" ]   # MUT-LFP
}
cl_mid_make() { # -> the id, made and kept when this checkout has none (or none for this host); rc 1 when it cannot be made
  _mn=$(cl_mid_read)
  if [ -z "$_mn" ]; then
    _mf=$(cl_midfile) || return 1
    _fp=$(cl_hostfp) || return 1   # no fingerprint, no id
    [ -n "$_fp" ] || return 1
    _mn=$(od -An -N8 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
    case "$_mn" in *[!0-9a-f]*) return 1 ;; esac
    [ "${#_mn}" -eq 16 ] || return 1
    printf '%s\n' "$_mn" > "$_mf" || return 1
    printf '%s\n' "$_fp" > "$(cl_hostfile)" || return 1
  fi
  printf '%s' "$_mn"
}
# the machine name this call compares a holder's `machine` with: the land lease's random id, or (the checkout lease) the hostname
cl_mymachine() {
  if [ "$CL_LNAME" = land ]; then
    _mm=$(cl_mid_read)
    printf '%s' "${_mm:-(no-id)}"
  else cl_machine; fi
}

# cl_lread -> rc 0 held (CL_SHA, CL_*, CL_MAL set; CL_GD is the dir holding it) · 1 free · 2 origin unreachable · 5 never read a stable lease
# The sha read by `ls-remote` must equal the commit fetched (a lease that moved between the two is re-read once), so what is classified is what was read.
cl_lread() {
  CL_MAL=0; CL_SHA=""; CL_GD=""; _lt=0
  cl_land_init
  _lurl=$(cl_url) || return 2
  while [ "$_lt" -lt 2 ]; do
    _lt=$((_lt + 1))
    _lo=0; _lout=$(git ls-remote --exit-code origin "$CL_LREF" 2>/dev/null) || _lo=$?
    if [ "$_lo" = 2 ]; then return 1; fi   # MUT-LUNREACH
    [ "$_lo" = 0 ] || return 2
    # only the line that ends in a tab and exactly this ref is the lease (a pattern also matches `<prefix>/refs/leases/land`)
    _lsha=$(printf '%s\n' "$_lout" | awk -F '\t' -v r="$CL_LREF" '$2 == r { print $1; exit }')
    [ -n "$_lsha" ] || return 1
    cl_token_ok "$_lsha" || return 2
    CL_GD=$(cl_iso) || return 2   # MUT-LTMP
    git -C "$CL_GD" fetch -q --no-tags --depth=1 "$_lurl" "$CL_LREF:refs/scratch" >/dev/null 2>&1 || continue
    _lgot=$(git -C "$CL_GD" rev-parse --verify -q refs/scratch 2>/dev/null || true)
    if [ "$_lgot" = "$_lsha" ]; then   # MUT-LSHAEQ
      CL_SHA=$_lsha
      if ! cl_load "$CL_SHA"; then CL_MAL=1; fi
      return 0
    fi
  done
  return 5
}
# cl_lread_msg <rc> <verb> -> the sentence for a read that gave no lease (rc 1 is the caller's own "free" answer)
cl_lread_msg() {
  case "$1" in
    2) cl_err "$2: origin is unreachable (or has no $CL_LREF to read); the lease is never read as free then. Nothing was changed." ;;
    *) cl_err "$2: could not read a stable lease at $CL_LREF (it moved, or the fetch failed). Nothing was changed; retry." ;;
  esac
}
cl_ckread() { # the CHECKOUT lease, read while a land verb is running (the order check: the land lease is taken under it)
  _cks=$CL_LNAME; CL_LNAME=checkout; CL_GD=""; _ckr=0
  cl_read || _ckr=$?
  CL_LNAME=$_cks
  return "$_ckr"
}
cl_pidrec() { # <pid> -> sets _lpid and _lpidstart (the harness process, with its start time); rc 2 when it is no ancestor
  _lpid=unproven; _lpidstart="(none)"; _wrc=0
  cl_walk "$1" || _wrc=$?
  case "$_wrc" in
    0) _lpid=$1; _lpidstart=$(cl_lstart "$1"); [ -n "$_lpidstart" ] || _lpidstart="(none)" ;;
    1) cl_err "acquire: --pid $1 is not an ancestor of this process; the lease records the process that holds it. Nothing was written."; return 2 ;;
    *) ;;
  esac
  return 0
}
# the CI form: no tree checks (a runner has no main checkout); origin's main must still be the base the run started from
cl_lacq_ci() {
  case "$(cl_state)" in on|missing) cl_err "acquire: REFUSED — --run is the CI form of the land lease; this checkout opted in to the checkout lease, so it takes the land lease with --lease-token. Nothing was pushed."; return 2 ;; esac   # MUT-LCIFORM
  cl_run_ok "$_run" || { cl_err "acquire: --run is <run id>/<attempt>, digits only."; return 2; }
  cl_holder_ok "$_holder" || { cl_err "acquire: --holder must match [A-Za-z0-9 ._-]{1,40} (one line, no control bytes)."; return 2; }
  [ "$_purpose" = land ] || { cl_err "acquire: the CI form is --purpose land."; return 2; }
  cl_token_ok "$_xbase" || { cl_err "acquire: --expect-base <sha> is required with --run."; return 2; }
  if ! cl_origin; then cl_err "REFUSED — origin is unreachable, or has no main. Nothing was pushed."; return 2; fi
  if [ "$CL_OSHA" != "$_xbase" ]; then   # MUT-LBASE
    cl_err "acquire: REFUSED — origin's main ($(printf '%.12s' "$CL_OSHA")) is not the base this run started on ($(printf '%.12s' "$_xbase")). Nothing was pushed."
    return 5
  fi
  _lmachine=ci; _lpid=unproven; _lpidstart="(none)"; _lrun=$_run
  return 0
}
# the laptop form: the checkout lease's token is the order check, and the holder is copied from the checkout lease it matches (B7, Q-B2)
cl_lacq_laptop() {
  cl_need_on acquire || return 2
  case "$_purpose" in land|actuate) ;; *) cl_err "acquire: the land lease is taken for --purpose land or actuate."; return 2 ;; esac
  case "$_pidarg" in ''|*[!0-9]*) cl_err "acquire: --pid names the process that holds the lease (digits)."; return 2 ;; esac
  [ "$_pidarg" -gt 1 ] || { cl_err "acquire: --pid must be a process above PID 1."; return 2; }
  if ! cl_token_ok "$_ctok"; then cl_err "acquire: REFUSED — the land lease is taken under the checkout lease: pass its --lease-token. Nothing was pushed."; return 5; fi
  _ckrc=0; cl_ckread || _ckrc=$?
  if [ "$_ckrc" != 0 ] || [ "$CL_MAL" = 1 ]; then cl_err "acquire: REFUSED — no readable checkout lease is held; take it first. Nothing was pushed."; return 5; fi
  if ! cl_match "$_ctok"; then   # MUT-LORDER
    cl_err "acquire: REFUSED — that is not the checkout lease holder's token. Nothing was pushed."
    return 5
  fi
  _holder=$CL_HOLDER
  cl_pidrec "$_pidarg" || return $?
  _lmachine=$(cl_mid_make) || { cl_err "acquire: could not make this checkout's machine id."; return 2; }   # MUT-LHOST
  _lrun=""
  return 0
}
cl_lacquire() { # uses the parsed _holder _purpose _pidarg _note _run _xbase _ctok
  cl_land_init
  if [ -n "$_note" ]; then cl_err "acquire: --note is not written to origin; the land lease is readable by everyone who reads origin."; return 2; fi
  if [ -n "$_run" ]; then cl_lacq_ci || return $?; else cl_lacq_laptop || return $?; fi
  CL_GD=$(cl_iso) || { cl_err "acquire: could not make a scratch area."; return 2; }
  _lurl=$(cl_url) || { cl_err "acquire: this repository has no origin."; return 2; }
  _lblob=$( { printf 'lease: land\nholder: %s\npurpose: %s\n' "$_holder" "$_purpose"
              [ -z "$_lrun" ] || printf 'run: %s\n' "$_lrun"
              printf 'machine: %s\npid: %s\npid-start: %s\nacquired-at: %s\nttl-s: %s\n' \
                "$_lmachine" "$_lpid" "$_lpidstart" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(cl_ttl "$_purpose")"
            } | cl_g hash-object -w --stdin) || { cl_err "acquire: could not write the lease blob."; return 2; }
  _ltree=$(printf '100644 blob %s\tLEASE\n' "$_lblob" | cl_g mktree) || { cl_err "acquire: could not write the lease tree."; return 2; }
  _lcommit=$(printf 'land lease: %s (%s)\n' "$_holder" "$_purpose" | cl_ct "$_ltree") || { cl_err "acquire: could not write the lease commit."; return 2; }
  # NO `+`: a second writer's push is refused by the forge as a non-fast-forward, and that refusal is the lock
  _lperr=""
  if _lperr=$(KIT_LEASE_FRONT_DOOR=1 git -C "$CL_GD" push -q "$_lurl" "$_lcommit:$CL_LREF" 2>&1); then   # MUT-LPUSH
    printf 'lease-token: %s\n' "$_lcommit"
    printf 'lease: land lease acquired by "%s" for %s (ttl %s min) on origin.\n' "$_holder" "$_purpose" "$(( $(cl_ttl "$_purpose") / 60 ))"
    return 0
  fi
  _lrc=0; cl_lread || _lrc=$?
  case "$_lrc" in
    0) if [ "$CL_MAL" = 1 ]; then cl_err "REFUSED — a lease exists at $CL_LREF but its LEASE is unreadable or malformed; a human clears it. Nothing was changed."; return 3; fi
       cl_classify
       cl_err "$(cl_held_line); retry after it is released, or ask the coordinator if it goes STALE"
       [ "$CL_CLASS" = LIVE ] && return 3
       if [ "$CL_CLASS" = STALE-PROVEN ]; then
         cl_err "this holder is proven gone ($CL_PROOF), but it is reported, never broken silently: 'sparkwright lease break --lease land --reason <why>' clears it, logged first."
       else
         cl_err "this lease is past its ttl and is reported, never broken silently: 'sparkwright lease status --lease land' reads it, 'break' needs a proof."
       fi
       return 4 ;;
    1) cl_err "acquire: the push was refused although no lease is visible on origin: $(cl_clean "$_lperr" | cut -c1-300)"; return 2 ;;
    *) cl_lread_msg "$_lrc" acquire; return 2 ;;
  esac
}
# cl_ldelete <sha> -> the leased delete: it removes the lease only while origin's ref still holds that sha
cl_ldelete() { KIT_LEASE_FRONT_DOOR=1 git -C "${CL_GD:-.}" push -q --force-with-lease="$CL_LREF:$1" "$_lurl" ":$CL_LREF" >/dev/null 2>&1; }   # MUT-LDEL
cl_lrelease() { # uses the parsed _tok
  cl_token_ok "$_tok" || { cl_err "release: --lease-token <sha> is required."; return 2; }
  _lrc=0; cl_lread || _lrc=$?
  case "$_lrc" in 0) ;; 1) cl_err "release: no land lease is held; nothing to release."; return 1 ;; *) cl_lread_msg "$_lrc" release; return 2 ;; esac
  if [ "$CL_MAL" = 1 ]; then cl_err "release: the lease's LEASE is unreadable or malformed; a human clears $CL_LREF on origin."; return 1; fi
  if ! cl_match "$_tok"; then cl_classify; cl_err "release: REFUSED — that is not the holder's token. $(cl_held_line)."; return 1; fi
  if cl_ldelete "$CL_SHA"; then
    printf 'lease: land lease released (%s, was held by "%s").\n' "$CL_PURPOSE" "$CL_HOLDER"
    return 0
  fi
  # The delete failed. Re-read: a lease that is still the very one we hold was REFUSED (it was MEASURED under `kit-guard install-shims`, whose
  # force-push rule refused a leased delete; SWAS-842 admits this one grammar-exact form, so the refusal is cured and this leg now covers any
  # other refusal); a lease that changed MOVED between the read and the delete.
  _was=$CL_SHA
  _rrc=0; cl_lread || _rrc=$?
  if [ "$_rrc" = 0 ] && [ "$CL_SHA" = "$_was" ]; then
    cl_llog "release-FAILED" delete-refused "(not deleted)" || cl_err "release: ALSO the record could not be written to $CL_LLOG."
    cl_err "release refused (for example under install-shims); the lease stays until a person runs 'break --lease land' outside the shims"
    return 1
  fi
  if [ "$_rrc" = 0 ] || [ "$_rrc" = 1 ]; then
    cl_err "release: FAILED — the lease changed or is gone between the read and the delete, so it was left alone. Read it with 'status --lease land'."
  else
    cl_lread_msg "$_rrc" release
  fi
  return 1
}
# cl_llog <proof> <reason code> <released-sha> -> appends one entry to $CL_LLOG on origin: a child of its tip (fetched --depth 1 into a throwaway dir),
# a plain push with no `+`. Written BEFORE a delete; a failed delete appends `<proof>-FAILED`. A trace, not tamper-evidence.
# S1: the reason is a FIXED CODE (lowercase and dashes only); a break's free-text reason never reaches origin (it stays in a local log).
cl_llog() {
  case "$2" in ''|*[!a-z-]*) return 1 ;; esac
  _lgd=$(cl_iso) || return 1
  _lt=""; _lo=0; _lout=$(git ls-remote --exit-code origin "$CL_LLOG" 2>/dev/null) || _lo=$?
  case "$_lo" in
    0) _lt=$(printf '%s\n' "$_lout" | awk -F '\t' -v r="$CL_LLOG" '$2 == r { print $1; exit }')
       [ -n "$_lt" ] || return 1
       git -C "$_lgd" fetch -q --no-tags --depth=1 "$_lurl" "$CL_LLOG:refs/scratch" >/dev/null 2>&1 || return 1
       [ "$(git -C "$_lgd" rev-parse --verify -q refs/scratch 2>/dev/null || true)" = "$_lt" ] || return 1 ;;
    2) ;;
    *) return 1 ;;
  esac
  _lsv=$CL_GD; CL_GD=$_lgd
  _lgb=$(printf 'at: %s\nproof: %s\nreason: %s\nold-holder: %s\nold-purpose: %s\nold-machine: %s\nold-run: %s\nreleased-sha: %s\n' \
           "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$CL_HOLDER" "$CL_PURPOSE" "$CL_MACHINE" "${CL_RUN:-none}" "$3" \
         | cl_g hash-object -w --stdin) || { CL_GD=$_lsv; return 1; }
  _lgt=$(printf '100644 blob %s\tLOG\n' "$_lgb" | cl_g mktree) || { CL_GD=$_lsv; return 1; }
  _lgc=$(printf 'break (%s)\n' "$1" | cl_ct "$_lgt" "$_lt") || { CL_GD=$_lsv; return 1; }
  CL_GD=$_lsv
  KIT_LEASE_FRONT_DOOR=1 git -C "$_lgd" push -q "$_lurl" "$_lgc:$CL_LLOG" >/dev/null 2>&1
}

# ── THE CI HOLDER'S PROOF (B3): the forge says whether its run is over ───────────────────────────
cl_dec() { printf '%s' "$1" | sed 's/^0*\([0-9]\)/\1/'; }
cl_epoch() { # YYYY-MM-DDTHH:MM:SSZ -> epoch seconds (UTC, no `date` dialect); rc 1 for anything else
  case "$1" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;; *) return 1 ;; esac
  _ey=${1%%-*}; _er=${1#*-}; _em=${_er%%-*}; _er=${_er#*-}; _ed=${_er%%T*}; _er=${_er#*T}
  _eh=${_er%%:*}; _er=${_er#*:}; _en=${_er%%:*}; _es=${_er#*:}; _es=${_es%Z}
  _ey=$(cl_dec "$_ey"); _em=$(cl_dec "$_em"); _ed=$(cl_dec "$_ed"); _eh=$(cl_dec "$_eh"); _en=$(cl_dec "$_en"); _es=$(cl_dec "$_es")
  if [ "$_em" -le 2 ]; then _ey=$((_ey - 1)); fi
  _eera=$((_ey / 400)); _eyoe=$((_ey - _eera * 400))
  _edoy=$(( (153 * ((_em + 9) % 12) + 2) / 5 + _ed - 1 ))
  _edays=$(( _eera * 146097 + _eyoe * 365 + _eyoe / 4 - _eyoe / 100 + _edoy - 719468 ))
  printf '%s' "$(( _edays * 86400 + _eh * 3600 + _en * 60 + _es ))"
}
cl_ghrepo() { # -> owner/repo from origin's URL as configured; rc 1 when it is not a GitHub URL (then there is no proof, only age)
  _gu=$(cl_url) || return 1
  case "$_gu" in
    https://github.com/*) _gp=${_gu#https://github.com/} ;;
    ssh://git@github.com/*) _gp=${_gu#ssh://git@github.com/} ;;
    git@github.com:*) _gp=${_gu#git@github.com:} ;;
    *) return 1 ;;
  esac
  _gp=${_gp%.git}; _gp=${_gp%/}
  case "$_gp" in */*) ;; *) return 1 ;; esac
  _go=${_gp%%/*}; _gr=${_gp#*/}
  case "$_go" in ''|-*|*[!A-Za-z0-9._-]*) return 1 ;; esac
  case "$_gr" in ''|-*|*[!A-Za-z0-9._-]*) return 1 ;; esac
  printf '%s/%s' "$_go" "$_gr"
}
# cl_ciproof -> sets CL_PROOF / CL_WHY for a lease that names a CI run. A proof only when the run is on the train's workflow, on main, from a
# non-PR event, was created no later than the lease commit + 300 s, has COMPLETED, and finished no earlier than the lease commit - 300 s (a run that had
# already finished before the lease was written cannot be its holder). Any gh failure, enum surprise or malformed time is no proof.
cl_ciproof() {
  cl_run_ok "$CL_RUN" || { CL_WHY="the run id is malformed"; return 0; }
  _cid=${CL_RUN%/*}; _cat=${CL_RUN#*/}
  _crepo=$(cl_ghrepo) || { CL_WHY="origin is not a GitHub repository, so the run cannot be read"; return 0; }
  set -- run view "$_cid"
  set -- "$@" --attempt "$_cat"   # MUT-LATT
  set -- "$@" -R "$_crepo"   # MUT-LREPO
  set -- "$@" --json status,conclusion,createdAt,updatedAt,workflowName,headBranch,event
  # S5: the fields come out of gh as ONE tab-separated line in a fixed order (`--jq` with @tsv escapes a tab or newline inside a value), never parsed from JSON layout
  set -- "$@" --jq '[.status,.conclusion,.createdAt,.updatedAt,.workflowName,.headBranch,.event]|@tsv'
  if command -v kit_gh_tls_pin >/dev/null 2>&1; then kit_gh_tls_pin; fi   # MUT-LPROBE
  _cj=$(gh "$@" 2>/dev/null) || { CL_WHY="gh could not read run $(cl_clean "$CL_RUN")"; return 0; }   # MUT-LGHFAIL
  _cj=$(printf '%s\n' "$_cj" | head -n 1)
  [ "$(printf '%s' "$_cj" | tr -cd '\t' | wc -c | tr -d ' ')" = 6 ] || { CL_WHY="gh answered with something other than the seven fields"; return 0; }
  _cs=$(printf '%s' "$_cj" | cut -f1); _cc=$(printf '%s' "$_cj" | cut -f2)
  _ccr=$(printf '%s' "$_cj" | cut -f3); _cup=$(printf '%s' "$_cj" | cut -f4)
  _cwf=$(printf '%s' "$_cj" | cut -f5); _cbr=$(printf '%s' "$_cj" | cut -f6); _cev=$(printf '%s' "$_cj" | cut -f7)
  case "$_cs" in queued|in_progress|completed|waiting|requested|pending) ;; *) CL_WHY="the status of the run is (unrecognised)"; return 0 ;; esac
  case "$_cc" in ''|success|failure|cancelled|skipped|timed_out|action_required|neutral|stale|startup_failure) ;; *) CL_WHY="the conclusion of the run is (unrecognised)"; return 0 ;; esac   # MUT-LENUM
  [ "$_cs" = completed ] || { CL_WHY="the run is $_cs, not completed"; return 0; }   # MUT-LDONE
  [ -n "$_cc" ] || { CL_WHY="the run has no conclusion"; return 0; }
  [ "$_cwf" = "$CL_TRAIN_WORKFLOW" ] || { CL_WHY="the run is on another workflow"; return 0; }   # MUT-LWF
  [ "$_cbr" = main ] || { CL_WHY="the run is not on main"; return 0; }   # MUT-LBRANCH
  case "$_cev" in ''|pull_request|pull_request_target) CL_WHY="the run is from a pull request event"; return 0 ;; esac   # MUT-LEVENT
  _cct=$(cl_ctime "$CL_SHA")
  _crt=$(cl_epoch "$_ccr") || { CL_WHY="the creation time of the run is unreadable"; return 0; }
  _cut=$(cl_epoch "$_cup") || { CL_WHY="the finish time of the run is unreadable"; return 0; }
  [ "$_crt" -le $((_cct + 300)) ] || { CL_WHY="the run was created after the lease was written"; return 0; }   # MUT-LCREATED
  [ "$_cut" -ge $((_cct - 300)) ] || { CL_WHY="the run finished before the lease was written"; return 0; }   # MUT-LDONEAFTER
  CL_PROOF="run $CL_RUN concluded $_cc"
}

# ── status and break, land lease ─────────────────────────────────────────────────────────────────
cl_lstatus() {
  _lrc=0; cl_lread || _lrc=$?
  case "$_lrc" in
    0) ;;
    1) echo "lease: FREE (land)"; return 1 ;;
    2) echo "lease: UNKNOWN — origin is unreachable; the land lease is never read as free then."; return 2 ;;
    *) echo "lease: UNKNOWN — no stable lease could be read at $CL_LREF."; return 2 ;;
  esac
  if [ "$CL_MAL" = 1 ]; then
    echo "lease: MALFORMED — $CL_LREF exists but its LEASE is unreadable, too long, or not plain text; it is not shown. A human clears it."
    return 0
  fi
  cl_classify
  echo "lease: $(cl_held_line)"
  [ -z "$CL_RUN" ] || echo "  run: $CL_RUN"
  echo "  machine: $CL_MACHINE · age: ${CL_AGE}s · ttl: ${CL_TTL}s"
  case "$CL_CLASS" in
    LIVE)         echo "  reading: LIVE" ;;
    STALE-AGE)    echo "  reading: STALE (age only: $CL_WHY); a break needs the human dial KIT_LEASE_FORCE_BREAK" ;;
    STALE-PROVEN) echo "  reading: STALE (proven: $CL_PROOF)" ;;
  esac
  if [ "$(cl_ctime "$CL_SHA")" -gt $(( $(cl_now) + 300 )) ]; then echo "  writer clock ahead: the lease commit is dated more than 300 s in the future; it reads as past its ttl (age only)"; fi   # MUT-LCLOCK
  return 0
}
# cl_lbreaklog <proof> <reason> -> one line in the LOCAL break log (the common git dir, never pushed); best effort
cl_lbreaklog() {
  _bl=$(cl_midfile) || return 0
  printf '%s | %s | %s | %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(cl_clean "$1" | cut -c1-80)" "${CL_HOLDER:-}" "$(cl_clean "$2" | cut -c1-200)" >> "${_bl%/*}/kit-lease-break.log" 2>/dev/null || true
  return 0
}
cl_lbreak() { # uses the parsed _reason (20+ characters, checked by the caller)
  _lrc=0; cl_lread || _lrc=$?
  case "$_lrc" in 0) ;; 1) cl_err "break: no land lease is held."; return 1 ;; *) cl_lread_msg "$_lrc" break; return 2 ;; esac
  if [ "$CL_MAL" = 1 ]; then cl_err "break: the lease's LEASE is unreadable or malformed; a human clears $CL_LREF on origin."; return 1; fi
  cl_classify
  _plabel=""; _dial="${KIT_LEASE_FORCE_BREAK:-}"
  case "$CL_CLASS" in
    LIVE) cl_err "break: REFUSED — $(cl_held_line) is within its ttl; it is not stale."; return 1 ;;
    STALE-PROVEN) if [ -n "$CL_RUN" ]; then _plabel=$CL_PROOF; _rcode=run-concluded; else _plabel=dead; _rcode=proven-dead; fi ;;
    STALE-AGE)
      if [ -z "$_dial" ]; then
        cl_err "break: REFUSED — $(cl_held_line) is past its ttl but nothing proves the holder is gone ($CL_WHY); age alone is never proof. If you know it is gone, a human sets KIT_LEASE_FORCE_BREAK in their own terminal."
        return 1
      fi
      _plabel=FORCED; _rcode=age-dial ;;
  esac
  [ -n "$_plabel" ] || { cl_err "break: REFUSED — no proof."; return 1; }
  # S1: origin gets the fixed code; the human's reason stays in a local log in the common git dir (a person's words are never pushed)
  _lcode=$_rcode   # MUT-LREASON
  cl_lbreaklog "$_plabel" "$_reason"
  # THE LOG IS PUSHED BEFORE THE DELETE: an untraceable break is what the record exists to prevent
  if ! cl_llog "$_plabel" "$_lcode" "$CL_SHA"; then   # MUT-LLOGFIRST
    cl_err "break: REFUSED — the break could not be logged to $CL_LLOG, so the lease is left alone."
    return 2
  fi
  if cl_ldelete "$CL_SHA"; then
    printf 'lease: BROKEN — was %s; proof %s; logged to %s.\n' "$(cl_held_line)" "$_plabel" "$CL_LLOG"
    return 0
  fi
  cl_llog "$_plabel-FAILED" delete-refused "(not deleted)" || cl_err "break: ALSO the compensating record could not be written; $CL_LLOG claims a break that did not happen. Correct it by hand."
  cl_err "break: FAILED — the lease could not be deleted (it moved, or the delete was refused); a $_plabel-FAILED entry was appended to $CL_LLOG. The lease is unchanged."
  return 1
}

# ── ORACLE MARKER: cl_selftest() and everything below is the non-vacuity oracle region. ──────────
cl_pass() { echo "selftest PASS: $1"; }
cl_fail() { echo "selftest FAIL: $1"; cl_fail_n=1; }
cl_expect_rc() { if [ "$cl_rc" -eq "$1" ]; then cl_pass "$2"; else cl_fail "$2 (rc=$cl_rc, wanted $1); out=[$cl_out]"; fi; }
cl_has() { case "$cl_out" in *"$2"*) cl_pass "$1" ;; *) cl_fail "$1 (output lacks '$2'); out=[$cl_out]" ;; esac; }
cl_hasnt() { case "$cl_out" in *"$2"*) cl_fail "$1 (output wrongly carries '$2'); out=[$cl_out]" ;; *) cl_pass "$1" ;; esac; }
cl_check() { if [ "$2" = 1 ]; then cl_pass "$1"; else cl_fail "$1"; fi; }
# cl_x <script> <pathprefix-or-empty> <dir> <args...> — run a copy of the verb inside the clone, capturing rc and merged output
cl_x() {
  _xs=$1; _xp=$2; _xd=$3; shift 3
  if [ -n "$_xp" ]; then
    if cl_out=$( cd "$_xd" && PATH="$_xp:$PATH" sh "$_xs" "$@" 2>&1 ); then cl_rc=0; else cl_rc=$?; fi
  else
    if cl_out=$( cd "$_xd" && sh "$_xs" "$@" 2>&1 ); then cl_rc=0; else cl_rc=$?; fi
  fi
}
cl_run() { _rd=$1; shift; cl_x "$CL_SELF" "" "$_rd" "$@"; }
cl_runm() { _rd=$1; shift; cl_x "$cl_mscript" "" "$_rd" "$@"; }
cl_acq() { cl_run "$1" acquire --holder "$2" --purpose "$3" --pid "$$"; cl_tok=$(printf '%s\n' "$cl_out" | sed -n 's/^lease-token: //p' | head -1); }
cl_acqm() { cl_runm "$1" acquire --holder "$2" --purpose "$3" --pid "$$"; cl_tok=$(printf '%s\n' "$cl_out" | sed -n 's/^lease-token: //p' | head -1); }
cl_ref() { git -C "$1" rev-parse --verify -q refs/local-lease/checkout 2>/dev/null || true; }
cl_logn() { git -C "$1" rev-list --count refs/local-lease-log/checkout 2>/dev/null || echo 0; }
# cl_reset <repo> — a fixture-only clean slate: the lease refs gone, the tree reset, back on main at origin's main
cl_reset() {
  for _rr in $(git -C "$1" for-each-ref --format='%(refname)' refs/local-lease/ refs/local-lease-log/); do git -C "$1" update-ref --no-deref -d "$_rr"; done
  git -C "$1" remote set-url origin "$cl_ourl"
  git -C "$1" checkout -q -f main 2>/dev/null || true
  git -C "$1" fetch -q origin main 2>/dev/null || true
  git -C "$1" reset -q --hard FETCH_HEAD 2>/dev/null || true
  git -C "$1" clean -fdq 2>/dev/null || true
  git -C "$1" config kit.checkoutLease true
}
# cl_land — B lands one more commit on origin's main (an outside land: A has not fetched it)
cl_land() {
  ( cd "$cl_base/B" && git fetch -q origin main && git reset -q --hard FETCH_HEAD && echo "n$$$(cl_now)" >> f.txt && git commit -q -am "land" && git push -q origin main ) >/dev/null 2>&1
}
cl_mutant() { # <cell> <marker> <sed-body> -> sets cl_mscript; rc 1 with a FAIL when the copy equals the original
  _md="$cl_base/mut-$1"; mkdir -p "$_md"
  sed "/# MUT-$2\$/$3" "$CL_SELF" > "$_md/checkout-lease.sh"
  if cmp -s "$CL_SELF" "$_md/checkout-lease.sh"; then cl_fail "$1 mutant $2: did not apply (no line ends with # MUT-$2, or the sed matched nothing)"; return 1; fi
  cl_mscript="$_md/checkout-lease.sh"
  return 0
}
# cl_killed <label> <ran-to-verdict 0|1> <differs-from-expected 0|1> — the mutant arm: it must have RUN to its own verdict AND differ
cl_killed() {
  if [ "$2" != 1 ]; then cl_fail "$1 (the mutant did not run to its own verdict, so a crash is not a kill); out=[$cl_out]"; return 0; fi
  if [ "$3" = 1 ]; then cl_pass "$1"; else cl_fail "$1 (the mutant SURVIVED: the cell did not notice); out=[$cl_out]"; fi
}
# cl_plant_blob <repo> <age-s> <blobfile> — a lease planted by hand (as a fixture), its commit dated <age-s> ago; sets cl_psha
cl_plant_blob() {
  _pb=$(git -C "$1" hash-object -w "$3")
  _pt=$(printf '100644 blob %s\tLEASE\n' "$_pb" | git -C "$1" mktree)
  _pd="$(( $(cl_now) - $2 )) +0000"
  cl_psha=$(printf 'planted\n' | GIT_COMMITTER_DATE="$_pd" GIT_AUTHOR_DATE="$_pd" git -C "$1" commit-tree "$_pt")
  git -C "$1" update-ref refs/local-lease/checkout "$cl_psha"
}
# cl_plant <repo> <holder> <purpose> <pid> <pidstart> <age-s> <ttl-s> <machine>
cl_plant() {
  printf 'lease: checkout\nholder: %s\npurpose: %s\nmachine: %s\npid: %s\npid-start: %s\nacquired-at: 2026-01-01T00:00:00Z\nttl-s: %s\nbase: %s\nbehind: no\n' \
    "$2" "$3" "$8" "$4" "$5" "$7" "$(git -C "$1" rev-parse refs/heads/main)" > "$cl_base/plant.txt"
  cl_plant_blob "$1" "$6" "$cl_base/plant.txt"
}
# ---- land-lease fixtures (slice B) ----
cl_lref() { git -C "$cl_o" rev-parse --verify -q refs/leases/land 2>/dev/null || true; }
cl_lclear() { git -C "$cl_o" update-ref -d refs/leases/land 2>/dev/null || true; git -C "$cl_o" update-ref -d refs/leases-log/land 2>/dev/null || true; }
cl_llogn() { git -C "$cl_o" rev-list --count refs/leases-log/land 2>/dev/null || echo 0; }
cl_llogtxt() { git -C "$cl_o" cat-file blob refs/leases-log/land:LOG 2>/dev/null || true; }   # the LAST entry
cl_iso8601() { date -u -r "$1" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d "@$1" '+%Y-%m-%dT%H:%M:%SZ'; }
# cl_lplant_blob <age-s> <blobfile> — a land lease planted by hand on the bare origin (a fixture), its commit dated <age-s> ago; sets cl_lpsha
cl_lplant_blob() {
  _pb=$(git -C "$cl_o" hash-object -w "$2")
  _pt=$(printf '100644 blob %s\tLEASE\n' "$_pb" | git -C "$cl_o" mktree)
  _pd="$(( $(cl_now) - $1 )) +0000"
  cl_lpsha=$(printf 'planted\n' | GIT_COMMITTER_DATE="$_pd" GIT_AUTHOR_DATE="$_pd" GIT_AUTHOR_NAME=x GIT_AUTHOR_EMAIL=x@x GIT_COMMITTER_NAME=x GIT_COMMITTER_EMAIL=x@x git -C "$cl_o" commit-tree "$_pt")
  git -C "$cl_o" update-ref refs/leases/land "$cl_lpsha"
}
# cl_lplant <age-s> <holder> <purpose> <machine> <pid> <pidstart> <run-or-empty>
cl_lplant() {
  { printf 'lease: land\nholder: %s\npurpose: %s\n' "$2" "$3"
    [ -z "$7" ] || printf 'run: %s\n' "$7"
    printf 'machine: %s\npid: %s\npid-start: %s\nacquired-at: 2026-01-01T00:00:00Z\nttl-s: %s\n' "$4" "$5" "$6" "$(cl_ttl "$3")"
  } > "$cl_base/lplant.txt"
  cl_lplant_blob "$1" "$cl_base/lplant.txt"
}
# cl_lacq <repo> <holder> <purpose> — the checkout lease, then the land lease under it; sets cl_ctok, cl_ltok (and cl_rc, cl_out of the land acquire)
cl_lacq() {
  cl_acq "$1" "$2" claim; cl_ctok=$cl_tok
  cl_run "$1" acquire --lease land --purpose "$3" --pid "$$" --lease-token "$cl_ctok"
  cl_ltok=$(printf '%s\n' "$cl_out" | sed -n 's/^lease-token: //p' | head -1)
}
cl_lacqm() { # the same, through the mutant copy
  cl_acq "$1" "$2" claim; cl_ctok=$cl_tok
  cl_runm "$1" acquire --lease land --purpose "$3" --pid "$$" --lease-token "$cl_ctok"
  cl_ltok=$(printf '%s\n' "$cl_out" | sed -n 's/^lease-token: //p' | head -1)
}
# the `gh` shim: logs its argv, reads gh.conf (written by cl_ghconf), prints the run as JSON; GH_RC non-zero makes it fail; attempt 2 may differ (GH2_*)
cl_ghmk() {
  mkdir -p "$cl_base/ghshim"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/gh.log"\n[ -f "%s/gh.conf" ] || exit 1\n. "%s/gh.conf"\n[ "${GH_RC:-0}" = 0 ] || exit "$GH_RC"\ncase " $* " in *" --attempt 2 "*) GH_STATUS=${GH2_STATUS:-$GH_STATUS}; GH_CONC=${GH2_CONC-$GH_CONC} ;; esac\nprintf "%%s\\t%%s\\t%%s\\t%%s\\t%%s\\t%%s\\t%%s\\n" "$GH_STATUS" "$GH_CONC" "$GH_CREATED" "$GH_UPDATED" "$GH_WF" "$GH_BRANCH" "$GH_EVENT"\n' "$cl_base" "$cl_base" "$cl_base" > "$cl_base/ghshim/gh"
  chmod +x "$cl_base/ghshim/gh"
}
# cl_ghconf <status> <conclusion> <created-epoch> <updated-epoch> <workflow> <branch> <event>
cl_ghconf() {
  printf 'GH_STATUS=%s\nGH_CONC=%s\nGH_CREATED=%s\nGH_UPDATED=%s\nGH_WF=%s\nGH_BRANCH=%s\nGH_EVENT=%s\n' \
    "$1" "$2" "$(cl_iso8601 "$3")" "$(cl_iso8601 "$4")" "$5" "$6" "$7" > "$cl_base/gh.conf"
}
cl_ghon() { git -C "$C" remote set-url origin "https://github.com/owner-login/repo-a.git"; }
cl_ghoff() { git -C "$C" remote set-url origin "$cl_ourl"; }
# cl_pvdrive <promotion-verify source> <checkout token or empty> <merge stub> — writes $cl_base/pvdrive.sh: the PRODUCTION land-lease functions and traps of
# `promotion-verify.sh` (cut out of <source> by sed, never retyped), then a land-shaped body: take the lease, run the merge stub, return the lease.
# (Driving `land` itself needs the whole GO fixture of conformance/promotion-actuate-wired.sh; this runs the same functions and trap lines, and
# cl_pvorder pins where `land` and `actuate` call them.)
cl_pvdrive() {
  {
    printf 'set -eu\n_pv_ltok=%s\n_pv_lsh=%s\n_pv_sig=""; _pv_crit=0\n_pv_drop_scratch() { :; }\n_pv_drop_syncref() { :; }\n_pv_die() { exit "$1"; }\n' "'$2'" "'$CL_SELF'"
    sed -n -e '/^pv_land_lease_take() {/,/^}/p' -e '/^pv_land_lease_return() {/,/^}/p' -e '/^_pv_llt=""/p' "$1"
    sed -n -e "/^trap '.*_pv_die/p" -e "/^trap '.*pv_land_lease_return/p" "$1"
    printf 'pv_land_lease_take land || exit $?\nsh %s || exit 1\npv_land_lease_return\nexit 0\n' "$3"
  } > "$cl_base/pvdrive.sh"
}
# cl_pvorder <verb-function> <merge-needle> <claim-release-needle> -> rc 0 when take comes before the merge and return after the claim release
cl_pvorder() {
  sed -n "/^$1() {/,/^}/p" "$cl_dir/promotion-verify.sh" | awk -v m="$2" -v c="$3" '
    index($0, "pv_land_lease_take") { t = NR } index($0, m) { if (!mm) mm = NR } index($0, c) { cc = NR } index($0, "pv_land_lease_return") { r = NR }
    END { exit !(t > 0 && mm > t && cc > mm && r > cc) }'
}
# cl_ci <script> <verb> [args] — a land-lease verb in C (never opted in: the CI shape) through the gh shim
cl_ci() { _cis=$1; _civ=$2; shift 2; cl_x "$_cis" "$cl_base/ghshim" "$C" "$_civ" --lease land "$@"; }
# cl_ciplant <age-s> <run> <status> <conclusion> <created-offset> <updated-offset> <workflow> <branch> <event> — a CI holder planted and its run's fixture;
# the offsets are seconds from the lease commit time
cl_ciplant() {
  cl_lplant "$1" train land ci unproven "(none)" "$2"
  cl_ct0=$(( $(cl_now) - $1 ))
  cl_ghconf "$3" "$4" "$(( cl_ct0 + $5 ))" "$(( cl_ct0 + $6 ))" "$7" "$8" "$9"
}

cl_selftest() {
  cl_fail_n=0
  cl_base=$(mktemp -d)
  # HERMETIC: no global or system git config, HOME inside the workdir, an identity set per clone; real refs on a real bare origin.
  HOME="$cl_base/home"; mkdir -p "$HOME"; export HOME
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null; export GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
  unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_DIR GIT_WORK_TREE KIT_GUARD_SELFEDIT KIT_LEASE_FORCE_BREAK KIT_LEASE_FRONT_DOOR 2>/dev/null || true
  cl_dir=$(dirname -- "$CL_SELF")
  # SWAS-903: a non-empty SSL_CERT_FILE makes the gh-tls probe return at once, so the CL14 cells see only their own gh calls in gh.log (the probe's own behaviour is
  # scripts/gh-tls.sh --selftest; CL14p below proves, with a stub library, that the probe runs right before the gh call).
  SSL_CERT_FILE=/fixture/ssl-cert.pem; export SSL_CERT_FILE
  cl_realgit=$(command -v git)
  # THE HARDWARE-ID SEAM: PATH shims (as for gh and git below) give every verb run in this selftest a FAKE hardware id and a FAKE host name, kept in files this
  # selftest rewrites; the machine's real id is never read here. `ioreg` answers from hw.id (nothing when that file is absent), `cat` hides /etc/machine-id, `uname -n` answers from hw.host.
  cl_realcat=$(command -v cat); cl_realuname=$(command -v uname)
  mkdir -p "$cl_base/hwshim"
  printf '#!/bin/sh\n[ -f "%s/hw.id" ] || exit 1\nIFS= read -r _i < "%s/hw.id"\nprintf "    | \\"IOPlatformUUID\\" = \\"%%s\\"\\n" "$_i"\n' "$cl_base" "$cl_base" > "$cl_base/hwshim/ioreg"
  # `cat` answers /etc/machine-id from hw.mid (nothing when absent); `readlink` answers /proc/self/ns/pid from hw.ns (nothing when absent).
  printf '#!/bin/sh\nfor a in "$@"; do if [ "$a" = /etc/machine-id ]; then [ -f "%s/hw.mid" ] || exit 1; exec "%s" "%s/hw.mid"; fi; done\nexec "%s" "$@"\n' "$cl_base" "$cl_realcat" "$cl_base" "$cl_realcat" > "$cl_base/hwshim/cat"
  cl_realreadlink=$(command -v readlink)
  printf '#!/bin/sh\nfor a in "$@"; do if [ "$a" = /proc/self/ns/pid ]; then [ -f "%s/hw.ns" ] || exit 1; exec "%s" "%s/hw.ns"; fi; done\nexec "%s" "$@"\n' "$cl_base" "$cl_realcat" "$cl_base" "$cl_realreadlink" > "$cl_base/hwshim/readlink"
  # the `uname -n` shim ALSO changes the host name that cl_machine (the checkout lease's machine) sees, deliberately: every verb in this selftest sees one fake host.
  printf '#!/bin/sh\nif [ "${1:-}" = -n ]; then IFS= read -r _h < "%s/hw.host"; printf "%%s\\n" "$_h"; exit 0; fi\nexec "%s" "$@"\n' "$cl_base" "$cl_realuname" > "$cl_base/hwshim/uname"
  chmod +x "$cl_base/hwshim/ioreg" "$cl_base/hwshim/cat" "$cl_base/hwshim/readlink" "$cl_base/hwshim/uname"
  printf 'FAKE-HWID-A\n' > "$cl_base/hw.id"; printf 'fake-host-a\n' > "$cl_base/hw.host"
  PATH="$cl_base/hwshim:$PATH"; export PATH
  cl_me=$(cl_machine)
  # The origin has the shape real use has: an https URL, mapped to the bare dir by `url.<dir>.insteadOf` in the fixture repos only. The guard masks
  # a URL origin (a plain local path, and a `.git`-suffixed one, trips its path rule under the shims), so the bare dir carries no `.git` suffix.
  cl_o="$cl_base/origin"
  cl_ourl="https://example.invalid/owner-login/kit.git"
  git init -q --bare "$cl_o"; git -C "$cl_o" symbolic-ref HEAD refs/heads/main
  git init -q "$cl_base/A"
  ( cd "$cl_base/A" && git symbolic-ref HEAD refs/heads/main && git config user.name "Lane A" && git config user.email a@example.com \
      && git config commit.gpgsign false && echo hi > f.txt && git add f.txt && git commit -q -m init \
      && git config "url.$cl_o.insteadOf" "$cl_ourl" && git remote add origin "$cl_ourl" && git push -q origin main && git config kit.checkoutLease true \
      && printf '.kit-run/\n.kit/lanes.conf\n' >> .git/info/exclude ) >/dev/null 2>&1
  git clone -q "$cl_o" "$cl_base/B" >/dev/null 2>&1
  ( cd "$cl_base/B" && git config user.name "Lane B" && git config user.email b@example.com && git config commit.gpgsign false \
      && git config "url.$cl_o.insteadOf" "$cl_ourl" && git remote set-url origin "$cl_ourl" ) >/dev/null 2>&1
  git clone -q "$cl_o" "$cl_base/C" >/dev/null 2>&1   # never enabled: no key, no lease refs
  ( cd "$cl_base/C" && git config user.name "Lane C" && git config user.email c@example.com && git config commit.gpgsign false \
      && git config "url.$cl_o.insteadOf" "$cl_ourl" && git remote set-url origin "$cl_ourl" ) >/dev/null 2>&1
  A="$cl_base/A"; C="$cl_base/C"
  cl_ps_ok=0; [ -n "$(ps -o ppid= -p $$ 2>/dev/null | tr -d ' ')" ] && cl_ps_ok=1
  cl_zero=$(cd "$A" && cl_zero)

  # ---- CL1: acquire on main, clean, at origin -------------------------------------------------------
  cl_acq "$A" "Lane A" claim
  cl_expect_rc 0 "CL1 acquire on main, clean, at origin -> rc 0"
  cl_check "CL1 the printed token equals the ref" "$([ -n "$cl_tok" ] && [ "$cl_tok" = "$(cl_ref "$A")" ] && echo 1 || echo 0)"
  cl_blobtxt=$(git -C "$A" cat-file blob "$(cl_ref "$A"):LEASE" 2>/dev/null || true)
  case "$cl_blobtxt" in
    *"holder: Lane A"*"purpose: claim"*"machine: $cl_me"*"ttl-s: 600"*"base: $(git -C "$A" rev-parse refs/heads/main)"*"behind: no"*) cl_pass "CL1 the ref holds the blob fields" ;;
    *) cl_fail "CL1 the blob lacks its fields; blob=[$cl_blobtxt]" ;;
  esac
  cl_tok1=$cl_tok
  # the recorded process is the harness ancestor (this selftest), never the script's own $$ (CL9)
  if [ "$cl_ps_ok" = 1 ]; then
    case "$cl_blobtxt" in *"pid: $$"*) cl_pass "CL9 the recorded pid is the harness ancestor, not the script's own" ;; *) cl_fail "CL9 the recorded pid is not the ancestor $$; blob=[$cl_blobtxt]" ;; esac
    if cl_mutant CL9 PIDSELF 's|_pidrec=\$_pidarg;|_pidrec=$$;|'; then
      cl_reset "$A"; cl_acqm "$A" "Lane A" claim
      cl_killed "CL9 mutant (\$\$ recorded) is killed by the pid assertion" "$([ "$cl_rc" = 0 ] && [ -n "$cl_tok" ] && echo 1 || echo 0)" \
        "$(git -C "$A" cat-file blob "$(cl_ref "$A"):LEASE" 2>/dev/null | grep -q "^pid: $$\$" && echo 0 || echo 1)"
      cl_reset "$A"; cl_acq "$A" "Lane A" claim; cl_tok1=$cl_tok
    fi
  else
    echo "selftest SKIP: CL9 the recorded pid (ps cannot be read in this environment; the parent walk would read unproven)"
  fi
  # a lease taken and checked a call later is LIVE
  cl_run "$A" status
  cl_has "CL9 a lease taken and checked a call later reads LIVE" "reading: LIVE"

  # ---- CL2: a second lane in the SAME worktree -> HELD, ref unchanged --------------------------------
  cl_acq "$A" "Lane B" claim
  cl_expect_rc 3 "CL2 a second lane in the same worktree is refused rc 3"
  cl_has "CL2 the holder is named" 'HELD by "Lane A"'
  cl_check "CL2 the ref is unchanged" "$([ "$(cl_ref "$A")" = "$cl_tok1" ] && echo 1 || echo 0)"
  if cl_mutant CL2 CAS 's| "\$_zero" 2>/dev/null|  2>/dev/null|'; then
    cl_acqm "$A" "Lane B" claim
    cl_killed "CL2 mutant (create-only old value dropped) is killed: the second lane takes the lease" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)" "$([ "$(cl_ref "$A")" != "$cl_tok1" ] && echo 1 || echo 0)"
    cl_reset "$A"; cl_acq "$A" "Lane A" claim; cl_tok1=$cl_tok
  fi

  # ---- CL3: the token is the ref, not anything the lane shares ---------------------------------------
  mkdir -p "$A/.kit-run"; printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' > "$A/.kit-run/session.id"
  cl_run "$A" gate --verb record
  cl_expect_rc 5 "CL3 a verb with no token is refused rc 5"
  cl_has "CL3 it names the holder and the next act" 'HELD by "Lane A"'
  cl_has "CL3 the next act is acquire and pass --lease-token" "--lease-token"
  cl_run "$A" gate --verb record --lease-token "$(cat "$A/.kit-run/session.id")"
  cl_expect_rc 5 "CL3 another lane's token (the shared session id) is refused rc 5"
  cl_run "$A" gate --verb record --lease-token "$cl_tok1"
  cl_expect_rc 0 "CL3 the holder's token passes"
  if cl_mutant CL3 TOKEN 's|"\$CL_SHA"|"$(head -c 64 "$(git rev-parse --show-toplevel)/.kit-run/session.id")"|'; then
    cl_runm "$A" gate --verb record --lease-token "$(cat "$A/.kit-run/session.id")"
    cl_killed "CL3 mutant (token compared with session.id) is killed: the shared id is accepted" "$([ "$cl_rc" = 0 ] || [ "$cl_rc" = 5 ] && echo 1 || echo 0)" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)"
  fi
  cl_reset "$A"

  # ---- CL4: the refusals, each its own sentence, no ref written --------------------------------------
  git -C "$A" checkout -q -b feat
  cl_acq "$A" "Lane A" claim
  cl_expect_rc 5 "CL4 not on main -> rc 5"; cl_has "CL4 not-on-main sentence" "not main"
  cl_check "CL4 not on main wrote no ref" "$([ -z "$(cl_ref "$A")" ] && echo 1 || echo 0)"
  git -C "$A" checkout -q main
  # L5: a branch name carrying a bidi override (bytes above 0x7f) never reaches the refusal raw
  # (a name with no '/', so it cannot collide with the branch `feat` above; and the cell only runs acquire once the fixture is really on that branch)
  _bidi=$(printf '\342\200\256')
  _bname="bidi-${_bidi}x"
  if git -C "$A" checkout -q -b "$_bname" 2>/dev/null && [ "$(git -C "$A" symbolic-ref --short HEAD 2>/dev/null)" = "$_bname" ]; then
    cl_acq "$A" "Lane A" claim
    cl_expect_rc 5 "CL4 L5 not on a bidi-named branch -> rc 5"
    # (the refusal's own text carries a dash above 0x7f, so the assertion is on the bidi bytes only)
    case "$cl_out" in
      *"$_bidi"*) cl_fail "CL4 L5 the bidi override reached the refusal; out=[$cl_out]" ;;
      *) cl_pass "CL4 L5 the bidi override did not reach the refusal" ;;
    esac
    cl_reset "$A"   # whatever happened, no lease is carried into the next arm (the branch stays; the mutant arm switches back to it)
    git -C "$A" checkout -q "$_bname" 2>/dev/null || true
    if cl_mutant CL4L CLEAN 's|LC_ALL=C tr -cd .\[:print:\].|cat|'; then
      if [ "$(git -C "$A" symbolic-ref --short HEAD 2>/dev/null)" = "$_bname" ]; then
        cl_acqm "$A" "Lane A" claim
        cl_killed "CL4 L5 mutant (cl_clean passes every byte) is killed: the bidi byte reaches the refusal" "$([ "$cl_rc" = 5 ] && echo 1 || echo 0)" "$(case "$cl_out" in *"$_bidi"*) echo 1 ;; *) echo 0 ;; esac)"
      else cl_fail "CL4 L5 mutant: the fixture could not return to the bidi-named branch (the fixture is broken, so the mutant did not run)"; fi
    fi
  else
    cl_fail "CL4 L5: git refused to create or switch to a branch named with a bidi override (git accepts these names on Linux and APFS, so the fixture is broken; the cell and its mutant did not run)"
  fi
  cl_reset "$A"   # drops any lease and returns to main, clean
  echo dirt >> "$A/f.txt"
  cl_acq "$A" "Lane A" claim
  cl_expect_rc 5 "CL4 a dirty tree -> rc 5"; cl_has "CL4 dirty sentence" "not clean"
  cl_check "CL4 dirty wrote no ref" "$([ -z "$(cl_ref "$A")" ] && echo 1 || echo 0)"
  if cl_mutant CL4 DIRTY 's|if \[ -n "\$_st" \]; then|if false; then|'; then
    cl_acqm "$A" "Lane A" claim
    cl_killed "CL4 mutant (the dirty check dropped) is killed: a dirty tree takes the lease" "$([ "$cl_rc" = 0 ] || [ "$cl_rc" = 5 ] && echo 1 || echo 0)" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)"
  fi
  cl_reset "$A"
  echo u > "$A/untracked.txt"
  cl_acq "$A" "Lane A" claim
  cl_expect_rc 5 "CL4 an untracked file -> rc 5"; cl_has "CL4 untracked sentence" "not clean"
  cl_reset "$A"
  ( cd "$A" && echo ahead >> f.txt && git commit -q -am ahead )
  cl_acq "$A" "Lane A" claim
  cl_expect_rc 5 "CL4 local main ahead -> rc 5"; cl_has "CL4 ahead sentence" "ahead of origin"
  cl_check "CL4 ahead wrote no ref" "$([ -z "$(cl_ref "$A")" ] && echo 1 || echo 0)"
  cl_reset "$A"
  # a diverged main whose origin sha IS present locally (fetched): refused at once, no ref written
  ( cd "$A" && echo local >> f.txt && git commit -q -am local )
  cl_land
  git -C "$A" fetch -q origin main
  cl_acq "$A" "Lane A" claim
  cl_expect_rc 5 "CL4 local main diverged from a fetched origin main -> rc 5"; cl_has "CL4 diverged sentence" "diverged"
  cl_check "CL4 diverged wrote no ref" "$([ -z "$(cl_ref "$A")" ] && echo 1 || echo 0)"
  cl_reset "$A"
  git -C "$A" remote set-url origin "$cl_base/no-such-origin.git"
  cl_acq "$A" "Lane A" claim
  cl_expect_rc 2 "CL4 origin unreachable -> rc 2"; cl_has "CL4 unreachable sentence" "unreachable"
  cl_check "CL4 unreachable wrote no ref" "$([ -z "$(cl_ref "$A")" ] && echo 1 || echo 0)"
  if cl_mutant CL4u UNREACH 's|return 2 *#|_o=$(git rev-parse refs/heads/main) #|'; then
    cl_acqm "$A" "Lane A" claim
    cl_killed "CL4 mutant (unreachable read as 'at origin') is killed: it takes the lease" "$([ "$cl_rc" = 0 ] || [ "$cl_rc" = 2 ] && echo 1 || echo 0)" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)"
  fi
  cl_reset "$A"

  # ---- CL4b: origin moved by an outside land -> BEHIND, sync first --------------------------------------
  cl_land
  cl_acq "$A" "Lane A" record
  cl_expect_rc 0 "CL4b acquire while origin moved -> rc 0"; cl_has "CL4b the lease is marked BEHIND" "BEHIND"
  cl_tokb=$cl_tok
  cl_x "$cl_dir/promotion-verify.sh" "" "$A" record --lease-token "$cl_tokb"
  cl_expect_rc 5 "CL4b record refuses while BEHIND"; cl_has "CL4b it names sync" "sync"
  if cl_mutant CL4b BEHIND 's|\[ "\$CL_BEHINDF" = yes \] \|\| return 1|return 1|'; then
    cl_runm "$A" held --lease-token "$cl_tokb"
    cl_killed "CL4b mutant (BEHIND ignored by held) is killed: held passes a BEHIND lease" "$([ "$cl_rc" = 0 ] || [ "$cl_rc" = 5 ] && echo 1 || echo 0)" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)"
  fi
  cl_run "$A" sync --lease-token "$cl_tokb"
  cl_expect_rc 0 "CL4b sync fast-forwards main"
  cl_x "$cl_dir/promotion-verify.sh" "" "$A" record --lease-token "$cl_tokb"
  cl_expect_rc 2 "CL4b after sync record runs (its own usage refusal, not the lease's)"
  cl_hasnt "CL4b after sync the lease does not refuse" "checkout lease"
  cl_run "$A" release --lease-token "$cl_tokb"
  cl_expect_rc 0 "CL4b release after sync -> rc 0"
  cl_reset "$A"
  # a diverged main: sync releases the lease and refuses
  ( cd "$A" && echo local >> f.txt && git commit -q -am local )
  cl_land
  cl_acq "$A" "Lane A" sync
  cl_expect_rc 0 "CL4b acquire with an unreadable origin sha (local main not provably behind) -> rc 0, BEHIND"
  cl_run "$A" sync --lease-token "$cl_tok"
  cl_expect_rc 5 "CL4b a diverged main makes sync refuse rc 5"; cl_has "CL4b it names a human repair" "diverged"
  cl_check "CL4b sync released the lease" "$([ -z "$(cl_ref "$A")" ] && echo 1 || echo 0)"
  cl_reset "$A"

  # ---- CL5: the tree changes between the check and the write -----------------------------------------
  mkdir -p "$cl_base/gitshim"
  printf '#!/bin/sh\n"%s" "$@"\nrc=$?\ncase "$*" in\n  *"update-ref --no-deref refs/local-lease/checkout "[0-9a-f]*) echo x > "$PWD/changed-after-write.txt" ;;\nesac\nexit $rc\n' "$cl_realgit" > "$cl_base/gitshim/git"
  chmod +x "$cl_base/gitshim/git"
  cl_x "$CL_SELF" "$cl_base/gitshim" "$A" acquire --holder "Lane A" --purpose claim --pid "$$"
  cl_expect_rc 5 "CL5 a change between the check and the write -> rc 5"; cl_has "CL5 the sentence says it changed" "changed between"
  cl_check "CL5 the lease just taken was released" "$([ -z "$(cl_ref "$A")" ] && echo 1 || echo 0)"
  rm -f "$A/changed-after-write.txt"
  if cl_mutant CL5 RECHECK 's|if ! cl_acquire_checks; then|if false; then|'; then
    cl_x "$cl_mscript" "$cl_base/gitshim" "$A" acquire --holder "Lane A" --purpose claim --pid "$$"
    cl_killed "CL5 mutant (the re-check dropped) is killed: the lease survives the change" "$([ "$cl_rc" = 0 ] || [ "$cl_rc" = 5 ] && echo 1 || echo 0)" "$([ -n "$(cl_ref "$A")" ] && echo 1 || echo 0)"
    rm -f "$A/changed-after-write.txt"
  fi
  cl_reset "$A"

  # ---- CL6, CL7: release -------------------------------------------------------------------------------
  cl_acq "$A" "Lane A" land; cl_tok6=$cl_tok
  cl_land
  cl_run "$A" release --lease-token "$cl_tok6"
  cl_expect_rc 5 "CL6 release after a land without sync -> rc 5"; cl_has "CL6 it names sync" "sync"
  cl_check "CL6 the lease is still held" "$([ "$(cl_ref "$A")" = "$cl_tok6" ] && echo 1 || echo 0)"
  if cl_mutant CL6 RELBASE 's|CL_WANT=\$CL_OSHA|CL_WANT=$(git rev-parse refs/heads/main)|'; then
    cl_runm "$A" release --lease-token "$cl_tok6"
    cl_killed "CL6 mutant (release checked against base, not origin) is killed: the lease is released" "$([ "$cl_rc" = 0 ] || [ "$cl_rc" = 5 ] && echo 1 || echo 0)" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)"
  fi
  cl_reset "$A"
  cl_acq "$A" "Lane A" claim; cl_tok7=$cl_tok
  cl_run "$A" release --lease-token "$cl_zero"
  cl_expect_rc 1 "CL7 release with a wrong token -> rc 1"; cl_has "CL7 the holder is named" '"Lane A"'
  cl_check "CL7 the lease is still held" "$([ "$(cl_ref "$A")" = "$cl_tok7" ] && echo 1 || echo 0)"
  cl_run "$A" release --lease-token "$cl_tok7"
  cl_expect_rc 0 "CL7 release with the holder's token -> rc 0"
  cl_check "CL7 the lease is gone" "$([ -z "$(cl_ref "$A")" ] && echo 1 || echo 0)"
  cl_reset "$A"

  # ---- CL8: stale by age only -----------------------------------------------------------------------------
  cl_plant "$A" "Lane Far" claim 4242 "(none)" 100000 600 "another-machine"
  cl_acq "$A" "Lane A" claim
  cl_expect_rc 4 "CL8 acquire on a stale lease -> rc 4"
  cl_check "CL8 nothing changed" "$([ "$(cl_ref "$A")" = "$cl_psha" ] && echo 1 || echo 0)"
  cl_run "$A" status
  cl_has "CL8 status reads STALE (age only)" "STALE (age only"
  cl_run "$A" break --reason "the far lane is long gone, owner confirmed"
  cl_expect_rc 1 "CL8 break without the dial refuses"; cl_has "CL8 it names the human dial" "KIT_LEASE_FORCE_BREAK"
  cl_check "CL8 the lease is unchanged" "$([ "$(cl_ref "$A")" = "$cl_psha" ] && echo 1 || echo 0)"
  if cl_mutant CL8 AGEPROOF 's|= STALE-AGE ] && |= NEVER ] \&\& |'; then
    cl_runm "$A" break --reason "the far lane is long gone, owner confirmed"
    cl_killed "CL8 mutant (age accepted as proof) is killed: the break goes through" "$([ "$cl_rc" = 0 ] || [ "$cl_rc" = 1 ] && echo 1 || echo 0)" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)"
  fi
  cl_reset "$A"
  # a stale lease is never broken by acquire: the mutant deletes it on the rc 4 path, which the 'nothing changed' cell must notice
  cl_plant "$A" "Lane Far" claim 4242 "(none)" 100000 600 "another-machine"
  if cl_mutant CL8a AUTOBREAK 's|cl_err |cl_drop "$CL_SHA"; cl_err |'; then
    cl_acqm "$A" "Lane A" claim
    cl_killed "CL8 mutant (a stale lease auto-broken by acquire) is killed: the lease is gone after rc 4" "$([ "$cl_rc" = 4 ] && echo 1 || echo 0)" "$([ "$(cl_ref "$A")" != "$cl_psha" ] && echo 1 || echo 0)"
  fi
  cl_reset "$A"
  # L4: a lease dated in the future (a skewed clock, or an ambient GIT_COMMITTER_DATE) is not live forever: it reads STALE (age only)
  cl_plant "$A" "Lane Future" claim 4242 "(none)" -100000 600 "$cl_me"
  cl_run "$A" status
  cl_has "CL8 L4 a future-dated lease reads STALE, not live forever" "STALE"
  if cl_mutant CL8f FUTURE 's|-gt \$((_now + 300))|-gt 99999999999|'; then
    cl_runm "$A" status
    cl_killed "CL8 L4 mutant (the future-date branch dropped) is killed: the future lease reads LIVE" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)" "$(case "$cl_out" in *"reading: LIVE"*) echo 1 ;; *) echo 0 ;; esac)"
  fi
  cl_reset "$A"
  # L4: acquire dates the lease NOW whatever GIT_COMMITTER_DATE says
  if cl_out=$( cd "$A" && GIT_COMMITTER_DATE="2090-01-01T00:00:00Z" sh "$CL_SELF" acquire --holder "Lane A" --purpose claim --pid "$$" 2>&1 ); then cl_rc=0; else cl_rc=$?; fi
  cl_expect_rc 0 "CL8 L4 acquire under an ambient future GIT_COMMITTER_DATE -> rc 0"
  cl_run "$A" status
  cl_has "CL8 L4 and the lease reads LIVE (dated now, not 2090)" "reading: LIVE"
  cl_ctnear() { _cn=$(git -C "$A" show -s --format=%ct "$(cl_ref "$A")" 2>/dev/null || echo 0); [ "$_cn" -le $(( $(cl_now) + 120 )) ] && [ "$_cn" -ge $(( $(cl_now) - 120 )) ]; }
  cl_check "CL8 L4 the lease commit is dated now" "$(cl_ctnear && echo 1 || echo 0)"
  cl_reset "$A"
  if cl_mutant CL8c CTDATE 's|_cd="\$(cl_now) +0000"|_cd="${GIT_COMMITTER_DATE:-$(cl_now) +0000}"|'; then
    if cl_out=$( cd "$A" && GIT_COMMITTER_DATE="2090-01-01T00:00:00Z" sh "$cl_mscript" acquire --holder "Lane A" --purpose claim --pid "$$" 2>&1 ); then cl_rc=0; else cl_rc=$?; fi
    cl_killed "CL8 L4 mutant (the commit date left to the environment) is killed: the lease commit is not dated now" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)" "$(cl_ctnear && echo 0 || echo 1)"
    cl_reset "$A"
  fi

  # ---- CL9: the recorded pid, the walk, a reused pid ---------------------------------------------------
  if [ "$cl_ps_ok" = 1 ]; then
    sleep 30 & cl_sp=$!
    cl_acq_pid() { cl_run "$A" acquire --holder "Lane A" --purpose claim --pid "$1"; }
    cl_acq_pid "$cl_sp"
    cl_expect_rc 2 "CL9 a --pid that is not an ancestor (the walk completes) refuses rc 2"
    cl_check "CL9 and records nothing" "$([ -z "$(cl_ref "$A")" ] && echo 1 || echo 0)"
    if cl_mutant CL9n NONANC 's|return 2 ;;   #|_pidrec=unproven ;;   #|'; then
      cl_runm "$A" acquire --holder "Lane A" --purpose claim --pid "$cl_sp"
      cl_killed "CL9 mutant (a non-ancestor accepted as unproven) is killed: it takes the lease" "$([ "$cl_rc" = 0 ] || [ "$cl_rc" = 2 ] && echo 1 || echo 0)" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)"
    fi
    kill "$cl_sp" 2>/dev/null || true; wait "$cl_sp" 2>/dev/null || true
    cl_reset "$A"
    # a live session process past its ttl is STALE (age only): never proven dead
    cl_selfstart=$(cl_lstart "$$")
    cl_plant "$A" "Lane Live" claim "$$" "$cl_selfstart" 100000 1 "$cl_me"
    cl_run "$A" status
    cl_has "CL9 a live holder past its ttl reads STALE (age only), not proven" "STALE (age only"
    # L3: the start time is compared in UTC, so another time zone does not turn a live holder into a "reused pid"
    if cl_out=$( cd "$A" && TZ=XXX-14 sh "$CL_SELF" status 2>&1 ); then cl_rc=0; else cl_rc=$?; fi
    cl_has "CL9 L3 under another TZ a live holder still reads STALE (age only), not proven" "STALE (age only"
    if cl_mutant CL9z TZ 's|TZ=UTC0 ||'; then
      if cl_out=$( cd "$A" && TZ=XXX-14 sh "$cl_mscript" status 2>&1 ); then cl_rc=0; else cl_rc=$?; fi
      cl_killed "CL9 mutant (the TZ pin dropped) is killed: a live holder reads as a reused pid under another TZ" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)" "$(case "$cl_out" in *"STALE (proven"*) echo 1 ;; *) echo 0 ;; esac)"
    fi
    cl_reset "$A"
    # a reused pid: the same pid with another start time is not live
    cl_plant "$A" "Lane Reused" claim "$$" "Thu Jan 1 00:00:00 1970" 100000 1 "$cl_me"
    cl_run "$A" status
    cl_has "CL9 a reused pid (another start time) reads STALE (proven" "STALE (proven"
    if cl_mutant CL9s PIDSTART 's|if \[ -n "\$_ls" \] && \[ "\$CL_PIDSTART" != "(none)" \] && \[ "\$_ls" != "\$CL_PIDSTART" \]; then|if false; then|'; then
      cl_runm "$A" status
      cl_killed "CL9 mutant (the pid-start comparison dropped) is killed: the reused pid reads live" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)" "$(case "$cl_out" in *"STALE (proven"*) echo 0 ;; *) echo 1 ;; esac)"
    fi
    cl_reset "$A"
  else
    echo "selftest SKIP: CL9 the walk and the reused pid (ps cannot be read in this environment)"
  fi

  # ---- CL9b: the parent chain hidden by a PATH-shimmed ps -----------------------------------------------
  mkdir -p "$cl_base/psshim"; printf '#!/bin/sh\nexit 1\n' > "$cl_base/psshim/ps"; chmod +x "$cl_base/psshim/ps"
  cl_x "$CL_SELF" "$cl_base/psshim" "$A" acquire --holder "Lane A" --purpose claim --pid "$$"
  cl_expect_rc 0 "CL9b with the parent chain hidden, acquire still succeeds rc 0"
  cl_has "CL9b it says the pid is unproven" "pid unproven"
  case "$(git -C "$A" cat-file blob "$(cl_ref "$A"):LEASE" 2>/dev/null || true)" in *"pid: unproven"*) cl_pass "CL9b the blob records pid: unproven" ;; *) cl_fail "CL9b the blob does not record pid: unproven" ;; esac
  cl_reset "$A"
  cl_plant "$A" "Lane Hidden" claim unproven "(none)" 100000 600 "$cl_me"
  cl_run "$A" status; cl_has "CL9b status prints pid unproven" "pid unproven"
  cl_run "$A" break --reason "the hidden lane's session has ended for sure"
  cl_expect_rc 1 "CL9b past ttl, a proof-of-death break refuses"; cl_has "CL9b it names the human dial" "KIT_LEASE_FORCE_BREAK"
  if cl_mutant CL9b UNPROVEN 's|case "\$CL_PID" in unproven) CL_WHY="pid unproven"; return 0 ;; esac|case "$CL_PID" in unproven) CL_PROOF="unproven read as dead"; return 0 ;; esac|'; then
    cl_runm "$A" break --reason "the hidden lane's session has ended for sure"
    cl_killed "CL9b mutant (unproven read as dead) is killed: a break with no proof goes through" "$([ "$cl_rc" = 0 ] || [ "$cl_rc" = 1 ] && echo 1 || echo 0)" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)"
    cl_reset "$A"; cl_plant "$A" "Lane Hidden" claim unproven "(none)" 100000 600 "$cl_me"
  fi
  if cl_out=$( cd "$A" && KIT_LEASE_FORCE_BREAK=1 sh "$CL_SELF" break --reason "the hidden lane's session has ended for sure" 2>&1 ); then cl_rc=0; else cl_rc=$?; fi
  cl_expect_rc 0 "CL9b with the human dial the break succeeds"
  cl_check "CL9b the break is logged as FORCED" "$(git -C "$A" cat-file blob "$(git -C "$A" rev-parse refs/local-lease-log/checkout):LOG" 2>/dev/null | grep -q '^proof: FORCED$' && echo 1 || echo 0)"
  cl_reset "$A"

  # ---- CL10: break needs STALE and a real reason ------------------------------------------------------------
  cl_acq "$A" "Lane A" claim
  cl_run "$A" break --reason "a live lane that is working right now"
  cl_expect_rc 1 "CL10 break on a live lease refuses"; cl_has "CL10 it says it is within its ttl" "within its ttl"
  if cl_out=$( cd "$A" && KIT_LEASE_FORCE_BREAK=1 sh "$CL_SELF" break --reason "a live lane that is working right now" 2>&1 ); then cl_rc=0; else cl_rc=$?; fi
  cl_expect_rc 1 "CL10 the human dial does not break a live lease either"
  cl_check "CL10 the live lease is unchanged" "$([ -n "$(cl_ref "$A")" ] && echo 1 || echo 0)"
  if cl_mutant CL10 STALEPRE 's|LIVE) .*|LIVE) _plabel=dead ;;   # MUT-STALEPRE|'; then
    cl_runm "$A" break --reason "a live lane that is working right now"
    cl_killed "CL10 mutant (the stale precondition dropped) is killed: a live lease is broken" "$([ "$cl_rc" = 0 ] || [ "$cl_rc" = 1 ] && echo 1 || echo 0)" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)"
  fi
  cl_reset "$A"
  cl_plant "$A" "Lane Far" claim 4242 "(none)" 100000 600 "another-machine"
  if cl_out=$( cd "$A" && KIT_LEASE_FORCE_BREAK=1 sh "$CL_SELF" break --reason "too short" 2>&1 ); then cl_rc=0; else cl_rc=$?; fi
  cl_expect_rc 2 "CL10 a short reason refuses rc 2"
  cl_check "CL10 the lease is unchanged after a short reason" "$([ "$(cl_ref "$A")" = "$cl_psha" ] && echo 1 || echo 0)"
  cl_reset "$A"

  # ---- CL11: a proven break is logged BEFORE the delete; a failed delete appends -FAILED ------------------------
  sleep 30 & cl_dp=$!
  cl_dps=$(cl_lstart "$cl_dp"); kill "$cl_dp" 2>/dev/null || true; wait "$cl_dp" 2>/dev/null || true
  cl_plant "$A" "Lane Gone" claim "$cl_dp" "${cl_dps:-(none)}" 100000 600 "$cl_me"
  if [ "$cl_ps_ok" = 1 ]; then
    cl_run "$A" break --reason "the session process of this lane has exited"
    cl_expect_rc 0 "CL11 a proven stale lease breaks rc 0"
    cl_check "CL11 the log has the entry" "$([ "$(cl_logn "$A")" = 1 ] && echo 1 || echo 0)"
    cl_check "CL11 the entry carries the proof and the old holder" "$(git -C "$A" cat-file blob "$(git -C "$A" rev-parse refs/local-lease-log/checkout):LOG" 2>/dev/null | grep -q '^old-holder: Lane Gone$' && echo 1 || echo 0)"
    cl_check "CL11 the lease is gone" "$([ -z "$(cl_ref "$A")" ] && echo 1 || echo 0)"
    cl_reset "$A"; cl_plant "$A" "Lane Gone" claim "$cl_dp" "${cl_dps:-(none)}" 100000 600 "$cl_me"
    if cl_mutant CL11 LOGFIRST 's|if ! cl_log_break "\$_plabel" "\$_reason" "\$CL_SHA"; then|if false; then|'; then
      cl_runm "$A" break --reason "the session process of this lane has exited"
      cl_killed "CL11 mutant (the log written after the delete, here never) is killed: no entry exists" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)" "$([ "$(cl_logn "$A")" = 0 ] && echo 1 || echo 0)"
    fi
    cl_reset "$A"; cl_plant "$A" "Lane Gone" claim "$cl_dp" "${cl_dps:-(none)}" 100000 600 "$cl_me"
    mkdir -p "$cl_base/delshim"
    printf '#!/bin/sh\ncase "$*" in\n  *" -d refs/local-lease/checkout "*) exit 1 ;;\nesac\nexec "%s" "$@"\n' "$cl_realgit" > "$cl_base/delshim/git"; chmod +x "$cl_base/delshim/git"
    cl_x "$CL_SELF" "$cl_base/delshim" "$A" break --reason "the session process of this lane has exited"
    cl_expect_rc 1 "CL11 a delete that fails -> rc 1"
    cl_check "CL11 the lease is still there" "$([ "$(cl_ref "$A")" = "$cl_psha" ] && echo 1 || echo 0)"
    cl_check "CL11 the log has the record AND a -FAILED entry" "$([ "$(cl_logn "$A")" = 2 ] && echo 1 || echo 0)"
    cl_check "CL11 the last entry says the delete did not happen" "$(git -C "$A" cat-file blob "$(git -C "$A" rev-parse refs/local-lease-log/checkout):LOG" 2>/dev/null | grep -q '^released-sha: (not deleted)$' && echo 1 || echo 0)"
  else
    echo "selftest SKIP: CL11 the proven break (ps cannot be read in this environment)"
  fi
  cl_reset "$A"

  # ---- CL12: the kit's verbs need the token in an enabled checkout ----------------------------------------------
  cl_acq "$A" "Lane A" claim; cl_tok12=$cl_tok
  for _v in "record" "land" "actuate"; do
    cl_x "$cl_dir/promotion-verify.sh" "" "$A" "$_v"
    cl_expect_rc 5 "CL12 promotion-verify $_v without the token -> rc 5"
  done
  cl_x "$cl_dir/board-claim.sh" "" "$A" claim ROW-1 --branch feat/x
  cl_expect_rc 5 "CL12 board-claim claim without the token -> rc 5"
  cl_x "$cl_dir/board-claim.sh" "" "$A" release ROW-1
  cl_expect_rc 5 "CL12 board-claim release without the token -> rc 5"
  cl_x "$cl_dir/board-claim.sh" "" "$A" claim-ref ROW-1 --branch feat/x
  cl_expect_rc 5 "CL12 board-claim claim-ref without the token -> rc 5"
  cl_x "$cl_dir/board-claim.sh" "" "$A" release-ref ROW-9
  cl_expect_rc 5 "CL12 board-claim release-ref without the token -> rc 5"; cl_has "CL12 it names the next act" "sparkwright lease acquire"
  cl_x "$cl_dir/board-claim.sh" "" "$A" release-ref ROW-9 --lease-token "$cl_tok12"
  cl_expect_rc 1 "CL12 release-ref WITH the holder's token runs as today (no claim -> rc 1)"
  # a claim THROUGH board.sh (the route start takes): without the token rc 5; with it the gate passes (the next refusal is the fixture's own: no board file)
  cl_x "$cl_dir/board.sh" "" "$A" claim ROW-1 --branch feat/x
  cl_expect_rc 5 "CL12 board.sh claim without the token -> rc 5"
  cl_x "$cl_dir/board.sh" "" "$A" claim ROW-1 --branch feat/x --lease-token "$cl_tok12"
  cl_expect_rc 2 "CL12 board.sh claim WITH the token passes the lease gate (rc 2 is the fixture's own: no board)"; cl_has "CL12 and reaches the board check" "no board at"
  cl_x "$cl_dir/start.sh" "" "$A" ROW-1 --branch feat/x --lease-token "$cl_tok12"
  cl_expect_rc 2 "CL12 start --lease-token forwards the token (rc 2 is the fixture's own: no board)"; cl_has "CL12 start reaches the board check" "no board at"
  cl_x "$cl_dir/board-claim.sh" "" "$C" release-ref ROW-9
  cl_expect_rc 1 "CL12 in a checkout never enabled, release-ref runs as today (rc 1)"
  cl_hasnt "CL12 and says nothing of the checkout lease" "checkout lease"
  cl_x "$cl_dir/promotion-verify.sh" "" "$C" record
  cl_expect_rc 2 "CL12 in a checkout never enabled, record runs as today (its own usage, rc 2)"
  # C5: the missing-script branch fails closed. A verb copied ALONE (no checkout-lease.sh beside it) refuses rc 5 when the key is set, and runs as today when it is not
  mkdir -p "$cl_base/alone"; cp "$cl_dir/board-claim.sh" "$cl_dir/promotion-verify.sh" "$cl_base/alone/"
  cl_x "$cl_base/alone/board-claim.sh" "" "$A" release-ref ROW-9
  cl_expect_rc 5 "CL12 C5 board-claim.sh alone, key set -> rc 5"; cl_has "CL12 C5 it says the script is missing" "checkout-lease.sh is missing"
  cl_x "$cl_base/alone/promotion-verify.sh" "" "$A" record
  cl_expect_rc 5 "CL12 C5 promotion-verify.sh alone, key set -> rc 5"; cl_has "CL12 C5 it says the script is missing too" "checkout-lease.sh is missing"
  cl_x "$cl_base/alone/board-claim.sh" "" "$C" release-ref ROW-9
  cl_expect_rc 1 "CL12 C5 board-claim.sh alone in a checkout never enabled runs as today (rc 1)"
  # C3: `land` releases the row's claim through board-claim.sh; the token stripped at dispatch must reach that release. A stub merge command and a
  # fixture GO note would be needed to run `land` itself, so the cell drives the helper's call shape: the lease-token reaches board-claim.sh's release
  # (it passes the gate and reaches its own no-claim answer, rc 1, where the pre-fix call was refused rc 5)
  cl_x "$cl_dir/board-claim.sh" "" "$A" release ROW-9 --stale --lease-token "$cl_tok12"
  cl_expect_rc 1 "CL12 C3 board-claim release ROW --stale WITH the token passes the gate (no claim -> rc 1)"
  cl_x "$cl_dir/board-claim.sh" "" "$A" release ROW-9 --stale
  cl_expect_rc 5 "CL12 C3 and without the token it is refused rc 5 (what land's release got before the token was passed on)"
  cl_reset "$A"
  cl_run "$A" gate --verb record
  cl_expect_rc 5 "CL12 in an enabled checkout with no lease held, a tokenless verb is refused rc 5"
  if cl_mutant CL12 ENABLED 's|"\$_kv" = true \]|"$_kv" != true ]|'; then
    cl_runm "$A" gate --verb record
    cl_killed "CL12 mutant (the enabled test inverted) is killed: the enabled checkout lets a tokenless verb through" "$([ "$cl_rc" = 0 ] || [ "$cl_rc" = 5 ] && echo 1 || echo 0)" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)"
  fi

  # ---- CL12b: the key removed after use fails closed ---------------------------------------------------------------
  cl_plant "$A" "Lane Far" claim 4242 "(none)" 100000 600 "another-machine"
  cl_out=$( cd "$A" && KIT_LEASE_FORCE_BREAK=1 sh "$CL_SELF" break --reason "to leave a log ref behind for the cell" 2>&1 ) || true
  cl_check "CL12b a lease-log ref exists" "$([ "$(cl_logn "$A")" = 1 ] && echo 1 || echo 0)"
  git -C "$A" config --unset kit.checkoutLease
  cl_run "$A" gate --verb record; cl_expect_rc 5 "CL12b the key gone with a log ref present: the gate refuses rc 5"; cl_has "CL12b it says a human restores it" "a human restores it"
  cl_acq "$A" "Lane A" claim; cl_expect_rc 2 "CL12b acquire refuses rc 2"; cl_has "CL12b acquire says the key is missing" "kit.checkoutLease is missing"
  cl_x "$cl_dir/promotion-verify.sh" "" "$A" record;  cl_expect_rc 5 "CL12b record refuses rc 5"
  cl_x "$cl_dir/board-claim.sh" "" "$A" release-ref ROW-9; cl_expect_rc 5 "CL12b release-ref refuses rc 5"
  # C4: the line `sparkwright doctor` prints (doctor.sh runs this verb and fails on its rc)
  cl_run "$A" doctor-line; cl_expect_rc 1 "CL12b doctor-line: the key gone beside a log ref -> rc 1"; cl_has "CL12b doctor-line reads FAIL" "lease: FAIL"
  if [ -f "$cl_dir/kit-guard" ] && [ -f "$cl_dir/../.claude/hooks/guard-core.sh" ]; then
    if sh "$cl_dir/kit-guard" cmd 'git config --unset kit.checkoutLease' >/dev/null 2>&1; then
      cl_fail "CL12b the guard allowed 'git config --unset kit.checkoutLease'"
    else cl_pass "CL12b the guard denies git config --unset kit.checkoutLease"; fi
  else echo "selftest SKIP: CL12b the guard cell (no kit-guard beside this script)"; fi
  if cl_mutant CL12b LOGREF 's|if \[ -n "\$(git for-each-ref .*|if false; then echo missing; return 0; fi   # MUT-LOGREF|'; then
    cl_runm "$A" gate --verb record
    cl_killed "CL12b mutant (the log-ref test dropped) is killed: the verbs run as today" "$([ "$cl_rc" = 0 ] || [ "$cl_rc" = 5 ] && echo 1 || echo 0)" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)"
    cl_runm "$A" doctor-line
    cl_killed "CL12b mutant (the log-ref test dropped) is killed on the doctor line: it reads off, rc 0" "$([ "$cl_rc" = 0 ] || [ "$cl_rc" = 1 ] && echo 1 || echo 0)" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)"
  fi
  # the human rollback: the key and every lease ref together
  cl_reset "$A"; git -C "$A" config --unset kit.checkoutLease
  cl_run "$A" gate --verb record; cl_expect_rc 0 "CL12b after the human rollback the verbs run as today (gate passes)"
  cl_run "$A" status; cl_expect_rc 1 "CL12b status reads free after the rollback"
  cl_run "$A" doctor-line; cl_expect_rc 0 "CL12b doctor-line after the rollback -> rc 0"; cl_has "CL12b doctor-line prints the off line" "lease: off (no key, no lease log)"
  git -C "$A" config kit.checkoutLease true
  cl_run "$A" doctor-line; cl_expect_rc 0 "CL12b doctor-line with the key set -> rc 0"; cl_has "CL12b doctor-line prints the on line" "lease: on"
  # L2: a checkout that only ever ACQUIRED and RELEASED (never broken) still reads as "used": removing the key afterwards fails closed
  cl_reset "$A"
  cl_acq "$A" "Lane A" claim; cl_tokl2=$cl_tok
  cl_run "$A" release --lease-token "$cl_tokl2"
  cl_expect_rc 0 "CL12b L2 acquire then release -> rc 0"
  cl_check "CL12b L2 no lease ref is left" "$([ -z "$(cl_ref "$A")" ] && echo 1 || echo 0)"
  git -C "$A" config --unset kit.checkoutLease
  cl_run "$A" gate --verb record
  cl_expect_rc 5 "CL12b L2 the key removed after acquire and release: the gate refuses rc 5"
  cl_run "$A" doctor-line; cl_expect_rc 1 "CL12b L2 doctor-line reads FAIL too"
  if cl_mutant CL12L USED 's|if ! KIT_LEASE_FRONT_DOOR=1 git update-ref --no-deref "\$CL_USED" "\$_commit" 2>/dev/null; then|if false; then|'; then
    cl_reset "$A"; cl_acqm "$A" "Lane A" claim; cl_tokm=$cl_tok
    cl_runm "$A" release --lease-token "$cl_tokm"
    git -C "$A" config --unset kit.checkoutLease
    cl_run "$A" gate --verb record
    cl_killed "CL12b L2 mutant (the used marker dropped) is killed: the key removal reads as never enabled" "$([ "$cl_rc" = 0 ] || [ "$cl_rc" = 5 ] && echo 1 || echo 0)" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)"
  fi
  cl_reset "$A"

  # ---- CL12c: a child commit replaces the holder (a measurement of the ceiling, not a defence) ---------------------------
  cl_acq "$A" "Lane A" claim; cl_tok12c=$cl_tok
  _child=$(printf 'child\n' | git -C "$A" commit-tree "$(git -C "$A" rev-parse "$cl_tok12c^{tree}")" -p "$cl_tok12c")
  git -C "$A" update-ref refs/local-lease/checkout "$_child"
  cl_run "$A" gate --verb record --lease-token "$cl_tok12c"
  cl_expect_rc 5 "CL12c the old holder's next act refuses rc 5 (token mismatch) after a child-commit takeover"
  git -C "$A" push -q origin "$cl_tok12c:refs/leases/land" 2>/dev/null || true
  git -C "$A" push -q origin "$_child:refs/leases/land" 2>/dev/null || true
  cl_check "CL12c MEASURED: a plain push of a child commit onto refs/leases/land replaces the holder with no +" "$([ "$(git -C "$cl_o" rev-parse --verify -q refs/leases/land 2>/dev/null || true)" = "$_child" ] && echo 1 || echo 0)"
  git -C "$cl_o" update-ref -d refs/leases/land   # the fixture origin is clean again for the land-lease cells
  cl_reset "$A"

  # ---- CL15: a malformed LEASE is refused, never shown raw ----------------------------------------------------------
  _esc=$(printf '\033')
  printf 'lease: checkout\nholder: Lane%sX\npurpose: claim\nmachine: %s\npid: 1234\npid-start: (none)\nttl-s: 600\nbase: x\nbehind: no\n' "$_esc" "$cl_me" > "$cl_base/bad1.txt"
  cl_plant_blob "$A" 10 "$cl_base/bad1.txt"; cl_run "$A" status
  cl_has "CL15 a control byte in the holder: reported MALFORMED" "MALFORMED"
  case "$cl_out" in *"$_esc"*) cl_fail "CL15 a raw ESC reached the output" ;; *) cl_pass "CL15 no raw control byte reached the output" ;; esac
  cl_reset "$A"
  printf 'lease: checkout\npurpose: claim\nmachine: %s\npid: 1234\npid-start: (none)\nttl-s: 600\nbase: x\nbehind: no\n' "$cl_me" > "$cl_base/bad2.txt"
  cl_plant_blob "$A" 10 "$cl_base/bad2.txt"; cl_run "$A" status
  cl_has "CL15 no holder: reported MALFORMED" "MALFORMED"
  cl_acq "$A" "Lane A" claim
  cl_check "CL15 acquire against a malformed lease is refused, not overwritten" "$([ "$cl_rc" = 3 ] && [ "$(cl_ref "$A")" = "$cl_psha" ] && echo 1 || echo 0)"
  cl_reset "$A"
  { printf 'lease: checkout\nholder: Lane Big\npurpose: claim\nmachine: %s\npid: 1234\npid-start: (none)\nttl-s: 600\nbase: x\nbehind: no\nnote: ' "$cl_me"; head -c 5000 /dev/zero | tr '\0' 'a'; printf '\n'; } > "$cl_base/bad3.txt"
  cl_plant_blob "$A" 10 "$cl_base/bad3.txt"; cl_run "$A" status
  cl_has "CL15 over 4096 bytes: reported MALFORMED" "MALFORMED"
  if cl_mutant CL15 SIZE 's|\[ "\$_sz" -le 4096 \] \|\| return 1|:|'; then
    cl_runm "$A" status
    cl_killed "CL15 mutant (the size bound dropped) is killed: the oversize lease is shown as held" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)" "$(case "$cl_out" in *MALFORMED*) echo 0 ;; *) echo 1 ;; esac)"
  fi
  cl_reset "$A"

  # ---- CL16 (the lease under the guard's shims): the verb's own writes are admitted ----------------------------------
  if [ -f "$cl_dir/kit-guard" ] && [ -f "$cl_dir/../.claude/hooks/guard-core.sh" ]; then
    sh "$cl_dir/kit-guard" install-shims --dir "$cl_base/shims" >/dev/null 2>&1 || true
    cl_x "$CL_SELF" "$cl_base/shims" "$A" acquire --holder "Lane A" --purpose claim --pid "$$"
    cl_expect_rc 0 "CL16 under install-shims the verb's own acquire is admitted"
    cl_x "$CL_SELF" "$cl_base/shims" "$A" release --lease-token "$(printf '%s\n' "$cl_out" | sed -n 's/^lease-token: //p' | head -1)"
    cl_expect_rc 0 "CL16 under install-shims the verb's own release is admitted"
    cl_reset "$A"; cl_acq "$A" "Lane A" claim
    if cl_out=$( cd "$A" && PATH="$cl_base/shims:$PATH" git update-ref refs/local-lease/checkout "$cl_zero" 2>&1 ); then cl_rc=0; else cl_rc=$?; fi
    cl_expect_rc 1 "CL16 under install-shims a raw update-ref of the lease ref is denied"
    cl_check "CL16 and the lease is unchanged" "$([ -n "$(cl_ref "$A")" ] && echo 1 || echo 0)"
    cl_reset "$A"
    # ---- CL16b (SWAS-839, SWAS-842): the land lease's own push and its LEASED DELETE under the shims are admitted; a raw push to refs/leases/* is denied (R38).
    # The delete was a measured refusal (SWAS-839: the force-push rule met `--force-with-lease`); SWAS-842 admits that one grammar-exact compare-and-swap delete
    # under the lease sentinel, so it is an assertion now, and so is the next acquire.
    cl_b16=$(git -C "$cl_o" rev-parse --verify -q refs/heads/main)
    if cl_out=$( cd "$C" && PATH="$cl_base/shims:$PATH" git push origin "$cl_b16:refs/leases/raw-cell" 2>&1 ); then cl_rc=0; else cl_rc=$?; fi
    cl_expect_rc 1 "CL16b under install-shims a raw push to refs/leases/* is denied"
    cl_check "CL16b and origin has no such ref" "$([ -z "$(git -C "$cl_o" rev-parse --verify -q refs/leases/raw-cell 2>/dev/null || true)" ] && echo 1 || echo 0)"
    cl_x "$CL_SELF" "$cl_base/shims" "$C" acquire --lease land --holder lane-a --purpose land --run 1/1 --expect-base "$cl_b16"
    cl_expect_rc 0 "CL16b under install-shims the land lease's own push is admitted"
    cl_t16=$(printf '%s\n' "$cl_out" | sed -n 's/^lease-token: //p' | head -1)
    cl_check "CL16b origin holds the lease the verb printed" "$([ -n "$cl_t16" ] && [ "$(git -C "$cl_o" rev-parse --verify -q refs/leases/land 2>/dev/null || true)" = "$cl_t16" ] && echo 1 || echo 0)"
    # the leased delete is ADMITTED under the shims (SWAS-842): rc 0, the lease is gone from origin, no -FAILED entry, and the next acquire succeeds (the next land is not blocked)
    cl_x "$CL_SELF" "$cl_base/shims" "$C" release --lease land --lease-token "$cl_t16"
    cl_expect_rc 0 "CL16b under install-shims the verb's leased delete is admitted (rc 0)"
    cl_check "CL16b the lease is gone from origin" "$([ -z "$(git -C "$cl_o" rev-parse --verify -q refs/leases/land 2>/dev/null || true)" ] && echo 1 || echo 0)"
    cl_check "CL16b no -FAILED entry was appended to the land log" "$(git -C "$cl_o" cat-file blob refs/leases-log/land:LOG 2>/dev/null | grep -q '^proof: release-FAILED$' && echo 0 || echo 1)"
    cl_x "$CL_SELF" "$cl_base/shims" "$C" acquire --lease land --holder lane-a --purpose land --run 1/1 --expect-base "$cl_b16"
    cl_expect_rc 0 "CL16b the next acquire under install-shims succeeds, so the next land is not blocked"
    git -C "$cl_o" update-ref -d refs/leases/land; git -C "$cl_o" update-ref -d refs/leases-log/land 2>/dev/null || true   # the fixture origin is clean again
  else echo "selftest SKIP: CL16 the shims leg (no kit-guard beside this script)"; fi

  # ---- CL16c: the lease's push names the origin URL as configured (https), never the path it resolves to (a path-shaped origin reds this) ----------------
  mkdir -p "$cl_base/argvshim"
  printf '#!/bin/sh\ncase " $* " in\n  *" push "*) printf "%%s\\n" "$*" >> "%s/argv.log" ;;\nesac\nexec "%s" "$@"\n' "$cl_base" "$cl_realgit" > "$cl_base/argvshim/git"
  chmod +x "$cl_base/argvshim/git"
  cl_x "$CL_SELF" "$cl_base/argvshim" "$C" acquire --lease land --holder lane-a --purpose land --run 1/1 --expect-base "$(git -C "$cl_o" rev-parse --verify -q refs/heads/main)"
  cl_expect_rc 0 "CL16c the land lease is taken through the https-shaped origin"
  cl_check "CL16c the push argv names the https URL" "$(grep -qF "$cl_ourl" "$cl_base/argv.log" 2>/dev/null && echo 1 || echo 0)"
  cl_check "CL16c and not the bare directory it maps to" "$(grep -qF "$cl_o" "$cl_base/argv.log" 2>/dev/null && echo 0 || echo 1)"
  git -C "$cl_o" update-ref -d refs/leases/land

  # ---- CL17: the --holder grammar ------------------------------------------------------------------------------------
  cl_run "$A" acquire --holder "$(printf 'Lane\nB')" --purpose claim --pid "$$"
  cl_expect_rc 2 "CL17 a multi-line holder is refused rc 2"
  cl_run "$A" acquire --holder "$(printf 'Lane\033B')" --purpose claim --pid "$$"
  cl_expect_rc 2 "CL17 a control-byte holder is refused rc 2"
  cl_run "$A" acquire --holder "$(head -c 41 /dev/zero | tr '\0' 'a')" --purpose claim --pid "$$"
  cl_expect_rc 2 "CL17 an over-long holder (41) is refused rc 2"
  mkdir -p "$A/.kit"; printf '# lanes\nLane A\nLane B\n' > "$A/.kit/lanes.conf"
  cl_acq "$A" "Lane Z" claim
  cl_expect_rc 2 "CL17 with lanes.conf, an unlisted name is refused rc 2"
  cl_check "CL17 and nothing was written" "$([ -z "$(cl_ref "$A")" ] && echo 1 || echo 0)"
  cl_acq "$A" "Lane A" claim
  cl_expect_rc 0 "CL17 a listed name is accepted"
  rm -f "$A/.kit/lanes.conf"
  cl_reset "$A"
  cl_run "$A" acquire --holder "Lane A" --purpose claim --pid "$$" --lease land
  cl_expect_rc 2 "the land lease is taken for --purpose land or actuate only: claim refused rc 2"

  # ======================= THE LAND LEASE (SWAS-192 slice B, card SWAS-839) =======================
  # A and B stand in for two machines (each its own machine id); C never opted in (the CI shape). The origin is the https-shaped fixture URL.
  B="$cl_base/B"; cl_ghmk
  git -C "$C" config --add "url.$cl_o.insteadOf" "https://github.com/owner-login/repo-a.git"
  cl_check "CL14 the epoch of a timestamp round-trips (no date dialect)" "$([ "$(cl_epoch "$(cl_iso8601 1767225600)")" = 1767225600 ] && [ "$(cl_epoch 1970-01-01T00:00:00Z)" = 0 ] && echo 1 || echo 0)"

  # ---- CL13: two acquirers -----------------------------------------------------------------------------------------
  cl_reset "$A"; cl_reset "$B"; cl_lclear
  cl_lacq "$A" lane-a land; cl_tokA=$cl_ltok
  cl_expect_rc 0 "CL13 the first acquirer takes the land lease"
  cl_check "CL13 origin holds exactly the sha the verb printed" "$([ -n "$cl_tokA" ] && [ "$(cl_lref)" = "$cl_tokA" ] && echo 1 || echo 0)"
  cl_lacq "$B" lane-b land
  cl_expect_rc 3 "CL13 a second acquirer is refused rc 3"; cl_has "CL13 the holder is named" 'HELD by "lane-a"'
  cl_check "CL13 and origin's lease is unchanged" "$([ "$(cl_lref)" = "$cl_tokA" ] && echo 1 || echo 0)"
  if cl_mutant CL13 LPUSH 's|"\$_lcommit:\$CL_LREF"|"+$_lcommit:$CL_LREF"|'; then
    cl_reset "$B"; cl_lacqm "$B" lane-b land
    cl_killed "CL13 mutant (+ added to the push) is killed: the second acquirer overwrites the holder" "$([ "$cl_rc" = 0 ] || [ "$cl_rc" = 3 ] && echo 1 || echo 0)" "$([ "$(cl_lref)" != "$cl_tokA" ] && echo 1 || echo 0)"
  fi

  # ---- CL13b: the ref moves between the verified read and the delete: the delete is leased, so the newer lease is left alone ----------
  cl_reset "$A"; cl_reset "$B"; cl_lclear
  cl_lacq "$A" lane-a land; cl_tok13b=$cl_ltok
  mkdir -p "$cl_base/mvshim"
  printf '#!/bin/sh\ncase "$*" in\n  *" :refs/leases/land"*)\n    g="%s -C %s"\n    cur=$($g rev-parse --verify -q refs/leases/land)\n    c=$(echo moved | GIT_AUTHOR_NAME=x GIT_AUTHOR_EMAIL=x@x GIT_COMMITTER_NAME=x GIT_COMMITTER_EMAIL=x@x $g commit-tree "$($g rev-parse "$cur^{tree}")" -p "$cur")\n    $g update-ref refs/leases/land "$c" ;;\nesac\nexec "%s" "$@"\n' "$cl_realgit" "$cl_o" "$cl_realgit" > "$cl_base/mvshim/git"
  chmod +x "$cl_base/mvshim/git"
  cl_x "$CL_SELF" "$cl_base/mvshim" "$A" release --lease land --lease-token "$cl_tok13b"
  cl_expect_rc 1 "CL13b release when the ref moved under it -> rc 1"
  cl_check "CL13b the newer lease is still on origin" "$([ -n "$(cl_lref)" ] && [ "$(cl_lref)" != "$cl_tok13b" ] && echo 1 || echo 0)"
  if cl_mutant CL13b LDEL 's|--force-with-lease="\$CL_LREF:\$1" ||'; then
    cl_lclear; cl_reset "$A"; cl_lacq "$A" lane-a land; cl_tok13b=$cl_ltok
    cl_x "$cl_mscript" "$cl_base/mvshim" "$A" release --lease land --lease-token "$cl_tok13b"
    cl_killed "CL13b mutant (delete without the lease) is killed: the newer lease is deleted" "$([ "$cl_rc" = 0 ] || [ "$cl_rc" = 1 ] && echo 1 || echo 0)" "$([ -z "$(cl_lref)" ] && echo 1 || echo 0)"
  fi

  # ---- CL15b: a fetched LEASE is bounded, printable, never shown raw; the fetch never touches the checkout --------------------------------
  cl_lclear; cl_reset "$A"
  cl_sh0=$([ -e "$A/.git/shallow" ] && echo 1 || echo 0)
  cl_fh0=$(cksum < "$A/.git/FETCH_HEAD" 2>/dev/null || echo none); cl_co0=$(git -C "$A" count-objects -v | cksum)
  printf 'lease: land\nholder: lane%sx\npurpose: land\nmachine: ci\npid: unproven\npid-start: (none)\nttl-s: 2700\n' "$_esc" > "$cl_base/b15.txt"
  cl_lplant_blob 10 "$cl_base/b15.txt"; cl_run "$A" status --lease land
  cl_has "CL15b a control byte in the holder: MALFORMED" "MALFORMED"
  case "$cl_out" in *"$_esc"*) cl_fail "CL15b a raw ESC reached the output" ;; *) cl_pass "CL15b no raw control byte reached the output" ;; esac
  printf 'lease: land\npurpose: land\nmachine: ci\npid: unproven\npid-start: (none)\nttl-s: 2700\n' > "$cl_base/b15.txt"
  cl_lplant_blob 10 "$cl_base/b15.txt"; cl_run "$A" status --lease land; cl_has "CL15b no holder: MALFORMED" "MALFORMED"
  printf 'lease: land\nholder: train\npurpose: land\nrun: 1;x\nmachine: ci\npid: unproven\npid-start: (none)\nttl-s: 2700\n' > "$cl_base/b15.txt"
  cl_lplant_blob 10 "$cl_base/b15.txt"; cl_run "$A" status --lease land; cl_has "CL15b a bad run: MALFORMED" "MALFORMED"
  { printf 'lease: land\nholder: train\npurpose: land\nmachine: ci\npid: unproven\npid-start: (none)\nttl-s: 2700\nnote: '; head -c 5000 /dev/zero | tr '\0' 'a'; printf '\n'; } > "$cl_base/b15.txt"
  cl_lplant_blob 10 "$cl_base/b15.txt"; cl_run "$A" status --lease land; cl_has "CL15b over 4096 bytes: MALFORMED" "MALFORMED"
  cl_check "CL15b the checkout is untouched: no .git/shallow, the same objects, the same FETCH_HEAD" "$([ "$([ -e "$A/.git/shallow" ] && echo 1 || echo 0)" = "$cl_sh0" ] && [ "$(git -C "$A" count-objects -v | cksum)" = "$cl_co0" ] && [ "$(cksum < "$A/.git/FETCH_HEAD" 2>/dev/null || echo none)" = "$cl_fh0" ] && echo 1 || echo 0)"
  if cl_mutant CL15b LTMP 's|CL_GD=\$(cl_iso) \|\| return 2|CL_GD=.|'; then
    cl_runm "$A" status --lease land
    cl_killed "CL15b mutant (the fetch into the checkout) is killed: the checkout gains a scratch ref" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)" "$([ -n "$(git -C "$A" rev-parse --verify -q refs/scratch 2>/dev/null || true)" ] && echo 1 || echo 0)"
    rm -f "$A/.git/shallow"; git -C "$A" update-ref -d refs/scratch 2>/dev/null || true
  fi
  # a fetched commit that is not the sha read is re-read once, then refused (never classified)
  cl_lplant 10 train land ci unproven "(none)" ""
  mkdir -p "$cl_base/lieshim"
  printf '#!/bin/sh\nif [ "$1" = ls-remote ]; then "%s" "$@" | sed "s/^[0-9a-f]*/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/"; exit 0; fi\nexec "%s" "$@"\n' "$cl_realgit" "$cl_realgit" > "$cl_base/lieshim/git"
  chmod +x "$cl_base/lieshim/git"
  cl_x "$CL_SELF" "$cl_base/lieshim" "$A" status --lease land
  cl_expect_rc 2 "CL15b a sha that differs from the fetched commit is re-read, then refused (UNKNOWN, rc 2)"; cl_has "CL15b and it says UNKNOWN" "UNKNOWN"
  if cl_mutant CL15b2 LSHAEQ 's|if \[ "\$_lgot" = "\$_lsha" \]; then|if true; then|'; then
    cl_x "$cl_mscript" "$cl_base/lieshim" "$A" status --lease land
    cl_killed "CL15b mutant (the sha-equality check dropped) is killed: the unread lease is classified" "$([ "$cl_rc" = 0 ] || [ "$cl_rc" = 2 ] && echo 1 || echo 0)" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)"
  fi
  cl_lclear

  # ---- CL20: origin unreachable is never "free" ------------------------------------------------------------------------------
  cl_reset "$A"; cl_acq "$A" lane-a claim; cl_ctok20=$cl_tok
  git -C "$A" remote set-url origin "$cl_base/no-such-origin"
  cl_run "$A" acquire --lease land --purpose land --pid "$$" --lease-token "$cl_ctok20"
  cl_expect_rc 2 "CL20 acquire with origin unreachable -> rc 2"
  cl_run "$A" status --lease land
  cl_expect_rc 2 "CL20 status with origin unreachable -> UNKNOWN, rc 2"; cl_hasnt "CL20 never FREE" "FREE"
  if cl_mutant CL20 LUNREACH 's|if \[ "\$_lo" = 2 \]; then return 1; fi|if [ "$_lo" != 0 ]; then return 1; fi|'; then
    cl_runm "$A" status --lease land
    cl_killed "CL20 mutant (unreachable read as free) is killed: status says FREE" "$([ "$cl_rc" = 1 ] || [ "$cl_rc" = 2 ] && echo 1 || echo 0)" "$([ "$cl_rc" = 1 ] && echo 1 || echo 0)"
  fi
  cl_reset "$A"

  # ---- CL21: nothing personal on origin (B4) -----------------------------------------------------------------------------------
  cl_lclear; cl_lacq "$A" lane-a land; cl_c21=$(cl_lref)
  cl_check "CL21 author and committer are the fixed identity" "$([ "$(git -C "$cl_o" log -1 --format='%an <%ae>|%cn <%ce>' "$cl_c21" 2>/dev/null)" = "kit <kit@lease.invalid>|kit <kit@lease.invalid>" ] && echo 1 || echo 0)"
  cl_blob21=$(git -C "$cl_o" cat-file blob "$cl_c21:LEASE" 2>/dev/null || true); cl_raw21=$(git -C "$cl_o" cat-file commit "$cl_c21" 2>/dev/null || true)
  cl_mid21=$(cat "$A/.git/kit-lease-machine" 2>/dev/null || true)
  cl_check "CL21 the machine is a 16-hex id, equal to this checkout's id file" "$([ "${#cl_mid21}" = 16 ] && printf '%s\n' "$cl_blob21" | grep -qx "machine: $cl_mid21" && echo 1 || echo 0)"
  cl_hn=$(uname -n)
  cl_check "CL21 neither the hostname nor the git name or email is in the commit or the blob" "$( { [ "${#cl_hn}" -lt 4 ] || ! printf '%s\n%s\n' "$cl_blob21" "$cl_raw21" | grep -qiF -- "$cl_hn"; } && ! printf '%s\n%s\n' "$cl_blob21" "$cl_raw21" | grep -qF -e "Lane A" -e "a@example.com" && echo 1 || echo 0)"
  cl_check "CL21 no note line on origin" "$(printf '%s\n' "$cl_blob21" | grep -q '^note:' && echo 0 || echo 1)"
  cl_fp21=$(cat "$A/.git/kit-lease-host" 2>/dev/null || true)
  cl_check "CL21 the local host fingerprint exists and is not on origin" "$([ -n "$cl_fp21" ] && ! printf '%s\n%s\n' "$cl_blob21" "$cl_raw21" | grep -qF -- "$cl_fp21" && echo 1 || echo 0)"
  if cl_mutant CL21 LIDENT 's|_cn=kit; _ce=kit@lease.invalid|_cn=$(git config user.name); _ce=$(git config user.email)|'; then
    cl_lclear; cl_reset "$A"; cl_lacqm "$A" lane-a land
    cl_killed "CL21 mutant (the person's git identity used) is killed: the commit carries it" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)" "$([ "$(git -C "$cl_o" log -1 --format='%an' "$(cl_lref)" 2>/dev/null)" = "Lane A" ] && echo 1 || echo 0)"
  fi
  if cl_mutant CL21h LHOST 's|_lmachine=\$(cl_mid_make)|_lmachine=$(cl_machine)|'; then
    cl_lclear; cl_reset "$A"; cl_lacqm "$A" lane-a land
    cl_killed "CL21 mutant (the hostname written) is killed: the blob carries it" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)" "$(git -C "$cl_o" cat-file blob "$(cl_lref):LEASE" 2>/dev/null | grep -qx "machine: $(cl_machine)" && echo 1 || echo 0)"
  fi
  cl_lclear; cl_reset "$A"
  # CL21b (S2): a .git copied from another host carries a fingerprint that no longer matches, so the id is made again
  cl_old21=$(cat "$A/.git/kit-lease-machine" 2>/dev/null || true)
  printf 'fingerprint-of-another-host\n' > "$A/.git/kit-lease-host"
  cl_lacq "$A" lane-a land
  cl_new21=$(cat "$A/.git/kit-lease-machine" 2>/dev/null || true)
  cl_check "CL21b a fingerprint that no longer matches makes a new id, the one the lease carries" "$([ -n "$cl_new21" ] && [ "$cl_new21" != "$cl_old21" ] && git -C "$cl_o" cat-file blob "$(cl_lref):LEASE" 2>/dev/null | grep -qx "machine: $cl_new21" && echo 1 || echo 0)"
  cl_check "CL21b and the fingerprint file is this host's again" "$([ "$(cat "$A/.git/kit-lease-host" 2>/dev/null)" = "$(cl_hostfp)" ] && echo 1 || echo 0)"
  cl_check "CL21b the old id and the fingerprint are not on origin, and no previous-id file is kept" "$([ -n "$cl_old21" ] && [ ! -e "$A/.git/kit-lease-machine.prev" ] && ! { git -C "$cl_o" cat-file blob "$(cl_lref):LEASE"; git -C "$cl_o" cat-file commit "$(cl_lref)"; } 2>/dev/null | grep -qF -e "$cl_old21" -e "$(cat "$A/.git/kit-lease-host" 2>/dev/null)" && echo 1 || echo 0)"
  if cl_mutant CL21b LFP 's,\[ "\$_hk" = "\$_cur" \],true,'; then
    cl_lclear; cl_reset "$A"; printf 'fingerprint-of-another-host\n' > "$A/.git/kit-lease-host"
    cl_lacqm "$A" lane-a land
    cl_killed "CL21b mutant (the fingerprint ignored) is killed: the copied id is kept" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)" "$([ "$(cat "$A/.git/kit-lease-machine" 2>/dev/null)" = "$cl_new21" ] && echo 1 || echo 0)"
  fi
  # an id file with NO fingerprint file beside it is a mismatch: the old id is not adopted (age only) and the next acquire makes a new one
  cl_lclear; cl_reset "$A"; cl_hostfp > "$A/.git/kit-lease-host"
  cl_old21m=$(cat "$A/.git/kit-lease-machine" 2>/dev/null || true)
  cl_lplant 100000 lane-a land "$cl_old21m" 4242 "(none)" ""
  rm -f "$A/.git/kit-lease-host"
  cl_run "$A" status --lease land
  cl_has "CL21b with no fingerprint file beside the id, the old id is not adopted (age only)" "STALE (age only"
  cl_lclear; cl_lacq "$A" lane-a land
  cl_check "CL21b and the next acquire makes a new id" "$([ -n "$(cat "$A/.git/kit-lease-machine" 2>/dev/null)" ] && [ "$(cat "$A/.git/kit-lease-machine" 2>/dev/null)" != "$cl_old21m" ] && echo 1 || echo 0)"
  cl_lclear; cl_reset "$A"
  # The hardware id is a FAKE here (the PATH shims at the top of this selftest; hw.id and hw.host are rewritten by the cells; no real id is ever read).
  # CL21c: a copy (the fingerprint no longer matches) gets a new id, and a dead-pid lease under the OLD id reads as another machine: age only, never proven.
  # CL21d: a network rename (the host NAME changes, the hardware id does not) keeps the id, so the dead-pid lease stays STALE (proven).
  # CL21e: with no hardware source the host name stands in, so a rename is a new id and a lost proof, never a false one.
  if [ "$cl_ps_ok" = 1 ]; then
    cl_hostfp > "$A/.git/kit-lease-host"
    cl_old21c=$(cat "$A/.git/kit-lease-machine" 2>/dev/null || true)
    cl_lplant 100000 lane-a land "$cl_old21c" "$cl_dp" "${cl_dps:-(none)}" ""
    cl_run "$A" status --lease land; cl_has "CL21c (control) the fingerprint unchanged: the dead-pid holder reads STALE (proven)" "STALE (proven"
    printf 'FAKE-HWID-B\n' > "$cl_base/hw.id"   # another machine's hardware: what a copied .git looks like
    cl_run "$A" status --lease land
    cl_has "CL21c a copy (the fingerprint changed): a dead-pid lease under the old id is NOT proven" "STALE (age only"
    cl_hasnt "CL21c and never STALE (proven)" "STALE (proven"
    cl_lacq "$A" lane-a land
    cl_check "CL21c the copy makes a new id" "$([ -n "$(cat "$A/.git/kit-lease-machine" 2>/dev/null)" ] && [ "$(cat "$A/.git/kit-lease-machine" 2>/dev/null)" != "$cl_old21c" ] && echo 1 || echo 0)"
    if cl_mutant CL21c LFP 's,\[ "\$_hk" = "\$_cur" \],true,'; then
      printf 'FAKE-HWID-A\n' > "$cl_base/hw.id"; cl_lclear; cl_reset "$A"; cl_hostfp > "$A/.git/kit-lease-host"
      cl_old21c=$(cat "$A/.git/kit-lease-machine" 2>/dev/null || true)
      cl_lplant 10 lane-a land "$cl_old21c" "$cl_dp" "${cl_dps:-(none)}" ""
      printf 'FAKE-HWID-B\n' > "$cl_base/hw.id"
      cl_runm "$A" status --lease land
      cl_killed "CL21c mutant (the old id accepted after a copy) is killed: the dead-pid holder is proven" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)" "$(case "$cl_out" in *"STALE (proven"*) echo 1 ;; *) echo 0 ;; esac)"
    fi
    # CL21d: the host NAME changes, the hardware does not
    printf 'FAKE-HWID-A\n' > "$cl_base/hw.id"; cl_lclear; cl_reset "$A"; cl_hostfp > "$A/.git/kit-lease-host"
    cl_old21d=$(cat "$A/.git/kit-lease-machine" 2>/dev/null || true)
    cl_lplant 10 lane-a land "$cl_old21d" "$cl_dp" "${cl_dps:-(none)}" ""
    printf 'fake-host-b\n' > "$cl_base/hw.host"
    cl_run "$A" status --lease land
    cl_has "CL21d a network rename (the host name changes, the hardware id does not): the dead-pid lease stays STALE (proven)" "STALE (proven"
    cl_lclear; cl_lacq "$A" lane-a land
    cl_check "CL21d and the id is kept" "$([ "$(cat "$A/.git/kit-lease-machine" 2>/dev/null)" = "$cl_old21d" ] && echo 1 || echo 0)"
    if cl_mutant CL21d LHWID 's,if \[ -z "\$_hu" \]; then,if true; then,'; then
      printf 'fake-host-a\n' > "$cl_base/hw.host"; rm -f "$A/.git/kit-lease-host"; cl_lclear; cl_reset "$A"
      cl_lacqm "$A" lane-a land; cl_lclear   # the mutant records its own (host-name) fingerprint when it makes or finds the id
      cl_lplant 10 lane-a land "$(cat "$A/.git/kit-lease-machine" 2>/dev/null || true)" "$cl_dp" "${cl_dps:-(none)}" ""
      printf 'fake-host-b\n' > "$cl_base/hw.host"
      cl_runm "$A" status --lease land
      cl_killed "CL21d mutant (a host-name fingerprint) is killed: a rename loses the proof" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)" "$(case "$cl_out" in *"STALE (proven"*) echo 0 ;; *) echo 1 ;; esac)"
    fi
    # CL21e: no hardware source (the shim answers nothing): the host name stands in
    printf 'fake-host-a\n' > "$cl_base/hw.host"; rm -f "$cl_base/hw.id"; cl_lclear; cl_reset "$A"; cl_hostfp > "$A/.git/kit-lease-host"
    cl_old21e=$(cat "$A/.git/kit-lease-machine" 2>/dev/null || true)
    cl_lplant 100000 lane-a land "$cl_old21e" "$cl_dp" "${cl_dps:-(none)}" ""
    printf 'fake-host-b\n' > "$cl_base/hw.host"
    cl_run "$A" status --lease land
    cl_has "CL21e no hardware source and a host rename: the old lease reads as another machine (age only)" "STALE (age only"
    cl_hasnt "CL21e and never STALE (proven)" "STALE (proven"
    if cl_mutant CL21e LUNAME 's,_hu="uname:\$_un",_hu="uname:const",'; then
      printf 'fake-host-a\n' > "$cl_base/hw.host"; rm -f "$A/.git/kit-lease-host"; cl_lclear; cl_reset "$A"
      cl_lacqm "$A" lane-a land; cl_lclear   # the mutant records its own (constant) fingerprint when it makes the id
      cl_lplant 100000 lane-a land "$(cat "$A/.git/kit-lease-machine" 2>/dev/null || true)" "$cl_dp" "${cl_dps:-(none)}" ""
      printf 'fake-host-b\n' > "$cl_base/hw.host"
      cl_runm "$A" status --lease land
      cl_killed "CL21e mutant (the host name replaced by a constant) is killed: a rename keeps the id and the dead-pid holder is proven" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)" "$(case "$cl_out" in *"STALE (proven"*) echo 1 ;; *) echo 0 ;; esac)"
    fi
    # CL21f: two containers share one machine id and one .git but have separate pid namespaces. The fake machine id and namespace come through the shims
    # (cat answers /etc/machine-id from hw.mid, readlink answers /proc/self/ns/pid from hw.ns); the real ones are never read.
    rm -f "$cl_base/hw.id"; printf 'FAKE-MID-1\n' > "$cl_base/hw.mid"; printf 'pid:[4026000001]\n' > "$cl_base/hw.ns"; printf 'fake-host-a\n' > "$cl_base/hw.host"
    cl_lclear; cl_reset "$A"; cl_hostfp > "$A/.git/kit-lease-host"
    cl_old21f=$(cat "$A/.git/kit-lease-machine" 2>/dev/null || true)
    cl_lplant 100000 lane-a land "$cl_old21f" "$cl_dp" "${cl_dps:-(none)}" ""
    cl_run "$A" status --lease land; cl_has "CL21f (control) the same machine id and the same pid namespace: the dead-pid holder reads STALE (proven)" "STALE (proven"
    printf 'pid:[4026000002]\n' > "$cl_base/hw.ns"
    cl_run "$A" status --lease land
    cl_has "CL21f the same machine id in another pid namespace: age only" "STALE (age only"; cl_hasnt "CL21f and never STALE (proven)" "STALE (proven"
    rm -f "$cl_base/hw.ns"
    cl_run "$A" status --lease land
    cl_has "CL21f no readable pid namespace: no fingerprint, no id, age only" "STALE (age only"
    if cl_mutant CL21f LNS 's,_ns=\$(readlink /proc/self/ns/pid 2>/dev/null || true),_ns=same,'; then
      printf 'pid:[4026000001]\n' > "$cl_base/hw.ns"; rm -f "$A/.git/kit-lease-host"; cl_lclear; cl_reset "$A"
      cl_lacqm "$A" lane-a land; cl_lclear   # the mutant records its own fingerprint (no namespace in it) when it makes the id
      cl_lplant 100000 lane-a land "$(cat "$A/.git/kit-lease-machine" 2>/dev/null || true)" "$cl_dp" "${cl_dps:-(none)}" ""
      printf 'pid:[4026000002]\n' > "$cl_base/hw.ns"
      cl_runm "$A" status --lease land
      cl_killed "CL21f mutant (the namespace not mixed in) is killed: another namespace is read as this machine and the holder is proven" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)" "$(case "$cl_out" in *"STALE (proven"*) echo 1 ;; *) echo 0 ;; esac)"
    fi
    rm -f "$cl_base/hw.mid" "$cl_base/hw.ns"; printf 'FAKE-HWID-A\n' > "$cl_base/hw.id"; printf 'fake-host-a\n' > "$cl_base/hw.host"
  else
    echo "selftest SKIP: CL21c to CL21f the fingerprint proofs (ps cannot be read in this environment)"
  fi
  cl_lclear; cl_reset "$A"; cl_hostfp > "$A/.git/kit-lease-host"

  # ---- CL18: the checkout token is the order check; the CI form is not for an opted-in checkout --------------------------------------
  cl_acq "$A" lane-a claim; cl_ctok18=$cl_tok
  cl_run "$A" acquire --lease land --purpose land --pid "$$"
  cl_expect_rc 5 "CL18 without the checkout token -> rc 5"
  cl_run "$A" acquire --lease land --purpose land --pid "$$" --lease-token "$cl_zero"
  cl_expect_rc 5 "CL18 with a wrong checkout token -> rc 5"
  cl_check "CL18 nothing was pushed" "$([ -z "$(cl_lref)" ] && echo 1 || echo 0)"
  cl_run "$A" acquire --lease land --holder lane-a --purpose land --run 1/1 --expect-base "$(git -C "$cl_o" rev-parse --verify -q refs/heads/main)"
  cl_expect_rc 2 "CL18 --run in an opted-in checkout -> rc 2"
  cl_check "CL18 and nothing was pushed" "$([ -z "$(cl_lref)" ] && echo 1 || echo 0)"
  cl_run "$A" acquire --lease land --purpose land --pid "$$" --lease-token "$cl_ctok18"
  cl_expect_rc 0 "CL18 with the checkout token -> rc 0"
  cl_check "CL18 the holder is the checkout lease's holder" "$(git -C "$cl_o" cat-file blob "$(cl_lref):LEASE" 2>/dev/null | grep -qx 'holder: lane-a' && echo 1 || echo 0)"
  if cl_mutant CL18 LORDER 's|if ! cl_match "\$_ctok"; then|if false; then|'; then
    cl_lclear
    cl_runm "$A" acquire --lease land --purpose land --pid "$$" --lease-token "$cl_zero"
    cl_killed "CL18 mutant (the token check dropped) is killed: a wrong token takes the lease" "$([ "$cl_rc" = 0 ] || [ "$cl_rc" = 5 ] && echo 1 || echo 0)" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)"
  fi
  if cl_mutant CL18c LCIFORM 's,in on|missing),in never),'; then
    cl_lclear
    cl_runm "$A" acquire --lease land --holder lane-a --purpose land --run 1/1 --expect-base "$(git -C "$cl_o" rev-parse --verify -q refs/heads/main)"
    cl_killed "CL18 mutant (--run accepted when opted in) is killed: the CI form takes the lease" "$([ "$cl_rc" = 0 ] || [ "$cl_rc" = 2 ] && echo 1 || echo 0)" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)"
  fi
  cl_lclear; cl_reset "$A"

  # ---- CL8b, CL8c: a holder on another machine is age only; a holder on this machine whose pid is dead is proven at ANY age (B8) ----------------
  if [ "$cl_ps_ok" = 1 ]; then
    cl_lclear; cl_mid8=$(cat "$A/.git/kit-lease-machine" 2>/dev/null || echo 0123456789abcdef)
    cl_lplant 100000 lane-b land bbbbbbbbbbbbbbbb "$cl_dp" "${cl_dps:-(none)}" ""
    cl_run "$A" status --lease land; cl_has "CL8b another machine, dead pid, past ttl: STALE (age only)" "STALE (age only"
    cl_run "$A" break --lease land --reason "the far lane is long gone, owner confirmed"
    cl_expect_rc 1 "CL8b break without the dial refuses"; cl_has "CL8b it names the human dial" "KIT_LEASE_FORCE_BREAK"
    cl_check "CL8b the lease is unchanged" "$([ "$(cl_lref)" = "$cl_lpsha" ] && echo 1 || echo 0)"
    if cl_mutant CL8b LMACH 's|if \[ "\$CL_MACHINE" != "\$(cl_mymachine)" \]; then|if false; then|'; then
      cl_runm "$A" break --lease land --reason "the far lane is long gone, owner confirmed"
      cl_killed "CL8b mutant (another machine read as proven) is killed: the break goes through" "$([ "$cl_rc" = 0 ] || [ "$cl_rc" = 1 ] && echo 1 || echo 0)" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)"
      cl_lclear; cl_lplant 100000 lane-b land bbbbbbbbbbbbbbbb "$cl_dp" "${cl_dps:-(none)}" ""
    fi
    if cl_out=$( cd "$A" && KIT_LEASE_FORCE_BREAK=1 sh "$CL_SELF" break --lease land --reason "the far lane is long gone, owner confirmed" 2>&1 ); then cl_rc=0; else cl_rc=$?; fi
    cl_expect_rc 0 "CL8b with the human dial the break succeeds"
    cl_check "CL8b it is logged as FORCED, and the lease is gone" "$(cl_llogtxt | grep -q '^proof: FORCED$' && [ -z "$(cl_lref)" ] && echo 1 || echo 0)"
    cl_lclear
    cl_lplant 10 lane-a land "$cl_mid8" "$cl_dp" "${cl_dps:-(none)}" ""
    cl_run "$A" status --lease land; cl_has "CL8c this machine, dead pid, INSIDE the ttl: STALE (proven)" "STALE (proven"
    if cl_mutant CL8c LANYAGE 's|if \[ -n "\$CL_PROOF" \]; then CL_CLASS=STALE-PROVEN; return 0; fi|if [ -n "$CL_PROOF" ] \&\& [ "$CL_AGE" -gt "$CL_TTL" ]; then CL_CLASS=STALE-PROVEN; return 0; fi|'; then
      cl_runm "$A" status --lease land
      cl_killed "CL8c mutant (the proof gated on the ttl again) is killed: the dead holder reads LIVE" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)" "$(case "$cl_out" in *"STALE (proven"*) echo 0 ;; *) echo 1 ;; esac)"
    fi
    cl_run "$A" break --lease land --reason "the land process of this lane has exited"
    cl_expect_rc 0 "CL8c a proven break succeeds, inside the ttl"
    cl_check "CL8c it is logged as dead before the delete" "$(cl_llogtxt | grep -q '^proof: dead$' && [ -z "$(cl_lref)" ] && echo 1 || echo 0)"
    cl_lclear
    # CL16d (SWAS-842): under install-shims `break --lease land` succeeds too. The delete is the same admitted compare-and-swap form, so a proven break and the
    # age-only break through the human dial both end in a delete that lands (Q-842-4: the admission cannot tell the two apart, and the dial's reach is unchanged).
    if [ -d "$cl_base/shims" ]; then
      cl_lplant 10 lane-a land "$cl_mid8" "$cl_dp" "${cl_dps:-(none)}" ""
      cl_x "$CL_SELF" "$cl_base/shims" "$A" break --lease land --reason "the land process of this lane has exited"
      cl_expect_rc 0 "CL16d under install-shims a proven break of the land lease succeeds"
      cl_check "CL16d it is logged as dead (not -FAILED) and the lease is gone" "$(cl_llogtxt | grep -q '^proof: dead$' && [ -z "$(cl_lref)" ] && echo 1 || echo 0)"
      cl_lclear
      cl_lplant 100000 lane-b land bbbbbbbbbbbbbbbb "$cl_dp" "${cl_dps:-(none)}" ""
      if cl_out=$( cd "$A" && PATH="$cl_base/shims:$PATH" KIT_LEASE_FORCE_BREAK=1 sh "$CL_SELF" break --lease land --reason "the far lane is long gone, owner confirmed" 2>&1 ); then cl_rc=0; else cl_rc=$?; fi
      cl_expect_rc 0 "CL16d under install-shims the age-only break through the human dial succeeds too"
      cl_check "CL16d it is logged as FORCED (not -FAILED) and the lease is gone" "$(cl_llogtxt | grep -q '^proof: FORCED$' && [ -z "$(cl_lref)" ] && echo 1 || echo 0)"
      cl_lclear
    else
      echo "selftest SKIP: CL16d the break under the shims (no shims directory, as CL16 found no kit-guard beside this script)"
    fi
  else
    echo "selftest SKIP: CL8b and CL8c the machine and pid proofs (ps cannot be read in this environment)"
  fi

  # ---- CL23: a lease commit dated 400 s ahead ---------------------------------------------------------------------------------------------
  cl_lplant -400 lane-b land aaaaaaaaaaaaaaaa 4242 "(none)" ""
  cl_run "$A" status --lease land
  cl_has "CL23 a lease dated ahead reads STALE (age only)" "STALE (age only"; cl_has "CL23 and says the writer clock is ahead" "writer clock ahead"
  if cl_mutant CL23 LCLOCK 's|-gt \$(( \$(cl_now) + 300 ))|-gt 99999999999|'; then
    cl_runm "$A" status --lease land
    cl_killed "CL23 mutant (the clock line dropped) is killed" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)" "$(case "$cl_out" in *"writer clock ahead"*) echo 0 ;; *) echo 1 ;; esac)"
  fi
  cl_lclear

  # ---- CL14 to CL14g: a CI holder's proof, from the forge (the gh shim; C is the CI shape; the origin URL is GitHub-shaped here) ---------------------------------
  cl_ghon
  # CL14: a completed run proves the holder gone at any age (here: inside the ttl); an in_progress run is LIVE
  cl_ciplant 60 123/1 completed success -10 -5 train main push
  cl_ci "$CL_SELF" status
  cl_has "CL14 a completed run inside the ttl: STALE (proven)" "STALE (proven: run 123/1 concluded success)"
  cl_ci "$CL_SELF" break --reason "the train run for this lease has concluded"
  cl_expect_rc 0 "CL14 break on a proven CI holder -> rc 0"
  cl_check "CL14 the log names the run and the conclusion, and the lease is gone" "$(cl_llogtxt | grep -q '^proof: run 123/1 concluded success$' && [ -z "$(cl_lref)" ] && echo 1 || echo 0)"
  cl_lclear
  cl_ciplant 60 123/1 in_progress success -10 -5 train main push   # a forge that still reports a conclusion on a live run: the status is what counts
  cl_ci "$CL_SELF" status; cl_has "CL14 an in_progress run: LIVE" "reading: LIVE"
  if cl_mutant CL14 LDONE 's#\[ "\$_cs" = completed \] || { CL_WHY="the run is \$_cs, not completed"; return 0; }#:#'; then
    cl_ci "$cl_mscript" status
    cl_killed "CL14 mutant (the completed test dropped) is killed: the live run is proven gone" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)" "$(case "$cl_out" in *"STALE (proven"*) echo 1 ;; *) echo 0 ;; esac)"
  fi
  cl_lclear
  # CL14b: a crafted run is MALFORMED and gh is never called
  for cl_run14 in '-R x/y 1' '1;x' '--web' '12/'; do
    : > "$cl_base/gh.log"
    printf 'lease: land\nholder: train\npurpose: land\nrun: %s\nmachine: ci\npid: unproven\npid-start: (none)\nttl-s: 2700\n' "$cl_run14" > "$cl_base/b14.txt"
    cl_lplant_blob 100000 "$cl_base/b14.txt"; cl_ci "$CL_SELF" status
    cl_has "CL14b the run '$cl_run14' is MALFORMED" "MALFORMED"
    cl_check "CL14b and gh was never called for '$cl_run14'" "$([ ! -s "$cl_base/gh.log" ] && echo 1 || echo 0)"
  done
  if cl_mutant CL14b LRUN 's,\[ -z "\$CL_RUN" \] || cl_run_ok "\$CL_RUN" || return 1,:,'; then
    printf 'lease: land\nholder: train\npurpose: land\nrun: 1;x\nmachine: ci\npid: unproven\npid-start: (none)\nttl-s: 2700\n' > "$cl_base/b14.txt"
    cl_lplant_blob 100000 "$cl_base/b14.txt"; cl_ci "$cl_mscript" status
    cl_killed "CL14b mutant (the run grammar dropped) is killed: the crafted run is read as a lease" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)" "$(case "$cl_out" in *MALFORMED*) echo 0 ;; *) echo 1 ;; esac)"
  fi
  cl_lclear
  # CL14p (SWAS-903): the gh-tls probe runs right before the gh call of the CI proof (never before the MALFORMED return above, which makes no gh call).
  # A stub library stands in for scripts/gh-tls.sh beside a COPY of this script and logs PROBE to gh.log; the first gh.log line must be PROBE and the second
  # the `run view` call. Mutant: the probe line deleted -> the first line is the gh call.
  cl_ciplant 60 123/1 completed success -10 -5 train main push
  mkdir -p "$cl_base/pcell"; cp "$CL_SELF" "$cl_base/pcell/checkout-lease.sh"
  printf 'kit_gh_tls_pin() { printf "PROBE\\n" >> "%s/gh.log"; }\n' "$cl_base" > "$cl_base/pcell/gh-tls.sh"
  : > "$cl_base/gh.log"; cl_ci "$cl_base/pcell/checkout-lease.sh" status
  cl_check "CL14p the probe runs first, then the gh call" "$([ "$(sed -n 1p "$cl_base/gh.log")" = PROBE ] && sed -n 2p "$cl_base/gh.log" | grep -q '^run view' && echo 1 || echo 0)"
  if cl_mutant CL14p LPROBE 'd'; then
    cp "$cl_base/pcell/gh-tls.sh" "$cl_base/mut-CL14p/gh-tls.sh"
    : > "$cl_base/gh.log"; cl_ci "$cl_mscript" status
    cl_killed "CL14p mutant (the probe deleted) is killed: the first gh.log line is the gh call, not the probe" "$([ -s "$cl_base/gh.log" ] && echo 1 || echo 0)" "$([ "$(sed -n 1p "$cl_base/gh.log")" = PROBE ] && echo 0 || echo 1)"
  fi
  cl_lclear
  # CL14c: no proof from another workflow, a non-main branch, a PR event, or another attempt (age only: past the ttl)
  cl_ciplant 100000 123/1 completed success -10 50 other main push
  cl_ci "$CL_SELF" status; cl_has "CL14c another workflow: no proof (age only)" "STALE (age only"
  if cl_mutant CL14c LWF 's,= "\$CL_TRAIN_WORKFLOW" \],!= "x" ],'; then
    cl_ci "$cl_mscript" status
    cl_killed "CL14c mutant (the workflow filter dropped) is killed" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)" "$(case "$cl_out" in *"STALE (proven"*) echo 1 ;; *) echo 0 ;; esac)"
  fi
  cl_lclear
  cl_ciplant 100000 123/1 completed success -10 50 train feature push
  cl_ci "$CL_SELF" status; cl_has "CL14c a non-main branch: no proof (age only)" "STALE (age only"
  if cl_mutant CL14c2 LBRANCH 's, = main \], != nope ],'; then
    cl_ci "$cl_mscript" status
    cl_killed "CL14c mutant (the branch filter dropped) is killed" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)" "$(case "$cl_out" in *"STALE (proven"*) echo 1 ;; *) echo 0 ;; esac)"
  fi
  cl_lclear
  cl_ciplant 100000 123/1 completed success -10 50 train main pull_request
  cl_ci "$CL_SELF" status; cl_has "CL14c a pull_request event: no proof (age only)" "STALE (age only"
  if cl_mutant CL14c3 LEVENT "s,in ''|pull_request|pull_request_target),in ''),"; then
    cl_ci "$cl_mscript" status
    cl_killed "CL14c mutant (the event filter dropped) is killed" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)" "$(case "$cl_out" in *"STALE (proven"*) echo 1 ;; *) echo 0 ;; esac)"
  fi
  cl_lclear
  # attempt 1 finished, attempt 2 live, the lease names attempt 2: the forge is asked about attempt 2
  cl_ciplant 100000 123/2 completed success -10 50 train main push
  printf 'GH2_STATUS=in_progress\nGH2_CONC=success\n' >> "$cl_base/gh.conf"
  cl_ci "$CL_SELF" status; cl_has "CL14c attempt 2 live (attempt 1 finished): no proof" "STALE (age only"
  if cl_mutant CL14c4 LATT 's,set -- "\$@" --attempt "\$_cat",:,'; then
    cl_ci "$cl_mscript" status
    cl_killed "CL14c mutant (--attempt dropped) is killed: attempt 1's end proves attempt 2 gone" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)" "$(case "$cl_out" in *"STALE (proven"*) echo 1 ;; *) echo 0 ;; esac)"
  fi
  cl_lclear
  # CL14d: gh failing or absent, or a conclusion outside gh's enum: no proof
  cl_ciplant 100000 123/1 completed success -10 50 train main push
  printf 'GH_RC=1\n' >> "$cl_base/gh.conf"; cl_ci "$CL_SELF" status; cl_has "CL14d gh failing: no proof (age only)" "STALE (age only"
  printf 'GH_RC=127\n' >> "$cl_base/gh.conf"; cl_ci "$CL_SELF" status; cl_has "CL14d gh absent (not found): no proof (age only)" "STALE (age only"
  if cl_mutant CL14d LGHFAIL 's,|| { CL_WHY="gh could not read run $(cl_clean "$CL_RUN")"; return 0; },|| { CL_PROOF="run $CL_RUN concluded unread"; return 0; },'; then
    cl_ci "$cl_mscript" status
    cl_killed "CL14d mutant (a gh failure read as concluded) is killed" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)" "$(case "$cl_out" in *"STALE (proven"*) echo 1 ;; *) echo 0 ;; esac)"
  fi
  cl_ciplant 100000 123/1 completed weird -10 50 train main push
  cl_ci "$CL_SELF" status; cl_has "CL14d a conclusion outside the enum: no proof" "STALE (age only"; cl_has "CL14d and it is shown as (unrecognised)" "(unrecognised)"
  if cl_mutant CL14d2 LENUM 's,\*) CL_WHY="the conclusion of the run is (unrecognised)"; return 0 ;; esac,*) ;; esac,'; then
    cl_ci "$cl_mscript" status
    cl_killed "CL14d mutant (the enum check dropped) is killed: the odd conclusion proves the holder gone" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)" "$(case "$cl_out" in *"STALE (proven"*) echo 1 ;; *) echo 0 ;; esac)"
  fi
  cl_lclear
  # CL14e: a run that finished before the lease was written cannot be its holder
  cl_ciplant 100000 123/1 completed success -2000 -900 train main push
  cl_ci "$CL_SELF" status; cl_has "CL14e a run that finished 900 s before the lease: no proof (age only)" "STALE (age only"
  if cl_mutant CL14e LDONEAFTER 's,-ge \$((_cct - 300)),-ge 0,'; then
    cl_ci "$cl_mscript" status
    cl_killed "CL14e mutant (the finished-after test dropped) is killed" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)" "$(case "$cl_out" in *"STALE (proven"*) echo 1 ;; *) echo 0 ;; esac)"
  fi
  cl_lclear
  # CL14f: a run created 600 s AFTER the lease cannot be its holder; --expect-base must be origin's main
  cl_ciplant 100000 123/1 completed success 600 700 train main push
  cl_ci "$CL_SELF" status; cl_has "CL14f a run created 600 s after the lease: no proof (age only)" "STALE (age only"
  if cl_mutant CL14f LCREATED 's,-le \$((_cct + 300)),-le 99999999999,'; then
    cl_ci "$cl_mscript" status
    cl_killed "CL14f mutant (the created-before test dropped) is killed" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)" "$(case "$cl_out" in *"STALE (proven"*) echo 1 ;; *) echo 0 ;; esac)"
  fi
  cl_lclear
  cl_ci "$CL_SELF" acquire --holder train --purpose land --run 5/1 --expect-base "$cl_zero"
  cl_expect_rc 5 "CL14f --expect-base that is not origin's main -> rc 5"; cl_check "CL14f and nothing was pushed" "$([ -z "$(cl_lref)" ] && echo 1 || echo 0)"
  cl_ci "$CL_SELF" acquire --holder train --purpose land --run 5/1 --expect-base "$(git -C "$cl_o" rev-parse --verify -q refs/heads/main)"
  cl_expect_rc 0 "CL14f --expect-base that is origin's main -> rc 0"; cl_lclear
  if cl_mutant CL14f2 LBASE 's|if \[ "\$CL_OSHA" != "\$_xbase" \]; then|if false; then|'; then
    cl_ci "$cl_mscript" acquire --holder train --purpose land --run 5/1 --expect-base "$cl_zero"
    cl_killed "CL14f mutant (the base check dropped) is killed: a stale base takes the lease" "$([ "$cl_rc" = 0 ] || [ "$cl_rc" = 5 ] && echo 1 || echo 0)" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)"
    cl_lclear
  fi
  # CL14g: the -R argument comes from origin's URL; a non-GitHub origin gives no proof
  : > "$cl_base/gh.log"
  cl_ciplant 100000 123/1 completed success -10 50 train main push
  cl_ci "$CL_SELF" status; cl_has "CL14g a GitHub origin: the run is proven" "STALE (proven"
  cl_check "CL14g and gh was asked with -R owner-login/repo-a" "$(grep -q -- '-R owner-login/repo-a' "$cl_base/gh.log" && echo 1 || echo 0)"
  if cl_mutant CL14g LREPO 's,set -- "\$@" -R "\$_crepo",:,'; then
    : > "$cl_base/gh.log"; cl_ci "$cl_mscript" status
    cl_killed "CL14g mutant (-R dropped) is killed: gh is asked with no repository" "$([ "$cl_rc" = 0 ] && echo 1 || echo 0)" "$(grep -q -- '-R owner-login/repo-a' "$cl_base/gh.log" && echo 0 || echo 1)"
  fi
  cl_ghoff
  cl_ci "$CL_SELF" status; cl_has "CL14g a non-GitHub origin: no proof (age only)" "STALE (age only"
  cl_lclear

  # ---- CL11b: the log is pushed before the delete; a refused log leaves the lease alone; a refused delete appends -FAILED ------------------------------------------------
  cl_ghon
  cl_ciplant 100000 123/1 completed success -10 50 train main push
  mkdir -p "$cl_base/logshim"
  printf '#!/bin/sh\ncase "$*" in\n  *"refs/leases-log/land"*) exit 1 ;;\nesac\nexec "%s" "$@"\n' "$cl_realgit" > "$cl_base/logshim/git"; chmod +x "$cl_base/logshim/git"
  cl_x "$CL_SELF" "$cl_base/logshim:$cl_base/ghshim" "$C" break --lease land --reason "the train run for this lease has concluded"
  cl_expect_rc 2 "CL11b a refused log push -> rc 2"; cl_check "CL11b the lease is untouched" "$([ "$(cl_lref)" = "$cl_lpsha" ] && echo 1 || echo 0)"
  if cl_mutant CL11b LLOGFIRST 's,if ! cl_llog "\$_plabel" "\$_lcode" "\$CL_SHA"; then,if false; then,'; then
    cl_x "$cl_mscript" "$cl_base/logshim:$cl_base/ghshim" "$C" break --lease land --reason "the train run for this lease has concluded"
    cl_killed "CL11b mutant (the log pushed after the delete, here never) is killed: the lease is deleted with no entry" "$([ "$cl_rc" = 0 ] || [ "$cl_rc" = 2 ] && echo 1 || echo 0)" "$([ "$cl_rc" = 0 ] && [ -z "$(cl_lref)" ] && echo 1 || echo 0)"
    cl_lclear; cl_ciplant 100000 123/1 completed success -10 50 train main push
  fi
  mkdir -p "$cl_base/dlshim"
  printf '#!/bin/sh\ncase "$*" in\n  *" :refs/leases/land"*) exit 1 ;;\nesac\nexec "%s" "$@"\n' "$cl_realgit" > "$cl_base/dlshim/git"; chmod +x "$cl_base/dlshim/git"
  cl_x "$CL_SELF" "$cl_base/dlshim:$cl_base/ghshim" "$C" break --lease land --reason "the train run for this lease has concluded"
  cl_expect_rc 1 "CL11b a refused delete -> rc 1"; cl_check "CL11b the lease is still on origin" "$([ "$(cl_lref)" = "$cl_lpsha" ] && echo 1 || echo 0)"
  cl_check "CL11b the log has the record and a -FAILED entry, the last saying nothing was deleted" "$([ "$(cl_llogn)" = 2 ] && cl_llogtxt | grep -q '^released-sha: (not deleted)$' && echo 1 || echo 0)"
  # ---- CL11c (S1): the free-text reason of a break never reaches origin; the log carries a fixed code, the words stay in a local log ----------------------------------
  cl_lclear
  cl_ciplant 100000 123/1 completed success -10 50 train main push
  cl_ci "$CL_SELF" break --reason "free text UNIQUEWORDS0451 must stay off origin"
  cl_expect_rc 0 "CL11c a proven break -> rc 0"
  cl_check "CL11c the pushed log entry carries a fixed reason code and none of the free text" "$(cl_llogtxt | grep -qx 'reason: run-concluded' && ! cl_llogtxt | grep -q UNIQUEWORDS0451 && echo 1 || echo 0)"
  cl_check "CL11c the free text is in the local log" "$(grep -q UNIQUEWORDS0451 "$C/.git/kit-lease-break.log" 2>/dev/null && echo 1 || echo 0)"
  if cl_mutant CL11c LREASON 's,_lcode=\$_rcode,_lcode=$_reason,'; then
    cl_lclear; cl_ciplant 100000 123/1 completed success -10 50 train main push
    cl_ci "$cl_mscript" break --reason "free text UNIQUEWORDS0451 must stay off origin"
    cl_killed "CL11c mutant (the reason pushed as the code) is killed: the break is refused or the words reach origin" "$([ "$cl_rc" = 0 ] || [ "$cl_rc" = 2 ] && echo 1 || echo 0)" "$([ "$cl_rc" != 0 ] || cl_llogtxt | grep -q UNIQUEWORDS0451 && echo 1 || echo 0)"
  fi
  cl_ghoff; cl_lclear

  # ---- CL19 to CL19d: `land` and `actuate` take the land lease before the merge and return it on every way out (B7) --------------------------------------------
  # These drive the production functions and trap lines of promotion-verify.sh through a land-shaped driver (see cl_pvdrive), and pin the call sites
  # by order (cl_pvorder); the whole-verb run needs the GO fixture of conformance/promotion-actuate-wired.sh (a departure, logged in the errata).
  cl_pv="$cl_dir/promotion-verify.sh"
  printf '#!/bin/sh\n: > "%s/merged.marker"\n' "$cl_base" > "$cl_base/stub-ok.sh"
  printf '#!/bin/sh\nexit 1\n' > "$cl_base/stub-fail.sh"
  printf '#!/bin/sh\n: > "%s/merged.marker"\nsleep 2\n' "$cl_base" > "$cl_base/stub-slow.sh"
  cl_check "CL19 land takes the lease before its merge and returns it after the claim release" "$(cl_pvorder do_land 'eval "$merge_cmd"' 'pv_release_claim "$_land_note" land' && echo 1 || echo 0)"
  cl_check "CL19 actuate takes the lease before its merge and returns it after the claim release" "$(cl_pvorder do_actuate 'eval "$merge_cmd"' 'pv_release_claim "$note" actuate' && echo 1 || echo 0)"
  cl_reset "$A"; cl_reset "$B"; cl_lclear; rm -f "$cl_base/merged.marker"
  cl_lacq "$B" lane-b land
  cl_acq "$A" lane-a claim; cl_ctok19=$cl_tok
  cl_pvdrive "$cl_pv" "$cl_ctok19" "$cl_base/stub-ok.sh"
  cl_x "$cl_base/pvdrive.sh" "" "$A"
  cl_expect_rc 5 "CL19 a held land lease refuses the verb rc 5"; cl_has "CL19 it names the holder" 'HELD by "lane-b"'; cl_has "CL19 it says the GO note is recorded and the verb can be re-run" "Re-run"
  cl_check "CL19 the merge never ran" "$([ ! -e "$cl_base/merged.marker" ] && echo 1 || echo 0)"
  _cl19m="$cl_base/pv-mut-gate.sh"
  sed '/# MUT-LGATE$/s,|| _pv_lrc=\$?,|| _pv_lrc=0,' "$cl_pv" > "$_cl19m"
  if cmp -s "$cl_pv" "$_cl19m"; then cl_fail "CL19 mutant LGATE: did not apply"; else
    cl_pvdrive "$_cl19m" "$cl_ctok19" "$cl_base/stub-ok.sh"; cl_x "$cl_base/pvdrive.sh" "" "$A"
    cl_killed "CL19 mutant (the HELD answer read as proceed) is killed: the merge runs under another holder's lease" "$([ "$cl_rc" = 0 ] || [ "$cl_rc" = 5 ] && echo 1 || echo 0)" "$([ -e "$cl_base/merged.marker" ] && echo 1 || echo 0)"
  fi
  cl_lclear; cl_reset "$B"; rm -f "$cl_base/merged.marker"
  # CL19b: a merge that fails still returns the lease (the EXIT trap)
  cl_reset "$A"; cl_acq "$A" lane-a claim; cl_ctok19=$cl_tok
  cl_pvdrive "$cl_pv" "$cl_ctok19" "$cl_base/stub-fail.sh"; cl_x "$cl_base/pvdrive.sh" "" "$A"
  cl_expect_rc 1 "CL19b a failing merge -> rc 1"; cl_check "CL19b and the land lease is back on origin's free list" "$([ -z "$(cl_lref)" ] && echo 1 || echo 0)"
  _cl19t="$cl_base/pv-mut-trap.sh"
  sed "/# MUT-LTRAP\$/s,; pv_land_lease_return || :' EXIT,' EXIT," "$cl_pv" > "$_cl19t"
  if cmp -s "$cl_pv" "$_cl19t"; then cl_fail "CL19b mutant LTRAP: did not apply"; else
    cl_reset "$A"; cl_acq "$A" lane-a claim; cl_ctok19=$cl_tok
    cl_pvdrive "$_cl19t" "$cl_ctok19" "$cl_base/stub-fail.sh"; cl_x "$cl_base/pvdrive.sh" "" "$A"
    cl_killed "CL19b mutant (the trap dropped) is killed: the failed merge leaves the lease held" "$([ "$cl_rc" = 1 ] && echo 1 || echo 0)" "$([ -n "$(cl_lref)" ] && echo 1 || echo 0)"
  fi
  cl_lclear
  # CL19c: a success returns it; a TERM sent while the merge runs returns it when the merge command ends
  cl_reset "$A"; cl_acq "$A" lane-a claim; cl_ctok19=$cl_tok
  cl_pvdrive "$cl_pv" "$cl_ctok19" "$cl_base/stub-ok.sh"; cl_x "$cl_base/pvdrive.sh" "" "$A"
  cl_expect_rc 0 "CL19c a successful run -> rc 0"; cl_check "CL19c and the lease is returned" "$([ -z "$(cl_lref)" ] && echo 1 || echo 0)"
  cl_reset "$A"; cl_acq "$A" lane-a claim; cl_ctok19=$cl_tok; rm -f "$cl_base/merged.marker"
  cl_pvdrive "$cl_pv" "$cl_ctok19" "$cl_base/stub-slow.sh"
  sh -c 'cd "$1" && exec sh "$2"' x "$A" "$cl_base/pvdrive.sh" >/dev/null 2>&1 & cl_pvp=$!
  cl_wt=0; while [ ! -e "$cl_base/merged.marker" ] && [ "$cl_wt" -lt 100 ]; do sleep 0.1 2>/dev/null || sleep 1; cl_wt=$((cl_wt + 1)); done   # the merge command has started
  kill -TERM "$cl_pvp" 2>/dev/null || true
  wait "$cl_pvp" 2>/dev/null || true
  cl_check "CL19c a TERM while the merge command runs: the lease is returned" "$([ -e "$cl_base/merged.marker" ] && [ -z "$(cl_lref)" ] && echo 1 || echo 0)"
  cl_lclear
  # CL19d: a checkout that never opted in runs as before, with one warning when the land lease is held
  rm -f "$cl_base/merged.marker"; cl_reset "$B"; cl_lacq "$B" lane-b land
  cl_pvdrive "$cl_pv" "" "$cl_base/stub-ok.sh"; cl_x "$cl_base/pvdrive.sh" "" "$C"
  cl_expect_rc 0 "CL19d a checkout that never opted in runs as before, the land lease held or not"
  cl_has "CL19d and says once that the land lease is held" "WARN"; cl_check "CL19d the merge ran" "$([ -e "$cl_base/merged.marker" ] && echo 1 || echo 0)"
  cl_check "CL19d and the other holder's lease is untouched" "$([ -n "$(cl_lref)" ] && echo 1 || echo 0)"
  cl_lclear; rm -f "$cl_base/merged.marker"
  cl_x "$cl_base/pvdrive.sh" "" "$C"
  cl_expect_rc 0 "CL19d with no land lease held: rc 0"; cl_hasnt "CL19d and no warning" "WARN"
  cl_reset "$A"; cl_reset "$B"

  if [ "$cl_fail_n" != 0 ]; then echo "checkout-lease --selftest: FAIL" >&2; return 1; fi
  echo "checkout-lease --selftest: OK (fixtures under $cl_base, removed by the best-effort EXIT trap)"
  return 0
}

CL_SELF=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/$(basename -- "$0")
# Best-effort, as board-claim's trap is: a failing cleanup step must never change the verb's own exit code.
cl_cleanup() { { [ -n "${cl_base:-}" ] && rm -rf "$cl_base" 2>/dev/null; } || true; { [ -n "${CL_ISOROOT:-}" ] && rm -rf "$CL_ISOROOT" 2>/dev/null; } || true; return 0; }
trap 'cl_cleanup' EXIT INT TERM

cl_cmd="${1:-}"
[ $# -gt 0 ] && shift || true
case "$cl_cmd" in
  --selftest) if cl_selftest; then cl_rc_main=0; else cl_rc_main=$?; fi ;;
  -h|--help|"") cl_usage; cl_rc_main=2 ;;
  acquire|release|sync|held|gate|status|break|doctor-line)
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
      # outside a repository there is nothing to lease: the gate has nothing to guard, doctor says off
      case "$cl_cmd" in gate) exit 0 ;; doctor-line) echo "lease: off (no key, no lease log)"; exit 0 ;; esac
      cl_err "not inside a git repository."; exit 2
    fi
    if "cl_$(printf '%s' "$cl_cmd" | tr - _)" "$@"; then cl_rc_main=0; else cl_rc_main=$?; fi ;;
  *) cl_err "unknown verb '$(cl_clean "$cl_cmd")'"; cl_usage; cl_rc_main=2 ;;
esac
exit "$cl_rc_main"
