# [Project] — Restore-Drill Evidence Record

> **Template.** A dated, PER-DRILL evidence record — distinct from the how-to (`docs/continuity/backup-restore-drill.md`) and from the BIA's targets (`templates/BIA-TEMPLATE.md`). Required once a project has a persistent-data surface (`conformance/dr-readiness.md`); the filled copy lives at `docs/continuity/RESTORE-DRILL.md` and is what `readiness.sh dr-ready` checks for, alongside the RUNBOOK's one-line `Restore verified:` date. One entry per drill — append new drills below the most recent rather than overwriting. Recording a date here is the floor; a *passed* drill (actuals within the BIA's RTO/RPO) is the bar — presence alone is not proof the restore worked.

## Drill record

- **Date:** [YYYY-MM-DD]
- **Tier / what was restored:** [e.g. Critical — customer DB, from the BIA's tier list]
- **Backup restored:** [snapshot / PITR / dump identifier, and its timestamp]
- **RTO actual / target:** [e.g. 38m / 1h]
- **RPO actual / target:** [e.g. 4m / 15m]
- **RPO/RTO met?** [yes / no — both must hold to call this drill passed]
- **Integrity verified:** [row counts / checksums / smoke query — what you actually checked]
- **Operator:** [name / role]
- **Outcome:** [passed / failed — if failed, the remediation and the re-drill date]

---

*(Append additional drill records above this line, most recent first.)*
