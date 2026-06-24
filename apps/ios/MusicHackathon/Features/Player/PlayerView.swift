import SwiftUI

struct PlayerView: View {
  @Environment(PlaybackController.self) private var playbackController

  var body: some View {
    VStack(spacing: 24) {
      artwork

      VStack(spacing: 8) {
        Text(playbackTitle)
          .font(.title2.bold())
          .multilineTextAlignment(.center)

        Text(playbackSubtitle)
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
          Image(systemName: playButtonSystemImage)
            .font(.title2)
            .frame(width: 56, height: 56)
        }
        .buttonStyle(.borderedProminent)
        .disabled(playbackController.state == .loading)
        .accessibilityLabel(playButtonAccessibilityLabel)
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
    Group {
      if playbackController.currentSpeech != nil {
        Image(systemName: "waveform.badge.mic")
          .font(.system(size: 92))
          .foregroundStyle(.tint)
      } else if let artworkURL = playbackController.currentTrack?.artworkURL {
        AsyncImage(url: artworkURL) { image in
          image
            .resizable()
            .scaledToFill()
        } placeholder: {
          Image(systemName: "music.note")
            .font(.system(size: 80))
            .foregroundStyle(.tint)
        }
      } else {
        Image(systemName: playbackController.currentTrack?.artworkSystemName ?? "waveform.circle")
          .font(.system(size: 92))
          .foregroundStyle(.tint)
      }
    }
    .frame(width: 180, height: 180)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    .accessibilityHidden(true)
  }

  @ViewBuilder
  private var statusText: some View {
    if let message = playbackController.lastErrorMessage {
      Text(message)
    } else if playbackController.state == .loading {
      Text("Loading")
    } else if let currentTrack = playbackController.currentTrack, !currentTrack.isPlayable {
      Text("This track is not playable yet.")
    } else if playbackController.activeBackend == .appleMusic {
      Text("Apple Music")
    } else if playbackController.activeBackend == .localPreview {
      Text("Local preview")
    } else if playbackController.activeBackend == .speechAudio || playbackController.activeBackend == .speechSynthesis {
      Text("Airset host")
    } else {
      Text(playbackController.state.rawValue.capitalized)
    }
  }

  private var playbackTitle: String {
    playbackController.currentSpeech == nil
      ? playbackController.currentTrack?.title ?? "Ready to play"
      : "Airset Host"
  }

  private var playbackSubtitle: String {
    playbackController.currentSpeech?.displayText
      ?? playbackController.currentTrack?.artist
      ?? "Choose a track from Discover"
  }

  private var playButtonSystemImage: String {
    if playbackController.state == .loading {
      return "hourglass"
    }

    return playbackController.state == .playing ? "pause.fill" : "play.fill"
  }

  private var playButtonAccessibilityLabel: String {
    if playbackController.state == .loading {
      return "Loading"
    }

    return playbackController.state == .playing ? "Pause" : "Play"
  }
}

#Preview {
  NavigationStack {
    PlayerView()
      .navigationTitle("Player")
  }
  .environment(PlaybackController())
}
