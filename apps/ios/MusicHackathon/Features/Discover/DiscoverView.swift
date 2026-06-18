import SwiftUI

struct DiscoverView: View {
  @Environment(PlaybackController.self) private var playbackController

  @State private var featuredTracks: [Track] = MockCatalog.featuredTracks
  @State private var isLoadingCatalog = false

  private let catalogService = AppleMusicCatalogService()

  var body: some View {
    GeometryReader { proxy in
      ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 0) {
          RadioHeaderCard(
            track: featuredTrack,
            state: playbackController.state,
            elapsedTimeText: playbackController.elapsedTimeText
          )
            .padding(.horizontal, 10)
            .padding(.top, 28)

          NowPlayingSetCard(
            track: featuredTrack,
            tracks: featuredTracks,
            isPlaying: playbackController.state == .playing,
            isLoading: playbackController.state == .loading || isLoadingCatalog,
            elapsedTimeText: playbackController.elapsedTimeText,
            playAction: toggleFeaturedTrack
          )
          .padding(.horizontal, 10)
          .offset(y: -20)
        }
        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        .clipped()
      }
      .scrollBounceBehavior(.always, axes: .vertical)
    }
    .background(.clear)
    .task {
      await loadAppleMusicTracks()
    }
  }

  private var featuredTrack: Track {
    playbackController.currentTrack ?? featuredTracks[0]
  }

  private func toggleFeaturedTrack() {
    if playbackController.currentTrack == nil {
      playbackController.play(track: featuredTrack)
    } else {
      playbackController.togglePlayback()
    }
  }

  private func loadAppleMusicTracks() async {
    guard !isLoadingCatalog else { return }

    isLoadingCatalog = true
    defer { isLoadingCatalog = false }

    do {
      let appleMusicTracks = try await catalogService.featuredTracks()
      if !appleMusicTracks.isEmpty {
        featuredTracks = Array(appleMusicTracks.prefix(3))
      }
    } catch {
      featuredTracks = await catalogService.enrich(MockCatalog.featuredTracks)
    }
  }
}

private struct RadioHeaderCard: View {
  let track: Track
  let state: PlaybackState
  let elapsedTimeText: String

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          Text("\(track.artist.uppercased()) Radio")
            .font(.system(size: 24, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)

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
    }
    .padding(.horizontal, 24)
    .padding(.top, 22)
    .padding(.bottom, 28)
    .frame(maxWidth: .infinity, minHeight: 238, alignment: .topLeading)
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
  let tracks: [Track]
  let isPlaying: Bool
  let isLoading: Bool
  let elapsedTimeText: String
  let playAction: () -> Void

  private var upNextText: String {
    let nextTracks = tracks
      .filter { $0.id != track.id }
      .prefix(2)
      .enumerated()
    return nextTracks
      .map { "\($0.offset + 2). \($0.element.title)" }
      .joined(separator: "  ")
  }

  private var sourceText: String {
    track.isAppleMusicTrack ? "Apple Music" : "Local preview"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
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

      VStack(alignment: .leading, spacing: 14) {
        FeedLine(
          source: "MusicDiscover",
          message: "\(track.artist) sets the tone with \(track.mood.lowercased()) color, ready for your Apple Music queue.",
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

        Button(action: playAction) {
          Image(systemName: playButtonSystemImage)
            .font(.system(size: 31, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 64, height: 64)
            .background(.black, in: Circle())
        }
        .disabled(isLoading)
        .accessibilityLabel(playButtonAccessibilityLabel)
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 48)
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

    return isPlaying ? "pause.fill" : "play.fill"
  }

  private var playButtonAccessibilityLabel: String {
    if isLoading {
      return "Loading"
    }

    return isPlaying ? "Pause" : "Play"
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
  NavigationStack {
    DiscoverView()
  }
  .environment(PlaybackController())
}
