import SpriteKit
import SwiftUI

struct IslandView: View {
  @Environment(PlaybackController.self) private var playbackController

  @State private var islands: [MusicIsland]
  @State private var selectedIslandID: UUID?
  @State private var scene: IslandScene
  @State private var coordinator = IslandSceneCoordinator()
  @State private var didResetInitialSelection = false

  private let catalogService = AppleMusicCatalogService()
  private let mapGenerator = IslandMapGenerator(seed: 170342)

  init() {
    let generatedIslands = IslandMapGenerator(seed: 170342).generate(from: MockCatalog.featuredTracks)
    _islands = State(initialValue: generatedIslands)
    _scene = State(initialValue: IslandScene(islands: generatedIslands))
  }

  var body: some View {
    ZStack {
      SpriteView(scene: scene, options: [.allowsTransparency])
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()

      VStack(spacing: 0) {
        IslandFilterBar()
          .padding(.horizontal, 18)
          .padding(.top, 18)

        Spacer()

        if let selectedIsland {
          IslandDetailCard(
            island: selectedIsland,
            isCurrentTrack: selectedIsland.track == playbackController.currentTrack,
            playAction: {
              guard let track = selectedIsland.track else { return }
              playbackController.play(track: track)
            }
          )
          .padding(.horizontal, 16)
          .padding(.bottom, 18)
          .transition(.move(edge: .bottom).combined(with: .opacity))
        }
      }

      VStack(spacing: 12) {
        IslandRoundButton(systemImage: "plus") {
          scene.zoomIn()
        }
        .accessibilityLabel("Zoom in")

        IslandRoundButton(systemImage: "minus") {
          scene.zoomOut()
        }
        .accessibilityLabel("Zoom out")

        IslandRoundButton(systemImage: "scope") {
          scene.resetCamera()
        }
        .accessibilityLabel("Reset island map")
      }
      .padding(.trailing, 18)
      .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .background(Color(red: 0.93, green: 0.98, blue: 0.94))
    .toolbar(.hidden, for: .navigationBar)
    .onAppear {
      configureScene()

      if !didResetInitialSelection {
        selectedIslandID = nil
        scene.clearSelection()
        didResetInitialSelection = true
      }
    }
    .task {
      await loadAppleMusicIslands()
    }
  }

  private var selectedIsland: MusicIsland? {
    guard let selectedIslandID else { return nil }
    return islands.first { $0.id == selectedIslandID }
  }

  private func loadAppleMusicIslands() async {
    let enrichedTracks = await catalogService.enrich(MockCatalog.featuredTracks)
    guard enrichedTracks.contains(where: { $0.isAppleMusicTrack }) else { return }

    let generatedIslands = mapGenerator.generate(from: enrichedTracks)
    islands = generatedIslands
    scene = IslandScene(islands: generatedIslands)
    selectedIslandID = nil
    configureScene()
  }

  private func configureScene() {
    scene.coordinator = coordinator
    coordinator.onSelectionChanged = { islandID in
      withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
        selectedIslandID = islandID
      }
    }
  }
}

private struct IslandFilterBar: View {
  var body: some View {
    HStack(spacing: 10) {
      Label("Map", systemImage: "map")
        .font(.system(size: 17, weight: .heavy, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .frame(height: 56)
        .background(Color(red: 0.04, green: 0.25, blue: 0.17), in: Capsule())

      Label("Mood", systemImage: "slider.horizontal.3")
        .font(.system(size: 17, weight: .bold, design: .rounded))
        .foregroundStyle(Color(red: 0.04, green: 0.16, blue: 0.13))
        .padding(.horizontal, 17)
        .frame(height: 56)
        .background(.white.opacity(0.88), in: Capsule())
        .overlay {
          Capsule()
            .stroke(Color.black.opacity(0.12), lineWidth: 1)
        }

      Spacer(minLength: 4)

      Button {
        sceneResetNotification()
      } label: {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 23, weight: .semibold))
          .foregroundStyle(Color(red: 0.04, green: 0.16, blue: 0.13))
          .frame(width: 58, height: 58)
          .background(.white.opacity(0.90), in: Circle())
          .overlay {
            Circle()
              .stroke(Color.black.opacity(0.13), lineWidth: 1)
          }
      }
      .accessibilityLabel("Search islands")
    }
  }

  private func sceneResetNotification() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }
}

private struct IslandRoundButton: View {
  let systemImage: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 23, weight: .semibold))
        .foregroundStyle(Color(red: 0.04, green: 0.16, blue: 0.13))
        .frame(width: 58, height: 58)
        .background(.white.opacity(0.90), in: Circle())
        .overlay {
          Circle()
            .stroke(Color.black.opacity(0.13), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.10), radius: 14, y: 7)
    }
  }
}

private struct IslandDetailCard: View {
  let island: MusicIsland
  let isCurrentTrack: Bool
  let playAction: () -> Void

  var body: some View {
    HStack(spacing: 14) {
      ZStack {
        Circle()
          .fill(Color(red: 0.39, green: 0.91, blue: 0.33))

        Image(systemName: island.track == nil ? "sparkles" : "music.note")
          .font(.system(size: 25, weight: .heavy))
          .foregroundStyle(Color(red: 0.04, green: 0.25, blue: 0.17))
      }
      .frame(width: 64, height: 64)

      VStack(alignment: .leading, spacing: 5) {
        Text(island.title)
          .font(.system(size: 20, weight: .heavy, design: .rounded))
          .foregroundStyle(.white)
          .lineLimit(1)
          .minimumScaleFactor(0.72)

        Text(island.subtitle)
          .font(.system(size: 14, weight: .bold, design: .rounded))
          .foregroundStyle(.white.opacity(0.66))
          .lineLimit(1)
          .minimumScaleFactor(0.72)

        Text(island.mood)
          .font(.system(size: 13, weight: .heavy, design: .rounded))
          .foregroundStyle(Color(red: 0.54, green: 0.92, blue: 0.66))
      }

      Spacer(minLength: 4)

      Button(action: playAction) {
        Image(systemName: isCurrentTrack ? "waveform" : "play.fill")
          .font(.system(size: 22, weight: .heavy))
          .foregroundStyle(Color(red: 0.04, green: 0.25, blue: 0.17))
          .frame(width: 54, height: 54)
          .background(.white, in: Circle())
      }
      .disabled(island.track == nil)
      .opacity(island.track == nil ? 0.36 : 1)
      .accessibilityLabel(isCurrentTrack ? "Now playing" : "Play island track")
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity)
    .background(Color(red: 0.04, green: 0.25, blue: 0.17), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 28, style: .continuous)
        .stroke(.white.opacity(0.13), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.20), radius: 22, y: 12)
  }
}

#Preview {
  NavigationStack {
    IslandView()
  }
  .environment(PlaybackController())
}
