import SwiftUI
import Observation
import SecondBrainComposition
import SecondBrainDomain

@MainActor
@Observable
final class NoteDetailViewModel {
    let noteID: UUID
    private let graph: AppGraph

    var note: Note?
    var draftTitle = ""
    var draftBody = ""
    var isLoading = false
    var isSaving = false
    var errorMessage: String?

    init(noteID: UUID, graph: AppGraph) {
        self.noteID = noteID
        self.graph = graph
    }

    /// Loads the note and refreshes the editable draft state.
    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            note = try await graph.loadNote.execute(id: noteID)
            draftTitle = note?.title ?? ""
            draftBody = note?.body ?? ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Saves the current draft back to the loaded note.
    func save() async {
        guard let note else {
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            self.note = try await graph.saveNote.execute(
                noteID: note.id,
                title: draftTitle,
                body: draftBody,
                lastSeenUpdatedAt: note.updatedAt,
                source: .manual
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func speakCurrentNote() {
        let body = draftBody.trimmingCharacters(in: .whitespacesAndNewlines)
        graph.textToSpeech.speak(body.isEmpty ? draftTitle : body, locale: .current)
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
        errorMessage = nil
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
                Button("OK", role: .cancel) {
                    viewModel.clearError()
                }
            },
            message: {
                Text(viewModel.errorMessage ?? "")
            }
        )
    }

    @ViewBuilder
    private var noteBodyEditor: some View {
#if os(watchOS)
        TextField("Body", text: $viewModel.draftBody, axis: .vertical)
            .lineLimit(4...10)
            .accessibilityIdentifier("noteBodyEditor")
#else
        TextEditor(text: $viewModel.draftBody)
            .frame(minHeight: 240)
            .accessibilityIdentifier("noteBodyEditor")
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
