from __future__ import annotations

import json
import re
from typing import Any

from radio_agent.fallbacks import (
  default_intro,
  item_from_raw,
  mock_entry_payload,
  mock_items,
  mock_payload,
  mock_transition_copy,
  mock_transition_payload,
)
from radio_agent.schemas import (
  RadioEntryCopy,
  RadioGenerateResponse,
  RadioGeneratedItem,
  RadioSpeech,
  RadioTransitionCopy,
)
from radio_agent.state_helpers import (
  AgentState,
  first_recommended_id,
  transition_id,
  valid_transition_pairs,
)


def parse_generation(raw_generation: str | dict[str, Any] | None) -> dict[str, Any] | None:
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


def validate_recommendations(state: AgentState) -> dict[str, Any]:
  request = state["request"]
  diagnostics = list(state.get("diagnostics", []))
  candidates = state.get("candidates", [])
  candidate_by_id = state.get("candidateByID", {})
  mode = state.get("mode", "fallback")
  raw_generation = state.get("rawRecommendation", state.get("rawGeneration"))

  if not candidates:
    return {**state, "recommendedItems": [], "mode": "fallback", "diagnostics": diagnostics}

  payload = parse_generation(raw_generation)
  if payload is None:
    diagnostics.append("Generation payload was not valid JSON; using repaired fallback queue.")
    payload = mock_payload(state)
    mode = "fallback" if mode == "llm" else "mock"

  station_intro = str(payload.get("stationIntro") or default_intro(request))
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
    repaired_items.append(item_from_raw(track, raw_item, len(repaired_items)))
    if len(repaired_items) >= request.limit:
      break

  if not repaired_items:
    diagnostics.append("Generation returned no usable tracks; using deterministic fallback queue.")
    mode = "fallback" if state.get("mode") == "llm" else "mock"
    repaired_items = mock_items(request, candidates)

  if len(repaired_items) < request.limit:
    fill_items = mock_items(request, candidates)
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
  return {
    **state,
    "legacyStationIntro": station_intro,
    "recommendedItems": response.items,
    "mode": response.mode,
    "diagnostics": diagnostics,
  }


def validate_and_repair(state: AgentState) -> dict[str, Any]:
  state = validate_recommendations(state)
  if "rawEntryCopy" not in state and state.get("legacyStationIntro"):
    station_intro = str(state["legacyStationIntro"])
    state = {
      **state,
      "rawEntryCopy": {
        "text": station_intro,
        "displayText": station_intro,
        "targetItemId": first_recommended_id(state),
      },
    }
  state = validate_entry_copy(state)
  if "rawTransitionCopy" not in state:
    state = {**state, "rawTransitionCopy": mock_transition_payload(state)}
  state = validate_transition_copy(state)
  return assemble_response(state)


def validate_entry_copy(state: AgentState) -> dict[str, Any]:
  diagnostics = list(state.get("diagnostics", []))
  raw_entry = state.get("rawEntryCopy")
  payload = parse_generation(raw_entry)
  if payload is None:
    diagnostics.append("Entry copy payload was not valid JSON; using deterministic intro.")
    payload = mock_entry_payload(state)

  valid_item_ids = {item.radioIdentity for item in state.get("recommendedItems", [])}
  target_item_id = payload.get("targetItemId")
  if target_item_id not in valid_item_ids:
    target_item_id = first_recommended_id(state)

  text = str(payload.get("text") or payload.get("displayText") or "").strip()
  display_text = str(payload.get("displayText") or text).strip()
  if not text or not display_text:
    diagnostics.append("Entry copy payload was empty; using deterministic intro.")
    payload = mock_entry_payload(state)
    text = str(payload["text"])
    display_text = str(payload["displayText"])
    target_item_id = payload.get("targetItemId")

  entry_copy = RadioEntryCopy(
    id=str(payload.get("id") or "station-intro"),
    text=text,
    displayText=display_text,
    targetItemId=target_item_id,
    agent=str(payload.get("agent") or "entry_copy_agent"),
  )
  return {**state, "entryCopy": entry_copy, "diagnostics": diagnostics}


def validate_transition_copy(state: AgentState) -> dict[str, Any]:
  diagnostics = list(state.get("diagnostics", []))
  payload = parse_generation(state.get("rawTransitionCopy"))
  if payload is None:
    diagnostics.append("Transition copy payload was not valid JSON; using deterministic bridges.")
    payload = mock_transition_payload(state)

  valid_pairs = valid_transition_pairs(state)
  raw_copies = payload.get("betweenTracks") if isinstance(payload.get("betweenTracks"), list) else []
  copies_by_pair: dict[tuple[str, str], RadioTransitionCopy] = {}

  for raw_copy in raw_copies:
    if not isinstance(raw_copy, dict):
      continue
    pair = (str(raw_copy.get("fromItemId") or ""), str(raw_copy.get("toItemId") or ""))
    if pair not in valid_pairs:
      if pair != ("", ""):
        diagnostics.append(f"Dropped transition copy for non-adjacent pair: {pair[0]} -> {pair[1]}")
      continue

    text = str(raw_copy.get("text") or raw_copy.get("displayText") or "").strip()
    display_text = str(raw_copy.get("displayText") or text).strip()
    if not text or not display_text:
      continue

    copies_by_pair[pair] = RadioTransitionCopy(
      id=str(raw_copy.get("id") or transition_id(pair, valid_pairs)),
      fromItemId=pair[0],
      toItemId=pair[1],
      text=text,
      displayText=display_text,
      agent=str(raw_copy.get("agent") or "transition_copy_agent"),
    )

  transition_copies = []
  for pair in valid_pairs:
    transition_copies.append(copies_by_pair.get(pair) or mock_transition_copy(state, pair))

  return {**state, "transitionCopies": transition_copies, "diagnostics": diagnostics}


def assemble_response(state: AgentState) -> dict[str, Any]:
  entry_copy = state.get("entryCopy") or RadioEntryCopy.model_validate(mock_entry_payload(state))
  transition_copies = state.get("transitionCopies", [])
  diagnostics = list(dict.fromkeys(state.get("diagnostics", [])))
  mode = state.get("mode", "fallback")
  if mode not in {"llm", "mock", "fallback"}:
    mode = "fallback"

  response = RadioGenerateResponse(
    mode=mode,
    stationIntro=entry_copy.displayText,
    items=state.get("recommendedItems", [])[: state["request"].limit],
    speech=RadioSpeech(
      stationIntro=entry_copy,
      betweenTracks=transition_copies,
    ),
    diagnostics=diagnostics,
  )
  return {**state, "response": response, "diagnostics": diagnostics}


def finalize_response(state: AgentState) -> dict[str, Any]:
  response = state["response"]
  diagnostics = list(dict.fromkeys([*response.diagnostics, *state.get("diagnostics", [])]))
  return {**state, "response": response.model_copy(update={"diagnostics": diagnostics})}
