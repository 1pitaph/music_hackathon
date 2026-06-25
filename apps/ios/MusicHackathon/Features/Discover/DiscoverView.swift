import SwiftUI

struct DiscoverView: View {
  @Environment(PlaybackController.self) private var playbackController
  @Environment(RadioStationController.self) private var radioStation
  @Environment(AppleMusicLibraryStore.self) private var appleMusicLibrary
  @Environment(DiscoverStationStore.self) private var discoverStationStore

  @State private var currentIndex = 0
  @State private var favoritedIDs: Set<String> = []
  @State private var expandedStationID: String?
  @State private var activeStationID: String?
  @State private var presentedSheet: DiscoverSheet?
  @State private var searchText = ""

  var body: some View {
    ZStack {
      ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 26) {
          discoverContent
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 36)
      }
      .refreshable {
        await discoverStationStore.refresh()
      }
    }
    .sheet(item: $presentedSheet) { sheet in
      switch sheet {
      case .publish:
        DiscoverPublishSheet()
          .presentationDetents([.large])
          .presentationDragIndicator(.visible)
      }
    }
    .task {
      await discoverStationStore.loadIfNeeded()
      await discoverStationStore.loadNextPageIfNeeded(currentIndex: safeCurrentIndex)
    }
    .animation(.spring(response: 0.35, dampingFraction: 0.82), value: activeStationID)
    .onChange(of: stationIDs) { _, _ in
      normalizeSelectionForAvailableStations()
    }
    .navigationTitle(L10n.tr("tab.discover"))
    .toolbarTitleDisplayMode(.inlineLarge)
    .searchable(text: $searchText, placement: .toolbar, prompt: L10n.tr("common.search"))
    .minimizedSearchToolbar()
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          presentedSheet = .publish
        } label: {
          Image(systemName: "plus")
        }
        .accessibilityLabel(L10n.tr("discover.publish.accessibilityLabel"))
      }
    }
  }

  private var stations: [DiscoverStation] {
    if !discoverStationStore.stations.isEmpty {
      return discoverStationStore.stations
    }
    return discoverStationStore.locallyRecoveredStations
  }

  private var isShowingLocalRecovery: Bool {
    discoverStationStore.stations.isEmpty && !discoverStationStore.locallyRecoveredStations.isEmpty
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

  @ViewBuilder
  private var discoverContent: some View {
    if stations.isEmpty {
      emptyOrFailedContent
    } else {
      if isShowingLocalRecovery {
        DiscoverFeedRecoveryBanner()
      }

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
  }

  @ViewBuilder
  private var emptyOrFailedContent: some View {
    switch discoverStationStore.state {
    case .idle, .loading:
      DiscoverFeedStatusPanel(
        systemImage: "dot.radiowaves.left.and.right",
        title: L10n.tr("discover.feed.loading.title"),
        message: L10n.tr("discover.feed.loading.message")
      )
    case .empty, .loaded:
      DiscoverFeedStatusPanel(
        systemImage: "antenna.radiowaves.left.and.right",
        title: L10n.tr("discover.feed.empty.title"),
        message: L10n.tr("discover.feed.empty.message"),
        actionTitle: L10n.tr("discover.publish.title")
      ) {
        presentedSheet = .publish
      }
    case let .failed(message):
      DiscoverFeedStatusPanel(
        systemImage: "wifi.exclamationmark",
        title: L10n.tr("discover.feed.failed.title"),
        message: message,
        actionTitle: L10n.tr("common.retry")
      ) {
        Task {
          await discoverStationStore.refresh()
        }
      }
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
    loadNextPageIfNeeded()
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
    guard !stations.isEmpty else {
      currentIndex = 0
      activeStationID = nil
      expandedStationID = nil
      return
    }

    currentIndex = safeCurrentIndex

    if let activeStationID,
       !stations.contains(where: { $0.id == activeStationID }) {
      self.activeStationID = nil
    }

    loadNextPageIfNeeded()
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

  private func loadNextPageIfNeeded() {
    Task {
      await discoverStationStore.loadNextPageIfNeeded(currentIndex: safeCurrentIndex)
    }
  }
}

private enum DiscoverSheet: Identifiable {
  case publish

  var id: String {
    switch self {
    case .publish:
      "publish"
    }
  }
}

private struct MinimizedSearchToolbarModifier: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      content.searchToolbarBehavior(.minimize)
    } else {
      content
    }
  }
}

private extension View {
  func minimizedSearchToolbar() -> some View {
    modifier(MinimizedSearchToolbarModifier())
  }
}

private struct DiscoverFeedRecoveryBanner: View {
  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "externaldrive.fill.badge.checkmark")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(Color(hex: "#7BCFA6"))
        .frame(width: 24)

      Text(L10n.tr("discover.feed.localRecovery"))
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.72))
        .lineLimit(2)

      Spacer(minLength: 0)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(.white.opacity(0.08), lineWidth: 1)
    }
  }
}

private struct DiscoverFeedStatusPanel: View {
  let systemImage: String
  let title: String
  let message: String
  var actionTitle: String?
  var action: (() -> Void)?

  var body: some View {
    VStack(spacing: 18) {
      Image(systemName: systemImage)
        .font(.system(size: 34, weight: .semibold))
        .foregroundStyle(Color(hex: "#7BCFA6"))
        .frame(width: 64, height: 64)
        .background(.white.opacity(0.08), in: Circle())

      VStack(spacing: 7) {
        Text(title)
          .font(.system(size: 20, weight: .bold, design: .rounded))
          .foregroundStyle(.white)
          .multilineTextAlignment(.center)

        Text(message)
          .font(.system(size: 14, weight: .medium, design: .rounded))
          .foregroundStyle(.white.opacity(0.54))
          .lineSpacing(3)
          .multilineTextAlignment(.center)
      }

      if let actionTitle, let action {
        Button(action: action) {
          Text(actionTitle)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.black.opacity(0.86))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color(hex: "#7BCFA6"), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
      }
    }
    .padding(22)
    .frame(maxWidth: .infinity)
    .frame(minHeight: 360, alignment: .center)
    .background(Color(hex: "#24211E").opacity(0.82), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(.white.opacity(0.1), lineWidth: 1)
    }
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

      ShareLink(
        item: station.shareURL,
        subject: Text(station.title),
        message: Text(L10n.tr("discover.share.message", station.hostName, station.title))
      ) {
        Label(L10n.tr("discover.share.title"), systemImage: "square.and.arrow.up")
          .font(.system(size: 14, weight: .bold, design: .rounded))
          .foregroundStyle(.white.opacity(0.84))
          .frame(maxWidth: .infinity)
          .frame(height: 42)
          .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(L10n.tr("discover.share.accessibilityLabel"))
    }
    .padding(.horizontal, 20)
    .padding(.top, 16)
    .padding(.bottom, 22)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(hex: "#1E1B18"))
  }
}

private struct DiscoverPublishSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(MusicAuthorizationService.self) private var musicAuthorization
  @Environment(AppleMusicLibraryStore.self) private var appleMusicLibrary
  @Environment(DiscoverStationStore.self) private var discoverStationStore
  @Environment(RadioStationController.self) private var radioStation

  @State private var selectedTrackIDs: [String] = []
  @State private var visibility: RadioStationVisibility = .public
  @State private var draft: DiscoverStationPublicationDraft?
  @State private var publishedStation: DiscoverStation?
  @State private var isGenerating = false
  @State private var isPublishing = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      content
        .navigationTitle(L10n.tr("discover.publish.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button(L10n.tr("common.close")) {
              dismiss()
            }
          }
        }
    }
    .preferredColorScheme(.dark)
    .task {
      await loadLibraryIfNeeded()
    }
    .onChange(of: selectedTrackIDs) { _, _ in
      draft = nil
      publishedStation = nil
      errorMessage = nil
    }
  }

  @ViewBuilder
  private var content: some View {
    if let publishedStation {
      publishedContent(station: publishedStation)
    } else {
      ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 18) {
          selectionHeader
          visibilityPicker

          if let draft {
            previewContent(draft: draft)
          } else {
            trackSelectionContent
          }

          if let errorMessage {
            Text(errorMessage)
              .font(.footnote)
              .foregroundStyle(Color(hex: "#F2A27F"))
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 28)
      }
      .background(Color(hex: "#151311"))
    }
  }

  private var selectionHeader: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(L10n.tr("discover.publish.selectionTitle"))
          .font(.system(size: 20, weight: .bold, design: .rounded))
          .foregroundStyle(.white)

        Text(L10n.tr("discover.publish.selectionCount", selectedTrackIDs.count))
          .font(.system(size: 13, weight: .semibold, design: .rounded))
          .foregroundStyle(.white.opacity(0.46))
      }

      Spacer()

      Button {
        Task {
          await generatePreview()
        }
      } label: {
        if isGenerating {
          ProgressView()
            .controlSize(.small)
            .frame(width: 42, height: 42)
        } else {
          Image(systemName: "sparkles")
            .font(.system(size: 18, weight: .bold))
            .frame(width: 42, height: 42)
        }
      }
      .buttonStyle(.plain)
      .foregroundStyle(canGenerate ? .white : .white.opacity(0.28))
      .background(.white.opacity(canGenerate ? 0.12 : 0.05), in: Circle())
      .disabled(!canGenerate || isGenerating)
      .accessibilityLabel(L10n.tr("discover.publish.generate"))
    }
  }

  private var visibilityPicker: some View {
    Picker(L10n.tr("discover.publish.visibility"), selection: $visibility) {
      ForEach(RadioStationVisibility.allCases) { visibility in
        Text(visibility.title).tag(visibility)
      }
    }
    .pickerStyle(.segmented)
  }

  @ViewBuilder
  private var trackSelectionContent: some View {
    if musicAuthorization.status != .authorized {
      VStack(spacing: 14) {
        Label(L10n.tr("library.connectAppleMusic"), systemImage: "person.badge.key")
          .font(.system(size: 15, weight: .semibold, design: .rounded))
          .foregroundStyle(.white.opacity(0.78))

        Button {
          Task {
            await musicAuthorization.requestAccess()
            await appleMusicLibrary.refresh(authorizationStatus: musicAuthorization.status)
          }
        } label: {
          Label(L10n.tr("appleMusic.requestAccess"), systemImage: "music.note.house")
            .frame(maxWidth: .infinity)
            .frame(height: 46)
        }
        .buttonStyle(.borderedProminent)
        .disabled(musicAuthorization.isRequestingAccess)
      }
      .padding(18)
      .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    } else if selectableTracks.isEmpty {
      VStack(spacing: 14) {
        Label(L10n.tr("discover.publish.emptyLibrary"), systemImage: "music.note.list")
          .font(.system(size: 15, weight: .semibold, design: .rounded))
          .foregroundStyle(.white.opacity(0.78))

        Button {
          Task {
            await appleMusicLibrary.refresh(authorizationStatus: musicAuthorization.status)
          }
        } label: {
          Label(L10n.tr("library.refreshPlaylists"), systemImage: "arrow.clockwise")
            .frame(maxWidth: .infinity)
            .frame(height: 46)
        }
        .buttonStyle(.bordered)
        .disabled(appleMusicLibrary.state.isLoading)
      }
      .padding(18)
      .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    } else {
      LazyVStack(spacing: 10) {
        ForEach(selectableTracks) { track in
          DiscoverPublishTrackRow(
            track: track,
            selectionIndex: selectionIndex(for: track),
            isDisabled: !isSelected(track) && selectedTrackIDs.count >= 5,
            onToggle: {
              toggleSelection(track)
            }
          )
        }
      }
    }
  }

  private func previewContent(draft: DiscoverStationPublicationDraft) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 6) {
        Text(draft.title)
          .font(.system(size: 22, weight: .bold, design: .rounded))
          .foregroundStyle(.white)
          .lineLimit(2)

        Text(draft.subtitle)
          .font(.system(size: 14, weight: .medium, design: .rounded))
          .foregroundStyle(.white.opacity(0.52))
          .lineLimit(3)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if draft.usedFallbackGeneration {
        Label(L10n.tr("discover.publish.generatedFallback"), systemImage: "exclamationmark.triangle")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(Color(hex: "#F2A27F"))
      }

      VStack(spacing: 10) {
        ForEach(draft.station.items.prefix(5)) { item in
          HStack(spacing: 10) {
            ArtworkImageView(resolution: ArtworkResolution(remoteURLs: [item.track.artworkURL])) {
              Color.white.opacity(0.08)
            }
            .frame(width: 38, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
              Text(item.track.title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

              Text(item.track.artist)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
            }

            Spacer()
          }
        }
      }
      .padding(12)
      .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

      HStack(spacing: 10) {
        Button {
          Task {
            await radioStation.loadLocalStation(draft.station, playImmediately: true)
          }
        } label: {
          Label(L10n.tr("discover.publish.previewPlay"), systemImage: "play.fill")
            .frame(maxWidth: .infinity)
            .frame(height: 46)
        }
        .buttonStyle(.bordered)

        Button {
          Task {
            await publishDraft()
          }
        } label: {
          if isPublishing {
            ProgressView()
              .frame(maxWidth: .infinity)
              .frame(height: 46)
          } else {
            Label(L10n.tr("discover.publish.publishAndShare"), systemImage: "paperplane.fill")
              .frame(maxWidth: .infinity)
              .frame(height: 46)
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(isPublishing)
      }
    }
    .padding(16)
    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func publishedContent(station: DiscoverStation) -> some View {
    VStack(spacing: 18) {
      Spacer(minLength: 24)

      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 48, weight: .bold))
        .foregroundStyle(Color(hex: "#7BCFA6"))

      VStack(spacing: 8) {
        Text(L10n.tr("discover.publish.successTitle"))
          .font(.system(size: 24, weight: .bold, design: .rounded))
          .foregroundStyle(.white)

        Text(station.title)
          .font(.system(size: 15, weight: .semibold, design: .rounded))
          .foregroundStyle(.white.opacity(0.58))
          .multilineTextAlignment(.center)
      }

      ShareLink(
        item: station.shareURL,
        subject: Text(station.title),
        message: Text(L10n.tr("discover.share.message", station.hostName, station.title))
      ) {
        Label(L10n.tr("discover.publish.shareNow"), systemImage: "square.and.arrow.up")
          .frame(maxWidth: .infinity)
          .frame(height: 48)
      }
      .buttonStyle(.borderedProminent)
      .padding(.horizontal, 20)

      Button(L10n.tr("common.close")) {
        dismiss()
      }
      .buttonStyle(.plain)
      .foregroundStyle(.white.opacity(0.62))

      Spacer()
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(hex: "#151311"))
  }

  private var selectableTracks: [Track] {
    let tracks = appleMusicLibrary.playlists.flatMap(\.tracks) + appleMusicLibrary.tracks
    var seen: Set<String> = []
    var result: [Track] = []

    for track in tracks where track.isPlayable && track.hasRealArtwork {
      guard !seen.contains(track.radioIdentity) else { continue }
      seen.insert(track.radioIdentity)
      result.append(track)
    }

    return result
  }

  private var selectedTracks: [Track] {
    let tracksByID = Dictionary(uniqueKeysWithValues: selectableTracks.map { ($0.radioIdentity, $0) })
    return selectedTrackIDs.compactMap { tracksByID[$0] }
  }

  private var canGenerate: Bool {
    selectedTrackIDs.count == 5 && selectedTracks.count == 5 && !isGenerating
  }

  private func isSelected(_ track: Track) -> Bool {
    selectedTrackIDs.contains(track.radioIdentity)
  }

  private func selectionIndex(for track: Track) -> Int? {
    selectedTrackIDs.firstIndex(of: track.radioIdentity).map { $0 + 1 }
  }

  private func toggleSelection(_ track: Track) {
    if let index = selectedTrackIDs.firstIndex(of: track.radioIdentity) {
      selectedTrackIDs.remove(at: index)
      return
    }

    guard selectedTrackIDs.count < 5 else { return }
    selectedTrackIDs.append(track.radioIdentity)
  }

  private func loadLibraryIfNeeded() async {
    await musicAuthorization.refreshAccessState()
    await appleMusicLibrary.loadIfNeeded(authorizationStatus: musicAuthorization.status)
  }

  private func generatePreview() async {
    guard canGenerate else { return }
    isGenerating = true
    errorMessage = nil
    defer { isGenerating = false }

    let ownerID = DiscoverPublisherIdentity.ownerID()
    let ownerDisplayName = DiscoverPublisherIdentity.displayName()
    draft = await discoverStationStore.generatePublicationDraft(
      seedTracks: selectedTracks,
      visibility: visibility,
      ownerID: ownerID,
      ownerDisplayName: ownerDisplayName
    )
  }

  private func publishDraft() async {
    guard var draft else { return }
    isPublishing = true
    errorMessage = nil
    defer { isPublishing = false }

    draft.visibility = visibility
    do {
      publishedStation = try await discoverStationStore.publish(draft)
    } catch {
      errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
  }
}

private struct DiscoverPublishTrackRow: View {
  let track: Track
  let selectionIndex: Int?
  let isDisabled: Bool
  let onToggle: () -> Void

  var body: some View {
    Button(action: onToggle) {
      HStack(spacing: 12) {
        ArtworkImageView(resolution: ArtworkResolution(remoteURLs: [track.artworkURL])) {
          Color.white.opacity(0.08)
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

        VStack(alignment: .leading, spacing: 4) {
          Text(track.title)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(isDisabled ? 0.35 : 0.92))
            .lineLimit(1)

          Text("\(track.artist) - \(track.album)")
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(isDisabled ? 0.24 : 0.44))
            .lineLimit(1)
        }

        Spacer()

        if let selectionIndex {
          Text("\(selectionIndex)")
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundStyle(.black.opacity(0.86))
            .frame(width: 28, height: 28)
            .background(Color(hex: "#7BCFA6"), in: Circle())
        } else {
          Image(systemName: "plus.circle")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.white.opacity(isDisabled ? 0.2 : 0.5))
        }
      }
      .padding(12)
      .background(.white.opacity(selectionIndex == nil ? 0.055 : 0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(isDisabled)
  }
}

#Preview {
  let playbackController = PlaybackController()
  DiscoverView()
    .environment(playbackController)
    .environment(RadioStationController(playbackController: playbackController))
    .environment(MusicAuthorizationService())
    .environment(AppleMusicLibraryStore())
    .environment(DiscoverStationStore())
    .environment(ImageAssetStore())
    .environment(ArtworkAnalysisStore())
}
