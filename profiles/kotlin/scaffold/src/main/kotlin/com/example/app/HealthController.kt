package com.example.app

import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RestController

/**
 * Liveness surface for the scaffold. Replace with real readiness/health
 * (e.g. Spring Boot Actuator) as the service grows.
 */
@RestController
class HealthController {
    @GetMapping("/healthz")
    fun healthz(): Map<String, String> = mapOf("status" to "ok")
}
