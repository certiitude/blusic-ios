import XCTest
import AVFoundation
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
        XCTAssertEqual(tracks.first?.source, .youtube)
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
}
