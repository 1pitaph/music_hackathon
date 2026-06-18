import SpriteKit
import UIKit

final class IslandSceneCoordinator {
  var onSelectionChanged: ((UUID?) -> Void)?

  func selectIsland(id: UUID?) {
    DispatchQueue.main.async { [onSelectionChanged] in
      onSelectionChanged?(id)
    }
  }
}

final class IslandScene: SKScene {
  weak var coordinator: IslandSceneCoordinator?

  private let islands: [MusicIsland]
  private let worldNode = SKNode()
  private let cameraNode = SKCameraNode()
  private var islandNodes: [UUID: SKNode] = [:]
  private var selectedIslandID: UUID?
  private var initialTouchLocations: [UITouch: CGPoint] = [:]
  private var initialCameraPosition: CGPoint = .zero
  private var initialCameraScale: CGFloat = 1
  private var lastTapCandidate: CGPoint?

  private let minimumCameraScale: CGFloat = 0.65
  private let maximumCameraScale: CGFloat = 2.4

  init(islands: [MusicIsland]) {
    self.islands = islands
    super.init(size: CGSize(width: 1200, height: 1800))
    scaleMode = .resizeFill
    backgroundColor = IslandScenePalette.background
    configureScene()
  }

  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func didMove(to view: SKView) {
    view.isMultipleTouchEnabled = true
    view.backgroundColor = IslandScenePalette.background
    view.allowsTransparency = false

    if worldNode.parent == nil {
      configureScene()
    }
  }

  func zoomIn() {
    setCameraScale(cameraNode.xScale * 0.84)
  }

  func zoomOut() {
    setCameraScale(cameraNode.xScale * 1.18)
  }

  func resetCamera() {
    let move = SKAction.move(to: .zero, duration: 0.28)
    move.timingMode = .easeOut
    let scale = SKAction.scale(to: 1, duration: 0.28)
    scale.timingMode = .easeOut
    cameraNode.run(.group([move, scale]))
  }

  func clearSelection() {
    updateSelection(nil)
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let view else { return }

    for touch in touches {
      let viewLocation = touch.location(in: view)
      guard !isChromeTouch(viewLocation, in: view) else { continue }
      initialTouchLocations[touch] = viewLocation
    }

    guard !initialTouchLocations.isEmpty else {
      lastTapCandidate = nil
      return
    }

    initialCameraPosition = cameraNode.position
    initialCameraScale = cameraNode.xScale
    lastTapCandidate = initialTouchLocations.count == 1 ? touches.first?.location(in: self) : nil
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let view else { return }
    let activeTouches = event?.allTouches ?? touches

    if activeTouches.count >= 2 {
      updatePinchZoom(with: Array(activeTouches), in: view)
      lastTapCandidate = nil
    } else if let touch = activeTouches.first, let start = initialTouchLocations[touch] {
      let current = touch.location(in: view)
      let delta = CGPoint(
        x: (current.x - start.x) * cameraNode.xScale,
        y: -(current.y - start.y) * cameraNode.yScale
      )
      cameraNode.position = CGPoint(
        x: initialCameraPosition.x - delta.x,
        y: initialCameraPosition.y - delta.y
      )

      if hypot(current.x - start.x, current.y - start.y) > 8 {
        lastTapCandidate = nil
      }
    }
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    defer {
      touches.forEach { initialTouchLocations[$0] = nil }
      if initialTouchLocations.isEmpty {
        lastTapCandidate = nil
      }
    }

    guard
      let candidate = lastTapCandidate,
      touches.count == 1
    else {
      return
    }

    selectIsland(at: candidate)
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    touches.forEach { initialTouchLocations[$0] = nil }
    lastTapCandidate = nil
  }

  private func configureScene() {
    addChild(worldNode)
    addChild(cameraNode)
    camera = cameraNode
    cameraNode.position = .zero
    cameraNode.setScale(1)

    addBackgroundTexture()
    addIslandNodes()
  }

  private func addBackgroundTexture() {
    let mapBounds = CGRect(x: -960, y: -1180, width: 1920, height: 2360)
    let base = SKShapeNode(rect: mapBounds)
    base.fillColor = IslandScenePalette.background
    base.strokeColor = .clear
    base.zPosition = -20
    worldNode.addChild(base)

    for offset in stride(from: -1500, through: 1500, by: 58) {
      let path = CGMutablePath()
      path.move(to: CGPoint(x: CGFloat(offset) - 900, y: -1200))
      path.addLine(to: CGPoint(x: CGFloat(offset) + 900, y: 1200))

      let line = SKShapeNode(path: path)
      line.strokeColor = UIColor(red: 0.37, green: 0.50, blue: 0.45, alpha: 0.10)
      line.lineWidth = 1
      line.zPosition = -18
      worldNode.addChild(line)
    }

    for offset in stride(from: -900, through: 900, by: 240) {
      let path = CGMutablePath()
      path.move(to: CGPoint(x: -1100, y: CGFloat(offset)))
      path.addCurve(
        to: CGPoint(x: 1100, y: CGFloat(offset) + 70),
        control1: CGPoint(x: -420, y: CGFloat(offset) + 150),
        control2: CGPoint(x: 360, y: CGFloat(offset) - 120)
      )

      let road = SKShapeNode(path: path)
      road.strokeColor = IslandScenePalette.road
      road.lineWidth = 26
      road.lineCap = .round
      road.zPosition = -12
      worldNode.addChild(road)
    }
  }

  private func addIslandNodes() {
    for island in islands {
      let container = SKNode()
      container.position = island.center
      container.name = nodeName(for: island.id)
      container.zPosition = CGFloat(island.importance)

      let islandPath = makeClosedPath(points: island.points)
      let fill = SKShapeNode(path: islandPath)
      fill.fillColor = fillColor(for: island.style.palette)
      fill.strokeColor = strokeColor(for: island)
      fill.lineWidth = island.importance >= 5 ? 2.2 : 1.4
      fill.userData = ["baseLineWidth": fill.lineWidth]
      fill.lineJoin = .round
      fill.glowWidth = island.importance >= 5 ? 1.6 : 0
      fill.name = container.name
      container.addChild(fill)

      addPattern(for: island, to: container, clippedBy: islandPath)

      if island.importance >= 4 {
        addLabel(for: island, to: container)
      } else if island.importance == 3 {
        addIcon(for: island, to: container)
      }

      islandNodes[island.id] = container
      worldNode.addChild(container)
    }
  }

  private func addPattern(for island: MusicIsland, to container: SKNode, clippedBy path: CGPath) {
    let crop = SKCropNode()
    let mask = SKShapeNode(path: path)
    mask.fillColor = .white
    mask.strokeColor = .clear
    crop.maskNode = mask
    crop.zPosition = 1

    switch island.style.pattern {
    case .diagonal, .crosshatch:
      addHatchLines(to: crop, radius: island.radius, mirrored: false)
      if island.style.pattern == .crosshatch {
        addHatchLines(to: crop, radius: island.radius, mirrored: true)
      }
    case .dots:
      addDots(to: crop, radius: island.radius)
    case .quiet:
      break
    }

    container.addChild(crop)
  }

  private func addHatchLines(to crop: SKCropNode, radius: CGFloat, mirrored: Bool) {
    let extent = radius * 1.75
    let step: CGFloat = 18
    for offset in stride(from: -extent * 2, through: extent * 2, by: step) {
      let path = CGMutablePath()
      let start = mirrored
        ? CGPoint(x: -extent, y: offset + extent)
        : CGPoint(x: -extent, y: offset - extent)
      let end = mirrored
        ? CGPoint(x: extent, y: offset - extent)
        : CGPoint(x: extent, y: offset + extent)
      path.move(to: start)
      path.addLine(to: end)

      let line = SKShapeNode(path: path)
      line.strokeColor = IslandScenePalette.pattern
      line.lineWidth = 1
      crop.addChild(line)
    }
  }

  private func addDots(to crop: SKCropNode, radius: CGFloat) {
    let step: CGFloat = 24
    for x in stride(from: -radius * 1.4, through: radius * 1.4, by: step) {
      for y in stride(from: -radius * 1.4, through: radius * 1.4, by: step) {
        let dot = SKShapeNode(circleOfRadius: 2.1)
        dot.position = CGPoint(x: x, y: y)
        dot.fillColor = IslandScenePalette.pattern
        dot.strokeColor = .clear
        crop.addChild(dot)
      }
    }
  }

  private func addLabel(for island: MusicIsland, to container: SKNode) {
    addIcon(for: island, to: container)

    let title = SKLabelNode(text: island.title)
    title.fontName = "AvenirNext-DemiBold"
    title.fontSize = 24
    title.fontColor = IslandScenePalette.text
    title.verticalAlignmentMode = .center
    title.position = CGPoint(x: 0, y: -8)
    title.zPosition = 4
    container.addChild(title)

    let subtitle = SKLabelNode(text: island.mood)
    subtitle.fontName = "AvenirNext-Medium"
    subtitle.fontSize = 13
    subtitle.fontColor = IslandScenePalette.secondaryText
    subtitle.verticalAlignmentMode = .center
    subtitle.position = CGPoint(x: 0, y: -34)
    subtitle.zPosition = 4
    container.addChild(subtitle)
  }

  private func addIcon(for island: MusicIsland, to container: SKNode) {
    let badge = SKShapeNode(circleOfRadius: island.importance >= 5 ? 18 : 13)
    badge.position = CGPoint(x: 0, y: island.importance >= 5 ? 31 : 0)
    badge.fillColor = .white.withAlphaComponent(0.72)
    badge.strokeColor = IslandScenePalette.deepGreen.withAlphaComponent(0.52)
    badge.lineWidth = 1.4
    badge.zPosition = 3
    container.addChild(badge)

    let note = SKLabelNode(text: "♪")
    note.fontName = "AvenirNext-Bold"
    note.fontSize = island.importance >= 5 ? 18 : 12
    note.fontColor = IslandScenePalette.deepGreen
    note.verticalAlignmentMode = .center
    note.horizontalAlignmentMode = .center
    note.position = badge.position
    note.zPosition = 4
    container.addChild(note)
  }

  private func selectIsland(at scenePoint: CGPoint) {
    let candidates = nodes(at: scenePoint)

    guard
      let islandNode = candidates
        .compactMap({ node in islandID(for: node) })
        .first
    else {
      updateSelection(nil)
      return
    }

    updateSelection(islandNode)
  }

  private func updateSelection(_ islandID: UUID?) {
    guard selectedIslandID != islandID else { return }

    if let selectedIslandID, let previous = islandNodes[selectedIslandID] {
      previous.removeAction(forKey: "selection")
      previous.run(.scale(to: 1, duration: 0.16), withKey: "selection")
      setStrokeColor(for: previous, selected: false)
    }

    selectedIslandID = islandID
    coordinator?.selectIsland(id: islandID)

    if let islandID, let selected = islandNodes[islandID] {
      selected.removeAction(forKey: "selection")
      let scale = SKAction.scale(to: 1.06, duration: 0.16)
      scale.timingMode = .easeOut
      selected.run(scale, withKey: "selection")
      setStrokeColor(for: selected, selected: true)
    }
  }

  private func setStrokeColor(for container: SKNode, selected: Bool) {
    for child in container.children {
      guard
        let shape = child as? SKShapeNode,
        shape.name?.hasPrefix("island-") == true
      else {
        continue
      }

      let baseLineWidth = shape.userData?["baseLineWidth"] as? CGFloat ?? 1.4
      shape.strokeColor = selected ? IslandScenePalette.selection : IslandScenePalette.deepGreen.withAlphaComponent(0.50)
      shape.lineWidth = selected ? 3.2 : baseLineWidth
    }
  }

  private func updatePinchZoom(with touches: [UITouch], in view: SKView) {
    guard touches.count >= 2 else { return }

    let first = touches[0]
    let second = touches[1]
    guard
      let firstStart = initialTouchLocations[first],
      let secondStart = initialTouchLocations[second]
    else {
      return
    }

    let startDistance = hypot(firstStart.x - secondStart.x, firstStart.y - secondStart.y)
    let firstCurrent = first.location(in: view)
    let secondCurrent = second.location(in: view)
    let currentDistance = hypot(firstCurrent.x - secondCurrent.x, firstCurrent.y - secondCurrent.y)

    guard startDistance > 0 else { return }
    setCameraScale(initialCameraScale * startDistance / currentDistance)
  }

  private func setCameraScale(_ scale: CGFloat) {
    let clamped = min(max(scale, minimumCameraScale), maximumCameraScale)
    cameraNode.setScale(clamped)
  }

  private func isChromeTouch(_ point: CGPoint, in view: SKView) -> Bool {
    point.y < 168 || point.y > view.bounds.height - 132 || point.x > view.bounds.width - 88
  }

  private func makeClosedPath(points: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    guard let first = points.first else { return path }
    path.move(to: first)
    points.dropFirst().forEach { path.addLine(to: $0) }
    path.closeSubpath()
    return path
  }

  private func nodeName(for id: UUID) -> String {
    "island-\(id.uuidString)"
  }

  private func islandID(for node: SKNode) -> UUID? {
    var current: SKNode? = node
    while let node = current {
      if let name = node.name, name.hasPrefix("island-") {
        return UUID(uuidString: String(name.dropFirst("island-".count)))
      }
      current = node.parent
    }
    return nil
  }

  private func fillColor(for palette: MusicIslandPalette) -> UIColor {
    switch palette {
    case .mint:
      UIColor(red: 0.80, green: 0.93, blue: 0.84, alpha: 0.96)
    case .cream:
      UIColor(red: 0.95, green: 0.92, blue: 0.76, alpha: 0.96)
    case .sage:
      UIColor(red: 0.76, green: 0.87, blue: 0.76, alpha: 0.96)
    case .linen:
      UIColor(red: 0.92, green: 0.86, blue: 0.72, alpha: 0.95)
    case .blueMist:
      UIColor(red: 0.76, green: 0.90, blue: 0.91, alpha: 0.95)
    }
  }

  private func strokeColor(for island: MusicIsland) -> UIColor {
    island.importance >= 5 ? IslandScenePalette.deepGreen : IslandScenePalette.deepGreen.withAlphaComponent(0.50)
  }
}

private enum IslandScenePalette {
  static let background = UIColor(red: 0.91, green: 0.97, blue: 0.92, alpha: 1)
  static let road = UIColor(red: 0.99, green: 1.00, blue: 0.95, alpha: 0.94)
  static let pattern = UIColor(red: 0.12, green: 0.27, blue: 0.23, alpha: 0.25)
  static let deepGreen = UIColor(red: 0.04, green: 0.25, blue: 0.17, alpha: 1)
  static let selection = UIColor(red: 0.06, green: 0.48, blue: 0.26, alpha: 1)
  static let text = UIColor(red: 0.04, green: 0.16, blue: 0.13, alpha: 1)
  static let secondaryText = UIColor(red: 0.23, green: 0.36, blue: 0.31, alpha: 0.78)
}
