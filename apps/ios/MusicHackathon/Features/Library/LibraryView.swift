import SwiftUI

struct LibraryView: View {
  @Environment(MusicAuthorizationService.self) private var musicAuthorization

  @State private var playlists: [AppleMusicPlaylistSummary] = []
  @State private var isLoadingPlaylists = false
  @State private var errorMessage: String?

  private let catalogService = AppleMusicCatalogService()

  var body: some View {
    List {
      Section("Playlists") {
        if playlists.isEmpty {
          ForEach(MockCatalog.playlists, id: \.self) { playlist in
            NavigationLink {
              PlaylistDetailView(title: playlist, subtitle: "Connect Apple Music to load this playlist.")
            } label: {
              Label(playlist, systemImage: "music.note.list")
            }
          }
        } else {
          ForEach(playlists) { playlist in
            NavigationLink {
              PlaylistDetailView(
                title: playlist.name,
                subtitle: playlist.curatorName ?? "Apple Music library"
              )
            } label: {
              Label(playlist.name, systemImage: "music.note.list")
            }
          }
        }
      }

      Section("Apple Music") {
        HStack {
          Label("Library access", systemImage: "person.badge.key")
          Spacer()
          Text(musicAuthorization.statusText)
            .foregroundStyle(.secondary)
        }

        Button {
          Task {
            await musicAuthorization.requestAccess()
            await loadPlaylists()
          }
        } label: {
          Label(
            musicAuthorization.isRequestingAccess ? "Requesting" : "Request Access",
            systemImage: "music.note.house"
          )
        }
        .disabled(musicAuthorization.isRequestingAccess || musicAuthorization.status == .authorized)

        Button {
          Task {
            await loadPlaylists()
          }
        } label: {
          Label(isLoadingPlaylists ? "Loading" : "Refresh Playlists", systemImage: "arrow.clockwise")
        }
        .disabled(isLoadingPlaylists)

        if let errorMessage {
          Text(errorMessage)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
    }
    .listStyle(.insetGrouped)
    .task {
      await musicAuthorization.refreshAccessState()
      await loadPlaylists()
    }
  }

  private func loadPlaylists() async {
    guard !isLoadingPlaylists else { return }
    guard musicAuthorization.status == .authorized else { return }

    isLoadingPlaylists = true
    errorMessage = nil

    do {
      playlists = try await catalogService.libraryPlaylists()
    } catch {
      errorMessage = error.localizedDescription
    }

    isLoadingPlaylists = false
  }
}

private struct PlaylistDetailView: View {
  let title: String
  let subtitle: String

  var body: some View {
    ContentUnavailableView(
      title,
      systemImage: "music.note.list",
      description: Text(subtitle)
    )
  }
}

#Preview {
  NavigationStack {
    LibraryView()
      .navigationTitle("Library")
  }
  .environment(MusicAuthorizationService())
}
