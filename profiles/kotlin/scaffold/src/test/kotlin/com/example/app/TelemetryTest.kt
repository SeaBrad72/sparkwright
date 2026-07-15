package com.example.app

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.ByteArrayOutputStream
import java.io.PrintStream
import java.nio.file.Files
import java.nio.file.Path
import java.time.Instant
import java.time.format.DateTimeParseException
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Unit tests for the pure telemetry primitives (spans, bounded-cardinality
 * Prometheus metrics, structured logs). Mirrors the go/python reference test
 * suites (telemetry_test.go / test_telemetry.py) so the shapes stay identical
 * across profiles. [Telemetry.emitSpan]'s `sinkPath` and [Telemetry.log]'s
 * `serviceName` are driven directly (the injectable-default seam) instead of
 * mutating the real process environment, which the JVM does not support.
 */
class TelemetryTest {
    private val mapper: ObjectMapper = jacksonObjectMapper()

    @AfterEach
    fun resetState() {
        Telemetry.resetMetrics()
    }

    /** Redirect stdout for the duration of [fn] and return what it printed. */
    private fun captureStdout(fn: () -> Unit): String {
        val original = System.out
        val buffer = ByteArrayOutputStream()
        System.setOut(PrintStream(buffer, true, "UTF-8"))
        try {
            fn()
        } finally {
            System.setOut(original)
        }
        return buffer.toString("UTF-8")
    }

    @Test
    fun `newSpanIds are hex of the right width`() {
        val (traceId, spanId) = Telemetry.newSpanIds()
        assertEquals(32, traceId.length) // 16 bytes hex
        assertEquals(16, spanId.length) // 8 bytes hex
        traceId.toBigInteger(16) // valid hex (throws otherwise)
        spanId.toBigInteger(16)
    }

    @Test
    fun `newSpanIds are random`() {
        assertNotEquals(Telemetry.newSpanIds(), Telemetry.newSpanIds())
    }

    @Test
    fun `buildSpan has all required keys`() {
        val span =
            Telemetry.buildSpan(
                name = "GET /healthz",
                startUnixNano = 1,
                endUnixNano = 2,
                attributes = mapOf("http.request.method" to "GET"),
                statusCode = 200,
            )
        for (key in listOf(
            "trace_id", "span_id", "parent_span_id", "name",
            "start_unix_nano", "end_unix_nano", "attributes", "status",
        )) {
            assertTrue(span.containsKey(key), "missing key $key")
        }
        assertEquals("GET /healthz", span["name"])
        assertNull(span["parent_span_id"])
        assertEquals(mapOf("http.request.method" to "GET"), span["attributes"])
        val traceId = span["trace_id"] as String
        val spanId = span["span_id"] as String
        assertEquals(32, traceId.length)
        assertEquals(16, spanId.length)
    }

    @Test
    fun `buildSpan nanos are decimal strings`() {
        val span =
            Telemetry.buildSpan(
                name = "x",
                startUnixNano = 1_700_000_000_000_000_000L,
                endUnixNano = 1_700_000_000_500_000_000L,
                attributes = emptyMap(),
                statusCode = 200,
            )
        assertEquals("1700000000000000000", span["start_unix_nano"])
        assertEquals("1700000000500000000", span["end_unix_nano"])
    }

    @Test
    fun `buildSpan status boundary is OK below 500 and ERROR at or above`() {
        val cases = listOf(200 to "OK", 404 to "OK", 499 to "OK", 500 to "ERROR", 503 to "ERROR")
        for ((statusCode, want) in cases) {
            val span = Telemetry.buildSpan("op", 0, 1, emptyMap(), statusCode)
            @Suppress("UNCHECKED_CAST")
            val status = span["status"] as Map<String, Any?>
            assertEquals(want, status["code"], "status for $statusCode")
        }
    }

    @Test
    fun `emitSpan appends ndjson to the given sink path`(
        @TempDir tempDir: Path,
    ) {
        val sink = tempDir.resolve("spans.ndjson")
        Telemetry.emitSpan(Telemetry.buildSpan("one", 0, 1, emptyMap(), 200), sinkPath = sink.toString())
        Telemetry.emitSpan(Telemetry.buildSpan("two", 2, 3, emptyMap(), 500), sinkPath = sink.toString())

        val lines = Files.readAllLines(sink)
        assertEquals(2, lines.size)
        assertEquals("one", mapper.readTree(lines[0])["name"].asText())
        assertEquals("two", mapper.readTree(lines[1])["name"].asText())
    }

    @Test
    fun `emitSpan writes ndjson to stdout when sinkPath is null`() {
        val out =
            captureStdout {
                Telemetry.emitSpan(Telemetry.buildSpan("stdout-span", 10, 20, emptyMap(), 200), sinkPath = null)
            }
        val node = mapper.readTree(out.trim())
        assertEquals("stdout-span", node["name"].asText())
        assertTrue(out.endsWith("\n"))
    }

    @Test
    fun `emitSpan writes ndjson to stdout when sinkPath is empty`() {
        val out =
            captureStdout {
                Telemetry.emitSpan(Telemetry.buildSpan("stdout-span-2", 10, 20, emptyMap(), 200), sinkPath = "")
            }
        assertEquals("stdout-span-2", mapper.readTree(out.trim())["name"].asText())
    }

    @Test
    fun `emitSpan degrades silently when the sink cannot be opened`(
        @TempDir tempDir: Path,
    ) {
        val badSink = tempDir.resolve("no-such-dir").resolve("spans.ndjson")
        // Must not throw even though the parent directory does not exist.
        Telemetry.emitSpan(Telemetry.buildSpan("dropped", 0, 1, emptyMap(), 200), sinkPath = badSink.toString())
    }

    @Test
    fun `the shipped emitSpan reads the real OTEL_TRACE_FILE env and defaults to stdout`() {
        // OTEL_TRACE_FILE is (virtually certainly) unset in CI/local env -> stdout.
        val out = captureStdout { Telemetry.emitSpan(Telemetry.buildSpan("env-default", 0, 1, emptyMap(), 200)) }
        assertEquals("env-default", mapper.readTree(out.trim())["name"].asText())
    }

    @Test
    fun `recordMetric buckets unknown and non-canonical methods as other`() {
        Telemetry.recordMetric("GET", 200, 5.0)
        Telemetry.recordMetric("BREW", 418, 3.0) // unknown method
        Telemetry.recordMetric("get", 200, 1.0) // case-sensitive: lowercase is not known

        val out = Telemetry.renderMetrics()
        assertTrue(out.contains("http_requests_total{method=\"GET\",status=\"200\"} 1"))
        assertTrue(out.contains("http_requests_total{method=\"other\",status=\"418\"} 1"))
        assertTrue(out.contains("http_requests_total{method=\"other\",status=\"200\"} 1"))
        assertFalse(out.contains("method=\"BREW\""))
        assertFalse(out.contains("method=\"get\""))
    }

    @Test
    fun `recordMetric buckets a null method as other`() {
        Telemetry.recordMetric(null, 200, 1.0)
        val out = Telemetry.renderMetrics()
        assertTrue(out.contains("http_requests_total{method=\"other\",status=\"200\"} 1"))
    }

    @Test
    fun `recordMetric counter aggregates repeated calls`() {
        Telemetry.recordMetric("POST", 201, 2.0)
        Telemetry.recordMetric("POST", 201, 2.0)
        val out = Telemetry.renderMetrics()
        assertTrue(out.contains("http_requests_total{method=\"POST\",status=\"201\"} 2"))
    }

    @Test
    fun `renderMetrics emits HELP and TYPE lines and a trailing newline`() {
        Telemetry.recordMetric("GET", 200, 1.0)
        val out = Telemetry.renderMetrics()
        assertTrue(out.contains("# HELP http_requests_total"))
        assertTrue(out.contains("# TYPE http_requests_total counter"))
        assertTrue(out.contains("# HELP http_request_duration_seconds_total"))
        assertTrue(out.contains("# TYPE http_request_duration_seconds_total counter"))
        assertTrue(out.endsWith("\n"))
    }

    @Test
    fun `renderMetrics on empty state is still valid exposition`() {
        val out = Telemetry.renderMetrics()
        assertTrue(out.contains("# TYPE http_requests_total counter"))
        assertTrue(out.contains("http_request_duration_seconds_total 0"))
    }

    @Test
    fun `renderMetrics duration accumulates`() {
        Telemetry.recordMetric("GET", 200, 500.0) // 0.5s
        Telemetry.recordMetric("GET", 200, 250.0) // 0.25s -> total 0.75s
        val out = Telemetry.renderMetrics()
        assertTrue(out.contains("http_request_duration_seconds_total 0.75"))
    }

    @Test
    fun `renderMetrics emits series in a stable method-then-status order`() {
        Telemetry.recordMetric("POST", 201, 1.0)
        Telemetry.recordMetric("GET", 500, 1.0)
        Telemetry.recordMetric("GET", 200, 1.0)
        val out = Telemetry.renderMetrics()
        val getIdx200 = out.indexOf("method=\"GET\",status=\"200\"")
        val getIdx500 = out.indexOf("method=\"GET\",status=\"500\"")
        val postIdx = out.indexOf("method=\"POST\",status=\"201\"")
        assertTrue(getIdx200 in 0 until getIdx500)
        assertTrue(getIdx500 in 0 until postIdx)
    }

    @Test
    fun `resetMetrics clears request series and zeroes duration`() {
        Telemetry.recordMetric("GET", 200, 5.0)
        Telemetry.resetMetrics()
        val out = Telemetry.renderMetrics()
        assertFalse(out.contains("http_requests_total{"))
        assertTrue(out.contains("http_request_duration_seconds_total 0"))
    }

    @Test
    fun `escapeLabelValue escapes backslash quote and newline`() {
        assertEquals("GET", Telemetry.escapeLabelValue("GET"))
        assertEquals("a\\\"b", Telemetry.escapeLabelValue("a\"b"))
        assertEquals("a\\\\b", Telemetry.escapeLabelValue("a\\b"))
        assertEquals("a\\nb", Telemetry.escapeLabelValue("a\nb"))
    }

    @Test
    fun `escapeLabelValue escapes hostile input`() {
        val hostile = "evil\"\\\n} injected 999"
        val escaped = Telemetry.escapeLabelValue(hostile)
        assertFalse(escaped.replace("\\\"", "").contains("\""))
        assertFalse(escaped.contains("\n"))
        assertEquals("evil\\\"\\\\\\n} injected 999", escaped)
    }

    @Test
    fun `log emits a structured JSON line with ts level and service`() {
        val out = captureStdout { Telemetry.log(mapOf("request_id" to "abc", "status" to 200), serviceName = null) }
        val record = mapper.readTree(out.trim())
        assertEquals("info", record["level"].asText())
        assertEquals("reference-app", record["service"].asText())
        assertEquals("abc", record["request_id"].asText())
        assertEquals(200, record["status"].asInt())
        assertTrue(record.has("ts"))
        // ts must be RFC3339/ISO-8601 parseable.
        Instant.parse(record["ts"].asText())
    }

    @Test
    fun `log falls back to the default service name when serviceName is empty`() {
        val out = captureStdout { Telemetry.log(mapOf("event" to "boot"), serviceName = "") }
        assertEquals("reference-app", mapper.readTree(out.trim())["service"].asText())
    }

    @Test
    fun `log uses the given serviceName when set`() {
        val out = captureStdout { Telemetry.log(mapOf("event" to "boot"), serviceName = "checkout-svc") }
        assertEquals("checkout-svc", mapper.readTree(out.trim())["service"].asText())
    }

    @Test
    fun `the shipped log reads the real SERVICE_NAME env and defaults to reference-app`() {
        // SERVICE_NAME is (virtually certainly) unset in CI/local env -> default.
        val out = captureStdout { Telemetry.log(mapOf("event" to "boot")) }
        assertEquals("reference-app", mapper.readTree(out.trim())["service"].asText())
    }

    @Test
    fun `log ts rejects a garbage value as a sanity check on the format`() {
        // Documents the expectation the positive assertions above rely on: a
        // non-RFC3339 string must fail Instant.parse.
        try {
            Instant.parse("not-a-timestamp")
            error("expected DateTimeParseException")
        } catch (e: DateTimeParseException) {
            // expected
        }
    }
}
