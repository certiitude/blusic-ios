import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @FocusState private var focused: Bool
    @State private var query = ""
    @State private var scope = "Bibliothèque"
    @State private var results: [Track] = []
    @State private var loading = false
    @State private var error: String?
    private var localResults: [Track] {
        library.tracks.filter { "\($0.title) \($0.subtitle) \($0.album)".localizedStandardContains(query) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 23) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("SUIS TA CURIOSITÉ").font(.system(size: 10, weight: .bold)).tracking(2.5).foregroundStyle(library.settings.color)
                    Text("Recherche").font(.system(size: 34, weight: .bold, design: .rounded)).tracking(-1.2)
                }.padding(.top, 18)
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Titres, artistes, albums…", text: $query).focused($focused)
                        .submitLabel(.search).autocorrectionDisabled()
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.accessibilityLabel("Effacer la recherche") }
                }.padding(16).surface(radius: 17)
                Picker("Rechercher dans", selection: $scope) {
                    Text("Bibliothèque").tag("Bibliothèque")
                    Text("YouTube").tag("YouTube")
                }.pickerStyle(.segmented)

                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        SectionHeading(title: "Qu’est-ce qui te fait vibrer ?")
                        let genres = ["Électronique", "Jazz", "Rap français", "Indie", "Piano", "Soul"]
                        let colors: [Color] = [.indigo, .orange, .blue, .purple, .teal, .pink]
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(Array(genres.enumerated()), id: \.offset) { i, genre in
                                Button { query = genre; scope = "YouTube"; focused = false } label: {
                                    ZStack(alignment: .bottomLeading) {
                                        LinearGradient(colors: [colors[i].opacity(0.8), colors[i].opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                        Image(systemName: ["waveform", "pianokeys", "mic.fill", "guitars.fill", "pianokeys", "sparkles"][i])
                                            .font(.system(size: 64, weight: .ultraLight)).rotationEffect(.degrees(-18)).foregroundStyle(.white.opacity(0.13)).frame(maxWidth: .infinity, alignment: .trailing).offset(x: 12, y: -10)
                                        Text(genre).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(.white).padding(16)
                                    }.frame(height: 110).clipShape(RoundedRectangle(cornerRadius: 19))
                                }.buttonStyle(.plain)
                            }
                        }
                        Text("Le catalogue YouTube nécessite une clé API dans les réglages. La lecture utilise le lecteur vidéo officiel.")
                            .font(.caption).foregroundStyle(.secondary).lineSpacing(4)
                    }
                } else if loading { ProgressView("Recherche en cours…").frame(maxWidth: .infinity).padding(30) }
                else if let error { EmptyState(symbol: "wifi.exclamationmark", title: "Recherche indisponible", message: error) }
                else {
                    let tracks = scope == "YouTube" ? results : localResults
                    if tracks.isEmpty { EmptyState(symbol: "magnifyingglass", title: "Pas encore trouvé", message: "Essaie un autre titre ou un autre artiste.") }
                    else {
                        SectionHeading(title: "\(tracks.count) résultats", subtitle: scope == "YouTube" ? "Catalogue vidéo YouTube" : "Dans ta bibliothèque")
                        ForEach(tracks) { track in
                            TrackRow(track: track, context: tracks) {
                                let saved = library.add(track)
                                player.play(saved, in: tracks.map { $0.id == track.id ? saved : $0 })
                                focused = false
                            }
                        }
                    }
                }
            }.pagePadding().padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .task(id: "\(scope)|\(query)") { await search() }
    }
    private func search() async {
        error = nil; loading = false; results = []
        guard scope == "YouTube", !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        loading = true
        do {
            try await Task.sleep(for: .milliseconds(650))
            let found = try await YouTubeService().search(query, key: SecureStore.read("youtube-api-key"))
            try Task.checkCancellation()
            results = found; loading = false
        } catch is CancellationError { }
        catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
    }
}
