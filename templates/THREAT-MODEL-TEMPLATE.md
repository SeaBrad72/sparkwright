# Threat Model

> **Template.** Delete the guidance; fill the sections. The auditable evidence for the **§7 security gate** (`DEVELOPMENT-PROCESS.md`) and the Definition-of-Ready **threat-model flag** (`CLAUDE.md`), required for **sensitive / regulated** features. STRIDE for security threats + a LINDDUN-lite privacy lens (the kit's adopter profile may handle customer + affiliate data and children's-audience content). The **security owner** signs at Review. Keep it a structured record, not prose — presence is not quality; the value is the threats you find and mitigate. There is deliberately **no conformance script** for this artifact (a script cannot tell a real threat model from a box-ticked one, and "sensitive" is not honestly auto-detectable). Attach to the PR or store under `docs/sign-offs/` (or your security record).

## System & assets
- **Feature / story:** <link>
- **What it does (1–2 lines):** [summary]
- **Assets at risk:** [data, credentials, money, availability, safety]
- **Data classification:** [public / internal / confidential / PII / children's data] — [why]
- **Entry points / actors:** [users, agents, services, admins]

## Trust boundaries
- [boundary 1 — e.g. internet → app; what crosses it; what is validated]
- [boundary 2 — e.g. app → datastore; least-privilege creds]
- [boundary 3 — e.g. app → third-party / AI provider; what data leaves, consent]

## Threats (STRIDE) + mitigations

| STRIDE category | Threat (this system) | Likelihood × Impact | Mitigation / control | Status |
|-----------------|----------------------|---------------------|----------------------|--------|
| **S**poofing (identity) | [threat] | [L×I] | [auth, MFA, token validation] | [planned/done] |
| **T**ampering (integrity) | [threat] | [L×I] | [input validation, signing, parameterized queries] | |
| **R**epudiation (audit) | [threat] | [L×I] | [immutable audit log] | |
| **I**nformation disclosure | [threat] | [L×I] | [encryption at rest/in transit, least privilege, log redaction] | |
| **D**enial of service | [threat] | [L×I] | [rate limiting, quotas, circuit breakers] | |
| **E**levation of privilege | [threat] | [L×I] | [authz checks, least-privilege roles] | |

## Privacy (LINDDUN-lite)
- **Linkability / identifiability:** [can records be linked / re-identified? minimization?]
- **PII handling:** [what PII, consent basis, retention, right-to-erasure path]
- **Third-party / AI data flow:** [what leaves the boundary; consent; redaction] — N/A if none
- **Prompt-injection / AI abuse** *(if an AI feature)*: [untrusted-input → model guardrails, output validation] — N/A if no model

## Residual risk
- [risk accepted, why, compensating control, expiry/review date — ties to the governed-exception register if a gate is waived]

## Sign-off

| Field | Value |
|-------|-------|
| Decision | **pass** / pass-with-conditions / fail |
| Security owner (role) | <name> (Security owner) |
| Date | YYYY-MM-DD |
| Conditions / follow-ups | [tracked items, links] |
