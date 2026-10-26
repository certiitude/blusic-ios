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
    val engine = app.engineState
    val artistResults = MutableStateFlow<List<MusicArtist>>(emptyList())
    val artistProfile = MutableStateFlow<ArtistProfile?>(null)
    val artistLoading = MutableStateFlow(false)
    val matchReference = MutableStateFlow<Track?>(null)
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
    private var recordedId: String? = null
    private val listener = object : Player.Listener {
        override fun onEvents(player: Player, events: Player.Events) {
            val track = player.currentMediaItem?.mediaMetadata?.extras?.getString("track")?.let { runCatching { Track.fromJson(JSONObject(it)) }.getOrNull() }
            val previous = mutablePlayback.value
            mutablePlayback.value = previous.copy(track = track, playing = player.isPlaying,
                loading = player.playbackState == Player.STATE_BUFFERING, shuffle = player.shuffleModeEnabled, repeat = player.repeatMode,
                queue = (0 until player.mediaItemCount).mapNotNull { player.getMediaItemAt(it).mediaMetadata.extras?.getString("track")?.let { raw -> runCatching { Track.fromJson(JSONObject(raw)) }.getOrNull() } })
            if (player.isPlaying) {
                loadingDeadline?.cancel()
                if (track != null && track.id != recordedId) { recordedId = track.id; save { app.library.record(track) } }
            }
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
    fun play(requested: Track, context: List<Track> = listOf(requested)) = viewModelScope.launch {
        try {
            val player = connected.await()
            var track = requested
            if (track.source == "reference") {
                mutablePlayback.update { it.copy(loading = true, error = null) }
                app.library.add(listOf(track))
                track = try { withContext(Dispatchers.IO) { app.api.match(requested).copy(id = requested.id) } }
                catch (e: Exception) { if (e is CancellationException) throw e; matchReference.value = requested; mutablePlayback.update { it.copy(loading = false) }; return@launch }
                app.library.replaceSource(requested, track)
            }
            var queue = context.ifEmpty { listOf(track) }.map { if (it.id == requested.id) track else it }.distinctBy { it.identity }
            app.library.add(queue)
            queue = queue.map { app.library.state.value.byIdentity[it.identity] ?: it }
            track = app.library.state.value.byIdentity[track.identity] ?: track
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
            val seconds = if (library.value.sourceMode in listOf("auto", "youtubei")) 50 else 20
            delay(seconds * 1000L)
            if (controller?.isPlaying != true) { controller?.stop(); mutablePlayback.update { it.copy(loading = false, playing = false, error = "Le chargement a dépassé $seconds secondes. Réessaie ou change de source audio.") } }
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
    fun relay(address: String, key: String) = save {
        if (address.isBlank()) app.library.update { it.copy(relayAddress = "", relayDisabled = true) }
        else {
            val server = MusicApi.validateInstance(address)
            require(key.length >= 24) { "La clé doit contenir au moins 24 caractères" }
            app.library.relayCredentials.save(key, server)
            app.library.update { it.copy(relayAddress = server, relayDisabled = false) }
        }
        message.value = "Réglage du relais enregistré"
    }
    private fun applyAudio() { val s = library.value; controller?.playbackParameters = PlaybackParameters(s.speed, s.pitchRatio) }
    fun settings(change: (LibraryState) -> LibraryState) = save { app.library.update(change) }
    fun pitch(semitones: Float) = settings { it.copy(pitchSemitones = semitones.coerceIn(-12f, 12f), speed = if (it.linkedPitch) Math.pow(2.0, semitones / 12.0).toFloat().coerceIn(.5f, 2f) else it.speed) }
    fun enqueue(track: Track, next: Boolean) = viewModelScope.launch {
        app.library.add(listOf(track)); val p = connected.await()
        val existing = (0 until p.mediaItemCount).firstOrNull { p.getMediaItemAt(it).mediaId == track.id }
        if (existing == p.currentMediaItemIndex) return@launch
        existing?.let(p::removeMediaItem)
        p.addMediaItem(if (next) (p.currentMediaItemIndex + 1).coerceAtLeast(0) else p.mediaItemCount, track.mediaItem())
        message.value = if (next) "À écouter juste après" else "Ajouté à la file"
    }
    fun removeQueue(index: Int) { controller?.takeIf { index in 0 until it.mediaItemCount }?.removeMediaItem(index) }
    fun moveQueue(index: Int, direction: Int) { controller?.let { if (index in 0 until it.mediaItemCount && index + direction in 0 until it.mediaItemCount) it.moveMediaItem(index, index + direction) } }
    fun clearQueue() { controller?.let { val item = it.currentMediaItem ?: return; val position = it.currentPosition; it.setMediaItems(listOf(item), 0, position) } }
    fun sleep(minutes: Int?) { engine.value = engine.value.copy(sleepDeadline = minutes?.let { System.currentTimeMillis() + it * 60_000L }, stopAtEnd = false) }
    fun stopAtEnd() { engine.value = engine.value.copy(stopAtEnd = !engine.value.stopAtEnd, sleepDeadline = null) }
    fun loop() {
        val e = engine.value; val position = controller?.currentPosition ?: return
        engine.value = when { e.loopA == null -> e.copy(loopA = position); e.loopB == null && position > e.loopA -> e.copy(loopB = position); else -> e.copy(loopA = null, loopB = null) }
    }
    fun follow(artist: MusicArtist) = save { app.library.follow(artist) }
    fun searchArtists(query: String) { searchJob?.cancel(); searchJob = viewModelScope.launch { try { delay(400); artistResults.value = withContext(Dispatchers.IO) { app.api.artists(query) } } catch (e: Exception) { if (e !is CancellationException) searchError.value = e.localizedMessage } } }
    fun openArtist(artist: MusicArtist) = viewModelScope.launch {
        artistLoading.value = true; artistProfile.value = ArtistProfile(artist, "", emptyList())
        try { artistProfile.value = withContext(Dispatchers.IO) { app.api.artist(artist) } } catch (e: Exception) { if (e !is CancellationException) message.value = e.localizedMessage } finally { artistLoading.value = false }
    }
    fun importDocument(uri: Uri) = save { message.value = app.library.importDocument(uri) }
    fun export(uri: Uri) = save { app.library.export(uri); message.value = "Sauvegarde exportée" }
    fun importLyrics(uri: Uri, track: Track) = save { app.library.importLyrics(uri, track); message.value = "Paroles enregistrées" }
    fun importRemote(address: String) = save { val result = app.api.importRemote(address, library.value.instance); app.library.importPlaylist(result.first, result.second); message.value = "${result.second.size} titres importés" }
    fun editPlaylist(id: String, name: String? = null, removeTrack: String? = null, delete: Boolean = false) = save { app.library.editPlaylist(id, name, removeTrack, delete) }
    fun removeTrack(track: Track) = save { withContext(Dispatchers.Main) { controller?.let { p -> for (i in p.mediaItemCount - 1 downTo 0) if (p.getMediaItemAt(i).mediaId == track.id) p.removeMediaItem(i) } }; app.library.remove(track) }
    fun associate(reference: Track, selected: Track) = save { val replacement = selected.copy(id = reference.id); app.library.replaceSource(reference, replacement); matchReference.value = null; withContext(Dispatchers.Main) { play(replacement, listOf(replacement)) } }
    suspend fun lyrics(track: Track): String? = withContext(Dispatchers.IO) {
        val text = app.api.lyrics(track)
        if (!text.isNullOrBlank()) { app.library.add(listOf(track)); app.library.cacheLyrics(track, text) }
        text
    }
    private fun save(block: suspend () -> Unit) = viewModelScope.launch(Dispatchers.IO) { try { block() } catch (e: Exception) { if (e !is CancellationException) message.value = e.localizedMessage } }
    override fun onCleared() { controller?.removeListener(listener); controller?.release(); super.onCleared() }
}
