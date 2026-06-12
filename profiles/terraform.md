# Stack Profile — Terraform / IaC

> Reference profile. The concrete *how* for the universal `DEVELOPMENT-STANDARDS.md` on an infrastructure-as-code (Terraform) stack. Copy/adapt per project; record selection as ADR-000. The headline addition is the **policy-as-code gate**. (Pulumi/CDK/Ansible teams: generate a profile via `scripts/new-profile.sh`.)

**Stack:** Terraform ≥1.6 (HCL) · tflint · Checkov + OPA/conftest · Trivy · remote state (S3+DynamoDB / Terraform Cloud)
**Status:** reference

---

## Best for / Avoid when

**Best for:** Infrastructure-as-code, cloud provisioning.
**Avoid when:** Application logic — it provisions infra, it is not an app stack (pair with an app profile).

Choosing a stack? Compare all profiles → [../docs/STACK-SELECTION.md](../docs/STACK-SELECTION.md).

---

## 1. Toolchain
- **Engine:** Terraform ≥1.6 (HCL); providers pinned via `.terraform.lock.hcl` (committed)
- **Format/lint:** `terraform fmt` + **tflint** (provider ruleset) · **Validate:** `terraform validate`
- **Tests:** **`terraform test`** (native HCL `*.tftest.hcl`) · **Policy:** **Checkov** + **conftest/OPA** (tfsec-style misconfig is covered by **Trivy**, which tfsec is now merged into)
- **Test quality:** here the **policy/plan tests ARE the bar** (`terraform test` + Checkov/conftest = the `gate-policy` gate); mutation/property-based testing is **N/A for HCL** (no unit logic to mutate) — see `docs/operations/test-quality.md`
- **Inner loop:** `pre-commit` (`terraform fmt` + tflint; `terraform validate`) — fast feedback before CI (`docs/operations/dev-inner-loop.md`)
- **Supply-chain:** **Trivy** (config misconfig/vuln scan + CycloneDX inventory) · secrets: gitleaks

## 2. Project scaffold
```
environments/{dev,staging,prod}/   # per-env root modules + backend config
modules/<module>/{main.tf,variables.tf,outputs.tf}
tests/*.tftest.hcl                 # native terraform test
policy/                            # OPA rego + conftest tests
backend.tf                         # remote state (encrypted + locked)
.tflint.hcl · .terraform.lock.hcl  # lockfile committed (pinned providers)
docs/architecture/                 # ADRs (incl. ADR-000)
.github/workflows/ci.yml
.env.example · .gitignore          # gitignore *.tfstate, *.tfvars secrets, .terraform/
```
Baselines: tflint ruleset for your cloud; Checkov + conftest wired; `prevent_destroy` on critical resources.

## 3. Standard commands
```
install:       terraform init
validate:      terraform fmt -check -recursive && tflint && terraform validate
test:          terraform test
policy:        checkov -d . && conftest test .
build (plan):  terraform plan -out=tfplan
apply:         terraform apply tfplan
sbom:          trivy fs --format cyclonedx --output sbom.json .
```

## 4. CI/CD pipeline
Implements §14's 7 required gates **via IaC analogs, plus a policy gate**. Drop-in reference files live in **`profiles/terraform/`**:
- **`ci.yml`** → copy to `.github/workflows/ci.yml`. fmt+tflint → `terraform validate` (type-check) → `terraform test` → `terraform plan` (build) → **`gate-policy` (Checkov + conftest/OPA)** → gitleaks → Trivy config scan (dep-scan) → Trivy CycloneDX (sbom) → provenance on the plan.
- **`CODEOWNERS`**, **`BRANCH-PROTECTION.md`** → governance companions.

Conformance: `sh conformance/ci-gates.sh profiles/terraform/ci.yml` (8 standard gates; `gate-policy` is the additional IaC gate). IaC has no software artifact, so the gates map to analogs: `gate-build`=`terraform plan` (the plan is the artifact); `gate-type-check`=`terraform validate`; `gate-dep-scan`=Trivy config scan (vulnerable/misconfigured providers & modules); `gate-sbom`=Trivy CycloneDX (provider/module inventory). §14's 8 stay intact — no contract change.

## 5. Security implementation
- **Env/secrets:** `TF_VAR_*` / environment; **never** commit `*.tfvars` secrets or state; `.env.example` documents required vars.
- **State:** remote backend **encrypted at rest + locked** (S3+DynamoDB / Terraform Cloud); least-privilege state access; sensitive outputs marked `sensitive`; secrets sourced from a secrets manager, never plaintext in state.
- **Misconfig prevention:** Checkov + Trivy gate insecure defaults (public buckets, open security groups, unencrypted volumes, wildcard IAM); gitleaks catches hardcoded secrets.
- **Policy:** OPA/conftest enforces org rules (allowed regions, required tags, mandatory encryption) at `gate-policy`.
- **Static analysis & licenses (conditional gates — `docs/operations/security-scanning.md`):** `gate-sast` is satisfied by the existing Checkov/Trivy policy gate (IaC SAST); `gate-license` is N/A for Terraform (providers, not library dependencies).

## 6. Testing
- **`terraform test`** (native): `run` blocks asserting plan/apply outcomes and outputs on modules (with mocked or ephemeral providers).
- **Policy tests:** conftest/OPA unit tests for the rego rules.
- **Example plans:** each module's `examples/` must `plan` cleanly. These + `gate-policy` are the regression suite — a violation fails the build.

## 7. Resilience & observability
- **Plan/apply via CI with human approval**; **drift detection** (scheduled `terraform plan` → alert on diff); state versioning/backup (backend versioning); cost visibility (Infracost, optional); audit trail via CI logs + state history.

## 8. State & "migrations"
- Remote backend with **state locking**; never manual state edits — `terraform state mv`/`import` only via reviewed change. **create-before-destroy** + `prevent_destroy` on critical resources to avoid destructive replacement; treat resource renames as expand-contract (add new → migrate → remove old). No click-ops; all infra changes flow through plan→apply + review.

## 9. Release & deploy
- **plan → human review of the plan → apply** (the merge/apply gate). dev → staging → prod via separate roots/workspaces; **build provenance attested on the plan**. **Rollback:** apply the previous known-good revision (or `terraform apply` a reverted config); targeted applies for canary changes.
- **Container/deploy: N/A by design.** Terraform provisions infrastructure — the `plan → apply` **is** the deploy; there is no application container artifact, so this profile ships no Dockerfile/compose/deploy and `conformance/container-supply-chain.sh` skips it (N/A). The *infrastructure you provision* must still let the apps that run on it meet §14's container image supply-chain.

## 10. Recommended tools
Terraform · tflint (+ cloud ruleset) · Checkov · conftest/OPA · Trivy (config scan + SBOM; includes tfsec checks) · `terraform test` (native; Terratest for heavy integration) · Infracost (cost) · gitleaks · `actions/attest-build-provenance`. Default Claude models: `claude-sonnet-4-6`, escalate to Opus for hard reasoning.

## 11. Stack-specific gotchas
- **Never commit state or `*.tfvars` secrets** — gitignore `*.tfstate*`, `.terraform/`, secret tfvars; use `TF_VAR_`/env + encrypted remote state.
- Commit `.terraform.lock.hcl` (pins provider versions); `fmt`/`validate`/`tflint`/`checkov`/`conftest` run offline, but `terraform plan` needs provider creds — CI wires **read-only/plan** creds (or `-backend=false` for pure validation).
- **The plan is reviewed by a human before apply** — never auto-apply to prod without the merge gate (this is the §13 human-gated, high-blast-radius action).
- **tfsec is merged into Trivy** — use Trivy for tfsec-style checks; don't add a standalone tfsec.
- **Conditional §13/15-factor:** an IaC repo defines infrastructure; it is not a running service — port-binding, concurrency, statelessness, disposability, and the process model are **N/A (mark with a one-line reason)**. The *infrastructure you provision* must still let the apps meet those factors.

---

**Last Updated:** 2026-06-06
