# Eval Plan — ml sentiment tagger (reference AI feature)

## Feature
- **AI feature:** yes
- **What the model/prompt does:** Deterministic-offline sentiment tagger reference (positive/negative/neutral); the SUT stub in `run.py` is replaced by the adopter's model call.

## Task-quality evals (the dataset + rubric)
- **Dataset:** `evals/golden.jsonl` — the versioned golden set, curated with the code and grown from production misses (add a real miss as a case at each retro). A `red-team.jsonl` adversarial set rides alongside for the safety suite.
- **Scoring:** exact-match offline (default `--judge exact`, green-on-clone with no network / no API key) → graded rubric / LLM-as-judge (`--judge fake` for the offline rubric path; `--judge claude` for the live judge) on upgrade. See `judges.py` + `rubric.md` for the upgrade recipe.
- **Pinned judge + model version:** `claude-opus-4-8` as judge @ temperature 0 (pinned in `PINNED_JUDGE_MODEL`); system-under-test = the adopter's model + version (recorded in the AI System Card).

## Regression bar (the §7 gate)
- **Regression threshold:** mean score >= 0.8 over the golden set; no metric drop > 2pts vs baseline.
- **Harness:** evals/run.py (python -m evals.run --threshold 0.8), run in CI gate-eval on any model/prompt/param change; behavioral lock conformance/eval-harness-runs.sh.
- **Model-upgrade regression:** on any model / prompt / parameter change, the suite re-runs before merge (the gate's trigger).

## Safety / red-team (Manual)
- [x] Adversarial prompts / jailbreaks tested before shipping — the adversarial `red-team.jsonl` set is exercised via `python -m evals.run --suite red-team`.
- [x] Harmful-output checks run — the red-team suite passes iff every judge-injection candidate is resisted (fenced-untrusted-candidate defense in `judges.py`).
- [x] Judge is independent of the system under test (no self-grading) — `ClaudeJudge` raises when `judge_model == sut_model`; independence is enforced in code, not by convention.

## Fairness / bias (Manual)
- [x] Protected dimensions evaluated — **N/A — product-review sentiment has no human-subject / protected-class dimension.** The feature labels the tone of review text; it makes no decision about a person and infers no protected attribute.
- [x] Fairness metric + threshold recorded — **N/A (same reason: no human-subject dimension).**
- [x] Result reviewed by the owner before shipping — **N/A (no fairness surface to regress).**

## Quality tracking
- **Eval score trend:** the CI gate-eval run's mean-score line (`eval: mean score ... over N cases`), plus the `--trace` NDJSON emission; a decline is tech debt, surfaced at retro and grown into a new golden case.
