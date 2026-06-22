import SwiftUI

struct DiscoverView: View {
  @Environment(PlaybackController.self) private var playbackController
  @Environment(RadioStationController.self) private var radioStation

  var body: some View {
    GeometryReader { proxy in
      ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 0) {
          RadioHeaderCard(
            track: displayTrack,
            stationTitle: radioStation.stationTitle,
            subtitle: radioStation.stationIntro,
            state: playbackController.state,
            elapsedTimeText: playbackController.elapsedTimeText
          )
            .padding(.horizontal, 10)
            .padding(.top, 28)

          NowPlayingSetCard(
            track: displayTrack,
            currentItem: radioStation.currentItem,
            queueItems: radioStation.upNextItems,
            status: panelStatus,
            errorMessage: radioStation.errorMessage,
            isPlaying: playbackController.state == .playing,
            isLoading: playbackController.state == .loading || radioStation.isLoadingStation,
            elapsedTimeText: playbackController.elapsedTimeText,
            primaryAction: primaryRadioAction,
            previousAction: playPreviousTrack,
            nextAction: playNextTrack,
            refreshAction: refreshStation
          )
          .padding(.horizontal, 10)
          .offset(y: -44)
        }
        .padding(.bottom, 96)
        .frame(width: proxy.size.width, alignment: .top)
        .frame(minHeight: proxy.size.height, alignment: .top)
      }
      .scrollBounceBehavior(.always, axes: .vertical)
    }
    .background(.clear)
    .task {
      if !radioStation.hasStationContent, !radioStation.isLoadingStation {
        await radioStation.loadCurrentStation()
      }
    }
  }

  private var displayTrack: Track {
    playbackController.currentTrack
      ?? radioStation.currentItem?.track
      ?? radioStation.queue.first?.track
      ?? MockCatalog.featuredTracks[0]
  }

  private var panelStatus: RadioPanelStatus {
    if radioStation.isLoadingStation, radioStation.currentItem == nil, radioStation.queue.isEmpty {
      return .loading
    }

    if radioStation.currentItem == nil, radioStation.queue.isEmpty {
      return .ready
    }

    return .onAir
  }

  private func primaryRadioAction() {
    switch panelStatus {
    case .loading:
      break
    case .ready:
      Task {
        await radioStation.startStation()
      }
    case .onAir:
      if radioStation.currentItem == nil {
        Task {
          await radioStation.playNext()
        }
      } else {
        playbackController.togglePlayback()
      }
    }
  }

  private func playNextTrack() {
    Task {
      await radioStation.playNext()
    }
  }

  private func playPreviousTrack() {
    radioStation.playPrevious()
  }

  private func refreshStation() {
    Task {
      await radioStation.refreshStation()
    }
  }
}

private enum RadioPanelStatus {
  case loading
  case ready
  case onAir
}

private struct RadioHeaderCard: View {
  let track: Track
  let stationTitle: String
  let subtitle: String
  let state: PlaybackState
  let elapsedTimeText: String

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          Text(stationTitle)
            .font(.system(size: 24, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.76)

          Text(statusText)
            .font(.system(size: 20, weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(0.54))
        }

        Spacer(minLength: 12)

        Text(elapsedTimeText)
          .font(.system(size: 24, weight: .heavy, design: .rounded))
          .foregroundStyle(.white)
      }

      ReactiveSpectrumView(
        track: track,
        isPlaying: state == .playing,
        baseColor: Color(red: 0.55, green: 0.66, blue: 0.76).opacity(0.82),
        activeColor: .white.opacity(0.92),
        barWidth: 5,
        spacing: 9,
        fallbackBars: SpectrumBarPresets.radioBars,
        cornerRadius: 3
      )
      .frame(height: 118)
      .offset(y: -18)

      Text(subtitle)
        .font(.system(size: 15, weight: .bold, design: .rounded))
        .foregroundStyle(.white.opacity(0.58))
        .lineLimit(2)
        .offset(y: -34)
    }
    .padding(.horizontal, 24)
    .padding(.top, 22)
    .padding(.bottom, 28)
    .frame(maxWidth: .infinity, minHeight: 224, alignment: .topLeading)
    .background(
      LinearGradient(
        colors: [
          Color(red: 0.02, green: 0.06, blue: 0.08),
          Color(red: 0.02, green: 0.04, blue: 0.08)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      ),
      in: RoundedRectangle(cornerRadius: 34, style: .continuous)
    )
    .shadow(color: .black.opacity(0.25), radius: 18, y: 12)
    .accessibilityElement(children: .combine)
  }

  private var statusText: String {
    switch state {
    case .playing:
      "On air"
    case .loading:
      "Loading"
    case .failed:
      "Playback error"
    case .paused:
      "Paused"
    case .idle:
      "Ready to play"
    }
  }
}

private struct NowPlayingSetCard: View {
  let track: Track
  let currentItem: RadioQueueItem?
  let queueItems: [RadioQueueItem]
  let status: RadioPanelStatus
  let errorMessage: String?
  let isPlaying: Bool
  let isLoading: Bool
  let elapsedTimeText: String
  let primaryAction: () -> Void
  let previousAction: () -> Void
  let nextAction: () -> Void
  let refreshAction: () -> Void

  private var nextItem: RadioQueueItem? {
    queueItems.first
  }

  private var upNextTitle: String {
    nextItem?.track.title ?? status.emptyQueueText
  }

  private var upNextDetail: String? {
    guard let track = nextItem?.track else { return nil }
    return "\(track.artist) • \(track.album)"
  }

  private var queueMetaTitle: String {
    nextItem?.track.durationText ?? "Radio set"
  }

  private var queueMetaDetail: String {
    nextItem == nil ? "Awaiting queue" : "Next up"
  }

  private var sourceText: String {
    currentItem?.sourceTitle ?? queueItems.first?.sourceTitle ?? "Backend station"
  }

  private var reasonText: String {
    errorMessage ?? currentItem?.handoffText ?? currentItem?.reason ?? status.reasonText
  }

  private var trackFeedSource: String {
    currentItem == nil ? "AIRSET" : track.artist.uppercased()
  }

  private var trackFeedMessage: String {
    if currentItem != nil {
      return "Now playing \(track.title), from \(track.album)."
    }

    if queueItems.isEmpty {
      return "Load the backend station to start playback."
    }

    return "Ready to play \(track.title), from \(track.album)."
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 6) {
          Text(track.album)
            .font(.system(size: 28, weight: .heavy, design: .rounded))
            .foregroundStyle(.black)
            .lineLimit(1)
            .minimumScaleFactor(0.72)

          Text(sourceText)
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(.black.opacity(0.38))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }

        Spacer(minLength: 18)

        VStack(alignment: .trailing, spacing: 6) {
          Text(queueMetaTitle)
            .font(.system(size: 25, weight: .heavy, design: .rounded))
            .foregroundStyle(.black)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

          Text(queueMetaDetail)
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(.black.opacity(0.36))
        }
      }

      VStack(alignment: .leading, spacing: 10) {
        FeedLine(
          source: "Radio Brain",
          message: reasonText,
          lineLimit: 3
        )

        FeedLine(
          source: trackFeedSource,
          message: trackFeedMessage,
          lineLimit: 2
        )

        VStack(alignment: .leading, spacing: 8) {
          Text("Up next")
            .font(.system(size: 16, weight: .heavy, design: .rounded))
            .foregroundStyle(.black.opacity(0.38))

          Text(upNextTitle)
            .font(.system(size: 19, weight: .heavy, design: .rounded))
            .foregroundStyle(.black)
            .lineLimit(1)
            .minimumScaleFactor(0.58)

          if let upNextDetail {
            Text(upNextDetail)
              .font(.system(size: 14, weight: .bold, design: .rounded))
              .foregroundStyle(.black.opacity(0.46))
              .lineLimit(1)
              .minimumScaleFactor(0.72)
          }
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.black.opacity(0.055), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
          .stroke(.white.opacity(0.72), lineWidth: 1)
      }

      HStack(spacing: 22) {
        Text(elapsedTimeText)
          .font(.system(size: 20, weight: .bold, design: .rounded))
          .foregroundStyle(.black.opacity(0.42))

        ReactiveSpectrumView(
          track: track,
          isPlaying: isPlaying,
          baseColor: .black.opacity(0.1),
          activeColor: .black,
          barWidth: 5,
          spacing: 8,
          fallbackBars: SpectrumBarPresets.progressBars,
          cornerRadius: 3
        )
        .frame(height: 42)

        Spacer(minLength: 4)

        Button(action: primaryAction) {
          Image(systemName: playButtonSystemImage)
            .font(.system(size: 31, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 64, height: 64)
            .background(.black, in: Circle())
        }
        .disabled(isLoading)
        .accessibilityLabel(playButtonAccessibilityLabel)
      }

      HStack(spacing: 12) {
        RadioActionButton(systemImage: "backward.end.fill", label: "Previous", action: previousAction)
        RadioActionButton(systemImage: "forward.end.fill", label: "Next", action: nextAction)
        RadioActionButton(systemImage: "arrow.clockwise", label: "Refresh station", action: refreshAction)
      }
      .disabled(status == .loading)
    }
    .padding(.horizontal, 20)
    .padding(.top, 36)
    .padding(.bottom, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Color(red: 0.98, green: 0.97, blue: 0.93),
      in: RoundedRectangle(cornerRadius: 34, style: .continuous)
    )
    .overlay(alignment: .top) {
      LinearGradient(
        colors: [.white.opacity(0.88), .clear],
        startPoint: .top,
        endPoint: .bottom
      )
      .frame(height: 128)
      .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
    }
    .shadow(color: .black.opacity(0.18), radius: 26, y: 16)
    .accessibilityElement(children: .contain)
  }

  private var playButtonSystemImage: String {
    if isLoading {
      return "hourglass"
    }

    switch status {
    case .loading:
      return "hourglass"
    case .ready:
      return "dot.radiowaves.left.and.right"
    case .onAir:
      return isPlaying ? "pause.fill" : "play.fill"
    }
  }

  private var playButtonAccessibilityLabel: String {
    if isLoading {
      return "Loading"
    }

    switch status {
    case .loading:
      return "Loading station"
    case .ready:
      return "Start radio"
    case .onAir:
      return isPlaying ? "Pause" : "Play"
    }
  }
}

private extension RadioPanelStatus {
  var reasonText: String {
    switch self {
    case .loading:
      "Loading the latest backend station queue."
    case .ready:
      "The backend station is ready to load a playable queue."
    case .onAir:
      "Streaming the backend-programmed station queue."
    }
  }

  var emptyQueueText: String {
    switch self {
    case .loading:
      "Loading station"
    case .ready:
      "Tap start to load the station"
    case .onAir:
      "End of queue"
    }
  }
}

private struct RadioActionButton: View {
  let systemImage: String
  let label: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 17, weight: .bold))
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .accessibilityLabel(label)
  }
}

private struct FeedLine: View {
  let source: String
  let message: String
  let lineLimit: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("\(source) • 0:00")
        .font(.system(size: 16, weight: .heavy, design: .rounded))
        .foregroundStyle(.black.opacity(0.34))

      Text(message)
        .font(.system(size: 18, weight: .heavy, design: .rounded))
        .foregroundStyle(.black)
        .lineSpacing(2)
        .lineLimit(lineLimit)
        .truncationMode(.tail)
    }
  }
}

private struct ReactiveSpectrumView: View {
  @Environment(PlaybackController.self) private var playbackController

  let track: Track
  let isPlaying: Bool
  let baseColor: Color
  let activeColor: Color
  let barWidth: CGFloat
  let spacing: CGFloat
  let fallbackBars: [CGFloat]
  let cornerRadius: CGFloat

  @State private var analysis: AudioSpectrumAnalysis?

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isPlaying)) { context in
      SpectrumBarsView(
        bands: currentBands(frameDate: context.date),
        isPlaying: isPlaying,
        baseColor: baseColor,
        activeColor: activeColor,
        barWidth: barWidth,
        spacing: spacing,
        cornerRadius: cornerRadius
      )
    }
    .task(id: SpectrumLoadRequest(trackID: track.id, previewURL: track.previewURL, bandCount: fallbackBars.count)) {
      analysis = nil

      guard let previewURL = track.previewURL else { return }
      let loadedAnalysis = await SpectrumAnalysisCache.shared.analysis(for: previewURL, bandCount: fallbackBars.count)
      if !Task.isCancelled {
        analysis = loadedAnalysis
      }
    }
    .accessibilityHidden(true)
  }

  private func currentBands(frameDate: Date) -> [Float] {
    if let analysis, !analysis.frames.isEmpty {
      return analysis.bands(at: playbackController.currentPlaybackSeconds())
    }

    _ = frameDate
    return ProceduralSpectrumGenerator.bands(
      for: track,
      at: playbackController.currentPlaybackSeconds(),
      fallbackBars: fallbackBars
    )
  }
}

private struct SpectrumLoadRequest: Equatable {
  let trackID: UUID
  let previewURL: URL?
  let bandCount: Int
}

private struct SpectrumBarsView: View {
  let bands: [Float]
  let isPlaying: Bool
  let baseColor: Color
  let activeColor: Color
  let barWidth: CGFloat
  let spacing: CGFloat
  let cornerRadius: CGFloat

  var body: some View {
    GeometryReader { proxy in
      let targetWidth = CGFloat(bands.count) * barWidth + CGFloat(max(bands.count - 1, 0)) * spacing
      let scale = min(1, max(0.35, proxy.size.width / max(targetWidth, 1)))
      let color = isPlaying ? activeColor : baseColor

      HStack(alignment: .center, spacing: spacing * scale) {
        ForEach(bands.indices, id: \.self) { index in
          Capsule()
            .fill(color)
            .frame(
              width: barWidth * scale,
              height: barHeight(for: bands[index], in: proxy.size.height, scale: scale)
            )
        }
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .animation(isPlaying ? nil : .easeOut(duration: 0.16), value: bands)
  }

  private func barHeight(for band: Float, in availableHeight: CGFloat, scale: CGFloat) -> CGFloat {
    let dotHeight = barWidth * scale
    let clampedBand = CGFloat(min(max(band, 0), 1))
    let activeBand = min(max((clampedBand - 0.1) / 0.9, 0), 1)
    let curvedBand = activeBand * activeBand * (3 - (2 * activeBand))
    let maxHeight = availableHeight * 0.86
    return dotHeight + ((maxHeight - dotHeight) * curvedBand)
  }
}

private enum SpectrumBarPresets {
  static let radioBars: [CGFloat] = [
    78, 96, 112, 126, 140, 130, 114, 98, 82, 66,
    54, 46, 42, 48, 58, 72, 88, 98, 104, 106,
    104, 96, 84, 72, 62, 70, 82, 96, 114, 132,
    140, 138, 128, 116, 104, 88, 72, 60, 48, 42
  ]

  static let progressBars: [CGFloat] = [
    30, 34, 38, 34, 40, 36, 42, 38, 40, 36,
    34, 32, 36, 34, 38, 40, 36, 42, 38, 34,
    32, 34, 36, 32, 30
  ]
}

#Preview {
  let playbackController = PlaybackController()
  NavigationStack {
    DiscoverView()
  }
  .environment(playbackController)
  .environment(RadioStationController(playbackController: playbackController))
  .environment(MusicAuthorizationService())
}
