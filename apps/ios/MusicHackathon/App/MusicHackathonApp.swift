import SwiftUI

@main
struct MusicHackathonApp: App {
  @State private var playbackController: PlaybackController
  @State private var radioStationController: RadioStationController
  @State private var musicAuthorization: MusicAuthorizationService
  @State private var appleMusicLibraryStore: AppleMusicLibraryStore
  @State private var discoverStationStore: DiscoverStationStore
  @State private var diagnostics: DiagnosticsStore
  @State private var imageAssetStore: ImageAssetStore
  @State private var artworkAnalysisStore: ArtworkAnalysisStore

  init() {
    AppLanguage.applyStoredPreference()

    let diagnostics = DiagnosticsStore()
    let musicAuthorization = MusicAuthorizationService(diagnostics: diagnostics)
    let playbackController = PlaybackController(musicAuthorization: musicAuthorization, diagnostics: diagnostics)
    let appleMusicLibraryStore = AppleMusicLibraryStore(diagnostics: diagnostics)
    let radioStationClient = RadioStationClient(diagnostics: diagnostics)
    let discoverStationStore = DiscoverStationStore(client: radioStationClient)
    let imageAssetStore = ImageAssetStore()
    let artworkAnalysisStore = ArtworkAnalysisStore()
    _musicAuthorization = State(initialValue: musicAuthorization)
    _playbackController = State(initialValue: playbackController)
    _appleMusicLibraryStore = State(initialValue: appleMusicLibraryStore)
    _discoverStationStore = State(initialValue: discoverStationStore)
    _diagnostics = State(initialValue: diagnostics)
    _imageAssetStore = State(initialValue: imageAssetStore)
    _artworkAnalysisStore = State(initialValue: artworkAnalysisStore)
    _radioStationController = State(
      initialValue: RadioStationController(
        playbackController: playbackController,
        stationClient: radioStationClient,
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
        .environment(discoverStationStore)
        .environment(diagnostics)
        .environment(imageAssetStore)
        .environment(artworkAnalysisStore)
    }
  }
}
