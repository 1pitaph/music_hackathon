import Foundation

struct RadioRecommendationEngine {
  private let narrationProvider: DJNarrationProvider

  init(narrationProvider: DJNarrationProvider = LocalDJNarrationProvider()) {
    self.narrationProvider = narrationProvider
  }

  func makeQueue(from context: RadioRuntimeContext, limit: Int = 12) -> [RadioQueueItem] {
    let normalizedTuning = context.tuning.normalized
    let libraryTarget = max(0, limit - Int((Double(limit) * normalizedTuning.discoveryRatio).rounded()))
    let catalogTarget = max(0, limit - libraryTarget)
    let profile = TasteProfile(seedTracks: context.seedTracks.map(\.track))

    let libraryCandidates = uniqueLibraryCandidates(from: context.seedTracks)
      .map { scoredItem(for: $0.track, source: .playlist(id: $0.playlistID, name: $0.playlistName), context: context, profile: profile) }
      .sorted(by: rankedBefore)

    let libraryKeys = Set(libraryCandidates.map { $0.track.radioIdentity })
    let catalogCandidates = context.catalogCandidates
      .filter { !libraryKeys.contains($0.track.radioIdentity) }
      .map { scoredItem(for: $0.track, source: $0.source, context: context, profile: profile) }
      .sorted(by: rankedBefore)

    var selected = Array(libraryCandidates.prefix(libraryTarget))
    selected.append(contentsOf: catalogCandidates.prefix(catalogTarget))

    if selected.count < limit {
      let selectedKeys = Set(selected.map { $0.track.radioIdentity })
      let fallback = (libraryCandidates + catalogCandidates)
        .filter { !selectedKeys.contains($0.track.radioIdentity) }
        .prefix(limit - selected.count)
      selected.append(contentsOf: fallback)
    }

    return distributeArtists(selected.sorted(by: rankedBefore))
      .prefix(limit)
      .map { item in
        guard item.reason.isEmpty else { return item }
        return RadioQueueItem(
          track: item.track,
          source: item.source,
          score: item.score,
          reason: narrationProvider.reason(for: item, context: context)
        )
      }
  }

  private func uniqueLibraryCandidates(from seedTracks: [RadioSeedTrack]) -> [RadioSeedTrack] {
    var seenKeys: Set<String> = []
    var result: [RadioSeedTrack] = []

    for seedTrack in seedTracks {
      let key = seedTrack.track.radioIdentity
      guard !seenKeys.contains(key) else { continue }
      seenKeys.insert(key)
      result.append(seedTrack)
    }

    return result
  }

  private func scoredItem(
    for track: Track,
    source: RadioQueueSource,
    context: RadioRuntimeContext,
    profile: TasteProfile
  ) -> RadioQueueItem {
    let key = track.radioIdentity
    var score = source.isCatalogDiscovery ? 44.0 : 64.0

    if context.memory.likedTrackKeys.contains(key) {
      score += 42
    }

    if context.memory.skippedTrackKeys.contains(key) {
      score -= 26
    }

    if context.memory.dislikedTrackKeys.contains(key) {
      score -= 160
    }

    if let recentIndex = context.memory.recentlyPlayedTrackKeys.firstIndex(of: key) {
      score -= max(10, 32 - Double(recentIndex * 4))
    }

    score += min(Double(profile.artistCounts[track.artist.radioScoreKey] ?? 0) * 7, 28)
    score += min(Double(profile.moodCounts[track.mood.radioScoreKey] ?? 0) * 4, 16)
    score += min(Double(profile.albumCounts[track.album.radioScoreKey] ?? 0) * 3, 12)

    if source.isCatalogDiscovery {
      score += (1 - context.tuning.familiarity) * 20
    } else {
      score += context.tuning.familiarity * 10
    }

    if track.duration > 0 {
      let radioLength = abs(track.duration - 210)
      score += max(0, 10 - (radioLength / 24))
    }

    let item = RadioQueueItem(track: track, source: source, score: score, reason: "")
    return RadioQueueItem(
      track: track,
      source: source,
      score: score,
      reason: narrationProvider.reason(for: item, context: context)
    )
  }

  private func rankedBefore(_ lhs: RadioQueueItem, _ rhs: RadioQueueItem) -> Bool {
    if lhs.score != rhs.score {
      return lhs.score > rhs.score
    }

    if lhs.source.isCatalogDiscovery != rhs.source.isCatalogDiscovery {
      return !lhs.source.isCatalogDiscovery
    }

    if lhs.track.artist != rhs.track.artist {
      return lhs.track.artist.localizedCaseInsensitiveCompare(rhs.track.artist) == .orderedAscending
    }

    return lhs.track.title.localizedCaseInsensitiveCompare(rhs.track.title) == .orderedAscending
  }

  private func distributeArtists(_ items: [RadioQueueItem]) -> [RadioQueueItem] {
    var remaining = items
    var result: [RadioQueueItem] = []
    var previousArtist: String?

    while !remaining.isEmpty {
      let preferredIndex = remaining.firstIndex { item in
        item.track.artist.radioScoreKey != previousArtist
      } ?? remaining.startIndex

      let next = remaining.remove(at: preferredIndex)
      result.append(next)
      previousArtist = next.track.artist.radioScoreKey
    }

    return result
  }
}

private struct TasteProfile {
  let artistCounts: [String: Int]
  let moodCounts: [String: Int]
  let albumCounts: [String: Int]

  init(seedTracks: [Track]) {
    artistCounts = Self.counts(seedTracks.map(\.artist))
    moodCounts = Self.counts(seedTracks.map(\.mood))
    albumCounts = Self.counts(seedTracks.map(\.album))
  }

  private static func counts(_ values: [String]) -> [String: Int] {
    values.reduce(into: [:]) { result, value in
      result[value.radioScoreKey, default: 0] += 1
    }
  }
}

private extension String {
  var radioScoreKey: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
  }
}
