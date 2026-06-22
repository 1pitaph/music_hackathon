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


class RadioTrack(BaseModel):
  radioIdentity: str
  title: str
  artist: str
  album: str = ""
  mood: str = ""
  duration: float = 0
  appleMusicID: str | None = None
  playlistName: str | None = None
  source: str | None = None


class RadioGenerateRequest(BaseModel):
  action: str = "start"
  tuning: RadioTuning = Field(default_factory=RadioTuning)
  seedTracks: list[RadioTrack] = Field(default_factory=list)
  catalogCandidates: list[RadioTrack] = Field(default_factory=list)
  memory: RadioMemory = Field(default_factory=RadioMemory)
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
