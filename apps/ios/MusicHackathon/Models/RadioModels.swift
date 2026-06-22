import Foundation

struct RadioStation: Identifiable, Hashable {
  let id: String
  let title: String
  let subtitle: String
  let items: [RadioQueueItem]
}

struct RadioQueueItem: Identifiable, Hashable {
  let id: String
  let track: Track
  let sourceTitle: String
  let reason: String
}

extension Track {
  var radioIdentity: String {
    if let appleMusicID {
      return "appleMusic:\(appleMusicID)"
    }

    let titleKey = title.radioKey
    let artistKey = artist.radioKey
    return "text:\(titleKey)::\(artistKey)"
  }
}

private extension String {
  var radioKey: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
  }
}
