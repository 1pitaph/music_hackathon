import Foundation

struct RadioSeedTrack: Identifiable, Hashable {
  var id: String { "\(playlistID)::\(track.radioIdentity)" }

  let track: Track
  let playlistID: String
  let playlistName: String
}

struct RadioQueueItem: Identifiable, Hashable {
  var id: String { "\(source.identity)::\(track.radioIdentity)" }

  let track: Track
  let source: RadioQueueSource
  let score: Double
  let reason: String
}

enum RadioQueueSource: Hashable, Codable {
  case playlist(id: String, name: String)
  case catalog(term: String)
  case fallback

  var identity: String {
    switch self {
    case let .playlist(id, _):
      "playlist:\(id)"
    case let .catalog(term):
      "catalog:\(term.lowercased())"
    case .fallback:
      "fallback"
    }
  }

  var displayName: String {
    switch self {
    case let .playlist(_, name):
      name
    case let .catalog(term):
      "Discovery: \(term)"
    case .fallback:
      "Local preview"
    }
  }

  var isCatalogDiscovery: Bool {
    if case .catalog = self {
      return true
    }
    return false
  }
}

struct RadioRuntimeContext: Hashable {
  let seedTracks: [RadioSeedTrack]
  let catalogCandidates: [RadioQueueItem]
  let memory: RadioMemory
  let tuning: RadioTuning
  let currentAction: RadioRuntimeAction
}

enum RadioRuntimeAction: String, Codable, Hashable {
  case idle
  case start
  case refresh
  case skip
  case tune
}

struct RadioTuning: Codable, Hashable {
  var discoveryRatio: Double = 0.30
  var familiarity: Double = 0.70
  var energy: Double = 0.50

  var normalized: RadioTuning {
    RadioTuning(
      discoveryRatio: discoveryRatio.clamped(to: 0...1),
      familiarity: familiarity.clamped(to: 0...1),
      energy: energy.clamped(to: 0...1)
    )
  }
}

struct RadioMemory: Codable, Equatable, Hashable {
  var selectedPlaylistIDs: Set<String> = []
  var recentlyPlayedTrackKeys: [String] = []
  var likedTrackKeys: Set<String> = []
  var skippedTrackKeys: Set<String> = []
  var dislikedTrackKeys: Set<String> = []
  var tuning: RadioTuning = RadioTuning()
  var lastSyncDate: Date?

  mutating func recordPlay(trackKey: String, limit: Int = 40) {
    recentlyPlayedTrackKeys.removeAll { $0 == trackKey }
    recentlyPlayedTrackKeys.insert(trackKey, at: 0)

    if recentlyPlayedTrackKeys.count > limit {
      recentlyPlayedTrackKeys = Array(recentlyPlayedTrackKeys.prefix(limit))
    }
  }

  mutating func recordLike(trackKey: String) {
    likedTrackKeys.insert(trackKey)
    skippedTrackKeys.remove(trackKey)
    dislikedTrackKeys.remove(trackKey)
  }

  mutating func recordSkip(trackKey: String) {
    skippedTrackKeys.insert(trackKey)
  }

  mutating func recordDislike(trackKey: String) {
    dislikedTrackKeys.insert(trackKey)
    likedTrackKeys.remove(trackKey)
  }
}

extension Track {
  var radioIdentity: String {
    if let appleMusicID {
      return "appleMusic:\(appleMusicID)"
    }

    let titleKey = title.radioKey
    let artistKey = artist.radioKey
    return "text:\(titleKey)::\(artistKey)"
  }
}

private extension String {
  var radioKey: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
  }
}

private extension Double {
  func clamped(to range: ClosedRange<Double>) -> Double {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
