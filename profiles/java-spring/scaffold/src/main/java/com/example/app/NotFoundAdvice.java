package com.example.app;

import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.servlet.NoHandlerFoundException;

/**
 * Turns an unmatched GET route into the hardened, framework-neutral 404 the parity contract fixes.
 *
 * <p>With {@code spring.mvc.throw-exception-if-no-handler-found=true} and {@code
 * spring.web.resources.add-mappings=false} an unknown path raises {@link NoHandlerFoundException}
 * rather than serving the default whitelabel error page; this advice maps it to a compact {@code
 * {"error":"not found"}} JSON body — no stack, no framework/version leak. (Non-GET methods never
 * reach the dispatcher: {@link AppInstrumentationFilter} short-circuits them to the same 404.)
 */
@RestControllerAdvice
public class NotFoundAdvice {

  /**
   * The compact 404 payload — matches the go/python spine byte-for-byte after Jackson renders it.
   */
  private static final Map<String, String> NOT_FOUND_BODY = Map.of("error", "not found");

  /**
   * Maps an unmatched route to the hardened JSON 404.
   *
   * @return a 404 carrying {@code {"error":"not found"}}
   */
  @ExceptionHandler(NoHandlerFoundException.class)
  public ResponseEntity<Map<String, String>> handleNotFound() {
    return ResponseEntity.status(HttpStatus.NOT_FOUND)
        .contentType(MediaType.APPLICATION_JSON)
        .body(NOT_FOUND_BODY);
  }
}
