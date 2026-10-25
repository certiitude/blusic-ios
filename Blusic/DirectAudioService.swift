import Foundation

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

    func resolve(_ track: Track, settings: AppSettings, avoiding previous: InvidiousStream? = nil) async throws -> InvidiousStream {
        let mode = settings.audioSourceMode
        let useDirect = mode != "invidious" && (previous == nil || previous?.isYouTubeDirect == false || mode == "direct")
        let useRelay = mode != "direct" && (previous == nil || previous?.isYouTubeDirect == true || mode == "invidious")
        return try await withThrowingTaskGroup(of: Result<InvidiousStream, Error>.self) { group in
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
                        try await Self.validateMedia(stream, session: session)
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
    }
}
