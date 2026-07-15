package com.example.app

import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Unit tests for the feature-flag registry + provider seam. The JVM process
 * environment is read-only at runtime, so strict env parsing is driven through
 * [FeatureFlags.envFlagProvider] with a fake lookup; the real [FeatureFlags.envProvider]
 * is exercised for the unset/registry-default path.
 */
class FeatureFlagsTest {
    @AfterEach
    fun restoreFloor() {
        // FeatureFlags is a process-wide singleton; never leak an installed provider.
        FeatureFlags.resetProvider()
    }

    @Test
    fun `registered flag defaults OFF`() {
        assertFalse(FeatureFlags.isEnabled("new_greeting"))
    }

    @Test
    fun `envName maps snake_case to FEATURE_ prefixed SCREAMING_SNAKE`() {
        assertEquals("FEATURE_NEW_GREETING", FeatureFlags.envName("new_greeting"))
    }

    @Test
    fun `registryDefault is own-key-only and strict`() {
        assertFalse(FeatureFlags.registryDefault("new_greeting")) // stored false
        assertFalse(FeatureFlags.registryDefault("unknown_flag")) // not a key
        assertFalse(FeatureFlags.registryDefault("__class__")) // dunder collision
    }

    @Test
    fun `env floor enables ONLY on the exact string true`() {
        val env = mutableMapOf<String, String?>()
        val provider = FeatureFlags.envFlagProvider { env[it] }

        env["FEATURE_NEW_GREETING"] = "true"
        assertTrue(provider.isEnabled("new_greeting"))

        for (loose in listOf("TRUE", "True", "1", "yes", "on", " true", "")) {
            env["FEATURE_NEW_GREETING"] = loose
            assertFalse(provider.isEnabled("new_greeting"), "\"$loose\" must not enable")
        }
    }

    @Test
    fun `env floor falls back to registry default when unset`() {
        val provider = FeatureFlags.envFlagProvider { null }
        assertFalse(provider.isEnabled("new_greeting")) // registry default OFF
        assertFalse(provider.isEnabled("unknown_flag")) // own-key-only
    }

    @Test
    fun `own-key-only — an unknown flag with no env var set never enables`() {
        // The env floor consults ONLY its own FEATURE_<NAME> var; with none set it
        // falls to the registry default, which is own-key-only (unknown -> OFF).
        val provider =
            FeatureFlags.envFlagProvider { name ->
                // Only a DIFFERENT flag's var is set to true — must not bleed across keys.
                if (name == "FEATURE_NEW_GREETING") "true" else null
            }
        assertFalse(provider.isEnabled("unknown_flag"))
        assertTrue(provider.isEnabled("new_greeting")) // its own key still resolves
    }

    @Test
    fun `the shipped envProvider reads the real environment and fails safe OFF`() {
        // new_greeting is (virtually certainly) unset in CI/local env -> registry default.
        assertFalse(FeatureFlags.envProvider.isEnabled("new_greeting"))
        assertFalse(FeatureFlags.envProvider.isEnabled("definitely_not_a_flag"))
    }

    @Test
    fun `setProvider installs a live provider and resetProvider restores the floor`() {
        FeatureFlags.setProvider { name -> name == "new_greeting" }
        assertTrue(FeatureFlags.isEnabled("new_greeting"))

        FeatureFlags.resetProvider()
        assertFalse(FeatureFlags.isEnabled("new_greeting"))
    }

    @Test
    fun `concurrent isEnabled and setProvider are thread-safe`() {
        val threads =
            (1..8).map { i ->
                Thread {
                    repeat(200) {
                        if (i % 2 == 0) {
                            FeatureFlags.setProvider { n -> n == "new_greeting" }
                        } else {
                            FeatureFlags.resetProvider()
                        }
                        // Must never throw regardless of interleaving.
                        FeatureFlags.isEnabled("new_greeting")
                    }
                }
            }
        threads.forEach(Thread::start)
        threads.forEach(Thread::join)
    }
}
