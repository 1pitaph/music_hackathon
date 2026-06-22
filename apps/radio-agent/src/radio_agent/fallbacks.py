from __future__ import annotations

import math
from typing import Any

from radio_agent.schemas import (
  RadioGenerateRequest,
  RadioGeneratedItem,
  RadioTrack,
  RadioTransitionCopy,
)
from radio_agent.state_helpers import (
  AgentState,
  first_recommended_id,
  track_summary,
  transition_id,
  valid_transition_pairs,
)


def mock_entry_payload(state: AgentState) -> dict[str, Any]:
  request = state["request"]
  first_item_id = first_recommended_id(state)
  first_track = track_summary(state, first_item_id)

  if first_track:
    text = (
      f"Welcome to Airset Radio. We are starting with {first_track['title']} by "
      f"{first_track['artist']}, then letting your listening memory shape the next turns."
    )
    display_text = f"Starting with {first_track['title']} by {first_track['artist']}, tuned from your listening memory."
  else:
    text = "No playable candidates are available for this station yet."
    display_text = text

  if not first_track and request.seedTracks:
    text = default_intro(request)
    display_text = text

  return {
    "id": "station-intro",
    "text": text,
    "displayText": display_text,
    "targetItemId": first_item_id,
    "agent": "entry_copy_agent",
  }


def mock_transition_payload(state: AgentState) -> dict[str, Any]:
  return {
    "betweenTracks": [
      mock_transition_copy(state, pair).model_dump()
      for pair in valid_transition_pairs(state)
    ]
  }


def mock_transition_copy(state: AgentState, pair: tuple[str, str]) -> RadioTransitionCopy:
  pairs = valid_transition_pairs(state)
  from_track = track_summary(state, pair[0])
  to_track = track_summary(state, pair[1])
  if from_track and to_track:
    text = (
      f"From {from_track['title']} by {from_track['artist']}, Airset is handing off to "
      f"{to_track['title']} by {to_track['artist']} for a {to_track['mood'] or 'fresh'} turn."
    )
    display_text = f"Next: {to_track['title']} by {to_track['artist']}."
  else:
    text = "Airset is keeping the station moving into the next track."
    display_text = text

  return RadioTransitionCopy(
    id=transition_id(pair, pairs),
    fromItemId=pair[0],
    toItemId=pair[1],
    text=text,
    displayText=display_text,
    agent="transition_copy_agent",
  )


def mock_payload(state: AgentState) -> dict[str, Any]:
  request = state["request"]
  candidates = state.get("candidates", [])
  return {
    "items": [item.model_dump() for item in mock_items(request, candidates)],
  }


def mock_items(request: RadioGenerateRequest, candidates: list[RadioTrack]) -> list[RadioGeneratedItem]:
  liked = set(request.memory.likedTrackKeys)
  skipped = set(request.memory.skippedTrackKeys)
  disliked = set(request.memory.dislikedTrackKeys)
  recent = {key: index for index, key in enumerate(request.memory.recentlyPlayedTrackKeys)}

  def score(track: RadioTrack) -> float:
    value = 62.0 if track.playlistName else 44.0
    if track.radioIdentity in liked:
      value += 35
    if track.radioIdentity in skipped:
      value -= 18
    if track.radioIdentity in disliked:
      value -= 120
    if track.radioIdentity in recent:
      value -= max(8, 28 - recent[track.radioIdentity] * 4)
    if track.duration:
      value += max(0, 8 - abs(track.duration - 210) / 30)
    if not track.playlistName:
      value += (1 - request.tuning.familiarity) * 18
    return round(value, 2)

  ranked = sorted(candidates, key=lambda track: (-score(track), track.artist.lower(), track.title.lower()))
  distributed = distribute_artists(ranked)
  items: list[RadioGeneratedItem] = []
  for index, track in enumerate(distributed[: request.limit]):
    source = "playlist" if track.playlistName else "catalog"
    items.append(
      RadioGeneratedItem(
        radioIdentity=track.radioIdentity,
        reason=mock_reason(track, source, index),
        role=role_for_index(index, request.limit, source),
        score=score(track),
        source=source,
      )
    )
  return items


def distribute_artists(tracks: list[RadioTrack]) -> list[RadioTrack]:
  remaining = list(tracks)
  result: list[RadioTrack] = []
  previous_artist: str | None = None

  while remaining:
    index = next(
      (idx for idx, track in enumerate(remaining) if track.artist.casefold() != previous_artist),
      0,
    )
    track = remaining.pop(index)
    result.append(track)
    previous_artist = track.artist.casefold()

  return result


def item_from_raw(track: RadioTrack, raw_item: dict[str, Any], index: int) -> RadioGeneratedItem:
  source = str(raw_item.get("source") or ("playlist" if track.playlistName else "catalog"))
  fallback_score = max(1, 90 - index * 3)
  return RadioGeneratedItem(
    radioIdentity=track.radioIdentity,
    reason=str(raw_item.get("reason") or mock_reason(track, source, index)),
    role=str(raw_item.get("role") or role_for_index(index, 14, source)),
    score=coerce_score(raw_item.get("score"), fallback_score),
    source=source,
  )


def coerce_score(value: Any, fallback: float) -> float:
  try:
    score = float(value)
  except (TypeError, ValueError):
    return float(fallback)

  if not math.isfinite(score):
    return float(fallback)
  return score


def default_intro(request: RadioGenerateRequest) -> str:
  playlist_names = sorted({track.playlistName for track in request.seedTracks if track.playlistName})
  if len(playlist_names) == 1:
    return f"Tuned from {playlist_names[0]}, with a little room for discovery."
  if len(playlist_names) > 1:
    return f"Blending {len(playlist_names)} playlists into a personal radio set."
  return "Airset is shaping a personal radio set from your current music seeds."


def mock_reason(track: RadioTrack, source: str, index: int) -> str:
  if source == "playlist" and track.playlistName:
    return f"Pulled from {track.playlistName} as a familiar anchor for this set."
  if index == 0:
    return f"Opens the set with {track.artist}'s lane and a clear signal."
  return f"Matched near {track.artist} and the {track.mood or 'Apple Music'} thread."


def role_for_index(index: int, limit: int, source: str) -> str:
  if index == 0:
    return "opener"
  if index >= max(0, limit - 1):
    return "closer"
  if source == "catalog":
    return "discovery"
  return "anchor" if index % 3 == 0 else "bridge"
