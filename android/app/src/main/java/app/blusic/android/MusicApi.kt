package app.blusic.android

import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.URI
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

data class SearchPage(val tracks: List<Track>, val continuation: String?)
data class AudioStream(val url: String, val bitrate: Int, val provider: String)

class MusicApi(val client: OkHttpClient = OkHttpClient.Builder().connectTimeout(5, TimeUnit.SECONDS)
    .readTimeout(7, TimeUnit.SECONDS).callTimeout(12, TimeUnit.SECONDS).build()) {
    private val resolved = ConcurrentHashMap<String, Pair<Long, AudioStream>>()
    private val jsonType = "application/json; charset=utf-8".toMediaType()
    fun search(query: String, continuation: String? = null): SearchPage {
        val body = JSONObject().put("context", JSONObject().put("client", JSONObject()
            .put("clientName", "WEB_REMIX").put("clientVersion", "1.20261021.01.00").put("hl", "fr").put("gl", "FR")))
            .put("query", query).put("params", "EgWKAQIIAWoMEA4QChADEAQQCRAF")
        val suffix = continuation?.let { "&continuation=" + java.net.URLEncoder.encode(it, "UTF-8") } ?: ""
        val request = Request.Builder().url("https://music.youtube.com/youtubei/v1/search?prettyPrint=false$suffix")
            .header("Origin", "https://music.youtube.com").header("X-YouTube-Client-Name", "67")
            .post(body.toString().toRequestBody(jsonType)).build()
        return parseSearch(json(request))
    }
    suspend fun resolve(video: String, settings: LibraryState, relayKey: String? = null): AudioStream = withContext(Dispatchers.IO) {
        require(video.matches(Regex("[A-Za-z0-9_-]{11}"))) { "Identifiant musical invalide" }
        val key = "${settings.relayAddress}|${settings.sourceMode}|${settings.instance}|$video"
        resolved[key]?.takeIf { it.first > System.currentTimeMillis() }?.let { return@withContext it.second }
        withTimeout(18_000) {
            supervisorScope {
                val outcomes = Channel<Result<AudioStream>>(3)
                val jobs = mutableListOf<Job>()
                if (settings.sourceMode == "auto" && settings.relayAddress.isNotBlank() && !relayKey.isNullOrBlank()) jobs += launch {
                    outcomes.send(runCatching { relayService(video, settings.relayAddress, relayKey) })
                }
                if (settings.sourceMode != "invidious") jobs += launch {
                    outcomes.send(runCatching { direct(video).also { validate(it) } })
                }
                if (settings.sourceMode != "direct") jobs += launch {
                    if (settings.sourceMode == "auto") delay(350)
                    outcomes.send(runCatching { relay(video, settings.instance) })
                }
                try {
                    val errors = mutableListOf<String>()
                    repeat(jobs.size) {
                        ensureActive()
                        val outcome = outcomes.receive()
                        outcome.getOrNull()?.let { stream ->
                            resolved[key] = (System.currentTimeMillis() + 90_000) to stream
                            return@supervisorScope stream
                        }
                        errors += outcome.exceptionOrNull()?.localizedMessage ?: "Source inaccessible"
                    }
                    throw IOException("Aucune source audio accessible.\n" + errors.joinToString("\n"))
                } finally { jobs.forEach { it.cancel() }; outcomes.close() }
            }
        }
    }
    fun invalidate(video: String) { resolved.keys.removeAll { it.endsWith("|$video") } }
    private fun relayService(video: String, address: String, key: String): AudioStream {
        val base = validateInstance(address)
        val payload = json(Request.Builder().url("$base/v1/streams/$video").header("Authorization", "Bearer $key").build())
        val server = URI(base)
        val url = server.resolve(payload.getString("url"))
        if (url.scheme != "https" || url.host != server.host || url.port != server.port || url.userInfo != null || !url.path.startsWith("/v1/audio/")) throw IOException("Lien audio du relais invalide")
        return AudioStream(url.toString(), payload.optInt("bitrate"), "youtubei.js").also(::validate)
    }
    private fun direct(video: String): AudioStream {
        // Compatibility context of the anonymous player endpoint validated by
        // Blusic iOS. This does not connect a Google account or solve challenges.
        val body = JSONObject().put("videoId", video).put("contentCheckOk", true).put("racyCheckOk", true)
            .put("context", JSONObject().put("client", JSONObject().put("clientName", "iOS").put("clientVersion", "20.11.6")
                .put("deviceMake", "Apple").put("deviceModel", "iPhone10,4").put("osName", "iOS")
                .put("osVersion", "16.7.7.20H330").put("platform", "MOBILE").put("hl", "fr").put("gl", "FR")))
        val root = json(Request.Builder().url("https://www.youtube.com/youtubei/v1/player?prettyPrint=false")
            .header("Origin", "https://www.youtube.com").post(body.toString().toRequestBody(jsonType)).build())
        val status = root.optJSONObject("playabilityStatus")
        if (status?.optString("status") != "OK") throw IOException("YouTube : " + (status?.optString("reason") ?: "Titre indisponible"))
        val formats = root.optJSONObject("streamingData")?.optJSONArray("adaptiveFormats").objects()
            .filter { it.optString("mimeType").startsWith("audio/mp4") && it.optString("mimeType").contains("mp4a") && !it.has("drmFamilies") }
            .sortedByDescending { it.optInt("bitrate") }
        return formats.firstNotNullOfOrNull { f -> f.stringOrNull("url")?.takeIf { validGoogleMedia(it) }?.let { AudioStream(it, f.optInt("bitrate"), "YouTube direct") } }
            ?: throw IOException("Aucun AAC direct public disponible")
    }
    private fun relay(video: String, address: String): AudioStream {
        val base = validateInstance(address)
        val errors = mutableListOf<String>()
        for (suffix in listOf("?local=true", "")) {
            try {
                val root = json(Request.Builder().url("$base/api/v1/videos/$video$suffix").build())
                root.stringOrNull("error")?.let { throw IOException(it.take(250)) }
                for (format in root.optJSONArray("adaptiveFormats").objects().filter {
                    it.optString("type").startsWith("audio/mp4") && it.stringOrNull("url") != null
                }.sortedByDescending { it.optInt("bitrate") }.take(2)) {
                    val uri = URI(base + "/").resolve(format.getString("url"))
                    if (uri.scheme != "https" || uri.userInfo != null) continue
                    try { return AudioStream(uri.toString(), format.optInt("bitrate"), "Invidious").also { validate(it) } }
                    catch (e: IOException) { errors += e.message.orEmpty() }
                }
            } catch (e: IOException) { errors += e.message.orEmpty() }
        }
        throw IOException("Relais : " + errors.distinct().takeLast(2).joinToString(" · "))
    }
    fun validate(stream: AudioStream) {
        client.newCall(Request.Builder().url(stream.url).header("Range", "bytes=0-4095").build()).execute().use { response ->
            if (!response.isSuccessful) throw IOException("${stream.provider} : HTTP ${response.code}")
            val bytes = response.body?.byteStream()?.readNBytesCompat(64) ?: byteArrayOf()
            if (!String(bytes, Charsets.ISO_8859_1).contains("ftyp")) throw IOException("${stream.provider} : la réponse n’est pas un fichier M4A")
            val range = ByteRange.parse(response.header("Content-Range"))
            if (range != null && range.total > 4160) {
                response.close()
                client.newCall(Request.Builder().url(stream.url).header("Range", "bytes=4096-4159").build()).execute().use { next ->
                    if (next.code != 206) throw IOException("${stream.provider} : début accessible, suite refusée (HTTP ${next.code})")
                    val span = ByteRange.parse(next.header("Content-Range"))
                    if (span?.start != 4096L || span.total != range.total || next.body?.byteStream()?.readNBytesCompat(64)?.size != 64) throw IOException("Plage audio suivante invalide")
                }
            }
        }
    }
    fun lyrics(track: Track): String? {
        if (!track.lyrics.isNullOrBlank()) return track.lyrics
        if (track.source == "bundled") return null
        val url = HttpUrl.Builder().scheme("https").host("lrclib.net").addPathSegments("api/get")
            .addQueryParameter("track_name", track.title).addQueryParameter("artist_name", track.artist.substringBefore(','))
            .apply { if (track.duration > 0) addQueryParameter("duration", (track.duration / 1000).toString()) }.build()
        client.newCall(Request.Builder().url(url).header("User-Agent", "Blusic Android/1.0").build()).execute().use { response ->
            if (response.code == 404) return null
            if (!response.isSuccessful) throw IOException("Paroles : HTTP ${response.code}")
            val body = JSONObject(response.body?.string() ?: "{}")
            if (body.optBoolean("instrumental")) return "Instrumental — pas de paroles."
            return body.stringOrNull("syncedLyrics") ?: body.stringOrNull("plainLyrics")
        }
    }
    private fun json(request: Request): JSONObject = client.newCall(request.newBuilder().header("User-Agent", "Blusic Android/1.0").build()).execute().use {
        if (!it.isSuccessful) throw IOException("${request.url.host} : HTTP ${it.code}")
        try { JSONObject(it.body?.string() ?: "") } catch (_: Exception) { throw IOException("${request.url.host} renvoie une page au lieu du JSON attendu") }
    }
    companion object {
        fun validGoogleMedia(value: String): Boolean = runCatching {
            val u = URI(value); u.scheme == "https" && u.host?.endsWith(".googlevideo.com") == true && u.userInfo == null
        }.getOrDefault(false)
        fun validateInstance(value: String): String {
            val u = runCatching { URI(value.trim()) }.getOrElse { throw IllegalArgumentException("Adresse HTTPS invalide") }
            require(u.scheme == "https" && !u.host.isNullOrBlank() && u.userInfo == null && u.query == null && u.fragment == null) { "Indique une adresse HTTPS sans identifiants ni paramètres" }
            return u.toString().trimEnd('/')
        }
        fun parseSearch(root: JSONObject): SearchPage {
            if (root.has("error")) throw IOException("Catalogue indisponible")
            val seen = hashSetOf<String>()
            val tracks = dictionaries("musicResponsiveListItemRenderer", root).mapNotNull { row ->
                val serialized = row.toString()
                if (!serialized.contains("MUSIC_VIDEO_TYPE_ATV") || serialized.contains("MUSIC_VIDEO_TYPE_OMV") || row.optString("musicItemRendererDisplayPolicy").contains("GREY_OUT")) return@mapNotNull null
                val columns = row.optJSONArray("flexColumns").objects().map { it.optJSONObject("musicResponsiveListItemFlexColumnRenderer")?.optJSONObject("text")?.optJSONArray("runs").objects() }
                val id = row.optJSONObject("playlistItemData")?.optString("videoId") ?: return@mapNotNull null
                if (!id.matches(Regex("[A-Za-z0-9_-]{11}")) || !seen.add(id)) return@mapNotNull null
                val title = columns.firstOrNull()?.joinToString("") { it.optString("text") }.orEmpty()
                if (title.isBlank()) return@mapNotNull null
                val runs = columns.drop(1).flatten()
                fun browse(r: JSONObject) = r.optJSONObject("navigationEndpoint")?.optJSONObject("browseEndpoint")?.optString("browseId").orEmpty()
                val artist = runs.filter { browse(it).startsWith("UC") }.map { it.optString("text") }.distinct().joinToString(", ")
                val album = runs.firstOrNull { browse(it).startsWith("MPRE") }?.optString("text").orEmpty()
                val seconds = runs.firstNotNullOfOrNull { parseDuration(it.optString("text")) } ?: 0
                val artwork = dictionaries("thumbnail", row).flatMap { it.optJSONArray("thumbnails").objects() }
                    .maxByOrNull { it.optInt("width") }?.stringOrNull("url")?.takeIf { it.startsWith("https://") }
                Track("yt:$id", title, artist, album, seconds * 1000, "online", id, artworkUrl = artwork)
            }
            val token = dictionaries("nextContinuationData", root).firstNotNullOfOrNull { it.stringOrNull("continuation") }
                ?: dictionaries("continuationCommand", root).firstNotNullOfOrNull { it.stringOrNull("token") }
            return SearchPage(tracks, token)
        }
        fun parseDuration(s: String): Long? {
            val parts = s.split(':'); if (parts.size !in 2..3 || parts.any { it.isEmpty() || !it.all(Char::isDigit) }) return null
            return parts.fold(0L) { n, p -> n * 60 + (p.toLongOrNull() ?: return null) }
        }
        private fun dictionaries(key: String, value: Any?): List<JSONObject> = when (value) {
            is JSONObject -> listOfNotNull(value.optJSONObject(key)) + value.keys().asSequence().flatMap { dictionaries(key, value.opt(it)) }.toList()
            is JSONArray -> (0 until value.length()).flatMap { dictionaries(key, value.opt(it)) }
            else -> emptyList()
        }
    }
}
internal fun java.io.InputStream.readNBytesCompat(count: Int): ByteArray {
    val out = java.io.ByteArrayOutputStream(count); val buffer = ByteArray(count)
    while (out.size() < count) { val n = read(buffer, 0, count - out.size()); if (n < 0) break; out.write(buffer, 0, n) }
    return out.toByteArray()
}
