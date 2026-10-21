import Foundation
import Security

enum SecureStore {
    private static let service = "app.blusic.credentials"
    static func read(_ account: String) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: account,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func write(_ value: String, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: account]
        if value.isEmpty { SecItemDelete(query as CFDictionary); return }
        let update: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = Data(value.utf8)
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
                throw BlusicError.message("Impossible d’enregistrer la clé dans le trousseau.")
            }
        } else if status != errSecSuccess { throw BlusicError.message("Le trousseau est indisponible.") }
    }
}

struct YouTubeService {
    struct Thumbnail: Decodable { var url: URL? }
    struct Snippet: Decodable {
        var title: String
        var channelTitle: String?
        var videoOwnerChannelTitle: String?
        var thumbnails: [String: Thumbnail]?
        var resourceId: ResourceID?
    }
    struct ResourceID: Decodable { var videoId: String? }
    struct Item: Decodable { var id: ResourceID?; var snippet: Snippet }
    struct Page: Decodable { var items: [Item]; var nextPageToken: String? }

    func search(_ query: String, key: String) async throws -> [Track] {
        guard !key.isEmpty else { throw BlusicError.message("Ajoute une clé YouTube Data API dans les réglages pour rechercher le catalogue YouTube.") }
        let page: Page = try await request("search", parameters: ["part": "snippet", "q": query,
            "type": "video", "videoCategoryId": "10", "videoEmbeddable": "true", "maxResults": "25"], key: key)
        return page.items.compactMap { makeTrack($0) }
    }

    func playlist(_ url: URL, key: String) async throws -> [Track] {
        guard let host = url.host?.lowercased(), ["youtube.com", "www.youtube.com", "music.youtube.com", "m.youtube.com"].contains(host),
              let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "list" })?.value,
              !id.isEmpty else { throw BlusicError.message("Colle le lien complet d’une playlist YouTube publique contenant « list= ».") }
        guard !key.isEmpty else { throw BlusicError.message("La clé YouTube Data API est nécessaire pour importer une playlist YouTube.") }
        var result: [Track] = []
        var next: String?
        repeat {
            try Task.checkCancellation()
            var parameters = ["part": "snippet", "playlistId": id, "maxResults": "50"]
            if let next { parameters["pageToken"] = next }
            // playlistItems uses string IDs; decode only the snippet for this endpoint.
            let page: PlaylistPage = try await request("playlistItems", parameters: parameters, key: key)
            result.append(contentsOf: page.items.compactMap { makeTrack(Item(id: nil, snippet: $0.snippet)) })
            next = page.nextPageToken
            if result.count >= 2000, next != nil { throw BlusicError.message("Cette playlist dépasse la limite de 2 000 titres. Importe une sélection plus courte.") }
        } while next != nil
        return result
    }

    static func videoID(from input: String) -> String? {
        guard let url = URL(string: input), let host = url.host?.lowercased() else { return nil }
        let id: String?
        if host == "youtu.be" { id = url.pathComponents.dropFirst().first }
        else if ["youtube.com", "www.youtube.com", "music.youtube.com", "m.youtube.com"].contains(host) {
            id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value
                ?? (url.pathComponents.count > 2 && ["embed", "shorts"].contains(url.pathComponents[1]) ? url.pathComponents[2] : nil)
        } else { return nil }
        guard let id, id.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil else { return nil }
        return id
    }

    private struct PlaylistItem: Decodable { var snippet: Snippet }
    private struct PlaylistPage: Decodable { var items: [PlaylistItem]; var nextPageToken: String? }
    private func makeTrack(_ item: Item) -> Track? {
        guard let id = item.id?.videoId ?? item.snippet.resourceId?.videoId else { return nil }
        let snippet = item.snippet
        guard !["Private video", "Deleted video"].contains(snippet.title) else { return nil }
        return Track(title: snippet.title.htmlDecoded, artist: snippet.videoOwnerChannelTitle ?? snippet.channelTitle ?? "YouTube",
                     source: .youtube, location: id,
                     artworkURL: snippet.thumbnails?["high"]?.url ?? snippet.thumbnails?["medium"]?.url)
    }
    private func request<T: Decodable>(_ endpoint: String, parameters: [String: String], key: String) async throws -> T {
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/\(endpoint)")!
        components.queryItems = (parameters.merging(["key": key]) { _, new in new }).map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        // Useful for an iOS-restricted Google API key; no key is bundled with the app.
        request.setValue(Bundle.main.bundleIdentifier ?? "app.blusic.ios", forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BlusicError.message("Réponse YouTube invalide.") }
        guard (200...299).contains(http.statusCode) else {
            switch http.statusCode {
            case 400, 401: throw BlusicError.message("Clé YouTube ou lien invalide. Vérifie les réglages.")
            case 403: throw BlusicError.message("YouTube a refusé la requête : vérifie la clé, l’activation de l’API et le quota Google.")
            case 404: throw BlusicError.message("Cette playlist est introuvable ou privée.")
            default: throw BlusicError.message("YouTube est indisponible (\(http.statusCode)). Réessaie plus tard.")
            }
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

struct LyricsResult: Decodable {
    var plainLyrics: String?
    var syncedLyrics: String?
    var instrumental: Bool?
}

struct LyricsService {
    func fetch(for track: Track) async throws -> LyricsResult? {
        var url = URLComponents(string: "https://lrclib.net/api/get")!
        url.queryItems = [URLQueryItem(name: "track_name", value: track.title),
                          URLQueryItem(name: "artist_name", value: track.artist)]
        if !track.album.isEmpty { url.queryItems?.append(URLQueryItem(name: "album_name", value: track.album)) }
        if track.duration > 0 { url.queryItems?.append(URLQueryItem(name: "duration", value: String(Int(track.duration)))) }
        var request = URLRequest(url: url.url!)
        request.timeoutInterval = 15
        request.setValue("Blusic/1.0 (iOS personal music player)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BlusicError.message("Service de paroles indisponible.") }
        if http.statusCode == 404 { return nil }
        guard (200...299).contains(http.statusCode) else { throw BlusicError.message("Les paroles sont momentanément indisponibles.") }
        return try JSONDecoder().decode(LyricsResult.self, from: data)
    }
}

enum PlaylistImporter {
    struct Result {
        var name: String
        var tracks: [Track]
    }

    static func parse(_ data: Data, filename: String) throws -> Result {
        guard data.count <= 10_000_000 else { throw BlusicError.message("Le fichier d’import est limité à 10 Mo.") }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            throw BlusicError.message("Enregistre le fichier en UTF-8 ou UTF-16.")
        }
        let name = (filename as NSString).deletingPathExtension
        if ["m3u", "m3u8"].contains((filename as NSString).pathExtension.lowercased()) {
            return Result(name: name, tracks: try parseM3U(text))
        }
        return Result(name: name, tracks: try parseCSV(text))
    }

    /// RFC 4180: escaped quotes, quoted delimiters, multiline fields and CRLF.
    static func csvRows(_ text: String, delimiter: Character) throws -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        let chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if quoted, i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 }
                else { quoted.toggle() }
            } else if c == delimiter && !quoted { row.append(field); field = "" }
            else if c == "\n" && !quoted { row.append(field); rows.append(row); row = []; field = "" }
            else { field.append(c) }
            i += 1
        }
        guard !quoted else { throw BlusicError.message("CSV invalide : un champ entre guillemets n’est pas terminé.") }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows.filter { $0.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    }
    static func parseCSV(_ input: String) throws -> [Track] {
        let text = input.replacingOccurrences(of: "\u{FEFF}", with: "")
        let headerLine = text.components(separatedBy: .newlines).first ?? ""
        let delimiter: Character = [Character(","), ";", "\t"].max { a, b in
            headerLine.filter { $0 == a }.count < headerLine.filter { $0 == b }.count
        } ?? ","
        let rows = try csvRows(text, delimiter: delimiter)
        guard let header = rows.first else { throw BlusicError.message("Le fichier CSV est vide.") }
        let columns = header.map { normalize($0) }
        func column(_ aliases: [String]) -> Int? { columns.firstIndex { aliases.contains($0) } }
        guard let titleIndex = column(["title", "trackname", "track", "name", "song", "titre", "tracktitle"]) else {
            throw BlusicError.message("Colonne de titre introuvable. Utilise un export CSV Soundiiz/TuneMyMusic ou les colonnes title, artist, album, url.")
        }
        let artistIndex = column(["artist", "artists", "artistname", "artistnames", "artiste", "author"])
        let albumIndex = column(["album", "albumname", "albumtitle"])
        let urlIndex = column(["url", "trackurl", "link", "tracklink", "uri", "trackuri"])
        var tracks: [Track] = []
        for row in rows.dropFirst() {
            func value(_ index: Int?) -> String { index.flatMap { row.indices.contains($0) ? row[$0].trimmingCharacters(in: .whitespacesAndNewlines) : nil } ?? "" }
            let title = value(titleIndex)
            guard !title.isEmpty else { continue }
            let link = value(urlIndex)
            let id = YouTubeService.videoID(from: link)
            let audioURL = URL(string: link)
            let remote = audioURL?.scheme == "https" && ["mp3", "m4a", "flac", "wav", "aac", "aiff"].contains(audioURL?.pathExtension.lowercased() ?? "")
            tracks.append(Track(title: title, artist: value(artistIndex), album: value(albumIndex),
                                source: id != nil ? .youtube : remote ? .remote : .unresolved, location: id ?? (remote ? link : "")))
        }
        guard !tracks.isEmpty else { throw BlusicError.message("Aucun titre trouvé dans cet export.") }
        return tracks
    }
    static func parseM3U(_ text: String) throws -> [Track] {
        var result: [Track] = [], title = "", duration = 0.0
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#EXTINF:"), let comma = line.firstIndex(of: ",") {
                duration = Double(line[line.index(line.startIndex, offsetBy: 8)..<comma]) ?? 0
                title = String(line[line.index(after: comma)...]); continue
            }
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let parts = title.components(separatedBy: " - ")
            let id = YouTubeService.videoID(from: line)
            let remote = URL(string: line)?.scheme == "https"
            result.append(Track(title: title.isEmpty ? (line as NSString).lastPathComponent : parts.count > 1 ? parts.dropFirst().joined(separator: " - ") : title,
                                artist: parts.count > 1 ? parts[0] : "", duration: max(0, duration),
                                source: id != nil ? .youtube : remote ? .remote : .unresolved, location: id ?? (remote ? line : "")))
            title = ""; duration = 0
        }
        guard !result.isEmpty else { throw BlusicError.message("La playlist M3U est vide.") }
        return result
    }
    static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR")).filter { $0.isLetter || $0.isNumber }
    }
}

private extension String {
    var htmlDecoded: String {
        replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#39;", with: "’")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
