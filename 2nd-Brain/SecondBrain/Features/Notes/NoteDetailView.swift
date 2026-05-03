import SwiftUI
import Observation
import SecondBrainComposition
import SecondBrainDomain
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
@Observable
final class NoteDetailViewModel {
    let noteID: UUID
    private let graph: AppGraph

    enum ViewState: Equatable {
        case idle
        case loading
        case loaded(Note)
        case conflict(message: String, note: Note?)
        case error(message: String, note: Note?)

        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }

        var note: Note? {
            switch self {
            case .loaded(let note):
                return note
            case .conflict(_, let note), .error(_, let note):
                return note
            case .idle, .loading:
                return nil
            }
        }

        var errorMessage: String? {
            get {
                if case .error(let message, _) = self { return message }
                return nil
            }
            set {
                if let newValue {
                    self = .error(message: newValue, note: note)
                } else if case .error = self {
                    self = note.map { .loaded($0) } ?? .idle
                }
            }
        }

        var conflictMessage: String? {
            if case .conflict(let message, _) = self { return message }
            return nil
        }
    }

    var state: ViewState = .idle

    var note: Note? {
        get { state.note }
        set {
            if let newValue {
                state = .loaded(newValue)
            } else {
                if state.isLoading { return }
                state = .idle
            }
        }
    }

    var draftTitle = ""
    var draftBody = ""
    var isSaving = false
    var isTogglingPinned = false

    var isLoading: Bool { state.isLoading }
    var errorMessage: String? {
        get { state.errorMessage }
        set { state.errorMessage = newValue }
    }
    var conflictMessage: String? { state.conflictMessage }
    var hasUnsavedChanges: Bool {
        draftTitle != lastAutosavedTitle || draftBody != lastAutosavedBody
    }

    private var autosaveTask: Task<Void, Never>?
    private var lastAutosavedTitle = ""
    private var lastAutosavedBody = ""
    private var lastSeenUpdatedAt: Date?

    init(noteID: UUID, graph: AppGraph) {
        self.noteID = noteID
        self.graph = graph
    }

    /// Loads the note and refreshes the editable draft state.
    func load(preservingUnsavedDrafts: Bool = true) async {
        let currentNote = note
        let shouldPreserveDrafts = preservingUnsavedDrafts && hasUnsavedChanges
        state = .loading

        do {
            let loaded = try await graph.loadNote.execute(id: noteID)
            guard let loaded else {
                state = .error(message: "The selected note could not be loaded.", note: currentNote)
                return
            }

            state = .loaded(loaded)
            lastSeenUpdatedAt = loaded.updatedAt
            if !shouldPreserveDrafts {
                draftTitle = loaded.title
                draftBody = loaded.body
                lastAutosavedTitle = loaded.title
                lastAutosavedBody = loaded.body
            }
        } catch {
            state = .error(message: error.localizedDescription, note: currentNote)
        }
    }

    /// Saves the current draft back to the loaded note.
    func save() async {
        await saveImpl(reason: "manual")
    }

    func retryAfterError() async {
        if hasUnsavedChanges, note != nil {
            await save()
        } else {
            await load()
        }
    }

    private func saveImpl(reason: String) async {
        guard let note else {
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let saved = try await graph.saveNote.execute(
                noteID: note.id,
                title: draftTitle,
                body: draftBody,
                lastSeenUpdatedAt: lastSeenUpdatedAt ?? note.updatedAt,
                source: .manual
            )
            self.note = saved
            lastAutosavedTitle = draftTitle
            lastAutosavedBody = draftBody
            lastSeenUpdatedAt = saved.updatedAt
        } catch let repoError as NoteRepositoryError {
            switch repoError {
            case .conflict:
                state = .conflict(
                    message: "This note was changed elsewhere. Reload the latest version or keep editing and try saving again.",
                    note: note
                )
            default:
                state = .error(message: repoError.localizedDescription, note: note)
            }
        } catch {
            state = .error(message: error.localizedDescription, note: note)
        }
    }

    func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 800_000_000)
            } catch {
                return
            }
            guard let self else { return }
            await self.autosaveIfNeeded()
        }
    }

    func autosaveIfNeeded() async {
        guard !isSaving else { return }
        guard note != nil else { return }

        guard hasUnsavedChanges else { return }

        await saveImpl(reason: "autosave")
    }

    func cancelAutosave() {
        autosaveTask?.cancel()
        autosaveTask = nil
    }

    func speakCurrentNote() {
        let body = draftBody.trimmingCharacters(in: .whitespacesAndNewlines)
        graph.textToSpeech.speak(body.isEmpty ? draftTitle : body, locale: .current)
    }

    /// Toggles the current note's pinned state without disturbing unsaved edits.
    func togglePinned() async {
        guard !isTogglingPinned, let note else {
            return
        }

        let targetPinnedState = !note.isPinned
        isTogglingPinned = true
        defer { isTogglingPinned = false }

        do {
            try await graph.setNotePinned.execute(noteID: note.id, isPinned: targetPinnedState)
            var updatedNote = note
            updatedNote.isPinned = targetPinnedState
            self.note = updatedNote
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Stops any active text-to-speech playback.
    func stopSpeaking() {
        graph.textToSpeech.stopSpeaking()
    }

    /// Deletes the loaded note.
    func delete() async throws {
        try await graph.deleteNote.execute(noteID: noteID)
    }

    /// Clears the current error message.
    func clearError() {
        if case .error = state {
            state = note.map { .loaded($0) } ?? .idle
        }
    }

    func clearConflict() {
        if case .conflict = state {
            state = note.map { .loaded($0) } ?? .idle
        }
    }
}

struct NoteDetailView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: NoteDetailViewModel

    private let onDeleted: @MainActor () async -> Void
    private let runsLoadTaskOnAppear: Bool

    init(
        noteID: UUID,
        graph: AppGraph,
        onDeleted: @escaping @MainActor () async -> Void,
        runsLoadTaskOnAppear: Bool = true
    ) {
        _viewModel = State(initialValue: NoteDetailViewModel(noteID: noteID, graph: graph))
        self.onDeleted = onDeleted
        self.runsLoadTaskOnAppear = runsLoadTaskOnAppear
    }

    init(
        viewModel: NoteDetailViewModel,
        onDeleted: @escaping @MainActor () async -> Void,
        runsLoadTaskOnAppear: Bool = false
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onDeleted = onDeleted
        self.runsLoadTaskOnAppear = runsLoadTaskOnAppear
    }

    var body: some View {
        Form {
            if let note = viewModel.note {
                Section("Note") {
                    TextField("Title", text: $viewModel.draftTitle)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("noteTitleField")
                        .onChange(of: viewModel.draftTitle) { _, _ in
                            viewModel.scheduleAutosave()
                        }

                    noteBodyEditor
                }

                Section("Metadata") {
                    LabeledContent("Created") {
                        Text(note.createdAt, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                    }
                    LabeledContent("Updated") {
                        Text(note.updatedAt, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                    }
                    LabeledContent("Entries") {
                        Text("\(note.entries.count)")
                    }
                }

                if !note.entries.isEmpty {
                    Section("History") {
                        ForEach(note.entries.sorted(by: { $0.createdAt > $1.createdAt })) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.kind.rawValue.capitalized)
                                    .font(.subheadline.weight(.semibold))
                                Text(entry.createdAt, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(entry.text)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(4)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            } else if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ContentUnavailableView(
                    "Note unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The selected note could not be loaded.")
                )
            }
        }
        .navigationTitle(viewModel.note?.displayTitle ?? "Note")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard runsLoadTaskOnAppear else {
                return
            }

            await viewModel.load()
        }
        .onDisappear {
            Task {
                await viewModel.autosaveIfNeeded()
                viewModel.cancelAutosave()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    if (viewModel.note?.body ?? viewModel.draftBody).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        viewModel.stopSpeaking()
                    } else {
                        viewModel.speakCurrentNote()
                    }
                } label: {
                    Label("Read aloud", systemImage: "speaker.wave.2")
                }

                Button {
                    Task { await viewModel.save() }
                } label: {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(viewModel.isSaving)
                .accessibilityIdentifier("saveNoteButton")

                pinNoteToolbarItem
                deleteNoteToolbarItem
            }
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { newValue in if !newValue { viewModel.clearError() } }
            ),
            actions: {
                Button("Retry") {
                    Task { await viewModel.retryAfterError() }
                }

                if viewModel.note != nil {
                    Button("Copy Draft") {
                        #if os(iOS)
                        UIPasteboard.general.string = [viewModel.draftTitle, viewModel.draftBody]
                            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                            .joined(separator: "\n\n")
                        #elseif os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            [viewModel.draftTitle, viewModel.draftBody]
                                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                                .joined(separator: "\n\n"),
                            forType: .string
                        )
                        #endif
                    }
                }

                Button("OK", role: .cancel) {
                    viewModel.clearError()
                }
            },
            message: {
                Text(viewModel.errorMessage ?? "")
            }
        )
        .alert(
            "Note changed",
            isPresented: Binding(
                get: { viewModel.conflictMessage != nil },
                set: { newValue in if !newValue { viewModel.clearConflict() } }
            ),
            actions: {
                Button("Reload latest") {
                    Task {
                        await viewModel.load(preservingUnsavedDrafts: false)
                        viewModel.clearConflict()
                    }
                }
                Button("Keep editing", role: .cancel) {
                    viewModel.clearConflict()
                }
            },
            message: {
                Text(viewModel.conflictMessage ?? "")
            }
        )
    }

    @ViewBuilder
    private var noteBodyEditor: some View {
#if os(watchOS)
        TextField("Body", text: $viewModel.draftBody, axis: .vertical)
            .lineLimit(4...10)
            .accessibilityIdentifier("noteBodyEditor")
            .onChange(of: viewModel.draftBody) { _, _ in
                viewModel.scheduleAutosave()
            }
#else
        TextEditor(text: $viewModel.draftBody)
            .frame(minHeight: 240)
            .accessibilityIdentifier("noteBodyEditor")
            .onChange(of: viewModel.draftBody) { _, _ in
                viewModel.scheduleAutosave()
            }
#endif
    }

    @ViewBuilder
    private var pinNoteToolbarItem: some View {
        let isPinned = viewModel.note?.isPinned == true
#if os(watchOS)
        Button {
            Task {
                await viewModel.togglePinned()
            }
        } label: {
            Image(systemName: isPinned ? "pin.fill" : "pin")
        }
        .disabled(viewModel.note == nil || viewModel.isTogglingPinned || viewModel.isSaving)
        .accessibilityIdentifier("togglePinnedButton")
#else
        Button {
            Task {
                await viewModel.togglePinned()
            }
        } label: {
            Label(isPinned ? "Unpin Note" : "Pin Note", systemImage: isPinned ? "pin.fill" : "pin")
        }
        .disabled(viewModel.note == nil || viewModel.isTogglingPinned || viewModel.isSaving)
        .accessibilityIdentifier("togglePinnedButton")
#endif
    }

    @ViewBuilder
    private var deleteNoteToolbarItem: some View {
#if os(watchOS)
        Button(role: .destructive) {
            Task {
                await deleteNote()
            }
        } label: {
            Image(systemName: "trash")
        }
        .accessibilityIdentifier("deleteNoteActionButton")
#else
        Menu {
            Button(role: .destructive) {
                Task {
                    await deleteNote()
                }
            } label: {
                Label("Delete Note", systemImage: "trash")
            }
            .accessibilityIdentifier("deleteNoteActionButton")
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityIdentifier("deleteNoteMenuButton")
#endif
    }

    /// Deletes the current note, invokes `onDeleted`, and dismisses on success.
    private func deleteNote() async {
        do {
            try await viewModel.delete()
            await onDeleted()
            dismiss()
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
}
