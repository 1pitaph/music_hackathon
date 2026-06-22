import Foundation

protocol DJNarrationProvider {
  func stationIntro(for context: RadioRuntimeContext) -> String
  func reason(for item: RadioQueueItem, context: RadioRuntimeContext) -> String
}

struct LocalDJNarrationProvider: DJNarrationProvider {
  func stationIntro(for context: RadioRuntimeContext) -> String {
    let playlistCount = Set(context.seedTracks.map(\.playlistID)).count
    if playlistCount > 1 {
      return "Blending \(playlistCount) playlists into a personal radio set."
    }

    if let playlistName = context.seedTracks.first?.playlistName {
      return "Tuned from \(playlistName), with a little room for discovery."
    }

    return "Ready to tune your Apple Music library into radio."
  }

  func reason(for item: RadioQueueItem, context: RadioRuntimeContext) -> String {
    let track = item.track

    switch item.source {
    case let .playlist(_, name):
      if context.memory.likedTrackKeys.contains(track.radioIdentity) {
        return "Back in rotation because you liked it from \(name)."
      }
      return "Pulled from \(name), close to your selected library seed."
    case let .catalog(term):
      return "A catalog discovery matched from \(term), near \(track.artist)'s lane."
    case .fallback:
      return "Local preview fallback while Apple Music warms up."
    }
  }
}
