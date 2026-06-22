import Foundation
import MusicKit

struct AppleMusicLibraryService {
  func playlists(limit: Int = 50) async throws -> [AppleMusicPlaylistSummary] {
    var request = MusicLibraryRequest<Playlist>()
    request.limit = limit

    let response = try await request.response()
    return response.items.map { playlist in
      AppleMusicPlaylistSummary(
        id: playlist.id.rawValue,
        name: playlist.name,
        curatorName: playlist.curatorName,
        artworkURL: playlist.artwork?.url(width: 512, height: 512)
      )
    }
  }

  func seedTracks(for selectedPlaylists: [AppleMusicPlaylistSummary]) async throws -> [RadioSeedTrack] {
    guard !selectedPlaylists.isEmpty else { return [] }

    let playlistByID = Dictionary(uniqueKeysWithValues: selectedPlaylists.map { ($0.id, $0) })
    let selectedIDs = Set(selectedPlaylists.map(\.id))
    let playlists = try await libraryPlaylists(limit: 100)
      .filter { selectedIDs.contains($0.id.rawValue) }

    var result: [RadioSeedTrack] = []
    for playlist in playlists {
      guard let summary = playlistByID[playlist.id.rawValue] else { continue }
      let tracks = try await tracks(in: playlist)
      result.append(
        contentsOf: tracks.map { track in
          RadioSeedTrack(track: track, playlistID: summary.id, playlistName: summary.name)
        }
      )
    }

    return result
  }

  private func libraryPlaylists(limit: Int) async throws -> MusicItemCollection<Playlist> {
    var request = MusicLibraryRequest<Playlist>()
    request.limit = limit
    let response = try await request.response()
    return response.items
  }

  private func tracks(in playlist: Playlist) async throws -> [Track] {
    let detailedPlaylist = try await playlist.with([.entries])
    return detailedPlaylist.entries?.compactMap { entry in
      guard case let .song(song) = entry.item else { return nil }
      return AppleMusicCatalogService.track(from: song)
    } ?? []
  }
}
