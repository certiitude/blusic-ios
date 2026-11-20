import Foundation
import Observation

protocol CatalogSearching: Sendable {
    func search(_ query: String, continuation: String?) async throws -> MusicSearchPage
    func searchArtists(_ query: String) async throws -> [MusicArtist]
}

enum SearchCategory: String, CaseIterable, Sendable {
    case songs = "Titres", artists = "Artistes"
}

/// Metadata only. No audio URL resolution or automatic file download while browsing.
/// A request identity protects results, pagination AND loading state from late replies.
@MainActor @Observable
final class CatalogSearchModel {
    private(set) var tracks: [Track] = []
    private(set) var artists: [MusicArtist] = []
    private(set) var loading = false
    private(set) var loadingMore = false
    private(set) var error: String?
    private(set) var pageError: String?
    private(set) var continuation: String?
    @ObservationIgnored private let catalog: any CatalogSearching
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var query = ""
    @ObservationIgnored private var category = SearchCategory.songs
    @ObservationIgnored private var cache: [String: Cached] = [:]
    private struct Cached {
        var tracks: [Track]
        var artists: [MusicArtist]
        var continuation: String?
        var date: Date
    }
    init(catalog: any CatalogSearching = MusicCatalogService()) { self.catalog = catalog }
    func cancel() { requestID = UUID(); loading = false; loadingMore = false }
    func search(_ text: String, category: SearchCategory = .songs, offline: Bool = false,
                immediately: Bool = false, refresh: Bool = false, now: Date = Date()) async {
        cancel()
        let id = requestID, clean = SearchTerms.clean(text)
        query = clean; self.category = category
        tracks = []; artists = []; continuation = nil; error = nil; pageError = nil
        guard !offline, !clean.isEmpty, !Task.isCancelled else { return }
        let key = category.rawValue + "|" + SearchTerms.key(clean)
        if !refresh, let entry = cache[key], now.timeIntervalSince(entry.date) >= 0, now.timeIntervalSince(entry.date) < 300 {
            tracks = entry.tracks; artists = entry.artists; continuation = entry.continuation
            return
        }
        loading = true
        defer { if requestID == id { loading = false } }
        do {
            if !immediately { try await Task.sleep(for: .milliseconds(350)) }
            try Task.checkCancellation()
            guard requestID == id else { return }
            if category == .artists {
                let found = try await catalog.searchArtists(clean)
                try Task.checkCancellation(); guard requestID == id else { return }
                var seen = Set<String>()
                artists = found.filter { seen.insert($0.id).inserted }
            } else {
                let found = try await catalog.search(clean, continuation: nil)
                try Task.checkCancellation(); guard requestID == id else { return }
                tracks = Self.unique(found.tracks); continuation = found.continuation
            }
            cache[key] = Cached(tracks: tracks, artists: artists, continuation: continuation, date: now)
            if cache.count > 12, let oldest = cache.min(by: { $0.value.date < $1.value.date })?.key { cache[oldest] = nil }
        } catch {
            guard requestID == id, !Task.isCancelled, !(error is CancellationError) else { return }
            self.error = error.localizedDescription
        }
    }
    func loadMore() async {
        guard !loading, !loadingMore, category == .songs, let token = continuation, !Task.isCancelled else { return }
        let id = requestID, text = query
        loadingMore = true; pageError = nil
        defer { if requestID == id { loadingMore = false } }
        do {
            let found = try await catalog.search(text, continuation: token)
            try Task.checkCancellation(); guard requestID == id else { return }
            let combined = Self.unique(tracks + found.tracks)
            let added = combined.count > tracks.count
            tracks = combined
            continuation = added && found.continuation != token ? found.continuation : nil
        } catch {
            guard requestID == id, !Task.isCancelled, !(error is CancellationError) else { return }
            pageError = error.localizedDescription
        }
    }
    private static func unique(_ tracks: [Track]) -> [Track] {
        var seen = Set<String>()
        return tracks.filter { seen.insert(PlaybackIdentity.key($0)).inserted }
    }
}

enum SearchTerms {
    static func clean(_ text: String) -> String { String(text.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(120)) }
    static func key(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
    }
}

/// Local to this device, separate from the library and optional account sync.
@MainActor @Observable
final class RecentSearches {
    private(set) var terms: [String]
    @ObservationIgnored private let defaults: UserDefaults
    private static let storageKey = "soryn.search.recent.v1"
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var seen = Set<String>()
        terms = Array((defaults.stringArray(forKey: Self.storageKey) ?? []).map(SearchTerms.clean)
            .filter { !$0.isEmpty && seen.insert(SearchTerms.key($0)).inserted }.prefix(8))
    }
    func record(_ text: String) {
        let term = SearchTerms.clean(text)
        guard !term.isEmpty else { return }
        terms.removeAll { SearchTerms.key($0) == SearchTerms.key(term) }
        terms.insert(term, at: 0); terms = Array(terms.prefix(8)); persist()
    }
    func remove(_ term: String) { terms.removeAll { SearchTerms.key($0) == SearchTerms.key(term) }; persist() }
    func clear() { terms = []; defaults.removeObject(forKey: Self.storageKey) }
    private func persist() { defaults.set(terms, forKey: Self.storageKey) }
}

enum PlaybackIdentity {
    static func key(_ track: Track) -> String {
        guard !track.location.isEmpty else { return track.id.uuidString }
        return (track.isYouTubeContent ? "youtube" : track.source.rawValue) + "|" + track.location
    }
    static func matches(_ a: Track?, _ b: Track) -> Bool { a.map { $0.id == b.id || key($0) == key(b) } ?? false }
}

enum LibrarySort: String, CaseIterable {
    case added = "Ajouts récents", title = "Titre", artist = "Artiste"
}
enum LibraryBrowse {
    static func filter(_ tracks: [Track], query: String, sort: LibrarySort = .added) -> [Track] {
        let words = SearchTerms.key(query).split(separator: " ")
        let matches = words.isEmpty ? tracks : tracks.filter {
            let value = SearchTerms.key("\($0.title) \($0.subtitle) \($0.album)")
            return words.allSatisfy { value.contains($0) }
        }
        return matches.sorted { a, b in
            let comparison: ComparisonResult
            switch sort {
            case .added: return a.addedAt == b.addedAt ? a.id.uuidString < b.id.uuidString : a.addedAt > b.addedAt
            case .title: comparison = a.title.localizedStandardCompare(b.title)
            case .artist:
                let artist = a.subtitle.localizedStandardCompare(b.subtitle)
                comparison = artist == .orderedSame ? a.title.localizedStandardCompare(b.title) : artist
            }
            return comparison == .orderedSame ? a.id.uuidString < b.id.uuidString : comparison == .orderedAscending
        }
    }
}

struct QueueTimeline {
    var queue: [Track]
    var currentID: UUID?
    var upcomingStart: Int { currentID.flatMap { id in queue.firstIndex { $0.id == id } }.map { $0 + 1 } ?? 0 }
    var upcoming: [Track] { Array(queue.dropFirst(upcomingStart)) }
    var previous: [Track] { Array(queue.prefix(max(0, upcomingStart - 1))) }
}
