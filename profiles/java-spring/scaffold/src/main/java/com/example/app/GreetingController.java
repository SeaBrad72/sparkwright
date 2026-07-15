package com.example.app;

import java.util.Map;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * The flag-gated greeting route — the load-bearing proof the flag seam reaches a REAL endpoint.
 *
 * <p>{@code GET /greeting} resolves {@code new_greeting} through {@link FeatureFlags#isEnabled}
 * (the pluggable provider seam), so installing a live provider (e.g. {@link FileConfigProvider})
 * flips the body on the SAME running server with no restart. The body is an exact single-key map so
 * Jackson renders the compact JSON the cross-stack parity contract fixes verbatim ({@code
 * {"greeting":"Hello, world!"}} / {@code {"greeting":"Hello, world! (new)"}}).
 */
@RestController
public class GreetingController {

  /** The default greeting served when {@code new_greeting} is OFF (the kill-switch state). */
  static final String DEFAULT_GREETING = "Hello, world!";

  /** The greeting served when {@code new_greeting} is ON. */
  static final String NEW_GREETING = "Hello, world! (new)";

  /**
   * Serves the greeting, gated on the {@code new_greeting} flag.
   *
   * @return a 200 carrying {@code {"greeting":"Hello, world!"}} (flag OFF) or {@code
   *     {"greeting":"Hello, world! (new)"}} (flag ON)
   */
  @GetMapping(value = "/greeting", produces = MediaType.APPLICATION_JSON_VALUE)
  public Map<String, String> greeting() {
    String greeting = FeatureFlags.isEnabled("new_greeting") ? NEW_GREETING : DEFAULT_GREETING;
    return Map.of("greeting", greeting);
  }
}
