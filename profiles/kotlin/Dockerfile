# syntax=docker/dockerfile:1
# Reference container image for the Kotlin / Spring Boot profile.
# COPY & ADAPT: copy to your project root as `Dockerfile`. INERT here in the kit.
# Satisfies DEVELOPMENT-STANDARDS.md §14 (container image supply-chain):
# multi-stage, non-root, minimal base.

# ---- builder: full JDK + Gradle, never shipped ----
FROM eclipse-temurin:21-jdk AS builder
WORKDIR /src
# Cache deps: copy the wrapper + build scripts first, then the source.
COPY gradlew settings.gradle* build.gradle* ./
COPY gradle ./gradle
RUN ./gradlew --no-daemon dependencies >/dev/null 2>&1 || true
COPY . .
# bootJar = the single runnable fat jar. If your build also emits a *-plain.jar,
# disable the `jar` task or copy the boot jar by explicit name.
# -x cyclonedxBom: SBOM generation is a CI/release concern (ci.yml's gate-sbom emits it), not part of
# building the runtime jar — and the cyclonedx-gradle plugin is version-sensitive; keep it out of the image build.
RUN ./gradlew --no-daemon -x test -x cyclonedxBom bootJar && cp build/libs/*.jar /app.jar

# ---- runtime: distroless Java 21 (JRE only, non-root by construction) ----
# The distroless java base sets ENTRYPOINT ["java","-jar"]; CMD supplies the jar path.
FROM gcr.io/distroless/java21-debian12:nonroot AS runtime
WORKDIR /app
COPY --from=builder /app.jar /app/app.jar
# Numeric UID (distroless 'nonroot' = 65532): matches the k8s securityContext runAsUser.
USER 65532
EXPOSE 8080
# No in-image HEALTHCHECK: distroless has no shell/curl. Health is via the k8s
# liveness/readiness probes (Spring Boot Actuator: /actuator/health/{liveness,readiness}).
CMD ["app.jar"]
