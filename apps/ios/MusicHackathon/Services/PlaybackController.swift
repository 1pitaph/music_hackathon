import AVFoundation
import MediaPlayer
import MusicKit
import Observation

enum PlaybackCompletionKind {
  case track
  case speech
}

@MainActor
protocol RadioPlaybackControlling: AnyObject {
  var onPlaybackFinished: ((PlaybackCompletionKind) -> Void)? { get set }

  func play(track: Track)
  func playSpeech(_ speech: RadioSpeechPlaybackSegment)
  func stop()
}

enum PlaybackState: String {
  case idle
  case loading
  case playing
  case paused
  case failed
}

@MainActor
@Observable
final class PlaybackController: RadioPlaybackControlling {
  var currentTrack: Track?
  var currentSpeech: RadioSpeechPlaybackSegment?
  var state: PlaybackState = .idle
  var lastErrorMessage: String?
  var playbackProgress: Double = 0
  var elapsedSeconds: TimeInterval = 0
  var elapsedTimeText: String = "0:00"
  var activeBackend: PlaybackBackend = .none
  var onPlaybackFinished: ((PlaybackCompletionKind) -> Void)?
  var onTrackFinished: (() -> Void)?

  @ObservationIgnored private let previewPlayer = AVPlayer()
  @ObservationIgnored private let musicPlayer = ApplicationMusicPlayer.shared
  @ObservationIgnored private let speechSynthesizer = AVSpeechSynthesizer()
  @ObservationIgnored private let speechCompletionDelegate = SpeechCompletionDelegate()
  @ObservationIgnored private let musicAuthorization: MusicAuthorizationService
  @ObservationIgnored private let diagnostics: DiagnosticsStore?
  @ObservationIgnored private let catalogService = AppleMusicCatalogService()
  @ObservationIgnored private var timeObserverToken: Any?
  @ObservationIgnored private var endObserverToken: NSObjectProtocol?
  @ObservationIgnored private var musicProgressTask: Task<Void, Never>?
  @ObservationIgnored private var speechProgressTask: Task<Void, Never>?
  @ObservationIgnored private var playbackTask: Task<Void, Never>?
  @ObservationIgnored private var didNotifyTrackFinished = false
  @ObservationIgnored private var currentPlaybackAttemptID: String?
  @ObservationIgnored private var currentPlaybackStartedAt: Date?

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
    speechSynthesizer.delegate = speechCompletionDelegate
    configureAudioSession()
    configureRemoteCommands()
  }

  deinit {
    timeObserverToken.map(previewPlayer.removeTimeObserver)

    if let endObserverToken {
      NotificationCenter.default.removeObserver(endObserverToken)
    }

    musicProgressTask?.cancel()
    speechProgressTask?.cancel()
    playbackTask?.cancel()
  }

  func play(track: Track) {
    playbackTask?.cancel()
    playbackTask = Task { [weak self] in
      await self?.startPlayback(for: track)
    }
  }

  func playSpeech(_ speech: RadioSpeechPlaybackSegment) {
    playbackTask?.cancel()
    startSpeechPlayback(speech)
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
    case .localPreview, .speechAudio:
      previewPlayer.pause()
    case .speechSynthesis:
      speechSynthesizer.pauseSpeaking(at: .word)
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
    case .localPreview, .speechAudio:
      let seconds = previewPlayer.currentTime().seconds
      return seconds.isFinite ? max(0, seconds) : 0
    case .speechSynthesis:
      return elapsedSeconds
    case .none:
      return 0
    }
  }

  private func startPlayback(for track: Track) async {
    let attemptID = UUID().uuidString
    currentPlaybackAttemptID = attemptID
    currentPlaybackStartedAt = Date()
    currentTrack = track
    currentSpeech = nil
    lastErrorMessage = nil
    state = .loading
    stopCurrentPlayback(clearCurrentTrack: false)
    resetPlaybackProgress()
    diagnostics?.record(
      .notice,
      chain: track.appleMusicID == nil ? .playbackPreview : .playbackAppleMusic,
      event: "attempt_start",
      message: "开始播放曲目。",
      correlationID: attemptID,
      payload: DiagnosticsPayload.track(track)
    )

    if track.appleMusicID != nil {
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
        reason: track.appleMusicID == nil ? "direct_preview" : "apple_music_fallback"
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
    let song: Song
    do {
      song = try await catalogService.song(for: track)
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

    let resolvedTrack = AppleMusicCatalogService.track(from: song, fallback: track)
    diagnostics?.record(
      .notice,
      chain: .musicCatalog,
      event: "resolve_success",
      message: "Apple Music 目录歌曲解析完成。",
      correlationID: attemptID,
      payload: DiagnosticsPayload.track(resolvedTrack)
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
    reason: String = "direct_preview"
  ) {
    didNotifyTrackFinished = false
    let item = AVPlayerItem(url: previewURL)
    previewPlayer.replaceCurrentItem(with: item)
    addPeriodicTimeObserver()
    addPlaybackEndObserver(for: item)
    previewPlayer.play()

    activeBackend = .localPreview
    state = .playing
    updateNowPlayingInfo(for: track)
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

  private func startSpeechPlayback(_ speech: RadioSpeechPlaybackSegment) {
    lastErrorMessage = nil
    state = .loading
    stopCurrentPlayback(clearCurrentTrack: false, clearCurrentSpeech: false)
    currentSpeech = speech
    resetPlaybackProgress()

    if let audioURL = speech.playableAudioURL {
      startSpeechAudioPlayback(for: speech, audioURL: audioURL)
    } else {
      startSynthesizedSpeechPlayback(for: speech)
    }
  }

  private func startSpeechAudioPlayback(for speech: RadioSpeechPlaybackSegment, audioURL: URL) {
    didNotifyTrackFinished = false
    let item = AVPlayerItem(url: audioURL)
    previewPlayer.replaceCurrentItem(with: item)
    addPeriodicTimeObserver()
    addPlaybackEndObserver(for: item)
    previewPlayer.play()

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

    didNotifyTrackFinished = false
    let utterance = AVSpeechUtterance(string: spokenText)
    utterance.voice = AVSpeechSynthesisVoice(language: Self.speechVoiceLanguage(for: spokenText))
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    speechSynthesizer.speak(utterance)

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
    case .localPreview, .speechAudio:
      if previewPlayer.currentItem != nil {
        previewPlayer.play()
        state = .playing
        updateNowPlayingPlaybackRate(1)
      } else if let currentTrack {
        play(track: currentTrack)
      } else if let currentSpeech {
        playSpeech(currentSpeech)
      }
    case .speechSynthesis:
      if speechSynthesizer.continueSpeaking() {
        state = .playing
        updateNowPlayingPlaybackRate(1)
        startSpeechProgressTimer(duration: currentSpeech?.audio?.durationSeconds ?? 0)
      } else if let currentSpeech {
        playSpeech(currentSpeech)
      }
    case .none:
      if let currentTrack {
        play(track: currentTrack)
      } else if let currentSpeech {
        playSpeech(currentSpeech)
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
    previewPlayer.pause()
    previewPlayer.replaceCurrentItem(with: nil)
    musicPlayer.stop()
    speechSynthesizer.stopSpeaking(at: .immediate)

    activeBackend = .none
    didNotifyTrackFinished = false
    state = .idle
    if clearCurrentTrack {
      currentTrack = nil
    }
    if clearCurrentSpeech {
      currentSpeech = nil
    }

    resetPlaybackProgress()
    removePeriodicTimeObserver()
    removePlaybackEndObserver()
    stopMusicProgressTimer()
    stopSpeechProgressTimer()
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
  }

  private func addPeriodicTimeObserver() {
    removePeriodicTimeObserver()

    let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    timeObserverToken = previewPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
      Task { @MainActor in
        self?.updatePlaybackProgress(for: time)
      }
    }
  }

  private func removePeriodicTimeObserver() {
    guard let timeObserverToken else { return }
    previewPlayer.removeTimeObserver(timeObserverToken)
    self.timeObserverToken = nil
  }

  private func addPlaybackEndObserver(for item: AVPlayerItem) {
    removePlaybackEndObserver()

    endObserverToken = NotificationCenter.default.addObserver(
      forName: AVPlayerItem.didPlayToEndTimeNotification,
      object: item,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.handleFinishedPlayerItem()
      }
    }
  }

  private func removePlaybackEndObserver() {
    guard let endObserverToken else { return }
    NotificationCenter.default.removeObserver(endObserverToken)
    self.endObserverToken = nil
  }

  private func handleFinishedPlayerItem() {
    guard state == .playing else { return }

    if activeBackend == .speechAudio {
      finishPlayback(kind: .speech)
      return
    }

    if onPlaybackFinished != nil || onTrackFinished != nil {
      finishPlayback(kind: .track)
      return
    }

    previewPlayer.seek(to: .zero)
    resetPlaybackProgress()
    previewPlayer.play()
    updateNowPlayingPlaybackRate(1)
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

          self.elapsedSeconds = self.currentPlaybackSeconds()
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
        }
      }
    }
  }

  private func stopSpeechProgressTimer() {
    speechProgressTask?.cancel()
    speechProgressTask = nil
  }

  private func updatePlaybackProgress(for time: CMTime) {
    let elapsedSeconds = time.seconds.isFinite ? max(0, time.seconds) : 0
    self.elapsedSeconds = elapsedSeconds

    let newElapsedTimeText = Self.timeText(for: elapsedSeconds)
    if elapsedTimeText != newElapsedTimeText {
      elapsedTimeText = newElapsedTimeText
    }

    guard
      let duration = previewPlayer.currentItem?.duration.seconds,
      duration.isFinite,
      duration > 0
    else {
      playbackProgress = 0
      return
    }

    playbackProgress = min(max(elapsedSeconds / duration, 0), 1)
  }

  private func updateMusicPlaybackProgress(duration: TimeInterval) {
    elapsedTimeText = Self.timeText(for: elapsedSeconds)

    guard duration > 0 else {
      playbackProgress = 0
      return
    }

    playbackProgress = min(max(elapsedSeconds / duration, 0), 1)

    if playbackProgress >= 0.995, !didNotifyTrackFinished {
      finishPlayback(kind: .track)
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
    lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    state = .failed
    activeBackend = .none
    stopMusicProgressTimer()
    updateNowPlayingPlaybackRate(0)
    diagnostics?.record(
      .error,
      chain: .playbackAppleMusic,
      event: "attempt_failed",
      message: "播放失败。",
      correlationID: correlationID,
      payload: DiagnosticsPayload.merge(
        ["failed_phase": failedPhase],
        currentTrack.map(DiagnosticsPayload.track) ?? [:],
        DiagnosticsPayload.error(error)
      )
    )
  }

  private func finishSynthesizedSpeech() {
    guard activeBackend == .speechSynthesis else { return }
    finishPlayback(kind: .speech)
  }

  private func finishPlayback(kind: PlaybackCompletionKind) {
    guard !didNotifyTrackFinished else { return }
    didNotifyTrackFinished = true
    state = .idle
    updateNowPlayingPlaybackRate(0)
    stopSpeechProgressTimer()
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
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowAirPlay])
      diagnostics?.record(
        .info,
        chain: .audioSession,
        event: "configure_success",
        message: "音频会话配置完成。",
        payload: ["category": "playback"]
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

  private static func estimatedSpeechDuration(for text: String) -> TimeInterval {
    let wordCount = max(1, text.split(separator: " ").count)
    return max(1.2, Double(wordCount) / 2.7)
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

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    onFinish?()
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
