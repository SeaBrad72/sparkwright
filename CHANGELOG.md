# Changelog

All notable changes to the Agentic SDLC Kit are recorded here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.14.0] - 2026-06-06

Slice 7b — Multi-persona role touchpoints. Second sub-slice of Slice 7. Makes the kit legible to non-developer roles without becoming a PM/design tool.

### Added
- **Persona mapping** in `DEVELOPMENT-PROCESS.md` §2 — PO/BA · Designer · Engineer · QA · DevOps/SRE · Security · Lead/Agent mapped to the existing "functions, not titles" model (personas are lenses on functions; nothing in §2 is replaced).
- **Designer lane** — a UX & accessibility prompt in §5 Discovery and a "Design assets / UX handoff" row in the §15 artifact flow.
- `templates/FEATURE-REQUEST-TEMPLATE.md` (non-coder intake front door, mirrors the §5 Discovery prompts) and `templates/SPEC-TEMPLATE.md` (tool-neutral PRD behind the Plan gate).
- **Persona-routed onboarding** — a "Who are you? Start here" router atop `START-HERE.md` that routes each role to its minimal path and surfaces `scripts/incept.sh` as the engineer fast-path.

### Changed
- `templates/PROJECT-CLAUDE-TEMPLATE.md` §4 Roles guidance now points at the persona map.

### Note
No new required CI gate (MINOR). Docs/templates only — no enforced separation or code added; personas augment, not replace, the §2 functions.

## [2.13.0] - 2026-06-06

Slice 7a — Environments & production safety. First sub-slice of Slice 7 (adoption/safety hardening).

### Added
- **Dev → QA → UAT → Prod** environment model with gated promotion (production always human-gated) in `DEVELOPMENT-PROCESS.md` + `DEVELOPMENT-STANDARDS.md` §14 + `PROJECT-CLAUDE-TEMPLATE.md` + `RUNBOOK-TEMPLATE.md`.
- `conformance/branch-protection.sh` — verifies `main` is actually protected (PR reviews + status checks) via `gh api`; informational clean-exit where the API isn't reachable. `incept.sh` now reminds to apply branch protection.
- Env-protected reference prod-deploy workflow; explicit **human-coverage boundary** (the guard governs the Claude Code runtime only; humans/other runtimes are Org-owned platform controls).

### Changed
- **`.claude/hooks/guard.sh` is now environment-aware (additive — no existing deny weakened):** expanded destructive coverage (database drops via ORM/framework tools across Rails/Laravel/Django/Alembic/Flyway/.NET-EF, raw DB-client `DROP DATABASE`, restore-with-clean, cache flush, cluster-resource and container-volume removal, cloud storage/DB/instance deletion) plus a **production-context catch-all** (prod kube/helm context or namespace, `*_ENV=prod` prefix, `--env production` co-occurring with a destructive/deploy verb). All 35 prior conformance cases pass; 61 cases total.

### Note
No new required CI gate (MINOR). Production destructive-action prevention for humans and non-Claude-Code runtimes is Org-owned (platform IAM / account separation / deploy approvals).

## [2.12.0] - 2026-06-06

Slice 6d — Enterprise addendum, pillar 4 (capstone): the audit-evidence checklist. **Completes the enterprise addendum and the kit roadmap.** Tagged `v3.0.0` as the "enterprise layer complete" milestone (a marker, not a semver-major — no new required gate; the kit's contract version is 2.12.0, per `MAINTAINING.md`).

### Added
- `conformance/audit-evidence-checklist.md` — checklist-type conformance check mapping every control in the compliance crosswalk to **where its evidence lives** in a kit-built repo (CI gate logs, SBOM + provenance, PR approvals, the executable `conformance/*.sh`, the §6b managed-secret config, the §6c governed-exception records). Auto rows name the runnable check; Manual rows are attestation; waived controls cite a governed exception.
- Wired into `docs/enterprise/README.md`, the 6b/6c back-references, and the `conformance/README.md` index.

### Note
Documentation/checklist only — no new gate, no code. Completeness tie-off: every crosswalk control has an evidence row. With this, the enterprise addendum (6a crosswalk · 6b secrets-at-scale · 6c ratification RBAC · 6d audit evidence) is complete.

## [2.11.0] - 2026-06-06

Slice 6c — Enterprise addendum, pillar 3: ratification RBAC. Third of four sub-slices.

### Added
- `DEVELOPMENT-PROCESS.md` §13 **"Ratification roles & exceptions"** — defines which named role (Project Owner / Code Owner / Security Owner / Release Manager) may ratify what, the builder ≠ sole-ratifier rule per change, and the **governed-exception process**: required gates/posture are universally required; a Security-Owner-ratified, time-boxed record is the only way to waive (settles the Slice 5e deferred question). §12 cross-references it.
- `docs/enterprise/ratification-rbac.md` — full role model, separation-of-duties, GitHub mapping (CODEOWNERS + branch protection + the profile companions), and the exception-record template.

### Note
No new gate, no code. The agent-autonomy human-gate set is unchanged — agents propose; a human in the appropriate role ratifies. Maps onto existing CODEOWNERS / BRANCH-PROTECTION companions; 6d's audit-evidence checklist attests it.

## [2.10.0] - 2026-06-06

Slice 6b — Enterprise addendum, pillar 2: secrets at scale. Second of four sub-slices.

### Added
- `DEVELOPMENT-STANDARDS.md` §2 **"Secrets at scale"** subsection — the contract: managed store (Vault/KMS) beyond `.env`, least-privilege, rotation (prefer dynamic/short-lived), no plaintext in state/logs/images, CI fetches at run time via OIDC, audited break-glass.
- `docs/enterprise/secrets-at-scale.md` — patterns (static vs dynamic, CI injection reusing the §14 OIDC/provenance pattern, rotation, envelope encryption, break-glass) + a **secret-manager-client-by-stack** table covering all 10 stacks in one place.
- `profiles/_TEMPLATE.md` Security section now points to the secrets-at-scale doc, so future/BYO profiles route correctly.

### Note
Stack-neutral contract + stack-aware reference — **no edit to the 10 existing profiles**. No new gate, no code. The CI-injection pattern ties to the Slice 5e push-only OIDC job.

## [2.9.0] - 2026-06-06

Slice 6a — Enterprise addendum, pillar 1: the compliance crosswalk. First of four sub-slices (umbrella spec: `docs/superpowers/specs/2026-06-06-slice6-enterprise-umbrella-design.md`).

### Added
- `docs/enterprise/README.md` — addendum index + an explicit **responsibility boundary** (Kit-enforced / Kit-assisted / Org-owned), naming what the kit does not cover (HR, physical, vendor risk, BCP, the privacy program).
- `docs/enterprise/compliance-crosswalk.md` — maps the controls the kit enforces/assists to **SOC 2 (Security CC + Privacy P) + ISO 27001:2022 Annex A**, with a dedicated **privacy/data-protection family** (data-subject rights, consent & age-gating, retention, third-party sharing; COPPA/GDPR-minors/CCPA named as triggers). Column-structured so NIST CSF / PCI-DSS / ISO 27701 are a cheap re-index later.

### Note
Pure documentation — no new gate, no code, no profile changes. The crosswalk *maps* controls; it does not mandate new ones. Privacy rows are N/A-with-reason for no-PII projects. Definition of Done unchanged.

## [2.8.0] - 2026-06-06

Slice 5e — CI security hardening across all 10 profile reference pipelines. Triggered by a push security review whose findings proved kit-wide. No new gate, no contract-breaking change.

### Changed
- **All 10 `profiles/*/ci.yml`** restructured to least-privilege OIDC: a `ci` job (all gates, PR + push, `permissions: contents: read`) plus a push-main-only `provenance` job (`needs: ci`) that holds `id-token`/`attestations: write` and attests the build artifact handed off via `upload-artifact`/`download-artifact` (`subject-path: build-artifact/**`). PR-triggered steps can no longer mint an OIDC token. PRs still run every gate.
- Strengthened the `# HARDENING:` block in every reference pipeline (SHA-pin actions · pin tool installs · cloud OIDC trust policy MUST restrict `sub` to `refs/heads/main`).
- `profiles/terraform/ci.yml`: pinned `checkov` to `3.2.533` (verified on PyPI); noted the conftest download should be checksum-verified.

### Added
- `DEVELOPMENT-STANDARDS.md` §14: a **CI security hardening** posture note (least-privilege OIDC via a push-only attestation job · SHA-pinning · trust-policy `sub` restriction). Guidance, not a new required gate — Definition of Done unchanged.

### Note
No gate id was removed from any profile; `conformance/ci-gates.sh` (job-agnostic id presence) and `profile-completeness.sh` pass unchanged across all 10. SHA-pinning the references is modeled as a documented adopter step rather than baked-in opaque hashes.

## [2.7.0] - 2026-06-06

Slice 5d — Terraform/IaC stack profile. Completes the profile family (10 stacks). Proves §14's 8 gates hold even for config-only IaC — via analogs, no contract change.

### Added
- `profiles/terraform.md` + `profiles/terraform/` (`ci.yml`, `CODEOWNERS`, `BRANCH-PROTECTION.md`) — Terraform ≥1.6 · tflint · `terraform validate`/`test` · Checkov + conftest/OPA · Trivy · gitleaks.
- A dedicated **`gate-policy`** step (Checkov + conftest/OPA) — the IaC headline gate (parallel to ML's `gate-eval` and data-engineering's `gate-data-quality`).

### Note
IaC has no software artifact, so §14's gates map to **analogs**, keeping the 8 intact (no `ci-gates.sh`/§14 change): `gate-build` = `terraform plan` (the plan is the artifact); `gate-dep-scan` = Trivy config scan (vulnerable/misconfigured providers & modules — tfsec is merged into Trivy); `gate-sbom` = Trivy CycloneDX (provider/module inventory). The profile applies the **conditional 15-factor** mechanism (an IaC repo isn't a running service → port-binding/concurrency/stateless/disposability N/A-with-reason). `incept.sh --stack terraform` wires the profile's CI.

## [2.6.0] - 2026-06-06

Slice 5c2 — Data-engineering stack profile. Completes the profile family (9 stacks). The data-eng analog of the ML eval gate: a data-quality gate.

### Added
- `profiles/data-engineering.md` + `profiles/data-engineering/` (`ci.yml`, `CODEOWNERS`, `BRANCH-PROTECTION.md`) — dbt-core (warehouse transforms) · Dagster (orchestration, asset checks) · Python ingestion · sqlfluff + ruff (lint) · dbt parse + mypy (validate) · dbt tests/contracts + Great Expectations + pandera + data-diff (data quality) · gitleaks · pip-audit · CycloneDX-py + provenance.
- A dedicated **`gate-data-quality`** step in the data-engineering `ci.yml` (`dbt build` + Great Expectations checkpoint, run against a CI Postgres service) that fails the build on a data-quality violation — the data-eng analog of ML's `gate-eval`. `conformance/ci-gates.sh` validates the 8 standard gates; `gate-data-quality` is an allowed extra.

### Note
`gate-type-check` = `dbt parse` + `mypy` (SQL has no compiler; parsing the model DAG is the validate analog). The profile applies the **conditional 15-factor** mechanism: an orchestrated batch pipeline marks port-binding/concurrency/stateless/disposability N/A-with-reason; the warehouse backing-service + lineage telemetry apply. `incept.sh --stack data-engineering` wires the profile's CI.

## [2.5.0] - 2026-06-06

Slice 5c — ML stack profile. The kit's first profile with a real **eval gate** — wiring the §7 "evals = the dev-time bar / AI analog of TDD" doctrine into CI.

### Added
- `profiles/ml.md` + `profiles/ml/` (`ci.yml`, `CODEOWNERS`, `BRANCH-PROTECTION.md`) — Python ML lifecycle: uv · ruff (+nbqa) · mypy · pytest (+ pandera data-validation, nbmake notebook smoke) · MLflow (tracking/registry) · DVC (data/model versioning) · notebook hygiene (nbstripout/jupytext) · gitleaks · pip-audit · CycloneDX-py + provenance.
- A dedicated **`gate-eval`** step in the ML `ci.yml` (`python -m evals.run --threshold 0.8`) that fails the build below the eval threshold — metric thresholds and/or LLM-as-judge (pinned judge), plus a safety/red-team set. `conformance/ci-gates.sh` validates the 8 standard gates; `gate-eval` is an allowed ML extra.

### Note
The ML profile applies the **conditional 15-factor** mechanism: a training pipeline is batch, so port-binding/concurrency/stateless/disposability are N/A-with-reason; the serving path satisfies them. `incept.sh --stack ml` wires the profile's CI. The data-engineering profile follows as a separate slice.

## [2.4.0] - 2026-06-06

Slice 5b — More first-class profiles + bring-your-own on-ramp. Seven shipped stacks now: TypeScript, Python, Java/Spring, C#/.NET, Go, Rust, Kotlin.

### Added
- `profiles/dotnet.md` + `profiles/dotnet/` — .NET 8 · dotnet format/analyzers · dotnet build (type-check) · xUnit+coverlet · dotnet list package --vulnerable · CycloneDX .NET · EF Core · ASP.NET Core.
- `profiles/go.md` + `profiles/go/` — Go 1.22+ · golangci-lint · go vet · go test -race -cover · govulncheck · cyclonedx-gomod · golang-migrate.
- `profiles/rust.md` + `profiles/rust/` — Rust stable · clippy · cargo check · cargo-llvm-cov · cargo-audit · cargo-cyclonedx · axum + sqlx.
- `profiles/kotlin.md` + `profiles/kotlin/` — Kotlin/JVM 21 · Gradle (Kotlin DSL) · ktlint+detekt · JUnit5/Kotest+JaCoCo · OWASP dependency-check · cyclonedx-gradle · Spring Boot + Flyway.
- `scripts/new-profile.sh` — scaffolds a new stack profile + a stub `ci.yml` that passes `ci-gates.sh` structurally, so bringing an unsupported stack is a guided, validated workflow.
- `README.md` "Generate your own profile" section; `START-HERE.md` §2B points at the scaffolder.

### Note
Each new `ci.yml` reuses the existing 8-gate `ci-gates.sh`; `profile-completeness.sh` now guards all 7 profiles. Kit CI verifies declaration + completeness; it does not execute the toolchains (adopter-side).

## [2.3.0] - 2026-06-06

Slice 5 — Enterprise profiles. Python and Java/Spring join TypeScript as ready, conformant stack profiles.

### Added
- `profiles/python.md` + `profiles/python/` (`ci.yml`, `CODEOWNERS`, `BRANCH-PROTECTION.md`) — uv · ruff · mypy · pytest+cov · gitleaks · pip-audit · CycloneDX-py + provenance; FastAPI + SQLAlchemy/Alembic reference.
- `profiles/java-spring.md` + `profiles/java-spring/` (`ci.yml`, `CODEOWNERS`, `BRANCH-PROTECTION.md`) — Maven · Spring Boot · Spotless/Checkstyle · JUnit5+JaCoCo · OWASP dependency-check · CycloneDX-maven + provenance; Flyway migrations. (`mvn compile` = type-check; `mvn package` = build.)
- `conformance/profile-completeness.sh` — every profile fills all 11 `_TEMPLATE.md` sections (no leftover `[...]`) and its companion `ci.yml` passes `ci-gates.sh`. Runs in kit CI; also regression-guards `typescript-node.md`.

### Changed
- `.github/workflows/ci.yml` — the conformance job now runs `profile-completeness.sh`.
- `docs/ROADMAP-KIT.md` — Slice 5 marked done.

### Note
`incept.sh --stack python` / `--stack java-spring` now wires the respective profile's CI. Kit CI verifies the profiles' workflows *declare* the §14 gates and the profiles are complete; it does not execute the Python/JVM pipelines (that happens in an adopting project).

## [2.2.0] - 2026-06-06

Slice 3 — Inception bootstrap. One command turns a cloned kit into a configured project. Absorbs the template work (RUNBOOK + flow-board BACKLOG); roadmap collapses 6→5.

### Added
- `scripts/incept.sh` — in-place Inception bootstrap (interactive + `--noninteractive`). At adoption it renames the principles doc `CLAUDE.md` → `ENGINEERING-PRINCIPLES.md` (freeing the project memory slot), rewrites the principles-sense references, stamps the project `CLAUDE.md`/`RUNBOOK.md`/`BACKLOG.md`/`ADR-000`, and wires the profile's CI. Prints the judgment steps it does not automate.
- `templates/RUNBOOK-TEMPLATE.md` — cold-resume runbook (setup/deploy/rollback/RPO-RTO).
- `conformance/inception-done.sh` — verifies the Inception-Done gate; kit CI bootstraps a temp project and asserts it passes.

### Changed
- `templates/BACKLOG-TEMPLATE.md` — rewritten from the stale phase/PROGRESS model to the §6 flow-board (states, work-item fields, ordering, work types, tech-debt paydown).
- `.github/workflows/ci.yml` — new `bootstrap` job (incept-into-temp → inception-done).
- `docs/ROADMAP-KIT.md` — Slice 3 done; roadmap 6→5 (template work absorbed).

### Note
The canonical kit stays **un-incepted** (principles remain in `CLAUDE.md`, which also serves as the kit's own memory). The `CLAUDE.md → ENGINEERING-PRINCIPLES.md` rename is an **adoption-time transform performed by `incept.sh`**, not a change to the kit's own layout.

## [2.1.0] - 2026-06-06

Slice 2 — Agent governance layer. The §13 autonomy matrix is now mechanically enforced for Claude Code (additive reference + conformance → MINOR per `MAINTAINING.md` §2).

### Added
- `.claude/` governance layer (kit-own + adopter reference): `settings.json` (allow/ask/deny permission globs), `hooks/guard.sh` (PreToolUse hook denying irreversible/high-blast actions, field-scoped via jq, hardened against allowlist-escape bypasses), `agents/reviewer.md` + `agents/security-reviewer.md` (the §12 separations), and `README.md`.
- `conformance/agent-autonomy.sh` — proves the guard denies a tier breach and allows safe actions, with false-positive and bypass-resistance regressions; runs in kit CI.
- `DEVELOPMENT-PROCESS.md` §13 — an "Enforcement reference" note (tool-neutral matrix → Claude Code `.claude/` reference).

### Changed
- `.github/workflows/ci.yml` — the conformance job now also runs `agent-autonomy.sh`.
- `.gitignore` — excludes `.claude/settings.local.json` (personal); `settings.json` is committed/shared.
- `docs/ROADMAP-KIT.md` — Slice 2 marked done.

## [2.0.0] - 2026-06-05

Slice 1 — CI/CD. Raises the supply-chain posture to the baseline for all projects (new required gates → MAJOR per `MAINTAINING.md` §2).

### Added
- `DEVELOPMENT-STANDARDS.md` §14 **CI/CD Pipeline** — 7 required per-PR gates (lint, type-check, test+coverage≥80%, build, secret-scan, dependency scan, SBOM+provenance) + branch protection (main protected, green-CI-to-merge, builder≠sole-merger).
- TypeScript reference pipeline in `profiles/typescript-node/`: `ci.yml`, `CODEOWNERS`, `BRANCH-PROTECTION.md`.
- `conformance/ci-gates.sh` — asserts a workflow declares every required gate; `conformance/check-links.sh` — relative-link integrity check.
- `.github/workflows/ci.yml` — the kit's own CI (conformance + docs links): the kit now dogfoods its gate.

### Changed
- `DEVELOPMENT-PROCESS.md` §10 — supply-chain integrity moves from optional configuration hook to **required CI gates**; §15 — recurring audit reframed as the deeper periodic complement to the per-PR gate.
- `profiles/typescript-node.md` §4 — points to the concrete reference files.
- `docs/ROADMAP-KIT.md` — Slice 1 marked done.

## [1.0.0] - 2026-06-05

First product release — the kit becomes a versioned, drop-in template framework.

### Added
- `LICENSE` (Apache-2.0) — the kit is now licensed for distribution.
- `VERSION` + this `CHANGELOG.md` — the kit is a semver'd product.
- `MAINTAINING.md` — the contract/reference/conformance convention, and how the kit is versioned, released, and contributed back to (the kit dogfoods its own loop).
- `conformance/` — the conformance-check pattern and `15-factor-checklist.md` (the first check, filled for the TypeScript/Node reference profile).
- `DEVELOPMENT-STANDARDS.md` §13 — **15-Factor Architecture**: a binding, conditional-by-project-type contract mapping all 15 factors to where the kit enforces them. Adds previously-uncovered factors: dependencies, disposability, backing services, dev/prod parity, statelessness, concurrency, and telemetry depth.
- `docs/ROADMAP-KIT.md` — the kit's own backlog: the six remaining contract/reference/conformance slices, sequenced.
- "Kit version adopted" field in `templates/PROJECT-CLAUDE-TEMPLATE.md` — projects record the kit version they run.

### Changed
- `DEVELOPMENT-PROCESS.md` §7 — the Review gate adds a conditional **15-Factor conformance** check; §8 — the L3 process retro now routes kit-level improvements upstream as a PR to the canonical kit.
- `README.md` — version surfaced; "How the kit is built" (the contract/reference/conformance convention) added; license declared.

[2.7.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.7.0
[2.6.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.6.0
[2.5.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.5.0
[2.4.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.4.0
[2.3.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.3.0
[2.2.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.2.0
[2.1.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.1.0
[2.0.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.0.0
[1.0.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v1.0.0
