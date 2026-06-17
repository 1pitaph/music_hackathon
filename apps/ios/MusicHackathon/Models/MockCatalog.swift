import Foundation

enum MockCatalog {
  static let featuredTracks: [Track] = [
    Track(
      title: "future",
      artist: "WRABEL",
      album: "up up above",
      mood: "Pop Surrealism",
      duration: 900,
      artworkSystemName: "waveform"
    ),
    Track(
      title: "birds & the bees",
      artist: "WRABEL",
      album: "up up above",
      mood: "Glowing",
      duration: 221,
      artworkSystemName: "music.quarternote.3"
    ),
    Track(
      title: "beautiful chaos",
      artist: "WRABEL",
      album: "up up above",
      mood: "Cinematic",
      duration: 236,
      artworkSystemName: "record.circle"
    )
  ]

  static let playlists: [String] = [
    "Morning queue",
    "Tracks to revisit",
    "Practice room",
    "Weekend discoveries"
  ]
}
