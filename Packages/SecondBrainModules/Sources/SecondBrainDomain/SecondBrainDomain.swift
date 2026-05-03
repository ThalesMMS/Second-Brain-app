import Foundation

package enum SecondBrainSettings {
    package nonisolated static let appGroupIdentifier = "group.thalesmms.secondbrain"
    package nonisolated static let cloudKitContainerIdentifier = "iCloud.thalesmms.secondbrain"
    package nonisolated static let assistantContextLimit = 5
    package nonisolated static let untitledNoteTitle = "Untitled note"
}

public enum NoteMutationSource: String, Codable, CaseIterable, Sendable {
    case manual
    case siri
    case assistant
    case speechToText
    case watch
    case appIntent
}

public enum NoteEntryKind: String, Codable, CaseIterable, Sendable {
    case creation
    case append
    case replaceBody
    case transcription
    case assistantSummary
}

public struct NoteSummary: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var previewText: String
    public var updatedAt: Date
    public var isPinned: Bool

    public init(id: UUID, title: String, previewText: String, updatedAt: Date, isPinned: Bool = false) {
        self.id = id
        self.title = title
        self.previewText = previewText
        self.updatedAt = updatedAt
        self.isPinned = isPinned
    }

    public var displayTitle: String {
        NoteTextUtilities.derivedTitle(from: title, body: "")
    }
}

public struct NoteEntry: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let kind: NoteEntryKind
    public let source: NoteMutationSource
    public let text: String

    public init(id: UUID, createdAt: Date, kind: NoteEntryKind, source: NoteMutationSource, text: String) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.source = source
        self.text = text
    }
}

public struct NoteSnippet: Hashable, Sendable {
    public let noteID: UUID
    public let title: String
    public let excerpt: String
    public let updatedAt: Date
    public let score: Int

    public init(noteID: UUID, title: String, excerpt: String, updatedAt: Date, score: Int) {
        self.noteID = noteID
        self.title = title
        self.excerpt = excerpt
        self.updatedAt = updatedAt
        self.score = score
    }
}

public struct Note: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var body: String
    public var createdAt: Date
    public var updatedAt: Date
    public var entries: [NoteEntry]
    public var isPinned: Bool

    public init(
        id: UUID,
        title: String,
        body: String,
        createdAt: Date,
        updatedAt: Date,
        entries: [NoteEntry],
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.entries = entries
        self.isPinned = isPinned
    }

    public var displayTitle: String {
        NoteTextUtilities.derivedTitle(from: title, body: body)
    }

    public var previewText: String {
        NoteTextUtilities.preview(for: body)
    }
}

public enum NotesAssistantInteractionState: String, Codable, CaseIterable, Hashable, Sendable {
    case none
    case pendingEditConfirmation
}

public struct NotesAssistantResponse: Hashable, Sendable {
    public let text: String
    public let referencedNoteIDs: [UUID]
    public let interaction: NotesAssistantInteractionState

    public nonisolated init(
        text: String,
        referencedNoteIDs: [UUID],
        interaction: NotesAssistantInteractionState = .none
    ) {
        self.text = text
        self.referencedNoteIDs = referencedNoteIDs
        self.interaction = interaction
    }
}

public struct NoteCaptureRefinement: Hashable, Sendable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

public enum VoiceCaptureIntent: String, Codable, CaseIterable, Hashable, Sendable {
    case newNote
    case assistantCommand
    case unknown
}

public struct VoiceCaptureInterpretation: Hashable, Sendable {
    public let intent: VoiceCaptureIntent
    public let normalizedText: String

    public init(intent: VoiceCaptureIntent, normalizedText: String) {
        self.intent = intent
        self.normalizedText = normalizedText
    }
}

public enum VoiceCaptureResult: Hashable, Sendable {
    case createdNote(Note)
    case assistantResponse(NotesAssistantResponse, transcript: String)
}

package enum NoteEditScope: String, Codable, CaseIterable, Sendable {
    case title
    case excerpt
    case wholeBody
    case clarify
}

package struct NoteEditProposal: Hashable, Sendable {
    package let noteID: UUID
    package let scope: NoteEditScope
    package let updatedTitle: String
    package let updatedBody: String
    package let targetExcerpt: String?
    package let changeSummary: String
    package let clarificationQuestion: String?

    package init(
        noteID: UUID,
        scope: NoteEditScope,
        updatedTitle: String,
        updatedBody: String,
        targetExcerpt: String?,
        changeSummary: String,
        clarificationQuestion: String?
    ) {
        self.noteID = noteID
        self.scope = scope
        self.updatedTitle = updatedTitle
        self.updatedBody = updatedBody
        self.targetExcerpt = targetExcerpt
        self.changeSummary = changeSummary
        self.clarificationQuestion = clarificationQuestion
    }
}

package struct PendingNoteEdit: Hashable, Sendable {
    package let noteID: UUID
    package let baseUpdatedAt: Date
    package let proposal: NoteEditProposal

    package init(noteID: UUID, baseUpdatedAt: Date, proposal: NoteEditProposal) {
        self.noteID = noteID
        self.baseUpdatedAt = baseUpdatedAt
        self.proposal = proposal
    }
}

package enum PendingNoteEditDecision: String, Codable, CaseIterable, Sendable {
    case confirm
    case cancel
}

public enum AssistantCapabilityState: Equatable, Sendable {
    case available
    case unavailable(reason: String)
}

public enum NotesAssistantStatus: Equatable, Sendable {
    case reducedFunctionality(reason: String)
}

public struct RecordedAudio: Hashable, Sendable {
    public let temporaryFileURL: URL
    public let durationSeconds: TimeInterval

    public init(temporaryFileURL: URL, durationSeconds: TimeInterval) {
        self.temporaryFileURL = temporaryFileURL
        self.durationSeconds = durationSeconds
    }
}

public enum NoteRepositoryError: LocalizedError {
    case notFound
    case emptyContent
    case conflict

    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "The requested note could not be found."
        case .emptyContent:
            return "The note needs some text before it can be saved."
        case .conflict:
            return "The note changed before the update could be applied."
        }
    }
}

public enum AudioServiceError: LocalizedError {
    case permissionDenied
    case recordingUnavailable
    case transcriptionUnavailable
    case unsupportedLocale

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission was denied."
        case .recordingUnavailable:
            return "Audio recording is currently unavailable."
        case .transcriptionUnavailable:
            return "Speech transcription is unavailable on this device."
        case .unsupportedLocale:
            return "The selected language is not supported for on-device transcription."
        }
    }
}

public enum NotesAssistantError: LocalizedError {
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case let .unavailable(reason):
            return reason
        }
    }
}

public enum CaptureIntelligenceError: LocalizedError {
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case let .unavailable(reason):
            return reason
        }
    }
}

public enum VoiceCaptureInterpretationError: LocalizedError {
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case let .unavailable(reason):
            return reason
        }
    }
}

public protocol NoteRepository: AnyObject, Sendable {
    func listNotes(matching query: String?) async throws -> [NoteSummary]
    /// Returns a limited, picker-friendly slice of recent notes for App Intents entity suggestions.
    func pickerRecentNotes(limit: Int) async throws -> [NoteSummary]
    /// Returns a limited, picker-friendly slice of note matches for App Intents entity search.
    func searchNotes(matching query: String, limit: Int) async throws -> [NoteSummary]
    func loadNote(id: UUID) async throws -> Note?
    func createNote(title: String, body: String, source: NoteMutationSource, initialEntryKind: NoteEntryKind) async throws -> Note
    func appendText(_ text: String, to noteID: UUID, source: NoteMutationSource) async throws -> Note
    func replaceNote(
        id: UUID,
        title: String,
        body: String,
        source: NoteMutationSource,
        expectedUpdatedAt: Date?
    ) async throws -> Note
    func setPinned(id: UUID, isPinned: Bool) async throws
    func deleteNote(id: UUID) async throws
    /// Fallback free-form note resolution for assistant and voice-command flows.
    ///
    /// Siri/App Intents note selection should prefer entity-backed lookup instead of this fuzzy API.
    func resolveNoteReference(_ reference: String) async throws -> Note?
    func snippets(matching query: String, limit: Int) async throws -> [NoteSnippet]
}

public extension NoteRepository {
    func replaceNote(
        id: UUID,
        title: String,
        body: String,
        source: NoteMutationSource
    ) async throws -> Note {
        try await replaceNote(
            id: id,
            title: title,
            body: body,
            source: source,
            expectedUpdatedAt: nil
        )
    }
}

public protocol AudioFileStore: AnyObject {
    func makeTemporaryRecordingURL() throws -> URL
    func cleanupLegacyPersistedAudio()
}

@MainActor
public protocol AudioRecordingService: AnyObject {
    var isRecording: Bool { get }
    func requestPermission() async -> Bool
    func startRecording(to url: URL) throws
    func stopRecording() throws -> RecordedAudio
    func cancelRecording()
}

public protocol SpeechTranscriptionService: AnyObject, Sendable {
    func transcribeFile(at url: URL, locale: Locale) async throws -> String
}

@MainActor
public protocol TextToSpeechService: AnyObject {
    var isSpeaking: Bool { get }
    func speak(_ text: String, locale: Locale?)
    func stopSpeaking()
}

@MainActor
public protocol NotesAssistantService: AnyObject, Sendable {
    var capabilityState: AssistantCapabilityState { get }
    var status: NotesAssistantStatus? { get }
    func prewarm()
    func resetConversation()
    func process(_ input: String) async throws -> NotesAssistantResponse
}

public extension NotesAssistantService {
    var status: NotesAssistantStatus? { nil }
}

public protocol VoiceCaptureInterpretationService: AnyObject, Sendable {
    var capabilityState: AssistantCapabilityState { get }
    func interpret(transcript: String, locale: Locale) async throws -> VoiceCaptureInterpretation
}

public protocol NoteCaptureIntelligenceService: AnyObject, Sendable {
    var capabilityState: AssistantCapabilityState { get }
    func refineTypedNote(title: String, body: String, locale: Locale) async throws -> NoteCaptureRefinement
    func refineTranscript(title: String, transcript: String, locale: Locale) async throws -> NoteCaptureRefinement
}

package protocol NoteEditIntelligenceService: AnyObject, Sendable {
    var capabilityState: AssistantCapabilityState { get }
    func proposeEdit(
        noteID: UUID,
        title: String,
        body: String,
        instruction: String,
        locale: Locale
    ) async throws -> NoteEditProposal
}

package enum NoteTextUtilities {
    /// Derives a user-facing note title from an explicit title or the note body.
    /// - Parameters:
    ///   - explicitTitle: The user-provided title; may be empty or contain only whitespace.
    ///   - body: The note body used as a fallback when `explicitTitle` is empty.
    /// - Returns: The trimmed explicit title if nonempty; otherwise the first nonempty line of `body` truncated to 60 characters; if neither yields text, `SecondBrainSettings.untitledNoteTitle`.
    package static func derivedTitle(from explicitTitle: String, body: String) -> String {
        let cleanedTitle = explicitTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedTitle.isEmpty {
            return cleanedTitle
        }

        let firstLine = body
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !firstLine.isEmpty {
            return String(firstLine.prefix(60))
        }

        return SecondBrainSettings.untitledNoteTitle
    }

    /// Produces a single-line preview of a note body, suitable for lists or search results.
    /// - Parameters:
    ///   - body: The note text to produce a preview from.
    ///   - limit: The maximum number of characters in the preview (default is 140).
    /// - Returns: A trimmed, single-line preview of `body` up to `limit` characters; returns `"No text yet"` if `body` is empty. If the text is truncated, the preview ends with an ellipsis (`…`).
    package static func preview(for body: String, limit: Int = 140) -> String {
        let flattened = body
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !flattened.isEmpty else {
            return "No text yet"
        }

        if flattened.count <= limit {
            return flattened
        }

        let endIndex = flattened.index(flattened.startIndex, offsetBy: limit)
        return String(flattened[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    /// Appends `addition` to `base`, trimming surrounding whitespace and ensuring a paragraph separator.
    /// - Parameters:
    ///   - base: The original text to append to; leading/trailing whitespace and newlines are removed.
    ///   - addition: The text to append; leading/trailing whitespace and newlines are removed.
    /// - Returns: The combined text. If `addition` is empty after trimming, returns the trimmed `base`. If `base` is empty after trimming, returns the trimmed `addition`. Otherwise returns `trimmedBase + "\n\n" + trimmedAddition`.
    package static func append(base: String, addition: String) -> String {
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddition = addition.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedAddition.isEmpty else {
            return trimmedBase
        }

        guard !trimmedBase.isEmpty else {
            return trimmedAddition
        }

        return trimmedBase + "\n\n" + trimmedAddition
    }

    /// Creates a search-normalized string by combining a note's title and body.
    /// - Parameters:
    ///   - title: The note's title.
    ///   - body: The note's body text.
    /// - Returns: A string containing `title` and `body` joined by a newline and folded for diacritic- and case-insensitive comparisons using the current locale.
    package static func searchableText(title: String, body: String) -> String {
        [title, body]
            .joined(separator: "\n")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    /// Produce a case- and diacritic-insensitive, trimmed version of the input string.
    /// - Parameter text: The string to normalize.
    /// - Returns: The input string folded to remove diacritics and case differences using the current locale, then trimmed of leading and trailing whitespace and newlines.
    package static func normalized(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Produces a concise excerpt of `body` centered around the first occurrence of `query`.
    /// 
    /// If `body` is empty, returns an empty string. If a normalized `query` is not found in the normalized `body`, returns a preview of `body` up to `min(radius * 2, 180)` characters. When a match is found, returns a trimmed slice of the original `body` that includes `radius` characters of context on each side of the match (bounded by the body), and adds leading and/or trailing ellipses (`"…"`) if the slice does not include the respective body boundary.
    /// - Parameters:
    ///   - body: The full text to extract an excerpt from.
    ///   - query: The search string to locate within `body`.
    ///   - radius: Number of characters of context to include on each side of the matched query.
    /// - Returns: An excerpt string containing the matched region with contextual padding and ellipses as needed, an empty string if `body` is empty, or a preview when `query` is not found.
    package static func excerpt(for body: String, matching query: String, radius: Int = 80) -> String {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedBody.isEmpty else {
            return ""
        }

        guard !trimmedQuery.isEmpty,
              let range = body.range(
                of: trimmedQuery,
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
              ) else {
            return preview(for: body, limit: min(radius * 2, 180))
        }

        let distanceFromStart = body.distance(from: body.startIndex, to: range.lowerBound)
        let matchedLength = body.distance(from: range.lowerBound, to: range.upperBound)
        let originalScalars = Array(body)
        let startOffset = max(distanceFromStart - radius, 0)
        let endOffset = min(distanceFromStart + matchedLength + radius, originalScalars.count)
        let safeStart = min(startOffset, originalScalars.count)
        let safeEnd = min(endOffset, originalScalars.count)
        let slice = String(originalScalars[safeStart..<safeEnd]).trimmingCharacters(in: .whitespacesAndNewlines)

        if safeStart > 0, safeEnd < originalScalars.count {
            return "…" + slice + "…"
        } else if safeStart > 0 {
            return "…" + slice
        } else if safeEnd < originalScalars.count {
            return slice + "…"
        }
        return slice
    }
}

package enum NoteSearchRanking {
    /// Computes a relevance score for a note given a search query, combining text-match signals from the title and body with a recency bonus.
    /// - Parameters:
    ///   - updatedAt: The note's last modification date used to compute a recency-based score.
    ///   - query: The search query; matching is performed case- and diacritic-insensitively.
    /// Computes a relevance score for a note given a search query, combining title/body text-match signals with a recency boost.
    /// - Parameters:
    ///   - title: The note's title.
    ///   - body: The note's body text.
    ///   - updatedAt: The note's last-updated date used to compute the recency component.
    ///   - query: The search query; if empty, the result is the recency score.
    /// - Returns: An integer relevance score; `0` denotes no textual match, otherwise a positive value that combines textual relevance and recency.
    package static func score(title: String, body: String, updatedAt: Date, query: String) -> Int {
        let normalizedQuery = NoteTextUtilities.normalized(query)
        guard !normalizedQuery.isEmpty else {
            return recencyScore(updatedAt: updatedAt)
        }

        let normalizedTitle = NoteTextUtilities.normalized(title)
        let normalizedBody = NoteTextUtilities.normalized(body)

        var score = 0

        if normalizedTitle == normalizedQuery {
            score += 120
        }
        if normalizedTitle.hasPrefix(normalizedQuery) {
            score += 90
        }
        if normalizedTitle.contains(normalizedQuery) {
            score += 70
        }
        if normalizedBody.contains(normalizedQuery) {
            score += 50
        }

        let queryWords = normalizedQuery.split(separator: " ").map(String.init)
        for word in queryWords where word.count > 1 {
            if normalizedTitle.contains(word) {
                score += 8
            }
            if normalizedBody.contains(word) {
                score += 4
            }
        }

        guard score > 0 else {
            return 0
        }

        score += recencyScore(updatedAt: updatedAt)
        return score
    }

    private static func recencyScore(updatedAt: Date) -> Int {
        let age = Date().timeIntervalSince(updatedAt)
        switch age {
        case ..<86_400:
            return 10
        case ..<604_800:
            return 6
        case ..<2_592_000:
            return 3
        default:
            return 0
        }
    }
}

extension Array where Element == NoteSnippet {
    package var referencedNoteIDs: [UUID] {
        map(\.noteID)
    }
}
