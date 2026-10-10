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
    @Test fun oversizedChunkedApiResponseIsRejectedWhileReading() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setChunkedBody("x".repeat(4096), 128))
            val call = OkHttpClient().newCall(Request.Builder().url(server.url("/api")).build())
            try { call.awaitResult { it.body!!.boundedText(1024) }; fail("Unbounded response accepted") }
            catch (expected: IllegalArgumentException) { }
        }
    }

    @Test fun oversizedChunkedAudioNeverWritesPastTheLimit() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setChunkedBody("x".repeat(4096), 128))
            val partial = java.io.File.createTempFile("muwa-bounded-audio", ".part")
            try {
                val call = OkHttpClient().newCall(Request.Builder().url(server.url("/audio")).build())
                try { call.awaitResult { transferAudio(it.body!!, partial, maximumBytes = 1024) }; fail("Oversized audio accepted") }
                catch (expected: IllegalStateException) { }
                assertTrue(partial.length() <= 1024)
            } finally { partial.delete() }
        }
    }

    @Test fun audioTransferAcceptsCompleteBodyAndRejectsCancellation() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setBody("real transfer fixture"))
            server.enqueue(MockResponse().setBody("cancelled fixture"))
            val partial = java.io.File.createTempFile("muwa-cancel-audio", ".part")
            try {
                val client = OkHttpClient()
                client.newCall(Request.Builder().url(server.url("/audio")).build()).awaitResult { transferAudio(it.body!!, partial) }
                assertEquals("real transfer fixture", partial.readText())
                try {
                    client.newCall(Request.Builder().url(server.url("/audio")).build()).awaitResult {
                        transferAudio(it.body!!, partial, checkActive = { throw CancellationException() })
                    }
                    fail("Cancelled transfer succeeded")
                } catch (expected: CancellationException) { }
            } finally { partial.delete() }
        }
    }
    @Test
    fun downloadedContainerUsesBytesInsteadOfTheCatalogUrl() {
        assertEquals("mp3", audioContainer("ID3fixture".toByteArray()))
        assertEquals("m4a", audioContainer(byteArrayOf(0, 0, 0, 24) + "ftypM4A ".toByteArray()))
        assertEquals("wav", audioContainer("RIFF0000WAVE".toByteArray()))
        try {
            audioContainer("{\"error\":\"no audio\"}".toByteArray())
            fail("JSON registered as audio")
        } catch (expected: IllegalStateException) {}
    }

}
