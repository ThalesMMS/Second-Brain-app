import Foundation
import Testing
@testable import SecondBrainAI
@testable import SecondBrainDomain
@testable import SecondBrainPersistence

// MARK: - DeterministicNotesAssistant: Additional Coverage

@MainActor
struct DeterministicNotesAssistantAdditionalTests {

    // MARK: capabilityState

    @Test
    func deterministicAssistantCapabilityStateIsAlwaysAvailable() throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let assistant = DeterministicNotesAssistant(repository: persistence.repository)

        // Even without notes, it should always report available
        #expect(assistant.capabilityState == .available)
    }

    // MARK: status

    @Test
    func deterministicAssistantStatusMentionsDeterministicRetrieval() throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let assistant = DeterministicNotesAssistant(repository: persistence.repository)

        switch assistant.status {
        case let .reducedFunctionality(reason):
            #expect(reason.contains("deterministic retrieval"))
        case nil:
            Issue.record("Expected a non-nil status from DeterministicNotesAssistant.")
        }
    }

    @Test
    func deterministicAssistantStatusMentionsAppleIntelligenceUnavailability() throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let assistant = DeterministicNotesAssistant(repository: persistence.repository)

        switch assistant.status {
        case let .reducedFunctionality(reason):
            #expect(reason.contains("Apple Intelligence"))
        case nil:
            Issue.record("Expected a non-nil status from DeterministicNotesAssistant.")
        }
    }

    // MARK: process – empty repository

    @Test
    func deterministicAssistantProcessReturnsNoNotesMessageForEmptyRepository() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let assistant = DeterministicNotesAssistant(repository: persistence.repository)

        let response = try await assistant.process("anything")

        #expect(response.text.contains("could not find"))
        #expect(response.referencedNoteIDs.isEmpty)
    }

    // MARK: process – formatted bullet list

    @Test
    func deterministicAssistantProcessIncludesNoteTitleInResponseText() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        _ = try await persistence.repository.createNote(
            title: "Radiology protocol",
            body: "Order CT with contrast for liver",
            source: .manual,
            initialEntryKind: .creation
        )
        let assistant = DeterministicNotesAssistant(repository: persistence.repository)

        let response = try await assistant.process("radiology")

        #expect(response.text.contains("Radiology protocol"))
    }

    @Test
    func deterministicAssistantProcessIncludesNoteExcerptInResponseText() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        _ = try await persistence.repository.createNote(
            title: "Pharmacy reminder",
            body: "Refill metformin prescription before the end of the month",
            source: .manual,
            initialEntryKind: .creation
        )
        let assistant = DeterministicNotesAssistant(repository: persistence.repository)

        let response = try await assistant.process("metformin")

        #expect(response.text.contains("metformin"))
    }

    @Test
    func deterministicAssistantProcessFormatsResponseAsBulletList() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        _ = try await persistence.repository.createNote(
            title: "ICU discharge checklist",
            body: "Review labs, confirm medication reconciliation",
            source: .manual,
            initialEntryKind: .creation
        )
        let assistant = DeterministicNotesAssistant(repository: persistence.repository)

        let response = try await assistant.process("ICU")

        // The deterministic assistant formats as "• title: excerpt"
        #expect(response.text.contains("•"))
    }

    @Test
    func deterministicAssistantProcessReturnsNonEmptyReferencedNoteIDsWhenMatchFound() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let note = try await persistence.repository.createNote(
            title: "Blood pressure log",
            body: "Morning BP 130/82, evening BP 128/80",
            source: .manual,
            initialEntryKind: .creation
        )
        let assistant = DeterministicNotesAssistant(repository: persistence.repository)

        let response = try await assistant.process("blood pressure")

        #expect(response.referencedNoteIDs.contains(note.id))
    }

    // MARK: process – interaction state

    @Test
    func deterministicAssistantProcessResponseInteractionStateIsNone() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        _ = try await persistence.repository.createNote(
            title: "Any note",
            body: "Any body",
            source: .manual,
            initialEntryKind: .creation
        )
        let assistant = DeterministicNotesAssistant(repository: persistence.repository)

        let response = try await assistant.process("any")

        #expect(response.interaction == .none)
    }

    @Test
    func deterministicAssistantNoMatchResponseInteractionStateIsNone() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let assistant = DeterministicNotesAssistant(repository: persistence.repository)

        let response = try await assistant.process("nothing matches this")

        #expect(response.interaction == .none)
    }

    // MARK: prewarm and resetConversation (no-ops)

    @Test
    func deterministicAssistantPrewarmIsANoOp() throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let assistant = DeterministicNotesAssistant(repository: persistence.repository)

        // prewarm should not throw or change observable state
        assistant.prewarm()
        #expect(assistant.capabilityState == .available)
    }

    @Test
    func deterministicAssistantResetConversationIsANoOp() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        _ = try await persistence.repository.createNote(
            title: "Reset test note",
            body: "Searchable body",
            source: .manual,
            initialEntryKind: .creation
        )
        let assistant = DeterministicNotesAssistant(repository: persistence.repository)

        assistant.resetConversation()

        // After reset, the assistant should still be able to process queries normally
        let response = try await assistant.process("reset test note")
        #expect(response.text.contains("Reset test note"))
    }
}

// MARK: - UnavailableNoteCaptureIntelligenceService: Additional Coverage

struct UnavailableNoteCaptureIntelligenceServiceTests {

    @Test
    func unavailableServiceCapabilityStateCarriesProvidedReason() {
        let reason = "Device is not eligible for Apple Intelligence."
        let service = UnavailableNoteCaptureIntelligenceService(reason: reason)

        #expect(service.capabilityState == .unavailable(reason: reason))
    }

    @Test
    func unavailableServiceRefineTypedNoteThrowsCaptureIntelligenceError() async {
        let service = UnavailableNoteCaptureIntelligenceService(reason: "Test reason")

        await #expect(throws: CaptureIntelligenceError.self) {
            _ = try await service.refineTypedNote(title: "Title", body: "Body", locale: .current)
        }
    }

    @Test
    func unavailableServiceRefineTranscriptThrowsCaptureIntelligenceError() async {
        let service = UnavailableNoteCaptureIntelligenceService(reason: "Test reason")

        await #expect(throws: CaptureIntelligenceError.self) {
            _ = try await service.refineTranscript(title: "Title", transcript: "Transcript text", locale: .current)
        }
    }

    @Test
    func unavailableServiceRefineTypedNoteErrorCarriesReason() async {
        let reason = "Apple Intelligence is turned off."
        let service = UnavailableNoteCaptureIntelligenceService(reason: reason)

        do {
            _ = try await service.refineTypedNote(title: "T", body: "B", locale: .current)
            Issue.record("Expected an error to be thrown.")
        } catch CaptureIntelligenceError.unavailable(let message) {
            #expect(message == reason)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test
    func unavailableServiceRefineTranscriptErrorCarriesReason() async {
        let reason = "Model is not ready yet."
        let service = UnavailableNoteCaptureIntelligenceService(reason: reason)

        do {
            _ = try await service.refineTranscript(title: "T", transcript: "Hello world", locale: .current)
            Issue.record("Expected an error to be thrown.")
        } catch CaptureIntelligenceError.unavailable(let message) {
            #expect(message == reason)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

// MARK: - UnavailableVoiceCaptureInterpretationService: Additional Coverage

struct UnavailableVoiceCaptureInterpretationServiceTests {

    @Test
    func unavailableServiceCapabilityStateCarriesProvidedReason() {
        let reason = "Companion relay requires paired iPhone."
        let service = UnavailableVoiceCaptureInterpretationService(reason: reason)

        #expect(service.capabilityState == .unavailable(reason: reason))
    }

    @Test
    func unavailableServiceInterpretThrowsVoiceCaptureInterpretationError() async {
        let service = UnavailableVoiceCaptureInterpretationService(reason: "Test reason")

        await #expect(throws: VoiceCaptureInterpretationError.self) {
            _ = try await service.interpret(transcript: "hello world", locale: .current)
        }
    }

    @Test
    func unavailableServiceInterpretErrorCarriesReason() async {
        let reason = "Voice routing requires iOS 26."
        let service = UnavailableVoiceCaptureInterpretationService(reason: reason)

        do {
            _ = try await service.interpret(transcript: "test", locale: .current)
            Issue.record("Expected an error to be thrown.")
        } catch VoiceCaptureInterpretationError.unavailable(let message) {
            #expect(message == reason)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test
    func unavailableServiceIsCallableFromNonMainActorContext() async {
        // Verifies @unchecked Sendable conformance allows cross-actor usage
        let service = UnavailableVoiceCaptureInterpretationService(reason: "unavailable")

        await #expect(throws: VoiceCaptureInterpretationError.self) {
            _ = try await service.interpret(transcript: "any transcript", locale: Locale(identifier: "de_DE"))
        }
    }
}