import MusicKit
import XCTest
@testable import MusicHackathon

@MainActor
final class AppleMusicLibraryStoreTests: XCTestCase {
  func testRefreshNeedsAuthorizationWhenAccessIsNotAuthorized() async {
    let store = AppleMusicLibraryStore(provider: FakeLibraryProvider(snapshot: makeSnapshot()))

    await store.refresh(authorizationStatus: .denied)

    XCTAssertEqual(store.state, .needsAuthorization)
    XCTAssertTrue(store.playlists.isEmpty)
    XCTAssertTrue(store.tracks.isEmpty)
    XCTAssertTrue(store.stations.isEmpty)
  }

  func testRefreshLoadsSnapshotAndBuildsDiscoverStations() async {
    let snapshot = makeSnapshot()
    let store = AppleMusicLibraryStore(provider: FakeLibraryProvider(snapshot: snapshot))

    await store.refresh(authorizationStatus: .authorized)

    XCTAssertEqual(store.state, .loaded)
    XCTAssertEqual(store.playlists.map(\.name), ["Library Mix"])
    XCTAssertEqual(store.tracks.map(\.title), ["Signal"])
    XCTAssertEqual(store.stations.first?.title, "Library Mix")
    XCTAssertEqual(store.stations.first?.items.first?.track.artworkURL?.absoluteString, "https://example.com/signal.jpg")
  }

  func testRefreshUsesEmptyStateWhenSnapshotHasNoPlayableTracks() async {
    let store = AppleMusicLibraryStore(provider: FakeLibraryProvider(snapshot: .empty))

    await store.refresh(authorizationStatus: .authorized)

    XCTAssertEqual(store.state, .empty)
    XCTAssertTrue(store.stations.isEmpty)
  }

  func testRefreshStoresFailureMessage() async {
    let store = AppleMusicLibraryStore(provider: FakeLibraryProvider(error: TestError.unavailable))

    await store.refresh(authorizationStatus: .authorized)

    XCTAssertEqual(store.state, .failed("Library unavailable."))
    XCTAssertEqual(store.lastErrorMessage, "Library unavailable.")
    XCTAssertTrue(store.tracks.isEmpty)
  }

  func testDiscoverStationFallsBackToLibraryTracksWhenPlaylistsAreEmpty() {
    let track = makeTrack(title: "Fallback Song")
    let stations = DiscoverStation.stations(from: [], libraryTracks: [track])

    XCTAssertEqual(stations.count, 1)
    XCTAssertEqual(stations[0].title, "我的 Apple Music")
    XCTAssertEqual(stations[0].items.first?.track.title, "Fallback Song")
    XCTAssertEqual(stations[0].heroArtworkURL?.absoluteString, "https://example.com/fallback-song.jpg")
  }

  private func makeSnapshot() -> AppleMusicLibrarySnapshot {
    let track = makeTrack(title: "Signal")
    let playlist = AppleMusicPlaylistSnapshot(
      id: "playlist-1",
      name: "Library Mix",
      curatorName: "Apple Music",
      artworkURL: URL(string: "https://example.com/playlist.jpg"),
      tracks: [track]
    )

    return AppleMusicLibrarySnapshot(playlists: [playlist], tracks: [track])
  }

  private func makeTrack(title: String) -> MusicHackathon.Track {
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
      appleMusicID: slug,
      playlistName: "Library Mix",
      source: "apple_music_library",
      sourceLane: "playlist_entry"
    )
  }
}

private struct FakeLibraryProvider: AppleMusicLibraryProviding {
  let result: Result<AppleMusicLibrarySnapshot, Error>

  init(snapshot: AppleMusicLibrarySnapshot) {
    result = .success(snapshot)
  }

  init(error: Error) {
    result = .failure(error)
  }

  func librarySnapshot(
    playlistLimit: Int,
    tracksPerPlaylistLimit: Int,
    fallbackSongLimit: Int
  ) async throws -> AppleMusicLibrarySnapshot {
    try result.get()
  }
}

private enum TestError: LocalizedError {
  case unavailable

  var errorDescription: String? {
    "Library unavailable."
  }
}
