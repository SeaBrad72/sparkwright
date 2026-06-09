# Conformance Check — Definition of Deployable

Proves a **release** is safe to promote: rollback ready, smoke + monitoring wired, migrations reversible. **Checklist-type**, run at the **Release gate** (`DEVELOPMENT-PROCESS.md` §7, after Review). **Conditional:** non-deployable projects (library, CLI, batch) mark the whole check **N/A — not a deployable service**. Aligns with OWASP DSOMM (deployment/release maturity) and the Safe Change Delivery contract (`DEVELOPMENT-PROCESS.md` §10).

> **What the Auto rows prove — and don't.** The `deployable-ready.sh` rows confirm the release-safety procedures are *written down* (RUNBOOK has Deploy + Rollback sections) and a smoke test is *referenced*. They do **not** verify the rollback was tested, alerts are wired, or the migration down-path works — those are the **Manual** rows, signed off by the release manager with evidence. **A green script is necessary, not sufficient.**

## How to use
Copy this file into your project (or your release record). For each item: mark **Applies? (Y / N+reason)** and give **Evidence** (where/how it's met). Items tagged *(documented)* are auto-checkable via `sh conformance/deployable-ready.sh`; items tagged *(tested / wired)* require the release manager's evidence. The reviewer signs off only when every applicable item has evidence.

## Checklist (blank)

| # | Item | Applies? | Evidence (where/how) | Check |
|---|------|----------|----------------------|-------|
| 1 | Rollback path **declared before ship** — flag-off → redeploy previous → revert (§10) *(documented)* | | | **Auto:** `deployable-ready.sh` (RUNBOOK Rollback section) |
| 2 | Rollback path **tested** — the chosen path was actually exercised *(tested)* | | | Manual |
| 3 | DB migration **reversible** — down-path tested, expand-contract; N/A if no migration *(tested)* | | | Manual |
| 4 | Feature flags have **owner + expiry**; N/A if no flags (no-expiry flag is a defect, §10) *(wired)* | | | Manual |
| 5 | Progressive-delivery plan — canary / blue-green / staged (§10; `docs/operations/progressive-delivery.md`); N/A at Stage 1 with reason *(wired)* | | | Manual |
| 6 | **Post-deploy smoke gate wired (deploy → smoke → rollback-on-fail), and smoke run at each promotion boundary** incl. the canary/green slice before widening (`docs/operations/progressive-delivery.md`); result recorded *(tested)* | | | Manual |
| 7 | Smoke test **referenced** in RUNBOOK or a workflow *(documented)* | | | **Auto:** `deployable-ready.sh` |
| 8 | Monitoring / alerts wired on the change's critical paths (`DEVELOPMENT-STANDARDS.md` §3) *(wired)* | | | Manual |
| 9 | Supply-chain CI gates green — SBOM + provenance (§14) *(documented)* | | | **Auto:** `ci-gates.sh <workflow>` |
| 10 | RUNBOOK has a **Deploy** section + a **Rollback** section *(documented)* | | | **Auto:** `deployable-ready.sh` |
| 11 | CHANGELOG entry recorded for this release (§15) | | | Manual |

## Worked example — TypeScript/Node reference profile (a deployable HTTP service, no DB change this release)

| # | Item | Applies? | Evidence | Check |
|---|------|----------|----------|-------|
| 1 | Rollback declared *(documented)* | Y | RUNBOOK §5 Rollback: flag-off → redeploy previous digest | Auto ✅ |
| 2 | Rollback tested *(tested)* | Y | staging rollback drill run 2026-06-08, screenshot in release record | Manual ✅ |
| 3 | Migration reversible *(tested)* | **N/A** | no schema change this release | — |
| 4 | Flags owner + expiry *(wired)* | Y | `checkout-v2` flag — owner @release-mgr, expiry 2026-07-01 (flag registry) | Manual ✅ |
| 5 | Progressive delivery *(wired)* | Y | staged: 10% canary → full, watch error rate (§9) | Manual ✅ |
| 6 | Smoke gate + multi-stage *(tested)* | Y | smoke gate in `deploy-prod` (rollback-on-fail); canary smoked before widening; run #1423 green | Manual ✅ |
| 7 | Smoke referenced *(documented)* | Y | `smoke` step in `deploy.yml` + RUNBOOK §4 | Auto ✅ |
| 8 | Monitoring/alerts *(wired)* | Y | Sentry alert rule + p95 latency alert on the changed route (`DEVELOPMENT-STANDARDS.md` §3) | Manual ✅ |
| 9 | Supply-chain gates *(documented)* | Y | `gate-sbom` + `gate-provenance` green (profile ci.yml) | Auto ✅ |
| 10 | RUNBOOK Deploy + Rollback *(documented)* | Y | RUNBOOK §4, §5 | Auto ✅ |
| 11 | CHANGELOG entry | Y | CHANGELOG `## [1.4.0]` | Manual ✅ |

> A library or CLI marks the whole check **N/A — not a deployable service** (no promotion to a running environment); `deployable-ready.sh` skip-passes such a project automatically.
