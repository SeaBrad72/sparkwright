# app — Kotlin/Spring starter scaffold

A minimal Spring Boot (Kotlin) service that satisfies the Kotlin profile's CI language pipeline
(`profiles/kotlin/ci.yml`) on an empty repo, plus a `/healthz` → 200 endpoint and its test.

> Incept-copied starter — **brownfield-safe**: `incept` copies these files into a fresh repo only.

## One-time Gradle wrapper step

The gates call the Gradle **wrapper** (`./gradlew`). The wrapper binary (`gradlew`,
`gradle/wrapper/gradle-wrapper.jar`) is intentionally not shipped — generate it once:

```sh
gradle wrapper            # writes gradlew + gradle/wrapper/*
git add gradlew gradle/ && git commit -m "chore: gradle wrapper"
```

## Layout

| File                                         | Role                                                      |
|----------------------------------------------|-----------------------------------------------------------|
| `build.gradle.kts` / `settings.gradle.kts`   | Kotlin JVM + Spring Boot; ktlint, detekt, jacoco plugins. |
| `detekt.yml`                                 | detekt config (the source is detekt-clean).               |
| `src/main/kotlin/.../Application.kt`         | `@SpringBootApplication` main (excluded from coverage).   |
| `src/main/kotlin/.../HealthController.kt`    | `@RestController` `GET /healthz` → 200 `{"status":"ok"}`.  |
| `src/test/kotlin/.../HealthControllerTest.kt`| controller test (clears JaCoCo ≥80%).                     |

## Commands (match `profiles/kotlin/ci.yml`)

```sh
./gradlew ktlintCheck detekt                 # gate-lint
./gradlew compileKotlin                      # gate-type-check
./gradlew test jacocoTestCoverageVerification# gate-test (>=80% line, Application excluded)
./gradlew build -x test                      # gate-build
```

## Verification status

> **Authored to the `profiles/kotlin/ci.yml` contract; not executed here (gradle toolchain absent).
> Verify with `gradle wrapper && ./gradlew test jacocoTestCoverageVerification` in an adopter env.**
