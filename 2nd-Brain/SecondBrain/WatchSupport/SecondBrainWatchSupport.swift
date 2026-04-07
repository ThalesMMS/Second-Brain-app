#if os(watchOS)
import SwiftUI
import SecondBrainComposition
import SecondBrainDomain

@main
struct SecondBrainWatchApp: App {
    private let startupCoordinator = AppStartupCoordinator {
        try AppGraph.makeLive(useSharedContainer: false)
    }

    var body: some Scene {
        WindowGroup {
            AppStartupContainerView(coordinator: startupCoordinator) { graph in
                WatchRootView(graph: graph)
            }
        }
    }
}

struct WatchRootView: View {
    let graph: AppGraph
    @State private var notesStore: NotesStore
    @State private var showingCapture = false
    @State private var showingAssistant = false

    init(graph: AppGraph) {
        self.graph = graph
        _notesStore = State(initialValue: NotesStore(graph: graph))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showingCapture = true
                    } label: {
                        Label("Quick Capture", systemImage: "square.and.pencil")
                    }

                    Button {
                        showingAssistant = true
                    } label: {
                        Label("Ask Notes", systemImage: "sparkles")
                    }
                }

                if notesStore.isLoading {
                    Section("Recent Notes") {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                } else if notesStore.notes.isEmpty {
                    Section("Recent Notes") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No notes yet")
                                .font(.headline)
                            Text("Create a text note, use voice input, or ask the assistant.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    Section("Recent Notes") {
                        ForEach(notesStore.notes) { note in
                            NavigationLink {
                                NoteDetailView(noteID: note.id, graph: graph) {
                                    await notesStore.refresh()
                                }
                            } label: {
                                WatchNoteRow(note: note)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Second Brain")
            .task {
                await notesStore.refresh()
            }
            .sheet(isPresented: $showingCapture) {
                QuickCaptureView(graph: graph) {
                    await notesStore.refresh()
                }
            }
            .sheet(isPresented: $showingAssistant) {
                AskNotesView(graph: graph)
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { notesStore.errorMessage != nil },
                    set: { newValue in if !newValue { notesStore.clearError() } }
                ),
                actions: {
                    Button("OK", role: .cancel) {
                        notesStore.clearError()
                    }
                },
                message: {
                    Text(notesStore.errorMessage ?? "")
                }
            )
        }
    }
}

private struct WatchNoteRow: View {
    let note: NoteSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.title)
                .font(.headline)
                .lineLimit(1)

            Text(note.previewText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}
#endif
