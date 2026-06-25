import Foundation

protocol RadioPlaybackSnapshotStoring {
  func load(now: Date) async -> RadioPlaybackSnapshot?
  func save(_ snapshot: RadioPlaybackSnapshot) async throws
  func clear() async throws
}

extension RadioPlaybackSnapshotStoring {
  func load() async -> RadioPlaybackSnapshot? {
    await load(now: Date())
  }
}

enum RadioPlaybackSettings {
  static let backgroundPlayKey = "settings.playback.backgroundPlay"
  static let defaultBackgroundPlay = true

  static func registerDefaults(defaults: UserDefaults = .standard) {
    defaults.register(defaults: [backgroundPlayKey: defaultBackgroundPlay])
  }
}

struct RadioPlaybackSnapshot: Codable, Equatable {
  static let currentVersion = 1

  var version = Self.currentVersion
  var savedAt: Date
  var station: RadioStation?
  var queue: [RadioQueueItem]
  var currentItem: RadioQueueItem?
  var history: [RadioQueueItem]
  var stationTitle: String
  var stationIntro: String
  var hasPlayedStationIntro: Bool
  var stationSessionID: String?
  var continuationCursor: String?
  var playback: Playback

  var hasContent: Bool {
    station != nil || currentItem != nil || !queue.isEmpty
  }

  func isValid(now: Date, validityInterval: TimeInterval) -> Bool {
    guard version == Self.currentVersion, hasContent else { return false }
    let age = now.timeIntervalSince(savedAt)
    guard age >= 0, age <= validityInterval else { return false }
    guard playback.elapsedSeconds.isFinite, playback.elapsedSeconds >= 0 else { return false }

    if let playbackTrack = playback.track {
      guard let currentItem else { return false }
      guard playbackTrack.radioIdentity == currentItem.track.radioIdentity else { return false }
    }

    return true
  }

  struct Playback: Codable, Equatable {
    var track: Track?
    var policy: RadioTrackPlaybackPolicy
    var elapsedSeconds: TimeInterval
    var wasPlaying: Bool
    var activeBackend: PlaybackBackend
  }
}

actor RadioPlaybackSnapshotStore: RadioPlaybackSnapshotStoring {
  private let directoryURL: URL
  private let snapshotURL: URL
  private let validityInterval: TimeInterval

  init(
    directoryURL: URL? = nil,
    validityInterval: TimeInterval = 7 * 24 * 60 * 60
  ) {
    let resolvedDirectory = directoryURL ?? Self.defaultDirectoryURL()
    self.directoryURL = resolvedDirectory
    snapshotURL = resolvedDirectory.appending(path: "playback-snapshot.json")
    self.validityInterval = validityInterval
  }

  func load(now: Date = Date()) async -> RadioPlaybackSnapshot? {
    guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
      return nil
    }

    do {
      let data = try Data(contentsOf: snapshotURL)
      let snapshot = try JSONDecoder().decode(RadioPlaybackSnapshot.self, from: data)
      guard snapshot.isValid(now: now, validityInterval: validityInterval) else {
        try? await clear()
        return nil
      }
      return snapshot
    } catch {
      try? await clear()
      return nil
    }
  }

  func save(_ snapshot: RadioPlaybackSnapshot) async throws {
    guard snapshot.hasContent else {
      try await clear()
      return
    }

    try ensureDirectory()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(snapshot)
    try data.write(to: snapshotURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }

  func clear() async throws {
    guard FileManager.default.fileExists(atPath: snapshotURL.path) else { return }
    try FileManager.default.removeItem(at: snapshotURL)
  }

  private func ensureDirectory() throws {
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
  }

  private static func defaultDirectoryURL() -> URL {
    let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return baseURL.appending(path: "AirsetRadioPlayback", directoryHint: .isDirectory)
  }
}
