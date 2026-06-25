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
      return "Today"
    }
    if days == 1 {
      return "1 day ago"
    }
    if days < 7 {
      return "\(days) days ago"
    }
    if days < 14 {
      return "1 week ago"
    }
    if days < 30 {
      return "\(days / 7) weeks ago"
    }
    return "\(days / 30) months ago"
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
    nickname: "Mine Radio",
    avatarColorHex: "#2A2A2A",
    bio: "Your sound. Your story.",
    stats: ArchiveStats(listeningHours: 342, stationsCount: 28, likesCount: 1247),
    published: [
      ArchiveStationItem(
        id: "p1",
        name: "Late Night Lo-fi",
        createdAt: Date(timeIntervalSinceNow: -2 * 86_400),
        isFeatured: true,
        genre: "Lo-fi",
        colorHex: ArchiveStationItem.colorHex(for: "p1")
      ),
      ArchiveStationItem(
        id: "p2",
        name: "Morning Coffee",
        createdAt: Date(timeIntervalSinceNow: -5 * 86_400),
        isFeatured: false,
        genre: "Jazz",
        colorHex: ArchiveStationItem.colorHex(for: "p2")
      ),
      ArchiveStationItem(
        id: "p3",
        name: "Weekend Vinyl",
        createdAt: Date(timeIntervalSinceNow: -8 * 86_400),
        isFeatured: true,
        genre: "Rock",
        colorHex: ArchiveStationItem.colorHex(for: "p3")
      ),
      ArchiveStationItem(
        id: "p4",
        name: "Indie Discovery",
        createdAt: Date(timeIntervalSinceNow: -12 * 86_400),
        isFeatured: true,
        genre: "Indie",
        colorHex: ArchiveStationItem.colorHex(for: "p4")
      ),
      ArchiveStationItem(
        id: "p5",
        name: "Electronic Hour",
        createdAt: Date(timeIntervalSinceNow: -20 * 86_400),
        isFeatured: false,
        genre: "Electronic",
        colorHex: ArchiveStationItem.colorHex(for: "p5")
      )
    ],
    saved: [
      station(id: "s1", name: "Jazz Standard", genre: "Jazz"),
      station(id: "s2", name: "Classic Rock Radio", genre: "Rock"),
      station(id: "s3", name: "Ambient Waves", genre: "Ambient"),
      station(id: "s4", name: "Hip Hop Daily", genre: "Hip Hop"),
      station(id: "s5", name: "Acoustic Sessions", genre: "Acoustic"),
      station(id: "s6", name: "Soul Kitchen", genre: "Soul")
    ],
    recentlyPlayed: [
      station(id: "r1", name: "Late Night Lo-fi", genre: "Lo-fi"),
      station(id: "r2", name: "Jazz Standard", genre: "Jazz"),
      station(id: "r3", name: "Morning Coffee", genre: "Jazz"),
      station(id: "r4", name: "Ambient Waves", genre: "Ambient"),
      station(id: "r5", name: "Electronic Hour", genre: "Electronic"),
      station(id: "r6", name: "Classic Rock Radio", genre: "Rock"),
      station(id: "r7", name: "Weekend Vinyl", genre: "Rock")
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
      "\(trackCount) \(trackCount == 1 ? "song" : "songs")"
    ]
      .compactMap { $0 }
      .joined(separator: " • ")

    return ArchiveStationItem(
      id: "playlist-\(playlist.id)",
      name: playlist.name,
      createdAt: nil,
      isFeatured: trackCount > 0,
      genre: "Playlist",
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
      name: "Apple Music Library",
      createdAt: nil,
      isFeatured: true,
      genre: "Library",
      colorHex: ArchiveStationItem.colorHex(for: "library-all-songs"),
      artworkURL: tracks.first?.artworkURL,
      subtitle: "\(tracks.count) \(tracks.count == 1 ? "song" : "songs")",
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
          genre: "Artist",
          colorHex: ArchiveStationItem.colorHex(for: artist),
          artworkURL: artistTracks.first?.artworkURL,
          subtitle: "\(artistTracks.count) \(artistTracks.count == 1 ? "song" : "songs")",
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
