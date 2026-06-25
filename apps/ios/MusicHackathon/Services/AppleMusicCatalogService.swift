import Foundation
import MusicKit

struct AppleMusicPlaylistSummary: Identifiable, Hashable, Codable {
  let id: String
  let name: String
  let curatorName: String?
  let artworkURL: URL?
}

enum AppleMusicCatalogResolutionMethod: String {
  case id
  case searchFallback
  case search
}

struct AppleMusicCatalogResolution {
  let song: Song
  let method: AppleMusicCatalogResolutionMethod
  let idError: Error?
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

  func relatedTracks(for seedTracks: [Track], limit: Int = 18) async -> [Track] {
    let terms = relatedSearchTerms(for: seedTracks)
    var result: [Track] = []
    var seenKeys: Set<String> = []

    for term in terms {
      guard result.count < limit else { break }

      do {
        let tracks = try await tracks(matching: term, limit: max(4, min(8, limit - result.count)))
        for track in tracks where !seenKeys.contains(track.radioIdentity) {
          seenKeys.insert(track.radioIdentity)
          result.append(track)
          if result.count >= limit {
            break
          }
        }
      } catch {
        continue
      }
    }

    return result
  }

  func resolveSong(for track: Track) async throws -> AppleMusicCatalogResolution {
    if let appleMusicID = track.normalizedAppleMusicID {
      do {
        return AppleMusicCatalogResolution(
          song: try await song(id: appleMusicID),
          method: .id,
          idError: nil
        )
      } catch {
        if let song = try await song(matching: track) {
          return AppleMusicCatalogResolution(
            song: song,
            method: .searchFallback,
            idError: error
          )
        }

        throw error
      }
    }

    if let song = try await song(matching: track) {
      return AppleMusicCatalogResolution(
        song: song,
        method: .search,
        idError: nil
      )
    }

    throw AppleMusicCatalogError.songUnavailable
  }

  func song(for track: Track) async throws -> Song {
    try await resolveSong(for: track).song
  }

  func song(id: String) async throws -> Song {
    let cleanedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanedID.isEmpty else {
      throw AppleMusicCatalogError.songUnavailable
    }

    let request = MusicCatalogResourceRequest<Song>(
      matching: \.id,
      equalTo: MusicItemID(cleanedID)
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
        artworkURL: Self.normalizedArtworkURL(playlist.artwork?.url(width: 512, height: 512))
      )
    }
  }

  func tracks(
    in playlist: Playlist,
    playlistName: String? = nil,
    pageSize: Int = 100
  ) async throws -> [Track] {
    let detailedPlaylist = try await playlist.with([.entries])
    guard let entries = detailedPlaylist.entries else { return [] }
    let allEntries = try await allItems(from: entries, pageSize: max(pageSize, 1))

    return allEntries.compactMap { entry in
      guard case let .song(song) = entry.item else { return nil }
      return Self.track(
        from: song,
        playlistName: playlistName ?? playlist.name,
        source: "apple_music_library",
        sourceLane: "playlist_entry"
      )
    }
  }

  private func songs(matching term: String, limit: Int) async throws -> [Song] {
    var request = MusicCatalogSearchRequest(term: term, types: [Song.self])
    request.limit = limit

    let response = try await request.response()
    return Array(response.songs.prefix(limit))
  }

  private func song(matching track: Track) async throws -> Song? {
    let title = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty || !artist.isEmpty else { return nil }

    let normalizedTitle = title.catalogMatchKey
    let normalizedArtist = artist.catalogMatchKey
    let songs = try await songs(matching: "\(title) \(artist)", limit: 8)

    return songs.first { song in
      song.title.catalogMatchKey == normalizedTitle && song.artistName.catalogMatchKey == normalizedArtist
    } ?? songs.first
  }

  static func track(
    from song: Song,
    fallback: Track? = nil,
    playlistName: String? = nil,
    source: String? = nil,
    sourceLane: String? = nil
  ) -> Track {
    Track(
      id: fallback?.id ?? stableID(for: song.id.rawValue),
      title: song.title,
      artist: song.artistName,
      album: song.albumTitle ?? fallback?.album ?? "Apple Music",
      mood: song.genreNames.first ?? fallback?.mood ?? "Apple Music",
      duration: song.duration ?? fallback?.duration ?? 0,
      artworkSystemName: fallback?.artworkSystemName ?? "music.note",
      artworkURL: normalizedArtworkURL(song.artwork?.url(width: 512, height: 512))
        ?? normalizedArtworkURL(fallback?.artworkURL),
      previewURL: song.previewAssets?.first?.url ?? fallback?.previewURL,
      appleMusicID: song.id.rawValue,
      isExplicit: song.contentRating == .explicit,
      playlistName: playlistName ?? fallback?.playlistName,
      source: source ?? fallback?.source,
      sourceLane: sourceLane ?? fallback?.sourceLane,
      sourceScore: fallback?.sourceScore,
      reasonSignals: fallback?.reasonSignals
    )
  }

  static func normalizedArtworkURL(_ url: URL?) -> URL? {
    ArtworkURLCandidates.normalized(url)
  }

  private static func stableID(for rawValue: String) -> UUID {
    let hash = rawValue.utf8.reduce(UInt64(0xcbf29ce484222325)) { partialResult, byte in
      (partialResult ^ UInt64(byte)) &* 0x100000001b3
    }
    let tail = String(format: "%012llX", hash & 0xFFFFFFFFFFFF)
    return UUID(uuidString: "A11E0000-0000-4000-8000-\(tail)") ?? UUID()
  }

  private func relatedSearchTerms(for seedTracks: [Track]) -> [String] {
    var terms: [String] = []
    var seen: Set<String> = []

    func add(_ term: String) {
      let cleaned = term.trimmingCharacters(in: .whitespacesAndNewlines)
      guard cleaned.count > 2 else { return }
      let key = cleaned.lowercased()
      guard !seen.contains(key) else { return }
      seen.insert(key)
      terms.append(cleaned)
    }

    for track in seedTracks.prefix(8) {
      add("\(track.artist) \(track.mood)")
      add("\(track.artist) \(track.album)")
      add(track.artist)
    }

    return terms
  }
}

private extension String {
  var catalogMatchKey: String {
    folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .lowercased()
  }
}

extension AppleMusicCatalogService: AppleMusicLibraryProviding {
  func librarySnapshot(
    options: AppleMusicLibraryLoadOptions = AppleMusicLibraryLoadOptions()
  ) async throws -> AppleMusicLibrarySnapshot {
    let pageSize = max(options.pageSize, 1)
    var request = MusicLibraryRequest<Playlist>()
    request.limit = pageSize

    let response = try await request.response()
    let playlists = try await allItems(from: response.items, pageSize: pageSize)
    var playlistSnapshots: [AppleMusicPlaylistSnapshot] = []
    var playlistTracks: [Track] = []

    for playlist in playlists {
      let tracks = (try? await tracks(in: playlist, playlistName: playlist.name, pageSize: pageSize)) ?? []
      playlistTracks.append(contentsOf: tracks)
      playlistSnapshots.append(
        AppleMusicPlaylistSnapshot(
          id: playlist.id.rawValue,
          name: playlist.name,
          curatorName: playlist.curatorName,
          artworkURL: Self.normalizedArtworkURL(playlist.artwork?.url(width: 512, height: 512)),
          tracks: tracks
        )
      )
    }

    let libraryTracks = options.includeLibrarySongs
      ? try await librarySongs(pageSize: pageSize)
      : []
    let tracks = uniqued(playlistTracks + libraryTracks)

    return AppleMusicLibrarySnapshot(
      playlists: playlistSnapshots,
      tracks: tracks
    )
  }

  private func librarySongs(pageSize: Int) async throws -> [Track] {
    var request = MusicLibraryRequest<Song>()
    request.limit = pageSize

    let response = try await request.response()
    let songs = try await allItems(from: response.items, pageSize: pageSize)
    return uniqued(
      songs.map {
        Self.track(
          from: $0,
          playlistName: "Apple Music Library",
          source: "apple_music_library",
          sourceLane: "library_song"
        )
      }
    )
  }

  private func allItems<Item: MusicItem>(
    from initialItems: MusicItemCollection<Item>,
    pageSize: Int
  ) async throws -> [Item] {
    var collection = initialItems
    var items = Array(collection)

    while let nextBatch = try await collection.nextBatch(limit: pageSize) {
      items.append(contentsOf: nextBatch)
      collection = nextBatch
    }

    return items
  }

  private func uniqued(_ tracks: [Track]) -> [Track] {
    var seen: Set<String> = []
    var result: [Track] = []

    for track in tracks where !seen.contains(track.radioIdentity) {
      seen.insert(track.radioIdentity)
      result.append(track)
    }

    return result
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
