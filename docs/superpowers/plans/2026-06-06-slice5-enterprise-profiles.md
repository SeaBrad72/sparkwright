# Slice 5: Enterprise Profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship conformant **Python** and **Java/Spring** stack profiles (each: a `profiles/<stack>.md` with all 11 sections + a companion `ci.yml`/`CODEOWNERS`/`BRANCH-PROTECTION.md` mirroring the TS profile) and a `profile-completeness` conformance check guarding every profile.

**Architecture:** Contract/reference/conformance slice on branch `feature/slice-5-enterprise-profiles`. Each companion `ci.yml` uses the 8 standardized `gate-*` step ids so `conformance/ci-gates.sh` validates it unchanged. `conformance/profile-completeness.sh` asserts every `profiles/*.md` fills the 11 `_TEMPLATE.md` sections (no `[...]` left) and that companion workflows pass ci-gates. Kit CI checks declaration + completeness only (it does not execute Python/JVM pipelines). `incept.sh --stack python|java-spring` wires the new profiles' CI.

**Tech Stack:** Markdown, GitHub Actions YAML, POSIX `sh`. Profiles: Python (uv·ruff·mypy·pytest·pip-audit·CycloneDX-py), Java (Maven·Spring Boot·Spotless/Checkstyle·JUnit5/JaCoCo·OWASP·CycloneDX-maven). Spec: `docs/superpowers/specs/2026-06-06-slice5-enterprise-profiles-design.md`.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `profiles/python.md` (new) | Python profile, 11 sections |
| `profiles/python/ci.yml` `CODEOWNERS` `BRANCH-PROTECTION.md` (new) | Python reference pipeline + governance |
| `profiles/java-spring.md` (new) | Java/Spring profile, 11 sections |
| `profiles/java-spring/ci.yml` `CODEOWNERS` `BRANCH-PROTECTION.md` (new) | Java reference pipeline + governance |
| `conformance/profile-completeness.sh` (new) | Guard: every profile complete + ci.yml conformant |
| `conformance/README.md` (edit) | Index profile-completeness; drop from "future" |
| `.github/workflows/ci.yml` (edit) | Run profile-completeness in the conformance job |
| `VERSION` `CHANGELOG.md` `docs/ROADMAP-KIT.md` (edit) | 2.3.0; changelog; Slice 5 done |

**Precondition:** on branch `feature/slice-5-enterprise-profiles` (spec commit is here).

---

### Task 1: profiles/python.md

**Files:**
- Create: `profiles/python.md`

- [ ] **Step 1: Write the profile**

Create `profiles/python.md` with exactly this content:

```markdown
# Stack Profile — Python

> Reference profile. The concrete *how* for the universal `DEVELOPMENT-STANDARDS.md` on a Python stack. Copy/adapt per project; record selection as ADR-000.

**Stack:** Python 3.12+ · uv · FastAPI · PostgreSQL + SQLAlchemy/Alembic · pytest · hosted (container / Fly / Railway)
**Status:** reference

---

## 1. Toolchain
- **Runtime:** Python 3.12+ · **Package/deps:** `uv` (lockfile `uv.lock` committed; exact pins for prod)
- **Format/lint:** `ruff` (format + lint; replaces black/isort/flake8) · **Types:** `mypy` (strict)
- **Tests:** `pytest` + `pytest-cov` (coverage gate) · **Build:** `uv build` (wheel + sdist)

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
```

- [ ] **Step 2: Verify (11 sections, no leftover placeholder) and commit**

```bash
cd ~/Development/agentic-sdlc-kit
i=1; ok=1; while [ "$i" -le 11 ]; do grep -Eq "^## ${i}\. " profiles/python.md || { echo "missing §$i"; ok=0; }; i=$((i+1)); done; [ "$ok" -eq 1 ] && echo "11 sections OK"
grep -Fq '[...]' profiles/python.md && echo "FAIL placeholder" || echo "no [...] placeholder"
git add profiles/python.md
git commit -m "feat: add Python stack profile"
```
Expected: `11 sections OK`; `no [...] placeholder`.

---

### Task 2: profiles/python/ (ci.yml + CODEOWNERS + BRANCH-PROTECTION.md)

**Files:**
- Create: `profiles/python/ci.yml`, `profiles/python/CODEOWNERS`, `profiles/python/BRANCH-PROTECTION.md`

- [ ] **Step 1: Write ci.yml**

Create `profiles/python/ci.yml` with exactly this content:

```yaml
# Reference CI pipeline for the Python profile.
# COPY & ADAPT: copy to your project's .github/workflows/ci.yml. Inert here in the kit.
# Each quality gate carries a standardized `id: gate-*` that conformance/ci-gates.sh asserts.
# Satisfies DEVELOPMENT-STANDARDS.md §14.
#
# HARDENING (recommended for production): pin every `uses:` to a commit SHA and pin tool
# versions (uvx tool@version). Left on major tags / latest here for reference readability.
name: CI

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read
  id-token: write       # build-provenance attestation
  attestations: write   # build-provenance attestation

jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0   # full history for secret scanning

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
        run: uv run ruff check .

      - name: Type-check
        id: gate-type-check
        run: uv run mypy .

      - name: Test + coverage (>=80%)
        id: gate-test
        run: uv run pytest --cov --cov-fail-under=80

      - name: Build
        id: gate-build
        run: uv build

      - name: Secret scan
        id: gate-secret-scan
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          # Organization-owned repos additionally require:
          # GITLEAKS_LICENSE: ${{ secrets.GITLEAKS_LICENSE }}

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
        # Provenance attaches to a published build artifact (the wheel/sdist in dist/),
        # so it runs on the release/build (push-to-main) path.
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        uses: actions/attest-build-provenance@v1
        with:
          subject-path: dist/**
```

- [ ] **Step 2: Write CODEOWNERS**

Create `profiles/python/CODEOWNERS` with exactly this content:

```
# Reference CODEOWNERS for the Python profile.
# COPY & ADAPT: copy to .github/CODEOWNERS (or repo root). Routes review so the
# builder is never the sole reviewer/merger (DEVELOPMENT-PROCESS.md §2, §12).
# Replace @your-org/* with real teams.

*            @your-org/engineering
/.github/    @your-org/platform
/src/        @your-org/engineering
```

- [ ] **Step 3: Write BRANCH-PROTECTION.md**

Create `profiles/python/BRANCH-PROTECTION.md` with exactly this content:

```markdown
# Branch Protection — reference setup (Python profile)

Enforces the §14 contract at the repo boundary: `main` protected, green CI to merge, builder ≠ sole merger. COPY & ADAPT — replace `OWNER/REPO` and team handles.

## What to require
- The CI status check (`ci`) must pass before merge.
- At least 1 approving review from someone other than the author.
- Stale approvals dismissed on new commits.
- Branch up to date before merge.
- (Org/plan-dependent) CODEOWNERS review required; self-merge disallowed.

## Apply via GitHub CLI
Run **after** the CI workflow has run at least once (so the check name `ci` is registered):

\`\`\`bash
gh api -X PUT repos/OWNER/REPO/branches/main/protection --input - <<'JSON'
{
  "required_status_checks": { "strict": true, "contexts": ["ci"] },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true
  },
  "restrictions": null
}
JSON
\`\`\`

> "Builder ≠ sole merger" is enforced by required reviews + CODEOWNERS. GitHub cannot strictly forbid every user from merging their own PR on all plans; on GitHub Enterprise use rulesets / required reviewers. Document the policy in the project `CLAUDE.md` regardless.
```

- [ ] **Step 4: Verify the workflow satisfies §14 and parses; commit**

```bash
cd ~/Development/agentic-sdlc-kit
sh conformance/ci-gates.sh profiles/python/ci.yml; echo "exit=$?"
ruby -ryaml -e "YAML.load_file('profiles/python/ci.yml'); puts 'YAML OK'"
test -f profiles/python/CODEOWNERS && grep -q "required_status_checks" profiles/python/BRANCH-PROTECTION.md && echo "companions OK"
git add profiles/python/ci.yml profiles/python/CODEOWNERS profiles/python/BRANCH-PROTECTION.md
git commit -m "feat: add Python reference CI pipeline + governance companions"
```
Expected: ci-gates `OK ... declares all required CI gates`, `exit=0`; `YAML OK`; `companions OK`.

---

### Task 3: profiles/java-spring.md

**Files:**
- Create: `profiles/java-spring.md`

- [ ] **Step 1: Write the profile**

Create `profiles/java-spring.md` with exactly this content:

```markdown
# Stack Profile — Java / Spring Boot

> Reference profile. The concrete *how* for the universal `DEVELOPMENT-STANDARDS.md` on a Java/Spring stack. Copy/adapt per project; record selection as ADR-000.

**Stack:** Java 21 (LTS) · Maven · Spring Boot 3.x · PostgreSQL + JPA/Hibernate + Flyway · JUnit 5 · hosted (container / K8s)
**Status:** reference

---

## 1. Toolchain
- **Runtime:** JDK 21 (Temurin) · **Build/deps:** Maven via wrapper `./mvnw` (reproducible)
- **Format/lint:** Spotless (format) + Checkstyle (lint) · **Types:** the compiler (`mvn compile` = type-checking)
- **Tests:** JUnit 5 + JaCoCo (coverage gate) · **Build:** `mvn package`

## 2. Project scaffold
```
src/main/java/<group>/{api,service,domain,repo,config}/
src/test/java/<group>/
src/main/resources/{application.yml,db/migration/}   # Flyway migrations
docs/architecture/            # ADRs (incl. ADR-000)
.github/workflows/ci.yml
pom.xml · mvnw · .mvn/ · .env.example · .gitignore · checkstyle.xml
```
Baselines: `pom.xml` with spotless-maven-plugin, checkstyle, jacoco-maven-plugin (rule: line ≥0.80, fails `verify`), cyclonedx-maven-plugin, dependency-check-maven.

## 3. Standard commands
```
install:       ./mvnw -q -DskipTests dependency:go-offline
dev:           ./mvnw spring-boot:run
test:          ./mvnw test
test:coverage: ./mvnw verify           # JaCoCo check binds to verify (≥80%)
lint:          ./mvnw spotless:check checkstyle:check
type-check:    ./mvnw -q compile
build:         ./mvnw -q -DskipTests package
start:         java -jar target/*.jar
```

## 4. CI/CD pipeline
Implements the 7 required gates of `DEVELOPMENT-STANDARDS.md` §14. Drop-in reference files live in **`profiles/java-spring/`**:
- **`ci.yml`** → copy to `.github/workflows/ci.yml`. spotless/checkstyle → `mvn compile` (type-check) → JUnit5+JaCoCo(≥80) → `mvn package` → secret-scan (gitleaks) → dependency scan (OWASP) → SBOM (CycloneDX-maven) → build provenance.
- **`CODEOWNERS`** → copy to `.github/CODEOWNERS`. · **`BRANCH-PROTECTION.md`** → how to protect `main`.

Conformance: `sh conformance/ci-gates.sh profiles/java-spring/ci.yml`. Note: Java has no separate type-check step — compilation **is** type-checking, so `gate-type-check`=`mvn compile` and `gate-build`=`mvn package`.

## 5. Security implementation
- **Env/secrets:** Spring `@Value`/`Environment` / `application.yml` with env placeholders; fail-fast on missing; `.env` gitignored; commit `.env.example`.
- **Validation:** **Jakarta Bean Validation** (`@Valid`, `@NotNull`, …) on request DTOs; validate create *and* update.
- **Injection-safe data:** **Spring Data JPA** / parameterized queries; never string-concatenate JPQL/SQL.
- **AuthN/Z:** **Spring Security** — BCrypt password encoder; JWT (minimal claims, short expiry); method/route authorization server-side.
- **HTTP headers / CSRF:** Spring Security default security headers; CSRF tokens for cookie-auth forms.
- **Rate limiting:** Resilience4j `RateLimiter` or a gateway (skip/relax in test profile).

## 6. Testing
- **Convention:** `src/test/java` mirrors `src/main/java`; `*Test.java`. Arrange-Act-Assert.
- **Integration:** `@SpringBootTest` + **Testcontainers** (real Postgres); assert status + body + DB state.
- **E2E:** Playwright/REST-assured against the running app.
- **AI evals:** an `evals/` module with JSONL datasets; a runner scoring against a rubric (LLM-as-judge via the Anthropic Java SDK, pinned judge) failing below threshold in CI.

## 7. Resilience & observability
- **Retry/backoff + circuit breaker:** **Resilience4j**.
- **Logging:** SLF4J + Logback (JSON encoder in prod). **Metrics/health/traces:** Micrometer + Spring Boot Actuator + OpenTelemetry. **Error tracking:** Sentry.

## 8. Data & migrations
- **JPA/Hibernate + Flyway.** Versioned SQL in `db/migration` (`V<n>__desc.sql`). Expand-contract: add → backfill → switch reads → drop old later. Reversible/repeatable where supported; no manual prod DDL.

## 9. Release & deploy
- **Build artifact:** executable jar + container image (Jib/buildpacks). **Deploy:** container to K8s/Fly; merge to `main` → deploy.
- **Feature flags:** a flag service or Spring `@ConfigurationProperties`; flag-off = fastest rollback.
- **Rollout:** staging → prod; **rollback:** redeploy previous image / revert + redeploy.

## 10. Recommended libraries
Spring Boot starters (web, security, data-jpa, validation, actuator) · Resilience4j (resilience) · Flyway (migrations) · Micrometer + Sentry (observability) · JUnit 5 + JaCoCo + Testcontainers + REST-assured (testing) · cyclonedx-maven-plugin + dependency-check-maven (supply-chain) · Anthropic Java SDK for AI features. Default Claude models: `claude-sonnet-4-6` (workhorse), escalate to Opus for hard reasoning.

## 11. Stack-specific gotchas
- Use `./mvnw` (the wrapper) everywhere for reproducible builds; commit `.mvn/wrapper`.
- JaCoCo coverage check binds to the `verify` phase — `mvn test` alone won't enforce it; CI runs the check explicitly.
- OWASP dependency-check's first run downloads the NVD database (slow) — cache it in CI.
- Spotless `apply` fixes formatting; CI uses `check` (fails on drift).
- Use Spring profiles (`application-<env>.yml`) for env config — never env conditionals in code.

---

**Last Updated:** 2026-06-06
```

- [ ] **Step 2: Verify and commit**

```bash
cd ~/Development/agentic-sdlc-kit
i=1; ok=1; while [ "$i" -le 11 ]; do grep -Eq "^## ${i}\. " profiles/java-spring.md || { echo "missing §$i"; ok=0; }; i=$((i+1)); done; [ "$ok" -eq 1 ] && echo "11 sections OK"
grep -Fq '[...]' profiles/java-spring.md && echo "FAIL placeholder" || echo "no [...] placeholder"
git add profiles/java-spring.md
git commit -m "feat: add Java/Spring stack profile"
```
Expected: `11 sections OK`; `no [...] placeholder`.

---

### Task 4: profiles/java-spring/ (ci.yml + CODEOWNERS + BRANCH-PROTECTION.md)

**Files:**
- Create: `profiles/java-spring/ci.yml`, `profiles/java-spring/CODEOWNERS`, `profiles/java-spring/BRANCH-PROTECTION.md`

- [ ] **Step 1: Write ci.yml**

Create `profiles/java-spring/ci.yml` with exactly this content:

```yaml
# Reference CI pipeline for the Java/Spring profile.
# COPY & ADAPT: copy to your project's .github/workflows/ci.yml. Inert here in the kit.
# Each quality gate carries a standardized `id: gate-*` that conformance/ci-gates.sh asserts.
# Satisfies DEVELOPMENT-STANDARDS.md §14. NOTE: compilation IS type-checking in Java, so
# gate-type-check = `mvn compile` and gate-build = `mvn package`.
#
# HARDENING (recommended for production): pin every `uses:` to a commit SHA and pin Maven
# plugin versions in pom.xml. Left on major tags here for reference readability.
name: CI

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read
  id-token: write       # build-provenance attestation
  attestations: write   # build-provenance attestation

jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0   # full history for secret scanning

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'
          cache: maven

      - name: Lint / format check
        id: gate-lint
        run: ./mvnw -q spotless:check checkstyle:check

      - name: Type-check (compile)
        id: gate-type-check
        run: ./mvnw -q compile

      - name: Test + coverage (JaCoCo >=80%)
        id: gate-test
        run: ./mvnw -q verify   # JaCoCo check binds to verify

      - name: Build
        id: gate-build
        run: ./mvnw -q -DskipTests package

      - name: Secret scan
        id: gate-secret-scan
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          # Organization-owned repos additionally require:
          # GITLEAKS_LICENSE: ${{ secrets.GITLEAKS_LICENSE }}

      - name: Dependency vulnerability scan (OWASP)
        id: gate-dep-scan
        run: ./mvnw -q org.owasp:dependency-check-maven:check

      - name: Generate SBOM (CycloneDX)
        id: gate-sbom
        run: ./mvnw -q org.cyclonedx:cyclonedx-maven-plugin:makeAggregateBom

      - name: Upload SBOM
        uses: actions/upload-artifact@v4
        with:
          name: sbom
          path: target/*-cyclonedx.json

      - name: Attest build provenance
        id: gate-provenance
        # Provenance attaches to the built jar, so it runs on the release/build (push-to-main) path.
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        uses: actions/attest-build-provenance@v1
        with:
          subject-path: target/*.jar
```

- [ ] **Step 2: Write CODEOWNERS**

Create `profiles/java-spring/CODEOWNERS` with exactly this content:

```
# Reference CODEOWNERS for the Java/Spring profile.
# COPY & ADAPT: copy to .github/CODEOWNERS (or repo root). Routes review so the
# builder is never the sole reviewer/merger (DEVELOPMENT-PROCESS.md §2, §12).
# Replace @your-org/* with real teams.

*            @your-org/engineering
/.github/    @your-org/platform
/src/        @your-org/engineering
```

- [ ] **Step 3: Write BRANCH-PROTECTION.md**

Create `profiles/java-spring/BRANCH-PROTECTION.md` with exactly this content:

```markdown
# Branch Protection — reference setup (Java/Spring profile)

Enforces the §14 contract at the repo boundary: `main` protected, green CI to merge, builder ≠ sole merger. COPY & ADAPT — replace `OWNER/REPO` and team handles.

## What to require
- The CI status check (`ci`) must pass before merge.
- At least 1 approving review from someone other than the author.
- Stale approvals dismissed on new commits.
- Branch up to date before merge.
- (Org/plan-dependent) CODEOWNERS review required; self-merge disallowed.

## Apply via GitHub CLI
Run **after** the CI workflow has run at least once (so the check name `ci` is registered):

\`\`\`bash
gh api -X PUT repos/OWNER/REPO/branches/main/protection --input - <<'JSON'
{
  "required_status_checks": { "strict": true, "contexts": ["ci"] },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true
  },
  "restrictions": null
}
JSON
\`\`\`

> "Builder ≠ sole merger" is enforced by required reviews + CODEOWNERS. GitHub cannot strictly forbid every user from merging their own PR on all plans; on GitHub Enterprise use rulesets / required reviewers. Document the policy in the project `CLAUDE.md` regardless.
```

- [ ] **Step 4: Verify and commit**

```bash
cd ~/Development/agentic-sdlc-kit
sh conformance/ci-gates.sh profiles/java-spring/ci.yml; echo "exit=$?"
ruby -ryaml -e "YAML.load_file('profiles/java-spring/ci.yml'); puts 'YAML OK'"
test -f profiles/java-spring/CODEOWNERS && grep -q "required_status_checks" profiles/java-spring/BRANCH-PROTECTION.md && echo "companions OK"
git add profiles/java-spring/ci.yml profiles/java-spring/CODEOWNERS profiles/java-spring/BRANCH-PROTECTION.md
git commit -m "feat: add Java/Spring reference CI pipeline + governance companions"
```
Expected: ci-gates `OK`, `exit=0`; `YAML OK`; `companions OK`.

---

### Task 5: conformance/profile-completeness.sh

**Files:**
- Create: `conformance/profile-completeness.sh`

- [ ] **Step 1: Write the checker**

Create `conformance/profile-completeness.sh` with exactly this content:

```sh
#!/bin/sh
# profile-completeness.sh — verify every stack profile fills the _TEMPLATE.md contract.
# For each profiles/*.md except _TEMPLATE.md: all 11 section headings present, no leftover
# [...] placeholder, and (if a companion profiles/<stack>/ci.yml exists) it passes ci-gates.sh.
# Usage: sh conformance/profile-completeness.sh   (run from repo root)
set -eu

HERE=$(dirname "$0")
fail=0

for prof in profiles/*.md; do
  base=$(basename "$prof")
  [ "$base" = "_TEMPLATE.md" ] && continue
  name="${base%.md}"

  miss=""
  i=1
  while [ "$i" -le 11 ]; do
    grep -Eq "^## ${i}\. " "$prof" || miss="$miss §${i}"
    i=$((i + 1))
  done
  if [ -n "$miss" ]; then echo "FAIL $base: missing section(s):$miss"; fail=1; else echo "PASS $base: 11 sections"; fi

  if grep -Fq '[...]' "$prof"; then echo "FAIL $base: leftover [...] placeholder(s)"; fail=1; fi

  if [ -f "profiles/${name}/ci.yml" ]; then
    if sh "${HERE}/ci-gates.sh" "profiles/${name}/ci.yml" >/dev/null 2>&1; then
      echo "PASS $base: companion ci.yml satisfies §14"
    else
      echo "FAIL $base: companion ci.yml missing required gates"; fail=1
    fi
  fi
done

if [ "$fail" -ne 0 ]; then echo "FAIL: profile-completeness"; exit 1; fi
echo "OK: all profiles complete and conformant"
exit 0
```

- [ ] **Step 2: Run it — all three profiles must pass (incl. the existing TS profile)**

```bash
cd ~/Development/agentic-sdlc-kit
chmod +x conformance/profile-completeness.sh
sh conformance/profile-completeness.sh; echo "exit=$?"
```
Expected: `PASS` lines for `typescript-node.md`, `python.md`, `java-spring.md` (sections + companion ci.yml), final `OK: ...`, `exit=0`. If `typescript-node.md` fails (missing section or stray `[...]`), that is a real pre-existing gap — report it; do NOT weaken the checker.

- [ ] **Step 3: Negative test (a profile missing a section fails)**

```bash
cd ~/Development/agentic-sdlc-kit
cp profiles/python.md /tmp/python.bak
# remove the "## 7." heading to simulate an incomplete profile
sed '/^## 7\. /d' profiles/python.md > /tmp/p.md && cp /tmp/p.md profiles/python.md
sh conformance/profile-completeness.sh; echo "exit=$?"
cp /tmp/python.bak profiles/python.md; rm -f /tmp/python.bak /tmp/p.md
sh conformance/profile-completeness.sh >/dev/null && echo "restored-OK"
```
Expected: with §7 removed, `FAIL python.md: missing section(s): §7` and `exit=1`; after restore, `restored-OK`. Confirm `git diff --stat profiles/python.md` shows NO change before committing.

- [ ] **Step 4: Commit**

```bash
cd ~/Development/agentic-sdlc-kit
git status --short profiles/python.md
git add conformance/profile-completeness.sh
git commit -m "feat: add profile-completeness conformance check"
```

---

### Task 6: conformance/README index + CI step

**Files:**
- Modify: `conformance/README.md`, `.github/workflows/ci.yml`

- [ ] **Step 1: Index profile-completeness.sh**

In `conformance/README.md`, find this exact line:

```
| `inception-done.sh` | script | `DEVELOPMENT-PROCESS.md` §3 / `START-HERE.md` (the Inception gate) | CI (bootstrap-into-temp) |
```

Replace with:

```
| `inception-done.sh` | script | `DEVELOPMENT-PROCESS.md` §3 / `START-HERE.md` (the Inception gate) | CI (bootstrap-into-temp) |
| `profile-completeness.sh` | script | `profiles/_TEMPLATE.md` (every profile fills all 11 sections; companion ci.yml conformant) | CI |
```

- [ ] **Step 2: Drop profile-completeness from the "future" note**

Find this exact line:

```
> Future slices add: `template-lint` (templates), `profile-completeness` (profiles). See `../docs/ROADMAP-KIT.md`.
```

Replace with:

```
> Future slices add: enterprise addendum checks (compliance/audit-evidence). See `../docs/ROADMAP-KIT.md`.
```

- [ ] **Step 3: Add the CI step**

In `.github/workflows/ci.yml`, find this exact block (the last step of the `conformance` job):

```
      - name: Agent-autonomy guard conformance (§13)
        run: sh conformance/agent-autonomy.sh
```

Replace with:

```
      - name: Agent-autonomy guard conformance (§13)
        run: sh conformance/agent-autonomy.sh
      - name: Profile-completeness conformance
        run: sh conformance/profile-completeness.sh
```

- [ ] **Step 4: Verify and commit**

```bash
cd ~/Development/agentic-sdlc-kit
ruby -ryaml -e "YAML.load_file('.github/workflows/ci.yml'); puts 'YAML OK'"
grep -c "profile-completeness.sh" conformance/README.md
git add conformance/README.md .github/workflows/ci.yml
git commit -m "feat: index + run profile-completeness in kit CI"
```
Expected: `YAML OK`; `1`.

---

### Task 7: VERSION + CHANGELOG + ROADMAP (2.3.0)

**Files:**
- Modify: `VERSION`, `CHANGELOG.md`, `docs/ROADMAP-KIT.md`

- [ ] **Step 1: Bump VERSION**

Overwrite `VERSION` with exactly one line + trailing newline:

```
2.3.0
```

- [ ] **Step 2: Add the 2.3.0 CHANGELOG entry**

In `CHANGELOG.md`, find this exact line:

```
## [2.2.0] - 2026-06-06
```

Insert IMMEDIATELY BEFORE it:

```
## [2.3.0] - 2026-06-06

Slice 5 — Enterprise profiles. Python and Java/Spring join TypeScript as ready, conformant stack profiles.

### Added
- `profiles/python.md` + `profiles/python/` (`ci.yml`, `CODEOWNERS`, `BRANCH-PROTECTION.md`) — uv · ruff · mypy · pytest+cov · gitleaks · pip-audit · CycloneDX-py + provenance; FastAPI + SQLAlchemy/Alembic reference.
- `profiles/java-spring.md` + `profiles/java-spring/` (`ci.yml`, `CODEOWNERS`, `BRANCH-PROTECTION.md`) — Maven · Spring Boot · Spotless/Checkstyle · JUnit5+JaCoCo · OWASP dependency-check · CycloneDX-maven + provenance; Flyway migrations. (`mvn compile` = type-check; `mvn package` = build.)
- `conformance/profile-completeness.sh` — every profile fills all 11 `_TEMPLATE.md` sections (no leftover `[...]`) and its companion `ci.yml` passes `ci-gates.sh`. Runs in kit CI; also regression-guards `typescript-node.md`.

### Changed
- `.github/workflows/ci.yml` — the conformance job now runs `profile-completeness.sh`.
- `docs/ROADMAP-KIT.md` — Slice 5 marked done.

### Note
`incept.sh --stack python` / `--stack java-spring` now wires the respective profile's CI. Kit CI verifies the profiles' workflows *declare* the §14 gates and the profiles are complete; it does not execute the Python/JVM pipelines (that happens in an adopting project).

```

- [ ] **Step 3: Add the 2.3.0 link reference**

In `CHANGELOG.md`, find:

```
[2.2.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.2.0
```

Replace with:

```
[2.3.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.3.0
[2.2.0]: https://github.com/SeaBrad72/agentic-sdlc-kit/releases/tag/v2.2.0
```

- [ ] **Step 4: Mark Slice 5 done in the roadmap**

In `docs/ROADMAP-KIT.md`, find this exact line:

```
| 5 | **Enterprise profiles** | `profiles/_TEMPLATE.md` | `profiles/python.md` + `profiles/java-spring.md` with real config files | `conformance/profile-completeness` — every section filled |
```

Replace with:

```
| 5 ✅ | **Enterprise profiles** *(shipped v2.3.0)* | `profiles/_TEMPLATE.md` | `profiles/python.md` + `profiles/java-spring.md` + companion `ci.yml`/`CODEOWNERS`/`BRANCH-PROTECTION.md` | `conformance/profile-completeness.sh` |
```

- [ ] **Step 5: Verify and commit**

```bash
cd ~/Development/agentic-sdlc-kit
cat VERSION
grep -c "## \[2.3.0\]" CHANGELOG.md
grep -c "shipped v2.3.0" docs/ROADMAP-KIT.md
git add VERSION CHANGELOG.md docs/ROADMAP-KIT.md
git commit -m "release: 2.3.0 — Slice 5 enterprise profiles (changelog + roadmap)"
```
Expected: `2.3.0`; `1`; `1`.

---

### Task 8: Final validation + PR

**Files:** none created; verification + PR only.

- [ ] **Step 1: Full conformance sweep**

```bash
cd ~/Development/agentic-sdlc-kit
sh conformance/profile-completeness.sh >/dev/null && echo "profile-completeness OK"
sh conformance/ci-gates.sh profiles/typescript-node/ci.yml >/dev/null && echo "ci-gates TS OK"
sh conformance/ci-gates.sh profiles/python/ci.yml >/dev/null && echo "ci-gates py OK"
sh conformance/ci-gates.sh profiles/java-spring/ci.yml >/dev/null && echo "ci-gates java OK"
sh conformance/agent-autonomy.sh >/dev/null && echo "agent-autonomy OK"
sh conformance/check-links.sh >/dev/null && echo "check-links OK"
test -f conformance/15-factor-checklist.md && echo "15-factor present"
```
Expected: all OK lines.

- [ ] **Step 2: incept wires each new profile (end-to-end)**

```bash
cd ~/Development/agentic-sdlc-kit
for stack in python java-spring; do
  tmp=$(mktemp -d); git archive HEAD | tar -x -C "$tmp"
  ( cd "$tmp" && sh scripts/incept.sh --noninteractive --name "Demo-$stack" --intent-owner "CI" --stack "$stack" --backlog md ) >/dev/null
  sh conformance/inception-done.sh "$tmp" >/dev/null && echo "incept --stack $stack → inception-done OK"
  sh conformance/ci-gates.sh "$tmp/.github/workflows/ci.yml" >/dev/null && echo "  wired $stack CI satisfies §14"
  rm -rf "$tmp"
done
```
Expected: for both stacks, `incept --stack <stack> → inception-done OK` and `wired <stack> CI satisfies §14`.

- [ ] **Step 3: Push and open the PR**

```bash
cd ~/Development/agentic-sdlc-kit
git push -u origin feature/slice-5-enterprise-profiles
gh pr create --title "Slice 5: Enterprise profiles — Python + Java/Spring + profile-completeness (v2.3.0)" --body "$(cat <<'EOF'
## Summary
Python and Java/Spring join TypeScript as ready, conformant stack profiles — so a Python or Java enterprise team can adopt the kit and `incept.sh --stack python|java-spring` straight into a §14-conformant pipeline.

- **`profiles/python.md`** + `profiles/python/` — uv · ruff · mypy · pytest+cov · gitleaks · pip-audit · CycloneDX-py + attest; FastAPI + SQLAlchemy/Alembic.
- **`profiles/java-spring.md`** + `profiles/java-spring/` — Maven · Spring Boot · Spotless/Checkstyle · JUnit5+JaCoCo · OWASP dependency-check · CycloneDX-maven + attest; Flyway. (`mvn compile`=type-check, `mvn package`=build.)
- **`conformance/profile-completeness.sh`** — every profile fills all 11 sections (no `[...]`) and its companion `ci.yml` passes `ci-gates.sh`; runs in CI and regression-guards the TS profile.
- **Release** 2.3.0 (MINOR).

## Verified
Both new `ci.yml`s pass `ci-gates.sh` (all 8 §14 gate ids); `incept.sh --stack python|java-spring` into a temp copy wires CI and passes `inception-done.sh`. Kit CI checks declaration + completeness only (it does not execute Python/JVM pipelines — that's adopter-side).

## Ratification
Additive profiles + a new conformance check. **Human ratification required before merge.**

Spec: `docs/superpowers/specs/2026-06-06-slice5-enterprise-profiles-design.md`
Plan: `docs/superpowers/plans/2026-06-06-slice5-enterprise-profiles.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
Expected: branch pushed; PR URL printed; CI starts.

- [ ] **Step 4: Report CI status, stop for ratification**

```bash
cd ~/Development/agentic-sdlc-kit
sleep 15
gh pr checks 2>&1 | head
```
Do **not** merge. Report PR URL + CI results.

---

## Self-Review (completed by plan author)

**Spec coverage:** §3 deliverables all mapped — python.md→T1, python/ companions→T2, java-spring.md→T3, java-spring/ companions→T4, profile-completeness→T5, README index + CI→T6, VERSION/CHANGELOG/ROADMAP→T7, validation/PR→T8. Spec §5 validation (profile-completeness on all three, ci-gates on both new workflows, incept --stack wiring, kit still green) appears in T2/T4/T5/T8.

**Placeholder scan:** no TBD/TODO; profile bodies are complete prose. The `[...]` checker (T5) flags only the *template* placeholder token (`grep -Fq '[...]'`); the authored profiles deliberately contain none. The `@your-org/*` tokens in CODEOWNERS are intentional copy-and-adapt placeholders.

**Type/name consistency:** the 8 `gate-*` ids in both new `ci.yml`s match exactly what `ci-gates.sh` requires (verified against the REQUIRED list: gate-lint/type-check/test/build/secret-scan/dep-scan/sbom/provenance). Profile filenames (`python.md`, `java-spring.md`) match their companion dirs (`profiles/python/`, `profiles/java-spring/`) and the `--stack` values used in T8. `profile-completeness.sh` references `ci-gates.sh` by the same relative path (`${HERE}/ci-gates.sh`).
