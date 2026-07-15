package com.example.app;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Prometheus metrics exposition — {@code GET /metrics}.
 *
 * <p>Renders {@link Telemetry#renderMetrics()} as Prometheus text exposition ({@code text/plain;
 * version=0.0.4}). The exact literal series names ({@code http_requests_total}, {@code
 * http_request_duration_seconds_total}) are load-bearing: {@code
 * conformance/metrics-endpoint-wired.sh} greps for them verbatim, which is why the hand-rolled
 * {@link Telemetry} exposition is used rather than Micrometer/Actuator's default naming scheme.
 */
@RestController
public class MetricsController {

  /**
   * The Prometheus text exposition content type (version-pinned, matching the go/python spine). Set
   * as a RAW header string rather than via {@code MediaType.parseMediaType}, which normalizes away
   * the space after the {@code ;} and breaks byte-for-byte parity with go/python ({@code
   * text/plain; version=0.0.4}).
   */
  private static final String PROMETHEUS_TEXT = "text/plain; version=0.0.4";

  /**
   * Serves the current metric counters as Prometheus text exposition.
   *
   * @return a 200 whose body is the Prometheus text rendering of the request counters
   */
  @GetMapping("/metrics")
  public ResponseEntity<String> metrics() {
    return ResponseEntity.ok()
        .header("Content-Type", PROMETHEUS_TEXT)
        .body(Telemetry.renderMetrics());
  }
}
