package com.example.app

import jakarta.annotation.PostConstruct
import org.springframework.context.annotation.Configuration

/**
 * The `FLAG_FILE` boot gate (Kotlin/Spring profile) — the load-bearing live-flip
 * wiring. When `FLAG_FILE` is set, install the file-config live provider into the
 * [FeatureFlags] seam at startup, so the running server's `/greeting` reflects live
 * file flips with no restart. Unset -> the env floor (the shipped default).
 *
 * Mirrors go's `configureProvider` and python's `serve()` boot gate.
 */
@Configuration
class FlagProviderConfig {
    @PostConstruct
    fun installFileProviderIfConfigured() {
        configureFlagProvider(System.getenv("FLAG_FILE"))
    }
}

/**
 * Install the file-config live provider when [flagFile] is a non-empty path; a null
 * or blank value leaves the env floor active. Extracted from the bean so the wiring
 * decision is directly unit-testable (the JVM process environment is read-only at
 * runtime).
 */
fun configureFlagProvider(flagFile: String?) {
    if (!flagFile.isNullOrEmpty()) {
        FeatureFlags.setProvider(fileConfigProvider(flagFile))
    }
}
