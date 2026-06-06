# Slice 5d: Terraform / IaC Stack Profile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a first-class **Terraform / IaC** stack profile (`profiles/terraform/`) with `gate-policy` (Checkov + OPA/conftest) as the headline gate, satisfying §14's 8 gates via IaC analogs (no contract change).

**Architecture:** Profile slice on branch `feature/slice-5d-terraform-profile`, mirroring the Slice 5/5c pattern. `profiles/terraform.md` (11 sections) + `profiles/terraform/ci.yml` (8 standard `gate-*` ids **+ `gate-policy`**) + companions derived from the Python reference. Validated by `conformance/ci-gates.sh` (8 ids; gate-policy is an allowed extra) + `profile-completeness.sh` — no new conformance logic. IaC analogs: `gate-build`=`terraform plan`, `gate-dep-scan`=Trivy config scan (incl. tfsec-style misconfig — tfsec is merged into Trivy upstream), `gate-sbom`=Trivy CycloneDX provider/module inventory.

**Tech Stack:** Markdown, GitHub Actions YAML, POSIX `sh`. Profile: Terraform ≥1.6 · tflint · Checkov · conftest/OPA · Trivy · `terraform test`. Spec: `docs/superpowers/specs/2026-06-06-slice5d-terraform-profile-design.md`.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `profiles/terraform.md` (new) | Terraform/IaC profile, 11 sections |
| `profiles/terraform/ci.yml` (new) | Reference CI (8 gates via IaC analogs + `gate-policy`) |
| `profiles/terraform/CODEOWNERS` (new) | Review routing (derived from Python ref) |
| `profiles/terraform/BRANCH-PROTECTION.md` (new) | Branch protection (derived from Python ref) |
| `VERSION` `CHANGELOG.md` `docs/ROADMAP-KIT.md` (edit) | 2.7.0; changelog; roadmap (family complete) |

**Precondition:** on branch `feature/slice-5d-terraform-profile`. The committed `profiles/python/CODEOWNERS` + `profiles/python/BRANCH-PROTECTION.md` are the source for the derived companions.

---

### Task 1: profiles/terraform.md

**Files:** Create `profiles/terraform.md`

- [ ] **Step 1: Write the profile** — create `profiles/terraform.md` with exactly this content (write LITERAL triple-backtick fences where scaffold + commands blocks are shown):

```markdown
# Stack Profile — Terraform / IaC

> Reference profile. The concrete *how* for the universal `DEVELOPMENT-STANDARDS.md` on an infrastructure-as-code (Terraform) stack. Copy/adapt per project; record selection as ADR-000. The headline addition is the **policy-as-code gate**. (Pulumi/CDK/Ansible teams: generate a profile via `scripts/new-profile.sh`.)

**Stack:** Terraform ≥1.6 (HCL) · tflint · Checkov + OPA/conftest · Trivy · remote state (S3+DynamoDB / Terraform Cloud)
**Status:** reference

---

## 1. Toolchain
- **Engine:** Terraform ≥1.6 (HCL); providers pinned via `.terraform.lock.hcl` (committed)
- **Format/lint:** `terraform fmt` + **tflint** (provider ruleset) · **Validate:** `terraform validate`
- **Tests:** **`terraform test`** (native HCL `*.tftest.hcl`) · **Policy:** **Checkov** + **conftest/OPA** (tfsec-style misconfig is covered by **Trivy**, which tfsec is now merged into)
- **Supply-chain:** **Trivy** (config misconfig/vuln scan + CycloneDX inventory) · secrets: gitleaks

## 2. Project scaffold
\`\`\`
environments/{dev,staging,prod}/   # per-env root modules + backend config
modules/<module>/{main.tf,variables.tf,outputs.tf}
tests/*.tftest.hcl                 # native terraform test
policy/                            # OPA rego + conftest tests
backend.tf                         # remote state (encrypted + locked)
.tflint.hcl · .terraform.lock.hcl  # lockfile committed (pinned providers)
docs/architecture/                 # ADRs (incl. ADR-000)
.github/workflows/ci.yml
.env.example · .gitignore          # gitignore *.tfstate, *.tfvars secrets, .terraform/
\`\`\`
Baselines: tflint ruleset for your cloud; Checkov + conftest wired; `prevent_destroy` on critical resources.

## 3. Standard commands
\`\`\`
install:       terraform init
validate:      terraform fmt -check -recursive && tflint && terraform validate
test:          terraform test
policy:        checkov -d . && conftest test .
build (plan):  terraform plan -out=tfplan
apply:         terraform apply tfplan
sbom:          trivy fs --format cyclonedx --output sbom.json .
\`\`\`

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

## 10. Recommended tools
Terraform · tflint (+ cloud ruleset) · Checkov · conftest/OPA · Trivy (config scan + SBOM; includes tfsec checks) · `terraform test` (native; Terratest for heavy integration) · Infracost (cost) · gitleaks · `actions/attest-build-provenance`. Default Claude models: `claude-sonnet-4-6`, escalate to Opus for hard reasoning.

## 11. Stack-specific gotchas
- **Never commit state or `*.tfvars` secrets** — gitignore `*.tfstate*`, `.terraform/`, secret tfvars; use `TF_VAR_`/env + encrypted remote state.
- Commit `.terraform.lock.hcl` (pins provider versions); `fmt`/`validate`/`tflint`/`checkov`/`conftest` run offline, but `terraform plan` needs provider creds — CI wires **read-only/plan** creds (or `-backend=false` for pure validation).
- **The plan is reviewed by a human before apply** — never auto-apply to prod without the merge gate (this is the §13 human-gated, high-blast-radius action).
- **tfsec is merged into Trivy** — use Trivy for tfsec-style checks; don't add a standalone tfsec.
- **Conditional §13/15-factor:** an IaC repo defines infrastructure; it is not a running service — port-binding, concurrency, statelessness, disposability, and the process model are **N/A (mark with a one-line reason)**. The *infrastructure you provision* must still let the apps meet those factors.
\`\`\`

---

**Last Updated:** 2026-06-06
```

- [ ] **Step 2: Verify and commit**

```bash
cd /Users/bradleyjames/Development/agentic-sdlc-kit
i=1; ok=1; while [ "$i" -le 11 ]; do grep -Eq "^## ${i}\. " profiles/terraform.md || { echo "missing §$i"; ok=0; }; i=$((i+1)); done; [ "$ok" -eq 1 ] && echo "11 sections OK"
grep -Fq '[...]' profiles/terraform.md && echo "FAIL placeholder" || echo "no [...] placeholder"
git add profiles/terraform.md
git commit -m "feat: add Terraform/IaC stack profile (policy-gate-centric)"
```
Expected: `11 sections OK`; `no [...] placeholder`.

---

### Task 2: profiles/terraform/ (ci.yml + CODEOWNERS + BRANCH-PROTECTION)

**Files:** Create `profiles/terraform/ci.yml`, `profiles/terraform/CODEOWNERS`, `profiles/terraform/BRANCH-PROTECTION.md`

- [ ] **Step 1: Write `profiles/terraform/ci.yml`** with exactly this content:

```yaml
# Reference CI pipeline for the Terraform/IaC profile.
# COPY & ADAPT: copy to your project's .github/workflows/ci.yml. Inert here in the kit.
# Satisfies DEVELOPMENT-STANDARDS.md §14 via IaC analogs (no contract change) PLUS gate-policy.
#   gate-build = terraform plan (the plan is the artifact)
#   gate-dep-scan = Trivy config scan (incl. tfsec-style misconfig — tfsec is merged into Trivy)
#   gate-sbom = Trivy CycloneDX provider/module inventory
# conformance/ci-gates.sh asserts the 8 standard ids; gate-policy is an allowed extra.
# HARDENING: pin uses:/tool versions for production.
name: CI

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read
  id-token: write
  attestations: write

jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: '1.9'
      - uses: terraform-linters/setup-tflint@v4

      - name: Init (offline)
        id: gate-install
        run: terraform init -backend=false

      - name: Lint
        id: gate-lint
        run: |
          terraform fmt -check -recursive
          tflint --init
          tflint

      - name: Validate
        id: gate-type-check
        run: terraform validate

      - name: Test
        id: gate-test
        run: terraform test

      - name: Build (terraform plan)
        id: gate-build
        # The plan is the IaC build artifact. Needs provider creds — wire read-only/plan
        # credentials in your repo (e.g. OIDC to the cloud). -backend=false for pure validation.
        run: terraform plan -out=tfplan -input=false

      - name: Policy-as-code (Checkov + OPA/conftest)
        id: gate-policy
        run: |
          pipx run checkov -d . --quiet --compact
          CONFTEST_VERSION=0.56.0
          curl -sSfL "https://github.com/open-policy-agent/conftest/releases/download/v${CONFTEST_VERSION}/conftest_${CONFTEST_VERSION}_Linux_x86_64.tar.gz" | tar -xz conftest
          ./conftest test .

      - name: Secret scan
        id: gate-secret-scan
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          # GITLEAKS_LICENSE: ${{ secrets.GITLEAKS_LICENSE }}  # required for org repos

      - name: Dependency / misconfig scan (Trivy config)
        id: gate-dep-scan
        uses: aquasecurity/trivy-action@0.24.0
        with:
          scan-type: config
          scan-ref: .
          severity: HIGH,CRITICAL
          exit-code: '1'

      - name: Generate SBOM (Trivy CycloneDX)
        id: gate-sbom
        uses: aquasecurity/trivy-action@0.24.0
        with:
          scan-type: fs
          scan-ref: .
          format: cyclonedx
          output: sbom.json

      - name: Upload SBOM
        uses: actions/upload-artifact@v4
        with:
          name: sbom
          path: sbom.json

      - name: Attest build provenance
        id: gate-provenance
        # Attest the Terraform plan on the release path.
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        uses: actions/attest-build-provenance@v1
        with:
          subject-path: tfplan
```

- [ ] **Step 2: Derive the governance companions**

```bash
cd /Users/bradleyjames/Development/agentic-sdlc-kit
sed 's/Python profile/Terraform profile/' profiles/python/CODEOWNERS > profiles/terraform/CODEOWNERS
sed 's/(Python profile)/(Terraform profile)/' profiles/python/BRANCH-PROTECTION.md > profiles/terraform/BRANCH-PROTECTION.md
```

- [ ] **Step 3: Verify and commit**

```bash
cd /Users/bradleyjames/Development/agentic-sdlc-kit
sh conformance/ci-gates.sh profiles/terraform/ci.yml; echo "exit=$?"
grep -q "id: gate-policy" profiles/terraform/ci.yml && echo "gate-policy present"
ruby -ryaml -e "YAML.load_file('profiles/terraform/ci.yml'); puts 'YAML OK'"
test -f profiles/terraform/CODEOWNERS && grep -q "required_status_checks" profiles/terraform/BRANCH-PROTECTION.md && echo "companions OK"
git add profiles/terraform/ci.yml profiles/terraform/CODEOWNERS profiles/terraform/BRANCH-PROTECTION.md
git commit -m "feat: add Terraform reference CI (8 gates via IaC analogs + gate-policy)"
```
Expected: ci-gates `OK ... declares all required CI gates`, `exit=0`; `gate-policy present`; `YAML OK`; `companions OK`.

---

### Task 3: VERSION + CHANGELOG + ROADMAP (2.7.0)

**Files:** Modify `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-KIT.md`

- [ ] **Step 1: Bump VERSION** — overwrite `VERSION` with exactly one line + trailing newline:

```
2.7.0
```

- [ ] **Step 2: Add the 2.7.0 CHANGELOG entry** — in `CHANGELOG.md`, find this exact line:

```
## [2.6.0] - 2026-06-06
```

Insert IMMEDIATELY BEFORE it:

```
## [2.7.0] - 2026-06-06

Slice 5d — Terraform/IaC stack profile. Completes the profile family (10 stacks). Proves §14's 8 gates hold even for config-only IaC — via analogs, no contract change.

### Added
- `profiles/terraform.md` + `profiles/terraform/` (`ci.yml`, `CODEOWNERS`, `BRANCH-PROTECTION.md`) — Terraform ≥1.6 · tflint · `terraform validate`/`test` · Checkov + conftest/OPA · Trivy · gitleaks.
- A dedicated **`gate-policy`** step (Checkov + conftest/OPA) — the IaC headline gate (parallel to ML's `gate-eval` and data-engineering's `gate-data-quality`).

### Note
IaC has no software artifact, so §14's gates map to **analogs**, keeping the 8 intact (no `ci-gates.sh`/§14 change): `gate-build` = `terraform plan` (the plan is the artifact); `gate-dep-scan` = Trivy config scan (vulnerable/misconfigured providers & modules — tfsec is merged into Trivy); `gate-sbom` = Trivy CycloneDX (provider/module inventory). The profile applies the **conditional 15-factor** mechanism (an IaC repo isn't a running service → port-binding/concurrency/stateless/disposability N/A-with-reason). `incept.sh --stack terraform` wires the profile's CI.

```

- [ ] **Step 3: Add the 2.7.0 link reference** — in `CHANGELOG.md`, find:

```
[2.6.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.6.0
```

Replace with:

```
[2.7.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.7.0
[2.6.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.6.0
```

- [ ] **Step 4: Update the roadmap** — in `docs/ROADMAP-KIT.md`, find this exact line:

```
| 5c2 ✅ | **Data-engineering profile** *(shipped v2.6.0)* | `profiles/_TEMPLATE.md` | `profiles/data-engineering/` — dbt + Dagster + Python; `gate-data-quality` (dbt build + Great Expectations) | `conformance/profile-completeness.sh` |
```

Replace with:

```
| 5c2 ✅ | **Data-engineering profile** *(shipped v2.6.0)* | `profiles/_TEMPLATE.md` | `profiles/data-engineering/` — dbt + Dagster + Python; `gate-data-quality` (dbt build + Great Expectations) | `conformance/profile-completeness.sh` |
| 5d ✅ | **Terraform/IaC profile** *(shipped v2.7.0)* | `profiles/_TEMPLATE.md` | `profiles/terraform/` — Terraform + tflint + Checkov + conftest/OPA + Trivy; `gate-policy`; §14 via IaC analogs | `conformance/profile-completeness.sh` |
```

- [ ] **Step 5: Verify and commit**

```bash
cd /Users/bradleyjames/Development/agentic-sdlc-kit
cat VERSION
grep -c "## \[2.7.0\]" CHANGELOG.md
grep -c "shipped v2.7.0" docs/ROADMAP-KIT.md
git add VERSION CHANGELOG.md docs/ROADMAP-KIT.md
git commit -m "release: 2.7.0 — Slice 5d Terraform/IaC profile (changelog + roadmap)"
```
Expected: `2.7.0`; `1`; `1`.

---

### Task 4: Final validation + PR

**Files:** none created; verification + PR only.

- [ ] **Step 1: Full conformance sweep (10 profiles)**

```bash
cd /Users/bradleyjames/Development/agentic-sdlc-kit
sh conformance/profile-completeness.sh; echo "exit=$?"
for p in typescript-node python java-spring dotnet go rust kotlin ml data-engineering terraform; do sh conformance/ci-gates.sh "profiles/$p/ci.yml" >/dev/null && echo "ci-gates $p OK"; done
grep -q "id: gate-policy" profiles/terraform/ci.yml && echo "gate-policy present"
sh conformance/agent-autonomy.sh >/dev/null && echo "agent-autonomy OK"
sh conformance/check-links.sh >/dev/null && echo "check-links OK"
```
Expected: profile-completeness all PASS + `exit=0`; `ci-gates <p> OK` for all 10; `gate-policy present`; agent-autonomy OK; check-links OK.

- [ ] **Step 2: incept wires the terraform profile (end-to-end)**

```bash
cd /Users/bradleyjames/Development/agentic-sdlc-kit
tmp=$(mktemp -d); git archive HEAD | tar -x -C "$tmp"
( cd "$tmp" && sh scripts/incept.sh --noninteractive --name DemoIaC --intent-owner "CI" --stack terraform --backlog md ) >/dev/null
sh conformance/inception-done.sh "$tmp" >/dev/null && echo "incept --stack terraform -> inception-done OK"
sh conformance/ci-gates.sh "$tmp/.github/workflows/ci.yml" >/dev/null && echo "wired CI satisfies §14"
grep -q "id: gate-policy" "$tmp/.github/workflows/ci.yml" && echo "wired CI carries gate-policy"
rm -rf "$tmp"
```
Expected: all three OK lines.

- [ ] **Step 3: Existing 9 profiles untouched (additive)**

```bash
cd /Users/bradleyjames/Development/agentic-sdlc-kit
git diff --stat main..HEAD -- profiles/typescript-node.md profiles/python.md profiles/java-spring.md profiles/dotnet.md profiles/go.md profiles/rust.md profiles/kotlin.md profiles/ml.md profiles/data-engineering.md | tail -1
echo "(empty above = unchanged)"
```
Expected: no diff line.

- [ ] **Step 4: Push and open the PR**

```bash
cd /Users/bradleyjames/Development/agentic-sdlc-kit
git push -u origin feature/slice-5d-terraform-profile
gh pr create --title "Slice 5d: Terraform/IaC profile — gate-policy, §14 via IaC analogs (v2.7.0)" --body "$(cat <<'EOF'
## Summary
A first-class **Terraform / IaC** profile — completes the profile family at **10 stacks**. Proves §14's 8 gates hold for a config-only repo via analogs (no contract change).

- **`profiles/terraform.md`** + `profiles/terraform/` — Terraform ≥1.6 · tflint · `terraform validate`/`test` · Checkov + conftest/OPA · Trivy · gitleaks.
- **`gate-policy`** (Checkov + conftest/OPA) — the IaC headline gate (3rd domain gate after ML's `gate-eval`, data-eng's `gate-data-quality`).
- **§14 via IaC analogs (no contract change):** `gate-build`=`terraform plan` (the plan is the artifact); `gate-dep-scan`=Trivy config scan (incl. tfsec-style misconfig — tfsec is merged into Trivy); `gate-sbom`=Trivy CycloneDX (provider/module inventory).
- **Conditional 15-factor:** IaC repo isn't a service → port-binding/concurrency/stateless N/A-with-reason; the provisioned infra must still let apps meet those factors.
- **Release** 2.7.0 (MINOR). Additive — the existing 9 profiles are untouched.

## Verified
`ci.yml` passes `ci-gates.sh` (8 ids; gate-policy extra); `profile-completeness.sh` passes all 10; `incept --stack terraform` wires CI (carrying gate-policy) + passes `inception-done.sh` + §14. SBOM path matches Trivy output. Zero new conformance logic.

## Ratification
Additive profile. **Human ratification required before merge.**

Spec: `docs/superpowers/specs/2026-06-06-slice5d-terraform-profile-design.md`
Plan: `docs/superpowers/plans/2026-06-06-slice5d-terraform-profile.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
Expected: branch pushed; PR URL printed; CI starts.

- [ ] **Step 5: Report CI status, stop for ratification**

```bash
cd /Users/bradleyjames/Development/agentic-sdlc-kit
sleep 15
gh pr checks 2>&1 | head
```
Do **not** merge. Report PR URL + CI results.

---

## Self-Review (completed by plan author)

**Spec coverage:** §3 deliverables mapped — terraform.md→T1, ci.yml+companions→T2, VERSION/CHANGELOG/ROADMAP→T3, validation/PR→T4. Spec §4.2 (8 gates via IaC analogs + gate-policy: plan=build, validate=type-check, Trivy config=dep-scan, Trivy CycloneDX=sbom) → T2 ci.yml. Spec §5 conditional-§13 + state security → terraform.md §5/§8/§11 (T1). Spec §5 validation (ci-gates, completeness over 10, incept wiring, additive) → T4.

**Placeholder scan:** no TBD/TODO in the plan. The `terraform plan` build step carries an inline note that it needs provider creds (adopter wires them; the reference is copy-and-adapt; doesn't affect any `gate-*` id, so ci-gates passes). SBOM `output: sbom.json` (trivy-action) ↔ upload `sbom.json` (Slice-5b lesson). No `[...]` in the profile (completeness check verifies). tfsec deprecation handled (folded into Trivy) so no dead standalone tool.

**Type/name consistency:** the `ci.yml` declares all 8 standard `gate-*` ids `ci-gates.sh` requires, plus `gate-policy`; `gate-dep-scan` and `gate-sbom` are on `uses: aquasecurity/trivy-action` steps (ci-gates greps `id: gate-*` regardless of run-vs-uses). Profile name `terraform` matches the companion dir + `--stack terraform` (T4). Companion derivation uses the Python reference's actual header strings.
