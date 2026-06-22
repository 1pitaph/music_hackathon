import MusicKit
import SwiftUI

struct SettingsView: View {
  @Environment(MusicAuthorizationService.self) private var musicAuthorization
  @Environment(RadioStationController.self) private var radioStation

  var body: some View {
    List {
      appleMusicSection
      backendStationSection
      localMemorySection
    }
    .listStyle(.insetGrouped)
    .task {
      await musicAuthorization.refreshAccessState()
      await radioStation.refreshMemoryStatus()
    }
  }

  private var appleMusicSection: some View {
    Section("Apple Music Playback") {
      LabeledContent("Authorization", value: musicAuthorization.statusText)
      LabeledContent("Subscription", value: musicAuthorization.subscriptionText)

      Button {
        Task {
          await musicAuthorization.requestAccess()
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
        }
      } label: {
        Label("Refresh Playback Access", systemImage: "arrow.triangle.2.circlepath")
      }
      .disabled(musicAuthorization.isRequestingAccess)

      if let message = musicAuthorization.lastErrorMessage {
        Text(message)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var backendStationSection: some View {
    Section("Backend Station") {
      LabeledContent("Current station", value: radioStation.stationTitle)
      LabeledContent("Queued tracks", value: "\(radioStation.stationTracks.count)")

      Button {
        Task {
          await radioStation.refreshStation()
        }
      } label: {
        Label(
          radioStation.isLoadingStation ? "Loading" : "Refresh Station",
          systemImage: "dot.radiowaves.left.and.right"
        )
      }
      .disabled(radioStation.isLoadingStation)

      if let message = radioStation.errorMessage {
        Text(message)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var localMemorySection: some View {
    Section("Local Radio Memory") {
      LabeledContent("Recent events", value: "\(radioStation.memoryEventCount)")

      Text(radioStation.memorySummaryText)
        .font(.footnote)
        .foregroundStyle(.secondary)

      Button(role: .destructive) {
        Task {
          await radioStation.clearMemory()
        }
      } label: {
        Label("Clear Local Memory", systemImage: "trash")
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
