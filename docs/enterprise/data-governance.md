# Data Governance — Classification, Retention & Privacy Review

A general capability: classify the data a project handles, set retention/deletion per tier, and
record a **DPIA-lite privacy review** for sensitive data. Right-sized hygiene — **COPPA / children's
data is one applicability, not the point**; the kit gives you the artifact to *record* a privacy
posture, it does not assert you are "compliant" (the honesty invariant: green = recorded, not lawful).

## Classification scheme (4 tiers)

| Tier | Meaning | Handling (baseline) |
|------|---------|---------------------|
| **Public** | Intended for public release | No restriction |
| **Internal** | Non-public, low sensitivity | Access-controlled; no PII |
| **Confidential** | PII / commercially sensitive | Encrypt at rest + in transit; least-privilege; audit access; a **privacy review** |
| **Restricted** | Regulated / children's data / special-category | Confidential controls **plus** explicit lawful basis/consent, minimization, deletion path, and DPIA sign-off |

Declare the **highest tier a project handles** in the project `CLAUDE.md` §3
(`Data classification:`); record **retention + deletion** in `RUNBOOK.md` (`Data handling:`).

## Retention & deletion
- Set a retention period per dataset, justified by purpose; delete (or anonymize) at end of retention.
- Provide a **deletion-on-request** path for Confidential/Restricted (right-to-erasure where applicable).
- Record both in `RUNBOOK.md` `Data handling:`. The check confirms they are *recorded*; that deletion
  *works* is a Manual operator row.

## Privacy review (DPIA-lite)
When a feature handles **Confidential/Restricted** data, fill `templates/PRIVACY-REVIEW-TEMPLATE.md`
(purpose · data + classification · lawful basis/consent · minimization · retention · sharing · residual
risk · sign-off). Flagged at the **Definition of Ready** (alongside the threat-model flag) and verified
by `conformance/privacy-ready.sh`. For per-feature rigor, keep one review per feature touching personal data.

## Honesty boundary
`privacy-ready.sh` green proves a privacy review is **recorded** for the declared sensitive data — never
that the processing is lawful, that consent is valid, or that deletion works. Those are Manual rows
(operator/DPO evidence). Necessary, not sufficient.
