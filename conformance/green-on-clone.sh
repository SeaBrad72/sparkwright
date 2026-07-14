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
run_aggregate() {
  _t=$1
  echo "--- the adopter's own verify.sh --require, on the exported tree ---"
  if ( cd "$_t" && sh conformance/verify.sh --require 2>&1 ); then
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
