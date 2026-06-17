# MusicHackathon iOS

SwiftUI scaffold for the music app.

## Structure

- `App`: app entry point, tab shell, routing primitives.
- `Features`: user-facing screens split by product area.
- `Models`: lightweight domain models and fixture data.
- `Services`: app services for playback and MusicKit authorization.
- `Resources`: app `Info.plist` and platform permissions.

## Current Scope

The scaffold is intentionally small but wired around the real music-app surface:

- Discover tab with fixture tracks.
- Library tab with placeholder playlist rows.
- Player tab connected to a shared playback controller.
- Settings tab with MusicKit authorization status and app capability notes.
- Playback controller prepared for `AVAudioSession`, `AVPlayer`, Now Playing metadata, and remote command center.

Actual streaming URLs, backend API clients, StoreKit subscriptions, and persistence should be added after the product MVP path is chosen.
