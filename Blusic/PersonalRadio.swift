import Foundation
import Observation

enum RadioRanking {
    static func identity(_ track: Track) -> String {
        track.isYouTubeContent ? "youtube:\(track.location)" : "\(track.source.rawValue):\(track.location)"
    }
    static func artist(_ track: Track) -> String { PlaylistImporter.normalize(track.subtitle) }
    static func select(_ candidates: [Track], seed: Track, favorites: Set<String>, listening: [String: Double],
                       excluded: Set<String>, disliked: Set<String>, limit: Int) -> [Track] {
        var seen = excluded.union(disliked)
        let ranked = candidates.filter { track in
            track.isNative && !track.location.isEmpty && seen.insert(identity(track)).inserted
        }.enumerated().map { index, track in
            let key = identity(track)
            let score = (favorites.contains(key) ? 7.0 : 0) + (artist(track) == artist(seed) ? 3 : 0)
                + min(4, log1p(max(0, listening[key] ?? 0)) / 2) - Double(index) * 0.005
            return (track, score)
        }.sorted { $0.1 > $1.1 }
        var remaining = ranked.map(\.0), result: [Track] = []
        var lastArtist = artist(seed)
        while !remaining.isEmpty, result.count < max(0, limit) {
            let index = remaining.firstIndex { artist($0) != lastArtist } ?? 0
            let next = remaining.remove(at: index); result.append(next); lastArtist = artist(next)
        }
        return result
    }
}

protocol RadioCatalogLoading: Sendable {
    func recommendations(for seed: Track) async throws -> [Track]
}
extension MusicCatalogService: RadioCatalogLoading {
    func recommendations(for seed: Track) async throws -> [Track] {
        guard seed.isYouTubeContent, InvidiousService.isVideoID(seed.location) else { return [] }
        return try Self.parseRadio(await callRadio(seed.location))
    }
}

@MainActor @Observable
final class PersonalRadio {
    private(set) var seed: Track?
    private(set) var loading = false
    private(set) var message = "Choisis un morceau pour lancer sa radio."
    private(set) var disliked: Set<String>
    var active: Bool { seed != nil }
    @ObservationIgnored private weak var library: LibraryStore?
    @ObservationIgnored private weak var player: AudioPlayer?
    @ObservationIgnored private let catalog: any RadioCatalogLoading
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var seen: Set<String> = []
    @ObservationIgnored private var skips: Set<String> = []
    @ObservationIgnored private var nextAttempt = Date.distantPast
    @ObservationIgnored private var discoverySeed: Track?

    init(library: LibraryStore, player: AudioPlayer, catalog: any RadioCatalogLoading = MusicCatalogService(), defaults: UserDefaults = .standard) {
        self.library = library; self.player = player; self.catalog = catalog; self.defaults = defaults
        disliked = Set(defaults.stringArray(forKey: "soryn.radio.disliked.v1") ?? [])
    }
    func start(_ track: Track) {
        stop(); seed = track; discoverySeed = track; seen = [RadioRanking.identity(track)]; skips = []
        message = "Radio de \(track.title) · personnalisation locale"
        player?.play(track, in: [track], preservingRadio: true)
        fillIfNeeded(force: true)
    }
    func stop() {
        generation = UUID(); task?.cancel(); task = nil; seed = nil; loading = false
        nextAttempt = .distantPast
    }
    func suspend() {
        generation = UUID(); task?.cancel(); task = nil; loading = false
    }
    func recordSkip(_ track: Track) { if active { skips.insert(RadioRanking.identity(track)) } }
    func dislikeCurrent() {
        guard let current = player?.current else { return }
        disliked.insert(RadioRanking.identity(current))
        defaults.set(Array(disliked).sorted(), forKey: "soryn.radio.disliked.v1")
        message = "Ce titre ne sera plus proposé dans les radios."
        player?.next()
    }
    func resetDislikes() { disliked = []; defaults.removeObject(forKey: "soryn.radio.disliked.v1") }
    func fillIfNeeded(force: Bool = false) {
        guard let seed, let library, let player, !loading, force || Date() >= nextAttempt else { return }
        let index = player.queue.firstIndex { $0.id == player.current?.id } ?? 0
        guard force || player.queue.count - index <= 4 else { return }
        loading = true
        let token = generation, offline = library.settings.usesOfflinePlaybackOnly
        let anchor = discoverySeed ?? seed
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            var candidates = library.tracks.filter { !offline || library.downloads.isAvailable($0) }
            var networkError: String?
            if !offline {
                do { candidates = try await catalog.recommendations(for: anchor) + candidates }
                catch { if Task.isCancelled { return }; networkError = error.localizedDescription }
            }
            guard !Task.isCancelled, generation == token, active else { return }
            if library.settings.usesOfflinePlaybackOnly { candidates = candidates.filter { library.downloads.isAvailable($0) } }
            let favoriteKeys = Set(library.tracks.filter { library.favorites.contains($0.id) }.map(RadioRanking.identity))
            var listening: [String: Double] = [:]
            for event in library.history {
                if let track = library.track(event.trackID) { listening[RadioRanking.identity(track), default: 0] += event.seconds }
            }
            let excluded = seen.union(player.queue.map(RadioRanking.identity)).union(skips)
            let selected = RadioRanking.select(candidates, seed: seed, favorites: favoriteKeys, listening: listening,
                                               excluded: excluded, disliked: disliked, limit: 12)
            for track in selected { seen.insert(RadioRanking.identity(track)) }
            player.appendRadioTracks(selected)
            discoverySeed = selected.last ?? player.current ?? anchor
            loading = false; task = nil; nextAttempt = Date().addingTimeInterval(selected.isEmpty ? 30 : 3)
            if selected.isEmpty {
                message = offline ? "Plus de titres hors ligne disponibles pour cette radio." : "Radio en attente de nouveaux titres." + (networkError == nil ? "" : " Catalogue indisponible ; ta file est conservée.")
            } else {
                message = "Radio de \(seed.title) · \(selected.count) titres ajoutés" + (offline ? " · hors ligne" : networkError == nil ? "" : " · bibliothèque locale")
            }
        }
    }
}
