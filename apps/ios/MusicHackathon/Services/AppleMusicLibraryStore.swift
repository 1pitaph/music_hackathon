import Foundation
import MusicKit
import Observation

struct AppleMusicLibrarySnapshot: Hashable, Codable {
  var playlists: [AppleMusicPlaylistSnapshot]
  var tracks: [Track]
  var isComplete: Bool

  static let empty = AppleMusicLibrarySnapshot(playlists: [], tracks: [])

  init(
    playlists: [AppleMusicPlaylistSnapshot],
    tracks: [Track],
    isComplete: Bool = true
  ) {
    self.playlists = playlists
    self.tracks = tracks
    self.isComplete = isComplete
  }
}

struct AppleMusicPlaylistSnapshot: Identifiable, Hashable, Codable {
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
  @ObservationIgnored private let cache: (any AppleMusicLibraryCaching)?
  @ObservationIgnored private let diagnostics: DiagnosticsStore?
  @ObservationIgnored private var hasCompletedInitialLoad = false
  @ObservationIgnored private var hasAttemptedAutomaticRefresh = false

  init(
    provider: any AppleMusicLibraryProviding = AppleMusicCatalogService(),
    cache: (any AppleMusicLibraryCaching)? = AppleMusicLibraryCacheStore.shared,
    diagnostics: DiagnosticsStore? = nil
  ) {
    self.provider = provider
    self.cache = cache
    self.diagnostics = diagnostics
  }

  func loadIfNeeded(authorizationStatus: MusicAuthorization.Status) async {
    while state == .loading {
      try? await Task.sleep(for: .milliseconds(100))
    }

    guard authorizationStatus == .authorized else {
      await handleUnauthorized(authorizationStatus)
      return
    }

    var shouldRefresh = playlists.isEmpty || tracks.isEmpty
    if !hasCompletedInitialLoad {
      let cachedResult = await loadCachedSnapshot()
      if let cachedResult {
        apply(cachedResult.snapshot, state: state(for: cachedResult.snapshot))
        hasCompletedInitialLoad = true
        shouldRefresh = cachedResult.isExpired

        guard cachedResult.isExpired else {
          return
        }
      } else {
        shouldRefresh = true
      }
    }

    guard !hasAttemptedAutomaticRefresh else { return }
    guard shouldRefresh else { return }

    hasAttemptedAutomaticRefresh = true
    await refresh(
      authorizationStatus: authorizationStatus,
      preservesExistingSnapshotOnFailure: true
    )
  }

  func refresh(authorizationStatus: MusicAuthorization.Status) async {
    await refresh(
      authorizationStatus: authorizationStatus,
      preservesExistingSnapshotOnFailure: true
    )
  }

  private func refresh(
    authorizationStatus: MusicAuthorization.Status,
    preservesExistingSnapshotOnFailure: Bool
  ) async {
    guard authorizationStatus == .authorized else {
      await handleUnauthorized(authorizationStatus)
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
      let cachedSnapshot = await saveCachedSnapshot(snapshot) ?? snapshot
      let nextState = state(for: cachedSnapshot)
      apply(cachedSnapshot, state: nextState)
      hasCompletedInitialLoad = true
      diagnostics?.record(
        nextState == .loaded ? .notice : .warning,
        chain: .libraryAppleMusic,
        event: "refresh_success",
        message: L10n.tr("diagnostic.message.libraryRefreshSucceeded"),
        payload: [
          "playlist_count": String(snapshot.playlists.count),
          "track_count": String(cachedSnapshot.tracks.count),
          "is_complete": DiagnosticsPayload.bool(snapshot.isComplete),
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
      if preservesExistingSnapshotOnFailure, !playlists.isEmpty || !tracks.isEmpty {
        state = state(for: AppleMusicLibrarySnapshot(playlists: playlists, tracks: tracks))
        lastErrorMessage = message
      } else {
        apply(.empty, state: .failed(message))
      }
      hasCompletedInitialLoad = true
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

  private func state(for snapshot: AppleMusicLibrarySnapshot) -> AppleMusicLibraryState {
    snapshot.tracks.isEmpty && snapshot.playlists.allSatisfy { $0.tracks.isEmpty }
      ? .empty
      : .loaded
  }

  private func loadCachedSnapshot() async -> AppleMusicLibraryCacheLoadResult? {
    guard let cache else { return nil }

    do {
      let result = try await cache.loadSnapshot(now: Date())
      if let result {
        diagnostics?.record(
          result.isExpired ? .info : .notice,
          chain: .libraryAppleMusic,
          event: "cache_load_success",
          message: L10n.tr("diagnostic.message.libraryRefreshSucceeded"),
          payload: [
            "playlist_count": String(result.snapshot.playlists.count),
            "track_count": String(result.snapshot.tracks.count),
            "cache_expired": DiagnosticsPayload.bool(result.isExpired)
          ]
        )
      }
      return result
    } catch {
      diagnostics?.record(
        .warning,
        chain: .libraryAppleMusic,
        event: "cache_load_failed",
        message: L10n.tr("appleMusicLibrary.error.unableToRead"),
        payload: DiagnosticsPayload.error(error)
      )
      return nil
    }
  }

  private func saveCachedSnapshot(_ snapshot: AppleMusicLibrarySnapshot) async -> AppleMusicLibrarySnapshot? {
    guard let cache else { return nil }

    do {
      let result = try await cache.saveSnapshot(snapshot, now: Date())
      diagnostics?.record(
        .info,
        chain: .libraryAppleMusic,
        event: "cache_save_success",
        message: L10n.tr("diagnostic.message.libraryRefreshSucceeded"),
        payload: [
          "playlist_count": String(result.snapshot.playlists.count),
          "track_count": String(result.snapshot.tracks.count),
          "cache_expired": DiagnosticsPayload.bool(result.isExpired)
        ]
      )
      return result.snapshot
    } catch {
      diagnostics?.record(
        .warning,
        chain: .libraryAppleMusic,
        event: "cache_save_failed",
        message: L10n.tr("diagnostic.message.libraryRefreshFailed"),
        payload: DiagnosticsPayload.error(error)
      )
      return nil
    }
  }

  private func handleUnauthorized(_ authorizationStatus: MusicAuthorization.Status) async {
    diagnostics?.record(
      .info,
      chain: .libraryAppleMusic,
      event: "refresh_skipped",
      message: L10n.tr("diagnostic.message.libraryRefreshSkippedUnauthorized"),
      payload: ["authorization_status": authorizationStatus.diagnosticValue]
    )
    try? await cache?.clear()
    hasCompletedInitialLoad = true
    apply(.empty, state: .needsAuthorization)
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
