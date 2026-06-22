import Foundation

protocol RadioAgentGenerating {
  func generateQueue(from context: RadioRuntimeContext, limit: Int) async throws -> RadioAgentGeneration
}

struct RadioAgentGeneration: Equatable {
  let mode: String
  let stationIntro: String
  let items: [RadioAgentGeneratedItem]
  let diagnostics: [String]
}

struct RadioAgentGeneratedItem: Equatable {
  let radioIdentity: String
  let reason: String
  let role: String
  let score: Double
  let source: String
}

struct RadioAgentClient: RadioAgentGenerating {
  #if DEBUG
  static let defaultBaseURL = URL(string: "http://127.0.0.1:8000")
  #else
  static let defaultBaseURL: URL? = nil
  #endif

  private let baseURL: URL?
  private let session: URLSession
  private let timeout: TimeInterval
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init(
    baseURL: URL? = Self.defaultBaseURL,
    session: URLSession = .shared,
    timeout: TimeInterval = 2.0
  ) {
    self.baseURL = baseURL
    self.session = session
    self.timeout = timeout
    encoder = JSONEncoder()
    decoder = JSONDecoder()
  }

  func generateQueue(from context: RadioRuntimeContext, limit: Int = 14) async throws -> RadioAgentGeneration {
    guard let baseURL else {
      throw RadioAgentClientError.disabled
    }

    let endpoint = baseURL.appending(path: "v1/radio/generate")
    var request = URLRequest(url: endpoint, timeoutInterval: timeout)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try encoder.encode(RadioAgentRequest(context: context, limit: limit))

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw RadioAgentClientError.invalidResponse
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      throw RadioAgentClientError.serverStatus(httpResponse.statusCode)
    }

    let payload = try decoder.decode(RadioAgentResponsePayload.self, from: data)
    return RadioAgentGeneration(
      mode: payload.mode,
      stationIntro: payload.stationIntro,
      items: payload.items.map {
        RadioAgentGeneratedItem(
          radioIdentity: $0.radioIdentity,
          reason: $0.reason,
          role: $0.role,
          score: $0.score,
          source: $0.source
        )
      },
      diagnostics: payload.diagnostics
    )
  }
}

enum RadioAgentClientError: LocalizedError, Equatable {
  case disabled
  case invalidResponse
  case serverStatus(Int)

  var errorDescription: String? {
    switch self {
    case .disabled:
      "Radio agent API is disabled for this build."
    case .invalidResponse:
      "Radio agent returned an invalid response."
    case let .serverStatus(statusCode):
      "Radio agent returned HTTP \(statusCode)."
    }
  }
}

private struct RadioAgentRequest: Encodable {
  let action: String
  let tuning: RadioAgentTuningPayload
  let seedTracks: [RadioAgentTrackPayload]
  let catalogCandidates: [RadioAgentTrackPayload]
  let memory: RadioAgentMemoryPayload
  let limit: Int

  init(context: RadioRuntimeContext, limit: Int) {
    action = context.currentAction.rawValue
    tuning = RadioAgentTuningPayload(tuning: context.tuning.normalized)
    seedTracks = context.seedTracks.map(RadioAgentTrackPayload.init(seedTrack:))
    catalogCandidates = context.catalogCandidates.map(RadioAgentTrackPayload.init(queueItem:))
    memory = RadioAgentMemoryPayload(memory: context.memory)
    self.limit = limit
  }
}

private struct RadioAgentTuningPayload: Encodable {
  let discoveryRatio: Double
  let familiarity: Double
  let energy: Double

  init(tuning: RadioTuning) {
    discoveryRatio = tuning.discoveryRatio
    familiarity = tuning.familiarity
    energy = tuning.energy
  }
}

private struct RadioAgentMemoryPayload: Encodable {
  let recentlyPlayedTrackKeys: [String]
  let likedTrackKeys: [String]
  let skippedTrackKeys: [String]
  let dislikedTrackKeys: [String]

  init(memory: RadioMemory) {
    recentlyPlayedTrackKeys = memory.recentlyPlayedTrackKeys
    likedTrackKeys = memory.likedTrackKeys.sorted()
    skippedTrackKeys = memory.skippedTrackKeys.sorted()
    dislikedTrackKeys = memory.dislikedTrackKeys.sorted()
  }
}

private struct RadioAgentTrackPayload: Encodable {
  let radioIdentity: String
  let title: String
  let artist: String
  let album: String
  let mood: String
  let duration: TimeInterval
  let appleMusicID: String?
  let playlistName: String?
  let source: String?

  init(seedTrack: RadioSeedTrack) {
    self.init(
      track: seedTrack.track,
      playlistName: seedTrack.playlistName,
      source: "playlist"
    )
  }

  init(queueItem: RadioQueueItem) {
    self.init(
      track: queueItem.track,
      playlistName: nil,
      source: queueItem.source.agentPayloadValue
    )
  }

  private init(track: Track, playlistName: String?, source: String?) {
    radioIdentity = track.radioIdentity
    title = track.title
    artist = track.artist
    album = track.album
    mood = track.mood
    duration = track.duration
    appleMusicID = track.appleMusicID
    self.playlistName = playlistName
    self.source = source
  }
}

private struct RadioAgentResponsePayload: Decodable {
  let mode: String
  let stationIntro: String
  let items: [RadioAgentItemPayload]
  let diagnostics: [String]
}

private struct RadioAgentItemPayload: Decodable {
  let radioIdentity: String
  let reason: String
  let role: String
  let score: Double
  let source: String
}

private extension RadioQueueSource {
  var agentPayloadValue: String {
    switch self {
    case .playlist:
      "playlist"
    case .catalog:
      "catalog"
    case .fallback:
      "fallback"
    }
  }
}
