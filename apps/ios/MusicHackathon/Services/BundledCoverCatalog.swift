import Foundation

struct BundledCover: Identifiable, Hashable {
  let id: String
  let fileName: String
  let title: String
}

enum BundledCoverCatalog {
  static let resourceSubdirectory = "PlaceholderCovers"

  static let covers: [BundledCover] = [
    BundledCover(id: "midnight-blue-note", fileName: "midnight-blue-note.jpg", title: "Midnight Blue Note"),
    BundledCover(id: "neon-rain", fileName: "neon-rain.jpg", title: "Neon Rain"),
    BundledCover(id: "expired-film-darkroom", fileName: "expired-film-darkroom.jpg", title: "Expired Film Darkroom"),
    BundledCover(id: "moon-far-side", fileName: "moon-far-side.jpg", title: "Moon Far Side"),
    BundledCover(id: "soul-shelter", fileName: "soul-shelter.jpg", title: "Soul Shelter"),
    BundledCover(id: "monsoon-leg", fileName: "monsoon-leg.jpg", title: "Monsoon Leg"),
    BundledCover(id: "3am-poetry", fileName: "3am-poetry.jpg", title: "3AM Poetry"),
    BundledCover(id: "blank-tape", fileName: "blank-tape.jpg", title: "Blank Tape"),
    BundledCover(id: "route-9", fileName: "route-9.jpg", title: "Route 9"),
    BundledCover(id: "kissaten-pilgrimage", fileName: "kissaten-pilgrimage.jpg", title: "Kissaten Pilgrimage")
  ]

  static func cover(id: String) -> BundledCover? {
    covers.first { $0.id == id }
  }

  static func source(for id: String) -> ArtworkSource? {
    guard cover(id: id) != nil else { return nil }
    return .bundledCover(id: id)
  }

  static func url(for id: String, bundle: Bundle = .main) -> URL? {
    guard let cover = cover(id: id) else { return nil }
    let resourceName = (cover.fileName as NSString).deletingPathExtension
    let resourceExtension = (cover.fileName as NSString).pathExtension
    return bundle.url(
      forResource: resourceName,
      withExtension: resourceExtension,
      subdirectory: resourceSubdirectory
    )
  }

  static func fallbackSource(forID id: String, title: String, genre: String? = nil) -> ArtworkSource? {
    guard !covers.isEmpty else { return nil }
    let key = [id, title, genre ?? ""].joined(separator: "|")
    let index = Int(stableHash(key) % UInt64(covers.count))
    return .bundledCover(id: covers[index].id)
  }

  static func stableHash(_ value: String) -> UInt64 {
    value.utf8.reduce(UInt64(0xcbf29ce484222325)) { partialResult, byte in
      (partialResult ^ UInt64(byte)) &* 0x100000001b3
    }
  }
}
