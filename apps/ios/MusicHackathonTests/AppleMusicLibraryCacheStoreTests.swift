import XCTest
@testable import MusicHackathon

final class AppleMusicLibraryCacheStoreTests: XCTestCase {
  func testSaveLoadRoundTripAndTTL() async throws {
    let cache = try makeCache(libraryTTL: 60)
    let now = Date(timeIntervalSince1970: 1_000)
    let snapshot = makeSnapshot(trackTitles: ["Signal"])

    let saved = try await cache.saveSnapshot(snapshot, now: now)
    let freshResult = try await cache.loadSnapshot(now: now.addingTimeInterval(30))
    let expiredResult = try await cache.loadSnapshot(now: now.addingTimeInterval(61))
    let fresh = try XCTUnwrap(freshResult)
    let expired = try XCTUnwrap(expiredResult)

    XCTAssertFalse(saved.isExpired)
    XCTAssertEqual(fresh.snapshot.playlists.map(\.name), ["Library Mix"])
    XCTAssertEqual(fresh.snapshot.tracks.map(\.title), ["Signal"])
    XCTAssertFalse(fresh.isExpired)
    XCTAssertTrue(expired.isExpired)
  }

  func testCompleteSyncTombstonesMissingTracksAndMemberships() async throws {
    let cache = try makeCache()
    let now = Date(timeIntervalSince1970: 1_000)
    _ = try await cache.saveSnapshot(makeSnapshot(trackTitles: ["Signal", "Fader"]), now: now)

    let next = makeSnapshot(trackTitles: ["Signal"], isComplete: true)
    let saved = try await cache.saveSnapshot(next, now: now.addingTimeInterval(60))

    XCTAssertEqual(saved.snapshot.tracks.map(\.title), ["Signal"])
    XCTAssertEqual(saved.snapshot.playlists.first?.tracks.map(\.title), ["Signal"])
  }

  func testPartialSyncDoesNotTombstoneMissingTracksOrMemberships() async throws {
    let cache = try makeCache()
    let now = Date(timeIntervalSince1970: 1_000)
    _ = try await cache.saveSnapshot(makeSnapshot(trackTitles: ["Signal", "Fader"]), now: now)

    let partial = makeSnapshot(trackTitles: ["Signal"], isComplete: false)
    let saved = try await cache.saveSnapshot(partial, now: now.addingTimeInterval(60))

    XCTAssertEqual(saved.snapshot.tracks.map(\.title), ["Signal", "Fader"])
    XCTAssertEqual(saved.snapshot.playlists.first?.tracks.map(\.title), ["Signal", "Fader"])
  }

  func testCatalogResolutionCacheExpiresAndInvalidates() async throws {
    let cache = try makeCache(catalogResolutionTTL: 60)
    let now = Date(timeIntervalSince1970: 1_000)
    let original = makeTrack(title: "Unknown", appleMusicID: nil)
    let resolved = makeTrack(title: "Known", appleMusicID: "catalog-known")

    try await cache.storeResolvedTrack(resolved, for: original, method: .search, now: now)

    let fresh = try await cache.cachedResolvedTrack(for: original, now: now.addingTimeInterval(30))
    let expired = try await cache.cachedResolvedTrack(for: original, now: now.addingTimeInterval(61))
    try await cache.invalidateResolution(for: original)
    let invalidated = try await cache.cachedResolvedTrack(for: original, now: now.addingTimeInterval(30))

    XCTAssertEqual(fresh?.appleMusicID, "catalog-known")
    XCTAssertNil(expired)
    XCTAssertNil(invalidated)
  }

  private func makeCache(
    libraryTTL: TimeInterval = 3_600,
    catalogResolutionTTL: TimeInterval = 3_600
  ) throws -> AppleMusicLibraryCacheStore {
    let directoryURL = FileManager.default.temporaryDirectory
      .appending(path: "AppleMusicLibraryCacheStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    addTeardownBlock {
      try? FileManager.default.removeItem(at: directoryURL)
    }
    return AppleMusicLibraryCacheStore(
      directoryURL: directoryURL,
      libraryTTL: libraryTTL,
      catalogResolutionTTL: catalogResolutionTTL
    )
  }

  private func makeSnapshot(
    trackTitles: [String],
    isComplete: Bool = true
  ) -> AppleMusicLibrarySnapshot {
    let tracks = trackTitles.map { makeTrack(title: $0) }
    let playlist = AppleMusicPlaylistSnapshot(
      id: "playlist-1",
      name: "Library Mix",
      curatorName: "Apple Music",
      artworkURL: URL(string: "https://example.com/playlist.jpg"),
      tracks: tracks
    )

    return AppleMusicLibrarySnapshot(
      playlists: [playlist],
      tracks: tracks,
      isComplete: isComplete
    )
  }

  private func makeTrack(title: String, appleMusicID: String? = nil) -> MusicHackathon.Track {
    let slug = title.lowercased().replacingOccurrences(of: " ", with: "-")
    return MusicHackathon.Track(
      title: title,
      artist: "Artist",
      album: "Album",
      mood: "Pop",
      duration: 210,
      artworkSystemName: "music.note",
      artworkURL: URL(string: "https://example.com/\(slug).jpg"),
      previewURL: URL(string: "https://example.com/\(slug).m4a"),
      appleMusicID: appleMusicID ?? slug,
      playlistName: "Library Mix",
      source: "apple_music_library",
      sourceLane: "playlist_entry"
    )
  }
}
