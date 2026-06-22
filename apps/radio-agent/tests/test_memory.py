from radio_agent.memory import compress_memory_deterministically, compress_radio_memory
from radio_agent.schemas import (
  RadioMemoryCompressionRequest,
  RadioMemoryContext,
  RadioMemoryEvent,
)


def test_deterministic_memory_compression_merges_and_limits_values():
  request = RadioMemoryCompressionRequest(
    existingSummary=RadioMemoryContext(
      tasteSummary="Likes intimate pop.",
      avoidSummary="Avoid brittle noise.",
      likedArtistsTop=["Existing Artist"],
      skippedMoodsTop=["Harsh"],
      pinnedNotes=["Night mode.", "Keep vocals warm."],
    ),
    newEvents=[
      RadioMemoryEvent(type="like", artist="WRABEL", mood="Pop"),
      RadioMemoryEvent(type="replay", artist="WRABEL", mood="Pop"),
      RadioMemoryEvent(type="skip", artist="Artist B", mood="High Energy"),
    ],
    pinnedNotes=[
      "Keep vocals warm.",
      *[f"Note {index}" for index in range(1, 20)],
    ],
  )

  proposal = compress_memory_deterministically(request)

  assert proposal.likedArtistsTop[:2] == ["WRABEL", "Existing Artist"]
  assert proposal.skippedMoodsTop[:2] == ["High Energy", "Harsh"]
  assert proposal.tasteSummary.startswith("Likes intimate pop.")
  assert "Recent positive listening signals lean toward WRABEL" in proposal.tasteSummary
  assert proposal.avoidSummary.startswith("Avoid brittle noise.")
  assert len(proposal.pinnedNotes) == 20
  assert proposal.pinnedNotes[:3] == ["Night mode.", "Keep vocals warm.", "Note 1"]


def test_memory_compression_llm_failure_falls_back_to_deterministic(monkeypatch):
  monkeypatch.setenv("OPENAI_API_KEY", "test-key")

  def fail_compression(_request):
    raise ValueError("bad json")

  monkeypatch.setattr("radio_agent.memory.compress_memory_with_llm", fail_compression)
  request = RadioMemoryCompressionRequest(
    newEvents=[RadioMemoryEvent(type="like", artist="WRABEL", mood="Pop")]
  )

  response = compress_radio_memory(request)

  assert response.compressedMemoryProposal.likedArtistsTop == ["WRABEL"]
  assert "LLM memory compression failed: bad json" in response.diagnostics
  assert "Using deterministic memory compression." in response.diagnostics
