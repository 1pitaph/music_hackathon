import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
  case discover
  case library
  case player
  case settings

  var id: String { rawValue }

  var title: String {
    switch self {
    case .discover:
      "Discover"
    case .library:
      "Library"
    case .player:
      "Player"
    case .settings:
      "Settings"
    }
  }

  @ViewBuilder
  var content: some View {
    switch self {
    case .discover:
      DiscoverView()
    case .library:
      LibraryView()
    case .player:
      PlayerView()
    case .settings:
      SettingsView()
    }
  }

  @ViewBuilder
  var label: some View {
    switch self {
    case .discover:
      Label("Discover", systemImage: "sparkles")
    case .library:
      Label("Library", systemImage: "music.note.list")
    case .player:
      Label("Player", systemImage: "play.circle")
    case .settings:
      Label("Settings", systemImage: "gearshape")
    }
  }
}
