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
  speechLanguage: Literal["zh-CN", "en-US"] = "zh-CN"


class RadioGeneratedItem(BaseModel):
  radioIdentity: str
  reason: str
  role: str
  score: float
  source: str


class RadioSpeechTimingWord(BaseModel):
  word: str
  startTime: float
  endTime: float
  confidence: float | None = None


class RadioSpeechCue(BaseModel):
  id: str
  text: str
  displayText: str
  startTime: float
  endTime: float
  words: list[RadioSpeechTimingWord] = Field(default_factory=list)


class RadioSpeechAudio(BaseModel):
  audioURL: str | None = None
  mimeType: str = "audio/mpeg"
  durationSeconds: float | None = None
  cacheKey: str
  voice: str
  model: str
  status: Literal["ready", "unavailable", "failed"] = "unavailable"
  cues: list[RadioSpeechCue] = Field(default_factory=list)


class RadioSpeechAudioConfig(BaseModel):
  enabled: bool = False
  provider: str = "openai"
  voice: str | None = None
  speaker: str | None = None
  resourceId: str | None = None
  model: str | None = None
  format: str = "mp3"
  speedRatio: float | None = Field(default=None, gt=0, le=3)
  volumeRatio: float | None = Field(default=None, gt=0, le=3)
  pitchRatio: float | None = Field(default=None, gt=0, le=3)
  sampleRate: int | None = Field(default=None, gt=0)
  bitRate: int | None = Field(default=None, gt=0)
  speechRate: int | None = Field(default=None, ge=-50, le=100)
  loudnessRate: int | None = Field(default=None, ge=-50, le=100)
  pitch: int | None = Field(default=None, ge=-12, le=12)
  language: str | None = None
  explicitLanguage: str | None = None
  emotion: str | None = None


class RadioSpeechVoice(BaseModel):
  id: str
  name: str
  language: str = "zh-cn"
  gender: str = ""
  style: str = ""
  resourceId: str = ""
  model: str = ""


class RadioSpeechVoiceCatalog(BaseModel):
  defaultSpeaker: str
  resourceId: str = "seed-tts-1.0"
  model: str = "seed-tts-1.0"
  voices: list[RadioSpeechVoice] = Field(default_factory=list)


class RadioEntryCopy(BaseModel):
  id: str = "station-intro"
  text: str
  displayText: str
  targetItemId: str | None = None
  agent: str = "entry_copy_agent"
  audio: RadioSpeechAudio | None = None


class RadioTransitionCopy(BaseModel):
  id: str
  fromItemId: str
  toItemId: str
  text: str
  displayText: str
  agent: str = "transition_copy_agent"
  audio: RadioSpeechAudio | None = None


class RadioSpeech(BaseModel):
  stationIntro: RadioEntryCopy | None = None
  betweenTracks: list[RadioTransitionCopy] = Field(default_factory=list)


class RadioGenerateResponse(BaseModel):
  mode: Literal["llm", "mock", "fallback"]
  stationIntro: str
  items: list[RadioGeneratedItem]
  speech: RadioSpeech | None = None
  diagnostics: list[str] = Field(default_factory=list)


class RadioStationGenerateRequest(RadioGenerateRequest):
  stationID: str = "airset-personal"
  title: str = "Airset Radio"
  speechAudio: RadioSpeechAudioConfig = Field(default_factory=RadioSpeechAudioConfig)


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
  source: str | None = None
  sourceLane: str | None = None
  reason: str = "Queued by the backend station."
  handoffText: str | None = None


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
  speech: RadioSpeech | None = None
  diagnostics: list[str] = Field(default_factory=list)
  memoryPatchProposals: list[RadioMemoryPatchProposal] = Field(default_factory=list)


class RadioSpeechSegment(BaseModel):
  id: str
  kind: Literal["stationIntro", "transition"]
  text: str
  displayText: str
  fromItemId: str | None = None
  toItemId: str | None = None
  targetItemId: str | None = None


class RadioSpeechSynthesisRequest(BaseModel):
  segments: list[RadioSpeechSegment] = Field(default_factory=list)
  speechAudio: RadioSpeechAudioConfig = Field(
    default_factory=lambda: RadioSpeechAudioConfig(enabled=True)
  )


class RadioSpeechSynthesisResult(RadioSpeechSegment):
  audio: RadioSpeechAudio


class RadioSpeechSynthesisResponse(BaseModel):
  segments: list[RadioSpeechSynthesisResult]
  diagnostics: list[str] = Field(default_factory=list)


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
