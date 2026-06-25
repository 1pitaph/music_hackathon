import Foundation

struct AppleMusicLibraryCacheLoadResult: Equatable {
  let snapshot: AppleMusicLibrarySnapshot
  let savedAt: Date
  let expiresAt: Date
  let isExpired: Bool
}

protocol AppleMusicLibraryCaching: Sendable {
  func loadSnapshot(now: Date) async throws -> AppleMusicLibraryCacheLoadResult?
  func saveSnapshot(
    _ snapshot: AppleMusicLibrarySnapshot,
    now: Date
  ) async throws -> AppleMusicLibraryCacheLoadResult
  func clear() async throws
}

protocol AppleMusicCatalogResolutionCaching: Sendable {
  func cachedResolvedTrack(for track: Track, now: Date) async throws -> Track?
  func storeResolvedTrack(
    _ resolvedTrack: Track,
    for originalTrack: Track,
    method: AppleMusicCatalogResolutionMethod,
    now: Date
  ) async throws
  func recordResolutionFailure(for track: Track, now: Date) async throws
  func invalidateResolution(for track: Track) async throws
}

actor AppleMusicLibraryCacheStore: AppleMusicLibraryCaching, AppleMusicCatalogResolutionCaching {
  static let shared = AppleMusicLibraryCacheStore()

  private let directoryURL: URL
  private let cacheURL: URL
  private let fileManager: FileManager
  private let libraryTTL: TimeInterval
  private let catalogResolutionTTL: TimeInterval
  private let tombstoneRetention: TimeInterval
  private let schemaVersion = 2

  init(
    directoryURL: URL? = nil,
    fileManager: FileManager = .default,
    libraryTTL: TimeInterval = 6 * 60 * 60,
    catalogResolutionTTL: TimeInterval = 7 * 24 * 60 * 60,
    tombstoneRetention: TimeInterval = 30 * 24 * 60 * 60
  ) {
    let rootURL = directoryURL ?? Self.defaultDirectoryURL()
    self.directoryURL = rootURL
    cacheURL = rootURL.appending(path: "library-cache.json")
    self.fileManager = fileManager
    self.libraryTTL = libraryTTL
    self.catalogResolutionTTL = catalogResolutionTTL
    self.tombstoneRetention = tombstoneRetention
  }

  func loadSnapshot(now: Date = Date()) async throws -> AppleMusicLibraryCacheLoadResult? {
    guard fileManager.fileExists(atPath: cacheURL.path) else { return nil }
    let cache = try loadCache()
    let snapshot = materializedSnapshot(from: cache)
    guard !snapshot.playlists.isEmpty || !snapshot.tracks.isEmpty else {
      return AppleMusicLibraryCacheLoadResult(
        snapshot: snapshot,
        savedAt: cache.metadata.lastSuccessfulSyncAt ?? cache.metadata.updatedAt,
        expiresAt: cache.metadata.expiresAt,
        isExpired: cache.metadata.expiresAt <= now
      )
    }

    return AppleMusicLibraryCacheLoadResult(
      snapshot: snapshot,
      savedAt: cache.metadata.lastSuccessfulSyncAt ?? cache.metadata.updatedAt,
      expiresAt: cache.metadata.expiresAt,
      isExpired: cache.metadata.expiresAt <= now
    )
  }

  func saveSnapshot(
    _ snapshot: AppleMusicLibrarySnapshot,
    now: Date = Date()
  ) async throws -> AppleMusicLibraryCacheLoadResult {
    var cache = try loadCache()
    cache.metadata.lastAttemptAt = now
    cache.metadata.updatedAt = now
    cache.metadata.lastSuccessfulSyncAt = now
    cache.metadata.expiresAt = now.addingTimeInterval(libraryTTL)
    cache.metadata.syncGeneration += 1

    var seenTrackKeys: Set<String> = []
    var seenPlaylistIDs: Set<String> = []
    var seenPlaylistTrackKeys: Set<String> = []

    for (index, track) in snapshot.tracks.enumerated() {
      upsertTrack(track, position: index, now: now, in: &cache, seenTrackKeys: &seenTrackKeys)
    }

    for (playlistIndex, playlist) in snapshot.playlists.enumerated() {
      seenPlaylistIDs.insert(playlist.id)
      upsertPlaylist(playlist, position: playlistIndex, now: now, in: &cache)

      for (trackIndex, track) in playlist.tracks.enumerated() {
        upsertTrack(track, position: nil, now: now, in: &cache, seenTrackKeys: &seenTrackKeys)
        let trackKey = track.radioIdentity
        let membershipKey = playlistTrackKey(playlistID: playlist.id, trackKey: trackKey)
        seenPlaylistTrackKeys.insert(membershipKey)
        upsertPlaylistTrack(
          playlistID: playlist.id,
          trackKey: trackKey,
          track: track,
          position: trackIndex,
          now: now,
          key: membershipKey,
          in: &cache
        )
      }
    }

    if snapshot.isComplete {
      tombstoneMissingRecords(
        seenTrackKeys: seenTrackKeys,
        seenPlaylistIDs: seenPlaylistIDs,
        seenPlaylistTrackKeys: seenPlaylistTrackKeys,
        now: now,
        in: &cache
      )
    }

    pruneExpiredTombstones(now: now, in: &cache)
    try save(cache)

    let materialized = materializedSnapshot(from: cache)
    return AppleMusicLibraryCacheLoadResult(
      snapshot: materialized,
      savedAt: now,
      expiresAt: cache.metadata.expiresAt,
      isExpired: false
    )
  }

  func clear() async throws {
    guard fileManager.fileExists(atPath: directoryURL.path) else { return }
    try fileManager.removeItem(at: directoryURL)
  }

  func cachedResolvedTrack(for track: Track, now: Date = Date()) async throws -> Track? {
    guard fileManager.fileExists(atPath: cacheURL.path) else { return nil }
    let cache = try loadCache()
    guard let record = cache.catalogResolutions[track.radioIdentity],
          !record.isInvalidated,
          record.expiresAt > now else {
      return nil
    }

    if let lastFailureAt = record.lastFailureAt, lastFailureAt > record.resolvedAt {
      return nil
    }

    return record.resolvedTrack
  }

  func storeResolvedTrack(
    _ resolvedTrack: Track,
    for originalTrack: Track,
    method: AppleMusicCatalogResolutionMethod,
    now: Date = Date()
  ) async throws {
    var cache = try loadCache()
    upsertResolution(
      resolvedTrack,
      for: originalTrack.radioIdentity,
      method: method,
      now: now,
      in: &cache
    )

    if resolvedTrack.radioIdentity != originalTrack.radioIdentity {
      upsertResolution(
        resolvedTrack,
        for: resolvedTrack.radioIdentity,
        method: method,
        now: now,
        in: &cache
      )
    }

    cache.metadata.updatedAt = now
    try save(cache)
  }

  func recordResolutionFailure(for track: Track, now: Date = Date()) async throws {
    var cache = try loadCache()
    let trackKey = track.radioIdentity
    if var record = cache.catalogResolutions[trackKey] {
      record.lastFailureAt = now
      cache.catalogResolutions[trackKey] = record
    } else {
      cache.catalogResolutions[trackKey] = CatalogResolutionRecord(
        trackKey: trackKey,
        resolvedTrack: track,
        method: AppleMusicCatalogResolutionMethod.search.rawValue,
        resolvedAt: .distantPast,
        expiresAt: now,
        lastFailureAt: now,
        isInvalidated: true
      )
    }
    cache.metadata.updatedAt = now
    try save(cache)
  }

  func invalidateResolution(for track: Track) async throws {
    guard fileManager.fileExists(atPath: cacheURL.path) else { return }
    var cache = try loadCache()
    let trackKey = track.radioIdentity
    guard var record = cache.catalogResolutions[trackKey] else { return }
    record.isInvalidated = true
    record.lastFailureAt = Date()
    cache.catalogResolutions[trackKey] = record
    cache.metadata.updatedAt = Date()
    try save(cache)
  }

  private func upsertTrack(
    _ track: Track,
    position: Int?,
    now: Date,
    in cache: inout StoredCache,
    seenTrackKeys: inout Set<String>
  ) {
    let trackKey = track.radioIdentity
    seenTrackKeys.insert(trackKey)

    if var record = cache.tracks[trackKey] {
      record.track = track
      record.lastSeenAt = now
      record.updatedAt = now
      record.isTombstoned = false
      record.tombstonedAt = nil
      if let position {
        record.position = position
      }
      cache.tracks[trackKey] = record
    } else {
      cache.tracks[trackKey] = TrackRecord(
        trackKey: trackKey,
        track: track,
        position: position ?? cache.tracks.count,
        firstSeenAt: now,
        lastSeenAt: now,
        updatedAt: now,
        isTombstoned: false,
        tombstonedAt: nil
      )
    }
  }

  private func upsertPlaylist(
    _ playlist: AppleMusicPlaylistSnapshot,
    position: Int,
    now: Date,
    in cache: inout StoredCache
  ) {
    if var record = cache.playlists[playlist.id] {
      record.name = playlist.name
      record.curatorName = playlist.curatorName
      record.artworkURL = playlist.artworkURL
      record.position = position
      record.lastSeenAt = now
      record.updatedAt = now
      record.isTombstoned = false
      record.tombstonedAt = nil
      cache.playlists[playlist.id] = record
    } else {
      cache.playlists[playlist.id] = PlaylistRecord(
        playlistID: playlist.id,
        name: playlist.name,
        curatorName: playlist.curatorName,
        artworkURL: playlist.artworkURL,
        position: position,
        firstSeenAt: now,
        lastSeenAt: now,
        updatedAt: now,
        isTombstoned: false,
        tombstonedAt: nil
      )
    }
  }

  private func upsertPlaylistTrack(
    playlistID: String,
    trackKey: String,
    track: Track,
    position: Int,
    now: Date,
    key: String,
    in cache: inout StoredCache
  ) {
    if var record = cache.playlistTracks[key] {
      record.track = track
      record.position = position
      record.lastSeenAt = now
      record.updatedAt = now
      record.isTombstoned = false
      record.tombstonedAt = nil
      cache.playlistTracks[key] = record
    } else {
      cache.playlistTracks[key] = PlaylistTrackRecord(
        key: key,
        playlistID: playlistID,
        trackKey: trackKey,
        track: track,
        position: position,
        firstSeenAt: now,
        lastSeenAt: now,
        updatedAt: now,
        isTombstoned: false,
        tombstonedAt: nil
      )
    }
  }

  private func tombstoneMissingRecords(
    seenTrackKeys: Set<String>,
    seenPlaylistIDs: Set<String>,
    seenPlaylistTrackKeys: Set<String>,
    now: Date,
    in cache: inout StoredCache
  ) {
    for (key, record) in cache.tracks where !seenTrackKeys.contains(key) && !record.isTombstoned {
      var nextRecord = record
      nextRecord.isTombstoned = true
      nextRecord.tombstonedAt = now
      nextRecord.updatedAt = now
      cache.tracks[key] = nextRecord
    }

    for (key, record) in cache.playlists where !seenPlaylistIDs.contains(key) && !record.isTombstoned {
      var nextRecord = record
      nextRecord.isTombstoned = true
      nextRecord.tombstonedAt = now
      nextRecord.updatedAt = now
      cache.playlists[key] = nextRecord
    }

    for (key, record) in cache.playlistTracks where !seenPlaylistTrackKeys.contains(key) && !record.isTombstoned {
      var nextRecord = record
      nextRecord.isTombstoned = true
      nextRecord.tombstonedAt = now
      nextRecord.updatedAt = now
      cache.playlistTracks[key] = nextRecord
    }
  }

  private func pruneExpiredTombstones(now: Date, in cache: inout StoredCache) {
    let cutoff = now.addingTimeInterval(-tombstoneRetention)
    cache.tracks = cache.tracks.filter { _, record in
      guard record.isTombstoned, let tombstonedAt = record.tombstonedAt else { return true }
      return tombstonedAt >= cutoff
    }
    cache.playlists = cache.playlists.filter { _, record in
      guard record.isTombstoned, let tombstonedAt = record.tombstonedAt else { return true }
      return tombstonedAt >= cutoff
    }
    cache.playlistTracks = cache.playlistTracks.filter { _, record in
      guard record.isTombstoned, let tombstonedAt = record.tombstonedAt else { return true }
      return tombstonedAt >= cutoff
    }
  }

  private func upsertResolution(
    _ resolvedTrack: Track,
    for trackKey: String,
    method: AppleMusicCatalogResolutionMethod,
    now: Date,
    in cache: inout StoredCache
  ) {
    cache.catalogResolutions[trackKey] = CatalogResolutionRecord(
      trackKey: trackKey,
      resolvedTrack: resolvedTrack,
      method: method.rawValue,
      resolvedAt: now,
      expiresAt: now.addingTimeInterval(catalogResolutionTTL),
      lastFailureAt: nil,
      isInvalidated: false
    )
  }

  private func materializedSnapshot(from cache: StoredCache) -> AppleMusicLibrarySnapshot {
    let activePlaylists = cache.playlists.values
      .filter { !$0.isTombstoned }
      .sorted { lhs, rhs in
        if lhs.position == rhs.position {
          return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return lhs.position < rhs.position
      }

    let activePlaylistTracks = cache.playlistTracks.values
      .filter { !$0.isTombstoned }

    let playlistSnapshots = activePlaylists.map { playlist in
      let tracks = activePlaylistTracks
        .filter { $0.playlistID == playlist.playlistID }
        .sorted { lhs, rhs in
          if lhs.position == rhs.position {
            return lhs.track.title.localizedCaseInsensitiveCompare(rhs.track.title) == .orderedAscending
          }
          return lhs.position < rhs.position
        }
        .map(\.track)

      return AppleMusicPlaylistSnapshot(
        id: playlist.playlistID,
        name: playlist.name,
        curatorName: playlist.curatorName,
        artworkURL: playlist.artworkURL,
        tracks: tracks
      )
    }

    let tracks = cache.tracks.values
      .filter { !$0.isTombstoned }
      .sorted { lhs, rhs in
        if lhs.position == rhs.position {
          return lhs.track.title.localizedCaseInsensitiveCompare(rhs.track.title) == .orderedAscending
        }
        return lhs.position < rhs.position
      }
      .map(\.track)

    return AppleMusicLibrarySnapshot(
      playlists: playlistSnapshots,
      tracks: tracks,
      isComplete: true
    )
  }

  private func loadCache() throws -> StoredCache {
    try ensureDirectory()
    guard fileManager.fileExists(atPath: cacheURL.path) else {
      return StoredCache.empty(schemaVersion: schemaVersion, now: Date(), ttl: libraryTTL)
    }

    do {
      let data = try Data(contentsOf: cacheURL)
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      var cache = try decoder.decode(StoredCache.self, from: data)
      cache.schemaVersion = schemaVersion
      return cache
    } catch {
      try quarantineCorruptCache()
      return StoredCache.empty(schemaVersion: schemaVersion, now: Date(), ttl: libraryTTL)
    }
  }

  private func save(_ cache: StoredCache) throws {
    try ensureDirectory()
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var directory = directoryURL
    try? directory.setResourceValues(values)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(cache)
    try data.write(to: cacheURL, options: [.atomic, .completeFileProtection])
  }

  private func ensureDirectory() throws {
    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
  }

  private func quarantineCorruptCache() throws {
    guard fileManager.fileExists(atPath: cacheURL.path) else { return }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
    let safeTimestamp = formatter.string(from: Date())
      .replacingOccurrences(of: ":", with: "-")
    let badURL = directoryURL.appending(path: "library-cache-\(safeTimestamp).bad")
    try? fileManager.removeItem(at: badURL)
    try fileManager.moveItem(at: cacheURL, to: badURL)
  }

  private func playlistTrackKey(playlistID: String, trackKey: String) -> String {
    "\(playlistID)::\(trackKey)"
  }

  private static func defaultDirectoryURL() -> URL {
    let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return baseURL.appending(path: "AirsetAppleMusicLibrary", directoryHint: .isDirectory)
  }
}

private struct StoredCache: Codable {
  var schemaVersion: Int
  var metadata: CacheMetadata
  var tracks: [String: TrackRecord]
  var playlists: [String: PlaylistRecord]
  var playlistTracks: [String: PlaylistTrackRecord]
  var catalogResolutions: [String: CatalogResolutionRecord]

  static func empty(schemaVersion: Int, now: Date, ttl: TimeInterval) -> StoredCache {
    StoredCache(
      schemaVersion: schemaVersion,
      metadata: CacheMetadata(
        updatedAt: now,
        lastSuccessfulSyncAt: nil,
        lastAttemptAt: nil,
        expiresAt: now.addingTimeInterval(ttl),
        syncGeneration: 0
      ),
      tracks: [:],
      playlists: [:],
      playlistTracks: [:],
      catalogResolutions: [:]
    )
  }
}

private struct CacheMetadata: Codable {
  var updatedAt: Date
  var lastSuccessfulSyncAt: Date?
  var lastAttemptAt: Date?
  var expiresAt: Date
  var syncGeneration: Int
}

private struct TrackRecord: Codable {
  var trackKey: String
  var track: Track
  var position: Int
  var firstSeenAt: Date
  var lastSeenAt: Date
  var updatedAt: Date
  var isTombstoned: Bool
  var tombstonedAt: Date?
}

private struct PlaylistRecord: Codable {
  var playlistID: String
  var name: String
  var curatorName: String?
  var artworkURL: URL?
  var position: Int
  var firstSeenAt: Date
  var lastSeenAt: Date
  var updatedAt: Date
  var isTombstoned: Bool
  var tombstonedAt: Date?
}

private struct PlaylistTrackRecord: Codable {
  var key: String
  var playlistID: String
  var trackKey: String
  var track: Track
  var position: Int
  var firstSeenAt: Date
  var lastSeenAt: Date
  var updatedAt: Date
  var isTombstoned: Bool
  var tombstonedAt: Date?
}

private struct CatalogResolutionRecord: Codable {
  var trackKey: String
  var resolvedTrack: Track
  var method: String
  var resolvedAt: Date
  var expiresAt: Date
  var lastFailureAt: Date?
  var isInvalidated: Bool
}
