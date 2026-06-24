import XCTest
@testable import MusicHackathon

final class VirtualMusicLibraryTests: XCTestCase {
  func testDecodeTracksPreservesPromptMetadata() throws {
    let data = """
    {
      "libraryID": "test-library",
      "title": "Test Library",
      "tracks": [
        {
          "id": "signal",
          "title": "Signal",
          "artist": "Artist A",
          "album": "Album A",
          "mood": "Warm",
          "duration": 210,
          "artworkSystemName": "waveform",
          "artworkURL": "https://example.com/signal.jpg",
          "previewURL": "https://example.com/signal.m4a",
          "playlistName": "Virtual Library: Warm Starts",
          "source": "virtual_music_library_json",
          "sourceLane": "familiar_anchor",
          "sourceScore": 0.91,
          "reasonSignals": ["warm opener", "intimate vocal"]
        }
      ]
    }
    """.data(using: .utf8)!

    let tracks = try VirtualMusicLibrary.decodeTracks(from: data)

    XCTAssertEqual(tracks.count, 1)
    XCTAssertEqual(tracks[0].title, "Signal")
    XCTAssertEqual(tracks[0].playlistName, "Virtual Library: Warm Starts")
    XCTAssertEqual(tracks[0].source, "virtual_music_library_json")
    XCTAssertEqual(tracks[0].sourceLane, "familiar_anchor")
    XCTAssertEqual(tracks[0].sourceScore, 0.91)
    XCTAssertEqual(tracks[0].reasonSignals, ["warm opener", "intimate vocal"])
    XCTAssertEqual(tracks[0].artworkURL?.absoluteString, "https://example.com/signal.jpg")
    XCTAssertEqual(tracks[0].previewURL?.absoluteString, "https://example.com/signal.m4a")
  }
}
