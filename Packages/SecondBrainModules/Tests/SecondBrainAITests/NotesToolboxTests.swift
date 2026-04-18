import Foundation
import Testing
@testable import SecondBrainAI
@testable import SecondBrainDomain
@testable import SecondBrainPersistence

#if os(iOS) && canImport(FoundationModels)

@MainActor
struct NotesToolboxTests {

    // MARK: - search

    @Test
    func searchIncludesNoteIDInReferencedIDsAfterMatch() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let note = try await persistence.repository.createNote(
            title: "Cardiology rounds",
            body: "Follow up on stress test results",
            source: .manual,
            initialEntryKind: .creation
        )
        let toolbox = makeToolbox(repository: persistence.repository)

        _ = try await toolbox.search(query: "cardiology")
        let ids = toolbox.consumeReferencedNoteIDs()

        #expect(ids.contains(note.id))
    }

    @Test
    func searchDoesNotAccumulateReferencedIDsAcrossCalls() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let alpha = try await persistence.repository.createNote(
            title: "Alpha cardiology",
            body: "Unique alpha marker",
            source: .manual,
            initialEntryKind: .creation
        )
        let beta = try await persistence.repository.createNote(
            title: "Beta dermatology",
            body: "Unique beta marker",
            source: .manual,
            initialEntryKind: .creation
        )
        let toolbox = makeToolbox(repository: persistence.repository)

        _ = try await toolbox.search(query: "alpha")
        let firstBatch = toolbox.consumeReferencedNoteIDs()

        _ = try await toolbox.search(query: "beta")
        let secondBatch = toolbox.consumeReferencedNoteIDs()

        // After consuming IDs, they should not carry over to the next search
        #expect(firstBatch.contains(alpha.id))
        #expect(!firstBatch.contains(beta.id))
        #expect(secondBatch.contains(beta.id))
        #expect(!secondBatch.contains(alpha.id))
    }

    // MARK: - read

    @Test
    func readReturnsFormattedNoteContentWhenFoundByTitle() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let note = try await persistence.repository.createNote(
            title: "Nephrology notes",
            body: "Creatinine trending up over 3 months",
            source: .manual,
            initialEntryKind: .creation
        )
        let toolbox = makeToolbox(repository: persistence.repository)

        let result = try await toolbox.read(reference: note.displayTitle)

        #expect(result.contains("Nephrology notes"))
        #expect(result.contains("Creatinine trending up"))
        #expect(result.contains(note.id.uuidString))
    }

    @Test
    func readReturnsFormattedNoteContentWhenFoundByUUIDString() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let note = try await persistence.repository.createNote(
            title: "UUID reference test",
            body: "This note is found by its UUID",
            source: .manual,
            initialEntryKind: .creation
        )
        let toolbox = makeToolbox(repository: persistence.repository)

        let result = try await toolbox.read(reference: note.id.uuidString)

        #expect(result.contains("UUID reference test"))
        #expect(result.contains(note.id.uuidString))
    }

    @Test
    func readAddsNoteIDToReferencedIDsOnSuccess() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let note = try await persistence.repository.createNote(
            title: "Read tracking test",
            body: "Body text",
            source: .manual,
            initialEntryKind: .creation
        )
        let toolbox = makeToolbox(repository: persistence.repository)

        _ = try await toolbox.read(reference: note.id.uuidString)
        let ids = toolbox.consumeReferencedNoteIDs()

        #expect(ids.contains(note.id))
    }

    @Test
    func readDoesNotAddIDToReferencedIDsWhenNoteNotFound() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let toolbox = makeToolbox(repository: persistence.repository)

        _ = try await toolbox.read(reference: "nonexistent-note-reference")
        let ids = toolbox.consumeReferencedNoteIDs()

        #expect(ids.isEmpty)
    }

    // MARK: - create

    @Test
    func createReturnsConfirmationMessageContainingTitle() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let toolbox = makeToolbox(repository: persistence.repository)

        let message = try await toolbox.create(title: "Meeting notes", body: "Discuss Q4 roadmap")

        #expect(message.contains("Meeting notes"))
    }

    @Test
    func createReturnsConfirmationMessageContainingNoteID() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let toolbox = makeToolbox(repository: persistence.repository)

        let message = try await toolbox.create(title: "Test note", body: "Body text")

        let uuidPattern = #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#
        #expect(message.range(of: uuidPattern, options: .regularExpression) != nil)
    }

    @Test
    func createAddsNewNoteIDToReferencedIDs() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let toolbox = makeToolbox(repository: persistence.repository)

        _ = try await toolbox.create(title: "Tracked note", body: "Body text")
        let ids = toolbox.consumeReferencedNoteIDs()

        #expect(!ids.isEmpty)
    }

    // MARK: - append

    @Test
    func appendReturnsConfirmationMessageOnSuccess() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let note = try await persistence.repository.createNote(
            title: "Lab results",
            body: "Hemoglobin 12.5",
            source: .manual,
            initialEntryKind: .creation
        )
        let toolbox = makeToolbox(repository: persistence.repository)

        let message = try await toolbox.append(reference: note.id.uuidString, content: "Potassium 4.2")

        #expect(message.contains("Appended content"))
        #expect(message.contains("Lab results"))
    }

    @Test
    func appendActuallyAddsContentToNoteBody() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let note = try await persistence.repository.createNote(
            title: "Shopping list",
            body: "Bananas",
            source: .manual,
            initialEntryKind: .creation
        )
        let toolbox = makeToolbox(repository: persistence.repository)

        _ = try await toolbox.append(reference: note.id.uuidString, content: "Avocados")
        let reloaded = try await persistence.repository.loadNote(id: note.id)

        #expect(reloaded?.body.contains("Avocados") == true)
    }

    @Test
    func appendReturnsNothingToAppendForWhitespacePaddedContent() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let note = try await persistence.repository.createNote(
            title: "Empty append test",
            body: "Original body",
            source: .manual,
            initialEntryKind: .creation
        )
        let toolbox = makeToolbox(repository: persistence.repository)

        let message = try await toolbox.append(reference: note.id.uuidString, content: "\t  \n")

        #expect(message == "No changes; nothing to append.")
    }

    @Test
    func appendReturnsNoNoteMatchedWhenReferenceIsUnknown() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let toolbox = makeToolbox(repository: persistence.repository)

        let message = try await toolbox.append(reference: "unknown-reference-xyz", content: "Some content")

        #expect(message.contains("No note matched"))
    }

    @Test
    func appendAddsNoteIDToReferencedIDsOnSuccess() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let note = try await persistence.repository.createNote(
            title: "Append ID tracking",
            body: "Initial body",
            source: .manual,
            initialEntryKind: .creation
        )
        let toolbox = makeToolbox(repository: persistence.repository)

        _ = try await toolbox.append(reference: note.id.uuidString, content: "Additional text")
        let ids = toolbox.consumeReferencedNoteIDs()

        #expect(ids.contains(note.id))
    }

    // MARK: - edit – invalid noteID

    @Test
    func editReturnsNoNoteMatchedForInvalidUUIDString() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let toolbox = makeToolbox(repository: persistence.repository)

        let message = try await toolbox.edit(noteID: "not-a-uuid", instruction: "rewrite it")

        #expect(message.contains("No note matched"))
    }

    @Test
    func editReturnsNoNoteMatchedForNonExistentNoteID() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let toolbox = makeToolbox(repository: persistence.repository)

        let message = try await toolbox.edit(noteID: UUID().uuidString, instruction: "rewrite it")

        #expect(message.contains("No note matched"))
    }

    @Test
    func editTrimsWhitespaceFromNoteIDBeforeParsing() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let note = try await persistence.repository.createNote(
            title: "Edit trimming test",
            body: "Original body",
            source: .manual,
            initialEntryKind: .creation
        )
        let proposal = makeProposal(for: note)
        let toolbox = makeToolbox(repository: persistence.repository, proposal: proposal)

        // Add leading/trailing whitespace and newlines
        let paddedID = "  \n\(note.id.uuidString)\n  "
        let message = try await toolbox.edit(noteID: paddedID, instruction: "clean it up")

        // Should not return "No note matched" since trimming should find the note
        #expect(!message.contains("No note matched"))
    }

    @Test
    func editThrowsUnavailableWhenIntelligenceIsUnavailable() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let note = try await persistence.repository.createNote(
            title: "Intelligence test",
            body: "Body text",
            source: .manual,
            initialEntryKind: .creation
        )
        let toolbox = makeToolboxWithUnavailableIntelligence(
            repository: persistence.repository,
            reason: "AI not available in test"
        )

        await #expect(throws: NotesAssistantError.self) {
            _ = try await toolbox.edit(noteID: note.id.uuidString, instruction: "rewrite it")
        }
    }

    // MARK: - resolvePendingEdit

    @Test
    func resolvePendingEditReturnsValidationMessageForInvalidDecision() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let toolbox = makeToolbox(repository: persistence.repository)

        let message = try await toolbox.resolvePendingEdit(decision: "maybe")

        #expect(message.contains("confirm or cancel"))
    }

    @Test
    func resolvePendingEditReturnsNoPendingEditMessageWhenConfirmingWithNoPendingEdit() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let toolbox = makeToolbox(repository: persistence.repository)

        let message = try await toolbox.resolvePendingEdit(decision: "confirm")

        #expect(message.contains("no pending edit"))
    }

    @Test
    func resolvePendingEditReturnsNoPendingEditMessageWhenCancellingWithNoPendingEdit() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let toolbox = makeToolbox(repository: persistence.repository)

        let message = try await toolbox.resolvePendingEdit(decision: "cancel")

        #expect(message.contains("no pending edit"))
    }

    @Test
    func resolvePendingEditIsCaseInsensitiveForDecision() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let toolbox = makeToolbox(repository: persistence.repository)

        let upperMessage = try await toolbox.resolvePendingEdit(decision: "CONFIRM")
        let mixedMessage = try await toolbox.resolvePendingEdit(decision: "Cancel")

        // Should receive "no pending edit" messages, not "invalid decision"
        #expect(upperMessage.contains("no pending edit"))
        #expect(mixedMessage.contains("no pending edit"))
    }

    @Test
    func resolvePendingEditTrimsWhitespaceFromDecision() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let toolbox = makeToolbox(repository: persistence.repository)

        let message = try await toolbox.resolvePendingEdit(decision: "  confirm  \n")

        // Should accept "confirm" after trimming
        #expect(message.contains("no pending edit"))
    }

    // MARK: - resetConversation

    @Test
    func resetConversationClearsReferencedNoteIDs() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        _ = try await persistence.repository.createNote(
            title: "Reset test",
            body: "Body text",
            source: .manual,
            initialEntryKind: .creation
        )
        let toolbox = makeToolbox(repository: persistence.repository)

        _ = try await toolbox.search(query: "reset test")

        toolbox.resetConversation()
        let idsAfterReset = toolbox.consumeReferencedNoteIDs()

        #expect(idsAfterReset.isEmpty)
    }

    @Test
    func resetConversationSetCurrentInteractionStateToNone() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let note = try await persistence.repository.createNote(
            title: "Pending edit test",
            body: "Body text",
            source: .manual,
            initialEntryKind: .creation
        )
        let proposal = makeProposal(for: note)
        let toolbox = makeToolbox(repository: persistence.repository, proposal: proposal)

        _ = try await toolbox.edit(noteID: note.id.uuidString, instruction: "restructure")

        // After edit, there should be a pending edit
        #expect(toolbox.currentInteractionState() == .pendingEditConfirmation)

        toolbox.resetConversation()

        #expect(toolbox.currentInteractionState() == .none)
    }

    // MARK: - consumeReferencedNoteIDs

    @Test
    func consumeReferencedNoteIDsReturnsSortedByUUIDString() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        _ = try await persistence.repository.createNote(
            title: "Note Alpha",
            body: "About alpha topics",
            source: .manual,
            initialEntryKind: .creation
        )
        _ = try await persistence.repository.createNote(
            title: "Note Beta",
            body: "About beta topics",
            source: .manual,
            initialEntryKind: .creation
        )
        let toolbox = makeToolbox(repository: persistence.repository)

        _ = try await toolbox.search(query: "topics")
        let ids = toolbox.consumeReferencedNoteIDs()

        let sorted = ids.sorted { $0.uuidString < $1.uuidString }
        #expect(ids == sorted)
    }

    @Test
    func consumeReferencedNoteIDsClearsIDsAfterReturn() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        _ = try await persistence.repository.createNote(
            title: "Consume test note",
            body: "This note will be searched",
            source: .manual,
            initialEntryKind: .creation
        )
        let toolbox = makeToolbox(repository: persistence.repository)

        _ = try await toolbox.search(query: "consume test note")
        let firstConsume = toolbox.consumeReferencedNoteIDs()
        let secondConsume = toolbox.consumeReferencedNoteIDs()

        #expect(!firstConsume.isEmpty)
        #expect(secondConsume.isEmpty)
    }

    // MARK: - currentInteractionState

    @Test
    func currentInteractionStateIsNoneInitially() throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let toolbox = makeToolbox(repository: persistence.repository)

        #expect(toolbox.currentInteractionState() == .none)
    }

    @Test
    func currentInteractionStateIsPendingEditConfirmationAfterEdit() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let note = try await persistence.repository.createNote(
            title: "Interaction state test",
            body: "Original body text",
            source: .manual,
            initialEntryKind: .creation
        )
        let proposal = makeProposal(for: note)
        let toolbox = makeToolbox(repository: persistence.repository, proposal: proposal)

        _ = try await toolbox.edit(noteID: note.id.uuidString, instruction: "restructure")

        #expect(toolbox.currentInteractionState() == .pendingEditConfirmation)
    }

    @Test
    func currentInteractionStateReturnsToNoneAfterConfirmation() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let note = try await persistence.repository.createNote(
            title: "Confirm returns none",
            body: "Original content",
            source: .manual,
            initialEntryKind: .creation
        )
        let proposal = makeProposal(for: note)
        let toolbox = makeToolbox(repository: persistence.repository, proposal: proposal)

        _ = try await toolbox.edit(noteID: note.id.uuidString, instruction: "change something")
        _ = try await toolbox.resolvePendingEdit(decision: "confirm")

        #expect(toolbox.currentInteractionState() == .none)
    }

    @Test
    func currentInteractionStateReturnsToNoneAfterCancellation() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let note = try await persistence.repository.createNote(
            title: "Cancel returns none",
            body: "Original content",
            source: .manual,
            initialEntryKind: .creation
        )
        let proposal = makeProposal(for: note)
        let toolbox = makeToolbox(repository: persistence.repository, proposal: proposal)

        _ = try await toolbox.edit(noteID: note.id.uuidString, instruction: "change something")
        _ = try await toolbox.resolvePendingEdit(decision: "cancel")

        #expect(toolbox.currentInteractionState() == .none)
    }
}

// MARK: - Helpers

@MainActor
private func makeToolbox(repository: some NoteRepository) -> NotesToolbox {
    NotesToolbox(
        repository: repository,
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
}

@MainActor
private func makeToolbox(repository: some NoteRepository, proposal: NoteEditProposal) -> NotesToolbox {
    NotesToolbox(
        repository: repository,
        editIntelligence: MockNoteEditIntelligenceService(proposal: proposal)
    )
}

@MainActor
private func makeToolboxWithUnavailableIntelligence(repository: some NoteRepository, reason: String) -> NotesToolbox {
    NotesToolbox(
        repository: repository,
        editIntelligence: UnavailableNoteEditIntelligenceService(reason: reason)
    )
}

private func makeProposal(for note: Note) -> NoteEditProposal {
    NoteEditProposal(
        noteID: note.id,
        scope: .wholeBody,
        updatedTitle: note.displayTitle,
        updatedBody: "Updated body content",
        targetExcerpt: nil,
        changeSummary: "Restructure the note.",
        clarificationQuestion: nil
    )
}

private final class MockNoteEditIntelligenceService: NoteEditIntelligenceService, @unchecked Sendable {
    let proposal: NoteEditProposal

    init(proposal: NoteEditProposal) {
        self.proposal = proposal
    }

    var capabilityState: AssistantCapabilityState { .available }

    func proposeEdit(
        noteID: UUID,
        title: String,
        body: String,
        instruction: String,
        locale: Locale
    ) async throws -> NoteEditProposal {
        NoteEditProposal(
            noteID: noteID,
            scope: proposal.scope,
            updatedTitle: title,
            updatedBody: proposal.updatedBody,
            targetExcerpt: proposal.targetExcerpt,
            changeSummary: proposal.changeSummary,
            clarificationQuestion: proposal.clarificationQuestion
        )
    }
}

private final class UnavailableNoteEditIntelligenceService: NoteEditIntelligenceService, @unchecked Sendable {
    private let reason: String

    init(reason: String) {
        self.reason = reason
    }

    var capabilityState: AssistantCapabilityState {
        .unavailable(reason: reason)
    }

    func proposeEdit(
        noteID: UUID,
        title: String,
        body: String,
        instruction: String,
        locale: Locale
    ) async throws -> NoteEditProposal {
        throw NotesAssistantError.unavailable(reason)
    }
}

#endif
