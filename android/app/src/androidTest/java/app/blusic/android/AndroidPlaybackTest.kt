package app.blusic.android

import android.content.Context
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.rule.GrantPermissionRule
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import androidx.media3.datasource.DataSpec
import android.net.Uri
import okhttp3.OkHttpClient
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import okhttp3.Protocol
import java.io.ByteArrayOutputStream
import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@RunWith(AndroidJUnit4::class)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class AndroidPlaybackTest {
    @get:Rule(order = 0) val permission: GrantPermissionRule = GrantPermissionRule.grant(android.Manifest.permission.POST_NOTIFICATIONS)
    @get:Rule(order = 1) val compose = createAndroidComposeRule<MainActivity>()

    @Test fun bundledAudioPlaysSeeksAndPausesInRealService() {
        lateinit var vm: BlusicViewModel
        compose.runOnUiThread { vm = ViewModelProvider(compose.activity)[BlusicViewModel::class.java]; vm.play(Track.demos()[0]) }
        compose.waitUntil(15_000) { vm.playback.value.playing }
        var initial = 0L
        compose.runOnUiThread { initial = vm.controller?.currentPosition ?: 0 }
        Thread.sleep(1200)
        compose.runOnUiThread {
            assertTrue((vm.controller?.currentPosition ?: 0) > initial + 500)
            vm.seek(30_000)
        }
        Thread.sleep(500)
        compose.runOnUiThread { assertTrue((vm.controller?.currentPosition ?: 0) >= 29_000) }
        compose.onNodeWithTag("mini-player").performClick()
        compose.onNodeWithTag("player-play").assertExists()
        screenshot("android-player")
        compose.onNodeWithContentDescription("Paroles").performClick()
        compose.onNodeWithTag("lyrics-panel").assertExists()
        screenshot("android-lyrics")
        compose.onNodeWithTag("player-play").performClick()
        compose.waitUntil(5000) { !vm.playback.value.playing }
        compose.onNodeWithContentDescription("Fermer le lecteur").performClick()
        screenshot("android-home")
    }

    @Test fun libraryFavoriteAndPlaylistSurviveRepositoryReload() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val repository = (context.applicationContext as BlusicApplication).library
        repository.ready.await()
        val song = Track(title = "Persistence fixture", artist = "Test", source = "local", location = "content://test/audio")
        repository.add(listOf(song))
        if (!repository.isFavorite(song)) repository.favorite(song)
        repository.createPlaylist("Test sauvegarde")
        val playlist = repository.state.value.playlists.last()
        repository.addToPlaylist(song, playlist.id)
        val restored = LibraryRepository(context); restored.ready.await()
        assertTrue(restored.isFavorite(song))
        assertTrue(restored.state.value.playlists.first { it.id == playlist.id }.tracks.contains(song.id))
    }

    @Test fun searchAndSettingsScreensRender() {
        compose.onNodeWithText("Recherche", useUnmergedTree = true).performClick()
        compose.onNodeWithTag("search-field").assertExists()
        screenshot("android-search")
        compose.onNodeWithContentDescription("Réglages").performClick()
        compose.onNodeWithText("Audio haute qualité").assertExists()
        compose.onNodeWithTag("high-quality").assertExists()
        screenshot("android-settings")
    }

    @Test fun finiteHttpSourceAssemblesEveryByteAndRejectsForbiddenPages() {
        val audio = ByteArray(700_000) { (it % 251).toByte() }
        val ranges = mutableListOf<String>()
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            val range = chain.request().header("Range")!!
            ranges += range
            val bounds = range.removePrefix("bytes=").split('-').map(String::toInt)
            val start = bounds[0]; val end = minOf(bounds[1], audio.lastIndex)
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).message("Partial Content").code(206)
                .header("Content-Type", "audio/mp4").header("Content-Range", "bytes $start-$end/${audio.size}")
                .body(audio.copyOfRange(start, end + 1).toResponseBody()).build()
        }.build()
        val source = FiniteHttpDataSource(client)
        assertEquals(audio.size.toLong(), source.open(DataSpec(Uri.parse("https://fixture.invalid/audio"))))
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) { val n = source.read(buffer, 0, buffer.size); if (n < 0) break; out.write(buffer, 0, n) }
        source.close()
        assertArrayEquals(audio, out.toByteArray())
        assertEquals(3, ranges.size)
        assertEquals("bytes=262144-524287", ranges[1])
        val forbidden = OkHttpClient.Builder().addInterceptor { chain -> Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).message("Forbidden").code(403).body("Denied".toResponseBody()).build() }.build()
        try { FiniteHttpDataSource(forbidden).open(DataSpec(Uri.parse("https://fixture.invalid/denied"))); fail("403 must not become an audio file") }
        catch (e: IOException) { assertTrue(e.message.orEmpty().contains("403")) }
    }

    @Test fun liveStephanieStartsFromPublicSourceAndSeeks() {
        lateinit var vm: BlusicViewModel
        compose.runOnUiThread {
            vm = ViewModelProvider(compose.activity)[BlusicViewModel::class.java]
            vm.play(Track("live-stephanie", "Stephanie", "Nafeesisboujee", duration = 127_000, location = "RFzfXv9wzfo"))
        }
        compose.waitUntil(55_000) { vm.playback.value.playing || vm.playback.value.error != null }
        compose.runOnUiThread {
            assertNull(vm.playback.value.error)
            assertTrue(vm.playback.value.playing)
            vm.seek(30_000)
        }
        Thread.sleep(1500)
        compose.runOnUiThread {
            assertNull(vm.playback.value.error)
            assertTrue((vm.controller?.currentPosition ?: 0) >= 29_000)
            vm.controller?.pause()
        }
    }

    @Test fun preparedNextTitleCrossfadesWithTwoNativeDecksAndPauseStopsBoth() {
        val app = compose.activity.application as BlusicApplication
        runBlocking { app.library.update { it.copy(crossfade = true, crossfadeSeconds = 2f, speed = 1f, volume = .1f) } }
        lateinit var vm: BlusicViewModel
        compose.runOnUiThread { vm = ViewModelProvider(compose.activity)[BlusicViewModel::class.java]; vm.play(Track.demos()[0], Track.demos().take(2)) }
        compose.waitUntil(15000) { vm.playback.value.playing }
        compose.runOnUiThread { vm.seek(5000) }
        compose.waitUntil(7000) { app.engineState.value.preparation == "Titre suivant préchargé" }
        compose.runOnUiThread { vm.next() }
        compose.waitUntil(7000) { app.engineState.value.overlapping == 2 && app.engineState.value.transitioning }
        compose.runOnUiThread { assertEquals(Track.demos()[1].id, vm.playback.value.track?.id); assertTrue(vm.playback.value.playing); vm.controller?.pause() }
        compose.waitUntil(4000) { app.engineState.value.overlapping == 0 }
        runBlocking { app.library.update { it.copy(crossfade = false, volume = .8f) } }
    }

    @Test fun highQualityEffectsArtistsAndQueueSettingsPersist() = runBlocking {
        val app = compose.activity.application as BlusicApplication
        app.library.update { it.copy(highQuality = true, equalizerEnabled = true, equalizer = List(10) { i -> if (i == 5) 3f else 0f }, linkedPitch = false, pitchSemitones = 5f, lyricsOffset = 500,
            followedArtists = listOf(MusicArtist("UC_test", "Test Artist"))) }
        val restored = LibraryRepository(compose.activity); restored.ready.await()
        assertTrue(restored.state.value.highQuality); assertEquals(3f, restored.state.value.equalizer[5]); assertEquals(500L, restored.state.value.lyricsOffset)
        assertEquals("Test Artist", restored.state.value.followedArtists.single().name)
        compose.onNodeWithContentDescription("Réglages").performClick()
        compose.onNodeWithTag("high-quality").assertExists(); screenshot("android-quality")
        compose.onNodeWithText("Égaliseur, vitesse et tonalité").performClick()
        compose.onNodeWithTag("sound-controls").assertExists(); screenshot("android-sound")
        app.library.update { it.copy(highQuality = false, equalizerEnabled = false, linkedPitch = true, pitchSemitones = 0f, lyricsOffset = 0) }
    }

    @Test fun packagedResolverUsesNativeBridgeAndProducesValidatedAudioWithoutMediaElement() = runBlocking {
        val context = compose.activity.applicationContext
        val audio = context.assets.open("bleu-nuit.wav").use { it.readNBytesCompat(44 + 44100 * 4 * 2) }
        java.nio.ByteBuffer.wrap(audio).order(java.nio.ByteOrder.LITTLE_ENDIAN).putInt(4, audio.size - 8).putInt(40, audio.size - 44)
        // A protocol fixture, not a claim that YouTube accepted this emulator.
        val encoded = android.util.Base64.encodeToString(audio, android.util.Base64.NO_WRAP)
        val resolver = NativeYouTubeiResolver(context) {
            """
            var waiting={},seq=0;
            window.__blusicReply=function(i,r){var p=waiting[i];delete waiting[i];r.error?p.reject(Error(r.error)):p.resolve(r);};
            function invoke(action,data){return new Promise(function(resolve,reject){var i=++seq;waiting[i]={resolve:resolve,reject:reject};webkit.messageHandlers.blusicResolver.postMessage(Object.assign({action:action,request:i},data));});}
            window.__blusicResolve=async function(id,job,quality){try {
              if(document.querySelector('audio,video'))throw Error('Unexpected media element');
              await invoke('beginAudio',{job:job,expected:${audio.size}});
              var bytes=atob('$encoded');
              for(var i=0;i<bytes.length;i+=32768)await invoke('appendAudio',{job:job,body:btoa(bytes.slice(i,i+32768))});
              webkit.messageHandlers.blusicResolver.postMessage({action:'finished',job:job,expected:${audio.size},bitrate:131000,duration:2});
            }catch(e){webkit.messageHandlers.blusicResolver.postMessage({action:'failed',job:job,error:e.message});}};
            window.__blusicCancel=function(){};
            webkit.messageHandlers.blusicResolver.postMessage({action:'ready'});
            """.trimIndent()
        }
        val result = withContext(Dispatchers.IO) { resolver.resolve("abcdefghijk", true) }
        val file = File(java.net.URI(result.url))
        try { assertEquals("high", result.quality); assertEquals(audio.size.toLong(), file.length()); assertTrue(NativeYouTubeiResolver.validateAudio(file, 2000) >= 1900) } finally { file.delete() }
        assertTrue(context.assets.open("YouTubeiResolver.js").bufferedReader().use { it.readText().contains("__blusicResolve") })
    }

    private fun screenshot(name: String) {
        compose.waitForIdle()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        require(name.matches(Regex("[a-z-]+")))
        // AGP uninstalls the test application after the suite, removing its
        // external files. Capture through the emulator's shell into a temporary
        // test-only folder that survives this cleanup.
        fun shell(command: String): String = android.os.ParcelFileDescriptor.AutoCloseInputStream(
            instrumentation.uiAutomation.executeShellCommand(command)).bufferedReader().use { it.readText() }
        // executeShellCommand is an exec interface, not a shell expression:
        // chaining with && would pass those words as mkdir arguments.
        shell("mkdir -p /data/local/tmp/blusic-screenshots")
        shell("screencap -p /data/local/tmp/blusic-screenshots/$name.png")
        val listing = shell("ls -l /data/local/tmp/blusic-screenshots/$name.png")
        assertTrue("Screenshot must be a regular PNG file: $listing", listing.trimStart().startsWith("-"))
    }
}
