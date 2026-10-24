import SwiftUI
import UniformTypeIdentifiers

struct ImportPlaylistView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var link = ""
    @State private var importingFile = false
    @State private var busy = false
    @State private var preview: [Track] = []
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var matchProgress: String?
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "arrow.triangle.merge").font(.system(size: 32, weight: .light)).foregroundStyle(library.settings.color)
                    Text("Tes playlists.\nUne nouvelle maison.").font(.system(size: 28, weight: .bold, design: .rounded)).tracking(-0.7)
                    Text("Récupère tes sélections, sans repartir de zéro.").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 12)
            }.listRowBackground(Color.clear)
            Section("Depuis un fichier") {
                Button { importingFile = true } label: { Label("Choisir un export CSV ou M3U", systemImage: "doc.badge.arrow.up") }.disabled(busy)
                Text("Spotify, Apple Music et les autres plateformes : utilise un export CSV Soundiiz/TuneMyMusic. Les titres et artistes sont importés, puis peuvent être associés aux chansons YouTube Music avant l’ajout.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Depuis un lien public") {
                TextField("Playlist YouTube, YouTube Music ou Deezer", text: $link).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button { importYouTube() } label: { Label("Récupérer les titres", systemImage: "play.rectangle") }.disabled(link.isEmpty || busy)
                Text("Liens publics Deezer et YouTube/YouTube Music. Pour Spotify et Apple Music, passe par le fichier CSV ci-dessus. Les morceaux Deezer ne sont jamais remplacés par leurs extraits de 30 secondes.").font(.caption).foregroundStyle(.secondary)
            }
            if busy { Section { ProgressView("Préparation de l’import…") } }
            if let matchProgress {
                Section {
                    Text(matchProgress).font(.caption).foregroundStyle(.secondary)
                    if busy { Button("Arrêter l’association") { task?.cancel() } }
                }
            }
            if let error { Section { Text(error).font(.subheadline).foregroundStyle(.red) } }
            if !preview.isEmpty {
                Section("Prêt à importer") {
                    TextField("Nom de la playlist", text: $name)
                    LabeledContent("Titres", value: "\(preview.count)")
                    LabeledContent("À associer au catalogue", value: "\(preview.filter { $0.source == .unresolved || $0.source == .catalogReference }.count)")
                    Button("Associer les titres à YouTube Music") { associatePreview() }.disabled(busy)
                    Button("Ajouter à Blusic") {
                        library.createPlaylist(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Playlist importée" : name, tracks: matchedTracks())
                        library.notice = "Playlist importée · \(preview.count) titres"
                        dismiss()
                    }.fontWeight(.bold).disabled(busy)
                }
                Section("Aperçu") {
                    ForEach(Array(preview.prefix(20))) { track in
                        VStack(alignment: .leading, spacing: 4) { Text(track.title).font(.subheadline.bold()); Text("\(track.subtitle) · \(track.sourceLabel)").font(.caption).foregroundStyle(.secondary) }
                    }
                    if preview.count > 20 { Text("Et \(preview.count - 20) autres titres…").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("Importer une playlist").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { task?.cancel(); dismiss() } } }
        .onDisappear { task?.cancel() }
        .fileImporter(isPresented: $importingFile, allowedContentTypes: [.commaSeparatedText, .plainText, .json, .data]) { result in
            error = nil
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 10_000_000 else { throw BlusicError.message("L’import est limité à 10 Mo.") }
                let data = try Data(contentsOf: url)
                if url.pathExtension.lowercased() == "json" {
                    try library.restoreBackup(data); dismiss(); return
                }
                let parsed = try PlaylistImporter.parse(data, filename: url.lastPathComponent)
                name = parsed.name; preview = references(parsed.tracks); matchProgress = nil
            } catch { self.error = error.localizedDescription }
        }
    }
    private func importYouTube() {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)) else { error = "Ce lien n’est pas valide."; return }
        busy = true; error = nil
        task = Task {
            defer { busy = false }
            do {
                if ["deezer.com", "www.deezer.com", "link.deezer.com", "deezer.page.link"].contains(url.host?.lowercased() ?? "") {
                    let parsed = try await PlatformPlaylistService().deezer(url)
                    try Task.checkCancellation()
                    preview = parsed.tracks
                    if name.isEmpty { name = parsed.name }
                    matchProgress = "Clique sur Associer les titres pour préparer leur lecture sur YouTube Music."
                    return
                }
                if (url.host ?? "").contains("spotify.com") || (url.host ?? "").contains("music.apple.com") {
                    throw BlusicError.message("Pour Spotify et Apple Music, importe un export CSV puis lance l’association YouTube Music. Le lien seul ne donne pas accès à la liste complète de façon fiable.")
                }
                let service = try InvidiousService(address: library.settings.invidiousAddress, automaticFallback: library.settings.usesInvidiousFallback)
                let imported = try await service.playlist(url)
                let tracks = imported.tracks
                try Task.checkCancellation()
                guard !tracks.isEmpty else { throw BlusicError.message("Cette playlist ne contient aucun titre public accessible.") }
                preview = tracks
                if name.isEmpty { name = imported.name }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func matchedTracks() -> [Track] {
        preview.map { imported in
            if imported.source == .unresolved || imported.source == .catalogReference, let local = library.tracks.first(where: {
                $0.isNative && PlaylistImporter.normalize($0.title) == PlaylistImporter.normalize(imported.title)
                    && PlaylistImporter.normalize($0.subtitle) == PlaylistImporter.normalize(imported.subtitle)
            }) { return local }
            return imported
        }
    }
    private func references(_ tracks: [Track]) -> [Track] {
        tracks.map { value in
            var track = value
            if track.source == .unresolved, !track.artist.isEmpty { track.source = .catalogReference }
            return track
        }
    }
    private func associatePreview() {
        busy = true; error = nil
        task = Task {
            defer { busy = false }
            var matched = 0
            let service = MusicCatalogService()
            for index in preview.indices {
                guard !Task.isCancelled else { return }
                guard preview[index].source == .catalogReference || preview[index].source == .unresolved else { continue }
                matchProgress = "Association \(index + 1)/\(preview.count) · \(preview[index].title)"
                if let song = try? await service.match(preview[index]) { preview[index] = song; matched += 1 }
                do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            }
            let remaining = preview.filter { $0.source == .catalogReference || $0.source == .unresolved }.count
            matchProgress = "\(matched) correspondances trouvées · \(remaining) titres à vérifier manuellement."
            await InvidiousAudioLoader.prefetch(preview.filter { $0.source == .invidious }, settings: library.settings)
        }
    }
}

struct MatchReferenceView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss
    var reference: Track
    @State private var results: [Track] = []
    @State private var loading = true
    @State private var error: String?
    var body: some View {
        List {
            Section { Text("Choisis la bonne version de « \(reference.title) » par \(reference.subtitle).").font(.subheadline) }
            if loading { ProgressView("Recherche YouTube Music…") }
            if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
            ForEach(results) { song in
                TrackRow(track: song) {
                    library.replaceSource(of: reference.id, with: song)
                    if let resolved = library.track(reference.id) { player.play(resolved, in: player.queue) }
                    dismiss()
                }
            }
        }.navigationTitle("Associer le morceau").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Fermer") { dismiss() } }
            .task {
                defer { loading = false }
                do {
                    results = try await MusicCatalogService().search("\(reference.title) \(reference.artist)").tracks
                    await InvidiousAudioLoader.prefetch(results, settings: library.settings)
                } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
