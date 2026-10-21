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
                Text("Les exports CSV Soundiiz et TuneMyMusic permettent de transférer les listes de Spotify, Apple Music, Deezer et d’autres services. Les fichiers audio ne sont pas inclus : les titres sans source devront être associés à tes fichiers.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Depuis YouTube") {
                TextField("Lien d’une playlist publique", text: $link).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button { importYouTube() } label: { Label("Récupérer les titres", systemImage: "play.rectangle") }.disabled(link.isEmpty || busy)
                Text("YouTube et YouTube Music : lien public avec list=. Une clé YouTube Data API est à renseigner dans les réglages. Lecture vidéo officielle au premier plan.").font(.caption).foregroundStyle(.secondary)
            }
            if busy { Section { ProgressView("Préparation de l’import…") } }
            if let error { Section { Text(error).font(.subheadline).foregroundStyle(.red) } }
            if !preview.isEmpty {
                Section("Prêt à importer") {
                    TextField("Nom de la playlist", text: $name)
                    LabeledContent("Titres", value: "\(preview.count)")
                    LabeledContent("Sources à associer", value: "\(preview.filter { $0.source == .unresolved }.count)")
                    Button("Ajouter à Blusic") {
                        library.createPlaylist(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Playlist importée" : name, tracks: matchedTracks())
                        library.notice = "Playlist importée · \(preview.count) titres"
                        dismiss()
                    }.fontWeight(.bold)
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
                name = parsed.name; preview = parsed.tracks
            } catch { self.error = error.localizedDescription }
        }
    }
    private func importYouTube() {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)) else { error = "Ce lien n’est pas valide."; return }
        busy = true; error = nil
        task = Task {
            defer { busy = false }
            do {
                let tracks = try await YouTubeService().playlist(url, key: SecureStore.read("youtube-api-key"))
                try Task.checkCancellation()
                guard !tracks.isEmpty else { throw BlusicError.message("Cette playlist ne contient aucun titre public accessible.") }
                preview = tracks
                if name.isEmpty { name = "Ma playlist YouTube" }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func matchedTracks() -> [Track] {
        preview.map { imported in
            if imported.source == .unresolved, let local = library.tracks.first(where: {
                $0.isNative && PlaylistImporter.normalize($0.title) == PlaylistImporter.normalize(imported.title)
                    && PlaylistImporter.normalize($0.subtitle) == PlaylistImporter.normalize(imported.subtitle)
            }) { return local }
            return imported
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
