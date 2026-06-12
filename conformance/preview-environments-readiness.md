# Conformance Check — Preview-Environments Readiness

Proves a **deployable project** declares how it runs **per-PR preview environments** — or records an explicit N/A. **Checklist-type**, run at Review and as recurring maintenance. **Conditional:** non-deployable projects mark the whole check **N/A — no deploy surface**. Verifies the lifecycle + guardrails in `docs/operations/preview-environments.md` and the env model in `DEVELOPMENT-PROCESS.md` §9.

> **What the Auto row proves — and doesn't.** `preview-env-ready.sh` confirms the approach is *recorded* (a RUNBOOK §4 "Preview environments:" line). It does **not** verify previews actually spin up, tear down, isolate, or exclude prod data. Those are the **Manual** operator rows. **A green script is necessary, not sufficient.**

## Checklist (blank)
| # | Item | Applies? | Evidence | Check |
|---|------|----------|----------|-------|
| 1 | Preview-env approach recorded (RUNBOOK §4) *(documented)* | | | **Auto:** `preview-env-ready.sh` |
| 2 | Previews actually spin up per PR *(verified)* | | | Manual |
| 3 | Previews **auto-tear-down** on merge/close (no orphans) *(verified)* | | | Manual |
| 4 | Seeded with safe (synthetic/masked) data — **no prod data** *(verified)* | | | Manual |
| 5 | Scoped short-lived credentials; **no prod secrets** in preview *(verified)* | | | Manual |
| 6 | Isolation — one PR's preview cannot reach another's data or prod *(verified)* | | | Manual |

> A non-deployable project (library, CLI, batch) marks the whole check **N/A — no deploy surface**; `preview-env-ready.sh` skip-passes it automatically.
