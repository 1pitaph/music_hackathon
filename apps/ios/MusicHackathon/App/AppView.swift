import FluidGradient
import SwiftUI

struct AppView: View {
  @State private var selectedTab: AppTab = .radio

  var body: some View {
    tabView
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
          ZStack {
            AppBackdrop()
              .ignoresSafeArea()

            tab.content
          }
          .navigationTitle(tab.title)
          .toolbar(tab.prefersHiddenNavigationBar ? .hidden : .automatic, for: .navigationBar)
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
      FluidGradient(
        blobs: [
          Color(red: 0.04, green: 0.36, blue: 0.42),
          Color(red: 0.68, green: 0.44, blue: 0.24),
          Color(red: 0.34, green: 0.13, blue: 0.26),
          Color(red: 0.05, green: 0.09, blue: 0.17)
        ],
        highlights: [
          Color(red: 0.46, green: 0.78, blue: 0.78),
          Color(red: 0.88, green: 0.58, blue: 0.30),
          Color(red: 0.57, green: 0.22, blue: 0.36)
        ],
        speed: 0.35,
        blur: 0.78
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(red: 0.05, green: 0.04, blue: 0.03))

      LinearGradient(
        colors: [
          .white.opacity(0.08),
          .clear,
          .black.opacity(0.58)
        ],
        startPoint: .top,
        endPoint: .bottom
      )

      LinearGradient(
        colors: [
          .clear,
          Color(red: 0.11, green: 0.05, blue: 0.03).opacity(0.68)
        ],
        startPoint: .center,
        endPoint: .bottom
      )
    }
  }
}

#Preview {
  let playbackController = PlaybackController()
  AppView()
    .environment(playbackController)
    .environment(RadioStationController(playbackController: playbackController))
    .environment(MusicAuthorizationService())
}
