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

  @ObservationIgnored private let player = AVPlayer()

  init() {
    configureAudioSession()
    configureRemoteCommands()
  }

  func play(track: Track) {
    currentTrack = track
    lastErrorMessage = nil
    state = .loading

    if let previewURL = track.previewURL {
      player.replaceCurrentItem(with: AVPlayerItem(url: previewURL))
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
    case .paused, .idle:
      if currentTrack == nil {
        currentTrack = MockCatalog.featuredTracks.first
      }

      if let currentTrack {
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
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
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
}
