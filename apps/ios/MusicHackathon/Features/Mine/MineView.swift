import PhotosUI
import SwiftUI

struct MineView: View {
  @Environment(MusicAuthorizationService.self) private var musicAuthorization
  @Environment(AppleMusicLibraryStore.self) private var appleMusicLibrary
  @Environment(ImageAssetStore.self) private var imageAssetStore

  @AppStorage("mine.profile.avatarSeed") private var profileAvatarSeed = ""
  @AppStorage("mine.profile.nickname") private var profileNickname = ""
  @AppStorage("mine.profile.bio") private var profileBio = ""

  @State private var profile = ArchiveProfile.empty
  @State private var recentlyPlayedExpanded = true
  @State private var savedExpanded = true
  @State private var transientAvatarSeed = MineAvatarSeed.make()

  var body: some View {
    let currentProfile = displayProfile

    ScrollView(.vertical, showsIndicators: false) {
      VStack(spacing: 26) {
        identityHeader(profile: currentProfile)
        libraryStatusSection

        if hasLibraryContent {
          recentArchiveSection(profile: currentProfile)
          stationPanel(
            title: "Songs",
            items: Array(currentProfile.recentlyPlayed.prefix(24)),
            isExpanded: $recentlyPlayedExpanded,
            seeAllDestination: .archive(initialTab: .curated)
          )
          stationPanel(title: "Artists", items: currentProfile.saved, isExpanded: $savedExpanded)
        }
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
      case let .archive(initialTab):
        ArchiveGridPage(profile: currentProfile, initialTab: initialTab)
          .navigationTitle("Apple Music")
      case let .station(station):
        ArchiveStationDetailPage(station: station)
          .navigationTitle(station.name)
      case .profile:
        ProfileEditorPage(
          initialNickname: currentProfile.nickname,
          nickname: $profileNickname,
          bio: $profileBio,
          avatarSeed: avatarSeedBinding
        )
          .navigationTitle("个人电台")
      }
    }
    .task {
      ensurePersistentAvatarSeed()
      await refreshLibraryIfNeeded()
    }
  }

  private var displayProfile: ArchiveProfile {
    guard hasLibraryContent else { return baseProfile }

    return ArchiveProfile.appleMusic(
      base: baseProfile,
      playlists: appleMusicLibrary.playlists,
      tracks: appleMusicLibrary.tracks
    )
  }

  private var baseProfile: ArchiveProfile {
    var baseProfile = profile
    baseProfile.nickname = profileNickname.trimmingCharacters(in: .whitespacesAndNewlines)
    baseProfile.bio = profileBio.trimmingCharacters(in: .whitespacesAndNewlines)
    return baseProfile
  }

  private var hasLibraryContent: Bool {
    !appleMusicLibrary.playlists.isEmpty || !appleMusicLibrary.tracks.isEmpty
  }

  private var avatarSeed: String {
    profileAvatarSeed.isEmpty ? transientAvatarSeed : profileAvatarSeed
  }

  private var avatarSeedBinding: Binding<String> {
    Binding {
      avatarSeed
    } set: { newValue in
      profileAvatarSeed = newValue
    }
  }

  private func identityHeader(profile: ArchiveProfile) -> some View {
    let nickname = profile.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    let bio = profile.bio.trimmingCharacters(in: .whitespacesAndNewlines)
    let avatarAccessibilityLabel = nickname.isEmpty ? "个人资料头像" : "\(nickname) 的头像"

    return VStack(spacing: 16) {
      NavigationLink(value: MineRoute.profile) {
        ProfileAvatarImageView(size: 82) {
          MarbleAvatarView(seed: avatarSeed, size: 82, accessibilityLabel: avatarAccessibilityLabel)
        }
      }
      .buttonStyle(.plain)
      .accessibilityLabel("编辑个人资料")

      if !nickname.isEmpty || !bio.isEmpty {
        VStack(spacing: 8) {
          if !nickname.isEmpty {
            Text(nickname)
              .font(.system(size: 28, weight: .bold, design: .rounded))
              .foregroundStyle(.white)
              .lineLimit(1)
          }

          if !bio.isEmpty {
            Text(bio)
              .font(.system(size: 13, weight: .medium, design: .rounded))
              .foregroundStyle(.white.opacity(0.42))
              .multilineTextAlignment(.center)
          }
        }
      }

      HStack(spacing: 0) {
        statItem(value: "\(profile.stats.listeningHours)", label: "Hours")
        statItem(value: "\(profile.stats.stationsCount)", label: "Playlists")
        statItem(value: profile.stats.likesCount.formatted(), label: "Songs")
      }
      .padding(.top, 4)
    }
    .frame(maxWidth: .infinity)
  }

  private func ensurePersistentAvatarSeed() {
    guard profileAvatarSeed.isEmpty else { return }
    profileAvatarSeed = transientAvatarSeed
  }

  @ViewBuilder
  private var libraryStatusSection: some View {
    switch appleMusicLibrary.state {
    case .idle, .loading:
      if !hasLibraryContent {
        MineLibraryStatusPanel(
          iconSystemName: "music.note.list",
          title: "正在读取 Apple Music",
          message: "资料库加载完成后，这里会显示你的真实歌单、歌曲和封面。",
          isLoading: true,
          actionTitle: nil,
          action: nil
        )
      }
    case .needsAuthorization:
      MineLibraryStatusPanel(
        iconSystemName: "person.badge.key",
        title: "连接 Apple Music",
        message: "授权后会读取你的资料库歌单和歌曲，不再显示占位内容。",
        isLoading: musicAuthorization.isRequestingAccess,
        actionTitle: musicAuthorization.isRequestingAccess ? "连接中" : "连接 Apple Music"
      ) {
        Task {
          await connectAppleMusic()
        }
      }
    case .empty:
      MineLibraryStatusPanel(
        iconSystemName: "music.note",
        title: "没有找到资料库歌曲",
        message: "确认 Apple Music 资料库中已有歌曲或歌单后，可以重新刷新。",
        isLoading: false,
        actionTitle: "刷新"
      ) {
        Task {
          await refreshLibrary()
        }
      }
    case let .failed(message):
      MineLibraryStatusPanel(
        iconSystemName: "exclamationmark.triangle",
        title: "无法读取 Apple Music",
        message: message,
        isLoading: false,
        actionTitle: "重试"
      ) {
        Task {
          await refreshLibrary()
        }
      }
    case .loaded:
      EmptyView()
    }
  }

  private func recentArchiveSection(profile: ArchiveProfile) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Label("Playlists", systemImage: "music.note.list")
          .font(.system(size: 15, weight: .bold, design: .rounded))
          .foregroundStyle(.white)

        Spacer()

        NavigationLink(value: MineRoute.archive(initialTab: .history)) {
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

                Text(station.displaySubtitle)
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

  private func refreshLibraryIfNeeded() async {
    await musicAuthorization.refreshAccessState()
    await appleMusicLibrary.loadIfNeeded(authorizationStatus: musicAuthorization.status)
  }

  private func refreshLibrary() async {
    await musicAuthorization.refreshAccessState()
    await appleMusicLibrary.refresh(authorizationStatus: musicAuthorization.status)
  }

  private func connectAppleMusic() async {
    await musicAuthorization.requestAccess()
    await appleMusicLibrary.refresh(authorizationStatus: musicAuthorization.status)
  }

  private func stationPanel(
    title: String,
    items: [ArchiveStationItem],
    isExpanded: Binding<Bool>,
    seeAllDestination: MineRoute? = nil
  ) -> some View {
    VStack(spacing: 0) {
      HStack(spacing: 14) {
        Button {
          withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            isExpanded.wrappedValue.toggle()
          }
        } label: {
          HStack(spacing: 8) {
            Text(title)
              .font(.system(size: 16, weight: .semibold, design: .rounded))
              .foregroundStyle(.white)

            Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.forward")
              .font(.system(size: 14, weight: .bold))
              .foregroundStyle(.white.opacity(0.38))
          }
          .contentShape(Rectangle())
          .padding(.vertical, 14)
        }
        .buttonStyle(.plain)

        Spacer()

        if let seeAllDestination {
          NavigationLink(value: seeAllDestination) {
            Text("See All")
              .font(.system(size: 13, weight: .semibold, design: .rounded))
              .foregroundStyle(.white.opacity(0.42))
          }
          .buttonStyle(.plain)
        }
      }

      if isExpanded.wrappedValue {
        LazyVStack(spacing: 0) {
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

                  VStack(alignment: .leading, spacing: 4) {
                    Text(station.name)
                      .font(.system(size: 15, weight: .semibold, design: .rounded))
                      .foregroundStyle(.white)
                      .lineLimit(1)

                    Text(station.displaySubtitle)
                      .font(.system(size: 12, weight: .medium, design: .rounded))
                      .foregroundStyle(.white.opacity(0.38))
                      .lineLimit(1)
                  }

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

private struct MineLibraryStatusPanel: View {
  let iconSystemName: String
  let title: String
  let message: String
  let isLoading: Bool
  let actionTitle: String?
  let action: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.white.opacity(0.08))
            .frame(width: 42, height: 42)

          if isLoading {
            ProgressView()
          } else {
            Image(systemName: iconSystemName)
              .font(.system(size: 18, weight: .semibold))
              .foregroundStyle(.white.opacity(0.72))
          }
        }

        VStack(alignment: .leading, spacing: 6) {
          Text(title)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(.white)

          Text(message)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.48))
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 0)
      }

      if let actionTitle, let action {
        Button(action: action) {
          Text(actionTitle)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(hex: "#121212"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
      }
    }
    .padding(16)
    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private enum MineRoute: Hashable {
  case settings
  case archive(initialTab: ArchiveGridTab)
  case station(ArchiveStationItem)
  case profile
}

private struct ArchiveGridPage: View {
  let profile: ArchiveProfile
  @State private var selectedTab: ArchiveGridTab

  private let columns = [
    GridItem(.flexible(), spacing: 14),
    GridItem(.flexible(), spacing: 14)
  ]
  private let artistColumns = [
    GridItem(.flexible(), spacing: 16),
    GridItem(.flexible(), spacing: 16),
    GridItem(.flexible(), spacing: 16)
  ]

  init(profile: ArchiveProfile, initialTab: ArchiveGridTab) {
    self.profile = profile
    _selectedTab = State(initialValue: initialTab)
  }

  var body: some View {
    VStack(spacing: 0) {
      archiveTabs

      ScrollView(.vertical, showsIndicators: false) {
        switch selectedTab {
        case .history:
          if sortedPublished.isEmpty {
            emptyText("No Apple Music playlists found")
          } else {
            stationGrid(stations: sortedPublished, showsGenres: false)
          }
        case .curated:
          if profile.recentlyPlayed.isEmpty {
            emptyText("No songs found")
          } else {
            songList(stations: profile.recentlyPlayed)
          }
        case .artists:
          if profile.saved.isEmpty {
            emptyText("No artists found")
          } else {
            artistGrid
          }
        }
      }
    }
  }

  private var sortedPublished: [ArchiveStationItem] {
    profile.published
      .enumerated()
      .sorted { lhs, rhs in
        switch (lhs.element.createdAt, rhs.element.createdAt) {
        case let (lhsDate?, rhsDate?):
          return lhsDate > rhsDate
        case (.some, nil):
          return true
        case (nil, .some):
          return false
        case (nil, nil):
          return lhs.offset < rhs.offset
        }
      }
      .map(\.element)
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
      ForEach(profile.saved) { artist in
        NavigationLink(value: MineRoute.station(artist)) {
          VStack(spacing: 9) {
            ArchiveStationCover(station: artist, size: nil)
            .aspectRatio(1, contentMode: .fit)

            Text(artist.name)
              .font(.system(size: 13, weight: .semibold, design: .rounded))
              .foregroundStyle(.white.opacity(0.62))
              .lineLimit(1)
          }
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 24)
    .padding(.bottom, 40)
  }

  private func songList(stations: [ArchiveStationItem]) -> some View {
    LazyVStack(spacing: 0) {
      ForEach(stations) { station in
        NavigationLink(value: MineRoute.station(station)) {
          HStack(spacing: 12) {
            ArchiveStationCover(station: station, size: 56)

            VStack(alignment: .leading, spacing: 4) {
              Text(station.name)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

              Text(station.displaySubtitle)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.38))
                .lineLimit(1)
            }

            Spacer()
          }
          .padding(.vertical, 10)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if station.id != stations.last?.id {
          Divider()
            .background(.white.opacity(0.08))
            .padding(.leading, 68)
        }
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 10)
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

              Text(station.displaySubtitle)
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

private enum ArchiveGridTab: CaseIterable, Identifiable, Hashable {
  case history
  case curated
  case artists

  var id: Self { self }

  var title: String {
    switch self {
    case .history:
      "Playlists"
    case .curated:
      "Songs"
    case .artists:
      "Artists"
    }
  }
}

private struct ArchiveStationDetailPage: View {
  let station: ArchiveStationItem

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(spacing: 24) {
        ArchiveStationCover(station: station, size: 122)

        VStack(spacing: 10) {
          Text(station.name)
            .font(.system(size: 23, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)

          Text(station.displaySubtitle)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.42))
            .multilineTextAlignment(.center)
        }

        if !station.tracks.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            Text("Songs")
              .font(.system(size: 16, weight: .semibold, design: .rounded))
              .foregroundStyle(.white)

            LazyVStack(spacing: 0) {
              ForEach(station.tracks) { track in
                HStack(spacing: 12) {
                  MineTrackArtwork(track: track, size: 44)

                  VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                      .font(.system(size: 14, weight: .semibold, design: .rounded))
                      .foregroundStyle(.white)
                      .lineLimit(1)

                    Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " • "))
                      .font(.system(size: 12, weight: .medium, design: .rounded))
                      .foregroundStyle(.white.opacity(0.4))
                      .lineLimit(1)
                  }

                  Spacer()
                }
                .padding(.vertical, 9)

                if track.id != station.tracks.last?.id {
                  Divider()
                    .background(.white.opacity(0.08))
                    .padding(.leading, 56)
                }
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }

        Spacer(minLength: 0)
      }
      .padding(.top, 42)
      .padding(.horizontal, 20)
      .padding(.bottom, 40)
    }
  }
}

private struct ProfileEditorPage: View {
  @Binding var nickname: String
  @Binding var bio: String
  @Binding var avatarSeed: String
  @Environment(\.dismiss) private var dismiss
  @Environment(ImageAssetStore.self) private var imageAssetStore

  @State private var draftNickname: String
  @State private var draftBio: String
  @State private var draftAvatarSeed: String
  @State private var selectedAvatarItem: PhotosPickerItem?
  @State private var avatarErrorMessage: String?
  @State private var isSavingAvatar = false

  init(
    initialNickname: String,
    nickname: Binding<String>,
    bio: Binding<String>,
    avatarSeed: Binding<String>
  ) {
    _nickname = nickname
    _bio = bio
    _avatarSeed = avatarSeed
    _draftNickname = State(initialValue: nickname.wrappedValue.isEmpty ? initialNickname : nickname.wrappedValue)
    _draftBio = State(initialValue: bio.wrappedValue)
    _draftAvatarSeed = State(initialValue: avatarSeed.wrappedValue)
  }

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(alignment: .leading, spacing: 30) {
        field(title: "昵称") {
          TextField("输入昵称", text: $draftNickname)
            .textInputAutocapitalization(.never)
            .foregroundStyle(.white)
        }

        field(title: "电台简介") {
          TextField("输入电台简介", text: $draftBio)
            .foregroundStyle(.white)
        }

        VStack(alignment: .leading, spacing: 12) {
          Text("头像")
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.62))

          VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
              ProfileAvatarImageView(size: 96) {
                MarbleAvatarView(seed: draftAvatarSeed, size: 96, accessibilityLabel: "当前头像")
              }

              VStack(alignment: .leading, spacing: 10) {
                PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                  Label("选择照片", systemImage: "photo")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(hex: "#121212"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isSavingAvatar)
                .accessibilityLabel("选择头像照片")

                Button {
                  withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    imageAssetStore.clearProfileAvatar()
                    draftAvatarSeed = MineAvatarSeed.make()
                  }
                } label: {
                  Label("随机头像", systemImage: "shuffle")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.76))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("重新生成随机头像")

                if imageAssetStore.profileAvatarSource != nil {
                  Button {
                    imageAssetStore.clearProfileAvatar()
                  } label: {
                    Label("移除照片", systemImage: "trash")
                      .font(.system(size: 14, weight: .semibold, design: .rounded))
                      .foregroundStyle(Color(hex: "#FFD5C8"))
                  }
                  .buttonStyle(.plain)
                  .accessibilityLabel("移除头像照片")
                }
              }

              Spacer(minLength: 0)
            }

            if isSavingAvatar {
              ProgressView("正在保存头像")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.62))
            }

            if let avatarErrorMessage {
              Text(avatarErrorMessage)
                .font(.footnote)
                .foregroundStyle(Color(hex: "#FFD5C8"))
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
    .onChange(of: selectedAvatarItem) { _, item in
      guard let item else { return }
      Task {
        await saveAvatar(item)
      }
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
    let trimmedNickname = draftNickname.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedBio = draftBio.trimmingCharacters(in: .whitespacesAndNewlines)
    nickname = String(trimmedNickname.prefix(20))
    bio = String(trimmedBio.prefix(60))
    avatarSeed = draftAvatarSeed
    dismiss()
  }

  private func saveAvatar(_ item: PhotosPickerItem) async {
    isSavingAvatar = true
    avatarErrorMessage = nil
    defer {
      isSavingAvatar = false
      selectedAvatarItem = nil
    }

    do {
      guard let data = try await item.loadTransferable(type: Data.self) else {
        avatarErrorMessage = "无法读取这张照片。"
        return
      }
      try await imageAssetStore.savePickedImage(data: data, purpose: .profileAvatar)
    } catch {
      avatarErrorMessage = "头像保存失败，请换一张照片重试。"
    }
  }
}

private enum MineAvatarSeed {
  static func make() -> String {
    "mine-avatar-\(UUID().uuidString)"
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
    ArtworkImageView(resolution: artworkResolution) {
      Color.clear
    }
    .aspectRatio(1, contentMode: .fit)
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .clipped()
    .accessibilityHidden(true)
  }

  private var artworkResolution: ArtworkResolution {
    ArtworkResolution(remoteURLs: [station.artworkURL] + station.tracks.map(\.artworkURL))
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

}

private struct MineTrackArtwork: View {
  let track: Track
  let size: CGFloat

  var body: some View {
    RemoteArtworkView(urls: [track.artworkURL]) {
      Color.clear
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    .accessibilityHidden(true)
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
  .environment(AppleMusicLibraryStore())
  .environment(DiagnosticsStore.preview())
  .environment(ImageAssetStore())
  .environment(ArtworkAnalysisStore())
}
