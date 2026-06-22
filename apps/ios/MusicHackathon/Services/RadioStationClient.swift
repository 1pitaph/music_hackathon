import Foundation

protocol RadioStationFetching {
  func fetchCurrentStation() async throws -> RadioStation
}

struct RadioStationClient: RadioStationFetching {
  static let defaultBaseURL = URL(string: "https://musichackathon-production.up.railway.app")

  private let baseURL: URL?
  private let session: URLSession
  private let timeout: TimeInterval
  private let decoder: JSONDecoder

  init(
    baseURL: URL? = Self.defaultBaseURL,
    session: URLSession = .shared,
    timeout: TimeInterval = 2.0
  ) {
    self.baseURL = baseURL
    self.session = session
    self.timeout = timeout
    decoder = JSONDecoder()
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

  enum CodingKeys: String, CodingKey {
    case id
    case stationID
    case stationId
    case title
    case subtitle
    case intro
    case items
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
      items: queueItems
    )
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
  let reason: String?

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
      reason: reason ?? "Queued by the backend station."
    )
  }
}
