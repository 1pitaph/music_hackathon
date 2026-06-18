import Foundation

struct Track: Identifiable, Hashable {
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
    isExplicit: Bool = false
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
  }

  var isAppleMusicTrack: Bool {
    appleMusicID != nil
  }

  var isPlayable: Bool {
    appleMusicID != nil || previewURL != nil
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
      isExplicit: isExplicit
    )
  }
}
