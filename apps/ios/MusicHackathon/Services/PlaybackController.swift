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
  @ObservationIgnored private let catalogService = AppleMusicCatalogService()
  @ObservationIgnored private var timeObserverToken: Any?
  @ObservationIgnored private var endObserverToken: NSObjectProtocol?
  @ObservationIgnored private var musicProgressTask: Task<Void, Never>?
  @ObservationIgnored private var speechProgressTask: Task<Void, Never>?
  @ObservationIgnored private var playbackTask: Task<Void, Never>?
  @ObservationIgnored private var didNotifyTrackFinished = false

  init() {
    self.musicAuthorization = MusicAuthorizationService()
    configureController()
  }

  init(musicAuthorization: MusicAuthorizationService) {
    self.musicAuthorization = musicAuthorization
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
    currentTrack = track
    currentSpeech = nil
    lastErrorMessage = nil
    state = .loading
    stopCurrentPlayback(clearCurrentTrack: false)
    resetPlaybackProgress()

    if track.appleMusicID != nil {
      do {
        try await startAppleMusicPlayback(for: track)
        return
      } catch {
        if track.previewURL == nil {
          failPlayback(error)
          return
        }

        lastErrorMessage = nil
      }
    }

    if let previewURL = track.previewURL {
      startPreviewPlayback(for: track, previewURL: previewURL)
    } else {
      do {
        try await startAppleMusicPlayback(for: track)
      } catch {
        failPlayback(error)
      }
    }
  }

  private func startAppleMusicPlayback(for track: Track) async throws {
    didNotifyTrackFinished = false
    try await musicAuthorization.ensureCatalogPlaybackReady()

    let song = try await catalogService.song(for: track)
    let resolvedTrack = AppleMusicCatalogService.track(from: song, fallback: track)
    musicPlayer.queue = [song]

    do {
      try await musicPlayer.prepareToPlay()
      try await musicPlayer.play()
    } catch {
      if let previewURL = resolvedTrack.previewURL ?? track.previewURL {
        currentTrack = resolvedTrack
        lastErrorMessage = "完整歌曲暂时不可用，已切换到试听片段。"
        startPreviewPlayback(for: resolvedTrack, previewURL: previewURL)
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

  private func startPreviewPlayback(for track: Track, previewURL: URL) {
    didNotifyTrackFinished = false
    let item = AVPlayerItem(url: previewURL)
    previewPlayer.replaceCurrentItem(with: item)
    addPeriodicTimeObserver()
    addPlaybackEndObserver(for: item)
    previewPlayer.play()

    activeBackend = .localPreview
    state = .playing
    updateNowPlayingInfo(for: track)
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
    } catch {
      failPlayback(error)
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
    lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    state = .failed
    activeBackend = .none
    stopMusicProgressTimer()
    updateNowPlayingPlaybackRate(0)
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

    onPlaybackFinished?(kind)
    if kind == .track {
      onTrackFinished?()
    }
  }

  private func configureAudioSession() {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowAirPlay])
    } catch {
      lastErrorMessage = error.localizedDescription
      state = .failed
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
