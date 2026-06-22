from radio_agent.graph import (
  generate_radio,
  validate_and_repair,
  validate_entry_copy,
  validate_transition_copy,
)
from radio_agent.schemas import RadioGenerateRequest, RadioTrack


def test_invalid_llm_json_falls_back_to_repaired_queue():
  request = _request()
  state = {
    "request": request,
    "candidates": request.seedTracks,
    "candidateByID": {track.radioIdentity: track for track in request.seedTracks},
    "mode": "llm",
    "rawGeneration": "not json",
    "diagnostics": [],
  }

  result = validate_and_repair(state)

  response = result["response"]
  assert response.mode == "fallback"
  assert response.items[0].radioIdentity == "song-1"
  assert response.speech is not None
  assert response.speech.stationIntro is not None
  assert "Generation payload was not valid JSON; using repaired fallback queue." in response.diagnostics


def test_unknown_tracks_are_repaired_from_candidates():
  request = _request()
  state = {
    "request": request,
    "candidates": request.seedTracks,
    "candidateByID": {track.radioIdentity: track for track in request.seedTracks},
    "mode": "llm",
    "rawGeneration": {
      "stationIntro": "Test",
      "items": [
        {"radioIdentity": "made-up", "reason": "bad", "role": "opener", "score": 99, "source": "catalog"}
      ],
    },
    "diagnostics": [],
  }

  result = validate_and_repair(state)

  response = result["response"]
  assert response.mode == "fallback"
  assert response.items[0].radioIdentity == "song-1"
  assert "Dropped unknown track from generation: made-up" in response.diagnostics


def test_mock_multi_agent_response_contains_speech(monkeypatch):
  monkeypatch.delenv("OPENAI_API_KEY", raising=False)

  response = generate_radio(_request())

  assert response.mode == "mock"
  assert response.speech is not None
  assert response.speech.stationIntro is not None
  assert response.speech.stationIntro.displayText == response.stationIntro
  assert len(response.speech.betweenTracks) == 0


def test_entry_copy_invalid_json_uses_default_intro():
  request = _request()
  state = {
    "request": request,
    "recommendedItems": [],
    "rawEntryCopy": "not json",
    "diagnostics": [],
  }

  result = validate_entry_copy(state)

  assert result["entryCopy"].displayText == "Tuned from Morning, with a little room for discovery."
  assert "Entry copy payload was not valid JSON; using deterministic intro." in result["diagnostics"]


def test_transition_copy_drops_non_adjacent_pairs_and_fills_template():
  request = _request_with_two_tracks()
  state = {
    "request": request,
    "candidateByID": {track.radioIdentity: track for track in request.seedTracks},
    "recommendedItems": [
      item for item in validate_and_repair({
        "request": request,
        "candidates": request.seedTracks,
        "candidateByID": {track.radioIdentity: track for track in request.seedTracks},
        "mode": "mock",
        "rawRecommendation": {"items": [
          {"radioIdentity": "song-1", "reason": "first", "role": "opener", "score": 99, "source": "playlist"},
          {"radioIdentity": "song-2", "reason": "second", "role": "bridge", "score": 90, "source": "playlist"},
        ]},
        "diagnostics": [],
      })["response"].items
    ],
    "rawTransitionCopy": {
      "betweenTracks": [
        {"fromItemId": "song-2", "toItemId": "song-1", "text": "bad", "displayText": "bad"}
      ]
    },
    "diagnostics": [],
  }

  result = validate_transition_copy(state)

  assert len(result["transitionCopies"]) == 1
  assert result["transitionCopies"][0].fromItemId == "song-1"
  assert result["transitionCopies"][0].toItemId == "song-2"
  assert result["transitionCopies"][0].displayText.startswith("Next:")
  assert "Dropped transition copy for non-adjacent pair: song-2 -> song-1" in result["diagnostics"]


def _request():
  return RadioGenerateRequest(
    action="start",
    limit=3,
    seedTracks=[
      RadioTrack(
        radioIdentity="song-1",
        title="A",
        artist="Artist A",
        album="Album",
        mood="Pop",
        duration=210,
        appleMusicID="1",
        playlistName="Morning",
      )
    ],
  )


def _request_with_two_tracks():
  return RadioGenerateRequest(
    action="start",
    limit=3,
    seedTracks=[
      RadioTrack(
        radioIdentity="song-1",
        title="A",
        artist="Artist A",
        album="Album",
        mood="Pop",
        duration=210,
        appleMusicID="1",
        playlistName="Morning",
      ),
      RadioTrack(
        radioIdentity="song-2",
        title="B",
        artist="Artist B",
        album="Album",
        mood="Indie",
        duration=200,
        appleMusicID="2",
        playlistName="Morning",
      ),
    ],
  )
