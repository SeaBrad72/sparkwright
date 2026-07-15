//! E2E: a full user journey against the assembled service.
//!
//! Liveness -> the greeting feature -> a not-found route, proving end-to-end behaviour
//! in-suite against a REAL server on an ephemeral port. DISTINCT from the post-deploy
//! `scripts/smoke.sh` (which proves a deployed container is alive); this is the runnable
//! in-process oracle. Mirrors the go reference `e2e_test.go` and python
//! `tests/e2e/test_journey.py`. Std-only HTTP client (this profile is dependency-free).

use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::time::Duration;

fn start_server() -> String {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind ephemeral port");
    let port = listener.local_addr().unwrap().port();
    std::thread::spawn(move || app::server::serve(&listener));
    format!("127.0.0.1:{port}")
}

/// A raw HTTP/1.1 GET returning `(status, body)`.
fn get(addr: &str, path: &str) -> (u16, String) {
    let mut stream = TcpStream::connect(addr).expect("connect to test server");
    stream
        .set_read_timeout(Some(Duration::from_secs(5)))
        .unwrap();
    let req = format!("GET {path} HTTP/1.1\r\nHost: {addr}\r\nConnection: close\r\n\r\n");
    stream.write_all(req.as_bytes()).unwrap();
    let mut raw = Vec::new();
    stream.read_to_end(&mut raw).unwrap();
    let text = String::from_utf8_lossy(&raw);
    let sep = text
        .find("\r\n\r\n")
        .expect("response missing head terminator");
    let status: u16 = text[..sep]
        .split(' ')
        .nth(1)
        .and_then(|code| code.parse().ok())
        .expect("status code");
    (status, text[sep + 4..].to_string())
}

#[test]
fn e2e_service_journey_liveness_greeting_then_404() {
    app::flags::reset_provider();
    std::env::remove_var("FEATURE_NEW_GREETING");
    let addr = start_server();

    let (status, body) = get(&addr, "/healthz");
    assert_eq!(status, 200, "liveness status");
    assert_eq!(body, r#"{"status":"ok"}"#, "liveness body");

    let (status, body) = get(&addr, "/greeting");
    assert_eq!(status, 200, "greeting status");
    assert!(
        body.starts_with(r#"{"greeting":"Hello, world!"#),
        "greeting body = {body}"
    );

    let (status, body) = get(&addr, "/nope");
    assert_eq!(status, 404, "not-found status");
    assert_eq!(body, r#"{"error":"not found"}"#, "not-found body");
}
