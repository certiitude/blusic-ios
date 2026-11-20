import SwiftUI

struct SearchView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayer.self) private var player
    @FocusState private var focused: Bool
    @State private var query = {
        #if DEBUG
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--blusic-query=") }) { return String(argument.dropFirst("--blusic-query=".count)) }
        #endif
        return ""
    }()
    @State private var scope = "Catalogue"
    @State private var category: SearchCategory = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--blusic-kind=artists") { return .artists }
        #endif
        return .songs
    }()
    @State private var search = CatalogSearchModel()
    @State private var history = RecentSearches()
    @State private var retry = 0
    @State private var pageTask: Task<Void, Never>?
    @State private var confirmClear = false
    private var offline: Bool { library.settings.usesOfflinePlaybackOnly }
    private var local: Bool { scope == "Bibliothèque" || offline }
    private var searchKey: String { "\(local)|\(category.rawValue)|\(SearchTerms.clean(query))|\(retry)" }
    private var localResults: [Track] {
        let tracks = offline ? library.tracks.filter { library.downloads.isAvailable($0) } : library.tracks
        return LibraryBrowse.filter(tracks, query: query, sort: .title)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 22) {
                PageTitle(eyebrow: "Une envie, un son", title: "Trouve ton prochain favori.", subtitle: "Un titre, un artiste, une nouvelle direction.")
                searchField
                if offline {
                    Label("Mode hors ligne · recherche dans les titres disponibles", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(library.settings.color)
                } else {
                    Picker("Rechercher dans", selection: $scope) {
                        Text("Catalogue").tag("Catalogue"); Text("Bibliothèque").tag("Bibliothèque")
                    }.pickerStyle(.segmented)
                }
                if !local {
                    HStack(spacing: 8) { ForEach(SearchCategory.allCases, id: \.self) { value in FilterPill(title: value.rawValue, selected: category == value) { category = value } } }
                }
                if SearchTerms.clean(query).isEmpty { suggestions }
                else if !local && search.loading {
                    VStack(spacing: 14) { ProgressView(); Text("On cherche « \(SearchTerms.clean(query)) »…").font(.subheadline).foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity).padding(.vertical, 42).accessibilityIdentifier("search-loading")
                } else if !local, let error = search.error {
                    EmptyState(symbol: "wifi.exclamationmark", title: "Le catalogue ne répond pas", message: error)
                    Button("Réessayer") { retry += 1 }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                } else if !local && category == .artists {
                    artistResults
                } else {
                    songResults
                }
            }.pagePadding().padding(.top, 24).padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .task(id: searchKey) {
            pageTask?.cancel()
            await search.search(query, category: category, offline: local, refresh: retry > 0)
        }
        .onDisappear { pageTask?.cancel(); search.cancel() }
        .confirmationDialog("Effacer les recherches récentes de cet iPhone ?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Effacer l’historique", role: .destructive) { history.clear() }
        }
    }
    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(library.settings.color)
            TextField("Titre, artiste, album…", text: $query).focused($focused).submitLabel(.search).autocorrectionDisabled()
                .onSubmit { history.record(query); focused = false }
                .accessibilityIdentifier("music-search-field")
            if !query.isEmpty {
                Button { query = ""; focused = true } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 44, height: 52) }
                    .accessibilityLabel("Effacer la recherche")
            }
        }.padding(.leading, 16).padding(.trailing, query.isEmpty ? 16 : 0).frame(minHeight: 56).surface(radius: 18)
    }
    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !history.terms.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Tes recherches récentes").font(.headline)
                        Spacer()
                        Button("Effacer") { confirmClear = true }.font(.caption).frame(minHeight: 44)
                    }
                    ForEach(history.terms, id: \.self) { term in
                        HStack {
                            Button { select(term) } label: {
                                HStack(spacing: 14) { Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary); Text(term).lineLimit(1); Spacer() }.frame(minHeight: 48).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Button { history.remove(term) } label: { Image(systemName: "xmark").font(.caption).foregroundStyle(.secondary).frame(width: 44, height: 44) }.accessibilityLabel("Oublier \(term)")
                        }
                    }
                    Text("Sur cet iPhone uniquement. Rien n’est enregistré pendant la frappe.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if local {
                SectionHeading(title: "Tout est déjà chez toi", subtitle: "Recherche aussi par album. Les accents et l’ordre des mots ne bloquent pas la recherche.")
                ForEach(Array((offline ? library.tracks.filter { library.downloads.isAvailable($0) } : library.recentTracks).prefix(6))) { track in
                    TrackRow(track: track, context: localResults)
                }
            } else {
                SectionHeading(title: "Suis ton envie", subtitle: "Quelques portes d’entrée, pas des recommandations inventées.")
                let genres = [("Électronique", "waveform", Color.indigo), ("Jazz", "pianokeys", Color.orange), ("Rap français", "mic.fill", Color.pink), ("Indie", "guitars.fill", Color.mint), ("Piano", "pianokeys", Color.blue), ("Soul", "sparkles", Color.purple)]
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(genres, id: \.0) { genre, symbol, color in
                        Button { select(genre) } label: {
                            VStack(alignment: .leading, spacing: 20) {
                                Image(systemName: symbol).font(.title2).foregroundStyle(color)
                                Text(genre).font(.headline).foregroundStyle(.primary)
                            }.frame(maxWidth: .infinity, minHeight: 90, alignment: .leading).padding(17)
                                .background(LinearGradient(colors: [color.opacity(0.16), Palette.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
    @ViewBuilder private var songResults: some View {
        let tracks = local ? localResults : search.tracks
        if tracks.isEmpty {
            EmptyState(symbol: "magnifyingglass", title: "Pas encore trouvé", message: local ? "Essaie un autre mot ou ajoute de la musique à ta bibliothèque." : "Essaie un titre plus court ou le nom de l’artiste.")
        } else {
            SectionHeading(title: "\(tracks.count) titres", subtitle: local ? "Dans ta musique" : "Chansons YouTube Music")
            ForEach(tracks) { track in
                TrackRow(track: track, context: tracks) { history.record(query); focused = false; player.play(track, in: tracks) }
            }
            if !local, search.continuation != nil {
                if let error = search.pageError { Text(error).font(.caption).foregroundStyle(.secondary) }
                Button {
                    pageTask = Task { await search.loadMore() }
                } label: {
                    HStack(spacing: 10) { if search.loadingMore { ProgressView() }; Text(search.pageError == nil ? "Encore quelques titres" : "Réessayer la suite") }.frame(maxWidth: .infinity, minHeight: 48)
                }.buttonStyle(.bordered).disabled(search.loadingMore)
            }
        }
    }
    @ViewBuilder private var artistResults: some View {
        if search.artists.isEmpty { EmptyState(symbol: "person.crop.circle", title: "Aucun artiste trouvé", message: "Essaie un autre nom.") }
        ForEach(search.artists) { artist in
            NavigationLink { ArtistView(name: artist.name, artistID: artist.id, initialArtworkURL: artist.artworkURL).onAppear { history.record(query) } } label: {
                HStack(spacing: 14) {
                    ArtworkView(track: nil, size: 60, radius: 30, artworkURL: artist.artworkURL)
                    VStack(alignment: .leading, spacing: 5) { Text(artist.name).font(.headline); Text("Artiste · YouTube Music").font(.caption).foregroundStyle(.secondary) }
                    Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }.buttonStyle(.plain)
        }
    }
    private func select(_ text: String) { history.record(text); query = text; scope = "Catalogue"; focused = false }
}
