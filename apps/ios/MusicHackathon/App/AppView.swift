import FluidGradient
import SwiftUI

struct AppView: View {
  @Environment(PlaybackController.self) private var playbackController
  @Environment(RadioStationController.self) private var radioStation
  @Environment(MusicAuthorizationService.self) private var musicAuthorization
  @Environment(AppleMusicLibraryStore.self) private var appleMusicLibrary
  @Environment(ImageAssetStore.self) private var imageAssetStore
  @Environment(\.scenePhase) private var scenePhase

  @State private var selectedTab: AppTab = .radio
  @State private var isPlayerPresented = false

  var body: some View {
    tabView
      .tint(.cyan)
      .preferredColorScheme(.dark)
      .sheet(isPresented: $isPlayerPresented) {
        PlayerView(showsPresentationHandle: false)
          .presentationDetents([.playerExpanded])
          .presentationDragIndicator(.visible)
          .presentationCompactAdaptation(.sheet)
      }
      .task {
        await musicAuthorization.refreshAccessState()
        await appleMusicLibrary.loadIfNeeded(authorizationStatus: musicAuthorization.status)
      }
      .onChange(of: scenePhase) { _, phase in
        guard phase == .active else { return }
        Task {
          await musicAuthorization.refreshAccessState()
          await appleMusicLibrary.loadIfNeeded(authorizationStatus: musicAuthorization.status)
        }
      }
  }

  @ViewBuilder
  private var tabView: some View {
    if #available(iOS 26.1, *) {
      systemTabView
        .tabBarMinimizeBehavior(.never)
        .tabViewBottomAccessory(isEnabled: showsGlobalPlayer) {
          globalMiniPlayer
            .padding(.horizontal, 12)
        }
    } else if #available(iOS 26.0, *) {
      systemTabView
        .tabBarMinimizeBehavior(.never)
        .safeAreaInset(edge: .bottom) {
          globalMiniPlayerInset
        }
    } else {
      systemTabView
        .safeAreaInset(edge: .bottom) {
          globalMiniPlayerInset
        }
    }
  }

  private var systemTabView: some View {
    TabView(selection: $selectedTab) {
      ForEach(AppTab.allCases) { tab in
        NavigationStack {
          ZStack {
            AppBackdrop()
              .ignoresSafeArea()

            tab.content
          }
          .navigationTitle(tab.navigationTitle)
          .toolbar(tab.prefersHiddenNavigationBar ? .hidden : .automatic, for: .navigationBar)
        }
        .tabItem { tab.label }
        .tag(tab)
      }
    }
  }

  private var showsGlobalPlayer: Bool {
    playbackController.currentTrack != nil || playbackController.currentSpeech != nil
  }

  private var miniPlayerTitle: String {
    playbackController.currentTrack?.title ?? radioStation.stationTitle
  }

  private var miniPlayerSubtitle: String {
    playbackController.currentSpeech?.displayText
      ?? playbackController.currentTrack?.artist
      ?? radioStation.stationIntro
  }

  private var miniPlayerArtworkURLs: [URL?] {
    [
      playbackController.currentTrack?.artworkURL,
      radioStation.currentItem?.track.artworkURL
    ]
  }

  private var miniPlayerFallbackSeed: String {
    playbackController.currentTrack?.title
      ?? playbackController.currentSpeech?.id
      ?? radioStation.station?.id
      ?? radioStation.stationTitle
  }

  @ViewBuilder
  private var globalMiniPlayerInset: some View {
    if showsGlobalPlayer {
      globalMiniPlayer
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
  }

  private var globalMiniPlayer: some View {
    GlobalMiniPlayer(
      title: miniPlayerTitle,
      subtitle: miniPlayerSubtitle,
      artworkResolution: miniPlayerArtworkResolution,
      fallbackSeed: miniPlayerFallbackSeed,
      isPlaying: playbackController.state == .playing,
      isLoading: playbackController.state == .loading,
      onOpenPlayer: {
        isPlayerPresented = true
      },
      onTogglePlay: {
        playbackController.togglePlayback()
      },
      onNext: {
        Task {
          await radioStation.playNext(reason: .manual)
        }
      }
    )
  }

  private var miniPlayerArtworkResolution: ArtworkResolution {
    let stationID = radioStation.station?.id ?? radioStation.stationTitle
    let hasRemoteArtwork = miniPlayerArtworkURLs.compactMap { $0 }.isEmpty == false
    let fallbackSource = BundledCoverCatalog.fallbackSource(
      forID: stationID,
      title: radioStation.stationTitle,
      genre: nil
    )

    return ArtworkResolution(
      overrideSource: hasRemoteArtwork
        ? nil
        : (radioStation.station.flatMap { imageAssetStore.coverSource(for: $0.id) } ?? imageAssetStore.profileAvatarSource),
      remoteURLs: miniPlayerArtworkURLs,
      bundledFallback: fallbackSource,
      fallbackSeed: miniPlayerFallbackSeed,
      fallbackTitle: miniPlayerTitle,
      fallbackColorHex: "#D9523A"
    )
  }
}

private struct PlayerExpandedDetent: CustomPresentationDetent {
  static func height(in context: Context) -> CGFloat? {
    max(360, context.maxDetentValue - 12)
  }
}

private extension PresentationDetent {
  static let playerExpanded = Self.custom(PlayerExpandedDetent.self)
}

private struct GlobalMiniPlayer: View {
  let title: String
  let subtitle: String
  let artworkResolution: ArtworkResolution
  let fallbackSeed: String
  let isPlaying: Bool
  let isLoading: Bool
  let onOpenPlayer: () -> Void
  let onTogglePlay: () -> Void
  let onNext: () -> Void

  private let accentColor = Color(hex: "#D9523A")

  var body: some View {
    content
  }

  private var content: some View {
    HStack(spacing: 10) {
      playableInfo
        .layoutPriority(1)

      controls
    }
    .padding(.leading, 8)
    .padding(.trailing, 7)
    .frame(height: 58)
    .frame(maxWidth: .infinity)
  }

  private var playableInfo: some View {
    HStack(spacing: 10) {
      artwork
      trackText
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .onTapGesture(perform: onOpenPlayer)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(title), \(subtitle)")
    .accessibilityAddTraits(.isButton)
    .accessibilityAction {
      onOpenPlayer()
    }
  }

  private var artwork: some View {
    ArtworkImageView(resolution: artworkResolution, showsLoadingIndicator: false) {
      ZStack {
        LinearGradient(
          colors: [
            accentColor.opacity(0.85),
            Color(hex: "#3F2630")
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )

        MarbleAvatarView(
          seed: fallbackSeed,
          size: 36,
          palette: ["#F6A46D", "#D9523A", "#7BC9C8", "#40232F"],
          accessibilityLabel: nil
        )
      }
    }
    .frame(width: 42, height: 42)
    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .stroke(.white.opacity(0.12), lineWidth: 1)
    }
    .accessibilityHidden(true)
  }

  private var trackText: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.system(size: 14, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .lineLimit(1)
        .truncationMode(.tail)

      Text(subtitle)
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(.white.opacity(0.62))
        .lineLimit(1)
        .truncationMode(.tail)
    }
    .frame(minWidth: 72, maxWidth: .infinity, alignment: .leading)
    .layoutPriority(1)
  }

  private var controls: some View {
    HStack(spacing: 6) {
      controlButton(
        systemImage: isLoading ? "hourglass" : (isPlaying ? "pause.fill" : "play.fill"),
        accessibilityLabel: isLoading ? "正在加载" : (isPlaying ? "暂停" : "播放"),
        prominent: true,
        action: onTogglePlay
      )
      .disabled(isLoading)

      controlButton(
        systemImage: "forward.fill",
        accessibilityLabel: "下一首",
        prominent: false,
        action: onNext
      )
    }
    .frame(width: 84, alignment: .trailing)
  }

  private func controlButton(
    systemImage: String,
    accessibilityLabel: String,
    prominent: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: prominent ? 16 : 14, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: prominent ? 42 : 36, height: prominent ? 42 : 36)
    }
    .buttonStyle(.plain)
    .contentShape(Circle())
    .accessibilityLabel(accessibilityLabel)
  }
}

private struct AppBackdrop: View {
  var body: some View {
    ZStack {
      FluidGradient(
        blobs: [
          Color(red: 0.04, green: 0.36, blue: 0.42),
          Color(red: 0.68, green: 0.44, blue: 0.24),
          Color(red: 0.34, green: 0.13, blue: 0.26),
          Color(red: 0.05, green: 0.09, blue: 0.17)
        ],
        highlights: [
          Color(red: 0.46, green: 0.78, blue: 0.78),
          Color(red: 0.88, green: 0.58, blue: 0.30),
          Color(red: 0.57, green: 0.22, blue: 0.36)
        ],
        speed: 0.35,
        blur: 0.78
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(red: 0.05, green: 0.04, blue: 0.03))

      LinearGradient(
        colors: [
          .white.opacity(0.08),
          .clear,
          .black.opacity(0.58)
        ],
        startPoint: .top,
        endPoint: .bottom
      )

      LinearGradient(
        colors: [
          .clear,
          Color(red: 0.11, green: 0.05, blue: 0.03).opacity(0.68)
        ],
        startPoint: .center,
        endPoint: .bottom
      )
    }
  }
}

#Preview {
  let playbackController = PlaybackController()
  AppView()
    .environment(playbackController)
    .environment(RadioStationController(playbackController: playbackController))
    .environment(MusicAuthorizationService())
    .environment(AppleMusicLibraryStore())
    .environment(DiagnosticsStore.preview())
    .environment(ImageAssetStore())
    .environment(ArtworkAnalysisStore())
}
