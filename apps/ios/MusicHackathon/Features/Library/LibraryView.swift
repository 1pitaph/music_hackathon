import SwiftUI

struct LibraryView: View {
  var body: some View {
    List {
      Section("Playlists") {
        ForEach(MockCatalog.playlists, id: \.self) { playlist in
          NavigationLink {
            PlaylistDetailView(title: playlist)
          } label: {
            Label(playlist, systemImage: "music.note.list")
          }
        }
      }

      Section("Next Integrations") {
        Label("MusicKit library sync", systemImage: "checklist")
        Label("SwiftData local cache", systemImage: "externaldrive")
        Label("Generated API client", systemImage: "point.3.connected.trianglepath.dotted")
      }
      .foregroundStyle(.secondary)
    }
    .listStyle(.insetGrouped)
  }
}

private struct PlaylistDetailView: View {
  let title: String

  var body: some View {
    ContentUnavailableView(
      title,
      systemImage: "music.note.list",
      description: Text("Playlist details will connect to MusicKit or the backend catalog.")
    )
  }
}

#Preview {
  NavigationStack {
    LibraryView()
      .navigationTitle("Library")
  }
}
