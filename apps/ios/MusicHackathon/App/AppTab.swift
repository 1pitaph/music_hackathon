import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
  case radio
  case discover
  case mine

  var id: String { rawValue }

  var title: String {
    switch self {
    case .radio:
      "电台"
    case .discover:
      "发现"
    case .mine:
      "我的"
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
    case .radio, .discover:
      true
    case .mine:
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
      Label("电台", systemImage: "dot.radiowaves.left.and.right")
    case .discover:
      Label("发现", systemImage: "music.note.list")
    case .mine:
      Label("我的", systemImage: "person.crop.circle")
    }
  }
}
