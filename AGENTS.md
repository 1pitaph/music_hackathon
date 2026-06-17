# Repository Guidelines

## Project Structure & Module Organization

This is an iOS-first monorepo.

- `apps/ios/MusicHackathon.xcodeproj`: Xcode project; scheme is `MusicHackathon`.
- `apps/ios/MusicHackathon/App`: entry point, tab shell, and navigation.
- `apps/ios/MusicHackathon/Features`: SwiftUI screens grouped by area: `Discover`, `Library`, `Player`, and `Settings`.
- `apps/ios/MusicHackathon/Models`: domain models and fixture data.
- `apps/ios/MusicHackathon/Services`: playback and MusicKit authorization.
- `apps/ios/MusicHackathon/Resources`: `Info.plist` and permissions.

Future apps should follow `apps/<name>`; shared contracts belong in `packages/`.

## Build, Test, and Development Commands

- `open apps/ios/MusicHackathon.xcodeproj`: open the iOS app in Xcode.
- `xcodebuild -project apps/ios/MusicHackathon.xcodeproj -scheme MusicHackathon -destination 'generic/platform=iOS Simulator' build`: build the app from the command line.
- `xcrun simctl terminate booted com.pitaph.music-hackathon && xcrun simctl launch booted com.pitaph.music-hackathon`: restart the installed Simulator app after code changes.

There is no test target yet. Add one before relying on `xcodebuild test` in CI.

## iOS Platform Priorities & Simulator Verification

After every code update, rebuild as needed and restart the app in an iOS Simulator before handoff. If it is not installed, run it from Xcode first.

Prefer iOS 26 capabilities for new UI and platform integrations when they improve the product. The project currently declares `IPHONEOS_DEPLOYMENT_TARGET = 17.0`, so guard iOS 26-only APIs with `@available(iOS 26.0, *)` and add fallbacks unless the target is intentionally raised.

## SwiftUI Navigation & Tab Bar Decisions

Preserve system navigation containers unless the user explicitly asks to replace them. In particular, keep the app shell based on SwiftUI `TabView` and `.tabItem` when changing tab content or visual styling.

Do not replace a system `TabView` with a hand-rolled selected-state switch plus custom buttons just to match a screenshot. First try to achieve the requested UI by evolving the existing `TabView`, using system tab bar APIs, iOS 26 tab bar behavior, toolbar/background customization, or bottom accessories where appropriate.

If a fully custom tab bar is truly necessary, state the tradeoff before implementing it: custom bars can lose native tab lifecycle behavior, accessibility defaults, platform styling, iOS 26 system tab bar appearance, and future OS improvements.

Treat screenshots as visual direction, not permission to rewrite navigation architecture. Separate content surface changes from app shell changes, and keep app shell changes minimal and explicit.

## Coding Style & Naming Conventions

Use Swift and SwiftUI conventions already present in the project. Indent Swift files with two spaces. Name types in `PascalCase`, properties and functions in `camelCase`, and keep feature views inside their feature folder. Prefer small SwiftUI views, private helper views, and environment-based dependency injection. Use descriptive names such as `PlaybackController` and `MusicAuthorizationService`.

## Testing Guidelines

When adding tests, create `apps/ios/MusicHackathonTests` for unit tests and `apps/ios/MusicHackathonUITests` for flows. Name files after the subject, for example `PlaybackControllerTests.swift`. Keep test fixtures out of production `Models`.

Prioritize tests for playback state transitions, authorization handling, and model transformations before snapshot or UI tests.

## Commit & Pull Request Guidelines

History uses Conventional Commit-style prefixes, including `feat(ios): ...` and `chore: ...`. Keep commits focused and use an imperative summary.

Pull requests should include a short description, commands run, and screenshots or recordings for UI changes. Link issues when relevant, and call out MusicKit, AVFoundation, entitlement, or permission changes.

## Security & Configuration Tips

Do not commit secrets, API keys, provisioning profiles, or private streaming URLs. Keep platform permissions in `Resources/Info.plist` intentional and documented in the PR when they change.
