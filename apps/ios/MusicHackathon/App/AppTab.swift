import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
  case radio
  case island
  case mine

  var id: String { rawValue }

  var title: String {
    switch self {
    case .radio:
      "Radio"
    case .island:
      "Island"
    case .mine:
      "Mine"
    }
  }

  var prefersHiddenNavigationBar: Bool {
    switch self {
    case .radio, .island:
      true
    case .mine:
      false
    }
  }

  @ViewBuilder
  var content: some View {
    switch self {
    case .radio:
      DiscoverView()
    case .island:
      IslandView()
    case .mine:
      SettingsView()
    }
  }

  @ViewBuilder
  var label: some View {
    switch self {
    case .radio:
      Label("Radio", systemImage: "dot.radiowaves.left.and.right")
    case .island:
      Label("Island", systemImage: "map.fill")
    case .mine:
      Label("Mine", systemImage: "person.crop.circle")
    }
  }
}
