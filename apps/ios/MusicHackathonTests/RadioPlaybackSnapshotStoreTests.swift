import XCTest
@testable import MusicHackathon

final class RadioPlaybackSnapshotStoreTests: XCTestCase {
  func testSaveAndLoadPreservesPlaybackSnapshot() async throws {
    let directory = temporaryDirectory()
    defer {
      try? FileManager.default.removeItem(at: directory)
    }
    let store = RadioPlaybackSnapshotStore(directoryURL: directory)
    let snapshot = makeSnapshot(savedAt: Date(timeIntervalSince1970: 1_000))

    try await store.save(snapshot)
    let loaded = await store.load(now: Date(timeIntervalSince1970: 1_100))

    XCTAssertEqual(loaded?.stationTitle, "Backend Radio")
    XCTAssertEqual(loaded?.currentItem?.track.title, "One")
    XCTAssertEqual(loaded?.queue.map(\.track.title), ["Two"])
    XCTAssertEqual(loaded?.history.map(\.track.title), ["Previous"])
    XCTAssertEqual(loaded?.stationSessionID, "session-1")
    XCTAssertEqual(loaded?.continuationCursor, "cursor-1")
    XCTAssertEqual(loaded?.playback.elapsedSeconds, 42)
    XCTAssertEqual(loaded?.playback.policy, .fullSongPreferred)
    XCTAssertEqual(loaded?.playback.activeBackend, .appleMusic)
  }

  func testExpiredSnapshotIsIgnoredAndCleared() async throws {
    let directory = temporaryDirectory()
    defer {
      try? FileManager.default.removeItem(at: directory)
    }
    let store = RadioPlaybackSnapshotStore(directoryURL: directory, validityInterval: 10)
    try await store.save(makeSnapshot(savedAt: Date(timeIntervalSince1970: 1_000)))

    let loaded = await store.load(now: Date(timeIntervalSince1970: 1_011))

    XCTAssertNil(loaded)
    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appending(path: "playback-snapshot.json").path))
  }

  func testFutureDatedSnapshotIsIgnoredAndCleared() async throws {
    let directory = temporaryDirectory()
    defer {
      try? FileManager.default.removeItem(at: directory)
    }
    let store = RadioPlaybackSnapshotStore(directoryURL: directory, validityInterval: 10)
    try await store.save(makeSnapshot(savedAt: Date(timeIntervalSince1970: 1_100)))

    let loaded = await store.load(now: Date(timeIntervalSince1970: 1_000))

    XCTAssertNil(loaded)
    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appending(path: "playback-snapshot.json").path))
  }

  func testMismatchedPlaybackTrackIsIgnoredAndCleared() async throws {
    let directory = temporaryDirectory()
    defer {
      try? FileManager.default.removeItem(at: directory)
    }
    let store = RadioPlaybackSnapshotStore(directoryURL: directory)
    var snapshot = makeSnapshot(savedAt: Date(timeIntervalSince1970: 1_000))
    snapshot.playback.track = makeQueueItem(title: "Mismatch").track
    try await store.save(snapshot)

    let loaded = await store.load(now: Date(timeIntervalSince1970: 1_100))

    XCTAssertNil(loaded)
    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appending(path: "playback-snapshot.json").path))
  }

  func testInvalidJSONIsIgnoredAndCleared() async throws {
    let directory = temporaryDirectory()
    defer {
      try? FileManager.default.removeItem(at: directory)
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let snapshotURL = directory.appending(path: "playback-snapshot.json")
    try Data("not-json".utf8).write(to: snapshotURL)
    let store = RadioPlaybackSnapshotStore(directoryURL: directory)

    let loaded = await store.load(now: Date())

    XCTAssertNil(loaded)
    XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))
  }

  func testClearRemovesSnapshot() async throws {
    let directory = temporaryDirectory()
    defer {
      try? FileManager.default.removeItem(at: directory)
    }
    let store = RadioPlaybackSnapshotStore(directoryURL: directory)
    try await store.save(makeSnapshot(savedAt: Date()))

    try await store.clear()

    let loaded = await store.load(now: Date())
    XCTAssertNil(loaded)
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appending(path: "RadioPlaybackSnapshotStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  }

  private func makeSnapshot(savedAt: Date) -> RadioPlaybackSnapshot {
    let current = makeQueueItem(title: "One")
    let next = makeQueueItem(title: "Two")
    let previous = makeQueueItem(title: "Previous")
    let station = RadioStation(
      id: "airset-personal",
      title: "Backend Radio",
      subtitle: "Complete backend station.",
      items: [previous, current, next],
      allowsAutoExtension: true
    )
    return RadioPlaybackSnapshot(
      savedAt: savedAt,
      station: station,
      queue: [next],
      currentItem: current,
      history: [previous],
      stationTitle: "Backend Radio",
      stationIntro: "Complete backend station.",
      hasPlayedStationIntro: true,
      stationSessionID: "session-1",
      continuationCursor: "cursor-1",
      playback: RadioPlaybackSnapshot.Playback(
        track: current.track,
        policy: .fullSongPreferred,
        elapsedSeconds: 42,
        wasPlaying: true,
        activeBackend: .appleMusic
      )
    )
  }

  private func makeQueueItem(title: String) -> RadioQueueItem {
    RadioQueueItem(
      id: title.lowercased(),
      track: Track(
        title: title,
        artist: "Artist",
        album: "Album",
        mood: "Radio",
        duration: 210,
        artworkSystemName: "music.note",
        artworkURL: URL(string: "https://example.com/\(title).jpg"),
        previewURL: URL(string: "https://example.com/\(title).m4a"),
        appleMusicID: title.lowercased()
      ),
      sourceTitle: "Backend",
      reason: "Programmed by backend."
    )
  }
}
