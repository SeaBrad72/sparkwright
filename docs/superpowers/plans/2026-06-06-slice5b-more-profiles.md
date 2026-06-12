# Slice 5b: More First-Class Profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship conformant **C#/.NET, Go, Rust, Kotlin** stack profiles (mirroring the proven `python`/`java-spring` pattern) and make bring-your-own-stack a guided, validated workflow (`scripts/new-profile.sh` + a README/START-HERE "Generate your own profile" treatment).

**Architecture:** Profiles slice on branch `feature/slice-5b-more-profiles`. Each profile = `profiles/<stack>.md` (11 `_TEMPLATE` sections) + `profiles/<stack>/{ci.yml,CODEOWNERS,BRANCH-PROTECTION.md}`. Each `ci.yml` uses the 8 standardized `gate-*` step ids so the existing `conformance/ci-gates.sh` validates it; `conformance/profile-completeness.sh` (Slice 5) guards all profiles — no new conformance logic. `scripts/new-profile.sh` scaffolds a skeleton whose stub `ci.yml` passes ci-gates structurally. Kit CI checks declaration + completeness only (it does not execute the toolchains).

**Tech Stack:** Markdown, GitHub Actions YAML, POSIX `sh`. Profiles: .NET 8 · Go 1.22+ · Rust stable · Kotlin/JVM 21 (Gradle Kotlin DSL + Spring Boot). Spec: `docs/superpowers/specs/2026-06-06-slice5b-more-profiles-design.md`.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `profiles/dotnet.md` + `profiles/dotnet/{ci.yml,CODEOWNERS,BRANCH-PROTECTION.md}` | .NET profile |
| `profiles/go.md` + `profiles/go/{…}` | Go profile |
| `profiles/rust.md` + `profiles/rust/{…}` | Rust profile |
| `profiles/kotlin.md` + `profiles/kotlin/{…}` | Kotlin profile |
| `scripts/new-profile.sh` | BYO scaffolder |
| `README.md`, `START-HERE.md` (edit) | "Generate your own profile" on-ramp |
| `VERSION` `CHANGELOG.md` `docs/ROADMAP-KIT.md` (edit) | 2.4.0; changelog; roadmap note |

**Precondition:** on branch `feature/slice-5b-more-profiles`. The committed Python profile (`profiles/python/CODEOWNERS`, `profiles/python/BRANCH-PROTECTION.md`) is the source for the generic companions (derive via `cp`+`sed`).

**Shared companion recipe (used in Tasks 1–4):** the `CODEOWNERS` and `BRANCH-PROTECTION.md` are stack-neutral. For stack `<S>`:
```bash
sed 's/Python profile/<S> profile/' profiles/python/CODEOWNERS > profiles/<S>/CODEOWNERS
sed 's/(Python profile)/(<S> profile)/' profiles/python/BRANCH-PROTECTION.md > profiles/<S>/BRANCH-PROTECTION.md
```
(The Python `BRANCH-PROTECTION.md` H1 reads `# Branch Protection — reference setup (Python profile)`; the sed retitles it.)

---

### Task 1: profiles/dotnet (.md + companion ci.yml/CODEOWNERS/BRANCH-PROTECTION)

**Files:** Create `profiles/dotnet.md`, `profiles/dotnet/ci.yml`, `profiles/dotnet/CODEOWNERS`, `profiles/dotnet/BRANCH-PROTECTION.md`

- [ ] **Step 1: Write `profiles/dotnet.md`**

```markdown
# Stack Profile — C# / .NET

> Reference profile. The concrete *how* for the universal `DEVELOPMENT-STANDARDS.md` on a C#/.NET stack. Copy/adapt per project; record selection as ADR-000.

**Stack:** .NET 8 (LTS) · C# · ASP.NET Core · PostgreSQL + EF Core · xUnit · hosted (container / Azure / K8s)
**Status:** reference

---

## 1. Toolchain
- **Runtime:** .NET 8 LTS · **Build/deps:** `dotnet` CLI + NuGet (lockfile `packages.lock.json`, `RestoreLockedMode` in CI)
- **Format/lint:** `dotnet format` + Roslyn analyzers (`TreatWarningsAsErrors`) · **Types:** the compiler (`dotnet build` = type-check)
- **Tests:** xUnit + coverlet (coverage gate) · **Build:** `dotnet publish -c Release`

## 2. Project scaffold
\`\`\`
src/<Project>/{Controllers,Services,Domain,Data,Config}/
tests/<Project>.Tests/
docs/architecture/            # ADRs (incl. ADR-000)
.github/workflows/ci.yml
<Solution>.sln · Directory.Build.props · .editorconfig · .env.example · .gitignore
\`\`\`
Baselines: `.editorconfig` for analyzers; `Directory.Build.props` with `TreatWarningsAsErrors=true`, `EnableNETAnalyzers=true`; coverlet threshold 80.

## 3. Standard commands
\`\`\`
install:       dotnet restore --locked-mode
dev:           dotnet watch run
test:          dotnet test
test:coverage: dotnet test --collect:"XPlat Code Coverage"
lint:          dotnet format --verify-no-changes
type-check:    dotnet build --no-restore
build:         dotnet publish -c Release
start:         dotnet <Project>.dll
\`\`\`

## 4. CI/CD pipeline
Implements the 7 required gates of `DEVELOPMENT-STANDARDS.md` §14. Drop-in reference files live in **`profiles/dotnet/`**:
- **`ci.yml`** → copy to `.github/workflows/ci.yml`. `dotnet restore` → `dotnet format --verify-no-changes` → `dotnet build` (type-check) → `dotnet test`+coverage(≥80) → `dotnet publish -c Release` → secret-scan (gitleaks) → dependency scan (`dotnet list package --vulnerable`) → SBOM (`dotnet CycloneDX`) → build provenance.
- **`CODEOWNERS`**, **`BRANCH-PROTECTION.md`** → governance companions.

Conformance: `sh conformance/ci-gates.sh profiles/dotnet/ci.yml`. Note: compilation **is** type-checking — `gate-type-check`=`dotnet build`, `gate-build`=`dotnet publish`.

## 5. Security implementation
- **Env/secrets:** `IConfiguration` + environment / user-secrets in dev; fail-fast on missing; `.env`/secrets gitignored; commit `.env.example`.
- **Validation:** **FluentValidation** (or DataAnnotations `[Required]` + `ModelState`) at every boundary; validate create *and* update.
- **Injection-safe data:** **EF Core** (parameterized LINQ) / `FromSqlInterpolated`; never string-concat SQL.
- **AuthN/Z:** ASP.NET Core Identity (BCrypt/PBKDF2) or JWT bearer (minimal claims, short expiry); `[Authorize]` policies server-side.
- **HTTP headers / CSRF:** security-headers middleware (`NetEscapades.AspNetCore.SecurityHeaders`); antiforgery tokens for cookie auth.
- **Rate limiting:** built-in `RateLimiter` middleware (relax in test env).

## 6. Testing
- **Convention:** `tests/<Project>.Tests`; `*Tests.cs`. Arrange-Act-Assert.
- **Integration:** `WebApplicationFactory<T>` + Testcontainers (real Postgres); assert status + body + DB state.
- **E2E:** Playwright (.NET) against the running app.
- **AI evals:** an `evals/` project with JSONL datasets; a runner scoring against a rubric (LLM-as-judge via the Anthropic .NET SDK, pinned judge) failing below threshold in CI.

## 7. Resilience & observability
- **Retry/backoff + circuit breaker:** **Polly** (`Microsoft.Extensions.Http.Resilience`).
- **Logging:** **Serilog** (JSON sink). **Metrics/health/traces:** OpenTelemetry + ASP.NET Core health checks. **Error tracking:** Sentry.

## 8. Data & migrations
- **EF Core migrations.** Expand-contract: add → backfill (batched) → switch reads → drop old in a later migration. Reversible (`Down`); apply via `dotnet ef database update` / `migrationBundle` in CI/CD; no manual prod DDL.

## 9. Release & deploy
- **Build artifact:** framework-dependent publish + container image. **Deploy:** container to Azure Container Apps / AKS / Fly; merge to `main` → deploy.
- **Feature flags:** `Microsoft.FeatureManagement` or a flag service; flag-off = fastest rollback.
- **Rollout:** staging → prod; **rollback:** redeploy previous image / revert + redeploy.

## 10. Recommended libraries
ASP.NET Core · EF Core (+ Npgsql) · FluentValidation · ASP.NET Core Identity / JwtBearer · Polly (`Microsoft.Extensions.Http.Resilience`) · Serilog + OpenTelemetry + Sentry · xUnit + coverlet + Testcontainers + WebApplicationFactory · CycloneDX .NET tool · Anthropic .NET SDK for AI features. Default Claude models: `claude-sonnet-4-6` (workhorse), escalate to Opus for hard reasoning.

## 11. Stack-specific gotchas
- Commit `packages.lock.json`; use `dotnet restore --locked-mode` in CI for reproducible restores.
- `dotnet format --verify-no-changes` fails on drift (CI); `dotnet format` fixes locally.
- Set `TreatWarningsAsErrors=true` + `EnableNETAnalyzers=true` so analyzer findings gate.
- `dotnet list package --vulnerable --include-transitive` exits 0 even with findings — the CI step greps output and fails on any vulnerability.
- Install the SBOM tool: `dotnet tool install --global CycloneDX`.
\`\`\`

---

**Last Updated:** 2026-06-06
```

(Where you see `\`\`\`` write literal triple-backtick fences for the scaffold + commands blocks.)

- [ ] **Step 2: Write `profiles/dotnet/ci.yml`**

```yaml
# Reference CI pipeline for the C#/.NET profile.
# COPY & ADAPT: copy to your project's .github/workflows/ci.yml. Inert here in the kit.
# Each quality gate carries a standardized `id: gate-*` that conformance/ci-gates.sh asserts.
# Satisfies DEVELOPMENT-STANDARDS.md §14. (compile = type-check: gate-type-check=build, gate-build=publish)
# HARDENING: pin `uses:` to SHAs and tool versions for production.
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

      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0.x'

      - name: Install dependencies
        id: gate-install
        run: dotnet restore --locked-mode

      - name: Lint
        id: gate-lint
        run: dotnet format --verify-no-changes

      - name: Type-check
        id: gate-type-check
        run: dotnet build --no-restore -c Release

      - name: Test + coverage (>=80%)
        id: gate-test
        run: dotnet test --no-build -c Release --collect:"XPlat Code Coverage"

      - name: Build
        id: gate-build
        run: dotnet publish -c Release -o ./publish

      - name: Secret scan
        id: gate-secret-scan
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          # GITLEAKS_LICENSE: ${{ secrets.GITLEAKS_LICENSE }}  # required for org repos

      - name: Dependency vulnerability scan
        id: gate-dep-scan
        run: |
          dotnet list package --vulnerable --include-transitive 2>&1 | tee audit.txt
          ! grep -q "Critical\|High\|Moderate" audit.txt

      - name: Generate SBOM (CycloneDX)
        id: gate-sbom
        run: |
          dotnet tool install --global CycloneDX
          dotnet CycloneDX *.sln -o . -j -f sbom.json

      - name: Upload SBOM
        uses: actions/upload-artifact@v4
        with:
          name: sbom
          path: sbom.json

      - name: Attest build provenance
        id: gate-provenance
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        uses: actions/attest-build-provenance@v1
        with:
          subject-path: ./publish/**
```

- [ ] **Step 3: Derive the governance companions**

```bash
cd ~/Development/agentic-sdlc-kit
sed 's/Python profile/.NET profile/' profiles/python/CODEOWNERS > profiles/dotnet/CODEOWNERS
sed 's/(Python profile)/(.NET profile)/' profiles/python/BRANCH-PROTECTION.md > profiles/dotnet/BRANCH-PROTECTION.md
```

- [ ] **Step 4: Verify and commit**

```bash
cd ~/Development/agentic-sdlc-kit
sh conformance/ci-gates.sh profiles/dotnet/ci.yml; echo "exit=$?"
ruby -ryaml -e "YAML.load_file('profiles/dotnet/ci.yml'); puts 'YAML OK'"
i=1; ok=1; while [ "$i" -le 11 ]; do grep -Eq "^## ${i}\. " profiles/dotnet.md || { echo "missing §$i"; ok=0; }; i=$((i+1)); done; [ "$ok" -eq 1 ] && echo "11 sections OK"
grep -Fq '[...]' profiles/dotnet.md && echo "FAIL placeholder" || echo "no [...] placeholder"
test -f profiles/dotnet/CODEOWNERS && grep -q "required_status_checks" profiles/dotnet/BRANCH-PROTECTION.md && echo "companions OK"
git add profiles/dotnet.md profiles/dotnet/
git commit -m "feat: add C#/.NET stack profile"
```
Expected: ci-gates `OK`, `exit=0`; `YAML OK`; `11 sections OK`; `no [...] placeholder`; `companions OK`.

---

### Task 2: profiles/go

**Files:** Create `profiles/go.md`, `profiles/go/ci.yml`, `profiles/go/CODEOWNERS`, `profiles/go/BRANCH-PROTECTION.md`

- [ ] **Step 1: Write `profiles/go.md`**

```markdown
# Stack Profile — Go

> Reference profile. The concrete *how* for the universal `DEVELOPMENT-STANDARDS.md` on a Go stack. Copy/adapt per project; record selection as ADR-000.

**Stack:** Go 1.22+ · net/http or chi · PostgreSQL + pgx/sqlc · `go test` · hosted (single-binary container / K8s)
**Status:** reference

---

## 1. Toolchain
- **Runtime:** Go 1.22+ · **Deps:** Go modules (`go.mod`/`go.sum` committed)
- **Format/lint:** `gofmt` + `golangci-lint` · **Types:** the compiler (`go vet` / `go build`)
- **Tests:** `go test -race -cover` · **Build:** `go build` (single static binary)

## 2. Project scaffold
\`\`\`
cmd/<app>/main.go
internal/{api,service,store,config}/
migrations/                   # golang-migrate SQL
docs/architecture/            # ADRs (incl. ADR-000)
.github/workflows/ci.yml
go.mod · go.sum · .golangci.yml · .env.example · .gitignore
\`\`\`
Baselines: `.golangci.yml` enabling govet, staticcheck, errcheck, gosec; coverage threshold 80 enforced in CI.

## 3. Standard commands
\`\`\`
install:       go mod download
dev:           go run ./cmd/<app>
test:          go test ./...
test:coverage: go test -race -coverprofile=cover.out ./...
lint:          golangci-lint run
type-check:    go vet ./...
build:         go build ./...
start:         ./<app>
\`\`\`

## 4. CI/CD pipeline
Implements the 7 required gates of `DEVELOPMENT-STANDARDS.md` §14. Drop-in reference files live in **`profiles/go/`**:
- **`ci.yml`** → copy to `.github/workflows/ci.yml`. `go mod download` → `golangci-lint` → `go vet` (type-check) → `go test -race -cover`(≥80) → `go build` → secret-scan (gitleaks) → dependency scan (`govulncheck`) → SBOM (`cyclonedx-gomod`) → build provenance.
- **`CODEOWNERS`**, **`BRANCH-PROTECTION.md`** → governance companions.

Conformance: `sh conformance/ci-gates.sh profiles/go/ci.yml`. Note: `gate-type-check`=`go vet`, `gate-build`=`go build`.

## 5. Security implementation
- **Env/secrets:** `os.Getenv` via a config struct with fail-fast validation; `.env` gitignored; commit `.env.example`.
- **Validation:** `go-playground/validator` on request structs at boundaries; validate create *and* update.
- **Injection-safe data:** `pgx`/`database/sql` parameterized queries or `sqlc`-generated code; never `fmt.Sprintf` SQL.
- **AuthN/Z:** `golang.org/x/crypto/bcrypt`; JWT (`golang-jwt`) minimal claims + short expiry; middleware authorization.
- **HTTP headers / CSRF:** secure-headers middleware (e.g. `unrolled/secure`); `gorilla/csrf` for cookie auth.
- **Rate limiting:** `golang.org/x/time/rate` or middleware (relax in test mode).

## 6. Testing
- **Convention:** `_test.go` beside source; table-driven tests; `t.Run` subtests.
- **Integration:** `net/http/httptest` + Testcontainers-go (real Postgres); assert status + body + DB state.
- **E2E:** Playwright/`rod` or HTTP-level against the running binary.
- **AI evals:** an `evals/` package with JSONL datasets; a runner scoring against a rubric (LLM-as-judge via the Anthropic Go SDK, pinned judge) failing below threshold in CI.

## 7. Resilience & observability
- **Retry/backoff:** `cenkalti/backoff`; **circuit breaker:** `sony/gobreaker`.
- **Logging:** `log/slog` (JSON handler). **Metrics/health/traces:** OpenTelemetry + Prometheus client. **Error tracking:** Sentry.

## 8. Data & migrations
- **`golang-migrate`** (SQL in `migrations/`). Expand-contract: add → backfill → switch reads → drop old later. Each migration has an `up`/`down`; no manual prod DDL.

## 9. Release & deploy
- **Build artifact:** static binary + minimal container (distroless/scratch). **Deploy:** container to K8s/Fly; merge to `main` → deploy.
- **Feature flags:** env-backed or a flag service; flag-off = fastest rollback.
- **Rollout:** staging → prod; **rollback:** redeploy previous image / revert + redeploy.

## 10. Recommended libraries
chi or net/http · pgx + sqlc · go-playground/validator · golang-jwt + x/crypto/bcrypt · cenkalti/backoff + sony/gobreaker · log/slog + OpenTelemetry + Sentry · Testcontainers-go · govulncheck + cyclonedx-gomod · golang-migrate · Anthropic Go SDK for AI features. Default Claude models: `claude-sonnet-4-6` (workhorse), escalate to Opus for hard reasoning.

## 11. Stack-specific gotchas
- Commit `go.sum`; CI uses the module cache for reproducible builds.
- `go vet`/`golangci-lint` are the lint gate; `gosec` (via golangci-lint) covers security lints.
- `go test -race` catches data races — keep it in CI; coverage is checked from `cover.out`.
- `govulncheck` reports only *reachable* vulnerabilities — exits non-zero on a real finding.
- Prefer the standard `log/slog` over third-party loggers for structured logging.
\`\`\`

---

**Last Updated:** 2026-06-06
```

- [ ] **Step 2: Write `profiles/go/ci.yml`**

```yaml
# Reference CI pipeline for the Go profile.
# COPY & ADAPT: copy to your project's .github/workflows/ci.yml. Inert here in the kit.
# Each quality gate carries a standardized `id: gate-*` that conformance/ci-gates.sh asserts.
# Satisfies DEVELOPMENT-STANDARDS.md §14. HARDENING: pin `uses:`/tools to versions for production.
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

      - uses: actions/setup-go@v5
        with:
          go-version: '1.22'

      - name: Install dependencies
        id: gate-install
        run: go mod download

      - name: Lint
        id: gate-lint
        uses: golangci/golangci-lint-action@v6

      - name: Type-check
        id: gate-type-check
        run: go vet ./...

      - name: Test + coverage (>=80%)
        id: gate-test
        run: |
          go test -race -coverprofile=cover.out ./...
          go tool cover -func=cover.out | awk '/^total:/ {gsub(/%/,"",$3); if ($3+0 < 80) {print "coverage " $3 "% < 80%"; exit 1}}'

      - name: Build
        id: gate-build
        run: go build ./...

      - name: Secret scan
        id: gate-secret-scan
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          # GITLEAKS_LICENSE: ${{ secrets.GITLEAKS_LICENSE }}  # required for org repos

      - name: Dependency vulnerability scan
        id: gate-dep-scan
        run: |
          go install golang.org/x/vuln/cmd/govulncheck@latest
          govulncheck ./...

      - name: Generate SBOM (CycloneDX)
        id: gate-sbom
        run: |
          go install github.com/CycloneDX/cyclonedx-gomod/cmd/cyclonedx-gomod@latest
          cyclonedx-gomod app -json -output sbom.json

      - name: Upload SBOM
        uses: actions/upload-artifact@v4
        with:
          name: sbom
          path: sbom.json

      - name: Attest build provenance
        id: gate-provenance
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        uses: actions/attest-build-provenance@v1
        with:
          subject-path: ./<app>   # TODO: path to the built binary
```

- [ ] **Step 3: Derive companions**

```bash
cd ~/Development/agentic-sdlc-kit
sed 's/Python profile/Go profile/' profiles/python/CODEOWNERS > profiles/go/CODEOWNERS
sed 's/(Python profile)/(Go profile)/' profiles/python/BRANCH-PROTECTION.md > profiles/go/BRANCH-PROTECTION.md
```

- [ ] **Step 4: Verify and commit**

```bash
cd ~/Development/agentic-sdlc-kit
sh conformance/ci-gates.sh profiles/go/ci.yml; echo "exit=$?"
ruby -ryaml -e "YAML.load_file('profiles/go/ci.yml'); puts 'YAML OK'"
i=1; ok=1; while [ "$i" -le 11 ]; do grep -Eq "^## ${i}\. " profiles/go.md || { echo "missing §$i"; ok=0; }; i=$((i+1)); done; [ "$ok" -eq 1 ] && echo "11 sections OK"
grep -Fq '[...]' profiles/go.md && echo "FAIL placeholder" || echo "no [...] placeholder"
test -f profiles/go/CODEOWNERS && grep -q "required_status_checks" profiles/go/BRANCH-PROTECTION.md && echo "companions OK"
git add profiles/go.md profiles/go/
git commit -m "feat: add Go stack profile"
```
Expected: ci-gates `OK`, `exit=0`; `YAML OK`; `11 sections OK`; `no [...] placeholder`; `companions OK`.

---

### Task 3: profiles/rust

**Files:** Create `profiles/rust.md`, `profiles/rust/ci.yml`, `profiles/rust/CODEOWNERS`, `profiles/rust/BRANCH-PROTECTION.md`

- [ ] **Step 1: Write `profiles/rust.md`**

```markdown
# Stack Profile — Rust

> Reference profile. The concrete *how* for the universal `DEVELOPMENT-STANDARDS.md` on a Rust stack. Copy/adapt per project; record selection as ADR-000.

**Stack:** Rust (stable) · axum · PostgreSQL + sqlx · `cargo test` · hosted (single-binary container / K8s)
**Status:** reference

---

## 1. Toolchain
- **Runtime:** Rust stable (pin via `rust-toolchain.toml`) · **Deps:** Cargo (`Cargo.lock` committed)
- **Format/lint:** `cargo fmt` + `cargo clippy` · **Types:** the compiler (`cargo check`)
- **Tests:** `cargo test` + `cargo-llvm-cov` (coverage gate) · **Build:** `cargo build --release`

## 2. Project scaffold
\`\`\`
src/{main.rs,api/,service/,store/,config.rs}
migrations/                   # sqlx migrations
tests/                        # integration tests
docs/architecture/            # ADRs (incl. ADR-000)
.github/workflows/ci.yml
Cargo.toml · Cargo.lock · rust-toolchain.toml · .env.example · .gitignore
\`\`\`
Baselines: `clippy` with `-D warnings`; `rustfmt.toml`; `cargo-llvm-cov` threshold 80.

## 3. Standard commands
\`\`\`
install:       cargo fetch
dev:           cargo run
test:          cargo test
test:coverage: cargo llvm-cov --fail-under-lines 80
lint:          cargo clippy --all-targets -- -D warnings
type-check:    cargo check --all-targets
build:         cargo build --release
start:         ./target/release/<app>
\`\`\`

## 4. CI/CD pipeline
Implements the 7 required gates of `DEVELOPMENT-STANDARDS.md` §14. Drop-in reference files live in **`profiles/rust/`**:
- **`ci.yml`** → copy to `.github/workflows/ci.yml`. `cargo fetch` → `clippy -D warnings` → `cargo check` (type-check) → `cargo test`+`llvm-cov`(≥80) → `cargo build --release` → secret-scan (gitleaks) → dependency scan (`cargo audit`) → SBOM (`cargo cyclonedx`) → build provenance.
- **`CODEOWNERS`**, **`BRANCH-PROTECTION.md`** → governance companions.

Conformance: `sh conformance/ci-gates.sh profiles/rust/ci.yml`. Note: `gate-type-check`=`cargo check`, `gate-build`=`cargo build --release`.

## 5. Security implementation
- **Env/secrets:** `std::env`/`envy` into a config struct with fail-fast; `.env` gitignored; commit `.env.example`.
- **Validation:** `validator` crate on request structs at boundaries; validate create *and* update.
- **Injection-safe data:** **sqlx** (compile-time-checked, parameterized) or `diesel`; never format SQL strings.
- **AuthN/Z:** `argon2` (or `bcrypt`) password hashing; `jsonwebtoken` minimal claims + short expiry; extractor/middleware authorization.
- **HTTP headers / CSRF:** `tower-http` `SetResponseHeaderLayer` / security middleware; CSRF for cookie auth.
- **Rate limiting:** `tower_governor` (relax in test config).

## 6. Testing
- **Convention:** unit tests in-module (`#[cfg(test)]`); integration tests in `tests/`.
- **Integration:** `axum::test` / `reqwest` + Testcontainers-rs (real Postgres); assert status + body + DB state.
- **E2E:** HTTP-level or Playwright against the running binary.
- **AI evals:** an `evals/` crate or module with JSONL datasets; a runner scoring against a rubric (LLM-as-judge via the Anthropic API, pinned judge) failing below threshold in CI.

## 7. Resilience & observability
- **Retry/backoff:** `tokio-retry` / `backoff`; **circuit breaker:** `tower` middleware.
- **Logging:** `tracing` + `tracing-subscriber` (JSON). **Metrics/health/traces:** OpenTelemetry (`tracing-opentelemetry`). **Error tracking:** Sentry.

## 8. Data & migrations
- **sqlx migrations** (`migrations/`, `sqlx migrate`). Expand-contract: add → backfill → switch reads → drop old later. Reversible where supported; no manual prod DDL.

## 9. Release & deploy
- **Build artifact:** release binary + minimal container (distroless/scratch). **Deploy:** container to K8s/Fly; merge to `main` → deploy.
- **Feature flags:** env-backed or a flag service; flag-off = fastest rollback.
- **Rollout:** staging → prod; **rollback:** redeploy previous image / revert + redeploy.

## 10. Recommended libraries
axum · sqlx (+ migrations) · validator · jsonwebtoken + argon2 · tokio-retry + tower (circuit breaking) · tracing + tracing-opentelemetry + Sentry · Testcontainers-rs · cargo-audit + cargo-cyclonedx · Anthropic API client for AI features. Default Claude models: `claude-sonnet-4-6` (workhorse), escalate to Opus for hard reasoning.

## 11. Stack-specific gotchas
- Commit `Cargo.lock` (for binaries) and pin the toolchain via `rust-toolchain.toml`.
- `cargo clippy -- -D warnings` makes lints gate; keep the tree warning-clean.
- `cargo-llvm-cov` and `cargo-audit`/`cargo-cyclonedx` are separate installs — the CI installs them.
- sqlx compile-time query checks need `DATABASE_URL` or `cargo sqlx prepare` (offline mode) committed.
- Use `cargo check` for fast type validation; reserve `--release` builds for the build gate.
\`\`\`

---

**Last Updated:** 2026-06-06
```

- [ ] **Step 2: Write `profiles/rust/ci.yml`**

```yaml
# Reference CI pipeline for the Rust profile.
# COPY & ADAPT: copy to your project's .github/workflows/ci.yml. Inert here in the kit.
# Each quality gate carries a standardized `id: gate-*` that conformance/ci-gates.sh asserts.
# Satisfies DEVELOPMENT-STANDARDS.md §14. HARDENING: pin `uses:`/tools to versions for production.
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

      - uses: dtolnay/rust-toolchain@stable
        with:
          components: clippy, rustfmt
      - uses: Swatinem/rust-cache@v2

      - name: Install dependencies
        id: gate-install
        run: cargo fetch

      - name: Lint
        id: gate-lint
        run: cargo clippy --all-targets -- -D warnings

      - name: Type-check
        id: gate-type-check
        run: cargo check --all-targets

      - name: Test + coverage (>=80%)
        id: gate-test
        run: |
          cargo install cargo-llvm-cov
          cargo llvm-cov --fail-under-lines 80

      - name: Build
        id: gate-build
        run: cargo build --release

      - name: Secret scan
        id: gate-secret-scan
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          # GITLEAKS_LICENSE: ${{ secrets.GITLEAKS_LICENSE }}  # required for org repos

      - name: Dependency vulnerability scan
        id: gate-dep-scan
        run: |
          cargo install cargo-audit
          cargo audit

      - name: Generate SBOM (CycloneDX)
        id: gate-sbom
        run: |
          cargo install cargo-cyclonedx
          cargo cyclonedx -f json

      - name: Upload SBOM
        uses: actions/upload-artifact@v4
        with:
          name: sbom
          path: "**/*.cdx.json"

      - name: Attest build provenance
        id: gate-provenance
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        uses: actions/attest-build-provenance@v1
        with:
          subject-path: target/release/<app>   # TODO: path to the built binary
```

- [ ] **Step 3: Derive companions**

```bash
cd ~/Development/agentic-sdlc-kit
sed 's/Python profile/Rust profile/' profiles/python/CODEOWNERS > profiles/rust/CODEOWNERS
sed 's/(Python profile)/(Rust profile)/' profiles/python/BRANCH-PROTECTION.md > profiles/rust/BRANCH-PROTECTION.md
```

- [ ] **Step 4: Verify and commit**

```bash
cd ~/Development/agentic-sdlc-kit
sh conformance/ci-gates.sh profiles/rust/ci.yml; echo "exit=$?"
ruby -ryaml -e "YAML.load_file('profiles/rust/ci.yml'); puts 'YAML OK'"
i=1; ok=1; while [ "$i" -le 11 ]; do grep -Eq "^## ${i}\. " profiles/rust.md || { echo "missing §$i"; ok=0; }; i=$((i+1)); done; [ "$ok" -eq 1 ] && echo "11 sections OK"
grep -Fq '[...]' profiles/rust.md && echo "FAIL placeholder" || echo "no [...] placeholder"
test -f profiles/rust/CODEOWNERS && grep -q "required_status_checks" profiles/rust/BRANCH-PROTECTION.md && echo "companions OK"
git add profiles/rust.md profiles/rust/
git commit -m "feat: add Rust stack profile"
```
Expected: ci-gates `OK`, `exit=0`; `YAML OK`; `11 sections OK`; `no [...] placeholder`; `companions OK`.

---

### Task 4: profiles/kotlin

**Files:** Create `profiles/kotlin.md`, `profiles/kotlin/ci.yml`, `profiles/kotlin/CODEOWNERS`, `profiles/kotlin/BRANCH-PROTECTION.md`

- [ ] **Step 1: Write `profiles/kotlin.md`**

```markdown
# Stack Profile — Kotlin (JVM) / Spring Boot

> Reference profile. The concrete *how* for the universal `DEVELOPMENT-STANDARDS.md` on a Kotlin/JVM stack. Copy/adapt per project; record selection as ADR-000. (Sibling of `java-spring` — Gradle + ktlint/detekt deltas.)

**Stack:** Kotlin · JDK 21 (LTS) · Gradle (Kotlin DSL) · Spring Boot 3.x · PostgreSQL + JPA/Hibernate + Flyway · JUnit 5/Kotest · hosted (container / K8s)
**Status:** reference

---

## 1. Toolchain
- **Runtime:** JDK 21 (Temurin) · **Build/deps:** Gradle (Kotlin DSL) via wrapper `./gradlew`
- **Format/lint:** ktlint (format) + detekt (static analysis) · **Types:** the compiler (`compileKotlin`)
- **Tests:** JUnit 5 / Kotest + JaCoCo (coverage gate) · **Build:** `./gradlew build`

## 2. Project scaffold
\`\`\`
src/main/kotlin/<group>/{api,service,domain,repo,config}/
src/test/kotlin/<group>/
src/main/resources/{application.yml,db/migration/}   # Flyway migrations
docs/architecture/            # ADRs (incl. ADR-000)
.github/workflows/ci.yml
build.gradle.kts · settings.gradle.kts · gradle/ · .env.example · .gitignore
\`\`\`
Baselines: `build.gradle.kts` with ktlint + detekt + jacoco (rule: line ≥0.80) + org.cyclonedx.bom + dependency-check plugins.

## 3. Standard commands
\`\`\`
install:       ./gradlew dependencies
dev:           ./gradlew bootRun
test:          ./gradlew test
test:coverage: ./gradlew test jacocoTestCoverageVerification
lint:          ./gradlew ktlintCheck detekt
type-check:    ./gradlew compileKotlin
build:         ./gradlew build -x test
start:         java -jar build/libs/*.jar
\`\`\`

## 4. CI/CD pipeline
Implements the 7 required gates of `DEVELOPMENT-STANDARDS.md` §14. Drop-in reference files live in **`profiles/kotlin/`**:
- **`ci.yml`** → copy to `.github/workflows/ci.yml`. ktlint+detekt → `compileKotlin` (type-check) → JUnit5/Kotest+JaCoCo(≥80) → `gradle build` → secret-scan (gitleaks) → dependency scan (OWASP) → SBOM (cyclonedx-gradle) → build provenance.
- **`CODEOWNERS`**, **`BRANCH-PROTECTION.md`** → governance companions.

Conformance: `sh conformance/ci-gates.sh profiles/kotlin/ci.yml`. Note: `gate-type-check`=`compileKotlin`, `gate-build`=`gradle build`.

## 5. Security implementation
- **Env/secrets:** Spring `@Value`/`Environment` / `application.yml` env placeholders; fail-fast; `.env` gitignored; commit `.env.example`.
- **Validation:** **Jakarta Bean Validation** (`@Valid`) on request DTOs (data classes); validate create *and* update.
- **Injection-safe data:** **Spring Data JPA** / parameterized; never string-concatenate JPQL/SQL.
- **AuthN/Z:** **Spring Security** — BCrypt encoder; JWT (minimal claims, short expiry); method/route authorization server-side.
- **HTTP headers / CSRF:** Spring Security default security headers; CSRF tokens for cookie auth.
- **Rate limiting:** Resilience4j `RateLimiter` or a gateway (relax in test profile).

## 6. Testing
- **Convention:** `src/test/kotlin` mirrors main; JUnit 5 or **Kotest**. Arrange-Act-Assert.
- **Integration:** `@SpringBootTest` + Testcontainers (real Postgres); assert status + body + DB state.
- **E2E:** Playwright/REST-assured against the running app.
- **AI evals:** an `evals/` source set with JSONL datasets; a runner scoring against a rubric (LLM-as-judge via the Anthropic Java/Kotlin SDK, pinned judge) failing below threshold in CI.

## 7. Resilience & observability
- **Retry/backoff + circuit breaker:** **Resilience4j**.
- **Logging:** SLF4J + Logback (JSON encoder). **Metrics/health/traces:** Micrometer + Spring Boot Actuator + OpenTelemetry. **Error tracking:** Sentry.

## 8. Data & migrations
- **JPA/Hibernate + Flyway.** Versioned SQL in `db/migration` (`V<n>__desc.sql`). Expand-contract: add → backfill → switch reads → drop old later. No manual prod DDL.

## 9. Release & deploy
- **Build artifact:** executable jar + container image (Jib/buildpacks). **Deploy:** container to K8s/Fly; merge to `main` → deploy.
- **Feature flags:** a flag service or Spring `@ConfigurationProperties`; flag-off = fastest rollback.
- **Rollout:** staging → prod; **rollback:** redeploy previous image / revert + redeploy.

## 10. Recommended libraries
Spring Boot starters (web, security, data-jpa, validation, actuator) · Resilience4j · Flyway · Micrometer + Sentry · JUnit 5 / Kotest + JaCoCo + Testcontainers · ktlint + detekt · cyclonedx-gradle + dependency-check-gradle · Anthropic Java SDK for AI features. Default Claude models: `claude-sonnet-4-6` (workhorse), escalate to Opus for hard reasoning.

## 11. Stack-specific gotchas
- Use `./gradlew` (the wrapper) for reproducible builds; commit `gradle/wrapper`.
- ktlint = formatting/style; detekt = static analysis/smells — both gate in CI.
- JaCoCo `jacocoTestCoverageVerification` binds to `check`; CI runs it explicitly.
- OWASP dependency-check's first run downloads the NVD DB (slow) — cache it in CI.
- Use Spring profiles (`application-<env>.yml`) for env config — never env conditionals in code.
\`\`\`

---

**Last Updated:** 2026-06-06
```

- [ ] **Step 2: Write `profiles/kotlin/ci.yml`**

```yaml
# Reference CI pipeline for the Kotlin/Spring profile.
# COPY & ADAPT: copy to your project's .github/workflows/ci.yml. Inert here in the kit.
# Each quality gate carries a standardized `id: gate-*` that conformance/ci-gates.sh asserts.
# Satisfies DEVELOPMENT-STANDARDS.md §14. HARDENING: pin `uses:` SHAs + Gradle plugin versions.
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

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'
          cache: gradle

      - name: Lint / format check
        id: gate-lint
        run: ./gradlew ktlintCheck detekt

      - name: Type-check (compile)
        id: gate-type-check
        run: ./gradlew compileKotlin

      - name: Test + coverage (JaCoCo >=80%)
        id: gate-test
        run: ./gradlew test jacocoTestCoverageVerification

      - name: Build
        id: gate-build
        run: ./gradlew build -x test

      - name: Secret scan
        id: gate-secret-scan
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          # GITLEAKS_LICENSE: ${{ secrets.GITLEAKS_LICENSE }}  # required for org repos

      - name: Dependency vulnerability scan (OWASP)
        id: gate-dep-scan
        run: ./gradlew dependencyCheckAnalyze

      - name: Generate SBOM (CycloneDX)
        id: gate-sbom
        run: ./gradlew cyclonedxBom

      - name: Upload SBOM
        uses: actions/upload-artifact@v4
        with:
          name: sbom
          path: build/reports/bom.json

      - name: Attest build provenance
        id: gate-provenance
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        uses: actions/attest-build-provenance@v1
        with:
          subject-path: build/libs/*.jar
```

- [ ] **Step 3: Derive companions**

```bash
cd ~/Development/agentic-sdlc-kit
sed 's/Python profile/Kotlin profile/' profiles/python/CODEOWNERS > profiles/kotlin/CODEOWNERS
sed 's/(Python profile)/(Kotlin profile)/' profiles/python/BRANCH-PROTECTION.md > profiles/kotlin/BRANCH-PROTECTION.md
```

- [ ] **Step 4: Verify and commit**

```bash
cd ~/Development/agentic-sdlc-kit
sh conformance/ci-gates.sh profiles/kotlin/ci.yml; echo "exit=$?"
ruby -ryaml -e "YAML.load_file('profiles/kotlin/ci.yml'); puts 'YAML OK'"
i=1; ok=1; while [ "$i" -le 11 ]; do grep -Eq "^## ${i}\. " profiles/kotlin.md || { echo "missing §$i"; ok=0; }; i=$((i+1)); done; [ "$ok" -eq 1 ] && echo "11 sections OK"
grep -Fq '[...]' profiles/kotlin.md && echo "FAIL placeholder" || echo "no [...] placeholder"
test -f profiles/kotlin/CODEOWNERS && grep -q "required_status_checks" profiles/kotlin/BRANCH-PROTECTION.md && echo "companions OK"
git add profiles/kotlin.md profiles/kotlin/
git commit -m "feat: add Kotlin/Spring stack profile"
```
Expected: ci-gates `OK`, `exit=0`; `YAML OK`; `11 sections OK`; `no [...] placeholder`; `companions OK`.

---

### Task 5: scripts/new-profile.sh (BYO scaffolder)

**Files:** Create `scripts/new-profile.sh`

- [ ] **Step 1: Write the scaffolder**

Create `scripts/new-profile.sh` with exactly this content:

```sh
#!/bin/sh
# new-profile.sh — scaffold a new stack profile so an unsupported stack is a guided,
# validated workflow (START-HERE.md §2B; the kit is never limited to pre-written stacks).
# Usage: sh scripts/new-profile.sh <stack-name>
# Creates profiles/<stack>.md (from _TEMPLATE.md) + profiles/<stack>/{ci.yml,CODEOWNERS,BRANCH-PROTECTION.md}.
# The stub ci.yml declares all 8 gate-* ids (placeholder run commands) so it passes the
# STRUCTURAL ci-gates.sh check immediately. Fill the 11 sections + real commands, then run
# `sh conformance/profile-completeness.sh` to validate.
set -eu

STACK="${1:-}"
[ -n "$STACK" ] || { echo "usage: new-profile.sh <stack-name>" >&2; exit 2; }
case "$STACK" in
  */*|*" "*|.*) echo "error: stack name must be a simple slug (e.g. go, dotnet, swift)" >&2; exit 2 ;;
esac
[ -f profiles/_TEMPLATE.md ] || { echo "error: run from the kit repo root (profiles/_TEMPLATE.md not found)" >&2; exit 1; }
if [ -e "profiles/${STACK}.md" ] || [ -e "profiles/${STACK}" ]; then
  echo "error: profiles/${STACK}.md or profiles/${STACK}/ already exists — choose another name" >&2; exit 1
fi

esc() { printf '%s' "$1" | sed 's/[&/\\]/\\&/g'; }

# 1. profile.md from the template (title stamped; sections remain [...] to fill)
cp profiles/_TEMPLATE.md "profiles/${STACK}.md"
sed -i.bak "s/\[Stack Name\]/$(esc "$STACK")/" "profiles/${STACK}.md" && rm -f "profiles/${STACK}.md.bak"

# 2. companion dir + stub ci.yml declaring all 8 required gate ids
mkdir -p "profiles/${STACK}"
cat > "profiles/${STACK}/ci.yml" <<'YAML'
# Reference CI pipeline — STUB generated by scripts/new-profile.sh.
# Replace each `run:` TODO with your stack's command. The 8 gate-* ids below satisfy
# DEVELOPMENT-STANDARDS.md §14 and conformance/ci-gates.sh — do NOT rename them.
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
      # TODO: add your language/runtime setup action
      - name: Lint
        id: gate-lint
        run: echo "TODO: lint command"
      - name: Type-check
        id: gate-type-check
        run: echo "TODO: type-check / compile command"
      - name: Test + coverage (>=80%)
        id: gate-test
        run: echo "TODO: test + coverage command"
      - name: Build
        id: gate-build
        run: echo "TODO: build command"
      - name: Secret scan
        id: gate-secret-scan
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      - name: Dependency vulnerability scan
        id: gate-dep-scan
        run: echo "TODO: dependency vulnerability scan command"
      - name: Generate SBOM (CycloneDX)
        id: gate-sbom
        run: echo "TODO: SBOM generation command"
      - name: Attest build provenance
        id: gate-provenance
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        uses: actions/attest-build-provenance@v1
        with:
          subject-path: dist/**   # TODO: your built artifact path
YAML

# 3. governance companions (derive from the shipped Python reference; stack-neutral)
sed "s/Python profile/${STACK} profile/" profiles/python/CODEOWNERS > "profiles/${STACK}/CODEOWNERS"
sed "s/(Python profile)/(${STACK} profile)/" profiles/python/BRANCH-PROTECTION.md > "profiles/${STACK}/BRANCH-PROTECTION.md"

cat <<EOF
Scaffolded:
  profiles/${STACK}.md
  profiles/${STACK}/ci.yml          (stub — passes ci-gates structurally)
  profiles/${STACK}/CODEOWNERS
  profiles/${STACK}/BRANCH-PROTECTION.md

Next:
  1. Fill all 11 sections in profiles/${STACK}.md (replace every [...]).
  2. Replace each TODO 'run:' in profiles/${STACK}/ci.yml with your stack's real command.
  3. Validate:  sh conformance/profile-completeness.sh
  4. Record the choice as ADR-000 and select this profile at Inception.
EOF
```

- [ ] **Step 2: Syntax check + dash check**

```bash
cd ~/Development/agentic-sdlc-kit
chmod +x scripts/new-profile.sh
sh -n scripts/new-profile.sh && echo "syntax OK"
dash -n scripts/new-profile.sh 2>/dev/null && echo "dash OK" || echo "dash check skipped/failed"
```
Expected: `syntax OK`; `dash OK` (dash present on this host).

- [ ] **Step 3: Functional test (create → stub passes ci-gates → completeness flags unfilled → re-run refuses → clean up)**

```bash
cd ~/Development/agentic-sdlc-kit
sh scripts/new-profile.sh demostack
echo "--- stub ci.yml passes ci-gates (structure) ---"
sh conformance/ci-gates.sh profiles/demostack/ci.yml; echo "exit=$?"
echo "--- profile-completeness flags the unfilled profile ---"
sh conformance/profile-completeness.sh; echo "exit=$? (expect 1 — demostack has [...])"
echo "--- re-run refuses ---"
sh scripts/new-profile.sh demostack; echo "rerun-exit=$?"
echo "--- bad name rejected ---"
sh scripts/new-profile.sh "a/b"; echo "badname-exit=$?"
echo "--- CLEAN UP (never commit demostack) ---"
rm -rf profiles/demostack.md profiles/demostack
git status --short profiles/
```
Expected: ci-gates on the stub `OK`/`exit=0`; profile-completeness `FAIL demostack.md: leftover [...]` with `exit=1`; re-run prints "already exists" with `rerun-exit=1`; bad name `badname-exit=2`; after cleanup `git status --short profiles/` shows NOTHING (demostack fully removed).

- [ ] **Step 4: Commit (only the script — confirm no demostack residue)**

```bash
cd ~/Development/agentic-sdlc-kit
git status --short
git add scripts/new-profile.sh
git commit -m "feat: add new-profile.sh scaffolder for bring-your-own stacks"
```

---

### Task 6: README + START-HERE "Generate your own profile" on-ramp

**Files:** Modify `README.md`, `START-HERE.md`

- [ ] **Step 1: Add a "Generate your own profile" section to README**

In `README.md`, find this exact line:

```
## Adapting it
```

Insert immediately **before** it:

```
## Generate your own profile (any stack)

The kit ships first-class profiles for **TypeScript/Node, Python, Java/Spring, C#/.NET, Go, Rust, and Kotlin** — but it is **never limited to them**. For any other stack:

1. `sh scripts/new-profile.sh <stack>` — scaffolds `profiles/<stack>.md` (from the template) + a stub `profiles/<stack>/ci.yml` whose 8 quality-gate ids already satisfy `conformance/ci-gates.sh`.
2. Fill the 11 profile sections and replace each `run:` command with your stack's tooling.
3. `sh conformance/profile-completeness.sh` validates it to the same bar as the shipped profiles.

Then select it at Inception (`incept.sh --stack <stack>`) and record it as ADR-000. A generated profile is held to the identical conformance bar — so "unsupported stack" is a guided, validated path, not a dead end.

```

- [ ] **Step 2: Point START-HERE §2B at the scaffolder**

In `START-HERE.md`, find this exact line:

```
**B — Generate a custom profile (any stack).** If your stack isn't there — Python, Go, Rust, Java, Elixir, anything:
```

Replace with:

```
**B — Generate a custom profile (any stack).** If your stack isn't there — Elixir, Scala, Swift, anything not already shipped. Fastest start: `sh scripts/new-profile.sh <stack>` scaffolds the profile + a conformance-passing stub `ci.yml`, then:
```

- [ ] **Step 3: Verify and commit**

```bash
cd ~/Development/agentic-sdlc-kit
grep -c "Generate your own profile" README.md
grep -c "new-profile.sh" README.md START-HERE.md
sh conformance/check-links.sh >/dev/null && echo "links OK"
git add README.md START-HERE.md
git commit -m "docs: add 'Generate your own profile' on-ramp (README + START-HERE)"
```
Expected: `1` (README heading); `new-profile.sh` referenced in both files; `links OK`.

---

### Task 7: VERSION + CHANGELOG + ROADMAP (2.4.0)

**Files:** Modify `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-KIT.md`

- [ ] **Step 1: Bump VERSION**

Overwrite `VERSION` with exactly one line + trailing newline:

```
2.4.0
```

- [ ] **Step 2: Add the 2.4.0 CHANGELOG entry**

In `CHANGELOG.md`, find this exact line:

```
## [2.3.0] - 2026-06-06
```

Insert IMMEDIATELY BEFORE it:

```
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

```

- [ ] **Step 3: Add the 2.4.0 link reference**

In `CHANGELOG.md`, find:

```
[2.3.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.3.0
```

Replace with:

```
[2.4.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.4.0
[2.3.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.3.0
```

- [ ] **Step 4: Note the profile expansion in the roadmap**

In `docs/ROADMAP-KIT.md`, find this exact line:

```
| 5 ✅ | **Enterprise profiles** *(shipped v2.3.0)* | `profiles/_TEMPLATE.md` | `profiles/python.md` + `profiles/java-spring.md` + companion `ci.yml`/`CODEOWNERS`/`BRANCH-PROTECTION.md` | `conformance/profile-completeness.sh` |
```

Replace with:

```
| 5 ✅ | **Enterprise profiles** *(v2.3.0; +v2.4.0)* | `profiles/_TEMPLATE.md` | Python + Java/Spring (v2.3.0); **.NET + Go + Rust + Kotlin + `scripts/new-profile.sh` BYO on-ramp (v2.4.0)** | `conformance/profile-completeness.sh` |
```

- [ ] **Step 5: Verify and commit**

```bash
cd ~/Development/agentic-sdlc-kit
cat VERSION
grep -c "## \[2.4.0\]" CHANGELOG.md
grep -c "v2.4.0" docs/ROADMAP-KIT.md
git add VERSION CHANGELOG.md docs/ROADMAP-KIT.md
git commit -m "release: 2.4.0 — Slice 5b more profiles + BYO on-ramp (changelog + roadmap)"
```
Expected: `2.4.0`; `1`; `1` or more.

---

### Task 8: Final validation + PR

**Files:** none created; verification + PR only.

- [ ] **Step 1: Full conformance sweep over all 7 profiles**

```bash
cd ~/Development/agentic-sdlc-kit
sh conformance/profile-completeness.sh; echo "exit=$?"
for p in typescript-node python java-spring dotnet go rust kotlin; do sh conformance/ci-gates.sh "profiles/$p/ci.yml" >/dev/null && echo "ci-gates $p OK"; done
sh conformance/agent-autonomy.sh >/dev/null && echo "agent-autonomy OK"
sh conformance/check-links.sh >/dev/null && echo "check-links OK"
```
Expected: profile-completeness all PASS + `exit=0`; `ci-gates <p> OK` for all 7; agent-autonomy OK; check-links OK.

- [ ] **Step 2: incept wires each new profile (end-to-end)**

```bash
cd ~/Development/agentic-sdlc-kit
for stack in dotnet go rust kotlin; do
  tmp=$(mktemp -d); git archive HEAD | tar -x -C "$tmp"
  ( cd "$tmp" && sh scripts/incept.sh --noninteractive --name "Demo-$stack" --intent-owner "CI" --stack "$stack" --backlog md ) >/dev/null
  sh conformance/inception-done.sh "$tmp" >/dev/null && echo "incept --stack $stack -> inception-done OK"
  sh conformance/ci-gates.sh "$tmp/.github/workflows/ci.yml" >/dev/null && echo "  wired $stack CI satisfies §14"
  rm -rf "$tmp"
done
```
Expected: for all four stacks, `incept --stack <stack> -> inception-done OK` and `wired <stack> CI satisfies §14`.

- [ ] **Step 3: Push and open the PR**

```bash
cd ~/Development/agentic-sdlc-kit
git push -u origin feature/slice-5b-more-profiles
gh pr create --title "Slice 5b: .NET + Go + Rust + Kotlin profiles + bring-your-own on-ramp (v2.4.0)" --body "$(cat <<'EOF'
## Summary
Four more first-class stack profiles + a guided bring-your-own-stack workflow. The kit now ships **7 stacks**: TypeScript, Python, Java/Spring, C#/.NET, Go, Rust, Kotlin.

- **`profiles/dotnet|go|rust|kotlin`** — each: full 11-section `.md` + companion `ci.yml` (8 §14 gate ids) + `CODEOWNERS` + `BRANCH-PROTECTION.md`, with vetted modern toolchains.
- **`scripts/new-profile.sh`** — scaffolds any new stack profile + a stub `ci.yml` that passes `ci-gates.sh` *structurally* on creation; `profile-completeness.sh` validates it once filled. Unsupported stack = guided, validated workflow, not a dead end.
- **README "Generate your own profile"** + `START-HERE.md` §2B pointer.
- **Release** 2.4.0 (MINOR).

## Verified
All 7 `ci.yml`s pass `ci-gates.sh`; `profile-completeness.sh` passes all 7 profiles; `incept --stack {dotnet,go,rust,kotlin}` wires CI and passes `inception-done.sh`; `new-profile.sh` tested (creates, stub passes ci-gates, completeness flags an unfilled profile, re-run refuses, bad-name rejected). Zero new conformance logic — the stack-neutral checks from Slice 1/5 validate everything.

## Ratification
Additive profiles + tooling + docs. **Human ratification required before merge.**

Spec: `docs/superpowers/specs/2026-06-06-slice5b-more-profiles-design.md`
Plan: `docs/superpowers/plans/2026-06-06-slice5b-more-profiles.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
Expected: branch pushed; PR URL printed; CI starts.

- [ ] **Step 4: Report CI status, stop for ratification**

```bash
cd ~/Development/agentic-sdlc-kit
sleep 15
gh pr checks 2>&1 | head
```
Do **not** merge. Report PR URL + CI results.

---

## Self-Review (completed by plan author)

**Spec coverage:** §3 deliverables all mapped — dotnet→T1, go→T2, rust→T3, kotlin→T4, new-profile.sh→T5, README/START-HERE→T6, VERSION/CHANGELOG/ROADMAP→T7, validation/PR→T8. Spec §6 validation (ci-gates per profile, profile-completeness over all 7, incept wiring, new-profile.sh behaviors) appears in T1–T5 and T8.

**Placeholder scan:** no TBD/TODO in the *plan*. The `TODO:` strings live only inside the `new-profile.sh` *stub* it emits (intentional — the adopter fills them) and the `<app>`/`<Project>` tokens in profiles are scaffold-illustration, not the `[...]` template marker the completeness check flags. The `subject-path: ./<app>` / `target/release/<app>` in the Go/Rust reference `ci.yml`s carry an inline `# TODO` note for the adopter (the workflow is copy-and-adapt; this does not affect any `gate-*` id, so ci-gates passes).

**Type/name consistency:** all four `ci.yml`s declare the identical 8 `gate-*` ids `ci-gates.sh` requires; profile filenames (`dotnet`/`go`/`rust`/`kotlin`) match companion dirs and the `--stack` values in T8; the companion-derivation `sed` uses the Python reference's actual strings ("Python profile" in CODEOWNERS header; "(Python profile)" in BRANCH-PROTECTION H1). SBOM upload paths point at each tool's real default (`sbom.json` where `--output`/`-output` set it; `build/reports/bom.json` for cyclonedx-gradle; `**/*.cdx.json` for cargo-cyclonedx) — applying the Slice-5 SBOM-path lesson.
