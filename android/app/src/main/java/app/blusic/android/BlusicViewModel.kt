package app.blusic.android

import android.app.Application
import android.content.ComponentName
import android.content.Context
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.MediaItem
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.guava.await
import org.json.JSONObject

data class PlaybackUi(val track: Track? = null, val playing: Boolean = false, val loading: Boolean = false,
    val error: String? = null, val queue: List<Track> = emptyList(), val shuffle: Boolean = false, val repeat: Int = Player.REPEAT_MODE_OFF)

class BlusicViewModel(application: Application) : AndroidViewModel(application) {
    private val app = application as BlusicApplication
    val library = app.library.state
    val libraryError = app.library.error
    private val mutablePlayback = MutableStateFlow(PlaybackUi())
    val playback = mutablePlayback.asStateFlow()
    val search = MutableStateFlow(SearchPage(emptyList(), null))
    val searchLoading = MutableStateFlow(false)
    val searchError = MutableStateFlow<String?>(null)
    val home = MutableStateFlow<List<Track>>(emptyList())
    val homeError = MutableStateFlow<String?>(null)
    val message = MutableStateFlow<String?>(null)
    var controller: MediaController? = null
        private set
    private val connected = CompletableDeferred<MediaController>()
    private var searchJob: Job? = null
    private var loadingDeadline: Job? = null
    private val listener = object : Player.Listener {
        override fun onEvents(player: Player, events: Player.Events) {
            val track = player.currentMediaItem?.mediaMetadata?.extras?.getString("track")?.let { runCatching { Track.fromJson(JSONObject(it)) }.getOrNull() }
            val previous = mutablePlayback.value
            mutablePlayback.value = previous.copy(track = track, playing = player.isPlaying,
                loading = player.playbackState == Player.STATE_BUFFERING, shuffle = player.shuffleModeEnabled, repeat = player.repeatMode)
            if (player.isPlaying) { loadingDeadline?.cancel(); if (track != null && track.id != previous.track?.id) save { app.library.record(track) } }
        }
        override fun onPlayerError(error: PlaybackException) {
            loadingDeadline?.cancel()
            val detail = generateSequence<Throwable>(error) { it.cause }.mapNotNull { it.message }.distinct().joinToString("\n").take(650)
            mutablePlayback.update { it.copy(loading = false, playing = false, error = "Lecture impossible : $detail") }
        }
    }
    init {
        viewModelScope.launch {
            try {
                val token = SessionToken(app, ComponentName(app, PlaybackService::class.java))
                val player = MediaController.Builder(app, token).buildAsync().await()
                controller = player; player.addListener(listener); connected.complete(player)
                app.library.ready.await()
                applyAudio()
            } catch (e: Exception) { connected.completeExceptionally(e); message.value = e.localizedMessage }
        }
        loadHome()
    }
    fun loadHome() = viewModelScope.launch {
        homeError.value = null
        try { home.value = withContext(Dispatchers.IO) { app.api.search("rap français").tracks.take(12) } }
        catch (e: Exception) { if (e !is CancellationException) homeError.value = e.localizedMessage }
    }
    fun search(query: String) {
        searchJob?.cancel(); searchError.value = null
        if (query.isBlank()) { search.value = SearchPage(emptyList(), null); searchLoading.value = false; return }
        searchLoading.value = true
        searchJob = viewModelScope.launch {
            try { delay(450); val result = withContext(Dispatchers.IO) { app.api.search(query) }; ensureActive(); search.value = result }
            catch (e: Exception) { if (e !is CancellationException) searchError.value = e.localizedMessage }
            finally { if (isActive) searchLoading.value = false }
        }
    }
    fun loadMore(query: String) {
        val token = search.value.continuation ?: return
        if (searchLoading.value) return
        searchLoading.value = true
        searchJob = viewModelScope.launch {
            try {
                val result = withContext(Dispatchers.IO) { app.api.search(query, token) }
                search.value = SearchPage((search.value.tracks + result.tracks).distinctBy { it.identity }, result.continuation)
            } catch (e: Exception) { if (e !is CancellationException) searchError.value = e.localizedMessage }
            finally { if (isActive) searchLoading.value = false }
        }
    }
    fun play(track: Track, context: List<Track> = listOf(track)) = viewModelScope.launch {
        try {
            val player = connected.await()
            val queue = context.ifEmpty { listOf(track) }.distinctBy { it.identity }
            mutablePlayback.value = PlaybackUi(track = track, loading = true, queue = queue, shuffle = player.shuffleModeEnabled, repeat = player.repeatMode)
            app.api.invalidate(track.location)
            player.setMediaItems(queue.map(Track::mediaItem), queue.indexOfFirst { it.identity == track.identity }.coerceAtLeast(0), 0)
            player.prepare(); player.play(); startDeadline()
            save { app.library.record(track) }
        } catch (e: Exception) { mutablePlayback.update { it.copy(loading = false, error = e.localizedMessage) } }
    }
    private fun startDeadline() {
        loadingDeadline?.cancel()
        loadingDeadline = viewModelScope.launch {
            delay(20_000)
            if (controller?.isPlaying != true) { controller?.stop(); mutablePlayback.update { it.copy(loading = false, playing = false, error = "Le chargement a dépassé 20 secondes. Réessaie ou change de source audio.") } }
        }
    }
    fun toggle() {
        val p = controller ?: return
        if (playback.value.loading) { p.stop(); loadingDeadline?.cancel(); mutablePlayback.update { it.copy(loading = false) } }
        else if (p.isPlaying) p.pause()
        else if (playback.value.error != null || p.playbackState == Player.STATE_IDLE) playback.value.track?.let { play(it, playback.value.queue) }
        else p.play()
    }
    fun next() { controller?.seekToNextMediaItem(); mutablePlayback.update { it.copy(error = null) } }
    fun previous() { controller?.seekToPreviousMediaItem() }
    fun seek(position: Long) { controller?.seekTo(position.coerceAtLeast(0)) }
    fun shuffle() { controller?.let { it.shuffleModeEnabled = !it.shuffleModeEnabled } }
    fun repeat() { controller?.let { it.repeatMode = (it.repeatMode + 1) % 3 } }
    fun favorite(track: Track) = save { app.library.favorite(track) }
    fun importAudio(uris: List<Uri>) = save { app.library.importAudio(uris); message.value = "${uris.size} fichier(s) ajouté(s)" }
    fun createPlaylist(name: String) = save { if (name.isNotBlank()) app.library.createPlaylist(name) }
    fun addToPlaylist(track: Track, playlist: Playlist) = save { app.library.addToPlaylist(track, playlist.id); message.value = "Ajouté à ${playlist.name}" }
    fun source(mode: String, instance: String) = save {
        val validated = MusicApi.validateInstance(instance)
        app.library.update { it.copy(sourceMode = mode, instance = validated) }
    }
    fun audio(speed: Float, linked: Boolean) = save { app.library.update { it.copy(speed = speed, linkedPitch = linked) }; withContext(Dispatchers.Main) { applyAudio() } }
    private fun applyAudio() { val s = library.value; controller?.playbackParameters = PlaybackParameters(s.speed, if (s.linkedPitch) s.speed else 1f) }
    suspend fun lyrics(track: Track): String? = withContext(Dispatchers.IO) {
        val text = app.api.lyrics(track)
        if (!text.isNullOrBlank()) { app.library.add(listOf(track)); app.library.cacheLyrics(track, text) }
        text
    }
    private fun save(block: suspend () -> Unit) = viewModelScope.launch(Dispatchers.IO) { try { block() } catch (e: Exception) { if (e !is CancellationException) message.value = e.localizedMessage } }
    override fun onCleared() { controller?.removeListener(listener); controller?.release(); super.onCleared() }
}
