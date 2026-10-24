import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @FocusState private var focused: Bool
    @State private var query = {
        #if DEBUG
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--blusic-query=") }) {
            return String(argument.dropFirst("--blusic-query=".count))
        }
        #endif
        return ""
    }()
    @State private var scope = "Catalogue"
    @State private var results: [Track] = []
    @State private var loading = false
    @State private var error: String?
    @State private var continuation: String?
    @State private var loadingMore = false
    @State private var retry = 0
    @State private var pageTask: Task<Void, Never>?
    @State private var prefetchTask: Task<Void, Never>?
    private var searchKey: String { "\(scope)|\(query)|\(library.settings.invidiousAddress)|\(library.settings.usesInvidiousFallback)|\(retry)" }
    private var localResults: [Track] {
        library.tracks.filter { "\($0.title) \($0.subtitle) \($0.album)".localizedStandardContains(query) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 23) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Recherche").font(.system(size: 27, weight: .bold)).tracking(-0.8)
                }.padding(.top, 14)
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Un titre ou un artiste…", text: $query).focused($focused)
                        .submitLabel(.search).autocorrectionDisabled()
                        .onSubmit { focused = false }
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
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(Array(genres.enumerated()), id: \.offset) { i, genre in
                                Button { query = genre; scope = "Catalogue"; focused = false } label: {
                                    ZStack(alignment: .bottomLeading) {
                                        Palette.surface
                                        Image(systemName: ["waveform", "pianokeys", "mic.fill", "guitars.fill", "pianokeys", "sparkles"][i])
                                            .font(.system(size: 30, weight: .light)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing).padding(13)
                                        Text(genre).font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary).padding(13)
                                    }.frame(height: 88).clipShape(RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain)
                            }
                        }
                        Text("Chansons du catalogue YouTube Music : artistes, albums et pochettes. Invidious est utilisé uniquement pour récupérer l’audio. Aucune clé API requise.")
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
                        SectionHeading(title: "\(tracks.count) titres", subtitle: scope == "Catalogue" ? "YouTube Music · chansons" : "Dans ta bibliothèque")
                        ForEach(tracks) { track in
                            TrackRow(track: track, context: tracks) {
                                let saved = library.add(track)
                                player.play(saved, in: tracks.map { $0.id == track.id ? saved : $0 })
                                focused = false
                            }
                        }
                        if scope == "Catalogue", continuation != nil {
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
        .onDisappear { pageTask?.cancel(); prefetchTask?.cancel() }
    }
    private func search() async {
        prefetchTask?.cancel()
        error = nil; loading = false; results = []; continuation = nil; loadingMore = false
        guard scope == "Catalogue", !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        loading = true
        do {
            try await Task.sleep(for: .milliseconds(650))
            let found = try await MusicCatalogService().search(query)
            try Task.checkCancellation()
            results = found.tracks; loading = false; continuation = found.continuation
            let settings = library.settings
            prefetchTask = Task {
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                await InvidiousAudioLoader.prefetch(found.tracks, settings: settings)
            }
        } catch is CancellationError { }
        catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
    }
    private func loadMore() async {
        guard let token = continuation else { return }
        let key = searchKey
        loadingMore = true
        defer { if key == searchKey { loadingMore = false } }
        do {
            let found = try await MusicCatalogService().search(query, continuation: token)
            try Task.checkCancellation()
            guard key == searchKey else { return }
            let ids = Set(results.map(\.location))
            let new = found.tracks.filter { !ids.contains($0.location) }
            results.append(contentsOf: new); continuation = new.isEmpty ? nil : found.continuation
        } catch { if !Task.isCancelled, key == searchKey { library.error = error.localizedDescription } }
    }
}
