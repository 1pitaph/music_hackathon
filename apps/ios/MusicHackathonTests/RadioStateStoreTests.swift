import XCTest
@testable import MusicHackathon

final class RadioStateStoreTests: XCTestCase {
  func testSelectedPlaylistsAndFeedbackSurviveRoundTrip() {
    let userDefaults = makeUserDefaults()
    let store = RadioStateStore(userDefaults: userDefaults, key: "memory")
    var memory = RadioMemory()
    memory.selectedPlaylistIDs = ["morning", "night"]
    memory.recordPlay(trackKey: "track-1")
    memory.recordLike(trackKey: "track-2")
    memory.recordSkip(trackKey: "track-3")
    memory.recordDislike(trackKey: "track-4")

    store.saveMemory(memory)
    let loaded = store.loadMemory()

    XCTAssertEqual(loaded.selectedPlaylistIDs, ["morning", "night"])
    XCTAssertEqual(loaded.recentlyPlayedTrackKeys, ["track-1"])
    XCTAssertTrue(loaded.likedTrackKeys.contains("track-2"))
    XCTAssertTrue(loaded.skippedTrackKeys.contains("track-3"))
    XCTAssertTrue(loaded.dislikedTrackKeys.contains("track-4"))
  }

  func testCorruptedJSONFallsBackToEmptyMemory() {
    let userDefaults = makeUserDefaults()
    userDefaults.set(Data("not json".utf8), forKey: "memory")
    let store = RadioStateStore(userDefaults: userDefaults, key: "memory")

    let memory = store.loadMemory()

    XCTAssertTrue(memory.selectedPlaylistIDs.isEmpty)
    XCTAssertTrue(memory.recentlyPlayedTrackKeys.isEmpty)
    XCTAssertTrue(memory.likedTrackKeys.isEmpty)
  }

  private func makeUserDefaults() -> UserDefaults {
    let suiteName = "MusicHackathonTests.\(UUID().uuidString)"
    let userDefaults = UserDefaults(suiteName: suiteName)!
    userDefaults.removePersistentDomain(forName: suiteName)
    return userDefaults
  }
}
