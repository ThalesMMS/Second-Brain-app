import Foundation
import SQLite3
import SwiftData
import Testing
@testable import SecondBrainDomain
@testable import SecondBrainPersistence

struct SecondBrainPersistenceTests {
    @Test
    @MainActor
    func prepareStoreDirectoryCreatesParentFolder() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = rootURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("default.store")
        let configuration = ModelConfiguration(url: storeURL, cloudKitDatabase: .none)

        defer { try? fileManager.removeItem(at: rootURL) }

        try PersistenceController.prepareStoreDirectory(for: configuration, fileManager: fileManager)

        #expect(fileManager.fileExists(atPath: storeURL.deletingLastPathComponent().path))
    }

    @Test
    @MainActor
    func resolvedStoreURLFallsBackToApplicationSupportWithoutAppGroup() {
        let fileManager = FileManager.default

        let storeURL = PersistenceController.resolvedStoreURL(
            fileManager: fileManager,
            appGroupContainerURL: nil
        )

        #expect(storeURL.lastPathComponent == "default.store")
        #expect(storeURL.deletingLastPathComponent().lastPathComponent == "Application Support")
    }

    @Test
    @MainActor
    func migrationRemovesLegacyAudioAttachmentsAndDormantNoteColumns() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = rootURL.appendingPathComponent("default.store")
        let configuration = ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
        defer { try? fileManager.removeItem(at: rootURL) }

        try PersistenceController.prepareStoreDirectory(for: configuration, fileManager: fileManager)

        let noteID = UUID()
        let createdAt = Date()
        do {
            let legacyContainer = try ModelContainer(
                for: Schema(versionedSchema: SecondBrainSchemaV1.self),
                configurations: configuration
            )
            let legacyContext = legacyContainer.mainContext
            let note = SecondBrainSchemaV1.NoteRecord(
                id: noteID,
                title: "Shopping list",
                bodyText: "banana",
                searchableText: "shopping list banana",
                createdAt: createdAt,
                updatedAt: createdAt,
                isPinned: true,
                lastViewedAt: createdAt
            )
            let entry = SecondBrainSchemaV1.NoteEntryRecord(
                createdAt: createdAt,
                kindRawValue: NoteEntryKind.creation.rawValue,
                sourceRawValue: NoteMutationSource.manual.rawValue,
                text: "banana",
                note: note
            )
            let attachment = SecondBrainSchemaV1.AudioAttachmentRecord(
                createdAt: createdAt,
                relativePath: "legacy.m4a",
                durationSeconds: 5,
                transcript: "banana",
                sourceRawValue: NoteMutationSource.speechToText.rawValue,
                note: note
            )
            note.entries.append(entry)
            note.audioAttachments.append(attachment)
            legacyContext.insert(note)
            try legacyContext.save()
        }

        let summaries: [NoteSummary]
        let loadedNote: Note?
        do {
            let migrated = try PersistenceController(configuration: configuration)
            summaries = try await migrated.repository.listNotes(matching: nil)
            loadedNote = try await migrated.repository.loadNote(id: noteID)
        }

        let audioAttachmentCount = try countRows(inSQLiteStoreAt: storeURL, table: "ZAUDIOATTACHMENTRECORD")
        let hasPinnedColumn = try columnExists(inSQLiteStoreAt: storeURL, table: "ZNOTERECORD", column: "ZISPINNED")
        let hasLastViewedColumn = try columnExists(inSQLiteStoreAt: storeURL, table: "ZNOTERECORD", column: "ZLASTVIEWEDAT")

        #expect(summaries.count == 1)
        #expect(loadedNote?.displayTitle == "Shopping list")
        #expect(loadedNote?.body == "banana")
        #expect(loadedNote?.entries.count == 1)
        #expect(audioAttachmentCount == 0)
        #expect(hasPinnedColumn == false)
        #expect(hasLastViewedColumn == false)
    }

    @Test
    @MainActor
    func createAndAppendPersistEntriesAndBody() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let original = try await persistence.repository.createNote(
            title: "Rounds",
            body: "Check CT head",
            source: .manual,
            initialEntryKind: .creation
        )

        let updated = try await persistence.repository.appendText(
            "Review chest CT",
            to: original.id,
            source: .manual
        )

        #expect(updated.displayTitle == "Rounds")
        #expect(updated.body.contains("Check CT head"))
        #expect(updated.body.contains("Review chest CT"))
        #expect(updated.entries.count == 2)
        #expect(updated.entries.last?.kind == .append)
    }

    @Test
    @MainActor
    func snippetsPrioritizeTitleMatches() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        _ = try await persistence.repository.createNote(
            title: "Oncology follow-up",
            body: "Review MRI liver next week",
            source: .manual,
            initialEntryKind: .creation
        )
        _ = try await persistence.repository.createNote(
            title: "General inbox",
            body: "Oncology follow-up meeting scheduled",
            source: .manual,
            initialEntryKind: .creation
        )

        let results = try await persistence.repository.snippets(matching: "oncology follow-up", limit: 5)

        #expect(results.count >= 2)
        let firstResult = try #require(results.first)
        let secondResult = try #require(results.dropFirst().first)
        let firstScore = firstResult.score
        let secondScore = secondResult.score

        #expect(firstResult.title == "Oncology follow-up")
        #expect(firstScore >= secondScore)
    }

    @Test
    @MainActor
    func resolveNoteReferenceUsesExactUUIDAcrossLargeCorpus() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        try await populateLargeCorpus(in: persistence, count: 180)
        let target = try await persistence.repository.createNote(
            title: "Target note",
            body: "Escalate the MRI follow-up with radiology.",
            source: .manual,
            initialEntryKind: .creation
        )
        try await populateLargeCorpus(in: persistence, count: 40, prefix: "Trailing filler")

        let resolved = try await persistence.repository.resolveNoteReference(target.id.uuidString)

        #expect(resolved?.id == target.id)
        #expect(resolved?.displayTitle == "Target note")
    }

    @Test
    @MainActor
    func listNotesReturnsMultipleRankedMatchesForAmbiguousQueries() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let exactTitle = try await persistence.repository.createNote(
            title: "Project roadmap",
            body: "Prioritize the Q3 milestones",
            source: .manual,
            initialEntryKind: .creation
        )
        _ = try await persistence.repository.createNote(
            title: "Planning inbox",
            body: "Project roadmap review with the team",
            source: .manual,
            initialEntryKind: .creation
        )

        let summaries = try await persistence.repository.listNotes(matching: "project roadmap")

        #expect(summaries.count == 2)
        #expect(summaries.first?.id == exactTitle.id)
        #expect(Set(summaries.map(\.title)) == Set(["Project roadmap", "Planning inbox"]))
    }

    @Test
    @MainActor
    func listNotesReturnsEmptyArrayWhenQueryMatchesNoNotes() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        _ = try await persistence.repository.createNote(
            title: "Vacation ideas",
            body: "Beach resort and mountains",
            source: .manual,
            initialEntryKind: .creation
        )

        let summaries = try await persistence.repository.listNotes(matching: "xyzzy irrelevant nonsense")

        #expect(summaries.isEmpty)
    }

    @Test
    @MainActor
    func listNotesOrdersByUpdatedAtDescendingWithoutPinSorting() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let first = try await persistence.repository.createNote(
            title: "First note",
            body: "Created first",
            source: .manual,
            initialEntryKind: .creation
        )
        // Append to the first note so its updatedAt advances past the second note's createdAt
        let updated = try await persistence.repository.appendText(
            "Additional text",
            to: first.id,
            source: .manual
        )
        let second = try await persistence.repository.createNote(
            title: "Second note",
            body: "Created second",
            source: .manual,
            initialEntryKind: .creation
        )
        // Advance the first note's updatedAt to be the most recent
        _ = try await persistence.repository.appendText(
            "One more line",
            to: first.id,
            source: .manual
        )

        let summaries = try await persistence.repository.listNotes(matching: nil)

        // Notes must be ordered by updatedAt descending; no pin-priority grouping
        #expect(summaries.count == 2)
        #expect(summaries.first?.id == first.id)
        for i in 1..<summaries.count {
            #expect(summaries[i - 1].updatedAt >= summaries[i].updatedAt)
        }
        _ = updated
        _ = second
    }

    @Test
    @MainActor
    func pickerRecentNotesReturnsUpToLimitMostRecentNotes() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        for i in 1...5 {
            _ = try await persistence.repository.createNote(
                title: "Note \(i)",
                body: "Body \(i)",
                source: .manual,
                initialEntryKind: .creation
            )
        }

        let results = try await persistence.repository.pickerRecentNotes(limit: 3)

        #expect(results.count == 3)
        // Results must be ordered by updatedAt descending
        for i in 1..<results.count {
            #expect(results[i - 1].updatedAt >= results[i].updatedAt)
        }
    }

    @Test
    @MainActor
    func searchNotesAppliesLimitAfterRelevanceRanking() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let exactTitle = try await persistence.repository.createNote(
            title: "Project roadmap",
            body: "Plan the next quarter",
            source: .manual,
            initialEntryKind: .creation
        )
        _ = try await persistence.repository.createNote(
            title: "Inbox",
            body: "Please review the project roadmap with the team",
            source: .manual,
            initialEntryKind: .creation
        )

        let results = try await persistence.repository.searchNotes(matching: "project roadmap", limit: 1)

        #expect(results.count == 1)
        #expect(results.first?.id == exactTitle.id)
        #expect(results.first?.title == "Project roadmap")
    }

    @Test
    @MainActor
    func listNotesMaintainsTitleBeforeBodyRankingAcrossLargeCorpus() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        try await populateLargeCorpus(in: persistence, count: 220)
        let exactTitle = try await persistence.repository.createNote(
            title: "Project roadmap",
            body: "Plan the next quarter.",
            source: .manual,
            initialEntryKind: .creation
        )
        let bodyOnly = try await persistence.repository.createNote(
            title: "Inbox",
            body: "Please review the project roadmap with the team.",
            source: .manual,
            initialEntryKind: .creation
        )

        let summaries = try await persistence.repository.listNotes(matching: "project roadmap")

        #expect(summaries.count >= 2)
        #expect(summaries.first?.id == exactTitle.id)
        #expect(Set(summaries.prefix(2).map(\.id)) == Set([exactTitle.id, bodyOnly.id]))
    }

    @Test
    @MainActor
    func snippetsMaintainRankingAndRespectLimitAcrossLargeCorpus() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        try await populateLargeCorpus(in: persistence, count: 220)
        let exactTitle = try await persistence.repository.createNote(
            title: "Oncology follow-up",
            body: "Review the MRI liver protocol next week.",
            source: .manual,
            initialEntryKind: .creation
        )
        let bodyOnly = try await persistence.repository.createNote(
            title: "General inbox",
            body: "Oncology follow-up meeting with the radiology team.",
            source: .manual,
            initialEntryKind: .creation
        )
        _ = try await persistence.repository.createNote(
            title: "Another inbox",
            body: "Oncology follow-up paperwork and reminders.",
            source: .manual,
            initialEntryKind: .creation
        )

        let snippets = try await persistence.repository.snippets(matching: "oncology follow-up", limit: 2)

        #expect(snippets.count == 2)
        #expect(snippets.first?.noteID == exactTitle.id)
        #expect(snippets.allSatisfy { $0.score > 0 })
        #expect(snippets.first!.score >= snippets.last!.score)
        _ = bodyOnly
    }

    @Test
    @MainActor
    func migrationFromV2ToV3DropsPinnedAndLastViewedColumns() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = rootURL.appendingPathComponent("default.store")
        let configuration = ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
        defer { try? fileManager.removeItem(at: rootURL) }

        try PersistenceController.prepareStoreDirectory(for: configuration, fileManager: fileManager)

        let noteID = UUID()
        let createdAt = Date()
        do {
            let v2Container = try ModelContainer(
                for: Schema(versionedSchema: SecondBrainSchemaV2.self),
                configurations: configuration
            )
            let context = v2Container.mainContext
            let note = SecondBrainSchemaV2.NoteRecord(
                id: noteID,
                title: "V2 note",
                bodyText: "some body",
                searchableText: "v2 note some body",
                createdAt: createdAt,
                updatedAt: createdAt,
                isPinned: true,
                lastViewedAt: createdAt
            )
            context.insert(note)
            try context.save()
        }

        let summaries: [NoteSummary]
        let loadedNote: Note?
        do {
            let migrated = try PersistenceController(configuration: configuration)
            summaries = try await migrated.repository.listNotes(matching: nil)
            loadedNote = try await migrated.repository.loadNote(id: noteID)
        }

        let hasPinnedColumn = try columnExists(inSQLiteStoreAt: storeURL, table: "ZNOTERECORD", column: "ZISPINNED")
        let hasLastViewedColumn = try columnExists(inSQLiteStoreAt: storeURL, table: "ZNOTERECORD", column: "ZLASTVIEWEDAT")

        #expect(summaries.count == 1)
        #expect(loadedNote?.displayTitle == "V2 note")
        #expect(loadedNote?.body == "some body")
        #expect(hasPinnedColumn == false)
        #expect(hasLastViewedColumn == false)
    }

    // MARK: - replaceNote (async, actor)

    @Test
    @MainActor
    func replaceNoteUpdatesContentAndAddsEntry() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let original = try await persistence.repository.createNote(
            title: "Old title",
            body: "Old body",
            source: .manual,
            initialEntryKind: .creation
        )

        let updated = try await persistence.repository.replaceNote(
            id: original.id,
            title: "New title",
            body: "New body",
            source: .manual
        )

        let reloaded = try await persistence.repository.loadNote(id: original.id)

        #expect(updated.displayTitle == "New title")
        #expect(updated.body == "New body")
        #expect(updated.entries.count == 2)
        #expect(updated.entries.last?.kind == .replaceBody)
        #expect(reloaded?.body == "New body")
    }

    @Test
    @MainActor
    func replaceNoteThrowsWhenNoteNotFound() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)

        await #expect(throws: NoteRepositoryError.self) {
            _ = try await persistence.repository.replaceNote(
                id: UUID(),
                title: "Ghost",
                body: "Content",
                source: .manual
            )
        }
    }

    // MARK: - deleteNote (async, actor)

    @Test
    @MainActor
    func deleteNoteRemovesNoteFromStore() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let note = try await persistence.repository.createNote(
            title: "To remove",
            body: "content",
            source: .manual,
            initialEntryKind: .creation
        )

        try await persistence.repository.deleteNote(id: note.id)

        let loaded = try await persistence.repository.loadNote(id: note.id)
        #expect(loaded == nil)
    }

    @Test
    @MainActor
    func deleteNoteIsNoOpForNonExistentID() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        // Deleting a note that doesn't exist should not throw
        try await persistence.repository.deleteNote(id: UUID())
        let summaries = try await persistence.repository.listNotes(matching: nil)
        #expect(summaries.isEmpty)
    }

    // MARK: - loadNote edge cases (async, actor)

    @Test
    @MainActor
    func loadNoteReturnsNilForUnknownID() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        _ = try await persistence.repository.createNote(
            title: "Some note",
            body: "body",
            source: .manual,
            initialEntryKind: .creation
        )

        let result = try await persistence.repository.loadNote(id: UUID())

        #expect(result == nil)
    }

    // MARK: - createNote error case (async, actor)

    @Test
    @MainActor
    func createNoteThrowsEmptyContentErrorForBlankInput() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)

        await #expect(throws: NoteRepositoryError.self) {
            _ = try await persistence.repository.createNote(
                title: "   ",
                body: "\n\n\t",
                source: .manual,
                initialEntryKind: .creation
            )
        }
    }

    // MARK: - snippets edge cases (async, actor)

    @Test
    @MainActor
    func snippetsWithZeroLimitReturnsEmpty() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        _ = try await persistence.repository.createNote(
            title: "Alpha",
            body: "Some content",
            source: .manual,
            initialEntryKind: .creation
        )

        let results = try await persistence.repository.snippets(matching: "alpha", limit: 0)

        #expect(results.isEmpty)
    }

    @Test
    @MainActor
    func snippetsWithEmptyQueryReturnsAllNotes() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        _ = try await persistence.repository.createNote(title: "Note 1", body: "Body 1", source: .manual, initialEntryKind: .creation)
        _ = try await persistence.repository.createNote(title: "Note 2", body: "Body 2", source: .manual, initialEntryKind: .creation)

        let results = try await persistence.repository.snippets(matching: "", limit: 10)

        #expect(results.count == 2)
    }

    // MARK: - resolveNoteReference edge cases (async, actor)

    @Test
    @MainActor
    func resolveNoteReferenceReturnsNilForUnknownUUID() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        _ = try await persistence.repository.createNote(
            title: "Existing",
            body: "present",
            source: .manual,
            initialEntryKind: .creation
        )

        let resolved = try await persistence.repository.resolveNoteReference(UUID().uuidString)

        #expect(resolved == nil)
    }

    @Test
    @MainActor
    func resolveNoteReferenceWithEmptyStringReturnsMostRecentNote() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        _ = try await persistence.repository.createNote(
            title: "First",
            body: "created first",
            source: .manual,
            initialEntryKind: .creation
        )
        let mostRecent = try await persistence.repository.createNote(
            title: "Second",
            body: "created second",
            source: .manual,
            initialEntryKind: .creation
        )

        let resolved = try await persistence.repository.resolveNoteReference("")

        #expect(resolved?.id == mostRecent.id)
    }

    @Test
    @MainActor
    func resolveNoteReferenceReturnsNilWhenStoreIsEmpty() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)

        let resolved = try await persistence.repository.resolveNoteReference("anything")

        #expect(resolved == nil)
    }

    // MARK: - appendText error case (async, actor)

    @Test
    @MainActor
    func appendTextThrowsWhenNoteNotFound() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)

        await #expect(throws: NoteRepositoryError.self) {
            _ = try await persistence.repository.appendText("text", to: UUID(), source: .manual)
        }
    }

    @Test
    @MainActor
    func noteLoadedFromPersistenceHasNoIsPinnedProperty() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let created = try await persistence.repository.createNote(
            title: "My note",
            body: "Some body text",
            source: .manual,
            initialEntryKind: .creation
        )

        let loaded = try await persistence.repository.loadNote(id: created.id)

        let note = try #require(loaded)
        // Verify the Note struct fields that remain after removing isPinned
        #expect(note.id == created.id)
        #expect(note.displayTitle == "My note")
        #expect(note.body == "Some body text")
        #expect(note.entries.count == 1)
    }

    @Test
    @MainActor
    func listNotesSummaryHasNoIsPinnedData() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        _ = try await persistence.repository.createNote(
            title: "Pinless note",
            body: "Body text",
            source: .manual,
            initialEntryKind: .creation
        )

        let summaries = try await persistence.repository.listNotes(matching: nil)

        let summary = try #require(summaries.first)
        // NoteSummary no longer carries isPinned; verify expected fields are present
        #expect(!summary.title.isEmpty)
        #expect(!summary.previewText.isEmpty)
        #expect(summary.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
    }

    // MARK: - SeededNoteEntryData

    @Test
    func seededNoteEntryDataStoresAllFields() {
        let id = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let createdAt = Date(timeIntervalSince1970: 1_000_000)
        let entry = SeededNoteEntryData(
            id: id,
            createdAt: createdAt,
            kind: .creation,
            source: .manual,
            text: "First entry text"
        )

        #expect(entry.id == id)
        #expect(entry.createdAt == createdAt)
        #expect(entry.kind == .creation)
        #expect(entry.source == .manual)
        #expect(entry.text == "First entry text")
    }

    @Test
    func seededNoteEntryDataStoresdifferentKindAndSource() {
        let entry = SeededNoteEntryData(
            id: UUID(),
            createdAt: Date(),
            kind: .append,
            source: .speechToText,
            text: "Appended via voice"
        )

        #expect(entry.kind == .append)
        #expect(entry.source == .speechToText)
    }

    // MARK: - SeededNoteData

    @Test
    func seededNoteDataStoresAllFields() {
        let id = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let createdAt = Date(timeIntervalSince1970: 2_000_000)
        let updatedAt = Date(timeIntervalSince1970: 2_001_000)
        let entry = SeededNoteEntryData(
            id: UUID(),
            createdAt: createdAt,
            kind: .creation,
            source: .manual,
            text: "Entry body"
        )

        let noteData = SeededNoteData(
            id: id,
            title: "My seeded note",
            body: "Note body text",
            createdAt: createdAt,
            updatedAt: updatedAt,
            entries: [entry]
        )

        #expect(noteData.id == id)
        #expect(noteData.title == "My seeded note")
        #expect(noteData.body == "Note body text")
        #expect(noteData.createdAt == createdAt)
        #expect(noteData.updatedAt == updatedAt)
        #expect(noteData.entries.count == 1)
        #expect(noteData.entries.first?.text == "Entry body")
    }

    @Test
    func seededNoteDataCanHaveMultipleEntries() {
        let noteData = SeededNoteData(
            id: UUID(),
            title: "Multi-entry note",
            body: "Full body",
            createdAt: Date(),
            updatedAt: Date(),
            entries: [
                SeededNoteEntryData(id: UUID(), createdAt: Date(), kind: .creation, source: .manual, text: "First"),
                SeededNoteEntryData(id: UUID(), createdAt: Date(), kind: .append, source: .speechToText, text: "Second"),
            ]
        )

        #expect(noteData.entries.count == 2)
        #expect(noteData.entries[0].kind == .creation)
        #expect(noteData.entries[1].kind == .append)
    }

    @Test
    func seededNoteDataCanHaveEmptyEntries() {
        let noteData = SeededNoteData(
            id: UUID(),
            title: "No entries note",
            body: "Body text",
            createdAt: Date(),
            updatedAt: Date(),
            entries: []
        )

        #expect(noteData.entries.isEmpty)
    }

    // MARK: - PersistenceController.seedForUITests

    @Test
    @MainActor
    func seedForUITestsWithEmptyArrayIsNoOp() throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)

        try persistence.seedForUITests([])

        // No notes inserted - store should be empty
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

@MainActor
private func populateLargeCorpus(
    in persistence: PersistenceController,
    count: Int,
    prefix: String = "Archive note"
) async throws {
    for index in 0..<count {
        _ = try await persistence.repository.createNote(
            title: "\(prefix) \(index)",
            body: "Routine archive entry \(index). Unrelated planning, groceries, and logistics.",
            source: .manual,
            initialEntryKind: .creation
        )
    }
}

private func countRows(inSQLiteStoreAt storeURL: URL, table: String) throws -> Int {
    var database: OpaquePointer?
    guard sqlite3_open(storeURL.path, &database) == SQLITE_OK else {
        defer { sqlite3_close(database) }
        throw SQLiteStoreInspectionError.openFailed(path: storeURL.path)
    }
    defer { sqlite3_close(database) }

    let tableExistsQuery = "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '\(table)';"
    var tableStatement: OpaquePointer?
    guard sqlite3_prepare_v2(database, tableExistsQuery, -1, &tableStatement, nil) == SQLITE_OK else {
        defer { sqlite3_finalize(tableStatement) }
        throw SQLiteStoreInspectionError.prepareFailed(query: tableExistsQuery)
    }
    defer { sqlite3_finalize(tableStatement) }

    guard sqlite3_step(tableStatement) == SQLITE_ROW else {
        throw SQLiteStoreInspectionError.stepFailed(query: tableExistsQuery)
    }

    guard sqlite3_column_int(tableStatement, 0) > 0 else {
        return 0
    }

    let rowCountQuery = "SELECT COUNT(*) FROM \(table);"
    var rowStatement: OpaquePointer?
    guard sqlite3_prepare_v2(database, rowCountQuery, -1, &rowStatement, nil) == SQLITE_OK else {
        defer { sqlite3_finalize(rowStatement) }
        throw SQLiteStoreInspectionError.prepareFailed(query: rowCountQuery)
    }
    defer { sqlite3_finalize(rowStatement) }

    guard sqlite3_step(rowStatement) == SQLITE_ROW else {
        throw SQLiteStoreInspectionError.stepFailed(query: rowCountQuery)
    }

    return Int(sqlite3_column_int(rowStatement, 0))
}

private func columnExists(inSQLiteStoreAt storeURL: URL, table: String, column: String) throws -> Bool {
    var database: OpaquePointer?
    guard sqlite3_open(storeURL.path, &database) == SQLITE_OK else {
        defer { sqlite3_close(database) }
        throw SQLiteStoreInspectionError.openFailed(path: storeURL.path)
    }
    defer { sqlite3_close(database) }

    let query = "SELECT COUNT(*) FROM pragma_table_info('\(table)') WHERE name = '\(column)';"
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
        defer { sqlite3_finalize(statement) }
        throw SQLiteStoreInspectionError.prepareFailed(query: query)
    }
    defer { sqlite3_finalize(statement) }

    guard sqlite3_step(statement) == SQLITE_ROW else {
        throw SQLiteStoreInspectionError.stepFailed(query: query)
    }

    return sqlite3_column_int(statement, 0) > 0
}

private enum SQLiteStoreInspectionError: LocalizedError {
    case openFailed(path: String)
    case prepareFailed(query: String)
    case stepFailed(query: String)

    var errorDescription: String? {
        switch self {
        case let .openFailed(path):
            "Failed to open SQLite store at \(path)."
        case let .prepareFailed(query):
            "Failed to prepare SQLite query: \(query)"
        case let .stepFailed(query):
            "Failed to execute SQLite query: \(query)"
        }
    }
}