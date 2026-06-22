import SwiftUI

@main
struct MusicHackathonApp: App {
  @State private var playbackController: PlaybackController
  @State private var radioStationController: RadioStationController
  @State private var musicAuthorization = MusicAuthorizationService()

  init() {
    let playbackController = PlaybackController()
    _playbackController = State(initialValue: playbackController)
    _radioStationController = State(initialValue: RadioStationController(playbackController: playbackController))
  }

  var body: some Scene {
    WindowGroup {
      AppView()
        .environment(playbackController)
        .environment(radioStationController)
        .environment(musicAuthorization)
    }
  }
}
