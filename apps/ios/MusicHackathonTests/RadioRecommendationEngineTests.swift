import XCTest
@testable import MusicHackathon

final class RadioRecommendationEngineTests: XCTestCase {
  func testDeduplicatesLibraryTracksByAppleMusicID() {
    let duplicateA = makeTrack(title: "Future", artist: "WRABEL", appleMusicID: "123")
    let duplicateB = makeTrack(title: "Future Again", artist: "WRABEL", appleMusicID: "123")
    let context = makeContext(seedTracks: [
      makeSeed(track: duplicateA),
      makeSeed(track: duplicateB)
    ])

    let queue = RadioRecommendationEngine().makeQueue(from: context, limit: 5)

    XCTAssertEqual(queue.count, 1)
    XCTAssertEqual(queue.first?.track.appleMusicID, "123")
  }

  func testUsesBalancedLibraryAndCatalogMix() {
    let seedTracks = (0..<10).map { index in
      makeSeed(track: makeTrack(title: "Library \(index)", artist: "Artist \(index)"))
    }
    let catalogCandidates = (0..<10).map { index in
      RadioQueueItem(
        track: makeTrack(title: "Discovery \(index)", artist: "Catalog \(index)", appleMusicID: "catalog-\(index)"),
        source: .catalog(term: "Discovery"),
        score: 0,
        reason: ""
      )
    }
    let context = makeContext(seedTracks: seedTracks, catalogCandidates: catalogCandidates)

    let queue = RadioRecommendationEngine().makeQueue(from: context, limit: 10)
    let catalogCount = queue.filter { $0.source.isCatalogDiscovery }.count

    XCTAssertEqual(queue.count, 10)
    XCTAssertEqual(catalogCount, 3)
  }

  func testFeedbackAffectsRanking() {
    let liked = makeTrack(title: "Liked", artist: "A", appleMusicID: "liked")
    let skipped = makeTrack(title: "Skipped", artist: "B", appleMusicID: "skipped")
    let disliked = makeTrack(title: "Disliked", artist: "C", appleMusicID: "disliked")
    var memory = RadioMemory()
    memory.recordLike(trackKey: liked.radioIdentity)
    memory.recordSkip(trackKey: skipped.radioIdentity)
    memory.recordDislike(trackKey: disliked.radioIdentity)

    let context = makeContext(
      seedTracks: [liked, skipped, disliked].map(makeSeed),
      memory: memory
    )

    let queue = RadioRecommendationEngine().makeQueue(from: context, limit: 3)

    XCTAssertEqual(queue.first?.track.radioIdentity, liked.radioIdentity)
    XCTAssertEqual(queue.last?.track.radioIdentity, disliked.radioIdentity)
  }

  func testAvoidsAdjacentSameArtistWhenAlternativesExist() {
    let context = makeContext(seedTracks: [
      makeSeed(track: makeTrack(title: "A One", artist: "Same")),
      makeSeed(track: makeTrack(title: "A Two", artist: "Same")),
      makeSeed(track: makeTrack(title: "B One", artist: "Other"))
    ])

    let queue = RadioRecommendationEngine().makeQueue(from: context, limit: 3)

    XCTAssertEqual(queue.count, 3)
    XCTAssertNotEqual(queue[0].track.artist, queue[1].track.artist)
  }

  private func makeContext(
    seedTracks: [RadioSeedTrack],
    catalogCandidates: [RadioQueueItem] = [],
    memory: RadioMemory = RadioMemory()
  ) -> RadioRuntimeContext {
    RadioRuntimeContext(
      seedTracks: seedTracks,
      catalogCandidates: catalogCandidates,
      memory: memory,
      tuning: RadioTuning(),
      currentAction: .start
    )
  }

  private func makeSeed(track: Track) -> RadioSeedTrack {
    RadioSeedTrack(track: track, playlistID: "playlist", playlistName: "Playlist")
  }

  private func makeTrack(
    title: String,
    artist: String,
    mood: String = "Pop",
    appleMusicID: String? = nil
  ) -> Track {
    Track(
      title: title,
      artist: artist,
      album: "Album",
      mood: mood,
      duration: 210,
      artworkSystemName: "music.note",
      appleMusicID: appleMusicID
    )
  }
}
