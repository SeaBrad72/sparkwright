# Conformance Check — Responsible-AI Readiness

Proves an **AI feature** carries its governance declaration: an **AI System Card** with a US risk classification and a named human-oversight mechanism. **Checklist-type**, run at the **§7 AI System Card gate** (`DEVELOPMENT-PROCESS.md` §7) and as **recurring maintenance** (§15). **Conditional:** a project with no model/prompt marks the whole check **N/A — not an AI feature**. US-anchored (NIST AI RMF + GenAI Profile · TX TRAIGA · CO/CA consequential-decision · COPPA/FTC); EU AI Act is an optional overlay. Verifies the discipline asserted in `DEVELOPMENT-STANDARDS.md` (AI / agent security) and the arc spec.

> **What the Auto rows prove — and don't.** `responsible-ai-ready.sh` confirms the AI System Card is *present, classified, and oversight-named*. It does **not** verify the classification is *correct*, the AI is *fair*, the disclosure *shipped*, or it is *compliant* — those are the **Manual** rows below, signed by the security/compliance owner. The good-citizen lines (prohibited-use ack, data-minimization, review/appeal path) are recommended defaults, **not enforced**. **A green script is necessary, not sufficient.**

## How to use
Produce an `AI-SYSTEM-CARD.md` from `templates/AI-SYSTEM-CARD-TEMPLATE.md`. Items tagged *(documented)* are auto-checkable via `sh conformance/responsible-ai-ready.sh`; items tagged *(verified)* require the owner's judgement/evidence.

## Checklist (blank)

| # | Item | Applies? | Evidence (where/how) | Check |
|---|------|----------|----------------------|-------|
| 1 | `AI-SYSTEM-CARD.md` present *(documented)* | | | **Auto:** `responsible-ai-ready.sh` |
| 2 | US risk classification recorded (consequential / children's / prohibited) *(documented)* | | | **Auto:** `responsible-ai-ready.sh` |
| 3 | Human-oversight mechanism named *(documented)* | | | **Auto:** `responsible-ai-ready.sh` |
| 4 | Classification is **correct** for the actual use *(verified)* | | | Manual |
| 5 | Fairness / disparate-impact tested where consequential (→ EVAL-PLAN) *(verified)* | | | Manual / §7 Eval gate |
| 6 | User-facing AI disclosure + content labeling shipped where applicable (`templates/AI-TRANSPARENCY-SIGNOFF-TEMPLATE.md`) *(verified)* | | | Manual |
| 7 | Children's-data care (COPPA: consent, minimization, retention) where applicable *(verified)* | | | Manual |
| 8 | Security/compliance owner signed the card *(verified)* | | | Manual |
| 9 | Produced-artifact lineage recorded where the AI ships outputs/models/datasets (`templates/AI-ARTIFACT-LINEAGE-TEMPLATE.md`) *(verified)* | | | Manual |

> A non-AI project (CLI, library, batch job with no model) marks the whole check **N/A — not an AI feature**; `responsible-ai-ready.sh` skip-passes it automatically.
