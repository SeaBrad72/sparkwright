# syntax=docker/dockerfile:1
# Reference container image for the Rust profile.
# COPY & ADAPT: copy to your project root as `Dockerfile`. INERT here in the kit.
# Satisfies DEVELOPMENT-STANDARDS.md §14 (container image supply-chain):
# multi-stage, non-root, minimal base, healthcheck.

# ---- builder: full Rust toolchain, never shipped ----
FROM rust:1-bookworm AS builder
WORKDIR /src
# Cache deps: copy manifests first, then the source.
COPY Cargo.toml Cargo.lock ./
COPY . .
# ADAPT the binary name (`server`) to your crate's [[bin]] name.
RUN cargo build --release --locked --bin server \
 && cp target/release/server /out-server

# ---- runtime: distroless cc (glibc + libgcc for dynamically-linked Rust) ----
# Use 'cc' (not 'static') because a typical axum + sqlx binary links glibc. If you build a
# fully static musl target (x86_64-unknown-linux-musl), switch to distroless/static instead.
FROM gcr.io/distroless/cc-debian12:nonroot AS runtime
WORKDIR /app
COPY --from=builder /out-server /app/server
# Numeric UID (distroless 'nonroot' = 65532): non-root by construction; matches k8s runAsUser.
USER 65532
EXPOSE 8080
# Distroless has no shell; use exec form. The binary must exit non-zero on a failed self-check.
# NOTE: the container stays UNHEALTHY until you implement this `--healthcheck` self-check.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["/app/server", "--healthcheck"]
CMD ["/app/server"]
