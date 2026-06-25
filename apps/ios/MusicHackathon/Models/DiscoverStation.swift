import SwiftUI

struct DiscoverStation: Identifiable, Hashable {
  let id: String
  let title: String
  let briefIntro: String
  let description: String
  let hostName: String
  let genre: String
  let favorites: Int
  let items: [RadioQueueItem]
  let colorHex: String
  let artworkURL: URL?
  let shareURL: URL

  var color: Color {
    Color(hex: colorHex)
  }

  var formattedFavorites: String {
    if favorites >= 1000 {
      return String(format: "%.1fk", Double(favorites) / 1000)
    }
    return "\(favorites)"
  }

  var heroArtworkURL: URL? {
    artworkURL ?? items.first?.track.artworkURL
  }

  var artworkURLs: [URL] {
    var seen: Set<URL> = []
    var urls: [URL] = []

    if let artworkURL {
      seen.insert(artworkURL)
      urls.append(artworkURL)
    }

    for item in items {
      guard let artworkURL = item.track.artworkURL, !seen.contains(artworkURL) else { continue }
      seen.insert(artworkURL)
      urls.append(artworkURL)
    }

    return urls
  }

  func radioStation() -> RadioStation {
    RadioStation(
      id: id,
      title: title,
      subtitle: briefIntro,
      items: items,
      speech: radioSpeech
    )
  }

  private var radioSpeech: RadioSpeech? {
    guard let firstItem = items.first else { return nil }

    let introText = firstItem.handoffText?.trimmedNilIfEmpty
      ?? L10n.tr("radioSpeech.stationIntro", title, firstItem.track.title)
    let transitions = adjacentItemPairs().enumerated().map { index, pair in
      let displayText = pair.next.handoffText?.trimmedNilIfEmpty
        ?? L10n.tr("radioSpeech.nextTrack", pair.next.track.title, pair.next.track.artist)
      let text = L10n.tr("radioSpeech.transition", pair.current.track.title, pair.next.track.title, displayText)

      return RadioTransitionCopy(
        id: "\(id)-transition-\(index + 1)",
        fromItemId: pair.current.id,
        toItemId: pair.next.id,
        text: text,
        displayText: displayText,
        agent: "discover_station"
      )
    }

    return RadioSpeech(
      stationIntro: RadioStationIntroCopy(
        id: "\(id)-intro",
        text: introText,
        displayText: introText,
        targetItemId: firstItem.id,
        agent: "discover_station"
      ),
      betweenTracks: transitions
    )
  }

  private func adjacentItemPairs() -> [(current: RadioQueueItem, next: RadioQueueItem)] {
    guard items.count > 1 else { return [] }

    return items.indices.dropLast().map { index in
      (current: items[index], next: items[index + 1])
    }
  }
}

extension DiscoverStation {
  static func stations(
    from playlists: [AppleMusicPlaylistSnapshot],
    libraryTracks: [Track]
  ) -> [DiscoverStation] {
    let playlistStations = playlists.enumerated().compactMap { index, playlist -> DiscoverStation? in
      let playableTracks = playlist.tracks.filter { $0.isPlayable && $0.hasRealArtwork }
      guard !playableTracks.isEmpty else { return nil }

      return make(
        id: "apple-music-playlist-\(playlist.id)",
        title: playlist.name,
        briefIntro: L10n.tr("discover.appleMusicPlaylist.briefIntro"),
        description: L10n.tr("discover.appleMusicPlaylist.description", playlist.name),
        hostName: playlist.curatorName ?? "Apple Music",
        genre: dominantGenre(in: playableTracks),
        favorites: playableTracks.count,
        colorHex: colorHex(at: index),
        artworkURL: playlist.artworkURL,
        tracks: playableTracks,
        startIndex: 0
      )
    }

    if !playlistStations.isEmpty {
      return playlistStations
    }

    let playableTracks = libraryTracks.filter { $0.isPlayable && $0.hasRealArtwork }
    guard !playableTracks.isEmpty else { return [] }

    return playableTracks.chunked(maxSize: 6).enumerated().compactMap { index, tracks in
      make(
        id: "apple-music-library-\(index)",
        title: index == 0 ? L10n.tr("discover.libraryStation.title") : L10n.tr("discover.libraryStation.numberedTitle", index + 1),
        briefIntro: L10n.tr("discover.libraryStation.briefIntro"),
        description: L10n.tr("discover.libraryStation.description"),
        hostName: "Apple Music",
        genre: dominantGenre(in: tracks),
        favorites: tracks.count,
        colorHex: colorHex(at: index),
        artworkURL: tracks.first?.artworkURL,
        tracks: tracks,
        startIndex: 0
      )
    }
  }

  static let mockStations: [DiscoverStation] = {
    let tracks = MockCatalog.radioCandidates.isEmpty ? MockCatalog.featuredTracks : MockCatalog.radioCandidates

    return [
      make(
        id: "kitchen-340",
        title: L10n.tr("discover.mock.kitchen.title"),
        briefIntro: L10n.tr("discover.mock.kitchen.briefIntro"),
        description: L10n.tr("discover.mock.kitchen.description"),
        hostName: L10n.tr("discover.mock.kitchen.hostName"),
        genre: L10n.tr("discover.mock.kitchen.genre"),
        favorites: 2340,
        colorHex: "#D8633C",
        artworkURL: nil,
        tracks: tracks,
        startIndex: 0
      ),
      make(
        id: "neighbor-piano",
        title: L10n.tr("discover.mock.neighborPiano.title"),
        briefIntro: L10n.tr("discover.mock.neighborPiano.briefIntro"),
        description: L10n.tr("discover.mock.neighborPiano.description"),
        hostName: L10n.tr("discover.mock.neighborPiano.hostName"),
        genre: L10n.tr("discover.mock.neighborPiano.genre"),
        favorites: 1890,
        colorHex: "#C9A23E",
        artworkURL: nil,
        tracks: tracks,
        startIndex: 2
      ),
      make(
        id: "last-bus",
        title: L10n.tr("discover.mock.lastBus.title"),
        briefIntro: L10n.tr("discover.mock.lastBus.briefIntro"),
        description: L10n.tr("discover.mock.lastBus.description"),
        hostName: L10n.tr("discover.mock.lastBus.hostName"),
        genre: L10n.tr("discover.mock.lastBus.genre"),
        favorites: 3200,
        colorHex: "#8C7355",
        artworkURL: nil,
        tracks: tracks,
        startIndex: 4
      ),
      make(
        id: "poster-shop",
        title: L10n.tr("discover.mock.posterShop.title"),
        briefIntro: L10n.tr("discover.mock.posterShop.briefIntro"),
        description: L10n.tr("discover.mock.posterShop.description"),
        hostName: "rec.",
        genre: L10n.tr("discover.mock.posterShop.genre"),
        favorites: 1560,
        colorHex: "#B5562E",
        artworkURL: nil,
        tracks: tracks,
        startIndex: 6
      ),
      make(
        id: "plastic-bloom",
        title: L10n.tr("discover.mock.plasticBloom.title"),
        briefIntro: L10n.tr("discover.mock.plasticBloom.briefIntro"),
        description: L10n.tr("discover.mock.plasticBloom.description"),
        hostName: L10n.tr("discover.mock.plasticBloom.hostName"),
        genre: L10n.tr("discover.mock.plasticBloom.genre"),
        favorites: 2780,
        colorHex: "#5C4A38",
        artworkURL: nil,
        tracks: tracks,
        startIndex: 8
      ),
      make(
        id: "weak-signal",
        title: L10n.tr("discover.mock.weakSignal.title"),
        briefIntro: L10n.tr("discover.mock.weakSignal.briefIntro"),
        description: L10n.tr("discover.mock.weakSignal.description"),
        hostName: L10n.tr("discover.mock.weakSignal.hostName"),
        genre: L10n.tr("discover.mock.weakSignal.genre"),
        favorites: 2100,
        colorHex: "#9C6B3E",
        artworkURL: nil,
        tracks: tracks,
        startIndex: 10
      )
    ].compactMap { $0 }
  }()

  private static func make(
    id: String,
    title: String,
    briefIntro: String,
    description: String,
    hostName: String,
    genre: String,
    favorites: Int,
    colorHex: String,
    artworkURL: URL?,
    tracks: [Track],
    startIndex: Int
  ) -> DiscoverStation? {
    let playableTracks = tracks.filter { $0.isPlayable && $0.hasRealArtwork }
    let fallbackTracks = MockCatalog.featuredTracks.filter { $0.isPlayable && $0.hasRealArtwork }
    let sourceTracks = playableTracks.isEmpty ? fallbackTracks : playableTracks
    let realArtworkURL = ArtworkURLCandidates.normalized(artworkURL) ?? sourceTracks.first?.artworkURL
    guard !sourceTracks.isEmpty, realArtworkURL != nil else { return nil }

    let items = (0..<min(5, sourceTracks.count)).map { offset in
      let track = sourceTracks[(startIndex + offset) % sourceTracks.count]
      return RadioQueueItem(
        id: "\(id)-\(offset)",
        track: track,
        sourceTitle: hostName,
        reason: L10n.tr("discover.station.reason", hostName, track.title, title),
        handoffText: offset == 0 ? L10n.tr("radioSpeech.stationIntro", title, track.title) : nil
      )
    }

    return DiscoverStation(
      id: id,
      title: title,
      briefIntro: briefIntro,
      description: description,
      hostName: hostName,
      genre: genre,
      favorites: favorites,
      items: items,
      colorHex: colorHex,
      artworkURL: realArtworkURL,
      shareURL: URL(string: "https://airset.example/stations/\(id)")!
    )
  }

  private static func dominantGenre(in tracks: [Track]) -> String {
    tracks.first?.mood ?? "Apple Music"
  }

  private static func colorHex(at index: Int) -> String {
    let palette = ["#D8633C", "#C9A23E", "#3A6B5C", "#5B4A7A", "#B5562E", "#4C7282"]
    return palette[index % palette.count]
  }
}

private extension Array {
  func chunked(maxSize: Int) -> [[Element]] {
    guard maxSize > 0 else { return [] }
    return stride(from: 0, to: count, by: maxSize).map { startIndex in
      Array(self[startIndex..<Swift.min(startIndex + maxSize, count)])
    }
  }
}

private extension String {
  var trimmedNilIfEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

extension Color {
  init(hex: String) {
    let cleanedHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var value: UInt64 = 0
    Scanner(string: cleanedHex).scanHexInt64(&value)

    let red: Double
    let green: Double
    let blue: Double

    switch cleanedHex.count {
    case 6:
      red = Double((value & 0xFF0000) >> 16) / 255
      green = Double((value & 0x00FF00) >> 8) / 255
      blue = Double(value & 0x0000FF) / 255
    default:
      red = 1
      green = 1
      blue = 1
    }

    self.init(red: red, green: green, blue: blue)
  }
}
