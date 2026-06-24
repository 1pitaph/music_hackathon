import SwiftUI

struct PlayerView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(PlaybackController.self) private var playbackController
  @Environment(RadioStationController.self) private var radioStation

  private let accentColor = Color(hex: "#D9523A")

  var body: some View {
    GeometryReader { proxy in
      let coverSize = artworkSize(for: proxy.size)

      ZStack {
        playerBackground

        VStack(spacing: 0) {
          header

          Spacer(minLength: 18)

          artwork(size: coverSize)

          metadata
            .padding(.top, 28)

          progress
            .padding(.top, 30)

          controls
            .padding(.top, 28)

          statusText
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.52))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .padding(.horizontal, 14)
            .padding(.top, 22)

          Spacer(minLength: 24)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
      }
    }
    .preferredColorScheme(.dark)
  }

  private var header: some View {
    HStack {
      iconButton(
        systemImage: "chevron.down",
        accessibilityLabel: "关闭播放器",
        size: 17,
        frameSize: 42,
        prominent: false
      ) {
        dismiss()
      }

      Spacer()

      Text("正在播放")
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.72))
        .lineLimit(1)

      Spacer()

      iconButton(
        systemImage: "ellipsis",
        accessibilityLabel: "更多",
        size: 17,
        frameSize: 42,
        prominent: false
      ) {}
      .disabled(true)
      .opacity(0.55)
    }
    .padding(.top, 18)
  }

  private var metadata: some View {
    VStack(spacing: 8) {
      Text(playbackTitle)
        .font(.system(size: 28, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.72)

      Text(playbackSubtitle)
        .font(.system(size: 15, weight: .medium, design: .rounded))
        .foregroundStyle(.white.opacity(0.58))
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.8)
    }
    .frame(maxWidth: .infinity)
  }

  private var progress: some View {
    VStack(spacing: 9) {
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule()
            .fill(.white.opacity(0.15))

          Capsule()
            .fill(
              LinearGradient(
                colors: [.white.opacity(0.95), accentColor.opacity(0.95)],
                startPoint: .leading,
                endPoint: .trailing
              )
            )
            .frame(width: proxy.size.width * clampedPlaybackProgress)
        }
      }
      .frame(height: 6)

      HStack {
        Text(playbackController.elapsedTimeText)
        Spacer()
        Text(durationText)
      }
      .font(.system(size: 11, weight: .medium, design: .rounded))
      .foregroundStyle(.white.opacity(0.42))
    }
  }

  private var controls: some View {
    HStack(spacing: 36) {
      iconButton(
        systemImage: playButtonSystemImage,
        accessibilityLabel: playButtonAccessibilityLabel,
        size: playbackController.state == .loading ? 28 : 36,
        frameSize: 74,
        prominent: true
      ) {
        playbackController.togglePlayback()
      }
      .disabled(playbackController.state == .loading)

      iconButton(
        systemImage: "forward.fill",
        accessibilityLabel: "下一首",
        size: 28,
        frameSize: 58,
        prominent: false
      ) {
        Task {
          await radioStation.playNext(reason: .manual)
        }
      }
    }
  }

  @ViewBuilder
  private var statusText: some View {
    if let message = playbackController.lastErrorMessage {
      Text(message)
    } else if playbackController.state == .loading {
      Text("正在加载")
    } else if let currentTrack = playbackController.currentTrack, !currentTrack.isPlayable {
      Text("这首歌暂时不可播放")
    } else if playbackController.activeBackend == .appleMusic {
      Text("Apple Music")
    } else if playbackController.activeBackend == .localPreview {
      Text("本地预览")
    } else if playbackController.activeBackend == .speechAudio || playbackController.activeBackend == .speechSynthesis {
      Text("电台主持")
    } else {
      Text(playbackController.state.rawValue.capitalized)
    }
  }

  private var playerBackground: some View {
    ZStack {
      LinearGradient(
        colors: [
          accentColor.opacity(0.52),
          Color(hex: "#261622"),
          Color(hex: "#09080A")
        ],
        startPoint: .top,
        endPoint: .bottom
      )

      RadialGradient(
        colors: [
          Color(hex: "#77D4D2").opacity(0.32),
          .clear
        ],
        center: .topTrailing,
        startRadius: 30,
        endRadius: 320
      )

      LinearGradient(
        colors: [
          .clear,
          .black.opacity(0.54)
        ],
        startPoint: .center,
        endPoint: .bottom
      )
    }
    .ignoresSafeArea()
  }

  private func artwork(size: CGFloat) -> some View {
    RemoteArtworkView(urls: artworkURLs, showsLoadingIndicator: false) {
      ZStack {
        LinearGradient(
          colors: [
            accentColor.opacity(0.88),
            Color(hex: "#3B2534"),
            Color(hex: "#10181B")
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )

        MarbleAvatarView(
          seed: fallbackArtworkSeed,
          size: size * 0.68,
          palette: ["#F6A46D", "#D9523A", "#7BC9C8", "#2B1C2A"],
          accessibilityLabel: nil
        )

        if playbackController.currentSpeech != nil {
          Image(systemName: "waveform.badge.mic")
            .font(.system(size: max(42, size * 0.18), weight: .semibold))
            .foregroundStyle(.white.opacity(0.78))
            .shadow(color: .black.opacity(0.24), radius: 12, y: 8)
        }
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .stroke(.white.opacity(0.16), lineWidth: 1)
    }
    .shadow(color: accentColor.opacity(0.28), radius: 34, y: 24)
    .accessibilityHidden(true)
  }

  @ViewBuilder
  private func iconButton(
    systemImage: String,
    accessibilityLabel: String,
    size: CGFloat,
    frameSize: CGFloat,
    prominent: Bool,
    action: @escaping () -> Void
  ) -> some View {
    if #available(iOS 26.0, *) {
      if prominent {
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
          .background(prominent ? accentColor : .white.opacity(0.09), in: Circle())
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
  }

  private func artworkSize(for size: CGSize) -> CGFloat {
    max(220, min(min(size.width - 56, size.height * 0.43), 360))
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

  private var durationText: String {
    if let currentTrack = playbackController.currentTrack {
      return currentTrack.durationText
    }

    if let duration = playbackController.currentSpeech?.audio?.durationSeconds, duration > 0 {
      return Self.timeText(for: duration)
    }

    return "--:--"
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

  private static func timeText(for seconds: TimeInterval) -> String {
    let totalSeconds = Int(max(0, seconds))
    return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
  }
}

#Preview {
  let playbackController = PlaybackController()
  PlayerView()
    .environment(playbackController)
    .environment(RadioStationController(playbackController: playbackController))
}
