import CoreGraphics
import Foundation

struct MusicIsland: Identifiable, Hashable {
  let id: UUID
  let title: String
  let subtitle: String
  let mood: String
  let track: Track?
  let center: CGPoint
  let radius: CGFloat
  let points: [CGPoint]
  let style: MusicIslandStyle
  let importance: Int
}

struct MusicIslandStyle: Hashable {
  let palette: MusicIslandPalette
  let pattern: MusicIslandPattern
  let dashPhase: CGFloat
}

enum MusicIslandPalette: Int, CaseIterable, Hashable {
  case mint
  case cream
  case sage
  case linen
  case blueMist
}

enum MusicIslandPattern: Int, CaseIterable, Hashable {
  case diagonal
  case dots
  case crosshatch
  case quiet
}
