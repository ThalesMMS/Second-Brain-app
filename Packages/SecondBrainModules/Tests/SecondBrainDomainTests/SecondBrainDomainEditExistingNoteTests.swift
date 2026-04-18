import Foundation
import Testing
@testable import SecondBrainDomain

@MainActor
struct SecondBrainDomainEditExistingNoteTests {
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

}
