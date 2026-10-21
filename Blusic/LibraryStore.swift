import AVFoundation
import Combine
import Foundation
import UIKit

@MainActor
final class LibraryStore: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var playlists: [Playlist] = []
    @Published var favorites: Set<UUID> = []
    @Published var history: [ListeningEvent] = []
    @Published var settings = AppSettings()
    @Published var savedQueue: [UUID] = []
    @Published var savedCurrentID: UUID?
    @Published var notice: String?
    @Published var error: String?
    private var cancellables = Set<AnyCancellable>()
    private let fileManager = FileManager.default

    static var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Blusic", isDirectory: true)
    }
    static var audioDirectory: URL { root.appendingPathComponent("Audio", isDirectory: true) }
    private var database: URL { Self.root.appendingPathComponent("library.json") }

    init() {
        do {
            try fileManager.createDirectory(at: Self.audioDirectory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: database.path) {
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
        Publishers.MergeMany($tracks.map { _ in true }.eraseToAnyPublisher(),
                            $playlists.map { _ in true }.eraseToAnyPublisher(),
                            $favorites.map { _ in true }.eraseToAnyPublisher(),
                            $settings.map { _ in true }.eraseToAnyPublisher(),
                            $history.map { _ in true }.eraseToAnyPublisher(),
                            $savedQueue.map { _ in true }.eraseToAnyPublisher(),
                            $savedCurrentID.map { _ in true }.eraseToAnyPublisher())
            .dropFirst(7)
            .debounce(for: .milliseconds(450), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }.store(in: &cancellables)
    }

    var likedTracks: [Track] { tracks.filter { favorites.contains($0.id) } }
    var recentTracks: [Track] {
        var seen = Set<UUID>()
        return history.reversed().compactMap { event in
            guard seen.insert(event.trackID).inserted else { return nil }
            return track(event.trackID)
        }
    }
    func track(_ id: UUID) -> Track? { tracks.first { $0.id == id } }
    func tracks(in playlist: Playlist) -> [Track] { playlist.trackIDs.compactMap { track($0) } }
    func toggleFavorite(_ track: Track) {
        if favorites.contains(track.id) { favorites.remove(track.id) } else { favorites.insert(track.id) }
        haptic()
    }
    func haptic() { if settings.haptics { UISelectionFeedbackGenerator().selectionChanged() } }

    @discardableResult
    func add(_ track: Track) -> Track {
        if let existing = tracks.first(where: { $0.id == track.id }) { return existing }
        if let existing = tracks.first(where: { $0.source == track.source && $0.location == track.location && !$0.location.isEmpty }) {
            return existing
        }
        tracks.append(track)
        return track
    }
    @discardableResult
    func createPlaylist(_ name: String, tracks: [Track] = []) -> Playlist {
        var seen = Set<UUID>()
        let ids = tracks.map { add($0).id }.filter { seen.insert($0).inserted }
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
        tracks[index].source = replacement.source
        tracks[index].location = replacement.location
        tracks[index].duration = replacement.duration
        tracks[index].artworkURL = replacement.artworkURL
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
                        if let data = try? await item.load(.dataValue), let image = UIImage(data: data),
                           let jpeg = image.jpegData(compressionQuality: 0.85) {
                            let cover = Self.audioDirectory.appendingPathComponent(filename + ".jpg")
                            try jpeg.write(to: cover, options: .atomic)
                            artworkURL = cover
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
        for var track in backup.tracks where !tracks.contains(where: { $0.id == track.id }) {
            if track.source == .local {
                guard track.location == (track.location as NSString).lastPathComponent else { continue }
                if !fileManager.fileExists(atPath: Self.audioDirectory.appendingPathComponent(track.location).path) {
                    track.source = .unresolved
                    track.location = ""
                    track.artworkURL = nil
                }
            }
            tracks.append(track)
        }
        for playlist in backup.playlists where !playlists.contains(where: { $0.id == playlist.id }) { playlists.append(playlist) }
        favorites.formUnion(backup.favorites)
        let known = Set(history.map(\.id))
        history.append(contentsOf: backup.history.filter { !known.contains($0.id) })
        history.sort { $0.date < $1.date }
        save()
        notice = "Bibliothèque fusionnée. Les fichiers audio absents sont à réassocier."
    }
    func save() {
        do { try JSONEncoder().encode(snapshot()).write(to: database, options: [.atomic, .completeFileProtectionUnlessOpen]) }
        catch { self.error = "Sauvegarde impossible : \(error.localizedDescription)" }
    }
    private func snapshot() -> LibrarySnapshot {
        LibrarySnapshot(tracks: tracks, playlists: playlists, favorites: favorites, history: history,
                        settings: settings, queue: savedQueue, currentTrackID: savedCurrentID)
    }
    private func apply(_ data: LibrarySnapshot) {
        tracks = data.tracks; playlists = data.playlists; favorites = data.favorites
        history = data.history; settings = data.settings; savedQueue = data.queue; savedCurrentID = data.currentTrackID
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

private actor AudioImportWorker {
    static let shared = AudioImportWorker()
    func copyAndValidate(from source: URL, to destination: URL) throws {
        let manager = FileManager.default
        try manager.copyItem(at: source, to: destination)
        try manager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
        // Reject media unsupported by the engine, including DRM-protected files.
        _ = try AVAudioFile(forReading: destination)
    }
}
