# Conformance Check — Eval Readiness

Proves an **AI feature** holds a dev-time quality bar: outputs are scored against a versioned dataset + rubric, a **regression threshold** gates CI, and safety/red-team checks run before shipping. **Checklist-type**, run at the **§7 Eval gate** (`DEVELOPMENT-PROCESS.md` §7) and as **recurring maintenance** (§15). **Conditional:** a project with no model/prompt marks the whole check **N/A — not an AI feature**. Verifies the discipline asserted in `DEVELOPMENT-STANDARDS.md` (AI Evaluations / eval-driven development).

> **What the Auto rows prove — and don't.** `eval-ready.sh` confirms the eval discipline is *declared* (an EVAL-PLAN with a recorded regression threshold and a located harness/gate). It does **not** run the evals, prove they pass, or run the red-team — that is the §7 Eval gate in CI plus the **Manual** rows below. **A green script is necessary, not sufficient.**

## How to use
Produce an `EVAL-PLAN.md` from `templates/EVAL-PLAN-TEMPLATE.md`. Items tagged *(documented)* are auto-checkable via `sh conformance/eval-ready.sh`; items tagged *(verified)* require the actual eval/red-team run.

## Checklist (blank)

| # | Item | Applies? | Evidence (where/how) | Check |
|---|------|----------|----------------------|-------|
| 1 | `EVAL-PLAN.md` present *(documented)* | | | **Auto:** `eval-ready.sh` |
| 2 | Regression threshold recorded (the §7 gate bar) *(documented)* | | | **Auto:** `eval-ready.sh` |
| 3 | Harness/gate located (suite + how CI runs it) *(documented)* | | | **Auto:** `eval-ready.sh` |
| 4 | Eval suite **passes** at/above threshold in CI *(verified)* | | | Manual / §7 Eval gate |
| 5 | Regression checked on the latest model/prompt/param change *(verified)* | | | Manual / §7 Eval gate |
| 6 | Safety / red-team set **run** (jailbreaks, harmful-output) *(verified)* | | | Manual |
| 7 | Judge independent of the system under test (no self-grading) *(verified)* | | | Manual |
| 8 | Fairness / disparate-impact tested where the feature affects people (or N/A) *(verified)* | | | Manual |

> A non-AI project (CLI, library, batch job with no model) marks the whole check **N/A — not an AI feature**; `eval-ready.sh` skip-passes it automatically.
