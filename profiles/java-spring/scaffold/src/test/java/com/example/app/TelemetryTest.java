package com.example.app;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;

import com.example.app.Telemetry.MetricKey;
import com.example.app.Telemetry.SpanIds;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.PrintStream;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.function.Executable;
import org.junit.jupiter.api.io.TempDir;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

/**
 * Unit tests for {@link Telemetry} — the span builder, bounded-cardinality Prometheus metrics, and
 * structured JSON logs. Mirrors the go reference's {@code telemetry_test.go} test-for-test so the
 * behavioural contract (schema, status boundary, escaping, cardinality bound) matches across
 * stacks.
 */
class TelemetryTest {

  private static final ObjectMapper JSON = new ObjectMapper();

  @AfterEach
  void resetState() {
    // The counter state is process-global (mirrors go's package-level map); never leak between
    // tests.
    Telemetry.resetMetrics();
  }

  /** Runs {@code action}, redirecting stdout to a buffer, and returns what it printed. */
  private static String captureStdout(Executable action) {
    PrintStream original = System.out;
    ByteArrayOutputStream buffer = new ByteArrayOutputStream();
    System.setOut(new PrintStream(buffer, true, StandardCharsets.UTF_8));
    try {
      action.execute();
    } catch (Throwable t) {
      throw new AssertionError("action under capture threw", t);
    } finally {
      System.setOut(original);
    }
    return buffer.toString(StandardCharsets.UTF_8);
  }

  @Test
  void newSpanIdsHasExpectedLengthsAndIsHex() {
    SpanIds ids = Telemetry.newSpanIds();

    assertThat(ids.traceId()).hasSize(32).matches("[0-9a-f]{32}");
    assertThat(ids.spanId()).hasSize(16).matches("[0-9a-f]{16}");
  }

  @Test
  void newSpanIdsIsRandomAcrossDraws() {
    SpanIds first = Telemetry.newSpanIds();
    SpanIds second = Telemetry.newSpanIds();

    assertThat(second.traceId()).isNotEqualTo(first.traceId());
    assertThat(second.spanId()).isNotEqualTo(first.spanId());
  }

  @Test
  void buildSpanSchema() {
    Map<String, String> attrs = Map.of("http.method", "GET", "http.route", "/healthz");
    Map<String, Object> span = Telemetry.buildSpan("GET /healthz", 1000L, 2500L, attrs, 200);

    assertThat(span.get("start_unix_nano")).isEqualTo("1000");
    assertThat(span.get("end_unix_nano")).isEqualTo("2500");
    assertThat(span.get("parent_span_id")).isNull();
    assertThat(span.get("name")).isEqualTo("GET /healthz");
    @SuppressWarnings("unchecked")
    Map<String, String> gotAttrs = (Map<String, String>) span.get("attributes");
    assertThat(gotAttrs).containsEntry("http.route", "/healthz");

    assertThat((String) span.get("trace_id")).hasSize(32);
    assertThat((String) span.get("span_id")).hasSize(16);
  }

  @ParameterizedTest
  @CsvSource({"200,OK", "404,OK", "499,OK", "500,ERROR", "503,ERROR"})
  void buildSpanStatusBoundary(int statusCode, String wantCode) {
    Map<String, Object> span = Telemetry.buildSpan("op", 0L, 1L, Map.of(), statusCode);

    @SuppressWarnings("unchecked")
    Map<String, Object> status = (Map<String, Object>) span.get("status");
    assertThat(status.get("code")).isEqualTo(wantCode);
  }

  @Test
  void emitSpanWritesToFile(@TempDir Path dir) throws Exception {
    Path sink = dir.resolve("spans.ndjson");

    Telemetry.emitSpan(Telemetry.buildSpan("first", 0L, 1L, Map.of(), 200), sink.toString());
    Telemetry.emitSpan(Telemetry.buildSpan("second", 2L, 3L, Map.of(), 500), sink.toString());

    List<String> lines = Files.readAllLines(sink, StandardCharsets.UTF_8);
    assertThat(lines).hasSize(2); // append semantics, not overwrite
    for (String line : lines) {
      assertThatCode(() -> JSON.readTree(line)).doesNotThrowAnyException();
    }
  }

  @Test
  void emitSpanWritesToStdoutWhenSinkUnset() {
    String out =
        captureStdout(
            () ->
                Telemetry.emitSpan(
                    Telemetry.buildSpan("stdout-span", 10L, 20L, Map.of(), 200), ""));

    JsonNode span = parseJsonLine(out);
    assertThat(span.get("name").asText()).isEqualTo("stdout-span");
  }

  @Test
  void emitSpanBadSinkDoesNotThrow(@TempDir Path dir) {
    // A sink under a nonexistent directory cannot be opened; emitSpan must degrade silently
    // rather than throw and break the request path it observes.
    String badSink = dir.resolve("no-such-dir").resolve("spans.ndjson").toString();

    assertThatCode(
            () ->
                Telemetry.emitSpan(Telemetry.buildSpan("dropped", 0L, 1L, Map.of(), 200), badSink))
        .doesNotThrowAnyException();
  }

  @Test
  void emitSpanPublicOverloadDoesNotThrow() {
    // Exercises the env-driven public entry point (the seam the server actually calls).
    assertThatCode(
            () ->
                captureStdout(
                    () ->
                        Telemetry.emitSpan(Telemetry.buildSpan("via-env", 0L, 1L, Map.of(), 200))))
        .doesNotThrowAnyException();
  }

  @Test
  void recordMetricBoundedCardinality() {
    Telemetry.recordMetric("GET", 200, 5);
    Telemetry.recordMetric("BREW", 418, 3); // unknown method -> "other"
    Telemetry.recordMetric("get", 200, 1); // case-sensitive: lowercase is not known -> "other"

    String out = Telemetry.renderMetrics();

    assertThat(out).contains("http_requests_total{method=\"GET\",status=\"200\"} 1");
    assertThat(out).contains("http_requests_total{method=\"other\",status=\"418\"} 1");
    assertThat(out).contains("http_requests_total{method=\"other\",status=\"200\"} 1");
    assertThat(out).doesNotContain("method=\"BREW\"").doesNotContain("method=\"get\"");
  }

  @Test
  void recordMetricCounterAggregates() {
    Telemetry.recordMetric("POST", 201, 2);
    Telemetry.recordMetric("POST", 201, 2);

    String out = Telemetry.renderMetrics();

    assertThat(out).contains("http_requests_total{method=\"POST\",status=\"201\"} 2");
  }

  @Test
  void renderMetricsShape() {
    Telemetry.recordMetric("GET", 200, 5);

    String out = Telemetry.renderMetrics();

    assertThat(out)
        .contains("# HELP http_requests_total Total number of HTTP requests handled.")
        .contains("# TYPE http_requests_total counter")
        .contains(
            "# HELP http_request_duration_seconds_total Total accumulated request duration in"
                + " seconds.")
        .contains("# TYPE http_request_duration_seconds_total counter")
        .contains("http_request_duration_seconds_total ")
        .endsWith("\n");
  }

  @Test
  void renderMetricsDurationAccumulates() {
    Telemetry.recordMetric("GET", 200, 500); // 0.5s
    Telemetry.recordMetric("GET", 200, 250); // 0.25s -> total 0.75s

    String out = Telemetry.renderMetrics();

    assertThat(out).contains("http_request_duration_seconds_total 0.75");
  }

  @Test
  void resetMetricsClearsState() {
    Telemetry.recordMetric("GET", 200, 5);

    Telemetry.resetMetrics();
    String out = Telemetry.renderMetrics();

    assertThat(out).doesNotContain("http_requests_total{");
    assertThat(out).contains("http_request_duration_seconds_total 0");
  }

  @ParameterizedTest
  @CsvSource(
      delimiterString = "|",
      value = {
        "GET|GET",
        "a\"b|a\\\"b",
        "a\\b|a\\\\b",
      })
  void escapeLabelValue(String input, String want) {
    assertThat(Telemetry.escapeLabelValue(input)).isEqualTo(want);
  }

  @Test
  void escapeLabelValueEscapesNewline() {
    assertThat(Telemetry.escapeLabelValue("a\nb")).isEqualTo("a\\nb");
  }

  @Test
  void renderMetricsEscapesLabels() {
    // Defensive: even if a value with quotes/backslashes/newlines reaches the renderer (bypassing
    // the normal recordMetric bounding), it must not break or inject a series line.
    synchronized (Telemetry.METRICS_LOCK) {
      Telemetry.requestsTotal.put(new MetricKey("x\"\\\n", 200), 1L);
    }

    String out = Telemetry.renderMetrics();

    assertThat(out).contains("method=\"x\\\"\\\\\\n\"");
  }

  @Test
  void logShapeHasDefaultServiceName() {
    String out =
        captureStdout(() -> Telemetry.log(Map.of("event", "request", "status", 200), null));

    JsonNode record = parseJsonLine(out);
    assertThat(record.get("level").asText()).isEqualTo("info");
    assertThat(record.get("service").asText()).isEqualTo("reference-app");
    assertThat(record.get("event").asText()).isEqualTo("request");
    assertThatCode(() -> Instant.parse(record.get("ts").asText())).doesNotThrowAnyException();
  }

  @Test
  void logRejectsBlankServiceOverrideFallsBackToDefault() {
    String out = captureStdout(() -> Telemetry.log(Map.of("event", "boot"), ""));

    JsonNode record = parseJsonLine(out);
    assertThat(record.get("service").asText()).isEqualTo("reference-app");
  }

  @Test
  void logServiceNameOverride() {
    String out = captureStdout(() -> Telemetry.log(Map.of("event", "boot"), "custom-svc"));

    JsonNode record = parseJsonLine(out);
    assertThat(record.get("service").asText()).isEqualTo("custom-svc");
  }

  @Test
  void logPublicOverloadDoesNotThrow() {
    // Exercises the env-driven public entry point (the seam the server actually calls).
    assertThatCode(() -> captureStdout(() -> Telemetry.log(Map.of("event", "via-env"))))
        .doesNotThrowAnyException();
  }

  private static JsonNode parseJsonLine(String out) {
    try {
      return JSON.readTree(out.strip());
    } catch (Exception e) {
      throw new UncheckedIOException(
          new IOException("captured output is not valid JSON: " + out, e));
    }
  }
}
