# Stack Profile — Data Engineering (dbt + Dagster)

> Reference profile. The concrete *how* for the universal `DEVELOPMENT-STANDARDS.md` on a modern ELT/data-engineering stack — warehouse transformations, orchestration, and data-quality contracts. Copy/adapt per project; record selection as ADR-000. The headline addition is the **data-quality gate**.

**Stack:** Python 3.12+ · uv · dbt-core · Dagster · PostgreSQL/Snowflake/BigQuery · Great Expectations · hosted (orchestrated batch; container/K8s)
**Status:** reference

---

## Best for / Avoid when

**Best for:** ETL/ELT, batch & stream pipelines, warehouse/lakehouse work.
**Avoid when:** Interactive apps / request-serving APIs.

Choosing a stack? Compare all profiles → [../docs/STACK-SELECTION.md](../docs/STACK-SELECTION.md).

---

## 1. Toolchain
- **Runtime:** Python 3.12+ · **Deps:** `uv` (lockfile `uv.lock`)
- **Transform:** **dbt-core** (warehouse SQL) · **Orchestrate:** **Dagster** (asset-centric + asset checks)
- **Format/lint:** `sqlfluff` (SQL) + `ruff` (Python) · **Validate/types:** `dbt parse` + `mypy`
- **Tests/data-quality:** `pytest` · dbt tests + dbt contracts · **Great Expectations** · `pandera` · data-diff
- **Test quality:** here the **data-quality suite IS the bar** (GE + dbt tests = the `gate-data-quality` gate); add Hypothesis + mutmut for the **Python transform logic** (`docs/operations/test-quality.md`)
- **Inner loop:** `pre-commit` (sqlfluff + ruff; `pytest-testmon` for Python) — fast feedback before CI (`docs/operations/dev-inner-loop.md`)

## 2. Project scaffold
```
models/{staging,marts}/        # dbt SQL + schema.yml (tests + contracts)
dbt_project.yml · profiles.yml  # profiles.yml uses env_var() for creds
dagster/{assets.py,asset_checks.py,schedules.py}
ingestion/                      # Python extract/load
great_expectations/             # GE suites + checkpoints
tests/{unit,integration}/
docs/architecture/              # ADRs (incl. ADR-000)
.github/workflows/ci.yml
pyproject.toml · uv.lock · .sqlfluff · packages.yml · .env.example · .gitignore
```
Baselines: `.sqlfluff` dialect = your warehouse (default postgres); dbt model **contracts** enforced; coverage fail_under = 80; GE checkpoint `main`.

## 3. Standard commands
```
install:        uv sync --frozen
dev:            uv run dagster dev
test:           uv run pytest
test:coverage:  uv run pytest --cov --cov-fail-under=80
data-quality:   uv run dbt build && uv run great_expectations checkpoint run main
lint:           uv run sqlfluff lint models/ && uv run ruff check .
type-check:     uv run dbt parse && uv run mypy .
build:          uv run dbt compile
```

## 4. CI/CD pipeline
Implements §14's 7 required gates **plus a data-quality gate**. Drop-in reference files live in **`profiles/data-engineering/`**:
- **`ci.yml`** → copy to `.github/workflows/ci.yml`. sqlfluff+ruff → `dbt parse`+mypy (type-check) → pytest+coverage(≥80) → `dbt compile` (build) → **`gate-data-quality` (dbt build + GE against a CI warehouse)** → gitleaks → pip-audit → CycloneDX-py SBOM → provenance. Runs a **Postgres service** for the data-quality gate.
- **`CODEOWNERS`**, **`BRANCH-PROTECTION.md`** → governance companions.

Conformance: `sh conformance/ci-gates.sh profiles/data-engineering/ci.yml` (8 standard gates; `gate-data-quality` is the additional data-eng gate). Note: SQL isn't typed, so `gate-type-check`=`dbt parse` (validates the model DAG) + `mypy`; `gate-build`=`dbt compile` (offline manifest).

## 5. Security implementation
- **Env/secrets:** warehouse creds via `profiles.yml` `env_var(...)` + environment; **never commit creds**; fail-fast on missing; commit `.env.example`.
- **Data governance / PII:** column-level masking; **least-privilege warehouse roles** (CI uses a scoped role); PII tagging; right-to-erasure; **lineage** retained for audit (Dagster asset graph / OpenLineage).
- **Injection-safe:** dbt `ref()`/`source()` + parameterized; never string-build SQL from untrusted input.
- **Validation:** dbt contracts + GE at ingestion/marts boundaries; pandera on Python dataframes.
- **Static analysis & licenses (conditional gates — `docs/operations/security-scanning.md`):** SAST via **Semgrep + `bandit`** (`gate-sast`); license policy via `scripts/license-check.sh` over the CycloneDX SBOM (`gate-license`, stack-neutral default — upgrade per the ladder if needed).

## 6. Testing
- **dbt tests:** schema tests (not_null/unique/relationships) + singular data tests.
- **dbt contracts:** enforced column names/types on published models.
- **Great Expectations:** suites for distributions/ranges/freshness; a `main` checkpoint gates in CI.
- **pandera:** schema checks on Python dataframes; **data-diff:** regression between runs.
- **pytest:** Python ingestion/transform logic. These are the regression suite — `gate-data-quality` fails the build on a violation.

## 7. Resilience & observability
- **Orchestration:** Dagster **retry policies**, sensors, and **asset checks**; freshness SLAs.
- **Data observability:** **lineage** (Dagster asset graph / OpenLineage); alert on failed checks / stale assets.
- **Logging:** structured (JSON). **Error tracking:** Sentry. **Metrics:** pipeline run/freshness via OpenTelemetry.

## 8. Data & "migrations"
- The warehouse + dbt models **are** the data layer. **Schema evolution** via versioned dbt models + contracts; **incremental, idempotent models**; backfills as orchestrated runs. Never manual prod DDL — all changes flow through dbt + review.

## 9. Release & deploy
- **Artifact:** the dbt package (compiled `target/manifest.json`) + the Dagster code location. **Build provenance attested on the dbt package.**
- **Rollout:** dev → staging warehouse → prod target; promote dbt + deploy Dagster. **Rollback:** redeploy the previous dbt package / revert models and re-run affected assets.
- **Container/deploy (reference-pattern, not a drop-in):** this profile ships **no generic web-Dockerfile** — the deploy unit is an *orchestrated job / code-location image* (Dagster/dbt runner), not a long-running request/response service. When you containerize that runner, follow the service-profile pattern (multi-stage, non-root, `gate-image-sbom` + digest-bound `gate-image-provenance`) — `profiles/python/{Dockerfile,ci.yml,deploy/}` is the closest reference. `conformance/container-supply-chain.sh` validates it once a Dockerfile exists.

## 10. Recommended libraries
dbt-core (+ warehouse adapter) · Dagster (+ dagster-dbt) · sqlfluff · Great Expectations (or Soda) · pandera · data-diff · pytest + pytest-cov · ruff + mypy · OpenLineage · pydantic-settings · Sentry · Anthropic SDK for any AI features. Default Claude models: `claude-sonnet-4-6` (workhorse), escalate to Opus for hard reasoning.

## 11. Stack-specific gotchas
- The **warehouse is the central backing service** — CI runs `gate-data-quality` against a **Postgres service** (or a DuckDB adapter for lightweight runs).
- `dbt parse` / `dbt compile` validate **offline** (no warehouse); `dbt build` needs the warehouse — that's why it lives in the data-quality gate with the service.
- **Never commit warehouse creds** — `profiles.yml` uses `env_var()`; commit `packages.yml` + `package-lock.yml`.
- Set the **sqlfluff dialect** to match your warehouse (default here: postgres).
- **Conditional §14/15-factor:** an orchestrated batch pipeline has no port-binding/concurrency/statelessness/disposability story — mark those **N/A with a one-line reason**. The warehouse backing-service and lineage telemetry always apply.

---

**Last Updated:** 2026-06-06
