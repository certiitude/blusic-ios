package app.blusic.android

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.BaseDataSource
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException

data class ByteRange(val start: Long, val end: Long, val total: Long) {
    companion object {
        fun parse(value: String?): ByteRange? {
            val match = Regex("bytes (\\d+)-(\\d+)/(\\d+)").matchEntire(value ?: "") ?: return null
            val values = match.groupValues.drop(1).map { it.toLongOrNull() ?: return null }
            val (start, end, total) = values
            return if (start >= 0 && end >= start && end < total) ByteRange(start, end, total) else null
        }
    }
}

/** Media3 consumes a continuous source while the HTTP host receives finite ranges.
 * Each Content-Range is checked before bytes reach the decoder. No open-ended
 * request and no assumption that an HTTP 200 HTML page is playable audio.
 */
@UnstableApi
class FiniteHttpDataSource(private val client: OkHttpClient) : BaseDataSource(true) {
    private var spec: DataSpec? = null
    private var buffer = byteArrayOf()
    private var cursor = 0
    private var position = 0L
    private var total = -1L
    private var remaining = C.LENGTH_UNSET.toLong()
    private var opened = false
    override fun open(dataSpec: DataSpec): Long {
        transferInitializing(dataSpec)
        spec = dataSpec; position = dataSpec.position; remaining = dataSpec.length; total = -1
        fetch()
        if (remaining == C.LENGTH_UNSET.toLong()) remaining = (total - position).coerceAtLeast(0)
        else remaining = minOf(remaining, (total - position).coerceAtLeast(0))
        opened = true; transferStarted(dataSpec)
        return remaining
    }
    private fun fetch() {
        val s = spec ?: throw IOException("Source fermée")
        val end = minOf(position + 262143, if (total >= 0) total - 1 else Long.MAX_VALUE)
        val request = Request.Builder().url(s.uri.toString()).header("Range", "bytes=$position-$end")
            .header("User-Agent", "Blusic Android/1.0").build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw IOException("Flux audio : HTTP ${response.code}")
            val mime = response.header("Content-Type").orEmpty()
            if (mime.startsWith("text/") || mime.contains("json")) throw IOException("Le serveur renvoie une page au lieu d’audio")
            if (response.code == 206) {
                val range = ByteRange.parse(response.header("Content-Range")) ?: throw IOException("Content-Range absent ou invalide")
                if (range.start != position || range.end > end || range.total > 300_000_000 || (total >= 0 && total != range.total)) throw IOException("Plage audio incohérente")
                buffer = response.body?.byteStream()?.readNBytesCompat(262145) ?: byteArrayOf()
                if (buffer.size.toLong() != range.end - range.start + 1) throw IOException("Plage audio tronquée")
                total = range.total
            } else {
                if (position != 0L) throw IOException("Le serveur ignore les plages de lecture")
                val size = response.body?.contentLength() ?: -1
                if (size !in 1..20_000_000) throw IOException("Le serveur ignore Range et le fichier est trop volumineux")
                buffer = response.body!!.byteStream().readNBytesCompat(size.toInt() + 1)
                if (buffer.size.toLong() != size) throw IOException("Audio tronqué")
                total = size
            }
            cursor = 0
        }
    }
    override fun read(target: ByteArray, offset: Int, length: Int): Int {
        if (length == 0) return 0
        if (remaining == 0L || position >= total) return C.RESULT_END_OF_INPUT
        if (cursor == buffer.size) fetch()
        val n = minOf(length, buffer.size - cursor, remaining.coerceAtMost(Int.MAX_VALUE.toLong()).toInt())
        if (n <= 0) throw IOException("Source audio vide")
        buffer.copyInto(target, offset, cursor, cursor + n)
        cursor += n; position += n; remaining -= n; bytesTransferred(n)
        return n
    }
    override fun getUri(): Uri? = spec?.uri
    override fun close() { spec = null; buffer = byteArrayOf(); if (opened) { opened = false; transferEnded() } }
    class Factory(private val client: OkHttpClient) : DataSource.Factory { override fun createDataSource() = FiniteHttpDataSource(client) }
}
