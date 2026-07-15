package main

// E2E: a full user journey against the assembled service.
//
// Liveness -> the greeting feature -> a not-found route, proving end-to-end
// behaviour in-suite. DISTINCT from post-deploy scripts/smoke.sh (which proves a
// deployed container is alive); this is the runnable in-process oracle. Mirrors the
// python reference tests/e2e/test_journey.py.

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func e2eGet(t *testing.T, base, path string) (int, string) {
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
	return resp.StatusCode, string(body)
}

func TestE2EServiceJourneyLiveGreetingThen404(t *testing.T) {
	ResetProvider()
	srv := httptest.NewServer(newHandler())
	t.Cleanup(func() {
		srv.Close()
		ResetProvider()
	})
	base := srv.URL

	status, body := e2eGet(t, base, "/healthz")
	if status != http.StatusOK || body != `{"status":"ok"}` {
		t.Fatalf("liveness: status=%d body=%q", status, body)
	}

	status, body = e2eGet(t, base, "/greeting")
	if status != http.StatusOK || !strings.HasPrefix(body, `{"greeting":"Hello, world!`) {
		t.Fatalf("greeting: status=%d body=%q", status, body)
	}

	status, body = e2eGet(t, base, "/nope")
	if status != http.StatusNotFound || body != `{"error":"not found"}` {
		t.Fatalf("not-found: status=%d body=%q", status, body)
	}
}
