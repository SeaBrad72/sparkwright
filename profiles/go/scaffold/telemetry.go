package main

// Pure telemetry primitives — spans, bounded-cardinality Prometheus metrics, and
// correlated JSON logs. The importable core the app server calls per request.
//
// Mirrors the python/typescript-node references (telemetry.py / server.ts): OTel-
// semantic spans in the exact scripts/otel-trace.sh schema, Prometheus text
// exposition, and structured logs — deliberately stdlib-only and free of any
// socket/handler code so the logic is unit-tested here and the I/O surface (the
// server) is wired separately. Sinks are chosen by env, exactly like the reference:
// spans go to OTEL_TRACE_FILE if set (append) else stdout; logs carry SERVICE_NAME
// (default "reference-app").

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

// knownMethods is the bounded label set. An unknown (or non-canonical) method is
// bucketed as "other" so a hostile caller cannot explode Prometheus series
// cardinality (path is intentionally NOT a label).
var knownMethods = map[string]bool{
	"GET":     true,
	"POST":    true,
	"PUT":     true,
	"DELETE":  true,
	"PATCH":   true,
	"HEAD":    true,
	"OPTIONS": true,
}

// metricKey is the (method, status) tuple keying the request counter.
type metricKey struct {
	method string
	status int
}

// Module-level counter state, guarded by metricsMu. Reset via ResetMetrics() for
// lifecycle/test isolation.
var (
	metricsMu            sync.Mutex
	requestsTotal        = map[metricKey]int{}
	durationSecondsTotal float64
)

// randomHex returns n cryptographically random bytes as a lowercase hex string.
// crypto/rand.Read only errors when the system entropy source is unavailable — an
// unrecoverable condition — so we panic rather than mint a predictable id.
func randomHex(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		panic("telemetry: crypto/rand unavailable: " + err.Error())
	}
	return hex.EncodeToString(b)
}

// NewSpanIDs returns a fresh (traceID, spanID): 16-byte and 8-byte cryptographic hex.
func NewSpanIDs() (traceID, spanID string) {
	return randomHex(16), randomHex(8)
}

// BuildSpan builds an OTel-semantic span in the reference otel-trace.sh schema.
//
// *_unix_nano are emitted as decimal STRINGS (OTLP/JSON represents them as strings,
// avoiding the float precision loss unix nanos, ~1.8e18, would incur). status.code is
// ERROR for >= 500, else OK. A fresh trace/span id is minted and parent_span_id is nil
// (root span); the server correlates via attributes.
func BuildSpan(name string, startUnixNano, endUnixNano int64, attributes map[string]string, statusCode int) map[string]any {
	traceID, spanID := NewSpanIDs()
	code := "OK"
	if statusCode >= 500 {
		code = "ERROR"
	}
	return map[string]any{
		"trace_id":        traceID,
		"span_id":         spanID,
		"parent_span_id":  nil,
		"name":            name,
		"start_unix_nano": strconv.FormatInt(startUnixNano, 10),
		"end_unix_nano":   strconv.FormatInt(endUnixNano, 10),
		"attributes":      attributes,
		"status":          map[string]any{"code": code},
	}
}

// EmitSpan writes the span as one JSON line to OTEL_TRACE_FILE (append) if set, else
// stdout. It degrades silently on any sink error — telemetry must never break the
// request path it observes.
func EmitSpan(span map[string]any) {
	data, err := json.Marshal(span)
	if err != nil {
		return
	}
	if sink := os.Getenv("OTEL_TRACE_FILE"); sink != "" {
		// #nosec G304 -- the trace sink is an operator-provided env var (OTEL_TRACE_FILE) by design.
		f, err := os.OpenFile(sink, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
		if err != nil {
			return
		}
		defer func() { _ = f.Close() }()
		_, _ = f.Write(append(data, '\n'))
		return
	}
	fmt.Println(string(data))
}

// RecordMetric increments the request counter for (methodLabel, status) and adds to the
// duration total. methodLabel is the method when in knownMethods, else "other" (bounded
// cardinality). The shared counter maps are guarded by metricsMu.
func RecordMetric(method string, status int, latencyMs float64) {
	label := "other"
	if knownMethods[method] {
		label = method
	}
	metricsMu.Lock()
	defer metricsMu.Unlock()
	requestsTotal[metricKey{method: label, status: status}]++
	durationSecondsTotal += latencyMs / 1000.0
}

// escapeLabelValue escapes a Prometheus label value per the text exposition spec
// (\, ", \n). Defensive: an unusual value can never break a series line or inject one.
func escapeLabelValue(value string) string {
	value = strings.ReplaceAll(value, "\\", "\\\\")
	value = strings.ReplaceAll(value, "\"", "\\\"")
	value = strings.ReplaceAll(value, "\n", "\\n")
	return value
}

// RenderMetrics renders the two counters as Prometheus text exposition (trailing
// newline). Series are emitted in a stable (method, status) order so the output is
// deterministic despite Go's randomised map iteration.
func RenderMetrics() string {
	metricsMu.Lock()
	defer metricsMu.Unlock()

	keys := make([]metricKey, 0, len(requestsTotal))
	for k := range requestsTotal {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		if keys[i].method != keys[j].method {
			return keys[i].method < keys[j].method
		}
		return keys[i].status < keys[j].status
	})

	var b strings.Builder
	b.WriteString("# HELP http_requests_total Total number of HTTP requests handled.\n")
	b.WriteString("# TYPE http_requests_total counter\n")
	for _, k := range keys {
		fmt.Fprintf(&b, "http_requests_total{method=\"%s\",status=\"%d\"} %d\n",
			escapeLabelValue(k.method), k.status, requestsTotal[k])
	}
	b.WriteString("# HELP http_request_duration_seconds_total Total accumulated request duration in seconds.\n")
	b.WriteString("# TYPE http_request_duration_seconds_total counter\n")
	fmt.Fprintf(&b, "http_request_duration_seconds_total %s\n",
		strconv.FormatFloat(durationSecondsTotal, 'g', -1, 64))
	return b.String()
}

// ResetMetrics clears the module-level counter state (lifecycle/test helper).
func ResetMetrics() {
	metricsMu.Lock()
	defer metricsMu.Unlock()
	requestsTotal = map[metricKey]int{}
	durationSecondsTotal = 0.0
}

// Log emits one structured JSON log line to stdout: ts (RFC3339 UTC), level "info",
// service (SERVICE_NAME env, default "reference-app"), plus the merged fields.
//
// Never pass request bodies, headers, or PII/secrets in fields.
func Log(fields map[string]any) {
	service := os.Getenv("SERVICE_NAME")
	if service == "" {
		service = "reference-app"
	}
	record := map[string]any{
		"ts":      time.Now().UTC().Format(time.RFC3339),
		"level":   "info",
		"service": service,
	}
	for k, v := range fields {
		record[k] = v
	}
	data, err := json.Marshal(record)
	if err != nil {
		return
	}
	fmt.Println(string(data))
}
