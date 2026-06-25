import CoreGraphics
import SwiftUI

// Local SwiftUI rendering of Boring Avatars' MIT-licensed marble variant:
// https://github.com/boringdesigners/boring-avatars
struct MarbleAvatarView: View {
  let seed: String
  let size: CGFloat
  let palette: [String]
  let accessibilityLabel: String?

  init(
    seed: String,
    size: CGFloat = 82,
    palette: [String] = MarbleAvatarPalette.defaultHex,
    accessibilityLabel: String? = nil
  ) {
    self.seed = seed
    self.size = size
    self.palette = palette
    self.accessibilityLabel = accessibilityLabel
  }

  var body: some View {
    let layers = MarbleAvatarRenderer.layers(seed: seed, palette: palette)

    Canvas { context, canvasSize in
      let scale = min(canvasSize.width, canvasSize.height) / MarbleAvatarRenderer.size
      let drawingRect = CGRect(origin: .zero, size: canvasSize)

      context.fill(Path(drawingRect), with: .color(Color(hex: layers[0].colorHex)))

      var firstContext = context
      firstContext.addFilter(.blur(radius: 7 * scale))
      firstContext.fill(
        MarbleAvatarRenderer.firstPath.applying(transform(for: layers[1], scaleLayer: layers[2])),
        with: .color(Color(hex: layers[1].colorHex))
      )

      var overlayContext = context
      overlayContext.blendMode = .overlay
      overlayContext.addFilter(.blur(radius: 7 * scale))
      overlayContext.fill(
        MarbleAvatarRenderer.secondPath.applying(transform(for: layers[2], scaleLayer: layers[2])),
        with: .color(Color(hex: layers[2].colorHex))
      )
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .overlay {
      Circle()
        .stroke(.white.opacity(0.18), lineWidth: 2)
    }
    .accessibilityLabel(accessibilityLabel ?? L10n.tr("profile.avatar"))
  }

  private func transform(for layer: MarbleAvatarLayer, scaleLayer: MarbleAvatarLayer) -> CGAffineTransform {
    let outputScale = size / MarbleAvatarRenderer.size
    let center = MarbleAvatarRenderer.size / 2

    var transform = CGAffineTransform.identity
    transform = transform.translatedBy(
      x: layer.translation.width * outputScale,
      y: layer.translation.height * outputScale
    )
    transform = transform.translatedBy(x: center * outputScale, y: center * outputScale)
    transform = transform.rotated(by: layer.rotationDegrees * .pi / 180)
    transform = transform.translatedBy(x: -center * outputScale, y: -center * outputScale)
    transform = transform.scaledBy(x: scaleLayer.scale * outputScale, y: scaleLayer.scale * outputScale)
    return transform
  }
}

enum MarbleAvatarPalette {
  static let defaultHex = ["#92A1C6", "#146A7C", "#F0AB3D", "#C271B4", "#C20D90"]
}

struct MarbleAvatarLayer: Hashable {
  let colorHex: String
  let translation: CGSize
  let scale: CGFloat
  let rotationDegrees: CGFloat
}

enum MarbleAvatarRenderer {
  static let size: CGFloat = 80

  static let firstPath: Path = {
    var path = Path()
    path.move(to: CGPoint(x: 32.414, y: 59.35))
    path.addLine(to: CGPoint(x: 50.376, y: 70.5))
    path.addLine(to: CGPoint(x: 72.5, y: 70.5))
    path.addLine(to: CGPoint(x: 72.5, y: -0.5))
    path.addLine(to: CGPoint(x: 33.728, y: -0.5))
    path.addLine(to: CGPoint(x: 26.5, y: 13.381))
    path.addLine(to: CGPoint(x: 45.557, y: 40.461))
    path.addLine(to: CGPoint(x: 32.414, y: 59.35))
    path.closeSubpath()
    return path
  }()

  static let secondPath: Path = {
    var path = Path()
    path.move(to: CGPoint(x: 22.216, y: 24))
    path.addLine(to: CGPoint(x: 0, y: 46.75))
    path.addLine(to: CGPoint(x: 14.108, y: 84.879))
    path.addLine(to: CGPoint(x: 78, y: 86))
    path.addLine(to: CGPoint(x: 74.919, y: 26.724))
    path.addLine(to: CGPoint(x: 52.541, y: 30.729))
    path.addLine(to: CGPoint(x: 65.513, y: 50.915))
    path.addLine(to: CGPoint(x: 42.163, y: 78.31))
    path.addLine(to: CGPoint(x: 22.215, y: 24))
    path.closeSubpath()
    return path
  }()

  static func layers(seed: String, palette: [String]) -> [MarbleAvatarLayer] {
    let colors = palette.isEmpty ? MarbleAvatarPalette.defaultHex : palette
    let number = hashCode(seed)
    let colorRange = colors.count

    return (0..<3).map { index in
      let multiplier = index + 1
      return MarbleAvatarLayer(
        colorHex: colors[(number + index) % colorRange],
        translation: CGSize(
          width: getUnit(number: number * multiplier, range: Int(size / 10), digitIndex: 1),
          height: getUnit(number: number * multiplier, range: Int(size / 10), digitIndex: 2)
        ),
        scale: 1.2 + CGFloat(getUnit(number: number * multiplier, range: Int(size / 20), digitIndex: nil)) / 10,
        rotationDegrees: CGFloat(getUnit(number: number * multiplier, range: 360, digitIndex: 1))
      )
    }
  }

  private static func hashCode(_ seed: String) -> Int {
    var hash: Int32 = 0
    for unit in seed.utf16 {
      hash = hash &* 31 &+ Int32(unit)
    }
    return Int(abs(Int64(hash)))
  }

  private static func getUnit(number: Int, range: Int, digitIndex: Int?) -> Int {
    let value = number % range
    guard let digitIndex else { return value }
    return getDigit(number: number, index: digitIndex).isMultiple(of: 2) ? -value : value
  }

  private static func getDigit(number: Int, index: Int) -> Int {
    Int(floor((Double(number) / pow(10, Double(index))).truncatingRemainder(dividingBy: 10)))
  }
}

#Preview {
  MarbleAvatarView(seed: "Maria Mitchell", size: 120)
    .padding()
    .background(Color(hex: "#121212"))
}
