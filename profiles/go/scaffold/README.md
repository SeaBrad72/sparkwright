# app — Go reference service scaffold

A **dependency-free** (stdlib-only) Go service that fills the Go profile to full
DoD-capability parity with the reference: a feature-flag provider seam, a wired
HTTP server (`/healthz`, `/greeting`, `/metrics`), app observability (OTel spans +
Prometheus metrics + structured logs), a data-backed archetype with a DR drill, and
a test pyramid (unit + integration + e2e). It satisfies the Go profile's CI language
pipeline (`profiles/go/ci.yml`) on an empty repo.

> Incept-copied starter — **brownfield-safe**: drop these files into a fresh
> repo (or merge into an existing one) and the CI language gates go green.

## Stdlib-only → clone-green by construction

This scaffold uses **only the Go standard library**. There are therefore:

- **no `require` block** in `go.mod`, and
- **no `go.sum`** (no external modules to verify, nothing to lock).

`go mod download` is a no-op, so there is **no lockfile step to keep in sync** — the *dependency
graph* is green by construction the moment it is cloned. (One caveat: `gate-dep-scan` runs
`govulncheck`, which also scans the Go **stdlib** — a future patch-level stdlib advisory in the
pinned `go1.22.x` could flag the build until you bump the toolchain. That's time-dependent, not a
scaffold defect.)

## Endpoints (served by `server.go`)

| Route       | Response                                                                            |
|-------------|-------------------------------------------------------------------------------------|
| `/healthz`  | `200` `{"status":"ok"}`                                                              |
| `/greeting` | `200` `{"greeting":"Hello, world!"}` — or `…(new)` when the `new_greeting` flag is on |
| `/metrics`  | `200` Prometheus text exposition (`http_requests_total`, duration total)            |
| other       | `404` `{"error":"not found"}`                                                        |

Every response (any method) carries four security headers
(`X-Content-Type-Options`, `X-Frame-Options`, `Content-Security-Policy`,
`Referrer-Policy`) and a neutral `Server: reference-app`, plus a per-request
structured log, a bounded-cardinality metric, and an OTel-semantic span.

## Feature flags (the provider seam)

`flags.go` is the kill-switch seam every profile replicates: a typed registry
(default **OFF**), a `FlagProvider` interface, and the env-floor `envProvider`
(restart-to-toggle, strict `== "true"`). `live_provider.go` is the reference LIVE
provider — a file-config `FlagProvider` that re-reads a JSON file per call, so
rewriting the file flips `/greeting` on the running server with **no restart**
(`FLAG_FILE=/path/to/flags.json`). Content is untrusted and fully fail-safe
(byte-capped read, forbidden-key rejection, strict boolean coercion). See
`docs/operations/feature-flags.md`.

## Layout

| File                   | Role                                                                           |
|------------------------|--------------------------------------------------------------------------------|
| `go.mod`               | `module example.com/app`, `go 1.22`, stdlib-only (no `require`).               |
| `health.go`            | `package main` — the pure `Health()` payload function.                          |
| `server.go`            | the app spine: routing, security-header + telemetry middleware, `FLAG_FILE` boot gate, `-healthcheck` self-check, `serve`/`main`. |
| `flags.go`             | flag registry + `FlagProvider` seam + env-floor provider.                      |
| `live_provider.go`     | reference file-config LIVE provider (live flip, tamper-safe).                   |
| `telemetry.go`         | OTel spans, Prometheus metrics, structured JSON logs (pure primitives).         |
| `observability/`       | `otel-collector.yaml` (local/CI collector) + README.                            |
| `scripts/smoke.sh`     | post-deploy smoke test (liveness + flag kill-switch proof, `:8080`).            |
| `scripts/dr-drill.sh`  | DB backup/restore drill (fail-closed, integrity-checked).                       |
| `.db-backed`           | archetype marker — this profile ships DB-backed (Postgres; see `compose.yaml`). |
| `*_test.go`            | unit tests; `integration_test.go` + `e2e_test.go` are the pyramid's upper tiers. |
| `.gitignore`           | ignores `cover.out` and the built `/app` binary.                                |

## Commands (match `profiles/go/ci.yml`)

```sh
go mod download                                  # no-op (no deps)
golangci-lint run                                # installed by the CI action
go vet ./...                                      # type-check gate
go test -race -coverprofile=cover.out ./...       # test gate (unit + integration + e2e)
go tool cover -func=cover.out                     # coverage report (CI enforces >=80%)
go build ./...                                     # build gate
```

### Coverage gate

CI enforces **≥80%** exactly as in `profiles/go/ci.yml`:

```sh
go tool cover -func=cover.out \
  | awk '/^total:/ {gsub(/%/,"",$3); if ($3+0 < 80) {print "coverage " $3 "% < 80%"; exit 1}}'
```

`server.go`'s request handlers, middleware, routing, flag/telemetry wiring, and the
`-healthcheck` self-check are exercised by the integration + e2e suites (the server
runs in-process via `httptest`), and `flags.go`/`live_provider.go`/`telemetry.go` by
their unit tests. Only the socket-binding boot path (`serve`/`main`) is uncovered by
design, so the `total:` line clears 80% comfortably.

## Verification status

> **Authored to the `profiles/go/ci.yml` contract; stdlib-only so
> green-by-construction. The reference server was booted and driven end-to-end
> (endpoints, live flag flip, `/metrics`, `-healthcheck`) during the profile fill.**
