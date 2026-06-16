# Eval rubric — reference (read me before trusting the green)

This `evals/` directory is the kit's **reference eval harness**. It exists so the `gate-eval`
CI step is green on first clone — but a green run here proves only that **the harness mechanics
work**, not that any real model meets a quality bar. That is the kit's honesty invariant applied
to evals: *declared/wired, not proven.* Make it real before you rely on it.

## What ships

- **`run.py`** — loads a golden set, runs the system under test, scores each case, aggregates a
  mean, and exits non-zero below `--threshold`. CI runs `python -m evals.run --threshold 0.8`.
- **`golden.jsonl`** — five rows (`id`, `input`, `expected`) for a toy sentiment task.
- **`generate()`** — a deterministic, offline **stub** (rule-based tagger). No network, no API key.
- **`score()`** — exact-match rubric (1.0 / 0.0).

## How to make it a real eval

1. **Replace `generate()`** with your model/prompt call — e.g. the Anthropic SDK with a pinned
   model. Keep it deterministic where you can (low temperature, fixed seed) so the gate is stable.
2. **Replace `golden.jsonl`** with your curated dataset. Grow it from production misses and
   red-team findings; version it with the code.
3. **Upgrade `score()`** from exact-match to either graded metrics (e.g. token-overlap, rubric
   keyword coverage) or an **LLM-as-judge**: send `(input, candidate, expected, rubric)` to a
   *pinned judge model* and parse a 0..1 score. Keep the judge model pinned so scores are
   comparable over time, and keep judge independence in mind (don't grade with the same prompt
   you're testing).
4. **Add a safety / red-team subset** — adversarial inputs that must be refused or handled.
5. **Tune `--threshold`** to your quality bar; a decline over time is tech debt to track.

## Why offline-by-default

A shipped runner that called a live judge would fail an adopter's first CI run without an API key
— re-creating the very "claims a capability it doesn't deliver" failure this harness was added to
fix. Offline-by-default is green-on-clone *and* honest. The live judge is the documented upgrade,
not the shipped default.
