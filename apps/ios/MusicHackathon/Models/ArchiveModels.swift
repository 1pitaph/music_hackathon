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
        .sorted { lhs, rhs in
          (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
        }
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
}
