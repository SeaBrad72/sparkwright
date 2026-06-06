# Enterprise Addendum

Governance, compliance, and privacy guidance for organizations adopting this kit. This addendum **hangs off** the authoritative docs (`../../CLAUDE.md`, `../../DEVELOPMENT-STANDARDS.md`, `../../DEVELOPMENT-PROCESS.md`) and never overrides them — where they overlap, the governing docs win.

## Contents

| Doc | Purpose |
|-----|---------|
| [compliance-crosswalk.md](compliance-crosswalk.md) | Maps the controls this kit enforces to SOC 2 (Security + Privacy) and ISO 27001:2022 Annex A. |
| [secrets-at-scale.md](secrets-at-scale.md) | Managed-secret-store contract (Vault/KMS) + secret-manager client by stack. |
| ratification-rbac.md *(Slice 6c)* | Which roles may ratify what; the governed-exception process. |
| conformance/audit-evidence-checklist.md *(Slice 6d)* | Per-control evidence checklist for an audit. |

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
