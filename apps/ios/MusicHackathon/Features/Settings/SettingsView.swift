import MusicKit
import SwiftUI

struct SettingsView: View {
  @Environment(MusicAuthorizationService.self) private var musicAuthorization
  @Environment(RadioStationController.self) private var radioStation

  var body: some View {
    List {
      appleMusicSection
      playlistSection
      radioMemorySection
    }
    .listStyle(.insetGrouped)
    .task {
      await musicAuthorization.refreshAccessState()
      if musicAuthorization.status == .authorized, radioStation.playlists.isEmpty {
        await radioStation.refreshLibrary()
      }
    }
  }

  private var appleMusicSection: some View {
    Section("Apple Music") {
      LabeledContent("Authorization", value: musicAuthorization.statusText)
      LabeledContent("Subscription", value: musicAuthorization.subscriptionText)

      Button {
        Task {
          await musicAuthorization.requestAccess()
          if musicAuthorization.status == .authorized {
            await radioStation.refreshLibrary()
          }
        }
      } label: {
        Label(
          musicAuthorization.isRequestingAccess ? "Requesting" : "Connect Apple Music",
          systemImage: "person.badge.key"
        )
      }
      .disabled(musicAuthorization.isRequestingAccess || musicAuthorization.status == .authorized)

      Button {
        Task {
          await musicAuthorization.refreshAccessState()
          await radioStation.refreshLibrary()
        }
      } label: {
        Label(radioStation.isSyncingLibrary ? "Syncing" : "Sync Playlists", systemImage: "arrow.triangle.2.circlepath")
      }
      .disabled(musicAuthorization.status != .authorized || radioStation.isSyncingLibrary)

      if let message = musicAuthorization.lastErrorMessage ?? radioStation.errorMessage {
        Text(message)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var playlistSection: some View {
    Section {
      if musicAuthorization.status != .authorized {
        ContentUnavailableView(
          "Connect Apple Music",
          systemImage: "music.note.house",
          description: Text("Your playlists become the seed material for Airset Radio.")
        )
        .listRowBackground(Color.clear)
      } else if radioStation.isSyncingLibrary {
        HStack {
          ProgressView()
          Text("Syncing playlists")
            .foregroundStyle(.secondary)
        }
      } else if radioStation.playlists.isEmpty {
        ContentUnavailableView(
          "No Playlists Yet",
          systemImage: "music.note.list",
          description: Text("Sync Apple Music to choose playlists for your station.")
        )
        .listRowBackground(Color.clear)
      } else {
        ForEach(radioStation.playlists) { playlist in
          Toggle(isOn: playlistBinding(for: playlist.id)) {
            VStack(alignment: .leading, spacing: 4) {
              Text(playlist.name)
              Text(playlist.curatorName ?? "Apple Music library")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
    } header: {
      Text("Radio Seeds")
    } footer: {
      Text("\(radioStation.selectedPlaylistIDs.count) selected • Last sync: \(radioStation.lastSyncText)")
    }
  }

  private var radioMemorySection: some View {
    Section("Radio Engine") {
      Label("Personal queue uses selected playlists", systemImage: "music.note.list")
      Label("Catalog discovery mix defaults to 30%", systemImage: "sparkles")
      Label("Likes, skips, and dislikes are remembered", systemImage: "brain.head.profile")
      Label("DJ narration adapter is local for now", systemImage: "quote.bubble")
    }
    .foregroundStyle(.secondary)
  }

  private func playlistBinding(for playlistID: String) -> Binding<Bool> {
    Binding {
      radioStation.selectedPlaylistIDs.contains(playlistID)
    } set: { isSelected in
      var nextIDs = radioStation.selectedPlaylistIDs
      if isSelected {
        nextIDs.insert(playlistID)
      } else {
        nextIDs.remove(playlistID)
      }

      Task {
        await radioStation.setSelectedPlaylistIDs(nextIDs)
      }
    }
  }
}

#Preview {
  let playbackController = PlaybackController()
  NavigationStack {
    SettingsView()
      .navigationTitle("Mine")
  }
  .environment(playbackController)
  .environment(RadioStationController(playbackController: playbackController))
  .environment(MusicAuthorizationService())
}
