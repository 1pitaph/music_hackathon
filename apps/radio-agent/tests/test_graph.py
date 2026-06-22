from radio_agent.graph import validate_and_repair
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
