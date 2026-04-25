import Foundation
import Testing
@testable import SecondBrainDomain

@MainActor
struct SecondBrainDomainNoteUseCaseTests {
    // MARK: - CreateNoteUseCase (async)

    @Test
    @MainActor
    func createNoteUseCasePropagatesEmptyContentError() async throws {
        let repository = InMemoryNoteRepository()
        let useCase = CreateNoteUseCase(repository: repository)

        do {
            _ = try await useCase.execute(title: "  ", body: "\n\n", source: .manual)
            Issue.record("Expected CreateNoteUseCase to throw emptyContent.")
        } catch let error as NoteRepositoryError {
            #expect(error == .emptyContent)
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test
    @MainActor
    func createNoteUseCaseReturnsNoteWithExpectedContent() async throws {
        let repository = InMemoryNoteRepository()
        let useCase = CreateNoteUseCase(repository: repository)

        let note = try await useCase.execute(title: "Alpha", body: "Body text", source: .manual)

        #expect(note.displayTitle == "Alpha")
        #expect(note.body == "Body text")
        #expect(note.entries.first?.kind == .creation)
    }

    // MARK: - DeleteNoteUseCase (async)

    @Test
    @MainActor
    func deleteNoteUseCaseRemovesNote() async throws {
        let repository = InMemoryNoteRepository()
        let note = try await repository.createNote(
            title: "To delete",
            body: "gone",
            source: .manual,
            initialEntryKind: .creation
        )

        try await DeleteNoteUseCase(repository: repository).execute(noteID: note.id)

        let loaded = try await repository.loadNote(id: note.id)
        #expect(loaded == nil)
    }

    @Test
    @MainActor
    func deleteNoteUseCaseIsNoOpForUnknownID() async throws {
        let repository = InMemoryNoteRepository()
        // Should not throw for a non-existent ID
        try await DeleteNoteUseCase(repository: repository).execute(noteID: UUID())
    }

    // MARK: - SaveNoteUseCase (async)

    @Test
    @MainActor
    func saveNoteUseCaseReplacesNoteContent() async throws {
        let repository = InMemoryNoteRepository()
        let original = try await repository.createNote(
            title: "Old title",
            body: "Old body",
            source: .manual,
            initialEntryKind: .creation
        )

        let updated = try await SaveNoteUseCase(repository: repository).execute(
            noteID: original.id,
            title: "New title",
            body: "New body",
            lastSeenUpdatedAt: original.updatedAt,
            source: .manual
        )

        #expect(updated.displayTitle == "New title")
        #expect(updated.body == "New body")
        #expect(updated.entries.count == 2)
        #expect(updated.entries.last?.kind == .replaceBody)
    }

    @Test
    @MainActor
    func saveNoteUseCaseThrowsWhenNoteNotFound() async throws {
        let repository = InMemoryNoteRepository()

        do {
            _ = try await SaveNoteUseCase(repository: repository).execute(
                noteID: UUID(),
                title: "T",
                body: "B",
                lastSeenUpdatedAt: .distantPast,
                source: .manual
            )
            Issue.record("Expected SaveNoteUseCase to throw notFound.")
        } catch let error as NoteRepositoryError {
            #expect(error == .notFound)
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test
    @MainActor
    func saveNoteUseCaseThrowsConflictWhenNoteChangesBeforeReplace() async throws {
        let repository = InMemoryNoteRepository()
        let note = try await repository.createNote(
            title: "Stale title",
            body: "Stale body",
            source: .manual,
            initialEntryKind: .creation
        )

        await repository.mutateOnNextReplace(id: note.id)

        do {
            _ = try await SaveNoteUseCase(repository: repository).execute(
                noteID: note.id,
                title: "Updated title",
                body: "Updated body",
                lastSeenUpdatedAt: note.updatedAt,
                source: .manual
            )
            Issue.record("Expected a conflict for a stale save.")
        } catch let error as NoteRepositoryError {
            switch error {
            case .conflict:
                break
            default:
                Issue.record("Unexpected repository error: \(error.localizedDescription)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - SetNotePinnedUseCase (async)

    @Test
    @MainActor
    func setNotePinnedUseCasePinsAndUnpinsNoteWithoutChangingContent() async throws {
        let repository = InMemoryNoteRepository()
        let note = try await repository.createNote(
            title: "Reference",
            body: "Body",
            source: .manual,
            initialEntryKind: .creation
        )

        try await SetNotePinnedUseCase(repository: repository).execute(noteID: note.id, isPinned: true)
        let pinned = try #require(try await repository.loadNote(id: note.id))

        #expect(pinned.isPinned == true)
        #expect(pinned.displayTitle == "Reference")
        #expect(pinned.body == "Body")
        #expect(pinned.updatedAt == note.updatedAt)

        try await SetNotePinnedUseCase(repository: repository).execute(noteID: note.id, isPinned: false)
        let unpinned = try #require(try await repository.loadNote(id: note.id))

        #expect(unpinned.isPinned == false)
        #expect(unpinned.updatedAt == note.updatedAt)
    }

    @Test
    @MainActor
    func setNotePinnedUseCaseThrowsWhenNoteNotFound() async throws {
        let repository = InMemoryNoteRepository()

        do {
            try await SetNotePinnedUseCase(repository: repository).execute(noteID: UUID(), isPinned: true)
            Issue.record("Expected SetNotePinnedUseCase to throw notFound.")
        } catch let error as NoteRepositoryError {
            #expect(error == .notFound)
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test
    @MainActor
    func listNotesUseCaseReturnsPinnedNotesBeforeUnpinnedNotes() async throws {
        let repository = InMemoryNoteRepository()
        let olderPinned = try await repository.createNote(
            title: "Pinned",
            body: "older",
            source: .manual,
            initialEntryKind: .creation,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        let newerUnpinned = try await repository.createNote(
            title: "Unpinned",
            body: "newer",
            source: .manual,
            initialEntryKind: .creation,
            createdAt: Date(timeIntervalSince1970: 20),
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        try await SetNotePinnedUseCase(repository: repository).execute(noteID: olderPinned.id, isPinned: true)

        let summaries = try await ListNotesUseCase(repository: repository).execute(matching: nil)

        #expect(summaries.map(\.id) == [olderPinned.id, newerUnpinned.id])
        #expect(summaries.first?.isPinned == true)
    }

    // MARK: - ListNotesUseCase (async)

    @Test
    @MainActor
    func listNotesUseCaseReturnsAllNotesForNilQuery() async throws {
        let repository = InMemoryNoteRepository()
        _ = try await repository.createNote(title: "A", body: "first", source: .manual, initialEntryKind: .creation)
        _ = try await repository.createNote(title: "B", body: "second", source: .manual, initialEntryKind: .creation)

        let summaries = try await ListNotesUseCase(repository: repository).execute(matching: nil)

        #expect(summaries.count == 2)
    }

    @Test
    @MainActor
    func listNotesUseCaseFiltersResultsByQuery() async throws {
        let repository = InMemoryNoteRepository()
        _ = try await repository.createNote(title: "Coffee notes", body: "espresso", source: .manual, initialEntryKind: .creation)
        _ = try await repository.createNote(title: "Tea notes", body: "green tea", source: .manual, initialEntryKind: .creation)

        let results = try await ListNotesUseCase(repository: repository).execute(matching: "coffee")

        #expect(results.count == 1)
        #expect(results.first?.title == "Coffee notes")
    }

    // MARK: - LoadNoteUseCase (async)

    @Test
    @MainActor
    func loadNoteUseCaseReturnsNilForMissingNote() async throws {
        let repository = InMemoryNoteRepository()

        let result = try await LoadNoteUseCase(repository: repository).execute(id: UUID())

        #expect(result == nil)
    }

    @Test
    @MainActor
    func loadNoteUseCaseReturnsNoteWhenPresent() async throws {
        let repository = InMemoryNoteRepository()
        let note = try await repository.createNote(
            title: "Present",
            body: "body",
            source: .manual,
            initialEntryKind: .creation
        )

        let loaded = try await LoadNoteUseCase(repository: repository).execute(id: note.id)

        #expect(loaded?.id == note.id)
        #expect(loaded?.displayTitle == "Present")
    }

    // MARK: - AppendToNoteUseCase (async, reference overload)

    @Test
    @MainActor
    func appendToNoteUseCaseByReferenceThrowsWhenNoteNotFound() async throws {
        let repository = InMemoryNoteRepository()

        do {
            _ = try await AppendToNoteUseCase(repository: repository)
                .execute(reference: "xyzzy-no-match", text: "text", source: .manual)
            Issue.record("Expected AppendToNoteUseCase to throw notFound.")
        } catch let error as NoteRepositoryError {
            #expect(error == .notFound)
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test
    @MainActor
    func appendToNoteUseCaseByReferenceAppendsText() async throws {
        let repository = InMemoryNoteRepository()
        let note = try await repository.createNote(
            title: "Shopping list",
            body: "Banana",
            source: .manual,
            initialEntryKind: .creation
        )

        let updated = try await AppendToNoteUseCase(repository: repository)
            .execute(reference: note.displayTitle, text: "Avocado", source: .manual)

        #expect(updated.body.contains("Banana"))
        #expect(updated.body.contains("Avocado"))
        #expect(updated.entries.count == 2)
    }


    // MARK: - NoteRepository default extension async coverage

    @Test
    @MainActor
    func resolveNoteReferenceByIDReturnsCorrectNote() async throws {
        let repository = InMemoryNoteRepository()
        let note = try await repository.createNote(
            title: "UUID lookup",
            body: "content",
            source: .manual,
            initialEntryKind: .creation
        )

        let resolved = try await repository.resolveNoteReference(note.id.uuidString)

        #expect(resolved?.id == note.id)
    }

    @Test
    @MainActor
    func resolveNoteReferenceWithEmptyStringReturnsMostRecent() async throws {
        let repository = InMemoryNoteRepository()
        let olderDate = Date(timeIntervalSince1970: 30)
        let recentDate = Date(timeIntervalSince1970: 40)
        _ = try await repository.createNote(
            title: "Older",
            body: "first",
            source: .manual,
            initialEntryKind: .creation,
            createdAt: olderDate,
            updatedAt: olderDate
        )
        let recent = try await repository.createNote(
            title: "Recent",
            body: "second",
            source: .manual,
            initialEntryKind: .creation,
            createdAt: recentDate,
            updatedAt: recentDate
        )

        let resolved = try await repository.resolveNoteReference("")

        #expect(resolved?.id == recent.id)
    }

}
