package app.blusic.android

import org.json.JSONObject
import java.net.URI
import java.text.Normalizer
import java.util.UUID

object PlaylistImports {
    fun normalize(value: String) = Normalizer.normalize(value.lowercase(), Normalizer.Form.NFD).replace(Regex("\\p{M}+"), "").filter(Char::isLetterOrDigit)
    fun videoId(value: String): String? = runCatching {
        val u = URI(value.trim()); val host = u.host?.lowercase().orEmpty()
        val id = when { host == "youtu.be" -> u.path.trim('/'); host in listOf("youtube.com", "www.youtube.com", "music.youtube.com", "m.youtube.com") -> u.rawQuery.orEmpty().split('&').firstOrNull { it.startsWith("v=") }?.substringAfter('='); else -> null }
        id?.takeIf { it.matches(Regex("[A-Za-z0-9_-]{11}")) }
    }.getOrNull()
    fun csv(text: String): List<List<String>> {
        val separator = if (text.lineSequence().firstOrNull().orEmpty().count { it == ';' } > text.lineSequence().firstOrNull().orEmpty().count { it == ',' }) ';' else ','
        val rows = mutableListOf<List<String>>(); var row = mutableListOf<String>(); val field = StringBuilder(); var quoted = false; var index = 0
        while (index < text.length) {
            val c = text[index++]
            when {
                c == '"' && quoted && index < text.length && text[index] == '"' -> { field.append('"'); index++ }
                c == '"' -> quoted = !quoted
                c == separator && !quoted -> { row.add(field.toString()); field.clear() }
                c == '\n' && !quoted -> { row.add(field.toString().trimEnd('\r')); field.clear(); if (row.any(String::isNotBlank)) rows.add(row); row = mutableListOf() }
                else -> field.append(c)
            }
        }
        require(!quoted) { "CSV : guillemet non fermé" }
        row.add(field.toString().trimEnd('\r')); if (row.any(String::isNotBlank)) rows.add(row)
        return rows
    }
    fun reference(title: String, artist: String, album: String = "", duration: Long = 0, url: String = ""): Track {
        val id = videoId(url)
        val identity = id ?: "${normalize(title)}|${normalize(artist)}"
        return Track(id = if (id != null) "yt:$id" else "ref:" + UUID.nameUUIDFromBytes(identity.toByteArray()), title = title, artist = artist,
            album = album, duration = duration, source = if (id != null) "online" else "reference", location = id ?: identity)
    }
    fun parse(text: String, name: String): List<Track> {
        if (name.endsWith(".m3u", true) || name.endsWith(".m3u8", true)) {
            var title = "Titre importé"; return text.lineSequence().mapNotNull { line ->
                if (line.startsWith("#EXTINF:")) { title = line.substringAfter(','); null }
                else if (line.isBlank() || line.startsWith('#')) null else reference(title.substringAfter(" - ", title), title.substringBefore(" - ", ""), url = line)
            }.distinctBy(Track::identity).take(2000).toList()
        }
        if (name.endsWith(".json", true)) return restore(text).tracks
        val rows = csv(text.removePrefix("\uFEFF")); require(rows.size > 1) { "CSV vide" }
        val header = rows.first().map(::normalize)
        fun column(vararg names: String) = header.indexOfFirst { it in names }
        val title = column("trackname", "title", "titre", "tracktitle", "name"); val artist = column("artistname", "artistnames", "artist", "artists", "artiste")
        val album = column("albumname", "album", "albumtitle"); val url = column("trackuri", "trackurl", "url", "link", "lien")
        val length = column("durationms", "duration", "durationseconds")
        require(title >= 0) { "Colonne titre introuvable dans ce CSV" }
        return rows.drop(1).mapNotNull { row ->
            val t = row.getOrNull(title)?.trim().orEmpty(); if (t.isEmpty()) null else {
                val duration = row.getOrNull(length)?.toDoubleOrNull()?.let { if (header.getOrNull(length) == "durationms") it.toLong() else (it * 1000).toLong() } ?: 0
                reference(t, row.getOrNull(artist).orEmpty(), row.getOrNull(album).orEmpty(), duration, row.getOrNull(url).orEmpty())
            }
        }.distinctBy(Track::identity).take(2000)
    }
    fun restore(text: String): LibraryState {
        val root = JSONObject(text); require(root.getInt("version") == 1) { "Sauvegarde non prise en charge" }
        if (!root.has("settings")) return LibraryState.parse(text)
        val settings = root.getJSONObject("settings")
        val tracks = root.getJSONArray("tracks").objects().map { j ->
            val source = when (j.getString("source")) { "invidious", "youtube" -> "online"; "bundled" -> "bundled"; else -> "reference" }
            Track(j.getString("id"), j.getString("title"), j.optString("artist"), j.optString("album"), (j.optDouble("duration") * 1000).toLong(), source,
                j.optString("location"), j.optString("artwork", "cover-night"), j.stringOrNull("artworkURL"), j.stringOrNull("lyrics"), j.stringOrNull("artistID"), j.optBoolean("isExplicit"))
        }
        return LibraryState(tracks = tracks, favorites = root.optJSONArray("favorites").strings().toSet(),
            playlists = root.optJSONArray("playlists").objects().map { Playlist(it.getString("id"), it.getString("name"), it.optJSONArray("trackIDs").strings()) },
            speed = settings.optDouble("playbackRate", 1.0).toFloat().coerceIn(.5f, 2f), linkedPitch = settings.optBoolean("linkSpeedAndPitch", true),
            highQuality = settings.optBoolean("highQualityAudio"), crossfade = settings.optBoolean("crossfadeEnabled"), crossfadeSeconds = settings.optDouble("crossfadeDuration", 3.0).toFloat().coerceIn(.5f, 8f),
            pitchSemitones = settings.optDouble("pitch", 0.0).toFloat().coerceIn(-12f, 12f), equalizerEnabled = settings.optBoolean("equalizerEnabled"),
            equalizer = (0 until 10).map { settings.optJSONArray("equalizer")?.optDouble(it, 0.0)?.toFloat()?.coerceIn(-12f, 12f) ?: 0f },
            savedQueue = root.optJSONArray("queue").strings(), savedCurrent = root.stringOrNull("currentTrackID"),
            followedArtists = root.optJSONArray("followedArtists").objects().map { MusicArtist(it.getString("id"), it.getString("name"), it.stringOrNull("artworkURL")) },
            history = root.optJSONArray("history").objects().takeLast(20000).map { ListeningEvent(it.getString("trackID"), ((it.optDouble("date", 0.0) + 978307200) * 1000).toLong(), it.optDouble("seconds", 0.0)) },
            volume = settings.optDouble("volume", .8).toFloat().coerceIn(0f, 1f), lyricsOffset = (settings.optDouble("lyricsOffset", 0.0) * 1000).toLong(),
            restoreQueue = settings.optBoolean("restoreQueue", true), appearance = settings.optString("appearance", "dark"), accent = settings.optString("accent", "blue"),
            haptics = settings.optBoolean("haptics", true), compactRows = settings.optBoolean("compactRows"), artworkRadius = settings.optDouble("artworkRadius", 18.0).toFloat().coerceIn(0f, 36f),
            animateArtwork = settings.optBoolean("animateArtwork", true), instance = settings.optString("invidiousInstance", "https://yt.chocolatemoo53.com"), automaticFallback = settings.optBoolean("invidiousAutomaticFallback", true))
    }
}

object CatalogMatching {
    fun title(value: String) = value.replace(Regex("(?i)\\s*[\\(\\[](?:feat\\.?|ft\\.?|featuring|avec)[^\\)\\]]*[\\)\\]]"), "").trim()
    private fun artistKeys(value: String) = (listOf(value) + value.split(';', ',')).map(PlaylistImports::normalize).filter(String::isNotEmpty).toSet()
    fun score(reference: Track, candidate: Track): Int {
        val a = PlaylistImports.normalize(title(reference.title)); val b = PlaylistImports.normalize(title(candidate.title))
        val versions = setOf("live", "remix", "acoustic", "acoustique", "instrumental", "karaoke", "slowed", "sped", "nightcore")
        fun labels(s: String) = s.lowercase().split(Regex("[^\\p{L}]+")).toSet().intersect(versions)
        if (a.isEmpty() || labels(reference.title) != labels(candidate.title)) return 0
        var score = if (a == b) 60 else if (a.length >= 4 && (a.contains(b) || b.contains(a))) 40 else 0
        if (artistKeys(reference.artist).intersect(artistKeys(candidate.artist)).isNotEmpty()) score += 35
        if (reference.duration > 0 && candidate.duration > 0) { val difference = kotlin.math.abs(reference.duration - candidate.duration); if (difference <= 4000) score += 10 else if (difference > maxOf(12000, reference.duration / 10)) score -= 30 }
        if (reference.explicit && !candidate.explicit) score -= 20
        return score
    }
}
