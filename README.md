# Music Hackathon

Monorepo for an iOS-first music app.

## Apps

- `apps/ios`: SwiftUI iOS app scaffold with MusicKit authorization, AVFoundation playback wiring, and a four-tab shell.

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
