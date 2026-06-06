# Design — Slice 6: Enterprise Addendum (umbrella spec)

**Date:** 2026-06-06
**Status:** Approved (approach + 3 key decisions) — pending spec review
**Author:** Bradley James + agent
**Roadmap:** The FINALE. Last roadmap slice. Delivered as an umbrella design (this doc) + four ratified sub-slices (6a–6d).

---

## 1. Goal

Add the **enterprise governance layer** that lets an organization adopt this kit and demonstrate, to an auditor or assessor, that following the kit *already produces* the controls and evidence enterprise frameworks expect — plus the two governance pieces a regulated enterprise needs that the kit doesn't yet state: **secrets-at-scale** (beyond `.env`) and **ratification RBAC** (which roles may approve what). The layer is stack-neutral, additive, and dogfoods the kit's own loop (shipped as governed increments).

Comprehensiveness is guaranteed by **this umbrella spec** (the whole set is designed up front), not by bundling delivery into one PR. Each pillar keeps the kit's **contract → reference → conformance** spine.

## 2. Confirmed decisions (from brainstorming)

1. **Hybrid delivery:** one umbrella design (this doc) → four sub-slices (6a crosswalk · 6b secrets-at-scale · 6c ratification RBAC · 6d audit-evidence capstone), each its own plan → PR → human ratification. Build order **6a → 6b → 6c → 6d** (6d consumes the others).
2. **Crosswalk scope:** map the controls the kit *already enforces* to SOC 2 TSC (Security **+ Privacy** categories) + ISO 27001:2022 Annex A, with an explicit **responsibility-boundary** column (what the adopting org must own — HR, physical security, vendor mgmt, …). A complete *map with honest edges*, not a company SOC 2 program.
   - **Frameworks in 6a:** SOC 2 Security (common criteria) + **SOC 2 Privacy (P) criteria** + ISO 27001:2022 Annex A, **plus a privacy/data-protection responsibility family** (data-subject rights, consent & age-gating, retention/minimization, third-party/affiliate data-sharing — naming COPPA / GDPR-minors / CCPA-CPRA as generic triggers). Rationale: security frameworks (SOC2-Security, ISO 27001) do **not** cover privacy, which is a control *family* the kit must speak to — and unlike a re-mappable framework, privacy can't be cheaply back-filled later. Kept generic/portable; activates only for adopters handling personal data (graceful **N/A-with-reason** for no-PII projects).
   - **Deferred, documented as "extensible the same way" with trigger notes (NOT built in 6a):** NIST CSF 2.0 (voluntary organizing lens; a re-mapping of the same controls — cheap to add later), PCI-DSS (*triggers only if the org processes/stores/transmits cardholder data — outsource/tokenize to a compliant processor to keep it out of scope*), ISO 27701 (formal privacy ISMS extension if certification is later required). Adding any of these later = appending a crosswalk column against the same kit controls (a re-index pass, not a redesign).
3. **6b is stack-neutral contract + stack-aware reference table** (a "secret-manager client by stack" lookup in one doc) — **no bulk edit of the 10 profiles**; a one-line pointer is added to `profiles/_TEMPLATE.md` so future/BYO profiles route correctly.
4. **Posture is universally required; exceptions are governed:** supply-chain / OIDC posture is never "conditional" — only a **Security Owner** may ratify a **documented, time-boxed exception** (defined in 6c, evidenced in 6d). This settles the question deferred from Slice 5e.
5. **Versioning:** each sub-slice is additive → **MINOR** (2.9.0 → 2.12.0). **Tag `3.0.0` at 6d** purely as an "enterprise layer complete" milestone marker (not a semver-breaking signal).

## 3. End-state shape (all four sub-slices)

```
docs/enterprise/
  README.md                     ← 6a · index + responsibility boundary (kit-covered vs org-owned)
  compliance-crosswalk.md       ← 6a · SOC 2 TSC + ISO 27001:2022 Annex A  ← kit controls
  secrets-at-scale.md           ← 6b · managed-secret-store contract + patterns + client-by-stack table
  ratification-rbac.md          ← 6c · roles × ratifiable actions; governed-exception process
conformance/
  audit-evidence-checklist.md   ← 6d · per-control "where is the evidence in a kit-built repo" (capstone)
DEVELOPMENT-STANDARDS.md         ← 6b adds a §2 "secrets at scale" subsection; (no new gate)
DEVELOPMENT-PROCESS.md           ← 6c extends §12/§13 with the ratification-role model + exception process
profiles/_TEMPLATE.md            ← 6b adds a one-line secrets-at-scale pointer to the Security section
docs/ROADMAP-KIT.md              ← each sub-slice marks its row shipped
```

Governing top-level docs (`CLAUDE.md`, `DEVELOPMENT-STANDARDS.md`, `DEVELOPMENT-PROCESS.md`) stay authoritative; `docs/enterprise/` is an **addendum** that hangs off §2/§12/§13 and never overrides them.

## 4. Per-pillar design

### 4a. Compliance crosswalk (Slice 6a) — `v2.9.0`

- **Deliverables:** `docs/enterprise/README.md` (index + responsibility boundary) and `docs/enterprise/compliance-crosswalk.md`.
- **Crosswalk table columns:** `Kit control` (the thing the kit enforces, e.g. "secret-scan gate", "branch protection / builder≠merger", "SBOM+provenance", "immutable audit log", "agent autonomy guard", "PII/erasure primitives §2") · `Where in the kit` (file/§) · `SOC 2 TSC` (Security CC-series, e.g. CC6.1/CC7.2/CC8.1; **Privacy P-series, e.g. P1–P8**) · `ISO 27001:2022 Annex A` (e.g. A.8.9, A.8.28, A.5.15) · `Evidence artifact` (CI log, SBOM file, PR approval, ADR, RUNBOOK) · `Responsibility` (Kit-enforced / Kit-assisted / **Org-owned**).
- **Privacy / data-protection family (in the crosswalk + README):** data-subject rights (access/erasure) · consent & **age-gating** · retention/minimization · third-party/affiliate data-sharing. Mapped to the §2 PII/consent/erasure primitives, marked **Kit-assisted / Org-owned** (the kit never claims to *make* an org COPPA/GDPR-compliant). Generic triggers named: **COPPA** (children's data), **GDPR** (incl. minors' provisions), **CCPA/CPRA**. Graceful **N/A-with-reason** for no-PII projects so non-privacy adopters carry zero overhead.
- **Responsibility boundary (README):** explicitly enumerate the control families the kit does **not** fully cover (HR/personnel security, physical/environmental, vendor/third-party risk, business-continuity beyond RUNBOOK DR, and the privacy *program* itself — the kit assists, the org owns) so the map is honest.
- **Frameworks:** SOC 2 Trust Services Criteria (Security common criteria + **Privacy (P) criteria**) + ISO/IEC 27001:2022 Annex A (93 controls, 4 themes). NIST CSF / PCI-DSS / ISO 27701 are noted as "extensible the same way" with trigger notes (not built — see §2 decision). Verify all control identifiers (CC-/P-series, Annex A numbers) against current sources at implementation time (WebSearch) — wrong identifiers are the main risk.
- **Conformance:** each crosswalk row must reference either a real enforced control (point to the file/§/gate) or be explicitly marked **Kit-assisted / Org-owned**. No row may claim coverage the kit doesn't provide. (Checked in 6d + a self-review; no new script.)

### 4b. Secrets at scale (Slice 6b) — `v2.10.0`

- **Contract (new `DEVELOPMENT-STANDARDS.md` §2 subsection "Secrets at scale"):** for non-trivial/regulated deployments, secrets live in a **managed secret store** (Vault / cloud KMS + Secrets Manager), not just env files; requirements = central store · least-privilege access policies · **rotation** (and prefer **short-lived/dynamic** secrets) · no plaintext secrets in state/logs/images · **break-glass** access is audited. `.env` remains the floor for local dev.
- **Reference (`docs/enterprise/secrets-at-scale.md`):** the patterns (static vs dynamic secrets, rotation, CI injection via OIDC→cloud — ties to the Slice 5e provenance job, sidecar/agent injection, envelope encryption with KMS) **+ a compact "secret-manager client by stack" table** so the adopter's chosen stack is covered in one place:

  | Stack | Managed-secret client (reference) |
  |-------|-----------------------------------|
  | python | `hvac` (Vault) · `boto3`/`google-cloud-secret-manager`/`azure-keyvault-secrets` |
  | typescript-node | `node-vault` · AWS/GCP/Azure SDK secret clients |
  | java-spring | Spring Cloud Vault · Spring Cloud AWS/GCP secrets |
  | dotnet | `VaultSharp` · Azure.Security.KeyVault.Secrets |
  | go | `hashicorp/vault/api` · cloud SDK secret managers |
  | rust | `vaultrs` · `aws-sdk-secretsmanager` |
  | kotlin | Spring Cloud Vault (JVM) |
  | ml / data-engineering | same Python clients; warehouse creds via the store, not `profiles.yml` plaintext |
  | terraform | Vault provider / cloud KMS data sources; never plaintext in state |

  (Reference libraries — verify currency at implementation time; mark clearly as "reference, not endorsement".)
- **Profile routing:** add to `profiles/_TEMPLATE.md` Security section: a one-line "**Secrets at scale:** for shared/regulated envs use a managed store — → `docs/enterprise/secrets-at-scale.md`". **No edit to the 10 existing profiles.**
- **Conformance:** checklist items in 6d ("managed store in use for shared envs", "rotation defined", "no plaintext secrets in state/logs").

### 4c. Ratification RBAC (Slice 6c) — `v2.11.0`

- **Contract (extends `DEVELOPMENT-PROCESS.md` §12 review-separation + §13 governance):** define **roles** and **what each may ratify** — the kit currently says "humans ratify / builder ≠ sole merger" but never *which* humans for *what*.
- **Role model (reference table):**

  | Role | May ratify |
  |------|-----------|
  | **Project Owner** | requirements/scope, architecture (ADRs), breaking changes |
  | **Code Owner** (per CODEOWNERS domain) | code PRs in their domain (the independent reviewer; builder ≠ sole merger) |
  | **Security Owner** | changes to governing docs (`CLAUDE.md`/STANDARDS/PROCESS), gate definitions, **supply-chain/OIDC posture exceptions**, secret-rotation policy, autonomy-tier raises |
  | **Release Manager** | production deploys / promotions, rollback decisions |

  - Separation-of-duties rules: builder ≠ sole approver; a single person may hold multiple roles in a small org **but not both builder and sole ratifier of the same change**; map roles → GitHub via CODEOWNERS + branch-protection required-reviewers.
  - **Governed-exception process (settles the 5e question):** posture/gate requirements are **universally required**; an exception requires a Security-Owner-ratified, **time-boxed** record (what, why, expiry, compensating control) — an auditable event, never a silent "conditional".
- **Conformance:** maps onto the existing `conformance/agent-autonomy.sh` (human-gate set) + CODEOWNERS/BRANCH-PROTECTION references; 6d attests the role mapping exists. No new script (or a light check if cheap).

### 4d. Audit-evidence checklist (Slice 6d, capstone) — `v2.12.0` / milestone `3.0.0`

- **Deliverable:** `conformance/audit-evidence-checklist.md` — same **checklist-type** format as `conformance/15-factor-checklist.md` (copy into the project/review record; mark Evidence per row; reviewer signs off).
- **Content:** one row per kit control (the 6a crosswalk's left column), each pointing to **the artifact that proves it in a kit-built repo** — CI gate run logs, the SBOM file + provenance attestation, PR approval records (builder≠merger), ADRs, RUNBOOK DR section, the immutable audit log, the `conformance/*.sh` outputs, the governed-exception records (6c), the managed-secret-store config (6b). Columns: `Control` · `SOC2/ISO ref` · `Evidence artifact (where)` · `Auto/Manual` · `Present? (Y/N/NA+reason)`.
- **Auto vs manual:** rows backed by an executable check (`ci-gates.sh`, `agent-autonomy.sh`, `profile-completeness.sh`, `inception-done.sh`) are marked **Auto** with the command; the rest are **Manual** attestation. The checklist is the human-attested capstone; it *points at* the kit's existing executable conformance rather than duplicating it.
- **Conformance (self-referential):** `conformance/check-links.sh` must stay green (the checklist links to real files/§); every crosswalk control (6a) must have a corresponding evidence row (6d) — the completeness tie-off for the whole slice.

## 5. Sequencing, versioning, ratification

- This umbrella spec is committed on the **6a branch** and merges with 6a (it governs all four; it is not separately merged).
- Each sub-slice: umbrella spec (this) → its own `writing-plans` plan → subagent-driven build → PR → **human ratification** (Bradley merges each; agents never self-merge governing changes).
- 6a `v2.9.0` · 6b `v2.10.0` · 6c `v2.11.0` · 6d `v2.12.0` (+ tag `3.0.0` milestone at 6d).
- 6c edits a governing doc (`DEVELOPMENT-PROCESS.md`) — highest ratification care; 6b edits a governing doc (`DEVELOPMENT-STANDARDS.md` §2) — same.

## 6. Validation (whole slice)

- `conformance/check-links.sh` green after every sub-slice (new docs cross-link real files).
- Crosswalk (6a): no row claims uncovered control; every "Kit-enforced" row resolves to a real file/§/gate.
- Audit-evidence (6d): every 6a control has an evidence row; Auto rows name a real `conformance/*.sh`.
- No regression: existing conformance scripts (`ci-gates`, `agent-autonomy`, `profile-completeness`, `inception-done`) still pass; no profile altered (except the one-line `_TEMPLATE.md` pointer in 6b).
- Kit CI green each sub-slice (`conformance`, `bootstrap`, `docs-links`).

## 7. Risks & mitigations

- **Wrong control identifiers (SOC2 CC-series / ISO Annex A numbers).** Highest risk in 6a/6d. Mitigation: verify every identifier against current sources (WebSearch) at implementation time; spec/quality review cross-checks; prefer citing the control *theme/name* alongside the number.
- **Over-claiming coverage** (saying the kit satisfies a control it only partially supports). Mitigation: the `Responsibility` column (Kit-enforced / Kit-assisted / Org-owned) is mandatory; "assisted" and "org-owned" are first-class, not failures.
- **RBAC contradicts §12/§13.** Mitigation: 6c *extends*, never overrides; explicit cross-refs; the human-gate set stays as in §13; agent-autonomy.sh unchanged.
- **Scope creep into a full GRC product.** Mitigation: out-of-scope list (§8); the kit ships a crosswalk + patterns + role model + evidence map, not a control-management platform.
- **Secrets-at-scale dr/ift vs profiles.** Mitigation: one stack-aware table + a `_TEMPLATE.md` pointer; no per-profile snippets to drift.

## 8. Out of scope

- A full SOC 2 / ISO 27001 control *catalog* or a company's compliance/privacy *program* (the kit maps to frameworks and assists privacy; the org runs the program).
- Frameworks beyond SOC 2 (Security + Privacy) + ISO 27001:2022 — **NIST CSF, PCI-DSS, ISO 27701, HIPAA, FedRAMP** are noted as "extensible the same way" with trigger notes, not built. (PCI triggers only if the org handles cardholder data — outsource/tokenize to avoid scope.)
- Per-profile managed-secret-store code snippets in the 10 existing profiles (stack-aware table + `_TEMPLATE.md` pointer instead).
- A GRC/evidence-collection tool or automated control-monitoring platform.
- Any new *required CI gate* (the addendum adds posture + evidence, not a gate; Definition of Done unchanged).

## 9. Definition of Done (umbrella — each sub-slice has its own)

- All four sub-slices (6a–6d) shipped via their own plan → PR → ratification, in order.
- `docs/enterprise/` set complete; `conformance/audit-evidence-checklist.md` present and tied to the 6a crosswalk.
- §2 (secrets-at-scale) + §12/§13 (ratification RBAC + governed-exception) extended; `profiles/_TEMPLATE.md` pointer added; no existing profile otherwise changed.
- `check-links.sh` + all existing conformance scripts green; kit CI green each sub-slice.
- VERSION walks 2.9.0 → 2.12.0; `3.0.0` milestone tag at 6d; CHANGELOG + ROADMAP updated each sub-slice.
- Each governing-doc change human-ratified (Bradley merges).

---

**Next:** on approval of this umbrella spec, proceed to **Slice 6a** — `writing-plans` for the compliance crosswalk + responsibility boundary (`docs/enterprise/README.md` + `compliance-crosswalk.md`), then subagent-driven build.
