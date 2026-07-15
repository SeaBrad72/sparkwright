package com.example.app

import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Test
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.web.server.LocalServerPort
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * E2E: a full user journey against the assembled service.
 *
 * Liveness -> the greeting feature -> a not-found route, proving end-to-end
 * behaviour in-suite. DISTINCT from post-deploy `scripts/smoke.sh` (which proves a
 * deployed container is alive); this is the runnable in-process oracle. Mirrors the
 * go/python e2e references.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class JourneyE2eTest {
    @LocalServerPort
    private var port: Int = 0

    private val client: HttpClient = HttpClient.newBuilder().version(HttpClient.Version.HTTP_1_1).build()

    @AfterEach
    fun restoreFloor() {
        FeatureFlags.resetProvider()
    }

    private fun get(path: String): HttpResponse<String> =
        client.send(
            HttpRequest.newBuilder(URI.create("http://127.0.0.1:$port$path")).GET().build(),
            HttpResponse.BodyHandlers.ofString(),
        )

    @Test
    fun `liveness then greeting then not-found journey`() {
        FeatureFlags.resetProvider()

        val liveness = get("/healthz")
        assertEquals(200, liveness.statusCode(), "liveness status")
        assertEquals("""{"status":"ok"}""", liveness.body(), "liveness body")

        val greeting = get("/greeting")
        assertEquals(200, greeting.statusCode(), "greeting status")
        assertTrue(
            greeting.body().startsWith("""{"greeting":"Hello, world!"""),
            "greeting body = ${greeting.body()}",
        )

        val notFound = get("/nope")
        assertEquals(404, notFound.statusCode(), "not-found status")
        assertEquals("""{"error":"not found"}""", notFound.body(), "not-found body")
    }
}
