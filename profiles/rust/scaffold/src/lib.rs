//! Library crate for the dependency-free (std-only) reference service.
//!
//! The spine restructure: the app is a `lib` (this crate) + a thin `bin`
//! (`src/main.rs`). Everything testable — the flag seam, the live file provider, the
//! telemetry primitives, the pure request handler, and the socket serve loop — lives
//! here so the integration/e2e suites (`tests/`) can drive the REAL server over an
//! ephemeral port through the public API. `main` only binds the listener and hands
//! off to [`server::run`].
//!
//! Mirrors the go reference (health.go + server.go in `package main`) and the python
//! reference (`src/app/{flags,live_provider,telemetry,server}.py`), kept std-only —
//! no tokio/axum, no serde — so the profile stays dependency-free.

pub mod flags;
pub mod health;
pub mod live_provider;
pub mod server;
pub mod telemetry;
