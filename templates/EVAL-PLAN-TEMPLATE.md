# Eval Plan — TEMPLATE

> **Template.** The dev-time quality bar for an **AI feature** (any behaviour that depends on a model or prompt) — *evals are the test suite* (`DEVELOPMENT-STANDARDS.md` §AI Evaluations). Produced at **Plan**, enforced at the **§7 Eval gate** (the suite runs in CI; a drop below threshold fails the build), and grown from production misses + retros. Its *presence* makes a project an AI feature for `conformance/eval-ready.sh`. Stack-specific harness → your `profiles/<stack>.md` (e.g. the `ml` profile ships `evals/run.py`).

> **What the readiness check proves — and doesn't.** `eval-ready.sh` confirms this plan is *declared*: a recorded regression threshold and a located harness/gate. It does **not** run the evals or prove they pass — that is the §7 Eval gate in CI, and the red-team/judge-independence items below are **Manual**. A green readiness check is necessary, not sufficient.

## Feature
- **AI feature:** yes
- **What the model/prompt does:** [one line]

## Task-quality evals (the dataset + rubric)
- **Dataset:** [path / size / how curated — golden set, versioned with the code]
- **Scoring:** [exact-match | graded rubric | LLM-as-judge]
- **Pinned judge + model version:** [e.g. claude-sonnet-4-6 as judge; system-under-test model + version]

## Regression bar (the §7 gate)
- **Regression threshold:** [threshold]   <!-- e.g. "score >= 0.85; no metric drops > 2pts vs baseline" — the bar the CI Eval gate enforces. Replace the bracketed placeholder above with a real value. -->
- **Harness:** [harness]   <!-- where the suite lives + how the gate runs it, e.g. "evals/run.py, pytest-driven, run in CI on any prompt/model/param change". Replace the bracketed placeholder above. -->
- **Model-upgrade regression:** on any model / prompt / parameter change, the suite re-runs before merge (the gate's trigger).

## Safety / red-team (Manual)
- [ ] Adversarial prompts / jailbreaks tested before shipping
- [ ] Harmful-output checks run
- [ ] Judge is independent of the system under test (no self-grading)

## Quality tracking
- **Eval score trend:** [where tracked] — a decline is tech debt, surfaced at retro.
