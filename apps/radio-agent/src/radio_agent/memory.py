from __future__ import annotations

from radio_agent.llm import has_openai_api_key, invoke_chat
from radio_agent.prompts import memory_compression_system_prompt, memory_compression_user_prompt
from radio_agent.repair import parse_generation
from radio_agent.schemas import (
  RadioCompressedMemory,
  RadioMemoryCompressionRequest,
  RadioMemoryCompressionResponse,
)


def compress_radio_memory(request: RadioMemoryCompressionRequest) -> RadioMemoryCompressionResponse:
  diagnostics: list[str] = []
  if has_openai_api_key():
    try:
      proposal = compress_memory_with_llm(request)
      return RadioMemoryCompressionResponse(compressedMemoryProposal=proposal, diagnostics=diagnostics)
    except Exception as error:  # pragma: no cover - network failures are environment-specific.
      diagnostics.append(f"LLM memory compression failed: {error}")

  diagnostics.append("Using deterministic memory compression.")
  return RadioMemoryCompressionResponse(
    compressedMemoryProposal=compress_memory_deterministically(request),
    diagnostics=diagnostics,
  )


def compress_memory_with_llm(request: RadioMemoryCompressionRequest) -> RadioCompressedMemory:
  result = invoke_chat(
    memory_compression_system_prompt(),
    memory_compression_user_prompt(request),
    temperature=0.2,
  )
  parsed = parse_generation(str(result))
  if parsed is None:
    raise ValueError("Memory compression payload was not valid JSON.")
  return RadioCompressedMemory.model_validate(parsed)


def compress_memory_deterministically(request: RadioMemoryCompressionRequest) -> RadioCompressedMemory:
  liked_artists = ranked_event_values(
    request,
    event_types={"like", "complete", "play", "replay"},
    attr="artist",
    seed_values=request.existingSummary.likedArtistsTop,
  )
  skipped_moods = ranked_event_values(
    request,
    event_types={"skip", "dislike"},
    attr="mood",
    seed_values=request.existingSummary.skippedMoodsTop,
  )

  taste_summary = request.existingSummary.tasteSummary.strip()
  if liked_artists:
    artist_text = ", ".join(liked_artists[:5])
    taste_summary = merge_summary(taste_summary, f"Recent positive listening signals lean toward {artist_text}.")

  avoid_summary = request.existingSummary.avoidSummary.strip()
  if skipped_moods:
    mood_text = ", ".join(skipped_moods[:5])
    avoid_summary = merge_summary(avoid_summary, f"Recent skips suggest reducing {mood_text}.")

  pinned_notes = list(dict.fromkeys([*request.existingSummary.pinnedNotes, *request.pinnedNotes]))[:20]
  return RadioCompressedMemory(
    tasteSummary=taste_summary,
    avoidSummary=avoid_summary,
    likedArtistsTop=liked_artists[:12],
    skippedMoodsTop=skipped_moods[:12],
    pinnedNotes=pinned_notes,
  )


def ranked_event_values(
  request: RadioMemoryCompressionRequest,
  *,
  event_types: set[str],
  attr: str,
  seed_values: list[str],
) -> list[str]:
  scores: dict[str, int] = {value: max(1, len(seed_values) - index) for index, value in enumerate(seed_values)}
  for event in request.newEvents:
    if event.type not in event_types:
      continue
    value = getattr(event, attr)
    if not value:
      continue
    scores[value] = scores.get(value, 0) + 3

  return [
    value
    for value, _score in sorted(scores.items(), key=lambda item: (-item[1], item[0].casefold()))
  ]


def merge_summary(existing: str, addition: str) -> str:
  if not existing:
    return addition
  if addition in existing:
    return existing
  return f"{existing} {addition}"
