package com.example.app

import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest
import org.springframework.http.MediaType
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.content
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.status
import kotlin.test.assertEquals

@WebMvcTest(HealthController::class)
class HealthControllerTest {
    @Autowired
    private lateinit var mockMvc: MockMvc

    @Test
    fun `GET healthz returns 200 with status ok`() {
        mockMvc.perform(get("/healthz"))
            .andExpect(status().isOk)
            .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
            .andExpect(jsonPath("$.status").value("ok"))
    }

    @Test
    fun `controller method returns status ok map`() {
        val body = HealthController().healthz()
        assertEquals("ok", body["status"])
    }
}
