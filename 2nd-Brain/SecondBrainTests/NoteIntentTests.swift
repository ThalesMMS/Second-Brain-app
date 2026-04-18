import Testing
import SecondBrainComposition
import SecondBrainDomain
@testable import SecondBrain

@Suite(.serialized)
struct NoteIntentTests {
    @Test
    @MainActor
    func createNoteIntentUsesInjectedGraph() async throws {
        let graph = try makeInMemoryGraph()

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
        let graph = try makeInMemoryGraph()
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
        let graph = try makeInMemoryGraph()
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
    func appendToNoteIntentReturnsNoOpDialogWhenContentIsWhitespaceOnly() async throws {
        let graph = try makeInMemoryGraph()
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
        let graph = try makeInMemoryGraph()
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
        let graph = try makeInMemoryGraph()
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
    func readNoteIntentReturnsEmptyBodyMessageWhenNoteBodyIsEmpty() async throws {
        let graph = try makeInMemoryGraph()
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
        let graph = try makeInMemoryGraph()
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
    func noteIntentEnvironmentGraphCanBeReplacedAndRestored() async throws {
        try await GraphInjectionCoordinator.shared.runExclusive {
            var callCount = 0
            let originalGraph = try makeInMemoryGraph()
            let temporaryGraph = try makeInMemoryGraph()
            let originalGraphFactory = NoteIntentEnvironment.graph
            let scopedOriginalGraphFactory: @MainActor () throws -> AppGraph = { originalGraph }
            NoteIntentEnvironment.graph = scopedOriginalGraphFactory
            defer { NoteIntentEnvironment.graph = originalGraphFactory }

            do {
                NoteIntentEnvironment.graph = {
                    callCount += 1
                    return temporaryGraph
                }
                defer { NoteIntentEnvironment.graph = scopedOriginalGraphFactory }

                _ = try NoteIntentEnvironment.graph()
                _ = try NoteIntentEnvironment.graph()

                #expect(callCount == 2)
            }

            let restoredGraph = try NoteIntentEnvironment.graph()
            #expect(callCount == 2)
            #expect(restoredGraph === originalGraph)
        }
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

    // MARK: - Additional edge cases

    @Test
    @MainActor
    func appendToNoteIntentMultipleAppendsIncreasesEntryCount() async throws {
        let graph = try makeInMemoryGraph()
        let original = try await graph.createNote.execute(
            title: "Log",
            body: "Entry 1",
            source: .manual
        )

        let intentA = AppendToNoteIntent()
        intentA.note = NoteEntity(note: original)
        intentA.content = "Entry 2"

        _ = try await withInjectedGraph({ graph }) {
            try await intentA.perform()
        }

        let intentB = AppendToNoteIntent()
        let refreshed = try await graph.loadNote.execute(id: original.id)
        intentB.note = NoteEntity(note: try #require(refreshed))
        intentB.content = "Entry 3"

        _ = try await withInjectedGraph({ graph }) {
            try await intentB.perform()
        }

        let updated = try await graph.repository.loadNote(id: original.id)
        // Body should contain all three entries separated by double newlines
        #expect(updated?.body == "Entry 1\n\nEntry 2\n\nEntry 3")
        #expect((updated?.entries.count ?? 0) >= 2)
    }

    @Test
    @MainActor
    func appendToNoteIntentBootstrapFailurePropagatesError() async {
        let intent = AppendToNoteIntent()
        intent.note = NoteEntity(tombstoneWithID: UUID())
        intent.content = "Some content"

        await #expect(throws: AppGraphBootstrapError.self) {
            try await withInjectedGraph({
                throw AppGraphBootstrapError(
                    summary: "Store unavailable.",
                    details: "Injected error for AppendToNoteIntent."
                )
            }) {
                _ = try await intent.perform()
            }
        }
    }

    @Test
    @MainActor
    func readNoteIntentBootstrapFailurePropagatesError() async {
        let intent = ReadNoteIntent()
        intent.note = NoteEntity(tombstoneWithID: UUID())

        await #expect(throws: AppGraphBootstrapError.self) {
            try await withInjectedGraph({
                throw AppGraphBootstrapError(
                    summary: "Store unavailable.",
                    details: "Injected error for ReadNoteIntent."
                )
            }) {
                _ = try await intent.perform()
            }
        }
    }

    @Test
    @MainActor
    func noteIntentEnvironmentGraphDefaultFactoryDoesNotReturnNil() throws {
        let original = NoteIntentEnvironment.graph

        let returnedDefault: AppGraph? = try original()

        _ = try #require(returnedDefault)
    }
}
