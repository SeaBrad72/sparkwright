# CI Platforms — Portability Reference

How the kit's CI contract is expressed on **GitHub Actions, GitLab CI, or any other platform**. The contract is the **gate-ids**, not a vendor — `conformance/ci-gates.sh` verifies the ids, so any platform that declares them by id conforms. The executable half of `DEVELOPMENT-STANDARDS.md` §14 (CI/CD Pipeline).

> **Principle — the contract is the interface, the platform is open.** The kit does not require GitHub. It requires that a pipeline declare the standardized gates *by id*, so the same conformance check verifies any platform. Pick your CI; keep the ids.

## The gate-id contract (platform-neutral)

Every project's CI must declare these **8 standardized gate-ids** (implementing the 7 required gates of §14 — supply-chain is two ids). `gate-install` is setup, **not** a gate.

| Gate-id | §14 gate |
|---------|----------|
| `gate-lint` | 1 — Lint |
| `gate-type-check` | 2 — Type-check |
| `gate-test` | 3 — Test + coverage |
| `gate-build` | 4 — Build |
| `gate-secret-scan` | 5 — Secret scan |
| `gate-dep-scan` | 6 — Dependency scan |
| `gate-sbom` | 7 — Supply-chain (SBOM) |
| `gate-provenance` | 7 — Supply-chain (provenance) |

`conformance/ci-gates.sh <workflow>` asserts all 8 are declared. It is **structural, best-effort, zero-dependency** — it recognizes the id, it does not run the pipeline. Pair it with the pipeline actually running (the gate must *do* the work, not merely be named).

## How each platform expresses the contract

### GitHub Actions — `id:` steps
A gate is a step whose `id:` is the gate-id:
```yaml
jobs:
  verify:
    steps:
      - id: gate-lint
        run: pnpm run lint
```
`ci-gates.sh` matches `id: gate-X` (anchored, ignores comments). Reference: `profiles/<stack>/ci.yml`. Drop in via `incept.sh --ci github` → `.github/workflows/ci.yml`.

### GitLab CI — `gate-X:` job keys
A gate is a top-level **job named exactly** the gate-id:
```yaml
gate-lint:
  stage: verify
  script: [pnpm run lint]
```
`ci-gates.sh` matches `gate-X:` at column 0 (anchored, ignores comments). Reference: `profiles/<stack>/ci.gitlab-ci.yml`. Drop in via `incept.sh --ci gitlab` → `.gitlab-ci.yml` at the repo root. Where GitLab ships a native control (Secret-Detection, Dependency-Scanning, CycloneDX SBOM templates), the reference names it in a comment — prefer it at scale.

### Azure DevOps — documented mapping (no shipped reference)
ADO is a **documented mapping**, not a shipped second reference — proportionate: one canonical reference plus the contract is enough, because the contract *is* the ids. Express each gate as a step with the gate-id as its `name`:
```yaml
steps:
  - script: pnpm run lint
    name: gate_lint        # ADO step 'name' must be a valid identifier — see note
    displayName: gate-lint
```
> **ADO naming caveat.** Azure Pipelines step `name` must match `[A-Za-z_][A-Za-z0-9_]*` — it cannot contain `-`. Use `gate_lint` for the machine `name` and `gate-lint` for `displayName`, and verify conformance against the **gate-ids as the contract** (a `yq`/`jq` check over `displayName`, or simply assert each gate ran). `ci-gates.sh`'s shell matcher targets GitHub `id:` and GitLab job keys; an ADO adopter verifies by the same gate-id convention with a platform-appropriate query. The kit states this rather than pretending the shell check covers ADO.

### Any other platform
Declare the 8 ids however the platform names units of work (job, stage, step, task), and verify them by id with a platform-appropriate query. The contract holds; only the syntax changes.

## Honest coupling note — what is *not* yet platform-neutral

Two helper scripts call the **GitHub API** (`gh`) directly. They are honest about it and degrade rather than pretend:

| Script | GitHub binding | On GitLab / ADO |
|--------|----------------|-----------------|
| `conformance/branch-protection.sh` | Reads `repos/.../branches/main/protection` via `gh api` | The equivalent is **adopter-owned**: GitLab *protected branches* (require MR + pipeline success + approval rule), ADO *branch policies* (require PR + build validation + reviewers). Wire it on your platform; the check returns **UNVERIFIED** (exit 2) off GitHub rather than a false pass. |
| `scripts/dora.sh` | Derives the DORA subset from GitHub APIs | Re-derive from GitLab (MR/pipeline analytics) or ADO (Pipelines/Boards analytics). It already prints **"unavailable"** per metric on any `gh` failure — it never fabricates a number. |

This is the same honesty discipline as the three-state conformance model (`conformance/verify.sh`): **green ≠ verified** — an unverifiable control reports UNVERIFIED, never a silent pass. Porting these two scripts to GitLab/ADO APIs is deliberately out of scope (adopter-owned, named here) rather than faked.

For the full GitLab adopter guide — branch protection wiring, control-plane ratification (the
keystone gap: the `gate-agent-boundary` merge-gate has no kit-shipped GitLab equivalent), and
DORA derivation — see [`gitlab-adoption.md`](gitlab-adoption.md).

## See also
- `DEVELOPMENT-STANDARDS.md` §14 — the gate contract and CI security hardening (two-job OIDC split).
- `conformance/ci-gates.sh` — the verifier; `conformance/README.md` — the conformance index.
- `profiles/<stack>/ci.yml` (GitHub) · `profiles/<stack>/ci.gitlab-ci.yml` (GitLab) — reference pipelines.
- `docs/work-tracking/adapters.md` — the analogous "contract, many backends" pattern for work-tracking.
