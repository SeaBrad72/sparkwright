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
- **Format/lint:** Spotless (format) + Checkstyle (lint) · **Types:** the compiler (`mvn compile` = type-checking) · **Complexity/duplication** (recommended `gate-lint` config): Checkstyle CyclomaticComplexity + CPD (PMD) (`docs/operations/code-quality.md`)
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

### Environments this stack needs
**Default archetype: DB-backed service.** The shipped `compose.yaml` provides the app + a Postgres database for dev/prod parity.
The profile ships `compose.yaml` + `Dockerfile` as **COPY-&-ADAPT references** (incept does not auto-copy them); adapt them when you containerize, adding services only as your feature needs them. The image-build CI gates skip until a `Dockerfile` is present.

| Need | Default | Add when |
|------|---------|----------|
| Database | Postgres (in compose) | relational data (the default) |
| Cache | — | sessions / hot-path caching (Redis) |
| Queue / broker | — | events / async messaging (Kafka/RabbitMQ) |
| Object store | — | blobs / file storage (S3/blob store) |

Promote **Dev → QA → UAT → Prod** with gated promotion; **production is human-gated**
(DEVELOPMENT-PROCESS.md env model). Record your approach in RUNBOOK §1/§4.

## 4. CI/CD pipeline
Implements the 7 required gates of `DEVELOPMENT-STANDARDS.md` §14. Drop-in reference files live in **`profiles/java-spring/`**:
- **`ci.yml`** → copy to `.github/workflows/ci.yml`. spotless/checkstyle → `mvn compile` (type-check) → JUnit5+JaCoCo(≥80) → `mvn package` → secret-scan (gitleaks) → dependency scan (OWASP) → SBOM (CycloneDX-maven) → build provenance.
- **`CODEOWNERS`** → copy to `.github/CODEOWNERS`. · **`BRANCH-PROTECTION.md`** → how to protect `main`.
- **Container image supply-chain (this profile ships a service):** the reference `ci.yml` adds `gate-image-sbom` (Syft/CycloneDX, on PR) and `gate-image-provenance` (digest-bound, push-only) on top of the 8 universal gate-ids. Verified by `conformance/container-supply-chain.sh`.

Conformance: `sh conformance/ci-gates.sh profiles/java-spring/ci.yml`. Note: Java has no separate type-check step — compilation **is** type-checking, so `gate-type-check`=`mvn compile` and `gate-build`=`mvn package`.

## 5. Security implementation
- **Env/secrets:** Spring `@Value`/`Environment` / `application.yml` with env placeholders; fail-fast on missing; `.env` gitignored; commit `.env.example`.
- **Validation:** **Jakarta Bean Validation** (`@Valid`, `@NotNull`, …) on request DTOs; validate create *and* update.
- **Injection-safe data:** **Spring Data JPA** / parameterized queries; never string-concatenate JPQL/SQL.
- **AuthN/Z:** **Spring Security** — BCrypt password encoder; JWT (minimal claims, short expiry); method/route authorization server-side.
- **HTTP headers / CSRF:** Spring Security default security headers; CSRF tokens for cookie-auth forms.
- **Rate limiting:** Resilience4j `RateLimiter` or a gateway (skip/relax in test profile).
- **Static analysis & licenses (conditional gates — `docs/operations/security-scanning.md`):** SAST via **Semgrep (or CodeQL)** (`gate-sast`); license policy via `scripts/license-check.sh` over the CycloneDX SBOM (`gate-license`, stack-neutral default — upgrade per the ladder if needed).

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
- **Container (service):** build the multi-stage non-root image (`profiles/java-spring/Dockerfile`, distroless `java21` JRE base), run locally via `compose.yaml` (dev/prod parity). CI scans the image SBOM on every PR (`gate-image-sbom`) and, on merge to `main`, pushes to GHCR and attests **provenance bound to the image digest** (`gate-image-provenance`). Deploy the **attested digest** via `deploy/k8s/` or the Helm chart in `deploy/helm/` (Actuator liveness/readiness probes, read-only root FS + writable `/tmp`, JVM-slow-start ⇒ prefer a startupProbe). Promote the same digest Dev → QA → UAT → Prod; rollback = redeploy the previous digest. (No in-image HEALTHCHECK or devcontainer — distroless has no shell; k8s probes are the health mechanism.)
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
