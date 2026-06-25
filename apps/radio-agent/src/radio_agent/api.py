from __future__ import annotations

import base64
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import sqlite3
from typing import Any
import uuid
from urllib.parse import urlparse

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, StreamingResponse

from radio_agent.graph import compress_radio_memory, generate_radio
from radio_agent.schemas import (
  DiscoverStationPage,
  DiscoverStationPublishRequest,
  DiscoverStationResponse,
  RadioGenerateRequest,
  RadioGenerateResponse,
  RadioMemoryCompressionRequest,
  RadioMemoryCompressionResponse,
  RadioMemoryPatchProposal,
  RadioSpeech,
  RadioSpeechAudioConfig,
  RadioSpeechSegment,
  RadioSpeechVoiceCatalog,
  RadioSpeechSynthesisRequest,
  RadioSpeechSynthesisResponse,
  RadioStationGenerateRequest,
  RadioStationGenerateResponse,
  RadioStationItem,
  RadioTrack,
)
from radio_agent.voices import speech_voice_catalog
from radio_agent.speech import (
  can_stream_speech_audio,
  ensure_speech_audio_file,
  speech_audio_mime_type,
  stream_speech_audio_file,
  synthesize_speech_segments,
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
  speech = generation.speech
  if speech and request.speechAudio.enabled:
    speech, speech_diagnostics = _speech_with_audio(
      speech,
      _speech_audio_config_for_request(request),
    )
    diagnostics.extend(speech_diagnostics)

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
    subtitle=speech.stationIntro.displayText if speech and speech.stationIntro else generation.stationIntro,
    items=items[: request.limit],
    mode=generation.mode,
    speech=speech,
    diagnostics=diagnostics,
    memoryPatchProposals=_memory_patch_proposals(request),
  )


@app.post("/v1/discover/stations", response_model=DiscoverStationResponse)
def publish_discover_station(request: DiscoverStationPublishRequest) -> DiscoverStationResponse:
  _validate_publish_request(request)
  station_id = f"station-{uuid.uuid4().hex[:12]}"
  share_url = f"{_discover_public_base_url()}/stations/{station_id}"
  published_at = _timestamp_now()
  response = DiscoverStationResponse(
    stationID=station_id,
    title=request.title.strip(),
    subtitle=request.subtitle.strip(),
    description=(request.description or request.subtitle or "").strip(),
    visibility=request.visibility,
    ownerID=request.ownerID.strip(),
    ownerDisplayName=request.ownerDisplayName.strip(),
    publishedAt=published_at,
    shareURL=share_url,
    seedTracks=request.seedTracks,
    items=request.items,
    speech=request.speech,
    coverArtworkURL=_trimmed_or_none(request.coverArtworkURL) or _first_artwork_url(request),
    colorHex=_trimmed_or_none(request.colorHex) or "#D8633C",
  )
  _save_discover_station(response)
  return response


@app.get("/v1/discover/stations", response_model=DiscoverStationPage)
def discover_stations(cursor: str | None = None, limit: int = 20) -> DiscoverStationPage:
  return _discover_station_page(cursor=cursor, limit=limit)


@app.get("/v1/radio/stations/{station_id}", response_model=DiscoverStationResponse)
def station_by_id(station_id: str) -> DiscoverStationResponse:
  station = _load_discover_station(station_id)
  if station is None or station.visibility == "private":
    raise HTTPException(status_code=404, detail="Station not found.")
  return station


@app.post("/v1/radio/generate", response_model=RadioGenerateResponse)
def generate(request: RadioGenerateRequest) -> RadioGenerateResponse:
  return generate_radio(request)


@app.post("/v1/radio/speech/synthesize", response_model=RadioSpeechSynthesisResponse)
def synthesize_speech(request: RadioSpeechSynthesisRequest) -> RadioSpeechSynthesisResponse:
  results, diagnostics = synthesize_speech_segments(request.segments, request.speechAudio)
  return RadioSpeechSynthesisResponse(segments=results, diagnostics=diagnostics)


@app.get("/v1/radio/speech/voices", response_model=RadioSpeechVoiceCatalog)
def speech_voices() -> RadioSpeechVoiceCatalog:
  return speech_voice_catalog()


@app.get("/v1/radio/speech/audio/{file_name}")
def speech_audio_file(file_name: str) -> FileResponse:
  file_path = ensure_speech_audio_file(file_name)
  if not file_path or not file_path.is_file():
    raise HTTPException(status_code=404, detail="Speech audio not found.")

  return FileResponse(
    file_path,
    media_type=speech_audio_mime_type(file_name),
    filename=file_name,
  )


@app.get("/v1/radio/speech/stream/{file_name}")
def speech_audio_stream(file_name: str) -> StreamingResponse:
  if not can_stream_speech_audio(file_name):
    raise HTTPException(status_code=404, detail="Speech audio stream not found.")

  return StreamingResponse(
    stream_speech_audio_file(file_name),
    media_type=speech_audio_mime_type(file_name),
  )


@app.post("/v1/radio/memory/compress", response_model=RadioMemoryCompressionResponse)
def compress_memory(request: RadioMemoryCompressionRequest) -> RadioMemoryCompressionResponse:
  return compress_radio_memory(request)


def _validate_publish_request(request: DiscoverStationPublishRequest) -> None:
  seed_keys = [track.radioIdentity for track in request.seedTracks]
  if len(set(seed_keys)) != 5:
    raise HTTPException(status_code=422, detail="seedTracks must contain exactly 5 unique tracks.")

  if not request.items:
    raise HTTPException(status_code=422, detail="items must contain at least one station item.")


def _discover_station_page(cursor: str | None, limit: int) -> DiscoverStationPage:
  page_size = min(max(limit, 1), 40)
  cursor_value = _decode_discover_cursor(cursor)
  connection = _discover_db_connection()
  try:
    _ensure_discover_schema(connection)
    if cursor_value is None:
      rows = connection.execute(
        """
        SELECT payload_json FROM discover_stations
        WHERE visibility = 'public'
        ORDER BY published_at DESC, station_id DESC
        LIMIT ?
        """,
        (page_size + 1,),
      ).fetchall()
    else:
      published_at, station_id = cursor_value
      rows = connection.execute(
        """
        SELECT payload_json FROM discover_stations
        WHERE visibility = 'public'
          AND (published_at < ? OR (published_at = ? AND station_id < ?))
        ORDER BY published_at DESC, station_id DESC
        LIMIT ?
        """,
        (published_at, published_at, station_id, page_size + 1),
      ).fetchall()
  finally:
    connection.close()

  stations = [_station_from_payload_json(row["payload_json"]) for row in rows[:page_size]]
  next_cursor = None
  if len(rows) > page_size and stations:
    last_station = stations[-1]
    next_cursor = _encode_discover_cursor(last_station.publishedAt, last_station.stationID)
  return DiscoverStationPage(stations=stations, nextCursor=next_cursor)


def _save_discover_station(station: DiscoverStationResponse) -> None:
  connection = _discover_db_connection()
  try:
    _ensure_discover_schema(connection)
    connection.execute(
      """
      INSERT INTO discover_stations (
        station_id,
        visibility,
        owner_id,
        owner_display_name,
        published_at,
        share_url,
        payload_json
      )
      VALUES (?, ?, ?, ?, ?, ?, ?)
      """,
      (
        station.stationID,
        station.visibility,
        station.ownerID,
        station.ownerDisplayName,
        station.publishedAt,
        station.shareURL,
        json.dumps(station.model_dump(mode="json"), ensure_ascii=False),
      ),
    )
    connection.commit()
  finally:
    connection.close()


def _load_discover_station(station_id: str) -> DiscoverStationResponse | None:
  connection = _discover_db_connection()
  try:
    _ensure_discover_schema(connection)
    row = connection.execute(
      "SELECT payload_json FROM discover_stations WHERE station_id = ?",
      (station_id,),
    ).fetchone()
  finally:
    connection.close()

  if row is None:
    return None
  return _station_from_payload_json(row["payload_json"])


def _station_from_payload_json(payload_json: str) -> DiscoverStationResponse:
  payload: dict[str, Any] = json.loads(payload_json)
  return DiscoverStationResponse.model_validate(payload)


def _discover_db_connection() -> sqlite3.Connection:
  db_path = _discover_db_path()
  if db_path != ":memory:":
    Path(db_path).parent.mkdir(parents=True, exist_ok=True)
  connection = sqlite3.connect(db_path)
  connection.row_factory = sqlite3.Row
  return connection


def _discover_db_path() -> str:
  return os.getenv("DISCOVER_STATIONS_DB_PATH", "/data/airset-discover.sqlite3")


def _ensure_discover_schema(connection: sqlite3.Connection) -> None:
  connection.execute(
    """
    CREATE TABLE IF NOT EXISTS discover_stations (
      station_id TEXT PRIMARY KEY,
      visibility TEXT NOT NULL,
      owner_id TEXT NOT NULL,
      owner_display_name TEXT NOT NULL,
      published_at TEXT NOT NULL,
      share_url TEXT NOT NULL,
      payload_json TEXT NOT NULL
    )
    """
  )
  connection.execute(
    """
    CREATE INDEX IF NOT EXISTS idx_discover_public_feed
    ON discover_stations (visibility, published_at DESC, station_id DESC)
    """
  )
  connection.commit()


def _discover_public_base_url() -> str:
  raw_value = (
    os.getenv("DISCOVER_STATIONS_PUBLIC_BASE_URL")
    or os.getenv("PUBLIC_BASE_URL")
    or "https://airset.example"
  )
  return raw_value.rstrip("/")


def _timestamp_now() -> str:
  return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _encode_discover_cursor(published_at: str, station_id: str) -> str:
  payload = json.dumps({"publishedAt": published_at, "stationID": station_id}, separators=(",", ":"))
  return base64.urlsafe_b64encode(payload.encode("utf-8")).decode("ascii").rstrip("=")


def _decode_discover_cursor(cursor: str | None) -> tuple[str, str] | None:
  if not cursor:
    return None

  try:
    padding = "=" * (-len(cursor) % 4)
    payload = json.loads(base64.urlsafe_b64decode(f"{cursor}{padding}").decode("utf-8"))
    published_at = payload["publishedAt"]
    station_id = payload["stationID"]
    if not isinstance(published_at, str) or not isinstance(station_id, str):
      raise ValueError("Invalid cursor values.")
    return published_at, station_id
  except Exception as exc:
    raise HTTPException(status_code=400, detail="Invalid discover cursor.") from exc


def _first_artwork_url(request: DiscoverStationPublishRequest) -> str | None:
  for item in request.items:
    if _trimmed_or_none(item.artworkURL):
      return item.artworkURL
  for track in request.seedTracks:
    if _trimmed_or_none(track.artworkURL):
      return track.artworkURL
  return None


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
  source_title = (
    _trimmed_or_none(track.playlistName)
    or _trimmed_or_none(track.sourceLane)
    or _trimmed_or_none(source)
    or _trimmed_or_none(track.source)
    or "Backend station"
  )
  return RadioStationItem(
    id=track.radioIdentity,
    title=track.title,
    artist=track.artist,
    album=track.album or "Backend Radio",
    mood=track.mood or "Radio",
    duration=track.duration,
    artworkURL=track.artworkURL,
    previewURL=_playable_preview_url(track.previewURL),
    appleMusicID=_trimmed_or_none(track.appleMusicID),
    isExplicit=track.isExplicit,
    sourceTitle=source_title,
    source=_trimmed_or_none(track.source) or _trimmed_or_none(source),
    sourceLane=_trimmed_or_none(track.sourceLane),
    reason=reason,
    handoffText=handoff_text,
  )


def _is_playable(track: RadioTrack) -> bool:
  return bool(_trimmed_or_none(track.appleMusicID) or _playable_preview_url(track.previewURL))


def _trimmed_or_none(value: str | None) -> str | None:
  if value is None:
    return None
  cleaned = value.strip()
  return cleaned or None


def _playable_preview_url(value: str | None) -> str | None:
  cleaned = _trimmed_or_none(value)
  if not cleaned:
    return None

  parsed = urlparse(cleaned)
  if parsed.scheme not in {"http", "https"} or not parsed.netloc:
    return None

  return cleaned


def _speech_with_audio(
  speech: RadioSpeech,
  config: RadioSpeechAudioConfig,
) -> tuple[RadioSpeech, list[str]]:
  segments = _speech_segments(speech)
  results, diagnostics = synthesize_speech_segments(segments, config)
  audio_by_id = {result.id: result.audio for result in results}

  station_intro = speech.stationIntro
  if station_intro and station_intro.id in audio_by_id:
    station_intro = station_intro.model_copy(update={"audio": audio_by_id[station_intro.id]})

  between_tracks = [
    copy.model_copy(update={"audio": audio_by_id[copy.id]})
    if copy.id in audio_by_id else copy
    for copy in speech.betweenTracks
  ]
  return speech.model_copy(update={
    "stationIntro": station_intro,
    "betweenTracks": between_tracks,
  }), diagnostics


def _speech_audio_config_for_request(
  request: RadioStationGenerateRequest,
) -> RadioSpeechAudioConfig:
  if request.speechAudio.explicitLanguage:
    return request.speechAudio
  return request.speechAudio.model_copy(update={"explicitLanguage": request.speechLanguage})


def _speech_segments(speech: RadioSpeech) -> list[RadioSpeechSegment]:
  segments: list[RadioSpeechSegment] = []
  if speech.stationIntro:
    segments.append(RadioSpeechSegment(
      id=speech.stationIntro.id,
      kind="stationIntro",
      text=speech.stationIntro.text,
      displayText=speech.stationIntro.displayText,
      targetItemId=speech.stationIntro.targetItemId,
    ))

  for copy in speech.betweenTracks:
    segments.append(RadioSpeechSegment(
      id=copy.id,
      kind="transition",
      text=copy.text,
      displayText=copy.displayText,
      fromItemId=copy.fromItemId,
      toItemId=copy.toItemId,
    ))
  return segments


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
