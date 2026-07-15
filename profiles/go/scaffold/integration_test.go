package main

// Integration: the flag seam + telemetry wiring THROUGH the running server.
//
// Unlike the unit tests (dispatch/IsEnabled in isolation), here the flag registry,
// the instrumented handler, and the real HTTP layer are exercised together against
// an ephemeral listening socket (httptest.Server) in the SAME process — so the
// coverage tool measures server.go. Mirrors the python reference
// tests/integration/test_greeting.py. The live-flip case is the load-bearing proof
// that the provider seam reaches the REAL endpoint with no restart.

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// expectedSecurityHeaders are the four headers stamped on EVERY response.
var expectedSecurityHeaders = map[string]string{
	"X-Content-Type-Options":  "nosniff",
	"X-Frame-Options":         "DENY",
	"Content-Security-Policy": "default-src 'none'",
	"Referrer-Policy":         "no-referrer",
}

// newLiveServer starts the assembled handler on an ephemeral port and returns its
// base URL. It resets the flag provider on cleanup so a live-flip test cannot leak
// a file provider into a later test.
func newLiveServer(t *testing.T) string {
	t.Helper()
	srv := httptest.NewServer(newHandler())
	t.Cleanup(func() {
		srv.Close()
		ResetProvider()
	})
	return srv.URL
}

// getBody performs a real GET and returns (status, body, content-type).
func getBody(t *testing.T, base, path string) (int, string, string) {
	t.Helper()
	resp, err := http.Get(base + path) //nolint:gosec // trusted localhost test URL
	if err != nil {
		t.Fatalf("GET %s: %v", path, err)
	}
	defer func() { _ = resp.Body.Close() }()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("read body: %v", err)
	}
	return resp.StatusCode, string(body), resp.Header.Get("Content-Type")
}

// doRequest performs an arbitrary-method request and returns (status, body, headers).
func doRequest(t *testing.T, base, method, path string, headers map[string]string) (int, string, http.Header) {
	t.Helper()
	req, err := http.NewRequest(method, base+path, nil)
	if err != nil {
		t.Fatalf("build %s %s: %v", method, path, err)
	}
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("%s %s: %v", method, path, err)
	}
	defer func() { _ = resp.Body.Close() }()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("read body: %v", err)
	}
	return resp.StatusCode, string(body), resp.Header
}

func TestIntegrationGreetingFlagOffServesDefault(t *testing.T) {
	base := newLiveServer(t)
	ResetProvider()
	status, body, ctype := getBody(t, base, "/greeting")
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}
	if ctype != "application/json" {
		t.Fatalf("content-type = %q, want application/json", ctype)
	}
	if body != `{"greeting":"Hello, world!"}` {
		t.Fatalf("off body = %q", body)
	}
}

func TestIntegrationGreetingFlagOnServesNew(t *testing.T) {
	base := newLiveServer(t)
	t.Setenv("FEATURE_NEW_GREETING", "true")
	ResetProvider()
	status, body, _ := getBody(t, base, "/greeting")
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}
	if body != `{"greeting":"Hello, world! (new)"}` {
		t.Fatalf("on body = %q", body)
	}
}

func TestIntegrationHealthzReturnsOK(t *testing.T) {
	base := newLiveServer(t)
	status, body, _ := getBody(t, base, "/healthz")
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}
	if body != `{"status":"ok"}` {
		t.Fatalf("healthz body = %q", body)
	}
}

func TestIntegrationMetricsExposesCounter(t *testing.T) {
	base := newLiveServer(t)
	_, _, _ = getBody(t, base, "/greeting") // record at least one request
	status, body, _ := getBody(t, base, "/metrics")
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}
	if !contains(body, "http_requests_total") {
		t.Fatalf("metrics missing http_requests_total:\n%s", body)
	}
}

// TestIntegrationGreetingLiveFlipOnSameRunningServer is the ★ load-bearing wiring
// proof: install the file-config provider, then rewrite the SAME flag file and
// observe /greeting flip on the SAME running server with NO restart. Proves the
// seam flips the REAL endpoint, not a side process.
func TestIntegrationGreetingLiveFlipOnSameRunningServer(t *testing.T) {
	base := newLiveServer(t)
	flagFile := filepath.Join(t.TempDir(), "flags.json")
	if err := os.WriteFile(flagFile, []byte(`{"new_greeting":false}`), 0o600); err != nil {
		t.Fatal(err)
	}
	SetProvider(FileConfigProvider(flagFile))
	defer ResetProvider()

	_, bodyOff, _ := getBody(t, base, "/greeting")
	if bodyOff != `{"greeting":"Hello, world!"}` {
		t.Fatalf("pre-flip body = %q, want the default greeting", bodyOff)
	}

	// Rewrite the SAME file — no server restart between these two GETs.
	if err := os.WriteFile(flagFile, []byte(`{"new_greeting":true}`), 0o600); err != nil {
		t.Fatal(err)
	}
	_, bodyOn, _ := getBody(t, base, "/greeting")
	if bodyOn != `{"greeting":"Hello, world! (new)"}` {
		t.Fatalf("post-flip body = %q, want the new greeting", bodyOn)
	}
}

func TestIntegrationGetCarriesSecurityHeadersAndNeutralServer(t *testing.T) {
	base := newLiveServer(t)
	status, _, headers := doRequest(t, base, http.MethodGet, "/healthz", nil)
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}
	for name, value := range expectedSecurityHeaders {
		got := headers.Values(name)
		if len(got) != 1 || got[0] != value {
			t.Fatalf("header %s = %v, want exactly [%q]", name, got, value)
		}
	}
	if server := headers.Get("Server"); server != "reference-app" {
		t.Fatalf("Server = %q, want reference-app (no go version leak)", server)
	}
}

func TestIntegrationNonGetReturns404WithSecurityHeaders(t *testing.T) {
	base := newLiveServer(t)
	for _, method := range []string{http.MethodPost, http.MethodPut, http.MethodDelete, http.MethodPatch, http.MethodOptions} {
		status, body, headers := doRequest(t, base, method, "/greeting", nil)
		if status != http.StatusNotFound {
			t.Fatalf("%s status = %d, want 404", method, status)
		}
		if body != `{"error":"not found"}` {
			t.Fatalf("%s body = %q", method, body)
		}
		for name, value := range expectedSecurityHeaders {
			got := headers.Values(name)
			if len(got) != 1 || got[0] != value {
				t.Fatalf("%s header %s = %v, want exactly [%q]", method, name, got, value)
			}
		}
		if server := headers.Get("Server"); server != "reference-app" {
			t.Fatalf("%s Server = %q, want reference-app", method, server)
		}
	}
}

func TestIntegrationHeadReturns404HeadersWithoutBody(t *testing.T) {
	base := newLiveServer(t)
	status, body, headers := doRequest(t, base, http.MethodHead, "/healthz", nil)
	if status != http.StatusNotFound {
		t.Fatalf("HEAD status = %d, want 404", status)
	}
	if body != "" {
		t.Fatalf("HEAD body = %q, want empty (HEAD semantics)", body)
	}
	for name := range expectedSecurityHeaders {
		if headers.Get(name) == "" {
			t.Fatalf("HEAD missing security header %s", name)
		}
	}
}

// lastSpanRequestID polls the trace file for the emitted span, returning its
// request_id attribute. Telemetry is emitted AFTER the response is written, so the
// span can land shortly after the client returns — poll to avoid a flake.
func lastSpanRequestID(t *testing.T, traceFile string) string {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		data, err := os.ReadFile(traceFile) //nolint:gosec // test-controlled temp path
		if err == nil && len(data) > 0 {
			lines := splitLines(string(data))
			if len(lines) > 0 {
				var span map[string]any
				if json.Unmarshal([]byte(lines[len(lines)-1]), &span) == nil {
					if attrs, ok := span["attributes"].(map[string]any); ok {
						if id, ok := attrs["request_id"].(string); ok {
							return id
						}
					}
				}
			}
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("no span was emitted to the trace file within the timeout")
	return ""
}

func TestIntegrationValidInboundRequestIDIsEchoedIntoSpan(t *testing.T) {
	traceFile := filepath.Join(t.TempDir(), "trace.jsonl")
	t.Setenv("OTEL_TRACE_FILE", traceFile)
	base := newLiveServer(t)
	const validID = "abc-123_valid.ID"
	status, _, _ := doRequest(t, base, http.MethodGet, "/healthz", map[string]string{"X-Request-Id": validID})
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}
	if got := lastSpanRequestID(t, traceFile); got != validID {
		t.Fatalf("span request_id = %q, want the honored inbound id %q", got, validID)
	}
}

func TestIntegrationOversizedInboundRequestIDIsReplaced(t *testing.T) {
	traceFile := filepath.Join(t.TempDir(), "trace.jsonl")
	t.Setenv("OTEL_TRACE_FILE", traceFile)
	base := newLiveServer(t)
	bad := ""
	for i := 0; i < 129; i++ {
		bad += "x"
	}
	status, _, _ := doRequest(t, base, http.MethodGet, "/healthz", map[string]string{"X-Request-Id": bad})
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}
	minted := lastSpanRequestID(t, traceFile)
	if minted == bad {
		t.Fatal("oversized inbound id must be rejected, not echoed into the span")
	}
	if len(minted) != 32 {
		t.Fatalf("minted span id = %q (len %d), want 32 hex chars", minted, len(minted))
	}
}

// contains reports whether s contains substr (avoids importing strings for one use
// in a test that is otherwise dependency-lean).
func contains(s, substr string) bool {
	for i := 0; i+len(substr) <= len(s); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}

// splitLines splits on '\n', dropping a trailing empty element.
func splitLines(s string) []string {
	var out []string
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == '\n' {
			if i > start {
				out = append(out, s[start:i])
			}
			start = i + 1
		}
	}
	if start < len(s) {
		out = append(out, s[start:])
	}
	return out
}
