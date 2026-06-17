import Foundation

struct Track: Identifiable, Hashable {
  let id: UUID
  let title: String
  let artist: String
  let album: String
  let mood: String
  let duration: TimeInterval
  let artworkSystemName: String
  let previewURL: URL?

  init(
    id: UUID = UUID(),
    title: String,
    artist: String,
    album: String,
    mood: String,
    duration: TimeInterval,
    artworkSystemName: String,
    previewURL: URL? = nil
  ) {
    self.id = id
    self.title = title
    self.artist = artist
    self.album = album
    self.mood = mood
    self.duration = duration
    self.artworkSystemName = artworkSystemName
    self.previewURL = previewURL
  }

  var durationText: String {
    let totalSeconds = Int(duration)
    return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
  }
}
