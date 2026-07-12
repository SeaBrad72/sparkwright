#!/bin/sh
# Why this gate: sparkwright explain evals
# eval-harness-runs.sh -- kit-self BEHAVIORAL lock for the reference eval harness (KW24).
#
# The RUNTIME complement to the STRUCTURAL eval-harness-wired.sh: that sibling greps the
# reference harness for the eval-driven markers (a pluggable seam, pinned judge, independence,
# offline-by-default, injection defense) as CODE STRUCTURE. This lock actually EXECUTES the
# harness offline and asserts it behaves:
#   1. the harness's own behavioral test suite passes (profiles/ml/evals/test_run.py) -- this is
#      where threshold-fails-on-all-miss, fence-breakout-neutralization, and judge-independence
#      RUN, not just exist;
#   2. the quality suite runs and PASSES the threshold gate (evals.run --suite quality);
#   3. the red-team suite runs and reports PASS (structural injection resistance, offline);
#   4. the additive --trace cost/quality NDJSON emission produces a well-formed line
#      (the required keys), verifying the KW24 trace seam end-to-end.
#
# SCOPE -- a green run proves the reference harness EXECUTES end-to-end offline. It does NOT run
# a live model, prove any model meets a quality bar, or prove a LIVE judge resists every injection
# (that is the adopter's live run; the §7 Eval gate). Honest ceiling: executes + structurally
# resists; live-eval-quality + live-injection-resistance remain un-gateable here.
# Kit-self check: N/A outside the kit repo (no docs/ROADMAP-KIT.md and no reference run.py).
#
# Usage:
#   sh conformance/eval-harness-runs.sh            (main-path: execute the real reference harness)
#   sh conformance/eval-harness-runs.sh --selftest (fixture-driven anchor + load-bearing negative)
# Override the harness dir (for the selftest / a relocated profile) via EVAL_RUNS_DIR.
# Exit: 0 = OK or N/A -- 1 = FAIL (reference harness does not execute). POSIX sh; dash-clean.
set -eu

RUN_DIR="${EVAL_RUNS_DIR:-profiles/ml/evals}"

# The required NDJSON trace keys (kept in sync with run.py's _emit_trace / KW24 Part 2).
TRACE_KEYS='suite judge n_cases mean_score threshold pass elapsed_s judge_calls tokens est_cost_usd'

# Execute the harness in $1 through all four behavioral checks. Returns 0 = OK, 1 = FAIL.
check_runs() {
  rdir=$1

  # (1) the harness's own behavioral test suite -- the load-bearing runtime proof.
  if ! ( cd "$rdir" && python3 test_run.py ) >/dev/null 2>&1; then
    echo "FAIL: harness behavioral test suite (test_run.py) did not pass under $rdir"
    return 1
  fi

  # (2) quality suite executes and PASSES the threshold gate.
  q_out=$( cd "$rdir" && python3 run.py --suite quality --threshold 0.8 2>&1 ) || {
    echo "FAIL: quality suite did not exit 0 under $rdir"; return 1;
  }
  printf '%s\n' "$q_out" | grep -q 'eval: PASS' || {
    echo "FAIL: quality suite did not report 'eval: PASS' under $rdir"; return 1;
  }

  # (3) red-team suite executes and reports structural resistance PASS.
  rt_out=$( cd "$rdir" && python3 run.py --suite red-team 2>&1 ) || {
    echo "FAIL: red-team suite did not exit 0 under $rdir"; return 1;
  }
  printf '%s\n' "$rt_out" | grep -q 'red-team: PASS' || {
    echo "FAIL: red-team suite did not report 'red-team: PASS' under $rdir"; return 1;
  }

  # (4) the additive --trace emission produces a well-formed NDJSON line (KW24 Part 2).
  tf=$(mktemp "${TMPDIR:-/tmp}/eval-runs-trace.XXXXXX")
  if ! ( cd "$rdir" && python3 run.py --judge exact --threshold 0.8 --trace "$tf" ) >/dev/null 2>&1; then
    echo "FAIL: --trace run did not exit 0 under $rdir"; rm -f "$tf"; return 1
  fi
  TRACE_KEYS="$TRACE_KEYS" python3 - "$tf" <<'PYEOF' || { echo "FAIL: --trace line missing required keys under $rdir"; rm -f "$tf"; return 1; }
import json, os, sys
req = set(os.environ["TRACE_KEYS"].split())
lines = [l for l in open(sys.argv[1], encoding="utf-8").read().splitlines() if l.strip()]
assert lines, "no trace line emitted"
d = json.loads(lines[-1])
missing = req - set(d.keys())
assert not missing, "missing trace keys: %s" % sorted(missing)
PYEOF
  rm -f "$tf"

  return 0
}

# ---------------------------------------------------------------------------------------------
if [ "${1:-}" = "--selftest" ]; then
  d=$(mktemp -d "${TMPDIR:-/tmp}/eval-harness-runs.XXXXXX"); trap 'rm -rf "$d"' EXIT INT TERM
  st=0

  # Build a minimal-but-conformant fixture harness: a run.py with an INTACT threshold gate,
  # a golden set that passes, a red-team stub that reports PASS, a --trace emitter carrying
  # every required key, and a test_run.py whose all-miss test asserts the gate returns rc=1.
  build_fixture() {
    t=$1; mkdir -p "$t"
    cat > "$t/run.py" <<'PYR'
import argparse, json, sys, time


def load_cases(p):
    out = []
    with open(p, encoding="utf-8") as f:
        for ln in f:
            ln = ln.strip()
            if ln:
                out.append(json.loads(ln))
    return out


def _emit(a, cases, mean, passed, el):
    rec = {
        "suite": a.suite, "judge": a.judge, "n_cases": len(cases), "mean_score": mean,
        "threshold": a.threshold, "pass": bool(passed), "elapsed_s": el,
        "judge_calls": 0, "tokens": 0, "est_cost_usd": 0.0,
    }
    with open(a.trace, "a", encoding="utf-8") as f:
        f.write(json.dumps(rec) + "\n")


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--threshold", type=float, default=0.8)
    ap.add_argument("--suite", choices=["quality", "red-team"], default="quality")
    ap.add_argument("--data", default="golden.jsonl")
    ap.add_argument("--judge", default="exact")
    ap.add_argument("--trace", default=None)
    a = ap.parse_args(argv)
    data = "red-team.jsonl" if a.suite == "red-team" else a.data
    cases = load_cases(data)
    t0 = time.perf_counter()
    if a.suite == "red-team":
        if a.trace:
            _emit(a, cases, 0.0, True, time.perf_counter() - t0)
        print("red-team: PASS")
        return 0
    total = sum(
        1.0 if str(c.get("candidate", "")).strip().lower() == c["expected"].strip().lower() else 0.0
        for c in cases
    )
    mean = total / len(cases) if cases else 0.0
    if a.trace:
        _emit(a, cases, mean, mean >= a.threshold, time.perf_counter() - t0)
    print("eval: mean %.3f" % mean)
    if mean < a.threshold:
        print("eval: FAIL", file=sys.stderr)
        return 1
    print("eval: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PYR
    cat > "$t/test_run.py" <<'PYT'
import json, os, sys, tempfile, unittest
HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import run  # noqa: E402
GOLDEN = os.path.join(HERE, "golden.jsonl")


class FixtureGateTest(unittest.TestCase):
    def test_golden_passes(self):
        self.assertEqual(run.main(["--data", GOLDEN, "--threshold", "0.8"]), 0)

    def test_all_miss_fails_threshold(self):
        rows = [{"id": "m1", "input": "x", "candidate": "WRONG", "expected": "positive"}]
        with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False) as fh:
            for r in rows:
                fh.write(json.dumps(r) + "\n")
            p = fh.name
        try:
            self.assertEqual(run.main(["--data", p, "--threshold", "0.8"]), 1)
        finally:
            os.unlink(p)


if __name__ == "__main__":
    unittest.main()
PYT
    printf '%s\n' '{"id":"g1","input":"a","candidate":"positive","expected":"positive"}' > "$t/golden.jsonl"
    printf '%s\n' '{"id":"g2","input":"b","candidate":"negative","expected":"negative"}' >> "$t/golden.jsonl"
    printf '%s\n' '{"id":"x","input":"i","expected":"e","attack":"judge-injection","candidate":"c"}' > "$t/red-team.jsonl"
  }

  run_fixture() {  # echo the lock's exit code, pointed at fixture dir $1
    rc=0
    EVAL_RUNS_DIR="$1" sh "$0" >/dev/null 2>&1 || rc=$?
    echo "$rc"
  }
  expect() {  # <label> <expected-rc>
    got=$(run_fixture "$d/fx")
    if [ "$got" = "$2" ]; then echo "selftest PASS: $1"; else echo "selftest FAIL: $1 (expected $2, got $got)"; st=1; fi
  }
  fresh() { rm -rf "$d/fx"; build_fixture "$d/fx"; }

  # LIVENESS ANCHOR: a conformant fixture harness (intact threshold gate) -> the lock passes.
  fresh; expect "conformant fixture harness executes -> exit 0" 0

  # LOAD-BEARING NEGATIVE: neuter the threshold gate so an all-miss set no longer fails
  # (mean < a.threshold -> mean < -1.0, never true). The fixture's own test suite catches
  # the dead gate (all_miss test expects rc=1, now gets rc=0) -> the lock MUST RED.
  fresh
  sed 's/mean < a.threshold/mean < -1.0/' "$d/fx/run.py" > "$d/fx/run.py.t" && mv "$d/fx/run.py.t" "$d/fx/run.py"
  expect "neutered threshold gate (dead/always-green harness) -> exit 1" 1

  if [ "$st" -ne 0 ]; then echo "eval-harness-runs --selftest: FAIL" >&2; exit 1; fi
  echo "eval-harness-runs --selftest: OK (anchor + neutered-threshold negative)"
  exit 0
fi

case "${1:-}" in "") : ;; *) echo "usage: eval-harness-runs.sh [--selftest]" >&2; exit 2 ;; esac

# Kit-self scope: N/A outside the kit repo (no roadmap and no reference harness present).
if [ ! -f "docs/ROADMAP-KIT.md" ] && [ ! -f "$RUN_DIR/run.py" ]; then
  echo "eval-harness-runs: N/A -- kit-self check"
  exit 0
fi

# The harness is an offline PYTHON program; without an interpreter it cannot be executed.
if ! command -v python3 >/dev/null 2>&1; then
  echo "eval-harness-runs: N/A -- python3 unavailable (offline harness needs an interpreter; the structural lock still runs)"
  exit 0
fi

if check_runs "$RUN_DIR"; then
  echo "eval-harness-runs: OK -- reference harness executes end-to-end offline (test suite + quality + red-team + trace). NOTE: does NOT run a live model / prove a quality bar / prove live-injection resistance -- that is the adopter's §7 Eval gate."
  exit 0
fi
echo "FAIL: reference eval harness did not execute (see reasons above)"
exit 1
