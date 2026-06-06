# Changelog

All notable changes to the Agentic SDLC Kit are recorded here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
