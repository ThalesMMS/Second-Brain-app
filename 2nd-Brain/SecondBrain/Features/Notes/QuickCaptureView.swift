import SwiftUI
import Observation
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif
import SecondBrainComposition
import SecondBrainDomain

@MainActor
@Observable
final class QuickCaptureViewModel {
    enum ErrorKind {
        case microphonePermissionDenied
        case generic
    }

    struct Dependencies {
        let captureCapabilityState: @MainActor () -> AssistantCapabilityState
        let voiceCommandCapabilityState: @MainActor () -> AssistantCapabilityState
        let refineTypedNote: @MainActor (_ title: String, _ body: String, _ locale: Locale) async throws -> NoteCaptureRefinement
        let createNote: @MainActor (_ title: String, _ body: String, _ source: NoteMutationSource) async throws -> Note
        let requestRecordingPermission: @MainActor () async -> Bool
        let makeTemporaryRecordingURL: @MainActor () throws -> URL
        let startRecording: @MainActor (_ url: URL) throws -> Void
        let stopRecording: @MainActor () throws -> RecordedAudio
        let cancelRecording: @MainActor () -> Void
        let processVoiceCapture: @MainActor (_ title: String, _ audioURL: URL, _ locale: Locale, _ source: NoteMutationSource) async throws -> VoiceCaptureResult
        let processAssistantInput: @MainActor (_ input: String) async throws -> NotesAssistantResponse
    }

    private let dependencies: Dependencies
    private let onSaved: @MainActor () async -> Void

    var title = ""
    var body = ""
    var isSavingText = false
    var isRecording = false
    var isSavingAudio = false
    var transcriptionPreview = ""
    var voiceAssistantMessage = ""
    var voiceAssistantInteraction: NotesAssistantInteractionState = .none
    var errorMessage: String?
    private var errorKind: ErrorKind?
    private(set) var shouldDismissAfterVoiceCapture = false

    var captureCapabilityState: AssistantCapabilityState {
        dependencies.captureCapabilityState()
    }

    var voiceCommandCapabilityState: AssistantCapabilityState {
        dependencies.voiceCommandCapabilityState()
    }

    var isAudioFlowActive: Bool {
        isRecording || isSavingAudio
    }

    var isSaveTextDisabled: Bool {
        isSavingText || isAudioFlowActive || (trimmedTitle.isEmpty && trimmedBody.isEmpty)
    }

    var isVoiceCaptureDisabled: Bool {
        isSavingText || isSavingAudio
    }

    var captureUnavailableReason: String? {
        if case let .unavailable(reason) = captureCapabilityState {
            return reason
        }
        return nil
    }

    var voiceCommandUnavailableReason: String? {
        if case let .unavailable(reason) = voiceCommandCapabilityState {
            return reason
        }
        return nil
    }

    var hasPendingVoiceConfirmation: Bool {
        voiceAssistantInteraction == .pendingEditConfirmation
    }

    var hasVoiceAssistantFeedback: Bool {
        !voiceAssistantMessage.isEmpty
    }

    var errorAlertAccessibilityIdentifier: String? {
        guard errorKind == .microphonePermissionDenied else {
            return nil
        }

        return "microphonePermissionErrorAlert"
    }

    convenience init(graph: AppGraph, onSaved: @escaping @MainActor () async -> Void) {
        let dependencies = Dependencies(
            captureCapabilityState: { graph.noteCaptureIntelligence.capabilityState },
            voiceCommandCapabilityState: { graph.voiceCaptureInterpretation.capabilityState },
            refineTypedNote: { title, body, locale in
                try await graph.noteCaptureIntelligence.refineTypedNote(
                    title: title,
                    body: body,
                    locale: locale
                )
            },
            createNote: { title, body, source in
                try await graph.createNote.execute(title: title, body: body, source: source)
            },
            requestRecordingPermission: {
                await graph.audioRecorder.requestPermission()
            },
            makeTemporaryRecordingURL: {
                try graph.audioFileStore.makeTemporaryRecordingURL()
            },
            startRecording: { url in
                try graph.audioRecorder.startRecording(to: url)
            },
            stopRecording: {
                try graph.audioRecorder.stopRecording()
            },
            cancelRecording: {
                graph.audioRecorder.cancelRecording()
            },
            processVoiceCapture: { title, audioURL, locale, source in
                try await graph.processVoiceCapture.execute(
                    title: title,
                    audioURL: audioURL,
                    locale: locale,
                    source: source
                )
            },
            processAssistantInput: { input in
                try await graph.askNotes.execute(input)
            }
        )
        self.init(dependencies: dependencies, onSaved: onSaved)
    }

    init(dependencies: Dependencies, onSaved: @escaping @MainActor () async -> Void) {
        self.dependencies = dependencies
        self.onSaved = onSaved
    }

    /// Saves the current typed draft, using refinement when available.
    /// - Note: No action is taken if a text save is already in progress or an audio flow is active.
    func saveTextNote() async {
        guard !isSavingText, !isAudioFlowActive else {
            return
        }

        isSavingText = true
        defer { isSavingText = false }

        do {
            shouldDismissAfterVoiceCapture = false
            clearError()
            let draft = NoteCaptureRefinement(title: title, body: body)
            let refinement: NoteCaptureRefinement

            do {
                refinement = try await dependencies.refineTypedNote(
                    title,
                    body,
                    .current
                )
            } catch let error as CaptureIntelligenceError {
                switch error {
                case .unavailable:
                    refinement = draft
                }
            }

            _ = try await dependencies.createNote(refinement.title, refinement.body, .manual)
            await onSaved()
            resetDraft()
        } catch {
            presentError(error)
        }
    }

    /// Starts or stops voice capture depending on the current recording state.
    func toggleRecording() async {
        guard !isSavingText else {
            return
        }

        if isRecording {
            await stopRecordingAndProcessVoiceCapture()
        } else {
            await startRecording()
        }
    }

    /// Confirms the pending voice confirmation, if one exists.
    func confirmPendingVoiceCommand() async {
        await resolvePendingVoiceCommand(input: "confirm")
    }

    /// Cancels the pending voice confirmation, if one exists.
    func cancelPendingVoiceCommand() async {
        await resolvePendingVoiceCommand(input: "cancel")
    }

    /// Cancels the active recording session.
    func cancelRecording() {
        dependencies.cancelRecording()
        isRecording = false
    }

    /// Starts a temporary recording after microphone permission is granted.
    private func startRecording() async {
        guard !isSavingText, !isSavingAudio else {
            return
        }

        do {
            shouldDismissAfterVoiceCapture = false
            let granted = await dependencies.requestRecordingPermission()
            guard granted else {
                throw AudioServiceError.permissionDenied
            }

            let url = try dependencies.makeTemporaryRecordingURL()
            try dependencies.startRecording(url)
            isRecording = true
            clearError()
        } catch {
            presentError(error)
        }
    }

    /// Stops the active recording and routes the transient audio through voice capture processing.
    /// - Note: The recorded audio is treated as temporary transport and is not retained as note data here.
    private func stopRecordingAndProcessVoiceCapture() async {
        guard isRecording else {
            return
        }

        isSavingAudio = true
        defer { isSavingAudio = false }

        do {
            let recordedAudio = try dependencies.stopRecording()
            isRecording = false
            let result = try await dependencies.processVoiceCapture(
                title,
                recordedAudio.temporaryFileURL,
                .current,
                .speechToText
            )
            await handleVoiceCaptureResult(result)
        } catch {
            isRecording = false
            presentError(error)
        }
    }

    /// Resolves a pending voice confirmation by sending the assistant the chosen input.
    /// - Parameter input: The assistant input used to resolve the pending confirmation, such as `"confirm"` or `"cancel"`.
    /// - Note: No action is taken if there is no pending confirmation or audio processing is already in progress.
    private func resolvePendingVoiceCommand(input: String) async {
        guard hasPendingVoiceConfirmation, !isSavingAudio else {
            return
        }

        isSavingAudio = true
        defer { isSavingAudio = false }

        do {
            let response = try await dependencies.processAssistantInput(input)
            await handleAssistantResponse(
                response,
                transcript: transcriptionPreview,
                prefersDraftPromotion: false
            )
        } catch {
            presentError(error)
        }
    }

    /// Clears the current user-facing error state.
    func clearError() {
        errorMessage = nil
        errorKind = nil
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedBody: String {
        body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Resets the draft and transient voice-capture UI state.
    private func resetDraft() {
        title = ""
        body = ""
        transcriptionPreview = ""
        voiceAssistantMessage = ""
        voiceAssistantInteraction = .none
        shouldDismissAfterVoiceCapture = false
        clearError()
    }

    /// Applies the result of a completed voice capture.
    private func handleVoiceCaptureResult(_ result: VoiceCaptureResult) async {
        shouldDismissAfterVoiceCapture = false

        switch result {
        case let .createdNote(note):
            transcriptionPreview = note.previewText
            voiceAssistantMessage = ""
            voiceAssistantInteraction = .none
            await onSaved()
            title = ""
            body = ""
            shouldDismissAfterVoiceCapture = true
        case let .assistantResponse(response, transcript):
            let shouldPromoteTranscriptToDraft = response.referencedNoteIDs.isEmpty && response.interaction == .none
            await handleAssistantResponse(
                response,
                transcript: transcript,
                prefersDraftPromotion: shouldPromoteTranscriptToDraft
            )
        }
    }

    /// Applies assistant feedback from a voice capture, optionally promoting the transcript into the draft.
    private func handleAssistantResponse(
        _ response: NotesAssistantResponse,
        transcript: String,
        prefersDraftPromotion: Bool
    ) async {
        transcriptionPreview = transcript
        voiceAssistantMessage = response.text
        voiceAssistantInteraction = response.interaction
        clearError()

        if prefersDraftPromotion {
            body = transcript
            title = ""
        }

        if !response.referencedNoteIDs.isEmpty {
            await onSaved()
        }
    }

    private func presentError(_ error: Error) {
        errorMessage = error.localizedDescription

        if let audioServiceError = error as? AudioServiceError,
           audioServiceError == .permissionDenied {
            errorKind = .microphonePermissionDenied
        } else {
            errorKind = .generic
        }
    }
}

#if canImport(UIKit) && !os(watchOS)
private struct QuickCaptureErrorAlertPresenter: UIViewControllerRepresentable {
    @Binding var message: String?
    let accessibilityIdentifier: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(message: $message)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ viewController: UIViewController, context: Context) {
        let presentingViewController = topPresentedController(
            from: viewController.view.window?.rootViewController ?? viewController
        )

        guard let message else {
            if let alertController = presentingViewController as? UIAlertController {
                alertController.dismiss(animated: true)
            }

            return
        }

        if let alertController = presentingViewController as? UIAlertController {
            alertController.message = message
            alertController.view.accessibilityIdentifier = accessibilityIdentifier
            return
        }

        let alertController = UIAlertController(
            title: "Error",
            message: message,
            preferredStyle: .alert
        )
        alertController.view.accessibilityIdentifier = accessibilityIdentifier
        alertController.addAction(
            UIAlertAction(title: "OK", style: .cancel) { _ in
                context.coordinator.message.wrappedValue = nil
            }
        )

        DispatchQueue.main.async {
            guard presentingViewController.presentedViewController == nil else {
                return
            }

            presentingViewController.present(alertController, animated: true)
        }
    }

    private func topPresentedController(from rootViewController: UIViewController) -> UIViewController {
        var currentViewController = rootViewController

        while let presentedViewController = currentViewController.presentedViewController {
            currentViewController = presentedViewController
        }

        return currentViewController
    }

    final class Coordinator {
        let message: Binding<String?>

        init(message: Binding<String?>) {
            self.message = message
        }
    }
}
#endif

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
                                dismiss()
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
                                dismiss()
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
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Transcript")
                                .font(.headline)
                            Text(viewModel.transcriptionPreview)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("voiceTranscriptPreview")
                    }

                    if viewModel.hasVoiceAssistantFeedback {
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
