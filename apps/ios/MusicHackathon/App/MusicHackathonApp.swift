import SwiftUI

@main
struct MusicHackathonApp: App {
  @State private var playbackController = PlaybackController()
  @State private var musicAuthorization = MusicAuthorizationService()

  var body: some Scene {
    WindowGroup {
      AppView()
        .environment(playbackController)
        .environment(musicAuthorization)
    }
  }
}
