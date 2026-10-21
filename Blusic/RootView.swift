import SwiftUI
import UniformTypeIdentifiers

private enum AppTab: String, CaseIterable {
    case home = "Accueil", search = "Recherche", library = "Bibliothèque"
    var symbol: String { switch self { case .home: return "house.fill"; case .search: return "magnifyingglass"; case .library: return "square.stack.fill" } }
}
private enum AppSheet: String, Identifiable {
    case player, settings, statistics, youtube
    var id: String { rawValue }
}

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @State private var tab: AppTab = .home
    @State private var sheet: AppSheet?
    @State private var resolveWithFile = false
    @State private var resolutionID: UUID?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Palette.background.ignoresSafeArea()
                RadialGradient(colors: [library.settings.color.opacity(0.10), .clear], center: .topTrailing, startRadius: 0, endRadius: 390)
                    .ignoresSafeArea().allowsHitTesting(false)
                Group {
                    switch tab {
                    case .home: HomeView()
                    case .search: SearchView()
                    case .library: LibraryView()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 8) {
                        BlusicMark().fill(.primary, style: FillStyle(eoFill: true)).frame(width: 27, height: 27)
                        Text("blusic").font(.system(size: 22, weight: .bold, design: .rounded)).tracking(-0.8)
                    }.accessibilityElement(children: .combine)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    IconButton(symbol: "chart.bar.xaxis", label: "Statistiques") { sheet = .statistics }
                    Button { sheet = .settings } label: {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 16, weight: .semibold))
                            .frame(width: 38, height: 38).blusicGlass(radius: 19)
                    }.buttonStyle(.plain).accessibilityLabel("Réglages")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        }
        .sheet(item: $sheet, onDismiss: { player.youtubeTrack = nil }) { item in
            switch item {
            case .player: PlayerView().presentationDragIndicator(.hidden).presentationCornerRadius(30)
            case .settings: NavigationStack { SettingsView() }
            case .statistics: NavigationStack { StatisticsView() }
            case .youtube:
                if let track = player.youtubeTrack ?? player.current { NavigationStack { YouTubePlayerView(track: track) } }
            }
        }
        .onChange(of: player.youtubeTrack) { _, value in if value != nil { sheet = .youtube } }
        .confirmationDialog("Associer une source", isPresented: Binding(get: { player.unresolvedTrack != nil }, set: { if !$0 { player.unresolvedTrack = nil } }), titleVisibility: .visible) {
            Button("Choisir un fichier audio") { resolutionID = player.current?.id; resolveWithFile = true }
            Button("Annuler", role: .cancel) { player.unresolvedTrack = nil }
        } message: { Text("Ce titre a été importé comme référence. Associe ton fichier audio pour l’écouter en natif.") }
        .fileImporter(isPresented: $resolveWithFile, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result {
                Task { await library.importAudio(urls, replacing: resolutionID) }
            } else if case let .failure(error) = result { library.error = error.localizedDescription }
        }
        .alert("Un petit contretemps", isPresented: Binding(get: { library.error != nil || player.error != nil }, set: { if !$0 { library.error = nil; player.error = nil } })) {
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
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if let current = player.current {
                HStack(spacing: 12) {
                    Button { sheet = current.source == .youtube ? .youtube : .player } label: {
                        HStack(spacing: 12) {
                            ArtworkView(track: current, size: 44, radius: 11)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(current.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                                Text(current.subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if player.isLoading { ProgressView().frame(width: 44) }
                    else { IconButton(symbol: player.isPlaying ? "pause.fill" : "play.fill", label: player.isPlaying ? "Pause" : "Lire") { player.toggle() } }
                    IconButton(symbol: "forward.end.fill", label: "Titre suivant") { player.next() }
                }
                .padding(.leading, 10).padding(.trailing, 5).padding(.vertical, 8)
                .blusicGlass(radius: 22)
                .overlay(alignment: .bottomLeading) {
                    GeometryReader { geometry in
                        Capsule().fill(library.settings.color.opacity(0.8))
                            .frame(width: geometry.size.width * min(1, max(0, player.position / max(1, player.duration))), height: 2)
                    }.frame(height: 2).padding(.horizontal, 20).padding(.bottom, 1)
                }
                .accessibilityElement(children: .contain)
            }
            HStack(spacing: 4) {
                ForEach(AppTab.allCases, id: \.self) { item in
                    Button {
                        library.haptic()
                        tab = item
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: item.symbol).font(.system(size: 19, weight: .semibold))
                            Text(item.rawValue).font(.system(size: 10, weight: .semibold))
                        }.frame(maxWidth: .infinity).frame(height: 51)
                            .foregroundStyle(tab == item ? library.settings.color : .secondary)
                            .background { if tab == item { Capsule().fill(library.settings.color.opacity(0.11)) } }
                    }.buttonStyle(.plain).accessibilityAddTraits(tab == item ? .isSelected : [])
                }
            }.padding(6).blusicGlass(radius: 34)
        }
        .padding(.horizontal, 18).padding(.top, 9).padding(.bottom, 4)
        .background { LinearGradient(colors: [Palette.background.opacity(0), Palette.background.opacity(0.95)], startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .bottom) }
    }
}
