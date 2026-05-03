import AppIntents
import Foundation
import Testing
import SecondBrainComposition
import SecondBrainDomain
@testable import SecondBrain

@Suite
struct NoteEntityTests {
    @Test
    @MainActor
    func noteEntityInitFromNoteMapsIdDisplayTitleAndPreviewText() async throws {
        let graph = try makeInMemoryGraph()
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
        #expect(entity.title == summary.displayTitle)
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
    func noteEntityDisplayRepresentationOmitsSubtitleWhenPreviewTextIsNonEmpty() throws {
        let entity = NoteEntity(id: UUID(), title: "Standup", previewText: "Reviewed PRs")

        let representation = entity.displayRepresentation
        #expect(representation.subtitle == nil)
    }

    // MARK: - Additional edge cases

    @Test
    @MainActor
    func noteEntityDisplayRepresentationUsesOnlyTitleWhenPreviewTextIsNonEmpty() {
        let entity = NoteEntity(id: UUID(), title: "Weekly sync", previewText: "Agenda items")

        let representation = entity.displayRepresentation

        #expect(representation.title.key == "Weekly sync")
        #expect(representation.subtitle == nil)
    }

    @Test
    @MainActor
    func noteEntityInitFromSummaryWithNonEmptyPreviewTextPreservesPreviewText() {
        let previewText = "This is the preview."
        let summary = NoteSummary(
            id: UUID(),
            title: "Some note",
            previewText: previewText,
            updatedAt: Date()
        )

        let entity = NoteEntity(summary: summary)

        #expect(entity.previewText == previewText)
    }

    @Test
    @MainActor
    func noteEntityTombstonePreviewTextIsEmpty() {
        // Regression: tombstone preview must be empty so displayRepresentation omits subtitle
        let entity = NoteEntity(tombstoneWithID: UUID())

        let representation = entity.displayRepresentation
        #expect(representation.subtitle == nil)
    }

    @Test
    @MainActor
    func noteEntityIDIsStableAcrossRepeatedAccesses() {
        let id = UUID()
        let entity = NoteEntity(id: id, title: "Stable", previewText: "")

        #expect(entity.id == id)
        #expect(entity.id == id)
    }
}
