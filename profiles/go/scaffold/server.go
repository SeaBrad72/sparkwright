package main

// App server spine — wires the flags + telemetry modules into a running HTTP server.
//
// The fuller counterpart to health.go: a stdlib-only net/http server that serves the
// real endpoints (/healthz, /metrics, /greeting, 404), stamps security headers on
// EVERY response, and emits per-request telemetry (a structured log, a bounded-
// cardinality metric, and an OTel-semantic span). Mirrors the python reference
// src/app/server.py and the typescript-node src/server.ts.
//
// Health()'s pure core is called (not re-implemented); the flag seam and the
// telemetry primitives are wired here — the ONE place the profile assembles them.
// The handler logic is covered by the integration + e2e suites (the server runs
// in-process); only the socket-binding boot (serve/main) stays thin and largely
// uncovered, exactly like the python reference's serve()/__main__.

import (
	"encoding/json"
	"flag"
	"io"
	"log"
	"net/http"
	"os"
	"regexp"
	"strconv"
	"time"
)

// securityHeaders is stamped on every response — a hardened baseline for a JSON/text
// API that serves no markup: block sniffing/framing, deny all subresources, leak no
// referrer.
var securityHeaders = map[string]string{
	"X-Content-Type-Options":  "nosniff",
	"X-Frame-Options":         "DENY",
	"Content-Security-Policy": "default-src 'none'",
	"Referrer-Policy":         "no-referrer",
}

// requestIDRe bounds an inbound X-Request-Id to a safe token (charset + length).
// Bounding the length + charset rejects malformed/oversized ids defensively — an
// unbounded inbound header must never flow into a log/span attribute verbatim.
var requestIDRe = regexp.MustCompile(`^[A-Za-z0-9._-]{1,128}$`)

// notFoundJSON is the compact 404 body, precomputed (a fixed constant).
var notFoundJSON = []byte(`{"error":"not found"}`)

// jsonBytes marshals a fixed payload to compact JSON bytes (json.Marshal emits no
// inter-token spaces). The payloads are fixed single-key maps whose values carry no
// HTML metacharacters, so json.Marshal's default HTML-escaping never triggers and
// the bytes match the reference server EXACTLY. They also never fail to marshal, so
// the error is explicitly discarded to keep the happy path the only path.
func jsonBytes(payload any) []byte {
	b, _ := json.Marshal(payload) //nolint:errchkjson // fixed maps never fail to marshal
	return b
}

// dispatch routes a request (query stripped) -> (status, content_type, body). Only
// GET is routed; every other method (incl. HEAD) falls through to a hardened JSON
// 404 (method-agnostic, mirroring the reference) so it too carries security headers
// + telemetry via the middleware.
func dispatch(r *http.Request) (int, string, []byte) {
	if r.Method != http.MethodGet {
		return http.StatusNotFound, "application/json", notFoundJSON
	}
	switch r.URL.Path {
	case "/healthz":
		return http.StatusOK, "application/json", jsonBytes(Health())
	case "/metrics":
		return http.StatusOK, "text/plain; version=0.0.4", []byte(RenderMetrics())
	case "/greeting":
		greeting := "Hello, world!"
		if IsEnabled("new_greeting") {
			greeting = "Hello, world! (new)"
		}
		return http.StatusOK, "application/json", jsonBytes(map[string]string{"greeting": greeting})
	default:
		return http.StatusNotFound, "application/json", notFoundJSON
	}
}

// requestID returns a validated inbound X-Request-Id, or a freshly minted random id.
// Minting uses telemetry.randomHex (crypto/rand) — NO external uuid dependency.
func requestID(r *http.Request) string {
	raw := r.Header.Get("X-Request-Id")
	if raw != "" && requestIDRe.MatchString(raw) {
		return raw
	}
	return randomHex(16)
}

// statusRecorder captures the status code written by the inner handler so the
// middleware can record it in telemetry after the response is flushed.
type statusRecorder struct {
	http.ResponseWriter
	status int
	wrote  bool
}

func (s *statusRecorder) WriteHeader(code int) {
	if !s.wrote {
		s.status = code
		s.wrote = true
	}
	s.ResponseWriter.WriteHeader(code)
}

func (s *statusRecorder) Write(b []byte) (int, error) {
	if !s.wrote {
		s.status = http.StatusOK
		s.wrote = true
	}
	return s.ResponseWriter.Write(b)
}

// writeResponse writes the status line, content headers, and (unless a HEAD) the
// body. Security headers are added by the instrument middleware (every response),
// so they are NOT stamped here — avoiding duplicate header emission.
func writeResponse(w http.ResponseWriter, r *http.Request, status int, contentType string, body []byte) {
	withBody := r.Method != http.MethodHead
	w.Header().Set("Content-Type", contentType)
	if withBody {
		w.Header().Set("Content-Length", strconv.Itoa(len(body)))
	} else {
		w.Header().Set("Content-Length", "0")
	}
	w.WriteHeader(status)
	if withBody {
		_, _ = w.Write(body)
	}
}

// dispatchHandler is the inner handler: route + write. Instrumentation (security
// headers + telemetry) is layered by instrument().
func dispatchHandler(w http.ResponseWriter, r *http.Request) {
	status, contentType, body := dispatch(r)
	writeResponse(w, r, status, contentType, body)
}

// instrument wraps a handler with the security-header baseline + neutral Server
// header (stamped in ONE place so even a 404 / non-GET carries them exactly once)
// and per-request telemetry emitted AFTER the response is written.
func instrument(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		startWall := time.Now()
		reqID := requestID(r)

		for name, value := range securityHeaders {
			w.Header().Set(name, value)
		}
		// Neutralize the Server header — no interpreter/library version disclosure.
		w.Header().Set("Server", "reference-app")

		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)

		elapsed := time.Since(startWall)
		latencyMs := float64(elapsed.Nanoseconds()) / 1_000_000.0
		startNano := startWall.UnixNano()
		spanName := r.Method + " " + r.URL.Path // query stripped (cardinality + secret hygiene)

		// NOTE: `path` below is the full request URI INCLUDING any query string. The
		// reference app's routes carry no secrets, but an adopter whose query params
		// can carry tokens/secrets MUST redact `path` here before logging (the span
		// name above already strips the query string).
		Log(map[string]any{
			"request_id": reqID,
			"method":     r.Method,
			"path":       r.RequestURI,
			"status":     rec.status,
			"latency_ms": latencyMs,
		})
		RecordMetric(r.Method, rec.status, latencyMs)
		EmitSpan(BuildSpan(
			spanName,
			startNano,
			startNano+elapsed.Nanoseconds(),
			map[string]string{
				"http.request.method":       r.Method,
				"http.response.status_code": strconv.Itoa(rec.status),
				"request_id":                reqID,
			},
			rec.status,
		))
	})
}

// newHandler assembles the instrumented app handler (routing + security + telemetry).
func newHandler() http.Handler {
	return instrument(http.HandlerFunc(dispatchHandler))
}

// newServer builds the configured HTTP server. A configured server (not
// http.ListenAndServe) sets ReadHeaderTimeout + ReadTimeout — the slow-loris guard
// (also satisfies gosec G114). PORT env (default 8080); bind 0.0.0.0 so a container
// can serve it.
func newServer() *http.Server {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	return &http.Server{
		Addr:              "0.0.0.0:" + port,
		Handler:           newHandler(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		// Belt-and-suspenders beyond the read-side slow-loris guard: WriteTimeout bounds a
		// slow-reader holding a connection open during the response write, IdleTimeout caps
		// idle keep-alive explicitly (rather than inheriting ReadTimeout), and MaxHeaderBytes
		// makes the request-header bound intentional (the logged RequestURI is bounded by it).
		WriteTimeout:   15 * time.Second,
		IdleTimeout:    60 * time.Second,
		MaxHeaderBytes: 1 << 20, // 1 MiB (also net/http's default, set explicitly)
	}
}

// configureProvider is the FLAG_FILE boot gate (the load-bearing live-flip wiring):
// when FLAG_FILE is set, install the file-config live provider BEFORE listening, so
// the running server's /greeting reflects live file flips with no restart. Unset ->
// the env floor (default). Extracted from serve() so this wiring is unit-tested.
func configureProvider() {
	if flagFile := os.Getenv("FLAG_FILE"); flagFile != "" {
		SetProvider(FileConfigProvider(flagFile))
	}
}

// healthCheck probes /healthz over HTTP and returns a process exit code: 0 when the
// endpoint returns 200 with the exact {"status":"ok"} body, else 1. This is the
// container HEALTHCHECK path — distroless static has no shell/curl, so the self-check
// is a flag on the binary (see main).
func healthCheck(url string) int {
	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Get(url) //nolint:gosec // url is app-configured (127.0.0.1:$PORT), not user input
	if err != nil {
		return 1
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return 1
	}
	// Bound the read — a health probe body is a handful of bytes; never slurp.
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1024))
	if err != nil {
		return 1
	}
	if string(body) != string(jsonBytes(Health())) {
		return 1
	}
	return 0
}

// serve starts the blocking app server (script entry point only).
//
// Plain HTTP is intentional: a starter service runs behind a TLS-terminating
// ingress/load balancer (the kit's k8s deploy model — see profiles/go/deploy/), so
// the process serves cleartext on the cluster network. Terminate TLS at the edge, or
// use ListenAndServeTLS if this is internet-facing.
func serve() {
	configureProvider()
	// nosemgrep: go.lang.security.audit.net.use-tls.use-tls -- TLS terminated at the ingress (see above)
	log.Fatal(newServer().ListenAndServe())
}

// main is the thin socket-binding entry (largely excluded from coverage). With
// -healthcheck it probes the running server's /healthz and exits 0/1 (the container
// HEALTHCHECK); otherwise it starts the server.
func main() {
	healthcheck := flag.Bool("healthcheck", false, "probe /healthz and exit 0/1 (container HEALTHCHECK)")
	flag.Parse()
	if *healthcheck {
		port := os.Getenv("PORT")
		if port == "" {
			port = "8080"
		}
		os.Exit(healthCheck("http://127.0.0.1:" + port + "/healthz"))
	}
	serve()
}
