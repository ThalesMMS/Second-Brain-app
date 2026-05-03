import Foundation
import SecondBrainDomain
#if (os(iOS) || os(macOS)) && canImport(FoundationModels)
import FoundationModels

@MainActor
package final class NotesToolbox {
    struct ConversationSnapshot {
        let referencedNoteIDs: Set<UUID>
        let pendingEdit: PendingNoteEdit?
    }

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

    /// Searches notes for snippets matching the given query and returns a formatted summary of matches.
    ///
    /// Matched note IDs are recorded in `referencedNoteIDs`.
    /// - Returns: A single string containing either the exact text "No matching notes were found." or a numbered list of matched snippets where each entry includes the note UUID, title, excerpt, and the updated timestamp formatted with abbreviated date and shortened time.
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

    /// Reads a note resolved from the given reference and returns a formatted representation containing its id, title, and full body.
    ///
    /// The resolved note ID is added to `referencedNoteIDs`.
    /// - Parameter reference: A note identifier or a natural-language reference used to locate the target note.
    /// - Returns: `"No note matched the provided reference."` if resolution fails; otherwise a multi-line string with:
    ///   - `id: <uuidString>`
    ///   - `title: <displayTitle>`
    ///   - `body:` followed by the note's full body text.
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

    /// Creates a new assistant-origin note with the provided title and body and records its ID in the conversation context.
    /// - Parameters:
    ///   - title: The note's title.
    ///   - body: The note's body content.
    /// - Returns: A confirmation string containing the created note's display title and UUID.
    func create(title: String, body: String) async throws -> String {
        let note = try await repository.createNote(title: title, body: body, source: .assistant, initialEntryKind: .creation)
        referencedNoteIDs.insert(note.id)
        return "Created note \(note.displayTitle) with id \(note.id.uuidString)."
    }

    /// Appends the given text to a note resolved from the provided reference and returns a user-facing message.
    /// - Parameters:
    ///   - reference: A note identifier or natural-language reference used to resolve the target note.
    ///   - content: The text to append; leading/trailing whitespace and newlines are trimmed before appending.
    /// - Returns: A confirmation string of the form `Appended content to note <displayTitle> with id <uuid>.`, or the exact message `No changes; nothing to append.` if the trimmed content is empty, or the exact message `No note matched the provided reference.` if resolution fails.
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

    /// Proposes and applies an edit to an existing note identified by a UUID string, updates toolbox state, and returns a user-facing outcome message.
    /// - Parameters:
    ///   - noteID: The note's UUID string (whitespace/newlines are trimmed) identifying which note to edit.
    ///   - instruction: Natural-language instructions describing the desired edit.
    /// - Returns: A user-facing message describing the result of the edit operation — this may be a confirmation that the edit was applied, a pending-edit confirmation prompt, a clarification request, a no-change notice, or a cancellation message.
    /// - Throws: `NotesAssistantError.unavailable` when the on-device edit intelligence capability is unavailable (the provided reason is preserved).
    func edit(noteID: String, instruction: String) async throws -> String {
        if case let .unavailable(reason) = editIntelligence.capabilityState {
            throw NotesAssistantError.unavailable(reason)
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

    /// Resolves the currently pending note edit by confirming or cancelling it.
    ///
    /// The input is trimmed and lowercased; valid decisions are `"confirm"` and `"cancel"`. If the decision is invalid
    /// or there is no pending edit to act on, a human-readable message explaining the situation is returned.
    /// - Parameters:
    ///   - decision: The user's decision; must be `"confirm"` or `"cancel"` (whitespace- and case-insensitive).
    /// - Returns: A user-facing message describing the outcome or why no action was taken (e.g. invalid decision or no pending edit).
    /// - Throws: Any error produced while resolving the pending edit via the edit use case.
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

    /// Resets the conversation state by clearing all tracked referenced note IDs and discarding any pending edit.
    func resetConversation() {
        referencedNoteIDs.removeAll()
        pendingEdit = nil
    }

    /// Reports the notes assistant's current interaction state.
    /// - Returns: The current `NotesAssistantInteractionState`: `.none` when there is no pending edit, `.pendingEditConfirmation` when an edit is awaiting confirmation.
    func currentInteractionState() -> NotesAssistantInteractionState {
        pendingEdit == nil ? .none : .pendingEditConfirmation
    }

    func conversationSnapshot() -> ConversationSnapshot {
        ConversationSnapshot(referencedNoteIDs: referencedNoteIDs, pendingEdit: pendingEdit)
    }

    func restoreConversationSnapshot(_ snapshot: ConversationSnapshot) {
        referencedNoteIDs = snapshot.referencedNoteIDs
        pendingEdit = snapshot.pendingEdit
    }

    /// Provides the referenced note IDs sorted by their UUID string and clears the stored set.
    /// - Returns: An array of referenced note UUIDs sorted by their `uuidString`. The toolbox's stored referenced IDs are cleared.
    func consumeReferencedNoteIDs() -> [UUID] {
        let ids = Array(referencedNoteIDs)
        referencedNoteIDs.removeAll()
        return ids.sorted { $0.uuidString < $1.uuidString }
    }

    /// Applies an edit-use-case result to the toolbox's conversational state and returns its user-facing message.
    /// 
    /// - Parameter result: The `EditExistingNoteUseCase.Result` to handle.
    /// - Returns: The message associated with the result.
    /// 
    /// Behavior by result case:
    /// - `.applied(note, _)`: inserts `note.id` into `referencedNoteIDs` and clears `pendingEdit`.
    /// - `.pending(nextPending, _)`: inserts `nextPending.noteID` into `referencedNoteIDs` and sets `pendingEdit` to `nextPending`.
    /// - `.clarification(_)`, `.noChange(_)`, `.cancelled(_)`: clears `pendingEdit`.
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

@available(iOS 26.0, macOS 26.0, *)
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

    /// Performs a notes search using the provided query and returns a user-facing result string.
    /// - Parameters:
    ///   - arguments: The `Arguments` payload containing the search `query` to match notes.
    /// - Returns: A formatted string with a numbered list of matching note snippets, or the exact text "No matching notes were found." if there are no matches.
    func call(arguments: Arguments) async throws -> String {
        try await toolbox.search(query: arguments.query)
    }
}

@available(iOS 26.0, macOS 26.0, *)
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

    /// Reads a note identified by an exact id or a natural-language reference.
    /// - Parameters:
    ///   - arguments: The tool arguments; `arguments.reference` is the note id or a natural-language reference to resolve.
    /// - Returns: A formatted string containing the note's id, display title, and full body, or a message stating that no note matched the provided reference.
    func call(arguments: Arguments) async throws -> String {
        try await toolbox.read(reference: arguments.reference)
    }
}

@available(iOS 26.0, macOS 26.0, *)
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

    /// Creates a new note using the toolbox with the provided title and body.
    /// - Parameters:
    ///   - arguments: The call arguments containing:
    ///     - `title`: The note's title.
    ///     - `body`: The note's initial body text.
    /// - Returns: A confirmation message describing the created note, including its display title and UUID.
    func call(arguments: Arguments) async throws -> String {
        try await toolbox.create(title: arguments.title, body: arguments.body)
    }
}

@available(iOS 26.0, macOS 26.0, *)
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

    /// Appends the provided content to an existing note identified by the given reference.
    /// - Parameters:
    ///   - arguments: Container with the call inputs:
    ///     - reference: A note identifier or natural-language reference to locate the target note.
    ///     - content: The text to append to the note.
    /// - Returns: A user-facing message confirming the append, or an explanatory message if no changes were made or the note could not be found.
    func call(arguments: Arguments) async throws -> String {
        try await toolbox.append(reference: arguments.reference, content: arguments.content)
    }
}

@available(iOS 26.0, macOS 26.0, *)
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

    /// Edits an existing note identified by the provided note ID using the given instruction.
    /// - Parameters:
    ///   - arguments: Container with `noteID` (the exact UUID string of the target note) and `instruction` (the edit instruction to apply).
    /// - Returns: A user-facing message describing the result of the edit.
    func call(arguments: Arguments) async throws -> String {
        try await toolbox.edit(noteID: arguments.noteID, instruction: arguments.instruction)
    }
}

@available(iOS 26.0, macOS 26.0, *)
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

    /// Resolves the currently pending note edit using the provided decision.
    /// - Parameters:
    ///   - arguments: An `Arguments` value whose `decision` must be either `"confirm"` or `"cancel"`.
    /// - Returns: A user-facing message describing the result of resolving the pending edit.
    func call(arguments: Arguments) async throws -> String {
        try await toolbox.resolvePendingEdit(decision: arguments.decision)
    }
}
#endif
