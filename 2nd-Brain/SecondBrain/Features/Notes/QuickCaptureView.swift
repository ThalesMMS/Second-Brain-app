import SwiftUI
import SecondBrainComposition

struct QuickCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: QuickCaptureViewModel

    init(graph: AppGraph, onSaved: @escaping @MainActor () async -> Void) {
        _viewModel = State(initialValue: QuickCaptureViewModel(graph: graph, onSaved: onSaved))
    }

    init(viewModel: QuickCaptureViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Form {
                QuickCaptureTextNoteSection(viewModel: viewModel) {
                    dismiss()
                }

                QuickCaptureVoiceInputSection(viewModel: viewModel) {
                    dismiss()
                }
            }
            .navigationTitle("Quick Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
#if canImport(UIKit) && !os(watchOS)
            .background {
                QuickCaptureErrorAlertPresenter(
                    message: Binding(
                        get: { viewModel.errorMessage },
                        set: { newValue in
                            if let newValue {
                                viewModel.errorMessage = newValue
                            } else {
                                viewModel.clearError()
                            }
                        }
                    ),
                    accessibilityIdentifier: viewModel.errorAlertAccessibilityIdentifier
                )
                .allowsHitTesting(false)
            }
#else
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
#endif
        }
    }
}

private struct QuickCaptureTextNoteSection: View {
    @Bindable var viewModel: QuickCaptureViewModel
    let dismissAfterSave: () -> Void

    var body: some View {
        Section("Text note") {
            TextField("Title", text: $viewModel.title)
                .textInputAutocapitalization(.sentences)
                .accessibilityIdentifier("quickCaptureTitleField")
            bodyEditor

            if let reason = viewModel.captureUnavailableReason {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task {
                    await viewModel.saveTextNote()
                    if viewModel.errorMessage == nil {
                        dismissAfterSave()
                    }
                }
            } label: {
                if viewModel.isSavingText {
                    ProgressView()
                } else {
                    Label("Save text note", systemImage: "square.and.arrow.down")
                }
            }
            .disabled(viewModel.isSaveTextDisabled)
            .accessibilityIdentifier("saveTextNoteButton")
        }
    }

    @ViewBuilder
    private var bodyEditor: some View {
#if os(watchOS)
        TextField("Body", text: $viewModel.body, axis: .vertical)
            .lineLimit(4...8)
            .accessibilityIdentifier("quickCaptureBodyEditor")
#else
        TextEditor(text: $viewModel.body)
            .frame(minHeight: 180)
            .accessibilityIdentifier("quickCaptureBodyEditor")
#endif
    }
}

private struct QuickCaptureVoiceInputSection: View {
    @Bindable var viewModel: QuickCaptureViewModel
    let dismissAfterVoiceCapture: () -> Void

    var body: some View {
        Section("Voice input") {
            if let reason = viewModel.voiceCommandUnavailableReason {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task {
                    await viewModel.toggleRecording()
                    if viewModel.shouldDismissAfterVoiceCapture {
                        dismissAfterVoiceCapture()
                    }
                }
            } label: {
                Label(
                    viewModel.isRecording ? "Stop recording and process" : "Record voice input",
                    systemImage: viewModel.isRecording ? "stop.circle.fill" : "mic.circle.fill"
                )
            }
            .disabled(viewModel.isVoiceCaptureDisabled)
            .accessibilityIdentifier("recordVoiceNoteButton")

            if viewModel.isRecording {
                Button(role: .destructive) {
                    viewModel.cancelRecording()
                } label: {
                    Label("Cancel recording", systemImage: "xmark.circle")
                }
            }

            if viewModel.isSavingAudio {
                ProgressView("Transcribing and routing voice input…")
            }

            if !viewModel.transcriptionPreview.isEmpty {
                QuickCaptureTranscriptPreview(transcript: viewModel.transcriptionPreview)
            }

            if viewModel.hasVoiceAssistantFeedback {
                QuickCaptureVoiceAssistantFeedback(viewModel: viewModel)
            }
        }
    }
}

private struct QuickCaptureTranscriptPreview: View {
    let transcript: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Transcript")
                .font(.headline)
            Text(transcript)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voiceTranscriptPreview")
    }
}

private struct QuickCaptureVoiceAssistantFeedback: View {
    @Bindable var viewModel: QuickCaptureViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Voice command result")
                .font(.headline)
            Text(viewModel.voiceAssistantMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if viewModel.hasPendingVoiceConfirmation {
                HStack {
                    Button("Confirm") {
                        Task {
                            await viewModel.confirmPendingVoiceCommand()
                        }
                    }
                    .disabled(viewModel.isSavingAudio)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("confirmPendingVoiceCommandButton")

                    Spacer(minLength: 12)

                    Button("Cancel") {
                        Task {
                            await viewModel.cancelPendingVoiceCommand()
                        }
                    }
                    .disabled(viewModel.isSavingAudio)
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .accessibilityIdentifier("cancelPendingVoiceCommandButton")

                    if viewModel.isSavingAudio {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voiceAssistantFeedback")
    }
}
