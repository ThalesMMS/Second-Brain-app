# Second Brain setup notes

This scaffold is wired for:

- SwiftData persistence for notes, note history, and audio metadata.
- CloudKit-ready storage configuration.
- App Group-based local file storage for recorded audio.
- App Intents shortcuts for create, append, read, and ask flows.
- On-device Apple Intelligence orchestration with Foundation Models when available.
- SpeechAnalyzer-based audio transcription when available.

## Required Xcode capability checks

Before running on device, confirm these values in **Signing & Capabilities**:

- **iCloud / CloudKit** container: `iCloud.thalesmms.secondbrain`
- **App Groups**: `group.thalesmms.secondbrain`
- Background mode for remote notifications is already present in `Info.plist`.

If you prefer a different CloudKit container or App Group name, update both:

- `SecondBrainSettings` in `Domain/SecondBrainDomain.swift`
- `SecondBrain.entitlements`

## watchOS

The repo includes `WatchSupport/SecondBrainWatchSupport.swift` and a real `SecondBrainWatch` target. Build the watch app with the `SecondBrainWatch` scheme when you want to validate the watch-specific UI and relay flows.

## Suggested next steps

1. Add Siri / Apple Intelligence testing on a physical device that supports Apple Intelligence.
2. If you remove or do not already have a dedicated watchOS target such as `SecondBrainWatch`, add one before expanding the watch-specific UI and relay flows.
3. Add snapshot and end-to-end UI tests for the critical note flows.
4. Add richer retrieval logic or embeddings if your note corpus grows a lot.
