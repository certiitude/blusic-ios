package app.blusic.android

import android.app.Application
import android.app.PendingIntent
import android.content.Intent
import android.net.Uri
import androidx.media3.common.*
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import kotlinx.coroutines.runBlocking

class BlusicApplication : Application() {
    val library by lazy { LibraryRepository(this) }
    val api by lazy { MusicApi() }
}

@androidx.annotation.OptIn(UnstableApi::class)
class PlaybackService : MediaSessionService() {
    private var session: MediaSession? = null
    override fun onCreate() {
        super.onCreate()
        val app = application as BlusicApplication
        val network = DefaultDataSource.Factory(this, FiniteHttpDataSource.Factory(app.api.client))
        val resolving = ResolvingDataSource.Factory(network) { spec ->
            if (spec.uri.scheme == "blusic") {
                val id = spec.uri.host ?: throw java.io.IOException("Identifiant absent")
                val stream = runBlocking {
                    app.library.ready.await()
                    val settings = app.library.state.value
                    app.api.resolve(id, settings, app.library.relayCredentials.read(settings.relayAddress))
                }
                spec.withUri(Uri.parse(stream.url))
            } else spec
        }
        val player = ExoPlayer.Builder(this).setMediaSourceFactory(DefaultMediaSourceFactory(resolving)
            .setLoadErrorHandlingPolicy(DefaultLoadErrorHandlingPolicy(1))).build().apply {
            setAudioAttributes(AudioAttributes.Builder().setContentType(C.AUDIO_CONTENT_TYPE_MUSIC).setUsage(C.USAGE_MEDIA).build(), true)
            setHandleAudioBecomingNoisy(true)
            setWakeMode(C.WAKE_MODE_LOCAL)
            addListener(object : Player.Listener {
                override fun onPlayerError(error: PlaybackException) {
                    currentMediaItem?.localConfiguration?.uri?.takeIf { it.scheme == "blusic" }?.host?.let(app.api::invalidate)
                }
            })
        }
        val activity = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        session = MediaSession.Builder(this, player).setSessionActivity(activity).build()
    }
    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session
    override fun onDestroy() { session?.run { player.release(); release() }; session = null; super.onDestroy() }
}

fun Track.mediaItem(): MediaItem {
    val uri = when (source) { "bundled" -> "asset:///$location"; "local" -> location; else -> "blusic://$location" }
    val extras = android.os.Bundle().apply { putString("track", json().toString()) }
    return MediaItem.Builder().setMediaId(id).setUri(uri).setMediaMetadata(MediaMetadata.Builder().setTitle(title)
        .setArtist(artist).setAlbumTitle(album).setArtworkUri(artworkUrl?.let(Uri::parse)).setExtras(extras).build()).build()
}
