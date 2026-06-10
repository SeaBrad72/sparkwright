# Slice 9j — Best-Practice Fidelity (design)

**Date:** 2026-06-10 · **Arc:** Slice 9, Stage V (R10) · **Version target:** MINOR → **v2.36.0**
**Input:** the review's R10 finding — the kit teaches supply-chain best practice but doesn't (a) **declare the SLSA level** it actually reaches, (b) map its controls to **NIST SSDF** (only SOC 2 + ISO), (c) state honestly whether **a11y/load/eval** are required, or (d) make its **reference pipeline satisfy its own SHA-pinning contract** (the canonical `profiles/typescript-node/ci.yml` comments "pin every `uses:` to a 40-char SHA" yet tag-pins every action).

## The fork (ratified at brainstorm)
a11y/load/eval are **inherently conditional** (UI-only / service-only / AI-only). Promoting them to universally-required CI gates would force a CLI/library/batch job to waive them every build — the exact false-universality the kit fights. **Decision: honest-demote → formalize them as first-class *conditional* gates (MINOR), not universal ones.** No new universal required gate → stays MINOR. The MAJOR/3.0.0 path (promote-to-universal) is explicitly rejected.

## Components

### 1. Conditional-gate formalization (the honest-demote)
- **`DEVELOPMENT-PROCESS.md` §7 gate table:** add an **Accessibility** conditional-gate row — *(user-facing UI)* → "keyboard/screen-reader/contrast pass; recorded in `templates/A11Y-SIGNOFF-TEMPLATE.md` (axe/Lighthouse evidence)". The **Eval gate** *(AI features)* and **Resilience readiness** *(deployable services — load/soak)* rows already exist; this names the conditional trio explicitly. Each carries its trigger + **N/A-with-reason** discipline (same pattern as threat-model / 15-factor).
- **`DEVELOPMENT-STANDARDS.md` §14:** a note distinguishing the **universal 7 gates** from the **conditional gates** (a11y / load / eval) — binding when their trigger is present, N/A-with-reason otherwise. Closes the "are these required?" ambiguity honestly.
- **`CLAUDE.md` DoD:** one additive line under the CI/CD item noting the conditional gates apply when triggered (no change to the 7; governing surface → security-owner lens; **adds no universal requirement**).
- **`conformance/conditional-gates.sh` (new):** drift-guard — §7 names a11y, load/resilience, and eval as conditional gates each with a trigger annotation. `--selftest` (two-tree, no `rm`).

### 2. SLSA level declaration
**`DEVELOPMENT-STANDARDS.md` §14:** declare the kit reaches **SLSA Build L2** — provenance is authenticated and service-generated (`actions/attest-build-provenance` + the push-only OIDC job; provenance bound to the artifact/image digest). Name the **evidence** (the attestation) and the honest **L3 path** (hermetic/isolated build + non-falsifiable provenance) the kit does *not* yet claim. A declaration, not a gate. Mirror as a crosswalk row.

### 3. Signed commits/tags (recommended hardening — not a gate)
**`DEVELOPMENT-STANDARDS.md` §2:** a "Commit & tag signing" subsection — Sigstore `gitsign` (keyless, OIDC-backed) or GPG; **sign release tags**. Explicitly **recommended, not required** (requiring it would be another MAJOR). Verifiable in CI by adopters who opt in; the kit documents the path.

### 4. NIST SSDF crosswalk column
**`docs/enterprise/compliance-crosswalk.md`:** add a **NIST SSDF (SP 800-218)** column to the controls table, mapping each kit control to its SSDF practice (PO/PS/PW/RV families) — e.g. SBOM+provenance → **PS.2/PS.3**, dep-scan → **PW.4/RV.1**, secret-scan → **PW.8/PS.1**, branch-protection → **PS.1**, threat-model → **PW.1**, lint/type/test → **PW.7/PW.8**, least-priv OIDC → **PO.3/PO.5**. Update the header line's "Frameworks covered."

### 5. SHA-pin the canonical reference + enforce
- **`profiles/typescript-node/ci.yml`:** every `uses:` → a full **40-char commit SHA** + a trailing `# vX` comment (real SHAs resolved via `gh api` at build time). Satisfies the contract the file itself states + §14's "pin third-party actions to a full commit SHA."
- **`conformance/action-pinning.sh` (new):** asserts every `uses:` in the canonical reference is a 40-hex SHA (not a tag). The other 9 profiles are **adopter-templates** (documented: pin at adoption); the check enforces on the canonical reference only. `--selftest` (a tag-pinned fixture must fail; a SHA-pinned one must pass).
- **Dependabot note:** `DEVELOPMENT-STANDARDS.md` §14 / the profile — SHAs stay current via Dependabot (which updates the SHA and the `# vX` comment together).

### 6. CI + release
- Both new checks wired into kit CI after the existing `dor-defined` steps (**one control-plane `cp`**): `conditional-gates.sh` + selftest, `action-pinning.sh` + selftest.
- `VERSION` → 2.36.0; CHANGELOG; roadmap 9j → shipped (resolving the arc's MINOR-or-MAJOR note in favor of MINOR).

## Files

| File | Change | Owner |
|------|--------|-------|
| `DEVELOPMENT-PROCESS.md` | §7 add Accessibility conditional-gate row (+ name the conditional trio) | agent |
| `DEVELOPMENT-STANDARDS.md` | §14 universal-vs-conditional note · SLSA L2 declaration + L3 path · §2 commit/tag-signing subsection · Dependabot note | agent (governing → security-owner lens) |
| `CLAUDE.md` | DoD CI/CD: one additive conditional-gates line (no universal requirement added) | agent (governing → security-owner lens) |
| `docs/enterprise/compliance-crosswalk.md` | new NIST SSDF column + SLSA row + frameworks-covered line | agent |
| `profiles/typescript-node/ci.yml` | every `uses:` → 40-char SHA + `# vX` | agent |
| `conformance/conditional-gates.sh` | **New** — §7 names the conditional trio; `--selftest` | agent |
| `conformance/action-pinning.sh` | **New** — canonical reference is SHA-pinned; `--selftest` | agent |
| `conformance/README.md` | two index rows | agent |
| `.github/workflows/ci.yml` | both checks + selftests | **human `cp`** |
| `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-SLICE9.md` | 2.36.0; 9j → shipped (MINOR) | agent |

## Verification
- `sh conformance/conditional-gates.sh` → PASS (a11y/load/eval named in §7 with triggers); `--selftest` detects a missing conditional gate.
- `sh conformance/action-pinning.sh` → PASS (canonical reference fully SHA-pinned); `--selftest` detects a tag-pinned `uses:`.
- `dash -n` clean on both scripts.
- `sh conformance/ci-gates.sh profiles/typescript-node/ci.yml` → still green (gate-ids intact after pinning — only the `uses:` refs change, not the gate `id:`s).
- `sh conformance/check-links.sh` + `sh conformance/verify.sh` → green.
- `git diff main..HEAD -- CLAUDE.md` shows the DoD edit adds **no universal requirement** (one conditional-gates clarification line; the 7 unchanged) — security-owner lens.
- The SLSA claim is **L2, not overclaimed L3** (diff-reviewed against the evidence the kit actually produces).
- Anonymization: generic ([[kit-anonymization]]).

## Out of scope / deferred
- **Pinning all 10 profiles** — the canonical reference is the exemplar; the other 9 are adopter-templates documented to pin at adoption (avoids 60 hand-resolved SHAs going stale).
- **Making signing or SLSA-L3 required gates** — that's a MAJOR; deferred. 9j documents the *path*, doesn't mandate it.
- **The SBOM-vs-attested-digest evidence gap** the reference admits — that's the **A4 auditor simulation**, not this build slice.
- **Promote-to-universal (MAJOR/3.0.0)** — explicitly rejected at the fork.

## Known implications
- The kit now states its supply-chain posture in the vocabulary auditors use (SLSA level + NIST SSDF), alongside the existing SOC 2 / ISO crosswalk.
- "Required" becomes honest: **7 universal gates + a named conditional trio**, each conditional gate trigger-bound and N/A-with-reason — no false universality.
- The canonical reference pipeline now satisfies its own pinning contract, enforced by `action-pinning.sh`; SHA drift is a Dependabot concern, not a silent rot.
- A future best-practice level-up (SLSA L3, required signing) is a deliberate MAJOR, pre-scoped here.
