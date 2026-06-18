import Foundation
import MusicKit

struct AppleMusicPlaylistSummary: Identifiable, Hashable {
  let id: String
  let name: String
  let curatorName: String?
  let artworkURL: URL?
}

struct AppleMusicCatalogService {
  func featuredTracks() async throws -> [Track] {
    try await tracks(matching: "WRABEL up up above", limit: 6)
  }

  func enrich(_ tracks: [Track]) async -> [Track] {
    await withTaskGroup(of: (Int, Track).self) { group in
      for (index, track) in tracks.enumerated() {
        group.addTask {
          guard let song = try? await song(matching: track) else {
            return (index, track)
          }

          return (index, Self.track(from: song, fallback: track))
        }
      }

      var enrichedTracks = tracks
      for await (index, track) in group {
        enrichedTracks[index] = track
      }
      return enrichedTracks
    }
  }

  func tracks(matching term: String, limit: Int = 10) async throws -> [Track] {
    let songs = try await songs(matching: term, limit: limit)
    return songs.map { Self.track(from: $0) }
  }

  func song(for track: Track) async throws -> Song {
    if let appleMusicID = track.appleMusicID {
      return try await song(id: appleMusicID)
    }

    if let song = try await song(matching: track) {
      return song
    }

    throw AppleMusicCatalogError.songUnavailable
  }

  func song(id: String) async throws -> Song {
    let request = MusicCatalogResourceRequest<Song>(
      matching: \.id,
      equalTo: MusicItemID(id)
    )
    let response = try await request.response()

    guard let song = response.items.first else {
      throw AppleMusicCatalogError.songUnavailable
    }

    return song
  }

  func libraryPlaylists(limit: Int = 25) async throws -> [AppleMusicPlaylistSummary] {
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

  func tracks(in playlist: Playlist) async throws -> [Track] {
    let detailedPlaylist = try await playlist.with([.entries])
    return detailedPlaylist.entries?.compactMap { entry in
      guard case let .song(song) = entry.item else { return nil }
      return Self.track(from: song)
    } ?? []
  }

  private func songs(matching term: String, limit: Int) async throws -> [Song] {
    var request = MusicCatalogSearchRequest(term: term, types: [Song.self])
    request.limit = limit

    let response = try await request.response()
    return Array(response.songs.prefix(limit))
  }

  private func song(matching track: Track) async throws -> Song? {
    let normalizedTitle = track.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let normalizedArtist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let songs = try await songs(matching: "\(track.title) \(track.artist)", limit: 8)

    return songs.first { song in
      song.title.lowercased() == normalizedTitle && song.artistName.lowercased() == normalizedArtist
    } ?? songs.first
  }

  private static func track(from song: Song, fallback: Track? = nil) -> Track {
    Track(
      id: fallback?.id ?? stableID(for: song.id.rawValue),
      title: song.title,
      artist: song.artistName,
      album: song.albumTitle ?? fallback?.album ?? "Apple Music",
      mood: song.genreNames.first ?? fallback?.mood ?? "Apple Music",
      duration: song.duration ?? fallback?.duration ?? 0,
      artworkSystemName: fallback?.artworkSystemName ?? "music.note",
      artworkURL: song.artwork?.url(width: 512, height: 512) ?? fallback?.artworkURL,
      previewURL: song.previewAssets?.first?.url ?? fallback?.previewURL,
      appleMusicID: song.id.rawValue,
      isExplicit: song.contentRating == .explicit
    )
  }

  private static func stableID(for rawValue: String) -> UUID {
    let hash = rawValue.utf8.reduce(UInt64(0xcbf29ce484222325)) { partialResult, byte in
      (partialResult ^ UInt64(byte)) &* 0x100000001b3
    }
    let tail = String(format: "%012llX", hash & 0xFFFFFFFFFFFF)
    return UUID(uuidString: "A11E0000-0000-4000-8000-\(tail)") ?? UUID()
  }
}

enum AppleMusicCatalogError: LocalizedError {
  case songUnavailable

  var errorDescription: String? {
    switch self {
    case .songUnavailable:
      "This song is not available in the Apple Music catalog for your storefront."
    }
  }
}
