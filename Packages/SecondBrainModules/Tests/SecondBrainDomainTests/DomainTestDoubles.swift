import Foundation
@testable import SecondBrainDomain

actor InMemoryNoteRepository: NoteRepository {
    private var notes: [UUID: Note] = [:]
    private var deleteOnNextReplaceID: UUID?
    private var mutateOnNextReplaceID: UUID?

    /// Provide summaries of notes matching an optional query.
    /// - Parameters:
    ///   - query: An optional search string; when `nil` or empty (after trimming) no filtering is applied.
    /// - Returns: An array of `NoteSummary` for matching notes, ordered by relevance and the repository's deterministic sort.
    func listNotes(matching query: String?) async throws -> [NoteSummary] {
        filteredNotes(matching: query).map(makeSummary)
    }

    /// Returns a list of the most recent note summaries up to the requested maximum.
    /// - Parameters:
    ///   - limit: The maximum number of summaries to return; if `limit` is less than or equal to zero, an empty array is returned.
    /// - Returns: An array of up to `limit` `NoteSummary` values representing the most recent notes.
    func pickerRecentNotes(limit: Int) async throws -> [NoteSummary] {
        guard limit > 0 else {
            return []
        }

        return Array(filteredNotes(matching: nil).map(makeSummary).prefix(limit))
    }

    /// Searches notes using the given query and returns up to the requested number of summaries.
    /// - Parameters:
    ///   - query: The search string used to match notes.
    ///   - limit: The maximum number of summaries to return.
    /// - Returns: An array containing at most `limit` matching `NoteSummary` values; returns an empty array when `limit` is less than or equal to zero.
    func searchNotes(matching query: String, limit: Int) async throws -> [NoteSummary] {
        guard limit > 0 else {
            return []
        }

        return Array(filteredNotes(matching: query).map(makeSummary).prefix(limit))
    }

    /// Loads a note with the specified UUID.
    /// - Returns: The `Note` with the given `id` if it exists, `nil` otherwise.
    func loadNote(id: UUID) async throws -> Note? {
        notes[id]
    }

    /// Creates a new `Note` using the provided title and body, setting both `createdAt` and `updatedAt` to the current date and adding a single initial `NoteEntry` of the specified kind.
    /// - Parameters:
    ///   - title: The title to store on the note (may be derived from `body` if empty).
    ///   - body: The note body; whitespace/newlines are trimmed before storage.
    ///   - source: The origin of this mutation (e.g., user, import) recorded on the note entry.
    ///   - initialEntryKind: The `NoteEntryKind` to use for the initial entry added to the note.
    /// - Returns: The newly created `Note` with current timestamps and one initial entry.
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

    /// Creates and stores a new `Note` with a single initial `NoteEntry`.
    /// - Parameters:
    ///   - title: The note title (leading/trailing whitespace/newlines are ignored when deriving the stored title).
    ///   - body: The note body (trimmed of leading/trailing whitespace/newlines before storage).
    ///   - source: The origin of the mutation to record on the initial entry.
    ///   - initialEntryKind: The kind of the initial `NoteEntry` to attach to the note.
    ///   - createdAt: Timestamp to use for the note's `createdAt` and for the initial entry's `createdAt`.
    ///   - updatedAt: Timestamp to set as the note's `updatedAt`.
    /// - Returns: The newly created and stored `Note`.
    /// - Throws: `NoteRepositoryError.emptyContent` if both the trimmed `body` and the trimmed `title` are empty.
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

    /// Appends trimmed text to the specified note's body, updates the title and timestamp, records an `.append` entry, and saves the note.
    /// - Parameters:
    ///   - text: The text to append; leading/trailing whitespace and newlines are trimmed and an empty result is a no-op.
    ///   - noteID: The identifier of the note to modify.
    ///   - source: The source of the mutation recorded on the appended entry.
    /// - Returns: The updated `Note` with the appended text, refreshed `updatedAt`, and a new `.append` `NoteEntry`.
    /// - Throws: `NoteRepositoryError.notFound` if no note exists for `noteID`.
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

    /// Replace a note's title and body, record a `.replaceBody` entry, and persist the updated note.
    /// 
    /// If `deleteOnNextReplaceID` equals `id`, the flag is cleared and the note is removed, causing a `notFound` error.
    /// If `mutateOnNextReplaceID` equals `id`, the flag is cleared and the note's `updatedAt` is bumped by one second before further checks.
    /// The provided `body` is trimmed and the title is derived from `title` and the cleaned body; `updatedAt` is set to the current time and a new `NoteEntry` is appended.
    /// - Parameters:
    ///   - id: The identifier of the note to replace.
    ///   - title: The candidate title used to derive the stored title.
    ///   - body: The new body text; leading/trailing whitespace and newlines are trimmed.
    ///   - source: The source of the mutation recorded on the appended entry.
    ///   - expectedUpdatedAt: If non-nil, treated as an optimistic-concurrency token; if it does not equal the note's current `updatedAt`, the operation fails.
    /// - Returns: The updated `Note`.
    /// - Throws: `NoteRepositoryError.notFound` if the note does not exist (or was removed by the delete-on-next-replace flag).  
    /// - Throws: `NoteRepositoryError.conflict` if `expectedUpdatedAt` is provided and does not match the note's current `updatedAt`.
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
        if cleanedBody.isEmpty && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return note
        }

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

    /// Marks the given note ID so that the next call to `replaceNote` for that ID will delete the note instead of replacing it.
    /// - Parameters:
    ///   - id: The `UUID` of the note to delete on the next replace; the flag is one-shot and is cleared after that replace.
    func deleteOnNextReplace(id: UUID) {
        deleteOnNextReplaceID = id
    }

    /// Schedules a one-shot `updatedAt` bump for the note with the given id on the next `replaceNote` call.
    /// - Parameter id: The UUID of the note to mutate on the next replace; the flag is cleared after it is consumed.
    func mutateOnNextReplace(id: UUID) {
        mutateOnNextReplaceID = id
    }

    func setPinned(id: UUID, isPinned: Bool) async throws {
        guard var note = notes[id] else {
            throw NoteRepositoryError.notFound
        }

        note.isPinned = isPinned
        notes[id] = note
    }

    /// Deletes the note with the given id from the in-memory store.
    /// If no note exists for the id, this call is a no-op.
    /// - Parameter id: The UUID of the note to remove.
    func deleteNote(id: UUID) async throws {
        notes.removeValue(forKey: id)
    }

    /// Resolves a textual note reference to a matching note.
    /// - Parameters:
    ///   - reference: A string that may be empty, a UUID, or a search query; leading and trailing whitespace and newlines are ignored.
    /// - Returns: The matching `Note` if found, `nil` otherwise. If the trimmed `reference` is empty, returns the first note according to the repository's ordering. If the trimmed `reference` parses as a UUID and a note with that ID exists, that note is returned; otherwise the first note matching the trimmed query is returned.
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

    /// Produces up to `limit` ranked snippets for notes that match `query`.
    /// - Parameters:
    ///   - query: The search string; leading/trailing whitespace and newlines are ignored. An empty or all-whitespace `query` matches all notes.
    ///   - limit: The maximum number of snippets to return. If `limit` is less than or equal to zero, an empty array is returned.
    /// - Returns: An array of `NoteSnippet` values (up to `limit`) for notes matching `query`. Each snippet contains the note ID, display title, an excerpt computed for the query, the note's `updatedAt`, and a relevance `score`. The results are ordered by relevance and then by recency.
    func snippets(matching query: String, limit: Int) async throws -> [NoteSnippet] {
        guard limit > 0 else {
            return []
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return Array(
            filteredNotes(matching: trimmed.isEmpty ? nil : trimmed)
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
        )
    }

    /// Returns notes that match an optional search query, sorted by relevance (when a query is provided) or by pinned state and recency otherwise.
    /// - Parameters:
    ///   - query: Optional search string; if `nil` or empty after trimming whitespace and newlines, all notes are returned.
    /// - Returns: An array of `Note` objects matching the query (or all notes when no query). Empty-query results are grouped by pinned state, then ordered by most recently updated.
    private func filteredNotes(matching query: String?) -> [Note] {
        let allNotes = notes.values

        guard let trimmedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmedQuery.isEmpty else {
            return allNotes.sorted(by: defaultNoteSortPrecedes)
        }

        return allNotes
            .map { note in
                (
                    note,
                    NoteSearchRanking.score(
                        title: note.displayTitle,
                        body: note.body,
                        updatedAt: note.updatedAt,
                        query: trimmedQuery
                    )
                )
            }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 > rhs.1
                }
                return recencySortPrecedes(lhs.0, rhs.0)
            }
            .map(\.0)
    }

    /// Determines whether the left-hand note should precede the right-hand note in the default repository sort order.
    /// - Parameters:
    ///   - lhs: The left-hand note to compare.
    ///   - rhs: The right-hand note to compare.
    /// - Returns: `true` if `lhs` should come before `rhs`; pinned notes come first, then notes with a later `updatedAt`.
    private func defaultNoteSortPrecedes(_ lhs: Note, _ rhs: Note) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned
        }
        return recencySortPrecedes(lhs, rhs)
    }

    private func recencySortPrecedes(_ lhs: Note, _ rhs: Note) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString > rhs.id.uuidString
    }

    /// Produces a summary representation for the given note.
    /// - Parameter note: The note to summarize.
    /// - Returns: A `NoteSummary` containing the note's `id`, `displayTitle` as `title`, a preview of the note `body` as `previewText`, and the note's `updatedAt` timestamp.
    private func makeSummary(_ note: Note) -> NoteSummary {
        NoteSummary(
            id: note.id,
            title: note.displayTitle,
            previewText: NoteTextUtilities.preview(for: note.body),
            updatedAt: note.updatedAt,
            isPinned: note.isPinned
        )
    }
}

final class MockSpeechTranscriptionService: SpeechTranscriptionService, @unchecked Sendable {
    private let result: String

    init(result: String) {
        self.result = result
    }

    /// Provides the mock transcription result for a given audio file.
    /// - Returns: The preconfigured transcription string.
    func transcribeFile(at url: URL, locale: Locale) async throws -> String {
        result
    }
}

final class MockNoteCaptureIntelligenceService: NoteCaptureIntelligenceService, @unchecked Sendable {
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

    /// Refines the provided typed note and returns the mock's configured refinement result.
    /// - Parameters:
    ///   - title: The note title to refine.
    ///   - body: The note body to refine.
    ///   - locale: The locale context for the refinement.
    /// - Returns: The configured `NoteCaptureRefinement` result.
    /// - Throws: `CaptureIntelligenceError.unavailable` when the mock's `capabilityState` is `.unavailable(…)`.
    func refineTypedNote(title: String, body: String, locale: Locale) async throws -> NoteCaptureRefinement {
        if case let .unavailable(reason) = capabilityState {
            throw CaptureIntelligenceError.unavailable(reason)
        }
        return typedResult
    }

    /// Produces a refinement for a transcript using the service's configured result.
    /// - Returns: The configured `NoteCaptureRefinement` to use for the given transcript.
    /// - Throws: `CaptureIntelligenceError.unavailable` if `capabilityState` is `.unavailable` with an associated reason.
    func refineTranscript(title: String, transcript: String, locale: Locale) async throws -> NoteCaptureRefinement {
        if case let .unavailable(reason) = capabilityState {
            throw CaptureIntelligenceError.unavailable(reason)
        }
        return transcriptResult
    }
}

final class MockVoiceCaptureInterpretationService: VoiceCaptureInterpretationService, @unchecked Sendable {
    let capabilityState: AssistantCapabilityState
    private let result: VoiceCaptureInterpretation

    init(
        capabilityState: AssistantCapabilityState = .available,
        result: VoiceCaptureInterpretation
    ) {
        self.capabilityState = capabilityState
        self.result = result
    }

    /// Produces a voice-capture interpretation for the given transcript and locale.
    /// - Parameters:
    ///   - transcript: The transcribed text to interpret.
    ///   - locale: The locale to use when interpreting the transcript.
    /// - Returns: A `VoiceCaptureInterpretation` representing the interpretation of the transcript.
    /// - Throws: `VoiceCaptureInterpretationError.unavailable(reason)` if the service capability state is `.unavailable`.
    func interpret(transcript: String, locale: Locale) async throws -> VoiceCaptureInterpretation {
        if case let .unavailable(reason) = capabilityState {
            throw VoiceCaptureInterpretationError.unavailable(reason)
        }
        return result
    }
}

@MainActor
final class MockNotesAssistantService: NotesAssistantService {
    let capabilityState: AssistantCapabilityState
    private let response: NotesAssistantResponse

    init(capabilityState: AssistantCapabilityState, response: NotesAssistantResponse) {
        self.capabilityState = capabilityState
        self.response = response
    }

    /// Triggers preparatory work required before using the assistant service.
    ///
    /// In this mock implementation, the call is a no-op and performs no work.
    func prewarm() {}

    /// Resets the assistant's conversation state.
    ///
    /// In this mock implementation this is a no-op.
    func resetConversation() {}

    /// Processes the given assistant input and returns the configured response.
    /// - Parameters:
    ///   - input: The assistant input text to process.
    /// - Returns: The configured `NotesAssistantResponse`.
    /// - Throws: `NotesAssistantError.unavailable` when the service `capabilityState` is `.unavailable(reason)`.
    func process(_ input: String) async throws -> NotesAssistantResponse {
        if case let .unavailable(reason) = capabilityState {
            throw NotesAssistantError.unavailable(reason)
        }
        return response
    }
}

/// Creates a temporary audio file named `source.m4a` containing the UTF-8 bytes of `"placeholder audio"`.
/// - Returns: The file `URL` pointing to `source.m4a` inside a newly created temporary directory (named by a UUID) under `FileManager.default.temporaryDirectory`.
/// - Throws: Any file system error that occurs while creating the directory or writing the file.
func makeSourceAudioFile() throws -> URL {
    let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    let sourceURL = rootURL.appendingPathComponent("source.m4a")
    try Data("placeholder audio".utf8).write(to: sourceURL)
    return sourceURL
}
