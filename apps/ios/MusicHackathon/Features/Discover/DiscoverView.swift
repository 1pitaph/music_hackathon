import SwiftUI

struct DiscoverView: View {
  @Environment(PlaybackController.self) private var playbackController

  var body: some View {
    List {
      Section {
        ForEach(MockCatalog.featuredTracks) { track in
          TrackRow(track: track) {
            playbackController.play(track: track)
          }
        }
      } header: {
        Text("Featured")
      } footer: {
        Text("Fixture tracks are placeholders until MusicKit catalog search or your own backend is connected.")
      }
    }
    .listStyle(.insetGrouped)
  }
}

private struct TrackRow: View {
  let track: Track
  let play: () -> Void

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: track.artworkSystemName)
        .font(.title2)
        .foregroundStyle(.tint)
        .frame(width: 44, height: 44)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))

      VStack(alignment: .leading, spacing: 4) {
        Text(track.title)
          .font(.headline)
        Text("\(track.artist) · \(track.mood)")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Button(action: play) {
        Image(systemName: "play.fill")
      }
      .buttonStyle(.bordered)
      .accessibilityLabel("Play \(track.title)")
    }
    .padding(.vertical, 4)
  }
}

#Preview {
  NavigationStack {
    DiscoverView()
      .navigationTitle("Discover")
  }
  .environment(PlaybackController())
}
