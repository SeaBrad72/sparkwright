# Design — Slice 5c2: Data-Engineering Stack Profile (data-quality-gate-centric)

**Date:** 2026-06-06
**Status:** Approved (brainstorming) — pending spec review
**Author:** Bradley James + agent
**Roadmap:** Second of the two shape-different profiles (after ML, Slice 5c). Followed by Slice 5d (Terraform/IaC), then Slice 6.

---

## 1. Goal

Ship a first-class **data-engineering** stack profile (`profiles/data-engineering/`) for modern ELT: dbt warehouse transformations + Python ingestion + Dagster orchestration, with **data-quality / data-contract validation** as the headline gate (`gate-data-quality`) — the data-eng analog of ML's `gate-eval`. Exercises the conditional 15-factor mechanism for an orchestrated batch pipeline.

## 2. Decisions (from brainstorming)

- **Core stack:** dbt (warehouse SQL transforms) + Python (ingestion/custom) + **Dagster** (orchestration, asset-centric + asset checks).
- **Lint:** sqlfluff (SQL) + ruff (Python). **Type-check:** `dbt parse` + `mypy`. **Data quality:** dbt tests + dbt model contracts + **Great Expectations** (Soda noted as alt) + pandera (Python dataframes).
- **`gate-data-quality`:** a dedicated CI step (beyond the 8) running `dbt build` + GE checks against a CI warehouse, failing on a data-quality violation.
- **Conditional §14/15-factor:** orchestrated batch pipeline → port-binding/concurrency/stateless/disposability **N/A-with-reason**; backing-services (warehouse) is the central dependency; telemetry = lineage + freshness.
- **Version:** **2.6.0** (MINOR, additive).

## 3. Deliverables

| Part | Files |
|------|-------|
| Profile | `profiles/data-engineering.md` (11 sections) |
| Companion | `profiles/data-engineering/{ci.yml,CODEOWNERS,BRANCH-PROTECTION.md}` |
| Meta | `VERSION` → `2.6.0`; `CHANGELOG.md` 2.6.0; `docs/ROADMAP-KIT.md` note |

Profile name = `data-engineering`; `--stack data-engineering` + `profiles/data-engineering/` align so `incept.sh --stack data-engineering` wires CI. Validated by the existing `conformance/ci-gates.sh` (8 ids) + `profile-completeness.sh` — no new conformance logic.

## 4. Detailed design

### 4.1 `profiles/data-engineering.md` (11 sections)

1. **Toolchain:** Python 3.12+ · uv · ruff + sqlfluff (lint) · mypy + `dbt parse` (types/validate) · pytest (+ dbt tests, GE) · dbt-core (transform) · Dagster (orchestration). Warehouse adapters: Postgres/Snowflake/BigQuery.
2. **Scaffold:** `models/{staging,marts}/` (dbt SQL + schema.yml contracts), `dbt_project.yml`/`profiles.yml` (env-var creds), `dagster/` (assets, asset_checks, schedules), `ingestion/` (Python), `great_expectations/` (suites), `tests/`, `.github/workflows/ci.yml`, `pyproject.toml`/`uv.lock`/`.sqlfluff`/`.env.example`.
3. **Standard commands:** install `uv sync --frozen`; lint `sqlfluff lint models/ && ruff check .`; type/validate `dbt parse && mypy .`; test `pytest`; **data-quality `dbt build && great_expectations checkpoint run`**; build `dbt compile`; orchestrate `dagster dev`.
4. **CI/CD:** §14's 7 gates **+ `gate-data-quality`**; points to `profiles/data-engineering/ci.yml`. `gate-type-check`=`dbt parse`+`mypy`; `gate-build`=`dbt compile` (manifest, no warehouse); `gate-data-quality`=`dbt build`+GE against a CI Postgres service.
5. **Security:** warehouse creds via env / `profiles.yml` `env_var()` (never committed); **data governance/PII** central — column-level masking, least-privilege warehouse roles, PII tagging, right-to-erasure, lineage for audit; injection-safe (dbt-parameterized / `ref()`/`source()`); secrets fail-fast.
6. **Testing:** **dbt tests** (schema: not_null/unique/relationships; singular data tests) + **dbt model contracts** (enforced column types) + **Great Expectations** suites (distribution/range/freshness expectations) + **pandera** for Python dataframes + **data-diff** for regression between runs. These are the regression suite; `gate-data-quality` fails on violation.
7. **Resilience & observability:** Dagster **retry policies** + sensors; **data observability** — asset checks, freshness SLAs, **lineage** (Dagster asset graph / OpenLineage); structured logs; alert on failed checks / stale assets; Sentry for code errors.
8. **Data & "migrations":** the warehouse + dbt models are the data layer. **Schema evolution** via versioned dbt models + contracts; **incremental/idempotent models**; backfills as orchestrated runs; never manual prod DDL — changes flow through dbt + review.
9. **Release & deploy:** artifact = the dbt package (compiled manifest) + the Dagster code location. Deploy: promote dbt to the prod warehouse target + deploy Dagster; **provenance attested on the dbt package**. Rollout: dev → staging warehouse → prod; **rollback:** redeploy the previous dbt package / revert models (and re-run affected assets).
10. **Recommended libraries:** dbt-core (+ adapter) · Dagster (+ dagster-dbt) · sqlfluff · Great Expectations (or Soda) · pandera · data-diff · pytest · ruff + mypy · OpenLineage · pydantic-settings · Sentry · Anthropic SDK for any AI features. Default Claude models: `claude-sonnet-4-6`, escalate to Opus for hard reasoning.
11. **Stack-specific gotchas:** warehouse is the central backing service — CI runs `gate-data-quality` against a **Postgres service** (or DuckDB adapter); `dbt parse` is fast offline validation, `dbt build` needs a warehouse; **never commit warehouse creds** — `profiles.yml` uses `env_var()`; commit `packages.yml` + `package-lock.yml`; set the **sqlfluff dialect** to match your warehouse; **conditional §14** — an orchestrated batch pipeline has no port-binding/concurrency/statelessness story (mark N/A-with-reason); the warehouse backing-service + lineage telemetry always apply.

### 4.2 `profiles/data-engineering/ci.yml`

8 standard `gate-*` ids **+ `gate-data-quality`**, on `ubuntu-latest` with a **Postgres service** for the data-quality gate:
- `gate-install`=`uv sync --frozen`; `gate-lint`=`uv run sqlfluff lint models/ && uv run ruff check .`; `gate-type-check`=`uv run dbt parse && uv run mypy .`; `gate-test`=`uv run pytest --cov --cov-fail-under=80`; `gate-build`=`uv run dbt compile`; **`gate-data-quality`**=`uv run dbt build && uv run great_expectations checkpoint run` (against the Postgres service; non-zero on violation); `gate-secret-scan`=gitleaks; `gate-dep-scan`=`uvx pip-audit`; `gate-sbom`=`uvx cyclonedx-py environment --output-format JSON --outfile sbom.json` (upload `sbom.json`); `gate-provenance`=attest `target/manifest.json` (release path).
- A `services: postgres:16` block + `DBT_PROFILES`/env so `dbt build` has a warehouse. `ci-gates.sh` requires the 8 standard ids; `gate-data-quality` is an allowed extra.

### 4.3 Companions
`CODEOWNERS` + `BRANCH-PROTECTION.md` derived from the Python reference (retitled "data-engineering profile").

## 5. Validation / testing

- `sh conformance/ci-gates.sh profiles/data-engineering/ci.yml` → exit 0 (8 ids; gate-data-quality extra fine).
- `sh conformance/profile-completeness.sh` → passes all 9 profiles.
- `profiles/data-engineering/ci.yml` valid YAML; SBOM upload path matches output.
- **incept wiring:** `incept.sh --noninteractive --stack data-engineering` into a temp copy wires CI + `inception-done.sh` passes; the wired `ci.yml` passes `ci-gates.sh`.
- Existing 8 profiles unchanged (additive). Kit CI green; check-links covers the new doc.

## 6. Risks & mitigations

- **`gate-data-quality` needs a warehouse** — the reference uses a CI Postgres service; documented that `dbt parse`/`dbt compile` are the offline gates and `dbt build` needs the service. Kit CI doesn't execute the reference (only ci-gates checks ids).
- **SBOM/coverage accuracy (Slice-5 lesson):** `cyclonedx-py environment --outfile sbom.json` → upload `sbom.json`; coverage `--cov-fail-under=80`. Same as the validated Python/ML profiles.
- **Conditional §14 mis-applied:** §11 + §4 explicitly mark batch factors N/A-with-reason while keeping the warehouse backing-service + lineage telemetry in force.
- **sqlfluff dialect mismatch:** §11 notes setting the dialect to the warehouse; the reference `.sqlfluff` defaults to postgres.

## 7. Out of scope

Terraform/IaC (Slice 5d) · enterprise addendum (Slice 6) · Airflow/Prefect variants (Dagster is the default; adopters swap) · executing the pipeline in kit CI (adopter-side).

## 8. Definition of Done

- `profiles/data-engineering.md` (11 sections, no `[...]`) + `profiles/data-engineering/{ci.yml,CODEOWNERS,BRANCH-PROTECTION.md}`; `ci.yml` passes `ci-gates.sh` (8 ids) + declares `gate-data-quality`.
- `profile-completeness.sh` green over all 9 profiles.
- `incept.sh --stack data-engineering` wires CI + passes `inception-done.sh` (verified in temp).
- Kit CI green; existing 8 profiles unchanged.
- `VERSION` = `2.6.0`; CHANGELOG 2.6.0; roadmap note (Slice 5 profile family complete).
- Feature branch → PR; **human-ratified before merge**.
