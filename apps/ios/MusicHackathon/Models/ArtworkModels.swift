import Foundation

enum ArtworkSource: Codable, Hashable, Identifiable {
  case userFile(fileName: String)
  case bundledCover(id: String)

  var id: String {
    switch self {
    case let .userFile(fileName):
      "user:\(fileName)"
    case let .bundledCover(id):
      "bundle:\(id)"
    }
  }
}

enum ImageAssetPurpose: String, Codable, Hashable {
  case profileAvatar
  case stationCover
}

struct ArtworkResolution: Hashable {
  var overrideSource: ArtworkSource?
  var remoteURLs: [URL?]
  var bundledFallback: ArtworkSource?
  var fallbackSeed: String
  var fallbackTitle: String
  var fallbackColorHex: String

  init(
    overrideSource: ArtworkSource? = nil,
    remoteURLs: [URL?] = [],
    bundledFallback: ArtworkSource? = nil,
    fallbackSeed: String,
    fallbackTitle: String,
    fallbackColorHex: String
  ) {
    self.overrideSource = overrideSource
    self.remoteURLs = remoteURLs
    self.bundledFallback = bundledFallback
    self.fallbackSeed = fallbackSeed
    self.fallbackTitle = fallbackTitle
    self.fallbackColorHex = fallbackColorHex
  }
}

enum ArtworkPriority: Hashable {
  case override(ArtworkSource)
  case remote(URL)
  case bundled(ArtworkSource)
  case generatedFallback
}

enum ArtworkPriorityResolver {
  static func preferredSource(
    overrideSource: ArtworkSource?,
    remoteURLs: [URL?],
    bundledFallback: ArtworkSource?
  ) -> ArtworkPriority {
    if let overrideSource {
      return .override(overrideSource)
    }

    if let remoteURL = ArtworkURLCandidates.unique(from: remoteURLs).first {
      return .remote(remoteURL)
    }

    if let bundledFallback {
      return .bundled(bundledFallback)
    }

    return .generatedFallback
  }
}

struct ArtworkAnalysisResult: Codable, Hashable {
  var dominantHex: String
  var secondaryHex: String
  var isDark: Bool
  var recommendedForegroundHex: String

  static let fallback = ArtworkAnalysisResult(
    dominantHex: "#D9523A",
    secondaryHex: "#24130B",
    isDark: true,
    recommendedForegroundHex: "#FFFFFF"
  )
}
