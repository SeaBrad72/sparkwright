# Stack Profile — Rust

> Reference profile. The concrete *how* for the universal `DEVELOPMENT-STANDARDS.md` on a Rust stack. Copy/adapt per project; record selection as ADR-000.

**Stack:** Rust (stable) · axum · PostgreSQL + sqlx · `cargo test` · hosted (single-binary container / K8s)
**Status:** reference

---

## Best for / Avoid when

**Best for:** Performance- and safety-critical systems, embedded-adjacent, WASM.
**Avoid when:** Rapid CRUD where delivery velocity dominates; exploratory prototyping.

Choosing a stack? Compare all profiles → [../docs/STACK-SELECTION.md](../docs/STACK-SELECTION.md).

---

## 1. Toolchain
- **Runtime:** Rust stable (pin via `rust-toolchain.toml`) · **Deps:** Cargo (`Cargo.lock` committed)
- **Format/lint:** `cargo fmt` + `cargo clippy` · **Types:** the compiler (`cargo check`) · **Complexity/duplication** (recommended `gate-lint` config): `clippy::cognitive_complexity` + `jscpd` (`docs/operations/code-quality.md`)
- **Tests:** `cargo test` + `cargo-llvm-cov` (coverage gate) · **Test quality:** proptest/quickcheck (property-based) + cargo-mutants (mutation — `docs/operations/test-quality.md`) · **Build:** `cargo build --release`
- **Inner loop:** `pre-commit` (rustfmt + clippy; `cargo test`) — fast feedback before CI (`docs/operations/dev-inner-loop.md`)

## 2. Project scaffold
```
src/{main.rs,api/,service/,store/,config.rs}
migrations/                   # sqlx migrations
tests/                        # integration tests
docs/architecture/            # ADRs (incl. ADR-000)
.github/workflows/ci.yml
Cargo.toml · Cargo.lock · rust-toolchain.toml · .env.example · .gitignore
```
Baselines: `clippy` with `-D warnings`; `rustfmt.toml`; `cargo-llvm-cov` threshold 80.

## 3. Standard commands
```
install:       cargo fetch
dev:           cargo run
test:          cargo test
test:coverage: cargo llvm-cov --fail-under-lines 80
lint:          cargo clippy --all-targets -- -D warnings
type-check:    cargo check --all-targets
build:         cargo build --release
start:         ./target/release/<app>
```

### Environments this stack needs
**Default archetype: stateless service.** The shipped `compose.yaml` provides the **app only — no database**; this stack defaults to a systems service / CLI with no backing store.
The profile ships `compose.yaml` + `Dockerfile` as **COPY-&-ADAPT references** (incept does not auto-copy them); adapt them when you containerize, adding services only as your feature needs them. The image-build CI gates skip until a `Dockerfile` is present.

| Need | Default | Add when |
|------|---------|----------|
| Database | — (none; add if needed) | you need relational/persistent data |
| Cache | — | hot-path caching / shared state (Redis) |
| Queue / broker | — | async/background jobs |
| Object store | — | blobs / file storage (S3/MinIO) |

Promote **Dev → QA → UAT → Prod** with gated promotion; **production is human-gated**
(DEVELOPMENT-PROCESS.md env model). Record your approach in RUNBOOK §1/§4.

## 4. CI/CD pipeline
Implements the 7 required gates of `DEVELOPMENT-STANDARDS.md` §14. Drop-in reference files live in **`profiles/rust/`**:
- **`ci.yml`** → copy to `.github/workflows/ci.yml`. `cargo fetch` → `clippy -D warnings` → `cargo check` (type-check) → `cargo test`+`llvm-cov`(≥80) → `cargo build --release` → secret-scan (gitleaks) → dependency scan (`cargo audit`) → SBOM (`cargo cyclonedx`) → build provenance.
- **`CODEOWNERS`**, **`BRANCH-PROTECTION.md`** → governance companions.
- **Container image supply-chain (this profile ships a service):** the reference `ci.yml` adds `gate-image-sbom` (Syft/CycloneDX, on PR) and `gate-image-provenance` (digest-bound, push-only) on top of the 8 universal gate-ids. Verified by `conformance/container-supply-chain.sh`.

Conformance: `sh conformance/ci-gates.sh profiles/rust/ci.yml`. Note: `gate-type-check`=`cargo check`, `gate-build`=`cargo build --release`.

## 5. Security implementation
- **Env/secrets:** `std::env`/`envy` into a config struct with fail-fast; `.env` gitignored; commit `.env.example`.
- **Validation:** `validator` crate on request structs at boundaries; validate create *and* update.
- **Injection-safe data:** **sqlx** (compile-time-checked, parameterized) or `diesel`; never format SQL strings.
- **AuthN/Z:** `argon2` (or `bcrypt`) password hashing; `jsonwebtoken` minimal claims + short expiry; extractor/middleware authorization.
- **HTTP headers / CSRF:** `tower-http` `SetResponseHeaderLayer` / security middleware; CSRF for cookie auth.
- **Rate limiting:** `tower_governor` (relax in test config).
- **Static analysis & licenses (conditional gates — `docs/operations/security-scanning.md`):** SAST via **Semgrep + `cargo-auditable`/clippy security lints** (`gate-sast`); license policy via `scripts/license-check.sh` over the CycloneDX SBOM (`gate-license`, stack-neutral default — upgrade per the ladder if needed).

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
- **Container (service):** build the multi-stage non-root image (`profiles/rust/Dockerfile`, distroless `cc` base for glibc-linked binaries — switch to `static` for a musl target), run locally via `compose.yaml` (dev/prod parity). CI scans the image SBOM on every PR (`gate-image-sbom`) and, on merge to `main`, pushes to GHCR and attests **provenance bound to the image digest** (`gate-image-provenance`). Deploy the **attested digest** via `deploy/k8s/` or the Helm chart in `deploy/helm/`. Promote the same digest Dev → QA → UAT → Prod; rollback = redeploy the previous digest. (No devcontainer shipped — distroless has no shell; add one against `rust:1` if desired.)
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

---

**Last Updated:** 2026-06-06
