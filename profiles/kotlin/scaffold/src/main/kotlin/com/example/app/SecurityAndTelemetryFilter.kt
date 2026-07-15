package com.example.app

import jakarta.servlet.FilterChain
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import org.springframework.core.Ordered
import org.springframework.core.annotation.Order
import org.springframework.stereotype.Component
import org.springframework.web.filter.OncePerRequestFilter
import java.time.Instant

/**
 * The server spine's cross-cutting middleware (Kotlin/Spring profile) — the ONE
 * place the profile assembles the flags + telemetry modules onto the running HTTP
 * layer. Mirrors go's `instrument` middleware and python's `AppHandler` overrides.
 *
 * On EVERY request, regardless of method or route, this filter:
 *  - stamps the four security headers + a neutral `Server: reference-app` (no
 *    framework/version leak) EXACTLY ONCE each (via `setHeader`, which replaces);
 *  - honours an inbound `X-Request-Id` ONLY when it matches [REQUEST_ID_RE]
 *    (bounded charset + length), else mints a fresh random id — an unbounded inbound
 *    header never flows verbatim into a log/span;
 *  - routes GET through the Spring controllers (`/healthz`, `/greeting`, `/metrics`,
 *    and NotFoundAdvice's JSON 404 for anything else); short-circuits every
 *    non-GET method (incl. HEAD) to the hardened JSON 404 BEFORE dispatch, so a
 *    non-GET never yields a 405 and HEAD carries the headers with no body;
 *  - emits per-request telemetry AFTER the response is written — a structured log, a
 *    bounded-cardinality metric, and an OTel-semantic span — so even a 404 is
 *    observed.
 *
 * Ordered first so the security baseline and the non-GET short-circuit apply before
 * any other filter in the chain.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
class SecurityAndTelemetryFilter : OncePerRequestFilter() {
    override fun doFilterInternal(
        request: HttpServletRequest,
        response: HttpServletResponse,
        filterChain: FilterChain,
    ) {
        val startNanos = System.nanoTime()
        val startInstant = Instant.now()
        val requestId = resolveRequestId(request)

        // Stamp the security baseline + neutral Server header exactly once each.
        for ((name, value) in SECURITY_HEADERS) {
            response.setHeader(name, value)
        }
        response.setHeader("Server", "reference-app")

        val method = request.method
        val status: Int =
            if (method == "GET") {
                filterChain.doFilter(request, response)
                response.status
            } else {
                writeNotFound(response, withBody = method != "HEAD")
            }

        emitTelemetry(request, method, status, startInstant, startNanos, requestId)
    }

    /** Write the hardened JSON 404 for a non-GET method (no body on HEAD). */
    private fun writeNotFound(
        response: HttpServletResponse,
        withBody: Boolean,
    ): Int {
        response.status = HttpServletResponse.SC_NOT_FOUND
        response.setHeader("Content-Type", "application/json")
        if (withBody) {
            response.setHeader("Content-Length", NOT_FOUND_JSON.size.toString())
            response.outputStream.write(NOT_FOUND_JSON)
        } else {
            response.setHeader("Content-Length", "0")
        }
        return HttpServletResponse.SC_NOT_FOUND
    }

    /** Validated inbound X-Request-Id, or a freshly minted 32-hex-char random id. */
    private fun resolveRequestId(request: HttpServletRequest): String {
        val raw = request.getHeader("X-Request-Id")
        return if (raw != null && REQUEST_ID_RE.matches(raw)) raw else Telemetry.newSpanIds().first
    }

    /** Log + metric + span, emitted after the response is written (mirrors the references). */
    private fun emitTelemetry(
        request: HttpServletRequest,
        method: String,
        status: Int,
        startInstant: Instant,
        startNanos: Long,
        requestId: String,
    ) {
        val elapsedNanos = System.nanoTime() - startNanos
        val latencyMs = elapsedNanos / NANOS_PER_MILLI
        val startUnixNano = startInstant.epochSecond * NANOS_PER_SECOND + startInstant.nano
        val requestUri = request.requestURI
        val fullPath = request.queryString?.let { "$requestUri?$it" } ?: requestUri
        // Span name strips the query string (cardinality + secret hygiene).
        val spanName = "$method $requestUri"

        // NOTE: `path` below is the full request URI INCLUDING any query string. The
        // reference app's routes carry no secrets, but an adopter whose query params
        // can carry tokens/secrets MUST redact `path` here before logging.
        Telemetry.log(
            mapOf(
                "request_id" to requestId,
                "method" to method,
                "path" to fullPath,
                "status" to status,
                "latency_ms" to latencyMs,
            ),
        )
        Telemetry.recordMetric(method, status, latencyMs)
        Telemetry.emitSpan(
            Telemetry.buildSpan(
                name = spanName,
                startUnixNano = startUnixNano,
                endUnixNano = startUnixNano + elapsedNanos,
                attributes =
                    mapOf(
                        "http.request.method" to method,
                        "http.response.status_code" to status.toString(),
                        "request_id" to requestId,
                    ),
                statusCode = status,
            ),
        )
    }

    companion object {
        /** The four security headers stamped on EVERY response. */
        private val SECURITY_HEADERS: Map<String, String> =
            linkedMapOf(
                "X-Content-Type-Options" to "nosniff",
                "X-Frame-Options" to "DENY",
                "Content-Security-Policy" to "default-src 'none'",
                "Referrer-Policy" to "no-referrer",
            )

        /**
         * Bounds an inbound X-Request-Id to a safe token (charset + length). Rejecting
         * malformed/oversized ids keeps an unbounded header out of logs/spans.
         */
        private val REQUEST_ID_RE = Regex("[A-Za-z0-9._-]{1,128}")

        /** The compact 404 body (matches the go/python references byte-for-byte). */
        private val NOT_FOUND_JSON: ByteArray = """{"error":"not found"}""".toByteArray(Charsets.UTF_8)

        private const val NANOS_PER_MILLI = 1_000_000.0
        private const val NANOS_PER_SECOND = 1_000_000_000L
    }
}
