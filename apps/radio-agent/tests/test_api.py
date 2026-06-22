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
  assert [item["radioIdentity"] for item in body["items"]] == ["song-1", "song-2"]


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
        "source": "catalog",
      }
    ],
  }
