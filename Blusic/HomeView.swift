import SwiftUI

struct HomeView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AudioPlayer.self) private var player
    @State private var discovery = CatalogSearchModel()
    @State private var mood = "Soul"
    @State private var refreshID = 0
    private let moods = ["Soul", "Rap français", "Électronique", "Jazz", "Indie", "Piano"]
    private var offline: Bool { library.settings.usesOfflinePlaybackOnly }
    private var available: [Track] { library.tracks.filter { library.downloads.isAvailable($0) } }
    private var resume: Track? {
        let candidates = [player.current].compactMap { $0 } + library.recentTracks + library.likedTracks
        return candidates.first { !offline || library.downloads.isAvailable($0) }
    }
    private var requestKey: String { "\(mood)|\(offline)|\(refreshID)" }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 30) {
                PageTitle(eyebrow: "À ton rythme", title: "Ta prochaine écoute.",
                          subtitle: offline ? "Ta musique est déjà là. Même sans réseau." : "Tes repères. De nouvelles ondes. Rien de plus.")
                if let track = resume { resumeCard(track) }
                shortcuts
                radioCard
                if !library.recentTracks.isEmpty {
                    MusicShelf(title: "Reviens-y", subtitle: "Tes dernières écoutes", tracks: eligible(library.recentTracks, limit: 10))
                }
                if !library.likedTracks.isEmpty {
                    MusicShelf(title: "Toujours les bons", subtitle: "Tes favoris, à portée de main", tracks: eligible(library.likedTracks, limit: 12))
                }
                if offline {
                    if !available.isEmpty { MusicShelf(title: "Prêts à partir", subtitle: "Fichiers et téléchargements disponibles hors ligne", tracks: Array(available.prefix(12))) }
                } else {
                    discoverySection
                }
                if !library.mostPlayedTracks.isEmpty {
                    MusicShelf(title: "En boucle chez toi", subtitle: "D’après ton temps d’écoute réel", tracks: eligible(library.mostPlayedTracks, limit: 12), ranked: true)
                }
                let originals = library.tracks.filter { $0.source == .bundled }
                if !originals.isEmpty { MusicShelf(title: "Premières ondes", subtitle: "Quatre instrumentaux originaux · hors ligne", tracks: originals) }
                HStack(spacing: 7) {
                    Image(systemName: "lock.shield")
                    Text("Tes goûts restent les tiens. Compte facultatif.")
                }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 8)
            }.padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 28)
        }
        .background(Palette.background)
        .refreshable { refreshID += 1 }
        .task(id: requestKey) {
            await discovery.search(mood, offline: offline, immediately: true, refresh: refreshID > 0)
        }
        .onDisappear { discovery.cancel() }
    }

    private func eligible(_ tracks: [Track], limit: Int) -> [Track] {
        Array(tracks.lazy.filter { !offline || library.downloads.isAvailable($0) }.prefix(limit))
    }
    private func resumeCard(_ track: Track) -> some View {
        Button {
            if PlaybackIdentity.matches(player.current, track) { if !player.isPlaying { player.toggle() } }
            else { player.play(track, in: offline ? available : library.recentTracks.isEmpty ? [track] : library.recentTracks) }
        } label: {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Label(PlaybackIdentity.matches(player.current, track) && player.isPlaying ? "À L’ÉCOUTE" : "REPRENDRE LE FIL", systemImage: "waveform")
                        .font(.caption2.weight(.bold)).tracking(1.3).foregroundStyle(library.settings.color)
                    Text(track.title).font(.title2.bold()).lineLimit(2).multilineTextAlignment(.leading)
                    Text(track.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    Label(player.isPlaying && PlaybackIdentity.matches(player.current, track) ? "Continuer l’écoute" : "Écouter", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold)).padding(.top, 2)
                }.frame(maxWidth: .infinity, alignment: .leading)
                ArtworkView(track: track, size: 100, radius: 20).rotationEffect(.degrees(5))
                    .shadow(color: .black.opacity(0.22), radius: 14, y: 10)
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [library.settings.color.opacity(0.15), Palette.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(library.settings.color.opacity(0.18), lineWidth: 1))
        }.buttonStyle(.plain).accessibilityIdentifier("home-resume")
    }
    private var shortcuts: some View {
        HStack(spacing: 10) {
            NavigationLink { TrackCollectionView(title: "Titres favoris", subtitle: "Ce qui compte pour toi", trackIDs: [], kind: .favorites) } label: {
                shortcut("Favoris", detail: "\(library.likedTracks.count) titres", symbol: "heart.fill", color: .pink)
            }
            NavigationLink { DownloadsView() } label: {
                shortcut("Hors ligne", detail: "\(available.count) prêts", symbol: "arrow.down.circle.fill", color: .mint)
            }
        }.buttonStyle(.plain)
    }
    private func shortcut(_ title: String, detail: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.title3).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(16).surface(radius: 20)
    }
    private var radioCard: some View {
        NavigationLink { RadioView() } label: {
            HStack(spacing: 16) {
                Image(systemName: "dot.radiowaves.left.and.right").font(.title2).foregroundStyle(library.settings.color)
                    .frame(width: 50, height: 50).background(library.settings.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 5) {
                    Text(player.radio.active ? "Ta radio continue" : "Un titre. Et la suite.").font(.headline)
                    Text(player.radio.active ? player.radio.message : offline ? "Une radio depuis ta musique disponible." : "Une radio personnelle, à partir d’un morceau.")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right").font(.subheadline).foregroundStyle(.secondary)
            }.padding(16).surface(radius: 22)
        }.buttonStyle(.plain).accessibilityIdentifier("open-personal-radio")
    }
    private var discoverySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "Change d’horizon", subtitle: "Choisis une couleur musicale")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(moods, id: \.self) { value in FilterPill(title: value, selected: mood == value) { mood = value } } }
            }
            if discovery.loading {
                HStack(spacing: 12) { ProgressView(); Text("À la recherche de nouvelles ondes…").font(.subheadline).foregroundStyle(.secondary) }.padding(.vertical, 30)
            } else if let error = discovery.error {
                VStack(alignment: .leading, spacing: 12) {
                    Label("La découverte peut attendre", systemImage: "wifi.exclamationmark").font(.headline)
                    Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    Button("Réessayer") { refreshID += 1 }.buttonStyle(.bordered)
                }.padding(18).surface()
            } else if !discovery.tracks.isEmpty {
                MusicShelf(title: mood, subtitle: "À explorer sur YouTube Music · pas un classement", tracks: Array(discovery.tracks.prefix(12)))
            }
        }
    }
}
