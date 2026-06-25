import SwiftUI

@main
struct MusicHackathonApp: App {
  @State private var playbackController: PlaybackController
  @State private var radioStationController: RadioStationController
  @State private var musicAuthorization: MusicAuthorizationService
  @State private var appleMusicLibraryStore: AppleMusicLibraryStore
  @State private var diagnostics: DiagnosticsStore

  init() {
    let diagnostics = DiagnosticsStore()
    let musicAuthorization = MusicAuthorizationService(diagnostics: diagnostics)
    let playbackController = PlaybackController(musicAuthorization: musicAuthorization, diagnostics: diagnostics)
    let appleMusicLibraryStore = AppleMusicLibraryStore(diagnostics: diagnostics)
    _musicAuthorization = State(initialValue: musicAuthorization)
    _playbackController = State(initialValue: playbackController)
    _appleMusicLibraryStore = State(initialValue: appleMusicLibraryStore)
    _diagnostics = State(initialValue: diagnostics)
    _radioStationController = State(
      initialValue: RadioStationController(
        playbackController: playbackController,
        stationClient: RadioStationClient(diagnostics: diagnostics),
        diagnostics: diagnostics,
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
        .environment(diagnostics)
    }
  }
}
