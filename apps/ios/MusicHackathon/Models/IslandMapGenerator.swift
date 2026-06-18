import CoreGraphics
import Foundation

struct IslandMapGenerator {
  let seed: UInt64

  func generate(from tracks: [Track]) -> [MusicIsland] {
    var random = SeededRandom(seed: seed)
    let columns = 7
    let rows = 8
    let spacing = CGSize(width: 236, height: 252)
    let origin = CGPoint(
      x: -CGFloat(columns - 1) * spacing.width / 2,
      y: -CGFloat(rows - 1) * spacing.height / 2
    )

    var centers: [CGPoint] = []
    for row in 0..<rows {
      for column in 0..<columns {
        let rowOffset: CGFloat = row.isMultiple(of: 2) ? 0 : spacing.width * 0.34
        let jitter = CGPoint(
          x: random.cgFloat(in: -46...46),
          y: random.cgFloat(in: -54...54)
        )
        centers.append(
          CGPoint(
            x: origin.x + CGFloat(column) * spacing.width + rowOffset + jitter.x,
            y: origin.y + CGFloat(row) * spacing.height + jitter.y
          )
        )
      }
    }

    let featuredIndexes = centers
      .indices
      .sorted { distanceSquared(centers[$0]) < distanceSquared(centers[$1]) }
      .prefix(tracks.count)

    var trackByIndex: [Int: Track] = [:]
    for (trackOffset, centerIndex) in featuredIndexes.enumerated() {
      trackByIndex[centerIndex] = tracks[trackOffset]
    }

    return centers.enumerated().map { index, center in
      let track = trackByIndex[index]
      let importance = track == nil ? random.int(in: 1...3) : 5
      let radius = random.cgFloat(in: track == nil ? 72...108 : 104...132)
      let pointCount = random.int(in: 18...28)
      let points = makeIslandPoints(radius: radius, pointCount: pointCount, random: &random)
      let style = MusicIslandStyle(
        palette: MusicIslandPalette.allCases[random.int(in: 0...(MusicIslandPalette.allCases.count - 1))],
        pattern: MusicIslandPattern.allCases[random.int(in: 0...(MusicIslandPattern.allCases.count - 1))],
        dashPhase: random.cgFloat(in: 0...16)
      )

      return MusicIsland(
        id: UUID(uuidString: seededUUIDString(index: index)) ?? UUID(),
        title: track?.title.capitalized ?? generatedTitle(index: index),
        subtitle: track.map { "\($0.artist) - \($0.album)" } ?? generatedSubtitle(index: index, random: &random),
        mood: track?.mood ?? generatedMood(index: index),
        track: track,
        center: center,
        radius: radius,
        points: points,
        style: style,
        importance: importance
      )
    }
  }

  private func makeIslandPoints(
    radius: CGFloat,
    pointCount: Int,
    random: inout SeededRandom
  ) -> [CGPoint] {
    let phaseA = random.cgFloat(in: 0...(CGFloat.pi * 2))
    let phaseB = random.cgFloat(in: 0...(CGFloat.pi * 2))
    let stretch = random.cgFloat(in: 0.82...1.18)
    let squash = random.cgFloat(in: 0.84...1.16)
    let wobble = random.cgFloat(in: 0.10...0.22)

    return (0..<pointCount).map { index in
      let t = CGFloat(index) / CGFloat(pointCount)
      let angle = t * CGFloat.pi * 2
      let wave = sin(angle * 2.0 + phaseA) * 0.10 + sin(angle * 5.0 + phaseB) * wobble
      let localNoise = random.cgFloat(in: -0.08...0.08)
      let r = radius * (1 + wave + localNoise)

      return CGPoint(
        x: cos(angle) * r * stretch,
        y: sin(angle) * r * squash
      )
    }
  }

  private func distanceSquared(_ point: CGPoint) -> CGFloat {
    point.x * point.x + point.y * point.y
  }

  private func seededUUIDString(index: Int) -> String {
    let indexHex = String(format: "%012llX", UInt64(index + 1))
    return "17034200-0000-4000-8000-\(indexHex)"
  }

  private func generatedTitle(index: Int) -> String {
    let names = [
      "Echo Garden",
      "Drift Cove",
      "Pulse Field",
      "Signal Reef",
      "Velvet Point",
      "Amber Loop",
      "Neon Orchard",
      "Soft Harbor",
      "Static Isle",
      "Cloud Verse",
      "Golden Break",
      "Quiet Channel"
    ]

    return names[index % names.count]
  }

  private func generatedSubtitle(index: Int, random: inout SeededRandom) -> String {
    let statuses = ["New signal", "Close friends", "Late replay", "Shared queue", "Hidden set"]
    let count = random.int(in: 2...9)
    return "\(statuses[index % statuses.count]) - \(count).\(random.int(in: 0...9))k listeners"
  }

  private func generatedMood(index: Int) -> String {
    let moods = ["Glowing", "Cinematic", "Warm", "Dream pop", "Night drive", "Acoustic", "Surreal"]
    return moods[index % moods.count]
  }
}

private struct SeededRandom {
  private var state: UInt64

  init(seed: UInt64) {
    self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
  }

  mutating func int(in range: ClosedRange<Int>) -> Int {
    let span = UInt64(range.upperBound - range.lowerBound + 1)
    return range.lowerBound + Int(next() % span)
  }

  mutating func cgFloat(in range: ClosedRange<CGFloat>) -> CGFloat {
    range.lowerBound + CGFloat(unitDouble()) * (range.upperBound - range.lowerBound)
  }

  private mutating func unitDouble() -> Double {
    Double(next() >> 11) / Double(1 << 53)
  }

  private mutating func next() -> UInt64 {
    state &+= 0x9E3779B97F4A7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
    z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
    return z ^ (z >> 31)
  }
}
