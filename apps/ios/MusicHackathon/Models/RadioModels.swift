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

  init(
    stationIntro: RadioStationIntroCopy? = nil,
    betweenTracks: [RadioTransitionCopy] = []
  ) {
    self.stationIntro = stationIntro
    self.betweenTracks = betweenTracks
  }
}

struct RadioStationIntroCopy: Codable, Hashable {
  let id: String
  let text: String
  let displayText: String
  let targetItemId: String?
  let agent: String
  let audio: RadioSpeechAudio?

  init(
    id: String = "station-intro",
    text: String,
    displayText: String,
    targetItemId: String? = nil,
    agent: String = "entry_copy_agent",
    audio: RadioSpeechAudio? = nil
  ) {
    self.id = id
    self.text = text
    self.displayText = displayText
    self.targetItemId = targetItemId
    self.agent = agent
    self.audio = audio
  }

  var playbackSegment: RadioSpeechPlaybackSegment {
    RadioSpeechPlaybackSegment(
      id: id,
      kind: .stationIntro,
      text: text,
      displayText: displayText,
      audio: audio
    )
  }
}

struct RadioTransitionCopy: Codable, Hashable {
  let id: String
  let fromItemId: String
  let toItemId: String
  let text: String
  let displayText: String
  let agent: String
  let audio: RadioSpeechAudio?

  init(
    id: String,
    fromItemId: String,
    toItemId: String,
    text: String,
    displayText: String,
    agent: String = "transition_copy_agent",
    audio: RadioSpeechAudio? = nil
  ) {
    self.id = id
    self.fromItemId = fromItemId
    self.toItemId = toItemId
    self.text = text
    self.displayText = displayText
    self.agent = agent
    self.audio = audio
  }

  var playbackSegment: RadioSpeechPlaybackSegment {
    RadioSpeechPlaybackSegment(
      id: id,
      kind: .transition,
      text: text,
      displayText: displayText,
      audio: audio
    )
  }
}

struct RadioSpeechAudio: Codable, Hashable {
  let audioURL: URL?
  let mimeType: String
  let durationSeconds: TimeInterval?
  let cacheKey: String
  let voice: String
  let model: String
  let status: String

  enum CodingKeys: String, CodingKey {
    case audioURL
    case audioUrl
    case mimeType
    case durationSeconds
    case cacheKey
    case voice
    case model
    case status
  }

  init(
    audioURL: URL? = nil,
    mimeType: String = "audio/mpeg",
    durationSeconds: TimeInterval? = nil,
    cacheKey: String,
    voice: String,
    model: String,
    status: String = "unavailable"
  ) {
    self.audioURL = audioURL
    self.mimeType = mimeType
    self.durationSeconds = durationSeconds
    self.cacheKey = cacheKey
    self.voice = voice
    self.model = model
    self.status = status
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    audioURL = try container.decodeIfPresent(URL.self, forKey: .audioURL)
      ?? container.decodeIfPresent(URL.self, forKey: .audioUrl)
    mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType) ?? "audio/mpeg"
    durationSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .durationSeconds)
    cacheKey = try container.decode(String.self, forKey: .cacheKey)
    voice = try container.decode(String.self, forKey: .voice)
    model = try container.decode(String.self, forKey: .model)
    status = try container.decodeIfPresent(String.self, forKey: .status) ?? "unavailable"
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(audioURL, forKey: .audioURL)
    try container.encode(mimeType, forKey: .mimeType)
    try container.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
    try container.encode(cacheKey, forKey: .cacheKey)
    try container.encode(voice, forKey: .voice)
    try container.encode(model, forKey: .model)
    try container.encode(status, forKey: .status)
  }
}

struct RadioSpeechPlaybackSegment: Identifiable, Hashable {
  enum Kind: String, Hashable {
    case stationIntro
    case transition
  }

  let id: String
  let kind: Kind
  let text: String
  let displayText: String
  let audio: RadioSpeechAudio?

  var playableAudioURL: URL? {
    guard audio?.status == "ready" else { return nil }
    return audio?.audioURL
  }
}

extension Track {
  var radioIdentity: String {
    if let appleMusicID = normalizedAppleMusicID {
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
