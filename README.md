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

Without `OPENAI_API_KEY`, the service uses deterministic mock generation. Set `OPENAI_API_KEY`, `OPENAI_BASE_URL`, and `OPENAI_MODEL` in `.env` to use an OpenAI-compatible model provider.

Run backend tests:

```sh
cd apps/radio-agent
pytest
```
