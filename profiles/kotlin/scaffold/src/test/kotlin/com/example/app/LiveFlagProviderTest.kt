package com.example.app

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Files
import java.nio.file.Path
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Unit tests for the reference file-config LIVE provider. Covers the live flip and
 * the full tamper-safety surface (byte cap, deep-nesting DoS, forbidden keys,
 * malformed / non-object / missing-key / non-bool -> fail-safe OFF).
 */
class LiveFlagProviderTest {
    @TempDir
    lateinit var tempDir: Path

    private fun writeFlagFile(contents: String): Path {
        val file = tempDir.resolve("flags.json")
        Files.writeString(file, contents)
        return file
    }

    @Test
    fun `live flip — rewriting the file flips behaviour with no restart`() {
        val file = writeFlagFile("""{"new_greeting": false}""")
        val provider = fileConfigProvider(file.toString())
        assertFalse(provider.isEnabled("new_greeting"))

        // Rewrite in place — SAME provider instance, no restart.
        Files.writeString(file, """{"new_greeting": true}""")
        assertTrue(provider.isEnabled("new_greeting"))

        // And back OFF.
        Files.writeString(file, """{"new_greeting": false}""")
        assertFalse(provider.isEnabled("new_greeting"))
    }

    @Test
    fun `strict coercion — only the JSON boolean true enables`() {
        for (nonBool in listOf("\"true\"", "1", "\"yes\"", "null", "[]", "{}")) {
            val file = writeFlagFile("""{"new_greeting": $nonBool}""")
            assertFalse(
                fileConfigProvider(file.toString()).isEnabled("new_greeting"),
                "value $nonBool must not enable",
            )
        }
    }

    @Test
    fun `forbidden and dunder keys are rejected outright even when set true`() {
        val file =
            writeFlagFile(
                """{"__proto__": true, "constructor": true, "prototype": true, "__evil__": true}""",
            )
        val provider = fileConfigProvider(file.toString())
        assertFalse(provider.isEnabled("__proto__"))
        assertFalse(provider.isEnabled("constructor"))
        assertFalse(provider.isEnabled("prototype"))
        assertFalse(provider.isEnabled("__evil__")) // any __dunder__ name
    }

    @Test
    fun `missing file fails safe OFF`() {
        val provider = fileConfigProvider(tempDir.resolve("does-not-exist.json").toString())
        assertFalse(provider.isEnabled("new_greeting"))
    }

    @Test
    fun `malformed JSON fails safe OFF`() {
        val file = writeFlagFile("""{ this is not json """)
        assertFalse(fileConfigProvider(file.toString()).isEnabled("new_greeting"))
    }

    @Test
    fun `non-object payloads fail safe OFF`() {
        for (payload in listOf("true", "42", "\"new_greeting\"", "null", "[true]")) {
            val file = writeFlagFile(payload)
            assertFalse(
                fileConfigProvider(file.toString()).isEnabled("new_greeting"),
                "payload $payload must not enable",
            )
        }
    }

    @Test
    fun `missing key fails safe OFF`() {
        val file = writeFlagFile("""{"some_other_flag": true}""")
        assertFalse(fileConfigProvider(file.toString()).isEnabled("new_greeting"))
    }

    @Test
    fun `oversized file is rejected before enabling`() {
        // A valid, flag-enabling object followed by >1 MiB of padding. The byte cap
        // rejects the read entirely -> fail-safe OFF (a tampered/huge file can never
        // be slurped in, nor flip the flag).
        val padding = " ".repeat((1 shl 20) + 16)
        val file = writeFlagFile("""{"new_greeting": true}$padding""")
        assertTrue(Files.size(file) > (1L shl 20))
        assertFalse(fileConfigProvider(file.toString()).isEnabled("new_greeting"))
    }

    @Test
    fun `deeply-nested payload is rejected — no stack blow-up (DoS lock)`() {
        // A tamperer nests far beyond MAX_NESTING_DEPTH to try to crash the resolver.
        // Jackson's StreamReadConstraints errors during parse; the provider catches
        // it and fails safe OFF instead of recursing onto the stack.
        val depth = 5_000
        val nested = "[".repeat(depth) + "]".repeat(depth)
        val file = writeFlagFile("""{"new_greeting": $nested}""")
        // Must not throw; must resolve OFF.
        assertFalse(fileConfigProvider(file.toString()).isEnabled("new_greeting"))
    }

    @Test
    fun `empty file fails safe OFF`() {
        val file = writeFlagFile("")
        assertFalse(fileConfigProvider(file.toString()).isEnabled("new_greeting"))
    }
}
