import SwiftUI

struct DiscoverView: View {
  @Environment(PlaybackController.self) private var playbackController
  @Environment(RadioStationController.self) private var radioStation
  @Environment(MusicAuthorizationService.self) private var musicAuthorization

  var body: some View {
    GeometryReader { proxy in
      ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 0) {
          RadioHeaderCard(
            track: displayTrack,
            stationTitle: stationTitle,
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
            isPlaying: playbackController.state == .playing,
            isLoading: playbackController.state == .loading || radioStation.isBuildingStation || radioStation.isSyncingLibrary,
            elapsedTimeText: playbackController.elapsedTimeText,
            tuning: radioStation.tuning,
            primaryAction: primaryRadioAction,
            skipAction: skipCurrent,
            likeAction: radioStation.likeCurrent,
            dislikeAction: dislikeCurrent,
            refreshAction: refreshRecommendations,
            tuningAction: updateTuning
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
      await musicAuthorization.refreshAccessState()
      if musicAuthorization.status == .authorized, radioStation.playlists.isEmpty {
        await radioStation.refreshLibrary()
      }
    }
  }

  private var displayTrack: Track {
    playbackController.currentTrack
      ?? radioStation.currentItem?.track
      ?? radioStation.queue.first?.track
      ?? MockCatalog.featuredTracks[0]
  }

  private var stationTitle: String {
    let selectedNames = radioStation.selectedPlaylists.map(\.name)
    if selectedNames.count == 1, let name = selectedNames.first {
      return "\(name) Radio"
    }
    return "Airset Radio"
  }

  private var panelStatus: RadioPanelStatus {
    if musicAuthorization.status != .authorized {
      return .needsAuthorization
    }

    if !radioStation.hasSelectedPlaylists {
      return .needsSelection
    }

    if radioStation.currentItem == nil, radioStation.queue.isEmpty {
      return .ready
    }

    return .onAir
  }

  private func primaryRadioAction() {
    switch panelStatus {
    case .needsAuthorization:
      Task {
        await musicAuthorization.requestAccess()
        if musicAuthorization.status == .authorized {
          await radioStation.refreshLibrary()
        }
      }
    case .needsSelection:
      Task {
        await radioStation.refreshLibrary()
      }
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

  private func skipCurrent() {
    Task {
      await radioStation.skipCurrent()
    }
  }

  private func dislikeCurrent() {
    radioStation.dislikeCurrent()
    Task {
      await radioStation.skipCurrent()
    }
  }

  private func refreshRecommendations() {
    Task {
      await radioStation.refreshRecommendations()
    }
  }

  private func updateTuning(_ tuning: RadioTuning) {
    Task {
      await radioStation.setTuning(tuning)
    }
  }
}

private enum RadioPanelStatus {
  case needsAuthorization
  case needsSelection
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
      "Tuning"
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
  let isPlaying: Bool
  let isLoading: Bool
  let elapsedTimeText: String
  let tuning: RadioTuning
  let primaryAction: () -> Void
  let skipAction: () -> Void
  let likeAction: () -> Void
  let dislikeAction: () -> Void
  let refreshAction: () -> Void
  let tuningAction: (RadioTuning) -> Void

  private var upNextText: String {
    guard !queueItems.isEmpty else { return status.emptyQueueText }
    return queueItems
      .prefix(3)
      .enumerated()
      .map { "\($0.offset + 1). \($0.element.track.title)" }
      .joined(separator: "  ")
  }

  private var sourceText: String {
    currentItem?.source.displayName ?? (track.isAppleMusicTrack ? "Apple Music" : "Local preview")
  }

  private var reasonText: String {
    currentItem?.reason ?? status.reasonText
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
          Text("15 min set")
            .font(.system(size: 25, weight: .heavy, design: .rounded))
            .foregroundStyle(.black)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

          Text("2026/06/16")
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
          source: track.artist.uppercased(),
          message: "Now playing \(track.title), the opening cut from \(track.album).",
          lineLimit: 2
        )

        VStack(alignment: .leading, spacing: 8) {
          Text("Up next")
            .font(.system(size: 16, weight: .heavy, design: .rounded))
            .foregroundStyle(.black.opacity(0.38))

          Text(upNextText)
            .font(.system(size: 19, weight: .heavy, design: .rounded))
            .foregroundStyle(.black)
            .lineLimit(1)
            .minimumScaleFactor(0.58)
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
        RadioActionButton(systemImage: "backward.end.fill", label: "Dislike", action: dislikeAction)
        RadioActionButton(systemImage: "hand.thumbsup.fill", label: "Like", action: likeAction)
        RadioActionButton(systemImage: "forward.end.fill", label: "Skip", action: skipAction)
        RadioActionButton(systemImage: "arrow.clockwise", label: "Refresh", action: refreshAction)
      }
      .disabled(status != .onAir && status != .ready)

      RadioTuningControls(tuning: tuning, action: tuningAction)
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
    case .needsAuthorization:
      return "person.badge.key.fill"
    case .needsSelection:
      return "music.note.list"
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
    case .needsAuthorization:
      return "Connect Apple Music"
    case .needsSelection:
      return "Sync playlists"
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
    case .needsAuthorization:
      "Connect Apple Music so Airset can read your playlists and tune a station."
    case .needsSelection:
      "Choose playlists in Mine. Airset will use them as radio seed material."
    case .ready:
      "Your selected playlists are ready. Start radio to build a living queue."
    case .onAir:
      "The station is listening to your feedback and preparing the next set."
    }
  }

  var emptyQueueText: String {
    switch self {
    case .needsAuthorization:
      "Connect Apple Music"
    case .needsSelection:
      "Pick playlists in Mine"
    case .ready:
      "Tap start to build the queue"
    case .onAir:
      "Refreshing queue"
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

private struct RadioTuningControls: View {
  let tuning: RadioTuning
  let action: (RadioTuning) -> Void

  var body: some View {
    VStack(spacing: 10) {
      RadioSliderRow(
        title: "Discovery",
        value: tuning.discoveryRatio,
        leading: "Safe",
        trailing: "Fresh"
      ) { value in
        var next = tuning
        next.discoveryRatio = value
        action(next)
      }

      RadioSliderRow(
        title: "Familiar",
        value: tuning.familiarity,
        leading: "Wide",
        trailing: "Close"
      ) { value in
        var next = tuning
        next.familiarity = value
        action(next)
      }
    }
    .padding(.top, 2)
  }
}

private struct RadioSliderRow: View {
  let title: String
  let value: Double
  let leading: String
  let trailing: String
  let action: (Double) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack {
        Text(title)
          .font(.system(size: 15, weight: .heavy, design: .rounded))
        Spacer()
        Text("\(Int(value * 100))%")
          .font(.system(size: 13, weight: .bold, design: .rounded))
          .foregroundStyle(.black.opacity(0.44))
      }

      Slider(
        value: Binding(
          get: { value },
          set: action
        ),
        in: 0...1
      )
      .tint(.black)

      HStack {
        Text(leading)
        Spacer()
        Text(trailing)
      }
      .font(.system(size: 12, weight: .bold, design: .rounded))
      .foregroundStyle(.black.opacity(0.38))
    }
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
