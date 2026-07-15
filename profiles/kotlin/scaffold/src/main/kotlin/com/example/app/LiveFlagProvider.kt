package com.example.app

import com.fasterxml.jackson.core.JsonFactory
import com.fasterxml.jackson.core.StreamReadConstraints
import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths

/*
 * Reference LIVE flag provider — a file-config FlagProvider that reflects changes
 * WITHOUT a restart (Kotlin/Spring profile).
 *
 * This is the reference implementation of the live slot in the flags seam: it
 * re-reads a JSON flag file on every resolution, so rewriting the file flips
 * behaviour in the SAME running process (a live runtime flip, not the env floor's
 * restart-to-toggle). A SaaS provider (OpenFeature / Unleash / LaunchDarkly) is an
 * adopter-pluggable alternative implementing the same [FlagProvider] — swap it in
 * via [FeatureFlags.setProvider] with no change to callers of
 * [FeatureFlags.isEnabled].
 *
 * TRUST BOUNDARY: `path` is APP-CONFIGURED (an operator-controlled deploy
 * artifact), NOT end-user input. The file CONTENT is still treated as untrusted (it
 * can be corrupted/tampered), so resolution is fully fail-safe and injection-safe:
 *
 *  - fail-safe: a missing / unreadable / unparseable / oversized / DEEPLY-NESTED
 *    file, a non-object payload (array/null/scalar), a non-bool value, or a flag
 *    absent from the file all fall back to the registry default (OFF). Resolution
 *    never throws and never enables on ANY file content. The byte cap is enforced
 *    while reading via a bounded `readNBytes` (TOCTOU-safe: it bounds the bytes
 *    pulled into memory regardless of a racing stat/rewrite), so a huge/tampered
 *    file can never be slurped in. A deeply-nested payload is rejected by Jackson's
 *    [StreamReadConstraints] nesting-depth limit (the parser errors before
 *    recursing onto the stack), so a tamperer cannot turn "flip a flag" into "crash
 *    the resolver" — the DoS class the Slice-2 review caught.
 *  - no injection: [FORBIDDEN_KEYS] (`__proto__`/`constructor`/`prototype` and
 *    dunder-ish keys) are rejected outright; only the SPECIFIC flag key is read —
 *    the parsed JSON is NEVER spread/merged into anything.
 *  - strict coercion: only the JSON boolean `true` enables (a `"true"` string, `1`,
 *    etc. stay OFF — mirrors the env floor's strict `== "true"`).
 *
 * PERFORMANCE CAVEAT: this provider does a SYNCHRONOUS file read on EVERY
 * `isEnabled` call. That is fine for a kill-switch and for the shipped default (the
 * env floor does no FS read at all), but a profile/adopter that wires the file
 * provider onto a HOT request path should add an mtime-gated cache.
 */

/** 1 MiB cap on the flag file. A flag file is tiny (a handful of booleans). */
private const val MAX_FILE_BYTES: Long = 1L shl 20

/**
 * Max JSON nesting depth. A flag file is flat; a deeply nested payload is a
 * tamper/DoS vector, rejected by Jackson before it recurses onto the stack.
 */
private const val MAX_NESTING_DEPTH: Int = 20

/** Names that must never be resolved from file data (shadowing / pollution vectors). */
private val FORBIDDEN_KEYS: Set<String> = setOf("__proto__", "constructor", "prototype")

/**
 * A single hardened mapper: its [StreamReadConstraints] cap the parser's nesting
 * depth, so a deeply-nested tampered payload errors out (fail-safe OFF) instead of
 * blowing the stack.
 */
private val HARDENED_MAPPER: ObjectMapper =
    ObjectMapper(
        JsonFactory.builder()
            .streamReadConstraints(
                StreamReadConstraints.builder().maxNestingDepth(MAX_NESTING_DEPTH).build(),
            )
            .build(),
    )

/**
 * Return a provider whose `isEnabled` re-reads [path] per call (the live flip), so
 * rewriting the file flips behaviour with no restart. Content is untrusted.
 */
fun fileConfigProvider(path: String): FlagProvider = FileConfigProvider(Paths.get(path))

private class FileConfigProvider(private val path: Path) : FlagProvider {
    @Suppress("TooGenericExceptionCaught")
    override fun isEnabled(name: String): Boolean {
        val fallback = FeatureFlags.registryDefault(name)

        // Reject dunder-ish / pollution keys outright — never resolved from file data.
        if (name in FORBIDDEN_KEYS || (name.startsWith("__") && name.endsWith("__"))) {
            return fallback
        }

        val data = readCapped(path) ?: return fallback

        return try {
            val node: JsonNode? = HARDENED_MAPPER.readTree(data)
            // Only a JSON object can carry flags; arrays/null/scalars fall back.
            if (node == null || !node.isObject) {
                return fallback
            }
            // Read the SPECIFIC key — never merge the untrusted object into anything.
            val value = node.get(name) ?: return fallback
            // Strict: only a JSON boolean true enables (a "true" string, 1, etc. stay OFF).
            value.isBoolean && value.booleanValue()
        } catch (e: Exception) {
            // Any parse failure — malformed JSON, a StreamReadConstraints violation
            // (deep nesting), or any other runtime fault on tampered content — is
            // fail-safe OFF. Never throws, never enables.
            fallback
        }
    }
}

/**
 * Read at most [MAX_FILE_BYTES] bytes from [path]; reject anything larger. The
 * bounded `readNBytes` is TOCTOU-safe: it caps the bytes pulled into memory
 * regardless of a racing stat/rewrite. Returns null on any error or oversize — the
 * caller treats that as fail-safe OFF.
 */
@Suppress("TooGenericExceptionCaught")
private fun readCapped(path: Path): ByteArray? =
    try {
        Files.newInputStream(path).use { stream ->
            val data = stream.readNBytes((MAX_FILE_BYTES + 1).toInt())
            if (data.size.toLong() > MAX_FILE_BYTES) null else data
        }
    } catch (e: Exception) {
        null
    }
