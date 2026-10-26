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
data class AudioStream(val url: String, val bitrate: Int, val provider: String, val quality: String = "standard", val duration: Long = 0)

class MusicApi(val client: OkHttpClient = OkHttpClient.Builder().connectTimeout(5, TimeUnit.SECONDS)
    .readTimeout(6, TimeUnit.SECONDS).callTimeout(7, TimeUnit.SECONDS).build(),
    private val nativeResolver: (suspend (String, LibraryState) -> AudioStream)? = null) {
    private val resolved = ConcurrentHashMap<String, Pair<Long, AudioStream>>()
    private val relayClient = client.newBuilder().readTimeout(17, TimeUnit.SECONDS).callTimeout(17, TimeUnit.SECONDS).build()
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
        val key = "${settings.resolutionKey}|$video"
        resolved[key]?.takeIf { it.first > System.currentTimeMillis() }?.let { return@withContext it.second }
        val usesNative = nativeResolver != null && settings.sourceMode in listOf("auto", "youtubei")
        withTimeout(if (usesNative) 35_000 else 18_000) {
            supervisorScope {
                val outcomes = Channel<Result<AudioStream>>(4)
                val jobs = mutableListOf<Job>()
                suspend fun attempt(block: () -> AudioStream) {
                    try { outcomes.send(Result.success(runInterruptible(Dispatchers.IO, block))) }
                    catch (e: CancellationException) { throw e }
                    catch (e: Exception) { outcomes.send(Result.failure(e)) }
                }
                if (usesNative) jobs += launch {
                    try { outcomes.send(Result.success(withTimeout(32_000) { nativeResolver!!.invoke(video, settings) })) }
                    catch (e: Exception) {
                        currentCoroutineContext().ensureActive()
                        outcomes.send(Result.failure(IOException("youtubei.js sur cet appareil : ${e.localizedMessage}")))
                    }
                }
                if (settings.sourceMode in listOf("auto", "youtubei") && !settings.relayDisabled && settings.relayAddress.isNotBlank() && !relayKey.isNullOrBlank()) jobs += launch {
                    if (usesNative) delay(600)
                    attempt { relayService(video, settings.relayAddress, relayKey, settings.highQuality) }
                }
                if (settings.sourceMode in listOf("auto", "direct")) jobs += launch {
                    if (usesNative) delay(900)
                    attempt { direct(video, settings.highQuality).also { validate(it) } }
                }
                if (settings.sourceMode in listOf("auto", "invidious")) jobs += launch {
                    if (settings.sourceMode == "auto") delay(if (usesNative) 1200 else 350)
                    attempt {
                        try { relay(video, settings.instance, settings.highQuality) }
                        catch (e: IOException) {
                            if (!settings.automaticFallback) throw e
                            var result: AudioStream? = null
                            for (address in alternatives(settings.instance)) { try { result = relay(video, address, settings.highQuality); break } catch (_: IOException) { } }
                            result ?: throw e
                        }
                    }
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
    private fun relayService(video: String, address: String, key: String, high: Boolean): AudioStream {
        val base = validateInstance(address)
        val payload = json(Request.Builder().url("$base/v1/streams/$video" + if (high) "?quality=high" else "").header("Authorization", "Bearer $key").build(), relayClient)
        if (high && payload.optString("requestedQuality") != "high") throw IOException("Relais sans prise en charge de la haute qualité")
        val server = URI(base)
        val url = server.resolve(payload.getString("url"))
        if (url.scheme != "https" || url.host != server.host || url.port != server.port || url.userInfo != null || !url.path.startsWith("/v1/audio/")) throw IOException("Lien audio du relais invalide")
        return AudioStream(url.toString(), payload.optInt("bitrate"), "youtubei.js", if (high) "high" else "standard", (payload.optDouble("duration", 0.0) * 1000).toLong()).also(::validate)
    }
    private fun direct(video: String, high: Boolean): AudioStream {
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
        return preferred(formats, high).firstNotNullOfOrNull { f -> f.stringOrNull("url")?.takeIf { validGoogleMedia(it) }?.let { AudioStream(it, f.optInt("bitrate"), "YouTube direct", if (high) "high" else "standard") } }
            ?: throw IOException("Aucun AAC direct public disponible")
    }
    private fun relay(video: String, address: String, high: Boolean): AudioStream {
        val base = validateInstance(address)
        val errors = mutableListOf<String>()
        for (suffix in listOf("?local=true", "")) {
            if (Thread.currentThread().isInterrupted) throw IOException("Chargement annulé")
            try {
                val root = json(Request.Builder().url("$base/api/v1/videos/$video$suffix").build())
                root.stringOrNull("error")?.let { throw IOException(it.take(250)) }
                val formats = root.optJSONArray("adaptiveFormats").objects().filter {
                    it.optString("type").startsWith("audio/mp4") && it.stringOrNull("url") != null
                }
                for (format in preferred(formats, high).take(2)) {
                    val uri = URI(base + "/").resolve(format.getString("url"))
                    if (uri.scheme != "https" || uri.userInfo != null) continue
                    try { return AudioStream(uri.toString(), format.optInt("bitrate"), "Invidious", if (high) "high" else "standard").also { validate(it) } }
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
                val offset = maxOf(4096L, range.total / 2)
                val end = minOf(offset + 63, range.total - 1)
                client.newCall(Request.Builder().url(stream.url).header("Range", "bytes=$offset-$end").build()).execute().use { next ->
                    if (next.code != 206) throw IOException("${stream.provider} : début accessible, suite refusée (HTTP ${next.code})")
                    val span = ByteRange.parse(next.header("Content-Range"))
                    if (span?.start != offset || span.total != range.total || next.body?.byteStream()?.readNBytesCompat(64)?.size?.toLong() != end-offset+1) throw IOException("Plage audio suivante invalide")
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
            if (response.code == 404) return searchLyrics(track)
            if (!response.isSuccessful) throw IOException("Paroles : HTTP ${response.code}")
            val body = JSONObject(response.body?.string() ?: "{}")
            if (body.optBoolean("instrumental")) return "Instrumental — pas de paroles."
            return body.stringOrNull("syncedLyrics") ?: body.stringOrNull("plainLyrics")
        }
    }
    private fun json(request: Request, transport: OkHttpClient = client): JSONObject = transport.newCall(request.newBuilder().header("User-Agent", "Blusic Android/1.9.2").build()).execute().use {
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
                Track("yt:$id", title, artist, album, seconds * 1000, "online", id, artworkUrl = artwork,
                    artistId = runs.firstNotNullOfOrNull { browse(it).takeIf { b -> b.startsWith("UC") } }, explicit = serialized.contains("MUSIC_EXPLICIT_BADGE"))
            }
            val token = dictionaries("nextContinuationData", root).firstNotNullOfOrNull { it.stringOrNull("continuation") }
                ?: dictionaries("continuationCommand", root).firstNotNullOfOrNull { it.stringOrNull("token") }
            return SearchPage(tracks, token)
        }
        fun parseDuration(s: String): Long? {
            val parts = s.split(':'); if (parts.size !in 2..3 || parts.any { it.isEmpty() || !it.all(Char::isDigit) }) return null
            return parts.fold(0L) { n, p -> n * 60 + (p.toLongOrNull() ?: return null) }
        }
        internal fun dictionaries(key: String, value: Any?): List<JSONObject> = when (value) {
            is JSONObject -> listOfNotNull(value.optJSONObject(key)) + value.keys().asSequence().flatMap { dictionaries(key, value.opt(it)) }.toList()
            is JSONArray -> (0 until value.length()).flatMap { dictionaries(key, value.opt(it)) }
            else -> emptyList()
        }
        fun preferred(formats: List<JSONObject>, high: Boolean): List<JSONObject> {
            val ranked = formats.sortedByDescending { it.optInt("bitrate") }
            return if (high) ranked else ranked.filter { it.optInt("bitrate") <= 160000 }.ifEmpty { ranked }
        }
    }
    private fun catalog(endpoint: String, payload: JSONObject): JSONObject {
        payload.put("context", JSONObject().put("client", JSONObject().put("clientName", "WEB_REMIX").put("clientVersion", "1.20261021.01.00").put("hl", "fr").put("gl", "FR")))
        return json(Request.Builder().url("https://music.youtube.com/youtubei/v1/$endpoint?prettyPrint=false").header("Origin", "https://music.youtube.com")
            .post(payload.toString().toRequestBody(jsonType)).build())
    }
    fun artists(query: String): List<MusicArtist> = dictionaries("musicResponsiveListItemRenderer", catalog("search", JSONObject().put("query", query).put("params", "EgWKAQIgAWoMEA4QChADEAQQCRAF"))).mapNotNull { row ->
        if (row.has("playlistItemData")) return@mapNotNull null
        val renderer = row.optJSONArray("flexColumns")?.optJSONObject(0)?.optJSONObject("musicResponsiveListItemFlexColumnRenderer")
        val endpoint = (dictionaries("browseEndpoint", row.optJSONObject("navigationEndpoint")) + dictionaries("browseEndpoint", renderer)).firstOrNull { it.optString("browseId").startsWith("UC") || it.optString("browseId").startsWith("MPLA") } ?: return@mapNotNull null
        val name = renderer?.optJSONObject("text")?.optJSONArray("runs").objects().joinToString("") { it.optString("text") }
        if (name.isBlank()) null else MusicArtist(endpoint.getString("browseId"), name, artwork(row))
    }.distinctBy { it.id }
    fun artist(known: MusicArtist): ArtistProfile {
        require(known.id.startsWith("UC") || known.id.startsWith("MPLA")) { "Identifiant d’artiste invalide" }
        val root = catalog("browse", JSONObject().put("browseId", known.id))
        val header = (dictionaries("musicImmersiveHeaderRenderer", root) + dictionaries("musicVisualHeaderRenderer", root)).firstOrNull()
        fun text(key: String) = header?.optJSONObject(key)?.optJSONArray("runs").objects().joinToString("") { it.optString("text") }
        return ArtistProfile(known.copy(name = text("title").ifBlank { known.name }, artworkUrl = header?.let(::artwork) ?: known.artworkUrl), text("description"), parseSearch(root).tracks)
    }
    private fun artwork(root: JSONObject): String? = dictionaries("thumbnail", root).flatMap { it.optJSONArray("thumbnails").objects() }.filter { it.optInt("width") <= 640 }.maxByOrNull { it.optInt("width") }?.stringOrNull("url")?.takeIf { it.startsWith("https://") }
    fun match(reference: Track): Track {
        val ranked = search("${CatalogMatching.title(reference.title)} ${reference.artist.substringBefore(',').substringBefore(';')}").tracks.sortedByDescending { CatalogMatching.score(reference, it) }
        return ranked.firstOrNull { CatalogMatching.score(reference, it) >= 85 } ?: throw IOException("Aucune association sûre pour « ${reference.title} ». Choisis le titre manuellement.")
    }
    private fun searchLyrics(track: Track): String? {
        val url = HttpUrl.Builder().scheme("https").host("lrclib.net").addPathSegments("api/search").addQueryParameter("q", "${track.title} ${track.artist.substringBefore(',')}").build()
        client.newCall(Request.Builder().url(url).build()).execute().use { response ->
            if (!response.isSuccessful) return null
            return JSONArray(response.body?.string().orEmpty()).objects().filter { candidate ->
                CatalogMatching.score(track, Track(title = candidate.optString("trackName"), artist = candidate.optString("artistName"), duration = (candidate.optDouble("duration", 0.0) * 1000).toLong(), location = "lyrics")) >= 85
            }.firstNotNullOfOrNull { it.stringOrNull("syncedLyrics") ?: it.stringOrNull("plainLyrics") }
        }
    }
    private fun alternatives(excluding: String): List<String> = runCatching {
        client.newCall(Request.Builder().url("https://api.invidious.io/").build()).execute().use { response ->
            if (!response.isSuccessful) return emptyList()
            val array = JSONArray(response.body?.string().orEmpty())
            (0 until array.length()).mapNotNull { array.optJSONArray(it)?.optJSONObject(1) }.filter { it.optBoolean("api") && it.optString("type") == "https" }
                .mapNotNull { it.stringOrNull("uri") }.filter { it.trimEnd('/') != excluding.trimEnd('/') }.take(2)
        }
    }.getOrDefault(emptyList())
    fun importRemote(address: String, instance: String): Pair<String, List<Track>> {
        val uri = URI(address.trim()); require(uri.scheme == "https" && uri.userInfo == null) { "Adresse de playlist HTTPS invalide" }
        if (uri.host in listOf("deezer.com", "www.deezer.com", "api.deezer.com")) {
            val id = Regex("/playlist/(\\d+)").find(uri.path)?.groupValues?.get(1) ?: error("Lien Deezer de playlist attendu")
            val root = json(Request.Builder().url("https://api.deezer.com/playlist/$id").build()); require(!root.has("error")) { "Playlist Deezer privée ou indisponible" }
            val tracks = mutableListOf<Track>(); var page = root.getJSONObject("tracks")
            while (true) {
                tracks += page.getJSONArray("data").objects().map { j -> PlaylistImports.reference(j.getString("title"), j.optJSONObject("artist")?.optString("name").orEmpty(), j.optJSONObject("album")?.optString("title").orEmpty(), j.optLong("duration") * 1000) }
                require(tracks.size <= 2000) { "Playlist limitée à 2 000 titres" }
                val next = page.stringOrNull("next") ?: break; val nextUri = URI(next); require(nextUri.scheme == "https" && nextUri.host == "api.deezer.com")
                page = json(Request.Builder().url(next).build())
            }
            return root.optString("title", "Deezer") to tracks.distinctBy(Track::identity)
        }
        require(uri.host in listOf("youtube.com", "www.youtube.com", "music.youtube.com", "m.youtube.com")) { "Lien YouTube ou Deezer attendu" }
        val id = uri.rawQuery.orEmpty().split('&').firstOrNull { it.startsWith("list=") }?.substringAfter('=') ?: error("Identifiant de playlist manquant")
        require(id.matches(Regex("[A-Za-z0-9_-]{10,100}")))
        val tracks = mutableListOf<Track>(); val seen = hashSetOf<String>(); var name = "YouTube"
        for (page in 1..20) {
            val root = json(Request.Builder().url("${validateInstance(instance)}/api/v1/playlists/$id?page=$page").build()); name = root.optString("title", name)
            val batch = root.optJSONArray("videos").objects(); if (batch.isEmpty()) break
            val fresh = batch.mapNotNull { j -> val video = j.optString("videoId"); if (!video.matches(Regex("[A-Za-z0-9_-]{11}")) || !seen.add(video)) null else Track("yt:$video", j.optString("title"), j.optString("author"), duration = j.optLong("lengthSeconds") * 1000, location = video) }
            require(fresh.isNotEmpty()) { "Le relais répète une page de playlist" }; tracks += fresh
            require(tracks.size <= 2000) { "Playlist limitée à 2 000 titres" }; if (seen.size >= root.optInt("videoCount", Int.MAX_VALUE)) break
        }
        return name to tracks
    }
}
internal fun java.io.InputStream.readNBytesCompat(count: Int): ByteArray {
    val out = java.io.ByteArrayOutputStream(count); val buffer = ByteArray(count)
    while (out.size() < count) { val n = read(buffer, 0, count - out.size()); if (n < 0) break; out.write(buffer, 0, n) }
    return out.toByteArray()
}
