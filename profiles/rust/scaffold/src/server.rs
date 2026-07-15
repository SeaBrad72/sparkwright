//! App server spine — wires the flags + telemetry modules into a running HTTP server.
//!
//! The fuller counterpart to [`crate::health`]: a std-only (no tokio/axum) server on a
//! `std::net::TcpListener` that serves the real endpoints (`/healthz`, `/metrics`,
//! `/greeting`, 404), stamps the security-header baseline on EVERY response, and emits
//! per-request telemetry (a structured log, a bounded-cardinality metric, and an
//! OTel-semantic span). Mirrors the go reference `server.go` and the python reference
//! `src/app/server.py`.
//!
//! [`health`] is called (not re-implemented); the flag seam and the telemetry
//! primitives are wired here — the ONE place the profile assembles them. [`handle`] is
//! a PURE request handler (method, path, headers -> [`Response`]) covered by unit tests;
//! the socket boot ([`serve`]/[`run`]) is covered by the integration + e2e suites, which
//! drive a real server on an ephemeral port. `main` stays thin, exactly like the python
//! reference's `serve()`/`__main__`.
//!
//! Security posture (all inbound is bounded):
//!   - security headers + a neutral `Server: reference-app` are stamped in ONE place, so
//!     even a 404 / non-GET carries them exactly once and no interpreter/version leaks;
//!   - an inbound `X-Request-Id` is honoured only when it matches a safe token
//!     (`^[A-Za-z0-9._-]{1,128}$`) — otherwise a fresh random id is minted, so an
//!     unbounded/hostile header never flows verbatim into a log/span;
//!   - the request head is size-capped ([`MAX_HEADER_BYTES`]) and read under a timeout
//!     ([`READ_TIMEOUT`]) — a slow-loris / oversized-header client is dropped; the body
//!     is never read (no unbounded read).

use std::collections::BTreeMap;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use crate::flags;
use crate::health::health;
use crate::live_provider::FileConfigProvider;
use crate::telemetry::{self, LogValue};

/// The four security headers stamped on EVERY response — a hardened baseline for a
/// JSON/text API that serves no markup: block sniffing/framing, deny all subresources,
/// leak no referrer.
pub const SECURITY_HEADERS: &[(&str, &str)] = &[
    ("X-Content-Type-Options", "nosniff"),
    ("X-Frame-Options", "DENY"),
    ("Content-Security-Policy", "default-src 'none'"),
    ("Referrer-Policy", "no-referrer"),
];

/// The neutral `Server` header value — no interpreter/library version disclosure.
const SERVER_NAME: &str = "reference-app";

/// The compact 404 body (a fixed constant).
const NOT_FOUND_BODY: &str = "{\"error\":\"not found\"}";

/// Byte cap on the request head (1 MiB). Bounds an oversized-header client; the body is
/// never read at all.
const MAX_HEADER_BYTES: usize = 1 << 20;

/// Read/write timeout — the slow-loris guard (a client that dribbles bytes is dropped).
const READ_TIMEOUT: Duration = Duration::from_secs(15);

/// A fully-formed HTTP response: status, ordered headers (security baseline + neutral
/// `Server` + `Content-Type` + `Content-Length` + `Connection`), and the body bytes to
/// write (empty for a HEAD request).
pub struct Response {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
}

/// A parsed request head: `(method, path, headers)`. Aliased so the reader/parser
/// signatures stay readable (and clippy-clean).
type ParsedRequest = (String, String, Vec<(String, String)>);

/// Routes `(method, path)` to `(status, content_type, body)`. Only GET is routed; every
/// other method (incl. HEAD) falls through to a hardened JSON 404 (method-agnostic,
/// mirroring the reference) so it too carries security headers + telemetry.
fn dispatch(method: &str, path: &str) -> (u16, &'static str, String) {
    if method != "GET" {
        return (404, "application/json", NOT_FOUND_BODY.to_string());
    }
    match path {
        "/healthz" => (200, "application/json", health().to_string()),
        "/metrics" => (
            200,
            "text/plain; version=0.0.4",
            telemetry::render_metrics(),
        ),
        "/greeting" => {
            let greeting = if flags::is_enabled("new_greeting") {
                "Hello, world! (new)"
            } else {
                "Hello, world!"
            };
            (
                200,
                "application/json",
                format!("{{\"greeting\":\"{greeting}\"}}"),
            )
        }
        _ => (404, "application/json", NOT_FOUND_BODY.to_string()),
    }
}

/// True when `raw` is a safe request-id token: 1-128 chars of `[A-Za-z0-9._-]`. A
/// hand-rolled check (this profile is dependency-free — no `regex` crate) equivalent to
/// the reference's `^[A-Za-z0-9._-]{1,128}$`.
fn valid_request_id(raw: &str) -> bool {
    (1..=128).contains(&raw.len())
        && raw
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'-'))
}

/// Returns a validated inbound `X-Request-Id`, or a freshly minted random id (32 hex
/// chars, from the telemetry crypto source — NO uuid dependency). Header lookup is
/// case-insensitive per RFC 7230.
fn request_id(headers: &[(String, String)]) -> String {
    if let Some((_, value)) = headers
        .iter()
        .find(|(name, _)| name.eq_ignore_ascii_case("x-request-id"))
    {
        if valid_request_id(value) {
            return value.clone();
        }
    }
    // trace-id shape: 16 random bytes -> 32 hex chars (matches the reference's mint).
    telemetry::new_span_ids().0
}

/// The PURE request handler: route + assemble the [`Response`] (security headers, neutral
/// `Server`, `Content-Type`, `Content-Length`) + emit per-request telemetry. No socket
/// I/O, so it is unit-tested directly. A HEAD request gets the 404 status + headers with
/// an EMPTY body (HEAD semantics). `path` may carry a query string — it is stripped for
/// routing and the span name (cardinality + secret hygiene) but logged in full.
#[must_use]
pub fn handle(method: &str, path: &str, headers: &[(String, String)]) -> Response {
    let start_wall = SystemTime::now();
    let start_instant = Instant::now();
    let req_id = request_id(headers);

    let route_path = path.split('?').next().unwrap_or(path);
    let (status, content_type, full_body) = dispatch(method, route_path);

    // HEAD carries the status + headers but no body.
    let with_body = method != "HEAD";
    let body: Vec<u8> = if with_body {
        full_body.into_bytes()
    } else {
        Vec::new()
    };

    let mut out_headers: Vec<(String, String)> = Vec::with_capacity(SECURITY_HEADERS.len() + 4);
    for (name, value) in SECURITY_HEADERS {
        out_headers.push(((*name).to_string(), (*value).to_string()));
    }
    out_headers.push(("Server".to_string(), SERVER_NAME.to_string()));
    out_headers.push(("Content-Type".to_string(), content_type.to_string()));
    out_headers.push(("Content-Length".to_string(), body.len().to_string()));
    out_headers.push(("Connection".to_string(), "close".to_string()));

    // Per-request telemetry, emitted AFTER the response is assembled (mirrors the
    // reference's post-write instrumentation).
    let elapsed = start_instant.elapsed();
    let latency_ms = elapsed.as_secs_f64() * 1000.0;
    let start_nano = i64::try_from(
        start_wall
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos(),
    )
    .unwrap_or(0);
    let end_nano = start_nano.saturating_add(i64::try_from(elapsed.as_nanos()).unwrap_or(0));
    let span_name = format!("{method} {route_path}");

    telemetry::log(&[
        ("request_id", LogValue::from(req_id.as_str())),
        ("method", LogValue::from(method)),
        ("path", LogValue::from(path)),
        ("status", LogValue::from(status)),
        ("latency_ms", LogValue::from(latency_ms)),
    ]);
    telemetry::record_metric(method, status, latency_ms);
    let mut attrs = BTreeMap::new();
    attrs.insert("http.request.method".to_string(), method.to_string());
    attrs.insert("http.response.status_code".to_string(), status.to_string());
    attrs.insert("request_id".to_string(), req_id);
    telemetry::emit_span(&telemetry::build_span(
        &span_name, start_nano, end_nano, attrs, status,
    ));

    Response {
        status,
        headers: out_headers,
        body,
    }
}

/// The FLAG_FILE boot gate (the load-bearing live-flip wiring): when `FLAG_FILE` is set
/// the file-config live provider is installed BEFORE listening, so the running server's
/// `/greeting` reflects live file flips with no restart. Unset -> the env floor
/// (restart-to-toggle) stays active. Operator-controlled — an unset var fails safe.
pub fn install_providers() {
    match std::env::var("FLAG_FILE") {
        Ok(path) if !path.is_empty() => {
            flags::set_provider(Box::new(FileConfigProvider::new(path)));
        }
        _ => flags::reset_provider(),
    }
}

/// Reads `PORT` (default `8080`) — the single source of truth for the listen/probe port,
/// shared by [`run`] and [`health_check`] so the container HEALTHCHECK targets the exact
/// port the server binds.
#[must_use]
pub fn resolve_port() -> String {
    std::env::var("PORT")
        .ok()
        .filter(|p| !p.is_empty())
        .unwrap_or_else(|| "8080".to_string())
}

/// The container HEALTHCHECK self-probe: opens a TCP connection to `addr`
/// (`127.0.0.1:$PORT`), issues a minimal HTTP/1.0 `GET /healthz`, and returns a process
/// exit code — `0` when the endpoint answers `200` with the exact [`health`] body, else
/// `1`. Std-only (no reqwest/curl): distroless has no shell, so the self-check is a flag
/// on the binary (see `main`). Any failure (connect/write/read/timeout, non-200, or a
/// mismatched body) maps to `1` — the probe fails safe. Mirrors the go reference's
/// `healthCheck`.
#[must_use]
pub fn health_check(addr: &str) -> i32 {
    match probe_healthz(addr) {
        Ok(true) => 0,
        _ => 1,
    }
}

/// Performs the raw HTTP/1.0 `GET /healthz` and reports whether it was `200` with the
/// exact [`health`] body. `Err` on any socket failure; `Ok(false)` on a reachable server
/// that answered wrong. Bounded: a 5s connect/read timeout (never hangs the probe) and a
/// capped read (a health body is a handful of bytes — never slurp an unbounded stream).
fn probe_healthz(addr: &str) -> std::io::Result<bool> {
    let target: std::net::SocketAddr = addr
        .parse()
        .map_err(|_| std::io::Error::new(std::io::ErrorKind::InvalidInput, "bad addr"))?;
    let mut stream = TcpStream::connect_timeout(&target, Duration::from_secs(5))?;
    stream.set_read_timeout(Some(Duration::from_secs(5)))?;
    stream.set_write_timeout(Some(Duration::from_secs(5)))?;
    // HTTP/1.0 + Connection: close -> the server closes after the body, so read_to_end
    // gets the whole response then EOF (no chunked/keep-alive parsing needed).
    let host = addr.rsplit_once(':').map_or(addr, |(h, _)| h);
    let request = format!("GET /healthz HTTP/1.0\r\nHost: {host}\r\nConnection: close\r\n\r\n");
    stream.write_all(request.as_bytes())?;
    stream.flush()?;

    let mut raw = Vec::new();
    // 8 KiB cap: the health response (status line + a few headers + tiny body) is far
    // smaller; bounding the read defends against a hostile/oversized reply.
    stream.take(8192).read_to_end(&mut raw)?;
    let text = String::from_utf8_lossy(&raw);
    let Some((head, body)) = text.split_once("\r\n\r\n") else {
        return Ok(false);
    };
    let status_ok = head
        .lines()
        .next()
        .is_some_and(|line| line.split_whitespace().nth(1) == Some("200"));
    Ok(status_ok && body == health())
}

/// Binds `0.0.0.0:$PORT` (default 8080) and serves forever. The thin boot the `bin`
/// entry calls — `0.0.0.0` so a container can serve it.
///
/// Plain HTTP is intentional: a starter service runs behind a TLS-terminating
/// ingress/load balancer (the kit's k8s deploy model), so the process serves cleartext
/// on the cluster network. Terminate TLS at the edge if this is internet-facing.
pub fn run() {
    install_providers();
    // Resolve the greeting flag at startup — proves the kill-switch is wired before the
    // service accepts traffic.
    let _new_greeting = flags::is_enabled("new_greeting");
    let addr = format!("0.0.0.0:{}", resolve_port());
    let listener = TcpListener::bind(&addr)
        .unwrap_or_else(|err| panic!("server: failed to bind {addr}: {err}"));
    telemetry::log(&[
        ("event", LogValue::from("listening")),
        ("addr", LogValue::from(addr.as_str())),
    ]);
    serve(&listener);
}

/// Accept loop: one detached thread per connection so a slow/hanging client cannot block
/// others. Bound to the same handler the tests drive, so the integration/e2e suites
/// exercise this exact path over an ephemeral port. Runs until the listener is dropped.
pub fn serve(listener: &TcpListener) {
    for stream in listener.incoming() {
        match stream {
            Ok(stream) => {
                std::thread::spawn(move || {
                    let _ = handle_connection(stream);
                });
            }
            Err(_) => continue,
        }
    }
}

/// Reads one request head off `stream` (bounded + timed), dispatches through [`handle`],
/// and writes the response. Non-panicking — a malformed/oversized/slow request is
/// dropped (the connection closes) rather than taking a worker down.
fn handle_connection(mut stream: TcpStream) -> std::io::Result<()> {
    stream.set_read_timeout(Some(READ_TIMEOUT))?;
    stream.set_write_timeout(Some(READ_TIMEOUT))?;
    let Some((method, path, headers)) = read_request(&mut stream)? else {
        return Ok(()); // malformed / empty / oversized head -> drop
    };
    let response = handle(&method, &path, &headers);
    write_response(&mut stream, &response)?;
    stream.flush()
}

/// Reads bytes until the end-of-head `\r\n\r\n`, capped at [`MAX_HEADER_BYTES`] and
/// bounded by the read timeout. The body is NEVER read. Returns `None` on EOF before a
/// complete head, an oversized head, or a malformed request line.
fn read_request(stream: &mut TcpStream) -> std::io::Result<Option<ParsedRequest>> {
    let mut buf = Vec::new();
    let mut chunk = [0u8; 4096];
    loop {
        let n = stream.read(&mut chunk)?;
        if n == 0 {
            return Ok(None); // connection closed before a complete head
        }
        buf.extend_from_slice(&chunk[..n]);
        if let Some(pos) = find_head_end(&buf) {
            return Ok(parse_request(&buf[..pos]));
        }
        if buf.len() > MAX_HEADER_BYTES {
            return Ok(None); // oversized head -> drop
        }
    }
}

/// Returns the index just past the `\r\n\r\n` head terminator, or `None`.
fn find_head_end(buf: &[u8]) -> Option<usize> {
    buf.windows(4)
        .position(|window| window == b"\r\n\r\n")
        .map(|pos| pos + 4)
}

/// Parses a request head (`METHOD PATH HTTP/x`, then `Name: value` lines). Returns `None`
/// on non-UTF-8 or a malformed request line. The HTTP version is ignored.
fn parse_request(bytes: &[u8]) -> Option<ParsedRequest> {
    let text = std::str::from_utf8(bytes).ok()?;
    let mut lines = text.split("\r\n");
    let request_line = lines.next()?;
    let mut parts = request_line.split(' ');
    let method = parts.next()?.to_string();
    let path = parts.next()?.to_string();
    if method.is_empty() || path.is_empty() {
        return None;
    }
    let mut headers = Vec::new();
    for line in lines {
        if line.is_empty() {
            continue;
        }
        if let Some((name, value)) = line.split_once(':') {
            headers.push((name.trim().to_string(), value.trim().to_string()));
        }
    }
    Some((method, path, headers))
}

/// The reason phrase for a status (generic — never leaks framework internals).
fn status_text(status: u16) -> &'static str {
    match status {
        200 => "OK",
        404 => "Not Found",
        _ => "OK",
    }
}

/// Writes the status line, headers, and body bytes to `stream`.
fn write_response(stream: &mut TcpStream, response: &Response) -> std::io::Result<()> {
    let mut head = format!(
        "HTTP/1.1 {} {}\r\n",
        response.status,
        status_text(response.status)
    );
    for (name, value) in &response.headers {
        head.push_str(&format!("{name}: {value}\r\n"));
    }
    head.push_str("\r\n");
    stream.write_all(head.as_bytes())?;
    stream.write_all(&response.body)?;
    Ok(())
}

// NOTE: the unit tests below deliberately cover only the PURE, non-emitting,
// flag-independent helpers (dispatch of flag-agnostic routes, request-id validation,
// the request parser, status text). `handle()` emits telemetry and `dispatch("/greeting")`
// reads the GLOBAL flag provider — both are process-global state that would race with the
// `flags`/`telemetry` module tests sharing this SAME test binary. Those behaviours
// (security headers exactly once, non-GET 404, HEAD empty body, the live flag flip, the
// request-id span echo) are covered end-to-end in `tests/integration.rs`, which runs in a
// SEPARATE test binary/process under a single serialization guard — no cross-module race.
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dispatch_healthz_ok() {
        let (status, ctype, body) = dispatch("GET", "/healthz");
        assert_eq!(status, 200);
        assert_eq!(ctype, "application/json");
        assert_eq!(body, "{\"status\":\"ok\"}");
    }

    #[test]
    fn dispatch_metrics_is_prometheus_text() {
        let (status, ctype, body) = dispatch("GET", "/metrics");
        assert_eq!(status, 200);
        assert!(ctype.starts_with("text/plain"));
        assert!(body.contains("http_requests_total"));
    }

    #[test]
    fn dispatch_unknown_is_404() {
        let (status, ctype, body) = dispatch("GET", "/nope");
        assert_eq!(status, 404);
        assert_eq!(ctype, "application/json");
        assert_eq!(body, "{\"error\":\"not found\"}");
    }

    #[test]
    fn dispatch_non_get_is_404() {
        for method in ["POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD"] {
            let (status, _, body) = dispatch(method, "/healthz");
            assert_eq!(status, 404, "method {method}");
            assert_eq!(body, "{\"error\":\"not found\"}");
        }
    }

    #[test]
    fn valid_request_id_charset_and_length() {
        assert!(valid_request_id("abc-123_valid.ID"));
        assert!(valid_request_id("A"));
        assert!(valid_request_id(&"x".repeat(128)));
        assert!(!valid_request_id("")); // empty
        assert!(!valid_request_id(&"x".repeat(129))); // too long
        assert!(!valid_request_id("has space"));
        assert!(!valid_request_id("bad/slash"));
        assert!(!valid_request_id("semi;colon"));
    }

    #[test]
    fn request_id_honours_valid_inbound() {
        let headers = vec![("X-Request-Id".to_string(), "abc-123_valid.ID".to_string())];
        assert_eq!(request_id(&headers), "abc-123_valid.ID");
    }

    #[test]
    fn request_id_is_case_insensitive_on_header_name() {
        let headers = vec![("x-request-id".to_string(), "lower.header".to_string())];
        assert_eq!(request_id(&headers), "lower.header");
    }

    #[test]
    fn request_id_replaces_oversized_inbound_with_32_hex() {
        let headers = vec![("X-Request-Id".to_string(), "x".repeat(200))];
        let minted = request_id(&headers);
        assert_ne!(minted, "x".repeat(200));
        assert_eq!(minted.len(), 32);
        assert!(minted.chars().all(|c| c.is_ascii_hexdigit()));
    }

    #[test]
    fn request_id_mints_when_absent() {
        let minted = request_id(&[]);
        assert_eq!(minted.len(), 32);
    }

    #[test]
    fn find_head_end_locates_terminator() {
        assert_eq!(find_head_end(b"GET / HTTP/1.1\r\n\r\n"), Some(18));
        assert_eq!(find_head_end(b"incomplete\r\n"), None);
    }

    #[test]
    fn parse_request_extracts_line_and_headers() {
        let raw = b"GET /greeting?x=1 HTTP/1.1\r\nHost: localhost\r\nX-Request-Id: abc\r\n\r\n";
        let (method, path, headers) = parse_request(raw).unwrap();
        assert_eq!(method, "GET");
        assert_eq!(path, "/greeting?x=1");
        assert!(headers
            .iter()
            .any(|(k, v)| k == "X-Request-Id" && v == "abc"));
    }

    #[test]
    fn parse_request_rejects_malformed_line() {
        assert!(parse_request(b"GET\r\n\r\n").is_none()); // no path
        assert!(parse_request(b"\r\n\r\n").is_none()); // empty request line
    }

    #[test]
    fn status_text_is_generic() {
        assert_eq!(status_text(200), "OK");
        assert_eq!(status_text(404), "Not Found");
        assert_eq!(status_text(503), "OK");
    }
}
