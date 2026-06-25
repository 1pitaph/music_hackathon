import Foundation
import Observation

protocol RadioStationFetching {
  func fetchCurrentStation() async throws -> RadioStation
  func generateStation(context: RadioStationGenerationContext) async throws -> RadioStationResult
  func fetchSpeechVoices() async throws -> RadioSpeechVoiceCatalog
  func compressMemory(_ request: RadioMemoryCompressionRequest) async throws -> RadioCompressedMemory?
}

protocol DiscoverStationServing {
  func fetchDiscoverStations(cursor: String?, limit: Int) async throws -> DiscoverFeedPage
  func publishDiscoverStation(_ draft: DiscoverStationPublicationDraft) async throws -> PublishedDiscoverStation
  func fetchPublishedStation(id: String) async throws -> PublishedDiscoverStation
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

enum DiscoverFeedState: Equatable {
  case idle
  case loading
  case loaded
  case empty
  case failed(String)

  var isLoading: Bool {
    self == .loading
  }
}

protocol PublishedDiscoverStationArchiving {
  func load() async throws -> [PublishedDiscoverStation]
  func save(_ stations: [PublishedDiscoverStation]) async throws
}

actor PublishedDiscoverStationArchiveStore: PublishedDiscoverStationArchiving {
  private let fileURL: URL

  init(fileURL: URL? = nil) {
    self.fileURL = fileURL ?? Self.defaultFileURL()
  }

  func load() async throws -> [PublishedDiscoverStation] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return []
    }

    let data = try Data(contentsOf: fileURL)
    return try JSONDecoder().decode([PublishedDiscoverStation].self, from: data)
  }

  func save(_ stations: [PublishedDiscoverStation]) async throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(stations)
    try data.write(to: fileURL, options: .atomic)
  }

  private static func defaultFileURL() -> URL {
    let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return baseURL
      .appending(path: "AirsetDiscover", directoryHint: .isDirectory)
      .appending(path: "my-published-stations.json")
  }
}

@MainActor
@Observable
final class DiscoverStationStore {
  var state: DiscoverFeedState = .idle
  var stations: [DiscoverStation] = []
  var myPublishedStations: [PublishedDiscoverStation] = []
  var nextCursor: String?
  var lastErrorMessage: String?

  @ObservationIgnored private let client: any RadioStationFetching & DiscoverStationServing
  @ObservationIgnored private let publishedArchive: any PublishedDiscoverStationArchiving
  @ObservationIgnored private var hasLoadedMyPublishedStations = false

  init(
    client: any RadioStationFetching & DiscoverStationServing = RadioStationClient(),
    publishedArchive: any PublishedDiscoverStationArchiving = PublishedDiscoverStationArchiveStore()
  ) {
    self.client = client
    self.publishedArchive = publishedArchive
  }

  func loadIfNeeded() async {
    guard stations.isEmpty else { return }
    await refresh()
  }

  func refresh() async {
    state = .loading
    lastErrorMessage = nil

    do {
      let page = try await client.fetchDiscoverStations(cursor: nil, limit: 20)
      apply(page)
    } catch is CancellationError {
      return
    } catch {
      state = .failed(Self.errorMessage(for: error))
      lastErrorMessage = Self.errorMessage(for: error)
      stations = []
      nextCursor = nil
    }
  }

  func generatePublicationDraft(
    seedTracks: [Track],
    visibility: RadioStationVisibility,
    ownerID: String,
    ownerDisplayName: String
  ) async -> DiscoverStationPublicationDraft {
    do {
      let context = RadioStationGenerationContext(
        seedTracks: seedTracks,
        catalogCandidates: seedTracks,
        memoryContext: RadioMemoryContext(),
        limit: 5,
        stationID: "published-\(UUID().uuidString.lowercased())",
        speechLanguage: RadioSpeechLanguage.stored()
      )
      let result = try await client.generateStation(context: context)
      let fixedStation = RadioStation(
        id: result.station.id,
        title: result.station.title,
        subtitle: result.station.subtitle,
        items: Array(result.station.items.prefix(5)),
        speech: result.station.speech,
        allowsAutoExtension: false
      )
      return publicationDraft(
        station: fixedStation,
        seedTracks: seedTracks,
        visibility: visibility,
        ownerID: ownerID,
        ownerDisplayName: ownerDisplayName,
        usedFallbackGeneration: false
      )
    } catch is CancellationError {
      return fallbackPublicationDraft(
        seedTracks: seedTracks,
        visibility: visibility,
        ownerID: ownerID,
        ownerDisplayName: ownerDisplayName
      )
    } catch {
      return fallbackPublicationDraft(
        seedTracks: seedTracks,
        visibility: visibility,
        ownerID: ownerID,
        ownerDisplayName: ownerDisplayName
      )
    }
  }

  func publish(_ draft: DiscoverStationPublicationDraft) async throws -> DiscoverStation {
    let publishedStation = try await client.publishDiscoverStation(draft)
    await rememberMyPublishedStation(publishedStation)

    let discoverStation = publishedStation.discoverStation()
    if publishedStation.visibility == .public {
      stations.removeAll { $0.id == discoverStation.id }
      stations.insert(discoverStation, at: 0)
      state = stations.isEmpty ? .empty : .loaded
    }
    return discoverStation
  }

  func loadMyPublishedStationsIfNeeded() async {
    guard !hasLoadedMyPublishedStations else { return }

    do {
      myPublishedStations = try await publishedArchive.load()
      hasLoadedMyPublishedStations = true
    } catch {
      myPublishedStations = []
      hasLoadedMyPublishedStations = true
    }
  }

  private func apply(_ page: DiscoverFeedPage) {
    stations = page.stations.map { $0.discoverStation() }
    nextCursor = page.nextCursor
    state = stations.isEmpty ? .empty : .loaded
  }

  private func rememberMyPublishedStation(_ station: PublishedDiscoverStation) async {
    await loadMyPublishedStationsIfNeeded()
    myPublishedStations.removeAll { $0.stationID == station.stationID }
    myPublishedStations.insert(station, at: 0)

    do {
      try await publishedArchive.save(myPublishedStations)
    } catch {
      lastErrorMessage = Self.errorMessage(for: error)
    }
  }

  private func publicationDraft(
    station: RadioStation,
    seedTracks: [Track],
    visibility: RadioStationVisibility,
    ownerID: String,
    ownerDisplayName: String,
    usedFallbackGeneration: Bool
  ) -> DiscoverStationPublicationDraft {
    DiscoverStationPublicationDraft(
      title: station.title,
      subtitle: station.subtitle,
      description: station.subtitle,
      visibility: visibility,
      ownerID: ownerID,
      ownerDisplayName: ownerDisplayName,
      seedTracks: seedTracks,
      station: station,
      coverArtworkURL: seedTracks.first?.artworkURL ?? station.items.first?.track.artworkURL,
      colorHex: "#D8633C",
      usedFallbackGeneration: usedFallbackGeneration
    )
  }

  private func fallbackPublicationDraft(
    seedTracks: [Track],
    visibility: RadioStationVisibility,
    ownerID: String,
    ownerDisplayName: String
  ) -> DiscoverStationPublicationDraft {
    let stationID = "local-published-\(UUID().uuidString.lowercased())"
    let items = seedTracks.prefix(5).enumerated().map { offset, track in
      RadioQueueItem(
        id: "\(stationID)-\(offset)",
        track: track,
        sourceTitle: ownerDisplayName,
        reason: L10n.tr("discover.publish.fallbackReason", ownerDisplayName, track.title),
        handoffText: offset == 0 ? L10n.tr("discover.publish.fallbackIntro", track.title) : nil
      )
    }
    let title = L10n.tr("discover.publish.fallbackTitle", ownerDisplayName)
    let subtitle = L10n.tr("discover.publish.fallbackSubtitle", seedTracks.first?.title ?? title)
    let station = RadioStation(
      id: stationID,
      title: title,
      subtitle: subtitle,
      items: items,
      speech: nil,
      allowsAutoExtension: false
    )
    return publicationDraft(
      station: station,
      seedTracks: seedTracks,
      visibility: visibility,
      ownerID: ownerID,
      ownerDisplayName: ownerDisplayName,
      usedFallbackGeneration: true
    )
  }

  private static func errorMessage(for error: Error) -> String {
    (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
  }
}

enum DiscoverPublisherIdentity {
  private static let ownerIDKey = "discover.publisher.ownerID"
  private static let nicknameKey = "mine.profile.nickname"

  static func ownerID(defaults: UserDefaults = .standard) -> String {
    if let existingID = defaults.string(forKey: ownerIDKey)?.trimmedNilIfEmpty {
      return existingID
    }

    let newID = "ios-\(UUID().uuidString.lowercased())"
    defaults.set(newID, forKey: ownerIDKey)
    return newID
  }

  static func displayName(defaults: UserDefaults = .standard) -> String {
    defaults.string(forKey: nicknameKey)?.trimmedNilIfEmpty
      ?? L10n.tr("discover.publish.defaultOwnerName")
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
    speechAudio.speaker = speechLanguage.resolvedHostSpeakerID(preferredSpeakerID: hostSpeakerID)
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
  var delivery = "stream"
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

  enum CodingKeys: String, CodingKey {
    case radioIdentity
    case title
    case artist
    case album
    case mood
    case duration
    case artworkURL
    case artworkUrl
    case previewURL
    case previewUrl
    case appleMusicID
    case appleMusicId
    case isExplicit
    case playlistName
    case source
    case sourceLane
    case sourceScore
    case reasonSignals
  }

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

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    title = try container.decode(String.self, forKey: .title)
    artist = try container.decode(String.self, forKey: .artist)
    album = try container.decodeIfPresent(String.self, forKey: .album) ?? ""
    mood = try container.decodeIfPresent(String.self, forKey: .mood) ?? ""
    duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
    artworkURL = try container.decodeIfPresent(URL.self, forKey: .artworkURL)
      ?? container.decodeIfPresent(URL.self, forKey: .artworkUrl)
    previewURL = try container.decodeIfPresent(URL.self, forKey: .previewURL)
      ?? container.decodeIfPresent(URL.self, forKey: .previewUrl)
    appleMusicID = (
      try container.decodeIfPresent(String.self, forKey: .appleMusicID)
        ?? container.decodeIfPresent(String.self, forKey: .appleMusicId)
    )?.trimmedNilIfEmpty
    isExplicit = try container.decodeIfPresent(Bool.self, forKey: .isExplicit) ?? false
    playlistName = try container.decodeIfPresent(String.self, forKey: .playlistName)?.trimmedNilIfEmpty
    source = try container.decodeIfPresent(String.self, forKey: .source)?.trimmedNilIfEmpty
    sourceLane = try container.decodeIfPresent(String.self, forKey: .sourceLane)?.trimmedNilIfEmpty
    sourceScore = try container.decodeIfPresent(Double.self, forKey: .sourceScore)
    reasonSignals = try container.decodeIfPresent([String].self, forKey: .reasonSignals) ?? []
    radioIdentity = try container.decodeIfPresent(String.self, forKey: .radioIdentity)?.trimmedNilIfEmpty
      ?? Track(
        title: title,
        artist: artist,
        album: album,
        mood: mood,
        duration: duration,
        artworkSystemName: "music.note",
        artworkURL: artworkURL,
        previewURL: previewURL,
        appleMusicID: appleMusicID,
        isExplicit: isExplicit,
        playlistName: playlistName,
        source: source,
        sourceLane: sourceLane,
        sourceScore: sourceScore,
        reasonSignals: reasonSignals
      ).radioIdentity
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(radioIdentity, forKey: .radioIdentity)
    try container.encode(title, forKey: .title)
    try container.encode(artist, forKey: .artist)
    try container.encode(album, forKey: .album)
    try container.encode(mood, forKey: .mood)
    try container.encode(duration, forKey: .duration)
    try container.encodeIfPresent(artworkURL, forKey: .artworkURL)
    try container.encodeIfPresent(previewURL, forKey: .previewURL)
    try container.encodeIfPresent(appleMusicID, forKey: .appleMusicID)
    try container.encode(isExplicit, forKey: .isExplicit)
    try container.encodeIfPresent(playlistName, forKey: .playlistName)
    try container.encodeIfPresent(source, forKey: .source)
    try container.encodeIfPresent(sourceLane, forKey: .sourceLane)
    try container.encodeIfPresent(sourceScore, forKey: .sourceScore)
    try container.encode(reasonSignals, forKey: .reasonSignals)
  }

  func track() -> Track {
    Track(
      title: title,
      artist: artist,
      album: album,
      mood: mood,
      duration: duration,
      artworkSystemName: "music.note",
      artworkURL: artworkURL,
      previewURL: previewURL,
      appleMusicID: appleMusicID,
      isExplicit: isExplicit,
      playlistName: playlistName,
      source: source,
      sourceLane: sourceLane,
      sourceScore: sourceScore,
      reasonSignals: reasonSignals
    )
  }
}

struct RadioStationClient: RadioStationFetching, DiscoverStationServing {
  static let defaultBaseURL = URL(string: "https://music.1pitaph.com")

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
    timeout: TimeInterval = 30.0,
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

  func fetchDiscoverStations(cursor: String? = nil, limit: Int = 20) async throws -> DiscoverFeedPage {
    guard let baseURL else {
      throw RadioStationClientError.disabled
    }

    let endpoint = discoverStationsURL(
      baseURL: baseURL,
      cursor: cursor,
      limit: limit
    )
    var request = URLRequest(url: endpoint, timeoutInterval: timeout)
    request.httpMethod = "GET"
    applyLocalizationHeaders(to: &request)

    let payload: DiscoverFeedPagePayload = try await decodedPayload(for: request)
    return try payload.page()
  }

  func publishDiscoverStation(_ draft: DiscoverStationPublicationDraft) async throws -> PublishedDiscoverStation {
    guard let baseURL else {
      throw RadioStationClientError.disabled
    }

    let endpoint = baseURL.appending(path: "v1/discover/stations")
    var request = URLRequest(url: endpoint, timeoutInterval: generationTimeout)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    applyLocalizationHeaders(to: &request)
    request.httpBody = try encoder.encode(DiscoverStationPublishPayload(draft: draft))

    let payload: PublishedDiscoverStationPayload = try await decodedPayload(for: request)
    return try payload.station()
  }

  func fetchPublishedStation(id: String) async throws -> PublishedDiscoverStation {
    guard let baseURL else {
      throw RadioStationClientError.disabled
    }

    let endpoint = baseURL.appending(path: "v1/radio/stations/\(id)")
    var request = URLRequest(url: endpoint, timeoutInterval: timeout)
    request.httpMethod = "GET"
    applyLocalizationHeaders(to: &request)

    let payload: PublishedDiscoverStationPayload = try await decodedPayload(for: request)
    return try payload.station()
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

  private func discoverStationsURL(baseURL: URL, cursor: String?, limit: Int) -> URL {
    let endpoint = baseURL.appending(path: "v1/discover/stations")
    guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
      return endpoint
    }

    components.queryItems = [
      URLQueryItem(name: "limit", value: "\(limit)"),
      cursor.map { URLQueryItem(name: "cursor", value: $0) }
    ].compactMap { $0 }
    return components.url ?? endpoint
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

private struct DiscoverFeedPagePayload: Decodable {
  let stations: [PublishedDiscoverStationPayload]
  let nextCursor: String?

  func page() throws -> DiscoverFeedPage {
    DiscoverFeedPage(
      stations: try stations.map { try $0.station() },
      nextCursor: nextCursor
    )
  }
}

private struct PublishedDiscoverStationPayload: Decodable {
  let stationID: String
  let title: String
  let subtitle: String
  let description: String
  let visibility: RadioStationVisibility
  let ownerID: String
  let ownerDisplayName: String
  let publishedAt: String
  let shareURL: URL
  let seedTracks: [RadioTrackPayload]
  let items: [RadioStationItemPayload]
  let speech: RadioSpeech?
  let coverArtworkURL: URL?
  let colorHex: String
  let favorites: Int

  enum CodingKeys: String, CodingKey {
    case id
    case stationID
    case stationId
    case title
    case subtitle
    case description
    case visibility
    case ownerID
    case ownerId
    case ownerDisplayName
    case publishedAt
    case shareURL
    case shareUrl
    case seedTracks
    case items
    case speech
    case coverArtworkURL
    case coverArtworkUrl
    case colorHex
    case favorites
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    stationID = try container.decodeIfPresent(String.self, forKey: .stationID)
      ?? container.decodeIfPresent(String.self, forKey: .stationId)
      ?? container.decodeIfPresent(String.self, forKey: .id)
      ?? "published"
    title = try container.decodeIfPresent(String.self, forKey: .title) ?? L10n.tr("radio.defaultTitle")
    subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
    description = try container.decodeIfPresent(String.self, forKey: .description) ?? subtitle
    visibility = try container.decodeIfPresent(RadioStationVisibility.self, forKey: .visibility) ?? .public
    ownerID = try container.decodeIfPresent(String.self, forKey: .ownerID)
      ?? container.decodeIfPresent(String.self, forKey: .ownerId)
      ?? "anonymous"
    ownerDisplayName = try container.decodeIfPresent(String.self, forKey: .ownerDisplayName)
      ?? L10n.tr("discover.publish.defaultOwnerName")
    publishedAt = try container.decodeIfPresent(String.self, forKey: .publishedAt) ?? ""
    shareURL = try container.decodeIfPresent(URL.self, forKey: .shareURL)
      ?? container.decodeIfPresent(URL.self, forKey: .shareUrl)
      ?? URL(string: "https://airset.example/stations/\(stationID)")!
    seedTracks = try container.decodeIfPresent([RadioTrackPayload].self, forKey: .seedTracks) ?? []
    items = try container.decode([RadioStationItemPayload].self, forKey: .items)
    speech = try container.decodeIfPresent(RadioSpeech.self, forKey: .speech)
    coverArtworkURL = try container.decodeIfPresent(URL.self, forKey: .coverArtworkURL)
      ?? container.decodeIfPresent(URL.self, forKey: .coverArtworkUrl)
    colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? "#D8633C"
    favorites = try container.decodeIfPresent(Int.self, forKey: .favorites) ?? 0
  }

  func station() throws -> PublishedDiscoverStation {
    let queueItems = items.compactMap { try? $0.queueItem() }
    guard !queueItems.isEmpty else {
      throw RadioStationClientError.emptyStation
    }

    return PublishedDiscoverStation(
      stationID: stationID,
      title: title,
      subtitle: subtitle,
      description: description,
      visibility: visibility,
      ownerID: ownerID,
      ownerDisplayName: ownerDisplayName,
      publishedAt: publishedAt,
      shareURL: shareURL,
      seedTracks: seedTracks.map { $0.track() },
      items: queueItems,
      speech: speech,
      coverArtworkURL: coverArtworkURL,
      colorHex: colorHex,
      favorites: favorites
    )
  }
}

private struct DiscoverStationPublishPayload: Encodable {
  let title: String
  let subtitle: String
  let description: String
  let visibility: RadioStationVisibility
  let ownerID: String
  let ownerDisplayName: String
  let seedTracks: [RadioTrackPayload]
  let items: [RadioStationItemPublishPayload]
  let speech: RadioSpeech?
  let coverArtworkURL: URL?
  let colorHex: String

  init(draft: DiscoverStationPublicationDraft) {
    title = draft.title
    subtitle = draft.subtitle
    description = draft.description
    visibility = draft.visibility
    ownerID = draft.ownerID
    ownerDisplayName = draft.ownerDisplayName
    seedTracks = draft.seedTracks.map {
      RadioTrackPayload(track: $0, playlistName: $0.playlistName, source: $0.source, sourceLane: $0.sourceLane)
    }
    items = draft.station.items.map(RadioStationItemPublishPayload.init)
    speech = draft.station.speech
    coverArtworkURL = draft.coverArtworkURL
    colorHex = draft.colorHex
  }
}

private struct RadioStationItemPublishPayload: Encodable {
  let id: String
  let title: String
  let artist: String
  let album: String
  let mood: String
  let duration: TimeInterval
  let artworkSystemName: String
  let artworkURL: URL?
  let previewURL: URL?
  let appleMusicID: String?
  let isExplicit: Bool
  let sourceTitle: String
  let source: String?
  let sourceLane: String?
  let reason: String
  let handoffText: String?

  init(item: RadioQueueItem) {
    id = item.id
    title = item.track.title
    artist = item.track.artist
    album = item.track.album
    mood = item.track.mood
    duration = item.track.duration
    artworkSystemName = item.track.artworkSystemName
    artworkURL = item.track.artworkURL
    previewURL = item.track.previewURL
    appleMusicID = item.track.normalizedAppleMusicID
    isExplicit = item.track.isExplicit
    sourceTitle = item.sourceTitle
    source = item.track.source
    sourceLane = item.track.sourceLane
    reason = item.reason
    handoffText = item.handoffText
  }
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
