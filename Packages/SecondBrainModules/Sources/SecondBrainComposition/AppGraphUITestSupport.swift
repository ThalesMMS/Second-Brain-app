import Foundation
import SecondBrainAI
import SecondBrainAudio
import SecondBrainDomain
import SecondBrainPersistence

@available(iOS 17.0, watchOS 10.0, *)
public extension AppGraph {
    struct UITestConfiguration: Sendable {
        public enum Dataset: String, Sendable {
            case empty
            case standard
        }

        public enum Assistant: String, Sendable {
            case deterministicSearch
            case fixedReply
            case pendingEdit
        }

        public enum Voice: String, Sendable {
            case newNote
            case assistantPendingEdit
            case draftFallback
        }

        public enum MicrophonePermission: String, Sendable {
            case granted
            case denied
        }

        public var dataset: Dataset
        public var assistant: Assistant
        public var voice: Voice
        public var microphonePermission: MicrophonePermission

        public init(
            dataset: Dataset = .standard,
            assistant: Assistant = .deterministicSearch,
            voice: Voice = .newNote,
            microphonePermission: MicrophonePermission = .granted
        ) {
            self.dataset = dataset
            self.assistant = assistant
            self.voice = voice
            self.microphonePermission = microphonePermission
        }
    }

    /// Creates an `AppGraph` preconfigured for deterministic UI tests.
    ///
    /// The returned graph uses in-memory persistence, seeds the requested dataset, and replaces runtime
    /// services with deterministic UI-test implementations for audio, transcription, text-to-speech,
    /// note capture, assistant behavior, and voice interpretation.
    /// - Parameters:
    ///   - configuration: UI-test parameters selecting the seeded dataset, assistant scenario, voice scenario, and simulated microphone permission.
    /// - Returns: An AppGraph wired for UI tests with seeded data and deterministic/stubbed runtime services.
    /// - Throws: `AppGraphBootstrapError.uiTestPersistenceFailure` if creating the in-memory persistence controller fails; `AppGraphBootstrapError.uiTestSeedingFailure` if seeding the persistence store with test notes fails; or any error thrown while constructing the UI-test runtime services.
    public static func uiTest(_ configuration: UITestConfiguration = UITestConfiguration()) throws -> AppGraph {
        let persistenceController: PersistenceController
        do {
            persistenceController = try PersistenceController(
                inMemory: true,
                enableCloudSync: false,
                useSharedContainer: false
            )
        } catch {
            throw AppGraphBootstrapError.uiTestPersistenceFailure(error)
        }

        let repository = persistenceController.repository
        do {
            try persistenceController.seedForUITests(Self.seededNotes(for: configuration.dataset))
        } catch {
            throw AppGraphBootstrapError.uiTestSeedingFailure(error)
        }

        let services = try Self.makeUITestServices(
            repository: repository,
            configuration: configuration
        )

        return AppGraph(
            persistenceController: persistenceController,
            repository: repository,
            audioFileStore: services.audioFileStore,
            audioRecorder: services.audioRecorder,
            speechTranscriber: services.speechTranscriber,
            textToSpeech: services.textToSpeech,
            notesAssistant: services.notesAssistant,
            noteCaptureIntelligence: services.noteCaptureIntelligence,
            voiceCaptureInterpretation: services.voiceCaptureInterpretation,
            companionRelayHost: services.companionRelayHost
        )
    }

    /// Builds deterministic runtime services for UI tests.
    ///
    /// The returned `RuntimeServices` uses stubbed implementations for audio, transcription, text-to-speech,
    /// note capture, assistant behavior, and voice interpretation. The assistant behavior is selected from
    /// `configuration` and backed by deterministic repository-driven fallbacks.
    /// - Parameters:
    ///   - repository: Repository used by assistant and deterministic fallback to load and modify notes.
    ///   - configuration: UI-test configuration controlling dataset scenarios, assistant behavior, voice scenario, and microphone permission.
    /// - Returns: A `RuntimeServices` instance composed of UI-test implementations wired to the provided repository and configuration.
    /// - Throws: `AppGraphBootstrapError.uiTestAudioDirectoryFailure` if the UI-test audio file store cannot be created (directory creation failure).
    private static func makeUITestServices(
        repository: any NoteRepository,
        configuration: UITestConfiguration
    ) throws -> RuntimeServices {
        let deterministicAssistant = DeterministicNotesAssistant(repository: repository)
        let assistant = UITestNotesAssistantService(
            repository: repository,
            scenario: configuration.assistant,
            deterministicFallback: deterministicAssistant,
            pendingEditTargetNoteID: UITestFixtures.shoppingListID
        )

        return RuntimeServices(
            audioFileStore: try UITestAudioFileStore(),
            audioRecorder: UITestAudioRecordingService(
                permission: configuration.microphonePermission
            ),
            speechTranscriber: UITestSpeechTranscriptionService(
                voiceScenario: configuration.voice
            ),
            textToSpeech: UITestTextToSpeechService(),
            notesAssistant: assistant,
            noteCaptureIntelligence: UITestNoteCaptureIntelligenceService(),
            voiceCaptureInterpretation: UITestVoiceCaptureInterpretationService(
                voiceScenario: configuration.voice
            ),
            companionRelayHost: nil
        )
    }

    /// Returns the seeded notes used for the requested UI-test dataset.
    /// - Parameter dataset: The dataset to seed. `.standard` returns the fixed UI-test notes; all other
    ///   values return an empty array.
    /// - Returns: Seed data for the selected dataset.
    private static func seededNotes(for dataset: UITestConfiguration.Dataset) -> [SeededNoteData] {
        guard dataset == .standard else {
            return []
        }

        return [
            SeededNoteData(
                id: UITestFixtures.shoppingListID,
                title: "Shopping list",
                body: "Milk\nEggs\nBread",
                createdAt: UITestFixtures.date("2025-01-10T09:00:00Z"),
                updatedAt: UITestFixtures.date("2025-01-10T09:00:00Z"),
                entries: [
                    SeededNoteEntryData(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
                        createdAt: UITestFixtures.date("2025-01-10T09:00:00Z"),
                        kind: .creation,
                        source: .manual,
                        text: "Milk\nEggs\nBread"
                    )
                ]
            ),
            SeededNoteData(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
                title: "Residency planning",
                body: "Collect transcripts and submit the residency application by July 15.",
                createdAt: UITestFixtures.date("2025-01-11T10:15:00Z"),
                updatedAt: UITestFixtures.date("2025-01-11T10:15:00Z"),
                entries: [
                    SeededNoteEntryData(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
                        createdAt: UITestFixtures.date("2025-01-11T10:15:00Z"),
                        kind: .creation,
                        source: .manual,
                        text: "Collect transcripts and submit the residency application by July 15."
                    )
                ]
            ),
            SeededNoteData(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
                title: "Oncology reminders",
                body: "Call Dr. Lima on Tuesday.\nBring pathology reports.\nSchedule MRI review.",
                createdAt: UITestFixtures.date("2025-01-12T08:30:00Z"),
                updatedAt: UITestFixtures.date("2025-01-12T08:30:00Z"),
                entries: [
                    SeededNoteEntryData(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000203")!,
                        createdAt: UITestFixtures.date("2025-01-12T08:30:00Z"),
                        kind: .creation,
                        source: .manual,
                        text: "Call Dr. Lima on Tuesday.\nBring pathology reports.\nSchedule MRI review."
                    )
                ]
            ),
        ]
    }
}

@available(iOS 17.0, watchOS 10.0, *)
private enum UITestFixtures {
    static let shoppingListID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    static let pendingEditCommand = "__ui_test_pending_edit__"
    static let fixedReply = "Stub assistant reply from UI test mode."

    /// Parses an ISO 8601 internet date-time string into a `Date`.
    /// - Parameter iso8601: A timestamp string in internet date-time format, such as
    ///   `"2024-01-01T12:00:00Z"`.
    /// - Returns: The `Date` represented by `iso8601`.
    /// - Note: Calls `preconditionFailure` if the string cannot be parsed.
    static func date(_ iso8601: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: iso8601) else {
            preconditionFailure("Invalid UI test date fixture: \(iso8601)")
        }
        return date
    }
}

@available(iOS 17.0, watchOS 10.0, *)
private final class UITestAudioFileStore: AudioFileStore {
    private let rootURL: URL

    init(fileManager: FileManager = .default) throws {
        rootURL = fileManager.temporaryDirectory.appendingPathComponent(
            "SecondBrainUITests",
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        } catch {
            throw AppGraphBootstrapError.uiTestAudioDirectoryFailure(error)
        }
    }

    /// Produces a unique temporary `.m4a` file URL under the store's root directory.
    /// - Returns: A `URL` pointing to a new, unique `.m4a` filename located inside the store's `rootURL`.
    func makeTemporaryRecordingURL() throws -> URL {
        rootURL.appendingPathComponent("\(UUID().uuidString).m4a")
    }

    /// No-op placeholder that preserves the `AudioFileStore` API surface for UI tests.
    ///
    /// This implementation intentionally performs no file-system cleanup.
    func cleanupLegacyPersistedAudio() {}
}

@available(iOS 17.0, watchOS 10.0, *)
@MainActor
private final class UITestAudioRecordingService: AudioRecordingService {
    private let permission: AppGraph.UITestConfiguration.MicrophonePermission
    private let fileManager: FileManager
    private var currentURL: URL?

    init(
        permission: AppGraph.UITestConfiguration.MicrophonePermission,
        fileManager: FileManager = .default
    ) {
        self.permission = permission
        self.fileManager = fileManager
    }

    var isRecording: Bool {
        currentURL != nil
    }

    /// Checks whether the configured UI-test microphone permission is granted.
    /// - Returns: `true` if the configured permission is `.granted`, `false` otherwise.
    func requestPermission() async -> Bool {
        permission == .granted
    }

    /// Begins a simulated recording by marking the given file URL as the active recording target.
    /// - Parameters:
    ///   - url: The file URL to record to. If no file exists at this URL, an empty file is created.
    func startRecording(to url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            guard fileManager.createFile(atPath: url.path, contents: Data()) else {
                currentURL = nil
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
            }
        }
        currentURL = url
    }

    /// Stops the current recording, clears the internal recording state, and returns metadata for the
    /// recorded audio.
    /// - Returns: A `RecordedAudio` with `temporaryFileURL` pointing to the recording and `durationSeconds` set to `1`.
    /// - Throws: `AudioServiceError.recordingUnavailable` if no recording is in progress.
    func stopRecording() throws -> RecordedAudio {
        guard let currentURL else {
            throw AudioServiceError.recordingUnavailable
        }
        self.currentURL = nil
        return RecordedAudio(temporaryFileURL: currentURL, durationSeconds: 1)
    }

    /// Cancels an in-progress recording by clearing the current recording URL.
    /// This does not delete any file at the previously assigned URL and does not produce or return audio metadata.
    func cancelRecording() {
        currentURL = nil
    }
}

@available(iOS 17.0, watchOS 10.0, *)
private final class UITestSpeechTranscriptionService: SpeechTranscriptionService, Sendable {
    private let voiceScenario: AppGraph.UITestConfiguration.Voice

    init(voiceScenario: AppGraph.UITestConfiguration.Voice) {
        self.voiceScenario = voiceScenario
    }

    /// Provides a deterministic transcript for a test audio file based on the configured voice scenario.
    /// - Parameters:
    ///   - url: The audio file URL (ignored by the UI-test implementation).
    ///   - locale: The locale for transcription (ignored by the UI-test implementation).
    /// - Returns: A deterministic transcript string chosen by the configured `voiceScenario`:
    ///   - `.newNote` -> "Buy oat milk on the way home."
    ///   - `.assistantPendingEdit` -> "Add butter to the shopping list."
    ///   - `.draftFallback` -> "Call the residency office tomorrow morning."
    func transcribeFile(at url: URL, locale: Locale) async throws -> String {
        switch voiceScenario {
        case .newNote:
            return "Buy oat milk on the way home."
        case .assistantPendingEdit:
            return "Add butter to the shopping list."
        case .draftFallback:
            return "Call the residency office tomorrow morning."
        }
    }
}

@available(iOS 17.0, watchOS 10.0, *)
@MainActor
private final class UITestTextToSpeechService: TextToSpeechService {
    private(set) var isSpeaking = false

    /// Begins speaking the provided text and updates speaking state.
    /// - Parameters:
    ///   - text: The text to speak. The UI-test implementation does not use this value.
    ///   - locale: Optional locale for voice selection. The UI-test implementation ignores this value.
    func speak(_ text: String, locale: Locale?) {
        isSpeaking = true
    }

    /// Stops any in-progress speaking activity.
    func stopSpeaking() {
        isSpeaking = false
    }
}

@available(iOS 17.0, watchOS 10.0, *)
private final class UITestNoteCaptureIntelligenceService: NoteCaptureIntelligenceService, Sendable {
    let capabilityState: AssistantCapabilityState = .available

    /// Produces a note-capture refinement that preserves the provided title and body.
    /// - Returns: A `NoteCaptureRefinement` containing the supplied `title` and `body`.
    func refineTypedNote(title: String, body: String, locale: Locale) async throws -> NoteCaptureRefinement {
        NoteCaptureRefinement(title: title, body: body)
    }

    /// Creates a note-capture refinement from an already-produced transcript.
    /// - Parameters:
    ///   - title: The proposed note title.
    ///   - transcript: The transcribed text to use as the note body.
    ///   - locale: The locale of the transcript (provided for compatibility; not used by this implementation).
    /// - Returns: A `NoteCaptureRefinement` whose `title` is `title` and whose `body` is `transcript`.
    func refineTranscript(title: String, transcript: String, locale: Locale) async throws -> NoteCaptureRefinement {
        NoteCaptureRefinement(title: title, body: transcript)
    }
}

@available(iOS 17.0, watchOS 10.0, *)
private final class UITestVoiceCaptureInterpretationService: VoiceCaptureInterpretationService, Sendable {
    private let voiceScenario: AppGraph.UITestConfiguration.Voice

    init(voiceScenario: AppGraph.UITestConfiguration.Voice) {
        self.voiceScenario = voiceScenario
    }

    var capabilityState: AssistantCapabilityState {
        switch voiceScenario {
        case .draftFallback:
            return .unavailable(reason: "Voice command routing is disabled for this UI test scenario.")
        case .newNote, .assistantPendingEdit:
            return .available
        }
    }

    /// Interprets the provided transcript into a voice-capture intent based on the configured UI-test voice scenario.
    /// - Parameters:
    ///   - transcript: The raw transcribed text to interpret.
    ///   - locale: The locale of the transcript (not used by all scenarios).
    /// - Returns: A `VoiceCaptureInterpretation` containing the inferred intent and the normalized text to use.
    /// - Throws: `VoiceCaptureInterpretationError.unavailable` when the voice scenario is `.draftFallback`, indicating voice command routing is disabled for this UI test scenario.
    func interpret(transcript: String, locale: Locale) async throws -> VoiceCaptureInterpretation {
        switch voiceScenario {
        case .newNote:
            return VoiceCaptureInterpretation(
                intent: .newNote,
                normalizedText: transcript
            )
        case .assistantPendingEdit:
            return VoiceCaptureInterpretation(
                intent: .assistantCommand,
                normalizedText: UITestFixtures.pendingEditCommand
            )
        case .draftFallback:
            throw VoiceCaptureInterpretationError.unavailable(
                "Voice command routing is disabled for this UI test scenario."
            )
        }
    }
}

@available(iOS 17.0, watchOS 10.0, *)
@MainActor
private final class UITestNotesAssistantService: NotesAssistantService {
    private struct PendingEdit {
        let noteID: UUID
        let updatedTitle: String
        let updatedBody: String
        let expectedUpdatedAt: Date
    }

    private let repository: any NoteRepository
    private let scenario: AppGraph.UITestConfiguration.Assistant
    private let deterministicFallback: DeterministicNotesAssistant
    private let pendingEditTargetNoteID: UUID
    private var pendingEdit: PendingEdit?

    init(
        repository: any NoteRepository,
        scenario: AppGraph.UITestConfiguration.Assistant,
        deterministicFallback: DeterministicNotesAssistant,
        pendingEditTargetNoteID: UUID
    ) {
        self.repository = repository
        self.scenario = scenario
        self.deterministicFallback = deterministicFallback
        self.pendingEditTargetNoteID = pendingEditTargetNoteID
    }

    var capabilityState: AssistantCapabilityState {
        .available
    }

    var status: NotesAssistantStatus? {
        scenario == .deterministicSearch ? deterministicFallback.status : nil
    }

    /// Prewarms assistant resources when running the deterministic-search scenario.
    /// When the assistant is configured for deterministic search, this triggers any initialization or warm-up of the deterministic fallback assistant. It has no effect for other assistant scenarios.
    func prewarm() {
        if scenario == .deterministicSearch {
            deterministicFallback.prewarm()
        }
    }

    /// Clears any in-progress pending edit and resets the deterministic assistant's conversation state.
    /// This removes the stored pending edit (if any) and instructs the deterministic fallback assistant to reset its conversation.
    func resetConversation() {
        pendingEdit = nil
        deterministicFallback.resetConversation()
    }

    /// Processes a user or voice assistant input and produces the corresponding notes-assistant response.
    /// - Parameters:
    ///   - input: The raw input text from the user or voice transcription.
    /// - Returns: A `NotesAssistantResponse` representing the assistant's reply or action (e.g., a search result, fixed reply, or pending-edit confirmation).
    /// Processes user input and produces a UI-test assistant response according to the configured scenario.
    /// - Parameter input: Raw user input text; may be the pending-edit command (`UITestFixtures.pendingEditCommand`), a confirmation command (`"confirm"`/`"cancel"`), or other conversational input.
    /// - Returns: A `NotesAssistantResponse` representing the assistant's reply and any referenced note IDs.
    /// - Throws: Any error propagated from the underlying assistant services or repository operations invoked during processing.
    func process(_ input: String) async throws -> NotesAssistantResponse {
        let normalizedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredInput = normalizedInput.lowercased()

        if loweredInput == "confirm" || loweredInput == "cancel" {
            return try await resolvePendingEdit(decision: loweredInput)
        }

        if normalizedInput == UITestFixtures.pendingEditCommand {
            return try await beginPendingEdit()
        }

        switch scenario {
        case .deterministicSearch:
            return try await deterministicFallback.process(normalizedInput)
        case .fixedReply:
            return NotesAssistantResponse(
                text: UITestFixtures.fixedReply,
                referencedNoteIDs: []
            )
        case .pendingEdit:
            return try await beginPendingEdit()
        }
    }

    /// Begins a pending-edit assistant interaction by loading the configured seeded note and preparing an
    /// update that adds "Butter" to the body if it is not already present.
    /// - Returns: A `NotesAssistantResponse` that prompts for confirmation (interaction `.pendingEditConfirmation`) and references the target note's ID, or a response indicating that no seeded note is available.
    /// - Throws: Any error thrown while loading the note from the repository.
    private func beginPendingEdit() async throws -> NotesAssistantResponse {
        guard let note = try await repository.loadNote(id: pendingEditTargetNoteID) else {
            pendingEdit = nil
            return NotesAssistantResponse(
                text: "No seeded note is available for the pending-edit UI test scenario.",
                referencedNoteIDs: []
            )
        }

        let updatedBody = note.body.contains("Butter")
            ? note.body
            : "\(note.body)\nButter"
        pendingEdit = PendingEdit(
            noteID: note.id,
            updatedTitle: note.title,
            updatedBody: updatedBody,
            expectedUpdatedAt: note.updatedAt
        )

        return NotesAssistantResponse(
            text: "I can update \(note.displayTitle) to add Butter. Confirm or Cancel.",
            referencedNoteIDs: [note.id],
            interaction: .pendingEditConfirmation
        )
    }

    /// Resolves the currently staged pending edit by applying or discarding it based on the provided
    /// decision.
    /// - Parameter decision: The action to take. `"confirm"` applies the pending edit, `"cancel"` discards
    ///   it, and any other value yields a validation response.
    /// - Returns: A `NotesAssistantResponse` describing the outcome and containing any referenced note IDs.
    /// - Throws: Any error thrown by the repository when attempting to replace the note during confirmation.
    private func resolvePendingEdit(decision: String) async throws -> NotesAssistantResponse {
        guard let pendingEdit else {
            return NotesAssistantResponse(
                text: "There is no pending edit to \(decision).",
                referencedNoteIDs: []
            )
        }

        switch decision {
        case "confirm":
            let processingNoteID = pendingEdit.noteID
            let updated = try await repository.replaceNote(
                id: pendingEdit.noteID,
                title: pendingEdit.updatedTitle,
                body: pendingEdit.updatedBody,
                source: .assistant,
                expectedUpdatedAt: pendingEdit.expectedUpdatedAt
            )
            if self.pendingEdit?.noteID == processingNoteID {
                self.pendingEdit = nil
            }
            return NotesAssistantResponse(
                text: "Updated note \(updated.displayTitle).",
                referencedNoteIDs: [updated.id]
            )
        case "cancel":
            self.pendingEdit = nil
            return NotesAssistantResponse(
                text: "Canceled the pending edit.",
                referencedNoteIDs: [pendingEdit.noteID]
            )
        default:
            return NotesAssistantResponse(
                text: "The decision must be either confirm or cancel.",
                referencedNoteIDs: []
            )
        }
    }
}
