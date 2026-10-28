#!/bin/sh
# non-vacuity-wired.sh — the WIRING LOCK for the sharded non-vacuity sweep (P1-CI).
#
# WHY THIS EXISTS. Sharding a governance gate introduces a failure mode that sharding a test suite does
# not: a leg that never runs is INVISIBLE. non-vacuity.sh itself guarantees a lot — each leg enforces a
# strict subset, an empty leg FAILS, and legs 1..n provably partition the control set (F5/F5b). But every
# one of those guarantees is scoped to a leg that ACTUALLY RUNS. Nothing inside the script can know how
# many legs CI chose to launch.
#
# So the hole is in the workflow, not the script:
#
#     run: sh conformance/non-vacuity.sh --shard ${{ matrix.shard }}/4
#     matrix: { shard: [1, 2, 3] }        # <-- 4 declared, 3 launched
#
# Every launched leg passes. The pipeline is GREEN. And one quarter of the control set was mutation-tested
# by NOBODY — silently, forever. That is precisely the vacuity non-vacuity.sh exists to detect, smuggled
# back in through the mechanism meant to speed it up.
#
# This check closes it: the DENOMINATOR in the --shard argument must equal the COUNT of the matrix legs,
# and the legs must be exactly 1..n with no gaps and no duplicates.
#
# Changes: nothing. Reads .github/workflows/ci.yml. Guardrails: none needed (read-only).
set -eu
cd "$(dirname "$0")/.." 2>/dev/null || true

CI_WF="${NV_WIRED_WF:-.github/workflows/ci.yml}"

# ── _matrix_legs <workflow> : the integers of the `shard: [...]` matrix of the job that carries the non-vacuity invocation.
_matrix_legs() {
  # A job block runs from a job-key header to the next one; the block holding the (unsuppressed) invocation owns the matrix. The job-key indent is
  # read from the first key line after `jobs:` (not assumed), a header may carry a trailing comment, and a file with NO header prints NOJOBS (fail closed).
  grep -vE '^[[:space:]]*#' "$1" | awk '
    function flush() { if (inv && !done) { done = 1; print legs; exit } legs = ""; inv = 0 }
    /^jobs:[ \t]*(#.*)?$/ { injobs = 1; next }
    injobs && !ji && /^ +[A-Za-z0-9_-]+:[ \t]*(#.*)?$/ { match($0, /^ +/); ji = RLENGTH }
    ji && /^ +[A-Za-z0-9_-]+:[ \t]*(#.*)?$/ { match($0, /^ +/); if (RLENGTH == ji) { nhdr++; flush() } }
    /^[ \t]*shard:[ \t]*\[/ && legs == "" { legs = $0 }
    /non-vacuity\.sh[ \t]+--shard/ && !/\|\| true/ { inv = 1 }
    END { if (!done) { if (inv && !nhdr) { print "NOJOBS"; exit } flush() } }' | sed 's/.*\[//; s/\].*//; s/,/ /g'
}

# ── assert_wired <workflow> : 0 iff the sharded sweep is completely wired.
assert_wired() {
  _wf=$1
  [ -f "$_wf" ] || { echo "FAIL: $_wf not found" >&2; return 1; }

  # The --shard invocation, ignoring comments. Extract the DENOMINATOR (the /n).
  _inv=$(grep -vE '^[[:space:]]*#' "$_wf" \
         | grep -E 'non-vacuity\.sh[[:space:]]+--shard' \
         | grep -v '|| true' || true)
  if [ -z "$_inv" ]; then
    echo "FAIL: $_wf never invokes 'non-vacuity.sh --shard <i>/<n>' — the sweep is not wired sharded" >&2
    return 1
  fi
  _n=$(printf '%s\n' "$_inv" | grep -oE '/[0-9]+' | head -1 | tr -d '/')
  if [ -z "$_n" ] || [ "$_n" -lt 1 ] 2>/dev/null; then
    echo "FAIL: could not read a positive shard denominator from: $_inv" >&2
    return 1
  fi

  # The matrix legs. `shard: [1, 2, 3, 4]` -> the integers.
  _legs=$(_matrix_legs "$_wf")
  if [ "$_legs" = NOJOBS ]; then
    echo "FAIL: $_wf declares --shard <i>/$_n but no job header was found under 'jobs:' — the matrix cannot be tied to the job that runs the sweep" >&2
    return 1
  fi
  if [ -z "$_legs" ]; then
    echo "FAIL: $_wf declares --shard <i>/$_n but has no 'shard: [...]' matrix — how many legs actually run?" >&2
    return 1
  fi

  # THE LOCK: the legs must be exactly 1..n. Sorted-unique, compared against the expected sequence.
  _got=$(printf '%s\n' $_legs | sort -n -u | tr '\n' ' ' | sed 's/ *$//')
  _want=$(_i=1; while [ "$_i" -le "$_n" ]; do printf '%s ' "$_i"; _i=$((_i + 1)); done | sed 's/ *$//')
  if [ "$_got" != "$_want" ]; then
    echo "FAIL: the matrix runs legs [$_got] but the sweep is invoked as --shard <i>/$_n (expected legs [$_want])." >&2
    echo "      A declared-but-unlaunched leg means part of the control set is mutation-tested by NOBODY," >&2
    echo "      while CI still reports GREEN. Make the matrix and the denominator agree." >&2
    return 1
  fi

  echo "OK: non-vacuity is sharded /$_n and the matrix launches exactly legs [$_got] — no leg goes untested."
  return 0
}

# ── selftest : the lock must be LOAD-BEARING. A wiring lock that passes on a broken wiring is worse
#    than no lock, because it certifies the hole. Every negative below is the real defect it must catch.
selftest() {
  st=0; d=$(mktemp -d)
  _mk() { if [ "${2#jobs:}" != "$2" ]; then printf '%s\n' "$2"; else printf 'jobs:\n  j:\n%s\n' "$2"; fi > "$d/$1"; }   # a bare snippet is wrapped in one job

  # GOOD — denominator 4, legs 1..4.
  _mk ok.yml '        shard: [1, 2, 3, 4]
        run: sh conformance/non-vacuity.sh --shard ${{ matrix.shard }}/4'
  if NV_WIRED_WF="$d/ok.yml" assert_wired "$d/ok.yml" >/dev/null 2>&1; then
    echo "PASS: a fully-wired 4-leg matrix is accepted"
  else echo "FAIL: rejected a correct wiring"; st=1; fi

  # THE DEFECT — 4 declared, 3 launched. A quarter of the gate tested by nobody, CI green.
  _mk gap.yml '        shard: [1, 2, 3]
        run: sh conformance/non-vacuity.sh --shard ${{ matrix.shard }}/4'
  if NV_WIRED_WF="$d/gap.yml" assert_wired "$d/gap.yml" >/dev/null 2>&1; then
    echo "FAIL: accepted a matrix that launches 3 of 4 declared legs — a silent hole in the gate"; st=1
  else echo "PASS: 4 declared / 3 launched -> FAIL (no leg may go untested)"; fi

  # A GAP in the middle — legs 1,2,4 of 4. Shard 3's checks tested by nobody.
  _mk hole.yml '        shard: [1, 2, 4]
        run: sh conformance/non-vacuity.sh --shard ${{ matrix.shard }}/4'
  if NV_WIRED_WF="$d/hole.yml" assert_wired "$d/hole.yml" >/dev/null 2>&1; then
    echo "FAIL: accepted legs [1 2 4] of 4 — shard 3 is never launched"; st=1
  else echo "PASS: a gap in the leg sequence -> FAIL"; fi

  # UNSHARDED — the sweep silently reverted to a full run with a matrix still present.
  _mk bare.yml '        shard: [1, 2, 3, 4]
        run: sh conformance/non-vacuity.sh'
  if NV_WIRED_WF="$d/bare.yml" assert_wired "$d/bare.yml" >/dev/null 2>&1; then
    echo "FAIL: accepted a workflow with no --shard invocation"; st=1
  else echo "PASS: a missing --shard invocation -> FAIL"; fi

  # SUPPRESSED — `|| true` neuters the gate. The classic way to make a check cosmetic.
  _mk supp.yml '        shard: [1, 2, 3, 4]
        run: sh conformance/non-vacuity.sh --shard ${{ matrix.shard }}/4 || true'
  if NV_WIRED_WF="$d/supp.yml" assert_wired "$d/supp.yml" >/dev/null 2>&1; then
    echo "FAIL: accepted a '|| true'-suppressed sweep (a gate that cannot fail)"; st=1
  else echo "PASS: a '|| true'-suppressed sweep -> FAIL"; fi

  # ANOTHER JOB'S MATRIX EARLIER IN THE FILE (the S3 shape: cf-verify-enforced-shard `shard: [1, 2]` sits above the sweep's own job). The lock
  # reads the matrix of the job that carries the non-vacuity invocation, so a neighbour's `shard:` cannot be mistaken for it.
  _mk other.yml 'jobs:
  other-job:
    strategy:
      matrix:
        shard: [1, 2]
    steps:
      - run: sh conformance/verify.sh --shard ${{ matrix.shard }}/2
  nv-job:
    strategy:
      matrix:
        shard: [1, 2, 3, 4]
    steps:
      - run: sh conformance/non-vacuity.sh --shard ${{ matrix.shard }}/4'
  if NV_WIRED_WF="$d/other.yml" assert_wired "$d/other.yml" >/dev/null 2>&1; then
    echo "PASS: another job's earlier shard matrix [1 2] does not shadow the sweep's own [1 2 3 4]"
  else echo "FAIL: another job's earlier shard matrix was read as the sweep's"; st=1; fi
  # ...and the sweep's OWN matrix disagreeing with its denominator still reds when another job's matrix precedes it.
  _mk othergap.yml 'jobs:
  other-job:
    strategy:
      matrix:
        shard: [1, 2]
    steps:
      - run: sh conformance/verify.sh --shard ${{ matrix.shard }}/2
  nv-job:
    strategy:
      matrix:
        shard: [1, 2]
    steps:
      - run: sh conformance/non-vacuity.sh --shard ${{ matrix.shard }}/4'
  if NV_WIRED_WF="$d/othergap.yml" assert_wired "$d/othergap.yml" >/dev/null 2>&1; then
    echo "FAIL: accepted the sweep's own matrix [1 2] against /4 because another job's [1 2] preceded it"; st=1
  else echo "PASS: the sweep's own matrix [1 2] against /4 -> FAIL even with another job's matrix earlier"; fi
  # MUTANT: the unscoped reader (first `shard:` in the file) must be SEEN by the other-job cell, or that cell is vacuous.
  if ( _matrix_legs() { grep -vE '^[[:space:]]*#' "$1" | grep -E '^[[:space:]]*shard:[[:space:]]*\[' | head -1 | sed 's/.*\[//; s/\].*//; s/,/ /g'; }
       NV_WIRED_WF="$d/other.yml" assert_wired "$d/other.yml" >/dev/null 2>&1 ); then
    echo "FAIL: MUTANT unscoped-first-matrix still accepts the other-job fixture, so that cell cannot see the bug"; st=1
  else echo "PASS: MUTANT unscoped-first-matrix reds the other-job fixture and is seen"; fi

  # JOB-HEADER SHAPES (F-A): a header with a trailing comment, or job keys indented by four, must still split blocks; a file with NO job header
  # fails closed (it would silently restore first-matrix-in-file). Each fixture puts a neighbour's [1 2 3 4] ABOVE the sweep's own [1 2 3] of /4.
  _mk cmt.yml 'jobs:
  other-job:
    strategy:
      matrix:
        shard: [1, 2, 3, 4]
    steps:
      - run: sh conformance/verify.sh --shard ${{ matrix.shard }}/4
  nv-job:  # the sweep
    strategy:
      matrix:
        shard: [1, 2, 3]
    steps:
      - run: sh conformance/non-vacuity.sh --shard ${{ matrix.shard }}/4'
  if NV_WIRED_WF="$d/cmt.yml" assert_wired "$d/cmt.yml" >/dev/null 2>&1; then
    echo "FAIL: a commented job header merged the blocks and the neighbour's [1 2 3 4] stood in for the sweep's [1 2 3]"; st=1
  else echo "PASS: a commented job header still splits blocks (the sweep's own [1 2 3] against /4 -> FAIL)"; fi
  _mk ind4.yml 'jobs:
    other-job:
      strategy:
        matrix:
          shard: [1, 2, 3, 4]
      steps:
        - run: sh conformance/verify.sh --shard ${{ matrix.shard }}/4
    nv-job:
      strategy:
        matrix:
          shard: [1, 2, 3]
      steps:
        - run: sh conformance/non-vacuity.sh --shard ${{ matrix.shard }}/4'
  if NV_WIRED_WF="$d/ind4.yml" assert_wired "$d/ind4.yml" >/dev/null 2>&1; then
    echo "FAIL: four-space job keys merged the blocks and the neighbour's [1 2 3 4] stood in for the sweep's [1 2 3]"; st=1
  else echo "PASS: four-space job keys still split blocks (the sweep's own [1 2 3] against /4 -> FAIL)"; fi
  _mk ind4ok.yml 'jobs:
    other-job:
      strategy:
        matrix:
          shard: [1, 2]
      steps:
        - run: sh conformance/verify.sh --shard ${{ matrix.shard }}/2
    nv-job:
      strategy:
        matrix:
          shard: [1, 2, 3, 4]
      steps:
        - run: sh conformance/non-vacuity.sh --shard ${{ matrix.shard }}/4'
  if NV_WIRED_WF="$d/ind4ok.yml" assert_wired "$d/ind4ok.yml" >/dev/null 2>&1; then
    echo "PASS: four-space job keys: the sweep's own [1 2 3 4] beside a neighbour's [1 2] is accepted"
  else echo "FAIL: four-space job keys: rejected a correct wiring"; st=1; fi
  printf '        shard: [1, 2, 3, 4]\n        run: sh conformance/non-vacuity.sh --shard ${{ matrix.shard }}/4\n' > "$d/nojobs.yml"
  if NV_WIRED_WF="$d/nojobs.yml" assert_wired "$d/nojobs.yml" >/dev/null 2>&1; then
    echo "FAIL: accepted a workflow with no job header at all (first-matrix-in-file behaviour restored silently)"; st=1
  else echo "PASS: no job header at all -> FAIL (fail closed)"; fi
  # F-B: the invocation's job declares NO `shard: [...]` matrix (none at all, or only an include: list) -> FAIL, never a pass.
  _mk nomat.yml 'jobs:
  nv-job:
    steps:
      - run: sh conformance/non-vacuity.sh --shard 1/4'
  _mk incl.yml 'jobs:
  nv-job:
    strategy:
      matrix:
        include:
          - shard: 1
    steps:
      - run: sh conformance/non-vacuity.sh --shard ${{ matrix.shard }}/4'
  if NV_WIRED_WF="$d/nomat.yml" assert_wired "$d/nomat.yml" >/dev/null 2>&1 || NV_WIRED_WF="$d/incl.yml" assert_wired "$d/incl.yml" >/dev/null 2>&1; then
    echo "FAIL: accepted an invocation whose job has no shard: [...] matrix (none, or include: only)"; st=1
  else echo "PASS: an invocation with no shard matrix in its job (none, or include: only) -> FAIL"; fi

  rm -rf "$d"
  [ "$st" = 0 ] && echo "non-vacuity-wired --selftest: OK" || { echo "non-vacuity-wired --selftest: FAIL" >&2; return 1; }
  return "$st"
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  "")         assert_wired "$CI_WF"; exit $? ;;
  *) echo "usage: non-vacuity-wired.sh [--selftest]" >&2; exit 2 ;;
esac
