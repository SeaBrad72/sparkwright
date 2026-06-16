package com.example.app;

import java.util.Map;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/** Liveness surface used by the scaffold smoke check and post-deploy gate. */
@RestController
public class HealthController {

  /**
   * Returns a 200 with a small status body.
   *
   * @return a 200 response carrying {@code {"status":"ok"}}
   */
  @GetMapping("/healthz")
  public ResponseEntity<Map<String, String>> healthz() {
    return ResponseEntity.ok(Map.of("status", "ok"));
  }
}
