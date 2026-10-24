import Foundation

struct InvidiousVideo: Decodable {
    struct Thumbnail: Decodable { var url: String; var width: Int? }
    var type: String?
    var videoId: String?
    var title: String?
    var author: String?
    var lengthSeconds: Int?
    var liveNow: Bool?
    var isUpcoming: Bool?
    var videoThumbnails: [Thumbnail]?

    func track(on instance: URL) -> Track? {
        guard let videoId, InvidiousService.isVideoID(videoId), let title, !title.isEmpty,
              liveNow != true, isUpcoming != true,
              !["[Deleted video]", "[Private video]", "Deleted video", "Private video"].contains(title) else { return nil }
        let cover = videoThumbnails?.sorted { ($0.width ?? 0) > ($1.width ?? 0) }
            .first { ($0.width ?? 0) <= 640 } ?? videoThumbnails?.first
        let artworkURL = cover.flatMap { URL(string: $0.url, relativeTo: instance)?.absoluteURL }
        return Track(title: title, artist: author ?? "YouTube", duration: Double(lengthSeconds ?? 0),
                     source: .invidious, location: videoId,
                     artworkURL: artworkURL?.scheme == "https" ? artworkURL : nil, originInstance: instance)
    }
}

struct InvidiousFormat: Decodable {
    var url: String
    var type: String
    var bitrate: Int
    var sampleRate: Int?

    enum CodingKeys: String, CodingKey { case url, type, bitrate, audioSampleRate }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        url = try values.decode(String.self, forKey: .url)
        type = try values.decode(String.self, forKey: .type)
        bitrate = (try? values.decode(Int.self, forKey: .bitrate))
            ?? (try? values.decode(String.self, forKey: .bitrate)).flatMap(Int.init) ?? 0
        sampleRate = (try? values.decode(Int.self, forKey: .audioSampleRate))
            ?? (try? values.decode(String.self, forKey: .audioSampleRate)).flatMap(Int.init)
    }
    var isCompatibleAAC: Bool {
        let mime = type.lowercased()
        return mime.hasPrefix("audio/mp4") && mime.contains("mp4a")
    }
}

struct InvidiousDetails: Decodable {
    var title: String?
    var lengthSeconds: Int?
    var adaptiveFormats: [InvidiousFormat]?
    var error: String?

    var compatibleFormats: [InvidiousFormat] {
        (adaptiveFormats ?? []).filter(\.isCompatibleAAC).sorted { $0.bitrate > $1.bitrate }
    }
}

struct InvidiousPlaylistPage: Decodable {
    var title: String?
    var videoCount: Int?
    var videos: [InvidiousVideo]?
}

struct InvidiousAudio: Sendable {
    var fileURL: URL
    var bitrate: Int
    var instance: URL
}

struct AudioLoadUpdate: Sendable {
    var message: String
    var fraction: Double? = nil
}

protocol OnlineAudioLoading: Sendable {
    func load(_ track: Track, settings: AppSettings, progress: @escaping @Sendable (AudioLoadUpdate) -> Void) async throws -> InvidiousAudio
}

struct InvidiousStream: Sendable {
    var url: URL
    var bitrate: Int
    var instance: URL
    var duration: Double
}

enum OnlinePlaybackResource: Sendable {
    case file(InvidiousAudio)
    case stream(InvidiousStream)
}

protocol StreamingAudioLoading: OnlineAudioLoading {
    func playback(_ track: Track, settings: AppSettings, direct: Bool) async throws -> OnlinePlaybackResource
}

struct InvidiousAudioLoader: StreamingAudioLoading {
    func load(_ track: Track, settings: AppSettings, progress: @escaping @Sendable (AudioLoadUpdate) -> Void) async throws -> InvidiousAudio {
        let service = try InvidiousService(address: settings.invidiousAddress, automaticFallback: settings.usesInvidiousFallback)
        return try await service.audio(for: track, progress: progress)
    }
    func playback(_ track: Track, settings: AppSettings, direct: Bool = false) async throws -> OnlinePlaybackResource {
        if let cached = await AudioCache.shared.cachedInvidious(track: track) { return .file(cached) }
        let stream = try await InvidiousStreamCache.shared.resolve(track, settings: settings, direct: direct)
        return .stream(stream)
    }
    static func prefetch(_ tracks: [Track], settings: AppSettings) async {
        for track in tracks.prefix(2) {
            guard !Task.isCancelled else { return }
            _ = try? await InvidiousStreamCache.shared.resolve(track, settings: settings, direct: false)
        }
    }
}

private actor InvidiousStreamCache {
    static let shared = InvidiousStreamCache()
    private var values: [String: (Date, InvidiousStream)] = [:]
    private var pending: [String: Task<InvidiousStream, Error>] = [:]
    func resolve(_ track: Track, settings: AppSettings, direct: Bool) async throws -> InvidiousStream {
        let key = "\(settings.invidiousAddress)|\(settings.usesInvidiousFallback)|\(track.location)|\(direct)"
        if let (expiry, value) = values[key], expiry > Date() { return value }
        if let task = pending[key] { return try await task.value }
        let task = Task {
            let service = try InvidiousService(address: settings.invidiousAddress, automaticFallback: settings.usesInvidiousFallback)
            return try await service.stream(for: track, preferProxy: !direct)
        }
        pending[key] = task
        do {
            let result = try await task.value
            values[key] = (Date().addingTimeInterval(120), result)
            pending[key] = nil
            if values.count > 40 { values = values.filter { $0.value.0 > Date() } }
            return result
        } catch { pending[key] = nil; throw error }
    }
}

struct InvidiousService {
    static let defaultInstance = "https://yt.chocolatemoo53.com"
    var instance: URL
    var automaticFallback: Bool
    var session: URLSession
    static let mediaSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 7
        // Full-file preparation is separate from progressive playback. Some
        // hosts throttle complete downloads; it must not delay the first sound.
        config.timeoutIntervalForResource = 90
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    init(address: String = Self.defaultInstance, automaticFallback: Bool = true, session: URLSession = .shared) throws {
        instance = try Self.instanceURL(address)
        self.automaticFallback = automaticFallback
        self.session = session
    }

    static func instanceURL(_ address: String) throws -> URL {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw BlusicError.message("Indique l’adresse HTTPS d’une instance Invidious, sans identifiants ni paramètres.")
        }
        return url
    }

    static func isVideoID(_ id: String) -> Bool { id.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil }

    /// Resolve a progressive AAC URL without downloading the whole song.
    func stream(for track: Track, preferProxy: Bool) async throws -> InvidiousStream {
        guard Self.isVideoID(track.location) else { throw BlusicError.message("Identifiant de chanson invalide.") }
        let result: (InvidiousDetails, URL) = try await request("videos/\(track.location)", parameters: preferProxy ? ["local": "true"] : [:])
        guard let format = result.0.compatibleFormats.first,
              let url = URL(string: format.url, relativeTo: result.1)?.absoluteURL, url.scheme == "https" else {
            throw BlusicError.message("Aucun flux AAC progressif n’est disponible pour ce titre sur cette instance.")
        }
        return InvidiousStream(url: url, bitrate: format.bitrate, instance: result.1, duration: Double(result.0.lengthSeconds ?? 0))
    }

    func search(_ query: String, page: Int = 1) async throws -> [Track] {
        let result: ([InvidiousVideo], URL) = try await request("search", parameters: [
            "q": query, "type": "video", "page": String(max(1, page)), "sort_by": "relevance"
        ])
        var seen = Set<String>()
        return result.0.filter { $0.type == "video" }.compactMap { video in
            guard let track = video.track(on: result.1), seen.insert(track.location).inserted else { return nil }
            return track
        }
    }

    func playlist(_ url: URL) async throws -> (name: String, tracks: [Track]) {
        guard let host = url.host?.lowercased(),
              ["youtube.com", "www.youtube.com", "music.youtube.com", "m.youtube.com", instance.host?.lowercased() ?? ""].contains(host),
              let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "list" })?.value,
              id.range(of: #"^[A-Za-z0-9_-]{10,128}$"#, options: .regularExpression) != nil else {
            throw BlusicError.message("Colle une playlist publique YouTube/YouTube Music contenant « list= ». Les radios dynamiques ne sont pas des playlists publiques.")
        }
        var tracks: [Track] = []
        var seen = Set<String>()
        var loaded = 0
        var title = "Ma playlist YouTube"
        for page in 1...41 {
            try Task.checkCancellation()
            let result: (InvidiousPlaylistPage, URL) = try await request("playlists/\(id)", parameters: ["page": String(page)])
            if let name = result.0.title, !name.isEmpty { title = name }
            let batch = result.0.videos ?? []
            if batch.isEmpty { return (title, tracks) }
            loaded += batch.count
            guard loaded <= 2000 else { throw BlusicError.message("La playlist dépasse la limite de 2 000 titres. Importe une sélection plus courte.") }
            let new = batch.compactMap { $0.track(on: result.1) }.filter { seen.insert($0.location).inserted }
            tracks.append(contentsOf: new)
            if page > 1, new.isEmpty { throw BlusicError.message("L’instance répète la même page de playlist. Change d’instance pour récupérer la liste complète.") }
            if let count = result.0.videoCount, loaded >= count { return (title, tracks) }
        }
        throw BlusicError.message("La pagination de cette playlist n’a pas pu être terminée. Essaie une autre instance.")
    }

    /// Resolve URLs afresh, download AAC and retry through the same instance's proxy.
    /// Only the video ID and discovery origin are persisted by the library.
    func audio(for track: Track, progress: @escaping @Sendable (AudioLoadUpdate) -> Void = { _ in }) async throws -> InvidiousAudio {
        guard Self.isVideoID(track.location) else { throw BlusicError.message("Identifiant YouTube invalide.") }
        if let cached = await AudioCache.shared.cachedInvidious(track: track) {
            progress(AudioLoadUpdate(message: "Audio en cache", fraction: 1))
            return cached
        }
        var attempted = Set<URL>()
        var failures: [String] = []
        var servers = [instance]
        if automaticFallback, let origin = track.originInstance,
           let validated = try? Self.instanceURL(origin.absoluteString), validated != instance { servers.append(validated) }
        var discovered = false
        while !servers.isEmpty {
            let server = servers.removeFirst()
            guard attempted.insert(server).inserted else { continue }
            do {
                // Prefer the relay: direct signed media can be bound to the instance IP,
                // which behaves differently on a real iPhone than on a cloud test runner.
                var hasAAC = false
                for local in [true, false] {
                    progress(AudioLoadUpdate(message: local ? "Connexion au relais audio…" : "Essai de l’accès direct…"))
                    let details: InvidiousDetails = try await get("videos/\(track.location)", on: server,
                                                                 parameters: local ? ["local": "true"] : [:])
                    if let error = details.error { throw BlusicError.message(error) }
                    let formats = details.compatibleFormats
                    hasAAC = hasAAC || !formats.isEmpty
                    for format in formats.prefix(2) {
                        try Task.checkCancellation()
                        guard let url = URL(string: format.url, relativeTo: server)?.absoluteURL, url.scheme == "https" else { continue }
                        do {
                            progress(AudioLoadUpdate(message: "Chargement de l’audio…"))
                            let file = try await AudioCache.shared.localCopy(of: url,
                                cacheKey: "invidious:\(track.location):aac:\(format.bitrate)", fileExtension: "m4a",
                                expectedDuration: Double(details.lengthSeconds ?? 0), session: Self.mediaSession,
                                progress: { fraction in progress(AudioLoadUpdate(message: "Chargement de l’audio…", fraction: fraction)) })
                            await AudioCache.shared.storeInvidiousInfo(track: track, bitrate: format.bitrate, instance: server)
                            return InvidiousAudio(fileURL: file, bitrate: format.bitrate, instance: server)
                        } catch {
                            try Self.rethrowCancellation(error)
                            failures.append("\(server.host ?? "Instance") : flux \(local ? "relayé" : "direct") inaccessible")
                        }
                    }
                }
                if !hasAAC { failures.append("\(server.host ?? "Instance") : aucun flux AAC/M4A compatible avec iOS") }
            } catch {
                try Self.rethrowCancellation(error)
                failures.append("\(server.host ?? "Instance") : \(error.localizedDescription)")
            }
            if servers.isEmpty, automaticFallback, !discovered {
                discovered = true
                servers = await InvidiousDirectory.shared.alternatives(excluding: attempted)
            }
        }
        throw BlusicError.message("Le flux audio de ce titre est inaccessible. Essaie une autre instance dans Réglages → Invidious, ou ouvre le lecteur officiel depuis le menu du titre.\n" + failures.suffix(3).joined(separator: "\n"))
    }

    func checkConnection() async throws -> String {
        let tracks = try await search("musique")
        guard !tracks.isEmpty else { throw BlusicError.message("L’API répond, mais aucun résultat n’a été renvoyé.") }
        return "API accessible · \(tracks.count) résultats · \(tracks.first?.originInstance?.host ?? instance.host ?? "Invidious")"
    }

    private func request<T: Decodable>(_ endpoint: String, parameters: [String: String]) async throws -> (T, URL) {
        do { return (try await get(endpoint, on: instance, parameters: parameters), instance) }
        catch {
            try Self.rethrowCancellation(error)
            guard automaticFallback else { throw error }
            var message = "\(instance.host ?? "Instance") : \(error.localizedDescription)"
            for server in await InvidiousDirectory.shared.alternatives(excluding: [instance]) {
                do { return (try await get(endpoint, on: server, parameters: parameters), server) }
                catch { try Self.rethrowCancellation(error); message += "\n\(server.host ?? "Instance") : \(error.localizedDescription)" }
            }
            throw BlusicError.message("Invidious indisponible. Change d’instance dans les réglages.\n" + message)
        }
    }

    private func get<T: Decodable>(_ endpoint: String, on server: URL, parameters: [String: String]) async throws -> T {
        try Task.checkCancellation()
        var components = URLComponents(url: server.appendingPathComponent("api/v1/" + endpoint), resolvingAgainstBaseURL: false)!
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Blusic/1.1 (iOS; Invidious client)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BlusicError.message("Réponse réseau invalide.") }
        guard (200...299).contains(http.statusCode) else {
            switch http.statusCode {
            case 401, 403: throw BlusicError.message("Cette instance bloque l’accès à son API (\(http.statusCode)).")
            case 404: throw BlusicError.message("Titre, playlist ou API introuvable sur cette instance.")
            case 429: throw BlusicError.message("Trop de requêtes sur cette instance. Patiente ou change de serveur.")
            default: throw BlusicError.message("Erreur du serveur Invidious (\(http.statusCode)).")
            }
        }
        if let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let error = body["error"] as? String {
            throw BlusicError.message("Invidious : \(error)")
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw BlusicError.message("L’instance ne renvoie pas la réponse JSON attendue. Un portail ou un CAPTCHA peut bloquer son API.") }
    }

    private static func rethrowCancellation(_ error: Error) throws {
        if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
    }
}

private actor InvidiousDirectory {
    static let shared = InvidiousDirectory()
    private var cached: [URL] = []
    private var expires = Date.distantPast

    func alternatives(excluding: Set<URL>) async -> [URL] {
        if Date() >= expires {
            do {
                var request = URLRequest(url: URL(string: "https://api.invidious.io/instances.json")!)
                request.timeoutInterval = 10
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let entries = try JSONSerialization.jsonObject(with: data) as? [[Any]] else { return [] }
                cached = entries.compactMap { entry in
                    guard entry.count == 2, let values = entry[1] as? [String: Any], values["api"] as? Bool == true,
                          let uri = values["uri"] as? String else { return nil }
                    return try? InvidiousService.instanceURL(uri)
                }
                expires = Date().addingTimeInterval(3600)
            } catch { return [] }
        }
        var seen = excluding
        return Array(cached.filter { seen.insert($0).inserted }.prefix(2))
    }
}
