import AVFoundation
import Observation
import Foundation
import UIKit

@MainActor
@Observable
final class LibraryStore {
    var tracks: [Track] = [] { didSet { rebuildTrackIndex(); scheduleSave() } }
    var playlists: [Playlist] = [] { didSet { scheduleSave() } }
    var favorites: Set<UUID> = [] { didSet { likedCache = nil; scheduleSave() } }
    var history: [ListeningEvent] = [] { didSet { recentCache = nil; mostPlayedCache = nil; scheduleSave() } }
    var followedArtists: [MusicArtist] = [] { didSet { scheduleSave() } }
    var settings = AppSettings() { didSet { scheduleSave() } }
    var savedQueue: [UUID] = [] { didSet { scheduleSave() } }
    var savedCurrentID: UUID? { didSet { scheduleSave() } }
    var notice: String?
    var error: String?
    var requestedArtist: MusicArtist?
    @ObservationIgnored private var trackIndex: [UUID: Int] = [:]
    @ObservationIgnored private var sourceIndex: [String: UUID] = [:]
    @ObservationIgnored private var likedCache: [Track]?
    @ObservationIgnored private var recentCache: [Track]?
    @ObservationIgnored private var mostPlayedCache: [Track]?
    @ObservationIgnored private var readyToSave = false
    @ObservationIgnored private var saveDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var saveRevision: UInt64 = 0
    private let writer = LibraryPersistenceWorker()
    private let fileManager = FileManager.default
    private let persists: Bool

    static var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Blusic", isDirectory: true)
    }
    static var audioDirectory: URL { root.appendingPathComponent("Audio", isDirectory: true) }
    private var database: URL { Self.root.appendingPathComponent("library.json") }

    init(inMemory: Bool = false) {
        persists = !inMemory
        do {
            try fileManager.createDirectory(at: Self.audioDirectory, withIntermediateDirectories: true)
            if inMemory { seed() }
            else if fileManager.fileExists(atPath: database.path) {
                let snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: database))
                guard snapshot.version == 1 else { throw BlusicError.message("Version de bibliothèque non prise en charge.") }
                apply(snapshot)
            } else { seed() }
        } catch {
            // Never replace a damaged library with seed data: retain it for recovery.
            if fileManager.fileExists(atPath: database.path) {
                try? fileManager.copyItem(at: database, to: Self.root.appendingPathComponent("library-recovery-\(UUID().uuidString).json"))
            }
            self.error = "Impossible de lire la bibliothèque. Une copie de récupération est conservée. \(error.localizedDescription)"
        }
        rebuildTrackIndex()
        readyToSave = true
    }

    private static func sourceKey(_ track: Track) -> String { "\(track.source.rawValue)|\(track.location)" }
    private func rebuildTrackIndex() {
        trackIndex.removeAll(keepingCapacity: true); sourceIndex.removeAll(keepingCapacity: true)
        for (index, track) in tracks.enumerated() {
            if trackIndex[track.id] == nil { trackIndex[track.id] = index }
            if !track.location.isEmpty, sourceIndex[Self.sourceKey(track)] == nil { sourceIndex[Self.sourceKey(track)] = track.id }
        }
        likedCache = nil; recentCache = nil; mostPlayedCache = nil
    }
    var likedTracks: [Track] {
        access(keyPath: \.tracks); access(keyPath: \.favorites)
        if let likedCache { return likedCache }
        let result = tracks.filter { favorites.contains($0.id) }; likedCache = result; return result
    }
    func isFavorite(_ track: Track) -> Bool {
        if favorites.contains(track.id) { return true }
        access(keyPath: \.tracks)
        guard !track.location.isEmpty, let id = sourceIndex[Self.sourceKey(track)] else { return false }
        return favorites.contains(id)
    }
    var recentTracks: [Track] {
        access(keyPath: \.tracks); access(keyPath: \.history)
        if let recentCache { return recentCache }
        var seen = Set<UUID>()
        let result = history.reversed().compactMap { event -> Track? in
            guard seen.insert(event.trackID).inserted else { return nil }
            return track(event.trackID)
        }
        recentCache = result; return result
    }
    var mostPlayedTracks: [Track] {
        access(keyPath: \.tracks); access(keyPath: \.history)
        if let mostPlayedCache { return mostPlayedCache }
        var totals: [UUID: Double] = [:]
        for event in history { totals[event.trackID, default: 0] += event.seconds }
        let result = totals.sorted { $0.value > $1.value }.prefix(12).compactMap { track($0.key) }
        mostPlayedCache = result; return result
    }
    func track(_ id: UUID) -> Track? {
        access(keyPath: \.tracks)
        guard let index = trackIndex[id], tracks.indices.contains(index) else { return nil }
        return tracks[index]
    }
    func tracks(in playlist: Playlist, limit: Int? = nil) -> [Track] {
        Array(playlist.trackIDs.lazy.compactMap { track($0) }.prefix(limit ?? playlist.trackIDs.count))
    }
    func toggleFavorite(_ track: Track) {
        let stored = add(track)
        if favorites.contains(stored.id) { favorites.remove(stored.id) } else { favorites.insert(stored.id) }
        haptic()
    }
    func haptic() { if settings.haptics { UISelectionFeedbackGenerator().selectionChanged() } }
    func toggleFollow(_ artist: MusicArtist) {
        if followedArtists.contains(where: { $0.id == artist.id }) { followedArtists.removeAll { $0.id == artist.id } }
        else { followedArtists.append(artist) }
        haptic()
    }

    @discardableResult
    func add(_ track: Track) -> Track {
        add([track])[0]
    }
    /// Merge a queue/import in one mutation rather than rebuilding after every song.
    @discardableResult
    func add(_ incoming: [Track]) -> [Track] {
        var updated = tracks, byID = trackIndex, bySource = sourceIndex
        var result: [Track] = []; result.reserveCapacity(incoming.count)
        var changed = false
        for track in incoming {
            if let index = byID[track.id] { result.append(updated[index]); continue }
            if !track.location.isEmpty, let id = bySource[Self.sourceKey(track)], let index = byID[id] {
                var existing = updated[index]
                if existing.artistID == nil { existing.artistID = track.artistID }
                if existing.musicCatalog == nil { existing.musicCatalog = track.musicCatalog }
                if existing.artworkURL == nil { existing.artworkURL = track.artworkURL }
                if existing.album.isEmpty { existing.album = track.album }
                if existing.duration <= 0 { existing.duration = track.duration }
                if existing != updated[index] { updated[index] = existing; changed = true }
                result.append(existing)
            } else {
                byID[track.id] = updated.count
                if !track.location.isEmpty { bySource[Self.sourceKey(track)] = track.id }
                updated.append(track); result.append(track); changed = true
            }
        }
        if changed { tracks = updated }
        return result
    }
    @discardableResult
    func createPlaylist(_ name: String, tracks: [Track] = []) -> Playlist {
        var seen = Set<UUID>()
        let ids = add(tracks).map(\.id).filter { seen.insert($0).inserted }
        let playlist = Playlist(name: name.trimmingCharacters(in: .whitespacesAndNewlines), trackIDs: ids)
        playlists.insert(playlist, at: 0)
        return playlist
    }
    func add(_ track: Track, to playlist: Playlist) {
        let saved = add(track)
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }),
              !playlists[index].trackIDs.contains(saved.id) else { return }
        playlists[index].trackIDs.append(saved.id)
        notice = "Ajouté à « \(playlist.name) »"
    }
    func remove(_ track: Track) {
        tracks.removeAll { $0.id == track.id }
        favorites.remove(track.id)
        for index in playlists.indices { playlists[index].trackIDs.removeAll { $0 == track.id } }
        savedQueue.removeAll { $0 == track.id }
        if track.source == .local, let url = nativeURL(for: track) { try? fileManager.removeItem(at: url) }
        if track.source == .local, let cover = track.artworkURL, cover.isFileURL,
           cover.deletingLastPathComponent().standardizedFileURL == Self.audioDirectory.standardizedFileURL {
            try? fileManager.removeItem(at: cover)
        }
    }
    func replaceSource(of id: UUID, with replacement: Track) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        var updated = tracks[index]
        updated.source = replacement.source; updated.location = replacement.location
        updated.duration = replacement.duration; updated.artworkURL = replacement.artworkURL
        updated.album = replacement.album; updated.artistID = replacement.artistID; updated.musicCatalog = replacement.musicCatalog
        tracks[index] = updated
    }
    func nativeURL(for track: Track) -> URL? {
        switch track.source {
        case .bundled: return Bundle.main.url(forResource: track.location, withExtension: nil)
        case .local:
            // Imported paths must stay inside the app's own Audio directory.
            guard track.location == (track.location as NSString).lastPathComponent else { return nil }
            return Self.audioDirectory.appendingPathComponent(track.location)
        case .remote:
            guard let url = URL(string: track.location), url.scheme == "https" else { return nil }
            return url
        default: return nil
        }
    }

    func importAudio(_ urls: [URL], replacing id: UUID? = nil) async {
        var successes = 0
        var failures: [String] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let filename = UUID().uuidString + "." + url.pathExtension.lowercased()
            let destination = Self.audioDirectory.appendingPathComponent(filename)
            do {
                // Large copies and decoder probing run off the main actor, keeping the UI fluid.
                try await AudioImportWorker.shared.copyAndValidate(from: url, to: destination)
                let asset = AVURLAsset(url: destination)
                let duration = (try? await asset.load(.duration).seconds) ?? 0
                let metadata = (try? await asset.load(.commonMetadata)) ?? []
                var title = url.deletingPathExtension().lastPathComponent
                var artist = "Artiste inconnu"
                var album = "Fichiers importés"
                var artworkURL: URL?
                for item in metadata {
                    switch item.commonKey {
                    case .commonKeyTitle: if let value = try? await item.load(.stringValue) { title = value }
                    case .commonKeyArtist: if let value = try? await item.load(.stringValue) { artist = value }
                    case .commonKeyAlbumName: if let value = try? await item.load(.stringValue) { album = value }
                    case .commonKeyArtwork:
                        if let data = try? await item.load(.dataValue) {
                            let cover = Self.audioDirectory.appendingPathComponent(filename + ".jpg")
                            artworkURL = try await AudioImportWorker.shared.storeArtwork(data, to: cover)
                        }
                    default: break
                    }
                }
                let track = Track(title: title, artist: artist, album: album, duration: duration.isFinite ? duration : 0,
                                  source: .local, location: filename, artworkURL: artworkURL)
                if let id {
                    replaceSource(of: id, with: track)
                    if let i = tracks.firstIndex(where: { $0.id == id }), let artworkURL { tracks[i].artworkURL = artworkURL }
                } else { tracks.append(track) }
                successes += 1
            } catch {
                try? fileManager.removeItem(at: destination)
                failures.append("\(url.lastPathComponent) : \(error.localizedDescription)")
            }
        }
        if successes > 0 { notice = "\(successes) morceau\(successes > 1 ? "x" : "") importé\(successes > 1 ? "s" : "")" }
        if !failures.isEmpty { error = failures.joined(separator: "\n") }
    }

    func recordListening(track: Track, seconds: Double, sessionID: UUID) {
        guard seconds > 0 else { return }
        let today = Calendar.current.startOfDay(for: Date())
        if let index = history.lastIndex(where: { $0.id == sessionID && Calendar.current.startOfDay(for: $0.date) == today }) {
            history[index].seconds += seconds
        } else {
            history.append(ListeningEvent(id: sessionID, trackID: track.id, date: Date(), seconds: seconds))
        }
    }

    func exportBackup() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Blusic-bibliotheque.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot()).write(to: url, options: .atomic)
        return url
    }
    func restoreBackup(_ data: Data) throws {
        let backup = try JSONDecoder().decode(LibrarySnapshot.self, from: data)
        guard backup.version == 1 else { throw BlusicError.message("Cette sauvegarde nécessite une autre version de Blusic.") }
        // Merge rather than erase the current library. Native media files are not in a JSON export.
        var restored: [Track] = []
        var knownTrackIDs = Set(trackIndex.keys)
        for var track in backup.tracks where knownTrackIDs.insert(track.id).inserted {
            if track.source == .youtube { track.source = .invidious }
            if track.source == .local {
                guard track.location == (track.location as NSString).lastPathComponent else { continue }
                if !fileManager.fileExists(atPath: Self.audioDirectory.appendingPathComponent(track.location).path) {
                    track.source = .unresolved
                    track.location = ""
                    track.artworkURL = nil
                }
            }
            restored.append(track)
        }
        // Backup playlists/favorites refer to these exact IDs, including older
        // libraries containing two IDs for the same source. Keep those references.
        if !restored.isEmpty { tracks.append(contentsOf: restored) }
        for playlist in backup.playlists where !playlists.contains(where: { $0.id == playlist.id }) { playlists.append(playlist) }
        favorites.formUnion(backup.favorites)
        let known = Set(history.map(\.id))
        history.append(contentsOf: backup.history.filter { !known.contains($0.id) })
        history.sort { $0.date < $1.date }
        for artist in backup.followedArtists ?? [] where !followedArtists.contains(where: { $0.id == artist.id }) { followedArtists.append(artist) }
        save()
        notice = "Bibliothèque fusionnée. Les fichiers audio absents sont à réassocier."
    }
    func save() {
        guard persists else { return }
        saveDebounceTask?.cancel(); saveDebounceTask = nil
        saveRevision += 1
        let revision = saveRevision, data = snapshot(), destination = database, worker = writer
        let app = UIApplication.shared
        let background = app.applicationState == .active ? UIBackgroundTaskIdentifier.invalid : app.beginBackgroundTask(withName: "Blusic library save", expirationHandler: nil)
        Task { @MainActor [weak self] in
            defer { if background != .invalid { app.endBackgroundTask(background) } }
            do { try await worker.write(data, to: destination, revision: revision) }
            catch { if self?.saveRevision == revision { self?.error = "Sauvegarde impossible : \(error.localizedDescription)" } }
        }
    }
    private func scheduleSave() {
        guard persists, readyToSave else { return }
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            self?.saveDebounceTask = nil
            self?.save()
        }
    }
    private func snapshot() -> LibrarySnapshot {
        LibrarySnapshot(tracks: tracks, playlists: playlists, favorites: favorites, history: history,
                        settings: settings, queue: savedQueue, currentTrackID: savedCurrentID, followedArtists: followedArtists)
    }
    private func apply(_ data: LibrarySnapshot) {
        tracks = data.tracks.map { item in
            var track = item
            if track.source == .youtube { track.source = .invidious }
            return track
        }
        playlists = data.playlists; favorites = data.favorites
        history = data.history; settings = data.settings; savedQueue = data.queue; savedCurrentID = data.currentTrackID
        followedArtists = data.followedArtists ?? []
    }
    private func seed() {
        tracks = [
            Track(title: "Bleu nuit", artist: "Blusic Studio", album: "Premières ondes", duration: 48, source: .bundled, location: "bleu-nuit.wav", artwork: "cover-night"),
            Track(title: "Après la pluie", artist: "Blusic Studio", album: "Premières ondes", duration: 48, source: .bundled, location: "apres-la-pluie.wav", artwork: "cover-rain"),
            Track(title: "Orbite", artist: "Blusic Studio", album: "Premières ondes", duration: 48, source: .bundled, location: "orbite.wav", artwork: "cover-orbit"),
            Track(title: "Dernier métro", artist: "Blusic Studio", album: "Premières ondes", duration: 48, source: .bundled, location: "dernier-metro.wav", artwork: "cover-metro")
        ]
        playlists = [Playlist(name: "Premières ondes", detail: "Quatre instrumentaux originaux. Le début de ton histoire.", trackIDs: tracks.map(\.id), symbol: "waveform")]
        save()
    }
}

actor LibraryPersistenceWorker {
    private var latest: [URL: UInt64] = [:]
    #if DEBUG
    private(set) var mainThreadWriteCount = 0
    #endif
    func write(_ snapshot: LibrarySnapshot, to url: URL, revision: UInt64) throws {
        guard revision > latest[url, default: 0] else { return }
        #if DEBUG
        if Thread.isMainThread { mainThreadWriteCount += 1 }
        #endif
        try JSONEncoder().encode(snapshot).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        latest[url] = revision
    }
}

private actor AudioImportWorker {
    static let shared = AudioImportWorker()
    func copyAndValidate(from source: URL, to destination: URL) throws {
        let manager = FileManager.default
        try manager.copyItem(at: source, to: destination)
        try manager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
        // Reject media unsupported by the engine, including DRM-protected files.
        _ = try AVAudioFile(forReading: destination)
    }
    func storeArtwork(_ data: Data, to destination: URL) throws -> URL? {
        guard let image = ArtworkImageCache.downsample(data, pixels: 1024), let jpeg = image.jpegData(compressionQuality: 0.85) else { return nil }
        try jpeg.write(to: destination, options: .atomic)
        return destination
    }
}
