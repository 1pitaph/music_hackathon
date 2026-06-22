import Foundation

struct RadioStation: Identifiable, Hashable {
  let id: String
  let title: String
  let subtitle: String
  let items: [RadioQueueItem]
  let speech: RadioSpeech?

  init(
    id: String,
    title: String,
    subtitle: String,
    items: [RadioQueueItem],
    speech: RadioSpeech? = nil
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.items = items
    self.speech = speech
  }
}

struct RadioQueueItem: Identifiable, Hashable {
  let id: String
  let track: Track
  let sourceTitle: String
  let reason: String
  let handoffText: String?

  init(
    id: String,
    track: Track,
    sourceTitle: String,
    reason: String,
    handoffText: String? = nil
  ) {
    self.id = id
    self.track = track
    self.sourceTitle = sourceTitle
    self.reason = reason
    self.handoffText = handoffText
  }
}

struct RadioSpeech: Codable, Hashable {
  let stationIntro: RadioStationIntroCopy?
  let betweenTracks: [RadioTransitionCopy]
}

struct RadioStationIntroCopy: Codable, Hashable {
  let id: String
  let text: String
  let displayText: String
  let targetItemId: String?
  let agent: String
}

struct RadioTransitionCopy: Codable, Hashable {
  let id: String
  let fromItemId: String
  let toItemId: String
  let text: String
  let displayText: String
  let agent: String
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
