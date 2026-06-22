from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


class RadioTuning(BaseModel):
  discoveryRatio: float = Field(default=0.3, ge=0, le=1)
  familiarity: float = Field(default=0.7, ge=0, le=1)
  energy: float = Field(default=0.5, ge=0, le=1)


class RadioMemory(BaseModel):
  recentlyPlayedTrackKeys: list[str] = Field(default_factory=list)
  likedTrackKeys: list[str] = Field(default_factory=list)
  skippedTrackKeys: list[str] = Field(default_factory=list)
  dislikedTrackKeys: list[str] = Field(default_factory=list)


class RadioMemoryEvent(BaseModel):
  type: str
  trackKey: str | None = None
  title: str | None = None
  artist: str | None = None
  mood: str | None = None
  at: str | None = None


class RadioMemoryContext(BaseModel):
  tasteSummary: str = Field(default="", max_length=1600)
  avoidSummary: str = Field(default="", max_length=1200)
  likedArtistsTop: list[str] = Field(default_factory=list, max_length=20)
  skippedMoodsTop: list[str] = Field(default_factory=list, max_length=20)
  recentlyPlayedTrackKeys: list[str] = Field(default_factory=list, max_length=60)
  recentEvents: list[RadioMemoryEvent] = Field(default_factory=list, max_length=80)
  pinnedNotes: list[str] = Field(default_factory=list, max_length=20)


class RadioTrack(BaseModel):
  radioIdentity: str
  title: str
  artist: str
  album: str = ""
  mood: str = ""
  duration: float = 0
  artworkURL: str | None = None
  previewURL: str | None = None
  appleMusicID: str | None = None
  isExplicit: bool = False
  playlistName: str | None = None
  source: str | None = None
  sourceLane: str | None = None
  sourceScore: float | None = None
  reasonSignals: list[str] = Field(default_factory=list)


class RadioGenerateRequest(BaseModel):
  action: str = "start"
  tuning: RadioTuning = Field(default_factory=RadioTuning)
  seedTracks: list[RadioTrack] = Field(default_factory=list)
  catalogCandidates: list[RadioTrack] = Field(default_factory=list)
  memory: RadioMemory = Field(default_factory=RadioMemory)
  memoryContext: RadioMemoryContext = Field(default_factory=RadioMemoryContext)
  memoryMarkdown: str = Field(default="", max_length=12000)
  limit: int = Field(default=14, ge=1, le=40)


class RadioGeneratedItem(BaseModel):
  radioIdentity: str
  reason: str
  role: str
  score: float
  source: str


class RadioGenerateResponse(BaseModel):
  mode: Literal["llm", "mock", "fallback"]
  stationIntro: str
  items: list[RadioGeneratedItem]
  diagnostics: list[str] = Field(default_factory=list)


class RadioStationGenerateRequest(RadioGenerateRequest):
  stationID: str = "airset-personal"
  title: str = "Airset Radio"


class RadioStationItem(BaseModel):
  id: str
  title: str
  artist: str
  album: str = "Backend Radio"
  mood: str = "Radio"
  duration: float = 0
  artworkSystemName: str | None = None
  artworkURL: str | None = None
  previewURL: str | None = None
  appleMusicID: str | None = None
  isExplicit: bool = False
  sourceTitle: str = "Backend station"
  reason: str = "Queued by the backend station."


class RadioMemoryPatchProposal(BaseModel):
  op: Literal["upsert", "delete"] = "upsert"
  type: str
  text: str
  confidence: float = Field(default=0.5, ge=0, le=1)
  source: str = "radio-agent"


class RadioStationGenerateResponse(BaseModel):
  stationID: str
  title: str
  subtitle: str
  items: list[RadioStationItem]
  mode: Literal["llm", "mock", "fallback"]
  diagnostics: list[str] = Field(default_factory=list)
  memoryPatchProposals: list[RadioMemoryPatchProposal] = Field(default_factory=list)


class RadioMemoryCompressionRequest(BaseModel):
  existingSummary: RadioMemoryContext = Field(default_factory=RadioMemoryContext)
  newEvents: list[RadioMemoryEvent] = Field(default_factory=list, max_length=200)
  pinnedNotes: list[str] = Field(default_factory=list, max_length=20)
  maxOutputTokens: int = Field(default=500, ge=100, le=1200)


class RadioCompressedMemory(BaseModel):
  tasteSummary: str = ""
  avoidSummary: str = ""
  likedArtistsTop: list[str] = Field(default_factory=list)
  skippedMoodsTop: list[str] = Field(default_factory=list)
  pinnedNotes: list[str] = Field(default_factory=list)


class RadioMemoryCompressionResponse(BaseModel):
  compressedMemoryProposal: RadioCompressedMemory
  diagnostics: list[str] = Field(default_factory=list)
