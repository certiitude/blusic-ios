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
