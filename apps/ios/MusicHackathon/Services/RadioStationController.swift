import Foundation
import MusicKit
import Observation

@MainActor
@Observable
final class RadioStationController {
  var playlists: [AppleMusicPlaylistSummary] = []
  var selectedPlaylistIDs: Set<String>
  var seedTracks: [RadioSeedTrack] = []
  var queue: [RadioQueueItem] = []
  var currentItem: RadioQueueItem?
  var tuning: RadioTuning
  var stationIntro = "Ready to tune your Apple Music library into radio."
  var isSyncingLibrary = false
  var isBuildingStation = false
  var errorMessage: String?

  @ObservationIgnored private let playbackController: PlaybackController
  @ObservationIgnored private let libraryService: AppleMusicLibraryService
  @ObservationIgnored private let contextBuilder: RadioContextBuilder
  @ObservationIgnored private let recommendationEngine: RadioRecommendationEngine
  @ObservationIgnored private let narrationProvider: DJNarrationProvider
  @ObservationIgnored private let stateStore: RadioStateStore
  @ObservationIgnored private var memory: RadioMemory

  init(
    playbackController: PlaybackController,
    libraryService: AppleMusicLibraryService = AppleMusicLibraryService(),
    contextBuilder: RadioContextBuilder = RadioContextBuilder(),
    recommendationEngine: RadioRecommendationEngine = RadioRecommendationEngine(),
    narrationProvider: DJNarrationProvider = LocalDJNarrationProvider(),
    stateStore: RadioStateStore = RadioStateStore()
  ) {
    self.playbackController = playbackController
    self.libraryService = libraryService
    self.contextBuilder = contextBuilder
    self.recommendationEngine = recommendationEngine
    self.narrationProvider = narrationProvider
    self.stateStore = stateStore

    let loadedMemory = stateStore.loadMemory()
    memory = loadedMemory
    selectedPlaylistIDs = loadedMemory.selectedPlaylistIDs
    tuning = loadedMemory.tuning

    playbackController.onTrackFinished = { [weak self] in
      Task { @MainActor in
        await self?.playNext()
      }
    }
  }

  var selectedPlaylists: [AppleMusicPlaylistSummary] {
    playlists.filter { selectedPlaylistIDs.contains($0.id) }
  }

  var hasSelectedPlaylists: Bool {
    !selectedPlaylistIDs.isEmpty
  }

  var canStartStation: Bool {
    !isBuildingStation && !selectedPlaylistIDs.isEmpty
  }

  var upNextItems: [RadioQueueItem] {
    Array(queue.prefix(5))
  }

  var stationTracks: [Track] {
    var tracks: [Track] = []
    if let currentItem {
      tracks.append(currentItem.track)
    }
    tracks.append(contentsOf: queue.map(\.track))
    return tracks
  }

  var stationTrackSignature: String {
    stationTracks.map(\.radioIdentity).joined(separator: "|")
  }

  var lastSyncText: String {
    guard let lastSyncDate = memory.lastSyncDate else {
      return "Not synced"
    }

    return lastSyncDate.formatted(date: .abbreviated, time: .shortened)
  }

  func refreshLibrary() async {
    guard !isSyncingLibrary else { return }
    guard MusicAuthorization.currentStatus == .authorized else {
      errorMessage = "Connect Apple Music before syncing playlists."
      return
    }

    isSyncingLibrary = true
    errorMessage = nil

    do {
      playlists = try await libraryService.playlists()
      selectedPlaylistIDs.formIntersection(Set(playlists.map(\.id)))
      memory.selectedPlaylistIDs = selectedPlaylistIDs
      memory.lastSyncDate = Date()
      stateStore.saveMemory(memory)
      try await loadSeedTracks()
    } catch {
      errorMessage = error.localizedDescription
    }

    isSyncingLibrary = false
  }

  func setSelectedPlaylistIDs(_ ids: Set<String>) async {
    selectedPlaylistIDs = ids
    memory.selectedPlaylistIDs = ids
    stateStore.saveMemory(memory)

    do {
      try await loadSeedTracks()
      if currentItem != nil || !queue.isEmpty {
        await refreshRecommendations(action: .tune)
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func startStation() async {
    guard canStartStation else { return }

    if playlists.isEmpty {
      await refreshLibrary()
    }

    if seedTracks.isEmpty {
      do {
        try await loadSeedTracks()
      } catch {
        errorMessage = error.localizedDescription
        return
      }
    }

    guard !seedTracks.isEmpty else {
      errorMessage = "Select playlists with playable Apple Music songs to start radio."
      return
    }

    await refreshRecommendations(action: .start)
    await playNext()
  }

  func playNext() async {
    if queue.isEmpty {
      await refreshRecommendations(action: .refresh)
    }

    guard !queue.isEmpty else {
      errorMessage = "No recommendations are ready yet."
      return
    }

    let nextItem = queue.removeFirst()
    currentItem = nextItem
    errorMessage = nil
    memory.recordPlay(trackKey: nextItem.track.radioIdentity)
    stateStore.saveMemory(memory)
    playbackController.play(track: nextItem.track)

    if queue.count < 4 {
      await refreshRecommendations(action: .refresh, keepExistingQueue: true)
    }
  }

  func skipCurrent() async {
    if let currentItem {
      memory.recordSkip(trackKey: currentItem.track.radioIdentity)
      stateStore.saveMemory(memory)
    }

    await playNext()
  }

  func likeCurrent() {
    guard let currentItem else { return }
    memory.recordLike(trackKey: currentItem.track.radioIdentity)
    stateStore.saveMemory(memory)
    queue = queue.map { item in
      item.track.radioIdentity == currentItem.track.radioIdentity
        ? RadioQueueItem(track: item.track, source: item.source, score: item.score + 12, reason: "Boosted because you liked this lane.")
        : item
    }
  }

  func dislikeCurrent() {
    guard let currentItem else { return }
    memory.recordDislike(trackKey: currentItem.track.radioIdentity)
    stateStore.saveMemory(memory)
  }

  func refreshRecommendations() async {
    await refreshRecommendations(action: .refresh)
  }

  func setTuning(_ tuning: RadioTuning) async {
    self.tuning = tuning.normalized
    memory.tuning = self.tuning
    stateStore.saveMemory(memory)
    await refreshRecommendations(action: .tune, keepExistingQueue: currentItem != nil)
  }

  private func refreshRecommendations(
    action: RadioRuntimeAction,
    keepExistingQueue: Bool = false
  ) async {
    guard !seedTracks.isEmpty else { return }
    guard !isBuildingStation else { return }

    isBuildingStation = true
    errorMessage = nil

    let context = await contextBuilder.build(
      seedTracks: seedTracks,
      memory: memory,
      tuning: tuning,
      action: action
    )
    stationIntro = narrationProvider.stationIntro(for: context)

    let newQueue = recommendationEngine.makeQueue(from: context, limit: 14)
    if keepExistingQueue {
      let existingKeys = Set(queue.map { $0.track.radioIdentity })
      queue.append(contentsOf: newQueue.filter { !existingKeys.contains($0.track.radioIdentity) })
    } else {
      queue = newQueue
    }

    isBuildingStation = false
  }

  private func loadSeedTracks() async throws {
    let selected = selectedPlaylists
    guard !selected.isEmpty else {
      seedTracks = []
      queue = []
      return
    }

    seedTracks = try await libraryService.seedTracks(for: selected)
  }
}
