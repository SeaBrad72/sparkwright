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
- **Format/lint:** `cargo fmt` + `cargo clippy` · **Types:** the compiler (`cargo check`)
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

---

**Last Updated:** 2026-06-06
