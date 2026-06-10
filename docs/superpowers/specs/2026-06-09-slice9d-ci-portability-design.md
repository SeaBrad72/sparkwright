# Slice 9d — CI-Platform Portability (design)

**Date:** 2026-06-09 · **Arc:** Slice 9, Tier 1 · **Version target:** MINOR → **v2.28.0**
**Input:** the review's convergent finding #3 + portability lens R4 — the kit assumes **GitHub Actions**: `conformance/ci-gates.sh` only recognizes GitHub `id: gate-X` step syntax, and `incept.sh` hardcodes `.github/workflows/ci.yml`, so a GitLab / Azure-DevOps adopter must rewrite all CI and can't pass conformance.

## Scope (the split)

This slice ships **CI-platform portability** — pure-additive, no control-plane edits. The companion **9d-b (runtime-guard portability)** — extracting the guard deny-matrix into a sourceable core + a generic pre-push hook for non-Claude runtimes — refactors `guard.sh` (control-plane) and is deferred to the human-gated batch closeout.

## Problem

`ci-gates.sh`'s own header claims "any workflow that adopts these ids can be verified, in any language," but its matcher (`^…id:[[:space:]]*gate-X`) is GitHub-Actions-only. GitLab CI keys jobs by name with no `id:` field, so a native GitLab pipeline can never satisfy the check. The contract (the 8 standardized gate-ids) is genuinely platform-neutral; only the *matcher* and the *reference* are GitHub-bound.

## Design — make the platform-neutral claim true

### 1. `ci-gates.sh` — recognize a GitLab gate alongside a GitHub gate

For each required `gate-X`, accept **either**:
- **GitHub Actions step:** the existing `^[[:space:]]*(-[[:space:]]+)?id:[[:space:]]*["']?gate-X["']?[[:space:]]*(#.*)?$`, **or**
- **GitLab CI job key:** `^gate-X:[[:space:]]*(#.*)?$` (a top-level job named exactly `gate-X`).

Same anti-false-positive discipline (line-anchored, not in a comment). Update the header to say it recognizes GitHub `id:` steps **and** GitLab job keys; the contract is the gate-ids, the platform is open. No behavior change for existing GitHub workflows (the GitHub branch is unchanged). `ci-gates.sh` is not control-plane — editable.

### 2. A GitLab CI reference — `profiles/typescript-node/ci.gitlab-ci.yml`

A real GitLab pipeline expressing the same gates as jobs named `gate-lint`, `gate-type-check`, `gate-test`, `gate-build`, `gate-secret-scan`, `gate-dep-scan`, `gate-sbom`, `gate-provenance` (+ `gate-install` setup), using the ts-node toolchain. Demonstrates the convention; the contract is the gate-ids, so adopters express the same in their stack. Notes GitLab-native equivalents (e.g. GitLab's built-in SBOM/dependency-scanning templates) in comments. Must pass `sh conformance/ci-gates.sh profiles/typescript-node/ci.gitlab-ci.yml`.

### 3. `incept.sh --ci github|gitlab`

Add a `--ci` flag (default `github`). `github` → copy `profiles/<stack>/ci.yml` to `.github/workflows/ci.yml` (current behavior). `gitlab` → copy `profiles/<stack>/ci.gitlab-ci.yml` to `.gitlab-ci.yml` (repo root, where GitLab requires it). If the chosen reference is absent for the stack, print the same "author one satisfying §14 / ci-gates.sh" note as today. `incept.sh` is `scripts/` — editable.

### 4. `docs/operations/ci-platforms.md` — the portability contract

- The **gate-id contract** (the 8 ids) as the platform-neutral interface.
- How to express it in **GitHub Actions** (`id: gate-X` steps), **GitLab CI** (`gate-X:` job keys — point at the reference), and **Azure DevOps** (documented mapping: a `job:`/`step:` named/`displayName: gate-X`, with the convention to verify via the gate-ids; ADO is a documented mapping, not a shipped second reference — proportionate).
- **Honest coupling note:** `branch-protection.sh` and `scripts/dora.sh` use the **GitHub API** (`gh`); on GitLab/ADO the equivalent (protected-branches API, pipeline/MR analytics) is the adopter's to wire — the kit states this rather than pretending coverage. (This is the same honesty as 9a's UNVERIFIED.)
- Cross-link from `conformance/README.md` (ci-gates row note) and `docs/work-tracking/adapters.md` style.

## Files

| File | Change |
|------|--------|
| `conformance/ci-gates.sh` | Add GitLab job-key alternative to the per-gate matcher; header update |
| `profiles/typescript-node/ci.gitlab-ci.yml` | **New** — GitLab reference pipeline with `gate-X` jobs |
| `scripts/incept.sh` | `--ci github\|gitlab` flag → correct output path/reference |
| `docs/operations/ci-platforms.md` | **New** — gate-id contract + GitHub/GitLab/ADO expression + honest gh-coupling note |
| `conformance/README.md` | ci-gates row note (recognizes GitHub + GitLab); link the new doc |
| `DEVELOPMENT-STANDARDS.md` §14 | One line: gates are expressed by id on any CI platform (→ ci-platforms.md) |
| `CHANGELOG.md`, `VERSION` | 2.28.0 |
| `docs/ROADMAP-SLICE9.md` | 9d row: CI-portability shipped; 9d-b runtime-guard split out (deferred to terminal) |
| `.github/workflows/ci.yml` | (batch-closeout, human-applied) add a step running `ci-gates.sh` against the GitLab reference |

## Verification
- `sh conformance/ci-gates.sh profiles/typescript-node/ci.yml` → still OK (GitHub; no regression).
- `sh conformance/ci-gates.sh profiles/typescript-node/ci.gitlab-ci.yml` → OK (GitLab job keys recognized).
- A negative: a GitLab file missing a gate job → FAIL naming it. A GitHub file with a gate id only in a comment → still FAIL (anti-false-positive preserved).
- `incept.sh --ci gitlab` in a temp dir writes `.gitlab-ci.yml`; `--ci github` writes `.github/workflows/ci.yml`; bad `--ci` value errors.
- dash-clean; `check-links.sh` green; existing conformance unaffected.
- Governance: feature branch → PR → human ratification; §14 is a governing surface (security-owner lens on the contract wording).

## Out of scope / deferred
- **9d-b runtime-guard portability** (needs `guard.sh` refactor → terminal).
- Full per-profile GitLab pipelines for all 10 stacks (one canonical reference + the contract is proportionate; adopters express it per stack).
- A full Azure DevOps reference pipeline (documented mapping instead).
- Porting `branch-protection.sh`/`dora.sh` to GitLab/ADO APIs (documented as adopter-owned).

## Known implications
- `ci-gates.sh` now passes a GitLab pipeline that names jobs `gate-X`. An adopter who names a *non-gate* job `gate-lint` by coincidence would satisfy that gate — same best-effort, structural limitation the GitHub `id:` matcher already has (paired with the pipeline actually running). Documented in the header.
