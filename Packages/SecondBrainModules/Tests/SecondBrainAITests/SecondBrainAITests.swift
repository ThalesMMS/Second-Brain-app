import Foundation
import Testing
@testable import SecondBrainAI
@testable import SecondBrainDomain
@testable import SecondBrainPersistence

#if os(iOS) && canImport(FoundationModels)
struct SecondBrainAITests {
    @Test
    @MainActor
    func deterministicAssistantReturnsRelevantSnippets() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let first = try await persistence.repository.createNote(
            title: "Oncology follow-up",
            body: "Review MRI liver next week",
            source: .manual,
            initialEntryKind: .creation
        )
        _ = try await persistence.repository.createNote(
            title: "General inbox",
            body: "Buy coffee beans",
            source: .manual,
            initialEntryKind: .creation
        )
        let assistant = DeterministicNotesAssistant(repository: persistence.repository)

        let response = try await assistant.process("oncology")

        #expect(response.text.contains("Oncology follow-up"))
        #expect(response.referencedNoteIDs.contains(first.id))
    }

    @Test
    @MainActor
    func deterministicAssistantReportsReducedFunctionalityWithoutBecomingUnavailable() throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let assistant = DeterministicNotesAssistant(repository: persistence.repository)

        #expect(assistant.capabilityState == .available)
        switch assistant.status {
        case let .reducedFunctionality(reason):
            #expect(reason.contains("Falling back to deterministic retrieval"))
        case nil:
            Issue.record("Expected deterministic assistant to expose reduced functionality status.")
        }
    }

    @Test
    @MainActor
    func toolboxCreatesPendingEditThenConfirmAppliesIt() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let note = try await persistence.repository.createNote(
            title: "Rounds",
            body: "Check CT head",
            source: .manual,
            initialEntryKind: .creation
        )
        let toolbox = NotesToolbox(
            repository: persistence.repository,
            editIntelligence: MockNoteEditIntelligenceService(
                proposal: NoteEditProposal(
                    noteID: note.id,
                    scope: .wholeBody,
                    updatedTitle: note.displayTitle,
                    updatedBody: "1. Check CT head\n2. Review chest CT",
                    targetExcerpt: nil,
                    changeSummary: "Restructure the note as a checklist.",
                    clarificationQuestion: nil
                )
            )
        )

        let firstResponse = try await toolbox.edit(
            noteID: note.id.uuidString,
            instruction: "transforme isso numa checklist"
        )
        let confirmation = try await toolbox.resolvePendingEdit(decision: "confirm")
        let updated = try await persistence.repository.loadNote(id: note.id)

        #expect(firstResponse.contains("Reply \"confirm\""))
        #expect(confirmation.contains("Updated note"))
        #expect(updated?.body == "1. Check CT head\n2. Review chest CT")
        #expect(toolbox.currentInteractionState() == .none)
    }

    @Test
    @MainActor
    func toolboxRejectsWhitespaceOnlyAppend() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let note = try await persistence.repository.createNote(
            title: "Shopping list",
            body: "Banana",
            source: .manual,
            initialEntryKind: .creation
        )
        let toolbox = NotesToolbox(
            repository: persistence.repository,
            editIntelligence: MockNoteEditIntelligenceService(
                proposal: NoteEditProposal(
                    noteID: note.id,
                    scope: .wholeBody,
                    updatedTitle: note.displayTitle,
                    updatedBody: note.body,
                    targetExcerpt: nil,
                    changeSummary: "No-op",
                    clarificationQuestion: nil
                )
            )
        )

        let response = try await toolbox.append(reference: note.displayTitle, content: "   \n ")
        let reloaded = try await persistence.repository.loadNote(id: note.id)

        #expect(response == "No changes; nothing to append.")
        #expect(reloaded?.body == "Banana")
        #expect(reloaded?.entries.count == 1)
    }

#if canImport(WatchConnectivity)
    @Test
    func companionRelayCodecRoundTripsRequestsAndResponses() throws {
        let id = UUID()
        let assistantRequest = CompanionRelayMessageCodec.assistantRequest(
            id: id,
            prompt: "replace banana with avocado"
        )
        let decodedRequest = try #require(CompanionRelayMessageCodec.decodeAssistantRequest(assistantRequest))
        let assistantResponse = try CompanionRelayMessageCodec.decodeAssistantResponse(
            CompanionRelayMessageCodec.assistantResponse(
                id: id,
                response: NotesAssistantResponse(
                    text: "Updated note Shopping list.",
                    referencedNoteIDs: [id],
                    interaction: .pendingEditConfirmation
                )
            )
        )
        let interpretationRequest = CompanionRelayMessageCodec.voiceInterpretationRequest(
            id: id,
            transcript: "show my shopping list",
            locale: Locale(identifier: "en_US")
        )
        let decodedInterpretationRequest = try #require(
            CompanionRelayMessageCodec.decodeVoiceInterpretationRequest(interpretationRequest)
        )
        let interpretation = try CompanionRelayMessageCodec.decodeVoiceInterpretationResponse(
            CompanionRelayMessageCodec.voiceInterpretationResponse(
                id: id,
                interpretation: VoiceCaptureInterpretation(
                    intent: .assistantCommand,
                    normalizedText: "show my shopping list"
                )
            )
        )

        #expect(decodedRequest.id == id)
        #expect(decodedRequest.prompt == "replace banana with avocado")
        #expect(assistantResponse.text == "Updated note Shopping list.")
        #expect(assistantResponse.referencedNoteIDs == [id])
        #expect(assistantResponse.interaction == .pendingEditConfirmation)
        #expect(decodedInterpretationRequest.localeIdentifier == "en_US")
        #expect(interpretation.intent == .assistantCommand)
        #expect(interpretation.normalizedText == "show my shopping list")
    }
#endif

#if os(iOS) && canImport(WatchConnectivity)
    @Test
    @MainActor
    func relayCoordinatorRejectsUnavailableAssistant() async {
        let coordinator = CompanionRelayNotesAssistantHostCoordinator(
            assistantFactory: {
                MockNotesAssistantService(
                    capabilityState: .unavailable(reason: "Apple Intelligence is unavailable on this device."),
                    response: NotesAssistantResponse(text: "", referencedNoteIDs: [])
                )
            },
            interpretationFactory: {
                MockVoiceCaptureInterpretationService()
            }
        )

        let result = await coordinator.process(prompt: "troque feijão por ervilha", conversationID: UUID())

        switch result {
        case .success:
            Issue.record("Expected failure for unavailable assistant.")
        case let .failure(error):
            #expect(error.localizedDescription.contains("Apple Intelligence is unavailable"))
        }
    }
#endif

    @Test
    @MainActor
    func unavailableVoiceCaptureServiceInterpretThrowsUnavailableReason() async {
        let service = UnavailableVoiceCaptureInterpretationService(reason: "Voice routing requires iOS 26.")

        await #expect(throws: VoiceCaptureInterpretationError.self) {
            _ = try await service.interpret(transcript: "hello", locale: .current)
        }
    }

    // MARK: - DeterministicNotesAssistant async (process uses await repository.snippets)

    @Test
    @MainActor
    func deterministicAssistantReturnsNoResultsMessageWhenNoNotesMatch() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        _ = try await persistence.repository.createNote(
            title: "Shopping list",
            body: "Milk and eggs",
            source: .manual,
            initialEntryKind: .creation
        )
        let assistant = DeterministicNotesAssistant(repository: persistence.repository)

        let response = try await assistant.process("oncology MRI liver")

        #expect(response.text.contains("could not find"))
        #expect(response.referencedNoteIDs.isEmpty)
    }

    @Test
    @MainActor
    func deterministicAssistantReferencesMultipleMatchingNotes() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let first = try await persistence.repository.createNote(
            title: "Oncology follow-up",
            body: "Review MRI liver next week",
            source: .manual,
            initialEntryKind: .creation
        )
        let second = try await persistence.repository.createNote(
            title: "Radiology request",
            body: "Order MRI of liver and contrast study",
            source: .manual,
            initialEntryKind: .creation
        )
        let assistant = DeterministicNotesAssistant(repository: persistence.repository)

        let response = try await assistant.process("MRI liver")

        #expect(response.referencedNoteIDs.count >= 2)
        #expect(response.referencedNoteIDs.contains(first.id))
        #expect(response.referencedNoteIDs.contains(second.id))
    }

    // MARK: - UnavailableNoteCaptureIntelligenceService Sendable (no longer @MainActor)

    @Test
    func unavailableNoteCaptureIntelligenceServiceThrowsFromNonMainActorContext() async {
        // This test verifies the service is callable from any concurrency context
        // (it was previously @MainActor; it is now @unchecked Sendable and callable anywhere)
        let service = UnavailableNoteCaptureIntelligenceService(reason: "AI unavailable in tests.")

        #expect(service.capabilityState == .unavailable(reason: "AI unavailable in tests."))

        await #expect(throws: CaptureIntelligenceError.self) {
            _ = try await service.refineTypedNote(title: "t", body: "b", locale: .current)
        }

        await #expect(throws: CaptureIntelligenceError.self) {
            _ = try await service.refineTranscript(title: "t", transcript: "transcript", locale: .current)
        }
    }

    // MARK: - NotesToolbox async (search and read use await repository)

    @Test
    @MainActor
    func toolboxSearchReturnsFormattedSnippetsForMatchingNotes() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        _ = try await persistence.repository.createNote(
            title: "Project roadmap",
            body: "Outline Q3 milestones",
            source: .manual,
            initialEntryKind: .creation
        )
        let toolbox = NotesToolbox(
            repository: persistence.repository,
            editIntelligence: MockNoteEditIntelligenceService(
                proposal: NoteEditProposal(
                    noteID: UUID(),
                    scope: .wholeBody,
                    updatedTitle: "",
                    updatedBody: "",
                    targetExcerpt: nil,
                    changeSummary: "",
                    clarificationQuestion: nil
                )
            )
        )

        let result = try await toolbox.search(query: "roadmap")

        #expect(result.contains("Project roadmap"))
    }

    @Test
    @MainActor
    func toolboxSearchReturnsEmptyMessageWhenNoMatches() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        _ = try await persistence.repository.createNote(
            title: "Shopping list",
            body: "Eggs and milk",
            source: .manual,
            initialEntryKind: .creation
        )
        let toolbox = NotesToolbox(
            repository: persistence.repository,
            editIntelligence: MockNoteEditIntelligenceService(
                proposal: NoteEditProposal(
                    noteID: UUID(),
                    scope: .wholeBody,
                    updatedTitle: "",
                    updatedBody: "",
                    targetExcerpt: nil,
                    changeSummary: "",
                    clarificationQuestion: nil
                )
            )
        )

        let result = try await toolbox.search(query: "xyzzy-unrelated-nonsense")

        #expect(result.contains("No matching notes"))
    }

    @Test
    @MainActor
    func toolboxReadReturnsMissingMessageForUnknownReference() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let toolbox = NotesToolbox(
            repository: persistence.repository,
            editIntelligence: MockNoteEditIntelligenceService(
                proposal: NoteEditProposal(
                    noteID: UUID(),
                    scope: .wholeBody,
                    updatedTitle: "",
                    updatedBody: "",
                    targetExcerpt: nil,
                    changeSummary: "",
                    clarificationQuestion: nil
                )
            )
        )

        let result = try await toolbox.read(reference: "xyzzy-no-such-note")

        #expect(result.contains("No note matched"))
    }

    @Test
    @MainActor
    func toolboxCreateNoteInsertsNoteInRepository() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let toolbox = NotesToolbox(
            repository: persistence.repository,
            editIntelligence: MockNoteEditIntelligenceService(
                proposal: NoteEditProposal(
                    noteID: UUID(),
                    scope: .wholeBody,
                    updatedTitle: "",
                    updatedBody: "",
                    targetExcerpt: nil,
                    changeSummary: "",
                    clarificationQuestion: nil
                )
            )
        )

        let message = try await toolbox.create(title: "Toolbox note", body: "Body text")

        #expect(message.contains("Toolbox note"))
        let summaries = try await persistence.repository.listNotes(matching: nil)
        #expect(summaries.contains(where: { $0.title == "Toolbox note" }))
    }
}

private final class MockNoteEditIntelligenceService: NoteEditIntelligenceService, @unchecked Sendable {
    let proposal: NoteEditProposal

    init(proposal: NoteEditProposal) {
        self.proposal = proposal
    }

    var capabilityState: AssistantCapabilityState {
        .available
    }

    func proposeEdit(
        noteID: UUID,
        title: String,
        body: String,
        instruction: String,
        locale: Locale
    ) async throws -> NoteEditProposal {
        proposal
    }
}

@MainActor
private final class MockNotesAssistantService: NotesAssistantService {
    let capabilityState: AssistantCapabilityState
    private let response: NotesAssistantResponse

    init(capabilityState: AssistantCapabilityState, response: NotesAssistantResponse) {
        self.capabilityState = capabilityState
        self.response = response
    }

    func prewarm() {}

    func resetConversation() {}

    func process(_ input: String) async throws -> NotesAssistantResponse {
        if case let .unavailable(reason) = capabilityState {
            throw NotesAssistantError.unavailable(reason)
        }
        return response
    }
}

private final class MockVoiceCaptureInterpretationService: VoiceCaptureInterpretationService, @unchecked Sendable {
    let capabilityState: AssistantCapabilityState
    private let result: VoiceCaptureInterpretation

    init(
        capabilityState: AssistantCapabilityState = .available,
        result: VoiceCaptureInterpretation = VoiceCaptureInterpretation(
            intent: .assistantCommand,
            normalizedText: "show my shopping list"
        )
    ) {
        self.capabilityState = capabilityState
        self.result = result
    }

    func interpret(transcript: String, locale: Locale) async throws -> VoiceCaptureInterpretation {
        if case let .unavailable(reason) = capabilityState {
            throw VoiceCaptureInterpretationError.unavailable(reason)
        }
        return result
    }
}
#endif
