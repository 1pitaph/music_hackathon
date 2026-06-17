import AVFoundation
import MediaPlayer
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
  var elapsedTimeText: String = "0:00"

  @ObservationIgnored private let player = AVPlayer()
  @ObservationIgnored private var timeObserverToken: Any?

  init() {
    configureAudioSession()
    configureRemoteCommands()
  }

  func play(track: Track) {
    currentTrack = track
    lastErrorMessage = nil
    state = .loading
    resetPlaybackProgress()
    removePeriodicTimeObserver()

    if let previewURL = track.previewURL {
      player.replaceCurrentItem(with: AVPlayerItem(url: previewURL))
      addPeriodicTimeObserver()
      player.play()
      state = .playing
    } else {
      state = .paused
    }

    updateNowPlayingInfo(for: track)
  }

  func togglePlayback() {
    switch state {
    case .playing:
      player.pause()
      state = .paused
      updateNowPlayingPlaybackRate(0)
    case .paused, .idle:
      if currentTrack == nil {
        currentTrack = MockCatalog.featuredTracks.first
      }

      if state == .paused, player.currentItem != nil {
        player.play()
        state = .playing
        updateNowPlayingPlaybackRate(1)
      } else if let currentTrack {
        play(track: currentTrack)
      }
    case .loading, .failed:
      break
    }
  }

  func stop() {
    player.pause()
    player.replaceCurrentItem(with: nil)
    state = .idle
    currentTrack = nil
    resetPlaybackProgress()
    removePeriodicTimeObserver()
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
  }

  private func addPeriodicTimeObserver() {
    let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
      Task { @MainActor in
        self?.updatePlaybackProgress(for: time)
      }
    }
  }

  private func removePeriodicTimeObserver() {
    guard let timeObserverToken else { return }
    player.removeTimeObserver(timeObserverToken)
    self.timeObserverToken = nil
  }

  private func updatePlaybackProgress(for time: CMTime) {
    let elapsedSeconds = time.seconds.isFinite ? max(0, time.seconds) : 0
    elapsedTimeText = Self.timeText(for: elapsedSeconds)

    guard
      let duration = player.currentItem?.duration.seconds,
      duration.isFinite,
      duration > 0
    else {
      playbackProgress = 0
      return
    }

    playbackProgress = min(max(elapsedSeconds / duration, 0), 1)
  }

  private func resetPlaybackProgress() {
    playbackProgress = 0
    elapsedTimeText = "0:00"
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
        guard let self else { return }
        self.player.pause()
        self.state = .paused
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
