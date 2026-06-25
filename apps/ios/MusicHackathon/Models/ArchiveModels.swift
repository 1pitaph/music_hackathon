import Foundation

struct ArchiveStats: Hashable {
  var listeningHours: Int
  var stationsCount: Int
  var likesCount: Int
}

struct ArchiveStationItem: Identifiable, Hashable {
  let id: String
  var name: String
  var createdAt: Date?
  var isFeatured: Bool
  var genre: String
  var colorHex: String
  var artworkURL: URL? = nil
  var subtitle: String? = nil
  var tracks: [Track] = []

  var relativeCreatedAt: String {
    guard let createdAt else { return "" }

    let days = max(0, Int(Date().timeIntervalSince(createdAt) / 86_400))
    if days < 1 {
      return L10n.tr("archive.relative.today")
    }
    if days == 1 {
      return L10n.count("archive.relative.dayAgo", 1)
    }
    if days < 7 {
      return L10n.count("archive.relative.dayAgo", days)
    }
    if days < 14 {
      return L10n.count("archive.relative.weekAgo", 1)
    }
    if days < 30 {
      return L10n.count("archive.relative.weekAgo", days / 7)
    }
    return L10n.count("archive.relative.monthAgo", days / 30)
  }

  var displaySubtitle: String {
    if let subtitle, !subtitle.isEmpty {
      return subtitle
    }

    let relativeDateText = relativeCreatedAt
    if !relativeDateText.isEmpty {
      return relativeDateText
    }

    return genre
  }
}

struct ArchiveProfile: Hashable {
  var nickname: String
  var avatarColorHex: String
  var bio: String
  var stats: ArchiveStats
  var published: [ArchiveStationItem]
  var saved: [ArchiveStationItem]
  var recentlyPlayed: [ArchiveStationItem]
  var artists: [String]

  var recentPublished: [ArchiveStationItem] {
    Array(
      published
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
        .prefix(5)
    )
  }

  var curatedStations: [ArchiveStationItem] {
    published.filter(\.isFeatured)
  }
}

extension ArchiveStationItem {
  static let coverPalette = [
    "#8B5E3C",
    "#C75B39",
    "#3A6B5C",
    "#5B4A7A",
    "#D4956A"
  ]

  static func colorHex(for id: String) -> String {
    var hash = 0
    for scalar in id.unicodeScalars {
      hash = ((hash << 5) &- hash) &+ Int(scalar.value)
    }
    return coverPalette[abs(hash) % coverPalette.count]
  }
}

extension PublishedDiscoverStation {
  func archiveStationItem() -> ArchiveStationItem {
    ArchiveStationItem(
      id: "published-discover-\(stationID)",
      name: title,
      createdAt: publishedDate,
      isFeatured: false,
      genre: seedTracks.first?.mood ?? items.first?.track.mood ?? "Radio",
      colorHex: colorHex,
      artworkURL: coverArtworkURL ?? items.first?.track.artworkURL,
      subtitle: subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : subtitle,
      tracks: items.map(\.track)
    )
  }

  private var publishedDate: Date? {
    PublishedDiscoverStationDateParser.date(from: publishedAt)
  }
}

private enum PublishedDiscoverStationDateParser {
  private static let fractionalFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private static let standardFormatter = ISO8601DateFormatter()

  static func date(from value: String) -> Date? {
    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedValue.isEmpty else { return nil }

    return fractionalFormatter.date(from: trimmedValue)
      ?? standardFormatter.date(from: trimmedValue)
  }
}

extension ArchiveProfile {
  static let empty = ArchiveProfile(
    nickname: "",
    avatarColorHex: "#2A2A2A",
    bio: "",
    stats: ArchiveStats(listeningHours: 0, stationsCount: 0, likesCount: 0),
    published: [],
    saved: [],
    recentlyPlayed: [],
    artists: []
  )

  static let mock = ArchiveProfile(
    nickname: L10n.tr("archive.mock.nickname"),
    avatarColorHex: "#2A2A2A",
    bio: L10n.tr("archive.mock.bio"),
    stats: ArchiveStats(listeningHours: 342, stationsCount: 28, likesCount: 1247),
    published: [
      ArchiveStationItem(
        id: "p1",
        name: L10n.tr("archive.mock.lateNightLoFi"),
        createdAt: Date(timeIntervalSinceNow: -2 * 86_400),
        isFeatured: true,
        genre: "Lo-fi",
        colorHex: ArchiveStationItem.colorHex(for: "p1")
      ),
      ArchiveStationItem(
        id: "p2",
        name: L10n.tr("archive.mock.morningCoffee"),
        createdAt: Date(timeIntervalSinceNow: -5 * 86_400),
        isFeatured: false,
        genre: L10n.tr("genre.jazz"),
        colorHex: ArchiveStationItem.colorHex(for: "p2")
      ),
      ArchiveStationItem(
        id: "p3",
        name: L10n.tr("archive.mock.weekendVinyl"),
        createdAt: Date(timeIntervalSinceNow: -8 * 86_400),
        isFeatured: true,
        genre: L10n.tr("genre.rock"),
        colorHex: ArchiveStationItem.colorHex(for: "p3")
      ),
      ArchiveStationItem(
        id: "p4",
        name: L10n.tr("archive.mock.indieDiscovery"),
        createdAt: Date(timeIntervalSinceNow: -12 * 86_400),
        isFeatured: true,
        genre: L10n.tr("genre.indie"),
        colorHex: ArchiveStationItem.colorHex(for: "p4")
      ),
      ArchiveStationItem(
        id: "p5",
        name: L10n.tr("archive.mock.electronicHour"),
        createdAt: Date(timeIntervalSinceNow: -20 * 86_400),
        isFeatured: false,
        genre: L10n.tr("genre.electronic"),
        colorHex: ArchiveStationItem.colorHex(for: "p5")
      )
    ],
    saved: [
      station(id: "s1", name: L10n.tr("archive.mock.jazzStandard"), genre: L10n.tr("genre.jazz")),
      station(id: "s2", name: L10n.tr("archive.mock.classicRockRadio"), genre: L10n.tr("genre.rock")),
      station(id: "s3", name: L10n.tr("archive.mock.ambientWaves"), genre: L10n.tr("genre.ambient")),
      station(id: "s4", name: L10n.tr("archive.mock.hipHopDaily"), genre: L10n.tr("genre.hipHop")),
      station(id: "s5", name: L10n.tr("archive.mock.acousticSessions"), genre: L10n.tr("genre.acoustic")),
      station(id: "s6", name: L10n.tr("archive.mock.soulKitchen"), genre: L10n.tr("genre.soul"))
    ],
    recentlyPlayed: [
      station(id: "r1", name: L10n.tr("archive.mock.lateNightLoFi"), genre: "Lo-fi"),
      station(id: "r2", name: L10n.tr("archive.mock.jazzStandard"), genre: L10n.tr("genre.jazz")),
      station(id: "r3", name: L10n.tr("archive.mock.morningCoffee"), genre: L10n.tr("genre.jazz")),
      station(id: "r4", name: L10n.tr("archive.mock.ambientWaves"), genre: L10n.tr("genre.ambient")),
      station(id: "r5", name: L10n.tr("archive.mock.electronicHour"), genre: L10n.tr("genre.electronic")),
      station(id: "r6", name: L10n.tr("archive.mock.classicRockRadio"), genre: L10n.tr("genre.rock")),
      station(id: "r7", name: L10n.tr("archive.mock.weekendVinyl"), genre: L10n.tr("genre.rock"))
    ],
    artists: [
      "Billie Eilish",
      "Laufey",
      "Frank Ocean",
      "Daniel Caesar",
      "Joji",
      "Keshi"
    ]
  )

  static func appleMusic(
    base: ArchiveProfile,
    playlists: [AppleMusicPlaylistSnapshot],
    tracks libraryTracks: [Track]
  ) -> ArchiveProfile {
    let realArtworkPlaylists = playlists.compactMap(playlistWithRealArtwork)
    let realArtworkLibraryTracks = libraryTracks.filter(\.hasRealArtwork)
    let allTracks = uniqueTracks(from: realArtworkPlaylists.flatMap(\.tracks) + realArtworkLibraryTracks)
    let playlistItems = realArtworkPlaylists.map(archiveItem(from:))
    let songItems = allTracks.map(archiveItem(from:))
    let artistItems = archiveArtistItems(from: allTracks)
    let totalDuration = allTracks.reduce(0) { $0 + $1.duration }

    var profile = base
    profile.stats = ArchiveStats(
      listeningHours: Int(totalDuration / 3_600),
      stationsCount: realArtworkPlaylists.count,
      likesCount: allTracks.count
    )
    profile.published = playlistItems.isEmpty && !allTracks.isEmpty
      ? [archiveLibraryItem(from: allTracks)]
      : playlistItems
    profile.saved = artistItems
    profile.recentlyPlayed = Array(songItems)
    profile.artists = artistItems.map(\.name)

    if profile.nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
       let inferredNickname = inferredNickname(from: realArtworkPlaylists) {
      profile.nickname = inferredNickname
    }

    return profile
  }

  private static func playlistWithRealArtwork(_ playlist: AppleMusicPlaylistSnapshot) -> AppleMusicPlaylistSnapshot? {
    let tracks = uniqueTracks(from: playlist.tracks.filter(\.hasRealArtwork))
    let artworkURL = ArtworkURLCandidates.normalized(playlist.artworkURL) ?? tracks.first?.artworkURL
    guard !tracks.isEmpty, artworkURL != nil else { return nil }

    return AppleMusicPlaylistSnapshot(
      id: playlist.id,
      name: playlist.name,
      curatorName: playlist.curatorName,
      artworkURL: artworkURL,
      tracks: tracks
    )
  }

  private static func station(id: String, name: String, genre: String) -> ArchiveStationItem {
    ArchiveStationItem(
      id: id,
      name: name,
      createdAt: nil,
      isFeatured: false,
      genre: genre,
      colorHex: ArchiveStationItem.colorHex(for: id)
    )
  }

  private static func archiveItem(from playlist: AppleMusicPlaylistSnapshot) -> ArchiveStationItem {
    let trackCount = playlist.tracks.count
    let subtitle = [
      playlist.curatorName,
      L10n.count("count.songs", trackCount)
    ]
      .compactMap { $0 }
      .joined(separator: " • ")

    return ArchiveStationItem(
      id: "playlist-\(playlist.id)",
      name: playlist.name,
      createdAt: nil,
      isFeatured: trackCount > 0,
      genre: L10n.tr("archive.genre.playlist"),
      colorHex: ArchiveStationItem.colorHex(for: playlist.id),
      artworkURL: playlist.artworkURL ?? playlist.tracks.first?.artworkURL,
      subtitle: subtitle,
      tracks: playlist.tracks
    )
  }

  private static func archiveItem(from track: Track) -> ArchiveStationItem {
    ArchiveStationItem(
      id: "track-\(track.radioIdentity)",
      name: track.title,
      createdAt: nil,
      isFeatured: false,
      genre: track.artist,
      colorHex: ArchiveStationItem.colorHex(for: track.radioIdentity),
      artworkURL: track.artworkURL,
      subtitle: [track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " • "),
      tracks: [track]
    )
  }

  private static func archiveLibraryItem(from tracks: [Track]) -> ArchiveStationItem {
    ArchiveStationItem(
      id: "library-all-songs",
      name: L10n.tr("archive.appleMusicLibrary"),
      createdAt: nil,
      isFeatured: true,
      genre: L10n.tr("archive.genre.library"),
      colorHex: ArchiveStationItem.colorHex(for: "library-all-songs"),
      artworkURL: tracks.first?.artworkURL,
      subtitle: L10n.count("count.songs", tracks.count),
      tracks: tracks
    )
  }

  private static func archiveArtistItems(from tracks: [Track]) -> [ArchiveStationItem] {
    let groupedTracks = Dictionary(grouping: tracks) { $0.artist }

    return groupedTracks.keys
      .sorted { lhs, rhs in
        let lhsCount = groupedTracks[lhs]?.count ?? 0
        let rhsCount = groupedTracks[rhs]?.count ?? 0
        if lhsCount == rhsCount {
          return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        return lhsCount > rhsCount
      }
      .prefix(18)
      .compactMap { artist in
        guard let artistTracks = groupedTracks[artist], !artist.isEmpty else { return nil }
        return ArchiveStationItem(
          id: "artist-\(artist)",
          name: artist,
          createdAt: nil,
          isFeatured: false,
          genre: L10n.tr("archive.genre.artist"),
          colorHex: ArchiveStationItem.colorHex(for: artist),
          artworkURL: artistTracks.first?.artworkURL,
          subtitle: L10n.count("count.songs", artistTracks.count),
          tracks: artistTracks
        )
      }
  }

  private static func inferredNickname(from playlists: [AppleMusicPlaylistSnapshot]) -> String? {
    for playlist in playlists {
      guard let curatorName = playlist.curatorName?.trimmingCharacters(in: .whitespacesAndNewlines),
            !curatorName.isEmpty,
            !isGenericAppleMusicCuratorName(curatorName) else {
        continue
      }

      return curatorName
    }

    return nil
  }

  private static func isGenericAppleMusicCuratorName(_ name: String) -> Bool {
    let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalizedName == "apple music" || normalizedName == "apple"
  }

  private static func uniqueTracks(from tracks: [Track]) -> [Track] {
    var seen = Set<String>()
    return tracks.filter { track in
      let key = track.radioIdentity
      guard !seen.contains(key) else { return false }
      seen.insert(key)
      return true
    }
  }
}
