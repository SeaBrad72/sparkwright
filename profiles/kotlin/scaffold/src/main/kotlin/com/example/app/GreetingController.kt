package com.example.app

import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RestController

/**
 * The flag-gated greeting surface — the ONE place the feature flag reaches a real
 * endpoint (Kotlin/Spring profile).
 *
 * `/greeting` resolves the `new_greeting` flag through the [FeatureFlags] seam on
 * EVERY request (never cached), so a live provider flip (see [fileConfigProvider])
 * changes the served body with no restart — the load-bearing proof this whole slice
 * guards. When the flag is OFF (the shipped default) it serves the classic greeting;
 * when a provider flips it ON it serves the new one. Mirrors the go/python
 * references' `/greeting` dispatch.
 *
 * The pure [greeting] method is also directly callable (unit-testable) without the
 * HTTP layer, mirroring [HealthController.healthz].
 */
@RestController
class GreetingController {
    @GetMapping("/greeting")
    fun greeting(): Map<String, String> {
        val body = if (FeatureFlags.isEnabled("new_greeting")) "Hello, world! (new)" else "Hello, world!"
        return mapOf("greeting" to body)
    }
}
