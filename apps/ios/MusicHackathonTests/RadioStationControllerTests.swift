import XCTest
@testable import MusicHackathon

@MainActor
final class RadioStationControllerTests: XCTestCase {
  func testLoadCurrentStationUsesBackendQueue() async {
    let station = makeStation(items: [
      makeQueueItem(title: "One", appleMusicID: "one"),
      makeQueueItem(title: "Two", appleMusicID: "two")
    ])
    let controller = RadioStationController(
      playbackController: PlaybackController(),
      stationClient: MockStationClient(result: .success(station))
    )

    await controller.loadCurrentStation()

    XCTAssertEqual(controller.stationTitle, "Backend Radio")
    XCTAssertEqual(controller.stationIntro, "Complete backend station.")
    XCTAssertNil(controller.currentItem)
    XCTAssertEqual(controller.queue.map(\.track.title), ["One", "Two"])
    XCTAssertNil(controller.errorMessage)
  }

  func testStartStationPlaysFirstBackendTrackAndKeepsUpNext() async {
    let station = makeStation(items: [
      makeQueueItem(title: "One", appleMusicID: "one"),
      makeQueueItem(title: "Two", appleMusicID: "two")
    ])
    let playbackController = PlaybackController()
    let controller = RadioStationController(
      playbackController: playbackController,
      stationClient: MockStationClient(result: .success(station))
    )

    await controller.startStation()
    await waitForPlayback(playbackController, title: "One")

    XCTAssertEqual(controller.currentItem?.track.title, "One")
    XCTAssertEqual(controller.queue.map(\.track.title), ["Two"])
    XCTAssertEqual(playbackController.currentTrack?.title, "One")
  }

  func testPlayNextAdvancesThroughBackendQueue() async {
    let station = makeStation(items: [
      makeQueueItem(title: "One", appleMusicID: "one"),
      makeQueueItem(title: "Two", appleMusicID: "two")
    ])
    let playbackController = PlaybackController()
    let controller = RadioStationController(
      playbackController: playbackController,
      stationClient: MockStationClient(result: .success(station))
    )

    await controller.loadCurrentStation()
    await controller.playNext()
    await controller.playNext()
    await waitForPlayback(playbackController, title: "Two")

    XCTAssertEqual(controller.currentItem?.track.title, "Two")
    XCTAssertEqual(controller.queue.map(\.track.title), [])
    XCTAssertEqual(playbackController.currentTrack?.title, "Two")
  }

  func testBackendFailureLeavesQueueEmptyWithoutFallback() async {
    let controller = RadioStationController(
      playbackController: PlaybackController(),
      stationClient: MockStationClient(result: .failure(URLError(.cannotConnectToHost)))
    )

    await controller.loadCurrentStation()

    XCTAssertNil(controller.station)
    XCTAssertNil(controller.currentItem)
    XCTAssertTrue(controller.queue.isEmpty)
    XCTAssertEqual(controller.stationIntro, "The backend station is not available right now.")
    XCTAssertNotNil(controller.errorMessage)
  }

  private func makeStation(items: [RadioQueueItem]) -> RadioStation {
    RadioStation(
      id: "station-1",
      title: "Backend Radio",
      subtitle: "Complete backend station.",
      items: items
    )
  }

  private func makeQueueItem(title: String, appleMusicID: String) -> RadioQueueItem {
    RadioQueueItem(
      id: appleMusicID,
      track: Track(
        title: title,
        artist: "Artist",
        album: "Album",
        mood: "Radio",
        duration: 210,
        artworkSystemName: "music.note",
        appleMusicID: appleMusicID
      ),
      sourceTitle: "Backend",
      reason: "Programmed by backend."
    )
  }

  private func waitForPlayback(_ playbackController: PlaybackController, title: String) async {
    for _ in 0..<20 {
      if playbackController.currentTrack?.title == title {
        return
      }

      try? await Task.sleep(for: .milliseconds(25))
    }
  }
}

private struct MockStationClient: RadioStationFetching {
  let result: Result<RadioStation, Error>

  func fetchCurrentStation() async throws -> RadioStation {
    try result.get()
  }
}
