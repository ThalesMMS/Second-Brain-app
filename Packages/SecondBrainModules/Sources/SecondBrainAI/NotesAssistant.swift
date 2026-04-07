import Foundation
import SecondBrainDomain
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

@MainActor
package final class DeterministicNotesAssistant: NotesAssistantService {
    private let repository: any NoteRepository

    package init(repository: any NoteRepository) {
        self.repository = repository
    }

    package var capabilityState: AssistantCapabilityState {
        .available
    }

    package var status: NotesAssistantStatus? {
        .reducedFunctionality(
            reason: "Apple Intelligence is unavailable on this device. Falling back to deterministic retrieval."
        )
    }

    /// Prewarms the service for upcoming use.
    ///
    /// This implementation is a no-op.
    package func prewarm() {}

    /// Clears any conversation-specific transient state maintained by the instance.
    ///
    /// This implementation has no conversation state to reset.
    package func resetConversation() {}

    /// Searches notes for the user's query and returns a formatted assistant response.
    /// - Parameter input: The user's query or prompt used to search note snippets.
    /// - Returns: A `NotesAssistantResponse` whose `text` is either an apology when no matches are found or a bulleted list of `title: excerpt` lines when matches exist; `referencedNoteIDs` contains the IDs of the returned snippets (empty if no matches).
    package func process(_ input: String) async throws -> NotesAssistantResponse {
        let snippets = try await repository.snippets(matching: input, limit: SecondBrainSettings.assistantContextLimit)
        guard !snippets.isEmpty else {
            return NotesAssistantResponse(
                text: "I could not find any notes related to that request.",
                referencedNoteIDs: []
            )
        }

        let lines = snippets.map { snippet in
            "• \(snippet.title): \(snippet.excerpt)"
        }

        return NotesAssistantResponse(
            text: "I found these relevant notes:\n\n\(lines.joined(separator: "\n"))",
            referencedNoteIDs: snippets.referencedNoteIDs
        )
    }
}

package final class UnavailableNoteCaptureIntelligenceService: NoteCaptureIntelligenceService, @unchecked Sendable {
    private let reason: String

    package init(reason: String) {
        self.reason = reason
    }

    package var capabilityState: AssistantCapabilityState {
        .unavailable(reason: reason)
    }

    /// Refines a typed note's title and body for the specified locale.
    /// - Returns: A `NoteCaptureRefinement` containing the refined `title` and `body`.
    /// - Throws: `CaptureIntelligenceError.unavailable(reason)` when capture intelligence is unavailable.
    package func refineTypedNote(title: String, body: String, locale: Locale) async throws -> NoteCaptureRefinement {
        throw CaptureIntelligenceError.unavailable(reason)
    }

    /// Produces a refined note title and body from a raw transcript, using the provided title as a fallback.
    /// - Parameters:
    ///   - title: A fallback title to use if the refinement does not provide one.
    ///   - transcript: The raw transcribed text to be cleaned and converted into note content.
    ///   - locale: The locale to use for language-specific normalization and formatting.
    /// - Returns: A `NoteCaptureRefinement` containing the resolved `title` and `body`.
    /// - Throws: `CaptureIntelligenceError.unavailable` when on-device capture intelligence is unavailable; the error carries a human-readable `reason`.
    package func refineTranscript(title: String, transcript: String, locale: Locale) async throws -> NoteCaptureRefinement {
        throw CaptureIntelligenceError.unavailable(reason)
    }
}

package final class UnavailableVoiceCaptureInterpretationService: VoiceCaptureInterpretationService, @unchecked Sendable {
    private let reason: String

    package init(reason: String) {
        self.reason = reason
    }

    package var capabilityState: AssistantCapabilityState {
        .unavailable(reason: reason)
    }

    /// Always throws because voice capture interpretation is unavailable in this implementation.
    /// - Parameters:
    ///   - transcript: The raw transcript text to interpret.
    ///   - locale: The locale to use for interpretation.
    /// - Throws: `VoiceCaptureInterpretationError.unavailable(reason)` with the service's stored unavailability reason.
    package func interpret(transcript: String, locale: Locale) async throws -> VoiceCaptureInterpretation {
        throw VoiceCaptureInterpretationError.unavailable(reason)
    }
}

#if os(iOS) && canImport(FoundationModels)
import FoundationModels

/// Maps a SystemLanguageModel's availability to an AssistantCapabilityState.
/// - Returns: `.available` when the model's availability is `.available`; otherwise `.unavailable` with a human-readable reason describing why the on-device model cannot be used.
@available(iOS 26.0, *)
private func appleIntelligenceCapabilityState(for model: SystemLanguageModel) -> AssistantCapabilityState {
    switch model.availability {
    case .available:
        return .available
    case let .unavailable(reason):
        let message: String
        switch reason {
        case .deviceNotEligible:
            message = "Apple Intelligence is unavailable on this device."
        case .appleIntelligenceNotEnabled:
            message = "Apple Intelligence is turned off on this device."
        case .modelNotReady:
            message = "Apple Intelligence is still preparing its on-device model."
        @unknown default:
            message = "The on-device model is unavailable."
        }
        return .unavailable(reason: message)
    @unknown default:
        return .unavailable(reason: "The on-device model is unavailable.")
    }
}

@available(iOS 26.0, *)
private func appleIntelligenceReducedFunctionalityStatus(
    for model: SystemLanguageModel
) -> NotesAssistantStatus? {
    switch appleIntelligenceCapabilityState(for: model) {
    case .available:
        return nil
    case let .unavailable(reason):
        return .reducedFunctionality(reason: "\(reason) Falling back to deterministic retrieval.")
    }
}

@available(iOS 26.0, *)
@Generable
struct NoteCaptureRefinementPayload {
    @Guide(description: "A concise note title. Keep explicit titles when they are already good, and avoid adding facts.")
    let title: String

    @Guide(description: "The complete note body after cleanup. Preserve meaning, details, numbers, lists, and dates.")
    let body: String
}

@available(iOS 26.0, *)
@Generable
struct VoiceCaptureInterpretationPayload {
    @Guide(description: "Either newNote or assistantCommand.")
    let intent: String

    @Guide(description: "The cleaned note content or cleaned assistant command in the same language as the transcript.")
    let normalizedText: String
}

@available(iOS 26.0, *)
@Generable
struct NoteEditProposalPayload {
    @Guide(description: "One of: title, excerpt, wholeBody.")
    let scope: String

    @Guide(description: "The full note title after the requested edit. Keep it unchanged unless the user asked to rename the note.")
    let updatedTitle: String

    @Guide(description: "The full note body after the requested edit.")
    let updatedBody: String

    @Guide(description: "For excerpt edits, copy the exact text from the current body that should be replaced. Otherwise leave this empty.")
    let targetExcerpt: String?

    @Guide(description: "A short summary of the proposed edit.")
    let changeSummary: String

    @Guide(description: "A clarification question when the request or the exact target text is ambiguous. Otherwise leave this empty.")
    let clarificationQuestion: String?
}

@available(iOS 26.0, *)
package final class AppleIntelligenceVoiceCaptureInterpretationService: VoiceCaptureInterpretationService, @unchecked Sendable {
    private let model = SystemLanguageModel(
        useCase: .general,
        guardrails: .permissiveContentTransformations
    )

    package init() {}

    package var capabilityState: AssistantCapabilityState {
        appleIntelligenceCapabilityState(for: model)
    }

    /// Classifies a spoken transcript into an intent and a cleaned, normalized text.
    /// - Parameters:
    ///   - transcript: The raw captured speech to classify.
    ///   - locale: The preferred locale to guide language selection and normalization.
    /// - Returns: A `VoiceCaptureInterpretation` containing the resolved intent and the cleaned, normalized text.
    /// - Throws: `VoiceCaptureInterpretationError.unavailable` if the voice-capture interpretation capability is not available.
    package func interpret(transcript: String, locale: Locale) async throws -> VoiceCaptureInterpretation {
        try ensureAvailable()

        let response = try await makeSession().respond(
            generating: VoiceCaptureInterpretationPayload.self,
            options: GenerationOptions(sampling: .greedy)
        ) {
            "You classify raw voice capture before the app decides what to do with it."
            "Always answer in the same language as the transcript. Prefer locale \(locale.identifier) when ambiguous."
            "Use intent newNote when the user is dictating note content to store."
            "Use intent assistantCommand when the user is asking the app to search, read, edit, append, replace, rename, summarize, or otherwise act on existing notes."
            "normalizedText must preserve the speaker's meaning and must not invent facts."
            "If intent is newNote, normalizedText should be cleaned note content."
            "If intent is assistantCommand, normalizedText should be the cleaned command."
            "Transcript:"
            transcript
        }

        return normalize(response.content, transcript: transcript)
    }

    /// Ensures the voice capture interpretation service is available, otherwise throws an unavailable error.
    /// - Throws: `VoiceCaptureInterpretationError.unavailable` with the service's unavailability reason, or with the message `"Voice command routing is unavailable."` when no specific reason is provided.
    private func ensureAvailable() throws {
        guard case .available = capabilityState else {
            if case let .unavailable(reason) = capabilityState {
                throw VoiceCaptureInterpretationError.unavailable(reason)
            }
            throw VoiceCaptureInterpretationError.unavailable("Voice command routing is unavailable.")
        }
    }

    /// Creates a LanguageModelSession configured to route spoken input into either note creation or assistant commands.
    /// 
    /// The session is primed with routing instructions and is conservative about interpreting inputs as `assistantCommand`.
    /// - Returns: A `LanguageModelSession` configured for routing spoken input between note creation and note-command intents.
    private func makeSession() -> LanguageModelSession {
        LanguageModelSession(model: model) {
            "You route spoken input into either note creation or note commands."
            "Be conservative about assistantCommand."
        }
    }

    /// Normalize a model classification payload into a concrete `VoiceCaptureInterpretation`.
    /// - Parameters:
    ///   - payload: The LLM-derived `VoiceCaptureInterpretationPayload` containing `intent` and `normalizedText`.
    ///   - transcript: The original transcript to use as a fallback if `payload.normalizedText` is empty after trimming.
    /// - Returns: A `VoiceCaptureInterpretation` whose `intent` is parsed from `payload.intent` (defaults to `.newNote` on unknown values) and whose `normalizedText` is the trimmed `payload.normalizedText` or, if that is empty, the trimmed `transcript`.
    private func normalize(
        _ payload: VoiceCaptureInterpretationPayload,
        transcript: String
    ) -> VoiceCaptureInterpretation {
        let resolvedIntent = VoiceCaptureIntent(
            rawValue: payload.intent.trimmingCharacters(in: .whitespacesAndNewlines)
        ) ?? .newNote
        let cleanedText = payload.normalizedText.trimmingCharacters(in: .whitespacesAndNewlines)

        return VoiceCaptureInterpretation(
            intent: resolvedIntent,
            normalizedText: cleanedText.isEmpty ? transcript.trimmingCharacters(in: .whitespacesAndNewlines) : cleanedText
        )
    }
}

@available(iOS 26.0, *)
package final class AppleIntelligenceNoteCaptureIntelligenceService: NoteCaptureIntelligenceService, @unchecked Sendable {
    private let model = SystemLanguageModel(
        useCase: .general,
        guardrails: .permissiveContentTransformations
    )

    package init() {}

    package var capabilityState: AssistantCapabilityState {
        appleIntelligenceCapabilityState(for: model)
    }

    /// Refines a quick-capture note's title and body while preserving the user's meaning and language.
    /// - Parameters:
    ///   - title: The original note title; if empty, a concise title may be derived from the body.
    ///   - body: The original note body to be cleaned up (punctuation, capitalization, spelling, and dictation artifacts).
    ///   - locale: Preferred locale to use when choosing the response language if the input is ambiguous.
    /// - Returns: A `NoteCaptureRefinement` containing the refined `title` and `body`.
    /// - Throws: `CaptureIntelligenceError.unavailable` if the capture intelligence service is not available.
    package func refineTypedNote(title: String, body: String, locale: Locale) async throws -> NoteCaptureRefinement {
        try ensureAvailable()

        let response = try await makeSession().respond(
            generating: NoteCaptureRefinementPayload.self,
            options: GenerationOptions(sampling: .greedy)
        ) {
            "You refine quick-capture notes before they are saved."
            "Always answer in the same language as the user's note. Prefer locale \(locale.identifier) when the input is ambiguous."
            "Preserve the user's meaning."
            "Fix punctuation, capitalization, spelling, and dictation-style phrasing."
            "Do not invent facts, tasks, dates, names, dosages, or decisions."
            "If the title is empty, derive a concise title from the note body."
            "If the title is already good, keep it close to the original."
            "Return both title and body."
            "Title:"
            title
            "Body:"
            body
        }

        return normalize(
            response.content,
            fallbackTitle: title,
            fallbackBody: body
        )
    }

    /// Refines a raw speech transcript into a cleaned note title and body.
    /// 
    /// The assistant corrects punctuation, capitalization, and obvious transcription errors while preserving the speaker's meaning and not inventing facts. If the model returns an empty title or body, the provided `title` or `transcript` is used as a fallback. The `locale` is used to prefer the correct language and formatting when ambiguous.
    /// - Parameters:
    ///   - title: The original or candidate title to preserve or use as a fallback when the model does not produce a title.
    ///   - transcript: The raw speech transcription to be cleaned and converted into the note body.
    ///   - locale: The preferred locale to guide language selection and formatting.
    /// - Returns: A `NoteCaptureRefinement` containing the refined `title` and `body`, using the provided fallbacks when necessary.
    package func refineTranscript(title: String, transcript: String, locale: Locale) async throws -> NoteCaptureRefinement {
        try ensureAvailable()

        let response = try await makeSession().respond(
            generating: NoteCaptureRefinementPayload.self,
            options: GenerationOptions(sampling: .greedy)
        ) {
            "You refine raw speech transcriptions into readable notes before they are saved."
            "Always answer in the same language as the transcript. Prefer locale \(locale.identifier) when the input is ambiguous."
            "Preserve the speaker's meaning."
            "Fix punctuation, capitalization, and only obvious transcription mistakes that are strongly supported by the transcript itself."
            "Do not invent missing facts or rewrite ambiguous audio into something more specific than the transcript supports."
            "If the title is empty, derive a concise title from the corrected transcript."
            "If the title is already good, keep it close to the original."
            "Return both title and body."
            "Title:"
            title
            "Transcript:"
            transcript
        }

        return normalize(
            response.content,
            fallbackTitle: title,
            fallbackBody: transcript
        )
    }

    private func ensureAvailable() throws {
        guard case .available = capabilityState else {
            if case let .unavailable(reason) = capabilityState {
                throw CaptureIntelligenceError.unavailable(reason)
            }
            throw CaptureIntelligenceError.unavailable("The on-device model is unavailable.")
        }
    }

    private func makeSession() -> LanguageModelSession {
        LanguageModelSession(model: model) {
            "You prepare high-fidelity notes for permanent storage."
            "Keep the user's original meaning."
            "Improve formatting, not substance."
        }
    }

    private func normalize(
        _ payload: NoteCaptureRefinementPayload,
        fallbackTitle: String,
        fallbackBody: String
    ) -> NoteCaptureRefinement {
        let cleanedBody = payload.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBody = cleanedBody.isEmpty
            ? fallbackBody.trimmingCharacters(in: .whitespacesAndNewlines)
            : cleanedBody
        let cleanedTitle = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = cleanedTitle.isEmpty
            ? fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            : cleanedTitle

        return NoteCaptureRefinement(title: resolvedTitle, body: resolvedBody)
    }
}

@available(iOS 26.0, *)
package final class AppleIntelligenceNoteEditService: NoteEditIntelligenceService, @unchecked Sendable {
    private let model = SystemLanguageModel(
        useCase: .general,
        guardrails: .permissiveContentTransformations
    )

    package var capabilityState: AssistantCapabilityState {
        appleIntelligenceCapabilityState(for: model)
    }

    /// Generates a safe edit proposal for an existing note based on a user instruction.
    /// - Parameters:
    ///   - locale: The preferred locale to guide language and formatting of the proposal.
    /// - Returns: A `NoteEditProposal` describing the proposed scope, updated title and body, an optional verbatim target excerpt when applicable, a change summary, and an optional clarification question.
    /// - Throws: `NotesAssistantError.unavailable(reason)` when the note-edit intelligence capability is not available.
    package func proposeEdit(
        noteID: UUID,
        title: String,
        body: String,
        instruction: String,
        locale: Locale
    ) async throws -> NoteEditProposal {
        try ensureAvailable()

        let response = try await makeSession().respond(
            generating: NoteEditProposalPayload.self,
            options: GenerationOptions(sampling: .greedy)
        ) {
            "You propose safe edits to an existing note."
            "Always answer in the same language as the user. Prefer locale \(locale.identifier) when the input is ambiguous."
            "Preserve facts unless the user explicitly asks to change them."
            "Do not invent new facts, tasks, dates, names, or decisions."
            "Return the complete updated title and the complete updated body."
            "Use scope title only when only the note title changes."
            "Use scope excerpt when the request changes a localized passage and the rest of the body should stay the same."
            "Use scope wholeBody for rewrites, restructures, or edits that touch multiple places."
            "For excerpt edits, targetExcerpt must be copied verbatim from the current body, including punctuation and line breaks."
            "If you cannot identify the exact target text confidently, keep the original title and body, leave scope as excerpt, and ask a clarification question."
            "When scope is excerpt, keep all unchanged text exactly the same outside the edited passage."
            "Current title:"
            title
            "Current body:"
            body
            "User instruction:"
            instruction
        }

        return normalize(
            response.content,
            noteID: noteID,
            fallbackTitle: title,
            fallbackBody: body
        )
    }

    private func ensureAvailable() throws {
        guard case .available = capabilityState else {
            if case let .unavailable(reason) = capabilityState {
                throw NotesAssistantError.unavailable(reason)
            }
            throw NotesAssistantError.unavailable("The on-device model is unavailable.")
        }
    }

    private func makeSession() -> LanguageModelSession {
        LanguageModelSession(model: model) {
            "You transform natural-language edit requests into safe structured note edits."
            "Be conservative when the target text is ambiguous."
        }
    }

    private func normalize(
        _ payload: NoteEditProposalPayload,
        noteID: UUID,
        fallbackTitle: String,
        fallbackBody: String
    ) -> NoteEditProposal {
        let resolvedScope = NoteEditScope(rawValue: payload.scope.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .wholeBody
        let cleanedTitle = payload.updatedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedBody = payload.updatedBody.isEmpty ? fallbackBody : payload.updatedBody
        let cleanedTarget = payload.targetExcerpt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedSummary = payload.changeSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedQuestion = payload.clarificationQuestion?.trimmingCharacters(in: .whitespacesAndNewlines)

        return NoteEditProposal(
            noteID: noteID,
            scope: resolvedScope,
            updatedTitle: cleanedTitle.isEmpty ? fallbackTitle : cleanedTitle,
            updatedBody: cleanedBody,
            targetExcerpt: cleanedTarget?.isEmpty == true ? nil : cleanedTarget,
            changeSummary: cleanedSummary.isEmpty ? "Update the note." : cleanedSummary,
            clarificationQuestion: cleanedQuestion?.isEmpty == true ? nil : cleanedQuestion
        )
    }
}

@MainActor
package final class NotesToolbox {
    private let repository: any NoteRepository
    private let editIntelligence: any NoteEditIntelligenceService
    private let editUseCase: EditExistingNoteUseCase
    private var referencedNoteIDs = Set<UUID>()
    private var pendingEdit: PendingNoteEdit?

    init(
        repository: any NoteRepository,
        editIntelligence: any NoteEditIntelligenceService
    ) {
        self.repository = repository
        self.editIntelligence = editIntelligence
        self.editUseCase = EditExistingNoteUseCase(repository: repository)
    }

    /// Searches notes matching the given query and returns a formatted summary of the matching snippets.
    /// - Returns: A string containing a numbered list of matching snippets where each entry includes the note id, title, excerpt, and formatted updated date; returns `"No matching notes were found."` when there are no matches.
    func search(query: String) async throws -> String {
        let snippets = try await repository.snippets(matching: query, limit: SecondBrainSettings.assistantContextLimit)
        referencedNoteIDs.formUnion(snippets.map(\.noteID))

        guard !snippets.isEmpty else {
            return "No matching notes were found."
        }

        return snippets.enumerated().map { index, snippet in
            """
            [\(index + 1)] id: \(snippet.noteID.uuidString)
            title: \(snippet.title)
            excerpt: \(snippet.excerpt)
            updated: \(snippet.updatedAt.formatted(date: .abbreviated, time: .shortened))
            """
        }.joined(separator: "\n\n")
    }

    /// Retrieves a note matching the given reference and returns a formatted block with its id, title, and body.
    ///
    /// The resolved note ID is added to `referencedNoteIDs`.
    /// - Parameter reference: A string used to identify the note, such as a title, id, or search snippet.
    /// - Returns: A string containing the note formatted as:
    ///   id: <uuid>
    ///   title: <display title>
    ///   body:
    ///   <full body>
    ///   If no note matches the reference, returns the exact string "No note matched the provided reference."
    func read(reference: String) async throws -> String {
        guard let note = try await repository.resolveNoteReference(reference) else {
            return "No note matched the provided reference."
        }

        referencedNoteIDs.insert(note.id)
        return """
        id: \(note.id.uuidString)
        title: \(note.displayTitle)
        body:
        \(note.body)
        """
    }

    /// Creates a new note in the repository and records the created note's ID in `referencedNoteIDs`.
    /// - Parameters:
    ///   - title: The note's title.
    ///   - body: The note's body content.
    /// - Returns: A confirmation message containing the created note's display title and UUID.
    func create(title: String, body: String) async throws -> String {
        let note = try await repository.createNote(title: title, body: body, source: .assistant, initialEntryKind: .creation)
        referencedNoteIDs.insert(note.id)
        return "Created note \(note.displayTitle) with id \(note.id.uuidString)."
    }

    /// Appends text to a note identified by a human-readable reference.
    /// - Parameters:
    ///   - reference: A user-provided reference used to locate the note (for example a title, id string, or excerpt).
    ///   - content: The text to append to the note.
    /// - Returns: A confirmation message that includes the note's display title and UUID.
    func append(reference: String, content: String) async throws -> String {
        let cleanedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedContent.isEmpty else {
            return "No changes; nothing to append."
        }

        guard let note = try await repository.resolveNoteReference(reference) else {
            return "No note matched the provided reference."
        }

        let updated = try await repository.appendText(cleanedContent, to: note.id, source: .assistant)
        referencedNoteIDs.insert(updated.id)
        return "Appended content to note \(updated.displayTitle) with id \(updated.id.uuidString)."
    }

    /// Proposes and applies an edit to the specified note using the provided instruction.
    /// - Parameters:
    ///   - noteID: The note identifier as a UUID string (whitespace is trimmed before parsing).
    ///   - instruction: A user-facing instruction describing the desired edit.
    /// - Returns: A user-facing message describing the outcome (e.g., `"No note matched the provided note id."` or a success/clarification/cancellation message produced by the edit use case).
    /// - Throws: `NotesAssistantError.unavailable(reason)` if the edit intelligence capability is unavailable.
    func edit(noteID: String, instruction: String) async throws -> String {
        guard case .available = editIntelligence.capabilityState else {
            if case let .unavailable(reason) = editIntelligence.capabilityState {
                throw NotesAssistantError.unavailable(reason)
            }
            throw NotesAssistantError.unavailable("The on-device model is unavailable.")
        }

        guard let id = UUID(uuidString: noteID.trimmingCharacters(in: .whitespacesAndNewlines)),
              let note = try await repository.loadNote(id: id) else {
            return "No note matched the provided note id."
        }

        referencedNoteIDs.insert(note.id)
        pendingEdit = nil

        let proposal = try await editIntelligence.proposeEdit(
            noteID: note.id,
            title: note.displayTitle,
            body: note.body,
            instruction: instruction,
            locale: .autoupdatingCurrent
        )

        let result = try await editUseCase.execute(proposal: proposal, source: .assistant)
        return handle(result)
    }

    /// Resolves a pending note edit by confirming or cancelling it based on the provided decision string.
    /// 
    /// The input is trimmed and lowercased; valid decisions are `"confirm"` and `"cancel"`. If the decision is invalid
    /// or there is no pending edit to act on, a human-readable message explaining the situation is returned.
    /// - Parameters:
    ///   - decision: A string indicating the desired action; expected values are `"confirm"` or `"cancel"`.
    /// - Returns: A user-facing message describing the outcome (validation message, no-pending-edit message, or the result of resolving the pending edit).
    /// - Throws: Any error thrown while resolving the pending edit via the edit use case.
    func resolvePendingEdit(decision: String) async throws -> String {
        let normalizedDecision = decision.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let resolvedDecision = PendingNoteEditDecision(rawValue: normalizedDecision) else {
            return "The decision must be either confirm or cancel."
        }

        guard let pendingEdit else {
            switch resolvedDecision {
            case .confirm:
                return "There is no pending edit to confirm."
            case .cancel:
                return "There is no pending edit to cancel."
            }
        }

        referencedNoteIDs.insert(pendingEdit.noteID)
        let result = try await editUseCase.resolve(
            pending: pendingEdit,
            decision: resolvedDecision,
            source: .assistant
        )
        return handle(result)
    }

    /// Clears the assistant's conversational context by removing all referenced note IDs and discarding any pending edit.
    func resetConversation() {
        referencedNoteIDs.removeAll()
        pendingEdit = nil
    }

    /// Determines the current assistant interaction state based on whether an edit is pending.
    /// - Returns: `.none` if there is no pending edit, `.pendingEditConfirmation` if a pending edit exists.
    func currentInteractionState() -> NotesAssistantInteractionState {
        pendingEdit == nil ? .none : .pendingEditConfirmation
    }

    /// Retrieve and clear the current set of referenced note IDs.
    /// - Returns: An array of referenced note UUIDs sorted by their `uuidString`. The internal set of referenced IDs is cleared.
    func consumeReferencedNoteIDs() -> [UUID] {
        let ids = Array(referencedNoteIDs)
        referencedNoteIDs.removeAll()
        return ids.sorted { $0.uuidString < $1.uuidString }
    }

    private func handle(_ result: EditExistingNoteUseCase.Result) -> String {
        switch result {
        case let .applied(note, message):
            referencedNoteIDs.insert(note.id)
            pendingEdit = nil
            return message
        case let .pending(nextPending, message):
            referencedNoteIDs.insert(nextPending.noteID)
            pendingEdit = nextPending
            return message
        case let .clarification(message):
            pendingEdit = nil
            return message
        case let .noChange(message):
            pendingEdit = nil
            return message
        case let .cancelled(message):
            pendingEdit = nil
            return message
        }
    }
}

@available(iOS 26.0, *)
struct SearchNotesTool: Tool {
    let name = "searchNotes"
    let description = "Searches the user's notes and returns note ids, titles, and excerpts. Use this before reading or modifying an existing note."

    private let toolbox: NotesToolbox

    init(toolbox: NotesToolbox) {
        self.toolbox = toolbox
    }

    @Generable
    struct Arguments {
        let query: String
    }

    func call(arguments: Arguments) async throws -> String {
        try await toolbox.search(query: arguments.query)
    }
}

@available(iOS 26.0, *)
struct ReadNoteTool: Tool {
    let name = "readNote"
    let description = "Reads the full body of an existing note. Accepts either the note id or a short natural reference, such as the title."

    private let toolbox: NotesToolbox

    init(toolbox: NotesToolbox) {
        self.toolbox = toolbox
    }

    @Generable
    struct Arguments {
        let reference: String
    }

    func call(arguments: Arguments) async throws -> String {
        try await toolbox.read(reference: arguments.reference)
    }
}

@available(iOS 26.0, *)
struct CreateNoteTool: Tool {
    let name = "createNote"
    let description = "Creates a new note with the provided title and text body."

    private let toolbox: NotesToolbox

    init(toolbox: NotesToolbox) {
        self.toolbox = toolbox
    }

    @Generable
    struct Arguments {
        let title: String
        let body: String
    }

    func call(arguments: Arguments) async throws -> String {
        try await toolbox.create(title: arguments.title, body: arguments.body)
    }
}

@available(iOS 26.0, *)
struct AppendToNoteTool: Tool {
    let name = "appendToNote"
    let description = "Appends additional text to an existing note. Provide either the note id or a natural reference like the title."

    private let toolbox: NotesToolbox

    init(toolbox: NotesToolbox) {
        self.toolbox = toolbox
    }

    @Generable
    struct Arguments {
        let reference: String
        let content: String
    }

    func call(arguments: Arguments) async throws -> String {
        try await toolbox.append(reference: arguments.reference, content: arguments.content)
    }
}

@available(iOS 26.0, *)
struct EditNoteTool: Tool {
    let name = "editNote"
    let description = "Edits an existing note after you have already searched and read it. Requires the exact note id returned by the note tools."

    private let toolbox: NotesToolbox

    init(toolbox: NotesToolbox) {
        self.toolbox = toolbox
    }

    @Generable
    struct Arguments {
        let noteID: String
        let instruction: String
    }

    func call(arguments: Arguments) async throws -> String {
        try await toolbox.edit(noteID: arguments.noteID, instruction: arguments.instruction)
    }
}

@available(iOS 26.0, *)
struct ResolvePendingEditTool: Tool {
    let name = "resolvePendingEdit"
    let description = "Confirms or cancels the currently pending note edit. Use this when the user says confirm or cancel after reviewing a proposed edit."

    private let toolbox: NotesToolbox

    init(toolbox: NotesToolbox) {
        self.toolbox = toolbox
    }

    @Generable
    struct Arguments {
        let decision: String
    }

    func call(arguments: Arguments) async throws -> String {
        try await toolbox.resolvePendingEdit(decision: arguments.decision)
    }
}

@available(iOS 26.0, *)
@MainActor
package final class AppleIntelligenceNotesAssistant: NotesAssistantService {
    private let model = SystemLanguageModel.default
    private let toolbox: NotesToolbox
    private let fallback: DeterministicNotesAssistant
    private var session: LanguageModelSession

    package init(repository: any NoteRepository) {
        let toolbox = NotesToolbox(
            repository: repository,
            editIntelligence: AppleIntelligenceNoteEditService()
        )
        self.toolbox = toolbox
        self.fallback = DeterministicNotesAssistant(repository: repository)
        self.session = Self.makeSession(toolbox: toolbox)
    }

    package var capabilityState: AssistantCapabilityState {
        fallback.capabilityState
    }

    package var status: NotesAssistantStatus? {
        appleIntelligenceReducedFunctionalityStatus(for: model)
    }

    /// Primes the assistant's internal language-model session to reduce latency for subsequent requests.
    package func prewarm() {
        session.prewarm()
    }

    /// Resets the assistant's conversation state and rebuilds its language-model session.
    /// 
    /// Clears any conversation-specific state held by the toolbox and replaces the current
    /// LLM session with a new session configured for that toolbox.
    package func resetConversation() {
        toolbox.resetConversation()
        session = Self.makeSession(toolbox: toolbox)
    }

    /// Processes an assistant prompt, using Apple Intelligence when available and falling back to deterministic retrieval.
    /// - Parameter input: The assistant prompt text to process.
    /// - Returns: A `NotesAssistantResponse` containing the assistant's reply text, any referenced note UUIDs, and the current interaction state.
    package func process(_ input: String) async throws -> NotesAssistantResponse {
        guard case .available = model.availability else {
            return try await fallback.process(input)
        }

        let response = try await session.respond(
            to: input,
            options: GenerationOptions(sampling: .greedy)
        )

        let referencedIDs = toolbox.consumeReferencedNoteIDs()
        return NotesAssistantResponse(
            text: response.content,
            referencedNoteIDs: referencedIDs,
            interaction: toolbox.currentInteractionState()
        )
    }

    /// Creates a LanguageModelSession configured for the notes assistant, registering toolbox-backed tools and assistant instructions that require consulting tools for searches, reads, creations, appends, and edits, avoid fabricating note content, and route confirm/cancel decisions to the resolvePendingEdit tool.
    /// - Parameter toolbox: The NotesToolbox supplying tool implementations and conversational state for the session.
    /// - Returns: A LanguageModelSession preconfigured with the toolbox tools and the assistant instructions.
    private static func makeSession(toolbox: NotesToolbox) -> LanguageModelSession {
        let instructions = Instructions {
            "You are Second Brain, a local note assistant."
            "Always answer in the same language as the user."
            "If the request depends on existing notes, search first and then read the most relevant note before answering."
            "If the user asks to create or append to a note, use the provided tools instead of inventing actions."
            "If the user asks to edit an existing note, search first, then read the exact note, and only then call editNote with the exact note id returned by the tools."
            "Never use editNote with a fuzzy title reference."
            "If the target note or the target text is ambiguous, ask a clarification question and do not edit."
            "When a pending edit has already been proposed and the user says confirm or cancel, call resolvePendingEdit instead of regenerating the edit."
            "Never fabricate note contents or claim that a note exists unless a tool confirms it."
            "When you answer based on notes, cite the note titles naturally in your response."
        }

        let tools: [any Tool] = [
            SearchNotesTool(toolbox: toolbox),
            ReadNoteTool(toolbox: toolbox),
            CreateNoteTool(toolbox: toolbox),
            AppendToNoteTool(toolbox: toolbox),
            EditNoteTool(toolbox: toolbox),
            ResolvePendingEditTool(toolbox: toolbox),
        ]

        return LanguageModelSession(tools: tools, instructions: instructions)
    }
}
#endif

#if canImport(WatchConnectivity)
package enum CompanionRelayRequestKind: String {
    case assistant
    case voiceInterpretation
}

package struct CompanionRelayAssistantRequest {
    let id: UUID
    let prompt: String
}

package struct CompanionRelayInterpretationRequest {
    let id: UUID
    let transcript: String
    let localeIdentifier: String
}

package enum CompanionRelayMessageCodec {
    nonisolated private static let kindKey = "kind"
    nonisolated private static let idKey = "id"
    nonisolated private static let promptKey = "prompt"
    nonisolated private static let transcriptKey = "transcript"
    nonisolated private static let localeIdentifierKey = "localeIdentifier"
    nonisolated private static let textKey = "text"
    nonisolated private static let referencedNoteIDsKey = "referencedNoteIDs"
    nonisolated private static let interactionKey = "interaction"
    nonisolated private static let intentKey = "intent"
    nonisolated private static let normalizedTextKey = "normalizedText"
    nonisolated private static let errorKey = "error"

    /// Builds a dictionary representing an assistant relay request.
    /// - Parameters:
    ///   - id: The relay conversation identifier to include in the request.
    ///   - prompt: The assistant prompt text to send.
    /// - Returns: A dictionary containing the request `kind`, `id`, and `prompt` suitable for sending over the companion relay.
    nonisolated static func assistantRequest(id: UUID, prompt: String) -> [String: Any] {
        [
            kindKey: CompanionRelayRequestKind.assistant.rawValue,
            idKey: id.uuidString,
            promptKey: prompt
        ]
    }

    /// Encodes a voice-interpretation relay request into a dictionary for WatchConnectivity transfer.
    /// - Parameters:
    ///   - id: The relay conversation identifier to correlate request and response.
    ///   - transcript: The raw transcript text to be interpreted.
    ///   - locale: The locale whose identifier will be included to guide interpretation.
    /// - Returns: A dictionary containing the request `kind`, the `id` string, `transcript`, and `localeIdentifier`.
    nonisolated static func voiceInterpretationRequest(
        id: UUID,
        transcript: String,
        locale: Locale
    ) -> [String: Any] {
        [
            kindKey: CompanionRelayRequestKind.voiceInterpretation.rawValue,
            idKey: id.uuidString,
            transcriptKey: transcript,
            localeIdentifierKey: locale.identifier
        ]
    }

    /// Parses a dictionary into a `CompanionRelayAssistantRequest` when the dictionary represents an assistant request.
    /// - Parameter message: A dictionary decoded from a relay message; expected to contain `kind` equal to `assistant`, an `id` UUID string, and a `prompt` string.
    /// - Returns: A `CompanionRelayAssistantRequest` constructed from the `id` and `prompt` if all required fields are present and valid, `nil` otherwise.
    nonisolated static func decodeAssistantRequest(_ message: [String: Any]) -> CompanionRelayAssistantRequest? {
        guard message[kindKey] as? String == CompanionRelayRequestKind.assistant.rawValue else {
            return nil
        }
        guard let idString = message[idKey] as? String,
              let id = UUID(uuidString: idString),
              let prompt = message[promptKey] as? String else {
            return nil
        }

        return CompanionRelayAssistantRequest(id: id, prompt: prompt)
    }

    /// Decodes a dictionary into a `CompanionRelayInterpretationRequest` when it represents a voice interpretation request.
    /// - Parameters:
    ///   - message: A dictionary received over the companion relay protocol.
    /// - Returns: A `CompanionRelayInterpretationRequest` if `message` has kind `voiceInterpretation` and contains valid `id`, `transcript`, and `localeIdentifier` values; `nil` otherwise.
    nonisolated static func decodeVoiceInterpretationRequest(_ message: [String: Any]) -> CompanionRelayInterpretationRequest? {
        guard message[kindKey] as? String == CompanionRelayRequestKind.voiceInterpretation.rawValue else {
            return nil
        }
        guard let idString = message[idKey] as? String,
              let id = UUID(uuidString: idString),
              let transcript = message[transcriptKey] as? String,
              let localeIdentifier = message[localeIdentifierKey] as? String else {
            return nil
        }

        return CompanionRelayInterpretationRequest(
            id: id,
            transcript: transcript,
            localeIdentifier: localeIdentifier
        )
    }

    /// Encodes a `NotesAssistantResponse` together with a relay `UUID` into a dictionary for messaging.
    /// - Parameters:
    ///   - id: The relay identifier to include under `idKey`.
    ///   - response: The `NotesAssistantResponse` whose fields will be encoded.
    /// - Returns: A dictionary containing:
    ///   - `idKey`: the `id` as a UUID string.
    ///   - `textKey`: the assistant response text.
    ///   - `referencedNoteIDsKey`: an array of referenced note IDs as UUID strings.
    ///   - `interactionKey`: the raw string value of the response interaction state.
    nonisolated static func assistantResponse(id: UUID, response: NotesAssistantResponse) -> [String: Any] {
        [
            idKey: id.uuidString,
            textKey: response.text,
            referencedNoteIDsKey: response.referencedNoteIDs.map(\.uuidString),
            interactionKey: response.interaction.rawValue
        ]
    }

    /// Builds a dictionary representing a voice-interpretation response for the companion relay.
    /// - Parameters:
    ///   - id: The UUID for the relay message.
    ///   - interpretation: The interpreted voice intent and its normalized text.
    /// - Returns: A dictionary containing the message `id` (UUID string), `intent` (intent raw value), and `normalizedText`.
    nonisolated static func voiceInterpretationResponse(
        id: UUID,
        interpretation: VoiceCaptureInterpretation
    ) -> [String: Any] {
        [
            idKey: id.uuidString,
            intentKey: interpretation.intent.rawValue,
            normalizedTextKey: interpretation.normalizedText
        ]
    }

    /// Creates a companion-relay error payload.
    /// - Parameters:
    ///   - id: An optional UUID to include in the payload under `idKey`.
    ///   - message: The error message to include under `errorKey`.
    /// - Returns: A dictionary containing the `errorKey` mapped to `message` and, if `id` is provided, `idKey` mapped to the UUID string.
    nonisolated static func error(id: UUID?, message: String) -> [String: Any] {
        var payload: [String: Any] = [
            errorKey: message
        ]
        if let id {
            payload[idKey] = id.uuidString
        }
        return payload
    }

    /// Decodes a companion relay assistant response dictionary into a `NotesAssistantResponse`.
    /// - Parameter message: The payload dictionary received from the paired iPhone; expected keys include `text`, optional `referencedNoteIDs` (array of UUID strings), optional `interaction`, or `error`.
    /// - Returns: A `NotesAssistantResponse` with `text`, parsed `referencedNoteIDs`, and the resolved `interaction` state.
    /// - Throws: `NotesAssistantError.unavailable` if the payload contains an `error` message or if the required `text` field is missing or invalid.
    nonisolated static func decodeAssistantResponse(_ message: [String: Any]) throws -> NotesAssistantResponse {
        if let errorMessage = message[errorKey] as? String {
            throw NotesAssistantError.unavailable(errorMessage)
        }

        guard let text = message[textKey] as? String else {
            throw NotesAssistantError.unavailable("The paired iPhone returned an invalid response.")
        }

        let ids = (message[referencedNoteIDsKey] as? [String] ?? []).compactMap(UUID.init(uuidString:))
        let interaction = NotesAssistantInteractionState(
            rawValue: (message[interactionKey] as? String) ?? ""
        ) ?? .none
        return NotesAssistantResponse(text: text, referencedNoteIDs: ids, interaction: interaction)
    }

    /// Decodes a voice-interpretation response dictionary from the companion device into a `VoiceCaptureInterpretation`.
    /// - Parameters:
    ///   - message: A dictionary received from the paired iPhone containing either an `error` string or the fields `intent` and `normalizedText`.
    /// - Returns: A `VoiceCaptureInterpretation` constructed from the decoded `intent` and `normalizedText`.
    /// - Throws: `VoiceCaptureInterpretationError.unavailable` if the `message` contains an `error` string or if the required fields are missing or invalid.
    nonisolated static func decodeVoiceInterpretationResponse(
        _ message: [String: Any]
    ) throws -> VoiceCaptureInterpretation {
        if let errorMessage = message[errorKey] as? String {
            throw VoiceCaptureInterpretationError.unavailable(errorMessage)
        }

        guard let intentRawValue = message[intentKey] as? String,
              let intent = VoiceCaptureIntent(rawValue: intentRawValue),
              let normalizedText = message[normalizedTextKey] as? String else {
            throw VoiceCaptureInterpretationError.unavailable("The paired iPhone returned an invalid voice interpretation.")
        }

        return VoiceCaptureInterpretation(intent: intent, normalizedText: normalizedText)
    }
}

#if os(iOS)
private struct CompanionRelayReplyHandler: @unchecked Sendable {
    let send: ([String: Any]) -> Void

    /// Sends the provided dictionary message to the remote peer.
    /// - Parameter message: The payload dictionary to transmit over the connectivity session.
    func callAsFunction(_ message: [String: Any]) {
        send(message)
    }
}

@MainActor
package final class CompanionRelayNotesAssistantHostCoordinator {
    private let assistantFactory: @MainActor () -> any NotesAssistantService
    private let interpretationFactory: @MainActor () -> any VoiceCaptureInterpretationService
    private var assistants: [UUID: any NotesAssistantService] = [:]
    private var interpretationService: (any VoiceCaptureInterpretationService)?
    private var conversationOrder: [UUID] = []
    private let maximumCachedConversations = 8

    init(
        assistantFactory: @escaping @MainActor () -> any NotesAssistantService,
        interpretationFactory: @escaping @MainActor () -> any VoiceCaptureInterpretationService
    ) {
        self.assistantFactory = assistantFactory
        self.interpretationFactory = interpretationFactory
    }

    /// Routes a prompt to the cached assistant for the given conversation and returns the assistant's response.
    /// - Parameters:
    ///   - prompt: The user prompt to process.
    ///   - conversationID: The identifier for the conversation; used to select or create the cached assistant instance.
    /// - Returns: A `Result` containing the assistant's `NotesAssistantResponse` on success. On failure, returns an `Error` — `NotesAssistantError.unavailable(reason)` when the assistant capability is unavailable, or the underlying assistant error otherwise.
    func process(prompt: String, conversationID: UUID) async -> Result<NotesAssistantResponse, Error> {
        let assistant = assistant(for: conversationID)
        guard case .available = assistant.capabilityState else {
            if case let .unavailable(reason) = assistant.capabilityState {
                return .failure(NotesAssistantError.unavailable(reason))
            }
            return .failure(NotesAssistantError.unavailable("The on-device model is unavailable."))
        }

        do {
            return .success(try await assistant.process(prompt))
        } catch {
            return .failure(error)
        }
    }

    /// Routes a transcript and locale to the voice interpretation service and returns the interpretation result.
    /// - Parameters:
    ///   - transcript: The raw transcript text to classify or normalize.
    ///   - locale: The locale to use for interpretation (affects language and formatting).
    /// - Returns: A `Result` containing a `VoiceCaptureInterpretation` on success, or an `Error` on failure (for example, `VoiceCaptureInterpretationError.unavailable(reason)` when the interpretation service is unavailable).
    func interpret(transcript: String, locale: Locale) async -> Result<VoiceCaptureInterpretation, Error> {
        let interpretationService = interpretationService ?? {
            let service = interpretationFactory()
            self.interpretationService = service
            return service
        }()

        guard case .available = interpretationService.capabilityState else {
            if case let .unavailable(reason) = interpretationService.capabilityState {
                return .failure(VoiceCaptureInterpretationError.unavailable(reason))
            }
            return .failure(VoiceCaptureInterpretationError.unavailable("Voice command routing is unavailable."))
        }

        do {
            return .success(try await interpretationService.interpret(transcript: transcript, locale: locale))
        } catch {
            return .failure(error)
        }
    }

    /// Retrieves an existing `NotesAssistantService` for the given conversation ID or creates one.
    /// - Parameters:
    ///   - conversationID: The conversation UUID used as the cache key.
    /// - Returns: The `NotesAssistantService` instance associated with `conversationID`.
    private func assistant(for conversationID: UUID) -> any NotesAssistantService {
        if let existing = assistants[conversationID] {
            touchConversation(conversationID)
            return existing
        }

        let assistant = assistantFactory()
        assistants[conversationID] = assistant
        touchConversation(conversationID)
        pruneIfNeeded()
        return assistant
    }

    private func touchConversation(_ id: UUID) {
        conversationOrder.removeAll { $0 == id }
        conversationOrder.append(id)
    }

    /// Removes the oldest cached assistants until the cache size does not exceed `maximumCachedConversations`.
    private func pruneIfNeeded() {
        while conversationOrder.count > maximumCachedConversations {
            let removedID = conversationOrder.removeFirst()
            assistants.removeValue(forKey: removedID)
        }
    }
}

@MainActor
package final class CompanionRelayNotesAssistantHost: NSObject, WCSessionDelegate {
    private let session: WCSession?
    private let coordinator: CompanionRelayNotesAssistantHostCoordinator

    package init(
        assistantFactory: @escaping @MainActor () -> any NotesAssistantService,
        interpretationFactory: @escaping @MainActor () -> any VoiceCaptureInterpretationService
    ) {
        self.coordinator = CompanionRelayNotesAssistantHostCoordinator(
            assistantFactory: assistantFactory,
            interpretationFactory: interpretationFactory
        )
        if WCSession.isSupported() {
            let session = WCSession.default
            self.session = session
        } else {
            self.session = nil
        }
        super.init()

        session?.delegate = self
        session?.activate()
    }

    /// Handles completion of a WCSession activation. This implementation intentionally performs no action.
    /// - Parameters:
    ///   - session: The `WCSession` whose activation completed.
    ///   - activationState: The resulting `WCSessionActivationState`.
    ///   - error: An optional error that occurred during activation.
    package nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {}

    /// Handler invoked when the watch connectivity session transitions to the inactive state.
    ///
    /// This implementation intentionally performs no action.
    package nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Re-activates the given WatchConnectivity session after it finishes deactivation.
    /// - Parameter session: The `WCSession` instance that was deactivated.
    package nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// No-op handler invoked when a `WCSession`'s reachability changes.
    /// - Parameter session: The `WCSession` whose reachability state changed.
    package nonisolated func sessionReachabilityDidChange(_ session: WCSession) {}

    /// Handles an incoming WatchConnectivity message, routes it to the coordinator, and sends back an encoded reply.
    /// - Parameters:
    ///   - session: The `WCSession` that delivered the message.
    ///   - message: A dictionary payload expected to represent either an assistant request or a voice interpretation request.
    ///   - replyHandler: A closure invoked with the reply dictionary; replies contain either a successful response payload or an error payload describing why the request could not be fulfilled.
    package nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let reply = CompanionRelayReplyHandler(send: replyHandler)

        if let request = CompanionRelayMessageCodec.decodeAssistantRequest(message) {
            Task { @MainActor in
                let result = await coordinator.process(prompt: request.prompt, conversationID: request.id)
                switch result {
                case let .success(response):
                    reply(CompanionRelayMessageCodec.assistantResponse(id: request.id, response: response))
                case let .failure(error):
                    reply(
                        CompanionRelayMessageCodec.error(
                            id: request.id,
                            message: error.localizedDescription
                        )
                    )
                }
            }
            return
        }

        if let request = CompanionRelayMessageCodec.decodeVoiceInterpretationRequest(message) {
            Task { @MainActor in
                let locale = Locale(identifier: request.localeIdentifier)
                let result = await coordinator.interpret(transcript: request.transcript, locale: locale)
                switch result {
                case let .success(interpretation):
                    reply(
                        CompanionRelayMessageCodec.voiceInterpretationResponse(
                            id: request.id,
                            interpretation: interpretation
                        )
                    )
                case let .failure(error):
                    reply(
                        CompanionRelayMessageCodec.error(
                            id: request.id,
                            message: error.localizedDescription
                        )
                    )
                }
            }
            return
        }

        reply(CompanionRelayMessageCodec.error(id: nil, message: "The watch sent an invalid relay request."))
    }
}
#endif

#if os(watchOS)
@MainActor
package final class CompanionRelayNotesAssistant: NSObject, NotesAssistantService, VoiceCaptureInterpretationService, WCSessionDelegate {
    private let session: WCSession?
    private var conversationID = UUID()

    package init(session: WCSession? = WCSession.isSupported() ? .default : nil) {
        self.session = session
        super.init()

        self.session?.delegate = self
        self.session?.activate()
    }

    package var capabilityState: AssistantCapabilityState {
        guard let session else {
            return .unavailable(reason: "Companion relay is unavailable on this Apple Watch.")
        }

        guard session.activationState == .activated else {
            return .unavailable(reason: "Connecting to the paired iPhone for Ask Notes.")
        }

        guard session.isReachable else {
            return .unavailable(reason: "Ask Notes on Apple Watch requires the paired iPhone to be nearby and reachable.")
        }

        return .available
    }

    /// Prewarms the service for upcoming use.
    ///
    /// This implementation is a no-op.
    package func prewarm() {}

    /// Regenerates the conversation identifier used to correlate requests and responses.
    package func resetConversation() {
        conversationID = UUID()
    }

    /// Sends the given assistant prompt to the paired iPhone and returns the decoded response.
    ///
    /// This requires an active, reachable companion relay session.
    /// - Parameters:
    ///   - input: The user prompt to send to the companion assistant.
    /// - Returns: A `NotesAssistantResponse` decoded from the companion reply, including response text, referenced note IDs, and interaction state.
    /// - Throws: `NotesAssistantError.unavailable` when the companion relay session is missing, when the paired iPhone is unavailable (propagating the capability state's reason when present), or when the message could not be delivered to the paired iPhone (the error's localized description is included).
    package func process(_ input: String) async throws -> NotesAssistantResponse {
        guard let session else {
            throw NotesAssistantError.unavailable("Companion relay is unavailable on this Apple Watch.")
        }

        guard case .available = capabilityState else {
            if case let .unavailable(reason) = capabilityState {
                throw NotesAssistantError.unavailable(reason)
            }
            throw NotesAssistantError.unavailable("The paired iPhone is unavailable.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            session.sendMessage(
                CompanionRelayMessageCodec.assistantRequest(id: conversationID, prompt: input),
                replyHandler: { reply in
                    do {
                        continuation.resume(returning: try CompanionRelayMessageCodec.decodeAssistantResponse(reply))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                },
                errorHandler: { error in
                    continuation.resume(
                        throwing: NotesAssistantError.unavailable(
                            "Ask Notes on Apple Watch could not reach the paired iPhone. \(error.localizedDescription)"
                        )
                    )
                }
            )
        }
    }

    /// Interprets a speech transcript by relaying it to the paired iPhone and returning the resolved intent and normalized text.
    /// - Parameters:
    ///   - transcript: The raw speech transcript to interpret.
    ///   - locale: The locale to use when interpreting the transcript.
    /// - Returns: A `VoiceCaptureInterpretation` containing the resolved intent and a normalized text representation.
    /// - Throws: `VoiceCaptureInterpretationError.unavailable` if the companion relay or paired iPhone is unavailable or if the watch cannot reach the paired iPhone.
    package func interpret(transcript: String, locale: Locale) async throws -> VoiceCaptureInterpretation {
        guard let session else {
            throw VoiceCaptureInterpretationError.unavailable("Companion relay is unavailable on this Apple Watch.")
        }

        guard case .available = capabilityState else {
            if case let .unavailable(reason) = capabilityState {
                throw VoiceCaptureInterpretationError.unavailable(reason)
            }
            throw VoiceCaptureInterpretationError.unavailable("The paired iPhone is unavailable.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            session.sendMessage(
                CompanionRelayMessageCodec.voiceInterpretationRequest(
                    id: conversationID,
                    transcript: transcript,
                    locale: locale
                ),
                replyHandler: { reply in
                    do {
                        continuation.resume(
                            returning: try CompanionRelayMessageCodec.decodeVoiceInterpretationResponse(reply)
                        )
                    } catch {
                        continuation.resume(throwing: error)
                    }
                },
                errorHandler: { error in
                    continuation.resume(
                        throwing: VoiceCaptureInterpretationError.unavailable(
                            "Voice command routing on Apple Watch could not reach the paired iPhone. \(error.localizedDescription)"
                        )
                    )
                }
            )
        }
    }

    /// Handles completion of a `WCSession` activation.
    ///
    /// This implementation intentionally performs no action.
    /// - Parameters:
    ///   - session: The `WCSession` whose activation completed.
    ///   - activationState: The resulting `WCSessionActivationState`.
    ///   - error: An optional error that occurred during activation.
    package nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {}

    /// No-op handler invoked when a `WCSession`'s reachability changes.
    /// - Parameter session: The `WCSession` whose reachability state changed.
    package nonisolated func sessionReachabilityDidChange(_ session: WCSession) {}
}
#endif
#endif
