import SwiftUI
import UniformTypeIdentifiers

private enum AppTab: String, CaseIterable {
    case home = "Accueil", search = "Recherche", library = "Bibliothèque"
    var symbol: String { switch self { case .home: return "house.fill"; case .search: return "magnifyingglass"; case .library: return "square.stack.fill" } }
}
private enum AppSheet: String, Identifiable {
    case player, settings, statistics, youtube, artist, sound
    var id: String { rawValue }
}

struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayer.self) private var player
    @State private var tab: AppTab = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--blusic-screen=search") { return .search }
        if ProcessInfo.processInfo.arguments.contains("--blusic-screen=library") { return .library }
        #endif
        return .home
    }()
    @State private var sheet: AppSheet?
    @State private var resolveWithFile = false
    @State private var resolutionID: UUID?
    @State private var referenceToMatch: Track?
    @State private var preparedScreenshot = false

    var body: some View {
        navigationTabs
        .background(Palette.background.ignoresSafeArea())
        .sheet(item: $sheet, onDismiss: { player.youtubeTrack = nil; library.requestedArtist = nil }) { item in
            switch item {
            case .player: PlayerView().presentationDragIndicator(.hidden).presentationCornerRadius(30)
            case .settings: NavigationStack { SettingsView() }
            case .statistics: NavigationStack { StatisticsView() }
            case .sound: NavigationStack { SoundSettingsView() }
            case .youtube:
                if let track = player.youtubeTrack ?? player.current { NavigationStack { YouTubePlayerView(track: track) } }
            case .artist:
                if let artist = library.requestedArtist {
                    NavigationStack {
                        ArtistView(name: artist.name, artistID: artist.id, initialArtworkURL: artist.artworkURL)
                            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Terminé") { sheet = nil } } }
                    }
                }
            }
        }
        .onChange(of: player.youtubeTrack) { _, value in if value != nil { sheet = .youtube } }
        .onChange(of: library.requestedArtist) { _, value in if value != nil { sheet = .artist } }
        .confirmationDialog("Associer une source", isPresented: Binding(get: { player.unresolvedTrack != nil }, set: { if !$0 { player.unresolvedTrack = nil } }), titleVisibility: .visible) {
            Button("Trouver le titre sur YouTube Music") { referenceToMatch = player.unresolvedTrack ?? player.current }
            Button("Choisir un fichier audio") { resolutionID = player.current?.id; resolveWithFile = true }
            Button("Annuler", role: .cancel) { player.unresolvedTrack = nil }
        } message: { Text("Choisis une correspondance YouTube Music ou associe ton fichier audio à ce titre importé.") }
        .sheet(item: $referenceToMatch) { reference in NavigationStack { MatchReferenceView(reference: reference) } }
        .fileImporter(isPresented: $resolveWithFile, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result {
                Task { await library.importAudio(urls, replacing: resolutionID) }
            } else if case let .failure(error) = result { library.error = error.localizedDescription }
        }
        .alert("Un petit contretemps", isPresented: Binding(get: { library.error != nil || player.error != nil }, set: { if !$0 { library.error = nil; player.error = nil } })) {
            if player.error != nil, let current = player.current, current.isYouTubeContent {
                Button("Réessayer") { player.error = nil; player.play(current) }
                if library.settings.audioSourceMode != "auto" {
                    Button("Essayer l’accès automatique") { library.settings.onlineAudioMode = "auto"; player.error = nil; player.play(current) }
                }
                Button("Ouvrir le lecteur officiel") { player.error = nil; player.openOfficialPlayer(for: current) }
            }
            Button("Compris") { library.error = nil; player.error = nil }
        } message: { Text(library.error ?? player.error ?? "") }
        .overlay(alignment: .top) {
            if let notice = library.notice {
                Label(notice, systemImage: "checkmark.circle.fill").font(.subheadline.weight(.medium))
                    .padding(16).blusicGlass(radius: 20).padding(.horizontal, 24).padding(.top, 55)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: notice) { try? await Task.sleep(for: .seconds(3)); if library.notice == notice { library.notice = nil } }
                    .onTapGesture { library.notice = nil }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: library.notice)
        .task {
            #if DEBUG
            guard !preparedScreenshot else { return }
            preparedScreenshot = true
            if ProcessInfo.processInfo.arguments.contains("--blusic-lyrics"), let index = library.tracks.firstIndex(where: { $0.source == .bundled }) {
                library.tracks[index].lyrics = "[00:00.00]Chaque note trouve sa place\n[00:04.00]Le rythme suit ton envie\n[00:08.00]Un exemple de paroles\n[00:12.00]Pour vérifier le défilement"
            }
            if ProcessInfo.processInfo.arguments.contains("--blusic-preview-player"), let demo = library.tracks.first(where: { $0.source == .bundled }) {
                player.play(demo, in: [demo]); sheet = .player
            } else if ProcessInfo.processInfo.arguments.contains("--blusic-preview-artist") {
                library.requestedArtist = MusicArtist(id: "UC2ISePqOr39OQ90kNN1WLjA", name: "Niska")
            } else if ProcessInfo.processInfo.arguments.contains("--blusic-preview-sound") {
                sheet = .sound
            } else if ProcessInfo.processInfo.arguments.contains("--blusic-preview-settings") {
                if ProcessInfo.processInfo.arguments.contains("--blusic-high-quality") { library.settings.highQualityAudio = true }
                sheet = .settings
            } else if ProcessInfo.processInfo.arguments.contains("--blusic-preview-mini"), let demo = library.tracks.first(where: { $0.source == .bundled }) {
                player.play(demo, in: [demo]); player.pause()
            }
            #endif
        }
    }

    @ViewBuilder private var navigationTabs: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.1, *) {
            systemTabs.tabViewBottomAccessory(isEnabled: player.current != nil) {
                if let current = player.current { miniPlayer(current) }
            }
        } else if #available(iOS 26.0, *) {
            systemTabs.tabViewBottomAccessory {
                if let current = player.current { miniPlayer(current) }
            }
        } else { systemTabs }
        #else
        systemTabs
        #endif
    }

    private var systemTabs: some View {
        TabView(selection: $tab) {
            tabPage(.home).tabItem { Label("Accueil", systemImage: "house.fill") }.tag(AppTab.home)
            tabPage(.search).tabItem { Label("Recherche", systemImage: "magnifyingglass") }.tag(AppTab.search)
            tabPage(.library).tabItem { Label("Bibliothèque", systemImage: "square.stack.fill") }.tag(AppTab.library)
        }
    }

    private func tabPage(_ selected: AppTab) -> some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Group {
                    switch selected {
                    case .home: HomeView()
                    case .search: SearchView()
                    case .library: LibraryView()
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Palette.background)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { legacyAccessory }
        }
    }

    @ViewBuilder private var legacyAccessory: some View {
        if #available(iOS 26.0, *) { EmptyView() }
        else if let current = player.current { miniPlayer(current).padding(8).background(Palette.background) }
    }

    private var header: some View {
        HStack(spacing: 9) {
            BlusicMark().fill(.primary, style: FillStyle(eoFill: true)).frame(width: 25, height: 25)
            Text("blusic").font(.system(size: 21, weight: .bold)).tracking(-0.7)
            Spacer()
            IconButton(symbol: "chart.bar.xaxis", label: "Statistiques") { sheet = .statistics }.blusicGlass(radius: 22)
            IconButton(symbol: "slider.horizontal.3", label: "Réglages") { sheet = .settings }.blusicGlass(radius: 22)
        }.padding(.leading, 20).padding(.trailing, 10).frame(height: 48).background(Palette.background)
    }

    private func miniPlayer(_ current: Track) -> some View {
                HStack(spacing: 12) {
                    Button { sheet = current.source == .youtube ? .youtube : .player } label: {
                        HStack(spacing: 12) {
                            ArtworkView(track: current, size: 36, radius: 6)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(current.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                                Text(player.isLoading ? player.loadingMessage : player.isTransitioning ? "Fondu en cours…" : current.subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Spacer(minLength: 0)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if player.isLoading {
                        ProgressView().scaleEffect(0.8).frame(width: 20)
                        IconButton(symbol: "xmark", label: "Annuler le chargement") { player.pause() }
                    }
                    else { IconButton(symbol: player.isPlaying ? "pause.fill" : "play.fill", label: player.isPlaying ? "Pause" : "Lire") { player.toggle() } }
                    IconButton(symbol: "forward.end.fill", label: "Titre suivant") { player.next() }
                }
                .padding(.horizontal, 12).padding(.vertical, 4)
                .accessibilityElement(children: .contain)
    }
}
