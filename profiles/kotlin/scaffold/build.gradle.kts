import io.gitlab.arturbosch.detekt.Detekt

plugins {
    val kotlinVersion = "2.0.21"
    kotlin("jvm") version kotlinVersion
    kotlin("plugin.spring") version kotlinVersion
    id("org.springframework.boot") version "3.3.5"
    id("io.spring.dependency-management") version "1.1.6"

    // Quality gates (kit contract — see profiles/kotlin/ci.yml).
    id("org.jlleitschuh.gradle.ktlint") version "12.1.1" // gate-lint (format)
    id("io.gitlab.arturbosch.detekt") version "1.23.7" // gate-lint (static analysis)
    jacoco // gate-test (coverage >=80%)

    // Supply-chain gates (referenced by ci.yml; harmless on an empty repo).
    id("org.cyclonedx.bom") version "1.10.0" // gate-sbom
    id("org.owasp.dependencycheck") version "10.0.4" // gate-dep-scan
}

group = "com.example"
version = "0.0.1"

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)
    }
}

repositories {
    mavenCentral()
}

dependencies {
    implementation("org.springframework.boot:spring-boot-starter-web")
    implementation("com.fasterxml.jackson.module:jackson-module-kotlin")

    testImplementation("org.springframework.boot:spring-boot-starter-test")
    testImplementation(kotlin("test"))   // HealthControllerTest uses kotlin.test.assertEquals
    detektPlugins("io.gitlab.arturbosch.detekt:detekt-formatting:1.23.7")
}

detekt {
    buildUponDefaultConfig = true
    config.setFrom(files("detekt.yml"))
}

tasks.withType<Detekt>().configureEach {
    jvmTarget = "21"
}

// Spring Boot's bootJar is the single runnable artifact; the plain jar is noise.
tasks.named<Jar>("jar") {
    enabled = false
}

tasks.test {
    useJUnitPlatform()
    finalizedBy(tasks.jacocoTestReport)
}

tasks.jacocoTestReport {
    dependsOn(tasks.test)
}

// Exclude the @SpringBootApplication bootstrap class so >=80% line coverage is
// achievable from the controller test alone.
val coverageExclusions = listOf(
    "com/example/app/ApplicationKt.class",
    "com/example/app/Application.class",
)

tasks.jacocoTestCoverageVerification {
    dependsOn(tasks.test)
    violationRules {
        rule {
            limit {
                counter = "LINE"
                value = "COVEREDRATIO"
                minimum = "0.80".toBigDecimal()
            }
        }
    }
    classDirectories.setFrom(
        files(
            classDirectories.files.map {
                fileTree(it) { exclude(coverageExclusions) }
            },
        ),
    )
}
