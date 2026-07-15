package com.example.app;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.regex.Pattern;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * The app server spine — wires the flag seam + telemetry primitives onto EVERY request.
 *
 * <p>The Spring counterpart to the go {@code instrument()} middleware / python {@code
 * AppHandler._handle}. In ONE place it:
 *
 * <ul>
 *   <li>stamps the four security headers + a neutral {@code Server: reference-app} on every
 *       response (incl. 404 and HEAD) — exactly once each (setHeader replaces);
 *   <li>routes only GET to the controllers; every other method (POST/PUT/DELETE/PATCH/OPTIONS/HEAD)
 *       is short-circuited to the hardened JSON 404 here — method-agnostic, mirroring the
 *       reference, and bypassing Spring's automatic HEAD-for-GET / OPTIONS handling so HEAD too
 *       returns 404;
 *   <li>honours an inbound {@code X-Request-Id} ONLY if it is a safe, bounded token, else mints a
 *       fresh 32-hex id (an unbounded inbound header must never flow verbatim into a log/span);
 *   <li>emits per-request telemetry AFTER the response is written — a structured log, a
 *       bounded-cardinality metric, and an OTel-semantic span.
 * </ul>
 *
 * <p>Read-side bounds (slow-loris / unbounded-body defenses) live in {@code application.properties}
 * (Tomcat connection-timeout + header/swallow caps); this filter adds the request-id bound.
 */
@Component
public class AppInstrumentationFilter extends OncePerRequestFilter {

  /** Stamped on every response — hardened baseline for a JSON/text API that serves no markup. */
  static final Map<String, String> SECURITY_HEADERS =
      Map.of(
          "X-Content-Type-Options", "nosniff",
          "X-Frame-Options", "DENY",
          "Content-Security-Policy", "default-src 'none'",
          "Referrer-Policy", "no-referrer");

  /** Bounds an inbound {@code X-Request-Id} to a safe token (charset + length). */
  private static final Pattern REQUEST_ID_RE = Pattern.compile("^[A-Za-z0-9._-]{1,128}$");

  /** The compact 404 body, precomputed. */
  private static final byte[] NOT_FOUND_JSON =
      "{\"error\":\"not found\"}".getBytes(StandardCharsets.UTF_8);

  private static final String JSON_CONTENT_TYPE = "application/json";
  private static final SecureRandom RANDOM = new SecureRandom();
  private static final HexFormat HEX = HexFormat.of();
  private static final long NANOS_PER_SECOND = 1_000_000_000L;
  private static final double NANOS_PER_MILLI = 1_000_000.0;

  @Override
  protected void doFilterInternal(
      HttpServletRequest request, HttpServletResponse response, FilterChain chain)
      throws ServletException, IOException {
    long startMono = System.nanoTime();
    long startUnixNano = unixNanoNow();
    String method = request.getMethod();
    String requestId = requestId(request);

    // Stamp the security baseline + neutral Server header on EVERY response, exactly once.
    SECURITY_HEADERS.forEach(response::setHeader);
    response.setHeader("Server", "reference-app");

    if ("GET".equals(method)) {
      // Only GET is routed — controllers handle /healthz, /greeting, /metrics; an unknown path
      // raises NoHandlerFoundException -> NotFoundAdvice's hardened 404.
      chain.doFilter(request, response);
    } else {
      // Every non-GET method (incl. HEAD) -> hardened JSON 404 here, never the dispatcher.
      writeNotFound(response, method);
    }

    // Telemetry AFTER the response is written (mirrors the go/python spine).
    long elapsedNanos = System.nanoTime() - startMono;
    emitTelemetry(request, response, method, requestId, startUnixNano, elapsedNanos);
  }

  /** Validated inbound {@code X-Request-Id}, or a freshly minted 32-hex id. */
  private static String requestId(HttpServletRequest request) {
    String raw = request.getHeader("X-Request-Id");
    if (raw != null && REQUEST_ID_RE.matcher(raw).matches()) {
      return raw;
    }
    byte[] bytes = new byte[16];
    RANDOM.nextBytes(bytes);
    return HEX.formatHex(bytes);
  }

  /**
   * Writes the hardened JSON 404 directly (bypassing the dispatcher) for a non-GET method. HEAD
   * gets the 404 status + headers with no body; every other method also gets the body.
   */
  private static void writeNotFound(HttpServletResponse response, String method)
      throws IOException {
    response.setStatus(HttpServletResponse.SC_NOT_FOUND);
    response.setContentType(JSON_CONTENT_TYPE);
    if ("HEAD".equals(method)) {
      response.setContentLength(0);
      return;
    }
    response.setContentLength(NOT_FOUND_JSON.length);
    response.getOutputStream().write(NOT_FOUND_JSON);
  }

  /** Emits the log + bounded metric + OTel span for the just-served request. */
  private static void emitTelemetry(
      HttpServletRequest request,
      HttpServletResponse response,
      String method,
      String requestId,
      long startUnixNano,
      long elapsedNanos) {
    double latencyMs = elapsedNanos / NANOS_PER_MILLI;
    int status = response.getStatus();
    String path = request.getRequestURI();
    String fullPath =
        request.getQueryString() == null ? path : path + "?" + request.getQueryString();
    String spanName = method + " " + path; // query stripped (cardinality + secret hygiene)

    Map<String, Object> logFields = new LinkedHashMap<>();
    logFields.put("request_id", requestId);
    logFields.put("method", method);
    logFields.put("path", fullPath);
    logFields.put("status", status);
    logFields.put("latency_ms", latencyMs);
    Telemetry.log(logFields);

    Telemetry.recordMetric(method, status, latencyMs);

    Map<String, String> attributes = new LinkedHashMap<>();
    attributes.put("http.request.method", method);
    attributes.put("http.response.status_code", Integer.toString(status));
    attributes.put("request_id", requestId);
    Telemetry.emitSpan(
        Telemetry.buildSpan(
            spanName, startUnixNano, startUnixNano + elapsedNanos, attributes, status));
  }

  /** Wall-clock unix nanos for the span anchor. */
  private static long unixNanoNow() {
    Instant now = Instant.now();
    return now.getEpochSecond() * NANOS_PER_SECOND + now.getNano();
  }
}
