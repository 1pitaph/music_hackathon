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

ENTRY_TEXT_MAX_CHARS = 120
ENGLISH_ENTRY_TEXT_MAX_CHARS = 480
ENTRY_DISPLAY_MAX_CHARS = 80
TRANSITION_TEXT_MAX_CHARS = 78
ENGLISH_TRANSITION_TEXT_MAX_CHARS = 480
TRANSITION_DISPLAY_MAX_CHARS = 42

SPOKEN_FILLERS = ("嗯", "呃", "啊", "怎么说呢", "好，", "好,")
UNVERIFIED_FACT_PATTERNS = [
  r"创作(?:于|自|灵感)",
  r"发行(?:于|在)?\s*\d{4}",
  r"\d{4}\s*年.*(?:发行|创作|写下)",
  r"(?:歌手|艺人).{0,12}(?:当时|曾经|经历|写下|创作)",
  r"(?:这首歌|歌曲).{0,12}(?:讲的是|写的是|背后|来源|灵感)",
  r"歌词.{0,16}(?:写|唱|讲|意思)",
  r"你(?:曾经|当时|一定|应该|其实|内心)",
  r"released in",
  r"written by",
  r"wrote this",
  r"the lyrics",
  r"this song is about",
]


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


def validate_station_program(state: AgentState) -> dict[str, Any]:
  diagnostics = list(state.get("diagnostics", []))
  payload = parse_generation(state.get("rawProgram"))
  if payload is None:
    diagnostics.append("Station program payload was not valid JSON; using repaired fallback queue.")
    return validate_and_repair({**state, "rawRecommendation": None, "diagnostics": diagnostics})

  next_state = {
    **state,
    "rawRecommendation": payload,
    "diagnostics": diagnostics,
  }
  speech_payload = payload.get("speech") if isinstance(payload.get("speech"), dict) else {}

  raw_entry = speech_payload.get("stationIntro") if isinstance(speech_payload, dict) else None
  if raw_entry is None:
    raw_entry = payload.get("stationIntroCopy")
  if isinstance(raw_entry, dict):
    next_state["rawEntryCopy"] = raw_entry

  raw_transitions = speech_payload.get("betweenTracks") if isinstance(speech_payload, dict) else None
  if raw_transitions is None:
    raw_transitions = payload.get("betweenTracks")
  if isinstance(raw_transitions, list):
    next_state["rawTransitionCopy"] = {"betweenTracks": raw_transitions}

  return validate_and_repair(next_state)


def validate_entry_copy(state: AgentState) -> dict[str, Any]:
  is_english = _is_english_request(state.get("request"))
  terminal = "." if is_english else "。"
  text_max_chars = ENGLISH_ENTRY_TEXT_MAX_CHARS if is_english else ENTRY_TEXT_MAX_CHARS
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

  if _contains_unverified_fact(text) or _contains_unverified_fact(display_text):
    diagnostics.append("Entry copy included unverified factual claims; using deterministic intro.")
    payload = mock_entry_payload(state)
    text = str(payload["text"])
    display_text = str(payload["displayText"])
    target_item_id = payload.get("targetItemId")

  text = _clean_spoken_text(text, text_max_chars, terminal)
  display_text = _clean_display_text(display_text, ENTRY_DISPLAY_MAX_CHARS, terminal)
  if not display_text:
    display_text = _clean_display_text(text, ENTRY_DISPLAY_MAX_CHARS, terminal)

  entry_copy = RadioEntryCopy(
    id=str(payload.get("id") or "station-intro"),
    text=text,
    displayText=display_text,
    targetItemId=target_item_id,
    agent=str(payload.get("agent") or "entry_copy_agent"),
  )
  return {**state, "entryCopy": entry_copy, "diagnostics": diagnostics}


def validate_transition_copy(state: AgentState) -> dict[str, Any]:
  is_english = _is_english_request(state.get("request"))
  terminal = "." if is_english else "。"
  text_max_chars = ENGLISH_TRANSITION_TEXT_MAX_CHARS if is_english else TRANSITION_TEXT_MAX_CHARS
  diagnostics = list(state.get("diagnostics", []))
  payload = parse_generation(state.get("rawTransitionCopy"))
  if payload is None:
    diagnostics.append("Transition copy payload was not valid JSON; using deterministic bridges.")
    payload = mock_transition_payload(state)

  valid_pairs = valid_transition_pairs(state)
  raw_copies = payload.get("betweenTracks") if isinstance(payload.get("betweenTracks"), list) else []
  copies_by_pair: dict[tuple[str, str], RadioTransitionCopy] = {}
  seen_opening_keys: set[str] = set()

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

    if _contains_unverified_fact(text) or _contains_unverified_fact(display_text):
      diagnostics.append(
        f"Dropped transition copy with unverified factual claims: {pair[0]} -> {pair[1]}"
      )
      continue

    opening_key = _opening_key(text)
    if opening_key and opening_key in seen_opening_keys:
      diagnostics.append(
        f"Dropped repetitive transition opening: {pair[0]} -> {pair[1]}"
      )
      continue
    if opening_key:
      seen_opening_keys.add(opening_key)

    text = _clean_spoken_text(text, text_max_chars, terminal)
    display_text = _clean_display_text(display_text, TRANSITION_DISPLAY_MAX_CHARS, terminal)
    if not display_text:
      display_text = _clean_display_text(text, TRANSITION_DISPLAY_MAX_CHARS, terminal)
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


def _clean_spoken_text(text: str, max_chars: int, terminal: str = "。") -> str:
  cleaned = _normalize_text(text)
  cleaned = _limit_fillers(cleaned)
  return _trim_to_limit(cleaned, max_chars, terminal)


def _clean_display_text(text: str, max_chars: int, terminal: str = "。") -> str:
  cleaned = _normalize_text(text)
  for filler in SPOKEN_FILLERS:
    cleaned = cleaned.replace(filler, "")
  cleaned = cleaned.strip(" ，,。")
  return _trim_to_limit(cleaned, max_chars, terminal)


def _normalize_text(text: str) -> str:
  return re.sub(r"\s+", " ", text).strip()


def _limit_fillers(text: str) -> str:
  filler_matches: list[tuple[int, int]] = []
  for filler in SPOKEN_FILLERS:
    for match in re.finditer(re.escape(filler), text):
      filler_matches.append(match.span())
  if len(filler_matches) <= 1:
    return text

  filler_matches.sort()
  keep_start, keep_end = filler_matches[0]
  pieces: list[str] = []
  cursor = 0
  for start, end in filler_matches:
    pieces.append(text[cursor:start])
    if start == keep_start and end == keep_end:
      pieces.append(text[start:end])
    cursor = end
  pieces.append(text[cursor:])
  return _normalize_text("".join(pieces))


def _trim_to_limit(text: str, max_chars: int, terminal: str = "。") -> str:
  if len(text) <= max_chars:
    return text

  clipped = text[:max_chars].rstrip(" ，,、；;：:")
  sentence_end = max(
    clipped.rfind("。"),
    clipped.rfind("！"),
    clipped.rfind("？"),
    clipped.rfind("."),
    clipped.rfind("!"),
    clipped.rfind("?"),
  )
  if sentence_end >= max(12, int(max_chars * 0.45)):
    return clipped[: sentence_end + 1].strip()
  return clipped.rstrip("。.!！?？") + terminal


def _is_english_request(request: Any) -> bool:
  speech_language = getattr(request, "speechLanguage", "")
  return str(speech_language).strip().lower().startswith("en")


def _contains_unverified_fact(text: str) -> bool:
  lowered = text.lower()
  return any(re.search(pattern, lowered) for pattern in UNVERIFIED_FACT_PATTERNS)


def _opening_key(text: str) -> str:
  cleaned = _normalize_text(text).lower()
  cleaned = re.sub(r"^[嗯呃啊好,\s，。.!！?？]+", "", cleaned)
  if not cleaned:
    return ""
  if re.match(r"^(next up|coming up|from |接下来|下一首|刚才|刚刚|从)", cleaned):
    return cleaned[:16]
  words = cleaned.split()
  if len(words) >= 4:
    return " ".join(words[:4])
  return cleaned[:12] if len(cleaned) >= 12 else ""


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
