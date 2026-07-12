# Test-Data Management

How to give non-prod environments **realistic data without the privacy risk of real data**. Stack-neutral; the per-stack tool is a profile choice. Pairs with the env strategy (`DEVELOPMENT-PROCESS.md` §9) and the privacy rules (`DEVELOPMENT-STANDARDS.md` §2). It is the data preview environments seed from (`preview-environments.md`).

## The rule: classify, then handle
| Data class | Non-prod handling |
|---|---|
| Public / non-sensitive | real data is fine |
| Internal / confidential | synthetic, or a masked subset |
| **PII / children's data** | **synthetic, or masked — never raw prod** (COPPA-grade; ties to the AI System Card data-minimization line) |

**Never copy raw production data into dev/QA/UAT.** If you must derive from prod, **mask on extract** (irreversibly transform PII before it leaves prod), never after.

## Three patterns
- **Synthetic generation** — generate fake-but-realistic data with a per-stack faker/factory tool (→ profile). Best default: no prod data ever touches non-prod.
- **Anonymization / masking** — for volume/shape realism, take a prod subset and irreversibly mask PII (names, emails, identifiers, children's data) at extraction time.
- **Deterministic seeds** — seed fixtures from a fixed seed so tests are reproducible and previews are consistent.

## Anti-patterns
- Raw prod dump in a shared dev DB · masking *after* the copy lands in non-prod · a "temporary" prod snapshot that becomes permanent · children's data in a preview environment.

## What the readiness check proves — and doesn't
`conformance/test-data-ready.sh` confirms a data-handling project **records** its test-data approach (RUNBOOK). It does **not** verify the data is *actually* synthetic/masked or that no prod data leaked — that is a **Manual** row (`test-data-readiness.md`). Necessary, not sufficient.
