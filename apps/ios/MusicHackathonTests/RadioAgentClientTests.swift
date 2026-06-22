import XCTest
@testable import MusicHackathon

final class RadioAgentClientTests: XCTestCase {
  func testEncodesContextAndDecodesGeneration() async throws {
    let session = makeSession { request in
      XCTAssertEqual(request.url?.absoluteString, "http://agent.test/v1/radio/generate")
      XCTAssertEqual(request.httpMethod, "POST")
      XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

      let body = try XCTUnwrap(Self.bodyData(from: request))
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
      XCTAssertEqual(json["action"] as? String, "start")
      XCTAssertEqual(json["limit"] as? Int, 2)

      let seedTracks = try XCTUnwrap(json["seedTracks"] as? [[String: Any]])
      XCTAssertEqual(seedTracks.first?["radioIdentity"] as? String, "appleMusic:seed-1")
      XCTAssertEqual(seedTracks.first?["playlistName"] as? String, "Morning")

      let catalogCandidates = try XCTUnwrap(json["catalogCandidates"] as? [[String: Any]])
      XCTAssertEqual(catalogCandidates.first?["radioIdentity"] as? String, "appleMusic:catalog-1")
      XCTAssertEqual(catalogCandidates.first?["source"] as? String, "catalog")

      let data = """
      {
        "mode": "llm",
        "stationIntro": "Agent intro",
        "items": [
          {
            "radioIdentity": "appleMusic:catalog-1",
            "reason": "Agent reason",
            "role": "discovery",
            "score": 88.5,
            "source": "catalog"
          }
        ],
        "diagnostics": ["ok"]
      }
      """.data(using: .utf8)!
      return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
    }
    let client = RadioAgentClient(baseURL: URL(string: "http://agent.test")!, session: session)

    let generation = try await client.generateQueue(from: makeContext(), limit: 2)

    XCTAssertEqual(generation.mode, "llm")
    XCTAssertEqual(generation.stationIntro, "Agent intro")
    XCTAssertEqual(generation.items, [
      RadioAgentGeneratedItem(
        radioIdentity: "appleMusic:catalog-1",
        reason: "Agent reason",
        role: "discovery",
        score: 88.5,
        source: "catalog"
      )
    ])
    XCTAssertEqual(generation.diagnostics, ["ok"])
  }

  func testThrowsForServerError() async {
    let session = makeSession { request in
      let data = Data("{}".utf8)
      return (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!, data)
    }
    let client = RadioAgentClient(baseURL: URL(string: "http://agent.test")!, session: session)

    do {
      _ = try await client.generateQueue(from: makeContext(), limit: 2)
      XCTFail("Expected server status error")
    } catch let error as RadioAgentClientError {
      XCTAssertEqual(error, .serverStatus(503))
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  private func makeContext() -> RadioRuntimeContext {
    let seed = makeTrack(title: "Seed", artist: "Artist A", appleMusicID: "seed-1")
    let catalog = makeTrack(title: "Catalog", artist: "Artist B", appleMusicID: "catalog-1")
    return RadioRuntimeContext(
      seedTracks: [RadioSeedTrack(track: seed, playlistID: "playlist-1", playlistName: "Morning")],
      catalogCandidates: [
        RadioQueueItem(
          track: catalog,
          source: .catalog(term: "Pop"),
          score: 0,
          reason: ""
        )
      ],
      memory: RadioMemory(),
      tuning: RadioTuning(),
      currentAction: .start
    )
  }

  private func makeTrack(title: String, artist: String, appleMusicID: String) -> Track {
    Track(
      title: title,
      artist: artist,
      album: "Album",
      mood: "Pop",
      duration: 210,
      artworkSystemName: "music.note",
      appleMusicID: appleMusicID
    )
  }

  private func makeSession(
    handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
  ) -> URLSession {
    MockURLProtocol.requestHandler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
  }

  private static func bodyData(from request: URLRequest) -> Data? {
    if let httpBody = request.httpBody {
      return httpBody
    }

    guard let stream = request.httpBodyStream else {
      return nil
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    while stream.hasBytesAvailable {
      let count = stream.read(buffer, maxLength: bufferSize)
      if count <= 0 {
        break
      }
      data.append(buffer, count: count)
    }

    return data
  }
}

private final class MockURLProtocol: URLProtocol {
  static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let requestHandler = Self.requestHandler else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }

    do {
      let (response, data) = try requestHandler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}
