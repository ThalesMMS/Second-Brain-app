import Foundation
import SwiftData
import Testing
@testable import SecondBrainDomain
@testable import SecondBrainPersistence

struct PersistenceControllerMigrationTests {
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
    func migrationRemovesLegacyAudioAttachmentsAndPreservesRestoredPinnedColumn() async throws {
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
        #expect(loadedNote?.isPinned == true)
        #expect(audioAttachmentCount == 0)
        #expect(hasPinnedColumn == true)
        #expect(hasLastViewedColumn == false)
    }


    @Test
    @MainActor
    func migrationFromV2PreservesRestoredPinnedColumnAndDropsLastViewedColumn() async throws {
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
        #expect(loadedNote?.isPinned == true)
        #expect(hasPinnedColumn == true)
        #expect(hasLastViewedColumn == false)
    }

    @Test
    @MainActor
    func migrationFromV3ToV4DefaultsAllExistingNotesPinnedFalse() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = rootURL.appendingPathComponent("default.store")
        let configuration = ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
        defer { try? fileManager.removeItem(at: rootURL) }

        try PersistenceController.prepareStoreDirectory(for: configuration, fileManager: fileManager)

        let firstNoteID = UUID()
        let secondNoteID = UUID()
        let createdAt = Date()
        do {
            let v3Container = try ModelContainer(
                for: Schema(versionedSchema: SecondBrainSchemaV3.self),
                configurations: configuration
            )
            let context = v3Container.mainContext
            let firstNote = SecondBrainSchemaV3.NoteRecord(
                id: firstNoteID,
                title: "V3 first note",
                bodyText: "some body",
                searchableText: "v3 first note some body",
                createdAt: createdAt,
                updatedAt: createdAt
            )
            let secondNote = SecondBrainSchemaV3.NoteRecord(
                id: secondNoteID,
                title: "V3 second note",
                bodyText: "other body",
                searchableText: "v3 second note other body",
                createdAt: createdAt.addingTimeInterval(1),
                updatedAt: createdAt.addingTimeInterval(1)
            )
            context.insert(firstNote)
            context.insert(secondNote)
            try context.save()
        }

        let summaries: [NoteSummary]
        let firstLoadedNote: Note?
        let secondLoadedNote: Note?
        do {
            let migrated = try PersistenceController(configuration: configuration)
            summaries = try await migrated.repository.listNotes(matching: nil)
            firstLoadedNote = try await migrated.repository.loadNote(id: firstNoteID)
            secondLoadedNote = try await migrated.repository.loadNote(id: secondNoteID)
        }

        let hasPinnedColumn = try columnExists(inSQLiteStoreAt: storeURL, table: "ZNOTERECORD", column: "ZISPINNED")

        #expect(summaries.count == 2)
        #expect(summaries.allSatisfy { $0.isPinned == false })
        #expect(firstLoadedNote?.displayTitle == "V3 first note")
        #expect(firstLoadedNote?.isPinned == false)
        #expect(secondLoadedNote?.displayTitle == "V3 second note")
        #expect(secondLoadedNote?.isPinned == false)
        #expect(hasPinnedColumn == true)
    }

}
