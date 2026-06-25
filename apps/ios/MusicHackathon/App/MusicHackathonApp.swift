import SwiftUI

@main
struct MusicHackathonApp: App {
  @State private var playbackController: PlaybackController
  @State private var radioStationController: RadioStationController
  @State private var musicAuthorization: MusicAuthorizationService
  @State private var appleMusicLibraryStore: AppleMusicLibraryStore

  init() {
    let musicAuthorization = MusicAuthorizationService()
    let playbackController = PlaybackController(musicAuthorization: musicAuthorization)
    let appleMusicLibraryStore = AppleMusicLibraryStore()
    _musicAuthorization = State(initialValue: musicAuthorization)
    _playbackController = State(initialValue: playbackController)
    _appleMusicLibraryStore = State(initialValue: appleMusicLibraryStore)
    _radioStationController = State(
      initialValue: RadioStationController(
        playbackController: playbackController,
        libraryTrackProvider: {
          appleMusicLibraryStore.candidateTracksForRadio()
        }
      )
    )
  }

  var body: some Scene {
    WindowGroup {
      AppView()
        .environment(playbackController)
        .environment(radioStationController)
        .environment(musicAuthorization)
        .environment(appleMusicLibraryStore)
    }
  }
}
