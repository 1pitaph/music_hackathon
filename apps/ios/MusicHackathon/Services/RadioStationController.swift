import Foundation
import Observation

@MainActor
@Observable
final class RadioStationController {
  var station: RadioStation?
  var queue: [RadioQueueItem] = []
  var currentItem: RadioQueueItem?
  var stationTitle = "Airset Radio"
  var stationIntro = "Ready to stream the backend radio queue."
  var isLoadingStation = false
  var errorMessage: String?
  var memorySummaryText = "Local memory is ready."
  var memoryEventCount = 0

  @ObservationIgnored private let playbackController: PlaybackController
  @ObservationIgnored private let stationClient: any RadioStationFetching
  @ObservationIgnored private let memoryStore: any RadioMemoryStoring
  @ObservationIgnored private var history: [RadioQueueItem] = []

  init(
    playbackController: PlaybackController,
    stationClient: any RadioStationFetching = RadioStationClient(),
    memoryStore: any RadioMemoryStoring = RadioMemoryStore()
  ) {
    self.playbackController = playbackController
    self.stationClient = stationClient
    self.memoryStore = memoryStore

    playbackController.onTrackFinished = { [weak self] in
      Task { @MainActor in
        await self?.playNext(reason: .automaticCompletion)
      }
    }
  }

  var hasStationContent: Bool {
    currentItem != nil || !queue.isEmpty
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

  func startStation() async {
    if queue.isEmpty {
      await loadCurrentStation(playImmediately: true)
    } else {
      await playNext(reason: .stationStart)
    }
  }

  func playNext(reason: RadioAdvanceReason = .manual) async {
    if queue.isEmpty {
      await loadCurrentStation()
    }

    guard !queue.isEmpty else {
      if errorMessage == nil {
        errorMessage = "No tracks are ready from the backend station."
      }
      return
    }

    if let currentItem {
      await recordMemoryEvent(type: reason == .automaticCompletion ? "complete" : "skip", track: currentItem.track)
      history.append(currentItem)
    }

    let nextItem = queue.removeFirst()
    currentItem = nextItem
    errorMessage = nil
    await recordMemoryEvent(type: "play", track: nextItem.track)
    playbackController.play(track: nextItem.track)
  }

  func playPrevious() {
    guard let previousItem = history.popLast() else { return }

    if let currentItem {
      queue.insert(currentItem, at: 0)
    }

    currentItem = previousItem
    errorMessage = nil
    Task {
      try? await memoryStore.record(RadioMemoryEvent(type: "replay", track: previousItem.track))
      await refreshMemoryStatus()
    }
    playbackController.play(track: previousItem.track)
  }

  func refreshStation() async {
    await loadCurrentStation()
  }

  func loadCurrentStation(playImmediately: Bool = false) async {
    guard !isLoadingStation else { return }

    isLoadingStation = true
    errorMessage = nil

    do {
      await refreshMemoryStatus()
      let memoryContext = (try? await memoryStore.buildContext()) ?? RadioMemoryContext()
      let generationContext = RadioStationGenerationContext(
        seedTracks: stationSeeds(),
        catalogCandidates: stationCandidates(),
        memoryContext: memoryContext
      )
      let result = try await stationClient.generateStation(context: generationContext)
      let station = result.station
      self.station = station
      stationTitle = station.title
      stationIntro = station.subtitle
      currentItem = nil
      history = []
      queue = station.items
      await recordMemoryEvent(type: "station_generate", track: station.items.first?.track)

      if playImmediately {
        isLoadingStation = false
        await playNext(reason: .stationStart)
        return
      }
    } catch {
      self.station = nil
      currentItem = nil
      history = []
      queue = []
      stationTitle = "Airset Radio"
      stationIntro = "The backend station is not available right now."
      errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    isLoadingStation = false
  }

  func refreshMemoryStatus() async {
    guard let snapshot = try? await memoryStore.snapshot() else { return }
    memoryEventCount = snapshot.eventCount
    if !snapshot.tasteSummary.isEmpty {
      memorySummaryText = snapshot.tasteSummary
    } else if !snapshot.avoidSummary.isEmpty {
      memorySummaryText = snapshot.avoidSummary
    } else {
      memorySummaryText = snapshot.eventCount == 0
        ? "Local memory is ready."
        : "Learning from \(snapshot.eventCount) recent radio events."
    }
  }

  func clearMemory() async {
    try? await memoryStore.clear()
    await refreshMemoryStatus()
  }

  private func stationSeeds() -> [Track] {
    let currentTracks = stationTracks
    if !currentTracks.isEmpty {
      return Array(currentTracks.prefix(6))
    }
    return MockCatalog.featuredTracks
  }

  private func stationCandidates() -> [Track] {
    var candidates = MockCatalog.radioCandidates
    for track in stationTracks where !candidates.contains(where: { $0.radioIdentity == track.radioIdentity }) {
      candidates.append(track)
    }
    return candidates
  }

  private func recordMemoryEvent(type: String, track: Track?) async {
    try? await memoryStore.record(RadioMemoryEvent(type: type, track: track))
    await compressMemoryIfNeeded()
    await refreshMemoryStatus()
  }

  private func compressMemoryIfNeeded() async {
    guard let request = try? await memoryStore.compressionRequest() else { return }
    guard let proposal = try? await stationClient.compressMemory(request) else { return }
    try? await memoryStore.applyCompression(proposal)
  }
}

enum RadioAdvanceReason {
  case manual
  case stationStart
  case automaticCompletion
}
