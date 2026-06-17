import SwiftUI

struct AppView: View {
  @State private var selectedTab: AppTab = .discover

  var body: some View {
    TabView(selection: $selectedTab) {
      ForEach(AppTab.allCases) { tab in
        NavigationStack {
          tab.content
            .navigationTitle(tab.title)
        }
        .tabItem { tab.label }
        .tag(tab)
      }
    }
  }
}

#Preview {
  AppView()
    .environment(PlaybackController())
    .environment(MusicAuthorizationService())
}
