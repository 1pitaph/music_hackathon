from __future__ import annotations

import json
import os
import re
from typing import Any, TypedDict

from dotenv import load_dotenv
from langchain_core.messages import HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI
from langgraph.graph import END, START, StateGraph

from radio_agent.schemas import (
  RadioGenerateRequest,
  RadioGenerateResponse,
  RadioGeneratedItem,
  RadioTrack,
)

load_dotenv()


class RadioAgentState(TypedDict, total=False):
  request: RadioGenerateRequest
  candidates: list[RadioTrack]
  candidateByID: dict[str, RadioTrack]
  diagnostics: list[str]
  mode: str
  rawGeneration: str | dict[str, Any] | None
  response: RadioGenerateResponse


def prepare_context(state: RadioAgentState) -> RadioAgentState:
  request = state["request"]
  diagnostics = list(state.get("diagnostics", []))
  candidates: list[RadioTrack] = []
  seen: set[str] = set()

  for track in [*request.seedTracks, *request.catalogCandidates]:
    if track.radioIdentity in seen:
      continue
    seen.add(track.radioIdentity)
    candidates.append(track)

  if not candidates:
    diagnostics.append("No candidate tracks supplied.")

  return {
    **state,
    "candidates": candidates,
    "candidateByID": {track.radioIdentity: track for track in candidates},
    "diagnostics": diagnostics,
  }


def choose_generation_path(state: RadioAgentState) -> RadioAgentState:
  diagnostics = list(state.get("diagnostics", []))
  if not state.get("candidates"):
    return {**state, "mode": "fallback", "diagnostics": diagnostics}

  if os.getenv("OPENAI_API_KEY"):
    return {**state, "mode": "llm", "diagnostics": diagnostics}

  diagnostics.append("OPENAI_API_KEY is not set; using deterministic mock generation.")
  return {**state, "mode": "mock", "diagnostics": diagnostics}


def generate_with_llm(state: RadioAgentState) -> RadioAgentState:
  request = state["request"]
  diagnostics = list(state.get("diagnostics", []))
  model = os.getenv("OPENAI_MODEL") or "gpt-4.1-mini"
  base_url = os.getenv("OPENAI_BASE_URL") or None

  try:
    llm = ChatOpenAI(
      model=model,
      api_key=os.getenv("OPENAI_API_KEY"),
      base_url=base_url,
      temperature=0.5,
      timeout=8,
    )
    result = llm.invoke([
      SystemMessage(content=_system_prompt()),
      HumanMessage(content=_user_prompt(request, state.get("candidates", []))),
    ])
    return {**state, "rawGeneration": result.content, "diagnostics": diagnostics}
  except Exception as error:  # pragma: no cover - network failures are environment-specific.
    diagnostics.append(f"LLM generation failed: {error}")
    return {**state, "mode": "fallback", "rawGeneration": None, "diagnostics": diagnostics}


def mock_generate(state: RadioAgentState) -> RadioAgentState:
  return {**state, "rawGeneration": _mock_payload(state), "mode": state.get("mode", "mock")}


def validate_and_repair(state: RadioAgentState) -> RadioAgentState:
  request = state["request"]
  diagnostics = list(state.get("diagnostics", []))
  candidates = state.get("candidates", [])
  candidate_by_id = state.get("candidateByID", {})
  mode = state.get("mode", "fallback")
  raw_generation = state.get("rawGeneration")

  if not candidates:
    response = RadioGenerateResponse(
      mode="fallback",
      stationIntro="No playable candidates are available for this station yet.",
      items=[],
      diagnostics=diagnostics,
    )
    return {**state, "response": response, "mode": "fallback", "diagnostics": diagnostics}

  payload = _parse_generation(raw_generation)
  if payload is None:
    diagnostics.append("Generation payload was not valid JSON; using repaired fallback queue.")
    payload = _mock_payload(state)
    mode = "fallback" if mode == "llm" else "mock"

  station_intro = str(payload.get("stationIntro") or _default_intro(request))
  raw_items = payload.get("items") if isinstance(payload.get("items"), list) else []
  repaired_items: list[RadioGeneratedItem] = []
  used: set[str] = set()

  for raw_item in raw_items:
    if not isinstance(raw_item, dict):
      continue

    radio_identity = str(raw_item.get("radioIdentity") or "")
    track = candidate_by_id.get(radio_identity)
    if track is None:
      if radio_identity:
        diagnostics.append(f"Dropped unknown track from generation: {radio_identity}")
      continue

    if radio_identity in used:
      continue

    used.add(radio_identity)
    repaired_items.append(_item_from_raw(track, raw_item, len(repaired_items)))
    if len(repaired_items) >= request.limit:
      break

  if not repaired_items:
    diagnostics.append("Generation returned no usable tracks; using deterministic fallback queue.")
    mode = "fallback" if state.get("mode") == "llm" else "mock"
    repaired_items = _mock_items(request, candidates)

  if len(repaired_items) < request.limit:
    fill_items = _mock_items(request, candidates)
    for item in fill_items:
      if item.radioIdentity in used:
        continue
      repaired_items.append(item)
      used.add(item.radioIdentity)
      if len(repaired_items) >= request.limit:
        break

  response = RadioGenerateResponse(
    mode=mode if mode in {"llm", "mock"} else "fallback",
    stationIntro=station_intro,
    items=repaired_items[:request.limit],
    diagnostics=diagnostics,
  )
  return {**state, "response": response, "mode": response.mode, "diagnostics": diagnostics}


def finalize_response(state: RadioAgentState) -> RadioAgentState:
  response = state["response"]
  diagnostics = list(dict.fromkeys([*response.diagnostics, *state.get("diagnostics", [])]))
  return {**state, "response": response.model_copy(update={"diagnostics": diagnostics})}


def build_graph():
  graph = StateGraph(RadioAgentState)
  graph.add_node("prepare_context", prepare_context)
  graph.add_node("choose_generation_path", choose_generation_path)
  graph.add_node("generate_with_llm", generate_with_llm)
  graph.add_node("mock_generate", mock_generate)
  graph.add_node("validate_and_repair", validate_and_repair)
  graph.add_node("finalize_response", finalize_response)

  graph.add_edge(START, "prepare_context")
  graph.add_edge("prepare_context", "choose_generation_path")
  graph.add_conditional_edges(
    "choose_generation_path",
    lambda state: state.get("mode", "fallback"),
    {
      "llm": "generate_with_llm",
      "mock": "mock_generate",
      "fallback": "validate_and_repair",
    },
  )
  graph.add_edge("generate_with_llm", "validate_and_repair")
  graph.add_edge("mock_generate", "validate_and_repair")
  graph.add_edge("validate_and_repair", "finalize_response")
  graph.add_edge("finalize_response", END)
  return graph.compile()


radio_graph = build_graph()


def generate_radio(request: RadioGenerateRequest) -> RadioGenerateResponse:
  result = radio_graph.invoke({"request": request, "diagnostics": []})
  return result["response"]


def _system_prompt() -> str:
  return (
    "You are Airset Radio's programming agent. Generate a compact radio queue as JSON only. "
    "You must choose only from the provided candidate tracks. Do not invent songs, artists, IDs, "
    "facts, or user biography. Keep reasons short, specific, and suitable for UI display."
  )


def _user_prompt(request: RadioGenerateRequest, candidates: list[RadioTrack]) -> str:
  candidate_payload = [
    {
      "radioIdentity": track.radioIdentity,
      "title": track.title,
      "artist": track.artist,
      "album": track.album,
      "mood": track.mood,
      "duration": track.duration,
      "source": track.source,
      "playlistName": track.playlistName,
    }
    for track in candidates
  ]
  payload = {
    "action": request.action,
    "tuning": request.tuning.model_dump(),
    "memory": request.memory.model_dump(),
    "limit": request.limit,
    "candidates": candidate_payload,
    "requiredShape": {
      "stationIntro": "string",
      "items": [
        {
          "radioIdentity": "must match a provided candidate",
          "reason": "short UI-ready explanation",
          "role": "opener|bridge|anchor|discovery|closer",
          "score": "number",
          "source": "playlist|catalog",
        }
      ],
    },
  }
  return json.dumps(payload, ensure_ascii=False)


def _parse_generation(raw_generation: str | dict[str, Any] | None) -> dict[str, Any] | None:
  if isinstance(raw_generation, dict):
    return raw_generation

  if not isinstance(raw_generation, str):
    return None

  cleaned = raw_generation.strip()
  fenced = re.match(r"^```(?:json)?\s*(.*?)\s*```$", cleaned, flags=re.DOTALL)
  if fenced:
    cleaned = fenced.group(1).strip()

  try:
    value = json.loads(cleaned)
  except json.JSONDecodeError:
    return None

  return value if isinstance(value, dict) else None


def _mock_payload(state: RadioAgentState) -> dict[str, Any]:
  request = state["request"]
  candidates = state.get("candidates", [])
  return {
    "stationIntro": _default_intro(request),
    "items": [item.model_dump() for item in _mock_items(request, candidates)],
  }


def _mock_items(request: RadioGenerateRequest, candidates: list[RadioTrack]) -> list[RadioGeneratedItem]:
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
  distributed = _distribute_artists(ranked)
  items: list[RadioGeneratedItem] = []
  for index, track in enumerate(distributed[: request.limit]):
    source = "playlist" if track.playlistName else "catalog"
    items.append(
      RadioGeneratedItem(
        radioIdentity=track.radioIdentity,
        reason=_mock_reason(track, source, index),
        role=_role_for_index(index, request.limit, source),
        score=score(track),
        source=source,
      )
    )
  return items


def _distribute_artists(tracks: list[RadioTrack]) -> list[RadioTrack]:
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


def _item_from_raw(track: RadioTrack, raw_item: dict[str, Any], index: int) -> RadioGeneratedItem:
  source = str(raw_item.get("source") or ("playlist" if track.playlistName else "catalog"))
  return RadioGeneratedItem(
    radioIdentity=track.radioIdentity,
    reason=str(raw_item.get("reason") or _mock_reason(track, source, index)),
    role=str(raw_item.get("role") or _role_for_index(index, 14, source)),
    score=float(raw_item.get("score") or max(1, 90 - index * 3)),
    source=source,
  )


def _default_intro(request: RadioGenerateRequest) -> str:
  playlist_names = sorted({track.playlistName for track in request.seedTracks if track.playlistName})
  if len(playlist_names) == 1:
    return f"Tuned from {playlist_names[0]}, with a little room for discovery."
  if len(playlist_names) > 1:
    return f"Blending {len(playlist_names)} playlists into a personal radio set."
  return "Airset is shaping a personal radio set from your current music seeds."


def _mock_reason(track: RadioTrack, source: str, index: int) -> str:
  if source == "playlist" and track.playlistName:
    return f"Pulled from {track.playlistName} as a familiar anchor for this set."
  if index == 0:
    return f"Opens the set with {track.artist}'s lane and a clear signal."
  return f"Matched near {track.artist} and the {track.mood or 'Apple Music'} thread."


def _role_for_index(index: int, limit: int, source: str) -> str:
  if index == 0:
    return "opener"
  if index >= max(0, limit - 1):
    return "closer"
  if source == "catalog":
    return "discovery"
  return "anchor" if index % 3 == 0 else "bridge"
