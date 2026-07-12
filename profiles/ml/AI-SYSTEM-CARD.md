# AI System Card — ml sentiment tagger (reference AI feature)

## System summary
- **Feature / story:** KW24 — reference AI feature (ml sentiment tagger); `profiles/ml/evals/`.
- **What it does (1–2 lines):** Sentiment tagger reference — labels product-review text as positive / negative / neutral. Ships as a deterministic offline scorer the adopter upgrades to a live model call.
- **Model + version:** claude-opus-4-8 — orchestrated frontier model, not trained in-house.
- **Build mode:** orchestrate a frontier model.

## Risk classification (US-first)
- **Risk classification:** low-risk — none triggered (consequential-decision: no; children's-data: no; prohibited-use: no).
- **EU AI Act overlay** *(optional — only with EU market exposure)*: N/A — no EU exposure.
- **Prohibited-use acknowledgment** *(good-citizen, one-time)*: this feature is **not designed for** unlawful discrimination, self-harm encouragement, CSAM, or deception. Confirmed — sentiment labeling of review text carries none of these uses.

## Intended use
- **Intended use:** sentiment labeling of product-review text for analytics (aggregate tone / trend reporting).
- **Out-of-scope / prohibited use:** NOT a consequential decision (no employment, credit, housing, education, healthcare, insurance, or legal outcome); NOT moderation-of-record; NOT for protected-class inference.

## Data flows + consent
- **What data reaches the model:** review text only. No PII. No children's data.
- **Consent basis + what leaves the trust boundary:** the offline default (`--judge exact` / `--judge fake`) sends nothing — no network, no egress. Provider egress happens ONLY on the opt-in live Claude judge (`--judge claude`), where review text reaches the Anthropic API; adopters gate that on consent for their data.
- **Data minimization** *(good-citizen)*: only the review text needed to score sentiment is sent; no user identifiers or metadata.

## Human oversight
- **Human oversight:** the §7 eval gate + human ratification (agents propose, humans ratify); an operator can disable the AI path via the judge selector / eval gate.

## Guardrails (links, not restated)
- **Runtime controls:** prompt-injection defense — the judge fences the UNTRUSTED candidate and instructs the judge to treat the fenced region as data to grade, never as instructions (`judges.py` `_build_prompt` / `_strip_fence`, fixed-point breakout neutralization); judge-independence enforcement (`ClaudeJudge.__init__` refuses `judge_model == sut_model`). Not restated here — see `profiles/ml/evals/judges.py`.
- **Eval / quality bar:** see the companion EVAL-PLAN.md + the §7 eval gate (behavioral lock `conformance/eval-harness-runs.sh`).
- **Transparency** *(user-facing AI)*: N/A — internal analytics labeling, no direct end-user AI interaction surface. If exposed to users, disclose per `templates/AI-TRANSPARENCY-SIGNOFF-TEMPLATE.md`.

## Known limitations + failure modes
- Sentiment is coarse (3-way) and offline-deterministic by default — the reference scorer does not understand nuance, sarcasm, or mixed sentiment until upgraded to a live judge. Degradation on out-of-distribution or non-English text; monitor the eval mean-score trend in production and grow the golden set from misses.

## Sign-off

| Field | Value |
|-------|-------|
| Decision | **pass** |
| Security / compliance owner (role) | Bradley James (security/compliance owner) |
| Date | 2026-07-08 |
| Conditions / follow-ups | Live-judge egress (`--judge claude`) requires adopter consent basis before enabling on real review data. |
