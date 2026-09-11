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
set -eu
ROOT=$(CDPATH='' cd "$(dirname "$0")/.." && pwd)

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
  _t=$1
  echo "--- the adopter's own verify.sh --require, on the exported tree ---"
  if _ra_out=$( cd "$_t" && sh conformance/verify.sh --require 2>&1 ); then _ra_rc=0; else _ra_rc=$?; fi
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
commit_tree() {
  ( cd "$1" && git init -q && git add -A \
    && git -c gc.auto=0 -c user.email=ci@kit -c user.name=ci commit -qm export >/dev/null 2>&1 )
}

# check <profile> -> 0 green · 1 red.
check() {
  _prof=${1:-typescript-node}
  _d=$(mktemp -d)/export
  _rc=0

  if ! ( cd "$ROOT" && sh scripts/adopter-export.sh "$_d" --profile "$_prof" >/dev/null 2>&1 ); then
    echo "FAIL: green-on-clone — adopter-export itself failed; nothing to judge" >&2
    _cleanup "$_d"; return 1
  fi
  if ! commit_tree "$_d"; then
    echo "FAIL: green-on-clone — could not commit the exported tree" >&2
    _cleanup "$_d"; return 1
  fi

  run_aggregate "$_d" || _rc=1
  census_verdict "$_d" "$RUN_AGGREGATE_OUTPUT" || _rc=1
  _cleanup "$_d"
  return "$_rc"
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

  rm -rf "$t" 2>/dev/null || true
  [ "$st" = 0 ] && echo "green-on-clone --selftest: OK" || { echo "green-on-clone --selftest: FAIL" >&2; return 1; }
  return "$st"
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
esac

# Kit-repo detector (C1 / R3) — IDENTICAL to adopter-export-wired.sh's, and load-bearing for RECURSION:
# this check exports the kit and runs the aggregate inside the export. The exported tree's own copy of
# this script must N/A-skip, or it would export itself forever. OR-of-markers is fail-closed:
# golden-path.yml is control-plane + export-ignored (un-spoofable), so deleting only the unprotected
# ROADMAP-KIT.md marker cannot make the kit skip its own check. N/A only when BOTH are absent.
if [ ! -f "$ROOT/docs/ROADMAP-KIT.md" ] && [ ! -f "$ROOT/.github/workflows/golden-path.yml" ]; then
  echo "green-on-clone: N/A — kit-self check (not applicable outside the kit repo)"; exit 0
fi

check typescript-node
