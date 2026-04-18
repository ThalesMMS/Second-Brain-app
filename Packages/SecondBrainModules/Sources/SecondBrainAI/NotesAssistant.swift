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

    /// Searches the repository for note snippets matching `input` and returns a response summarizing the results.
    /// - Parameter input: The search query used to find relevant note snippets.
    /// - Returns: A `NotesAssistantResponse` whose `text` either lists matching notes as bullet lines with their titles and excerpts or states that no related notes were found; `referencedNoteIDs` contains the IDs of matched snippets or is empty if none matched.
    /// - Throws: Any error propagated from `repository.snippets(matching:limit:)`.
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
    /// - Throws: `VoiceCaptureInterpretationError.unavailable` when the interpretation service is unavailable, carrying the unavailability reason.
    package func interpret(transcript: String, locale: Locale) async throws -> VoiceCaptureInterpretation {
        throw VoiceCaptureInterpretationError.unavailable(reason)
    }
}