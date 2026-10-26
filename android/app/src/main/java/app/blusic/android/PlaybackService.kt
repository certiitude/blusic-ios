package app.blusic.android

import android.app.Application
import android.app.PendingIntent
import android.content.Intent
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.net.Uri
import androidx.media3.common.*
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.source.ShuffleOrder
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import java.util.concurrent.ConcurrentHashMap
import coil.ImageLoader
import coil.ImageLoaderFactory
import coil.memory.MemoryCache
import coil.disk.DiskCache
import java.io.File

data class EngineState(val preparation: String? = null, val transitioning: Boolean = false, val overlapping: Int = 0,
    val format: String = "", val firstAudioMs: Long? = null, val sleepDeadline: Long? = null, val stopAtEnd: Boolean = false,
    val loopA: Long? = null, val loopB: Long? = null)

class BlusicApplication : Application(), ImageLoaderFactory {
    override fun newImageLoader(): ImageLoader = ImageLoader.Builder(this)
        .memoryCache { MemoryCache.Builder(this).maxSizeBytes(minOf(48L * 1024 * 1024, Runtime.getRuntime().maxMemory() / 8).toInt()).build() }
        .diskCache { DiskCache.Builder().directory(File(cacheDir, "artwork-hd-v2")).maxSizeBytes(80L * 1024 * 1024).build() }.build()
    val library by lazy { LibraryRepository(this) }
    val nativeResolver by lazy { NativeYouTubeiResolver(this) }
    val api by lazy { MusicApi(nativeResolver = { video, settings -> nativeResolver.resolve(video, settings.highQuality) }) }
    val prepared by lazy { PreparedAudioRepository(this, api) }
    val engineState = MutableStateFlow(EngineState())
    val streamInfo = ConcurrentHashMap<String, AudioStream>()
    var playbackEngine: PlaybackService? = null
}

@androidx.annotation.OptIn(UnstableApi::class)
class PlaybackService : MediaSessionService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val app get() = application as BlusicApplication
    private var session: MediaSession? = null
    private lateinit var main: ExoPlayer
    private lateinit var standby: ExoPlayer
    private var outgoing: ExoPlayer? = null
    private var preparation: Deferred<AudioStream>? = null
    private var preparationKey: String? = null
    private var plannedIndex = -1
    private var fade: Job? = null
    private var transitionStarting = false
    private var settingsKey = ""
    private var startedAt = 0L
    private var firstAudio: Long? = null
    private var activeTrackId: String? = null
    private var listeningTrack: Track? = null
    private var pendingAdvance: Job? = null
    private var tickAt = 0L
    private var listening = 0.0
    private var shuffleSeed = 261026L
    private var queueSignature = emptyList<String>()
    private var focusResume = false
    private var cachedItem: MediaItem? = null
    private var cachedTrack: Track? = null
    private var appliedSound: Triple<Float, Float, Float>? = null
    private val manager by lazy { getSystemService(AudioManager::class.java) }
    private val focus by lazy { AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
        .setAudioAttributes(android.media.AudioAttributes.Builder().setUsage(android.media.AudioAttributes.USAGE_MEDIA).setContentType(android.media.AudioAttributes.CONTENT_TYPE_MUSIC).build())
        .setOnAudioFocusChangeListener { change ->
            when (change) {
                AudioManager.AUDIOFOCUS_LOSS, AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> { focusResume = change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT && main.playWhenReady; main.pause(); cancelTransition() }
                AudioManager.AUDIOFOCUS_GAIN -> { main.volume = app.library.state.value.volume; if (focusResume) { focusResume = false; main.play() } }
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> { main.volume = app.library.state.value.volume * .2f; outgoing?.volume = 0f }
            }
        }.build() }

    override fun onCreate() {
        super.onCreate(); app.playbackEngine = this
        main = buildPlayer(); standby = buildPlayer()
        val activity = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        session = MediaSession.Builder(this, controllerPlayer(main)).setSessionActivity(activity).build()
        scope.launch {
            app.library.ready.await()
            val s = app.library.state.value
            if (s.restoreQueue && main.mediaItemCount == 0) {
                val queue = s.savedQueue.mapNotNull { s.byId[it] }
                if (queue.isNotEmpty()) main.setMediaItems(queue.map(Track::mediaItem), queue.indexOfFirst { it.id == s.savedCurrent }.coerceAtLeast(0), 0)
            }
            app.library.state.collect { settings ->
                if (settingsKey != settings.resolutionKey) { settingsKey = settings.resolutionKey; invalidatePreparation() }
                val sound = Triple(settings.speed, settings.pitchRatio, settings.volume)
                if (appliedSound != sound) {
                    for (player in listOf(main, standby)) player.playbackParameters = PlaybackParameters(settings.speed, settings.pitchRatio)
                    if (fade == null) main.volume = settings.volume
                    appliedSound = sound
                }
                if (!settings.crossfade && (outgoing != null || transitionStarting)) cancelTransition()
            }
        }
        scope.launch { while (isActive) { tick(); delay(100) } }
    }
    private fun buildPlayer(): ExoPlayer {
        val network = DefaultDataSource.Factory(this, FiniteHttpDataSource.Factory(app.api.client))
        val resolving = ResolvingDataSource.Factory(network) { spec ->
            if (spec.uri.scheme !in listOf("blusic", "blusic-reference")) spec else {
                var video = spec.uri.host ?: error("Identifiant absent")
                val stream = runBlocking(Dispatchers.IO) {
                    app.library.ready.await(); val s = app.library.state.value
                    var track = if (spec.uri.scheme == "blusic-reference") s.byId[spec.uri.lastPathSegment] ?: error("Référence absente") else s.tracks.firstOrNull { it.location == video } ?: Track(title = "Audio", artist = "", location = video)
                    if (track.source == "reference") { val reference = track; track = app.api.match(reference).copy(id = reference.id); app.library.replaceSource(reference, track); video = track.location }
                    app.prepared.cached(track, s) ?: app.api.resolve(video, s, app.library.relayCredentials.read(s.relayAddress))
                }
                app.streamInfo[video] = stream
                spec.withUri(Uri.parse(stream.url))
            }
        }
        val renderers = object : DefaultRenderersFactory(this) {
            override fun buildAudioSink(context: android.content.Context, enableFloatOutput: Boolean, enableAudioTrackPlaybackParams: Boolean): AudioSink =
                DefaultAudioSink.Builder(context).setAudioProcessors(arrayOf(EqualizerAudioProcessor { app.library.state.value })).build()
        }
        val player = ExoPlayer.Builder(this, renderers).setMediaSourceFactory(DefaultMediaSourceFactory(resolving).setLoadErrorHandlingPolicy(DefaultLoadErrorHandlingPolicy(1))).build()
        player.setAudioAttributes(AudioAttributes.Builder().setContentType(C.AUDIO_CONTENT_TYPE_MUSIC).setUsage(C.USAGE_MEDIA).build(), false)
        player.setHandleAudioBecomingNoisy(true); player.setWakeMode(C.WAKE_MODE_LOCAL)
        player.addListener(object : Player.Listener {
            override fun onEvents(p: Player, events: Player.Events) {
                if (!::main.isInitialized || p !== main) return
                val track = currentTrack()
                if (track?.id != activeTrackId) {
                    flushListening(); activeTrackId = track?.id; listeningTrack = track; startedAt = android.os.SystemClock.elapsedRealtime(); firstAudio = null
                    if (!transitionStarting && outgoing == null) invalidatePreparation()
                    app.engineState.value = app.engineState.value.copy(loopA = null, loopB = null, firstAudioMs = null)
                    track?.let { scope.launch(Dispatchers.IO) { app.library.record(it) } }
                    persistQueue()
                }
                if (p.playWhenReady && events.contains(Player.EVENT_PLAY_WHEN_READY_CHANGED)) manager.requestAudioFocus(focus)
                else if (!p.playWhenReady) { flushListening(); cancelTransition(); invalidatePreparation() }
                if (events.contains(Player.EVENT_TIMELINE_CHANGED)) {
                    val ids = (0 until main.mediaItemCount).map { main.getMediaItemAt(it).mediaId }
                    if (ids != queueSignature) {
                        queueSignature = ids
                        invalidatePreparation(); shuffleSeed += 1; main.setShuffleOrder(ShuffleOrder.DefaultShuffleOrder(main.mediaItemCount, shuffleSeed)); persistQueue()
                    }
                }
                if (events.contains(Player.EVENT_SHUFFLE_MODE_ENABLED_CHANGED) || events.contains(Player.EVENT_REPEAT_MODE_CHANGED)) invalidatePreparation()
                if (p.playbackState == Player.STATE_ENDED) { flushListening(); if (app.engineState.value.stopAtEnd) app.engineState.value = app.engineState.value.copy(stopAtEnd = false) }
            }
            override fun onPlayerError(error: PlaybackException) { if (::main.isInitialized && player === main) { currentTrack()?.let { app.api.invalidate(it.location) }; cancelTransition() } }
        })
        return player
    }
    private fun controllerPlayer(player: ExoPlayer): Player = object : ForwardingPlayer(player) {
        override fun seekToNextMediaItem() { advance() }
        override fun seekToNext() { advance() }
        override fun pause() { player.pause(); cancelTransition(); invalidatePreparation() }
        override fun stop() { player.stop(); cancelTransition(); invalidatePreparation() }
    }
    private fun currentTrack(): Track? {
        val item = main.currentMediaItem
        if (item !== cachedItem) { cachedItem = item; cachedTrack = item?.mediaMetadata?.extras?.getString("track")?.let { runCatching { Track.fromJson(org.json.JSONObject(it)) }.getOrNull() } }
        return cachedTrack
    }
    private fun persistQueue() {
        val tracks = (0 until main.mediaItemCount).mapNotNull { index -> main.getMediaItemAt(index).mediaMetadata.extras?.getString("track")?.let { runCatching { Track.fromJson(org.json.JSONObject(it)) }.getOrNull() } }
        val current = currentTrack()?.id
        scope.launch(Dispatchers.IO) { app.library.saveQueue(tracks, current) }
    }
    private fun invalidatePreparation() {
        pendingAdvance?.cancel(); pendingAdvance = null
        preparation?.cancel(); preparation = null; preparationKey = null; plannedIndex = -1
        if (::standby.isInitialized && standby !== outgoing) { standby.stop(); standby.clearMediaItems() }
        app.engineState.value = app.engineState.value.copy(preparation = null)
    }
    private fun prepareNext() {
        if (preparationKey != null || outgoing != null || transitionStarting || app.engineState.value.stopAtEnd || app.engineState.value.loopB != null || main.repeatMode == Player.REPEAT_MODE_ONE) return
        val index = main.nextMediaItemIndex; if (index == C.INDEX_UNSET || index == main.currentMediaItemIndex) return
        val item = main.getMediaItemAt(index); val track = item.mediaMetadata.extras?.getString("track")?.let { Track.fromJson(org.json.JSONObject(it)) } ?: return
        val settings = app.library.state.value; val key = "${track.identity}|${settings.resolutionKey}"
        preparationKey = key; plannedIndex = index
        app.engineState.value = app.engineState.value.copy(preparation = "Préparation du titre suivant…")
        val task = scope.async(Dispatchers.IO) { PreparationRetry.run(operation = { withTimeout(35_000) {
            val effective = if (track.source == "reference") app.api.match(track).copy(id = track.id).also { app.library.replaceSource(track, it) } else track
            app.prepared.prepare(effective, settings, app.library.relayCredentials.read(settings.relayAddress))
        } }, onRetry = { count, wait ->
            app.api.invalidate(track.location)
            withContext(Dispatchers.Main) { if (preparationKey == key) app.engineState.value = app.engineState.value.copy(preparation = "Préchargement : nouvel essai ${count + 1} dans ${wait / 1000} s…") }
        }) }
        preparation = task
        scope.launch {
            try {
                val audio = task.await(); if (preparationKey != key) return@launch
                val items = (0 until main.mediaItemCount).map { main.getMediaItemAt(it) }.toMutableList()
                val effective = app.library.state.value.byId[track.id] ?: track
                items[index] = effective.mediaItem().buildUpon().setUri(audio.url).build()
                standby.setMediaItems(items, index, 0); standby.setShuffleOrder(ShuffleOrder.DefaultShuffleOrder(items.size, shuffleSeed))
                standby.shuffleModeEnabled = main.shuffleModeEnabled; standby.repeatMode = main.repeatMode
                standby.playbackParameters = PlaybackParameters(settings.speed, settings.pitchRatio); standby.volume = 0f; standby.prepare()
                app.streamInfo[track.location] = audio
                app.engineState.value = app.engineState.value.copy(preparation = "Titre suivant préchargé")
            } catch (e: Exception) { if (e !is CancellationException && preparationKey == key) app.engineState.value = app.engineState.value.copy(preparation = "Le titre suivant n’a pas pu être préchargé") }
        }
    }
    fun advance() {
        if (outgoing != null || transitionStarting) cancelTransition()
        if (!transitionStarting && outgoing == null && standby.mediaItemCount > 0 && plannedIndex == main.nextMediaItemIndex && standby.playbackState == Player.STATE_READY) beginTransition()
        else if (!transitionStarting && outgoing == null && plannedIndex == main.nextMediaItemIndex && preparation != null) {
            if (pendingAdvance?.isActive == true) return
            val key = preparationKey; val task = preparation!!
            pendingAdvance = scope.launch {
                try { task.await(); repeat(30) { if (standby.playbackState == Player.STATE_READY || preparationKey != key) return@repeat; delay(20) }
                    if (preparationKey == key && standby.playbackState == Player.STATE_READY) beginTransition()
                } catch (e: Exception) { if (e !is CancellationException) { invalidatePreparation(); main.seekToNextMediaItem(); main.play() } }
            }
        }
        else { invalidatePreparation(); main.seekToNextMediaItem(); main.play() }
    }
    private fun beginTransition() {
        if (transitionStarting || outgoing != null) return
        transitionStarting = true
        val old = main; val incoming = standby; val s = app.library.state.value
        scope.launch {
            incoming.volume = 0f; incoming.play()
            val deadline = android.os.SystemClock.elapsedRealtime() + 2500
            while (incoming.currentPosition <= 20 && incoming.playerError == null && old.playWhenReady && android.os.SystemClock.elapsedRealtime() < deadline) delay(20)
            if (!old.playWhenReady || incoming.playerError != null || incoming.currentPosition <= 20) { incoming.pause(); transitionStarting = false; return@launch }
            flushListening(); main = incoming; standby = old; outgoing = old
            session?.setPlayer(controllerPlayer(main)); preparation = null; preparationKey = null; plannedIndex = -1
            activeTrackId = currentTrack()?.id; listeningTrack = currentTrack(); firstAudio = 0; startedAt = android.os.SystemClock.elapsedRealtime()
            currentTrack()?.let { scope.launch(Dispatchers.IO) { app.library.record(it) } }; persistQueue()
            val duration = if (s.crossfade) minOf((s.crossfadeSeconds * 1000).toLong(), ((old.duration - old.currentPosition).coerceAtLeast(150) / s.speed).toLong()) else 0L
            app.engineState.value = app.engineState.value.copy(transitioning = duration > 0, preparation = null, firstAudioMs = 0)
            transitionStarting = false
            fade = scope.launch {
                val start = android.os.SystemClock.elapsedRealtime()
                try {
                    while (true) {
                        val fraction = if (duration == 0L) 1f else ((android.os.SystemClock.elapsedRealtime() - start).toFloat() / duration).coerceIn(0f, 1f)
                        main.volume = app.library.state.value.volume * fraction; old.volume = app.library.state.value.volume * (1 - fraction)
                        if (fraction >= 1) break; delay(20)
                    }
                } finally { old.pause(); old.stop(); old.clearMediaItems(); outgoing = null; main.volume = app.library.state.value.volume; fade = null; app.engineState.value = app.engineState.value.copy(transitioning = false) }
            }
        }
    }
    private fun cancelTransition() { fade?.cancel(); fade = null; outgoing?.pause(); outgoing = null; transitionStarting = false; if (::standby.isInitialized) standby.pause(); if (::main.isInitialized) main.volume = app.library.state.value.volume; app.engineState.value = app.engineState.value.copy(transitioning = false) }
    private fun flushListening() { val seconds = listening; listening = 0.0; val track = listeningTrack ?: return; if (seconds > 0) app.library.listeningAsync(track, seconds) }
    private fun tick() {
        if (!::main.isInitialized) return
        val now = android.os.SystemClock.elapsedRealtime(); val elapsed = if (tickAt > 0) (now - tickAt) / 1000.0 else 0.0; tickAt = now
        var runtime = app.engineState.value
        if ((runtime.stopAtEnd || runtime.loopB != null) && preparationKey != null) invalidatePreparation()
        if (runtime.sleepDeadline?.let { System.currentTimeMillis() >= it } == true) { main.pause(); cancelTransition(); runtime = runtime.copy(sleepDeadline = null); app.engineState.value = runtime }
        if (main.isPlaying) {
            if (elapsed in 0.0..1.0) listening += elapsed
            if (listening >= 5) flushListening()
            if (firstAudio == null && main.currentPosition > 50) firstAudio = now - startedAt
            val s = app.library.state.value
            val duration = currentTrack()?.duration?.takeIf { it > 0 } ?: main.duration
            val remaining = (duration - main.currentPosition) / s.speed
            if (runtime.loopA != null && runtime.loopB != null && main.currentPosition >= runtime.loopB) main.seekTo(runtime.loopA)
            if (runtime.stopAtEnd && duration > 0 && remaining <= 150) { main.pause(); main.seekTo(duration); app.engineState.value = runtime.copy(stopAtEnd = false) }
            else if (firstAudio != null && QueuePreparationPolicy.shouldStart(duration, main.currentPosition, s.speed)) {
                prepareNext()
                if (s.crossfade && main.repeatMode != Player.REPEAT_MODE_ONE && runtime.loopB == null && remaining <= s.crossfadeSeconds * 1000 && standby.playbackState == Player.STATE_READY && standby.mediaItemCount > 0) beginTransition()
            }
        }
        val track = currentTrack(); val info = track?.let { app.streamInfo[it.location] }
        val format = if (info != null) "AAC${if (info.bitrate > 0) " · ${kotlin.math.round(info.bitrate / 1000.0).toInt()} kbit/s" else ""} · ${info.provider}" else if (track?.source == "bundled") "PCM · sans perte · 44,1 kHz" else "Audio natif"
        val next = app.engineState.value.copy(overlapping = (if (main.isPlaying) 1 else 0) + (if (outgoing?.isPlaying == true) 1 else 0), format = format, firstAudioMs = firstAudio)
        if (next != app.engineState.value) app.engineState.value = next
    }
    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session
    override fun onDestroy() {
        flushListening(); preparation?.cancel(); cancelTransition(); scope.cancel(); manager.abandonAudioFocusRequest(focus)
        session?.release(); if (::main.isInitialized) main.release(); if (::standby.isInitialized) standby.release()
        app.playbackEngine = null; session = null; super.onDestroy()
    }
}

fun Track.mediaItem(): MediaItem {
    val uri = when (source) { "bundled" -> "asset:///$location"; "local", "remote" -> location; "reference" -> "blusic-reference://resolve/${Uri.encode(id)}"; else -> "blusic://$location" }
    val extras = android.os.Bundle().apply { putString("track", json().toString()) }
    return MediaItem.Builder().setMediaId(id).setUri(uri).setMediaMetadata(MediaMetadata.Builder().setTitle(title)
        .setArtist(artist).setAlbumTitle(album).setArtworkUri(artworkUrl?.let(Uri::parse)).setExtras(extras).build()).build()
}
