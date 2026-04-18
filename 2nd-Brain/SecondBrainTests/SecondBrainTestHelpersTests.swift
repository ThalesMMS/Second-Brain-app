import Foundation
import Testing
import SecondBrainComposition
import SecondBrainDomain
@testable import SecondBrain

// MARK: - makeTemporaryRecordingURL

@Suite
struct MakeTemporaryRecordingURLTests {
    @Test
    func makeTemporaryRecordingURLProducesM4AExtension() {
        let url = makeTemporaryRecordingURL()

        #expect(url.pathExtension == "m4a")
    }

    @Test
    func makeTemporaryRecordingURLIsInsideTemporaryDirectory() {
        let url = makeTemporaryRecordingURL()
        let tempDir = FileManager.default.temporaryDirectory.standardized.path

        #expect(url.standardized.path.hasPrefix(tempDir))
    }

    @Test
    func makeTemporaryRecordingURLProducesUniqueURLsOnEachCall() {
        let first = makeTemporaryRecordingURL()
        let second = makeTemporaryRecordingURL()

        #expect(first != second)
    }

    @Test
    func makeUITestAudioURLDelegatesToMakeTemporaryRecordingURL() {
        // makeUITestAudioURL is a thin wrapper — verify it produces a valid .m4a URL
        let url = makeUITestAudioURL()

        #expect(url.pathExtension == "m4a")
    }
}

// MARK: - seedNotes

@Suite
struct SeedNotesTests {
    @Test
    @MainActor
    func seedNotesWithZeroCountCreatesNoNotes() async throws {
        let graph = try makeInMemoryGraph()

        try await seedNotes(in: graph, count: 0, titlePrefix: "Note", bodyPrefix: "Body")

        let notes = try await graph.listNotes.execute(matching: nil)
        #expect(notes.isEmpty)
    }

    @Test
    @MainActor
    func seedNotesWithPositiveCountCreatesCorrectNumberOfNotes() async throws {
        let graph = try makeInMemoryGraph()

        try await seedNotes(in: graph, count: 5, titlePrefix: "Item", bodyPrefix: "Content")

        let notes = try await graph.listNotes.execute(matching: nil)
        #expect(notes.count == 5)
    }

    @Test
    @MainActor
    func seedNotesTitlesAndBodiesIncludeIndexSuffix() async throws {
        let graph = try makeInMemoryGraph()

        try await seedNotes(in: graph, count: 3, titlePrefix: "Note", bodyPrefix: "Body")

        let notes = try await graph.listNotes.execute(matching: nil)
        let titles = Set(notes.map(\.title))
        let bodies = Set(notes.map(\.body))
        let expectedTitles: Set<String> = ["Note 0", "Note 1", "Note 2"]
        let expectedBodies: Set<String> = ["Body 0", "Body 1", "Body 2"]
        #expect(titles == expectedTitles)
        #expect(bodies == expectedBodies)
    }

    @Test
    @MainActor
    func seedNotesWithNegativeCountThrowsInvalidCount() async throws {
        let graph = try makeInMemoryGraph()

        await #expect(throws: SeedNotesError.self) {
            try await seedNotes(in: graph, count: -1, titlePrefix: "Note", bodyPrefix: "Body")
        }
    }

}

// MARK: - GraphInjectionCoordinator

@Suite(.serialized)
struct GraphInjectionCoordinatorTests {
    @Test
    @MainActor
    func graphInjectionCoordinatorRunExclusiveReturnsBlockResult() async throws {
        let coordinator = GraphInjectionCoordinator()
        let result = try await coordinator.runExclusive { 42 }
        #expect(result == 42)
    }

    @Test
    @MainActor
    func graphInjectionCoordinatorRunExclusivePropagatesErrors() async {
        struct TestError: Error {}
        let coordinator = GraphInjectionCoordinator()

        await #expect(throws: TestError.self) {
            try await coordinator.runExclusive { throw TestError() }
        }
    }

    @Test
    @MainActor
    func graphInjectionCoordinatorRunExclusiveReleasesLockAfterThrowing() async throws {
        struct TestError: Error {}
        let coordinator = GraphInjectionCoordinator()

        // First call throws
        try? await coordinator.runExclusive { throw TestError() }

        // Second call should not deadlock — lock was released after throw
        let result = try await coordinator.runExclusive { "recovered" }
        #expect(result == "recovered")
    }

    @Test
    @MainActor
    func graphInjectionCoordinatorConcurrentCallsBothComplete() async throws {
        let coordinator = GraphInjectionCoordinator()
        var order: [Int] = []

        async let first: Void = coordinator.runExclusive {
            order.append(1)
        }
        async let second: Void = coordinator.runExclusive {
            order.append(2)
        }
        _ = try await (first, second)

        // Acquisition order for concurrent calls is not part of this helper's contract.
        #expect(Set(order) == Set([1, 2]))
    }
}

// MARK: - withInjectedGraph

@Suite(.serialized)
struct WithInjectedGraphTests {
    @Test
    @MainActor
    func withInjectedGraphPropagatesErrorsFromGraphFactory() async {
        await #expect(throws: AppGraphBootstrapError.self) {
            try await withInjectedGraph({
                throw AppGraphBootstrapError(
                    summary: "Store unavailable",
                    details: "Intentional test error"
                )
            }) {
                _ = try NoteIntentEnvironment.graph()
            }
        }
    }
}
