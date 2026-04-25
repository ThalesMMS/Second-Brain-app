import SwiftUI
import Observation
import SecondBrainComposition
import SecondBrainDomain

@MainActor
@Observable
final class NotesStore {
    let graph: AppGraph

    var notes: [NoteSummary] = []
    var searchText = ""
    var isLoading = false
    var errorMessage: String?
    private var togglingPinnedNoteIDs: Set<UUID> = []
    private var refreshToken = 0

    init(graph: AppGraph) {
        self.graph = graph
    }

    /// Reloads notes for the current search text.
    func refresh() async {
        let token = beginRefresh()

        do {
            let refreshedNotes = try await graph.listNotes.execute(matching: currentQuery())
            commitRefresh(notes: refreshedNotes, token: token)
        } catch {
            commitRefresh(error: error, token: token)
        }
    }

    /// Deletes a note and reloads the list.
    func delete(noteID: UUID) async {
        let token = beginRefresh()

        do {
            try await graph.deleteNote.execute(noteID: noteID)
            let refreshedNotes = try await graph.listNotes.execute(matching: currentQuery())
            commitRefresh(notes: refreshedNotes, token: token)
        } catch {
            commitRefresh(error: error, token: token)
        }
    }

    /// Toggles a note's pinned state and reloads the list.
    func togglePinned(noteID: UUID) async {
        guard !togglingPinnedNoteIDs.contains(noteID),
              let note = notes.first(where: { $0.id == noteID }) else {
            return
        }

        togglingPinnedNoteIDs.insert(noteID)
        defer { togglingPinnedNoteIDs.remove(noteID) }

        var token: Int?

        do {
            try await graph.setNotePinned.execute(noteID: noteID, isPinned: !note.isPinned)
            let refreshToken = beginRefresh()
            token = refreshToken
            let refreshedNotes = try await graph.listNotes.execute(matching: currentQuery())
            commitRefresh(notes: refreshedNotes, token: refreshToken)
        } catch {
            if let token {
                commitRefresh(error: error, token: token)
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func isTogglingPinned(noteID: UUID) -> Bool {
        togglingPinnedNoteIDs.contains(noteID)
    }

    private func beginRefresh() -> Int {
        refreshToken += 1
        isLoading = true
        return refreshToken
    }

    private func commitRefresh(notes: [NoteSummary], token: Int) {
        guard token == refreshToken else {
            return
        }

        self.notes = notes
        errorMessage = nil
        isLoading = false
    }

    private func commitRefresh(error: any Error, token: Int) {
        guard token == refreshToken else {
            return
        }

        errorMessage = error.localizedDescription
        isLoading = false
    }

    private func currentQuery() -> String? {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedQuery.isEmpty ? nil : trimmedQuery
    }
}

struct NotesListView: View {
    @Bindable var store: NotesStore
    let runsTasksOnAppear: Bool

    @State private var showingQuickCapture = false
    @State private var showingAssistant = false

    init(store: NotesStore, runsTasksOnAppear: Bool = true) {
        self.store = store
        self.runsTasksOnAppear = runsTasksOnAppear
    }

    var body: some View {
        List {
            if store.notes.isEmpty, !store.isLoading {
                ContentUnavailableView(
                    "No notes yet",
                    systemImage: "note.text",
                    description: Text("Create notes manually, by voice, or through Siri shortcuts.")
                )
                .listRowSeparatorIfAvailable()
            } else {
                ForEach(store.notes) { note in
                    NavigationLink {
                        NoteDetailView(noteID: note.id, graph: store.graph) {
                            await store.refresh()
                        }
                    } label: {
                        NoteSummaryRow(note: note)
                    }
                    .contextMenu {
                        Button {
                            Task {
                                await store.togglePinned(noteID: note.id)
                            }
                        } label: {
                            Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
                        }
                        .disabled(store.isTogglingPinned(noteID: note.id))
                    }
                    .accessibilityIdentifier("noteRow_\(note.id.uuidString)")
                }
                .onDelete { offsets in
                    let ids = offsets.compactMap { index in
                        store.notes.indices.contains(index) ? store.notes[index].id : nil
                    }

                    Task {
                        for id in ids {
                            await store.delete(noteID: id)
                        }
                    }
                }
            }
        }
        .overlay {
            if store.isLoading, store.notes.isEmpty {
                ProgressView()
            }
        }
        .navigationTitle("Second Brain")
        .searchable(text: $store.searchText, prompt: "Search notes")
        .task {
            guard runsTasksOnAppear else {
                return
            }

            await store.refresh()
            store.graph.notesAssistant.prewarm()
        }
        .task(id: store.searchText) {
            guard runsTasksOnAppear else {
                return
            }

            await store.refresh()
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingAssistant = true
                } label: {
                    Label("Ask Notes", systemImage: "sparkles")
                }
                .accessibilityIdentifier("askNotesButton")

                Button {
                    showingQuickCapture = true
                } label: {
                    Label("Quick Capture", systemImage: "square.and.pencil")
                }
                .accessibilityIdentifier("quickCaptureButton")
            }
        }
        .sheet(isPresented: $showingQuickCapture) {
            QuickCaptureView(graph: store.graph) {
                await store.refresh()
            }
        }
        .sheet(isPresented: $showingAssistant) {
            AskNotesView(graph: store.graph)
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { newValue in if !newValue { store.clearError() } }
            ),
            actions: {
                Button("OK", role: .cancel) {
                    store.clearError()
                }
            },
            message: {
                Text(store.errorMessage ?? "")
            }
        )
    }
}

private extension View {
    @ViewBuilder
    func listRowSeparatorIfAvailable() -> some View {
#if os(watchOS)
        self
#else
        self.listRowSeparator(.hidden)
#endif
    }
}

private struct NoteSummaryRow: View {
    let note: NoteSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(note.title)
                    .font(.headline)
                    .lineLimit(1)

                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Pinned")
                }
            }

            Text(note.previewText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(note.updatedAt, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
