import Foundation
import Testing
@testable import SecondBrainAudio
@testable import SecondBrainDomain

struct SecondBrainAudioTests {
    @Test
    @MainActor
    func cleanupLegacyPersistedAudioIsIdempotent() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let legacyDirectoryURL = rootURL.appendingPathComponent("AudioNotes", isDirectory: true)
        try fileManager.createDirectory(at: legacyDirectoryURL, withIntermediateDirectories: true)
        try Data("legacy audio".utf8).write(to: legacyDirectoryURL.appendingPathComponent("old.m4a"))
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileStore = AppGroupAudioFileStore(useSharedContainer: false, baseURL: rootURL)

        fileStore.cleanupLegacyPersistedAudio()
        #expect(!fileManager.fileExists(atPath: legacyDirectoryURL.path))

        fileStore.cleanupLegacyPersistedAudio()
        #expect(!fileManager.fileExists(atPath: legacyDirectoryURL.path))
    }

    @Test
    @MainActor
    func cleanupLegacyPersistedAudioDoesNothingWhenDirectoryIsMissing() {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileStore = AppGroupAudioFileStore(useSharedContainer: false, baseURL: rootURL)
        fileStore.cleanupLegacyPersistedAudio()

        let legacyDirectoryURL = rootURL.appendingPathComponent("AudioNotes", isDirectory: true)
        #expect(!fileManager.fileExists(atPath: legacyDirectoryURL.path))
    }

    @Test
    @MainActor
    func makeTemporaryRecordingURLProducesM4AFileURL() throws {
        let fileStore = AppGroupAudioFileStore(useSharedContainer: false)

        let url = try fileStore.makeTemporaryRecordingURL()

        #expect(url.isFileURL)
        #expect(url.pathExtension == "m4a")
        #expect(url.deletingLastPathComponent() == FileManager.default.temporaryDirectory)
    }

    @Test
    @MainActor
    func unavailableSpeechTranscriptionServiceThrowsUnavailable() async {
        let service = UnavailableSpeechTranscriptionService()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")

        do {
            _ = try await service.transcribeFile(at: url, locale: .current)
            Issue.record("Expected transcription to be unavailable.")
        } catch let error as AudioServiceError {
            #expect(error == .transcriptionUnavailable)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - AudioServices.swift async refactor: Sendable / no-@MainActor coverage

    @Test
    func unavailableSpeechTranscriptionServiceIsCallableFromNonMainActor() async {
        // UnavailableSpeechTranscriptionService was previously @MainActor; it is now
        // Sendable, so it must be usable from any concurrency context.
        let service = UnavailableSpeechTranscriptionService()
        let url = URL(fileURLWithPath: "/tmp/nonexistent.m4a")

        await #expect(throws: AudioServiceError.self) {
            _ = try await Task.detached {
                try await service.transcribeFile(at: url, locale: .current)
            }.value
        }
    }

    @Test
    func unavailableSpeechTranscriptionServiceThrowsTranscriptionUnavailableError() async throws {
        // Verify the exact error case thrown, matching the Sendable service contract.
        let service = UnavailableSpeechTranscriptionService()

        do {
            _ = try await service.transcribeFile(
                at: URL(fileURLWithPath: "/tmp/audio.m4a"),
                locale: Locale(identifier: "en_US")
            )
            Issue.record("Expected AudioServiceError.transcriptionUnavailable.")
        } catch AudioServiceError.transcriptionUnavailable {
            // Expected path – test passes.
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test
    func appGroupAudioFileStoreIsCallableFromNonMainActor() throws {
        // AppGroupAudioFileStore was previously @MainActor; removing that annotation means
        // it must be constructible and usable from any context.
        let store = AppGroupAudioFileStore(useSharedContainer: false)
        let url = try store.makeTemporaryRecordingURL()

        #expect(url.isFileURL)
        #expect(url.pathExtension == "m4a")
    }

    #if os(macOS)
    @Test
    @MainActor
    func macOSRecorderPermissionAllowsUnavailableStartRecordingError() async {
        let service = AVAudioRecorderService()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        let permissionGranted = await service.requestPermission()

        #expect(permissionGranted == true)
        #expect(throws: AudioServiceError.recordingUnavailable) {
            try service.startRecording(to: url)
        }
    }

    @Test
    @MainActor
    func macOSTextToSpeechStubPublishesUnavailableSignals() {
        let service = AVSpeechTextToSpeechService()
        let recorder = NotificationRecorder()
        let observers = makeTTSObservers(service: service, recorder: recorder)
        defer {
            removeObservers(observers)
        }

        service.speak("Hello world", locale: Locale(identifier: "en_US"))
        #expect(service.isSpeaking == true)

        service.stopSpeaking()

        #expect(service.isSpeaking == false)
        #expect(recorder.didPostSpeakNotification == true)
        #expect(recorder.speakTextLength == 11)
        #expect(recorder.speakLocaleIdentifier == "en_US")
        #expect(recorder.didPostStopNotification == true)
        #expect(recorder.stopWasSpeaking == true)
    }

    @Test
    @MainActor
    func macOSTextToSpeechStubIgnoresEmptySpeakRequests() {
        let service = AVSpeechTextToSpeechService()
        let recorder = NotificationRecorder()
        let observers = makeTTSObservers(service: service, recorder: recorder)
        defer {
            removeObservers(observers)
        }

        service.speak(" \n\t ", locale: Locale(identifier: "en_US"))

        #expect(service.isSpeaking == false)
        #expect(recorder.didPostSpeakNotification == false)
    }
    #endif
}

#if os(macOS)
private final class NotificationRecorder: @unchecked Sendable {
    var didPostSpeakNotification = false
    var speakTextLength: Int?
    var speakLocaleIdentifier: String?
    var didPostStopNotification = false
    var stopWasSpeaking: Bool?
}

private func makeTTSObservers(
    service: AVSpeechTextToSpeechService,
    recorder: NotificationRecorder
) -> [NSObjectProtocol] {
    let speakObserver = NotificationCenter.default.addObserver(
        forName: AudioServiceNotifications.textToSpeechUnavailableSpeakRequested,
        object: service,
        queue: nil
    ) { notification in
        recorder.didPostSpeakNotification = true
        recorder.speakTextLength = notification.userInfo?[AudioServiceNotifications.textLengthKey] as? Int
        recorder.speakLocaleIdentifier = notification.userInfo?[AudioServiceNotifications.localeIdentifierKey] as? String
    }
    let stopObserver = NotificationCenter.default.addObserver(
        forName: AudioServiceNotifications.textToSpeechUnavailableStopRequested,
        object: service,
        queue: nil
    ) { notification in
        recorder.didPostStopNotification = true
        recorder.stopWasSpeaking = notification.userInfo?[AudioServiceNotifications.wasSpeakingKey] as? Bool
    }
    return [speakObserver, stopObserver]
}

private func removeObservers(_ observers: [NSObjectProtocol]) {
    observers.forEach(NotificationCenter.default.removeObserver)
}
#endif
