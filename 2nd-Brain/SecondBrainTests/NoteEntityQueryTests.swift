import Foundation
import Testing
import SecondBrainComposition
import SecondBrainDomain
@testable import SecondBrain

@Suite(.serialized)
struct NoteEntityQueryTests {
    @Test
    @MainActor
    func noteEntityQueryRehydratesExistingNotesByIdentifier() async throws {
        let graph = try makeInMemoryGraph()
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
        let graph = try makeInMemoryGraph()
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
        let graph = try makeInMemoryGraph()

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
        let graph = try makeInMemoryGraph()
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
        let graph = try makeInMemoryGraph()
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
        let graph = try makeInMemoryGraph()

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
        let graph = try makeInMemoryGraph()
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
    func noteEntityQueryReturnsTombstonesForUnknownIdentifiers() async throws {
        let graph = try makeInMemoryGraph()
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
        let graph = try makeInMemoryGraph()
        _ = try await graph.createNote.execute(title: "Some note", body: "Body", source: .manual)

        let entities = try await withInjectedGraph({ graph }) {
            try await NoteEntityQuery().entities(for: [])
        }

        #expect(entities.isEmpty)
    }

    @Test
    @MainActor
    func noteEntityQueryEntitiesMatchingWhitespaceOnlyFallsBackToSuggestedEntities() async throws {
        let graph = try makeInMemoryGraph()
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
        let graph = try makeInMemoryGraph()
        _ = try await graph.createNote.execute(title: "Meeting notes", body: "Discuss Q4", source: .manual)

        let entities = try await withInjectedGraph({ graph }) {
            try await NoteEntityQuery().entities(matching: "xyzzy irrelevant nonsense")
        }

        #expect(entities.isEmpty)
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

    // MARK: - Additional edge cases

    @Test
    @MainActor
    func noteEntityQueryEntitiesForExactlyTenIDsReturnsAllTen() async throws {
        let graph = try makeInMemoryGraph()
        var ids: [UUID] = []
        for index in 0..<10 {
            let note = try await graph.createNote.execute(
                title: "Note \(index)",
                body: "Body \(index)",
                source: .manual
            )
            ids.append(note.id)
        }

        let entities = try await withInjectedGraph({ graph }) {
            try await NoteEntityQuery().entities(for: ids)
        }

        // At the cap boundary (10) all requested IDs should be returned
        #expect(entities.count == 10)
        #expect(Set(entities.map(\.id)) == Set(ids))
    }

    @Test
    @MainActor
    func noteEntityQueryEntitiesMatchingFindsResultsInNoteBody() async throws {
        let graph = try makeInMemoryGraph()
        let bodyOnlyMatch = try await graph.createNote.execute(
            title: "Daily standup",
            body: "Discussed the onboarding funnel",
            source: .manual
        )
        _ = try await graph.createNote.execute(
            title: "Sprint review",
            body: "Reviewed completed tickets",
            source: .manual
        )

        let entities = try await withInjectedGraph({ graph }) {
            try await NoteEntityQuery().entities(matching: "onboarding")
        }

        // The match is in the body, not the title
        #expect(entities.count == 1)
        #expect(entities.first?.id == bodyOnlyMatch.id)
    }

    @Test
    @MainActor
    func noteEntityQueryEntitiesForSingleTombstoneIDReturnsTombstone() async throws {
        let graph = try makeInMemoryGraph()
        let phantomID = UUID()

        let entities = try await withInjectedGraph({ graph }) {
            try await NoteEntityQuery().entities(for: [phantomID])
        }

        #expect(entities.count == 1)
        #expect(entities.first?.id == phantomID)
        #expect(entities.first?.title == "Unavailable note")
    }

    @Test
    @MainActor
    func noteEntityQueryEntitiesMatchingBootstrapFailurePropagatesError() async {
        let query = NoteEntityQuery()

        await #expect(throws: AppGraphBootstrapError.self) {
            try await withInjectedGraph({
                throw AppGraphBootstrapError(
                    summary: "Store unavailable.",
                    details: "Injected error for entities(matching:) path."
                )
            }) {
                _ = try await query.entities(matching: "anything")
            }
        }
    }
}