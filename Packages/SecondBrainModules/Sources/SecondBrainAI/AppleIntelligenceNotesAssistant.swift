import Foundation
import SecondBrainDomain
#if os(iOS) && canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
@MainActor
package final class AppleIntelligenceNotesAssistant: NotesAssistantService {
    private let model: SystemLanguageModel
    private let toolbox: NotesToolbox
    private let fallback: DeterministicNotesAssistant
    private var session: LanguageModelSession

    package init(
        repository: any NoteRepository,
        editIntelligence: any NoteEditIntelligenceService = AppleIntelligenceNoteEditService()
    ) {
        let model = SystemLanguageModel(
            useCase: .general,
            guardrails: .permissiveContentTransformations
        )
        let toolbox = NotesToolbox(
            repository: repository,
            editIntelligence: editIntelligence
        )
        self.model = model
        self.toolbox = toolbox
        self.fallback = DeterministicNotesAssistant(repository: repository)
        self.session = Self.makeSession(toolbox: toolbox, model: model)
    }

    package var capabilityState: AssistantCapabilityState {
        fallback.capabilityState
    }

    package var status: NotesAssistantStatus? {
        appleIntelligenceReducedFunctionalityStatus(for: model)
    }

    /// Primes the internal language model session to reduce latency for subsequent requests.
    package func prewarm() {
        session.prewarm()
    }

    /// Resets the assistant's conversational state and recreates its language model session.
    ///
    /// Clears any in-memory conversation state maintained by the toolbox and replaces the current
    /// `LanguageModelSession` with a fresh session configured for the assistant.
    package func resetConversation() {
        toolbox.resetConversation()
        session = Self.makeSession(toolbox: toolbox, model: model)
    }

    /// Produces an assistant response for the given user input, using the system language model when available and delegating to the deterministic fallback when not.
    /// - Parameter input: The user's prompt or instruction for the notes assistant.
    /// - Returns: A `NotesAssistantResponse` containing the model-generated text, any note UUIDs the assistant referenced during the interaction, and the toolbox's current interaction state.
    package func process(_ input: String) async throws -> NotesAssistantResponse {
        guard case .available = model.availability else {
            return try await fallback.process(input)
        }

        let toolboxSnapshot = toolbox.conversationSnapshot()
        do {
            let response = try await session.respond(
                to: input,
                options: GenerationOptions(sampling: .greedy)
            )
            let interaction = toolbox.currentInteractionState()
            let referencedIDs = toolbox.consumeReferencedNoteIDs()
            return NotesAssistantResponse(
                text: response.content,
                referencedNoteIDs: referencedIDs,
                interaction: interaction
            )
        } catch {
            toolbox.restoreConversationSnapshot(toolboxSnapshot)
            throw error
        }
    }

    /// Constructs a LanguageModelSession configured for the Second Brain notes assistant.
    ///
    /// The session is initialized with a set of tools bound to the provided `toolbox` (search, read, create, append, edit, and resolve-pending-edit)
    /// and assistant instructions that constrain tool usage, require searching/reading before editing or answering from notes, avoid fabricating note data,
    /// and preserve the user's language.
    /// - Parameters:
    ///   - toolbox: The NotesToolbox used to create and bind tool instances to the session's repository and conversational state.
    ///   - model: The configured system language model used by the assistant.
    /// - Returns: A LanguageModelSession initialized with the assistant's tools and behavioral instructions.
    private static func makeSession(toolbox: NotesToolbox, model: SystemLanguageModel) -> LanguageModelSession {
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

        return LanguageModelSession(model: model, tools: tools, instructions: instructions)
    }
}
#endif
