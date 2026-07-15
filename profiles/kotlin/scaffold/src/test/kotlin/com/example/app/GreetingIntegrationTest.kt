package com.example.app

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.web.server.LocalServerPort
import java.io.ByteArrayOutputStream
import java.io.PrintStream
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.nio.file.Files
import java.nio.file.Path
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * Integration: the flag seam + telemetry wiring THROUGH the RUNNING server.
 *
 * Unlike the unit tests (isEnabled / dispatch in isolation), here the flag registry,
 * the [SecurityAndTelemetryFilter], the controllers, and the real embedded Tomcat
 * are exercised together against an ephemeral port (`RANDOM_PORT`) in the SAME
 * process — so JaCoCo measures the spine. Mirrors the go/python integration suites.
 * The live-flip case is the load-bearing proof that the provider seam reaches the
 * REAL endpoint with no restart.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class GreetingIntegrationTest {
    @LocalServerPort
    private var port: Int = 0

    private val client: HttpClient = HttpClient.newBuilder().version(HttpClient.Version.HTTP_1_1).build()
    private val mapper = jacksonObjectMapper()

    @AfterEach
    fun restoreFloor() {
        // FeatureFlags is a process-wide singleton; never leak an installed provider.
        FeatureFlags.resetProvider()
    }

    private fun base() = "http://127.0.0.1:$port"

    private fun send(
        method: String,
        path: String,
        headers: Map<String, String> = emptyMap(),
    ): HttpResponse<String> {
        val builder = HttpRequest.newBuilder(URI.create(base() + path))
        headers.forEach { (k, v) -> builder.header(k, v) }
        builder.method(method, HttpRequest.BodyPublishers.noBody())
        return client.send(builder.build(), HttpResponse.BodyHandlers.ofString())
    }

    private val expectedSecurityHeaders =
        mapOf(
            "X-Content-Type-Options" to "nosniff",
            "X-Frame-Options" to "DENY",
            "Content-Security-Policy" to "default-src 'none'",
            "Referrer-Policy" to "no-referrer",
        )

    private fun assertSecurityHeadersExactlyOnce(resp: HttpResponse<*>) {
        for ((name, value) in expectedSecurityHeaders) {
            val values = resp.headers().allValues(name)
            assertEquals(listOf(value), values, "header $name must appear exactly once as $value")
        }
        assertEquals("reference-app", resp.headers().firstValue("Server").orElse(null), "Server must be neutralized")
    }

    @Test
    fun `greeting with flag OFF serves the default body`() {
        FeatureFlags.resetProvider()
        val resp = send("GET", "/greeting")
        assertEquals(200, resp.statusCode())
        assertTrue(
            resp.headers().firstValue("Content-Type").orElse("").startsWith("application/json"),
            "content-type = ${resp.headers().firstValue("Content-Type").orElse("")}",
        )
        assertEquals("""{"greeting":"Hello, world!"}""", resp.body())
    }

    @Test
    fun `greeting with flag ON serves the new body`() {
        // The JVM process environment is read-only, so drive ON through the seam.
        FeatureFlags.setProvider { it == "new_greeting" }
        val resp = send("GET", "/greeting")
        assertEquals(200, resp.statusCode())
        assertEquals("""{"greeting":"Hello, world! (new)"}""", resp.body())
    }

    @Test
    fun `healthz returns 200 with status ok`() {
        val resp = send("GET", "/healthz")
        assertEquals(200, resp.statusCode())
        assertEquals("""{"status":"ok"}""", resp.body())
    }

    @Test
    fun `metrics exposes the request counter`() {
        send("GET", "/greeting") // record at least one request
        val resp = send("GET", "/metrics")
        assertEquals(200, resp.statusCode())
        assertTrue(resp.body().contains("http_requests_total"), "metrics missing counter:\n${resp.body()}")
    }

    /**
     * LOCK: the /metrics Content-Type is the cross-profile parity contract, INCLUDING
     * the space after the semicolon (`text/plain; version=0.0.4`). go and python both
     * emit the spaced form; routing through Spring's MediaType round-trip drops the
     * space, so this asserts the RAW value survives through the running server.
     */
    @Test
    fun `metrics Content-Type is the spaced parity contract exactly`() {
        val resp = send("GET", "/metrics")
        assertEquals(200, resp.statusCode())
        assertEquals(
            "text/plain; version=0.0.4",
            resp.headers().firstValue("Content-Type").orElse(null),
            "the /metrics Content-Type must equal the spaced parity contract byte-for-byte",
        )
    }

    /**
     * ★ The load-bearing wiring proof: install the file-config live provider, then
     * rewrite the SAME flag file and observe /greeting flip on the SAME running
     * server with NO restart. Proves the seam flips the REAL endpoint.
     */
    @Test
    fun `greeting live-flips on the same running server with no restart`(
        @TempDir tempDir: Path,
    ) {
        val flagFile = tempDir.resolve("flags.json")
        Files.writeString(flagFile, """{"new_greeting":false}""")
        FeatureFlags.setProvider(fileConfigProvider(flagFile.toString()))

        val off = send("GET", "/greeting")
        assertEquals("""{"greeting":"Hello, world!"}""", off.body(), "pre-flip must serve the default greeting")

        // Rewrite the SAME file — no server restart between these two GETs.
        Files.writeString(flagFile, """{"new_greeting":true}""")
        val on = send("GET", "/greeting")
        assertEquals("""{"greeting":"Hello, world! (new)"}""", on.body(), "post-flip must serve the new greeting")
    }

    @Test
    fun `GET carries the four security headers exactly once and a neutral Server`() {
        val resp = send("GET", "/healthz")
        assertEquals(200, resp.statusCode())
        assertSecurityHeadersExactlyOnce(resp)
    }

    @Test
    fun `every non-GET method returns a hardened 404 with security headers`() {
        for (method in listOf("POST", "PUT", "DELETE", "PATCH", "OPTIONS")) {
            val resp = send(method, "/greeting")
            assertEquals(404, resp.statusCode(), "$method status")
            assertEquals("""{"error":"not found"}""", resp.body(), "$method body")
            assertSecurityHeadersExactlyOnce(resp)
        }
    }

    @Test
    fun `HEAD returns a 404 with security headers and no body`() {
        val resp = send("HEAD", "/healthz")
        assertEquals(404, resp.statusCode())
        assertEquals("", resp.body(), "HEAD must carry no body")
        assertSecurityHeadersExactlyOnce(resp)
    }

    @Test
    fun `unknown GET path returns the hardened JSON 404`() {
        val resp = send("GET", "/nope")
        assertEquals(404, resp.statusCode())
        assertEquals("""{"error":"not found"}""", resp.body())
        assertSecurityHeadersExactlyOnce(resp)
    }

    @Test
    fun `a valid inbound X-Request-Id is echoed into the span`() {
        val validId = "abc-123_valid.ID"
        val got = spanRequestIdFor(mapOf("X-Request-Id" to validId))
        assertEquals(validId, got, "the honoured inbound id must reach the span")
    }

    @Test
    fun `an oversized inbound X-Request-Id is replaced by a minted id`() {
        val bad = "x".repeat(129)
        val minted = spanRequestIdFor(mapOf("X-Request-Id" to bad))
        assertNotEquals(bad, minted, "oversized inbound id must be rejected, not echoed")
        assertEquals(32, minted.length, "minted id must be 32 hex chars")
    }

    /**
     * Drive a GET /healthz with [headers] and return the request_id its emitted span
     * carried. Telemetry is emitted AFTER the response is written (on the worker
     * thread), and spans go to stdout when OTEL_TRACE_FILE is unset — so capture
     * stdout and poll for the span, mirroring the go suite's trace-file poll.
     */
    private fun spanRequestIdFor(headers: Map<String, String>): String {
        val original = System.out
        val buffer = ByteArrayOutputStream()
        System.setOut(PrintStream(buffer, true, "UTF-8"))
        try {
            val resp = send("GET", "/healthz", headers)
            assertEquals(200, resp.statusCode())
            val deadline = System.currentTimeMillis() + 2_000
            while (System.currentTimeMillis() < deadline) {
                lastSpanRequestId(buffer.toString("UTF-8"))?.let { return it }
                Thread.sleep(10)
            }
            fail("no span was emitted to stdout within the timeout")
        } finally {
            System.setOut(original)
        }
    }

    /** Parse ndjson lines; return the request_id of the last valid span, or null. */
    private fun lastSpanRequestId(captured: String): String? {
        var found: String? = null
        for (line in captured.lineSequence()) {
            if (line.isBlank()) continue
            val node: JsonNode =
                try {
                    mapper.readTree(line)
                } catch (_: Exception) {
                    continue
                }
            val attrs = node.get("attributes") ?: continue
            val id = attrs.get("request_id") ?: continue
            if (node.has("trace_id")) found = id.asText()
        }
        return found
    }
}
