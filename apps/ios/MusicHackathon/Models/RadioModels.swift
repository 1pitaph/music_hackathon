import Foundation

struct RadioStation: Identifiable, Hashable, Codable {
  let id: String
  let title: String
  let subtitle: String
  let items: [RadioQueueItem]
  let speech: RadioSpeech?
  let allowsAutoExtension: Bool

  init(
    id: String,
    title: String,
    subtitle: String,
    items: [RadioQueueItem],
    speech: RadioSpeech? = nil,
    allowsAutoExtension: Bool = true
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.items = items
    self.speech = speech
    self.allowsAutoExtension = allowsAutoExtension
  }
}

struct RadioQueueItem: Identifiable, Hashable, Codable {
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

  func replacingTrack(_ track: Track) -> RadioQueueItem {
    RadioQueueItem(
      id: id,
      track: track,
      sourceTitle: sourceTitle,
      reason: reason,
      handoffText: handoffText
    )
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

struct RadioSpeechTimingWord: Codable, Hashable {
  let word: String
  let startTime: TimeInterval
  let endTime: TimeInterval
  let confidence: Double?
}

struct RadioSpeechCue: Codable, Hashable, Identifiable {
  let id: String
  let text: String
  let displayText: String
  let startTime: TimeInterval
  let endTime: TimeInterval
  let words: [RadioSpeechTimingWord]
}

struct RadioSpeechAudio: Codable, Hashable {
  let audioURL: URL?
  let streamURL: URL?
  let metadataURL: URL?
  let mimeType: String
  let durationSeconds: TimeInterval?
  let durationSource: String
  let estimatedDurationSeconds: TimeInterval?
  let actualDurationSeconds: TimeInterval?
  let advanceTimeSeconds: TimeInterval?
  let advanceCueId: String?
  let cacheKey: String
  let voice: String
  let model: String
  let status: String
  let cues: [RadioSpeechCue]

  enum CodingKeys: String, CodingKey {
    case audioURL
    case audioUrl
    case streamURL
    case streamUrl
    case metadataURL
    case metadataUrl
    case mimeType
    case durationSeconds
    case durationSource
    case estimatedDurationSeconds
    case actualDurationSeconds
    case advanceTimeSeconds
    case advanceCueId
    case cacheKey
    case voice
    case model
    case status
    case cues
  }

  init(
    audioURL: URL? = nil,
    streamURL: URL? = nil,
    metadataURL: URL? = nil,
    mimeType: String = "audio/mpeg",
    durationSeconds: TimeInterval? = nil,
    durationSource: String = "estimated",
    estimatedDurationSeconds: TimeInterval? = nil,
    actualDurationSeconds: TimeInterval? = nil,
    advanceTimeSeconds: TimeInterval? = nil,
    advanceCueId: String? = nil,
    cacheKey: String,
    voice: String,
    model: String,
    status: String = "unavailable",
    cues: [RadioSpeechCue] = []
  ) {
    self.audioURL = audioURL
    self.streamURL = streamURL
    self.metadataURL = metadataURL
    self.mimeType = mimeType
    self.durationSeconds = durationSeconds
    self.durationSource = durationSource
    self.estimatedDurationSeconds = estimatedDurationSeconds
    self.actualDurationSeconds = actualDurationSeconds
    self.advanceTimeSeconds = advanceTimeSeconds
    self.advanceCueId = advanceCueId
    self.cacheKey = cacheKey
    self.voice = voice
    self.model = model
    self.status = status
    self.cues = cues
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    audioURL = try container.decodeIfPresent(URL.self, forKey: .audioURL)
      ?? container.decodeIfPresent(URL.self, forKey: .audioUrl)
    streamURL = try container.decodeIfPresent(URL.self, forKey: .streamURL)
      ?? container.decodeIfPresent(URL.self, forKey: .streamUrl)
    metadataURL = try container.decodeIfPresent(URL.self, forKey: .metadataURL)
      ?? container.decodeIfPresent(URL.self, forKey: .metadataUrl)
    mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType) ?? "audio/mpeg"
    durationSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .durationSeconds)
    durationSource = try container.decodeIfPresent(String.self, forKey: .durationSource) ?? "estimated"
    estimatedDurationSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .estimatedDurationSeconds)
    actualDurationSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .actualDurationSeconds)
    advanceTimeSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .advanceTimeSeconds)
    advanceCueId = try container.decodeIfPresent(String.self, forKey: .advanceCueId)
    cacheKey = try container.decode(String.self, forKey: .cacheKey)
    voice = try container.decode(String.self, forKey: .voice)
    model = try container.decode(String.self, forKey: .model)
    status = try container.decodeIfPresent(String.self, forKey: .status) ?? "unavailable"
    cues = try container.decodeIfPresent([RadioSpeechCue].self, forKey: .cues) ?? []
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(audioURL, forKey: .audioURL)
    try container.encodeIfPresent(streamURL, forKey: .streamURL)
    try container.encodeIfPresent(metadataURL, forKey: .metadataURL)
    try container.encode(mimeType, forKey: .mimeType)
    try container.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
    try container.encode(durationSource, forKey: .durationSource)
    try container.encodeIfPresent(estimatedDurationSeconds, forKey: .estimatedDurationSeconds)
    try container.encodeIfPresent(actualDurationSeconds, forKey: .actualDurationSeconds)
    try container.encodeIfPresent(advanceTimeSeconds, forKey: .advanceTimeSeconds)
    try container.encodeIfPresent(advanceCueId, forKey: .advanceCueId)
    try container.encode(cacheKey, forKey: .cacheKey)
    try container.encode(voice, forKey: .voice)
    try container.encode(model, forKey: .model)
    try container.encode(status, forKey: .status)
    try container.encode(cues, forKey: .cues)
  }

  var resolvedMetadataURL: URL? {
    metadataURL ?? Self.derivedMetadataURL(from: streamURL) ?? Self.derivedMetadataURL(from: audioURL)
  }

  var hasActualTiming: Bool {
    durationSource == "audio" || durationSource == "timing" || actualDurationSeconds != nil || !cues.isEmpty
  }

  private static func derivedMetadataURL(from url: URL?) -> URL? {
    guard let url,
          var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return nil
    }

    let path = components.path
    if path.contains("/v1/radio/speech/stream/") {
      components.path = path.replacingOccurrences(of: "/v1/radio/speech/stream/", with: "/v1/radio/speech/metadata/")
    } else if path.contains("/v1/radio/speech/audio/") {
      components.path = path.replacingOccurrences(of: "/v1/radio/speech/audio/", with: "/v1/radio/speech/metadata/")
    } else if let derivedPath = siblingMetadataPath(from: path) {
      components.path = derivedPath
    } else {
      return nil
    }
    return components.url
  }

  private static func siblingMetadataPath(from path: String) -> String? {
    var components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard components.count >= 2 else { return nil }
    let parentIndex = components.count - 2
    guard components[parentIndex] == "stream" || components[parentIndex] == "audio" else {
      return nil
    }
    components[parentIndex] = "metadata"
    return components.joined(separator: "/")
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
    return Self.playableRemoteURL(audio?.streamURL) ?? Self.playableRemoteURL(audio?.audioURL)
  }

  var timedCues: [RadioSpeechCue] {
    audio?.cues ?? []
  }

  func replacingAudio(_ audio: RadioSpeechAudio) -> RadioSpeechPlaybackSegment {
    RadioSpeechPlaybackSegment(
      id: id,
      kind: kind,
      text: text,
      displayText: displayText,
      audio: audio
    )
  }

  private static func playableRemoteURL(_ url: URL?) -> URL? {
    guard let url,
          let scheme = url.scheme?.lowercased(),
          ["http", "https"].contains(scheme),
          url.host?.isEmpty == false else {
      return nil
    }
    return url
  }
}

enum RadioStationVisibility: String, Codable, CaseIterable, Identifiable {
  case `public`
  case unlisted
  case `private`

  var id: String { rawValue }

  var title: String {
    switch self {
    case .public:
      L10n.tr("discover.publish.visibility.public")
    case .unlisted:
      L10n.tr("discover.publish.visibility.unlisted")
    case .private:
      L10n.tr("discover.publish.visibility.private")
    }
  }
}

struct DiscoverFeedPage: Equatable {
  var stations: [PublishedDiscoverStation]
  var nextCursor: String?
}

struct DiscoverStationPublicationDraft: Equatable {
  var title: String
  var subtitle: String
  var description: String
  var visibility: RadioStationVisibility
  var ownerID: String
  var ownerDisplayName: String
  var seedTracks: [Track]
  var station: RadioStation
  var coverArtworkURL: URL?
  var colorHex: String
  var usedFallbackGeneration: Bool = false
}

struct PublishedDiscoverStation: Identifiable, Equatable, Codable {
  var stationID: String
  var title: String
  var subtitle: String
  var description: String
  var visibility: RadioStationVisibility
  var ownerID: String
  var ownerDisplayName: String
  var publishedAt: String
  var shareURL: URL
  var seedTracks: [Track]
  var items: [RadioQueueItem]
  var speech: RadioSpeech?
  var coverArtworkURL: URL?
  var colorHex: String
  var favorites: Int

  var id: String { stationID }

  func discoverStation() -> DiscoverStation {
    DiscoverStation(
      id: stationID,
      title: title,
      briefIntro: subtitle,
      description: description,
      hostName: ownerDisplayName,
      genre: seedTracks.first?.mood ?? items.first?.track.mood ?? "Radio",
      favorites: favorites,
      items: items,
      colorHex: colorHex,
      artworkURL: coverArtworkURL,
      shareURL: shareURL
    )
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
