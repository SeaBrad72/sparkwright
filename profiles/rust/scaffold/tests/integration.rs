//! Integration: the flag seam + telemetry wiring THROUGH the running server.
//!
//! Unlike the unit tests (dispatch/handle in isolation), here the flag registry, the
//! assembled handler, and the real HTTP layer are exercised together against a server
//! bound to an ephemeral port in the SAME process — so the coverage tool measures
//! `server.rs`'s socket path (read_request/parse_request/write_response/serve). Mirrors
//! the go reference `integration_test.go` and python `tests/integration/`.
//!
//! The live-flip case is the ★ load-bearing proof that the provider seam reaches the
//! REAL endpoint on the RUNNING server with NO restart — the whole point of the seam.
//!
//! Std-only: this profile is dependency-free, so the HTTP client is hand-rolled over
//! `TcpStream` (no reqwest/hyper) and the server sends `Connection: close` so a plain
//! `read_to_end` gets the whole response then EOF.

use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use std::time::Duration;

// Serializes tests that touch process-global state (the flag provider slot, the
// telemetry metric counters, the OTEL_TRACE_FILE / FEATURE_NEW_GREETING env vars) —
// cargo runs the tests in a binary multi-threaded by default.
static GUARD: Mutex<()> = Mutex::new(());
static COUNTER: AtomicU64 = AtomicU64::new(0);

fn lock() -> std::sync::MutexGuard<'static, ()> {
    GUARD.lock().unwrap_or_else(|e| e.into_inner())
}

/// The four security headers stamped on EVERY response.
const EXPECTED_SECURITY_HEADERS: &[(&str, &str)] = &[
    ("X-Content-Type-Options", "nosniff"),
    ("X-Frame-Options", "DENY"),
    ("Content-Security-Policy", "default-src 'none'"),
    ("Referrer-Policy", "no-referrer"),
];

/// Binds an ephemeral port and serves the assembled handler on a detached thread.
/// Returns the `host:port` to connect to. The listener stays owned by the thread for
/// the life of the process (harmless — every test uses a fresh port).
fn start_server() -> String {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind ephemeral port");
    let port = listener.local_addr().unwrap().port();
    std::thread::spawn(move || app::server::serve(&listener));
    format!("127.0.0.1:{port}")
}

/// A unique temp dir per test (avoids cross-test file collisions).
fn temp_dir() -> PathBuf {
    let unique = COUNTER.fetch_add(1, Ordering::Relaxed);
    let dir = std::env::temp_dir().join(format!("sp_rust_it_{}_{}", std::process::id(), unique));
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// Performs a raw HTTP/1.1 request and returns `(status, headers, body)`.
fn http_request(
    addr: &str,
    method: &str,
    path: &str,
    extra: &[(&str, &str)],
) -> (u16, Vec<(String, String)>, String) {
    let mut stream = TcpStream::connect(addr).expect("connect to test server");
    stream
        .set_read_timeout(Some(Duration::from_secs(5)))
        .unwrap();
    let mut req = format!("{method} {path} HTTP/1.1\r\nHost: {addr}\r\n");
    for (name, value) in extra {
        req.push_str(&format!("{name}: {value}\r\n"));
    }
    req.push_str("Connection: close\r\n\r\n");
    stream.write_all(req.as_bytes()).unwrap();
    let mut raw = Vec::new();
    stream.read_to_end(&mut raw).unwrap();
    parse_response(&raw)
}

/// Parses a raw HTTP response into `(status, headers, body)`.
fn parse_response(raw: &[u8]) -> (u16, Vec<(String, String)>, String) {
    let text = String::from_utf8_lossy(raw);
    let sep = text
        .find("\r\n\r\n")
        .expect("response missing head terminator");
    let head = &text[..sep];
    let body = text[sep + 4..].to_string();
    let mut lines = head.split("\r\n");
    let status_line = lines.next().unwrap();
    let status: u16 = status_line
        .split(' ')
        .nth(1)
        .and_then(|code| code.parse().ok())
        .expect("status code");
    let mut headers = Vec::new();
    for line in lines {
        if let Some((name, value)) = line.split_once(':') {
            headers.push((name.trim().to_string(), value.trim().to_string()));
        }
    }
    (status, headers, body)
}

/// All values for a (case-insensitive) header name — proves "exactly once".
fn header_values<'a>(headers: &'a [(String, String)], name: &str) -> Vec<&'a str> {
    headers
        .iter()
        .filter(|(key, _)| key.eq_ignore_ascii_case(name))
        .map(|(_, value)| value.as_str())
        .collect()
}

fn assert_security_headers(headers: &[(String, String)], context: &str) {
    for (name, value) in EXPECTED_SECURITY_HEADERS {
        let got = header_values(headers, name);
        assert_eq!(
            got,
            vec![*value],
            "{context}: header {name} not exactly once"
        );
    }
    assert_eq!(
        header_values(headers, "Server"),
        vec!["reference-app"],
        "{context}: Server header must be neutral (no version leak)"
    );
}

/// Reads a trace file, retrying briefly (the span is emitted on the server thread).
fn read_trace(path: &Path) -> String {
    for _ in 0..200 {
        if let Ok(contents) = std::fs::read_to_string(path) {
            if !contents.is_empty() {
                return contents;
            }
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    panic!("no span was written to the trace file within the timeout");
}

/// Extracts the last `request_id` attribute value from a trace file's spans.
fn last_span_request_id(trace: &str) -> String {
    let marker = "\"request_id\":\"";
    let start = trace.rfind(marker).expect("span has request_id") + marker.len();
    let rest = &trace[start..];
    let end = rest.find('"').expect("terminated request_id");
    rest[..end].to_string()
}

#[test]
fn integration_greeting_flag_off_serves_default() {
    let _g = lock();
    app::flags::reset_provider();
    std::env::remove_var("FEATURE_NEW_GREETING");
    let addr = start_server();
    let (status, headers, body) = http_request(&addr, "GET", "/greeting", &[]);
    assert_eq!(status, 200);
    assert_eq!(
        header_values(&headers, "Content-Type"),
        vec!["application/json"]
    );
    assert_eq!(body, r#"{"greeting":"Hello, world!"}"#);
}

#[test]
fn integration_greeting_flag_on_serves_new() {
    let _g = lock();
    std::env::set_var("FEATURE_NEW_GREETING", "true");
    app::flags::reset_provider();
    let addr = start_server();
    let (status, _, body) = http_request(&addr, "GET", "/greeting", &[]);
    assert_eq!(status, 200);
    assert_eq!(body, r#"{"greeting":"Hello, world! (new)"}"#);
    std::env::remove_var("FEATURE_NEW_GREETING");
    app::flags::reset_provider();
}

#[test]
fn integration_healthz_returns_ok() {
    let _g = lock();
    let addr = start_server();
    let (status, _, body) = http_request(&addr, "GET", "/healthz", &[]);
    assert_eq!(status, 200);
    assert_eq!(body, r#"{"status":"ok"}"#);

    // A query string is stripped for routing (cardinality + secret hygiene).
    let (status, _, body) = http_request(&addr, "GET", "/healthz?token=secret", &[]);
    assert_eq!(status, 200);
    assert_eq!(body, r#"{"status":"ok"}"#);
}

#[test]
fn integration_metrics_exposes_counter() {
    let _g = lock();
    let addr = start_server();
    let _ = http_request(&addr, "GET", "/greeting", &[]); // record at least one request
    let (status, headers, body) = http_request(&addr, "GET", "/metrics", &[]);
    assert_eq!(status, 200);
    assert!(header_values(&headers, "Content-Type")[0].starts_with("text/plain"));
    assert!(
        body.contains("http_requests_total"),
        "metrics missing http_requests_total:\n{body}"
    );
}

/// ★ The load-bearing wiring proof: install the file-config provider, then rewrite the
/// SAME flag file and observe `/greeting` flip on the SAME running server with NO
/// restart. Proves the seam flips the REAL endpoint, not a side process. This is the
/// exact failure an inert seam would hide.
#[test]
fn integration_greeting_live_flip_on_same_running_server() {
    let _g = lock();
    std::env::remove_var("FEATURE_NEW_GREETING");
    app::flags::reset_provider();
    let addr = start_server();

    let flag_file = temp_dir().join("flags.json");
    std::fs::write(&flag_file, r#"{"new_greeting":false}"#).unwrap();
    app::flags::set_provider(Box::new(app::live_provider::FileConfigProvider::new(
        flag_file.to_string_lossy().to_string(),
    )));

    let (_, _, before) = http_request(&addr, "GET", "/greeting", &[]);
    assert_eq!(
        before, r#"{"greeting":"Hello, world!"}"#,
        "pre-flip body should be the default greeting"
    );

    // Rewrite the SAME file — no server restart between these two GETs.
    std::fs::write(&flag_file, r#"{"new_greeting":true}"#).unwrap();
    let (_, _, after) = http_request(&addr, "GET", "/greeting", &[]);
    assert_eq!(
        after, r#"{"greeting":"Hello, world! (new)"}"#,
        "post-flip body should be the new greeting (live flip, no restart)"
    );

    app::flags::reset_provider();
}

#[test]
fn integration_get_carries_security_headers_and_neutral_server() {
    let _g = lock();
    let addr = start_server();
    let (status, headers, _) = http_request(&addr, "GET", "/healthz", &[]);
    assert_eq!(status, 200);
    assert_security_headers(&headers, "GET /healthz");
}

#[test]
fn integration_non_get_returns_404_with_security_headers() {
    let _g = lock();
    let addr = start_server();
    for method in ["POST", "PUT", "DELETE", "PATCH", "OPTIONS"] {
        let (status, headers, body) = http_request(&addr, method, "/greeting", &[]);
        assert_eq!(status, 404, "{method} status");
        assert_eq!(body, r#"{"error":"not found"}"#, "{method} body");
        assert_security_headers(&headers, method);
    }
}

#[test]
fn integration_head_returns_404_headers_without_body() {
    let _g = lock();
    let addr = start_server();
    let (status, headers, body) = http_request(&addr, "HEAD", "/healthz", &[]);
    assert_eq!(status, 404, "HEAD is not GET -> 404");
    assert_eq!(body, "", "HEAD must carry no body");
    for (name, _) in EXPECTED_SECURITY_HEADERS {
        assert!(
            !header_values(&headers, name).is_empty(),
            "HEAD missing security header {name}"
        );
    }
}

#[test]
fn integration_valid_inbound_request_id_is_echoed_into_span() {
    let _g = lock();
    app::flags::reset_provider();
    let trace = temp_dir().join("trace.jsonl");
    std::env::set_var("OTEL_TRACE_FILE", &trace);
    let addr = start_server();

    const VALID_ID: &str = "abc-123_valid.ID";
    let (status, _, _) = http_request(&addr, "GET", "/healthz", &[("X-Request-Id", VALID_ID)]);
    assert_eq!(status, 200);

    let contents = read_trace(&trace);
    assert_eq!(
        last_span_request_id(&contents),
        VALID_ID,
        "span request_id should be the honored inbound id"
    );
    std::env::remove_var("OTEL_TRACE_FILE");
}

#[test]
fn integration_oversized_inbound_request_id_is_replaced() {
    let _g = lock();
    app::flags::reset_provider();
    let trace = temp_dir().join("trace.jsonl");
    std::env::set_var("OTEL_TRACE_FILE", &trace);
    let addr = start_server();

    let bad = "x".repeat(129);
    let (status, _, _) = http_request(&addr, "GET", "/healthz", &[("X-Request-Id", &bad)]);
    assert_eq!(status, 200);

    let contents = read_trace(&trace);
    let minted = last_span_request_id(&contents);
    assert_ne!(
        minted, bad,
        "oversized inbound id must be rejected, not echoed"
    );
    assert_eq!(minted.len(), 32, "minted id should be 32 hex chars");
    assert!(minted.chars().all(|c| c.is_ascii_hexdigit()));
    std::env::remove_var("OTEL_TRACE_FILE");
}

// --- container HEALTHCHECK self-probe (server::health_check) ---
// Mirrors the go reference: `--healthcheck` must probe the RUNNING server's /healthz
// over HTTP and map 200+exact-body -> exit 0, anything else -> exit 1 (fail-safe).

#[test]
fn integration_health_check_returns_0_against_live_server() {
    let _g = lock();
    app::flags::reset_provider();
    let addr = start_server();
    assert_eq!(
        app::server::health_check(&addr),
        0,
        "health_check must return 0 when /healthz answers 200 with the ok body"
    );
}

#[test]
fn integration_health_check_returns_1_when_unreachable() {
    let _g = lock();
    // Bind an ephemeral port, capture it, then drop the listener so nothing is listening
    // -> connect fails -> the probe fails safe with exit code 1.
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind ephemeral port");
    let addr = format!("127.0.0.1:{}", listener.local_addr().unwrap().port());
    drop(listener);
    assert_eq!(
        app::server::health_check(&addr),
        1,
        "health_check must return 1 when the server is unreachable"
    );
}

#[test]
fn integration_health_check_returns_1_on_bad_addr() {
    let _g = lock();
    assert_eq!(
        app::server::health_check("not-an-addr"),
        1,
        "health_check must return 1 (not panic) on an unparseable address"
    );
}
