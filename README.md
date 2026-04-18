# Second Brain

![Platform](https://img.shields.io/badge/platform-iOS%2026%2B%20%7C%20watchOS%2026%2B-0A84FF)
![Xcode](https://img.shields.io/badge/Xcode-26%2B-147EFB)
![AI](https://img.shields.io/badge/Apple%20Intelligence-on--device%20when%20available-5E5CE6)

Second Brain is the private development repository for a SwiftUI second-brain and note-taking app for iPhone and Apple Watch. It combines local note capture, transient voice input, note-aware search, App Intents, CloudKit sync, and on-device Apple Intelligence flows when available.

## Start Here

```bash
git clone https://github.com/ThalesMMS/Second-Brain-app.git
cd Second-Brain-app
open 2nd-Brain/2nd-Brain.xcodeproj
xcodebuild -list -project 2nd-Brain/2nd-Brain.xcodeproj
```

That gets you into the app workspace quickly and confirms the checked-in project and schemes are available on your machine.

## Related ThalesMMS Projects

- [Second-Brain-app](https://github.com/ThalesMMS/Second-Brain-app), the public AI note-taking iOS/watchOS app repository, or browse the [ThalesMMS](https://github.com/ThalesMMS) organization.

## Features

- Manual text notes with searchable titles and previews
- Voice capture that turns speech into note content or note-editing commands without persisting raw audio
- `Ask Notes` for note-aware Q&A and safe note editing
- Safe AI note edits with clarification or confirmation when the requested change is ambiguous or large
- App Intents for create, append, read, and ask flows
- Apple Watch companion app with recent notes, quick capture, and assistant access
- CloudKit-backed sync for note data across devices
- Watch-to-iPhone relay for assistant requests that require Apple Intelligence
- Watch-to-iPhone relay for voice-command routing that requires Apple Intelligence

## Tech Stack

- SwiftUI for iPhone and Apple Watch UI
- SwiftData for note persistence and history
- CloudKit for sync-ready storage
- App Intents for Siri and Shortcuts integration
- Foundation Models for on-device Apple Intelligence flows when supported
- Speech transcription/analysis for voice note capture
- WatchConnectivity for watch assistant relay

## Requirements

- Xcode 26 or newer
- iOS 26 or newer for Apple Intelligence-backed assistant and capture refinement
- A supported Apple Intelligence device/configuration for Foundation Models features
- Apple Developer signing if you want to run full device builds with iCloud/CloudKit enabled

## Setup

The Xcode project lives at:

```text
2nd-Brain/2nd-Brain.xcodeproj
```

Important capabilities already wired into the project:

- CloudKit container: `iCloud.thalesmms.secondbrain`
- App Group: `group.thalesmms.secondbrain`

These values are defined in the app settings/constants and entitlements. If you need to change them, update both the source constants and the corresponding entitlement files.

## Run / Build / Test

Open the project in Xcode or use the command line.

Available schemes:

- `SecondBrain`
- `SecondBrainWatch`
- `SecondBrainDomain`
- `SecondBrainPersistence`
- `SecondBrainAudio`
- `SecondBrainAI`
- `SecondBrainComposition`

Build the iPhone app:

```bash
xcodebuild -project 2nd-Brain/2nd-Brain.xcodeproj -scheme SecondBrain -destination 'generic/platform=iOS' build
```

Build the Apple Watch app for simulator:

```bash
xcodebuild -project 2nd-Brain/2nd-Brain.xcodeproj -scheme SecondBrainWatch -destination 'generic/platform=watchOS Simulator' build
```

Run the iOS unit tests:

```bash
SIM_DEST='platform=iOS Simulator,name=iPhone 17'
xcodebuild -project 2nd-Brain/2nd-Brain.xcodeproj -scheme SecondBrain -destination "$SIM_DEST" -only-testing:SecondBrainTests test
```

Record or verify the iPhone snapshot suite:

```bash
SIM_DEST='platform=iOS Simulator,name=iPhone 17,OS=26.4'
SNAPSHOT_SENTINEL='2nd-Brain/SecondBrainTests/.record_snapshots'
trap 'rm -f "$SNAPSHOT_SENTINEL"' EXIT
touch "$SNAPSHOT_SENTINEL"
xcodebuild -project 2nd-Brain/2nd-Brain.xcodeproj -scheme SecondBrain -destination "$SIM_DEST" -only-testing:SecondBrainTests/SecondBrainSnapshotTests test
rm -f "$SNAPSHOT_SENTINEL"
trap - EXIT
xcodebuild -project 2nd-Brain/2nd-Brain.xcodeproj -scheme SecondBrain -destination "$SIM_DEST" -only-testing:SecondBrainTests/SecondBrainSnapshotTests test
```

Snapshot notes:

- Snapshot baselines live under the default `__Snapshots__` folder next to the snapshot test file.
- Recording intentionally fails after refreshing the baselines; rerun the suite without `.record_snapshots` to verify the newly recorded images.
- The suite also honors `RECORD_SNAPSHOTS=1` or `SIMCTL_CHILD_RECORD_SNAPSHOTS=1`, but the checked-in workflow uses `.record_snapshots` so the behavior is explicit and reproducible.
- Verify on the same simulator family used to record them. This suite is pinned to `iPhone 17`, portrait, light mode, `en_US_POSIX`, UTC, and default Dynamic Type to reduce visual drift.

Run the package module tests:

```bash
SIM_DEST='platform=iOS Simulator,name=iPhone 17'
cd Packages/SecondBrainModules
xcodebuild -scheme SecondBrainModules-Package -destination "$SIM_DEST" test
xcodebuild -scheme SecondBrainModules-Package -destination "$SIM_DEST" -only-testing:SecondBrainDomainTests test
xcodebuild -scheme SecondBrainModules-Package -destination "$SIM_DEST" -only-testing:SecondBrainPersistenceTests test
xcodebuild -scheme SecondBrainModules-Package -destination "$SIM_DEST" -only-testing:SecondBrainAudioTests test
xcodebuild -scheme SecondBrainModules-Package -destination "$SIM_DEST" -only-testing:SecondBrainAITests test
```

## Project Structure

- `Packages/SecondBrainModules/Package.swift`: local Swift package declaration for the shared modules
- `Packages/SecondBrainModules/Sources/SecondBrainDomain/`: domain models, protocols, utilities, and use cases
- `Packages/SecondBrainModules/Sources/SecondBrainPersistence/`: SwiftData schema, migration plan, and repository implementation
- `Packages/SecondBrainModules/Sources/SecondBrainAudio/`: file storage, recording, speech transcription, and text-to-speech
- `Packages/SecondBrainModules/Sources/SecondBrainAI/`: deterministic assistant, Apple Intelligence services, and WatchConnectivity relay
- `Packages/SecondBrainModules/Sources/SecondBrainComposition/`: `AppGraph` composition root for app and watch entrypoints
- `2nd-Brain/SecondBrain/Features/Assistant/`: `Ask Notes` UI
- `2nd-Brain/SecondBrain/Features/Notes/`: note list, detail, and quick capture flows
- `2nd-Brain/SecondBrain/Intents/`: App Intents kept in the app target
- `2nd-Brain/SecondBrain/WatchSupport/`: watchOS entrypoints and watch-specific UI
- `2nd-Brain/SecondBrainTests/`: smoke and integration tests for app composition and App Intents
- `Packages/SecondBrainModules/Tests/`: module tests for domain, persistence, audio, and AI
- `2nd-Brain/SecondBrainUITests/`: UI tests

## Module Graph

- `SecondBrainDomain`
- `SecondBrainPersistence -> SecondBrainDomain`
- `SecondBrainAudio -> SecondBrainDomain`
- `SecondBrainAI -> SecondBrainDomain`
- `SecondBrainComposition -> SecondBrainDomain + SecondBrainPersistence + SecondBrainAudio + SecondBrainAI`
- `SecondBrain -> SecondBrainDomain + SecondBrainComposition`
- `SecondBrainWatch -> SecondBrainDomain + SecondBrainComposition`

The iPhone and Apple Watch targets are intentionally thin. Shared business logic, storage, AI orchestration, and audio services now live in the local package, while the app targets keep UI, entrypoints, and App Intents.

## Search Strategy

Note search currently uses a two-stage approach:

- SwiftData prefilters candidate notes using the normalized `searchableText` field.
- Existing in-memory ranking then orders that smaller candidate set for note lists, snippets, and free-form note resolution.

This keeps ranking behavior stable while avoiding full-corpus scans for non-empty queries. If the corpus grows beyond what this hybrid approach handles well, a dedicated search index can be added later without changing the note schema in the current app.

## watchOS Notes

- The repository includes a real `SecondBrainWatch` target and scheme.
- `Ask Notes` on Apple Watch is relayed through the paired iPhone.
- AI-assisted capture does not run locally on watchOS because Foundation Models are not available there.
- Notes edited on iPhone are expected to flow back to the watch through CloudKit sync.
- Physical watch builds require provisioning profiles that include the iCloud/CloudKit entitlements used by the project.

## Current Limitations

- Apple Intelligence features depend on supported hardware, OS version, and local model availability.
- Assistant behavior on Apple Watch depends on the paired iPhone being nearby and reachable.
- Physical watch signing must include CloudKit-capable provisioning to match the watch entitlements.

## Voice Architecture

- Raw audio is treated as transient transport and is not persisted as note data.
- The durable output of voice capture is either note content or an assistant-driven note mutation.
- When voice-command routing is unavailable, the app keeps the transcript as editable draft text instead of applying a command silently.

For lower-level setup notes, see [SETUP.md](2nd-Brain/SecondBrain/Docs/SETUP.md).
