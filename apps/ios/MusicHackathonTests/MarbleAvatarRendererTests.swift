import CoreGraphics
import XCTest
@testable import MusicHackathon

final class MarbleAvatarRendererTests: XCTestCase {
  func testLayersAreStableForSameSeedAndPalette() {
    let first = MarbleAvatarRenderer.layers(seed: "Maria Mitchell", palette: MarbleAvatarPalette.defaultHex)
    let second = MarbleAvatarRenderer.layers(seed: "Maria Mitchell", palette: MarbleAvatarPalette.defaultHex)

    XCTAssertEqual(first, second)
  }

  func testDifferentSeedsProduceDifferentLayerSpecs() {
    let first = MarbleAvatarRenderer.layers(seed: "Maria Mitchell", palette: MarbleAvatarPalette.defaultHex)
    let second = MarbleAvatarRenderer.layers(seed: "mine-avatar-test", palette: MarbleAvatarPalette.defaultHex)

    XCTAssertNotEqual(first, second)
  }

  func testMariaMitchellMatchesBoringAvatarsMarbleProperties() {
    let layers = MarbleAvatarRenderer.layers(seed: "Maria Mitchell", palette: MarbleAvatarPalette.defaultHex)

    XCTAssertEqual(layers.count, 3)
    assertLayer(layers[0], colorHex: "#C271B4", translation: CGSize(width: 6, height: -6), scale: 1.4, rotationDegrees: 198)
    assertLayer(layers[1], colorHex: "#C20D90", translation: CGSize(width: 4, height: -4), scale: 1.2, rotationDegrees: 36)
    assertLayer(layers[2], colorHex: "#92A1C6", translation: CGSize(width: 2, height: 2), scale: 1.4, rotationDegrees: 234)
  }

  func testEmptyPaletteFallsBackToDefaultPaletteAndValidGeometry() {
    let layers = MarbleAvatarRenderer.layers(seed: "seed-123", palette: [])

    XCTAssertEqual(layers.count, 3)
    for layer in layers {
      XCTAssertFalse(layer.colorHex.isEmpty)
      XCTAssertTrue(MarbleAvatarPalette.defaultHex.contains(layer.colorHex))
      XCTAssertFalse(layer.translation.width.isNaN)
      XCTAssertFalse(layer.translation.height.isNaN)
      XCTAssertFalse(layer.scale.isNaN)
      XCTAssertFalse(layer.rotationDegrees.isNaN)
    }
  }

  private func assertLayer(
    _ layer: MarbleAvatarLayer,
    colorHex: String,
    translation: CGSize,
    scale: CGFloat,
    rotationDegrees: CGFloat,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(layer.colorHex, colorHex, file: file, line: line)
    XCTAssertEqual(layer.translation.width, translation.width, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(layer.translation.height, translation.height, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(layer.scale, scale, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(layer.rotationDegrees, rotationDegrees, accuracy: 0.0001, file: file, line: line)
  }
}
