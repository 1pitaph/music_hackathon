import XCTest
@testable import MusicHackathon

final class RadioStationClientTests: XCTestCase {
  func testFetchCurrentStationRequestsAndDecodesPlayableQueue() async throws {
    let session = makeSession { request in
      XCTAssertEqual(request.url?.absoluteString, "http://station.test/v1/radio/stations/current")
      XCTAssertEqual(request.httpMethod, "GET")

      let data = """
      {
        "stationID": "station-1",
        "title": "Backend Radio",
        "subtitle": "A complete backend-programmed queue.",
        "items": [
          {
            "id": "item-1",
            "title": "Signal",
            "artist": "Artist A",
            "album": "Album A",
            "mood": "Electronic",
            "duration": 210,
            "appleMusicID": "song-1",
            "sourceTitle": "Backend",
            "reason": "Programmed by backend."
          },
          {
            "id": "item-2",
            "title": "Preview",
            "artist": "Artist B",
            "previewURL": "https://example.com/preview.m4a"
          }
        ]
      }
      """.data(using: .utf8)!
      return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
    }
    let client = RadioStationClient(baseURL: URL(string: "http://station.test")!, session: session)

    let station = try await client.fetchCurrentStation()

    XCTAssertEqual(station.id, "station-1")
    XCTAssertEqual(station.title, "Backend Radio")
    XCTAssertEqual(station.subtitle, "A complete backend-programmed queue.")
    XCTAssertEqual(station.items.count, 2)
    XCTAssertEqual(station.items[0].track.appleMusicID, "song-1")
    XCTAssertEqual(station.items[0].sourceTitle, "Backend")
    XCTAssertEqual(station.items[0].reason, "Programmed by backend.")
    XCTAssertEqual(station.items[1].track.previewURL?.absoluteString, "https://example.com/preview.m4a")
  }

  func testGenerateStationPostsMemoryContextAndDecodesResult() async throws {
    let session = makeSession { request in
      XCTAssertEqual(request.url?.absoluteString, "http://station.test/v1/radio/stations/generate")
      XCTAssertEqual(request.httpMethod, "POST")

      let body = try JSONSerialization.jsonObject(with: self.bodyData(from: request)) as? [String: Any]
      XCTAssertEqual(body?["stationID"] as? String, "airset-personal")
      let memoryContext = body?["memoryContext"] as? [String: Any]
      XCTAssertEqual(memoryContext?["tasteSummary"] as? String, "Likes intimate pop.")

      let data = """
      {
        "stationID": "airset-personal",
        "title": "Airset Radio",
        "subtitle": "Generated from local memory.",
        "mode": "mock",
        "diagnostics": ["ok"],
        "memoryPatchProposals": [
          {
            "op": "upsert",
            "type": "taste",
            "text": "User starts radio from WRABEL.",
            "confidence": 0.35,
            "source": "radio_generation"
          }
        ],
        "items": [
          {
            "id": "item-1",
            "title": "Signal",
            "artist": "Artist A",
            "previewURL": "https://example.com/preview.m4a"
          }
        ]
      }
      """.data(using: .utf8)!
      return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
    }
    let client = RadioStationClient(baseURL: URL(string: "http://station.test")!, session: session)
    let context = RadioStationGenerationContext(
      seedTracks: [makeTrack(title: "Seed")],
      catalogCandidates: [makeTrack(title: "Candidate")],
      memoryContext: RadioMemoryContext(tasteSummary: "Likes intimate pop.")
    )

    let result = try await client.generateStation(context: context)

    XCTAssertEqual(result.station.id, "airset-personal")
    XCTAssertEqual(result.station.subtitle, "Generated from local memory.")
    XCTAssertEqual(result.diagnostics, ["ok"])
    XCTAssertEqual(result.memoryPatchProposals.first?.type, "taste")
  }

  func testGenerateStationFallsBackToCurrentStationWhenEndpointIsMissing() async throws {
    let session = makeSession { request in
      if request.url?.path == "/v1/radio/stations/generate" {
        let data = Data("{}".utf8)
        return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, data)
      }

      XCTAssertEqual(request.url?.path, "/v1/radio/stations/current")
      let data = """
      {
        "stationID": "fallback",
        "title": "Fallback Radio",
        "items": [
          {
            "title": "Preview",
            "artist": "Artist B",
            "previewURL": "https://example.com/preview.m4a"
          }
        ]
      }
      """.data(using: .utf8)!
      return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
    }
    let client = RadioStationClient(baseURL: URL(string: "http://station.test")!, session: session)

    let result = try await client.generateStation(
      context: RadioStationGenerationContext(
        seedTracks: [makeTrack(title: "Seed")],
        catalogCandidates: [],
        memoryContext: RadioMemoryContext()
      )
    )

    XCTAssertEqual(result.station.id, "fallback")
    XCTAssertEqual(result.station.title, "Fallback Radio")
    XCTAssertEqual(
      result.diagnostics,
      ["Station generation endpoint is not deployed yet; used current station fallback."]
    )
  }

  func testCompressMemoryPostsRequestAndDecodesProposal() async throws {
    let session = makeSession { request in
      XCTAssertEqual(request.url?.absoluteString, "http://station.test/v1/radio/memory/compress")
      XCTAssertEqual(request.httpMethod, "POST")

      let data = """
      {
        "compressedMemoryProposal": {
          "tasteSummary": "Likes warm vocals.",
          "avoidSummary": "Avoid harsh noise.",
          "likedArtistsTop": ["WRABEL"],
          "skippedMoodsTop": ["Harsh"],
          "pinnedNotes": ["Night mode."]
        },
        "diagnostics": []
      }
      """.data(using: .utf8)!
      return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
    }
    let client = RadioStationClient(baseURL: URL(string: "http://station.test")!, session: session)

    let proposal = try await client.compressMemory(
      RadioMemoryCompressionRequest(
        existingSummary: RadioMemoryContext(),
        newEvents: [RadioMemoryEvent(type: "like", track: makeTrack(title: "Signal"))],
        pinnedNotes: [],
        maxOutputTokens: 500
      )
    )

    XCTAssertEqual(proposal?.tasteSummary, "Likes warm vocals.")
    XCTAssertEqual(proposal?.likedArtistsTop, ["WRABEL"])
  }

  func testThrowsForServerError() async {
    let session = makeSession { request in
      let data = Data("{}".utf8)
      return (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!, data)
    }
    let client = RadioStationClient(baseURL: URL(string: "http://station.test")!, session: session)

    do {
      _ = try await client.fetchCurrentStation()
      XCTFail("Expected server status error")
    } catch let error as RadioStationClientError {
      XCTAssertEqual(error, .serverStatus(503))
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testThrowsForEmptyStation() async {
    let session = makeSession { request in
      let data = """
      {
        "stationID": "empty",
        "title": "Empty",
        "items": []
      }
      """.data(using: .utf8)!
      return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
    }
    let client = RadioStationClient(baseURL: URL(string: "http://station.test")!, session: session)

    do {
      _ = try await client.fetchCurrentStation()
      XCTFail("Expected empty station error")
    } catch let error as RadioStationClientError {
      XCTAssertEqual(error, .emptyStation)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testThrowsForUnplayableItem() async {
    let session = makeSession { request in
      let data = """
      {
        "stationID": "station-1",
        "title": "Backend Radio",
        "items": [
          {
            "title": "Missing",
            "artist": "Artist A"
          }
        ]
      }
      """.data(using: .utf8)!
      return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
    }
    let client = RadioStationClient(baseURL: URL(string: "http://station.test")!, session: session)

    do {
      _ = try await client.fetchCurrentStation()
      XCTFail("Expected unplayable item error")
    } catch let error as RadioStationClientError {
      XCTAssertEqual(error, .unplayableItem("Missing"))
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  private func makeSession(
    handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
  ) -> URLSession {
    MockURLProtocol.requestHandler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
  }

  private func makeTrack(title: String) -> Track {
    Track(
      title: title,
      artist: "WRABEL",
      album: "Album",
      mood: "Pop",
      duration: 200,
      artworkSystemName: "music.note",
      previewURL: URL(string: "https://example.com/\(title).m4a")
    )
  }

  private func bodyData(from request: URLRequest) -> Data {
    if let httpBody = request.httpBody {
      return httpBody
    }

    guard let stream = request.httpBodyStream else {
      return Data()
    }

    stream.open()
    defer {
      stream.close()
    }

    var data = Data()
    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer {
      buffer.deallocate()
    }

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
