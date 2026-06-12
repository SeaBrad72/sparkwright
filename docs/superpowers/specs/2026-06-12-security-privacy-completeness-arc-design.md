# Security & Privacy Completeness Arc — Design

**Status:** approved (brainstorm), ready for per-slice implementation planning
**Arc:** closes the verified security/privacy gaps before the kit pivots to UX/product-design. Decomposes into 3 slices → one **2.57.0** release.

---

## 1. Why

A repo-grounded gap-scan (not guesswork) confirmed the kit is robust but missing a few standard controls. Verified **present**: runtime guard + MCP gate + egress + containment, 8 CI gates incl. secret-scan/dep-scan/SBOM/provenance, action SHA-pinning, mutation/property testing, DORA, DR/BIA, threat-model + AI-governance + compliance crosswalk, resilience/load, progressive delivery, agent-ops. Verified **gaps** (the subject of this arc):

1. **SAST is not a gate** — the gates scan *dependencies* (`gate-dep-scan`) and *secrets*, but not **first-party code** for injection/auth-bypass/SSRF patterns.
2. **No license-compliance check** — the SBOM is *generated* but never *acted on* (nothing flags copyleft entering a proprietary build).
3. **No `SECURITY.md` / vulnerability-disclosure policy** — absent.
4. **No data-classification + retention/deletion scheme** — PII handling is implicit; no formal classification (esp. for COPPA/children's data).
5. **No general privacy-review/DPIA artifact** — the RAI arc covers *AI* governance; nothing covers a non-AI feature touching children's PII.

## 2. Shaping decisions (settled)

- **SAST + license = conditional gates** (the a11y/load/eval family): first-class but **trigger-bound, N/A-with-reason**. SAST triggers on first-party application code (N/A for pure-IaC/docs); license triggers when an SBOM is produced. Keeps the release **MINOR** (a new *universal-required* gate would be MAJOR/3.0.0). Verified by extending `conformance/conditional-gates.sh`.
- **Cross-cutting per-stack tooling reaches ALL profiles** + `profiles/_TEMPLATE.md` (the `MAINTAINING.md` rule) — SAST + license get a per-stack reference line in every profile.
- **Honesty invariant** — a green SAST/license gate proves the scan *ran*, never that the code is secure/compliant; a green privacy/classification readiness check proves the posture is *recorded*, never that privacy is *assured* (the real assessment is Manual rows).
- **Doc budget is the primary constraint** — PROCESS 468/470, STANDARDS 317/320. **Bulk → new reference docs** (`docs/operations/security-scanning.md`, `docs/enterprise/data-governance.md`); core docs get only minimal `+0`/≤2-line pointers, `doc-budget.sh`-verified after each edit. If a core row won't fit, it routes to the reference doc.

## 3. Slice decomposition (3 slices → 2.57.0)

### Slice SP-1 — Security gates (`gate-sast` + `gate-license`)
- **`gate-sast`** — conditional gate. Reference tool: **Semgrep** (multi-language, OSS; portable default), **CodeQL** as the GitHub-native alternative. Scans first-party code for injection/auth-bypass/SSRF/insecure-deserialization patterns. A per-profile reference step + the profile security section names the stack's SAST entry.
- **`gate-license`** — conditional gate. A **stack-neutral policy check over the existing CycloneDX SBOM** (reuses `gate-sbom` output — no 10 per-stack license tools). Default policy: **flag strong-copyleft (AGPL/GPL/LGPL-as-applicable) for proprietary builds; allow permissive (MIT/Apache-2.0/BSD/ISC)**; per-project overridable via a small policy file. Honest: flags for review, doesn't auto-judge legal validity.
  - **Self-flagging on its own blind spot (the stack-neutral compromise).** A component with `NOASSERTION` / undetermined / missing license is **never silently passed** — the check counts them and emits a review-required message that names the count and points to the upgrade path, e.g. *"N component(s) have undetermined licenses the SBOM can't clear — flagged for review; for higher-fidelity license detection on this stack see `docs/operations/security-scanning.md` → per-stack upgrade."* The tool quantifies its own uncertainty and tells the adopter when they've outgrown it.
  - **Per-stack upgrade ladder (contract-preserving).** `security-scanning.md` carries a table mapping each profile → its recommended native tool (npm `license-checker`; `pip-licenses` for python/ml/data-eng; `go-licenses`; **`cargo-deny`** for rust; `license-maven-plugin`/`gradle-license-report` for java/kotlin; `nuget-license` for dotnet; terraform mostly N/A). An adopter swaps the default implementation but **keeps the same `gate-license` id and the same policy file**, so conformance still passes — the kit's "rewrite the reference, keep the contract" rule. Plus a one-line pointer in each profile's security section.
  - **Named "when to upgrade" triggers:** (a) the default repeatedly reports undetermined-license components; (b) a strict/audited legal license-compliance obligation; (c) shipping a proprietary product with copyleft exposure; (d) needing build-graph scoping (allow a dev-only copyleft tool). Stated in the guidance so the upgrade decision isn't vague.
- **Wiring:** add both rows to `DEVELOPMENT-PROCESS.md` §7 conditional-gate table + a `DEVELOPMENT-STANDARDS.md` §14 sentence (budget-checked); extend `conformance/conditional-gates.sh` markers (+ `--selftest`); add a SAST + license reference line to all 10 profiles + `_TEMPLATE`; bulk in `docs/operations/security-scanning.md`. Optional reference CI steps (`gate-sast`/`gate-license` ids) in the profile `ci.yml` files (agent-editable).
- **Honesty:** green = the scan executed and the policy was applied; NOT that the code is vulnerability-free or the licenses are legally cleared.

### Slice SP-2 — `SECURITY.md` / vulnerability-disclosure policy
- **`templates/SECURITY-TEMPLATE.md`** — coordinated-disclosure process, security contact, supported-versions, a `.well-known/security.txt` pointer, response-time expectations.
- **`scripts/incept.sh`** drops a `SECURITY.md` at inception (like it scaffolds other project files).
- **`conformance/security-policy.sh`** — presence + non-placeholder check (a real contact, not the `[security-contact]` placeholder); conditional N/A only for a non-shipping scratch repo, else required-present. Mirror the readiness-check three-state + `--selftest` + coupling test.
- Wire into `verify.sh` (doc-check) + README/audit rows + CI selftest (control-plane hand-apply).

### Slice SP-3 — Data governance (classification + retention + DPIA-lite)
- **Data-classification scheme** — 4 tiers **Public / Internal / Confidential / Restricted** (Restricted = children's-PII / regulated). Declared in `PROJECT-CLAUDE-TEMPLATE.md` (project default) and per-feature in the SPEC/threat-model; **retention + deletion** recorded in RUNBOOK (a `Data handling:` record line, colon-adjacent per SNP-1).
- **`templates/PRIVACY-REVIEW-TEMPLATE.md`** (DPIA-lite) — purpose, data collected + classification, lawful basis / COPPA consent, minimization, retention, third-party sharing, deletion path, residual risk. A **conditional flag in the Definition of Ready** (privacy-sensitive trigger), mirroring the threat-model flag.
- **`conformance/privacy-ready.sh`** — conditional (data-surface / Restricted-data trigger), fail-closed, three-state: asserts the privacy posture is **recorded** (classification declared + a privacy review located when Restricted data is present). `--selftest` + coupling test. Bulk in `docs/enterprise/data-governance.md`.
- **Honesty:** green = classification + DPIA are *recorded*; the actual privacy assessment + deletion-works verification are Manual rows.

## 4. Cross-slice conventions
- Each slice: brainstorm-settled here → its own plan (`writing-plans`) → build → independent review (security-owner lens — this is the security/privacy domain) → ratified PR → Bradley merges.
- Conditional gates and readiness checks follow the existing families exactly (`conditional-gates.sh`; the `*-ready.sh` three-state pattern); no new patterns invented.
- Control-plane CI selftest steps are prepared as hand-applies (verify against **committed `origin/main`**, not the working tree — the MP-3a.2 lesson).
- Doc-budget: `+0` appends preferred; bulk to the new reference docs; verify with `doc-budget.sh` after every core-doc touch.

## 5. Out of scope (Tier-3 — explicitly deferred, noted not built)
Image **signing + verify-at-deploy** (cosign) beyond provenance attestation · explicit **secret-rotation cadence** doc · **feature-flag debt** cleanup · **flaky-test quarantine** · **pre-mortem** template · cloud **FinOps budget** alerts. Each is either low-ROI or already partially covered; revisit only if a concrete need arises.

## 6. Definition of Done (arc)
- SP-1: `gate-sast` + `gate-license` named in §7/§14 + `conditional-gates.sh` (with `--selftest`); per-stack reference in all 10 profiles + `_TEMPLATE`; `docs/operations/security-scanning.md`.
- SP-2: `SECURITY-TEMPLATE.md` + incept wiring + `security-policy.sh` (three-state, `--selftest`, coupling-tested) + verify/README/audit/CI rows.
- SP-3: data-classification scheme + `PRIVACY-REVIEW-TEMPLATE.md` + DoR flag + `privacy-ready.sh` (conditional, three-state, `--selftest`) + `docs/enterprise/data-governance.md` + RUNBOOK `Data handling:` record.
- Each slice: independent security-owner review → SHIP; ratified PR; doc-budget green; links green; `verify.sh` green.
- **Arc close:** a **2.57.0** release covering SP-1/2/3. Then the kit pivots to UX/product-design.
