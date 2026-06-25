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

struct AppleMusicLibraryLoadOptions: Equatable {
  var pageSize = 100
  var includeLibrarySongs = true
}

protocol AppleMusicLibraryProviding {
  func librarySnapshot(options: AppleMusicLibraryLoadOptions) async throws -> AppleMusicLibrarySnapshot
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
  @ObservationIgnored private let diagnostics: DiagnosticsStore?

  init(
    provider: any AppleMusicLibraryProviding = AppleMusicCatalogService(),
    diagnostics: DiagnosticsStore? = nil
  ) {
    self.provider = provider
    self.diagnostics = diagnostics
  }

  func loadIfNeeded(authorizationStatus: MusicAuthorization.Status) async {
    while state == .loading {
      try? await Task.sleep(for: .milliseconds(100))
    }

    guard playlists.isEmpty, tracks.isEmpty else { return }
    await refresh(authorizationStatus: authorizationStatus)
  }

  func refresh(authorizationStatus: MusicAuthorization.Status) async {
    guard authorizationStatus == .authorized else {
      diagnostics?.record(
        .info,
        chain: .libraryAppleMusic,
        event: "refresh_skipped",
        message: L10n.tr("diagnostic.message.libraryRefreshSkippedUnauthorized"),
        payload: ["authorization_status": authorizationStatus.diagnosticValue]
      )
      apply(.empty, state: .needsAuthorization)
      return
    }

    state = .loading
    lastErrorMessage = nil
    diagnostics?.record(
      .info,
      chain: .libraryAppleMusic,
      event: "refresh_start",
      message: L10n.tr("diagnostic.message.libraryRefreshStarted")
    )

    do {
      let snapshot = try await provider.librarySnapshot(options: AppleMusicLibraryLoadOptions())
      let nextState: AppleMusicLibraryState = snapshot.tracks.isEmpty && snapshot.playlists.allSatisfy { $0.tracks.isEmpty }
        ? .empty
        : .loaded
      apply(snapshot, state: nextState)
      diagnostics?.record(
        nextState == .loaded ? .notice : .warning,
        chain: .libraryAppleMusic,
        event: "refresh_success",
        message: L10n.tr("diagnostic.message.libraryRefreshSucceeded"),
        payload: [
          "playlist_count": String(snapshot.playlists.count),
          "track_count": String(snapshot.tracks.count),
          "loaded_state": nextState.diagnosticValue
        ]
      )
    } catch is CancellationError {
      return
    } catch {
      let rawMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      let message = rawMessage == "Unknown error"
        ? L10n.tr("appleMusicLibrary.error.unableToRead")
        : rawMessage
      apply(.empty, state: .failed(message))
      diagnostics?.record(
        .error,
        chain: .libraryAppleMusic,
        event: "refresh_failed",
        message: L10n.tr("diagnostic.message.libraryRefreshFailed"),
        payload: DiagnosticsPayload.error(error)
      )
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

private extension MusicAuthorization.Status {
  var diagnosticValue: String {
    switch self {
    case .authorized:
      "authorized"
    case .denied:
      "denied"
    case .notDetermined:
      "not_determined"
    case .restricted:
      "restricted"
    @unknown default:
      "unknown"
    }
  }
}

private extension AppleMusicLibraryState {
  var diagnosticValue: String {
    switch self {
    case .idle:
      "idle"
    case .loading:
      "loading"
    case .needsAuthorization:
      "needs_authorization"
    case .loaded:
      "loaded"
    case .empty:
      "empty"
    case .failed:
      "failed"
    }
  }
}
