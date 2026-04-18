import Foundation
import Testing
@testable import SecondBrainDomain
@testable import SecondBrainPersistence

struct SeededNoteDataTests {
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
    func seededNoteEntryDataStoresDifferentKindAndSource() {
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

}
