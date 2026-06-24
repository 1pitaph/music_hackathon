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
}
