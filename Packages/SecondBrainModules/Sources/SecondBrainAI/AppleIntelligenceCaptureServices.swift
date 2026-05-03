import Foundation
import SecondBrainDomain
#if (os(iOS) || os(macOS)) && canImport(FoundationModels)
import FoundationModels
import OSLog

private let appleIntelligenceLogger = Logger(
    subsystem: "SecondBrain",
    category: "AppleIntelligence"
)

/// Maps a `SystemLanguageModel`'s availability to an `AssistantCapabilityState`.
/// - Parameters:
///   - model: The system language model whose availability will be inspected.
/// - Returns: An `AssistantCapabilityState` — `.available` when the model is available; otherwise `.unavailable(reason: <message>)` where `<message>` is a user-facing explanation:
///   - `deviceNotEligible` → "Apple Intelligence is unavailable on this device."
///   - `appleIntelligenceNotEnabled` → "Apple Intelligence is turned off on this device."
///   - `modelNotReady` → "Apple Intelligence is still preparing its on-device model."
///   - unknown/unhandled reasons → "The on-device model is unavailable."
@available(iOS 26.0, macOS 26.0, *)
func appleIntelligenceCapabilityState(for model: SystemLanguageModel) -> AssistantCapabilityState {
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

/// Map a system language model's capability into a notes assistant reduced-functionality status.
/// - Parameter model: The `SystemLanguageModel` whose availability will be checked.
/// - Returns: `nil` if the model is available; otherwise `.reducedFunctionality(reason: "<reason> Falling back to deterministic retrieval.")`, where `<reason>` is the human-readable unavailability message.
@available(iOS 26.0, macOS 26.0, *)
func appleIntelligenceReducedFunctionalityStatus(
    for model: SystemLanguageModel
) -> NotesAssistantStatus? {
    switch appleIntelligenceCapabilityState(for: model) {
    case .available:
        return nil
    case let .unavailable(reason):
        return .reducedFunctionality(reason: "\(reason) Falling back to deterministic retrieval.")
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct NoteCaptureRefinementPayload {
    @Guide(description: "A concise note title. Keep explicit titles when they are already good, and avoid adding facts.")
    let title: String

    @Guide(description: "The complete note body after cleanup. Preserve meaning, details, numbers, lists, and dates.")
    let body: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct VoiceCaptureInterpretationPayload {
    @Guide(description: "Either newNote or assistantCommand.")
    let intent: String

    @Guide(description: "The cleaned note content or cleaned assistant command in the same language as the transcript.")
    let normalizedText: String
}

@available(iOS 26.0, macOS 26.0, *)
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

@available(iOS 26.0, macOS 26.0, *)
package final class AppleIntelligenceVoiceCaptureInterpretationService: VoiceCaptureInterpretationService, @unchecked Sendable {
    private let model = SystemLanguageModel(
        useCase: .general,
        guardrails: .permissiveContentTransformations
    )

    package init() {}

    package var capabilityState: AssistantCapabilityState {
        appleIntelligenceCapabilityState(for: model)
    }

    /// Classifies a raw voice transcript as either a new note or an assistant command and returns a cleaned, language-matched interpretation.
    /// - Parameters:
    ///   - transcript: The raw captured transcript to classify and normalize.
    ///   - locale: The preferred locale to guide language selection when the transcript language is ambiguous.
    /// - Throws: `VoiceCaptureInterpretationError.unavailable` if the Apple Intelligence capability is unavailable.
    /// - Returns: A `VoiceCaptureInterpretation` containing the resolved `intent` and cleaned `normalizedText`.
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

    /// Ensures the Apple Intelligence capability required by this service is available.
    /// - Throws: `VoiceCaptureInterpretationError.unavailable` with the capability's human-readable reason when the capability is `.unavailable`.
    private func ensureAvailable() throws {
        if case let .unavailable(reason) = capabilityState {
            throw VoiceCaptureInterpretationError.unavailable(reason)
        }
    }

    /// Creates a LanguageModelSession configured to route spoken input into note creation or note commands.
    /// - Returns: A `LanguageModelSession` with instructions that route spoken input into either note creation or note commands and that emphasize conservative handling of `assistantCommand`.
    private func makeSession() -> LanguageModelSession {
        LanguageModelSession(model: model) {
            "You route spoken input into either note creation or note commands."
            "Be conservative about assistantCommand."
        }
    }

    /// Produces a cleaned `VoiceCaptureInterpretation` from a model payload and the original transcript.
    /// - Parameters:
    ///   - payload: The model-generated payload containing `intent` and `normalizedText`.
    ///   - transcript: The original raw transcript used as a fallback when `normalizedText` is empty.
    /// - Returns: A `VoiceCaptureInterpretation` whose `intent` comes from `payload.intent` and whose `normalizedText` is `payload.normalizedText` trimmed of whitespace and newlines or, if that is empty, the trimmed `transcript`.
    private func normalize(
        _ payload: VoiceCaptureInterpretationPayload,
        transcript: String
    ) -> VoiceCaptureInterpretation {
        let cleanedText = payload.normalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIntent = payload.intent.trimmingCharacters(in: .whitespacesAndNewlines)
        let intent: VoiceCaptureIntent
        if let parsedIntent = VoiceCaptureIntent(rawValue: trimmedIntent) {
            intent = parsedIntent
        } else {
            appleIntelligenceLogger.error(
                "Unknown voice capture intent from FoundationModels payload: \(trimmedIntent, privacy: .public)"
            )
            intent = .unknown
        }

        return VoiceCaptureInterpretation(
            intent: intent,
            normalizedText: cleanedText.isEmpty ? transcript.trimmingCharacters(in: .whitespacesAndNewlines) : cleanedText
        )
    }
}

@available(iOS 26.0, macOS 26.0, *)
package final class AppleIntelligenceNoteCaptureIntelligenceService: NoteCaptureIntelligenceService, @unchecked Sendable {
    private let model = SystemLanguageModel(
        useCase: .general,
        guardrails: .permissiveContentTransformations
    )

    package init() {}

    package var capabilityState: AssistantCapabilityState {
        appleIntelligenceCapabilityState(for: model)
    }

    /// Refines a quick-capture note's title and body into a cleaned, storage-ready form.
    /// - Parameters:
    ///   - title: The original note title; if empty, a concise title may be derived from the body.
    ///   - body: The original note body to be cleaned up.
    ///   - locale: The preferred locale to use when choosing output language and formatting.
    /// - Returns: A `NoteCaptureRefinement` containing a cleaned `title` and `body`. If the model returns empty fields, the corresponding provided `title` or `body` is used as a fallback.
    /// - Throws: `CaptureIntelligenceError.unavailable(reason)` when the on-device model is unavailable or otherwise cannot be used.
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

    /// Refines a raw speech transcript into a cleaned note (title and body).
    /// - Parameters:
    ///   - title: A fallback or existing title; used if the model does not produce a non-empty title.
    ///   - transcript: The raw speech transcript to be corrected and converted into a readable body.
    ///   - locale: Preferred locale identifier to guide language selection when the transcript language is ambiguous.
    /// - Returns: A `NoteCaptureRefinement` whose `title` and `body` are taken from the model's output; if the model returns an empty title or body, the provided `title` and `transcript` are used respectively.
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

    /// Ensures the Apple Intelligence capture capability is available.
    /// - Throws: `CaptureIntelligenceError.unavailable` with the model-provided reason when the capability is unavailable.
    private func ensureAvailable() throws {
        if case let .unavailable(reason) = capabilityState {
            throw CaptureIntelligenceError.unavailable(reason)
        }
    }

    /// Creates a language model session configured to produce high-fidelity notes suitable for permanent storage.
    /// - Returns: A `LanguageModelSession` configured to prepare notes for storage with conservative content-preservation instructions.
    private func makeSession() -> LanguageModelSession {
        LanguageModelSession(model: model) {
            "You prepare high-fidelity notes for permanent storage."
            "Keep the user's original meaning."
            "Improve formatting, not substance."
        }
    }

    /// Resolves and cleans a `NoteCaptureRefinementPayload` into a `NoteCaptureRefinement`.
    /// - Parameters:
    ///   - payload: The model-produced payload containing `title` and `body`.
    ///   - fallbackTitle: Title to use when `payload.title` is empty or whitespace; will be trimmed.
    ///   - fallbackBody: Body to use when `payload.body` is empty or whitespace; will be trimmed.
    /// - Returns: A `NoteCaptureRefinement` whose `title` and `body` are trimmed of surrounding whitespace and newlines; if a payload field is empty after trimming, the corresponding trimmed fallback value is used.
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

@available(iOS 26.0, macOS 26.0, *)
package final class AppleIntelligenceNoteEditService: NoteEditIntelligenceService, @unchecked Sendable {
    private let model = SystemLanguageModel(
        useCase: .general,
        guardrails: .permissiveContentTransformations
    )

    package var capabilityState: AssistantCapabilityState {
        appleIntelligenceCapabilityState(for: model)
    }

    package init() {}

    /// Generates a structured edit proposal for an existing note based on the user's instruction and the note's current content.
    /// - Parameters:
    ///   - noteID: The identifier of the note to be edited.
    ///   - title: The current title of the note; used as a fallback if the model does not provide one.
    ///   - body: The current body of the note; used as a fallback if the model does not provide one.
    ///   - instruction: A natural-language edit request describing the desired changes.
    ///   - locale: The preferred locale/language to use when interpreting the instruction and producing the proposal.
    /// - Returns: A `NoteEditProposal` containing the resolved `scope` (`title`, `excerpt`, or `wholeBody`), the updated title and body (falling back to the provided values when the model output is empty), an optional `targetExcerpt` (nil if empty), a `changeSummary` (defaults to "Update the note." when empty), and an optional `clarificationQuestion` (nil if empty).
    /// - Throws: `NotesAssistantError.unavailable` when the on-device model or Apple Intelligence capability is unavailable.
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

    /// Verifies that the Apple Intelligence capability is available; throws if it is not.
    /// - Throws: `NotesAssistantError.unavailable` with the capability's human-readable reason when the model reports an unavailability.
    private func ensureAvailable() throws {
        if case let .unavailable(reason) = capabilityState {
            throw NotesAssistantError.unavailable(reason)
        }
    }

    /// Creates a language model session configured to convert natural-language edit requests into conservative, structured note edits.
    /// - Returns: A `LanguageModelSession` with routing instructions that prioritize safe, conservative transformations when the target text is ambiguous.
    private func makeSession() -> LanguageModelSession {
        LanguageModelSession(model: model) {
            "You transform natural-language edit requests into safe structured note edits."
            "Be conservative when the target text is ambiguous."
        }
    }

    /// Normalizes a `NoteEditProposalPayload` into a `NoteEditProposal`, resolving empty or ambiguous fields and applying sensible defaults.
    /// - Parameters:
    ///   - payload: The payload produced by the language model to normalize.
    ///   - noteID: The identifier of the note being edited; included in the resulting proposal.
    ///   - fallbackTitle: Title to use when the payload's `updatedTitle` is empty after trimming.
    ///   - fallbackBody: Body to use when the payload's `updatedBody` is empty.
    /// - Returns: A `NoteEditProposal` where:
    ///   - `scope` comes from `payload.scope`.
    ///   - `updatedTitle` is the trimmed `payload.updatedTitle` or `fallbackTitle` if empty.
    ///   - `updatedBody` is `payload.updatedBody` unless it is empty or whitespace-only, in which case `fallbackBody` is used.
    ///   - `targetExcerpt` is preserved verbatim and set to `nil` only when empty.
    ///   - `clarificationQuestion` is trimmed and set to `nil` if empty after trimming.
    ///   - `changeSummary` is trimmed and defaults to `"Update the note."` when empty.
    private func normalize(
        _ payload: NoteEditProposalPayload,
        noteID: UUID,
        fallbackTitle: String,
        fallbackBody: String
    ) -> NoteEditProposal {
        let cleanedTitle = payload.updatedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedBody = payload.updatedBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? fallbackBody
            : payload.updatedBody
        let trimmedScope = payload.scope.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedScope = NoteEditScope(rawValue: trimmedScope)
        if parsedScope == nil {
            appleIntelligenceLogger.error(
                "Unknown note edit scope from FoundationModels payload: \(trimmedScope, privacy: .public)"
            )
        }
        let cleanedScope = parsedScope ?? .clarify
        let cleanedTarget = payload.targetExcerpt
        let cleanedSummary = payload.changeSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedQuestion = payload.clarificationQuestion?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedClarificationQuestion = cleanedScope == .clarify
            ? cleanedQuestion ?? "I could not understand the edit scope returned by Apple Intelligence. Please clarify the edit."
            : cleanedQuestion

        return NoteEditProposal(
            noteID: noteID,
            scope: cleanedScope,
            updatedTitle: cleanedTitle.isEmpty ? fallbackTitle : cleanedTitle,
            updatedBody: cleanedBody,
            targetExcerpt: cleanedTarget?.isEmpty == true ? nil : cleanedTarget,
            changeSummary: cleanedSummary.isEmpty ? "Update the note." : cleanedSummary,
            clarificationQuestion: resolvedClarificationQuestion?.isEmpty == true ? nil : resolvedClarificationQuestion
        )
    }
}
#endif
