import Foundation
import Security

/// Anonymous iOS player request validated alongside youtubei.js's IOS client.
/// Only ordinary HTTPS AAC URLs are used; no login or deciphering runtime.
struct DirectAudioService: Sendable {
    var session: URLSession = .shared

    func stream(for track: Track) async throws -> InvidiousStream {
        guard InvidiousService.isVideoID(track.location) else { throw BlusicError.message("Identifiant de chanson invalide.") }
        var request = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")!)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Blusic/1.6 (iOS audio source)", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "videoId": track.location, "contentCheckOk": true, "racyCheckOk": true,
            "context": ["client": ["clientName": "iOS", "clientVersion": "20.11.6",
                "deviceMake": "Apple", "deviceModel": "iPhone10,4", "osName": "iOS", "osVersion": "16.7.7.20H330",
                "hl": "fr", "gl": "FR", "platform": "MOBILE"]]
        ])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw BlusicError.message("L’accès audio direct est indisponible (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)).")
        }
        return try Self.parse(data, track: track)
    }

    static func parse(_ data: Data, track: Track) throws -> InvidiousStream {
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BlusicError.message("Réponse audio directe invalide.")
        }
        let status = body["playabilityStatus"] as? [String: Any]
        guard status?["status"] as? String == "OK" else {
            let reason = status?["reason"] as? String ?? "Ce titre n’est pas disponible sans connexion au lecteur officiel."
            throw BlusicError.message("YouTube : \(String(reason.prefix(300)))")
        }
        let details = body["videoDetails"] as? [String: Any]
        guard details?["isLiveContent"] as? Bool != true else { throw BlusicError.message("Les directs ne sont pas des chansons à durée fixe.") }
        let streaming = body["streamingData"] as? [String: Any]
        let formats = streaming?["adaptiveFormats"] as? [[String: Any]] ?? []
        let compatible = formats.filter {
            let mime = ($0["mimeType"] as? String ?? "").lowercased()
            return mime.hasPrefix("audio/mp4") && mime.contains("mp4a") && $0["url"] is String
                && $0["drmFamilies"] == nil && $0["drmTrackType"] == nil
        }.sorted { ($0["bitrate"] as? Int ?? 0) > ($1["bitrate"] as? Int ?? 0) }
        for format in compatible {
            guard let address = format["url"] as? String, let url = URL(string: address), url.scheme == "https",
                  let host = url.host?.lowercased(), host.hasSuffix(".googlevideo.com"), url.user == nil, url.password == nil else { continue }
            let seconds = (details?["lengthSeconds"] as? String).flatMap(Double.init) ?? track.duration
            return InvidiousStream(url: url, bitrate: format["bitrate"] as? Int ?? 0,
                instance: URL(string: "https://www.youtube.com")!, duration: seconds)
        }
        throw BlusicError.message("Aucun flux AAC direct disponible pour ce titre. Essaie le relais Invidious ou le lecteur officiel.")
    }
}

/// First usable source wins, rather than waiting for a broken relay to time out.
struct OnlineStreamResolver: Sendable {
    var session: URLSession = .shared
    var relayAccess: @Sendable (String) -> String? = { address in
        RelayKeychain.read(server: address) ?? BundledRelayConfiguration.load()?.access(for: address)
    }

    func resolve(_ track: Track, settings: AppSettings, avoiding previous: InvidiousStream? = nil) async throws -> InvidiousStream {
        let mode = settings.audioSourceMode
        let useDirect = ["auto", "direct"].contains(mode) && (previous == nil || previous?.isYouTubeDirect == false || mode == "direct")
        let useRelay = ["auto", "invidious"].contains(mode) && (previous == nil || previous?.isYouTubeDirect == true || mode == "invidious")
        let configuredAddress = settings.youtubeiRelayDisabled == true ? nil : settings.youtubeiRelayAddress
        let configuredKey = configuredAddress.flatMap { relayAccess($0) }
        if mode == "youtubei", configuredAddress == nil || configuredKey == nil {
            throw BlusicError.message("Le relais youtubei.js n’est pas configuré. Active le relais préconfiguré dans Réglages → Relais youtubei.js.")
        }
        return try await withThrowingTaskGroup(of: Result<InvidiousStream, Error>.self) { group in
            if ["auto", "youtubei"].contains(mode), previous?.provider != "youtubei.js" || mode == "youtubei", let address = configuredAddress,
               let server = try? InvidiousService.instanceURL(address), let key = configuredKey {
                group.addTask {
                    do { return .success(try await YouTubeRelayService(session: session).stream(for: track, server: server, key: key)) }
                    catch { return .failure(error) }
                }
            }
            if useDirect {
                group.addTask {
                    do {
                        let stream = try await DirectAudioService(session: session).stream(for: track)
                        try await Self.validateMedia(stream, session: session)
                        return .success(stream)
                    } catch { return .failure(error) }
                }
            }
            if useRelay {
                group.addTask {
                    do {
                        // A short head start avoids a relay request for fast direct resolutions.
                        if useDirect { try await Task.sleep(for: .milliseconds(350)) }
                        let service = try InvidiousService(address: settings.invidiousAddress,
                            automaticFallback: settings.usesInvidiousFallback, session: session)
                        let stream = try await service.stream(for: track, preferProxy: true)
                        return .success(stream)
                    } catch { return .failure(error) }
                }
            }
            var failures: [String] = []
            while let outcome = try await group.next() {
                try Task.checkCancellation()
                switch outcome {
                case .success(let stream): group.cancelAll(); return stream
                case .failure(let error): failures.append(error.localizedDescription)
                }
            }
            throw BlusicError.message("Aucune source audio accessible. Réessaie ou choisis un autre accès dans Réglages → Sources audio.\n" + failures.joined(separator: "\n"))
        }
    }

    static func validateMedia(_ stream: InvidiousStream, session: URLSession) async throws {
        var request = URLRequest(url: stream.url)
        request.timeoutInterval = 4
        request.setValue("bytes=0-4095", forHTTPHeaderField: "Range")
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse, [200, 206].contains(http.statusCode) else {
            throw BlusicError.message("Le flux \(stream.providerLabel) refuse la lecture (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)).")
        }
        var header = Data()
        for try await byte in bytes.prefix(64) { header.append(byte) }
        guard header.range(of: Data("ftyp".utf8)) != nil else {
            throw BlusicError.message("Le serveur renvoie une page ou un fichier non AAC/M4A.")
        }
        // A few cached opening bytes are not proof that the rest of the song
        // is authorized. Probe a second finite range on the same signed URL.
        if let value = http.value(forHTTPHeaderField: "Content-Range"), let range = AudioByteRange.parse(value), range.total > 4096 {
            bytes.task.cancel()
            let offset = max(4096, range.total / 2)
            let end = min(offset + 63, range.total - 1)
            var following = URLRequest(url: stream.url)
            following.timeoutInterval = 4
            following.setValue("bytes=\(offset)-\(end)", forHTTPHeaderField: "Range")
            let (rest, nextResponse) = try await session.bytes(for: following)
            defer { rest.task.cancel() }
            guard let next = nextResponse as? HTTPURLResponse, next.statusCode == 206 else {
                throw BlusicError.message("\(stream.providerLabel) : début du fichier accessible, mais la suite est refusée (HTTP \((nextResponse as? HTTPURLResponse)?.statusCode ?? 0)).")
            }
            guard let raw = next.value(forHTTPHeaderField: "Content-Range"), let nextRange = AudioByteRange.parse(raw), nextRange.start == offset,
                  nextRange.total == range.total else { throw BlusicError.message("Le serveur ne respecte pas les plages du fichier audio.") }
            var count = 0
            for try await _ in rest.prefix(64) { count += 1 }
            guard count == end - offset + 1 else { throw BlusicError.message("La suite du fichier audio est vide ou tronquée.") }
        }
    }
}

struct YouTubeRelayService {
    var session: URLSession = .shared
    func stream(for track: Track, server: URL, key: String) async throws -> InvidiousStream {
        guard InvidiousService.isVideoID(track.location) else { throw BlusicError.message("Identifiant musical invalide.") }
        var request = URLRequest(url: server.appendingPathComponent("v1/streams/\(track.location)"))
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let detail = (payload?["error"] as? String).map {
                String($0.prefix(500)).replacingOccurrences(of: #"https?://[^\s]+"#, with: "[source]", options: .regularExpression)
            }
            throw BlusicError.message("Relais youtubei.js : HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)." + (detail.map { "\n" + $0 } ?? ""))
        }
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let path = payload?["url"] as? String, let url = URL(string: path, relativeTo: server)?.absoluteURL,
              url.scheme == "https", url.host == server.host, url.port == server.port,
              url.user == nil, url.password == nil, url.path.hasPrefix("/v1/audio/") else {
            throw BlusicError.message("Le relais youtubei.js n’a pas renvoyé un lien audio du même serveur.")
        }
        let stream = InvidiousStream(url: url, bitrate: payload?["bitrate"] as? Int ?? 0, instance: server,
            duration: payload?["duration"] as? Double ?? track.duration, provider: "youtubei.js")
        try await OnlineStreamResolver.validateMedia(stream, session: session)
        return stream
    }
}

struct BundledRelayConfiguration: Sendable {
    let server: URL
    let applicationAccess: String
    let revision: String

    static func load(bundle: Bundle = .main) -> Self? {
        guard let data = bundle.object(forInfoDictionaryKey: "BlusicBundledRelay") as? [String: Any] else { return nil }
        return parse(data)
    }
    static func parse(_ data: [String: Any]) -> Self? {
        guard let address = data["url"] as? String, let server = try? InvidiousService.instanceURL(address),
              server.path.isEmpty || server.path == "/",
              let access = data["access"] as? String, access.range(of: #"^app\.ios\.[a-f0-9]{64}$"#, options: .regularExpression) != nil,
              let expiry = data["expiresAt"] as? NSNumber, expiry.int64Value == 0,
              let revision = data["revision"] as? String, !revision.isEmpty else { return nil }
        return Self(server: server, applicationAccess: access, revision: revision)
    }
    func access(for address: String) -> String? {
        guard let candidate = try? InvidiousService.instanceURL(address), candidate == server else { return nil }
        return applicationAccess
    }
    /// Migrate once per build configuration. Respect an explicit opt-out and a
    /// custom server, and never put the credential in Codable library settings.
    func install(settings: inout AppSettings, installedRevision: String?, save: (String, String) throws -> Void) throws -> Bool {
        guard installedRevision != revision, settings.youtubeiRelayDisabled != true else { return false }
        if let address = settings.youtubeiRelayAddress, !address.isEmpty, address != server.absoluteString { return false }
        try save(applicationAccess, server.absoluteString)
        settings.youtubeiRelayAddress = server.absoluteString
        settings.youtubeiRelayDisabled = false
        settings.onlineAudioMode = "auto"
        return true
    }
    @MainActor
    func install(in library: LibraryStore, defaults: UserDefaults = .standard) throws {
        let key = "blusic.bundledRelay.revision"
        var settings = library.settings
        let changed = try install(settings: &settings, installedRevision: defaults.string(forKey: key)) {
            try RelayKeychain.save($0, server: $1)
        }
        if changed { library.settings = settings; defaults.set(revision, forKey: key) }
    }
}

/// Relay access credentials stay out of exported library JSON snapshots.
enum RelayKeychain {
    private static func query(server: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.blusic.youtubei-relay", kSecAttrAccount as String: server]
    }
    static func read(server: String) -> String? {
        var query = query(server: server)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ key: String, server: String) throws {
        let query = query(server: server)
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let insert = query.merging(attributes) { _, new in new }
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw BlusicError.message("Impossible d’enregistrer la clé du relais dans le trousseau.") }
        } else if status != errSecSuccess { throw BlusicError.message("Impossible de mettre à jour la clé du relais.") }
    }
}
