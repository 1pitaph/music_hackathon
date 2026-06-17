import SwiftUI

struct PlayerView: View {
  @Environment(PlaybackController.self) private var playbackController

  var body: some View {
    VStack(spacing: 24) {
      artwork

      VStack(spacing: 8) {
        Text(playbackController.currentTrack?.title ?? "Ready to play")
          .font(.title2.bold())
          .multilineTextAlignment(.center)

        Text(playbackController.currentTrack?.artist ?? "Choose a track from Discover")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      HStack(spacing: 20) {
        Button {
          playbackController.stop()
        } label: {
          Image(systemName: "stop.fill")
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Stop")

        Button {
          playbackController.togglePlayback()
        } label: {
          Image(systemName: playbackController.state == .playing ? "pause.fill" : "play.fill")
            .font(.title2)
            .frame(width: 56, height: 56)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityLabel(playbackController.state == .playing ? "Pause" : "Play")
      }

      statusText
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal)

      Spacer()
    }
    .padding()
  }

  private var artwork: some View {
    Image(systemName: playbackController.currentTrack?.artworkSystemName ?? "waveform.circle")
      .font(.system(size: 92))
      .foregroundStyle(.tint)
      .frame(width: 180, height: 180)
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
      .accessibilityHidden(true)
  }

  @ViewBuilder
  private var statusText: some View {
    if let message = playbackController.lastErrorMessage {
      Text(message)
    } else if playbackController.currentTrack?.previewURL == nil {
      Text("This scaffold uses fixture tracks without audio files. Add preview URLs or MusicKit playback next.")
    } else {
      Text(playbackController.state.rawValue.capitalized)
    }
  }
}

#Preview {
  NavigationStack {
    PlayerView()
      .navigationTitle("Player")
  }
  .environment(PlaybackController())
}
