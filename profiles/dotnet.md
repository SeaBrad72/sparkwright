# Stack Profile — C# / .NET

> Reference profile. The concrete *how* for the universal `DEVELOPMENT-STANDARDS.md` on a C#/.NET stack. Copy/adapt per project; record selection as ADR-000.

**Stack:** .NET 8 (LTS) · C# · ASP.NET Core · PostgreSQL + EF Core · xUnit · hosted (container / Azure / K8s)
**Status:** reference

---

## Best for / Avoid when

**Best for:** C#/Azure enterprise, Windows shops, high-performance services.
**Avoid when:** One-off scripts; teams with no .NET familiarity.

Choosing a stack? Compare all profiles → [../docs/STACK-SELECTION.md](../docs/STACK-SELECTION.md).

---

## 1. Toolchain
- **Runtime:** .NET 8 LTS · **Build/deps:** `dotnet` CLI + NuGet (lockfile `packages.lock.json`, `RestoreLockedMode` in CI)
- **Format/lint:** `dotnet format` + Roslyn analyzers (`TreatWarningsAsErrors`) · **Types:** the compiler (`dotnet build` = type-check) · **Complexity/duplication** (recommended `gate-lint` config): Roslyn analyzers / SonarAnalyzer + `jscpd` (`docs/operations/code-quality.md`)
- **Tests:** xUnit + coverlet (coverage gate) · **Test quality:** FsCheck/CsCheck (property-based) + Stryker.NET (mutation — `docs/operations/test-quality.md`) · **Build:** `dotnet publish -c Release`
- **Inner loop:** `pre-commit` (`dotnet format` + analyzers; `dotnet test --filter`) — fast feedback before CI (`docs/operations/dev-inner-loop.md`)

## 2. Project scaffold
```
src/<Project>/{Controllers,Services,Domain,Data,Config}/
tests/<Project>.Tests/
docs/architecture/            # ADRs (incl. ADR-000)
.github/workflows/ci.yml
<Solution>.sln · Directory.Build.props · .editorconfig · .env.example · .gitignore
```
Baselines: `.editorconfig` for analyzers; `Directory.Build.props` with `TreatWarningsAsErrors=true`, `EnableNETAnalyzers=true`; coverlet threshold 80.

## 3. Standard commands
```
install:       dotnet restore --locked-mode
dev:           dotnet watch run
test:          dotnet test
test:coverage: dotnet test --collect:"XPlat Code Coverage"
lint:          dotnet format --verify-no-changes
type-check:    dotnet build --no-restore
build:         dotnet publish -c Release
start:         dotnet <Project>.dll
```

### Environments this stack needs
**Default archetype: DB-backed service.** The shipped `compose.yaml` provides the app + a Postgres database for dev/prod parity.
The profile ships `compose.yaml` + `Dockerfile` as **COPY-&-ADAPT references** (incept does not auto-copy them); adapt them when you containerize, adding services only as your feature needs them. The image-build CI gates skip until a `Dockerfile` is present.

| Need | Default | Add when |
|------|---------|----------|
| Database | Postgres (in compose) | relational data (the default) |
| Cache | — | sessions / hot-path caching (Redis) |
| Queue / broker | — | events / async messaging (Azure Service Bus / RabbitMQ) |
| Object store | — | blobs / file storage (Azure Blob / S3) |

Promote **Dev → QA → UAT → Prod** with gated promotion; **production is human-gated**
(DEVELOPMENT-PROCESS.md env model). Record your approach in RUNBOOK §1/§4.

## 4. CI/CD pipeline
Implements the 7 required gates of `DEVELOPMENT-STANDARDS.md` §14. Drop-in reference files live in **`profiles/dotnet/`**:
- **`ci.yml`** → copy to `.github/workflows/ci.yml`. `dotnet restore` → `dotnet format --verify-no-changes` → `dotnet build` (type-check) → `dotnet test`+coverage(≥80) → `dotnet publish -c Release` → secret-scan (gitleaks) → dependency scan (`dotnet list package --vulnerable`) → SBOM (`dotnet CycloneDX`) → build provenance.
- **`CODEOWNERS`**, **`BRANCH-PROTECTION.md`** → governance companions.
- **Container image supply-chain (this profile ships a service):** the reference `ci.yml` adds `gate-image-sbom` (Syft/CycloneDX, on PR) and `gate-image-provenance` (digest-bound, push-only) on top of the 8 universal gate-ids. Verified by `conformance/container-supply-chain.sh`.

Conformance: `sh conformance/ci-gates.sh profiles/dotnet/ci.yml`. Note: compilation **is** type-checking — `gate-type-check`=`dotnet build`, `gate-build`=`dotnet publish`.

## 5. Security implementation
- **Env/secrets:** `IConfiguration` + environment / user-secrets in dev; fail-fast on missing; `.env`/secrets gitignored; commit `.env.example`.
- **Validation:** **FluentValidation** (or DataAnnotations `[Required]` + `ModelState`) at every boundary; validate create *and* update.
- **Injection-safe data:** **EF Core** (parameterized LINQ) / `FromSqlInterpolated`; never string-concat SQL.
- **AuthN/Z:** ASP.NET Core Identity (BCrypt/PBKDF2) or JWT bearer (minimal claims, short expiry); `[Authorize]` policies server-side.
- **HTTP headers / CSRF:** security-headers middleware (`NetEscapades.AspNetCore.SecurityHeaders`); antiforgery tokens for cookie auth.
- **Rate limiting:** built-in `RateLimiter` middleware (relax in test env).
- **Static analysis & licenses (conditional gates — `docs/operations/security-scanning.md`):** SAST via **Semgrep (or CodeQL)** (`gate-sast`); license policy via `scripts/license-check.sh` over the CycloneDX SBOM (`gate-license`, stack-neutral default — upgrade per the ladder if needed).

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
- **Container (service):** build the multi-stage non-root image (`profiles/dotnet/Dockerfile`, chiseled `aspnet:8.0` base, `USER 1654`), run locally via `compose.yaml` (dev/prod parity). CI scans the image SBOM on every PR (`gate-image-sbom`) and, on merge to `main`, pushes to GHCR and attests **provenance bound to the image digest** (`gate-image-provenance`). Deploy the **attested digest** via `deploy/k8s/` or the Helm chart in `deploy/helm/` (read-only root FS + writable `/tmp`; persist Data Protection keys to a volume/vault if used). Promote the same digest Dev → QA → UAT → Prod; rollback = redeploy the previous digest. (No in-image HEALTHCHECK or devcontainer — chiseled has no shell; k8s probes are the health mechanism.)
- **Feature flags:** `Microsoft.FeatureManagement` or a flag service; flag-off = fastest rollback.
- **Rollout:** staging → prod; **rollback:** redeploy previous image / revert + redeploy.

## 10. Recommended libraries
ASP.NET Core · EF Core (+ Npgsql) · FluentValidation · ASP.NET Core Identity / JwtBearer · Polly (`Microsoft.Extensions.Http.Resilience`) · Serilog + OpenTelemetry + Sentry · xUnit + coverlet + Testcontainers + WebApplicationFactory · CycloneDX .NET tool · Anthropic .NET SDK for AI features. Default Claude models: `claude-sonnet-4-6` (workhorse), escalate to Opus for hard reasoning.

## 11. Stack-specific gotchas
- Commit `packages.lock.json`; use `dotnet restore --locked-mode` in CI for reproducible restores.
- `dotnet format --verify-no-changes` fails on drift (CI); `dotnet format` fixes locally.
- Set `TreatWarningsAsErrors=true` + `EnableNETAnalyzers=true` so analyzer findings gate.
- `dotnet list package --vulnerable --include-transitive` exits 0 even with findings — the CI step greps output and fails on any vulnerability.
- Install the SBOM tool: `dotnet tool install --global CycloneDX` (CLI flags: `-F Json -fn <file>`).
- The coverage **gate** needs the `coverlet.msbuild` package in the test project — `/p:Threshold=80 /p:ThresholdType=line` fails the build below 80% (the `--collect` collector alone only gathers, it does not enforce).

---

**Last Updated:** 2026-06-06
