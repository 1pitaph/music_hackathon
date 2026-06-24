import MediaPlayer
import SwiftUI

struct PlayerView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(PlaybackController.self) private var playbackController
  @Environment(RadioStationController.self) private var radioStation

  @State private var presentedSheet: PlayerSheet?

  private let accentColor = Color(hex: "#D9523A")

  var body: some View {
    GeometryReader { proxy in
      let safeArea = proxy.safeAreaInsets

      ZStack {
        PlayerArtworkBackdrop(
          artworkURLs: artworkURLs,
          fallbackSeed: fallbackArtworkSeed,
          accentColor: accentColor
        )
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
      .overlay(alignment: .top) {
        playerHeader
          .frame(width: proxy.size.width)
          .padding(.top, max(safeArea.top, 10))
      }
      .overlay(alignment: .bottom) {
        bottomControls
          .padding(.horizontal, horizontalPadding(for: proxy.size))
          .padding(.bottom, max(safeArea.bottom, 20))
          .frame(width: proxy.size.width, alignment: .leading)
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

  private var playerHeader: some View {
    VStack(spacing: 12) {
      Capsule()
        .fill(.white.opacity(0.42))
        .frame(width: 72, height: 6)
        .accessibilityHidden(true)

      HStack {
        playerButton(
          systemImage: "chevron.down",
          accessibilityLabel: "关闭播放器",
          size: 17,
          frameSize: 42,
          style: .subtle
        ) {
          dismiss()
        }

        Spacer()

        Text("正在播放")
          .font(.system(size: 13, weight: .semibold, design: .rounded))
          .foregroundStyle(.white.opacity(0.7))
          .lineLimit(1)
          .shadow(color: .black.opacity(0.3), radius: 10, y: 4)

        Spacer()

        playerButton(
          systemImage: "ellipsis",
          accessibilityLabel: "更多",
          size: 18,
          frameSize: 42,
          style: .subtle
        ) {
          presentedSheet = .details
        }
      }
    }
    .padding(.horizontal, 22)
  }

  private var bottomControls: some View {
    VStack(alignment: .leading, spacing: 26) {
      PlayerTrackIdentity(
        title: playbackTitle,
        subtitle: playbackSubtitle,
        isExplicit: playbackController.currentTrack?.isExplicit == true,
        moreAction: {
          presentedSheet = .details
        }
      )

      PlayerScrubber(
        progress: clampedPlaybackProgress,
        elapsedText: playbackController.elapsedTimeText,
        trailingText: trailingTimeText,
        statusText: playbackStatusText,
        statusIsAlert: playbackController.lastErrorMessage != nil
      )

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
    .padding(.top, 52)
    .padding(.bottom, 4)
    .frame(maxWidth: .infinity, alignment: .leading)
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

  @ViewBuilder
  private func playerButton(
    systemImage: String,
    accessibilityLabel: String,
    size: CGFloat,
    frameSize: CGFloat,
    style: PlayerButtonStyle,
    action: @escaping () -> Void
  ) -> some View {
    if #available(iOS 26.0, *) {
      if style == .primary {
        Button(action: action) {
          buttonImage(systemImage: systemImage, size: size, frameSize: frameSize)
        }
        .buttonStyle(.glassProminent)
        .accessibilityLabel(accessibilityLabel)
      } else {
        Button(action: action) {
          buttonImage(systemImage: systemImage, size: size, frameSize: frameSize)
        }
        .buttonStyle(.glass)
        .accessibilityLabel(accessibilityLabel)
      }
    } else {
      Button(action: action) {
        buttonImage(systemImage: systemImage, size: size, frameSize: frameSize)
          .background(style.backgroundColor(accentColor: accentColor), in: Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(accessibilityLabel)
    }
  }

  private func buttonImage(systemImage: String, size: CGFloat, frameSize: CGFloat) -> some View {
    Image(systemName: systemImage)
      .font(.system(size: size, weight: .bold))
      .foregroundStyle(.white)
      .frame(width: frameSize, height: frameSize)
      .contentShape(Circle())
  }

  private func horizontalPadding(for size: CGSize) -> CGFloat {
    size.width > 700 ? 86 : 30
  }

  private var artworkURLs: [URL?] {
    [
      playbackController.currentTrack?.artworkURL,
      radioStation.currentItem?.track.artworkURL
    ]
  }

  private var fallbackArtworkSeed: String {
    playbackController.currentTrack?.title
      ?? playbackController.currentSpeech?.id
      ?? radioStation.station?.id
      ?? radioStation.stationTitle
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
      return "正在加载"
    }

    return playbackController.state == .playing ? "暂停" : "播放"
  }

  private var playbackStatusText: String {
    if let message = playbackController.lastErrorMessage {
      return message
    }

    if playbackController.state == .loading {
      return "正在加载"
    }

    if let currentTrack = playbackController.currentTrack, !currentTrack.isPlayable {
      return "这首歌暂时不可播放"
    }

    switch playbackController.activeBackend {
    case .appleMusic:
      return "Apple Music"
    case .localPreview:
      return "本地预览"
    case .speechAudio, .speechSynthesis:
      return "电台主持"
    case .none:
      return playbackController.state == .idle ? "准备播放" : playbackController.state.rawValue.capitalized
    }
  }

  private var playbackBackendText: String {
    switch playbackController.activeBackend {
    case .appleMusic:
      return "Apple Music"
    case .localPreview:
      return "本地预览"
    case .speechAudio:
      return "电台主持音频"
    case .speechSynthesis:
      return "系统语音合成"
    case .none:
      return "未连接"
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

private enum PlayerButtonStyle {
  case primary
  case subtle

  func backgroundColor(accentColor: Color) -> Color {
    switch self {
    case .primary:
      accentColor.opacity(0.92)
    case .subtle:
      .white.opacity(0.16)
    }
  }
}

private struct PlayerArtworkBackdrop: View {
  let artworkURLs: [URL?]
  let fallbackSeed: String
  let accentColor: Color

  var body: some View {
    ZStack {
      RemoteArtworkView(urls: artworkURLs, showsLoadingIndicator: false) {
        fallbackArtwork
      }
      .scaledToFill()
      .blur(radius: 18)
      .scaleEffect(1.08)
      .overlay {
        RemoteArtworkView(urls: artworkURLs, showsLoadingIndicator: false) {
          fallbackArtwork
        }
        .scaledToFill()
        .opacity(0.74)
      }

      LinearGradient(
        colors: [
          .black.opacity(0.12),
          Color(hex: "#1E1510").opacity(0.32),
          Color(hex: "#2A160B").opacity(0.72),
          Color(hex: "#180D08").opacity(0.98)
        ],
        startPoint: .top,
        endPoint: .bottom
      )

      LinearGradient(
        colors: [
          .clear,
          .black.opacity(0.1),
          .black.opacity(0.42)
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    }
    .ignoresSafeArea()
  }

  private var fallbackArtwork: some View {
    ZStack {
      LinearGradient(
        colors: [
          accentColor.opacity(0.9),
          Color(hex: "#5B3822"),
          Color(hex: "#16100D")
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

      MarbleAvatarView(
        seed: fallbackSeed,
        size: 280,
        palette: ["#F6A46D", "#D9523A", "#7BC9C8", "#2B1C2A"],
        accessibilityLabel: nil
      )
    }
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
              .accessibilityLabel("Explicit")
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
          accessibilityLabel: "收藏暂不可用",
          size: 25,
          frameSize: 56,
          isEnabled: false,
          action: {}
        )

        CircleIconButton(
          systemImage: "ellipsis",
          accessibilityLabel: "更多",
          size: 24,
          frameSize: 56,
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
      .accessibilityLabel("播放进度")
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
          .font(.system(size: 42, weight: .bold))
          .foregroundStyle(.white.opacity(0.36))
          .frame(width: 88, height: 72)
      }
      .disabled(true)
      .accessibilityLabel("上一首暂不可用")

      Spacer(minLength: 14)

      Button(action: playPauseAction) {
        Image(systemName: playButtonSystemImage)
          .font(.system(size: isLoading ? 50 : 58, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 96, height: 92)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(isLoading)
      .accessibilityLabel(playButtonAccessibilityLabel)

      Spacer(minLength: 14)

      Button(action: nextAction) {
        Image(systemName: "forward.fill")
          .font(.system(size: 42, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 88, height: 72)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("下一首")
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
        accessibilityLabel: "歌词",
        action: lyricsAction
      )

      Spacer()

      SecondaryActionButton(
        systemImage: "airpodspro",
        accessibilityLabel: "播放详情",
        action: routeAction
      )

      Spacer()

      SecondaryActionButton(
        systemImage: "list.bullet",
        accessibilityLabel: "播放队列",
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
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(.white.opacity(0.56))
        .frame(width: 22)
        .accessibilityHidden(true)

      SystemVolumeSlider()
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .accessibilityLabel("音量")

      Image(systemName: "speaker.wave.3.fill")
        .font(.system(size: 20, weight: .bold))
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
        .font(.system(size: 29, weight: .semibold))
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(.white.opacity(0.64))
        .frame(width: 52, height: 44)
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
            SheetSectionTitle("正在播放")
            QueueTrackRow(track: visibleCurrentTrack, detail: "Now playing")
          }

          SheetSectionTitle("接下来")

          if upNextItems.isEmpty {
            EmptySheetMessage(
              systemImage: "music.note.list",
              title: "队列为空",
              message: "电台会在需要时继续请求新的播放内容。"
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
      .navigationTitle("播放队列")
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
              title: "歌词暂不可用",
              message: "\(currentTrack?.title ?? stationTitle) 目前没有同步歌词；电台主持内容会在这里显示。"
            )
          }
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .padding(.bottom, 34)
      }
      .navigationTitle("歌词")
      .navigationBarTitleDisplayMode(.inline)
      .scrollContentBackground(.hidden)
      .background(Color.clear)
    }
  }

  private func speechTitle(for speech: RadioSpeechPlaybackSegment) -> String {
    switch speech.kind {
    case .stationIntro:
      "电台开场"
    case .transition:
      "电台串场"
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
            DetailRow(title: "播放状态", value: statusText)
            DetailRow(title: "播放后端", value: backendText)
            DetailRow(title: "专辑", value: track?.album ?? "未知")
            DetailRow(title: "来源", value: sourceText)
            DetailRow(title: "时长", value: track?.durationText ?? "--:--")
            DetailRow(title: "可播放", value: track?.isPlayable == true ? "是" : "否")
          }
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .padding(.bottom, 34)
      }
      .navigationTitle("播放详情")
      .navigationBarTitleDisplayMode(.inline)
      .scrollContentBackground(.hidden)
      .background(Color.clear)
    }
  }

  private var sourceText: String {
    track?.playlistName
      ?? track?.source
      ?? track?.sourceLane
      ?? "Airset Radio"
  }
}

private struct QueueTrackRow: View {
  let track: Track
  let detail: String

  var body: some View {
    HStack(spacing: 13) {
      RemoteArtworkView(urls: [track.artworkURL], showsLoadingIndicator: false) {
        LinearGradient(
          colors: [
            Color(hex: "#D9523A").opacity(0.9),
            Color(hex: "#2A1D19")
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
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
}

#Preview("Loading") {
  let playbackController = PlaybackController()
  playbackController.currentTrack = MockCatalog.featuredTracks[1]
  playbackController.state = .loading
  playbackController.elapsedTimeText = "0:00"

  return PlayerView()
    .environment(playbackController)
    .environment(RadioStationController(playbackController: playbackController))
}

#Preview("Speech") {
  let playbackController = PlaybackController()
  playbackController.currentSpeech = RadioSpeechPlaybackSegment(
    id: "preview-speech",
    kind: .transition,
    text: "接下来这首歌会把夜色往前推一步，留一点空气给旋律。",
    displayText: "接下来这首歌会把夜色往前推一步。",
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
}
