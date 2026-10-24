import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @State private var online: [Track] = []
    @State private var onlineError: String?
    @State private var loadingCatalogue = false
    @State private var retry = 0
    private var quickTracks: [Track] { Array((library.recentTracks.isEmpty ? online : library.recentTracks).prefix(4)) }
    private var mostPlayed: [Track] {
        let totals = Dictionary(grouping: library.history, by: \.trackID).mapValues { $0.reduce(0) { $0 + $1.seconds } }
        return totals.sorted { $0.value > $1.value }.prefix(12).compactMap { library.track($0.key) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 27) {
                VStack(alignment: .leading, spacing: 13) {
                    heading("Accès rapide", symbol: "bolt.circle.fill")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        NavigationLink { TrackCollectionView(title: "Titres favoris", subtitle: "Tes morceaux favoris", trackIDs: [], kind: .favorites) } label: {
                            quickCard("Titres favoris", detail: "\(library.likedTracks.count) titre\(library.likedTracks.count > 1 ? "s" : "")", symbol: "heart.fill")
                        }
                        NavigationLink { TrackCollectionView(title: "Récemment écoutés", subtitle: "Ton historique", trackIDs: [], kind: .recent) } label: {
                            quickCard("Récents", detail: "Ton historique", symbol: "clock")
                        }
                        ForEach(quickTracks) { track in
                            Button { player.play(track, in: quickTracks) } label: {
                                HStack(spacing: 9) {
                                    ArtworkView(track: track, size: 36, radius: 5)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(track.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                        Text(track.subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.padding(8).frame(height: 52).surface(radius: 8)
                            }
                        }
                    }.buttonStyle(.plain)
                }

                if !mostPlayed.isEmpty {
                    albumSection("Les plus écoutés par toi", subtitle: "Tes écoutes, tout simplement", symbol: "chart.bar.fill", tracks: mostPlayed, ranked: true)
                }
                if loadingCatalogue && online.isEmpty {
                    HStack(spacing: 10) { ProgressView(); Text("Chargement de YouTube Music…").font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 12)
                } else if let onlineError {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("Catalogue indisponible", systemImage: "wifi.exclamationmark").font(.subheadline.bold())
                        Text(onlineError).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        Button("Réessayer") { retry += 1 }.font(.caption.bold())
                    }.padding(14).surface(radius: 10)
                }
                if !online.isEmpty {
                    albumSection("À l’écoute en ce moment", subtitle: "Chansons YouTube Music", symbol: "flame.fill", tracks: online)
                }
                if !library.recentTracks.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        heading("Récemment écoutés", symbol: "clock.arrow.circlepath")
                        ForEach(Array(library.recentTracks.prefix(5))) { TrackRow(track: $0, context: library.recentTracks) }
                    }
                }
                let originals = library.tracks.filter { $0.source == .bundled }
                if !originals.isEmpty {
                    albumSection("Premières ondes", subtitle: "Démos Blusic · disponibles hors ligne", symbol: "waveform", tracks: originals)
                }
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.background)
        .task(id: retry) {
            loadingCatalogue = true; onlineError = nil
            defer { loadingCatalogue = false }
            do {
                let result = try await MusicCatalogService().search("rap français")
                try Task.checkCancellation()
                online = Array(result.tracks.prefix(12))
                await InvidiousAudioLoader.prefetch(online, settings: library.settings)
            } catch { if !Task.isCancelled { onlineError = error.localizedDescription } }
        }
    }

    private func heading(_ title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
            Text(title).font(.system(size: 22, weight: .bold)).tracking(-0.6)
        }.foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func albumSection(_ title: String, subtitle: String, symbol: String, tracks: [Track], ranked: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                heading(title, symbol: symbol)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        Button { player.play(track, in: tracks) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ArtworkView(track: track, size: 144, radius: 8)
                                    .overlay(alignment: .topLeading) {
                                        if ranked { Text("#\(index + 1)").font(.system(size: 9, weight: .bold)).padding(5).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4)).padding(6) }
                                    }
                                Text(track.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                Text(track.subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }.frame(width: 144, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
    private func quickCard(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 18)).frame(width: 36, height: 36)
                .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(8).frame(height: 52).surface(radius: 8)
    }
}
