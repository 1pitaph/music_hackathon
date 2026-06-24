import XCTest
@testable import MusicHackathon

final class MigrationModelsTests: XCTestCase {
  func testDiscoverStationsConvertToPlayableRadioStations() {
    let stations = DiscoverStation.mockStations

    XCTAssertGreaterThanOrEqual(stations.count, 6)

    for station in stations {
      let radioStation = station.radioStation()
      XCTAssertEqual(radioStation.id, station.id)
      XCTAssertFalse(radioStation.items.isEmpty)
      XCTAssertTrue(radioStation.items.allSatisfy { $0.track.isPlayable })
    }
  }

  func testArchiveProfileSortsRecentPublishedAndFiltersCurated() {
    let profile = ArchiveProfile.mock

    XCTAssertEqual(profile.recentPublished.map(\.id), ["p1", "p2", "p3", "p4", "p5"])
    XCTAssertFalse(profile.curatedStations.isEmpty)
    XCTAssertTrue(profile.curatedStations.allSatisfy(\.isFeatured))
  }

  func testArchiveCoverColorHashIsStable() {
    let first = ArchiveStationItem.colorHex(for: "stable-station")
    let second = ArchiveStationItem.colorHex(for: "stable-station")

    XCTAssertEqual(first, second)
    XCTAssertTrue(ArchiveStationItem.coverPalette.contains(first))
  }

  func testArchiveProfileEmptyStartsWithoutDefaultNameOrBio() {
    XCTAssertEqual(ArchiveProfile.empty.nickname, "")
    XCTAssertEqual(ArchiveProfile.empty.bio, "")
  }

  func testArchiveProfileBuildsMineDataFromAppleMusicLibrary() {
    let artworkURL = URL(string: "https://example.com/artwork.jpg")!
    let firstTrack = makeTrack(
      appleMusicID: "song-1",
      title: "First Song",
      artist: "Artist A",
      album: "Album A",
      duration: 240,
      artworkURL: artworkURL
    )
    let secondTrack = makeTrack(
      appleMusicID: "song-2",
      title: "Second Song",
      artist: "Artist B",
      album: "Album B",
      duration: 300,
      artworkURL: nil
    )
    let playlist = AppleMusicPlaylistSnapshot(
      id: "playlist-1",
      name: "Road Trip",
      curatorName: "Apple Music",
      artworkURL: artworkURL,
      tracks: [firstTrack, secondTrack]
    )

    let profile = ArchiveProfile.appleMusic(
      base: .empty,
      playlists: [playlist],
      tracks: [firstTrack]
    )

    XCTAssertEqual(profile.stats.stationsCount, 1)
    XCTAssertEqual(profile.stats.likesCount, 2)
    XCTAssertEqual(profile.published.map(\.name), ["Road Trip"])
    XCTAssertEqual(profile.published.first?.artworkURL, artworkURL)
    XCTAssertEqual(profile.published.first?.tracks.map(\.title), ["First Song", "Second Song"])
    XCTAssertEqual(profile.recentlyPlayed.map(\.name), ["First Song", "Second Song"])
    XCTAssertEqual(profile.saved.map(\.name), ["Artist A", "Artist B"])
    XCTAssertEqual(profile.nickname, "")
    XCTAssertEqual(profile.bio, "")
  }

  func testArchiveProfileInfersNicknameFromPersonalPlaylistCurator() {
    let track = makeTrack(
      appleMusicID: "song-1",
      title: "Personal Song",
      artist: "Artist A",
      album: "Album A",
      duration: 180,
      artworkURL: nil
    )
    let playlist = AppleMusicPlaylistSnapshot(
      id: "playlist-1",
      name: "Personal Mix",
      curatorName: "Ada Chen",
      artworkURL: nil,
      tracks: [track]
    )

    let profile = ArchiveProfile.appleMusic(base: .empty, playlists: [playlist], tracks: [])

    XCTAssertEqual(profile.nickname, "Ada Chen")
    XCTAssertEqual(profile.bio, "")
  }

  func testArchiveProfileIgnoresGenericAppleMusicCuratorName() {
    let track = makeTrack(
      appleMusicID: "song-1",
      title: "Editorial Song",
      artist: "Artist A",
      album: "Album A",
      duration: 180,
      artworkURL: nil
    )
    let playlist = AppleMusicPlaylistSnapshot(
      id: "playlist-1",
      name: "Editorial Mix",
      curatorName: "Apple Music",
      artworkURL: nil,
      tracks: [track]
    )

    let profile = ArchiveProfile.appleMusic(base: .empty, playlists: [playlist], tracks: [])

    XCTAssertEqual(profile.nickname, "")
    XCTAssertEqual(profile.bio, "")
  }

  func testArchiveProfileKeepsManualNicknameAndBio() {
    var baseProfile = ArchiveProfile.empty
    baseProfile.nickname = "Manual Name"
    baseProfile.bio = "Manual intro"
    let track = makeTrack(
      appleMusicID: "song-1",
      title: "Personal Song",
      artist: "Artist A",
      album: "Album A",
      duration: 180,
      artworkURL: nil
    )
    let playlist = AppleMusicPlaylistSnapshot(
      id: "playlist-1",
      name: "Personal Mix",
      curatorName: "Ada Chen",
      artworkURL: nil,
      tracks: [track]
    )

    let profile = ArchiveProfile.appleMusic(base: baseProfile, playlists: [playlist], tracks: [])

    XCTAssertEqual(profile.nickname, "Manual Name")
    XCTAssertEqual(profile.bio, "Manual intro")
  }

  func testArchiveProfileUsesLibrarySummaryWhenNoPlaylistsExist() {
    let track = makeTrack(
      appleMusicID: "song-1",
      title: "Loose Song",
      artist: "Artist A",
      album: "Singles",
      duration: 180,
      artworkURL: URL(string: "https://example.com/song.jpg")
    )

    let profile = ArchiveProfile.appleMusic(base: .empty, playlists: [], tracks: [track])

    XCTAssertEqual(profile.stats.stationsCount, 0)
    XCTAssertEqual(profile.stats.likesCount, 1)
    XCTAssertEqual(profile.published.first?.name, "Apple Music Library")
    XCTAssertEqual(profile.published.first?.artworkURL, track.artworkURL)
    XCTAssertEqual(profile.recentlyPlayed.first?.name, "Loose Song")
  }

  private func makeTrack(
    appleMusicID: String,
    title: String,
    artist: String,
    album: String,
    duration: TimeInterval,
    artworkURL: URL?
  ) -> Track {
    Track(
      title: title,
      artist: artist,
      album: album,
      mood: "Library",
      duration: duration,
      artworkSystemName: "music.note",
      artworkURL: artworkURL,
      appleMusicID: appleMusicID
    )
  }
}
