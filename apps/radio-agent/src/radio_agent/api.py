from __future__ import annotations

from fastapi import FastAPI

from radio_agent.schemas import RadioGenerateRequest, RadioGenerateResponse

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


@app.post("/v1/radio/generate", response_model=RadioGenerateResponse)
def generate(request: RadioGenerateRequest) -> RadioGenerateResponse:
  from radio_agent.graph import generate_radio

  return generate_radio(request)
