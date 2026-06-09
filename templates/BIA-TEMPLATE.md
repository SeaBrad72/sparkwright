# [Project] — Business Impact Analysis (BIA)

> **Template.** Classifies the project's data and services by criticality and sets recovery targets (RTO/RPO) per tier. Produced at **Inception** for any project that handles durable data (`START-HERE.md` §6); the filled copy lives at `docs/continuity/BIA.md` and feeds RUNBOOK §6 and the DR-readiness check (`conformance/dr-readiness.md`). Aligns with **NIST SP 800-34**.

**Owner:** [name / role] · **Date:** [date] · **Review cadence:** [e.g. annually + on major change]

## How to use
- Fill every section in plain language. Revisit when the data model or dependencies change.
- The tiers and targets you set here are the contract the restore drill (`docs/continuity/backup-restore-drill.md`) is measured against.

---

## 1. Data & service inventory
> What data and services exist, and what each holds.

| Data / service | What it holds | Owner |
|----------------|---------------|-------|
| [e.g. customer DB] | [PII, orders] | [team] |

## 2. Criticality classification
> Classify each by impact of loss/unavailability. Suggested tiers: Critical · Important · Deferrable.

| Data / service | Tier | Impact if lost or unavailable |
|----------------|------|-------------------------------|
| [customer DB] | [Critical] | [regulatory + revenue + trust] |

## 3. Recovery targets (RTO / RPO) per tier
> RTO = how fast you must be back. RPO = how much data loss is tolerable.

| Tier | RTO (max downtime) | RPO (max data loss) |
|------|--------------------|---------------------|
| Critical | [e.g. 1h] | [e.g. 15m] |
| Important | [e.g. 4h] | [e.g. 24h] |
| Deferrable | [e.g. 72h] | [e.g. 1 week] |

## 4. Dependencies
> Upstream/downstream systems and third parties whose failure affects recovery.

[...]

## 5. Maximum tolerable downtime & notes
> The point beyond which downtime causes unacceptable / irreversible harm; any regulatory recovery obligations.

[...]
