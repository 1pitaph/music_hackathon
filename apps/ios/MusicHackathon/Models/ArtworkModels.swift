import Foundation

enum ArtworkSource: Codable, Hashable, Identifiable {
  case userFile(fileName: String)
  // Legacy metadata only. Bundled placeholder covers are no longer produced or rendered.
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
}

struct ArtworkResolution: Hashable {
  var remoteURLs: [URL?]

  init(
    remoteURLs: [URL?] = []
  ) {
    self.remoteURLs = remoteURLs
  }
}

enum ArtworkPriority: Hashable {
  case remote(URL)
  case none
}

enum ArtworkPriorityResolver {
  static func preferredSource(
    remoteURLs: [URL?]
  ) -> ArtworkPriority {
    if let remoteURL = ArtworkURLCandidates.unique(from: remoteURLs).first {
      return .remote(remoteURL)
    }

    return .none
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
