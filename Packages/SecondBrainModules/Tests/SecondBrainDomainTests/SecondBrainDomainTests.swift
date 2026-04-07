import Foundation
import Testing
@testable import SecondBrainDomain

@MainActor
struct SecondBrainDomainTests {
    // MARK: - NoteSummary / Note model

    @Test
    func noteSummaryInitializerHasNoIsPinnedParameter() {
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
    }

    @Test
    func noteInitializerHasNoIsPinnedParameter() {
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
    func listNotesOrdersByUpdatedAtDescendingWithoutPinPriority() async throws {
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

        // The more recently updated note should appear first regardless of any other attribute
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

    @Test
    @MainActor
    func editExistingNoteUseCaseCreatesPendingConfirmationForWholeBodyRewrite() async throws {
        let repository = InMemoryNoteRepository()
        let note = try await repository.createNote(
            title: "Rounds",
            body: "Check CT head",
            source: .manual,
            initialEntryKind: .creation
        )
        let proposal = NoteEditProposal(
            noteID: note.id,
            scope: .wholeBody,
            updatedTitle: note.displayTitle,
            updatedBody: "1. Check CT head\n2. Review chest CT",
            targetExcerpt: nil,
            changeSummary: "Restructure the note as a checklist.",
            clarificationQuestion: nil
        )

        let result = try await EditExistingNoteUseCase(repository: repository).execute(
            proposal: proposal,
            source: .assistant
        )

        switch result {
        case let .pending(pending, message):
            #expect(pending.noteID == note.id)
            #expect(message.contains("Reply \"confirm\""))
        case .applied:
            Issue.record("Expected the edit to require confirmation.")
        default:
            Issue.record("Unexpected edit result.")
        }
    }

    @Test
    @MainActor
    func editExistingNoteUseCaseConfirmAppliesPendingEdit() async throws {
        let repository = InMemoryNoteRepository()
        let note = try await repository.createNote(
            title: "Rounds",
            body: "Check CT head",
            source: .manual,
            initialEntryKind: .creation
        )
        let proposal = NoteEditProposal(
            noteID: note.id,
            scope: .wholeBody,
            updatedTitle: note.displayTitle,
            updatedBody: "1. Check CT head\n2. Review chest CT",
            targetExcerpt: nil,
            changeSummary: "Restructure the note as a checklist.",
            clarificationQuestion: nil
        )
        let useCase = EditExistingNoteUseCase(repository: repository)
        let initialResult = try await useCase.execute(proposal: proposal, source: .assistant)
        let pending = switch initialResult {
        case let .pending(pending, _):
            pending
        case .applied:
            Issue.record("Expected a pending edit before confirmation.")
            throw NoteRepositoryError.notFound
        default:
            Issue.record("Unexpected edit result.")
            throw NoteRepositoryError.notFound
        }

        let resolved = try await useCase.resolve(
            pending: pending,
            decision: .confirm,
            source: .assistant
        )

        switch resolved {
        case let .applied(updated, message):
            #expect(updated.body == "1. Check CT head\n2. Review chest CT")
            #expect(message.contains("Updated note"))
        case .pending:
            Issue.record("Expected the pending edit to be applied.")
        default:
            Issue.record("Unexpected edit result.")
        }
    }

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

    // MARK: - EditExistingNoteUseCase cancel / clarification paths (async)

    @Test
    @MainActor
    func editExistingNoteUseCaseCancelDecisionReturnsCancelled() async throws {
        let repository = InMemoryNoteRepository()
        let note = try await repository.createNote(
            title: "Draft",
            body: "Original content",
            source: .manual,
            initialEntryKind: .creation
        )
        let proposal = NoteEditProposal(
            noteID: note.id,
            scope: .wholeBody,
            updatedTitle: note.displayTitle,
            updatedBody: "Completely different body",
            targetExcerpt: nil,
            changeSummary: "Rewrite the entire note.",
            clarificationQuestion: nil
        )
        let useCase = EditExistingNoteUseCase(repository: repository)
        let pendingResult = try await useCase.execute(proposal: proposal, source: .assistant)

        let pending: PendingNoteEdit
        switch pendingResult {
        case let .pending(p, _):
            pending = p
        default:
            Issue.record("Expected pending result before cancel.")
            return
        }

        let cancelled = try await useCase.resolve(
            pending: pending,
            decision: .cancel,
            source: .assistant
        )

        switch cancelled {
        case let .cancelled(message):
            #expect(message.contains("Cancelled"))
        default:
            Issue.record("Expected cancelled result.")
        }
    }

    @Test
    @MainActor
    func editExistingNoteUseCaseReturnsClarificationForMissingNote() async throws {
        let repository = InMemoryNoteRepository()
        let fakeID = UUID()
        let proposal = NoteEditProposal(
            noteID: fakeID,
            scope: .wholeBody,
            updatedTitle: "Ghost",
            updatedBody: "Irrelevant",
            targetExcerpt: nil,
            changeSummary: "Edit a note that doesn't exist.",
            clarificationQuestion: nil
        )

        let result = try await EditExistingNoteUseCase(repository: repository).execute(
            proposal: proposal,
            source: .assistant
        )

        switch result {
        case let .clarification(message):
            #expect(message.contains("could not be found"))
        default:
            Issue.record("Expected clarification when note does not exist.")
        }
    }

    @Test
    @MainActor
    func editExistingNoteUseCaseNoChangeWhenProposalIsIdentical() async throws {
        let repository = InMemoryNoteRepository()
        let note = try await repository.createNote(
            title: "Idempotent",
            body: "Same body",
            source: .manual,
            initialEntryKind: .creation
        )
        let proposal = NoteEditProposal(
            noteID: note.id,
            scope: .title,
            updatedTitle: note.displayTitle,
            updatedBody: note.body,
            targetExcerpt: nil,
            changeSummary: "No actual change.",
            clarificationQuestion: nil
        )

        let result = try await EditExistingNoteUseCase(repository: repository).execute(
            proposal: proposal,
            source: .assistant
        )

        switch result {
        case .noChange:
            break
        default:
            Issue.record("Expected noChange when title and body are identical.")
        }
    }

    @Test
    @MainActor
    func editExistingNoteUseCaseResolveReturnsClarificationWhenNoteModifiedSincePending() async throws {
        let repository = InMemoryNoteRepository()
        let note = try await repository.createNote(
            title: "Concurrent edit",
            body: "Version one",
            source: .manual,
            initialEntryKind: .creation
        )
        let proposal = NoteEditProposal(
            noteID: note.id,
            scope: .wholeBody,
            updatedTitle: note.displayTitle,
            updatedBody: "Version two",
            targetExcerpt: nil,
            changeSummary: "Replace body.",
            clarificationQuestion: nil
        )
        let useCase = EditExistingNoteUseCase(repository: repository)
        let pendingResult = try await useCase.execute(proposal: proposal, source: .assistant)

        let pending: PendingNoteEdit
        switch pendingResult {
        case let .pending(p, _):
            pending = p
        default:
            Issue.record("Expected pending result.")
            return
        }

        // Simulate a concurrent modification so updatedAt diverges from pending.baseUpdatedAt
        _ = try await repository.appendText("appended concurrently", to: note.id, source: .manual)

        let result = try await useCase.resolve(
            pending: pending,
            decision: .confirm,
            source: .assistant
        )

        switch result {
        case let .clarification(message):
            #expect(message.contains("changed since"))
        default:
            Issue.record("Expected clarification when note was modified after pending edit was created.")
        }
    }

    @Test
    @MainActor
    func editExistingNoteUseCaseReturnsClarificationWhenNoteIsDeletedDuringImmediateApply() async throws {
        let repository = InMemoryNoteRepository()
        let note = try await repository.createNote(
            title: "Title edit",
            body: "Original content",
            source: .manual,
            initialEntryKind: .creation
        )
        let proposal = NoteEditProposal(
            noteID: note.id,
            scope: .title,
            updatedTitle: "Renamed title",
            updatedBody: note.body,
            targetExcerpt: nil,
            changeSummary: "Rename the note.",
            clarificationQuestion: nil
        )

        await repository.deleteOnNextReplace(id: note.id)

        let result = try await EditExistingNoteUseCase(repository: repository).execute(
            proposal: proposal,
            source: .assistant
        )

        switch result {
        case let .clarification(message):
            #expect(message.contains("changed since"))
        default:
            Issue.record("Expected clarification when note was deleted during immediate apply.")
        }
    }

    @Test
    @MainActor
    func editExistingNoteUseCaseResolveReturnsClarificationWhenNoteIsDeletedDuringReplace() async throws {
        let repository = InMemoryNoteRepository()
        let note = try await repository.createNote(
            title: "Pending delete",
            body: "Version one",
            source: .manual,
            initialEntryKind: .creation
        )
        let proposal = NoteEditProposal(
            noteID: note.id,
            scope: .wholeBody,
            updatedTitle: note.displayTitle,
            updatedBody: "Version two",
            targetExcerpt: nil,
            changeSummary: "Replace body.",
            clarificationQuestion: nil
        )
        let useCase = EditExistingNoteUseCase(repository: repository)
        let pendingResult = try await useCase.execute(proposal: proposal, source: .assistant)

        let pending: PendingNoteEdit
        switch pendingResult {
        case let .pending(pendingEdit, _):
            pending = pendingEdit
        default:
            Issue.record("Expected pending result.")
            return
        }

        await repository.deleteOnNextReplace(id: note.id)

        let result = try await useCase.resolve(
            pending: pending,
            decision: .confirm,
            source: .assistant
        )

        switch result {
        case let .clarification(message):
            #expect(message.contains("changed since"))
        default:
            Issue.record("Expected clarification when note was deleted during replace.")
        }
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

    @Test
    @MainActor
    func processVoiceCaptureFallsBackToRawTranscriptWhenIntelligenceIsUnavailable() async throws {
        let repository = InMemoryNoteRepository()
        let sourceURL = try makeSourceAudioFile()
        defer { try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent()) }

        let useCase = ProcessVoiceCaptureUseCase(
            repository: repository,
            transcriptionService: MockSpeechTranscriptionService(result: "raw transcript from speech"),
            captureIntelligence: MockNoteCaptureIntelligenceService(
                capabilityState: .unavailable(reason: "AI-assisted capture is unavailable on watchOS."),
                typedResult: NoteCaptureRefinement(title: "", body: ""),
                transcriptResult: NoteCaptureRefinement(title: "Ignored", body: "Ignored")
            ),
            interpretationService: MockVoiceCaptureInterpretationService(
                result: VoiceCaptureInterpretation(
                    intent: .newNote,
                    normalizedText: "raw transcript from speech"
                )
            ),
            assistant: MockNotesAssistantService(
                capabilityState: .available,
                response: NotesAssistantResponse(text: "", referencedNoteIDs: [])
            )
        )

        let result = try await useCase.execute(
            title: "",
            audioURL: sourceURL,
            locale: .current,
            source: .speechToText
        )

        switch result {
        case let .createdNote(note):
            #expect(note.displayTitle == "raw transcript from speech")
            #expect(note.body == "raw transcript from speech")
            #expect(note.entries.first?.kind == .transcription)
        case .assistantResponse:
            Issue.record("Expected a created note result.")
        }
    }

    @Test
    @MainActor
    func processVoiceCaptureRoutesAssistantCommandsAndPreservesTranscript() async throws {
        let repository = InMemoryNoteRepository()
        let sourceURL = try makeSourceAudioFile()
        defer { try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent()) }
        let noteID = UUID()

        let useCase = ProcessVoiceCaptureUseCase(
            repository: repository,
            transcriptionService: MockSpeechTranscriptionService(result: "replace banana with avocado"),
            captureIntelligence: MockNoteCaptureIntelligenceService(
                typedResult: NoteCaptureRefinement(title: "", body: ""),
                transcriptResult: NoteCaptureRefinement(title: "", body: "")
            ),
            interpretationService: MockVoiceCaptureInterpretationService(
                result: VoiceCaptureInterpretation(
                    intent: .assistantCommand,
                    normalizedText: "in the shopping list, replace banana with avocado"
                )
            ),
            assistant: MockNotesAssistantService(
                capabilityState: .available,
                response: NotesAssistantResponse(
                    text: "Updated note Shopping list.",
                    referencedNoteIDs: [noteID]
                )
            )
        )

        let result = try await useCase.execute(
            title: "",
            audioURL: sourceURL,
            locale: .current,
            source: .speechToText
        )

        switch result {
        case .createdNote:
            Issue.record("Expected an assistant response result.")
        case let .assistantResponse(response, transcript):
            #expect(response.text == "Updated note Shopping list.")
            #expect(response.referencedNoteIDs == [noteID])
            #expect(response.interaction == .none)
            #expect(transcript == "replace banana with avocado")
        }
    }
}

private actor InMemoryNoteRepository: NoteRepository {
    private var notes: [UUID: Note] = [:]
    private var deleteOnNextReplaceID: UUID?
    private var mutateOnNextReplaceID: UUID?

    func listNotes(matching query: String?) async throws -> [NoteSummary] {
        filteredNotes(matching: query).map(makeSummary)
    }

    func pickerRecentNotes(limit: Int) async throws -> [NoteSummary] {
        guard limit > 0 else {
            return []
        }

        return Array(filteredNotes(matching: nil).map(makeSummary).prefix(limit))
    }

    func searchNotes(matching query: String, limit: Int) async throws -> [NoteSummary] {
        guard limit > 0 else {
            return []
        }

        return Array(filteredNotes(matching: query).map(makeSummary).prefix(limit))
    }

    func loadNote(id: UUID) async throws -> Note? {
        notes[id]
    }

    func createNote(
        title: String,
        body: String,
        source: NoteMutationSource,
        initialEntryKind: NoteEntryKind
    ) async throws -> Note {
        let now = Date()
        return try await createNote(
            title: title,
            body: body,
            source: source,
            initialEntryKind: initialEntryKind,
            createdAt: now,
            updatedAt: now
        )
    }

    func createNote(
        title: String,
        body: String,
        source: NoteMutationSource,
        initialEntryKind: NoteEntryKind,
        createdAt: Date,
        updatedAt: Date
    ) async throws -> Note {
        let cleanedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedTitle = NoteTextUtilities.derivedTitle(from: title, body: cleanedBody)
        if cleanedBody.isEmpty && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw NoteRepositoryError.emptyContent
        }

        let note = Note(
            id: UUID(),
            title: cleanedTitle,
            body: cleanedBody,
            createdAt: createdAt,
            updatedAt: updatedAt,
            entries: [
                NoteEntry(
                    id: UUID(),
                    createdAt: createdAt,
                    kind: initialEntryKind,
                    source: source,
                    text: cleanedBody.isEmpty ? cleanedTitle : cleanedBody
                )
            ]
        )
        notes[note.id] = note
        return note
    }

    func appendText(_ text: String, to noteID: UUID, source: NoteMutationSource) async throws -> Note {
        guard var note = notes[noteID] else {
            throw NoteRepositoryError.notFound
        }

        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty else {
            return note
        }

        let now = Date()
        note.body = NoteTextUtilities.append(base: note.body, addition: cleanedText)
        note.title = NoteTextUtilities.derivedTitle(from: note.title, body: note.body)
        note.updatedAt = now
        note.entries.append(
            NoteEntry(
                id: UUID(),
                createdAt: now,
                kind: .append,
                source: source,
                text: cleanedText
            )
        )
        notes[noteID] = note
        return note
    }

    func replaceNote(
        id: UUID,
        title: String,
        body: String,
        source: NoteMutationSource,
        expectedUpdatedAt: Date?
    ) async throws -> Note {
        guard var note = notes[id] else {
            throw NoteRepositoryError.notFound
        }
        if deleteOnNextReplaceID == id {
            deleteOnNextReplaceID = nil
            notes.removeValue(forKey: id)
            throw NoteRepositoryError.notFound
        }
        if mutateOnNextReplaceID == id {
            mutateOnNextReplaceID = nil
            note.updatedAt = note.updatedAt.addingTimeInterval(1)
            notes[id] = note
        }
        if let expectedUpdatedAt, note.updatedAt != expectedUpdatedAt {
            throw NoteRepositoryError.conflict
        }

        let cleanedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedTitle = NoteTextUtilities.derivedTitle(from: title, body: cleanedBody)
        let now = Date()
        note.title = cleanedTitle
        note.body = cleanedBody
        note.updatedAt = now
        note.entries.append(
            NoteEntry(
                id: UUID(),
                createdAt: now,
                kind: .replaceBody,
                source: source,
                text: cleanedBody
            )
        )
        notes[id] = note
        return note
    }

    func deleteOnNextReplace(id: UUID) {
        deleteOnNextReplaceID = id
    }

    func mutateOnNextReplace(id: UUID) {
        mutateOnNextReplaceID = id
    }

    func deleteNote(id: UUID) async throws {
        notes.removeValue(forKey: id)
    }

    func resolveNoteReference(_ reference: String) async throws -> Note? {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return filteredNotes(matching: nil).first
        }
        if let id = UUID(uuidString: trimmed), let note = notes[id] {
            return note
        }

        return filteredNotes(matching: trimmed).first
    }

    func snippets(matching query: String, limit: Int) async throws -> [NoteSnippet] {
        guard limit > 0 else {
            return []
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return filteredNotes(matching: trimmed.isEmpty ? nil : trimmed)
            .map { note in
                NoteSnippet(
                    noteID: note.id,
                    title: note.displayTitle,
                    excerpt: NoteTextUtilities.excerpt(for: note.body, matching: trimmed),
                    updatedAt: note.updatedAt,
                    score: NoteSearchRanking.score(
                        title: note.displayTitle,
                        body: note.body,
                        updatedAt: note.updatedAt,
                        query: trimmed
                    )
                )
            }
            .prefix(limit)
            .map { $0 }
    }

    private func filteredNotes(matching query: String?) -> [Note] {
        let allNotes = notes.values

        guard let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return allNotes.sorted(by: noteSortPrecedes)
        }

        return allNotes
            .map { note in
                (
                    note,
                    NoteSearchRanking.score(
                        title: note.displayTitle,
                        body: note.body,
                        updatedAt: note.updatedAt,
                        query: query
                    )
                )
            }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 > rhs.1
                }
                return noteSortPrecedes(lhs.0, rhs.0)
            }
            .map(\.0)
    }

    private func noteSortPrecedes(_ lhs: Note, _ rhs: Note) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString > rhs.id.uuidString
    }

    private func makeSummary(_ note: Note) -> NoteSummary {
        NoteSummary(
            id: note.id,
            title: note.displayTitle,
            previewText: NoteTextUtilities.preview(for: note.body),
            updatedAt: note.updatedAt
        )
    }
}

private final class MockSpeechTranscriptionService: SpeechTranscriptionService, @unchecked Sendable {
    private let result: String

    init(result: String) {
        self.result = result
    }

    func transcribeFile(at url: URL, locale: Locale) async throws -> String {
        result
    }
}

private final class MockNoteCaptureIntelligenceService: NoteCaptureIntelligenceService, @unchecked Sendable {
    let capabilityState: AssistantCapabilityState
    private let typedResult: NoteCaptureRefinement
    private let transcriptResult: NoteCaptureRefinement

    init(
        capabilityState: AssistantCapabilityState = .available,
        typedResult: NoteCaptureRefinement,
        transcriptResult: NoteCaptureRefinement
    ) {
        self.capabilityState = capabilityState
        self.typedResult = typedResult
        self.transcriptResult = transcriptResult
    }

    func refineTypedNote(title: String, body: String, locale: Locale) async throws -> NoteCaptureRefinement {
        if case let .unavailable(reason) = capabilityState {
            throw CaptureIntelligenceError.unavailable(reason)
        }
        return typedResult
    }

    func refineTranscript(title: String, transcript: String, locale: Locale) async throws -> NoteCaptureRefinement {
        if case let .unavailable(reason) = capabilityState {
            throw CaptureIntelligenceError.unavailable(reason)
        }
        return transcriptResult
    }
}

private final class MockVoiceCaptureInterpretationService: VoiceCaptureInterpretationService, @unchecked Sendable {
    let capabilityState: AssistantCapabilityState
    private let result: VoiceCaptureInterpretation

    init(
        capabilityState: AssistantCapabilityState = .available,
        result: VoiceCaptureInterpretation
    ) {
        self.capabilityState = capabilityState
        self.result = result
    }

    func interpret(transcript: String, locale: Locale) async throws -> VoiceCaptureInterpretation {
        if case let .unavailable(reason) = capabilityState {
            throw VoiceCaptureInterpretationError.unavailable(reason)
        }
        return result
    }
}

@MainActor
private final class MockNotesAssistantService: NotesAssistantService {
    let capabilityState: AssistantCapabilityState
    private let response: NotesAssistantResponse

    init(capabilityState: AssistantCapabilityState, response: NotesAssistantResponse) {
        self.capabilityState = capabilityState
        self.response = response
    }

    func prewarm() {}

    func resetConversation() {}

    func process(_ input: String) async throws -> NotesAssistantResponse {
        if case let .unavailable(reason) = capabilityState {
            throw NotesAssistantError.unavailable(reason)
        }
        return response
    }
}

@MainActor
private func makeSourceAudioFile() throws -> URL {
    let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    let sourceURL = rootURL.appendingPathComponent("source.m4a")
    try Data("placeholder audio".utf8).write(to: sourceURL)
    return sourceURL
}
