import SwiftUI

struct DiscoverView: View {
  @Environment(PlaybackController.self) private var playbackController
  @Environment(RadioStationController.self) private var radioStation

  @State private var currentIndex = 0
  @State private var favoritedIDs: Set<String> = []
  @State private var expandedStationID: String?
  @State private var activeStationID: String?
  @State private var presentedPlayerStation: DiscoverStation?

  private let stations = DiscoverStation.mockStations

  var body: some View {
    ZStack {
      ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 26) {
          header

          DiscoverCardStack(
            stations: stations,
            currentIndex: currentIndex,
            isPlaying: isCurrentCardPlaying,
            favoritedIDs: favoritedIDs,
            expandedStationID: expandedStationID,
            onPlayToggle: toggleCurrentStationPlayback,
            onToggleFavorite: toggleFavorite,
            onToggleExpanded: toggleExpanded,
            onPreviousCard: showPreviousCard,
            onNextCard: showNextCard
          )

          HotStationsList(
            stations: stations.sorted { $0.favorites > $1.favorites },
            favoritedIDs: favoritedIDs,
            onPlayStation: playStation,
            onToggleFavorite: toggleFavorite
          )
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, activeStation == nil ? 36 : 118)
      }
    }
    .safeAreaInset(edge: .bottom) {
      if let activeStation {
        DiscoverFloatingPlayer(
          station: activeStation,
          speechText: playbackController.currentSpeech?.displayText,
          isPlaying: playbackController.state == .playing,
          onOpenPlayer: {
            presentedPlayerStation = activeStation
          },
          onTogglePlay: {
            playbackController.togglePlayback()
          },
          onPrevious: {
            playAdjacentStation(direction: -1)
          },
          onNext: {
            playAdjacentStation(direction: 1)
          }
        )
        .padding(.bottom, 10)
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .fullScreenCover(item: $presentedPlayerStation) { station in
      DiscoverNowPlayingView(
        station: activeStation ?? station,
        isFavorited: favoritedIDs.contains((activeStation ?? station).id),
        onClose: {
          presentedPlayerStation = nil
        },
        onToggleFavorite: {
          toggleFavorite(activeStation ?? station)
        },
        onPreviousStation: {
          playAdjacentStation(direction: -1)
        },
        onNextStation: {
          playAdjacentStation(direction: 1)
        },
        onTogglePlay: {
          playbackController.togglePlayback()
        }
      )
    }
    .animation(.spring(response: 0.35, dampingFraction: 0.82), value: activeStationID)
  }

  private var currentStation: DiscoverStation {
    stations[currentIndex]
  }

  private var activeStation: DiscoverStation? {
    guard let activeStationID else { return nil }
    return stations.first { $0.id == activeStationID }
  }

  private var isCurrentCardPlaying: Bool {
    activeStationID == currentStation.id && playbackController.state == .playing
  }

  private var header: some View {
    HStack {
      Button {} label: {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 20, weight: .semibold))
          .frame(width: 44, height: 44)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.white.opacity(0.58))
      .accessibilityLabel("搜索")

      Spacer()

      Text("发现")
        .font(.system(size: 30, weight: .bold, design: .rounded))
        .foregroundStyle(.white)

      Spacer()

      ShareLink(
        item: currentStation.shareURL,
        subject: Text(currentStation.title),
        message: Text("正在收听 \(currentStation.hostName) 的 \(currentStation.title)")
      ) {
        Image(systemName: "square.and.arrow.up")
          .font(.system(size: 20, weight: .semibold))
          .frame(width: 44, height: 44)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.white.opacity(0.72))
      .accessibilityLabel("分享当前电台")
    }
  }

  private func showPreviousCard() {
    guard !stations.isEmpty else { return }
    currentIndex = (currentIndex - 1 + stations.count) % stations.count
    expandedStationID = nil
  }

  private func showNextCard() {
    guard !stations.isEmpty else { return }
    currentIndex = (currentIndex + 1) % stations.count
    expandedStationID = nil
  }

  private func toggleCurrentStationPlayback() {
    if activeStationID == currentStation.id, playbackController.state == .playing || playbackController.state == .paused {
      playbackController.togglePlayback()
    } else {
      playStation(currentStation)
    }
  }

  private func playStation(_ station: DiscoverStation) {
    activeStationID = station.id
    if let index = stations.firstIndex(where: { $0.id == station.id }) {
      currentIndex = index
    }

    Task {
      await radioStation.loadLocalStation(station.radioStation(), playImmediately: true)
    }
  }

  private func playAdjacentStation(direction: Int) {
    let startIndex = activeStation.flatMap { station in
      stations.firstIndex(where: { $0.id == station.id })
    } ?? currentIndex
    let nextIndex = (startIndex + direction + stations.count) % stations.count
    playStation(stations[nextIndex])
  }

  private func toggleFavorite(_ station: DiscoverStation) {
    if favoritedIDs.contains(station.id) {
      favoritedIDs.remove(station.id)
    } else {
      favoritedIDs.insert(station.id)
    }
  }

  private func toggleExpanded(_ station: DiscoverStation) {
    expandedStationID = expandedStationID == station.id ? nil : station.id
  }
}

private struct DiscoverCardStack: View {
  let stations: [DiscoverStation]
  let currentIndex: Int
  let isPlaying: Bool
  let favoritedIDs: Set<String>
  let expandedStationID: String?
  let onPlayToggle: () -> Void
  let onToggleFavorite: (DiscoverStation) -> Void
  let onToggleExpanded: (DiscoverStation) -> Void
  let onPreviousCard: () -> Void
  let onNextCard: () -> Void

  @GestureState private var dragOffset: CGFloat = 0

  var body: some View {
    GeometryReader { proxy in
      let width = max(proxy.size.width - 8, 1)
      let threshold = proxy.size.width * 0.22
      let previousIndex = (currentIndex - 1 + stations.count) % stations.count
      let nextIndex = (currentIndex + 1) % stations.count
      let activeStation = stations[currentIndex]

      ZStack {
        DiscoverStationCard(
          station: stations[previousIndex],
          isActive: false,
          isPlaying: false,
          isFavorited: favoritedIDs.contains(stations[previousIndex].id),
          isExpanded: false,
          onPlayToggle: {},
          onToggleFavorite: {},
          onToggleExpanded: {}
        )
        .frame(width: width)
        .scaleEffect(0.9)
        .rotationEffect(.degrees(-3))
        .opacity(0.42)
        .offset(x: -42, y: 20)

        DiscoverStationCard(
          station: stations[nextIndex],
          isActive: false,
          isPlaying: false,
          isFavorited: favoritedIDs.contains(stations[nextIndex].id),
          isExpanded: false,
          onPlayToggle: {},
          onToggleFavorite: {},
          onToggleExpanded: {}
        )
        .frame(width: width)
        .scaleEffect(0.9)
        .rotationEffect(.degrees(3))
        .opacity(0.42)
        .offset(x: 42, y: 20)

        DiscoverStationCard(
          station: activeStation,
          isActive: true,
          isPlaying: isPlaying,
          isFavorited: favoritedIDs.contains(activeStation.id),
          isExpanded: expandedStationID == activeStation.id,
          onPlayToggle: onPlayToggle,
          onToggleFavorite: {
            onToggleFavorite(activeStation)
          },
          onToggleExpanded: {
            onToggleExpanded(activeStation)
          }
        )
        .frame(width: width)
        .offset(x: dragOffset)
        .rotationEffect(.degrees(Double(dragOffset / max(proxy.size.width, 1)) * 2.5))
        .gesture(
          DragGesture()
            .updating($dragOffset) { value, state, _ in
              state = value.translation.width
            }
            .onEnded { value in
              if value.translation.width > threshold {
                onPreviousCard()
              } else if value.translation.width < -threshold {
                onNextCard()
              }
            }
        )
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .frame(height: expandedStationID == stations[currentIndex].id ? 650 : 548)
    .animation(.spring(response: 0.34, dampingFraction: 0.86), value: currentIndex)
    .animation(.spring(response: 0.32, dampingFraction: 0.88), value: expandedStationID)
  }
}

private struct DiscoverStationCard: View {
  let station: DiscoverStation
  let isActive: Bool
  let isPlaying: Bool
  let isFavorited: Bool
  let isExpanded: Bool
  let onPlayToggle: () -> Void
  let onToggleFavorite: () -> Void
  let onToggleExpanded: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      Button(action: onPlayToggle) {
        ZStack {
          stationGradient

          Circle()
            .fill(.white.opacity(0.08))
            .frame(width: 210, height: 74)
            .scaleEffect(y: 0.42)
            .offset(y: -92)

          VStack(spacing: 10) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
              .font(.system(size: 36, weight: .black))
              .foregroundStyle(.white)
              .frame(width: 84, height: 84)
              .background(.black.opacity(0.28), in: Circle())
              .overlay {
                Circle()
                  .stroke(.white.opacity(0.18), lineWidth: 1)
              }

            Text(isPlaying ? "ON AIR" : "TAP TO TUNE")
              .font(.system(size: 12, weight: .black, design: .rounded))
              .foregroundStyle(.white.opacity(0.7))
          }
        }
        .frame(height: 350)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(!isActive)
      .accessibilityLabel(isPlaying ? "暂停 \(station.title)" : "播放 \(station.title)")

      VStack(spacing: 12) {
        HStack(spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            Text(station.title)
              .font(.system(size: 22, weight: .semibold, design: .rounded))
              .foregroundStyle(.white)
              .lineLimit(1)
              .minimumScaleFactor(0.7)

            Text(station.hostName)
              .font(.system(size: 15, weight: .medium, design: .rounded))
              .foregroundStyle(.white.opacity(0.58))
              .lineLimit(1)
          }

          Spacer()

          Button(action: onToggleFavorite) {
            Image(systemName: isFavorited ? "heart.fill" : "heart")
              .font(.system(size: 22, weight: .semibold))
              .foregroundStyle(isFavorited ? Color(hex: "#D9523A") : .white.opacity(0.34))
              .frame(width: 44, height: 44)
          }
          .buttonStyle(.plain)
          .disabled(!isActive)
          .accessibilityLabel(isFavorited ? "取消收藏" : "收藏")
        }

        Text(station.briefIntro)
          .font(.system(size: 13, weight: .medium, design: .rounded))
          .foregroundStyle(.white.opacity(0.36))
          .frame(maxWidth: .infinity, alignment: .leading)
          .lineLimit(1)

        if isActive {
          Button(action: onToggleExpanded) {
            VStack(spacing: 9) {
              Capsule()
                .fill(.white.opacity(0.34))
                .frame(width: 36, height: 4)

              Text(isExpanded ? "收起详情" : "查看详情")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(isExpanded ? "收起详情" : "查看详情")
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 18)
      .padding(.bottom, isActive ? 0 : 18)
      .background(Color(hex: "#24211E").opacity(0.82))

      if isActive, isExpanded {
        DiscoverStationDrawer(station: station)
          .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(.white.opacity(isActive ? 0.14 : 0.06), lineWidth: 1)
    }
    .shadow(color: .black.opacity(isActive ? 0.48 : 0.2), radius: isActive ? 44 : 20, y: isActive ? 24 : 12)
    .accessibilityElement(children: .contain)
  }

  private var stationGradient: some View {
    LinearGradient(
      colors: [
        station.color,
        station.color.opacity(0.78),
        station.color.opacity(0.55)
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
    .overlay {
      RadialGradient(
        colors: [
          .white.opacity(0.16),
          .clear
        ],
        center: .top,
        startRadius: 20,
        endRadius: 240
      )
    }
  }
}

private struct DiscoverStationDrawer: View {
  let station: DiscoverStation

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 8) {
        Text("关于此电台")
          .font(.system(size: 13, weight: .bold, design: .rounded))
          .foregroundStyle(.white.opacity(0.48))

        Text(station.description)
          .font(.system(size: 14, weight: .medium, design: .rounded))
          .foregroundStyle(.white.opacity(0.84))
          .lineSpacing(3)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(spacing: 9) {
        ForEach(station.items.prefix(5)) { item in
          HStack(spacing: 10) {
            Image(systemName: "music.note.list")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(.white.opacity(0.38))
              .frame(width: 18)

            Text(item.track.title)
              .font(.system(size: 14, weight: .semibold, design: .rounded))
              .foregroundStyle(.white.opacity(0.88))
              .lineLimit(1)

            Spacer()
          }
        }
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 16)
    .padding(.bottom, 22)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(hex: "#1E1B18"))
  }
}

private struct HotStationsList: View {
  let stations: [DiscoverStation]
  let favoritedIDs: Set<String>
  let onPlayStation: (DiscoverStation) -> Void
  let onToggleFavorite: (DiscoverStation) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("热门电台")
        .font(.system(size: 18, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .padding(.bottom, 8)

      ForEach(stations) { station in
        Button {
          onPlayStation(station)
        } label: {
          HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(
                LinearGradient(
                  colors: [station.color, station.color.opacity(0.72)],
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                )
              )
              .frame(width: 52, height: 52)
              .overlay {
                Text(String(station.title.prefix(1)))
                  .font(.system(size: 22, weight: .black, design: .rounded))
                  .foregroundStyle(.white.opacity(0.68))
              }

            VStack(alignment: .leading, spacing: 3) {
              Text(station.title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

              HStack(spacing: 4) {
                Text(station.hostName)
                Text("·")
                Text(station.genre)
              }
              .font(.system(size: 13, weight: .medium, design: .rounded))
              .foregroundStyle(.white.opacity(0.45))
              .lineLimit(1)
            }

            Spacer()

            Text(station.formattedFavorites)
              .font(.system(size: 12, weight: .semibold, design: .rounded))
              .foregroundStyle(.white.opacity(0.32))

            Image(systemName: favoritedIDs.contains(station.id) ? "heart.fill" : "chevron.right")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(favoritedIDs.contains(station.id) ? Color(hex: "#D9523A") : .white.opacity(0.28))
          }
          .padding(.vertical, 12)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if station.id != stations.last?.id {
          Divider()
            .background(.white.opacity(0.08))
            .padding(.leading, 65)
        }
      }

      Text("滑到底了，要听听自己的电台吗？")
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(.white.opacity(0.3))
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }
  }
}

private struct DiscoverFloatingPlayer: View {
  let station: DiscoverStation
  let speechText: String?
  let isPlaying: Bool
  let onOpenPlayer: () -> Void
  let onTogglePlay: () -> Void
  let onPrevious: () -> Void
  let onNext: () -> Void

  var body: some View {
    Button(action: onOpenPlayer) {
      HStack(spacing: 12) {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(
            LinearGradient(
              colors: [station.color, station.color.opacity(0.72)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .frame(width: 42, height: 42)

        VStack(alignment: .leading, spacing: 2) {
          Text(station.title)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)

          Text(speechText ?? station.hostName)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.5))
            .lineLimit(1)
        }

        Spacer()

        HStack(spacing: 18) {
          playerButton(systemImage: "backward.fill", action: onPrevious, size: 18)
          playerButton(systemImage: isPlaying ? "pause.fill" : "play.fill", action: onTogglePlay, size: 18, filled: true)
          playerButton(systemImage: "forward.fill", action: onNext, size: 18)
        }
      }
      .padding(.horizontal, 16)
      .frame(height: 62)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .stroke(.white.opacity(0.08), lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.35), radius: 28, y: 14)
      .padding(.horizontal, 22)
    }
    .buttonStyle(.plain)
  }

  private func playerButton(systemImage: String, action: @escaping () -> Void, size: CGFloat, filled: Bool = false) -> some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: size, weight: .bold))
        .foregroundStyle(.white.opacity(filled ? 1 : 0.62))
        .frame(width: filled ? 38 : 24, height: filled ? 38 : 24)
        .background(filled ? Color(hex: "#D9523A") : .clear, in: Circle())
    }
    .buttonStyle(.plain)
  }
}

private struct DiscoverNowPlayingView: View {
  @Environment(PlaybackController.self) private var playbackController

  let station: DiscoverStation
  let isFavorited: Bool
  let onClose: () -> Void
  let onToggleFavorite: () -> Void
  let onPreviousStation: () -> Void
  let onNextStation: () -> Void
  let onTogglePlay: () -> Void

  private var isPlaying: Bool {
    playbackController.state == .playing
  }

  private var durationText: String {
    let totalSeconds = Int(station.items.map(\.track.duration).reduce(0, +))
    return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
  }

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          station.color.opacity(0.22),
          Color(hex: "#15120F")
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()

      VStack(spacing: 0) {
        HStack {
          Button(action: onClose) {
            Image(systemName: "chevron.down")
              .font(.system(size: 18, weight: .bold))
              .foregroundStyle(.white)
              .frame(width: 38, height: 38)
              .background(.white.opacity(0.07), in: Circle())
          }
          .buttonStyle(.plain)

          Spacer()

          Button {} label: {
            Image(systemName: "ellipsis")
              .font(.system(size: 18, weight: .bold))
              .foregroundStyle(.white.opacity(0.58))
              .frame(width: 38, height: 38)
              .background(.white.opacity(0.07), in: Circle())
          }
          .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)

        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(
            LinearGradient(
              colors: [station.color, station.color.opacity(0.78), station.color.opacity(0.5)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .frame(maxWidth: .infinity)
          .aspectRatio(1.04, contentMode: .fit)
          .overlay {
            Circle()
              .fill(.white.opacity(0.08))
              .frame(width: 220, height: 88)
              .scaleEffect(y: 0.45)
              .offset(y: -90)
          }
          .shadow(color: station.color.opacity(0.22), radius: 36, y: 22)
          .padding(.horizontal, 26)
          .padding(.top, 22)

        VStack(spacing: 8) {
          Text(station.title)
            .font(.system(size: 27, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

          HStack(spacing: 12) {
            Text(playbackController.currentSpeech?.displayText ?? "by \(station.hostName)")
              .font(.system(size: 15, weight: .medium, design: .rounded))
              .foregroundStyle(.white.opacity(0.5))
              .lineLimit(2)
              .multilineTextAlignment(.center)

            Button(action: onToggleFavorite) {
              Image(systemName: isFavorited ? "heart.fill" : "heart")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isFavorited ? Color(hex: "#D9523A") : .white.opacity(0.34))
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.top, 24)

        DiscoverWaveformView(
          seed: station.id,
          progress: playbackController.playbackProgress,
          elapsedText: playbackController.elapsedTimeText,
          durationText: durationText,
          color: station.color
        )
        .padding(.top, 28)

        HStack(spacing: 56) {
          Button(action: onPreviousStation) {
            Image(systemName: "backward.fill")
              .font(.system(size: 34, weight: .bold))
              .foregroundStyle(.white)
          }
          .buttonStyle(.plain)

          Button(action: onTogglePlay) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
              .font(.system(size: 52, weight: .bold))
              .foregroundStyle(.white)
              .frame(width: 76, height: 76)
          }
          .buttonStyle(.plain)

          Button(action: onNextStation) {
            Image(systemName: "forward.fill")
              .font(.system(size: 34, weight: .bold))
              .foregroundStyle(.white)
          }
          .buttonStyle(.plain)
        }
        .padding(.top, 34)

        Spacer()
      }
    }
  }
}

private struct DiscoverWaveformView: View {
  let seed: String
  let progress: Double
  let elapsedText: String
  let durationText: String
  let color: Color

  private var bars: [Double] {
    var state = abs(seed.unicodeScalars.reduce(17) { ($0 * 31) + Int($1.value) })
    return (0..<44).map { _ in
      state = (state * 16_807) % 2_147_483_647
      return 0.18 + (Double(state % 100) / 100) * 0.82
    }
  }

  var body: some View {
    VStack(spacing: 8) {
      HStack(alignment: .center, spacing: 2) {
        ForEach(Array(bars.enumerated()), id: \.offset) { index, value in
          Capsule()
            .fill(Double(index) / Double(max(bars.count - 1, 1)) <= progress ? color : .white.opacity(0.14))
            .frame(width: 4, height: 10 + 52 * value)
        }
      }
      .frame(height: 66)

      HStack {
        Text(elapsedText)
        Spacer()
        Text(durationText)
      }
      .font(.system(size: 11, weight: .medium, design: .rounded))
      .foregroundStyle(.white.opacity(0.4))
    }
    .padding(.horizontal, 26)
  }
}

#Preview {
  let playbackController = PlaybackController()
  DiscoverView()
    .environment(playbackController)
    .environment(RadioStationController(playbackController: playbackController))
    .environment(MusicAuthorizationService())
}
