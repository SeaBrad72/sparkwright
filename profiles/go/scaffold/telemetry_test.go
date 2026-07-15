package main

import (
	"bytes"
	"encoding/hex"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// captureStdout runs fn with os.Stdout redirected to a pipe and returns what fn wrote.
func captureStdout(t *testing.T, fn func()) string {
	t.Helper()
	old := os.Stdout
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("os.Pipe: %v", err)
	}
	os.Stdout = w
	fn()
	if err := w.Close(); err != nil {
		t.Fatalf("close pipe writer: %v", err)
	}
	os.Stdout = old
	var buf bytes.Buffer
	if _, err := io.Copy(&buf, r); err != nil {
		t.Fatalf("copy pipe: %v", err)
	}
	return buf.String()
}

func TestNewSpanIDs(t *testing.T) {
	traceID, spanID := NewSpanIDs()

	if len(traceID) != 32 {
		t.Fatalf("traceID length = %d, want 32 hex chars (16 bytes)", len(traceID))
	}
	if len(spanID) != 16 {
		t.Fatalf("spanID length = %d, want 16 hex chars (8 bytes)", len(spanID))
	}
	if _, err := hex.DecodeString(traceID); err != nil {
		t.Fatalf("traceID not valid hex: %v", err)
	}
	if _, err := hex.DecodeString(spanID); err != nil {
		t.Fatalf("spanID not valid hex: %v", err)
	}

	// Two draws must differ (cryptographic randomness, not a constant).
	t2, s2 := NewSpanIDs()
	if traceID == t2 {
		t.Fatal("two traceIDs are identical; ids are not random")
	}
	if spanID == s2 {
		t.Fatal("two spanIDs are identical; ids are not random")
	}
}

func TestBuildSpanSchema(t *testing.T) {
	attrs := map[string]string{"http.method": "GET", "http.route": "/healthz"}
	span := BuildSpan("GET /healthz", 1000, 2500, attrs, 200)

	// Nano fields are decimal STRINGS (OTLP/JSON), not numbers.
	if got, ok := span["start_unix_nano"].(string); !ok || got != "1000" {
		t.Fatalf("start_unix_nano = %v (%T), want string \"1000\"", span["start_unix_nano"], span["start_unix_nano"])
	}
	if got, ok := span["end_unix_nano"].(string); !ok || got != "2500" {
		t.Fatalf("end_unix_nano = %v (%T), want string \"2500\"", span["end_unix_nano"], span["end_unix_nano"])
	}

	if span["parent_span_id"] != nil {
		t.Fatalf("parent_span_id = %v, want nil (root span)", span["parent_span_id"])
	}
	if span["name"] != "GET /healthz" {
		t.Fatalf("name = %v, want %q", span["name"], "GET /healthz")
	}
	if got, ok := span["attributes"].(map[string]string); !ok || got["http.route"] != "/healthz" {
		t.Fatalf("attributes = %v, want the passed-through map", span["attributes"])
	}

	traceID, ok := span["trace_id"].(string)
	if !ok || len(traceID) != 32 {
		t.Fatalf("trace_id = %v, want 32-hex-char string", span["trace_id"])
	}
	spanID, ok := span["span_id"].(string)
	if !ok || len(spanID) != 16 {
		t.Fatalf("span_id = %v, want 16-hex-char string", span["span_id"])
	}
}

func TestBuildSpanStatusBoundary(t *testing.T) {
	cases := []struct {
		statusCode int
		want       string
	}{
		{200, "OK"},
		{404, "OK"},
		{499, "OK"},
		{500, "ERROR"},
		{503, "ERROR"},
	}
	for _, c := range cases {
		span := BuildSpan("op", 0, 1, nil, c.statusCode)
		status, ok := span["status"].(map[string]any)
		if !ok {
			t.Fatalf("status is %T, want map[string]any", span["status"])
		}
		if status["code"] != c.want {
			t.Fatalf("status.code for %d = %v, want %q", c.statusCode, status["code"], c.want)
		}
	}
}

func TestEmitSpanToFile(t *testing.T) {
	dir := t.TempDir()
	sink := filepath.Join(dir, "spans.ndjson")
	t.Setenv("OTEL_TRACE_FILE", sink)

	EmitSpan(BuildSpan("first", 0, 1, nil, 200))
	EmitSpan(BuildSpan("second", 2, 3, nil, 500))

	data, err := os.ReadFile(sink) // #nosec G304 -- test-controlled temp path
	if err != nil {
		t.Fatalf("read sink: %v", err)
	}
	lines := strings.Split(strings.TrimRight(string(data), "\n"), "\n")
	if len(lines) != 2 {
		t.Fatalf("wrote %d lines, want 2 (append semantics)", len(lines))
	}
	for i, line := range lines {
		var span map[string]any
		if err := json.Unmarshal([]byte(line), &span); err != nil {
			t.Fatalf("line %d is not valid JSON: %v", i, err)
		}
	}
}

func TestEmitSpanToStdout(t *testing.T) {
	t.Setenv("OTEL_TRACE_FILE", "")
	out := captureStdout(t, func() {
		EmitSpan(BuildSpan("stdout-span", 10, 20, nil, 200))
	})
	var span map[string]any
	if err := json.Unmarshal([]byte(strings.TrimSpace(out)), &span); err != nil {
		t.Fatalf("stdout span is not valid JSON: %v (out=%q)", err, out)
	}
	if span["name"] != "stdout-span" {
		t.Fatalf("stdout span name = %v, want stdout-span", span["name"])
	}
}

func TestEmitSpanBadSinkDoesNotPanic(t *testing.T) {
	// A sink under a nonexistent directory cannot be opened; EmitSpan must
	// degrade silently rather than crash the request path.
	t.Setenv("OTEL_TRACE_FILE", filepath.Join(t.TempDir(), "no-such-dir", "spans.ndjson"))
	EmitSpan(BuildSpan("dropped", 0, 1, nil, 200))
}

func TestRecordMetricBoundedCardinality(t *testing.T) {
	ResetMetrics()
	RecordMetric("GET", 200, 5)
	RecordMetric("BREW", 418, 3) // unknown method -> "other"
	RecordMetric("get", 200, 1)  // case-sensitive: lowercase is not known -> "other"

	out := RenderMetrics()
	if !strings.Contains(out, `http_requests_total{method="GET",status="200"} 1`) {
		t.Fatalf("known method series missing:\n%s", out)
	}
	if !strings.Contains(out, `http_requests_total{method="other",status="418"} 1`) {
		t.Fatalf("unknown method not bucketed as other:\n%s", out)
	}
	if !strings.Contains(out, `http_requests_total{method="other",status="200"} 1`) {
		t.Fatalf("lowercase method not bucketed as other:\n%s", out)
	}
	if strings.Contains(out, `method="BREW"`) || strings.Contains(out, `method="get"`) {
		t.Fatalf("raw unknown method label leaked into output:\n%s", out)
	}
}

func TestRecordMetricCounterAggregates(t *testing.T) {
	ResetMetrics()
	RecordMetric("POST", 201, 2)
	RecordMetric("POST", 201, 2)
	out := RenderMetrics()
	if !strings.Contains(out, `http_requests_total{method="POST",status="201"} 2`) {
		t.Fatalf("counter did not aggregate to 2:\n%s", out)
	}
}

func TestRenderMetricsShape(t *testing.T) {
	ResetMetrics()
	RecordMetric("GET", 200, 5)

	out := RenderMetrics()
	for _, want := range []string{
		"# HELP http_requests_total Total number of HTTP requests handled.",
		"# TYPE http_requests_total counter",
		"# HELP http_request_duration_seconds_total Total accumulated request duration in seconds.",
		"# TYPE http_request_duration_seconds_total counter",
		"http_request_duration_seconds_total ",
	} {
		if !strings.Contains(out, want) {
			t.Fatalf("RenderMetrics output missing %q:\n%s", want, out)
		}
	}
	if !strings.HasSuffix(out, "\n") {
		t.Fatalf("RenderMetrics output must end with a trailing newline:\n%q", out)
	}
}

func TestRenderMetricsDurationAccumulates(t *testing.T) {
	ResetMetrics()
	RecordMetric("GET", 200, 500) // 0.5s
	RecordMetric("GET", 200, 250) // 0.25s -> total 0.75s
	out := RenderMetrics()
	if !strings.Contains(out, "http_request_duration_seconds_total 0.75") {
		t.Fatalf("duration did not accumulate to 0.75:\n%s", out)
	}
}

func TestResetMetrics(t *testing.T) {
	RecordMetric("GET", 200, 5)
	ResetMetrics()
	out := RenderMetrics()
	if strings.Contains(out, "http_requests_total{") {
		t.Fatalf("ResetMetrics left request series behind:\n%s", out)
	}
	if !strings.Contains(out, "http_request_duration_seconds_total 0") {
		t.Fatalf("ResetMetrics did not zero the duration total:\n%s", out)
	}
}

func TestEscapeLabelValue(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"GET", "GET"},
		{`a"b`, `a\"b`},
		{`a\b`, `a\\b`},
		{"a\nb", `a\nb`},
		{"\\\"\n", `\\\"\n`},
	}
	for _, c := range cases {
		if got := escapeLabelValue(c.in); got != c.want {
			t.Fatalf("escapeLabelValue(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestRenderMetricsEscapesLabels(t *testing.T) {
	// Defensive: even if a value with quotes/backslashes reaches the renderer it
	// must not break or inject a series line.
	ResetMetrics()
	metricsMu.Lock()
	requestsTotal[metricKey{method: `x"\` + "\n", status: 200}] = 1
	metricsMu.Unlock()
	out := RenderMetrics()
	if !strings.Contains(out, `method="x\"\\\n"`) {
		t.Fatalf("label value not escaped in output:\n%s", out)
	}
}

func TestLogShape(t *testing.T) {
	t.Setenv("SERVICE_NAME", "")
	out := captureStdout(t, func() {
		Log(map[string]any{"event": "request", "status": 200})
	})
	var record map[string]any
	if err := json.Unmarshal([]byte(strings.TrimSpace(out)), &record); err != nil {
		t.Fatalf("log line is not valid JSON: %v (out=%q)", err, out)
	}
	if record["level"] != "info" {
		t.Fatalf("level = %v, want info", record["level"])
	}
	if record["service"] != "reference-app" {
		t.Fatalf("service = %v, want default reference-app", record["service"])
	}
	if record["event"] != "request" {
		t.Fatalf("merged field event = %v, want request", record["event"])
	}
	ts, ok := record["ts"].(string)
	if !ok {
		t.Fatalf("ts is %T, want string", record["ts"])
	}
	if _, err := time.Parse(time.RFC3339, ts); err != nil {
		t.Fatalf("ts %q is not RFC3339: %v", ts, err)
	}
}

func TestLogServiceNameOverride(t *testing.T) {
	t.Setenv("SERVICE_NAME", "custom-svc")
	out := captureStdout(t, func() {
		Log(map[string]any{"event": "boot"})
	})
	var record map[string]any
	if err := json.Unmarshal([]byte(strings.TrimSpace(out)), &record); err != nil {
		t.Fatalf("log line is not valid JSON: %v", err)
	}
	if record["service"] != "custom-svc" {
		t.Fatalf("service = %v, want custom-svc from SERVICE_NAME", record["service"])
	}
}
