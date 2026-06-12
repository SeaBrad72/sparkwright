# Stack Profile — Go

> Reference profile. The concrete *how* for the universal `DEVELOPMENT-STANDARDS.md` on a Go stack. Copy/adapt per project; record selection as ADR-000.

**Stack:** Go 1.22+ · net/http or chi · PostgreSQL + pgx/sqlc · `go test` · hosted (single-binary container / K8s)
**Status:** reference

---

## Best for / Avoid when

**Best for:** Networked services, CLIs, high-concurrency, single-binary cloud infra.
**Avoid when:** Rich desktop GUIs; heavy data-science/numerics.

Choosing a stack? Compare all profiles → [../docs/STACK-SELECTION.md](../docs/STACK-SELECTION.md).

---

## 1. Toolchain
- **Runtime:** Go 1.22+ · **Deps:** Go modules (`go.mod`/`go.sum` committed)
- **Format/lint:** `gofmt` + `golangci-lint` · **Types:** the compiler (`go vet` / `go build`) · **Complexity/duplication** (recommended `gate-lint` config): `gocyclo` / `gocognit` + `dupl` via golangci-lint (`docs/operations/code-quality.md`)
- **Tests:** `go test -race -cover` · **Test quality:** rapid/gopter (property-based) + go-mutesting (mutation — `docs/operations/test-quality.md`) · **Build:** `go build` (single static binary)
- **Inner loop:** `pre-commit` (gofmt + golangci-lint; `go test ./<changed-pkg>`) — fast feedback before CI (`docs/operations/dev-inner-loop.md`)

## 2. Project scaffold
```
cmd/<app>/main.go
internal/{api,service,store,config}/
migrations/                   # golang-migrate SQL
docs/architecture/            # ADRs (incl. ADR-000)
.github/workflows/ci.yml
go.mod · go.sum · .golangci.yml · .env.example · .gitignore
```
Baselines: `.golangci.yml` enabling govet, staticcheck, errcheck, gosec; coverage threshold 80 enforced in CI.

## 3. Standard commands
```
install:       go mod download
dev:           go run ./cmd/<app>
test:          go test ./...
test:coverage: go test -race -coverprofile=cover.out ./...
lint:          golangci-lint run
type-check:    go vet ./...
build:         go build ./...
start:         ./<app>
```

## 4. CI/CD pipeline
Implements the 7 required gates of `DEVELOPMENT-STANDARDS.md` §14. Drop-in reference files live in **`profiles/go/`**:
- **`ci.yml`** → copy to `.github/workflows/ci.yml`. `go mod download` → `golangci-lint` → `go vet` (type-check) → `go test -race -cover`(≥80) → `go build` → secret-scan (gitleaks) → dependency scan (`govulncheck`) → SBOM (`cyclonedx-gomod`) → build provenance.
- **`CODEOWNERS`**, **`BRANCH-PROTECTION.md`** → governance companions.
- **Container image supply-chain (this profile ships a service):** the reference `ci.yml` adds `gate-image-sbom` (Syft/CycloneDX, on PR) and `gate-image-provenance` (digest-bound, push-only) on top of the 8 universal gate-ids. Verified by `conformance/container-supply-chain.sh`.

Conformance: `sh conformance/ci-gates.sh profiles/go/ci.yml`. Note: `gate-type-check`=`go vet`, `gate-build`=`go build`.

## 5. Security implementation
- **Env/secrets:** `os.Getenv` via a config struct with fail-fast validation; `.env` gitignored; commit `.env.example`.
- **Validation:** `go-playground/validator` on request structs at boundaries; validate create *and* update.
- **Injection-safe data:** `pgx`/`database/sql` parameterized queries or `sqlc`-generated code; never `fmt.Sprintf` SQL.
- **AuthN/Z:** `golang.org/x/crypto/bcrypt`; JWT (`golang-jwt`) minimal claims + short expiry; middleware authorization.
- **HTTP headers / CSRF:** secure-headers middleware (e.g. `unrolled/secure`); `gorilla/csrf` for cookie auth.
- **Rate limiting:** `golang.org/x/time/rate` or middleware (relax in test mode).
- **Static analysis & licenses (conditional gates — `docs/operations/security-scanning.md`):** SAST via **Semgrep + `gosec` (already via golangci-lint)** (`gate-sast`); license policy via `scripts/license-check.sh` over the CycloneDX SBOM (`gate-license`, stack-neutral default — upgrade per the ladder if needed).

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
- **Container (service):** build the multi-stage non-root image (`profiles/go/Dockerfile`, distroless `static` base), run locally via `compose.yaml` (dev/prod parity). CI scans the image SBOM on every PR (`gate-image-sbom`) and, on merge to `main`, pushes to GHCR and attests **provenance bound to the image digest** (`gate-image-provenance`). Deploy the **attested digest** via `deploy/k8s/` or the Helm chart in `deploy/helm/` (probes, resource limits, non-root `securityContext`). Promote the same digest Dev → QA → UAT → Prod; rollback = redeploy the previous digest. (A devcontainer isn't shipped — distroless has no shell; add one against `golang:1.22` if desired.)
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

---

**Last Updated:** 2026-06-06
