import json
import re

from radio_agent.graph import (
  generate_radio,
  validate_and_repair,
  validate_entry_copy,
  validate_transition_copy,
)
from radio_agent.prompts import station_program_system_prompt, station_program_user_prompt
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


def test_english_speech_language_shapes_station_program_prompt():
  request = _request_with_two_tracks().model_copy(update={"speechLanguage": "en-US"})
  state = {
    "request": request,
    "candidates": request.seedTracks,
    "sharedMemory": {},
  }

  system_prompt = station_program_system_prompt(request.speechLanguage)
  payload = json.loads(station_program_user_prompt(request, state))

  assert "friend-like English radio host companion" in system_prompt
  assert payload["hostStyle"]["language"] == "en-US"
  assert payload["hostStyle"]["tone"].startswith("friend-like radio companion")
  assert payload["copyBudget"]["stationIntroText"].startswith("50-75 English words")
  assert payload["copyBudget"]["transitionText"].startswith("50-75 English words")
  assert payload["copyBudget"]["displayText"].startswith("8-16 English words")
  assert "friend-like English host intro" in payload["requiredShape"]["speech"]["stationIntro"]["text"]


def test_mock_english_response_contains_english_speech(monkeypatch):
  monkeypatch.delenv("OPENAI_API_KEY", raising=False)

  response = generate_radio(_request_with_two_tracks().model_copy(update={"speechLanguage": "en-US"}))

  assert response.mode == "mock"
  assert response.speech is not None
  assert response.speech.stationIntro is not None
  assert response.stationIntro.startswith("Opening with A")
  assert _sentence_count(response.speech.stationIntro.text) >= 2
  assert len(response.speech.stationIntro.text.split()) > len(response.stationIntro.split())
  assert _sentence_count(response.speech.betweenTracks[0].text) >= 2
  assert len(response.speech.betweenTracks[0].text.split()) >= 50
  assert len(response.speech.betweenTracks[0].text.split()) > len(response.speech.betweenTracks[0].displayText.split())
  assert response.speech.betweenTracks[0].displayText.startswith("Another side of the album")
  assert len(response.speech.betweenTracks[0].displayText.split()) <= 16
  assert "《" not in response.stationIntro


def test_single_call_llm_generates_station_program(monkeypatch):
  monkeypatch.setenv("OPENAI_API_KEY", "test-key")
  monkeypatch.delenv("RADIO_AGENT_GENERATION_MODE", raising=False)
  calls = []

  def fake_invoke(system_prompt, user_prompt, *, temperature):
    calls.append({
      "systemPrompt": system_prompt,
      "userPayload": json.loads(user_prompt),
      "temperature": temperature,
    })
    return json.dumps({
      "stationIntro": "A focused two-song set.",
      "items": [
        {"radioIdentity": "song-1", "reason": "first", "role": "opener", "score": 99, "source": "playlist"},
        {"radioIdentity": "song-2", "reason": "second", "role": "bridge", "score": 91, "source": "playlist"},
      ],
      "speech": {
        "stationIntro": {
          "id": "station-intro",
          "text": "Welcome into A then B.",
          "displayText": "Welcome into A then B.",
          "targetItemId": "song-1",
          "agent": "station_program_agent",
        },
        "betweenTracks": [
          {
            "id": "bridge-song-1-song-2",
            "fromItemId": "song-1",
            "toItemId": "song-2",
            "text": "That was A. Next is B.",
            "displayText": "Next: B by Artist B.",
            "agent": "station_program_agent",
          }
        ],
      },
    })

  monkeypatch.setattr("radio_agent.graph.invoke_chat", fake_invoke)

  response = generate_radio(_request_with_two_tracks())

  assert len(calls) == 1
  assert "station programming agent" in calls[0]["systemPrompt"]
  assert response.mode == "llm"
  assert [item.radioIdentity for item in response.items] == ["song-1", "song-2"]
  assert response.stationIntro == "Welcome into A then B."
  assert response.speech.stationIntro.agent == "station_program_agent"
  assert response.speech.betweenTracks[0].fromItemId == "song-1"
  assert response.speech.betweenTracks[0].toItemId == "song-2"


def test_single_call_invalid_json_falls_back_to_repaired_queue(monkeypatch):
  monkeypatch.setenv("OPENAI_API_KEY", "test-key")
  monkeypatch.delenv("RADIO_AGENT_GENERATION_MODE", raising=False)
  monkeypatch.setattr("radio_agent.graph.invoke_chat", lambda *args, **kwargs: "not json")

  response = generate_radio(_request_with_two_tracks())

  assert response.mode == "fallback"
  assert [item.radioIdentity for item in response.items] == ["song-1", "song-2"]
  assert "Station program payload was not valid JSON; using repaired fallback queue." in response.diagnostics
  assert "Generation payload was not valid JSON; using repaired fallback queue." in response.diagnostics


def test_single_call_repairs_unknown_tracks_and_bad_transitions(monkeypatch):
  monkeypatch.setenv("OPENAI_API_KEY", "test-key")
  monkeypatch.delenv("RADIO_AGENT_GENERATION_MODE", raising=False)

  def fake_invoke(*args, **kwargs):
    return json.dumps({
      "stationIntro": "A repaired set.",
      "items": [
        {"radioIdentity": "song-1", "reason": "first", "role": "opener", "score": 99, "source": "playlist"},
        {"radioIdentity": "made-up", "reason": "bad", "role": "bridge", "score": 90, "source": "catalog"},
      ],
      "speech": {
        "stationIntro": {
          "text": "A repaired intro.",
          "displayText": "A repaired intro.",
          "targetItemId": "song-1",
        },
        "betweenTracks": [
          {"fromItemId": "song-2", "toItemId": "song-1", "text": "bad", "displayText": "bad"}
        ],
      },
    })

  monkeypatch.setattr("radio_agent.graph.invoke_chat", fake_invoke)

  response = generate_radio(_request_with_two_tracks())

  assert response.mode == "llm"
  assert [item.radioIdentity for item in response.items] == ["song-1", "song-2"]
  assert response.speech.betweenTracks[0].fromItemId == "song-1"
  assert response.speech.betweenTracks[0].toItemId == "song-2"
  assert "《B》" in response.speech.betweenTracks[0].displayText
  assert not response.speech.betweenTracks[0].displayText.startswith("Next:")
  assert "Dropped unknown track from generation: made-up" in response.diagnostics
  assert "Dropped transition copy for non-adjacent pair: song-2 -> song-1" in response.diagnostics


def test_legacy_generation_mode_uses_multi_agent_path(monkeypatch):
  monkeypatch.setenv("OPENAI_API_KEY", "test-key")
  monkeypatch.setenv("RADIO_AGENT_GENERATION_MODE", "legacy_multi_agent")
  prompts = []

  def fake_invoke(system_prompt, user_prompt, *, temperature):
    prompts.append(system_prompt)
    if "recommendation agent" in system_prompt:
      return json.dumps({
        "items": [
          {"radioIdentity": "song-1", "reason": "first", "role": "opener", "score": 99, "source": "playlist"},
          {"radioIdentity": "song-2", "reason": "second", "role": "bridge", "score": 91, "source": "playlist"},
        ]
      })
    if "first-entry" in system_prompt:
      return json.dumps({
        "text": "Legacy intro.",
        "displayText": "Legacy intro.",
        "targetItemId": "song-1",
      })
    return json.dumps({
      "betweenTracks": [
        {
          "fromItemId": "song-1",
          "toItemId": "song-2",
          "text": "Legacy bridge.",
          "displayText": "Legacy bridge.",
        }
      ]
    })

  monkeypatch.setattr("radio_agent.graph.invoke_chat", fake_invoke)

  response = generate_radio(_request_with_two_tracks())

  assert len(prompts) == 3
  assert response.mode == "llm"
  assert response.stationIntro == "Legacy intro."
  assert response.speech.betweenTracks[0].displayText == "Legacy bridge."


def test_entry_copy_invalid_json_uses_default_intro():
  request = _request()
  state = {
    "request": request,
    "recommendedItems": [],
    "rawEntryCopy": "not json",
    "diagnostics": [],
  }

  result = validate_entry_copy(state)

  assert result["entryCopy"].displayText == "从 Morning 调出这一段，留一点发现新歌的空间"
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
  assert "《B》" in result["transitionCopies"][0].displayText
  assert not result["transitionCopies"][0].displayText.startswith("Next:")
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


def test_entry_copy_drops_unverified_claims():
  request = _request()
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
      )
    ],
    "rawEntryCopy": {
      "text": "这首歌创作于 2001 年，歌手当时写下了自己的故事。",
      "displayText": "这首歌创作于 2001 年。",
      "targetItemId": "song-1",
    },
    "diagnostics": [],
  }

  result = validate_entry_copy(state)

  assert "《A》" in result["entryCopy"].displayText
  assert "创作于" not in result["entryCopy"].text
  assert "Entry copy included unverified factual claims" in " ".join(result["diagnostics"])


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
  assert "《C》" in result["transitionCopies"][1].displayText
  assert not result["transitionCopies"][1].displayText.startswith("Next:")


def test_transition_copy_sanitizes_long_text_and_drops_unverified_claims():
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
          "id": "long-transition",
          "fromItemId": "song-1",
          "toItemId": "song-2",
          "text": "嗯，" + "这一段我们把刚才的亮度收回来，留一点空气感，再让下一首把边缘慢慢推开。" * 3,
          "displayText": "嗯，刚才的亮度收回来，再交给《B》。" * 2,
        },
        {
          "id": "unsafe-transition",
          "fromItemId": "song-2",
          "toItemId": "song-3",
          "text": "这首歌创作于 1999 年，背后是歌手当时的故事。Next up is C.",
          "displayText": "这首歌创作于 1999 年。",
        },
      ]
    },
    "diagnostics": [],
  }

  result = validate_transition_copy(state)

  assert len(result["transitionCopies"]) == 2
  assert result["transitionCopies"][0].id == "long-transition"
  assert len(result["transitionCopies"][0].text) <= 78
  assert len(result["transitionCopies"][0].displayText) <= 42
  assert result["transitionCopies"][0].text.count("嗯") <= 1
  assert result["transitionCopies"][1].id != "unsafe-transition"
  assert "unverified factual claims" in " ".join(result["diagnostics"])


def test_english_copy_keeps_long_spoken_text_with_english_periods():
  request = _request_with_two_tracks().model_copy(update={"speechLanguage": "en-US"})
  state = {
    "request": request,
    "candidateByID": {track.radioIdentity: track for track in request.seedTracks},
    "recommendedItems": [
      RadioGeneratedItem(radioIdentity="song-1", reason="first", role="opener", score=99, source="playlist"),
      RadioGeneratedItem(radioIdentity="song-2", reason="second", role="bridge", score=90, source="playlist"),
    ],
    "rawEntryCopy": {
      "id": "long-intro",
      "text": (
        "Hey, stay with me for a minute. This opening stretch is meant to feel warm, "
        "close, and easy while A gets the room settled. I will keep one ear on the "
        "familiar side of the set and one ear open for small surprises. "
      ) * 4,
      "displayText": (
        "A warm opening stretch with room for a small surprise while A settles in. "
      ) * 3,
      "targetItemId": "song-1",
    },
    "rawTransitionCopy": {
      "betweenTracks": [
        {
          "id": "long-english-transition",
          "fromItemId": "song-1",
          "toItemId": "song-2",
          "text": (
            "That first track gave us a bright little landing place. Let us carry "
            "that warmth into B without making the turn feel too sharp. The next "
            "song should keep the room open while adding a softer edge. "
          ) * 4,
          "displayText": "Warmth carries into B with a softer edge.",
        }
      ]
    },
    "diagnostics": [],
  }

  entry_result = validate_entry_copy(state)
  transition_result = validate_transition_copy(state)
  transition = transition_result["transitionCopies"][0]

  assert len(entry_result["entryCopy"].text) <= 480
  assert _sentence_count(entry_result["entryCopy"].text) >= 2
  assert entry_result["entryCopy"].text.endswith(".")
  assert not entry_result["entryCopy"].text.endswith("。")
  assert len(transition.text) <= 480
  assert _sentence_count(transition.text) >= 2
  assert transition.text.endswith(".")
  assert not transition.text.endswith("。")
  assert transition.displayText == "Warmth carries into B with a softer edge."


def test_transition_copy_drops_repetitive_template_openings():
  request = _request_with_three_tracks()
  state = {
    "request": request,
    "candidateByID": {track.radioIdentity: track for track in request.seedTracks},
    "recommendedItems": [
      RadioGeneratedItem(radioIdentity="song-1", reason="first", role="opener", score=99, source="playlist"),
      RadioGeneratedItem(radioIdentity="song-2", reason="second", role="bridge", score=90, source="playlist"),
      RadioGeneratedItem(radioIdentity="song-3", reason="third", role="closer", score=80, source="playlist"),
    ],
    "rawTransitionCopy": {
      "betweenTracks": [
        {
          "id": "template-1",
          "fromItemId": "song-1",
          "toItemId": "song-2",
          "text": "Next up, let us hear B by Artist B.",
          "displayText": "Next up: B.",
        },
        {
          "id": "template-2",
          "fromItemId": "song-2",
          "toItemId": "song-3",
          "text": "Next up, let us hear C by Artist C.",
          "displayText": "Next up: C.",
        },
      ]
    },
    "diagnostics": [],
  }

  result = validate_transition_copy(state)

  assert result["transitionCopies"][0].id == "template-1"
  assert result["transitionCopies"][1].id != "template-2"
  assert "Dropped repetitive transition opening" in " ".join(result["diagnostics"])


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


def _sentence_count(text: str) -> int:
  return len([part for part in re.split(r"[.!?]+", text) if part.strip()])
