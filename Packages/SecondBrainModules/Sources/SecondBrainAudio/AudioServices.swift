import Foundation
import AVFAudio
import AVFoundation
import SecondBrainDomain

package final class AppGroupAudioFileStore: AudioFileStore {
    private let fileManager = FileManager.default
    private let legacyDirectoryURL: URL

    package init(
        appGroupIdentifier: String = SecondBrainSettings.appGroupIdentifier,
        useSharedContainer: Bool = true,
        baseURL: URL? = nil
    ) {
        let resolvedBaseURL: URL
        if let baseURL {
            resolvedBaseURL = baseURL
        } else if useSharedContainer {
            resolvedBaseURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
                ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        } else {
            resolvedBaseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        }

        legacyDirectoryURL = resolvedBaseURL.appendingPathComponent("AudioNotes", isDirectory: true)
    }

    /// Creates a temporary file URL for a new recording using a unique `.m4a` filename.
    /// - Returns: A file URL located in the file manager's temporary directory with a UUID filename and `.m4a` extension.
    package func makeTemporaryRecordingURL() throws -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        return url
    }

    /// Removes the legacy persisted-audio directory when it exists.
    ///
    /// This is a no-op when the directory is absent, and removal errors are ignored.
    package func cleanupLegacyPersistedAudio() {
        guard fileManager.fileExists(atPath: legacyDirectoryURL.path) else {
            return
        }
        try? fileManager.removeItem(at: legacyDirectoryURL)
    }
}

@MainActor
package final class AVAudioRecorderService: NSObject, AudioRecordingService {
    private var recorder: AVAudioRecorder?
    private var activeURL: URL?

    package override init() {
        super.init()
    }

    package var isRecording: Bool {
        recorder?.isRecording == true
    }

    /// Requests the user's permission to record audio.
    /// - Returns: `true` if the user granted microphone recording permission, `false` otherwise.
    package func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Begins recording audio and writes the captured audio to the specified file URL.
    /// 
    /// The method configures and activates the audio session, creates an `AVAudioRecorder` with AAC (44.1 kHz, mono, high quality) settings, prepares it, and starts recording. If a recording is already in progress this method returns without changing state.
    /// - Parameters:
    ///   - url: The file URL where the recording will be written.
    /// - Throws:
    ///   - `AudioServiceError.recordingUnavailable` if the recorder fails to start.
    ///   - An underlying `Error` propagated from `AVAudioSession` configuration or `AVAudioRecorder` initialization.
    package func startRecording(to url: URL) throws {
        guard !isRecording else {
            return
        }

        let session = AVAudioSession.sharedInstance()
        #if os(iOS)
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
        #else
        try session.setCategory(.playAndRecord, mode: .spokenAudio)
        #endif
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        recorder = try AVAudioRecorder(url: url, settings: settings)
        activeURL = url
        recorder?.prepareToRecord()
        guard recorder?.record() == true else {
            recorder?.stop()
            recorder = nil
            activeURL = nil
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? FileManager.default.removeItem(at: url)
            throw AudioServiceError.recordingUnavailable
        }
    }

    /// Stops the active recording, clears internal recorder state, and returns the recorded file metadata.
    /// 
    /// This deactivates the audio session (errors during deactivation are ignored) and computes the recording duration (clamped to at least 0).
    /// - Returns: A `RecordedAudio` containing the temporary file URL and the duration in seconds.
    /// - Throws: `AudioServiceError.recordingUnavailable` if there is no active recording to stop.
    package func stopRecording() throws -> RecordedAudio {
        guard let recorder, let url = activeURL else {
            throw AudioServiceError.recordingUnavailable
        }

        recorder.stop()
        self.recorder = nil
        self.activeURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        let duration = max(CMTimeGetSeconds(AVURLAsset(url: url).duration), 0)
        return RecordedAudio(temporaryFileURL: url, durationSeconds: duration)
    }

    /// Cancels any in-progress recording and cleans up its temporary file and state.
    /// 
    /// Stops the active recorder if present, removes the active recording file if one exists (errors are ignored), clears the recorder and active URL state, and deactivates the shared audio session (deactivation errors are ignored).
    package func cancelRecording() {
        recorder?.stop()
        if let activeURL {
            try? FileManager.default.removeItem(at: activeURL)
        }
        recorder = nil
        activeURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

#if canImport(Speech)
import Speech

final class SpeechAnalyzerFileTranscriptionService: SpeechTranscriptionService, Sendable {
    /// Transcribes speech from an audio file into a plain text string.
    /// - Parameters:
    ///   - url: File URL of the audio to transcribe.
    ///   - locale: Locale to use for the transcription model and recognition.
    /// - Returns: The transcription text with leading and trailing whitespace and newlines removed.
    /// - Throws: `AudioServiceError.transcriptionUnavailable` if speech transcription is not supported on the current OS version.
    func transcribeFile(at url: URL, locale: Locale) async throws -> String {
        guard #available(iOS 26.0, *) else {
            throw AudioServiceError.transcriptionUnavailable
        }

        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        try await ensureModel(for: transcriber, locale: locale)

        async let transcriptionFuture: String = transcriber.results.reduce(into: "") { partial, result in
            partial.append(String(result.text.characters))
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let audioFile = try AVAudioFile(forReading: url)
        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        let result = try await transcriptionFuture
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @available(iOS 26.0, *)
    private func ensureModel(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        let supported = await SpeechTranscriber.supportedLocales
            .map(\.identifier)

        guard supported.contains(locale.identifier) else {
            throw AudioServiceError.unsupportedLocale
        }

        let installed = await Set(SpeechTranscriber.installedLocales)
            .map(\.identifier)

        if installed.contains(locale.identifier) {
            return
        }

        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await downloader.downloadAndInstall()
        }
    }
}
#endif

package final class UnavailableSpeechTranscriptionService: SpeechTranscriptionService, Sendable {
    /// Throws `AudioServiceError.transcriptionUnavailable` because transcription is unavailable in this implementation.
    /// - Parameters:
    ///   - url: The file URL of the audio to transcribe.
    ///   - locale: The locale to use for transcription.
    /// - Throws: `AudioServiceError.transcriptionUnavailable` when transcription is not available.
    package func transcribeFile(at url: URL, locale: Locale) async throws -> String {
        throw AudioServiceError.transcriptionUnavailable
    }
}

package enum SpeechTranscriptionServiceFactory {
    /// Returns an appropriate implementation of `SpeechTranscriptionService` for the current environment.
    /// - Returns: An instance conforming to `SpeechTranscriptionService`: a working transcription service when the Speech framework is available, otherwise an unavailable fallback implementation that reports transcription as unavailable.
    package static func make() -> any SpeechTranscriptionService {
        #if canImport(Speech)
        return SpeechAnalyzerFileTranscriptionService()
        #else
        return UnavailableSpeechTranscriptionService()
        #endif
    }
}

@MainActor
package final class AVSpeechTextToSpeechService: NSObject, TextToSpeechService, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()

    package var isSpeaking: Bool {
        synthesizer.isSpeaking
    }

    package override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks the provided text aloud, interrupting any currently speaking utterance.
    /// - Parameters:
    ///   - text: The text to speak; leading and trailing whitespace/newlines are removed and no speech occurs if the result is empty.
    ///   - locale: Optional locale used to select the voice (system default voice is used when `nil`).
    package func speak(_ text: String, locale: Locale?) {
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty else {
            return
        }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: cleanedText)
        if let locale {
            utterance.voice = AVSpeechSynthesisVoice(language: locale.identifier)
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    /// Stops ongoing and queued speech immediately.
    package func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
