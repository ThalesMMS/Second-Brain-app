import Foundation
import SecondBrainDomain
import SwiftData

package struct SeededNoteEntryData: Sendable {
    package let id: UUID
    package let createdAt: Date
    package let kind: NoteEntryKind
    package let source: NoteMutationSource
    package let text: String

    package init(
        id: UUID,
        createdAt: Date,
        kind: NoteEntryKind,
        source: NoteMutationSource,
        text: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.source = source
        self.text = text
    }
}

package struct SeededNoteData: Sendable {
    package let id: UUID
    package let title: String
    package let body: String
    package let createdAt: Date
    package let updatedAt: Date
    package let entries: [SeededNoteEntryData]

    package init(
        id: UUID,
        title: String,
        body: String,
        createdAt: Date,
        updatedAt: Date,
        entries: [SeededNoteEntryData]
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.entries = entries
    }
}

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
package final class PersistenceController {
    package let container: ModelContainer
    package let repository: SwiftDataNoteRepository

    package convenience init(
        inMemory: Bool = false,
        enableCloudSync: Bool = true,
        useSharedContainer: Bool = true
    ) throws {
        let configuration = try Self.makeConfiguration(
            inMemory: inMemory,
            enableCloudSync: enableCloudSync,
            useSharedContainer: useSharedContainer
        )
        try self.init(configuration: configuration)
    }

    package init(configuration: ModelConfiguration) throws {
        container = try Self.makeContainer(configuration: configuration)
        repository = SwiftDataNoteRepository(modelContainer: container)
    }

    /// Creates a `ModelContainer` configured with the app's versioned schema and migration plan.
    /// - Parameter configuration: The `ModelConfiguration` that supplies store URL, cloud settings, and related options.
    /// - Returns: A `ModelContainer` instance bound to `SecondBrainSchemaV4` and `SecondBrainMigrationPlan`.
    /// - Throws: Any error encountered while constructing the `ModelContainer`.
    private static func makeContainer(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: SecondBrainSchemaV4.self),
            migrationPlan: SecondBrainMigrationPlan.self,
            configurations: configuration
        )
    }

    private static func makeConfiguration(
        inMemory: Bool,
        enableCloudSync: Bool,
        useSharedContainer: Bool,
        fileManager: FileManager = .default
    ) throws -> ModelConfiguration {
        if inMemory {
            return ModelConfiguration(isStoredInMemoryOnly: true)
        }

        let configuration = ModelConfiguration(
            url: resolvedStoreURL(fileManager: fileManager, useSharedContainer: useSharedContainer),
            cloudKitDatabase: enableCloudSync ? .automatic : .none
        )

        try prepareStoreDirectory(for: configuration, fileManager: fileManager)
        return configuration
    }

    static func resolvedStoreURL(fileManager: FileManager = .default, useSharedContainer: Bool = true) -> URL {
        guard useSharedContainer else {
            return defaultStoreURL(fileManager: fileManager)
        }

        return resolvedStoreURL(
            fileManager: fileManager,
            appGroupContainerURL: fileManager.containerURL(
                forSecurityApplicationGroupIdentifier: SecondBrainSettings.appGroupIdentifier
            )
        )
    }

    static func resolvedStoreURL(fileManager: FileManager = .default, appGroupContainerURL: URL?) -> URL {
        if let appGroupContainerURL {
            return appGroupStoreURL(for: appGroupContainerURL)
        }

        return defaultStoreURL(fileManager: fileManager)
    }

    static func appGroupStoreURL(for appGroupContainerURL: URL) -> URL {
        appGroupContainerURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("default.store")
    }

    /// Constructs the default SwiftData store file URL inside the app's Application Support directory.
    /// - Returns: A `URL` pointing to "default.store" located in the user's Application Support directory.
    static func defaultStoreURL(fileManager: FileManager = .default) -> URL {
        fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("default.store")
    }

    /// Ensures the parent directory for the configuration's store URL exists.
    ///
    /// This is a no-op when `configuration.isStoredInMemoryOnly` is `true` or when the directory already exists.
    /// - Parameters:
    ///   - configuration: The model configuration whose store URL determines the directory to create.
    ///   - fileManager: The file manager used to check for and create the directory. Defaults to `.default`.
    /// - Throws: An error from `FileManager.createDirectory(at:withIntermediateDirectories:attributes:)` if the directory cannot be created.
    static func prepareStoreDirectory(for configuration: ModelConfiguration, fileManager: FileManager = .default) throws {
        guard !configuration.isStoredInMemoryOnly else {
            return
        }

        let directoryURL = configuration.url.deletingLastPathComponent()
        guard !fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
    }

    /// Inserts seeded notes and entries into a fresh `ModelContext` for UI testing.
    ///
    /// Inserts each `SeededNoteData` as a `NoteRecord`, computes `searchableText`, inserts each `SeededNoteEntryData`
    /// as a `NoteEntryRecord`, and then saves the context.
    /// - Parameters:
    ///   - notes: An array of seeded note data to insert; each item may include multiple seeded entries.
    /// - Throws: An error from `ModelContext.save()` if persisting the inserted records fails.
    package func seedForUITests(_ notes: [SeededNoteData]) throws {
        guard !notes.isEmpty else {
            return
        }

        let context = ModelContext(container)
        for note in notes {
            let record = NoteRecord(
                id: note.id,
                title: note.title,
                bodyText: note.body,
                searchableText: NoteTextUtilities.searchableText(title: note.title, body: note.body),
                createdAt: note.createdAt,
                updatedAt: note.updatedAt
            )
            for entry in note.entries {
                let entryRecord = NoteEntryRecord(
                    id: entry.id,
                    createdAt: entry.createdAt,
                    kindRawValue: entry.kind.rawValue,
                    sourceRawValue: entry.source.rawValue,
                    text: entry.text,
                    note: record
                )
                record.entries.append(entryRecord)
            }
            context.insert(record)
        }
        try context.save()
    }
}

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
package actor SwiftDataNoteRepository: NoteRepository {
    private let modelContainer: ModelContainer
    private var cachedModelContext: ModelContext?

    package init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    /// Lists note summaries that match an optional search query.
    /// - Parameters:
    ///   - query: An optional raw query string. If `nil` or empty after normalization, the method returns all notes.
    /// - Returns: An array of `NoteSummary` objects. If `query` is `nil` or empty, returns all notes grouped by pinned state then sorted by `updatedAt` descending; otherwise returns summaries of notes matched and ranked by relevance to the normalized query.
    package func listNotes(matching query: String?) async throws -> [NoteSummary] {
        let normalizedQuery = query.map(NoteTextUtilities.normalized)
        guard let normalizedQuery, !normalizedQuery.isEmpty else {
            return try fetchAllNotes().map(Self.makeSummary)
        }

        let candidates = try fetchCandidateNotes(matching: normalizedQuery)
        return rankRecords(candidates, query: normalizedQuery).map(Self.makeSummary)
    }

    /// Fetches summaries for the pinned-first recent notes, limited to the specified count.
    /// - Parameter limit: Maximum number of summaries to return. If `limit` is less than or equal to zero, an empty array is returned.
    /// - Returns: An array of `NoteSummary` grouped by pinned state then recency, containing at most `limit` items; returns an empty array when `limit` <= 0.
    package func pickerRecentNotes(limit: Int) async throws -> [NoteSummary] {
        guard limit > 0 else {
            return []
        }

        return try fetchRecentNotes(limit: limit).map(Self.makeSummary)
    }

    /// Searches for notes matching the provided query and returns up to `limit` summaries.
    /// 
    /// The `query` is normalized before matching; if the normalized query is empty, the most recent notes are returned instead.
    /// - Parameters:
    ///   - query: The search text to match against notes (will be normalized).
    ///   - limit: The maximum number of summaries to return. If `limit` is less than or equal to zero, an empty array is returned.
    /// - Returns: An array of `NoteSummary` objects matching the query, containing at most `limit` items.
    package func searchNotes(matching query: String, limit: Int) async throws -> [NoteSummary] {
        guard limit > 0 else {
            return []
        }

        let normalizedQuery = NoteTextUtilities.normalized(query)
        guard !normalizedQuery.isEmpty else {
            return try await pickerRecentNotes(limit: limit)
        }

        return Array(try await listNotes(matching: normalizedQuery).prefix(limit))
    }

    /// Fetches the note record with the specified identifier and returns it as a domain `Note`.
    /// - Parameter id: The note identifier to load.
    /// - Returns: The mapped `Note` for the given identifier, or `nil` if no record exists.
    package func loadNote(id: UUID) async throws -> Note? {
        try fetchRecord(id: id).map(Self.makeNote)
    }

    /// Creates and persists a new note with the provided title and body, recording an initial entry.
    /// - Parameters:
    ///   - title: The note's title. If empty or whitespace, a title will be derived from `body`.
    ///   - body: The note's body text.
    ///   - source: The origin of this mutation.
    ///   - initialEntryKind: The kind assigned to the initial note entry.
    /// - Returns: The newly created `Note`.
    /// - Throws: `NoteRepositoryError.emptyContent` if both `title` and `body` are empty or whitespace.
    /// - Throws: Any error that occurs while saving the note to persistent storage.
    package func createNote(
        title: String,
        body: String,
        source: NoteMutationSource,
        initialEntryKind: NoteEntryKind
    ) async throws -> Note {
        let cleanedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedTitle = NoteTextUtilities.derivedTitle(from: title, body: cleanedBody)

        if cleanedBody.isEmpty, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw NoteRepositoryError.emptyContent
        }

        let now = Date()
        let note = NoteRecord(
            title: cleanedTitle,
            bodyText: cleanedBody,
            searchableText: NoteTextUtilities.searchableText(title: cleanedTitle, body: cleanedBody),
            createdAt: now,
            updatedAt: now,
            isPinned: false
        )
        let entry = makeEntry(
            kind: initialEntryKind,
            source: source,
            text: cleanedBody.isEmpty ? cleanedTitle : cleanedBody,
            createdAt: now,
            note: note
        )
        note.entries.append(entry)
        modelContext().insert(note)
        try saveIfNeeded()
        return Self.makeNote(note)
    }

    /// Appends the provided text to the body of the note identified by `noteID`, records an append entry, updates timestamps and searchable text, persists changes, and returns the resulting note.
    /// - Parameters:
    ///   - text: The text to append; leading and trailing whitespace/newlines are trimmed before appending.
    ///   - noteID: The identifier of the note to update.
    ///   - source: The origin of this mutation (used for the created entry's metadata).
    /// - Returns: The `Note` reflecting the appended text and updated metadata; if `text` trims to an empty string, returns the existing note unchanged.
    /// - Throws: `NoteRepositoryError.notFound` if no note exists with `noteID`, or any error produced while saving changes.
    package func appendText(_ text: String, to noteID: UUID, source: NoteMutationSource) async throws -> Note {
        guard let note = try fetchRecord(id: noteID) else {
            throw NoteRepositoryError.notFound
        }

        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty else {
            return Self.makeNote(note)
        }

        let now = Date()
        note.bodyText = NoteTextUtilities.append(base: note.bodyText, addition: cleanedText)
        note.title = NoteTextUtilities.derivedTitle(from: note.title, body: note.bodyText)
        note.updatedAt = now
        note.searchableText = NoteTextUtilities.searchableText(title: note.title, body: note.bodyText)
        note.entries.append(makeEntry(kind: .append, source: source, text: cleanedText, createdAt: now, note: note))
        try saveIfNeeded()
        return Self.makeNote(note)
    }

    /// Replaces the title and body of an existing note, appends a `replaceBody` entry, and persists the change.
    /// - Returns: The updated `Note` reflecting the new title, body, entries, and timestamps.
    /// - Throws: `NoteRepositoryError.notFound` if no note exists with the provided `id`.
    package func replaceNote(
        id: UUID,
        title: String,
        body: String,
        source: NoteMutationSource,
        expectedUpdatedAt: Date?
    ) async throws -> Note {
        guard let note = try fetchRecord(id: id) else {
            throw NoteRepositoryError.notFound
        }
        if let expectedUpdatedAt, note.updatedAt != expectedUpdatedAt {
            throw NoteRepositoryError.conflict
        }

        let cleanedTitle = NoteTextUtilities.derivedTitle(from: title, body: body)
        let cleanedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()

        note.title = cleanedTitle
        note.bodyText = cleanedBody
        note.updatedAt = now
        note.searchableText = NoteTextUtilities.searchableText(title: cleanedTitle, body: cleanedBody)
        note.entries.append(makeEntry(kind: .replaceBody, source: source, text: cleanedBody, createdAt: now, note: note))
        try saveIfNeeded()
        return Self.makeNote(note)
    }

    /// Updates only the pinned state of an existing note.
    /// - Throws: `NoteRepositoryError.notFound` if no note exists with the provided `id`.
    package func setPinned(id: UUID, isPinned: Bool) async throws {
        guard let note = try fetchRecord(id: id) else {
            throw NoteRepositoryError.notFound
        }

        note.isPinned = isPinned
        try saveIfNeeded()
    }

    /// Deletes the note with the specified identifier if it exists.
    ///
    /// If no note with the given identifier exists, the call returns without error.
    /// - Throws: Any underlying persistence error encountered while fetching the record or saving changes.
    package func deleteNote(id: UUID) async throws {
        guard let note = try fetchRecord(id: id) else {
            return
        }

        modelContext().delete(note)
        try saveIfNeeded()
    }

    /// Resolves a user-supplied note reference into the corresponding `Note`.
    /// - Parameter reference: A string provided by the user; leading and trailing whitespace and newlines are ignored. The string may be a UUID identifying a note or free-form text used to find a matching note.
    /// - Returns: The resolved `Note` if a match is found, `nil` otherwise. An empty or whitespace-only `reference` yields the most recently updated note. Matching preference is: exact UUID, exact title, title prefix, then the highest-ranked candidate.
    package func resolveNoteReference(_ reference: String) async throws -> Note? {
        let trimmedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReference.isEmpty else {
            return try fetchMostRecentNote().map(Self.makeNote)
        }

        if let uuid = UUID(uuidString: trimmedReference),
           let exact = try fetchRecord(id: uuid) {
            return Self.makeNote(exact)
        }

        let normalizedReference = NoteTextUtilities.normalized(trimmedReference)
        guard !normalizedReference.isEmpty else {
            return try fetchMostRecentNote().map(Self.makeNote)
        }

        let candidates = try fetchCandidateNotes(matching: normalizedReference)

        if let exactTitleMatch = candidates.first(where: { NoteTextUtilities.normalized($0.title) == normalizedReference }) {
            return Self.makeNote(exactTitleMatch)
        }

        if let prefixTitleMatch = candidates.first(where: { NoteTextUtilities.normalized($0.title).hasPrefix(normalizedReference) }) {
            return Self.makeNote(prefixTitleMatch)
        }

        return rankRecords(candidates, query: normalizedReference).first.map(Self.makeNote)
    }

    /// Produces ranked snippets from notes that match a search query.
    ///
    /// When `query` is empty (after normalization), snippets are generated from recent notes using `fetchRecentNotes(limit:)`; otherwise candidates are prefiltered and ranked. Values less than or equal to zero return an empty array. Results are sorted by descending relevance score then by most recent `updatedAt`, and limited to `limit` items.
    /// - Parameters:
    ///   - query: The search text; normalized before matching and excerpt generation.
    ///   - limit: The maximum number of snippets to return; values less than or equal to zero result in an empty array.
    /// - Returns: An array of `NoteSnippet` objects containing `noteID`, `title`, `excerpt`, `updatedAt`, and `score`, with at most `limit` entries.
    package func snippets(matching query: String, limit: Int) async throws -> [NoteSnippet] {
        guard limit > 0 else {
            return []
        }

        let normalizedQuery = NoteTextUtilities.normalized(query)
        let notes = if normalizedQuery.isEmpty {
            try fetchRecentNotes(limit: limit)
        } else {
            try fetchCandidateNotes(matching: normalizedQuery)
        }

        return notes
            .map { note in
                NoteSnippet(
                    noteID: note.id,
                    title: note.title,
                    excerpt: NoteTextUtilities.excerpt(for: note.bodyText, matching: normalizedQuery),
                    updatedAt: note.updatedAt,
                    score: NoteSearchRanking.score(
                        title: note.title,
                        body: note.bodyText,
                        updatedAt: note.updatedAt,
                        query: normalizedQuery
                    )
                )
            }
            .filter { normalizedQuery.isEmpty ? true : $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return lhs.updatedAt > rhs.updatedAt
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Fetches all stored `NoteRecord` instances ordered by pinned state, then most recent `updatedAt` first.
    /// - Returns: An array of `NoteRecord` sorted by `isPinned` descending, then `updatedAt` descending.
    /// - Throws: If the underlying model context fetch fails.
    private func fetchAllNotes() throws -> [NoteRecord] {
        let descriptor = FetchDescriptor<NoteRecord>(
            sortBy: [
                SortDescriptor(\.updatedAt, order: .reverse)
            ]
        )
        return try modelContext().fetch(descriptor).sorted(by: Self.noteSortPrecedes)
    }

    /// Fetches up to `limit` recent `NoteRecord` values sorted by pinned state, then `updatedAt` descending.
    /// - Parameters:
    ///   - limit: The maximum number of records to return.
    /// - Returns: An array of `NoteRecord` sorted by `isPinned` descending, then `updatedAt` descending.
    private func fetchRecentNotes(limit: Int) throws -> [NoteRecord] {
        let descriptor = FetchDescriptor<NoteRecord>(
            sortBy: [
                SortDescriptor(\.updatedAt, order: .reverse)
            ]
        )
        return Array(try modelContext().fetch(descriptor).sorted(by: Self.noteSortPrecedes).prefix(limit))
    }

    /// Fetches the most recently updated note record, if any.
    /// - Returns: The most recently updated `NoteRecord`, or `nil` if no records are available.
    /// - Throws: Any error thrown while fetching the record.
    private func fetchMostRecentNote() throws -> NoteRecord? {
        var descriptor = FetchDescriptor<NoteRecord>(
            sortBy: [
                SortDescriptor(\.updatedAt, order: .reverse)
            ]
        )
        descriptor.fetchLimit = 1
        return try modelContext().fetch(descriptor).first
    }

    /// Fetches a single `NoteRecord` with the given identifier.
    /// - Parameters:
    ///   - id: The `UUID` of the note to fetch.
    /// - Returns: The matching `NoteRecord` if found, `nil` otherwise.
    /// - Throws: If the underlying model context fetch fails.
    private func fetchRecord(id: UUID) throws -> NoteRecord? {
        var descriptor = FetchDescriptor<NoteRecord>(
            predicate: #Predicate<NoteRecord> { note in
                note.id == id
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext().fetch(descriptor).first
    }

    /// Produces a deduplicated list of candidate notes that match any search term derived from the provided normalized query, ordered by most recently updated first.
    /// - Parameter normalizedQuery: A normalized search string used to derive search terms for prefiltering records.
    /// - Returns: An array of `NoteRecord` instances whose `searchableText` matches at least one derived term, deduplicated by `id` and sorted by `updatedAt` descending.
    private func fetchCandidateNotes(matching normalizedQuery: String) throws -> [NoteRecord] {
        // Current scaling strategy: prefilter in SwiftData using normalized search text,
        // then apply the existing in-memory ranking rules to the smaller candidate pool.
        var deduplicatedRecords: [UUID: NoteRecord] = [:]

        for term in Self.searchTerms(for: normalizedQuery) {
            for record in try fetchRecords(containing: term) {
                deduplicatedRecords[record.id] = record
            }
        }

        return deduplicatedRecords.values.sorted { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }
    }

    /// Fetches note records whose `searchableText` contains the given term, ordered by `updatedAt` descending.
    /// - Parameter term: The search term to match within each record's `searchableText`.
    /// - Returns: An array of matching `NoteRecord` objects sorted with the most recently updated first.
    private func fetchRecords(containing term: String) throws -> [NoteRecord] {
        var descriptor = FetchDescriptor<NoteRecord>(
            predicate: #Predicate<NoteRecord> { note in
                note.searchableText.contains(term)
            },
            sortBy: [
                SortDescriptor(\.updatedAt, order: .reverse)
            ]
        )
        descriptor.includePendingChanges = true
        return try modelContext().fetch(descriptor)
    }

    /// Ranks and filters note records by relevance to a search query.
    /// - Parameters:
    ///   - notes: Candidate note records to evaluate.
    ///   - query: The normalized search query used to compute relevance scores.
    /// - Returns: The subset of `notes` with positive relevance scores, ordered by descending relevance then by most recent update.
    private func rankRecords(_ notes: [NoteRecord], query: String) -> [NoteRecord] {
        notes
            .map { note in
                (
                    note,
                    NoteSearchRanking.score(
                        title: note.title,
                        body: note.bodyText,
                        updatedAt: note.updatedAt,
                        query: query
                    )
                )
            }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 > rhs.1
                }
                return lhs.0.updatedAt > rhs.0.updatedAt
            }
            .map(\.0)
    }

    /// Creates a `NoteEntryRecord` representing a single note entry and associates it with the given note.
    /// - Parameters:
    ///   - kind: The entry kind to store (converted to the record's raw value).
    ///   - source: The origin of the mutation (converted to the record's raw value).
    ///   - text: The entry text content.
    ///   - createdAt: The creation timestamp to record on the entry.
    ///   - note: The `NoteRecord` to which the new entry will be attached.
    /// - Returns: A new `NoteEntryRecord` initialized with the provided values and linked to `note`.
    private func makeEntry(
        kind: NoteEntryKind,
        source: NoteMutationSource,
        text: String,
        createdAt: Date,
        note: NoteRecord
    ) -> NoteEntryRecord {
        NoteEntryRecord(
            createdAt: createdAt,
            kindRawValue: kind.rawValue,
            sourceRawValue: source.rawValue,
            text: text,
            note: note
        )
    }

    /// Saves the cached `ModelContext` only when there are pending changes.
    /// - Throws: Any error produced by `ModelContext.save()` if persisting changes fails.
    private func saveIfNeeded() throws {
        let modelContext = modelContext()

        guard modelContext.hasChanges else {
            return
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            cachedModelContext = nil
            throw error
        }
    }

    /// Returns the repository's cached `ModelContext`, creating one with `autosaveEnabled = false` when needed.
    /// - Returns: The `ModelContext` instance cached by the repository.
    private func modelContext() -> ModelContext {
        if let cachedModelContext {
            return cachedModelContext
        }

        let modelContext = ModelContext(modelContainer)
        modelContext.autosaveEnabled = false
        cachedModelContext = modelContext
        return modelContext
    }

    /// Builds an ordered list of search terms derived from a normalized query string.
    /// - Parameter normalizedQuery: The normalized query string to derive search terms from.
    /// - Returns: An array containing the full query first, then each distinct multi-character word in order.
    private static func searchTerms(for normalizedQuery: String) -> [String] {
        var terms: [String] = []

        if !normalizedQuery.isEmpty {
            terms.append(normalizedQuery)
        }

        for word in normalizedQuery.split(separator: " ").map(String.init) where word.count > 1 {
            if !terms.contains(word) {
                terms.append(word)
            }
        }

        return terms
    }

    private static func noteSortPrecedes(_ lhs: NoteRecord, _ rhs: NoteRecord) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString > rhs.id.uuidString
    }

    /// Creates a `NoteSummary` representing the given `NoteRecord`.
    /// - Parameter record: The source `NoteRecord` to convert.
    /// - Returns: A `NoteSummary` containing the record's `id`, a derived `title`, a preview of the body, and `updatedAt`.
    private static func makeSummary(_ record: NoteRecord) -> NoteSummary {
        NoteSummary(
            id: record.id,
            title: NoteTextUtilities.derivedTitle(from: record.title, body: record.bodyText),
            previewText: NoteTextUtilities.preview(for: record.bodyText),
            updatedAt: record.updatedAt,
            isPinned: record.isPinned
        )
    }

    /// Builds a `Note` value from a `NoteRecord`.
    /// - Parameters:
    ///   - record: The persisted `NoteRecord` to convert.
    /// - Returns: A `Note` populated with the record's `id`, `title`, `bodyText`, timestamps, and entries converted to `NoteEntry` values sorted by `createdAt` ascending.
    private static func makeNote(_ record: NoteRecord) -> Note {
        Note(
            id: record.id,
            title: record.title,
            body: record.bodyText,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            entries: record.entries
                .sorted(by: { $0.createdAt < $1.createdAt })
                .map(makeEntry),
            isPinned: record.isPinned
        )
    }

    /// Creates a `NoteEntry` value from a persisted `NoteEntryRecord`.
    /// - Parameter record: The stored entry record whose fields are copied; raw enum values are mapped back to `NoteEntryKind` and `NoteMutationSource` with fallbacks (`.append` and `.manual`) if mapping fails.
    /// - Returns: A `NoteEntry` populated with `id`, `createdAt`, `kind`, `source`, and `text` from the record.
    private static func makeEntry(_ record: NoteEntryRecord) -> NoteEntry {
        NoteEntry(
            id: record.id,
            createdAt: record.createdAt,
            kind: NoteEntryKind(rawValue: record.kindRawValue) ?? .append,
            source: NoteMutationSource(rawValue: record.sourceRawValue) ?? .manual,
            text: record.text
        )
    }
}
