package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// dispatch is the pure router (query stripped, telemetry-free). These unit tests
// pin the EXACT bytes each route returns so a refactor cannot silently drift a body.

func TestDispatchHealthz(t *testing.T) {
	status, ctype, body := dispatch(httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}
	if ctype != "application/json" {
		t.Fatalf("content-type = %q, want application/json", ctype)
	}
	if string(body) != `{"status":"ok"}` {
		t.Fatalf("body = %q, want {\"status\":\"ok\"}", body)
	}
}

func TestDispatchMetrics(t *testing.T) {
	status, ctype, body := dispatch(httptest.NewRequest(http.MethodGet, "/metrics", nil))
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200", status)
	}
	if ctype != "text/plain; version=0.0.4" {
		t.Fatalf("content-type = %q, want prometheus text", ctype)
	}
	if len(body) == 0 {
		t.Fatal("metrics body is empty")
	}
}

func TestDispatchGreetingFlagOff(t *testing.T) {
	t.Cleanup(ResetProvider)
	ResetProvider()
	_, ctype, body := dispatch(httptest.NewRequest(http.MethodGet, "/greeting", nil))
	if ctype != "application/json" {
		t.Fatalf("content-type = %q, want application/json", ctype)
	}
	if string(body) != `{"greeting":"Hello, world!"}` {
		t.Fatalf("off body = %q", body)
	}
}

func TestDispatchGreetingFlagOn(t *testing.T) {
	t.Cleanup(ResetProvider)
	t.Setenv("FEATURE_NEW_GREETING", "true")
	ResetProvider()
	_, _, body := dispatch(httptest.NewRequest(http.MethodGet, "/greeting", nil))
	if string(body) != `{"greeting":"Hello, world! (new)"}` {
		t.Fatalf("on body = %q", body)
	}
}

func TestDispatchGreetingStripsQuery(t *testing.T) {
	t.Cleanup(ResetProvider)
	ResetProvider()
	status, _, body := dispatch(httptest.NewRequest(http.MethodGet, "/greeting?token=secret", nil))
	if status != http.StatusOK {
		t.Fatalf("status = %d, want 200 (query must not defeat routing)", status)
	}
	if string(body) != `{"greeting":"Hello, world!"}` {
		t.Fatalf("body = %q", body)
	}
}

func TestDispatchUnknownRouteIs404(t *testing.T) {
	status, ctype, body := dispatch(httptest.NewRequest(http.MethodGet, "/nope", nil))
	if status != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", status)
	}
	if ctype != "application/json" {
		t.Fatalf("content-type = %q, want application/json", ctype)
	}
	if string(body) != `{"error":"not found"}` {
		t.Fatalf("body = %q", body)
	}
}

func TestDispatchNonGetIs404(t *testing.T) {
	for _, method := range []string{http.MethodPost, http.MethodPut, http.MethodDelete, http.MethodPatch, http.MethodOptions, http.MethodHead} {
		status, _, body := dispatch(httptest.NewRequest(method, "/healthz", nil))
		if status != http.StatusNotFound {
			t.Fatalf("%s status = %d, want 404", method, status)
		}
		if string(body) != `{"error":"not found"}` {
			t.Fatalf("%s body = %q", method, body)
		}
	}
}

// requestID: honor a safe inbound X-Request-Id, else mint a bounded random hex id.

func TestRequestIDValidIsHonored(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	req.Header.Set("X-Request-Id", "abc-123_valid.ID")
	if got := requestID(req); got != "abc-123_valid.ID" {
		t.Fatalf("requestID = %q, want the honored inbound id", got)
	}
}

func TestRequestIDOversizedIsMinted(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	bad := ""
	for i := 0; i < 129; i++ {
		bad += "x"
	}
	req.Header.Set("X-Request-Id", bad)
	got := requestID(req)
	if got == bad {
		t.Fatal("oversized inbound id must be rejected, not echoed")
	}
	if len(got) != 32 { // randomHex(16) -> 32 hex chars
		t.Fatalf("minted id = %q (len %d), want 32 hex chars", got, len(got))
	}
}

func TestRequestIDMissingIsMinted(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	if got := requestID(req); len(got) != 32 {
		t.Fatalf("minted id = %q (len %d), want 32 hex chars", got, len(got))
	}
}

func TestRequestIDIllegalCharIsMinted(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	req.Header.Set("X-Request-Id", "has space")
	if got := requestID(req); got == "has space" {
		t.Fatal("id with an illegal char must be rejected")
	}
}

// newServer: the socket config posture (slow-loris guard + container bind).

func TestNewServerConfig(t *testing.T) {
	srv := newServer()
	if srv.Addr != "0.0.0.0:8080" {
		t.Fatalf("Addr = %q, want 0.0.0.0:8080", srv.Addr)
	}
	if srv.ReadHeaderTimeout != 5*time.Second {
		t.Fatalf("ReadHeaderTimeout = %v, want 5s", srv.ReadHeaderTimeout)
	}
	if srv.ReadTimeout != 15*time.Second {
		t.Fatalf("ReadTimeout = %v, want 15s", srv.ReadTimeout)
	}
	if srv.Handler == nil {
		t.Fatal("Handler is nil")
	}
}

func TestNewServerHonorsPORT(t *testing.T) {
	t.Setenv("PORT", "9137")
	if got := newServer().Addr; got != "0.0.0.0:9137" {
		t.Fatalf("Addr = %q, want 0.0.0.0:9137", got)
	}
}

// configureProvider: the FLAG_FILE boot gate (the live-flip wiring).

func TestConfigureProviderInstallsFileProvider(t *testing.T) {
	t.Cleanup(ResetProvider)
	flagFile := filepath.Join(t.TempDir(), "flags.json")
	if err := os.WriteFile(flagFile, []byte(`{"new_greeting":true}`), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("FLAG_FILE", flagFile)
	configureProvider()
	if !IsEnabled("new_greeting") {
		t.Fatal("FLAG_FILE set -> file provider should be active and resolve true")
	}
}

func TestConfigureProviderNoFlagFileKeepsEnvFloor(t *testing.T) {
	t.Cleanup(ResetProvider)
	os.Unsetenv("FLAG_FILE")
	ResetProvider()
	configureProvider()
	// Env floor: unset FEATURE_NEW_GREETING -> registry default OFF.
	if IsEnabled("new_greeting") {
		t.Fatal("no FLAG_FILE -> env floor, default OFF")
	}
}

// healthCheck: the container HEALTHCHECK probe (distroless has no shell/curl).

func TestHealthCheckPassesAgainstLiveServer(t *testing.T) {
	srv := httptest.NewServer(newHandler())
	t.Cleanup(srv.Close)
	if code := healthCheck(srv.URL + "/healthz"); code != 0 {
		t.Fatalf("healthCheck exit = %d, want 0", code)
	}
}

func TestHealthCheckFailsOnNotFound(t *testing.T) {
	srv := httptest.NewServer(newHandler())
	t.Cleanup(srv.Close)
	if code := healthCheck(srv.URL + "/nope"); code != 1 {
		t.Fatalf("healthCheck exit = %d, want 1 (404 must fail the probe)", code)
	}
}

func TestHealthCheckFailsOnUnreachable(t *testing.T) {
	// A port with no listener: the GET errors -> non-zero exit.
	if code := healthCheck("http://127.0.0.1:1/healthz"); code != 1 {
		t.Fatalf("healthCheck exit = %d, want 1 (unreachable must fail)", code)
	}
}

// jsonBytes: compact, HTML-unescaped bytes (matches the reference exactly).

func TestJSONBytesCompact(t *testing.T) {
	got := jsonBytes(map[string]string{"greeting": "Hello, world!"})
	if string(got) != `{"greeting":"Hello, world!"}` {
		t.Fatalf("jsonBytes = %q, want compact single-key object", got)
	}
	// It must be valid JSON that round-trips.
	var back map[string]string
	if err := json.Unmarshal(got, &back); err != nil {
		t.Fatalf("jsonBytes emitted invalid JSON: %v", err)
	}
}
