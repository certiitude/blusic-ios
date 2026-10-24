import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var showAudioImport = false
    @State private var showPlaylistImport = false
    @State private var showCreate = false
    @State private var playlistName = ""
    @State private var section = "Playlists"
    private let sections = ["Playlists", "Titres", "Artistes", "Hors ligne"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Bibliothèque").font(.system(size: 27, weight: .bold)).tracking(-0.8)
                        Spacer()
                        Menu {
                            Button { showAudioImport = true } label: { Label("Importer des fichiers audio", systemImage: "square.and.arrow.down") }
                            Button { showPlaylistImport = true } label: { Label("Importer une playlist", systemImage: "arrow.down.doc") }
                            Button { showCreate = true } label: { Label("Créer une playlist", systemImage: "plus") }
                        } label: { Image(systemName: "plus").font(.title3.weight(.medium)).frame(width: 42, height: 42).blusicGlass(radius: 21) }
                            .accessibilityLabel("Ajouter à la bibliothèque")
                    }
                    Text("\(library.tracks.count) titres. Une infinité de moments.").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.top, 18)

                HStack(spacing: 12) {
                    NavigationLink { TrackCollectionView(title: "Titres favoris", subtitle: "Garde le meilleur, tout simplement.", trackIDs: [], kind: .favorites) } label: {
                        smartCard("Favoris", count: library.favorites.count, symbol: "heart.fill", colors: [.pink.opacity(0.8), .purple.opacity(0.6)])
                    }
                    NavigationLink { TrackCollectionView(title: "Récemment ajoutés", subtitle: "Du nouveau dans tes oreilles.", trackIDs: [], kind: .added) } label: {
                        smartCard("Ajouts récents", count: library.tracks.count, symbol: "sparkles", colors: [.blue.opacity(0.8), .cyan.opacity(0.5)])
                    }
                }.buttonStyle(.plain)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(sections, id: \.self) { item in
                            Button { section = item } label: {
                                Text(item).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 15).padding(.vertical, 10)
                                    .foregroundStyle(section == item ? Palette.background : .secondary)
                                    .background(section == item ? Color.primary : Palette.surface, in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                switch section {
                case "Playlists": playlists
                case "Artistes": artists
                default:
                    let tracks = section == "Hors ligne" ? library.tracks.filter(\.isOffline) : library.tracks
                    if tracks.isEmpty { EmptyState(symbol: "music.note", title: "Tout commence ici", message: "Ajoute tes premiers fichiers audio avec le bouton +.") }
                    ForEach(tracks) { TrackRow(track: $0, context: tracks) }
                }
            }.pagePadding().padding(.bottom, 24)
        }
        .alert("Nouvelle playlist", isPresented: $showCreate) {
            TextField("Le nom de ta playlist", text: $playlistName)
            Button("Créer") {
                let name = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { library.createPlaylist(name); playlistName = "" }
            }
            Button("Annuler", role: .cancel) { playlistName = "" }
        }
        .sheet(isPresented: $showPlaylistImport) { NavigationStack { ImportPlaylistView() } }
        .fileImporter(isPresented: $showAudioImport, allowedContentTypes: [.audio, UTType(filenameExtension: "flac") ?? .audio], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await library.importAudio(urls) }
            case .failure(let error): library.error = error.localizedDescription
            }
        }
    }
    private var playlists: some View {
        VStack(spacing: 16) {
            ForEach(library.playlists) { playlist in
                NavigationLink {
                    TrackCollectionView(title: playlist.name, subtitle: playlist.detail, trackIDs: playlist.trackIDs, kind: .playlist(playlist.id))
                } label: {
                    HStack(spacing: 15) {
                        PlaylistArtwork(tracks: library.tracks(in: playlist)).frame(width: 72, height: 72)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(playlist.name).font(.system(size: 16, weight: .semibold))
                            Text("\(playlist.trackIDs.count) titres · Playlist").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                }.buttonStyle(.plain)
                    .contextMenu { Button("Supprimer la playlist", role: .destructive) { library.playlists.removeAll { $0.id == playlist.id } } }
            }
            Button { showPlaylistImport = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.doc").font(.title2).foregroundStyle(library.settings.color)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Toute ta musique, réunie.").font(.system(size: 14, weight: .semibold))
                        Text("YouTube, CSV, M3U et sauvegardes.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(18).surface()
            }.buttonStyle(.plain).padding(.top, 8)
        }
    }
    private var artists: some View {
        let names = Array(Set(library.tracks.map(\.subtitle))).sorted()
        return VStack(spacing: 20) {
            ForEach(library.followedArtists) { artist in
                NavigationLink { ArtistView(name: artist.name, artistID: artist.id, initialArtworkURL: artist.artworkURL) } label: {
                    HStack(spacing: 14) {
                        ArtworkView(track: nil, size: 64, radius: 32, artworkURL: artist.artworkURL)
                        VStack(alignment: .leading, spacing: 5) { Text(artist.name).font(.headline); Text("Suivi dans Blusic").font(.caption).foregroundStyle(.secondary) }
                        Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain)
            }
            ForEach(names, id: \.self) { name in
                NavigationLink { ArtistView(name: name) } label: {
                    HStack(spacing: 14) {
                        ArtworkView(track: library.tracks.first { $0.subtitle == name }, size: 64, radius: 32)
                        Text(name).font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain)
            }
        }
    }
    private func smartCard(_ title: String, count: Int, symbol: String, colors: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: symbol).font(.system(size: 23)).foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                Text("\(count) titres").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(19)
            .surface(radius: 12)
    }
}

struct PlaylistArtwork: View {
    var tracks: [Track]
    var body: some View {
        GeometryReader { geometry in
            if tracks.isEmpty {
                ZStack {
                    LinearGradient(colors: [.indigo.opacity(0.6), .blue.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note.list").font(.system(size: geometry.size.width * 0.32)).foregroundStyle(.white)
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
                    ForEach(0..<4) { index in ArtworkView(track: tracks[index % tracks.count], size: (geometry.size.width - 2) / 2, radius: 0) }
                }
            }
        }.clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

enum CollectionKind: Equatable {
    case favorites, recent, added, playlist(UUID), fixed
}

struct TrackCollectionView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss
    var title: String
    var subtitle: String
    var trackIDs: [UUID]
    var kind: CollectionKind = .fixed
    @State private var sort = "Ordre original"
    @State private var query = ""
    @State private var rename = false
    @State private var name = ""
    @State private var exporting: URL?
    @State private var showShare = false
    @State private var addingTracks = false

    private var playlist: Playlist? {
        if case let .playlist(id) = kind { return library.playlists.first { $0.id == id } }; return nil
    }
    private var resolvedTitle: String { playlist?.name ?? title }
    private var tracks: [Track] {
        var items: [Track]
        switch kind {
        case .favorites: items = library.likedTracks
        case .recent: items = library.recentTracks
        case .added: items = library.tracks.sorted { $0.addedAt > $1.addedAt }
        case .playlist: items = playlist.map { library.tracks(in: $0) } ?? []
        case .fixed: items = trackIDs.compactMap { library.track($0) }
        }
        if !query.isEmpty { items = items.filter { "\($0.title) \($0.subtitle)".localizedStandardContains(query) } }
        switch sort {
        case "Titre": items.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case "Artiste": items.sort { $0.subtitle.localizedStandardCompare($1.subtitle) == .orderedAscending }
        case "Plus récents": items.sort { $0.addedAt > $1.addedAt }
        default: break
        }
        return items
    }
    var body: some View {
        List {
            Section {
                VStack(spacing: 18) {
                    PlaylistArtwork(tracks: tracks).frame(width: 180, height: 180).shadow(color: .black.opacity(0.2), radius: 20, y: 12)
                    VStack(spacing: 7) {
                        Text(resolvedTitle).font(.system(size: 29, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Text("\(tracks.count) titres · \(Int(tracks.reduce(0) { $0 + $1.duration } / 60)) min").font(.caption).foregroundStyle(.tertiary)
                    }
                    HStack(spacing: 12) {
                        Button { if let first = tracks.first { player.shuffle = false; player.play(first, in: tracks) } } label: {
                            Label("Écouter", systemImage: "play.fill").frame(maxWidth: .infinity).padding(.vertical, 13)
                        }.buttonStyle(.plain).foregroundStyle(Palette.background).background(.primary, in: RoundedRectangle(cornerRadius: 14))
                        Button { if let first = tracks.randomElement() { player.shuffle = true; player.play(first, in: tracks) } } label: {
                            Label("Aléatoire", systemImage: "shuffle").frame(maxWidth: .infinity).padding(.vertical, 13)
                        }.buttonStyle(.plain).foregroundStyle(library.settings.color).surface(radius: 14)
                    }.font(.system(size: 14, weight: .semibold)).disabled(tracks.isEmpty)
                }.padding(.vertical, 20)
            }.listRowBackground(Color.clear).listRowSeparator(.hidden)
            Section {
                if tracks.isEmpty { EmptyState(symbol: "music.note", title: "Un espace à remplir", message: "Ajoute des morceaux depuis le menu d’un titre ou le bouton +.") }
                ForEach(tracks) { TrackRow(track: $0, context: tracks).listRowBackground(Color.clear) }
                    .onDelete(perform: playlist == nil ? nil : delete)
                    .onMove(perform: playlist == nil || sort != "Ordre original" || !query.isEmpty ? nil : move)
            } header: {
                HStack {
                    Text("Titres")
                    Spacer()
                    Menu {
                        Picker("Trier", selection: $sort) { ForEach(["Ordre original", "Titre", "Artiste", "Plus récents"], id: \.self) { Text($0) } }
                    } label: { Image(systemName: "arrow.up.arrow.down") }
                }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden).background(Palette.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .searchable(text: $query, prompt: "Dans cette sélection")
        .toolbar {
            if playlist != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { addingTracks = true } label: { Label("Ajouter des titres", systemImage: "plus") }
                        Button { name = resolvedTitle; rename = true } label: { Label("Renommer", systemImage: "pencil") }
                        Button { exportCSV() } label: { Label("Exporter en CSV", systemImage: "square.and.arrow.up") }
                        Button("Supprimer la playlist", role: .destructive) {
                            if let playlist { library.playlists.removeAll { $0.id == playlist.id }; dismiss() }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
        .alert("Renommer", isPresented: $rename) {
            TextField("Nom", text: $name)
            Button("Enregistrer") {
                if let playlist, let i = library.playlists.firstIndex(where: { $0.id == playlist.id }), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { library.playlists[i].name = name }
            }
            Button("Annuler", role: .cancel) {}
        }
        .sheet(isPresented: $showShare) { if let exporting { ShareSheet(items: [exporting]) } }
        .sheet(isPresented: $addingTracks) {
            NavigationStack {
                List(library.tracks) { track in
                    Button { if let playlist { library.add(track, to: playlist) } } label: {
                        HStack { Text(track.title); Spacer(); Image(systemName: playlist?.trackIDs.contains(track.id) == true ? "checkmark.circle.fill" : "plus.circle") }
                    }
                }.navigationTitle("Ajouter des titres").toolbar { Button("Terminé") { addingTracks = false } }
            }
        }
    }
    private func delete(_ offsets: IndexSet) {
        guard let playlist, let index = library.playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        let ids = Set(offsets.map { tracks[$0].id })
        library.playlists[index].trackIDs.removeAll { ids.contains($0) }
    }
    private func move(_ offsets: IndexSet, _ destination: Int) {
        guard let playlist, let index = library.playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        library.playlists[index].trackIDs.move(fromOffsets: offsets, toOffset: destination)
    }
    private func exportCSV() {
        func quote(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let rows = tracks.map { track -> String in
            let link = track.isYouTubeContent ? "https://\(track.musicCatalog == "youtube-music" ? "music.youtube.com" : "www.youtube.com")/watch?v=\(track.location)" : track.source == .remote ? track.location : ""
            return [track.title, track.artist, track.album, link].map(quote).joined(separator: ",")
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Blusic-playlist.csv")
        do {
            try ("title,artist,album,url\n" + rows.joined(separator: "\n")).write(to: url, atomically: true, encoding: .utf8)
            exporting = url; showShare = true
        } catch { library.error = error.localizedDescription }
    }
}

struct ArtistView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    var name: String
    var artistID: String? = nil
    var initialArtworkURL: URL? = nil
    @State private var profile: ArtistProfile?
    @State private var loading = false
    @State private var error: String?
    private var tracks: [Track] { profile?.tracks ?? library.tracks.filter { $0.subtitle == name } }
    private var artist: MusicArtist { profile?.artist ?? MusicArtist(id: artistID ?? "", name: name, artworkURL: initialArtworkURL) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ZStack(alignment: .bottomLeading) {
                    ArtworkView(track: tracks.first, radius: 0, artworkURL: artist.artworkURL).frame(height: 300).clipped()
                    LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 10) {
                        Label(profile == nil ? "TA BIBLIOTHÈQUE" : "YOUTUBE MUSIC", systemImage: "music.note").font(.system(size: 10, weight: .bold)).tracking(1)
                        Text(artist.name).font(.system(size: 36, weight: .bold)).tracking(-1)
                    }.padding(23).foregroundStyle(.white)
                }.frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 24))
                HStack {
                    Button { if let track = tracks.first { player.play(track, in: tracks) } } label: {
                        Label("Écouter", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 9)
                    }.buttonStyle(.borderedProminent).tint(library.settings.color).disabled(tracks.isEmpty)
                    if !artist.id.isEmpty {
                        Button { library.toggleFollow(artist) } label: {
                            Label(library.followedArtists.contains(where: { $0.id == artist.id }) ? "Suivi" : "Suivre", systemImage: "person.badge.plus")
                        }.buttonStyle(.bordered)
                    }
                }
                if loading { ProgressView("Chargement du profil…") }
                if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
                if let bio = profile?.biography, !bio.isEmpty {
                    VStack(alignment: .leading, spacing: 9) { Text("À propos").font(.headline); Text(bio).font(.subheadline).foregroundStyle(.secondary).lineLimit(8) }.padding(16).surface(radius: 12)
                }
                SectionHeading(title: "Titres", subtitle: profile == nil ? "Dans ta collection" : "Chansons du catalogue")
                ForEach(tracks) { TrackRow(track: $0, context: tracks) }
            }.pagePadding().padding(.bottom, 24)
        }.background(Palette.background).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .task(id: artistID ?? name) {
            loading = true; error = nil
            defer { loading = false }
            do {
                let service = MusicCatalogService()
                let target: MusicArtist
                if let artistID { target = MusicArtist(id: artistID, name: name, artworkURL: initialArtworkURL) }
                else {
                    let found = try await service.searchArtists(name)
                    guard let match = found.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) ?? found.first else { return }
                    target = match
                }
                profile = try await service.artist(target)
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
