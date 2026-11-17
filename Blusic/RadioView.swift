import SwiftUI

struct RadioView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayer.self) private var player
    @State private var query = ""
    private var suggestions: [Track] {
        var seen = Set<UUID>()
        let choices = library.likedTracks + library.recentTracks + library.tracks
        return choices.filter { track in
            seen.insert(track.id).inserted && track.isNative &&
            (!library.settings.usesOfflinePlaybackOnly || library.downloads.isAvailable(track)) &&
            (query.isEmpty || "\(track.title) \(track.subtitle)".localizedStandardContains(query))
        }
    }
    var body: some View {
        List {
            Section {
                Label("Ta radio, tes découvertes", systemImage: "dot.radiowaves.left.and.right").font(.title2.bold())
                Text("Pars d’un titre. Soryn utilise sa radio YouTube Music, tes favoris, tes écoutes et les titres que tu écartes pour composer la suite. Pas de compte obligatoire.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Toggle("AutoMix", isOn: Binding(get: { library.settings.usesAutoMix }, set: { library.settings.autoMixEnabled = $0 }))
                if library.settings.usesOfflinePlaybackOnly { Label("Découverte limitée à tes titres hors ligne", systemImage: "wifi.slash").font(.caption) }
            }
            if player.radio.active {
                Section("À l’écoute") {
                    if let current = player.current {
                        radioRow(current)
                        Button("Moins de ce titre", systemImage: "hand.thumbsdown") { player.radio.dislikeCurrent() }
                    }
                    HStack { Text(player.radio.message).font(.caption); if player.radio.loading { Spacer(); ProgressView() } }
                    Button("Arrêter la radio, garder la file", systemImage: "stop.circle") { player.radio.stop() }
                }
                Section("Prochaines découvertes") {
                    let index = player.queue.firstIndex { $0.id == player.current?.id } ?? -1
                    ForEach(Array(player.queue.dropFirst(index + 1).prefix(12))) { track in radioRow(track) }
                }
            }
            Section(player.radio.active ? "Changer de point de départ" : "Choisis ton point de départ") {
                if suggestions.isEmpty { Text("Ajoute des favoris ou lance une radio depuis le menu d’un résultat de recherche.").foregroundStyle(.secondary) }
                ForEach(Array(suggestions.prefix(40))) { track in
                    Button { player.radio.start(track) } label: {
                        HStack(spacing: 12) {
                            ArtworkView(track: track, size: 42, radius: 9)
                            VStack(alignment: .leading) { Text(track.title).lineLimit(1); Text(track.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            Spacer(); Image(systemName: "dot.radiowaves.left.and.right")
                        }
                    }.buttonStyle(.plain).accessibilityLabel("Lancer la radio de \(track.title)")
                }
            }
            if !player.radio.disliked.isEmpty {
                Section { Button("Réinitialiser les titres écartés (\(player.radio.disliked.count))") { player.radio.resetDislikes() } }
            }
        }
        .navigationTitle("Radio personnalisée").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .searchable(text: $query, prompt: "Un titre de ta bibliothèque")
    }
    private func radioRow(_ track: Track) -> some View {
        Button { player.play(track, preservingRadio: true) } label: {
            HStack(spacing: 12) {
                ArtworkView(track: track, size: 42, radius: 9)
                VStack(alignment: .leading) { Text(track.title).lineLimit(1); Text(track.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Spacer(); Image(systemName: player.current?.id == track.id ? "waveform" : "play.circle")
            }
        }.buttonStyle(.plain)
    }
}
