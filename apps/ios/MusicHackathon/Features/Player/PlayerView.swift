import MediaPlayer
import SwiftUI

struct PlayerView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(PlaybackController.self) private var playbackController
  @Environment(RadioStationController.self) private var radioStation
  @Environment(ArtworkAnalysisStore.self) private var analysisStore

  let showsPresentationHandle: Bool

  @State private var presentedSheet: PlayerSheet?
  @GestureState private var verticalDragOffset: CGFloat = 0

  private var accentColor: Color {
    Color(hex: activeArtworkAnalysis?.dominantHex ?? "#D9523A")
  }

  init(showsPresentationHandle: Bool = true) {
    self.showsPresentationHandle = showsPresentationHandle
  }

  var body: some View {
    GeometryReader { proxy in
      let safeArea = proxy.safeAreaInsets
      let artworkFrame = artworkStageFrame(for: proxy.size)
      let controlsSpacing = controlSpacing(for: proxy.size)
      let controlsClusterSpacing = controlClusterSpacing(for: proxy.size)
      let horizontalPadding = horizontalPadding(for: proxy.size)
      let dragOffset = showsPresentationHandle ? max(0, verticalDragOffset) : 0
      let isLandscape = proxy.size.width > proxy.size.height

      dismissiblePlayerContent(
        ZStack(alignment: .top) {
          PlayerBackgroundSurface(accentColor: accentColor)

          Group {
            if isLandscape {
              HStack(alignment: .center, spacing: 28) {
                artworkStage(size: artworkFrame)

                bottomControls(
                  spacing: controlsSpacing,
                  clusterSpacing: controlsClusterSpacing,
                  anchorsControlClusterToBottom: false
                )
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              .padding(.horizontal, horizontalPadding)
              .padding(.top, max(safeArea.top, 14))
              .padding(.bottom, max(safeArea.bottom, 14))
              .frame(width: proxy.size.width, height: proxy.size.height)
            } else {
              VStack(spacing: 0) {
                artworkStage(size: artworkFrame)
                  .frame(maxWidth: .infinity)
                  .ignoresSafeArea(edges: .top)

                bottomControls(
                  spacing: controlsSpacing,
                  clusterSpacing: controlsClusterSpacing,
                  anchorsControlClusterToBottom: true
                )
                  .padding(.horizontal, horizontalPadding)
                  .padding(.top, -8)
                  .padding(.bottom, bottomControlsBottomPadding(for: safeArea))
                  .frame(maxHeight: .infinity, alignment: .top)
                  .frame(width: proxy.size.width, alignment: .top)
              }
              .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
          }
          .overlay(alignment: .top) {
            if showsPresentationHandle {
              playerHeader
                .padding(.top, max(safeArea.top + 48, 64))
            }
          }
        }
      )
      .frame(width: proxy.size.width, height: proxy.size.height)
      .offset(y: dragOffset)
      .opacity(1 - min(Double(dragOffset / 420), 0.28))
      .accessibilityAction(.escape) {
        dismiss()
      }
    }
    .preferredColorScheme(.dark)
    .sheet(item: $presentedSheet) { sheet in
      playerSheet(sheet)
        .presentationDetents(sheet.detents)
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
        .preferredColorScheme(.dark)
    }
  }

  @ViewBuilder
  private func dismissiblePlayerContent<Content: View>(_ content: Content) -> some View {
    if showsPresentationHandle {
      content.simultaneousGesture(dismissDragGesture)
    } else {
      content
    }
  }

  private var playerHeader: some View {
    Capsule()
      .fill(.white.opacity(0.46))
      .frame(width: 72, height: 6)
      .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
      .accessibilityHidden(true)
  }

  private func artworkStage(size: CGSize) -> some View {
    PlayerArtworkStage(
      artworkResolution: playerArtworkResolution
    )
    .frame(width: size.width, height: size.height)
  }

  private func bottomControls(
    spacing: CGFloat,
    clusterSpacing: CGFloat,
    anchorsControlClusterToBottom: Bool
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      PlayerTrackIdentity(
        title: playbackTitle,
        subtitle: playbackSubtitle,
        isExplicit: playbackController.currentTrack?.isExplicit == true,
        moreAction: {
          presentedSheet = .details
        }
      )

      Spacer()
        .frame(height: spacing)

      PlayerScrubber(
        progress: clampedPlaybackProgress,
        elapsedText: playbackController.elapsedTimeText,
        trailingText: trailingTimeText,
        statusText: playbackStatusText,
        statusIsAlert: playbackController.lastErrorMessage != nil
      )

      if anchorsControlClusterToBottom {
        Spacer(minLength: spacing)
      } else {
        Spacer()
          .frame(height: spacing)
      }

      VStack(alignment: .leading, spacing: clusterSpacing) {
        PlayerTransportControls(
          playButtonSystemImage: playButtonSystemImage,
          playButtonAccessibilityLabel: playButtonAccessibilityLabel,
          isLoading: playbackController.state == .loading,
          playPauseAction: {
            playbackController.togglePlayback()
          },
          nextAction: {
            Task {
              await radioStation.playNext(reason: .manual)
            }
          }
        )

        VolumeControlRow()

        PlayerSecondaryActions(
          lyricsAction: {
            presentedSheet = .lyrics
          },
          routeAction: {
            presentedSheet = .details
          },
          queueAction: {
            presentedSheet = .queue
          }
        )
      }
    }
    .frame(maxWidth: .infinity, maxHeight: anchorsControlClusterToBottom ? .infinity : nil, alignment: .topLeading)
  }

  @ViewBuilder
  private func playerSheet(_ sheet: PlayerSheet) -> some View {
    switch sheet {
    case .queue:
      QueueSheet(
        currentItem: radioStation.currentItem,
        upNextItems: radioStation.upNextItems,
        currentTrack: playbackController.currentTrack
      )
    case .lyrics:
      LyricsSheet(
        currentSpeech: playbackController.currentSpeech,
        currentTrack: playbackController.currentTrack,
        stationTitle: radioStation.stationTitle
      )
    case .details:
      DetailsSheet(
        title: playbackTitle,
        subtitle: playbackSubtitle,
        track: playbackController.currentTrack,
        backendText: playbackBackendText,
        statusText: playbackStatusText
      )
    }
  }

  private func horizontalPadding(for size: CGSize) -> CGFloat {
    size.width > 700 ? 86 : 30
  }

  private func artworkStageFrame(for size: CGSize) -> CGSize {
    if size.width <= size.height {
      return CGSize(
        width: size.width,
        height: min(size.width, size.height * 0.47)
      )
    }

    let sideLength = min(size.height * 0.72, size.width * 0.58)
    return CGSize(width: sideLength, height: sideLength)
  }

  private func controlSpacing(for size: CGSize) -> CGFloat {
    if size.height < 700 {
      return 12
    }

    return size.height < 780 ? 18 : 24
  }

  private func controlClusterSpacing(for size: CGSize) -> CGFloat {
    size.height < 780 ? 20 : 24
  }

  private func bottomControlsBottomPadding(for safeArea: EdgeInsets) -> CGFloat {
    max(24, safeArea.bottom - 10)
  }

  private var dismissDragGesture: some Gesture {
    DragGesture(minimumDistance: 12)
      .updating($verticalDragOffset) { value, state, _ in
        guard value.translation.height > 0,
              abs(value.translation.height) > abs(value.translation.width) else {
          return
        }

        state = min(value.translation.height, 180)
      }
      .onEnded { value in
        let isMostlyVertical = abs(value.translation.height) > abs(value.translation.width)
        let shouldDismiss = value.translation.height > 120 || value.predictedEndTranslation.height > 180

        if isMostlyVertical, shouldDismiss {
          dismiss()
        }
      }
  }

  private var artworkURLs: [URL?] {
    [
      playbackController.currentTrack?.artworkURL,
      radioStation.currentItem?.track.artworkURL
    ]
  }

  private var playerArtworkResolution: ArtworkResolution {
    ArtworkResolution(remoteURLs: artworkURLs)
  }

  private var activeArtworkAnalysis: ArtworkAnalysisResult? {
    if let remoteURL = artworkURLs.compactMap({ $0 }).first,
       let analysis = analysisStore.analysis(for: "remote:\(remoteURL.absoluteString)") {
      return analysis
    }

    return nil
  }

  private var playbackTitle: String {
    playbackController.currentTrack?.title ?? radioStation.stationTitle
  }

  private var playbackSubtitle: String {
    playbackController.currentSpeech?.displayText
      ?? playbackController.currentTrack?.artist
      ?? radioStation.stationIntro
  }

  private var playbackDurationSeconds: TimeInterval? {
    if let currentTrack = playbackController.currentTrack {
      return currentTrack.duration
    }

    if let duration = playbackController.currentSpeech?.audio?.durationSeconds, duration > 0 {
      return duration
    }

    return nil
  }

  private var trailingTimeText: String {
    guard let duration = playbackDurationSeconds, duration > 0 else {
      return "--:--"
    }

    let remaining = duration - playbackController.elapsedSeconds
    guard remaining.isFinite, playbackController.elapsedSeconds > 0 else {
      return Self.timeText(for: duration)
    }

    return "-\(Self.timeText(for: max(0, remaining)))"
  }

  private var clampedPlaybackProgress: Double {
    min(max(playbackController.playbackProgress, 0), 1)
  }

  private var playButtonSystemImage: String {
    if playbackController.state == .loading {
      return "hourglass"
    }

    return playbackController.state == .playing ? "pause.fill" : "play.fill"
  }

  private var playButtonAccessibilityLabel: String {
    if playbackController.state == .loading {
      return L10n.tr("playback.loading")
    }

    return playbackController.state == .playing ? L10n.tr("common.pause") : L10n.tr("common.play")
  }

  private var playbackStatusText: String {
    if let message = playbackController.lastErrorMessage {
      return message
    }

    if playbackController.state == .loading {
      return L10n.tr("playback.loading")
    }

    if let currentTrack = playbackController.currentTrack, !currentTrack.isPlayable {
      return L10n.tr("playback.trackUnavailable")
    }

    switch playbackController.activeBackend {
    case .appleMusic:
      return "Apple Music"
    case .localPreview:
      return L10n.tr("playback.backend.localPreview")
    case .speechAudio, .speechSynthesis:
      return L10n.tr("playback.backend.radioHost")
    case .none:
      return playbackController.state == .idle ? L10n.tr("playback.readyToPlay") : playbackController.state.rawValue.capitalized
    }
  }

  private var playbackBackendText: String {
    switch playbackController.activeBackend {
    case .appleMusic:
      return "Apple Music"
    case .localPreview:
      return L10n.tr("playback.backend.localPreview")
    case .speechAudio:
      return L10n.tr("playback.backend.speechAudio")
    case .speechSynthesis:
      return L10n.tr("playback.backend.speechSynthesis")
    case .none:
      return L10n.tr("playback.backend.none")
    }
  }

  private static func timeText(for seconds: TimeInterval) -> String {
    let totalSeconds = Int(max(0, seconds.rounded(.down)))
    return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
  }
}

private enum PlayerSheet: String, Identifiable {
  case queue
  case lyrics
  case details

  var id: String { rawValue }

  var detents: Set<PresentationDetent> {
    switch self {
    case .queue:
      [.medium, .large]
    case .lyrics, .details:
      [.medium]
    }
  }
}

private struct PlayerBackgroundSurface: View {
  let accentColor: Color

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(hex: "#3B2112"),
          Color(hex: "#22110A"),
          Color(hex: "#0B0705")
        ],
        startPoint: .top,
        endPoint: .bottom
      )

      RadialGradient(
        colors: [
          accentColor.opacity(0.18),
          .clear
        ],
        center: .top,
        startRadius: 20,
        endRadius: 360
      )
      .blendMode(.plusLighter)
    }
    .ignoresSafeArea()
  }
}

private struct PlayerArtworkStage: View {
  let artworkResolution: ArtworkResolution

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .bottom) {
        ArtworkImageView(resolution: artworkResolution, showsLoadingIndicator: false) {
          fallbackArtwork
        }
        .frame(width: proxy.size.width, height: proxy.size.height)
        .clipped()

        ArtworkImageView(resolution: artworkResolution, showsLoadingIndicator: false) {
          fallbackArtwork
        }
        .frame(width: proxy.size.width, height: proxy.size.height)
        .blur(radius: 24)
        .scaleEffect(1.08)
        .clipped()
        .mask {
          LinearGradient(
            stops: [
              .init(color: .clear, location: 0.48),
              .init(color: .black.opacity(0.5), location: 0.74),
              .init(color: .black, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
          )
        }

        LinearGradient(
          stops: [
            .init(color: .clear, location: 0.52),
            .init(color: Color(hex: "#24130B").opacity(0.54), location: 0.82),
            .init(color: Color(hex: "#180D08"), location: 1)
          ],
          startPoint: .top,
          endPoint: .bottom
        )
      }
    }
    .clipped()
    .accessibilityHidden(true)
  }

  private var fallbackArtwork: some View {
    Color.clear
  }
}

private struct PlayerTrackIdentity: View {
  let title: String
  let subtitle: String
  let isExplicit: Bool
  let moreAction: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 18) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          Text(title)
            .font(.system(size: 30, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .fixedSize(horizontal: false, vertical: true)

          if isExplicit {
            Text("E")
              .font(.system(size: 11, weight: .heavy, design: .rounded))
              .foregroundStyle(.black.opacity(0.8))
              .padding(.horizontal, 5)
              .padding(.vertical, 2)
              .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
              .accessibilityLabel(L10n.tr("player.explicit"))
          }
        }

        Text(subtitle)
          .font(.system(size: 24, weight: .medium, design: .rounded))
          .foregroundStyle(.white.opacity(0.62))
          .lineLimit(2)
          .minimumScaleFactor(0.72)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .layoutPriority(1)

      HStack(spacing: 12) {
        CircleIconButton(
          systemImage: "star.fill",
          accessibilityLabel: L10n.tr("player.favoriteUnavailable"),
          size: 21,
          frameSize: 48,
          isEnabled: false,
          action: {}
        )

        CircleIconButton(
          systemImage: "ellipsis",
          accessibilityLabel: L10n.tr("common.more"),
          size: 20,
          frameSize: 48,
          action: moreAction
        )
      }
    }
    .accessibilityElement(children: .combine)
  }
}

private struct PlayerScrubber: View {
  let progress: Double
  let elapsedText: String
  let trailingText: String
  let statusText: String
  let statusIsAlert: Bool

  var body: some View {
    VStack(spacing: 12) {
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule()
            .fill(.white.opacity(0.26))

          Capsule()
            .fill(.white.opacity(0.86))
            .frame(width: max(0, proxy.size.width * progress))
        }
      }
      .frame(height: 6)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(L10n.tr("player.progress"))
      .accessibilityValue("\(Int(progress * 100))%")

      HStack(alignment: .center) {
        Text(elapsedText)
          .frame(width: 64, alignment: .leading)

        Spacer(minLength: 10)

        Text(statusText)
          .font(.system(size: 13, weight: .semibold, design: .rounded))
          .foregroundStyle(statusIsAlert ? Color(hex: "#FFD5C8") : .white.opacity(0.66))
          .lineLimit(1)
          .minimumScaleFactor(0.72)
          .padding(.horizontal, 13)
          .padding(.vertical, 7)
          .background(.white.opacity(statusIsAlert ? 0.14 : 0.1), in: Capsule())

        Spacer(minLength: 10)

        Text(trailingText)
          .frame(width: 64, alignment: .trailing)
      }
      .font(.system(size: 14, weight: .bold, design: .rounded))
      .foregroundStyle(.white.opacity(0.42))
    }
  }
}

private struct PlayerTransportControls: View {
  let playButtonSystemImage: String
  let playButtonAccessibilityLabel: String
  let isLoading: Bool
  let playPauseAction: () -> Void
  let nextAction: () -> Void

  var body: some View {
    HStack {
      Button(action: {}) {
        Image(systemName: "backward.fill")
          .font(.system(size: 34, weight: .bold))
          .foregroundStyle(.white.opacity(0.36))
          .frame(width: 76, height: 62)
      }
      .disabled(true)
      .accessibilityLabel(L10n.tr("player.previousUnavailable"))

      Spacer(minLength: 14)

      Button(action: playPauseAction) {
        Image(systemName: playButtonSystemImage)
          .font(.system(size: isLoading ? 42 : 48, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 80, height: 76)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(isLoading)
      .accessibilityLabel(playButtonAccessibilityLabel)

      Spacer(minLength: 14)

      Button(action: nextAction) {
        Image(systemName: "forward.fill")
          .font(.system(size: 34, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 76, height: 62)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(L10n.tr("player.next"))
    }
    .frame(maxWidth: .infinity)
  }
}

private struct PlayerSecondaryActions: View {
  let lyricsAction: () -> Void
  let routeAction: () -> Void
  let queueAction: () -> Void

  var body: some View {
    HStack {
      SecondaryActionButton(
        systemImage: "quote.bubble",
        accessibilityLabel: L10n.tr("player.lyrics"),
        action: lyricsAction
      )

      Spacer()

      SecondaryActionButton(
        systemImage: "airpodspro",
        accessibilityLabel: L10n.tr("player.details"),
        action: routeAction
      )

      Spacer()

      SecondaryActionButton(
        systemImage: "list.bullet",
        accessibilityLabel: L10n.tr("player.queue"),
        action: queueAction
      )
    }
    .padding(.horizontal, 44)
  }
}

private struct VolumeControlRow: View {
  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: "speaker.fill")
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(.white.opacity(0.56))
        .frame(width: 22)
        .accessibilityHidden(true)

      SystemVolumeSlider()
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .accessibilityLabel(L10n.tr("player.volume"))

      Image(systemName: "speaker.wave.3.fill")
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(.white.opacity(0.56))
        .frame(width: 26)
        .accessibilityHidden(true)
    }
  }
}

private struct CircleIconButton: View {
  let systemImage: String
  let accessibilityLabel: String
  let size: CGFloat
  let frameSize: CGFloat
  var isEnabled = true
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: size, weight: .bold))
        .foregroundStyle(.white.opacity(isEnabled ? 0.96 : 0.48))
        .frame(width: frameSize, height: frameSize)
        .background(.white.opacity(isEnabled ? 0.14 : 0.08), in: Circle())
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
    .accessibilityLabel(accessibilityLabel)
  }
}

private struct SecondaryActionButton: View {
  let systemImage: String
  let accessibilityLabel: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 24, weight: .semibold))
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(.white.opacity(0.64))
        .frame(width: 46, height: 40)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityLabel)
  }
}

private struct SystemVolumeSlider: UIViewRepresentable {
  func makeUIView(context: Context) -> MPVolumeView {
    let volumeView = MPVolumeView(frame: .zero)
    volumeView.showsVolumeSlider = true
    volumeView.tintColor = .white

    if let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first {
      slider.minimumTrackTintColor = UIColor.white.withAlphaComponent(0.72)
      slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.22)
      slider.thumbTintColor = UIColor.white
    }

    hideRouteControls(in: volumeView)
    return volumeView
  }

  func updateUIView(_ uiView: MPVolumeView, context: Context) {
    hideRouteControls(in: uiView)
  }

  private func hideRouteControls(in volumeView: MPVolumeView) {
    for subview in volumeView.subviews where !(subview is UISlider) {
      subview.isHidden = true
      subview.isUserInteractionEnabled = false
    }
  }
}

private struct QueueSheet: View {
  let currentItem: RadioQueueItem?
  let upNextItems: [RadioQueueItem]
  let currentTrack: Track?

  private var visibleCurrentTrack: Track? {
    currentItem?.track ?? currentTrack
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          if let visibleCurrentTrack {
            SheetSectionTitle(L10n.tr("player.nowPlaying"))
            QueueTrackRow(track: visibleCurrentTrack, detail: L10n.tr("player.nowPlaying"))
          }

          SheetSectionTitle(L10n.tr("player.upNext"))

          if upNextItems.isEmpty {
            EmptySheetMessage(
              systemImage: "music.note.list",
              title: L10n.tr("player.queueEmpty.title"),
              message: L10n.tr("player.queueEmpty.message")
            )
          } else {
            VStack(spacing: 12) {
              ForEach(upNextItems) { item in
                QueueTrackRow(track: item.track, detail: item.sourceTitle)
              }
            }
          }
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 34)
      }
      .navigationTitle(L10n.tr("player.queue"))
      .navigationBarTitleDisplayMode(.inline)
      .scrollContentBackground(.hidden)
      .background(Color.clear)
    }
  }
}

private struct LyricsSheet: View {
  let currentSpeech: RadioSpeechPlaybackSegment?
  let currentTrack: Track?
  let stationTitle: String

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if let currentSpeech {
            SheetSectionTitle(speechTitle(for: currentSpeech))

            Text(currentSpeech.text.isEmpty ? currentSpeech.displayText : currentSpeech.text)
              .font(.system(size: 22, weight: .semibold, design: .rounded))
              .foregroundStyle(.white)
              .lineSpacing(5)
              .frame(maxWidth: .infinity, alignment: .leading)
          } else {
            EmptySheetMessage(
              systemImage: "quote.bubble",
              title: L10n.tr("player.lyricsUnavailable.title"),
              message: L10n.tr("player.lyricsUnavailable.message", currentTrack?.title ?? stationTitle)
            )
          }
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .padding(.bottom, 34)
      }
      .navigationTitle(L10n.tr("player.lyrics"))
      .navigationBarTitleDisplayMode(.inline)
      .scrollContentBackground(.hidden)
      .background(Color.clear)
    }
  }

  private func speechTitle(for speech: RadioSpeechPlaybackSegment) -> String {
    switch speech.kind {
    case .stationIntro:
      L10n.tr("radio.subtitle.stationIntro")
    case .transition:
      L10n.tr("radio.subtitle.transitionActive")
    }
  }
}

private struct DetailsSheet: View {
  let title: String
  let subtitle: String
  let track: Track?
  let backendText: String
  let statusText: String

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          VStack(alignment: .leading, spacing: 8) {
            Text(title)
              .font(.system(size: 28, weight: .bold, design: .rounded))
              .foregroundStyle(.white)
              .lineLimit(3)
              .minimumScaleFactor(0.78)

            Text(subtitle)
              .font(.system(size: 18, weight: .semibold, design: .rounded))
              .foregroundStyle(.white.opacity(0.6))
          }

          VStack(spacing: 12) {
            DetailRow(title: L10n.tr("player.detail.status"), value: statusText)
            DetailRow(title: L10n.tr("player.detail.backend"), value: backendText)
            DetailRow(title: L10n.tr("player.detail.album"), value: track?.album ?? L10n.tr("common.unknown"))
            DetailRow(title: L10n.tr("player.detail.source"), value: sourceText)
            DetailRow(title: L10n.tr("player.detail.duration"), value: track?.durationText ?? "--:--")
            DetailRow(title: L10n.tr("player.detail.playable"), value: track?.isPlayable == true ? L10n.tr("common.yes") : L10n.tr("common.no"))
          }
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .padding(.bottom, 34)
      }
      .navigationTitle(L10n.tr("player.details"))
      .navigationBarTitleDisplayMode(.inline)
      .scrollContentBackground(.hidden)
      .background(Color.clear)
    }
  }

  private var sourceText: String {
    track?.playlistName
      ?? track?.source
      ?? track?.sourceLane
      ?? L10n.tr("radio.defaultTitle")
  }
}

private struct QueueTrackRow: View {
  let track: Track
  let detail: String

  var body: some View {
    HStack(spacing: 13) {
      RemoteArtworkView(urls: [track.artworkURL], showsLoadingIndicator: false) {
        Color.clear
      }
      .frame(width: 50, height: 50)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text(track.title)
          .font(.system(size: 16, weight: .bold, design: .rounded))
          .foregroundStyle(.white)
          .lineLimit(1)

        Text("\(track.artist) • \(detail)")
          .font(.system(size: 13, weight: .medium, design: .rounded))
          .foregroundStyle(.white.opacity(0.55))
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Text(track.durationText)
        .font(.system(size: 13, weight: .bold, design: .rounded))
        .foregroundStyle(.white.opacity(0.42))
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
  }
}

private struct DetailRow: View {
  let title: String
  let value: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 18) {
      Text(title)
        .font(.system(size: 14, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.44))
        .frame(width: 76, alignment: .leading)

      Text(value)
        .font(.system(size: 16, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.88))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private struct SheetSectionTitle: View {
  let title: String

  init(_ title: String) {
    self.title = title
  }

  var body: some View {
    Text(title)
      .font(.system(size: 14, weight: .heavy, design: .rounded))
      .foregroundStyle(.white.opacity(0.46))
      .textCase(.uppercase)
      .tracking(0.8)
  }
}

private struct EmptySheetMessage: View {
  let systemImage: String
  let title: String
  let message: String

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Image(systemName: systemImage)
        .font(.system(size: 30, weight: .semibold))
        .foregroundStyle(.white.opacity(0.46))

      Text(title)
        .font(.system(size: 20, weight: .bold, design: .rounded))
        .foregroundStyle(.white)

      Text(message)
        .font(.system(size: 15, weight: .medium, design: .rounded))
        .foregroundStyle(.white.opacity(0.58))
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 10)
  }
}

#Preview("Playing") {
  let playbackController = PlaybackController()
  playbackController.currentTrack = MockCatalog.featuredTracks[0]
  playbackController.state = .playing
  playbackController.activeBackend = .appleMusic
  playbackController.playbackProgress = 0.42
  playbackController.elapsedSeconds = 93
  playbackController.elapsedTimeText = "1:33"

  return PlayerView()
    .environment(playbackController)
    .environment(RadioStationController(playbackController: playbackController))
    .environment(ImageAssetStore())
    .environment(ArtworkAnalysisStore())
}

#Preview("Loading") {
  let playbackController = PlaybackController()
  playbackController.currentTrack = MockCatalog.featuredTracks[1]
  playbackController.state = .loading
  playbackController.elapsedTimeText = "0:00"

  return PlayerView()
    .environment(playbackController)
    .environment(RadioStationController(playbackController: playbackController))
    .environment(ImageAssetStore())
    .environment(ArtworkAnalysisStore())
}

#Preview("Speech") {
  let playbackController = PlaybackController()
  playbackController.currentSpeech = RadioSpeechPlaybackSegment(
    id: "preview-speech",
    kind: .transition,
    text: L10n.tr("player.preview.speechText"),
    displayText: L10n.tr("player.preview.speechDisplayText"),
    audio: nil
  )
  playbackController.state = .playing
  playbackController.activeBackend = .speechSynthesis
  playbackController.playbackProgress = 0.3
  playbackController.elapsedSeconds = 7
  playbackController.elapsedTimeText = "0:07"

  return PlayerView()
    .environment(playbackController)
    .environment(RadioStationController(playbackController: playbackController))
    .environment(ImageAssetStore())
    .environment(ArtworkAnalysisStore())
}
