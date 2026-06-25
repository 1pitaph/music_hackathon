import AVFoundation
import MediaPlayer
import MusicKit
import Observation
import UIKit

enum PlaybackCompletionKind {
  case track
  case speech
}

enum RadioTrackPlaybackPolicy: Equatable {
  case fullSongPreferred
  case mixablePreferred
}

enum RadioSpeechPlaybackMode: Equatable {
  case standalone
  case transitionOverlay
}

struct PlaybackFailureContext {
  let track: Track
  let phase: String
  let message: String
}

@MainActor
protocol RadioPlaybackControlling: AnyObject {
  var onPlaybackFinished: ((PlaybackCompletionKind) -> Void)? { get set }
  var onPlaybackFailed: ((PlaybackFailureContext) -> Void)? { get set }
  var onTrackTransitionWindowReached: (() -> Void)? { get set }
  var onSpeechAdvancePointReached: (() -> Void)? { get set }

  func play(track: Track)
  func play(track: Track, policy: RadioTrackPlaybackPolicy, preservesSpeech: Bool)
  func playSpeech(_ speech: RadioSpeechPlaybackSegment)
  func playSpeech(_ speech: RadioSpeechPlaybackSegment, mode: RadioSpeechPlaybackMode)
  func stop()
}

enum PlaybackState: String {
  case idle
  case loading
  case playing
  case paused
  case failed
}

private enum PlaybackMediaKind {
  case track(Track, String?)
  case speech(RadioSpeechPlaybackSegment)
}

private struct RadioTransitionOverlayTiming {
  let fadeDuration: TimeInterval
  let speechDelay: TimeInterval
  let duckVolume: Float
  let advanceRatio: Double
  let restoreDuration: TimeInterval

  static let automatic = RadioTransitionOverlayTiming(
    fadeDuration: 1.2,
    speechDelay: 0.7,
    duckVolume: 0.22,
    advanceRatio: 0.667,
    restoreDuration: 1.2
  )

  static let manual = RadioTransitionOverlayTiming(
    fadeDuration: 0.8,
    speechDelay: 0.35,
    duckVolume: 0.22,
    advanceRatio: 0.667,
    restoreDuration: 1.2
  )
}

private struct SpeechCueRange {
  let cue: RadioSpeechCue
  let range: NSRange
}

private enum PlaybackControllerError: LocalizedError {
  case playerItemFailed

  var errorDescription: String? {
    switch self {
    case .playerItemFailed:
      "The audio item failed to load."
    }
  }
}

@MainActor
@Observable
final class PlaybackController: RadioPlaybackControlling {
  var currentTrack: Track?
  var currentSpeech: RadioSpeechPlaybackSegment?
  var currentSpeechCue: RadioSpeechCue?
  var state: PlaybackState = .idle
  var lastErrorMessage: String?
  var playbackProgress: Double = 0
  var elapsedSeconds: TimeInterval = 0
  var elapsedTimeText: String = "0:00"
  var activeBackend: PlaybackBackend = .none
  var onPlaybackFinished: ((PlaybackCompletionKind) -> Void)?
  var onPlaybackFailed: ((PlaybackFailureContext) -> Void)?
  var onTrackTransitionWindowReached: (() -> Void)?
  var onSpeechAdvancePointReached: (() -> Void)?
  var onTrackFinished: (() -> Void)?

  @ObservationIgnored private let trackPreviewPlayer = AVPlayer()
  @ObservationIgnored private let speechAudioPlayer = AVPlayer()
  @ObservationIgnored private let musicPlayer = ApplicationMusicPlayer.shared
  @ObservationIgnored private let speechSynthesizer = AVSpeechSynthesizer()
  @ObservationIgnored private let speechCompletionDelegate = SpeechCompletionDelegate()
  @ObservationIgnored private let musicAuthorization: MusicAuthorizationService
  @ObservationIgnored private let diagnostics: DiagnosticsStore?
  @ObservationIgnored private let catalogService = AppleMusicCatalogService()
  @ObservationIgnored private var trackTimeObserverToken: Any?
  @ObservationIgnored private var speechTimeObserverToken: Any?
  @ObservationIgnored private var trackEndObserverToken: NSObjectProtocol?
  @ObservationIgnored private var trackFailedItemObserverToken: NSObjectProtocol?
  @ObservationIgnored private var speechEndObserverToken: NSObjectProtocol?
  @ObservationIgnored private var speechFailedItemObserverToken: NSObjectProtocol?
  @ObservationIgnored private var trackItemStatusObserver: NSKeyValueObservation?
  @ObservationIgnored private var speechItemStatusObserver: NSKeyValueObservation?
  @ObservationIgnored private var musicProgressTask: Task<Void, Never>?
  @ObservationIgnored private var speechProgressTask: Task<Void, Never>?
  @ObservationIgnored private var playbackTask: Task<Void, Never>?
  @ObservationIgnored private var speechStartTask: Task<Void, Never>?
  @ObservationIgnored private var trackVolumeRampTask: Task<Void, Never>?
  @ObservationIgnored private var didNotifyTrackFinished = false
  @ObservationIgnored private var didNotifySpeechFinished = false
  @ObservationIgnored private var didNotifyTrackTransitionWindow = false
  @ObservationIgnored private var didNotifySpeechAdvancePoint = false
  @ObservationIgnored private var didNotifyPlaybackFailed = false
  @ObservationIgnored private var currentPlaybackAttemptID: String?
  @ObservationIgnored private var currentPlaybackStartedAt: Date?
  @ObservationIgnored private var synthesizedSpeechCueRanges: [SpeechCueRange] = []
  @ObservationIgnored private var currentTrackPlaybackPolicy: RadioTrackPlaybackPolicy = .fullSongPreferred
  @ObservationIgnored private var currentSpeechPlaybackMode: RadioSpeechPlaybackMode = .standalone
  @ObservationIgnored private var currentOverlayTiming: RadioTransitionOverlayTiming = .automatic
  @ObservationIgnored private var backgroundContinuationTask: UIBackgroundTaskIdentifier = .invalid
  @ObservationIgnored private var backgroundContinuationReason: String?

  init(diagnostics: DiagnosticsStore? = nil) {
    self.musicAuthorization = MusicAuthorizationService(diagnostics: diagnostics)
    self.diagnostics = diagnostics
    configureController()
  }

  init(musicAuthorization: MusicAuthorizationService, diagnostics: DiagnosticsStore? = nil) {
    self.musicAuthorization = musicAuthorization
    self.diagnostics = diagnostics
    configureController()
  }

  private func configureController() {
    speechCompletionDelegate.onFinish = { [weak self] in
      Task { @MainActor in
        self?.finishSynthesizedSpeech()
      }
    }
    speechCompletionDelegate.onSpeakRange = { [weak self] range, utterance in
      Task { @MainActor in
        self?.updateSynthesizedSpeechCue(for: range, spokenText: utterance.speechString)
      }
    }
    speechSynthesizer.delegate = speechCompletionDelegate
    configureAudioSession()
    configureRemoteCommands()
  }

  deinit {
    if let trackTimeObserverToken {
      trackPreviewPlayer.removeTimeObserver(trackTimeObserverToken)
    }
    if let speechTimeObserverToken {
      speechAudioPlayer.removeTimeObserver(speechTimeObserverToken)
    }

    [trackEndObserverToken, trackFailedItemObserverToken, speechEndObserverToken, speechFailedItemObserverToken]
      .compactMap { $0 }
      .forEach(NotificationCenter.default.removeObserver)
    trackItemStatusObserver?.invalidate()
    speechItemStatusObserver?.invalidate()

    musicProgressTask?.cancel()
    speechProgressTask?.cancel()
    playbackTask?.cancel()
    speechStartTask?.cancel()
    trackVolumeRampTask?.cancel()
  }

  func play(track: Track) {
    play(track: track, policy: .fullSongPreferred, preservesSpeech: false)
  }

  func play(track: Track, policy: RadioTrackPlaybackPolicy, preservesSpeech: Bool) {
    playbackTask?.cancel()
    playbackTask = Task { [weak self] in
      await self?.startPlayback(for: track, policy: policy, preservesSpeech: preservesSpeech)
    }
  }

  func playSpeech(_ speech: RadioSpeechPlaybackSegment) {
    playSpeech(speech, mode: .standalone)
  }

  func playSpeech(_ speech: RadioSpeechPlaybackSegment, mode: RadioSpeechPlaybackMode) {
    playbackTask?.cancel()
    startSpeechPlayback(speech, mode: mode)
  }

  func togglePlayback() {
    playbackTask?.cancel()

    switch state {
    case .playing:
      pause()
    case .paused:
      resume()
    case .idle:
      if let currentTrack {
        play(track: currentTrack)
      } else if let firstTrack = MockCatalog.featuredTracks.first {
        play(track: firstTrack)
      }
    case .loading, .failed:
      break
    }
  }

  func pause() {
    diagnostics?.record(
      .info,
      chain: activeBackend.diagnosticChain,
      event: "pause",
      message: "暂停当前播放。",
      correlationID: currentPlaybackAttemptID,
      payload: ["backend": activeBackend.rawValue]
    )

    switch activeBackend {
    case .appleMusic:
      musicPlayer.pause()
      stopMusicProgressTimer()
    case .localPreview:
      trackPreviewPlayer.pause()
      speechAudioPlayer.pause()
      speechSynthesizer.pauseSpeaking(at: .word)
      stopSpeechProgressTimer()
    case .speechAudio:
      speechAudioPlayer.pause()
      if trackPreviewPlayer.currentItem != nil {
        trackPreviewPlayer.pause()
      }
    case .speechSynthesis:
      speechSynthesizer.pauseSpeaking(at: .word)
      if trackPreviewPlayer.currentItem != nil {
        trackPreviewPlayer.pause()
      }
      stopSpeechProgressTimer()
    case .none:
      break
    }

    state = .paused
    updateNowPlayingPlaybackRate(0)
  }

  func stop() {
    playbackTask?.cancel()
    stopCurrentPlayback(clearCurrentTrack: true)
  }

  func currentPlaybackSeconds() -> TimeInterval {
    switch activeBackend {
    case .appleMusic:
      let seconds = musicPlayer.playbackTime
      return seconds.isFinite ? max(0, seconds) : elapsedSeconds
    case .localPreview:
      let seconds = trackPreviewPlayer.currentTime().seconds
      return seconds.isFinite ? max(0, seconds) : 0
    case .speechAudio:
      let seconds = speechAudioPlayer.currentTime().seconds
      return seconds.isFinite ? max(0, seconds) : 0
    case .speechSynthesis:
      return elapsedSeconds
    case .none:
      return 0
    }
  }

  private func startPlayback(
    for track: Track,
    policy: RadioTrackPlaybackPolicy,
    preservesSpeech: Bool
  ) async {
    let attemptID = UUID().uuidString
    currentPlaybackAttemptID = attemptID
    currentPlaybackStartedAt = Date()
    currentTrack = track
    currentTrackPlaybackPolicy = policy
    if !preservesSpeech {
      currentSpeech = nil
      currentSpeechCue = nil
      synthesizedSpeechCueRanges = []
      currentSpeechPlaybackMode = .standalone
      didNotifySpeechAdvancePoint = false
    }
    lastErrorMessage = nil
    state = .loading
    if preservesSpeech {
      stopTrackPlayback(clearCurrentTrack: false)
    } else {
      stopCurrentPlayback(clearCurrentTrack: false)
    }
    didNotifyPlaybackFailed = false
    resetPlaybackProgress()
    let shouldPreferPreview = policy == .mixablePreferred && track.previewURL != nil
    diagnostics?.record(
      .notice,
      chain: shouldPreferPreview || track.normalizedAppleMusicID == nil ? .playbackPreview : .playbackAppleMusic,
      event: "attempt_start",
      message: "开始播放曲目。",
      correlationID: attemptID,
      payload: DiagnosticsPayload.track(track)
    )

    if shouldPreferPreview, let previewURL = track.previewURL {
      startPreviewPlayback(
        for: track,
        previewURL: previewURL,
        correlationID: attemptID,
        reason: "mixable_preferred",
        initialVolume: preservesSpeech ? currentOverlayTiming.duckVolume : 1.0
      )
      return
    }

    if track.normalizedAppleMusicID != nil {
      do {
        try await startAppleMusicPlayback(for: track, attemptID: attemptID)
        return
      } catch {
        if track.previewURL == nil {
          failPlayback(error, failedPhase: "apple_music_start", correlationID: attemptID)
          return
        }

        lastErrorMessage = nil
        diagnostics?.record(
          .warning,
          chain: .playbackPreview,
          event: "fallback_preview",
          message: "完整歌曲启动失败，切换到试听片段。",
          correlationID: attemptID,
          payload: DiagnosticsPayload.merge(
            ["failed_phase": "apple_music_start"],
            DiagnosticsPayload.track(track),
            DiagnosticsPayload.error(error)
          )
        )
      }
    }

    if let previewURL = track.previewURL {
      startPreviewPlayback(
        for: track,
        previewURL: previewURL,
        correlationID: attemptID,
        reason: track.normalizedAppleMusicID == nil ? "direct_preview" : "apple_music_fallback"
      )
    } else {
      do {
        try await startAppleMusicPlayback(for: track, attemptID: attemptID)
      } catch {
        failPlayback(error, failedPhase: "apple_music_retry", correlationID: attemptID)
      }
    }
  }

  private func startAppleMusicPlayback(for track: Track, attemptID: String) async throws {
    didNotifyTrackFinished = false
    diagnostics?.record(
      .info,
      chain: .musicSubscription,
      event: "access_check_start",
      message: "检查 Apple Music 完整播放资格。",
      correlationID: attemptID
    )

    do {
      try await musicAuthorization.ensureCatalogPlaybackReady()
      diagnostics?.record(
        .notice,
        chain: .musicSubscription,
        event: "access_check_success",
        message: "Apple Music 完整播放资格检查通过。",
        correlationID: attemptID
      )
    } catch {
      diagnostics?.record(
        .error,
        chain: .musicSubscription,
        event: "access_check_failed",
        message: "Apple Music 完整播放资格检查失败。",
        correlationID: attemptID,
        payload: DiagnosticsPayload.error(error)
      )
      throw error
    }

    diagnostics?.record(
      .info,
      chain: .musicCatalog,
      event: "resolve_start",
      message: "开始解析 Apple Music 目录歌曲。",
      correlationID: attemptID,
      payload: DiagnosticsPayload.track(track)
    )
    let resolution: AppleMusicCatalogResolution
    do {
      resolution = try await catalogService.resolveSong(for: track)
      if let idError = resolution.idError {
        diagnostics?.record(
          .warning,
          chain: .musicCatalog,
          event: "resolve_id_failed_search_fallback",
          message: "Apple Music ID 直查失败，已用标题和艺人搜索兜底。",
          correlationID: attemptID,
          payload: DiagnosticsPayload.merge(
            ["resolution_method": resolution.method.rawValue],
            DiagnosticsPayload.track(track),
            DiagnosticsPayload.error(idError)
          )
        )
      }
    } catch {
      diagnostics?.record(
        .error,
        chain: .musicCatalog,
        event: "resolve_failed",
        message: "Apple Music 目录歌曲解析失败。",
        correlationID: attemptID,
        payload: DiagnosticsPayload.merge(
          DiagnosticsPayload.track(track),
          DiagnosticsPayload.error(error)
        )
      )
      throw error
    }

    let song = resolution.song
    let resolvedTrack = AppleMusicCatalogService.track(from: song, fallback: track)
    diagnostics?.record(
      .notice,
      chain: .musicCatalog,
      event: "resolve_success",
      message: "Apple Music 目录歌曲解析完成。",
      correlationID: attemptID,
      payload: DiagnosticsPayload.merge(
        ["resolution_method": resolution.method.rawValue],
        DiagnosticsPayload.track(resolvedTrack)
      )
    )
    musicPlayer.queue = [song]
    diagnostics?.record(
      .info,
      chain: .playbackAppleMusic,
      event: "queue_set",
      message: "ApplicationMusicPlayer 队列已设置。",
      correlationID: attemptID,
      payload: DiagnosticsPayload.track(resolvedTrack)
    )

    do {
      let prepareStart = Date()
      diagnostics?.record(
        .info,
        chain: .playbackAppleMusic,
        event: "prepare_start",
        message: "开始准备完整歌曲播放。",
        correlationID: attemptID
      )
      try await musicPlayer.prepareToPlay()
      diagnostics?.record(
        .notice,
        chain: .playbackAppleMusic,
        event: "prepare_success",
        message: "完整歌曲播放准备完成。",
        correlationID: attemptID,
        payload: ["duration_ms": DiagnosticsPayload.durationMilliseconds(Date().timeIntervalSince(prepareStart))]
      )
    } catch {
      if fallbackToPreviewAfterAppleMusicFailure(
        error,
        resolvedTrack: resolvedTrack,
        originalTrack: track,
        attemptID: attemptID,
        failedPhase: "prepare_to_play"
      ) {
        return
      }

      throw error
    }

    do {
      let playStart = Date()
      diagnostics?.record(
        .info,
        chain: .playbackAppleMusic,
        event: "play_start",
        message: "开始请求完整歌曲播放。",
        correlationID: attemptID
      )
      try await musicPlayer.play()
      diagnostics?.record(
        .notice,
        chain: .playbackAppleMusic,
        event: "play_success",
        message: "完整歌曲播放已启动。",
        correlationID: attemptID,
        payload: ["duration_ms": DiagnosticsPayload.durationMilliseconds(Date().timeIntervalSince(playStart))]
      )
    } catch {
      if fallbackToPreviewAfterAppleMusicFailure(
        error,
        resolvedTrack: resolvedTrack,
        originalTrack: track,
        attemptID: attemptID,
        failedPhase: "play"
      ) {
        return
      }

      throw error
    }

    currentTrack = resolvedTrack
    activeBackend = .appleMusic
    state = .playing
    updateNowPlayingInfo(for: resolvedTrack)
    updateNowPlayingPlaybackRate(1)
    startMusicProgressTimer(duration: resolvedTrack.duration)
    endBackgroundContinuationTask(reason: "apple_music_started")
  }

  private func fallbackToPreviewAfterAppleMusicFailure(
    _ error: Error,
    resolvedTrack: Track,
    originalTrack: Track,
    attemptID: String,
    failedPhase: String
  ) -> Bool {
    guard let previewURL = resolvedTrack.previewURL ?? originalTrack.previewURL else {
      diagnostics?.record(
        .error,
        chain: .playbackAppleMusic,
        event: "apple_music_failed",
        message: "完整歌曲播放失败，且没有可用试听片段。",
        correlationID: attemptID,
        payload: DiagnosticsPayload.merge(
          ["failed_phase": failedPhase],
          DiagnosticsPayload.track(resolvedTrack),
          DiagnosticsPayload.error(error)
        )
      )
      return false
    }

    currentTrack = resolvedTrack
    lastErrorMessage = "完整歌曲暂时不可用，已切换到试听片段。"
    diagnostics?.record(
      .warning,
      chain: .playbackPreview,
      event: "fallback_preview",
      message: "完整歌曲暂时不可用，已切换到试听片段。",
      correlationID: attemptID,
      payload: DiagnosticsPayload.merge(
        ["failed_phase": failedPhase],
        DiagnosticsPayload.track(resolvedTrack),
        DiagnosticsPayload.error(error)
      )
    )
    startPreviewPlayback(
      for: resolvedTrack,
      previewURL: previewURL,
      correlationID: attemptID,
      reason: "apple_music_\(failedPhase)_fallback"
    )
    return true
  }

  private func startPreviewPlayback(
    for track: Track,
    previewURL: URL,
    correlationID: String? = nil,
    reason: String = "direct_preview",
    initialVolume: Float = 1.0
  ) {
    didNotifyTrackFinished = false
    didNotifyTrackTransitionWindow = false
    let item = AVPlayerItem(url: previewURL)
    trackPreviewPlayer.volume = initialVolume
    trackPreviewPlayer.replaceCurrentItem(with: item)
    addTrackPeriodicTimeObserver()
    addTrackPlaybackItemObservers(for: item, mediaKind: .track(track, correlationID))
    trackPreviewPlayer.play()
    endBackgroundContinuationTask(reason: "preview_started")

    if currentSpeech == nil {
      activeBackend = .localPreview
    }
    state = .playing
    updateNowPlayingInfo(for: track)
    updateNowPlayingPlaybackRate(1)
    diagnostics?.record(
      .notice,
      chain: .playbackPreview,
      event: "preview_play_start",
      message: "试听片段播放已启动。",
      correlationID: correlationID,
      payload: DiagnosticsPayload.merge(
        ["reason": reason],
        DiagnosticsPayload.track(track),
        DiagnosticsPayload.url(previewURL)
      )
    )
  }

  private func startSpeechPlayback(_ speech: RadioSpeechPlaybackSegment, mode: RadioSpeechPlaybackMode) {
    lastErrorMessage = nil
    currentSpeechPlaybackMode = mode
    currentOverlayTiming = overlayTiming(for: mode)
    didNotifySpeechFinished = false
    didNotifySpeechAdvancePoint = false
    speechStartTask?.cancel()
    if mode == .standalone {
      state = .loading
      stopCurrentPlayback(clearCurrentTrack: false, clearCurrentSpeech: false)
    } else {
      state = .playing
      startTrackPreviewVolumeRamp(to: currentOverlayTiming.duckVolume, duration: currentOverlayTiming.fadeDuration)
    }
    currentSpeech = speech
    currentSpeechCue = initialSpeechCue(
      for: speech,
      spokenText: speech.text.trimmedNilIfEmpty ?? speech.displayText
    )
    synthesizedSpeechCueRanges = []
    if mode == .standalone {
      resetPlaybackProgress()
    }

    if mode == .transitionOverlay {
      let delay = currentOverlayTiming.speechDelay
      speechStartTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(delay))
        guard !Task.isCancelled else { return }
        await MainActor.run {
          self?.beginSpeechOutput(for: speech)
        }
      }
    } else {
      beginSpeechOutput(for: speech)
    }
  }

  private func beginSpeechOutput(for speech: RadioSpeechPlaybackSegment) {
    if let audioURL = speech.playableAudioURL {
      startSpeechAudioPlayback(for: speech, audioURL: audioURL)
    } else {
      startSynthesizedSpeechPlayback(for: speech)
    }
  }

  private func startSpeechAudioPlayback(for speech: RadioSpeechPlaybackSegment, audioURL: URL) {
    didNotifySpeechFinished = false
    let item = AVPlayerItem(url: audioURL)
    speechAudioPlayer.replaceCurrentItem(with: item)
    addSpeechPeriodicTimeObserver()
    addSpeechPlaybackItemObservers(for: item, mediaKind: .speech(speech))
    speechAudioPlayer.play()
    endBackgroundContinuationTask(reason: "speech_audio_started")

    activeBackend = .speechAudio
    state = .playing
    updateNowPlayingInfo(for: speech)
    updateNowPlayingPlaybackRate(1)
    diagnostics?.record(
      .notice,
      chain: .playbackSpeech,
      event: "speech_audio_start",
      message: "主持人语音音频播放已启动。",
      payload: [
        "speech_id_hash": DiagnosticsRedactor.hash(speech.id),
        "duration_seconds": String(Int((speech.audio?.durationSeconds ?? 0).rounded()))
      ]
    )
  }

  private func startSynthesizedSpeechPlayback(for speech: RadioSpeechPlaybackSegment) {
    let spokenText = speech.text.isEmpty ? speech.displayText : speech.text
    guard !spokenText.isEmpty else {
      finishPlayback(kind: .speech)
      return
    }

    didNotifySpeechFinished = false
    synthesizedSpeechCueRanges = cueRanges(for: speech, spokenText: spokenText)
    currentSpeechCue = synthesizedSpeechCueRanges.first?.cue ?? initialSpeechCue(for: speech, spokenText: spokenText)
    let utterance = AVSpeechUtterance(string: spokenText)
    utterance.voice = Self.preferredSpeechVoice(for: spokenText)
    utterance.rate = Self.speechRate(for: spokenText)
    utterance.preUtteranceDelay = 0.08
    utterance.postUtteranceDelay = 0.12
    speechSynthesizer.speak(utterance)
    endBackgroundContinuationTask(reason: "speech_synthesis_started")

    activeBackend = .speechSynthesis
    state = .playing
    updateNowPlayingInfo(for: speech)
    updateNowPlayingPlaybackRate(1)
    startSpeechProgressTimer(duration: speech.audio?.durationSeconds ?? Self.estimatedSpeechDuration(for: spokenText))
    diagnostics?.record(
      .notice,
      chain: .playbackSpeech,
      event: "speech_synthesis_start",
      message: "主持人语音合成播放已启动。",
      payload: [
        "speech_id_hash": DiagnosticsRedactor.hash(speech.id),
        "text_length": String(spokenText.count)
      ]
    )
  }

  private func resume() {
    switch activeBackend {
    case .appleMusic:
      playbackTask = Task { [weak self] in
        await self?.resumeAppleMusicPlayback()
      }
    case .localPreview:
      if trackPreviewPlayer.currentItem != nil {
        trackPreviewPlayer.play()
        state = .playing
        updateNowPlayingPlaybackRate(1)
      } else if let currentTrack {
        play(track: currentTrack)
      } else if let currentSpeech {
        playSpeech(currentSpeech)
      }
    case .speechAudio:
      if trackPreviewPlayer.currentItem != nil {
        trackPreviewPlayer.play()
      }
      if speechAudioPlayer.currentItem != nil {
        speechAudioPlayer.play()
        state = .playing
        updateNowPlayingPlaybackRate(1)
      } else if let currentSpeech {
        playSpeech(currentSpeech, mode: currentSpeechPlaybackMode)
      }
    case .speechSynthesis:
      if trackPreviewPlayer.currentItem != nil {
        trackPreviewPlayer.play()
      }
      if speechSynthesizer.continueSpeaking() {
        state = .playing
        updateNowPlayingPlaybackRate(1)
        startSpeechProgressTimer(duration: currentSpeech?.audio?.durationSeconds ?? 0)
      } else if let currentSpeech {
        playSpeech(currentSpeech)
      }
    case .none:
      if let currentTrack {
        play(track: currentTrack, policy: currentTrackPlaybackPolicy, preservesSpeech: false)
      } else if let currentSpeech {
        playSpeech(currentSpeech, mode: currentSpeechPlaybackMode)
      }
    }
  }

  private func resumeAppleMusicPlayback() async {
    do {
      try await musicPlayer.play()
      state = .playing
      updateNowPlayingPlaybackRate(1)
      startMusicProgressTimer(duration: currentTrack?.duration ?? 0)
      diagnostics?.record(
        .notice,
        chain: .playbackAppleMusic,
        event: "resume_success",
        message: "完整歌曲播放已恢复。",
        correlationID: currentPlaybackAttemptID
      )
    } catch {
      failPlayback(error, failedPhase: "resume", correlationID: currentPlaybackAttemptID)
    }
  }

  private func stopCurrentPlayback(clearCurrentTrack: Bool, clearCurrentSpeech: Bool = true) {
    stopTrackPlayback(clearCurrentTrack: clearCurrentTrack)
    stopSpeechPlayback(clearCurrentSpeech: clearCurrentSpeech)
    musicPlayer.stop()

    activeBackend = .none
    state = .idle
    resetPlaybackProgress()
    stopMusicProgressTimer()
    endBackgroundContinuationTask(reason: "playback_stopped")
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
  }

  private func stopTrackPlayback(clearCurrentTrack: Bool) {
    trackVolumeRampTask?.cancel()
    trackPreviewPlayer.pause()
    trackPreviewPlayer.replaceCurrentItem(with: nil)
    trackPreviewPlayer.volume = 1.0
    musicPlayer.stop()
    didNotifyTrackFinished = false
    didNotifyTrackTransitionWindow = false
    removeTrackPeriodicTimeObserver()
    removeTrackPlaybackItemObservers()
    stopMusicProgressTimer()
    if clearCurrentTrack {
      currentTrack = nil
    }
  }

  private func stopSpeechPlayback(clearCurrentSpeech: Bool) {
    speechStartTask?.cancel()
    speechAudioPlayer.pause()
    speechAudioPlayer.replaceCurrentItem(with: nil)
    speechSynthesizer.stopSpeaking(at: .immediate)
    didNotifySpeechFinished = false
    didNotifySpeechAdvancePoint = false
    removeSpeechPeriodicTimeObserver()
    removeSpeechPlaybackItemObservers()
    stopSpeechProgressTimer()
    if clearCurrentSpeech {
      currentSpeech = nil
      currentSpeechCue = nil
      synthesizedSpeechCueRanges = []
      currentSpeechPlaybackMode = .standalone
    }
  }

  private func addTrackPeriodicTimeObserver() {
    removeTrackPeriodicTimeObserver()

    let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    trackTimeObserverToken = trackPreviewPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
      Task { @MainActor in
        self?.updateTrackPlaybackProgress(for: time)
      }
    }
  }

  private func removeTrackPeriodicTimeObserver() {
    guard let trackTimeObserverToken else { return }
    trackPreviewPlayer.removeTimeObserver(trackTimeObserverToken)
    self.trackTimeObserverToken = nil
  }

  private func addSpeechPeriodicTimeObserver() {
    removeSpeechPeriodicTimeObserver()

    let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    speechTimeObserverToken = speechAudioPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
      Task { @MainActor in
        self?.updateSpeechPlaybackProgress(for: time)
      }
    }
  }

  private func removeSpeechPeriodicTimeObserver() {
    guard let speechTimeObserverToken else { return }
    speechAudioPlayer.removeTimeObserver(speechTimeObserverToken)
    self.speechTimeObserverToken = nil
  }

  private func addTrackPlaybackItemObservers(for item: AVPlayerItem, mediaKind: PlaybackMediaKind) {
    removeTrackPlaybackItemObservers()

    trackEndObserverToken = NotificationCenter.default.addObserver(
      forName: AVPlayerItem.didPlayToEndTimeNotification,
      object: item,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.handleFinishedTrackPlayerItem()
      }
    }

    trackFailedItemObserverToken = NotificationCenter.default.addObserver(
      forName: AVPlayerItem.failedToPlayToEndTimeNotification,
      object: item,
      queue: .main
    ) { [weak self] notification in
      Task { @MainActor in
        let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
          ?? item.error
          ?? PlaybackControllerError.playerItemFailed
        self?.handleFailedPlayerItem(mediaKind: mediaKind, error: error)
      }
    }

    trackItemStatusObserver = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
      guard observedItem.status == .failed else { return }

      Task { @MainActor in
        self?.handleFailedPlayerItem(
          mediaKind: mediaKind,
          error: observedItem.error ?? PlaybackControllerError.playerItemFailed
        )
      }
    }
  }

  private func removeTrackPlaybackItemObservers() {
    if let trackEndObserverToken {
      NotificationCenter.default.removeObserver(trackEndObserverToken)
      self.trackEndObserverToken = nil
    }
    if let trackFailedItemObserverToken {
      NotificationCenter.default.removeObserver(trackFailedItemObserverToken)
      self.trackFailedItemObserverToken = nil
    }
    trackItemStatusObserver?.invalidate()
    trackItemStatusObserver = nil
  }

  private func addSpeechPlaybackItemObservers(for item: AVPlayerItem, mediaKind: PlaybackMediaKind) {
    removeSpeechPlaybackItemObservers()

    speechEndObserverToken = NotificationCenter.default.addObserver(
      forName: AVPlayerItem.didPlayToEndTimeNotification,
      object: item,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.handleFinishedSpeechPlayerItem()
      }
    }

    speechFailedItemObserverToken = NotificationCenter.default.addObserver(
      forName: AVPlayerItem.failedToPlayToEndTimeNotification,
      object: item,
      queue: .main
    ) { [weak self] notification in
      Task { @MainActor in
        let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
          ?? item.error
          ?? PlaybackControllerError.playerItemFailed
        self?.handleFailedPlayerItem(mediaKind: mediaKind, error: error)
      }
    }

    speechItemStatusObserver = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
      guard observedItem.status == .failed else { return }

      Task { @MainActor in
        self?.handleFailedPlayerItem(
          mediaKind: mediaKind,
          error: observedItem.error ?? PlaybackControllerError.playerItemFailed
        )
      }
    }
  }

  private func removeSpeechPlaybackItemObservers() {
    if let speechEndObserverToken {
      NotificationCenter.default.removeObserver(speechEndObserverToken)
      self.speechEndObserverToken = nil
    }
    if let speechFailedItemObserverToken {
      NotificationCenter.default.removeObserver(speechFailedItemObserverToken)
      self.speechFailedItemObserverToken = nil
    }
    speechItemStatusObserver?.invalidate()
    speechItemStatusObserver = nil
  }

  private func handleFailedPlayerItem(mediaKind: PlaybackMediaKind, error: Error) {
    switch mediaKind {
    case let .track(track, correlationID):
      currentTrack = track
      failPlayback(error, failedPhase: "preview_item_failed", correlationID: correlationID)
    case let .speech(speech):
      diagnostics?.record(
        .warning,
        chain: .playbackSpeech,
        event: "speech_audio_failed",
        message: "主持人语音音频播放失败，切换到系统语音合成。",
        payload: DiagnosticsPayload.merge(
          ["speech_id_hash": DiagnosticsRedactor.hash(speech.id)],
          DiagnosticsPayload.error(error)
        )
      )
      removeSpeechPlaybackItemObservers()
      removeSpeechPeriodicTimeObserver()
      speechAudioPlayer.replaceCurrentItem(with: nil)
      startSynthesizedSpeechPlayback(for: speech)
    }
  }

  private func handleFinishedTrackPlayerItem() {
    guard state == .playing else { return }

    if onPlaybackFinished != nil || onTrackFinished != nil {
      finishPlayback(kind: .track)
      return
    }

    trackPreviewPlayer.seek(to: .zero)
    resetPlaybackProgress()
    trackPreviewPlayer.play()
    updateNowPlayingPlaybackRate(1)
  }

  private func handleFinishedSpeechPlayerItem() {
    guard state == .playing else { return }
    finishPlayback(kind: .speech)
  }

  private func startMusicProgressTimer(duration: TimeInterval) {
    stopMusicProgressTimer()

    musicProgressTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))

        await MainActor.run {
          guard
            let self,
            self.activeBackend == .appleMusic,
            self.state == .playing
          else { return }

          let observedSeconds = self.currentPlaybackSeconds()
          let playbackStatus = self.musicPlayer.state.playbackStatus
          if playbackStatus == .stopped, self.elapsedSeconds > observedSeconds {
            // ApplicationMusicPlayer may reset playbackTime before the completion tick runs.
          } else {
            self.elapsedSeconds = observedSeconds
          }
          self.updateMusicPlaybackProgress(duration: duration)
        }
      }
    }
  }

  private func stopMusicProgressTimer() {
    musicProgressTask?.cancel()
    musicProgressTask = nil
  }

  private func startSpeechProgressTimer(duration: TimeInterval) {
    stopSpeechProgressTimer()
    guard duration > 0 else { return }

    speechProgressTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(0.5))

        await MainActor.run {
          guard
            let self,
            self.activeBackend == .speechSynthesis,
            self.state == .playing
          else { return }

          self.elapsedSeconds += 0.5
          self.elapsedTimeText = Self.timeText(for: self.elapsedSeconds)
          self.playbackProgress = min(max(self.elapsedSeconds / duration, 0), 1)
          if let currentSpeech = self.currentSpeech, self.currentSpeechCue == nil {
            self.updateCurrentSpeechCue(for: self.elapsedSeconds, speech: currentSpeech)
          }
          self.notifySpeechAdvancePointIfNeeded(elapsedSeconds: self.elapsedSeconds, duration: duration)
        }
      }
    }
  }

  private func stopSpeechProgressTimer() {
    speechProgressTask?.cancel()
    speechProgressTask = nil
  }

  private func updateTrackPlaybackProgress(for time: CMTime) {
    let elapsedSeconds = time.seconds.isFinite ? max(0, time.seconds) : 0
    if activeBackend == .localPreview {
      self.elapsedSeconds = elapsedSeconds
    }

    let newElapsedTimeText = Self.timeText(for: elapsedSeconds)
    if activeBackend == .localPreview, elapsedTimeText != newElapsedTimeText {
      elapsedTimeText = newElapsedTimeText
    }

    guard
      let duration = trackDurationForCurrentPreview(),
      duration.isFinite,
      duration > 0
    else {
      if activeBackend == .localPreview {
        playbackProgress = 0
      }
      return
    }

    if activeBackend == .localPreview {
      playbackProgress = min(max(elapsedSeconds / duration, 0), 1)
    }
    notifyTrackTransitionWindowIfNeeded(elapsedSeconds: elapsedSeconds, duration: duration)
  }

  private func updateSpeechPlaybackProgress(for time: CMTime) {
    let elapsedSeconds = time.seconds.isFinite ? max(0, time.seconds) : 0
    self.elapsedSeconds = elapsedSeconds

    let newElapsedTimeText = Self.timeText(for: elapsedSeconds)
    if elapsedTimeText != newElapsedTimeText {
      elapsedTimeText = newElapsedTimeText
    }
    if let currentSpeech {
      updateCurrentSpeechCue(for: elapsedSeconds, speech: currentSpeech)
    }

    guard let currentSpeech else {
      playbackProgress = 0
      return
    }
    let duration = speechDuration(for: speechAudioPlayer.currentItem, speech: currentSpeech)
    playbackProgress = min(max(elapsedSeconds / duration, 0), 1)
    notifySpeechAdvancePointIfNeeded(elapsedSeconds: elapsedSeconds, duration: duration)
  }

  private func updateMusicPlaybackProgress(duration: TimeInterval) {
    elapsedTimeText = Self.timeText(for: elapsedSeconds)

    guard duration > 0 else {
      playbackProgress = 0
      return
    }

    playbackProgress = min(max(elapsedSeconds / duration, 0), 1)
    notifyTrackTransitionWindowIfNeeded(elapsedSeconds: elapsedSeconds, duration: duration)

    let wallClockElapsed = currentPlaybackStartedAt.map { Date().timeIntervalSince($0) } ?? elapsedSeconds
    let musicPlayerStoppedAtEnd = musicPlayer.state.playbackStatus == .stopped
      && wallClockElapsed >= max(1, duration - 2)

    if (playbackProgress >= 0.995 || musicPlayerStoppedAtEnd), !didNotifyTrackFinished {
      finishPlayback(kind: .track)
    }
  }

  private func trackDurationForCurrentPreview() -> TimeInterval? {
    if let duration = trackPreviewPlayer.currentItem?.duration.seconds,
       duration.isFinite,
       duration > 0 {
      return duration
    }
    guard let duration = currentTrack?.duration, duration > 0 else { return nil }
    return duration
  }

  private func speechDuration(
    for item: AVPlayerItem?,
    speech: RadioSpeechPlaybackSegment
  ) -> TimeInterval {
    if let duration = item?.duration.seconds,
       duration.isFinite,
       duration > 0 {
      return duration
    }
    if let duration = speech.audio?.durationSeconds, duration > 0 {
      return duration
    }
    return Self.estimatedSpeechDuration(for: speech.text.isEmpty ? speech.displayText : speech.text)
  }

  private func notifyTrackTransitionWindowIfNeeded(elapsedSeconds: TimeInterval, duration: TimeInterval) {
    guard currentTrackPlaybackPolicy == .mixablePreferred else { return }
    guard !didNotifyTrackTransitionWindow else { return }
    guard duration > 0, duration - elapsedSeconds <= 3.0 else { return }
    didNotifyTrackTransitionWindow = true
    beginBackgroundContinuationTask(reason: "track_transition_window")
    onTrackTransitionWindowReached?()
  }

  private func notifySpeechAdvancePointIfNeeded(elapsedSeconds: TimeInterval, duration: TimeInterval) {
    guard currentSpeechPlaybackMode == .transitionOverlay else { return }
    guard !didNotifySpeechAdvancePoint else { return }
    guard duration > 0, elapsedSeconds / duration >= currentOverlayTiming.advanceRatio else { return }
    didNotifySpeechAdvancePoint = true
    onSpeechAdvancePointReached?()
  }

  private func updateCurrentSpeechCue(for elapsedSeconds: TimeInterval, speech: RadioSpeechPlaybackSegment) {
    let cues = speechCues(for: speech, spokenText: speech.text)
    guard !cues.isEmpty else {
      currentSpeechCue = nil
      return
    }

    let cue = cues.last { cue in
      elapsedSeconds >= cue.startTime && elapsedSeconds < cue.endTime
    } ?? cues.last { cue in
      elapsedSeconds >= cue.startTime
    } ?? cues.first

    if currentSpeechCue?.id != cue?.id {
      currentSpeechCue = cue
    }
  }

  private func updateSynthesizedSpeechCue(for range: NSRange, spokenText: String) {
    guard !synthesizedSpeechCueRanges.isEmpty else { return }
    let cueRange = synthesizedSpeechCueRanges.first { cueRange in
      NSIntersectionRange(cueRange.range, range).length > 0 || cueRange.range.location <= range.location
        && range.location < cueRange.range.location + cueRange.range.length
    }
    guard let cueRange, currentSpeechCue?.id != cueRange.cue.id else { return }
    currentSpeechCue = cueRange.cue
  }

  private func initialSpeechCue(
    for speech: RadioSpeechPlaybackSegment,
    spokenText: String
  ) -> RadioSpeechCue? {
    speechCues(for: speech, spokenText: spokenText).first
  }

  private func speechCues(
    for speech: RadioSpeechPlaybackSegment,
    spokenText: String
  ) -> [RadioSpeechCue] {
    if !speech.timedCues.isEmpty {
      return speech.timedCues
    }
    let fallbackText = spokenText.trimmedNilIfEmpty ?? speech.displayText.trimmedNilIfEmpty ?? speech.text
    return Self.fallbackSpeechCues(for: fallbackText, speechID: speech.id)
  }

  private func cueRanges(
    for speech: RadioSpeechPlaybackSegment,
    spokenText: String
  ) -> [SpeechCueRange] {
    let cues = speechCues(for: speech, spokenText: spokenText)
    guard !cues.isEmpty else { return [] }

    var cursor = spokenText.startIndex
    return cues.compactMap { cue in
      let cueText = cue.text.trimmedNilIfEmpty ?? cue.displayText.trimmedNilIfEmpty
      guard let cueText else { return nil }
      let searchRange = cursor..<spokenText.endIndex
      guard let range = spokenText.range(of: cueText, options: [], range: searchRange)
        ?? spokenText.range(of: cueText)
      else { return nil }
      cursor = range.upperBound
      return SpeechCueRange(cue: cue, range: NSRange(range, in: spokenText))
    }
  }

  private static func fallbackSpeechCues(for text: String, speechID: String) -> [RadioSpeechCue] {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let spans = sentenceSpans(in: trimmed)
    return spans.enumerated().map { index, range in
      let sentence = String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines)
      return RadioSpeechCue(
        id: "\(speechID)-fallback-cue-\(index + 1)",
        text: sentence,
        displayText: sentence,
        startTime: 0,
        endTime: 0,
        words: []
      )
    }
  }

  private static func sentenceSpans(in text: String) -> [Range<String.Index>] {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }

    var ranges: [Range<String.Index>] = []
    var start = trimmed.startIndex
    var index = start
    while index < trimmed.endIndex {
      let next = trimmed.index(after: index)
      if ".!?。！？".contains(trimmed[index]) {
        ranges.append(start..<next)
        start = next
      }
      index = next
    }
    if start < trimmed.endIndex {
      ranges.append(start..<trimmed.endIndex)
    }
    return ranges.isEmpty ? [trimmed.startIndex..<trimmed.endIndex] : ranges
  }

  private func overlayTiming(for mode: RadioSpeechPlaybackMode) -> RadioTransitionOverlayTiming {
    guard mode == .transitionOverlay else { return .automatic }
    return didNotifyTrackTransitionWindow ? .automatic : .manual
  }

  private func startTrackPreviewVolumeRamp(to targetVolume: Float, duration: TimeInterval) {
    trackVolumeRampTask?.cancel()
    guard trackPreviewPlayer.currentItem != nil else { return }
    let startVolume = trackPreviewPlayer.volume
    guard duration > 0 else {
      trackPreviewPlayer.volume = targetVolume
      return
    }

    trackVolumeRampTask = Task { [weak self] in
      let steps = max(1, Int(duration / 0.05))
      for step in 1...steps {
        guard !Task.isCancelled else { return }
        let progress = Float(step) / Float(steps)
        let volume = startVolume + (targetVolume - startVolume) * progress
        await MainActor.run {
          self?.trackPreviewPlayer.volume = volume
        }
        try? await Task.sleep(for: .milliseconds(50))
      }
      await MainActor.run {
        self?.trackPreviewPlayer.volume = targetVolume
      }
    }
  }

  private func resetPlaybackProgress() {
    playbackProgress = 0
    elapsedSeconds = 0
    elapsedTimeText = "0:00"
  }

  private func failPlayback(_ error: Error) {
    failPlayback(error, failedPhase: "unknown", correlationID: currentPlaybackAttemptID)
  }

  private func failPlayback(_ error: Error, failedPhase: String, correlationID: String?) {
    let failureChain: DiagnosticLogChain = activeBackend == .localPreview
      ? .playbackPreview
      : .playbackAppleMusic
    lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    state = .failed
    activeBackend = .none
    currentSpeechCue = nil
    synthesizedSpeechCueRanges = []
    trackPreviewPlayer.pause()
    trackPreviewPlayer.replaceCurrentItem(with: nil)
    removeTrackPlaybackItemObservers()
    removeTrackPeriodicTimeObserver()
    stopMusicProgressTimer()
    updateNowPlayingPlaybackRate(0)
    beginBackgroundContinuationTask(reason: "playback_failed")
    diagnostics?.record(
      .error,
      chain: failureChain,
      event: "attempt_failed",
      message: "播放失败。",
      correlationID: correlationID,
      payload: DiagnosticsPayload.merge(
        ["failed_phase": failedPhase],
        currentTrack.map(DiagnosticsPayload.track) ?? [:],
        DiagnosticsPayload.error(error)
      )
    )

    guard let currentTrack, !didNotifyPlaybackFailed else { return }
    didNotifyPlaybackFailed = true
    onPlaybackFailed?(
      PlaybackFailureContext(
        track: currentTrack,
        phase: failedPhase,
        message: lastErrorMessage ?? "Playback failed."
      )
    )
  }

  private func finishSynthesizedSpeech() {
    guard activeBackend == .speechSynthesis else { return }
    finishPlayback(kind: .speech)
  }

  private func finishPlayback(kind: PlaybackCompletionKind) {
    switch kind {
    case .track:
      guard !didNotifyTrackFinished else { return }
      didNotifyTrackFinished = true
      beginBackgroundContinuationTask(reason: "track_finished")
      removeTrackPlaybackItemObservers()
      removeTrackPeriodicTimeObserver()
      stopMusicProgressTimer()
      if currentSpeech == nil {
        state = .idle
        updateNowPlayingPlaybackRate(0)
      }
    case .speech:
      guard !didNotifySpeechFinished else { return }
      didNotifySpeechFinished = true
      beginBackgroundContinuationTask(reason: "speech_finished")
      speechStartTask?.cancel()
      removeSpeechPlaybackItemObservers()
      removeSpeechPeriodicTimeObserver()
      stopSpeechProgressTimer()
      currentSpeech = nil
      currentSpeechCue = nil
      synthesizedSpeechCueRanges = []
      if trackPreviewPlayer.currentItem != nil {
        activeBackend = .localPreview
        state = .playing
        startTrackPreviewVolumeRamp(to: 1.0, duration: currentOverlayTiming.restoreDuration)
        updateNowPlayingPlaybackRate(1)
        endBackgroundContinuationTask(reason: "preview_resumed_after_speech")
      } else if let currentTrack, musicPlayer.state.playbackStatus == .playing {
        activeBackend = .appleMusic
        state = .playing
        startMusicProgressTimer(duration: currentTrack.duration)
        updateNowPlayingPlaybackRate(1)
        endBackgroundContinuationTask(reason: "apple_music_resumed_after_speech")
      } else {
        state = .idle
        updateNowPlayingPlaybackRate(0)
      }
    }
    diagnostics?.record(
      .notice,
      chain: activeBackend.diagnosticChain,
      event: "playback_complete",
      message: kind == .track ? "曲目播放完成。" : "主持人语音播放完成。",
      correlationID: currentPlaybackAttemptID,
      payload: [
        "completion_kind": kind.diagnosticValue,
        "elapsed_seconds": String(Int(elapsedSeconds.rounded()))
      ]
    )

    onPlaybackFinished?(kind)
    if kind == .track {
      onTrackFinished?()
    }
  }

  private func configureAudioSession() {
    do {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(.playback, mode: .default, options: [.allowAirPlay])
      try audioSession.setActive(true)
      diagnostics?.record(
        .info,
        chain: .audioSession,
        event: "configure_success",
        message: "音频会话配置完成。",
        payload: ["category": "playback", "active": "true"]
      )
    } catch {
      lastErrorMessage = error.localizedDescription
      state = .failed
      diagnostics?.record(
        .error,
        chain: .audioSession,
        event: "configure_failed",
        message: "音频会话配置失败。",
        payload: DiagnosticsPayload.error(error)
      )
    }
  }

  private func beginBackgroundContinuationTask(reason: String) {
    guard backgroundContinuationTask == .invalid else { return }

    backgroundContinuationReason = reason
    backgroundContinuationTask = UIApplication.shared.beginBackgroundTask(withName: "AirsetPlaybackContinuation") { [weak self] in
      Task { @MainActor in
        self?.endBackgroundContinuationTask(reason: "expired")
      }
    }

    guard backgroundContinuationTask != .invalid else {
      backgroundContinuationReason = nil
      diagnostics?.record(
        .warning,
        chain: .audioSession,
        event: "background_continuation_unavailable",
        message: "无法申请后台播放交接时间。",
        payload: ["reason": reason]
      )
      return
    }

    diagnostics?.record(
      .info,
      chain: .audioSession,
      event: "background_continuation_begin",
      message: "已申请后台播放交接时间。",
      payload: ["reason": reason]
    )
  }

  private func endBackgroundContinuationTask(reason: String) {
    guard backgroundContinuationTask != .invalid else { return }

    let task = backgroundContinuationTask
    let startReason = backgroundContinuationReason ?? "unknown"
    backgroundContinuationTask = .invalid
    backgroundContinuationReason = nil
    UIApplication.shared.endBackgroundTask(task)
    diagnostics?.record(
      .info,
      chain: .audioSession,
      event: "background_continuation_end",
      message: "后台播放交接时间已结束。",
      payload: [
        "reason": reason,
        "start_reason": startReason
      ]
    )
  }

  private func configureRemoteCommands() {
    let commandCenter = MPRemoteCommandCenter.shared()

    commandCenter.playCommand.addTarget { [weak self] _ in
      Task { @MainActor in
        self?.togglePlayback()
      }
      return .success
    }

    commandCenter.pauseCommand.addTarget { [weak self] _ in
      Task { @MainActor in
        self?.pause()
      }
      return .success
    }
  }

  private func updateNowPlayingInfo(for track: Track) {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = [
      MPMediaItemPropertyTitle: track.title,
      MPMediaItemPropertyArtist: track.artist,
      MPMediaItemPropertyAlbumTitle: track.album,
      MPMediaItemPropertyPlaybackDuration: track.duration,
      MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0
    ]
  }

  private func updateNowPlayingInfo(for speech: RadioSpeechPlaybackSegment) {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = [
      MPMediaItemPropertyTitle: "Airset Host",
      MPMediaItemPropertyArtist: speech.displayText,
      MPMediaItemPropertyAlbumTitle: "Airset Radio",
      MPMediaItemPropertyPlaybackDuration: speech.audio?.durationSeconds ?? 0,
      MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0
    ]
  }

  private func updateNowPlayingPlaybackRate(_ rate: Double) {
    var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = rate
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }

  private static func timeText(for seconds: TimeInterval) -> String {
    let totalSeconds = max(0, Int(seconds.rounded(.down)))
    return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
  }

  static func estimatedSpeechDuration(for text: String) -> TimeInterval {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return 1.2 }

    let hanCharacterCount = trimmed.reduce(0) { count, character in
      String(character).range(of: #"\p{Han}"#, options: .regularExpression) == nil ? count : count + 1
    }
    let latinWordCount = trimmed
      .replacingOccurrences(of: #"\p{Han}"#, with: " ", options: .regularExpression)
      .split { !$0.isLetter && !$0.isNumber }
      .count
    let punctuationPauseCount = trimmed.filter { "，,。.!！?？；;：:".contains($0) }.count

    let hanSeconds = Double(hanCharacterCount) / 4.6
    let latinSeconds = Double(latinWordCount) / 2.7
    let pauseSeconds = Double(punctuationPauseCount) * 0.12
    return max(1.2, hanSeconds + latinSeconds + pauseSeconds)
  }

  private static func preferredSpeechVoice(for text: String) -> AVSpeechSynthesisVoice? {
    let language = speechVoiceLanguage(for: text)
    let voices = AVSpeechSynthesisVoice.speechVoices().filter {
      $0.language.caseInsensitiveCompare(language) == .orderedSame
    }
    if let premiumVoice = voices.first(where: { $0.quality == .premium }) {
      return premiumVoice
    }
    if let enhancedVoice = voices.first(where: { $0.quality == .enhanced }) {
      return enhancedVoice
    }
    return voices.first ?? AVSpeechSynthesisVoice(language: language)
  }

  private static func speechRate(for text: String) -> Float {
    speechVoiceLanguage(for: text) == "zh-CN"
      ? AVSpeechUtteranceDefaultSpeechRate * 0.88
      : AVSpeechUtteranceDefaultSpeechRate * 0.94
  }

  private static func speechVoiceLanguage(for text: String) -> String {
    text.range(of: #"\p{Han}"#, options: .regularExpression) == nil ? "en-US" : "zh-CN"
  }
}

enum PlaybackBackend: String {
  case none
  case localPreview
  case appleMusic
  case speechAudio
  case speechSynthesis
}

private extension PlaybackBackend {
  var diagnosticChain: DiagnosticLogChain {
    switch self {
    case .appleMusic:
      .playbackAppleMusic
    case .localPreview:
      .playbackPreview
    case .speechAudio, .speechSynthesis:
      .playbackSpeech
    case .none:
      .audioSession
    }
  }
}

private extension PlaybackCompletionKind {
  var diagnosticValue: String {
    switch self {
    case .track:
      "track"
    case .speech:
      "speech"
    }
  }
}

private final class SpeechCompletionDelegate: NSObject, AVSpeechSynthesizerDelegate {
  var onFinish: (() -> Void)?
  var onSpeakRange: ((NSRange, AVSpeechUtterance) -> Void)?

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    onFinish?()
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    willSpeakRangeOfSpeechString characterRange: NSRange,
    utterance: AVSpeechUtterance
  ) {
    onSpeakRange?(characterRange, utterance)
  }
}

private extension String {
  var trimmedNilIfEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

private enum PlaybackError: LocalizedError {
  case appleMusicAccessDenied
  case appleMusicSubscriptionRequired

  var errorDescription: String? {
    switch self {
    case .appleMusicAccessDenied:
      "Apple Music access is required to play this track."
    case .appleMusicSubscriptionRequired:
      "An active Apple Music subscription is required to play catalog tracks."
    }
  }
}
