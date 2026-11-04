#!/bin/sh
# selftest-hermetic.sh — the fixture-hermeticity lane (PHASE-B-HYGIENE H2 / FIXTURE-HERMETICITY-LANE).
#
# THE CLASS THIS CLOSES (third recurrence; panel #38 finding 3-H2): a check's --selftest reads
# something AMBIENT it did not itself set — global git identity/config (B2 §10-A9: 25 GO-leg FAILs
# on a runner with no identity), or the surrounding repo's notes-refs/object-store/kit markers
# (B3 HIGH-A, B4 H-4). All three instances were green on every reviewer's tree and dead on a runner;
# every prior cure was instance-scoped. This lane detects the CLASS: every targeted --selftest must
# pass under TWO FACES whose non-overlap is measured, not assumed:
#   face (a) STRIPPED ENV — B2 §10-A9's exact recipe: GIT_CONFIG_GLOBAL=/dev/null
#            GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.useConfigOnly
#            GIT_CONFIG_VALUE_0=true, HOME = a bare mktemp dir, GIT_AUTHOR_*/GIT_COMMITTER_* unset,
#            TMPDIR = a fresh dir made with an explicit mktemp template (macOS mktemp ignores TMPDIR, so a
#            script that makes its fixtures with a bare `mktemp` lands outside it: SWAS-244).
#            Catches ambient IDENTITY/CONFIG reads (a clone does NOT: it inherits global identity —
#            measured by the B2 round-3 executor, independently confirmed).
#   face (b) `git clone --no-local` of the containing repo into mktemp, selftest run inside it, with
#            TMPDIR = a fresh templated dir as in face (a).
#            Catches ambient NOTES-REFS/OBJECT-STORE reads (a clone carries neither).
#
# MODES
#   --touched         changed files vs merge-base(HEAD, $HERMETIC_BASE [default origin/main]),
#                     intersected with the selftest-capable roster. Empty target => N/A, rc 0.
#                     An UNDERIVABLE base/merge-base FAILS LOUD (rc 1) — never a silent pass.
#   --all             the full roster. NOT wired per-PR (measured: ~163 selftests x ~1.4s median
#                     x 2 faces = minutes — incompatible with per-PR latency and with `git push`).
#   <path>...         explicit targets (any file path; face (b) needs it inside a git repo).
#   --selftest        this lane's own fixture battery (hermetic by construction).
#
# ROSTER semantics = conformance/ci-selftest-coverage.sh's exactly: scan conformance/*.sh
# scripts/*.sh hooks/pre-push; capability = `--selftest` survives comment-strip.
#
# CORE-ONLY (SWAS-460): on a kit tree a CORE_FACE_TARGETS entry runs --selftest-core under both faces; see the list's comment below.
#
# FACE LINES (SWAS-376): every PASS line, and the FAIL line of a face that ran, ends `(<n> s) battery: <state>` — the face's
# whole seconds, and whether verify.sh's nested run deferred the guard battery (`deferred` / `NOT deferred` / `not run/unknown`,
# read from the face's own `renderer probe: agent-autonomy <verdict>` line, only when exactly one is present; see battery_state).
#
# EXCLUSIONS: conformance/hermetic-exclusions.txt (the aggregate-exclusions.txt precedent) —
# basename<TAB>reason; a reasonless entry FAILS the lane. That file is a BYPASS SURFACE and its
# header says so. It ships EMPTY.
#
# WHERE THIS BINDS (stated plainly — design self-review finding 3): the per-PR CI step is what
# BINDS; the pre-push rhythm line in skills/build is CONDUCT and will drift.
# ADOPTER SCOPE (security F6, design §10-A1): the per-PR `--touched` face is KIT-CI-only — no
# emitted adopter pipeline wires this step; adopters must wire it in their own pipeline or run
# `--touched`/`--all` manually. The exported binding today is this lane's `--selftest` via
# `verify.sh --require`. HONEST CEILINGS:
# touched-scope means a pre-existing ambient read in an UNTOUCHED selftest sleeps until that file
# is next edited (--all exists for a scheduled sweep); face (b) clones the repo's HEAD, so an
# UNCOMMITTED target fails loud with the reason (commit first — the pre-push/CI callers always run
# on committed trees); this lane does NOT close NON-VACUITY-HOOK-SCOPE (sweep REACHABILITY is a
# different axis); the 4/163 collateral sample does not prove the other 159 run collateral-free
# under strip — a genuinely-collateral case gets an exclusion-with-reason, never a silent skip.
#
# Usage: sh conformance/selftest-hermetic.sh [--touched | --all | <path>... | --selftest]
# Exit: 0 = every targeted selftest passed both faces (or N/A) · 1 = a face failed / lane misuse
#       (underivable base, unreasoned exclusion, uncommitted target) · 2 = bad usage. POSIX sh.
set -eu

TAB=$(printf '\t')
BASE="${HERMETIC_BASE:-origin/main}"
EXCL_FILE="conformance/hermetic-exclusions.txt"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/hermetic-XXXXXX")
HF_PERL=/usr/bin/perl
# SWAS-592: the group wrapper. Reset INT and QUIT (a background job starts with them IGNORED, and exec keeps that), make a process group of its own, ASSERT it is one (pgid == pid), else leave the sentinel named by the first argument and stop (exit 125, the face is never run); then exec the face.
HF_PROG='my $s = shift; $SIG{INT}=$SIG{QUIT}="DEFAULT"; (setpgrp(0,0) && getpgrp(0) == $$) or do { open(my $f, ">", $s); exit 125 }; exec {$ARGV[0]} @ARGV or exit 126'   # HFGRP
_hf_pg=''; _hf_pid=''; _hf_grp=0; _hf_sent=''; _hf_killed=0; _hf_left=''; _hf_rc=0
trap 'hf_reap; rm -rf "$WORK"; exit 130' INT TERM
# done-sentinel: bash 3.2 posix (macOS /bin/sh) exits 0 after a readonly-assignment abort when an EXIT trap runs; only _fin sets _done=1, so an unfinished exit 0 becomes 2
_done=0
# shellcheck disable=SC2154 # _rc is assigned inside the trap string itself
trap '_rc=$?; rm -rf "$WORK"; if [ "$_done" != 1 ] && [ "$_rc" = 0 ]; then exit 2; fi' EXIT
_fin() { _done=1; exit "$1"; }

# roster — selftest-capable scripts of the CURRENT repo (relative paths), ci-selftest-coverage
# semantics: the fixed scan set, capability = --selftest survives comment-strip.
roster() {
  for _f in conformance/*.sh scripts/*.sh hooks/pre-push; do
    [ -f "$_f" ] || continue
    sed 's/#.*//' "$_f" | grep -q -- '--selftest' || continue
    printf '%s\n' "$_f"
  done | sort -u
}

# validate_exclusions — every non-comment line must be basename<TAB>reason. rc 1 on a reasonless
# entry (an unreasoned exclusion is a silent widening — the defect the file exists to prevent).
validate_exclusions() {
  [ -f "$EXCL_FILE" ] || return 0
  while IFS= read -r _l; do
    case "$_l" in ''|\#*) continue ;; esac
    _r=${_l#*"$TAB"}
    if [ "$_r" = "$_l" ] || [ -z "$_r" ]; then
      echo "FAIL: $EXCL_FILE entry '$_l' carries no <TAB>reason — an unreasoned exclusion is a silent bypass"
      return 1
    fi
  done < "$EXCL_FILE"
  return 0
}

# excluded <path> — 0 (and prints the disposition) iff the basename is excluded-with-reason.
excluded() {
  [ -f "$EXCL_FILE" ] || return 1
  _b=$(basename "$1")
  while IFS= read -r _l; do
    case "$_l" in ''|\#*) continue ;; esac
    if [ "${_l%%"$TAB"*}" = "$_b" ]; then
      echo "  EXCLUDED: $_b — ${_l#*"$TAB"} ($EXCL_FILE)"
      return 0
    fi
  done < "$EXCL_FILE"
  return 1
}

# first_fails <face-output> — name the first FAIL lines of a red face BEFORE the tail (SWAS-244/248): a
# FAIL in the middle of a long output sits above the PASS legs the tail shows. A FAIL line contains FAIL and
# does not START with a PASS marker (tracker-contract prints PASS lines that name FAIL). grep answers rc 1 on
# no match, so each is guarded under set -eu. Output stays bounded: a header and at most 10 lines.
first_fails() {
  # SWAS-577: a selftest grep that could not answer prints an UNVERIFIED (grep rc=N) line, so those lines are listed too (the count in the header includes them).
  _ff=$(LC_ALL=C grep -n -e FAIL -e UNVERIFIED "$1" | LC_ALL=C grep -v -E -e '^[0-9]+:[[:space:]]*(selftest )?PASS' || :)
  if [ -z "$_ff" ]; then
    echo "  no output line contains FAIL or UNVERIFIED; see the tail below"
    return 0
  fi
  _fk=$(printf '%s\n' "$_ff" | LC_ALL=C grep -c -e '^' || :)
  if [ "$_fk" -gt 10 ]; then echo "  first 10 of $_fk FAIL lines:"; else echo "  $_fk FAIL lines:"; fi
  printf '%s\n' "$_ff" | sed -n '1,10p' | LC_ALL=C cut -c1-300 | sed 's/^/    /'
}

_repo_of() { git -C "$(dirname "$1")" rev-parse --show-toplevel 2>/dev/null; }

# CORE_FACE_TARGETS (SWAS-460) — repo-relative paths whose hermetic faces run --selftest-core, never the full --selftest, ON A KIT TREE ONLY.
# Why: boundary-redteam.sh's full --selftest (every load-bearing mutant, targeted: each mutant re-runs only the core segments it declares, SWAS-560) is graded once by the diff-gated CI job
# `boundary-redteam`; each mutant is the same --selftest-core on a sed copy outside any git repo, so the core under both faces covers their ambient class.
# Matched whole-path and exact against the target's repo-relative path (never a pattern or a basename). ci-gates.sh check_core_face_graders pins
# every entry to a CI job named for its basename that runs the full --selftest, and an empty list reds there. Inert on an adopter tree (no kit marker).
# A kit tree holds docs/ROADMAP-KIT.md or .github/workflows/golden-path.yml at the repo top; a listed target then prints a CORE-ONLY line and tags its PASS lines `[--selftest-core]`.
CORE_FACE_TARGETS='conformance/boundary-redteam.sh'
readonly CORE_FACE_TARGETS

# core_face_listed <repo-top> <repo-relative-path> — 0 iff the repo top is a kit tree and the path is a listed entry, whole and exact (set -f: an entry is never a glob).
core_face_listed() {
  [ -f "$1/docs/ROADMAP-KIT.md" ] || [ -f "$1/.github/workflows/golden-path.yml" ] || return 1
  _cf=1; set -f
  for _e in $CORE_FACE_TARGETS; do
    if [ "$2" = "$_e" ]; then _cf=0; break; fi
  done
  set +f; return $_cf
}

# battery_state <face-output> — SWAS-376: did this face defer the guard battery? Read from the face's own
# `renderer probe: agent-autonomy <verdict>` line (printed once by verify.sh --selftest, from the rendered row), and
# ONLY when exactly one such line is present: N-A is `deferred`, PASS is `NOT deferred` (a fallback ran the battery),
# anything else (FAIL, UNVERIFIED, absent, no line, two or more lines) is `not run/unknown`. The trailing space in the
# pattern keeps a longer row name (`agent-autonomy-alias`) from counting. Deferred or not, never why.
battery_state() {
  _bn=$(LC_ALL=C grep -c -e '^renderer probe: agent-autonomy ' "$1" || :)
  if [ "$_bn" != 1 ]; then echo "not run/unknown"; return 0; fi
  _bl=$(LC_ALL=C grep -e '^renderer probe: agent-autonomy ' "$1" || :)
  case "$_bl" in
    'renderer probe: agent-autonomy N-A') echo "deferred" ;;
    'renderer probe: agent-autonomy PASS') echo "NOT deferred" ;;
    *) echo "not run/unknown" ;;
  esac
}

# hf_pgid_ok <pgid> — the ONE gate before any group signal (the prepush-lane arm_pgid_ok gate): refuses empty, not all digits, a leading zero, at most 1 (`kill -- -1` reaches every process the user owns), the lane's own group and its parent's group, and refuses when the lane's own group cannot be read.
hf_pgid_ok() {
  case ${1-} in ''|*[!0-9]*|0?*) return 1 ;; esac
  [ "$1" -gt 1 ] || return 1
  _hf_own=$(ps -o pgid= -p "$$" 2>/dev/null | tr -d ' ') || _hf_own=''
  [ -n "$_hf_own" ] || return 1   # HFPG
  [ "$1" != "$_hf_own" ] || return 1   # HFPG
  _hf_par=$(ps -o pgid= -p "$PPID" 2>/dev/null | tr -d ' ') || _hf_par=''
  [ -z "$_hf_par" ] || [ "$1" != "$_hf_par" ] || return 1   # HFPG
  return 0
}
# hf_mode — one reading per target: is there a perl to make the group? Without one (errata E11) the faces run exactly as before: no group, no reap, the face's own verdict stands; one WARN names the consequence. Not UNVERIFIED, and _rv is untouched.
hf_mode() {
  if [ -x "$HF_PERL" ]; then _hf_grp=1; return 0; fi
  _hf_grp=0
  echo "  WARN: perl is missing, so leftover processes are not reaped; reds under load may follow"   # HFWARN
}
# hf_begin — per face: clear the sentinel and the per-face state.
hf_begin() { _hf_sent="$WORK/hf.sentinel"; rm -f "$_hf_sent"; _hf_pg=''; _hf_killed=0; _hf_left=''; }
# hf_exec <script> <flag> — the LAST act of a face's subshell: exec the face in a group of its own (the sentinel is the wrapper's first argument).
hf_exec() {
  if [ "$_hf_grp" = 1 ]; then exec "$HF_PERL" -e "$HF_PROG" -- "$_hf_sent" sh "$@"; fi
  exec sh "$@"
}
# hf_run <body-function> — run the face's subshell (its output to $_o); the face's rc is _hf_rc; then kill what it left in its group.
# Grouped (perl present): the subshell is a background job, and the pgid is set from $! on the SAME line as the `&`, so a TERM between the two still reaps (the pgid IS the leader's pid; the wrapper asserted it).
# No perl (errata E11): the OLD foreground form, so a Ctrl-C reaches the face exactly as before; nothing to reap.
hf_run() {
  _hf_rc=0
  if [ "$_hf_grp" = 1 ]; then
    ( "$1" ) >"$_o" 2>&1 & _hf_pg=$!; _hf_pid=$_hf_pg
    wait "$_hf_pid" || _hf_rc=$?
  else
    ( "$1" ) >"$_o" 2>&1 || _hf_rc=$?
  fi
  hf_reap
}
# hf_wait_gone <polls> — rc 0 as soon as the group has no member, rc 1 when the polls run out (0.1 s each).
hf_wait_gone() {
  _hw=0
  while [ "$_hw" -lt "$1" ]; do
    kill -s 0 -- "-$_hf_pg" 2>/dev/null || return 0
    sleep 0.1 2>/dev/null || sleep 1
    _hw=$((_hw + 1))
  done
  kill -s 0 -- "-$_hf_pg" 2>/dev/null || return 0
  return 1
}
# hf_reap — kill what the face left in its group: TERM (and CONT, to wake a member stopped on a tty), a short wait, KILL, a short wait. _hf_killed=1 says something was signalled; _hf_left names a group that could not be emptied (UNVERIFIED).
hf_reap() {
  _hf_left=''
  [ -n "$_hf_pg" ] || return 0
  kill -s 0 -- "-$_hf_pg" 2>/dev/null || { _hf_pg=''; return 0; }   # signal 0 delivers nothing: a face that left no member needs no gate (and a host with no ps must not read UNVERIFIED for it)
  if ! hf_pgid_ok "$_hf_pg"; then _hf_left="refused to signal group $_hf_pg"; _hf_pg=''; return 0; fi
  if kill -s TERM -- "-$_hf_pg" 2>/dev/null; then   # HFTERM
    _hf_killed=1
    kill -s CONT -- "-$_hf_pg" 2>/dev/null || :
    if ! hf_wait_gone 20; then
      kill -s KILL -- "-$_hf_pg" 2>/dev/null || :   # HFKILL
      hf_wait_gone 20 || _hf_left="group $_hf_pg still has members after KILL"
    fi
  fi
  _hf_pg=''
}
# hf_notes <label> — after a face: say what was killed; an unconfirmed kill is UNVERIFIED and the target exits non-zero.
hf_notes() {
  if [ "$_hf_killed" = 1 ]; then echo "  NOTE: $1 left processes running in its process group; killed"; fi
  if [ -n "$_hf_left" ]; then echo "  UNVERIFIED (leftover not confirmed gone): $1: $_hf_left"; _rv=1; fi
}
# hf_nogroup <label> — the wrapper could not make a group of its own (the sentinel exists); the face was never run and nothing was signalled.
hf_nogroup() {
  echo "  UNVERIFIED (no separate process group): $1 was not run — the group wrapper could not put $_rel in a process group of its own (the lane's own group is never signalled)"
  _rv=1
}
# hf_part <text> <n> — the n-th line of a multi-line string, in-process (no pipe, no fork); rc 1 when there is none.
hf_part() {
  _hp_i=0
  while IFS= read -r _hp_l; do
    _hp_i=$((_hp_i + 1))
    if [ "$_hp_i" = "$2" ]; then printf '%s\n' "$_hp_l"; return 0; fi
  done <<EOF
$1
EOF
  return 1
}
# hf_fp <repo-top> — the live tree's fingerprint, four lines: HEAD, the branch (the word detached when HEAD is not a branch: git exits 1 there, and every CI merge checkout is detached), a cksum of the staged entries (git ls-files -s) and a cksum of the porcelain status. NEVER the .git/index file: git status rewrites its stat data legitimately. A part git cannot answer reads UNREADABLE.
hf_fp() {
  _fp_h=$(git -C "$1" rev-parse HEAD 2>/dev/null) || _fp_h=UNREADABLE
  _fp_rc=0; _fp_b=$(git -C "$1" symbolic-ref -q HEAD 2>/dev/null) || _fp_rc=$?
  if [ "$_fp_rc" = 1 ]; then _fp_b=detached; elif [ "$_fp_rc" != 0 ]; then _fp_b=UNREADABLE; fi   # rc 1 is git's answer for a detached HEAD; any other rc is not an answer
  if git -C "$1" ls-files -s > "$WORK/fp.s" 2>/dev/null; then _fp_s=$(cksum < "$WORK/fp.s") || _fp_s=UNREADABLE; else _fp_s=UNREADABLE; fi
  if git -C "$1" --no-optional-locks status --porcelain > "$WORK/fp.p" 2>/dev/null; then _fp_p=$(cksum < "$WORK/fp.p") || _fp_p=UNREADABLE; else _fp_p=UNREADABLE; fi
  printf '%s\n%s\n%s\n%s\n' "$_fp_h" "$_fp_b" "$_fp_s" "$_fp_p"
}
# hf_diff <before> <after> — the names of the parts that moved or could not be read, comma-separated; empty = unchanged. A part missing from either reading counts as unreadable (fail closed).
hf_diff() {
  _hd_n=''; _hd_i=0
  for _hd_k in "HEAD" "branch" "staged entries" "working tree"; do
    _hd_i=$((_hd_i + 1))
    _hd_x=$(hf_part "$1" "$_hd_i") || _hd_x=UNREADABLE
    _hd_y=$(hf_part "$2" "$_hd_i") || _hd_y=UNREADABLE
    case "$_hd_x$_hd_y" in
      *UNREADABLE*) _hd_n="${_hd_n:+$_hd_n, }$_hd_k (unreadable)" ;;
      *) if [ "$_hd_x" != "$_hd_y" ]; then _hd_n="${_hd_n:+$_hd_n, }$_hd_k"; fi ;;
    esac
  done
  printf '%s' "$_hd_n"
}
# hf_moved <what> — the live tree changed during face (a): UNVERIFIED, non-zero, never green; face (b) still runs.
hf_moved() { echo "  UNVERIFIED (live tree changed during face (a): $1)"; _rv=1; }
# crash_sig_of <rc> - SWAS-600: rc above 128 is a signal death. Prints the signal NAME and returns 0 when it is a crash (SEGV BUS ILL ABRT FPE SYS TRAP); returns 1 for any other status, for TERM INT HUP KILL, and when kill -l cannot name it. Names, never numbers: BUS is 10 on macOS and 7 on Linux.
crash_sig_of() {
  case ${1-} in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$1" -gt 128 ] || return 1
  _cs_n=$(kill -l $(($1 - 128)) 2>/dev/null) || return 1
  _cs_n=${_cs_n#SIG}
  case $_cs_n in
    SEGV|BUS|ILL|ABRT|FPE|SYS|TRAP) printf '%s\n' "$_cs_n"; return 0 ;;
  esac
  return 1
}
# crash_line_in <file> - SWAS-600: does a captured output hold a shell's crash line? WHOLE-LINE match under LC_ALL=C grep -E, two forms (dash: the bare line; bash 3.2: <file>: line N: <pid> <text>[ <cmd>]). Prose, a table row and a quoted source line do not match. rc 0 found (CRASH_LINE, CRASH_TXT set), 1 none, 2 the scan could not run (a grep rc other than 0 or 1, a signal, or a hit file that cannot be written) - never clean. CEILING, stated: the bash-form prefix is a bare token, so a crash line whose script path contains whitespace does not match; the exit-status evidence still covers a top-level crash.
crash_line_in() {
  CRASH_LINE=""; CRASH_TXT=""
  _cl_x1="'"   # CRX1
  _cl_x2='"'   # CRX2
  _cl_x3='|'   # CRX3
  _cl_s='(Segmentation fault|Bus error|Illegal instruction|Abort trap|Aborted|Floating point exception|Bad system call|Trace/BPT trap|Trace/breakpoint trap)'   # CRSET
  _cl_pre='[^[:space:]'$_cl_x1$_cl_x2'`'$_cl_x3']+'   # CRPRE
  _cl_d='^[[:space:]]*'$_cl_s'(: [0-9]+)?( \(core dumped\))?[[:space:]]*$'
  _cl_b='^'$_cl_pre': line [0-9]+: +[0-9]+ '$_cl_s'(: [0-9]+)?( +\(core dumped\))?( .*)?$'   # CRBASH
  # a failed redirect must never read as "no hit" (bash 3.2 gives rc 1 for it)
  ( : > "$WORK/crash.hit" ) 2>/dev/null || return 2   # CRHIT
  _cl_r=0
  LC_ALL=C grep -E -e "$_cl_d" -e "$_cl_b" "$1" > "$WORK/crash.hit" 2>/dev/null || _cl_r=$?   # CRLINE
  case $_cl_r in
    0) ;;
    1) return 1 ;;
    *) return 2 ;;   # CRFAIL
  esac
  CRASH_LINE=$(sed -n 1p "$WORK/crash.hit") || return 2
  for _cl_n in 'Segmentation fault' 'Bus error' 'Illegal instruction' 'Abort trap' 'Aborted' 'Floating point exception' 'Bad system call' 'Trace/BPT trap' 'Trace/breakpoint trap'; do
    case $CRASH_LINE in
      *"$_cl_n"*) CRASH_TXT=$_cl_n; break ;;
    esac
  done
  return 0
}
# hf_crashed <label> <rc> - SWAS-600: did this face crash? By its exit status (a top-level crash is reaped by THIS script, so its line goes to the lane's capture, which we cannot read) or by a crash line in the face's own captured output $_o (a nested crash, whatever the face's rc). rc 0: yes, an UNVERIFIED line is printed and _rv is set; rc 1: no.
hf_crashed() {
  if _hc_s=$(crash_sig_of "$2"); then   # CRFRC
    echo "  UNVERIFIED ($1 crashed: $_hc_s, rc $2)"; _rv=1; return 0
  fi
  _hc_r=0; crash_line_in "$_o" || _hc_r=$?
  case $_hc_r in
    0) echo "  UNVERIFIED ($1 crashed: $CRASH_TXT line)"; _rv=1; return 0 ;;
    2) echo "  UNVERIFIED ($1: crash scan could not run: no verdict is claimed)"; _rv=1; return 0 ;;
  esac
  return 1
}
# hf_scan_fail - SWAS-604: does a face that exited 0 hold a line STARTING with FAIL in its captured output $_o? Sets _hf_fl: 0 yes, 1 no, 2 the scan could not run (a grep rc above 1, or a signal: never read as clean). Line start only: a FAIL quoted mid-line or indented is not a verdict. Called only for a face with rc 0.
hf_scan_fail() {
  _sf_r=0
  LC_ALL=C grep -q -e '^FAIL' "$_o" 2>/dev/null || _sf_r=$?   # HFFL
  case $_sf_r in
    0) _hf_fl=0 ;;
    1) _hf_fl=1 ;;
    *) _hf_fl=2 ;;
  esac
}
# hf_fl_red <face label> - SWAS-604: report a face with rc 0 that printed a FAIL line, as the rc-not-0 branch reports its red: the cause, the load, the FAIL lines, the output tail.
hf_fl_red() {
  echo "FAIL: $1 — $_rel rc 0, but it printed a FAIL line ($_el s) battery: $_bs."
  echo "  A selftest that prints a FAIL line must exit non-zero; an rc 0 beside one is a false green."
  hf_load
  first_fails "$_o"
  sed 's/^/    /' "$_o" | tail -30
}
# hf_load — printed beside a face red: the per-user process limit and the user's live process count, so the "grep could not spawn" inference (SWAS-577 design section 1) is measured the next time. A reading that cannot be made says so.
hf_load() {
  # shellcheck disable=SC3045  # ulimit -u/-p are non-POSIX by design: dash has only -p, bash's -p is the pipe size; both are tried with a fallback to 'unreadable'
  _hl_u=$(ulimit -u 2>/dev/null) || _hl_u=$(ulimit -p 2>/dev/null) || _hl_u=''   # -u first: dash has no -u (its process limit is -p), and in bash -p is the PIPE size
  _hl_id=$(id -u 2>/dev/null) || _hl_id=''
  _hl_n=unreadable
  if [ -n "$_hl_id" ]; then
    _hl_p=$(ps -U "$_hl_id" -o pid= 2>/dev/null) || _hl_p=''
    if [ -n "$_hl_p" ]; then set -- $_hl_p; _hl_n=$#; fi
  fi
  echo "  load: ulimit -u = ${_hl_u:-unreadable}; live processes of uid ${_hl_id:-unknown} = $_hl_n"
}
# hf_body_a / hf_body_b — the two face subshells' bodies (hf_run runs each in a subshell): the stripped environment of face (a), and the clone of face (b).
hf_body_a() {
  unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_AUTHOR_DATE GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_COMMITTER_DATE || true
  HOME=$_hh; GIT_CONFIG_GLOBAL=/dev/null; GIT_CONFIG_SYSTEM=/dev/null
  GIT_CONFIG_COUNT=1; GIT_CONFIG_KEY_0=user.useConfigOnly; GIT_CONFIG_VALUE_0=true
  TMPDIR=$_ta
  export HOME GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 TMPDIR
  cd "$_top" && hf_exec "$_rel" "$_sel"
}
hf_body_b() { cd "$_c" && TMPDIR=$_tb && export TMPDIR && hf_exec "$_rel" "$_sel"; }
# hf_face_a — face (a): stripped environment (B2 §10-A9's exact recipe). rc 1 = the face reds (the lane stops there); UNVERIFIED sets _rv.
hf_face_a() {
  _hh="$WORK/home.$$"; mkdir -p "$_hh"
  _ta=$(mktemp -d "$WORK/tmp.a.XXXXXX") || { echo "FAIL: face (a) — cannot make its TMPDIR"; return 1; }
  _fp0=$(hf_fp "$_top")
  _t0=$(date +%s); hf_begin
  hf_run hf_body_a
  _fa=$_hf_rc
  _el=$(( $(date +%s) - _t0 )); _bs=$(battery_state "$_o")
  _hf_fl=1; if [ "$_fa" = 0 ]; then hf_scan_fail; fi
  _fchg=$(hf_diff "$_fp0" "$(hf_fp "$_top")")   # HFCMP
  rm -rf "$_ta"
  if [ -e "$_hf_sent" ]; then
    hf_nogroup "face (a)"
  elif hf_crashed "face (a)" "$_fa"; then
    :   # a crash is UNVERIFIED, never a FAIL or a PASS; face (b) still runs
  elif [ "$_fa" != 0 ]; then
    echo "FAIL: face (a) stripped-env — $_rel reds with no ambient identity/config (rc $_fa) ($_el s) battery: $_bs."
    echo "  The selftest reads git identity/config it did not set (green on a dev tree, dead on a runner)."
    hf_load
    first_fails "$_o"
    sed 's/^/    /' "$_o" | tail -30
    hf_notes "face (a)"
    if [ -n "$_fchg" ]; then hf_moved "$_fchg"; fi
    return 1
  elif [ "$_hf_fl" = 0 ]; then
    hf_fl_red "face (a) stripped-env"
    hf_notes "face (a)"
    if [ -n "$_fchg" ]; then hf_moved "$_fchg"; fi
    return 1
  elif [ "$_hf_fl" = 2 ]; then
    echo "  UNVERIFIED (face (a): the FAIL-line scan could not run: no verdict is claimed)"; _rv=1
    if [ -n "$_fchg" ]; then hf_moved "$_fchg"; fi   # HFFLMV
  elif [ -n "$_fchg" ]; then
    hf_moved "$_fchg"
  else
    echo "  PASS: face (a) stripped-env — $_rel$_tag ($_el s) battery: $_bs"
  fi
  hf_notes "face (a)"
  return 0
}
# hf_face_b — face (b): a --no-local clone (no notes refs, no ambient object store; grades HEAD).
hf_face_b() {
  _c="$WORK/clone.$$"; rm -rf "$_c"
  git clone --no-local --quiet "$_top" "$_c" 2>>"$_o" || { echo "FAIL: face (b) — cannot clone $_top"; sed 's/^/    /' "$_o" | tail -10; return 1; }
  if [ ! -f "$_c/$_rel" ]; then
    echo "FAIL: face (b) — $_rel is not in the clone: it is uncommitted. Face (b) grades HEAD; commit before running the lane."
    rm -rf "$_c"; return 1
  fi
  _tb=$(mktemp -d "$WORK/tmp.b.XXXXXX") || { echo "FAIL: face (b) — cannot make its TMPDIR"; rm -rf "$_c"; return 1; }
  _t0=$(date +%s); hf_begin
  hf_run hf_body_b
  _fb=$_hf_rc
  _el=$(( $(date +%s) - _t0 )); _bs=$(battery_state "$_o")
  _hf_fl=1; if [ "$_fb" = 0 ]; then hf_scan_fail; fi
  rm -rf "$_c" "$_tb"
  if [ -e "$_hf_sent" ]; then
    hf_nogroup "face (b)"
  elif hf_crashed "face (b)" "$_fb"; then
    :   # a crash is UNVERIFIED, never a FAIL or a PASS
  elif [ "$_fb" != 0 ]; then
    echo "FAIL: face (b) clone — $_rel reds inside a fresh git clone --no-local (rc $_fb) ($_el s) battery: $_bs."
    echo "  The selftest reads ambient notes-refs/object-store/worktree state a clone does not carry."
    hf_load
    first_fails "$_o"
    sed 's/^/    /' "$_o" | tail -30
    hf_notes "face (b)"
    return 1
  elif [ "$_hf_fl" = 0 ]; then
    hf_fl_red "face (b) clone"
    hf_notes "face (b)"
    return 1
  elif [ "$_hf_fl" = 2 ]; then
    echo "  UNVERIFIED (face (b): the FAIL-line scan could not run: no verdict is claimed)"; _rv=1
  else
    echo "  PASS: face (b) clone — $_rel$_tag ($_el s) battery: $_bs"
  fi
  hf_notes "face (b)"
  return 0
}

# run_faces <path> — run <path> --selftest under both faces. 0 = both pass and nothing read UNVERIFIED; 1 = a face failed or read UNVERIFIED,
# with the FACE, TARGET and captured output named (the operator must not need a re-run to see why).
# HONEST CEILINGS (SWAS-592): a descendant that leaves the face's process group (setsid, setpgrp, a nested lane that makes its own group) is neither reaped nor reported.
# The face (a) fingerprint reads HEAD, the branch, the staged entries and the porcelain status; it does not see refs other than HEAD, .git/config, or ignored files.
run_faces() {
  _tgt=$1
  _top=$(_repo_of "$_tgt") || { echo "FAIL: $_tgt is not inside a git repo (face (b) needs one)"; return 1; }
  # pwd -P: git rev-parse --show-toplevel answers the PHYSICAL path, so the target's dir must be
  # canonicalized the same way or the prefix-strip fails on a symlinked tmpdir (macOS /var -> /private/var).
  _abs=$(CDPATH='' cd "$(dirname "$_tgt")" && pwd -P)/$(basename "$_tgt")
  _rel=${_abs#"$_top"/}
  _o="$WORK/face.out"
  _sel=--selftest; _tag=''
  if core_face_listed "$_top" "$_rel"; then
    # SWAS-460: on a kit tree a listed target runs its mutant-free core only; a core arm that is absent reds, never passes vacuously
    if ! sed 's/#.*//' "$_top/$_rel" | grep -q -E -e '(^|\|)[[:space:]]*--selftest-core[[:space:]]*[|)]'; then
      echo "FAIL: $_rel is core-only (the core-face list) but has no --selftest-core arm — refusing to pass vacuously"
      return 1
    fi
    _core=$((_core + 1)); _sel=--selftest-core; _tag=' [--selftest-core]'
    echo "CORE-ONLY: $_rel — both faces run --selftest-core; the full mutant --selftest is graded by CI job $(basename "$_rel" .sh), not here"
  fi

  _rv=0; hf_mode
  hf_face_a || return 1
  hf_face_b || return 1
  return "$_rv"
}

# touched_set — changed files vs merge-base(HEAD, $BASE), intersected with the roster.
# An underivable base FAILS LOUD: a lane that silently passes when it cannot see the diff is
# satisfiable by breaking the diff derivation.
touched_set() {
  git rev-parse --verify --quiet "$BASE" >/dev/null 2>&1 || {
    echo "FAIL: base '$BASE' is not resolvable — cannot derive the touched set (fetch the base, or set HERMETIC_BASE). Refusing to silent-pass." >&2
    return 1
  }
  _mb=$(git merge-base HEAD "$BASE" 2>/dev/null) || {
    echo "FAIL: no merge-base between HEAD and '$BASE' (shallow history?) — deepen the fetch. Refusing to silent-pass." >&2
    return 1
  }
  git diff --name-only "$_mb" HEAD | sort -u > "$WORK/changed"
  roster > "$WORK/roster"
  comm -12 "$WORK/changed" "$WORK/roster"
}

# run_lane <path>... — the shared engine for every non-selftest mode.
run_lane() {
  validate_exclusions || return 1
  _fail=0; _ran=0; _core=0
  for _t in "$@"; do
    [ -f "$_t" ] || { echo "FAIL: target not found: $_t"; _fail=1; continue; }
    excluded "$_t" && continue
    _ran=$((_ran + 1))
    echo "TARGET: $_t (both faces)"
    run_faces "$_t" || _fail=1
  done
  if [ "$_fail" != 0 ]; then
    echo "selftest-hermetic: FAIL — a targeted --selftest is not hermetic (face + output above)."
    return 1
  fi
  echo "selftest-hermetic: OK ($_ran target(s) passed both faces, $_core of them --selftest-core only (CORE-ONLY above))"
  echo "  note: the per-PR --touched binding is kit-CI-only; adopter trees carry only this lane's --selftest via verify.sh --require — wire --touched into your own pipeline for per-PR coverage (design §10-A1)"
  return 0
}

# ---------------------------------------------------------------------------- selftest
selftest() {
  sfail=0
  _self=$(CDPATH='' cd "$(dirname "$0")" && pwd)/$(basename "$0")
  st="$WORK/st"; mkdir -p "$st"
  _unv_f=$WORK/unverified   # SWAS-592: the marker file of grep calls that could not answer (read by _unv_end before the verdict)
  : > "$_unv_f" || { echo "FAIL: selftest — the UNVERIFIED marker file cannot be created ($_unv_f), so an unanswered grep could not be recorded"; sfail=1; }

  # 1. AMBIENT-IDENTITY fixture: a selftest doing a BARE `git commit` (no inline -c identity)
  #    => face (a) must RED it, through the whole lane (main path, not a direct function call).
  st_repo "$st/fa"
  st_script "$st/fa/conformance/ambient-check.sh" 'bare'
  st_commit "$st/fa"
  rc=0; out=$( cd "$st/fa" && sh "$_self" conformance/ambient-check.sh 2>&1 ) || rc=$?
  st_expect "ambient-identity fixture REDs on face (a)" 1 "$rc"
  _has "$out" 'face (a)' || { echo "FAIL: selftest — the failure did not NAME face (a)"; sfail=1; }

  # 2. HERMETIC TWIN (inline -c identity) => both faces pass, rc 0 (liveness anchor: a lane that
  #    reds everything would pass leg 1 and be worse than useless).
  st_repo "$st/ft"
  st_script "$st/ft/conformance/hermetic-check.sh" 'inline'
  st_commit "$st/ft"
  rc=0; ( cd "$st/ft" && sh "$_self" conformance/hermetic-check.sh ) >/dev/null 2>&1 || rc=$?
  st_expect "hermetic twin passes both faces" 0 "$rc"

  # 3. AMBIENT-NOTES fixture: a selftest reading a notes ref it did not create => face (a) passes
  #    (the ref exists in the working repo) but face (b) must RED it (a clone carries no notes).
  st_repo "$st/fb"
  st_script "$st/fb/conformance/notes-check.sh" 'notes'
  st_commit "$st/fb"
  ( cd "$st/fb" && git -c user.email=t@kit -c user.name=kit notes --ref=amb add -m x HEAD ) >/dev/null 2>&1
  rc=0; out=$( cd "$st/fb" && sh "$_self" conformance/notes-check.sh 2>&1 ) || rc=$?
  st_expect "ambient-notes fixture REDs on face (b)" 1 "$rc"
  _has "$out" 'face (b)' || { echo "FAIL: selftest — the failure did not NAME face (b)"; sfail=1; }

  # 4. --touched, empty intersection => N/A, rc 0 (with the reason printed).
  st_repo "$st/fc"; st_commit "$st/fc"
  ( cd "$st/fc" && git update-ref refs/remotes/origin/main HEAD ) >/dev/null 2>&1
  rc=0; out=$( cd "$st/fc" && sh "$_self" --touched 2>&1 ) || rc=$?
  st_expect "--touched with no touched roster files = N/A rc 0" 0 "$rc"
  _has "$out" 'N/A' || { echo "FAIL: selftest — empty --touched did not say N/A"; sfail=1; }

  # 5. --touched picks up a touched roster script (positive discrimination), and passes on the twin.
  ( cd "$st/fc" && git update-ref refs/remotes/origin/main HEAD ) >/dev/null 2>&1
  st_script "$st/fc/conformance/hermetic-check.sh" 'inline'
  st_commit "$st/fc"
  rc=0; out=$( cd "$st/fc" && sh "$_self" --touched 2>&1 ) || rc=$?
  st_expect "--touched targets the touched hermetic script, both faces pass" 0 "$rc"
  _has "$out" 'hermetic-check.sh' || { echo "FAIL: selftest — --touched did not target the touched script"; sfail=1; }

  # 6. --touched with an UNDERIVABLE base => FAIL LOUD rc 1 (never a silent pass).
  st_repo "$st/fd"; st_commit "$st/fd"
  rc=0; out=$( cd "$st/fd" && sh "$_self" --touched 2>&1 ) || rc=$?
  st_expect "--touched with no resolvable base = FAIL LOUD" 1 "$rc"
  _grepx "$out" -qi 'base' && _b7=0 || _b7=$?
  if [ "$_b7" = 1 ]; then echo "FAIL: selftest — the underivable-base failure did not name the base"; sfail=1; fi   # rc 2: _grepx already printed UNVERIFIED (grep rc=N) and marked the run

  # 7. exclusion-with-reason skips (rc 0, disposition printed); a REASONLESS entry FAILS the lane.
  printf '# fixture exclusions\nambient-check.sh\tfixture: planted non-hermetic selftest, excluded to prove the escape is dispositioned\n' > "$st/fa/conformance/hermetic-exclusions.txt"
  rc=0; out=$( cd "$st/fa" && sh "$_self" conformance/ambient-check.sh 2>&1 ) || rc=$?
  st_expect "excluded-with-reason target is skipped (rc 0)" 0 "$rc"
  _has "$out" 'EXCLUDED' || { echo "FAIL: selftest — exclusion disposition not printed"; sfail=1; }
  printf 'ambient-check.sh\n' > "$st/fa/conformance/hermetic-exclusions.txt"
  rc=0; ( cd "$st/fa" && sh "$_self" conformance/ambient-check.sh ) >/dev/null 2>&1 || rc=$?
  st_expect "a reasonless exclusion entry FAILS the lane" 1 "$rc"

  # 8. an EXCLUSIONS-ONLY diff (touched∩roster empty) with a reasonless entry must STILL fail rc 1
  #    (reviewer 3: before the fix, the N/A exit ran before validate_exclusions — a PR touching only
  #    hermetic-exclusions.txt could widen the bypass surface unvalidated).
  st_repo "$st/fe"; st_commit "$st/fe"
  ( cd "$st/fe" && git update-ref refs/remotes/origin/main HEAD ) >/dev/null 2>&1
  printf 'anything.sh\n' > "$st/fe/conformance/hermetic-exclusions.txt"   # REASONLESS
  st_commit "$st/fe"
  rc=0; out=$( cd "$st/fe" && sh "$_self" --touched 2>&1 ) || rc=$?
  st_expect "exclusions-only --touched diff with a reasonless entry FAILS (no N/A bypass)" 1 "$rc"
  _has "$out" 'no <TAB>reason' || { echo "FAIL: selftest — the exclusions-only failure did not name the reasonless entry"; sfail=1; }

  # 9. FIRST-FAIL CAPTURE (SWAS-244/248): a red face names its FAIL lines before the tail, so a FAIL in the
  #    middle of a long output is not hidden under the PASS legs that follow it. One shared fixture repo.
  st_repo "$st/fh"
  for _k in fail1 nofail passshape fail15 unv; do st_fix "$st/fh/conformance/$_k-check.sh" "$_k"; done
  st_commit "$st/fh"
  # H1 — one FAIL line, then 40 PASS lines: the FAIL line is listed with its line number
  rc=0; out=$( cd "$st/fh" && sh "$_self" conformance/fail1-check.sh 2>&1 ) || rc=$?
  st_expect "H1 first-FAIL: a lone FAIL line buried above 40 PASS lines is lane rc 1" 1 "$rc"
  st_has "H1 the FAIL line is listed under '1 FAIL lines:'" "$out" '1 FAIL lines:'
  st_has "H1 the FAIL line is listed with its line number" "$out" '1:selftest FAIL: boom'
  # H9 (SWAS-592, control 9) — a red face prints the per-user process limit and the live process count (the labels are asserted; the numbers are read by the person)
  st_has "H9 a red face prints the process limit" "$out" 'load: ulimit -u = '
  st_has "H9 a red face prints the user's live process count" "$out" '; live processes of uid '
  _h9=${out#*"load: ulimit -u = "}; _h9=${_h9%%;*}
  case $_h9 in unlimited) _h9ok=1 ;; ''|*[!0-9]*) _h9ok=0 ;; *) _h9ok=1 ;; esac
  if [ "$_h9ok" = 1 ]; then echo "PASS: selftest — H9 the limit field is digits or unlimited ('$_h9'), not 'unreadable'"
  else echo "FAIL: selftest — H9 the limit field is '$_h9', want digits or unlimited"; sfail=1; fi
  if command -v dash >/dev/null 2>&1; then
    rc=0; out=$( cd "$st/fh" && dash "$_self" conformance/fail1-check.sh 2>&1 ) || rc=$?
    _h9=${out#*"load: ulimit -u = "}; _h9=${_h9%%;*}
    case $_h9 in unlimited) _h9ok=1 ;; ''|*[!0-9]*) _h9ok=0 ;; *) _h9ok=1 ;; esac
    if [ "$rc" = 1 ] && [ "$_h9ok" = 1 ]; then echo "PASS: selftest — H9d the lane run BY dash reads the limit too ('$_h9'; dash has no ulimit -u, so -p is the fallback)"
    else echo "FAIL: selftest — H9d the lane run by dash printed limit '$_h9' (rc $rc), want digits or unlimited"; sfail=1; fi
  else echo "SKIP: selftest — H9d no dash here"; fi
  # H2 — rc 1 with no FAIL word anywhere: the output says so
  rc=0; out=$( cd "$st/fh" && sh "$_self" conformance/nofail-check.sh 2>&1 ) || rc=$?
  st_expect "H2 no-FAIL: 40 PASS lines and rc 1 is lane rc 1" 1 "$rc"
  st_has "H2 the output says no line contains FAIL" "$out" 'no output line contains FAIL or UNVERIFIED; see the tail below'
  # H7 (SWAS-577) — a red whose only marker is an UNVERIFIED line still shows its cause
  rc=0; out=$( cd "$st/fh" && sh "$_self" conformance/unv-check.sh 2>&1 ) || rc=$?
  st_expect "H7 UNVERIFIED-only: lane rc 1" 1 "$rc"
  st_has "H7 the UNVERIFIED line is listed with its line number" "$out" '1:selftest UNVERIFIED (grep rc=2)'
  # H5 — tracker-contract's real PASS shape that names FAIL is skipped; the real line is kept
  rc=0; out=$( cd "$st/fh" && sh "$_self" conformance/passshape-check.sh 2>&1 ) || rc=$?
  st_expect "H5 PASS-shape: lane rc 1" 1 "$rc"
  st_has "H5 exactly one line is listed (the PASS-shaped line is skipped)" "$out" '1 FAIL lines:'
  st_has "H5 the real line is the one listed (a blanket PASS exclusion would lose it)" "$out" '2:selftest FAIL: expected PASS'
  # H6 — 15 FAIL lines: the header counts all, the list stops at 10
  rc=0; out=$( cd "$st/fh" && sh "$_self" conformance/fail15-check.sh 2>&1 ) || rc=$?
  st_expect "H6 cap: 15 FAIL lines is lane rc 1" 1 "$rc"
  st_has "H6 the header reads 'first 10 of 15 FAIL lines:'" "$out" 'first 10 of 15 FAIL lines:'
  if _n=$(_grepx "$out" -c -e ':selftest FAIL: leg '); then :; fi
  st_expect "H6 exactly 10 FAIL lines are listed" 10 "$_n"

  # H3 — an outer SENTINEL TMPDIR: each face must hold its own fresh TMPDIR (the fixture reds if TMPDIR still
  #      equals the sentinel, or if its explicit-template mktemp does not land under the physical TMPDIR).
  #      Equality, not mktemp behaviour, so a face that forgets to export TMPDIR reds on every platform.
  _sent=$(mktemp -d "$WORK/sent.XXXXXX")
  st_repo "$st/fs"
  st_fix "$st/fs/conformance/sentinel-check.sh" sentinel
  st_commit "$st/fs"
  rc=0; out=$( cd "$st/fs" && TMPDIR=$_sent HERMETIC_ST_SENT=$_sent sh "$_self" conformance/sentinel-check.sh 2>&1 ) || rc=$?
  st_expect "H3 both faces hold a fresh TMPDIR under an outer sentinel TMPDIR" 0 "$rc"
  st_has "H3 face (a) passed" "$out" 'PASS: face (a)'
  st_has "H3 face (b) passed" "$out" 'PASS: face (b)'

  # N2 — a face whose TMPDIR cannot be made FAILS closed (never runs with TMPDIR empty and passes). A PATH shim
  #      makes the explicit-template mktemp of one face exit 1; the hermetic twin would pass otherwise.
  _real_mk=$(command -v mktemp)
  mkdir -p "$WORK/shim"
  # The shim refuses only an argument whose BASENAME is the face's own template, so an outer TMPDIR that
  # itself has tmp.a. / tmp.b. path components (the lane inside a face) does not trip it.
  printf '#!/bin/sh\nfor _a in "$@"; do\n  case "$_a" in\n    */"$FAIL_MK") exit 1 ;;\n  esac\ndone\nexec "%s" "$@"\n' "$_real_mk" > "$WORK/shim/mktemp"
  chmod +x "$WORK/shim/mktemp"
  _odd="$_sent/tmp.a.1/tmp.b.1"; mkdir -p "$_odd"
  for _fc in a b; do
    rc=0; out=$( cd "$st/ft" && TMPDIR=$_odd PATH="$WORK/shim:$PATH" FAIL_MK="tmp.$_fc.XXXXXX" sh "$_self" conformance/hermetic-check.sh 2>&1 ) || rc=$?
    st_expect "N2 face ($_fc) with an unmakeable TMPDIR is lane rc 1" 1 "$rc"
    st_has "N2 face ($_fc) names the TMPDIR failure" "$out" "FAIL: face ($_fc) — cannot make its TMPDIR"
  done

  # HB (SWAS-376, C1(i) + C3) — every face's PASS/FAIL line states the guard battery's state and the face's seconds, on green as well as
  #      red. The state comes from the face's own `renderer probe: agent-autonomy <verdict>` line and only when EXACTLY ONE such line is
  #      present: N-A is `deferred`, PASS is `NOT deferred`, and everything else (FAIL, UNVERIFIED, no line, two lines, a longer row name)
  #      is `not run/unknown`. The suffix is `(<n> s) battery: <state>`; a lane that always says `deferred`, takes the first of two
  #      lines, or reports 0 s reds a cell below. Fixture faces print the probe shapes; the lane runs through its main path.
  st_repo "$st/fp"
  for _k in probena probepass probefail probeunv probenone probetwo probealias probealias2 probered sleep2; do st_fix "$st/fp/conformance/$_k-check.sh" "$_k"; done
  st_commit "$st/fp"
  # probealias2: the real row N-A beside a longer-named row's PASS line is still ONE probe line (the alias does not count, so it is `deferred`)
  for _hb in "probena:deferred" "probepass:NOT deferred" "probefail:not run/unknown" "probeunv:not run/unknown" "probenone:not run/unknown" "probetwo:not run/unknown" "probealias:not run/unknown" "probealias2:deferred"; do
    _hk=${_hb%%:*}; _hw=${_hb#*:}
    rc=0; out=$( cd "$st/fp" && sh "$_self" "conformance/$_hk-check.sh" 2>&1 ) || rc=$?
    st_expect "HB $_hk: both faces pass, lane rc 0" 0 "$rc"
    for _hf in a b; do
      if _hl=$(_grepx "$out" -F -e "PASS: face ($_hf)"); then :; fi
      case "$_hl" in
        *") battery: $_hw") echo "PASS: selftest — HB $_hk face ($_hf) states 'battery: $_hw'" ;;
        *) echo "FAIL: selftest — HB $_hk face ($_hf) line does not end '(<n> s) battery: $_hw': [$_hl]"; sfail=1 ;;
      esac
    done
  done
  # a RED face states it too (the FAIL line, not only the PASS line): face (a) reds, the probe line says N-A
  rc=0; out=$( cd "$st/fp" && sh "$_self" conformance/probered-check.sh 2>&1 ) || rc=$?
  st_expect "HB probered: a red face is lane rc 1" 1 "$rc"
  if _hl=$(_grepx "$out" -F -e "FAIL: face (a)"); then :; fi
  case "$_hl" in
    *") battery: deferred.") echo "PASS: selftest — HB probered the FAIL line states 'battery: deferred'" ;;
    *) echo "FAIL: selftest — HB probered the FAIL line does not end '(<n> s) battery: deferred.': [$_hl]"; sfail=1 ;;
  esac
  # C3 non-vacuity: a face that sleeps 2 s reports at least 2 s on each face's line (a constant-0 timer reds)
  rc=0; out=$( cd "$st/fp" && sh "$_self" conformance/sleep2-check.sh 2>&1 ) || rc=$?
  st_expect "HB sleep2: both faces pass, lane rc 0" 0 "$rc"
  for _hf in a b; do
    if _hl=$(_grepx "$out" -F -e "PASS: face ($_hf)"); then :; fi
    _hs=${_hl%%" s) battery"*}; _hs=${_hs##*(}
    case "$_hs" in
      ''|*[!0-9]*) echo "FAIL: selftest — HB sleep2 face ($_hf) carries no whole-seconds '(<n> s)' field: [$_hs]"; sfail=1 ;;
      *) if [ "$_hs" -ge 2 ]; then echo "PASS: selftest — HB sleep2 face ($_hf) reports $_hs s (>= 2)"
         else echo "FAIL: selftest — HB sleep2 face ($_hf) reports $_hs s for a 2 s sleep (a constant timer?)"; sfail=1; fi ;;
    esac
  done

  # CF1-CF7 (SWAS-460) — the kit-tree core-face list. A listed target runs --selftest-core under both faces, only where the repo top holds a kit marker
  #      (docs/ROADMAP-KIT.md); every other target, and every target on an adopter-shaped tree, keeps --selftest. Fixture stubs log "<argv0> <args>" to $CF_LOG.
  st_repo "$st/cfk"; mkdir -p "$st/cfk/docs/conformance"; : > "$st/cfk/docs/ROADMAP-KIT.md"
  for _k in conformance/boundary-redteam.sh conformance/other-check.sh docs/conformance/boundary-redteam.sh conformance/boundary-redteam.sh.bak; do
    st_cfstub "$st/cfk/$_k" core
  done
  st_commit "$st/cfk"
  _cfl="$WORK/cf1.log"; : > "$_cfl"
  rc=0; out=$( cd "$st/cfk" && CF_LOG=$_cfl sh "$_self" conformance/boundary-redteam.sh conformance/other-check.sh 2>&1 ) || rc=$?
  st_expect "CF1 kit tree: the listed path and a non-listed one both pass the lane" 0 "$rc"
  st_count "CF1 the listed path is called with --selftest-core on both faces" 2 "$_cfl" 'conformance/boundary-redteam.sh --selftest-core'
  st_count "CF1 the listed path is never called with the full --selftest" 0 "$_cfl" 'conformance/boundary-redteam.sh --selftest'
  st_has "CF1 the OK summary counts the core-only target" "$out" 'OK (2 target(s) passed both faces, 1 of them --selftest-core only (CORE-ONLY above))'
  st_has "CF2 the CORE-ONLY line names the grading CI job" "$out" 'CORE-ONLY: conformance/boundary-redteam.sh — both faces run --selftest-core; the full mutant --selftest is graded by CI job boundary-redteam, not here'
  st_has "CF2 face (a) PASS line carries the tag" "$out" 'PASS: face (a) stripped-env — conformance/boundary-redteam.sh [--selftest-core] ('
  st_has "CF2 face (b) PASS line carries the tag" "$out" 'PASS: face (b) clone — conformance/boundary-redteam.sh [--selftest-core] ('
  st_count "CF3 a non-listed target in the same run still gets the full --selftest on both faces" 2 "$_cfl" 'conformance/other-check.sh --selftest'
  st_count "CF3 a non-listed target never gets --selftest-core" 0 "$_cfl" 'conformance/other-check.sh --selftest-core'
  _cfl="$WORK/cf4.log"; : > "$_cfl"
  rc=0; out=$( cd "$st/cfk" && CF_LOG=$_cfl sh "$_self" docs/conformance/boundary-redteam.sh conformance/boundary-redteam.sh.bak 2>&1 ) || rc=$?
  st_expect "CF4 the two near-miss paths pass the lane" 0 "$rc"
  st_count "CF4 docs/conformance/boundary-redteam.sh (a suffix of the listed path) gets the full --selftest twice" 2 "$_cfl" 'docs/conformance/boundary-redteam.sh --selftest'
  st_count "CF4 conformance/boundary-redteam.sh.bak (a prefix of the listed path) gets the full --selftest twice" 2 "$_cfl" 'conformance/boundary-redteam.sh.bak --selftest'
  st_count "CF4 neither near-miss gets --selftest-core" 0 "$_cfl" 'docs/conformance/boundary-redteam.sh --selftest-core'
  st_lacks "CF4 no CORE-ONLY line for a near-miss path" "$out" 'CORE-ONLY:'
  st_repo "$st/cfm"; mkdir -p "$st/cfm/docs"; : > "$st/cfm/docs/ROADMAP-KIT.md"
  st_cfstub "$st/cfm/conformance/boundary-redteam.sh" full
  st_commit "$st/cfm"
  _cfl="$WORK/cf5.log"; : > "$_cfl"
  rc=0; out=$( cd "$st/cfm" && CF_LOG=$_cfl sh "$_self" conformance/boundary-redteam.sh 2>&1 ) || rc=$?
  st_expect "CF5 a listed target with no --selftest-core arm FAILS the lane" 1 "$rc"
  st_has "CF5 the failure names the missing arm" "$out" 'has no --selftest-core arm'
  st_count "CF5 the target was not run at all (no vacuous pass)" 0 "$_cfl" 'conformance/boundary-redteam.sh --selftest'
  # CF5b — an arm that exists only as text in an echo is not an arm (a substring test would pass it vacuously)
  st_repo "$st/cfn"; mkdir -p "$st/cfn/docs"; : > "$st/cfn/docs/ROADMAP-KIT.md"
  st_cfstub "$st/cfn/conformance/boundary-redteam.sh" mention
  st_commit "$st/cfn"
  rc=0; out=$( cd "$st/cfn" && CF_LOG=$_cfl sh "$_self" conformance/boundary-redteam.sh 2>&1 ) || rc=$?
  st_expect "CF5b a stub that only mentions --selftest-core in an echo FAILS the lane" 1 "$rc"
  st_has "CF5b the failure names the missing arm" "$out" 'has no --selftest-core arm'
  _n=$(grep -c -x -e "CORE_FACE_TARGETS='conformance/boundary-redteam.sh'" "$_self" || :)
  st_expect "CF6 the list is the literal one entry, once" 1 "$_n"
  st_expect "CF6 the real file names the list on exactly its three lines, readonly directly after the literal" "3 1 1 1 1" "$(st_cfcount "$_self")"
  _l1="CORE_FACE_TARGETS='a'"; _l2="readonly CORE_FACE_TARGETS"; _l3='  for _e in $CORE_FACE_TARGETS; do'
  st_expect "CF6 fixture: the three expected lines count 3 1 1 1 1" "3 1 1 1 1" "$(st_cffix "$_l1" "$_l2" "$_l3")"
  st_expect "CF6 fixture: an export between the literal and readonly is counted" "4 1 1 1 0" "$(st_cffix "$_l1" 'export CORE_FACE_TARGETS="$CORE_FACE_TARGETS b"' "$_l2" "$_l3")"
  st_expect "CF6 fixture: an eval line is counted" "4 1 1 1 1" "$(st_cffix "$_l1" "$_l2" "$_l3" 'eval "CORE_FACE_TARGETS=b"')"
  st_expect "CF6 fixture: an indented append is counted" "4 1 1 1 1" "$(st_cffix "$_l1" "$_l2" "$_l3" '  CORE_FACE_TARGETS="$CORE_FACE_TARGETS b"')"
  st_expect "CF6 fixture: readonly moved down is not adjacent" "3 1 1 1 0" "$(st_cffix "$_l1" "$_l3" "$_l2")"
  # CF10 (R2) — a readonly violation must never exit 0 (bash 3.2 posix under an EXIT trap does, without the done-sentinel)
  awk '{ print } /^core_face_listed\(\) \{$/ { print "  CORE_FACE_TARGETS=\"x\"" }' "$_self" > "$WORK/r2.sh"
  rc=0; ( cd "$st/cfk" && CF_LOG=$_cfl sh "$WORK/r2.sh" conformance/other-check.sh ) >/dev/null 2>&1 || rc=$?
  if [ "$rc" = 0 ]; then rc=zero; else rc=nonzero; fi
  st_expect "CF10 a readonly-violation abort exits non-zero" nonzero "$rc"
  # CF9 — an entry is never a glob: a list of 'conformance/*.sh' must not make conformance/other-check.sh core-only
  sed "s,^CORE_FACE_TARGETS='.*'\$,CORE_FACE_TARGETS='conformance/*.sh'," "$_self" > "$WORK/cf9.sh"
  _cfl="$WORK/cf9.log"; : > "$_cfl"
  rc=0; ( cd "$st/cfk" && CF_LOG=$_cfl sh "$WORK/cf9.sh" conformance/other-check.sh ) >/dev/null 2>&1 || rc=$?
  st_expect "CF9 a glob entry: the lane passes" 0 "$rc"
  st_count "CF9 a glob entry never matches a path (full --selftest on both faces)" 2 "$_cfl" 'conformance/other-check.sh --selftest'
  st_repo "$st/cfa"
  st_cfstub "$st/cfa/conformance/boundary-redteam.sh" core
  st_commit "$st/cfa"
  _cfl="$WORK/cf7.log"; : > "$_cfl"
  rc=0; out=$( cd "$st/cfa" && CF_LOG=$_cfl sh "$_self" conformance/boundary-redteam.sh 2>&1 ) || rc=$?
  st_expect "CF7 adopter-shaped tree: the listed path passes the lane" 0 "$rc"
  st_count "CF7 adopter-shaped tree: the listed path gets the full --selftest on both faces" 2 "$_cfl" 'conformance/boundary-redteam.sh --selftest'
  st_count "CF7 adopter-shaped tree: never --selftest-core" 0 "$_cfl" 'conformance/boundary-redteam.sh --selftest-core'
  st_lacks "CF7 adopter-shaped tree: no CORE-ONLY line" "$out" 'CORE-ONLY:'
  st_has "CF7 adopter-shaped tree: the OK summary counts no core-only target" "$out" '1 target(s) passed both faces, 0 of them --selftest-core only'
  # CF8 — the other kit marker alone (.github/workflows/golden-path.yml, no docs/ROADMAP-KIT.md) also makes it a kit tree
  st_repo "$st/cfg"; mkdir -p "$st/cfg/.github/workflows"; : > "$st/cfg/.github/workflows/golden-path.yml"
  st_cfstub "$st/cfg/conformance/boundary-redteam.sh" core
  st_commit "$st/cfg"
  _cfl="$WORK/cf8.log"; : > "$_cfl"
  rc=0; ( cd "$st/cfg" && CF_LOG=$_cfl sh "$_self" conformance/boundary-redteam.sh ) >/dev/null 2>&1 || rc=$?
  st_expect "CF8 golden-path.yml alone marks a kit tree: the lane passes" 0 "$rc"
  st_count "CF8 golden-path.yml alone: the listed path gets --selftest-core on both faces" 2 "$_cfl" 'conformance/boundary-redteam.sh --selftest-core'

  # MTC1-MTC7 (SWAS-592, errata E6) — this file's own verdicts match captured output in-process (_has) or through the rc-aware wrapper (_grepx + marker); each cell carries its mutant (no knob)
  _mtc_nl='
'
  _mtc_h="line one${_mtc_nl}line two"
  _mtc_fn=$(sed -n '/^_has() {/,/^}/p' "$_self")
  _mtc_mut=$(printf '%s\n' "$_mtc_fn" | sed 's/\*"\$2"\*) return 0/*) return 0/')
  if _has "abc def" def && ! _has "abc def" xyz && _has "abc" "" && ! _has "" x && _has "$_mtc_h" "one${_mtc_nl}line" && ! _has "$_mtc_h" "two${_mtc_nl}line"; then
    if [ -n "$_mtc_fn" ] && [ "$_mtc_mut" != "$_mtc_fn" ] && ( eval "$_mtc_mut"; _has "abc def" xyz ); then echo "PASS: selftest — MTC1 _has answers present, absent, empty-needle and multi-line questions, and an always-true mutant of the real function text flips the absent question (the cell has teeth)"
    else echo "FAIL: selftest — MTC1 the always-true mutant of _has did not apply or did not flip the absent-needle question"; sfail=1; fi
  else echo "FAIL: selftest — MTC1 _has answered a present/absent/empty/multi-line question wrongly"; sfail=1; fi
  _mtc_want="y1${_mtc_nl}n1${_mtc_nl}y2${_mtc_nl}n2${_mtc_nl}y3${_mtc_nl}n3${_mtc_nl}y4${_mtc_nl}n4"
  for _mtc_sh in sh dash bash; do
    if ! command -v "$_mtc_sh" >/dev/null 2>&1; then echo "SKIP: selftest — MTC2[$_mtc_sh] the shell is absent here"; continue; fi
    _mtc_o=$("$_mtc_sh" -c "$_mtc_fn
_has 'x a\\b y' 'a\\b' && echo y1
_has 'x ab y' 'a\\b' || echo n1
_has 'x * y' '*' && echo y2
_has 'x ab y' '*' || echo n2
_has 'x ? y' '?' && echo y3
_has 'xy' '?' || echo n3
_has 'x [ y' '[' && echo y4
_has 'x a y' '[a]' || echo n4" 2>&1)
    if [ -n "$_mtc_fn" ] && [ "$_mtc_o" = "$_mtc_want" ]; then echo "PASS: selftest — MTC2[$_mtc_sh] _has treats a backslash and the glob characters * ? [ literally"
    else echo "FAIL: selftest — MTC2[$_mtc_sh] _has mishandled a backslash or glob needle (got: $_mtc_o)"; sfail=1; fi
  done
  mkdir -p "$WORK/mtc/bin2" "$WORK/mtc/bin3"
  printf '#!/bin/sh\nexit 2\n' > "$WORK/mtc/bin2/grep"; chmod +x "$WORK/mtc/bin2/grep"
  printf '#!/bin/sh\nkill -TERM $$\n' > "$WORK/mtc/bin3/grep"; chmod +x "$WORK/mtc/bin3/grep"
  _mtc_r=$( _unv_f="$WORK/mtc/m0"; _grepx abc -q b && echo a0 || echo a$?; _grepx abc -q z && echo b0 || echo b$? )
  if [ "$_mtc_r" = "a0${_mtc_nl}b1" ] && [ ! -s "$WORK/mtc/m0" ]; then echo "PASS: selftest — MTC3a _grepx passes grep's rc 0 and rc 1 through and marks nothing"
  else echo "FAIL: selftest — MTC3a _grepx altered grep's own answer (got: $_mtc_r)"; sfail=1; fi
  for _mtc_s in 2:bin2 143:bin3; do
    _mtc_rc=${_mtc_s%%:*}; _mtc_b=${_mtc_s#*:}
    if ( _unv_f="$WORK/mtc/m$_mtc_b"; PATH="$WORK/mtc/$_mtc_b:$PATH"; export PATH
         if _mtc_x=$(_grepx abc -q b 2>&1); then :; fi
         _has "$_mtc_x" "UNVERIFIED (grep rc=$_mtc_rc)" && [ -s "$_unv_f" ] && ! _unv_end >/dev/null ); then
      echo "PASS: selftest — MTC3[$_mtc_b] a grep that exits $_mtc_rc inside \$( ) prints UNVERIFIED (grep rc=$_mtc_rc), marks the run, and _unv_end reads non-zero"
    else echo "FAIL: selftest — MTC3[$_mtc_b] an unanswered grep (rc $_mtc_rc) was not marked or not read back by _unv_end"; sfail=1; fi
  done
  _mtc_gx=$(sed -n '/^_grepx() {/,/^}/p' "$_self")
  _mtc_gm=$(printf '%s\n' "$_mtc_gx" | sed '/>> "\$_unv_f"/d')
  if [ -n "$_mtc_gx" ] && [ "$_mtc_gm" != "$_mtc_gx" ] && ( _unv_f="$WORK/mtc/mm"; : > "$_unv_f"; PATH="$WORK/mtc/bin2:$PATH"; export PATH; eval "$_mtc_gm"
       if _mtc_x=$(_grepx abc -q b 2>&1); then :; fi
       _unv_end >/dev/null ); then echo "PASS: selftest — MTC3m with the marker write deleted from the real _grepx text (a sed), _unv_end reads clean, so MTC3's marker assertion has teeth"
  else echo "FAIL: selftest — MTC3m the marker-drop mutant of _grepx did not apply or still read non-zero: MTC3 pins nothing"; sfail=1; fi
  _mtc_ue=$(sed -n '/^_unv_end() {/,/^}/p' "$_self")
  _mtc_um=$(printf '%s\n' "$_mtc_ue" | sed 's/^  if \[ -z .*# UNVMISS$/  if false; then/')
  if [ -n "$_mtc_ue" ] && [ "$_mtc_um" != "$_mtc_ue" ] && ( _unv_f="$WORK/mtc/gone"; rm -f "$_unv_f"; ! _unv_end >/dev/null ) && ( _unv_f=""; ! _unv_end >/dev/null ) \
     && ( _unv_f="$WORK/mtc/gone"; rm -f "$_unv_f"; eval "$_mtc_um"; _unv_end >/dev/null ); then echo "PASS: selftest — MTC6 _unv_end reads RED on a missing or unnamed marker file, and the real text with its existence test off reads clean (the cell has teeth)"
  else echo "FAIL: selftest — MTC6 _unv_end did not red on a missing marker, or its mutant did not apply or still read non-zero"; sfail=1; fi
  _mtc_n=$(sed -n '/^  _unv_end || sfail=1$/p' "$_self" | wc -l | tr -d ' ')
  if [ "$_mtc_n" = 1 ]; then echo "PASS: selftest — MTC3e the verdict path reads the marker (the one _unv_end || sfail=1 line)"
  else echo "FAIL: selftest — MTC3e the file holds $_mtc_n marker-reading verdict lines, want exactly 1"; sfail=1; fi
  # MTC7 — st_lacks was false-green (a failing grep fell to its PASS arm); under a grep that always exits 2 it must still FAIL on a PRESENT needle and PASS on a real absence
  _mtc_r=$( PATH="$WORK/mtc/bin2:$PATH"; export PATH; sfail=0; st_lacks x "abc present" present >/dev/null; echo "$sfail"; sfail=0; st_lacks x "abc" present >/dev/null; echo "$sfail" )
  if [ "$_mtc_r" = "1${_mtc_nl}0" ]; then echo "PASS: selftest — MTC7 st_lacks FAILs a present needle and PASSes a real absence even when grep cannot run (the false-green is closed)"
  else echo "FAIL: selftest — MTC7 st_lacks answered '$_mtc_r' under a failing grep, want 1 then 0 (a spurious grep failure passed it)"; sfail=1; fi
  # H8-H12 (SWAS-592, design controls 8-11, errata E9-E11) — each face runs in a process group of its own and what it leaves behind is killed.
  #      Every mutant is a sed of THIS file into a throwaway copy (no knob); a sed that changes nothing is a FAIL, never a skip.
  for _k in leave hang; do st_repo "$st/fz$_k"; st_fix "$st/fz$_k/conformance/$_k-check.sh" "$_k"; st_commit "$st/fz$_k"; done
  # H8 (control 8) — a face that leaves a sleep behind: face (b)'s fixture reds if face (a)'s sleep is still alive, so a lane rc 0 proves the kill
  _hl=$WORK/hf8.left; : > "$_hl"
  rc=0; ( cd "$st/fzleave" && HF_LEFT=$_hl sh "$_self" conformance/leave-check.sh ) >/dev/null 2>&1 || rc=$?
  st_expect "H8 a face that leaves a sleep behind: face (b) finds no leftover of face (a), lane rc 0" 0 "$rc"
  st_gone "H8 every sleep the faces left is gone once the lane returns" "$_hl" 2
  st_reap "$_hl"
  sed -e '/# HFTERM$/s/^\( *\).*/\1if false; then/' -e '/# HFKILL$/s/^\( *\).*/\1:/' "$_self" > "$WORK/hf8m.sh"
  if cmp -s "$_self" "$WORK/hf8m.sh"; then echo "FAIL: selftest — H8m the kill-skipping mutant changed nothing (the HFTERM / HFKILL anchors are gone)"; sfail=1
  else
    : > "$_hl"; rc=0; ( cd "$st/fzleave" && HF_LEFT=$_hl sh "$WORK/hf8m.sh" conformance/leave-check.sh ) >/dev/null 2>&1 || rc=$?
    if [ "$rc" != 0 ] && st_alive "$_hl"; then echo "PASS: selftest — H8m with both kills skipped the lane reds (rc $rc) and a sleep survives, so H8 has teeth"
    else echo "FAIL: selftest — H8m the kill-skipping mutant still passed or left nothing alive (rc $rc)"; sfail=1; fi
    st_reap "$_hl"
  fi
  # H11a (control 11, E9) — the pgid gate refuses empty, non-numeric, leading-zero, 1, 0, the lane's own group and its parent's group
  _pg_fn=$(sed -n '/^hf_pgid_ok() {/,/^}/p' "$_self")
  _pg_own=$(ps -o pgid= -p "$$" | tr -d ' '); _pg_par=$(ps -o pgid= -p "$PPID" | tr -d ' ')
  _pg_mut=$(printf '%s\n' "$_pg_fn" | sed '/# HFPG$/s/^\( *\).*/\1:/')
  _pg_ask='_r=""; for _v in "" abc 1 0 012 "$_pg_own" "$_pg_par"; do if hf_pgid_ok "$_v"; then _r="${_r}A"; else _r="${_r}R"; fi; done; if hf_pgid_ok 987654; then _r="${_r}A"; else _r="${_r}R"; fi; echo "$_r"'
  _pg_got=$( eval "$_pg_fn"; eval "$_pg_ask" )
  if [ -n "$_pg_fn" ] && [ "$_pg_got" = RRRRRRRA ]; then echo "PASS: selftest — H11a hf_pgid_ok refuses empty, text, a leading zero, 1, 0, the lane's own group and its parent's group, and accepts another number"
  else echo "FAIL: selftest — H11a hf_pgid_ok answered '$_pg_got', want RRRRRRRA"; sfail=1; fi
  _pg_mgot=$( eval "$_pg_mut"; eval "$_pg_ask" )
  if [ -n "$_pg_fn" ] && [ "$_pg_mut" != "$_pg_fn" ] && [ "$_pg_mgot" != RRRRRRRA ]; then echo "PASS: selftest — H11am with the own-group refusals dropped hf_pgid_ok accepts the lane's own group ('$_pg_mgot'), so H11a has teeth"
  else echo "FAIL: selftest — H11am the gate-dropping mutant did not apply or still refused everything ('$_pg_mgot')"; sfail=1; fi
  # H11a2 / H11ap — the parent clause is pinned apart from the own-group clause: a ps stub gives the lane's own group 4242 and its parent's group 5252 (distinct), so each refusal is asked alone
  _pg_ask2='ps() { case "$*" in "-o pgid= -p $$") echo 4242 ;; *) echo 5252 ;; esac; }; _r=""; for _v in 4242 5252 6262; do if hf_pgid_ok "$_v"; then _r="${_r}A"; else _r="${_r}R"; fi; done; echo "$_r"'
  _pg_got=$( eval "$_pg_fn"; eval "$_pg_ask2" )
  if [ -n "$_pg_fn" ] && [ "$_pg_got" = RRA ]; then echo "PASS: selftest — H11a2 with distinct own and parent groups hf_pgid_ok refuses each and accepts a third (RRA)"
  else echo "FAIL: selftest — H11a2 hf_pgid_ok answered '$_pg_got' for own/parent/other, want RRA"; sfail=1; fi
  _pg_mut2=$(printf '%s\n' "$_pg_fn" | sed '/\[ -z "\$_hf_par" \]/s/^\( *\).*/\1:/')
  _pg_mgot=$( eval "$_pg_mut2"; eval "$_pg_ask2" )
  if [ -n "$_pg_fn" ] && [ "$_pg_mut2" != "$_pg_fn" ] && [ "$_pg_mgot" = RAA ]; then echo "PASS: selftest — H11ap with only the parent-group refusal dropped the parent's group is accepted (RAA), so the parent clause is pinned"
  else echo "FAIL: selftest — H11ap the parent-dropping mutant did not apply or answered '$_pg_mgot', want RAA"; sfail=1; fi
  # H11b (control 11, E9) — a wrapper that cannot make a separate group reads UNVERIFIED and signals nothing; the copy runs in a DISPOSABLE group beside a bystander sleep
  if [ -x /usr/bin/perl ]; then
    _by=$WORK/hf11.by; _hl=$WORK/hf11.left
    sed '/# HFGRP$/s/setpgrp(0,0) && //' "$_self" > "$WORK/hf11.sh"
    if cmp -s "$_self" "$WORK/hf11.sh"; then echo "FAIL: selftest — H11b the no-setpgrp copy changed nothing (the HFGRP anchor is gone)"; sfail=1
    else
      : > "$_hl"; st_dgrp "$WORK/hf11.out" "$st/fzleave" "$WORK/hf11.sh" "$_hl" "$_by"
      out=$(cat "$WORK/hf11.out")
      st_expect "H11b a wrapper that cannot make its own group: the lane reds" 1 "$_dg_rc"
      st_has "H11b the face reads UNVERIFIED (no separate process group)" "$out" 'UNVERIFIED (no separate process group)'
      if [ ! -s "$_hl" ]; then echo "PASS: selftest — H11b the face was never run"; else echo "FAIL: selftest — H11b the face ran although no group was made"; sfail=1; fi
      if st_alive "$_by"; then echo "PASS: selftest — H11b (structural liveness check, not the control-11 negative: that is H11a/H11am/H11ap) the bystander in the lane's own group was not signalled"; else echo "FAIL: selftest — H11b a process in the lane's own group was killed"; sfail=1; fi
      st_dgkill; st_reap "$_by"; st_reap "$_hl"
    fi
    sed '/# HFGRP$/s/(setpgrp(0,0) && getpgrp(0) == \$\$) or do { open(my \$f, ">", \$s); exit 125 }; //' "$_self" > "$WORK/hf11m.sh"
    if cmp -s "$_self" "$WORK/hf11m.sh"; then echo "FAIL: selftest — H11bm the assertion-dropping copy changed nothing (the HFGRP anchor is gone)"; sfail=1
    else
      : > "$_hl"; st_dgrp "$WORK/hf11m.out" "$st/fzleave" "$WORK/hf11m.sh" "$_hl" "$_by"
      out=$(cat "$WORK/hf11m.out")
      st_lacks "H11bm with setpgrp and the assertion dropped the lane no longer reads UNVERIFIED, so H11b has teeth" "$out" 'UNVERIFIED (no separate process group)'
      st_dgkill; st_reap "$_by"; st_reap "$_hl"
    fi
  else echo "SKIP: selftest — H11b/H11bm — no /usr/bin/perl here"; fi
  # H12 (E10) — TERM to a lane that waits on a hung face reaps the face's group and exits 130 (TERM, never INT: a background job starts with INT ignored)
  _hl=$WORK/hf12.left; : > "$_hl"
  ( cd "$st/fzhang" && HF_LEFT=$_hl && export HF_LEFT && exec sh "$_self" conformance/hang-check.sh ) >"$WORK/hf12.out" 2>&1 &
  _lp=$!; _i=0
  while [ "$_i" -lt 100 ] && [ "$(grep -c '' "$_hl")" -lt 3 ]; do sleep 0.1; _i=$((_i + 1)); done
  kill -s TERM "$_lp"; rc=0; wait "$_lp" || rc=$?
  st_expect "H12 a TERM to the lane exits 130" 130 "$rc"
  st_gone "H12 the hung face's whole group is gone once the lane has exited" "$_hl" 3
  st_reap "$_hl"
  sed "s/^trap 'hf_reap; /trap '/" "$_self" > "$WORK/hf12m.sh"
  if cmp -s "$_self" "$WORK/hf12m.sh"; then echo "FAIL: selftest — H12m the reap-less trap copy changed nothing"; sfail=1
  else
    : > "$_hl"
    ( cd "$st/fzhang" && HF_LEFT=$_hl && export HF_LEFT && exec sh "$WORK/hf12m.sh" conformance/hang-check.sh ) >"$WORK/hf12.out" 2>&1 &
    _lp=$!; _i=0
    while [ "$_i" -lt 100 ] && [ "$(grep -c '' "$_hl")" -lt 3 ]; do sleep 0.1; _i=$((_i + 1)); done
    kill -s TERM "$_lp"; rc=0; wait "$_lp" || rc=$?
    if st_alive "$_hl"; then echo "PASS: selftest — H12m without hf_reap in the trap the hung face survives the TERM, so H12 has teeth"
    else echo "FAIL: selftest — H12m the reap-less trap still left nothing alive (rc $rc)"; sfail=1; fi
    st_reap "$_hl"
  fi
  # H11c / H11d / H11cm (E11) — no perl: the faces run as before (no group, no reap, the face's own verdict stands) and ONE WARN names the consequence; not UNVERIFIED
  _warn='  WARN: perl is missing, so leftover processes are not reaped; reds under load may follow'
  sed 's|^HF_PERL=.*|HF_PERL=/nonexistent/perl|' "$_self" > "$WORK/hf11c.sh"
  if cmp -s "$_self" "$WORK/hf11c.sh"; then echo "FAIL: selftest — H11c the no-perl copy changed nothing (the HF_PERL line is gone)"; sfail=1
  else
    rc=0; ( cd "$st/ft" && sh "$WORK/hf11c.sh" conformance/hermetic-check.sh ) >"$WORK/hf11c.out" 2>&1 || rc=$?
    out=$(cat "$WORK/hf11c.out")
    st_expect "H11c no perl, a hermetic twin: both faces run as before, lane rc 0" 0 "$rc"
    st_count "H11c exactly one WARN line names the consequence" 1 "$WORK/hf11c.out" "$_warn"
    st_lacks "H11c no UNVERIFIED line (a missing perl is a warning, not a verdict)" "$out" 'UNVERIFIED'
    st_has "H11c both faces passed" "$out" 'PASS: face (b)'
    rc=0; ( cd "$st/fh" && sh "$WORK/hf11c.sh" conformance/fail1-check.sh ) >/dev/null 2>&1 || rc=$?
    st_expect "H11d no perl, a red fixture: the face's own verdict stands, lane rc 1" 1 "$rc"
    sed '/# HFWARN$/s/^\( *\).*/\1:/' "$WORK/hf11c.sh" > "$WORK/hf11cm.sh"
    if cmp -s "$WORK/hf11c.sh" "$WORK/hf11cm.sh"; then echo "FAIL: selftest — H11cm the WARN-dropping copy changed nothing (the HFWARN anchor is gone)"; sfail=1
    else
      ( cd "$st/ft" && sh "$WORK/hf11cm.sh" conformance/hermetic-check.sh ) >"$WORK/hf11cm.out" 2>&1 || :
      st_count "H11cm with the WARN dropped no WARN line is printed, so H11c has teeth" 0 "$WORK/hf11cm.out" "$_warn"
    fi
  fi
  # H11e (E11, R-M2) — with no perl the face runs in the FOREGROUND as before, so a SIGINT reaches it; a background job starts with INT ignored and would survive. The environment is probed first (a selftest started in the background ignores INT everywhere).
  st_repo "$st/fzintsig"; st_fix "$st/fzintsig/conformance/intsig-check.sh" intsig; st_commit "$st/fzintsig"
  # (the OUTER launcher, only, runs under a real perl that resets INT to default where perl exists, so a CI background job does not turn the cell into a permanent SKIP; the copy under test still has no perl)
  _probe=$(st_dflint sh -c 'kill -s INT $$; echo SURVIVED' 2>/dev/null) || :
  if [ -n "$_probe" ]; then echo "SKIP: selftest — H11e SIGINT is ignored in this environment and cannot be reset (no perl), so a foreground face cannot be told from a background one"
  else
    rc=0; out=$( cd "$st/fzintsig" && st_dflint sh "$WORK/hf11c.sh" conformance/intsig-check.sh 2>&1 ) || rc=$?
    if [ "$rc" != 0 ]; then echo "PASS: selftest — H11e with no perl a face that sends itself SIGINT dies of it (lane rc $rc), so the face ran in the foreground"
    else echo "FAIL: selftest — H11e with no perl the face survived its own SIGINT (lane rc 0): it ran as a background job"; sfail=1; fi
    st_has "H11e the lane output shows the face died of INT (rc 130), not merely that the lane exited non-zero" "$out" '(rc 130)'
  fi
  # H14 (NEW-M1) — a host with perl but no working ps: a face that leaves nothing behind needs no gate, so no UNVERIFIED and lane rc 0; a face that leaves a sleep behind is refused (fail closed) and the sleep is NOT signalled
  mkdir -p "$WORK/mtc/binps"; printf '#!/bin/sh\nexit 1\n' > "$WORK/mtc/binps/ps"; chmod +x "$WORK/mtc/binps/ps"
  rc=0; out=$( cd "$st/ft" && PATH="$WORK/mtc/binps:$PATH" sh "$_self" conformance/hermetic-check.sh 2>&1 ) || rc=$?
  st_expect "H14 no working ps, a face that leaves nothing behind: lane rc 0" 0 "$rc"
  st_lacks "H14 no UNVERIFIED line for it" "$out" 'UNVERIFIED'
  _hl=$WORK/hf14.left; : > "$_hl"
  rc=0; out=$( cd "$st/fzleave" && HF_LEFT=$_hl PATH="$WORK/mtc/binps:$PATH" sh "$_self" conformance/leave-check.sh 2>&1 ) || rc=$?
  st_has "H14 no working ps, a face that leaves a sleep behind: the signal is refused (fail closed)" "$out" 'refused to signal group'
  if st_alive "$_hl"; then echo "PASS: selftest — H14 the refused group was not signalled (a sleep is still alive)"; else echo "FAIL: selftest — H14 a group was signalled although the gate could not read the lane's own group"; sfail=1; fi
  st_reap "$_hl"
  # H13 (R-N1) — hf_fp: symbolic-ref exit 1 is a detached HEAD; any other exit is not an answer (UNREADABLE)
  _fp_fn=$(sed -n '/^hf_fp() {/,/^}/p' "$_self")
  _fp_real=$( eval "$_fp_fn"; hf_fp "$st/ft" | sed -n 2p )
  _fp_det=$( eval "$_fp_fn"; git() { if [ "$3" = symbolic-ref ]; then return 1; fi; command git "$@"; }; hf_fp "$st/ft" | sed -n 2p )
  _fp_unr=$( eval "$_fp_fn"; git() { if [ "$3" = symbolic-ref ]; then return 128; fi; command git "$@"; }; hf_fp "$st/ft" | sed -n 2p )
  case $_fp_real in refs/heads/*) _fp_ok=1 ;; *) _fp_ok=0 ;; esac
  if [ -n "$_fp_fn" ] && [ "$_fp_ok" = 1 ] && [ "$_fp_det" = detached ] && [ "$_fp_unr" = UNREADABLE ]; then echo "PASS: selftest — H13 hf_fp reads a branch, maps symbolic-ref exit 1 to detached and any other exit to UNREADABLE"
  else echo "FAIL: selftest — H13 hf_fp branch part: real '$_fp_real', exit 1 '$_fp_det', exit 128 '$_fp_unr'"; sfail=1; fi
  # H12d (S-LOW-4) — the TERM-to-the-lane cell again with dash as the LANE shell (the CI /bin/sh on Ubuntu)
  if command -v dash >/dev/null 2>&1; then
    _hl=$WORK/hf12d.left; : > "$_hl"
    ( cd "$st/fzhang" && HF_LEFT=$_hl && export HF_LEFT && exec dash "$_self" conformance/hang-check.sh ) >"$WORK/hf12d.out" 2>&1 &
    _lp=$!; _i=0
    while [ "$_i" -lt 100 ] && [ "$(grep -c '' "$_hl")" -lt 3 ]; do sleep 0.1; _i=$((_i + 1)); done
    kill -s TERM "$_lp"; rc=0; wait "$_lp" || rc=$?
    st_expect "H12d a TERM to a lane run by dash exits 130" 130 "$rc"
    st_gone "H12d the hung face's whole group is gone once the dash lane has exited" "$_hl" 3
    st_reap "$_hl"
  else echo "SKIP: selftest — H12d no dash here"; fi
  # H10 (control 10, item 7) — face (a) fingerprints the live tree before and after its window; a change is UNVERIFIED (non-zero), face (b) still runs
  for _k in commit edit touchstat; do
    st_repo "$st/fz$_k"; printf 'x\n' > "$st/fz$_k/tracked.txt"; st_fix "$st/fz$_k/conformance/$_k-check.sh" "$_k"; st_commit "$st/fz$_k"
  done
  rc=0; out=$( cd "$st/fzcommit" && sh "$_self" conformance/commit-check.sh 2>&1 ) || rc=$?
  st_expect "H10a a face that commits mid-window: the lane exits 1" 1 "$rc"
  st_has "H10a the change is named HEAD" "$out" 'UNVERIFIED (live tree changed during face (a): HEAD)'
  st_has "H10a face (b) still ran" "$out" 'PASS: face (b)'
  rc=0; out=$( cd "$st/fzedit" && sh "$_self" conformance/edit-check.sh 2>&1 ) || rc=$?
  st_expect "H10b a face that edits a tracked file: the lane exits 1" 1 "$rc"
  st_has "H10b the change is named the working tree" "$out" 'UNVERIFIED (live tree changed during face (a): working tree)'
  st_has "H10b face (b) still ran" "$out" 'PASS: face (b)'
  rc=0; out=$( cd "$st/fztouchstat" && sh "$_self" conformance/touchstat-check.sh 2>&1 ) || rc=$?
  st_expect "H10c a face that only runs git status (index stat data rewritten, nothing else): lane rc 0" 0 "$rc"
  st_lacks "H10c no UNVERIFIED line (the .git/index file is never hashed)" "$out" 'UNVERIFIED'
  sed '/# HFCMP$/s/^\( *\).*/\1_fchg=/' "$_self" > "$WORK/hf10m.sh"
  if cmp -s "$_self" "$WORK/hf10m.sh"; then echo "FAIL: selftest — H10m the compare-skipping copy changed nothing (the HFCMP anchor is gone)"; sfail=1
  else
    rc=0; out=$( cd "$st/fzcommit" && sh "$WORK/hf10m.sh" conformance/commit-check.sh 2>&1 ) || rc=$?
    if [ "$rc" = 0 ]; then echo "PASS: selftest — H10m with the before/after compare skipped the mid-window commit goes unseen (lane rc 0), so H10a has teeth"
    else echo "FAIL: selftest — H10m the compare-skipping copy still exited $rc"; sfail=1; fi
  fi

  # FL1-FL4 (SWAS-604) — a face with rc 0 whose output has a line STARTING with FAIL is a FAIL ("rc 0, but it printed a FAIL line"); a FAIL quoted mid-line or indented is not; a scan that cannot run is UNVERIFIED
  st_repo "$st/ffl"
  for _k in failrc0 failquote; do st_fix "$st/ffl/conformance/$_k-check.sh" "$_k"; done
  st_commit "$st/ffl"
  rc=0; out=$( cd "$st/ffl" && sh "$_self" conformance/failrc0-check.sh 2>&1 ) || rc=$?
  st_expect "FL1 a face with rc 0 that printed a FAIL line: the lane exits 1" 1 "$rc"
  st_has "FL1 face (a) names the cause" "$out" 'FAIL: face (a) stripped-env — conformance/failrc0-check.sh rc 0, but it printed a FAIL line'
  st_has "FL1 the face output is printed, so the reader sees the line" "$out" 'FAIL: planted stub'
  st_lacks "FL1 face (a) is not a PASS" "$out" 'PASS: face (a)'
  rc=0; out=$( cd "$st/ffl" && sh "$_self" conformance/failquote-check.sh 2>&1 ) || rc=$?
  st_expect "FL2 a FAIL quoted mid-line, or indented, is not a FAIL line: the lane exits 0" 0 "$rc"
  st_has "FL2 face (b) passed too" "$out" 'PASS: face (b)'
  st_fix "$st/ffl/conformance/failb-check.sh" failb; st_commit "$st/ffl"; : > "$st/ffl/fbmark"
  rc=0; out=$( cd "$st/ffl" && sh "$_self" conformance/failb-check.sh 2>&1 ) || rc=$?
  st_expect "FL3 a face (b) with rc 0 that printed a FAIL line: the lane exits 1" 1 "$rc"
  st_has "FL3 face (a) passed" "$out" 'PASS: face (a)'
  st_has "FL3 face (b) names the cause" "$out" 'FAIL: face (b) clone — conformance/failb-check.sh rc 0, but it printed a FAIL line'
  sed '/# HFFL$/s/^\( *\).*/\1_sf_r=1/' "$_self" > "$WORK/fl1m.sh"
  if cmp -s "$_self" "$WORK/fl1m.sh"; then echo "FAIL: selftest — FL1m the scan-removed copy changed nothing (the HFFL tag is gone)"; sfail=1
  else
    rc=0; ( cd "$st/ffl" && sh "$WORK/fl1m.sh" conformance/failrc0-check.sh ) >/dev/null 2>&1 || rc=$?
    st_expect "FL1m with the FAIL-line scan removed the same fixture passes (rc 0), so FL1 has teeth" 0 "$rc"
  fi
  mkdir -p "$WORK/fl/bin"
  printf '#!/bin/sh\nfor _a in "$@"; do\n  [ "$_a" != "^FAIL" ] || exit 2\ndone\nexec %s "$@"\n' "$(command -v grep)" > "$WORK/fl/bin/grep"; chmod +x "$WORK/fl/bin/grep"
  rc=0; out=$( cd "$st/ft" && PATH="$WORK/fl/bin:$PATH" sh "$_self" conformance/hermetic-check.sh 2>&1 ) || rc=$?
  st_expect "FL4 a FAIL-line scan that cannot run (grep rc 2) is not a PASS: the lane exits 1" 1 "$rc"
  st_has "FL4 face (a) reads UNVERIFIED" "$out" 'UNVERIFIED (face (a): the FAIL-line scan could not run'
  st_lacks "FL4 face (a) is not a PASS" "$out" 'PASS: face (a)'
  rc=0; out=$( cd "$st/fzcommit" && PATH="$WORK/fl/bin:$PATH" sh "$_self" conformance/commit-check.sh 2>&1 ) || rc=$?
  st_has "FL4m a moved tree is still reported when the scan cannot run" "$out" 'UNVERIFIED (live tree changed during face (a): HEAD)'
  sed '/# HFFLMV$/d' "$_self" > "$WORK/fl4mm.sh"
  if cmp -s "$_self" "$WORK/fl4mm.sh"; then echo "FAIL: selftest — FL4mm the moved-report-dropping copy changed nothing (the HFFLMV tag is gone)"; sfail=1
  else
    rc=0; out=$( cd "$st/fzcommit" && PATH="$WORK/fl/bin:$PATH" sh "$WORK/fl4mm.sh" conformance/commit-check.sh 2>&1 ) || rc=$?
    st_has "FL4mm the mutant run reached the scan-failed branch (it did not crash)" "$out" 'UNVERIFIED (face (a): the FAIL-line scan could not run: no verdict is claimed)'
    st_lacks "FL4mm with the moved-tree report dropped from the scan-failed branch it is not printed, so FL4m has teeth" "$out" 'UNVERIFIED (live tree changed during face (a): HEAD)'
  fi

  # C3-C5, C10 and C7 (SWAS-600; errata E3) - the crash cells run as one group into a file, the file is printed, and the same file is rescanned: a crash cell's own PASS output must hold no crash line
  _cq=$WORK/crash.cells
  crash_cells_h > "$_cq" 2>&1 || :
  cat "$_cq"
  _cqr=0; crash_line_in "$_cq" || _cqr=$?
  st_expect "C7 the crash cells' own printed output holds no crash line" 1 "$_cqr"
  _cqn=$(grep -c '^PASS: selftest' "$_cq" || :)
  if [ "$_cqn" -ge 20 ]; then echo "PASS: selftest — C7 the rescanned output is the real one ($_cqn PASS lines, at least 20)"
  else echo "FAIL: selftest — C7 the rescanned output holds only $_cqn PASS lines, want at least 20 (an empty capture would pass vacuously)"; sfail=1; fi
  # C7m - one crash cell edited (in a throwaway copy) to print its inner capture on a PASS: the same rescan must find the crash line
  sed -e '/# CQ10$/s/# CQ10$/; printf "%s\\n" "$out"   # CQ10/' "$_self" > "$WORK/cm.c7m.sh"
  if cmp -s "$_self" "$WORK/cm.c7m.sh"; then echo "FAIL: selftest — C7m the printing copy changed nothing (the CQ10 tag is gone)"; sfail=1
  else
    _cqf=$(sed -n '/^crash_cells_h() {/,/^}/p' "$WORK/cm.c7m.sh")
    ( eval "$_cqf"; crash_cells_h ) > "$WORK/crash.cells.m" 2>&1 || :
    _cqr=0; crash_line_in "$WORK/crash.cells.m" || _cqr=$?
    st_expect "C7m with one crash cell printing its inner capture the rescan finds a crash line, so C7 has teeth" 0 "$_cqr"
  fi

  _unv_end || sfail=1
  [ "$sfail" -eq 0 ] && { echo "selftest-hermetic --selftest: OK"; return 0; }
  echo "selftest-hermetic --selftest: FAIL"; return 1
}

# --- selftest-only helpers (BELOW selftest() on purpose: the non-vacuity sweep mutates only lines
#     BEFORE the marker; kill logic and fixture builders must sit in the protected oracle region) ---
st_repo() { # <dir> — an empty git repo (identity passed inline everywhere; hermetic by construction)
  mkdir -p "$1/conformance"
  ( cd "$1" && git init -q ) >/dev/null 2>&1
}
st_commit() { # <dir> — commit everything, inline identity
  ( cd "$1" && git add -A >/dev/null 2>&1 && git -c user.email=t@kit -c user.name=kit commit -q -m fixture --allow-empty ) >/dev/null 2>&1
}
st_script() { # <path> <kind: bare|inline|notes> — a fixture conformance script with a --selftest
  case $2 in
    bare)   printf '#!/bin/sh\ncase "${1:-}" in --selftest) d=$(mktemp -d); ( cd "$d" && git init -q && echo x > f && git add f && git commit -q -m s ) || { rm -rf "$d"; echo FAIL; exit 1; }; rm -rf "$d"; echo OK ;; esac\n' > "$1" ;;
    inline) printf '#!/bin/sh\ncase "${1:-}" in --selftest) d=$(mktemp -d); ( cd "$d" && git init -q && echo x > f && git add f && git -c user.email=t@k -c user.name=t commit -q -m s ) || { rm -rf "$d"; echo FAIL; exit 1; }; rm -rf "$d"; echo OK ;; esac\n' > "$1" ;;
    notes)  printf '#!/bin/sh\ncase "${1:-}" in --selftest) git rev-parse -q --verify refs/notes/amb >/dev/null || { echo "FAIL: notes ref missing"; exit 1; }; echo OK ;; esac\n' > "$1" ;;
  esac
}
st_has() { # <label> <output> <fixed-string> — the output carries the string
  if _has "$2" "$3"; then echo "PASS: selftest — $1"
  else echo "FAIL: selftest — $1 (missing: $3)"; sfail=1; fi
}
st_fix() { # <path> <kind: fail1|nofail|passshape|fail15|sentinel|probe*|sleep2> — a fixture whose --selftest prints a shaped output
  case $2 in
    fail1)     _b='echo "selftest FAIL: boom"; i=0; while [ $i -lt 40 ]; do echo "selftest PASS: leg $i"; i=$((i+1)); done; exit 1' ;;
    unv)       _b='echo "selftest UNVERIFIED (grep rc=2): grep -c ."; i=0; while [ $i -lt 40 ]; do echo "selftest PASS: leg $i"; i=$((i+1)); done; exit 1' ;;
    nofail)    _b='i=0; while [ $i -lt 40 ]; do echo "selftest PASS: leg $i"; i=$((i+1)); done; exit 1' ;;
    passshape) _b='echo "PASS: selftest — a non-zero adapter rc yields the exact FAIL sentence (rc -> FAIL)"; echo "selftest FAIL: expected PASS"; i=0; while [ $i -lt 40 ]; do echo "selftest PASS: leg $i"; i=$((i+1)); done; exit 1' ;;
    fail15)    _b='i=0; while [ $i -lt 15 ]; do echo "selftest FAIL: leg $i"; i=$((i+1)); done; i=0; while [ $i -lt 40 ]; do echo "selftest PASS: leg $i"; i=$((i+1)); done; exit 1' ;;
    probena)    _b='echo "renderer probe: agent-autonomy N-A"; echo OK' ;;
    probepass)  _b='echo "renderer probe: agent-autonomy PASS"; echo OK' ;;
    probefail)  _b='echo "renderer probe: agent-autonomy FAIL"; echo OK' ;;
    probeunv)   _b='echo "renderer probe: agent-autonomy UNVERIFIED"; echo OK' ;;
    probenone)  _b='echo OK' ;;
    probetwo)   _b='echo "renderer probe: agent-autonomy N-A"; echo "renderer probe: agent-autonomy PASS"; echo OK' ;;
    probealias) _b='echo "renderer probe: agent-autonomy-alias N-A"; echo OK' ;;
    probealias2) _b='echo "renderer probe: agent-autonomy N-A"; echo "renderer probe: agent-autonomy-alias PASS"; echo OK' ;;
    probered)   _b='echo "renderer probe: agent-autonomy N-A"; echo "selftest FAIL: boom"; exit 1' ;;
    sleep2)     _b='sleep 2; echo OK' ;;
    intsig)     _b='kill -s INT $$; echo SURVIVED' ;;
    leave)      _b='[ ! -s "$HF_LEFT" ] || while read -r p; do kill -s 0 "$p" 2>/dev/null && { echo "FAIL: a leftover of the previous face is alive ($p)"; exit 1; }; done < "$HF_LEFT"; sleep 120 & echo "$!" >> "$HF_LEFT"; echo OK' ;;
    commit)     _b='git -c user.email=t@k -c user.name=t commit -q --allow-empty -m mid; echo OK' ;;
    edit)       _b='echo x >> tracked.txt; echo OK' ;;
    touchstat)  _b='touch tracked.txt; git status >/dev/null 2>&1; echo OK' ;;
    hang)       _b='echo "$$" >> "$HF_LEFT"; sleep 120 & echo "$!" >> "$HF_LEFT"; sleep 120 & echo "$!" >> "$HF_LEFT"; wait' ;;
    failrc0)    _b='echo "PASS: selftest — leg 1"; echo "FAIL: planted stub"; echo OK' ;;
    failquote)  _b='echo "PASS: selftest — a gate said FAIL, as required"; echo "selftest FAIL: not at the line start"; echo "  FAIL: an indented relay"; echo OK' ;;
    failb)      _b='if [ ! -e fbmark ]; then echo "FAIL: planted in the clone"; fi; echo OK' ;;
    crash)      _b='if [ -e crashmark ]; then kill -s SEGV $$; fi; echo OK' ;;
    crashnest)  _b='if [ -e crashmark ]; then sh -c "kill -s SEGV \$\$"; fi; echo OK' ;;
    crashb)     _b='if [ ! -e crashmark ]; then kill -s SEGV $$; fi; echo OK' ;;
    sentinel)  _b='[ -n "${HERMETIC_ST_SENT:-}" ] || { echo "FAIL: no sentinel given"; exit 1; }
    [ "${TMPDIR:-}" != "$HERMETIC_ST_SENT" ] || { echo "FAIL: TMPDIR is still the outer sentinel"; exit 1; }
    d=$(mktemp -d "$TMPDIR/x.XXXXXX") || { echo "FAIL: no templated mktemp"; exit 1; }
    p=$(cd "$d" && pwd -P); t=$(cd "$TMPDIR" && pwd -P); rm -rf "$d"
    case "$p" in
      "$t"/*) echo OK ;;
      *) echo "FAIL: the templated mktemp did not land under TMPDIR"; exit 1 ;;
    esac' ;;
  esac
  printf '#!/bin/sh\ncase "${1:-}" in\n  --selftest)\n    %s ;;\nesac\n' "$_b" > "$1"
}
st_lacks() { # <label> <output> <fixed-string> — the output does NOT carry the string
  if _has "$2" "$3"; then echo "FAIL: selftest — $1 (unexpected: $3)"; sfail=1
  else echo "PASS: selftest — $1"; fi
}
st_count() { # <label> <want-n> <log-file> <fixed-line> — the log holds exactly <want-n> whole lines equal to <fixed-line>
  _cn=$(grep -c -x -F -e "$4" "$3" || :)
  if [ "$_cn" = "$2" ]; then echo "PASS: selftest — $1"
  else echo "FAIL: selftest — $1 (want $2 line(s) '$4', got $_cn)"; sfail=1; fi
}
st_cfcount() { # <file> — "<n> <lit> <ro> <loop> <adj>": non-comment lines naming the list token outside selftest(), the literal assignment, its readonly line, the one loop, readonly directly after the literal; the real file is "3 1 1 1 1"
  awk '/^selftest\(\) \{$/ { insf = 1 }
    { ln = $0; sub(/#.*/, "", ln) }
    !insf && ln ~ /CORE_FACE_TARGET[S]/ { n++ }
    !insf && ln ~ /^CORE_FACE_TARGET[S]=\047[^\047]*\047$/ { lit = NR; litn++ }
    !insf && ln ~ /^readonly CORE_FACE_TARGET[S]$/ { ro++; if (lit && NR == lit + 1) adj++ }
    !insf && ln ~ /^  for _e in \$CORE_FACE_TARGET[S]; do$/ { lp++ }
    insf && /^}$/ { insf = 0 }
    END { print n + 0, litn + 0, ro + 0, lp + 0, adj + 0 }' "$1"
}
st_cffix() { # <line>... — write the lines to a scratch file and count them as st_cfcount does
  printf '%s\n' "$@" > "$WORK/cf6m.sh"; st_cfcount "$WORK/cf6m.sh"
}
st_cfstub() { # <path> <kind: core|full|mention> — a fixture script that logs "<argv0> <args>" to $CF_LOG; `full` has no --selftest-core arm, `mention` only names it in an echo
  mkdir -p "$(dirname "$1")"
  case $2 in
    mention) printf '#!/bin/sh\ncase "${1:-}" in\n  --selftest) printf "%%s %%s\\n" "$0" "$*" >> "$CF_LOG"; echo "no --selftest-core arm here" ;;\nesac\n' > "$1" ;;
    core) printf '#!/bin/sh\ncase "${1:-}" in\n  --selftest|--selftest-core) printf "%%s %%s\\n" "$0" "$*" >> "$CF_LOG"; echo OK ;;\nesac\n' > "$1" ;;
    full) printf '#!/bin/sh\ncase "${1:-}" in\n  --selftest) printf "%%s %%s\\n" "$0" "$*" >> "$CF_LOG"; echo OK ;;\nesac\n' > "$1" ;;
  esac
}
st_expect() { # <label> <want-rc> <got-rc>
  if [ "$2" = "$3" ]; then echo "PASS: selftest — $1"
  else echo "FAIL: selftest — $1 (want rc $2, got $3)"; sfail=1; fi
}
# _has <haystack> <needle> — 0 iff the needle occurs in the haystack, literally (equal to grep -F for a needle with no newline). In-process: no fork, no signal, rc 0 or 1 only, so ! _has is safe (SWAS-577 errata E6).
_has() {
  case $1 in
    *"$2"*) return 0 ;;
  esac
  return 1
}
# _grepx <haystack> <grep-args...> — grep over a captured string, for the shapes case cannot answer (-i, -c, an extracted line). rc 0 and 1 are grep's own answer and pass through.
# Any other rc (an error, a spawn failure, a signal) is NOT an answer: print UNVERIFIED (grep rc=N) to stderr, append one line to the marker file $_unv_f (a $( ) subshell cannot lose a file), and return 2. The verdict reads the marker, never this return code.
_grepx() {
  _gx_h=$1; shift
  _gx_rc=0
  printf '%s\n' "$_gx_h" | grep "$@" || _gx_rc=$?
  case $_gx_rc in
    0|1) return "$_gx_rc" ;;
  esac
  printf 'selftest UNVERIFIED (grep rc=%s): grep %s\n' "$_gx_rc" "$*" >&2
  printf 'rc=%s grep %s\n' "$_gx_rc" "$*" >> "$_unv_f"
  return 2
}
# _unv_end — the final verdict's read of the marker: rc 1 (and one FAIL line naming the count) when any grep call could not answer, or when the marker file is missing.
_unv_end() {
  if [ -z "${_unv_f:-}" ] || [ ! -f "$_unv_f" ]; then   # UNVMISS
    echo "selftest FAIL: UNVERIFIED: the marker file is missing or unnamed, so an unanswered grep could not have been recorded"
    return 1
  fi
  [ -s "$_unv_f" ] || return 0
  _un_n=0
  while IFS= read -r _un_l || [ -n "$_un_l" ]; do _un_n=$((_un_n + 1)); done < "$_unv_f"
  echo "selftest FAIL: UNVERIFIED: $_un_n grep call(s) could not answer (rc 2 or more, or a signal), so the verdict is not a PASS"
  return 1
}
st_dflint() { # <argv…> — run the argv with SIGINT reset to its default where perl exists (a background job starts with INT ignored); plain otherwise
  if [ -x /usr/bin/perl ]; then /usr/bin/perl -e '$SIG{INT}="DEFAULT"; exec @ARGV' -- "$@"; else "$@"; fi
}
st_gone() { # <label> <pidfile> <min> — the file lists at least <min> pids (the non-vacuity floor) and none of them is alive
  _sg_n=0; _sg_a=0
  while IFS= read -r _sg_p; do
    case $_sg_p in ''|*[!0-9]*) continue ;; esac
    _sg_n=$((_sg_n + 1))
    if kill -s 0 "$_sg_p" 2>/dev/null; then _sg_a=$((_sg_a + 1)); fi
  done < "$2"
  if [ "$_sg_n" -ge "$3" ] && [ "$_sg_a" = 0 ]; then echo "PASS: selftest — $1"
  else echo "FAIL: selftest — $1 ($_sg_n pid(s) recorded, want at least $3; $_sg_a still alive)"; sfail=1; fi
}
st_alive() { # <pidfile> — 0 iff some recorded pid is alive
  while IFS= read -r _sa_p; do
    case $_sa_p in ''|*[!0-9]*) continue ;; esac
    if kill -s 0 "$_sa_p" 2>/dev/null; then return 0; fi
  done < "$1"
  return 1
}
st_reap() { # <pidfile> — KILL every pid a fixture recorded (digits only, greater than 1; never an empty or defaulted pid)
  while IFS= read -r _sr_p; do
    case $_sr_p in ''|*[!0-9]*) continue ;; esac
    [ "$_sr_p" -gt 1 ] || continue
    kill -s KILL "$_sr_p" 2>/dev/null || :
  done < "$1"
}
st_dgrp() { # <outfile> <repo> <lane-copy> <HF_LEFT file> <bystander pid file> — run a lane copy on leave-check.sh inside a DISPOSABLE process group (the same perl start) beside a bystander sleep; sets _dg_rc and _dg_gp
  printf 'sleep 120 & echo $! > "$1"\nexec sh "$2" "$3"\n' > "$WORK/dg-run.sh"
  ( cd "$2" && HF_LEFT=$4 && export HF_LEFT && exec /usr/bin/perl -e '$SIG{INT}=$SIG{QUIT}="DEFAULT"; setpgrp(0,0) or exit 125; exec {$ARGV[0]} @ARGV or exit 126' -- sh "$WORK/dg-run.sh" "$5" "$3" conformance/leave-check.sh ) >"$1" 2>&1 &
  _dg_gp=$!
  _dg_rc=0; wait "$_dg_gp" || _dg_rc=$?
}
st_dgkill() { # the disposable group made by st_dgrp (its id is the leader's pid, digits only)
  case ${_dg_gp-} in ''|*[!0-9]*) return 0 ;; esac
  [ "$_dg_gp" -gt 1 ] || return 0
  kill -s KILL -- "-$_dg_gp" 2>/dev/null || :
}
st_cmut() { # <name> <sed-expr> — SWAS-600: a throwaway copy of $_self with one tagged line rewritten (cmp -s guard: a sed that changed nothing is a FAIL); the copy's three crash functions land in $WORK/cm.<name>.fn
  sed -e "$2" "$_self" > "$WORK/cm.$1.sh"
  if cmp -s "$_self" "$WORK/cm.$1.sh"; then echo "FAIL: selftest — $1 the mutant copy changed nothing (its tag is gone)"; sfail=1; return 1; fi
  sed -n -e '/^crash_sig_of() {/,/^}/p' -e '/^crash_line_in() {/,/^}/p' -e '/^hf_crashed() {/,/^}/p' "$WORK/cm.$1.sh" > "$WORK/cm.$1.fn"
}
st_cscan() { # <fn-file> <data-file> — that copy's crash_line_in over the data file, in a subshell; prints its rc
  # shellcheck disable=SC1090  # sources a mutant copy's extracted crash functions (the path is built at run time)
  ( . "$1"; _sc_r=0; crash_line_in "$2" || _sc_r=$?; echo "$_sc_r" )
}
st_cbash() { # <fn-file> <data-file> — that copy's crash_line_in under bash (a failed redirect on an external command is rc 1 there and rc 2 under dash); prints its rc
  WORK=$WORK bash -c '. "$1"; _sc_r=0; crash_line_in "$2" || _sc_r=$?; echo "$_sc_r"' crash "$1" "$2" 2>/dev/null
}
# crash_cells_h — SWAS-600 controls 3, 4, 5 and 10, run as ONE group by selftest() so the group's own output can be rescanned for a crash line (control 7, errata E3). Every inner run is captured into a variable or a file and reaches this output only through a label; fixture crash lines are built with printf from parts.
crash_cells_h() {
  for _k in crash crashnest crashb; do
    st_repo "$st/fz$_k"; st_fix "$st/fz$_k/conformance/$_k-check.sh" "$_k"; st_commit "$st/fz$_k"; : > "$st/fz$_k/crashmark"
  done
  # C10 - a top-level crash is caught by the exit status; face (b) still runs; the crash is not a FAIL
  rc=0; out=$( cd "$st/fzcrash" && sh "$_self" conformance/crash-check.sh 2>&1 ) || rc=$?   # CQ10
  st_expect "C10 a face killed by SEGV: the lane exits 1" 1 "$rc"
  st_has "C10 face (a) reads UNVERIFIED by its exit status" "$out" 'UNVERIFIED (face (a) crashed: SEGV, rc 139)'
  st_has "C10 face (b) still ran" "$out" 'PASS: face (b)'
  st_lacks "C10 the crash is not read as a FAIL" "$out" 'FAIL: face (a)'
  # C10n - a nested crash (the face's own shell prints the line into the face's output), whatever the face's rc
  rc=0; out=$( cd "$st/fzcrashnest" && sh "$_self" conformance/crashnest-check.sh 2>&1 ) || rc=$?
  st_expect "C10n a face with a crashed child (face rc 0): the lane exits 1" 1 "$rc"
  st_has "C10n face (a) reads UNVERIFIED by the crash line" "$out" 'UNVERIFIED (face (a) crashed: Segmentation fault line)'
  st_has "C10n face (b) still ran" "$out" 'PASS: face (b)'
  # C10b - the same for face (b)
  rc=0; out=$( cd "$st/fzcrashb" && sh "$_self" conformance/crashb-check.sh 2>&1 ) || rc=$?
  st_expect "C10b a face (b) killed by SEGV: the lane exits 1" 1 "$rc"
  st_has "C10b face (b) reads UNVERIFIED by its exit status" "$out" 'UNVERIFIED (face (b) crashed: SEGV, rc 139)'
  st_has "C10b face (a) passed" "$out" 'PASS: face (a)'
  if st_cmut c10m '/# CRFRC$/s/^\( *\).*/\1if false; then/'; then
    rc=0; out=$( cd "$st/fzcrash" && sh "$WORK/cm.c10m.sh" conformance/crash-check.sh 2>&1 ) || rc=$?
    st_lacks "C10m with the exit-status rule dropped the top-level crash no longer reads UNVERIFIED by rc, so C10 has teeth" "$out" 'UNVERIFIED (face (a) crashed: SEGV, rc 139)'
  fi
  # C3/C4 - both forms are found; deliberate signals, prose and quoted crash lines are not crashes
  _qd=$WORK/cq.dash; _qb=$WORK/cq.bash; _qc=$WORK/cq.clean
  printf '%s %s\n' Segmentation 'fault: 11' > "$_qd"
  printf '%s: line %s: %s %s %s  %s\n' x.sh 4 123 Segmentation 'fault: 11' cmd > "$_qb"
  { printf '%s: %s\n' Terminated 15; printf '%s: %s\n' Killed 9
    printf '%s %s %s\n' 'the lane reads' Segmentation 'fault: 11 in prose'
    printf '`%s: line %s: %s %s %s  %s`\n' x.sh 4 123 Segmentation 'fault: 11' cmd
    printf '| %s | %s %s |\n' row Segmentation 'fault: 11'
    printf '  printf "x" # %s %s\n' Segmentation 'fault: 11'
    printf "'%s: line %s: %s %s %s  %s\n" x.sh 4 123 Segmentation 'fault: 11' cmd
    printf '"%s: line %s: %s %s %s  %s\n' x.sh 4 123 Segmentation 'fault: 11' cmd
    printf '| %s: line %s: %s %s %s |\n' x.sh 4 123 Segmentation 'fault: 11'
    printf '|%s: line %s: %s %s %s |\n' x.sh 4 123 Segmentation 'fault: 11'; } > "$_qc"
  _qr=0; crash_line_in "$_qd" || _qr=$?
  st_expect "C3 the dash form is found" 0 "$_qr"
  st_expect "C3 and its phrase is named" "Segmentation fault" "$CRASH_TXT"
  _qr=0; crash_line_in "$_qb" || _qr=$?
  st_expect "C3 the bash-parent form is found" 0 "$_qr"
  _qr=0; crash_line_in "$_qc" || _qr=$?
  st_expect "C4 Terminated, Killed, prose, a backticked line, table rows, lines led by a quote or a pipe, and a quoted source line are not crashes" 1 "$_qr"
  for _xc in 1 2 3; do
    if st_cmut "c4x$_xc" "/# CRX$_xc\$/s/^\\( *\\).*/\\1_cl_x$_xc=/"; then
      st_expect "C4x$_xc with prefix exclusion $_xc dropped a line led by it reads as a crash, so C4 has teeth" 0 "$(st_cscan "$WORK/cm.c4x$_xc.fn" "$_qc")"
    fi
  done
  # CR1 - a hit file that cannot be written is rc 2, never clean (under bash 3.2 the failed redirect alone reads rc 1)
  sed -n '/^crash_line_in() {/,/^}/p' "$_self" > "$WORK/cm.cr1.fn"
  rm -rf "$WORK/crash.hit"; mkdir "$WORK/crash.hit"
  st_expect "CR1 a hit file that cannot be written is rc 2, never clean" 2 "$(_sr=0; crash_line_in "$_qd" || _sr=$?; echo "$_sr")"
  if command -v bash >/dev/null 2>&1; then
    st_expect "CR1 and the same under bash" 2 "$(st_cbash "$WORK/cm.cr1.fn" "$_qd")"
    if st_cmut cr1m '/# CRHIT$/s/^\( *\).*/\1:/'; then
      st_expect "CR1m without the hit-file test a failed redirect reads clean under bash, so CR1 has teeth" 1 "$(st_cbash "$WORK/cm.cr1m.fn" "$_qd")"
    fi
  else echo "SKIP: selftest — CR1 under bash: no bash here, the bash-only half was NOT exercised"; fi
  rmdir "$WORK/crash.hit"
  if st_cmut c3m '/# CRBASH$/s/^\( *\).*/\1_cl_b=NOMATCHXQ/'; then
    st_expect "C3m with the bash form dropped the bash-parent line goes unseen, so C3 has teeth" 1 "$(st_cscan "$WORK/cm.c3m.fn" "$_qb")"
  fi
  if st_cmut c4a '/# CRSET$/s/(Segmentation fault|/(Terminated|Segmentation fault|/'; then
    st_expect "C4a with TERM added to the set a deliberate Terminated line reads as a crash, so C4 has teeth" 0 "$(st_cscan "$WORK/cm.c4a.fn" "$_qc")"
  fi
  if st_cmut c4b '/# CRPRE$/s/^\( *\).*/\1_cl_pre=.+/'; then
    st_expect "C4b with the bash-form prefix loosened to .+ a quoted line reads as a crash, so C4 has teeth" 0 "$(st_cscan "$WORK/cm.c4b.fn" "$_qc")"
  fi
  # C5 - the scan fails closed: a grep that exits 2 only for the crash set is rc 2, never clean
  _qs=$WORK/cq.stub; mkdir -p "$_qs"; _qg=$(command -v grep)
  printf '#!/bin/sh\nfor _a in "$@"; do\n  case $_a in\n    *Segmentation*) exit 2 ;;\n  esac\ndone\nexec %s "$@"\n' "$_qg" > "$_qs/grep"; chmod +x "$_qs/grep"
  _qr=$( PATH="$_qs:$PATH"; _sr=0; grep -q zzzzz "$_qd" || _sr=$?; echo "$_sr" )
  st_expect "C5 liveness: the stub passes any other pattern through (rc 1, not 2)" 1 "$_qr"
  _qr=$( PATH="$_qs:$PATH"; _sr=0; crash_line_in "$_qd" || _sr=$?; echo "$_sr" )
  st_expect "C5 a crash scan whose grep cannot run is rc 2, never clean" 2 "$_qr"
  out=$( PATH="$_qs:$PATH"; _o=$_qd; _rv=0; _hr=0; hf_crashed 'face (a)' 0 || _hr=$?; echo "hf_crashed rc $_hr, _rv $_rv" )
  st_has "C5 a face whose scan cannot run reads UNVERIFIED, not PASS" "$out" 'UNVERIFIED (face (a): crash scan could not run: no verdict is claimed)'
  st_has "C5 and the face's verdict state is set" "$out" 'hf_crashed rc 0, _rv 1'
  if st_cmut c5m '/# CRFAIL$/s/^\( *\)\*.*/\1*) return 1 ;;/'; then
    _qr=$( PATH="$_qs:$PATH"; st_cscan "$WORK/cm.c5m.fn" "$_qd" )
    st_expect "C5m with the scan's failure read as clean a forced failure reads clean (rc 1), so C5 has teeth" 1 "$_qr"
  fi
}

# ---------------------------------------------------------------------------- dispatch
case "${1:-}" in
  --selftest)
    selftest; _fin $? ;;
  --touched)
    cd "$(git rev-parse --show-toplevel)" 2>/dev/null || { echo "selftest-hermetic: not a git repo" >&2; exit 2; }
    # Reviewer 3 (2026-08-07): validate BEFORE the empty-target N/A exit — an exclusions-only PR
    # (touched∩roster empty) must not slip a reasonless entry past the lane it widens.
    validate_exclusions || exit 1
    _set=$(touched_set) || exit 1
    if [ -z "$_set" ]; then
      echo "selftest-hermetic: N/A — no touched selftest-capable script (changed-set ∩ roster is empty vs $BASE)"
      _fin 0
    fi
    # shellcheck disable=SC2086
    run_lane $_set; _fin $? ;;
  --all)
    cd "$(git rev-parse --show-toplevel)" 2>/dev/null || { echo "selftest-hermetic: not a git repo" >&2; exit 2; }
    validate_exclusions || exit 1
    _set=$(roster)
    if [ -z "$_set" ]; then echo "selftest-hermetic: N/A — the roster is empty on this tree"; _fin 0; fi
    # shellcheck disable=SC2086
    run_lane $_set; _fin $? ;;
  "")
    echo "usage: selftest-hermetic.sh [--touched | --all | <path>... | --selftest]" >&2; exit 2 ;;
  *)
    run_lane "$@"; _fin $? ;;
esac
