from radio_agent.graph import (
  generate_radio,
  validate_and_repair,
  validate_entry_copy,
  validate_transition_copy,
)
from radio_agent.schemas import RadioGenerateRequest, RadioGeneratedItem, RadioTrack


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


def test_fenced_json_duplicate_items_and_non_numeric_score_are_repaired():
  request = _request_with_three_tracks()
  state = {
    "request": request,
    "candidates": request.seedTracks,
    "candidateByID": {track.radioIdentity: track for track in request.seedTracks},
    "mode": "llm",
    "rawGeneration": """
    ```json
    {
      "stationIntro": "A focused set.",
      "items": [
        {"radioIdentity": "song-1", "reason": "first", "role": "opener", "score": "high", "source": "playlist"},
        {"radioIdentity": "song-1", "reason": "duplicate", "role": "bridge", "score": 88, "source": "playlist"}
      ]
    }
    ```
    """,
    "diagnostics": [],
  }

  result = validate_and_repair(state)

  response = result["response"]
  assert response.mode == "llm"
  assert response.stationIntro == "A focused set."
  assert response.items[0].radioIdentity == "song-1"
  assert {item.radioIdentity for item in response.items} == {"song-1", "song-2", "song-3"}
  assert response.items[0].score == 90


def test_valid_entry_copy_repairs_invalid_target_item():
  state = {
    "request": _request(),
    "recommendedItems": [
      RadioGeneratedItem(
        radioIdentity="song-1",
        reason="first",
        role="opener",
        score=99,
        source="playlist",
      )
    ],
    "rawEntryCopy": {
      "id": "custom-intro",
      "text": "Full host copy.",
      "displayText": "Short host copy.",
      "targetItemId": "made-up",
      "agent": "test_agent",
    },
    "diagnostics": [],
  }

  result = validate_entry_copy(state)

  assert result["entryCopy"].id == "custom-intro"
  assert result["entryCopy"].displayText == "Short host copy."
  assert result["entryCopy"].targetItemId == "song-1"
  assert result["entryCopy"].agent == "test_agent"


def test_transition_copy_keeps_valid_pairs_and_fills_missing_bridge():
  request = _request_with_three_tracks()
  state = {
    "request": request,
    "candidateByID": {track.radioIdentity: track for track in request.seedTracks},
    "recommendedItems": [
      RadioGeneratedItem(
        radioIdentity="song-1",
        reason="first",
        role="opener",
        score=99,
        source="playlist",
      ),
      RadioGeneratedItem(
        radioIdentity="song-2",
        reason="second",
        role="bridge",
        score=90,
        source="playlist",
      ),
      RadioGeneratedItem(
        radioIdentity="song-3",
        reason="third",
        role="closer",
        score=80,
        source="playlist",
      ),
    ],
    "rawTransitionCopy": {
      "betweenTracks": [
        {
          "id": "custom-transition",
          "fromItemId": "song-1",
          "toItemId": "song-2",
          "text": "Custom full bridge.",
          "displayText": "Custom display bridge.",
          "agent": "test_agent",
        }
      ]
    },
    "diagnostics": [],
  }

  result = validate_transition_copy(state)

  assert len(result["transitionCopies"]) == 2
  assert result["transitionCopies"][0].id == "custom-transition"
  assert result["transitionCopies"][0].displayText == "Custom display bridge."
  assert result["transitionCopies"][1].fromItemId == "song-2"
  assert result["transitionCopies"][1].toItemId == "song-3"
  assert result["transitionCopies"][1].displayText.startswith("Next:")


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


def _request_with_three_tracks():
  request = _request_with_two_tracks()
  return RadioGenerateRequest(
    action=request.action,
    limit=3,
    seedTracks=[
      *request.seedTracks,
      RadioTrack(
        radioIdentity="song-3",
        title="C",
        artist="Artist C",
        album="Album",
        mood="Chill",
        duration=205,
        appleMusicID="3",
        playlistName="Morning",
      ),
    ],
  )
