import AVFoundation
import MediaPlayer
import MusicKit
import Observation

enum PlaybackState: String {
  case idle
  case loading
  case playing
  case paused
  case failed
}

@MainActor
@Observable
final class PlaybackController {
  var currentTrack: Track?
  var state: PlaybackState = .idle
  var lastErrorMessage: String?
  var playbackProgress: Double = 0
  var elapsedSeconds: TimeInterval = 0
  var elapsedTimeText: String = "0:00"
  var activeBackend: PlaybackBackend = .none
  var onTrackFinished: (() -> Void)?

  @ObservationIgnored private let previewPlayer = AVPlayer()
  @ObservationIgnored private let musicPlayer = ApplicationMusicPlayer.shared
  @ObservationIgnored private let catalogService = AppleMusicCatalogService()
  @ObservationIgnored private var timeObserverToken: Any?
  @ObservationIgnored private var endObserverToken: NSObjectProtocol?
  @ObservationIgnored private var musicProgressTask: Task<Void, Never>?
  @ObservationIgnored private var playbackTask: Task<Void, Never>?
  @ObservationIgnored private var didNotifyTrackFinished = false

  init() {
    configureAudioSession()
    configureRemoteCommands()
  }

  deinit {
    timeObserverToken.map(previewPlayer.removeTimeObserver)

    if let endObserverToken {
      NotificationCenter.default.removeObserver(endObserverToken)
    }

    musicProgressTask?.cancel()
    playbackTask?.cancel()
  }

  func play(track: Track) {
    playbackTask?.cancel()
    playbackTask = Task { [weak self] in
      await self?.startPlayback(for: track)
    }
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
    case .localPreview:
      previewPlayer.pause()
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
      let seconds = previewPlayer.currentTime().seconds
      return seconds.isFinite ? max(0, seconds) : 0
    case .none:
      return 0
    }
  }

  private func startPlayback(for track: Track) async {
    currentTrack = track
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
    let authorizedStatus = MusicAuthorization.currentStatus == .authorized
      ? MusicAuthorization.currentStatus
      : await MusicAuthorization.request()
    guard authorizedStatus == .authorized else {
      throw PlaybackError.appleMusicAccessDenied
    }

    let subscription = try await MusicSubscription.current
    guard subscription.canPlayCatalogContent else {
      throw PlaybackError.appleMusicSubscriptionRequired
    }

    let song = try await catalogService.song(for: track)
    musicPlayer.queue = [song]
    try await musicPlayer.play()

    activeBackend = .appleMusic
    state = .playing
    updateNowPlayingInfo(for: track)
    updateNowPlayingPlaybackRate(1)
    startMusicProgressTimer(duration: track.duration)
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

  private func resume() {
    switch activeBackend {
    case .appleMusic:
      playbackTask = Task { [weak self] in
        await self?.resumeAppleMusicPlayback()
      }
    case .localPreview:
      if previewPlayer.currentItem != nil {
        previewPlayer.play()
        state = .playing
        updateNowPlayingPlaybackRate(1)
      } else if let currentTrack {
        play(track: currentTrack)
      }
    case .none:
      if let currentTrack {
        play(track: currentTrack)
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

  private func stopCurrentPlayback(clearCurrentTrack: Bool) {
    previewPlayer.pause()
    previewPlayer.replaceCurrentItem(with: nil)
    musicPlayer.stop()

    activeBackend = .none
    didNotifyTrackFinished = false
    state = .idle
    if clearCurrentTrack {
      currentTrack = nil
    }

    resetPlaybackProgress()
    removePeriodicTimeObserver()
    removePlaybackEndObserver()
    stopMusicProgressTimer()
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
        self?.restartFinishedPreviewIfNeeded()
      }
    }
  }

  private func removePlaybackEndObserver() {
    guard let endObserverToken else { return }
    NotificationCenter.default.removeObserver(endObserverToken)
    self.endObserverToken = nil
  }

  private func restartFinishedPreviewIfNeeded() {
    guard state == .playing else { return }

    if let onTrackFinished {
      didNotifyTrackFinished = true
      onTrackFinished()
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
      didNotifyTrackFinished = true
      onTrackFinished?()
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

  private func updateNowPlayingPlaybackRate(_ rate: Double) {
    var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = rate
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }

  private static func timeText(for seconds: TimeInterval) -> String {
    let totalSeconds = max(0, Int(seconds.rounded(.down)))
    return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
  }
}

enum PlaybackBackend: String {
  case none
  case localPreview
  case appleMusic
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
