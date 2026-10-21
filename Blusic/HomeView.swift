import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    private var discovery: [Track] { Array(library.tracks.filter { $0.isNative }.prefix(12)) }
    private var featured: Track? { discovery.first }
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 6 || hour >= 18 ? "Bonsoir" : "Bonjour"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("JUSTE TOI ET LA MUSIQUE").font(.system(size: 10, weight: .bold)).tracking(2.8).foregroundStyle(library.settings.color)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(greeting).").font(.system(size: 37, weight: .bold, design: .rounded)).tracking(-1.5)
                        Image(systemName: "sparkle").font(.system(size: 22, weight: .light)).foregroundStyle(library.settings.color)
                    }
                    Text("Trouve ta prochaine obsession.").font(.subheadline).foregroundStyle(.secondary)
                }.pagePadding().padding(.top, 18)

                if let featured { hero(featured).pagePadding() }
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "À portée d’oreille")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        NavigationLink { TrackCollectionView(title: "Titres favoris", subtitle: "Les morceaux qui restent.", trackIDs: library.likedTracks.map(\.id), kind: .favorites) } label: {
                            quickCard("Titres favoris", detail: "\(library.favorites.count) titre\(library.favorites.count > 1 ? "s" : "")", symbol: "heart.fill", color: .pink)
                        }
                        NavigationLink { TrackCollectionView(title: "Récemment écoutés", subtitle: "Reprends le fil.", trackIDs: library.recentTracks.map(\.id), kind: .recent) } label: {
                            quickCard("Récents", detail: "Ton historique", symbol: "clock.fill", color: .purple)
                        }
                        ForEach(Array(discovery.prefix(2))) { track in
                            Button { player.play(track, in: discovery) } label: {
                                HStack(spacing: 9) {
                                    ArtworkView(track: track, size: 43, radius: 10)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(track.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                        Text(track.subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }.padding(8).surface(radius: 14)
                            }
                        }
                    }.buttonStyle(.plain)
                }.pagePadding()

                if !discovery.isEmpty {
                    VStack(alignment: .leading, spacing: 17) {
                        SectionHeading(title: "Premières ondes", subtitle: "Des originaux Blusic à découvrir.").pagePadding()
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 15) {
                                ForEach(discovery) { track in
                                    Button { player.play(track, in: discovery) } label: {
                                        VStack(alignment: .leading, spacing: 9) {
                                            ArtworkView(track: track, size: 158, radius: library.settings.artworkRadius)
                                            Text(track.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                                            Text(track.subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                                        }.frame(width: 158, alignment: .leading)
                                    }.buttonStyle(.plain)
                                }
                            }.pagePadding()
                        }
                    }
                }
                if !library.recentTracks.isEmpty {
                    VStack(spacing: 12) {
                        SectionHeading(title: "Encore un tour ?", subtitle: "Tes dernières écoutes.")
                        ForEach(Array(library.recentTracks.prefix(5))) { TrackRow(track: $0, context: library.recentTracks) }
                    }.pagePadding()
                }
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path").font(.title3).foregroundStyle(library.settings.color)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ta bibliothèque n’attend que toi.").font(.system(size: 13, weight: .semibold))
                        Text("Importe tes fichiers et tes playlists.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(18).surface().pagePadding()
            }.padding(.bottom, 24)
        }
    }
    private func hero(_ track: Track) -> some View {
        Button { player.play(track, in: discovery) } label: {
            ZStack(alignment: .bottomLeading) {
                Image(track.artwork).resizable().scaledToFill().frame(height: 300).clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.15), .black.opacity(0.82)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 5) {
                        Image(systemName: "waveform").font(.system(size: 9))
                        Text("LA SÉLECTION BLUSIC").font(.system(size: 9, weight: .bold)).tracking(1.6)
                    }.padding(.horizontal, 10).padding(.vertical, 7).background(.white.opacity(0.12), in: Capsule())
                    Spacer()
                    Text("Un peu de calme.\nBeaucoup de musique.")
                        .font(.system(size: 29, weight: .bold, design: .rounded)).tracking(-0.9).multilineTextAlignment(.leading)
                    HStack {
                        Text("\(track.title) · \(track.subtitle)").font(.system(size: 11)).foregroundStyle(.white.opacity(0.75))
                        Spacer()
                        Image(systemName: "play.fill").font(.system(size: 17)).frame(width: 44, height: 44).background(.white.opacity(0.18), in: Circle())
                    }
                }.padding(22)
            }.frame(height: 300).foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 26))
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.1), lineWidth: 0.5))
        }.buttonStyle(.plain).accessibilityLabel("Écouter \(track.title)")
    }
    private func quickCard(_ title: String, detail: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 19)).foregroundStyle(color)
                .frame(width: 43, height: 43).background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(8).surface(radius: 14)
    }
}
