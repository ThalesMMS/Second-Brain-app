import SwiftUI
import SecondBrainComposition

struct ContentView: View {
    let graph: AppGraph
    @State private var notesStore: NotesStore

    init(graph: AppGraph) {
        self.graph = graph
        _notesStore = State(initialValue: NotesStore(graph: graph))
    }

    var body: some View {
        NavigationStack {
            NotesListView(store: notesStore)
        }
    }
}

#Preview {
    ContentView(graph: AppGraph.preview)
}
