package com.example.app

import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Files
import java.nio.file.Path
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Unit tests for the FLAG_FILE boot gate. The bean's @PostConstruct reads the real
 * env (unset in test -> no-op), so the wiring decision is exercised through the
 * extracted [configureFlagProvider] for both branches.
 */
class FlagProviderConfigTest {
    @TempDir
    lateinit var tempDir: Path

    @AfterEach
    fun restoreFloor() {
        FeatureFlags.resetProvider()
    }

    @Test
    fun `a null or blank FLAG_FILE leaves the env floor active`() {
        configureFlagProvider(null)
        assertFalse(FeatureFlags.isEnabled("new_greeting"))
        configureFlagProvider("")
        assertFalse(FeatureFlags.isEnabled("new_greeting"))
    }

    @Test
    fun `a set FLAG_FILE installs the live file provider`() {
        val file = tempDir.resolve("flags.json")
        Files.writeString(file, """{"new_greeting":true}""")
        configureFlagProvider(file.toString())
        assertTrue(FeatureFlags.isEnabled("new_greeting"), "the file provider must flip the flag ON")
    }

    @Test
    fun `the bean's post-construct wiring is a no-op when FLAG_FILE is unset`() {
        // FLAG_FILE is (virtually certainly) unset in CI/local env -> env floor.
        FlagProviderConfig().installFileProviderIfConfigured()
        assertFalse(FeatureFlags.isEnabled("new_greeting"))
    }
}
