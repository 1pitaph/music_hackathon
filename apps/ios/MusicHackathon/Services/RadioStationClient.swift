import Foundation

protocol RadioStationFetching {
  func fetchCurrentStation() async throws -> RadioStation
  func generateStation(context: RadioStationGenerationContext) async throws -> RadioStationResult
  func compressMemory(_ request: RadioMemoryCompressionRequest) async throws -> RadioCompressedMemory?
}

extension RadioStationFetching {
  func generateStation(context: RadioStationGenerationContext) async throws -> RadioStationResult {
    RadioStationResult(station: try await fetchCurrentStation())
  }

  func compressMemory(_ request: RadioMemoryCompressionRequest) async throws -> RadioCompressedMemory? {
    nil
  }
}

struct RadioStationResult: Equatable {
  let station: RadioStation
  var diagnostics: [String] = []
  var memoryPatchProposals: [RadioMemoryPatchProposal] = []
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
  var limit = 12
  var stationID = "airset-personal"
  var title = "Airset Radio"
  var speechAudio = RadioSpeechAudioRequest(enabled: true)

  init(
    seedTracks: [Track],
    catalogCandidates: [Track],
    memoryContext: RadioMemoryContext,
    limit: Int = 12
  ) {
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
  var provider = "openai"
  var voice = "coral"
  var model = "gpt-4o-mini-tts"
  var format = "mp3"
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
    appleMusicID = track.appleMusicID
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
  private let decoder: JSONDecoder
  private let encoder: JSONEncoder

  init(
    baseURL: URL? = Self.defaultBaseURL,
    session: URLSession = .shared,
    timeout: TimeInterval = 15.0
  ) {
    self.baseURL = baseURL
    self.session = session
    self.timeout = timeout
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

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw RadioStationClientError.invalidResponse
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      throw RadioStationClientError.serverStatus(httpResponse.statusCode)
    }

    let payload = try decoder.decode(RadioStationPayload.self, from: data)
    return try payload.station()
  }

  func generateStation(context: RadioStationGenerationContext) async throws -> RadioStationResult {
    guard let baseURL else {
      throw RadioStationClientError.disabled
    }

    let endpoint = baseURL.appending(path: "v1/radio/stations/generate")
    var request = URLRequest(url: endpoint, timeoutInterval: timeout)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try encoder.encode(context)

    do {
      let payload: RadioStationPayload = try await decodedPayload(for: request)
      return try payload.result()
    } catch RadioStationClientError.serverStatus(404) {
      return RadioStationResult(
        station: try await fetchCurrentStation(),
        diagnostics: ["Station generation endpoint is not deployed yet; used current station fallback."]
      )
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
    request.httpBody = try encoder.encode(requestPayload)

    let response: RadioMemoryCompressionPayload = try await decodedPayload(for: request)
    return response.compressedMemoryProposal
  }

  private func decodedPayload<T: Decodable>(for request: URLRequest) async throws -> T {
    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw RadioStationClientError.invalidResponse
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      throw RadioStationClientError.serverStatus(httpResponse.statusCode)
    }

    return try decoder.decode(T.self, from: data)
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
      "Radio station API is disabled for this build."
    case .invalidResponse:
      "Radio station API returned an invalid response."
    case let .serverStatus(statusCode):
      "Radio station API returned HTTP \(statusCode)."
    case .emptyStation:
      "Radio station API returned an empty station."
    case let .unplayableItem(title):
      "Radio station item is missing a playable Apple Music ID or preview URL: \(title)."
    }
  }
}

private struct RadioStationPayload: Decodable {
  let stationID: String
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
    title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Airset Radio"
    subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
      ?? container.decodeIfPresent(String.self, forKey: .intro)
      ?? "Streaming from the backend station queue."
    items = try container.decode([RadioStationItemPayload].self, forKey: .items)
    speech = try container.decodeIfPresent(RadioSpeech.self, forKey: .speech)
    diagnostics = try container.decodeIfPresent([String].self, forKey: .diagnostics) ?? []
    memoryPatchProposals = try container.decodeIfPresent([RadioMemoryPatchProposal].self, forKey: .memoryPatchProposals) ?? []
  }

  func station() throws -> RadioStation {
    let queueItems = try items.map { try $0.queueItem() }
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
      memoryPatchProposals: memoryPatchProposals
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
    previewURL = try container.decodeIfPresent(URL.self, forKey: .previewURL)
      ?? container.decodeIfPresent(URL.self, forKey: .previewUrl)
    appleMusicID = try container.decodeIfPresent(String.self, forKey: .appleMusicID)
      ?? container.decodeIfPresent(String.self, forKey: .appleMusicId)
    isExplicit = try container.decodeIfPresent(Bool.self, forKey: .isExplicit)
    sourceTitle = try container.decodeIfPresent(String.self, forKey: .sourceTitle)
    source = try container.decodeIfPresent(String.self, forKey: .source)
    reason = try container.decodeIfPresent(String.self, forKey: .reason)
    handoffText = try container.decodeIfPresent(String.self, forKey: .handoffText)
  }

  func queueItem() throws -> RadioQueueItem {
    let track = Track(
      title: title,
      artist: artist,
      album: album ?? "Backend Radio",
      mood: mood ?? "Radio",
      duration: duration ?? 0,
      artworkSystemName: artworkSystemName ?? "dot.radiowaves.left.and.right",
      artworkURL: artworkURL,
      previewURL: previewURL,
      appleMusicID: appleMusicID,
      isExplicit: isExplicit ?? false
    )

    guard track.isPlayable else {
      throw RadioStationClientError.unplayableItem(title)
    }

    return RadioQueueItem(
      id: id ?? track.radioIdentity,
      track: track,
      sourceTitle: sourceTitle ?? source ?? "Backend station",
      reason: reason ?? "Queued by the backend station.",
      handoffText: handoffText
    )
  }
}
