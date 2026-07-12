# Conformance Check — Test-Data Readiness

Proves a **data-handling project** declares how it gets **safe non-prod data**: synthetic, masked, or seeded — never raw prod. **Checklist-type**, run at Review and as recurring maintenance. **Conditional:** a project with no data surface marks the whole check **N/A — no test data to manage**. Verifies the patterns in `docs/operations/test-data-management.md` and the privacy rules in `DEVELOPMENT-STANDARDS.md` §2.

> **What the Auto row proves — and doesn't.** `test-data-ready.sh` confirms the approach is *recorded* (a RUNBOOK "Test data:" line). It does **not** verify the data is *actually* synthetic/masked or that no prod data leaked into non-prod. Those are the **Manual** rows. **A green script is necessary, not sufficient.**

## Checklist (blank)
| # | Item | Applies? | Evidence | Check |
|---|------|----------|----------|-------|
| 1 | Test-data approach recorded (RUNBOOK §2) *(documented)* | | | **Auto:** `test-data-ready.sh` |
| 2 | Non-prod data is actually synthetic / masked — no raw prod *(verified)* | | | Manual |
| 3 | PII / children's data masked or synthetic (COPPA-grade) where applicable *(verified)* | | | Manual |
| 4 | Masking happens on-extract (never raw prod copied down then masked) *(verified)* | | | Manual |

> A pure-compute project (CLI, library, no datastore) marks the whole check **N/A — no test data to manage**; `test-data-ready.sh` skip-passes it automatically.
