# Compliance Crosswalk — SOC 2 · ISO 27001:2022 · NIST SSDF

Maps the controls **this kit enforces or assists** to SOC 2 Trust Services Criteria (Security Common Criteria + Privacy) and ISO/IEC 27001:2022 Annex A. Use it to show an auditor *where the evidence lives* in a repo built with this kit.

**How to read it:** the `Responsibility` column is the honest part — **Kit-enforced** (mechanical, automatic evidence), **Kit-assisted** (kit gives the pattern; team produces evidence), **Org-owned** (see [README responsibility boundary](README.md)). Rows that don't apply to a given project are marked **N/A (reason)** — e.g. a service with no personal data marks the Privacy rows N/A.

**Frameworks covered:** SOC 2 (Security + Privacy categories) · ISO 27001:2022 Annex A · NIST SSDF (SP 800-218 v1.1).
**Extensible the same way (not yet mapped):** NIST CSF 2.0 (organizing lens — a re-mapping of the same controls), PCI-DSS (*triggers only if you process/store/transmit cardholder data — outsource/tokenize to a compliant processor to keep it out of scope*), ISO 27701 (privacy ISMS extension if certification is later required). Adding any of these = appending a column against the same kit controls.

## Security & engineering controls

| Kit control | Where in the kit | SOC 2 | ISO 27001:2022 | NIST SSDF (800-218) | Evidence artifact | Responsibility |
|-------------|------------------|-------|----------------|---------------------|-------------------|----------------|
| Lint / type-check / test + 80% coverage | STANDARDS §14 gates 1–3; `profiles/*/ci.yml` | CC8.1 | A.8.28 (secure coding), A.8.29 (security testing in dev) | PW.7, PW.8 | CI gate run logs | Kit-enforced |
| Reproducible production build | STANDARDS §14 gate 4; `gate-build` | CC8.1 | A.8.25 (secure development life cycle), A.8.31 (separation of dev/test/prod) | PW.6, PS.3 | build CI log / artifact | Kit-enforced |
| Secret scanning (no committed secrets) | STANDARDS §14 gate 5; `gate-secret-scan` | CC6.1 | A.8.28 (secure coding), A.5.15 (access control) | PW.8, PS.1 | secret-scan CI log | Kit-enforced |
| Dependency vulnerability scan | STANDARDS §14 gate 6; `gate-dep-scan` | CC7.1 | A.8.8 (management of technical vulnerabilities) | PW.4, RV.1 | dep-scan CI log | Kit-enforced |
| SBOM + build-provenance attestation | STANDARDS §14 gate 7; `gate-sbom` / `gate-provenance` | CC7.1, CC9.2 | A.8.8 (management of technical vulnerabilities), A.5.21 (managing information security in the ICT supply chain) | PS.2, PS.3 (SLSA Build L2) | SBOM file, attestation | Kit-enforced |
| Least-privilege OIDC in CI (push-only provenance job) | STANDARDS §14 hardening note; `profiles/*/ci.yml` | CC6.1, CC6.3 | A.8.2 (privileged access rights), A.5.15 (access control) | PO.3, PO.5 | workflow definition | Kit-enforced |
| Branch protection · builder ≠ sole merger | STANDARDS §14 governance; PROCESS §12 | CC8.1, CC6.1 | A.8.32 (change management), A.8.4 (access to source code) | PS.1, PW.7 | PR approval records | Kit-enforced |
| Change management via PR + green CI | STANDARDS §14; PROCESS §12 | CC8.1 | A.8.32 (change management) | PO.3, PS.1 | merge history | Kit-enforced |
| Agent autonomy guard · human gates for irreversible actions | PROCESS §13; `.claude/`, `conformance/agent-autonomy.sh` | CC6.1, CC6.3, CC8.1 | A.8.2 (privileged access rights), A.5.15 (access control) | PO.5, PS.1 | guard hook, agent-autonomy.sh | Kit-enforced |
| Immutable audit logging (who/what/when/resource) | STANDARDS §2 (Audit logging) | CC7.2, CC7.3 | A.8.15 (logging), A.8.16 (monitoring activities) | PO.5 | audit log stream | Kit-assisted |
| Secrets management (env + managed store) | STANDARDS §2; secrets-at-scale.md *(6b)* | CC6.1 | A.8.24 (use of cryptography), A.5.15 (access control), A.8.9 (configuration management) | PO.3, PO.5 | `.env.example`, store config | Kit-assisted |
| Input validation / injection prevention | STANDARDS §2 | CC6.1, CC6.6 | A.8.28 (secure coding), A.8.26 (application security requirements) | PW.5 | code, tests | Kit-assisted |
| Authentication & authorization (hashing, least-priv tokens) | STANDARDS §2 | CC6.1, CC6.2, CC6.3 | A.8.5 (secure authentication), A.5.15 (access control), A.5.18 (access rights management) | PW.5 | code, config | Kit-assisted |
| Encryption at rest & in transit | STANDARDS §2 (PII) | CC6.1, CC6.7 | A.8.24 (use of cryptography) | PW.5, PW.9 | infra/config | Kit-assisted |
| Observability / monitoring | STANDARDS §3 | CC7.2 | A.8.15 (logging), A.8.16 (monitoring activities) | PO.5 | dashboards, alerts | Kit-assisted |
| Config in environment (15-factor) | STANDARDS §13; `conformance/15-factor-checklist.md` | CC8.1 | A.8.9 (configuration management) | PW.9 | 15-factor checklist | Kit-assisted |
| Architecture decisions recorded (ADRs) | PROCESS; `docs/ADR-*` | CC1.2, CC3.1 | A.5.4 (management responsibilities), A.8.27 (secure system architecture) | PW.1, PW.2 | ADR files | Kit-assisted |
| RUNBOOK · DR / rollback | DoD (CLAUDE.md); `templates/RUNBOOK-TEMPLATE.md` | CC7.4, CC7.5 | A.5.29 (information security during disruption), A.5.30 (ICT readiness for business continuity), A.8.13 (information backup), A.8.14 (redundancy of information processing facilities) | — | RUNBOOK | Kit-assisted |
| Cost governance · rate-limiting external/LLM spend | STANDARDS §2 (Cost management) | CC7.1 | A.8.6 (capacity management) | — | config, alerts | Kit-assisted |
| Personnel / HR security | — | CC1.4 | A.6.1 (screening), A.6.2 (terms and conditions of employment), A.6.3 (information security awareness), A.6.4 (disciplinary process), A.6.5 (responsibilities after termination), A.6.6 (confidentiality agreements) | — | — | Org-owned |
| Physical & environmental security | — | CC6.4 | A.7.1–A.7.14 (physical controls) | — | — | Org-owned |
| Vendor / third-party risk management | — | CC9.2 | A.5.19 (information security in supplier relationships), A.5.20 (addressing security within supplier agreements), A.5.22 (monitoring, review and change management of supplier services) | PW.4 | — | Org-owned |
| Agent/runtime MCP capability gate (deny-by-default) | `.claude/hooks/guard-core.sh` (`guard_check_mcp`) · `.claude/mcp-policy.json` | CC6.1, CC6.3 | A.8.2 (privileged access rights), A.5.15 (access control) | PO.5, PS.1 | `conformance/mcp-policy.sh` + `agent-autonomy.sh` MCP cases — gates MCP tool capability **by name**; the `net.egress` class is a name-match speed bump, not egress containment | Kit-enforced |
| Agent/runtime platform boundary · network-egress allowlist | `docs/enterprise/platform-safety-boundary.md` · `../operations/egress-control.md` | CC6.6, CC6.7 | A.8.20 (networks security), A.8.21 (security of network services), A.8.22 (segregation of networks), A.8.23 (web filtering) | PO.5 | default-deny egress reference + RUNBOOK attestation, verified by `conformance/egress-policy.sh` | Kit-assisted |
| Agent/runtime platform boundary · separate prod credentials (SoD) | `docs/enterprise/platform-safety-boundary.md` · `../operations/containment.md` | CC6.1, CC6.3 | A.5.15 (access control), A.5.18 (access rights), A.8.2 (privileged access rights) | PO.5 | break-glass workflow + RUNBOOK attestation, verified by `conformance/containment-ready.sh` | Kit-assisted |
| Agent/runtime platform boundary · sandboxed filesystem | `docs/enterprise/platform-safety-boundary.md` · `../operations/containment.md` | CC6.1 | A.8.31 (separation of development, test and production environments) | PO.5 | read-only-mount reference + RUNBOOK attestation, verified by `conformance/containment-ready.sh` | Kit-assisted |
| Agent/runtime platform boundary · scoped short-lived tokens | `docs/enterprise/platform-safety-boundary.md` · `../operations/containment.md` | CC6.1 | A.5.17 (authentication information), A.8.2 (privileged access rights) | PO.5 | OIDC->role / short-TTL reference + RUNBOOK attestation, verified by `conformance/containment-ready.sh` | Kit-assisted |

## Privacy & data-protection family

Applies to projects handling personal data. **N/A (reason)** for projects with no personal data. The kit provides PII/consent/erasure *primitives* (STANDARDS §2) and maps them; the **privacy program is Org-owned**. The data-classification scheme + DPIA-lite live in [data-governance.md](data-governance.md). Triggers to watch: **COPPA** (children's data), **GDPR** (incl. minors' provisions), **CCPA/CPRA**.

| Privacy control | Where in the kit | SOC 2 Privacy | ISO 27001:2022 | Evidence artifact | Responsibility |
|-----------------|------------------|---------------|----------------|-------------------|----------------|
| Notice / privacy communication | STANDARDS §2 (PII) | P1.0 (notice) | A.5.34 (privacy and protection of PII) | privacy notice | Org-owned |
| Choice & consent (incl. age-gating for children's data) | STANDARDS §2 | P2.0 (choice and consent) | A.5.34 (privacy and protection of PII) | consent records | Org-owned |
| Collection limitation | STANDARDS §2 (validate at boundaries) | P3.0 (collection) | A.5.34 (privacy and protection of PII), A.8.26 (application security requirements) | data inventory | Kit-assisted |
| Use, retention & disposal (minimization) | STANDARDS §2 | P4.0 (use, retention, and disposal) | A.8.10 (information deletion), A.5.34 (privacy and protection of PII) | retention policy | Kit-assisted |
| Data-subject access | STANDARDS §2 | P5.0 (access) | A.5.34 (privacy and protection of PII) | DSAR process | Org-owned |
| Right to erasure | STANDARDS §2 (deletable on request) | P4.0 (use, retention, and disposal) | A.8.10 (information deletion) | erasure process + code path | Kit-assisted |
| Disclosure & third-party/affiliate data-sharing | STANDARDS §2 (no PII to third parties w/o consent) | P6.0 (disclosure and notification) | A.5.34 (privacy and protection of PII), A.5.19 (information security in supplier relationships), A.5.20 (addressing security within supplier agreements) | data-sharing agreements | Org-owned |
| Data quality | STANDARDS §2 | P7.0 (quality) | A.5.34 (privacy and protection of PII) | validation | Kit-assisted |
| Privacy monitoring & enforcement | STANDARDS §2 (audit logging); §3 | P8.0 (monitoring and enforcement) | A.8.15 (logging), A.8.16 (monitoring activities), A.5.34 (privacy and protection of PII) | audit log, reviews | Kit-assisted |
| PII redaction in logs | STANDARDS §2 (redact in logs) | P4.0 (use, retention, and disposal), P8.0 (monitoring and enforcement) | A.8.15 (logging), A.5.34 (privacy and protection of PII) | log config | Kit-assisted |

> **Children's data:** if a project is directed to or knowingly collects data from children, COPPA (US) and GDPR Art. 8 (EU) impose heightened consent/age-verification duties the kit does **not** implement — they are Org-owned, surfaced here so they are not missed.
