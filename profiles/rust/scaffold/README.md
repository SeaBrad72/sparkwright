# app — Rust starter scaffold

A minimal, **dependency-free** Rust service that satisfies the Rust profile's CI language
pipeline (`profiles/rust/ci.yml`) on an empty repo: a std-only HTTP server (`std::net::TcpListener`,
no tokio/axum) exposing `/healthz`, `/greeting` (feature-flag gated), and `/metrics`, with a
pluggable flag-provider seam, per-request telemetry, and a hardened security-header baseline.

> Incept-copied starter — **brownfield-safe**: `incept` copies these files into a fresh repo only.

## Std-only → clone-green by construction

Uses only the Rust standard library, so `[dependencies]` is empty and the committed `Cargo.lock`
holds just the root package — `cargo fetch` is a no-op and there is **no lockfile to keep in sync**.

## Layout

The profile is split into a **library** (`src/lib.rs`, crate `app`) + a **thin binary**
(`src/main.rs`), so the integration/e2e suites drive the REAL server over an ephemeral port
through the public API.

| File                  | Role                                                                          |
|-----------------------|-------------------------------------------------------------------------------|
| `Cargo.toml`          | `name = "app"`, edition 2021, no dependencies.                                |
| `Cargo.lock`          | trivial (zero-dep) lockfile.                                                  |
| `src/lib.rs`          | library crate root — re-exports the modules below.                           |
| `src/flags.rs`        | typed flag registry + provider SEAM (default OFF, strict env floor).          |
| `src/live_provider.rs`| reference LIVE file-config provider (flips a flag with **no restart**).       |
| `src/telemetry.rs`    | pure spans / bounded-cardinality metrics / structured logs.                  |
| `src/health.rs`       | pure `health()` — the `/healthz` payload.                                     |
| `src/server.rs`       | the spine: pure `handle()` router + security headers + telemetry + `serve()`. |
| `src/main.rs`         | thin `bin` — binds `0.0.0.0:$PORT` and calls `app::server::run()`.            |
| `tests/integration.rs`| flag seam + telemetry THROUGH a running server (incl. the live-flip proof).   |
| `tests/e2e.rs`        | full journey: liveness → greeting → 404.                                      |

## Commands (match `profiles/rust/ci.yml`)

```sh
cargo fetch                                  # no-op (no deps)
cargo clippy --all-targets -- -D warnings    # gate-lint (must be warning-free)
cargo check --all-targets                    # gate-type-check
cargo install cargo-llvm-cov                 # (CI installs the coverage tool)
cargo llvm-cov --fail-under-lines 80         # gate-test (>=80% line coverage)
cargo build --release                        # gate-build
```

The pure `handle()`/`dispatch()` router, the flag seam, and the telemetry primitives are exercised
by the unit tests; the socket path (`serve`/`read_request`/`write_response`) and the live flag flip
are exercised by `tests/integration.rs` + `tests/e2e.rs` against a real server on an ephemeral port.
Only the thin `main` boot is uncovered, so line coverage clears 80%.

## Endpoints

| Route       | Response                                                                        |
|-------------|---------------------------------------------------------------------------------|
| `/healthz`  | `200 {"status":"ok"}`                                                            |
| `/greeting` | `200 {"greeting":"Hello, world!"}` — or `… (new)` when flag `new_greeting` is ON |
| `/metrics`  | `200` Prometheus text exposition                                                |
| *(other)*   | `404 {"error":"not found"}` (any non-GET method also 404s)                       |

Every response carries four security headers (`X-Content-Type-Options`, `X-Frame-Options`,
`Content-Security-Policy`, `Referrer-Policy`) plus a neutral `Server: reference-app`. The flag is
resolved through the provider seam: the env floor (`FEATURE_NEW_GREETING=true`, restart-to-toggle)
by default, or the live file-config provider when `FLAG_FILE` is set (flips with no restart).

## Growing it into a production service

The spine is std-only by design (dependency-free). For a higher-throughput surface, swap the
`serve()` accept loop for `axum`/`tokio` while keeping the pure `handle()` contract — the routing,
flag seam, and telemetry are already factored out and tested.

## Verification status

> **Authored to the `profiles/rust/ci.yml` contract; std-only and written clippy-clean by
> construction, but not executed here (cargo toolchain absent). Verify with
> `cargo clippy -- -D warnings && cargo llvm-cov --fail-under-lines 80` in an adopter env.**
