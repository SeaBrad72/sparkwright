# Design — Slice 1: CI/CD (contract · reference · conformance + kit-own CI)

**Date:** 2026-06-05
**Status:** Approved (brainstorming) — pending spec review
**Author:** Bradley James + agent
**Roadmap:** `docs/ROADMAP-KIT.md` Slice 1. Follows the Foundation increment (v1.0.0) which established the contract/reference/conformance convention (`MAINTAINING.md` §1).

---

## 1. Goal

Make the kit's CI/CD governance **enforced, not just described**: define a stack-neutral CI contract, ship a working TypeScript reference pipeline adopters drop in, provide an executable conformance check, and have the kit repo itself run CI (dogfooding). This converts the highest-leverage governance promise — "automated quality gates" — from prose into a running gate.

## 2. Decisions (from brainstorming)

- **Scope:** both the adopter-facing reference pipeline AND the kit's own dogfooding CI.
- **Gate set:** **7 required gates on every PR**, raised to the **baseline for all projects** (not maturity-gated): (1) lint, (2) type-check, (3) test + coverage ≥ 80% / 100% critical paths, (4) build, (5) secret-scan, (6) dependency/vulnerability scan (fail on high/critical), (7) SBOM + build provenance. Plus branch protection: `main` protected, green CI to merge, builder ≠ sole merger.
- **Posture reconciliation:** update `DEVELOPMENT-PROCESS.md` §10 (supply-chain "configuration hook" → required gate) and §15 (recurring audit reframed as the deeper periodic complement) so the docs agree with §14. Human-ratified governance change.
- **Tooling (TS reference):** gitleaks (secrets) · `npm audit --audit-level=high` (deps) · CycloneDX `@cyclonedx/cyclonedx-npm` (SBOM) · `actions/attest-build-provenance` (provenance, at release/build path).
- **Conformance form:** static-assertion POSIX `sh` script (Approach A) — checks contract identifiers, not stack tools.
- **Version:** **2.0.0** (MAJOR) — per `MAINTAINING.md` §2, a new required gate is MAJOR. The kit dogfoods its own semver rule.

## 3. Deliverables

| Part | Files |
|------|-------|
| **Contract** | `DEVELOPMENT-STANDARDS.md` new **§14 CI/CD Pipeline**; edits to `DEVELOPMENT-PROCESS.md` §10 and §15 |
| **Reference** (inert in kit repo) | `profiles/typescript-node/ci.yml`, `profiles/typescript-node/CODEOWNERS`, `profiles/typescript-node/BRANCH-PROTECTION.md`; pointer in `profiles/typescript-node.md` §4 |
| **Conformance** | `conformance/ci-gates.sh`; index row in `conformance/README.md` |
| **Kit-own CI** | `.github/workflows/ci.yml` (this repo) |
| **Meta** | `VERSION` → `2.0.0`; `CHANGELOG.md` 2.0.0 entry; `docs/ROADMAP-KIT.md` marks Slice 1 done |

## 4. Detailed design

### 4.1 Contract — `DEVELOPMENT-STANDARDS.md` §14 (stack-neutral)

New section after §13. States:
- The **7 required gates**, each one sentence, stack-neutral; tools deferred **→ profile**.
- Coverage gate restates the §7 floor (80% / 100% critical) — cross-reference, don't duplicate.
- **Branch protection**: `main` protected; green CI required to merge; builder ≠ sole merger (cross-ref §13 governance + the "builder ≠ reviewer" rule in `DEVELOPMENT-PROCESS.md` §2).
- **Provenance note**: SBOM + scan run per-PR; provenance attestation attaches to release/build artifacts (there is nothing to attest on a no-artifact change) — the pipeline still *owns* provenance, the reference shows where it attaches.
- Pointer to `conformance/ci-gates.sh` as the check.

### 4.2 Contract reconciliation — `DEVELOPMENT-PROCESS.md`

- **§10 "Supply-chain integrity *(configuration hook)*"** → rewritten: pin/lock deps, dependency-scan, SBOM, and provenance are **required CI gates (§14 of standards)**, no longer optional hooks. Keep the sentence about tooling being a project choice (→ profile).
- **§15 recurring work** — "Dependency audits / vulnerability scans + SBOM refresh (monthly + pre-release)" reframed as the **deeper periodic** scan that complements the per-PR gate (e.g. full-tree audit, not just high/critical on changed deps). No contradiction with §14.

### 4.3 Reference — `profiles/typescript-node/`

A companion directory beside `profiles/typescript-node.md`. Files here are **inert in the kit repo** (GitHub only executes `.github/workflows/`); adopters copy them into their own `.github/`.

**`ci.yml`** — GitHub Actions, triggers on PR + push to `main`. Single job (or matrixed) with steps, each carrying a standardized `id` the conformance script keys on:
- `gate-install` — `npm ci`
- `gate-lint` — `eslint`
- `gate-type-check` — `tsc --noEmit`
- `gate-test` — `vitest run --coverage` (coverage threshold 80 enforced in `vitest.config.ts`)
- `gate-build` — `tsc` / `next build`
- `gate-secret-scan` — gitleaks action
- `gate-dep-scan` — `npm audit --audit-level=high`
- `gate-sbom` — CycloneDX SBOM generation, upload artifact
- `gate-provenance` — `actions/attest-build-provenance` (guarded to release/build-artifact context)

**`CODEOWNERS`** — reference mapping routing review (e.g. `* @your-team`), demonstrating the "builder ≠ reviewer" enforcement point.

**`BRANCH-PROTECTION.md`** — prose + a `gh api` snippet to: require the CI status check, require ≥1 review from a non-author, dismiss stale approvals, and the org-setting note that strictly forbidding self-merge depends on GitHub plan/org policy.

**`profiles/typescript-node.md` §4** — replace the prose-only pipeline description with a pointer to the concrete `profiles/typescript-node/ci.yml` (+ the two companions), keeping the prose summary.

### 4.4 Conformance — `conformance/ci-gates.sh`

POSIX `sh`. Usage: `ci-gates.sh <workflow-file>`. Asserts the file contains all required gate ids: `gate-lint gate-type-check gate-test gate-build gate-secret-scan gate-dep-scan gate-sbom gate-provenance` — **8 step-ids implementing the 7 contract gates** (gate 7, supply-chain integrity, = `gate-sbom` + `gate-provenance`). (Install is setup, not a quality gate, so it's not asserted.) Exits 0 if all present; non-zero listing each missing gate. Checks **identifiers, not tools** → stack-neutral. Adds a row to `conformance/README.md`'s index table.

### 4.5 Kit-own CI — `.github/workflows/ci.yml`

Runs on PR + push to `main`. Two jobs:
- **`conformance`** — `sh conformance/ci-gates.sh profiles/typescript-node/ci.yml`; assert `conformance/15-factor-checklist.md` exists. Fails the build if the reference drifts from the contract.
- **`docs-lint`** — markdownlint (`markdownlint-cli2`) over the kit's `.md`; a relative-link existence check (every `](path)` to a repo file resolves).

This is the kit's own gate going green on every PR — the visible dogfood.

### 4.6 Branch protection on the kit repo

Documented in `BRANCH-PROTECTION.md`; applied **after** the workflow has run at least once (so the required-status-check name exists), to avoid locking the branch before CI is registered. Applying it is the final step, optional if it risks blocking the in-flight PR.

## 5. Validation / testing

- **Positive:** `ci-gates.sh profiles/typescript-node/ci.yml` exits 0.
- **Negative:** a temporary copy with one `gate-*` id removed exits non-zero naming the missing gate (a test in the plan; the temp file is not committed).
- **Dogfood:** the kit's `.github/workflows/ci.yml` goes green on the Slice-1 PR.
- **Consistency:** §14 stays stack-neutral (grep guard like §13); §10/§15 no longer contradict §14; `VERSION`/`CHANGELOG`/any doc references to 2.0.0 agree.
- **Cold-resume:** `BRANCH-PROTECTION.md` is enough for another engineer to configure protection unaided.

## 6. Risks & mitigations

- **Provenance semantics on no-artifact PRs.** Mitigation: 4.1 provenance note + `gate-provenance` guarded to the release/build path; the contract owns it, the reference scopes it.
- **Locking the kit's `main` mid-slice via branch protection.** Mitigation: apply protection last, after CI has run once; make it optional in the plan.
- **Raised baseline burdens trivial repos.** Accepted per the user's explicit "7 gates for all" choice; SBOM/provenance scoped to build/release path keeps PR cost bounded.
- **Doc contradiction (the failure mode caught in Foundation).** Mitigation: §10/§15 reconciliation is an explicit deliverable, with a consistency check in validation.
- **Two `ci.yml` files (kit-own vs reference) confusion.** Mitigation: reference lives under `profiles/typescript-node/` (inert path); kit-own lives at `.github/workflows/`; both clearly headed with a comment stating which is which.

## 7. Out of scope (later slices)

Other-stack reference pipelines (Python/Java → Slice 5) · agent-governance `.claude/` layer (Slice 2) · Inception bootstrap wiring CI automatically (Slice 3) · actually configuring each adopter's repo (adopters do this at Inception).

## 8. Definition of Done (this slice)

- §14 written (stack-neutral); §10/§15 reconciled; no doc contradicts another.
- Reference `ci.yml` + `CODEOWNERS` + `BRANCH-PROTECTION.md` present; profile §4 points to them.
- `ci-gates.sh` passes positive, fails negative; indexed in `conformance/README.md`.
- Kit-own `.github/workflows/ci.yml` present and green on the PR.
- `VERSION` = `2.0.0`; `CHANGELOG` 2.0.0 entry; `docs/ROADMAP-KIT.md` Slice 1 marked done.
- Feature branch → PR opened; **human-ratified before merge** (governing-doc change).
