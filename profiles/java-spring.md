# Stack Profile — Java / Spring Boot

> Reference profile. The concrete *how* for the universal `DEVELOPMENT-STANDARDS.md` on a Java/Spring stack. Copy/adapt per project; record selection as ADR-000.

**Stack:** Java 21 (LTS) · Maven · Spring Boot 3.x · PostgreSQL + JPA/Hibernate + Flyway · JUnit 5 · hosted (container / K8s)
**Status:** reference

---

## Best for / Avoid when

**Best for:** Large transactional enterprise services; mature JVM ecosystem; big teams.
**Avoid when:** Cold-start-sensitive tiny serverless; quick throwaway scripts.

Choosing a stack? Compare all profiles → [../docs/STACK-SELECTION.md](../docs/STACK-SELECTION.md).

---

## 1. Toolchain
- **Runtime:** JDK 21 (Temurin) · **Build/deps:** Maven via wrapper `./mvnw` (reproducible)
- **Format/lint:** Spotless (format) + Checkstyle (lint) · **Types:** the compiler (`mvn compile` = type-checking)
- **Tests:** JUnit 5 + JaCoCo (coverage gate) · **Test quality:** jqwik (property-based) + PITest (mutation, critical paths/nightly — `docs/operations/test-quality.md`) · **Build:** `mvn package`
- **Inner loop:** `pre-commit` (spotless + checkstyle; `mvn -o test` for the changed module) — fast feedback before CI (`docs/operations/dev-inner-loop.md`)

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
