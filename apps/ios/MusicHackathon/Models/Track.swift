import Foundation

struct Track: Identifiable, Hashable, Codable {
  let id: UUID
  let title: String
  let artist: String
  let album: String
  let mood: String
  let duration: TimeInterval
  let artworkSystemName: String
  let artworkURL: URL?
  let previewURL: URL?
  let appleMusicID: String?
  let isExplicit: Bool
  let playlistName: String?
  let source: String?
  let sourceLane: String?
  let sourceScore: Double?
  let reasonSignals: [String]?

  init(
    id: UUID = UUID(),
    title: String,
    artist: String,
    album: String,
    mood: String,
    duration: TimeInterval,
    artworkSystemName: String,
    artworkURL: URL? = nil,
    previewURL: URL? = nil,
    appleMusicID: String? = nil,
    isExplicit: Bool = false,
    playlistName: String? = nil,
    source: String? = nil,
    sourceLane: String? = nil,
    sourceScore: Double? = nil,
    reasonSignals: [String]? = nil
  ) {
    self.id = id
    self.title = title
    self.artist = artist
    self.album = album
    self.mood = mood
    self.duration = duration
    self.artworkSystemName = artworkSystemName
    self.artworkURL = artworkURL
    self.previewURL = previewURL
    self.appleMusicID = appleMusicID
    self.isExplicit = isExplicit
    self.playlistName = playlistName
    self.source = source
    self.sourceLane = sourceLane
    self.sourceScore = sourceScore
    self.reasonSignals = reasonSignals
  }

  var normalizedAppleMusicID: String? {
    appleMusicID?.trimmedNilIfEmpty
  }

  var isAppleMusicTrack: Bool {
    normalizedAppleMusicID != nil
  }

  var isPlayable: Bool {
    normalizedAppleMusicID != nil || previewURL != nil
  }

  var hasRealArtwork: Bool {
    ArtworkURLCandidates.normalized(artworkURL) != nil
  }

  var durationText: String {
    let totalSeconds = Int(duration)
    return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
  }

  func withAppleMusicMetadata(
    id appleMusicID: String,
    artworkURL: URL?,
    previewURL: URL?,
    duration: TimeInterval?,
    isExplicit: Bool
  ) -> Track {
    Track(
      id: id,
      title: title,
      artist: artist,
      album: album,
      mood: mood,
      duration: duration ?? self.duration,
      artworkSystemName: artworkSystemName,
      artworkURL: artworkURL ?? self.artworkURL,
      previewURL: previewURL ?? self.previewURL,
      appleMusicID: appleMusicID,
      isExplicit: isExplicit,
      playlistName: playlistName,
      source: source,
      sourceLane: sourceLane,
      sourceScore: sourceScore,
      reasonSignals: reasonSignals
    )
  }
}

private extension String {
  var trimmedNilIfEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
