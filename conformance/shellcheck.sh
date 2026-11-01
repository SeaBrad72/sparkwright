#!/bin/sh
# Kit shell regression-lock: lint the kit's MAINTAINER-EDITABLE shell code (dogfooding quality).
# Scope: scripts/*.sh, scripts/kit-guard, conformance/*.sh, hooks/pre-push. The control-plane
# guard under .claude/hooks/ is DELIBERATELY excluded — see collect() for why.
# Floor: error + warning (POSIX -s sh). This shell is currently shellcheck-clean; this keeps it
# that way (dash -n only checks syntax, not lint). CONDITIONAL on shellcheck being installed:
# SKIP-pass if absent (a dev may not have it) — the kit CI installs it and runs it for real, so
# drift IN THE LINTED SCOPE is caught in CI. (The excluded .claude/hooks/ guard core is linted
# NOWHERE — by design; it is regression-locked behaviorally instead, see collect() below.)
#   sh conformance/shellcheck.sh [--selftest | --listed <listing-file>]
# --listed (PREPUSH-CORE-DEFAULT): lint only the files that are BOTH in collect()'s scope AND named, one
#   repo-relative path per line, in <listing-file> — the pre-push lane's default arm lints the change's
#   own shell, CI keeps the full lock. Same scope, same flags (one source: collect() + lint_set()).
# Memory (SWAS-471): shellcheck runs in bounded batches (1 file per process by default), never one process over
#   every file; with GNU or BSD time a one-line "peak RSS top-5" summary is printed (never part of the verdict), a file above 4096 MB
#   gets a warn-only HEADROOM line, and with no usable time binary "peak RSS: not measured" says so.
# Data-flow (SWAS-499): every run prints "dataflow analysis OFF for 3 files …" (shellcheck >=0.10) or "… ON" (older/unreadable), and the
#   verdict line names the shellcheck version. See SC_NOFLOW_FILES below for what goes quiet and why.
# Exit: 0 = clean or SKIP · 1 = a finding · 2 = bad usage (incl. a missing/unreadable listing). POSIX sh; dash-clean.
set -eu

# collect existing kit shell files into the positional params.
# DELIBERATELY excludes .claude/hooks/guard.sh + guard-core.sh — the §13 autonomy-guard core,
# the single most security-sensitive shell in the kit. guard.sh is clean; guard-core.sh carries
# only 3 benign shellcheck warnings (2 redundant-but-still-denying case patterns + 1 cls=read
# false positive — no behavior
# change); silencing those in-place means cosmetic edits to the most sensitive file, so instead
# they're regression-locked BEHAVIORALLY by their own dedicated conformance — agent-autonomy.sh
# (deny-corpus), guard-wired.sh, guard-core-sourced.sh, kit-guard --selftest — not by this lint
# floor. NB: the OTHER control-plane shell (scripts/kit-guard, hooks/pre-push) IS included below —
# it was cleanable with justified disables, so it stays in the lock for maximal coverage. The
# discriminator is cleanable-vs-benign-warnings, not control-plane-ness.
collect() {
  set --
  for f in scripts/*.sh conformance/*.sh; do [ -f "$f" ] && set -- "$@" "$f"; done
  # CP-3: the scripts the kit SHIPS are held to the same bar as the scripts the kit IS. incept copies
  # profiles/<stack>/scaffold/scripts/* into the adopter's scripts/, where this very check scopes them
  # — so a scaffold script that fails shellcheck reddens EVERY adopter's `verify.sh --require` while
  # the kit's own CI never sees it. Linting only our own scripts/ is precisely how that shipped.
  for f in profiles/*/scaffold/scripts/*.sh; do [ -f "$f" ] && set -- "$@" "$f"; done
  [ -f scripts/kit-guard ] && set -- "$@" scripts/kit-guard
  [ -f hooks/pre-push ]    && set -- "$@" hooks/pre-push
  printf '%s\n' "$@"
}

# Bounded batches (SWAS-471): ONE shellcheck process over all ~225 kit files peaked at 7165 MB RSS on a
# 7931 MB CI runner (run 40902268954) and OOM-killed it (exit 143). Default 1 file per process, so a
# process's peak is one file's, and the RSS summary names a real file. Both values are HARD-CODED: no
# environment variable may widen the batch or swap the time binary on a gate (the selftest edits a COPY).
SC_BATCH=1
_sc_time=/usr/bin/time
_sc_tmp=""

# Data-flow analysis (SWAS-499): on shellcheck >=0.10 three files run with `--extended-analysis=false`, and the first of them without `-x`,
# because their peaks were 4-11 GB (agent-autonomy 9.4-11.3 GB, tracker-read 4.3 GB, preflight 3.0 GB; 0.11.0, macOS) on a 7.9 GB runner that
# was OOM-killed three times. What goes quiet there: SC2218 (a function used before it is defined), SC2319/SC2320 (an exit code overwritten
# before it is read), SC2324 (`+=` on a number). On 0.9 the flag does not exist, so older versions lint EXACTLY as before. The lists are
# LITERAL and reviewed here, no argv flag or environment variable reaches them, and conformance/ci-gates.sh holds a copy of both (check_shellcheck_pin_tree).
SC_NOFLOW_FILES="conformance/agent-autonomy.sh scripts/tracker-read.sh scripts/preflight.sh"
SC_NOFOLLOW_FILES="conformance/agent-autonomy.sh"
_sc_ver=""; _sc_reduced=0

# sc_probe — read the version of the shellcheck on PATH; sets _sc_ver (X.Y.Z, or "" when unreadable) and _sc_reduced (1 on >=0.10).
# The compare is NUMERIC on major and minor (a string compare would put 0.10 before 0.9). The probe sits inside an `if`, so a
# `--version` that exits non-zero cannot abort the wrapper under `set -e`; anything unparseable stays at 0 = lint as before.
sc_probe() {
  _sc_ver=""; _sc_reduced=0
  if _sp_o=$(shellcheck --version 2>/dev/null); then
    _sc_ver=$(printf '%s\n' "$_sp_o" | sed -n 's/^version: *\([0-9][0-9]*[.][0-9][0-9]*[.][0-9][0-9]*\).*$/\1/p' | head -n 1)
  fi
  [ -n "$_sc_ver" ] || return 0
  _sp_major=${_sc_ver%%.*}; _sp_rest=${_sc_ver#*.}; _sp_minor=${_sp_rest%%.*}
  if [ "$_sp_major" -gt 0 ] || [ "$_sp_minor" -ge 10 ]; then _sc_reduced=1; fi
}

# sc_noflow / sc_nofollow <file> — 0 when this run drops data-flow analysis / `-x` for that file (>=0.10 only; the listed files only).
sc_noflow() {
  [ "$_sc_reduced" = 1 ] || return 1
  case " $SC_NOFLOW_FILES " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}
sc_nofollow() {
  [ "$_sc_reduced" = 1 ] || return 1
  case " $SC_NOFOLLOW_FILES " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

# detect_time — sets _sc_flavour to gnu (Linux: -v -o FILE) or bsd (macOS: -l, report on stderr, bytes), else
# "" (measurement off, shellcheck runs directly). Each flavour is probed in the EXACT shape used per batch and
# is taken only if the probe ran its command (sentinel file) AND printed the RSS line: a binary that exits 0
# without running the command (/usr/bin/true) is never taken for either.
detect_time() {
  [ -x "$_sc_time" ] || return 0
  rm -f "$_sc_tmp/ran"
  if "$_sc_time" -v -o "$_sc_tmp/probe" sh -c ': > "$1"' sh "$_sc_tmp/ran" >/dev/null 2>&1 \
     && grep -q 'Maximum resident set size' "$_sc_tmp/probe" 2>/dev/null && [ -f "$_sc_tmp/ran" ]; then
    _sc_flavour=gnu; return 0
  fi
  rm -f "$_sc_tmp/ran"
  if "$_sc_time" -l sh -c 'exec "$@" 2>&3' sh sh -c ': > "$1"' sh "$_sc_tmp/ran" 3>&2 2>"$_sc_tmp/probe" >/dev/null \
     && grep -q 'maximum resident set size' "$_sc_tmp/probe" 2>/dev/null && [ -f "$_sc_tmp/ran" ]; then
    _sc_flavour=bsd
  fi
}

# record_rss <time-output-file> <label> — append "<kB> <label>" (BSD reports bytes); a file above 1 GB is also
# named at once, since a process can be killed before the final summary. Best effort, the caller ignores its rc.
record_rss() {
  _rr_kb=$(sed -n -e 's/.*Maximum resident set size (kbytes): *\([0-9][0-9]*\).*/\1/p' \
    -e 's/^ *\([0-9][0-9]*\)  *maximum resident set size.*/\1/p' "$1" 2>/dev/null | head -n 1)
  [ -n "$_rr_kb" ] || return 1
  if [ "$_sc_flavour" = bsd ]; then _rr_kb=$((_rr_kb / 1024)); fi
  printf '%s %s\n' "$_rr_kb" "$2" >> "$_sc_tmp/rss"
  [ "$_rr_kb" -le 1048576 ] || echo "shellcheck: peak RSS $2=$((_rr_kb / 1024))MB"
  # HEADROOM (SWAS-499): WARN-ONLY, conduct and NOT enforced. The same file measured 9.4 GB once and 11.3 GB another time, so a
  # memory-graded FAIL would be a flake surface; the OOM stays the hard failure. 4096 MB = half the smallest runner that lints (7.9 GB).
  [ "$_rr_kb" -le 4194304 ] || echo "shellcheck: HEADROOM $2=$(((_rr_kb + 1023) / 1024))MB is above 4096 MB (half the 7.9 GB CI runner; conduct, not enforced)"
}

# print_rss_top5 — one bounded summary line; rc 1 when nothing was measured. Never part of the verdict.
print_rss_top5() {
  [ -s "$_sc_tmp/rss" ] || return 1
  _p5=$(sort -rn "$_sc_tmp/rss" | head -n 5 | while read -r _kb _label; do printf ' %s=%sMB' "$_label" "$((_kb / 1024))"; done)
  echo "shellcheck: peak RSS top-5:$_p5"
}

# lint_batch <files…> — THE one shellcheck invocation (flags), optionally under GNU time. Returns shellcheck's rc.
lint_batch() {
  _lb_n=$((_lb_n + 1)); _lb_label=$1
  [ "$#" -le 1 ] || _lb_label="$1+$(($# - 1))"
  # Follow sources (the option before -s): verdict parity with the old ONE-process run, whose resolution of a
  # caller's sourced library came from the library being among the files; per file, that must come from disk.
  # A listed file always arrives alone (lint_set), so the per-file flags below never apply to a mixed batch.
  if [ "$#" -eq 1 ] && sc_noflow "$1"; then
    if sc_nofollow "$1"; then set -- shellcheck --extended-analysis=false -s sh -S warning "$@"
    else set -- shellcheck -x --extended-analysis=false -s sh -S warning "$@"; fi
  else set -- shellcheck -x -s sh -S warning "$@"; fi
  case $_sc_flavour in
    gnu) set -- "$_sc_time" -v -o "$_sc_tmp/t$_lb_n" "$@" ;;
    # BSD time has no -o and reports on ITS stderr, which the command shares: fd 3 keeps the user's stderr,
    # the wrapper sends shellcheck's own stderr there, and time's report alone lands in the temp file.
    bsd) set -- "$_sc_time" -l sh -c 'exec "$@" 2>&3' sh "$@" ;;
  esac
  if [ "$_sc_flavour" = bsd ]; then
    if "$@" 3>&2 2>"$_sc_tmp/t$_lb_n"; then _lb_rc=0; else _lb_rc=$?; fi
  elif "$@"; then _lb_rc=0; else _lb_rc=$?; fi
  [ -z "$_sc_flavour" ] || record_rss "$_sc_tmp/t$_lb_n" "$_lb_label" || :
  return "$_lb_rc"
}

# lint_set <files…> — shared by run() and run_listed(): bounded batches, any finding makes it red, messages.
lint_set() {
  _ls_n=$#; _ls_rc=0; _lb_n=0; _sc_flavour=""
  _sc_tmp=$(mktemp -d); trap 'rm -rf "$_sc_tmp"' EXIT
  trap 'exit 130' INT; trap 'exit 143' TERM
  detect_time
  [ -n "$_sc_flavour" ] || echo "shellcheck: peak RSS: not measured (no usable time binary)"
  sc_probe
  if [ "$_sc_reduced" = 1 ]; then
    _ls_off=0  # how many of THIS run's files sit on the literal list (a --listed run may hold none, or one)
    for _ls_f in "$@"; do if sc_noflow "$_ls_f"; then _ls_off=$((_ls_off + 1)); fi; done
    echo "shellcheck: dataflow analysis OFF for $_ls_off files in this run (the 3 listed: agent-autonomy, tracker-read, preflight) on shellcheck >=0.10: SC2218/2319/2320/2324 not checked there; agent-autonomy linted without -x"
  elif [ -n "$_sc_ver" ]; then echo "shellcheck: dataflow analysis ON (shellcheck <0.10)"
  else echo "shellcheck: dataflow analysis ON (shellcheck version not readable: treated as <0.10)"; fi
  while [ "$#" -gt 0 ]; do  # batches
    _b=0; _bl=""
    while [ "$#" -gt 0 ] && [ "$_b" -lt "$SC_BATCH" ]; do
      if sc_noflow "$1"; then  # a listed file is always a batch of one: its flags are its own
        [ "$_b" -eq 0 ] || break
        _bl=" $1"; shift; break
      fi
      _bl="$_bl $1"; shift; _b=$((_b + 1))
    done
    set -f  # no globbing of the split batch
    # shellcheck disable=SC2086  # word-splitting the batch is intended (kit paths have no spaces)
    lint_batch $_bl || _ls_rc=1
    set +f
  done
  print_rss_top5 || :
  if [ "$_ls_rc" = 0 ]; then
    echo "shellcheck: OK ($_ls_n kit shell file(s) clean at the error/warning floor) (shellcheck ${_sc_ver:-unknown})"
    return 0
  fi
  echo "shellcheck: FAIL (findings above) — fix or justify with a '# shellcheck disable=SCnnnn' + reason"
  return 1
}

run() {
  command -v shellcheck >/dev/null 2>&1 || { echo "SKIP: shellcheck not installed (kit CI runs it for real)"; return 0; }
  # shellcheck disable=SC2046  # word-splitting the file list is intended here
  set -- $(collect)
  [ "$#" -gt 0 ] || { echo "shellcheck: no kit shell files found"; return 1; }
  lint_set "$@"
}

# run_listed <listing-file> — collect()'s scope INTERSECTED with the listing (exact whole-line match).
# The listing is validated BEFORE the SKIP test: a bad operand is rc 2 whether or not shellcheck is here.
run_listed() {
  [ -f "$1" ] && [ -r "$1" ] || { echo "shellcheck: --listed needs a readable listing file: $1" >&2; return 2; }
  command -v shellcheck >/dev/null 2>&1 || { echo "SKIP: shellcheck not installed (kit CI runs it for real)"; return 0; }
  _rl_sel=$(collect | while IFS= read -r _rl_f; do
    if grep -qxF -- "$_rl_f" "$1"; then printf '%s\n' "$_rl_f"; fi
  done)
  [ -n "$_rl_sel" ] || { echo "shellcheck: OK (no listed kit shell file)"; return 0; }
  # shellcheck disable=SC2086  # word-splitting the intersected list is intended, as in run()
  set -- $_rl_sel
  lint_set "$@"
}

_st_clean() {  # <rc> — EXIT trap of selftest()
  if [ "$1" = 0 ]; then rm -rf "$d" "$dd" "$_sb_d"; else echo "selftest: fixtures kept in $d $dd $_sb_d" >&2; fi
}

selftest() {
  command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck --selftest: SKIP (shellcheck not installed)"; return 0; }
  d=$(mktemp -d); dd=""; _sb_d=""
  trap '_st_clean $?' EXIT  # temp dirs go on success; on failure they are kept and named
  printf '#!/bin/sh\nx="hello"\nprintf "%%s\\n" "$x"\n' > "$d/clean.sh"
  printf '#!/bin/sh\nx=$1\nif [ "$x" == "bad" ]; then echo bad; fi\n' > "$d/dirty.sh"  # SC3014 (== in POSIX sh)
  shellcheck -s sh -S warning "$d/clean.sh" >/dev/null 2>&1 || { echo "selftest FAIL: clean fixture flagged"; return 1; }
  if shellcheck -s sh -S warning "$d/dirty.sh" >/dev/null 2>&1; then
    echo "selftest FAIL: dirty fixture not flagged"; return 1
  fi
  # fail-closed: run() must FAIL on a tree containing a dirty shell file — proves run()'s own `return 1` is
  # load-bearing, not just that the shellcheck tool works. Runs in a temp cwd so collect() globs the fixture.
  # The `return 1` below is INSIDE selftest() (oracle region) so non-vacuity never neuters it (non-circular).
  dd=$(mktemp -d); mkdir -p "$dd/conformance"
  printf '#!/bin/sh\nx=$1\nif [ "$x" == "bad" ]; then echo bad; fi\n' > "$dd/conformance/dirty.sh"  # SC3014
  # if/else (not `(...); _rrc=$?`) so the subshell's expected non-zero exit doesn't trip this
  # script's own `set -eu` before the exit code can be captured.
  if ( cd "$dd" && run >/dev/null 2>&1 ); then _rrc=0; else _rrc=$?; fi
  [ "$_rrc" != 0 ] || { echo "selftest FAIL: run() did not fail on a dirty tree (fail-closed broken)"; return 1; }
  # --listed (PREPUSH-CORE-DEFAULT): lints a LISTED dirty file, ignores an UNLISTED dirty one, and is rc 2
  # on a missing listing. Same temp-cwd pattern; every `return 1` is INSIDE selftest() (non-circular).
  printf '#!/bin/sh\nx="hello"\nprintf "%%s\\n" "$x"\n' > "$dd/conformance/clean.sh"
  printf '#!/bin/sh\nx=$1\nif [ "$x" == "bad" ]; then echo bad; fi\n' > "$dd/conformance/dirty2.sh"  # SC3014
  printf 'conformance/dirty.sh\n' > "$dd/list-dirty"; printf 'conformance/clean.sh\n' > "$dd/list-clean"
  printf 'README.md\n' > "$dd/list-none"
  if ( cd "$dd" && run_listed "$dd/list-dirty" >/dev/null 2>&1 ); then _rc=0; else _rc=$?; fi
  [ "$_rc" = 1 ] || { echo "selftest FAIL: --listed did not FAIL on a listed dirty file (rc $_rc)"; return 1; }
  if _lo=$( cd "$dd" && run_listed "$dd/list-clean" 2>&1 ); then _rc=0; else _rc=$?; fi
  [ "$_rc" = 0 ] || { echo "selftest FAIL: --listed linted an UNLISTED dirty file (rc $_rc)"; return 1; }
  case $_lo in *"OK (1 kit shell file(s)"*) ;; *) echo "selftest FAIL: --listed did not lint exactly the one listed clean file: $_lo"; return 1 ;; esac
  if _lo=$( cd "$dd" && run_listed "$dd/list-none" 2>&1 ); then _rc=0; else _rc=$?; fi
  [ "$_rc" = 0 ] || { echo "selftest FAIL: --listed with no in-scope file was not rc 0 (rc $_rc)"; return 1; }
  case $_lo in *"no listed kit shell file"*) ;; *) echo "selftest FAIL: --listed zero-intersection message missing: $_lo"; return 1 ;; esac
  if ( cd "$dd" && run_listed "$dd/nope" >/dev/null 2>&1 ); then _rc=0; else _rc=$?; fi
  [ "$_rc" = 2 ] || { echo "selftest FAIL: --listed on a missing listing was not rc 2 (rc $_rc)"; return 1; }
  selftest_batches || return 1
  echo "shellcheck --selftest: OK (clean passes, dirty fails, --listed scopes, bounded batches, sources followed)"
  return 0
}

# --- SWAS-471 cells: bounded batches, verdict aggregation, no file skipped, RSS summary never the verdict.
# A stub shellcheck on PATH records what it receives; each cell also runs a MUTANT of this script (sed copy)
# and demands the cell's predicate go red on it. Every sed anchor uses a [x] class so it cannot match the
# mutator's own line. Every `return 1` is inside these selftest functions (non-circular).
_sb_run() {  # <script> — runs it in $_sb_cwd with the stubs; sets _cr (rc), output in $_sb_d/out
  rm -f "$_sb_d/calls" "$_sb_d/seen" "$_sb_d/args"
  # shellcheck disable=SC2086  # $_sb_args is "" or "--listed <file>" (a fixture path with no spaces): word-splitting is intended
  if ( cd "$_sb_cwd" && PATH="$_sb_path" STUB_LOG="$_sb_d" STUB_RSS_KB="$_sb_kb" STUB_RSS_BYTES="$_sb_bytes" STUB_VERSION="$_sb_ver" sh "$1" $_sb_args >"$_sb_d/out" 2>&1 ); then
    _cr=0
  else _cr=$?; fi
}
# _sb_harness — the gate hard-codes its batch and time binary (no env knobs), so the test edits a COPY:
# batch 3 and the stub time $_sb_tm. Each edit is checked to have applied (a no-op sed fails the selftest).
_sb_harness() {
  sed -e 's/^SC_BATCH=1$/SC_BATCH=3/' "$_sb_self" > "$_sb_d/h1.sh"
  if cmp -s "$_sb_self" "$_sb_d/h1.sh"; then echo "selftest FAIL: harness batch edit did not apply"; return 1; fi
  sed -e "s|^_sc_time=/usr/bin/time\$|_sc_time=$_sb_tm|" "$_sb_d/h1.sh" > "$_sb_d/harness.sh"
  if cmp -s "$_sb_d/h1.sh" "$_sb_d/harness.sh"; then echo "selftest FAIL: harness time edit did not apply"; return 1; fi
}
_sb_mutate() {  # <sed-expr> — mutates the harness into $_sb_d/mut.sh; refuses a mutant that did not apply
  sed -e "$1" "$_sb_d/harness.sh" > "$_sb_d/mut.sh"
  if cmp -s "$_sb_d/harness.sh" "$_sb_d/mut.sh"; then echo "selftest FAIL: mutant did not apply: $1"; return 1; fi
}
_sb_p_bound() { [ -s "$_sb_d/calls" ] && [ "$(sort -rn "$_sb_d/calls" | head -n 1)" -le 3 ] && [ "$(wc -l < "$_sb_d/calls")" -ge 3 ]; }
_sb_p_seen() { [ -s "$_sb_d/seen" ] && [ "$(sort "$_sb_d/seen" | tr '\n' ' ')" = "$_sb_want" ]; }
_sb_p_bsd() { _sb_p_green && grep -q 'shellcheck: peak RSS top-5: conformance/f1.sh+1=3MB' "$_sb_d/out"; }
_sb_p_note() { _sb_p_green && grep -q 'stub stderr note' "$_sb_d/out"; }
_sb_p_big() { _sb_p_green && grep -q '^shellcheck: peak RSS conformance/f1.sh+1=2048MB$' "$_sb_d/out"; }
_sb_p_red() { [ "$_cr" = 1 ] && grep -q 'shellcheck: FAIL' "$_sb_d/out"; }
_sb_p_green() { [ "$_cr" = 0 ] && grep -q 'shellcheck: OK' "$_sb_d/out"; }
# SWAS-499 version-branch predicates (read the stub's per-call args log, one line per shellcheck call, and the wrapper's output)
_sb_p_off() {  # >=0.10: exactly the 3 listed files get the literal flag; agent-autonomy alone loses -x; the OFF line is printed
  _sb_p_green \
    && [ "$(grep -c -e '--extended-analysis=false' "$_sb_d/args")" = 3 ] \
    && grep -qxF -e '--extended-analysis=false -s sh -S warning conformance/agent-autonomy.sh' "$_sb_d/args" \
    && grep -qxF -e '-x --extended-analysis=false -s sh -S warning scripts/tracker-read.sh' "$_sb_d/args" \
    && grep -qxF -e '-x --extended-analysis=false -s sh -S warning scripts/preflight.sh' "$_sb_d/args" \
    && grep -qxF -e '-x -s sh -S warning conformance/f1.sh' "$_sb_d/args" \
    && grep -q '^shellcheck: dataflow analysis OFF for 3 files' "$_sb_d/out"
}
_sb_p_on() {  # <0.10, or a version that cannot be read: every one of the 4 files runs as before (-x, no flag); the ON line is printed
  _sb_p_green \
    && [ "$(tr ' ' '\n' < "$_sb_d/args" | grep -c '[.]sh$')" = 4 ] \
    && [ "$(grep -vc '^-x -s sh -S warning ' "$_sb_d/args")" = 0 ] \
    && ! grep -q 'extended-analysis' "$_sb_d/args" \
    && grep -q '^shellcheck: dataflow analysis ON' "$_sb_d/out"
}
_sb_p_off0() { _sb_p_green && grep -q '^shellcheck: dataflow analysis OFF for 0 files in this run' "$_sb_d/out"; }
_sb_p_off1() { _sb_p_green && grep -q '^shellcheck: dataflow analysis OFF for 1 files in this run' "$_sb_d/out"; }
_sb_p_unlisted() { _sb_p_green && grep -qF -e 'conformance/f1.sh' "$_sb_d/args" && ! grep -F -e 'conformance/f1.sh' "$_sb_d/args" | grep -q 'extended-analysis'; }
_sb_p_vers() { _sb_p_green && grep -q 'shellcheck: OK (.*) (shellcheck 9[.]9[.]9)$' "$_sb_d/out"; }
_sb_p_headroom() { _sb_p_green && grep -q '^shellcheck: HEADROOM conformance/f1.sh+1=4097MB is above 4096 MB' "$_sb_d/out"; }
_sb_p_noheadroom() { _sb_p_green && ! grep -q 'HEADROOM' "$_sb_d/out"; }
_sb_p_nomeasure() { _sb_p_green && grep -q '^shellcheck: peak RSS: not measured' "$_sb_d/out"; }

# _sb_cell <name> <predicate> <mutant-sed-expr> — the predicate must hold on the real script, fail on the mutant.
_sb_cell() {
  _sb_harness || return 1
  _sb_run "$_sb_d/harness.sh"
  "$2" || { echo "selftest FAIL: $1 (real script)"; return 1; }
  _sb_mutate "$3" || return 1
  _sb_run "$_sb_d/mut.sh"
  if "$2"; then echo "selftest FAIL: $1 mutant survived (cell is vacuous)"; return 1; fi
}

selftest_batches() {
  _sb_d=$(mktemp -d); mkdir -p "$_sb_d/bin" "$_sb_d/fx/conformance" "$_sb_d/fx2/conformance" "$_sb_d/fx3/conformance" "$_sb_d/fx4/conformance" "$_sb_d/fx4/scripts"
  _sb_real="$PATH"; _sb_path="$_sb_d/bin:$PATH"; _sb_bytes=""; _sb_ver=0.11.0; _sb_args=""
  _sb_self=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
  cat > "$_sb_d/bin/shellcheck" <<'EOF'
#!/bin/sh
# --version answers $STUB_VERSION and exits BEFORE anything is logged ("junk" = garbage text and rc 1)
if [ "${1:-}" = --version ]; then
  [ "${STUB_VERSION:-}" != junk ] || { echo "not a version line"; exit 1; }
  printf 'ShellCheck - shell script analysis tool\nversion: %s\nlicense: GNU\n' "${STUB_VERSION:-0.11.0}"
  exit 0
fi
rc=0; n=0
for a in "$@"; do case $a in conformance/*) n=$((n + 1)); echo "$a" >> "$STUB_LOG/seen"
  case $a in *FAILME*) echo "stub finding in $a"; rc=1 ;; esac ;; esac; done
echo "$n" >> "$STUB_LOG/calls"
echo "$*" >> "$STUB_LOG/args"
echo "stub stderr note" >&2
exit "$rc"
EOF
  # BSD-time lookalikes: only -l, report (bytes) on stderr AFTER running the command; the liar never runs it
  cat > "$_sb_d/bin/faketimebsd" <<'EOF'
#!/bin/sh
[ "${1:-}" = "-l" ] || exit 1
shift
"$@"; rc=$?
[ -z "${STUB_RSS_BYTES:-}" ] || printf '%12s  maximum resident set size\n' "$STUB_RSS_BYTES" >&2
exit "$rc"
EOF
  cat > "$_sb_d/bin/lietimebsd" <<'EOF'
#!/bin/sh
[ "${1:-}" = "-l" ] || exit 1
printf '%12s  maximum resident set size\n' 1 >&2
exit 0
EOF
  cat > "$_sb_d/bin/faketime" <<'EOF'
#!/bin/sh
out=""
while [ "$#" -gt 0 ]; do case $1 in -v) shift ;; -o) out=$2; shift 2 ;; *) break ;; esac; done
if [ -n "$out" ] && [ -n "${STUB_RSS_KB:-}" ]; then printf '\tMaximum resident set size (kbytes): %s\n' "$STUB_RSS_KB" > "$out"; fi
exec "$@"
EOF
  # a "time" that writes the GNU line but exits 0 WITHOUT running its command (the /usr/bin/true shape)
  cat > "$_sb_d/bin/lietime" <<'EOF'
#!/bin/sh
out=""
while [ "$#" -gt 0 ]; do case $1 in -v) shift ;; -o) out=$2; shift 2 ;; *) break ;; esac; done
if [ -n "$out" ]; then printf '\tMaximum resident set size (kbytes): 1\n' > "$out"; fi
exit 0
EOF
  chmod +x "$_sb_d/bin/shellcheck" "$_sb_d/bin/faketime" "$_sb_d/bin/lietime" "$_sb_d/bin/faketimebsd" "$_sb_d/bin/lietimebsd"
  for _n in f1 f2 f3-FAILME f4 f5 f6 f7; do : > "$_sb_d/fx/conformance/$_n.sh"; done
  for _n in f1 f2; do : > "$_sb_d/fx2/conformance/$_n.sh"; done
  # fx4 (SWAS-499): the three files the >=0.10 branch treats apart, plus one ordinary file
  : > "$_sb_d/fx4/conformance/agent-autonomy.sh"; : > "$_sb_d/fx4/conformance/f1.sh"
  : > "$_sb_d/fx4/scripts/tracker-read.sh"; : > "$_sb_d/fx4/scripts/preflight.sh"
  _sb_want="conformance/f1.sh conformance/f2.sh conformance/f3-FAILME.sh conformance/f4.sh conformance/f5.sh conformance/f6.sh conformance/f7.sh "
  _sb_cwd="$_sb_d/fx"; _sb_tm="$_sb_d/none"; _sb_kb=""
  _sb_cell "batch bound (no call gets more than 3 files)" _sb_p_bound 's/"[$]_b" -lt "[$]SC_BATCH"/1 -eq 1/' || return 1
  _sb_cell "verdict aggregation (one failing file among several is red)" _sb_p_red 's/ || _ls_rc=[1]$/ \&\& _ls_rc=0 || _ls_rc=1/' || return 1
  _sb_cell "no file skipped (stub saw exactly the input set)" _sb_p_seen \
    's/while \[ "[$]#" -gt 0 \]; do  # batches/while [ "$#" -gt "$SC_BATCH" ]; do  # batches/' || return 1
  # SWAS-499: no usable time binary is SAID, never silent (the CI conformance-core probe makes measurement mandatory there)
  _sb_cwd="$_sb_d/fx2"
  _sb_cell "no time binary: the summary says peak RSS was not measured" _sb_p_nomeasure '/peak RSS[:] not measured/d' || return 1
  _sb_cwd="$_sb_d/fx"
  # RSS summary: a clean run with GNU-time data stays green AND prints top-5; with NO data it is still green.
  _sb_cwd="$_sb_d/fx2"; _sb_tm="$_sb_d/bin/faketime"; _sb_kb=2048
  _sb_harness || return 1
  _sb_run "$_sb_d/harness.sh"
  { _sb_p_green && grep -q 'shellcheck: peak RSS top-5: conformance/f1.sh+1=2MB' "$_sb_d/out" && ! grep -q 'peak RSS conformance' "$_sb_d/out"; } \
    || { echo "selftest FAIL: RSS top-5 line missing or verdict not green with a GNU-time stub"; return 1; }
  _sb_kb=""
  _sb_cell "RSS summary never changes the verdict" _sb_p_green 's/print_rss_top5 || [:]$/print_rss_top5 || _ls_rc=1/' || return 1
  # A time that exits 0 without running its command must not make the gate green with nothing linted.
  _sb_tm="$_sb_d/bin/lietime"; _sb_kb=1
  _sb_want="conformance/f1.sh conformance/f2.sh "
  _sb_cell "a non-running time binary never leaves files unlinted" _sb_p_seen 's/ && \[ -f "[$]_sc_tmp\/ran" \]//' || return 1
  # BSD time (macOS): bytes -> MB, shellcheck's own stderr still reaches the user, a liar never skips linting.
  _sb_tm="$_sb_d/bin/faketimebsd"; _sb_kb=""; _sb_bytes=3145728
  _sb_cell "BSD time: bytes become MB in the top-5 line" _sb_p_bsd 's/then _rr_kb=[$]((_rr_kb \/ 1024))/then _rr_kb=$((_rr_kb))/' || return 1
  _sb_cell "BSD time: shellcheck's own stderr still reaches the user" _sb_p_note 's/exec "[$]@" 2>&3/exec "$@" 2>\/dev\/null/' || return 1
  _sb_tm="$_sb_d/bin/lietimebsd"
  _sb_cell "a non-running BSD time never leaves files unlinted" _sb_p_seen 's/ && \[ -f "[$]_sc_tmp\/ran" \]//' || return 1
  # a file above 1 GB is named at once (a process can die before the summary); small ones are not
  _sb_tm="$_sb_d/bin/faketime"; _sb_kb=2097152; _sb_bytes=""
  _sb_cell "a file above 1 GB is named as it finishes" _sb_p_big 's/-le 104857[6] ]/-le 99999999 ]/' || return 1
  # SWAS-499 HEADROOM: warn-only above 4096 MB (half the 7.9 GB CI runner). Over the line it names the file and stays GREEN; at the line it is silent.
  _sb_kb=4194305
  _sb_cell "HEADROOM: a file above 4096 MB is named, and the verdict stays green" _sb_p_headroom 's/-le 419430[4]/-le 99999999/' || return 1
  _sb_kb=4194304
  _sb_cell "HEADROOM: a file at exactly 4096 MB is not named" _sb_p_noheadroom 's/-le 419430[4]/-lt 4194304/' || return 1
  # SWAS-499 version branches. The stub answers `--version` from _sb_ver; the wrapper's choice is read off the per-call args log.
  _sb_cwd="$_sb_d/fx4"; _sb_tm="$_sb_d/none"; _sb_kb=""; _sb_bytes=""
  _sb_ver=0.11.0
  _sb_cell "0.11.0: 3 listed files get exactly --extended-analysis=false, agent-autonomy loses -x, the rest unchanged" _sb_p_off 's/_sc_reduced=[1]/_sc_reduced=0/' || return 1
  _sb_cell "0.11.0: an unlisted file never gets the flag" _sb_p_unlisted 's/[*]" [$]1 "[*]) return 0/*) return 0/' || return 1
  # --listed: the OFF line counts the files of THIS run that sit on the literal list (a listing with none of them says 0, one with one says 1)
  printf 'conformance/f1.sh\n' > "$_sb_d/list-f1"; printf 'conformance/f1.sh\nscripts/preflight.sh\n' > "$_sb_d/list-two"
  _sb_args="--listed $_sb_d/list-f1"
  _sb_cell "--listed with none of the 3 files: the OFF line says 0" _sb_p_off0 's/_ls_off=[0]  #/_ls_off=3  #/' || return 1
  _sb_args="--listed $_sb_d/list-two"
  _sb_cell "--listed with one of the 3 files: the OFF line says 1" _sb_p_off1 's/_ls_off=[$]((_ls_off + 1))/_ls_off=$((_ls_off + 2))/' || return 1
  _sb_args=""
  _sb_ver=0.10.0
  _sb_cell "0.10.0 (the boundary): the reduced branch" _sb_p_off 's/"[$]_sp_minor" -ge 10/"$_sp_minor" -gt 10/' || return 1
  _sb_ver=1.0.0
  _sb_cell "1.0.0 (a major bump, minor 0): the reduced branch" _sb_p_off 's/\[ "[$]_sp_major" -gt 0 \] || //' || return 1
  _sb_ver=0.9.0
  _sb_cell "0.9.0: every file lints as before and the ON line is printed" _sb_p_on 's/if \[ "[$]_sp_major" -gt 0 \] || \[ "[$]_sp_minor" -ge 10 \]; then/if true; then/' || return 1
  _sb_ver=junk
  _sb_cell "an unreadable version (garbage, exit 1): no abort under set -eu, treated as old" _sb_p_on 's/if _sp_o=[$](shellcheck --version 2>\/dev\/null); then/_sp_o=$(shellcheck --version 2>\/dev\/null); if true; then/' || return 1
  _sb_cell "an unreadable version is never routed to the reduced branch" _sb_p_on 's/\[ -n "[$]_sc_ver" \] || return 0/[ -n "$_sc_ver" ] || { _sc_reduced=1; return 0; }/' || return 1
  _sb_ver=9.9.9
  _sb_cell "the verdict line names the shellcheck version" _sb_p_vers 's/shellcheck [$]{_sc_ver:-unknown}/shellcheck 0.0.0/' || return 1
  _sb_ver=0.11.0
  # REAL shellcheck, per file: a caller sets LIBVAR for a SOURCED library that reads it. Clean only if the
  # source is followed from disk; the -x-less mutant must red it with SC2034 (the 6 findings of the 832f4ccb run).
  # The library lives in lib/ (outside collect()'s scope), so ONLY the caller is an input and only -x can
  # resolve the source: a constant path with no directive, relative to the fixture root = the run's cwd.
  mkdir -p "$_sb_d/fx3/lib"
  printf '#!/bin/sh\nLIBVAR=yes\n. lib/lib.sh\n' > "$_sb_d/fx3/conformance/caller.sh"
  printf '#!/bin/sh\necho "${LIBVAR:-}"\n' > "$_sb_d/fx3/lib/lib.sh"
  _sb_cwd="$_sb_d/fx3"; _sb_tm="$_sb_d/none"; _sb_path="$_sb_real"
  _sb_cell "a sourced library's variable is not reported unused (sources followed)" _sb_p_green 's/shellcheck [-]x/shellcheck/' || return 1
  return 0
}

case "${1:-}" in
  --selftest) selftest ;;
  --listed)   [ "$#" -eq 2 ] || { echo "usage: shellcheck.sh --listed <listing-file>" >&2; exit 2; }
              run_listed "$2" ;;
  "")         run ;;
  *)          echo "usage: shellcheck.sh [--selftest | --listed <listing-file>]" >&2; exit 2 ;;
esac
exit $?
