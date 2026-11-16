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
#   --touched --face a|b --output-file F
#                     SWAS-864, CI only: the --touched set under ONE face, with a v1 record written to F (atomically). One face alone
#                     is never a pass: it prints PARTIAL, and only --join over both faces gives a verdict. Exactly this argument order;
#                     anything else that names --face, --output-file or --join is rc 2.
#   --join <rec> <rec>  grades the two face records: rc 0 only for exactly one record per face, both on this checkout's HEAD tree and
#                     the same base, with the same targets and selectors, every target PASS or EXCLUDED (or both N/A). Else rc 1 and the cause.
#   --groups <path>   SWAS-871: a SPLIT target (SPLIT_FACE_TARGETS, kit trees only) prints its committed group names, one per line, parsed STATICALLY from `git show HEAD:<path>` (nothing of the target runs);
#                     any other path prints nothing (rc 0); a split target with a missing, malformed, empty or duplicated ST_GROUPS table is rc 1.
#   --group <name> <path>  one group of a split target under both faces (`<path> --selftest-group <name>`); rc 2 for a name its table does not have. A face record (--touched --face) holds one
#                     `sel=--selftest-group:<name>` line per group for a split target, and --join checks those lines against the committed table (JN20). Each of the two flags is rc 2 outside its exact grammar.
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
#       --face: rc 0 = that face only (PARTIAL); --join gives the verdict.
set -eu

TAB=$(printf '\t')
NL='
'
_faces='a b'   # the faces run_faces runs; only the --face arm narrows it
_hg_g=''       # SWAS-871: the group a run of one split target is limited to (set by run_group and fl_groups); empty runs the whole --selftest
_rf_fin=0      # run_faces sets 1 once every wanted face ran without a FAIL (so a non-zero return then is UNVERIFIED)
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
    # SWAS-864: no pipe, so no EPIPE when the first match ends the read (a grep -q at the end of a pipe made sed print Broken pipe)
    [ -n "$(sed -n 's/#.*//; /--selftest/{p;q;}' "$_f")" ] || continue   # BPROS
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

# SPLIT_FACE_TARGETS (SWAS-871) — repo-relative paths whose --selftest is a table of committed groups (ST_GROUPS below that script's selftest marker), ON A KIT TREE ONLY. The local lane and H2 run each group as a unit under both faces
# (`<path> --selftest-group <g>`); the target passes only when every group passed on both faces, and the full --selftest is graded by CI job conformance-selftests-4 (ci-gates.sh check_split_face_graders pins that, and an empty list reds there).
# Matched whole-path and exact (never a pattern or a basename). Inert on an adopter tree (no kit marker). Every reader goes through split_face_listed, the one loop below.
SPLIT_FACE_TARGETS='conformance/prepush-lane.sh'
readonly SPLIT_FACE_TARGETS

# split_face_listed <repo-top> <repo-relative-path> — 0 iff the repo top is a kit tree and the path is a listed entry, whole and exact (set -f: an entry is never a glob).
split_face_listed() {
  [ -f "$1/docs/ROADMAP-KIT.md" ] || [ -f "$1/.github/workflows/golden-path.yml" ] || return 1   # SFKIT
  _sf=1; set -f
  for _e in $SPLIT_FACE_TARGETS; do
    if [ "$2" = "$_e" ]; then _sf=0; break; fi
  done
  set +f; return $_sf
}

# hf_groups <repo-relative-path> — the group names of a split target, one per line, parsed STATICALLY from the bytes face (b) grades (git show HEAD:<path>): nothing of the target is executed, and the ST_GROUPS line is read in its closed charset.
# rc 0 with nothing printed: not a split target (no kit marker, or not on the list). rc 1, with the cause on stderr: a split target whose table is missing, malformed, empty or duplicated. Used by --groups, --group, fl_target and the join.
hf_groups() {
  _gp=$1
  _gtop=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  split_face_listed "$_gtop" "$_gp" || return 0
  git show "HEAD:$_gp" > "$WORK/grp.src" 2>/dev/null || { echo "FAIL: group table: HEAD has no $_gp (face (b) grades HEAD)" >&2; return 1; }   # HGSHOW
  _gc=$(sed -n "/^ST_GROUPS='/p" "$WORK/grp.src" | grep -c '' || :)
  [ "$_gc" = 1 ] || { echo "FAIL: group table: $_gp must carry exactly one column-0 ST_GROUPS=' line (found $_gc)" >&2; return 1; }
  _gm=$(sed -n "/^ST_GROUPS='[a-z0-9 ]*'\$/p" "$WORK/grp.src" | grep -c '' || :)
  [ "$_gm" = 1 ] || { echo "FAIL: group table: the ST_GROUPS line of $_gp is outside its closed charset [a-z0-9 ] (one single-quoted line)" >&2; return 1; }
  # a shadow assignment (indented, double-quoted, readonly or export, eval'd) would make this parse and the runtime table disagree: any second non-comment assignment of ST_GROUPS or of one ST_G_<g> is refused
  _gdup=$(sed 's/#.*//' "$WORK/grp.src" | sed -n -E 's/^[[:space:]]*(readonly[[:space:]]+|export[[:space:]]+)?(ST_GROUPS|ST_G_[a-z0-9]+)=.*/\2/p' | LC_ALL=C sort | uniq -d)
  _gev=$(sed 's/#.*//' "$WORK/grp.src" | grep -c -E 'eval.*ST_G(ROUPS|_[a-z0-9]+)=' || :)
  { [ -z "$_gdup" ] && [ "$_gev" = 0 ]; } || { echo "FAIL: group table: $_gp assigns ST_GROUPS or an ST_G_<g> line more than once, or through eval (a shadow table)" >&2; return 1; }   # HGSHADOW
  _gv=$(sed -n "s/^ST_GROUPS='\\([a-z0-9 ]*\\)'\$/\\1/p" "$WORK/grp.src")
  set -f; set -- $_gv; set +f
  [ "$#" -gt 0 ] || { echo "FAIL: group table: ST_GROUPS of $_gp names no group" >&2; return 1; }
  _gseen=" "
  for _gn in "$@"; do
    case $_gseen in *" $_gn "*) echo "FAIL: group table: group $_gn is listed twice in $_gp" >&2; return 1 ;; esac
    _gseen="$_gseen$_gn "
  done
  printf '%s\n' "$@"
}
# hf_group_known <group> <path> — rc 0 iff <group> is one of the path's committed groups, whole.
hf_group_known() {
  case $1 in ''|*[!a-z0-9]*) return 1 ;; esac
  _hgk=$(hf_groups "$2") || return 1
  [ -n "$_hgk" ] || return 1
  case "$NL$_hgk$NL" in *"$NL$1$NL"*) return 0 ;; esac
  return 1
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
  cd "$_top" && hf_exec "$_rel" "$_sel" ${_sel2:+"$_sel2"}   # HFSEL2
}
hf_body_b() { cd "$_c" && TMPDIR=$_tb && export TMPDIR && hf_exec "$_rel" "$_sel" ${_sel2:+"$_sel2"}; }
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
  _tgt=$1; _rf_fin=0
  _top=$(_repo_of "$_tgt") || { echo "FAIL: $_tgt is not inside a git repo (face (b) needs one)"; return 1; }
  # pwd -P: git rev-parse --show-toplevel answers the PHYSICAL path, so the target's dir must be
  # canonicalized the same way or the prefix-strip fails on a symlinked tmpdir (macOS /var -> /private/var).
  _abs=$(CDPATH='' cd "$(dirname "$_tgt")" && pwd -P)/$(basename "$_tgt")
  _rel=${_abs#"$_top"/}
  _o="$WORK/face.out"
  _sel=--selftest; _sel2=''; _tag=''
  if core_face_listed "$_top" "$_rel"; then
    # SWAS-460: on a kit tree a listed target runs its mutant-free core only; a core arm that is absent reds, never passes vacuously
    _cs_pat='s/#.*//; /(^|\|)[[:space:]]*--selftest-core[[:space:]]*[|)]/{p;q;}'
    if [ -z "$(sed -n -E "$_cs_pat" "$_top/$_rel")" ]; then
      echo "FAIL: $_rel is core-only (the core-face list) but has no --selftest-core arm — refusing to pass vacuously"
      return 1
    fi
    _core=$((_core + 1)); _sel=--selftest-core; _tag=' [--selftest-core]'
    echo "CORE-ONLY: $_rel — both faces run --selftest-core; the full mutant --selftest is graded by CI job $(basename "$_rel" .sh), not here"
  fi
  # SWAS-871: one group of a split target (run_group / fl_groups set _hg_g): both faces run `<path> --selftest-group <g>`
  if [ -n "$_hg_g" ]; then _sel=--selftest-group; _sel2=$_hg_g; _tag=" [--selftest-group $_hg_g]"; fi

  _rv=0; hf_mode
  case " $_faces " in *" a "*) hf_face_a || return 1 ;; esac   # FACEA
  case " $_faces " in *" b "*) hf_face_b || return 1 ;; esac   # FACEB
  _rf_fin=1
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

# run_group <group> <path> — one group of a split target under both faces (SWAS-871): the TARGET line names the group, and the verdict lines are run_lane's. The caller has checked the group against the committed table (hf_group_known).
run_group() {
  validate_exclusions || return 1
  [ -f "$2" ] || { echo "FAIL: target not found: $2"; return 1; }
  _fail=0; _ran=0; _core=0
  if ! excluded "$2"; then
    _ran=1; _hg_g=$1
    echo "TARGET: $2 group $1 (both faces)"
    run_faces "$2" || _fail=1
    _hg_g=''
  fi
  if [ "$_fail" != 0 ]; then
    echo "selftest-hermetic: FAIL — a targeted --selftest-group is not hermetic (face + output above)."
    return 1
  fi
  echo "selftest-hermetic: OK ($_ran target(s) passed both faces, $_core of them --selftest-core only (CORE-ONLY above))"
  return 0
}

# usage_text — the usage, with the E1 sentence: one face alone is never a pass.
usage_text() {
  echo "usage: selftest-hermetic.sh [--touched | --all | <path>... | --selftest]"
  echo "       selftest-hermetic.sh --groups <path>   |   --group <name> <path>   (a split target's committed groups; one group under both faces)"
  echo "       selftest-hermetic.sh --touched --face <a|b> --output-file <F>   |   --join <record> <record>"
  echo "  one face alone is never a pass: it prints PARTIAL, and only --join over both faces gives a verdict"   # E1SENT
}

# new_flag_in <arg>... — rc 0 when an argument is one of the five flags --face --output-file --join --group --groups (they are refused, rc 2, outside their exact grammar).
new_flag_in() {
  for _nf in "$@"; do
    case $_nf in --face|--output-file|--join|--group|--groups) return 0 ;; esac
  done
  return 1
}

# face_grammar <argv...> — rc 0 only for exactly: --touched --face <a|b> --output-file <F> (sets _fl_face and _fl_out).
face_grammar() {
  [ "$#" = 5 ] || return 1
  [ "$1" = --touched ] && [ "$2" = --face ] && [ "$4" = --output-file ] || return 1
  case $3 in a|b) : ;; *) return 1 ;; esac
  [ -n "$5" ] || return 1
  _fl_face=$3; _fl_out=$5
}

# fl_target <path> — one target under the face in $_faces: print its lines and append its verdict line(s) to the record body ($_fl_body).
# EXCLUDED and not-found targets carry sel=- (nothing was run, so no selector applies). A split target (SWAS-871) is one body line per committed group; one whose table cannot be read is one `sel=- verdict=FAIL` line and nothing runs.
fl_target() {
  if [ ! -f "$1" ]; then
    echo "FAIL: target not found: $1"; _fl_bad=1
    printf 'target=%s sel=- verdict=FAIL\n' "$1" >> "$_fl_body"; _fl_cnt=$((_fl_cnt + 1)); return 0
  fi
  if excluded "$1"; then
    printf 'target=%s sel=- verdict=EXCLUDED\n' "$1" >> "$_fl_body"; _fl_cnt=$((_fl_cnt + 1)); return 0
  fi
  _fg=$(hf_groups "$1") || { echo "FAIL: $1 is a split target but its group table cannot be read (the cause is above); nothing ran"; _fl_bad=1; printf 'target=%s sel=- verdict=FAIL\n' "$1" >> "$_fl_body"; _fl_cnt=$((_fl_cnt + 1)); return 0; }   # FLGFAIL
  if [ -n "$_fg" ]; then fl_groups "$1" "$_fg"; return 0; fi
  echo "TARGET: $1 (face $_fl_face only)"
  _sel=--selftest; _fv=PASS
  if run_faces "$1"; then :
  elif [ "$_rf_fin" = 1 ]; then _fv=UNVERIFIED; _fl_bad=1
  else _fv=FAIL; _fl_bad=1; fi
  printf 'target=%s sel=%s verdict=%s\n' "$1" "$_sel" "$_fv" >> "$_fl_body"; _fl_cnt=$((_fl_cnt + 1))
}
# fl_groups <path> <groups> — a split target under the face in $_faces: each committed group runs alone and writes its own body line, so a red names the group. Every group runs, whatever an earlier one did.
fl_groups() {
  _fl_p=$1; set -f; set -- $2; set +f
  for _fl_g in "$@"; do
    echo "TARGET: $_fl_p group $_fl_g (face $_fl_face only)"
    _hg_g=$_fl_g; _fv=PASS
    if run_faces "$_fl_p"; then :
    elif [ "$_rf_fin" = 1 ]; then _fv=UNVERIFIED; _fl_bad=1
    else _fv=FAIL; _fl_bad=1; fi
    _hg_g=''
    printf 'target=%s sel=--selftest-group:%s verdict=%s\n' "$_fl_p" "$_fl_g" "$_fv" >> "$_fl_body"; _fl_cnt=$((_fl_cnt + 1))   # FLGRP
  done
}

# fl_commit — the record, atomically: a mktemp file beside F (an unpredictable name, so a planted link cannot be followed), then mv.
# F must not be a directory or a symlink (refused, rc 1, no record), and after the mv F must be a regular file. A failure removes the temp file.
fl_commit() {
  _fc_dir=$(dirname "$_fl_out")
  [ ! -d "$_fl_out" ] || { echo "FAIL: the record cannot be written: $_fl_out (it is a directory)"; return 1; }   # FM11
  [ ! -L "$_fl_out" ] || { echo "FAIL: the record cannot be written: $_fl_out (it is a symlink)"; return 1; }   # FM12
  _fc_tmp=$(mktemp "$_fc_dir/.h2rec.XXXXXX" 2>/dev/null) || { echo "FAIL: the record cannot be written: $_fl_out (no temp file can be made beside it)"; return 1; }
  if cp "$_fl_rec" "$_fc_tmp" 2>/dev/null && mv "$_fc_tmp" "$_fl_out" 2>/dev/null && [ -f "$_fl_out" ] && [ ! -L "$_fl_out" ]; then return 0; fi
  rm -f "$_fc_tmp"
  [ ! -d "$_fl_out" ] || rm -f "$_fl_out/${_fc_tmp##*/}" 2>/dev/null   # F turned into a directory after the check: the mv put the temp inside it
  echo "FAIL: the record cannot be written: $_fl_out (no partial file is left behind)"
  return 1
}

# face_lane [path...] — run the face in $_faces over each path and write the record. rc 0 only when every path is PASS or EXCLUDED (or the set is N/A) and the record is written.
# The last line says PARTIAL: one face alone is never a lane verdict, and this path never prints "selftest-hermetic: OK".
face_lane() {
  _fl_tree=$(git rev-parse --verify --quiet 'HEAD^{tree}' 2>/dev/null) || _fl_tree=''
  _fl_rec="$WORK/face.rec"; _fl_body="$WORK/face.body"; _fl_bad=0; _core=0; _fl_cnt=0; : > "$_fl_body"
  if [ "$#" = 0 ]; then
    printf 'verdict=N/A\n' >> "$_fl_body"
    echo "selftest-hermetic: N/A - no touched selftest-capable script (changed-set and roster do not meet vs $BASE)"
  fi
  for _ft in "$@"; do fl_target "$_ft"; done
  # the header counts BODY lines (a split target is one per group), so it is written after the body is known
  # a writer-side count: a target's own process could append to the body file, so the header never counts the file's lines (J)
  _fl_n=$_fl_cnt   # FLN
  printf 'v1 face=%s tree=%s base=%s targets=%s\n' "$_fl_face" "$_fl_tree" "$_fbase" "$_fl_n" > "$_fl_rec"
  cat "$_fl_body" >> "$_fl_rec"
  if [ "$_fl_bad" != 0 ]; then echo "selftest-hermetic: FAIL - a targeted --selftest is not hermetic on face ($_fl_face) (face + output above)."; fi
  fl_commit || _fl_bad=1
  echo "selftest-hermetic: PARTIAL - face ($_fl_face) only; not a lane verdict (graded by --join)"   # FMPART
  return "$_fl_bad"
}

# face_touched — the --touched --face arm after its grammar passed: no record on an underivable base or an unreasoned exclusion (rc 1; the join then reds on the missing record).
face_touched() {
  case $_fl_out in /*) : ;; *) _fl_out="$PWD/$_fl_out" ;; esac
  cd "$(git rev-parse --show-toplevel)" 2>/dev/null || { echo "selftest-hermetic: not a git repo" >&2; exit 2; }
  validate_exclusions || exit 1
  _set=$(touched_set) || exit 1   # FM10
  _fbase=$(git merge-base HEAD "$BASE" 2>/dev/null) || { echo "FAIL: no merge-base between HEAD and '$BASE' - no record is written"; exit 1; }   # FM10b
  _faces=$_fl_face
  # shellcheck disable=SC2086
  face_lane $_set
}

# join_records <rec>... — rc 0 only when there are exactly two records, one per face, each a well-formed v1 record on this checkout's HEAD tree
# with the same base, the same targets and selectors, every target PASS or EXCLUDED (or both N/A). Else rc 1 and the first cause. Each check is one
# tagged line (# JNn) so the selftest can delete it and watch its cause go unnamed.
_jn_bad() { echo "selftest-hermetic: join FAIL - $1"; return 1; }
jn_exist() {
  for _jq in "$@"; do
    [ -f "$_jq" ] || { _jn_bad "no such record: $_jq (an unexpanded glob means zero records)"; return 1; }
  done
  return 0
}
# jn_head — _jh is the first line of a record: set _jf _jt _jb _jc from it, or name why it is not a v1 header.
jn_head() {
  case ${_jh%% *} in
    v1) : ;;
    v[0-9]*) _jn_bad "unknown record version '${_jh%% *}' (this join reads v1)"; return 1 ;;   # JN14
  esac
  case $_jh in
    "v1 face="[ab]" tree="?*" base="?*" targets="[0-9]*) : ;;
    *) _jn_bad "malformed header: $_jh"; return 1 ;;   # JN13
  esac
  _jf=${_jh#v1 face=}; _jf=${_jf%% *}
  _jt=${_jh#* tree=}; _jt=${_jt%% *}
  _jb=${_jh#* base=}; _jb=${_jb%% *}
  _jc=${_jh#* targets=}
}
# jn_line <line> — one body line of a record: N/A, or target=<path> sel=<sel> verdict=<v> (PASS or EXCLUDED; FAIL, UNVERIFIED and anything else red).
jn_line() {
  case $1 in
    "verdict=N/A") _jna=1; return 0 ;;
    "target="*" sel="*" verdict="*) : ;;
    *) _jn_bad "malformed line: $1"; return 1 ;;   # JN19
  esac
  _jv=${1##* verdict=}; _jkey=${1% verdict=*}; _jpth=${_jkey#target=}; _jpth=${_jpth% sel=*}
  case $_jv in
    PASS|EXCLUDED) : ;;
    FAIL) _jn_bad "a target FAILED on face ($_jf): $_jpth"; return 1 ;;   # JN10
    UNVERIFIED) _jn_bad "a target UNVERIFIED on face ($_jf): $_jpth"; return 1 ;;   # JN11
    *) _jn_bad "unknown verdict '$_jv' (only PASS or EXCLUDED pass): $1"; return 1 ;;   # JN15
  esac
  _jsel=${_jkey##* sel=}
  _jgok=0   # SWAS-871: a group selector is --selftest-group:<name>, the name in [a-z0-9]+
  case $_jsel in --selftest-group:*) case ${_jsel#--selftest-group:} in ''|*[!a-z0-9]*) : ;; *) if split_face_listed "$_jtop" "$_jpth"; then _jgok=1; fi ;; esac ;; esac   # JN18G
  case "$_jsel:$_jv:$_jgok" in --selftest:PASS:0|--selftest-core:PASS:0|-:EXCLUDED:0|--selftest-group:?*:PASS:1) : ;; *) _jn_bad "bad selector '$_jsel' for verdict $_jv: $1"; return 1 ;; esac   # JN18
  # a split-listed path is keyed by path and selector (one line per group); any other path by path alone
  if split_face_listed "$_jtop" "$_jpth"; then _jdk="$_jpth $_jsel"; _jdl=$_jd; else _jdk=$_jpth; _jdl=$_jp; fi
  case "$NL$_jdl" in *"$NL$_jdk$NL"*) _jn_bad "target listed twice on face ($_jf): $_jpth"; return 1 ;; esac   # JN8
  _jp="$_jp$_jpth$NL"; _jl="$_jl$_jkey$NL"; _jd="$_jd$_jdk$NL"; _jk=$((_jk + 1))
}
# jn_group_one <path> — JN20 for one split-listed path of the record in hand: when it has group lines, they are exactly the groups its committed table names (parsed statically from git show HEAD:<path>; the join runs nothing of the target),
# and no whole --selftest line and no sel=- line sits beside them. A path with no group line is not judged here (an EXCLUDED or not-found split target keeps its one sel=- line).
jn_group_one() {
  split_face_listed "$_jtop" "$1" || return 0
  _jsl=$(printf '%s' "$_jl" | awk -v p="$1" 'index($0, "target=" p " sel=") == 1 { print substr($0, length("target=" p " sel=") + 1) }')
  _jgc=$(printf '%s\n' "$_jsl" | grep -c '^--selftest-group:' || :)
  [ "$_jgc" != 0 ] || return 0
  _jnw=$(printf '%s\n' "$_jsl" | grep -c -x -F -e '--selftest' -e '--selftest-core' || :)
  [ "$_jnw" = 0 ] || { _jn_bad "a whole --selftest line beside group lines for $1 on face ($_jf)"; return 1; }   # JN20c
  _jnd=$(printf '%s\n' "$_jsl" | grep -c -x -F -e '-' || :)
  [ "$_jnd" = 0 ] || { _jn_bad "a sel=- line beside group lines for $1 on face ($_jf)"; return 1; }   # JN20d
  _jw=$(hf_groups "$1") || { _jn_bad "the group table of $1 cannot be read (the cause is above), so its group lines cannot be graded"; return 1; }
  printf '%s\n' "$_jw" | LC_ALL=C sort -u > "$WORK/jn20.want"
  printf '%s\n' "$_jsl" | sed -n 's/^--selftest-group://p' | LC_ALL=C sort -u > "$WORK/jn20.got"
  _jx=$(LC_ALL=C comm -13 "$WORK/jn20.want" "$WORK/jn20.got" | tr '\n' ' ' | sed 's/ $//')
  [ -z "$_jx" ] || { _jn_bad "$1 on face ($_jf) names a group the table does not have: $_jx"; return 1; }   # JN20b
  _jm=$(LC_ALL=C comm -23 "$WORK/jn20.want" "$WORK/jn20.got" | tr '\n' ' ' | sed 's/ $//')
  [ -z "$_jm" ] || { _jn_bad "$1 on face ($_jf) is missing group $_jm that its table names"; return 1; }   # JN20a
  return 0
}
# jn_groups — JN20 over every distinct path of the record in hand.
jn_groups() {
  _jqs=$(printf '%s' "$_jp" | LC_ALL=C sort -u); _jgr=0
  set -f
  for _jq in $_jqs; do
    jn_group_one "$_jq" || _jgr=1
    [ "$_jgr" = 0 ] || break
  done
  set +f
  return "$_jgr"
}
# jn_load <file> — read one record into _jf _jt _jb _jp (target paths) _jl (path and selector lines) _jna (N/A) or name why it is no record.
jn_load() {
  _jf=''; _jt=''; _jb=''; _jc=''; _jp=''; _jl=''; _jd=''; _jna=0; _jk=0; _jh=''; _ji=0
  _jtop=$(git rev-parse --show-toplevel 2>/dev/null) || _jtop=''
  IFS= read -r _jh < "$1" || :
  jn_head || return 1
  while IFS= read -r _jr || [ -n "$_jr" ]; do
    _ji=$((_ji + 1))
    [ "$_ji" -gt 1 ] || continue
    jn_line "$_jr" || return 1
  done < "$1"
  [ "$_jc" = "$_jk" ] || { _jn_bad "count mismatch: the header says targets=$_jc but the body has $_jk target line(s) ($1)"; return 1; }   # JN16
  case "$_jna:$_jk" in 1:0) : ;; 0:0) _jn_bad "inconsistent record: neither a target nor verdict=N/A ($1)"; return 1 ;; 0:*) : ;; *) _jn_bad "inconsistent record: verdict=N/A beside target lines ($1)"; return 1 ;; esac   # JN17
  jn_groups || return 1   # SWAS-871: JN20, the group lines of a split target against its committed table
  return 0
}
join_records() {
  _jtree=$(git rev-parse --verify --quiet 'HEAD^{tree}' 2>/dev/null) || { _jn_bad "cannot read this checkout's HEAD tree (not a git repo?)"; return 1; }
  jn_exist "$@" || return 1   # JN2
  [ "$#" -ge 2 ] || { _jn_bad "fewer than two records (got $#): a face is missing"; return 1; }   # JN1
  [ "$#" -le 2 ] || { _jn_bad "more than two records (got $#)"; return 1; }   # JN3
  jn_load "$1" || return 1
  _jf1=$_jf; _jt1=$_jt; _jb1=$_jb; _jp1=$_jp; _jl1=$_jl; _jna1=$_jna
  jn_load "${2-}" || return 1
  _jf2=$_jf; _jt2=$_jt; _jb2=$_jb; _jp2=$_jp; _jl2=$_jl; _jna2=$_jna
  case "$_jf1$_jf2" in ab|ba) : ;; *) _jn_bad "the two records are not one record per face (got $_jf1 and $_jf2)"; return 1 ;; esac   # JN4
  [ "$_jt1" = "$_jtree" ] && [ "$_jt2" = "$_jtree" ] || { _jn_bad "a record tree is not the HEAD tree of this checkout ($_jt1, $_jt2 vs $_jtree)"; return 1; }   # JN5
  [ "$_jb1" = "$_jb2" ] || { _jn_bad "the two records have different bases ($_jb1, $_jb2)"; return 1; }   # JN6
  [ "$_jna1" = "$_jna2" ] || { _jn_bad "one record is N/A and the other is not"; return 1; }   # JN12
  [ "$_jp1" = "$_jp2" ] || { _jn_bad "the two records have different target lists"; return 1; }   # JN7
  [ "$_jl1" = "$_jl2" ] || { _jn_bad "the two records have different selectors for the same targets"; return 1; }   # JN9
  echo "selftest-hermetic: join OK - faces a and b graded the same tree and targets, every target PASS or EXCLUDED (or both N/A)"
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

  # BP1 (SWAS-864, design section 5) — roster() over a large file whose first line names --selftest, with SIGPIPE ignored (as on the CI runner), prints nothing on stderr: the sed|grep -q pipe is gone. BP1m restores the pipe in a copy: GNU sed then prints Broken pipe.
  mkdir -p "$st/bp/conformance"
  { printf 'case "${1:-}" in --selftest) : ;; esac\n'; awk 'BEGIN { for (i = 0; i < 20000; i++) print "filler line " i " padding padding padding padding" }'; } > "$st/bp/conformance/big.sh"
  rc=0; ( cd "$st/bp" && trap '' PIPE && roster ) > "$WORK/bp.out" 2> "$WORK/bp.err" || rc=$?
  st_expect "BP1 roster over a large file with SIGPIPE ignored: rc 0" 0 "$rc"
  st_has "BP1 the file whose first line names --selftest is listed" "$(cat "$WORK/bp.out")" 'conformance/big.sh'
  if [ ! -s "$WORK/bp.err" ]; then echo "PASS: selftest — BP1 roster wrote nothing to stderr (no Broken pipe)"
  else echo "FAIL: selftest — BP1 roster wrote to stderr: $(cat "$WORK/bp.err")"; sfail=1; fi
  if st_cmut bp1m '/# BPROS$/s,^.*$,    sed "s/#.*//" "$_f" | grep -q -- "--selftest" || continue,'; then
    _bp_fn=$(sed -n '/^roster() {/,/^}/p' "$WORK/cm.bp1m.sh")
    _bp_v=$(sed --version 2>&1) || _bp_v=''
    if _has "$_bp_v" 'GNU sed'; then
      ( cd "$st/bp" && trap '' PIPE && eval "$_bp_fn" && roster ) > /dev/null 2> "$WORK/bp.errm" || :
      st_has "BP1m with the pipe restored GNU sed prints Broken pipe, so BP1 has teeth" "$(cat "$WORK/bp.errm")" 'Broken pipe'
    else echo "SKIP: selftest — BP1m the sed here is not GNU sed: the Broken pipe message is GNU's, so the pipe-restored half was NOT exercised"; fi
  fi

  # FM-u1..FM-u7 and E1 (SWAS-864, design section 3 face mode + errata E1) — the exact grammar is --touched --face a|b --output-file F; every other use of the three new flags is rc 2 with the usage text, and the usage text says plainly that one face alone is never a pass
  st_repo "$st/jn"; st_commit "$st/jn"
  st_fmu FM-u1 --face a --touched --output-file "$WORK/u.rec"
  st_fmu FM-u2 --touched --face c --output-file "$WORK/u.rec"
  st_fmu FM-u3 --touched --face a
  st_fmu FM-u4 --output-file "$WORK/u.rec" --touched --face a
  st_fmu FM-u5 --all --face a
  st_fmu FM-u6 conformance/x.sh --face a
  st_fmu FM-u7 --touched --face a --output-file "$WORK/u.rec" extra
  if [ ! -e "$WORK/u.rec" ]; then echo "PASS: selftest — FM-u no refused call left a record"; else echo "FAIL: selftest — FM-u a refused call left a record"; sfail=1; fi
  _fm_sent='one face alone is never a pass: it prints PARTIAL, and only --join over both faces gives a verdict'
  _su_o=$( cd "$st/jn" && sh "$_self" 2>&1 ) || :
  st_has "E1 the usage text carries the one-face-alone sentence" "$_su_o" "$_fm_sent"
  if st_cmut e1m '/# E1SENT$/d'; then
    _su_o=$( cd "$st/jn" && sh "$WORK/cm.e1m.sh" 2>&1 ) || :
    st_lacks "E1m with the sentence dropped the usage text no longer carries it, so E1 has teeth" "$_su_o" "$_fm_sent"
  fi

  # FM1-FM2, FM8, FM9 (design section 3 face mode, AC3, AC4) — one face over a one-target fixture: rc 0, the record binds face, tree, base and the target, only that face runs, and the last line says PARTIAL (never a verdict, never OK)
  st_fmrepo "$st/fma" ok
  _fm_t=$(git -C "$st/fma" rev-parse 'HEAD^{tree}'); _fm_b=$(git -C "$st/fma" rev-parse refs/remotes/origin/main)
  for _fm_x in a b; do
    case $_fm_x in a) _fm_n=1; _fm_o=b ;; *) _fm_n=2; _fm_o=a ;; esac
    rc=0; out=$( cd "$st/fma" && sh "$_self" --touched --face "$_fm_x" --output-file "$WORK/fm.$_fm_x.rec" 2>&1 ) || rc=$?
    st_expect "FM$_fm_n face ($_fm_x) over a one-target fixture: rc 0" 0 "$rc"
    st_expect "FM$_fm_n the record header binds face, tree, base and one target" "v1 face=$_fm_x tree=$_fm_t base=$_fm_b targets=1" "$(sed -n 1p "$WORK/fm.$_fm_x.rec")"
    st_expect "FM$_fm_n the target line is PASS with its selector" 'target=conformance/hermetic-check.sh sel=--selftest verdict=PASS' "$(sed -n 2p "$WORK/fm.$_fm_x.rec")"
    st_has "FM$_fm_n face ($_fm_x) ran and passed" "$out" "PASS: face ($_fm_x)"
    st_has "FM$_fm_n the face line ends (<n> s) battery: <state>" "$out" ' s) battery: '
    st_lacks "FM$_fm_n the other face ($_fm_o) did not run" "$out" "face ($_fm_o)"
    st_expect "FM$_fm_n the last line is PARTIAL, not a verdict" "selftest-hermetic: PARTIAL - face ($_fm_x) only; not a lane verdict (graded by --join)" "${out##*"$NL"}"
    st_lacks "FM8 face ($_fm_x) never prints selftest-hermetic: OK" "$out" 'selftest-hermetic: OK'
  done
  if st_cmut fm9m '/# FACEB$/s/\*" b "\*)/*)/'; then
    out=$( cd "$st/fma" && sh "$WORK/cm.fm9m.sh" --touched --face a --output-file "$WORK/fm.9m.rec" 2>&1 ) || :
    st_has "FM9m with the face filter dropped face a also runs face (b), so FM1's other-face check has teeth" "$out" 'PASS: face (b)'
  fi
  # FM3, FM4 — a FAIL target and an UNVERIFIED target give rc 1 and their verdict in the record (the FL4 grep stub makes face (a)'s FAIL-line scan unable to run)
  st_fmrepo "$st/fmf" fail
  rc=0; out=$( cd "$st/fmf" && sh "$_self" --touched --face a --output-file "$WORK/fm.f.rec" 2>&1 ) || rc=$?
  st_expect "FM3 a FAIL fixture: rc 1" 1 "$rc"
  st_expect "FM3 the record says verdict=FAIL" 'target=conformance/fail1-check.sh sel=--selftest verdict=FAIL' "$(sed -n 2p "$WORK/fm.f.rec")"
  st_lacks "FM8 a FAIL face run never prints selftest-hermetic: OK" "$out" 'selftest-hermetic: OK'
  rc=0; out=$( cd "$st/fma" && PATH="$WORK/fl/bin:$PATH" sh "$_self" --touched --face a --output-file "$WORK/fm.u.rec" 2>&1 ) || rc=$?
  st_expect "FM4 an UNVERIFIED fixture: rc 1" 1 "$rc"
  st_expect "FM4 the record says verdict=UNVERIFIED" 'target=conformance/hermetic-check.sh sel=--selftest verdict=UNVERIFIED' "$(sed -n 2p "$WORK/fm.u.rec")"
  # FM5 — an excluded target is EXCLUDED in the record, rc 0
  st_fmrepo "$st/fmx" ok
  printf 'hermetic-check.sh\tfixture: excluded to prove the disposition\n' > "$st/fmx/conformance/hermetic-exclusions.txt"
  rc=0; out=$( cd "$st/fmx" && sh "$_self" --touched --face a --output-file "$WORK/fm.x.rec" 2>&1 ) || rc=$?
  st_expect "FM5 an excluded target: rc 0" 0 "$rc"
  st_expect "FM5 the record says verdict=EXCLUDED" 'target=conformance/hermetic-check.sh sel=- verdict=EXCLUDED' "$(sed -n 2p "$WORK/fm.x.rec")"
  # FM6 — push-shaped: the base ref is HEAD, so the touched set is empty and the SCRIPT writes the N/A record (the YAML never forges one)
  st_repo "$st/fmp"; st_commit "$st/fmp"
  ( cd "$st/fmp" && git update-ref refs/remotes/origin/main HEAD ) >/dev/null 2>&1
  _fm_pt=$(git -C "$st/fmp" rev-parse 'HEAD^{tree}'); _fm_pb=$(git -C "$st/fmp" rev-parse HEAD)
  rc=0; out=$( cd "$st/fmp" && HERMETIC_BASE=refs/remotes/origin/main sh "$_self" --touched --face a --output-file "$WORK/fm.p.rec" 2>&1 ) || rc=$?
  st_expect "FM6 push-shaped (base ref = HEAD): rc 0" 0 "$rc"
  st_expect "FM6 the script wrote the N/A record" "v1 face=a tree=$_fm_pt base=$_fm_pb targets=0${NL}verdict=N/A" "$(cat "$WORK/fm.p.rec")"
  # FM7 — a record that cannot be written is rc 1 and leaves no F and no F.tmp.* (the empty set keeps this cheap: no face runs)
  rc=0; out=$( cd "$st/fmp" && HERMETIC_BASE=refs/remotes/origin/main sh "$_self" --touched --face a --output-file "$WORK/nodir/x.rec" 2>&1 ) || rc=$?
  st_expect "FM7 a record in a directory that does not exist: rc 1" 1 "$rc"
  st_has "FM7 the failure names the record" "$out" 'the record cannot be written'
  mkdir -p "$WORK/ro"; chmod 555 "$WORK/ro"
  if ( : > "$WORK/ro/probe" ) 2>/dev/null; then rm -f "$WORK/ro/probe"; echo "SKIP: selftest — FM7b this user can write into a read-only directory (root?), so the read-only half was NOT exercised"
  else
    rc=0; out=$( cd "$st/fmp" && HERMETIC_BASE=refs/remotes/origin/main sh "$_self" --touched --face a --output-file "$WORK/ro/x.rec" 2>&1 ) || rc=$?
    st_expect "FM7b a record in a read-only directory: rc 1" 1 "$rc"
    st_expect "FM7b no F and no F.tmp.* is left behind" "" "$(ls -A "$WORK/ro")"
  fi
  chmod 755 "$WORK/ro"
  # FM11, FM12 (security read, L2) — F that is an existing directory or a symlink is refused (rc 1, FAIL line); the mutants drop the guard: a record lands inside the directory, a symlink F is replaced and rc 0
  mkdir -p "$WORK/dirf"
  rc=0; out=$( cd "$st/fmp" && HERMETIC_BASE=refs/remotes/origin/main sh "$_self" --touched --face a --output-file "$WORK/dirf" 2>&1 ) || rc=$?
  st_expect "FM11 F is an existing directory: rc 1" 1 "$rc"
  st_has "FM11 the failure says it is a directory" "$out" 'it is a directory'
  st_expect "FM11 nothing was written inside the directory" "" "$(ls -A "$WORK/dirf")"
  if st_cmut fm11m '/# FM11$/d'; then
    rc=0; out=$( cd "$st/fmp" && HERMETIC_BASE=refs/remotes/origin/main sh "$WORK/cm.fm11m.sh" --touched --face a --output-file "$WORK/dirf" 2>&1 ) || rc=$?
    st_expect "FM11m with the directory guard dropped the post-mv check still reds (rc 1)" 1 "$rc"
    st_lacks "FM11m with the directory guard dropped the run no longer says it is a directory (it falls through to the post-mv failure), so FM11 has teeth" "$out" 'it is a directory'
    st_has "FM11m the mutant reached the post-mv failure" "$out" 'no partial file is left behind'
    st_expect "FM11m the post-mv cleanup left nothing inside the directory" "" "$(ls -A "$WORK/dirf")"
  fi
  printf 'keep\n' > "$WORK/victim"; ln -s "$WORK/victim" "$WORK/lnk.rec"
  rc=0; out=$( cd "$st/fmp" && HERMETIC_BASE=refs/remotes/origin/main sh "$_self" --touched --face a --output-file "$WORK/lnk.rec" 2>&1 ) || rc=$?
  st_expect "FM12 F is a symlink: rc 1" 1 "$rc"
  st_has "FM12 the failure says it is a symlink" "$out" 'it is a symlink'
  st_expect "FM12 the link target is untouched" "keep" "$(cat "$WORK/victim")"
  if [ -L "$WORK/lnk.rec" ]; then echo "PASS: selftest — FM12 the symlink is still a symlink"; else echo "FAIL: selftest — FM12 the symlink was replaced"; sfail=1; fi
  if st_cmut fm12m '/# FM12$/d'; then
    rc=0; ( cd "$st/fmp" && HERMETIC_BASE=refs/remotes/origin/main sh "$WORK/cm.fm12m.sh" --touched --face a --output-file "$WORK/lnk.rec" ) >/dev/null 2>&1 || rc=$?
    st_expect "FM12m with the symlink guard dropped a symlink F is accepted (rc 0), so FM12 has teeth" 0 "$rc"
  fi
  # FM8m — a face path that printed OK would red FM8's checks
  if st_cmut fm8m '/# FMPART$/s/selftest-hermetic: PARTIAL/selftest-hermetic: OK/'; then
    out=$( cd "$st/fmp" && HERMETIC_BASE=refs/remotes/origin/main sh "$WORK/cm.fm8m.sh" --touched --face a --output-file "$WORK/fm.8m.rec" 2>&1 ) || :
    st_has "FM8m with the PARTIAL line turned into OK the face path prints it, so FM8 has teeth" "$out" 'selftest-hermetic: OK'
  fi
  # FM10 (conductor ruling Q4) — no base: rc 1 and NO record (never an N/A record that binds nothing); FM10m drops the guard and a record appears
  st_repo "$st/fmn"; st_script "$st/fmn/conformance/hermetic-check.sh" inline; st_commit "$st/fmn"
  rc=0; out=$( cd "$st/fmn" && sh "$_self" --touched --face a --output-file "$WORK/fm.n.rec" 2>&1 ) || rc=$?
  st_expect "FM10 an underivable base: rc 1" 1 "$rc"
  if [ ! -e "$WORK/fm.n.rec" ]; then echo "PASS: selftest — FM10 no record was written for an underivable base"; else echo "FAIL: selftest — FM10 a record was written for an underivable base"; sfail=1; fi
  # FM10c — the merge-base guard (FM10b) is a second line of defence: with ONLY the touched_set guard dropped it still reds with no record; FM10m drops both
  if st_cmut fm10c '/# FM10$/s/|| exit 1/|| :/'; then
    rc=0; out=$( cd "$st/fmn" && sh "$WORK/cm.fm10c.sh" --touched --face a --output-file "$WORK/fm.nc.rec" 2>&1 ) || rc=$?
    st_expect "FM10c a failed merge-base in face mode (touched_set guard dropped): rc 1" 1 "$rc"
    st_has "FM10c the merge-base guard names itself" "$out" 'no merge-base between HEAD and'
    if [ ! -e "$WORK/fm.nc.rec" ]; then echo "PASS: selftest — FM10c no record was written when the merge-base failed"; else echo "FAIL: selftest — FM10c a record was written when the merge-base failed"; sfail=1; fi
  fi
  if st_cmut fm10m '/# FM10$/s/|| exit 1/|| :/;/# FM10b$/s/exit 1; }/:; }/'; then
    rc=0; ( cd "$st/fmn" && sh "$WORK/cm.fm10m.sh" --touched --face a --output-file "$WORK/fm.nm.rec" ) >/dev/null 2>&1 || rc=$?
    if [ -e "$WORK/fm.nm.rec" ]; then echo "PASS: selftest — FM10m with the base guard dropped a record is written for an underivable base, so FM10 has teeth"
    else echo "FAIL: selftest — FM10m the guard-dropped copy still wrote no record (rc $rc)"; sfail=1; fi
  fi
  st_fmrepo "$st/fmr" ok
  printf 'anything.sh\n' > "$st/fmr/conformance/hermetic-exclusions.txt"
  rc=0; ( cd "$st/fmr" && sh "$_self" --touched --face a --output-file "$WORK/fm.r.rec" ) >/dev/null 2>&1 || rc=$?
  st_expect "FM10e a reasonless exclusion: rc 1" 1 "$rc"
  if [ ! -e "$WORK/fm.r.rec" ]; then echo "PASS: selftest — FM10e no record was written for a reasonless exclusion"; else echo "FAIL: selftest — FM10e a record was written for a reasonless exclusion"; sfail=1; fi

  # JN0-JN14 (design section 3 join, AC2) — the join is green for two agreeing records and reds, naming the cause, for each way a face can be missing or disagree; each cell has a mutant (the tagged check deleted) that no longer names the cause
  mkdir -p "$WORK/jn"
  _jn_t=$(git -C "$st/jn" rev-parse 'HEAD^{tree}')
  _jn_p1='target=conformance/a.sh sel=--selftest verdict=PASS'
  _jn_p2='target=conformance/b.sh sel=- verdict=EXCLUDED'
  st_jrec "$WORK/jn/a.rec" a "$_jn_t" base1 2 "$_jn_p1" "$_jn_p2"
  st_jrec "$WORK/jn/b.rec" b "$_jn_t" base1 2 "$_jn_p1" "$_jn_p2"
  rc=0; out=$( cd "$st/jn" && sh "$_self" --join "$WORK/jn/a.rec" "$WORK/jn/b.rec" 2>&1 ) || rc=$?
  st_expect "JN0 two agreeing PASS/EXCLUDED records: rc 0" 0 "$rc"
  st_has "JN0 the join says OK" "$out" 'join OK'
  st_jrec "$WORK/jn/na.rec" a "$_jn_t" base1 0 'verdict=N/A'
  st_jrec "$WORK/jn/nb.rec" b "$_jn_t" base1 0 'verdict=N/A'
  rc=0; out=$( cd "$st/jn" && sh "$_self" --join "$WORK/jn/nb.rec" "$WORK/jn/na.rec" 2>&1 ) || rc=$?
  st_expect "JN0 two N/A records (either order): rc 0" 0 "$rc"
  rc=0; out=$( cd "$st/fma" && sh "$_self" --join "$WORK/fm.a.rec" "$WORK/fm.b.rec" 2>&1 ) || rc=$?
  st_expect "JN0 the two records FM1 and FM2 really wrote join green (writer and reader agree)" 0 "$rc"
  st_jn JN1 JN1 'fewer than two records' "$WORK/jn/a.rec"
  st_jn JN2 JN2 'no such record' "$WORK/nosuch/*.rec"
  st_jn JN3 JN3 'more than two records' "$WORK/jn/a.rec" "$WORK/jn/b.rec" "$WORK/jn/b.rec"
  st_jrec "$WORK/jn/aa.rec" a "$_jn_t" base1 2 "$_jn_p1" "$_jn_p2"
  st_jn JN4 JN4 'not one record per face' "$WORK/jn/a.rec" "$WORK/jn/aa.rec"
  st_jrec "$WORK/jn/t1.rec" a badtree base1 2 "$_jn_p1" "$_jn_p2"
  st_jrec "$WORK/jn/t2.rec" b badtree base1 2 "$_jn_p1" "$_jn_p2"
  st_jn JN5 JN5 'is not the HEAD tree' "$WORK/jn/t1.rec" "$WORK/jn/t2.rec"
  st_jrec "$WORK/jn/bb.rec" b "$_jn_t" base2 2 "$_jn_p1" "$_jn_p2"
  st_jn JN6 JN6 'different bases' "$WORK/jn/a.rec" "$WORK/jn/bb.rec"
  st_jrec "$WORK/jn/b1.rec" b "$_jn_t" base1 1 "$_jn_p1"
  st_jn JN7 JN7 'different target lists' "$WORK/jn/a.rec" "$WORK/jn/b1.rec"
  st_jrec "$WORK/jn/d1.rec" a "$_jn_t" base1 2 "$_jn_p1" "$_jn_p1"
  st_jrec "$WORK/jn/d2.rec" b "$_jn_t" base1 2 "$_jn_p1" "$_jn_p1"
  st_jn JN8 JN8 'listed twice' "$WORK/jn/d1.rec" "$WORK/jn/d2.rec"
  st_jrec "$WORK/jn/s1.rec" a "$_jn_t" base1 1 "$_jn_p1"
  st_jrec "$WORK/jn/s2.rec" b "$_jn_t" base1 1 'target=conformance/a.sh sel=--selftest-core verdict=PASS'
  st_jn JN9 JN9 'different selectors' "$WORK/jn/s1.rec" "$WORK/jn/s2.rec"
  st_jrec "$WORK/jn/f2.rec" b "$_jn_t" base1 1 'target=conformance/a.sh sel=--selftest verdict=FAIL'
  st_jn JN10 JN10 'target FAILED' "$WORK/jn/s1.rec" "$WORK/jn/f2.rec"
  st_jrec "$WORK/jn/u2.rec" b "$_jn_t" base1 1 'target=conformance/a.sh sel=--selftest verdict=UNVERIFIED'
  st_jn JN11 JN11 'target UNVERIFIED' "$WORK/jn/s1.rec" "$WORK/jn/u2.rec"
  st_jn JN12 JN12 'one record is N/A and the other is not' "$WORK/jn/na.rec" "$WORK/jn/b.rec"
  printf 'v1 face=a tree=%s\n' "$_jn_t" > "$WORK/jn/m1.rec"
  st_jn JN13 JN13 'malformed header' "$WORK/jn/m1.rec" "$WORK/jn/b.rec"
  st_jrec "$WORK/jn/g1.rec" a "$_jn_t" base1 1 'garbage'
  st_jrec "$WORK/jn/g2.rec" b "$_jn_t" base1 1 'garbage'
  st_jn JN19 JN19 'malformed line' "$WORK/jn/g1.rec" "$WORK/jn/g2.rec"
  st_jrec "$WORK/jn/n1.rec" a "$_jn_t" base1 1 'verdict=N/A' "$_jn_p1"
  st_jrec "$WORK/jn/n2.rec" b "$_jn_t" base1 1 'verdict=N/A' "$_jn_p1"
  st_jn JN17 JN17 'inconsistent record: verdict=N/A beside target lines' "$WORK/jn/n1.rec" "$WORK/jn/n2.rec"
  # JN17b — a header-only record (targets=0, no target and no verdict=N/A) is no record; the mutant neutralises that arm's action (the tagged line stays, so the other two arms are kept)
  st_jrec "$WORK/jn/h1.rec" a "$_jn_t" base1 0
  st_jrec "$WORK/jn/h2.rec" b "$_jn_t" base1 0
  rc=0; out=$( cd "$st/jn" && sh "$_self" --join "$WORK/jn/h1.rec" "$WORK/jn/h2.rec" 2>&1 ) || rc=$?
  st_expect "JN17b two header-only records: the join reds" 1 "$rc"
  st_has "JN17b the join names its cause" "$out" 'inconsistent record: neither a target nor verdict=N/A'
  if st_cmut jn17bm '/# JN17$/s/0:0) _jn_bad "[^"]*"; return 1 ;;/0:0) : ;;/'; then
    out=$( cd "$st/jn" && sh "$WORK/cm.jn17bm.sh" --join "$WORK/jn/h1.rec" "$WORK/jn/h2.rec" 2>&1 ) || :
    st_has "JN17bm the mutant still reached a join verdict" "$out" 'selftest-hermetic: join'
    st_lacks "JN17bm with the 0:0 arm neutralised the join no longer names the cause, so JN17b has teeth" "$out" 'inconsistent record: neither a target nor verdict=N/A'
  fi
  st_jrec "$WORK/jn/v2.rec" a "$_jn_t" base1 2 "$_jn_p1" "$_jn_p2"
  sed 's/^v1 /v2 /' "$WORK/jn/v2.rec" > "$WORK/jn/v2b.rec"
  st_jn JN14 JN14 'unknown record version' "$WORK/jn/v2b.rec" "$WORK/jn/b.rec"
  st_jrec "$WORK/jn/k1.rec" a "$_jn_t" base1 1 'target=conformance/a.sh sel=--selftest verdict=SKIP'
  st_jrec "$WORK/jn/k2.rec" b "$_jn_t" base1 1 'target=conformance/a.sh sel=--selftest verdict=SKIP'
  st_jn JN15 JN15 "unknown verdict 'SKIP'" "$WORK/jn/k1.rec" "$WORK/jn/k2.rec"
  st_jrec "$WORK/jn/c1.rec" a "$_jn_t" base1 3 "$_jn_p1" "$_jn_p2"
  st_jrec "$WORK/jn/c2.rec" b "$_jn_t" base1 3 "$_jn_p1" "$_jn_p2"
  st_jn JN16 JN16 'count mismatch: the header says targets=3 but the body has 2' "$WORK/jn/c1.rec" "$WORK/jn/c2.rec"
  st_jrec "$WORK/jn/x1.rec" a "$_jn_t" base1 1 'target=conformance/a.sh sel=- verdict=PASS'
  st_jrec "$WORK/jn/x2.rec" b "$_jn_t" base1 1 'target=conformance/a.sh sel=- verdict=PASS'
  st_jn JN18 JN18 "bad selector '-' for verdict PASS" "$WORK/jn/x1.rec" "$WORK/jn/x2.rec"

  # GRP, GR, FLG, JNG (SWAS-871, S1) — the split target: a kit-tree-only committed list (SPLIT_FACE_TARGETS), a STATIC parse of the target's group table (git show HEAD:<path>; nothing of the target runs), --group <g> <path> (one group under both faces),
  # one record line per group, and the join's per-group lines (JN8 keyed by path and selector for a split path, JN18's group selector, JN20). The stub records every run to $HG_MARK, the marker a static parse must never create.
  _hgm=$WORK/hg.mark; _hgl=$WORK/hg.log; : > "$_hgl"
  st_repo "$st/gk"; mkdir -p "$st/gk/docs"; : > "$st/gk/docs/ROADMAP-KIT.md"
  st_splitstub "$st/gk/conformance/prepush-lane.sh" ok; st_splitstub "$st/gk/conformance/other.sh" ok
  st_commit "$st/gk"
  st_repo "$st/gn"; st_splitstub "$st/gn/conformance/prepush-lane.sh" ok; st_commit "$st/gn"
  rc=0; out=$( cd "$st/gk" && HG_MARK=$_hgm CF_LOG=$_hgl sh "$_self" --groups conformance/prepush-lane.sh 2>&1 ) || rc=$?
  st_expect "GRP a listed target on a kit tree: --groups is rc 0" 0 "$rc"
  st_expect "GRP and prints its groups in table order, one per line" "g1${NL}g2${NL}g3" "$out"
  if [ ! -e "$_hgm" ]; then echo "PASS: selftest — GRP --groups executed nothing of the target (the stub's marker is absent)"; else echo "FAIL: selftest — GRP --groups ran the target (its marker exists)"; sfail=1; fi
  rc=0; out=$( cd "$st/gn" && sh "$_self" --groups conformance/prepush-lane.sh 2>&1 ) || rc=$?
  st_expect "GRP a non-kit tree prints nothing and is rc 0" "0|" "$rc|$out"
  rc=0; out=$( cd "$st/gk" && sh "$_self" --groups conformance/other.sh 2>&1 ) || rc=$?
  st_expect "GRP an unlisted path (with a table of its own) prints nothing and is rc 0" "0|" "$rc|$out"
  for _hk in dup empty malformed none; do
    st_repo "$st/g$_hk"; mkdir -p "$st/g$_hk/docs"; : > "$st/g$_hk/docs/ROADMAP-KIT.md"; st_splitstub "$st/g$_hk/conformance/prepush-lane.sh" "$_hk"; st_commit "$st/g$_hk"
    rc=0; out=$( cd "$st/g$_hk" && sh "$_self" --groups conformance/prepush-lane.sh 2>&1 ) || rc=$?
    st_expect "GRP a $_hk group table on a listed target is rc 1" 1 "$rc"
    st_has "GRP and names the table" "$out" 'group table'
  done
  if st_cmut grpk '/# SFKIT$/d'; then
    out=$( cd "$st/gn" && sh "$WORK/cm.grpk.sh" --groups conformance/prepush-lane.sh 2>&1 ) || :
    st_expect "GRPm with the kit test dropped a non-kit tree prints the groups, so GRP has teeth" "g1${NL}g2${NL}g3" "$out"
  fi
  if st_cmut grpx '/# HGSHOW$/s,^,  sh "$_gtop/$_gp" >/dev/null 2>\&1 || :; ,'; then
    rm -f "$_hgm"; ( cd "$st/gk" && HG_MARK=$_hgm CF_LOG=$_hgl sh "$WORK/cm.grpx.sh" --groups conformance/prepush-lane.sh ) >/dev/null 2>&1 || :
    if [ -e "$_hgm" ]; then echo "PASS: selftest — GRPm a parse that runs the target creates the stub's marker, so the marker check has teeth"; else echo "FAIL: selftest — GRPm the running mutant left no marker: the marker proves nothing"; sfail=1; fi
  fi
  # GR — --group <g> <path>: one group, both faces, the TARGET line names the group; any other grammar is rc 2
  : > "$_hgl"; rc=0; out=$( cd "$st/gk" && CF_LOG=$_hgl sh "$_self" --group g2 conformance/prepush-lane.sh 2>&1 ) || rc=$?
  st_expect "GR --group g2 of a split target passes both faces" 0 "$rc"
  st_has "GR the TARGET line names the group" "$out" 'TARGET: conformance/prepush-lane.sh group g2 (both faces)'
  st_count "GR each face ran the group once (--selftest-group g2)" 2 "$_hgl" 'conformance/prepush-lane.sh --selftest-group g2'
  st_count "GR and no other group ran" 0 "$_hgl" 'conformance/prepush-lane.sh --selftest-group g1'
  st_has "GR the face line carries the group" "$out" 'PASS: face (b) clone — conformance/prepush-lane.sh [--selftest-group g2] ('
  rc=0; ( cd "$st/gk" && sh "$_self" --group nosuch conformance/prepush-lane.sh ) >/dev/null 2>&1 || rc=$?
  st_expect "GR a group the table does not name is rc 2" 2 "$rc"
  rc=0; ( cd "$st/gk" && sh "$_self" --group g1 conformance/other.sh ) >/dev/null 2>&1 || rc=$?
  st_expect "GR a group of an unlisted path is rc 2" 2 "$rc"
  st_fmu GR1 --groups
  st_fmu GR2 --groups conformance/a.sh conformance/b.sh
  st_fmu GR3 --group g1
  st_fmu GR4 --touched --groups conformance/a.sh
  st_fmu GR5 conformance/a.sh --group g1
  st_fmu GR6 --all --group g1 conformance/a.sh
  st_fmu GR7 --join --groups conformance/a.sh
  if st_cmut grp2m '/# HFSEL2$/s/ \${_sel2:+"\$_sel2"}//'; then
    : > "$_hgl"; ( cd "$st/gk" && CF_LOG=$_hgl sh "$WORK/cm.grp2m.sh" --group g2 conformance/prepush-lane.sh ) >/dev/null 2>&1 || :
    st_count "GRm with face (a) not handed the group name it runs one call short (--selftest-group g2 once), so GR has teeth" 1 "$_hgl" 'conformance/prepush-lane.sh --selftest-group g2'
  fi
  # FLG — a face record holds one line per group, targets= counts the body lines, a malformed table is a FAIL line and runs nothing
  st_repo "$st/fsp"; mkdir -p "$st/fsp/docs"; : > "$st/fsp/docs/ROADMAP-KIT.md"; st_commit "$st/fsp"
  ( cd "$st/fsp" && git update-ref refs/remotes/origin/main HEAD ) >/dev/null 2>&1
  st_splitstub "$st/fsp/conformance/prepush-lane.sh" ok; st_commit "$st/fsp"
  _fp_t=$(git -C "$st/fsp" rev-parse 'HEAD^{tree}'); _fp_b=$(git -C "$st/fsp" rev-parse refs/remotes/origin/main)
  _fp_l1='target=conformance/prepush-lane.sh sel=--selftest-group:g1 verdict=PASS'
  _fp_l2='target=conformance/prepush-lane.sh sel=--selftest-group:g2 verdict=PASS'
  _fp_l3='target=conformance/prepush-lane.sh sel=--selftest-group:g3 verdict=PASS'
  : > "$_hgl"
  for _fx in a b; do
    rc=0; out=$( cd "$st/fsp" && CF_LOG=$_hgl sh "$_self" --touched --face "$_fx" --output-file "$WORK/fsp.$_fx.rec" 2>&1 ) || rc=$?
    st_expect "FLG face ($_fx) over a split target: rc 0" 0 "$rc"
    st_expect "FLG the record header counts the three body lines" "v1 face=$_fx tree=$_fp_t base=$_fp_b targets=3" "$(sed -n 1p "$WORK/fsp.$_fx.rec")"
    st_expect "FLG and the body is one line per group, in table order" "$_fp_l1${NL}$_fp_l2${NL}$_fp_l3" "$(sed -n '2,$p' "$WORK/fsp.$_fx.rec")"
    st_has "FLG a group's TARGET line says it is one face" "$out" 'TARGET: conformance/prepush-lane.sh group g3 (face '"$_fx"' only)'
  done
  st_count "FLG each group ran once per face (g1, two faces)" 2 "$_hgl" 'conformance/prepush-lane.sh --selftest-group g1'
  rc=0; out=$( cd "$st/fsp" && sh "$_self" --join "$WORK/fsp.a.rec" "$WORK/fsp.b.rec" 2>&1 ) || rc=$?
  st_expect "FLG the two records the writer made join green (writer and reader agree)" 0 "$rc"
  if st_cmut flg1 "/# FLGRP\$/s,^.*\$,    printf 'target=%s sel=--selftest verdict=%s\\\\n' \"\$_fl_p\" \"\$_fv\" >> \"\$_fl_body\"   # FLGRP,"; then
    ( cd "$st/fsp" && sh "$WORK/cm.flg1.sh" --touched --face a --output-file "$WORK/fsp.m1.rec" ) >/dev/null 2>&1 || :
    st_expect "FLGm with one whole --selftest line per group the first body line is no group line, so FLG has teeth" "target=conformance/prepush-lane.sh sel=--selftest verdict=PASS" "$(sed -n 2p "$WORK/fsp.m1.rec")"
  fi
  if st_cmut flg2 '/# FLN$/s/_fl_n=.*$/_fl_n=$#   # FLN/'; then
    ( cd "$st/fsp" && sh "$WORK/cm.flg2.sh" --touched --face a --output-file "$WORK/fsp.m2.rec" ) >/dev/null 2>&1 || :
    st_expect "FLGm with the header counting paths it says targets=1 over three body lines, so FLG has teeth" "v1 face=a tree=$_fp_t base=$_fp_b targets=1" "$(sed -n 1p "$WORK/fsp.m2.rec")"
  fi
  st_repo "$st/fsm"; mkdir -p "$st/fsm/docs"; : > "$st/fsm/docs/ROADMAP-KIT.md"; st_commit "$st/fsm"
  ( cd "$st/fsm" && git update-ref refs/remotes/origin/main HEAD ) >/dev/null 2>&1
  st_splitstub "$st/fsm/conformance/prepush-lane.sh" malformed; st_commit "$st/fsm"
  rm -f "$_hgm"; rc=0; out=$( cd "$st/fsm" && HG_MARK=$_hgm sh "$_self" --touched --face a --output-file "$WORK/fsm.a.rec" 2>&1 ) || rc=$?
  st_expect "FLGb a malformed table: the face is rc 1" 1 "$rc"
  st_expect "FLGb the record says sel=- verdict=FAIL, one body line" "targets=1${NL}target=conformance/prepush-lane.sh sel=- verdict=FAIL" "$(sed -n 1p "$WORK/fsm.a.rec" | sed 's/^.*targets=/targets=/')${NL}$(sed -n '2,$p' "$WORK/fsm.a.rec")"
  if [ ! -e "$_hgm" ]; then echo "PASS: selftest — FLGb and nothing of the target ran"; else echo "FAIL: selftest — FLGb the target ran although its table is malformed"; sfail=1; fi
  # JNG — the join over group lines (a kit fixture holding the stub at HEAD: the join reads git show HEAD:<path>, never the stub)
  st_repo "$st/jk"; mkdir -p "$st/jk/docs"; : > "$st/jk/docs/ROADMAP-KIT.md"; st_splitstub "$st/jk/conformance/prepush-lane.sh" ok; st_commit "$st/jk"
  _jk_t=$(git -C "$st/jk" rev-parse 'HEAD^{tree}')
  st_jrec "$WORK/jn/ga.rec" a "$_jk_t" base1 3 "$_fp_l1" "$_fp_l2" "$_fp_l3"
  st_jrec "$WORK/jn/gb.rec" b "$_jk_t" base1 3 "$_fp_l1" "$_fp_l2" "$_fp_l3"
  rm -f "$_hgm"; rc=0; out=$( cd "$st/jk" && HG_MARK=$_hgm sh "$_self" --join "$WORK/jn/ga.rec" "$WORK/jn/gb.rec" 2>&1 ) || rc=$?
  st_expect "JNG the same three group lines on both faces join OK (JN8 keyed by path and selector, JN16 counts body lines, JN20 agrees with the table)" 0 "$rc"
  if [ ! -e "$_hgm" ]; then echo "PASS: selftest — JNG the join read the table statically (the stub's marker is absent)"; else echo "FAIL: selftest — JNG the join ran the target"; sfail=1; fi
  _sj_dir=$st/jk
  st_jrec "$WORK/jn/gd.rec" a "$_jk_t" base1 1 'target=conformance/prepush-lane.sh sel=--selftest-group: verdict=PASS'
  st_jn JN18g1 JN18 "bad selector '--selftest-group:' for verdict PASS" "$WORK/jn/gd.rec" "$WORK/jn/gb.rec"
  st_jrec "$WORK/jn/ge.rec" a "$_jk_t" base1 1 'target=conformance/prepush-lane.sh sel=--selftest-group:G! verdict=PASS'
  st_jn JN18g2 JN18 "bad selector '--selftest-group:G!' for verdict PASS" "$WORK/jn/ge.rec" "$WORK/jn/gb.rec"
  st_jrec "$WORK/jn/gf.rec" a "$_jk_t" base1 4 "$_fp_l1" "$_fp_l1" "$_fp_l2" "$_fp_l3"
  st_jrec "$WORK/jn/gg.rec" b "$_jk_t" base1 4 "$_fp_l1" "$_fp_l1" "$_fp_l2" "$_fp_l3"
  st_jn JN8g JN8 'listed twice on face (a)' "$WORK/jn/gf.rec" "$WORK/jn/gg.rec"
  if st_cmut jn8m '/# JN8$/s/\$_jdl/$_jp/;/# JN8$/s/\$_jdk/$_jpth/'; then
    out=$( cd "$st/jk" && sh "$WORK/cm.jn8m.sh" --join "$WORK/jn/ga.rec" "$WORK/jn/gb.rec" 2>&1 ) || :
    st_has "JN8gm with the duplicate key by path alone a split target's own group lines read as a duplicate, so JNG has teeth" "$out" 'listed twice'
  fi
  st_jrec "$WORK/jn/gh.rec" a "$_jk_t" base1 1 "$_fp_l1" "$_fp_l2" "$_fp_l3"
  st_jn JN16g JN16 'count mismatch: the header says targets=1 but the body has 3' "$WORK/jn/gh.rec" "$WORK/jn/gb.rec"
  # a group missing on ONE face reds (JN7 and JN9 compare the line lists; JN20 is each record's own check). With JN20 deleted the join still reds by JN7, and with JN7 gone too it joins, so each is load-bearing
  st_jrec "$WORK/jn/gi.rec" b "$_jk_t" base1 2 "$_fp_l1" "$_fp_l2"
  rc=0; out=$( cd "$st/jk" && sh "$_self" --join "$WORK/jn/ga.rec" "$WORK/jn/gi.rec" 2>&1 ) || rc=$?
  st_expect "JN7g a group missing on face b reds the join" 1 "$rc"
  if st_cmut jn7a '/# JN20[abcd]$/d'; then
    out=$( cd "$st/jk" && sh "$WORK/cm.jn7a.sh" --join "$WORK/jn/ga.rec" "$WORK/jn/gi.rec" 2>&1 ) || :
    st_has "JN7gm with JN20 gone the join still reds, by the two faces' different target lists (JN7)" "$out" 'different target lists'
  fi
  if st_cmut jn7b '/# JN20[abcd]$/d;/# JN7$/d;/# JN9$/d'; then
    rc=0; ( cd "$st/jk" && sh "$WORK/cm.jn7b.sh" --join "$WORK/jn/ga.rec" "$WORK/jn/gi.rec" ) >/dev/null 2>&1 || rc=$?
    st_expect "JN7gm with JN20, JN7 and JN9 all gone the same two records join, so each check is load-bearing" 0 "$rc"
  fi
  # JN20 — each clause, a cell and a mutant: a missing group, an extra group, an unknown group, a whole --selftest line beside group lines, a sel=- line beside group lines (both faces carry the same lines, so only JN20 can red it)
  _jg_pair() {   # <id> <n> <line>... — two identical records, one per face
    _jg_id=$1; _jg_n=$2; shift 2
    st_jrec "$WORK/jn/$_jg_id.a.rec" a "$_jk_t" base1 "$_jg_n" "$@"
    st_jrec "$WORK/jn/$_jg_id.b.rec" b "$_jk_t" base1 "$_jg_n" "$@"
  }
  _jg_pair miss 2 "$_fp_l1" "$_fp_l2"
  st_jn JN20a JN20a 'is missing group g3' "$WORK/jn/miss.a.rec" "$WORK/jn/miss.b.rec"
  _jg_pair extra 4 "$_fp_l1" "$_fp_l2" "$_fp_l3" 'target=conformance/prepush-lane.sh sel=--selftest-group:g4 verdict=PASS'
  st_jn JN20b JN20b 'names a group the table does not have: g4' "$WORK/jn/extra.a.rec" "$WORK/jn/extra.b.rec"
  _jg_pair unk 3 "$_fp_l1" "$_fp_l2" 'target=conformance/prepush-lane.sh sel=--selftest-group:gx verdict=PASS'
  st_jn JN20bu JN20b 'names a group the table does not have: gx' "$WORK/jn/unk.a.rec" "$WORK/jn/unk.b.rec"
  _jg_pair whole 4 "$_fp_l1" "$_fp_l2" "$_fp_l3" 'target=conformance/prepush-lane.sh sel=--selftest verdict=PASS'
  st_jn JN20c JN20c 'a whole --selftest line beside group lines' "$WORK/jn/whole.a.rec" "$WORK/jn/whole.b.rec"
  _jg_pair dash 4 "$_fp_l1" "$_fp_l2" "$_fp_l3" 'target=conformance/prepush-lane.sh sel=- verdict=EXCLUDED'
  st_jn JN20d JN20d 'a sel=- line beside group lines' "$WORK/jn/dash.a.rec" "$WORK/jn/dash.b.rec"
  _jg_pair excl 1 'target=conformance/prepush-lane.sh sel=- verdict=EXCLUDED'
  rc=0; out=$( cd "$st/jk" && sh "$_self" --join "$WORK/jn/excl.a.rec" "$WORK/jn/excl.b.rec" 2>&1 ) || rc=$?
  st_expect "JN20 an excluded split target keeps its ONE sel=- line and joins (JN20 applies only when group lines exist)" 0 "$rc"
  # JN18g3 (D) - a group selector is admitted only for a split-listed path: on any other path it is a bad selector
  st_jrec "$WORK/jn/gu.a.rec" a "$_jk_t" base1 1 'target=conformance/a.sh sel=--selftest-group:g1 verdict=PASS'
  st_jrec "$WORK/jn/gu.b.rec" b "$_jk_t" base1 1 'target=conformance/a.sh sel=--selftest-group:g1 verdict=PASS'
  rc=0; out=$( cd "$st/jk" && sh "$_self" --join "$WORK/jn/gu.a.rec" "$WORK/jn/gu.b.rec" 2>&1 ) || rc=$?
  st_expect "JN18g3 a group line on an unsplit path reds the join" 1 "$rc"
  st_has "JN18g3 naming the selector" "$out" "bad selector '--selftest-group:g1' for verdict PASS"
  if st_cmut jn18g '/# JN18G$/s/if split_face_listed "\$_jtop" "\$_jpth"; then _jgok=1; fi/_jgok=1/'; then
    rc=0; ( cd "$st/jk" && sh "$WORK/cm.jn18g.sh" --join "$WORK/jn/gu.a.rec" "$WORK/jn/gu.b.rec" ) >/dev/null 2>&1 || rc=$?
    st_expect "JN18g3m with the split-list condition dropped the same unsplit group line joins, so JN18g3 has teeth" 0 "$rc"
  fi
  # B(i) - a shadow table (a second, double-quoted ST_GROUPS) is refused by the static parse
  st_repo "$st/gshadow"; mkdir -p "$st/gshadow/docs"; : > "$st/gshadow/docs/ROADMAP-KIT.md"; st_splitstub "$st/gshadow/conformance/prepush-lane.sh" shadow; st_commit "$st/gshadow"
  rc=0; out=$( cd "$st/gshadow" && sh "$_self" --groups conformance/prepush-lane.sh 2>&1 ) || rc=$?
  st_expect "GRPs a second, double-quoted ST_GROUPS line is rc 1" 1 "$rc"
  st_has "GRPs naming the shadow table" "$out" 'a shadow table'
  if st_cmut grps '/# HGSHADOW$/d'; then
    rc=0; out=$( cd "$st/gshadow" && sh "$WORK/cm.grps.sh" --groups conformance/prepush-lane.sh 2>&1 ) || rc=$?
    st_expect "GRPsm with the census line deleted the shadow table parses (rc 0), so GRPs has teeth" 0 "$rc"
  fi
  # H - the two operand arms screen their operands with new_flag_in
  st_fmu H1 --groups --join
  st_fmu H2 --group g1 --groups
  if st_cmut hgf '/# HGFLAG$/d'; then
    rc=0; ( cd "$st/jn" && sh "$WORK/cm.hgf.sh" --groups --join ) >/dev/null 2>&1 || rc=$?
    st_expect "Hm with the flag screen deleted --groups --join is no longer rc 2, so H has teeth" 0 "$rc"
  fi
  # J - the face header is a writer-side count, so a line a target appends to the body file cannot make the record agree with itself
  _jf='/# FLGRP$/s/; _fl_cnt=/; echo "target=conformance\/z-$_fl_g.sh sel=- verdict=EXCLUDED" >> "$_fl_body"; _fl_cnt=/'
  if st_cmut jf1 "$_jf"; then
    for _jx in a b; do ( cd "$st/fsp" && sh "$WORK/cm.jf1.sh" --touched --face "$_jx" --output-file "$WORK/jf.$_jx.rec" ) >/dev/null 2>&1 || :; done
    rc=0; out=$( cd "$st/fsp" && sh "$_self" --join "$WORK/jf.a.rec" "$WORK/jf.b.rec" 2>&1 ) || rc=$?
    st_expect "J a body with appended lines reds the join (the header is the writer's count)" 1 "$rc"
    st_has "J naming the count mismatch" "$out" 'count mismatch: the header says targets=3 but the body has 6'
  fi
  if st_cmut jf2 "$_jf;/# FLN\$/s/.*/  _fl_n=\$(grep -c \"\" \"\$_fl_body\" || :)   # FLN/"; then
    for _jx in a b; do ( cd "$st/fsp" && sh "$WORK/cm.jf2.sh" --touched --face "$_jx" --output-file "$WORK/jf2.$_jx.rec" ) >/dev/null 2>&1 || :; done
    rc=0; ( cd "$st/fsp" && sh "$_self" --join "$WORK/jf2.a.rec" "$WORK/jf2.b.rec" ) >/dev/null 2>&1 || rc=$?
    st_expect "Jm with the header counting the file's lines again the forged body joins (rc 0), so J has teeth" 0 "$rc"
  fi
  _sj_dir=''

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
st_fmu() { # <id> <argv...> — a face-mode or join grammar the script refuses: rc 2 with the usage text
  _su_id=$1; shift
  _su_rc=0; _su_o=$( cd "$st/jn" && sh "$_self" "$@" 2>&1 ) || _su_rc=$?
  st_expect "$_su_id a bad grammar is rc 2" 2 "$_su_rc"
  st_has "$_su_id the usage text is printed" "$_su_o" 'usage: selftest-hermetic.sh'
}
st_fmrepo() { # <dir> <kind: ok|fail> — a repo whose base ref (refs/remotes/origin/main) is its first commit and whose ONE touched roster script comes in the second
  st_repo "$1"; st_commit "$1"
  ( cd "$1" && git update-ref refs/remotes/origin/main HEAD ) >/dev/null 2>&1
  case $2 in
    ok)   st_script "$1/conformance/hermetic-check.sh" inline ;;
    fail) st_fix "$1/conformance/fail1-check.sh" fail1 ;;
  esac
  st_commit "$1"
}
st_jrec() { # <file> <face> <tree> <base> <n> [line...] — write a v1 face record
  _sj_f=$1; _sj_h="v1 face=$2 tree=$3 base=$4 targets=$5"; shift 5
  { printf '%s\n' "$_sj_h"; if [ "$#" -gt 0 ]; then printf '%s\n' "$@"; fi; } > "$_sj_f"
}
st_splitstub() { # <path> <kind: ok|dup|empty|malformed|none> — a stub target: it records every run to $HG_MARK (the marker a static parse must never create) and logs each --selftest / --selftest-group call to $CF_LOG; `none` carries no ST_GROUPS line
  case $2 in ok|shadow) _sp_t="g1 g2 g3" ;; dup) _sp_t="g1 g1" ;; empty) _sp_t="" ;; malformed) _sp_t="g1 G-2" ;; none) _sp_t="" ;; esac
  mkdir -p "$(dirname "$1")"
  { printf '%s\n' '#!/bin/sh' '[ -z "${HG_MARK-}" ] || : > "$HG_MARK"'
    if [ "$2" != none ]; then printf "ST_GROUPS='%s'\n" "$_sp_t"; fi
    if [ "$2" = shadow ]; then printf 'ST_GROUPS="g1"\n'; fi
    printf '%s\n' 'case "${1:-}" in' '  --selftest|--selftest-group) printf "%s %s\n" "$0" "$*" >> "${CF_LOG:-/dev/null}"; echo OK ;;' 'esac'; } > "$1"
}
st_jn() { # <id> <tag> <cause> <record>... — the join reds (rc 1) and names the cause; the same run with the tagged check deleted (a throwaway copy, the st_cmut idiom) no longer names it. Runs in $_sj_dir when set (a kit fixture), else in $st/jn.
  _sj_id=$1; _sj_tag=$2; _sj_cause=$3; shift 3
  rc=0; out=$( cd "${_sj_dir:-$st/jn}" && sh "$_self" --join "$@" 2>&1 ) || rc=$?
  st_expect "$_sj_id the join reds" 1 "$rc"
  st_has "$_sj_id the join names its cause" "$out" "$_sj_cause"
  if st_cmut "${_sj_id}m" "/# $_sj_tag\$/d"; then
    out=$( cd "${_sj_dir:-$st/jn}" && sh "$WORK/cm.${_sj_id}m.sh" --join "$@" 2>&1 ) || :
    st_has "${_sj_id}m the mutant still reached a join verdict (it did not crash)" "$out" 'selftest-hermetic: join'
    st_lacks "${_sj_id}m with the tagged check deleted the join no longer names the cause, so $_sj_id has teeth" "$out" "$_sj_cause"
  fi
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
    if [ "${2:-}" = --face ]; then
      face_grammar "$@" || { usage_text >&2; exit 2; }
      face_touched; _fin $?
    fi
    if new_flag_in "$@"; then usage_text >&2; exit 2; fi
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
  --join)
    shift
    if new_flag_in "$@"; then usage_text >&2; exit 2; fi
    join_records "$@"; _fin $? ;;
  --all)
    if new_flag_in "$@"; then usage_text >&2; exit 2; fi
    cd "$(git rev-parse --show-toplevel)" 2>/dev/null || { echo "selftest-hermetic: not a git repo" >&2; exit 2; }
    validate_exclusions || exit 1
    _set=$(roster)
    if [ -z "$_set" ]; then echo "selftest-hermetic: N/A — the roster is empty on this tree"; _fin 0; fi
    # shellcheck disable=SC2086
    run_lane $_set; _fin $? ;;
  --groups)
    # SWAS-871: exactly `--groups <path>`; a static parse (hf_groups), nothing of the target runs
    shift
    if [ "$#" != 1 ]; then usage_text >&2; exit 2; fi
    if new_flag_in "$@"; then usage_text >&2; exit 2; fi   # HGFLAG
    hf_groups "$1"; _fin $? ;;
  --group)
    # SWAS-871: exactly `--group <name> <path>`, the name one of the path's committed groups (rc 2 otherwise)
    shift
    if [ "$#" != 2 ]; then usage_text >&2; exit 2; fi
    if new_flag_in "$@"; then usage_text >&2; exit 2; fi   # HGFLAG
    cd "$(git rev-parse --show-toplevel)" 2>/dev/null || { echo "selftest-hermetic: not a git repo" >&2; exit 2; }
    if ! hf_group_known "$1" "$2"; then usage_text >&2; echo "selftest-hermetic: '$1' is not a committed group of '$2' (see --groups $2)" >&2; exit 2; fi
    run_group "$1" "$2"; _fin $? ;;
  "")
    usage_text >&2; exit 2 ;;
  *)
    if new_flag_in "$@"; then usage_text >&2; exit 2; fi
    run_lane "$@"; _fin $? ;;
esac
