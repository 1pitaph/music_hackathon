import MusicKit
import SwiftUI

struct SettingsView: View {
  @Environment(MusicAuthorizationService.self) private var musicAuthorization

  var body: some View {
    List {
      Section("Apple Music") {
        HStack {
          Label("Authorization", systemImage: "music.note")
          Spacer()
          Text(musicAuthorization.statusText)
            .foregroundStyle(.secondary)
        }

        HStack {
          Label("Subscription", systemImage: "play.circle")
          Spacer()
          Text(musicAuthorization.subscriptionText)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
        }

        Button {
          Task {
            await musicAuthorization.requestAccess()
          }
        } label: {
          Label(
            musicAuthorization.isRequestingAccess ? "Requesting" : "Request Access",
            systemImage: "person.badge.key"
          )
        }
        .disabled(musicAuthorization.isRequestingAccess || musicAuthorization.status == .authorized)

        Button {
          Task {
            await musicAuthorization.refreshAccessState()
          }
        } label: {
          Label(
            musicAuthorization.isRefreshingSubscription ? "Checking" : "Refresh Status",
            systemImage: "arrow.clockwise"
          )
        }
        .disabled(musicAuthorization.isRequestingAccess || musicAuthorization.isRefreshingSubscription)

        if let message = musicAuthorization.lastErrorMessage {
          Text(message)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }

      Section("Native Capabilities") {
        Label("Background audio mode is declared", systemImage: "speaker.wave.2")
        Label("Remote command center is wired", systemImage: "dot.radiowaves.left.and.right")
        Label("MusicKit catalog playback is wired", systemImage: "music.note.tv")
        Label("Local preview fallback is retained", systemImage: "play.rectangle")
      }
      .foregroundStyle(.secondary)
    }
    .listStyle(.insetGrouped)
    .task {
      await musicAuthorization.refreshAccessState()
    }
  }
}

#Preview {
  NavigationStack {
    SettingsView()
      .navigationTitle("Settings")
  }
  .environment(MusicAuthorizationService())
}
