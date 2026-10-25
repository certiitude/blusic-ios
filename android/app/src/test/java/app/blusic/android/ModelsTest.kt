package app.blusic.android

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ModelsTest {
    @Test fun libraryRoundTripKeepsFavoritesPlaylistAndSources() {
        val track = Track(title = "Song", artist = "Artist", location = "abcdefghijk", lyrics = "[00:01.00]Words")
        val state = LibraryState(tracks = listOf(track), favorites = setOf(track.id), playlists = listOf(Playlist(name = "My playlist", tracks = listOf(track.id))), recent = listOf(track.id))
        assertEquals(state, LibraryState.parse(state.json().toString()))
        assertEquals(state.tracks.first().lyrics, LibraryState.parse(state.json().toString()).tracks.first().lyrics)
    }
    @Test fun lyricsKeepsRepeatedTimestampsAndOffset() {
        val lines = LyricsParser.parse("[offset:-500]\n[00:01.25][00:05.250]First\n[01:02.5]Second")
        assertEquals(listOf(750L, 4750L, 62000L), lines.map { it.time })
        assertEquals(listOf("First", "First", "Second"), lines.map { it.text })
        assertTrue(LyricsParser.parse("Plain words").isEmpty())
    }
    @Test fun instanceValidationRejectsCredentialsAndQuery() {
        assertEquals("https://example.org", MusicApi.validateInstance(" https://example.org/ "))
        for (invalid in listOf("http://example.org", "https://user:pass@example.org", "https://example.org?x=y", "https://example.org/#a")) {
            assertTrue(runCatching { MusicApi.validateInstance(invalid) }.isFailure)
        }
    }
    @Test fun directMediaHostMustBeActualGoogleVideo() {
        assertTrue(MusicApi.validGoogleMedia("https://rr1.googlevideo.com/audio?a=b"))
        assertFalse(MusicApi.validGoogleMedia("https://googlevideo.com.evil.invalid/audio"))
        assertFalse(MusicApi.validGoogleMedia("https://user:pass@rr1.googlevideo.com/audio"))
        assertFalse(MusicApi.validGoogleMedia("http://rr1.googlevideo.com/audio"))
    }
    @Test fun finiteRangesRejectTruncationAndWildcards() {
        assertEquals(ByteRange(0, 262143, 2311731), ByteRange.parse("bytes 0-262143/2311731"))
        for (value in listOf("bytes 4-3/10", "bytes 0-10/10", "bytes 0-3/*", "garbage", "bytes -1-3/10")) assertNull(ByteRange.parse(value))
    }
    @Test fun musicalSearchExcludesOfficialVideoAndDeduplicatesSongs() {
        fun row(id: String, type: String): JSONObject = JSONObject().put("musicResponsiveListItemRenderer", JSONObject()
            .put("playlistItemData", JSONObject().put("videoId", id)).put("musicVideoType", type)
            .put("flexColumns", JSONArray().put(column(JSONArray().put(JSONObject().put("text", "Song"))))
                .put(column(JSONArray().put(JSONObject().put("text", "Artist").put("navigationEndpoint", JSONObject().put("browseEndpoint", JSONObject().put("browseId", "UC_artist"))))
                    .put(JSONObject().put("text", "2:23"))))))
        val root = JSONObject().put("contents", JSONArray().put(row("abcdefghijk", "MUSIC_VIDEO_TYPE_ATV"))
            .put(row("abcdefghijk", "MUSIC_VIDEO_TYPE_ATV")).put(row("bbbbbbbbbbb", "MUSIC_VIDEO_TYPE_OMV")))
        val tracks = MusicApi.parseSearch(root).tracks
        assertEquals(1, tracks.size); assertEquals("Artist", tracks.first().artist); assertEquals(143000L, tracks.first().duration)
    }
    private fun column(runs: JSONArray) = JSONObject().put("musicResponsiveListItemFlexColumnRenderer", JSONObject().put("text", JSONObject().put("runs", runs)))
    @Test fun clockHandlesNegativePosition() { assertEquals("0:00", (-120L).clock()); assertEquals("2:23", 143000L.clock()) }
}
