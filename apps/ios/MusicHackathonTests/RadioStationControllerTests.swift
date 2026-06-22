import XCTest
@testable import MusicHackathon

@MainActor
final class RadioStationControllerTests: XCTestCase {
  func testRefreshRecommendationsUsesAgentQueue() async {
    let seed = makeTrack(title: "Seed", artist: "Artist A", appleMusicID: "seed-1")
    let agent = MockRadioAgent { _, _ in
      RadioAgentGeneration(
        mode: "llm",
        stationIntro: "Agent built this station.",
        items: [
          RadioAgentGeneratedItem(
            radioIdentity: seed.radioIdentity,
            reason: "Agent chose this opener.",
            role: "opener",
            score: 91,
            source: "playlist"
          )
        ],
        diagnostics: []
      )
    }
    let controller = makeController(agent: agent)
    controller.seedTracks = [RadioSeedTrack(track: seed, playlistID: "playlist-1", playlistName: "Morning")]

    await controller.refreshRecommendations(action: .start)

    XCTAssertEqual(controller.stationIntro, "Agent built this station.")
    XCTAssertEqual(controller.queue.count, 1)
    XCTAssertEqual(controller.queue.first?.track.radioIdentity, seed.radioIdentity)
    XCTAssertEqual(controller.queue.first?.reason, "Agent chose this opener.")
  }

  func testRefreshRecommendationsFallsBackWhenAgentThrows() async {
    let seed = makeTrack(title: "Seed", artist: "Artist A", appleMusicID: "seed-1")
    let agent = MockRadioAgent { _, _ in
      throw URLError(.cannotConnectToHost)
    }
    let controller = makeController(agent: agent)
    controller.seedTracks = [RadioSeedTrack(track: seed, playlistID: "playlist-1", playlistName: "Morning")]

    await controller.refreshRecommendations(action: .start)

    XCTAssertEqual(controller.stationIntro, "Tuned from Morning, with a little room for discovery.")
    XCTAssertEqual(controller.queue.count, 1)
    XCTAssertEqual(controller.queue.first?.track.radioIdentity, seed.radioIdentity)
    XCTAssertNotEqual(controller.queue.first?.reason, "Agent chose this opener.")
  }

  func testRefreshRecommendationsFallsBackForUnknownAgentTrack() async {
    let seed = makeTrack(title: "Seed", artist: "Artist A", appleMusicID: "seed-1")
    let agent = MockRadioAgent { _, _ in
      RadioAgentGeneration(
        mode: "llm",
        stationIntro: "Bad agent response.",
        items: [
          RadioAgentGeneratedItem(
            radioIdentity: "appleMusic:made-up",
            reason: "This should not survive.",
            role: "opener",
            score: 91,
            source: "catalog"
          )
        ],
        diagnostics: []
      )
    }
    let controller = makeController(agent: agent)
    controller.seedTracks = [RadioSeedTrack(track: seed, playlistID: "playlist-1", playlistName: "Morning")]

    await controller.refreshRecommendations(action: .start)

    XCTAssertEqual(controller.stationIntro, "Tuned from Morning, with a little room for discovery.")
    XCTAssertEqual(controller.queue.count, 1)
    XCTAssertEqual(controller.queue.first?.track.radioIdentity, seed.radioIdentity)
    XCTAssertNotEqual(controller.queue.first?.reason, "This should not survive.")
  }

  private func makeController(agent: MockRadioAgent) -> RadioStationController {
    RadioStationController(
      playbackController: PlaybackController(),
      contextBuilder: MockContextBuilder(),
      agentClient: agent,
      stateStore: RadioStateStore(userDefaults: makeUserDefaults(), key: "memory")
    )
  }

  private func makeTrack(title: String, artist: String, appleMusicID: String) -> Track {
    Track(
      title: title,
      artist: artist,
      album: "Album",
      mood: "Pop",
      duration: 210,
      artworkSystemName: "music.note",
      appleMusicID: appleMusicID
    )
  }

  private func makeUserDefaults() -> UserDefaults {
    let suiteName = "MusicHackathonTests.\(UUID().uuidString)"
    let userDefaults = UserDefaults(suiteName: suiteName)!
    userDefaults.removePersistentDomain(forName: suiteName)
    return userDefaults
  }
}

private struct MockRadioAgent: RadioAgentGenerating {
  let handler: (RadioRuntimeContext, Int) async throws -> RadioAgentGeneration

  func generateQueue(from context: RadioRuntimeContext, limit: Int) async throws -> RadioAgentGeneration {
    try await handler(context, limit)
  }
}

private struct MockContextBuilder: RadioContextBuilding {
  func build(
    seedTracks: [RadioSeedTrack],
    memory: RadioMemory,
    tuning: RadioTuning,
    action: RadioRuntimeAction
  ) async -> RadioRuntimeContext {
    RadioRuntimeContext(
      seedTracks: seedTracks,
      catalogCandidates: [],
      memory: memory,
      tuning: tuning,
      currentAction: action
    )
  }
}
