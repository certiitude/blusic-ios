import SwiftUI

struct DownloadsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayer.self) private var player
    @State private var confirmRemoveAll = false
    @State private var query = ""
    @State private var format = "all"
    @State private var sortByTitle = false
    var body: some View {
        let downloads = library.downloads
        let entries = downloads.records.values.filter { entry in
            (format == "all" || entry.codec?.rawValue == format) &&
            (query.isEmpty || entry.track.title.localizedStandardContains(query) || entry.track.subtitle.localizedStandardContains(query))
        }.sorted { sortByTitle ? $0.track.title.localizedStandardCompare($1.track.title) == .orderedAscending : $0.downloadedAt > $1.downloadedAt }
        let playable = entries.filter { downloads.integrityIssues[$0.id] == nil }.reduce(into: [Track]()) { tracks, entry in
            if !tracks.contains(where: { $0.id == entry.track.id }) { tracks.append(library.track(entry.track.id) ?? entry.track) }
        }
        let pending = library.tracks.filter { downloads.status(for: $0) != nil }
        List {
            Section {
                LabeledContent("Stockage audio", value: ByteCountFormatter.string(fromByteCount: downloads.totalBytes, countStyle: .file))
                LabeledContent("Titres enregistrés", value: "\(downloads.uniqueTrackCount) · \(downloads.records.count) fichiers")
                if downloads.pendingCount > 0 || downloads.completedInSession > 0 {
                    Text("\(downloads.completedInSession) terminés · \(downloads.pendingCount) en attente ou en cours · \(downloads.failedCount) en échec")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Les titres entièrement téléchargés sont conservés sur cet iPhone jusqu’à leur suppression. Ils sont lus en priorité sans connexion, même si le cache temporaire est vidé.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Garde Soryn ouvert pendant les téléchargements. iOS peut suspendre une préparation lorsque l’application est en arrière-plan ; les fichiers déjà terminés restent disponibles.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = downloads.error { Section { Text(error).foregroundStyle(.red).font(.caption) } }
            if !downloads.recoverable.isEmpty {
                Section("Téléchargements interrompus · \(downloads.recoverable.count)") {
                    Text("La file a été conservée après la fermeture de l’app. Aucun téléchargement ne reprend sans ton accord.").font(.caption).foregroundStyle(.secondary)
                    Button("Reprendre la file", systemImage: "arrow.clockwise") { downloads.resumeInterrupted() }
                    Button("Oublier cette file", role: .destructive) { downloads.discardInterrupted() }
                }
            }
            Section("État des fichiers") {
                Button { Task { await downloads.verifyDownloads() } } label: {
                    HStack { Label(downloads.checkingIntegrity ? "Vérification en cours…" : "Vérifier les téléchargements", systemImage: "checkmark.shield"); if downloads.checkingIntegrity { Spacer(); ProgressView() } }
                }.disabled(downloads.checkingIntegrity || downloads.records.isEmpty)
                if downloads.integrityCheckedAt != nil {
                    Text(downloads.integrityIssues.isEmpty ? "Tous les fichiers sont présents et leur format est vérifié." : "\(downloads.integrityIssues.count) fichiers à réparer. Les autres restent disponibles.")
                        .font(.caption).foregroundStyle(downloads.integrityIssues.isEmpty ? Color.secondary : .orange)
                }
            }
            if !pending.isEmpty {
                Section("En attente et en cours") {
                    if downloads.failedCount > 0 { Button("Réessayer tous les échecs", systemImage: "arrow.clockwise") { downloads.retryFailed() } }
                    ForEach(pending) { track in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) { Text(track.title).font(.headline).lineLimit(2); Text(track.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                Spacer()
                                if case .failed? = downloads.status(for: track) {
                                    Button { downloads.enqueue([track]) } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Réessayer \(track.title)")
                                }
                                Button { downloads.cancel(track) } label: { Image(systemName: "xmark.circle") }.accessibilityLabel("Annuler \(track.title)")
                            }.buttonStyle(.borderless)
                            if let state = downloads.status(for: track) {
                                Text(state.label).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                if case .downloading(_, let fraction) = state { ProgressView(value: fraction).accessibilityLabel("Téléchargement de \(track.title)") }
                            }
                        }.padding(.vertical, 5)
                    }
                    if downloads.pendingCount > 0 { Button("Annuler les téléchargements en attente") { downloads.cancelAll() } }
                }
            }
            Section {
                Picker("Format", selection: $format) { Text("Tous").tag("all"); Text("Opus").tag("opus"); Text("AAC").tag("aac") }.pickerStyle(.segmented)
                Toggle("Trier par titre", isOn: $sortByTitle)
            }
            Section("Fichiers enregistrés · \(entries.count)") {
                if entries.isEmpty { Text("Choisis Télécharger dans le menu … d’un titre ou dans une playlist.").foregroundStyle(.secondary) }
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        TrackRow(track: library.track(entry.track.id) ?? entry.track, context: playable)
                        Text(ByteCountFormatter.string(fromByteCount: entry.bytes, countStyle: .file) + (entry.codec == .opus ? " · Opus VBR" : entry.codec == .aac ? " · AAC" : "") + (entry.bitrate > 0 ? " · \(Int((Double(entry.bitrate) / 1000).rounded())) kbit/s" : "") + " · Hors ligne")
                            .font(.caption2).foregroundStyle(.secondary)
                        if let reason = entry.fallbackReason { Text(reason).font(.caption2).foregroundStyle(.orange) }
                        if downloads.integrityIssues[entry.id] != nil {
                            Label("Fichier absent, incomplet ou illisible", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                            Button("Réparer ce téléchargement", systemImage: "arrow.clockwise") { downloads.repair(entry) }
                                .disabled(downloads.status(for: entry.track)?.isActive == true)
                        }
                    }.swipeActions { Button("Supprimer", role: .destructive) { Task { await downloads.remove(entry) } } }
                }
            }
        }
        .navigationTitle("Téléchargements").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Titre ou artiste hors ligne")
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Écouter cette sélection", systemImage: "play.fill") { if let first = playable.first { player.play(first, in: playable) } }.disabled(playable.isEmpty)
                    Button(role: .destructive) { confirmRemoveAll = true } label: { Label("Tout supprimer", systemImage: "trash") }.disabled(entries.isEmpty)
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .confirmationDialog("Supprimer tous les fichiers téléchargés ?", isPresented: $confirmRemoveAll, titleVisibility: .visible) {
            Button("Supprimer les téléchargements", role: .destructive) { Task { await downloads.removeAll() } }
        } message: { Text("Les titres, playlists, favoris et fichiers importés restent dans ta bibliothèque.") }
        .task { await downloads.waitUntilReady() }
    }
}
