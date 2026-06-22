import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
  case radio
  case mine

  var id: String { rawValue }

  var title: String {
    switch self {
    case .radio:
      "Radio"
    case .mine:
      "Mine"
    }
  }

  var prefersHiddenNavigationBar: Bool {
    switch self {
    case .radio:
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
    case .mine:
      SettingsView()
    }
  }

  @ViewBuilder
  var label: some View {
    switch self {
    case .radio:
      Label("Radio", systemImage: "dot.radiowaves.left.and.right")
    case .mine:
      Label("Mine", systemImage: "person.crop.circle")
    }
  }
}
