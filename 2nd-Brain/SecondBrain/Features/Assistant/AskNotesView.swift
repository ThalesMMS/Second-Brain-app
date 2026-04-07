import SwiftUI
import Observation
import SecondBrainComposition
import SecondBrainDomain

struct AssistantMessage: Identifiable, Hashable {
    enum Role: Hashable {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
}

@MainActor
@Observable
final class AskNotesViewModel {
    private let graph: AppGraph?

    var input = ""
    var messages: [AssistantMessage] = []
    var isSending = false
    var errorMessage: String?
    var capabilityState: AssistantCapabilityState
    var assistantStatus: NotesAssistantStatus?

    init(graph: AppGraph) {
        self.graph = graph
        self.capabilityState = graph.notesAssistant.capabilityState
        self.assistantStatus = graph.notesAssistant.status
    }

    init(
        input: String = "",
        messages: [AssistantMessage] = [],
        isSending: Bool = false,
        errorMessage: String? = nil,
        capabilityState: AssistantCapabilityState = .unavailable(reason: "Snapshot-only Ask Notes model."),
        assistantStatus: NotesAssistantStatus? = nil
    ) {
        self.graph = nil
        self.input = input
        self.messages = messages
        self.isSending = isSending
        self.errorMessage = errorMessage
        self.capabilityState = capabilityState
        self.assistantStatus = assistantStatus
    }

    func send() async {
        guard let graph else {
            errorMessage = "Ask Notes test doubles cannot send messages."
            return
        }

        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            return
        }

        messages.append(AssistantMessage(role: .user, text: trimmedInput))
        input = ""
        isSending = true
        defer { isSending = false }

        do {
            let response = try await graph.askNotes.execute(trimmedInput)
            messages.append(AssistantMessage(role: .assistant, text: response.text))
            errorMessage = nil
            refreshStatus()
        } catch {
            errorMessage = error.localizedDescription
            refreshStatus()
        }
    }

    func resetConversation() {
        graph?.notesAssistant.resetConversation()
        messages.removeAll()
        refreshStatus()
    }

    func clearError() {
        errorMessage = nil
    }

    private func refreshStatus() {
        guard let graph else {
            return
        }

        capabilityState = graph.notesAssistant.capabilityState
        assistantStatus = graph.notesAssistant.status
    }
}

struct AskNotesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: AskNotesViewModel

    init(graph: AppGraph) {
        _viewModel = State(initialValue: AskNotesViewModel(graph: graph))
    }

    init(viewModel: AskNotesViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.messages.isEmpty {
                    ContentUnavailableView(
                        "Ask your notes",
                        systemImage: "sparkles",
                        description: Text("Examples: summarize my oncology reminders, read the note about residency, append a new task to my shopping list, or na lista de compras, troque feijão por ervilha.")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                AssistantBubble(message: message)
                            }
                            if viewModel.isSending {
                                ProgressView()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding()
                    }
                }

                Divider()

                HStack(alignment: .bottom, spacing: 12) {
                    TextField("Ask or instruct the assistant", text: $viewModel.input, axis: .vertical)
                        .platformInputStyle()
                        .lineLimit(1...5)
                        .accessibilityIdentifier("assistantInputField")

                    Button {
                        Task {
                            await viewModel.send()
                        }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                    }
                    .disabled(viewModel.isSending)
                    .accessibilityIdentifier("assistantSendButton")
                }
                .padding()
            }
            .navigationTitle("Ask Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset") {
                        viewModel.resetConversation()
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                capabilityBanner
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
    }

    @ViewBuilder
    private var capabilityBanner: some View {
        switch viewModel.capabilityState {
        case .available:
            switch viewModel.assistantStatus {
            case let .reducedFunctionality(reason):
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(.thinMaterial)
            case nil:
                EmptyView()
            }
        case let .unavailable(reason):
            Text(reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(.thinMaterial)
        }
    }
}

private extension View {
    @ViewBuilder
    func platformInputStyle() -> some View {
#if os(watchOS)
        self
#else
        self.textFieldStyle(.roundedBorder)
#endif
    }
}

private struct AssistantBubble: View {
    let message: AssistantMessage

    var body: some View {
        HStack {
            if message.role == .assistant {
                bubble
                Spacer(minLength: 32)
            } else {
                Spacer(minLength: 32)
                bubble
            }
        }
    }

    private var bubble: some View {
        Text(message.text)
            .padding(12)
            .frame(maxWidth: 320, alignment: .leading)
            .background(message.role == .assistant ? Color.secondary.opacity(0.15) : Color.accentColor.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
