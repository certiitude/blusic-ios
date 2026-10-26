package app.blusic.android

import org.junit.Assert.*
import org.junit.Test
import kotlinx.coroutines.*
import okhttp3.OkHttpClient
import okhttp3.Response
import okhttp3.Protocol
import okhttp3.ResponseBody.Companion.toResponseBody

class UiPerformanceTest {
    @Test fun automaticPlaybackDoesNotWaitForSlowNativeResolverBeforeTryingWorkingAudio() = runBlocking {
        var nativeCancelled = false
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            val metadata = chain.request().url.encodedPath == "/youtubei/v1/player"
            val body = if (metadata) """{"playabilityStatus":{"status":"OK"},"streamingData":{"adaptiveFormats":[{"url":"https://media.googlevideo.com/audio","mimeType":"audio/mp4; codecs=mp4a.40.2","bitrate":131000}]}}""" else "0000ftypM4A fixture"
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(if (metadata) 200 else 206).message("Fixture").body(body.toResponseBody()).build()
        }.build()
        val api = MusicApi(client, nativeResolver = { _, _ -> try { delay(30000); error("Should be cancelled") } finally { nativeCancelled = true } })
        val start = System.nanoTime()
        val stream = withTimeout(5000) { api.resolve("abcdefghijk", LibraryState(automaticFallback = false)) }
        assertEquals("YouTube direct", stream.provider); assertTrue(nativeCancelled)
        assertTrue((System.nanoTime() - start) / 1000000 < 5000)
    }
    @Test fun preparationHasNoRetryCountLimitAndRemainsCancellable() = runBlocking {
        var calls = 0; val waits = mutableListOf<Long>()
        val result = PreparationRetry.run(operation = { calls++; if (calls <= 25) throw java.io.IOException("Temporary fixture failure"); "ready" }, pause = { waits += it })
        assertEquals("ready", result); assertEquals(26, calls); assertEquals(listOf(1000L, 2000L, 4000L, 8000L, 10000L), waits.take(5)); assertEquals(10000L, waits.last())
        val retrying = CompletableDeferred<Unit>(); var attempts = 0
        val job = launch { PreparationRetry.run(operation = { attempts++; throw java.io.IOException("Offline fixture") }, onRetry = { _, _ -> retrying.complete(Unit) }) }
        retrying.await(); job.cancelAndJoin(); delay(50)
        assertEquals(1, attempts)
    }
    @Test fun thumbnailsUseDisplayDensityAndUpgradeOnlyKnownUnsignedSizing() {
        assertEquals(960, ArtworkPolicy.pixels(320f, 3f))
        val small = "https://lh3.googleusercontent.com/cover=w60-h60-l90-rj"
        assertEquals("https://lh3.googleusercontent.com/cover=w960-h960-l90-rj", ArtworkPolicy.candidates(small, 960).first())
        assertEquals(small, ArtworkPolicy.candidates(small, 960).last())
        val signed = "https://lh3.googleusercontent.com/cover=w60-h60?token=123"
        assertEquals(listOf(signed), ArtworkPolicy.candidates(signed, 960))
        assertEquals(listOf("https://example.org/image.jpg"), ArtworkPolicy.candidates("https://example.org/image.jpg", 960))
        assertTrue(ArtworkPolicy.candidates("https://i.ytimg.com/vi/abcdefghijk/default.jpg", 960).first().endsWith("maxresdefault.jpg"))
    }
    @Test fun unchangedTracksKeepTheirIndexesWhenOnlyListeningHistoryChanges() {
        val original = LibraryState(tracks = (0 until 2500).map { Track(id = "$it", title = "Track $it", artist = "Artist", location = "test$it") })
        val indexed = original.byId; val sourceIndex = original.byIdentity
        var state = original
        val start = System.nanoTime()
        repeat(2000) { n ->
            state = state.copy(history = listOf(ListeningEvent("1", n.toLong(), 5.0))).reuseIndexes(state)
            assertSame(indexed, state.byId); assertSame(sourceIndex, state.byIdentity)
            assertSame(original.tracks[1234], state.byId["1234"])
        }
        assertEquals(original.presentation(), state.presentation())
        println("LIBRARY INDEX: 2500 tracks, 2000 history updates, ${((System.nanoTime() - start) / 1000000.0)} ms; maps reused")
    }
    @Test fun bundledAccessRepairsMissingCredentialsAndRespectsExplicitChoices() {
        val access = "app.android." + "a".repeat(64)
        val bundled = BundledRelay.parse("""{"url":"https://blusic-audio-relay.onrender.com","access":"$access","revision":"v2","expiresAt":0}""")
        assertTrue(bundled.shouldInstall(LibraryState(), null))
        val configured = LibraryState(relayAddress = bundled.address, relayRevision = bundled.revision)
        assertFalse(bundled.shouldInstall(configured, access))
        assertTrue(bundled.shouldInstall(configured, null))
        assertFalse(bundled.shouldInstall(configured.copy(relayDisabled = true), null))
        assertFalse(bundled.shouldInstall(configured.copy(relayAddress = "https://custom.example.org"), null))
        assertTrue(bundled.shouldInstall(configured.copy(relayDisabled = true), null, force = true))
    }
}
