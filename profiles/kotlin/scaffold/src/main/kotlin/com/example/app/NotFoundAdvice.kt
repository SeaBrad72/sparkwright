package com.example.app

import org.springframework.http.HttpStatus
import org.springframework.http.MediaType
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.ExceptionHandler
import org.springframework.web.bind.annotation.RestControllerAdvice
import org.springframework.web.servlet.NoHandlerFoundException

/**
 * Maps an unrouted request to the contract's hardened JSON 404 (Kotlin/Spring
 * profile).
 *
 * With `spring.web.resources.add-mappings=false` +
 * `spring.mvc.throw-exception-if-no-handler-found=true` (see
 * `application.properties`), an unknown GET path raises [NoHandlerFoundException]
 * instead of returning the Whitelabel page; this advice turns it into
 * `{"error":"not found"}` with `application/json`, so the body matches the go/python
 * references EXACTLY. Non-GET methods never reach here — the
 * [SecurityAndTelemetryFilter] short-circuits them to the same 404 before dispatch.
 *
 * The security headers + per-request telemetry are still applied: this handler runs
 * INSIDE the filter's wrap, so the filter's stamped headers and after-response
 * telemetry cover this 404 too.
 */
@RestControllerAdvice
class NotFoundAdvice {
    @ExceptionHandler(NoHandlerFoundException::class)
    fun handleNoHandler(): ResponseEntity<Map<String, String>> =
        ResponseEntity.status(HttpStatus.NOT_FOUND)
            .contentType(MediaType.APPLICATION_JSON)
            .body(mapOf("error" to "not found"))
}
