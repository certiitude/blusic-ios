import Foundation
import AVFoundation
import Observation
import CryptoKit

struct OfflineAudioRecord: Codable, Sendable, Identifiable {
    var id: String
    var track: Track
    var filename: String
    var artworkFilename: String?
    var bytes: Int64
    var bitrate: Int
    var duration: Double
    var quality: String
    var downloadedAt: Date
    static func key(_ track: Track) -> String {
        SHA256.hash(data: Data("\(track.source.rawValue)|\(track.location)".utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Explicit downloads live in Application Support, outside the purgeable audio
/// cache. Only complete, locally decodable files enter the atomic manifest.
actor OfflineAudioStore {
    static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Blusic/Downloads", isDirectory: true)
    }
    nonisolated let root: URL
    private var records: [String: OfflineAudioRecord] = [:]
    private var loaded = false
    init(root: URL = Self.defaultRoot) { self.root = root }
    private func path(_ filename: String) throws -> URL {
        guard !filename.isEmpty, filename == (filename as NSString).lastPathComponent,
              !filename.contains("\\"), filename != ".", filename != ".." else {
            throw BlusicError.message("Chemin de téléchargement invalide.")
        }
        let url = root.appendingPathComponent(filename)
        guard url.resolvingSymlinksInPath().deletingLastPathComponent().path == root.resolvingSymlinksInPath().path else {
            throw BlusicError.message("Téléchargement hors du dossier autorisé.")
        }
        return url
    }
    private func load() throws {
        guard !loaded else { return }
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let manifest = root.appendingPathComponent("downloads.json")
        if manager.fileExists(atPath: manifest.path) {
            let values = try JSONDecoder().decode([OfflineAudioRecord].self, from: Data(contentsOf: manifest))
            for entry in values {
                guard entry.id == OfflineAudioRecord.key(entry.track), entry.bytes > 0,
                      let url = try? path(entry.filename), manager.fileExists(atPath: url.path),
                      let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, Int64(size) == entry.bytes else { continue }
                records[entry.id] = entry
            }
        }
        loaded = true
    }
    private func persist(_ next: [String: OfflineAudioRecord]) throws {
        let manifest = root.appendingPathComponent("downloads.json")
        try JSONEncoder().encode(Array(next.values)).write(to: manifest, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var folder = root
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
    }
    func all() throws -> [OfflineAudioRecord] { try load(); return records.values.sorted { $0.downloadedAt > $1.downloadedAt } }
    func audio(for track: Track) throws -> InvidiousAudio? {
        try load()
        guard let record = records[OfflineAudioRecord.key(track)] else { return nil }
        let url = try path(record.filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        try Self.validate(url, expected: record.duration)
        return InvidiousAudio(fileURL: url, bitrate: record.bitrate, instance: URL(string: "https://www.youtube.com")!,
            duration: record.duration, provider: "Téléchargé · hors ligne", quality: record.quality == "high" ? .high : .standard)
    }
    func save(_ audio: InvidiousAudio, track: Track) throws -> OfflineAudioRecord {
        try load(); try Task.checkCancellation()
        guard audio.fileURL.isFileURL else { throw BlusicError.message("Le fichier audio complet n’a pas été préparé.") }
        let duration = try Self.validate(audio.fileURL, expected: audio.duration ?? track.duration)
        let size = Int64(try audio.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        guard size > 0, size <= 300_000_000 else { throw BlusicError.message("Fichier audio vide ou trop volumineux.") }
        if let available = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           available < size + 20_000_000 { throw BlusicError.message("Espace insuffisant pour télécharger ce titre.") }
        let filename = "audio-\(UUID().uuidString).\(audio.fileURL.pathExtension.isEmpty ? "m4a" : audio.fileURL.pathExtension)"
        let target = try path(filename)
        do {
            try FileManager.default.copyItem(at: audio.fileURL, to: target)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: target.path)
            try Task.checkCancellation()
            let key = OfflineAudioRecord.key(track)
            let entry = OfflineAudioRecord(id: key, track: track, filename: filename, artworkFilename: records[key]?.artworkFilename,
                bytes: size, bitrate: audio.bitrate, duration: duration, quality: audio.quality.rawValue, downloadedAt: Date())
            var next = records; next[key] = entry
            try persist(next)
            if let old = records[key], let previous = try? path(old.filename) { try? FileManager.default.removeItem(at: previous) }
            records = next
            return entry
        } catch { try? FileManager.default.removeItem(at: target); throw error }
    }
    func saveArtwork(_ data: Data, key: String) throws -> OfflineAudioRecord? {
        try load()
        guard var entry = records[key], !data.isEmpty, data.count <= 5_000_000 else { return nil }
        let filename = "cover-\(UUID().uuidString).jpg", target = try path(filename)
        do {
            try data.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            let old = entry.artworkFilename; entry.artworkFilename = filename
            var next = records; next[key] = entry; try persist(next); records = next
            if let old, let url = try? path(old) { try? FileManager.default.removeItem(at: url) }
            return entry
        } catch { try? FileManager.default.removeItem(at: target); throw error }
    }
    func remove(_ key: String) throws {
        try load()
        guard let entry = records[key] else { return }
        var next = records; next[key] = nil; try persist(next); records = next
        try? FileManager.default.removeItem(at: path(entry.filename))
        if let cover = entry.artworkFilename { try? FileManager.default.removeItem(at: path(cover)) }
    }
    private static func validate(_ url: URL, expected: Double) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        let seconds = Double(file.length) / file.processingFormat.sampleRate
        guard file.length > 0, seconds.isFinite, seconds > 0, expected <= 0 || seconds >= expected * 0.8 else {
            throw BlusicError.message("Le téléchargement audio est incomplet ou illisible.")
        }
        return seconds
    }
}

enum OfflineDownloadStatus: Equatable {
    case queued, downloading(String, Double?), failed(String)
    var label: String {
        switch self {
        case .queued: return "En attente"
        case .downloading(let message, _): return message
        case .failed(let reason): return "Échec : \(reason)"
        }
    }
    var isActive: Bool { if case .failed = self { return false }; return true }
}

@MainActor @Observable
final class OfflineDownloads {
    private(set) var records: [String: OfflineAudioRecord] = [:]
    private(set) var statuses: [String: OfflineDownloadStatus] = [:]
    var error: String?
    @ObservationIgnored private weak var library: LibraryStore?
    @ObservationIgnored private let store: OfflineAudioStore
    @ObservationIgnored private let loader: any OnlineAudioLoading
    @ObservationIgnored private var ready: Task<Void, Never>?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var active: Task<OfflineAudioRecord, Error>?
    @ObservationIgnored private var queue: [Track] = []
    @ObservationIgnored private var activeKey: String?
    @ObservationIgnored private var cancelled: Set<String> = []
    init(library: LibraryStore, store: OfflineAudioStore = OfflineAudioStore(), loader: any OnlineAudioLoading = InvidiousAudioLoader()) {
        self.library = library; self.store = store; self.loader = loader
        ready = Task { [weak self, store] in
            do {
                let entries = try await store.all()
                guard let self else { return }
                self.records = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
                library.add(entries.map(\.track))
            } catch { self?.error = "Les téléchargements n’ont pas pu être lus. \(error.localizedDescription)" }
        }
    }
    func waitUntilReady() async { await ready?.value }
    func record(for track: Track) -> OfflineAudioRecord? { records[OfflineAudioRecord.key(track)] }
    func status(for track: Track) -> OfflineDownloadStatus? { statuses[track.id.uuidString] }
    func isAvailable(_ track: Track) -> Bool { track.isOffline || record(for: track) != nil }
    var totalBytes: Int64 { records.values.reduce(0) { $0 + $1.bytes } }
    var pendingCount: Int { statuses.values.filter(\.isActive).count }
    func artworkURL(for track: Track) -> URL? {
        guard let filename = record(for: track)?.artworkFilename else { return nil }
        return store.root.appendingPathComponent(filename)
    }
    func audio(for track: Track) async throws -> InvidiousAudio? { await waitUntilReady(); return try await store.audio(for: track) }
    func waitUntilIdle() async { await waitUntilReady(); await worker?.value }
    func enqueue(_ tracks: [Track]) {
        guard let library else { return }
        for track in library.add(tracks) {
            guard [.invidious, .remote, .catalogReference].contains(track.source), record(for: track) == nil else { continue }
            let key = track.id.uuidString
            guard statuses[key]?.isActive != true else { continue }
            cancelled.remove(key); statuses[key] = .queued; queue.append(track)
        }
        startWorker()
    }
    func cancel(_ track: Track) {
        let key = track.id.uuidString
        cancelled.insert(key); queue.removeAll { $0.id.uuidString == key }; statuses[key] = nil
        if activeKey == key { active?.cancel() }
    }
    func cancelAll() { for track in queue { cancel(track) }; if let key = activeKey { cancelled.insert(key); active?.cancel(); statuses[key] = nil }; queue.removeAll() }
    func remove(_ track: Track) async {
        cancel(track)
        do { try await store.remove(OfflineAudioRecord.key(track)); records[OfflineAudioRecord.key(track)] = nil }
        catch { self.error = error.localizedDescription }
    }
    func removeAll() async { cancelAll(); for record in Array(records.values) { await remove(record.track) } }
    private func startWorker() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            await waitUntilReady()
            while !queue.isEmpty {
                let requested = queue.removeFirst(), key = requested.id.uuidString
                guard !cancelled.contains(key), record(for: requested) == nil, let library else { statuses[key] = nil; continue }
                activeKey = key; statuses[key] = .downloading("Préparation du téléchargement…", nil)
                let settings = library.settings, loader = self.loader, store = self.store
                let task = Task { @MainActor [weak self] () throws -> OfflineAudioRecord in
                    var track = library.track(requested.id) ?? requested
                    if track.source == .catalogReference {
                        let matched = try await MusicCatalogService().match(track)
                        try Task.checkCancellation(); library.replaceSource(of: track.id, with: matched)
                        track = library.track(track.id) ?? matched
                    }
                    let audio = try await withThrowingTaskGroup(of: InvidiousAudio.self) { group in
                        group.addTask {
                            if track.source == .remote, let url = URL(string: track.location) {
                                let file = try await AudioCache.shared.localCopy(of: url, expectedDuration: track.duration)
                                return InvidiousAudio(fileURL: file, bitrate: 0, instance: url, duration: track.duration)
                            }
                            if let streaming = loader as? any StreamingAudioLoading {
                                switch try await streaming.playback(track, settings: settings, direct: false) {
                                case .file(let audio): return audio
                                case .stream(let stream):
                                    let file = try await AudioCache.shared.localCopy(of: stream.url, cacheKey: stream.quality.fileKey(videoID: track.location, bitrate: stream.bitrate),
                                        fileExtension: "m4a", expectedDuration: stream.duration, session: InvidiousService.mediaSession)
                                    return InvidiousAudio(fileURL: file, bitrate: stream.bitrate, instance: stream.instance, duration: stream.duration, quality: stream.quality)
                                }
                            }
                            return try await loader.load(track, settings: settings, progress: { update in
                                Task { @MainActor [weak self] in
                                    guard let self, self.activeKey == key, !self.cancelled.contains(key) else { return }
                                    self.statuses[key] = .downloading(update.message, update.fraction)
                                }
                            })
                        }
                        group.addTask { try await Task.sleep(for: .seconds(120)); throw BlusicError.message("Téléchargement trop lent. Réessaie lorsque la connexion sera disponible.") }
                        defer { group.cancelAll() }; return try await group.next()!
                    }
                    try Task.checkCancellation()
                    return try await store.save(audio, track: track)
                }
                active = task
                do {
                    let entry = try await task.value
                    if cancelled.contains(key) { try? await store.remove(entry.id) }
                    else {
                        records[entry.id] = entry
                        statuses[key] = nil
                        if let url = entry.track.artworkURL {
                            let image = await ArtworkImageCache.shared.image(for: ArtworkRequest(url: url, pixels: 512))
                            if !cancelled.contains(key), let data = image?.jpegData(compressionQuality: 0.9), let updated = try? await store.saveArtwork(data, key: entry.id) { records[entry.id] = updated }
                        }
                    }
                } catch {
                    if cancelled.contains(key) || error is CancellationError { statuses[key] = nil }
                    else { statuses[key] = .failed(error.localizedDescription) }
                }
                active = nil; activeKey = nil
            }
            worker = nil
        }
    }
}
