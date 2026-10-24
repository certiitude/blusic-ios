import SwiftUI
import AVKit

enum Palette {
    static let background = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.027, green: 0.031, blue: 0.043, alpha: 1)
        : UIColor(red: 0.957, green: 0.965, blue: 0.98, alpha: 1) })
    static let surface = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.075, green: 0.083, blue: 0.105, alpha: 1) : .white })
    static let line = Color.primary.opacity(0.07)
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
    var track: Track?
    var size: CGFloat? = nil
    var radius: CGFloat = 14
    var body: some View {
        ZStack {
            Image(track?.artwork ?? "cover-night").resizable().scaledToFill()
            if let url = track?.artworkURL {
                if url.isFileURL, let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if !url.isFileURL {
                    AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
                }
            }
        }
        .frame(width: size, height: size)
        .aspectRatio(1, contentMode: .fit)
        .clipped().clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .accessibilityHidden(true)
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
            Text(title).font(.system(size: 23, weight: .bold, design: .rounded)).tracking(-0.5)
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TrackRow: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
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
                            if track.source == .unresolved { Image(systemName: "link.badge.plus").accessibilityLabel("Source à associer") }
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
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    var track: Track
    var body: some View {
        Button { library.toggleFavorite(track) } label: {
            Label(library.favorites.contains(track.id) ? "Retirer des favoris" : "Ajouter aux favoris", systemImage: "heart")
        }
        Button { player.enqueue(track, next: true) } label: { Label("Écouter ensuite", systemImage: "text.line.first.and.arrowtriangle.forward") }
        Button { player.enqueue(track) } label: { Label("Ajouter à la file", systemImage: "text.badge.plus") }
        Menu {
            if library.playlists.isEmpty { Text("Crée une playlist dans la bibliothèque") }
            ForEach(library.playlists) { playlist in Button(playlist.name) { library.add(track, to: playlist) } }
        } label: { Label("Ajouter à une playlist", systemImage: "plus.square.on.square") }
        if track.isYouTubeContent, let url = URL(string: "https://www.youtube.com/watch?v=\(track.location)") {
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
