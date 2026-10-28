import XCTest
import AVFoundation
import SwiftUI
import CryptoKit
@testable import Blusic

final class BlusicTests: XCTestCase {
    @MainActor func testSorynPairingRejectsPublicAddressesAndInvalidKeys() throws {
        let key = Data(repeating: 0, count: 32).base64EncodedString().replacingOccurrences(of: "=", with: "")
        let valid = "soryn://pair?address=http%3A%2F%2F192.168.1.20%3A48763&key=\(key)"
        XCTAssertEqual(try SorynSyncClient.pairing(valid).0, "http://192.168.1.20:48763")
        XCTAssertEqual(try SorynSyncClient.pairing(valid).1.count, 32)
        for address in ["http://8.8.8.8:48763", "http://192.168.1.20:80", "https://192.168.1.20:48763", "http://192.168.1.20:48763/path", "http://user@192.168.1.20:48763", "http://example.com:48763"] {
            let escaped = address.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
            XCTAssertThrowsError(try SorynSyncClient.pairing("soryn://pair?address=\(escaped)&key=\(key)"))
        }
        XCTAssertThrowsError(try SorynSyncClient.pairing("soryn://pair?address=http%3A%2F%2F192.168.1.20%3A48763&key=short"))
    }

    func testSorynAuthenticatedEncryptionRejectsTamperingAndWrongKey() throws {
        let key = SymmetricKey(data: Data(repeating: 4, count: 32))
        let box = try SorynSyncBox.seal(["title": "Écoutez le moment."], key: key)
        XCTAssertEqual(try box.open([String: String].self, key: key)["title"], "Écoutez le moment.")
        XCTAssertThrowsError(try box.open([String: String].self, key: SymmetricKey(data: Data(repeating: 5, count: 32))))
        var bytes = Data(base64Encoded: box.box)!; bytes[15] ^= 1
        XCTAssertThrowsError(try SorynSyncBox(box: bytes.base64EncodedString()).open([String: String].self, key: key))
    }

    @MainActor func testSorynMergePreservesPersonalFilesSettingsAndConcurrentEdits() throws {
        let library = LibraryStore(inMemory: true)
        let local = Track(title: "Personnel", artist: "Moi", duration: 48, source: .local, location: "personal.wav")
        library.tracks.append(local); library.favorites.insert(local.id)
        library.settings.playbackRate = 1.5
        let sent = SorynSharedLibrary(library)
        XCTAssertEqual(sent.tracks.first(where: { $0.id == local.id })?.source, .unresolved)
        XCTAssertEqual(sent.tracks.first(where: { $0.id == local.id })?.location, "")
        var reply = sent
        reply.favorites.remove(local.id)
        reply.playlists[0].name = "Renommée sur PC"
        let added = Track(title: "Ajout pendant la requête", artist: "Moi", duration: 48, source: .bundled, location: "bleu-nuit.wav")
        library.tracks.append(added); library.favorites.insert(added.id)
        reply.apply(to: library, sent: sent)
        XCTAssertEqual(library.track(local.id)?.source, .local)
        XCTAssertEqual(library.track(local.id)?.location, "personal.wav")
        XCTAssertEqual(library.settings.playbackRate, 1.5)
        XCTAssertFalse(library.favorites.contains(local.id))
        XCTAssertTrue(library.favorites.contains(added.id))
        XCTAssertEqual(library.playlists[0].name, "Renommée sur PC")
    }

    @MainActor func testSorynEncryptedWindowsProtocolAgainstNodeServer() async throws {
        let library = LibraryStore(inMemory: true)
        let snapshot = SorynSharedLibrary(library), key = SymmetricKey(data: Data(repeating: 0, count: 32))
        let device = UUID().uuidString, requestID = UUID().uuidString
        struct Packet: Encodable {
            var `protocol` = 1; var deviceID: String; var requestID: String; var sentAt: Double; var snapshot: SorynSharedLibrary
        }
        struct Reply: Decodable { var `protocol`: Int; var requestID: String; var snapshot: SorynSharedLibrary }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:48764/v1/sync")!)
        request.httpMethod = "POST"; request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SorynSyncBox.seal(Packet(deviceID: device, requestID: requestID, sentAt: Date().timeIntervalSince1970 * 1000, snapshot: snapshot), key: key))
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let reply = try JSONDecoder().decode(SorynSyncBox.self, from: data).open(Reply.self, key: key)
        XCTAssertEqual(reply.requestID, requestID)
        try reply.snapshot.validate()
        XCTAssertEqual(reply.snapshot.tracks.count, 4, "The independently seeded Node and Swift originals must deduplicate")
        reply.snapshot.apply(to: library, sent: snapshot)
        XCTAssertEqual(library.tracks.count, 4)
        let (_, replay) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((replay as? HTTPURLResponse)?.statusCode, 409, "Authenticated requests must not be replayable")
    }

    func testLRCMultipleTagsFractionsAndOffset() {
        let input = "[ar:Artist]\n[offset:-500]\n[00:01.25][00:05.250]Premier vers\n[01:02.5]Deuxième vers"
        let result = LRCParser.parse(input)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.map(\.time), [0.75, 4.75, 62])
        XCTAssertEqual(result.map(\.text), ["Premier vers", "Premier vers", "Deuxième vers"])
    }

    func testPlainTextDoesNotInventSyncedLyrics() {
        XCTAssertTrue(LRCParser.parse("Paroles sans horodatage").isEmpty)
        XCTAssertEqual((-10.0).clock, "0:00")
        XCTAssertEqual(Double.nan.clock, "0:00")
        XCTAssertEqual(149.0.clock, "2:29")
    }

    func testCSVQuotedFieldsMultilineAndCRLF() throws {
        let csv = "title,artist,album,url\r\n\"L’été, la nuit\",\"Un \"\"artiste\"\"\",\"Deux\nLignes\",\r\n"
        let result = try PlaylistImporter.parseCSV(csv)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "L’été, la nuit")
        XCTAssertEqual(result[0].artist, "Un \"artiste\"")
        XCTAssertEqual(result[0].album, "Deux\nLignes")
        XCTAssertEqual(result[0].source, .unresolved)
    }

    func testSpotifySoundiizAndSemicolonImports() throws {
        let spotify = "Track Name,Artist Name(s),Album Name,Track URI\nTest,Artist,Album,spotify:track:abc"
        XCTAssertEqual(try PlaylistImporter.parseCSV(spotify).first?.source, .unresolved)
        let french = "\u{FEFF}Titre;Artiste;Album;URL\nPanam;Lushe;Singles;https://www.youtube.com/watch?v=abcdefghijk"
        let tracks = try PlaylistImporter.parseCSV(french)
        XCTAssertEqual(tracks.first?.title, "Panam")
        XCTAssertEqual(tracks.first?.source, .invidious)
        XCTAssertEqual(tracks.first?.location, "abcdefghijk")
    }

    func testCSVRejectsMalformedInput() {
        XCTAssertThrowsError(try PlaylistImporter.parseCSV("title,artist\n\"not closed,artist"))
        XCTAssertThrowsError(try PlaylistImporter.parseCSV("noheader,invalid\nfoo,bar"))
        XCTAssertThrowsError(try PlaylistImporter.parseCSV("title,artist\n,,"))
    }

    func testM3UHandlesReferencesWithoutAssumingFilesExist() throws {
        let text = "#EXTM3U\n#EXTINF:149,Artiste - Titre\n../song.mp3\n#EXTINF:48,Artiste - Direct\nhttps://example.org/song.flac"
        let result = try PlaylistImporter.parseM3U(text)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].source, .unresolved)
        XCTAssertEqual(result[0].title, "Titre")
        XCTAssertEqual(result[0].duration, 149)
        XCTAssertEqual(result[1].source, .remote)
    }

    func testYouTubeIDValidation() {
        XCTAssertEqual(YouTubeService.videoID(from: "https://music.youtube.com/watch?v=abcdefghijk&list=abc"), "abcdefghijk")
        XCTAssertEqual(YouTubeService.videoID(from: "https://youtu.be/abcdefghijk?t=15"), "abcdefghijk")
        XCTAssertEqual(YouTubeService.videoID(from: "https://www.youtube.com/shorts/abcdefghijk"), "abcdefghijk")
        XCTAssertNil(YouTubeService.videoID(from: "https://notyoutube.com/watch?v=abcdefghijk"))
        XCTAssertNil(YouTubeService.videoID(from: "https://youtube.com/watch?v=bad<script>"))
    }

    func testLibrarySnapshotRoundTripKeepsIdentityAndOrder() throws {
        let track = Track(title: "Test", artist: "Artiste", source: .unresolved, location: "")
        let playlist = Playlist(name: "Ma playlist", trackIDs: [track.id])
        let snapshot = LibrarySnapshot(tracks: [track], playlists: [playlist], favorites: [track.id], history: [], settings: AppSettings(), queue: [track.id], currentTrackID: track.id)
        let decoded = try JSONDecoder().decode(LibrarySnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.playlists[0].trackIDs, [track.id])
        XCTAssertEqual(decoded.queue, [track.id])
        XCTAssertTrue(decoded.favorites.contains(track.id))
    }

    func testBundledTracksAreRealDecodableAudio() throws {
        let bundle = Bundle(for: AudioPlayer.self)
        for name in ["bleu-nuit", "apres-la-pluie", "orbite", "dernier-metro"] {
            let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "wav"))
            let file = try AVAudioFile(forReading: url)
            XCTAssertEqual(file.processingFormat.channelCount, 2)
            XCTAssertEqual(Double(file.length) / file.processingFormat.sampleRate, 48, accuracy: 0.01)
        }
    }

    func testRepeatCycle() {
        var mode = RepeatMode.off
        mode.cycle(); XCTAssertEqual(mode, .all)
        mode.cycle(); XCTAssertEqual(mode, .one)
        mode.cycle(); XCTAssertEqual(mode, .off)
    }

    func testLegacySettingsStillDecodeWithInvidiousDefaults() throws {
        var original = AppSettings()
        original.accent = "mint"
        original.playbackRate = 1.25
        let data = try JSONEncoder().encode(original)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["invidiousInstance"])
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.accent, "mint")
        XCTAssertEqual(decoded.playbackRate, 1.25)
        XCTAssertEqual(decoded.invidiousAddress, InvidiousService.defaultInstance)
        XCTAssertTrue(decoded.usesInvidiousFallback)
        XCTAssertEqual(decoded.audioQuality, .standard)
    }

    func testHighQualitySettingPersistsAndSelectsOnlyRealCompatibleAAC() throws {
        var settings = AppSettings(); settings.highQualityAudio = true
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)).audioQuality, .high)
        let track = Track(title: "Quality fixture", artist: "Test", source: .invidious, location: "abcdefghijk")
        let data = Data(#"{"playabilityStatus":{"status":"OK"},"streamingData":{"adaptiveFormats":[{"url":"https://media.googlevideo.com/normal","mimeType":"audio/mp4; codecs=mp4a.40.2","bitrate":131000},{"url":"https://media.googlevideo.com/high","mimeType":"audio/mp4; codecs=mp4a.40.2","bitrate":256000},{"url":"https://media.googlevideo.com/opus","mimeType":"audio/webm; codecs=opus","bitrate":300000}]}}"#.utf8)
        let standard = try DirectAudioService.parse(data, track: track)
        let high = try DirectAudioService.parse(data, track: track, quality: .high)
        XCTAssertEqual(standard.url.path, "/normal"); XCTAssertEqual(standard.bitrate, 131000)
        XCTAssertEqual(high.url.path, "/high"); XCTAssertEqual(high.bitrate, 256000); XCTAssertEqual(high.quality, .high)
        XCTAssertEqual(OnlineAudioQuality.high.preferred([131000], bitrate: { $0 }), [131000], "High quality must not invent a higher rate when none is offered")
    }

    func testHighQualityNeverReusesAStandardResolvedURL() async throws {
        let session = stubSession()
        defer { session.invalidateAndCancel(); InvidiousStubProtocol.handler = nil }
        let calls = NetworkRequestCounter()
        InvidiousStubProtocol.handler = { request in
            if request.url?.path == "/youtubei/v1/player" {
                calls.increment()
                return (200, Data(#"{"playabilityStatus":{"status":"OK"},"streamingData":{"adaptiveFormats":[{"url":"https://media.googlevideo.com/normal","mimeType":"audio/mp4; codecs=mp4a.40.2","bitrate":131000},{"url":"https://media.googlevideo.com/high","mimeType":"audio/mp4; codecs=mp4a.40.2","bitrate":256000}]}}"#.utf8))
            }
            return (206, Data([0,0,0,20]) + Data("ftypM4A ".utf8) + Data(repeating: 0, count: 64))
        }
        let cache = InvidiousStreamCache(resolver: OnlineStreamResolver(session: session))
        var settings = AppSettings(); settings.onlineAudioMode = "direct"
        let track = Track(title: "Variant cache fixture", artist: "Test", source: .invidious, location: "abcdefghijk")
        let standard = try await cache.resolve(track, settings: settings, direct: false)
        settings.highQualityAudio = true
        let high = try await cache.resolve(track, settings: settings, direct: false)
        let cached = try await cache.resolve(track, settings: settings, direct: false)
        XCTAssertEqual(standard.bitrate, 131000); XCTAssertEqual(high.bitrate, 256000); XCTAssertEqual(cached.url, high.url)
        XCTAssertEqual(calls.count, 2, "Changing quality must resolve a fresh variant once, then cache it")
    }

    func testHighQualityFileCacheDoesNotUseTheOldStandardDownload() async throws {
        let cache = AudioCache()
        let fixture = try XCTUnwrap(Bundle(for: AudioPlayer.self).url(forResource: "orbite", withExtension: "wav"))
        let id = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(11))
        let track = Track(title: "File quality fixture", artist: "Test", duration: 48, source: .invidious, location: id)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("quality-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.copyItem(at: fixture, to: temp)
        let source = URL(string: "https://www.youtube.com")!
        let standard = try await cache.adoptNativeYouTubei(InvidiousAudio(fileURL: temp, bitrate: 131000, instance: source, duration: 48), track: track)
        defer { try? FileManager.default.removeItem(at: standard.fileURL) }
        let missingHigh = await cache.cachedInvidious(track: track, quality: .high)
        XCTAssertNil(missingHigh, "An existing standard download must not hide a fresh best-format lookup")
        try FileManager.default.copyItem(at: fixture, to: temp)
        let high = try await cache.adoptNativeYouTubei(InvidiousAudio(fileURL: temp, bitrate: 256000, instance: source, duration: 48, quality: .high), track: track)
        defer { try? FileManager.default.removeItem(at: high.fileURL) }
        let cachedHigh = await cache.cachedInvidious(track: track, quality: .high)
        let cachedStandard = await cache.cachedInvidious(track: track)
        XCTAssertEqual(cachedHigh?.bitrate, 256000); XCTAssertEqual(cachedStandard?.bitrate, 131000)
        XCTAssertNotEqual(cachedHigh?.fileURL, cachedStandard?.fileURL)
    }

    func testInvidiousAddressValidation() throws {
        XCTAssertEqual(try InvidiousService.instanceURL(" https://example.org/ ").host, "example.org")
        for invalid in ["http://example.org", "", "https://user:password@example.org", "https://example.org?key=value", "https://example.org/#fragment"] {
            XCTAssertThrowsError(try InvidiousService.instanceURL(invalid))
        }
        XCTAssertFalse(InvidiousService.isVideoID("../bad/path"))
        XCTAssertTrue(InvidiousService.isVideoID("KVpeHSX2ZEY"))
    }

    func testInvidiousKeepsStableIDAndResolvesRelativeArtwork() throws {
        let json = #"{"type":"video","videoId":"abcdefghijk","title":"Un titre","author":"Artiste","lengthSeconds":171,"videoThumbnails":[{"url":"/vi/abcdefghijk/hqdefault.jpg","width":480}]}"#
        let video = try JSONDecoder().decode(InvidiousVideo.self, from: Data(json.utf8))
        let track = try XCTUnwrap(video.track(on: URL(string: "https://example.org")!))
        XCTAssertEqual(track.source, .invidious)
        XCTAssertEqual(track.location, "abcdefghijk")
        XCTAssertEqual(track.artworkURL?.absoluteString, "https://example.org/vi/abcdefghijk/hqdefault.jpg")
        XCTAssertEqual(track.duration, 171)
        XCTAssertTrue(track.isNative)
        XCTAssertFalse(track.isOffline)
    }

    func testInvidiousSelectsBestAACWithoutClaimingOpusSupport() throws {
        let json = #"{"adaptiveFormats":[{"url":"/opus","type":"audio/webm; codecs=opus","bitrate":"190000"},{"url":"/small","type":"audio/mp4; codecs=mp4a.40.2","bitrate":"128000","audioSampleRate":"44100"},{"url":"/best","type":"audio/mp4; codecs=mp4a.40.2","bitrate":256000,"audioSampleRate":48000},{"url":"/video","type":"video/mp4; codecs=avc1","bitrate":1000000}]}"#
        let result = try JSONDecoder().decode(InvidiousDetails.self, from: Data(json.utf8))
        XCTAssertEqual(result.compatibleFormats.map(\.bitrate), [256000, 128000])
        XCTAssertEqual(result.compatibleFormats.first?.sampleRate, 48000)
    }

    func testIncompleteInvidiousFormatDoesNotHideValidAAC() throws {
        let data = Data(#"{"adaptiveFormats":[{"bitrate":250000},{"url":"/good","type":"audio/mp4; codecs=mp4a.40.2","bitrate":"131055"}]}"#.utf8)
        let details = try JSONDecoder().decode(InvidiousDetails.self, from: data)
        XCTAssertEqual(details.compatibleFormats.map(\.url), ["/good"])
    }

    func testDirectAudioRejectsEncryptedDRMAndNonGoogleMedia() throws {
        let track = Track(title: "Fixture", artist: "Test", source: .invidious, location: "abcdefghijk")
        let invalid = Data(#"{"playabilityStatus":{"status":"OK"},"streamingData":{"adaptiveFormats":[{"mimeType":"audio/mp4; codecs=mp4a.40.2","signatureCipher":"encrypted"},{"mimeType":"audio/mp4; codecs=mp4a.40.2","url":"https://media.googlevideo.com/a","drmFamilies":["WIDEVINE"]},{"mimeType":"audio/mp4; codecs=mp4a.40.2","url":"https://googlevideo.com.evil.invalid/a"}]}}"#.utf8)
        XCTAssertThrowsError(try DirectAudioService.parse(invalid, track: track))
        let restricted = Data(#"{"playabilityStatus":{"status":"LOGIN_REQUIRED","reason":"Sign in required"}}"#.utf8)
        XCTAssertThrowsError(try DirectAudioService.parse(restricted, track: track)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Sign in required"))
        }
    }

    func testAutomaticAudioSkipsDirectURLThatRefusesMediaAndUsesRelay() async throws {
        let session = stubSession()
        defer { session.invalidateAndCancel(); InvidiousStubProtocol.handler = nil }
        InvidiousStubProtocol.handler = { request in
            switch request.url?.path {
            case "/youtubei/v1/player":
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                return (200, Data(#"{"playabilityStatus":{"status":"OK"},"videoDetails":{"lengthSeconds":"171"},"streamingData":{"adaptiveFormats":[{"url":"https://media.googlevideo.com/refused","mimeType":"audio/mp4; codecs=mp4a.40.2","bitrate":131055}]}}"#.utf8))
            case "/refused": return (403, Data())
            case "/api/v1/videos/abcdefghijk":
                return (200, Data(#"{"lengthSeconds":171,"adaptiveFormats":[{"url":"/media.m4a","type":"audio/mp4; codecs=mp4a.40.2","bitrate":131055}]}"#.utf8))
            case "/media.m4a":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=0-4095")
                return (206, Data([0, 0, 0, 20]) + Data("ftypM4A ".utf8) + Data(repeating: 0, count: 64))
            default: XCTFail("Unexpected source request"); return (404, Data())
            }
        }
        var settings = AppSettings(); settings.invidiousInstance = "https://fixture.invalid"; settings.invidiousAutomaticFallback = false
        let track = Track(title: "Fixture", artist: "Test", source: .invidious, location: "abcdefghijk")
        let stream = try await OnlineStreamResolver(session: session).resolve(track, settings: settings)
        XCTAssertFalse(stream.isYouTubeDirect)
        XCTAssertEqual(stream.url.absoluteString, "https://fixture.invalid/media.m4a")
    }

    func testDirectModeNeverContactsInvidiousAndValidatesMP4Bytes() async throws {
        let session = stubSession()
        defer { session.invalidateAndCancel(); InvidiousStubProtocol.handler = nil }
        InvidiousStubProtocol.handler = { request in
            if request.url?.host == "www.youtube.com" {
                return (200, Data(#"{"playabilityStatus":{"status":"OK"},"streamingData":{"adaptiveFormats":[{"url":"https://media.googlevideo.com/audio","mimeType":"audio/mp4; codecs=mp4a.40.2","bitrate":131055}]}}"#.utf8))
            }
            XCTAssertEqual(request.url?.host, "media.googlevideo.com")
            return (206, Data([0, 0, 0, 20]) + Data("ftypM4A ".utf8) + Data(repeating: 0, count: 64))
        }
        var settings = AppSettings(); settings.onlineAudioMode = "direct"
        let track = Track(title: "Fixture", artist: "Test", source: .invidious, location: "abcdefghijk")
        let stream = try await OnlineStreamResolver(session: session).resolve(track, settings: settings)
        XCTAssertTrue(stream.isYouTubeDirect)
        XCTAssertEqual(stream.bitrate, 131055)
    }

    @MainActor
    func testLiveDamsoPreviouslyFailingTitleStartsAndSeeksUsingDirectAudio() async throws {
        let track = Track(title: "Dieu ne ment jamais", artist: "Damso", source: .invidious, location: "-WXpT4Ej2No", musicCatalog: "youtube-music")
        let store = LibraryStore(inMemory: true)
        store.settings.onlineAudioMode = "direct"; store.settings.volume = 0.1
        let player = AudioPlayer(library: store)
        defer { player.forget(track.id) }
        player.play(track, in: [track])
        for _ in 0..<160 {
            if player.firstAudioLatency != nil || player.error != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertNil(player.error)
        XCTAssertTrue(player.isStreaming)
        XCTAssertTrue(player.isPlaying)
        let latency = try XCTUnwrap(player.firstAudioLatency)
        XCTAssertLessThan(latency, 8)
        XCTAssertTrue(player.formatLabel.contains("YouTube direct"))
        XCTAssertGreaterThan(player.duration, 60)
        player.seek(to: 30)
        try await Task.sleep(for: .seconds(1))
        XCTAssertGreaterThanOrEqual(player.position, 29)
        print("DAMSO DIRECT PLAYBACK: first-audio=\(latency)s, duration=\(player.duration)s, format=\(player.formatLabel), seek=\(player.position)s")
    }

    func testInvidiousSearchUsesNativeSourceAndPaginationWithoutKey() async throws {
        let session = stubSession()
        defer { session.invalidateAndCancel(); InvidiousStubProtocol.handler = nil }
        InvidiousStubProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/search")
            let params = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertEqual(params.first { $0.name == "page" }?.value, "2")
            XCTAssertNil(params.first { $0.name == "key" })
            return (200, Data(#"[{"type":"video","videoId":"abcdefghijk","title":"Test","author":"Artist","lengthSeconds":170},{"type":"channel","title":"Channel"},{"type":"video","videoId":"aaaaaaaaaaa","title":"Live","liveNow":true}]"#.utf8))
        }
        let service = try InvidiousService(address: "https://fixture.invalid", automaticFallback: false, session: session)
        let tracks = try await service.search("test", page: 2)
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks.first?.source, .invidious)
    }

    func testInvidiousReportsBlockedAPI() async throws {
        let session = stubSession()
        defer { session.invalidateAndCancel(); InvidiousStubProtocol.handler = nil }
        InvidiousStubProtocol.handler = { _ in (401, Data()) }
        let service = try InvidiousService(address: "https://fixture.invalid", automaticFallback: false, session: session)
        do { _ = try await service.search("test"); XCTFail("An HTTP 401 must not become an empty success") }
        catch { XCTAssertTrue(error.localizedDescription.contains("401")) }
    }

    func testInvidiousDistinguishesHTMLFromAnIncompatibleJSONSchema() async throws {
        let session = stubSession()
        defer { session.invalidateAndCancel(); InvidiousStubProtocol.handler = nil }
        let service = try InvidiousService(address: "https://fixture.invalid", automaticFallback: false, session: session)
        for (body, expected) in [("<html><body>Service unavailable</body></html>", "page HTML"), ("{\"unexpected\":true}", "champs absents")] {
            InvidiousStubProtocol.handler = { _ in (200, Data(body.utf8)) }
            do { _ = try await service.search("test"); XCTFail("An invalid API response must not become empty results") }
            catch {
                XCTAssertTrue(error.localizedDescription.contains(expected), error.localizedDescription)
                XCTAssertFalse(error.localizedDescription.contains("CAPTCHA"), "An API schema error does not prove a CAPTCHA")
            }
        }
    }

    func testInvidiousCancellationDoesNotTryOtherInstances() async throws {
        let session = stubSession()
        defer { session.invalidateAndCancel(); InvidiousStubProtocol.handler = nil }
        InvidiousStubProtocol.handler = { _ in throw URLError(.cancelled) }
        let service = try InvidiousService(address: "https://fixture.invalid", automaticFallback: true, session: session)
        do { _ = try await service.search("test"); XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testInvidiousPlaylistPaginationKeepsOrder() async throws {
        let session = stubSession()
        defer { session.invalidateAndCancel(); InvidiousStubProtocol.handler = nil }
        InvidiousStubProtocol.handler = { request in
            let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value
            let json = page == "1"
                ? #"{"title":"Playlist test","videoCount":3,"videos":[{"videoId":"aaaaaaaaaaa","title":"A"},{"videoId":"bbbbbbbbbbb","title":"B"}]}"#
                : #"{"title":"Playlist test","videoCount":3,"videos":[{"videoId":"ccccccccccc","title":"C"}]}"#
            return (200, Data(json.utf8))
        }
        let service = try InvidiousService(address: "https://fixture.invalid", automaticFallback: false, session: session)
        let result = try await service.playlist(URL(string: "https://music.youtube.com/playlist?list=PLabcdefghijk")!)
        XCTAssertEqual(result.name, "Playlist test")
        XCTAssertEqual(result.tracks.map(\.title), ["A", "B", "C"])
        XCTAssertTrue(result.tracks.allSatisfy { $0.source == .invidious })
    }

    func testInvidiousRejectsRepeatedPlaylistPage() async throws {
        let session = stubSession()
        defer { session.invalidateAndCancel(); InvidiousStubProtocol.handler = nil }
        InvidiousStubProtocol.handler = { _ in (200, Data(#"{"videoCount":3,"videos":[{"videoId":"aaaaaaaaaaa","title":"A"},{"videoId":"bbbbbbbbbbb","title":"B"}]}"#.utf8)) }
        let service = try InvidiousService(address: "https://fixture.invalid", automaticFallback: false, session: session)
        do {
            _ = try await service.playlist(URL(string: "https://youtube.com/playlist?list=PLabcdefghijk")!)
            XCTFail("A repeated page must not silently truncate the playlist")
        } catch { XCTAssertTrue(error.localizedDescription.contains("répète")) }
    }

    /// A real network and native audio graph check, not a fixture or a UI-only test.
    @MainActor
    func testLiveInvidiousAACDecodesAndNativePlaybackAdvances() async throws {
        let service = try InvidiousService(automaticFallback: true)
        let found = try await MusicCatalogService().search("Niska Salé")
        let track = try XCTUnwrap(found.tracks.first { $0.title.lowercased() == "salé" && $0.artist.lowercased().contains("niska") })
        XCTAssertEqual(track.musicCatalog, "youtube-music")
        XCTAssertEqual(track.album, "Commando")
        XCTAssertFalse(track.title.localizedCaseInsensitiveContains("clip"))
        let store = LibraryStore(inMemory: true)
        store.settings.onlineAudioMode = "invidious" // Exercise the legacy progressive path explicitly.
        store.settings.volume = 0.1
        let player = AudioPlayer(library: store)
        defer { player.forget(track.id) }
        let began = Date()
        player.play(track, in: [track])
        for _ in 0..<150 {
            if !player.isLoading { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        guard player.error == nil, player.isPlaying, player.isStreaming else {
            XCTFail(player.error ?? "Cold progressive playback did not start")
            return
        }
        let startup = Date().timeIntervalSince(began)
        guard startup < 12 else { XCTFail("Cold progressive startup too slow: \(startup) s"); return }
        XCTAssertNotNil(player.firstAudioLatency)
        XCTAssertLessThanOrEqual(player.artworkFetchCount, 2, "Playback status observations must not trigger an artwork request loop")
        print("COLD PROGRESSIVE START: \(startup)s, first-audio clock=\(player.firstAudioLatency ?? -1)s, title=\(track.title), artist=\(track.artist), id=\(track.location), artwork requests=\(player.artworkFetchCount)")
        let loaded = try await service.audio(for: track) // Fetch the full file only after progressive startup was measured.
        let file = try AVAudioFile(forReading: loaded.fileURL)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        XCTAssertGreaterThan(duration, 60, "Expected a complete track, not a short preview")
        XCTAssertGreaterThanOrEqual(duration, track.duration * 0.8)
        file.framePosition = file.length / 3
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192))
        try file.read(into: buffer)
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        let peak = (0..<Int(buffer.frameLength)).map { abs(samples[$0]) }.max() ?? 0
        XCTAssertGreaterThan(peak, 0.0001, "Decoded audio must contain a non-silent signal")

        let start = player.position
        try await Task.sleep(for: .seconds(2))
        XCTAssertGreaterThan(player.position, start + 0.5)
        XCTAssertLessThanOrEqual(player.artworkFetchCount, 2)
        player.prepareNativeEffects()
        for _ in 0..<50 {
            if !player.isStreaming { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(player.isStreaming, "The prepared audio must support the full effects engine")
        XCTAssertTrue(player.isPlaying)
        player.seek(to: 30)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertGreaterThanOrEqual(player.position, 29)
        player.pause()
        XCTAssertFalse(player.isPlaying)
        print("LIVE MUSIC PASS: title=\(track.title), artist=\(track.artist), album=\(track.album), id=\(track.location), cold progressive startup=\(startup)s, first-audio clock=\(player.firstAudioLatency ?? -1)s, AAC bitrate=\(loaded.bitrate), decoded duration=\(duration), peak=\(peak), native effects handover/seek/pause verified")
    }

    func testMusicCatalogRejectsVideoResultsAndKeepsSongMetadata() throws {
        let page = try MusicCatalogService.parse(musicFixture())
        XCTAssertEqual(page.tracks.count, 1)
        let song = try XCTUnwrap(page.tracks.first)
        XCTAssertEqual(song.title, "Salé")
        XCTAssertEqual(song.artist, "Niska")
        XCTAssertEqual(song.album, "Commando")
        XCTAssertEqual(song.duration, 171)
        XCTAssertEqual(song.musicCatalog, "youtube-music")
        XCTAssertEqual(song.artworkURL?.absoluteString, "https://example.org/album.jpg")
        XCTAssertEqual(page.continuation, "NEXT_SONG_PAGE")
    }

    func testMusicCatalogDoesNotAcceptUnclassifiedGenericVideo() throws {
        let data = Data(#"{"contents":{"musicResponsiveListItemRenderer":{"playlistItemData":{"videoId":"abcdefghijk"},"flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Vlog"}]}}}]}}}"#.utf8)
        XCTAssertTrue(try MusicCatalogService.parse(data).tracks.isEmpty)
    }

    func testMusicCatalogPostsSongsFilterToYouTubeMusic() async throws {
        let session = stubSession()
        defer { session.invalidateAndCancel(); InvidiousStubProtocol.handler = nil }
        let fixture = try musicFixture()
        InvidiousStubProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.host, "music.youtube.com")
            XCTAssertEqual(request.url?.path, "/youtubei/v1/search")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-YouTube-Client-Name"), "67")
            return (200, fixture)
        }
        let page = try await MusicCatalogService(session: session).search("Niska")
        XCTAssertEqual(page.tracks.first?.artist, "Niska")
    }

    @MainActor
    func testLoadingDeadlineEndsSpinnerAndReportsFailure() async throws {
        let counter = LoadCallCounter()
        let player = AudioPlayer(library: LibraryStore(inMemory: true), loadingTimeout: 0.2, onlineLoader: HangingAudioLoader(counter: counter))
        let track = Track(title: "Network fixture", artist: "Test", source: .invidious, location: "abcdefghijk")
        defer { player.forget(track.id) }
        player.play(track)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertFalse(player.isLoading)
        XCTAssertFalse(player.isPlaying)
        XCTAssertNotNil(player.error)
        XCTAssertNil(player.loadingProgress)
        let calls = await counter.count
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testPressingPlayWhileLoadingCancelsInsteadOfRestarting() async throws {
        let counter = LoadCallCounter()
        let player = AudioPlayer(library: LibraryStore(inMemory: true), onlineLoader: HangingAudioLoader(counter: counter))
        let track = Track(title: "Network fixture", artist: "Test", source: .invidious, location: "abcdefghijk")
        defer { player.forget(track.id) }
        player.play(track)
        try await Task.sleep(for: .milliseconds(50))
        player.toggle()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(player.isLoading)
        XCTAssertNil(player.error)
        let calls = await counter.count
        XCTAssertEqual(calls, 1)
    }

    private func musicFixture() throws -> Data {
        func row(id: String, videoType: String) -> [String: Any] {
            ["musicResponsiveListItemRenderer": [
                "playlistItemData": ["videoId": id],
                "flexColumns": [
                    ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [["text": "Salé", "navigationEndpoint": ["watchEndpoint": ["videoId": id, "watchEndpointMusicSupportedConfigs": ["watchEndpointMusicConfig": ["musicVideoType": videoType]]]]]]]]],
                    ["musicResponsiveListItemFlexColumnRenderer": ["text": ["runs": [
                        ["text": "Niska", "navigationEndpoint": ["browseEndpoint": ["browseId": "UC_fixture_artist"]]],
                        ["text": " • "], ["text": "Commando", "navigationEndpoint": ["browseEndpoint": ["browseId": "MPRE_fixture_album"]]],
                        ["text": " • "], ["text": "2:51"]
                    ]]]]
                ],
                "thumbnail": ["musicThumbnailRenderer": ["thumbnail": ["thumbnails": [["url": "https://example.org/album.jpg", "width": 544]]]]]
            ]]
        }
        let data: [String: Any] = ["contents": ["musicShelfRenderer": [
            "contents": [row(id: "abcdefghijk", videoType: "MUSIC_VIDEO_TYPE_ATV"), row(id: "bbbbbbbbbbb", videoType: "MUSIC_VIDEO_TYPE_OMV")],
            "continuations": [["nextContinuationData": ["continuation": "NEXT_SONG_PAGE"]]]
        ]]]
        return try JSONSerialization.data(withJSONObject: data)
    }

    private func stubSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [InvidiousStubProtocol.self]
        return URLSession(configuration: config)
    }

    func testPlaybackDurationRejectsDoubleContainerDuration() {
        XCTAssertEqual(PlaybackDuration.effective(declared: 171, measured: 342), 171)
        XCTAssertEqual(PlaybackDuration.effective(declared: 171, measured: .nan), 171)
        XCTAssertEqual(PlaybackDuration.effective(declared: 171, measured: 30), 171)
        XCTAssertEqual(PlaybackDuration.effective(declared: 0, measured: 170.25), 170.25)
        XCTAssertEqual(PlaybackDuration.effective(declared: 171, measured: 170.25), 170.25)
    }

    @MainActor
    func testNativeSegmentStopsAtDeclaredEndWithoutSilentTail() async throws {
        let store = LibraryStore(inMemory: true)
        store.tracks = []
        let player = AudioPlayer(library: store)
        let short = Track(title: "Duration boundary fixture", artist: "Test", duration: 0.4, source: .bundled, location: "bleu-nuit.wav")
        defer { player.forget(short.id) }
        player.play(short, in: [short])
        try await Task.sleep(for: .seconds(1.2))
        XCTAssertEqual(player.duration, 0.4, accuracy: 0.01)
        XCTAssertFalse(player.isPlaying, "The 48-second file must stop at its declared test boundary, not append a silent tail")
        XCTAssertEqual(player.position, 0.4, accuracy: 0.05)
    }

    func testSpeedAndSemitoneRelationship() {
        XCTAssertEqual(AppSettings.rate(for: 12), 2, accuracy: 0.0001)
        XCTAssertEqual(AppSettings.rate(for: -12), 0.5, accuracy: 0.0001)
        XCTAssertEqual(AppSettings.rate(for: 1), 1.059463, accuracy: 0.0001)
        XCTAssertEqual(AppSettings.semitones(for: 2), 12, accuracy: 0.0001)
        XCTAssertEqual(AppSettings.semitones(for: 0.5), -12, accuracy: 0.0001)
    }

    func testLinkedAndIndependentSpeedSettings() {
        var settings = AppSettings()
        settings.setSemitones(7)
        XCTAssertEqual(settings.playbackRate, 1.498307, accuracy: 0.0001)
        settings.setPlaybackRate(1.25)
        XCTAssertEqual(settings.effectiveSemitones, 3.863137, accuracy: 0.0001)
        settings.setSpeedPitchLinked(false)
        settings.setSemitones(-3)
        XCTAssertEqual(settings.playbackRate, 1.25)
        settings.setSpeedPitchLinked(true)
        XCTAssertEqual(settings.effectiveSemitones, 3.863137, accuracy: 0.0001)
    }

    func testPlaylistMatchingRejectsCoversAndDifferentVersions() {
        let original = Track(title: "Salé", artist: "Niska", duration: 171, source: .catalogReference, location: "")
        var match = Track(title: "Salé", artist: "Niska", duration: 171, source: .invidious, location: "abcdefghijk")
        XCTAssertGreaterThanOrEqual(MusicCatalogService.matchScore(original, match), 85)
        match.artist = "Another Singer"
        XCTAssertLessThan(MusicCatalogService.matchScore(original, match), 85)
        match.artist = "Niska"; match.title = "Salé (Live)"
        XCTAssertEqual(MusicCatalogService.matchScore(original, match), 0)
        match.title = "Salé"; match.duration = 300
        XCTAssertLessThan(MusicCatalogService.matchScore(original, match), 85)
    }

    func testArtistSearchParsesProfileNotSongArtistLinks() throws {
        let data = Data(#"{"contents":[{"musicResponsiveListItemRenderer":{"navigationEndpoint":{"browseEndpoint":{"browseId":"UC_artist_profile"}},"flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Niska"}]}}}]}},{"musicResponsiveListItemRenderer":{"playlistItemData":{"videoId":"abcdefghijk"},"navigationEndpoint":{"browseEndpoint":{"browseId":"UC_wrong_song"}},"flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"A song, not a profile"}]}}}]}}]}"#.utf8)
        let artists = try MusicCatalogService.parseArtists(data)
        XCTAssertEqual(artists.map(\.name), ["Niska"])
        XCTAssertEqual(artists.first?.id, "UC_artist_profile")
    }

    func testDeezerImportKeepsMetadataAndNeverUsesPreviewAudio() async throws {
        let session = stubSession()
        defer { session.invalidateAndCancel(); InvidiousStubProtocol.handler = nil }
        InvidiousStubProtocol.handler = { request in
            if request.url?.path.hasSuffix("/tracks") == true {
                return (200, Data(#"{"data":[{"title":"Salé","duration":171,"artist":{"name":"Niska"},"album":{"title":"Commando"},"preview":"https://example.org/only-30-seconds.mp3"}]}"#.utf8))
            }
            return (200, Data(#"{"title":"Test playlist","public":true}"#.utf8))
        }
        let imported = try await PlatformPlaylistService(session: session).deezer(URL(string: "https://www.deezer.com/fr/playlist/123")!)
        XCTAssertEqual(imported.name, "Test playlist")
        XCTAssertEqual(imported.tracks.first?.source, .catalogReference)
        XCTAssertEqual(imported.tracks.first?.location, "")
        XCTAssertEqual(imported.tracks.first?.duration, 171)
    }

    @MainActor
    func testFollowedArtistsAreIncludedInBackup() throws {
        let store = LibraryStore(inMemory: true)
        let artist = MusicArtist(id: "UC_artist_profile", name: "Niska")
        store.toggleFollow(artist)
        let data = try Data(contentsOf: store.exportBackup())
        let decoded = try JSONDecoder().decode(LibrarySnapshot.self, from: data)
        XCTAssertEqual(decoded.followedArtists, [artist])
        store.toggleFollow(artist)
        XCTAssertTrue(store.followedArtists.isEmpty)
    }

    func testLiveArtistProfileLoadsPublicTracks() async throws {
        let service = MusicCatalogService()
        let artists = try await service.searchArtists("Niska")
        let found = try XCTUnwrap(artists.first { $0.name.lowercased() == "niska" })
        let profile = try await service.artist(found)
        XCTAssertTrue(profile.artist.name.localizedCaseInsensitiveContains("Niska"))
        XCTAssertFalse(profile.tracks.isEmpty)
        XCTAssertTrue(profile.tracks.allSatisfy { $0.musicCatalog == "youtube-music" })
    }

    @MainActor
    func testLivePrefetchedStreamingStartsWithinTwoSeconds() async throws {
        let page = try await MusicCatalogService().search("Niska Réseaux")
        let track = try XCTUnwrap(page.tracks.first { $0.title.localizedCaseInsensitiveContains("Réseaux") })
        let store = LibraryStore(inMemory: true)
        store.settings.onlineAudioMode = "invidious" // This performance test is for an AVPlayer preroll, not full SABR preparation.
        await InvidiousAudioLoader.prefetch([track], settings: store.settings)
        let player = AudioPlayer(library: store)
        defer { player.forget(track.id) }
        let began = Date()
        player.play(track, in: [track])
        for _ in 0..<100 {
            if player.firstAudioLatency != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(player.isPlaying, player.error ?? "Playback has not started")
        let latency = try XCTUnwrap(player.firstAudioLatency)
        XCTAssertLessThan(latency, 2)
        XCTAssertLessThan(Date().timeIntervalSince(began), 2.5)
        print("PREFETCHED START: first-audio clock=\(latency)s, title=\(track.title), id=\(track.location)")
    }

    @MainActor
    func testCrossfadeOverlapsTwoNativeDecksAndFinishes() async throws {
        let store = LibraryStore(inMemory: true); store.tracks = []
        store.settings.crossfadeEnabled = true; store.settings.crossfadeDuration = 0.6
        let player = AudioPlayer(library: store)
        let first = Track(title: "Fade fixture A", artist: "Test", duration: 4, source: .bundled, location: "bleu-nuit.wav")
        let second = Track(title: "Fade fixture B", artist: "Test", duration: 4, source: .bundled, location: "orbite.wav")
        defer { player.forget(second.id); player.forget(first.id) }
        player.play(first, in: [first, second])
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(player.isPlaying)
        player.next()
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(player.current?.id, second.id)
        XCTAssertTrue(player.isTransitioning)
        XCTAssertEqual(player.overlappingPlaybackCount, 2)
        try await Task.sleep(for: .seconds(1))
        XCTAssertFalse(player.isTransitioning)
        XCTAssertEqual(player.overlappingPlaybackCount, 1)
    }

    @MainActor
    func testDisabledCrossfadeDoesNotKeepAnOutgoingDeck() async throws {
        let store = LibraryStore(inMemory: true); store.tracks = []; store.settings.crossfadeEnabled = false
        let player = AudioPlayer(library: store)
        let first = Track(title: "Cut fixture A", artist: "Test", duration: 4, source: .bundled, location: "bleu-nuit.wav")
        let second = Track(title: "Cut fixture B", artist: "Test", duration: 4, source: .bundled, location: "orbite.wav")
        defer { player.forget(second.id); player.forget(first.id) }
        player.play(first, in: [first, second]); try await Task.sleep(for: .milliseconds(350))
        player.next(); try await Task.sleep(for: .milliseconds(350))
        XCTAssertFalse(player.isTransitioning)
        XCTAssertEqual(player.overlappingPlaybackCount, 1)
    }

    @MainActor
    func testPauseStopsBothCrossfadeDecks() async throws {
        let store = LibraryStore(inMemory: true); store.tracks = []
        store.settings.crossfadeEnabled = true; store.settings.crossfadeDuration = 3
        let player = AudioPlayer(library: store)
        let first = Track(title: "Pause fixture A", artist: "Test", duration: 5, source: .bundled, location: "bleu-nuit.wav")
        let second = Track(title: "Pause fixture B", artist: "Test", duration: 5, source: .bundled, location: "orbite.wav")
        defer { player.forget(second.id); player.forget(first.id) }
        player.play(first, in: [first, second]); try await Task.sleep(for: .milliseconds(350))
        player.next(); try await Task.sleep(for: .milliseconds(350)); player.pause()
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(player.isTransitioning)
        XCTAssertEqual(player.overlappingPlaybackCount, 0)
    }

    @MainActor
    func testAutomaticCrossfadeAdvancesBeforeTheOldTrackEnds() async throws {
        let store = LibraryStore(inMemory: true); store.tracks = []
        store.settings.crossfadeEnabled = true; store.settings.crossfadeDuration = 1
        let player = AudioPlayer(library: store)
        let first = Track(title: "Auto fixture A", artist: "Test", duration: 2, source: .bundled, location: "bleu-nuit.wav")
        let second = Track(title: "Auto fixture B", artist: "Test", duration: 3, source: .bundled, location: "orbite.wav")
        defer { player.forget(second.id); player.forget(first.id) }
        player.play(first, in: [first, second]); try await Task.sleep(for: .milliseconds(1750))
        XCTAssertEqual(player.current?.id, second.id)
        XCTAssertTrue(player.isPlaying)
    }

    func testLyricsUsePlainTextWhenSyncedFieldIsEmpty() throws {
        let result = try JSONDecoder().decode(LyricsResult.self, from: Data(#"{"plainLyrics":"Un texte de test","syncedLyrics":"  ","instrumental":false}"#.utf8))
        XCTAssertEqual(result.text, "Un texte de test")
    }

    func testLyricsFallbackUsesPrimaryArtistAndReturnsSyncedText() async throws {
        let session = stubSession()
        defer { session.invalidateAndCancel(); InvidiousStubProtocol.handler = nil }
        InvidiousStubProtocol.handler = { request in
            if request.url?.path == "/api/get" { return (404, Data()) }
            return (200, Data(#"[{"trackName":"Test song","artistName":"Artist","duration":120,"plainLyrics":"Texte de test","syncedLyrics":"[00:00.00]Texte de test","instrumental":false}]"#.utf8))
        }
        let track = Track(title: "Test song (Official Audio)", artist: "Artist, Guest", duration: 120, source: .invidious, location: "abcdefghijk")
        let result = try await LyricsService(session: session).fetch(for: track)
        XCTAssertFalse(LRCParser.parse(result?.text ?? "").isEmpty)
    }

    func testLyricsFallbackDoesNotDisplayAnotherArtistsWords() async throws {
        let session = stubSession()
        defer { session.invalidateAndCancel(); InvidiousStubProtocol.handler = nil }
        InvidiousStubProtocol.handler = { request in
            if request.url?.path == "/api/get" { return (404, Data()) }
            return (200, Data(#"[{"trackName":"Test song","artistName":"Unrelated singer","duration":120,"plainLyrics":"Wrong test fixture","instrumental":false}]"#.utf8))
        }
        let track = Track(title: "Test song", artist: "Artist", duration: 120, source: .invidious, location: "abcdefghijk")
        let result = try await LyricsService(session: session).fetch(for: track)
        XCTAssertNil(result)
    }

    func testLiveLyricsAreAvailableForTheMusicCatalogTrack() async throws {
        let track = Track(title: "Salé", artist: "Niska", album: "Commando", duration: 171, source: .invidious, location: "zka6uW2aurU")
        let result = try await LyricsService().fetch(for: track)
        let lines = LRCParser.parse(result?.text ?? "")
        XCTAssertGreaterThan(lines.count, 10)
        print("LIVE LYRICS: matched title/artist, synced lines=\(lines.count)")
    }

    @MainActor
    func testFavoritingASearchResultSavesItsTrack() {
        let store = LibraryStore(inMemory: true); store.tracks = []
        let result = Track(title: "Search fixture", artist: "Artist", source: .invidious, location: "abcdefghijk")
        store.toggleFavorite(result)
        XCTAssertEqual(store.likedTracks.count, 1)
        XCTAssertEqual(store.likedTracks.first?.location, "abcdefghijk")
        XCTAssertTrue(store.isFavorite(result))
    }

    @MainActor
    func testFavoritesUseCanonicalIdentityAcrossRepeatedSearches() {
        let store = LibraryStore(inMemory: true); store.tracks = []
        let first = Track(title: "Search fixture", artist: "Artist", source: .invidious, location: "abcdefghijk")
        let refreshed = Track(title: "Search fixture", artist: "Artist", source: .invidious, location: "abcdefghijk")
        XCTAssertNotEqual(first.id, refreshed.id)
        store.toggleFavorite(first)
        XCTAssertTrue(store.isFavorite(refreshed))
        store.toggleFavorite(refreshed)
        XCTAssertTrue(store.likedTracks.isEmpty)
        XCTAssertEqual(store.tracks.count, 1)
    }

    func testGoogleArtworkRequestsHighResolution() throws {
        let original = try XCTUnwrap(URL(string: "https://lh3.googleusercontent.com/image-id=w120-h120-l90-rj"))
        let upgraded = ArtworkURL.highResolution(original)
        XCTAssertTrue(upgraded.absoluteString.hasSuffix("=w1024-h1024-l95-rj"))
        XCTAssertEqual(upgraded.host, original.host)
        let wide = URL(string: "https://yt3.googleusercontent.com/image-id=w600-h300-l90-rj")!
        XCTAssertTrue(ArtworkURL.highResolution(wide, square: false).absoluteString.hasSuffix("=w1024-h512-l95-rj"))
    }

    func testOtherProvidersSignedArtworkURLsAreNotModified() {
        let signed = URL(string: "https://example.org/cover.jpg?width=120&signature=abc")!
        XCTAssertEqual(ArtworkURL.highResolution(signed), signed)
    }

    func testImportedCollaborationAndFeaturingMatchAutomatically() {
        let reference = Track(title: "Alpha (feat. Kalash)", artist: "Damso;Kalash", duration: 180, source: .catalogReference, location: "")
        let song = Track(title: "Alpha (avec Kalash)", artist: "Kalash, Damso", duration: 181, source: .invidious, location: "abcdefghijk")
        XCTAssertGreaterThanOrEqual(MusicCatalogService.matchScore(reference, song), 85)
    }

    func testSpotifyCSVNamesResolveToActualMusicIDs() async throws {
        let csv = Data("Track Name,Artist Name(s),Album Name,Duration (ms),Track URI\nSalé,Niska,Commando,171000,spotify:track:fixture".utf8)
        let imported = try PlaylistImporter.parse(csv, filename: "Spotify.csv")
        let reference = try XCTUnwrap(imported.tracks.first)
        XCTAssertEqual(reference.duration, 171)
        let session = stubSession()
        defer { session.invalidateAndCancel(); InvidiousStubProtocol.handler = nil }
        let fixture = try musicFixture()
        InvidiousStubProtocol.handler = { _ in (200, fixture) }
        let resolved = try await MusicCatalogService(session: session).match(reference)
        XCTAssertEqual(resolved.source, .invidious)
        XCTAssertEqual(resolved.musicCatalog, "youtube-music")
        XCTAssertEqual(resolved.location, "abcdefghijk")
        XCTAssertFalse(resolved.location.hasPrefix("spotify:"))
    }

    @MainActor
    func testNativeTabViewContainsASystemTabBar() async throws {
        let store = LibraryStore(inMemory: true)
        let player = AudioPlayer(library: store)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let host = UIHostingController(rootView: RootView().environment(store).environment(player))
        let window = UIWindow(windowScene: scene); window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(700))
        window.layoutIfNeeded()
        func containsTabBar(_ view: UIView) -> Bool { view is UITabBar || view.subviews.contains(where: containsTabBar) }
        XCTAssertTrue(containsTabBar(host.view), "Bottom navigation must be the actual system TabView/UITabBar, not custom buttons")
    }

    @MainActor
    func testLiveLyricsViewAutomaticallyFetchesAndCachesWords() async throws {
        let store = LibraryStore(inMemory: true)
        let track = Track(title: "Salé", artist: "Niska", album: "Commando", duration: 171, source: .invidious, location: "zka6uW2aurU", musicCatalog: "youtube-music")
        _ = store.add(track)
        let player = AudioPlayer(library: store)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let host = UIHostingController(rootView: LyricsView(track: track).environment(store).environment(player))
        let window = UIWindow(windowScene: scene); window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        for _ in 0..<120 {
            if !(store.track(track.id)?.lyrics ?? "").isEmpty { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let words = store.track(track.id)?.lyrics ?? ""
        XCTAssertGreaterThan(words.count, 100, "Opening the real SwiftUI lyrics view must fetch words without pressing a second search button")
        XCTAssertGreaterThan(LRCParser.parse(words).count, 10)
        print("LYRICS UI AUTO-FETCH: synced lines=\(LRCParser.parse(words).count), cache populated by the view")
    }

    @MainActor
    func testPerformanceLargeLibraryLookupsAndQueuePreparation() {
        let store = LibraryStore(inMemory: true)
        let tracks = (0..<2500).map { Track(title: "Performance \($0)", artist: "Artist \($0 % 50)", source: .unresolved, location: "perf-\($0)") }
        store.tracks = tracks
        store.history = (0..<20000).map { ListeningEvent(trackID: tracks[$0 % tracks.count].id, date: Date(timeIntervalSince1970: Double($0)), seconds: 30) }
        let playlist = Playlist(name: "Performance fixture", trackIDs: tracks.map(\.id))
        let began = ProcessInfo.processInfo.systemUptime
        var checksum = 0
        for _ in 0..<5 {
            checksum += store.tracks(in: playlist).count
            checksum += store.recentTracks.count
        }
        let lookupMilliseconds = (ProcessInfo.processInfo.systemUptime - began) * 1000
        XCTAssertEqual(checksum, 25000)
        XCTAssertLessThan(lookupMilliseconds, 1500, "Indexed library lookups must not stall the main thread for seconds")
        let player = AudioPlayer(library: store)
        let queueBegan = ProcessInfo.processInfo.systemUptime
        player.play(tracks[0], in: tracks)
        let queueMilliseconds = (ProcessInfo.processInfo.systemUptime - queueBegan) * 1000
        XCTAssertEqual(player.queue.count, tracks.count)
        player.forget(tracks[0].id)
        print("PERFORMANCE LIBRARY: tracks=2500 history=20000 repetitions=5 lookup_ms=\(lookupMilliseconds) queue_ms=\(queueMilliseconds)")
    }

    @MainActor
    func testPerformanceStableUIInvalidationsDuringPlayback() async throws {
        let store = LibraryStore(inMemory: true)
        let player = AudioPlayer(library: store)
        let stable = PerformanceRenderCounter(), clock = PerformanceRenderCounter()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let host = UIHostingController(rootView: VStack {
            StablePlaybackProbe(counter: stable)
            PlaybackClockProbe(counter: clock)
        }.environment(player))
        let window = UIWindow(windowScene: scene); window.rootViewController = host; window.makeKeyAndVisible()
        let track = try XCTUnwrap(store.tracks.first { $0.source == .bundled })
        defer { player.forget(track.id); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        player.play(track, in: [track])
        try await Task.sleep(for: .seconds(1))
        let stableBefore = stable.count, clockBefore = clock.count, position = player.position
        try await Task.sleep(for: .milliseconds(1500))
        XCTAssertGreaterThan(player.position, position + 0.5)
        XCTAssertLessThanOrEqual(stable.count - stableBefore, 1, "The clock must not invalidate a title-only view")
        XCTAssertGreaterThanOrEqual(clock.count - clockBefore, 2, "The progress view must still update")
        print("PERFORMANCE UI: interval=1.5s stable_body_updates=\(stable.count - stableBefore) clock_body_updates=\(clock.count - clockBefore)")
    }

    @MainActor
    func testArtworkCacheDownsamplesAndReusesDecodedImages() async throws {
        let session = stubSession()
        defer { session.invalidateAndCancel(); InvidiousStubProtocol.handler = nil }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2048, height: 1024), format: format)
        let image = renderer.image { context in UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2048, height: 1024)) }
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
        let calls = NetworkRequestCounter()
        InvidiousStubProtocol.handler = { _ in calls.increment(); return (200, data) }
        let cache = ArtworkImageCache(session: session)
        let request = ArtworkRequest(url: URL(string: "https://images.fixture.invalid/cover.jpg")!, pixels: 128, square: false)
        async let first = cache.image(for: request)
        async let second = cache.image(for: request)
        let (a, b) = await (first, second)
        let thumbnail = try XCTUnwrap(a)
        XCTAssertTrue(a === b)
        let again = await cache.image(for: request)
        XCTAssertTrue(a === again)
        XCTAssertEqual(calls.count, 1)
        let bitmap = try XCTUnwrap(thumbnail.cgImage)
        XCTAssertEqual(bitmap.width, 128); XCTAssertEqual(bitmap.height, 64)
        XCTAssertEqual(ArtworkRequest.pixelSize(points: 52, scale: 3), 256)
        XCTAssertEqual(ArtworkRequest.pixelSize(points: 360, scale: 3), 1024, "Full player artwork must remain high resolution")
        print("PERFORMANCE ARTWORK: original=2048x1024 thumbnail=\(bitmap.width)x\(bitmap.height) decoded_bytes=\(bitmap.bytesPerRow * bitmap.height) network_requests=\(calls.count)")
    }

    @MainActor
    func testLibraryIndexesAndDerivedCollectionsStayCorrectAfterEdits() {
        let store = LibraryStore(inMemory: true)
        let original = Track(title: "Original", artist: "Artist", source: .invidious, location: "abcdefghijk")
        store.tracks = [original]; store.favorites = [original.id]
        store.history = [ListeningEvent(trackID: original.id, date: Date(), seconds: 20)]
        XCTAssertEqual(store.recentTracks.first?.title, "Original")
        XCTAssertEqual(store.mostPlayedTracks.first?.id, original.id)
        XCTAssertEqual(store.likedTracks.count, 1)
        store.tracks[0].title = "Updated"
        XCTAssertEqual(store.track(original.id)?.title, "Updated")
        XCTAssertEqual(store.recentTracks.first?.title, "Updated")
        XCTAssertEqual(store.likedTracks.first?.title, "Updated")
        let replacement = Track(title: "Replacement", artist: "Artist", source: .invidious, location: "bbbbbbbbbbb")
        store.replaceSource(of: original.id, with: replacement)
        XCTAssertTrue(store.isFavorite(replacement))
        XCTAssertEqual(store.add([replacement, replacement]).map(\.id), [original.id, original.id])
        XCTAssertEqual(store.tracks.count, 1)
        store.tracks = []
        XCTAssertNil(store.track(original.id)); XCTAssertTrue(store.recentTracks.isEmpty); XCTAssertTrue(store.likedTracks.isEmpty)
    }

    func testLibraryWritesRunOffMainAndRejectOlderSnapshots() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("blusic-write-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let worker = LibraryPersistenceWorker()
        var settings = AppSettings(); settings.accent = "mint"
        let latest = LibrarySnapshot(tracks: [], playlists: [], favorites: [], history: [], settings: settings, queue: [], currentTrackID: nil)
        try await worker.write(latest, to: url, revision: 2)
        var older = latest; older.settings.accent = "orange"
        try await worker.write(older, to: url, revision: 1)
        let saved = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: url))
        XCTAssertEqual(saved.settings.accent, "mint")
        let mainThreadWrites = await worker.mainThreadWriteCount
        XCTAssertEqual(mainThreadWrites, 0)
    }

    @MainActor
    func testBackupMergeKeepsPlaylistAndFavoriteIDsForAnExistingSource() throws {
        let store = LibraryStore(inMemory: true)
        let existing = Track(title: "Same song", artist: "Artist", source: .invidious, location: "abcdefghijk")
        let imported = Track(title: "Same song", artist: "Artist", source: .invidious, location: "abcdefghijk")
        store.tracks = [existing]; store.playlists = []; store.favorites = []
        let playlist = Playlist(name: "Backup fixture", trackIDs: [imported.id])
        let backup = LibrarySnapshot(tracks: [imported], playlists: [playlist], favorites: [imported.id], history: [], settings: AppSettings(), queue: [], currentTrackID: nil)
        try store.restoreBackup(JSONEncoder().encode(backup))
        XCTAssertNotNil(store.track(imported.id))
        XCTAssertEqual(store.tracks(in: playlist).map(\.id), [imported.id])
        XCTAssertEqual(store.likedTracks.map(\.id), [imported.id])
    }

    func testRelayRetriesTransient500AndTriesUnproxiedMetadata() async throws {
        let session = stubSession()
        defer { session.invalidateAndCancel(); InvidiousStubProtocol.handler = nil }
        let calls = NetworkRequestCounter()
        InvidiousStubProtocol.handler = { request in
            if request.url?.path.hasPrefix("/api/v1/videos/") == true {
                calls.increment()
                if request.url?.query?.contains("local=true") == true { return (500, Data()) }
                return (200, Data(#"{"lengthSeconds":171,"adaptiveFormats":[{"url":"/audio.m4a","type":"audio/mp4; codecs=mp4a.40.2","bitrate":131055}]}"#.utf8))
            }
            return (206, Data([0, 0, 0, 20]) + Data("ftypM4A ".utf8) + Data(repeating: 0, count: 64))
        }
        let service = try InvidiousService(address: "https://fixture.invalid", automaticFallback: false, session: session)
        let track = Track(title: "Fixture", artist: "Artist", source: .invidious, location: "abcdefghijk")
        let stream = try await service.stream(for: track, preferProxy: true)
        XCTAssertEqual(stream.url.path, "/audio.m4a")
        XCTAssertEqual(calls.count, 3, "One transient retry, then a real alternate metadata mode")
    }

    @MainActor
    func testLiveStephanieFromUserReportStartsAndSeeks() async throws {
        let track = Track(title: "Stephanie", artist: "Nafeesisboujee", source: .invidious, location: "RFzfXv9wzfo", musicCatalog: "youtube-music")
        let store = LibraryStore(inMemory: true); store.settings.volume = 0.1
        let player = AudioPlayer(library: store)
        defer { player.forget(track.id) }
        player.play(track, in: [track])
        for _ in 0..<120 {
            if player.firstAudioLatency != nil || player.error != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertNil(player.error)
        let latency = try XCTUnwrap(player.firstAudioLatency)
        XCTAssertTrue(player.isPlaying); XCTAssertGreaterThan(player.duration, 60)
        player.seek(to: 30)
        try await Task.sleep(for: .seconds(1))
        XCTAssertGreaterThanOrEqual(player.position, 29)
        print("STEPHANIE USER-REPORT PLAYBACK: first_audio=\(latency)s duration=\(player.duration)s source=\(player.formatLabel) seek=\(player.position)s")
    }

    @MainActor
    func testFailedProgressiveStreamUsesVerifiedFileBeforeChangingProvider() async throws {
        let store = LibraryStore(inMemory: true)
        let url = try XCTUnwrap(Bundle(for: AudioPlayer.self).url(forResource: "bleu-nuit", withExtension: "wav"))
        let calls = StreamRecoveryCounter()
        let loader = FileRecoveryLoader(file: url, calls: calls)
        let player = AudioPlayer(library: store, loadingTimeout: 5, streamBufferTimeout: 0.15, onlineLoader: loader)
        let track = Track(title: "Progressive recovery fixture", artist: "Test", duration: 4, source: .invidious, location: "abcdefghijk")
        defer { player.forget(track.id) }
        player.play(track, in: [track])
        for _ in 0..<60 {
            if player.firstAudioLatency != nil || player.error != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertNil(player.error)
        XCTAssertTrue(player.isPlaying)
        XCTAssertFalse(player.isStreaming, "The validated file must replace the failed remote AVPlayer")
        XCTAssertNotNil(player.firstAudioLatency)
        let counts = await calls.counts
        XCTAssertEqual(counts.0, 1, "A failed relay must not replace the usable source before file recovery")
        XCTAssertEqual(counts.1, 1)
        player.seek(to: 2)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertGreaterThanOrEqual(player.position, 1.9)
    }

    @MainActor
    func testCancellingFileRecoveryDoesNotRestartPlayback() async throws {
        let store = LibraryStore(inMemory: true)
        let url = try XCTUnwrap(Bundle(for: AudioPlayer.self).url(forResource: "bleu-nuit", withExtension: "wav"))
        let calls = StreamRecoveryCounter()
        let loader = FileRecoveryLoader(file: url, calls: calls, delay: true)
        let player = AudioPlayer(library: store, loadingTimeout: 5, streamBufferTimeout: 0.1, onlineLoader: loader)
        let track = Track(title: "Cancelled recovery fixture", artist: "Test", duration: 4, source: .invidious, location: "bbbbbbbbbbb")
        defer { player.forget(track.id) }
        player.play(track)
        for _ in 0..<30 {
            let counts = await calls.counts
            if counts.1 > 0 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        player.pause()
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(player.isPlaying); XCTAssertFalse(player.isLoading); XCTAssertNil(player.error)
        let counts = await calls.counts
        XCTAssertEqual(counts.0, 1); XCTAssertEqual(counts.1, 1)
    }

    func testRejected403IsNotCachedAndNextAttemptResolvesFreshURL() async throws {
        let session = stubSession()
        defer { session.invalidateAndCancel(); InvidiousStubProtocol.handler = nil }
        let calls = NetworkRequestCounter()
        InvidiousStubProtocol.handler = { request in
            if request.url?.path == "/youtubei/v1/player" {
                calls.increment()
                let path = calls.count == 1 ? "expired" : "fresh"
                let json = "{\"playabilityStatus\":{\"status\":\"OK\"},\"streamingData\":{\"adaptiveFormats\":[{\"url\":\"https://media.googlevideo.com/\(path)\",\"mimeType\":\"audio/mp4; codecs=mp4a.40.2\",\"bitrate\":131055}]}}"
                return (200, Data(json.utf8))
            }
            if request.url?.path == "/expired" { return (403, Data()) }
            return (206, Data([0, 0, 0, 20]) + Data("ftypM4A ".utf8) + Data(repeating: 0, count: 64))
        }
        let cache = InvidiousStreamCache(resolver: OnlineStreamResolver(session: session))
        var settings = AppSettings(); settings.onlineAudioMode = "direct"
        let track = Track(title: "Fresh URL fixture", artist: "Test", source: .invidious, location: "abcdefghijk")
        do { _ = try await cache.resolve(track, settings: settings, direct: false); XCTFail("403 must remain a failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("403")) }
        let stream = try await cache.resolve(track, settings: settings, direct: false)
        XCTAssertEqual(stream.url.path, "/fresh"); XCTAssertEqual(calls.count, 2)
        await cache.invalidate(track, settings: settings)
        _ = try await cache.resolve(track, settings: settings, direct: false)
        XCTAssertEqual(calls.count, 3, "Explicit invalidation must discard expiring URLs")
    }

    func testFiniteRangeAssemblyRejectsMissingAndOverlappingBytes() async throws {
        XCTAssertNil(AudioByteRange.parse("bytes 1-0/20"))
        XCTAssertNil(AudioByteRange.parse("bytes 0-20/20"))
        XCTAssertNil(AudioByteRange.parse("bytes 0-10/*"))
        let session = stubSession()
        defer { session.invalidateAndCancel(); InvidiousStubProtocol.handler = nil; InvidiousStubProtocol.headerProvider = nil }
        let data = try Data(contentsOf: XCTUnwrap(Bundle(for: AudioPlayer.self).url(forResource: "bleu-nuit", withExtension: "wav")))
        let calls = NetworkRequestCounter()
        InvidiousStubProtocol.handler = { request in
            let header = request.value(forHTTPHeaderField: "Range") ?? ""
            XCTAssertNotEqual(header, "bytes=0-", "The reported host rejects open-ended ranges")
            let start = Int(header.dropFirst(6).split(separator: "-").first ?? "") ?? 0
            calls.increment()
            return (206, data.subdata(in: start..<min(start + 262144, data.count)))
        }
        InvidiousStubProtocol.headerProvider = { request in
            let start = Int((request.value(forHTTPHeaderField: "Range") ?? "").dropFirst(6).split(separator: "-").first ?? "") ?? 0
            return ["Content-Type": "audio/mp4", "Content-Range": "bytes \(start)-\(min(start + 262143, data.count - 1))/\(data.count)"]
        }
        let cache = AudioCache()
        let result = try await cache.localCopy(of: URL(string: "https://fixture.invalid/audio.m4a")!,
            cacheKey: UUID().uuidString, fileExtension: "m4a", expectedDuration: 48, session: session)
        defer { try? FileManager.default.removeItem(at: result) }
        XCTAssertEqual(calls.count, (data.count + 262143) / 262144)
        XCTAssertEqual(try AVAudioFile(forReading: result).length, 2116800)
    }

    func testAccessibleOpeningBytesDoNotHide403OnNextRange() async throws {
        let session = stubSession()
        defer { session.invalidateAndCancel(); InvidiousStubProtocol.handler = nil; InvidiousStubProtocol.headerProvider = nil }
        InvidiousStubProtocol.handler = { request in
            if request.value(forHTTPHeaderField: "Range") == "bytes=10000-10063" { return (403, Data()) }
            return (206, Data([0, 0, 0, 20]) + Data("ftypM4A ".utf8) + Data(repeating: 0, count: 64))
        }
        InvidiousStubProtocol.headerProvider = { _ in ["Content-Type": "audio/mp4", "Content-Range": "bytes 0-4095/20000"] }
        let stream = InvidiousStream(url: URL(string: "https://media.googlevideo.com/audio")!, bitrate: 131000, instance: URL(string: "https://www.youtube.com")!, duration: 143)
        do { try await OnlineStreamResolver.validateMedia(stream, session: session); XCTFail("Opening bytes alone must not select a denied source") }
        catch { XCTAssertTrue(error.localizedDescription.contains("suite est refusée")); XCTAssertTrue(error.localizedDescription.contains("403")) }
    }

    func testYouTubeiRelayUsesAuthForResolutionAndOnlySameHostAudio() async throws {
        let session = stubSession()
        defer { session.invalidateAndCancel(); InvidiousStubProtocol.handler = nil }
        let track = Track(title: "Relay fixture", artist: "Test", source: .invidious, location: "abcdefghijk")
        InvidiousStubProtocol.handler = { request in
            if request.url?.path.hasPrefix("/v1/streams/") == true {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
                return (200, Data(#"{"url":"/v1/audio/abcdefghijk?ticket=fixture","bitrate":131000,"duration":143}"#.utf8))
            }
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"), "Audio uses a temporary ticket rather than copying the private relay key")
            return (206, Data([0, 0, 0, 20]) + Data("ftypM4A ".utf8) + Data(repeating: 0, count: 64))
        }
        let stream = try await YouTubeRelayService(session: session).stream(for: track, server: URL(string: "https://relay.fixture.invalid")!, key: "fixture-key")
        XCTAssertEqual(stream.providerLabel, "youtubei.js")
        XCTAssertEqual(stream.url.host, "relay.fixture.invalid")
        InvidiousStubProtocol.handler = { _ in (200, Data(#"{"url":"https://other.invalid/v1/audio/abcdefghijk","bitrate":131000}"#.utf8)) }
        do { _ = try await YouTubeRelayService(session: session).stream(for: track, server: URL(string: "https://relay.fixture.invalid")!, key: "fixture-key"); XCTFail("A relay must not redirect media to an unrelated host") }
        catch { XCTAssertTrue(error.localizedDescription.contains("même serveur")) }
    }

    func testBundledRelayAutomaticallyConfiguresAudioWithoutExportingItsAccess() throws {
        let access = "app.ios." + String(repeating: "a", count: 64)
        let data: [String: Any] = ["url":"https://relay.fixture.invalid", "access":access, "expiresAt":0, "revision":"fixture-v1"]
        let config = try XCTUnwrap(BundledRelayConfiguration.parse(data))
        var settings = AppSettings(); settings.onlineAudioMode = "invidious"
        var saved: [String] = []
        let changed = try config.install(settings: &settings, installedRevision: nil) { key, address in saved = [key, address] }
        XCTAssertTrue(changed)
        XCTAssertEqual(settings.youtubeiRelayAddress, "https://relay.fixture.invalid")
        XCTAssertEqual(settings.audioSourceMode, "auto")
        XCTAssertEqual(saved, [access,"https://relay.fixture.invalid"])
        let backup = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
        XCTAssertFalse(backup.contains(access), "The client credential must not be serialized into library backups")
        XCTAssertEqual(config.access(for: "https://relay.fixture.invalid"), access)
        XCTAssertNil(config.access(for: "https://other.invalid"))
        settings.onlineAudioMode = "direct"
        XCTAssertFalse(try config.install(settings: &settings, installedRevision: "fixture-v1") { _, _ in XCTFail("Unchanged configuration must not be reinstalled") })
        XCTAssertEqual(settings.audioSourceMode, "direct")
        var disabled = AppSettings(); disabled.youtubeiRelayDisabled = true
        XCTAssertFalse(try config.install(settings: &disabled, installedRevision: nil) { _, _ in XCTFail("Explicit opt-out must remain disabled") })
        var invalid = data; invalid["access"] = "master-key-not-an-app-token"
        XCTAssertNil(BundledRelayConfiguration.parse(invalid))
        invalid = data; invalid["expiresAt"] = 123456789
        XCTAssertNil(BundledRelayConfiguration.parse(invalid))
    }

    func testYouTubeiOnlyModeRoutesAudioThroughThePreconfiguredRelay() async throws {
        let session = stubSession()
        defer { session.invalidateAndCancel(); InvidiousStubProtocol.handler = nil }
        InvidiousStubProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "relay.fixture.invalid", "youtubei-only mode must not silently use another provider")
            if request.url?.path.hasPrefix("/v1/streams/") == true {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-access")
                return (200, Data(#"{"url":"/v1/audio/abcdefghijk?ticket=fixture","bitrate":131042,"duration":166}"#.utf8))
            }
            return (206, Data([0,0,0,20]) + Data("ftypM4A ".utf8) + Data(repeating: 0, count: 64))
        }
        var settings = AppSettings(); settings.onlineAudioMode = "youtubei"; settings.youtubeiRelayAddress = "https://relay.fixture.invalid"
        let resolver = OnlineStreamResolver(session: session, relayAccess: { _ in "fixture-access" })
        let track = Track(title:"Relay audio fixture",artist:"Test",source:.invidious,location:"abcdefghijk")
        let stream = try await resolver.resolve(track, settings: settings)
        XCTAssertEqual(stream.providerLabel,"youtubei.js")
        XCTAssertEqual(stream.url.host,"relay.fixture.invalid")
    }

    func testHighQualityRequestReachesYouTubeiRelayAndRetainsItsRealBitrate() async throws {
        let session = stubSession()
        defer { session.invalidateAndCancel(); InvidiousStubProtocol.handler = nil }
        InvidiousStubProtocol.handler = { request in
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertEqual(items.first { $0.name == "quality" }?.value, "high")
            if request.url?.path.hasPrefix("/v1/streams/") == true {
                return (200, Data(#"{"url":"/v1/audio/abcdefghijk?ticket=fixture&quality=high","bitrate":131042,"duration":166,"requestedQuality":"high"}"#.utf8))
            }
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (206, Data([0,0,0,20]) + Data("ftypM4A ".utf8) + Data(repeating: 0, count: 64))
        }
        let track = Track(title: "Relay quality fixture", artist: "Test", source: .invidious, location: "abcdefghijk")
        let stream = try await YouTubeRelayService(session: session).stream(for: track, server: URL(string: "https://relay.fixture.invalid")!, key: "fixture", quality: .high)
        XCTAssertEqual(stream.quality, .high)
        XCTAssertEqual(stream.bitrate, 131042, "A high-quality preference must retain the actual bitrate when no higher format is offered")
    }

    func testRelayUpstream403RemainsVisibleInsteadOfBecomingAnUnknownPlayerError() async throws {
        let session = stubSession()
        defer { session.invalidateAndCancel(); InvidiousStubProtocol.handler = nil }
        InvidiousStubProtocol.handler = { _ in (502, Data(#"{"error":"YouTube upstream HTTP 403"}"#.utf8)) }
        let track = Track(title:"Reported failure fixture",artist:"Test",source:.invidious,location:"abcdefghijk")
        do { _ = try await YouTubeRelayService(session: session).stream(for:track,server:URL(string:"https://relay.fixture.invalid")!,key:"fixture");XCTFail("An upstream refusal must remain a failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("502"));XCTAssertTrue(error.localizedDescription.contains("403")) }
    }

    @MainActor
    func testLivePreconfiguredYouTubeiSABRPlaysFuturAmourAndSeeksNatively() async throws {
        let config = try XCTUnwrap(BundledRelayConfiguration.load(), "This build must actually bundle its youtubei.js access")
        let store = LibraryStore(inMemory:true)
        store.settings.onlineAudioMode = "youtubei"; store.settings.youtubeiRelayAddress = config.server.absoluteString
        store.settings.volume = 0.1
        let track = Track(title:"FUTUR AMOUR",artist:"L’ange",duration:166,source:.invidious,location:"qMAzmGNeDxc",musicCatalog:"youtube-music")
        let player = AudioPlayer(library:store,loadingTimeout:50)
        defer { player.forget(track.id) }
        player.play(track,in:[track])
        for _ in 0..<200 {
            if player.firstAudioLatency != nil || player.error != nil { break }
            try await Task.sleep(for:.milliseconds(250))
        }
        guard player.error == nil, player.isPlaying, player.firstAudioLatency != nil, player.formatLabel.contains("youtubei.js") else {
            XCTFail(player.error ?? "Le moteur youtubei.js n’a pas commencé la lecture native")
            return
        }
        XCTAssertGreaterThan(player.duration,160)
        player.seek(to:90)
        try await Task.sleep(for:.seconds(1.5))
        guard player.position >= 89 else { XCTFail("Le déplacement natif n’a pas abouti"); return }
        print("LIVE YOUTUBEI SABR: native playback and seek verified; first_audio=\(player.firstAudioLatency ?? -1)s duration=\(player.duration)s")
    }

    func testOnDeviceResolverBridgeOnlyAllowsItsPublicProviderHosts() {
        for address in ["https://www.youtube.com/youtubei/v1/player", "https://jnn-pa.googleapis.com/rpc", "https://rr1.googlevideo.com/audio", "https://www.gstatic.com/script.js"] {
            XCTAssertTrue(NativeYouTubeRequestPolicy.allows(URL(string: address)!))
        }
        for address in ["http://www.youtube.com/", "https://127.0.0.1/", "https://youtube.com.attacker.invalid/", "https://user:pass@www.youtube.com/", "https://www.youtube.com:8443/"] {
            XCTAssertFalse(NativeYouTubeRequestPolicy.allows(URL(string: address)!))
        }
    }

    func testUpcomingPreparationStartsAt45PlaybackSecondsIncludingVarispeed() {
        XCTAssertFalse(QueuePreparationPolicy.shouldStart(duration: 200, position: 154.9, rate: 1))
        XCTAssertTrue(QueuePreparationPolicy.shouldStart(duration: 200, position: 155, rate: 1))
        XCTAssertTrue(QueuePreparationPolicy.shouldStart(duration: 30, position: 0.2, rate: 1))
        XCTAssertTrue(QueuePreparationPolicy.shouldStart(duration: 200, position: 110, rate: 2))
        XCTAssertFalse(QueuePreparationPolicy.shouldStart(duration: 200, position: 109, rate: 2))
        XCTAssertFalse(QueuePreparationPolicy.shouldStart(duration: 0, position: 0, rate: 1))
        XCTAssertFalse(QueuePreparationPolicy.shouldStart(duration: .nan, position: 0, rate: 1))
    }

    func testOfflineDownloadPersistsAfterRestartAndPlaysWithoutAnyNetworkLoader() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("offline-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try XCTUnwrap(Bundle(for: AudioPlayer.self).url(forResource: "orbite", withExtension: "wav"))
        let track = Track(title: "Offline fixture", artist: "Blusic test", duration: 48, source: .invidious, location: "aaaaaaaaaaa")
        let storage = OfflineAudioStore(root: root)
        let entry = try await storage.save(InvidiousAudio(fileURL: file, bitrate: 131000, instance: URL(string: "https://fixture.invalid")!, duration: 48), track: track)
        XCTAssertGreaterThan(entry.bytes, 1_000_000)
        let reopened = OfflineAudioStore(root: root)
        let audio = try await reopened.audio(for: track)
        XCTAssertTrue(audio?.fileURL.isFileURL == true)
        XCTAssertEqual(audio?.provider, "Téléchargé · hors ligne")
        XCTAssertNotEqual(audio?.fileURL, file, "An explicit download must copy the file outside its original cache/bundle location")
        let store = await LibraryStore(inMemory: true)
        let calls = OfflineDownloadFixtureCounter()
        let downloads = await OfflineDownloads(library: store, store: reopened, loader: OfflineFixtureLoader(file: file, calls: calls, failures: [track.location]))
        await MainActor.run { store.downloads = downloads }
        await downloads.waitUntilReady()
        let player = await AudioPlayer(library: store, onlineLoader: OfflineFixtureLoader(file: file, calls: calls, failures: [track.location]))
        await player.play(track, in: [track])
        for _ in 0..<40 {
            let latency = await player.firstAudioLatency
            if latency != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let result = await MainActor.run { (player.isPlaying, player.firstAudioLatency, player.formatLabel, player.error) }
        XCTAssertTrue(result.0); XCTAssertNotNil(result.1); XCTAssertTrue(result.2.contains("hors ligne")); XCTAssertNil(result.3)
        await player.seek(to: 30); try await Task.sleep(for: .milliseconds(300))
        let position = await player.position; XCTAssertGreaterThanOrEqual(position, 29)
        let networkCalls = await calls.locations; XCTAssertTrue(networkCalls.isEmpty, "Offline playback must never ask the network loader to resolve a title")
        await player.pause()
        await downloads.remove(track)
        let removed = try await OfflineAudioStore(root: root).audio(for: track)
        XCTAssertNil(removed)
        let stillInLibrary = await store.track(track.id)
        XCTAssertNotNil(stillInLibrary, "Removing a download must keep its library entry")
    }

    @MainActor
    func testPlaylistDownloadsContinueAfterOneFailureAndDoNotDownloadDuplicates() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("offline-playlist-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try XCTUnwrap(Bundle(for: AudioPlayer.self).url(forResource: "orbite", withExtension: "wav"))
        let library = LibraryStore(inMemory: true), calls = OfflineDownloadFixtureCounter()
        let first = Track(title: "First", artist: "Test", duration: 48, source: .invidious, location: "aaaaaaaaaaa")
        let failed = Track(title: "Unavailable", artist: "Test", duration: 48, source: .invidious, location: "bbbbbbbbbbb")
        let last = Track(title: "Last", artist: "Test", duration: 48, source: .invidious, location: "ccccccccccc")
        let downloads = OfflineDownloads(library: library, store: OfflineAudioStore(root: root), loader: OfflineFixtureLoader(file: file, calls: calls, failures: [failed.location]))
        library.downloads = downloads
        let playlist = library.createPlaylist("Offline playlist", tracks: [first, failed, last])
        downloads.enqueue(library.tracks(in: playlist)); downloads.enqueue([first, last])
        await downloads.waitUntilIdle()
        XCTAssertEqual(downloads.records.count, 2); XCTAssertEqual(downloads.pendingCount, 0)
        XCTAssertNotNil(downloads.record(for: first)); XCTAssertNotNil(downloads.record(for: last)); XCTAssertNil(downloads.record(for: failed))
        if case .failed? = downloads.status(for: failed) {} else { XCTFail("A failed title needs a visible retry state") }
        let locations = await calls.locations; XCTAssertEqual(locations, [first.location, failed.location, last.location])
        downloads.enqueue([first]); await downloads.waitUntilIdle()
        let after = await calls.locations; XCTAssertEqual(after, locations)
        await downloads.removeAll()
        XCTAssertTrue(downloads.records.isEmpty)
        XCTAssertEqual(library.playlists.first { $0.id == playlist.id }?.trackIDs.count, 3)
    }

    func testOfflineStoreRejectsIncompleteAudioAndUntrustedManifestPaths() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("offline-invalid-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try XCTUnwrap(Bundle(for: AudioPlayer.self).url(forResource: "orbite", withExtension: "wav"))
        let track = Track(title: "Too long fixture", artist: "Test", duration: 300, source: .invidious, location: "aaaaaaaaaaa")
        let storage = OfflineAudioStore(root: root)
        do { _ = try await storage.save(InvidiousAudio(fileURL: file, bitrate: 131000, instance: URL(string: "https://fixture.invalid")!, duration: 300), track: track); XCTFail("Truncated audio must not become an offline download") } catch {}
        let empty = try await storage.all(); XCTAssertTrue(empty.isEmpty)
        let malicious = OfflineAudioRecord(id: OfflineAudioRecord.key(track), track: track, filename: "../orbite.wav", bytes: 100,
            bitrate: 131000, duration: 48, quality: "standard", downloadedAt: Date())
        try JSONEncoder().encode([malicious]).write(to: root.appendingPathComponent("downloads.json"))
        let loaded = try await OfflineAudioStore(root: root).all(); XCTAssertTrue(loaded.isEmpty)
    }

    @MainActor
    func testCancellingAnOfflineDownloadDoesNotLeaveACompletedEntry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("offline-cancel-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try XCTUnwrap(Bundle(for: AudioPlayer.self).url(forResource: "orbite", withExtension: "wav"))
        let library = LibraryStore(inMemory: true), calls = OfflineDownloadFixtureCounter()
        let track = Track(title: "Cancel fixture", artist: "Test", duration: 48, source: .invidious, location: "aaaaaaaaaaa")
        let downloads = OfflineDownloads(library: library, store: OfflineAudioStore(root: root), loader: OfflineFixtureLoader(file: file, calls: calls, delay: 5))
        downloads.enqueue([track])
        for _ in 0..<30 {
            let started = await calls.locations
            if !started.isEmpty { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        downloads.cancel(track); await downloads.waitUntilIdle()
        XCTAssertTrue(downloads.records.isEmpty); XCTAssertNil(downloads.status(for: track)); XCTAssertEqual(downloads.pendingCount, 0)
        let persisted = try await OfflineAudioStore(root: root).all(); XCTAssertTrue(persisted.isEmpty)
    }

    func testPreparationRetriesBeyondTwentyFailuresAndUsesBoundedBackoff() async throws {
        let fixture = RetryingPreparationFixture(failures: 20)
        let result = try await QueuePreparationPolicy.retry(operation: { try await fixture.attempt() }, sleep: { _ in })
        XCTAssertEqual(result, 21)
        XCTAssertEqual([1, 2, 3, 4, 5, 1000].map { QueuePreparationPolicy.retryDelay(afterFailure: $0) }, [1, 2, 4, 8, 10, 10])
    }

    @MainActor
    func testFailedUpcomingPreparationRetriesUntilReadyAndPauseCancelsPendingRetry() async throws {
        let store = LibraryStore(inMemory: true); store.tracks = []
        let file = try XCTUnwrap(Bundle(for: AudioPlayer.self).url(forResource: "orbite", withExtension: "wav"))
        let attempts = RetryingPreparationFixture(failures: 2)
        let player = AudioPlayer(library: store, onlineLoader: RetryingUpcomingLoader(file: file, attempts: attempts))
        let current = Track(title: "Retry current", artist: "Test", duration: 48, source: .bundled, location: "bleu-nuit.wav")
        let next = Track(title: "Retry next", artist: "Test", duration: 48, source: .invidious, location: "bbbbbbbbbbb")
        defer { player.forget(current.id); player.forget(next.id) }
        player.play(current, in: [current, next]); try await Task.sleep(for: .milliseconds(500)); player.seek(to: 4)
        for _ in 0..<100 {
            if player.upcomingPreparationStatus == "Titre suivant préchargé" { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(player.upcomingPreparationStatus, "Titre suivant préchargé")
        XCTAssertTrue(player.isPlaying); XCTAssertEqual(player.current?.id, current.id)
        let count = await attempts.count; XCTAssertEqual(count, 3)
        player.next(); try await Task.sleep(for: .milliseconds(350))
        let reused = await attempts.count; XCTAssertEqual(reused, 3)
        player.pause()

        let unavailable = RetryingPreparationFixture(failures: 1000)
        let other = AudioPlayer(library: store, onlineLoader: RetryingUpcomingLoader(file: file, attempts: unavailable))
        defer { other.pause() }
        other.play(current, in: [current, next]); try await Task.sleep(for: .milliseconds(500)); other.seek(to: 4)
        for _ in 0..<30 {
            let observed = await unavailable.count
            if observed > 0 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        other.pause(); let before = await unavailable.count
        try await Task.sleep(for: .seconds(1.3)); let after = await unavailable.count
        XCTAssertGreaterThan(before, 0); XCTAssertEqual(before, after, "Pause must stop retrying instead of starting background network requests forever")
    }

    func testCancelledResolverJobCannotDiscardTheNextJobsAudio() async throws {
        let spool = NativeYouTubeSpool()
        await spool.start(token: "old-job")
        try await spool.begin(expected: 4, token: "old-job")
        await spool.start(token: "new-job")
        try await spool.begin(expected: 4, token: "new-job")
        await spool.cancel(token: "old-job")
        do {
            try await spool.append(encoded: Data([1]).base64EncodedString(), token: "old-job")
            XCTFail("A stale callback must not write to a new job's audio file")
        } catch is CancellationError {} catch { XCTFail("Unexpected stale-job error: \(error)") }
        try await spool.append(encoded: Data([1, 2, 3, 4]).base64EncodedString(), token: "new-job")
        await spool.cancel(token: "new-job")
    }

    @MainActor
    func test45SecondPreparationIsReusedByNextAndTheCrossfade() async throws {
        let store = LibraryStore(inMemory: true); store.tracks = []
        store.settings.crossfadeEnabled = true; store.settings.crossfadeDuration = 1.2
        let file = try XCTUnwrap(Bundle(for: AudioPlayer.self).url(forResource: "orbite", withExtension: "wav"))
        let calls = UpcomingPreparationCounter()
        let player = AudioPlayer(library: store, onlineLoader: UpcomingPreparationLoader(file: file, calls: calls))
        let current = Track(title: "Current 48s fixture", artist: "Test", duration: 48, source: .bundled, location: "bleu-nuit.wav")
        let next = Track(title: "Next network fixture", artist: "Test", duration: 5, source: .invidious, location: "bbbbbbbbbbb")
        defer { player.forget(current.id); player.forget(next.id) }
        player.play(current, in: [current,next])
        try await Task.sleep(for: .milliseconds(450))
        let initial = await calls.count
        XCTAssertEqual(initial, 0, "Do not start the transition preparation while more than 45s remain")
        player.seek(to: 4)
        for _ in 0..<40 {
            if player.upcomingPreparationStatus == "Titre suivant préchargé" { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(player.upcomingPreparationStatus, "Titre suivant préchargé")
        let count = await calls.count
        XCTAssertEqual(count, 1)
        player.next()
        for _ in 0..<20 {
            if player.isPlaying, player.firstAudioLatency != nil, player.isTransitioning { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(player.current?.location, next.location)
        XCTAssertTrue(player.isPlaying)
        XCTAssertNotNil(player.firstAudioLatency, "Observe the incoming audio, not only the outgoing deck retained during loading")
        XCTAssertTrue(player.isTransitioning)
        XCTAssertEqual(player.overlappingPlaybackCount, 2)
        let finalCount = await calls.count
        XCTAssertEqual(finalCount, 1, "Next must reuse the prepared AAC/file instead of resolving the source a second time")
    }

    @MainActor
    func testShuffleUsesTheSameNextTitleThatWasPreparedInAdvance() async throws {
        let store = LibraryStore(inMemory: true); store.tracks = []
        let file = try XCTUnwrap(Bundle(for: AudioPlayer.self).url(forResource: "orbite", withExtension: "wav"))
        let calls = UpcomingPreparationCounter()
        let player = AudioPlayer(library: store, onlineLoader: UpcomingPreparationLoader(file: file, calls: calls))
        player.shuffle = true
        let current = Track(title: "Shuffle current fixture", artist: "Test", duration: 48, source: .bundled, location: "bleu-nuit.wav")
        let a = Track(title: "Shuffle next A", artist: "Test", duration: 5, source: .invidious, location: "aaaaaaaaaaa")
        let b = Track(title: "Shuffle next B", artist: "Test", duration: 5, source: .invidious, location: "bbbbbbbbbbb")
        defer { player.forget(current.id); player.forget(a.id); player.forget(b.id) }
        player.play(current, in: [current,a,b])
        try await Task.sleep(for: .milliseconds(450)); player.seek(to: 4)
        for _ in 0..<40 {
            if player.upcomingPreparationStatus == "Titre suivant préchargé" { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let prepared = await calls.lastLocation
        XCTAssertNotNil(prepared)
        player.next()
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(player.current?.location, prepared, "Shuffle must not choose a different title at the last moment")
        let repeated = await calls.calls(for: prepared ?? "")
        XCTAssertEqual(repeated, 1, "The prepared title must not be resolved again; the following title may now begin its own preparation")
    }

    @MainActor
    func testChangingQualityRepreparesTheNextTitleWithoutInterruptingCurrentAudio() async throws {
        let store = LibraryStore(inMemory: true); store.tracks = []
        let file = try XCTUnwrap(Bundle(for: AudioPlayer.self).url(forResource: "orbite", withExtension: "wav"))
        let calls = UpcomingPreparationCounter()
        let player = AudioPlayer(library: store, onlineLoader: UpcomingPreparationLoader(file: file, calls: calls))
        let current = Track(title: "Quality current", artist: "Test", duration: 48, source: .bundled, location: "bleu-nuit.wav")
        let next = Track(title: "Quality next", artist: "Test", duration: 5, source: .invidious, location: "bbbbbbbbbbb")
        defer { player.forget(current.id); player.forget(next.id) }
        player.play(current, in: [current,next])
        try await Task.sleep(for: .milliseconds(450)); player.seek(to: 4)
        for _ in 0..<40 {
            if player.upcomingPreparationStatus == "Titre suivant préchargé" { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        store.settings.highQualityAudio = true; player.apply(store.settings)
        for _ in 0..<40 {
            if player.upcomingPreparationStatus == "Titre suivant préchargé" { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let qualities = await calls.qualities
        XCTAssertEqual(qualities, [.standard,.high])
        XCTAssertEqual(player.current?.id, current.id); XCTAssertTrue(player.isPlaying); XCTAssertNil(player.error)
        player.next()
        for _ in 0..<20 {
            if player.isPlaying, player.firstAudioLatency != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(player.current?.location, next.location)
        let count = await calls.count
        XCTAssertEqual(count, 2, "The high-quality preparation must be reused, not resolved a third time")
    }
}

private actor UpcomingPreparationCounter {
    private(set) var count = 0
    private(set) var lastLocation: String?
    private var locations: [String] = []
    private(set) var qualities: [OnlineAudioQuality] = []
    func record(_ location: String, quality: OnlineAudioQuality) { count += 1; lastLocation = location; locations.append(location); qualities.append(quality) }
    func calls(for location: String) -> Int { locations.filter { $0 == location }.count }
}

private actor OfflineDownloadFixtureCounter {
    private(set) var locations: [String] = []
    func record(_ location: String) { locations.append(location) }
}
private struct OfflineFixtureLoader: OnlineAudioLoading {
    let file: URL
    let calls: OfflineDownloadFixtureCounter
    var failures: Set<String> = []
    var delay: Double = 0
    func load(_ track: Track, settings: AppSettings, progress: @escaping @Sendable (AudioLoadUpdate) -> Void) async throws -> InvidiousAudio {
        await calls.record(track.location)
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        if failures.contains(track.location) { throw BlusicError.message("Fixture source unavailable") }
        return InvidiousAudio(fileURL: file, bitrate: 131000, instance: URL(string: "https://fixture.invalid")!, duration: track.duration)
    }
}

private actor RetryingPreparationFixture {
    let failures: Int
    private(set) var count = 0
    init(failures: Int) { self.failures = failures }
    func attempt() throws -> Int {
        count += 1
        if count <= failures { throw BlusicError.message("Fixture : source temporairement indisponible") }
        return count
    }
}
private struct RetryingUpcomingLoader: StreamingAudioLoading {
    let file: URL
    let attempts: RetryingPreparationFixture
    func load(_ track: Track, settings: AppSettings, progress: @escaping @Sendable (AudioLoadUpdate) -> Void) async throws -> InvidiousAudio {
        _ = try await attempts.attempt()
        return InvidiousAudio(fileURL: file, bitrate: 131000, instance: URL(string: "https://fixture.invalid")!, duration: track.duration)
    }
    func playback(_ track: Track, settings: AppSettings, direct: Bool) async throws -> OnlinePlaybackResource {
        .file(try await load(track, settings: settings, progress: { _ in }))
    }
}

private struct UpcomingPreparationLoader: StreamingAudioLoading {
    var file: URL
    var calls: UpcomingPreparationCounter
    func load(_ track: Track, settings: AppSettings, progress: @escaping @Sendable (AudioLoadUpdate) -> Void) async throws -> InvidiousAudio {
        throw BlusicError.message("The test must use the streaming loader's prepared-file result")
    }
    func playback(_ track: Track, settings: AppSettings, direct: Bool) async throws -> OnlinePlaybackResource {
        await calls.record(track.location, quality: settings.audioQuality)
        try await Task.sleep(for: .milliseconds(180))
        return .file(InvidiousAudio(fileURL: file, bitrate: 0, instance: URL(string: "https://fixture.invalid")!, duration: track.duration, provider: "Prepared test fixture", quality: settings.audioQuality))
    }
}

private actor StreamRecoveryCounter {
    private var playback = 0, prepared = 0
    var counts: (Int, Int) { (playback, prepared) }
    func played() { playback += 1 }
    func preparing() { prepared += 1 }
}

private struct FileRecoveryLoader: StreamingAudioLoading {
    var file: URL
    var calls: StreamRecoveryCounter
    var delay = false
    func load(_ track: Track, settings: AppSettings, progress: @escaping @Sendable (AudioLoadUpdate) -> Void) async throws -> InvidiousAudio {
        throw BlusicError.message("The test must start through the progressive path")
    }
    func playback(_ track: Track, settings: AppSettings, direct: Bool) async throws -> OnlinePlaybackResource {
        await calls.played()
        if direct { throw BlusicError.message("The alternate provider is unavailable in this test") }
        return .stream(InvidiousStream(url: URL(string: "https://fixture.invalid/audio.m4a")!, bitrate: 128000,
            instance: URL(string: "https://www.youtube.com")!, duration: 4))
    }
    func prepareFile(_ stream: InvidiousStream, for track: Track) async throws -> InvidiousAudio {
        await calls.preparing()
        if delay { try await Task.sleep(for: .seconds(5)) }
        return InvidiousAudio(fileURL: file, bitrate: 0, instance: stream.instance, duration: 4)
    }
}

private final class NetworkRequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func increment() { lock.lock(); value += 1; lock.unlock() }
}

@MainActor
private final class PerformanceRenderCounter { var count = 0 }

private struct StablePlaybackProbe: View {
    @Environment(AudioPlayer.self) private var player
    let counter: PerformanceRenderCounter
    var body: some View {
        counter.count += 1
        return Text(player.current?.title ?? "")
    }
}

private struct PlaybackClockProbe: View {
    @Environment(AudioPlayer.self) private var player
    let counter: PerformanceRenderCounter
    var body: some View {
        counter.count += 1
        return Text(player.position.clock)
    }
}

private actor LoadCallCounter {
    var count = 0
    func increment() { count += 1 }
}

private struct HangingAudioLoader: OnlineAudioLoading {
    var counter: LoadCallCounter
    func load(_ track: Track, settings: AppSettings, progress: @escaping @Sendable (AudioLoadUpdate) -> Void) async throws -> InvidiousAudio {
        await counter.increment()
        try await Task.sleep(for: .seconds(60))
        throw URLError(.timedOut)
    }
}

private final class InvidiousStubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    static var headerProvider: ((URLRequest) -> [String: String])?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.handler)
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: Self.headerProvider?(request) ?? ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
