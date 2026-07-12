# Conformance Check — DR Readiness

Proves **disaster recovery is real**: data classified by criticality (BIA), RTO/RPO tiered, and a restore drill actually run. **Checklist-type**, run at the **DR-readiness gate** (`DEVELOPMENT-PROCESS.md` §7), as **recurring maintenance** (§15), and as part of the **Definition of Done for data services** (`CLAUDE.md`). **Conditional:** projects with no durable data (stateless service, CLI, library) mark the whole check **N/A — no persistent data to recover**. Aligns with NIST SP 800-34 (contingency planning) and the Data Management contract (`DEVELOPMENT-STANDARDS.md` §10).

> **What the Auto rows prove — and don't.** `dr-ready.sh` confirms DR is *written down* (a BIA exists, RUNBOOK RTO/RPO are set, a restore-drill date is recorded). It does **not** verify the restore *succeeded* or *met RTO/RPO* — those are the **Manual** rows, signed off by the on-call/operator with evidence. **A green script is necessary, not sufficient.**

> **The script's `N/A` is advisory only.** Detection of a "persistent-data surface" is deliberately conservative and can miss a data project. **If this project handles durable data, this checklist applies regardless of what `dr-ready.sh` prints.** The script escalates (detect → require); it never exempts. The human-applied checklist is the gate of record.

## How to use
Copy this file into your project (or your DR record). For each item: mark **Applies? (Y / N+reason)** and give **Evidence**. Items tagged *(documented)* are auto-checkable via `sh conformance/dr-ready.sh`; items tagged *(verified)* require the on-call/operator's evidence from an actual drill. The reviewer signs off only when every applicable item has evidence.

## Checklist (blank)

| # | Item | Applies? | Evidence (where/how) | Check |
|---|------|----------|----------------------|-------|
| 1 | BIA done — data/services classified by criticality (`docs/continuity/BIA.md`) *(documented)* | | | **Auto:** `dr-ready.sh` |
| 2 | Per-tier RTO/RPO defined from the BIA (RUNBOOK §6, not placeholder) *(documented)* | | | **Auto:** `dr-ready.sh` |
| 3 | Automated backups configured for production data *(verified)* | | | Manual |
| 4 | Restore drill **run** — date recorded in RUNBOOK §6 *(documented)* | | | **Auto:** `dr-ready.sh` |
| 5 | Restore drill **succeeded** — data actually restored, integrity verified *(verified)* | | | Manual |
| 6 | RTO/RPO **actuals met** the tier targets in the last drill *(verified)* | | | Manual |
| 7 | Backups stored durably + access-controlled (off-host / off-region) *(verified)* | | | Manual |
| 8 | Drill scheduled as recurring maintenance (§15) | | | Manual |

## Worked example — a deployable HTTP service with a Postgres database

| # | Item | Applies? | Evidence | Check |
|---|------|----------|----------|-------|
| 1 | BIA done *(documented)* | Y | `docs/continuity/BIA.md` — 3 tiers, customer data = Critical | Auto ✅ |
| 2 | Per-tier RTO/RPO *(documented)* | Y | RUNBOOK §6: Critical RTO 1h/RPO 15m; Standard RTO 4h/RPO 24h | Auto ✅ |
| 3 | Automated backups *(verified)* | Y | managed Postgres PITR + nightly snapshot (infra console) | Manual ✅ |
| 4 | Drill run — date recorded *(documented)* | Y | RUNBOOK §6 "Restore verified: 2026-06-01" | Auto ✅ |
| 5 | Drill succeeded *(verified)* | Y | restored to isolated env; row-count + checksum match (drill log) | Manual ✅ |
| 6 | RTO/RPO actuals met *(verified)* | Y | restore took 38m (< 1h target); data loss 4m (< 15m) | Manual ✅ |
| 7 | Durable + access-controlled *(verified)* | Y | backups in separate region bucket, IAM-restricted | Manual ✅ |
| 8 | Drill scheduled | Y | quarterly recurring board item (§15) | Manual ✅ |

> A stateless service, CLI, or library marks the whole check **N/A — no persistent data to recover**; `dr-ready.sh` skip-passes such a project automatically. **If your only "data" is an ephemeral cache (e.g. a cache-only `REDIS_URL`), mark N/A — there is no durable data to recover.**
