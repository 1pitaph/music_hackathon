import Foundation

protocol RadioContextBuilding {
  func build(
    seedTracks: [RadioSeedTrack],
    memory: RadioMemory,
    tuning: RadioTuning,
    action: RadioRuntimeAction
  ) async -> RadioRuntimeContext
}

struct RadioContextBuilder: RadioContextBuilding {
  private let catalogService: AppleMusicCatalogService

  init(catalogService: AppleMusicCatalogService = AppleMusicCatalogService()) {
    self.catalogService = catalogService
  }

  func build(
    seedTracks: [RadioSeedTrack],
    memory: RadioMemory,
    tuning: RadioTuning,
    action: RadioRuntimeAction
  ) async -> RadioRuntimeContext {
    let relatedTracks = await catalogService.relatedTracks(
      for: seedTracks.map(\.track),
      limit: max(12, Int(Double(seedTracks.count) * 0.35))
    )

    let catalogCandidates = relatedTracks.map { track in
      RadioQueueItem(
        track: track,
        source: .catalog(term: catalogTerm(for: track, seedTracks: seedTracks)),
        score: 0,
        reason: ""
      )
    }

    return RadioRuntimeContext(
      seedTracks: seedTracks,
      catalogCandidates: catalogCandidates,
      memory: memory,
      tuning: tuning,
      currentAction: action
    )
  }

  private func catalogTerm(for track: Track, seedTracks: [RadioSeedTrack]) -> String {
    if seedTracks.contains(where: { $0.track.artist.caseInsensitiveCompare(track.artist) == .orderedSame }) {
      return track.artist
    }

    if let seedMood = seedTracks.first(where: { !$0.track.mood.isEmpty })?.track.mood {
      return seedMood
    }

    return "Apple Music"
  }
}
