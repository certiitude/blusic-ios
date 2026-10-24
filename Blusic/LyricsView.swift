import SwiftUI
import UniformTypeIdentifiers

struct LyricsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var track: Track
    @State private var raw = ""
    @State private var loading = false
    @State private var message: String?
    @State private var importing = false
    @State private var autoScroll = true
    @State private var fetchTask: Task<Void, Never>?
    private var lines: [LyricLine] { LRCParser.parse(raw) }
    private var activeLine: Int? {
        lines.last { $0.time <= player.position + library.settings.lyricsOffset }?.id
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if raw.isEmpty {
                Spacer()
                Image(systemName: "quote.bubble").font(.system(size: 32, weight: .light)).foregroundStyle(.white.opacity(0.6))
                Text(message ?? (track.artist == "Blusic Studio" ? "Un instrumental.\nJuste les notes." : "Les mots derrière\nla musique."))
                    .font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.85))
                if loading { ProgressView().tint(.white).padding(.top, 8) }
                else {
                    HStack {
                        Button("Rechercher les paroles") { fetchTask?.cancel(); fetchTask = Task { await fetch() } }.font(.caption.bold()).buttonStyle(.bordered)
                        Button { importing = true } label: { Image(systemName: "square.and.arrow.down").frame(width: 44, height: 44) }.accessibilityLabel("Importer des paroles LRC")
                    }.tint(.white)
                    Text("Recherche via LRCLIB · Import .lrc ou .txt").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
            } else {
                HStack {
                    Text(lines.isEmpty ? "PAROLES" : "PAROLES SYNCHRONISÉES").font(.system(size: 9, weight: .bold)).tracking(1.6).foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Menu {
                        Toggle("Défilement automatique", isOn: $autoScroll)
                        Button("Avancer les paroles de 0,5 s") { library.settings.lyricsOffset += 0.5 }
                        Button("Retarder les paroles de 0,5 s") { library.settings.lyricsOffset -= 0.5 }
                        Button("Réinitialiser le décalage") { library.settings.lyricsOffset = 0 }
                        Button("Importer un fichier .lrc") { importing = true }
                        Button("Actualiser depuis LRCLIB") { fetchTask?.cancel(); fetchTask = Task { await fetch() } }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 30) }.tint(.white)
                }
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 22) {
                            if lines.isEmpty { Text(raw).font(.system(size: 26, weight: .bold, design: .rounded)).lineSpacing(9).foregroundStyle(.white.opacity(0.85)) }
                            else {
                                ForEach(lines) { line in
                                    Button { if track.isNative { player.seek(to: max(0, line.time - library.settings.lyricsOffset)) } } label: {
                                        Text(line.text.isEmpty ? "♪" : line.text)
                                            .font(.system(size: 27, weight: .bold, design: .rounded)).tracking(-0.4)
                                            .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                                            .foregroundStyle(.white.opacity(activeLine == line.id ? 1 : 0.30))
                                            .blur(radius: activeLine == line.id || reduceMotion ? 0 : 0.25)
                                    }.buttonStyle(.plain).id(line.id)
                                }
                            }
                        }.padding(.vertical, 15).padding(.bottom, 100)
                    }
                    .onChange(of: activeLine) { _, line in
                        guard autoScroll, let line else { return }
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) { proxy.scrollTo(line, anchor: .center) }
                    }
                }
            }
        }
        .task(id: "\(track.id)|\(track.title)|\(track.artist)|\(track.album)") {
            fetchTask?.cancel()
            raw = (library.track(track.id)?.lyrics ?? track.lyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines); message = nil
            if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, track.source != .bundled { await fetch() }
        }
        .onDisappear { fetchTask?.cancel() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .data]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size < 2_000_000 else { throw BlusicError.message("Ce fichier de paroles dépasse 2 Mo.") }
                raw = try String(contentsOf: url, encoding: .utf8)
                cache()
            } catch { message = error.localizedDescription }
        }
    }
    private func fetch() async {
        loading = true
        defer { loading = false }
        do {
            var lookup = track
            if lookup.musicCatalog != "youtube-music", lookup.isYouTubeContent || lookup.artist.isEmpty || lookup.artist == "Artiste inconnu" {
                let parts = lookup.title.components(separatedBy: " - ")
                if parts.count >= 2, !parts[0].isEmpty {
                    lookup.artist = parts[0]; lookup.title = parts.dropFirst().joined(separator: " - "); lookup.album = ""
                }
            }
            if lookup.duration <= 0 { lookup.duration = player.duration }
            guard let result = try await LyricsService().fetch(for: lookup) else {
                message = "Paroles introuvables.\nImporte ton fichier .lrc."; return
            }
            try Task.checkCancellation()
            if result.instrumental == true { raw = ""; message = "Un instrumental.\nJuste les notes."; return }
            raw = result.text ?? ""
            if raw.isEmpty { message = "Pas de paroles disponibles pour ce titre." }
            cache()
        } catch { if !Task.isCancelled { message = error.localizedDescription } }
    }
    private func cache() {
        if let index = library.tracks.firstIndex(where: { $0.id == track.id }) { library.tracks[index].lyrics = raw }
    }
}
