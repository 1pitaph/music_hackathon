import XCTest
@testable import MusicHackathon

final class RadioMemoryStoreTests: XCTestCase {
  func testRecordsEventsBuildsContextAndWritesMarkdown() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "RadioMemoryStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer {
      try? FileManager.default.removeItem(at: directory)
    }
    let store = RadioMemoryStore(directoryURL: directory, compressionEventThreshold: 2)

    try await store.record(RadioMemoryEvent(type: "like", track: makeTrack(title: "Future", mood: "Pop")))
    try await store.record(RadioMemoryEvent(type: "skip", track: makeTrack(title: "Noise", mood: "Harsh")))

    let context = try await store.buildContext()
    XCTAssertEqual(context.likedArtistsTop, ["WRABEL"])
    XCTAssertEqual(context.skippedMoodsTop, ["Harsh"])
    XCTAssertEqual(context.recentEvents.count, 2)
    let compressionRequest = try await store.compressionRequest()
    XCTAssertNotNil(compressionRequest)

    let markdown = try String(contentsOf: directory.appending(path: "memory.md"), encoding: .utf8)
    XCTAssertTrue(markdown.contains("# Airset Memory"))
    XCTAssertTrue(markdown.contains("WRABEL"))
    XCTAssertTrue(markdown.contains("Harsh"))
  }

  func testApplyCompressionUpdatesSummaryAndResetsThreshold() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "RadioMemoryStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer {
      try? FileManager.default.removeItem(at: directory)
    }
    let store = RadioMemoryStore(directoryURL: directory, compressionEventThreshold: 1)

    try await store.record(RadioMemoryEvent(type: "like", track: makeTrack(title: "Future", mood: "Pop")))
    try await store.applyCompression(
      RadioCompressedMemory(
        tasteSummary: "Likes intimate pop vocals.",
        avoidSummary: "Avoid harsh noise.",
        likedArtistsTop: ["WRABEL"],
        skippedMoodsTop: ["Harsh"],
        pinnedNotes: ["Softer music at night."]
      )
    )

    let snapshot = try await store.snapshot()
    XCTAssertEqual(snapshot.tasteSummary, "Likes intimate pop vocals.")
    XCTAssertEqual(snapshot.avoidSummary, "Avoid harsh noise.")
    XCTAssertEqual(snapshot.uncompressedEventCount, 0)
    let compressionRequest = try await store.compressionRequest()
    XCTAssertNil(compressionRequest)
  }

  private func makeTrack(title: String, mood: String) -> Track {
    Track(
      title: title,
      artist: "WRABEL",
      album: "Album",
      mood: mood,
      duration: 200,
      artworkSystemName: "music.note",
      previewURL: URL(string: "https://example.com/\(title).m4a")
    )
  }
}
