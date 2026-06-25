import Foundation

enum MockCatalog {
  static var featuredTracks: [Track] {
    let virtualTracks = VirtualMusicLibrary.featuredTracks
    return virtualTracks.isEmpty ? fallbackFeaturedTracks : virtualTracks
  }

  static var radioCandidates: [Track] {
    let virtualTracks = VirtualMusicLibrary.tracks
    return virtualTracks.isEmpty ? fallbackFeaturedTracks : virtualTracks
  }

  private static let fallbackFeaturedTracks: [Track] = [
    Track(
      title: "future",
      artist: "WRABEL",
      album: "up up above",
      mood: "Pop Surrealism",
      duration: 204,
      artworkSystemName: "waveform",
      artworkURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/9a/8a/0d/9a8a0d30-c5a8-1131-0a98-f3c6e3da82eb/067003255943.png/512x512bb.jpg"),
      previewURL: featuredPreviewURL ?? URL(string: "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/86/6d/82/866d820f-8c32-a173-525f-c3e109d7054b/mzaf_16084222939051357701.plus.aac.p.m4a"),
      appleMusicID: "1879898145"
    ),
    Track(
      title: "birds & the bees",
      artist: "WRABEL",
      album: "up up above",
      mood: "Glowing",
      duration: 221,
      artworkSystemName: "music.quarternote.3",
      artworkURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/9a/8a/0d/9a8a0d30-c5a8-1131-0a98-f3c6e3da82eb/067003255943.png/512x512bb.jpg"),
      previewURL: URL(string: "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/bf/f1/2c/bff12c97-74a7-8d0e-1e30-f8709f8b184e/mzaf_13238801874770777058.plus.aac.p.m4a"),
      appleMusicID: "1879898163"
    ),
    Track(
      title: "move",
      artist: "WRABEL",
      album: "up up above",
      mood: "Cinematic",
      duration: 207,
      artworkSystemName: "record.circle",
      artworkURL: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/9a/8a/0d/9a8a0d30-c5a8-1131-0a98-f3c6e3da82eb/067003255943.png/512x512bb.jpg"),
      previewURL: URL(string: "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/e5/bc/9b/e5bc9b5d-eb9c-4f3d-3f2b-80f68bf88f1a/mzaf_9247009263125251965.plus.aac.p.m4a"),
      appleMusicID: "1879898517"
    )
  ]

  static let playlists: [String] = [
    L10n.tr("mockCatalog.playlist.morningQueue"),
    L10n.tr("mockCatalog.playlist.tracksToRevisit"),
    L10n.tr("mockCatalog.playlist.practiceRoom"),
    L10n.tr("mockCatalog.playlist.weekendDiscoveries")
  ]

  private static var featuredPreviewURL: URL? {
    Bundle.main.url(forResource: "featured-preview", withExtension: "m4a")
  }
}
