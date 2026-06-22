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
