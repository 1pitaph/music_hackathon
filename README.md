# Music Hackathon

Monorepo for an iOS-first music app.

## Apps

- `apps/ios`: SwiftUI iOS app scaffold with MusicKit authorization, AVFoundation playback wiring, and a four-tab shell.
- `apps/radio-agent`: FastAPI + LangGraph radio generation service used by the iOS radio flow in debug builds.

## Recommended Direction

- iOS client: SwiftUI, AVFoundation, MediaPlayer, MusicKit, StoreKit, SwiftData.
- Web/admin later: React or Next.js in `apps/admin-web`.
- Shared contracts later: OpenAPI or generated API clients in `packages/contracts`.

## iOS

Open `apps/ios/MusicHackathon.xcodeproj` in Xcode, or build from the command line:

```sh
xcodebuild \
  -project apps/ios/MusicHackathon.xcodeproj \
  -scheme MusicHackathon \
  -destination 'generic/platform=iOS Simulator' \
  build
```

## Radio Agent

Run the LangGraph radio agent locally:

```sh
cd apps/radio-agent
python3 -m venv .venv
. .venv/bin/activate
pip install -e ".[test]"
cp .env.example .env
uvicorn radio_agent.api:app --reload --port 8000
```

Without `OPENAI_API_KEY`, the service uses deterministic mock generation. Set `OPENAI_API_KEY`, `OPENAI_BASE_URL`, and `OPENAI_MODEL` in `.env` to use an OpenAI-compatible model provider. `OPENAI_TIMEOUT_SECONDS` controls the model request timeout and defaults to 60 seconds.

Run backend tests:

```sh
cd apps/radio-agent
pytest
```

### Railway deployment

Create a Railway service from this GitHub repository and point it at the backend app:

- Root Directory: `/apps/radio-agent`
- Config File: `/apps/radio-agent/railway.json`
- Watch Paths: `/apps/radio-agent/**`

Railway builds the service from `apps/radio-agent/Dockerfile`, starts it with `sh ./start.sh`, and uses `/` as its health check path. `OPENAI_API_KEY` is optional; without it, the agent returns deterministic mock recommendations.

### Local-first radio memory

The iOS app keeps Airset radio memory on device in Application Support as `memory.json` plus a generated, user-readable `memory.md`. The backend does not persist raw memory. When the app generates a station, it sends a trimmed structured memory context with playable candidate tracks to:

```sh
POST /v1/radio/stations/generate
```

The backend returns an iOS-ready station payload with track reasons and optional memory patch proposals. When local memory has enough new events to compact, the app can request a backend compression proposal:

```sh
POST /v1/radio/memory/compress
```

The app owns the final write back to local memory; model output is treated as a proposal, not a direct write.
