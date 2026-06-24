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

  func radioStation() -> RadioStation {
    RadioStation(
      id: id,
      title: title,
      subtitle: briefIntro,
      items: items
    )
  }
}

extension DiscoverStation {
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
        tracks: tracks,
        startIndex: 10
      )
    ]
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
    tracks: [Track],
    startIndex: Int
  ) -> DiscoverStation {
    let playableTracks = tracks.filter(\.isPlayable)
    let sourceTracks = playableTracks.isEmpty ? MockCatalog.featuredTracks : playableTracks
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
      shareURL: URL(string: "https://airset.example/stations/\(id)")!
    )
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
