# syntax=docker/dockerfile:1
# Reference container image for the Java / Spring Boot profile.
# COPY & ADAPT: copy to your project root as `Dockerfile`. INERT here in the kit.
# Satisfies DEVELOPMENT-STANDARDS.md §14 (container image supply-chain):
# multi-stage, non-root, minimal base.

# ---- builder: full JDK + Maven, never shipped ----
FROM eclipse-temurin:21-jdk AS builder
WORKDIR /src
# Cache deps: copy the wrapper + pom first, resolve offline, then the source.
COPY .mvn/ .mvn/
COPY mvnw pom.xml ./
RUN ./mvnw -q -B dependency:go-offline
COPY src ./src
RUN ./mvnw -q -B -DskipTests package && cp target/*.jar /app.jar

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
