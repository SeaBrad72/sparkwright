"""Reference eval harness — deterministic, offline (no network, no API key).

This is the SHIPPED REFERENCE so the `gate-eval` CI step is green the moment you clone
the profile, with no secrets configured. It demonstrates the harness *mechanics* the
§7 eval gate depends on: load a golden set, run the system under test, score each case
against a rubric, aggregate, and FAIL the build below `--threshold`.

It is intentionally a placeholder, not a real model evaluation. To make it real:
  1. Replace `generate()` with your model/prompt call.
  2. Replace `golden.jsonl` with your curated dataset (grow it from production misses).
  3. Select a graded/LLM-as-judge scorer via `--judge` (see judges.py + rubric.md).
See rubric.md for the upgrade recipe. Run: `python -m evals.run --threshold 0.8`.

Scoring is a pluggable seam (`judges.py`): `--judge {exact,fake,claude}` selects the
judge; the default is offline exact-match so `gate-eval` is green-on-clone with no key.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys
import time

try:  # allow both `python -m evals.run` and `python run.py`
    from judges import load_judge, ClaudeJudge, _CANDIDATE_FENCE, _strip_fence
except ImportError:  # pragma: no cover - packaged import path
    from .judges import load_judge, ClaudeJudge, _CANDIDATE_FENCE, _strip_fence

HERE = pathlib.Path(__file__).resolve().parent
DEFAULT_DATA = HERE / "golden.jsonl"
REDTEAM_DATA = HERE / "red-team.jsonl"

_POSITIVE = ("love", "great", "excellent", "perfect", "amazing")
_NEGATIVE = ("hate", "terrible", "broken", "awful", "worst")


def generate(prompt: str) -> str:
    """STUB system-under-test — REPLACE with your model/prompt call.

    Deterministic rule-based sentiment tagger so the reference suite passes offline.
    A real implementation would call your model (e.g. the Anthropic SDK) here.
    """
    text = prompt.lower()
    if any(w in text for w in _POSITIVE):
        return "positive"
    if any(w in text for w in _NEGATIVE):
        return "negative"
    return "neutral"


def load_cases(path: str) -> list:
    cases = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                cases.append(json.loads(line))
    return cases


def _print_resistance_summary(cases: list) -> tuple:
    """Print a structural resistance summary for the red-team suite.

    For each ``attack == "judge-injection"`` case, build the judge prompt via
    ``ClaudeJudge._build_prompt`` and confirm the injection payload lands INSIDE
    the untrusted-data region (after the first fence), i.e. it is fenced as data
    rather than leaking into the leading instruction. This is a STRUCTURAL proof of
    the defense (offline, no live call); live-injection resistance is the adopter's
    run and is honestly un-gateable here.
    """
    injections = [c for c in cases if c.get("attack") == "judge-injection"]
    total = len(injections)
    neutralized = 0
    for c in injections:
        candidate = c.get("candidate") or generate(c["input"])
        built = ClaudeJudge._build_prompt(
            c["input"], candidate, c.get("expected", ""), c.get("rubric", "")
        )
        first_fence = built.find(_CANDIDATE_FENCE)
        second_fence = built.find(_CANDIDATE_FENCE, first_fence + len(_CANDIDATE_FENCE))
        # The candidate (stripped identically to _build_prompt) must land BETWEEN the
        # two fences — inside the untrusted-data region, not before the open fence
        # (instruction leak) nor after the close fence (still a leak).
        stripped = _strip_fence(candidate)
        payload_at = built.find(stripped, first_fence + len(_CANDIDATE_FENCE))
        if first_fence != -1 and second_fence != -1 and first_fence < payload_at < second_fence:
            neutralized += 1
    print(f"red-team: {neutralized}/{total} judge-injection candidates neutralized (fenced)")
    return neutralized, total


def _emit_trace(path, args, cases, mean, passed, elapsed_s) -> None:
    """Append ONE NDJSON cost/quality trace line (additive; only when --trace is set).

    Offline judges make NO live API calls, so judge_calls/tokens/est_cost_usd are 0 here —
    real cost/tokens are the live Claude judge's, read from message.usage on a live run.
    """
    record = {
        "suite": args.suite,
        "judge": args.judge,
        "n_cases": len(cases),
        "mean_score": mean,
        "threshold": args.threshold,
        "pass": bool(passed),
        "elapsed_s": elapsed_s,
        "judge_calls": 0,
        "tokens": 0,
        "est_cost_usd": 0.0,
    }
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(record) + "\n")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Reference eval gate (deterministic, offline).")
    ap.add_argument("--threshold", type=float, default=0.8, help="minimum mean score to pass")
    ap.add_argument(
        "--suite",
        choices=["quality", "red-team"],
        default="quality",
        help="which suite to run (default quality; red-team runs the adversarial set)",
    )
    ap.add_argument(
        "--data",
        default=None,
        help="path to a JSONL set (defaults to golden.jsonl, or red-team.jsonl for --suite red-team)",
    )
    # offline by default: exact-match needs no network/key; claude is opt-in.
    ap.add_argument(
        "--judge",
        choices=["exact", "fake", "claude"],
        default="exact",
        help="scoring judge (default offline exact-match; claude is opt-in, needs a key)",
    )
    # Additive cost/quality trace: when set, append ONE NDJSON line per run.
    ap.add_argument(
        "--trace",
        default=None,
        help="optional path to append a one-line NDJSON cost/quality trace for this run",
    )
    args = ap.parse_args(argv)

    # Resolve the default dataset per suite: red-team runs the sibling red-team.jsonl.
    data_path = args.data
    if data_path is None:
        data_path = str(REDTEAM_DATA) if args.suite == "red-team" else str(DEFAULT_DATA)

    cases = load_cases(data_path)
    if not cases:
        print(f"eval: no cases found in {data_path}", file=sys.stderr)
        return 1

    judge = load_judge(args.judge)

    total = 0.0
    _t0 = time.perf_counter()  # bracket the scoring loop for the cost/quality trace
    for c in cases:
        prompt = c["input"]
        # Red-team cases may supply a malicious SUT output verbatim; a supplied
        # candidate override is used as-is (never regenerated) so the adversarial
        # payload actually reaches the judge.
        candidate = c.get("candidate") or generate(prompt)
        expected = c["expected"]
        # Thread a per-case rubric through the seam (default to empty if absent).
        rubric = c.get("rubric", "")
        s = judge.score(prompt, candidate, expected, rubric)
        total += s
        # Graded judges score in (0,1); only a zero is a clear MISS, a full 1.0 a clear ok,
        # anything between is a partial — a flat binary label would misread a graded judge.
        mark = "ok  " if s >= 1.0 else ("MISS" if s <= 0.0 else "part")
        print(f"  [{mark}] {c.get('id', '?')}: got={candidate!r} expected={expected!r} score={s:.2f}")

    if args.suite == "red-team":
        # The red-team suite's pass/fail is STRUCTURAL resistance, not a quality mean:
        # a low mean is expected (the reference SUT stub cannot refuse), so the mean
        # threshold does not gate here. It PASSES iff every judge-injection candidate
        # is neutralized (fenced). Live-injection resistance is the adopter's run.
        neutralized, injection_count = _print_resistance_summary(cases)
        mean = total / len(cases)
        print(f"red-team: mean score {mean:.3f} over {len(cases)} adversarial cases (structural gate)")
        rt_pass = not (injection_count and neutralized < injection_count)
        if args.trace:
            _emit_trace(args.trace, args, cases, mean, rt_pass, time.perf_counter() - _t0)
        if injection_count and neutralized < injection_count:
            print("red-team: FAIL — a judge-injection candidate was not fenced", file=sys.stderr)
            return 1
        print("red-team: PASS")
        return 0

    mean = total / len(cases)
    print(f"eval: mean score {mean:.3f} over {len(cases)} cases (threshold {args.threshold})")
    q_pass = mean >= args.threshold
    if args.trace:
        _emit_trace(args.trace, args, cases, mean, q_pass, time.perf_counter() - _t0)
    if mean < args.threshold:
        print(f"eval: FAIL — below threshold {args.threshold}", file=sys.stderr)
        return 1
    print("eval: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
