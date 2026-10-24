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
        try Self.parse(await call("search", payload: ["query": query, "params": Self.songsFilter], continuation: continuation))
    }

    func searchArtists(_ query: String) async throws -> [MusicArtist] {
        let data = try await call("search", payload: ["query": query, "params": "EgWKAQIgAWoMEA4QChADEAQQCRAF"])
        return try Self.parseArtists(data)
    }

    func match(_ reference: Track) async throws -> Track {
        let primary = reference.artist.components(separatedBy: CharacterSet(charactersIn: ";,")).first ?? reference.artist
        let page = try await search("\(Self.matchTitle(reference.title)) \(primary)")
        let ranked = page.tracks.map { ($0, Self.matchScore(reference, $0)) }.sorted { $0.1 > $1.1 }
        guard let best = ranked.first, best.1 >= 85 else {
            throw BlusicError.message("Aucune correspondance suffisamment sûre pour « \(reference.title) ». Choisis le bon titre manuellement.")
        }
        return best.0
    }

    static func matchScore(_ reference: Track, _ candidate: Track) -> Int {
        let title = PlaylistImporter.normalize(matchTitle(reference.title)), found = PlaylistImporter.normalize(matchTitle(candidate.title))
        let artists = artistKeys(reference.artist), singers = artistKeys(candidate.artist)
        guard !title.isEmpty, !artists.isEmpty else { return 0 }
        let versionWords: Set<String> = ["live", "remix", "acoustic", "acoustique", "instrumental", "karaoke", "slowed", "sped", "nightcore"]
        let originalWords = Set(reference.title.lowercased().split { !$0.isLetter }.map(String.init))
        let candidateWords = Set(candidate.title.lowercased().split { !$0.isLetter }.map(String.init))
        guard originalWords.intersection(versionWords) == candidateWords.intersection(versionWords) else { return 0 }
        var score = title == found ? 60 : (title.count >= 4 && (found.contains(title) || title.contains(found)) ? 40 : 0)
        if !artists.intersection(singers).isEmpty { score += 35 }
        if reference.duration > 0 {
            let difference = abs(reference.duration - candidate.duration)
            if difference <= 4 { score += 10 }
            else if difference > max(12, reference.duration * 0.1) { score -= 30 }
        }
        if reference.isExplicit && !candidate.isExplicit { score -= 20 }
        if !reference.album.isEmpty, PlaylistImporter.normalize(reference.album) == PlaylistImporter.normalize(candidate.album) { score += 5 }
        return score
    }

    static func matchTitle(_ value: String) -> String {
        value.replacingOccurrences(of: #"(?i)\s*[\(\[](?:feat\.?|ft\.?|featuring|avec)[^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\s*[-–\(\[]\s*(?:\d{4}\s*)?remaster(?:ed)?[^\)\]]*[\)\]]?\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
    private static func artistKeys(_ value: String) -> Set<String> {
        let names = [value] + value.components(separatedBy: CharacterSet(charactersIn: ";,"))
        let ignored: Set<String> = ["and", "et", "feat", "ft", "featuring", "avec"]
        return Set(names.map { name in
            name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
                .split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { !ignored.contains($0) }.joined()
        }.filter { !$0.isEmpty })
    }

    func artist(_ known: MusicArtist) async throws -> ArtistProfile {
        guard known.id.hasPrefix("UC") || known.id.hasPrefix("MPLA") else { throw BlusicError.message("Identifiant d’artiste invalide.") }
        let data = try await call("browse", payload: ["browseId": known.id])
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], root["error"] == nil else {
            throw BlusicError.message("Le profil de cet artiste est indisponible.")
        }
        let header = (Self.dictionaries(named: "musicImmersiveHeaderRenderer", in: root) + Self.dictionaries(named: "musicVisualHeaderRenderer", in: root)).first ?? [:]
        let name = Self.text(header["title"])
        let biography = Self.text(header["description"])
        var artist = known
        if !name.isEmpty { artist.name = name }
        artist.artworkURL = Self.artwork(in: header) ?? known.artworkURL
        let page = try Self.parse(data)
        return ArtistProfile(artist: artist, biography: biography, tracks: page.tracks)
    }

    private func call(_ endpoint: String, payload: [String: Any], continuation: String? = nil) async throws -> Data {
        var components = URLComponents(string: "https://music.youtube.com/youtubei/v1/" + endpoint)!
        components.queryItems = [URLQueryItem(name: "prettyPrint", value: "false")]
        if let continuation { components.queryItems?.append(URLQueryItem(name: "continuation", value: continuation)) }
        var body = payload
        body["context"] = ["client": ["clientName": "WEB_REMIX", "clientVersion": Self.clientVersion, "hl": "fr", "gl": "FR"]]
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
        return data
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
            var artistID: String?
            var album = ""
            for run in runs {
                guard let text = run["text"] as? String,
                      let endpoint = run["navigationEndpoint"] as? [String: Any],
                      let browse = endpoint["browseEndpoint"] as? [String: Any], let browseID = browse["browseId"] as? String else { continue }
                if browseID.hasPrefix("UC"), !artists.contains(text) { artists.append(text); if artistID == nil { artistID = browseID } }
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
                         isExplicit: explicit, musicCatalog: "youtube-music", artistID: artistID)
        }
        let continuation = dictionaries(named: "nextContinuationData", in: root).compactMap { $0["continuation"] as? String }.first
            ?? dictionaries(named: "continuationCommand", in: root).compactMap { $0["token"] as? String }.first
        return MusicSearchPage(tracks: tracks, continuation: continuation)
    }

    static func parseArtists(_ data: Data) throws -> [MusicArtist] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], root["error"] == nil else {
            throw BlusicError.message("La recherche d’artistes est indisponible.")
        }
        var seen = Set<String>()
        return dictionaries(named: "musicResponsiveListItemRenderer", in: root).compactMap { row in
            guard (row["playlistItemData"] as? [String: Any])?["videoId"] == nil else { return nil }
            let columns = row["flexColumns"] as? [[String: Any]] ?? []
            let renderer = columns.first?["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any] ?? [:]
            let endpoints = dictionaries(named: "browseEndpoint", in: row["navigationEndpoint"] ?? [:])
                + dictionaries(named: "browseEndpoint", in: renderer["text"] ?? [:])
            guard let endpoint = endpoints.first(where: {
                ($0["browseId"] as? String)?.hasPrefix("UC") == true || ($0["browseId"] as? String)?.hasPrefix("MPLA") == true
            }), let id = endpoint["browseId"] as? String, seen.insert(id).inserted else { return nil }
            let name = text(renderer["text"])
            guard !name.isEmpty else { return nil }
            return MusicArtist(id: id, name: name, artworkURL: artwork(in: row))
        }
    }

    private static func text(_ value: Any?) -> String {
        guard let value = value as? [String: Any] else { return "" }
        return (value["runs"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined() ?? value["simpleText"] as? String ?? ""
    }
    private static func artwork(in value: Any) -> URL? {
        let thumbnails = dictionaries(named: "musicThumbnailRenderer", in: value)
            .flatMap { dictionaries(named: "thumbnail", in: $0) }.flatMap { $0["thumbnails"] as? [[String: Any]] ?? [] }
        let sorted = thumbnails.sorted { ($0["width"] as? Int ?? 0) > ($1["width"] as? Int ?? 0) }
        let cover = sorted.first { ($0["width"] as? Int ?? 0) <= 640 } ?? sorted.first
        guard let string = cover?["url"] as? String, let url = URL(string: string), url.scheme == "https" else { return nil }
        return url
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
