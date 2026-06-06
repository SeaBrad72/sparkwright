# Design — Slice 5b: More First-Class Profiles (.NET, Go, Rust, Kotlin) + BYO On-Ramp

**Date:** 2026-06-06
**Status:** Approved (brainstorming) — pending spec review
**Author:** Bradley James + agent
**Roadmap:** Adds to Slice 5 (profiles). Followed by Slice 5c (Data-ML), Slice 5d (Terraform/IaC), then Slice 6.

---

## 1. Goal

Broaden first-class stack coverage to the highest-demand modern + enterprise stacks — **C#/.NET, Go, Rust, Kotlin** — each a conformant profile mirroring the proven `python`/`java-spring` pattern. And make the **bring-your-own-stack** capability a guaranteed, guided, validated workflow (`scripts/new-profile.sh` + a prominent README/START-HERE "generate your own profile" treatment), so an unsupported stack is never a dead end.

## 2. Decisions (from brainstorming)

- **Four mechanical profiles** (mirror Slice 5): .NET 8 · Go 1.22+ · Rust (stable) · Kotlin (JVM, Gradle Kotlin DSL + Spring Boot).
- **Vetted toolchain defaults** (the "recommended libraries" each profile settles) — §4.
- **BYO on-ramp:** `scripts/new-profile.sh <stack>` scaffolder + README §"Generate your own profile" + a louder `START-HERE.md` §2B pointer.
- **No new conformance logic:** the 8-gate `ci-gates.sh` and `profile-completeness.sh` (Slice 5) validate the four new profiles unchanged.
- **Version:** **2.4.0** (MINOR — additive profiles + tooling).

## 3. Deliverables

| Part | Files |
|------|-------|
| .NET | `profiles/dotnet.md`; `profiles/dotnet/{ci.yml,CODEOWNERS,BRANCH-PROTECTION.md}` |
| Go | `profiles/go.md`; `profiles/go/{ci.yml,CODEOWNERS,BRANCH-PROTECTION.md}` |
| Rust | `profiles/rust.md`; `profiles/rust/{ci.yml,CODEOWNERS,BRANCH-PROTECTION.md}` |
| Kotlin | `profiles/kotlin.md`; `profiles/kotlin/{ci.yml,CODEOWNERS,BRANCH-PROTECTION.md}` |
| BYO on-ramp | `scripts/new-profile.sh`; `README.md` §Generate-your-own; `START-HERE.md` §2B enhancement |
| Meta | `VERSION` → `2.4.0`; `CHANGELOG.md` 2.4.0; `docs/ROADMAP-KIT.md` note |

Profile filenames = `--stack` values = companion dir names: `dotnet`, `go`, `rust`, `kotlin` (so `incept.sh --stack <x>` wires CI).

## 4. Toolchain mapping (each `ci.yml` uses the 8 standardized `gate-*` ids)

**`gate-install` is setup (not asserted); the 8 required are lint, type-check, test, build, secret-scan, dep-scan, sbom, provenance.** secret-scan = gitleaks and provenance = `actions/attest-build-provenance` (release/build path) for all four.

### 4.1 C#/.NET (`profiles/dotnet/ci.yml`) — .NET 8 LTS
- `gate-lint`=`dotnet format --verify-no-changes` (+ Roslyn analyzers as build warnings-as-errors); `gate-type-check`=`dotnet build --no-restore` (compilation = type-check); `gate-test`=`dotnet test --collect:"XPlat Code Coverage"` (coverlet; threshold via runsettings/`--`); `gate-build`=`dotnet publish -c Release`; `gate-dep-scan`=`dotnet list package --vulnerable --include-transitive` (fail on findings); `gate-sbom`=`dotnet CycloneDX` (`CycloneDX` global tool); `gate-provenance`=attest on the publish output. Setup: `actions/setup-dotnet@v4` (8.0.x).
- Profile §5 security: ASP.NET Core; secrets via `IConfiguration`/env + fail-fast; **FluentValidation**/DataAnnotations; **EF Core** (parameterized); ASP.NET Core Identity / JWT bearer + BCrypt; security headers middleware. §7: **Polly** (retry/circuit-breaker), Serilog (JSON), OpenTelemetry. §8: EF Core migrations (expand-contract).

### 4.2 Go (`profiles/go/ci.yml`) — Go 1.22+
- `gate-lint`=`golangci-lint run`; `gate-type-check`=`go vet ./...`; `gate-test`=`go test -race -coverprofile=cover.out ./...` (+ a coverage-threshold check step or `go-test-coverage`); `gate-build`=`go build ./...`; `gate-dep-scan`=`govulncheck ./...`; `gate-sbom`=`cyclonedx-gomod app -json -output sbom.json`; `gate-provenance`=attest on the built binary. Setup: `actions/setup-go@v5`.
- §5: net/http or chi; secrets via env + fail-fast; `go-playground/validator`; `pgx`/`sqlc` (parameterized); `golang.org/x/crypto/bcrypt` + JWT; secure headers middleware. §7: `cenkalti/backoff` + `sony/gobreaker`; `log/slog` (JSON); OpenTelemetry. §8: `golang-migrate`.

### 4.3 Rust (`profiles/rust/ci.yml`) — stable toolchain
- `gate-lint`=`cargo clippy --all-targets -- -D warnings` (+ `cargo fmt --check`); `gate-type-check`=`cargo check --all-targets`; `gate-test`=`cargo test` (+ `cargo llvm-cov --fail-under-lines 80`); `gate-build`=`cargo build --release`; `gate-dep-scan`=`cargo audit`; `gate-sbom`=`cargo cyclonedx -f json`; `gate-provenance`=attest on the release binary. Setup: `dtolnay/rust-toolchain@stable` + `Swatinem/rust-cache`.
- §5: **axum**; secrets via env + fail-fast; `validator` crate; **sqlx** (compile-checked, parameterized) + migrations; `argon2`/`bcrypt` + `jsonwebtoken`; `tower-http` security headers. §7: `tokio-retry` + circuit-breaker (tower); `tracing` (JSON). §8: sqlx migrations.

### 4.4 Kotlin (`profiles/kotlin/ci.yml`) — JVM 21, Gradle (Kotlin DSL) + Spring Boot
- `gate-lint`=`./gradlew ktlintCheck detekt`; `gate-type-check`=`./gradlew compileKotlin`; `gate-test`=`./gradlew test` (JUnit5/Kotest + JaCoCo verification ≥80 bound to `check`); `gate-build`=`./gradlew build -x test`; `gate-dep-scan`=`./gradlew dependencyCheckAnalyze` (OWASP gradle plugin); `gate-sbom`=`./gradlew cyclonedxBom` (cyclonedx-gradle plugin); `gate-provenance`=attest on `build/libs/*.jar`. Setup: `actions/setup-java@v4` (temurin 21) + Gradle cache.
- §5: **Spring Boot** (web, security, data-jpa, validation, actuator); Jakarta Bean Validation; Spring Data JPA; Spring Security (BCrypt + JWT). §7: **Resilience4j**; SLF4J+Logback (JSON); Micrometer+Actuator. §8: **Flyway**. §11 notes: Gradle Kotlin DSL `./gradlew`; ktlint vs detekt roles; JaCoCo `verification` binds to `check`.

Each profile `.md` fills all 11 `_TEMPLATE.md` sections; `CODEOWNERS`/`BRANCH-PROTECTION.md` mirror the existing reference companions (generic, copy-and-adapt).

## 5. BYO on-ramp

### 5.1 `scripts/new-profile.sh <stack>`
POSIX `sh`. `sh scripts/new-profile.sh <stack-name>`:
- Refuse if `profiles/<stack>.md` or `profiles/<stack>/` already exists.
- Create `profiles/<stack>.md` by copying `profiles/_TEMPLATE.md` (the 11-section template with `[...]` to fill) and replacing the title `[Stack Name]` with the given name.
- Create `profiles/<stack>/ci.yml` — a **stub workflow pre-seeded with all 8 `gate-*` step ids** and placeholder `run:` commands (so it passes the *structural* `ci-gates.sh` check immediately; the team fills the real commands).
- Copy `profiles/_TEMPLATE`-style `CODEOWNERS` + `BRANCH-PROTECTION.md` stubs into `profiles/<stack>/` (reuse the generic reference text).
- Print next steps: fill the 11 sections + real `run:` commands, then `sh conformance/profile-completeness.sh` to validate.
- Note: a freshly-generated profile **intentionally fails** `profile-completeness` until filled (it still contains `[...]`) — that's the finish line, not a regression. The tool is run by adopters in their repo, not committed to the kit.

### 5.2 Docs
- **`README.md`** — a "Generate your own profile" section: any stack is first-class; 3 steps (`new-profile.sh <stack>` → fill 11 sections + ci.yml commands → `profile-completeness.sh` validates). Lists the shipped profiles (TS, Python, Java/Spring, .NET, Go, Rust, Kotlin).
- **`START-HERE.md` §2B** — add a one-line pointer to `scripts/new-profile.sh` as the turnkey way to start a custom profile.

## 6. Validation / testing

- `ci-gates.sh` passes for all four new `profiles/<stack>/ci.yml` (8 gate ids each).
- `profile-completeness.sh` passes for ALL profiles (the 3 existing + 4 new) — 11 sections, no `[...]`, conformant ci.yml.
- Each new `ci.yml` is valid YAML.
- **incept wiring:** `incept.sh --stack dotnet|go|rust|kotlin` into a temp copy wires `.github/workflows/ci.yml` and `inception-done.sh` passes for each.
- **new-profile.sh:** running `sh scripts/new-profile.sh demo-stack` in a temp copy creates the files; the stub `ci.yml` passes `ci-gates.sh`; a second run refuses; `profile-completeness.sh` reports the generated profile as incomplete (still has `[...]`) — proving the validator catches an unfilled profile. (Clean up the temp `demo-stack` — it is NOT committed to the kit.)
- `sh -n scripts/new-profile.sh`; dash-clean.
- Kit CI green (conformance incl. profile-completeness over 7 profiles, bootstrap, docs-links); check-links covers the new docs.

## 7. Risks & mitigations

- **`new-profile.sh` output failing kit CI:** it must never leave a half-filled profile in the kit. Mitigation: it's an adopter tool; the kit never commits a generated stub. The validation test (§6) generates into a temp dir and cleans up. profile-completeness over the kit only sees the 7 shipped (complete) profiles.
- **Toolchain command accuracy** (e.g. `dotnet CycloneDX`, `cargo llvm-cov`, gradle plugin tasks): reference workflows are copy-and-adapt; kit CI checks gate-id *declaration*, not execution. Commands chosen are the standard documented invocations; profiles note any required project config (analyzers, JaCoCo rule, plugins in build files).
- **SBOM upload path correctness** (the Slice-5 Java lesson): each profile's Upload SBOM step points at the tool's actual default output path (`sbom.json` where we set `--output`, the tool default otherwise). Verified per profile.
- **Kotlin ≈ Java overlap:** the Kotlin profile is a Gradle/ktlint sibling; it does not duplicate java-spring needlessly — it documents the Kotlin-specific deltas (Gradle Kotlin DSL, ktlint/detekt, compileKotlin).

## 8. Out of scope

Data-ML (Slice 5c) · Terraform/IaC (Slice 5d) · Swift/Elixir/Ruby/PHP (generate-your-own) · executing the new pipelines in kit CI (adopter-side).

## 9. Definition of Done

- Four profiles (`dotnet`, `go`, `rust`, `kotlin`) each: `.md` (11 sections, no `[...]`) + companion `ci.yml` (passes ci-gates) + `CODEOWNERS` + `BRANCH-PROTECTION.md`.
- `profile-completeness.sh` green over all 7 profiles.
- `incept.sh --stack {dotnet,go,rust,kotlin}` wires CI + passes `inception-done.sh` (verified in temp).
- `scripts/new-profile.sh` scaffolds a conformant-structure skeleton; tested (creates, stub passes ci-gates, re-run refuses, completeness flags unfilled).
- README "Generate your own profile" + START-HERE §2B pointer added.
- `VERSION` = `2.4.0`; CHANGELOG 2.4.0; roadmap note.
- Kit CI green; feature branch → PR; **human-ratified before merge**.
