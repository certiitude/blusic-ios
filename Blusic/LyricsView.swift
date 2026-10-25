import SwiftUI
import UniformTypeIdentifiers

struct LyricsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayer.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var track: Track
    @State private var raw = ""
    @State private var loading = false
    @State private var message: String?
    @State private var importing = false
    @State private var autoScroll = true
    @State private var fetchTask: Task<Void, Never>?
    @State private var lines: [LyricLine] = []
    @ScaledMetric(relativeTo: .largeTitle) private var lyricSize = 34.0
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
                    if !lines.isEmpty, !autoScroll {
                        Button("Recentrer") { autoScroll = true }.font(.caption.bold()).tint(.white)
                    }
                    Menu {
                        Toggle("Défilement automatique", isOn: $autoScroll)
                        Button("Avancer les paroles de 0,5 s") { library.settings.lyricsOffset += 0.5 }
                        Button("Retarder les paroles de 0,5 s") { library.settings.lyricsOffset -= 0.5 }
                        Button("Réinitialiser le décalage") { library.settings.lyricsOffset = 0 }
                        Button("Importer un fichier .lrc") { importing = true }
                        Button("Actualiser depuis LRCLIB") { fetchTask?.cancel(); fetchTask = Task { await fetch() } }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 30) }.tint(.white)
                }
                GeometryReader { geometry in
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 28) {
                                if lines.isEmpty {
                                    Text(raw).font(.system(size: lyricSize, weight: .bold, design: .rounded)).lineSpacing(10).foregroundStyle(.white.opacity(0.85))
                                } else {
                                    ForEach(lines) { line in
                                        let distance = abs(line.id - (activeLine ?? lines.first?.id ?? 0))
                                        let selected = line.id == activeLine
                                        Button {
                                            if track.isNative { player.seek(to: max(0, line.time - library.settings.lyricsOffset)); autoScroll = true }
                                        } label: {
                                            Text(line.text.isEmpty ? "♪ ♪ ♪" : line.text)
                                                .font(.system(size: lyricSize, weight: .bold, design: .rounded)).tracking(-0.6)
                                                .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                                                .fixedSize(horizontal: false, vertical: true)
                                                .foregroundStyle(.white.opacity(selected ? 1 : distance <= 1 ? 0.55 : 0.28))
                                                .scaleEffect(reduceMotion || selected ? 1 : 0.94, anchor: .leading)
                                                .blur(radius: reduceMotion || selected ? 0 : distance <= 1 ? 0.3 : 1.2)
                                                .animation(reduceMotion ? nil : .spring(response: 0.65, dampingFraction: 0.85), value: activeLine)
                                        }.buttonStyle(.plain).id(line.id)
                                            .accessibilityLabel("\(line.text), \(line.time.clock)")
                                            .accessibilityAddTraits(selected ? .isSelected : [])
                                    }
                                }
                            }.padding(.vertical, lines.isEmpty ? 18 : geometry.size.height * 0.42)
                        }
                        .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { _ in autoScroll = false })
                        .mask {
                            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.08),
                                .init(color: .black, location: 0.90), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                        }
                        .onChange(of: activeLine) { _, line in
                            guard autoScroll, let line else { return }
                            withAnimation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.88)) { proxy.scrollTo(line, anchor: .center) }
                        }
                        .task(id: "\(raw)|\(autoScroll)") {
                            guard autoScroll else { return }
                            try? await Task.sleep(for: .milliseconds(80))
                            guard !Task.isCancelled else { return }
                            guard let line = activeLine ?? lines.first?.id else { return }
                            proxy.scrollTo(line, anchor: .center)
                        }
                    }
                }
            }
        }
        .onChange(of: raw) { _, text in lines = LRCParser.parse(text); autoScroll = true }
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
