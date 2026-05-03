import SwiftUI
import SecondBrainComposition

struct ContentView: View {
    let graph: AppGraph
    @State private var notesStore: NotesStore
    @State private var navigationPath = NavigationPath()

    init(graph: AppGraph) {
        self.graph = graph
        _notesStore = State(initialValue: NotesStore(graph: graph))
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            NotesListView(store: notesStore) { noteID in
                navigationPath.append(noteID)
            }
            .navigationDestination(for: UUID.self) { noteID in
                NoteDetailView(noteID: noteID, graph: graph) {
                    await notesStore.refresh()
                }
            }
        }
    }
}

#Preview {
    ContentView(graph: AppGraph.preview)
}
