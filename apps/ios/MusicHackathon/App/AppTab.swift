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

  @ViewBuilder
  var content: some View {
    switch self {
    case .radio:
      DiscoverView()
    case .island:
      LibraryView()
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
      Label("Island", systemImage: "person.2.wave.2")
    case .mine:
      Label("Mine", systemImage: "person.crop.circle")
    }
  }
}
