# app — Go starter scaffold

A minimal, **dependency-free** Go service that satisfies the Go profile's CI
language pipeline (`profiles/go/ci.yml`) on an empty repo, plus a `/healthz`
liveness surface and its test.

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

## Layout

| File             | Role                                                                 |
|------------------|----------------------------------------------------------------------|
| `go.mod`         | `module example.com/app`, `go 1.22`, stdlib-only (no `require`).      |
| `health.go`      | `package main` — pure `Health()`, `/healthz` handler, thin `main()`. |
| `health_test.go` | `Health()` unit test + `httptest` handler test (`200` + JSON body).  |
| `.gitignore`     | ignores `cover.out` and the built `/app` binary.                     |

## Commands (match `profiles/go/ci.yml`)

```sh
go mod download                                  # no-op (no deps)
golangci-lint run                                # installed by the CI action
go vet ./...                                      # type-check gate
go test -race -coverprofile=cover.out ./...       # test gate
go tool cover -func=cover.out                     # coverage report (CI enforces >=80%)
go build ./...                                     # build gate
```

### Coverage gate

CI enforces **≥80%** exactly as in `profiles/go/ci.yml`:

```sh
go tool cover -func=cover.out \
  | awk '/^total:/ {gsub(/%/,"",$3); if ($3+0 < 80) {print "coverage " $3 "% < 80%"; exit 1}}'
```

`Health()` and the `/healthz` handler (incl. `newMux`/`healthzHandler`) are
fully exercised by the tests on the happy path — the handler ignores the
never-failing encode error explicitly, so it has no uncovered branch. Only the
one-line `main()` wrapper is uncovered, so the `total:` line clears 80%.

## Verification status

> **Authored to the `profiles/go/ci.yml` contract; stdlib-only so
> green-by-construction, but not executed here (go toolchain absent).**
