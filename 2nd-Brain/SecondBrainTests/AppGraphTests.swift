import Foundation
import Testing
import SecondBrainComposition
import SecondBrainDomain
@testable import SecondBrain

private extension AppGraph.UITestConfiguration {
    /// Standard dataset wired for the pending-edit voice scenario.
    static let pendingEditVoice = AppGraph.UITestConfiguration(
        dataset: .standard,
        assistant: .pendingEdit,
        voice: .assistantPendingEdit,
        microphonePermission: .granted
    )
}

@Suite
struct AppGraphTests {
    @Test
    @MainActor
    func uiTestGraphStandardDatasetSeedsStableNotes() async throws {
        let graph = try AppGraph.uiTest()

        let notes = try await graph.listNotes.execute(matching: nil)
        #expect(notes.count == 3)
        #expect(notes.map(\.title) == ["Oncology reminders", "Residency planning", "Shopping list"])
        #expect(
            notes.map(\.id.uuidString) == [
                "00000000-0000-0000-0000-000000000103",
                "00000000-0000-0000-0000-000000000102",
                "00000000-0000-0000-0000-000000000101",
            ]
        )

        let shoppingList = try await graph.loadNote.execute(id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!)
        #expect(shoppingList?.body == "Milk\nEggs\nBread")
        #expect(shoppingList?.entries.count == 1)
    }

    @Test
    @MainActor
    func uiTestGraphEmptyDatasetStartsWithoutNotes() async throws {
        let graph = try AppGraph.uiTest(
            .init(dataset: .empty)
        )

        let notes = try await graph.listNotes.execute(matching: nil)
        #expect(notes.isEmpty)
    }

    @Test
    @MainActor
    func uiTestGraphAssistantPendingEditConfirmsVoiceRoutedChange() async throws {
        let graph = try AppGraph.uiTest(.pendingEditVoice)

        let result = try await graph.executeUITestVoiceCapture()

        switch result {
        case let .assistantResponse(response, transcript):
            #expect(transcript == "Add butter to the shopping list.")
            #expect(response.interaction == .pendingEditConfirmation)
            #expect(response.referencedNoteIDs == [UUID(uuidString: "00000000-0000-0000-0000-000000000101")!])
        case .createdNote:
            Issue.record("Expected a pending assistant response for the UI test voice scenario.")
        }

        let confirmation = try await graph.askNotes.execute("confirm")
        #expect(confirmation.interaction == .none)
        #expect(confirmation.referencedNoteIDs == [UUID(uuidString: "00000000-0000-0000-0000-000000000101")!])

        let shoppingList = try await graph.loadNote.execute(id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!)
        #expect(shoppingList?.body == "Milk\nEggs\nBread\nButter")
    }

    @Test
    @MainActor
    func uiTestGraphAssistantPendingEditCancelsWithoutMutatingTheSeededNote() async throws {
        let graph = try AppGraph.uiTest(.pendingEditVoice)

        _ = try await graph.executeUITestVoiceCapture()

        let cancellation = try await graph.askNotes.execute("cancel")
        #expect(cancellation.interaction == .none)
        #expect(cancellation.referencedNoteIDs == [UUID(uuidString: "00000000-0000-0000-0000-000000000101")!])

        let shoppingList = try await graph.loadNote.execute(id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!)
        #expect(shoppingList?.body == "Milk\nEggs\nBread")
    }

    @Test
    @MainActor
    func uiTestGraphWithFixedReplyReturnsStubAssistantResponse() async throws {
        let graph = try AppGraph.uiTest(
            .init(dataset: .standard, assistant: .fixedReply)
        )

        let response = try await graph.askNotes.execute("Anything you want to ask")

        #expect(response.text == "Stub assistant reply from UI test mode.")
        #expect(response.referencedNoteIDs.isEmpty)
    }

    @Test
    @MainActor
    func uiTestGraphWithDraftFallbackVoiceCreatesNewNoteFromTranscript() async throws {
        let graph = try AppGraph.uiTest(
            .init(dataset: .standard, assistant: .fixedReply, voice: .draftFallback)
        )

        let result = try await graph.executeUITestVoiceCapture()

        switch result {
        case let .assistantResponse(response, transcript):
            #expect(transcript == "Call the residency office tomorrow morning.")
            #expect(response.text.contains("disabled"))
        case .createdNote:
            Issue.record("Expected draftFallback to preserve the transcript without creating a note.")
        }
    }

    @Test
    @MainActor
    func uiTestGraphWithNewNoteVoiceCreatesNoteWithOatMilkTranscript() async throws {
        let graph = try AppGraph.uiTest(
            .init(dataset: .empty, assistant: .deterministicSearch, voice: .newNote)
        )

        let initialNotes = try await graph.listNotes.execute(matching: nil)
        #expect(initialNotes.isEmpty)

        let result = try await graph.executeUITestVoiceCapture()

        switch result {
        case let .createdNote(note):
            #expect(note.body.contains("Buy oat milk on the way home."))
        case .assistantResponse:
            Issue.record("Expected a created note for the newNote voice scenario.")
        }

        let afterNotes = try await graph.listNotes.execute(matching: nil)
        #expect(afterNotes.count == 1)
    }

    @Test
    @MainActor
    func uiTestGraphConfirmWithNoPendingEditReturnsExplanatoryMessage() async throws {
        let graph = try AppGraph.uiTest(
            .init(dataset: .standard, assistant: .pendingEdit)
        )

        // Confirm without first triggering a pending edit
        let response = try await graph.askNotes.execute("confirm")

        #expect(response.text.contains("no pending edit"))
        #expect(response.referencedNoteIDs.isEmpty)
    }

    @Test
    @MainActor
    func uiTestGraphCancelWithNoPendingEditReturnsExplanatoryMessage() async throws {
        let graph = try AppGraph.uiTest(
            .init(dataset: .standard, assistant: .pendingEdit)
        )

        // Cancel without first triggering a pending edit
        let response = try await graph.askNotes.execute("cancel")

        #expect(response.text.contains("no pending edit"))
        #expect(response.referencedNoteIDs.isEmpty)
    }

    @Test
    @MainActor
    func uiTestGraphPendingEditAppendsButterOnlyOnce() async throws {
        let graph = try AppGraph.uiTest(.pendingEditVoice)

        // Trigger and confirm first pending edit (adds Butter)
        _ = try await graph.executeUITestVoiceCapture()
        _ = try await graph.askNotes.execute("confirm")

        // Trigger again - Butter is already present, body should not gain a second Butter
        _ = try await graph.executeUITestVoiceCapture()
        _ = try await graph.askNotes.execute("confirm")

        let shoppingList = try await graph.loadNote.execute(id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!)
        let butterCount = shoppingList?.body.components(separatedBy: "Butter").count.advanced(by: -1) ?? 0
        #expect(butterCount == 1)
    }

    @Test
    @MainActor
    func uiTestGraphDeterministicSearchAssistantSearchesSeededNotes() async throws {
        let graph = try AppGraph.uiTest(
            .init(dataset: .standard, assistant: .deterministicSearch)
        )

        let response = try await graph.askNotes.execute("shopping list")

        // DeterministicNotesAssistant should find the shopping list note
        #expect(response.referencedNoteIDs.contains(UUID(uuidString: "00000000-0000-0000-0000-000000000101")!))
    }

    @Test
    @MainActor
    func appGraphInMemoryComposesRepositoryAndUseCases() async throws {
        let graph = try makeInMemoryGraph()

        let created = try await graph.createNote.execute(
            title: "Inbox",
            body: "Buy coffee beans",
            source: .manual
        )
        let loaded = try await graph.loadNote.execute(id: created.id)

        #expect(loaded?.displayTitle == "Inbox")
        #expect(loaded?.body == "Buy coffee beans")
    }

    @Test
    @MainActor
    func appGraphModelContainerIsAccessibleAsPublicProperty() throws {
        let graph = try makeInMemoryGraph()

        // modelContainer is the new public API that replaces graph.persistenceController.container.
        // Verify it is accessible and stable across repeated accesses.
        let first = graph.modelContainer
        let second = graph.modelContainer

        #expect(first === second)
    }

    // MARK: - Additional edge cases

    @Test
    @MainActor
    func appGraphDeleteNoteRemovesItFromListNotes() async throws {
        let graph = try makeInMemoryGraph()
        let created = try await graph.createNote.execute(
            title: "Temporary",
            body: "To be deleted",
            source: .manual
        )

        try await graph.deleteNote.execute(noteID: created.id)

        let notes = try await graph.listNotes.execute(matching: nil)
        #expect(notes.isEmpty)
    }

    @Test
    @MainActor
    func appGraphSetNotePinnedUpdatesPinnedStateAndOrdering() async throws {
        let graph = try makeInMemoryGraph()
        let older = try await graph.createNote.execute(
            title: "Reference",
            body: "Pinned",
            source: .manual
        )
        let newer = try await graph.createNote.execute(
            title: "Inbox",
            body: "Unpinned",
            source: .manual
        )

        try await graph.setNotePinned.execute(noteID: older.id, isPinned: true)

        let loaded = try await graph.loadNote.execute(id: older.id)
        let notes = try await graph.listNotes.execute(matching: nil)

        #expect(loaded?.isPinned == true)
        #expect(notes.map(\.id) == [older.id, newer.id])
        #expect(notes.first?.isPinned == true)
    }

    @Test
    @MainActor
    func noteDetailViewModelTogglePinnedPreservesDraftEdits() async throws {
        let graph = try makeInMemoryGraph()
        let note = try await graph.createNote.execute(
            title: "Reference",
            body: "Body",
            source: .manual
        )
        let viewModel = NoteDetailViewModel(noteID: note.id, graph: graph)
        await viewModel.load()
        viewModel.draftTitle = "Unsaved title"
        viewModel.draftBody = "Unsaved body"

        await viewModel.togglePinned()

        #expect(viewModel.note?.isPinned == true)
        #expect(viewModel.isTogglingPinned == false)
        #expect(viewModel.draftTitle == "Unsaved title")
        #expect(viewModel.draftBody == "Unsaved body")
    }

    @Test
    @MainActor
    func notesStoreTogglePinnedRefreshesList() async throws {
        let graph = try makeInMemoryGraph()
        let older = try await graph.createNote.execute(title: "Reference", body: "Pinned", source: .manual)
        let newer = try await graph.createNote.execute(title: "Inbox", body: "Unpinned", source: .manual)
        let store = NotesStore(graph: graph)
        await store.refresh()

        await store.togglePinned(noteID: older.id)

        #expect(store.notes.map(\.id) == [older.id, newer.id])
        #expect(store.notes.first?.isPinned == true)
        #expect(store.isTogglingPinned(noteID: older.id) == false)
    }

    @Test
    @MainActor
    func appGraphLoadNoteReturnsNilForUnknownID() async throws {
        let graph = try makeInMemoryGraph()
        let unknownID = UUID()

        let loaded = try await graph.loadNote.execute(id: unknownID)

        #expect(loaded == nil)
    }

    @Test
    @MainActor
    func appGraphListNotesWithMatchingQueryFiltersResults() async throws {
        let graph = try makeInMemoryGraph()
        _ = try await graph.createNote.execute(title: "Grocery list", body: "Eggs and milk", source: .manual)
        _ = try await graph.createNote.execute(title: "Meeting agenda", body: "Discuss roadmap", source: .manual)

        let results = try await graph.listNotes.execute(matching: "grocery")

        #expect(results.count == 1)
        #expect(results.first?.title == "Grocery list")
    }

    @Test
    @MainActor
    func appGraphCreateNoteWithEmptyTitleProducesUntitledDisplayTitle() async throws {
        let graph = try makeInMemoryGraph()

        let created = try await graph.createNote.execute(
            title: "",
            body: "Some content",
            source: .manual
        )

        #expect(created.displayTitle == "Untitled note")
    }

    @Test
    @MainActor
    func uiTestGraphStandardDatasetNoteCountIsStableAcrossMultipleListCalls() async throws {
        let graph = try AppGraph.uiTest()

        let firstCall = try await graph.listNotes.execute(matching: nil)
        let secondCall = try await graph.listNotes.execute(matching: nil)

        // Regression: repeated list calls must not duplicate seeded notes
        #expect(firstCall.count == secondCall.count)
        #expect(firstCall.count == 3)
    }
}
