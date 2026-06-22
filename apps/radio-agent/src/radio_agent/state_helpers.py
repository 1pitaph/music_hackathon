from __future__ import annotations

from typing import Any, Mapping

from radio_agent.schemas import RadioGeneratedItem

AgentState = Mapping[str, Any]


def trim_memory_markdown(memory_markdown: str) -> str:
  cleaned = memory_markdown.strip()
  if len(cleaned) <= 6000:
    return cleaned
  return cleaned[:6000] + "\n\n[Memory markdown truncated by server.]"


def first_recommended_id(state: AgentState) -> str | None:
  items = state.get("recommendedItems", [])
  return items[0].radioIdentity if items else None


def track_summary(state: AgentState, radio_identity: str | None) -> dict[str, Any] | None:
  if not radio_identity:
    return None

  track = state.get("candidateByID", {}).get(radio_identity)
  if track is None:
    return None
  return {
    "radioIdentity": track.radioIdentity,
    "title": track.title,
    "artist": track.artist,
    "album": track.album,
    "mood": track.mood,
    "duration": track.duration,
    "source": track.source,
    "sourceLane": track.sourceLane,
    "reasonSignals": track.reasonSignals,
    "playlistName": track.playlistName,
  }


def tracks_for_items(state: AgentState, items: list[RadioGeneratedItem]) -> list[dict[str, Any]]:
  tracks = []
  for item in items:
    track = track_summary(state, item.radioIdentity)
    if track:
      tracks.append({**track, "recommendationReason": item.reason, "role": item.role})
  return tracks


def valid_transition_pairs(state: AgentState) -> list[tuple[str, str]]:
  items = state.get("recommendedItems", [])
  return [
    (items[index].radioIdentity, items[index + 1].radioIdentity)
    for index in range(max(0, len(items) - 1))
  ]


def transition_id(pair: tuple[str, str], pairs: list[tuple[str, str]]) -> str:
  try:
    index = pairs.index(pair) + 1
  except ValueError:
    index = 1
  return f"transition-{index}"
