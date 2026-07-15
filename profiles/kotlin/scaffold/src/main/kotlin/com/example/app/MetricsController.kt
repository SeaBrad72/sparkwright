package com.example.app

import jakarta.servlet.http.HttpServletResponse
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RestController

/**
 * Prometheus metrics surface (Kotlin/Spring profile).
 *
 * Serves the bounded-cardinality counters rendered by [Telemetry.renderMetrics] as
 * Prometheus text exposition (`text/plain; version=0.0.4`) — the SAME exposition the
 * go/python references emit, so `/metrics` is byte-identical across profiles.
 *
 * The Content-Type is written as a RAW string literal via `setHeader` — the SAME way
 * [SecurityAndTelemetryFilter] stamps its raw headers — so the space after the
 * semicolon in the cross-profile parity contract (`text/plain; version=0.0.4`)
 * survives verbatim. Routing this through Spring's [org.springframework.http.MediaType]
 * (e.g. `parseMediaType(...)` / `ResponseEntity.contentType(...)`) round-trips the
 * value and normalizes the space AWAY (`text/plain;version=0.0.4`), silently breaking
 * byte-parity with go/python — so we bypass the converter and write bytes directly.
 *
 * NOTE: this profile deliberately renders metrics from the kit's own [Telemetry]
 * primitives rather than Actuator/Micrometer, so the exposition matches the
 * cross-profile parity contract exactly. An adopter who wants the full Micrometer
 * registry can swap this controller for the Actuator Prometheus endpoint.
 */
@RestController
class MetricsController {
    @GetMapping("/metrics")
    fun metrics(response: HttpServletResponse) {
        val body = Telemetry.renderMetrics().toByteArray(Charsets.UTF_8)
        response.status = HttpServletResponse.SC_OK
        // RAW literal — must keep the space after ';' (cross-profile parity contract).
        response.setHeader("Content-Type", METRICS_CONTENT_TYPE)
        response.setHeader("Content-Length", body.size.toString())
        response.outputStream.write(body)
        response.outputStream.flush()
    }

    companion object {
        /**
         * The Prometheus text-exposition Content-Type, byte-identical to the go/python
         * references — INCLUDING the space after the semicolon. Do not route through
         * [org.springframework.http.MediaType]; it normalizes the space away.
         */
        const val METRICS_CONTENT_TYPE = "text/plain; version=0.0.4"
    }
}
