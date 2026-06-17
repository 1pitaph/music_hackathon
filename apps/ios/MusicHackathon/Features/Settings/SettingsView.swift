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
          Text(statusText)
            .foregroundStyle(.secondary)
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
      }

      Section("Native Capabilities") {
        Label("Background audio mode is declared", systemImage: "speaker.wave.2")
        Label("Remote command center is wired", systemImage: "dot.radiowaves.left.and.right")
        Label("Playback service is ready for AVPlayer", systemImage: "play.rectangle")
      }
      .foregroundStyle(.secondary)
    }
    .listStyle(.insetGrouped)
    .task {
      musicAuthorization.refresh()
    }
  }

  private var statusText: String {
    switch musicAuthorization.status {
    case .authorized:
      "Authorized"
    case .denied:
      "Denied"
    case .notDetermined:
      "Not Determined"
    case .restricted:
      "Restricted"
    @unknown default:
      "Unknown"
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
