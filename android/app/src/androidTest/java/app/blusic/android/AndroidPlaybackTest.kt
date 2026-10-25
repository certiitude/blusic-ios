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
        compose.onNodeWithText("Sources audio").assertExists()
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
        compose.waitUntil(25_000) { vm.playback.value.playing || vm.playback.value.error != null }
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
