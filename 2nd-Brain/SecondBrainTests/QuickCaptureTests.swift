import Foundation
import Testing
import SecondBrainComposition
import SecondBrainDomain
@testable import SecondBrain

@Suite
struct QuickCaptureTests {
    @Test
    @MainActor
    func quickCaptureConfirmPendingVoiceCommandPassesConfirmString() async {
        var capturedInputs: [String] = []
        let viewModel = QuickCaptureViewModel(
            dependencies: makeMinimalDependencies(
                processAssistantInput: { input in
                    capturedInputs.append(input)
                    return NotesAssistantResponse(
                        text: "Edit applied.",
                        referencedNoteIDs: [UUID()],
                        interaction: .none
                    )
                }
            ),
            onSaved: {}
        )
        viewModel.voiceAssistantInteraction = .pendingEditConfirmation
        viewModel.transcriptionPreview = "replace eggs with milk"
        viewModel.voiceAssistantMessage = "Proposed edit."

        await viewModel.confirmPendingVoiceCommand()

        #expect(capturedInputs == ["confirm"])
        #expect(viewModel.voiceAssistantInteraction == .none)
        #expect(viewModel.voiceAssistantMessage == "Edit applied.")
    }

    @Test
    @MainActor
    func quickCaptureCancelPendingVoiceCommandPassesCancelString() async {
        var capturedInputs: [String] = []
        let viewModel = QuickCaptureViewModel(
            dependencies: makeMinimalDependencies(
                processAssistantInput: { input in
                    capturedInputs.append(input)
                    return NotesAssistantResponse(
                        text: "Cancelled the edit.",
                        referencedNoteIDs: [],
                        interaction: .none
                    )
                }
            ),
            onSaved: {}
        )
        viewModel.voiceAssistantInteraction = .pendingEditConfirmation
        viewModel.transcriptionPreview = "add avocado to shopping list"
        viewModel.voiceAssistantMessage = "Proposed edit."

        await viewModel.cancelPendingVoiceCommand()

        #expect(capturedInputs == ["cancel"])
        #expect(viewModel.voiceAssistantInteraction == .none)
        #expect(viewModel.voiceAssistantMessage == "Cancelled the edit.")
    }

    @Test
    @MainActor
    func quickCaptureResolvePendingVoiceCommandIsNoOpWhenNoPendingConfirmation() async {
        var capturedInputs: [String] = []
        let viewModel = QuickCaptureViewModel(
            dependencies: makeMinimalDependencies(
                processAssistantInput: { input in
                    capturedInputs.append(input)
                    return NotesAssistantResponse(text: "", referencedNoteIDs: [])
                }
            ),
            onSaved: {}
        )
        // voiceAssistantInteraction defaults to .none — no pending confirmation

        await viewModel.confirmPendingVoiceCommand()
        await viewModel.cancelPendingVoiceCommand()

        #expect(capturedInputs.isEmpty)
    }

    @Test
    @MainActor
    func quickCaptureResolvePendingVoiceCommandIsNoOpWhenAlreadySavingAudio() async {
        var capturedInputs: [String] = []
        let viewModel = QuickCaptureViewModel(
            dependencies: makeMinimalDependencies(
                processAssistantInput: { input in
                    capturedInputs.append(input)
                    return NotesAssistantResponse(text: "", referencedNoteIDs: [])
                }
            ),
            onSaved: {}
        )
        viewModel.voiceAssistantInteraction = .pendingEditConfirmation
        viewModel.isSavingAudio = true  // simulate audio save in progress

        await viewModel.confirmPendingVoiceCommand()

        #expect(capturedInputs.isEmpty)
    }

    @Test
    @MainActor
    func quickCaptureConfirmSetsErrorMessageOnAssistantFailure() async {
        struct AssistantError: LocalizedError {
            var errorDescription: String? { "Network timeout." }
        }
        let viewModel = QuickCaptureViewModel(
            dependencies: makeMinimalDependencies(
                processAssistantInput: { _ in throw AssistantError() }
            ),
            onSaved: {}
        )
        viewModel.voiceAssistantInteraction = .pendingEditConfirmation
        viewModel.voiceAssistantMessage = "Proposed edit."

        await viewModel.confirmPendingVoiceCommand()

        #expect(viewModel.errorMessage == "Network timeout.")
    }

    // MARK: - hasPendingVoiceConfirmation (drives confirmPendingVoiceCommandButton / cancelPendingVoiceCommandButton visibility)

    @Test
    @MainActor
    func quickCaptureHasPendingVoiceConfirmationTrueWhenInteractionIsPendingEditConfirmation() {
        let viewModel = QuickCaptureViewModel(dependencies: makeMinimalDependencies(), onSaved: {})
        viewModel.voiceAssistantInteraction = .pendingEditConfirmation

        #expect(viewModel.hasPendingVoiceConfirmation == true)
    }

    @Test
    @MainActor
    func quickCaptureHasPendingVoiceConfirmationFalseByDefault() {
        let viewModel = QuickCaptureViewModel(dependencies: makeMinimalDependencies(), onSaved: {})
        // voiceAssistantInteraction defaults to .none

        #expect(viewModel.hasPendingVoiceConfirmation == false)
    }

    @Test
    @MainActor
    func quickCaptureHasPendingVoiceConfirmationFalseAfterSuccessfulConfirm() async {
        let viewModel = QuickCaptureViewModel(
            dependencies: makeMinimalDependencies(
                processAssistantInput: { _ in
                    NotesAssistantResponse(text: "Updated note.", referencedNoteIDs: [UUID()], interaction: .none)
                }
            ),
            onSaved: {}
        )
        viewModel.voiceAssistantInteraction = .pendingEditConfirmation

        await viewModel.confirmPendingVoiceCommand()

        #expect(viewModel.hasPendingVoiceConfirmation == false)
    }

    @Test
    @MainActor
    func quickCaptureHasPendingVoiceConfirmationFalseAfterSuccessfulCancel() async {
        let viewModel = QuickCaptureViewModel(
            dependencies: makeMinimalDependencies(
                processAssistantInput: { _ in
                    NotesAssistantResponse(text: "Canceled the pending edit.", referencedNoteIDs: [], interaction: .none)
                }
            ),
            onSaved: {}
        )
        viewModel.voiceAssistantInteraction = .pendingEditConfirmation

        await viewModel.cancelPendingVoiceCommand()

        #expect(viewModel.hasPendingVoiceConfirmation == false)
    }

    @Test
    @MainActor
    func quickCaptureHasPendingVoiceConfirmationRemainsUnchangedOnAssistantError() async {
        struct AssistantError: LocalizedError {
            var errorDescription: String? { "Connection failed." }
        }
        let viewModel = QuickCaptureViewModel(
            dependencies: makeMinimalDependencies(
                processAssistantInput: { _ in throw AssistantError() }
            ),
            onSaved: {}
        )
        viewModel.voiceAssistantInteraction = .pendingEditConfirmation

        await viewModel.confirmPendingVoiceCommand()

        // Error path: interaction state is not updated — pending confirmation stays
        #expect(viewModel.hasPendingVoiceConfirmation == true)
        #expect(viewModel.errorMessage == "Connection failed.")
    }

    // MARK: - hasVoiceAssistantFeedback (drives voiceAssistantFeedback container visibility)

    @Test
    @MainActor
    func quickCaptureHasVoiceAssistantFeedbackTrueWhenMessageNonEmpty() {
        let viewModel = QuickCaptureViewModel(dependencies: makeMinimalDependencies(), onSaved: {})
        viewModel.voiceAssistantMessage = "I can update Shopping list to add Butter. Confirm or Cancel."

        #expect(viewModel.hasVoiceAssistantFeedback == true)
    }

    @Test
    @MainActor
    func quickCaptureHasVoiceAssistantFeedbackFalseByDefault() {
        let viewModel = QuickCaptureViewModel(dependencies: makeMinimalDependencies(), onSaved: {})
        // voiceAssistantMessage defaults to ""

        #expect(viewModel.hasVoiceAssistantFeedback == false)
    }

    @Test
    @MainActor
    func quickCaptureHasVoiceAssistantFeedbackFalseAfterMessageIsCleared() {
        let viewModel = QuickCaptureViewModel(dependencies: makeMinimalDependencies(), onSaved: {})
        viewModel.voiceAssistantMessage = "Some feedback."
        #expect(viewModel.hasVoiceAssistantFeedback == true)

        viewModel.voiceAssistantMessage = ""

        #expect(viewModel.hasVoiceAssistantFeedback == false)
    }

    // MARK: - transcriptionPreview (drives voiceTranscriptPreview container visibility)

    @Test
    @MainActor
    func quickCaptureTranscriptionPreviewEmptyByDefault() {
        let viewModel = QuickCaptureViewModel(dependencies: makeMinimalDependencies(), onSaved: {})

        #expect(viewModel.transcriptionPreview.isEmpty)
    }

    @Test
    @MainActor
    func quickCaptureTranscriptionPreviewRetainedAfterPendingEditResponse() async {
        let transcript = "Add butter to the shopping list."
        var processVoiceCaptureCalled = false
        let voiceDeps = makeMinimalDependencies(
            requestRecordingPermission: { true },
            stopRecording: {
                RecordedAudio(temporaryFileURL: makeTemporaryRecordingURL(), durationSeconds: 2)
            },
            processVoiceCapture: { _, _, _, _ in
                processVoiceCaptureCalled = true
                return .assistantResponse(
                    NotesAssistantResponse(
                        text: "I can update Shopping list to add Butter. Confirm or Cancel.",
                        referencedNoteIDs: [],
                        interaction: .pendingEditConfirmation
                    ),
                    transcript: transcript
                )
            }
        )
        let viewModel = QuickCaptureViewModel(dependencies: voiceDeps, onSaved: {})

        await viewModel.toggleRecording()   // start recording
        await viewModel.toggleRecording()   // stop and process

        #expect(processVoiceCaptureCalled)
        #expect(viewModel.transcriptionPreview == transcript)
        #expect(viewModel.hasVoiceAssistantFeedback == true)
        #expect(viewModel.hasPendingVoiceConfirmation == true)
    }

    // MARK: - Additional edge cases

    @Test
    @MainActor
    func quickCaptureCancelIsNoOpWhenAlreadySavingAudio() async {
        var capturedInputs: [String] = []
        let viewModel = QuickCaptureViewModel(
            dependencies: makeMinimalDependencies(
                processAssistantInput: { input in
                    capturedInputs.append(input)
                    return NotesAssistantResponse(text: "", referencedNoteIDs: [])
                }
            ),
            onSaved: {}
        )
        viewModel.voiceAssistantInteraction = .pendingEditConfirmation
        viewModel.isSavingAudio = true

        await viewModel.cancelPendingVoiceCommand()

        #expect(capturedInputs.isEmpty)
    }

    @Test
    @MainActor
    func quickCaptureErrorMessageClearedOnSubsequentSuccessfulConfirm() async {
        struct FirstError: LocalizedError {
            var errorDescription: String? { "First failure." }
        }

        var shouldFail = true
        let viewModel = QuickCaptureViewModel(
            dependencies: makeMinimalDependencies(
                processAssistantInput: { _ in
                    if shouldFail {
                        throw FirstError()
                    }
                    return NotesAssistantResponse(text: "Recovered.", referencedNoteIDs: [], interaction: .none)
                }
            ),
            onSaved: {}
        )
        viewModel.voiceAssistantInteraction = .pendingEditConfirmation

        // First attempt fails
        await viewModel.confirmPendingVoiceCommand()
        #expect(viewModel.errorMessage == "First failure.")

        // Second attempt succeeds — pending state was preserved on error so we can retry
        shouldFail = false
        viewModel.voiceAssistantInteraction = .pendingEditConfirmation
        await viewModel.confirmPendingVoiceCommand()

        // Error message should be cleared after a successful call
        #expect(viewModel.errorMessage == nil || viewModel.errorMessage?.isEmpty == true)
    }

    @Test
    @MainActor
    func quickCaptureTranscriptionPreviewClearedAfterSuccessfulConfirm() async {
        let viewModel = QuickCaptureViewModel(
            dependencies: makeMinimalDependencies(
                processAssistantInput: { _ in
                    NotesAssistantResponse(text: "Confirmed.", referencedNoteIDs: [UUID()], interaction: .none)
                }
            ),
            onSaved: {}
        )
        viewModel.voiceAssistantInteraction = .pendingEditConfirmation
        viewModel.transcriptionPreview = "Some prior transcript."

        await viewModel.confirmPendingVoiceCommand()

        // After a successful confirm the transcript preview should be cleared
        #expect(viewModel.transcriptionPreview.isEmpty)
    }

    @Test
    @MainActor
    func quickCaptureVoiceAssistantMessageUpdatedToCancelResponseText() async {
        let viewModel = QuickCaptureViewModel(
            dependencies: makeMinimalDependencies(
                processAssistantInput: { _ in
                    NotesAssistantResponse(
                        text: "Edit discarded.",
                        referencedNoteIDs: [],
                        interaction: .none
                    )
                }
            ),
            onSaved: {}
        )
        viewModel.voiceAssistantInteraction = .pendingEditConfirmation
        viewModel.voiceAssistantMessage = "Proposed edit text."

        await viewModel.cancelPendingVoiceCommand()

        #expect(viewModel.voiceAssistantMessage == "Edit discarded.")
    }
}