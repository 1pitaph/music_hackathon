import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
  case radio
  case discover
  case mine

  var id: String { rawValue }

  var title: String {
    switch self {
    case .radio:
      L10n.tr("tab.radio")
    case .discover:
      L10n.tr("tab.discover")
    case .mine:
      L10n.tr("tab.mine")
    }
  }

  var navigationTitle: String {
    switch self {
    case .mine:
      ""
    case .radio, .discover:
      title
    }
  }

  var prefersHiddenNavigationBar: Bool {
    switch self {
    case .radio:
      true
    case .discover, .mine:
      false
    }
  }

  @ViewBuilder
  var content: some View {
    switch self {
    case .radio:
      RadioView()
    case .discover:
      DiscoverView()
    case .mine:
      MineView()
    }
  }

  @ViewBuilder
  var label: some View {
    switch self {
    case .radio:
      Label(L10n.tr("tab.radio"), systemImage: "dot.radiowaves.left.and.right")
    case .discover:
      Label(L10n.tr("tab.discover"), systemImage: "music.note.list")
    case .mine:
      Label(L10n.tr("tab.mine"), systemImage: "person.crop.circle")
    }
  }
}
