# Stack Profile — Kotlin (JVM) / Spring Boot

> Reference profile. The concrete *how* for the universal `DEVELOPMENT-STANDARDS.md` on a Kotlin/JVM stack. Copy/adapt per project; record selection as ADR-000. (Sibling of `java-spring` — Gradle + ktlint/detekt deltas.)

**Stack:** Kotlin · JDK 21 (LTS) · Gradle (Kotlin DSL) · Spring Boot 3.x · PostgreSQL + JPA/Hibernate + Flyway · JUnit 5/Kotest · hosted (container / K8s)
**Status:** reference

---

## 1. Toolchain
- **Runtime:** JDK 21 (Temurin) · **Build/deps:** Gradle (Kotlin DSL) via wrapper `./gradlew`
- **Format/lint:** ktlint (format) + detekt (static analysis) · **Types:** the compiler (`compileKotlin`)
- **Tests:** JUnit 5 / Kotest + JaCoCo (coverage gate) · **Build:** `./gradlew build`

## 2. Project scaffold
```
src/main/kotlin/<group>/{api,service,domain,repo,config}/
src/test/kotlin/<group>/
src/main/resources/{application.yml,db/migration/}   # Flyway migrations
docs/architecture/            # ADRs (incl. ADR-000)
.github/workflows/ci.yml
build.gradle.kts · settings.gradle.kts · gradle/ · .env.example · .gitignore
```
Baselines: `build.gradle.kts` with ktlint + detekt + jacoco (rule: line ≥0.80) + org.cyclonedx.bom + dependency-check plugins.

## 3. Standard commands
```
install:       ./gradlew dependencies
dev:           ./gradlew bootRun
test:          ./gradlew test
test:coverage: ./gradlew test jacocoTestCoverageVerification
lint:          ./gradlew ktlintCheck detekt
type-check:    ./gradlew compileKotlin
build:         ./gradlew build -x test
start:         java -jar build/libs/*.jar
```

## 4. CI/CD pipeline
Implements the 7 required gates of `DEVELOPMENT-STANDARDS.md` §14. Drop-in reference files live in **`profiles/kotlin/`**:
- **`ci.yml`** → copy to `.github/workflows/ci.yml`. ktlint+detekt → `compileKotlin` (type-check) → JUnit5/Kotest+JaCoCo(≥80) → `gradle build` → secret-scan (gitleaks) → dependency scan (OWASP) → SBOM (cyclonedx-gradle) → build provenance.
- **`CODEOWNERS`**, **`BRANCH-PROTECTION.md`** → governance companions.

Conformance: `sh conformance/ci-gates.sh profiles/kotlin/ci.yml`. Note: `gate-type-check`=`compileKotlin`, `gate-build`=`gradle build`.

## 5. Security implementation
- **Env/secrets:** Spring `@Value`/`Environment` / `application.yml` env placeholders; fail-fast; `.env` gitignored; commit `.env.example`.
- **Validation:** **Jakarta Bean Validation** (`@Valid`) on request DTOs (data classes); validate create *and* update.
- **Injection-safe data:** **Spring Data JPA** / parameterized; never string-concatenate JPQL/SQL.
- **AuthN/Z:** **Spring Security** — BCrypt encoder; JWT (minimal claims, short expiry); method/route authorization server-side.
- **HTTP headers / CSRF:** Spring Security default security headers; CSRF tokens for cookie auth.
- **Rate limiting:** Resilience4j `RateLimiter` or a gateway (relax in test profile).

## 6. Testing
- **Convention:** `src/test/kotlin` mirrors main; JUnit 5 or **Kotest**. Arrange-Act-Assert.
- **Integration:** `@SpringBootTest` + Testcontainers (real Postgres); assert status + body + DB state.
- **E2E:** Playwright/REST-assured against the running app.
- **AI evals:** an `evals/` source set with JSONL datasets; a runner scoring against a rubric (LLM-as-judge via the Anthropic Java/Kotlin SDK, pinned judge) failing below threshold in CI.

## 7. Resilience & observability
- **Retry/backoff + circuit breaker:** **Resilience4j**.
- **Logging:** SLF4J + Logback (JSON encoder). **Metrics/health/traces:** Micrometer + Spring Boot Actuator + OpenTelemetry. **Error tracking:** Sentry.

## 8. Data & migrations
- **JPA/Hibernate + Flyway.** Versioned SQL in `db/migration` (`V<n>__desc.sql`). Expand-contract: add → backfill → switch reads → drop old later. No manual prod DDL.

## 9. Release & deploy
- **Build artifact:** executable jar + container image (Jib/buildpacks). **Deploy:** container to K8s/Fly; merge to `main` → deploy.
- **Feature flags:** a flag service or Spring `@ConfigurationProperties`; flag-off = fastest rollback.
- **Rollout:** staging → prod; **rollback:** redeploy previous image / revert + redeploy.

## 10. Recommended libraries
Spring Boot starters (web, security, data-jpa, validation, actuator) · Resilience4j · Flyway · Micrometer + Sentry · JUnit 5 / Kotest + JaCoCo + Testcontainers · ktlint + detekt · cyclonedx-gradle + dependency-check-gradle · Anthropic Java SDK for AI features. Default Claude models: `claude-sonnet-4-6` (workhorse), escalate to Opus for hard reasoning.

## 11. Stack-specific gotchas
- Use `./gradlew` (the wrapper) for reproducible builds; commit `gradle/wrapper`.
- ktlint = formatting/style; detekt = static analysis/smells — both gate in CI.
- JaCoCo `jacocoTestCoverageVerification` binds to `check`; CI runs it explicitly.
- OWASP dependency-check's first run downloads the NVD DB (slow) — cache it in CI.
- Use Spring profiles (`application-<env>.yml`) for env config — never env conditionals in code.

---

**Last Updated:** 2026-06-06
