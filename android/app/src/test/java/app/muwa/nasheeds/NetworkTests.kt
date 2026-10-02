package app.muwa.nasheeds

import kotlinx.coroutines.*
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.TimeUnit

class NetworkTests {
    @Test fun readsSuccessfulAndErrorResponsesBeforeClosingThem() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setBody("ready"))
            server.enqueue(MockResponse().setResponseCode(503).setBody("unavailable"))
            val client = OkHttpClient()
            fun call() = client.newCall(Request.Builder().url(server.url("/audio")).build())
            assertEquals("ready", call().awaitResult { it.body!!.string() })
            assertEquals(503 to "unavailable", call().awaitResult { it.code to it.body!!.string() })
        }
    }

    @Test fun cancellationDuringBodyReadCancelsTheActualHttpCall() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setBody("delayed audio").setBodyDelay(2, TimeUnit.SECONDS))
            val call = OkHttpClient().newCall(Request.Builder().url(server.url("/audio")).build())
            val headersReceived = CompletableDeferred<Unit>()
            val job = launch {
                call.awaitResult { response ->
                    headersReceived.complete(Unit)
                    response.body!!.string()
                }
                fail("A cancelled read must not publish a successful result")
            }
            withTimeout(5000) { headersReceived.await() }
            withTimeout(1000) { job.cancelAndJoin() }
            assertTrue("HTTP socket continued after coroutine cancellation", call.isCanceled())
        }
    }
}
