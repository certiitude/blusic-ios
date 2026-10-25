package app.blusic.android

import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

data class Track(
    val id: String = UUID.randomUUID().toString(), val title: String, val artist: String,
    val album: String = "", val duration: Long = 0, val source: String = "online", val location: String,
    val artwork: String = "cover-night", val artworkUrl: String? = null, val lyrics: String? = null
) {
    fun json() = JSONObject().put("id", id).put("title", title).put("artist", artist).put("album", album)
        .put("duration", duration).put("source", source).put("location", location).put("artwork", artwork)
        .put("artworkUrl", artworkUrl).put("lyrics", lyrics)
    val identity get() = "$source|$location"
    companion object {
        fun fromJson(j: JSONObject) = Track(j.getString("id"), j.getString("title"), j.optString("artist"),
            j.optString("album"), j.optLong("duration"), j.optString("source", "online"), j.getString("location"),
            j.optString("artwork", "cover-night"), j.stringOrNull("artworkUrl"), j.stringOrNull("lyrics"))
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
data class LibraryState(val tracks: List<Track> = Track.demos(), val favorites: Set<String> = emptySet(),
    val playlists: List<Playlist> = emptyList(), val recent: List<String> = emptyList(),
    val sourceMode: String = "auto", val instance: String = "https://yt.chocolatemoo53.com", val speed: Float = 1f,
    val linkedPitch: Boolean = true) {
    fun json() = JSONObject().put("version", 1).put("tracks", JSONArray(tracks.map { it.json() }))
        .put("favorites", JSONArray(favorites.toList())).put("playlists", JSONArray(playlists.map { it.json() }))
        .put("recent", JSONArray(recent)).put("sourceMode", sourceMode).put("instance", instance)
        .put("speed", speed.toDouble()).put("linkedPitch", linkedPitch)
    companion object {
        fun parse(text: String): LibraryState {
            val j = JSONObject(text)
            require(j.getInt("version") == 1) { "Version de bibliothèque inconnue" }
            return LibraryState(j.getJSONArray("tracks").objects().map(Track::fromJson),
                j.optJSONArray("favorites").strings().toSet(), j.optJSONArray("playlists").objects().map {
                    Playlist(it.getString("id"), it.getString("name"), it.optJSONArray("tracks").strings())
                }, j.optJSONArray("recent").strings(), j.optString("sourceMode", "auto"),
                j.optString("instance", "https://yt.chocolatemoo53.com"), j.optDouble("speed", 1.0).toFloat().coerceIn(.5f, 2f), j.optBoolean("linkedPitch", true))
        }
    }
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
