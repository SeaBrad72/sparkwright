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
RUN uv sync --frozen --no-dev

# ---- runtime: slim, non-root, venv-on-PATH ----
FROM python:3.12-slim-bookworm AS runtime
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PATH="/app/.venv/bin:$PATH"
WORKDIR /app
# ADAPT `app/` to your package directory; copy the resolved venv + the source.
COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app/app ./app
# Numeric UID 65532 (matches the k8s securityContext runAsUser). World-readable copies
# above keep the venv executable for this user. PYTHONDONTWRITEBYTECODE avoids __pycache__
# writes under a read-only root filesystem.
USER 65532
EXPOSE 8000
# NOTE: the container stays UNHEALTHY until your app serves the /healthz endpoint below.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz').status==200 else 1)"]
# ADAPT `app.api:app` to your FastAPI app import path.
CMD ["uvicorn", "app.api:app", "--host", "0.0.0.0", "--port", "8000"]
