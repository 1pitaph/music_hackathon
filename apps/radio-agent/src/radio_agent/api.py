from __future__ import annotations

from fastapi import FastAPI

from radio_agent.graph import compress_radio_memory, generate_radio
from radio_agent.schemas import (
  RadioGenerateRequest,
  RadioGenerateResponse,
  RadioMemoryCompressionRequest,
  RadioMemoryCompressionResponse,
  RadioMemoryPatchProposal,
  RadioStationGenerateRequest,
  RadioStationGenerateResponse,
  RadioStationItem,
  RadioTrack,
)

app = FastAPI(title="Airset Radio Agent", version="0.1.0")

CURRENT_STATION = {
  "stationID": "airset-live",
  "title": "Airset Radio",
  "subtitle": "A backend-programmed preview queue from the Railway radio agent.",
  "items": [
    {
      "id": "wrabel-up-above",
      "title": "up above",
      "artist": "WRABEL",
      "album": "up up above",
      "mood": "Pop Surrealism",
      "duration": 210,
      "artworkURL": "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/9a/8a/0d/9a8a0d30-c5a8-1131-0a98-f3c6e3da82eb/067003255943.png/512x512bb.jpg",
      "previewURL": "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/64/79/0f/64790f4e-945b-dbec-62e9-51ddea0c782d/mzaf_5055537866043613116.plus.aac.p.m4a",
      "appleMusicID": "1879898104",
      "sourceTitle": "Railway station",
      "reason": "Opens with the bright title-track signal for the live backend queue.",
    },
    {
      "id": "wrabel-future",
      "title": "future",
      "artist": "WRABEL",
      "album": "up up above",
      "mood": "Glowing",
      "duration": 204,
      "artworkURL": "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/9a/8a/0d/9a8a0d30-c5a8-1131-0a98-f3c6e3da82eb/067003255943.png/512x512bb.jpg",
      "previewURL": "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/86/6d/82/866d820f-8c32-a173-525f-c3e109d7054b/mzaf_16084222939051357701.plus.aac.p.m4a",
      "appleMusicID": "1879898145",
      "sourceTitle": "Railway station",
      "reason": "Keeps the set moving with a clean pop lift and familiar artist thread.",
    },
    {
      "id": "wrabel-birds-bees",
      "title": "birds & the bees",
      "artist": "WRABEL",
      "album": "up up above",
      "mood": "Warm",
      "duration": 221,
      "artworkURL": "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/9a/8a/0d/9a8a0d30-c5a8-1131-0a98-f3c6e3da82eb/067003255943.png/512x512bb.jpg",
      "previewURL": "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/v4/bf/f1/2c/bff12c97-74a7-8d0e-1e30-f8709f8b184e/mzaf_13238801874770777058.plus.aac.p.m4a",
      "appleMusicID": "1879898163",
      "sourceTitle": "Railway station",
      "reason": "Adds a softer bridge before the queue turns upward again.",
    },
    {
      "id": "wrabel-move",
      "title": "move",
      "artist": "WRABEL",
      "album": "up up above",
      "mood": "Kinetic",
      "duration": 207,
      "artworkURL": "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/9a/8a/0d/9a8a0d30-c5a8-1131-0a98-f3c6e3da82eb/067003255943.png/512x512bb.jpg",
      "previewURL": "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/e5/bc/9b/e5bc9b5d-eb9c-4f3d-3f2b-80f68bf88f1a/mzaf_9247009263125251965.plus.aac.p.m4a",
      "appleMusicID": "1879898517",
      "sourceTitle": "Railway station",
      "reason": "Brings the energy back up for the next on-air handoff.",
    },
  ],
}


@app.get("/")
def root() -> dict[str, str]:
  return {"status": "ok", "service": "airset-radio-agent"}


@app.get("/healthz")
def healthz() -> dict[str, str]:
  return {"status": "ok"}


@app.get("/v1/radio/stations/current")
def current_station() -> dict:
  return CURRENT_STATION


@app.post("/v1/radio/stations/generate", response_model=RadioStationGenerateResponse)
def generate_station(request: RadioStationGenerateRequest) -> RadioStationGenerateResponse:
  generation = generate_radio(request)
  candidates = _candidate_map(request)
  items = _station_items_from_generation(generation, candidates)

  diagnostics = list(generation.diagnostics)
  if len(items) < request.limit:
    used = {item.id for item in items}
    for track in [*request.seedTracks, *request.catalogCandidates]:
      if track.radioIdentity in used or not _is_playable(track):
        continue
      items.append(_station_item(track, "Queued as a playable fallback from the candidate pool."))
      used.add(track.radioIdentity)
      if len(items) >= request.limit:
        break

  if not items:
    diagnostics.append("No playable generated items; returning the public preview station.")
    items = [RadioStationItem.model_validate(item) for item in CURRENT_STATION["items"]]

  return RadioStationGenerateResponse(
    stationID=request.stationID,
    title=request.title,
    subtitle=generation.speech.stationIntro.displayText if generation.speech and generation.speech.stationIntro else generation.stationIntro,
    items=items[: request.limit],
    mode=generation.mode,
    speech=generation.speech,
    diagnostics=diagnostics,
    memoryPatchProposals=_memory_patch_proposals(request),
  )


@app.post("/v1/radio/generate", response_model=RadioGenerateResponse)
def generate(request: RadioGenerateRequest) -> RadioGenerateResponse:
  return generate_radio(request)


@app.post("/v1/radio/memory/compress", response_model=RadioMemoryCompressionResponse)
def compress_memory(request: RadioMemoryCompressionRequest) -> RadioMemoryCompressionResponse:
  return compress_radio_memory(request)


def _candidate_map(request: RadioStationGenerateRequest) -> dict[str, RadioTrack]:
  candidates: dict[str, RadioTrack] = {}
  for track in [*request.seedTracks, *request.catalogCandidates]:
    candidates.setdefault(track.radioIdentity, track)
  return candidates


def _station_items_from_generation(
  generation: RadioGenerateResponse,
  candidates: dict[str, RadioTrack],
) -> list[RadioStationItem]:
  items: list[RadioStationItem] = []
  used: set[str] = set()
  handoff_by_to_item = {
    copy.toItemId: copy.displayText
    for copy in (generation.speech.betweenTracks if generation.speech else [])
  }
  for generated_item in generation.items:
    if generated_item.radioIdentity in used:
      continue
    track = candidates.get(generated_item.radioIdentity)
    if track is None or not _is_playable(track):
      continue
    used.add(generated_item.radioIdentity)
    items.append(_station_item(
      track,
      generated_item.reason,
      generated_item.source,
      handoff_by_to_item.get(generated_item.radioIdentity),
    ))
  return items


def _station_item(
  track: RadioTrack,
  reason: str,
  source: str | None = None,
  handoff_text: str | None = None,
) -> RadioStationItem:
  return RadioStationItem(
    id=track.radioIdentity,
    title=track.title,
    artist=track.artist,
    album=track.album or "Backend Radio",
    mood=track.mood or "Radio",
    duration=track.duration,
    artworkURL=track.artworkURL,
    previewURL=track.previewURL,
    appleMusicID=track.appleMusicID,
    isExplicit=track.isExplicit,
    sourceTitle=track.playlistName or track.sourceLane or source or track.source or "Backend station",
    reason=reason,
    handoffText=handoff_text,
  )


def _is_playable(track: RadioTrack) -> bool:
  return bool(track.appleMusicID or track.previewURL)


def _memory_patch_proposals(request: RadioStationGenerateRequest) -> list[RadioMemoryPatchProposal]:
  if request.memoryContext.tasteSummary or request.memoryContext.likedArtistsTop:
    return []

  seed_artists = list(dict.fromkeys(track.artist for track in request.seedTracks if track.artist))
  if not seed_artists:
    return []

  return [
    RadioMemoryPatchProposal(
      type="taste",
      text=f"User is starting radio sessions from {', '.join(seed_artists[:3])}.",
      confidence=0.35,
      source="radio_generation",
    )
  ]
