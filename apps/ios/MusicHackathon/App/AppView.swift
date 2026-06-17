import SwiftUI

struct AppView: View {
  @State private var selectedTab: AppTab = .radio

  var body: some View {
    ZStack {
      AppBackdrop()
        .ignoresSafeArea()

      tabView
    }
    .tint(.cyan)
    .preferredColorScheme(.dark)
  }

  @ViewBuilder
  private var tabView: some View {
    if #available(iOS 26.0, *) {
      systemTabView
        .tabBarMinimizeBehavior(.never)
    } else {
      systemTabView
    }
  }

  private var systemTabView: some View {
    TabView(selection: $selectedTab) {
      ForEach(AppTab.allCases) { tab in
        NavigationStack {
          tab.content
            .navigationTitle(tab.title)
            .toolbar(tab == .radio ? .hidden : .automatic, for: .navigationBar)
        }
        .tabItem { tab.label }
        .tag(tab)
      }
    }
  }
}

private struct AppBackdrop: View {
  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(red: 0.26, green: 0.36, blue: 0.38),
          Color(red: 0.56, green: 0.45, blue: 0.34),
          Color(red: 0.14, green: 0.06, blue: 0.02)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

      LinearGradient(
        colors: [
          .white.opacity(0.18),
          .clear,
          .black.opacity(0.72)
        ],
        startPoint: .top,
        endPoint: .bottom
      )

      LinearGradient(
        colors: [
          .clear,
          Color(red: 0.21, green: 0.10, blue: 0.03).opacity(0.92)
        ],
        startPoint: .center,
        endPoint: .bottom
      )
    }
  }
}

#Preview {
  AppView()
    .environment(PlaybackController())
    .environment(MusicAuthorizationService())
}
