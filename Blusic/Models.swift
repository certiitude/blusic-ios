import Foundation
import SwiftUI

enum AudioSource: String, Codable, CaseIterable, Sendable {
    case bundled, local, remote, youtube, invidious, catalogReference, unresolved
}

struct Track: Identifiable, Codable, Equatable, Hashable, Sendable {
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
    /// Discovery origin only. Expiring audio URLs are never saved in the library.
    var originInstance: URL?
    var musicCatalog: String?
    var artistID: String?

    var isNative: Bool { [.bundled, .local, .remote, .invidious].contains(source) }
    var isYouTubeContent: Bool { source == .youtube || source == .invidious }
    var isOffline: Bool { [.bundled, .local].contains(source) }
    var subtitle: String { artist.isEmpty ? "Artiste inconnu" : artist }
    var sourceLabel: String {
        switch source {
        case .bundled: return "Original Blusic"
        case .local: return "Sur cet iPhone"
        case .remote: return "Source HTTPS"
        case .youtube: return "YouTube"
        case .invidious: return musicCatalog == "youtube-music" ? "YouTube Music · audio en ligne" : "YouTube · audio en ligne"
        case .catalogReference: return "À associer à YouTube Music"
        case .unresolved: return "Source à associer"
        }
    }
}

struct Playlist: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var detail: String = "Ta sélection, ton univers."
    var trackIDs: [UUID] = []
    var createdAt = Date()
    var symbol = "music.note.list"
}

struct MusicArtist: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String
    var name: String
    var artworkURL: URL?
}

struct ArtistProfile {
    var artist: MusicArtist
    var biography: String
    var tracks: [Track]
}

enum PlaybackDuration {
    /// Public catalogue duration bounds unreliable AAC/container estimates.
    static func effective(declared: Double, measured: Double) -> Double {
        let known = declared.isFinite && declared > 0
        let valid = measured.isFinite && measured > 0
        guard known else { return valid ? measured : 0 }
        guard valid, abs(measured - declared) <= max(2, declared * 0.02) else { return declared }
        return measured
    }
}

enum QueuePreparationPolicy {
    static let leadSeconds = 45.0
    static func shouldStart(duration: Double, position: Double, rate: Float) -> Bool {
        guard duration.isFinite, position.isFinite, duration > 0, position >= 0, position < duration, rate.isFinite, rate > 0 else { return false }
        return (duration - position) / Double(rate) <= leadSeconds
    }
}

enum OnlineAudioQuality: String, Sendable {
    case standard, high
    /// YouTube's nominal 128 kbit/s AAC may advertise a slightly higher peak.
    static let standardBitrateCeiling = 160_000
    func preferred<T>(_ formats: [T], bitrate: (T) -> Int) -> [T] {
        let ranked = formats.sorted { bitrate($0) > bitrate($1) }
        guard self == .standard else { return ranked }
        let standard = ranked.filter { bitrate($0) <= Self.standardBitrateCeiling }
        return standard.isEmpty ? ranked : standard
    }
    func metadataKey(videoID: String) -> String {
        "invidious:\(videoID):aac" + (self == .high ? ":high" : "")
    }
    func fileKey(videoID: String, bitrate: Int) -> String { "\(metadataKey(videoID: videoID)):\(bitrate)" }
}

struct ListeningEvent: Identifiable, Codable, Sendable {
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

struct AppSettings: Codable, Equatable, Sendable {
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
    // Optional fields keep v1.0 Codable snapshots readable without resetting the library.
    var invidiousInstance: String?
    var invidiousAutomaticFallback: Bool?
    var linkSpeedAndPitch: Bool?
    var crossfadeEnabled: Bool?
    var crossfadeDuration: Double?
    var onlineAudioMode: String?
    var youtubeiRelayAddress: String?
    var youtubeiRelayDisabled: Bool?
    var highQualityAudio: Bool?

    var audioQuality: OnlineAudioQuality { highQualityAudio == true ? .high : .standard }
    var audioSourceMode: String {
        guard let mode = onlineAudioMode, ["auto", "direct", "invidious", "youtubei"].contains(mode) else { return "auto" }
        return mode
    }
    var usesInvidiousFallback: Bool { invidiousAutomaticFallback ?? true }
    var invidiousAddress: String { invidiousInstance ?? InvidiousService.defaultInstance }
    var usesLinkedSpeedAndPitch: Bool { linkSpeedAndPitch ?? true }
    var usesCrossfade: Bool { crossfadeEnabled ?? false }
    var crossfadeSeconds: Double { min(8, max(0.5, crossfadeDuration ?? 3)) }
    var effectiveSemitones: Float { usesLinkedSpeedAndPitch ? Self.semitones(for: playbackRate) : pitch }
    var needsPreparedEffects: Bool { equalizerEnabled || (!usesLinkedSpeedAndPitch && abs(pitch) > 0.001) }
    static func rate(for semitones: Float) -> Float { Float(pow(2, Double(min(12, max(-12, semitones))) / 12)) }
    static func semitones(for rate: Float) -> Float { Float(12 * log2(Double(min(2, max(0.5, rate))))) }
    mutating func setPlaybackRate(_ rate: Float) {
        playbackRate = min(2, max(0.5, rate))
        if usesLinkedSpeedAndPitch { pitch = Self.semitones(for: playbackRate) }
    }
    mutating func setSemitones(_ semitones: Float) {
        pitch = min(12, max(-12, semitones))
        if usesLinkedSpeedAndPitch { playbackRate = Self.rate(for: pitch) }
    }
    mutating func setSpeedPitchLinked(_ linked: Bool) {
        let oldSemitones = effectiveSemitones
        linkSpeedAndPitch = linked
        pitch = linked ? Self.semitones(for: playbackRate) : oldSemitones
    }

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

struct LibrarySnapshot: Codable, Sendable {
    var version = 1
    var tracks: [Track]
    var playlists: [Playlist]
    var favorites: Set<UUID>
    var history: [ListeningEvent]
    var settings: AppSettings
    var queue: [UUID]
    var currentTrackID: UUID?
    var followedArtists: [MusicArtist]?
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
