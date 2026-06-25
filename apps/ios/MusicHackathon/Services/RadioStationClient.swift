import Foundation

protocol RadioStationFetching {
  func fetchCurrentStation() async throws -> RadioStation
  func generateStation(context: RadioStationGenerationContext) async throws -> RadioStationResult
  func fetchSpeechVoices() async throws -> RadioSpeechVoiceCatalog
  func compressMemory(_ request: RadioMemoryCompressionRequest) async throws -> RadioCompressedMemory?
}

extension RadioStationFetching {
  func generateStation(context: RadioStationGenerationContext) async throws -> RadioStationResult {
    RadioStationResult(station: try await fetchCurrentStation())
  }

  func compressMemory(_ request: RadioMemoryCompressionRequest) async throws -> RadioCompressedMemory? {
    nil
  }

  func fetchSpeechVoices() async throws -> RadioSpeechVoiceCatalog {
    .fallback
  }
}

struct RadioStationResult: Equatable {
  let station: RadioStation
  var diagnostics: [String] = []
  var memoryPatchProposals: [RadioMemoryPatchProposal] = []
  var stationSessionID: String?
  var continuationCursor: String?
}

struct RadioMemoryPatchProposal: Codable, Equatable {
  let op: String
  let type: String
  let text: String
  let confidence: Double
  let source: String
}

struct RadioStationGenerationContext: Encodable, Equatable {
  var action = "start"
  var tuning = RadioTuningPayload()
  var seedTracks: [RadioTrackPayload]
  var catalogCandidates: [RadioTrackPayload]
  var memory: RadioMemoryRequest
  var memoryContext: RadioMemoryContext
  var memoryMarkdown = ""
  var limit = 6
  var stationID = "airset-personal"
  var stationSessionID: String?
  var continuationCursor: String?
  var currentTrackKey: String?
  var queuedTrackKeys: [String] = []
  var recentlyPlayedTrackKeys: [String] = []
  var title = L10n.tr("radio.defaultTitle")
  var speechLanguage = RadioSpeechLanguage.chinese.speechLanguageCode
  var speechAudio = RadioSpeechAudioRequest(enabled: true)

  init(
    action: String = "start",
    seedTracks: [Track],
    catalogCandidates: [Track],
    memoryContext: RadioMemoryContext,
    limit: Int = 6,
    stationID: String = "airset-personal",
    stationSessionID: String? = nil,
    continuationCursor: String? = nil,
    currentTrackKey: String? = nil,
    queuedTrackKeys: [String] = [],
    recentlyPlayedTrackKeys: [String] = [],
    hostSpeakerID: String? = nil,
    speechLanguage: RadioSpeechLanguage = .chinese
  ) {
    self.action = action
    self.seedTracks = seedTracks.map {
      RadioTrackPayload(track: $0, playlistName: "Local memory seeds", sourceLane: "familiar_anchor")
    }
    self.catalogCandidates = catalogCandidates.map {
      RadioTrackPayload(
        track: $0,
        source: $0.source ?? "catalog",
        sourceLane: $0.sourceLane ?? "candidate_pool"
      )
    }
    self.memoryContext = memoryContext
    self.limit = limit
    self.stationID = stationID
    self.stationSessionID = stationSessionID
    self.continuationCursor = continuationCursor
    self.currentTrackKey = currentTrackKey
    self.queuedTrackKeys = queuedTrackKeys
    self.recentlyPlayedTrackKeys = recentlyPlayedTrackKeys
    self.speechLanguage = speechLanguage.speechLanguageCode
    if let hostSpeakerID = hostSpeakerID?.trimmedNilIfEmpty {
      speechAudio.speaker = hostSpeakerID
    }
    speechAudio.explicitLanguage = speechLanguage.speechLanguageCode
    memory = RadioMemoryRequest(
      recentlyPlayedTrackKeys: memoryContext.recentlyPlayedTrackKeys,
      likedTrackKeys: [],
      skippedTrackKeys: [],
      dislikedTrackKeys: []
    )
  }
}

struct RadioSpeechAudioRequest: Codable, Equatable {
  var enabled = false
  var provider = "volcengine"
  var voice: String?
  var speaker: String?
  var resourceId = "seed-tts-1.0"
  var model = "seed-tts-1.0"
  var format = "mp3"
  var speechRate: Int? = -6
  var loudnessRate: Int?
  var pitch: Int?
  var explicitLanguage: String?
  var emotion: String?
}

struct RadioSpeechVoiceCatalog: Codable, Equatable {
  var defaultSpeaker: String
  var resourceId: String
  var model: String
  var voices: [RadioSpeechVoice]

  static let fallback = RadioSpeechVoiceCatalog(
    defaultSpeaker: "zh_female_shuangkuaisisi_moon_bigtts",
    resourceId: "seed-tts-1.0",
    model: "seed-tts-1.0",
    voices: [
      RadioSpeechVoice(
        id: "zh_female_shuangkuaisisi_moon_bigtts",
        name: L10n.tr("radio.speechVoice.fallbackName"),
        language: "zh-cn",
        gender: "female",
        style: L10n.tr("radio.speechVoice.fallbackStyle"),
        resourceId: "seed-tts-1.0",
        model: "seed-tts-1.0"
      )
    ]
  )

  func voice(for speakerID: String) -> RadioSpeechVoice? {
    voices.first { $0.id == speakerID }
  }
}

struct RadioSpeechVoice: Codable, Equatable, Identifiable {
  let id: String
  let name: String
  let language: String
  let gender: String
  let style: String
  let resourceId: String
  let model: String
}

enum RadioHostVoiceSettings {
  static let speakerIDKey = "radio.hostSpeakerID"

  static func selectedSpeakerID(defaults: UserDefaults = .standard) -> String? {
    defaults.string(forKey: speakerIDKey)?.trimmedNilIfEmpty
  }
}

struct RadioTuningPayload: Codable, Equatable {
  var discoveryRatio = 0.3
  var familiarity = 0.7
  var energy = 0.5
}

struct RadioMemoryRequest: Codable, Equatable {
  var recentlyPlayedTrackKeys: [String]
  var likedTrackKeys: [String]
  var skippedTrackKeys: [String]
  var dislikedTrackKeys: [String]
}

struct RadioTrackPayload: Codable, Equatable {
  let radioIdentity: String
  let title: String
  let artist: String
  let album: String
  let mood: String
  let duration: TimeInterval
  let artworkURL: URL?
  let previewURL: URL?
  let appleMusicID: String?
  let isExplicit: Bool
  let playlistName: String?
  let source: String?
  let sourceLane: String?
  let sourceScore: Double?
  let reasonSignals: [String]

  init(
    track: Track,
    playlistName: String? = nil,
    source: String? = nil,
    sourceLane: String? = nil,
    sourceScore: Double? = nil,
    reasonSignals: [String] = []
  ) {
    radioIdentity = track.radioIdentity
    title = track.title
    artist = track.artist
    album = track.album
    mood = track.mood
    duration = track.duration
    artworkURL = track.artworkURL
    previewURL = track.previewURL
    appleMusicID = track.normalizedAppleMusicID
    isExplicit = track.isExplicit
    self.playlistName = playlistName ?? track.playlistName
    self.source = source ?? track.source
    self.sourceLane = sourceLane ?? track.sourceLane
    self.sourceScore = sourceScore ?? track.sourceScore
    self.reasonSignals = reasonSignals.isEmpty ? (track.reasonSignals ?? []) : reasonSignals
  }
}

struct RadioStationClient: RadioStationFetching {
  static let defaultBaseURL = URL(string: "https://musichackathon-production.up.railway.app")

  private let baseURL: URL?
  private let session: URLSession
  private let timeout: TimeInterval
  private let generationTimeout: TimeInterval
  private let decoder: JSONDecoder
  private let encoder: JSONEncoder
  private let diagnostics: DiagnosticsStore?

  init(
    baseURL: URL? = Self.defaultBaseURL,
    session: URLSession = .shared,
    timeout: TimeInterval = 15.0,
    generationTimeout: TimeInterval = 45.0,
    diagnostics: DiagnosticsStore? = nil
  ) {
    self.baseURL = baseURL
    self.session = session
    self.timeout = timeout
    self.generationTimeout = generationTimeout
    self.diagnostics = diagnostics
    decoder = JSONDecoder()
    encoder = JSONEncoder()
  }

  func fetchCurrentStation() async throws -> RadioStation {
    guard let baseURL else {
      throw RadioStationClientError.disabled
    }

    let endpoint = baseURL.appending(path: "v1/radio/stations/current")
    var request = URLRequest(url: endpoint, timeoutInterval: timeout)
    request.httpMethod = "GET"
    applyLocalizationHeaders(to: &request)

    let startedAt = Date()
    recordNetwork(
      .info,
      event: "request_start",
      message: L10n.tr("diagnostic.message.backendStationRequestStarted"),
      request: request
    )

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      recordNetwork(
        .error,
        event: "request_failed",
        message: L10n.tr("diagnostic.message.backendStationRequestFailed"),
        request: request,
        payload: DiagnosticsPayload.error(error)
      )
      throw error
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      recordNetwork(
        .error,
        event: "invalid_response",
        message: L10n.tr("diagnostic.message.backendStationInvalidResponse"),
        request: request,
        payload: ["duration_ms": DiagnosticsPayload.durationMilliseconds(Date().timeIntervalSince(startedAt))]
      )
      throw RadioStationClientError.invalidResponse
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      recordNetwork(
        .error,
        event: "server_status",
        message: L10n.tr("diagnostic.message.backendStationServerStatus"),
        request: request,
        payload: [
          "status_code": String(httpResponse.statusCode),
          "duration_ms": DiagnosticsPayload.durationMilliseconds(Date().timeIntervalSince(startedAt))
        ]
      )
      throw RadioStationClientError.serverStatus(httpResponse.statusCode)
    }

    let payload: RadioStationPayload
    do {
      payload = try decoder.decode(RadioStationPayload.self, from: data)
    } catch {
      recordNetwork(
        .error,
        event: "decode_failed",
        message: L10n.tr("diagnostic.message.backendStationDecodeFailed"),
        request: request,
        payload: DiagnosticsPayload.error(error)
      )
      throw error
    }
    recordNetwork(
      .notice,
      event: "request_success",
      message: L10n.tr("diagnostic.message.backendStationRequestSucceeded"),
      request: request,
      payload: [
        "status_code": String(httpResponse.statusCode),
        "duration_ms": DiagnosticsPayload.durationMilliseconds(Date().timeIntervalSince(startedAt))
      ]
    )
    return try payload.station()
  }

  func generateStation(context: RadioStationGenerationContext) async throws -> RadioStationResult {
    guard let baseURL else {
      throw RadioStationClientError.disabled
    }

    let endpoint = baseURL.appending(path: "v1/radio/stations/generate")
    var request = URLRequest(url: endpoint, timeoutInterval: generationTimeout)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    applyLocalizationHeaders(to: &request)
    request.httpBody = try encoder.encode(context)

    do {
      let payload: RadioStationPayload = try await decodedPayload(for: request)
      return try payload.result()
    } catch RadioStationClientError.serverStatus(404) {
      recordNetwork(
        .warning,
        event: "generate_fallback_current",
        message: L10n.tr("diagnostic.message.radioGenerateEndpointFallback"),
        request: request,
        payload: ["status_code": "404"]
      )
      return RadioStationResult(
        station: try await fetchCurrentStation(),
        diagnostics: [L10n.tr("radio.diagnostic.generateEndpointFallback")]
      )
    }
  }

  func fetchSpeechVoices() async throws -> RadioSpeechVoiceCatalog {
    guard let baseURL else {
      throw RadioStationClientError.disabled
    }

    let endpoint = baseURL.appending(path: "v1/radio/speech/voices")
    var request = URLRequest(url: endpoint, timeoutInterval: timeout)
    request.httpMethod = "GET"
    applyLocalizationHeaders(to: &request)

    do {
      return try await decodedPayload(for: request)
    } catch RadioStationClientError.serverStatus(404) {
      return .fallback
    }
  }

  func compressMemory(_ requestPayload: RadioMemoryCompressionRequest) async throws -> RadioCompressedMemory? {
    guard let baseURL else {
      throw RadioStationClientError.disabled
    }

    let endpoint = baseURL.appending(path: "v1/radio/memory/compress")
    var request = URLRequest(url: endpoint, timeoutInterval: timeout)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    applyLocalizationHeaders(to: &request)
    request.httpBody = try encoder.encode(requestPayload)

    let response: RadioMemoryCompressionPayload = try await decodedPayload(for: request)
    return response.compressedMemoryProposal
  }

  private func decodedPayload<T: Decodable>(for request: URLRequest) async throws -> T {
    let startedAt = Date()
    recordNetwork(
      .info,
      event: "request_start",
      message: L10n.tr("diagnostic.message.backendRequestStarted"),
      request: request
    )

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      recordNetwork(
        .error,
        event: "request_failed",
        message: L10n.tr("diagnostic.message.backendRequestFailed"),
        request: request,
        payload: DiagnosticsPayload.error(error)
      )
      throw error
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      recordNetwork(
        .error,
        event: "invalid_response",
        message: L10n.tr("diagnostic.message.backendInvalidResponse"),
        request: request,
        payload: ["duration_ms": DiagnosticsPayload.durationMilliseconds(Date().timeIntervalSince(startedAt))]
      )
      throw RadioStationClientError.invalidResponse
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      recordNetwork(
        .error,
        event: "server_status",
        message: L10n.tr("diagnostic.message.backendServerStatus"),
        request: request,
        payload: [
          "status_code": String(httpResponse.statusCode),
          "duration_ms": DiagnosticsPayload.durationMilliseconds(Date().timeIntervalSince(startedAt))
        ]
      )
      throw RadioStationClientError.serverStatus(httpResponse.statusCode)
    }

    do {
      let payload = try decoder.decode(T.self, from: data)
      recordNetwork(
        .notice,
        event: "request_success",
        message: L10n.tr("diagnostic.message.backendRequestSucceeded"),
        request: request,
        payload: [
          "status_code": String(httpResponse.statusCode),
          "duration_ms": DiagnosticsPayload.durationMilliseconds(Date().timeIntervalSince(startedAt))
        ]
      )
      return payload
    } catch {
      recordNetwork(
        .error,
        event: "decode_failed",
        message: L10n.tr("diagnostic.message.backendDecodeFailed"),
        request: request,
        payload: DiagnosticsPayload.error(error)
      )
      throw error
    }
  }

  private func recordNetwork(
    _ level: DiagnosticLogLevel,
    event: String,
    message: String,
    request: URLRequest,
    payload: [String: String] = [:]
  ) {
    guard let diagnostics else { return }
    let requestPayload = DiagnosticsPayload.merge(
      [
        "method": request.httpMethod ?? "GET",
        "endpoint_path": request.url?.path ?? "unknown",
        "timeout_seconds": String(Int(request.timeoutInterval.rounded()))
      ],
      DiagnosticsPayload.url(request.url),
      payload
    )

    Task { @MainActor in
      diagnostics.record(
        level,
        chain: .network,
        event: event,
        message: message,
        payload: requestPayload
      )
    }
  }

  private func applyLocalizationHeaders(to request: inout URLRequest) {
    request.setValue(AppLanguage.acceptLanguageHeader(), forHTTPHeaderField: "Accept-Language")
  }
}

enum RadioStationClientError: LocalizedError, Equatable {
  case disabled
  case invalidResponse
  case serverStatus(Int)
  case emptyStation
  case unplayableItem(String)

  var errorDescription: String? {
    switch self {
    case .disabled:
      L10n.tr("radioClient.error.disabled")
    case .invalidResponse:
      L10n.tr("radioClient.error.invalidResponse")
    case let .serverStatus(statusCode):
      L10n.tr("radioClient.error.serverStatus", statusCode)
    case .emptyStation:
      L10n.tr("radioClient.error.emptyStation")
    case let .unplayableItem(title):
      L10n.tr("radioClient.error.unplayableItem", title)
    }
  }
}

private struct RadioStationPayload: Decodable {
  let stationID: String
  let stationSessionID: String?
  let continuationCursor: String?
  let title: String
  let subtitle: String
  let items: [RadioStationItemPayload]
  let speech: RadioSpeech?
  let diagnostics: [String]
  let memoryPatchProposals: [RadioMemoryPatchProposal]

  enum CodingKeys: String, CodingKey {
    case id
    case stationID
    case stationId
    case stationSessionID
    case stationSessionId
    case sessionID
    case sessionId
    case continuationCursor
    case cursor
    case title
    case subtitle
    case intro
    case items
    case speech
    case diagnostics
    case memoryPatchProposals
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    stationID = try container.decodeIfPresent(String.self, forKey: .stationID)
      ?? container.decodeIfPresent(String.self, forKey: .stationId)
      ?? container.decodeIfPresent(String.self, forKey: .id)
      ?? "current"
    stationSessionID = try container.decodeIfPresent(String.self, forKey: .stationSessionID)
      ?? container.decodeIfPresent(String.self, forKey: .stationSessionId)
      ?? container.decodeIfPresent(String.self, forKey: .sessionID)
      ?? container.decodeIfPresent(String.self, forKey: .sessionId)
    continuationCursor = try container.decodeIfPresent(String.self, forKey: .continuationCursor)
      ?? container.decodeIfPresent(String.self, forKey: .cursor)
    title = try container.decodeIfPresent(String.self, forKey: .title) ?? L10n.tr("radio.defaultTitle")
    subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
      ?? container.decodeIfPresent(String.self, forKey: .intro)
      ?? L10n.tr("radio.streamingBackendQueue")
    items = try container.decode([RadioStationItemPayload].self, forKey: .items)
    speech = try container.decodeIfPresent(RadioSpeech.self, forKey: .speech)
    diagnostics = try container.decodeIfPresent([String].self, forKey: .diagnostics) ?? []
    memoryPatchProposals = try container.decodeIfPresent([RadioMemoryPatchProposal].self, forKey: .memoryPatchProposals) ?? []
  }

  func station() throws -> RadioStation {
    let queueItems = items.compactMap { try? $0.queueItem() }
    guard !queueItems.isEmpty else {
      throw RadioStationClientError.emptyStation
    }

    return RadioStation(
      id: stationID,
      title: title,
      subtitle: subtitle,
      items: queueItems,
      speech: speech
    )
  }

  func result() throws -> RadioStationResult {
    RadioStationResult(
      station: try station(),
      diagnostics: diagnostics,
      memoryPatchProposals: memoryPatchProposals,
      stationSessionID: stationSessionID,
      continuationCursor: continuationCursor
    )
  }
}

private struct RadioMemoryCompressionPayload: Decodable {
  let compressedMemoryProposal: RadioCompressedMemory
}

private struct RadioStationItemPayload: Decodable {
  let id: String?
  let title: String
  let artist: String
  let album: String?
  let mood: String?
  let duration: TimeInterval?
  let artworkSystemName: String?
  let artworkURL: URL?
  let previewURL: URL?
  let appleMusicID: String?
  let isExplicit: Bool?
  let sourceTitle: String?
  let source: String?
  let sourceLane: String?
  let reason: String?
  let handoffText: String?

  enum CodingKeys: String, CodingKey {
    case id
    case itemID
    case itemId
    case title
    case artist
    case album
    case mood
    case duration
    case artworkSystemName
    case artworkURL
    case artworkUrl
    case previewURL
    case previewUrl
    case appleMusicID
    case appleMusicId
    case isExplicit
    case sourceTitle
    case source
    case sourceLane
    case reason
    case handoffText
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(String.self, forKey: .itemID)
      ?? container.decodeIfPresent(String.self, forKey: .itemId)
      ?? container.decodeIfPresent(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    artist = try container.decode(String.self, forKey: .artist)
    album = try container.decodeIfPresent(String.self, forKey: .album)
    mood = try container.decodeIfPresent(String.self, forKey: .mood)
    duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
    artworkSystemName = try container.decodeIfPresent(String.self, forKey: .artworkSystemName)
    artworkURL = try container.decodeIfPresent(URL.self, forKey: .artworkURL)
      ?? container.decodeIfPresent(URL.self, forKey: .artworkUrl)
    let rawPreviewURL = try container.decodeIfPresent(URL.self, forKey: .previewURL)
      ?? container.decodeIfPresent(URL.self, forKey: .previewUrl)
    previewURL = rawPreviewURL?.playableRemoteAudioURL
    appleMusicID = (
      try container.decodeIfPresent(String.self, forKey: .appleMusicID)
        ?? container.decodeIfPresent(String.self, forKey: .appleMusicId)
    )?.trimmedNilIfEmpty
    isExplicit = try container.decodeIfPresent(Bool.self, forKey: .isExplicit)
    sourceTitle = try container.decodeIfPresent(String.self, forKey: .sourceTitle)?.trimmedNilIfEmpty
    source = try container.decodeIfPresent(String.self, forKey: .source)?.trimmedNilIfEmpty
    sourceLane = try container.decodeIfPresent(String.self, forKey: .sourceLane)?.trimmedNilIfEmpty
    reason = try container.decodeIfPresent(String.self, forKey: .reason)?.trimmedNilIfEmpty
    handoffText = try container.decodeIfPresent(String.self, forKey: .handoffText)?.trimmedNilIfEmpty
  }

  func queueItem() throws -> RadioQueueItem {
    let track = Track(
      title: title,
      artist: artist,
      album: album ?? L10n.tr("radio.backendRadio"),
      mood: mood ?? "Radio",
      duration: duration ?? 0,
      artworkSystemName: artworkSystemName ?? "dot.radiowaves.left.and.right",
      artworkURL: artworkURL,
      previewURL: previewURL,
      appleMusicID: appleMusicID,
      isExplicit: isExplicit ?? false,
      source: source,
      sourceLane: sourceLane
    )

    guard track.isPlayable else {
      throw RadioStationClientError.unplayableItem(title)
    }

    return RadioQueueItem(
      id: id?.trimmedNilIfEmpty ?? track.radioIdentity,
      track: track,
      sourceTitle: sourceTitle ?? sourceLane ?? source ?? L10n.tr("radio.backendStation"),
      reason: reason ?? "Queued by the backend station.",
      handoffText: handoffText
    )
  }
}

private extension URL {
  var playableRemoteAudioURL: URL? {
    guard let scheme = scheme?.lowercased(), ["http", "https"].contains(scheme), host != nil else {
      return nil
    }
    return self
  }
}

private extension String {
  var trimmedNilIfEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
