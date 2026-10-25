package app.blusic.android

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import coil.request.ImageRequest
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private val Ink = Color(0xFF09090B)
private val Panel = Color(0xFF18181E)
private val Accent = Color(0xFFAD93FF)
private val Muted = Color(0xFF9999A6)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MaterialTheme(colorScheme = darkColorScheme(primary = Accent, background = Ink, surface = Panel, onSurface = Color.White)) {
                BlusicApp()
            }
        }
    }
}

@Composable
fun BlusicApp(vm: BlusicViewModel = viewModel()) {
    val library by vm.library.collectAsStateWithLifecycle()
    val playback by vm.playback.collectAsStateWithLifecycle()
    val message by vm.message.collectAsStateWithLifecycle()
    val libraryError by vm.libraryError.collectAsStateWithLifecycle()
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var showPlayer by rememberSaveable { mutableStateOf(false) }
    var showSettings by rememberSaveable { mutableStateOf(false) }
    var selection by remember { mutableStateOf<Playlist?>(null) }
    val context = LocalContext.current
    val notifications = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {}
    LaunchedEffect(Unit) { if (Build.VERSION.SDK_INT >= 33) notifications.launch(Manifest.permission.POST_NOTIFICATIONS) }
    val snackbar = remember { SnackbarHostState() }
    LaunchedEffect(message) { message?.let { snackbar.showSnackbar(it); vm.message.value = null } }
    LaunchedEffect(libraryError) { libraryError?.let { snackbar.showSnackbar(it) } }
    BackHandler(showSettings || selection != null) { showSettings = false; selection = null }
    Scaffold(containerColor = Ink, snackbarHost = { SnackbarHost(snackbar) }, topBar = {
        Row(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 20.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("●", color = Color.White, fontSize = 26.sp)
            Text(" blusic", fontSize = 29.sp, fontWeight = FontWeight.Bold, letterSpacing = (-1).sp)
            Spacer(Modifier.weight(1f))
            Action(Icons.Rounded.Tune, "Réglages", { showSettings = !showSettings })
        }
    }, bottomBar = {
        Column(Modifier.navigationBarsPadding().padding(horizontal = 12.dp)) {
            playback.track?.let { track ->
                Surface(shape = RoundedCornerShape(22.dp), color = Color(0xFF24232F), modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp).testTag("mini-player").clickable { showPlayer = true }) {
                    Row(Modifier.padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Row(Modifier.weight(1f).clickable { showPlayer = true }, verticalAlignment = Alignment.CenterVertically) {
                            Cover(track, Modifier.size(44.dp), 160)
                            Column(Modifier.padding(horizontal = 12.dp)) {
                                Text(track.title, maxLines = 1, overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.SemiBold)
                                Text(if (playback.loading) "Connexion à l’audio…" else track.artist, fontSize = 12.sp, color = Muted, maxLines = 1)
                            }
                        }
                        Action(if (playback.loading) Icons.Rounded.Close else if (playback.playing) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, if (playback.loading) "Annuler" else if (playback.playing) "Pause" else "Lire", vm::toggle)
                        Action(Icons.Rounded.SkipNext, "Titre suivant", vm::next)
                    }
                }
            }
            NavigationBar(containerColor = Panel, modifier = Modifier.clip(RoundedCornerShape(28.dp))) {
                listOf("Accueil" to Icons.Rounded.Home, "Recherche" to Icons.Rounded.Search, "Bibliothèque" to Icons.Rounded.LibraryMusic).forEachIndexed { index, item ->
                    NavigationBarItem(selected = tab == index && !showSettings, onClick = { tab = index; showSettings = false; selection = null },
                        icon = { Icon(item.second, item.first) }, label = { Text(item.first, fontSize = 11.sp) },
                        colors = NavigationBarItemDefaults.colors(indicatorColor = Accent.copy(alpha = .2f)))
                }
            }
        }
    }) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            when {
                showSettings -> SettingsScreen(vm, library)
                selection != null -> {
                    val playlist = library.playlists.firstOrNull { it.id == selection?.id } ?: selection!!
                    val byId = remember(library.tracks) { library.tracks.associateBy { it.id } }
                    TrackListScreen(playlist.name, playlist.tracks.mapNotNull { byId[it] }, vm, library)
                }
                tab == 0 -> HomeScreen(vm, library)
                tab == 1 -> SearchScreen(vm, library)
                else -> LibraryScreen(vm, library) { selection = it }
            }
        }
    }
    if (showPlayer && playback.track != null) {
        Dialog(onDismissRequest = { showPlayer = false }, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
            PlayerScreen(vm, playback, library) { showPlayer = false }
        }
    } else if (playback.error != null) {
        // Keep playback failures visible without a repeated blocking alert.
        LaunchedEffect(playback.error) { snackbar.showSnackbar(playback.error!!, duration = SnackbarDuration.Long) }
    }
}

@Composable
private fun HomeScreen(vm: BlusicViewModel, library: LibraryState) {
    val online by vm.home.collectAsStateWithLifecycle()
    val error by vm.homeError.collectAsStateWithLifecycle()
    val byId = remember(library.tracks) { library.tracks.associateBy { it.id } }
    val recent = remember(library.recent, byId) { library.recent.mapNotNull { byId[it] } }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(22.dp)) {
        item { Heading("Accès rapide", Icons.Rounded.Bolt) }
        item {
            Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    QuickCard("Titres favoris", "${library.favorites.size} titres", Icons.Rounded.Favorite, Modifier.weight(1f)) { library.tracks.firstOrNull { it.id in library.favorites }?.let { vm.play(it, library.tracks.filter { t -> t.id in library.favorites }) } }
                    QuickCard("Récents", "Ton historique", Icons.Rounded.History, Modifier.weight(1f)) { recent.firstOrNull()?.let { vm.play(it, recent) } }
                }
                val quick = (recent.ifEmpty { online }).take(4)
                quick.chunked(2).forEach { pair -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    pair.forEach { track -> Surface(color = Panel, shape = RoundedCornerShape(12.dp), modifier = Modifier.weight(1f).clickable { vm.play(track, quick) }) {
                        Row(Modifier.padding(8.dp), verticalAlignment = Alignment.CenterVertically) { Cover(track, Modifier.size(38.dp), 128); Text(track.title, Modifier.padding(start = 8.dp).weight(1f), maxLines = 2, fontSize = 12.sp) }
                    } }
                    if (pair.size == 1) Spacer(Modifier.weight(1f))
                } }
            }
        }
        if (recent.isNotEmpty()) item { AlbumShelf("Tes dernières écoutes", recent.take(12), vm) }
        if (error != null) item { Column(Modifier.padding(horizontal = 20.dp)) { Text(error!!, color = Muted, fontSize = 13.sp); TextButton(onClick = { vm.loadHome() }) { Text("Réessayer") } } }
        if (online.isNotEmpty()) item { AlbumShelf("À l’écoute en ce moment", online, vm) }
        item { AlbumShelf("Premières ondes", library.tracks.filter { it.source == "bundled" }, vm) }
    }
}

@Composable
private fun SearchScreen(vm: BlusicViewModel, library: LibraryState) {
    var query by rememberSaveable { mutableStateOf("") }
    var local by rememberSaveable { mutableStateOf(false) }
    val results by vm.search.collectAsStateWithLifecycle()
    val loading by vm.searchLoading.collectAsStateWithLifecycle()
    val error by vm.searchError.collectAsStateWithLifecycle()
    val tracks = remember(local, query, library.tracks, results) { if (local) library.tracks.filter { "${it.title} ${it.artist}".contains(query, true) } else results.tracks }
    LaunchedEffect(query, local) { if (!local) vm.search(query) }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item { Title("Recherche") }
        item { OutlinedTextField(query, { query = it }, label = { Text("Un titre ou un artiste…") }, singleLine = true, modifier = Modifier.fillMaxWidth().testTag("search-field"), leadingIcon = { Icon(Icons.Rounded.Search, null) }, shape = RoundedCornerShape(18.dp)) }
        item { Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { FilterChip(!local, { local = false }, { Text("Catalogue") }); FilterChip(local, { local = true }, { Text("Bibliothèque") }) } }
        if (query.isBlank() && !local) {
            item { Text("Qu’est-ce qui te fait vibrer ?", fontSize = 22.sp, fontWeight = FontWeight.Bold) }
            items(listOf("Rap français", "Jazz", "Électronique", "Piano", "Soul")) { genre -> Surface(onClick = { query = genre }, shape = RoundedCornerShape(14.dp), color = Panel, modifier = Modifier.fillMaxWidth()) { Text(genre, Modifier.padding(20.dp)) } }
        } else {
            if (loading) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
            if (error != null && !local) item { Text(error!!, color = Muted); TextButton(onClick = { vm.search(query) }) { Text("Réessayer") } }
            items(tracks, key = { it.id }) { track -> TrackRow(track, vm, library) { vm.play(track, tracks) } }
            if (!local && results.continuation != null) item { TextButton(onClick = { vm.loadMore(query) }, enabled = !loading) { Text("Charger la suite") } }
            if (!loading && tracks.isEmpty()) item { Text("Aucun titre trouvé.", color = Muted) }
        }
    }
}

@Composable
private fun LibraryScreen(vm: BlusicViewModel, library: LibraryState, open: (Playlist) -> Unit) {
    var section by rememberSaveable { mutableStateOf("Titres") }
    var creating by remember { mutableStateOf(false) }
    var name by remember { mutableStateOf("") }
    val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { vm.importAudio(it) }
    val tracks = remember(section, library.tracks, library.favorites) { when (section) { "Favoris" -> library.tracks.filter { it.id in library.favorites }; "Hors ligne" -> library.tracks.filter { it.source != "online" }; else -> library.tracks } }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item { Row(verticalAlignment = Alignment.CenterVertically) { Title("Bibliothèque"); Spacer(Modifier.weight(1f)); Action(Icons.Rounded.Add, "Importer des fichiers", { importer.launch(arrayOf("audio/*")) }) } }
        item { Text("${library.tracks.size} titres · ta musique, simplement", color = Muted, fontSize = 13.sp) }
        item { LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) { items(listOf("Titres", "Favoris", "Playlists", "Hors ligne")) { value -> FilterChip(section == value, { section = value }, { Text(value) }) } } }
        if (section == "Playlists") {
            item { OutlinedButton(onClick = { creating = true }) { Icon(Icons.Rounded.Add, null); Text("Créer une playlist") } }
            items(library.playlists, key = { it.id }) { p -> ListItem(headlineContent = { Text(p.name) }, supportingContent = { Text("${p.tracks.size} titres") }, leadingContent = { Icon(Icons.Rounded.QueueMusic, null) }, modifier = Modifier.clip(RoundedCornerShape(12.dp)).clickable { open(p) }) }
        } else {
            items(tracks, key = { it.id }) { track -> TrackRow(track, vm, library) { vm.play(track, tracks) } }
        }
    }
    if (creating) AlertDialog(onDismissRequest = { creating = false }, title = { Text("Nouvelle playlist") }, text = { OutlinedTextField(name, { name = it }, label = { Text("Nom") }) }, confirmButton = { TextButton(onClick = { vm.createPlaylist(name); name = ""; creating = false }, enabled = name.isNotBlank()) { Text("Créer") } }, dismissButton = { TextButton(onClick = { creating = false }) { Text("Annuler") } })
}

@Composable
private fun TrackListScreen(title: String, tracks: List<Track>, vm: BlusicViewModel, library: LibraryState) {
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item { Title(title); Text("${tracks.size} titres", color = Muted) }
        item { Button(onClick = { tracks.firstOrNull()?.let { vm.play(it, tracks) } }, enabled = tracks.isNotEmpty()) { Text("Écouter") } }
        items(tracks, key = { it.id }) { track -> TrackRow(track, vm, library) { vm.play(track, tracks) } }
    }
}

@Composable
private fun PlayerScreen(vm: BlusicViewModel, state: PlaybackUi, library: LibraryState, close: () -> Unit) {
    val track = state.track ?: return
    var mode by rememberSaveable { mutableStateOf("artwork") }
    val context = LocalContext.current
    Column(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color(0xFF26334A), Color(0xFF171B28), Ink))).systemBarsPadding().padding(horizontal = 26.dp)) {
        Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Action(Icons.Rounded.KeyboardArrowDown, "Fermer le lecteur", close)
            Text("À L’ÉCOUTE", Modifier.weight(1f), fontSize = 11.sp, color = Muted, letterSpacing = 3.sp)
            Favorite(track, library, vm)
        }
        if (mode == "lyrics") {
            Text(track.title, fontSize = 20.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            Text(track.artist, color = Muted, fontSize = 14.sp)
            LyricsPanel(track, vm, Modifier.weight(1f))
        } else if (mode == "queue") {
            LazyColumn(Modifier.weight(1f)) { item { Title("À suivre") }; items(state.queue, key = { it.id }) { item -> TrackRow(item, vm, library) { vm.play(item, state.queue) } } }
        } else {
            Spacer(Modifier.weight(.3f))
            Cover(track, Modifier.fillMaxWidth().weight(2f, fill = false).aspectRatio(1f).testTag("player-artwork"), 1024)
            Spacer(Modifier.height(24.dp))
            Text(track.title, fontSize = 28.sp, fontWeight = FontWeight.Bold, maxLines = 2, lineHeight = 32.sp)
            Text(track.artist, color = Color.White.copy(alpha = .6f), fontSize = 19.sp, maxLines = 1)
            Text(track.album, color = Muted, fontSize = 12.sp, maxLines = 1, modifier = Modifier.padding(top = 7.dp))
            Spacer(Modifier.weight(.25f))
        }
        if (state.loading) Row(Modifier.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) { CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp); Text("  Connexion à l’audio…", fontSize = 12.sp) }
        state.error?.let { error ->
            Text(error, color = Color(0xFFFFC7CC), fontSize = 12.sp, maxLines = 4, overflow = TextOverflow.Ellipsis)
            Row {
                TextButton(onClick = { vm.play(track, state.queue) }) { Text("Réessayer") }
                TextButton(onClick = { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://music.youtube.com/watch?v=${track.location}"))) }) { Text("Lecteur officiel") }
            }
        }
        PlaybackProgress(vm, track)
        Row(Modifier.fillMaxWidth().padding(vertical = 12.dp), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Action(Icons.Rounded.Shuffle, "Lecture aléatoire", vm::shuffle, if (state.shuffle) Accent else Muted)
            Action(Icons.Rounded.SkipPrevious, "Titre précédent", vm::previous)
            FilledIconButton(onClick = vm::toggle, modifier = Modifier.size(72.dp).testTag("player-play"), colors = IconButtonDefaults.filledIconButtonColors(containerColor = Color.White, contentColor = Ink)) {
                Icon(if (state.loading) Icons.Rounded.Close else if (state.playing) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, if (state.loading) "Annuler" else if (state.playing) "Pause" else "Lire", modifier = Modifier.size(35.dp))
            }
            Action(Icons.Rounded.SkipNext, "Titre suivant", vm::next)
            Action(if (state.repeat == 1) Icons.Rounded.RepeatOne else Icons.Rounded.Repeat, "Répétition", vm::repeat, if (state.repeat != 0) Accent else Muted)
        }
        Row(Modifier.fillMaxWidth().padding(bottom = 12.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            Action(Icons.Rounded.Lyrics, "Paroles", { mode = if (mode == "lyrics") "artwork" else "lyrics" }, if (mode == "lyrics") Accent else Muted)
            TextButton(onClick = { vm.audio(if (library.speed >= 1.5f) .75f else library.speed + .25f, library.linkedPitch) }) { Text("${library.speed}×") }
            Action(Icons.Rounded.QueueMusic, "File d’attente", { mode = if (mode == "queue") "artwork" else "queue" }, if (mode == "queue") Accent else Muted)
        }
    }
}

@Composable
private fun PlaybackProgress(vm: BlusicViewModel, track: Track) {
    var position by remember { mutableLongStateOf(0L) }
    var duration by remember { mutableLongStateOf(track.duration) }
    var scrubbing by remember { mutableStateOf(false) }
    var scrub by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(track.id) { while (true) { if (!scrubbing) position = vm.controller?.currentPosition ?: 0; duration = vm.controller?.duration?.takeIf { it > 0 } ?: track.duration; delay(250) } }
    Column {
        Slider(value = if (scrubbing) scrub else position.toFloat().coerceIn(0f, duration.coerceAtLeast(1).toFloat()),
            onValueChange = { scrubbing = true; scrub = it }, valueRange = 0f..duration.coerceAtLeast(1).toFloat(),
            onValueChangeFinished = { vm.seek(scrub.toLong()); position = scrub.toLong(); scrubbing = false }, modifier = Modifier.testTag("progress"))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { Text(position.clock(), color = Muted, fontSize = 12.sp); Text("−${(duration - position).clock()}", color = Muted, fontSize = 12.sp) }
    }
}

@Composable
private fun LyricsPanel(track: Track, vm: BlusicViewModel, modifier: Modifier) {
    var raw by remember(track.id) { mutableStateOf(track.lyrics.orEmpty()) }
    var status by remember(track.id) { mutableStateOf("Recherche des paroles…") }
    var position by remember { mutableLongStateOf(0) }
    var auto by remember(track.id) { mutableStateOf(true) }
    val list = rememberLazyListState()
    LaunchedEffect(track.id) { try { raw = vm.lyrics(track).orEmpty(); status = if (track.source == "bundled") "Un instrumental. Juste les notes." else "Paroles introuvables pour ce titre." } catch (e: Exception) { status = e.localizedMessage.orEmpty() } }
    LaunchedEffect(track.id) { while (true) { position = vm.controller?.currentPosition ?: 0; delay(250) } }
    val lines = remember(raw) { LyricsParser.parse(raw) }
    val active = lines.indexOfLast { it.time <= position }
    LaunchedEffect(active, auto, lines) { if (auto && active >= 0 && !list.isScrollInProgress) list.animateScrollToItem(active, -180) }
    LaunchedEffect(list.interactionSource) { list.interactionSource.interactions.collect { if (it is androidx.compose.foundation.interaction.DragInteraction.Start) auto = false } }
    Column(modifier.padding(top = 12.dp)) {
        if (!auto) TextButton(onClick = { auto = true }) { Text("Recentrer") }
        LazyColumn(state = list, modifier = Modifier.fillMaxSize().testTag("lyrics-panel"), contentPadding = PaddingValues(vertical = 80.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
            if (lines.isEmpty()) item { Text(raw.ifEmpty { status }, fontSize = 28.sp, lineHeight = 37.sp, fontWeight = FontWeight.Bold, color = Color.White.copy(alpha = .7f)) }
            else items(lines.size) { index ->
                val color by animateColorAsState(if (index == active) Color.White else Color.White.copy(alpha = .35f), label = "lyric color")
                val scale by animateFloatAsState(if (index == active) 1f else .95f, label = "lyric size")
                Text(lines[index].text.ifBlank { "♪ ♪ ♪" }, fontSize = 31.sp, lineHeight = 40.sp, fontWeight = FontWeight.Bold, color = color,
                    modifier = Modifier.scale(scale).clickable { vm.seek(lines[index].time); auto = true })
            }
        }
    }
}

@Composable
private fun SettingsScreen(vm: BlusicViewModel, library: LibraryState) {
    var mode by remember(library.sourceMode) { mutableStateOf(library.sourceMode) }
    var instance by remember(library.instance) { mutableStateOf(library.instance) }
    var speed by remember(library.speed) { mutableFloatStateOf(library.speed) }
    var relay by remember(library.relayAddress) { mutableStateOf(library.relayAddress) }
    var relayKey by remember { mutableStateOf("") }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        item { Title("À ton image") }
        item { Text("Sources audio", fontWeight = FontWeight.Bold, fontSize = 19.sp) }
        item { Column { listOf("auto" to "Automatique", "direct" to "YouTube direct", "invidious" to "Relais Invidious").forEach { (key, label) -> Row(Modifier.fillMaxWidth().clickable { mode = key }, verticalAlignment = Alignment.CenterVertically) { RadioButton(mode == key, { mode = key }); Text(label) } } } }
        item { OutlinedTextField(instance, { instance = it }, label = { Text("Adresse HTTPS Invidious") }, singleLine = true, modifier = Modifier.fillMaxWidth()) }
        item { Button(onClick = { vm.source(mode, instance) }) { Text("Enregistrer les sources") } }
        item { Text("Les flux publics peuvent être indisponibles ou refusés par leur fournisseur. Blusic vérifie l’audio et utilise des plages HTTP bornées. Aucun compte Google n’est connecté.", color = Muted, fontSize = 13.sp) }
        item { HorizontalDivider() }
        item { Text("Relais youtubei.js", fontWeight = FontWeight.Bold, fontSize = 19.sp) }
        item { OutlinedTextField(relay, { relay = it }, label = { Text("Adresse HTTPS du relais") }, singleLine = true, modifier = Modifier.fillMaxWidth()) }
        item { OutlinedTextField(relayKey, { relayKey = it }, label = { Text("Clé du relais") }, visualTransformation = PasswordVisualTransformation(), singleLine = true, modifier = Modifier.fillMaxWidth()) }
        item { Button(onClick = { vm.relay(relay, relayKey) }) { Text("Enregistrer le relais") }; Text("Nécessite le service Node déployé. La clé est protégée par Android Keystore ; aucun serveur n’est déclaré fonctionnel avant son test audio complet.", color = Muted, fontSize = 13.sp) }
        item { HorizontalDivider() }
        item { Text("Vitesse et tonalité", fontWeight = FontWeight.Bold, fontSize = 19.sp); Text("${"%.2f".format(speed)}×", color = Accent); Slider(speed, { speed = it }, valueRange = .5f..2f, onValueChangeFinished = { vm.audio(speed, library.linkedPitch) }) }
        item { Row(verticalAlignment = Alignment.CenterVertically) { Text("Lier vitesse et tonalité", Modifier.weight(1f)); Switch(library.linkedPitch, { vm.audio(speed, it) }) } }
        item { Text("Mode lié : le son accélère et monte ensemble. Mode désactivé : la vitesse change en conservant la hauteur.", color = Muted, fontSize = 13.sp) }
        item { HorizontalDivider(); Text("Blusic Android ${BuildConfig.VERSION_NAME}", Modifier.padding(top = 16.dp), fontWeight = FontWeight.Bold) }
        item { Text("Bibliothèque et favoris conservés sur cet appareil. Imports via le sélecteur Android, sans accès global à tes fichiers. Recherche : YouTube Music ; paroles : LRCLIB ; pochettes : fournisseurs du catalogue. Lecture en arrière-plan : Media3/ExoPlayer, notification média et écran verrouillé.", color = Muted, fontSize = 13.sp) }
        item { Text("Les quatre instrumentaux Blusic Studio et leurs pochettes sont les originaux du projet. Les autres contenus appartiennent à leurs titulaires. AAC compressé : aucune promesse de lossless ni de catalogue intégral.", color = Muted, fontSize = 13.sp) }
    }
}

@Composable
private fun TrackRow(track: Track, vm: BlusicViewModel, library: LibraryState, play: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Row(Modifier.weight(1f).clickable(onClick = play), verticalAlignment = Alignment.CenterVertically) {
            Cover(track, Modifier.size(52.dp), 160)
            Column(Modifier.padding(start = 12.dp).weight(1f)) { Text(track.title, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis); Text(track.artist, color = Muted, fontSize = 12.sp, maxLines = 1) }
        }
        Favorite(track, library, vm)
        Box {
            Action(Icons.Rounded.MoreVert, "Options pour ${track.title}", { menu = true })
            DropdownMenu(menu, { menu = false }) {
                library.playlists.forEach { playlist -> DropdownMenuItem(text = { Text("Ajouter à ${playlist.name}") }, onClick = { vm.addToPlaylist(track, playlist); menu = false }) }
                if (library.playlists.isEmpty()) DropdownMenuItem(text = { Text("Crée une playlist dans Bibliothèque") }, onClick = { menu = false })
            }
        }
    }
}
@Composable
private fun Favorite(track: Track, library: LibraryState, vm: BlusicViewModel) {
    val liked = library.tracks.firstOrNull { it.identity == track.identity }?.id in library.favorites
    Action(if (liked) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder, if (liked) "Retirer des favoris" else "Ajouter aux favoris", { vm.favorite(track) }, if (liked) Accent else Muted)
}
@Composable
private fun Cover(track: Track, modifier: Modifier, pixels: Int) {
    val context = LocalContext.current
    val url = track.artworkUrl ?: "file:///android_asset/${track.artwork}.imageset/${track.artwork}.png"
    AsyncImage(ImageRequest.Builder(context).data(url).size(pixels).crossfade(false).build(), contentDescription = "Pochette de ${track.title}",
        modifier = modifier.clip(RoundedCornerShape(14.dp)).background(Panel), contentScale = ContentScale.Crop)
}
@Composable
private fun AlbumShelf(title: String, tracks: List<Track>, vm: BlusicViewModel) {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text(title, Modifier.padding(horizontal = 20.dp), fontSize = 22.sp, fontWeight = FontWeight.Bold)
        LazyRow(contentPadding = PaddingValues(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            items(tracks, key = { it.id }) { track -> Column(Modifier.width(148.dp).clickable { vm.play(track, tracks) }) {
                Cover(track, Modifier.size(148.dp), 512)
                Text(track.title, Modifier.padding(top = 8.dp), maxLines = 1, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                Text(track.artist, maxLines = 1, color = Muted, fontSize = 12.sp)
            } }
        }
    }
}
@Composable
private fun Heading(text: String, icon: ImageVector) { Row(Modifier.padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) { Icon(icon, null); Text(text, Modifier.padding(start = 8.dp), fontSize = 24.sp, fontWeight = FontWeight.Bold) } }
@Composable
private fun Title(text: String) { Text(text, fontSize = 27.sp, fontWeight = FontWeight.Bold, letterSpacing = (-.7).sp) }
@Composable
private fun QuickCard(title: String, detail: String, icon: ImageVector, modifier: Modifier, click: () -> Unit) { Surface(color = Panel, shape = RoundedCornerShape(12.dp), modifier = modifier.clickable(onClick = click)) { Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) { Icon(icon, null, tint = Accent); Column(Modifier.padding(start = 10.dp)) { Text(title, fontSize = 12.sp, fontWeight = FontWeight.SemiBold); Text(detail, color = Muted, fontSize = 10.sp) } } } }
@Composable
private fun Action(icon: ImageVector, label: String, action: () -> Unit, tint: Color = Color.White) { IconButton(onClick = action) { Icon(icon, contentDescription = label, tint = tint) } }
