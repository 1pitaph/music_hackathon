import SwiftUI

struct MineView: View {
  @State private var profile = ArchiveProfile.mock
  @State private var recentlyPlayedExpanded = true
  @State private var savedExpanded = true

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(spacing: 26) {
        identityHeader
        recentArchiveSection
        stationPanel(title: "Recently Played", items: profile.recentlyPlayed, isExpanded: $recentlyPlayedExpanded)
        stationPanel(title: "Saved", items: profile.saved, isExpanded: $savedExpanded)
      }
      .padding(.horizontal, 20)
      .padding(.top, 18)
      .padding(.bottom, 40)
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        NavigationLink(value: MineRoute.settings) {
          Image(systemName: "gearshape")
            .foregroundStyle(.white.opacity(0.7))
        }
        .accessibilityLabel("设置")
      }
    }
    .navigationDestination(for: MineRoute.self) { route in
      switch route {
      case .settings:
        SettingsView()
          .navigationTitle("设置")
      case .archive:
        ArchiveGridPage(profile: profile)
          .navigationTitle("Archive")
      case let .station(station):
        ArchiveStationDetailPage(station: station)
          .navigationTitle(station.name)
      case .profile:
        ProfileEditorPage(profile: $profile)
          .navigationTitle("个人电台")
      }
    }
  }

  private var identityHeader: some View {
    VStack(spacing: 16) {
      NavigationLink(value: MineRoute.profile) {
        ZStack {
          Circle()
            .fill(Color(hex: profile.avatarColorHex))
            .frame(width: 82, height: 82)
            .overlay {
              Circle()
                .stroke(.white.opacity(0.16), lineWidth: 2)
            }

          Text(String(profile.nickname.prefix(1)))
            .font(.system(size: 30, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.72))
        }
      }
      .buttonStyle(.plain)
      .accessibilityLabel("编辑个人资料")

      VStack(spacing: 8) {
        Text(profile.nickname)
          .font(.system(size: 28, weight: .bold, design: .rounded))
          .foregroundStyle(.white)
          .lineLimit(1)

        Text(profile.bio)
          .font(.system(size: 13, weight: .medium, design: .rounded))
          .foregroundStyle(.white.opacity(0.42))
          .multilineTextAlignment(.center)
      }

      HStack(spacing: 0) {
        statItem(value: "\(profile.stats.listeningHours)", label: "Hours")
        statItem(value: "\(profile.stats.stationsCount)", label: "Stations")
        statItem(value: profile.stats.likesCount.formatted(), label: "Likes")
      }
      .padding(.top, 4)
    }
    .frame(maxWidth: .infinity)
  }

  private var recentArchiveSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Label("Radio Archive", systemImage: "dot.radiowaves.left.and.right")
          .font(.system(size: 15, weight: .bold, design: .rounded))
          .foregroundStyle(.white)

        Spacer()

        NavigationLink(value: MineRoute.archive) {
          Text("See All")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.42))
        }
      }

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 14) {
          ForEach(profile.recentPublished) { station in
            NavigationLink(value: MineRoute.station(station)) {
              VStack(alignment: .leading, spacing: 8) {
                ArchiveStationCover(station: station, size: 104)

                Text(station.name)
                  .font(.system(size: 13, weight: .semibold, design: .rounded))
                  .foregroundStyle(.white)
                  .lineLimit(1)

                Text(station.relativeCreatedAt)
                  .font(.system(size: 11, weight: .medium, design: .rounded))
                  .foregroundStyle(.white.opacity(0.34))
                  .lineLimit(1)
              }
              .frame(width: 104, alignment: .leading)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.trailing, 20)
      }
    }
  }

  private func stationPanel(title: String, items: [ArchiveStationItem], isExpanded: Binding<Bool>) -> some View {
    VStack(spacing: 0) {
      Button {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
          isExpanded.wrappedValue.toggle()
        }
      } label: {
        HStack {
          Text(title)
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)

          Spacer()

          Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.forward")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white.opacity(0.38))
        }
        .contentShape(Rectangle())
        .padding(.vertical, 14)
      }
      .buttonStyle(.plain)

      if isExpanded.wrappedValue {
        VStack(spacing: 0) {
          if items.isEmpty {
            Text("Nothing here yet.")
              .font(.system(size: 14, weight: .medium, design: .rounded))
              .foregroundStyle(.white.opacity(0.36))
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.vertical, 12)
          } else {
            ForEach(items) { station in
              NavigationLink(value: MineRoute.station(station)) {
                HStack(spacing: 12) {
                  ArchiveStationCover(station: station, size: 56)

                  Text(station.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                  Spacer()
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)

              if station.id != items.last?.id {
                Divider()
                  .background(.white.opacity(0.08))
                  .padding(.leading, 68)
              }
            }
          }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
  }

  private func statItem(value: String, label: String) -> some View {
    VStack(spacing: 5) {
      Text(value)
        .font(.system(size: 16, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)

      Text(label)
        .font(.system(size: 10, weight: .bold, design: .rounded))
        .foregroundStyle(.white.opacity(0.34))
    }
    .frame(maxWidth: .infinity)
  }
}

private enum MineRoute: Hashable {
  case settings
  case archive
  case station(ArchiveStationItem)
  case profile
}

private struct ArchiveGridPage: View {
  let profile: ArchiveProfile
  @State private var selectedTab: ArchiveGridTab = .history

  private let columns = [
    GridItem(.flexible(), spacing: 14),
    GridItem(.flexible(), spacing: 14)
  ]
  private let artistColumns = [
    GridItem(.flexible(), spacing: 16),
    GridItem(.flexible(), spacing: 16),
    GridItem(.flexible(), spacing: 16)
  ]

  var body: some View {
    VStack(spacing: 0) {
      archiveTabs

      ScrollView(.vertical, showsIndicators: false) {
        switch selectedTab {
        case .history:
          stationGrid(stations: sortedPublished, showsGenres: true)
        case .curated:
          if profile.curatedStations.isEmpty {
            emptyText("No curated stations yet")
          } else {
            stationGrid(stations: profile.curatedStations, showsGenres: false)
          }
        case .artists:
          artistGrid
        }
      }
    }
  }

  private var sortedPublished: [ArchiveStationItem] {
    profile.published.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
  }

  private var archiveTabs: some View {
    HStack(spacing: 28) {
      ForEach(ArchiveGridTab.allCases) { tab in
        Button {
          withAnimation(.easeInOut(duration: 0.2)) {
            selectedTab = tab
          }
        } label: {
          VStack(spacing: 9) {
            Text(tab.title)
              .font(.system(size: 14, weight: .semibold, design: .rounded))
              .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.42))

            Capsule()
              .fill(selectedTab == tab ? .white : .clear)
              .frame(width: 16, height: 2)
          }
        }
        .buttonStyle(.plain)
      }

      Spacer()
    }
    .padding(.horizontal, 20)
    .padding(.bottom, 4)
    .overlay(alignment: .bottom) {
      Divider()
        .background(.white.opacity(0.08))
    }
  }

  private var artistGrid: some View {
    LazyVGrid(columns: artistColumns, spacing: 18) {
      ForEach(profile.artists, id: \.self) { artist in
        VStack(spacing: 9) {
          Circle()
            .fill(Color(hex: ArchiveStationItem.colorHex(for: artist)))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
              Text(String(artist.prefix(1)))
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
            }

          Text(artist)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.62))
            .lineLimit(1)
        }
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 24)
    .padding(.bottom, 40)
  }

  private func stationGrid(stations: [ArchiveStationItem], showsGenres: Bool) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      if showsGenres {
        genreTags
      }

      LazyVGrid(columns: columns, spacing: 16) {
        ForEach(stations) { station in
          NavigationLink(value: MineRoute.station(station)) {
            VStack(alignment: .leading, spacing: 9) {
              ArchiveStationCover(station: station, size: nil)
                .aspectRatio(1, contentMode: .fit)

              Text(station.name)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

              Text(station.relativeCreatedAt)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.34))
                .lineLimit(1)
            }
          }
          .buttonStyle(.plain)
        }
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 20)
    .padding(.bottom, 40)
  }

  private var genreTags: some View {
    let genres = Array(Set(profile.published.map(\.genre))).sorted()
    return HStack(spacing: 8) {
      ForEach(genres, id: \.self) { genre in
        Text(genre)
          .font(.system(size: 14, weight: .semibold, design: .rounded))
          .foregroundStyle(.white.opacity(0.56))
          .padding(.horizontal, 18)
          .padding(.vertical, 8)
          .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      }
    }
  }

  private func emptyText(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 15, weight: .medium, design: .rounded))
      .foregroundStyle(.white.opacity(0.42))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(.top, 80)
  }
}

private enum ArchiveGridTab: CaseIterable, Identifiable {
  case history
  case curated
  case artists

  var id: Self { self }

  var title: String {
    switch self {
    case .history:
      "History"
    case .curated:
      "Curated"
    case .artists:
      "Artists"
    }
  }
}

private struct ArchiveStationDetailPage: View {
  let station: ArchiveStationItem

  var body: some View {
    VStack(spacing: 24) {
      ArchiveStationCover(station: station, size: 122)

      VStack(spacing: 10) {
        Text(station.name)
          .font(.system(size: 23, weight: .bold, design: .rounded))
          .foregroundStyle(.white)
          .multilineTextAlignment(.center)

        Text("播放功能开发中")
          .font(.system(size: 14, weight: .medium, design: .rounded))
          .foregroundStyle(.white.opacity(0.42))
      }

      Button {} label: {
        Label("播放", systemImage: "play.fill")
          .font(.system(size: 16, weight: .semibold, design: .rounded))
          .foregroundStyle(.white.opacity(0.34))
          .padding(.horizontal, 38)
          .padding(.vertical, 14)
          .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      .buttonStyle(.plain)
      .disabled(true)

      Spacer()
    }
    .padding(.top, 42)
    .padding(.horizontal, 20)
  }
}

private struct ProfileEditorPage: View {
  @Binding var profile: ArchiveProfile
  @Environment(\.dismiss) private var dismiss

  @State private var nickname: String
  @State private var bio: String
  @State private var selectedColorHex: String

  private let colors = ["#2A2A2A", "#FF6B6B", "#4ECDC4", "#45B7D1", "#DDA0DD"]

  init(profile: Binding<ArchiveProfile>) {
    _profile = profile
    _nickname = State(initialValue: profile.wrappedValue.nickname)
    _bio = State(initialValue: profile.wrappedValue.bio)
    _selectedColorHex = State(initialValue: profile.wrappedValue.avatarColorHex)
  }

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(alignment: .leading, spacing: 30) {
        field(title: "昵称") {
          TextField("输入昵称", text: $nickname)
            .textInputAutocapitalization(.never)
            .foregroundStyle(.white)
        }

        field(title: "电台简介") {
          TextField("输入电台简介", text: $bio)
            .foregroundStyle(.white)
        }

        VStack(alignment: .leading, spacing: 12) {
          Text("头像颜色")
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.62))

          HStack(spacing: 16) {
            ForEach(colors, id: \.self) { colorHex in
              Button {
                selectedColorHex = colorHex
              } label: {
                Circle()
                  .fill(Color(hex: colorHex))
                  .frame(width: 48, height: 48)
                  .overlay {
                    if selectedColorHex == colorHex {
                      Circle()
                        .stroke(.white, lineWidth: 3)
                    }
                  }
              }
              .buttonStyle(.plain)
              .accessibilityLabel("选择颜色 \(colorHex)")
            }
          }
        }

        Button(action: save) {
          Text("保存")
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(hex: "#121212"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
      }
      .padding(.horizontal, 20)
      .padding(.top, 24)
      .padding(.bottom, 40)
    }
  }

  private func field<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(.system(size: 14, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.62))

      content()
        .font(.system(size: 16, weight: .medium, design: .rounded))
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
          Rectangle()
            .fill(.white.opacity(0.18))
            .frame(height: 1)
        }
    }
  }

  private func save() {
    profile.nickname = String(nickname.prefix(20))
    profile.bio = String(bio.prefix(60))
    profile.avatarColorHex = selectedColorHex
    dismiss()
  }
}

private struct ArchiveStationCover: View {
  let station: ArchiveStationItem
  let size: CGFloat?

  init(station: ArchiveStationItem, size: CGFloat? = 56) {
    self.station = station
    self.size = size
  }

  var body: some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      .fill(Color(hex: station.colorHex))
      .frame(width: size, height: size)
      .overlay {
        Text(String(station.name.prefix(1)))
          .font(.system(size: fontSize, weight: .black, design: .rounded))
          .foregroundStyle(.white.opacity(0.68))
      }
  }

  private var cornerRadius: CGFloat {
    guard let size else { return 8 }
    if size >= 120 {
      return 12
    }
    if size >= 100 {
      return 8
    }
    return 6
  }

  private var fontSize: CGFloat {
    guard let size else { return 54 }
    return max(size * 0.38, 18)
  }
}

#Preview {
  let playbackController = PlaybackController()
  NavigationStack {
    MineView()
      .navigationTitle("我的")
  }
  .environment(playbackController)
  .environment(RadioStationController(playbackController: playbackController))
  .environment(MusicAuthorizationService())
}
