import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @FocusState private var focused: Bool
    @State private var query = ""
    @State private var scope = "Catalogue"
    @State private var results: [Track] = []
    @State private var loading = false
    @State private var error: String?
    @State private var page = 1
    @State private var hasMore = false
    @State private var loadingMore = false
    @State private var retry = 0
    @State private var pageTask: Task<Void, Never>?
    private var searchKey: String { "\(scope)|\(query)|\(library.settings.invidiousAddress)|\(library.settings.usesInvidiousFallback)|\(retry)" }
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
                    Text("Catalogue").tag("Catalogue")
                    Text("Bibliothèque").tag("Bibliothèque")
                }.pickerStyle(.segmented)

                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        SectionHeading(title: "Qu’est-ce qui te fait vibrer ?")
                        let genres = ["Électronique", "Jazz", "Rap français", "Indie", "Piano", "Soul"]
                        let colors: [Color] = [.indigo, .orange, .blue, .purple, .teal, .pink]
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(Array(genres.enumerated()), id: \.offset) { i, genre in
                                Button { query = genre; scope = "Catalogue"; focused = false } label: {
                                    ZStack(alignment: .bottomLeading) {
                                        LinearGradient(colors: [colors[i].opacity(0.8), colors[i].opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                        Image(systemName: ["waveform", "pianokeys", "mic.fill", "guitars.fill", "pianokeys", "sparkles"][i])
                                            .font(.system(size: 64, weight: .ultraLight)).rotationEffect(.degrees(-18)).foregroundStyle(.white.opacity(0.13)).frame(maxWidth: .infinity, alignment: .trailing).offset(x: 12, y: -10)
                                        Text(genre).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(.white).padding(16)
                                    }.frame(height: 110).clipShape(RoundedRectangle(cornerRadius: 19))
                                }.buttonStyle(.plain)
                            }
                        }
                        Text("Catalogue YouTube public via Invidious · Aucune clé API. Lecture audio native, qualité AAC disponible selon le titre. L’instance peut être changée dans les réglages.")
                            .font(.caption).foregroundStyle(.secondary).lineSpacing(4)
                    }
                } else if loading { ProgressView("Recherche en cours…").frame(maxWidth: .infinity).padding(30) }
                else if let error {
                    EmptyState(symbol: "wifi.exclamationmark", title: "Recherche indisponible", message: error)
                    Button("Réessayer") { retry += 1 }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                }
                else {
                    let tracks = scope == "Catalogue" ? results : localResults
                    if tracks.isEmpty { EmptyState(symbol: "magnifyingglass", title: "Pas encore trouvé", message: "Essaie un autre titre ou un autre artiste.") }
                    else {
                        SectionHeading(title: "\(tracks.count) résultats", subtitle: scope == "Catalogue" ? "YouTube via Invidious · audio natif" : "Dans ta bibliothèque")
                        ForEach(tracks) { track in
                            TrackRow(track: track, context: tracks) {
                                let saved = library.add(track)
                                player.play(saved, in: tracks.map { $0.id == track.id ? saved : $0 })
                                focused = false
                            }
                        }
                        if scope == "Catalogue", hasMore {
                            Button {
                                pageTask?.cancel()
                                pageTask = Task { await loadMore() }
                            } label: {
                                HStack { if loadingMore { ProgressView() }; Text("Charger la suite") }.frame(maxWidth: .infinity).padding(10)
                            }.buttonStyle(.bordered).disabled(loadingMore)
                        }
                    }
                }
            }.pagePadding().padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .task(id: searchKey) { pageTask?.cancel(); await search() }
        .onDisappear { pageTask?.cancel() }
    }
    private func search() async {
        error = nil; loading = false; results = []; page = 1; hasMore = false; loadingMore = false
        guard scope == "Catalogue", !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        loading = true
        do {
            try await Task.sleep(for: .milliseconds(650))
            let service = try InvidiousService(address: library.settings.invidiousAddress, automaticFallback: library.settings.usesInvidiousFallback)
            let found = try await service.search(query)
            try Task.checkCancellation()
            results = found; loading = false; hasMore = !found.isEmpty
        } catch is CancellationError { }
        catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
    }
    private func loadMore() async {
        let key = searchKey
        loadingMore = true
        defer { if key == searchKey { loadingMore = false } }
        do {
            let service = try InvidiousService(address: library.settings.invidiousAddress, automaticFallback: library.settings.usesInvidiousFallback)
            let found = try await service.search(query, page: page + 1)
            try Task.checkCancellation()
            guard key == searchKey else { return }
            let ids = Set(results.map(\.location))
            let new = found.filter { !ids.contains($0.location) }
            results.append(contentsOf: new); page += 1; hasMore = !new.isEmpty
        } catch { if !Task.isCancelled, key == searchKey { library.error = error.localizedDescription } }
    }
}
