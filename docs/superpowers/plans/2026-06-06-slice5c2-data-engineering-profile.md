# Slice 5c2: Data-Engineering Stack Profile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a first-class **data-engineering** stack profile (`profiles/data-engineering/`) — dbt + Dagster + Python — whose CI carries a `gate-data-quality` step (dbt build + Great Expectations), alongside the 8 standard §14 gates.

**Architecture:** Profile slice on branch `feature/slice-5c2-data-engineering-profile`, mirroring the Slice 5/5c pattern. `profiles/data-engineering.md` (11 sections) + `profiles/data-engineering/ci.yml` (8 standard `gate-*` ids **+ `gate-data-quality`**, with a Postgres service) + companions derived from the Python reference. Validated by the existing `conformance/ci-gates.sh` (8 ids; gate-data-quality is an allowed extra) and `profile-completeness.sh` — no new conformance logic.

**Tech Stack:** Markdown, GitHub Actions YAML, POSIX `sh`. Profile: Python 3.12 · uv · ruff + sqlfluff · mypy + dbt parse · pytest · dbt-core · Dagster · Great Expectations · pandera. Spec: `docs/superpowers/specs/2026-06-06-slice5c2-data-engineering-profile-design.md`.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `profiles/data-engineering.md` (new) | Data-engineering profile, 11 sections |
| `profiles/data-engineering/ci.yml` (new) | Reference CI (8 gates + `gate-data-quality` + Postgres service) |
| `profiles/data-engineering/CODEOWNERS` (new) | Review routing (derived from Python ref) |
| `profiles/data-engineering/BRANCH-PROTECTION.md` (new) | Branch protection (derived from Python ref) |
| `VERSION` `CHANGELOG.md` `docs/ROADMAP-KIT.md` (edit) | 2.6.0; changelog; roadmap note |

**Precondition:** on branch `feature/slice-5c2-data-engineering-profile`. The committed `profiles/python/CODEOWNERS` + `profiles/python/BRANCH-PROTECTION.md` are the source for the derived companions.

---

### Task 1: profiles/data-engineering.md

**Files:** Create `profiles/data-engineering.md`

- [ ] **Step 1: Write the profile** — create `profiles/data-engineering.md` with exactly this content (write LITERAL triple-backtick fences where scaffold + commands blocks are shown):

```markdown
# Stack Profile — Data Engineering (dbt + Dagster)

> Reference profile. The concrete *how* for the universal `DEVELOPMENT-STANDARDS.md` on a modern ELT/data-engineering stack — warehouse transformations, orchestration, and data-quality contracts. Copy/adapt per project; record selection as ADR-000. The headline addition is the **data-quality gate**.

**Stack:** Python 3.12+ · uv · dbt-core · Dagster · PostgreSQL/Snowflake/BigQuery · Great Expectations · hosted (orchestrated batch; container/K8s)
**Status:** reference

---

## 1. Toolchain
- **Runtime:** Python 3.12+ · **Deps:** `uv` (lockfile `uv.lock`)
- **Transform:** **dbt-core** (warehouse SQL) · **Orchestrate:** **Dagster** (asset-centric + asset checks)
- **Format/lint:** `sqlfluff` (SQL) + `ruff` (Python) · **Validate/types:** `dbt parse` + `mypy`
- **Tests/data-quality:** `pytest` · dbt tests + dbt contracts · **Great Expectations** · `pandera` · data-diff

## 2. Project scaffold
\`\`\`
models/{staging,marts}/        # dbt SQL + schema.yml (tests + contracts)
dbt_project.yml · profiles.yml  # profiles.yml uses env_var() for creds
dagster/{assets.py,asset_checks.py,schedules.py}
ingestion/                      # Python extract/load
great_expectations/             # GE suites + checkpoints
tests/{unit,integration}/
docs/architecture/              # ADRs (incl. ADR-000)
.github/workflows/ci.yml
pyproject.toml · uv.lock · .sqlfluff · packages.yml · .env.example · .gitignore
\`\`\`
Baselines: `.sqlfluff` dialect = your warehouse (default postgres); dbt model **contracts** enforced; coverage fail_under = 80; GE checkpoint `main`.

## 3. Standard commands
\`\`\`
install:        uv sync --frozen
dev:            uv run dagster dev
test:           uv run pytest
test:coverage:  uv run pytest --cov --cov-fail-under=80
data-quality:   uv run dbt build && uv run great_expectations checkpoint run main
lint:           uv run sqlfluff lint models/ && uv run ruff check .
type-check:     uv run dbt parse && uv run mypy .
build:          uv run dbt compile
\`\`\`

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

## 10. Recommended libraries
dbt-core (+ warehouse adapter) · Dagster (+ dagster-dbt) · sqlfluff · Great Expectations (or Soda) · pandera · data-diff · pytest + pytest-cov · ruff + mypy · OpenLineage · pydantic-settings · Sentry · Anthropic SDK for any AI features. Default Claude models: `claude-sonnet-4-6` (workhorse), escalate to Opus for hard reasoning.

## 11. Stack-specific gotchas
- The **warehouse is the central backing service** — CI runs `gate-data-quality` against a **Postgres service** (or a DuckDB adapter for lightweight runs).
- `dbt parse` / `dbt compile` validate **offline** (no warehouse); `dbt build` needs the warehouse — that's why it lives in the data-quality gate with the service.
- **Never commit warehouse creds** — `profiles.yml` uses `env_var()`; commit `packages.yml` + `package-lock.yml`.
- Set the **sqlfluff dialect** to match your warehouse (default here: postgres).
- **Conditional §14/15-factor:** an orchestrated batch pipeline has no port-binding/concurrency/statelessness/disposability story — mark those **N/A with a one-line reason**. The warehouse backing-service and lineage telemetry always apply.
\`\`\`

---

**Last Updated:** 2026-06-06
```

- [ ] **Step 2: Verify and commit**

```bash
cd ~/Development/agentic-sdlc-kit
i=1; ok=1; while [ "$i" -le 11 ]; do grep -Eq "^## ${i}\. " profiles/data-engineering.md || { echo "missing §$i"; ok=0; }; i=$((i+1)); done; [ "$ok" -eq 1 ] && echo "11 sections OK"
grep -Fq '[...]' profiles/data-engineering.md && echo "FAIL placeholder" || echo "no [...] placeholder"
git add profiles/data-engineering.md
git commit -m "feat: add data-engineering stack profile (dbt + Dagster, data-quality gate)"
```
Expected: `11 sections OK`; `no [...] placeholder`.

---

### Task 2: profiles/data-engineering/ (ci.yml + CODEOWNERS + BRANCH-PROTECTION)

**Files:** Create `profiles/data-engineering/ci.yml`, `profiles/data-engineering/CODEOWNERS`, `profiles/data-engineering/BRANCH-PROTECTION.md`

- [ ] **Step 1: Write `profiles/data-engineering/ci.yml`** with exactly this content:

```yaml
# Reference CI pipeline for the data-engineering profile.
# COPY & ADAPT: copy to your project's .github/workflows/ci.yml. Inert here in the kit.
# Carries the 8 standardized gate-* ids (DEVELOPMENT-STANDARDS.md §14) PLUS gate-data-quality.
# conformance/ci-gates.sh asserts the 8; gate-data-quality is an allowed extra.
# A Postgres service backs the data-quality gate (dbt build needs a warehouse).
# HARDENING: pin uses:/tool versions for production.
name: CI

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read
  id-token: write
  attestations: write

jobs:
  ci:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_USER: dbt
          POSTGRES_PASSWORD: dbt
          POSTGRES_DB: analytics
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    env:
      DBT_HOST: localhost
      DBT_USER: dbt
      DBT_PASSWORD: dbt
      DBT_DBNAME: analytics
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: astral-sh/setup-uv@v5
        with:
          enable-cache: true
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install dependencies
        id: gate-install
        run: uv sync --frozen

      - name: Lint
        id: gate-lint
        run: |
          uv run sqlfluff lint models/
          uv run ruff check .

      - name: Type-check / validate
        id: gate-type-check
        run: |
          uv run dbt parse
          uv run mypy .

      - name: Test + coverage (>=80%)
        id: gate-test
        run: uv run pytest --cov --cov-fail-under=80

      - name: Build (dbt compile)
        id: gate-build
        run: uv run dbt compile

      - name: Data quality (dbt build + Great Expectations)
        id: gate-data-quality
        run: |
          uv run dbt build
          uv run great_expectations checkpoint run main

      - name: Secret scan
        id: gate-secret-scan
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          # GITLEAKS_LICENSE: ${{ secrets.GITLEAKS_LICENSE }}  # required for org repos

      - name: Dependency vulnerability scan
        id: gate-dep-scan
        run: uvx pip-audit

      - name: Generate SBOM (CycloneDX)
        id: gate-sbom
        run: uvx cyclonedx-py environment --output-format JSON --outfile sbom.json

      - name: Upload SBOM
        uses: actions/upload-artifact@v4
        with:
          name: sbom
          path: sbom.json

      - name: Attest build provenance
        id: gate-provenance
        # Attest the compiled dbt package on the release path.
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        uses: actions/attest-build-provenance@v1
        with:
          subject-path: target/manifest.json
```

- [ ] **Step 2: Derive the governance companions**

```bash
cd ~/Development/agentic-sdlc-kit
sed 's/Python profile/data-engineering profile/' profiles/python/CODEOWNERS > profiles/data-engineering/CODEOWNERS
sed 's/(Python profile)/(data-engineering profile)/' profiles/python/BRANCH-PROTECTION.md > profiles/data-engineering/BRANCH-PROTECTION.md
```

- [ ] **Step 3: Verify and commit**

```bash
cd ~/Development/agentic-sdlc-kit
sh conformance/ci-gates.sh profiles/data-engineering/ci.yml; echo "exit=$?"
grep -q "id: gate-data-quality" profiles/data-engineering/ci.yml && echo "gate-data-quality present"
ruby -ryaml -e "YAML.load_file('profiles/data-engineering/ci.yml'); puts 'YAML OK'"
test -f profiles/data-engineering/CODEOWNERS && grep -q "required_status_checks" profiles/data-engineering/BRANCH-PROTECTION.md && echo "companions OK"
git add profiles/data-engineering/ci.yml profiles/data-engineering/CODEOWNERS profiles/data-engineering/BRANCH-PROTECTION.md
git commit -m "feat: add data-engineering reference CI (8 gates + gate-data-quality + Postgres service)"
```
Expected: ci-gates `OK ... declares all required CI gates`, `exit=0`; `gate-data-quality present`; `YAML OK`; `companions OK`.

---

### Task 3: VERSION + CHANGELOG + ROADMAP (2.6.0)

**Files:** Modify `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-KIT.md`

- [ ] **Step 1: Bump VERSION** — overwrite `VERSION` with exactly one line + trailing newline:

```
2.6.0
```

- [ ] **Step 2: Add the 2.6.0 CHANGELOG entry** — in `CHANGELOG.md`, find this exact line:

```
## [2.5.0] - 2026-06-06
```

Insert IMMEDIATELY BEFORE it:

```
## [2.6.0] - 2026-06-06

Slice 5c2 — Data-engineering stack profile. Completes the profile family (9 stacks). The data-eng analog of the ML eval gate: a data-quality gate.

### Added
- `profiles/data-engineering.md` + `profiles/data-engineering/` (`ci.yml`, `CODEOWNERS`, `BRANCH-PROTECTION.md`) — dbt-core (warehouse transforms) · Dagster (orchestration, asset checks) · Python ingestion · sqlfluff + ruff (lint) · dbt parse + mypy (validate) · dbt tests/contracts + Great Expectations + pandera + data-diff (data quality) · gitleaks · pip-audit · CycloneDX-py + provenance.
- A dedicated **`gate-data-quality`** step in the data-engineering `ci.yml` (`dbt build` + Great Expectations checkpoint, run against a CI Postgres service) that fails the build on a data-quality violation — the data-eng analog of ML's `gate-eval`. `conformance/ci-gates.sh` validates the 8 standard gates; `gate-data-quality` is an allowed extra.

### Note
`gate-type-check` = `dbt parse` + `mypy` (SQL has no compiler; parsing the model DAG is the validate analog). The profile applies the **conditional 15-factor** mechanism: an orchestrated batch pipeline marks port-binding/concurrency/stateless/disposability N/A-with-reason; the warehouse backing-service + lineage telemetry apply. `incept.sh --stack data-engineering` wires the profile's CI.

```

- [ ] **Step 3: Add the 2.6.0 link reference** — in `CHANGELOG.md`, find:

```
[2.5.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.5.0
```

Replace with:

```
[2.6.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.6.0
[2.5.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.5.0
```

- [ ] **Step 4: Update the roadmap** — in `docs/ROADMAP-KIT.md`, find this exact line:

```
| 5c2 | **Data-engineering profile** *(next)* | `profiles/_TEMPLATE.md` | `profiles/data-engineering/` (dbt/orchestration/data-contracts; shape-different gate model) | `conformance/profile-completeness.sh` |
```

Replace with:

```
| 5c2 ✅ | **Data-engineering profile** *(shipped v2.6.0)* | `profiles/_TEMPLATE.md` | `profiles/data-engineering/` — dbt + Dagster + Python; `gate-data-quality` (dbt build + Great Expectations) | `conformance/profile-completeness.sh` |
```

- [ ] **Step 5: Verify and commit**

```bash
cd ~/Development/agentic-sdlc-kit
cat VERSION
grep -c "## \[2.6.0\]" CHANGELOG.md
grep -c "shipped v2.6.0" docs/ROADMAP-KIT.md
git add VERSION CHANGELOG.md docs/ROADMAP-KIT.md
git commit -m "release: 2.6.0 — Slice 5c2 data-engineering profile (changelog + roadmap)"
```
Expected: `2.6.0`; `1`; `1`.

---

### Task 4: Final validation + PR

**Files:** none created; verification + PR only.

- [ ] **Step 1: Full conformance sweep (9 profiles)**

```bash
cd ~/Development/agentic-sdlc-kit
sh conformance/profile-completeness.sh; echo "exit=$?"
for p in typescript-node python java-spring dotnet go rust kotlin ml data-engineering; do sh conformance/ci-gates.sh "profiles/$p/ci.yml" >/dev/null && echo "ci-gates $p OK"; done
grep -q "id: gate-data-quality" profiles/data-engineering/ci.yml && echo "gate-data-quality present"
sh conformance/agent-autonomy.sh >/dev/null && echo "agent-autonomy OK"
sh conformance/check-links.sh >/dev/null && echo "check-links OK"
```
Expected: profile-completeness all PASS + `exit=0`; `ci-gates <p> OK` for all 9; `gate-data-quality present`; agent-autonomy OK; check-links OK.

- [ ] **Step 2: incept wires the data-engineering profile (end-to-end)**

```bash
cd ~/Development/agentic-sdlc-kit
tmp=$(mktemp -d); git archive HEAD | tar -x -C "$tmp"
( cd "$tmp" && sh scripts/incept.sh --noninteractive --name DemoDE --intent-owner "CI" --stack data-engineering --backlog md ) >/dev/null
sh conformance/inception-done.sh "$tmp" >/dev/null && echo "incept --stack data-engineering -> inception-done OK"
sh conformance/ci-gates.sh "$tmp/.github/workflows/ci.yml" >/dev/null && echo "wired CI satisfies §14"
grep -q "id: gate-data-quality" "$tmp/.github/workflows/ci.yml" && echo "wired CI carries gate-data-quality"
rm -rf "$tmp"
```
Expected: all three OK lines.

- [ ] **Step 3: Existing 8 profiles untouched (additive)**

```bash
cd ~/Development/agentic-sdlc-kit
git diff --stat main..HEAD -- profiles/typescript-node.md profiles/python.md profiles/java-spring.md profiles/dotnet.md profiles/go.md profiles/rust.md profiles/kotlin.md profiles/ml.md | tail -1
echo "(empty above = unchanged)"
```
Expected: no diff line.

- [ ] **Step 4: Push and open the PR**

```bash
cd ~/Development/agentic-sdlc-kit
git push -u origin feature/slice-5c2-data-engineering-profile
gh pr create --title "Slice 5c2: data-engineering profile — dbt+Dagster, gate-data-quality (v2.6.0)" --body "$(cat <<'EOF'
## Summary
A first-class **data-engineering** profile (modern ELT) — completes the profile family at **9 stacks**.

- **`profiles/data-engineering.md`** + `profiles/data-engineering/` — dbt-core · Dagster · Python · sqlfluff+ruff · dbt parse+mypy · dbt tests/contracts + Great Expectations + pandera + data-diff · gitleaks · pip-audit · CycloneDX-py + attest.
- **`gate-data-quality`** in the `ci.yml` — `dbt build` + GE checkpoint against a CI Postgres service, fails the build on a data-quality violation (the data-eng analog of ML's `gate-eval`). `ci-gates.sh` validates the 8 standard gates; `gate-data-quality` is an allowed extra.
- **`gate-type-check` = `dbt parse` + `mypy`** (SQL has no compiler; parsing the model DAG is the validate analog).
- **Conditional 15-factor:** orchestrated batch → port-binding/concurrency/stateless N/A-with-reason; warehouse backing-service + lineage telemetry apply.
- **Release** 2.6.0 (MINOR). Additive — the existing 8 profiles are untouched.

## Verified
`ci.yml` passes `ci-gates.sh` (8 ids; gate-data-quality extra); `profile-completeness.sh` passes all 9; `incept --stack data-engineering` wires CI (carrying gate-data-quality) + passes `inception-done.sh` + §14. SBOM path matches output. Zero new conformance logic.

## Ratification
Additive profile. **Human ratification required before merge.**

Spec: `docs/superpowers/specs/2026-06-06-slice5c2-data-engineering-profile-design.md`
Plan: `docs/superpowers/plans/2026-06-06-slice5c2-data-engineering-profile.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
Expected: branch pushed; PR URL printed; CI starts.

- [ ] **Step 5: Report CI status, stop for ratification**

```bash
cd ~/Development/agentic-sdlc-kit
sleep 15
gh pr checks 2>&1 | head
```
Do **not** merge. Report PR URL + CI results.

---

## Self-Review (completed by plan author)

**Spec coverage:** §3 deliverables mapped — data-engineering.md→T1, ci.yml+companions→T2, VERSION/CHANGELOG/ROADMAP→T3, validation/PR→T4. Spec §4.2 (8 gates + gate-data-quality + Postgres service, dbt parse type-check, dbt compile build) → T2 ci.yml. Spec §5 conditional-§14 + data-governance → ml.md §5/§11 equivalents in data-engineering.md §5/§11 (T1). Spec §5 validation (ci-gates, completeness over 9, incept wiring, additive) → T4.

**Placeholder scan:** no TBD/TODO in the plan. The dbt/GE invocations (`dbt build`, `great_expectations checkpoint run main`) are concrete reference commands the adopter's project config backs (consistent with reference-impl philosophy; documented in §2/§6/§11). SBOM upload path `sbom.json` matches `--outfile sbom.json` (Slice-5b lesson). No `[...]` in the profile (completeness check verifies).

**Type/name consistency:** the `ci.yml` declares all 8 standard `gate-*` ids `ci-gates.sh` requires, plus `gate-data-quality`; profile name `data-engineering` matches the companion dir + `--stack data-engineering` (T4). Companion derivation uses the Python reference's actual header strings. The Postgres `env` (DBT_HOST/USER/PASSWORD/DBNAME) is consistent with a `profiles.yml` using `env_var()` as §5 describes.
