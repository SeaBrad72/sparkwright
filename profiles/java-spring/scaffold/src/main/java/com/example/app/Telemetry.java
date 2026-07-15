package com.example.app;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Pure telemetry primitives — spans, bounded-cardinality Prometheus metrics, and correlated JSON
 * logs. The importable core the app server calls per request.
 *
 * <p>Mirrors the go/python/typescript-node references ({@code telemetry.go} / {@code
 * telemetry.py}): OTel-semantic spans in the exact {@code scripts/otel-trace.sh} schema, Prometheus
 * text exposition, and structured logs — deliberately dependency-light (stdlib + Jackson, already
 * on the classpath via {@code spring-boot-starter-web}) and free of any socket/handler code so the
 * logic is unit-tested here and the I/O surface (the server) is wired separately. Sinks are chosen
 * by env, exactly like the reference: spans go to {@code OTEL_TRACE_FILE} if set (append) else
 * stdout; logs carry {@code SERVICE_NAME} (default {@code "reference-app"}).
 *
 * <p>The exact literal series names ({@code http_requests_total}, {@code
 * http_request_duration_seconds_total}) are load-bearing: {@code
 * conformance/metrics-endpoint-wired.sh} greps for them verbatim, so a Micrometer/Actuator default
 * naming scheme would not satisfy the kit's cross-stack parity contract without hand-rolling this
 * exact exposition — which is what this class does.
 */
public final class Telemetry {

  private Telemetry() {}

  /**
   * Bounded label set. An unknown method is bucketed as "other" so a hostile caller cannot explode
   * Prometheus series cardinality (path is intentionally NEVER a label).
   */
  private static final Set<String> KNOWN_METHODS =
      Set.of("GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS");

  private static final SecureRandom RANDOM = new SecureRandom();
  private static final HexFormat HEX = HexFormat.of();
  private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();
  private static final String DEFAULT_SERVICE_NAME = "reference-app";

  /**
   * Module-level counter state. Package-private (not {@code private}) so the test in this same
   * package can exercise the escaping-defensiveness path directly, mirroring the go reference's
   * package-level state. Guarded by {@link #METRICS_LOCK}; reset via {@link #resetMetrics()} for
   * lifecycle/test isolation.
   */
  static final Object METRICS_LOCK = new Object();

  static final Map<MetricKey, Long> requestsTotal = new HashMap<>();
  static double durationSecondsTotal = 0.0;

  /** The (method, status) tuple keying the request counter. */
  record MetricKey(String method, int status) {}

  /** A fresh (traceId, spanId) pair: 16-byte and 8-byte cryptographic hex. */
  public record SpanIds(String traceId, String spanId) {}

  /** Returns a fresh (traceId, spanId): 16-byte and 8-byte cryptographic hex. */
  public static SpanIds newSpanIds() {
    return new SpanIds(randomHex(16), randomHex(8));
  }

  private static String randomHex(int byteLength) {
    byte[] bytes = new byte[byteLength];
    RANDOM.nextBytes(bytes);
    return HEX.formatHex(bytes);
  }

  /**
   * Builds an OTel-semantic span in the reference {@code otel-trace.sh} schema.
   *
   * <p>{@code *_unix_nano} are emitted as decimal STRINGS (OTLP/JSON represents them as strings,
   * avoiding the float precision loss unix nanos, ~1.8e18, would incur). {@code status.code} is
   * ERROR for &gt;= 500, else OK. A fresh trace/span id is minted and {@code parent_span_id} is
   * null (root span); the server correlates via {@code attributes}.
   */
  public static Map<String, Object> buildSpan(
      String name,
      long startUnixNano,
      long endUnixNano,
      Map<String, String> attributes,
      int statusCode) {
    SpanIds ids = newSpanIds();
    Map<String, Object> span = new LinkedHashMap<>();
    span.put("trace_id", ids.traceId());
    span.put("span_id", ids.spanId());
    span.put("parent_span_id", null);
    span.put("name", name);
    span.put("start_unix_nano", Long.toString(startUnixNano));
    span.put("end_unix_nano", Long.toString(endUnixNano));
    span.put("attributes", attributes);
    span.put("status", Map.of("code", statusCode >= 500 ? "ERROR" : "OK"));
    return span;
  }

  /**
   * Writes the span as one JSON line to {@code OTEL_TRACE_FILE} (append) if set, else stdout. It
   * degrades silently on any sink error — telemetry must never break the request path it observes.
   */
  public static void emitSpan(Map<String, Object> span) {
    emitSpan(span, System.getenv("OTEL_TRACE_FILE"));
  }

  /** Package-private overload taking the sink explicitly, so tests need not mutate env vars. */
  static void emitSpan(Map<String, Object> span, String sink) {
    String line;
    try {
      line = OBJECT_MAPPER.writeValueAsString(span);
    } catch (JsonProcessingException e) {
      return;
    }
    if (sink != null && !sink.isBlank()) {
      try {
        Files.writeString(
            Path.of(sink),
            line + "\n",
            StandardCharsets.UTF_8,
            StandardOpenOption.CREATE,
            StandardOpenOption.APPEND);
      } catch (IOException e) {
        // Degrade silently — telemetry must never break the request path it observes.
      }
      return;
    }
    System.out.print(line + "\n");
  }

  /**
   * Increments the request counter for (methodLabel, status) and adds to the duration total. {@code
   * methodLabel} is the method when in {@link #KNOWN_METHODS}, else "other" (bounded cardinality).
   * The shared counter maps are guarded by {@link #METRICS_LOCK}.
   */
  public static void recordMetric(String method, int status, double latencyMs) {
    String label = KNOWN_METHODS.contains(method) ? method : "other";
    synchronized (METRICS_LOCK) {
      MetricKey key = new MetricKey(label, status);
      requestsTotal.merge(key, 1L, Long::sum);
      durationSecondsTotal += latencyMs / 1000.0;
    }
  }

  /**
   * Escapes a Prometheus label value per the text exposition spec ({@code \}, {@code "}, {@code
   * \n}). Defensive: an unusual value can never break a series line or inject one.
   */
  static String escapeLabelValue(String value) {
    return value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n");
  }

  /**
   * Renders the two counters as Prometheus text exposition (trailing newline). Series are emitted
   * in a stable (method, status) order so the output is deterministic despite {@link HashMap}'s
   * unspecified iteration order.
   */
  public static String renderMetrics() {
    StringBuilder builder = new StringBuilder();
    synchronized (METRICS_LOCK) {
      builder
          .append("# HELP http_requests_total Total number of HTTP requests handled.\n")
          .append("# TYPE http_requests_total counter\n");

      List<MetricKey> keys = new ArrayList<>(requestsTotal.keySet());
      keys.sort(Comparator.comparing(MetricKey::method).thenComparingInt(MetricKey::status));
      for (MetricKey key : keys) {
        builder
            .append("http_requests_total{method=\"")
            .append(escapeLabelValue(key.method()))
            .append("\",status=\"")
            .append(key.status())
            .append("\"} ")
            .append(requestsTotal.get(key))
            .append('\n');
      }

      builder
          .append(
              "# HELP http_request_duration_seconds_total Total accumulated request duration in"
                  + " seconds.\n")
          .append("# TYPE http_request_duration_seconds_total counter\n")
          .append("http_request_duration_seconds_total ")
          .append(formatDuration(durationSecondsTotal))
          .append('\n');
    }
    return builder.toString();
  }

  /** Renders like go's {@code strconv.FormatFloat(v, 'g', -1, 64)}: "0" not "0.0". */
  private static String formatDuration(double value) {
    if (!Double.isInfinite(value) && !Double.isNaN(value) && value == Math.floor(value)) {
      return Long.toString((long) value);
    }
    return Double.toString(value);
  }

  /** Clears the module-level counter state (lifecycle/test helper). */
  public static void resetMetrics() {
    synchronized (METRICS_LOCK) {
      requestsTotal.clear();
      durationSecondsTotal = 0.0;
    }
  }

  /**
   * Emits one structured JSON log line to stdout: {@code ts} (RFC3339 UTC), {@code level} "info",
   * {@code service} ({@code SERVICE_NAME} env, default "reference-app"), plus the merged fields.
   *
   * <p>Never pass request bodies, headers, or PII/secrets in {@code fields}.
   */
  public static void log(Map<String, Object> fields) {
    log(fields, System.getenv("SERVICE_NAME"));
  }

  /** Package-private overload taking the service name explicitly, so tests need not mutate env. */
  static void log(Map<String, Object> fields, String serviceOverride) {
    String service =
        (serviceOverride == null || serviceOverride.isBlank())
            ? DEFAULT_SERVICE_NAME
            : serviceOverride;
    Map<String, Object> record = new LinkedHashMap<>();
    record.put("ts", Instant.now().toString());
    record.put("level", "info");
    record.put("service", service);
    record.putAll(fields);
    try {
      System.out.print(OBJECT_MAPPER.writeValueAsString(record) + "\n");
    } catch (JsonProcessingException e) {
      // Degrade silently — telemetry must never break the request path it observes.
    }
  }
}
