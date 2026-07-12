//! Dependency-free (std-only) starter service.
//!
//! `route()` models the `/healthz` response as a pure function so it is unit-tested
//! without binding a socket — which also keeps line coverage high (only the one-line
//! `main` is uncovered). Swap `main` for a real HTTP server (e.g. `axum`/`tokio`, or a
//! `std::net::TcpListener` loop calling `route`) to expose it over HTTP — see README.

/// Health payload as a JSON string. Pure and directly testable.
fn health() -> &'static str {
    "{\"status\":\"ok\"}"
}

/// Route a request to `(status, body)`. Pure: no I/O, fully testable.
fn route(method: &str, path: &str) -> (u16, String) {
    match (method, path) {
        ("GET", "/healthz") => (200, health().to_string()),
        _ => (404, "{\"error\":\"not found\"}".to_string()),
    }
}

fn main() {
    println!("{}", route("GET", "/healthz").1);
}

#[cfg(test)]
mod tests {
    use super::{health, route};

    #[test]
    fn health_is_ok() {
        assert_eq!(health(), "{\"status\":\"ok\"}");
    }

    #[test]
    fn healthz_route_returns_200() {
        let (status, body) = route("GET", "/healthz");
        assert_eq!(status, 200);
        assert_eq!(body, "{\"status\":\"ok\"}");
    }

    #[test]
    fn unknown_route_returns_404() {
        let (status, _body) = route("POST", "/nope");
        assert_eq!(status, 404);
    }
}
