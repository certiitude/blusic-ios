import SwiftUI
import WebKit

struct YouTubePlayerView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    var track: Track
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                YouTubeEmbed(videoID: track.location, isActive: scenePhase == .active)
                    .frame(height: 230)
                VStack(alignment: .leading, spacing: 8) {
                    Label("YOUTUBE", systemImage: "play.rectangle.fill").font(.system(size: 10, weight: .bold)).tracking(1.6).foregroundStyle(.red)
                    Text(track.title).font(.title2.bold())
                    Text(track.subtitle).foregroundStyle(.secondary)
                }
                HStack {
                    Button { library.toggleFavorite(track) } label: { Label("Favori", systemImage: library.isFavorite(track) ? "heart.fill" : "heart") }.buttonStyle(.bordered)
                    Menu { TrackActions(track: track) } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                }
                Text("La lecture utilise le lecteur officiel YouTube. Lance la vidéo avec son bouton de lecture. Les publicités, la disponibilité et les restrictions sont définies par YouTube. L’audio YouTube n’est pas extrait et ne passe pas par l’égaliseur natif.")
                    .font(.subheadline).foregroundStyle(.secondary).lineSpacing(5)
                if let url = URL(string: "https://www.youtube.com/watch?v=\(track.location)") {
                    Link(destination: url) { Label("Ouvrir dans YouTube", systemImage: "arrow.up.right.square") }.buttonStyle(.borderedProminent)
                    Text("Si la vidéo refuse la lecture intégrée, ouvre-la dans YouTube.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(22)
        }.background(Palette.background).navigationTitle("Lecteur YouTube").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
    }
}

struct YouTubeEmbed: UIViewRepresentable {
    var videoID: String
    var isActive: Bool
    final class Coordinator { var videoID: String? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.isOpaque = false; web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        load(web)
        context.coordinator.videoID = videoID
        return web
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.videoID != videoID { load(uiView); context.coordinator.videoID = videoID }
        if !isActive { uiView.evaluateJavaScript("document.querySelector('video')?.pause()", completionHandler: nil) }
    }
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        // Stop playback when the video is no longer visible.
        uiView.loadHTMLString("", baseURL: nil)
    }
    private func load(_ web: WKWebView) {
        guard videoID.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil,
              let url = URL(string: "https://www.youtube.com/embed/\(videoID)?playsinline=1&autoplay=0") else { return }
        var request = URLRequest(url: url)
        let appID = (Bundle.main.bundleIdentifier ?? "app.blusic.ios").lowercased()
        request.setValue("https://\(appID)", forHTTPHeaderField: "Referer")
        web.load(request)
    }
}
