import XCTest
@testable import MusicHackathon

@MainActor
final class RadioStationControllerTests: XCTestCase {
  func testLoadCurrentStationUsesBackendQueue() async {
    let station = makeStation(items: [
      makeQueueItem(title: "One", appleMusicID: "one", handoffText: "Welcome into One."),
      makeQueueItem(title: "Two", appleMusicID: "two")
    ])
    let controller = RadioStationController(
      playbackController: MockPlaybackController(),
      stationClient: MockStationClient(result: .success(station)),
      memoryStore: MockMemoryStore()
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
      makeQueueItem(title: "One", appleMusicID: "one", handoffText: "Welcome into One."),
      makeQueueItem(title: "Two", appleMusicID: "two")
    ])
    let playbackController = MockPlaybackController()
    let controller = RadioStationController(
      playbackController: playbackController,
      stationClient: MockStationClient(result: .success(station)),
      memoryStore: MockMemoryStore()
    )

    await controller.startStation()
    await waitForPlayback(playbackController, title: "One")

    XCTAssertEqual(controller.currentItem?.track.title, "One")
    XCTAssertEqual(controller.currentItem?.handoffText, "Welcome into One.")
    XCTAssertEqual(controller.queue.map(\.track.title), ["Two"])
    XCTAssertEqual(playbackController.currentTrack?.title, "One")
  }

  func testPlayNextAdvancesThroughBackendQueue() async {
    let station = makeStation(items: [
      makeQueueItem(title: "One", appleMusicID: "one"),
      makeQueueItem(title: "Two", appleMusicID: "two")
    ])
    let playbackController = MockPlaybackController()
    let controller = RadioStationController(
      playbackController: playbackController,
      stationClient: MockStationClient(result: .success(station)),
      memoryStore: MockMemoryStore()
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
      playbackController: MockPlaybackController(),
      stationClient: MockStationClient(result: .failure(URLError(.cannotConnectToHost))),
      memoryStore: MockMemoryStore()
    )

    await controller.loadCurrentStation()

    XCTAssertNil(controller.station)
    XCTAssertNil(controller.currentItem)
    XCTAssertTrue(controller.queue.isEmpty)
    XCTAssertEqual(controller.stationIntro, "The backend station is not available right now.")
    XCTAssertNotNil(controller.errorMessage)
  }

  func testLoadLocalStationReplacesQueueAndPlaysFirstTrack() async {
    let playbackController = MockPlaybackController()
    let controller = RadioStationController(
      playbackController: playbackController,
      stationClient: MockStationClient(result: .success(makeStation(items: []))),
      memoryStore: MockMemoryStore()
    )
    let firstStation = RadioStation(
      id: "local-1",
      title: "First Local",
      subtitle: "First local queue.",
      items: [
        makeQueueItem(title: "Old One", appleMusicID: "old-one"),
        makeQueueItem(title: "Old Two", appleMusicID: "old-two")
      ]
    )
    let secondStation = RadioStation(
      id: "local-2",
      title: "Second Local",
      subtitle: "Second local queue.",
      items: [
        makeQueueItem(title: "New One", appleMusicID: "new-one"),
        makeQueueItem(title: "New Two", appleMusicID: "new-two")
      ]
    )

    await controller.loadLocalStation(firstStation, playImmediately: true)
    await waitForPlayback(playbackController, title: "Old One")
    await controller.playNext()
    await waitForPlayback(playbackController, title: "Old Two")

    await controller.loadLocalStation(secondStation, playImmediately: true)
    await waitForPlayback(playbackController, title: "New One")

    XCTAssertEqual(controller.stationTitle, "Second Local")
    XCTAssertEqual(controller.stationIntro, "Second local queue.")
    XCTAssertEqual(controller.currentItem?.track.title, "New One")
    XCTAssertEqual(controller.queue.map(\.track.title), ["New Two"])
    XCTAssertEqual(playbackController.currentTrack?.title, "New One")
    XCTAssertNil(controller.errorMessage)
  }

  func testStartStationPlaysIntroSpeechBeforeFirstTrack() async {
    let station = makeStation(
      items: [
        makeQueueItem(title: "One", appleMusicID: "one"),
        makeQueueItem(title: "Two", appleMusicID: "two")
      ],
      speech: RadioSpeech(
        stationIntro: RadioStationIntroCopy(
          text: "Welcome to Airset.",
          displayText: "Welcome to Airset.",
          targetItemId: "one"
        )
      )
    )
    let playbackController = MockPlaybackController()
    let controller = RadioStationController(
      playbackController: playbackController,
      stationClient: MockStationClient(result: .success(station)),
      memoryStore: MockMemoryStore()
    )

    await controller.startStation()

    XCTAssertEqual(playbackController.currentSpeech?.displayText, "Welcome to Airset.")
    XCTAssertNil(controller.currentItem)

    playbackController.finish(.speech)
    await waitForPlayback(playbackController, title: "One")

    XCTAssertEqual(controller.currentItem?.track.title, "One")
    XCTAssertEqual(controller.queue.map(\.track.title), ["Two"])
  }

  func testAutomaticCompletionPlaysTransitionSpeechBeforeNextTrack() async {
    let station = makeStation(
      items: [
        makeQueueItem(title: "One", appleMusicID: "one"),
        makeQueueItem(title: "Two", appleMusicID: "two")
      ],
      speech: RadioSpeech(
        betweenTracks: [
          RadioTransitionCopy(
            id: "transition-1",
            fromItemId: "one",
            toItemId: "two",
            text: "Next up is Two.",
            displayText: "Next up is Two."
          )
        ]
      )
    )
    let playbackController = MockPlaybackController()
    let controller = RadioStationController(
      playbackController: playbackController,
      stationClient: MockStationClient(result: .success(station)),
      memoryStore: MockMemoryStore()
    )

    await controller.startStation()
    XCTAssertEqual(playbackController.currentTrack?.title, "One")

    playbackController.finish(.track)
    await waitForSpeech(playbackController, text: "Next up is Two.")

    XCTAssertNil(controller.currentItem)
    XCTAssertEqual(controller.queue.map(\.track.title), ["Two"])

    playbackController.finish(.speech)
    await waitForPlayback(playbackController, title: "Two")

    XCTAssertEqual(controller.currentItem?.track.title, "Two")
    XCTAssertTrue(controller.queue.isEmpty)
  }

  func testManualNextSkipsTransitionSpeech() async {
    let station = makeStation(
      items: [
        makeQueueItem(title: "One", appleMusicID: "one"),
        makeQueueItem(title: "Two", appleMusicID: "two")
      ],
      speech: RadioSpeech(
        betweenTracks: [
          RadioTransitionCopy(
            id: "transition-1",
            fromItemId: "one",
            toItemId: "two",
            text: "Next up is Two.",
            displayText: "Next up is Two."
          )
        ]
      )
    )
    let playbackController = MockPlaybackController()
    let controller = RadioStationController(
      playbackController: playbackController,
      stationClient: MockStationClient(result: .success(station)),
      memoryStore: MockMemoryStore()
    )

    await controller.startStation()
    await controller.playNext(reason: .manual)

    XCTAssertEqual(playbackController.currentTrack?.title, "Two")
    XCTAssertNil(playbackController.currentSpeech)
    XCTAssertEqual(controller.currentItem?.track.title, "Two")
  }

  private func makeStation(items: [RadioQueueItem], speech: RadioSpeech? = nil) -> RadioStation {
    RadioStation(
      id: "station-1",
      title: "Backend Radio",
      subtitle: "Complete backend station.",
      items: items,
      speech: speech
    )
  }

  private func makeQueueItem(title: String, appleMusicID: String, handoffText: String? = nil) -> RadioQueueItem {
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
      reason: "Programmed by backend.",
      handoffText: handoffText
    )
  }

  private func waitForPlayback(_ playbackController: MockPlaybackController, title: String) async {
    for _ in 0..<20 {
      if playbackController.currentTrack?.title == title {
        return
      }

      try? await Task.sleep(for: .milliseconds(25))
    }
  }

  private func waitForSpeech(_ playbackController: MockPlaybackController, text: String) async {
    for _ in 0..<20 {
      if playbackController.currentSpeech?.displayText == text {
        return
      }

      try? await Task.sleep(for: .milliseconds(25))
    }
  }
}

@MainActor
private final class MockPlaybackController: RadioPlaybackControlling {
  var onPlaybackFinished: ((PlaybackCompletionKind) -> Void)?
  var currentTrack: Track?
  var currentSpeech: RadioSpeechPlaybackSegment?

  func play(track: Track) {
    currentTrack = track
    currentSpeech = nil
  }

  func playSpeech(_ speech: RadioSpeechPlaybackSegment) {
    currentSpeech = speech
  }

  func stop() {
    currentTrack = nil
    currentSpeech = nil
  }

  func finish(_ kind: PlaybackCompletionKind) {
    onPlaybackFinished?(kind)
  }
}

private struct MockStationClient: RadioStationFetching {
  let result: Result<RadioStation, Error>

  func fetchCurrentStation() async throws -> RadioStation {
    try result.get()
  }
}

private actor MockMemoryStore: RadioMemoryStoring {
  var events: [RadioMemoryEvent] = []

  func buildContext() async throws -> RadioMemoryContext {
    RadioMemoryContext()
  }

  func record(_ event: RadioMemoryEvent) async throws {
    events.append(event)
  }

  func compressionRequest() async throws -> RadioMemoryCompressionRequest? {
    nil
  }

  func applyCompression(_ proposal: RadioCompressedMemory) async throws {}

  func clear() async throws {
    events = []
  }

  func snapshot() async throws -> RadioMemorySnapshot {
    RadioMemorySnapshot(
      eventCount: events.count,
      uncompressedEventCount: events.count,
      tasteSummary: "",
      avoidSummary: "",
      markdownPreview: ""
    )
  }
}
