import Foundation
import MusicKit
import Observation

struct AppleMusicLibrarySnapshot: Hashable {
  var playlists: [AppleMusicPlaylistSnapshot]
  var tracks: [Track]

  static let empty = AppleMusicLibrarySnapshot(playlists: [], tracks: [])
}

struct AppleMusicPlaylistSnapshot: Identifiable, Hashable {
  let id: String
  let name: String
  let curatorName: String?
  let artworkURL: URL?
  let tracks: [Track]

  var artworkCandidateURLs: [URL] {
    ArtworkURLCandidates.unique(from: [artworkURL] + tracks.map(\.artworkURL))
  }
}

protocol AppleMusicLibraryProviding {
  func librarySnapshot(
    playlistLimit: Int,
    tracksPerPlaylistLimit: Int,
    fallbackSongLimit: Int
  ) async throws -> AppleMusicLibrarySnapshot
}

enum AppleMusicLibraryState: Equatable {
  case idle
  case loading
  case needsAuthorization
  case loaded
  case empty
  case failed(String)

  var isLoading: Bool {
    self == .loading
  }
}

@MainActor
@Observable
final class AppleMusicLibraryStore {
  var state: AppleMusicLibraryState = .idle
  var playlists: [AppleMusicPlaylistSnapshot] = []
  var tracks: [Track] = []
  var stations: [DiscoverStation] = []
  var lastErrorMessage: String?

  @ObservationIgnored private let provider: any AppleMusicLibraryProviding

  init(provider: any AppleMusicLibraryProviding = AppleMusicCatalogService()) {
    self.provider = provider
  }

  func loadIfNeeded(authorizationStatus: MusicAuthorization.Status) async {
    guard state != .loading, playlists.isEmpty, tracks.isEmpty else { return }
    await refresh(authorizationStatus: authorizationStatus)
  }

  func refresh(authorizationStatus: MusicAuthorization.Status) async {
    guard authorizationStatus == .authorized else {
      apply(.empty, state: .needsAuthorization)
      return
    }

    state = .loading
    lastErrorMessage = nil

    do {
      let snapshot = try await provider.librarySnapshot(
        playlistLimit: 12,
        tracksPerPlaylistLimit: 8,
        fallbackSongLimit: 36
      )
      let nextState: AppleMusicLibraryState = snapshot.tracks.isEmpty && snapshot.playlists.allSatisfy { $0.tracks.isEmpty }
        ? .empty
        : .loaded
      apply(snapshot, state: nextState)
    } catch is CancellationError {
      return
    } catch {
      let rawMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      let message = rawMessage == "Unknown error"
        ? "无法读取 Apple Music 资料库，请确认已登录并授权后重试。"
        : rawMessage
      apply(.empty, state: .failed(message))
    }
  }

  func candidateTracksForRadio() -> [Track] {
    tracks.filter(\.isPlayable)
  }

  private func apply(_ snapshot: AppleMusicLibrarySnapshot, state: AppleMusicLibraryState) {
    playlists = snapshot.playlists
    tracks = snapshot.tracks
    stations = DiscoverStation.stations(from: snapshot.playlists, libraryTracks: snapshot.tracks)
    self.state = state

    if case let .failed(message) = state {
      lastErrorMessage = message
    } else {
      lastErrorMessage = nil
    }
  }
}
