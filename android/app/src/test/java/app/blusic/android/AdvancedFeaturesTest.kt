package app.blusic.android

import org.junit.Assert.*
import org.junit.Test
import org.json.JSONObject
import kotlin.math.*

class AdvancedFeaturesTest {
    @Test fun oldLibraryKeepsDefaultsAndNewSettingsRoundTrip() {
        val old = LibraryState.parse(LibraryState().json().toString())
        assertFalse(old.highQuality); assertFalse(old.crossfade); assertEquals(10, old.equalizer.size)
        val state = old.copy(highQuality = true, crossfade = true, crossfadeSeconds = 2.5f, linkedPitch = false, pitchSemitones = 7f,
            equalizerEnabled = true, equalizer = List(10) { it / 2f }, followedArtists = listOf(MusicArtist("UC_test", "Artist")),
            history = listOf(ListeningEvent("demo-night", 1000, 35.0)), savedQueue = listOf("demo-night"), savedCurrent = "demo-night")
        assertEquals(state, LibraryState.parse(state.json().toString()))
        assertNotEquals(old.resolutionKey, state.resolutionKey)
        assertEquals(2.0.pow(7.0 / 12).toFloat(), state.pitchRatio, .00001f)
    }
    @Test fun preparationUses45RealSecondsAndVarispeed() {
        assertFalse(QueuePreparationPolicy.shouldStart(200000, 154999, 1f))
        assertTrue(QueuePreparationPolicy.shouldStart(200000, 155000, 1f))
        assertTrue(QueuePreparationPolicy.shouldStart(200000, 110000, 2f))
        assertFalse(QueuePreparationPolicy.shouldStart(200000, 109999, 2f))
        assertTrue(QueuePreparationPolicy.shouldStart(30000, 100, 1f))
        assertFalse(QueuePreparationPolicy.shouldStart(0, 0, Float.NaN))
    }
    @Test fun highQualitySelectsOnlyAnOfferedRate() {
        val formats = listOf(JSONObject().put("bitrate", 131000), JSONObject().put("bitrate", 256000))
        assertEquals(131000, MusicApi.preferred(formats, false).first().getInt("bitrate"))
        assertEquals(256000, MusicApi.preferred(formats, true).first().getInt("bitrate"))
        assertEquals(131000, MusicApi.preferred(formats.take(1), true).first().getInt("bitrate"))
    }
    @Test fun csvSupportsQuotedNamesAndReferencesRatherThanFakeVideoIds() {
        val tracks = PlaylistImports.parse("Track Name;Artist Name;Album;Track URI\n\"A; B\";Artist;Album;spotify:track:123\nSong;Artist;Album;https://music.youtube.com/watch?v=abcdefghijk", "playlist.csv")
        assertEquals(2, tracks.size); assertEquals("A; B", tracks[0].title); assertEquals("reference", tracks[0].source)
        assertEquals("online", tracks[1].source); assertEquals("abcdefghijk", tracks[1].location)
        assertTrue(runCatching { PlaylistImports.csv("Title,Artist\n\"broken") }.isFailure)
    }
    @Test fun matchingRejectsCoversAndDifferentVersions() {
        val track = PlaylistImports.reference("Song", "Artist, Guest", duration = 180000)
        assertTrue(CatalogMatching.score(track, track.copy(source = "online", artist = "Artist", location = "abcdefghijk")) >= 85)
        assertTrue(CatalogMatching.score(track, track.copy(artist = "Cover singer")) < 85)
        assertEquals(0, CatalogMatching.score(track, track.copy(title = "Song (live)")))
    }
    @Test fun iosBackupImportsSourcesSettingsAndPlaylists() {
        val text = """{"version":1,"tracks":[{"id":"id","title":"Song","artist":"Artist","duration":180,"source":"invidious","location":"abcdefghijk"}],"favorites":["id"],"playlists":[{"id":"p","name":"P","trackIDs":["id"]}],"settings":{"highQualityAudio":true,"crossfadeEnabled":true}}"""
        val state = PlaylistImports.restore(text)
        assertEquals("online", state.tracks[0].source); assertEquals(180000L, state.tracks[0].duration)
        assertTrue(state.highQuality); assertTrue(state.crossfade); assertEquals(listOf("id"), state.playlists[0].tracks)
    }
    @Test fun bridgeRejectsLocalFilesAndLookalikeHosts() {
        assertTrue(NativeYouTubeiResolver.allows("https://rr1.googlevideo.com/audio?x=y"))
        for (url in listOf("file:///private/data", "http://www.youtube.com", "https://www.youtube.com.evil.invalid/", "https://user:pass@www.youtube.com/", "https://www.youtube.com:444/")) assertFalse(NativeYouTubeiResolver.allows(url))
    }
    @Test fun tenBandEqIsTransparentWhenFlatAndChangesRelativeSpectrum() {
        val flat = TenBandEqualizer().apply { configure(48000, 2, List(10) { 0f }) }
        repeat(1000) { i -> val x = (.1 * sin(i.toDouble())).toFloat(); assertEquals(x, flat.process(x, i % 2), .00001f) }
        fun rms(hz: Int): Double {
            val eq = TenBandEqualizer().apply { configure(48000, 1, List(10) { if (it == 5) 6f else 0f }) }
            return sqrt((0 until 48000).sumOf { i -> val out = eq.process((.1 * sin(2 * PI * hz * i / 48000)).toFloat(), 0); out.toDouble() * out } / 48000)
        }
        assertTrue(rms(1000) > rms(100) * 1.5)
    }
}
