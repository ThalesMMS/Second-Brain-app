import AppIntents
import Foundation
import Testing
import SecondBrainComposition
import SecondBrainDomain
@testable import SecondBrain

@Suite(.serialized)
struct SecondBrainTests {
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
        let graph = try AppGraph.uiTest(
            .init(
                dataset: .standard,
                assistant: .pendingEdit,
                voice: .assistantPendingEdit,
                microphonePermission: .granted
            )
        )

        let result = try await graph.processVoiceCapture.execute(
            title: "",
            audioURL: makeUITestAudioURL(),
            locale: Locale(identifier: "en_US_POSIX"),
            source: .speechToText
        )

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
        let graph = try AppGraph.uiTest(
            .init(
                dataset: .standard,
                assistant: .pendingEdit,
                voice: .assistantPendingEdit,
                microphonePermission: .granted
            )
        )

        _ = try await graph.processVoiceCapture.execute(
            title: "",
            audioURL: makeUITestAudioURL(),
            locale: Locale(identifier: "en_US_POSIX"),
            source: .speechToText
        )

        let cancellation = try await graph.askNotes.execute("cancel")
        #expect(cancellation.interaction == .none)
        #expect(cancellation.referencedNoteIDs == [UUID(uuidString: "00000000-0000-0000-0000-000000000101")!])

        let shoppingList = try await graph.loadNote.execute(id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!)
        #expect(shoppingList?.body == "Milk\nEggs\nBread")
    }

    // MARK: - UITestConfiguration

    @Test
    func uiTestConfigurationDefaultsToStandardDatasetAndDeterministicSearch() {
        let config = AppGraph.UITestConfiguration()

        #expect(config.dataset == .standard)
        #expect(config.assistant == .deterministicSearch)
        #expect(config.voice == .newNote)
        #expect(config.microphonePermission == .granted)
    }

    @Test
    func uiTestConfigurationCanBeCustomized() {
        let config = AppGraph.UITestConfiguration(
            dataset: .empty,
            assistant: .pendingEdit,
            voice: .draftFallback,
            microphonePermission: .denied
        )

        #expect(config.dataset == .empty)
        #expect(config.assistant == .pendingEdit)
        #expect(config.voice == .draftFallback)
        #expect(config.microphonePermission == .denied)
    }

    @Test
    func uiTestConfigurationDatasetRawValuesRoundTrip() {
        #expect(AppGraph.UITestConfiguration.Dataset(rawValue: "empty") == .empty)
        #expect(AppGraph.UITestConfiguration.Dataset(rawValue: "standard") == .standard)
        #expect(AppGraph.UITestConfiguration.Dataset(rawValue: "unknown") == nil)
        #expect(AppGraph.UITestConfiguration.Dataset.empty.rawValue == "empty")
        #expect(AppGraph.UITestConfiguration.Dataset.standard.rawValue == "standard")
    }

    @Test
    func uiTestConfigurationAssistantRawValuesRoundTrip() {
        #expect(AppGraph.UITestConfiguration.Assistant(rawValue: "deterministicSearch") == .deterministicSearch)
        #expect(AppGraph.UITestConfiguration.Assistant(rawValue: "fixedReply") == .fixedReply)
        #expect(AppGraph.UITestConfiguration.Assistant(rawValue: "pendingEdit") == .pendingEdit)
        #expect(AppGraph.UITestConfiguration.Assistant(rawValue: "invalid") == nil)
        #expect(AppGraph.UITestConfiguration.Assistant.deterministicSearch.rawValue == "deterministicSearch")
        #expect(AppGraph.UITestConfiguration.Assistant.fixedReply.rawValue == "fixedReply")
        #expect(AppGraph.UITestConfiguration.Assistant.pendingEdit.rawValue == "pendingEdit")
    }

    @Test
    func uiTestConfigurationVoiceRawValuesRoundTrip() {
        #expect(AppGraph.UITestConfiguration.Voice(rawValue: "newNote") == .newNote)
        #expect(AppGraph.UITestConfiguration.Voice(rawValue: "assistantPendingEdit") == .assistantPendingEdit)
        #expect(AppGraph.UITestConfiguration.Voice(rawValue: "draftFallback") == .draftFallback)
        #expect(AppGraph.UITestConfiguration.Voice(rawValue: "bogus") == nil)
        #expect(AppGraph.UITestConfiguration.Voice.newNote.rawValue == "newNote")
        #expect(AppGraph.UITestConfiguration.Voice.assistantPendingEdit.rawValue == "assistantPendingEdit")
        #expect(AppGraph.UITestConfiguration.Voice.draftFallback.rawValue == "draftFallback")
    }

    @Test
    func uiTestConfigurationMicrophonePermissionRawValuesRoundTrip() {
        #expect(AppGraph.UITestConfiguration.MicrophonePermission(rawValue: "granted") == .granted)
        #expect(AppGraph.UITestConfiguration.MicrophonePermission(rawValue: "denied") == .denied)
        #expect(AppGraph.UITestConfiguration.MicrophonePermission(rawValue: "unknown") == nil)
        #expect(AppGraph.UITestConfiguration.MicrophonePermission.granted.rawValue == "granted")
        #expect(AppGraph.UITestConfiguration.MicrophonePermission.denied.rawValue == "denied")
    }

    // MARK: - AppGraph.uiTest() additional scenarios

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

        let result = try await graph.processVoiceCapture.execute(
            title: "",
            audioURL: makeUITestAudioURL(),
            locale: Locale(identifier: "en_US_POSIX"),
            source: .speechToText
        )

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

        let result = try await graph.processVoiceCapture.execute(
            title: "",
            audioURL: makeUITestAudioURL(),
            locale: Locale(identifier: "en_US_POSIX"),
            source: .speechToText
        )

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
        let graph = try AppGraph.uiTest(
            .init(
                dataset: .standard,
                assistant: .pendingEdit,
                voice: .assistantPendingEdit,
                microphonePermission: .granted
            )
        )

        // Trigger and confirm first pending edit (adds Butter)
        _ = try await graph.processVoiceCapture.execute(
            title: "",
            audioURL: makeUITestAudioURL(),
            locale: Locale(identifier: "en_US_POSIX"),
            source: .speechToText
        )
        _ = try await graph.askNotes.execute("confirm")

        // Trigger again - Butter is already present, body should not gain a second Butter
        _ = try await graph.processVoiceCapture.execute(
            title: "",
            audioURL: makeUITestAudioURL(),
            locale: Locale(identifier: "en_US_POSIX"),
            source: .speechToText
        )
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
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)

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
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)

        // modelContainer is the new public API that replaces graph.persistenceController.container.
        // Verify it is accessible and stable across repeated accesses.
        let first = graph.modelContainer
        let second = graph.modelContainer

        #expect(first === second)
    }

    @Test
    @MainActor
    func createNoteIntentUsesInjectedGraph() async throws {
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)

        let intent = CreateNoteIntent()
        intent.titleText = "Trip"
        intent.bodyText = "Pack passport"

        _ = try await withInjectedGraph({ graph }) {
            try await intent.perform()
        }

        let notes = try await graph.repository.listNotes(matching: nil)
        let saved = try #require(notes.first)
        #expect(notes.count == 1)
        #expect(saved.title == "Trip")
        #expect(saved.previewText == "Pack passport")
    }

    @Test
    @MainActor
    func appendToNoteIntentUsesInjectedGraph() async throws {
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)
        let original = try await graph.createNote.execute(
            title: "Shopping list",
            body: "Banana",
            source: .manual
        )

        let intent = AppendToNoteIntent()
        intent.note = NoteEntity(note: original)
        intent.content = "Avocado"

        _ = try await withInjectedGraph({ graph }) {
            try await intent.perform()
        }

        let updated = try await graph.repository.loadNote(id: original.id)
        #expect(updated?.body == "Banana\n\nAvocado")
        #expect(updated?.entries.count == 2)
    }

    @Test
    @MainActor
    func readNoteIntentResolvesNoteFromInjectedGraph() async throws {
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)
        let original = try await graph.createNote.execute(
            title: "Meeting",
            body: "Discuss roadmap",
            source: .manual
        )

        let intent = ReadNoteIntent()
        intent.note = NoteEntity(note: original)

        let result = try await withInjectedGraph({ graph }) {
            try await intent.perform()
        }

        let loaded = try await graph.repository.loadNote(id: original.id)
        #expect(loaded?.body == "Discuss roadmap")
        #expect(dialogDescription(of: result).contains("Discuss roadmap"))
    }

    @Test
    @MainActor
    func noteEntityQueryRehydratesExistingNotesByIdentifier() async throws {
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)
        let original = try await graph.createNote.execute(
            title: "Weekly review",
            body: "Summarize progress",
            source: .manual
        )

        let entities = try await withInjectedGraph({ graph }) {
            try await NoteEntityQuery().entities(for: [original.id])
        }

        let entity = try #require(entities.first)
        #expect(entities.count == 1)
        #expect(entity.id == original.id)
        #expect(entity.title == "Weekly review")
    }

    @Test
    @MainActor
    func noteEntityQuerySuggestsRecentNotesFromInjectedGraph() async throws {
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)
        let first = try await graph.createNote.execute(
            title: "First note",
            body: "One",
            source: .manual
        )
        let second = try await graph.createNote.execute(
            title: "Second note",
            body: "Two",
            source: .manual
        )

        let entities = try await withInjectedGraph({ graph }) {
            try await NoteEntityQuery().suggestedEntities()
        }

        #expect(entities.count == 2)
        #expect(Set(entities.map(\.id)) == Set([first.id, second.id]))
    }

    @Test
    @MainActor
    func noteEntityQuerySuggestedEntitiesAreCapped() async throws {
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)

        for index in 0..<12 {
            _ = try await graph.createNote.execute(
                title: "Note \(index)",
                body: "Body \(index)",
                source: .manual
            )
        }

        let entities = try await withInjectedGraph({ graph }) {
            try await NoteEntityQuery().suggestedEntities()
        }

        #expect(entities.count == 10)
        let titles = Set(entities.map(\.title))
        #expect(titles.contains("Note 11"))
        #expect(titles.contains("Note 2"))
        #expect(!titles.contains("Note 1"))
        #expect(!titles.contains("Note 0"))
    }

    @Test
    @MainActor
    func noteEntityQuerySuggestedEntitiesStayCappedAcrossLargeCorpus() async throws {
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)
        try await seedNotes(in: graph, count: 250, titlePrefix: "Note", bodyPrefix: "Body")

        let entities = try await withInjectedGraph({ graph }) {
            try await NoteEntityQuery().suggestedEntities()
        }

        #expect(entities.count == 10)
        let titles = Set(entities.map(\.title))
        #expect(titles.contains("Note 249"))
        #expect(titles.contains("Note 240"))
        #expect(!titles.contains("Note 239"))
        #expect(!titles.contains("Note 0"))
    }

    @Test
    @MainActor
    func noteEntityQueryReturnsMultipleCandidatesForAmbiguousMatches() async throws {
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)
        let planning = try await graph.createNote.execute(
            title: "Roadmap planning",
            body: "Draft next quarter goals",
            source: .manual
        )
        let review = try await graph.createNote.execute(
            title: "Roadmap review",
            body: "Discuss the current roadmap",
            source: .manual
        )

        let entities = try await withInjectedGraph({ graph }) {
            try await NoteEntityQuery().entities(matching: "roadmap")
        }

        #expect(entities.count == 2)
        #expect(Set(entities.map(\.id)) == Set([planning.id, review.id]))
    }

    @Test
    @MainActor
    func noteEntityQuerySearchResultsAreCapped() async throws {
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)

        for index in 0..<12 {
            _ = try await graph.createNote.execute(
                title: "Roadmap \(index)",
                body: "Roadmap details \(index)",
                source: .manual
            )
        }

        let entities = try await withInjectedGraph({ graph }) {
            try await NoteEntityQuery().entities(matching: "roadmap")
        }

        #expect(entities.count == 10)
        let titles = Set(entities.map(\.title))
        #expect(titles.contains("Roadmap 11"))
        #expect(titles.contains("Roadmap 2"))
        #expect(!titles.contains("Roadmap 1"))
        #expect(!titles.contains("Roadmap 0"))
    }

    @Test
    @MainActor
    func noteEntityQuerySearchResultsStayCappedAcrossLargeCorpus() async throws {
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)
        try await seedNotes(in: graph, count: 250, titlePrefix: "Roadmap", bodyPrefix: "Roadmap details")

        let entities = try await withInjectedGraph({ graph }) {
            try await NoteEntityQuery().entities(matching: "roadmap")
        }

        #expect(entities.count == 10)
        let titles = Set(entities.map(\.title))
        #expect(titles.contains("Roadmap 249"))
        #expect(titles.contains("Roadmap 240"))
        #expect(!titles.contains("Roadmap 239"))
        #expect(!titles.contains("Roadmap 0"))
    }

    @Test
    @MainActor
    func appendToNoteIntentReturnsNoOpDialogWhenContentIsWhitespaceOnly() async throws {
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)
        let original = try await graph.createNote.execute(
            title: "Scratchpad",
            body: "Draft",
            source: .manual
        )
        let intent = AppendToNoteIntent()
        intent.note = NoteEntity(note: original)
        intent.content = "   \n  "

        let result = try await withInjectedGraph({ graph }) {
            try await intent.perform()
        }

        let loaded = try await graph.repository.loadNote(id: original.id)
        #expect(loaded?.body == "Draft")
        #expect(loaded?.entries.count == 1)
        #expect(dialogDescription(of: result).contains("No changes; nothing to append."))
    }

    @Test
    @MainActor
    func appendToNoteIntentReturnsUnavailableDialogWhenSelectedNoteWasDeleted() async throws {
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)
        let original = try await graph.createNote.execute(
            title: "Scratchpad",
            body: "Draft",
            source: .manual
        )
        try await graph.deleteNote.execute(noteID: original.id)

        let deletedEntity = try await withInjectedGraph({ graph }) {
            let entities = try await NoteEntityQuery().entities(for: [original.id])
            return try #require(entities.first)
        }

        let intent = AppendToNoteIntent()
        intent.note = deletedEntity
        intent.content = "Add this"

        let result = try await withInjectedGraph({ graph }) {
            try await intent.perform()
        }

        #expect(dialogDescription(of: result).contains("That note is no longer available."))
    }

    @Test
    @MainActor
    func readNoteIntentReturnsUnavailableDialogWhenSelectedNoteWasDeleted() async throws {
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)
        let original = try await graph.createNote.execute(
            title: "Meeting notes",
            body: "Follow up with product",
            source: .manual
        )
        try await graph.deleteNote.execute(noteID: original.id)

        let deletedEntity = try await withInjectedGraph({ graph }) {
            let entities = try await NoteEntityQuery().entities(for: [original.id])
            return try #require(entities.first)
        }

        let intent = ReadNoteIntent()
        intent.note = deletedEntity

        let result = try await withInjectedGraph({ graph }) {
            try await intent.perform()
        }

        #expect(dialogDescription(of: result).contains("That note is no longer available."))
    }

    @Test
    @MainActor
    func noteEntityInitFromNoteMapsIdDisplayTitleAndPreviewText() async throws {
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)
        let note = try await graph.createNote.execute(
            title: "Grocery run",
            body: "Buy oat milk and sourdough bread",
            source: .manual
        )

        let entity = NoteEntity(note: note)

        #expect(entity.id == note.id)
        #expect(entity.title == note.displayTitle)
        #expect(entity.previewText == note.previewText)
    }

    @Test
    @MainActor
    func noteEntityInitFromSummaryMapsIdTitleAndPreviewText() throws {
        let id = UUID()
        let summary = NoteSummary(
            id: id,
            title: "Sprint retro",
            previewText: "What went well",
            updatedAt: Date()
        )

        let entity = NoteEntity(summary: summary)

        #expect(entity.id == id)
        #expect(entity.title == "Sprint retro")
        #expect(entity.previewText == "What went well")
    }

    @Test
    @MainActor
    func noteEntityInitFromSummaryNormalizesEmptyAndWhitespaceTitles() {
        let emptyTitleSummary = NoteSummary(
            id: UUID(),
            title: "",
            previewText: "Summary preview",
            updatedAt: Date()
        )
        let whitespaceTitleSummary = NoteSummary(
            id: UUID(),
            title: "   \n  ",
            previewText: "Another preview",
            updatedAt: Date()
        )

        let emptyTitleEntity = NoteEntity(summary: emptyTitleSummary)
        let whitespaceTitleEntity = NoteEntity(summary: whitespaceTitleSummary)

        #expect(emptyTitleEntity.title == "Untitled note")
        #expect(whitespaceTitleEntity.title == "Untitled note")
    }

    @Test
    @MainActor
    func noteEntityInitTombstonePreservesIDAndMarksEntityUnavailable() {
        let id = UUID()

        let entity = NoteEntity(tombstoneWithID: id)

        #expect(entity.id == id)
        #expect(entity.title == "Unavailable note")
        #expect(entity.previewText.isEmpty)
    }

    @Test
    @MainActor
    func noteEntityDisplayRepresentationOmitsSubtitleWhenPreviewTextIsEmpty() throws {
        let entity = NoteEntity(id: UUID(), title: "Untitled note", previewText: "")

        let representation = entity.displayRepresentation
        #expect(representation.subtitle == nil)
    }

    @Test
    @MainActor
    func noteEntityDisplayRepresentationOmitsSubtitleWhenPreviewTextIsWhitespaceOnly() throws {
        let entity = NoteEntity(id: UUID(), title: "Whitespace note", previewText: "   \n  ")

        let representation = entity.displayRepresentation
        #expect(representation.subtitle == nil)
    }

    @Test
    @MainActor
    func noteEntityDisplayRepresentationIncludesSubtitleWhenPreviewTextIsNonEmpty() throws {
        let entity = NoteEntity(id: UUID(), title: "Standup", previewText: "Reviewed PRs")

        let representation = entity.displayRepresentation
        #expect(representation.subtitle != nil)
    }

    @Test
    @MainActor
    func noteEntityQueryReturnsTombstonesForUnknownIdentifiers() async throws {
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)
        let existing = try await graph.createNote.execute(
            title: "Keep this",
            body: "Still here",
            source: .manual
        )
        let unknownID = UUID()

        let entities = try await withInjectedGraph({ graph }) {
            try await NoteEntityQuery().entities(for: [existing.id, unknownID])
        }

        #expect(entities.count == 2)
        #expect(entities.first?.id == existing.id)
        #expect(entities.last?.id == unknownID)
        #expect(entities.last?.title == "Unavailable note")
    }

    @Test
    @MainActor
    func noteEntityQueryEntitiesForEmptyIdentifierListReturnsEmpty() async throws {
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)
        _ = try await graph.createNote.execute(title: "Some note", body: "Body", source: .manual)

        let entities = try await withInjectedGraph({ graph }) {
            try await NoteEntityQuery().entities(for: [])
        }

        #expect(entities.isEmpty)
    }

    @Test
    @MainActor
    func noteEntityQueryEntitiesMatchingWhitespaceOnlyFallsBackToSuggestedEntities() async throws {
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)
        _ = try await graph.createNote.execute(title: "Alpha", body: "First", source: .manual)
        _ = try await graph.createNote.execute(title: "Beta", body: "Second", source: .manual)

        let (suggested, entities) = try await withInjectedGraph({ graph }) {
            let query = NoteEntityQuery()
            let suggested = try await query.suggestedEntities()
            let entities = try await query.entities(matching: "   \n  ")
            return (suggested, entities)
        }

        #expect(entities.count == suggested.count)
        #expect(Set(entities.map(\.id)) == Set(suggested.map(\.id)))
    }

    @Test
    @MainActor
    func noteEntityQueryEntitiesMatchingQueryWithNoResultsReturnsEmpty() async throws {
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)
        _ = try await graph.createNote.execute(title: "Meeting notes", body: "Discuss Q4", source: .manual)

        let entities = try await withInjectedGraph({ graph }) {
            try await NoteEntityQuery().entities(matching: "xyzzy irrelevant nonsense")
        }

        #expect(entities.isEmpty)
    }

    @Test
    @MainActor
    func readNoteIntentReturnsEmptyBodyMessageWhenNoteBodyIsEmpty() async throws {
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)
        let original = try await graph.createNote.execute(
            title: "Empty note",
            body: "placeholder",
            source: .manual
        )
        // Replace with empty body so the note exists but has no content
        _ = try await graph.repository.replaceNote(
            id: original.id,
            title: "Empty note",
            body: "",
            source: .manual
        )

        let intent = ReadNoteIntent()
        intent.note = NoteEntity(note: original)

        let result = try await withInjectedGraph({ graph }) {
            try await intent.perform()
        }

        let dialog = dialogDescription(of: result)
        #expect(dialog.contains("Empty note"))
        #expect(dialog.contains("currently empty"))
    }

    @Test
    @MainActor
    func readNoteIntentTrimsWhitespaceBodyBeforeCheckingEmpty() async throws {
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)
        let original = try await graph.createNote.execute(
            title: "Whitespace body note",
            body: "initial text",
            source: .manual
        )
        _ = try await graph.repository.replaceNote(
            id: original.id,
            title: "Whitespace body note",
            body: "   \n\n   ",
            source: .manual
        )

        let intent = ReadNoteIntent()
        intent.note = NoteEntity(note: original)

        let result = try await withInjectedGraph({ graph }) {
            try await intent.perform()
        }

        let dialog = dialogDescription(of: result)
        #expect(dialog.contains("Whitespace body note"))
        #expect(dialog.contains("currently empty"))
    }

    @Test
    @MainActor
    func noteIntentEnvironmentGraphCanBeReplacedAndRestored() throws {
        var callCount = 0
        let graph = try AppGraph(inMemory: true, enableCloudSync: false, useSharedContainer: false)
        let originalGraphFactory = NoteIntentEnvironment.graph
        NoteIntentEnvironment.graph = {
            callCount += 1
            return graph
        }
        defer { NoteIntentEnvironment.graph = originalGraphFactory }

        _ = try NoteIntentEnvironment.graph()
        _ = try NoteIntentEnvironment.graph()

        #expect(callCount == 2)

        // After defer executes the factory is restored (no crash/assertion)
    }

    @Test
    @MainActor
    func createNoteIntentThrowsBootstrapFailureWhenGraphBootstrapFails() async {
        let intent = CreateNoteIntent()
        intent.titleText = "Trip"
        intent.bodyText = "Pack passport"

        await #expect(throws: AppGraphBootstrapError.self) {
            try await withInjectedGraph({
                throw AppGraphBootstrapError(
                    summary: "Second Brain couldn't open your notes store.",
                    details: "Injected bootstrap failure."
                )
            }) {
                _ = try await intent.perform()
            }
        }
    }

    @Test
    @MainActor
    func noteEntityQuerySuggestedEntitiesThrowsBootstrapFailureWhenGraphBootstrapFails() async {
        let query = NoteEntityQuery()

        await #expect(throws: AppGraphBootstrapError.self) {
            try await withInjectedGraph({
                throw AppGraphBootstrapError(
                    summary: "Second Brain couldn't open your notes store.",
                    details: "Injected bootstrap failure."
                )
            }) {
                _ = try await query.suggestedEntities()
            }
        }
    }

    @Test
    @MainActor
    func quickCaptureConfirmPendingVoiceCommandPassesConfirmString() async {
        var capturedInputs: [String] = []
        let viewModel = QuickCaptureViewModel(
            dependencies: makeMinimalDependencies(
                processAssistantInput: { input in
                    capturedInputs.append(input)
                    return NotesAssistantResponse(
                        text: "Edit applied.",
                        referencedNoteIDs: [UUID()],
                        interaction: .none
                    )
                }
            ),
            onSaved: {}
        )
        viewModel.voiceAssistantInteraction = .pendingEditConfirmation
        viewModel.transcriptionPreview = "replace eggs with milk"
        viewModel.voiceAssistantMessage = "Proposed edit."

        await viewModel.confirmPendingVoiceCommand()

        #expect(capturedInputs == ["confirm"])
        #expect(viewModel.voiceAssistantInteraction == .none)
        #expect(viewModel.voiceAssistantMessage == "Edit applied.")
    }

    @Test
    @MainActor
    func quickCaptureCancelPendingVoiceCommandPassesCancelString() async {
        var capturedInputs: [String] = []
        let viewModel = QuickCaptureViewModel(
            dependencies: makeMinimalDependencies(
                processAssistantInput: { input in
                    capturedInputs.append(input)
                    return NotesAssistantResponse(
                        text: "Cancelled the edit.",
                        referencedNoteIDs: [],
                        interaction: .none
                    )
                }
            ),
            onSaved: {}
        )
        viewModel.voiceAssistantInteraction = .pendingEditConfirmation
        viewModel.transcriptionPreview = "add avocado to shopping list"
        viewModel.voiceAssistantMessage = "Proposed edit."

        await viewModel.cancelPendingVoiceCommand()

        #expect(capturedInputs == ["cancel"])
        #expect(viewModel.voiceAssistantInteraction == .none)
        #expect(viewModel.voiceAssistantMessage == "Cancelled the edit.")
    }

    @Test
    @MainActor
    func quickCaptureResolvePendingVoiceCommandIsNoOpWhenNoPendingConfirmation() async {
        var capturedInputs: [String] = []
        let viewModel = QuickCaptureViewModel(
            dependencies: makeMinimalDependencies(
                processAssistantInput: { input in
                    capturedInputs.append(input)
                    return NotesAssistantResponse(text: "", referencedNoteIDs: [])
                }
            ),
            onSaved: {}
        )
        // voiceAssistantInteraction defaults to .none — no pending confirmation

        await viewModel.confirmPendingVoiceCommand()
        await viewModel.cancelPendingVoiceCommand()

        #expect(capturedInputs.isEmpty)
    }

    @Test
    @MainActor
    func quickCaptureResolvePendingVoiceCommandIsNoOpWhenAlreadySavingAudio() async {
        var capturedInputs: [String] = []
        let viewModel = QuickCaptureViewModel(
            dependencies: makeMinimalDependencies(
                processAssistantInput: { input in
                    capturedInputs.append(input)
                    return NotesAssistantResponse(text: "", referencedNoteIDs: [])
                }
            ),
            onSaved: {}
        )
        viewModel.voiceAssistantInteraction = .pendingEditConfirmation
        viewModel.isSavingAudio = true  // simulate audio save in progress

        await viewModel.confirmPendingVoiceCommand()

        #expect(capturedInputs.isEmpty)
    }

    @Test
    @MainActor
    func quickCaptureConfirmSetsErrorMessageOnAssistantFailure() async {
        struct AssistantError: LocalizedError {
            var errorDescription: String? { "Network timeout." }
        }
        let viewModel = QuickCaptureViewModel(
            dependencies: makeMinimalDependencies(
                processAssistantInput: { _ in throw AssistantError() }
            ),
            onSaved: {}
        )
        viewModel.voiceAssistantInteraction = .pendingEditConfirmation
        viewModel.voiceAssistantMessage = "Proposed edit."

        await viewModel.confirmPendingVoiceCommand()

        #expect(viewModel.errorMessage == "Network timeout.")
    }

    // MARK: - hasPendingVoiceConfirmation (drives confirmPendingVoiceCommandButton / cancelPendingVoiceCommandButton visibility)

    @Test
    @MainActor
    func quickCaptureHasPendingVoiceConfirmationTrueWhenInteractionIsPendingEditConfirmation() {
        let viewModel = QuickCaptureViewModel(dependencies: makeMinimalDependencies(), onSaved: {})
        viewModel.voiceAssistantInteraction = .pendingEditConfirmation

        #expect(viewModel.hasPendingVoiceConfirmation == true)
    }

    @Test
    @MainActor
    func quickCaptureHasPendingVoiceConfirmationFalseByDefault() {
        let viewModel = QuickCaptureViewModel(dependencies: makeMinimalDependencies(), onSaved: {})
        // voiceAssistantInteraction defaults to .none

        #expect(viewModel.hasPendingVoiceConfirmation == false)
    }

    @Test
    @MainActor
    func quickCaptureHasPendingVoiceConfirmationFalseAfterSuccessfulConfirm() async {
        let viewModel = QuickCaptureViewModel(
            dependencies: makeMinimalDependencies(
                processAssistantInput: { _ in
                    NotesAssistantResponse(text: "Updated note.", referencedNoteIDs: [UUID()], interaction: .none)
                }
            ),
            onSaved: {}
        )
        viewModel.voiceAssistantInteraction = .pendingEditConfirmation

        await viewModel.confirmPendingVoiceCommand()

        #expect(viewModel.hasPendingVoiceConfirmation == false)
    }

    @Test
    @MainActor
    func quickCaptureHasPendingVoiceConfirmationFalseAfterSuccessfulCancel() async {
        let viewModel = QuickCaptureViewModel(
            dependencies: makeMinimalDependencies(
                processAssistantInput: { _ in
                    NotesAssistantResponse(text: "Canceled the pending edit.", referencedNoteIDs: [], interaction: .none)
                }
            ),
            onSaved: {}
        )
        viewModel.voiceAssistantInteraction = .pendingEditConfirmation

        await viewModel.cancelPendingVoiceCommand()

        #expect(viewModel.hasPendingVoiceConfirmation == false)
    }

    @Test
    @MainActor
    func quickCaptureHasPendingVoiceConfirmationRemainsUnchangedOnAssistantError() async {
        struct AssistantError: LocalizedError {
            var errorDescription: String? { "Connection failed." }
        }
        let viewModel = QuickCaptureViewModel(
            dependencies: makeMinimalDependencies(
                processAssistantInput: { _ in throw AssistantError() }
            ),
            onSaved: {}
        )
        viewModel.voiceAssistantInteraction = .pendingEditConfirmation

        await viewModel.confirmPendingVoiceCommand()

        // Error path: interaction state is not updated — pending confirmation stays
        #expect(viewModel.hasPendingVoiceConfirmation == true)
        #expect(viewModel.errorMessage == "Connection failed.")
    }

    // MARK: - hasVoiceAssistantFeedback (drives voiceAssistantFeedback container visibility)

    @Test
    @MainActor
    func quickCaptureHasVoiceAssistantFeedbackTrueWhenMessageNonEmpty() {
        let viewModel = QuickCaptureViewModel(dependencies: makeMinimalDependencies(), onSaved: {})
        viewModel.voiceAssistantMessage = "I can update Shopping list to add Butter. Confirm or Cancel."

        #expect(viewModel.hasVoiceAssistantFeedback == true)
    }

    @Test
    @MainActor
    func quickCaptureHasVoiceAssistantFeedbackFalseByDefault() {
        let viewModel = QuickCaptureViewModel(dependencies: makeMinimalDependencies(), onSaved: {})
        // voiceAssistantMessage defaults to ""

        #expect(viewModel.hasVoiceAssistantFeedback == false)
    }

    @Test
    @MainActor
    func quickCaptureHasVoiceAssistantFeedbackFalseAfterMessageIsCleared() {
        let viewModel = QuickCaptureViewModel(dependencies: makeMinimalDependencies(), onSaved: {})
        viewModel.voiceAssistantMessage = "Some feedback."
        #expect(viewModel.hasVoiceAssistantFeedback == true)

        viewModel.voiceAssistantMessage = ""

        #expect(viewModel.hasVoiceAssistantFeedback == false)
    }

    // MARK: - transcriptionPreview (drives voiceTranscriptPreview container visibility)

    @Test
    @MainActor
    func quickCaptureTranscriptionPreviewEmptyByDefault() {
        let viewModel = QuickCaptureViewModel(dependencies: makeMinimalDependencies(), onSaved: {})

        #expect(viewModel.transcriptionPreview.isEmpty)
    }

    @Test
    @MainActor
    func quickCaptureTranscriptionPreviewRetainedAfterPendingEditResponse() async {
        let transcript = "Add butter to the shopping list."
        var processVoiceCaptureCalled = false
        var deps = makeMinimalDependencies()
        let voiceDeps = QuickCaptureViewModel.Dependencies(
            captureCapabilityState: deps.captureCapabilityState,
            voiceCommandCapabilityState: deps.voiceCommandCapabilityState,
            refineTypedNote: deps.refineTypedNote,
            createNote: deps.createNote,
            requestRecordingPermission: { true },
            makeTemporaryRecordingURL: deps.makeTemporaryRecordingURL,
            startRecording: deps.startRecording,
            stopRecording: {
                RecordedAudio(
                    temporaryFileURL: FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("m4a"),
                    durationSeconds: 2
                )
            },
            cancelRecording: deps.cancelRecording,
            processVoiceCapture: { _, _, _, _ in
                processVoiceCaptureCalled = true
                return .assistantResponse(
                    NotesAssistantResponse(
                        text: "I can update Shopping list to add Butter. Confirm or Cancel.",
                        referencedNoteIDs: [],
                        interaction: .pendingEditConfirmation
                    ),
                    transcript: transcript
                )
            },
            processAssistantInput: deps.processAssistantInput
        )
        let viewModel = QuickCaptureViewModel(dependencies: voiceDeps, onSaved: {})

        await viewModel.toggleRecording()   // start recording
        await viewModel.toggleRecording()   // stop and process

        #expect(processVoiceCaptureCalled)
        #expect(viewModel.transcriptionPreview == transcript)
        #expect(viewModel.hasVoiceAssistantFeedback == true)
        #expect(viewModel.hasPendingVoiceConfirmation == true)
    }
}

// MARK: - Test helpers

@MainActor
private func makeMinimalDependencies(
    processAssistantInput: @escaping @MainActor (_ input: String) async throws -> NotesAssistantResponse = { _ in
        NotesAssistantResponse(text: "", referencedNoteIDs: [])
    }
) -> QuickCaptureViewModel.Dependencies {
    QuickCaptureViewModel.Dependencies(
        captureCapabilityState: { .available },
        voiceCommandCapabilityState: { .available },
        refineTypedNote: { title, body, _ in NoteCaptureRefinement(title: title, body: body) },
        createNote: { _, _, _ in
            throw NoteRepositoryError.emptyContent
        },
        requestRecordingPermission: { false },
        makeTemporaryRecordingURL: {
            FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
        },
        startRecording: { _ in },
        stopRecording: {
            RecordedAudio(
                temporaryFileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a"),
                durationSeconds: 0
            )
        },
        cancelRecording: {},
        processVoiceCapture: { _, _, _, _ in
            .assistantResponse(
                NotesAssistantResponse(text: "", referencedNoteIDs: []),
                transcript: ""
            )
        },
        processAssistantInput: processAssistantInput
    )
}

@MainActor
private func withInjectedGraph<T>(
    _ graphFactory: @escaping @MainActor () throws -> AppGraph,
    operation: @MainActor () async throws -> T
) async rethrows -> T {
    let originalGraphFactory = NoteIntentEnvironment.graph
    NoteIntentEnvironment.graph = graphFactory
    defer { NoteIntentEnvironment.graph = originalGraphFactory }
    return try await operation()
}

private func dialogDescription<T>(of result: T) -> String {
    String(describing: Mirror(reflecting: result).descendant("dialog"))
        .replacingOccurrences(of: "\\'", with: "'")
}

private func makeUITestAudioURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
}

@MainActor
private func seedNotes(
    in graph: AppGraph,
    count: Int,
    titlePrefix: String,
    bodyPrefix: String
) async throws {
    for index in 0..<count {
        _ = try await graph.createNote.execute(
            title: "\(titlePrefix) \(index)",
            body: "\(bodyPrefix) \(index)",
            source: .manual
        )
    }
}