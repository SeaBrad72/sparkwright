# java-spring starter scaffold

Minimal Spring Boot starter that makes the **java-spring** profile's CI language
pipeline (`profiles/java-spring/ci.yml`) go green on an empty repo, plus a
`/healthz` → 200 surface and its test.

This is an **incept-copied** starter: copy its contents into your new project at
Inception. It is **brownfield-safe** — it only adds `pom.xml`, `checkstyle.xml`,
`src/`, `.gitignore`, and this `README.md`; it does not overwrite existing app code.

## What's here

| File | Purpose |
|------|---------|
| `pom.xml` | Spring Boot 3.3.x parent, Java 21, web + test starters. Plugins: Spotless (google-java-format), Checkstyle, JaCoCo (line ≥80% bound to `verify`, `Application` excluded). |
| `checkstyle.xml` | Minimal lint ruleset the shipped source passes cleanly. |
| `src/main/java/com/example/app/Application.java` | `@SpringBootApplication` entry point. |
| `src/main/java/com/example/app/HealthController.java` | `@RestController` exposing `GET /healthz` → `200 {"status":"ok"}`. |
| `src/test/java/com/example/app/HealthControllerTest.java` | Unit test asserting status + body; covers the controller for the JaCoCo gate. |
| `.gitignore` | Ignores `target/` and local env. |

## One-time setup: generate the Maven wrapper

The CI gates invoke the **Maven wrapper** (`./mvnw`), but the wrapper binary
(`mvnw`, `mvnw.cmd`, `.mvn/wrapper/maven-wrapper.jar`) is **not** shipped in this
scaffold. Generate it once in your project (you need a system `mvn` for this step
only):

```sh
mvn wrapper:wrapper
```

Commit the generated `mvnw`, `mvnw.cmd`, and `.mvn/` (per the profile: "commit
`.mvn/wrapper`"). After that, everything runs through `./mvnw`.

## The gates (must match `profiles/java-spring/ci.yml`)

```sh
./mvnw spotless:check checkstyle:check   # gate-lint   (format + lint)
./mvnw compile                           # gate-type-check (compile = type-check in Java)
./mvnw verify                            # gate-test   (JUnit + JaCoCo line ≥80%, binds to verify)
./mvnw -DskipTests package               # gate-build  (executable jar)
```

`./mvnw spotless:apply` auto-fixes formatting; CI uses `check` (fails on drift).

## Verification status

**Authored to the java-spring `ci.yml` contract; not executed here (Maven absent
in the authoring environment).** Verify in an adopter environment with:

```sh
mvn wrapper:wrapper && ./mvnw verify
```

## Next steps (beyond the language pipeline)

The scaffold satisfies only the language gates + health surface. The full profile
also expects, per `profiles/java-spring.md`: a `Dockerfile` + `compose.yaml` (shipped
in `profiles/java-spring/`), OWASP dependency-check, CycloneDX SBOM, secret scanning,
`.env.example`, Flyway migrations, and ADR-000 recording the stack choice. Add these
as the project grows.
