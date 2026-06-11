# Conformance Check — Audit Evidence

Proves that a repo built with this kit can produce the **evidence** an auditor expects for the controls mapped in [`../docs/enterprise/compliance-crosswalk.md`](../docs/enterprise/compliance-crosswalk.md). **Checklist-type**, run at the **Review gate** / before an audit (`../DEVELOPMENT-PROCESS.md` §7). The capstone of the enterprise addendum (`../docs/enterprise/README.md`).

## How to use

Copy this file into your project (or your audit/review record). For each control, fill **Present?** (`Y` / `N` / `N/A + reason`) and point **Evidence** at the concrete artifact. For **Auto** rows, run the named command and attach its output. A reviewer (security owner for governing controls — see [`../docs/enterprise/ratification-rbac.md`](../docs/enterprise/ratification-rbac.md)) signs off only when every applicable control has evidence **or** a governed, time-boxed exception on record. A waived control cites its exception ID; nothing is silently skipped.

## Security & engineering controls

| Control | Crosswalk ref (SOC 2 / ISO / SSDF) | Evidence artifact (where) | Check | Present? |
|---------|-----------------------------------|---------------------------|-------|----------|
| Lint / type-check / test + coverage | CC8.1 / A.8.28–29 / PW.7, PW.8 | CI gate run logs (gates 1–3) | **Auto:** `sh conformance/ci-gates.sh .github/workflows/ci.yml` | |
| Reproducible build | CC8.1 / A.8.25 / PW.6, PS.3 | build CI log / artifact (gate-build) | **Auto:** `sh conformance/ci-gates.sh .github/workflows/ci.yml` | |
| Secret scanning | CC6.1 / A.8.28 / PW.8, PS.1 | secret-scan CI log (gate-secret-scan) | **Auto:** `sh conformance/ci-gates.sh …` | |
| Dependency vulnerability scan | CC7.1 / A.8.8 / PW.4, RV.1 | dep-scan CI log (gate-dep-scan) | **Auto:** `sh conformance/ci-gates.sh …` | |
| SBOM + build provenance (SLSA Build L2) | CC7.1, CC9.2 / A.8.8, A.5.21 / PS.2, PS.3 | SBOM file + attestation (gate-sbom / gate-provenance) | **Auto:** `sh conformance/ci-gates.sh …` + the SBOM artifact | |
| Container image supply-chain (if service image) | CC7.1, CC8.1 / A.8.25, A.8.28 / PS.2, PS.3 | image SBOM + digest-bound provenance attestation | **Auto (conditional):** `sh conformance/container-supply-chain.sh` | |
| Network egress · default-deny allowlist (if networked) | CC6.6, CC6.7 / A.8.20–A.8.23 / PO.5 | egress reference + RUNBOOK attestation (declared + wired) | **Auto (conditional):** `sh conformance/egress-policy.sh` | |
| Least-privilege OIDC in CI | CC6.1, CC6.3 / A.8.2 / PO.3, PO.5 | the workflow's push-only `provenance` job (no workflow-level `id-token`) | Manual (review the workflow) | |
| Branch protection · builder ≠ sole merger | CC8.1, CC6.1 / A.8.32, A.8.4 / PS.1, PW.7 | branch-protection settings + PR approval records | **Auto (where reachable):** `sh conformance/branch-protection.sh` + PR history | |
| Change management via PR + green CI | CC8.1 / A.8.32 / PO.3, PS.1 | merge history (every change via reviewed PR with green CI) | Manual (PR / merge records) | |
| Agent autonomy · human gates for irreversible actions | CC6.1, CC6.3 / A.8.2 / PO.5, PS.1 | guard hook denies the gated set | **Auto:** `sh conformance/agent-autonomy.sh` | |
| Inception completed (project resumable cold) | — | the Inception gate passes | **Auto:** `sh conformance/inception-done.sh` | |
| Profile completeness (chosen stack) | — | the profile fills all sections; companion CI conformant | **Auto:** `sh conformance/profile-completeness.sh` | |
| Docs link integrity | A.5.x (documentation) | all relative links resolve | **Auto:** `sh conformance/check-links.sh` | |
| 15-factor architecture (services) | CC8.1 / A.8.9 / PW.9 | the completed checklist | **Checklist:** `conformance/15-factor-checklist.md` | |
| Immutable audit logging | CC7.2, CC7.3 / A.8.15, A.8.16 | audit log stream (who/what/when/resource) | Manual | |
| Secrets management & secrets-at-scale | CC6.1 / A.8.24 / PO.3, PO.5 | `.env.example` + managed-store config (→ `../docs/enterprise/secrets-at-scale.md`) | Manual | |
| Input validation / injection prevention | CC6.1, CC6.6 / A.8.28, A.8.26 / PW.5 | schema-validation code + tests | Manual | |
| Authentication & authorization | CC6.1–6.3 / A.8.5, A.5.15 / PW.5 | auth code/config | Manual | |
| Encryption at rest & in transit | CC6.1, CC6.7 / A.8.24 / PW.5, PW.9 | infra/config | Manual | |
| Observability / monitoring | CC7.2 / A.8.15, A.8.16 | dashboards, alerts | Manual | |
| Incident response · postmortem | CC7.3, CC7.4 / A.5.24–A.5.28 | postmortem record(s) (`templates/POSTMORTEM-TEMPLATE.md`) + action-item backlog links | Manual | |
| Architecture decisions recorded | CC1.2, CC3.1 / A.5.4 / PW.1, PW.2 | `docs/ADR-*` files | Manual (files present) | |
| RUNBOOK · DR / rollback | CC7.4, CC7.5 / A.5.29, A.8.13 | RUNBOOK | Manual (file present) | |
| DR drill · backup-restore | CC7.5, A1.2 / A.5.29, A.8.13, A.8.14 | BIA (`docs/continuity/BIA.md`) + RUNBOOK §6 + recorded drill date + drill log | **Auto (conditional):** `sh conformance/dr-ready.sh` | |
| Resilience · load/soak + fault-injection | A1.2, A1.3 / A.8.6, A.8.16 | resilience-verification records (RUNBOOK §8) + drill/load logs | **Auto (conditional):** `sh conformance/resilience-ready.sh` | |
| Release readiness · Definition of Deployable | CC8.1 / A.8.31, A.8.32 | filled `definition-of-deployable.md` + script output | **Auto (conditional):** `sh conformance/deployable-ready.sh` | |
| Cost governance · rate-limiting | CC7.1 / A.8.6 | config, budget alerts | Manual | |
| Personnel / HR security | CC1.4 / A.6.1–A.6.6 | org program (outside the kit) | Manual — **Org-owned** | |
| Physical & environmental security | CC6.4 / A.7.1–A.7.14 | org program (outside the kit) | Manual — **Org-owned** | |
| Vendor / third-party risk management | CC9.2 / A.5.19, A.5.20, A.5.22 | org program (outside the kit) | Manual — **Org-owned** | |

## Privacy & data-protection controls

Mark **N/A (no personal data)** for projects that handle none. Most are **Org-owned** — the kit assists; the program is the org's (see [`../docs/enterprise/compliance-crosswalk.md`](../docs/enterprise/compliance-crosswalk.md) privacy family and the [responsibility boundary](../docs/enterprise/README.md)).

| Control | Crosswalk ref | Evidence artifact (where) | Check | Present? |
|---------|---------------|---------------------------|-------|----------|
| Notice / privacy communication | P1.0 / A.5.34 | privacy notice | Manual — Org-owned | |
| Choice & consent (incl. age-gating) | P2.0 / A.5.34 | consent records / age-gate | Manual — Org-owned | |
| Collection limitation | P3.0 / A.5.34 | data inventory + boundary validation | Manual | |
| Use, retention & disposal | P4.0 / A.8.10, A.5.34 | retention policy + deletion path | Manual | |
| Data-subject access | P5.0 / A.5.34 | DSAR process | Manual — Org-owned | |
| Right to erasure | P4.0 / A.8.10 | erasure process + code path | Manual | |
| Disclosure & third-party/affiliate sharing | P6.0 / A.5.34, A.5.19 | data-sharing agreements | Manual — Org-owned | |
| PII redaction in logs | P4.0, P8.0 / A.8.15 | log config | Manual | |
| Privacy monitoring & enforcement | P8.0 / A.8.16, A.5.34 | audit log + reviews | Manual | |

## Governed exceptions

Any waived control above must cite a **governed exception** (`../docs/enterprise/ratification-rbac.md`): a security-owner-ratified, time-boxed record (what / why / expiry / compensating control). List active exception IDs here at review time. An expired exception means the control is back in force.

| Exception ID | Control waived | Ratified by (security owner) | Expires | Compensating control |
|--------------|----------------|------------------------------|---------|----------------------|
| | | | | |
