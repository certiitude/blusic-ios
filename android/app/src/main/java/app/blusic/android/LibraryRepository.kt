package app.blusic.android

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.util.AtomicFile
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.File

class LibraryRepository(private val context: Context) {
    val relayCredentials = RelayCredentials(context)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val lock = Mutex()
    private val file = AtomicFile(File(context.filesDir, "library.json"))
    private val mutable = MutableStateFlow(LibraryState())
    val state = mutable.asStateFlow()
    val error = MutableStateFlow<String?>(null)
    val ready = scope.async {
        try { if (file.baseFile.exists()) mutable.value = LibraryState.parse(file.openRead().bufferedReader().use { it.readText() }) }
        catch (e: Exception) { error.value = "Bibliothèque illisible, fichier conservé : ${e.localizedMessage}" }
        installBundledRelay()
    }
    private fun installBundledRelay() {
        runCatching {
            val bundled = org.json.JSONObject(context.assets.open("bundled-relay.json").bufferedReader().use { it.readText() })
            val old = mutable.value; val revision = bundled.getString("revision"); val address = bundled.getString("url")
            if (old.relayRevision != revision && !old.relayDisabled && (old.relayAddress.isBlank() || old.relayAddress == address)) {
                val access = bundled.getString("access")
                require(access.matches(Regex("app\\.android\\.[a-f0-9]{64}")) && bundled.getLong("expiresAt") == 0L)
                relayCredentials.save(access, address)
                mutable.value = old.copy(relayAddress = address, relayRevision = revision)
            }
        }.onFailure { if (it !is java.io.FileNotFoundException) error.value = "Configuration du relais : ${it.localizedMessage}" }
    }
    suspend fun update(change: (LibraryState) -> LibraryState) = withContext(Dispatchers.IO) {
        ready.await()
        lock.withLock {
            val next = change(mutable.value)
            val stream = file.startWrite()
            try { stream.write(next.json().toString().toByteArray()); file.finishWrite(stream); mutable.value = next }
            catch (e: Exception) { file.failWrite(stream); throw e }
        }
    }
    suspend fun add(tracks: List<Track>) {
        update { old ->
            val identities = old.tracks.map { it.identity }.toMutableSet()
            old.copy(tracks = old.tracks + tracks.filter { identities.add(it.identity) })
        }
    }
    suspend fun favorite(track: Track) {
        add(listOf(track))
        update { old ->
            val id = old.tracks.first { it.identity == track.identity }.id
            old.copy(favorites = if (id in old.favorites) old.favorites - id else old.favorites + id)
        }
    }
    suspend fun record(track: Track) {
        add(listOf(track))
        update { old -> val id = old.tracks.first { it.identity == track.identity }.id; old.copy(recent = (listOf(id) + old.recent.filterNot { it == id }).take(200)) }
    }
    suspend fun createPlaylist(name: String) = update { it.copy(playlists = it.playlists + Playlist(name = name.trim())) }
    suspend fun addToPlaylist(track: Track, id: String) {
        add(listOf(track))
        update { old ->
            val saved = old.tracks.first { it.identity == track.identity }.id
            old.copy(playlists = old.playlists.map { if (it.id == id) it.copy(tracks = (it.tracks + saved).distinct()) else it })
        }
    }
    suspend fun cacheLyrics(track: Track, text: String) = update { old -> old.copy(tracks = old.tracks.map { if (it.identity == track.identity) it.copy(lyrics = text) else it }) }
    suspend fun importAudio(uris: List<Uri>) = withContext(Dispatchers.IO) {
        val imported = uris.map { uri ->
            val name = context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else "Audio importé"
            } ?: "Audio importé"
            // Keep the user's document in its chosen location through a persisted grant.
            try { context.contentResolver.takePersistableUriPermission(uri, android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch (_: SecurityException) { }
            val reader = android.media.MediaMetadataRetriever()
            try {
                reader.setDataSource(context, uri)
                var cover: String? = null
                reader.embeddedPicture?.takeIf { it.size <= 16_000_000 }?.let { bytes ->
                    val bounds = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                    val options = android.graphics.BitmapFactory.Options().apply { inSampleSize = (maxOf(bounds.outWidth, bounds.outHeight) / 512).coerceAtLeast(1) }
                    android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)?.let { bitmap ->
                        val directory = File(context.filesDir, "ImportedArtwork").apply { mkdirs() }; val target = File(directory, "${java.util.UUID.randomUUID()}.jpg")
                        target.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 90, it) }; bitmap.recycle(); cover = target.toURI().toString()
                    }
                }
                Track(title = reader.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_TITLE)?.takeIf(String::isNotBlank) ?: name.substringBeforeLast('.'),
                    artist = reader.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_ARTIST).orEmpty().ifBlank { "Fichiers importés" },
                    album = reader.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_ALBUM).orEmpty(), duration = reader.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0,
                    source = "local", location = uri.toString(), artworkUrl = cover)
            } catch (_: Exception) { Track(title = name.substringBeforeLast('.'), artist = "Fichiers importés", source = "local", location = uri.toString()) }
            finally { reader.release() }
        }
        add(imported)
    }
    fun isFavorite(track: Track): Boolean = state.value.tracks.firstOrNull { it.identity == track.identity }?.id in state.value.favorites
    suspend fun follow(artist: MusicArtist) = update { old -> old.copy(followedArtists = if (old.followedArtists.any { it.id == artist.id }) old.followedArtists.filterNot { it.id == artist.id } else old.followedArtists + artist) }
    suspend fun listening(track: Track, seconds: Double) = update { old ->
        if (seconds <= 0 || seconds > 15) old else {
            val last = old.history.lastOrNull(); val now = System.currentTimeMillis()
            val events = if (last?.trackId == track.id && now - last.date < 86_400_000) old.history.dropLast(1) + last.copy(seconds = last.seconds + seconds)
                else old.history + ListeningEvent(track.id, now, seconds)
            old.copy(history = events.takeLast(20000))
        }
    }
    suspend fun saveQueue(tracks: List<Track>, current: String?) {
        add(tracks)
        update { if (it.savedQueue == tracks.map(Track::id) && it.savedCurrent == current) it else it.copy(savedQueue = tracks.map(Track::id), savedCurrent = current) }
    }
    suspend fun replaceSource(reference: Track, matched: Track) = update { old -> old.copy(tracks = old.tracks.map {
        if (it.id == reference.id) matched.copy(id = it.id, lyrics = it.lyrics ?: matched.lyrics) else it
    }) }
    suspend fun remove(track: Track) = update { old -> old.copy(tracks = old.tracks.filterNot { it.id == track.id }, favorites = old.favorites - track.id,
        playlists = old.playlists.map { it.copy(tracks = it.tracks - track.id) }, savedQueue = old.savedQueue - track.id, recent = old.recent - track.id) }
    suspend fun editPlaylist(id: String, name: String? = null, removeTrack: String? = null, delete: Boolean = false) = update { old ->
        old.copy(playlists = if (delete) old.playlists.filterNot { it.id == id } else old.playlists.map { p -> if (p.id == id) p.copy(name = name?.trim()?.takeIf(String::isNotBlank) ?: p.name, tracks = removeTrack?.let { p.tracks - it } ?: p.tracks) else p })
    }
    suspend fun importPlaylist(name: String, tracks: List<Track>) { add(tracks); update { old -> old.copy(playlists = old.playlists + Playlist(name = name, tracks = tracks.mapNotNull { old.byIdentity[it.identity]?.id }.distinct())) } }
    suspend fun importDocument(uri: Uri): String = withContext(Dispatchers.IO) {
        val name = context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { if (it.moveToFirst()) it.getString(0) else null } ?: "Playlist importée"
        val text = context.contentResolver.openInputStream(uri)?.use { input ->
            val bytes = input.readNBytesCompat(12_000_001); require(bytes.size <= 12_000_000) { "Document trop volumineux" }; String(bytes, Charsets.UTF_8)
        } ?: kotlin.error("Document illisible")
        if (name.endsWith(".json", true) && org.json.JSONObject(text).has("favorites")) {
            val restored = PlaylistImports.restore(text); update { restored }; "Bibliothèque restaurée"
        } else { val tracks = PlaylistImports.parse(text, name); require(tracks.isNotEmpty()) { "Aucun titre importable" }; importPlaylist(name.substringBeforeLast('.'), tracks); "${tracks.size} titres importés" }
    }
    suspend fun export(uri: Uri) = withContext(Dispatchers.IO) { ready.await(); context.contentResolver.openOutputStream(uri)?.use { it.write(state.value.json().toString(2).toByteArray()) } ?: kotlin.error("Export impossible") }
    suspend fun importLyrics(uri: Uri, track: Track) = withContext(Dispatchers.IO) {
        val text = context.contentResolver.openInputStream(uri)?.use { String(it.readNBytesCompat(1_000_001), Charsets.UTF_8) } ?: kotlin.error("Paroles illisibles")
        require(text.length <= 1_000_000) { "Paroles trop volumineuses" }; add(listOf(track)); cacheLyrics(track, text)
    }
}
