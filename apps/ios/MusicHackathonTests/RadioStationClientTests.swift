import XCTest
@testable import MusicHackathon

final class RadioStationClientTests: XCTestCase {
  func testFetchCurrentStationRequestsAndDecodesPlayableQueue() async throws {
    let session = makeSession { request in
      XCTAssertEqual(request.url?.absoluteString, "http://station.test/v1/radio/stations/current")
      XCTAssertEqual(request.httpMethod, "GET")
      XCTAssertEqual(request.timeoutInterval, 15.0)
      XCTAssertEqual(request.value(forHTTPHeaderField: "Accept-Language"), AppLanguage.acceptLanguageHeader())

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

  func testFetchCurrentStationFiltersInvalidPlayableFieldsAndPreservesSourceLane() async throws {
    let session = makeSession { request in
      let data = """
      {
        "stationID": "station-1",
        "title": "Backend Radio",
        "items": [
          {
            "id": "bad-item",
            "title": "Missing",
            "artist": "Artist A",
            "appleMusicID": "   ",
            "previewURL": "ftp://example.com/not-playable.m4a"
          },
          {
            "id": "good-item",
            "title": "Signal",
            "artist": "Artist B",
            "appleMusicId": "  song-2  ",
            "previewUrl": "https://example.com/signal.m4a",
            "source": "virtual_music_library_json",
            "sourceLane": "familiar_anchor"
          }
        ]
      }
      """.data(using: .utf8)!
      return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
    }
    let client = RadioStationClient(baseURL: URL(string: "http://station.test")!, session: session)

    let station = try await client.fetchCurrentStation()

    XCTAssertEqual(station.items.map(\.id), ["good-item"])
    XCTAssertEqual(station.items[0].track.appleMusicID, "song-2")
    XCTAssertEqual(station.items[0].track.previewURL?.absoluteString, "https://example.com/signal.m4a")
    XCTAssertEqual(station.items[0].track.source, "virtual_music_library_json")
    XCTAssertEqual(station.items[0].track.sourceLane, "familiar_anchor")
    XCTAssertEqual(station.items[0].sourceTitle, "familiar_anchor")
  }

  func testGenerateStationPostsMemoryContextAndDecodesResult() async throws {
    let session = makeSession { request in
      XCTAssertEqual(request.url?.absoluteString, "http://station.test/v1/radio/stations/generate")
      XCTAssertEqual(request.httpMethod, "POST")
      XCTAssertEqual(request.timeoutInterval, 45.0)
      XCTAssertEqual(request.value(forHTTPHeaderField: "Accept-Language"), AppLanguage.acceptLanguageHeader())

      let body = try JSONSerialization.jsonObject(with: self.bodyData(from: request)) as? [String: Any]
      XCTAssertEqual(body?["stationID"] as? String, "airset-personal")
      XCTAssertEqual(body?["action"] as? String, "start")
      XCTAssertEqual(body?["limit"] as? Int, 6)
      XCTAssertEqual(body?["speechLanguage"] as? String, "zh-CN")
      let memoryContext = body?["memoryContext"] as? [String: Any]
      XCTAssertEqual(memoryContext?["tasteSummary"] as? String, "Likes intimate pop.")
      let speechAudio = body?["speechAudio"] as? [String: Any]
      XCTAssertEqual(speechAudio?["enabled"] as? Bool, true)
      XCTAssertEqual(speechAudio?["provider"] as? String, "volcengine")
      XCTAssertEqual(speechAudio?["speaker"] as? String, "zh_female_shuangkuaisisi_moon_bigtts")
      XCTAssertEqual(speechAudio?["resourceId"] as? String, "seed-tts-1.0")
      XCTAssertEqual(speechAudio?["model"] as? String, "seed-tts-1.0")
      XCTAssertEqual(speechAudio?["format"] as? String, "mp3")
      XCTAssertEqual(speechAudio?["speechRate"] as? Int, -6)
      XCTAssertNil(speechAudio?["loudnessRate"])
      XCTAssertEqual(speechAudio?["explicitLanguage"] as? String, "zh-CN")
      let catalogCandidates = body?["catalogCandidates"] as? [[String: Any]]
      XCTAssertEqual(catalogCandidates?.first?["playlistName"] as? String, "Virtual Library: Warm Starts")
      XCTAssertEqual(catalogCandidates?.first?["source"] as? String, "virtual_music_library_json")
      XCTAssertEqual(catalogCandidates?.first?["sourceLane"] as? String, "familiar_anchor")
      XCTAssertEqual(catalogCandidates?.first?["reasonSignals"] as? [String], ["warm opener", "intimate vocal"])

      let data = """
      {
        "stationID": "airset-personal",
        "stationSessionID": "session-1",
        "continuationCursor": "cursor-1",
        "title": "Airset Radio",
        "subtitle": "Generated from local memory.",
        "mode": "mock",
        "diagnostics": ["ok"],
        "speech": {
          "stationIntro": {
            "id": "station-intro",
            "text": "Welcome into this generated station.",
            "displayText": "Welcome into this generated station.",
            "targetItemId": "item-1",
            "agent": "entry_copy_agent",
            "audio": {
              "audioURL": "https://example.com/speech/intro.mp3",
              "mimeType": "audio/mpeg",
              "durationSeconds": 3.2,
              "cacheKey": "speech_intro",
              "voice": "coral",
              "model": "gpt-4o-mini-tts",
              "status": "ready"
            }
          },
          "betweenTracks": [
            {
              "id": "transition-1",
              "fromItemId": "previous-item",
              "toItemId": "item-1",
              "text": "From the opener, Airset is moving into Signal.",
              "displayText": "Next: Signal by Artist A.",
              "agent": "transition_copy_agent",
              "audio": {
                "audioURL": "https://example.com/speech/transition.mp3",
                "mimeType": "audio/mpeg",
                "durationSeconds": 2.8,
                "cacheKey": "speech_transition",
                "voice": "coral",
                "model": "gpt-4o-mini-tts",
                "status": "ready"
              }
            }
          ]
        },
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
            "previewURL": "https://example.com/preview.m4a",
            "handoffText": "Next: Signal by Artist A."
          }
        ]
      }
      """.data(using: .utf8)!
      return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
    }
    let client = RadioStationClient(baseURL: URL(string: "http://station.test")!, session: session)
    let context = RadioStationGenerationContext(
      seedTracks: [makeTrack(title: "Seed")],
      catalogCandidates: [
        makeTrack(
          title: "Candidate",
          playlistName: "Virtual Library: Warm Starts",
          source: "virtual_music_library_json",
          sourceLane: "familiar_anchor",
          reasonSignals: ["warm opener", "intimate vocal"]
        )
      ],
      memoryContext: RadioMemoryContext(tasteSummary: "Likes intimate pop."),
      hostSpeakerID: "zh_female_shuangkuaisisi_moon_bigtts"
    )

    let result = try await client.generateStation(context: context)

    XCTAssertEqual(result.station.id, "airset-personal")
    XCTAssertEqual(result.station.subtitle, "Generated from local memory.")
    XCTAssertEqual(result.station.speech?.stationIntro?.displayText, "Welcome into this generated station.")
    XCTAssertEqual(result.station.speech?.stationIntro?.audio?.audioURL?.absoluteString, "https://example.com/speech/intro.mp3")
    XCTAssertEqual(result.station.speech?.stationIntro?.audio?.status, "ready")
    XCTAssertEqual(result.station.speech?.betweenTracks.first?.toItemId, "item-1")
    XCTAssertEqual(result.station.speech?.betweenTracks.first?.audio?.cacheKey, "speech_transition")
    XCTAssertEqual(result.station.items.first?.handoffText, "Next: Signal by Artist A.")
    XCTAssertEqual(result.diagnostics, ["ok"])
    XCTAssertEqual(result.memoryPatchProposals.first?.type, "taste")
    XCTAssertEqual(result.stationSessionID, "session-1")
    XCTAssertEqual(result.continuationCursor, "cursor-1")
  }

  func testGenerateStationCanEncodeEnglishSpeechLanguage() async throws {
    let session = makeSession { request in
      let body = try JSONSerialization.jsonObject(with: self.bodyData(from: request)) as? [String: Any]
      XCTAssertEqual(body?["speechLanguage"] as? String, "en-US")
      let speechAudio = body?["speechAudio"] as? [String: Any]
      XCTAssertEqual(speechAudio?["speaker"] as? String, "en_female_lauren_moon_bigtts")
      XCTAssertEqual(speechAudio?["explicitLanguage"] as? String, "en-US")

      let data = """
      {
        "stationID": "airset-personal",
        "title": "Airset Radio",
        "subtitle": "English station intro.",
        "mode": "mock",
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
      catalogCandidates: [],
      memoryContext: RadioMemoryContext(),
      speechLanguage: .english
    )

    let result = try await client.generateStation(context: context)

    XCTAssertEqual(result.station.subtitle, "English station intro.")
  }

  func testEnglishSpeechLanguageUsesLaurenWhenPreferredSpeakerIsChinese() {
    let context = RadioStationGenerationContext(
      seedTracks: [makeTrack(title: "Seed")],
      catalogCandidates: [],
      memoryContext: RadioMemoryContext(),
      hostSpeakerID: "zh_female_shuangkuaisisi_moon_bigtts",
      speechLanguage: .english
    )

    XCTAssertEqual(context.speechAudio.speaker, "en_female_lauren_moon_bigtts")
    XCTAssertEqual(context.speechAudio.explicitLanguage, "en-US")
  }

  func testContinueStationPostsRollingQueueContextAndDecodesAliases() async throws {
    let session = makeSession { request in
      XCTAssertEqual(request.url?.absoluteString, "http://station.test/v1/radio/stations/generate")
      XCTAssertEqual(request.httpMethod, "POST")

      let body = try JSONSerialization.jsonObject(with: self.bodyData(from: request)) as? [String: Any]
      XCTAssertEqual(body?["action"] as? String, "continue")
      XCTAssertEqual(body?["limit"] as? Int, 6)
      XCTAssertEqual(body?["stationID"] as? String, "station-1")
      XCTAssertEqual(body?["stationSessionID"] as? String, "session-1")
      XCTAssertEqual(body?["continuationCursor"] as? String, "cursor-1")
      XCTAssertEqual(body?["currentTrackKey"] as? String, "appleMusic:current")
      XCTAssertEqual(body?["queuedTrackKeys"] as? [String], ["appleMusic:queued"])
      XCTAssertEqual(body?["recentlyPlayedTrackKeys"] as? [String], ["appleMusic:played"])

      let data = """
      {
        "stationID": "station-1",
        "sessionId": "session-2",
        "cursor": "cursor-2",
        "title": "Airset Radio",
        "items": [
          {
            "id": "item-next",
            "title": "Next Signal",
            "artist": "Artist A",
            "previewURL": "https://example.com/next.m4a"
          }
        ]
      }
      """.data(using: .utf8)!
      return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
    }
    let client = RadioStationClient(baseURL: URL(string: "http://station.test")!, session: session)
    let context = RadioStationGenerationContext(
      action: "continue",
      seedTracks: [makeTrack(title: "Seed")],
      catalogCandidates: [],
      memoryContext: RadioMemoryContext(),
      limit: 6,
      stationID: "station-1",
      stationSessionID: "session-1",
      continuationCursor: "cursor-1",
      currentTrackKey: "appleMusic:current",
      queuedTrackKeys: ["appleMusic:queued"],
      recentlyPlayedTrackKeys: ["appleMusic:played"]
    )

    let result = try await client.generateStation(context: context)

    XCTAssertEqual(result.station.items.first?.track.title, "Next Signal")
    XCTAssertEqual(result.stationSessionID, "session-2")
    XCTAssertEqual(result.continuationCursor, "cursor-2")
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
      [L10n.tr("radio.diagnostic.generateEndpointFallback")]
    )
  }

  func testFetchDiscoverStationsRequestsFeedAndDecodesPublishedStations() async throws {
    let session = makeSession { request in
      XCTAssertEqual(request.url?.path, "/v1/discover/stations")
      let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
      let queryItems = components?.queryItems ?? []
      XCTAssertEqual(queryItems.first(where: { $0.name == "cursor" })?.value, "cursor-1")
      XCTAssertEqual(queryItems.first(where: { $0.name == "limit" })?.value, "3")
      XCTAssertEqual(request.httpMethod, "GET")

      let data = """
      {
        "stations": [
          {
            "stationID": "station-1",
            "title": "Published Radio",
            "subtitle": "Five songs from a friend.",
            "description": "A published station.",
            "visibility": "public",
            "ownerID": "owner-1",
            "ownerDisplayName": "Publisher",
            "publishedAt": "2026-06-25T01:00:00.000Z",
            "shareURL": "https://share.test/stations/station-1",
            "coverArtworkURL": "https://example.com/cover.jpg",
            "colorHex": "#D8633C",
            "favorites": 8,
            "seedTracks": [
              {
                "radioIdentity": "seed-1",
                "title": "Seed",
                "artist": "Artist",
                "album": "Album",
                "mood": "Pop",
                "duration": 200,
                "artworkURL": "https://example.com/seed.jpg",
                "previewURL": "https://example.com/seed.m4a",
                "appleMusicID": "seed"
              }
            ],
            "items": [
              {
                "id": "item-1",
                "title": "Signal",
                "artist": "Artist A",
                "artworkURL": "https://example.com/signal.jpg",
                "previewURL": "https://example.com/signal.m4a",
                "sourceTitle": "Publisher",
                "reason": "Published by Publisher."
              }
            ]
          }
        ],
        "nextCursor": "cursor-2"
      }
      """.data(using: .utf8)!
      return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
    }
    let client = RadioStationClient(baseURL: URL(string: "http://station.test")!, session: session)

    let page = try await client.fetchDiscoverStations(cursor: "cursor-1", limit: 3)

    XCTAssertEqual(page.nextCursor, "cursor-2")
    XCTAssertEqual(page.stations.first?.stationID, "station-1")
    XCTAssertEqual(page.stations.first?.ownerDisplayName, "Publisher")
    XCTAssertEqual(page.stations.first?.shareURL.absoluteString, "https://share.test/stations/station-1")
    XCTAssertEqual(page.stations.first?.discoverStation().hostName, "Publisher")
    XCTAssertEqual(page.stations.first?.discoverStation().favorites, 8)
  }

  func testPublishDiscoverStationPostsFiveSeedTracksAndDecodesPublishedStation() async throws {
    let session = makeSession { request in
      XCTAssertEqual(request.url?.absoluteString, "http://station.test/v1/discover/stations")
      XCTAssertEqual(request.httpMethod, "POST")

      let body = try JSONSerialization.jsonObject(with: self.bodyData(from: request)) as? [String: Any]
      XCTAssertEqual(body?["title"] as? String, "Draft Radio")
      XCTAssertEqual(body?["visibility"] as? String, "public")
      XCTAssertEqual(body?["ownerID"] as? String, "owner-1")
      XCTAssertEqual((body?["seedTracks"] as? [[String: Any]])?.count, 5)
      XCTAssertEqual((body?["items"] as? [[String: Any]])?.count, 5)
      XCTAssertEqual((body?["seedTracks"] as? [[String: Any]])?.first?["appleMusicID"] as? String, "seed-1")

      let data = """
      {
        "stationID": "station-1",
        "title": "Draft Radio",
        "subtitle": "Draft intro.",
        "description": "Draft description.",
        "visibility": "public",
        "ownerID": "owner-1",
        "ownerDisplayName": "Publisher",
        "publishedAt": "2026-06-25T01:00:00.000Z",
        "shareURL": "https://share.test/stations/station-1",
        "seedTracks": [
          {
            "radioIdentity": "appleMusic:seed-1",
            "title": "Seed 1",
            "artist": "Artist",
            "album": "Album",
            "mood": "Pop",
            "duration": 200,
            "artworkURL": "https://example.com/seed-1.jpg",
            "previewURL": "https://example.com/seed-1.m4a",
            "appleMusicID": "seed-1"
          }
        ],
        "items": [
          {
            "id": "item-1",
            "title": "Seed 1",
            "artist": "Artist",
            "artworkURL": "https://example.com/seed-1.jpg",
            "previewURL": "https://example.com/seed-1.m4a",
            "sourceTitle": "Publisher",
            "reason": "Published."
          }
        ]
      }
      """.data(using: .utf8)!
      return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
    }
    let client = RadioStationClient(baseURL: URL(string: "http://station.test")!, session: session)

    let station = try await client.publishDiscoverStation(makePublicationDraft())

    XCTAssertEqual(station.stationID, "station-1")
    XCTAssertEqual(station.visibility, .public)
    XCTAssertEqual(station.shareURL.absoluteString, "https://share.test/stations/station-1")
    XCTAssertEqual(station.items.first?.track.title, "Seed 1")
  }

  func testFetchSpeechVoicesDecodesCatalog() async throws {
    let session = makeSession { request in
      XCTAssertEqual(request.url?.absoluteString, "http://station.test/v1/radio/speech/voices")
      XCTAssertEqual(request.httpMethod, "GET")
      XCTAssertEqual(request.timeoutInterval, 15.0)
      XCTAssertEqual(request.value(forHTTPHeaderField: "Accept-Language"), AppLanguage.acceptLanguageHeader())

      let data = """
      {
        "defaultSpeaker": "zh_female_shuangkuaisisi_moon_bigtts",
        "resourceId": "seed-tts-1.0",
        "model": "seed-tts-1.0",
        "voices": [
          {
            "id": "zh_female_shuangkuaisisi_moon_bigtts",
            "name": "爽快思思",
            "language": "zh-cn",
            "gender": "female",
            "style": "通用主持",
            "resourceId": "seed-tts-1.0",
            "model": "seed-tts-1.0"
          }
        ]
      }
      """.data(using: .utf8)!
      return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
    }
    let client = RadioStationClient(baseURL: URL(string: "http://station.test")!, session: session)

    let catalog = try await client.fetchSpeechVoices()

    XCTAssertEqual(catalog.defaultSpeaker, "zh_female_shuangkuaisisi_moon_bigtts")
    XCTAssertEqual(catalog.resourceId, "seed-tts-1.0")
    XCTAssertEqual(catalog.voices.first?.name, "爽快思思")
    XCTAssertEqual(catalog.voices.first?.style, "通用主持")
  }

  func testFetchSpeechVoicesFallsBackWhenEndpointIsMissing() async throws {
    let session = makeSession { request in
      let data = Data("{}".utf8)
      return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, data)
    }
    let client = RadioStationClient(baseURL: URL(string: "http://station.test")!, session: session)

    let catalog = try await client.fetchSpeechVoices()

    XCTAssertEqual(catalog.defaultSpeaker, RadioSpeechVoiceCatalog.fallback.defaultSpeaker)
    XCTAssertFalse(catalog.voices.isEmpty)
  }

  func testCompressMemoryPostsRequestAndDecodesProposal() async throws {
    let session = makeSession { request in
      XCTAssertEqual(request.url?.absoluteString, "http://station.test/v1/radio/memory/compress")
      XCTAssertEqual(request.httpMethod, "POST")
      XCTAssertEqual(request.timeoutInterval, 15.0)
      XCTAssertEqual(request.value(forHTTPHeaderField: "Accept-Language"), AppLanguage.acceptLanguageHeader())

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

  func testThrowsForEmptyStationWhenAllItemsAreUnplayable() async {
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
      XCTFail("Expected empty station error")
    } catch let error as RadioStationClientError {
      XCTAssertEqual(error, .emptyStation)
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

  private func makeTrack(
    title: String,
    playlistName: String? = nil,
    source: String? = nil,
    sourceLane: String? = nil,
    reasonSignals: [String]? = nil
  ) -> Track {
    Track(
      title: title,
      artist: "WRABEL",
      album: "Album",
      mood: "Pop",
      duration: 200,
      artworkSystemName: "music.note",
      previewURL: URL(string: "https://example.com/\(title).m4a"),
      playlistName: playlistName,
      source: source,
      sourceLane: sourceLane,
      reasonSignals: reasonSignals
    )
  }

  private func makePublicationDraft() -> DiscoverStationPublicationDraft {
    let seedTracks = (1...5).map { makePublishTrack(index: $0) }
    let items = seedTracks.enumerated().map { offset, track in
      RadioQueueItem(
        id: "item-\(offset + 1)",
        track: track,
        sourceTitle: "Publisher",
        reason: "Selected by Publisher.",
        handoffText: offset == 0 ? "Start here." : nil
      )
    }
    let station = RadioStation(
      id: "draft-1",
      title: "Draft Radio",
      subtitle: "Draft intro.",
      items: items,
      allowsAutoExtension: false
    )
    return DiscoverStationPublicationDraft(
      title: "Draft Radio",
      subtitle: "Draft intro.",
      description: "Draft description.",
      visibility: .public,
      ownerID: "owner-1",
      ownerDisplayName: "Publisher",
      seedTracks: seedTracks,
      station: station,
      coverArtworkURL: URL(string: "https://example.com/cover.jpg"),
      colorHex: "#D8633C"
    )
  }

  private func makePublishTrack(index: Int) -> Track {
    Track(
      title: "Seed \(index)",
      artist: "Artist",
      album: "Album",
      mood: "Pop",
      duration: 200,
      artworkSystemName: "music.note",
      artworkURL: URL(string: "https://example.com/seed-\(index).jpg"),
      previewURL: URL(string: "https://example.com/seed-\(index).m4a"),
      appleMusicID: "seed-\(index)",
      playlistName: "Publish Seeds",
      source: "apple_music_library",
      sourceLane: "library_song"
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
