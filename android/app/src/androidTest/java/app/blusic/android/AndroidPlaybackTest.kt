package app.blusic.android

import android.content.Context
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class AndroidPlaybackTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

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

    private fun screenshot(name: String) {
        compose.waitForIdle()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val bitmap = instrumentation.uiAutomation.takeScreenshot()
        val folder = File(instrumentation.targetContext.getExternalFilesDir(null), "screenshots").apply { mkdirs() }
        File(folder, "$name.png").outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
    }
}
