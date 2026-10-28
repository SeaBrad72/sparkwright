#!/bin/sh
# verify.sh — honest aggregate conformance runner. Classifies each check:
#   [control] — verifies a live/remote/structural WORKING control
#   [doc]     — verifies DOCUMENTATION / recorded evidence EXISTS (not that it was tested)
# Prints PASS/FAIL/UNVERIFIED/N-A per check + an honest summary footer. THREE non-FAIL outcomes, and
# they are NOT interchangeable: PASS = it ran and proved its claim · UNVERIFIED (rc 2) = it could not
# run, and is a FAIL under --require/CI · N-A = it declined to verify here and SAID SO (a --kitself row
# on an adopter tree, or a child that self-skipped on rc 0) — never blocking, never an OK. Exit policy:
#   non-zero if any [control] check FAILS, or (under --require / CI) any check is UNVERIFIED.
#   [doc] checks that are present-but-untested PASS — honestly labelled, not hidden.
# MISCONFIGURED splits rc 2: a row whose child answers with `usage: <that child's basename>` was
# INVOKED WRONG by this file's own registry — a wiring bug, not an environment one — so it FAILS
# ALWAYS, not only under --require (VERIFY-RC2-USAGE-OVERLOAD). ⚠️ SAFETY DIRECTION IS INVERTED HERE,
# and it is the first prose heuristic in this file that BLOCKS: everywhere else a false hit under-
# claims (a real proof renders N-A — visible, never green-while-dark), but a false hit HERE reds a
# legitimate row. The child-basename anchor is what carries that risk down: a bare `^usage:` key would
# also match a NESTED child's usage bubbling up through a wrapper (measured at ci-gates.sh:457). A
# check that prints its usage text in some other shape stays UNVERIFIED — the marker is a convention.
# A green run proves controls hold AND release/DR/resilience safety is DOCUMENTED — NOT
# that those procedures were tested. See conformance/README.md "What a green run means".
# SCOPE: this is a curated aggregate of the repo-runnable checks — NOT every conformance
# script. Checks needing project context or live creds (e.g. inception-done, tracker-contract,
# stack-selection — repo-admin creds it can't have in least-privilege CI; verified at the
# governance gate, see its header) and conditionally-wired checks (e.g. container-supply-chain)
# run in their own CI steps / at the adopter's gate, not here. branch-protection.sh is now SPLIT at
# the credential seam (B4): its OFFLINE declaration-integrity leg (--declared-only — no gh, no
# network) IS registered below; its LIVE forge-comparison leg still needs repo-admin gh and runs
# operator-side, not here. "aggregate" means representative.
#   usage: sh conformance/verify.sh [--require] [--changed <listing-file>] [--summary-file <path>] [--timing-file <path>] [--output-file <path>] | --selftest [--from-output <path>]
#
# ADOPTER-KIT-SELFTESTS-ON-CHANGE — `--changed <listing>` (a newline-delimited changed-paths file) lets an
# ADOPTER's pull-request run skip the rows flagged `--kitselftest` (the kit's own selftests, whose subject
# cannot have changed) and render them N-A. The skip fires ONLY when the listing is a readable, non-empty
# file AND `conformance/promotion-readiness.sh --class --changed <listing>` exits 0 and answers `ordinary` or
# `sensitive`. Everything else — no --changed, an empty/unreadable listing, a classifier failure or unknown
# answer, class `control-plane` — runs the FULL battery: every unknown costs time, never coverage. One notice
# line `kit selftests not re-run: …` precedes the Summary; `--summary-file <path>` also receives it. A run with no --changed is
# byte-for-byte the old behaviour. Design: docs/architecture/2026-10-01-adopter-kit-selftests-on-change-design.md.
# A LITERAL FORCED-FULL FLOOR (below, _ks_floor_hit) sits in front of the classifier: any listed control-plane-shaped path
# (.claude/, conformance/, scripts/, hooks/, adapters/, profiles/, .github/, .kit/, a .gitattributes / .shellcheckrc basename,
# docs/roadmap-kit.md, case-folded, plus any CR byte) forces the full battery without consulting the classifier.
# TEST SEAMS (test affordances for a TRUSTED LOCAL shell, not a security boundary): VERIFY_SELFTEST_REGISTRY=<file>
# (sourced in place of the built-in registry) and VERIFY_CLASSIFIER=<script> (in place of the real classifier). The seams
# are REFUSED outright (error, exit 2) when CI or GITHUB_ACTIONS is set, and any run that uses one is tainted: a loud
# stderr banner and an UNVERIFIED exit 2 whatever the rows did. A sourced registry runs in-process, so this is not a sandbox.
set -eu
# Refuse the test seams under CI BEFORE doing anything else (ADOPTER-KIT-SELFTESTS-ON-CHANGE fix round 1, S3).
if { [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; } && { [ -n "${VERIFY_SELFTEST_REGISTRY:-}" ] || [ -n "${VERIFY_CLASSIFIER:-}" ]; }; then
  echo "verify: REFUSED — VERIFY_SELFTEST_REGISTRY / VERIFY_CLASSIFIER are test seams and are not honoured when CI or GITHUB_ACTIONS is set" >&2
  exit 2
fi
# REVIEW R1: resolve THIS script's absolute path BEFORE the cd — `cd conformance && sh ./verify.sh`
# leaves $0 as a relative path that no longer resolves once we have moved up a directory.
_SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
_KS_ORIG_PWD=$(pwd)   # a relative --changed / --summary-file path means relative to the CALLER, not the repo root

# ── CI-DEDUP-VERIFY-SELFTEST-NESTED (SWAS-282) — grade the ENFORCED run's record instead of re-running it ───
# Two opt-in options, inert for a caller who never passes them (a run without them is today's run, byte for byte):
#   --output-file <path>            beside --require: run the aggregate once and ALSO write a provenance-stamped
#                                   record of it to <path> (header: head, verify.sh cksum, working-tree cksum,
#                                   require, changed · the run's combined output · trailer: rc, line count).
#   --selftest --from-output <path> grade that record in place of the nested aggregate run the selftest used to do.
# The path should sit OUTSIDE the working tree (CI: $RUNNER_TEMP): a record inside it is an untracked file the
# `dirty` checksum then sees. Design: docs/architecture/2026-10-16-ci-dedup-verify-selftest-nested-design.md.
# The functions below are PURE (their positional parameters and the named file only), so --selftest drives the
# shipped code on fixtures. SEMGREP: a one-line case-esac is rejected by the SAST parse step, so esac stays on its own line.

# _vs_from_mode <args...> -> `nested` | `file <path>` | `error`. The selection is an ARGUMENT, never the environment:
# the loop variables are assigned empty first, so an inherited variable of the same name is overwritten.
_vs_from_mode() {
  _vm_n=0; _vm_path=""; _vm_prev=""; _vm_a=""; _vm_first=${1:-}
  for _vm_a in "$@"; do
    if [ "$_vm_prev" = "--from-output" ]; then _vm_path=$_vm_a; fi
    if [ "$_vm_a" = "--from-output" ]; then _vm_n=$((_vm_n+1)); fi
    _vm_prev=$_vm_a
  done
  if [ "$_vm_n" = 0 ]; then echo nested; return 0; fi
  # (not one `if` line carrying the first-word test: the mass budget prices the selftest marker off such a line)
  if [ "$_vm_first" = "--selftest" ] && [ "$_vm_n" = 1 ] && [ -n "$_vm_path" ]; then printf 'file %s\n' "$_vm_path"; return 0; fi
  echo error   # a stray flag (no --selftest first), a doubled flag, or no value: never falls back to nested
}

# _vs_probe_line <rendered-output> -> the one line `renderer probe: agent-autonomy <PASS|N-A|FAIL|UNVERIFIED|MISCONFIGURED|absent>` (SWAS-376;
# `absent` also for two or more anchored rows; the lane reads everything but N-A and PASS as not run/unknown).
# The selftest's nested aggregate run (the renderer probe) grades RENDERING only, so its agent-autonomy row is paid for and never read; the
# hermetic lane reads this line instead, to say on green as well as red whether a face deferred the battery to `guard-battery` (N-A) or ran
# it (PASS). The match is the whole rendered row, anchored: a longer row name (`agent-autonomy-alias`) or a [doc] row never matches.
# Deferred or not, never why: a fallback's NOTE is discarded inside check() and does not reach the rendered output.
_vs_probe_line() {
  _pl_v=absent
  # exactly ONE anchored row, as the lane's one-line rule wants; two or more are not one battery, so `absent`
  _pl_n=$(printf '%s\n' "$1" | grep -Ec '^  \[control\] agent-autonomy +(PASS|N-A|FAIL|UNVERIFIED|MISCONFIGURED)$') || _pl_n=0
  if [ "$_pl_n" = 1 ]; then
    for _pl_t in PASS N-A FAIL UNVERIFIED MISCONFIGURED; do
      if printf '%s\n' "$1" | grep -Eq "^  \[control\] agent-autonomy +$_pl_t\$"; then _pl_v=$_pl_t; break; fi
    done
  fi
  printf 'renderer probe: agent-autonomy %s\n' "$_pl_v"
}

# _vs_record_field <header-or-trailer-line> <key> -> the value of ` key=value`
_vs_record_field() { printf '%s\n' "$1" | sed -n "s/.* $2=\\([^ ]*\\).*/\\1/p"; }

# _vs_record_check <path> <head> <self> <dirty> : 0 = the record is a complete, fresh, full enforced run;
# otherwise print the reason and return 1. Reads ONLY the file and its arguments (the caller supplies the live values).
_vs_record_check() {
  _rc_f=$1
  if [ ! -f "$_rc_f" ] || [ ! -r "$_rc_f" ]; then echo "not a readable file"; return 1; fi
  if [ ! -s "$_rc_f" ]; then echo "empty: the file has no bytes"; return 1; fi
  _rc_h=$(sed -n 1p "$_rc_f")
  case "$_rc_h" in
    "verify-output-file: v1 head="*" self="*" dirty="*" require="*" changed="*) ;;
    *) echo "foreign: not written by verify.sh --output-file"; return 1 ;;
  esac
  # SWAS-393 (S3): a fifth argument `shard` asks for a ROW-SHARD record (its header carries ` shard=i/N`); the default asks for a full
  # run, which a shard record is NOT (--selftest --from-output would otherwise grade a partial run as the whole aggregate).
  _rc_sh=$(_vs_record_field "$_rc_h" shard)
  if [ "${5:-full}" = shard ] && [ -z "$_rc_sh" ]; then echo "not a shard record (no shard= field)"; return 1; fi   # MG:shardmode
  if [ "${5:-full}" != shard ] && [ -n "$_rc_sh" ]; then echo "a shard record, not a full enforced run (grade it with --merge)"; return 1; fi   # MG:fullmode
  _rc_hd=$(_vs_record_field "$_rc_h" head)
  if [ -z "$_rc_hd" ] || [ "$_rc_hd" = none ] || [ "$2" = none ] || [ "$_rc_hd" != "$2" ]; then
    echo "stale: written at another commit"; return 1
  fi
  if [ "$(_vs_record_field "$_rc_h" self)" != "$3" ]; then echo "stale: written by another verify.sh"; return 1; fi
  if [ "$(_vs_record_field "$_rc_h" dirty)" != "$4" ]; then echo "stale: the working tree changed since the record"; return 1; fi
  if [ "$(_vs_record_field "$_rc_h" require)" != 1 ] || [ "$(_vs_record_field "$_rc_h" changed)" != 0 ]; then
    echo "not a full enforced run (require must be 1 and changed 0)"; return 1
  fi
  _rc_t=$(tail -n 1 "$_rc_f")
  case "$_rc_t" in
    "verify-output-end: v1 rc="*" lines="*) ;;
    *) echo "truncated: no end line"; return 1 ;;
  esac
  _rc_rc=$(_vs_record_field "$_rc_t" rc); _rc_ln=$(_vs_record_field "$_rc_t" lines)
  case "${_rc_rc}x${_rc_ln}" in
    x*|*x|*[!0-9x]*) echo "truncated: the end line carries no numeric rc and lines"; return 1 ;;
  esac
  if [ "$(( $(sed -n '$=' "$_rc_f") - 2 ))" != "$_rc_ln" ]; then echo "truncated or edited: lines= disagrees with the body"; return 1; fi
  _rc_body=$(sed '1d;$d' "$_rc_f")
  if printf '%s\n' "$_rc_body" | grep -q '^RESULT: FAIL (INCOMPLETE'; then echo "interrupted run: the body carries an INCOMPLETE verdict"; return 1; fi
  case "$(printf '%s\n' "$_rc_body" | tail -n 1)" in
    "RESULT: OK"*) _rc_v=ok ;;
    "RESULT: FAIL"*) _rc_v=fail ;;
    *) echo "no verdict: the body does not end in RESULT: OK or RESULT: FAIL (a crash, or a test-seam run)"; return 1 ;;
  esac
  if { [ "$_rc_rc" = 0 ] && [ "$_rc_v" = fail ]; } || { [ "$_rc_rc" != 0 ] && [ "$_rc_v" = ok ]; }; then
    echo "the exit status and the RESULT line disagree"; return 1
  fi
  return 0
}

# _vs_load_record <path> : the selftest's source switch for --from-output. Hands the LIVE head, this script's cksum and
# the working-tree cksum to the pure check; on success sets `out` (the body) and `_vs_src`; on ANY refusal prints
# `verify --selftest: FAIL (from-output: <reason> — <path>)` and returns 1. It never falls back to the nested run.
_vs_load_record() {
  _vl_p=$1
  if [ "${_vl_p#/}" = "$_vl_p" ]; then _vl_p="$_KS_ORIG_PWD/$_vl_p"; fi
  _vl_hd=$(git rev-parse HEAD 2>/dev/null) || _vl_hd=none
  if [ -z "$_vl_hd" ]; then _vl_hd=none; fi
  _vl_sf=$(cksum < "$_SELF" | tr ' ' '-')
  _vl_dt=$(git status --porcelain --untracked-files=all 2>/dev/null | cksum | tr ' ' '-')
  # Copy the record ONCE into a private mktemp and check and read that copy only (review L3): the file that was
  # validated is then the file that is graded, whatever happens to <path> in between. A path that cannot be copied
  # is handed to the check as it is, which names the true reason (missing, unreadable, not a regular file).
  _vl_c=$(mktemp "${TMPDIR:-/tmp}/verify-rec-copy.XXXXXX" 2>/dev/null) || _vl_c=""
  _vl_u=$_vl_p
  if [ -f "$_vl_p" ] && [ -r "$_vl_p" ]; then
    if [ -z "$_vl_c" ] || ! cp "$_vl_p" "$_vl_c" 2>/dev/null; then
      if [ -n "$_vl_c" ]; then rm -f "$_vl_c"; fi
      echo "verify --selftest: FAIL (from-output: cannot take a private copy of the record — $_vl_p)"
      return 1
    fi
    _vl_u=$_vl_c
  fi
  if ! _vl_why=$(_vs_record_check "$_vl_u" "$_vl_hd" "$_vl_sf" "$_vl_dt"); then
    if [ -n "$_vl_c" ]; then rm -f "$_vl_c"; fi
    echo "verify --selftest: FAIL (from-output: $_vl_why — $_vl_p)"
    return 1
  fi
  out=$(sed '1d;$d' "$_vl_u")
  if [ -n "$_vl_c" ]; then rm -f "$_vl_c"; fi
  _vs_src="recorded run at $(printf '%s' "$_vl_hd" | cut -c1-8)"
  return 0
}

# _vs_ci_shape <workflow-file> : 0 when every job that records (--require --output-file P) also grades the SAME
# record in a --selftest --from-output P line, and no uncommented --selftest line lacks --from-output (a dropped flag
# silently re-nests the aggregate). The grading step must also be able to FAIL the job (review M1): no continue-on-error
# on it or its job, no step `if:` other than exactly the not-cancelled expression, and no shell tail (a pipe, a semicolon
# or an ampersand) after its command. SWAS-393: a job that runs `verify.sh --shard` writes a PARTIAL record, so it is not a recorder
# and is not graded here — but it must feed a job that runs `--merge`, which lists it in `needs:` (block list or inline), so a
# shard can never be the only verdict. Else print why and return 1. Comment lines never count.
_vs_ci_shape() {
  if _sh_msg=$(LC_ALL=C awk '
    { l = $0; sub(/^[ \t]+/, "", l); ind = match($0, /[^ ]/) - 1 }
    $0 ~ /^  [A-Za-z0-9_-]+:/ { job = $1; sub(/:.*/, "", job); inst = 0; cur = 0 }
    substr(l, 1, 1) == "#" || l == "" { next }
    ind <= 4 && !(ind == 4 && l ~ /^needs:/) { innd = 0 }
    ind == 4 && l ~ /^needs:/ { innd = 1; v = l; sub(/^needs:[ \t]*/, "", v); sub(/[ \t]+#.*/, "", v); gsub(/[][,]/, " ", v); needs[job] = needs[job] " " v " "; next }
    innd && ind > 4 && l ~ /^- / { v = substr(l, 3); sub(/[ \t]+#.*/, "", v); needs[job] = needs[job] " " v " "; next }
    { isnew =(substr(l, 1, 2) == "- " && (!inst || ind <= sind)) }
    isnew { nst++; cur = nst; inst = 1; sind = ind; att = 1; l = substr(l, 3); sub(/^[ \t]+/, "", l) }
    !isnew && inst && ind <= sind { inst = 0; cur = 0 }
    !isnew && inst { att = (ind == sind + 2) }
    !inst && ind == 4 && l ~ /^continue-on-error:/ { v = l; sub(/^continue-on-error:[ \t]*/, "", v); if (v != "false") jobcoe[job] = 1 }
    inst && att && l ~ /^if:/ { v = l; sub(/^if:[ \t]*/, "", v); sub(/[ \t]+$/, "", v); hasif[cur] = 1; sif[cur] = v }
    inst && att && l ~ /^continue-on-error:/ { v = l; sub(/^continue-on-error:[ \t]*/, "", v); if (v != "false") scoe[cur] = 1 }
    index(l, "conformance/verify.sh") == 0 { next }
    {
      n = split(l, w, " "); rec = 0; sel = 0; op = ""; fo = ""; shd = 0; mrg = 0
      for (i = 1; i <= n; i++) {
        if (w[i] == "--require" || w[i] == "--merge") rec = 1
        if (w[i] == "--merge") mrg = 1
        if (w[i] == "--shard") shd = 1   # SWAS-393: a row-shard leg writes a PARTIAL record that only --merge grades; it is not graded here
        if (w[i] == "--selftest") sel = 1
        if (w[i] == "--output-file") op = w[i + 1]
        if (w[i] == "--from-output") fo = w[i + 1]
      }
      if (sel && fo == "") bare = bare " " job
      if (sel && fo != "") {
        k = job SUBSEP fo; grade[k] = 1; gstep[k] = gstep[k] " " cur
        tail = substr(l, index(l, "--from-output") + 13); sub(/^[ \t]+[^ \t]+/, "", tail); sub(/[ \t]#.*/, "", tail)
        if (tail ~ /[|;&]/) badtail[k] = 1
      }
      if (rec && op != "" && !shd) recd[job SUBSEP op] = 1
      if (shd) shardjob[job] = 1
      if (mrg) mergejob[job] = 1
    }
    END {
      for (sj in shardjob) {   # SWAS-393: a shard job is a partial run, so it must feed a --merge job (never be a verdict on its own)
        ok = 0
        for (mj in mergejob) if (index(needs[mj], " " sj " ") > 0) ok = 1
        if (!ok) { print "job " sj " runs verify.sh --shard but no --merge job lists it in needs: (a shard is a partial run and may not be a verdict on its own)"; bad = 1 }
      }
      if (bare != "") { print "an uncommented verify.sh --selftest line in job" bare " has no --from-output (it would re-run the aggregate nested)"; bad = 1 }
      for (k in recd) if (!(k in grade)) { split(k, p, SUBSEP); print "job " p[1] " records " p[2] " with --output-file but never grades that record with --selftest --from-output"; bad = 1 }
      for (k in recd) if (k in grade) {
        split(k, p, SUBSEP)
        if (jobcoe[p[1]]) { print "job " p[1] " sets continue-on-error, so its grading step can never fail the job"; bad = 1 }
        if (badtail[k]) { print "job " p[1] ": the grading command is followed by a pipe, semicolon or ampersand that can mask its exit status"; bad = 1 }
        ns = split(gstep[k], sl, " ")
        for (i = 1; i <= ns; i++) {
          if (scoe[sl[i]]) { print "job " p[1] ": the grading step sets continue-on-error, so it can never fail the job"; bad = 1 }
          if (hasif[sl[i]] && sif[sl[i]] != "${{ !cancelled() }}") { print "job " p[1] ": the grading step has an if: other than exactly ${{ !cancelled() }}, so it may never run"; bad = 1 }
        }
      }
      exit (bad ? 3 : 0)
    }' "$1"); then return 0; fi
  echo "$_sh_msg"; return 1
}

# ── ROW-SHARDS (SWAS-393, slice S3 of SWAS-314; design 2026-10-24-ci-shaping section 4.2; controls C6, C7, C8) ───────────────
# `--require --shard <i>/<N> --output-file F` runs the registry rows whose ORDINAL (the 1-based position of the `check` call) mod N
# is i-1, writes the rows' lines, then a `Shard-rows: i/N <ordinal>:<name>...` line and a `Shard-counts:` line, and records the run
# in SWAS-282's record, whose header gains ` shard=i/N tree=<git write-tree>` (the tree and the working-tree checksum are taken
# BEFORE the run: the join compares the tree a shard STARTED from). The agent-autonomy row is never run in a shard; it is written
# JOIN. `--merge [--battery <dir>] <records...>` refuses unless every record is fresh (_vs_record_check, shard mode), graded in
# this tree, and the coordinates, the rows and the union are exactly the registry's; it then grades the battery row through
# `agent-autonomy.sh --join`, rebuilds the rows in registry order, sums the counters and falls through to the SAME footer a plain
# run prints. The selection is an ARGUMENT, never the environment. Each refusal line below ends in a `# MG:<tag>` comment: the
# --selftest strips the refusal from the shipped text and requires its leg to fail (the mutant), so a tag is load-bearing.

# _rs_usage <args...> : the row-shard flags are valid only as `--shard <i>/<N>` (once, 1 <= i <= N, beside --require or CI, never with
# --merge, --selftest or --changed) or as the FIRST word `--merge` (once; never with --shard or --changed), and `--battery <dir>` only
# after --merge. Prints the refusal and returns 1 (the caller exits 2). Reads its arguments only.
_rs_usage() {
  _ru_first=${1:-}; _ru_prev=""; _ru_sh=0; _ru_shv=""; _ru_mg=0; _ru_bt=0; _ru_btv=""; _ru_req=0; _ru_chg=0; _ru_a=""
  for _ru_a in "$@"; do
    if [ "$_ru_prev" = "--shard" ]; then _ru_shv=$_ru_a; fi
    if [ "$_ru_prev" = "--battery" ]; then _ru_btv=$_ru_a; fi
    case "$_ru_a" in
      --shard) _ru_sh=$((_ru_sh+1)) ;;
      --merge) _ru_mg=$((_ru_mg+1)) ;;
      --battery) _ru_bt=$((_ru_bt+1)) ;;
      --require) _ru_req=1 ;;
      --changed) _ru_chg=1 ;;
    esac
    _ru_prev=$_ru_a
  done
  if [ "$_ru_mg" -gt 0 ] && [ "$_ru_first" != "--merge" ]; then echo "--merge must be the FIRST word"; return 1; fi   # MG:u-merge-first
  if [ "$_ru_mg" -gt 1 ]; then echo "--merge given twice"; return 1; fi   # MG:u-merge-twice
  if [ "$_ru_bt" -gt 0 ] && [ "$_ru_mg" = 0 ]; then echo "--battery is valid only with --merge"; return 1; fi   # MG:u-battery-alone
  if [ "$_ru_bt" -gt 1 ]; then echo "--battery given twice"; return 1; fi   # MG:u-battery-twice
  if [ "$_ru_bt" = 1 ] && { [ -z "$_ru_btv" ] || [ "${_ru_btv#--}" != "$_ru_btv" ]; }; then echo "--battery needs a directory"; return 1; fi   # MG:u-battery-value
  if [ "$_ru_sh" -gt 1 ]; then echo "--shard given twice"; return 1; fi   # MG:u-shard-twice
  if [ "$_ru_sh" = 1 ]; then
    _ru_ok=1
    case "$_ru_shv" in
      [1-9]*/[1-9]*) ;;
      *) _ru_ok=0 ;;
    esac
    case "${_ru_shv%/*}${_ru_shv#*/}" in
      *[!0-9]*) _ru_ok=0 ;;
    esac
    if [ "${#_ru_shv}" -gt 7 ]; then _ru_ok=0; fi
    if [ "$_ru_ok" = 1 ] && [ "${_ru_shv%/*}" -gt "${_ru_shv#*/}" ]; then _ru_ok=0; fi
    if [ "$_ru_ok" = 0 ]; then echo "--shard needs <i>/<N> with 1 <= i <= N (got '$_ru_shv')"; return 1; fi   # MG:u-shard-format
  fi
  if [ "$_ru_sh" = 1 ] && [ "$_ru_mg" -gt 0 ]; then echo "--shard and --merge are exclusive"; return 1; fi   # MG:u-shard-merge
  if [ "$_ru_sh" = 1 ] && [ "$_ru_first" = "--selftest" ]; then echo "--shard cannot be combined with --selftest"; return 1; fi   # MG:u-shard-selftest
  if [ "$_ru_sh" = 1 ] && [ "$_ru_chg" = 1 ]; then echo "--shard runs every row: it cannot be combined with --changed"; return 1; fi   # MG:u-shard-changed
  if [ "$_ru_mg" -gt 0 ] && [ "$_ru_chg" = 1 ]; then echo "--merge grades full-run records: it cannot be combined with --changed"; return 1; fi   # MG:u-merge-changed
  if [ "$_ru_sh" = 1 ] && [ "$_ru_req" = 0 ] && [ -z "${CI:-}" ]; then echo "--shard needs --require (a shard record is graded as an enforced run)"; return 1; fi   # MG:u-shard-require
  return 0
}

# _mg_registry <out> : this file's `^check` rows as `<ordinal>:<name>`, in file order (the census reads the same lines).
_mg_registry() {
  awk '/^check [a-z]+ / { n = $3; gsub(/"/, "", n); print ++i ":" n }' "$_SELF" > "$1"
}

# _mg_parse <record> <k> <wd> <display> : read ONE record (already past _vs_record_check) into <wd>/meta.<k> (tab-separated: shard,
# tree, counts, one `row ordinal listed-name rendered-name verdict` per listed row) and <wd>/rows.<k> (`ordinal<TAB>seq<TAB>line` for
# every body line; the battery row's line is replaced by the marker @@JOIN@@). Prints the reason and returns 1 when it is malformed.
_mg_parse() {
  : > "$3/meta.$2"; : > "$3/rows.$2"
  if ! _mp_why=$(awk -v meta="$3/meta.$2" -v rows="$3/rows.$2" '
    function bad(m) { print "malformed record (" m ")"; err = 1; exit 1 }
    NR == 1 {
      if (match($0, / shard=[0-9]+\/[0-9]+( |$)/)) { sh = substr($0, RSTART + 7, RLENGTH - 7); sub(/ $/, "", sh) } else bad("no shard=<i>/<N> in the header")
      if (match($0, / tree=[^ ]+/)) tr = substr($0, RSTART + 6, RLENGTH - 6); else bad("no tree= in the header")
      if (length(sh) > 13) bad("the coordinate is too long")
      next
    }
    NR == 2 { if ($0 != "Conformance verification (honest aggregate)") bad("line 2 is not the aggregate heading"); next }
    NR == 3 { if ($0 != "-------------------------------------------") bad("line 3 is not the heading rule"); next }
    tail {
      if ($0 ~ /^Shard-rows: /) bad("two Shard-rows lines")
      if ($0 ~ /^Shard-counts: /) { if (cnt != "") bad("two Shard-counts lines"); cnt = $0 }
      if ($0 ~ /^verify-output-end: v1 rc=/) { trc = $0; sub(/^verify-output-end: v1 rc=/, "", trc); sub(/ .*/, "", trc) }
      next
    }
    /^Shard-rows: / {
      n = split($0, t, " ")
      if (t[2] != sh) bad("Shard-rows names " t[2] " but the header " sh)
      for (i = 3; i <= n; i++) {
        if (t[i] !~ /^[0-9]+:[^ ]+$/) bad("a Shard-rows token is not ordinal:name")
        p = index(t[i], ":"); idx[i - 2] = substr(t[i], 1, p - 1) + 0; nm[i - 2] = substr(t[i], p + 1)
      }
      nt = n - 2; tail = 1; next
    }
    /^  \[(control|doc)\] / { rown++; rname[rown] = $2; rver[rown] = $3; rkind[rown] = $1; L[++nl] = $0; R[nl] = rown; next }
    { if (rown == 0) bad("a line before the first row"); L[++nl] = $0; R[nl] = rown }
    END {
      if (err) exit 1
      if (!tail) { print "malformed record (no Shard-rows line)"; exit 1 }
      if (cnt == "") { print "malformed record (no Shard-counts line)"; exit 1 }
      print "shard\t" sh > meta; print "tree\t" tr > meta
      m = split(cnt, c, " ")
      for (i = 2; i <= m; i++) { split(c[i], kv, "="); v = kv[2] + 0; print "count\t" kv[1] "\t" v > meta }
      nr = rown + 0; print "nrows\t" nr > meta; print "ntok\t" nt > meta
      for (r = 1; r <= rown; r++) {
        k = rkind[r]; v = rver[r]
        if (v == "JOIN" || v == "N-A") { if (v == "N-A") dn++; continue }
        if (k == "[control]") dc++; else dd++
        if (v == "FAIL") { df++; if (k == "[control]") dcf = 1 }
        if (v == "UNVERIFIED") { du++; df++ }
        if (v == "MISCONFIGURED") dm++
      }
      print "derived\tcontrols\t" dc + 0 > meta; print "derived\tdocs\t" dd + 0 > meta; print "derived\tunverified\t" du + 0 > meta
      print "derived\tnas\t" dn + 0 > meta; print "derived\tfailed\t" df + 0 > meta; print "derived\tmisconfigured\t" dm + 0 > meta
      print "derived\tctrl_fail\t" dcf + 0 > meta
      print "rc\t" ((dcf + 0 > 0 || du + 0 > 0 || dm + 0 > 0) ? 1 : 0) "\t" trc > meta
      for (r = 1; r <= nt; r++) { rn = (r <= rown) ? rname[r] : ""; rv = (r <= rown) ? rver[r] : ""; print "row\t" idx[r] "\t" nm[r] "\t" rn "\t" rv > meta }
      for (j = 1; j <= nl; j++) {
        r = R[j]; tx = L[j]; ix = 0
        if (r >= 1 && r <= nt) ix = idx[r]
        if (r >= 1 && r <= nt && rver[r] == "JOIN" && L[j] ~ /^  \[/) tx = "@@JOIN@@"
        print ix "\t" j "\t" tx > rows
      }
    }' "$1"); then echo "$_mp_why — $4"; return 1; fi   # MG:parse
  _mp_nr=$(awk -F'\t' '$1 == "nrows" { print $2 }' "$3/meta.$2"); _mp_nt=$(awk -F'\t' '$1 == "ntok" { print $2 }' "$3/meta.$2")
  if [ "$_mp_nr" != "$_mp_nt" ]; then echo "rendered rows disagree with the row list ($_mp_nr rendered, $_mp_nt listed) — $4"; return 1; fi   # MG:body
  _mp_nm=$(awk -F'\t' '$1 == "row" && $3 != $4 { print $3 " listed, " $4 " rendered"; exit }' "$3/meta.$2")
  if [ -n "$_mp_nm" ]; then echo "a rendered row name differs from its listed name ($_mp_nm) — $4"; return 1; fi   # MG:bodyname
  _mp_j=$(awk -F'\t' '$1 == "row" && $5 == "JOIN" && $3 != "agent-autonomy" { print $3; exit }' "$3/meta.$2")
  if [ -n "$_mp_j" ]; then echo "the row $_mp_j is written JOIN, and only the agent-autonomy row may be (a JOIN row is graded by the battery join, so any other would escape its grading) — $4"; return 1; fi   # MG:join
  _mp_a=$(awk -F'\t' '$1 == "row" && $5 != "JOIN" && $3 == "agent-autonomy" { print $5; exit }' "$3/meta.$2")
  if [ -n "$_mp_a" ]; then echo "the agent-autonomy row must be written JOIN, not $_mp_a (a shard may not run the battery) — $4"; return 1; fi   # MG:join2
  # the record's own counters and trailer must agree with the rows it renders (a record that hides a FAIL row behind zero counters
  # or an rc 0 would otherwise carry its lie into the merged Summary and exit)
  _mp_cd=$(awk -F'\t' '$1 == "count" { c[$2] = $3 } $1 == "derived" { if (c[$2] + 0 != $3 + 0) { print $2 ": the record says " c[$2] + 0 ", its rows show " $3 + 0; exit } }' "$3/meta.$2")
  if [ -n "$_mp_cd" ]; then echo "the record's Shard-counts disagree with its rows ($_mp_cd) — $4"; return 1; fi   # MG:counts
  _mp_rc=$(awk -F'\t' '$1 == "rc" && $2 != $3 { print "the rows need rc " $2 ", the trailer says rc " $3; exit }' "$3/meta.$2")
  if [ -n "$_mp_rc" ]; then echo "the record's trailer rc disagrees with its rows ($_mp_rc) — $4"; return 1; fi   # MG:trailerrc
  return 0
}

# _mg_validate <wd> <head> <self> <dirty> <tree> <registry> <record>... : rc 0 with <wd>/rows (the rebuilt rows, registry order, the
# battery row as @@JOIN@@) and <wd>/counts (`controls docs unverified nas failed misconfigured ctrl_fail`); else the reason and rc 1.
_mg_validate() {
  _mv_wd=$1; _mv_hd=$2; _mv_sf=$3; _mv_dt=$4; _mv_tr=$5; _mv_reg=$6; shift 6
  if [ "$#" = 0 ]; then echo "no shard record given"; return 1; fi   # MG:none
  _mv_k=0; _mv_m=""; _mv_js=" "
  for _mv_f in "$@"; do
    _mv_k=$((_mv_k+1)); _mv_u=$_mv_f
    # a private copy, checked and read once (the file validated is the file graded); an unreadable path goes on as it is, and the check names why
    if [ -f "$_mv_f" ] && [ -r "$_mv_f" ] && cp "$_mv_f" "$_mv_wd/r$_mv_k" 2>/dev/null; then _mv_u="$_mv_wd/r$_mv_k"; fi
    if ! _mv_why=$(_vs_record_check "$_mv_u" "$_mv_hd" "$_mv_sf" "$_mv_dt" shard); then echo "$_mv_why — $_mv_f"; return 1; fi   # MG:rec
    _mg_parse "$_mv_u" "$_mv_k" "$_mv_wd" "$_mv_f" || return 1
    _mv_t=$(awk -F'\t' '$1 == "tree" { print $2 }' "$_mv_wd/meta.$_mv_k")
    if [ "$_mv_t" != "$_mv_tr" ]; then echo "the record was graded in another tree ($_mv_t; this tree is $_mv_tr) — $_mv_f"; return 1; fi   # MG:tree
    _mv_c=$(awk -F'\t' '$1 == "shard" { print $2 }' "$_mv_wd/meta.$_mv_k"); _mv_j=${_mv_c%/*}; _mv_n=${_mv_c#*/}
    if [ "$_mv_j" -lt 1 ] || [ "$_mv_j" -gt "$_mv_n" ]; then echo "the coordinate $_mv_c is outside 1..N — $_mv_f"; return 1; fi   # MG:range
    if [ -z "$_mv_m" ]; then _mv_m=$_mv_n; fi
    if [ "$_mv_n" != "$_mv_m" ]; then echo "the records disagree on N ($_mv_m and $_mv_n) — $_mv_f"; return 1; fi   # MG:n
    case "$_mv_js" in
      *" $_mv_j "*) echo "the coordinate $_mv_j/$_mv_m appears twice — $_mv_f"; return 1 ;;   # MG:dup
    esac
    _mv_js="$_mv_js$_mv_j "
  done
  if [ "$_mv_k" != "$_mv_m" ]; then
    _mv_miss=""; _mv_i=1
    while [ "$_mv_i" -le "$_mv_m" ] && [ "$_mv_i" -le 64 ]; do
      case "$_mv_js" in
        *" $_mv_i "*) ;;
        *) _mv_miss="$_mv_miss $_mv_i/$_mv_m" ;;
      esac
      _mv_i=$((_mv_i+1))
    done
    echo "missing coordinate(s):${_mv_miss:- none listed} ($_mv_k record(s) given, M is $_mv_m)"; return 1   # MG:missing
  fi
  if [ "$(grep -c ':agent-autonomy$' "$_mv_reg")" != 1 ]; then echo "the registry has no agent-autonomy row (or has several): there is nothing to join the battery with"; return 1; fi   # MG:noaa
  : > "$_mv_wd/idxs"; : > "$_mv_wd/union"; : > "$_mv_wd/rows.all"; : > "$_mv_wd/cnt"
  _mv_i=1
  while [ "$_mv_i" -le "$_mv_k" ]; do
    awk -F'\t' '$1 == "row" { print $2 }' "$_mv_wd/meta.$_mv_i" >> "$_mv_wd/idxs"
    awk -F'\t' '$1 == "row" { print $2 ":" $3 }' "$_mv_wd/meta.$_mv_i" >> "$_mv_wd/union"
    awk -F'\t' '$1 == "count" { print $2 "\t" $3 }' "$_mv_wd/meta.$_mv_i" >> "$_mv_wd/cnt"
    cat "$_mv_wd/rows.$_mv_i" >> "$_mv_wd/rows.all"
    _mv_i=$((_mv_i+1))
  done
  _mv_d=$(LC_ALL=C sort "$_mv_wd/idxs" | LC_ALL=C uniq -d | sed -n 1p)
  if [ -n "$_mv_d" ]; then echo "the row $_mv_d ran in two shards (overlapping rows)"; return 1; fi   # MG:overlap
  _mv_i=1
  while [ "$_mv_i" -le "$_mv_k" ]; do
    _mv_c=$(awk -F'\t' '$1 == "shard" { print $2 }' "$_mv_wd/meta.$_mv_i"); _mv_j=${_mv_c%/*}
    _mv_fr=$(awk -F'\t' -v j="$_mv_j" -v n="$_mv_m" '$1 == "row" && ($2 - 1) % n != j - 1 { print $2 ":" $3; exit }' "$_mv_wd/meta.$_mv_i")
    if [ -n "$_mv_fr" ]; then echo "the row $_mv_fr is owned by another shard than $_mv_c (its ordinal mod N is not $((_mv_j - 1)))"; return 1; fi   # MG:foreign
    _mv_i=$((_mv_i+1))
  done
  LC_ALL=C sort "$_mv_wd/union" > "$_mv_wd/union.s"; LC_ALL=C sort "$_mv_reg" > "$_mv_wd/reg.s"
  if ! cmp -s "$_mv_wd/union.s" "$_mv_wd/reg.s"; then echo "the union of the records' rows is not the registry's rows (first difference: $(LC_ALL=C comm -3 "$_mv_wd/union.s" "$_mv_wd/reg.s" | sed -n 1p | tr -d '\t'))"; return 1; fi   # MG:union
  LC_ALL=C sort -t "$(printf '\t')" -k1,1n -k2,2n "$_mv_wd/rows.all" | cut -f3- > "$_mv_wd/rows"
  awk -F'\t' '{ s[$1] += $2 } END { print s["controls"] + 0, s["docs"] + 0, s["unverified"] + 0, s["nas"] + 0, s["failed"] + 0, s["misconfigured"] + 0, (s["ctrl_fail"] > 0 ? 1 : 0) }' "$_mv_wd/cnt" > "$_mv_wd/counts"
  return 0
}

# _mg_battery_recs <dir> : the *.rec files of the battery directory, one per line; rc 1 when there are none.
_mg_battery_recs() {
  _br_n=0
  for _br_f in "$1"/*.rec; do
    if [ -f "$_br_f" ]; then printf '%s\n' "$_br_f"; _br_n=$((_br_n+1)); fi
  done
  if [ "$_br_n" = 0 ]; then return 1; fi   # MG:battery
  return 0
}

# _mg_aa_na <file> : 0 when the (captured) agent-autonomy row rendered N-A.
_mg_aa_na() {
  if grep -Eq '^  \[control\] +agent-autonomy +N-A$' "$1"; then return 0; fi   # MG:na
  return 1
}

# _mg_aa_row <battery-records-file> : the battery row, graded by the JOIN of the battery shard records (C8). Runs the REAL check().
_mg_aa_row() {
  _ar_l=$1
  set -- sh conformance/agent-autonomy.sh --join
  while IFS= read -r _ar_f; do
    set -- "$@" "$_ar_f"
  done < "$_ar_l"
  check control agent-autonomy --kitselftest "$@"   # mb:replay agent-autonomy
}

# _mg_timing <out> <record>... : append each record's `<record>.timing` sidecar (the shard's --timing-file) to <out>. Timing is
# telemetry, never a gate: a missing sidecar is skipped.
_mg_timing() {
  _mt_o=$1; shift
  for _mt_f in "$@"; do
    if [ -f "$_mt_f.timing" ]; then cat "$_mt_f.timing" >> "$_mt_o" 2>/dev/null || true; fi   # MG:timing
  done
  return 0
}

# _mg_main : the --merge run (the record paths are in $MERGE_RECS, newline-separated). On success sets the counters from the records
# and the battery row, and MERGE_FINAL to the file holding the rebuilt rows; the caller prints it where the registry's rows would be.
_mg_main() {
  if [ -n "$SEAM_ACTIVE" ]; then echo "verify --merge: REFUSED (a test seam is active: $SEAM_ACTIVE — a merge is a verdict, never a test)"; return 2; fi   # MG:seam
  _mm_nl='
'
  _mm_oifs=$IFS; IFS=$_mm_nl; set -f
  # shellcheck disable=SC2086  # the record list is newline-separated, and is split on purpose
  set -- $MERGE_RECS
  set +f; IFS=$_mm_oifs
  _mm_wd=$(mktemp -d "${TMPDIR:-/tmp}/verify-merge.XXXXXX") || { echo "verify --merge: REFUSED (no scratch directory)"; return 1; }
  _mm_hd=$(git rev-parse HEAD 2>/dev/null) || _mm_hd=none
  if [ -z "$_mm_hd" ]; then _mm_hd=none; fi
  _mm_sf=$(cksum < "$_SELF" | tr ' ' '-')
  _mm_dt=$(git status --porcelain --untracked-files=all 2>/dev/null | cksum | tr ' ' '-')
  _mm_tr=$(git write-tree 2>/dev/null) || _mm_tr=none
  if [ -z "$_mm_tr" ]; then _mm_tr=none; fi
  _mg_registry "$_mm_wd/registry"
  if ! _mm_why=$(_mg_validate "$_mm_wd" "$_mm_hd" "$_mm_sf" "$_mm_dt" "$_mm_tr" "$_mm_wd/registry" "$@"); then
    echo "verify --merge: REFUSED ($_mm_why)"; rm -rf "$_mm_wd"; return 1
  fi
  read -r controls docs unverified nas failed misconfigured ctrl_fail < "$_mm_wd/counts"
  if [ -n "$BATTERY" ]; then
    if ! _mg_battery_recs "$BATTERY" > "$_mm_wd/brecs"; then echo "verify --merge: REFUSED ($BATTERY holds no *.rec battery record to join)"; rm -rf "$_mm_wd"; return 1; fi
    _mg_aa_row "$_mm_wd/brecs" > "$_mm_wd/aa"
    # C8: a joined battery row is PASS or FAIL, never N-A (adopter-census forbids an unclassified N-A control row on the export, and a
    # deferral is not a join). Without --battery the row runs as it always did, and a deferral stays the N-A it is today.
    if _mg_aa_na "$_mm_wd/aa"; then
      nas=$((nas-1)); controls=$((controls+1)); failed=$((failed+1)); ctrl_fail=1
      { line "[control]" agent-autonomy FAIL; emit_diag agent-autonomy "the joined battery rendered N-A. In a merge the agent-autonomy row is PASS or FAIL, never N-A"; } > "$_mm_wd/aa"
    fi
  else
    check control agent-autonomy --kitselftest sh conformance/agent-autonomy.sh > "$_mm_wd/aa"   # mb:replay agent-autonomy
  fi
  if [ -n "$KS_TIMING" ]; then _mg_timing "$KS_TIMING" "$@"; fi
  awk 'FNR == NR { a[++n] = $0; next } $0 == "@@JOIN@@" { for (i = 1; i <= n; i++) print a[i]; next } { print }' "$_mm_wd/aa" "$_mm_wd/rows" > "$_mm_wd/final"
  MERGE_FINAL=$_mm_wd/final
  return 0
}

# The writer's signal path: on INT or TERM print what the child captured, write NO record (the reader then refuses
# the missing file), and exit 128 plus the signal.
_vs_wr_signal() {
  trap - INT TERM
  kill -TERM "$_wr_pid" 2>/dev/null || true
  wait "$_wr_pid" 2>/dev/null || true
  if [ -f "$_wr_cap" ]; then cat "$_wr_cap"; fi
  rm -f "$_wr_cap"
  exit "$1"
}

# _vs_write_record <path> <child-args...> : re-execute this script with the SAME arguments minus the --output-file
# pair, from the caller's directory, combined output captured WITHOUT a pipe so the exit status is the child's exactly;
# then write the record, print the captured body, and exit with the child's status. Stderr is folded into stdout
# (disclosed, design O6). A record that cannot be written warns and leaves the verdict untouched.
_vs_write_record() {
  _wr_path=$1; shift
  if [ "${_wr_path#/}" = "$_wr_path" ]; then _wr_path="$_KS_ORIG_PWD/$_wr_path"; fi
  _wr_root=$(cd "$(dirname "$_SELF")/.." && pwd)
  # The capture and the staging file are mktemp-created in the record's directory (unpredictable names, 0600, never a
  # pre-existing path an attacker could point a symlink at), then moved into place; both are removed on every exit.
  _wr_dir=$(dirname "$_wr_path")
  _wr_cap=$(mktemp "$_wr_dir/.verify-rec.XXXXXX" 2>/dev/null) || _wr_cap=""
  _wr_req=0; _wr_chg=0; _wr_shard=""; _wr_prev=""
  if [ -n "${CI:-}" ]; then _wr_req=1; fi
  for _wr_a in "$@"; do
    if [ "$_wr_a" = "--require" ]; then _wr_req=1; fi
    if [ "$_wr_a" = "--merge" ]; then _wr_req=1; fi   # a merge is an enforced run (SWAS-393)
    if [ "$_wr_a" = "--changed" ]; then _wr_chg=1; fi
    if [ "$_wr_prev" = "--shard" ]; then _wr_shard=$_wr_a; fi
    _wr_prev=$_wr_a
  done
  if [ -z "$_wr_cap" ]; then
    echo "verify: WARNING — cannot create a capture file next to $_wr_path; running WITHOUT recording" >&2
    exec sh "$_SELF" "$@"
  fi
  # SWAS-393 (S3): a ROW-SHARD record also carries the tree id and the working-tree checksum of the tree the shard STARTED from, taken
  # BEFORE the run (a row may leave untracked residue, and the join runs in a pristine tree of the same content). A plain record is unchanged.
  _wr_extra=""; _wr_dirty0=""
  if [ -n "$_wr_shard" ]; then
    _wr_tree=$(git -C "$_wr_root" write-tree 2>/dev/null) || _wr_tree=none
    if [ -z "$_wr_tree" ]; then _wr_tree=none; fi
    _wr_dirty0=$(git -C "$_wr_root" status --porcelain --untracked-files=all 2>/dev/null | cksum | tr ' ' '-')
    _wr_extra=" shard=$_wr_shard tree=$_wr_tree"
  fi
  sh "$_SELF" "$@" > "$_wr_cap" 2>&1 &
  _wr_pid=$!
  # LOCAL-TERMINAL GAP (review m1): the async child starts with SIGINT ignored (POSIX), so on Ctrl-C only the PARENT's
  # trap fires and it TERMs the child alone; a check the child is running finishes (or is orphaned) before the child
  # prints INCOMPLETE. CI sends TERM/cancel to the job, which is the path this handles. No record is written either way.
  trap '_vs_wr_signal 130' INT
  trap '_vs_wr_signal 143' TERM
  if wait "$_wr_pid"; then _wr_rc=0; else _wr_rc=$?; fi
  trap - INT TERM
  _wr_head=$(git -C "$_wr_root" rev-parse HEAD 2>/dev/null) || _wr_head=none
  if [ -z "$_wr_head" ]; then _wr_head=none; fi
  _wr_self=$(cksum < "$_SELF" | tr ' ' '-')
  _wr_dirty=$(git -C "$_wr_root" status --porcelain --untracked-files=all 2>/dev/null | cksum | tr ' ' '-')
  if [ -n "$_wr_shard" ]; then _wr_dirty=$_wr_dirty0; fi
  _wr_lines=$(sed -n '$=' "$_wr_cap")
  _wr_nl=0
  if [ -s "$_wr_cap" ] && [ -n "$(tail -c 1 "$_wr_cap")" ]; then _wr_nl=1; fi
  _wr_tmp=$(mktemp "$_wr_dir/.verify-rec.XXXXXX" 2>/dev/null) || _wr_tmp=""
  if [ -n "$_wr_tmp" ] && {
    printf 'verify-output-file: v1 head=%s self=%s dirty=%s require=%s changed=%s%s\n' "$_wr_head" "$_wr_self" "$_wr_dirty" "$_wr_req" "$_wr_chg" "$_wr_extra"
    cat "$_wr_cap"
    if [ "$_wr_nl" = 1 ]; then printf '\n'; fi
    printf 'verify-output-end: v1 rc=%s lines=%s\n' "$_wr_rc" "${_wr_lines:-0}"
  } > "$_wr_tmp" 2>/dev/null && mv -f "$_wr_tmp" "$_wr_path" 2>/dev/null; then
    :
  else
    if [ -n "$_wr_tmp" ]; then rm -f "$_wr_tmp"; fi
    echo "verify: WARNING — could not write the record to $_wr_path (the enforced verdict is unchanged)" >&2
  fi
  cat "$_wr_cap"
  rm -f "$_wr_cap"
  exit "$_wr_rc"
}

# A stray, doubled or valueless --from-output is a usage error BEFORE anything runs (never a silent green).
if [ "$(_vs_from_mode "$@")" = error ]; then
  echo "verify: usage error — --from-output <path> is valid only as: --selftest --from-output <path>, once, with a path (it never falls back to the nested run)" >&2
  exit 2
fi
# --output-file <path>: strip the pair (rotating "$@"), then re-execute as the recorded run. The placement is fixed:
# after the CI seam refusal above, before the traps and the cd below, from the caller's directory.
_of_n=$#; _of_path=""; _of_cnt=0; _of_take=0
while [ "$_of_n" -gt 0 ]; do
  _of_a=$1; shift; _of_n=$((_of_n-1))
  if [ "$_of_take" = 1 ]; then _of_take=0; _of_path=$_of_a; continue; fi
  if [ "$_of_a" = "--output-file" ]; then _of_cnt=$((_of_cnt+1)); _of_take=1; continue; fi
  set -- "$@" "$_of_a"
done
_of_first=${1:-}   # the first word LEFT after the pair is stripped: --output-file F --selftest is refused like --selftest --output-file F
# SWAS-393: the row-shard flags are validated BEFORE anything runs (and again by the recorded child, with the same answer).
if _rs_why=$(_rs_usage "$@"); then :; else echo "verify: usage error — $_rs_why" >&2; exit 2; fi
if [ "$_of_cnt" -gt 0 ]; then
  if [ "$_of_cnt" -gt 1 ]; then echo "verify: usage error — --output-file given twice" >&2; exit 2; fi
  if [ "$_of_take" = 1 ] || [ -z "$_of_path" ]; then echo "verify: usage error — --output-file needs a path" >&2; exit 2; fi
  if [ "$_of_first" = "--selftest" ]; then echo "verify: usage error — --output-file cannot be combined with --selftest" >&2; exit 2; fi
  for _of_seam in VERIFY_SELFTEST_REGISTRY VERIFY_CLASSIFIER VERIFY_SKIP_PREFLIGHT; do
    eval "_of_sv=\${$_of_seam:-}"
    if [ -n "$_of_sv" ]; then
      echo "verify: REFUSED — --output-file will not record a run under $_of_seam (a test seam or a skipped pre-flight can forge a green, and its record would be a plausible file that proves nothing)" >&2
      exit 2
    fi
  done
  _vs_write_record "$_of_path" "$@"
fi

cd "$(dirname "$0")/.."

# SWAS-393 (S3): `--merge` is the FIRST word (validated by _rs_usage above). The flags it understands are taken out of "$@" here: the
# record paths go to MERGE_RECS (newline-separated, absolute), --battery's directory to BATTERY, and --require / --timing-file /
# --summary-file stay in "$@" for the option loop below. Any other flag is a usage error.
MERGE=0; BATTERY=""; MERGE_RECS=""; MERGE_FINAL=""
if [ "${1:-}" = "--merge" ]; then
  MERGE=1; shift
  _mg_n=$#; _mg_take=""
  while [ "$_mg_n" -gt 0 ]; do
    _mg_a=$1; shift; _mg_n=$((_mg_n-1))
    if [ "$_mg_take" = battery ]; then
      case "$_mg_a" in
        /*) BATTERY=$_mg_a ;;
        *) BATTERY="$_KS_ORIG_PWD/$_mg_a" ;;
      esac
      _mg_take=""; continue
    fi
    if [ "$_mg_take" = keep ]; then set -- "$@" "$_mg_a"; _mg_take=""; continue; fi
    case "$_mg_a" in
      --battery) _mg_take=battery ;;
      --require) set -- "$@" "$_mg_a" ;;
      --timing-file|--summary-file) set -- "$@" "$_mg_a"; _mg_take=keep ;;
      --*) echo "verify: usage error — $_mg_a is not valid with --merge" >&2; exit 2 ;;
      /*) MERGE_RECS="$MERGE_RECS$_mg_a
" ;;
      *) MERGE_RECS="$MERGE_RECS$_KS_ORIG_PWD/$_mg_a
" ;;
    esac
  done
fi

REQUIRE=0
[ -n "${CI:-}" ] && REQUIRE=1
[ "${1:-}" = "--require" ] && REQUIRE=1
if [ "$MERGE" = 1 ]; then REQUIRE=1; fi
# --changed / --summary-file may sit anywhere after the first word; a missing value leaves them empty,
# which means "no listing" = the full battery (the safe direction). Values are made absolute BEFORE use.
KS_CHANGED=""; KS_SUMMARY=""; KS_TIMING=""; _ks_prev=""; RS_SPEC=""
for _ks_a in "$@"; do
  case "$_ks_prev" in
    --changed) KS_CHANGED=$_ks_a ;;
    --summary-file) KS_SUMMARY=$_ks_a ;;
    --timing-file) KS_TIMING=$_ks_a ;;
    --shard) RS_SPEC=$_ks_a ;;
  esac
  [ "$_ks_a" = "--require" ] && REQUIRE=1
  _ks_prev=$_ks_a
done
# SWAS-393: the row shard is an ARGUMENT only (validated by _rs_usage); SHARD_I/SHARD_N stay 0 for a run without --shard.
SHARD_I=0; SHARD_N=0
if [ -n "$RS_SPEC" ]; then SHARD_I=${RS_SPEC%/*}; SHARD_N=${RS_SPEC#*/}; fi
case "$KS_CHANGED" in ''|/*) ;; *) KS_CHANGED="$_KS_ORIG_PWD/$KS_CHANGED" ;; esac
case "$KS_SUMMARY" in ''|/*) ;; *) KS_SUMMARY="$_KS_ORIG_PWD/$KS_SUMMARY" ;; esac
case "$KS_TIMING" in ''|/*) ;; *) KS_TIMING="$_KS_ORIG_PWD/$KS_TIMING" ;; esac
[ -z "$KS_TIMING" ] || : > "$KS_TIMING" 2>/dev/null || true   # truncate ONCE per run: a reused path never mixes runs

ctrl_fail=0; unverified=0; controls=0; docs=0; failed=0; nas=0; misconfigured=0
_rs_idx=0; _rs_rows=""   # SWAS-393: the ordinal of the current `check` call, and this shard's rows (` ordinal:name`)
SKIP_KS=0; SKIPPED_KS=""   # --kitselftest skip mode (decided once, after the selftest block) and the rows it skipped
line() { printf '  %-9s %-18s %s\n' "$1" "$2" "$3"; }

# ── K3 — a failing gate must not hide WHY ───────────────────────────────────────────────────────────
# check() already captures the child's combined output in $out and, until v3.173.0, threw it away: the
# aggregate printed `whitespace-clean FAIL` in an otherwise 101-pass run and nothing else, so the
# operator had to RE-RUN the individual gate to learn which file was at fault. That is a diagnostic
# round trip on every failure, paid at exactly the moment the operator is least oriented — and on a
# COLD field test (where nobody may assist) it is the difference between a self-explaining failure and
# a dead end. The output was always in hand; it was simply never printed.
#
# Indented and clearly delimited so the aggregate stays SCANNABLE: only failures expand, passes stay
# one line each. A child that prints nothing still shows nothing — this surfaces existing output, it
# does not invent any.
emit_diag() {  # <check-name> <captured-output>
  [ -n "$2" ] || { printf '      (%s produced no output — re-run it directly)\n' "$1"; return 0; }
  printf '      ── %s output ──────────────────────────────\n' "$1"
  printf '%s\n' "$2" | sed 's/^/      /'
  printf '      ──────────────────────────────────────────\n'
}

# ── C6 — a check that DID NOT VERIFY must not render PASS ───────────────────────────────────────────
# THE DEFECT: check() runs the child, and on rc 0 it threw the child's own words away and printed PASS.
# But dozens of checks are CONDITIONAL — "no Dockerfile", "no data surface", "not an AI feature", "not
# the kit repo" — and they say so on stdout and exit 0. The aggregate rendered that self-declared
# NON-verification with the same token as an executed proof, so a green run over-claimed by however
# many rows had quietly skipped (MEASURED: ≥14 on the kit tree, whose Summary simultaneously reported
# `0 n/a` — the bug's own signature; ≥39 on a raw adopter export).
#
# THE PREDICATE IS MEASURED, NOT INVENTED — and the measurement CORRECTED it twice. It has two
# conjuncts, and both were forced by evidence rather than chosen.
#
# CONJUNCT 1 — the child declares a skip. Enumerated over every rc-0 self-skip branch reachable from
# the `check` rows below, the shipped idiom has exactly three shapes, all printed as a WHOLE LINE:
#   `N/A: …` / `N/A (no Dockerfile): …` / `N/A — …`        (the conditional-surface skips)
#   `<check-name>: N/A — kit-self check (…)`                (the ~20 *-wired.sh kit-self skips)
#   `SKIP: …`                                               (conformance/shellcheck.sh, tool absent)
# LINE-ANCHORING IS LOAD-BEARING, not tidiness. A check that is genuinely RUNNING prints `N/A` mid-line
# all the time — incept-first-run-green.sh renders `  [N/A]   db-postgres — …` per sub-gate and a
# `… $NAS N/A, …` summary; selftests narrate `selftest PASS: no CLAUDE.md -> N/A`. MEASURED over a full
# instrumented aggregate: 36 of the 135 rc-0 rows mention n/a or skip prose somewhere in their output
# and every one of them had really run. An unanchored match would demote all 36. The anchor takes none.
#
# CONJUNCT 2 — and the child claims NO verdict. This one is a BUILD-TIME FALSIFICATION of the design's
# assumed predicate (design §6.2 expected conjunct 1 alone). Measured on the same aggregate: conjunct 1
# on its own captured `image-supply` and `runtime-floor`, which iterate the ten profiles, skip the three
# or four that have no Dockerfile / no declared floor, and VERIFY THE REST — `image-supply` proved seven
# real supply chains and then signed off `container-supply-chain: OK (7 profile(s) … checked; others
# N/A)`. Calling that N-A under-claims: the run DID verify something. So a PARTIAL skip beside a real
# verdict stays PASS, and N-A means what it says — this check verified NOTHING here. The verdict idiom
# is uppercase `OK`/`PASS` at line start (bare or `<name>: OK`), deliberately case-SENSITIVE so ordinary
# prose ("ok, so…") cannot suppress a real skip. Measured effect: 17 rows classified → 15, and the two
# it drops are exactly the two that had proved something.
#
# FAIL DIRECTION IS SAFE BY CONSTRUCTION: this is a render-honesty change, never an authorization one.
# A false positive under-claims (a real proof shows as N-A — visible, non-blocking, never green-when-
# dark); a false negative is exactly today's status quo. HONEST CEILING: it is a prose heuristic. A
# future check that self-skips in NON-conforming prose renders PASS until its idiom is added here —
# the class is narrowed, not closed (boarded: VERIFY-SKIP-IDIOM-RESIDUAL).
is_self_skip() {  # <captured-output> — 0 when the child DECLARED it verified nothing here
  printf '%s\n' "$1" | grep -Eqi '^(N/A([^A-Za-z0-9]|$)|SKIP:|[A-Za-z0-9_.-]+:[[:space:]]*N/A([^A-Za-z0-9]|$))' || return 1
  # ZERO-COUNT REFINEMENT (VERIFY-SKIP-IDIOM-RESIDUAL, face ii): a verdict line that SELF-REPORTS zero
  # verified items suppresses nothing — `OK (0 profile(s) … checked)` is a skip wearing a verdict, and
  # C6's own rule ("N-A means this check verified NOTHING here") says so. Dropped BEFORE the verdict
  # test, so a run with a zero-count line AND a real one still passes on the real one.
  # THE KEY IS THE WHOLE SENTENCE SHAPE, not a bare `(0 `: MEASURED, conformance/*.sh emits `(0 ` on 37
  # lines — `(0 rows)`, `(0 find spawns…)`, `(0 foreign lines…)`, `(0 files)`, `(0 occurrence(s))` — and
  # a loose key would demote every row that prints one. ZERO of the 37 match this key. That tightness is
  # also what protects mechanism 3: a false N-A here would inflate the very `na` the CI walks' floor reads.
  ! printf '%s\n' "$1" | grep -Ev '\(0 [A-Za-z-]+\(s\)[^)]*checked' \
    | grep -Eq '^(OK|PASS)([^A-Za-z0-9]|$)|^[A-Za-z0-9_.-]+:[[:space:]]*(OK|PASS)([^A-Za-z0-9]|$)'
}

# is_usage_marked <captured-output> <child-basename> — 0 when a line STARTS with `usage: <basename>`
#
# ⚠️ LITERAL MATCH, DELIBERATELY NOT A REGEX. The first draft interpolated the basename into a BRE
# (`grep -q "^usage: $_base"`), where `foo.sh`'s `.` matches ANY character — so `usage: foo-sh …` was
# blamed on a row invoking `foo.sh`. Elsewhere in this file a false hit under-claims; HERE the safety
# direction is inverted (see the header) and it BLOCKS a legitimate row. The quoted `case` pattern is
# exact. The `while` reads a heredoc, not a pipe, so the assignment survives the loop.
is_usage_marked() {
  [ -n "$2" ] || return 1
  _um=1
  while IFS= read -r _uml; do
    case "$_uml" in "usage: $2"*) _um=0; break ;; esac
  done <<EOF
$1
EOF
  return "$_um"
}

# ── INCOMPLETE (K16) — an interrupted run must SAY so, in its own output ────────────────────────────
# The aggregate is WELL OVER A HUNDRED checks and takes MINUTES (measured 281s at v3.171.0; ~22min on a
# loaded host). The authoritative count is the run's own `Summary:` line — no figure is repeated here,
# because every hard-coded one in this file had gone stale by ~30 rows before C6 corrected them. That
# runtime is LONGER than the default foreground command cap of the agent harnesses this kit is driven
# with. When one of those caps fires, the run is killed mid-flight.
#
# THE EXIT CODE WAS NEVER THE GAP. A signalled run already exits non-zero (143 for TERM, 130 for INT),
# so a caller that inspects the status is not fooled. What was missing is any STATEMENT: the output
# simply stopped, leaving a partial transcript indistinguishable from a run still in progress. A human
# or agent READING that transcript had to infer completion from an ABSENCE — the weakest possible
# signal, and how a truncated run gets mistaken for a green one (CP-7 run 4, finding K16).
#
# So this trap adds the sentence, and keeps the conventional 128+signal status. `INCOMPLETE is not a
# pass` is the sibling of `UNVERIFIED is not a pass` — a second way output can look green without being
# one. HONEST CEILING: cannot fire on SIGKILL, and cannot help a consumer that simply stops reading.
_incomplete() {
  echo ""
  printf 'RESULT: FAIL (INCOMPLETE — interrupted after %d check(s); this is NOT a pass)\n' "$((controls+docs+nas))"
  echo "An interrupted run proves nothing about the checks that never ran."
  echo "The full aggregate is well over a hundred checks / several minutes — re-run WITHOUT a command timeout"
  echo "(background it, or capture output to a file). See conformance/README.md \"What a green run means\"."
  exit "${1:-1}"
}
trap '_incomplete 130' INT
trap '_incomplete 143' TERM

# SWAS-372 (SWAS-314 S0) — optional per-row timing, selected by ARGUMENT only: `--timing-file <path>` makes check()
# append one line per row, `<name>\t<seconds>\t<verdict>` (whole seconds of the row's command; 0 for a row skipped
# before it ran). Absent = no file, no extra work: the default output is byte-identical.
_rt_log() {  # <name> <seconds> <verdict>
  [ -n "$KS_TIMING" ] || return 0
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$KS_TIMING" 2>/dev/null || true
}

# check KIND NAME [--kitself | --adopter] COMMAND...
check() {
  kind=$1; name=$2; shift 2
  # CP7R5-VERIFY-NONTS — a --kitself check validates the kit's OWN internals (a reference profile, a
  # dev selftest) and is meaningless on an already-incepted ADOPTER tree, where incept has pruned the
  # fixtures it reads. On an adopter tree it renders N-A (not a pass, not a fail); in the kit repo it runs.
  # The tree is classified by the un-spoofable kit-marker set: an adopter export strips BOTH
  # docs/ROADMAP-KIT.md (export-ignored) AND .github/workflows/golden-path.yml (control-plane +
  # export-ignored), so their joint absence == an adopter tree. Same set incept-first-run-green.sh keys on.
  # Paths are repo-root-relative (this script cd's to the root at startup).
  #
  # ADOPTER-GATES-INERT (A3) — --adopter is the SIBLING classification, METADATA-ONLY: it never skips
  # the command (unlike --kitself, which short-circuits before invocation). It exists purely so
  # conformance/adopter-census.sh can read the classification off this REGISTRY LINE — the census's
  # single source of truth — for a row whose subject is the ADOPTER'S OWN artifact (their ci.yml, ADR,
  # RUNBOOK, VERSION tag, board): such a row correctly N/As on a pre-inception export (nothing authored
  # yet) and ARMS once the adopter incepts/authors, so silencing it with --kitself would be a lie — the
  # exact error A3 found and corrected (see verify.sh's registry rows below for the 9 --adopter cases).
  # The two flags are mutually exclusive: a row is either a KIT fact or an ADOPTER fact, never both.
  if [ "${1:-}" = "--kitself" ] && [ "${2:-}" = "--adopter" ]; then
    echo "verify.sh: registry error — check '$name' declares BOTH --kitself and --adopter (mutually exclusive)" >&2
    exit 2
  fi
  if [ "${1:-}" = "--adopter" ] && [ "${2:-}" = "--kitself" ]; then
    echo "verify.sh: registry error — check '$name' declares BOTH --adopter and --kitself (mutually exclusive)" >&2
    exit 2
  fi
  # --kitselftest (ADOPTER-KIT-SELFTESTS-ON-CHANGE) is the THIRD sibling, exclusive with both others in either order.
  case "${1:-}:${2:-}" in
    --kitselftest:--kitself|--kitselftest:--adopter|--kitself:--kitselftest|--adopter:--kitselftest)
      echo "verify.sh: registry error — check '$name' declares --kitselftest together with --kitself/--adopter (mutually exclusive)" >&2
      exit 2 ;;
  esac
  # SWAS-393 (S3) — ROW SHARDS. Every call counts, so the ordinal is the row's position in the registry. A shard runs only the rows whose
  # ordinal mod N is i-1 and prints nothing for the others; the battery row (agent-autonomy) is never run here — it is written JOIN and
  # graded by `--merge` through agent-autonomy.sh --join. With no --shard (SHARD_N 0) this block changes nothing.
  _rs_idx=$((_rs_idx+1))
  if [ "$SHARD_N" -gt 0 ]; then
    if [ $(( (_rs_idx - 1) % SHARD_N )) -ne $((SHARD_I - 1)) ]; then return 0; fi   # MG:select
    _rs_rows="$_rs_rows $_rs_idx:$name"
    if [ "$name" = agent-autonomy ]; then line "[$kind]" "$name" "JOIN"; return 0; fi   # MG:joinrow
  fi
  if [ "${1:-}" = "--kitselftest" ]; then
    shift
    # Skip mode is decided ONCE (below the selftest block) from a readable non-empty non-control-plane
    # listing; it renders through the SAME N-A path and counters as --kitself — no new verdict kind.
    if [ "$SKIP_KS" = "1" ]; then
      line "[$kind]" "$name" "N-A"; nas=$((nas+1)); SKIPPED_KS="$SKIPPED_KS $name"; _rt_log "$name" 0 "N-A"; return 0
    fi
  elif [ "${1:-}" = "--kitself" ]; then
    shift
    if [ ! -f docs/ROADMAP-KIT.md ] && [ ! -f .github/workflows/golden-path.yml ]; then
      line "[$kind]" "$name" "N-A"; nas=$((nas+1)); _rt_log "$name" 0 "N-A"; return 0
    fi
  elif [ "${1:-}" = "--adopter" ]; then
    shift   # metadata-only: fall through and run the command like any unflagged row
  fi
  # The child's own basename, for the MISCONFIGURED key below. Taken from the ROW, not from $out.
  _base=""; for _a in "$@"; do case "$_a" in conformance/*.sh) _base=${_a##*/}; break ;; esac; done
  _rt0=""; [ -z "$KS_TIMING" ] || _rt0=$(date +%s)
  if out=$("$@" 2>&1); then rc=0; else rc=$?; fi
  _rt_secs=0; [ -z "$_rt0" ] || _rt_secs=$(( $(date +%s) - _rt0 ))
  # C6 — a child that self-declared it verified NOTHING here renders N-A, not PASS. Gated on rc = 0
  # EXACTLY, so this branch is structurally unreachable from the FAIL and rc-2/UNVERIFIED arms below:
  # no failing or unverified check can be reclassified by prose, and --require semantics are untouched.
  # Placed BEFORE the kind-increment so an N-A row leaves BOTH denominators — byte-consistent with the
  # --kitself precedent above, so N-A means one thing everywhere: this check did not verify anything
  # here, and said so. Not blocking, not OK; the reason stays in $out and is deliberately not surfaced
  # (the token + the count IS the honesty claim; one line per check, per the selftest's own pin).
  if [ "$rc" = "0" ] && is_self_skip "$out"; then
    line "[$kind]" "$name" "N-A"; nas=$((nas+1)); _rt_log "$name" "$_rt_secs" "N-A"; return 0
  fi
  case "$kind" in control) controls=$((controls+1)) ;; doc) docs=$((docs+1)) ;; esac
  if [ "$rc" = "0" ]; then
    line "[$kind]" "$name" "PASS"; _rt_log "$name" "$_rt_secs" "PASS"
  elif [ "$rc" = "2" ] && is_usage_marked "$out" "$_base"; then
    _rt_log "$name" "$_rt_secs" "MISCONFIGURED"
    # The registry invoked this child WRONG. Blocking without --require, on purpose: a broken row is
    # invisible to a local run otherwise, and a row that never runs proves nothing while looking green.
    # Its OWN counter, and it does NOT touch $failed (the doc-check advisory tally): borrowing that
    # gave the class two blocking paths, one of which no leg could kill (a mutant dropping the
    # $failed increment survived the whole battery).
    line "[$kind]" "$name" "MISCONFIGURED"; misconfigured=$((misconfigured+1))
    emit_diag "$name" "$out"
  elif [ "$rc" = "2" ]; then
    line "[$kind]" "$name" "UNVERIFIED"; unverified=$((unverified+1)); _rt_log "$name" "$_rt_secs" "UNVERIFIED"
    # Under --require/CI an UNVERIFIED IS a failure, so it earns its diagnostic too — otherwise the
    # one state most likely to be environmental ("no gh, no remote") is the hardest to act on.
    [ "$REQUIRE" = "1" ] && { failed=$((failed+1)); emit_diag "$name" "$out"; } || true
  else
    line "[$kind]" "$name" "FAIL"; failed=$((failed+1)); _rt_log "$name" "$_rt_secs" "FAIL"
    [ "$kind" = "control" ] && ctrl_fail=1 || true
    emit_diag "$name" "$out"
  fi
}

# CP7R5-VERIFY-SUMMARY — the RESULT sentence must not claim "docs present" over FAILING doc-checks.
# Emitted via a function so --selftest drives it with synthetic counters (non-vacuous, no full aggregate).
# Reads globals $ctrl_fail/$unverified/$misconfigured/$failed/$REQUIRE; echoes RESULT; 1 on FAIL, 0 on OK.
# When this is reached with $failed != 0, ctrl_fail is 0 and (under --require) unverified is 0, so every
# remaining failure is a doc-check — hence "$failed doc-check(s)" is exact, not an over-count.
result_sentence() {
  if [ "$ctrl_fail" != "0" ]; then echo "RESULT: FAIL (a control check failed)"; return 1; fi
  if [ "$REQUIRE" = "1" ] && [ "$unverified" != "0" ]; then echo "RESULT: FAIL (unverified under --require/CI)"; return 1; fi
  # BEFORE the $failed branch, and that ORDER is the whole mechanism. ⚠️ NOT because MISCONFIGURED
  # increments $failed — it does NOT. The reason is CO-OCCURRENCE: with a MISCONFIGURED row AND any
  # failing doc-check, a $failed-first ordering prints "advisory, non-blocking" and returns 0 — a
  # FAIL-always class downgraded by an unrelated advisory failure. The selftest drives exactly that
  # pair (misconfigured=1, failed=1); a failed=0 fixture cannot tell the two orderings apart.
  if [ "$misconfigured" != "0" ]; then
    echo "RESULT: FAIL ($misconfigured check row(s) MISCONFIGURED — a child answered with its own usage text, so verify.sh's registry invoked it wrong. The row proved nothing; fix the row.)"; return 1
  fi
  if [ "$failed" != "0" ]; then
    echo "RESULT: OK (controls verified; $failed doc-check(s) FAILED, shown above — advisory, non-blocking)"; return 0
  fi
  echo "RESULT: OK (controls verified; docs present)"; return 0
}

if [ "${1:-}" = "--selftest" ]; then
  # deterministic: the aggregate renders its classification + honesty footer, and a
  # control failure is surfaced. We exercise the renderer, not live infra.
  # The source of $out is chosen FIRST: with --from-output the enforced run's RECORD is loaded before any fixture leg,
  # so a missing, stale, foreign or truncated record reds in seconds (exit 1, naming the path and the reason) and NEVER
  # falls back to the nested run. The live head, this script's cksum and the working-tree cksum go to the PURE check.
  _vs_fm=$(_vs_from_mode "$@")
  _vs_src="nested run"
  if [ "${_vs_fm#file }" != "$_vs_fm" ]; then
    _vs_load_record "${_vs_fm#file }" || exit 1
  fi
  # ── CI-DEDUP-VERIFY-SELFTEST-NESTED (SWAS-282) legs — FIRST, because they are fixtures that cost seconds ──
  # Design: docs/architecture/2026-10-16-ci-dedup-verify-selftest-nested-design.md section 5. They grade the
  # record grammar (FROM-OUTPUT), the selection function (MODE), the writer's refusals (WRITER-REFUSAL) and the
  # ci.yml shape (CI-SHAPE) with the SHIPPED functions, never a copy. They sit ahead of the nested aggregate so a
  # broken mechanism fails in seconds rather than after the aggregate's minutes.
  _vsd=$(mktemp -d) || { echo "verify --selftest: FAIL (no tmpdir for the record legs)"; exit 1; }
  _vs_die() { rm -rf "$_vsd"; echo "verify --selftest: FAIL ($1)"; shift; for _vsl in "$@"; do echo "  $_vsl"; done; exit 1; }

  # -- FROM-OUTPUT: one positive anchor, then one single-change negative per refusal reason ----------------
  # The record is built from the _fo_* variables; a negative changes exactly ONE of them (in a subshell) or one
  # ARGUMENT of the pure check. Without the anchor every negative below could pass on a check that refuses all.
  _fo_hd=0123456789abcdef0123456789abcdef01234567; _fo_sf=111-222; _fo_dt=333-444
  _fo_rq=1; _fo_ch=0; _fo_rc=0; _fo_ln=4
  _fo_b1='Conformance verification (honest aggregate)'
  _fo_b2='  [control] stub                   PASS'
  _fo_b3='Summary: 1 control-checks'
  _fo_b4='RESULT: OK (controls verified; docs present)'
  _fo_write() {  # <path> : a record from the _fo_* variables
    {
      printf 'verify-output-file: v1 head=%s self=%s dirty=%s require=%s changed=%s\n' "$_fo_hd" "$_fo_sf" "$_fo_dt" "$_fo_rq" "$_fo_ch"
      printf '%s\n' "$_fo_b1" "$_fo_b2" "$_fo_b3" "$_fo_b4"
      printf 'verify-output-end: v1 rc=%s lines=%s\n' "$_fo_rc" "$_fo_ln"
    } > "$1"
  }
  _fo_expect() {  # <label> <file> <reason-substring> [head self dirty] : the pure check must REFUSE with that reason
    if _fo_r=$(_vs_record_check "$2" "${4:-$_fo_hd}" "${5:-$_fo_sf}" "${6:-$_fo_dt}"); then
      _vs_die "FROM-OUTPUT($1): the malformed record was ACCEPTED — a stale, foreign or truncated file would be graded green"
    fi
    case "$_fo_r" in
      *"$3"*) ;;
      *) _vs_die "FROM-OUTPUT($1): refused with the wrong reason" "want: $3" "got: $_fo_r" ;;
    esac
  }
  _fo_write "$_vsd/good"
  _vs_record_check "$_vsd/good" "$_fo_hd" "$_fo_sf" "$_fo_dt" >/dev/null || _vs_die "FROM-OUTPUT(anchor): the well-formed record was REFUSED — every negative below would pass vacuously"
  _fo_expect missing "$_vsd/none" 'not a readable file'
  mkdir "$_vsd/adir"; _fo_expect not-regular "$_vsd/adir" 'not a readable file'
  : > "$_vsd/empty"; _fo_expect empty "$_vsd/empty" 'empty: the file has no bytes'
  sed '1s/.*/something else entirely/' "$_vsd/good" > "$_vsd/foreign"; _fo_expect foreign "$_vsd/foreign" 'foreign: not written by verify.sh --output-file'
  _fo_expect head "$_vsd/good" 'stale: written at another commit' fedcba9876543210fedcba9876543210fedcba98
  ( _fo_hd=none; _fo_write "$_vsd/headnone" ); _fo_expect head-none "$_vsd/headnone" 'stale: written at another commit' "$_fo_hd"
  _fo_expect self "$_vsd/good" 'stale: written by another verify.sh' "$_fo_hd" 999-999
  _fo_expect dirty "$_vsd/good" 'stale: the working tree changed since the record' "$_fo_hd" "$_fo_sf" 555-666
  ( _fo_rq=0; _fo_write "$_vsd/req0" ); _fo_expect require "$_vsd/req0" 'not a full enforced run'
  ( _fo_ch=1; _fo_write "$_vsd/chg1" ); _fo_expect changed "$_vsd/chg1" 'not a full enforced run'
  sed '$d' "$_vsd/good" > "$_vsd/noend"; _fo_expect no-end "$_vsd/noend" 'truncated: no end line'
  ( _fo_ln=5; _fo_write "$_vsd/lines" ); _fo_expect lines "$_vsd/lines" 'truncated or edited'
  ( _fo_b2='RESULT: FAIL (INCOMPLETE — interrupted after 3 check(s); this is NOT a pass)'; _fo_write "$_vsd/incomplete" ); _fo_expect incomplete "$_vsd/incomplete" 'interrupted run'
  ( _fo_b4='RESULT: UNVERIFIED (TEST SEAM ACTIVE: VERIFY_CLASSIFIER)'; _fo_write "$_vsd/seam" ); _fo_expect seam-run "$_vsd/seam" 'no verdict'
  ( _fo_b4='sh: conformance/x.sh: Terminated'; _fo_write "$_vsd/crash" ); _fo_expect crash "$_vsd/crash" 'no verdict'
  ( _fo_b4='RESULT: FAIL (a control check failed)'; _fo_write "$_vsd/rc0fail" ); _fo_expect rc0-fail "$_vsd/rc0fail" 'the exit status and the RESULT line disagree'
  ( _fo_rc=1; _fo_write "$_vsd/rc1ok" ); _fo_expect rc1-ok "$_vsd/rc1ok" 'the exit status and the RESULT line disagree'

  # -- MODE: the selection is an ARGUMENT, never the environment ---------------------------------------------
  # Decoys are exported first (the option's would-be variable names and the function's own loop variables); an
  # env-reading mutant answers `file /decoy` on the first case. A stray or doubled --from-output is an error.
  _mo_is() {  # <want> args... : _vs_from_mode must answer exactly <want>
    _mo_want=$1; shift
    _mo_got=$(_vs_from_mode "$@")
    [ "$_mo_got" = "$_mo_want" ] || _vs_die "MODE: _vs_from_mode $* answered '$_mo_got', want '$_mo_want'"
  }
  (
    export VERIFY_FROM_OUTPUT=/decoy FROM_OUTPUT=/decoy _vm_n=1 _vm_path=/decoy _vm_prev=--from-output _vm_a=--from-output
    _mo_is nested --selftest
    _mo_is 'file /p' --selftest --from-output /p
    _mo_is error --selftest --from-output
    _mo_is error --require --from-output /p
    _mo_is error --selftest --from-output /p --from-output /q
  ) || exit 1
  # The script maps `error` to exit 2 BEFORE the aggregate: one cheap child run, in a one-commit temp repo with no
  # conformance/ directory, so even a mutant that ignored the flag fails every row at once instead of running minutes.
  mkdir -p "$_vsd/repo/conformance"; cp "$_SELF" "$_vsd/repo/conformance/verify.sh"
  ( cd "$_vsd/repo" && git init -q . && git -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q --allow-empty -m t ) >/dev/null 2>&1 || _vs_die "MODE: no fixture repo for the child runs"
  _vs_child() {  # <env-assignment-or-empty> args... : the temp repo's copy, a scrubbed environment; sets _vc_rc and _vc_out
    _vc_env=$1; shift
    if [ -n "$_vc_env" ]; then
      _vc_out=$(cd "$_vsd/repo" && env -u CI -u GITHUB_ACTIONS -u VERIFY_SELFTEST_REGISTRY -u VERIFY_CLASSIFIER -u VERIFY_SKIP_PREFLIGHT "$_vc_env" sh "$_vsd/repo/conformance/verify.sh" "$@" 2>&1) && _vc_rc=0 || _vc_rc=$?
    else
      _vc_out=$(cd "$_vsd/repo" && env -u CI -u GITHUB_ACTIONS -u VERIFY_SELFTEST_REGISTRY -u VERIFY_CLASSIFIER -u VERIFY_SKIP_PREFLIGHT sh "$_vsd/repo/conformance/verify.sh" "$@" 2>&1) && _vc_rc=0 || _vc_rc=$?
    fi
  }
  _vs_child '' --require --from-output /p
  [ "$_vc_rc" = 2 ] || _vs_die "MODE: a stray --from-output (no --selftest as the first word) exited $_vc_rc, not 2 — verify.sh --require --from-output F would run the aggregate and grade nothing"
  _vs_child '' --selftest --from-output
  [ "$_vc_rc" = 2 ] || _vs_die "MODE: --selftest --from-output with no value exited $_vc_rc, not 2 — it must never fall back to the nested run"
  _vs_child '' --require --output-file
  [ "$_vc_rc" = 2 ] || _vs_die "WRITER: --output-file with no value exited $_vc_rc, not 2"
  _vs_child '' --require --output-file "$_vsd/a" --output-file "$_vsd/b"
  [ "$_vc_rc" = 2 ] || _vs_die "WRITER: --output-file given twice exited $_vc_rc, not 2"
  _vs_child '' --selftest --output-file "$_vsd/a"
  [ "$_vc_rc" = 2 ] || _vs_die "WRITER: --output-file together with --selftest exited $_vc_rc, not 2"
  # The first word LEFT after the pair is stripped decides it (review L2/m2), so the pair may come first. A mutant that
  # reads the original first word would run a recorded SELFTEST here: this leg then recurses or exits non-2 and dies.
  # The child is a copy whose --selftest block is replaced by `exit 0`: a mutant that lets the recorded selftest
  # through then exits 0 here and dies on this assertion, instead of recursing into these very legs.
  awk '{ print } $0 == "if [ \"${1:-}\" = \"--selftest\" ]; then" { print "  echo SELFTEST-STUB; exit 0" }' "$_SELF" > "$_vsd/repo/conformance/verify-stub.sh"
  _vc_out=$(cd "$_vsd/repo" && env -u CI -u GITHUB_ACTIONS sh "$_vsd/repo/conformance/verify-stub.sh" --output-file "$_vsd/a" --selftest 2>&1) && _vc_rc=0 || _vc_rc=$?
  [ "$_vc_rc" = 2 ] || _vs_die "WRITER: --output-file F --selftest (pair first) exited $_vc_rc, not 2 — a recorded selftest must be refused whichever order the words come in"

  # -- WRITER-REFUSAL: the writer will not record a run it cannot vouch for ----------------------------------------
  # A sourced replacement registry runs in-process and can print RESULT: OK and exit 0 before the footer's taint,
  # so the record's grammar alone cannot refuse it: the WRITER does, before anything runs, one leg per variable.
  printf '%s\n' 'check control stub true' > "$_vsd/registry.sh"
  printf '#!/bin/sh\necho ordinary\n' > "$_vsd/classifier.sh"
  for _wr_var in VERIFY_SELFTEST_REGISTRY VERIFY_CLASSIFIER VERIFY_SKIP_PREFLIGHT; do
    case "$_wr_var" in
      VERIFY_SELFTEST_REGISTRY) _wr_val="$_vsd/registry.sh" ;;
      VERIFY_CLASSIFIER) _wr_val="$_vsd/classifier.sh" ;;
      *) _wr_val=1 ;;
    esac
    _vs_child "$_wr_var=$_wr_val" --require --output-file "$_vsd/rec-$_wr_var"
    [ "$_vc_rc" = 2 ] || _vs_die "WRITER-REFUSAL($_wr_var): exited $_vc_rc, not 2"
    printf '%s\n' "$_vc_out" | grep -q "^verify: REFUSED.*--output-file.*$_wr_var" || _vs_die "WRITER-REFUSAL($_wr_var): no 'verify: REFUSED' line naming --output-file and the variable" "output was:" "$_vc_out"
    if printf '%s\n' "$_vc_out" | grep -q 'Conformance verification'; then _vs_die "WRITER-REFUSAL($_wr_var): the aggregate STARTED — the refusal must come before anything runs"; fi
    [ -z "$(find "$_vsd" -name "rec-$_wr_var*" -o -name '.verify-rec.*')" ] || _vs_die "WRITER-REFUSAL($_wr_var): a file was written at the record path (or a staging file left) although the writer refused"
  done

  # -- LOAD-RECORD: a refused record reds with the reason and NEVER falls back to the nested run ----------------
  # (The glue is a function so this leg can drive it; a child `--selftest --from-output` run would recurse into
  # these very legs.) A missing path and an empty file, then the well-formed record from the FROM-OUTPUT leg
  # accepted only when the live values match: here it is refused as stale, which proves the live values are handed over.
  # TMPDIR points at an empty directory, so the reader's private copy of the record (review L3) is observable: it
  # must be gone again after the call, on the refusal path too.
  mkdir "$_vsd/tmp"
  for _lr_p in "$_vsd/none" "$_vsd/empty" "$_vsd/good"; do
    if _lr_o=$( TMPDIR="$_vsd/tmp"; export TMPDIR; _vs_load_record "$_lr_p" ); then _vs_die "LOAD-RECORD: $_lr_p was accepted"; fi
    case "$_lr_o" in
      "verify --selftest: FAIL (from-output: "*) ;;
      *) _vs_die "LOAD-RECORD: the refusal of $_lr_p did not print the FAIL line" "got: $_lr_o" ;;
    esac
    [ -z "$(ls -A "$_vsd/tmp")" ] || _vs_die "LOAD-RECORD: the reader left its private copy of the record behind after refusing $_lr_p"
  done
  # And the copy is what is graded: a refused record from the good file proves a copy WAS taken and then checked.
  ( TMPDIR="$_vsd/tmp"; export TMPDIR; _vs_load_record "$_vsd/good" ) | grep -q 'stale: written at another commit' || _vs_die "LOAD-RECORD: the good fixture was not refused as stale against the live head"

  # -- WRITER-RECORD: the recording run keeps the child's exit status and writes a record the reader ACCEPTS ----
  # In the temp repo (no conformance/ directory) the aggregate fails every row at once, so the child's status is
  # non-zero and known: the recorded run must exit with EXACTLY that status, and its record must pass the pure
  # check against the live values. Without this leg a writer that swallowed the status, or wrote a record the
  # reader refuses, would be caught only by CI's first live run.
  _vs_child '' --require
  _wp_rc=$_vc_rc
  _vs_child '' --require --output-file "$_vsd/rec-live"
  [ "$_vc_rc" = "$_wp_rc" ] || _vs_die "WRITER-RECORD: the recorded run exited $_vc_rc, the plain run $_wp_rc — the writer must pass the child's status through exactly"
  [ -f "$_vsd/rec-live" ] || _vs_die "WRITER-RECORD: no record was written"
  _wp_hd=$(git -C "$_vsd/repo" rev-parse HEAD)
  _wp_sf=$(cksum < "$_vsd/repo/conformance/verify.sh" | tr ' ' '-')
  _wp_dt=$(git -C "$_vsd/repo" status --porcelain --untracked-files=all | cksum | tr ' ' '-')
  _wp_why=$(_vs_record_check "$_vsd/rec-live" "$_wp_hd" "$_wp_sf" "$_wp_dt") || _vs_die "WRITER-RECORD: the writer's own record was REFUSED by the reader ($_wp_why)"
  grep -q "^verify-output-end: v1 rc=$_wp_rc " "$_vsd/rec-live" || _vs_die "WRITER-RECORD: the trailer does not carry the child's status ($_wp_rc)"
  [ -z "$(find "$_vsd" -name '.verify-rec.*')" ] || _vs_die "WRITER-RECORD: the writer left a .verify-rec.* capture or staging file behind"
  if sed -n 1p "$_vsd/rec-live" | grep -q ' shard='; then _vs_die "WRITER-RECORD: a plain recorded run carries a shard= field — a full run would read as a shard record"; fi

  # -- ROW-SHARDS (SWAS-393, slice S3 of SWAS-314; design 2026-10-24-ci-shaping section 4.2; controls C6, C7, C8) -----------
  # `--require --shard i/N --output-file F` runs the rows whose ordinal mod N is i-1 and records them; `--merge --battery <dir>
  # <records...>` refuses unless the records partition the registry exactly, and rebuilds ONE run. Every refusal below has a leg
  # AND a mutant: _mg_mut neutralises the line the SHIPPED function tags `# MG:<tag>`, and the same leg must then fail to prove
  # that line (the bad input is accepted, or refused for another reason). The functions are pure over files and arguments, so
  # they are driven directly; the flags are driven end to end in the fixture repo of the legs above.
  _mg_mut() {  # <function> <tag> [sed-expr] : the function's text with its tagged line neutralised; rc 1 when nothing changed
    _mu_o=$(sed -n "/^$1() {\$/,/^}\$/p" "$_SELF")
    if [ -z "$_mu_o" ]; then _mu_o=$(sed -n "/^  $1() {\$/,/^  }\$/p" "$_SELF"); fi   # a helper this selftest defines (two-space indent)
    _mu_m=$(printf '%s\n' "$_mu_o" | sed "/# MG:$2\$/{${3:-s/echo /: /;s/return [0-9]/:/};}")
    if [ -z "$_mu_o" ] || [ "$_mu_o" = "$_mu_m" ]; then return 1; fi
    printf '%s\n' "$_mu_m"
  }
  _mg_neg() {  # <label> <function> <tag> <sed|-> <reason> <call...> : REAL refuses with <reason>; the MUTANT does not
    _ng_l=$1; _ng_f=$2; _ng_t=$3; _ng_x=$4; _ng_r=$5; shift 5
    if _ng_o=$("$@"); then _vs_die "ROW-SHARDS($_ng_l): the bad input was ACCEPTED"; fi
    case "$_ng_o" in
      *"$_ng_r"*) ;;
      *) _vs_die "ROW-SHARDS($_ng_l): refused for the wrong reason" "want: $_ng_r" "got: $_ng_o" ;;
    esac
    if [ "$_ng_x" = - ]; then _ng_m=$(_mg_mut "$_ng_f" "$_ng_t") || _ng_m=""; else _ng_m=$(_mg_mut "$_ng_f" "$_ng_t" "$_ng_x") || _ng_m=""; fi
    if [ -z "$_ng_m" ]; then _vs_die "ROW-SHARDS($_ng_l): no mutant — $_ng_f has no line tagged MG:$_ng_t that the edit changes, so the leg proves nothing"; fi
    if _ng_mo=$( eval "$_ng_m"; "$@" 2>/dev/null ); then return 0; fi
    case "$_ng_mo" in
      *"$_ng_r"*) _vs_die "ROW-SHARDS($_ng_l): the MUTANT ($_ng_f without MG:$_ng_t) was still refused with the same reason — the leg does not prove that line" ;;
    esac
    return 0
  }
  # A hand-built shard record: header, the two heading lines, the rows, Shard-rows, Shard-counts, a footer, the trailer.
  # Knobs (set in a subshell): _sr_drop=<idx> omits that row's rendered line; _sr_rename=<idx>:<name> renders another name;
  # _sr_noshard=1 omits the Shard-rows line; _sr_counts=<text> replaces the Shard-counts values; _sr_result=OK|FAIL forces the
  # RESULT line and the trailer rc (the default follows the rows, as the real footer does).
  _sr_drop=""; _sr_rename=""; _sr_noshard=0; _sr_counts=""; _sr_result=""
  _sr_rec() {  # <out> <j/N> <tree> <idx:name[=VERDICT]>...
    _sr_o=$1; _sr_c=$2; _sr_t=$3; shift 3
    _sr_cc=0; _sr_nn=0; _sr_ff=0; _sr_uu=0; _sr_mm=0; _sr_cf=0; _sr_tok=""
    {
      printf '%s\n' 'Conformance verification (honest aggregate)' '-------------------------------------------'
      for _sr_x in "$@"; do
        _sr_i=${_sr_x%%:*}; _sr_r=${_sr_x#*:}; _sr_v=PASS
        if [ "${_sr_r%%=*}" = agent-autonomy ]; then _sr_v=JOIN; fi
        if [ "${_sr_r#*=}" != "$_sr_r" ]; then _sr_v=${_sr_r#*=}; _sr_r=${_sr_r%%=*}; fi
        _sr_tok="$_sr_tok $_sr_i:$_sr_r"
        if [ "$_sr_drop" = "$_sr_i" ]; then continue; fi
        _sr_shown=$_sr_r
        if [ "${_sr_rename%%:*}" = "$_sr_i" ]; then _sr_shown=${_sr_rename#*:}; fi
        printf '  %-9s %-18s %s\n' '[control]' "$_sr_shown" "$_sr_v"
        case "$_sr_v" in
          PASS) _sr_cc=$((_sr_cc+1)) ;;
          N-A) _sr_nn=$((_sr_nn+1)) ;;
          FAIL) _sr_cc=$((_sr_cc+1)); _sr_ff=$((_sr_ff+1)); _sr_cf=1 ;;
          UNVERIFIED) _sr_cc=$((_sr_cc+1)); _sr_uu=$((_sr_uu+1)); _sr_ff=$((_sr_ff+1)) ;;
          MISCONFIGURED) _sr_cc=$((_sr_cc+1)); _sr_mm=$((_sr_mm+1)) ;;
        esac
      done
      _sr_res=OK
      if [ "$_sr_cf" = 1 ] || [ "$_sr_uu" != 0 ] || [ "$_sr_mm" != 0 ]; then _sr_res=FAIL; fi
      if [ -n "$_sr_result" ]; then _sr_res=$_sr_result; fi
      if [ "$_sr_noshard" = 0 ]; then printf 'Shard-rows: %s%s\n' "$_sr_c" "$_sr_tok"; fi
      if [ -n "$_sr_counts" ]; then printf 'Shard-counts: %s\n' "$_sr_counts"
      else printf 'Shard-counts: controls=%s docs=0 unverified=%s nas=%s failed=%s misconfigured=%s ctrl_fail=%s\n' "$_sr_cc" "$_sr_uu" "$_sr_nn" "$_sr_ff" "$_sr_mm" "$_sr_cf"; fi
      printf '\n%s\n' 'Summary: stub'
      if [ "$_sr_res" = OK ]; then printf '%s\n' 'RESULT: OK (controls verified; docs present)'; else printf '%s\n' 'RESULT: FAIL (a control check failed)'; fi
    } > "$_sr_o.body"
    _sr_n=$(sed -n '$=' "$_sr_o.body")
    _sr_trc=0; if [ "$_sr_res" != OK ]; then _sr_trc=1; fi
    {
      printf 'verify-output-file: v1 head=%s self=%s dirty=%s require=1 changed=0 shard=%s tree=%s\n' "$_fo_hd" "$_fo_sf" "$_fo_dt" "$_sr_c" "$_sr_t"
      cat "$_sr_o.body"
      printf 'verify-output-end: v1 rc=%s lines=%s\n' "$_sr_trc" "$_sr_n"
    } > "$_sr_o"
  }
  _sr_t1=0123456789012345678901234567890123456789
  _sr_t2=9876543210987654321098765432109876543210
  _sr_reg="$_vsd/sr.reg"
  printf '%s\n' 1:alpha 2:beta 3:gamma 4:agent-autonomy 5:delta 6:eps > "$_sr_reg"
  _sr_wd="$_vsd/wd"
  _sr_v() {  # <records...> : _mg_validate against the fixture's live values, in a fresh scratch directory
    rm -rf "$_sr_wd"; mkdir "$_sr_wd"
    _mg_validate "$_sr_wd" "$_fo_hd" "$_fo_sf" "$_fo_dt" "$_sr_t1" "$_sr_reg" "$@"
  }
  # -- the registry, and the anchor: a well-formed pair is accepted and rebuilt in registry order ------------------
  _mg_registry "$_vsd/live.reg" || _vs_die "ROW-SHARDS(registry): _mg_registry failed"
  [ "$(grep -c '' "$_vsd/live.reg")" = "$(grep -c '^check ' "$_SELF")" ] || _vs_die "ROW-SHARDS(registry): the registry listing does not hold one entry per ^check row"
  [ "$(grep -c ':agent-autonomy$' "$_vsd/live.reg")" = 1 ] || _vs_die "ROW-SHARDS(registry): the agent-autonomy row is not listed exactly once"
  [ "$(sed -n 1p "$_vsd/live.reg")" = "1:branch-protection-declared" ] || _vs_die "ROW-SHARDS(registry): the first row is not 1:branch-protection-declared"
  _sr_rec "$_vsd/s1.rec" 1/2 "$_sr_t1" 1:alpha 3:gamma 5:delta=N-A
  _sr_rec "$_vsd/s2.rec" 2/2 "$_sr_t1" 2:beta 4:agent-autonomy 6:eps
  _sr_why=$(_sr_v "$_vsd/s1.rec" "$_vsd/s2.rec") || _vs_die "ROW-SHARDS(anchor): the well-formed pair was REFUSED — every negative below would pass vacuously" "$_sr_why"
  {
    printf '  %-9s %-18s %s\n' '[control]' alpha PASS; printf '  %-9s %-18s %s\n' '[control]' beta PASS
    printf '  %-9s %-18s %s\n' '[control]' gamma PASS; printf '%s\n' '@@JOIN@@'
    printf '  %-9s %-18s %s\n' '[control]' delta N-A; printf '  %-9s %-18s %s\n' '[control]' eps PASS
  } > "$_vsd/sr.expect"
  cmp -s "$_vsd/sr.expect" "$_sr_wd/rows" || _vs_die "ROW-SHARDS(anchor): the rebuilt rows are not the registry order with the JOIN marker in place" "got:" "$(cat "$_sr_wd/rows")"
  [ "$(cat "$_sr_wd/counts")" = "4 0 0 1 0 0 0" ] || _vs_die "ROW-SHARDS(anchor): the summed counters are wrong (want '4 0 0 1 0 0 0')" "got: $(cat "$_sr_wd/counts")"
  # records may be given in any order
  _sr_v "$_vsd/s2.rec" "$_vsd/s1.rec" >/dev/null || _vs_die "ROW-SHARDS(anchor): the pair in the other order was refused"
  cmp -s "$_vsd/sr.expect" "$_sr_wd/rows" || _vs_die "ROW-SHARDS(anchor): the order of the records changed the rebuilt rows"

  # -- C6: every --merge refusal, each with its mutant -------------------------------------------------------------
  _mg_neg none _mg_validate none - 'no shard record given' _sr_v
  ( _fo_hd=fedcba9876543210fedcba9876543210fedcba98; _sr_rec "$_vsd/x-head.rec" 1/2 "$_sr_t1" 1:alpha 3:gamma 5:delta )
  _mg_neg stale-record _mg_validate rec - 'stale: written at another commit' _sr_v "$_vsd/x-head.rec" "$_vsd/s2.rec"
  _mg_neg not-a-shard-record _vs_record_check shardmode - 'not a shard record' _sr_v "$_vsd/good" "$_vsd/s2.rec"
  _mg_neg full-mode-refuses-shard _vs_record_check fullmode - 'a shard record, not a full enforced run' _vs_record_check "$_vsd/s1.rec" "$_fo_hd" "$_fo_sf" "$_fo_dt"
  _sr_rec "$_vsd/x-tree.rec" 1/2 "$_sr_t2" 1:alpha 3:gamma 5:delta
  _mg_neg foreign-tree _mg_validate tree - 'graded in another tree' _sr_v "$_vsd/x-tree.rec" "$_vsd/s2.rec"
  _sr_rec "$_vsd/x-range.rec" 3/2 "$_sr_t1" 3:gamma
  _mg_neg coordinate-range _mg_validate range - 'outside 1..N' _sr_v "$_vsd/x-range.rec" "$_vsd/s2.rec"
  _sr_rec "$_vsd/x-n3.rec" 2/3 "$_sr_t1" 2:beta
  _mg_neg disagree-on-N _mg_validate n - 'disagree on N' _sr_v "$_vsd/s1.rec" "$_vsd/x-n3.rec"
  _mg_neg duplicate-coordinate _mg_validate dup - 'appears twice' _sr_v "$_vsd/s1.rec" "$_vsd/s1.rec"
  _mg_neg missing-coordinate _mg_validate missing - 'missing coordinate' _sr_v "$_vsd/s1.rec"
  _sr_rec "$_vsd/x-foreign.rec" 1/2 "$_sr_t1" 1:alpha 2:beta 5:delta
  _sr_rec "$_vsd/x-s2nob.rec" 2/2 "$_sr_t1" 4:agent-autonomy 6:eps
  _mg_neg foreign-row _mg_validate foreign - 'owned by another shard' _sr_v "$_vsd/x-foreign.rec" "$_vsd/x-s2nob.rec"
  _sr_rec "$_vsd/x-overlap.rec" 2/2 "$_sr_t1" 2:beta 3:gamma 4:agent-autonomy 6:eps
  _mg_neg overlapping-rows _mg_validate overlap - 'ran in two shards' _sr_v "$_vsd/s1.rec" "$_vsd/x-overlap.rec"
  _sr_rec "$_vsd/x-short.rec" 1/2 "$_sr_t1" 1:alpha 3:gamma
  _mg_neg union-row-missing _mg_validate union - 'not the registry' _sr_v "$_vsd/x-short.rec" "$_vsd/s2.rec"
  _sr_rec "$_vsd/x-zeta.rec" 2/2 "$_sr_t1" 2:beta 4:agent-autonomy 6:zeta
  _mg_neg union-unknown-row _mg_validate union - 'not the registry' _sr_v "$_vsd/s1.rec" "$_vsd/x-zeta.rec"
  ( _sr_drop=3; _sr_rec "$_vsd/x-drop.rec" 1/2 "$_sr_t1" 1:alpha 3:gamma 5:delta )
  _mg_neg rendered-fewer-than-listed _mg_parse body - 'rendered rows disagree' _sr_v "$_vsd/x-drop.rec" "$_vsd/s2.rec"
  ( _sr_rename=3:other; _sr_rec "$_vsd/x-rename.rec" 1/2 "$_sr_t1" 1:alpha 3:gamma 5:delta )
  _mg_neg rendered-name-differs _mg_parse bodyname - 'row name differs' _sr_v "$_vsd/x-rename.rec" "$_vsd/s2.rec"
  _sr_rec "$_vsd/x-join.rec" 1/2 "$_sr_t1" 1:alpha 3:gamma=JOIN 5:delta
  _mg_neg join-on-another-row _mg_parse join - 'only the agent-autonomy row may be' _sr_v "$_vsd/x-join.rec" "$_vsd/s2.rec"
  _sr_rec "$_vsd/x-aa.rec" 2/2 "$_sr_t1" 2:beta 4:agent-autonomy=PASS 6:eps
  _mg_neg battery-row-not-join _mg_parse join2 - 'must be written JOIN' _sr_v "$_vsd/s1.rec" "$_vsd/x-aa.rec"
  ( _sr_noshard=1; _sr_rec "$_vsd/x-nosr.rec" 1/2 "$_sr_t1" 1:alpha 3:gamma 5:delta )
  _mg_neg malformed-record _mg_parse parse - 'malformed record' _sr_v "$_vsd/x-nosr.rec" "$_vsd/s2.rec"
  # a record that shows a FAIL row is accepted when its counters and trailer say so (the anchor), and refused when either lies
  _sr_rec "$_vsd/x-fail.rec" 1/2 "$_sr_t1" 1:alpha 3:gamma=FAIL 5:delta
  _sr_why=$(_sr_v "$_vsd/x-fail.rec" "$_vsd/s2.rec") || _vs_die "ROW-SHARDS(counts anchor): an honest record with a FAIL row was REFUSED ($_sr_why)"
  [ "$(cat "$_sr_wd/counts")" = "5 0 0 0 1 0 1" ] || _vs_die "ROW-SHARDS(counts anchor): the merged counters of an honest FAIL record are wrong" "got: $(cat "$_sr_wd/counts")"
  ( _sr_counts='controls=5 docs=0 unverified=0 nas=0 failed=0 misconfigured=0 ctrl_fail=0'; _sr_rec "$_vsd/x-lie-counts.rec" 1/2 "$_sr_t1" 1:alpha 3:gamma=FAIL 5:delta )
  _mg_neg counts-hide-a-fail _mg_parse counts - 'Shard-counts disagree with its rows' _sr_v "$_vsd/x-lie-counts.rec" "$_vsd/s2.rec"
  ( _sr_result=OK; _sr_rec "$_vsd/x-lie-rc.rec" 1/2 "$_sr_t1" 1:alpha 3:gamma=FAIL 5:delta )
  _mg_neg trailer-rc-hides-a-fail _mg_parse trailerrc - 'trailer rc disagrees with its rows' _sr_v "$_vsd/x-lie-rc.rec" "$_vsd/s2.rec"
  _sr_rec "$_vsd/x-unv.rec" 1/2 "$_sr_t1" 1:alpha 3:gamma=UNVERIFIED 5:delta
  _sr_why=$(_sr_v "$_vsd/x-unv.rec" "$_vsd/s2.rec") || _vs_die "ROW-SHARDS(counts anchor): an honest record with an UNVERIFIED row was REFUSED ($_sr_why)"
  [ "$(cat "$_sr_wd/counts")" = "5 0 1 0 1 0 0" ] || _vs_die "ROW-SHARDS(counts anchor): the merged counters of an honest UNVERIFIED record are wrong" "got: $(cat "$_sr_wd/counts")"
  printf '%s\n' 1:alpha 2:beta 3:gamma 5:delta 6:eps > "$_vsd/sr-noaa.reg"
  _sr_v_noaa() { rm -rf "$_sr_wd"; mkdir "$_sr_wd"; _mg_validate "$_sr_wd" "$_fo_hd" "$_fo_sf" "$_fo_dt" "$_sr_t1" "$_vsd/sr-noaa.reg" "$@"; }
  _mg_neg registry-without-battery-row _mg_validate noaa - 'no agent-autonomy row' _sr_v_noaa "$_vsd/s1.rec" "$_vsd/s2.rec"
  mkdir "$_vsd/emptybat"
  _mg_neg battery-dir-without-records _mg_battery_recs battery - '' _mg_battery_recs "$_vsd/emptybat"
  mkdir "$_vsd/bat"; : > "$_vsd/bat/b2.rec"; : > "$_vsd/bat/b1.rec"; : > "$_vsd/bat/notes.txt"
  [ "$(_mg_battery_recs "$_vsd/bat")" = "$(printf '%s\n%s' "$_vsd/bat/b1.rec" "$_vsd/bat/b2.rec")" ] || _vs_die "ROW-SHARDS(battery): the battery directory's *.rec files were not listed (sorted, records only)"

  # -- C8: the joined battery row is PASS or FAIL, never N-A -------------------------------------------------------
  printf '%s\n' '  [control] agent-autonomy      N-A' > "$_vsd/aa-na.txt"
  printf '%s\n' '  [control] agent-autonomy      PASS' > "$_vsd/aa-pass.txt"
  _mg_aa_na "$_vsd/aa-na.txt" || _vs_die "ROW-SHARDS(C8): an N-A battery row was not recognised"
  if _mg_aa_na "$_vsd/aa-pass.txt"; then _vs_die "ROW-SHARDS(C8): a PASS battery row was read as N-A"; fi
  _ng_m=$(_mg_mut _mg_aa_na na) || _vs_die "ROW-SHARDS(C8): no mutant — _mg_aa_na has no line tagged MG:na"
  if ( eval "$_ng_m"; _mg_aa_na "$_vsd/aa-na.txt" ); then _vs_die "ROW-SHARDS(C8): the MUTANT (_mg_aa_na without MG:na) still recognised N-A — the leg does not prove that line"; fi

  # -- section 7: --merge concatenates the shards' timing files ----------------------------------------------------
  printf 'alpha\t3\tPASS\ngamma\t4\tPASS\n' > "$_vsd/s1.rec.timing"; printf 'beta\t5\tPASS\n' > "$_vsd/s2.rec.timing"
  rm -f "$_vsd/t.tsv"; printf 'aa-join\t1\tPASS\n' > "$_vsd/t.tsv"
  _mg_timing "$_vsd/t.tsv" "$_vsd/s1.rec" "$_vsd/s2.rec" "$_vsd/x-none.rec"
  [ "$(grep -c '' "$_vsd/t.tsv")" = 4 ] || _vs_die "ROW-SHARDS(timing): the shards' timing files were not appended after the existing lines (want 4 lines)" "$(cat "$_vsd/t.tsv")"
  grep -q "^gamma$(printf '\t')4$(printf '\t')PASS\$" "$_vsd/t.tsv" || _vs_die "ROW-SHARDS(timing): a shard's timing line is missing"
  _ng_m=$(_mg_mut _mg_timing timing 's/cat /: /') || _vs_die "ROW-SHARDS(timing): no mutant — _mg_timing has no line tagged MG:timing"
  printf 'aa-join\t1\tPASS\n' > "$_vsd/t2.tsv"; ( eval "$_ng_m"; _mg_timing "$_vsd/t2.tsv" "$_vsd/s1.rec" "$_vsd/s2.rec" )
  [ "$(grep -c '' "$_vsd/t2.tsv")" = 1 ] || _vs_die "ROW-SHARDS(timing): the MUTANT (_mg_timing without its cat) still concatenated — the leg does not prove that line"

  # -- the usage refusals (exit 2 before anything runs), each with its mutant ----------------------------------------
  _ru_ci() { ( unset CI; _rs_usage "$@" ); }
  _ru_ok() { _ru_ci "$@" >/dev/null || _vs_die "ROW-SHARDS(usage anchor): _rs_usage refused a valid line: $*"; }
  _ru_ok --require
  _ru_ok --require --shard 2/3
  _ru_ok --require --shard 3/3 --timing-file t
  _ru_ok --merge --battery d a b
  _ru_ok --merge a
  _ru_ok --selftest
  _mg_neg usage-merge-first _rs_usage u-merge-first - 'FIRST word' _ru_ci --require --merge a
  _mg_neg usage-merge-twice _rs_usage u-merge-twice - 'given twice' _ru_ci --merge --merge a
  _mg_neg usage-battery-alone _rs_usage u-battery-alone - 'only with --merge' _ru_ci --require --battery d
  _mg_neg usage-battery-twice _rs_usage u-battery-twice - 'given twice' _ru_ci --merge --battery d --battery e a
  _mg_neg usage-battery-no-value _rs_usage u-battery-value - 'needs a directory' _ru_ci --merge --battery
  _mg_neg usage-battery-flag-as-value _rs_usage u-battery-value - 'needs a directory' _ru_ci --merge --battery --require a
  _mg_neg usage-shard-twice _rs_usage u-shard-twice - 'given twice' _ru_ci --require --shard 1/2 --shard 2/2
  _mg_neg usage-shard-no-value _rs_usage u-shard-format - '<i>/<N>' _ru_ci --require --shard
  _mg_neg usage-shard-out-of-range _rs_usage u-shard-format - '<i>/<N>' _ru_ci --require --shard 3/2
  _mg_neg usage-shard-zero _rs_usage u-shard-format - '<i>/<N>' _ru_ci --require --shard 0/2
  _mg_neg usage-shard-not-numeric _rs_usage u-shard-format - '<i>/<N>' _ru_ci --require --shard 1/x
  _mg_neg usage-shard-two-slashes _rs_usage u-shard-format - '<i>/<N>' _ru_ci --require --shard 1/2/3
  _mg_neg usage-shard-and-merge _rs_usage u-shard-merge - 'exclusive' _ru_ci --merge --shard 1/2 a
  _mg_neg usage-shard-with-selftest _rs_usage u-shard-selftest - 'with --selftest' _ru_ci --selftest --shard 1/2
  _mg_neg usage-shard-with-changed _rs_usage u-shard-changed - 'cannot be combined with --changed' _ru_ci --require --shard 1/2 --changed f
  _mg_neg usage-merge-with-changed _rs_usage u-merge-changed - 'cannot be combined with --changed' _ru_ci --merge --changed f a
  _mg_neg usage-shard-without-require _rs_usage u-shard-require - 'needs --require' _ru_ci --shard 1/2

  # -- the selection: an argument, never the environment; the battery row is never run in a shard ----------------------
  printf '#!/bin/sh\necho "OK: stub verified"\nexit 0\n' > "$_vsd/ok.sh"
  printf '#!/bin/sh\ntouch "%s/aa-ran"\necho "OK: stub battery"\nexit 0\n' "$_vsd" > "$_vsd/aa-ran.sh"
  printf '%s\n' "check control r1 sh $_vsd/ok.sh" "check control r2 sh $_vsd/ok.sh" "check doc r3 sh $_vsd/ok.sh" \
    "check control agent-autonomy --kitselftest sh $_vsd/aa-ran.sh" "check control r5 sh $_vsd/ok.sh" "check control r6 sh $_vsd/ok.sh" \
    "check control r7 sh $_vsd/ok.sh" > "$_vsd/sel-registry.sh"
  # (the decoys are the option's would-be variable names and the internals: all must be overwritten or ignored)
  _sr_run() {  # <script> <args...> : a stub-registry run (a test seam, so it ends UNVERIFIED), decoy environment
    _sr_s=$1; shift
    ( cd "$_vsd/repo" && env -u CI -u GITHUB_ACTIONS VERIFY_SELFTEST_REGISTRY="$_vsd/sel-registry.sh" VERIFY_SHARD=3/3 SHARD=1/1 SHARDS=3 \
        SHARD_N=9 SHARD_I=9 _rs_idx=7 _rs_rows=" 9:decoy" sh "$_sr_s" "$@" 2>&1 ) || true
  }
  _sr_rows() { printf '%s\n' "$1" | grep -E '^  \[(control|doc)\] ' | sed 's/  */ /g'; }
  _sr_sc=$_vsd/repo/conformance/verify.sh
  rm -f "$_vsd/aa-ran"
  _sr_all=$(_sr_run "$_sr_sc" --require)
  [ -f "$_vsd/aa-ran" ] || _vs_die "ROW-SHARDS(selection): the plain stub run never ran the battery row (the marker leg is vacuous)"
  [ "$(_sr_rows "$_sr_all" | grep -c '')" = 7 ] || _vs_die "ROW-SHARDS(selection): a plain run under decoy variables did not print all 7 rows" "$_sr_all"
  if printf '%s\n' "$_sr_all" | grep -Eq 'JOIN|^Shard-'; then _vs_die "ROW-SHARDS(selection): a plain run printed a JOIN or Shard- line — it is no longer today's output"; fi
  rm -f "$_vsd/aa-ran"
  _sr_s1=$(_sr_run "$_sr_sc" --require --shard 1/3); _sr_s2=$(_sr_run "$_sr_sc" --require --shard 2/3); _sr_s3=$(_sr_run "$_sr_sc" --require --shard 3/3)
  [ ! -f "$_vsd/aa-ran" ] || _vs_die "ROW-SHARDS(selection): a row shard RAN the battery row — it is graded by the join, never in a shard"
  [ "$(_sr_rows "$_sr_s1")" = "$(printf '%s\n' ' [control] r1 PASS' ' [control] agent-autonomy JOIN' ' [control] r7 PASS')" ] || _vs_die "ROW-SHARDS(selection): shard 1/3 did not render rows 1, 4 (JOIN) and 7" "$(_sr_rows "$_sr_s1")"
  [ "$(_sr_rows "$_sr_s2")" = "$(printf '%s\n' ' [control] r2 PASS' ' [control] r5 PASS')" ] || _vs_die "ROW-SHARDS(selection): shard 2/3 did not render rows 2 and 5" "$(_sr_rows "$_sr_s2")"
  [ "$(_sr_rows "$_sr_s3")" = "$(printf '%s\n' ' [doc] r3 PASS' ' [control] r6 PASS')" ] || _vs_die "ROW-SHARDS(selection): shard 3/3 did not render rows 3 and 6" "$(_sr_rows "$_sr_s3")"
  printf '%s\n' "$_sr_s1" | grep -qx 'Shard-rows: 1/3 1:r1 4:agent-autonomy 7:r7' || _vs_die "ROW-SHARDS(selection): shard 1/3's Shard-rows line is wrong" "$_sr_s1"
  printf '%s\n' "$_sr_s2" | grep -qx 'Shard-rows: 2/3 2:r2 5:r5' || _vs_die "ROW-SHARDS(selection): shard 2/3's Shard-rows line is wrong" "$_sr_s2"
  printf '%s\n' "$_sr_s1" | grep -qx 'Shard-counts: controls=2 docs=0 unverified=0 nas=0 failed=0 misconfigured=0 ctrl_fail=0' || _vs_die "ROW-SHARDS(selection): shard 1/3's counters are wrong (the battery row is counted by the join, not here)" "$_sr_s1"
  # the mutants of the two selection lines are process-level: a mutated COPY of this script runs the same shards
  _sr_mutmk() {  # <tag> <sed-expr> : write the copy of this script with MG:<tag> edited (it must differ)
    sed "/# MG:$1\$/$2" "$_SELF" > "$_vsd/repo/conformance/verify-mut.sh"
    if cmp -s "$_SELF" "$_vsd/repo/conformance/verify-mut.sh"; then _vs_die "ROW-SHARDS($1): no mutant — no line tagged MG:$1 is changed by the edit"; fi
  }
  rm -f "$_vsd/aa-ran"; _sr_mutmk joinrow 's/return 0/:/'
  _sr_m=$(_sr_run "$_vsd/repo/conformance/verify-mut.sh" --require --shard 1/3)
  [ -f "$_vsd/aa-ran" ] || _vs_die "ROW-SHARDS(joinrow): the MUTANT (a shard that runs the battery row) did not run it — the leg does not prove the JOIN line"
  _sr_mutmk select 's/-ne/-eq/'
  _sr_m=$(_sr_run "$_vsd/repo/conformance/verify-mut.sh" --require --shard 2/3)
  [ "$(_sr_rows "$_sr_m")" != "$(_sr_rows "$_sr_s2")" ] || _vs_die "ROW-SHARDS(select): the MUTANT (the wrong rows) rendered shard 2/3's rows — the leg does not prove the selection line"
  rm -f "$_vsd/repo/conformance/verify-mut.sh" "$_vsd/aa-ran"

  # -- end to end in the fixture repo: the writer's shard header, the merge equals one run (C6), the join row (C8) -----
  # The battery stub exists BEFORE the records are written (an untracked file is in the working-tree checksum).
  # The battery stub is the DELIBERATELY FAILING row of the fixture: it exits 1, so a FAIL-class row (with its diagnostic block and a
  # non-zero rc) is exercised end to end whichever shell runs the other rows (bash: a missing script is rc 127 = FAIL; dash: rc 2 =
  # UNVERIFIED under --require). It is replaced by a passing stub before the legs that need a PASS.
  printf '%s\n' '#!/bin/sh' "echo \"\$*\" > $_vsd/aa-args" 'echo "FAIL: planted battery row"' 'exit 1' > "$_vsd/repo/conformance/agent-autonomy.sh"
  # What the parity leg compares must cover every rendering: the whole registry, an N-A row, a FAIL-class row, its diagnostic block, rc != 0.
  # _sr_anchor <plain-output> <rc> <registry-rows>
  _sr_anchor() {
    [ "$(printf '%s\n' "$1" | grep -Ec '^  \[(control|doc)\] ')" = "$3" ] || { echo "the plain fixture run did not render one line per registry row"; return 1; }   # MG:anchor-rows
    [ "$(printf '%s\n' "$1" | grep -Ec '^  \[(control|doc)\] .* N-A$')" -gt 0 ] || { echo "the plain fixture run has no N-A row"; return 1; }   # MG:anchor-na
    [ "$(printf '%s\n' "$1" | grep -Ec '^  \[(control|doc)\] .* (FAIL|UNVERIFIED|MISCONFIGURED)$')" -gt 0 ] || { echo "the plain fixture run has no FAIL, UNVERIFIED or MISCONFIGURED row"; return 1; }   # MG:anchor-fail
    printf '%s\n' "$1" | grep -q '^      ── ' || { echo "the plain fixture run printed no diagnostic block"; return 1; }   # MG:anchor-diag
    [ "$2" != 0 ] || { echo "the plain fixture run exited 0"; return 1; }   # MG:anchor-rc
    return 0
  }
  _sr_ao=$(printf '%s\n' '  [control] a    PASS' '  [control] b    N-A' '  [control] c    FAIL' '      ── c output ──────')
  _sr_an=$(printf '%s\n' '  [control] a    PASS' '  [control] c    FAIL' '      ── c output ──────')
  _sr_af=$(printf '%s\n' '  [control] a    PASS' '  [control] b    N-A' '      ── c output ──────')
  _sr_ad=$(printf '%s\n' '  [control] a    PASS' '  [control] b    N-A' '  [control] c    FAIL')
  _sr_why=$(_sr_anchor "$_sr_ao" 1 3) || _vs_die "ROW-SHARDS(parity anchor): a complete plain output was refused ($_sr_why)"
  _mg_neg anchor-rows _sr_anchor anchor-rows - 'one line per registry row' _sr_anchor "$_sr_ao" 1 4
  _mg_neg anchor-no-na _sr_anchor anchor-na - 'no N-A row' _sr_anchor "$_sr_an" 1 2
  _mg_neg anchor-no-fail-class _sr_anchor anchor-fail - 'no FAIL, UNVERIFIED or MISCONFIGURED row' _sr_anchor "$_sr_af" 1 2
  _mg_neg anchor-no-diagnostic _sr_anchor anchor-diag - 'no diagnostic block' _sr_anchor "$_sr_ad" 1 3
  _mg_neg anchor-rc-zero _sr_anchor anchor-rc - 'exited 0' _sr_anchor "$_sr_ao" 0 3
  mkdir "$_vsd/shards"
  _vs_child '' --require
  _sr_plain=$_vc_out; _sr_plain_rc=$_vc_rc
  _sr_why=$(_sr_anchor "$_sr_plain" "$_sr_plain_rc" "$(grep -c '' "$_vsd/live.reg")") || _vs_die "ROW-SHARDS(parity): $_sr_why (the parity leg would not cover every rendering)" "rc $_sr_plain_rc" "$(printf '%s\n' "$_sr_plain" | sed -n '1,8p')"
  printf '%s\n' "$_sr_plain" | grep -Eq '^  \[control\] +agent-autonomy +FAIL$' || _vs_die "ROW-SHARDS(parity): the planted battery row did not render FAIL in the plain run" "$(printf '%s\n' "$_sr_plain" | grep agent-autonomy)"
  rm -f "$_vsd/aa-args"
  _vs_child '' --require --shard 1/2 --output-file "$_vsd/shards/a.rec" --timing-file "$_vsd/shards/a.rec.timing"
  _vs_child '' --require --shard 2/2 --output-file "$_vsd/shards/b.rec" --timing-file "$_vsd/shards/b.rec.timing"
  [ -f "$_vsd/shards/a.rec" ] && [ -f "$_vsd/shards/b.rec" ] || _vs_die "ROW-SHARDS(writer): a shard run wrote no record"
  _sr_hd=$(git -C "$_vsd/repo" rev-parse HEAD); _sr_tr=$(git -C "$_vsd/repo" write-tree)
  _sr_sf=$(cksum < "$_vsd/repo/conformance/verify.sh" | tr ' ' '-')
  _sr_dt=$(git -C "$_vsd/repo" status --porcelain --untracked-files=all | cksum | tr ' ' '-')
  sed -n 1p "$_vsd/shards/a.rec" | grep -q " shard=1/2 tree=$_sr_tr\$" || _vs_die "ROW-SHARDS(writer): the shard record's header does not end in ' shard=1/2 tree=<this tree>'" "$(sed -n 1p "$_vsd/shards/a.rec")"
  _sr_why=$(_vs_record_check "$_vsd/shards/a.rec" "$_sr_hd" "$_sr_sf" "$_sr_dt" shard) || _vs_die "ROW-SHARDS(writer): the writer's own shard record was REFUSED by the reader ($_sr_why)"
  _sr_why=$(_vs_record_check "$_vsd/shards/a.rec" "$_sr_hd" "$_sr_sf" "$_sr_dt") && _vs_die "ROW-SHARDS(writer): --selftest --from-output would grade a SHARD record as a full run"
  [ "$(cat "$_vsd/shards/a.rec" "$_vsd/shards/b.rec" | grep -Ec '^  \[control\] +agent-autonomy +JOIN$')" = 1 ] || _vs_die "ROW-SHARDS(writer): the battery row is not written JOIN in exactly one record"
  [ ! -f "$_vsd/aa-args" ] || _vs_die "ROW-SHARDS(writer): a shard run executed the battery row (the stub recorded its arguments)"
  _vs_child '' --merge "$_vsd/shards/a.rec" "$_vsd/shards/b.rec"
  [ "$_vc_rc" = "$_sr_plain_rc" ] || _vs_die "ROW-SHARDS(parity): the merge exited $_vc_rc, the plain run $_sr_plain_rc"
  if [ "$_vc_out" != "$_sr_plain" ]; then
    printf '%s\n' "$_sr_plain" > "$_vsd/parity.plain"; printf '%s\n' "$_vc_out" > "$_vsd/parity.merge"
    _vs_die "ROW-SHARDS(parity): the merged output is not the plain run's output, byte for byte" "$(diff "$_vsd/parity.plain" "$_vsd/parity.merge" | head -n 12)"
  fi
  [ "$(cat "$_vsd/aa-args")" = "" ] || _vs_die "ROW-SHARDS(parity): without --battery the battery row did not run as today's bare row (arguments: $(cat "$_vsd/aa-args"))"
  # the flags are refused with exit 2 before anything runs, by the real argument path
  _vs_child '' --require --shard 3/2
  [ "$_vc_rc" = 2 ] || _vs_die "ROW-SHARDS(usage): --shard 3/2 exited $_vc_rc, not 2"
  printf '%s\n' "$_vc_out" | grep -q '^verify: usage error' || _vs_die "ROW-SHARDS(usage): the refusal is not a 'verify: usage error' line" "$_vc_out"
  if printf '%s\n' "$_vc_out" | grep -q 'Conformance verification'; then _vs_die "ROW-SHARDS(usage): a refused --shard started the aggregate"; fi
  _vs_child '' --merge --bogus "$_vsd/shards/a.rec"
  [ "$_vc_rc" = 2 ] || _vs_die "ROW-SHARDS(usage): --merge with an unknown flag exited $_vc_rc, not 2"
  _vs_child '' --require --output-file "$_vsd/never.rec" --merge "$_vsd/shards/a.rec"
  [ "$_vc_rc" = 2 ] || _vs_die "ROW-SHARDS(usage): --merge after another word exited $_vc_rc, not 2"
  # nothing is printed by a refused merge (not even the heading), and the refusals are exit 1 (a seam: 2)
  _vs_child '' --merge "$_vsd/shards/a.rec"
  [ "$_vc_rc" = 1 ] || _vs_die "ROW-SHARDS(refusal): a merge of one of two records exited $_vc_rc, not 1"
  printf '%s\n' "$_vc_out" | grep -q 'missing coordinate' || _vs_die "ROW-SHARDS(refusal): the refusal does not name the missing coordinate" "$_vc_out"
  if printf '%s\n' "$_vc_out" | grep -q 'Conformance verification'; then _vs_die "ROW-SHARDS(refusal): a refused merge printed rows"; fi
  _vs_child "VERIFY_SELFTEST_REGISTRY=$_vsd/sel-registry.sh" --merge "$_vsd/shards/a.rec" "$_vsd/shards/b.rec"
  [ "$_vc_rc" = 2 ] || _vs_die "ROW-SHARDS(refusal): a merge under a test seam exited $_vc_rc, not 2"
  printf '%s\n' "$_vc_out" | grep -q 'REFUSED (a test seam is active' || _vs_die "ROW-SHARDS(refusal): a merge under a test seam was not refused by name" "$_vc_out"
  _ng_m=$(_mg_mut _mg_main seam) || _vs_die "ROW-SHARDS(seam): no mutant — _mg_main has no line tagged MG:seam"
  SEAM_ACTIVE=x; _sr_sm=$( eval "$_ng_m"; MERGE_RECS=""; _mg_main 2>&1 ) || true; SEAM_ACTIVE=
  case "$_sr_sm" in
    *'REFUSED (a test seam is active'*) _vs_die "ROW-SHARDS(seam): the MUTANT (_mg_main without MG:seam) still refused the seam — the leg does not prove that line" ;;
  esac
  # C8 end to end: the battery directory's records go to `agent-autonomy.sh --join`, and N-A can never stand
  mkdir -p "$_vsd/bat2"; : > "$_vsd/bat2/x.rec"
  printf '%s\n' '#!/bin/sh' "echo \"\$*\" > $_vsd/aa-args" 'echo "OK: stub joined"' 'exit 0' > "$_vsd/repo/conformance/agent-autonomy.sh"
  _vs_child '' --merge --battery "$_vsd/bat2" "$_vsd/shards/a.rec" "$_vsd/shards/b.rec"
  printf '%s\n' "$_vc_out" | grep -Eq '^  \[control\] +agent-autonomy +PASS$' || _vs_die "ROW-SHARDS(C8): a passing joined battery did not render PASS" "$(printf '%s\n' "$_vc_out" | grep agent-autonomy)"
  [ "$(cat "$_vsd/aa-args")" = "--join $_vsd/bat2/x.rec" ] || _vs_die "ROW-SHARDS(C8): the battery row was not run as 'agent-autonomy.sh --join <the *.rec files>'" "got: $(cat "$_vsd/aa-args")"
  printf '%s\n' '#!/bin/sh' 'echo "N/A: deferred to a CI job"' 'exit 0' > "$_vsd/repo/conformance/agent-autonomy.sh"
  _vs_child '' --merge --battery "$_vsd/bat2" "$_vsd/shards/a.rec" "$_vsd/shards/b.rec"
  printf '%s\n' "$_vc_out" | grep -Eq '^  \[control\] +agent-autonomy +FAIL$' || _vs_die "ROW-SHARDS(C8): a joined battery that answered N/A did not render FAIL" "$(printf '%s\n' "$_vc_out" | grep agent-autonomy)"
  if printf '%s\n' "$_vc_out" | grep -Eq '^  \[control\] +agent-autonomy +N-A$'; then _vs_die "ROW-SHARDS(C8): the joined battery row rendered N-A — adopter-census would need an exemption"; fi
  _c8na=$(printf '%s\n' "$_vc_out" | grep -Ec '^  \[(control|doc)\] .* N-A$') || true
  printf '%s\n' "$_vc_out" | grep '^Summary:' | grep -q "· $_c8na n/a ·" || _vs_die "ROW-SHARDS(C8): the Summary's n/a count and the N-A rows differ after the rewrite"
  # ...but WITHOUT --battery (the kit tree's merge, whose battery defers to guard-battery) a deferral stays the N-A it is today
  _vs_child '' --merge "$_vsd/shards/a.rec" "$_vsd/shards/b.rec"
  printf '%s\n' "$_vc_out" | grep -Eq '^  \[control\] +agent-autonomy +N-A$' || _vs_die "ROW-SHARDS(C8): without --battery a deferred battery row no longer renders N-A (the kit tree's merge would turn red)"
  printf '%s\n' '#!/bin/sh' 'echo "FAIL: stub"' 'exit 1' > "$_vsd/repo/conformance/agent-autonomy.sh"
  _vs_child '' --merge --battery "$_vsd/bat2" "$_vsd/shards/a.rec" "$_vsd/shards/b.rec"
  printf '%s\n' "$_vc_out" | grep -Eq '^  \[control\] +agent-autonomy +FAIL$' || _vs_die "ROW-SHARDS(C8): a failing joined battery did not render FAIL" "$(printf '%s\n' "$_vc_out" | grep agent-autonomy)"
  _vs_child '' --merge --battery "$_vsd/emptybat" "$_vsd/shards/a.rec" "$_vsd/shards/b.rec"
  [ "$_vc_rc" = 1 ] || _vs_die "ROW-SHARDS(refusal): a --battery directory with no record exited $_vc_rc, not 1"
  printf '%s\n' "$_vc_out" | grep -q 'holds no \*.rec' || _vs_die "ROW-SHARDS(refusal): the empty battery directory was not named" "$_vc_out"
  printf '%s\n' '#!/bin/sh' 'echo "OK: stub joined"' 'exit 0' > "$_vsd/repo/conformance/agent-autonomy.sh"
  # section 7 end to end: every registry row is timed exactly once across the shards' files and the merge's own join row
  rm -f "$_vsd/t-all.tsv"
  _vs_child '' --merge --timing-file "$_vsd/t-all.tsv" "$_vsd/shards/a.rec" "$_vsd/shards/b.rec"
  [ "$(cut -f1 "$_vsd/t-all.tsv" | LC_ALL=C sort)" = "$(sed 's/^[0-9]*://' "$_vsd/live.reg" | LC_ALL=C sort)" ] || _vs_die "ROW-SHARDS(timing): the merged timing file does not hold each registry row exactly once"
  rm -rf "$_vsd/shards" "$_vsd/bat" "$_vsd/bat2" "$_vsd/emptybat" "$_sr_wd"

  # -- CI-SHAPE: the merged job keeps BOTH steps and they name the SAME record --------------------------------------
  # Kit tree only (disclosed N/A elsewhere, as the --kitself rows). Three fixtures, then the live ci.yml.
  _cs_good='    steps:
      - run: sh conformance/verify.sh --require --output-file "$RUNNER_TEMP/v.out"
      - name: grade
        if: ${{ !cancelled() }}
        run: sh conformance/verify.sh --selftest --from-output "$RUNNER_TEMP/v.out"
      # sh conformance/verify.sh --selftest   (a COMMENTED bare line must not count)'
  _cs_expect() {  # <label> <yaml-body> <ok|bad>
    printf 'jobs:\n  cf-x:\n%s\n' "$2" > "$_vsd/ci-fixture.yml"
    if _cs_r=$(_vs_ci_shape "$_vsd/ci-fixture.yml"); then _cs_ok=ok; else _cs_ok=bad; fi
    [ "$_cs_ok" = "$3" ] || _vs_die "CI-SHAPE($1): graded '$_cs_ok', want '$3'" "reason: $_cs_r"
    case "$_cs_r" in
      *"${4:-}"*) ;;
      *) _vs_die "CI-SHAPE($1): refused for the wrong reason" "want: $4" "got: $_cs_r" ;;
    esac
  }
  _cs_expect 'flag present' "$_cs_good" ok
  _cs_expect 'flag dropped' '    steps:
      - run: sh conformance/verify.sh --require --output-file "$RUNNER_TEMP/v.out"
      - run: sh conformance/verify.sh --selftest' bad
  _cs_expect 'grading step deleted' '    steps:
      - run: sh conformance/verify.sh --require --output-file "$RUNNER_TEMP/v.out"' bad
  _cs_expect 'extra bare selftest line' "$_cs_good
      - run: sh conformance/verify.sh --selftest" bad
  _cs_expect 'different record path' '    steps:
      - run: sh conformance/verify.sh --require --output-file "$RUNNER_TEMP/v.out"
      - run: sh conformance/verify.sh --selftest --from-output "$RUNNER_TEMP/other.out"' bad
  # A NEUTRALISED grading step is as dark as a deleted one (review M1): each fixture changes ONE thing in the good
  # pair, and the reason must name the disqualifier. continue-on-error and a step `if:` other than the exact
  # !cancelled() expression stop the step from ever failing the job; a shell tail after the command masks its status.
  _cs_req='      - run: sh conformance/verify.sh --require --output-file "$RUNNER_TEMP/v.out"'
  _cs_gr='        run: sh conformance/verify.sh --selftest --from-output "$RUNNER_TEMP/v.out"'
  _cs_expect 'continue-on-error on the step' "    steps:
$_cs_req
      - name: grade
        if: \${{ !cancelled() }}
        continue-on-error: true
$_cs_gr" bad 'the grading step sets continue-on-error'
  _cs_expect 'continue-on-error on the job' "    continue-on-error: true
    steps:
$_cs_req
      - name: grade
        if: \${{ !cancelled() }}
$_cs_gr" bad 'job cf-x sets continue-on-error'
  _cs_expect 'step if: false' "    steps:
$_cs_req
      - name: grade
        if: false
$_cs_gr" bad 'an if: other than exactly'
  _cs_expect 'command || true' "    steps:
$_cs_req
      - name: grade
        if: \${{ !cancelled() }}
$_cs_gr || true" bad 'can mask its exit status'
  _cs_expect 'continue-on-error: false is allowed' "    steps:
$_cs_req
      - name: grade
        if: \${{ !cancelled() }}
        continue-on-error: false
$_cs_gr" ok
  # SWAS-393: a row-shard leg writes a PARTIAL record that only --merge grades, so it owes no grading step; the merge job is the
  # recorder (it writes the full record), so it owes exactly the one --selftest --from-output of the SAME path.
  _cs_mj='  cf-m:
    needs:
      - changes
      - cf-x
    steps:
      - run: sh conformance/verify.sh --merge --output-file "$RUNNER_TEMP/v.out" "$RUNNER_TEMP"/r/*.rec
      - name: grade
        if: ${{ !cancelled() }}
        run: sh conformance/verify.sh --selftest --from-output "$RUNNER_TEMP/v.out"'
  _cs_expect 'a row-shard leg is not a recorder when a merge job lists it' "    steps:
      - run: sh conformance/verify.sh --require --shard \"\$S/2\" --output-file \"\$RUNNER_TEMP/s.rec\"
$_cs_mj" ok
  _cs_expect 'a row-shard job no merge job lists is a sole verdict' '    steps:
      - run: sh conformance/verify.sh --require --shard "$S/2" --output-file "$RUNNER_TEMP/s.rec"' bad 'no --merge job lists it'
  _cs_expect 'a row-shard job a merge job does not list' "    steps:
      - run: sh conformance/verify.sh --require --shard \"\$S/2\" --output-file \"\$RUNNER_TEMP/s.rec\"
$(printf '%s\n' "$_cs_mj" | sed 's/      - cf-x/      - cf-y/')" bad 'no --merge job lists it'
  _cs_expect 'a merge job listing the shard job inline' '    steps:
      - run: sh conformance/verify.sh --require --shard "$S/2" --output-file "$RUNNER_TEMP/s.rec"
  cf-m:
    needs: [changes, cf-x]
    steps:
      - run: sh conformance/verify.sh --merge --output-file "$RUNNER_TEMP/v.out" "$RUNNER_TEMP"/r/*.rec
      - name: grade
        if: ${{ !cancelled() }}
        run: sh conformance/verify.sh --selftest --from-output "$RUNNER_TEMP/v.out"' ok
  _cs_expect 'a merge that is never graded' '    steps:
      - run: sh conformance/verify.sh --merge --output-file "$RUNNER_TEMP/v.out" "$RUNNER_TEMP"/r/*.rec' bad 'records'
  _cs_expect 'a merge graded by the same record' '    steps:
      - run: sh conformance/verify.sh --merge --output-file "$RUNNER_TEMP/v.out" "$RUNNER_TEMP"/r/*.rec
      - name: grade
        if: ${{ !cancelled() }}
        run: sh conformance/verify.sh --selftest --from-output "$RUNNER_TEMP/v.out"' ok
  if [ -f docs/ROADMAP-KIT.md ] || [ -f .github/workflows/golden-path.yml ]; then
    [ -f .github/workflows/ci.yml ] || _vs_die "CI-SHAPE: the kit tree has no .github/workflows/ci.yml to grade"
    _cs_live=$(_vs_ci_shape .github/workflows/ci.yml) || _vs_die "CI-SHAPE: the live ci.yml is mis-shaped" "$_cs_live"
  else
    echo "verify --selftest: CI-SHAPE leg N/A — not the kit tree (no kit markers), so there is no ci.yml of the kit to grade"
  fi
  rm -rf "$_vsd"

  # -- the source of $out: the record loaded at the top of this block, or, without --from-output, the nested run as ever --
  if [ "$_vs_src" = "nested run" ]; then
    # $_SELF, not $0: after the top-level cd, a relative $0 no longer resolves. VERIFY_SKIP_PREFLIGHT
    # because THIS nested run is the renderer probe — on a HEAD-less checkout the pre-flight would
    # refuse it in a second and every leg below would grade an empty string (review R2). The pre-flight
    # LANE stays proven: its dedicated leg further down runs a real --require WITHOUT this variable.
    out=$(VERIFY_SKIP_PREFLIGHT=1 sh "$_SELF" 2>&1) || true
    # SWAS-376: the ONE place the agent-autonomy row's rendered verdict is printed (the hermetic lane classifies it as deferred or not).
    _vs_probe_line "$out"
  fi
  printf '%s\n' "$out" | grep -q "control-checks" || { echo "verify --selftest: FAIL (no summary)"; exit 1; }
  printf '%s\n' "$out" | grep -q "UNVERIFIED is NOT a pass" || { echo "verify --selftest: FAIL (no honesty footer)"; exit 1; }
  printf '%s\n' "$out" | grep -Eq '\[control\]|\[doc\]' || { echo "verify --selftest: FAIL (no classification)"; exit 1; }
  # non-vacuous: at least one [control] must actually PASS — a render of only FAILs (green-while-dark)
  # must NOT satisfy --selftest. The synthetic line below proves the control-PASS grep is load-bearing.
  printf '%s\n' "$out" | grep -q '\[control\] .* PASS' || { echo "verify --selftest: FAIL (no [control] PASS — vacuous render)"; exit 1; }
  if printf '  [control] x                FAIL\n' | grep -q '\[control\] .* PASS'; then echo "verify --selftest: FAIL (vacuous fixture wrongly matched control-PASS)"; exit 1; fi

  # -- C6 COUNT leg: the Summary's `n/a` field must EQUAL the N-A rows the run actually rendered -------
  # "Rendered AND COUNTED" is half the C6 claim, and until now NOTHING in this file asserted a count —
  # every leg graded tokens. Reuses the aggregate already captured above (no extra run). Both directions
  # are load-bearing: a mutant that renders N-A without `nas++` under-counts and dies here; one that
  # increments without rendering over-counts and dies here; and the >0 floor stops the equality going
  # vacuous on a hypothetical tree where nothing skips (the kit tree measured ≥14 at C6).
  _c6rows=$(printf '%s\n' "$out" | grep -Ec '^  \[(control|doc)\] .* N-A$') || true
  _c6na=$(printf '%s\n' "$out" | grep '^Summary:' | sed -n 's/.*· \([0-9][0-9]*\) n\/a ·.*/\1/p')
  case "${_c6na:-x}" in ''|*[!0-9]*)
    echo "verify --selftest: FAIL (the Summary line carries no parseable n/a field — the third outcome is"
    echo "  rendered but not counted, which is the half of the C6 claim nothing used to assert)"; exit 1 ;;
  esac
  if [ "$_c6rows" -eq 0 ]; then
    echo "verify --selftest: FAIL (the aggregate rendered ZERO N-A rows — either every check really executed"
    echo "  (then this leg is vacuous and the floor must be re-measured) or the skip classifier is dead)"; exit 1
  fi
  if [ "$_c6na" != "$_c6rows" ]; then
    echo "verify --selftest: FAIL (Summary says $_c6na n/a but $_c6rows N-A row(s) were rendered — the count and"
    echo "  the render disagree, so one of them is lying about how much the run actually verified)"; exit 1
  fi

  # -- SIBLING-LINE leg (PR 10, VERIFY-HEADLINE-TRUTH): the census reconciliation-of-record ------------
  # The `Summary:` scalar is parsed by the C6 leg above AND by three ci.yml walk steps, verify.sh:255 and
  # promotion-readiness.sh:407 — every one of them anchors `^Summary:` and reads the match as ONE line.
  # So the census sibling must NOT begin with that token: a second `^Summary:` match turns those scalars
  # multi-line and their sed reads garbage. BOTH halves are pinned, and both were watched RED: exactly
  # one `^Summary:` line exists, and the `Scripts:` sibling is present with all four populations.
  _sibn=$(printf '%s\n' "$out" | grep -c '^Summary:') || true
  if [ "$_sibn" != 1 ]; then
    echo "verify --selftest: FAIL (the run emitted $_sibn line(s) beginning 'Summary:', want exactly 1 —"
    echo "  every consumer of that scalar anchors ^Summary: and reads one line; a second match makes"
    echo "  their sed parse a multi-line string, which is how the n/a walk goes silently wrong)"; exit 1
  fi
  printf '%s\n' "$out" | grep -qE '^Scripts: [0-9]+ unique conformance scripts across [0-9]+ rows \([0-9]+ conformance/\*\.sh on disk; [0-9]+ registered by no row' || {
    echo "verify --selftest: FAIL (no 'Scripts:' census sibling line — the run states how many ROWS it"
    echo "  holds but not how many SCRIPTS they invoke, which is the unreconciled count verify.sh:579"
    echo "  used to answer with 'three methods, three answers')"; exit 1; }

  # ── INCOMPLETE leg (K16) — an INTERRUPTED run must SAY it was interrupted and exit non-zero ──────────
  # WHY THIS EXISTS. The aggregate takes minutes over well over a hundred checks (see the header: the
  # authoritative count is the run's own Summary line, never a figure copied into prose) — longer than the default foreground
  # command cap of the agent harnesses people drive this kit with. In CP-7 run 4 a wrapper stopped
  # reading at ~43s of output and the run was read as an unexplained stall; with no trap, a killed run's
  # partial output is INDISTINGUISHABLE from a run still in progress, so the consumer must notice an
  # ABSENCE. That is the weakest possible signal, and it is how a truncated run gets mistaken for a
  # green one. `INCOMPLETE is not a pass` is the second honesty class beside `UNVERIFIED is not a pass`.
  #
  # BEHAVIOURAL, never a text grep for `trap` — presence is not effect. This launches a REAL run, kills
  # it mid-flight with SIGTERM, and asserts on what the process actually emitted and returned.
  _kout=$(mktemp) || { echo "verify --selftest: FAIL (no tmpdir for the INCOMPLETE leg)"; exit 1; }
  VERIFY_SKIP_PREFLIGHT=1 sh "$_SELF" > "$_kout" 2>&1 &   # same reason as the renderer probe above:
                                                          # this leg needs a LONG run to kill mid-flight
  _kpid=$!
  sleep 2                      # let it start and clear at least one check; the trap fires regardless
  kill -TERM "$_kpid" 2>/dev/null || true
  if wait "$_kpid"; then _krc=0; else _krc=$?; fi
  if ! grep -q 'RESULT: FAIL (INCOMPLETE' "$_kout"; then
    echo "verify --selftest: FAIL (a SIGTERM-killed run did not announce INCOMPLETE — a truncated run is"
    echo "  indistinguishable from a passing one; the consumer would have to notice an ABSENCE)"
    rm -f "$_kout"; exit 1
  fi
  # Load-bearing: announcing INCOMPLETE while exiting 0 would be worse than silence — a caller checking
  # only the exit status would score a truncated run as GREEN.
  if [ "$_krc" = 0 ]; then
    echo "verify --selftest: FAIL (interrupted run exited 0 — a truncated run must never score as a pass)"
    rm -f "$_kout"; exit 1
  fi
  rm -f "$_kout"


  # -- K3 leg: a FAILING gate must print WHY, not just FAIL -----------------------------------------
  # This block now sits AFTER the function definitions precisely so it can drive the REAL check() and
  # emit_diag(), not a replica. Testing a copy of the logic is the classic way a green proves nothing
  # about the shipped path.
  _d=$(mktemp -d) || { echo "verify --selftest: FAIL (no tmpdir for the K3 leg)"; exit 1; }
  printf '#!/bin/sh\necho "K3-DIAGNOSTIC-MARKER: /some/path:42"\nexit 1\n' > "$_d/failing.sh"
  _k3=$( controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0
         check control k3demo sh "$_d/failing.sh" 2>&1 )
  rm -f "$_d/failing.sh"; rmdir "$_d" 2>/dev/null || true
  printf '%s\n' "$_k3" | grep -q 'K3-DIAGNOSTIC-MARKER' || {
    echo "verify --selftest: FAIL (a failing check hid its diagnostic -- the operator must re-run the"
    echo "  individual gate to learn what broke, which is the K3 round trip this gate exists to remove)"
    exit 1; }
  # Load-bearing the other way: a PASSING check must stay ONE line, or every green run drowns in output.
  _k3p=$( controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0
          check control k3ok true 2>&1 )
  [ "$(printf '%s\n' "$_k3p" | grep -c .)" = 1 ] || {
    echo "verify --selftest: FAIL (a PASSING check emitted more than one line -- the aggregate must stay scannable)"
    exit 1; }

  # -- CP7R5-VERIFY-NONTS leg: a --kitself check N/As on an adopter tree, RUNS on the kit tree ----------
  # A kit-self check (validates the kit's OWN reference profiles / dev selftests) has no meaning on an
  # already-incepted ADOPTER tree, where incept has pruned the fixtures it needs (e.g. ci-gates hardcodes
  # profiles/typescript-node/ci.yml; adopter-preflight's selftest reads the pruned .nvmrc). The --kitself
  # flag renders N-A there -- keyed on the un-spoofable kit-marker set (BOTH docs/ROADMAP-KIT.md AND
  # .github/workflows/golden-path.yml absent == an adopter export) -- and must ACTUALLY RUN in the kit repo.
  # Both halves are load-bearing: without N-A a non-ts adopter's first verify.sh --require is red; without
  # RUN an always-N-A mutant masks a genuinely-broken kit-self reference on the kit tree. Drives the REAL
  # check() in a counter-reset subshell (mirrors the K3 leg), never a replica.
  _kna=$( cd "$(mktemp -d)" || exit 1        # a marker-less cwd == an adopter export
          controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
          check control kitdemo --kitself false 2>&1 )
  printf '%s\n' "$_kna" | grep -q 'kitdemo .* N-A' || {
    echo "verify --selftest: FAIL (a --kitself check did not render N-A on a marker-less adopter tree --"
    echo "  a non-ts adopter's first verify.sh --require would be red on a kit-self check)"; exit 1; }
  if printf '%s\n' "$_kna" | grep -q 'FAIL'; then
    echo "verify --selftest: FAIL (a --kitself check RAN its command on a marker-less tree instead of N-A)"; exit 1
  fi
  # Load-bearing negative: in the kit repo (markers present) --kitself must NOT suppress the check -- a
  # `false` command FAILs. An always-N-A mutant renders N-A here and dies on this assertion.
  _krun=$( controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
           check control kitdemo --kitself false 2>&1 )
  printf '%s\n' "$_krun" | grep -q 'kitdemo .* FAIL' || {
    echo "verify --selftest: FAIL (a --kitself check did not RUN on the kit tree -- an always-N-A guard would"
    echo "  mask a genuinely-broken kit-self reference; markers present must mean the check executes)"; exit 1; }

  # -- ADOPTER-GATES-INERT (A3) leg: --adopter is METADATA-ONLY -- it RUNS the command, never skips it,
  # even on a marker-less (adopter) tree, and it is mutually exclusive with --kitself ------------------
  # The whole point of the new flag is that a row whose SUBJECT is the adopter's own artifact must keep
  # RUNNING post-inception -- --kitself's registry-level skip would silence it forever, which is exactly
  # the A3 defect (roadmap-current et al.). So the load-bearing assertion is the NEGATIVE: on a
  # marker-less cwd, --kitself would render N-A without invoking the command at all; --adopter must NOT.
  _adna=$( cd "$(mktemp -d)" || exit 1       # a marker-less cwd == an adopter export
           controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
           check control addemo --adopter false 2>&1 )
  printf '%s\n' "$_adna" | grep -q 'addemo .* FAIL' || {
    echo "verify --selftest: FAIL (a --adopter check did NOT run its command on a marker-less (adopter) tree --"
    echo "  --adopter must be metadata-only, never a --kitself-style skip, or a real adopter-subject gate goes"
    echo "  permanently silent)"; exit 1; }
  # And it must run in the kit repo too (no accidental new skip path on the kit tree either).
  _adkit=$( controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
            check control addemo2 --adopter true 2>&1 )
  printf '%s\n' "$_adkit" | grep -q 'addemo2 .* PASS' || {
    echo "verify --selftest: FAIL (a --adopter check did not run+PASS on the kit tree)"; exit 1; }
  # MUTUAL EXCLUSION: a row declaring BOTH flags is a registry error, either order, and must not silently
  # pick one.
  if ( controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
       check control admix --kitself --adopter true ) >/dev/null 2>&1; then
    echo "verify --selftest: FAIL (a check registering BOTH --kitself and --adopter did not error -- they"
    echo "  must be mutually exclusive)"; exit 1
  fi
  if ( controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
       check control admix2 --adopter --kitself true ) >/dev/null 2>&1; then
    echo "verify --selftest: FAIL (a check registering --adopter then --kitself did not error -- the"
    echo "  mutual-exclusion check must not depend on flag order)"; exit 1
  fi

  # -- CP7R5-VERIFY-SUMMARY leg: the RESULT sentence must be honest about failing doc-checks -----------
  # A run with a failing doc-check must NOT print "docs present"; a fully-green run must keep it. Drives
  # the REAL result_sentence() with synthetic counters -- no full aggregate. Both halves are load-bearing:
  # the first kills a mutant that keeps "docs present" over a failure; the second kills one that always
  # cries "FAILED". Exit semantics are UNCHANGED (a doc-only failure still returns 0) -- this is wording.
  _rsf=$( ctrl_fail=0; unverified=0; failed=1; REQUIRE=0; result_sentence )
  printf '%s\n' "$_rsf" | grep -q 'doc-check(s) FAILED' || {
    echo "verify --selftest: FAIL (a failing doc-check did not surface in the RESULT sentence)"; exit 1; }
  if printf '%s\n' "$_rsf" | grep -q 'docs present'; then
    echo "verify --selftest: FAIL (RESULT claimed 'docs present' while a doc-check FAILED -- the summary lied)"; exit 1
  fi
  _rsok=$( ctrl_fail=0; unverified=0; failed=0; REQUIRE=0; result_sentence )
  printf '%s\n' "$_rsok" | grep -q 'docs present' || {
    echo "verify --selftest: FAIL (a fully-green run lost its 'docs present' summary)"; exit 1; }
  # Pins the JOINT predicate: N-A requires BOTH markers absent (`&&`). A MIXED tree (exactly one marker
  # present) must RUN -- so an `&&`->`||` mutation, which would N-A a mixed tree, dies here. This is the only
  # leg that constructs a one-marker tree; without it the conjunction is untested (both other legs use
  # all-absent / all-present trees, on which `&&` and `||` agree).
  _kmix=$( _md=$(mktemp -d) && mkdir -p "$_md/docs" && : > "$_md/docs/ROADMAP-KIT.md" && cd "$_md" || exit 1
           controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
           check control kitdemo --kitself false 2>&1 )
  printf '%s\n' "$_kmix" | grep -q 'kitdemo .* FAIL' || {
    echo "verify --selftest: FAIL (a --kitself check N-A'd a MIXED-marker tree -- N-A must require BOTH kit"
    echo "  markers absent; one present means run. An && -> || regression would mis-N-A here)"; exit 1; }

  # -- C6 NEVER-OK leg: a check that DID NOT VERIFY must render N-A, never PASS ------------------------
  # The row's own acceptance criterion. Fixture-driven against the REAL check() (a counter-reset subshell,
  # mirroring the K3/--kitself legs), never a replica — a copy of the logic is the classic way a green
  # proves nothing about the shipped path. Zero additional full aggregates.
  _d6=$(mktemp -d) || { echo "verify --selftest: FAIL (no tmpdir for the C6 leg)"; exit 1; }
  printf '#!/bin/sh\necho "N/A: no data surface here — skipping"\nexit 0\n' > "$_d6/skipper.sh"
  _c6skip=$( controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
             check control c6skip sh "$_d6/skipper.sh" 2>&1 )
  rm -f "$_d6/skipper.sh"; rmdir "$_d6" 2>/dev/null || true
  printf '%s\n' "$_c6skip" | grep -q 'c6skip .* N-A' || {
    echo "verify --selftest: FAIL (a check that exited 0 saying it verified NOTHING did not render N-A —"
    echo "  a self-declared skip is being reported with the same token as an executed proof, which is"
    echo "  exactly how a green aggregate over-claims: it counts non-verification as verification)"; exit 1; }
  # LOAD-BEARING NEGATIVE (the anti-vacuity pair's second half): the skipped row must not satisfy the
  # control-PASS grep this file's own non-vacuity leg (above) relies on. Without this, a render that
  # printed BOTH tokens, or an N-A that still read as PASS to every downstream grep, would pass silently.
  if printf '%s\n' "$_c6skip" | grep -q '\[control\] .* PASS'; then
    echo "verify --selftest: FAIL (a self-skipped check still matched the control-PASS grep — the N-A token"
    echo "  must REPLACE PASS, not accompany it, or every consumer still reads the skip as a proof)"; exit 1
  fi
  # POSITIVE ANCHOR: an executed proof must still render PASS. Kills the opposite mutant — an
  # always-N-A classifier, which would make the whole aggregate honest-looking and worthless.
  _c6ran=$( controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
            check control c6ran sh -c 'echo "OK: really verified something"; exit 0' 2>&1 )
  printf '%s\n' "$_c6ran" | grep -q 'c6ran .* PASS' || {
    echo "verify --selftest: FAIL (an EXECUTED, passing check no longer renders PASS — an over-broad skip"
    echo "  classifier demotes real proofs to N-A, emptying the aggregate of every claim it makes)"; exit 1; }
  # ANCHOR leg: the skip idiom is matched at LINE START only. A check that is genuinely RUNNING prints
  # `N/A` mid-line as a matter of course — incept-first-run-green.sh renders `  [N/A]   <id>` per sub-gate
  # and a `… $NAS N/A, …` summary line while proving every gate. An unanchored classifier demotes those
  # real proofs; this fixture reproduces that exact shipped output shape and must still render PASS.
  _c6mid=$( controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
            check control c6midline sh -c 'echo "  [N/A]   db-postgres — stateless fixture"; echo "  summary: 12 GREEN, 1 N/A, 0 MISCONFIGURED-RED"; exit 0' 2>&1 )
  printf '%s\n' "$_c6mid" | grep -q 'c6midline .* PASS' || {
    echo "verify --selftest: FAIL (a RUNNING check that merely mentions N/A mid-line was demoted to N-A —"
    echo "  the classifier lost its line anchor and now under-claims real proofs, e.g. every"
    echo "  incept-first-run-green row, whose per-gate render legitimately prints '  [N/A]  <id>')"; exit 1; }
  # PARTIAL-SKIP leg: a check that skips SOME items and VERIFIES the rest has verified something, so it
  # is a PASS. This fixture reproduces the two rows that falsified the design's one-conjunct predicate
  # at build time (image-supply and runtime-floor iterate the ten profiles, skip the few with no
  # Dockerfile / no declared floor, prove the rest, and sign off `… OK (7 profile(s) … checked; others
  # N/A)`). A one-conjunct mutant renders this N-A and dies here — which is the point: N-A must mean
  # NOTHING was verified, or the count stops meaning anything.
  _c6part=$( controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
             check control c6partial sh -c 'echo "N/A (no Dockerfile): profiles/ml"; echo "OK profiles/go: supply chain present"; echo "container-supply-chain: OK (1 profile(s) checked; others N/A)"; exit 0' 2>&1 )
  printf '%s\n' "$_c6part" | grep -q 'c6partial .* PASS' || {
    echo "verify --selftest: FAIL (a check that skipped SOME items but PROVED others was rendered N-A —"
    echo "  it verified something, so N-A under-claims its own run. N-A is for a check that verified"
    echo "  NOTHING here; a partial skip beside a real verdict is a PASS)"; exit 1; }
  # AMENDED (VERIFY-SKIP-IDIOM-RESIDUAL, face ii) — the leg above pins "a partial skip beside a REAL
  # verdict stays PASS"; its unstated other half is that a ZERO-checked verdict is not a real one.
  # Same fixture, count 0: it must render N-A. Without the pair the ruling reads "any OK suppresses".
  _c6zero=$( controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
             check control c6zero sh -c 'echo "N/A (no Dockerfile): profiles/ml"; echo "container-supply-chain: OK (0 profile(s) with a Dockerfile checked; others N/A)"; exit 0' 2>&1 )
  printf '%s\n' "$_c6zero" | grep -q 'c6zero .* N-A' || {
    echo "verify --selftest: FAIL (a verdict line self-reporting ZERO checked items still suppressed the"
    echo "  skip — 0-checked is being rendered with the same token as N-checked, so a check that iterated"
    echo "  an empty set signs off as a proof. That is face (ii) of VERIFY-SKIP-IDIOM-RESIDUAL)"; exit 1; }
  # THE KEY'S LOAD-BEARING NEGATIVE: `(0 ` appears on 37 conformance/*.sh lines that are NOT zero-count
  # verdicts. A loose key demotes each, and inflates the `na` the CI floor reads. Measured shapes, PASS.
  _c6col=$( controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
            check control c6collide sh -c 'echo "N/A: one sub-surface skipped"; echo "OK: reconciled (0 foreign lines, 12 kept); In Review→PR (0 rows, empty); 0 SUPERSEDED-CITATION site(s) (0 occurrence(s))"; exit 0' 2>&1 )
  printf '%s\n' "$_c6col" | grep -q 'c6collide .* PASS' || {
    echo "verify --selftest: FAIL (a REAL verdict that merely contains '(0 ' was demoted to N-A — the"
    echo "  zero-count key lost its sentence shape and now under-claims every row reporting a zero of"
    echo "  something else, which also silently inflates the n/a the CI walks' floor is derived from)"; exit 1; }
  # THE SHIPPED IDIOMS, PINNED (canaries): a narrowed classifier reds here, not in the wild.
  for _idm in 'N/A: no data surface' 'N/A (no Dockerfile): profiles/ml' 'doc-markers: N/A — kit-self check (no marker)' 'SKIP: shellcheck not installed'; do
    _c6i=$( controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
            check control c6idiom sh -c "echo \"$_idm\"; exit 0" 2>&1 )
    printf '%s\n' "$_c6i" | grep -q 'c6idiom .* N-A' || {
      echo "verify --selftest: FAIL (the shipped skip idiom \"$_idm\" no longer renders N-A — the"
      echo "  classifier narrowed, and every check using that idiom now signs off as an executed proof)"; exit 1; }
  done
  # AND THE DISCLOSED MISS, PINNED AS A MISS (conjunct 1's `^` anchor). An INDENTED skip renders PASS.
  # The anchor is load-bearing (36 rc-0 rows mention n/a mid-line and every one had really run), so
  # this is a CEILING, not a bug to widen — pinned so a future loosening is a deliberate, reviewed act.
  # The cure is the authoring rule in conformance/README.md, "Writing a check that skips".
  _c6ind=$( controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0
            check control c6indent sh -c 'echo "   N/A: indented skip — outside the column-0 idiom"; exit 0' 2>&1 )
  printf '%s\n' "$_c6ind" | grep -q 'c6indent .* PASS' || {
    echo "verify --selftest: FAIL (an INDENTED skip was classified — the line anchor was loosened. That"
    echo "  anchor keeps 36 genuinely-running rows from being demoted; widening it here is a decision"
    echo "  for a design gate, not a regex tweak. Authoring rule: conformance/README.md)"; exit 1; }

  # ── MISCONFIGURED legs (VERIFY-RC2-USAGE-OVERLOAD) — a wrong INVOCATION is not a missing CREDENTIAL —
  # Both fixtures exit 2. Only the one answering with ITS OWN basename's usage text is a registry bug,
  # and it must block WITHOUT --require; the other is the protected UNVERIFIED lane (the 15 genuine
  # cannot-verify paths), which must keep failing ONLY under --require. Run in $_d6's parent-style tmp
  # so the row names a real `conformance/<name>.sh` path — the key is taken from the ROW, not from $out.
  _dm=$(mktemp -d) || { echo "verify --selftest: FAIL (no tmpdir for the MISCONFIGURED legs)"; exit 1; }
  mkdir -p "$_dm/conformance"
  printf '#!/bin/sh\necho "usage: mcchild.sh [--flag]" >&2\nexit 2\n' > "$_dm/conformance/mcchild.sh"
  printf '#!/bin/sh\necho "cannot verify: no gh credentials here" >&2\nexit 2\n' > "$_dm/conformance/cvchild.sh"
  # THE ANCHOR'S LOAD-BEARING NEGATIVE: a row that correctly invokes ITS child, whose child in turn
  # shells out to a helper it mis-calls, BUBBLES the helper's usage text up. The registry row is fine;
  # a bare `^usage:` key would red it. Measured shape: ci-gates.sh:457.
  printf '#!/bin/sh\necho "usage: helper.sh <arg>" >&2\necho "nestchild: could not verify" >&2\nexit 2\n' > "$_dm/conformance/nestchild.sh"
  _mcu=$( cd "$_dm" || exit 1; controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0; misconfigured=0; REQUIRE=0
          check control mcusage sh conformance/mcchild.sh 2>&1; result_sentence || true )
  _mccv=$( cd "$_dm" || exit 1; controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0; misconfigured=0; REQUIRE=0
           check control mccv sh conformance/cvchild.sh 2>&1; result_sentence || true )
  _mcnest=$( cd "$_dm" || exit 1; controls=0; docs=0; failed=0; unverified=0; ctrl_fail=0; nas=0; misconfigured=0; REQUIRE=0
             check control mcnest sh conformance/nestchild.sh 2>&1 )
  rm -rf "$_dm"
  printf '%s\n' "$_mcnest" | grep -q 'mcnest .* UNVERIFIED' || {
    echo "verify --selftest: FAIL (a NESTED child's usage text, bubbled up through a correctly-invoked"
    echo "  row, was blamed on the row — the key lost its child-basename anchor and now reds honest rows)"; exit 1; }
  printf '%s\n' "$_mcu" | grep -q 'mcusage .* MISCONFIGURED' || {
    echo "verify --selftest: FAIL (a child answering with its OWN usage text rendered as an ordinary"
    echo "  UNVERIFIED — a row this file INVOKED WRONG is indistinguishable from one that could not run)"; exit 1; }
  printf '%s\n' "$_mcu" | grep -q 'RESULT: FAIL (1 check row(s) MISCONFIGURED' || {
    echo "verify --selftest: FAIL (a MISCONFIGURED row did not FAIL the run WITHOUT --require — the"
    echo "  result_sentence branch must sit BEFORE the \$failed one, or a FAIL-always class renders"
    echo "  'advisory, non-blocking' and returns 0, which is a broken row wearing a green)"; exit 1; }
  printf '%s\n' "$_mccv" | grep -q 'mccv .* UNVERIFIED' || {
    echo "verify --selftest: FAIL (a GENUINE cannot-verify rc-2 was reclassified — the usage key must be"
    echo "  anchored to the child's own basename, or the 15 credential-blocked rows all turn into FAILs)"; exit 1; }
  printf '%s\n' "$_mccv" | grep -q 'RESULT: OK' || {
    echo "verify --selftest: FAIL (an UNVERIFIED row blocked WITHOUT --require — the rc-2 lane's"
    echo "  --require-only semantics are the regression pin here, and they moved)"; exit 1; }
  # ── THE ORDERING LEG, and it needs failed >= 1 to mean anything ────────────────────────────────
  # The $_mcu fixture leaves failed=0, so both orderings agree on it and a reorder mutant SURVIVES
  # (measured, by both review seats). The discriminating input is the co-occurrence: one MISCONFIGURED
  # row beside one failing doc-check, which a $failed-first ordering renders "advisory, non-blocking"
  # at rc 0. Real result_sentence, synthetic counters; both the wording AND the rc are asserted.
  _mcord=$( ctrl_fail=0; unverified=0; failed=1; misconfigured=1; REQUIRE=0; result_sentence || true )
  ( ctrl_fail=0; unverified=0; failed=1; misconfigured=1; REQUIRE=0; result_sentence >/dev/null ) && _mcordrc=0 || _mcordrc=$?
  printf '%s\n' "$_mcord" | grep -q 'RESULT: FAIL (1 check row(s) MISCONFIGURED' || {
    echo "verify --selftest: FAIL (a MISCONFIGURED row BESIDE a failing doc-check did not FAIL — the"
    echo "  \$failed branch ran first and rendered 'advisory, non-blocking'. A FAIL-always class must"
    echo "  not be downgradable by an unrelated advisory failure; the MISCONFIGURED branch has to sit"
    echo "  BEFORE the \$failed one, and only a failed>=1 fixture can tell the two orderings apart)"; exit 1; }
  [ "$_mcordrc" = 1 ] || {
    echo "verify --selftest: FAIL (a MISCONFIGURED row beside a failing doc-check returned rc"
    echo "  $_mcordrc, not 1 — the wording said FAIL while the exit status said pass, which is the"
    echo "  worst of both: a run that reads red and grades green)"; exit 1; }

  # ── ADOPTER-KIT-SELFTESTS-ON-CHANGE legs K1-K4, K6, K7 — the --kitselftest skip is diff-gated and fails SAFE ──
  # Design: docs/architecture/2026-10-01-adopter-kit-selftests-on-change-design.md §3/§4/§7. A row flagged
  # `--kitselftest` (position 3) is skipped (renders N-A) ONLY when `--changed <listing>` names a readable,
  # NON-EMPTY listing whose class (the gates' own `promotion-readiness.sh --class --changed`) is not
  # control-plane. Everything else — no --changed, empty/unreadable listing, classifier failure, control-plane
  # class — runs the full battery. Time is spent, never coverage (D-240903-3).
  #
  # INTERFACE THE MECHANISM MUST HONOUR (test seams, both read from the environment):
  #   VERIFY_SELFTEST_REGISTRY=<file>  a file of `check ...` lines that verify.sh `.`-sources IN PLACE OF its
  #                                    built-in registry (everything else — option parse, classify-once, notice,
  #                                    --summary-file, footer — runs for real). Unset/empty = built-in registry.
  #   VERIFY_CLASSIFIER=<script>       run as `sh "$VERIFY_CLASSIFIER" --class --changed <listing>` instead of
  #                                    `sh conformance/promotion-readiness.sh --class --changed <listing>`; the
  #                                    answer is the LAST stdout line, and a NON-ZERO exit means "unknown" =>
  #                                    full run (even if it printed a class first). Unset/empty = the real one.
  # These drive the REAL option path end to end (a throwaway registry of two stub rows), never a replica.
  # Without the mechanism each leg would run the WHOLE real battery (minutes) once per leg, so the first
  # assertion checks the seams exist outside this selftest and names every leg it is withholding.
  _ksd=$(mktemp -d) || { echo "verify --selftest: FAIL (no tmpdir for the --kitselftest legs)"; exit 1; }
  _ks_die() { rm -rf "$_ksd"; echo "verify --selftest: FAIL ($1)"; shift; for _ksl in "$@"; do echo "  $_ksl"; done; exit 1; }
  _ks_out_of_selftest=$(sed '/^if \[ "\${1:-}" = "--selftest" \]/,/^fi$/d' "$_SELF")
  for _kst in VERIFY_SELFTEST_REGISTRY VERIFY_CLASSIFIER -- --kitselftest --changed --summary-file; do
    case "$_kst" in --) continue ;; esac
    printf '%s\n' "$_ks_out_of_selftest" | grep -qe "$_kst" || _ks_die "K1-K4/K7: the mechanism is absent — '$_kst' does not appear outside --selftest" \
      "legs K1 (guard-only runs everything), K2 (app-only skips as N-A + notice with 'kit v'), K3 (no --changed /" \
      "empty / unreadable listing / classifier exit!=0 => full run), K4 (renamed-away control-plane path => full run)" \
      "and K7 (--summary-file notice only on a skip) cannot run: ADOPTER-KIT-SELFTESTS-ON-CHANGE task 2 is unbuilt"
  done
  # stub check (prints a real verdict, so is_self_skip never reclassifies it) + the two-row throwaway registry
  printf '#!/bin/sh\necho "OK: stub verified"\nexit 0\n' > "$_ksd/pass.sh"
  printf '%s\n' "check control kst-marked --kitselftest sh $_ksd/pass.sh" "check control kst-plain sh $_ksd/pass.sh" > "$_ksd/registry.sh"
  # classifier stubs: `ordinary` + exit 3 (a mechanism that ignores the exit status would SKIP — the leg must catch it)
  printf '#!/bin/sh\necho ordinary\nexit 3\n' > "$_ksd/failclass.sh"
  # _ks_run <classifier-or-empty> [verify.sh args...] -> the run's combined output (rc deliberately ignored:
  # the footer of a two-row registry is not under test). Classifier passed positionally, not as a prefix
  # assignment, so nothing persists after a function call on any shell.
  _ks_run() {
    _ksc=$1; shift
    # `env -u CI -u GITHUB_ACTIONS`: the seams are REFUSED under CI, and this selftest itself runs in CI.
    env -u CI -u GITHUB_ACTIONS VERIFY_SKIP_PREFLIGHT=1 VERIFY_SELFTEST_REGISTRY="$_ksd/registry.sh" VERIFY_CLASSIFIER="$_ksc" sh "$_SELF" "$@" 2>&1 || true
  }
  # _ks_row <output> <row> <token> : 0 when the row line carries that token (PASS or N-A)
  _ks_row() { printf '%s\n' "$1" | grep -Eq "\\[control\\] +$2 +$3\$"; }
  _ks_noticelines() { printf '%s\n' "$1" | grep -c '^kit selftests not re-run:' || true; }
  # the REAL classifier, run from the repo root (this script cd'd there) against an absolute listing path
  _ks_class() { sh conformance/promotion-readiness.sh --class --changed "$1" 2>/dev/null | tail -1; }
  # _ks_full <label> <output> : the marked row RAN (PASS), no N-A on it, no skip notice — a FULL battery
  _ks_full() {
    _ks_row "$2" kst-marked PASS || _ks_die "$1: the --kitselftest row did not RUN to PASS — a skip fired where the full battery was required" "output was:" "$2"
    if _ks_row "$2" kst-marked 'N-A'; then _ks_die "$1: the --kitselftest row rendered N-A where the full battery was required"; fi
    _ks_row "$2" kst-plain PASS || _ks_die "$1: the plain row did not run to PASS" "output was:" "$2"
    [ "$(_ks_noticelines "$2")" = 0 ] || _ks_die "$1: a skip notice was printed although nothing was skipped"
  }

  # K1 — THE SECURITY PROPERTY: a listing naming only the guard (.claude/hooks/guard.sh) is control-plane by the
  # REAL classifier, so every --kitselftest row RUNS. Two-part: the classifier answer is pinned first, so the
  # leg cannot go green by a classifier drifting to `ordinary` AND the mechanism skipping together.
  printf '.claude/hooks/guard.sh\n' > "$_ksd/k1.list"
  [ "$(_ks_class "$_ksd/k1.list")" = control-plane ] || _ks_die "K1: the REAL classifier no longer calls .claude/hooks/guard.sh control-plane — the skip's whole safety premise (design §6) is gone"
  _ks_k1=$(_ks_run "" --changed "$_ksd/k1.list" --summary-file "$_ksd/k1.summary")
  _ks_full K1 "$_ks_k1"

  # K2 — an ordinary listing skips the marked row as N-A, leaves the plain row running, prints ONE notice
  # naming the skipped row and carrying the kit version. The REAL classifier again (pinned not control-plane).
  printf 'src/app.ts\n' > "$_ksd/k2.list"
  _ks_c2=$(_ks_class "$_ksd/k2.list")
  case "$_ks_c2" in ordinary|sensitive) ;; *) _ks_die "K2: the REAL classifier answered '$_ks_c2' for src/app.ts, not ordinary/sensitive — the leg would be vacuous" ;; esac
  _ks_k2=$(_ks_run "" --changed "$_ksd/k2.list" --summary-file "$_ksd/k2.summary")
  _ks_row "$_ks_k2" kst-marked 'N-A' || _ks_die "K2: an app-only listing did not render the --kitselftest row N-A" "output was:" "$_ks_k2"
  if _ks_row "$_ks_k2" kst-marked PASS; then _ks_die "K2: the skipped row ALSO rendered PASS — N-A must replace PASS, never accompany it"; fi
  _ks_row "$_ks_k2" kst-plain PASS || _ks_die "K2: a plain row in the same registry stopped running when a --kitselftest row was skipped" "output was:" "$_ks_k2"
  [ "$(_ks_noticelines "$_ks_k2")" = 1 ] || _ks_die "K2: want exactly ONE 'kit selftests not re-run:' notice line, got $(_ks_noticelines "$_ks_k2")" "output was:" "$_ks_k2"
  printf '%s\n' "$_ks_k2" | grep '^kit selftests not re-run:' | grep -q 'kit v' || _ks_die "K2: the notice does not carry the kit version ('kit v<ver>')"
  printf '%s\n' "$_ks_k2" | grep '^kit selftests not re-run:' | grep -q 'kst-marked' || _ks_die "K2: the notice does not name the skipped row (kst-marked)"

  # K3 — EVERY unknown costs time, never coverage: four legs, each must run the marked row in full.
  _ks_k3a=$(_ks_run "")                                              # (a) no --changed at all (the hand run)
  _ks_full "K3a (no --changed)" "$_ks_k3a"
  : > "$_ksd/k3.empty"                                               # (b) an EMPTY listing
  _ks_k3b=$(_ks_run "" --changed "$_ksd/k3.empty")
  _ks_full "K3b (empty listing)" "$_ks_k3b"
  _ks_k3c=$(_ks_run "" --changed "$_ksd/no-such-listing")            # (c) a NONEXISTENT listing path
  _ks_full "K3c (nonexistent listing)" "$_ks_k3c"
  _ks_k3d=$(_ks_run "$_ksd/failclass.sh" --changed "$_ksd/k2.list")  # (d) classifier exits non-zero (after printing `ordinary`)
  _ks_full "K3d (classifier exits non-zero)" "$_ks_k3d"
  # and the stub seam is itself live: the same stub class WITHOUT a failing exit must be able to skip (else K3d is vacuous)
  printf '#!/bin/sh\necho ordinary\nexit 0\n' > "$_ksd/okclass.sh"
  _ks_k3e=$(_ks_run "$_ksd/okclass.sh" --changed "$_ksd/k2.list")
  _ks_row "$_ks_k3e" kst-marked 'N-A' || _ks_die "K3: VERIFY_CLASSIFIER is not honoured (a stub answering 'ordinary', exit 0 did not skip) — leg K3d would be vacuous" "output was:" "$_ks_k3e"

  # SEAM leg (security) — the two test seams must NEVER produce a verdict. A seam run whose rows all PASS must
  # still print the loud stderr banner, end with an UNVERIFIED RESULT, and exit 2; both seams are checked.
  # The registry seam is always on (the real registry would run for minutes); pass 1 adds nothing, pass 2 also
  # sets the classifier seam, whose banner must then be named too.
  printf '#!/bin/sh\necho control-plane\nexit 0\n' > "$_ksd/cpclass.sh"
  for _kss in VERIFY_SELFTEST_REGISTRY VERIFY_CLASSIFIER; do
    if [ "$_kss" = VERIFY_CLASSIFIER ]; then _ks_sv_cls="$_ksd/cpclass.sh"; else _ks_sv_cls=""; fi
    if _ks_sout=$(env -u CI -u GITHUB_ACTIONS VERIFY_SKIP_PREFLIGHT=1 VERIFY_SELFTEST_REGISTRY="$_ksd/registry.sh" VERIFY_CLASSIFIER="$_ks_sv_cls" sh "$_SELF" --changed "$_ksd/k1.list" 2>&1); then _ks_srcode=0; else _ks_srcode=$?; fi
    _ks_row "$_ks_sout" kst-marked PASS || _ks_die "SEAM($_kss): the all-PASS stub registry did not run (leg vacuous)" "output was:" "$_ks_sout"
    [ "$_ks_srcode" = 2 ] || _ks_die "SEAM($_kss): a test-seam run that would otherwise be all-PASS exited $_ks_srcode, not 2 — an env var could forge a green"
    printf '%s\n' "$_ks_sout" | grep -q "verify: TEST SEAM ACTIVE ($_kss) — this run is NOT a verdict" || _ks_die "SEAM($_kss): no loud 'TEST SEAM ACTIVE ($_kss)' banner"
    printf '%s\n' "$_ks_sout" | grep -q '^RESULT: UNVERIFIED (TEST SEAM ACTIVE' || _ks_die "SEAM($_kss): the summary does not say UNVERIFIED / TEST SEAM ACTIVE"
  done

  # SEAM-UNDER-CI leg — a seam under CI=true (or GITHUB_ACTIONS) is REFUSED: exit 2, the refusal, and NO row output.
  for _kci in CI GITHUB_ACTIONS; do
    if _ks_cout=$(env -u CI -u GITHUB_ACTIONS "$_kci=true" VERIFY_SKIP_PREFLIGHT=1 VERIFY_SELFTEST_REGISTRY="$_ksd/registry.sh" sh "$_SELF" --changed "$_ksd/k2.list" 2>&1); then _ks_crc=0; else _ks_crc=$?; fi
    [ "$_ks_crc" = 2 ] || _ks_die "SEAM-CI($_kci): a seam under $_kci=true exited $_ks_crc, not 2 (refused)"
    printf '%s\n' "$_ks_cout" | grep -q '^verify: REFUSED' || _ks_die "SEAM-CI($_kci): no 'verify: REFUSED' message" "output was:" "$_ks_cout"
    if _ks_row "$_ks_cout" kst-marked PASS || _ks_row "$_ks_cout" kst-marked 'N-A'; then _ks_die "SEAM-CI($_kci): rows ran although the seam must be refused before anything else"; fi
  done

  # K1b / K1c / floor legs — the LITERAL FORCED-FULL FLOOR (S1/R2/R5/R7). Each listing is paired with a classifier
  # stub answering `ordinary`, exit 0, so ONLY the floor can force the full run (the stub's skip power is proven by
  # K3e above). K1b: an unnamed .kit/ conf (agent-autonomy's on-disk leg). K1c: the guard itself, with the classifier
  # declassifying it (a PR that broke _cpp_match). Then a .shellcheckrc, a case-folded .GITHUB/ path, and a CRLF listing.
  _ks_floor() {  # <label> <listing-bytes-printf-format>
    printf "$2" > "$_ksd/floor.list"
    _ks_full "$1" "$(_ks_run "$_ksd/okclass.sh" --changed "$_ksd/floor.list")"
  }
  _ks_floor K1b '.kit/newthing.conf\n'
  _ks_floor K1c '.claude/hooks/guard-core.sh\n'
  _ks_floor 'floor(.shellcheckrc)' 'src/.shellcheckrc\n'
  _ks_floor 'floor(.GITHUB case-fold)' '.GITHUB/x\n'
  _ks_floor 'floor(CRLF listing)' 'src/app.ts\r\n'
  # S7: a non-ASCII byte forces the full battery (Unicode fold evasion: long-s U+017F = UTF-8 \305\277 aliasing `scripts/`).
  _ks_floor 'floor(S7 non-ASCII long-s)' '\305\277cripts/x.sh\n'
  # S6: a floor ERROR is a full run, not "no hit". There is no awk seam, so a stub `awk` that fails is put FIRST on PATH for the
  # child only; with the classifier stubbed `ordinary` a fail-open floor would skip, a fail-closed one runs the full battery.
  mkdir -p "$_ksd/failbin"; printf '#!/bin/sh\nexit 2\n' > "$_ksd/failbin/awk"; chmod +x "$_ksd/failbin/awk"
  printf 'src/app.ts\n' > "$_ksd/floor.list"
  _ks_oldpath=$PATH; PATH="$_ksd/failbin:$PATH"
  _ks_s6=$(_ks_run "$_ksd/okclass.sh" --changed "$_ksd/floor.list")
  PATH=$_ks_oldpath
  _ks_full "S6 (floor awk fails => full run)" "$_ks_s6"

  # K4 — a control-plane path RENAMED AWAY (git diff --no-renames lists old AND new): the old path alone
  # keeps the class control-plane, so the full battery runs. REAL classifier, two-line listing.
  printf 'scripts/old-name.sh\nsrc/new-name.ts\n' > "$_ksd/k4.list"
  [ "$(_ks_class "$_ksd/k4.list")" = control-plane ] || _ks_die "K4: the REAL classifier did not call a listing containing scripts/old-name.sh control-plane"
  _ks_k4=$(_ks_run "" --changed "$_ksd/k4.list")
  _ks_full "K4 (renamed-away control-plane path)" "$_ks_k4"

  # K7 — --summary-file receives the notice when rows were skipped (K2's run), and NOTHING when none were (K1's).
  [ -s "$_ksd/k2.summary" ] || _ks_die "K7: --summary-file stayed empty although a row was skipped — the notice never reached the run page"
  grep -q '^kit selftests not re-run:' "$_ksd/k2.summary" || _ks_die "K7: the --summary-file content is not the skip notice"
  grep -q 'kit v' "$_ksd/k2.summary" || _ks_die "K7: the --summary-file notice lacks the kit version"
  [ ! -s "$_ksd/k1.summary" ] || _ks_die "K7: --summary-file was written although NO row was skipped (guard-only listing)"

  # ROWTIMES (SWAS-372) — `--timing-file <file>` appends one `<name>\t<seconds>\t<verdict>` line per row; absent = no file,
  # and the printed rows are byte-identical either way. Stub registry (the two rows plus one that sleeps 2 s), so it costs
  # ~2 s. The sleeper is the non-vacuity row (design 2026-10-24-ci-shaping §7): it must record >= 2, so a constant-0
  # timer reds here; the line count must equal the rendered rows. Nothing after this leg reads registry.sh but K6 (a grep).
  printf '#!/bin/sh\nsleep 2\necho "OK: slept"\nexit 0\n' > "$_ksd/sleep.sh"
  printf '%s\n' "check control kst-marked --kitselftest sh $_ksd/pass.sh" "check control kst-plain sh $_ksd/pass.sh" "check control kst-sleep sh $_ksd/sleep.sh" > "$_ksd/registry.sh"
  _ks_rt="$_ksd/rowtimes.tsv"
  printf 'stale-row\t99\tPASS\n' > "$_ks_rt"   # a pre-existing file is REPLACED, never appended to
  _ks_rt_on=$(_ks_run "" --timing-file "$_ks_rt")
  if grep -q '^stale-row' "$_ks_rt"; then _ks_die "ROWTIMES: a pre-existing --timing-file was appended to, not replaced" "file was:" "$(cat "$_ks_rt")"; fi
  _ks_rt_rows=$(printf '%s\n' "$_ks_rt_on" | grep -Ec '^  \[control\] ')
  [ "$_ks_rt_rows" = 3 ] || _ks_die "ROWTIMES: the stub run rendered $_ks_rt_rows rows, not 3 (leg vacuous)" "output was:" "$_ks_rt_on"
  [ "$(grep -c '' "$_ks_rt" 2>/dev/null)" = "$_ks_rt_rows" ] || _ks_die "ROWTIMES: --timing-file did not get exactly one line per rendered row (want $_ks_rt_rows)" "file was:" "$(cat "$_ks_rt" 2>/dev/null)"
  _ks_rt_sl=$(awk -F '\t' '$1 == "kst-sleep" { print $2 }' "$_ks_rt")
  case "$_ks_rt_sl" in ''|*[!0-9]*) _ks_die "ROWTIMES: the kst-sleep line has no whole-seconds field" "file was:" "$(cat "$_ks_rt")" ;; esac
  [ "$_ks_rt_sl" -ge 2 ] || _ks_die "ROWTIMES: a row that sleeps 2 s recorded $_ks_rt_sl s (a constant-0 timer?)" "file was:" "$(cat "$_ks_rt")"
  grep -Eq "^kst-marked$(printf '\t')[0-9]+$(printf '\t')PASS\$" "$_ks_rt" || _ks_die "ROWTIMES: no 'kst-marked<TAB>secs<TAB>PASS' line" "file was:" "$(cat "$_ks_rt")"
  grep -Eq "^kst-plain$(printf '\t')[0-9]+$(printf '\t')PASS\$" "$_ks_rt" || _ks_die "ROWTIMES: no 'kst-plain<TAB>secs<TAB>PASS' line" "file was:" "$(cat "$_ks_rt")"
  rm -f "$_ks_rt"
  _ks_rt_off=$(_ks_run "")
  [ ! -e "$_ks_rt" ] || _ks_die "ROWTIMES: a file appeared although --timing-file was absent"
  [ "$_ks_rt_on" = "$_ks_rt_off" ] || _ks_die "ROWTIMES: the printed output differs with --timing-file present vs absent (must be byte-identical)"

  # VP (SWAS-376, C1(ii)) — the renderer-probe line the hermetic lane classifies. The shipped probe path is `out=$(... sh "$_SELF" ...) || true`
  # followed by ONE print of the agent-autonomy row's rendered verdict; here the SAME capture shape (the seam run, `_ks_run`) feeds the
  # SHIPPED function over stub registries, and the computed line is held in a variable, never printed (a printed stub line would make the
  # lane see two probe lines and read `not run/unknown`). The match is anchored and whole-name: a longer `agent-autonomy-alias` row, or a
  # [doc] row of the same name, must never be read as the battery.
  printf '#!/bin/sh\necho "N/A: agent-autonomy deferred to CI job guard-battery (stub)"\nexit 0\n' > "$_ksd/vp-na.sh"
  printf '#!/bin/sh\necho "FAIL: stub"\nexit 1\n' > "$_ksd/vp-fail.sh"
  printf '#!/bin/sh\necho "cannot verify: stub has no credentials"\nexit 2\n' > "$_ksd/vp-unv.sh"
  _vp_fn=_vs_probe_; _vp_fn="${_vp_fn}line"   # the name is assembled from parts so the VP-site scan below does not count its own text
  command -v "$_vp_fn" >/dev/null 2>&1 || _ks_die "VP: the probe-line function ($_vp_fn) is not defined — the renderer probe prints no agent-autonomy line, so the hermetic lane cannot tell a deferred battery from a full run"
  _vp_is() {  # <label> <want-verdict> <registry-row>... : the probe line over a stub registry run
    _vpl=$1; _vpw=$2; shift 2
    printf '%s\n' "$@" > "$_ksd/registry.sh"
    _vpo=$(_ks_run "")
    _vpg=$(_vs_probe_line "$_vpo")
    [ "$_vpg" = "renderer probe: agent-autonomy $_vpw" ] || _ks_die "VP($_vpl): the probe line read '$_vpg', want 'renderer probe: agent-autonomy $_vpw'" "output was:" "$_vpo"
  }
  _vp_is N-A N-A "check control agent-autonomy sh $_ksd/vp-na.sh"
  _vp_is PASS PASS "check control agent-autonomy sh $_ksd/pass.sh"
  _vp_is FAIL FAIL "check control agent-autonomy sh $_ksd/vp-fail.sh"
  _vp_is UNVERIFIED UNVERIFIED "check control agent-autonomy sh $_ksd/vp-unv.sh"
  _vp_is absent absent "check control kst-plain sh $_ksd/pass.sh"
  _vp_is doc-row absent "check doc agent-autonomy sh $_ksd/pass.sh"
  _vp_is alias-first PASS "check control agent-autonomy-alias sh $_ksd/vp-na.sh" "check control agent-autonomy sh $_ksd/pass.sh"
  _vp_is alias-only absent "check control agent-autonomy-alias sh $_ksd/vp-na.sh"
  # fix round: two anchored rows are not one battery (the lane's one-line rule), and a MISCONFIGURED row is a recognised verdict, not `absent`
  _vp_is two-rows absent "check control agent-autonomy sh $_ksd/vp-na.sh" "check control agent-autonomy sh $_ksd/pass.sh"
  _vp_is MISCONFIGURED MISCONFIGURED "check control agent-autonomy sh -c 'echo \"usage: vpmc.sh [x]\" >&2; exit 2' conformance/vpmc.sh"
  # VP-site: the shipped file prints the line ONCE — one bare call, directly after the probe's `out=$(... "$_SELF" ...) || true` line, on `$out`.
  # Every other use (these legs) is inside a command substitution.
  _vp_want="$_vp_fn \"\$out\""
  _vp_sites=$(awk -v fn="$_vp_fn" '
    /^[ \t]*#/ || /^[ \t]*$/ { next }
    index($0, fn "()") { prev = $0; next }
    index($0, "$(" fn) { prev = $0; next }
    index($0, fn) { n++; s = $0; p = prev }
    { prev = $0 }
    END { print n + 0; sub(/^ +/, "", s); print s; sub(/^ +/, "", p); print p }' "$_SELF")
  _vp_n=$(printf '%s\n' "$_vp_sites" | sed -n 1p); _vp_s=$(printf '%s\n' "$_vp_sites" | sed -n 2p); _vp_p=$(printf '%s\n' "$_vp_sites" | sed -n 3p)
  [ "$_vp_n" = 1 ] || _ks_die "VP-site: the file prints the renderer probe line $_vp_n time(s), want exactly 1 (a stub leg that prints its line, or a dropped print, breaks the lane's one-line rule)"
  [ "$_vp_s" = "$_vp_want" ] || _ks_die "VP-site: the one print is '$_vp_s', want '$_vp_want' (the probe's own output)"
  case "$_vp_p" in
    'out=$(VERIFY_SKIP_PREFLIGHT=1 '*'sh "$_SELF" 2>&1) || true') ;;
    *) _ks_die "VP-site: the print does not directly follow the renderer probe command (previous line: '$_vp_p')" ;;
  esac

  # K6 — LAST (it reds until the marker rows are applied, plan task 3): the REAL registry carries at least one
  # --kitselftest row, and agent-autonomy's is one of them. Read off this file's own `^check` rows, the same
  # single source the census reads; the fixtures above are printf strings, so they cannot satisfy these greps.
  _ks_nrows=$(grep -Ec '^check +[a-z]+ +[A-Za-z0-9_.-]+ +--kitselftest( |$)' "$_SELF") || true
  [ "${_ks_nrows:-0}" -ge 1 ] || _ks_die "K6: the registry has NO --kitselftest row — the marker set is empty, so --changed can skip nothing"
  grep -Eq '^check +control +agent-autonomy +--kitselftest( |$)' "$_SELF" || _ks_die "K6: the agent-autonomy row does not carry --kitselftest — the 532 s row the whole change exists to skip"
  rm -rf "$_ksd"

  # ── PRE-FLIGHT leg (B3) — a HEAD-less tree must fail FAST and name the TRUE cause ─────────────────
  # Behavioural: a real no-commit repo + this very script; asserts exit status, wording AND the clock.
  # The fixture is a whole git repo, so it is trap-cleaned (review R1): the earlier inline `rmdir` left
  # a .git behind on every run, and on an early `exit 1` it never ran at all.
  #
  # _vs_preflight_fired <text> : 0 when <text> contains the PRE-FLIGHT'S OWN refusal, ANCHORED to the
  # start of a line (SANITIZER-UNSET-RESTORES-EXPORTED, defect 2). The old probes grepped the bare
  # phrase `no commits yet`, which a FAILING CHILD'S SURFACED DIAGNOSTIC can carry — inception-done.sh
  # prints a leg header `--- (b9) tracked mode, unborn HEAD (no commits yet) ---` — so an unrelated
  # child failure was reported as "the pre-flight fired on a tree WITH history", a false attribution
  # that sends the reader to the wrong file. Both probes below go through this one matcher so the
  # negative and the positive can never drift apart.
  _vs_preflight_fired() {
    printf '%s\n' "$1" | grep -q '^verify: this repository has no commits yet'
  }

  # selftest_preflight_anchor: the anchor is load-bearing in BOTH directions — a child's prose that
  # merely MENTIONS the phrase must not match, and the pre-flight's real sentence must.
  selftest_preflight_anchor() {
    _pa_child='--- (b9) tracked mode, unborn HEAD (no commits yet) ---'
    _pa_real='verify: this repository has no commits yet — commit the incepted baseline first (git add -A && git commit -m "chore: incept baseline"), then re-run. Nothing below can be evaluated against an empty history.'
    if _vs_preflight_fired "$_pa_child"; then
      echo "verify --selftest: FAIL (the pre-flight probe matched a CHILD'S prose — '(no commits yet)' in a surfaced diagnostic would again be read as the pre-flight firing)"; exit 1
    fi
    if ! _vs_preflight_fired "$_pa_real"; then
      echo "verify --selftest: FAIL (the pre-flight probe no longer matches the pre-flight's OWN sentence — the leg below would be vacuous)"; exit 1
    fi
  }
  selftest_preflight_anchor

  _b3=$(mktemp -d) || { echo "verify --selftest: FAIL (no tmpdir for the pre-flight leg)"; exit 1; }
  trap 'rm -rf "$_b3"' EXIT
  mkdir -p "$_b3/conformance"; cp "$_SELF" "$_b3/conformance/verify.sh"
  ( cd "$_b3" && git init -q . 2>/dev/null ) || true; _b3st=$(date +%s)
  if _b3out=$(sh "$_b3/conformance/verify.sh" --require 2>&1); then _b3rc=0; else _b3rc=$?; fi
  _b3el=$(( $(date +%s) - _b3st ))
  [ "$_b3rc" = 0 ] && { echo "verify --selftest: FAIL (a repo with NO COMMITS exited 0 — an empty history cannot be evaluated, so that green is green-while-dark)"; exit 1; }
  _vs_preflight_fired "$_b3out" || { echo "verify --selftest: FAIL (a HEAD-less tree did not name the true cause — the adopter is sent to 'recopy the kit tree' when all that is missing is the first commit)"; exit 1; }
  [ "$_b3el" -gt 10 ] && { echo "verify --selftest: FAIL (a HEAD-less tree took ${_b3el}s to fail — the pre-flight must precede the battery)"; exit 1; }
  # Load-bearing the other way: it must NOT fire on a tree that HAS a commit (the aggregate above).
  _vs_preflight_fired "$out" && { echo "verify --selftest: FAIL (the pre-flight fired on a tree WITH history — it would block every real run)"; exit 1; } || true

  echo "verify --selftest: OK (renderer + honesty footer + non-vacuous control-PASS + INCOMPLETE-on-interrupt"
  echo "                       + K3: a FAILING check surfaces its diagnostic, a PASSING one stays one line"
  echo "                       + --kitself N-A/RUNS/mixed + VERIFY-SUMMARY: no 'docs present' over a doc-fail"
  echo "                       + C6: a self-declared skip renders N-A not PASS, an executed proof keeps PASS,"
  echo "                         a mid-line N/A mention and a PARTIAL skip beside a real verdict both stay"
  echo "                         PASS, and the Summary n/a count equals the N-A rows rendered)"
  echo "                       + ZERO-COUNT: a verdict reporting 0 checked items renders N-A, while a real"
  echo "                         verdict merely containing '(0 ' stays PASS; the three shipped skip idioms"
  echo "                         are pinned as canaries and the INDENTED-skip miss is pinned as a ceiling"
  echo "                       + MISCONFIGURED: a child answering with its OWN basename's usage text is a"
  echo "                         registry wiring bug and FAILS without --require, while a genuine"
  echo "                         cannot-verify rc 2 stays UNVERIFIED and blocks only under --require"
  echo "                       + KSOC K1-K4/K6/K7: --kitselftest rows skip (N-A + notice + --summary-file) only on a"
  echo "                         readable non-empty non-control-plane --changed listing; the guard, a renamed-away"
  echo "                         control-plane path, no/empty/unreadable listing and a failing classifier all run full"
  echo "                       + VP: the renderer probe prints ONE 'renderer probe: agent-autonomy <verdict>' line, read from the"
  echo "                         whole-name rendered row (a longer or [doc] row never counts), kept in variables everywhere else"
  echo "                       + PRE-FLIGHT: NO COMMITS fails in seconds naming the missing first"
  echo "                         commit, and stays silent on a tree that has history — both probes"
  echo "                         ANCHORED to the pre-flight's OWN sentence, so a failing child's prose"
  echo "                         mentioning '(no commits yet)' is never read as the pre-flight firing)"
  echo "verify --selftest: graded: $_vs_src"; exit 0
fi

# ── PRE-FLIGHT: an EMPTY HISTORY is not a conformance failure, it is a missing first commit ─────────
# MEASURED (B3, KIT-EVAL-2): an adopter's first act after `incept` is `verify.sh --require`; on a
# not-yet-committed tree it ran the whole battery (384s) then said `guard-wired FAIL: tracked
# hooks/pre-push missing from HEAD — recopy the kit tree`: both halves wrong (nothing is missing; there
# is no HEAD). Sits immediately before the battery, AFTER the --selftest exit (review R1), so the
# selftest stays runnable from a HEAD-less checkout. VERIFY_SKIP_PREFLIGHT is set ONLY by the
# selftest's own renderer probe, which needs a full aggregate rather than this refusal; the dedicated
# pre-flight leg deliberately does NOT set it, so the lane below is still proven end-to-end.
if [ -z "${VERIFY_SKIP_PREFLIGHT:-}" ] && git rev-parse --git-dir >/dev/null 2>&1 && ! git rev-parse --verify HEAD >/dev/null 2>&1; then
  echo "verify: this repository has no commits yet — commit the incepted baseline first (git add -A && git commit -m \"chore: incept baseline\"), then re-run. Nothing below can be evaluated against an empty history."
  exit 1
fi

# ── TEST SEAMS NEVER PRODUCE A VERDICT (ADOPTER-KIT-SELFTESTS-ON-CHANGE, security). The two env seams the
# selftest drives (a replacement registry; a stub classifier) would, in a real CI run, let whoever sets an
# environment variable forge a green (empty registry) or a skip (stub class). So a run that uses either
# says so loudly on stderr and ends UNVERIFIED (exit 2) whatever the rows did — see the footer.
SEAM_ACTIVE=""
for _ks_seam in VERIFY_SELFTEST_REGISTRY VERIFY_CLASSIFIER; do
  eval "_ks_sv=\${$_ks_seam:-}"
  [ -n "$_ks_sv" ] || continue
  echo "verify: TEST SEAM ACTIVE ($_ks_seam) — this run is NOT a verdict" >&2
  SEAM_ACTIVE="$SEAM_ACTIVE${SEAM_ACTIVE:+, }$_ks_seam"
done
readonly SEAM_ACTIVE   # a sourced seam registry cannot clear the taint (an assignment to it aborts the run)

# ── --kitselftest skip decision: classify ONCE, before any row runs, failing toward the FULL battery ───
# Skip mode needs ALL of: a --changed listing that is a readable NON-EMPTY file; a classifier that exits 0;
# and an answer of `ordinary` or `sensitive` (the last stdout line). Anything else — including `control-plane`,
# an empty answer, or a token this file does not know — leaves SKIP_KS=0 and every row runs.
# THE LITERAL FORCED-FULL FLOOR (security S1 / reviewer R2, R5, R7). The classifier below runs the PR's OWN checked-out
# guard-core (promotion-readiness.sh sources .claude/hooks/guard-core.sh), so a PR that breaks `_cpp_match` would
# declassify ITSELF and earn its own skip. This floor therefore must NEVER depend on the classifier, the guard, or any
# other file a PR can edit: it is a literal path test over the listing, run BEFORE the classifier is even invoked. Each
# path is case-folded (a case-insensitive checkout resolves `.GITHUB/` to `.github/`) and stripped of a leading `./`, and
# ANY of these forces the full battery: `.claude/` (anywhere), `conformance/`, `scripts/`, `hooks/`, `adapters/`,
# `profiles/`, `.github/`, `.kit/` (agent-autonomy's on-disk leg enumerates `git ls-files '.kit/*.conf'`), a basename of
# `.gitattributes` / `.shellcheckrc` / `shellcheckrc` (shellcheck honours a repo rc), `docs/roadmap-kit.md` (a kit-marker
# latch), or ANY byte outside printable ASCII (S7: a CR, a tab, or a non-ASCII byte — a CR would defeat every match above, and
# a Unicode fold such as the Kelvin sign in `.Kit` or the long-s in `ſcripts` can alias a control-plane directory on a
# case-insensitive runner).
# FAIL-CLOSED (S6): _ks_floor_hit returns 3 ONLY when it positively examined the whole listing and found no floor path. EVERY
# other status — a hit (0), a failed mktemp/tr/awk, a missing tool, a signal — is a FULL run. The stages write temp files and
# are checked one by one, because a pipeline's status under `set -e` without pipefail is only its LAST stage.
_ks_floor_hit() {  # <listing> -> 3 = examined, no floor path (skip allowed); anything else = FULL battery
  _kf_t=$(mktemp) || return 0
  if _kf_odd=$(LC_ALL=C tr -d ' -~\n' < "$1"); then :; else rm -f "$_kf_t"; return 0; fi
  [ -z "$_kf_odd" ] || { rm -f "$_kf_t"; return 0; }
  if LC_ALL=C tr 'A-Z' 'a-z' < "$1" > "$_kf_t"; then :; else rm -f "$_kf_t"; return 0; fi
  if LC_ALL=C awk '
    { p = $0; sub(/^\.\//, "", p); n = p; sub(/.*\//, "", n) }
    p ~ /^\.claude\// || p ~ /\/\.claude\// { f = 1 }
    p ~ /^(conformance|scripts|hooks|adapters|profiles|\.github|\.kit)\// { f = 1 }
    n == ".gitattributes" || n == ".shellcheckrc" || n == "shellcheckrc" || p == "docs/roadmap-kit.md" { f = 1 }
    END { exit(f ? 0 : 3) }' "$_kf_t"; then _kf_rc=0; else _kf_rc=$?; fi
  rm -f "$_kf_t"
  return "$_kf_rc"
}
if [ -n "$KS_CHANGED" ] && [ -f "$KS_CHANGED" ] && [ -r "$KS_CHANGED" ] && [ -s "$KS_CHANGED" ]; then
  if _ks_floor_hit "$KS_CHANGED"; then _ks_fr=0; else _ks_fr=$?; fi
  if [ "$_ks_fr" != 3 ]; then
    :   # forced full (a floor hit OR a floor error): the classifier is not even consulted
  elif _ks_cls=$(env -u KIT_ADAPTERS_DIR -u KIT_UNION_LIB sh "${VERIFY_CLASSIFIER:-conformance/promotion-readiness.sh}" --class --changed "$KS_CHANGED" 2>/dev/null); then
    # (the two KIT_* env seams of the classifier are scrubbed, as loop-state.sh does: an env var cannot move a path out of the set)
    _ks_cls=$(printf '%s\n' "$_ks_cls" | tail -n 1)
    case "$_ks_cls" in ordinary|sensitive) SKIP_KS=1 ;; esac
  fi
fi

# SWAS-393: a --merge validates its records and grades the battery row BEFORE it prints anything (a refused merge prints no rows).
if [ "$MERGE" = 1 ]; then
  _mg_rc=0; _mg_main || _mg_rc=$?
  if [ "$_mg_rc" != 0 ]; then exit "$_mg_rc"; fi
fi

echo "Conformance verification (honest aggregate)"
echo "-------------------------------------------"
# branch-protection's OFFLINE leg only (B4) — declaration-integrity, no gh, no network; see the
# SCOPE note above for why the LIVE leg stays out of this aggregate.
# --adopter (ADOPTER-GATES-INERT A3): the subject is the ADOPTER'S OWN declared required-checks file —
# it correctly N/As on a pre-inception export (nothing declared yet) and ARMS once the adopter authors
# their own declaration; --kitself would silence a real adopter gate forever.
# TEST SEAM (selftest only; the run is forced UNVERIFIED in the footer): a replacement registry is sourced
# INSTEAD of the built-in rows below. The wrapper is deliberately UNINDENTED so every `check` row below still
# begins in column 0 (the census awk, the `Scripts:` reconciliation and the K6 leg all read them as text).
if [ -n "${VERIFY_SELFTEST_REGISTRY:-}" ]; then
  # shellcheck source=/dev/null  # a test-only seam resolved at runtime
  . "$VERIFY_SELFTEST_REGISTRY"
elif [ "$MERGE" = 1 ]; then
  # SWAS-393: the rows of the shard records, rebuilt in registry order (the battery row graded by the join), in place of the registry.
  cat "$MERGE_FINAL"; rm -rf "$(dirname "$MERGE_FINAL")"
else
check control branch-protection-declared    --adopter sh conformance/branch-protection.sh --declared-only
check control branch-protection-selftest    sh conformance/branch-protection.sh --selftest
# --kitselftest (design §3 (a)+(b)): inputs are the guard (.claude/hooks/*), the named .kit/*.conf and conformance/ scripts it
# drives, plus its own temp fixtures. Residual (record in review): its `git ls-files '.kit/*.conf'` leg also sees an UNNAMED
# .kit/<x>.conf an adopter could add (not a control-plane path): closed by the .kit/ rule (any listed .kit/ path forces a full run).
check control agent-autonomy   --kitselftest sh conformance/agent-autonomy.sh
check control agent-boundary   sh conformance/agent-boundary.sh --selftest
check control hardlink-integrity          sh conformance/hardlink-integrity.sh
check control hardlink-integrity-selftest sh conformance/hardlink-integrity.sh --selftest
check control harness-adapter  sh conformance/harness-adapter.sh adapters/claude-code
check control harness-generic  sh conformance/harness-adapter.sh adapters/generic
check control harness-adapter-selftest sh conformance/harness-adapter.sh --selftest
# agents-brief carries the ENTRY-CONTRACT lock (§1 byte-identical in every adapter's declared
# contextFile). It ran only in CI and via harness-adapter's floor_holds, so `non-vacuity.sh --only
# agents-brief.sh` matched NO targeted check — the sweep selects from `^check control` rows here, and
# the lock that makes the whole entry-contract slice real therefore had ZERO mutation coverage.
# Registering it is what gives it teeth locally AND in the CI sweep.
check control agents-brief             sh conformance/agents-brief.sh
check control agents-brief-selftest     sh conformance/agents-brief.sh --selftest
# doc-budget carried the SAME zero-mutation-coverage gap: it runs in CI, it was never a `check control`
# row here, and the sweep selects only from these rows — so `non-vacuity.sh --only doc-budget.sh`
# matched no targeted check. The ratchet that keeps the core governing docs from re-bloating had no
# proof it can still fail. (It is one of a set of workflow-invoked conformance checks that are not
# registered here. THE RECONCILIATION-OF-RECORD IS THE RUN'S OWN `Scripts:` LINE, printed beside the
# Summary at the foot of this file (PR 10): rows · unique scripts · files on disk · files no row
# invokes, computed at runtime. "Three methods, three answers" was true because the three methods count
# three DIFFERENT populations; that line names all of them. Which unregistered files SHOULD be
# registered stays CONFORMANCE-MUTATION-COVERAGE-GAP's question — the count is no longer part of it.)
#
# --kitself IS LOAD-BEARING, and it is a CATEGORY distinction, not a convenience. doc-budget budgets
# CLAUDE.md / DEVELOPMENT-PROCESS.md / DEVELOPMENT-STANDARDS.md — the KIT's own core-3 governing docs,
# and its whole purpose is an anti-re-bloat ratchet on kit-authored prose. On an INCEPTED tree
# `CLAUDE.md` is the project CHARTER: a different document that merely shares a filename, whose length
# is the adopter's business. Registering the rows unqualified made this slice's own +25-line entry
# contract in templates/PROJECT-CLAUDE-TEMPLATE.md red a BRAND-NEW project's first
# `verify.sh --require` (MEASURED: stamped charter 143 lines vs a budget of 135, rc 1) — a kit ratchet
# charged to adopter content. Raising the number would only postpone the same collision.
check control doc-budget               --kitself sh conformance/doc-budget.sh
check control doc-budget-selftest       --kitself sh conformance/doc-budget.sh --selftest
# conformance-mass-budget (CUT-A7) is doc-budget's sibling one level up: doc-budget ratchets the core
# governing PROSE, this ratchets the kit's own conformance MASS (lines + files + the `^check control `
# census right here in this file). --kitself IS LOAD-BEARING on BOTH rows, and non-negotiably so: it
# is the identical exposure doc-budget MEASURED above — a kit ratchet charged to adopter content. An
# adopter's conformance/ holds THEIR checks; holding them to the kit's line count would red a
# brand-new tree's first `verify.sh --require` for growth that is none of the kit's business. The
# check ALSO stands down in-script on the same OR-of-markers detector (arming evaluated BEFORE any
# enumeration, so an adopter never reaches its fail-closed refusal), so neither surface alone is the
# switch. ⚠️ These two rows are themselves counted by the census this check budgets — adding them cost
# the founding measurement, which is why GENESIS was taken on the POST-diff tree.
check control conformance-mass-budget          --kitself sh conformance/conformance-mass-budget.sh
check control conformance-mass-budget-selftest --kitself sh conformance/conformance-mass-budget.sh --selftest
# loop-state is the universal refusal floor (KIT-ADHERENCE-ENFORCEMENT B1). ONLY the --selftest is
# registered here: this file accepts BASE-INDEPENDENT checks, and the REAL gate needs the PR head SHA
# (`--head <sha>`), which does not exist on an arbitrary tree. The real gate runs as a PR-context job
# in ci.yml — the same split ceremony-binding already uses (selftest backstop vs diff-relative gate).
# Registering the selftest is also what puts loop-state inside `non-vacuity.sh`'s swept set, which
# selects from these `^check control` rows: without this row the gate would ship a green nobody has
# proven can go red — exactly the CONFORMANCE-MUTATION-COVERAGE-GAP this row avoids inheriting.
# --kitself IS LOAD-BEARING here, exactly as it is for doc-budget above. THE LIVE REASON: this
# selftest's map-completeness anchor grades the KIT's own roster, so an adopter who adds a single
# project skill reds it — measured. On an adopter tree that roster is the adopter's business, not a
# kit assertion.
# ⚠️ A SECOND REASON WAS ONCE GIVEN HERE AND IS NOW STALE — that BACKLOG.md being export-ignore'd
# inverted the row leg's negative. The same commit made the row legs hermetic (they run against a
# fixture board), so the selftest now PASSES with BACKLOG.md removed; re-measured at ce49514. It is
# recorded rather than deleted so nobody later "fixes" the hermetic fixtures and drops this flag on
# the strength of a reason that no longer applies. The reason above carries the flag alone.
# A --kitself row is still a `^check control` row, so non-vacuity coverage survives (verified:
# `non-vacuity.sh --only loop-state.sh` reports KILLED).
check control loop-state-selftest      --kitself sh conformance/loop-state.sh --selftest
# pre-push (B1) runs loop-state.sh --head on the pushed HEAD as a local speed bump — the same
# script path, at the same SHA CI grades (design Δ1: head-of-ref, identical to the PR head).
# Registering only the SELFTEST here (not a live invocation) rides the same split as loop-state
# itself: the real gate needs a pushed SHA that does not exist on an arbitrary tree. --kitself
# because the hook's selftest (like loop-state's) grades against this repo's own throwaway
# fixtures and self-invocation path, the same category as the doc-budget / loop-state rows above.
# ⚠️ This row's own script path (hooks/pre-push, not conformance/*.sh) is NOT a
# `conformance/[a-z0-9-]+\.sh` token, so non-vacuity.sh's target_set CANNOT select it — measured
# (see docs/architecture/2026-08-05-b1-pre-push-entry-declaration-design.md §7, amended with this
# measurement). The hook's mutation-sweepable region (decl_check_ref, above its own --selftest
# marker) is proven by hand-run cases inside that file's own selftest, not by this sweep. Same
# caveat as the design's own §7: the predicate's class leg still reads the ambient worktree at
# grading time, not a pristine checkout of the graded SHA — "identical SHA" is a claim about
# WHICH commit is graded, not a guarantee the working tree matches it byte-for-byte.
check control pre-push-selftest        --kitself sh hooks/pre-push --selftest
# dial-state (DIAL-DELIVERY Δ-A) — the presence+values lock on .kit/dials.conf, the repo-carried
# state the two rows above actually read. The LIVE check is registered (not just a selftest): it is
# base-independent and needs no SHA, and it is the row that would red a COMMITTED disarm — the whole
# point of moving the dial out of an env var. --kitself IS LOAD-BEARING and is the same category as
# the three rows above: `.kit/dials.conf` is export-ignored, so an adopter tree legitimately has
# none and reads observe by design; holding an adopter to the kit's flip would be a kit ratchet
# charged to adopter content (the doc-budget lesson). The check ALSO scope-guards itself in-script
# on the same un-spoofable marker set, so neither surface alone is the switch. Registering it here
# is additionally what enrols the file in non-vacuity.sh's sweep (which selects from these
# `^check control` rows), and its own --selftest runs as a dedicated ci.yml step (H3 pair pointer:
# conformance-selftests, "dial-state self-test").
check control dial-state               --kitself sh conformance/dial-state.sh
# permission-surface-audit (C3 PERMISSION-SURFACE-DELIVERY-AUDIT) — reconciles the shipped
# .claude/settings.json allow/ask/deny surface + the PreToolUse hook against the checked enumeration
# conformance/sanctioned-commands.tsv, and resolves every ruling-only/deliberately-absent ruling-ref
# against DECISIONS.md. The LIVE check is registered (base-INDEPENDENT — pure tracked-text compare, no
# SHA/base needed) and is the row that reds a committed shipped-vs-ruling disagreement. --kitself IS
# LOAD-BEARING and the same category as the four rows above: the enumeration is export-ignored, so an
# adopter tree legitimately carries none and reads N/A by design (adopters populate their own). The
# check ALSO scope-guards itself in-script on the same un-spoofable marker set, so neither surface
# alone is the switch. Registering it here enrols the file in non-vacuity.sh's sweep (which selects
# from these `^check control` rows); its own --selftest runs as a dedicated ci.yml step
# (conformance-selftests, "permission-surface-audit self-test").
check control permission-surface-audit --kitself sh conformance/permission-surface-audit.sh
# tool-coverage (C5 GUARD-TOOL-COVERAGE-GREP-GLOB) — the content-tool FAMILY LOCK. Keys on C3's
# sanctioned-commands.tsv guard-backstop column (corrected in C5): every tool-name allow/ask row must
# carry a recorded backstop (full/residual-family/declared-uncovered), never a silent `none`, and each
# claimed backstop must have a matching guard.sh case arm. Detection-not-enumeration: a newly-added
# content tool (forced into the TSV by C3's reconcile lock) reds this unless a human wires/declares it.
# The LIVE check is registered (base-INDEPENDENT — pure tracked-text compare of the TSV against
# guard.sh, no SHA/base needed). --kitself IS LOAD-BEARING and the same category as the rows above: the
# enumeration is export-ignored, so an adopter tree carries none and reads N/A (adopters populate their
# own). The check ALSO scope-guards itself in-script on the same un-spoofable marker set, so neither
# surface alone is the switch. Registering it here enrols the file in non-vacuity.sh's sweep (which
# selects from these `^check control` rows); its own --selftest runs as a dedicated ci.yml step
# (conformance-selftests, "tool-coverage self-test").
check control tool-coverage            --kitself sh conformance/tool-coverage.sh
# adopter-told (C7 ADOPTER-TOLD-LOOP-GATES-ARE-ENFORCED) — the shipped prose must not tell an adopter
# a gate is ENFORCED when nothing in what they receive enforces it. It builds a real adopter export
# (~0.4s), classifies every conformance check as hard-reachable / dial-reachable (observe-dialed
# profiles/adopter-gates.yml) / unreachable, and reds a claim-verb line naming a check the adopter
# cannot reach — unless the line discloses the dial or is narrowed to the kit's own CI and true there.
# STILL NO --kitself IN THE FIRST-INVOCATION SENSE, and this is the distinction from the four rows
# above: this check ARMS ITSELF in-script on the same un-spoofable kit-marker pair, so a registry-level
# skip would be redundant on the adopter side — its N/A is a self-declared skip (C6 renders it N-A), not
# a registry-level suppression, and on an ARMED tree an export or parse failure is a FAIL rather than an
# N/A. --kitself (ADOPTER-GATES-INERT A3): the SUBJECT graded is the KIT'S OWN shipped prose (does the
# kit's own documentation overclaim what an adopter's export enforces) — a genuine kit fact, never the
# adopter's artifact, so the registry flag is added purely for the census's benefit; the self-arming
# logic above is unchanged and is what actually governs behaviour. Registering it here also enrols it in
# non-vacuity.sh's sweep (which selects from these `^check control` rows); its own --selftest runs as a
# dedicated ci.yml step (conformance-selftests, "adopter-told self-test") and the LIVE check runs in
# `docs-links` — a required, no-`if:` job that SURVIVES the docs_only skip, unlike
# cf-verify-enforced/cf-export, which are disarmed on exactly the `.md` PRs a prose-claim check governs
# (measured, C7 design §2.7).
check control adopter-told             --kitself sh conformance/adopter-told.sh
# TOMBSTONE (2026-08-19, CUT-PHASE-GATE-PARK, `D-240819-3` amending `D-240804-1`): two `check control`
# rows for the edit-time phase gate stood here. The gate was PARKED to the history branch
# `history/phase-gate-s1a-i` — it had no wired caller, so it denied nothing, and its registration here
# was buying one composite mutant per sweep run over the single largest file in the corpus. Do not
# re-add a row without re-adding the script; the rows and the file move together (see
# `docs/kit-internals/retiring-conventions.md`, the tombstone there, for the history ref and what
# re-wiring would take).
# --kitself (ADOPTER-GATES-INERT A3): both rows drive a REAL `incept` run as their OWN fixture (to
# prove the KIT'S OWN incept mechanism discloses the harness ceiling correctly) — a kit fact about the
# kit's tooling, never a specific adopter's already-incepted tree.
check control harness-ceiling          --kitself sh conformance/harness-ceiling-disclosed.sh
check control harness-ceiling-selftest  --kitself sh conformance/harness-ceiling-disclosed.sh --selftest
# --kitself (ADOPTER-GATES-INERT A3): proves the KIT'S OWN incept mechanism stamps a non-colliding
# pipeline-origin marker — a kit fact about incept's own emission, never a specific adopter's tree.
check control pipeline-origin          --kitself sh conformance/pipeline-origin.sh
check control pipeline-origin-selftest  --kitself sh conformance/pipeline-origin.sh --selftest
# CONFORMANCE-DOC-FAMILIES-MERGE (D-240828-4): these four rows used to name two single-purpose
# scripts. Both folded into the table-driven conformance/doc-markers.sh (subject:
# conformance/doc-markers.tsv) with their marker labels preserved verbatim — the mutants those
# selftests killed are now GENERATED per table row, one per marker, and still die by label. The rows
# stay FOUR AND DISTINCT on purpose: `^check control ` is both the census the mass budget ratchets
# and the target set non-vacuity.sh sweeps, so collapsing them would silently drop two rows of
# mutation coverage while the budget read it as a saving.
check control validation-terminal-state           sh conformance/doc-markers.sh validation-terminal-state
check control validation-terminal-state-selftest   sh conformance/doc-markers.sh validation-terminal-state --selftest
check control feedback-link-lifecycle              sh conformance/doc-markers.sh feedback-link-lifecycle
check control feedback-link-lifecycle-selftest      sh conformance/doc-markers.sh feedback-link-lifecycle --selftest
check control named-adapters-selftest  sh conformance/named-adapters.sh --selftest
check control ci-gates         --kitself sh conformance/ci-gates.sh profiles/typescript-node/ci.yml --expect-seams
# B7 (D-240805-2 executed) — the NON-kitself leg: THIS tree's OWN installed pipeline(s) judged
# against the 8 gate ids minus the tree's validated na dispositions
# (conformance/gate-dispositions.txt; absent = all 8 — the adopter default, the kit's file being
# export-ignored). Deliberately NOT --kitself: this is the row adopters run — an adopter deleting
# gate-sbom from their emitted pipeline goes RED on their own tree (the Phase-B spine AC). Raw
# pre-incept export disposes N/A; an unmarked FOREIGN (brownfield) pipeline disposes
# ADOPTER-OWNED N/A-with-remedy, never FAIL (the verify-enforced-wired provenance axis, copied).
# On the kit tree it binds the kit's own meta-CI to the D-240805-2 3-apply set.
# --adopter, NOT --kitself (ADOPTER-GATES-INERT A3 STOP-AND-FLAG): the census-reconciliation input to
# this build listed ci-gates-own under the --kitself group, but the paragraph immediately above and the
# script's own "raw pre-incept export: no pipeline and no incepted/kit marker" N/A message (ci-gates.sh)
# say the opposite — the subject is THE TREE'S OWN INSTALLED PIPELINE, it correctly N/As pre-inception
# (no pipeline exists yet) and ARMS the moment incept emits one, exactly the pattern the other 8
# --adopter rows share. `--kitself` here would have PERMANENTLY SILENCED the exact adopter-facing
# enforcement the paragraph above says this row exists for. Re-classified during T4's mandatory re-triage
# pass; flagged in the build's self-verify report for reviewer attention.
check control ci-gates-own     --adopter sh conformance/ci-gates.sh --own-tree
check control ci-gates-selftest sh conformance/ci-gates.sh --selftest
# TIER0-LOCKS-OWED (b) — the aggregator needs:/classifier drift-lock, live on the KIT's OWN
# .github/workflows/ci.yml + conformance/ci-classify-changes.sh (the shape this lock judges — a
# many-shard `conformance` aggregator with a hand-maintained PG_NEEDED mirror — is this repo's own
# meta-CI, not an adopter's emitted single-pipeline profile). --kitself: an adopter export carries
# neither this ci.yml's aggregator shape nor this exact classifier constant.
check control ci-gates-aggregator-lock --kitself sh conformance/ci-gates.sh --aggregator-lock
# A8/T1-09 — the kit's own ci.yml must carry a real secret-scan gate. The LIVE check + its --selftest are
# gitleaks-FREE (pure grep over the workflow + runtime fixtures), so both are portable and mutation-swept.
# The gitleaks-DEPENDENT planted-secret liveness proof lives under --scan-selftest and runs ONLY in the
# dedicated `secret-scan` CI job (which downloads the pinned binary) — registering it here would UNVERIFIED-
# red the offline aggregate on any host without gitleaks. See conformance/secret-scan-wired.sh's header.
# --kitself on the LIVE check: it asserts THE KIT'S OWN .github/workflows/ci.yml carries the secret-scan
# gate — that file is export-ignored, so on an adopter/export tree it is absent and the check must N/A,
# not FAIL (adopters get their own secret-scan via their profile pipeline + ci-gates.sh). Without this
# it reds green-on-clone: the adopter's first push would be RED (measured on PR-486 CI). The --selftest
# is tree-independent (runtime fixtures) so it stays portable and mutation-swept.
check control secret-scan-wired --kitself sh conformance/secret-scan-wired.sh
check control secret-scan-wired-selftest  sh conformance/secret-scan-wired.sh --selftest
check control dep-scan-visibility           sh conformance/dep-scan-visibility.sh
check control dep-scan-visibility-selftest   sh conformance/dep-scan-visibility.sh --selftest
check control image-supply     sh conformance/container-supply-chain.sh
# --kitselftest (design §3 (a)): lints only scripts/*.sh, conformance/*.sh, profiles/*/scaffold/scripts/*.sh, scripts/kit-guard and
# hooks/pre-push - every one a control-plane path (its --selftest uses temp fixtures only).
check control shellcheck       --kitselftest sh conformance/shellcheck.sh
check control "license-check(selftest)" sh scripts/license-check.sh --selftest
check control guard-wired      sh conformance/guard-wired.sh
check control check-links      sh conformance/check-links.sh
# citation-live (C9 CITATION-LIVE, ruling D-240804-2) — the COMPLEMENT of the row above, and the pair
# is the point: check-links validates Markdown LINKS and deliberately SKIPS code spans, where ~85% of
# the kit's `path.ext:LINE` citations live (its own header discloses that ceiling). This row grades
# exactly those, over the LIVING Markdown corpus only — the dated record (designs, plans, CHANGELOG,
# the meta-control log) is exempt-and-REPORTED, because a dated document's citations were correct
# against the tree of its own date. STILL SELF-ARMING, for adopter-told's reason: the check ARMS ITSELF
# in-script on the same un-spoofable kit-marker pair, so on an armed tree a failed corpus enumeration
# or a zero-citation domain is a FAIL rather than an N/A, while an adopter tree with no citations
# self-declares N/A (C6 renders it N-A). --kitself (ADOPTER-GATES-INERT A3): the SUBJECT is "the kit's
# LIVING Markdown"/"the kit's governance record" (its own header) — a genuine kit fact; the flag is
# added purely for the census, the self-arming logic above still governs actual behaviour. Registering
# it here also enrols the file in non-vacuity.sh's sweep (which selects from these `^check control`
# rows); its own --selftest runs as a dedicated ci.yml step (conformance-selftests, "citation-live
# self-test") and the LIVE check runs in `docs-links` — the same required, no-`if:` job that survives
# the docs_only skip, chosen for the same reason: a citation-decay check governs exactly the `.md`-only
# PRs that disarm cf-verify-enforced.
check control citation-live    --kitself sh conformance/citation-live.sh
# citation-history (the sixth-dial slice, route (b), ruling D-240815-2d) — the row above grades whether
# a cited line still EXISTS; this one grades the WRITING SHAPE that carries a dead value forward. The
# two are deliberately separate files: citation-live is mode-pure and its logic is frozen by this
# slice, so the new grammar lands beside it rather than inside its mutation region. The LIVE row is
# registered (base-INDEPENDENT — a `git ls-files` enumeration and one awk pass, no SHA, no merge-base)
# and it is sub-second. STILL SELF-ARMING, for citation-live's exact reason: the check ARMS ITSELF
# in-script on the same un-spoofable kit-marker pair, so on an armed tree an unreadable or unenumerable
# corpus is a FAIL rather than an N/A, while an adopter tree self-declares the line-anchored N/A that C6
# renders N-A (de-lining is the kit's own writing convention; the adopter face is the doctrine, not this
# gate). --kitself (ADOPTER-GATES-INERT A3): the subject is the kit's own writing convention over its
# own docs corpus, purely for the census; the self-arming logic still governs behaviour. Registering it
# here also enrols the file in non-vacuity.sh's sweep (which selects from these `^check control` rows);
# its own --selftest runs as a dedicated ci.yml step (conformance-selftests, "citation-history
# self-test") and the LIVE check runs in `docs-links` — the same required, no-`if:` job, chosen for the
# same reason: a lint over `.md` prose governs exactly the `.md`-only PRs that disarm cf-verify-enforced.
check control citation-history --kitself sh conformance/citation-history.sh
# decision-id-live (DANGLING-DECISION-ID-CITES) — the citation-live family ONE LEVEL UP: citation-live
# asks "does the cited LINE still exist"; this row asks "does the cited RULING still exist". A `D-*` id
# is the kit's strongest form of authority and was unforgeable only by convention — a living doc could
# carry an authority-shaped token to a ruling never recorded and nothing would red it. This grades every
# `D-YYMMDD-N` cited in a LIVING `.md` for membership in DECISIONS.md's `**`D-...`` headers (folding a
# dotted `.N` sub-id to its parent, the sanctioned-commands.tsv:54 precedent); the dated record is
# exempt-and-REPORTED (the C9 dated principle) and a `.sh` fixture id is out of the `.md`-only domain by
# construction. HONEST CEILING: it proves the parent ruling EXISTS, never that a sub-item number or the
# ruling's SUBSTANCE is real (Q3). KIT-SELF, and now --kitself (ADOPTER-GATES-INERT A3): the ids are the
# kit's own governance vocabulary, so the check ARMS ITSELF on the same un-spoofable kit-marker pair —
# on an armed tree a missing/empty DECISIONS.md or a zero-citation domain is a FAIL, while an adopter
# tree self-declares the line-anchored N/A that C6 renders N-A; the registry flag is added purely for
# the census, the self-arming logic still governs behaviour. Registering it here also enrols the file in
# non-vacuity.sh's sweep (which selects from these `^check control` rows); its own --selftest runs as a
# dedicated ci.yml step (conformance-selftests, "decision-id-live self-test") and the LIVE check runs in
# `docs-links` — the same required, no-`if:` job, chosen because a ruling-citation check governs exactly
# the `.md`-only PRs that disarm cf-verify-enforced.
check control decision-id-live --kitself sh conformance/decision-id-live.sh
# roadmap-current (C10 ROADMAP-STALE-RECONCILE) — the SIBLING of the row above and placed here for the
# same reason: both grade whether a LIVING document still tells the truth about the tree it describes.
# citation-live asks "does the line this doc cites still exist"; this row asks "does the roadmap still
# call SHIPPED work pending". Measured at the C10 probe, seven ROADMAP.md items carried a pending glyph
# while BACKLOG.md's `## Done` carried a row for each. The reconciliation was done by hand in that
# slice; THIS ROW IS THE RATCHET that keeps the count at zero. STILL NO --kitself, for citation-live's
# exact reason: the check ARMS ITSELF in-script on the same un-spoofable kit-marker pair, so on an armed
# tree a dead ROADMAP.md, an absent `## Done` section or a zero-marker stub is a FAIL rather than an N/A.
# --adopter (ADOPTER-GATES-INERT A3, correcting an earlier --kitself estimate): the check's own header
# says "An adopter who KEEPS a ROADMAP.md and a BACKLOG.md with a Done section is graded normally" — the
# subject is the ADOPTER'S OWN roadmap<->board coherence, self-arming and borderline, but adopter-subject
# nonetheless. `--kitself` would have permanently silenced a real gate the moment an adopter authors
# either file; `--adopter` keeps it census-visible without that lie. Registering it here also enrols the
# file in non-vacuity.sh's sweep (which selects from these `^check control` rows); its own --selftest
# runs as a dedicated ci.yml step (conformance-selftests, "roadmap-current self-test") and the LIVE check
# runs in `docs-links` — the same required, no-`if:` job, chosen because a roadmap-honesty check governs
# exactly the `.md`-only PRs that disarm cf-verify-enforced.
check control roadmap-current  --adopter sh conformance/roadmap-current.sh
# runbook-current (C11 KIT-RUNBOOK) — the THIRD member of the living-document family above, and it sits
# here for the family's reason: citation-live asks "does the line this doc cites still exist", roadmap-current
# asks "does the roadmap still call SHIPPED work pending", and this row asks "do the kit's own release-pinned
# governing records — RUNBOOK.md and THREAT-MODEL.md — still name the release they describe". The threat model
# joined the marker table in A4 of KIT-EVAL-2-TIER-A (`D-240825-1`): it was stamped 3.185.0 (header) and 3.186.0
# (footer) against VERSION 3.218.0, so the document defining what the guard is FOR had no ratchet while the
# runbook had one. Extending this row's check was the cheap path; a second check would have been the expensive
# one (CONFORMANCE-MASS-BUDGET). Measured at the C11 probe, the kit had NO RUNBOOK.md at all and
# its cold-resume path ran entirely through one agent's private memory — a friction-test failure. C11 authored
# the file; THIS ROW IS THE RATCHET that keeps it existing and dated. STILL SELF-ARMING, for the same reason
# the two rows above carry: the check ARMS ITSELF in-script on the same un-spoofable kit-marker pair, so on an
# armed tree an absent RUNBOOK.md or THREAT-MODEL.md, a missing/duplicated/stale marker or a dead VERSION is a
# FAIL rather than an N/A, while an adopter tree (where both records are export-ignored and the adopter's own
# are stamped from the templates) self-declares N/A and C6 renders it N-A. --kitself (ADOPTER-GATES-INERT A3):
# the subject is explicitly "the KIT'S OWN release-pinned governing records" (this comment's own words) — a
# genuine kit fact; the registry flag is added purely for the census, the self-arming logic above still
# governs behaviour. Registering it here also enrols the file in non-vacuity.sh's sweep
# (which selects from these `^check control` rows); its own --selftest runs as a dedicated ci.yml step
# (conformance-selftests, "runbook-current self-test") and the LIVE check runs in `docs-links` — the same
# required, no-`if:` job, chosen because a runbook-currency check governs exactly the `.md`-only PRs that
# disarm cf-verify-enforced. HONEST CEILING, so the row is not read as more than it is: it proves EXISTENCE +
# VERSION-STRING CURRENCY, never that a single procedure in the file is true.
check control runbook-current  --kitself sh conformance/runbook-current.sh
check control whitespace-clean  sh conformance/whitespace-clean.sh
check control build-output-ignored  sh conformance/build-output-ignored.sh
check control assurance-tiers   sh conformance/assurance-tiers.sh
check control promotion-contract  sh conformance/promotion-contract-documented.sh
check control inception-bootstrap  sh conformance/inception-bootstrap-documented.sh
check control backlog-adapters sh conformance/backlog-adapters.sh
# --kitself (ADOPTER-GATES-INERT A3): scans "the kit's own checks" (conformance/*.sh, scripts/*.sh,
# hooks/pre-push, its own header) for --selftest wiring into the KIT's own ci.yml — a kit fact, and
# meaningless once an adopter's export prunes those very files/that workflow.
check control ci-selftest-cov  --kitself sh conformance/ci-selftest-coverage.sh
check control runtime-floor   sh conformance/runtime-floor-coherent.sh
# Registered here (unlike non-vacuity-wired below) BECAUSE IT IS PORTABLE: a pure classifier over a file
# listing, with no dependency on the kit's own ci.yml, so it behaves identically on an adopter artifact.
# It lives in conformance/ (not scripts/) DELIBERATELY: the non-vacuity sweep's target_set only greps
# `conformance/*.sh`, so a classifier in scripts/ would never be mutation-tested. A classifier that could be
# neutered into "everything is docs-only" would silently skip the conformance gates — it MUST be swept.
check control ci-classify      sh conformance/ci-classify-changes.sh --selftest
# NOT REGISTERED HERE (deliberate): conformance/non-vacuity-wired.sh. It locks THE KIT'S OWN ci.yml
# (that the shard matrix launches every leg the sweep declares). This battery is PORTABLE — adopters run
# it too — and after incept an adopter's .github/workflows/ci.yml is THEIR pipeline, which has no sharded
# sweep to lock, so the check would correctly FAIL on every adopter. It is enforced as a ci.yml STEP (in
# conformance-core, a shard of the required `conformance` aggregate) — a failure there still reddens the
# required check. Caught by artifact-gate on PR #309: the kit's own gate, run on the INCEPTED artifact.
# Every exclusion from this battery is named with its reason in conformance/aggregate-exclusions.txt,
# and conformance/aggregate-coverage.sh FAILs on any check that is neither registered nor excluded.
#
# ★ verify-enforced-wired.sh USED TO SHARE THAT EXCLUSION — and no longer does (CP7R5-GATE-AUTHORITY).
# The old reasoning was "an adopter's ci.yml is THEIR pipeline, so the check would fail on every
# adopter". That was TRUE while no emitted pipeline ran the aggregate. Now that all 11 emitted
# pipelines carry a real `verify.sh --require` step, an incepted tree PASSES it — measured on a real
# export→incept before this line was written, not reasoned. So it is registered below, and an adopter
# who deletes the step goes RED: that is the enforcement, not a regression. Its --fleet mode stays
# kit-only (an adopter's tree is pruned to one profile) and is enforced as a ci.yml step instead.
# --adopter (ADOPTER-GATES-INERT A3): the subject is the ADOPTER'S OWN ci.yml running `verify --require`
# — it correctly N/As pre-inception (no emitted pipeline yet) and ARMS the moment incept emits one;
# --kitself would silence exactly the enforcement this row exists for.
check control verify-enforced  --adopter sh conformance/verify-enforced-wired.sh
check control onboarding       sh conformance/onboarding-complete.sh
check control discovery        sh conformance/discovery-complete.sh
check control adopter-preflight --kitself sh conformance/adopter-preflight-wired.sh
# --kitself (ADOPTER-GATES-INERT A3): "regression-lock for the S3 adopter-clean obtain MECHANISM"
# (its own header) — proves the KIT'S OWN exporter (scripts/adopter-export.sh) works, never a specific
# adopter's already-exported tree, and it needs the kit's own committed HEAD to run at all.
check control adopter-export   --kitself sh conformance/adopter-export-wired.sh
# adopter-export-claims (NON-VACUITY-SHARD2-FLOOR) — the exported tree's OWN claims-registry proof,
# un-nested out of the row above. THE ROW FORM IS `--selftest`, DELIBERATELY, and the reason is the
# whole point of the slice: the LIVE check runs two full exports and two claims-registry runs (~316s
# measured), and this aggregate is run by cf-verify-enforced AND by every local `verify.sh --require`.
# A live-form row here would charge both of them the cost the un-nesting just removed — reversing the
# cure's sign. Registering the CHEAP selftest is what enrols the file in non-vacuity.sh's sweep (which
# selects from these `^check control` rows), exactly as the loop-state and brownfield-walk rows above do.
# The LIVE both-faces proof runs in ci.yml's `cf-export-claims` job (adjudicated by the `conformance`
# aggregator) and weekly in drift-watch.yml. NOT --kitself: the selftest is hermetic (fixture trees with
# canned registries, no kit file read), so it is portable and must stay green inside the export too.
# WHAT THIS LANE GIVES UP (the coverage delta, stated): `verify.sh --require` no longer proves the
# exported tree's own claims-registry — an orphaned maintainer-only claim now surfaces only in
# cf-export-claims (non-docs PRs) and the weekly drift-watch, no longer in this local/enforced lane.
check control adopter-export-claims-selftest sh conformance/adopter-export-claims.sh --selftest
# A7 brownfield end-to-end lock: drives a legacy fixture through the CORRECTED docs/adoption/brownfield.md
# sequence to inception-done --surface rc 0, with a load-bearing negative (pre-push-skipped => FAIL).
# --kitself: it produces the tree via scripts/adopter-export.sh, which needs the kit's OWN committed .git,
# so it has no meaning on an adopter tree (N/A there; the walk also self-detects the kit repo). Its teeth
# live in the two-arm walk (a script-selftest), so non-vacuity.sh reports it UNCOVERED=no-idiom.
check control brownfield-walk  --kitself sh conformance/brownfield-walk.sh --selftest
# A2 archive lock (row CODEOWNERS-ROOT-EXPORT-LEAK): offline — `git archive HEAD` runs locally, no
# network. N/A on a non-repo or unborn-HEAD tree, so a freshly incepted adopter stays green.
# --kitself: the invariant is the KIT's (maintainer handles must not ship in the export). On an
# adopter tree the same scan would red their own legitimate handles (e.g. dual-forge CODEOWNERS
# naming the identities their .github/CODEOWNERS declares) — a false-red for a policy that is not
# theirs (review I-2). Adopter trees render N/A; the kit-side lock stays fully binding.
check control codeowners-export-clean --kitself sh conformance/codeowners-export-clean.sh
check control mode-blind       sh conformance/mode-enforcement-blind.sh
# --kitself (ADOPTER-GATES-INERT A3, design §2 bucket (b)): the E4/E5 reference-lock family below
# (orchestrator-loop, feature-flags-wired, containment-audit, runtime-security, structured-logging,
# app-tracing, metrics-endpoint, otlp-backend, trace-query, agentops-sensor) — each script's own header
# already states "kit-self lock; NOT that an adopter's app does": today they instrument the KIT's OWN
# reference app, keyed on golden-path.yml + the kit scaffold. The adopter-facing successor (grading the
# adopter's OWN deployed app) is the boarded ADOPTER-OPERATIONAL-CONFORMANCE row, not this slice.
check control orchestrator-loop --kitself sh conformance/orchestrator-loop-wired.sh
check control escalation-seam    sh conformance/escalation-wired.sh --selftest
check control proportional-gate sh conformance/proportional-gate-wired.sh --selftest
# HITL obligation engine (HITL-1/2/4/5 — HITL-5's regulated-data surface rides threat-obligation.sh's own
# selftest, so the scope label names it too). ONLY the fixture-driven, base-INDEPENDENT selftests are registered
# in this offline aggregate. The REAL diff-relative gates (sh conformance/threat-obligation.sh,
# conformance/uat-obligation.sh and conformance/a11y-obligation.sh, no args) are DELIBERATELY NOT here:
# each derives its change-set from
# `merge-base HEAD origin/main`, and by design a non-derivable base fails CLOSED (routes to 'uncertain' ->
# requires the record). In a base-less context — a shallow CI checkout with origin/main unfetched, or a
# fresh `git clone` on an adopter tree with no resolvable base — that correct fail-closed behavior would
# redden `verify.sh --require` for every caller, which is a false positive at the aggregate level (the
# aggregate must be green on any well-formed tree regardless of git-fetch depth). So each real gate runs as
# a dedicated PR-context CI step with a resolvable base (fetch-depth: 0 -> origin/main resolves) — the kit's
# own `threat-obligation`/`uat-obligation`/`a11y-obligation` jobs in ci.yml, and the reference adopter steps in
# profiles/typescript-node/ci.yml. This mirrors how promotion-readiness.sh (the same merge-base diff-relative
# pattern) runs only in the PR-context ratification.yml, never in this aggregate. The engine
# (obligation-lib.sh) still carries its own mutation-tested selftest so non-vacuity.sh mutates + kills its
# FAIL paths directly; threat-obligation.sh, uat-obligation.sh and a11y-obligation.sh each expose their
# selftest as behavioral proof. All selftests are base-independent (they build their own fixtures), so they
# belong here.
check control obligation-lib-selftest    sh conformance/obligation-lib.sh --selftest
check control threat-obligation-selftest sh conformance/threat-obligation.sh --selftest
check control uat-obligation-selftest    sh conformance/uat-obligation.sh --selftest
check control a11y-obligation-selftest   sh conformance/a11y-obligation.sh --selftest
# ceremony-binding follows the SAME split as the three obligations above: the selftest is
# base-independent (every leg builds its own git fixture repos, each hermetic w.r.t. the surrounding
# repository and its notes ref) and belongs here; the diff-relative REAL gate lives in ci.yml's PR-context job, where
# `origin/main` and refs/notes/promotions both resolve.
check control ceremony-binding-selftest  sh conformance/ceremony-binding.sh --selftest
# selftest-hermetic (PHASE-B-HYGIENE H2) — the fixture-hermeticity lane. ONLY the --selftest is
# registered: it is base-independent and hermetic by construction (every fixture repo is built by
# the selftest itself, identity inline), so it belongs in this offline aggregate on ANY tree — and
# registering it is what enrols the lane in non-vacuity.sh's sweep. The REAL gate is diff-relative
# (--touched needs a resolvable merge-base) and runs as a PR-context ci.yml step in conformance-core
# — the same split the HITL obligations and ceremony-binding rows above use. No --kitself: nothing
# here reads the kit's roster or budgets; an adopter tree answers identically.
check control selftest-hermetic  sh conformance/selftest-hermetic.sh --selftest
check control non-vacuity      sh conformance/non-vacuity.sh --selftest
# coverage-census (PR 10): the STATIC half of the mutation-coverage census — re-derive which control
# scripts are mutation-targeted vs excluded and diff against the ratified conformance/nv-coverage.tsv.
# Grep-class, ZERO mutants, so no measurable CI time (D-240815-3). --kitself for the doc-budget reason:
# the census records the KIT's control set; an adopter's own checks are their business.
check control coverage-census  --kitself sh conformance/non-vacuity.sh --coverage-census
check control eval-harness      sh conformance/eval-harness-wired.sh --selftest
check control eval-harness-runs sh conformance/eval-harness-runs.sh --selftest
check control roster-guard      sh conformance/roster-guard-wired.sh --selftest
# GATE-SUBJECT-IS-THE-ADOPTERS-SYSTEM (K13): the regression-lock for the two arms added to
# has_deploy_surface (conformance/surface-lib.sh) — surface-lib.sh itself has no --selftest of its own
# by design (aggregate-exclusions.txt); this is its wired companion. Portable (mktemp fixtures only,
# not kit-self), so registered plainly like roster-guard above.
check control surface-lib-wired sh conformance/surface-lib-wired.sh --selftest
# TRIPLE COLLAPSED (PR 10): `conflict-safe-integration` and `skill-spine` sat here as two MORE rows
# invoking orchestrator-loop-wired.sh with IDENTICAL arguments — one script run three times per aggregate
# for zero extra evidence. Both CLAIM IDS ARE UNTOUCHED (claims.tsv, REQUIRED_IDS, the S3b carve;
# DECISIONS:179 — dropping a verify row and dropping a claim are separate acts). HONEST NOTE: the claims
# job still runs each id's verifier, so the three identical runs remain THERE.
# NOT REGISTERED HERE (deliberate): conformance/incept-containment.sh. It is KIT-ONLY — its fixtures build an
# UN-INCEPTED export via `git archive HEAD`, which needs a committed kit SOURCE. The incepted adopter artifact
# (artifact-gate) has no such HEAD, and a real adopter never re-incepts (incept refuses an already-incepted
# tree), so the check cannot and should not run there. Same class as kit-base.sh / kit-manifest.sh. Its teeth
# run as a dedicated ci.yml step on the kit source (which satisfies ci-selftest-coverage) plus the standing
# self-negative inside --selftest; non-vacuity sweeps conformance/*.sh directly, so it is covered regardless.
check control release-tag       sh conformance/release-tag-wired.sh
# --kitself (ADOPTER-GATES-INERT A3): feature-flags-wired is "regression-lock for the E2 feature-flag
# REFERENCE" (its own header) — the kit's own reference wiring, not a specific adopter's app.
check control feature-flags-wired --kitself sh conformance/feature-flags-wired.sh
# --kitself: "PARITY across the app-stack PROFILES" (its own header) — grades the KIT's own template
# set (all ten profiles), meaningless on an adopter tree pruned to the ONE profile they chose.
check control profile-parity   --kitself sh conformance/profile-parity.sh
# --kitself: "ships for EVERY stack" (its own header) — grades the KIT's own template set across all
# profiles, same reason as profile-parity above.
check control ratification-parity --kitself sh conformance/ratification-parity.sh
# --kitself: same reason as ratification-parity — "ship for EVERY stack" (its own header), the kit's
# own template set.
check control adopter-gates-parity --kitself sh conformance/adopter-gates-parity.sh
# --kitself: locks that a retired KIT mechanism (check-run posters) stays retired across the kit's own
# workflows — a kit fact, not an adopter artifact.
check control poster-parity       --kitself sh conformance/poster-parity.sh
# --kitself (design §2 bucket (b), E4/E5 family): see the note above orchestrator-loop.
check control containment-audit   --kitself sh conformance/containment-audit-wired.sh
check control token-scope         sh conformance/token-scope.sh
# --kitself (E4/E5 family, design §2 bucket (b) — see the note above orchestrator-loop): each script's
# own header states "kit-self lock; NOT that an adopter's app does" — proves the KIT's reference app is
# instrumented, not that an adopter's arbitrary app is. The adopter-facing successor is the boarded
# ADOPTER-OPERATIONAL-CONFORMANCE row.
check control runtime-security    --kitself sh conformance/runtime-security.sh
check control structured-logging  --kitself sh conformance/structured-logging-wired.sh
check control app-tracing         --kitself sh conformance/app-tracing-wired.sh
check control metrics-endpoint    --kitself sh conformance/metrics-endpoint-wired.sh
check control otlp-backend        --kitself sh conformance/otlp-backend-wired.sh
check control trace-query         --kitself sh conformance/trace-query-wired.sh
check control agentops-sensor    --kitself sh conformance/agentops-sensor-wired.sh
check control author-not-approver sh conformance/author-not-approver-wired.sh
# --kitselftest (design §3 (a)+(b)): reads scripts/runaway-guard.sh and the real .kit/budget.conf (both control-plane) + temp git fixtures.
check control runaway-killswitch --kitselftest sh conformance/runaway-killswitch-wired.sh --selftest
# --adopter (ADOPTER-GATES-INERT A3): the subject is the ADOPTER'S OWN VERSION file vs THEIR OWN git
# tags — it correctly N/As pre-inception (no tags cut yet) and ARMS once the adopter releases; --kitself
# would silence a real adopter gate forever.
check control version-tag-coherent --adopter sh conformance/version-tag-coherent.sh
# --kitselftest (design §3 (a)+(b)): reads scripts/promotion-verify.sh, conformance/backlog-lib.sh, hooks/pre-push, .claude/hooks/guard-core.sh and
# .github/workflows/ci.yml (all control-plane) + temp git fixtures. Residual: the ci.yml trace-lock latches on the kit marker docs/ROADMAP-KIT.md
# (existence only; an adopter tree never carries it).
check control promotion-verify  --kitselftest sh conformance/promotion-verify-wired.sh --selftest
check control control-plane-revert-drill  sh conformance/control-plane-revert-drill.sh --selftest
# --kitselftest on both rows (design §3 (a)+(b)): the selftest reads scripts/promotion-verify.sh, conformance/verify.sh, .claude/hooks/guard-core.sh and
# the real .kit/budget.conf (all control-plane) + temp git fixtures; the bare run only greps those same three control-plane files.
check control promotion-actuate  --kitselftest sh conformance/promotion-actuate-wired.sh --selftest
check control promotion-actuate-run  --kitselftest sh conformance/promotion-actuate-wired.sh
# --kitself (ADOPTER-GATES-INERT A3): every leg below drives a REAL `incept` against the KIT's OWN
# `profiles/<x>` reference scaffold (needs the kit's committed HEAD + its own profiles/ directory,
# neither of which ships in an adopter export, which is pruned to the ONE profile the adopter chose).
# A kit fact about the kit's ten reference stacks, never a specific adopter's tree.
check control incept-first-run-green  --kitself sh conformance/incept-first-run-green.sh --selftest
check control inception-done-surface  sh conformance/inception-done.sh --selftest
check control incept-first-run-green-profile  --kitself sh conformance/incept-first-run-green.sh profiles/typescript-node
check control incept-first-run-green-go  --kitself sh conformance/incept-first-run-green.sh profiles/go
check control incept-first-run-green-python  --kitself sh conformance/incept-first-run-green.sh profiles/python
check control incept-first-run-green-rust  --kitself sh conformance/incept-first-run-green.sh profiles/rust
check control incept-first-run-green-java-spring  --kitself sh conformance/incept-first-run-green.sh profiles/java-spring
check control incept-first-run-green-kotlin  --kitself sh conformance/incept-first-run-green.sh profiles/kotlin
check control incept-first-run-green-dotnet  --kitself sh conformance/incept-first-run-green.sh profiles/dotnet
check control incept-first-run-green-terraform  --kitself sh conformance/incept-first-run-green.sh profiles/terraform
check control incept-first-run-green-data-engineering  --kitself sh conformance/incept-first-run-green.sh profiles/data-engineering
check control incept-first-run-green-ml  --kitself sh conformance/incept-first-run-green.sh profiles/ml
# SWAS-202 (GO-PROFILE-BASELINE-CI-RED) — the Go profile's toolchain pins (go.mod, setup-go, Dockerfile tag, linter,
# docs) move as ONE set. The bare run is --adopter: it grades the kit's profile in the kit and the adopter's OWN root
# go.mod / Dockerfile / emitted ci.yml after incept (advisory there: a WARN, never a red --require). The --eol face is
# drift-watch's, not this aggregate's (it is time-dependent). The selftest builds its own fixtures: --kitselftest.
check control go-toolchain-coherent  --adopter sh conformance/go-toolchain-coherent.sh
check control go-toolchain-coherent-selftest  --kitselftest sh conformance/go-toolchain-coherent.sh --selftest
check control stack-decision-integrity  sh conformance/stack-decision-integrity.sh --selftest
# --adopter (ADOPTER-GATES-INERT A3): the LIVE leg's subject is the ADOPTER'S OWN stack-choice ADR
# rationale — it correctly N/As pre-inception (no ADR authored yet) and ARMS once the adopter writes
# one; --kitself would silence a real adopter gate forever. The --selftest sibling above is hermetic
# (fixture-driven) and stays unflagged.
check control stack-decision-integrity-adr  --adopter sh conformance/stack-decision-integrity.sh
check control deploy-decision-integrity  sh conformance/deploy-decision-integrity.sh --selftest
# --adopter, same reason as stack-decision-integrity-adr above: the subject is the adopter's OWN
# deploy-target rationale.
check control deploy-decision-integrity-run  --adopter sh conformance/deploy-decision-integrity.sh
check control harness-decision-integrity  sh conformance/harness-decision-integrity.sh --selftest
# --adopter, same reason again: the subject is the adopter's OWN harness-fit rationale.
check control harness-decision-integrity-run  --adopter sh conformance/harness-decision-integrity.sh
# SWAS-303a: the model axis (#4) is a config row in the engine, not a shim. N/A while the map is all-`unset`.
check control model-decision-integrity  sh conformance/decision-integrity.sh model --selftest
# --adopter, same reason again: the subject is the adopter's OWN model-fit rationale (read only once their map binds a model).
check control model-decision-integrity-run  --adopter sh conformance/decision-integrity.sh model
# SWAS-303a: the vendor lock + the map's decision= record. --adopter: it grades the adopter's OWN map and their kit-shipped
# seat-binding surfaces; it never skips (a single-model adopter reads PASS), and its fixtures run in the --selftest sibling.
check control model-tiering  sh conformance/model-tiering.sh --selftest
check control model-tiering-lock-run  --adopter sh conformance/model-tiering.sh
check control script-disclosure  sh conformance/script-disclosure.sh --selftest
check control script-disclosure-scan  sh conformance/script-disclosure.sh
# shell-parse-lint (SEMGREP-BASH-PARSE-KIT-WIDE T1): the shared SAST-parse structural lint —
# its own fixtures, then a live run over the default list (conformance/sast-parse-files.txt).
check control shell-parse-lint  sh conformance/shell-parse-lint.sh --selftest
check control shell-parse-lint-run  sh conformance/shell-parse-lint.sh
# board-parser-drift (BOARD-PIPE-ESCAPE CI fix round, collected-not-gated): the mutation-proof
# selftest AND the live corpus/enum run both register — the real run is base-independent (reads the
# repo's own board-claim.sh/backlog-lib.sh/meta-control-fresh.sh/backlog-current.sh, no live creds).
check control board-parser-drift  sh conformance/board-parser-drift.sh --selftest
check control board-parser-drift-run  sh conformance/board-parser-drift.sh
check control backlog-current  sh conformance/backlog-current.sh --selftest
# --adopter (ADOPTER-GATES-INERT A3): the subject is the ADOPTER'S OWN BACKLOG.md board hygiene — it
# correctly N/As pre-inception (no board authored yet) and ARMS once the adopter starts one; --kitself
# would silence a real adopter gate forever.
check control backlog-current-run  --adopter sh conformance/backlog-current.sh .
# owner-step-markers (PHASE-B-HYGIENE R1) — stale `OWNER STEP OPEN` / "not yet bound live" markers
# must not outlive their steps. Both rows are base-independent (git ls-files + grep; the selftest
# builds its own fixture repos), so live + selftest register here and enter the mutation sweep.
check control owner-step-markers          sh conformance/owner-step-markers.sh
check control owner-step-markers-selftest  sh conformance/owner-step-markers.sh --selftest
# KW6-A2 presence gate: selftest ONLY — no `-run` companion. Unlike backlog-current, the real run
# needs a live PR number (--pr), which exists only in PR context, so it cannot run as an offline
# verify.sh control-check; the ci.yml `backlog-presence` job calls check_pr live. check_pr is NOT dead
# code: selftest() drives it by argument (assert_msg), and the CI job invokes it on every gated PR.
check control backlog-presence  sh conformance/backlog-presence.sh --selftest
# T0-09 — pairs with the `check doc security-policy` row below: that row proves the disclosure
# policy is RECORDED; security-channel-live.sh probes the FORGE SETTING it advertises (PVR enabled
# on the declared `Channel repo:`). Selftest ONLY — same shape as backlog-presence above: the live
# probe needs gh+network+auth, and adopters run `verify.sh --require` offline with no GH_TOKEN
# (all ten profiles/*/ci.yml), so registering the live row would red every adopter's documented
# first CI push. The LIVE probe runs as a dedicated step in the kit's own ci.yml (step-scoped
# GH_TOKEN, beside the security-policy real-path step); adopters MAY wire the live run into their
# own pipeline the same way (no profile ships the step yet). check_channel is NOT dead code:
# selftest() drives it by argument, and the
# CI step invokes it live. The load-bearing negative lives in --selftest (stubbed
# {"enabled":false}); the live repo must never serve as the negative.
check control security-channel-live-selftest sh conformance/security-channel-live.sh --selftest
# TIER0-LOCKS-OWED (c): review-lane.sh was wired ONLY in ci.yml, so `non-vacuity.sh --only
# review-lane.sh` matched no targeted check and the mutation sweep never covered the kit's newest
# control-plane gate (the review-record grammar). Selftest-only, same shape as backlog-presence and
# security-channel-live above: the live `review-lane.sh --pre-push` / `--pr` runs need a real git
# history / forge context that a hermetic offline sweep does not carry; those live paths run in
# ci.yml and at the pre-push speed bump, not here. review-lane.sh is NOT dead code registered only
# for the sweep's sake: its --selftest oracle drives the same functions the live callers invoke.
check control review-lane      sh conformance/review-lane.sh --selftest
# --kitselftest (design §3 (a)+(b)): reads conformance/* (incl. prepush-twins.tsv, shellcheck.sh, ci-classify-changes.sh), the CI workflow and
# profiles/typescript-node/ci.yml (all control-plane) + temp fixtures; BACKLOG.md/CHANGELOG.md appear only as strings in its cache-key code.
check control prepush-lane    --kitselftest sh conformance/prepush-lane.sh --selftest   # selftest only (why + ceiling: conformance/README.md index row; the live faces run the KIT's battery and --census grades the KIT's ci.yml, so neither is portable — the census is its own conformance-core step). Not dead code: --selftest drives what `sparkwright prepush` invokes live.
# CONFORMANCE-DOC-FAMILIES-MERGE (D-240828-4): the nine conditional readiness rows now dispatch into
# conformance/readiness.sh (subject: conformance/readiness.tsv) and the two kit-doc marker rows into
# conformance/doc-markers.sh (subject: conformance/doc-markers.tsv). SAME ROW NAMES, same three-state
# contract, same per-case wording — the row name is what a reader and the summary see, and it did not
# move. deployable-ready / test-layers-ready / feature-flags-ready / roster-authority / security-policy
# are NOT part of the fold (structural detectors and mixed checks); they still name their own scripts.
check doc     deployable-ready sh conformance/deployable-ready.sh
check doc     dr-ready         sh conformance/readiness.sh dr-ready
check doc     resilience-ready sh conformance/readiness.sh resilience-ready
check doc     eval-ready       sh conformance/readiness.sh eval-ready
check doc     eval-ready-ml    --kitself sh conformance/readiness.sh eval-ready profiles/ml
check doc     observability-ready sh conformance/readiness.sh observability-ready
check doc     responsible-ai-ready sh conformance/readiness.sh responsible-ai-ready
check doc     responsible-ai-ready-ml --kitself sh conformance/readiness.sh responsible-ai-ready profiles/ml
check doc     test-data-ready  sh conformance/readiness.sh test-data-ready
check doc     test-layers-ready sh conformance/test-layers-ready.sh
check doc     preview-env-ready sh conformance/readiness.sh preview-env-ready
check doc     agentops-ready  sh conformance/readiness.sh agentops-ready
check doc     security-policy sh conformance/security-policy.sh
check doc     privacy-ready   sh conformance/readiness.sh privacy-ready
check doc     feature-flags-ready sh conformance/feature-flags-ready.sh
check doc     gate-eval-secrets sh conformance/doc-markers.sh gate-eval-secrets
check doc     artifact-lineage sh conformance/doc-markers.sh artifact-lineage
check doc     dod-precedence  sh conformance/doc-markers.sh dod-precedence
check doc     collected-not-gated sh conformance/doc-markers.sh collected-not-gated
check doc     roster-authority sh conformance/roster-authority-ready.sh
fi

# SWAS-393: a row shard names the rows it owns and its counters, for --merge (a plain run prints neither line).
if [ "$SHARD_N" -gt 0 ]; then
  printf 'Shard-rows: %s/%s%s\n' "$SHARD_I" "$SHARD_N" "$_rs_rows"
  printf 'Shard-counts: controls=%d docs=%d unverified=%d nas=%d failed=%d misconfigured=%d ctrl_fail=%d\n' "$controls" "$docs" "$unverified" "$nas" "$failed" "$misconfigured" "$ctrl_fail"
fi
echo ""
# ADOPTER-KIT-SELFTESTS-ON-CHANGE — ONE notice line when any --kitselftest row was skipped. Never says the
# skipped checks "passed" (design F1: the skip INHERITS the base's verdict, it does not check it). Nothing
# is printed or written when nothing was skipped.
if [ -n "$SKIPPED_KS" ]; then
  _ks_ver=""
  for _ks_src in "origin/kit-base:VERSION" "kit-base:VERSION"; do
    [ -z "$_ks_ver" ] || break
    _ks_ver=$(git show "$_ks_src" 2>/dev/null | head -n 1 | tr -d ' \t\r') || _ks_ver=""
  done
  [ -n "$_ks_ver" ] || _ks_ver=$(head -n 1 VERSION 2>/dev/null | tr -d ' \t\r') || _ks_ver=""
  [ -n "$_ks_ver" ] || _ks_ver=unknown
  _ks_names=${SKIPPED_KS# }
  _ks_note="kit selftests not re-run: $_ks_names — this PR changes no control-plane path, so their subject is byte-identical to the base; they run in full on every push to main and on the scheduled run (kit v$_ks_ver)"
  printf '%s\n' "$_ks_note"
  if [ -n "$KS_SUMMARY" ]; then ( printf '%s\n' "$_ks_note" >> "$KS_SUMMARY" ) 2>/dev/null || true; fi
fi
# `misconfigured` is APPENDED AFTER `failed`, never inserted: three ci.yml walk steps parse this line
# with `sed -n 's/.*· \([0-9]*\) n\/a ·.*/\1/p'`, which needs the `· ` that follows `n/a` to survive.
printf 'Summary: %d control-checks · %d doc-checks · %d unverified · %d n/a · %d failed · %d misconfigured\n' "$controls" "$docs" "$unverified" "$nas" "$failed" "$misconfigured"
# ── THE CENSUS RECONCILIATION-OF-RECORD (PR 10, VERIFY-HEADLINE-TRUTH). A SIBLING line, never an edit to
# the format string above, and it deliberately does NOT begin with the token `Summary` — that scalar is
# read as ONE line by this file's own C6 leg, three ci.yml walk steps and promotion-readiness.sh:407, so
# a second `^Summary:` match would make every one of those seds parse a multi-line string.
# THREE REAL POPULATIONS, NOT ONE NUMBER: registered ROWS, the unique SCRIPTS they invoke, and the FILES
# on disk. All three are true, none is the others, and the fourth field (files no row invokes: libs,
# ci-only, kit-self) is the gap that made the mismatch look like an error. Computed at RUNTIME — every
# hard-coded count in this file had gone stale by C6.
_sc_reg=$(grep -E '^check ' "$_SELF" 2>/dev/null | grep -oE 'conformance/[a-z0-9-]+\.sh' | sort -u) || _sc_reg=""
_sc_uniq=$(printf '%s\n' "$_sc_reg" | grep -c 'conformance/') || _sc_uniq=0
_sc_rows=$(grep -c '^check ' "$_SELF" 2>/dev/null) || _sc_rows=0
_sc_disk=0; _sc_norow=0
for _scf in conformance/*.sh; do
  [ -f "$_scf" ] || continue
  _sc_disk=$((_sc_disk + 1))
  printf '%s\n' "$_sc_reg" | grep -Fxq "$_scf" || _sc_norow=$((_sc_norow + 1))
done
printf 'Scripts: %d unique conformance scripts across %d rows (%d conformance/*.sh on disk; %d registered by no row: libs, ci-only, kit-self)\n' "$_sc_uniq" "$_sc_rows" "$_sc_disk" "$_sc_norow"
echo "A green run proves controls hold AND release/DR/resilience safety is DOCUMENTED —"
echo "it does NOT prove those procedures were tested. doc-checks verify records exist."
echo "UNVERIFIED is NOT a pass. See conformance/README.md \"What a green run means\"."

if [ -n "$SEAM_ACTIVE" ]; then
  # A seam run is a TEST of this file, never a verdict: the rows above may be a stub registry, and the
  # Scripts: line above counts the BUILT-IN registry's rows, not necessarily the ones this run executed.
  echo "RESULT: UNVERIFIED (TEST SEAM ACTIVE: $SEAM_ACTIVE — this run is NOT a verdict, whatever the rows above say)"
  exit 2
fi
result_sentence; exit $?
