package com.example.app;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

/**
 * Unit test for {@link HealthController}. Plain (no Spring context) for speed; it exercises every
 * line of the controller, which is the only class measured by the JaCoCo bundle (Application is
 * excluded), so line coverage clears the >=0.80 gate.
 */
class HealthControllerTest {

  private final HealthController controller = new HealthController();

  @Test
  void healthzReturnsOkStatus() {
    ResponseEntity<Map<String, String>> response = controller.healthz();

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    assertThat(response.getBody()).containsEntry("status", "ok");
  }
}
