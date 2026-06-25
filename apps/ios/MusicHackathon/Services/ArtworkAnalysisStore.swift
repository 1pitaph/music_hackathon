import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class ArtworkAnalysisStore {
  private var analyses: [String: ArtworkAnalysisResult] = [:]

  func analysis(for key: String) -> ArtworkAnalysisResult? {
    analyses[key]
  }

  func setAnalysis(_ analysis: ArtworkAnalysisResult, for key: String) {
    analyses[key] = analysis
  }

  @discardableResult
  func analyze(source: ArtworkSource, imageStore: ImageAssetStore) -> ArtworkAnalysisResult? {
    let key = source.id
    if let analysis = analyses[key] {
      return analysis
    }
    guard let image = imageStore.image(for: source) else { return nil }
    let analysis = Self.analyze(image: image)
    analyses[key] = analysis
    return analysis
  }

  @discardableResult
  func analyze(image: UIImage, key: String) -> ArtworkAnalysisResult {
    if let analysis = analyses[key] {
      return analysis
    }
    let analysis = Self.analyze(image: image)
    analyses[key] = analysis
    return analysis
  }

  static func analyze(image: UIImage) -> ArtworkAnalysisResult {
    guard let cgImage = image.cgImage else { return .fallback }

    let width = 12
    let height = 12
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var rawData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
    guard let context = CGContext(
      data: &rawData,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return .fallback
    }

    context.interpolationQuality = .medium
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    var redTotal = 0
    var greenTotal = 0
    var blueTotal = 0
    var darkRedTotal = 0
    var darkGreenTotal = 0
    var darkBlueTotal = 0
    var darkCount = 0

    for index in stride(from: 0, to: rawData.count, by: bytesPerPixel) {
      let red = Int(rawData[index])
      let green = Int(rawData[index + 1])
      let blue = Int(rawData[index + 2])
      redTotal += red
      greenTotal += green
      blueTotal += blue

      let luma = luma(red: red, green: green, blue: blue)
      if luma < 142 {
        darkRedTotal += red
        darkGreenTotal += green
        darkBlueTotal += blue
        darkCount += 1
      }
    }

    let count = width * height
    let dominant = RGB(
      red: redTotal / count,
      green: greenTotal / count,
      blue: blueTotal / count
    )
    let secondary = darkCount > 0
      ? RGB(red: darkRedTotal / darkCount, green: darkGreenTotal / darkCount, blue: darkBlueTotal / darkCount)
      : dominant.darkened()
    let dominantLuma = luma(red: dominant.red, green: dominant.green, blue: dominant.blue)
    let isDark = dominantLuma < 128

    return ArtworkAnalysisResult(
      dominantHex: dominant.hex,
      secondaryHex: secondary.hex,
      isDark: isDark,
      recommendedForegroundHex: isDark ? "#FFFFFF" : "#121212"
    )
  }

  private static func luma(red: Int, green: Int, blue: Int) -> Int {
    Int((Double(red) * 0.299) + (Double(green) * 0.587) + (Double(blue) * 0.114))
  }
}

private struct RGB {
  let red: Int
  let green: Int
  let blue: Int

  var hex: String {
    String(format: "#%02X%02X%02X", clamped(red), clamped(green), clamped(blue))
  }

  func darkened() -> RGB {
    RGB(red: red / 2, green: green / 2, blue: blue / 2)
  }

  private func clamped(_ value: Int) -> Int {
    min(max(value, 0), 255)
  }
}
