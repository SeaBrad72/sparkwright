package com.example.app

import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import java.io.File
import java.security.SecureRandom
import java.time.Instant
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * Pure telemetry primitives — spans, bounded-cardinality Prometheus metrics, and
 * correlated JSON logs. The importable core the app server calls per request.
 *
 * Mirrors the go/python references (`telemetry.go` / `telemetry.py`): OTel-semantic
 * spans in the exact `scripts/otel-trace.sh` schema, Prometheus text exposition, and
 * structured logs — deliberately free of any socket/handler code so the logic is
 * unit-tested here and the I/O surface (the server) is wired separately. Sinks are
 * chosen by env, exactly like the reference: spans go to `OTEL_TRACE_FILE` if set
 * (append) else stdout; logs carry `SERVICE_NAME` (default `"reference-app"`).
 */
object Telemetry {
    /**
     * Bounded label set. An unknown (or non-canonical, e.g. lowercase) method is
     * bucketed as "other" so a hostile caller cannot explode Prometheus series
     * cardinality (path is intentionally NEVER a label).
     */
    private val knownMethods = setOf("GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS")

    private const val DEFAULT_SERVICE_NAME = "reference-app"
    private const val TRACE_ID_BYTES = 16
    private const val SPAN_ID_BYTES = 8

    private val mapper = jacksonObjectMapper()
    private val secureRandom = SecureRandom()

    // Module-level counter state, guarded by metricsLock. Reset via resetMetrics()
    // for lifecycle/test isolation.
    private val metricsLock = ReentrantLock()
    private val requestsTotal = mutableMapOf<Pair<String, Int>, Long>()
    private var durationSecondsTotal = 0.0

    /** n cryptographically random bytes as a lowercase hex string. */
    private fun randomHex(byteCount: Int): String {
        val bytes = ByteArray(byteCount)
        secureRandom.nextBytes(bytes)
        return bytes.joinToString("") { "%02x".format(it) }
    }

    /** Return a fresh (traceId, spanId): 16-byte and 8-byte cryptographic hex. */
    fun newSpanIds(): Pair<String, String> = randomHex(TRACE_ID_BYTES) to randomHex(SPAN_ID_BYTES)

    /**
     * Build an OTel-semantic span in the reference `otel-trace.sh` schema.
     *
     * `*_unix_nano` are emitted as decimal STRINGS (OTLP/JSON represents them as
     * strings, avoiding the float precision loss unix nanos (~1.8e18) would incur).
     * `status.code` is `ERROR` for `>= 500`, else `OK`. A fresh trace/span id is
     * minted and `parent_span_id` is null (root span); the server correlates via
     * `attributes`.
     */
    fun buildSpan(
        name: String,
        startUnixNano: Long,
        endUnixNano: Long,
        attributes: Map<String, String>,
        statusCode: Int,
    ): Map<String, Any?> {
        val (traceId, spanId) = newSpanIds()
        val code = if (statusCode >= HTTP_SERVER_ERROR_FLOOR) "ERROR" else "OK"
        return linkedMapOf(
            "trace_id" to traceId,
            "span_id" to spanId,
            "parent_span_id" to null,
            "name" to name,
            "start_unix_nano" to startUnixNano.toString(),
            "end_unix_nano" to endUnixNano.toString(),
            "attributes" to attributes,
            "status" to mapOf("code" to code),
        )
    }

    /**
     * Write the span as one JSON line to `OTEL_TRACE_FILE` (append) if set, else
     * stdout. Degrades silently on any sink error — telemetry must never break the
     * request path it observes.
     *
     * [sinkPath] defaults to the real `OTEL_TRACE_FILE` env var — the JVM has no
     * supported way to mutate `System.getenv` for a test, so (mirroring
     * [FeatureFlags]'s injectable-lookup seam) it is a parameter with an
     * env-reading default rather than a hardcoded read, letting unit tests drive
     * both branches directly.
     */
    @Suppress("TooGenericExceptionCaught", "SwallowedException")
    fun emitSpan(
        span: Map<String, Any?>,
        sinkPath: String? = System.getenv("OTEL_TRACE_FILE"),
    ) {
        val line =
            try {
                mapper.writeValueAsString(span)
            } catch (e: Exception) {
                return
            }
        if (!sinkPath.isNullOrEmpty()) {
            try {
                File(sinkPath).appendText(line + "\n")
            } catch (e: Exception) {
                // Sink unwritable (e.g. missing directory) — degrade silently.
            }
            return
        }
        println(line)
    }

    /**
     * Increment the request counter for `(methodLabel, status)` and add to the
     * duration total. `methodLabel` is `method` when in [knownMethods], else
     * `"other"` (bounded cardinality). The shared counter state is guarded by
     * [metricsLock].
     */
    fun recordMetric(
        method: String?,
        status: Int,
        latencyMs: Double,
    ) {
        val label = if (method != null && method in knownMethods) method else "other"
        metricsLock.withLock {
            val key = label to status
            requestsTotal[key] = (requestsTotal[key] ?: 0L) + 1L
            durationSecondsTotal += latencyMs / MILLIS_PER_SECOND
        }
    }

    /**
     * Escape a Prometheus label value per the text exposition spec (`\`, `"`,
     * `\n`). Defensive: an unusual value can never break a series line or inject
     * one.
     */
    fun escapeLabelValue(value: String): String =
        value
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")

    /**
     * Render the two counters as Prometheus text exposition (trailing newline).
     * Series are emitted in a stable `(method, status)` order so output is
     * deterministic.
     */
    fun renderMetrics(): String =
        metricsLock.withLock {
            val builder = StringBuilder()
            builder.append("# HELP http_requests_total Total number of HTTP requests handled.\n")
            builder.append("# TYPE http_requests_total counter\n")
            requestsTotal.keys
                .sortedWith(compareBy({ it.first }, { it.second }))
                .forEach { key ->
                    val count = requestsTotal.getValue(key)
                    val method = escapeLabelValue(key.first)
                    builder.append(
                        "http_requests_total{method=\"$method\",status=\"${key.second}\"} $count\n",
                    )
                }
            builder.append(
                "# HELP http_request_duration_seconds_total " +
                    "Total accumulated request duration in seconds.\n",
            )
            builder.append("# TYPE http_request_duration_seconds_total counter\n")
            builder.append(
                "http_request_duration_seconds_total ${formatDuration(durationSecondsTotal)}\n",
            )
            builder.toString()
        }

    /** Clear module-level counter state (lifecycle/test helper). */
    fun resetMetrics() {
        metricsLock.withLock {
            requestsTotal.clear()
            durationSecondsTotal = 0.0
        }
    }

    /**
     * Emit one structured JSON log line to stdout: `ts` (RFC3339 UTC), `level`
     * `"info"`, `service` (`SERVICE_NAME` env, default `"reference-app"`), plus the
     * merged fields.
     *
     * Never pass request bodies, headers, or PII/secrets in `fields`.
     *
     * [serviceName] defaults to the real `SERVICE_NAME` env var — same
     * injectable-default seam as [emitSpan]'s `sinkPath`, for direct unit testing.
     */
    fun log(
        fields: Map<String, Any?>,
        serviceName: String? = System.getenv("SERVICE_NAME"),
    ) {
        val service = if (serviceName.isNullOrEmpty()) DEFAULT_SERVICE_NAME else serviceName
        val record =
            linkedMapOf<String, Any?>(
                "ts" to Instant.now().toString(),
                "level" to "info",
                "service" to service,
            )
        record.putAll(fields)
        println(mapper.writeValueAsString(record))
    }

    /**
     * Format a duration total the way Go's `strconv.FormatFloat(v, 'g', -1, 64)`
     * would: the shortest round-trippable decimal (Kotlin's [Double.toString]
     * already guarantees that, same as Go's algorithm), with no forced trailing
     * `.0` (`0.75` stays `0.75`; whole numbers render as `0`, `2`, never
     * `0.0`/`2.0`).
     */
    private fun formatDuration(value: Double): String {
        val rendered = value.toString()
        return if (rendered.endsWith(".0")) rendered.dropLast(WHOLE_NUMBER_SUFFIX_LENGTH) else rendered
    }
}

private const val HTTP_SERVER_ERROR_FLOOR = 500
private const val MILLIS_PER_SECOND = 1000.0
private const val WHOLE_NUMBER_SUFFIX_LENGTH = 2
