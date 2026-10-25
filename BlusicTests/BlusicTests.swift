import XCTest
import AVFoundation
import SwiftUI
@testable import Blusic

final class BlusicTests: XCTestCase {
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
        let host = UIHostingController(rootView: RootView().environmentObject(store).environmentObject(player))
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
        let host = UIHostingController(rootView: LyricsView(track: track).environmentObject(store).environmentObject(player))
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
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.handler)
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
