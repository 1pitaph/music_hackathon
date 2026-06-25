import SwiftUI

struct DiscoverView: View {
  @Environment(PlaybackController.self) private var playbackController
  @Environment(RadioStationController.self) private var radioStation
  @Environment(AppleMusicLibraryStore.self) private var appleMusicLibrary

  @State private var currentIndex = 0
  @State private var favoritedIDs: Set<String> = []
  @State private var expandedStationID: String?
  @State private var activeStationID: String?

  var body: some View {
    ZStack {
      ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 26) {
          header

          DiscoverCardStack(
            stations: stations,
            currentIndex: currentIndex,
            isPlaying: isCurrentCardPlaying,
            favoritedIDs: favoritedIDs,
            expandedStationID: expandedStationID,
            onPlayToggle: toggleCurrentStationPlayback,
            onToggleFavorite: toggleFavorite,
            onToggleExpanded: toggleExpanded,
            onPreviousCard: showPreviousCard,
            onNextCard: showNextCard
          )
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 36)
      }
    }
    .animation(.spring(response: 0.35, dampingFraction: 0.82), value: activeStationID)
    .onChange(of: stationIDs) { _, _ in
      normalizeSelectionForAvailableStations()
    }
  }

  private var stations: [DiscoverStation] {
    appleMusicLibrary.stations.isEmpty ? DiscoverStation.mockStations : appleMusicLibrary.stations
  }

  private var stationIDs: [String] {
    stations.map(\.id)
  }

  private var currentStation: DiscoverStation {
    stations[safeCurrentIndex]
  }

  private var safeCurrentIndex: Int {
    guard !stations.isEmpty else { return 0 }
    return min(max(currentIndex, 0), stations.count - 1)
  }

  private var isCurrentCardPlaying: Bool {
    activeStationID == currentStation.id && playbackController.state == .playing
  }

  private var header: some View {
    HStack {
      Button {} label: {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 20, weight: .semibold))
          .frame(width: 44, height: 44)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.white.opacity(0.58))
      .accessibilityLabel(L10n.tr("common.search"))

      Spacer()

      Text(L10n.tr("tab.discover"))
        .font(.system(size: 30, weight: .bold, design: .rounded))
        .foregroundStyle(.white)

      Spacer()

      ShareLink(
        item: currentStation.shareURL,
        subject: Text(currentStation.title),
        message: Text(L10n.tr("discover.share.message", currentStation.hostName, currentStation.title))
      ) {
        Image(systemName: "square.and.arrow.up")
          .font(.system(size: 20, weight: .semibold))
          .frame(width: 44, height: 44)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.white.opacity(0.72))
      .accessibilityLabel(L10n.tr("discover.share.accessibilityLabel"))
    }
  }

  private func showPreviousCard() {
    guard !stations.isEmpty else { return }
    currentIndex = (currentIndex - 1 + stations.count) % stations.count
    expandedStationID = nil
  }

  private func showNextCard() {
    guard !stations.isEmpty else { return }
    currentIndex = (currentIndex + 1) % stations.count
    expandedStationID = nil
  }

  private func toggleCurrentStationPlayback() {
    if activeStationID == currentStation.id, playbackController.state == .playing || playbackController.state == .paused {
      playbackController.togglePlayback()
    } else {
      playStation(currentStation)
    }
  }

  private func playStation(_ station: DiscoverStation) {
    activeStationID = station.id
    if let index = stations.firstIndex(where: { $0.id == station.id }) {
      currentIndex = index
    }

    Task {
      await radioStation.loadLocalStation(station.radioStation(), playImmediately: true)
    }
  }

  private func normalizeSelectionForAvailableStations() {
    guard !stations.isEmpty else { return }

    currentIndex = safeCurrentIndex

    if let activeStationID,
       !stations.contains(where: { $0.id == activeStationID }) {
      self.activeStationID = nil
    }
  }

  private func toggleFavorite(_ station: DiscoverStation) {
    if favoritedIDs.contains(station.id) {
      favoritedIDs.remove(station.id)
    } else {
      favoritedIDs.insert(station.id)
    }
  }

  private func toggleExpanded(_ station: DiscoverStation) {
    expandedStationID = expandedStationID == station.id ? nil : station.id
  }
}

private struct DiscoverCardStack: View {
  let stations: [DiscoverStation]
  let currentIndex: Int
  let isPlaying: Bool
  let favoritedIDs: Set<String>
  let expandedStationID: String?
  let onPlayToggle: () -> Void
  let onToggleFavorite: (DiscoverStation) -> Void
  let onToggleExpanded: (DiscoverStation) -> Void
  let onPreviousCard: () -> Void
  let onNextCard: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var dragTranslation: CGSize = .zero
  @State private var committedDirection: SwipeDirection?
  @State private var isAnimatingSwipe = false
  @State private var isTrackingHorizontalDrag = false
  @State private var rejectedVerticalDrag = false
  @State private var swipeToken = 0

  var body: some View {
    if stations.isEmpty {
      EmptyView()
        .frame(height: collapsedHeight)
    } else {
      GeometryReader { proxy in
        let safeIndex = wrappedIndex(currentIndex, count: stations.count)
        let width = max(proxy.size.width - 8, 1)
        let activeStation = stations[safeIndex]
        let direction = committedDirection ?? SwipeDirection(translation: dragTranslation.width)
        let progress = swipeProgress(width: proxy.size.width)
        let sideDirections = visibleSideDirections(activeDirection: direction, currentIndex: safeIndex)

        ZStack {
          ForEach(sideDirections, id: \.self) { sideDirection in
            let sideIndex = adjacentIndex(from: safeIndex, direction: sideDirection)

            backCard(
              station: stations[sideIndex],
              direction: sideDirection,
              isTarget: direction == sideDirection,
              width: width,
              progress: progress
            )
          }

          activeCard(
            station: activeStation,
            direction: direction,
            progress: progress,
            width: width,
            proxySize: proxy.size
          )
        }
        .frame(width: proxy.size.width, height: proxy.size.height)
      }
      .frame(height: stackHeight)
      .animation(.spring(response: 0.32, dampingFraction: 0.88), value: currentIndex)
      .animation(.spring(response: 0.32, dampingFraction: 0.88), value: expandedStationID)
      .onChange(of: currentIndex) { _, _ in
        resetSwipeState(invalidatesPendingSwipe: true)
      }
    }
  }

  private var stackHeight: CGFloat {
    guard !stations.isEmpty else { return collapsedHeight }
    let safeIndex = wrappedIndex(currentIndex, count: stations.count)
    return expandedStationID == stations[safeIndex].id ? expandedHeight : collapsedHeight
  }

  private var snapBackAnimation: Animation {
    reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.32, dampingFraction: 0.82)
  }

  private var flyOutAnimation: Animation {
    reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.34, dampingFraction: 0.86)
  }

  private var flyOutDuration: TimeInterval {
    reduceMotion ? 0.18 : 0.28
  }

  private var collapsedHeight: CGFloat {
    548
  }

  private var expandedHeight: CGFloat {
    650
  }

  private func activeCard(
    station: DiscoverStation,
    direction: SwipeDirection?,
    progress: CGFloat,
    width: CGFloat,
    proxySize: CGSize
  ) -> some View {
    DiscoverStationCard(
      station: station,
      isActive: true,
      isPlaying: isPlaying,
      isFavorited: favoritedIDs.contains(station.id),
      isExpanded: expandedStationID == station.id,
      onPlayToggle: onPlayToggle,
      onToggleFavorite: {
        onToggleFavorite(station)
      },
      onToggleExpanded: {
        onToggleExpanded(station)
      }
    )
    .frame(width: width)
    .offset(x: dragTranslation.width, y: dragTranslation.height)
    .rotationEffect(.degrees(activeRotation(width: proxySize.width)), anchor: .bottom)
    .overlay(alignment: direction?.indicatorAlignment ?? .top) {
      if let direction {
        swipeIndicator(direction: direction, progress: progress)
      }
    }
    .contentShape(Rectangle())
    .zIndex(4)
    .simultaneousGesture(
      swipeGesture(width: proxySize.width, size: proxySize, activeStation: station)
    )
    .accessibilityAction(named: Text(L10n.tr("discover.card.previous"))) {
      commitSwipe(.right, size: proxySize, activeStation: station)
    }
    .accessibilityAction(named: Text(L10n.tr("discover.card.next"))) {
      commitSwipe(.left, size: proxySize, activeStation: station)
    }
  }

  private func backCard(
    station: DiscoverStation,
    direction: SwipeDirection,
    isTarget: Bool,
    width: CGFloat,
    progress: CGFloat
  ) -> some View {
    let targetProgress = isTarget ? progress : 0

    return DiscoverStationCard(
      station: station,
      isActive: false,
      isPlaying: false,
      isFavorited: favoritedIDs.contains(station.id),
      isExpanded: false,
      onPlayToggle: {},
      onToggleFavorite: {},
      onToggleExpanded: {}
    )
    .frame(width: width)
    .scaleEffect(backScale(progress: targetProgress))
    .rotationEffect(.degrees(direction.restingRotation * Double(1 - targetProgress)))
    .opacity(backOpacity(progress: targetProgress, isTarget: isTarget))
    .offset(
      x: direction.restingOffsetX * (1 - targetProgress),
      y: 22 * (1 - targetProgress)
    )
    .zIndex(isTarget ? 2 : 1)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func swipeIndicator(direction: SwipeDirection, progress: CGFloat) -> some View {
    Text(direction.label)
      .font(.system(size: reduceMotion ? 16 : 18, weight: .black, design: .rounded))
      .foregroundStyle(.white.opacity(0.92))
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .background(direction.tint.opacity(0.82), in: Capsule())
      .overlay {
        Capsule()
          .stroke(.white.opacity(0.22), lineWidth: 1)
      }
      .rotationEffect(.degrees(reduceMotion ? 0 : direction.indicatorRotation))
      .opacity(indicatorOpacity(progress: progress))
      .padding(.top, 26)
      .padding(direction.indicatorPaddingEdge, 24)
  }

  private func swipeGesture(width: CGFloat, size: CGSize, activeStation: DiscoverStation) -> some Gesture {
    DragGesture(minimumDistance: 12, coordinateSpace: .local)
      .onChanged { value in
        handleDragChanged(value)
      }
      .onEnded { value in
        handleDragEnded(value, width: width, size: size, activeStation: activeStation)
      }
  }

  private func handleDragChanged(_ value: DragGesture.Value) {
    guard !isAnimatingSwipe else { return }

    let horizontalDistance = abs(value.translation.width)
    let verticalDistance = abs(value.translation.height)

    if !isTrackingHorizontalDrag, !rejectedVerticalDrag {
      guard horizontalDistance > 6 || verticalDistance > 6 else { return }

      if horizontalDistance > max(12, verticalDistance * 1.18) {
        isTrackingHorizontalDrag = true
      } else if verticalDistance > horizontalDistance * 1.12 {
        rejectedVerticalDrag = true
      }
    }

    guard isTrackingHorizontalDrag else { return }

    dragTranslation = CGSize(
      width: value.translation.width,
      height: reduceMotion ? 0 : value.translation.height * 0.18
    )
  }

  private func handleDragEnded(
    _ value: DragGesture.Value,
    width: CGFloat,
    size: CGSize,
    activeStation: DiscoverStation
  ) {
    defer {
      isTrackingHorizontalDrag = false
      rejectedVerticalDrag = false
    }

    guard isTrackingHorizontalDrag else {
      resetDragOffset()
      return
    }

    let actualX = value.translation.width
    let predictedX = value.predictedEndTranslation.width
    let distanceThreshold = width * 0.26
    let predictionThreshold = width * 0.45

    if abs(actualX) > distanceThreshold || abs(predictedX) > predictionThreshold {
      let decisionX = abs(predictedX) > abs(actualX) ? predictedX : actualX
      let direction: SwipeDirection = decisionX < 0 ? .left : .right
      commitSwipe(direction, size: size, activeStation: activeStation)
    } else {
      resetDragOffset()
    }
  }

  private func commitSwipe(_ direction: SwipeDirection, size: CGSize, activeStation: DiscoverStation) {
    guard !isAnimatingSwipe else { return }

    isAnimatingSwipe = true
    committedDirection = direction
    swipeToken += 1
    let token = swipeToken

    if expandedStationID == activeStation.id {
      onToggleExpanded(activeStation)

      DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
        flyOut(direction, size: size, token: token)
      }
    } else {
      flyOut(direction, size: size, token: token)
    }
  }

  private func flyOut(_ direction: SwipeDirection, size: CGSize, token: Int) {
    guard token == swipeToken else { return }

    let targetWidth = max(size.width, 1) * 1.35
    let targetHeight = reduceMotion ? 0 : dragTranslation.height * 0.35

    withAnimation(flyOutAnimation) {
      dragTranslation = CGSize(
        width: direction.sign * targetWidth,
        height: targetHeight
      )
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + flyOutDuration) {
      finishSwipe(direction, token: token)
    }
  }

  private func finishSwipe(_ direction: SwipeDirection, token: Int) {
    guard token == swipeToken else { return }

    var transaction = Transaction()
    transaction.disablesAnimations = true

    withTransaction(transaction) {
      switch direction {
      case .left:
        onNextCard()
      case .right:
        onPreviousCard()
      }

      resetSwipeState()
    }
  }

  private func resetDragOffset() {
    withAnimation(snapBackAnimation) {
      dragTranslation = .zero
    }
  }

  private func resetSwipeState(invalidatesPendingSwipe: Bool = false) {
    if invalidatesPendingSwipe {
      swipeToken += 1
    }

    dragTranslation = .zero
    committedDirection = nil
    isAnimatingSwipe = false
    isTrackingHorizontalDrag = false
    rejectedVerticalDrag = false
  }

  private func activeRotation(width: CGFloat) -> Double {
    let limit = reduceMotion ? 4.0 : 12.0
    let multiplier = reduceMotion ? 4.0 : 11.0
    let rotation = Double(dragTranslation.width / max(width, 1)) * multiplier
    return min(max(rotation, -limit), limit)
  }

  private func swipeProgress(width: CGFloat) -> CGFloat {
    min(abs(dragTranslation.width) / max(width * 0.26, 1), 1)
  }

  private func backScale(progress: CGFloat) -> CGFloat {
    let lift = reduceMotion ? 0.04 : 0.08
    return 0.92 + progress * lift
  }

  private func backOpacity(progress: CGFloat, isTarget: Bool) -> Double {
    let base = isTarget ? 0.45 : 0.3
    return Double(base + progress * 0.55)
  }

  private func indicatorOpacity(progress: CGFloat) -> Double {
    let visibleProgress = max(progress - 0.12, 0) / 0.88
    return Double(min(visibleProgress, 1))
  }

  private func visibleSideDirections(activeDirection: SwipeDirection?, currentIndex: Int) -> [SwipeDirection] {
    guard stations.count > 1 else { return [] }

    let previousIndex = adjacentIndex(from: currentIndex, direction: .right)
    let nextIndex = adjacentIndex(from: currentIndex, direction: .left)

    if previousIndex == nextIndex {
      return [activeDirection ?? .left]
    }

    return [.right, .left]
  }

  private func adjacentIndex(from index: Int, direction: SwipeDirection) -> Int {
    wrappedIndex(index + direction.indexDelta, count: stations.count)
  }

  private func wrappedIndex(_ index: Int, count: Int) -> Int {
    guard count > 0 else { return 0 }
    return (index % count + count) % count
  }

  private enum SwipeDirection: Hashable {
    case left
    case right

    init?(translation: CGFloat) {
      if translation < -1 {
        self = .left
      } else if translation > 1 {
        self = .right
      } else {
        return nil
      }
    }

    var indexDelta: Int {
      switch self {
      case .left:
        return 1
      case .right:
        return -1
      }
    }

    var sign: CGFloat {
      switch self {
      case .left:
        return -1
      case .right:
        return 1
      }
    }

    var restingOffsetX: CGFloat {
      switch self {
      case .left:
        return 42
      case .right:
        return -42
      }
    }

    var restingRotation: Double {
      switch self {
      case .left:
        return 3
      case .right:
        return -3
      }
    }

    var label: String {
      switch self {
      case .left:
        return L10n.tr("discover.card.next")
      case .right:
        return L10n.tr("discover.card.previous")
      }
    }

    var tint: Color {
      switch self {
      case .left:
        return Color(hex: "#426D8F")
      case .right:
        return Color(hex: "#D9523A")
      }
    }

    var indicatorAlignment: Alignment {
      switch self {
      case .left:
        return .topTrailing
      case .right:
        return .topLeading
      }
    }

    var indicatorPaddingEdge: Edge.Set {
      switch self {
      case .left:
        return .trailing
      case .right:
        return .leading
      }
    }

    var indicatorRotation: Double {
      switch self {
      case .left:
        return 8
      case .right:
        return -8
      }
    }
  }

}

private struct DiscoverStationCard: View {
  let station: DiscoverStation
  let isActive: Bool
  let isPlaying: Bool
  let isFavorited: Bool
  let isExpanded: Bool
  let onPlayToggle: () -> Void
  let onToggleFavorite: () -> Void
  let onToggleExpanded: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      Button(action: onPlayToggle) {
        ZStack {
          stationArtwork

          Circle()
            .fill(.white.opacity(0.08))
            .frame(width: 210, height: 74)
            .scaleEffect(y: 0.42)
            .offset(y: -92)

          VStack(spacing: 10) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
              .font(.system(size: 36, weight: .black))
              .foregroundStyle(.white)
              .frame(width: 84, height: 84)
              .background(.black.opacity(0.28), in: Circle())
              .overlay {
                Circle()
                  .stroke(.white.opacity(0.18), lineWidth: 1)
              }

            Text(isPlaying ? L10n.tr("discover.card.onAir") : L10n.tr("discover.card.tapToTune"))
              .font(.system(size: 12, weight: .black, design: .rounded))
              .foregroundStyle(.white.opacity(0.7))
          }
        }
        .frame(height: 350)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(!isActive)
      .accessibilityLabel(isPlaying ? L10n.tr("discover.station.pauseAccessibility", station.title) : L10n.tr("discover.station.playAccessibility", station.title))

      VStack(spacing: 12) {
        HStack(spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            Text(station.title)
              .font(.system(size: 22, weight: .semibold, design: .rounded))
              .foregroundStyle(.white)
              .lineLimit(1)
              .minimumScaleFactor(0.7)

            Text(station.hostName)
              .font(.system(size: 15, weight: .medium, design: .rounded))
              .foregroundStyle(.white.opacity(0.58))
              .lineLimit(1)
          }

          Spacer()

          Button(action: onToggleFavorite) {
            Image(systemName: isFavorited ? "heart.fill" : "heart")
              .font(.system(size: 22, weight: .semibold))
              .foregroundStyle(isFavorited ? Color(hex: "#D9523A") : .white.opacity(0.34))
              .frame(width: 44, height: 44)
          }
          .buttonStyle(.plain)
          .disabled(!isActive)
          .accessibilityLabel(isFavorited ? L10n.tr("common.unfavorite") : L10n.tr("common.favorite"))
        }

        Text(station.briefIntro)
          .font(.system(size: 13, weight: .medium, design: .rounded))
          .foregroundStyle(.white.opacity(0.36))
          .frame(maxWidth: .infinity, alignment: .leading)
          .lineLimit(1)

        if isActive {
          Button(action: onToggleExpanded) {
            VStack(spacing: 9) {
              Capsule()
                .fill(.white.opacity(0.34))
                .frame(width: 36, height: 4)

              Text(isExpanded ? L10n.tr("common.collapseDetails") : L10n.tr("common.viewDetails"))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(isExpanded ? L10n.tr("common.collapseDetails") : L10n.tr("common.viewDetails"))
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 18)
      .padding(.bottom, isActive ? 0 : 18)
      .background(Color(hex: "#24211E").opacity(0.82))

      if isActive, isExpanded {
        DiscoverStationDrawer(station: station)
          .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(.white.opacity(isActive ? 0.14 : 0.06), lineWidth: 1)
    }
    .shadow(color: .black.opacity(isActive ? 0.48 : 0.2), radius: isActive ? 44 : 20, y: isActive ? 24 : 12)
    .accessibilityElement(children: .contain)
  }

  private var stationArtwork: some View {
    ArtworkImageView(resolution: artworkResolution, showsLoadingIndicator: false) {
      Color.clear
    }
    .overlay {
      LinearGradient(
        colors: [
          .black.opacity(0.08),
          .black.opacity(0.18),
          .black.opacity(0.42)
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    }
  }

  private var artworkResolution: ArtworkResolution {
    ArtworkResolution(remoteURLs: station.artworkURLs.map(Optional.some))
  }
}

private struct DiscoverStationDrawer: View {
  let station: DiscoverStation

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 8) {
        Text(L10n.tr("discover.station.about"))
          .font(.system(size: 13, weight: .bold, design: .rounded))
          .foregroundStyle(.white.opacity(0.48))

        Text(station.description)
          .font(.system(size: 14, weight: .medium, design: .rounded))
          .foregroundStyle(.white.opacity(0.84))
          .lineSpacing(3)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(spacing: 9) {
        ForEach(station.items.prefix(5)) { item in
          HStack(spacing: 10) {
            Image(systemName: "music.note.list")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(.white.opacity(0.38))
              .frame(width: 18)

            Text(item.track.title)
              .font(.system(size: 14, weight: .semibold, design: .rounded))
              .foregroundStyle(.white.opacity(0.88))
              .lineLimit(1)

            Spacer()
          }
        }
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 16)
    .padding(.bottom, 22)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(hex: "#1E1B18"))
  }
}

#Preview {
  let playbackController = PlaybackController()
  DiscoverView()
    .environment(playbackController)
    .environment(RadioStationController(playbackController: playbackController))
    .environment(MusicAuthorizationService())
    .environment(AppleMusicLibraryStore())
    .environment(ImageAssetStore())
    .environment(ArtworkAnalysisStore())
}
