//! Thin socket-binding entry — all logic lives in the `app` library (`src/lib.rs`).
//!
//! The spine restructure splits the profile into a `lib` (the flag seam, live provider,
//! telemetry primitives, pure request handler, and serve loop — all testable via the
//! public API) + this thin `bin`. `main` binds the listener and hands off to
//! [`app::server::run`]; the integration/e2e suites drive the real server over an
//! ephemeral port, so this line is the only largely-uncovered code (matching the go /
//! python references' thin boot).
//!
//! With `--healthcheck` it does NOT start the server — it probes the running server's
//! `/healthz` on `127.0.0.1:$PORT` and exits `0`/`1`. This is the container HEALTHCHECK
//! path: distroless has no shell/curl, so the self-check is a flag on the binary
//! (matching the Dockerfile's `HEALTHCHECK ... ["/app/server", "--healthcheck"]` and the
//! go reference's `-healthcheck`).

fn main() {
    if std::env::args().skip(1).any(|arg| arg == "--healthcheck") {
        let addr = format!("127.0.0.1:{}", app::server::resolve_port());
        std::process::exit(app::server::health_check(&addr));
    }
    app::server::run();
}
