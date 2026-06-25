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

  func testLoadCurrentStationEnrichesMissingArtworkAndFiltersFailures() async {
    let station = makeStation(items: [
      makeQueueItem(title: "Recovered", appleMusicID: "recovered", includeArtwork: false),
      makeQueueItem(title: "Dropped", appleMusicID: "dropped", includeArtwork: false)
    ])
    let controller = RadioStationController(
      playbackController: MockPlaybackController(),
      stationClient: MockStationClient(result: .success(station)),
      memoryStore: MockMemoryStore(),
      artworkEnricher: FakeArtworkEnricher(
        artworkURLsByTitle: ["Recovered": URL(string: "https://example.com/recovered.jpg")!]
      )
    )

    await controller.loadCurrentStation()

    XCTAssertEqual(controller.queue.map(\.track.title), ["Recovered"])
    XCTAssertEqual(controller.queue.first?.track.artworkURL?.absoluteString, "https://example.com/recovered.jpg")
    XCTAssertNil(controller.errorMessage)
  }

  func testLoadCurrentStationFailsWhenArtworkFilteringEmptiesQueue() async {
    let station = makeStation(items: [
      makeQueueItem(title: "No Cover", appleMusicID: "no-cover", includeArtwork: false)
    ])
    let controller = RadioStationController(
      playbackController: MockPlaybackController(),
      stationClient: MockStationClient(result: .success(station)),
      memoryStore: MockMemoryStore(),
      artworkEnricher: FakeArtworkEnricher(artworkURLsByTitle: [:])
    )

    await controller.loadCurrentStation()

    XCTAssertNil(controller.station)
    XCTAssertTrue(controller.queue.isEmpty)
    XCTAssertEqual(controller.stationIntro, L10n.tr("radio.backendUnavailable"))
    XCTAssertEqual(controller.errorMessage, L10n.tr("radio.error.noArtworkTracks"))
  }

  func testLoadCurrentStationSendsSelectedHostSpeaker() async {
    let station = makeStation(items: [
      makeQueueItem(title: "One", appleMusicID: "one")
    ])
    let stationClient = CapturingStationClient(station: station)
    let controller = RadioStationController(
      playbackController: MockPlaybackController(),
      stationClient: stationClient,
      memoryStore: MockMemoryStore(),
      hostSpeakerIDProvider: { "zh_female_shuangkuaisisi_moon_bigtts" },
      speechLanguageProvider: { .chinese }
    )

    await controller.loadCurrentStation()

    XCTAssertEqual(stationClient.capturedContext?.speechAudio.provider, "volcengine")
    XCTAssertEqual(stationClient.capturedContext?.speechAudio.speaker, "zh_female_shuangkuaisisi_moon_bigtts")
    XCTAssertEqual(stationClient.capturedContext?.speechAudio.resourceId, "seed-tts-1.0")
    XCTAssertEqual(stationClient.capturedContext?.speechLanguage, "zh-CN")
    XCTAssertEqual(stationClient.capturedContext?.speechAudio.explicitLanguage, "zh-CN")
  }

  func testLoadAndContinueStationSendSelectedSpeechLanguage() async {
    let stationClient = SequencedStationClient(results: [
      .success(makeResult(titles: ["One", "Two"])),
      .success(makeResult(titles: ["Three", "Four"]))
    ])
    let controller = RadioStationController(
      playbackController: MockPlaybackController(),
      stationClient: stationClient,
      memoryStore: MockMemoryStore(),
      speechLanguageProvider: { .english }
    )

    await controller.loadCurrentStation()
    _ = await controller.extendCurrentStation()

    XCTAssertEqual(stationClient.contexts.map(\.action), ["start", "continue"])
    XCTAssertEqual(stationClient.contexts.map(\.speechLanguage), ["en-US", "en-US"])
    XCTAssertEqual(
      stationClient.contexts.map(\.speechAudio.speaker),
      ["en_female_lauren_moon_bigtts", "en_female_lauren_moon_bigtts"]
    )
    XCTAssertEqual(stationClient.contexts.map(\.speechAudio.explicitLanguage), ["en-US", "en-US"])
  }

  func testChineseSpeechDurationEstimateUsesCharactersAndPauses() {
    let chineseText = "嗯，刚才那首歌把气氛慢慢铺开了。下一首我们稍微往前走一点，听听新的颜色。"
    let englishText = "Next up is Two."

    XCTAssertGreaterThan(PlaybackController.estimatedSpeechDuration(for: chineseText), 5.0)
    XCTAssertLessThan(PlaybackController.estimatedSpeechDuration(for: englishText), 3.0)
  }

  func testSmoothedVolumeUsesMonotonicSmoothstepCurve() {
    let start = PlaybackController.smoothedVolume(startVolume: 1.0, targetVolume: 0.2, progress: 0)
    let middle = PlaybackController.smoothedVolume(startVolume: 1.0, targetVolume: 0.2, progress: 0.5)
    let end = PlaybackController.smoothedVolume(startVolume: 1.0, targetVolume: 0.2, progress: 1)

    XCTAssertEqual(start, 1.0, accuracy: 0.0001)
    XCTAssertEqual(middle, 0.6, accuracy: 0.0001)
    XCTAssertEqual(end, 0.2, accuracy: 0.0001)
    XCTAssertGreaterThan(start, middle)
    XCTAssertGreaterThan(middle, end)
  }

  func testLoadCurrentStationUsesLibraryTracksForGenerationCandidates() async {
    let station = makeStation(items: [
      makeQueueItem(title: "Generated", appleMusicID: "generated")
    ])
    let stationClient = CapturingStationClient(station: station)
    let libraryTrack = makeTrack(title: "Library Candidate", appleMusicID: "library-candidate")
    let controller = RadioStationController(
      playbackController: MockPlaybackController(),
      stationClient: stationClient,
      memoryStore: MockMemoryStore(),
      libraryTrackProvider: { [libraryTrack] }
    )

    await controller.loadCurrentStation()

    XCTAssertEqual(stationClient.capturedContext?.seedTracks.first?.title, "Library Candidate")
    XCTAssertEqual(stationClient.capturedContext?.catalogCandidates.first?.appleMusicID, "library-candidate")
  }

  func testRefreshSpeechVoicesStoresCatalog() async {
    let stationClient = CapturingStationClient(
      station: makeStation(items: [makeQueueItem(title: "One", appleMusicID: "one")]),
      voices: RadioSpeechVoiceCatalog(
        defaultSpeaker: "voice-a",
        resourceId: "seed-tts-1.0",
        model: "seed-tts-1.0",
        voices: [
          RadioSpeechVoice(
            id: "voice-a",
            name: "Voice A",
            language: "zh-cn",
            gender: "female",
            style: "Host",
            resourceId: "seed-tts-1.0",
            model: "seed-tts-1.0"
          )
        ]
      )
    )
    let controller = RadioStationController(
      playbackController: MockPlaybackController(),
      stationClient: stationClient,
      memoryStore: MockMemoryStore()
    )

    await controller.refreshSpeechVoices()

    XCTAssertEqual(controller.speechVoiceCatalog?.defaultSpeaker, "voice-a")
    XCTAssertEqual(controller.speechVoiceCatalog?.voices.first?.name, "Voice A")
    XCTAssertNil(controller.speechVoicesErrorMessage)
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
    XCTAssertEqual(playbackController.preparedUpcomingTrack?.title, "Two")
    XCTAssertEqual(playbackController.preparedUpcomingPolicy, .fullSongPreferred)
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
    XCTAssertEqual(controller.stationIntro, L10n.tr("radio.backendUnavailable"))
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

  func testFixedLocalStationDoesNotPrefetchBackendExtension() async {
    let playbackController = MockPlaybackController()
    let stationClient = SequencedStationClient(results: [
      .success(makeResult(titles: ["Backend Extension"]))
    ])
    let controller = RadioStationController(
      playbackController: playbackController,
      stationClient: stationClient,
      memoryStore: MockMemoryStore()
    )
    let localStation = makeStation(
      items: [
        makeQueueItem(title: "One", appleMusicID: "one"),
        makeQueueItem(title: "Two", appleMusicID: "two"),
        makeQueueItem(title: "Three", appleMusicID: "three")
      ],
      allowsAutoExtension: false
    )

    await controller.loadLocalStation(localStation, playImmediately: true)
    await waitForPlayback(playbackController, title: "One")

    XCTAssertEqual(controller.queue.map(\.track.title), ["Two", "Three"])
    XCTAssertTrue(stationClient.contexts.isEmpty)
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
    XCTAssertEqual(playbackController.preparedUpcomingTrack?.title, "One")
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
    XCTAssertEqual(playbackController.preparedUpcomingTrack?.title, "Two")

    playbackController.finish(.speech)
    await waitForPlayback(playbackController, title: "Two")

    XCTAssertEqual(controller.currentItem?.track.title, "Two")
    XCTAssertTrue(controller.queue.isEmpty)
  }

  func testTransitionWindowOverlaysSpeechAndStartsNextTrackAtAdvancePoint() async {
    let station = makeStation(
      items: [
        makeQueueItem(title: "One", appleMusicID: "one", includePreview: true),
        makeQueueItem(title: "Two", appleMusicID: "two", includePreview: true)
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

    playbackController.triggerTransitionWindow()
    await waitForSpeech(playbackController, text: "Next up is Two.")

    XCTAssertNil(controller.currentItem)
    XCTAssertEqual(controller.queue.map(\.track.title), ["Two"])
    XCTAssertEqual(playbackController.lastSpeechMode, .transitionOverlay)
    XCTAssertEqual(playbackController.preparedUpcomingTrack?.title, "Two")
    XCTAssertEqual(playbackController.preparedUpcomingPolicy, .mixablePreferred)

    playbackController.triggerSpeechAdvancePoint()
    await waitForPlayback(playbackController, title: "Two")

    XCTAssertEqual(controller.currentItem?.track.title, "Two")
    XCTAssertTrue(controller.queue.isEmpty)
    XCTAssertEqual(playbackController.lastTrackPolicy, .mixablePreferred)
    XCTAssertTrue(playbackController.lastPreservesSpeech)

    playbackController.finish(.speech)

    XCTAssertEqual(controller.currentItem?.track.title, "Two")
    XCTAssertNil(playbackController.currentSpeech)
  }

  func testTransitionSpeechCompletionBeforeAdvancePointStartsPendingNextTrack() async {
    let station = makeStation(
      items: [
        makeQueueItem(title: "One", appleMusicID: "one", includePreview: true),
        makeQueueItem(title: "Two", appleMusicID: "two", includePreview: true)
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
    playbackController.triggerTransitionWindow()
    await waitForSpeech(playbackController, text: "Next up is Two.")

    playbackController.finish(.speech)
    await waitForPlayback(playbackController, title: "Two")

    XCTAssertEqual(controller.currentItem?.track.title, "Two")
    XCTAssertFalse(playbackController.lastPreservesSpeech)
  }

  func testAppleMusicOnlyTransitionKeepsSerialSpeechFlow() async {
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
    playbackController.triggerTransitionWindow()

    XCTAssertEqual(controller.currentItem?.track.title, "One")
    XCTAssertNil(playbackController.currentSpeech)

    playbackController.finish(.track)
    await waitForSpeech(playbackController, text: "Next up is Two.")

    XCTAssertEqual(playbackController.lastSpeechMode, .standalone)
    XCTAssertNil(controller.currentItem)
    XCTAssertEqual(controller.queue.map(\.track.title), ["Two"])
    XCTAssertEqual(playbackController.preparedUpcomingTrack?.title, "Two")

    playbackController.finish(.speech)
    await waitForPlayback(playbackController, title: "Two")

    XCTAssertEqual(controller.currentItem?.track.title, "Two")
  }

  func testAutomaticCompletionUsesHandoffTextWhenSpeechIsMissing() async {
    let station = makeStation(
      items: [
        makeQueueItem(title: "One", appleMusicID: "one"),
        makeQueueItem(title: "Two", appleMusicID: "two", handoffText: "Next up is Two.")
      ]
    )
    let playbackController = MockPlaybackController()
    let controller = RadioStationController(
      playbackController: playbackController,
      stationClient: MockStationClient(result: .success(station)),
      memoryStore: MockMemoryStore()
    )

    await controller.startStation()
    playbackController.finish(.track)
    await waitForSpeech(playbackController, text: "Next up is Two.")

    XCTAssertEqual(playbackController.currentSpeech?.displayText, "Next up is Two.")

    playbackController.finish(.speech)
    await waitForPlayback(playbackController, title: "Two")

    XCTAssertEqual(controller.currentItem?.track.title, "Two")
  }

  func testPlaybackFailureAutoSkipsToNextTrackWithoutAddingFailedTrackToHistory() async {
    let memoryStore = MockMemoryStore()
    let station = makeStation(items: [
      makeQueueItem(title: "One", appleMusicID: "one"),
      makeQueueItem(title: "Two", appleMusicID: "two")
    ])
    let playbackController = MockPlaybackController()
    let controller = RadioStationController(
      playbackController: playbackController,
      stationClient: MockStationClient(result: .success(station)),
      memoryStore: memoryStore
    )

    await controller.startStation()
    await waitForPlayback(playbackController, title: "One")

    playbackController.failCurrent(phase: "apple_music_start")
    await waitForPlayback(playbackController, title: "Two")

    XCTAssertEqual(controller.currentItem?.track.title, "Two")
    XCTAssertTrue(controller.queue.isEmpty)
    XCTAssertEqual(playbackController.currentTrack?.title, "Two")

    controller.playPrevious()

    XCTAssertEqual(controller.currentItem?.track.title, "Two")
    XCTAssertTrue(controller.queue.isEmpty)
    XCTAssertEqual(playbackController.currentTrack?.title, "Two")

    let eventTypes = await memoryStore.eventTypes()
    XCTAssertTrue(eventTypes.contains("playback_failed"))
    XCTAssertFalse(eventTypes.contains("skip"))
  }

  func testPlaybackFailureWithEmptyQueueSurfacesErrorWithoutCrash() async {
    let stationClient = SequencedStationClient(results: [
      .success(makeResult(titles: ["One"])),
      .failure(URLError(.cannotConnectToHost)),
      .failure(URLError(.cannotConnectToHost))
    ])
    let playbackController = MockPlaybackController()
    let controller = RadioStationController(
      playbackController: playbackController,
      stationClient: stationClient,
      memoryStore: MockMemoryStore()
    )

    await controller.startStation()
    await waitForPlayback(playbackController, title: "One")
    await waitForExtensionError(controller)

    playbackController.failCurrent(phase: "resolve_failed")
    await waitForControllerError(controller)

    XCTAssertNil(controller.currentItem)
    XCTAssertTrue(controller.queue.isEmpty)
    XCTAssertNotNil(controller.errorMessage)
  }

  func testManualNextPlaysTransitionSpeechBeforeNextTrack() async {
    let memoryStore = MockMemoryStore()
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
      memoryStore: memoryStore
    )

    await controller.startStation()
    await controller.playNext(reason: .manual)
    await waitForSpeech(playbackController, text: "Next up is Two.")

    XCTAssertEqual(playbackController.currentSpeech?.displayText, "Next up is Two.")
    XCTAssertNil(controller.currentItem)
    XCTAssertEqual(controller.queue.map(\.track.title), ["Two"])
    XCTAssertEqual(playbackController.preparedUpcomingTrack?.title, "Two")

    playbackController.finish(.speech)
    await waitForPlayback(playbackController, title: "Two")

    XCTAssertEqual(controller.currentItem?.track.title, "Two")
    XCTAssertTrue(controller.queue.isEmpty)
    let eventTypes = await memoryStore.eventTypes()
    XCTAssertTrue(eventTypes.contains("skip"))
  }

  func testManualNextUsesOverlayTransitionWhenTracksAreMixable() async {
    let memoryStore = MockMemoryStore()
    let station = makeStation(
      items: [
        makeQueueItem(title: "One", appleMusicID: "one", includePreview: true),
        makeQueueItem(title: "Two", appleMusicID: "two", includePreview: true)
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
      memoryStore: memoryStore
    )

    await controller.startStation()
    await controller.playNext(reason: .manual)
    await waitForSpeech(playbackController, text: "Next up is Two.")

    XCTAssertEqual(playbackController.lastSpeechMode, .transitionOverlay)
    XCTAssertNil(controller.currentItem)
    XCTAssertEqual(controller.queue.map(\.track.title), ["Two"])
    XCTAssertEqual(playbackController.preparedUpcomingTrack?.title, "Two")
    XCTAssertEqual(playbackController.preparedUpcomingPolicy, .mixablePreferred)

    playbackController.triggerSpeechAdvancePoint()
    await waitForPlayback(playbackController, title: "Two")

    XCTAssertEqual(controller.currentItem?.track.title, "Two")
    XCTAssertTrue(playbackController.lastPreservesSpeech)
    let eventTypes = await memoryStore.eventTypes()
    XCTAssertTrue(eventTypes.contains("skip"))
  }

  func testDiscoverStationBuildsSpeechForLocalPlayback() {
    let station = DiscoverStation.mockStations[0].radioStation()

    XCTAssertEqual(station.speech?.stationIntro?.targetItemId, station.items.first?.id)
    XCTAssertFalse(station.speech?.stationIntro?.displayText.isEmpty ?? true)
    XCTAssertEqual(station.speech?.betweenTracks.count, max(station.items.count - 1, 0))
  }

  func testStartStationPrefetchesWhenQueueFallsToThresholdAndAppends() async {
    let stationClient = SequencedStationClient(results: [
      .success(
        RadioStationResult(
          station: makeStation(items: [
            makeQueueItem(title: "One", appleMusicID: "one"),
            makeQueueItem(title: "Two", appleMusicID: "two"),
            makeQueueItem(title: "Three", appleMusicID: "three")
          ]),
          stationSessionID: "session-1",
          continuationCursor: "cursor-1"
        )
      ),
      .success(
        RadioStationResult(
          station: makeStation(items: [
            makeQueueItem(title: "Four", appleMusicID: "four"),
            makeQueueItem(title: "Five", appleMusicID: "five")
          ]),
          stationSessionID: "session-2",
          continuationCursor: "cursor-2"
        )
      )
    ])
    let playbackController = MockPlaybackController()
    let controller = RadioStationController(
      playbackController: playbackController,
      stationClient: stationClient,
      memoryStore: MockMemoryStore()
    )

    await controller.startStation()
    await waitForQueue(controller, titles: ["Two", "Three", "Four", "Five"])

    XCTAssertEqual(controller.currentItem?.track.title, "One")
    XCTAssertEqual(playbackController.currentTrack?.title, "One")
    XCTAssertEqual(stationClient.contexts.map(\.action), ["start", "continue"])
    XCTAssertEqual(stationClient.contexts.last?.stationID, "station-1")
    XCTAssertEqual(stationClient.contexts.last?.stationSessionID, "session-1")
    XCTAssertEqual(stationClient.contexts.last?.continuationCursor, "cursor-1")
    XCTAssertEqual(stationClient.contexts.last?.currentTrackKey, "appleMusic:one")
    XCTAssertEqual(stationClient.contexts.last?.queuedTrackKeys, ["appleMusic:two", "appleMusic:three"])
    XCTAssertNil(controller.extensionErrorMessage)
  }

  func testAutomaticCompletionContinuesIntoAppendedBatch() async {
    let stationClient = SequencedStationClient(results: [
      .success(makeResult(titles: ["One", "Two"])),
      .success(makeResult(titles: ["Three"]))
    ])
    let playbackController = MockPlaybackController()
    let controller = RadioStationController(
      playbackController: playbackController,
      stationClient: stationClient,
      memoryStore: MockMemoryStore()
    )

    await controller.startStation()
    await waitForQueue(controller, titles: ["Two", "Three"])

    playbackController.finish(.track)
    await waitForPlayback(playbackController, title: "Two")
    playbackController.finish(.track)
    await waitForPlayback(playbackController, title: "Three")

    XCTAssertEqual(controller.currentItem?.track.title, "Three")
    XCTAssertTrue(controller.queue.isEmpty)
  }

  func testStationExtensionPreservesPlayedIntroState() async {
    let intro = RadioSpeech(
      stationIntro: RadioStationIntroCopy(
        text: "Welcome to Airset.",
        displayText: "Welcome to Airset.",
        targetItemId: "one"
      )
    )
    let stationClient = SequencedStationClient(results: [
      .success(
        RadioStationResult(
          station: makeStation(
            items: [
              makeQueueItem(title: "One", appleMusicID: "one"),
              makeQueueItem(title: "Two", appleMusicID: "two"),
              makeQueueItem(title: "Three", appleMusicID: "three")
            ],
            speech: intro
          )
        )
      ),
      .success(makeResult(titles: ["Four"]))
    ])
    let playbackController = MockPlaybackController()
    let controller = RadioStationController(
      playbackController: playbackController,
      stationClient: stationClient,
      memoryStore: MockMemoryStore()
    )

    await controller.startStation()
    XCTAssertEqual(playbackController.currentSpeech?.displayText, "Welcome to Airset.")

    playbackController.finish(.speech)
    await waitForPlayback(playbackController, title: "One")
    await waitForQueue(controller, titles: ["Two", "Three", "Four"])
    playbackController.finish(.track)
    await waitForPlayback(playbackController, title: "Two")

    XCTAssertNil(playbackController.currentSpeech)
    XCTAssertEqual(controller.currentItem?.track.title, "Two")
  }

  func testStationExtensionFiltersDuplicateTracks() async {
    let stationClient = SequencedStationClient(results: [
      .success(makeResult(titles: ["One", "Two", "Three"])),
      .success(
        RadioStationResult(
          station: makeStation(items: [
            makeQueueItem(title: "Two", appleMusicID: "two"),
            makeQueueItem(title: "Four", appleMusicID: "four"),
            makeQueueItem(title: "Four Again", appleMusicID: "four")
          ])
        )
      )
    ])
    let playbackController = MockPlaybackController()
    let controller = RadioStationController(
      playbackController: playbackController,
      stationClient: stationClient,
      memoryStore: MockMemoryStore()
    )

    await controller.startStation()
    await waitForQueue(controller, titles: ["Two", "Three", "Four"])

    XCTAssertEqual(controller.queue.map(\.track.title), ["Two", "Three", "Four"])
  }

  func testStationExtensionFailureKeepsExistingQueue() async {
    let stationClient = SequencedStationClient(results: [
      .success(makeResult(titles: ["One", "Two", "Three"])),
      .failure(URLError(.cannotConnectToHost))
    ])
    let playbackController = MockPlaybackController()
    let controller = RadioStationController(
      playbackController: playbackController,
      stationClient: stationClient,
      memoryStore: MockMemoryStore()
    )

    await controller.startStation()
    await waitForExtensionError(controller)

    XCTAssertEqual(controller.currentItem?.track.title, "One")
    XCTAssertEqual(controller.queue.map(\.track.title), ["Two", "Three"])
    XCTAssertNil(controller.errorMessage)
    XCTAssertNotNil(controller.extensionErrorMessage)
  }

  func testEmptyQueueExtensionFailureShowsErrorOnlyWhenNoTrackIsReady() async {
    let stationClient = SequencedStationClient(results: [
      .success(makeResult(titles: ["One"])),
      .failure(URLError(.cannotConnectToHost)),
      .failure(URLError(.cannotConnectToHost))
    ])
    let playbackController = MockPlaybackController()
    let controller = RadioStationController(
      playbackController: playbackController,
      stationClient: stationClient,
      memoryStore: MockMemoryStore()
    )

    await controller.startStation()
    await waitForExtensionError(controller)
    playbackController.finish(.track)
    await waitForControllerError(controller)

    XCTAssertNil(controller.currentItem)
    XCTAssertTrue(controller.queue.isEmpty)
    XCTAssertNotNil(controller.errorMessage)
  }

  func testRefreshStationStartsNewStationInsteadOfContinuing() async {
    let stationClient = SequencedStationClient(results: [
      .success(makeResult(titles: ["One", "Two"])),
      .success(makeResult(titles: ["Fresh"]))
    ])
    let controller = RadioStationController(
      playbackController: MockPlaybackController(),
      stationClient: stationClient,
      memoryStore: MockMemoryStore()
    )

    await controller.loadCurrentStation()
    await controller.refreshStation()

    XCTAssertEqual(controller.queue.map(\.track.title), ["Fresh"])
    XCTAssertEqual(stationClient.contexts.map(\.action), ["start", "start"])
  }

  func testRefreshStationClearsPreparedUpcomingTrack() async {
    let stationClient = SequencedStationClient(results: [
      .success(makeResult(titles: ["One", "Two"])),
      .success(makeResult(titles: ["Fresh"]))
    ])
    let playbackController = MockPlaybackController()
    let controller = RadioStationController(
      playbackController: playbackController,
      stationClient: stationClient,
      memoryStore: MockMemoryStore()
    )

    await controller.startStation()
    await waitForPlayback(playbackController, title: "One")
    XCTAssertEqual(playbackController.preparedUpcomingTrack?.title, "Two")

    await controller.refreshStation()

    XCTAssertNil(playbackController.preparedUpcomingTrack)
    XCTAssertEqual(controller.queue.map(\.track.title), ["Fresh"])
  }

  private func makeStation(
    items: [RadioQueueItem],
    speech: RadioSpeech? = nil,
    allowsAutoExtension: Bool = true
  ) -> RadioStation {
    RadioStation(
      id: "station-1",
      title: "Backend Radio",
      subtitle: "Complete backend station.",
      items: items,
      speech: speech,
      allowsAutoExtension: allowsAutoExtension
    )
  }

  private func makeResult(titles: [String]) -> RadioStationResult {
    RadioStationResult(
      station: makeStation(
        items: titles.map { title in
          makeQueueItem(title: title, appleMusicID: title.lowercased())
        }
      )
    )
  }

  private func makeQueueItem(
    title: String,
    appleMusicID: String,
    handoffText: String? = nil,
    includeArtwork: Bool = true,
    includePreview: Bool = false
  ) -> RadioQueueItem {
    RadioQueueItem(
      id: appleMusicID,
      track: makeTrack(
        title: title,
        appleMusicID: appleMusicID,
        includeArtwork: includeArtwork,
        includePreview: includePreview
      ),
      sourceTitle: "Backend",
      reason: "Programmed by backend.",
      handoffText: handoffText
    )
  }

  private func makeTrack(
    title: String,
    appleMusicID: String,
    includeArtwork: Bool = true,
    includePreview: Bool = false
  ) -> Track {
    Track(
      title: title,
      artist: "Artist",
      album: "Album",
      mood: "Radio",
      duration: 210,
      artworkSystemName: "music.note",
      artworkURL: includeArtwork ? URL(string: "https://example.com/\(appleMusicID).jpg") : nil,
      previewURL: includePreview ? URL(string: "https://example.com/\(appleMusicID).m4a") : nil,
      appleMusicID: includePreview ? nil : appleMusicID
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

  private func waitForQueue(_ controller: RadioStationController, titles: [String]) async {
    for _ in 0..<40 {
      if controller.queue.map(\.track.title) == titles {
        return
      }

      try? await Task.sleep(for: .milliseconds(25))
    }
  }

  private func waitForExtensionError(_ controller: RadioStationController) async {
    for _ in 0..<40 {
      if controller.extensionErrorMessage != nil {
        return
      }

      try? await Task.sleep(for: .milliseconds(25))
    }
  }

  private func waitForControllerError(_ controller: RadioStationController) async {
    for _ in 0..<40 {
      if controller.errorMessage != nil {
        return
      }

      try? await Task.sleep(for: .milliseconds(25))
    }
  }
}

@MainActor
private final class MockPlaybackController: RadioPlaybackControlling {
  var onPlaybackFinished: ((PlaybackCompletionKind) -> Void)?
  var onPlaybackFailed: ((PlaybackFailureContext) -> Void)?
  var onTrackTransitionWindowReached: (() -> Void)?
  var onSpeechAdvancePointReached: (() -> Void)?
  var currentTrack: Track?
  var currentSpeech: RadioSpeechPlaybackSegment?
  var lastTrackPolicy: RadioTrackPlaybackPolicy?
  var lastPreservesSpeech = false
  var lastSpeechMode: RadioSpeechPlaybackMode?
  var preparedUpcomingTrack: Track?
  var preparedUpcomingPolicy: RadioTrackPlaybackPolicy?

  func prepareUpcomingTrack(_ track: Track?, policy: RadioTrackPlaybackPolicy) {
    preparedUpcomingTrack = track
    preparedUpcomingPolicy = policy
  }

  func play(track: Track) {
    play(track: track, policy: .fullSongPreferred, preservesSpeech: false)
  }

  func play(track: Track, policy: RadioTrackPlaybackPolicy, preservesSpeech: Bool) {
    currentTrack = track
    lastTrackPolicy = policy
    lastPreservesSpeech = preservesSpeech
    if !preservesSpeech {
      currentSpeech = nil
    }
  }

  func playSpeech(_ speech: RadioSpeechPlaybackSegment) {
    playSpeech(speech, mode: .standalone)
  }

  func playSpeech(_ speech: RadioSpeechPlaybackSegment, mode: RadioSpeechPlaybackMode) {
    currentSpeech = speech
    lastSpeechMode = mode
  }

  func stop() {
    currentTrack = nil
    currentSpeech = nil
  }

  func finish(_ kind: PlaybackCompletionKind) {
    if kind == .speech {
      currentSpeech = nil
    }
    onPlaybackFinished?(kind)
  }

  func triggerTransitionWindow() {
    onTrackTransitionWindowReached?()
  }

  func triggerSpeechAdvancePoint() {
    onSpeechAdvancePointReached?()
  }

  func failCurrent(phase: String) {
    guard let currentTrack else { return }
    onPlaybackFailed?(
      PlaybackFailureContext(
        track: currentTrack,
        phase: phase,
        message: "Mock playback failed."
      )
    )
  }
}

private struct MockStationClient: RadioStationFetching {
  let result: Result<RadioStation, Error>

  func fetchCurrentStation() async throws -> RadioStation {
    try result.get()
  }
}

private struct FakeArtworkEnricher: TrackArtworkEnriching {
  let artworkURLsByTitle: [String: URL]

  func enrichArtwork(_ tracks: [Track]) async -> [Track] {
    tracks.map { track in
      guard !track.hasRealArtwork, let artworkURL = artworkURLsByTitle[track.title] else {
        return track
      }
      return track.replacingArtworkURL(artworkURL)
    }
  }
}

private final class SequencedStationClient: RadioStationFetching {
  var results: [Result<RadioStationResult, Error>]
  var contexts: [RadioStationGenerationContext] = []

  init(results: [Result<RadioStationResult, Error>]) {
    self.results = results
  }

  func fetchCurrentStation() async throws -> RadioStation {
    try nextResult().station
  }

  func generateStation(context: RadioStationGenerationContext) async throws -> RadioStationResult {
    contexts.append(context)
    return try nextResult()
  }

  private func nextResult() throws -> RadioStationResult {
    guard !results.isEmpty else {
      throw URLError(.badServerResponse)
    }

    return try results.removeFirst().get()
  }
}

private extension Track {
  func replacingArtworkURL(_ artworkURL: URL?) -> Track {
    Track(
      id: id,
      title: title,
      artist: artist,
      album: album,
      mood: mood,
      duration: duration,
      artworkSystemName: artworkSystemName,
      artworkURL: artworkURL,
      previewURL: previewURL,
      appleMusicID: appleMusicID,
      isExplicit: isExplicit,
      playlistName: playlistName,
      source: source,
      sourceLane: sourceLane,
      sourceScore: sourceScore,
      reasonSignals: reasonSignals
    )
  }
}

private final class CapturingStationClient: RadioStationFetching {
  let station: RadioStation
  let voices: RadioSpeechVoiceCatalog
  var capturedContext: RadioStationGenerationContext?
  var capturedContexts: [RadioStationGenerationContext] = []

  init(station: RadioStation, voices: RadioSpeechVoiceCatalog = .fallback) {
    self.station = station
    self.voices = voices
  }

  func fetchCurrentStation() async throws -> RadioStation {
    station
  }

  func generateStation(context: RadioStationGenerationContext) async throws -> RadioStationResult {
    capturedContext = context
    capturedContexts.append(context)
    return RadioStationResult(station: station)
  }

  func fetchSpeechVoices() async throws -> RadioSpeechVoiceCatalog {
    voices
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

  func eventTypes() -> [String] {
    events.map(\.type)
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
