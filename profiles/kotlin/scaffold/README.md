# app — Kotlin/Spring starter scaffold

A minimal Spring Boot (Kotlin) service that satisfies the Kotlin profile's CI language pipeline
(`profiles/kotlin/ci.yml`) on an empty repo, plus a `/healthz` → 200 endpoint and its test.

> Incept-copied starter — **brownfield-safe**: `incept` copies these files into a fresh repo only.

## One-time Gradle wrapper step

The gates call the Gradle **wrapper** (`./gradlew`). The wrapper binary (`gradlew`,
`gradle/wrapper/gradle-wrapper.jar`) is intentionally not shipped — generate it once.
**Pin the version** (`--gradle-version`): this build needs Gradle **8.5+** (Kotlin 2.0 +
Spring Boot 3.3 + JDK 21), and a bare `gradle wrapper` pins whatever Gradle is on your PATH —
an older system Gradle would generate a wrapper that then fails every `./gradlew` gate.

```sh
gradle wrapper --gradle-version 8.10 --distribution-type bin    # needs a local Gradle >= 8.5 to bootstrap
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
> Verify with `gradle wrapper --gradle-version 8.10 && ./gradlew test jacocoTestCoverageVerification` in an adopter env.**
