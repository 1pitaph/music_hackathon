import Foundation

enum VirtualMusicLibrary {
  static let tracks: [Track] = {
    guard
      let url = resourceURL(in: .main),
      let data = try? Data(contentsOf: url),
      let tracks = try? decodeTracks(from: data, bundle: .main),
      !tracks.isEmpty
    else {
      return []
    }

    return tracks
  }()

  static var featuredTracks: [Track] {
    Array(tracks.prefix(6))
  }

  static func decodeTracks(from data: Data, bundle: Bundle = .main) throws -> [Track] {
    let payload = try JSONDecoder().decode(VirtualMusicLibraryPayload.self, from: data)
    return payload.tracks.map { $0.track(bundle: bundle) }
  }

  private static func resourceURL(in bundle: Bundle) -> URL? {
    bundle.url(
      forResource: "virtual-music-library",
      withExtension: "json",
      subdirectory: "VirtualMusicLibrary"
    ) ?? bundle.url(forResource: "virtual-music-library", withExtension: "json")
  }
}

private struct VirtualMusicLibraryPayload: Decodable {
  let libraryID: String
  let title: String
  let tracks: [VirtualMusicLibraryTrackPayload]
}

private struct VirtualMusicLibraryTrackPayload: Decodable {
  let id: String
  let title: String
  let artist: String
  let album: String
  let mood: String
  let duration: TimeInterval
  let artworkSystemName: String?
  let artworkURL: URL?
  let previewURL: URL?
  let previewResource: String?
  let appleMusicID: String?
  let isExplicit: Bool?
  let playlistName: String?
  let source: String?
  let sourceLane: String?
  let sourceScore: Double?
  let reasonSignals: [String]?

  func track(bundle: Bundle) -> Track {
    Track(
      id: stableID(for: id),
      title: title,
      artist: artist,
      album: album,
      mood: mood,
      duration: duration,
      artworkSystemName: artworkSystemName ?? "music.note",
      artworkURL: artworkURL,
      previewURL: previewURL ?? previewResourceURL(bundle: bundle),
      appleMusicID: appleMusicID,
      isExplicit: isExplicit ?? false,
      playlistName: playlistName ?? "Virtual music library",
      source: source ?? "virtual_library",
      sourceLane: sourceLane ?? "virtual_library",
      sourceScore: sourceScore,
      reasonSignals: reasonSignals
    )
  }

  private func previewResourceURL(bundle: Bundle) -> URL? {
    guard let previewResource else { return nil }
    return bundle.url(forResource: previewResource, withExtension: "m4a", subdirectory: "Audio")
      ?? bundle.url(forResource: previewResource, withExtension: "m4a")
  }

  private func stableID(for rawValue: String) -> UUID {
    let hash = rawValue.utf8.reduce(UInt64(0xcbf29ce484222325)) { partialResult, byte in
      (partialResult ^ UInt64(byte)) &* 0x100000001b3
    }
    let tail = String(format: "%012llX", hash & 0xFFFFFFFFFFFF)
    return UUID(uuidString: "A11E0000-0000-4000-8000-\(tail)") ?? UUID()
  }
}
