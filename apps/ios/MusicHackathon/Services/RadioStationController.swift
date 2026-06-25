import Foundation
import Observation

private enum RadioStationArtworkError: LocalizedError {
  case emptyQueue

  var errorDescription: String? {
    L10n.tr("radio.error.noArtworkTracks")
  }
}

private enum RadioTransitionPlaybackStyle {
  case standalone
  case overlay
}

private struct PendingRadioTransition {
  let fromItem: RadioQueueItem
  let toItem: RadioQueueItem
  let speech: RadioSpeechPlaybackSegment
  let reason: RadioAdvanceReason
  var didStartNextTrack = false
}

private extension RadioTransitionPlaybackStyle {
  var diagnosticValue: String {
    switch self {
    case .standalone:
      "standalone"
    case .overlay:
      "overlay"
    }
  }
}

@MainActor
@Observable
final class RadioStationController {
  var station: RadioStation?
  var queue: [RadioQueueItem] = []
  var currentItem: RadioQueueItem?
  var stationTitle = L10n.tr("radio.defaultTitle")
  var stationIntro = L10n.tr("radio.defaultIntro")
  var isLoadingStation = false
  var isExtendingStation = false
  var errorMessage: String?
  var extensionErrorMessage: String?
  var memorySummaryText = L10n.tr("radio.memory.ready")
  var memoryEventCount = 0
  var speechVoiceCatalog: RadioSpeechVoiceCatalog?
  var isLoadingSpeechVoices = false
  var speechVoicesErrorMessage: String?
  let prefetchThreshold = 2
  let batchSize = 6

  @ObservationIgnored private let playbackController: any RadioPlaybackControlling
  @ObservationIgnored private let stationClient: any RadioStationFetching
  @ObservationIgnored private let memoryStore: any RadioMemoryStoring
  @ObservationIgnored private let artworkEnricher: any TrackArtworkEnriching
  @ObservationIgnored private let diagnostics: DiagnosticsStore?
  @ObservationIgnored private let hostSpeakerIDProvider: () -> String?
  @ObservationIgnored private let speechLanguageProvider: () -> RadioSpeechLanguage
  @ObservationIgnored private let libraryTrackProvider: @MainActor () -> [Track]
  @ObservationIgnored private var history: [RadioQueueItem] = []
  @ObservationIgnored private var hasPlayedStationIntro = false
  @ObservationIgnored private var stationSessionID: String?
  @ObservationIgnored private var continuationCursor: String?
  @ObservationIgnored private var stationGenerationID = UUID()
  @ObservationIgnored private var extensionTask: Task<Bool, Never>?
  @ObservationIgnored private var extensionTaskID: UUID?
  @ObservationIgnored private var pendingTransition: PendingRadioTransition?

  init(
    playbackController: any RadioPlaybackControlling,
    stationClient: any RadioStationFetching = RadioStationClient(),
    memoryStore: any RadioMemoryStoring = RadioMemoryStore(),
    artworkEnricher: any TrackArtworkEnriching = AppleMusicCatalogService(),
    diagnostics: DiagnosticsStore? = nil,
    hostSpeakerIDProvider: @escaping () -> String? = { RadioHostVoiceSettings.selectedSpeakerID() },
    speechLanguageProvider: @escaping () -> RadioSpeechLanguage = { RadioSpeechLanguage.stored() },
    libraryTrackProvider: @escaping @MainActor () -> [Track] = { [] }
  ) {
    self.playbackController = playbackController
    self.stationClient = stationClient
    self.memoryStore = memoryStore
    self.artworkEnricher = artworkEnricher
    self.diagnostics = diagnostics
    self.hostSpeakerIDProvider = hostSpeakerIDProvider
    self.speechLanguageProvider = speechLanguageProvider
    self.libraryTrackProvider = libraryTrackProvider

    playbackController.onPlaybackFinished = { [weak self] kind in
      Task { @MainActor in
        await self?.handlePlaybackFinished(kind)
      }
    }
    playbackController.onPlaybackFailed = { [weak self] context in
      Task { @MainActor in
        await self?.handlePlaybackFailed(context)
      }
    }
    playbackController.onTrackTransitionWindowReached = { [weak self] in
      Task { @MainActor in
        await self?.handleTrackTransitionWindowReached()
      }
    }
    playbackController.onSpeechAdvancePointReached = { [weak self] in
      Task { @MainActor in
        await self?.handleSpeechAdvancePointReached()
      }
    }
  }

  var hasStationContent: Bool {
    station != nil || currentItem != nil || !queue.isEmpty
  }

  var upNextItems: [RadioQueueItem] {
    Array(queue.prefix(5))
  }

  var upcomingSpeechSegment: RadioSpeechPlaybackSegment? {
    if currentItem == nil,
       !queue.isEmpty,
       !hasPlayedStationIntro,
       let intro = station?.speech?.stationIntro {
      return intro.playbackSegment
    }

    if let currentItem,
       let nextItem = queue.first,
       let transition = transitionCopy(from: currentItem, to: nextItem) {
      return transition.playbackSegment
    }

    return nil
  }

  var stationTracks: [Track] {
    var tracks: [Track] = []
    if let currentItem {
      tracks.append(currentItem.track)
    }
    tracks.append(contentsOf: queue.map(\.track))
    return tracks
  }

  var stationTrackSignature: String {
    stationTracks.map(\.radioIdentity).joined(separator: "|")
  }

  func startStation() async {
    diagnostics?.record(
      .notice,
      chain: .radioStation,
      event: "start_station",
      message: L10n.tr("diagnostic.message.radioStartPlayback"),
      payload: ["has_station_content": DiagnosticsPayload.bool(hasStationContent)]
    )

    if queue.isEmpty, station == nil {
      await loadCurrentStation(playImmediately: true)
    } else {
      await playNext(reason: .stationStart)
    }
  }

  func playNext(reason: RadioAdvanceReason = .manual) async {
    if reason == .stationStart,
       !hasPlayedStationIntro,
       let intro = station?.speech?.stationIntro {
      hasPlayedStationIntro = true
      diagnostics?.record(
        .notice,
        chain: .playbackSpeech,
        event: "station_intro_selected",
        message: L10n.tr("diagnostic.message.radioIntroPlaybackStarted"),
        payload: [
          "station_id_hash": (station?.id).map(DiagnosticsRedactor.hash) ?? "unknown",
          "speech_id_hash": DiagnosticsRedactor.hash(intro.id)
        ]
      )
      playbackController.playSpeech(intro.playbackSegment, mode: .standalone)
      return
    }

    if reason == .automaticCompletion, let finishedItem = currentItem {
      if await playTransitionIfAvailable(
        from: finishedItem,
        reason: reason,
        style: .standalone,
        memoryEventType: "complete"
      ) {
        return
      }
      await retireCurrentItem(finishedItem, memoryEventType: "complete")
    } else if reason == .manual, let skippedItem = currentItem {
      if await playTransitionIfAvailable(
        from: skippedItem,
        reason: reason,
        style: .overlay,
        memoryEventType: "skip"
      ) {
        return
      }
      if await playTransitionIfAvailable(
        from: skippedItem,
        reason: reason,
        style: .standalone,
        memoryEventType: "skip"
      ) {
        return
      }
      await retireCurrentItem(skippedItem, memoryEventType: "skip")
    }

    if queue.isEmpty, let extensionTask {
      _ = await extensionTask.value
    }

    if queue.isEmpty {
      if station == nil {
        await loadCurrentStation()
      } else {
        _ = await extendCurrentStation()
      }
    }

    guard !queue.isEmpty else {
      if errorMessage == nil {
        errorMessage = extensionErrorMessage ?? L10n.tr("radio.error.noBackendTracks")
      }
      diagnostics?.record(
        .warning,
        chain: .radioStation,
        event: "queue_empty",
        message: L10n.tr("diagnostic.message.radioQueueEmpty"),
        payload: [
          "station_loaded": DiagnosticsPayload.bool(station != nil),
          "extension_error_hash": extensionErrorMessage.map(DiagnosticsRedactor.hash) ?? "none"
        ]
      )
      return
    }

    let nextItem = queue.removeFirst()
    currentItem = nextItem
    errorMessage = nil
    await recordMemoryEvent(type: "play", track: nextItem.track)
    diagnostics?.record(
      .notice,
      chain: .radioStation,
      event: "track_selected",
      message: L10n.tr("diagnostic.message.radioTrackSelected"),
      payload: DiagnosticsPayload.merge(
        [
          "advance_reason": reason.diagnosticValue,
          "queue_count_after_pop": String(queue.count),
          "item_id_hash": DiagnosticsRedactor.hash(nextItem.id)
        ],
        DiagnosticsPayload.track(nextItem.track)
      )
    )
    playbackController.play(track: nextItem.track, policy: .mixablePreferred, preservesSpeech: false)
    prefetchStationExtensionIfNeeded()
  }

  func playPrevious() {
    guard let previousItem = history.popLast() else { return }

    if let currentItem {
      queue.insert(currentItem, at: 0)
    }

    currentItem = previousItem
    errorMessage = nil
    diagnostics?.record(
      .notice,
      chain: .radioStation,
      event: "play_previous",
      message: L10n.tr("diagnostic.message.radioPlayPrevious"),
      payload: DiagnosticsPayload.track(previousItem.track)
    )
    Task {
      try? await memoryStore.record(RadioMemoryEvent(type: "replay", track: previousItem.track))
      await refreshMemoryStatus()
    }
    playbackController.play(track: previousItem.track, policy: .mixablePreferred, preservesSpeech: false)
  }

  func refreshStation() async {
    guard !isExtendingStation else { return }
    await loadCurrentStation()
  }

  func loadLocalStation(_ station: RadioStation, playImmediately: Bool = false) async {
    beginNewStationSession()
    let station = await stationWithRealArtwork(station)
    isLoadingStation = false
    errorMessage = nil
    extensionErrorMessage = nil
    self.station = station
    stationTitle = station.title
    stationIntro = station.subtitle
    currentItem = nil
    history = []
    queue = station.items
    hasPlayedStationIntro = false
    if station.items.isEmpty {
      errorMessage = RadioStationArtworkError.emptyQueue.errorDescription
    }
    diagnostics?.record(
      .notice,
      chain: .radioStation,
      event: "local_station_loaded",
      message: L10n.tr("diagnostic.message.localStationLoaded"),
      payload: [
        "station_id_hash": DiagnosticsRedactor.hash(station.id),
        "item_count": String(station.items.count),
        "play_immediately": DiagnosticsPayload.bool(playImmediately)
      ]
    )
    await recordMemoryEvent(type: "station_generate", track: station.items.first?.track)

    if playImmediately, !station.items.isEmpty {
      await playNext(reason: .stationStart)
    } else {
      playbackController.stop()
    }
  }

  func loadCurrentStation(playImmediately: Bool = false) async {
    guard !isLoadingStation else { return }

    beginNewStationSession()
    isLoadingStation = true
    errorMessage = nil
    extensionErrorMessage = nil
    diagnostics?.record(
      .notice,
      chain: .radioBackend,
      event: "generate_start",
      message: L10n.tr("diagnostic.message.radioGenerateStarted"),
      payload: ["play_immediately": DiagnosticsPayload.bool(playImmediately)]
    )

    do {
      await refreshMemoryStatus()
      let memoryContext = (try? await memoryStore.buildContext()) ?? RadioMemoryContext()
      let generationContext = RadioStationGenerationContext(
        action: "start",
        seedTracks: stationSeeds(),
        catalogCandidates: stationCandidates(),
        memoryContext: memoryContext,
        limit: batchSize,
        stationID: "airset-personal",
        hostSpeakerID: hostSpeakerIDProvider(),
        speechLanguage: speechLanguageProvider()
      )
      let result = try await stationClient.generateStation(context: generationContext)
      let station = await stationWithRealArtwork(result.station)
      guard !station.items.isEmpty else {
        throw RadioStationArtworkError.emptyQueue
      }
      stationSessionID = result.stationSessionID
      continuationCursor = result.continuationCursor
      self.station = station
      stationTitle = station.title
      stationIntro = station.subtitle
      currentItem = nil
      history = []
      queue = station.items
      hasPlayedStationIntro = false
      diagnostics?.record(
        .notice,
        chain: .radioBackend,
        event: "generate_success",
        message: L10n.tr("diagnostic.message.radioGenerateSucceeded"),
        payload: [
          "station_id_hash": DiagnosticsRedactor.hash(station.id),
          "station_session_id_hash": stationSessionID.map(DiagnosticsRedactor.hash) ?? "none",
          "item_count": String(station.items.count),
          "diagnostic_count": String(result.diagnostics.count),
          "memory_patch_count": String(result.memoryPatchProposals.count)
        ]
      )
      await recordMemoryEvent(type: "station_generate", track: station.items.first?.track)

      if playImmediately {
        isLoadingStation = false
        await playNext(reason: .stationStart)
        return
      }
    } catch {
      self.station = nil
      currentItem = nil
      history = []
      queue = []
      hasPlayedStationIntro = false
      stationSessionID = nil
      continuationCursor = nil
      stationTitle = L10n.tr("radio.defaultTitle")
      stationIntro = L10n.tr("radio.backendUnavailable")
      errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      diagnostics?.record(
        .error,
        chain: .radioBackend,
        event: "generate_failed",
        message: L10n.tr("diagnostic.message.radioGenerateFailed"),
        payload: DiagnosticsPayload.error(error)
      )
    }

    isLoadingStation = false
  }

  @discardableResult
  func extendCurrentStationIfNeeded() async -> Bool {
    guard queue.count <= prefetchThreshold else { return true }
    return await extendCurrentStation()
  }

  @discardableResult
  func extendCurrentStation() async -> Bool {
    if let extensionTask {
      return await extensionTask.value
    }

    return await performStationExtension()
  }

  func refreshSpeechVoices() async {
    guard !isLoadingSpeechVoices else { return }

    isLoadingSpeechVoices = true
    speechVoicesErrorMessage = nil
    diagnostics?.record(
      .info,
      chain: .radioBackend,
      event: "speech_voices_refresh_start",
      message: L10n.tr("diagnostic.message.speechVoicesRefreshStarted")
    )

    do {
      speechVoiceCatalog = try await stationClient.fetchSpeechVoices()
      diagnostics?.record(
        .notice,
        chain: .radioBackend,
        event: "speech_voices_refresh_success",
        message: L10n.tr("diagnostic.message.speechVoicesRefreshSucceeded"),
        payload: [
          "voice_count": String(speechVoiceCatalog?.voices.count ?? 0),
          "default_speaker_hash": (speechVoiceCatalog?.defaultSpeaker).map(DiagnosticsRedactor.hash) ?? "none"
        ]
      )
    } catch {
      speechVoicesErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      diagnostics?.record(
        .error,
        chain: .radioBackend,
        event: "speech_voices_refresh_failed",
        message: L10n.tr("diagnostic.message.speechVoicesRefreshFailed"),
        payload: DiagnosticsPayload.error(error)
      )
    }

    isLoadingSpeechVoices = false
  }

  func refreshMemoryStatus() async {
    guard let snapshot = try? await memoryStore.snapshot() else { return }
    memoryEventCount = snapshot.eventCount
    if !snapshot.tasteSummary.isEmpty {
      memorySummaryText = snapshot.tasteSummary
    } else if !snapshot.avoidSummary.isEmpty {
      memorySummaryText = snapshot.avoidSummary
    } else {
      memorySummaryText = snapshot.eventCount == 0
        ? L10n.tr("radio.memory.ready")
        : "Learning from \(snapshot.eventCount) recent radio events."
    }
  }

  func clearMemory() async {
    do {
      try await memoryStore.clear()
      diagnostics?.record(
        .notice,
        chain: .radioMemory,
        event: "cleared",
        message: L10n.tr("diagnostic.message.radioMemoryCleared")
      )
    } catch {
      diagnostics?.record(
        .error,
        chain: .radioMemory,
        event: "clear_failed",
        message: L10n.tr("diagnostic.message.radioMemoryClearFailed"),
        payload: DiagnosticsPayload.error(error)
      )
    }
    await refreshMemoryStatus()
  }

  private func prefetchStationExtensionIfNeeded() {
    guard queue.count <= prefetchThreshold else { return }
    guard extensionTask == nil else { return }

    let taskID = UUID()
    extensionTaskID = taskID
    extensionTask = Task { @MainActor [weak self] in
      guard let self else { return false }
      guard !Task.isCancelled else { return false }
      let didExtend = await self.performStationExtension()
      if self.extensionTaskID == taskID {
        self.extensionTask = nil
        self.extensionTaskID = nil
      }
      return didExtend
    }
  }

  private func performStationExtension() async -> Bool {
    guard !Task.isCancelled else { return false }
    guard station != nil else { return false }
    guard !isLoadingStation, !isExtendingStation else { return !queue.isEmpty }

    let generationID = stationGenerationID
    isExtendingStation = true
    extensionErrorMessage = nil
    diagnostics?.record(
      .info,
      chain: .radioBackend,
      event: "extend_start",
      message: L10n.tr("diagnostic.message.radioExtendStarted"),
      payload: [
        "station_id_hash": (station?.id).map(DiagnosticsRedactor.hash) ?? "none",
        "queue_count": String(queue.count)
      ]
    )

    do {
      await refreshMemoryStatus()
      let memoryContext = (try? await memoryStore.buildContext()) ?? RadioMemoryContext()
      let generationContext = RadioStationGenerationContext(
        action: "continue",
        seedTracks: stationSeeds(),
        catalogCandidates: stationCandidates(),
        memoryContext: memoryContext,
        limit: batchSize,
        stationID: station?.id ?? "airset-personal",
        stationSessionID: stationSessionID,
        continuationCursor: continuationCursor,
        currentTrackKey: currentItem?.track.radioIdentity,
        queuedTrackKeys: queue.map(\.track.radioIdentity),
        recentlyPlayedTrackKeys: recentPlaybackTrackKeys(),
        hostSpeakerID: hostSpeakerIDProvider(),
        speechLanguage: speechLanguageProvider()
      )
      let result = try await stationClient.generateStation(context: generationContext)

      guard generationID == stationGenerationID, !Task.isCancelled else {
        return false
      }

      let nextStation = await stationWithRealArtwork(result.station)
      stationSessionID = result.stationSessionID ?? stationSessionID
      continuationCursor = result.continuationCursor ?? continuationCursor
      let newItems = appendStationExtension(nextStation)
      isExtendingStation = false

      guard let firstNewItem = newItems.first else {
        extensionErrorMessage = L10n.tr("radio.error.noNewBackendTracks")
        diagnostics?.record(
          .warning,
          chain: .radioBackend,
          event: "extend_empty",
          message: L10n.tr("diagnostic.message.radioExtendEmpty"),
          payload: ["known_queue_count": String(queue.count)]
        )
        return false
      }

      errorMessage = nil
      extensionErrorMessage = nil
      await recordMemoryEvent(type: "station_extend", track: firstNewItem.track)
      diagnostics?.record(
        .notice,
        chain: .radioBackend,
        event: "extend_success",
        message: L10n.tr("diagnostic.message.radioExtendSucceeded"),
        payload: [
          "new_item_count": String(newItems.count),
          "queue_count": String(queue.count),
          "station_session_id_hash": stationSessionID.map(DiagnosticsRedactor.hash) ?? "none"
        ]
      )
      return true
    } catch {
      guard generationID == stationGenerationID else {
        return false
      }

      isExtendingStation = false
      extensionErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      diagnostics?.record(
        .error,
        chain: .radioBackend,
        event: "extend_failed",
        message: L10n.tr("diagnostic.message.radioExtendFailed"),
        payload: DiagnosticsPayload.error(error)
      )
      return false
    }
  }

  private func appendStationExtension(_ nextStation: RadioStation) -> [RadioQueueItem] {
    let newItems = uniqueExtensionItems(from: nextStation.items)
    guard !newItems.isEmpty else { return [] }

    queue.append(contentsOf: newItems)

    let currentStation = station
    let baseItems = currentStation?.items ?? []
    station = RadioStation(
      id: currentStation?.id ?? nextStation.id,
      title: currentStation?.title ?? nextStation.title,
      subtitle: currentStation?.subtitle ?? nextStation.subtitle,
      items: baseItems + newItems,
      speech: mergedSpeech(existing: currentStation?.speech, incoming: nextStation.speech)
    )
    return newItems
  }

  private func stationWithRealArtwork(_ station: RadioStation) async -> RadioStation {
    let items = await queueItemsWithRealArtwork(station.items)
    return RadioStation(
      id: station.id,
      title: station.title,
      subtitle: station.subtitle,
      items: items,
      speech: station.speech
    )
  }

  private func queueItemsWithRealArtwork(_ items: [RadioQueueItem]) async -> [RadioQueueItem] {
    guard !items.isEmpty else { return [] }
    let enrichedTracks = await artworkEnricher.enrichArtwork(items.map(\.track))
    return zip(items, enrichedTracks).compactMap { item, track in
      guard track.hasRealArtwork else { return nil }
      return item.replacingTrack(track)
    }
  }

  private func uniqueExtensionItems(from items: [RadioQueueItem]) -> [RadioQueueItem] {
    var seenTrackKeys = knownStationTrackKeys()
    var uniqueItems: [RadioQueueItem] = []

    for item in items {
      let key = item.track.radioIdentity
      guard !seenTrackKeys.contains(key) else { continue }
      seenTrackKeys.insert(key)
      uniqueItems.append(item)
    }

    return uniqueItems
  }

  private func knownStationTrackKeys() -> Set<String> {
    var keys = Set(station?.items.map(\.track.radioIdentity) ?? [])
    if let currentItem {
      keys.insert(currentItem.track.radioIdentity)
    }
    keys.formUnion(queue.map(\.track.radioIdentity))
    keys.formUnion(history.map(\.track.radioIdentity))
    return keys
  }

  private func mergedSpeech(existing: RadioSpeech?, incoming: RadioSpeech?) -> RadioSpeech? {
    guard existing != nil || incoming != nil else { return nil }

    let intro = existing?.stationIntro ?? incoming?.stationIntro
    var transitions = existing?.betweenTracks ?? []
    var seenTransitionKeys = Set(transitions.map(transitionKey))

    for transition in incoming?.betweenTracks ?? [] {
      let key = transitionKey(transition)
      guard !seenTransitionKeys.contains(key) else { continue }
      seenTransitionKeys.insert(key)
      transitions.append(transition)
    }

    return RadioSpeech(stationIntro: intro, betweenTracks: transitions)
  }

  private func transitionKey(_ transition: RadioTransitionCopy) -> String {
    "\(transition.id)|\(transition.fromItemId)|\(transition.toItemId)"
  }

  private func recentPlaybackTrackKeys() -> [String] {
    var recentKeys = history.suffix(12).reversed().map(\.track.radioIdentity)
    if let currentItem {
      recentKeys.insert(currentItem.track.radioIdentity, at: 0)
    }
    return recentKeys
  }

  private func beginNewStationSession() {
    extensionTask?.cancel()
    extensionTask = nil
    extensionTaskID = nil
    stationGenerationID = UUID()
    stationSessionID = nil
    continuationCursor = nil
    isExtendingStation = false
    extensionErrorMessage = nil
    pendingTransition = nil
  }

  private func stationSeeds() -> [Track] {
    let currentTracks = stationTracks
    if !currentTracks.isEmpty {
      return Array(currentTracks.prefix(6))
    }
    let recentTracks = history.suffix(6).map(\.track)
    if !recentTracks.isEmpty {
      return Array(recentTracks)
    }
    let libraryTracks = libraryTrackProvider().filter(\.isPlayable)
    if !libraryTracks.isEmpty {
      return Array(libraryTracks.prefix(6))
    }
    return MockCatalog.featuredTracks
  }

  private func stationCandidates() -> [Track] {
    var candidates = libraryTrackProvider().filter(\.isPlayable)
    if candidates.isEmpty {
      candidates = MockCatalog.radioCandidates
    }

    for track in stationTracks where !candidates.contains(where: { $0.radioIdentity == track.radioIdentity }) {
      candidates.append(track)
    }
    return candidates
  }

  private func recordMemoryEvent(type: String, track: Track?) async {
    do {
      try await memoryStore.record(RadioMemoryEvent(type: type, track: track))
      diagnostics?.record(
        .info,
        chain: .radioMemory,
        event: "event_recorded",
        message: L10n.tr("diagnostic.message.radioMemoryEventRecorded"),
        payload: DiagnosticsPayload.merge(
          ["memory_event_type": type],
          track.map(DiagnosticsPayload.track) ?? [:]
        )
      )
    } catch {
      diagnostics?.record(
        .error,
        chain: .radioMemory,
        event: "event_record_failed",
        message: L10n.tr("diagnostic.message.radioMemoryEventRecordFailed"),
        payload: DiagnosticsPayload.merge(
          ["memory_event_type": type],
          DiagnosticsPayload.error(error)
        )
      )
    }
    await compressMemoryIfNeeded()
    await refreshMemoryStatus()
  }

  private func retireCurrentItem(_ item: RadioQueueItem, memoryEventType: String) async {
    await recordMemoryEvent(type: memoryEventType, track: item.track)
    history.append(item)
    if currentItem?.id == item.id {
      currentItem = nil
    }
  }

  private func handleTrackTransitionWindowReached() async {
    guard let currentItem else { return }
    _ = await playTransitionIfAvailable(
      from: currentItem,
      reason: .automaticCompletion,
      style: .overlay,
      memoryEventType: "complete"
    )
  }

  private func handleSpeechAdvancePointReached() async {
    await startPendingTransitionNextTrackIfNeeded(preservesSpeech: true)
  }

  private func startPendingTransitionNextTrackIfNeeded(preservesSpeech: Bool) async {
    guard var transition = pendingTransition else { return }
    guard !transition.didStartNextTrack else { return }
    guard let nextItem = removePendingTransitionNextItem(transition.toItem) else {
      pendingTransition = nil
      return
    }

    transition.didStartNextTrack = true
    pendingTransition = transition
    currentItem = nextItem
    errorMessage = nil
    await recordMemoryEvent(type: "play", track: nextItem.track)
    diagnostics?.record(
      .notice,
      chain: .radioStation,
      event: "transition_next_track_selected",
      message: L10n.tr("diagnostic.message.radioTransitionAdvanceReached"),
      payload: DiagnosticsPayload.merge(
        [
          "advance_reason": transition.reason.diagnosticValue,
          "queue_count_after_pop": String(queue.count),
          "item_id_hash": DiagnosticsRedactor.hash(nextItem.id),
          "preserves_speech": DiagnosticsPayload.bool(preservesSpeech)
        ],
        DiagnosticsPayload.track(nextItem.track)
      )
    )
    playbackController.play(track: nextItem.track, policy: .mixablePreferred, preservesSpeech: preservesSpeech)
    prefetchStationExtensionIfNeeded()
  }

  private func removePendingTransitionNextItem(_ expectedItem: RadioQueueItem) -> RadioQueueItem? {
    if let firstItem = queue.first, idsMatch(expectedItem.id, firstItem) {
      return queue.removeFirst()
    }
    guard let index = queue.firstIndex(where: { item in
      item.id == expectedItem.id || item.track.radioIdentity == expectedItem.track.radioIdentity
    }) else {
      return nil
    }
    return queue.remove(at: index)
  }

  private func handlePlaybackFinished(_ kind: PlaybackCompletionKind) async {
    switch kind {
    case .track:
      if pendingTransition != nil {
        await startPendingTransitionNextTrackIfNeeded(preservesSpeech: true)
        if pendingTransition != nil {
          return
        }
      }
      await playNext(reason: .automaticCompletion)
    case .speech:
      if pendingTransition != nil {
        await startPendingTransitionNextTrackIfNeeded(preservesSpeech: false)
        pendingTransition = nil
        return
      }
      await playNext(reason: .speechCompletion)
    }
  }

  private func handlePlaybackFailed(_ context: PlaybackFailureContext) async {
    guard let failedItem = currentItem else { return }
    guard failedItem.track.id == context.track.id || failedItem.track.radioIdentity == context.track.radioIdentity else {
      return
    }

    diagnostics?.record(
      .warning,
      chain: .radioStation,
      event: "playback_failed_auto_skip",
      message: L10n.tr("diagnostic.message.radioTrackFailedSkipNext"),
      payload: DiagnosticsPayload.merge(
        [
          "failed_phase": context.phase,
          "item_id_hash": DiagnosticsRedactor.hash(failedItem.id)
        ],
        DiagnosticsPayload.track(failedItem.track)
      )
    )

    await recordMemoryEvent(type: "playback_failed", track: failedItem.track)
    currentItem = nil
    errorMessage = nil
    await playNext(reason: .playbackFailure)
  }

  private func transitionCopy(from finishedItem: RadioQueueItem, to nextItem: RadioQueueItem) -> RadioTransitionCopy? {
    if let transition = station?.speech?.betweenTracks.first(where: { copy in
      idsMatch(copy.fromItemId, finishedItem) && idsMatch(copy.toItemId, nextItem)
    }) {
      return transition
    }

    guard let handoffText = nextItem.handoffText?.trimmedNilIfEmpty else { return nil }
    return RadioTransitionCopy(
      id: "handoff-\(finishedItem.id)-\(nextItem.id)",
      fromItemId: finishedItem.id,
      toItemId: nextItem.id,
      text: handoffText,
      displayText: handoffText,
      agent: "handoff_text"
    )
  }

  private func playTransitionIfAvailable(
    from finishedItem: RadioQueueItem,
    reason: RadioAdvanceReason,
    style: RadioTransitionPlaybackStyle,
    memoryEventType: String
  ) async -> Bool {
    guard let nextItem = queue.first,
          let transition = transitionCopy(from: finishedItem, to: nextItem) else {
      return false
    }
    if style == .overlay, !canUseOverlayTransition(from: finishedItem, to: nextItem) {
      return false
    }

    await retireCurrentItem(finishedItem, memoryEventType: memoryEventType)
    prefetchStationExtensionIfNeeded()
    let speech = transition.playbackSegment
    pendingTransition = PendingRadioTransition(
      fromItem: finishedItem,
      toItem: nextItem,
      speech: speech,
      reason: reason
    )
    diagnostics?.record(
      .notice,
      chain: .playbackSpeech,
      event: "transition_selected",
      message: L10n.tr("diagnostic.message.radioTransitionPlaybackStarted"),
      payload: [
        "advance_reason": reason.diagnosticValue,
        "from_item_hash": DiagnosticsRedactor.hash(finishedItem.id),
        "to_item_hash": DiagnosticsRedactor.hash(nextItem.id),
        "speech_id_hash": DiagnosticsRedactor.hash(transition.id),
        "transition_style": style.diagnosticValue
      ]
    )
    playbackController.playSpeech(speech, mode: style == .overlay ? .transitionOverlay : .standalone)
    return true
  }

  private func canUseOverlayTransition(from finishedItem: RadioQueueItem, to nextItem: RadioQueueItem) -> Bool {
    finishedItem.track.previewURL != nil && nextItem.track.previewURL != nil
  }

  private func idsMatch(_ id: String, _ item: RadioQueueItem) -> Bool {
    id == item.id || id == item.track.radioIdentity
  }

  private func compressMemoryIfNeeded() async {
    guard let request = try? await memoryStore.compressionRequest() else { return }
    diagnostics?.record(
      .info,
      chain: .radioMemory,
      event: "compression_requested",
      message: L10n.tr("diagnostic.message.radioMemoryCompressionThreshold"),
      payload: ["new_event_count": String(request.newEvents.count)]
    )

    do {
      guard let proposal = try await stationClient.compressMemory(request) else {
        diagnostics?.record(
          .info,
          chain: .radioMemory,
          event: "compression_skipped",
          message: L10n.tr("diagnostic.message.radioMemoryCompressionEmpty")
        )
        return
      }
      try await memoryStore.applyCompression(proposal)
      diagnostics?.record(
        .notice,
        chain: .radioMemory,
        event: "compression_applied",
        message: L10n.tr("diagnostic.message.radioMemoryCompressionApplied")
      )
    } catch {
      diagnostics?.record(
        .error,
        chain: .radioMemory,
        event: "compression_failed",
        message: L10n.tr("diagnostic.message.radioMemoryCompressionFailed"),
        payload: DiagnosticsPayload.error(error)
      )
    }
  }
}

enum RadioAdvanceReason {
  case manual
  case stationStart
  case automaticCompletion
  case speechCompletion
  case playbackFailure
}

private extension RadioAdvanceReason {
  var diagnosticValue: String {
    switch self {
    case .manual:
      "manual"
    case .stationStart:
      "station_start"
    case .automaticCompletion:
      "automatic_completion"
    case .speechCompletion:
      "speech_completion"
    case .playbackFailure:
      "playback_failure"
    }
  }
}

private extension String {
  var trimmedNilIfEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
