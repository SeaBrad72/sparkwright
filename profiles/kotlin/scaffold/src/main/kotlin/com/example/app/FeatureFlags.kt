package com.example.app

import java.util.concurrent.locks.ReentrantReadWriteLock
import kotlin.concurrent.read
import kotlin.concurrent.write

/**
 * The seam contract every provider (env floor, file-config, SaaS) implements.
 *
 * Exported (public) so an adopter can plug in their own provider — e.g. the
 * reference file-config live provider (see [fileConfigProvider]) or a SaaS
 * provider (OpenFeature / Unleash / LaunchDarkly) — via [FeatureFlags.setProvider]
 * with no change to callers of [FeatureFlags.isEnabled].
 */
fun interface FlagProvider {
    fun isEnabled(name: String): Boolean
}

/**
 * Feature-flag registry + resolver SEAM — the kit's kill-switch (Kotlin/Spring profile).
 *
 * A typed flag module whose default is OFF, so an unset / unknown / malformed
 * value can never silently enable a feature (fail-safe). This module is a PROVIDER
 * SEAM (the shape the whole profile fan-out replicates):
 *
 *  - the FLOOR provider ([envProvider]) is env-driven and restart-to-toggle —
 *    dark-launch + a real kill-switch, but NOT a live runtime flip;
 *  - a pluggable live slot ([setProvider]) accepts any [FlagProvider] — e.g. the
 *    reference file-config live provider ([fileConfigProvider], flips WITHOUT a
 *    restart) or an adopter's SaaS provider implementing the same interface.
 *
 * The public API stays [isEnabled] and delegates to whichever provider is active.
 * Adding a flag = one entry in [flags] (the single place to enumerate live flags,
 * so retiring one is a known list, not a code hunt).
 */
object FeatureFlags {
    /**
     * The single typed registry — the one place flags are enumerated. Default OFF:
     * a name absent here (or stored false) can never resolve truthy.
     */
    private val flags: Map<String, Boolean> = mapOf("new_greeting" to false)

    /**
     * snake_case flag -> `FEATURE_`-prefixed SCREAMING_SNAKE env var:
     * `new_greeting` -> `FEATURE_NEW_GREETING`.
     */
    fun envName(name: String): String = "FEATURE_" + name.uppercase()

    /**
     * Own-key-only, strict-boolean fallback. A name that is not a registry key
     * (incl. dunder-ish collisions like `__class__`/`constructor`) must NOT
     * resolve truthy — fail-safe OFF, not open. Only a registry key stored exactly
     * `true` enables.
     */
    fun registryDefault(name: String): Boolean = flags[name] == true

    /**
     * Build an env-floor provider over an injectable lookup (defaults to the real
     * process environment). True ONLY when the value is exactly `"true"`; otherwise
     * the registry default (OFF). `"TRUE"`/`"1"`/`"yes"` do NOT enable (strict
     * parse). `internal` so unit tests can drive strict parsing with a fake lookup
     * (the JVM process environment is read-only at runtime).
     */
    internal fun envFlagProvider(lookup: (String) -> String?): FlagProvider =
        FlagProvider { name ->
            when (val raw = lookup(envName(name))) {
                null -> registryDefault(name)
                else -> raw == "true"
            }
        }

    /** The env floor — the default active provider installed below. */
    val envProvider: FlagProvider = envFlagProvider(System::getenv)

    // The pluggable seam. Default = the env floor; a live provider is installed by
    // setProvider(). Guarded by a RW lock because setProvider/resetProvider/isEnabled
    // touch this shared slot from multiple threads (integration tests hit it
    // concurrently).
    private val lock = ReentrantReadWriteLock()
    private var activeProvider: FlagProvider = envProvider

    /** Install a live provider into the seam (e.g. the file-config live provider). */
    fun setProvider(provider: FlagProvider) = lock.write { activeProvider = provider }

    /** Restore the env floor as the active provider. */
    fun resetProvider() = lock.write { activeProvider = envProvider }

    /** Public API — delegates to the active provider under a read lock. */
    fun isEnabled(name: String): Boolean = lock.read { activeProvider }.isEnabled(name)
}
