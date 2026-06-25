import SwiftUI

struct RadioView: View {
  @Environment(PlaybackController.self) private var playbackController
  @Environment(RadioStationController.self) private var radioStation
  @Environment(MusicAuthorizationService.self) private var musicAuthorization
  @Environment(AppleMusicLibraryStore.self) private var appleMusicLibrary

  @GestureState private var cardDragOffset: CGFloat = 0

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
            station: radioStation.station,
            currentItem: radioStation.currentItem,
            queueItems: radioStation.upNextItems,
            status: panelStatus,
            isPlaying: playbackController.state == .playing,
            isLoading: playbackController.state == .loading || radioStation.isLoadingStation,
            isExtending: radioStation.isExtendingStation,
            elapsedTimeText: playbackController.elapsedTimeText,
            primaryAction: primaryRadioAction
          )
          .padding(.horizontal, 10)
          .offset(y: -44)

          RadioSpeechSubtitleCard(
            speech: speechSubtitleSegment,
            activeCue: playbackController.currentSpeechCue,
            isActive: playbackController.currentSpeech != nil,
            elapsedTimeText: playbackController.elapsedTimeText,
            isLoading: radioStation.isLoadingStation
          )
          .padding(.horizontal, 10)
          .padding(.top, 12)
          .offset(y: -44)
        }
        .padding(.bottom, 96)
        .frame(width: proxy.size.width, alignment: .top)
        .frame(minHeight: proxy.size.height, alignment: .top)
        .offset(y: cardDragOffset)
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: cardDragOffset)
        .contentShape(Rectangle())
        .simultaneousGesture(cardReturnGesture)
      }
      .scrollDisabled(true)
      .scrollBounceBehavior(.always, axes: .vertical)
    }
    .background(.clear)
    .task {
      await musicAuthorization.refreshAccessState()
      await appleMusicLibrary.loadIfNeeded(authorizationStatus: musicAuthorization.status)

      if !radioStation.hasStationContent, !radioStation.isLoadingStation {
        await radioStation.loadCurrentStation()
      }
    }
  }

  private var cardReturnGesture: some Gesture {
    DragGesture(minimumDistance: 10, coordinateSpace: .local)
      .updating($cardDragOffset) { value, state, _ in
        guard abs(value.translation.height) > abs(value.translation.width) else { return }
        state = rubberBandOffset(for: value.translation.height)
      }
  }

  private func rubberBandOffset(for translation: CGFloat) -> CGFloat {
    let limit: CGFloat = 58
    let magnitude = min(abs(translation), 220)
    let eased = limit * (1 - (1 / ((magnitude * 0.55 / limit) + 1)))
    return translation < 0 ? -eased : eased
  }

  private var displayTrack: Track {
    playbackController.currentTrack
      ?? radioStation.currentItem?.track
      ?? radioStation.queue.first?.track
      ?? MockCatalog.featuredTracks[0]
  }

  private var speechSubtitleSegment: RadioSpeechPlaybackSegment? {
    playbackController.currentSpeech ?? radioStation.upcomingSpeechSegment
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
      if playbackController.currentSpeech != nil {
        playbackController.togglePlayback()
      } else if radioStation.currentItem == nil {
        Task {
          await radioStation.startStation()
        }
      } else {
        playbackController.togglePlayback()
      }
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
      L10n.tr("radio.status.onAir")
    case .loading:
      L10n.tr("playback.loading")
    case .failed:
      L10n.tr("playback.error.short")
    case .paused:
      L10n.tr("playback.paused")
    case .idle:
      L10n.tr("playback.readyToPlay")
    }
  }
}

private struct NowPlayingSetCard: View {
  let track: Track
  let station: RadioStation?
  let currentItem: RadioQueueItem?
  let queueItems: [RadioQueueItem]
  let status: RadioPanelStatus
  let isPlaying: Bool
  let isLoading: Bool
  let isExtending: Bool
  let elapsedTimeText: String
  let primaryAction: () -> Void

  private var nextItem: RadioQueueItem? {
    queueItems.first
  }

  private var queueMetaTitle: String {
    nextItem?.track.durationText ?? L10n.tr("radio.queue.radioSet")
  }

  private var queueMetaDetail: String {
    nextItem == nil ? L10n.tr("radio.queue.awaitingQueue") : L10n.tr("radio.queue.nextUp")
  }

  private var sourceText: String {
    currentItem?.sourceTitle ?? queueItems.first?.sourceTitle ?? L10n.tr("radio.backendStation")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top) {
        HStack(alignment: .top, spacing: 12) {
          artwork

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

      if isExtending {
        Label(L10n.tr("radio.extendingNextSegment"), systemImage: "sparkles")
          .font(.system(size: 14, weight: .heavy, design: .rounded))
          .foregroundStyle(.black.opacity(0.5))
          .lineLimit(1)
          .minimumScaleFactor(0.78)
          .padding(.top, 2)
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 36)
    .padding(.bottom, 20)
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

  private var artwork: some View {
    ArtworkImageView(resolution: artworkResolution, showsLoadingIndicator: false) {
      Color.clear
    }
    .frame(width: 66, height: 66)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(.black.opacity(0.08), lineWidth: 1)
    }
    .accessibilityHidden(true)
  }

  private var artworkResolution: ArtworkResolution {
    ArtworkResolution(remoteURLs: [track.artworkURL])
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
      return L10n.tr("playback.loading")
    }

    switch status {
    case .loading:
      return L10n.tr("radio.loadingStation")
    case .ready:
      return L10n.tr("radio.start")
    case .onAir:
      return isPlaying ? L10n.tr("common.pause") : L10n.tr("common.play")
    }
  }
}

private struct RadioSpeechSubtitleCard: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let speech: RadioSpeechPlaybackSegment?
  let activeCue: RadioSpeechCue?
  let isActive: Bool
  let elapsedTimeText: String
  let isLoading: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("\(subtitleTitle) • \(subtitleTimeText)")
        .font(.system(size: 17, weight: .heavy, design: .rounded))
        .foregroundStyle(.black.opacity(0.36))
        .lineLimit(1)
        .minimumScaleFactor(0.76)

      Text(captionText)
        .id(captionIdentity)
        .font(.system(size: 26, weight: .heavy, design: .rounded))
        .foregroundStyle(.black)
        .lineSpacing(3)
        .lineLimit(4)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: captionIdentity)
    .padding(.horizontal, 20)
    .padding(.vertical, 18)
    .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
    .background(
      Color(red: 0.98, green: 0.97, blue: 0.93),
      in: RoundedRectangle(cornerRadius: 30, style: .continuous)
    )
    .overlay(alignment: .top) {
      LinearGradient(
        colors: [.white.opacity(0.76), .clear],
        startPoint: .top,
        endPoint: .bottom
      )
      .frame(height: 78)
      .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
    .overlay {
      RoundedRectangle(cornerRadius: 30, style: .continuous)
        .stroke(.white.opacity(0.7), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(subtitleTitle), \(subtitleTimeText), \(captionText)")
  }

  private var subtitleTitle: String {
    guard let speech else {
      return isLoading ? L10n.tr("radio.subtitle.loadingTitle") : L10n.tr("radio.subtitle.idleTitle")
    }

    switch speech.kind {
    case .stationIntro:
      return L10n.tr("radio.subtitle.stationIntro")
    case .transition:
      return isActive ? L10n.tr("radio.subtitle.transitionActive") : L10n.tr("radio.subtitle.transitionNext")
    }
  }

  private var subtitleTimeText: String {
    if isActive {
      return elapsedTimeText
    }

    return isLoading ? L10n.tr("playback.loading") : L10n.tr("radio.subtitle.readyToPlay")
  }

  private var captionText: String {
    guard let speech else {
      return isLoading
        ? L10n.tr("radio.subtitle.loadingCaption")
        : L10n.tr("radio.subtitle.idleCaption")
    }

    if let cue = displayCue {
      let displayText = cue.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
      if !displayText.isEmpty {
        return displayText
      }
    }

    let displayText = speech.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !displayText.isEmpty {
      return Self.firstSentence(in: displayText)
    }

    return Self.firstSentence(in: speech.text)
  }

  private var captionIdentity: String {
    if let speech, let displayCue {
      return "\(speech.id)-\(displayCue.id)"
    }
    return "\(speech?.id ?? "empty")-\(captionText)"
  }

  private var displayCue: RadioSpeechCue? {
    if isActive, let activeCue {
      return activeCue
    }
    return speech?.timedCues.first
  }

  private static func firstSentence(in text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return trimmed }

    if let terminatorIndex = trimmed.firstIndex(where: { ".!?。！？".contains($0) }) {
      return String(trimmed[...terminatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return trimmed
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
    RadioView()
  }
  .environment(playbackController)
  .environment(RadioStationController(playbackController: playbackController))
  .environment(MusicAuthorizationService())
  .environment(AppleMusicLibraryStore())
  .environment(ImageAssetStore())
  .environment(ArtworkAnalysisStore())
}
