// Package main is a dependency-free (stdlib-only) starter service.
//
// health.go holds ONLY the pure health core; the routing, security middleware,
// per-request telemetry, and socket-binding boot live in server.go (the ONE place
// the profile assembles the flags + telemetry modules into a running server).
// Keeping Health() pure (no I/O) makes it directly unit-testable.
package main

// Health is a pure function returning the service health payload.
// Keeping it pure (no I/O) makes it directly unit-testable and lets both the
// /healthz route (server.go) and the container HEALTHCHECK probe share one source
// of truth for the exact body.
func Health() map[string]string {
	return map[string]string{"status": "ok"}
}
