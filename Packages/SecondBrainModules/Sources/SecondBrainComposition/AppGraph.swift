import Foundation
import SecondBrainAI
import SecondBrainAudio
import SecondBrainDomain
import SecondBrainPersistence
import SwiftData

private struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
}

@available(iOS 17.0, watchOS 10.0, *)
public struct AppGraphBootstrapError: LocalizedError, Sendable {
    public let summary: String
    public let details: String

    public init(summary: String, details: String) {
        self.summary = summary
        self.details = details
    }

    public var errorDescription: String? {
        summary
    }

    public var failureReason: String? {
        details
    }

    /// Creates an `AppGraphBootstrapError` for failures opening the live notes store.
    /// - Parameter error: The underlying persistence error to normalize for the user-facing details.
    static func livePersistenceFailure(_ error: any Error) -> AppGraphBootstrapError {
        AppGraphBootstrapError(
            summary: "Second Brain couldn't open your notes store.",
            details: Self.describe(error)
        )
    }

    /// Creates an `AppGraphBootstrapError` for failures starting in UI test mode.
    /// - Parameter error: The underlying error to normalize for the user-facing details.
    static func uiTestPersistenceFailure(_ error: any Error) -> AppGraphBootstrapError {
        AppGraphBootstrapError(
            summary: "Second Brain couldn't start in UI test mode.",
            details: Self.describe(error)
        )
    }

    /// Creates an `AppGraphBootstrapError` for failures seeding UI test data.
    /// - Parameter error: The underlying seeding error to normalize for the user-facing details.
    static func uiTestSeedingFailure(_ error: any Error) -> AppGraphBootstrapError {
        AppGraphBootstrapError(
            summary: "Second Brain couldn't seed UI test data.",
            details: Self.describe(error)
        )
    }

    /// Creates an `AppGraphBootstrapError` for failures preparing UI test audio storage.
    /// - Parameter error: The underlying error to normalize for the user-facing details.
    static func uiTestAudioDirectoryFailure(_ error: any Error) -> AppGraphBootstrapError {
        AppGraphBootstrapError(
            summary: "Second Brain couldn't prepare UI test audio storage.",
            details: Self.describe(error)
        )
    }

    /// Produces a trimmed, user-facing description for an error.
    /// - Parameter error: The error to describe.
    /// - Returns: `error.localizedDescription` trimmed of whitespace and newlines, or `String(describing: error)` if the trimmed description is empty.
    private static func describe(_ error: any Error) -> String {
        let localizedDescription = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return localizedDescription.isEmpty ? String(describing: error) : localizedDescription
    }
}

@available(iOS 17.0, watchOS 10.0, *)
@MainActor
public final class AppGraph {
    struct RuntimeServices {
        let audioFileStore: any AudioFileStore
        let audioRecorder: any AudioRecordingService
        let speechTranscriber: any SpeechTranscriptionService
        let textToSpeech: any TextToSpeechService
        let notesAssistant: any NotesAssistantService
        let noteCaptureIntelligence: any NoteCaptureIntelligenceService
        let voiceCaptureInterpretation: any VoiceCaptureInterpretationService
        let companionRelayHost: AnyObject?
    }

    public static let preview = try! AppGraph(
        inMemory: true,
        enableCloudSync: false,
        useSharedContainer: false
    )

    package let persistenceController: PersistenceController
    public var modelContainer: ModelContainer { persistenceController.container }
    public let repository: any NoteRepository
    public let audioFileStore: any AudioFileStore
    public let audioRecorder: any AudioRecordingService
    package let speechTranscriber: any SpeechTranscriptionService
    public let textToSpeech: any TextToSpeechService
    public let notesAssistant: any NotesAssistantService
    public let noteCaptureIntelligence: any NoteCaptureIntelligenceService
    public let voiceCaptureInterpretation: any VoiceCaptureInterpretationService
    private let companionRelayHost: AnyObject?

    public let createNote: CreateNoteUseCase
    public let processVoiceCapture: ProcessVoiceCaptureUseCase
    public let appendToNote: AppendToNoteUseCase
    public let saveNote: SaveNoteUseCase
    public let deleteNote: DeleteNoteUseCase
    public let listNotes: ListNotesUseCase
    public let loadNote: LoadNoteUseCase
    package let searchNotes: SearchNotesUseCase
    public let askNotes: AskNotesUseCase

    /// Creates a fully-wired AppGraph configured for the current runtime.
    /// - Parameters:
    ///   - enableCloudSync: Whether cloud sync should be enabled for the persistence layer.
    ///   - useSharedContainer: Whether to use the app group/shared container for persisted data (defaults to `false` on watchOS, `true` elsewhere).
    /// - Returns: A configured `AppGraph` with persistence, repositories, runtime services, and use cases wired.
    /// - Throws: `AppGraphBootstrapError.livePersistenceFailure` when the persistence controller cannot be created or opened.
    public static func makeLive(
        enableCloudSync: Bool = true,
        useSharedContainer: Bool = {
#if os(watchOS)
            false
#else
            true
#endif
        }()
    ) throws -> AppGraph {
        do {
            return try makeLive(
                enableCloudSync: enableCloudSync,
                useSharedContainer: useSharedContainer,
                persistenceControllerFactory: Self.makePersistenceController
            )
        } catch {
            throw AppGraphBootstrapError.livePersistenceFailure(error)
        }
    }

    public static func makeLiveForStartup(
        enableCloudSync: Bool = true,
        useSharedContainer: Bool = {
#if os(watchOS)
            false
#else
            true
#endif
        }()
    ) async throws -> AppGraph {
        do {
            let persistenceController = try await Task.detached(priority: .userInitiated) {
                UncheckedSendableBox(
                    value: try Self.makePersistenceController(
                        inMemory: false,
                        enableCloudSync: enableCloudSync,
                        useSharedContainer: useSharedContainer
                    )
                )
            }.value.value

            return makeLive(
                persistenceController: persistenceController,
                useSharedContainer: useSharedContainer
            )
        } catch {
            throw AppGraphBootstrapError.livePersistenceFailure(error)
        }
    }

    public convenience init(
        inMemory: Bool = false,
        enableCloudSync: Bool = true,
        useSharedContainer: Bool = true
    ) throws {
        let persistenceController = try Self.makePersistenceController(
            inMemory: inMemory,
            enableCloudSync: enableCloudSync,
            useSharedContainer: useSharedContainer
        )
        let repository = persistenceController.repository
        let services = Self.makeRuntimeServices(
            repository: repository,
            useSharedContainer: useSharedContainer
        )

        self.init(
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

    init(
        persistenceController: PersistenceController,
        repository: any NoteRepository,
        audioFileStore: any AudioFileStore,
        audioRecorder: any AudioRecordingService,
        speechTranscriber: any SpeechTranscriptionService,
        textToSpeech: any TextToSpeechService,
        notesAssistant: any NotesAssistantService,
        noteCaptureIntelligence: any NoteCaptureIntelligenceService,
        voiceCaptureInterpretation: any VoiceCaptureInterpretationService,
        companionRelayHost: AnyObject?
    ) {
        self.persistenceController = persistenceController
        self.repository = repository
        self.audioFileStore = audioFileStore
        self.audioRecorder = audioRecorder
        self.speechTranscriber = speechTranscriber
        self.textToSpeech = textToSpeech
        self.notesAssistant = notesAssistant
        self.noteCaptureIntelligence = noteCaptureIntelligence
        self.voiceCaptureInterpretation = voiceCaptureInterpretation
        self.companionRelayHost = companionRelayHost
        audioFileStore.cleanupLegacyPersistedAudio()

        createNote = CreateNoteUseCase(repository: repository)
        processVoiceCapture = ProcessVoiceCaptureUseCase(
            repository: repository,
            transcriptionService: speechTranscriber,
            captureIntelligence: noteCaptureIntelligence,
            interpretationService: voiceCaptureInterpretation,
            assistant: notesAssistant
        )
        appendToNote = AppendToNoteUseCase(repository: repository)
        saveNote = SaveNoteUseCase(repository: repository)
        deleteNote = DeleteNoteUseCase(repository: repository)
        listNotes = ListNotesUseCase(repository: repository)
        loadNote = LoadNoteUseCase(repository: repository)
        searchNotes = SearchNotesUseCase(repository: repository)
        askNotes = AskNotesUseCase(assistant: notesAssistant)
    }

    /// Creates and returns a PersistenceController configured for the app graph.
    /// - Parameters:
    ///   - inMemory: If `true`, configures the controller to use an in-memory store instead of on-disk storage.
    ///   - enableCloudSync: If `true`, enables cloud synchronization for the persistence layer.
    ///   - useSharedContainer: If `true`, stores data in the app group / shared container for cross-process access.
    /// - Returns: A configured `PersistenceController`.
    /// - Throws: If the underlying persistence initialization fails.
    nonisolated private static func makePersistenceController(
        inMemory: Bool,
        enableCloudSync: Bool,
        useSharedContainer: Bool
    ) throws -> PersistenceController {
        try PersistenceController(
            inMemory: inMemory,
            enableCloudSync: enableCloudSync,
            useSharedContainer: useSharedContainer
        )
    }

    /// Creates a live AppGraph by constructing a persistence controller via the supplied factory and wiring platform-appropriate runtime services.
    /// - Parameters:
    ///   - enableCloudSync: Whether cloud sync should be enabled for the persistence controller.
    ///   - useSharedContainer: Whether to configure the persistence controller and file store to use an app group/shared container.
    ///   - persistenceControllerFactory: Factory that creates a `PersistenceController` given `(inMemory, enableCloudSync, useSharedContainer)`. The factory is called with `inMemory` set to `false`.
    /// - Returns: A fully wired `AppGraph` using the created persistence controller and selected runtime services.
    /// - Throws: Any error thrown by `persistenceControllerFactory`.
    static func makeLive(
        enableCloudSync: Bool,
        useSharedContainer: Bool,
        persistenceControllerFactory: (Bool, Bool, Bool) throws -> PersistenceController
    ) throws -> AppGraph {
        let persistenceController = try persistenceControllerFactory(
            false,
            enableCloudSync,
            useSharedContainer
        )
        return makeLive(
            persistenceController: persistenceController,
            useSharedContainer: useSharedContainer
        )
    }

    private static func makeLive(
        persistenceController: PersistenceController,
        useSharedContainer: Bool
    ) -> AppGraph {
        let repository = persistenceController.repository
        let services = Self.makeRuntimeServices(
            repository: repository,
            useSharedContainer: useSharedContainer
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

    /// Builds the runtime services used by `AppGraph` for the current platform and model availability.
    ///
    /// This wires audio, transcription, and text-to-speech services, then selects the appropriate assistant,
    /// note-capture, and voice-interpretation implementations, plus an optional companion relay host.
    /// - Parameters:
    ///   - repository: The note repository provided to assistants and deterministic services.
    ///   - useSharedContainer: If `true`, the audio file store will be configured to use the shared app group container.
    /// - Returns: A `RuntimeServices` instance containing the selected concrete service implementations and optional companion relay host.
    private static func makeRuntimeServices(
        repository: any NoteRepository,
        useSharedContainer: Bool
    ) -> RuntimeServices {
        let audioFileStore = AppGroupAudioFileStore(useSharedContainer: useSharedContainer)
        let audioRecorder = AVAudioRecorderService()
        let speechTranscriber = SpeechTranscriptionServiceFactory.make()
        let textToSpeech = AVSpeechTextToSpeechService()

        #if os(watchOS)
        let relayAssistant = CompanionRelayNotesAssistant()
        return RuntimeServices(
            audioFileStore: audioFileStore,
            audioRecorder: audioRecorder,
            speechTranscriber: speechTranscriber,
            textToSpeech: textToSpeech,
            notesAssistant: relayAssistant,
            noteCaptureIntelligence: UnavailableNoteCaptureIntelligenceService(
                reason: "AI-assisted capture is unavailable on watchOS because Apple Intelligence does not run there yet."
            ),
            voiceCaptureInterpretation: relayAssistant,
            companionRelayHost: nil
        )
        #else
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let localAssistant = AppleIntelligenceNotesAssistant(repository: repository)
            return RuntimeServices(
                audioFileStore: audioFileStore,
                audioRecorder: audioRecorder,
                speechTranscriber: speechTranscriber,
                textToSpeech: textToSpeech,
                notesAssistant: localAssistant,
                noteCaptureIntelligence: AppleIntelligenceNoteCaptureIntelligenceService(),
                voiceCaptureInterpretation: AppleIntelligenceVoiceCaptureInterpretationService(),
                companionRelayHost: CompanionRelayNotesAssistantHost(
                    assistantFactory: { [repository] in
                        AppleIntelligenceNotesAssistant(repository: repository)
                    },
                    interpretationFactory: {
                        AppleIntelligenceVoiceCaptureInterpretationService()
                    }
                )
            )
        } else {
            let localAssistant = DeterministicNotesAssistant(repository: repository)
            return RuntimeServices(
                audioFileStore: audioFileStore,
                audioRecorder: audioRecorder,
                speechTranscriber: speechTranscriber,
                textToSpeech: textToSpeech,
                notesAssistant: localAssistant,
                noteCaptureIntelligence: UnavailableNoteCaptureIntelligenceService(
                    reason: "AI-assisted capture requires Apple Intelligence on iOS 26 or newer."
                ),
                voiceCaptureInterpretation: UnavailableVoiceCaptureInterpretationService(
                    reason: "Voice command routing requires Apple Intelligence on iOS 26 or newer."
                ),
                companionRelayHost: CompanionRelayNotesAssistantHost(
                    assistantFactory: { [repository] in
                        DeterministicNotesAssistant(repository: repository)
                    },
                    interpretationFactory: {
                        UnavailableVoiceCaptureInterpretationService(
                            reason: "Voice command routing requires Apple Intelligence on iOS 26 or newer."
                        )
                    }
                )
            )
        }
        #else
        return RuntimeServices(
            audioFileStore: audioFileStore,
            audioRecorder: audioRecorder,
            speechTranscriber: speechTranscriber,
            textToSpeech: textToSpeech,
            notesAssistant: DeterministicNotesAssistant(repository: repository),
            noteCaptureIntelligence: UnavailableNoteCaptureIntelligenceService(
                reason: "AI-assisted capture is unavailable on this device."
            ),
            voiceCaptureInterpretation: UnavailableVoiceCaptureInterpretationService(
                reason: "Voice command routing is unavailable on this device."
            ),
            companionRelayHost: CompanionRelayNotesAssistantHost(
                assistantFactory: { [repository] in
                    DeterministicNotesAssistant(repository: repository)
                },
                interpretationFactory: {
                    UnavailableVoiceCaptureInterpretationService(
                        reason: "Voice command routing is unavailable on this device."
                    )
                }
            )
        )
        #endif
        #endif
    }
}
