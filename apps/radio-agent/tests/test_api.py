import base64
import json

import pytest
from fastapi.testclient import TestClient

import radio_agent.api as api
from radio_agent.api import app, _is_playable, _station_item
from radio_agent import speech
from radio_agent.schemas import RadioSpeechAudioConfig, RadioSpeechSegment, RadioTrack


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


def test_generate_station_honors_english_speech_language(monkeypatch):
  monkeypatch.delenv("OPENAI_API_KEY", raising=False)
  client = TestClient(app)
  payload = {**_request_payload(), "speechLanguage": "en-US"}

  response = client.post("/v1/radio/stations/generate", json=payload)

  assert response.status_code == 200
  body = response.json()
  assert body["subtitle"].startswith("Opening with A")
  assert body["speech"]["stationIntro"]["text"].startswith("Welcome to Airset")
  assert body["speech"]["stationIntro"]["text"] != body["subtitle"]
  assert len(body["speech"]["stationIntro"]["text"].split()) > len(body["subtitle"].split())
  assert body["speech"]["betweenTracks"][0]["displayText"].startswith("Another side of the album")
  assert body["speech"]["betweenTracks"][0]["text"] != body["speech"]["betweenTracks"][0]["displayText"]
  assert body["items"][1]["handoffText"] == body["speech"]["betweenTracks"][0]["displayText"]
  assert "《" not in body["subtitle"]


def test_playable_filter_rejects_blank_ids_and_invalid_preview_urls():
  assert not _is_playable(_track(appleMusicID="   "))
  assert not _is_playable(_track(previewURL="ftp://example.com/a.m4a"))
  assert not _is_playable(_track(previewURL="/relative/a.m4a"))
  assert _is_playable(_track(appleMusicID=" 123456 "))
  assert _is_playable(_track(previewURL="https://example.com/a.m4a"))


def test_station_item_sanitizes_playable_fields_and_preserves_source_metadata():
  item = _station_item(
    _track(
      appleMusicID=" 123456 ",
      previewURL="ftp://example.com/a.m4a",
      source="virtual_music_library_json",
      sourceLane="familiar_anchor",
    ),
    "Reason.",
  )

  assert item.appleMusicID == "123456"
  assert item.previewURL is None
  assert item.source == "virtual_music_library_json"
  assert item.sourceLane == "familiar_anchor"
  assert item.sourceTitle == "familiar_anchor"


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


def test_publish_discover_station_persists_feed_and_station_lookup(monkeypatch, tmp_path):
  monkeypatch.setenv("DISCOVER_STATIONS_DB_PATH", str(tmp_path / "discover.sqlite3"))
  monkeypatch.setenv("DISCOVER_STATIONS_PUBLIC_BASE_URL", "https://share.test")
  timestamps = iter([
    "2026-06-25T01:00:00.000Z",
    "2026-06-25T01:01:00.000Z",
    "2026-06-25T01:02:00.000Z",
    "2026-06-25T01:03:00.000Z",
  ])
  monkeypatch.setattr(api, "_timestamp_now", lambda: next(timestamps))
  client = TestClient(app)

  first_public = client.post("/v1/discover/stations", json=_publish_payload(title="First")).json()
  unlisted = client.post(
    "/v1/discover/stations",
    json=_publish_payload(title="Unlisted", visibility="unlisted"),
  ).json()
  second_public = client.post("/v1/discover/stations", json=_publish_payload(title="Second")).json()
  private = client.post(
    "/v1/discover/stations",
    json=_publish_payload(title="Private", visibility="private"),
  ).json()

  assert first_public["shareURL"] == f"https://share.test/stations/{first_public['stationID']}"
  assert first_public["visibility"] == "public"
  assert first_public["seedTracks"][0]["radioIdentity"] == "seed-1"

  first_page = client.get("/v1/discover/stations?limit=1")
  assert first_page.status_code == 200
  first_page_body = first_page.json()
  assert [station["title"] for station in first_page_body["stations"]] == ["Second"]
  assert first_page_body["nextCursor"]

  second_page = client.get(f"/v1/discover/stations?limit=5&cursor={first_page_body['nextCursor']}")
  assert second_page.status_code == 200
  assert [station["title"] for station in second_page.json()["stations"]] == ["First"]
  assert second_page.json()["nextCursor"] is None

  assert client.get(f"/v1/radio/stations/{first_public['stationID']}").json()["title"] == "First"
  assert client.get(f"/v1/radio/stations/{unlisted['stationID']}").json()["title"] == "Unlisted"
  assert client.get(f"/v1/radio/stations/{private['stationID']}").status_code == 404

  persisted_client = TestClient(app)
  persisted_response = persisted_client.get(f"/v1/radio/stations/{second_public['stationID']}")
  assert persisted_response.status_code == 200
  assert persisted_response.json()["title"] == "Second"


def test_publish_discover_station_requires_five_unique_seed_tracks(monkeypatch, tmp_path):
  monkeypatch.setenv("DISCOVER_STATIONS_DB_PATH", str(tmp_path / "discover.sqlite3"))
  client = TestClient(app)
  payload = _publish_payload()
  payload["seedTracks"][4]["radioIdentity"] = "seed-1"

  response = client.post("/v1/discover/stations", json=payload)

  assert response.status_code == 422
  assert "5 unique" in response.json()["detail"]


def test_discover_station_feed_rejects_invalid_cursor(monkeypatch, tmp_path):
  monkeypatch.setenv("DISCOVER_STATIONS_DB_PATH", str(tmp_path / "discover.sqlite3"))
  client = TestClient(app)

  response = client.get("/v1/discover/stations?cursor=not-a-cursor")

  assert response.status_code == 400


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
  monkeypatch.setenv("VOLCENGINE_TTS_RESOURCE_ID", "seed-tts-1.0")
  monkeypatch.setenv("VOLCENGINE_TTS_MODEL", "seed-tts-1.0")
  monkeypatch.setenv("VOLCENGINE_TTS_SPEAKER", "voice-b")
  monkeypatch.setenv("VOLCENGINE_TTS_ALLOWED_SPEAKERS", "voice-b,voice-c")
  monkeypatch.setenv("VOLCENGINE_TTS_VOICES_JSON", json.dumps([
    {
      "id": "voice-a",
      "name": "Voice A",
      "language": "zh-cn",
      "gender": "female",
      "style": "Not allowed",
      "resourceId": "seed-tts-1.0",
      "model": "seed-tts-1.0",
    },
    {
      "id": "voice-b",
      "name": "Voice B",
      "language": "zh-cn",
      "gender": "male",
      "style": "Host",
      "resourceId": "seed-tts-1.0",
      "model": "seed-tts-1.0",
    },
  ]))
  client = TestClient(app)

  response = client.get("/v1/radio/speech/voices")

  assert response.status_code == 200
  body = response.json()
  assert body["defaultSpeaker"] == "voice-b"
  assert body["resourceId"] == "seed-tts-1.0"
  assert [voice["id"] for voice in body["voices"]] == ["voice-b", "voice-c"]
  assert body["voices"][0]["name"] == "Voice B"
  assert body["voices"][1]["style"] == "自定义音色"


def test_speech_voices_include_builtin_english_lauren(monkeypatch):
  monkeypatch.delenv("VOLCENGINE_TTS_SPEAKER", raising=False)
  monkeypatch.delenv("VOLCENGINE_TTS_VOICE_TYPE", raising=False)
  monkeypatch.delenv("VOLCENGINE_TTS_ALLOWED_SPEAKERS", raising=False)
  monkeypatch.delenv("VOLCENGINE_TTS_VOICES_JSON", raising=False)
  client = TestClient(app)

  response = client.get("/v1/radio/speech/voices")

  assert response.status_code == 200
  body = response.json()
  voices = {voice["id"]: voice for voice in body["voices"]}
  assert "en_female_lauren_moon_bigtts" in voices
  assert voices["en_female_lauren_moon_bigtts"]["name"] == "Lauren"
  assert voices["en_female_lauren_moon_bigtts"]["language"] == "en-us"


def test_speech_voices_ignores_legacy_openai_model(monkeypatch):
  monkeypatch.delenv("VOLCENGINE_TTS_MODEL", raising=False)
  monkeypatch.setenv("SPEECH_MODEL", "gpt-4o-mini-tts")
  monkeypatch.setenv("VOLCENGINE_TTS_CLUSTER", "seed-tts-1.0")
  monkeypatch.setenv("VOLCENGINE_TTS_VOICE_TYPE", "voice-legacy")
  client = TestClient(app)

  response = client.get("/v1/radio/speech/voices")

  assert response.status_code == 200
  body = response.json()
  assert body["defaultSpeaker"] == "voice-legacy"
  assert body["resourceId"] == "seed-tts-1.0"
  assert body["model"] == "seed-tts-1.0"
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
  assert calls[0]["headers"]["X-Api-Resource-Id"] == "seed-tts-1.0"
  assert calls[0]["headers"]["X-Api-Request-Id"].startswith("speech_")
  req_params = calls[0]["json"]["req_params"]
  assert req_params["text"] == "Welcome in."
  assert req_params["speaker"] == "zh_female_test"
  assert "model" not in req_params
  assert req_params["audio_params"] == {
    "format": "mp3",
    "sample_rate": 24000,
    "bit_rate": 128000,
    "speech_rate": 0,
    "loudness_rate": 0,
    "enable_subtitle": True,
  }

  audio = results[0].audio
  assert audio.status == "ready"
  assert audio.voice == "zh_female_test"
  assert audio.model == "seed-tts-1.0"
  assert audio.mimeType == "audio/mpeg"
  assert audio.durationSeconds == 1.2
  assert audio.cues == []
  assert audio.audioURL == f"https://speech.test/audio/{audio.cacheKey}.mp3"
  assert (tmp_path / f"{audio.cacheKey}.mp3").read_bytes() == audio_bytes

  def fail_if_called(*args, **kwargs):
    raise AssertionError("cache hit should not call Volcengine")

  monkeypatch.setattr(speech.httpx, "stream", fail_if_called)
  cached_results, cached_diagnostics = speech.synthesize_speech_segments([segment], config)

  assert cached_diagnostics == []
  assert cached_results[0].audio.status == "ready"
  assert cached_results[0].audio.audioURL == audio.audioURL
  assert cached_results[0].audio.cues == []


def test_volcengine_speech_synthesis_returns_cues_and_reuses_metadata(monkeypatch, tmp_path):
  _configure_volcengine_env(monkeypatch, tmp_path)
  audio_bytes = b"ID3timed-mp3"
  calls = []

  def fake_stream(method, url, *, headers, json, timeout):
    calls.append({"method": method, "url": url, "headers": headers, "json": json, "timeout": timeout})
    return _FakeVolcengineStream(
      200,
      [
        {"code": 0, "data": base64.b64encode(audio_bytes).decode("ascii")},
        {
          "code": 0,
          "payload": {
            "words": [
              {"word": "Hello", "startTime": 0.1, "endTime": 0.35, "confidence": 0.91},
              {"word": "there", "startTime": 0.36, "endTime": 0.7},
              {"word": "Next", "startTime": 0.9, "endTime": 1.1},
              {"word": "up", "startTime": 1.12, "endTime": 1.4},
            ]
          },
        },
        {"code": 20000000, "message": "finished"},
      ],
    )

  monkeypatch.setattr(speech.httpx, "stream", fake_stream)
  segment = RadioSpeechSegment(
    id="station-intro",
    kind="stationIntro",
    text="Hello there. Next up.",
    displayText="Hello there.",
    targetItemId="song-1",
  )

  results, diagnostics = speech.synthesize_speech_segments(
    [segment],
    RadioSpeechAudioConfig(enabled=True, provider="volcengine"),
  )

  assert diagnostics == []
  assert len(calls) == 1
  audio = results[0].audio
  assert audio.status == "ready"
  assert audio.durationSeconds == 1.4
  assert len(audio.cues) == 2
  assert audio.cues[0].displayText == "Hello there."
  assert audio.cues[0].startTime == 0.1
  assert audio.cues[0].endTime == 0.7
  assert audio.cues[0].words[0].word == "Hello"
  assert audio.cues[0].words[0].confidence == 0.91
  assert audio.cues[1].displayText == "Next up."
  assert audio.cues[1].startTime == 0.9
  assert audio.cues[1].endTime == 1.4
  assert (tmp_path / f"{audio.cacheKey}.metadata.json").is_file()

  def fail_if_called(*args, **kwargs):
    raise AssertionError("cache hit should not call Volcengine")

  monkeypatch.setattr(speech.httpx, "stream", fail_if_called)
  cached_results, cached_diagnostics = speech.synthesize_speech_segments(
    [segment],
    RadioSpeechAudioConfig(enabled=True, provider="volcengine"),
  )

  assert cached_diagnostics == []
  assert cached_results[0].audio.status == "ready"
  assert cached_results[0].audio.audioURL == audio.audioURL
  assert cached_results[0].audio.durationSeconds == 1.4
  assert [cue.displayText for cue in cached_results[0].audio.cues] == ["Hello there.", "Next up."]


def test_volcengine_speech_synthesis_dedupes_cache_keys_and_preserves_order(monkeypatch, tmp_path):
  _configure_volcengine_env(monkeypatch, tmp_path)
  calls = []

  def fake_stream(method, url, *, headers, json, timeout):
    text = json["req_params"]["text"]
    calls.append(text)
    return _FakeVolcengineStream(
      200,
      [
        {"code": 0, "data": base64.b64encode(f"ID3{text}".encode("utf-8")).decode("ascii")},
        {"code": 20000000, "message": "finished"},
      ],
    )

  monkeypatch.setattr(speech.httpx, "stream", fake_stream)
  segments = [
    RadioSpeechSegment(
      id="station-intro",
      kind="stationIntro",
      text="Same text.",
      displayText="Same text.",
      targetItemId="song-1",
    ),
    RadioSpeechSegment(
      id="transition-1",
      kind="transition",
      text="Different text.",
      displayText="Different text.",
      fromItemId="song-1",
      toItemId="song-2",
    ),
    RadioSpeechSegment(
      id="transition-duplicate",
      kind="transition",
      text="Same text.",
      displayText="Same text again.",
      fromItemId="song-2",
      toItemId="song-3",
    ),
  ]

  results, diagnostics = speech.synthesize_speech_segments(
    segments,
    RadioSpeechAudioConfig(enabled=True, provider="volcengine"),
  )

  assert diagnostics == []
  assert [result.id for result in results] == ["station-intro", "transition-1", "transition-duplicate"]
  assert len(calls) == 2
  assert set(calls) == {"Same text.", "Different text."}
  assert results[0].audio.status == "ready"
  assert results[1].audio.status == "ready"
  assert results[2].audio.status == "ready"
  assert results[0].audio.cacheKey == results[2].audio.cacheKey
  assert results[0].audio.audioURL == results[2].audio.audioURL


def test_synthesize_speech_endpoint_keeps_ready_audio_when_one_volcengine_segment_fails(monkeypatch, tmp_path):
  _configure_volcengine_env(monkeypatch, tmp_path)

  def fake_stream(method, url, *, headers, json, timeout):
    text = json["req_params"]["text"]
    if "Fail" in text:
      return _FakeVolcengineStream(500, [])
    return _FakeVolcengineStream(
      200,
      [
        {"code": 0, "data": base64.b64encode(f"ID3{text}".encode("utf-8")).decode("ascii")},
        {"code": 20000000, "message": "finished"},
      ],
    )

  monkeypatch.setattr(speech.httpx, "stream", fake_stream)
  client = TestClient(app)

  response = client.post(
    "/v1/radio/speech/synthesize",
    json={
      "speechAudio": {"enabled": True, "provider": "volcengine"},
      "segments": [
        {
          "id": "station-intro",
          "kind": "stationIntro",
          "text": "Ready intro.",
          "displayText": "Ready intro.",
          "targetItemId": "song-1",
        },
        {
          "id": "transition-fail",
          "kind": "transition",
          "text": "Fail this bridge.",
          "displayText": "Fail this bridge.",
          "fromItemId": "song-1",
          "toItemId": "song-2",
        },
        {
          "id": "transition-ready",
          "kind": "transition",
          "text": "Ready bridge.",
          "displayText": "Ready bridge.",
          "fromItemId": "song-2",
          "toItemId": "song-3",
        },
      ],
    },
  )

  assert response.status_code == 200
  body = response.json()
  assert [segment["id"] for segment in body["segments"]] == [
    "station-intro",
    "transition-fail",
    "transition-ready",
  ]
  assert [segment["audio"]["status"] for segment in body["segments"]] == [
    "ready",
    "unavailable",
    "ready",
  ]
  assert "HTTP 500" in " ".join(body["diagnostics"])


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
  client = TestClient(app)
  payload = {
    **_request_payload(),
    "speechLanguage": "en-US",
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
  assert calls
  assert all(call["req_params"]["explicit_language"] == "en-US" for call in calls)
  sent_texts = {call["req_params"]["text"] for call in calls}
  assert body["speech"]["stationIntro"]["text"] in sent_texts
  assert body["speech"]["betweenTracks"][0]["text"] in sent_texts
  assert body["subtitle"] not in sent_texts

  audio_response = client.get(f"/v1/radio/speech/audio/{intro_audio['cacheKey']}.mp3")

  assert audio_response.status_code == 200
  assert audio_response.content == audio_bytes
  assert audio_response.headers["content-type"].startswith("audio/mpeg")


def test_generate_station_stream_delivery_returns_urls_without_synthesizing(monkeypatch, tmp_path):
  monkeypatch.delenv("OPENAI_API_KEY", raising=False)
  _configure_volcengine_env(monkeypatch, tmp_path)

  def fail_if_called(*args, **kwargs):
    raise AssertionError("stream delivery should not synthesize during station generation")

  monkeypatch.setattr(speech.httpx, "stream", fail_if_called)
  client = TestClient(app)
  payload = {
    **_request_payload(),
    "speechAudio": {
      "enabled": True,
      "delivery": "stream",
      "provider": "volcengine",
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
  assert intro_audio["streamURL"].startswith("https://speech.test/stream/speech_")
  assert intro_audio["metadataURL"].startswith("https://speech.test/metadata/speech_")
  assert transition_audio["status"] == "ready"
  assert not (tmp_path / f"{intro_audio['cacheKey']}.mp3").exists()
  assert (tmp_path / f"{intro_audio['cacheKey']}.metadata.json").exists()


def test_speech_stream_endpoint_generates_cache_and_audio_endpoint_reuses(monkeypatch, tmp_path):
  _configure_volcengine_env(monkeypatch, tmp_path)
  audio_bytes = _fake_mp3_bytes(frame_count=100)
  calls = []
  segment = RadioSpeechSegment(
    id="station-intro",
    kind="stationIntro",
    text="Stream this intro.",
    displayText="Stream this intro.",
    targetItemId="song-1",
  )
  results, diagnostics = speech.synthesize_speech_segments(
    [segment],
    RadioSpeechAudioConfig(enabled=True, delivery="stream", provider="volcengine"),
  )
  audio = results[0].audio

  assert diagnostics == []
  assert audio.status == "ready"
  assert audio.streamURL == f"https://speech.test/stream/{audio.cacheKey}.mp3"
  assert audio.audioURL == f"https://speech.test/audio/{audio.cacheKey}.mp3"
  assert audio.metadataURL == f"https://speech.test/metadata/{audio.cacheKey}.mp3"
  assert audio.durationSource == "estimated"
  assert audio.estimatedDurationSeconds == audio.durationSeconds
  assert audio.actualDurationSeconds is None
  assert audio.advanceTimeSeconds is None
  assert not (tmp_path / f"{audio.cacheKey}.mp3").exists()

  def fake_stream(method, url, *, headers, json, timeout):
    calls.append(json)
    return _FakeVolcengineStream(
      200,
      [
        {"code": 0, "data": base64.b64encode(audio_bytes[:5]).decode("ascii")},
        {"code": 0, "data": base64.b64encode(audio_bytes[5:]).decode("ascii")},
        {"code": 20000000, "message": "finished"},
      ],
    )

  monkeypatch.setattr(speech.httpx, "stream", fake_stream)
  client = TestClient(app)
  stream_response = client.get(f"/v1/radio/speech/stream/{audio.cacheKey}.mp3")

  assert stream_response.status_code == 200
  assert stream_response.content == audio_bytes
  assert stream_response.headers["content-type"].startswith("audio/mpeg")
  assert len(calls) == 1
  assert (tmp_path / f"{audio.cacheKey}.mp3").read_bytes() == audio_bytes

  metadata_response = client.get(f"/v1/radio/speech/metadata/{audio.cacheKey}.mp3")
  metadata = metadata_response.json()
  assert metadata_response.status_code == 200
  assert metadata["durationSource"] == "audio"
  assert metadata["metadataURL"] == f"https://speech.test/metadata/{audio.cacheKey}.mp3"
  assert metadata["estimatedDurationSeconds"] == audio.estimatedDurationSeconds
  assert metadata["actualDurationSeconds"] == 2.4
  assert metadata["durationSeconds"] == 2.4
  assert metadata["advanceTimeSeconds"] == 1.6

  def fail_if_called(*args, **kwargs):
    raise AssertionError("cache hit should not call Volcengine")

  monkeypatch.setattr(speech.httpx, "stream", fail_if_called)
  cached_stream_response = client.get(f"/v1/radio/speech/stream/{audio.cacheKey}.mp3")
  audio_response = client.get(f"/v1/radio/speech/audio/{audio.cacheKey}.mp3")

  assert cached_stream_response.status_code == 200
  assert cached_stream_response.content == audio_bytes
  assert audio_response.status_code == 200
  assert audio_response.content == audio_bytes


def test_speech_stream_metadata_keeps_timing_cues_and_advance_marker(monkeypatch, tmp_path):
  _configure_volcengine_env(monkeypatch, tmp_path)
  audio_bytes = _fake_mp3_bytes(frame_count=100)
  segment = RadioSpeechSegment(
    id="transition-1",
    kind="transition",
    text="Hello there. Next up.",
    displayText="Next up.",
    fromItemId="song-1",
    toItemId="song-2",
  )
  results, diagnostics = speech.synthesize_speech_segments(
    [segment],
    RadioSpeechAudioConfig(enabled=True, delivery="stream", provider="volcengine"),
  )
  audio = results[0].audio

  assert diagnostics == []
  assert audio.durationSource == "estimated"

  def fake_stream(method, url, *, headers, json, timeout):
    return _FakeVolcengineStream(
      200,
      [
        {"code": 0, "data": base64.b64encode(audio_bytes).decode("ascii")},
        {
          "code": 0,
          "payload": {
            "words": [
              {"word": "Hello", "startTime": 0.1, "endTime": 0.35},
              {"word": "there", "startTime": 0.36, "endTime": 0.7},
              {"word": "Next", "startTime": 0.9, "endTime": 1.1},
              {"word": "up", "startTime": 1.12, "endTime": 1.4},
            ]
          },
        },
        {"code": 20000000, "message": "finished"},
      ],
    )

  monkeypatch.setattr(speech.httpx, "stream", fake_stream)
  client = TestClient(app)
  stream_response = client.get(f"/v1/radio/speech/stream/{audio.cacheKey}.mp3")
  metadata_response = client.get(f"/v1/radio/speech/metadata/{audio.cacheKey}.mp3")
  metadata = metadata_response.json()

  assert stream_response.status_code == 200
  assert metadata_response.status_code == 200
  assert metadata["durationSource"] == "audio"
  assert metadata["actualDurationSeconds"] == 2.4
  assert [cue["displayText"] for cue in metadata["cues"]] == ["Hello there.", "Next up."]
  assert metadata["advanceCueId"] == "transition-1-cue-2"
  assert metadata["advanceTimeSeconds"] == 0.9


def test_speech_stream_failure_does_not_leave_final_cache_or_leak_secret(monkeypatch, tmp_path):
  _configure_volcengine_env(monkeypatch, tmp_path)
  segment = RadioSpeechSegment(
    id="transition-1",
    kind="transition",
    text="Fail this stream.",
    displayText="Fail this stream.",
    fromItemId="song-1",
    toItemId="song-2",
  )
  results, _ = speech.synthesize_speech_segments(
    [segment],
    RadioSpeechAudioConfig(enabled=True, delivery="stream", provider="volcengine"),
  )
  audio = results[0].audio

  def fake_stream(method, url, *, headers, json, timeout):
    return _FakeVolcengineStream(
      200,
      [{"code": 5000, "message": "bad key test-api-key"}],
    )

  monkeypatch.setattr(speech.httpx, "stream", fake_stream)

  with pytest.raises(ValueError) as exc_info:
    list(speech.stream_speech_audio_file(f"{audio.cacheKey}.mp3"))

  assert "test-api-key" not in str(exc_info.value)
  assert "[redacted]" in str(exc_info.value)
  assert not (tmp_path / f"{audio.cacheKey}.mp3").exists()


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


def _track(**overrides):
  payload = {
    "radioIdentity": "song-1",
    "title": "A",
    "artist": "Artist A",
    "album": "Album",
    "mood": "Pop",
    "duration": 210,
  }
  payload.update(overrides)
  return RadioTrack(**payload)


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


def _publish_payload(title="Published", visibility="public"):
  seed_tracks = []
  items = []
  for index in range(1, 6):
    seed_tracks.append({
      "radioIdentity": f"seed-{index}",
      "title": f"Seed {index}",
      "artist": f"Artist {index}",
      "album": "Shared Album",
      "mood": "Pop",
      "duration": 180 + index,
      "appleMusicID": f"apple-{index}",
      "previewURL": f"https://example.com/seed-{index}.m4a",
      "artworkURL": f"https://example.com/seed-{index}.jpg",
      "playlistName": "Publish Seeds",
    })
    items.append({
      "id": f"seed-{index}",
      "title": f"Seed {index}",
      "artist": f"Artist {index}",
      "album": "Shared Album",
      "mood": "Pop",
      "duration": 180 + index,
      "artworkURL": f"https://example.com/seed-{index}.jpg",
      "previewURL": f"https://example.com/seed-{index}.m4a",
      "appleMusicID": f"apple-{index}",
      "sourceTitle": "Publish Seeds",
      "reason": "Selected by the publisher.",
      "handoffText": "Next from the published station.",
    })

  return {
    "title": title,
    "subtitle": f"{title} station intro.",
    "description": f"{title} station description.",
    "visibility": visibility,
    "ownerID": "owner-1",
    "ownerDisplayName": "Publisher",
    "seedTracks": seed_tracks,
    "items": items,
    "coverArtworkURL": "https://example.com/cover.jpg",
    "colorHex": "#D8633C",
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


def _fake_mp3_bytes(frame_count: int = 1) -> bytes:
  # MPEG 2, Layer III, 128 kbps, 24 kHz. Each frame is 384 bytes and 24 ms.
  header = _mp3_frame_header(version_id=0b10, layer_id=0b01, bitrate_index=12, sample_rate_index=1)
  frame = header + (b"\0" * 380)
  return b"ID3\x04\x00\x00\x00\x00\x00\x00" + (frame * frame_count)


def _mp3_frame_header(
  *,
  version_id: int,
  layer_id: int,
  bitrate_index: int,
  sample_rate_index: int,
) -> bytes:
  header = (
    0x7FF << 21
    | version_id << 19
    | layer_id << 17
    | 1 << 16
    | bitrate_index << 12
    | sample_rate_index << 10
  )
  return header.to_bytes(4, "big")


def _configure_volcengine_env(monkeypatch, tmp_path):
  monkeypatch.setenv("SPEECH_ENABLED", "true")
  monkeypatch.setenv("SPEECH_PROVIDER", "volcengine")
  monkeypatch.setenv("SPEECH_MODEL", "seed-tts-1.0")
  monkeypatch.setenv("SPEECH_DEFAULT_VOICE", "")
  monkeypatch.setenv("SPEECH_FORMAT", "mp3")
  monkeypatch.setenv("SPEECH_CACHE_DIR", str(tmp_path))
  monkeypatch.setenv("SPEECH_PUBLIC_BASE_URL", "https://speech.test/audio")
  monkeypatch.setenv("VOLCENGINE_TTS_ENDPOINT", "https://openspeech.bytedance.com/api/v3/tts/unidirectional")
  monkeypatch.setenv("VOLCENGINE_TTS_API_KEY", "test-api-key")
  monkeypatch.setenv("VOLCENGINE_TTS_RESOURCE_ID", "seed-tts-1.0")
  monkeypatch.setenv("VOLCENGINE_TTS_SPEAKER", "zh_female_test")
  monkeypatch.setenv("VOLCENGINE_TTS_MODEL", "seed-tts-1.0")
  monkeypatch.setenv("VOLCENGINE_TTS_SAMPLE_RATE", "24000")
  monkeypatch.setenv("VOLCENGINE_TTS_BIT_RATE", "128000")
  monkeypatch.setenv("VOLCENGINE_TTS_SPEECH_RATE", "0")
  monkeypatch.setenv("VOLCENGINE_TTS_LOUDNESS_RATE", "0")
