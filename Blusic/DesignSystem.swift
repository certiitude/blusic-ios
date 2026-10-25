import SwiftUI
import AVKit
import ImageIO

enum Palette {
    static let background = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.035, green: 0.035, blue: 0.035, alpha: 1)
        : UIColor(red: 0.957, green: 0.965, blue: 0.98, alpha: 1) })
    static let surface = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.075, green: 0.075, blue: 0.075, alpha: 1) : .white })
    static let line = Color.primary.opacity(0.07)
}

enum ArtworkURL {
    /// Resize only the documented-size suffix on trusted Google image hosts.
    /// Other providers' signed image URLs are kept intact.
    static func highResolution(_ url: URL, pixels: Int = 1024, square: Bool = true) -> URL {
        let hosts = ["lh3.googleusercontent.com", "yt3.googleusercontent.com", "lh3.ggpht.com", "yt3.ggpht.com"]
        guard hosts.contains(url.host?.lowercased() ?? ""), url.query == nil,
              let equal = url.absoluteString.lastIndex(of: "=") else { return url }
        let suffix = String(url.absoluteString[url.absoluteString.index(after: equal)...])
        guard suffix.range(of: #"^(w\d+|s\d+)"#, options: .regularExpression) != nil else { return url }
        var height = pixels
        if !square, let regex = try? NSRegularExpression(pattern: #"w(\d+)-h(\d+)"#),
           let match = regex.firstMatch(in: suffix, range: NSRange(suffix.startIndex..., in: suffix)),
           let wr = Range(match.range(at: 1), in: suffix), let hr = Range(match.range(at: 2), in: suffix),
           let width = Double(suffix[wr]), let originalHeight = Double(suffix[hr]), width > 0 {
            height = max(1, Int((Double(pixels) * originalHeight / width).rounded()))
        }
        return URL(string: String(url.absoluteString[..<equal]) + "=w\(pixels)-h\(height)-l95-rj") ?? url
    }
}

struct BlusicMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        p.move(to: pt(0.30, 0.08))
        p.addCurve(to: pt(0.91, 0.36), control1: pt(0.54, -0.01), control2: pt(0.88, 0.15))
        p.addCurve(to: pt(0.65, 0.92), control1: pt(0.99, 0.53), control2: pt(0.83, 0.90))
        p.addCurve(to: pt(0.08, 0.69), control1: pt(0.47, 1.01), control2: pt(0.09, 0.88))
        p.addCurve(to: pt(0.30, 0.08), control1: pt(0.01, 0.56), control2: pt(0.14, 0.17)); p.closeSubpath()
        p.move(to: pt(0.52, 0.29))
        p.addCurve(to: pt(0.64, 0.60), control1: pt(0.59, 0.20), control2: pt(0.61, 0.44))
        p.addCurve(to: pt(0.54, 0.63), control1: pt(0.65, 0.70), control2: pt(0.55, 0.71))
        p.addCurve(to: pt(0.52, 0.29), control1: pt(0.51, 0.56), control2: pt(0.51, 0.38)); p.closeSubpath()
        p.move(to: pt(0.72, 0.29))
        p.addCurve(to: pt(0.82, 0.45), control1: pt(0.78, 0.24), control2: pt(0.82, 0.36))
        p.addCurve(to: pt(0.76, 0.51), control1: pt(0.85, 0.53), control2: pt(0.78, 0.56))
        p.addCurve(to: pt(0.72, 0.29), control1: pt(0.73, 0.46), control2: pt(0.72, 0.35)); p.closeSubpath()
        return p
    }
}

struct GlassSurface: ViewModifier {
    var radius: CGFloat = 24
    func body(content: Content) -> some View {
        // iOS 26's actual Liquid Glass; older SDKs compile the material fallback.
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else { fallback(content) }
        #else
        fallback(content)
        #endif
    }
    private func fallback(_ content: Content) -> some View {
        content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(.white.opacity(0.12), lineWidth: 0.5))
    }
}

extension View {
    func blusicGlass(radius: CGFloat = 24) -> some View { modifier(GlassSurface(radius: radius)) }
    func pagePadding() -> some View { padding(.horizontal, 22) }
    func surface(radius: CGFloat = 20) -> some View {
        background(Palette.surface, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Palette.line, lineWidth: 0.5))
    }
}

struct ArtworkView: View {
    @Environment(\.displayScale) private var displayScale
    @State private var loadedImage: UIImage?
    @State private var loadedRequest: ArtworkRequest?
    var track: Track?
    var size: CGFloat? = nil
    var radius: CGFloat = 14
    var artworkURL: URL? = nil
    var square = true
    var maximumPixels = 1024
    @ViewBuilder private var sizing: some View {
        if square { Color.clear.aspectRatio(1, contentMode: .fit) }
        else { Color.clear }
    }
    var body: some View {
        sizing
            .overlay {
                GeometryReader { geometry in
                    ZStack {
                        Image(track?.artwork ?? "cover-night").resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        if let url = artworkURL ?? track?.artworkURL {
                            let pixels = ArtworkRequest.pixelSize(points: max(geometry.size.width, geometry.size.height), scale: displayScale, maximum: maximumPixels)
                            let request = ArtworkRequest(url: url, pixels: pixels, square: square)
                            Group {
                                if loadedRequest == request, let loadedImage {
                                    Image(uiImage: loadedImage).resizable().scaledToFill()
                                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                                } else { Color.clear }
                            }.task(id: request) {
                                let image = await ArtworkImageCache.shared.image(for: request)
                                guard !Task.isCancelled else { return }
                                loadedImage = image; loadedRequest = request
                            }
                        }
                    }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct ArtworkRequest: Hashable, Sendable {
    var url: URL
    var pixels: Int
    var square = true
    static func pixelSize(points: CGFloat, scale: CGFloat, maximum: Int = 1024) -> Int {
        let requested = max(1, Int(ceil(points * scale)))
        return min(maximum, [128, 256, 512, 1024].first { $0 >= requested } ?? 1024)
    }
}

/// Decode and downsample away from the UI; reuse decoded thumbnails between rows.
actor ArtworkImageCache {
    static let shared = ArtworkImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private var pending: [ArtworkRequest: Task<UIImage?, Never>] = [:]
    private let session: URLSession
    init(session: URLSession? = nil) {
        cache.totalCostLimit = 48 * 1024 * 1024
        cache.countLimit = 160
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 7; config.timeoutIntervalForResource = 15
            config.httpMaximumConnectionsPerHost = 4
            config.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 64 * 1024 * 1024, diskPath: "BlusicArtwork")
            self.session = URLSession(configuration: config)
        }
    }
    func image(for request: ArtworkRequest) async -> UIImage? {
        let key = "\(request.url.absoluteString)|\(request.pixels)|\(request.square)" as NSString
        if let image = cache.object(forKey: key) { return image }
        if let work = pending[request] { return await work.value }
        let session = session
        let work = Task.detached(priority: .utility) { () -> UIImage? in
            let preferred = request.url.isFileURL ? request.url : ArtworkURL.highResolution(request.url, pixels: request.pixels, square: request.square)
            for url in preferred == request.url ? [preferred] : [preferred, request.url] {
                do {
                    let data: Data
                    if url.isFileURL { data = try Data(contentsOf: url, options: .mappedIfSafe) }
                    else {
                        let result = try await session.data(from: url)
                        guard let http = result.1 as? HTTPURLResponse, (200...299).contains(http.statusCode) else { continue }
                        data = result.0
                    }
                    if let image = Self.downsample(data, pixels: request.pixels) { return image }
                } catch { continue }
            }
            return nil
        }
        pending[request] = work
        let image = await work.value
        pending[request] = nil
        if let image {
            let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? request.pixels * request.pixels * 4
            cache.setObject(image, forKey: key, cost: cost)
        }
        return image
    }
    nonisolated static func downsample(_ data: Data, pixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, pixels), kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

struct IconButton: View {
    var symbol: String
    var label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44).contentShape(Circle())
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }
}

struct SectionHeading: View {
    var title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 23, weight: .bold)).tracking(-0.5)
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TrackRow: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayer.self) private var player
    var track: Track
    var context: [Track] = []
    var rank: Int? = nil
    var action: (() -> Void)? = nil
    var isCurrent: Bool { player.current?.id == track.id }

    var body: some View {
        HStack(spacing: 12) {
            if let rank { Text(String(rank)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 20) }
            Button {
                if let action { action() } else { player.play(track, in: context.isEmpty ? library.tracks : context) }
            } label: {
                HStack(spacing: 13) {
                    ArtworkView(track: track, size: library.settings.compactRows ? 44 : 52, radius: 10)
                        .overlay { if isCurrent && player.isPlaying { Image(systemName: "waveform").foregroundStyle(.white).padding(9).background(.black.opacity(0.5), in: Circle()) } }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(track.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(isCurrent ? library.settings.color : .primary).lineLimit(1)
                        HStack(spacing: 4) {
                            if track.isExplicit { Image(systemName: "e.square.fill").font(.system(size: 10)) }
                            Text(track.subtitle).lineLimit(1)
                            if track.source == .unresolved || track.source == .catalogReference { Image(systemName: "link.badge.plus").accessibilityLabel("Source à associer") }
                            if track.isYouTubeContent { Image(systemName: track.source == .invidious ? "network" : "play.rectangle").accessibilityLabel(track.sourceLabel) }
                        }.font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            Menu {
                TrackActions(track: track)
            } label: { Image(systemName: "ellipsis").frame(width: 40, height: 44).contentShape(Rectangle()) }
                .tint(.secondary).accessibilityLabel("Options pour \(track.title)")
        }
        .padding(.vertical, library.settings.compactRows ? 4 : 6)
    }
}

struct TrackActions: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayer.self) private var player
    var track: Track
    var body: some View {
        Button { library.toggleFavorite(track) } label: {
            Label(library.isFavorite(track) ? "Retirer des favoris" : "Ajouter aux favoris", systemImage: "heart")
        }
        Button { player.enqueue(track, next: true) } label: { Label("Écouter ensuite", systemImage: "text.line.first.and.arrowtriangle.forward") }
        Button { player.enqueue(track) } label: { Label("Ajouter à la file", systemImage: "text.badge.plus") }
        Menu {
            if library.playlists.isEmpty { Text("Crée une playlist dans la bibliothèque") }
            ForEach(library.playlists) { playlist in Button(playlist.name) { library.add(track, to: playlist) } }
        } label: { Label("Ajouter à une playlist", systemImage: "plus.square.on.square") }
        if let artistID = track.artistID {
            Button { library.requestedArtist = MusicArtist(id: artistID, name: track.subtitle) } label: { Label("Voir l’artiste", systemImage: "person.crop.circle") }
        }
        if track.isYouTubeContent, let url = URL(string: "https://\(track.musicCatalog == "youtube-music" ? "music.youtube.com" : "www.youtube.com")/watch?v=\(track.location)") {
            Button { player.openOfficialPlayer(for: track) } label: { Label("Ouvrir le lecteur officiel", systemImage: "play.rectangle") }
            ShareLink(item: url) { Label("Partager", systemImage: "square.and.arrow.up") }
        } else if track.source == .local, let url = library.nativeURL(for: track) {
            ShareLink(item: url) { Label("Partager le fichier", systemImage: "square.and.arrow.up") }
        }
    }
}

struct AirPlayPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .secondaryLabel
        view.activeTintColor = .systemBlue
        view.prioritizesVideoDevices = false
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

struct EmptyState: View {
    var symbol: String
    var title: String
    var message: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 38, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(.title3.bold())
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(32).frame(maxWidth: .infinity)
    }
}
