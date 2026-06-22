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

  @ObservationIgnored private let playbackController: PlaybackController
  @ObservationIgnored private let stationClient: any RadioStationFetching
  @ObservationIgnored private var history: [RadioQueueItem] = []

  init(
    playbackController: PlaybackController,
    stationClient: any RadioStationFetching = RadioStationClient()
  ) {
    self.playbackController = playbackController
    self.stationClient = stationClient

    playbackController.onTrackFinished = { [weak self] in
      Task { @MainActor in
        await self?.playNext()
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
      await playNext()
    }
  }

  func playNext() async {
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
      history.append(currentItem)
    }

    let nextItem = queue.removeFirst()
    currentItem = nextItem
    errorMessage = nil
    playbackController.play(track: nextItem.track)
  }

  func playPrevious() {
    guard let previousItem = history.popLast() else { return }

    if let currentItem {
      queue.insert(currentItem, at: 0)
    }

    currentItem = previousItem
    errorMessage = nil
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
      let station = try await stationClient.fetchCurrentStation()
      self.station = station
      stationTitle = station.title
      stationIntro = station.subtitle
      currentItem = nil
      history = []
      queue = station.items

      if playImmediately {
        isLoadingStation = false
        await playNext()
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
}
