import AppIntents
import Foundation
import SecondBrainComposition
import SecondBrainDomain

@MainActor
enum NoteIntentEnvironment {
    static var graph: () throws -> AppGraph = { try AppGraph.makeLive() }
}

struct NoteEntity: AppEntity, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Note")
    static let defaultQuery = NoteEntityQuery()
    private static let unavailableTitle = "Unavailable note"

    let id: UUID
    let title: String
    let previewText: String

    init(id: UUID, title: String, previewText: String) {
        self.id = id
        self.title = title
        self.previewText = previewText
    }

    init(summary: NoteSummary) {
        self.init(
            id: summary.id,
            title: summary.displayTitle,
            previewText: summary.previewText
        )
    }

    init(note: Note) {
        self.init(
            id: note.id,
            title: note.displayTitle,
            previewText: note.previewText
        )
    }

    init(tombstoneWithID id: UUID) {
        self.init(
            id: id,
            title: Self.unavailableTitle,
            previewText: ""
        )
    }

    var displayRepresentation: DisplayRepresentation {
        return DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: title)
        )
    }
}

struct NoteEntityQuery: EntityStringQuery {
    private let suggestedLimit = 10
    private let searchLimit = 10

    /// Loads note entities in the requested order, using tombstones for notes that no longer exist.
    /// - Parameters:
    ///   - identifiers: The note UUIDs to load.
    func entities(for identifiers: [UUID]) async throws -> [NoteEntity] {
        let graph = try await MainActor.run {
            try NoteIntentEnvironment.graph()
        }
        var loadedNotes: [Note?] = []
        loadedNotes.reserveCapacity(identifiers.count)

        for identifier in identifiers {
            loadedNotes.append(try await graph.loadNote.execute(id: identifier))
        }

        return zip(identifiers, loadedNotes).map { identifier, loadedNote in
            loadedNote.map(NoteEntity.init(note:)) ?? NoteEntity(tombstoneWithID: identifier)
        }
    }

    /// Returns recent note entities for intent suggestions.
    func suggestedEntities() async throws -> [NoteEntity] {
        let graph = try await MainActor.run {
            try NoteIntentEnvironment.graph()
        }
        let summaries = try await graph.repository.pickerRecentNotes(limit: suggestedLimit)

        return summaries.map(NoteEntity.init(summary:))
    }

    /// Searches for note entities matching the query, or returns suggestions when the query is empty.
    /// - Parameter string: The query string to match against notes; leading/trailing whitespace and newlines are ignored.
    func entities(matching string: String) async throws -> [NoteEntity] {
        let trimmedQuery = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            return try await suggestedEntities()
        }

        let graph = try await MainActor.run {
            try NoteIntentEnvironment.graph()
        }
        let summaries = try await graph.repository.searchNotes(matching: trimmedQuery, limit: searchLimit)

        return summaries.map(NoteEntity.init(summary:))
    }
}

struct CreateNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Note"
    static let description = IntentDescription("Create a new note in Second Brain.")
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    static var openAppWhenRun = false

    @Parameter(title: "Title")
    var titleText: String?

    @Parameter(title: "Body")
    var bodyText: String

    /// Creates a note and returns a confirmation dialog with its display title.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let note = try await NoteIntentEnvironment.graph().createNote.execute(
            title: titleText ?? "",
            body: bodyText,
            source: .appIntent
        )
        return .result(dialog: IntentDialog("Created note \(note.displayTitle)."))
    }
}

struct AppendToNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Append To Note"
    static let description = IntentDescription("Append text to an existing note.")
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    static var openAppWhenRun = false

    @Parameter(title: "Note")
    var note: NoteEntity

    @Parameter(title: "Content")
    var content: String

    /// Appends content to a note and reports whether the update succeeded, was empty, or targeted a missing note.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            return .result(dialog: IntentDialog("No changes; nothing to append."))
        }

        do {
            let updatedNote = try await NoteIntentEnvironment.graph().appendToNote.execute(
                noteID: note.id,
                text: trimmedContent,
                source: .appIntent
            )
            return .result(dialog: IntentDialog("Updated note \(updatedNote.displayTitle)."))
        } catch NoteRepositoryError.notFound {
            return .result(dialog: IntentDialog("That note is no longer available."))
        }
    }
}

struct ReadNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Read Note"
    static let description = IntentDescription("Read the contents of a note.")
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    static var openAppWhenRun = false

    @Parameter(title: "Note")
    var note: NoteEntity

    /// Reads a note and returns its body, an empty-note message, or an unavailable-note message.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let graph = try NoteIntentEnvironment.graph()
        guard let loadedNote = try await graph.loadNote.execute(id: note.id) else {
            return .result(dialog: IntentDialog("That note is no longer available."))
        }

        let spokenBody = loadedNote.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let response = spokenBody.isEmpty ? "The note \(loadedNote.displayTitle) is currently empty." : spokenBody
        return .result(dialog: IntentDialog(stringLiteral: response))
    }
}

struct AskNotesIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Notes"
    static let description = IntentDescription("Ask a question based on your notes.")
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    static var openAppWhenRun = false

    @Parameter(title: "Question")
    var question: String

    /// Asks the notes assistant a question and returns the assistant response as dialog text.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let response = try await NoteIntentEnvironment.graph().askNotes.execute(question)
        return .result(dialog: IntentDialog(stringLiteral: response.text))
    }
}

struct SecondBrainAppShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .purple

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateNoteIntent(),
            phrases: [
                "Create a note in \(.applicationName)",
                "Save a note in \(.applicationName)",
            ],
            shortTitle: "Create Note",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: AppendToNoteIntent(),
            phrases: [
                "Append to a note in \(.applicationName)",
                "Add information to a note in \(.applicationName)",
            ],
            shortTitle: "Append Note",
            systemImageName: "text.append"
        )
        AppShortcut(
            intent: ReadNoteIntent(),
            phrases: [
                "Read a note in \(.applicationName)",
                "Read my note from \(.applicationName)",
            ],
            shortTitle: "Read Note",
            systemImageName: "text.book.closed"
        )
        AppShortcut(
            intent: AskNotesIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Question my notes in \(.applicationName)",
            ],
            shortTitle: "Ask Notes",
            systemImageName: "sparkles"
        )
    }
}
