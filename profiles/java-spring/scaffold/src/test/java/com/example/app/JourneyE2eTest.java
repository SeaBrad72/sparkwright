package com.example.app;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;

/**
 * E2E: a full user journey against the assembled, running service.
 *
 * <p>Liveness -&gt; the greeting feature -&gt; a not-found route, proving end-to-end behaviour
 * in-suite against a real booted Spring context. DISTINCT from the post-deploy {@code
 * scripts/smoke.sh} (which proves a deployed container is alive); this is the runnable in-process
 * oracle. Mirrors the go/python reference journeys.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class JourneyE2eTest {

  private final HttpClient client =
      HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();

  @LocalServerPort private int port;

  @AfterEach
  void restoreEnvFloor() {
    FeatureFlags.resetProvider();
  }

  private HttpResponse<String> get(String path) throws IOException, InterruptedException {
    HttpRequest request =
        HttpRequest.newBuilder(URI.create("http://localhost:" + port + path))
            .timeout(Duration.ofSeconds(5))
            .GET()
            .build();
    return client.send(request, HttpResponse.BodyHandlers.ofString());
  }

  @Test
  void serviceJourneyLivenessThenGreetingThenNotFound() throws Exception {
    FeatureFlags.resetProvider();

    HttpResponse<String> liveness = get("/healthz");
    assertThat(liveness.statusCode()).isEqualTo(200);
    assertThat(liveness.body()).isEqualTo("{\"status\":\"ok\"}");

    HttpResponse<String> greeting = get("/greeting");
    assertThat(greeting.statusCode()).isEqualTo(200);
    assertThat(greeting.body()).startsWith("{\"greeting\":\"Hello, world!");

    HttpResponse<String> notFound = get("/nope");
    assertThat(notFound.statusCode()).isEqualTo(404);
    assertThat(notFound.body()).isEqualTo("{\"error\":\"not found\"}");
  }
}
