//! Pure health core (Rust profile).
//!
//! Holds ONLY the pure health payload; the routing, security middleware,
//! per-request telemetry, and socket-binding boot live in [`crate::server`] (the ONE
//! place the profile assembles the flags + telemetry modules into a running server).
//! Keeping [`health`] pure (no I/O) makes it directly unit-testable and lets both the
//! `/healthz` route and any container HEALTHCHECK probe share one source of truth for
//! the exact body. Mirrors the go reference's `Health()` and python's health payload.

/// The service health payload as a compact JSON string. Pure — no I/O — so it is
/// directly testable and is the single source of truth for the `/healthz` body.
#[must_use]
pub fn health() -> &'static str {
    "{\"status\":\"ok\"}"
}

#[cfg(test)]
mod tests {
    use super::health;

    #[test]
    fn health_is_ok() {
        assert_eq!(health(), "{\"status\":\"ok\"}");
    }
}
