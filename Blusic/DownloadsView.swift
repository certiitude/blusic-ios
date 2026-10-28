import SwiftUI

struct DownloadsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayer.self) private var player
    @State private var confirmRemoveAll = false
    var body: some View {
        let downloads = library.downloads
        let entries = downloads.records.values.sorted { $0.downloadedAt > $1.downloadedAt }
        let pending = library.tracks.filter { downloads.status(for: $0) != nil }
        List {
            Section {
                LabeledContent("Stockage audio", value: ByteCountFormatter.string(fromByteCount: downloads.totalBytes, countStyle: .file))
                Text("Les titres entièrement téléchargés sont conservés sur cet iPhone jusqu’à leur suppression. Ils sont lus en priorité sans connexion, même si le cache temporaire est vidé.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Garde Soryn ouvert pendant les téléchargements. iOS peut suspendre une préparation lorsque l’application est en arrière-plan ; les fichiers déjà terminés restent disponibles.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = downloads.error { Section { Text(error).foregroundStyle(.red).font(.caption) } }
            if !pending.isEmpty {
                Section("En attente et en cours") {
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
            Section("Disponibles hors ligne · \(entries.count)") {
                if entries.isEmpty { Text("Choisis Télécharger dans le menu … d’un titre ou dans une playlist.").foregroundStyle(.secondary) }
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        TrackRow(track: library.track(entry.track.id) ?? entry.track, context: entries.map(\.track))
                        Text(ByteCountFormatter.string(fromByteCount: entry.bytes, countStyle: .file) + (entry.bitrate > 0 ? " · \(Int((Double(entry.bitrate) / 1000).rounded())) kbit/s" : "") + " · Hors ligne")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.swipeActions { Button("Supprimer", role: .destructive) { Task { await downloads.remove(entry.track) } } }
                }
            }
        }
        .navigationTitle("Téléchargements").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Écouter les téléchargements", systemImage: "play.fill") { if let first = entries.first { player.play(first.track, in: entries.map(\.track)) } }.disabled(entries.isEmpty)
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
