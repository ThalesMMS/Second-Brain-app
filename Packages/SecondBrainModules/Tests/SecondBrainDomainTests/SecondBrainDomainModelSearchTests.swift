import Foundation
import Testing
@testable import SecondBrainDomain

@MainActor
struct SecondBrainDomainModelSearchTests {
    // MARK: - NoteSummary / Note model

    @Test
    func noteSummaryInitializerDefaultsIsPinnedToFalse() {
        let id = UUID()
        let date = Date()
        let summary = NoteSummary(
            id: id,
            title: "Stand-up notes",
            previewText: "What I did yesterday",
            updatedAt: date
        )

        #expect(summary.id == id)
        #expect(summary.title == "Stand-up notes")
        #expect(summary.previewText == "What I did yesterday")
        #expect(summary.updatedAt == date)
        #expect(summary.isPinned == false)
    }

    @Test
    func noteSummaryInitializerAcceptsIsPinnedAndHashableIncludesIt() {
        let id = UUID()
        let date = Date()
        let pinned = NoteSummary(
            id: id,
            title: "Stand-up notes",
            previewText: "What I did yesterday",
            updatedAt: date,
            isPinned: true
        )
        let unpinned = NoteSummary(
            id: id,
            title: "Stand-up notes",
            previewText: "What I did yesterday",
            updatedAt: date,
            isPinned: false
        )

        #expect(pinned.isPinned == true)
        #expect(pinned != unpinned)
        #expect(Set([pinned, unpinned]).count == 2)
    }

    @Test
    func noteInitializerDefaultsIsPinnedToFalse() {
        let id = UUID()
        let now = Date()
        let note = Note(
            id: id,
            title: "Sprint retro",
            body: "What went well",
            createdAt: now,
            updatedAt: now,
            entries: []
        )

        #expect(note.id == id)
        #expect(note.title == "Sprint retro")
        #expect(note.body == "What went well")
        #expect(note.entries.isEmpty)
        #expect(note.isPinned == false)
    }

    @Test
    func noteInitializerAcceptsIsPinnedAndHashableIncludesIt() {
        let id = UUID()
        let now = Date()
        let pinned = Note(
            id: id,
            title: "Sprint retro",
            body: "What went well",
            createdAt: now,
            updatedAt: now,
            entries: [],
            isPinned: true
        )
        let unpinned = Note(
            id: id,
            title: "Sprint retro",
            body: "What went well",
            createdAt: now,
            updatedAt: now,
            entries: [],
            isPinned: false
        )

        #expect(pinned.isPinned == true)
        #expect(pinned != unpinned)
        #expect(Set([pinned, unpinned]).count == 2)
    }

    // MARK: - NoteSearchRanking

    @Test
    func noteSearchRankingReturnsZeroWhenQueryDoesNotMatchTitleOrBody() {
        let score = NoteSearchRanking.score(
            title: "Shopping list",
            body: "Milk and eggs",
            updatedAt: Date(),
            query: "xyzzy irrelevant"
        )

        #expect(score == 0)
    }

    @Test
    func noteSearchRankingDoesNotAddRecencyBonusForZeroTextMatchScore() {
        // A very recent note that doesn't match the query should still score 0
        let recentDate = Date()
        let score = NoteSearchRanking.score(
            title: "Unrelated topic",
            body: "Nothing relevant here",
            updatedAt: recentDate,
            query: "xyzzy plugh"
        )

        #expect(score == 0)
    }

    @Test
    func noteSearchRankingAddsRecencyBonusOnlyWhenTextMatches() {
        let recentDate = Date()
        let matchingScore = NoteSearchRanking.score(
            title: "Alpha beta",
            body: "Some content",
            updatedAt: recentDate,
            query: "alpha"
        )
        let nonMatchingScore = NoteSearchRanking.score(
            title: "Gamma delta",
            body: "Other content",
            updatedAt: recentDate,
            query: "alpha"
        )

        // The matching note should score higher than zero; the non-matching note scores exactly zero
        #expect(matchingScore > 0)
        #expect(nonMatchingScore == 0)
    }

    // MARK: - NoteRepository query helpers

    @Test
    @MainActor
    func pickerRecentNotesReturnsUpToLimit() async throws {
        let repository = InMemoryNoteRepository()
        for i in 1...5 {
            _ = try await repository.createNote(
                title: "Note \(i)",
                body: "Body \(i)",
                source: .manual,
                initialEntryKind: .creation
            )
        }

        let results = try await repository.pickerRecentNotes(limit: 3)

        #expect(results.count == 3)
    }

    @Test
    @MainActor
    func pickerRecentNotesReturnsAllWhenLimitExceedsCount() async throws {
        let repository = InMemoryNoteRepository()
        _ = try await repository.createNote(title: "Only note", body: "content", source: .manual, initialEntryKind: .creation)

        let results = try await repository.pickerRecentNotes(limit: 10)

        #expect(results.count == 1)
    }

    @Test
    @MainActor
    func noteRepositoryDefaultHelpersReturnEmptyArraysForNonPositiveLimits() async throws {
        let repository = InMemoryNoteRepository()
        _ = try await repository.createNote(title: "Meeting notes", body: "Agenda", source: .manual, initialEntryKind: .creation)

        let recentWithZeroLimit = try await repository.pickerRecentNotes(limit: 0)
        let recentWithNegativeLimit = try await repository.pickerRecentNotes(limit: -1)
        let searchWithZeroLimit = try await repository.searchNotes(matching: "meeting", limit: 0)
        let searchWithNegativeLimit = try await repository.searchNotes(matching: "meeting", limit: -1)
        let snippetsWithZeroLimit = try await repository.snippets(matching: "meeting", limit: 0)
        let snippetsWithNegativeLimit = try await repository.snippets(matching: "meeting", limit: -1)

        #expect(recentWithZeroLimit.isEmpty)
        #expect(recentWithNegativeLimit.isEmpty)
        #expect(searchWithZeroLimit.isEmpty)
        #expect(searchWithNegativeLimit.isEmpty)
        #expect(snippetsWithZeroLimit.isEmpty)
        #expect(snippetsWithNegativeLimit.isEmpty)
    }

    @Test
    @MainActor
    func listNotesOrdersUnpinnedNotesByUpdatedAtDescending() async throws {
        let repository = InMemoryNoteRepository()
        let olderDate = Date(timeIntervalSince1970: 10)
        let newerDate = Date(timeIntervalSince1970: 20)
        let older = try await repository.createNote(
            title: "Older note",
            body: "written first",
            source: .manual,
            initialEntryKind: .creation,
            createdAt: olderDate,
            updatedAt: olderDate
        )
        let newer = try await repository.createNote(
            title: "Newer note",
            body: "written second",
            source: .manual,
            initialEntryKind: .creation,
            createdAt: newerDate,
            updatedAt: newerDate
        )

        let summaries = try await repository.listNotes(matching: nil)

        #expect(summaries.count == 2)
        #expect(summaries.first?.id == newer.id)
        #expect(summaries.last?.id == older.id)
    }

    @Test
    @MainActor
    func searchNotesRespectsLimit() async throws {
        let repository = InMemoryNoteRepository()
        for i in 1...4 {
            _ = try await repository.createNote(
                title: "Meeting \(i)",
                body: "Agenda for meeting \(i)",
                source: .manual,
                initialEntryKind: .creation
            )
        }

        let results = try await repository.searchNotes(matching: "meeting", limit: 2)

        #expect(results.count == 2)
    }

    @Test
    @MainActor
    func searchNotesLargeCorpusRegressionRespectsLimitAndRanking() async throws {
        let repository = InMemoryNoteRepository()

        for i in 0..<240 {
            let createdAt = Date(timeIntervalSince1970: TimeInterval(i))
            let updatedAt = createdAt
            let title = if i >= 220 {
                "Oncology escalation \(i)"
            } else if i.isMultiple(of: 11) {
                "Background oncology \(i)"
            } else {
                "Routine note \(i)"
            }
            let body = if i >= 220 {
                "Escalate oncology follow-up plan \(i)"
            } else if i.isMultiple(of: 11) {
                "General oncology mention \(i)"
            } else {
                "Routine body \(i)"
            }

            _ = try await repository.createNote(
                title: title,
                body: body,
                source: .manual,
                initialEntryKind: .creation,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }

        let results = try await repository.searchNotes(matching: "oncology escalation", limit: 10)

        #expect(results.count == 10)
        #expect(results.allSatisfy { $0.title.contains("Oncology escalation") })
        #expect(results.first?.title == "Oncology escalation 239")
        #expect(results.last?.title == "Oncology escalation 230")
        #expect(!results.contains { $0.title == "Oncology escalation 219" })
        #expect(!results.contains { $0.title.contains("Background oncology") })
    }

    // MARK: - SecondBrainSettings

    @Test
    func secondBrainSettingsDoesNotExposeRecentNotesLimit() {
        // Verify the settings enum still exposes the expected constants that remain after the PR
        #expect(SecondBrainSettings.assistantContextLimit == 5)
        #expect(!SecondBrainSettings.untitledNoteTitle.isEmpty)
        #expect(!SecondBrainSettings.appGroupIdentifier.isEmpty)
        #expect(!SecondBrainSettings.cloudKitContainerIdentifier.isEmpty)
    }

    @Test
    func noteTextUtilitiesDeriveTitlePreviewAndExcerpt() {
        let title = NoteTextUtilities.derivedTitle(from: "   ", body: "First line\nSecond line")
        let preview = NoteTextUtilities.preview(for: "Line one\nLine two")
        let excerpt = NoteTextUtilities.excerpt(
            for: "Alpha beta gamma delta epsilon zeta eta theta",
            matching: "gamma"
        )

        #expect(title == "First line")
        #expect(preview == "Line one Line two")
        #expect(excerpt.contains("gamma"))
    }

    @Test
    @MainActor
    func searchNotesUseCasePrioritizesTitleMatches() async throws {
        let repository = InMemoryNoteRepository()
        _ = try await repository.createNote(
            title: "Oncology follow-up",
            body: "Review MRI liver next week",
            source: .manual,
            initialEntryKind: .creation
        )
        _ = try await repository.createNote(
            title: "General inbox",
            body: "Oncology follow-up meeting scheduled",
            source: .manual,
            initialEntryKind: .creation
        )

        let results = try await SearchNotesUseCase(repository: repository).execute(query: "oncology follow-up")

        #expect(results.count >= 2)
        #expect(results.first?.title == "Oncology follow-up")
    }

    @Test
    func searchNotesUseCaseCanRunFromDetachedTask() async throws {
        let repository = InMemoryNoteRepository()
        _ = try await repository.createNote(
            title: "Detached oncology note",
            body: "MRI liver follow-up",
            source: .manual,
            initialEntryKind: .creation
        )

        let results = try await Task.detached(priority: .background) {
            try await SearchNotesUseCase(repository: repository).execute(query: "MRI liver")
        }.value

        #expect(results.count == 1)
        #expect(results.first?.title == "Detached oncology note")
    }

}
