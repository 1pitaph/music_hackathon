from __future__ import annotations

import os
from typing import Any, TypedDict

from langgraph.graph import END, START, StateGraph

from radio_agent.fallbacks import mock_entry_payload, mock_payload, mock_transition_payload
from radio_agent.llm import has_openai_api_key, invoke_chat
from radio_agent.memory import compress_radio_memory
from radio_agent.prompts import (
  entry_copy_system_prompt,
  entry_copy_user_prompt,
  recommendation_system_prompt,
  recommendation_user_prompt,
  station_program_system_prompt,
  station_program_user_prompt,
  transition_copy_system_prompt,
  transition_copy_user_prompt,
)
from radio_agent.repair import (
  assemble_response,
  finalize_response,
  validate_and_repair,
  validate_entry_copy,
  validate_recommendations,
  validate_station_program,
  validate_transition_copy,
)
from radio_agent.schemas import (
  RadioEntryCopy,
  RadioGenerateRequest,
  RadioGenerateResponse,
  RadioGeneratedItem,
  RadioTrack,
  RadioTransitionCopy,
)
from radio_agent.state_helpers import trim_memory_markdown


class RadioAgentState(TypedDict, total=False):
  request: RadioGenerateRequest
  candidates: list[RadioTrack]
  candidateByID: dict[str, RadioTrack]
  diagnostics: list[str]
  mode: str
  generationPath: str
  sharedMemory: dict[str, Any]
  rawGeneration: str | dict[str, Any] | None
  rawRecommendation: str | dict[str, Any] | None
  rawProgram: str | dict[str, Any] | None
  recommendedItems: list[RadioGeneratedItem]
  rawEntryCopy: str | dict[str, Any] | None
  entryCopy: RadioEntryCopy
  rawTransitionCopy: str | dict[str, Any] | None
  transitionCopies: list[RadioTransitionCopy]
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


def build_shared_memory(state: RadioAgentState) -> RadioAgentState:
  request = state["request"]
  memory_context = request.memoryContext
  shared_memory = {
    "tasteSummary": memory_context.tasteSummary,
    "avoidSummary": memory_context.avoidSummary,
    "likedArtistsTop": memory_context.likedArtistsTop,
    "skippedMoodsTop": memory_context.skippedMoodsTop,
    "recentlyPlayedTrackKeys": memory_context.recentlyPlayedTrackKeys,
    "recentEvents": [event.model_dump() for event in memory_context.recentEvents],
    "pinnedNotes": memory_context.pinnedNotes,
    "memoryMarkdown": trim_memory_markdown(request.memoryMarkdown),
  }
  return {**state, "sharedMemory": shared_memory}


def choose_generation_path(state: RadioAgentState) -> RadioAgentState:
  diagnostics = list(state.get("diagnostics", []))
  if not state.get("candidates"):
    return {**state, "mode": "fallback", "generationPath": "fallback", "diagnostics": diagnostics}

  if has_openai_api_key():
    generation_path = "legacy_multi_agent" if _generation_mode() == "legacy_multi_agent" else "single_call"
    return {**state, "mode": "llm", "generationPath": generation_path, "diagnostics": diagnostics}

  diagnostics.append("OPENAI_API_KEY is not set; using deterministic mock generation.")
  return {**state, "mode": "mock", "generationPath": "mock", "diagnostics": diagnostics}


def _generation_mode() -> str:
  return os.getenv("RADIO_AGENT_GENERATION_MODE", "single_call").strip().lower()


def _generation_path(state: RadioAgentState) -> str:
  return state.get("generationPath") or state.get("mode", "fallback")


def station_program_agent(state: RadioAgentState) -> RadioAgentState:
  request = state["request"]
  diagnostics = list(state.get("diagnostics", []))

  try:
    content = invoke_chat(
      station_program_system_prompt(),
      station_program_user_prompt(request, state),
      temperature=0.5,
    )
    return {**state, "rawProgram": content, "diagnostics": diagnostics}
  except Exception as error:  # pragma: no cover - network failures are environment-specific.
    diagnostics.append(f"Station program agent failed: {error}")
    return {**state, "mode": "fallback", "rawProgram": None, "diagnostics": diagnostics}


def recommendation_agent(state: RadioAgentState) -> RadioAgentState:
  request = state["request"]
  diagnostics = list(state.get("diagnostics", []))

  try:
    content = invoke_chat(
      recommendation_system_prompt(),
      recommendation_user_prompt(request, state),
      temperature=0.5,
    )
    return {**state, "rawRecommendation": content, "diagnostics": diagnostics}
  except Exception as error:  # pragma: no cover - network failures are environment-specific.
    diagnostics.append(f"Recommendation agent failed: {error}")
    return {**state, "mode": "fallback", "rawRecommendation": None, "diagnostics": diagnostics}


def mock_recommendation(state: RadioAgentState) -> RadioAgentState:
  return {**state, "rawRecommendation": mock_payload(state), "mode": state.get("mode", "mock")}


def entry_copy_agent(state: RadioAgentState) -> RadioAgentState:
  if state.get("mode") == "llm" and has_openai_api_key():
    diagnostics = list(state.get("diagnostics", []))
    try:
      content = invoke_chat(
        entry_copy_system_prompt(),
        entry_copy_user_prompt(state),
        temperature=0.45,
      )
      return validate_entry_copy({**state, "rawEntryCopy": content, "diagnostics": diagnostics})
    except Exception as error:  # pragma: no cover - network failures are environment-specific.
      diagnostics.append(f"Entry copy agent failed: {error}")
      return validate_entry_copy({**state, "rawEntryCopy": None, "diagnostics": diagnostics})

  return validate_entry_copy({**state, "rawEntryCopy": mock_entry_payload(state)})


def transition_copy_agent(state: RadioAgentState) -> RadioAgentState:
  if state.get("mode") == "llm" and has_openai_api_key():
    diagnostics = list(state.get("diagnostics", []))
    try:
      content = invoke_chat(
        transition_copy_system_prompt(),
        transition_copy_user_prompt(state),
        temperature=0.55,
      )
      return validate_transition_copy({**state, "rawTransitionCopy": content, "diagnostics": diagnostics})
    except Exception as error:  # pragma: no cover - network failures are environment-specific.
      diagnostics.append(f"Transition copy agent failed: {error}")
      return validate_transition_copy({**state, "rawTransitionCopy": None, "diagnostics": diagnostics})

  return validate_transition_copy({**state, "rawTransitionCopy": mock_transition_payload(state)})


def build_graph():
  graph = StateGraph(RadioAgentState)
  graph.add_node("prepare_context", prepare_context)
  graph.add_node("build_shared_memory", build_shared_memory)
  graph.add_node("choose_generation_path", choose_generation_path)
  graph.add_node("station_program_agent", station_program_agent)
  graph.add_node("validate_station_program", validate_station_program)
  graph.add_node("recommendation_agent", recommendation_agent)
  graph.add_node("mock_recommendation", mock_recommendation)
  graph.add_node("validate_recommendations", validate_recommendations)
  graph.add_node("entry_copy_agent", entry_copy_agent)
  graph.add_node("transition_copy_agent", transition_copy_agent)
  graph.add_node("assemble_response", assemble_response)

  graph.add_edge(START, "prepare_context")
  graph.add_edge("prepare_context", "build_shared_memory")
  graph.add_edge("build_shared_memory", "choose_generation_path")
  graph.add_conditional_edges(
    "choose_generation_path",
    _generation_path,
    {
      "single_call": "station_program_agent",
      "legacy_multi_agent": "recommendation_agent",
      "mock": "mock_recommendation",
      "fallback": "validate_recommendations",
    },
  )
  graph.add_edge("station_program_agent", "validate_station_program")
  graph.add_edge("validate_station_program", END)
  graph.add_edge("recommendation_agent", "validate_recommendations")
  graph.add_edge("mock_recommendation", "validate_recommendations")
  graph.add_edge("validate_recommendations", "entry_copy_agent")
  graph.add_edge("entry_copy_agent", "transition_copy_agent")
  graph.add_edge("transition_copy_agent", "assemble_response")
  graph.add_edge("assemble_response", END)
  return graph.compile()


radio_graph = build_graph()


def generate_radio(request: RadioGenerateRequest) -> RadioGenerateResponse:
  result = radio_graph.invoke({"request": request, "diagnostics": []})
  return result["response"]
