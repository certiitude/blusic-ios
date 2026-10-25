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
    }
    suspend fun update(change: (LibraryState) -> LibraryState) {
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
            Track(title = name.substringBeforeLast('.'), artist = "Fichiers importés", source = "local", location = uri.toString())
        }
        add(imported)
    }
    fun isFavorite(track: Track): Boolean = state.value.tracks.firstOrNull { it.identity == track.identity }?.id in state.value.favorites
}
