import Foundation

struct MusicSearchPage {
    var tracks: [Track]
    var continuation: String?
}

/// Public YouTube Music metadata search. Invidious remains the audio resolver.
/// No fallback to generic YouTube video search: a song must be identified as an ATV.
struct MusicCatalogService {
    static let songsFilter = "EgWKAQIIAWoMEA4QChADEAQQCRAF"
    static let clientVersion = "1.20261021.01.00"
    var session: URLSession = .shared

    func search(_ query: String, continuation: String? = nil) async throws -> MusicSearchPage {
        var components = URLComponents(string: "https://music.youtube.com/youtubei/v1/search")!
        components.queryItems = [URLQueryItem(name: "prettyPrint", value: "false")]
        if let continuation { components.queryItems?.append(URLQueryItem(name: "continuation", value: continuation)) }
        let body: [String: Any] = [
            "context": ["client": ["clientName": "WEB_REMIX", "clientVersion": Self.clientVersion, "hl": "fr", "gl": "FR"]],
            "query": query, "params": Self.songsFilter
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue("67", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(Self.clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("Blusic/1.2 (YouTube Music catalog client)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw BlusicError.message("La recherche YouTube Music est indisponible. Réessaie dans quelques instants.")
        }
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> MusicSearchPage {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], root["error"] == nil else {
            throw BlusicError.message("YouTube Music n’a pas renvoyé un catalogue exploitable.")
        }
        var seen = Set<String>()
        let tracks = dictionaries(named: "musicResponsiveListItemRenderer", in: root).compactMap { row -> Track? in
            guard row["musicItemRendererDisplayPolicy"] as? String != "MUSIC_ITEM_RENDERER_DISPLAY_POLICY_GREY_OUT" else { return nil }
            let types = strings(named: "musicVideoType", in: row)
            guard types.contains("MUSIC_VIDEO_TYPE_ATV"), !types.contains("MUSIC_VIDEO_TYPE_OMV") else { return nil }
            let columns = (row["flexColumns"] as? [[String: Any]] ?? []).map { column -> [[String: Any]] in
                let renderer = column["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any] ?? [:]
                let text = renderer["text"] as? [String: Any] ?? [:]
                return text["runs"] as? [[String: Any]] ?? []
            }
            guard let titleColumn = columns.first else { return nil }
            let title = titleColumn.compactMap { $0["text"] as? String }.joined()
            let id = (row["playlistItemData"] as? [String: Any])?["videoId"] as? String
                ?? strings(named: "videoId", in: titleColumn).first
            guard let id, InvidiousService.isVideoID(id), !title.isEmpty, seen.insert(id).inserted else { return nil }
            let runs = Array(columns.dropFirst()).flatMap { $0 }
            var artists: [String] = []
            var album = ""
            for run in runs {
                guard let text = run["text"] as? String,
                      let endpoint = run["navigationEndpoint"] as? [String: Any],
                      let browse = endpoint["browseEndpoint"] as? [String: Any], let browseID = browse["browseId"] as? String else { continue }
                if browseID.hasPrefix("UC"), !artists.contains(text) { artists.append(text) }
                if browseID.hasPrefix("MPRE"), album.isEmpty { album = text }
            }
            let duration = runs.compactMap { ($0["text"] as? String).flatMap(parseDuration) }.first ?? 0
            let thumbnails = dictionaries(named: "musicThumbnailRenderer", in: row)
                .flatMap { dictionaries(named: "thumbnail", in: $0) }
                .flatMap { $0["thumbnails"] as? [[String: Any]] ?? [] }
            let sorted = thumbnails.sorted { ($0["width"] as? Int ?? 0) > ($1["width"] as? Int ?? 0) }
            let cover = sorted.first { ($0["width"] as? Int ?? 0) <= 640 } ?? sorted.first
            let artwork = (cover?["url"] as? String).flatMap(URL.init(string:))
            let explicit = strings(named: "iconType", in: row).contains("MUSIC_EXPLICIT_BADGE")
            return Track(title: title, artist: artists.joined(separator: ", "), album: album, duration: duration,
                         source: .invidious, location: id, artworkURL: artwork?.scheme == "https" ? artwork : nil,
                         isExplicit: explicit, musicCatalog: "youtube-music")
        }
        let continuation = dictionaries(named: "nextContinuationData", in: root).compactMap { $0["continuation"] as? String }.first
            ?? dictionaries(named: "continuationCommand", in: root).compactMap { $0["token"] as? String }.first
        return MusicSearchPage(tracks: tracks, continuation: continuation)
    }

    private static func parseDuration(_ input: String) -> Double? {
        let parts = input.split(separator: ":")
        guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        return parts.reduce(0.0) { $0 * 60 + (Double($1) ?? 0) }
    }
    private static func dictionaries(named key: String, in value: Any) -> [[String: Any]] {
        if let dict = value as? [String: Any] {
            let found = (dict[key] as? [String: Any]).map { [$0] } ?? []
            return found + dict.values.flatMap { dictionaries(named: key, in: $0) }
        }
        if let array = value as? [Any] { return array.flatMap { dictionaries(named: key, in: $0) } }
        return []
    }
    private static func strings(named key: String, in value: Any) -> [String] {
        if let dict = value as? [String: Any] {
            let found = (dict[key] as? String).map { [$0] } ?? []
            return found + dict.values.flatMap { strings(named: key, in: $0) }
        }
        if let array = value as? [Any] { return array.flatMap { strings(named: key, in: $0) } }
        return []
    }
}
