import base64
import json

from fastapi.testclient import TestClient

from radio_agent.api import app
from radio_agent import speech
from radio_agent.schemas import RadioSpeechAudioConfig, RadioSpeechSegment


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


def test_speech_voices_returns_configured_catalog(monkeypatch):
  monkeypatch.setenv("VOLCENGINE_TTS_RESOURCE_ID", "seed-tts-2.0")
  monkeypatch.setenv("VOLCENGINE_TTS_MODEL", "seed-tts-2.0-standard")
  monkeypatch.setenv("VOLCENGINE_TTS_SPEAKER", "voice-b")
  monkeypatch.setenv("VOLCENGINE_TTS_ALLOWED_SPEAKERS", "voice-b,voice-c")
  monkeypatch.setenv("VOLCENGINE_TTS_VOICES_JSON", json.dumps([
    {
      "id": "voice-a",
      "name": "Voice A",
      "language": "zh-cn",
      "gender": "female",
      "style": "Not allowed",
      "resourceId": "seed-tts-2.0",
      "model": "seed-tts-2.0-standard",
    },
    {
      "id": "voice-b",
      "name": "Voice B",
      "language": "zh-cn",
      "gender": "male",
      "style": "Host",
      "resourceId": "seed-tts-2.0",
      "model": "seed-tts-2.0-standard",
    },
  ]))
  client = TestClient(app)

  response = client.get("/v1/radio/speech/voices")

  assert response.status_code == 200
  body = response.json()
  assert body["defaultSpeaker"] == "voice-b"
  assert body["resourceId"] == "seed-tts-2.0"
  assert [voice["id"] for voice in body["voices"]] == ["voice-b", "voice-c"]
  assert body["voices"][0]["name"] == "Voice B"
  assert body["voices"][1]["style"] == "自定义音色"


def test_speech_voices_ignores_legacy_openai_model(monkeypatch):
  monkeypatch.delenv("VOLCENGINE_TTS_MODEL", raising=False)
  monkeypatch.setenv("SPEECH_MODEL", "gpt-4o-mini-tts")
  monkeypatch.setenv("VOLCENGINE_TTS_CLUSTER", "seed-tts-2.0")
  monkeypatch.setenv("VOLCENGINE_TTS_VOICE_TYPE", "voice-legacy")
  client = TestClient(app)

  response = client.get("/v1/radio/speech/voices")

  assert response.status_code == 200
  body = response.json()
  assert body["defaultSpeaker"] == "voice-legacy"
  assert body["resourceId"] == "seed-tts-2.0"
  assert body["model"] == "seed-tts-2.0-standard"
  assert body["voices"][0]["id"] == "voice-legacy"


def test_volcengine_speech_synthesis_writes_audio_and_reuses_cache(monkeypatch, tmp_path):
  _configure_volcengine_env(monkeypatch, tmp_path)
  audio_bytes = b"ID3fake-mp3"
  calls = []

  def fake_stream(method, url, *, headers, json, timeout):
    calls.append({"method": method, "url": url, "headers": headers, "json": json, "timeout": timeout})
    return _FakeVolcengineStream(
      200,
      [
        {"code": 0, "data": base64.b64encode(audio_bytes[:4]).decode("ascii")},
        {"code": 0, "data": base64.b64encode(audio_bytes[4:]).decode("ascii")},
        {"code": 20000000, "message": "finished"},
      ],
    )

  monkeypatch.setattr(speech.httpx, "stream", fake_stream)
  config = RadioSpeechAudioConfig(
    enabled=True,
    provider="openai",
    voice="coral",
    model="gpt-4o-mini-tts",
    format="mp3",
  )
  segment = RadioSpeechSegment(
    id="station-intro",
    kind="stationIntro",
    text="Welcome in.",
    displayText="Welcome in.",
    targetItemId="song-1",
  )

  results, diagnostics = speech.synthesize_speech_segments([segment], config)

  assert diagnostics == []
  assert len(calls) == 1
  assert calls[0]["method"] == "POST"
  assert calls[0]["url"] == "https://openspeech.bytedance.com/api/v3/tts/unidirectional"
  assert calls[0]["headers"]["X-Api-Key"] == "test-api-key"
  assert calls[0]["headers"]["X-Api-Resource-Id"] == "seed-tts-2.0"
  assert calls[0]["headers"]["X-Api-Request-Id"].startswith("speech_")
  req_params = calls[0]["json"]["req_params"]
  assert req_params["text"] == "Welcome in."
  assert req_params["speaker"] == "zh_female_test"
  assert req_params["model"] == "seed-tts-2.0-standard"
  assert req_params["audio_params"] == {
    "format": "mp3",
    "sample_rate": 24000,
    "bit_rate": 128000,
    "speech_rate": 0,
    "loudness_rate": 0,
    "enable_subtitle": False,
  }

  audio = results[0].audio
  assert audio.status == "ready"
  assert audio.voice == "zh_female_test"
  assert audio.model == "seed-tts-2.0-standard"
  assert audio.mimeType == "audio/mpeg"
  assert audio.audioURL == f"https://speech.test/audio/{audio.cacheKey}.mp3"
  assert (tmp_path / f"{audio.cacheKey}.mp3").read_bytes() == audio_bytes

  def fail_if_called(*args, **kwargs):
    raise AssertionError("cache hit should not call Volcengine")

  monkeypatch.setattr(speech.httpx, "stream", fail_if_called)
  cached_results, cached_diagnostics = speech.synthesize_speech_segments([segment], config)

  assert cached_diagnostics == []
  assert cached_results[0].audio.status == "ready"
  assert cached_results[0].audio.audioURL == audio.audioURL


def test_volcengine_speech_synthesis_rejects_unallowed_speaker(monkeypatch, tmp_path):
  _configure_volcengine_env(monkeypatch, tmp_path)
  monkeypatch.setenv("VOLCENGINE_TTS_ALLOWED_SPEAKERS", "zh_female_test")
  audio_bytes = b"ID3safe-speaker"
  calls = []

  def fake_stream(method, url, *, headers, json, timeout):
    calls.append(json)
    return _FakeVolcengineStream(
      200,
      [
        {"code": 0, "data": base64.b64encode(audio_bytes).decode("ascii")},
        {"code": 20000000, "message": "finished"},
      ],
    )

  monkeypatch.setattr(speech.httpx, "stream", fake_stream)

  results, diagnostics = speech.synthesize_speech_segments(
    [
      RadioSpeechSegment(
        id="station-intro",
        kind="stationIntro",
        text="Welcome in.",
        displayText="Welcome in.",
      )
    ],
    RadioSpeechAudioConfig(
      enabled=True,
      provider="volcengine",
      speaker="not_allowed_speaker",
    ),
  )

  assert results[0].audio.status == "ready"
  assert calls[0]["req_params"]["speaker"] == "zh_female_test"
  assert "Requested speech speaker 'not_allowed_speaker' is not allowed" in " ".join(diagnostics)


def test_volcengine_speech_synthesis_failure_does_not_leak_secret(monkeypatch, tmp_path):
  _configure_volcengine_env(monkeypatch, tmp_path)

  def fake_stream(method, url, *, headers, json, timeout):
    return _FakeVolcengineStream(
      200,
      [{"code": 5000, "message": "bad key test-api-key"}],
    )

  monkeypatch.setattr(speech.httpx, "stream", fake_stream)
  results, diagnostics = speech.synthesize_speech_segments(
    [
      RadioSpeechSegment(
        id="transition-1",
        kind="transition",
        text="Next up.",
        displayText="Next up.",
        fromItemId="song-1",
        toItemId="song-2",
      )
    ],
    RadioSpeechAudioConfig(enabled=True, provider="volcengine", voice="zh_female_test"),
  )

  assert results[0].audio.status == "unavailable"
  assert "test-api-key" not in " ".join(diagnostics)
  assert "[redacted]" in " ".join(diagnostics)


def test_volcengine_speech_synthesis_reports_missing_configuration(monkeypatch, tmp_path):
  monkeypatch.setenv("SPEECH_ENABLED", "true")
  monkeypatch.setenv("SPEECH_PROVIDER", "volcengine")
  monkeypatch.setenv("SPEECH_CACHE_DIR", str(tmp_path))
  monkeypatch.setenv("SPEECH_PUBLIC_BASE_URL", "https://speech.test/audio")
  monkeypatch.delenv("VOLCENGINE_TTS_API_KEY", raising=False)
  monkeypatch.delenv("VOLCENGINE_TTS_SPEAKER", raising=False)
  monkeypatch.delenv("VOLCENGINE_TTS_VOICE_TYPE", raising=False)

  def fail_if_called(*args, **kwargs):
    raise AssertionError("missing configuration should not call Volcengine")

  monkeypatch.setattr(speech.httpx, "stream", fail_if_called)
  results, diagnostics = speech.synthesize_speech_segments(
    [
      RadioSpeechSegment(
        id="station-intro",
        kind="stationIntro",
        text="Welcome in.",
        displayText="Welcome in.",
      )
    ],
    RadioSpeechAudioConfig(enabled=True, provider="volcengine"),
  )

  assert results[0].audio.status == "unavailable"
  assert "Volcengine TTS is missing required configuration" in " ".join(diagnostics)
  assert "VOLCENGINE_TTS_API_KEY" in " ".join(diagnostics)


def test_generate_station_can_attach_volcengine_speech_audio(monkeypatch, tmp_path):
  monkeypatch.delenv("OPENAI_API_KEY", raising=False)
  _configure_volcengine_env(monkeypatch, tmp_path)
  audio_bytes = b"ID3station-mp3"

  def fake_stream(method, url, *, headers, json, timeout):
    return _FakeVolcengineStream(
      200,
      [
        {"code": 0, "data": base64.b64encode(audio_bytes).decode("ascii")},
        {"code": 20000000, "message": "finished"},
      ],
    )

  monkeypatch.setattr(speech.httpx, "stream", fake_stream)
  client = TestClient(app)
  payload = {
    **_request_payload(),
    "speechAudio": {
      "enabled": True,
      "provider": "openai",
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
  assert transition_audio["status"] == "ready"
  assert intro_audio["voice"] == "zh_female_test"
  assert intro_audio["audioURL"].startswith("https://speech.test/audio/speech_")

  audio_response = client.get(f"/v1/radio/speech/audio/{intro_audio['cacheKey']}.mp3")

  assert audio_response.status_code == 200
  assert audio_response.content == audio_bytes
  assert audio_response.headers["content-type"].startswith("audio/mpeg")


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


class _FakeVolcengineStream:
  def __init__(self, status_code, bodies):
    self.status_code = status_code
    self._bodies = bodies

  def __enter__(self):
    return self

  def __exit__(self, exc_type, exc_value, traceback):
    return False

  def iter_lines(self):
    for body in self._bodies:
      yield json.dumps(body)


def _configure_volcengine_env(monkeypatch, tmp_path):
  monkeypatch.setenv("SPEECH_ENABLED", "true")
  monkeypatch.setenv("SPEECH_PROVIDER", "volcengine")
  monkeypatch.setenv("SPEECH_MODEL", "seed-tts-2.0-standard")
  monkeypatch.setenv("SPEECH_DEFAULT_VOICE", "")
  monkeypatch.setenv("SPEECH_FORMAT", "mp3")
  monkeypatch.setenv("SPEECH_CACHE_DIR", str(tmp_path))
  monkeypatch.setenv("SPEECH_PUBLIC_BASE_URL", "https://speech.test/audio")
  monkeypatch.setenv("VOLCENGINE_TTS_ENDPOINT", "https://openspeech.bytedance.com/api/v3/tts/unidirectional")
  monkeypatch.setenv("VOLCENGINE_TTS_API_KEY", "test-api-key")
  monkeypatch.setenv("VOLCENGINE_TTS_RESOURCE_ID", "seed-tts-2.0")
  monkeypatch.setenv("VOLCENGINE_TTS_SPEAKER", "zh_female_test")
  monkeypatch.setenv("VOLCENGINE_TTS_MODEL", "seed-tts-2.0-standard")
  monkeypatch.setenv("VOLCENGINE_TTS_SAMPLE_RATE", "24000")
  monkeypatch.setenv("VOLCENGINE_TTS_BIT_RATE", "128000")
  monkeypatch.setenv("VOLCENGINE_TTS_SPEECH_RATE", "0")
  monkeypatch.setenv("VOLCENGINE_TTS_LOUDNESS_RATE", "0")
