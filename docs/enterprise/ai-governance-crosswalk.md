# AI-Governance Crosswalk — US-first (NIST AI RMF · ISO 42001 · US state law · OWASP/MITRE)

Maps the **AI-governance controls this kit provides** to the frameworks a **US** AI-deploying enterprise actually answers to. Use it to show an auditor *where the AI-governance evidence lives* in a repo built with this kit. Companion to `compliance-crosswalk.md` (SOC 2 / ISO 27001).

**How to read it:** the `Responsibility` column is the honest part — **Kit-enforced** (mechanical evidence), **Kit-assisted** (kit gives the artifact/pattern; team produces evidence), **Org-owned** (the organization owns it — see [README boundary](README.md)). Rows that don't apply are marked **N/A (reason)**.

**Jurisdiction:** **US-first.** The practical US anchor is **NIST AI RMF + the Generative AI Profile (NIST-AI-600-1)** — and Texas TRAIGA grants a **safe harbor** for substantial compliance with it. **ISO/IEC 42001** (international, voluntary) pairs with SOC 2. The **EU AI Act** is a fenced **optional overlay** (last section) — only with EU market exposure; its conformity-assessment / CE / FRIA / EU-database machinery is **Org-owned and out of the US baseline**.

## AI-governance controls

| Kit control / artifact | Where in the kit | NIST AI RMF | ISO/IEC 42001 | US driver (state / federal) | Responsibility |
|---|---|---|---|---|---|
| AI System Card — risk classification + human oversight | `templates/AI-SYSTEM-CARD-TEMPLATE.md`; `conformance/responsible-ai-ready.sh` (§7 gate) | GOVERN, MAP | Clause 6 (risk + impact assessment); Annex A (impact assessment, human oversight) | CO SB 26-189 / CA ADMT (consequential-decision disclosure); NIST RMF (TX TRAIGA safe harbor) | Kit-assisted |
| AI Policy | `templates/AI-POLICY-TEMPLATE.md` | GOVERN | Clause 5.2 (AI policy) | — | Kit-assisted |
| Eval gate — quality + regression + safety/red-team | `profiles/ml.md`; `conformance/eval-ready.sh`; §7 eval gate | MEASURE, MANAGE | Annex A (AI system lifecycle, performance) | NIST RMF MEASURE | Kit-enforced (the gate) · Kit-assisted (the evals) |
| Fairness / bias eval dimension | `templates/EVAL-PLAN-TEMPLATE.md` (Fairness section) | MEASURE | Annex A (impact: fairness) | EEOC · NYC Local Law 144 · CO/CA consequential-decision | Kit-assisted (Manual) |
| AI-output transparency sign-off | `templates/AI-TRANSPARENCY-SIGNOFF-TEMPLATE.md` | GOVERN, MAP | Annex A (transparency to stakeholders) | CA SB 942 / AB 2013 · FTC deception · COPPA | Kit-assisted (Manual) |
| Human oversight — agents propose, humans ratify | `DEVELOPMENT-PROCESS.md` §13; `docs/enterprise/ratification-rbac.md` | GOVERN, MANAGE | Annex A (human oversight) | CO/CA consequential-decision | Kit-enforced (ratification) |
| Prohibited-use acknowledgment | `templates/AI-SYSTEM-CARD-TEMPLATE.md` | MAP | Annex A (impact) | TX TRAIGA · FTC UDAP | Kit-assisted (Manual) |
| Data minimization + children's-data care | AI System Card; `DEVELOPMENT-STANDARDS.md` §2 (PII) | MAP, MANAGE | Annex A (data governance) | COPPA · CA | Kit-assisted · privacy program Org-owned |
| AI incident response + feedback to evals | `templates/POSTMORTEM-TEMPLATE.md`; `DEVELOPMENT-STANDARDS.md` (incident) | MANAGE | Clause 10 (improvement); Annex A | CA SB 53 incident-report principle · FTC | Kit-assisted |
| Prompt-injection defense / output validation | `DEVELOPMENT-STANDARDS.md` §2 (AI/agent security) | MANAGE | Annex A (lifecycle security) | — | Kit-assisted |
| Agent guard · MCP policy · containment · egress | `.claude/hooks/guard-core.sh`; `conformance/mcp-policy.sh` / `containment-ready.sh` / `egress-policy.sh` | MANAGE | Annex A (third-party governance, lifecycle) | — | Kit-enforced / Kit-assisted |
| Model + data versioning · reproducibility | `profiles/ml.md` (MLflow, DVC) | MEASURE, MANAGE | Annex A (lifecycle) | — | Kit-assisted |
| ISO 42001 certification (the AIMS itself) | — | — | Clauses 4–10 (the management system) | — | Org-owned |
| Which AI laws apply (legal determination) | — | — | — | state-law applicability is a legal call | Org-owned |

## Agentic-threat coverage — OWASP Top 10 for Agentic Applications (2025) + MITRE ATLAS

Honest coverage of the agentic-AI threat surface: **5 fully covered, 3 partial, 2 platform-owned gaps.** (Threat frameworks are jurisdiction-neutral.)

| OWASP Agentic risk | Kit control | Status |
|---|---|---|
| ASI01 Agent goal hijack | prompt-injection defense (`DEVELOPMENT-STANDARDS.md` §2) | Partial |
| ASI02 Tool misuse | MCP capability policy + guard deny-matrix | **Covered** |
| ASI03 Identity & privilege abuse | scoped short-lived tokens + containment | **Covered** |
| ASI04 Agentic supply chain | SBOM + provenance gates; MCP allowlist | **Covered** |
| ASI05 Unexpected code execution | guard deny-matrix + sandboxed FS | **Covered** |
| ASI06 Memory / context poisoning | TCC declares per-step context (not a runtime control) | Gap — platform-owned |
| ASI07 Insecure inter-agent comms | — | Gap — multi-agent, platform-owned |
| ASI08 Cascading failures | resilience / circuit-breakers (`resilience-ready.sh`) | Partial |
| ASI09 Human-agent trust exploitation | agents-propose-humans-ratify + ratification RBAC | Partial |
| ASI10 Rogue agents | autonomy tiers (`agent-autonomy.sh`) + immutable audit | **Covered** |

> **MITRE ATLAS** (v5.4.0): the kit's controls map to ATLAS techniques — e.g. *Publish Poisoned AI Agent Tool* → MCP allowlist + SBOM; *Escape to Host* → sandboxed FS + containment. ATLAS is the technique catalog; OWASP Agentic is the risk-prioritization lens.

> The 2 gaps (ASI06 memory poisoning, ASI07 inter-agent comms) and the runtime depth of the partials are **platform-owned** — the kit declares + governs; the runtime enforces. This is the same honest boundary as `platform-safety-boundary.md`.

## EU AI Act — optional overlay (only with EU market exposure)

Turn this on **only** if you place AI on the EU market. The EU's *substantive* requirements are good practice the kit already embodies; its *bureaucracy* (conformity assessment, CE marking, fundamental-rights impact assessment, EU-database registration) is **Org-owned and excluded from the US baseline**.

| EU AI Act article | Good-practice substance | Kit artifact (already covers the substance) |
|---|---|---|
| Art. 9 (risk management) | iterative AI risk management | AI System Card + threat-model |
| Art. 10 (data governance) | data quality + bias examination | Fairness eval + data-minimization |
| Art. 12 (logging) | lifecycle traceability | immutable audit logging |
| Art. 13/14 (transparency / human oversight) | instructions + meaningful oversight | AI System Card + AI Transparency sign-off + ratification |
| Art. 15 (accuracy / robustness / security) | tested, robust, adversarial-resistant | eval gate + agentic-threat lens |
| Art. 50 (transparency to users) | disclose AI + label synthetic content | AI Transparency sign-off |
| Art. 72 (post-market monitoring) | monitor in production | observability + ML drift |
| Conformity assessment / CE / FRIA / EU-DB | EU-only certification machinery | **Org-owned — not in the US baseline** |
