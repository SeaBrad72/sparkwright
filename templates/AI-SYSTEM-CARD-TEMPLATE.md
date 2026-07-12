# AI System Card

> **Template.** Delete the guidance; fill the sections. The declarative artifact for an **AI feature** (any behaviour depending on a model or prompt) — a US-anchored AI use declaration + risk classification, verified *present* by `conformance/responsible-ai-ready.sh`. Doubles as the ISO/IEC 42005 AI system impact assessment for adopters pursuing ISO 42001. **Proportional:** a low-risk feature fills only the summary + classification + oversight; a consequential-decision or children's-data feature fills the rest. The **security/compliance owner** signs at Review. Presence is not correctness — the classification's accuracy and the fairness/compliance results are **Manual** rows in `conformance/responsible-ai-readiness.md`. Store under `docs/sign-offs/` or attach to the PR.

## System summary
- **Feature / story:** <link>
- **What it does (1–2 lines):** [summary]
- **Model + version:** [e.g. claude-opus-4-8 — orchestrated frontier model, not trained in-house]
- **Build mode:** [orchestrate a frontier model · fine-tune · train from scratch]

## Risk classification (US-first)
- **Risk classification:** [classification]
  <!-- Answer three triggers: consequential/automated decision (employment, credit, housing, education, healthcare, insurance, legal)? · children's data (under-13 / mixed-audience → COPPA)? · prohibited use (unlawful discrimination, self-harm encouragement, CSAM, deception → hard stop)? → e.g. "low-risk — none triggered" or "consequential-decision: yes (hiring screen); children's-data: no; prohibited-use: no". Replace the bracketed placeholder above. -->
- **EU AI Act overlay** *(optional — only with EU market exposure)*: [tier or "N/A — no EU exposure"]
- **Prohibited-use acknowledgment** *(good-citizen, one-time)*: this feature is **not designed for** unlawful discrimination, self-harm encouragement, CSAM, or deception. [confirm / note exception]

## Intended use
- **Intended use:** [what it is for]
- **Out-of-scope / prohibited use:** [what it must not be used for]

## Data flows + consent
- **What data reaches the model:** [inputs; PII; children's data]
- **Consent basis + what leaves the trust boundary:** [consent; third-party/provider egress — links to egress/containment]
- **Data minimization** *(good-citizen)*: [minimize inputs to what the task needs, esp. PII/children's data]

## Human oversight
- **Human oversight:** [mechanism]
  <!-- who can override/halt the AI; links to "agents propose, humans ratify" + ratification RBAC. If a consequential decision: add a documented human review / appeal path. Replace the bracketed placeholder above. -->

## Guardrails (links, not restated)
- **Runtime controls:** [prompt-injection defense · MCP policy · egress · containment — link the kit controls already in place]
- **Eval / quality bar:** [link the EVAL-PLAN + §7 eval gate]
- **Transparency** *(user-facing AI)*: [AI interaction disclosed + synthetic content labeled — `templates/AI-TRANSPARENCY-SIGNOFF-TEMPLATE.md`]

## Known limitations + failure modes
- [what it gets wrong; degradation modes; monitoring in production]

## Sign-off

| Field | Value |
|-------|-------|
| Decision | **pass** / pass-with-conditions / fail |
| Security / compliance owner (role) | <name> |
| Date | YYYY-MM-DD |
| Conditions / follow-ups | [tracked items, links] |
