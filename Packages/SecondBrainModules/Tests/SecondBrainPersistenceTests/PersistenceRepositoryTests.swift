import Foundation
import Testing
@testable import SecondBrainDomain
@testable import SecondBrainPersistence

struct PersistenceRepositoryTests {
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
    func listNotesOrdersPinnedNotesFirstThenUpdatedAtDescending() async throws {
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
        try await persistence.repository.setPinned(id: second.id, isPinned: true)

        let summaries = try await persistence.repository.listNotes(matching: nil)

        #expect(summaries.count == 2)
        #expect(summaries.map(\.id) == [second.id, first.id])
        #expect(summaries[0].isPinned == true)
        #expect(summaries[1].isPinned == false)
        _ = updated
    }

    @Test
    @MainActor
    func listNotesMaintainsUpdatedAtDescendingWithinPinnedAndUnpinnedGroups() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let olderPinned = try await persistence.repository.createNote(
            title: "Pinned old",
            body: "older pinned",
            source: .manual,
            initialEntryKind: .creation
        )
        let newerPinned = try await persistence.repository.createNote(
            title: "Pinned new",
            body: "newer pinned",
            source: .manual,
            initialEntryKind: .creation
        )
        let olderUnpinned = try await persistence.repository.createNote(
            title: "Unpinned old",
            body: "older unpinned",
            source: .manual,
            initialEntryKind: .creation
        )
        let newerUnpinned = try await persistence.repository.createNote(
            title: "Unpinned new",
            body: "newer unpinned",
            source: .manual,
            initialEntryKind: .creation
        )

        try await persistence.repository.setPinned(id: olderPinned.id, isPinned: true)
        try await persistence.repository.setPinned(id: newerPinned.id, isPinned: true)

        let summaries = try await persistence.repository.listNotes(matching: nil)

        #expect(summaries.map(\.id) == [
            newerPinned.id,
            olderPinned.id,
            newerUnpinned.id,
            olderUnpinned.id,
        ])
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

    @Test
    @MainActor
    func replaceNoteThrowsConflictWhenExpectedUpdatedAtDoesNotMatch() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let original = try await persistence.repository.createNote(
            title: "Title",
            body: "Body",
            source: .manual,
            initialEntryKind: .creation
        )

        let staleExpectedUpdatedAt = original.updatedAt.addingTimeInterval(-5)

        do {
            _ = try await persistence.repository.replaceNote(
                id: original.id,
                title: "Updated title",
                body: "Updated body",
                source: .manual,
                expectedUpdatedAt: staleExpectedUpdatedAt
            )
            Issue.record("Expected replaceNote with staleExpectedUpdatedAt to throw NoteRepositoryError.conflict.")
        } catch let error as NoteRepositoryError {
            switch error {
            case .conflict:
                break
            default:
                Issue.record("Expected NoteRepositoryError.conflict, got \(error).")
            }
        } catch {
            Issue.record("Expected NoteRepositoryError.conflict, got \(error).")
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
        let older = try await persistence.repository.createNote(
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
        try await persistence.repository.setPinned(id: older.id, isPinned: true)

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
    func createNoteDefaultsToUnpinnedInLoadedNoteAndSummary() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let created = try await persistence.repository.createNote(
            title: "My note",
            body: "Some body text",
            source: .manual,
            initialEntryKind: .creation
        )

        let loaded = try await persistence.repository.loadNote(id: created.id)
        let summaries = try await persistence.repository.listNotes(matching: nil)

        let note = try #require(loaded)
        #expect(note.id == created.id)
        #expect(note.displayTitle == "My note")
        #expect(note.body == "Some body text")
        #expect(note.entries.count == 1)
        #expect(note.isPinned == false)

        let summary = try #require(summaries.first)
        #expect(summary.id == created.id)
        #expect(summary.isPinned == false)
    }

    @Test
    @MainActor
    func setPinnedUpdatesOnlyPinnedFlag() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)
        let created = try await persistence.repository.createNote(
            title: "Pinned note",
            body: "Body text",
            source: .manual,
            initialEntryKind: .creation
        )
        let originalUpdatedAt = created.updatedAt

        try await persistence.repository.setPinned(id: created.id, isPinned: true)

        let loaded = try #require(try await persistence.repository.loadNote(id: created.id))
        let summaries = try await persistence.repository.listNotes(matching: nil)
        let summary = try #require(summaries.first)

        #expect(loaded.isPinned == true)
        #expect(summary.isPinned == true)
        #expect(loaded.updatedAt == originalUpdatedAt)
        #expect(loaded.displayTitle == "Pinned note")
        #expect(loaded.body == "Body text")
    }

    @Test
    @MainActor
    func setPinnedThrowsWhenNoteNotFound() async throws {
        let persistence = try PersistenceController(inMemory: true, enableCloudSync: false)

        await #expect(throws: NoteRepositoryError.self) {
            try await persistence.repository.setPinned(id: UUID(), isPinned: true)
        }
    }

}
