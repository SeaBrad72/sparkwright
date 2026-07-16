# syntax=docker/dockerfile:1
# Reference container image for the Python profile.
# COPY & ADAPT: copy to your project root as `Dockerfile`. INERT here in the kit.
# Satisfies DEVELOPMENT-STANDARDS.md §14 (container image supply-chain):
# multi-stage, non-root, minimal base, healthcheck.
#
# Base choice: python:3.12-slim (NOT distroless). The profile targets Python 3.12+, but
# gcr.io/distroless/python3 tracks Debian's interpreter (3.11) — distroless here would
# silently downgrade the runtime. slim gives the declared 3.12 + a shell for HEALTHCHECK.

# ---- builder: resolve + install deps into an isolated venv (never the system python) ----
FROM python:3.12-slim-bookworm AS builder
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy
WORKDIR /app
# uv: fast, reproducible installs from the committed uv.lock.
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project
COPY . .
# --no-editable installs the app package AS A COPY into the venv's site-packages
# (not an `.pth` back to ./src), so the runtime stage's venv is self-contained.
RUN uv sync --frozen --no-dev --no-editable

# ---- runtime: slim, non-root, venv-on-PATH ----
FROM python:3.12-slim-bookworm AS runtime
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PATH="/app/.venv/bin:$PATH"
WORKDIR /app
# The venv is self-contained (--no-editable copied the app package into site-packages),
# so only the resolved venv is needed at runtime — no separate source copy.
COPY --from=builder /app/.venv /app/.venv
# Numeric UID 65532 (matches the k8s securityContext runAsUser). World-readable copies
# above keep the venv executable for this user. PYTHONDONTWRITEBYTECODE avoids __pycache__
# writes under a read-only root filesystem.
# HOST=0.0.0.0 so the app binds all interfaces in-container (reachable via -p); server.py
# reads HOST (env-gated — local dev stays on loopback).
ENV HOST=0.0.0.0
USER 65532
EXPOSE 8000
# NOTE: the container stays UNHEALTHY until your app serves the /healthz endpoint below.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz').status==200 else 1)"]
# Runs the shipped stdlib app server (src/app/server.py `serve()`); no web framework.
CMD ["python", "-m", "app.server"]
