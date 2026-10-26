package app.blusic.android

import android.content.Context
import android.net.Uri
import androidx.media3.datasource.DataSpec
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class PreparedAudioRepository(context: Context, private val api: MusicApi) {
    private val root = File(context.cacheDir, "PreparedAudio").apply { mkdirs() }
    private val locks = java.util.concurrent.ConcurrentHashMap<String, Mutex>()
    private fun key(track: Track, settings: LibraryState) = MessageDigest.getInstance("SHA-256").digest("${track.identity}|${settings.resolutionKey}".toByteArray()).joinToString("") { "%02x".format(it) }
    fun cached(track: Track, settings: LibraryState): AudioStream? = runCatching {
        val id = key(track, settings); val meta = File(root, "$id.json"); val file = File(root, "$id.m4a")
        val j = JSONObject(meta.readText()); require(j.getLong("expires") > System.currentTimeMillis() && file.length() == j.getLong("size"))
        AudioStream(file.toURI().toString(), j.getInt("bitrate"), j.getString("provider"), settings.quality, j.optLong("duration"))
    }.getOrNull()
    suspend fun prepare(track: Track, settings: LibraryState, access: String?): AudioStream = withContext(Dispatchers.IO) {
        if (track.source in listOf("bundled", "local")) return@withContext AudioStream(if (track.source == "bundled") "asset:///${track.location}" else track.location, 0, "Fichier local", settings.quality, track.duration)
        val id = key(track, settings)
        locks.getOrPut(id) { Mutex() }.withLock {
            cached(track, settings)?.let { return@withLock it }
            val source = if (track.source == "remote") {
                val address = java.net.URI(track.location); require(address.scheme == "https" && address.userInfo == null)
                AudioStream(track.location, 0, "Source HTTPS", settings.quality, track.duration)
            } else api.resolve(track.location, settings, access)
            val temporary = File(root, "partial-${java.util.UUID.randomUUID()}.m4a")
            try {
                if (source.url.startsWith("file:")) {
                    val incoming = File(java.net.URI(source.url)); incoming.copyTo(temporary, overwrite = true)
                    if (incoming.parentFile?.canonicalFile == root.parentFile?.canonicalFile && incoming.name.startsWith("youtubei-")) incoming.delete()
                } else {
                    val input = FiniteHttpDataSource(api.client)
                    try {
                        input.open(DataSpec(Uri.parse(source.url)))
                        temporary.outputStream().use { output ->
                            val bytes = ByteArray(32768); var total = 0L
                            while (true) { ensureActive(); val n = input.read(bytes, 0, bytes.size); if (n < 0) break; total += n; require(total <= 25_000_000) { "Préparation audio trop volumineuse" }; output.write(bytes, 0, n) }
                        }
                    } finally { input.close() }
                }
                val duration = NativeYouTubeiResolver.validateAudio(temporary, track.duration)
                ensureActive(); val target = File(root, "$id.m4a"); temporary.copyTo(target, overwrite = true)
                File(root, "$id.json").writeText(JSONObject().put("expires", System.currentTimeMillis() + if (source.bitrate >= 90000) 86_400_000 else 600_000)
                    .put("size", target.length()).put("bitrate", source.bitrate).put("provider", source.provider).put("duration", duration).toString())
                root.listFiles { f -> f.extension == "m4a" && !f.name.startsWith("partial-") }?.sortedByDescending(File::lastModified)?.drop(10)?.forEach { it.delete(); File(root, it.nameWithoutExtension + ".json").delete() }
                source.copy(url = target.toURI().toString(), duration = duration)
            } finally { temporary.delete() }
        }
    }
}
