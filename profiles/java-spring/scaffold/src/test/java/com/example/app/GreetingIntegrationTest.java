package com.example.app;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;

/**
 * Integration: the flag seam + telemetry wiring THROUGH the running Spring server.
 *
 * <p>Unlike the unit tests (which exercise a class in isolation), this boots the FULL application
 * context on a random port ({@link SpringBootTest.WebEnvironment#RANDOM_PORT}) and drives it over
 * real HTTP with the JDK {@link HttpClient} (which — unlike {@code TestRestTemplate}'s default
 * factory — supports every method incl. PATCH/HEAD/OPTIONS). It measures {@link
 * AppInstrumentationFilter}, {@link GreetingController}, {@link MetricsController}, and {@link
 * NotFoundAdvice} together. The live-flip case is the ★ load-bearing proof that the provider seam
 * reaches the REAL endpoint with NO restart.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class GreetingIntegrationTest {

  /** The four security headers expected — exactly once each — on EVERY response. */
  private static final Map<String, String> EXPECTED_SECURITY_HEADERS =
      Map.of(
          "X-Content-Type-Options", "nosniff",
          "X-Frame-Options", "DENY",
          "Content-Security-Policy", "default-src 'none'",
          "Referrer-Policy", "no-referrer");

  private static final ObjectMapper MAPPER = new ObjectMapper();
  private final HttpClient client =
      HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();

  @LocalServerPort private int port;

  @AfterEach
  void restoreEnvFloor() {
    // A live-flip test installs a file provider into the shared static seam — restore the env floor
    // so it cannot leak into a later test.
    FeatureFlags.resetProvider();
  }

  private String base() {
    return "http://localhost:" + port;
  }

  private HttpResponse<String> send(String method, String path, Map<String, String> headers)
      throws IOException, InterruptedException {
    HttpRequest.Builder builder =
        HttpRequest.newBuilder(URI.create(base() + path))
            .timeout(Duration.ofSeconds(5))
            .method(method, HttpRequest.BodyPublishers.noBody());
    headers.forEach(builder::header);
    return client.send(builder.build(), HttpResponse.BodyHandlers.ofString());
  }

  private HttpResponse<String> get(String path) throws IOException, InterruptedException {
    return send("GET", path, Map.of());
  }

  @Test
  void greetingFlagOffServesDefaultBody() throws Exception {
    FeatureFlags.resetProvider();
    HttpResponse<String> response = get("/greeting");

    assertThat(response.statusCode()).isEqualTo(200);
    assertThat(response.headers().firstValue("Content-Type").orElse(""))
        .contains("application/json");
    assertThat(response.body()).isEqualTo("{\"greeting\":\"Hello, world!\"}");
  }

  @Test
  void greetingFlagOnServesNewBody() throws Exception {
    // Install a provider that enables new_greeting on the SAME running server (own-key-only).
    FeatureFlags.setProvider(name -> "new_greeting".equals(name));
    HttpResponse<String> response = get("/greeting");

    assertThat(response.statusCode()).isEqualTo(200);
    assertThat(response.body()).isEqualTo("{\"greeting\":\"Hello, world! (new)\"}");
  }

  @Test
  void healthzReturnsOkBody() throws Exception {
    HttpResponse<String> response = get("/healthz");

    assertThat(response.statusCode()).isEqualTo(200);
    assertThat(response.body()).isEqualTo("{\"status\":\"ok\"}");
  }

  @Test
  void metricsExposesPrometheusCounter() throws Exception {
    get("/greeting"); // record at least one request first
    HttpResponse<String> response = get("/metrics");

    assertThat(response.statusCode()).isEqualTo(200);
    assertThat(response.body()).contains("http_requests_total");
    assertThat(response.body()).contains("http_request_duration_seconds_total");
    // byte-for-byte parity with go/python: the space after ';' must survive (Spring's
    // MediaType.parseMediaType would normalize it away — the raw header string preserves it).
    assertThat(response.headers().firstValue("Content-Type").orElse(""))
        .isEqualTo("text/plain; version=0.0.4");
  }

  /**
   * ★ The load-bearing wiring proof: install the file-config live provider, then rewrite the SAME
   * flag file and observe {@code /greeting} flip on the SAME running server with NO restart — the
   * seam flips the REAL endpoint, not a side process.
   */
  @Test
  void greetingLiveFlipOnSameRunningServer(@org.junit.jupiter.api.io.TempDir Path tmp)
      throws Exception {
    Path flagFile = tmp.resolve("flags.json");
    Files.writeString(flagFile, "{\"new_greeting\":false}", StandardCharsets.UTF_8);
    FeatureFlags.setProvider(new FileConfigProvider(flagFile.toString()));

    HttpResponse<String> off = get("/greeting");
    assertThat(off.body())
        .as("pre-flip: the default greeting")
        .isEqualTo("{\"greeting\":\"Hello, world!\"}");

    // Rewrite the SAME file — NO server restart between these two GETs.
    Files.writeString(flagFile, "{\"new_greeting\":true}", StandardCharsets.UTF_8);

    HttpResponse<String> on = get("/greeting");
    assertThat(on.body())
        .as("post-flip: the new greeting, same running server")
        .isEqualTo("{\"greeting\":\"Hello, world! (new)\"}");
  }

  @Test
  void getCarriesSecurityHeadersExactlyOnceAndNeutralServer() throws Exception {
    HttpResponse<String> response = get("/healthz");

    assertThat(response.statusCode()).isEqualTo(200);
    EXPECTED_SECURITY_HEADERS.forEach(
        (name, value) -> {
          List<String> values = response.headers().allValues(name);
          assertThat(values).as("header %s exactly once", name).containsExactly(value);
        });
    assertThat(response.headers().firstValue("Server").orElse(""))
        .as("neutral Server header, no framework/version leak")
        .isEqualTo("reference-app");
  }

  @Test
  void everyNonGetMethodReturns404WithBodyAndSecurityHeaders() throws Exception {
    for (String method : List.of("POST", "PUT", "DELETE", "PATCH", "OPTIONS")) {
      HttpResponse<String> response = send(method, "/greeting", Map.of());

      assertThat(response.statusCode()).as("%s -> 404", method).isEqualTo(404);
      assertThat(response.body()).as("%s body", method).isEqualTo("{\"error\":\"not found\"}");
      EXPECTED_SECURITY_HEADERS.forEach(
          (name, value) ->
              assertThat(response.headers().allValues(name))
                  .as("%s header %s exactly once", method, name)
                  .containsExactly(value));
      assertThat(response.headers().firstValue("Server").orElse(""))
          .as("%s neutral Server header", method)
          .isEqualTo("reference-app");
    }
  }

  @Test
  void headReturns404StatusAndHeadersWithoutBody() throws Exception {
    HttpResponse<String> response = send("HEAD", "/healthz", Map.of());

    assertThat(response.statusCode()).isEqualTo(404);
    assertThat(response.body()).as("HEAD carries no body").isEmpty();
    EXPECTED_SECURITY_HEADERS
        .keySet()
        .forEach(
            name ->
                assertThat(response.headers().firstValue(name))
                    .as("HEAD carries security header %s", name)
                    .isPresent());
    assertThat(response.headers().firstValue("Server").orElse("")).isEqualTo("reference-app");
  }

  @Test
  void unknownGetPathReturnsHardened404() throws Exception {
    HttpResponse<String> response = get("/no-such-route");

    assertThat(response.statusCode()).isEqualTo(404);
    assertThat(response.body()).isEqualTo("{\"error\":\"not found\"}");
    assertThat(response.headers().firstValue("Server").orElse("")).isEqualTo("reference-app");
  }

  @Test
  void validInboundRequestIdIsEchoedIntoSpan() throws Exception {
    String validId = "req-" + UUID.randomUUID().toString();
    HttpResponse<String> response = send("GET", "/healthz", Map.of("X-Request-Id", validId));

    assertThat(response.statusCode()).isEqualTo(200);
    assertThat(spanRequestIdsAfter(response)).contains(validId);
  }

  @Test
  void oversizedInboundRequestIdIsReplacedNotEchoed() throws Exception {
    String oversized = "x".repeat(129); // 129 > the 128-char bound
    HttpResponse<String> response = send("GET", "/healthz", Map.of("X-Request-Id", oversized));

    assertThat(response.statusCode()).isEqualTo(200);
    assertThat(spanRequestIdsAfter(response))
        .as("an oversized inbound id must be replaced by a minted id, never echoed")
        .doesNotContain(oversized);
  }

  /**
   * Reads every emitted span's {@code request_id} attribute from the OTEL trace sink. The sink is
   * configured via the {@code OTEL_TRACE_FILE} env var (surefire, see pom); telemetry is emitted
   * AFTER the response is written, so the request must have completed before this reads.
   */
  private List<String> spanRequestIdsAfter(HttpResponse<String> ignoredCompletedResponse)
      throws IOException {
    String traceFile = System.getenv("OTEL_TRACE_FILE");
    assertThat(traceFile).as("OTEL_TRACE_FILE must be configured (surefire)").isNotNull();
    List<String> lines = Files.readAllLines(Path.of(traceFile), StandardCharsets.UTF_8);
    return lines.stream()
        .map(GreetingIntegrationTest::spanRequestId)
        .filter(id -> id != null)
        .toList();
  }

  private static String spanRequestId(String jsonLine) {
    try {
      JsonNode span = MAPPER.readTree(jsonLine);
      JsonNode requestId = span.path("attributes").path("request_id");
      return requestId.isTextual() ? requestId.asText() : null;
    } catch (IOException e) {
      return null;
    }
  }
}
