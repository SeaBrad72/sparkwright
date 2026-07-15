# syntax=docker/dockerfile:1
# Reference container image for the Go profile.
# COPY & ADAPT: copy to your project root as `Dockerfile`. INERT here in the kit.
# Satisfies DEVELOPMENT-STANDARDS.md §14 (container image supply-chain):
# multi-stage, non-root, minimal base, healthcheck.

# ---- builder: full Go toolchain, never shipped ----
FROM golang:1.22-bookworm AS builder
WORKDIR /src
# Stdlib-only scaffold: there is no go.sum (no external modules). COPY only go.mod;
# `go mod download` is a no-op. If you add dependencies, run `go mod tidy` to generate
# a go.sum and change this to `COPY go.mod go.sum ./`.
COPY go.mod ./
RUN go mod download
COPY . .
# CGO_ENABLED=0 → a fully static binary that runs on the distroless 'static' base.
# The scaffold is a flat `package main` at the repo root, so build `.`; if you
# restructure to a cmd/ layout, change this to your main package path (e.g. ./cmd/server).
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/server .

# ---- runtime: distroless static, non-root by construction ----
FROM gcr.io/distroless/static-debian12:nonroot AS runtime
WORKDIR /app
COPY --from=builder /out/server /app/server
# Numeric UID (distroless 'nonroot' = 65532): stays non-root even on :debug/:latest tags
# and matches the k8s securityContext runAsUser.
USER 65532
EXPOSE 8080
# Distroless has no shell; use exec form. The binary must exit non-zero on a failed self-check.
# NOTE: the container stays UNHEALTHY until you implement this `-healthcheck` self-check.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["/app/server", "-healthcheck"]
CMD ["/app/server"]
