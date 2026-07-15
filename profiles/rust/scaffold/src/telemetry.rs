//! Pure telemetry primitives — spans, bounded-cardinality Prometheus metrics, and
//! correlated JSON logs. The importable core the app server calls per request.
//!
//! Mirrors the go/python/typescript-node references (`telemetry.go` / `telemetry.py`
//! / `server.ts`): OTel-semantic spans in the exact `scripts/otel-trace.sh` schema,
//! Prometheus text exposition, and structured logs — deliberately std-only (this
//! profile is dependency-free) and free of any socket/handler code, so the logic is
//! unit-tested here and the I/O surface (the server) is wired separately. Sinks are
//! chosen by env, exactly like the reference: spans go to `OTEL_TRACE_FILE` if set
//! (append) else stdout; logs carry `SERVICE_NAME` (default `"reference-app"`).
//!
//! JSON is hand-formatted rather than pulling in `serde_json`: every shape emitted
//! here is small and fully controlled (span/log field sets are closed), and
//! [`escape_json`] is the single choke point every string value passes through, so
//! there is one place to audit for injection rather than one per call site.

use std::collections::BTreeMap;
use std::fs::OpenOptions;
use std::io::{Read, Write};
use std::sync::{Mutex, OnceLock, PoisonError};

/// The bounded label set. An unknown (or non-canonical, e.g. lowercase) method is
/// bucketed as `"other"` so a hostile caller cannot explode Prometheus series
/// cardinality — the request path is intentionally NEVER a label.
const KNOWN_METHODS: &[&str] = &["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"];

/// Module-level request-metric state, reset via [`reset_metrics`] for
/// lifecycle/test isolation. `BTreeMap` (rather than `HashMap`) keeps
/// [`render_metrics`]'s series output in deterministic `(method, status)` order
/// without a separate sort step.
#[derive(Default)]
struct MetricsState {
    requests_total: BTreeMap<(String, u16), u64>,
    duration_seconds_total: f64,
}

/// Returns the shared metrics mutex, lazily initialized. A poisoned lock (a prior
/// panic while held) is recovered rather than propagated — telemetry must never
/// take the request path down with it.
fn metrics_state() -> &'static Mutex<MetricsState> {
    static STATE: OnceLock<Mutex<MetricsState>> = OnceLock::new();
    STATE.get_or_init(|| Mutex::new(MetricsState::default()))
}

fn lock_metrics() -> std::sync::MutexGuard<'static, MetricsState> {
    metrics_state()
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
}

/// Returns `n` cryptographically random bytes as a lowercase hex string, sourced
/// from the OS entropy device. This profile is intentionally dependency-free
/// (std-only — no `rand`/`getrandom` crate); `/dev/urandom` is present on every
/// platform this profile's CI targets (Linux/macOS) and is the same kernel source
/// Go's `crypto/rand` and Python's `secrets` draw from underneath their stdlib API.
fn random_hex(n: usize) -> String {
    let mut buf = vec![0u8; n];
    // #nosec -- OS entropy device read for trace/span id generation, not a secret path.
    let mut urandom = std::fs::File::open("/dev/urandom")
        .expect("telemetry: /dev/urandom unavailable (unsupported platform)");
    urandom
        .read_exact(&mut buf)
        .expect("telemetry: failed to read OS entropy from /dev/urandom");
    buf.iter().map(|b| format!("{b:02x}")).collect()
}

/// Returns a fresh `(trace_id, span_id)`: 16-byte and 8-byte cryptographic hex.
pub fn new_span_ids() -> (String, String) {
    (random_hex(16), random_hex(8))
}

/// Escapes a string for embedding inside a JSON string literal (`"`, `\`, control
/// characters). Defensive: an unusual span name / attribute / log field value can
/// never break out of its JSON string or inject a sibling key.
fn escape_json(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for c in value.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

/// An OTel-semantic span in the reference `otel-trace.sh` schema.
pub struct Span {
    pub trace_id: String,
    pub span_id: String,
    pub name: String,
    pub start_unix_nano: i64,
    pub end_unix_nano: i64,
    pub attributes: BTreeMap<String, String>,
    pub status_code: u16,
}

impl Span {
    /// Serializes the span to its wire JSON. `*_unix_nano` are emitted as decimal
    /// STRINGS (OTLP/JSON represents them that way — avoids the float precision
    /// loss unix nanos, ~1.8e18, would incur through a JSON number). `status.code`
    /// is `"ERROR"` for `>= 500` else `"OK"`. `parent_span_id` is always `null`
    /// (root span) — the server correlates related spans via `attributes`.
    #[must_use]
    pub fn to_json(&self) -> String {
        let status_code = if self.status_code >= 500 {
            "ERROR"
        } else {
            "OK"
        };
        let mut attrs = String::from("{");
        for (i, (k, v)) in self.attributes.iter().enumerate() {
            if i > 0 {
                attrs.push(',');
            }
            attrs.push_str(&format!("\"{}\":\"{}\"", escape_json(k), escape_json(v)));
        }
        attrs.push('}');
        format!(
            "{{\"trace_id\":\"{}\",\"span_id\":\"{}\",\"parent_span_id\":null,\"name\":\"{}\",\
             \"start_unix_nano\":\"{}\",\"end_unix_nano\":\"{}\",\"attributes\":{attrs},\
             \"status\":{{\"code\":\"{status_code}\"}}}}",
            self.trace_id,
            self.span_id,
            escape_json(&self.name),
            self.start_unix_nano,
            self.end_unix_nano,
        )
    }
}

/// Builds an OTel-semantic span — see [`Span::to_json`] for the wire shape. Mints a
/// fresh trace/span id on every call; the server correlates related spans via
/// `attributes`, not `parent_span_id` (always root here).
pub fn build_span(
    name: &str,
    start_unix_nano: i64,
    end_unix_nano: i64,
    attributes: BTreeMap<String, String>,
    status_code: u16,
) -> Span {
    let (trace_id, span_id) = new_span_ids();
    Span {
        trace_id,
        span_id,
        name: name.to_string(),
        start_unix_nano,
        end_unix_nano,
        attributes,
        status_code,
    }
}

/// Writes the span as one JSON line to `OTEL_TRACE_FILE` (append) if set and
/// non-empty, else stdout. Degrades silently on any sink error — telemetry must
/// never break the request path it observes.
pub fn emit_span(span: &Span) {
    let line = span.to_json();
    match std::env::var("OTEL_TRACE_FILE") {
        Ok(path) if !path.is_empty() => {
            // #nosec -- the trace sink is an operator-provided env var (OTEL_TRACE_FILE) by design.
            if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(&path) {
                let _ = writeln!(file, "{line}");
            }
        }
        _ => println!("{line}"),
    }
}

/// Increments the request counter for `(method_label, status)` and adds to the
/// duration total. `method_label` is `method` when it is one of [`KNOWN_METHODS`],
/// else `"other"` (bounded cardinality; the request path is never a label).
pub fn record_metric(method: &str, status: u16, latency_ms: f64) {
    let label = if KNOWN_METHODS.contains(&method) {
        method
    } else {
        "other"
    };
    let mut state = lock_metrics();
    *state
        .requests_total
        .entry((label.to_string(), status))
        .or_insert(0) += 1;
    state.duration_seconds_total += latency_ms / 1000.0;
}

/// Escapes a Prometheus label value per the text exposition spec (`\`, `"`, `\n`).
/// `method` is already normalised to a known set by [`record_metric`], but escaping
/// stays defensive: an unusual value can never break a series line or inject one.
fn escape_label_value(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
}

/// Renders the two counters as Prometheus text exposition (trailing newline).
/// Series are emitted in the `BTreeMap`'s natural `(method, status)` order, so
/// output is deterministic across runs.
#[must_use]
pub fn render_metrics() -> String {
    let state = lock_metrics();
    let mut out = String::new();
    out.push_str("# HELP http_requests_total Total number of HTTP requests handled.\n");
    out.push_str("# TYPE http_requests_total counter\n");
    for ((method, status), count) in &state.requests_total {
        let method = escape_label_value(method);
        out.push_str(&format!(
            "http_requests_total{{method=\"{method}\",status=\"{status}\"}} {count}\n"
        ));
    }
    out.push_str(
        "# HELP http_request_duration_seconds_total Total accumulated request duration in seconds.\n",
    );
    out.push_str("# TYPE http_request_duration_seconds_total counter\n");
    let duration = state.duration_seconds_total;
    out.push_str(&format!("http_request_duration_seconds_total {duration}\n"));
    out
}

/// Clears the module-level counter state (lifecycle/test helper).
pub fn reset_metrics() {
    let mut state = lock_metrics();
    state.requests_total.clear();
    state.duration_seconds_total = 0.0;
}

/// A structured log field value — the small, closed set of JSON scalar shapes an
/// app log line needs. Never construct one from a request body, header, or
/// PII/secret.
pub enum LogValue {
    Str(String),
    Int(i64),
    UInt(u64),
    Bool(bool),
    Float(f64),
}

impl LogValue {
    fn to_json(&self) -> String {
        match self {
            LogValue::Str(s) => format!("\"{}\"", escape_json(s)),
            LogValue::Int(i) => i.to_string(),
            LogValue::UInt(u) => u.to_string(),
            LogValue::Bool(b) => b.to_string(),
            // A non-finite float (NaN/Inf) is not valid JSON; coerce to 0 so a log line
            // can never emit a malformed token. Request latency is always finite, so
            // this is purely defensive.
            LogValue::Float(f) => {
                if f.is_finite() {
                    f.to_string()
                } else {
                    "0".to_string()
                }
            }
        }
    }
}

impl From<&str> for LogValue {
    fn from(v: &str) -> Self {
        LogValue::Str(v.to_string())
    }
}

impl From<String> for LogValue {
    fn from(v: String) -> Self {
        LogValue::Str(v)
    }
}

impl From<i64> for LogValue {
    fn from(v: i64) -> Self {
        LogValue::Int(v)
    }
}

impl From<u16> for LogValue {
    fn from(v: u16) -> Self {
        LogValue::UInt(u64::from(v))
    }
}

impl From<u64> for LogValue {
    fn from(v: u64) -> Self {
        LogValue::UInt(v)
    }
}

impl From<bool> for LogValue {
    fn from(v: bool) -> Self {
        LogValue::Bool(v)
    }
}

impl From<f64> for LogValue {
    fn from(v: f64) -> Self {
        LogValue::Float(v)
    }
}

/// Emits one structured JSON log line to stdout: `ts` (RFC3339 UTC), `level:"info"`,
/// `service` (`SERVICE_NAME` env, default `"reference-app"`), plus the merged
/// fields in the given order.
///
/// Never pass request bodies, headers, or PII/secrets in `fields`.
pub fn log(fields: &[(&str, LogValue)]) {
    let service = std::env::var("SERVICE_NAME").unwrap_or_default();
    let service = if service.is_empty() {
        "reference-app"
    } else {
        &service
    };
    println!("{}", format_log_line(&rfc3339_now(), service, fields));
}

/// Pure line-formatting core of [`log`], with `ts` and the resolved `service`
/// injected — split out so tests assert an exact rendered line without depending
/// on wall-clock time.
fn format_log_line(ts: &str, service: &str, fields: &[(&str, LogValue)]) -> String {
    let mut out = format!(
        "{{\"ts\":\"{}\",\"level\":\"info\",\"service\":\"{}\"",
        escape_json(ts),
        escape_json(service)
    );
    for (k, v) in fields {
        out.push_str(&format!(",\"{}\":{}", escape_json(k), v.to_json()));
    }
    out.push('}');
    out
}

/// Returns the current instant as an RFC3339 UTC timestamp (`YYYY-MM-DDTHH:MM:SSZ`,
/// no fractional seconds — matching the go reference's `time.Now().UTC().Format
/// (time.RFC3339)`). Hand-rolled: std has no calendar API and this profile is
/// dependency-free (no `chrono`/`time` crate).
fn rfc3339_now() -> String {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default();
    let secs = now.as_secs();
    let days = i64::try_from(secs / 86400).unwrap_or(0);
    let secs_of_day = secs % 86400;
    let (year, month, day) = civil_from_days(days);
    let hour = secs_of_day / 3600;
    let minute = (secs_of_day % 3600) / 60;
    let second = secs_of_day % 60;
    format!("{year:04}-{month:02}-{day:02}T{hour:02}:{minute:02}:{second:02}Z")
}

/// Converts a day count since the Unix epoch (1970-01-01) to a civil
/// `(year, month, day)` triple. Howard Hinnant's `civil_from_days` algorithm — the
/// standard proleptic-Gregorian conversion used across many std libraries that
/// (like this one) don't have a calendar type to call instead.
fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u64; // [0, 146096]
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365; // [0, 399]
    let y = i64::try_from(yoe).unwrap_or(0) + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100); // [0, 365]
    let mp = (5 * doy + 2) / 153; // [0, 11]
    let d = u32::try_from(doy - (153 * mp + 2) / 5 + 1).unwrap_or(1); // [1, 31]
    let m = u32::try_from(if mp < 10 { mp + 3 } else { mp - 9 }).unwrap_or(1); // [1, 12]
    let y = if m <= 2 { y + 1 } else { y };
    (y, m, d)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex as StdMutex;

    /// Serializes tests that touch shared process-global state (the metrics mutex,
    /// `OTEL_TRACE_FILE`/`SERVICE_NAME` env vars) — `cargo test` runs tests
    /// multi-threaded by default, unlike `go test`'s single-goroutine-per-package
    /// default, so these tests would otherwise race each other.
    static GUARD: StdMutex<()> = StdMutex::new(());

    fn lock() -> std::sync::MutexGuard<'static, ()> {
        GUARD.lock().unwrap_or_else(PoisonError::into_inner)
    }

    fn attrs(pairs: &[(&str, &str)]) -> BTreeMap<String, String> {
        pairs
            .iter()
            .map(|(k, v)| ((*k).to_string(), (*v).to_string()))
            .collect()
    }

    #[test]
    fn new_span_ids_are_correctly_shaped_and_random() {
        let (trace_id, span_id) = new_span_ids();
        assert_eq!(
            trace_id.len(),
            32,
            "trace_id should be 32 hex chars (16 bytes)"
        );
        assert_eq!(
            span_id.len(),
            16,
            "span_id should be 16 hex chars (8 bytes)"
        );
        assert!(trace_id.chars().all(|c| c.is_ascii_hexdigit()));
        assert!(span_id.chars().all(|c| c.is_ascii_hexdigit()));

        let (trace_id2, span_id2) = new_span_ids();
        assert_ne!(
            trace_id, trace_id2,
            "two trace_ids must differ (randomness)"
        );
        assert_ne!(span_id, span_id2, "two span_ids must differ (randomness)");
    }

    #[test]
    fn build_span_schema() {
        let span = build_span(
            "GET /healthz",
            1000,
            2500,
            attrs(&[("http.method", "GET"), ("http.route", "/healthz")]),
            200,
        );
        assert_eq!(span.name, "GET /healthz");
        assert_eq!(span.start_unix_nano, 1000);
        assert_eq!(span.end_unix_nano, 2500);
        assert_eq!(span.attributes.get("http.route").unwrap(), "/healthz");
        assert_eq!(span.trace_id.len(), 32);
        assert_eq!(span.span_id.len(), 16);
    }

    #[test]
    fn escape_json_covers_every_control_case() {
        assert_eq!(escape_json("a\"b"), "a\\\"b");
        assert_eq!(escape_json("a\\b"), "a\\\\b");
        assert_eq!(escape_json("a\nb"), "a\\nb");
        assert_eq!(escape_json("a\rb"), "a\\rb");
        assert_eq!(escape_json("a\tb"), "a\\tb");
        assert_eq!(escape_json("a\u{01}b"), "a\\u0001b");
        assert_eq!(escape_json("plain"), "plain");
    }

    #[test]
    fn to_json_nano_fields_are_strings() {
        let span = build_span("op", 1000, 2500, BTreeMap::new(), 200);
        let json = span.to_json();
        assert!(json.contains("\"start_unix_nano\":\"1000\""), "{json}");
        assert!(json.contains("\"end_unix_nano\":\"2500\""), "{json}");
    }

    #[test]
    fn to_json_parent_span_id_is_null() {
        let span = build_span("op", 0, 1, BTreeMap::new(), 200);
        assert!(span.to_json().contains("\"parent_span_id\":null"));
    }

    #[test]
    fn to_json_status_boundary() {
        for (status_code, want) in [
            (200u16, "OK"),
            (404, "OK"),
            (499, "OK"),
            (500, "ERROR"),
            (503, "ERROR"),
        ] {
            let span = build_span("op", 0, 1, BTreeMap::new(), status_code);
            let json = span.to_json();
            assert!(
                json.contains(&format!("\"status\":{{\"code\":\"{want}\"}}")),
                "status_code={status_code}: {json}"
            );
        }
    }

    #[test]
    fn to_json_escapes_name_and_attributes() {
        let span = build_span(
            "op \"quoted\"",
            0,
            1,
            attrs(&[("k", "v\\with\nbreaks")]),
            200,
        );
        let json = span.to_json();
        assert!(json.contains(r#""name":"op \"quoted\"""#), "{json}");
        assert!(json.contains(r#""k":"v\\with\nbreaks""#), "{json}");
    }

    #[test]
    fn to_json_multiple_attributes_are_comma_separated() {
        let span = build_span(
            "op",
            0,
            1,
            attrs(&[("http.method", "GET"), ("http.route", "/healthz")]),
            200,
        );
        let json = span.to_json();
        assert!(
            json.contains(r#""attributes":{"http.method":"GET","http.route":"/healthz"}"#),
            "{json}"
        );
    }

    #[test]
    fn emit_span_to_file_appends_lines() {
        let _g = lock();
        let dir = std::env::temp_dir().join(format!(
            "sparkwright-rust-telemetry-test-{}-{}",
            std::process::id(),
            new_span_ids().1
        ));
        std::fs::create_dir_all(&dir).unwrap();
        let sink = dir.join("spans.ndjson");
        std::env::set_var("OTEL_TRACE_FILE", &sink);

        emit_span(&build_span("first", 0, 1, BTreeMap::new(), 200));
        emit_span(&build_span("second", 2, 3, BTreeMap::new(), 500));

        let data = std::fs::read_to_string(&sink).unwrap();
        let lines: Vec<&str> = data.trim_end().split('\n').collect();
        assert_eq!(
            lines.len(),
            2,
            "append semantics: expected 2 lines, got {lines:?}"
        );
        for line in lines {
            assert!(
                line.starts_with('{') && line.ends_with('}'),
                "not JSON-shaped: {line}"
            );
        }

        std::env::remove_var("OTEL_TRACE_FILE");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn emit_span_bad_sink_does_not_panic() {
        let _g = lock();
        std::env::set_var(
            "OTEL_TRACE_FILE",
            std::env::temp_dir().join("sparkwright-rust-telemetry-no-such-dir/spans.ndjson"),
        );
        emit_span(&build_span("dropped", 0, 1, BTreeMap::new(), 200));
        std::env::remove_var("OTEL_TRACE_FILE");
    }

    #[test]
    fn emit_span_empty_sink_var_falls_back_to_stdout_path() {
        // An OTEL_TRACE_FILE set to "" must take the stdout branch, not attempt to
        // open an empty path. Exercised for coverage of that branch; the exact
        // rendered content is covered by the `to_json` tests above (`emit_span`
        // prints the same string `to_json` produces).
        let _g = lock();
        std::env::set_var("OTEL_TRACE_FILE", "");
        emit_span(&build_span("stdout-path", 0, 1, BTreeMap::new(), 200));
        std::env::remove_var("OTEL_TRACE_FILE");
    }

    #[test]
    fn record_metric_bounded_cardinality() {
        let _g = lock();
        reset_metrics();
        record_metric("GET", 200, 5.0);
        record_metric("BREW", 418, 3.0); // unknown method -> "other"
        record_metric("get", 200, 1.0); // case-sensitive: lowercase is not known -> "other"

        let out = render_metrics();
        assert!(
            out.contains(r#"http_requests_total{method="GET",status="200"} 1"#),
            "{out}"
        );
        assert!(
            out.contains(r#"http_requests_total{method="other",status="418"} 1"#),
            "{out}"
        );
        assert!(
            out.contains(r#"http_requests_total{method="other",status="200"} 1"#),
            "{out}"
        );
        assert!(!out.contains("method=\"BREW\""), "{out}");
        assert!(!out.contains("method=\"get\""), "{out}");
    }

    #[test]
    fn record_metric_counter_aggregates() {
        let _g = lock();
        reset_metrics();
        record_metric("POST", 201, 2.0);
        record_metric("POST", 201, 2.0);
        let out = render_metrics();
        assert!(
            out.contains(r#"http_requests_total{method="POST",status="201"} 2"#),
            "{out}"
        );
    }

    #[test]
    fn render_metrics_shape() {
        let _g = lock();
        reset_metrics();
        record_metric("GET", 200, 5.0);
        let out = render_metrics();
        for want in [
            "# HELP http_requests_total Total number of HTTP requests handled.",
            "# TYPE http_requests_total counter",
            "# HELP http_request_duration_seconds_total Total accumulated request duration in seconds.",
            "# TYPE http_request_duration_seconds_total counter",
            "http_request_duration_seconds_total ",
        ] {
            assert!(out.contains(want), "missing {want:?} in:\n{out}");
        }
        assert!(out.ends_with('\n'));
    }

    #[test]
    fn render_metrics_duration_accumulates() {
        let _g = lock();
        reset_metrics();
        record_metric("GET", 200, 500.0); // 0.5s
        record_metric("GET", 200, 250.0); // 0.25s -> total 0.75s
        let out = render_metrics();
        assert!(
            out.contains("http_request_duration_seconds_total 0.75"),
            "{out}"
        );
    }

    #[test]
    fn reset_metrics_clears_state() {
        let _g = lock();
        record_metric("GET", 200, 5.0);
        reset_metrics();
        let out = render_metrics();
        assert!(!out.contains("http_requests_total{"), "{out}");
        assert!(
            out.contains("http_request_duration_seconds_total 0"),
            "{out}"
        );
    }

    #[test]
    fn escape_label_value_cases() {
        assert_eq!(escape_label_value("GET"), "GET");
        assert_eq!(escape_label_value("a\"b"), "a\\\"b");
        assert_eq!(escape_label_value("a\\b"), "a\\\\b");
        assert_eq!(escape_label_value("a\nb"), "a\\nb");
    }

    #[test]
    fn render_metrics_escapes_labels() {
        // Defensive: even if a value with quotes/backslashes reached the renderer
        // (record_metric only ever passes a bounded label) it must not break or
        // inject a series line.
        let _g = lock();
        reset_metrics();
        {
            let mut state = lock_metrics();
            state.requests_total.insert(("x\"\\\n".to_string(), 200), 1);
        }
        let out = render_metrics();
        assert!(out.contains(r#"method="x\"\\\n""#), "{out}");
    }

    #[test]
    fn log_value_conversions_render_expected_json() {
        assert_eq!(LogValue::from("hi").to_json(), "\"hi\"");
        assert_eq!(LogValue::from(String::from("hi")).to_json(), "\"hi\"");
        assert_eq!(LogValue::from(-3i64).to_json(), "-3");
        assert_eq!(LogValue::from(7u64).to_json(), "7");
        assert_eq!(LogValue::from(200u16).to_json(), "200");
        assert_eq!(LogValue::from(true).to_json(), "true");
        assert_eq!(LogValue::from(1.5f64).to_json(), "1.5");
        assert_eq!(LogValue::from(f64::NAN).to_json(), "0"); // non-finite -> valid JSON
    }

    #[test]
    fn format_log_line_shape() {
        let line = format_log_line(
            "2024-01-01T00:00:00Z",
            "reference-app",
            &[
                ("event", LogValue::from("request")),
                ("status", LogValue::from(200u16)),
            ],
        );
        assert!(line.starts_with('{') && line.ends_with('}'), "{line}");
        assert!(line.contains(r#""ts":"2024-01-01T00:00:00Z""#), "{line}");
        assert!(line.contains(r#""level":"info""#), "{line}");
        assert!(line.contains(r#""service":"reference-app""#), "{line}");
        assert!(line.contains(r#""event":"request""#), "{line}");
        assert!(line.contains(r#""status":200"#), "{line}");
    }

    #[test]
    fn log_default_service_name() {
        let _g = lock();
        std::env::set_var("SERVICE_NAME", "");
        // Exercises the public entry point (env resolution + println!) for
        // coverage; format_log_line above asserts the exact rendered shape.
        log(&[("event", LogValue::from("boot"))]);
        std::env::remove_var("SERVICE_NAME");
    }

    #[test]
    fn log_service_name_override_resolves_from_env() {
        let _g = lock();
        std::env::set_var("SERVICE_NAME", "custom-svc");
        log(&[("event", LogValue::from("boot"))]);
        std::env::remove_var("SERVICE_NAME");
    }

    #[test]
    fn rfc3339_now_is_well_formed() {
        let ts = rfc3339_now();
        assert_eq!(ts.len(), 20, "{ts}");
        assert!(ts.ends_with('Z'), "{ts}");
        let bytes = ts.as_bytes();
        assert_eq!(bytes[4], b'-');
        assert_eq!(bytes[7], b'-');
        assert_eq!(bytes[10], b'T');
        assert_eq!(bytes[13], b':');
        assert_eq!(bytes[16], b':');
        let year: u32 = ts[0..4].parse().unwrap();
        let month: u32 = ts[5..7].parse().unwrap();
        let day: u32 = ts[8..10].parse().unwrap();
        assert!(year >= 2024, "{ts}");
        assert!((1..=12).contains(&month), "{ts}");
        assert!((1..=31).contains(&day), "{ts}");
    }

    #[test]
    fn civil_from_days_known_dates() {
        // 1970-01-01 is day 0; 2000-01-01 is day 10957 (well-known epoch offset,
        // cross-checked against the Hinnant algorithm's reference table).
        assert_eq!(civil_from_days(0), (1970, 1, 1));
        assert_eq!(civil_from_days(10_957), (2000, 1, 1));
        assert_eq!(civil_from_days(19_723), (2024, 1, 1));
    }
}
