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
    var codec: OnlineAudioCodec?
    var fallbackReason: String?
    static func key(_ track: Track, quality: OnlineAudioQuality = .standard) -> String {
        let suffix = quality == .opus ? "|opus:v1" : ""
        return SHA256.hash(data: Data("\(track.source.rawValue)|\(track.location)\(suffix)".utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct PendingAudioDownload: Codable, Sendable, Identifiable {
    var id = UUID()
    var track: Track
    var quality: String
    var replacing: Bool?
    var requestedAt = Date()
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
    private var queueRevision: UInt64 = 0
    init(root: URL = OfflineAudioStore.defaultRoot) { self.root = root }
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
                guard entry.id == OfflineAudioRecord.key(entry.track, quality: entry.quality == "opus" ? .opus : .standard), entry.bytes > 0,
                      (try? path(entry.filename)) != nil else { continue }
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
    func pending() throws -> [PendingAudioDownload] {
        try load()
        let url = root.appendingPathComponent("download-queue.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let requests = try JSONDecoder().decode([PendingAudioDownload].self, from: Data(contentsOf: url))
        var seen = Set<UUID>()
        return requests.filter { seen.insert($0.track.id).inserted && OnlineAudioQuality(rawValue: $0.quality) != nil && [.invidious, .remote, .catalogReference].contains($0.track.source) }
    }
    func savePending(_ requests: [PendingAudioDownload], revision: UInt64) throws {
        try load()
        guard revision >= queueRevision else { return }
        try JSONEncoder().encode(requests).write(to: root.appendingPathComponent("download-queue.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        queueRevision = revision
    }
    func audit() throws -> [String: String] {
        try load()
        var issues: [String: String] = [:]
        for entry in records.values {
            try Task.checkCancellation()
            do { _ = try inspect(entry) } catch { issues[entry.id] = error.localizedDescription }
        }
        return issues
    }
    private func inspect(_ record: OfflineAudioRecord) throws -> NativeAudioInspection {
        let url = try path(record.filename)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.size] as? NSNumber)?.int64Value == record.bytes else { throw BlusicError.message("Fichier manquant ou taille différente. Répare ce téléchargement.") }
        let result = try NativeAudioInspection.inspect(url, expectedDuration: record.duration)
        guard record.quality != "opus" || result.codec == .opus else { throw BlusicError.message("Le fichier n’est pas l’Opus attendu. Répare ce téléchargement.") }
        return result
    }
    func audio(for track: Track, quality: OnlineAudioQuality = .standard) throws -> InvidiousAudio? {
        try load()
        let keys = quality == .opus ? [OfflineAudioRecord.key(track, quality: .opus), OfflineAudioRecord.key(track)] : [OfflineAudioRecord.key(track), OfflineAudioRecord.key(track, quality: .opus)]
        for key in keys {
            guard let record = records[key] else { continue }
            let url = try path(record.filename)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                let inspection = try inspect(record)
                return InvidiousAudio(fileURL: url, bitrate: record.bitrate, instance: URL(string: "https://www.youtube.com")!,
                    duration: record.duration, provider: "Téléchargé · hors ligne" + (record.fallbackReason.map { " · " + $0 } ?? ""), quality: OnlineAudioQuality(rawValue: record.quality) ?? .standard, codec: inspection.codec ?? record.codec ?? .aac)
            } catch { continue } // Try the intact alternate variant, then allow a fresh online resolution.
        }
        return nil
    }
    func save(_ audio: InvidiousAudio, track: Track, preferredQuality: OnlineAudioQuality? = nil) throws -> OfflineAudioRecord {
        try load(); try Task.checkCancellation()
        // A failed Opus attempt must not replace an already downloaded AAC file.
        if preferredQuality == .opus, audio.quality != .opus, let previous = records[OfflineAudioRecord.key(track)] {
            if (try? inspect(previous)) != nil { return previous }
        }
        guard audio.fileURL.isFileURL else { throw BlusicError.message("Le fichier audio complet n’a pas été préparé.") }
        let inspection = try NativeAudioInspection.inspect(audio.fileURL, expectedDuration: audio.duration ?? track.duration)
        let duration = inspection.duration, codec = inspection.codec
        guard audio.quality != .opus || codec == .opus else { throw BlusicError.message("La source reçue n’est pas de l’Opus : aucun faux téléchargement Opus n’a été enregistré. Réessaie ou choisis AAC.") }
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
            let key = OfflineAudioRecord.key(track, quality: audio.quality)
            let entry = OfflineAudioRecord(id: key, track: track, filename: filename, artworkFilename: records[key]?.artworkFilename,
                bytes: size, bitrate: audio.bitrate, duration: duration, quality: audio.quality.rawValue, downloadedAt: Date(), codec: codec,
                fallbackReason: preferredQuality == .opus && codec != .opus ? "Secours AAC · Opus indisponible" : nil)
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
    private(set) var recoverable: [PendingAudioDownload] = []
    private(set) var integrityIssues: [String: String] = [:]
    private(set) var checkingIntegrity = false
    private(set) var integrityCheckedAt: Date?
    private(set) var completedInSession = 0
    var uniqueTrackCount: Int { Set(records.values.map { $0.track.id }).count }
    var failedCount: Int { statuses.values.filter { if case .failed = $0 { return true }; return false }.count }
    @ObservationIgnored private weak var library: LibraryStore?
    @ObservationIgnored private let store: OfflineAudioStore
    @ObservationIgnored private let loader: any OnlineAudioLoading
    @ObservationIgnored private var ready: Task<Void, Never>?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var active: Task<OfflineAudioRecord, Error>?
    @ObservationIgnored private var queue: [PendingAudioDownload] = []
    @ObservationIgnored private var activeRequest: PendingAudioDownload?
    @ObservationIgnored private var attempts: [String: UUID] = [:]
    @ObservationIgnored private var failedQuality: [UUID: OnlineAudioQuality] = [:]
    @ObservationIgnored private var persistenceRevision: UInt64 = 0
    @ObservationIgnored private var persistenceTask: Task<Void, Never>?
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
                let pending = try await store.pending()
                self.recoverable = pending.filter { self.attempts[$0.track.id.uuidString] == nil && !self.cancelled.contains($0.track.id.uuidString) }
                library.add(self.recoverable.map(\.track))
            } catch { self?.error = "Les téléchargements n’ont pas pu être lus. \(error.localizedDescription)" }
        }
    }
    func waitUntilReady() async { await ready?.value }
    func record(for track: Track) -> OfflineAudioRecord? {
        let standard = records[OfflineAudioRecord.key(track)].flatMap { integrityIssues[$0.id] == nil ? $0 : nil }
        let opus = records[OfflineAudioRecord.key(track, quality: .opus)].flatMap { integrityIssues[$0.id] == nil ? $0 : nil }
        return library?.settings.audioQuality == .opus ? opus ?? standard : standard ?? opus
    }
    func status(for track: Track) -> OfflineDownloadStatus? { statuses[track.id.uuidString] }
    func canAddOpusVariant(for track: Track) -> Bool {
        library?.settings.audioQuality == .opus && [.invidious, .catalogReference].contains(track.source)
            && records[OfflineAudioRecord.key(track, quality: .opus)] == nil
    }
    func verifyDownloads() async {
        guard !checkingIntegrity else { return }
        checkingIntegrity = true; defer { checkingIntegrity = false }
        await waitUntilReady()
        do { integrityIssues = try await store.audit(); integrityCheckedAt = Date() }
        catch { self.error = "Vérification interrompue. \(error.localizedDescription)" }
    }
    func repair(_ entry: OfflineAudioRecord) {
        enqueue([entry.track], quality: OnlineAudioQuality(rawValue: entry.quality) ?? .standard, replace: true)
    }
    func retryFailed() {
        guard let library else { return }
        let tracks = library.tracks.filter { if case .failed? = statuses[$0.id.uuidString] { return true }; return false }
        for track in tracks {
            enqueue([track], quality: failedQuality[track.id] ?? library.settings.audioQuality)
        }
    }
    func resumeInterrupted() {
        let requests = recoverable; recoverable = []
        for request in requests { enqueue([request.track], quality: OnlineAudioQuality(rawValue: request.quality) ?? .standard, replace: request.replacing == true) }
        persistQueue()
    }
    func discardInterrupted() { recoverable = []; persistQueue() }
    func isAvailable(_ track: Track) -> Bool { track.isOffline || record(for: track) != nil }
    var totalBytes: Int64 { records.values.reduce(0) { $0 + $1.bytes } }
    var pendingCount: Int { statuses.values.filter(\.isActive).count }
    func artworkURL(for track: Track) -> URL? {
        guard let filename = record(for: track)?.artworkFilename else { return nil }
        return store.root.appendingPathComponent(filename)
    }
    func audio(for track: Track) async throws -> InvidiousAudio? { await waitUntilReady(); return try await store.audio(for: track, quality: library?.settings.audioQuality ?? .standard) }
    func waitUntilIdle() async { await waitUntilReady(); await worker?.value; await persistenceTask?.value }
    func enqueue(_ tracks: [Track]) {
        guard let library else { return }
        enqueue(tracks, quality: library.settings.audioQuality)
    }
    private func enqueue(_ tracks: [Track], quality: OnlineAudioQuality, replace: Bool = false) {
        guard let library else { return }
        for track in library.add(tracks) {
            let existing = quality == .opus ? records[OfflineAudioRecord.key(track, quality: .opus)] : records[OfflineAudioRecord.key(track)]
            let damaged = existing.map { integrityIssues[$0.id] != nil } ?? false
            guard [.invidious, .remote, .catalogReference].contains(track.source), replace || existing == nil || damaged else { continue }
            let key = track.id.uuidString
            guard statuses[key]?.isActive != true else { continue }
            let request = PendingAudioDownload(track: track, quality: quality.rawValue, replacing: replace || damaged)
            cancelled.remove(key); attempts[key] = request.id; statuses[key] = .queued; queue.append(request)
        }
        persistQueue()
        startWorker()
    }
    func cancel(_ track: Track) {
        let key = track.id.uuidString
        cancelled.insert(key); attempts[key] = nil; queue.removeAll { $0.track.id.uuidString == key }; statuses[key] = nil
        recoverable.removeAll { $0.track.id == track.id }
        if activeKey == key { active?.cancel() }
        persistQueue()
    }
    func cancelAll() { for request in queue { cancel(request.track) }; if let key = activeKey { cancelled.insert(key); attempts[key] = nil; active?.cancel(); statuses[key] = nil }; queue.removeAll(); recoverable = []; persistQueue() }
    func remove(_ track: Track) async {
        cancel(track)
        do { for key in [OfflineAudioRecord.key(track), OfflineAudioRecord.key(track, quality: .opus)] { try await store.remove(key); records[key] = nil; integrityIssues[key] = nil } }
        catch { self.error = error.localizedDescription }
    }
    func remove(_ record: OfflineAudioRecord) async {
        cancel(record.track)
        do { try await store.remove(record.id); records[record.id] = nil; integrityIssues[record.id] = nil }
        catch { self.error = error.localizedDescription }
    }
    func removeAll() async { cancelAll(); for record in Array(records.values) { await remove(record.track) } }
    private func persistQueue() {
        persistenceRevision += 1
        let revision = persistenceRevision, store = self.store
        let active = activeRequest.flatMap { attempts[$0.track.id.uuidString] == $0.id ? $0 : nil }
        let requests = (active.map { [$0] } ?? []) + queue
        let previous = persistenceTask, ready = self.ready
        persistenceTask = Task { @MainActor [weak self] in
            await ready?.value; await previous?.value
            do { try await store.savePending((self?.recoverable ?? []) + requests, revision: revision) }
            catch { self?.error = "La file de téléchargements n’a pas pu être sauvegardée. \(error.localizedDescription)" }
        }
    }
    private func startWorker() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            await waitUntilReady()
            while !queue.isEmpty {
                let request = queue.removeFirst(), requested = request.track, key = requested.id.uuidString
                guard attempts[key] == request.id, !cancelled.contains(key), let library else { continue }
                let quality = OnlineAudioQuality(rawValue: request.quality) ?? .standard
                let existing = records[OfflineAudioRecord.key(requested, quality: quality)]
                if request.replacing != true, let existing, integrityIssues[existing.id] == nil {
                    statuses[key] = nil; attempts[key] = nil; persistQueue(); continue
                }
                activeRequest = request
                activeKey = key; statuses[key] = .downloading("Préparation du téléchargement…", nil)
                persistQueue()
                var settings = library.settings
                settings.opusAudio = quality == .opus; settings.highQualityAudio = quality == .high
                let requestedSettings = settings
                let loader = self.loader, store = self.store
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
                                switch try await streaming.playback(track, settings: requestedSettings, direct: false) {
                                case .file(let audio): return audio
                                case .stream(let stream):
                                    let file = try await AudioCache.shared.localCopy(of: stream.url, cacheKey: stream.quality.fileKey(videoID: track.location, bitrate: stream.bitrate),
                                        fileExtension: "m4a", expectedDuration: stream.duration, session: InvidiousService.mediaSession,
                                        progress: { fraction in Task { @MainActor [weak self] in
                                            guard let self, self.attempts[key] == request.id else { return }
                                            self.statuses[key] = .downloading("Récupération du fichier audio…", fraction)
                                        } })
                                    return InvidiousAudio(fileURL: file, bitrate: stream.bitrate, instance: stream.instance, duration: stream.duration, provider: stream.provider, quality: stream.quality)
                                }
                            }
                            return try await loader.load(track, settings: requestedSettings, progress: { update in
                                Task { @MainActor [weak self] in
                                    guard let self, self.attempts[key] == request.id, !self.cancelled.contains(key) else { return }
                                    self.statuses[key] = .downloading(update.message, update.fraction)
                                }
                            })
                        }
                        group.addTask { try await Task.sleep(for: .seconds(120)); throw BlusicError.message("Téléchargement trop lent. Réessaie lorsque la connexion sera disponible.") }
                        defer { group.cancelAll() }; return try await group.next()!
                    }
                    try Task.checkCancellation()
                    guard self?.attempts[key] == request.id else { throw CancellationError() }
                    self?.statuses[key] = .downloading("Vérification du fichier et sauvegarde…", 1)
                    return try await store.save(audio, track: track, preferredQuality: requestedSettings.audioQuality)
                }
                active = task
                do {
                    let entry = try await task.value
                    // A save that committed is kept even if cancellation arrived
                    // immediately afterwards: never delete a previous intact AAC.
                    records[entry.id] = entry; integrityIssues[entry.id] = nil
                    if attempts[key] == request.id {
                        statuses[key] = nil; attempts[key] = nil; failedQuality[requested.id] = nil; completedInSession += 1
                        if let url = entry.track.artworkURL {
                            let image = await ArtworkImageCache.shared.image(for: ArtworkRequest(url: url, pixels: 512))
                            if !cancelled.contains(key), let data = image?.jpegData(compressionQuality: 0.9), let updated = try? await store.saveArtwork(data, key: entry.id) { records[entry.id] = updated }
                        }
                    }
                } catch {
                    if attempts[key] == request.id {
                        if cancelled.contains(key) || error is CancellationError { statuses[key] = nil }
                        else { statuses[key] = .failed(error.localizedDescription); failedQuality[requested.id] = quality }
                    }
                }
                active = nil; activeKey = nil; activeRequest = nil; persistQueue()
            }
            worker = nil
        }
    }
}
