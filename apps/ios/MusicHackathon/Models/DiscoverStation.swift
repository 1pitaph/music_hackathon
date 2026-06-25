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
      ?? "调到 \(title)，先从 \(firstItem.track.title) 开始。"
    let transitions = adjacentItemPairs().enumerated().map { index, pair in
      let displayText = pair.next.handoffText?.trimmedNilIfEmpty
        ?? "接下来是 \(pair.next.track.title) - \(pair.next.track.artist)。"
      let text = "从 \(pair.current.track.title) 进入 \(pair.next.track.title)。\(displayText)"

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
        briefIntro: "来自 Apple Music 资料库的真实歌单",
        description: "\(playlist.name) 已连接到你的 Apple Music 资料库，电台会直接使用这些真实曲目、艺人、专辑和封面。",
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
        title: index == 0 ? "我的 Apple Music" : "我的 Apple Music \(index + 1)",
        briefIntro: "从资料库歌曲生成的真实电台",
        description: "这张卡片来自你的 Apple Music 资料库歌曲，封面、曲名、艺人和专辑都会使用真实数据。",
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
        title: "三点四十的厨房",
        briefIntro: "深夜路过厨房时顺手按下的录音",
        description: "凌晨三点四十分，水滴、锅铲和没关紧的水龙头凑成了一段临时合奏。这是一档适合轻声听完的厨房电台。",
        hostName: "鲸鱼睡着了",
        genre: "Lo-Fi / 氛围",
        favorites: 2340,
        colorHex: "#D8633C",
        artworkURL: nil,
        tracks: tracks,
        startIndex: 0
      ),
      make(
        id: "neighbor-piano",
        title: "邻居的钢琴课",
        briefIntro: "练习曲弹错的部分比弹对的部分好听",
        description: "墙那边的练习曲总会跑偏一点。这里收集那些被老师划红叉、但听起来刚刚好的片段。",
        hostName: "隔壁阿姨",
        genre: "古典 / 钢琴",
        favorites: 1890,
        colorHex: "#C9A23E",
        artworkURL: nil,
        tracks: tracks,
        startIndex: 2
      ),
      make(
        id: "last-bus",
        title: "末班车没追上",
        briefIntro: "适合站在路灯下假装在等人",
        description: "每一次错过末班车，都会多一首回家的歌。如果你也在某个路灯下，这个频道会陪你站一会儿。",
        hostName: "迟到的春天",
        genre: "独立民谣",
        favorites: 3200,
        colorHex: "#8C7355",
        artworkURL: nil,
        tracks: tracks,
        startIndex: 4
      ),
      make(
        id: "poster-shop",
        title: "褪色海报店",
        briefIntro: "老海报店收音机常年没人换台",
        description: "阳光把电影海报晒得很慢，柜台上的收音机也慢。这里放一些旧的、不急着被换掉的声音。",
        hostName: "rec.",
        genre: "低保真 / 独立",
        favorites: 1560,
        colorHex: "#B5562E",
        artworkURL: nil,
        tracks: tracks,
        startIndex: 6
      ),
      make(
        id: "plastic-bloom",
        title: "塑料花期",
        briefIntro: "假花不会枯，但也不会真的开",
        description: "梦幻流行、低保真和一点独立电子组成一朵不会谢的塑料花。它只是安静地开着。",
        hostName: "潦草",
        genre: "梦幻流行",
        favorites: 2780,
        colorHex: "#5C4A38",
        artworkURL: nil,
        tracks: tracks,
        startIndex: 8
      ),
      make(
        id: "weak-signal",
        title: "信号不良",
        briefIntro: "收不清楚反而更适合循环播放",
        description: "信号刚开始断断续续的时候，人会认真听每一个音节。这档电台就在那个模糊但还没消失的频率上。",
        hostName: "三号宇航员",
        genre: "电子 / 实验",
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
        reason: "\(hostName) 把 \(track.title) 放进了 \(title)。",
        handoffText: offset == 0 ? "调到 \(title)，先从 \(track.title) 开始。" : nil
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
