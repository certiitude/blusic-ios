package app.blusic.android

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil.compose.AsyncImage
import kotlinx.coroutines.delay

@Composable internal fun AdvancedDialog(title: String, close: () -> Unit, content: @Composable () -> Unit) {
    Dialog(onDismissRequest = close, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Surface(color = Ink, contentColor = MaterialTheme.colorScheme.onBackground, modifier = Modifier.fillMaxSize()) {
            Column(Modifier.systemBarsPadding().padding(20.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) { Text(title, Modifier.weight(1f), fontSize = 24.sp, fontWeight = FontWeight.Bold); Action(Icons.Rounded.Close, "Fermer", close) }
                Box(Modifier.weight(1f)) { content() }
            }
        }
    }
}
@Composable internal fun SettingSwitch(label: String, checked: Boolean, tag: String? = null, change: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().then(if (tag != null) Modifier.testTag(tag) else Modifier), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f)); Switch(checked, change)
    }
}
@Composable internal fun QualityControls(vm: BlusicViewModel, state: LibraryState) {
    Column {
        SettingSwitch("Audio haute qualité", state.highQuality, "high-quality") { value -> vm.settings { it.copy(highQuality = value) } }
        Text("Meilleur débit AAC réellement disponible. 256 kbit/s dépend du titre et de l’accès ; le lecteur affiche le débit obtenu. S’applique aux prochaines lectures et au préchargement.", color = Muted, fontSize = 12.sp)
    }
}
@Composable internal fun ListeningSettings(vm: BlusicViewModel, state: LibraryState) {
    var show by remember { mutableStateOf(false) }
    Column {
        Text("Écoute", fontSize = 19.sp, fontWeight = FontWeight.Bold)
        Text("Le suivant est préparé entièrement 45 secondes avant la fin, en tenant compte de la vitesse. Le fichier prêt est réutilisé pour le fondu et Suivant.", color = Muted, fontSize = 12.sp)
        SettingSwitch("Fondu entre les titres", state.crossfade, "crossfade-setting") { value -> vm.settings { it.copy(crossfade = value) } }
        if (state.crossfade) ValueSlider("Durée du fondu", state.crossfadeSeconds, .5f..8f, "s") { value -> vm.settings { it.copy(crossfadeSeconds = value) } }
        SettingSwitch("Retrouver la file au lancement", state.restoreQueue) { value -> vm.settings { it.copy(restoreQueue = value) } }
        OutlinedButton(onClick = { show = true }) { Text("Égaliseur, vitesse et tonalité") }
    }
    if (show) AdvancedDialog("Le son, à ta façon", { show = false }) { SoundControls(vm, state) }
}
@Composable private fun ValueSlider(label: String, value: Float, range: ClosedFloatingPointRange<Float>, unit: String = "", change: (Float) -> Unit) {
    var local by remember(value) { mutableFloatStateOf(value) }
    Column { Text("$label : ${"%.1f".format(local)} $unit", fontSize = 13.sp); Slider(local.coerceIn(range), { local = it }, valueRange = range, onValueChangeFinished = { change(local) }) }
}
@Composable internal fun SoundControls(vm: BlusicViewModel, state: LibraryState) {
    LazyColumn(Modifier.fillMaxSize().testTag("sound-controls"), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item { ValueSlider("Volume", state.volume * 100, 0f..100f, "%") { value -> vm.settings { it.copy(volume = value / 100) } } }
        item { ValueSlider("Vitesse", state.speed, .5f..2f, "×") { vm.audio(it, state.linkedPitch) } }
        item { SettingSwitch("Lier vitesse et tonalité", state.linkedPitch) { linked -> vm.audio(state.speed, linked) } }
        item { ValueSlider("Tonalité", if (state.linkedPitch) (12 * kotlin.math.log2(state.speed.toDouble())).toFloat() else state.pitchSemitones, -12f..12f, "demi-tons", vm::pitch) }
        item { Text(if (state.linkedPitch) "Le son accélère et monte ensemble." else "Vitesse et hauteur réglées indépendamment.", color = Muted, fontSize = 12.sp) }
        item { HorizontalDivider(); SettingSwitch("Égaliseur 10 bandes", state.equalizerEnabled, "equalizer-setting") { value -> vm.settings { it.copy(equalizerEnabled = value) } } }
        if (state.equalizerEnabled) items(10) { index ->
            ValueSlider("${TenBandEqualizer.frequencies[index].toInt()} Hz", state.equalizer[index], -12f..12f, "dB") { value -> vm.settings { old -> old.copy(equalizer = old.equalizer.toMutableList().apply { this[index] = value }) } }
        }
        item { TextButton(onClick = { vm.settings { it.copy(equalizer = List(10) { 0f }, pitchSemitones = 0f, speed = 1f) } }) { Text("Réinitialiser le son") } }
        item { Text("Le traitement reste natif. Une marge de volume évite la saturation des bandes amplifiées. Aucun réencodage vers un faux débit supérieur.", color = Muted, fontSize = 12.sp) }
    }
}
@Composable internal fun PlaybackOptions(vm: BlusicViewModel, track: Track) {
    val engine by vm.engine.collectAsStateWithLifecycle()
    val state by vm.library.collectAsStateWithLifecycle()
    val lyrics = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { it?.let { uri -> vm.importLyrics(uri, track) } }
    Column(Modifier.heightIn(max = 460.dp).verticalScroll(rememberScrollState())) {
        Text("Minuterie", fontWeight = FontWeight.Bold)
        LazyRow { items(listOf(15, 30, 45, 60)) { minutes -> TextButton(onClick = { vm.sleep(minutes) }) { Text("$minutes min") } } }
        engine.sleepDeadline?.let { Text("Arrêt à ${java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault()).format(java.util.Date(it))}", color = Muted) }
        TextButton(onClick = { vm.sleep(null) }) { Text("Annuler la minuterie") }
        SettingSwitch("Arrêter à la fin du titre", engine.stopAtEnd) { vm.stopAtEnd() }
        TextButton(onClick = vm::loop) { Text(when { engine.loopA == null -> "Définir le point A"; engine.loopB == null -> "Définir le point B"; else -> "Désactiver la boucle A–B" }) }
        engine.loopA?.let { Text("A ${it.clock()}" + (engine.loopB?.let { b -> " · B ${b.clock()}" } ?: ""), color = Muted) }
        HorizontalDivider()
        TextButton(onClick = { lyrics.launch(arrayOf("text/*", "application/octet-stream")) }) { Text("Importer des paroles LRC / texte") }
        ValueSlider("Décalage des paroles", state.lyricsOffset / 1000f, -10f..10f, "s") { value -> vm.settings { it.copy(lyricsOffset = (value * 1000).toLong()) } }
    }
}
@Composable internal fun AppearanceControls(vm: BlusicViewModel, state: LibraryState) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Ton univers", fontWeight = FontWeight.Bold, fontSize = 19.sp)
        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) { items(listOf("dark" to "Sombre", "light" to "Clair", "system" to "Système")) { (key, label) -> FilterChip(state.appearance == key, { vm.settings { it.copy(appearance = key) } }, { Text(label) }) } }
        LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) { items(listOf("blue", "violet", "rose", "mint", "orange", "white")) { color ->
            FilledIconButton(onClick = { vm.settings { it.copy(accent = color) } }, colors = IconButtonDefaults.filledIconButtonColors(containerColor = accentColor(color), contentColor = Color.Black)) { Icon(if (state.accent == color) Icons.Rounded.Check else Icons.Rounded.Circle, "Accent $color") }
        } }
        ValueSlider("Arrondi des pochettes", state.artworkRadius, 0f..36f) { value -> vm.settings { it.copy(artworkRadius = value) } }
        SettingSwitch("Animations des pochettes", state.animateArtwork) { value -> vm.settings { it.copy(animateArtwork = value) } }
        SettingSwitch("Retours haptiques", state.haptics) { value -> vm.settings { it.copy(haptics = value) } }
        SettingSwitch("Listes compactes", state.compactRows) { value -> vm.settings { it.copy(compactRows = value) } }
    }
}
@Composable internal fun BackupControls(vm: BlusicViewModel) {
    val export = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { it?.let(vm::export) }
    val restore = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { it?.let(vm::importDocument) }
    Column {
        Text("Ta bibliothèque", fontWeight = FontWeight.Bold, fontSize = 19.sp)
        OutlinedButton(onClick = { export.launch("Blusic-bibliotheque.json") }) { Text("Exporter la bibliothèque JSON") }
        OutlinedButton(onClick = { restore.launch(arrayOf("application/json", "text/*")) }) { Text("Restaurer une sauvegarde") }
        Text("Playlists, favoris, paroles, réglages, artistes suivis et statistiques sont sauvegardés. Conserve séparément tes fichiers audio. L’accès au relais n’est jamais exporté.", color = Muted, fontSize = 12.sp)
    }
}
@Composable internal fun ImportControls(vm: BlusicViewModel) {
    val document = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { it?.let(vm::importDocument) }
    var remote by remember { mutableStateOf(false) }; var address by remember { mutableStateOf("") }
    LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        item { OutlinedButton(onClick = { document.launch(arrayOf("text/*", "application/json", "application/octet-stream", "audio/x-mpegurl")) }) { Text("Importer CSV / JSON / M3U") } }
        item { OutlinedButton(onClick = { remote = true }) { Text("Playlist YouTube / Deezer") } }
    }
    if (remote) AlertDialog(onDismissRequest = { remote = false }, title = { Text("Importer une playlist") }, text = { OutlinedTextField(address, { address = it }, label = { Text("Lien HTTPS de la playlist publique") }) },
        confirmButton = { TextButton(onClick = { vm.importRemote(address); remote = false }) { Text("Importer") } }, dismissButton = { TextButton(onClick = { remote = false }) { Text("Annuler") } })
}
@Composable internal fun PlaylistEditControls(playlist: Playlist, vm: BlusicViewModel) {
    var editing by remember { mutableStateOf(false) }; var name by remember(playlist.name) { mutableStateOf(playlist.name) }
    Row { TextButton(onClick = { editing = true }) { Text("Renommer") }; TextButton(onClick = { vm.editPlaylist(playlist.id, delete = true) }) { Text("Supprimer la playlist") } }
    if (editing) AlertDialog(onDismissRequest = { editing = false }, title = { Text("Renommer la playlist") }, text = { OutlinedTextField(name, { name = it }) }, confirmButton = { TextButton(onClick = { vm.editPlaylist(playlist.id, name = name); editing = false }) { Text("Enregistrer") } })
}
@Composable internal fun ArtistRow(artist: MusicArtist, vm: BlusicViewModel, state: LibraryState) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Row(Modifier.weight(1f).clickable { vm.openArtist(artist) }, verticalAlignment = Alignment.CenterVertically) {
            AsyncImage(artist.artworkUrl, artist.name, Modifier.size(56.dp)); Text(artist.name, Modifier.padding(12.dp), fontWeight = FontWeight.Bold)
        }
        val followed = state.followedArtists.any { it.id == artist.id }
        Action(if (followed) Icons.Rounded.Check else Icons.Rounded.PersonAdd, if (followed) "Ne plus suivre" else "Suivre l’artiste", { vm.follow(artist) })
    }
}
@Composable internal fun ArtistScreen(profile: ArtistProfile, vm: BlusicViewModel, state: LibraryState) {
    val loading by vm.artistLoading.collectAsStateWithLifecycle()
    LazyColumn(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item { AsyncImage(profile.artist.artworkUrl, profile.artist.name, Modifier.fillMaxWidth().height(200.dp)) }
        item { ArtistRow(profile.artist, vm, state) }
        if (loading) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
        if (profile.biography.isNotBlank()) item { Text(profile.biography, color = Muted) }
        items(profile.tracks, key = { it.id }) { track -> TrackRow(track, vm, state) { vm.play(track, profile.tracks) } }
        if (!loading && profile.tracks.isEmpty()) item { Text("Aucun titre disponible dans ce profil.", color = Muted) }
    }
}
@Composable internal fun StatisticsScreen(state: LibraryState) {
    val totals = remember(state.history) { state.history.groupBy { it.trackId }.mapValues { it.value.sumOf(ListeningEvent::seconds) } }
    val now = System.currentTimeMillis(); val today = java.util.Calendar.getInstance().apply { set(java.util.Calendar.HOUR_OF_DAY, 0); set(java.util.Calendar.MINUTE, 0); set(java.util.Calendar.SECOND, 0); set(java.util.Calendar.MILLISECOND, 0) }.timeInMillis
    LazyColumn(Modifier.fillMaxSize().testTag("statistics"), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item { Title("${(state.history.sumOf { it.seconds } / 60).toInt()} min écoutées") }
        item { Text("Aujourd’hui : ${(state.history.filter { it.date >= today }.sumOf { it.seconds } / 60).toInt()} min · 7 jours : ${(state.history.filter { now - it.date <= 7 * 86400000L }.sumOf { it.seconds } / 60).toInt()} min", color = Muted) }
        item { Text("${state.tracks.size} titres · ${state.favorites.size} favoris · ${state.playlists.size} playlists · ${state.followedArtists.size} artistes suivis") }
        item { Text("Les plus écoutés", fontSize = 22.sp, fontWeight = FontWeight.Bold) }
        items(totals.entries.sortedByDescending { it.value }.take(12)) { entry -> state.byId[entry.key]?.let { track -> Text("${track.title} — ${track.artist}\n${(entry.value / 60).toInt()} min", Modifier.padding(vertical = 6.dp)) } }
    }
}
@Composable internal fun MatchDialog(reference: Track, vm: BlusicViewModel) {
    var query by remember(reference.id) { mutableStateOf("${reference.title} ${reference.artist}") }
    val results by vm.search.collectAsStateWithLifecycle(); val state by vm.library.collectAsStateWithLifecycle()
    val context = androidx.compose.ui.platform.LocalContext.current
    val file = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri -> uri?.let {
        runCatching { context.contentResolver.takePersistableUriPermission(it, android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION) }
        vm.associate(reference, reference.copy(source = "local", location = it.toString()))
    } }
    LaunchedEffect(query) { vm.search(query) }
    AdvancedDialog("Associer « ${reference.title} »", { vm.matchReference.value = null }) {
        LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item { OutlinedTextField(query, { query = it }, label = { Text("Trouver la bonne chanson") }, modifier = Modifier.fillMaxWidth()) }
            item { Text("L’association automatique n’est pas assez sûre. Choisis la bonne version.", color = Muted) }
            item { OutlinedButton(onClick = { file.launch(arrayOf("audio/*")) }) { Text("Associer un fichier audio") } }
            items(results.tracks, key = { it.id }) { candidate -> TrackRow(candidate, vm, state) { vm.associate(reference, candidate) } }
        }
    }
}
