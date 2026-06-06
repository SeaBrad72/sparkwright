# Design — Slice 5d: Terraform / IaC Stack Profile (policy-gate-centric)

**Date:** 2026-06-06
**Status:** Approved (brainstorming) — pending spec review
**Author:** Bradley James + agent
**Roadmap:** Final shape-different profile (after ML 5c, data-engineering 5c2). Completes the profile family; followed by Slice 6 (enterprise addendum).

---

## 1. Goal

Ship a first-class **Terraform / IaC** stack profile (`profiles/terraform/`) for infrastructure-as-code, with **policy-as-code** (`gate-policy`: Checkov + tfsec + OPA/conftest) as the headline gate. Prove the §14 contract holds even for a config-only repo with no software artifact — by mapping all 8 standard gates to real IaC analogs (no contract change). Exercises the conditional 15-factor mechanism for a non-service repo.

## 2. Decisions (from brainstorming)

- **§14 reconciliation:** **IaC analogs — keep §14's 8 intact, no contract change.** `gate-dep-scan` = Trivy/Checkov (vulnerable/misconfigured providers & modules); `gate-sbom` = Trivy CycloneDX inventory of providers/modules. `ci-gates.sh` unchanged.
- **Tooling:** Terraform (HCL) · `terraform fmt` + tflint (lint) · `terraform validate` (type-check) · `terraform test` native HCL tests · `terraform plan` (build) · **Checkov + tfsec + OPA/conftest** (`gate-policy`) · gitleaks · Trivy (SBOM/dep analogs).
- **gate-policy:** dedicated extra step — the headline IaC quality bar (parallel to ML's `gate-eval`, data-eng's `gate-data-quality`).
- **Conditional §13/15-factor:** IaC repo defines infra, isn't a running service → port-binding/concurrency/stateless/disposability/processes **N/A-with-reason**; live concerns = remote state (encrypted+locked), plan→apply, drift.
- **Version:** **2.7.0** (MINOR, additive). Profile name `terraform`.

## 3. Deliverables

| Part | Files |
|------|-------|
| Profile | `profiles/terraform.md` (11 sections) |
| Companion | `profiles/terraform/{ci.yml,CODEOWNERS,BRANCH-PROTECTION.md}` |
| Meta | `VERSION` → `2.7.0`; `CHANGELOG.md` 2.7.0; `docs/ROADMAP-KIT.md` note (profile family complete) |

Profile name = `terraform`; `--stack terraform` + `profiles/terraform/` align so `incept.sh --stack terraform` wires CI. Validated by `conformance/ci-gates.sh` (8 ids) + `profile-completeness.sh` — no new conformance logic.

## 4. Detailed design

### 4.1 `profiles/terraform.md` (11 sections)

1. **Toolchain:** Terraform ≥1.6 (HCL) · `terraform fmt` + **tflint** (lint) · `terraform validate` (validate) · **`terraform test`** (native) · **Checkov + tfsec + conftest/OPA** (policy) · **Trivy** (SBOM/dep) · gitleaks.
2. **Scaffold:** `environments/{dev,staging,prod}/`, `modules/<module>/{main.tf,variables.tf,outputs.tf}`, `tests/*.tftest.hcl`, `policy/` (OPA rego + conftest), `.tflint.hcl`, `backend.tf` (remote state), `.github/workflows/ci.yml`, `.terraform.lock.hcl` (committed), `.env.example`.
3. **Standard commands:** install `terraform init`; validate `terraform fmt -check -recursive && tflint && terraform validate`; test `terraform test`; **policy `checkov -d . && tfsec . && conftest test .`**; plan/build `terraform plan -out=tfplan`; apply `terraform apply tfplan`.
4. **CI/CD:** §14's 7 gates (IaC analogs) **+ `gate-policy`**; points to `profiles/terraform/ci.yml`. Note: no software artifact — `gate-build`=`terraform plan` (the plan IS the artifact); `gate-type-check`=`terraform validate`; `gate-dep-scan`=Trivy/Checkov (provider/module vuln+misconfig); `gate-sbom`=Trivy CycloneDX (provider/module inventory). `gate-policy` (Checkov+tfsec+OPA) is the headline.
5. **Security:** secrets via `TF_VAR_*`/env (never in `.tf` or committed state); **remote state encrypted + locked**, least-privilege state access; Checkov/tfsec gate misconfig (open security groups, public buckets, unencrypted volumes) + hardcoded secrets; no plaintext secrets in state (use a secrets manager + `sensitive`).
6. **Testing:** **`terraform test`** (native HCL — `run` blocks asserting plan/apply outcomes on modules) + **policy tests** (conftest/OPA unit tests for rego) + **examples that plan cleanly**. These + `gate-policy` are the regression suite.
7. **Resilience & observability:** plan/apply via CI with approvals; **drift detection** (scheduled `terraform plan` → alert on diff); state backup/versioning (backend versioning); audit via CI logs + state history; cost estimation (Infracost) optional.
8. **State & "migrations":** remote backend (S3 + DynamoDB lock / Terraform Cloud); **state locking**; never manual state edits — `terraform state mv`/`import` via reviewed change; **create-before-destroy** + `prevent_destroy` on critical resources to avoid destructive replacement; expand-contract for resource renames.
9. **Release & deploy:** **plan → human review of the plan → apply** (the merge/apply gate); dev → staging → prod via workspaces/dirs; **provenance attested on the plan**; rollback = apply the previous known-good config (or `terraform apply` a reverted revision); targeted applies for canary.
10. **Recommended libraries/tools:** Terraform · tflint · Checkov · tfsec · conftest (OPA) · Trivy · `terraform test` (native) (or Terratest for heavy integration) · Infracost (cost) · TFLint ruleset for the cloud provider. Default Claude models: `claude-sonnet-4-6`, escalate to Opus for hard reasoning.
11. **Stack-specific gotchas:** **never commit state or `*.tfvars` secrets** — `TF_VAR_`/env + remote encrypted state; commit `.terraform.lock.hcl` (pin provider versions); `terraform validate`/`fmt`/`tflint` run offline, but `plan` needs provider creds (CI uses read-only/plan creds or `-backend=false` for pure validation); the **plan is reviewed by a human before apply** — never auto-apply to prod without the merge gate; **conditional §13** — an IaC repo isn't a running service, so port-binding/concurrency/statelessness/disposability/processes are **N/A (mark with a one-line reason)**; the *managed infrastructure* must still meet the app-side factors. set the tflint ruleset + Checkov/tfsec to your cloud.

### 4.2 `profiles/terraform/ci.yml`

8 standard `gate-*` ids **+ `gate-policy`**, on `ubuntu-latest`:
- `gate-install`=`terraform init -backend=false` (offline init for validation); `gate-lint`=`terraform fmt -check -recursive && tflint`; `gate-type-check`=`terraform validate`; `gate-test`=`terraform test`; `gate-build`=`terraform plan -out=tfplan -input=false` (the plan artifact; needs provider creds — adopter wires them); **`gate-policy`**=`checkov -d . && tfsec . && conftest test .` (non-zero on violation); `gate-secret-scan`=gitleaks; `gate-dep-scan`=`trivy config --severity HIGH,CRITICAL .` (provider/module misconfig + vuln); `gate-sbom`=`trivy fs --format cyclonedx --output sbom.json .` (provider/module inventory; upload `sbom.json`); `gate-provenance`=`actions/attest-build-provenance` on `tfplan` (release path).
- Setup: `hashicorp/setup-terraform@v3`. `ci-gates.sh` requires the 8 standard ids; `gate-policy` is an allowed extra.

### 4.3 Companions
`CODEOWNERS` + `BRANCH-PROTECTION.md` derived from the Python reference (retitled "terraform profile").

## 5. Validation / testing

- `sh conformance/ci-gates.sh profiles/terraform/ci.yml` → exit 0 (8 ids; gate-policy extra fine).
- `sh conformance/profile-completeness.sh` → passes all 10 profiles.
- `profiles/terraform/ci.yml` valid YAML; SBOM upload path matches output (`sbom.json`).
- **incept wiring:** `incept.sh --noninteractive --stack terraform` into a temp copy wires CI + `inception-done.sh` passes; the wired `ci.yml` passes `ci-gates.sh`.
- Existing 9 profiles unchanged (additive). Kit CI green; check-links covers the new doc.

## 6. Risks & mitigations

- **`gate-build`/`gate-policy` need provider creds / `plan` needs a backend:** documented — `validate`/`fmt`/`tflint`/`checkov`/`tfsec` run offline; `plan` needs read-only creds (adopter wires them); `-backend=false` for pure validation. Kit CI doesn't execute the reference (only ci-gates checks ids).
- **dep-scan vs policy overlap:** `gate-dep-scan` (Trivy: provider/module vuln + outdated) and `gate-policy` (Checkov/tfsec/OPA: misconfig + org rules) are different lenses; §4 frames them distinctly.
- **SBOM-for-IaC is non-standard:** Trivy genuinely emits CycloneDX for a filesystem incl. the lockfile — a real provider/module inventory. Keeps §14's 8 intact (the chosen reconciliation).
- **Conditional §13 mis-applied:** §11 + §4 mark which factors are N/A-with-reason; the managed infra still meets app-side factors.
- **SBOM/coverage-path accuracy (Slice-5 lesson):** `trivy ... --output sbom.json` ↔ upload `sbom.json`. Verified.

## 7. Out of scope

OpenTofu / Pulumi / CDK / Ansible variants (generate-your-own via `new-profile.sh`) · the enterprise addendum (Slice 6) · whether supply-chain gates should be conditional (we kept §14 intact; revisit in Slice 6 if desired) · executing `terraform plan/apply` in kit CI (adopter-side).

## 8. Definition of Done

- `profiles/terraform.md` (11 sections, no `[...]`) + `profiles/terraform/{ci.yml,CODEOWNERS,BRANCH-PROTECTION.md}`; `ci.yml` passes `ci-gates.sh` (8 ids) + declares `gate-policy`.
- `profile-completeness.sh` green over all 10 profiles.
- `incept.sh --stack terraform` wires CI + passes `inception-done.sh` (verified in temp).
- Kit CI green; existing 9 profiles unchanged.
- `VERSION` = `2.7.0`; CHANGELOG 2.7.0; roadmap note (profile family complete).
- Feature branch → PR; **human-ratified before merge**.
