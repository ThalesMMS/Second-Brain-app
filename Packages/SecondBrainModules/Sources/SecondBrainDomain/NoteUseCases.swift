import Foundation

public struct CreateNoteUseCase: Sendable {
    package let repository: any NoteRepository

    public init(repository: any NoteRepository) {
        self.repository = repository
    }

    /// Creates a new note and records it as a creation entry.
    /// - Parameters:
    ///   - title: The note's title.
    ///   - body: The note's body content.
    ///   - source: The origin of the mutation.
    /// - Returns: The newly created `Note`.
    public func execute(title: String, body: String, source: NoteMutationSource) async throws -> Note {
        try await repository.createNote(title: title, body: body, source: source, initialEntryKind: .creation)
    }
}

public struct ProcessVoiceCaptureUseCase: Sendable {
    package let repository: any NoteRepository
    package let transcriptionService: any SpeechTranscriptionService
    package let captureIntelligence: any NoteCaptureIntelligenceService
    package let interpretationService: any VoiceCaptureInterpretationService
    package let assistant: any NotesAssistantService

    public init(
        repository: any NoteRepository,
        transcriptionService: any SpeechTranscriptionService,
        captureIntelligence: any NoteCaptureIntelligenceService,
        interpretationService: any VoiceCaptureInterpretationService,
        assistant: any NotesAssistantService
    ) {
        self.repository = repository
        self.transcriptionService = transcriptionService
        self.captureIntelligence = captureIntelligence
        self.interpretationService = interpretationService
        self.assistant = assistant
    }

    /// Processes a voice capture by transcribing audio, interpreting the transcript, and either creating a note or returning an assistant response.
    ///
    /// If voice interpretation or assistant processing is unavailable, the cleaned transcript is preserved in
    /// an assistant response instead of being dropped.
    /// - Parameters:
    ///   - title: A suggested title for the created note.
    ///   - audioURL: The URL of the captured audio file to transcribe.
    ///   - locale: The locale to use for transcription and interpretation.
    ///   - source: The source metadata to associate with a created note.
    /// - Returns: A `VoiceCaptureResult` containing either the created note or an assistant response with the preserved transcript.
    /// - Throws: Propagates errors from the transcription service, interpretation service (except `VoiceCaptureInterpretationError.unavailable`, which yields an assistant response), note creation, and assistant processing (except `NotesAssistantError.unavailable`, which yields an assistant response).
    public func execute(
        title: String,
        audioURL: URL,
        locale: Locale,
        source: NoteMutationSource
    ) async throws -> VoiceCaptureResult {
        let transcript = try await transcriptionService.transcribeFile(at: audioURL, locale: locale)
        let cleanedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let interpretation: VoiceCaptureInterpretation
        do {
            interpretation = try await interpretationService.interpret(
                transcript: cleanedTranscript,
                locale: locale
            )
        } catch let error as VoiceCaptureInterpretationError {
            switch error {
            case .unavailable:
                return .assistantResponse(
                    makeUnavailableAssistantResponse(reason: error.localizedDescription),
                    transcript: cleanedTranscript
                )
            }
        }

        switch interpretation.intent {
        case .newNote:
            let note = try await createNoteFromTranscript(
                title: title,
                transcript: interpretation.normalizedText.isEmpty ? cleanedTranscript : interpretation.normalizedText,
                locale: locale,
                source: source
            )
            return .createdNote(note)
        case .assistantCommand:
            do {
                let response = try await assistant.process(interpretation.normalizedText)
                return .assistantResponse(response, transcript: cleanedTranscript)
            } catch let error as NotesAssistantError {
                switch error {
                case .unavailable:
                    return .assistantResponse(
                        makeUnavailableAssistantResponse(reason: error.localizedDescription),
                        transcript: cleanedTranscript
                    )
                }
            }
        }
    }

    /// Creates a `Note` from a voice transcript, refining the title and body when capture intelligence is available.
    ///
    /// If refinement is unavailable, the raw `title` and `transcript` are used. When both refined title and body
    /// are empty, the title falls back to `SecondBrainSettings.untitledNoteTitle`.
    /// - Parameters:
    ///   - title: The initial title candidate provided for refinement.
    ///   - transcript: The raw transcribed text to refine and store.
    ///   - locale: The locale to use for refinement.
    ///   - source: The source of the note mutation.
    /// - Returns: The created `Note`.
    private func createNoteFromTranscript(
        title: String,
        transcript: String,
        locale: Locale,
        source: NoteMutationSource
    ) async throws -> Note {
        let refinement: NoteCaptureRefinement

        do {
            refinement = try await captureIntelligence.refineTranscript(
                title: title,
                transcript: transcript,
                locale: locale
            )
        } catch let error as CaptureIntelligenceError {
            switch error {
            case .unavailable:
                refinement = NoteCaptureRefinement(title: title, body: transcript)
            }
        }

        let cleanedTitle = refinement.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedBody = refinement.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTitle = cleanedTitle.isEmpty && cleanedBody.isEmpty
            ? SecondBrainSettings.untitledNoteTitle
            : cleanedTitle

        return try await repository.createNote(
            title: effectiveTitle,
            body: cleanedBody,
            source: source,
            initialEntryKind: cleanedBody.isEmpty ? .creation : .transcription
        )
    }

    /// Creates an assistant response that explains voice commands are unavailable while preserving the transcript for later use.
    /// - Parameter reason: A human-readable reason for unavailability to include in the response; trimmed before use.
    /// - Returns: A `NotesAssistantResponse` whose `text` states the assistant is unavailable and that the transcript was preserved in the draft, with `referencedNoteIDs` empty and `interaction` set to `.none`.
    private func makeUnavailableAssistantResponse(reason: String) -> NotesAssistantResponse {
        let message = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedReason = message.isEmpty ? "Voice commands are unavailable right now." : message
        return NotesAssistantResponse(
            text: "\(resolvedReason) I kept the transcript in the draft so you can save it as a note or use Ask Notes later.",
            referencedNoteIDs: [],
            interaction: .none
        )
    }
}

public struct AppendToNoteUseCase: Sendable {
    package let repository: any NoteRepository

    public init(repository: any NoteRepository) {
        self.repository = repository
    }

    /// Appends text to the note identified by `noteID`.
    /// - Parameters:
    ///   - noteID: The identifier of the note to append to.
    ///   - text: The text to append to the note.
    ///   - source: The origin of the mutation.
    /// - Returns: The updated `Note` after the text has been appended.
    public func execute(noteID: UUID, text: String, source: NoteMutationSource) async throws -> Note {
        try await repository.appendText(text, to: noteID, source: source)
    }

    /// Appends text to a note resolved from a free-form reference.
    ///
    /// This path is intended for assistant and voice-command flows; Siri/App Intents should pass a concrete note identifier instead.
    /// - Parameters:
    ///   - reference: A free-form or fuzzy reference string used to resolve the target note.
    ///   - text: The text to append to the note.
    ///   - source: The origin of the mutation.
    /// - Returns: The updated `Note` after the text has been appended.
    /// - Throws: `NoteRepositoryError.notFound` if no note could be resolved from `reference`. Repository errors encountered while resolving or appending are propagated.
    public func execute(reference: String, text: String, source: NoteMutationSource) async throws -> Note {
        guard let note = try await repository.resolveNoteReference(reference) else {
            throw NoteRepositoryError.notFound
        }
        return try await repository.appendText(text, to: note.id, source: source)
    }
}

public struct SaveNoteUseCase: Sendable {
    package let repository: any NoteRepository

    public init(repository: any NoteRepository) {
        self.repository = repository
    }

    /// Replaces an existing note's title and body and returns the updated note.
    /// - Parameters:
    ///   - noteID: The identifier of the note to replace.
    ///   - title: The new title for the note.
    ///   - body: The new body content for the note.
    ///   - lastSeenUpdatedAt: The note `updatedAt` value from the editor snapshot being saved.
    ///   - source: The source of the mutation.
    /// - Returns: The updated `Note`.
    public func execute(
        noteID: UUID,
        title: String,
        body: String,
        lastSeenUpdatedAt: Date,
        source: NoteMutationSource
    ) async throws -> Note {
        return try await repository.replaceNote(
            id: noteID,
            title: title,
            body: body,
            source: source,
            expectedUpdatedAt: lastSeenUpdatedAt
        )
    }
}

package struct EditExistingNoteUseCase: Sendable {
    package enum Result {
        case applied(Note, message: String)
        case pending(PendingNoteEdit, message: String)
        case clarification(String)
        case noChange(String)
        case cancelled(String)
    }

    let repository: any NoteRepository

    package init(repository: any NoteRepository) {
        self.repository = repository
    }

    /// Evaluates a proposed edit against an existing note and returns the resulting decision.
    /// - Parameters:
    ///   - proposal: The proposed edits and metadata for the target note.
    ///   - source: The origin of the mutation request (e.g., voice, assistant, user).
    /// - Returns: A `Result` describing whether the edit was applied, queued as a pending edit, requires clarification, resulted in no change, or was cancelled.
    package func execute(proposal: NoteEditProposal, source: NoteMutationSource) async throws -> Result {
        guard let note = try await repository.loadNote(id: proposal.noteID) else {
            return .clarification("That note could not be found anymore.")
        }

        return try await evaluate(
            proposal: proposal,
            against: note,
            source: source,
            allowPending: true
        )
    }

    /// Resolves a pending note edit by applying or cancelling it after validating concurrency and changes.
    /// - Parameters:
    ///   - pending: The pending edit to resolve.
    ///   - decision: The user's decision to confirm or cancel the pending edit.
    ///   - source: The source to record for the mutation if the edit is applied.
    /// - Returns: A `Result` describing the outcome:
    ///   - `.cancelled(...)` when the decision is `.cancel`.
    ///   - `.clarification(...)` when the target note cannot be found or changed since the proposal.
    ///   - `.noChange(...)` when the proposed edit would not change the note.
    ///   - `.applied(updatedNote, message: ...)` when the edit is successfully applied.
    /// - Throws: Errors propagated from repository operations performed while loading or replacing the note.
    package func resolve(
        pending: PendingNoteEdit,
        decision: PendingNoteEditDecision,
        source: NoteMutationSource
    ) async throws -> Result {
        switch decision {
        case .cancel:
            return .cancelled("Cancelled the pending edit.")
        case .confirm:
            break
        }

        guard let note = try await repository.loadNote(id: pending.noteID) else {
            return .clarification("That note could not be found anymore.")
        }

        guard note.updatedAt == pending.baseUpdatedAt else {
            return .clarification("That note changed since the proposed edit. Please repeat your request.")
        }

        let normalizedCurrentBody = Self.normalizedLineEndings(note.body)
        let normalizedUpdatedBody = Self.normalizedLineEndings(pending.proposal.updatedBody)
        let resolvedUpdatedTitle = NoteTextUtilities.derivedTitle(
            from: pending.proposal.updatedTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            body: normalizedUpdatedBody.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        guard resolvedUpdatedTitle != note.displayTitle || normalizedUpdatedBody != normalizedCurrentBody else {
            return .noChange("That edit would not change note \(note.displayTitle).")
        }

        do {
            let updated = try await repository.replaceNote(
                id: note.id,
                title: pending.proposal.updatedTitle,
                body: pending.proposal.updatedBody,
                source: source,
                expectedUpdatedAt: pending.baseUpdatedAt
            )
            return .applied(updated, message: "Updated note \(updated.displayTitle).")
        } catch NoteRepositoryError.conflict, NoteRepositoryError.notFound {
            return .clarification("That note changed since the proposed edit. Please repeat your request.")
        }
    }

    /// Decide whether a proposed edit to an existing note should be applied, marked pending, request clarification, or reported as no change.
    /// 
    /// Evaluates title and body changes according to the proposal's scope (`title`, `excerpt`, or `wholeBody`) and repository state, then either performs an immediate replacement or produces a `Result` indicating the next action.
    /// - Parameters:
    ///   - proposal: The proposed edit, including updated title/body, scope, and any excerpt-targeting information.
    ///   - note: The current note to evaluate the proposal against.
    ///   - source: The mutation source to record if an immediate update is applied.
    ///   - allowPending: If `true`, the function may return a `.pending` result when the edit cannot be safely applied immediately; if `false`, such situations yield a clarification result.
    /// - Returns: A `Result` describing the outcome:
    ///   - `.applied(Note, message: String)` when the edit was applied and the updated note is returned with a confirmation message.
    ///   - `.pending(PendingNoteEdit, message: String)` when the edit is recorded as a pending change along with a user-facing prompt.
    ///   - `.clarification(String)` when more information is required from the user.
    ///   - `.noChange(String)` when the proposed edit would not alter the note.
    ///   - `.cancelled(String)` is not produced by this function but may appear elsewhere in the flow.
    private func evaluate(
        proposal: NoteEditProposal,
        against note: Note,
        source: NoteMutationSource,
        allowPending: Bool
    ) async throws -> Result {
        let normalizedCurrentBody = Self.normalizedLineEndings(note.body)
        let normalizedUpdatedBody = Self.normalizedLineEndings(proposal.updatedBody)
        let cleanedUpdatedBody = normalizedUpdatedBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedUpdatedTitle = proposal.updatedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedUpdatedTitle = NoteTextUtilities.derivedTitle(
            from: cleanedUpdatedTitle,
            body: cleanedUpdatedBody
        )
        let titleChanged = resolvedUpdatedTitle != note.displayTitle
        let bodyChanged = normalizedUpdatedBody != normalizedCurrentBody

        guard titleChanged || bodyChanged else {
            return .noChange("That edit would not change note \(note.displayTitle).")
        }

        switch proposal.scope {
        case .title:
            if bodyChanged {
                return makePendingResult(proposal: proposal, note: note, allowPending: allowPending)
            }

            return try await applyProposal(
                proposal,
                to: note,
                source: source
            )
        case .excerpt:
            guard !titleChanged else {
                return makePendingResult(proposal: proposal, note: note, allowPending: allowPending)
            }

            guard bodyChanged else {
                return .noChange("That edit would not change note \(note.displayTitle).")
            }

            let targetExcerpt = Self.normalizedLineEndings(
                proposal.targetExcerpt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
            guard !targetExcerpt.isEmpty else {
                return .clarification(
                    proposal.clarificationQuestion
                    ?? "I need the exact text to replace in note \(note.displayTitle)."
                )
            }

            let matches = Self.matchRanges(of: targetExcerpt, in: normalizedCurrentBody)
            if matches.isEmpty {
                return .clarification(
                    proposal.clarificationQuestion
                    ?? "I could not find that exact text in note \(note.displayTitle). Please point to the line or phrase to change."
                )
            }

            guard matches.count == 1, let match = matches.first else {
                return .clarification(
                    proposal.clarificationQuestion
                    ?? "I found multiple matches for that text in note \(note.displayTitle). Please be more specific."
                )
            }

            let prefix = String(normalizedCurrentBody[..<match.lowerBound])
            let suffix = String(normalizedCurrentBody[match.upperBound...])
            let anchoredReplacement = normalizedUpdatedBody.hasPrefix(prefix)
                && normalizedUpdatedBody.hasSuffix(suffix)
                && normalizedUpdatedBody.count >= prefix.count + suffix.count

            guard anchoredReplacement else {
                return makePendingResult(proposal: proposal, note: note, allowPending: allowPending)
            }

            return try await applyProposal(
                proposal,
                to: note,
                source: source
            )
        case .wholeBody:
            return makePendingResult(proposal: proposal, note: note, allowPending: allowPending)
        }
    }

    private func makePendingResult(
        proposal: NoteEditProposal,
        note: Note,
        allowPending: Bool
    ) -> Result {
        guard allowPending else {
            return .clarification("That note changed since the proposed edit. Please repeat your request.")
        }

        let prompt = """
        Proposed edit for note \(note.displayTitle): \(proposal.changeSummary)

        Reply \"confirm\" to apply it or \"cancel\" to discard it.
        """
        return .pending(
            PendingNoteEdit(noteID: note.id, baseUpdatedAt: note.updatedAt, proposal: proposal),
            message: prompt
        )
    }

    private func applyProposal(
        _ proposal: NoteEditProposal,
        to note: Note,
        source: NoteMutationSource
    ) async throws -> Result {
        do {
            let updated = try await repository.replaceNote(
                id: note.id,
                title: proposal.updatedTitle,
                body: proposal.updatedBody,
                source: source,
                expectedUpdatedAt: note.updatedAt
            )
            return .applied(updated, message: "Updated note \(updated.displayTitle).")
        } catch NoteRepositoryError.conflict, NoteRepositoryError.notFound {
            return .clarification("That note changed since the proposed edit. Please repeat your request.")
        }
    }

    private static func normalizedLineEndings(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// Finds all non-overlapping occurrences of a substring within a string and returns their ranges.
    /// - Parameters:
    ///   - needle: The substring to search for. If empty, no matches are returned.
    ///   - haystack: The string to search within.
    /// - Returns: An array of `Range<String.Index>` values, one for each non-overlapping match of `needle` in `haystack`; returns an empty array if there are no matches.
    private static func matchRanges(of needle: String, in haystack: String) -> [Range<String.Index>] {
        guard !needle.isEmpty else {
            return []
        }

        var matches: [Range<String.Index>] = []
        var searchStart = haystack.startIndex

        while searchStart < haystack.endIndex,
              let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            matches.append(range)
            searchStart = range.upperBound
        }

        return matches
    }
}

public struct DeleteNoteUseCase: Sendable {
    package let repository: any NoteRepository

    public init(repository: any NoteRepository) {
        self.repository = repository
    }

    /// Deletes the note with the given identifier.
    /// - Parameter noteID: The UUID of the note to delete.
    public func execute(noteID: UUID) async throws {
        try await repository.deleteNote(id: noteID)
    }
}

public struct ListNotesUseCase: Sendable {
    package let repository: any NoteRepository

    public init(repository: any NoteRepository) {
        self.repository = repository
    }

    /// Lists note summaries, optionally filtered by a search query.
    /// - Parameters:
    ///   - query: An optional search string; when `nil`, all summaries are returned.
    /// - Returns: An array of `NoteSummary` objects that match the provided query (or all summaries if `query` is `nil`).
    public func execute(matching query: String?) async throws -> [NoteSummary] {
        try await repository.listNotes(matching: query)
    }
}

public struct LoadNoteUseCase: Sendable {
    package let repository: any NoteRepository

    public init(repository: any NoteRepository) {
        self.repository = repository
    }

    /// Loads the note with the specified identifier.
    /// - Returns: The note with the given `id`, or `nil` if no note exists with that identifier.
    /// - Throws: Any error thrown by the repository while loading the note.
    public func execute(id: UUID) async throws -> Note? {
        try await repository.loadNote(id: id)
    }
}

package struct SearchNotesUseCase: Sendable {
    let repository: any NoteRepository

    package init(repository: any NoteRepository) {
        self.repository = repository
    }

    /// Searches for note snippets that match the given query.
    /// - Parameters:
    ///   - query: The search query to match against note contents.
    ///   - limit: Optional maximum number of snippets to return; when `nil`, uses `SecondBrainSettings.assistantContextLimit`.
    /// - Returns: An array of `NoteSnippet` objects matching the query, up to the specified limit.
    package func execute(query: String, limit: Int? = nil) async throws -> [NoteSnippet] {
        try await repository.snippets(
            matching: query,
            limit: limit ?? SecondBrainSettings.assistantContextLimit
        )
    }
}

public struct AskNotesUseCase: Sendable {
    package let assistant: any NotesAssistantService

    public init(assistant: any NotesAssistantService) {
        self.assistant = assistant
    }

    /// Sends an input string to the Notes assistant for processing.
    /// - Parameters:
    ///   - input: The user-provided assistant input or query text.
    /// - Returns: The assistant's response as a `NotesAssistantResponse`.
    public func execute(_ input: String) async throws -> NotesAssistantResponse {
        try await assistant.process(input)
    }
}
