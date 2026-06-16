# app — Rust starter scaffold

A minimal, **dependency-free** Rust binary that satisfies the Rust profile's CI language
pipeline (`profiles/rust/ci.yml`) on an empty repo, plus a `/healthz` response modeled as a
pure, tested function.

> Incept-copied starter — **brownfield-safe**: `incept` copies these files into a fresh repo only.

## Std-only → clone-green by construction

Uses only the Rust standard library, so `[dependencies]` is empty and the committed `Cargo.lock`
holds just the root package — `cargo fetch` is a no-op and there is **no lockfile to keep in sync**.

## Layout

| File          | Role                                                                     |
|---------------|--------------------------------------------------------------------------|
| `Cargo.toml`  | `name = "app"`, edition 2021, no dependencies.                           |
| `Cargo.lock`  | trivial (zero-dep) lockfile.                                             |
| `src/main.rs` | pure `health()` + `route()` (the `/healthz` logic) + tests; thin `main`. |

## Commands (match `profiles/rust/ci.yml`)

```sh
cargo fetch                                  # no-op (no deps)
cargo clippy --all-targets -- -D warnings    # gate-lint (must be warning-free)
cargo check --all-targets                    # gate-type-check
cargo install cargo-llvm-cov                 # (CI installs the coverage tool)
cargo llvm-cov --fail-under-lines 80         # gate-test (>=80% line coverage)
cargo build --release                        # gate-build
```

`route()` and `health()` are fully exercised by the three tests; only the one-line `main` is
uncovered, so line coverage clears 80%.

## Growing it into an HTTP service

`main` currently prints the `/healthz` body. For a real HTTP surface, replace it with a
`std::net::TcpListener` loop (or add `axum`/`tokio`) that calls `route(method, path)` — the routing
logic is already factored out and tested.

## Verification status

> **Authored to the `profiles/rust/ci.yml` contract; std-only and written clippy-clean by
> construction, but not executed here (cargo toolchain absent). Verify with
> `cargo clippy -- -D warnings && cargo llvm-cov --fail-under-lines 80` in an adopter env.**
