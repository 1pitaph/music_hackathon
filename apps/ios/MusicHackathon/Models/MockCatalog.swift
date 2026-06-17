import Foundation

enum MockCatalog {
  static let featuredTracks: [Track] = [
    Track(
      title: "Afterglow Sketch",
      artist: "North Pier",
      album: "Late Signals",
      mood: "Focus",
      duration: 214,
      artworkSystemName: "waveform"
    ),
    Track(
      title: "Glass Roads",
      artist: "Mira Vale",
      album: "City Tempo",
      mood: "Commute",
      duration: 188,
      artworkSystemName: "music.quarternote.3"
    ),
    Track(
      title: "Low Sun Loop",
      artist: "Tape Garden",
      album: "Small Hours",
      mood: "Unwind",
      duration: 241,
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
