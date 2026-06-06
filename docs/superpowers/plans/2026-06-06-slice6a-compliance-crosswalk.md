# Slice 6a: Compliance Crosswalk + Responsibility Boundary — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Ship the first pillar of the enterprise addendum — `docs/enterprise/README.md` (index + responsibility boundary) and `docs/enterprise/compliance-crosswalk.md` (kit controls → SOC 2 Security + Privacy + ISO 27001:2022 Annex A, with a privacy/data-protection family and an honest Kit-enforced/Kit-assisted/Org-owned column).

**Architecture:** Pure documentation. Maps controls the kit *already enforces* (no new enforcement, no gate, no code). A column-structured crosswalk so future frameworks (NIST/PCI/27701) are a cheap re-index later. Generic/portable; privacy rows are N/A-with-reason for no-PII adopters.

**Tech Stack:** Markdown · `conformance/check-links.sh`.

**Design source:** `docs/superpowers/specs/2026-06-06-slice6-enterprise-umbrella-design.md` §4a. Verified framework scaffolding: SOC 2 Common Criteria CC1–CC9 + Privacy P1.0–P8.0; ISO 27001:2022 Annex A themes A.5 (Organizational), A.6 (People), A.7 (Physical), A.8 (Technological).

---

## Task 1: `docs/enterprise/README.md` — index + responsibility boundary

**Files:**
- Create: `docs/enterprise/README.md`

- [ ] **Step 1: Write the file** with exactly this content:

```markdown
# Enterprise Addendum

Governance, compliance, and privacy guidance for organizations adopting this kit. This addendum **hangs off** the authoritative docs (`../../CLAUDE.md`, `../../DEVELOPMENT-STANDARDS.md`, `../../DEVELOPMENT-PROCESS.md`) and never overrides them — where they overlap, the governing docs win.

## Contents

| Doc | Purpose |
|-----|---------|
| [compliance-crosswalk.md](compliance-crosswalk.md) | Maps the controls this kit enforces to SOC 2 (Security + Privacy) and ISO 27001:2022 Annex A. |
| secrets-at-scale.md *(Slice 6b)* | Managed-secret-store contract (Vault/KMS) + secret-manager client by stack. |
| ratification-rbac.md *(Slice 6c)* | Which roles may ratify what; the governed-exception process. |
| [../../conformance/audit-evidence-checklist.md](../../conformance/audit-evidence-checklist.md) *(Slice 6d)* | Per-control evidence checklist for an audit. |

## What this kit does — and does not — cover

This kit is a **portable SDLC framework**, not a compliance program. It bakes in the *engineering* controls that produce audit evidence (CI quality gates, supply-chain integrity, branch protection, agent governance, audit logging, security primitives). It **maps** those to framework controls so you can show an auditor where the evidence lives.

It does **not** run your compliance or privacy *program*. The following control families are **Org-owned** (the kit may assist, but the organization owns them):

- **Personnel / HR security** — background checks, onboarding/offboarding, security training.
- **Physical & environmental security** — facilities, media handling, equipment.
- **Vendor / third-party risk management** — supplier due diligence, contracts, ongoing monitoring (incl. affiliate/partner data-sharing agreements).
- **Business continuity / disaster recovery** — beyond the technical RUNBOOK DR section (BIA, tested recovery, alternate sites).
- **Privacy program** — the kit provides PII/consent/erasure *primitives* and maps them, but the organization owns its privacy program: lawful basis, notices, consent records, data-subject-request handling, retention schedules, and **children's-data obligations (COPPA / GDPR minors' provisions / CCPA-CPRA)** where applicable.

## Responsibility legend

Every crosswalk row carries one of:

- **Kit-enforced** — the kit mechanically enforces this (a CI gate, a guard hook, branch protection); evidence is produced automatically.
- **Kit-assisted** — the kit provides patterns/primitives/standards, but the team must apply them and produce evidence.
- **Org-owned** — outside the kit's scope; the organization owns the control and its evidence.

> A map that hides its own edges is misleading. "Kit-assisted" and "Org-owned" are first-class, honest outcomes — not gaps to paper over.
```

- [ ] **Step 2: Verify links**

Run: `sh conformance/check-links.sh ; echo "exit=$?"`
Expected: `exit=0`. (Note: `secrets-at-scale.md` and `ratification-rbac.md` are referenced without links until 6b/6c create them — they appear as plain text above, not `[links]`, so check-links will not flag them. The `audit-evidence-checklist.md` link is to a file not yet created in 6d — verify check-links tolerates it; **if check-links flags the not-yet-created `audit-evidence-checklist.md` link, change that one table cell to plain text `conformance/audit-evidence-checklist.md *(Slice 6d)*` (no link) and re-run.**)

- [ ] **Step 3: Commit**

```bash
git add docs/enterprise/README.md
git commit -m "$(printf 'docs(enterprise): addendum index + responsibility boundary (6a)\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Task 2: `docs/enterprise/compliance-crosswalk.md` — the crosswalk

**Files:**
- Create: `docs/enterprise/compliance-crosswalk.md`

- [ ] **Step 1: Verify the framework control identifiers are current**

Before writing, confirm via WebSearch (wrong identifiers are the top risk):
- SOC 2 Common Criteria series CC1–CC9 and their topics; Privacy criteria P1.0–P8.0 topics.
- ISO 27001:2022 Annex A control numbers used below (spot-check at least: A.8.8 management of technical vulnerabilities; A.8.28 secure coding; A.8.15 logging; A.8.16 monitoring activities; A.8.24 use of cryptography; A.5.34 privacy and protection of PII; A.8.10 information deletion; A.8.32 change management; A.8.4 access to source code; A.8.5 secure authentication; A.8.2 privileged access rights; A.5.19–A.5.22 supplier relationships; A.8.9 configuration management; A.5.29/A.5.30 + A.8.13/A.8.14 continuity & backup).
Correct any identifier that has drifted; keep the control *name* beside the number so a wrong number is self-evident.

- [ ] **Step 2: Write the file** with this content (apply any identifier corrections from Step 1):

```markdown
# Compliance Crosswalk — SOC 2 & ISO 27001:2022

Maps the controls **this kit enforces or assists** to SOC 2 Trust Services Criteria (Security Common Criteria + Privacy) and ISO/IEC 27001:2022 Annex A. Use it to show an auditor *where the evidence lives* in a repo built with this kit.

**How to read it:** the `Responsibility` column is the honest part — **Kit-enforced** (mechanical, automatic evidence), **Kit-assisted** (kit gives the pattern; team produces evidence), **Org-owned** (see [README responsibility boundary](README.md)). Rows that don't apply to a given project are marked **N/A (reason)** — e.g. a service with no personal data marks the Privacy rows N/A.

**Frameworks covered:** SOC 2 (Security + Privacy categories) · ISO 27001:2022 Annex A.
**Extensible the same way (not yet mapped):** NIST CSF 2.0 (organizing lens — a re-mapping of the same controls), PCI-DSS (*triggers only if you process/store/transmit cardholder data — outsource/tokenize to a compliant processor to keep it out of scope*), ISO 27701 (privacy ISMS extension if certification is later required). Adding any of these = appending a column against the same kit controls.

## Security & engineering controls

| Kit control | Where in the kit | SOC 2 | ISO 27001:2022 | Evidence artifact | Responsibility |
|-------------|------------------|-------|----------------|-------------------|----------------|
| Lint / type-check / test + 80% coverage | STANDARDS §14 gates 1–4; `profiles/*/ci.yml` | CC8.1 | A.8.28, A.8.29 | CI gate run logs | Kit-enforced |
| Secret scanning (no committed secrets) | §14 gate 5; `gate-secret-scan` | CC6.1 | A.8.28, A.5.15 | secret-scan CI log | Kit-enforced |
| Dependency vulnerability scan | §14 gate 6; `gate-dep-scan` | CC7.1 | A.8.8 | dep-scan CI log | Kit-enforced |
| SBOM + build-provenance attestation | §14 gate 7; `gate-sbom` / `gate-provenance` | CC7.1, CC9.2 | A.8.8, A.5.21 | SBOM file, attestation | Kit-enforced |
| Least-privilege OIDC in CI (push-only provenance job) | §14 hardening note; `profiles/*/ci.yml` | CC6.1, CC6.3 | A.8.2, A.5.15 | workflow definition | Kit-enforced |
| Branch protection · builder ≠ sole merger | §14 governance; PROCESS §12 | CC8.1, CC6.1 | A.8.32, A.8.4 | PR approval records | Kit-enforced |
| Change management via PR + green CI | §14; PROCESS §12 | CC8.1 | A.8.32 | merge history | Kit-enforced |
| Agent autonomy guard · human gates for irreversible actions | PROCESS §13; `.claude/`, `conformance/agent-autonomy.sh` | CC6.1, CC6.3, CC8.1 | A.8.2, A.5.15 | guard hook, agent-autonomy.sh | Kit-enforced |
| Immutable audit logging (who/what/when/resource) | STANDARDS §2 (Audit logging) | CC7.2, CC7.3 | A.8.15, A.8.16 | audit log stream | Kit-assisted |
| Secrets management (env + managed store) | §2; secrets-at-scale.md *(6b)* | CC6.1 | A.8.24, A.5.15, A.8.9 | `.env.example`, store config | Kit-assisted |
| Input validation / injection prevention | §2 | CC6.1, CC6.6 | A.8.28, A.8.26 | code, tests | Kit-assisted |
| Authentication & authorization (hashing, least-priv tokens) | §2 | CC6.1, CC6.2, CC6.3 | A.8.5, A.5.15, A.5.18 | code, config | Kit-assisted |
| Encryption at rest & in transit | §2 (PII) | CC6.1, CC6.7 | A.8.24 | infra/config | Kit-assisted |
| Observability / monitoring | STANDARDS §3 | CC7.2 | A.8.15, A.8.16 | dashboards, alerts | Kit-assisted |
| Config in environment (15-factor) | STANDARDS §13; `conformance/15-factor-checklist.md` | CC8.1 | A.8.9 | 15-factor checklist | Kit-assisted |
| Architecture decisions recorded (ADRs) | PROCESS; `docs/ADR-*` | CC1.2, CC3.1 | A.5.4, A.8.27 | ADR files | Kit-assisted |
| RUNBOOK · DR / rollback | DoD (CLAUDE.md); `RUNBOOK-TEMPLATE.md` | CC7.4, CC7.5 | A.5.29, A.5.30, A.8.13, A.8.14 | RUNBOOK | Kit-assisted |
| Cost governance · rate-limiting external/LLM spend | §2 (Cost management) | CC7.1 | A.8.6 | config, alerts | Kit-assisted |
| Personnel / HR security | — | CC1.4 | A.6.1–A.6.6 | — | Org-owned |
| Physical & environmental security | — | CC6.4 | A.7.1–A.7.14 | — | Org-owned |
| Vendor / third-party risk management | — | CC9.2 | A.5.19, A.5.20, A.5.22 | — | Org-owned |

## Privacy & data-protection family

Applies to projects handling personal data. **N/A (reason)** for projects with no personal data. The kit provides PII/consent/erasure *primitives* (STANDARDS §2) and maps them; the **privacy program is Org-owned**. Triggers to watch: **COPPA** (children's data), **GDPR** (incl. minors' provisions), **CCPA/CPRA**.

| Privacy control | Where in the kit | SOC 2 Privacy | ISO 27001:2022 | Evidence artifact | Responsibility |
|-----------------|------------------|---------------|----------------|-------------------|----------------|
| Notice / privacy communication | §2 (PII) | P1.0 | A.5.34 | privacy notice | Org-owned |
| Choice & consent (incl. age-gating for children's data) | §2 | P2.0 | A.5.34 | consent records | Org-owned |
| Collection limitation | §2 (validate at boundaries) | P3.0 | A.5.34, A.8.26 | data inventory | Kit-assisted |
| Use, retention & disposal (minimization) | §2; A.8.10 deletion | P4.0 | A.8.10, A.5.34 | retention policy | Kit-assisted |
| Data-subject access | §2 | P5.0 | A.5.34 | DSAR process | Org-owned |
| Right to erasure | §2 (deletable on request) | P4.0 | A.8.10 | erasure process + code path | Kit-assisted |
| Disclosure & third-party/affiliate data-sharing | §2 (no PII to third parties w/o consent) | P6.0 | A.5.34, A.5.19, A.5.20 | data-sharing agreements | Org-owned |
| Data quality | §2 | P7.0 | A.5.34 | validation | Kit-assisted |
| Privacy monitoring & enforcement | §2 (audit logging); §3 | P8.0 | A.8.15, A.8.16, A.5.34 | audit log, reviews | Kit-assisted |
| PII redaction in logs | §2 (redact in logs) | P4.0, P8.0 | A.8.15, A.5.34 | log config | Kit-assisted |

> **Children's data:** if a project is directed to or knowingly collects data from children, COPPA (US) and GDPR Art. 8 (EU) impose heightened consent/age-verification duties the kit does **not** implement — they are Org-owned, surfaced here so they are not missed.
```

- [ ] **Step 3: Verify links + no over-claim**

Run: `sh conformance/check-links.sh ; echo "exit=$?"` → expect `exit=0`.
Run a self-check that every "Where in the kit" reference resolves: grep that `DEVELOPMENT-STANDARDS.md` has §14/§2/§3/§13, `DEVELOPMENT-PROCESS.md` has §12/§13, `conformance/15-factor-checklist.md` and `conformance/agent-autonomy.sh` exist, `RUNBOOK-TEMPLATE.md` exists. Any reference that doesn't resolve must be corrected (not deleted) to the right location.
Confirm no row marked **Kit-enforced** lacks a real mechanism (gate id, guard, branch protection).

- [ ] **Step 4: Commit**

```bash
git add docs/enterprise/compliance-crosswalk.md
git commit -m "$(printf 'docs(enterprise): SOC2 + ISO27001 compliance crosswalk with privacy family (6a)\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Task 3: VERSION, CHANGELOG, ROADMAP

**Files:**
- Modify: `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-KIT.md`

- [ ] **Step 1: Bump VERSION** → write `VERSION` to exactly:
```
2.9.0
```

- [ ] **Step 2: Prepend CHANGELOG entry** above `## [2.8.0] - 2026-06-06`:
```markdown
## [2.9.0] - 2026-06-06

Slice 6a — Enterprise addendum, pillar 1: the compliance crosswalk. First of four sub-slices (umbrella spec: `docs/superpowers/specs/2026-06-06-slice6-enterprise-umbrella-design.md`).

### Added
- `docs/enterprise/README.md` — addendum index + an explicit **responsibility boundary** (Kit-enforced / Kit-assisted / Org-owned), naming what the kit does not cover (HR, physical, vendor risk, BCP, the privacy program).
- `docs/enterprise/compliance-crosswalk.md` — maps the controls the kit enforces/assists to **SOC 2 (Security CC + Privacy P) + ISO 27001:2022 Annex A**, with a dedicated **privacy/data-protection family** (data-subject rights, consent & age-gating, retention, third-party sharing; COPPA/GDPR-minors/CCPA named as triggers). Column-structured so NIST CSF / PCI-DSS / ISO 27701 are a cheap re-index later.

### Note
Pure documentation — no new gate, no code, no profile changes. The crosswalk *maps* controls; it does not mandate new ones. Privacy rows are N/A-with-reason for no-PII projects. Definition of Done unchanged.
```

- [ ] **Step 3: Add ROADMAP row** — in `docs/ROADMAP-KIT.md`, insert after the `5e ✅` row and before the `| 6 |` row:
```markdown
| 6a ✅ | **Compliance crosswalk** *(shipped v2.9.0)* | standards §2/§14 | `docs/enterprise/{README,compliance-crosswalk}.md` — SOC 2 + ISO 27001:2022 + privacy family | `check-links.sh` + audit-evidence (6d) |
```
And update the `| 6 |` row label to indicate it is now in progress (change `| 6 |` to `| 6 🔄 |` and append " — *6a shipped; 6b–6d next*" to its reference cell). If that edit is ambiguous, leave the `| 6 |` row as-is and rely on the new `6a ✅` row.

- [ ] **Step 4: Verify**
```bash
cat VERSION   # 2.9.0
grep -n "2.9.0" CHANGELOG.md docs/ROADMAP-KIT.md
sh conformance/check-links.sh ; echo "links exit=$?"   # exit=0
```

- [ ] **Step 5: Commit**
```bash
git add VERSION CHANGELOG.md docs/ROADMAP-KIT.md
git commit -m "$(printf 'chore(release): 2.9.0 — enterprise addendum pillar 1 (compliance crosswalk)\n\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>')"
```

---

## Task 4: Final 6a validation

**Files:** none (verification only; fix-forward if needed).

- [ ] **Step 1: Links + structure**
```bash
sh conformance/check-links.sh ; echo "links exit=$?"
ls -1 docs/enterprise/
```
Expected: `links exit=0`; `README.md` + `compliance-crosswalk.md` present.

- [ ] **Step 2: Every kit-referenced anchor resolves**
```bash
for ref in "## 14" "## 2" "## 3" "## 13" ; do grep -q "$ref" DEVELOPMENT-STANDARDS.md && echo "STANDARDS $ref ok" || echo "STANDARDS $ref MISSING"; done
for ref in "## 12" "## 13" ; do grep -q "$ref" DEVELOPMENT-PROCESS.md && echo "PROCESS $ref ok" || echo "PROCESS $ref MISSING"; done
ls conformance/15-factor-checklist.md conformance/agent-autonomy.sh RUNBOOK-TEMPLATE.md >/dev/null 2>&1 && echo "referenced files ok" || echo "referenced files MISSING"
```
Expected: all `ok`.

- [ ] **Step 3: No over-claim audit**
Read `compliance-crosswalk.md`; confirm every **Kit-enforced** row names a real mechanism present in the repo (a `gate-*` id, branch protection, the guard hook). Any that can't be substantiated must be downgraded to **Kit-assisted**. Confirm no existing conformance script regressed:
```bash
for c in ci-gates profile-completeness agent-autonomy inception-done; do echo -n "$c: "; sh conformance/$c.sh >/dev/null 2>&1 && echo ok || echo "check (may need args)"; done
```
(Some scripts need arguments — `ci-gates`/`agent-autonomy` may print usage; that's fine, they are unchanged by this doc-only slice.)

No commit unless a defect is found; fix-forward and re-run Steps 1–3.

---

## Self-review (author)

- **Spec coverage (umbrella §4a):** README + responsibility boundary → Task 1; crosswalk + SOC2 Security/Privacy + ISO + privacy family → Task 2; version/changelog/roadmap → Task 3; validation → Task 4.
- **No placeholders:** full file contents inline; control identifiers are concrete (verified scaffolding) with a Step-1 re-verification gate in Task 2.
- **Honesty column enforced:** Task 4 Step 3 is an explicit over-claim audit (no Kit-enforced row without a real mechanism).
- **Additive/non-destructive:** only new files + meta; no profile or governing-doc change in 6a (those come in 6b/6c). check-links + existing conformance must stay green.
