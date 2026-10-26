package app.blusic.android

import android.annotation.SuppressLint
import android.content.Context
import android.media.MediaExtractor
import android.media.MediaFormat
import android.util.Base64
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.File
import java.io.FileOutputStream
import java.net.URI
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

/** WebView executes the packaged protocol only. Media3 plays the validated AAC;
 * no video/audio element or account/browser cookies are used for playback. */
class NativeYouTubeiResolver(private val context: Context, private val scriptProvider: (() -> String)? = null) {
    private val lock = Mutex()
    private val writes = Mutex()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var web: WebView? = null
    private var ready = CompletableDeferred<Unit>()
    @Volatile private var token: String? = null
    private var result: CompletableDeferred<AudioStream>? = null
    private val calls = ConcurrentHashMap<Int, Call>()
    private data class Stream(val response: Response, var count: Long = 0)
    private val streams = ConcurrentHashMap<Int, Stream>()
    private var file: File? = null
    private var output: FileOutputStream? = null
    private var expected = 0L
    private var written = 0L
    private var quality = "standard"
    private val cookies = object : CookieJar {
        private val values = mutableListOf<Cookie>()
        @Synchronized override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
            val now = System.currentTimeMillis(); values.removeAll { it.expiresAt <= now }
            cookies.filterNot { it.name.matches(Regex("(?i)(SAPISID|APISID|SID|HSID|SSID|LOGIN_INFO|__Secure-[0-9]P.*SID.*)")) }.forEach { c ->
                values.removeAll { it.name == c.name && it.domain == c.domain && it.path == c.path }; values += c
            }
        }
        @Synchronized override fun loadForRequest(url: HttpUrl) = values.filter { it.expiresAt > System.currentTimeMillis() && it.matches(url) }
    }
    private val client = OkHttpClient.Builder().cookieJar(cookies).connectTimeout(10, TimeUnit.SECONDS).readTimeout(12, TimeUnit.SECONDS).callTimeout(20, TimeUnit.SECONDS).build()

    suspend fun resolve(video: String, high: Boolean): AudioStream = lock.withLock {
        require(video.matches(Regex("[A-Za-z0-9_-]{11}")))
        val job = UUID.randomUUID().toString(); val answer = CompletableDeferred<AudioStream>()
        token = job; result = answer; quality = if (high) "high" else "standard"
        var succeeded = false
        try {
            val audio = withTimeout(32_000) {
                withContext(Dispatchers.Main) { prepareDocument() }
                ready.await()
                withContext(Dispatchers.Main) { web?.evaluateJavascript("window.__blusicResolve('$video','$job','$quality'); void 0", null) }
                answer.await()
            }
            succeeded = true; audio
        } finally {
            if (token == job) {
                token = null; result = null
                calls.values.forEach(Call::cancel); calls.clear(); streams.values.forEach { it.response.close() }; streams.clear()
                withContext(NonCancellable) { writes.withLock { output?.close(); output = null; file?.delete(); file = null }; if (!succeeded) reset() }
            }
        }
    }
    @SuppressLint("SetJavaScriptEnabled")
    private fun prepareDocument() {
        if (web != null) return
        ready = CompletableDeferred()
        val source = scriptProvider?.invoke() ?: context.assets.open("YouTubeiResolver.js").bufferedReader().use { it.readText() }
        web = WebView(context).apply {
            settings.javaScriptEnabled = true; settings.domStorageEnabled = false
            settings.allowFileAccess = false; settings.allowContentAccess = false
            settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW; settings.mediaPlaybackRequiresUserGesture = true
            addJavascriptInterface(Bridge(), "BlusicNative")
            webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView, url: String) {
                    view.evaluateJavascript("window.webkit={messageHandlers:{blusicResolver:{postMessage:function(x){BlusicNative.postMessage(JSON.stringify(x));}}}};\n$source", null)
                }
                override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?) = true
                override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): WebResourceResponse? =
                    if (request?.url?.scheme in listOf("https", "http")) WebResourceResponse("text/plain", "UTF-8", ByteArrayInputStream(byteArrayOf())) else null
            }
            loadDataWithBaseURL("https://www.youtube.com/", "<!doctype html><html><head><title>Blusic audio resolver</title></head><body></body></html>", "text/html", "UTF-8", null)
        }
    }
    private suspend fun reset() = withContext(NonCancellable + Dispatchers.Main) {
        web?.removeJavascriptInterface("BlusicNative"); web?.stopLoading(); web?.destroy(); web = null
    }
    inner class Bridge {
        @JavascriptInterface fun postMessage(text: String) {
            if (text.length > 12_000_000) return
            val body = runCatching { JSONObject(text) }.getOrNull() ?: return
            if (body.optString("action") == "ready") { ready.complete(Unit); return }
            val job = token ?: return
            if (body.optString("job") != job) return
            scope.launch {
                try {
                    val id = body.optInt("request")
                    val reply = when (body.getString("action")) {
                        "fetch" -> fetch(body, id, job)
                        "readFetch" -> {
                            val streamId = body.getInt("stream"); val stream = streams[streamId] ?: error("Flux fermé")
                            val bytes = ByteArray(32768); val count = stream.response.body?.byteStream()?.read(bytes) ?: -1
                            stream.count += maxOf(0, count); require(stream.count <= 12_000_000) { "Réponse trop volumineuse" }
                            if (count < 0) { streams.remove(streamId)?.response?.close(); JSONObject().put("done", true).put("body", "") }
                            else JSONObject().put("done", false).put("body", Base64.encodeToString(bytes.copyOf(count), Base64.NO_WRAP))
                        }
                        "closeFetch" -> { streams.remove(body.getInt("stream"))?.response?.close(); JSONObject().put("ok", true) }
                        "beginAudio" -> writes.withLock {
                            check(token == job); output?.close(); file?.delete(); expected = body.getLong("expected"); written = 0
                            require(expected in 1..25_000_000); file = File(context.cacheDir, "youtubei-${UUID.randomUUID()}.m4a"); output = FileOutputStream(file!!)
                            JSONObject().put("ok", true)
                        }
                        "appendAudio" -> writes.withLock {
                            check(token == job); val bytes = Base64.decode(body.getString("body"), Base64.DEFAULT)
                            require(written + bytes.size <= expected); checkNotNull(output).write(bytes); written += bytes.size
                            JSONObject().put("ok", true)
                        }
                        "finished" -> {
                            writes.withLock {
                                check(token == job); require(written == expected && expected == body.getLong("expected")) { "AAC incomplet" }
                                output?.close(); output = null
                                val prepared = checkNotNull(file); validateAudio(prepared, (body.optDouble("duration", 0.0) * 1000).toLong())
                                if (token == job && result?.complete(AudioStream(prepared.toURI().toString(), body.optInt("bitrate"), "youtubei.js · Android", quality, (body.optDouble("duration", 0.0) * 1000).toLong())) == true) file = null
                                else { prepared.delete(); file = null }
                            }; return@launch
                        }
                        "failed" -> { result?.completeExceptionally(java.io.IOException(body.optString("error").replace(Regex("https?://\\S+"), "[source]").take(600))); return@launch }
                        else -> return@launch
                    }
                    respond(id, reply, job)
                } catch (e: Exception) {
                    if (token == job) {
                        if (body.optString("action") in listOf("finished", "beginAudio", "appendAudio")) result?.completeExceptionally(e)
                        else respond(body.optInt("request"), JSONObject().put("error", e.localizedMessage.orEmpty().replace(Regex("https?://\\S+"), "[source]").take(300)), job)
                    }
                }
            }
        }
    }
    private fun fetch(body: JSONObject, id: Int, job: String): JSONObject {
        val address = body.getString("url"); require(allows(address)) { "Hôte youtubei.js non autorisé" }
        val headers = body.optJSONObject("headers") ?: JSONObject(); val request = Request.Builder().url(address)
        headers.keys().forEach { name -> if (name.lowercase() !in listOf("host", "cookie", "authorization", "content-length", "connection")) request.header(name, headers.getString(name)) }
        val method = body.optString("method", "GET"); require(method in listOf("GET", "POST", "HEAD"))
        val encoded = body.stringOrNull("body"); require((encoded?.length ?: 0) <= 4_000_000)
        val data = encoded?.let { Base64.decode(it, Base64.DEFAULT) } ?: byteArrayOf()
        request.method(method, if (method == "POST") data.toRequestBody(headers.optString("content-type").toMediaTypeOrNull()) else null)
        val call = client.newCall(request.build()); calls[id] = call
        try {
            val response = call.execute()
            if (token != job || !allows(response.request.url.toString())) { response.close(); error("Réponse annulée ou hôte invalide") }
            streams[id] = Stream(response)
            val fields = JSONObject(); response.headers.names().forEach { fields.put(it, response.header(it)) }
            // OkHttp transparently decompresses gzip; Response sees decoded bytes.
            fields.remove("content-encoding"); fields.remove("content-length")
            return JSONObject().put("status", response.code).put("headers", fields).put("stream", id).put("url", response.request.url.toString())
        } finally { calls.remove(id) }
    }
    private suspend fun respond(id: Int, data: JSONObject, job: String) = withContext(Dispatchers.Main) {
        if (token == job) web?.evaluateJavascript("window.__blusicReply($id,$data)", null)
    }
    companion object {
        fun allows(address: String): Boolean = runCatching {
            val u = URI(address); val host = u.host?.lowercase().orEmpty()
            u.scheme == "https" && u.userInfo == null && u.port in listOf(-1, 443) &&
                (host in listOf("www.youtube.com", "music.youtube.com", "m.youtube.com", "youtube.com", "youtubei.googleapis.com", "jnn-pa.googleapis.com", "www.google.com", "www.gstatic.com") || host.endsWith(".googlevideo.com") || host.endsWith(".gstatic.com"))
        }.getOrDefault(false)
        fun validateAudio(file: File, expectedDuration: Long = 0): Long {
            require(file.length() in 16..300_000_000) { "Fichier audio vide ou trop volumineux" }
            val extractor = MediaExtractor()
            try {
                extractor.setDataSource(file.absolutePath)
                val format = (0 until extractor.trackCount).map(extractor::getTrackFormat).firstOrNull { it.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true } ?: error("Fichier audio indécodable")
                val duration = if (format.containsKey(MediaFormat.KEY_DURATION)) format.getLong(MediaFormat.KEY_DURATION) / 1000 else 0
                require(duration > 0 && (expectedDuration <= 0 || duration >= expectedDuration * .8)) { "Audio tronqué" }
                return duration
            } finally { extractor.release() }
        }
    }
}
