import Foundation
import SwiftUI

enum AudioSource: String, Codable, CaseIterable {
    case bundled, local, remote, youtube, unresolved
}

struct Track: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var title: String
    var artist: String
    var album: String = ""
    var duration: Double = 0
    var source: AudioSource
    /// Bundle filename, sandbox-relative filename, HTTPS URL or YouTube video ID.
    var location: String
    var artwork: String = "cover-night"
    var artworkURL: URL?
    var addedAt: Date = Date()
    var lyrics: String?
    var isExplicit: Bool = false

    var isNative: Bool { [.bundled, .local, .remote].contains(source) }
    var isOffline: Bool { [.bundled, .local].contains(source) }
    var subtitle: String { artist.isEmpty ? "Artiste inconnu" : artist }
    var sourceLabel: String {
        switch source {
        case .bundled: return "Original Blusic"
        case .local: return "Sur cet iPhone"
        case .remote: return "Source HTTPS"
        case .youtube: return "YouTube"
        case .unresolved: return "Source à associer"
        }
    }
}

struct Playlist: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var detail: String = "Ta sélection, ton univers."
    var trackIDs: [UUID] = []
    var createdAt = Date()
    var symbol = "music.note.list"
}

struct ListeningEvent: Identifiable, Codable {
    var id = UUID()
    var trackID: UUID
    var date: Date
    var seconds: Double
}

enum RepeatMode: String, Codable, CaseIterable {
    case off, all, one
    var icon: String { self == .one ? "repeat.1" : "repeat" }
    mutating func cycle() { self = Self.allCases[(Self.allCases.firstIndex(of: self)! + 1) % 3] }
}

struct AppSettings: Codable, Equatable {
    var accent = "blue"
    var appearance = "dark"
    var haptics = true
    var animateArtwork = true
    var compactRows = false
    var artworkRadius = 18.0
    var playbackRate: Float = 1
    var pitch: Float = 0
    var equalizer: [Float] = Array(repeating: 0, count: 10)
    var equalizerEnabled = false
    var lyricsOffset = 0.0
    var volume: Float = 0.8
    var restoreQueue = true

    var color: Color {
        switch accent {
        case "violet": return Color(red: 0.64, green: 0.48, blue: 1)
        case "rose": return Color(red: 1, green: 0.35, blue: 0.54)
        case "mint": return Color(red: 0.22, green: 0.81, blue: 0.67)
        case "orange": return Color(red: 1, green: 0.62, blue: 0.28)
        case "white": return .primary
        default: return Color(red: 0.32, green: 0.62, blue: 1)
        }
    }
}

struct LibrarySnapshot: Codable {
    var version = 1
    var tracks: [Track]
    var playlists: [Playlist]
    var favorites: Set<UUID>
    var history: [ListeningEvent]
    var settings: AppSettings
    var queue: [UUID]
    var currentTrackID: UUID?
}

struct LyricLine: Identifiable, Equatable {
    var id: Int
    var time: Double
    var text: String
}

enum LRCParser {
    static func parse(_ input: String) -> [LyricLine] {
        let regex = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#)
        var result: [(Double, String)] = []
        var offset = 0.0
        for line in input.components(separatedBy: .newlines) {
            if line.hasPrefix("[offset:"), let end = line.firstIndex(of: "]"),
               let ms = Double(line[line.index(line.startIndex, offsetBy: 8)..<end]) { offset = ms / 1000 }
        }
        for line in input.components(separatedBy: .newlines) {
            let ns = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: NSMaxRange(last.range)).trimmingCharacters(in: .whitespaces)
            for match in matches {
                let minutes = Double(ns.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(ns.substring(with: match.range(at: 2))) ?? 0
                let fraction: Double
                if match.range(at: 3).location != NSNotFound {
                    fraction = Double("0." + ns.substring(with: match.range(at: 3))) ?? 0
                } else { fraction = 0 }
                result.append((max(0, minutes * 60 + seconds + fraction + offset), text))
            }
        }
        return result.sorted { $0.0 < $1.0 }.enumerated().map {
            LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1)
        }
    }
}

extension Double {
    var clock: String {
        guard isFinite else { return "0:00" }
        let value = max(0, Int(self))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

enum BlusicError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}
