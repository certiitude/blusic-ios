package app.blusic.android

import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

data class Track(
    val id: String = UUID.randomUUID().toString(), val title: String, val artist: String,
    val album: String = "", val duration: Long = 0, val source: String = "online", val location: String,
    val artwork: String = "cover-night", val artworkUrl: String? = null, val lyrics: String? = null,
    val artistId: String? = null, val explicit: Boolean = false
) {
    fun json() = JSONObject().put("id", id).put("title", title).put("artist", artist).put("album", album)
        .put("duration", duration).put("source", source).put("location", location).put("artwork", artwork)
        .put("artworkUrl", artworkUrl).put("lyrics", lyrics).put("artistId", artistId).put("explicit", explicit)
    val identity get() = "$source|$location"
    companion object {
        fun fromJson(j: JSONObject) = Track(j.getString("id"), j.getString("title"), j.optString("artist"),
            j.optString("album"), j.optLong("duration"), j.optString("source", "online"), j.getString("location"),
            j.optString("artwork", "cover-night"), j.stringOrNull("artworkUrl"), j.stringOrNull("lyrics"), j.stringOrNull("artistId"), j.optBoolean("explicit"))
        fun demos() = listOf(
            Track("demo-night", "Bleu nuit", "Blusic Studio", "Premières ondes", 48_000, "bundled", "bleu-nuit.wav", "cover-night"),
            Track("demo-rain", "Après la pluie", "Blusic Studio", "Premières ondes", 48_000, "bundled", "apres-la-pluie.wav", "cover-rain"),
            Track("demo-orbit", "Orbite", "Blusic Studio", "Premières ondes", 48_000, "bundled", "orbite.wav", "cover-orbit"),
            Track("demo-metro", "Dernier métro", "Blusic Studio", "Premières ondes", 48_000, "bundled", "dernier-metro.wav", "cover-metro")
        )
    }
}
data class Playlist(val id: String = UUID.randomUUID().toString(), val name: String, val tracks: List<String> = emptyList()) {
    fun json() = JSONObject().put("id", id).put("name", name).put("tracks", JSONArray(tracks))
}
data class MusicArtist(val id: String, val name: String, val artworkUrl: String? = null) {
    fun json() = JSONObject().put("id", id).put("name", name).put("artworkUrl", artworkUrl)
}
data class ArtistProfile(val artist: MusicArtist, val biography: String, val tracks: List<Track>)
data class ListeningEvent(val trackId: String, val date: Long, val seconds: Double) {
    fun json() = JSONObject().put("trackId", trackId).put("date", date).put("seconds", seconds)
}
data class LibraryState(val tracks: List<Track> = Track.demos(), val favorites: Set<String> = emptySet(),
    val playlists: List<Playlist> = emptyList(), val recent: List<String> = emptyList(),
    val sourceMode: String = "auto", val instance: String = "https://yt.chocolatemoo53.com", val speed: Float = 1f,
    val linkedPitch: Boolean = true, val relayAddress: String = "", val highQuality: Boolean = false,
    val crossfade: Boolean = false, val crossfadeSeconds: Float = 3f, val pitchSemitones: Float = 0f,
    val equalizerEnabled: Boolean = false, val equalizer: List<Float> = List(10) { 0f }, val volume: Float = .8f,
    val lyricsOffset: Long = 0, val followedArtists: List<MusicArtist> = emptyList(), val history: List<ListeningEvent> = emptyList(),
    val savedQueue: List<String> = emptyList(), val savedCurrent: String? = null, val restoreQueue: Boolean = true,
    val relayDisabled: Boolean = false, val relayRevision: String = "", val automaticFallback: Boolean = true,
    val appearance: String = "dark", val accent: String = "violet", val haptics: Boolean = true,
    val compactRows: Boolean = false, val artworkRadius: Float = 14f, val animateArtwork: Boolean = true) {
    val byId by lazy { tracks.associateBy { it.id } }
    val byIdentity by lazy { tracks.associateBy { it.identity } }
    val likedTracks by lazy { tracks.filter { it.id in favorites } }
    val recentTracks by lazy { recent.mapNotNull { byId[it] } }
    val quality get() = if (highQuality) "high" else "standard"
    val resolutionKey get() = "$relayAddress|$relayDisabled|$sourceMode|$instance|$automaticFallback|$quality"
    val pitchRatio get() = if (linkedPitch) speed else Math.pow(2.0, pitchSemitones / 12.0).toFloat()
    fun json() = JSONObject().put("version", 1).put("tracks", JSONArray(tracks.map { it.json() }))
        .put("favorites", JSONArray(favorites.toList())).put("playlists", JSONArray(playlists.map { it.json() }))
        .put("recent", JSONArray(recent)).put("sourceMode", sourceMode).put("instance", instance)
        .put("speed", speed.toDouble()).put("linkedPitch", linkedPitch).put("relayAddress", relayAddress)
        .put("highQuality", highQuality).put("crossfade", crossfade).put("crossfadeSeconds", crossfadeSeconds.toDouble())
        .put("pitchSemitones", pitchSemitones.toDouble()).put("equalizerEnabled", equalizerEnabled).put("equalizer", JSONArray(equalizer))
        .put("volume", volume.toDouble()).put("lyricsOffset", lyricsOffset).put("followedArtists", JSONArray(followedArtists.map { it.json() }))
        .put("history", JSONArray(history.map { it.json() })).put("savedQueue", JSONArray(savedQueue)).put("savedCurrent", savedCurrent)
        .put("restoreQueue", restoreQueue).put("relayDisabled", relayDisabled).put("relayRevision", relayRevision)
        .put("automaticFallback", automaticFallback).put("appearance", appearance).put("accent", accent).put("haptics", haptics)
        .put("compactRows", compactRows).put("artworkRadius", artworkRadius.toDouble()).put("animateArtwork", animateArtwork)
    companion object {
        fun parse(text: String): LibraryState {
            val j = JSONObject(text)
            require(j.getInt("version") == 1) { "Version de bibliothèque inconnue" }
            return LibraryState(j.getJSONArray("tracks").objects().map(Track::fromJson),
                j.optJSONArray("favorites").strings().toSet(), j.optJSONArray("playlists").objects().map {
                    Playlist(it.getString("id"), it.getString("name"), it.optJSONArray("tracks").strings())
                }, j.optJSONArray("recent").strings(), j.optString("sourceMode", "auto"),
                j.optString("instance", "https://yt.chocolatemoo53.com"), j.optDouble("speed", 1.0).toFloat().coerceIn(.5f, 2f), j.optBoolean("linkedPitch", true), j.optString("relayAddress"),
                j.optBoolean("highQuality"), j.optBoolean("crossfade"), j.optDouble("crossfadeSeconds", 3.0).toFloat().coerceIn(.5f, 8f),
                j.optDouble("pitchSemitones", 0.0).toFloat().coerceIn(-12f, 12f), j.optBoolean("equalizerEnabled"),
                (0 until 10).map { j.optJSONArray("equalizer")?.optDouble(it, 0.0)?.toFloat()?.coerceIn(-12f, 12f) ?: 0f },
                j.optDouble("volume", .8).toFloat().coerceIn(0f, 1f), j.optLong("lyricsOffset"),
                j.optJSONArray("followedArtists").objects().map { MusicArtist(it.getString("id"), it.getString("name"), it.stringOrNull("artworkUrl")) },
                j.optJSONArray("history").objects().takeLast(20000).map { ListeningEvent(it.getString("trackId"), it.getLong("date"), it.getDouble("seconds")) },
                j.optJSONArray("savedQueue").strings(), j.stringOrNull("savedCurrent"), j.optBoolean("restoreQueue", true),
                j.optBoolean("relayDisabled"), j.optString("relayRevision"), j.optBoolean("automaticFallback", true),
                j.optString("appearance", "dark"), j.optString("accent", "violet"), j.optBoolean("haptics", true),
                j.optBoolean("compactRows"), j.optDouble("artworkRadius", 14.0).toFloat().coerceIn(0f, 36f), j.optBoolean("animateArtwork", true))
        }
    }
}
object QueuePreparationPolicy {
    fun shouldStart(duration: Long, position: Long, speed: Float): Boolean =
        duration > 0 && position in 1 until duration && speed.isFinite() && speed > 0 && (duration - position) / speed <= 45_000
}
data class LyricLine(val time: Long, val text: String)
object LyricsParser {
    private val tag = Regex("\\[(\\d{1,3}):(\\d{2})(?:[.:](\\d{1,3}))?]")
    fun parse(raw: String): List<LyricLine> {
        val offset = Regex("\\[offset:([+-]?\\d+)]").find(raw)?.groupValues?.get(1)?.toLongOrNull() ?: 0
        return raw.lineSequence().flatMap { line ->
            val tags = tag.findAll(line).toList()
            val text = tags.lastOrNull()?.let { line.substring(it.range.last + 1).trim() } ?: ""
            tags.asSequence().map {
                val fraction = it.groupValues[3].padEnd(3, '0').take(3).toLongOrNull() ?: 0
                LyricLine((it.groupValues[1].toLong() * 60_000 + it.groupValues[2].toLong() * 1000 + fraction + offset).coerceAtLeast(0), text)
            }
        }.sortedBy { it.time }.toList()
    }
}
fun JSONArray?.strings() = this?.let { a -> (0 until a.length()).map { a.getString(it) } } ?: emptyList()
fun JSONArray?.objects() = this?.let { a -> (0 until a.length()).mapNotNull { a.optJSONObject(it) } } ?: emptyList()
fun JSONObject.stringOrNull(key: String) = optString(key).takeIf { !isNull(key) && it.isNotBlank() }
fun Long.clock(): String { val s = coerceAtLeast(0) / 1000; return "%d:%02d".format(s / 60, s % 60) }
