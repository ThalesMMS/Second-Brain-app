import Foundation
import Testing
@testable import SecondBrainDomain
@testable import SecondBrainPersistence

struct PersistenceUITestSeedingTests {
    // MARK: - PersistenceController.seedForUITests

    @Test
    @MainActor
    func seedForUITestsWithEmptyArrayIsNoOp() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)

        try persistence.seedForUITests([])

        let summaries = try await persistence.repository.listNotes(matching: nil)
        #expect(summaries.isEmpty)
    }

    @Test
    @MainActor
    func seedForUITestsInsertsNoteWithStableID() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let noteID = UUID(uuidString: "00000000-1111-2222-3333-444444444444")!

        try persistence.seedForUITests([
            SeededNoteData(
                id: noteID,
                title: "Seed title",
                body: "Seed body",
                createdAt: Date(),
                updatedAt: Date(),
                entries: []
            )
        ])

        let loaded = try await persistence.repository.loadNote(id: noteID)
        #expect(loaded?.id == noteID)
    }

    @Test
    @MainActor
    func seedForUITestsPreservesNoteBody() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let noteID = UUID(uuidString: "00000000-AAAA-BBBB-CCCC-DDDDDDDDDDDD")!

        try persistence.seedForUITests([
            SeededNoteData(
                id: noteID,
                title: "Shopping list",
                body: "Milk\nEggs\nBread",
                createdAt: Date(),
                updatedAt: Date(),
                entries: []
            )
        ])

        let loaded = try await persistence.repository.loadNote(id: noteID)
        #expect(loaded?.body == "Milk\nEggs\nBread")
        #expect(loaded?.title == "Shopping list")
    }

    @Test
    @MainActor
    func seedForUITestsPreservesCreatedAndUpdatedTimestamps() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let noteID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_700_001_000)

        try persistence.seedForUITests([
            SeededNoteData(
                id: noteID,
                title: "Timestamped note",
                body: "Body",
                createdAt: createdAt,
                updatedAt: updatedAt,
                entries: []
            )
        ])

        let loaded = try await persistence.repository.loadNote(id: noteID)
        #expect(loaded?.createdAt == createdAt)
        #expect(loaded?.updatedAt == updatedAt)
    }

    @Test
    @MainActor
    func seedForUITestsInsertsNoteEntries() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let noteID = UUID()
        let entryID = UUID(uuidString: "00000000-0000-0000-0000-EEEEEEEEEEEE")!
        let entryCreatedAt = Date(timeIntervalSince1970: 1_000_000)

        try persistence.seedForUITests([
            SeededNoteData(
                id: noteID,
                title: "Note with entry",
                body: "Entry body text",
                createdAt: Date(),
                updatedAt: Date(),
                entries: [
                    SeededNoteEntryData(
                        id: entryID,
                        createdAt: entryCreatedAt,
                        kind: .creation,
                        source: .manual,
                        text: "Entry body text"
                    )
                ]
            )
        ])

        let loaded = try await persistence.repository.loadNote(id: noteID)
        #expect(loaded?.entries.count == 1)
        #expect(loaded?.entries.first?.id == entryID)
        #expect(loaded?.entries.first?.kind == .creation)
        #expect(loaded?.entries.first?.source == .manual)
        #expect(loaded?.entries.first?.text == "Entry body text")
    }

    @Test
    @MainActor
    func seedForUITestsInsertsMultipleNotes() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let id1 = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let id2 = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let id3 = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

        try persistence.seedForUITests([
            SeededNoteData(id: id1, title: "Note A", body: "Body A", createdAt: Date(), updatedAt: Date(), entries: []),
            SeededNoteData(id: id2, title: "Note B", body: "Body B", createdAt: Date(), updatedAt: Date(), entries: []),
            SeededNoteData(id: id3, title: "Note C", body: "Body C", createdAt: Date(), updatedAt: Date(), entries: []),
        ])

        let summaries = try await persistence.repository.listNotes(matching: nil)
        #expect(summaries.count == 3)
        #expect(Set(summaries.map(\.id)) == Set([id1, id2, id3]))
    }

    @Test
    @MainActor
    func seedForUITestsAllowsSubsequentMutation() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let noteID = UUID()

        try persistence.seedForUITests([
            SeededNoteData(
                id: noteID,
                title: "Mutable note",
                body: "Initial body",
                createdAt: Date(),
                updatedAt: Date(),
                entries: []
            )
        ])

        _ = try await persistence.repository.appendText("Appended text", to: noteID, source: .manual)

        let loaded = try await persistence.repository.loadNote(id: noteID)
        #expect(loaded?.body == "Initial body\n\nAppended text")
    }

    @Test
    @MainActor
    func seedForUITestsNoteIsSearchableAfterSeeding() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)

        try persistence.seedForUITests([
            SeededNoteData(
                id: UUID(),
                title: "Oncology reminders",
                body: "Call Dr. Lima on Tuesday.",
                createdAt: Date(),
                updatedAt: Date(),
                entries: []
            )
        ])

        let results = try await persistence.repository.listNotes(matching: "oncology")
        #expect(results.count == 1)
        #expect(results.first?.title == "Oncology reminders")
    }

}
