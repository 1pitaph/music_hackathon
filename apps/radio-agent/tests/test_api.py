from fastapi.testclient import TestClient

from radio_agent.api import app


def test_root_health():
  client = TestClient(app)

  response = client.get("/")

  assert response.status_code == 200
  assert response.json() == {"status": "ok", "service": "airset-radio-agent"}


def test_healthz():
  client = TestClient(app)

  response = client.get("/healthz")

  assert response.status_code == 200
  assert response.json() == {"status": "ok"}


def test_current_station_returns_playable_ios_payload():
  client = TestClient(app)

  response = client.get("/v1/radio/stations/current")

  assert response.status_code == 200
  body = response.json()
  assert body["stationID"] == "airset-live"
  assert body["title"] == "Airset Radio"
  assert body["items"]
  assert all(item["previewURL"].startswith("https://") for item in body["items"])


def test_generate_uses_mock_without_key(monkeypatch):
  monkeypatch.delenv("OPENAI_API_KEY", raising=False)
  client = TestClient(app)

  response = client.post("/v1/radio/generate", json=_request_payload())

  assert response.status_code == 200
  body = response.json()
  assert body["mode"] == "mock"
  assert body["stationIntro"]
  assert body["speech"]["stationIntro"]["displayText"] == body["stationIntro"]
  assert [item["radioIdentity"] for item in body["items"]] == ["song-1", "song-2"]
  assert body["speech"]["betweenTracks"][0]["fromItemId"] == "song-1"
  assert body["speech"]["betweenTracks"][0]["toItemId"] == "song-2"


def test_generate_station_returns_ios_playable_payload(monkeypatch):
  monkeypatch.delenv("OPENAI_API_KEY", raising=False)
  client = TestClient(app)

  response = client.post("/v1/radio/stations/generate", json=_request_payload())

  assert response.status_code == 200
  body = response.json()
  assert body["stationID"] == "airset-personal"
  assert body["title"] == "Airset Radio"
  assert body["subtitle"]
  assert [item["id"] for item in body["items"]] == ["song-1", "song-2"]
  assert body["items"][0]["appleMusicID"] == "1"
  assert body["items"][1]["previewURL"] == "https://example.com/b.m4a"
  assert body["speech"]["stationIntro"]["displayText"] == body["subtitle"]
  assert body["speech"]["betweenTracks"][0]["toItemId"] == "song-2"
  assert body["items"][1]["handoffText"] == body["speech"]["betweenTracks"][0]["displayText"]
  assert body["memoryPatchProposals"]


def test_generate_station_can_attach_mock_speech_audio(monkeypatch):
  monkeypatch.delenv("OPENAI_API_KEY", raising=False)
  monkeypatch.setenv("SPEECH_PUBLIC_BASE_URL", "https://speech.test/audio")
  client = TestClient(app)
  payload = {
    **_request_payload(),
    "speechAudio": {
      "enabled": True,
      "provider": "mock",
      "voice": "coral",
      "model": "gpt-4o-mini-tts",
      "format": "mp3",
    },
  }

  response = client.post("/v1/radio/stations/generate", json=payload)

  assert response.status_code == 200
  body = response.json()
  intro_audio = body["speech"]["stationIntro"]["audio"]
  transition_audio = body["speech"]["betweenTracks"][0]["audio"]
  assert intro_audio["status"] == "ready"
  assert intro_audio["audioURL"].startswith("https://speech.test/audio/speech_")
  assert transition_audio["status"] == "ready"
  assert "Using mock speech synthesis metadata." in body["diagnostics"]


def test_synthesize_speech_endpoint_returns_matching_segment_audio(monkeypatch):
  monkeypatch.setenv("SPEECH_PUBLIC_BASE_URL", "https://speech.test/audio")
  client = TestClient(app)

  response = client.post(
    "/v1/radio/speech/synthesize",
    json={
      "speechAudio": {"enabled": True, "provider": "mock"},
      "segments": [
        {
          "id": "station-intro",
          "kind": "stationIntro",
          "text": "Welcome in.",
          "displayText": "Welcome in.",
          "targetItemId": "song-1",
        },
        {
          "id": "transition-1",
          "kind": "transition",
          "text": "Next up is B.",
          "displayText": "Next up is B.",
          "fromItemId": "song-1",
          "toItemId": "song-2",
        },
      ],
    },
  )

  assert response.status_code == 200
  body = response.json()
  assert [segment["id"] for segment in body["segments"]] == ["station-intro", "transition-1"]
  assert all(segment["audio"]["status"] == "ready" for segment in body["segments"])
  assert all(segment["audio"]["cacheKey"].startswith("speech_") for segment in body["segments"])


def test_compress_memory_uses_deterministic_fallback(monkeypatch):
  monkeypatch.delenv("OPENAI_API_KEY", raising=False)
  client = TestClient(app)

  response = client.post(
    "/v1/radio/memory/compress",
    json={
      "existingSummary": {"tasteSummary": "Likes intimate pop."},
      "newEvents": [
        {"type": "like", "artist": "WRABEL", "mood": "Pop"},
        {"type": "skip", "artist": "Artist B", "mood": "High Energy"},
      ],
      "pinnedNotes": ["Softer music at night."],
    },
  )

  assert response.status_code == 200
  body = response.json()
  proposal = body["compressedMemoryProposal"]
  assert "WRABEL" in proposal["likedArtistsTop"]
  assert "High Energy" in proposal["skippedMoodsTop"]
  assert "Softer music at night." in proposal["pinnedNotes"]
  assert "Using deterministic memory compression." in body["diagnostics"]


def test_compress_memory_accepts_ios_event_id_extra_field(monkeypatch):
  monkeypatch.delenv("OPENAI_API_KEY", raising=False)
  client = TestClient(app)

  response = client.post(
    "/v1/radio/memory/compress",
    json={
      "newEvents": [
        {
          "id": "event-1",
          "type": "like",
          "artist": "WRABEL",
          "mood": "Pop",
        }
      ]
    },
  )

  assert response.status_code == 200
  proposal = response.json()["compressedMemoryProposal"]
  assert proposal["likedArtistsTop"] == ["WRABEL"]


def test_empty_candidates_returns_explainable_fallback(monkeypatch):
  monkeypatch.delenv("OPENAI_API_KEY", raising=False)
  client = TestClient(app)

  response = client.post("/v1/radio/generate", json={"seedTracks": [], "catalogCandidates": [], "limit": 3})

  assert response.status_code == 200
  body = response.json()
  assert body["mode"] == "fallback"
  assert body["items"] == []
  assert "No candidate tracks supplied." in body["diagnostics"]


def _request_payload():
  return {
    "action": "start",
    "limit": 2,
    "tuning": {"discoveryRatio": 0.3, "familiarity": 0.7, "energy": 0.5},
    "memory": {
      "recentlyPlayedTrackKeys": [],
      "likedTrackKeys": [],
      "skippedTrackKeys": [],
      "dislikedTrackKeys": [],
    },
    "seedTracks": [
      {
        "radioIdentity": "song-1",
        "title": "A",
        "artist": "Artist A",
        "album": "Album",
        "mood": "Pop",
        "duration": 210,
        "appleMusicID": "1",
        "previewURL": "https://example.com/a.m4a",
        "playlistName": "Morning",
      }
    ],
    "catalogCandidates": [
      {
        "radioIdentity": "song-2",
        "title": "B",
        "artist": "Artist B",
        "album": "Album",
        "mood": "Indie",
        "duration": 200,
        "appleMusicID": "2",
        "previewURL": "https://example.com/b.m4a",
        "source": "catalog",
      }
    ],
  }
