# Stack Profile — Python

> Reference profile. The concrete *how* for the universal `DEVELOPMENT-STANDARDS.md` on a Python stack. Copy/adapt per project; record selection as ADR-000.

**Stack:** Python 3.12+ · uv · FastAPI · PostgreSQL + SQLAlchemy/Alembic · pytest · hosted (container / Fly / Railway)
**Status:** reference

---

## Best for / Avoid when

**Best for:** Data, ML, scripting, APIs, automation, glue; rapid development.
**Avoid when:** Perf-critical hot loops without native extensions; mobile front-ends.

Choosing a stack? Compare all profiles → [../docs/STACK-SELECTION.md](../docs/STACK-SELECTION.md).

---

## 1. Toolchain
- **Runtime:** Python 3.12+ · **Package/deps:** `uv` (lockfile `uv.lock` committed; exact pins for prod)
- **Format/lint:** `ruff` (format + lint; replaces black/isort/flake8) · **Types:** `mypy` (strict)
- **Tests:** `pytest` + `pytest-cov` (coverage gate) · **Test quality:** `hypothesis` (property-based) + `mutmut`/`cosmic-ray` (mutation, critical paths/nightly — `docs/operations/test-quality.md`) · **Build:** `uv build` (wheel + sdist)

## 2. Project scaffold
```
src/<package>/{api,services,models,schemas,lib}/
tests/{unit,integration,e2e}/
docs/architecture/            # ADRs (incl. ADR-000)
.github/workflows/ci.yml
pyproject.toml · uv.lock · .env.example · .gitignore · ruff.toml · mypy.ini
```
Baselines: `pyproject.toml` with ruff + mypy config; `[tool.coverage]` fail_under = 80; `mypy` strict = true.

## 3. Standard commands
```
install:       uv sync --frozen
dev:           uv run uvicorn <package>.api:app --reload
test:          uv run pytest
test:coverage: uv run pytest --cov --cov-fail-under=80
lint:          uv run ruff check .
type-check:    uv run mypy .
build:         uv build
start:         uv run uvicorn <package>.api:app
```

## 4. CI/CD pipeline
Implements the 7 required gates of `DEVELOPMENT-STANDARDS.md` §14. Drop-in reference files live in **`profiles/python/`**:
- **`ci.yml`** → copy to `.github/workflows/ci.yml`. `uv sync` → ruff → mypy → pytest+coverage(≥80) → `uv build` → secret-scan (gitleaks) → dependency scan (`pip-audit`) → SBOM (CycloneDX-py) → build provenance.
- **`CODEOWNERS`** → copy to `.github/CODEOWNERS`. · **`BRANCH-PROTECTION.md`** → how to protect `main`.

Conformance: `sh conformance/ci-gates.sh profiles/python/ci.yml`.

## 5. Security implementation
- **Env/secrets:** `pydantic-settings` (`BaseSettings`) with fail-fast; `.env` gitignored; commit `.env.example`.
- **Validation:** **Pydantic** models at every boundary; validate on create *and* update.
- **Injection-safe data:** **SQLAlchemy** (parameterized) / `text()` with bound params — never f-string SQL.
- **AuthN/Z:** `passlib[bcrypt]` (≥12 rounds); `pyjwt` minimal claims + short expiry; verify on protected routes.
- **HTTP headers / CORS:** FastAPI middleware (`secure` or `starlette` middleware); restrict CORS origins.
- **Rate limiting:** `slowapi` (skip in test mode).

## 6. Testing
- **Convention:** `tests/` mirrors `src/`; `test_*.py`. Arrange-Act-Assert; describe behavior.
- **Integration:** `pytest` + `httpx.AsyncClient` against the app; assert status + body + DB state (Testcontainers or a test DB).
- **E2E:** Playwright (Python) against the dev server.
- **AI evals:** an `evals/` dir with JSONL datasets; a runner scoring against a rubric (LLM-as-judge via the Anthropic SDK, pinned judge) that fails below threshold in CI.

## 7. Resilience & observability
- **Retry/backoff:** `tenacity`; **circuit breaker:** `pybreaker`.
- **Logging:** `structlog` (JSON in prod). **Error tracking:** Sentry (`sentry-sdk`). **Metrics:** `prometheus-client` / OpenTelemetry.

## 8. Data & migrations
- **SQLAlchemy + Alembic.** Expand-contract: add → backfill (batched) → switch reads → drop old in a later migration. Every migration reversible (`downgrade`); no manual prod DDL.

## 9. Release & deploy
- **Build artifact:** wheel + container image. **Deploy:** container to Fly/Railway/K8s; merge to `main` → deploy.
- **Feature flags:** env-backed or a flag service; flag-off = fastest rollback.
- **Rollout:** staging → prod; **rollback:** redeploy previous image / revert + redeploy.

## 10. Recommended libraries
Pydantic + pydantic-settings (validation/config) · SQLAlchemy + Alembic (ORM/migrations) · FastAPI (web) · passlib[bcrypt] + pyjwt (auth) · tenacity + pybreaker (resilience) · structlog + sentry-sdk (observability) · pytest + pytest-cov + httpx + Testcontainers (testing) · Anthropic SDK (`anthropic`) for AI features. Default Claude models: `claude-sonnet-4-6` (workhorse), escalate to Opus for hard reasoning.

## 11. Stack-specific gotchas
- Commit `uv.lock`; use `uv sync --frozen` in CI for reproducible installs.
- `ruff` subsumes black/isort/flake8 — don't add them too.
- Keep `mypy` strict; don't silence with broad `# type: ignore`.
- `pip-audit` reads the locked environment — run after `uv sync`.
- Async: don't block the event loop; use async DB drivers (asyncpg) with SQLAlchemy 2.0.

---

**Last Updated:** 2026-06-06
