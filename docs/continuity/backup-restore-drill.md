# Backup-Restore Drill — Reference

How to **prove** disaster recovery works by actually restoring a backup. Stack-neutral; tooling is a project/Org choice. Aligns with **NIST SP 800-34** (contingency planning). This is the "how" behind the recurring-maintenance item "Backup-restore verification" (`DEVELOPMENT-PROCESS.md` §15) and the DR-readiness check (`conformance/dr-readiness.md`).

> **Do no harm — never drill against production.** A restore drill restores **into an isolated environment** (a scratch database/instance), never over live data. Restoring onto production can destroy the very data you are trying to protect.

## Before you drill — the inputs
- A **BIA** (`templates/BIA-TEMPLATE.md` → `docs/continuity/BIA.md`) that classifies data/services by criticality and sets **per-tier RTO/RPO**.
- A known-good **backup** (snapshot, PITR, dump) for the tier you are drilling.

## The drill, step by step
1. **Pick a tier** from the BIA (drill the most critical tier most often).
2. **Identify the backup** to restore (note its timestamp — this sets the data-loss window).
3. **Restore into an isolated environment** — a fresh DB/instance with no production access.
4. **Verify integrity** — row counts vs. expectation, checksums/hashes, a smoke query on critical tables, referential integrity.
5. **Measure the actuals** — **RTO actual** = wall-clock from "start restore" to "service usable"; **RPO actual** = gap between the backup timestamp and the incident point.
6. **Compare to the tier targets** — actuals must be within the BIA's RTO/RPO for that tier.
7. **Record** — write the date and result in RUNBOOK §6 ("Restore verified: YYYY-MM-DD (passed/failed, RTO/RPO actuals)") and close the recurring board item (§15).

## What "passed" means
- Data restored **and** integrity verified **and** RTO/RPO actuals within the tier targets.
- Recording a date is the **floor**; a *passed* drill (the Manual rows in `conformance/dr-readiness.md`) is the **bar**. A recorded date alone does not prove DR works.

## Cadence
- At least **once per project**, then **on schedule** (recurring maintenance, §15) — quarterly is a sensible default; the most critical tier more often.
- **Pre-launch** for any new data service, and after any change to the backup/restore path.

## Tooling (Org-owned)
Backup mechanism, snapshot scheduling, and the isolated restore environment are platform choices (managed-DB PITR, object-store snapshots, IaC to stand up the scratch env). The kit standardizes the **practice and the proof**, not the tool.
