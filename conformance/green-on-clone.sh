#!/bin/sh
# green-on-clone.sh — the adopter's FIRST CI PUSH must be green.
#
# THE PROOF (unchanged — this is a MOVE, not a new gate, and certainly not a weaker one): export the kit
# exactly as an adopter gets it, commit it, and run the SAME aggregate the adopter's own ci.yml runs —
# `verify.sh --require`. A kit-self control-check that hard-fails on the export (because it needs an
# export-ignored file and does not N/A when that file is absent) would otherwise surface only when a REAL
# ADOPTER pushes for the first time. Their first impression of the kit would be a red build.
#
# WHY IT LIVES HERE NOW (P1-CI-c) — it used to be NESTED inside conformance/adopter-export-wired.sh:
#
#   COST    — it is a full 87-check battery (~58s of that check's 77s). And `non-vacuity` MUTATION-TESTS
#             adopter-export-wired.sh, so EVERY MUTANT re-ran the ENTIRE BATTERY. That — not the export,
#             which takes <1s — was the 387s non-vacuity leg. A proof nested inside a mutation-tested
#             check is paid for ONCE PER MUTANT.
#   OPACITY — it ran as `verify.sh --require >/dev/null 2>&1`. The failure output was DISCARDED and
#             replaced with a generic string: you learned green-on-clone broke, never WHICH control
#             failed. P0-FU(a) named exactly this — "load-sensitive + opaque ... refactor to a dedicated,
#             visible green-on-clone job" — and it was never done until now.
#
# Un-nested into its own check + its own parallel CI job. **Nothing is skipped; the proof simply stops
# being re-run once per mutant, and starts printing why it failed.**
#
# ADOPTER-GATES-INERT (census / kit-self face, design A2) — this is also where the census FOLDS IN.
# `conformance/adopter-census.sh` used to build ITS OWN second export and run ITS OWN second full
# `verify.sh` battery on it — measured 862s (~14 min); registered anywhere it would roughly TRIPLE the
# cost of this one job. So `check()` below captures the SAME `verify.sh --require` output it already
# produces (via the `run_aggregate` seam) and hands it to `census_verdict`, which cross-references it
# against the export's own registry for any `control` row that renders N-A without being classified
# `--kitself` or `--adopter` (conformance/adopter-census.sh's own header has the full algorithm). TWO
# separately labelled verdicts come out of the ONE run: "the exported tree passes verify --require" and
# "vacuous control rows: none/list" — deliberately not merged into one, so each stays independently
# legible (software-dev separation of concerns) and either can red this check for its own reason.
#
# RECURSION-SAFE, and this is load-bearing: this check EXPORTS the kit and runs the aggregate INSIDE the
# export. If it were registered in that aggregate, it would export itself, forever. The kit-repo detector
# at the bottom N/A-skips outside the kit (both markers are stripped from the export), so the exported
# tree's own copy returns immediately. It is ALSO deliberately NOT registered in conformance/verify.sh —
# belt and braces. Do not "helpfully" add it there.
#
# What it changes: nothing in the repo (exports to a temp dir, removed on exit).
# Guardrails: read-only wrt the kit; temp-only writes; teardown is non-fatal.
#
# Usage:
#   sh conformance/green-on-clone.sh      # 0 = the adopter's first push is green · 1 = it is NOT
#   sh conformance/green-on-clone.sh --selftest
#   sh conformance/green-on-clone.sh --timing-file <path>   # also record per-row seconds of the inner verify.sh run
#   sh conformance/green-on-clone.sh --report-times <path>  # print the 15 slowest rows + ::warning annotations; always exits 0
#
# SWAS-393 (SWAS-314 slice S3, design 2026-10-24-ci-shaping section 4.2) — THE SAME PROOF, AS PARALLEL LEGS AND A JOIN. In CI the job
# `cf-green-on-clone` is the JOIN of `cf-goc-rows` legs and `cf-goc-battery` legs; each leg exports the kit, commits the export
# (with fixed dates, so every leg's commit id is the same) and runs ONE slice of what the serial mode above runs in a row:
#   --leg-rows <i>/<N> --output-file <record>       verify.sh --require --shard i/N --output-file <record> on the export
#                                                   (+ <record>.timing: the shard's per-row seconds); prints the export's tree id
#   --leg-battery <j>/<M> --output-file <record>    agent-autonomy.sh --shard j/M --output-file <record> on the export, which must sit
#                                                   under a temp root (the `tmp1` dims the serial mode's battery ran with); prints the tree id
#   --join --rows <dir> --battery <dir> [--timing-file <path>]
#                                                   export + commit again, then verify.sh --merge --battery <dir> <dir>/*.rec on it (which
#                                                   refuses a record graded in any OTHER tree: the legs' tree ids must equal this one's),
#                                                   then the same adopter-census as the serial mode on the merged output
# A leg's exit is its slice's verdict; the join's exit is the whole proof's. No leg and no join reads the environment to choose.
set -eu
ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)
TIMING_FILE=""   # --timing-file <path>: per-row timing of the inner verify.sh run (SWAS-372); absent = off
LEG_MODE=""; LEG_SPEC=""; LEG_REC=""; JOIN_ROWS=""; JOIN_BAT=""   # SWAS-393: --leg-rows / --leg-battery / --join (arguments only)

# Teardown must NEVER decide a verdict (P0-FU(a): a bare `rm` under `set -eu` is a latent flake — a
# detached git gc still writing into .git races the rm into ENOTEMPTY and reddens a PASSING check).
_cleanup() { rm -rf "$1" 2>/dev/null || true; }

# ── run_aggregate <tree> : THE SEAM. Run the adopter's own aggregate inside <tree>, with output VISIBLE,
#    and propagate its verdict. Factored out so --selftest can drive this EXACT seam against a tiny
#    fixture instead of paying for a real 87-check battery. That matters: the selftest runs on EVERY PR,
#    and a selftest that re-ran the real battery would cost ~2 MINUTES per PR — giving back everything
#    this slice saves. The LIVE export is exercised by the cf-green-on-clone job; the selftest's job is to
#    prove the SEAM (a failing aggregate reddens this check, and the failing control is NAMED).
#
# CAPTURES rather than streams (ADOPTER-GATES-INERT): the output must reach census_verdict too, so it is
# collected via command substitution into $RUN_AGGREGATE_OUTPUT, then printed in full for visibility —
# unchanged from the operator's point of view (still sees everything), just no longer line-buffered live.
run_aggregate() {
  _t=$1; shift
  # SWAS-393: the arguments after the tree are verify.sh's own (the join passes --merge ...); none = today's `--require`.
  if [ "$#" -gt 0 ]; then echo "--- the adopter's own verify.sh $1 (the shards of the aggregate), on the exported tree ---"
  else echo "--- the adopter's own verify.sh --require, on the exported tree ---"; set -- --require; fi
  # SWAS-372: --timing-file <path> (off by default) is passed through to the inner run; absent = the old command.
  if [ -n "$TIMING_FILE" ]; then set -- "$@" --timing-file "$TIMING_FILE"; fi
  if _ra_out=$( cd "$_t" && sh conformance/verify.sh "$@" 2>&1 ); then _ra_rc=0; else _ra_rc=$?; fi
  printf '%s\n' "$_ra_out"
  RUN_AGGREGATE_OUTPUT=$_ra_out
  if [ "$_ra_rc" = 0 ]; then
    echo "-------------------------------------------------------------------"
    echo "OK: green-on-clone — the exported tree passes verify --require (an adopter's first CI push is GREEN)"
    return 0
  fi
  echo "-------------------------------------------------------------------"
  echo "FAIL: green-on-clone — the EXPORTED tree fails verify --require. A real adopter's FIRST push would be RED." >&2
  echo "      Usually a kit-self control-check that needs an export-ignored file and does not N/A when it is absent." >&2
  echo "      The failing control is NAMED in the aggregate output above — it is no longer swallowed." >&2
  return 1
}

# ── census_verdict <tree> <aggregate-output> : THE SECOND SEAM. Cross-reference <aggregate-output>
#    (already produced by run_aggregate above — this function never runs anything) against <tree>'s own
#    conformance/verify.sh registry via conformance/adopter-census.sh, print the labelled verdict, and
#    propagate its verdict. Factored out for the SAME reason run_aggregate is: --selftest drives this
#    exact seam against fixture trees instead of paying for a real export+battery to prove the fold-in
#    wiring (a planted unclassified vacuous control row must red THIS check, not just census's own
#    --selftest, which only proves adopter-census.sh's internal parse in isolation).
census_verdict() {
  _cv_t=$1; _cv_out=$2
  echo "--- adopter-census: vacuous control rows on this export ---"
  if _cv_res=$(sh "$ROOT/conformance/adopter-census.sh" --assert "$_cv_out" "$_cv_t" 2>&1); then _cv_rc=0; else _cv_rc=$?; fi
  printf '%s\n' "$_cv_res"
  echo "-------------------------------------------------------------------"
  if [ "$_cv_rc" != 0 ]; then
    echo "FAIL: green-on-clone — adopter-census found a vacuous control row (or could not measure). See above." >&2
  fi
  return "$_cv_rc"
}

# ── commit_tree <tree> : an adopter's tree is a git repo on their first push, and some controls read git
#    state. gc.auto=0 because a detached auto-gc still writing into .git races the teardown `rm` into
#    ENOTEMPTY and reddens a PASSING check — the P0-FU(a) flake, in the very check that surfaced it.
#    SWAS-393 (C7): the commit uses FIXED DATES, so every leg's commit of the same export is the same commit id and the legs' records
#    match the join's head.
commit_tree() {
  ( cd "$1" && git init -q && git add -A \
    && GIT_AUTHOR_DATE="2000-01-01T00:00:00Z" GIT_COMMITTER_DATE="2000-01-01T00:00:00Z" git -c gc.auto=0 -c commit.gpgsign=false -c user.email=ci@kit -c user.name=ci commit -qm export >/dev/null 2>&1 )   # MG:dates
}

# prep_export <profile> : export the kit as an adopter gets it and commit it; sets EXPORT_DIR. Returns 1 (FAIL printed) on failure.
prep_export() {
  EXPORT_DIR=$(mktemp -d)/export
  if ! ( cd "$ROOT" && sh scripts/adopter-export.sh "$EXPORT_DIR" --profile "$1" >/dev/null 2>&1 ); then
    echo "FAIL: green-on-clone — adopter-export itself failed; nothing to judge" >&2
    _cleanup "$EXPORT_DIR"; return 1
  fi
  if ! commit_tree "$EXPORT_DIR"; then
    echo "FAIL: green-on-clone — could not commit the exported tree" >&2
    _cleanup "$EXPORT_DIR"; return 1
  fi
}

# check <profile> -> 0 green · 1 red.
check() {
  _prof=${1:-typescript-node}
  _rc=0
  prep_export "$_prof" || return 1
  _d=$EXPORT_DIR
  run_aggregate "$_d" || _rc=1
  census_verdict "$_d" "$RUN_AGGREGATE_OUTPUT" || _rc=1
  _cleanup "$_d"
  return "$_rc"
}

# leg_rows <i>/<N> <record> : one row shard of the aggregate on a fresh export; the exit is the shard's.
leg_rows() {
  prep_export typescript-node || return 1
  _d=$EXPORT_DIR
  echo "export tree: $(git -C "$_d" write-tree)"
  case "$2" in
    /*) _lr_rec=$2 ;;
    *) _lr_rec="$(pwd)/$2" ;;
  esac
  _lr_rc=0
  ( cd "$_d" && sh conformance/verify.sh --require --shard "$1" --output-file "$_lr_rec" --timing-file "$_lr_rec.timing" ) || _lr_rc=$?
  _cleanup "$_d"
  return "$_lr_rc"
}

# leg_battery <j>/<M> <record> : one battery shard on a fresh export, which must sit under a temp root (the tmp1 dims the serial mode graded).
leg_battery() {
  prep_export typescript-node || return 1
  _d=$EXPORT_DIR
  echo "export tree: $(git -C "$_d" write-tree)"
  case "$2" in
    /*) _lb_rec=$2 ;;
    *) _lb_rec="$(pwd)/$2" ;;
  esac
  _lb_dims=$( cd "$_d" && sh conformance/agent-autonomy.sh --dims ) || _lb_dims="<--dims failed>"
  case "$_lb_dims" in
    *-tmp1-*) ;;
    *) echo "FAIL: green-on-clone — the export has dims '$_lb_dims', not a temp-root (tmp1) tree; its shard could not join the battery the serial mode graded" >&2; _cleanup "$_d"; return 1 ;;   # MG:dims
  esac
  _lb_rc=0
  ( cd "$_d" && sh conformance/agent-autonomy.sh --shard "$1" --output-file "$_lb_rec" ) || _lb_rc=$?
  _cleanup "$_d"
  return "$_lb_rc"
}

# join_aggregate <rows-dir> <battery-dir> : the join — a fresh export, verify.sh --merge over the legs' records, then the census.
join_aggregate() {
  prep_export typescript-node || return 1
  _d=$EXPORT_DIR
  echo "export tree: $(git -C "$_d" write-tree)"
  _ja_rows=$1; _ja_bat=$2
  set -- --merge --battery "$_ja_bat"
  for _ja_f in "$_ja_rows"/*.rec; do
    if [ -f "$_ja_f" ]; then set -- "$@" "$_ja_f"; fi
  done
  _rc=0
  run_aggregate "$_d" "$@" || _rc=1
  census_verdict "$_d" "$RUN_AGGREGATE_OUTPUT" || _rc=1
  _cleanup "$_d"
  return "$_rc"
}

# ── report_times <file> : SWAS-372 — read the --timing-file record (`name<TAB>secs<TAB>verdict`) and print the 15
#    slowest rows plus WARN annotations. It NEVER fails: every path returns 0 (a slow row is a warning, not a gate).
#    WARN 1: one `::warning title=row-time::` per row over 10% of the summed row time.
#    WARN 2: when the summed total exceeds 1.3 x 2300 s = 2990 s, one warning naming the top 3 rows.
#    2300 s is the MEASURED normal [M]: the cf-green-on-clone span "the adopter's own verify.sh --require, on the
#    exported tree" was 2209 s on the #890 run (run 40047142655) and 2283 s on the #895 run (run 40120698997).
#    The 10-24 slow window was #893 (run 40097361027) at 3225 s [M] (SWAS-372). 2300 s is the round figure just above
#    the two normals; 1.3x leaves headroom for runner noise.
report_times() {
  _rp=${1:-}
  if [ -z "$_rp" ] || [ ! -s "$_rp" ]; then echo "row-times: not produced"; return 0; fi
  _rp_sorted=$(sort -t "$(printf '\t')" -k2,2nr "$_rp" 2>/dev/null) || _rp_sorted=""
  [ -n "$_rp_sorted" ] || { echo "row-times: not produced"; return 0; }
  echo "--- 15 slowest rows (name, secs, verdict) ---"
  printf '%s\n' "$_rp_sorted" | awk -F'\t' 'NR <= 15 { gsub(/[^A-Za-z0-9_.-]/, "?", $1); gsub(/[^A-Za-z0-9_.-]/, "?", $3); printf "  %-44s %6s s  %s\n", $1, $2 + 0, $3 }'
  printf '%s\n' "$_rp_sorted" | awk -F'\t' -v norm=2300 '
    { gsub(/[^A-Za-z0-9_.-]/, "?", $1); name[NR] = $1; secs[NR] = $2 + 0; total += $2 }   # a row name never carries ::, a backtick or a newline into an annotation
    END {
      if (total <= 0) exit 0
      printf "row-times: summed row time %d s over %d rows\n", total, NR
      for (i = 1; i <= NR; i++)
        if (secs[i] * 10 > total)
          printf "::warning title=row-time::%s took %d s, >10%% of the aggregate %d s\n", name[i], secs[i], total
      if (total > 1.3 * norm) {
        top = ""
        for (i = 1; i <= 3 && i <= NR; i++) top = top (i > 1 ? ", " : "") name[i] " (" secs[i] " s)"
        printf "::warning title=row-time::aggregate %d s is over 1.3 x %d s; top 3 rows: %s\n", total, norm, top
      }
    }'
  return 0
}

# parse_modes <args...> : the argument grammar of --leg-rows / --leg-battery / --join. PURE: it only sets LEG_MODE, LEG_SPEC, LEG_REC,
# JOIN_ROWS, JOIN_BAT and TIMING_FILE, or prints the usage error and returns 2. It is refused here, BEFORE any export is made, and the
# selftest drives this function directly, so a wrongly accepted line can never start a real export.
parse_modes() {
  case "$1" in
    --leg-rows|--leg-battery)
      case "${2:-}" in
        [1-9]*/[1-9]*) ;;
        *) echo "green-on-clone: usage error — $1 needs <i>/<N>" >&2; return 2 ;;
      esac
      if [ "$#" != 4 ] || [ "${3:-}" != "--output-file" ] || [ -z "${4:-}" ]; then
        echo "green-on-clone: usage error — $1 <i>/<N> --output-file <record>" >&2; return 2   # MG:usage
      fi
      LEG_MODE=$1; LEG_SPEC=$2; LEG_REC=$4 ;;
    --join)
      if [ "$#" -lt 5 ] || [ "${2:-}" != "--rows" ] || [ "${4:-}" != "--battery" ] || [ -z "${3:-}" ] || [ -z "${5:-}" ]; then
        echo "green-on-clone: usage error — --join --rows <dir> --battery <dir> [--timing-file <path>]" >&2; return 2
      fi
      JOIN_ROWS=$3; JOIN_BAT=$5
      if [ "$#" = 7 ] && [ "${6:-}" = "--timing-file" ] && [ -n "${7:-}" ]; then
        case "$7" in /*) TIMING_FILE=$7 ;; *) TIMING_FILE="$(pwd)/$7" ;; esac
      elif [ "$#" != 5 ]; then
        echo "green-on-clone: usage error — --join --rows <dir> --battery <dir> [--timing-file <path>]" >&2; return 2
      fi
      LEG_MODE=--join ;;
  esac
  return 0
}

# ── selftest : the proof must be LOAD-BEARING. Un-nesting is only safe if the un-nested check can still
#    FAIL — otherwise we traded ~200s of CI for a green light that attests nothing, and a real adopter's
#    first push goes red instead of ours.
selftest() {
  st=0; t=$(mktemp -d)

  # _fixture <dir> <verify-body> : a minimal tree that looks like an adopter export to run_aggregate — it
  # needs exactly one thing, a conformance/verify.sh that exits 0 or 1 and prints.
  _fixture() {
    mkdir -p "$1/conformance"
    printf '#!/bin/sh\n%s\n' "$2" > "$1/conformance/verify.sh"
  }

  # LIVENESS ANCHOR — a PASSING aggregate must make this check PASS. Without it, a check that always FAILs
  # would satisfy the negative below and be worse than useless.
  d="$t/ok"; _fixture "$d" 'echo "  [control] everything    PASS"; exit 0'
  if run_aggregate "$d" >/dev/null 2>&1; then
    echo "PASS: a GREEN aggregate -> green-on-clone passes (liveness anchor)"
  else
    echo "FAIL: liveness — a passing aggregate was reported RED"; st=1
  fi

  # TEETH — THE LOAD-BEARING NEGATIVE, and the entire justification for un-nesting. A FAILING aggregate
  # must make this check RED. If a broken export can still pass here, the move traded cost for a lie.
  # (Verified LIVE too, at authoring time: a planted kit-self control that fails on the export — the exact
  # regression class — turned this check RED and NAMED the control. Note the export archives COMMITTED
  # HEAD, so such a mutant must be committed to reach the export at all.)
  d="$t/red"; _fixture "$d" 'echo "  [control] planted-regression    FAIL"; exit 1'
  if run_aggregate "$d" >/dev/null 2>&1; then
    echo "FAIL: teeth — a FAILING aggregate passed green-on-clone; a broken export would ship undetected"; st=1
  else
    echo "PASS: a FAILING aggregate -> green-on-clone goes RED (the un-nested proof is load-bearing)"
  fi

  # VISIBILITY — the defect that motivated the un-nesting. The nested version ran `>/dev/null 2>&1`, so a
  # failure told you THAT green-on-clone broke but never WHICH control. Assert the name reaches the output.
  _out=$(run_aggregate "$t/red" 2>&1 || true)
  if printf '%s' "$_out" | grep -q 'planted-regression'; then
    echo "PASS: the failing control is NAMED in the output (no longer swallowed by >/dev/null)"
  else
    echo "FAIL: the failing control was not named — the failure is still opaque"; st=1
  fi

  # ── ADOPTER-GATES-INERT (A2/A3) census legs — proves the FOLD-IN WIRING (census_verdict, and the
  #    check()-level `|| _rc=1` that consumes it), never a replica of adopter-census.sh's own parse
  #    (that is separately proven by adopter-census.sh --selftest). Cheap: no real export, no real
  #    ~14-min battery — a fixture verify.sh carrying a minimal, faithful check()/line() grammar clone
  #    (the --kitself/--adopter latch + the self-declared-N/A idiom), run for real, fed through the REAL
  #    census_verdict seam.
  _census_fixture() {  # <dir> <extra-check-line>
    mkdir -p "$1/conformance"
    cat > "$1/conformance/verify.sh" <<'EOF'
#!/bin/sh
set -eu
cd "$(dirname "$0")/.." 2>/dev/null || true
check() {
  kind=$1; name=$2; shift 2
  if [ "${1:-}" = "--kitself" ]; then
    shift
    if [ ! -f docs/ROADMAP-KIT.md ] && [ ! -f .github/workflows/golden-path.yml ]; then
      printf '  [%s] %-18s %s\n' "$kind" "$name" "N-A"; return 0
    fi
  elif [ "${1:-}" = "--adopter" ]; then
    shift
  fi
  if out=$("$@" 2>&1); then rc=0; else rc=$?; fi
  case "$out" in
    N/A*|N-A*) printf '  [%s] %-18s %s\n' "$kind" "$name" "N-A"; return 0 ;;
  esac
  if [ "$rc" = 0 ]; then printf '  [%s] %-18s %s\n' "$kind" "$name" "PASS"
  else printf '  [%s] %-18s %s\n' "$kind" "$name" "FAIL"
  fi
}
check control baseline true
EOF
    printf '%s\n' "$2" >> "$1/conformance/verify.sh"
  }

  # VACUOUS — a control row that N/As with NO classification flag. verify.sh itself still exits 0 (N/A
  # rows never block a local run), so run_aggregate alone would pass; census_verdict must catch the
  # vacuity, and the check()-level `|| _rc=1` must make green-on-clone go RED overall.
  d="$t/census-vacuous"
  _census_fixture "$d" 'check control vacuousrow sh -c "echo N/A: unflagged skip; exit 0"'
  if _cv1_out=$( (cd "$d" && sh conformance/verify.sh) 2>&1 ); then :; else :; fi
  if census_verdict "$d" "$_cv1_out" >/dev/null 2>&1; then
    echo "FAIL: census leg — a planted unclassified vacuous control row did not red census_verdict"; st=1
  else
    echo "PASS: census leg — a planted unclassified vacuous control row reds census_verdict"
  fi

  # CLEAN — the identical row registered --kitself: census_verdict must stay green.
  d="$t/census-clean"
  _census_fixture "$d" 'check control vacuousrow --kitself sh -c "echo N/A: classified skip; exit 0"'
  if _cv2_out=$( (cd "$d" && sh conformance/verify.sh) 2>&1 ); then :; else :; fi
  if census_verdict "$d" "$_cv2_out" >/dev/null 2>&1; then
    echo "PASS: census leg — the same row registered --kitself keeps census_verdict clean"
  else
    echo "FAIL: census leg — a classified N/A row still reds census_verdict"; st=1
  fi

  # VISIBILITY — the violating name must reach the output, the same discipline as the aggregate's own
  # VISIBILITY leg above. Deliberately re-uses the VACUOUS dir + its OWN output (not the clean one) —
  # census_verdict reads its registry from the tree it is HANDED, so a mismatched pairing would silently
  # pass and this leg would prove nothing.
  _cv3=$(census_verdict "$t/census-vacuous" "$_cv1_out" 2>&1 || true)
  if printf '%s' "$_cv3" | grep -q 'vacuousrow'; then
    echo "PASS: census leg — the vacuous row's name is NAMED in census_verdict's output"
  else
    echo "FAIL: census leg — the vacuous row was not named — the failure is opaque"; st=1
  fi

  # ROW-TIMES legs (SWAS-372) — report_times: a row >10% warns; a total >1.3 x 2300 s warns with the top 3; a normal
  # file is silent; a missing file prints the note; and the exit is ALWAYS 0 (run in a subshell with `|| _rc=$?`).
  printf 'big\t200\tPASS\nsmall1\t10\tPASS\nsmall2\t10\tPASS\n' > "$t/rt-big"          # total 220, big = 91%
  _ro=$(report_times "$t/rt-big"); _rc=0; report_times "$t/rt-big" >/dev/null || _rc=$?
  if printf '%s\n' "$_ro" | grep -q '^::warning title=row-time::big took 200 s, >10% of the aggregate 220 s$' \
     && ! printf '%s\n' "$_ro" | grep -q 'over 1.3 x' && [ "$_rc" = 0 ]; then
    echo "PASS: row-times leg — a row over 10% warns (and the small total does not trip the 1.3x warning)"
  else echo "FAIL: row-times leg — the >10% row warning is wrong: $_ro"; st=1; fi
  : > "$t/rt-slow"; _i=0
  while [ "$_i" -lt 40 ]; do
    if [ "$_i" -lt 3 ]; then _s=400; else _s=70; fi
    printf 'r%s\t%s\tPASS\n' "$_i" "$_s" >> "$t/rt-slow"; _i=$((_i+1))
  done   # total 3*400+37*70 = 3790
  _ro=$(report_times "$t/rt-slow"); _rc=0; report_times "$t/rt-slow" >/dev/null || _rc=$?
  if printf '%s\n' "$_ro" | grep -q '^::warning title=row-time::aggregate 3790 s is over 1.3 x 2300 s; top 3 rows: ' \
     && [ "$(printf '%s\n' "$_ro" | grep '^::warning title=row-time::aggregate' | tr ',' '\n' | grep -c ' s)')" = 3 ] && [ "$_rc" = 0 ]; then
    echo "PASS: row-times leg — a total over 1.3x warns once, naming exactly the top 3 rows"
  else echo "FAIL: row-times leg — the total warning is wrong: $_ro"; st=1; fi
  : > "$t/rt-ok"; _i=0
  while [ "$_i" -lt 30 ]; do printf 'n%s\t%s\tPASS\n' "$_i" 60 >> "$t/rt-ok"; _i=$((_i+1)); done   # total 1800, each row 3.3%
  _ro=$(report_times "$t/rt-ok"); _rc=0; report_times "$t/rt-ok" >/dev/null || _rc=$?
  if ! printf '%s\n' "$_ro" | grep -q '^::warning' && [ "$_rc" = 0 ]; then
    echo "PASS: row-times leg — a normal file is silent (no warning)"
  else echo "FAIL: row-times leg — a normal file warned: $_ro"; st=1; fi
  # a hostile row name (a planted annotation, a triple backtick) must come out neutralised in BOTH the table and the warnings
  printf '::warning title=x::pwn\t300\tPASS\n```\t300\tPASS\nok\t10\tPASS\n' > "$t/rt-evil"
  _ro=$(report_times "$t/rt-evil"); _rc=0; report_times "$t/rt-evil" >/dev/null || _rc=$?
  if ! printf '%s\n' "$_ro" | grep -q '^::warning title=x' && ! printf '%s\n' "$_ro" | grep -q '```' \
     && printf '%s\n' "$_ro" | grep -q '^::warning title=row-time::[?][?]warning' && [ "$_rc" = 0 ]; then
    echo "PASS: row-times leg — a planted ::warning / triple-backtick row name is neutralised (table and annotations)"
  else echo "FAIL: row-times leg — a hostile row name reached the output unsanitised: $_ro"; st=1; fi
  _ro=$(report_times "$t/no-such-file"); _rc=0; report_times "$t/no-such-file" >/dev/null || _rc=$?
  if [ "$_ro" = "row-times: not produced" ] && [ "$_rc" = 0 ]; then
    echo "PASS: row-times leg — a missing file prints the note and exits 0"
  else echo "FAIL: row-times leg — missing-file behaviour wrong (rc=$_rc): $_ro"; st=1; fi

  # ── ROW-SHARD LEG/JOIN legs (SWAS-393; controls C7, C8) ─────────────────────────────────────────────────────────────────
  # The legs and the join are driven with the REAL functions over a fixture export: prep_export is replaced, for the rest of this
  # selftest, by a tiny committed tree whose verify.sh and agent-autonomy.sh are stubs that record their arguments in $t (the stubs
  # are the only fixture; the committing is the real commit_tree). C7: every leg's commit must be the SAME commit, so the commit uses
  # fixed dates (the mutant strips them and a second's wait then separates two commits of one tree).
  _gx_self="$ROOT/conformance/green-on-clone.sh"
  _gx_mut() {  # <function> <tag> <sed-expr> : the function's text with the tagged line edited; rc 1 when nothing changed
    _gm_o=$(sed -n "/^$1() {\$/,/^}\$/p" "$_gx_self")
    _gm_m=$(printf '%s\n' "$_gm_o" | sed "/# MG:$2\$/{$3;}")
    if [ -z "$_gm_o" ] || [ "$_gm_o" = "$_gm_m" ]; then return 1; fi
    printf '%s\n' "$_gm_m"
  }
  _gx_a="$t/dc-a"; _gx_b="$t/dc-b"; mkdir "$_gx_a" "$_gx_b"; printf 'same\n' > "$_gx_a/f"; printf 'same\n' > "$_gx_b/f"
  commit_tree "$_gx_a"; sleep 1; commit_tree "$_gx_b"
  if [ -n "$(git -C "$_gx_a" rev-parse HEAD 2>/dev/null)" ] && [ "$(git -C "$_gx_a" rev-parse HEAD)" = "$(git -C "$_gx_b" rev-parse HEAD)" ]; then
    echo "PASS: C7 leg — two commits of one tree, a second apart, are the SAME commit (every leg's record matches the join's head)"
  else echo "FAIL: C7 leg — two commits of one tree differ: the legs' records would never match the join's commit"; st=1; fi
  _gx_m=$(_gx_mut commit_tree dates 's/GIT_AUTHOR_DATE="[^"]*" //;s/GIT_COMMITTER_DATE="[^"]*" //') || _gx_m=""
  if [ -z "$_gx_m" ]; then echo "FAIL: C7 leg — no mutant: commit_tree has no line tagged MG:dates"; st=1
  else
    _gx_c="$t/dc-c"; _gx_d="$t/dc-d"; mkdir "$_gx_c" "$_gx_d"; printf 'same\n' > "$_gx_c/f"; printf 'same\n' > "$_gx_d/f"
    ( eval "$_gx_m"; commit_tree "$_gx_c"; sleep 1; commit_tree "$_gx_d" )
    if [ "$(git -C "$_gx_c" rev-parse HEAD)" = "$(git -C "$_gx_d" rev-parse HEAD)" ]; then echo "FAIL: C7 leg — the MUTANT (commit_tree without fixed dates) still gave one commit: the leg does not prove the dates"; st=1
    else echo "PASS: C7 leg — a commit without fixed dates differs after a second (the dates are load-bearing)"; fi
  fi
  prep_export() {  # <profile> : fixture export in $t/fx.*, committed by the real commit_tree; sets EXPORT_DIR
    EXPORT_DIR=$(mktemp -d "$t/fx.XXXXXX")
    mkdir -p "$EXPORT_DIR/conformance"
    printf '%s\n' '#!/bin/sh' 'set -eu' 'cd "$(dirname "$0")/.."' 'echo "$*" > ../verify-args' 'if [ -f ../verify-rc ]; then exit "$(cat ../verify-rc)"; fi' \
      'check() { printf "  [%s] %-18s %s\n" "$1" "$2" PASS; }' 'check control baseline' 'echo "RESULT: OK"' > "$EXPORT_DIR/conformance/verify.sh"
    printf '%s\n' '#!/bin/sh' 'if [ "$1" = --dims ]; then cat ../dims; exit 0; fi' 'echo "$*" > ../aa-args' 'exit 0' > "$EXPORT_DIR/conformance/agent-autonomy.sh"
    commit_tree "$EXPORT_DIR"
  }
  mkdir "$t/legs"; printf 'case0-tmp1-git1-uid00\n' > "$t/dims"; rm -f "$t/verify-rc" "$t/verify-args" "$t/aa-args"
  _gx_ok=1
  ( cd "$t/legs" && leg_rows 2/4 r2.rec >/dev/null 2>&1 ) || _gx_ok=0
  if [ "$_gx_ok" = 1 ] && [ "$(cat "$t/verify-args" 2>/dev/null)" = "--require --shard 2/4 --output-file $t/legs/r2.rec --timing-file $t/legs/r2.rec.timing" ]; then
    echo "PASS: row leg — verify.sh runs --require --shard i/N with an absolute --output-file and its .timing sidecar, on the export"
  else echo "FAIL: row leg — verify.sh was not run as '--require --shard 2/4 --output-file <abs> --timing-file <abs>.timing' (got: $(cat "$t/verify-args" 2>/dev/null))"; st=1; fi
  printf '3\n' > "$t/verify-rc"; _gx_rc=0; ( cd "$t/legs" && leg_rows 1/4 r1.rec >/dev/null 2>&1 ) || _gx_rc=$?
  if [ "$_gx_rc" = 3 ]; then echo "PASS: row leg — the shard's exit status is the leg's"; else echo "FAIL: row leg — verify's rc 3 became $_gx_rc"; st=1; fi
  rm -f "$t/verify-rc"
  _gx_ok=1; ( leg_battery 5/6 "$t/legs/b5.rec" >/dev/null 2>&1 ) || _gx_ok=0
  if [ "$_gx_ok" = 1 ] && [ "$(cat "$t/aa-args" 2>/dev/null)" = "--shard 5/6 --output-file $t/legs/b5.rec" ]; then
    echo "PASS: battery leg — agent-autonomy.sh runs --shard j/M --output-file on the export"
  else echo "FAIL: battery leg — agent-autonomy.sh was not run as '--shard 5/6 --output-file <record>' (got: $(cat "$t/aa-args" 2>/dev/null))"; st=1; fi
  printf 'case0-tmp0-git1-uid00\n' > "$t/dims"; rm -f "$t/aa-args"; _gx_rc=0
  ( leg_battery 5/6 "$t/legs/b5x.rec" >/dev/null 2>&1 ) || _gx_rc=$?
  if [ "$_gx_rc" != 0 ] && [ ! -f "$t/aa-args" ]; then echo "PASS: battery leg — an export that is not under a temp root (dims tmp0) is refused before any shard runs"
  else echo "FAIL: battery leg — a tmp0 export was accepted (rc=$_gx_rc): its record could not join the tmp1 battery the serial mode graded"; st=1; fi
  _gx_m=$(_gx_mut leg_battery dims 's/echo /: /;s/_cleanup "[^"]*"; //;s/return 1/:/') || _gx_m=""
  if [ -z "$_gx_m" ]; then echo "FAIL: battery leg — no mutant: leg_battery has no line tagged MG:dims"; st=1
  else
    rm -f "$t/aa-args"
    ( eval "$_gx_m"; leg_battery 5/6 "$t/legs/b5y.rec" >/dev/null 2>&1 ) || true
    if [ -f "$t/aa-args" ]; then echo "PASS: battery leg — without the dims guard the tmp0 export runs its shard (the guard is load-bearing)"
    else echo "FAIL: battery leg — the MUTANT (no dims guard) still refused the tmp0 export: the leg does not prove the guard"; st=1; fi
  fi
  printf 'case0-tmp1-git1-uid00\n' > "$t/dims"
  # the join: a fixture whose verify.sh logs its arguments and then answers in the census grammar, so the REAL census_verdict runs
  mkdir "$t/jrows" "$t/jbat"; : > "$t/jrows/a.rec"; : > "$t/jrows/b.rec"; : > "$t/jrows/a.rec.timing"; : > "$t/jbat/x.rec"
  prep_export() {
    EXPORT_DIR=$(mktemp -d "$t/fx.XXXXXX")
    _census_fixture "$EXPORT_DIR" ''
    { printf '%s\n' '#!/bin/sh' 'echo "$*" > "$(dirname "$0")/../../verify-args"'; sed 1d "$EXPORT_DIR/conformance/verify.sh"; } > "$EXPORT_DIR/v.new"
    mv "$EXPORT_DIR/v.new" "$EXPORT_DIR/conformance/verify.sh"
    commit_tree "$EXPORT_DIR"
  }
  rm -f "$t/verify-args"; _gx_rc=0
  join_aggregate "$t/jrows" "$t/jbat" >"$t/join.out" 2>&1 || _gx_rc=$?
  if [ "$_gx_rc" = 0 ] && [ "$(cat "$t/verify-args" 2>/dev/null)" = "--merge --battery $t/jbat $t/jrows/a.rec $t/jrows/b.rec" ] && grep -q '^OK: green-on-clone' "$t/join.out"; then
    echo "PASS: join — verify.sh --merge --battery <dir> <the row records, *.rec only> on a fresh export, then the census"
  else echo "FAIL: join — wrong verify.sh arguments or verdict (rc=$_gx_rc; got: $(cat "$t/verify-args" 2>/dev/null))"; st=1; fi
  # a join that is told where to put the timing file passes it on, after the records
  TIMING_FILE="$t/join.times"; rm -f "$t/verify-args"; join_aggregate "$t/jrows" "$t/jbat" >/dev/null 2>&1 || true; TIMING_FILE=""
  if [ "$(cat "$t/verify-args" 2>/dev/null)" = "--merge --battery $t/jbat $t/jrows/a.rec $t/jrows/b.rec --timing-file $t/join.times" ]; then
    echo "PASS: join — --timing-file is passed to the merge (it concatenates the shards' sidecars)"
  else echo "FAIL: join — the timing file was not passed to --merge (got: $(cat "$t/verify-args" 2>/dev/null))"; st=1; fi
  # and the census still reds the join: the merged output is censused like a serial run's
  prep_export() {
    EXPORT_DIR=$(mktemp -d "$t/fx.XXXXXX")
    _census_fixture "$EXPORT_DIR" 'check control vacuousrow sh -c "echo N/A: unflagged skip; exit 0"'
    { printf '%s\n' '#!/bin/sh' 'echo "$*" > "$(dirname "$0")/../../verify-args"'; sed 1d "$EXPORT_DIR/conformance/verify.sh"; } > "$EXPORT_DIR/v.new"
    mv "$EXPORT_DIR/v.new" "$EXPORT_DIR/conformance/verify.sh"
    commit_tree "$EXPORT_DIR"
  }
  _gx_rc=0; join_aggregate "$t/jrows" "$t/jbat" >/dev/null 2>&1 || _gx_rc=$?
  if [ "$_gx_rc" != 0 ]; then echo "PASS: join — a planted unclassified vacuous control row on the merged output reds the join (C8: the census still grades it)"
  else echo "FAIL: join — a vacuous control row passed the join: the census is not applied to the merged output"; st=1; fi
  # the argument grammar: parse_modes is PURE and is driven directly (never by running the script on a bad line), so a wrongly accepted
  # line cannot start a real export. Malformed lines are refused with 2; well-formed ones are accepted.
  for _gx_args in "--leg-rows 1/4" "--leg-rows 1/4 --output-file" "--leg-battery --output-file x" "--leg-rows 0/4 --output-file x" "--join --rows $t/jrows" "--join --battery $t/jbat" "--join --rows a --battery b --timing-file" "--leg-rows 1/4 --output-file x extra"; do
    _gx_rc=0; ( parse_modes $_gx_args ) >/dev/null 2>&1 || _gx_rc=$?
    if [ "$_gx_rc" = 2 ]; then echo "PASS: usage — '$_gx_args' is refused with exit 2, before any export"
    else echo "FAIL: usage — '$_gx_args' was not refused (rc=$_gx_rc)"; st=1; fi
  done
  for _gx_args in "--leg-rows 1/4 --output-file x" "--leg-battery 6/6 --output-file x" "--join --rows a --battery b" "--join --rows a --battery b --timing-file t"; do
    _gx_rc=0; ( parse_modes $_gx_args ) >/dev/null 2>&1 || _gx_rc=$?
    if [ "$_gx_rc" = 0 ]; then echo "PASS: usage — '$_gx_args' is accepted"; else echo "FAIL: usage — the well-formed '$_gx_args' was refused (rc=$_gx_rc)"; st=1; fi
  done
  _gx_m=$(_gx_mut parse_modes usage 's/echo /: /;s/return 2/:/') || _gx_m=""
  if [ -z "$_gx_m" ]; then echo "FAIL: usage — no mutant: parse_modes has no line tagged MG:usage"; st=1
  else
    _gx_rc=0; ( eval "$_gx_m"; parse_modes --leg-rows 1/4 --output-file x extra ) >/dev/null 2>&1 || _gx_rc=$?
    if [ "$_gx_rc" = 0 ]; then echo "PASS: usage — without the word-count refusal an extra word is accepted (the line is load-bearing)"
    else echo "FAIL: usage — the MUTANT (no word-count refusal) still refused an extra word: the leg does not prove the line"; st=1; fi
  fi

  rm -rf "$t" 2>/dev/null || true
  [ "$st" = 0 ] && echo "green-on-clone --selftest: OK" || { echo "green-on-clone --selftest: FAIL" >&2; return 1; }
  return "$st"
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  --report-times) report_times "${2:-}"; exit 0 ;;
  --timing-file)
    if [ -z "${2:-}" ]; then echo "green-on-clone: usage error — --timing-file needs a path" >&2; exit 2; fi
    case "$2" in /*) TIMING_FILE=$2 ;; *) TIMING_FILE="$(pwd)/$2" ;; esac ;;
  --leg-rows|--leg-battery|--join) parse_modes "$@" || exit 2 ;;
esac

# Kit-repo detector (C1 / R3) — IDENTICAL to adopter-export-wired.sh's, and load-bearing for RECURSION:
# this check exports the kit and runs the aggregate inside the export. The exported tree's own copy of
# this script must N/A-skip, or it would export itself forever. OR-of-markers is fail-closed:
# golden-path.yml is control-plane + export-ignored (un-spoofable), so deleting only the unprotected
# ROADMAP-KIT.md marker cannot make the kit skip its own check. N/A only when BOTH are absent.
if [ ! -f "$ROOT/docs/ROADMAP-KIT.md" ] && [ ! -f "$ROOT/.github/workflows/golden-path.yml" ]; then
  echo "green-on-clone: N/A — kit-self check (not applicable outside the kit repo)"; exit 0
fi

case "$LEG_MODE" in
  --leg-rows) leg_rows "$LEG_SPEC" "$LEG_REC"; exit $? ;;
  --leg-battery) leg_battery "$LEG_SPEC" "$LEG_REC"; exit $? ;;
  --join) join_aggregate "$JOIN_ROWS" "$JOIN_BAT"; exit $? ;;
esac
check typescript-node
