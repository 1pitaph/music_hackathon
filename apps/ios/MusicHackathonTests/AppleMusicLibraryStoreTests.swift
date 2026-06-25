import MusicKit
import XCTest
@testable import MusicHackathon

@MainActor
final class AppleMusicLibraryStoreTests: XCTestCase {
  func testRefreshNeedsAuthorizationWhenAccessIsNotAuthorized() async {
    let store = AppleMusicLibraryStore(provider: FakeLibraryProvider(snapshot: makeSnapshot()), cache: nil)

    await store.refresh(authorizationStatus: .denied)

    XCTAssertEqual(store.state, .needsAuthorization)
    XCTAssertTrue(store.playlists.isEmpty)
    XCTAssertTrue(store.tracks.isEmpty)
    XCTAssertTrue(store.stations.isEmpty)
  }

  func testRefreshLoadsSnapshotAndBuildsDiscoverStations() async {
    let snapshot = makeSnapshot()
    let store = AppleMusicLibraryStore(provider: FakeLibraryProvider(snapshot: snapshot), cache: nil)

    await store.refresh(authorizationStatus: .authorized)

    XCTAssertEqual(store.state, .loaded)
    XCTAssertEqual(store.playlists.map(\.name), ["Library Mix"])
    XCTAssertEqual(store.tracks.map(\.title), ["Signal"])
    XCTAssertEqual(store.stations.first?.title, "Library Mix")
    XCTAssertEqual(store.stations.first?.items.first?.track.artworkURL?.absoluteString, "https://example.com/signal.jpg")
  }

  func testRefreshRequestsFullLibrarySnapshotOptions() async {
    let provider = FakeLibraryProvider(snapshot: makeSnapshot())
    let store = AppleMusicLibraryStore(provider: provider, cache: nil)

    await store.refresh(authorizationStatus: .authorized)

    XCTAssertEqual(provider.capturedOptions?.pageSize, 100)
    XCTAssertEqual(provider.capturedOptions?.includeLibrarySongs, true)
  }

  func testRefreshUsesEmptyStateWhenSnapshotHasNoPlayableTracks() async {
    let store = AppleMusicLibraryStore(provider: FakeLibraryProvider(snapshot: .empty), cache: nil)

    await store.refresh(authorizationStatus: .authorized)

    XCTAssertEqual(store.state, .empty)
    XCTAssertTrue(store.stations.isEmpty)
  }

  func testRefreshStoresFailureMessage() async {
    let store = AppleMusicLibraryStore(provider: FakeLibraryProvider(error: TestError.unavailable), cache: nil)

    await store.refresh(authorizationStatus: .authorized)

    XCTAssertEqual(store.state, .failed("Library unavailable."))
    XCTAssertEqual(store.lastErrorMessage, "Library unavailable.")
    XCTAssertTrue(store.tracks.isEmpty)
  }

  func testLoadIfNeededUsesFreshCacheWithoutProviderRefresh() async throws {
    let cache = try makeCache()
    let cachedSnapshot = makeSnapshot(title: "Cached Signal")
    try await cache.saveSnapshot(cachedSnapshot, now: Date())
    let provider = FakeLibraryProvider(error: TestError.unavailable)
    let store = AppleMusicLibraryStore(provider: provider, cache: cache)

    await store.loadIfNeeded(authorizationStatus: .authorized)

    XCTAssertEqual(store.state, .loaded)
    XCTAssertEqual(store.tracks.map(\.title), ["Cached Signal"])
    XCTAssertNil(provider.capturedOptions)
    XCTAssertEqual(provider.requestCount, 0)
  }

  func testLoadIfNeededPreservesExpiredCacheWhenRefreshFails() async throws {
    let cache = try makeCache(libraryTTL: -1)
    let cachedSnapshot = makeSnapshot(title: "Cached Signal")
    try await cache.saveSnapshot(cachedSnapshot, now: Date())
    let provider = FakeLibraryProvider(error: TestError.unavailable)
    let store = AppleMusicLibraryStore(provider: provider, cache: cache)

    await store.loadIfNeeded(authorizationStatus: .authorized)

    XCTAssertEqual(store.state, .loaded)
    XCTAssertEqual(store.tracks.map(\.title), ["Cached Signal"])
    XCTAssertEqual(store.lastErrorMessage, "Library unavailable.")
    XCTAssertEqual(provider.requestCount, 1)
  }

  func testDiscoverStationFallsBackToLibraryTracksWhenPlaylistsAreEmpty() {
    let track = makeTrack(title: "Fallback Song")
    let stations = DiscoverStation.stations(from: [], libraryTracks: [track])

    XCTAssertEqual(stations.count, 1)
    XCTAssertEqual(stations[0].title, L10n.tr("discover.libraryStation.title"))
    XCTAssertEqual(stations[0].items.first?.track.title, "Fallback Song")
    XCTAssertEqual(stations[0].heroArtworkURL?.absoluteString, "https://example.com/fallback-song.jpg")
  }

  func testNormalizedArtworkURLKeepsOnlyFetchableLookingHTTPURLs() {
    let validURL = URL(string: "https://example.com/cover.jpg")!
    let fileURL = URL(string: "file:///tmp/cover.jpg")!
    let hostlessURL = URL(string: "https:/cover.jpg")!
    let templateURL = URL(string: "https://example.com/{w}x{h}bb.{f}")!

    XCTAssertEqual(AppleMusicCatalogService.normalizedArtworkURL(validURL), validURL)
    XCTAssertNil(AppleMusicCatalogService.normalizedArtworkURL(fileURL))
    XCTAssertNil(AppleMusicCatalogService.normalizedArtworkURL(hostlessURL))
    XCTAssertNil(AppleMusicCatalogService.normalizedArtworkURL(templateURL))
    XCTAssertNil(AppleMusicCatalogService.normalizedArtworkURL(nil))
  }

  func testPlaylistArtworkCandidatesPreferPlaylistThenTrackArtworkAndDedupe() {
    let playlistArtworkURL = URL(string: "https://example.com/playlist.jpg")!
    let trackArtworkURL = URL(string: "https://example.com/track.jpg")!
    let templateArtworkURL = URL(string: "https://example.com/{w}x{h}bb.{f}")!
    let playlist = AppleMusicPlaylistSnapshot(
      id: "playlist-1",
      name: "Library Mix",
      curatorName: "Apple Music",
      artworkURL: playlistArtworkURL,
      tracks: [
        makeTrack(title: "Signal", artworkURL: trackArtworkURL),
        makeTrack(title: "Duplicate", artworkURL: playlistArtworkURL),
        makeTrack(title: "Template", artworkURL: templateArtworkURL)
      ]
    )

    XCTAssertEqual(
      playlist.artworkCandidateURLs.map(\.absoluteString),
      [
        "https://example.com/playlist.jpg",
        "https://example.com/track.jpg"
      ]
    )
  }

  func testDiscoverStationArtworkURLsKeepOrderAndRemoveDuplicates() {
    let stationArtworkURL = URL(string: "https://example.com/station.jpg")!
    let trackArtworkURL = URL(string: "https://example.com/track.jpg")!
    let station = DiscoverStation(
      id: "station-1",
      title: "Station",
      briefIntro: "Brief",
      description: "Description",
      hostName: "Host",
      genre: "Pop",
      favorites: 2,
      items: [
        RadioQueueItem(
          id: "item-1",
          track: makeTrack(title: "Duplicate", artworkURL: stationArtworkURL),
          sourceTitle: "Host",
          reason: "Duplicate artwork"
        ),
        RadioQueueItem(
          id: "item-2",
          track: makeTrack(title: "Unique", artworkURL: trackArtworkURL),
          sourceTitle: "Host",
          reason: "Unique artwork"
        )
      ],
      colorHex: "#2A2A2A",
      artworkURL: stationArtworkURL,
      shareURL: URL(string: "https://example.com/station-1")!
    )

    XCTAssertEqual(
      station.artworkURLs.map(\.absoluteString),
      [
        "https://example.com/station.jpg",
        "https://example.com/track.jpg"
      ]
    )
  }

  private func makeSnapshot(title: String = "Signal") -> AppleMusicLibrarySnapshot {
    let track = makeTrack(title: title)
    let playlist = AppleMusicPlaylistSnapshot(
      id: "playlist-1",
      name: "Library Mix",
      curatorName: "Apple Music",
      artworkURL: URL(string: "https://example.com/playlist.jpg"),
      tracks: [track]
    )

    return AppleMusicLibrarySnapshot(playlists: [playlist], tracks: [track])
  }

  private func makeCache(libraryTTL: TimeInterval = 3_600) throws -> AppleMusicLibraryCacheStore {
    let directoryURL = FileManager.default.temporaryDirectory
      .appending(path: "AppleMusicLibraryStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    addTeardownBlock {
      try? FileManager.default.removeItem(at: directoryURL)
    }
    return AppleMusicLibraryCacheStore(directoryURL: directoryURL, libraryTTL: libraryTTL)
  }

  private func makeTrack(title: String, artworkURL: URL? = nil) -> MusicHackathon.Track {
    let slug = title.lowercased().replacingOccurrences(of: " ", with: "-")
    return MusicHackathon.Track(
      title: title,
      artist: "Artist",
      album: "Album",
      mood: "Pop",
      duration: 210,
      artworkSystemName: "music.note",
      artworkURL: artworkURL ?? URL(string: "https://example.com/\(slug).jpg"),
      previewURL: URL(string: "https://example.com/\(slug).m4a"),
      appleMusicID: slug,
      playlistName: "Library Mix",
      source: "apple_music_library",
      sourceLane: "playlist_entry"
    )
  }
}

private final class FakeLibraryProvider: AppleMusicLibraryProviding {
  let result: Result<AppleMusicLibrarySnapshot, Error>
  var capturedOptions: AppleMusicLibraryLoadOptions?
  var requestCount = 0

  init(snapshot: AppleMusicLibrarySnapshot) {
    result = .success(snapshot)
  }

  init(error: Error) {
    result = .failure(error)
  }

  func librarySnapshot(options: AppleMusicLibraryLoadOptions) async throws -> AppleMusicLibrarySnapshot {
    requestCount += 1
    capturedOptions = options
    return try result.get()
  }
}

private enum TestError: LocalizedError {
  case unavailable

  var errorDescription: String? {
    "Library unavailable."
  }
}
