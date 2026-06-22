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
  @ObservationIgnored private let contextBuilder: any RadioContextBuilding
  @ObservationIgnored private let recommendationEngine: RadioRecommendationEngine
  @ObservationIgnored private let narrationProvider: DJNarrationProvider
  @ObservationIgnored private let agentClient: any RadioAgentGenerating
  @ObservationIgnored private let stateStore: RadioStateStore
  @ObservationIgnored private var memory: RadioMemory

  init(
    playbackController: PlaybackController,
    libraryService: AppleMusicLibraryService = AppleMusicLibraryService(),
    contextBuilder: any RadioContextBuilding = RadioContextBuilder(),
    recommendationEngine: RadioRecommendationEngine = RadioRecommendationEngine(),
    narrationProvider: DJNarrationProvider = LocalDJNarrationProvider(),
    agentClient: any RadioAgentGenerating = RadioAgentClient(),
    stateStore: RadioStateStore = RadioStateStore()
  ) {
    self.playbackController = playbackController
    self.libraryService = libraryService
    self.contextBuilder = contextBuilder
    self.recommendationEngine = recommendationEngine
    self.narrationProvider = narrationProvider
    self.agentClient = agentClient
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

  func refreshRecommendations(
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

    let newQueue = await makeQueue(from: context, limit: 14)
    if keepExistingQueue {
      let existingKeys = Set(queue.map { $0.track.radioIdentity })
      queue.append(contentsOf: newQueue.filter { !existingKeys.contains($0.track.radioIdentity) })
    } else {
      queue = newQueue
    }

    isBuildingStation = false
  }

  private func makeQueue(from context: RadioRuntimeContext, limit: Int) async -> [RadioQueueItem] {
    do {
      let generation = try await agentClient.generateQueue(from: context, limit: limit)
      let agentQueue = try queue(from: generation, context: context)
      stationIntro = generation.stationIntro
      return agentQueue
    } catch {
      stationIntro = narrationProvider.stationIntro(for: context)
      return recommendationEngine.makeQueue(from: context, limit: limit)
    }
  }

  private func queue(
    from generation: RadioAgentGeneration,
    context: RadioRuntimeContext
  ) throws -> [RadioQueueItem] {
    guard !generation.items.isEmpty else {
      throw RadioAgentMappingError.emptyQueue
    }

    let candidates = candidateItems(for: context)
    var result: [RadioQueueItem] = []
    var seenKeys: Set<String> = []

    for generatedItem in generation.items {
      guard let candidate = candidates[generatedItem.radioIdentity] else {
        throw RadioAgentMappingError.unknownTrack(generatedItem.radioIdentity)
      }

      guard !seenKeys.contains(generatedItem.radioIdentity) else { continue }
      seenKeys.insert(generatedItem.radioIdentity)
      result.append(
        RadioQueueItem(
          track: candidate.track,
          source: candidate.source,
          score: generatedItem.score,
          reason: generatedItem.reason
        )
      )
    }

    guard !result.isEmpty else {
      throw RadioAgentMappingError.emptyQueue
    }

    return result
  }

  private func candidateItems(for context: RadioRuntimeContext) -> [String: RadioQueueItem] {
    var result: [String: RadioQueueItem] = [:]

    for seedTrack in context.seedTracks {
      let key = seedTrack.track.radioIdentity
      guard result[key] == nil else { continue }
      result[key] = RadioQueueItem(
        track: seedTrack.track,
        source: .playlist(id: seedTrack.playlistID, name: seedTrack.playlistName),
        score: 0,
        reason: ""
      )
    }

    for candidate in context.catalogCandidates where result[candidate.track.radioIdentity] == nil {
      result[candidate.track.radioIdentity] = candidate
    }

    return result
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

private enum RadioAgentMappingError: Error {
  case emptyQueue
  case unknownTrack(String)
}
