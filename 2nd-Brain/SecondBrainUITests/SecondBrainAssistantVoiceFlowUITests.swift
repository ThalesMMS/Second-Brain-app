import XCTest

final class SecondBrainAssistantVoiceFlowUITests: XCTestCase {
    private enum Fixture {
        static let shoppingListID = "00000000-0000-0000-0000-000000000101"
        static let shoppingListTitle = "Shopping list"
        static let fixedAssistantReply = "Stub assistant reply from UI test mode."
        static let pendingEditTranscript = "Add butter to the shopping list."
        static let draftFallbackTranscript = "Call the residency office tomorrow morning."
        static let pendingEditMessage = "I can update Shopping list to add Butter. Confirm or Cancel."
        static let pendingEditConfirmedMessage = "Updated note Shopping list."
        static let pendingEditCancelledMessage = "Canceled the pending edit."
        static let draftFallbackFeedbackSnippet = "I kept the transcript in the draft"
        static let seededShoppingListBody = "Milk\nEggs\nBread"
        static let updatedShoppingListBody = "Milk\nEggs\nBread\nButter"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAskNotesSendsPromptAndRendersDeterministicReply() throws {
        let app = SecondBrainUITestLaunchConfiguration.askNotesReply.makeApplication()
        app.launch()

        openAskNotes(in: app)

        let inputField = app.textFields["assistantInputField"]
        XCTAssertTrue(inputField.waitForExistence(timeout: 5))
        inputField.tap()
        inputField.typeText("Summarize my shopping list.")

        let sendButton = app.buttons["assistantSendButton"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5))
        sendButton.tap()

        XCTAssertTrue(app.staticTexts[Fixture.fixedAssistantReply].waitForExistence(timeout: 5))
    }

    @MainActor
    func testQuickCaptureShowsTranscriptFeedbackAndPendingConfirmation() throws {
        let app = SecondBrainUITestLaunchConfiguration.quickCapturePendingEdit.makeApplication()
        app.launch()

        openQuickCapture(in: app)
        processVoiceInput(in: app)

        assertPendingEditUI(in: app)
    }

    @MainActor
    func testQuickCaptureConfirmAppliesSeededNoteMutation() throws {
        let app = SecondBrainUITestLaunchConfiguration.quickCapturePendingEdit.makeApplication()
        app.launch()

        openQuickCapture(in: app)
        processVoiceInput(in: app)
        assertPendingEditUI(in: app)

        let confirmButton = app.buttons["confirmPendingVoiceCommandButton"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5))
        confirmButton.tap()

        XCTAssertTrue(app.staticTexts[Fixture.pendingEditConfirmedMessage].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForDisappearance(of: confirmButton))
        XCTAssertFalse(app.buttons["cancelPendingVoiceCommandButton"].exists)

        closeQuickCapture(in: app)
        openShoppingList(in: app)

        let noteBodyEditor = app.textViews["noteBodyEditor"]
        XCTAssertTrue(noteBodyEditor.waitForExistence(timeout: 5))
        XCTAssertEqual(stringValue(of: noteBodyEditor), Fixture.updatedShoppingListBody)
    }

    @MainActor
    func testQuickCaptureCancelLeavesSeededNoteUnchanged() throws {
        let app = SecondBrainUITestLaunchConfiguration.quickCapturePendingEdit.makeApplication()
        app.launch()

        openQuickCapture(in: app)
        processVoiceInput(in: app)
        assertPendingEditUI(in: app)

        let cancelButton = app.buttons["cancelPendingVoiceCommandButton"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5))
        cancelButton.tap()
        XCTAssertTrue(app.staticTexts[Fixture.pendingEditCancelledMessage].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForDisappearance(of: cancelButton))

        closeQuickCapture(in: app)
        openShoppingList(in: app)

        let noteBodyEditor = app.textViews["noteBodyEditor"]
        XCTAssertTrue(noteBodyEditor.waitForExistence(timeout: 5))
        XCTAssertEqual(stringValue(of: noteBodyEditor), Fixture.seededShoppingListBody)
    }

    @MainActor
    func testQuickCaptureDraftFallbackPromotesTranscriptIntoDraft() throws {
        let app = SecondBrainUITestLaunchConfiguration.quickCaptureDraftFallback.makeApplication()
        app.launch()

        openQuickCapture(in: app)
        processVoiceInput(in: app)

        let transcriptPreview = app.otherElements["voiceTranscriptPreview"]
        XCTAssertTrue(transcriptPreview.waitForExistence(timeout: 5))
        XCTAssertTrue(transcriptPreview.staticTexts[Fixture.draftFallbackTranscript].exists)

        let feedback = app.otherElements["voiceAssistantFeedback"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))
        XCTAssertTrue(
            feedback.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", Fixture.draftFallbackFeedbackSnippet)
            ).firstMatch.waitForExistence(timeout: 5)
        )

        XCTAssertFalse(app.buttons["confirmPendingVoiceCommandButton"].exists)
        XCTAssertFalse(app.buttons["cancelPendingVoiceCommandButton"].exists)

        let bodyEditor = app.textViews["quickCaptureBodyEditor"]
        XCTAssertTrue(bodyEditor.waitForExistence(timeout: 5))
        XCTAssertEqual(stringValue(of: bodyEditor), Fixture.draftFallbackTranscript)
    }

    @MainActor
    private func openAskNotes(in app: XCUIApplication) {
        let askNotesButton = app.buttons["askNotesButton"]
        XCTAssertTrue(askNotesButton.waitForExistence(timeout: 5))
        askNotesButton.tap()
        XCTAssertTrue(app.navigationBars["Ask Notes"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func openQuickCapture(in app: XCUIApplication) {
        let quickCaptureButton = app.buttons["quickCaptureButton"]
        XCTAssertTrue(quickCaptureButton.waitForExistence(timeout: 5))
        quickCaptureButton.tap()
        XCTAssertTrue(app.navigationBars["Quick Capture"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func closeQuickCapture(in app: XCUIApplication) {
        let closeButton = app.buttons["Close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        closeButton.tap()
        XCTAssertTrue(app.buttons["quickCaptureButton"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func processVoiceInput(in app: XCUIApplication) {
        let recordButton = app.buttons["recordVoiceNoteButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
        recordButton.tap()
        XCTAssertTrue(waitForLabel("Stop recording and process", on: recordButton))
        recordButton.tap()
    }

    // MARK: - Accessibility identifier presence / absence

    /// Regression: the voiceTranscriptPreview and voiceAssistantFeedback containers must NOT
    /// be present when Quick Capture is first opened and no voice input has been processed yet.
    @MainActor
    func testVoiceTranscriptPreviewAndFeedbackAbsentOnFreshOpen() throws {
        let app = SecondBrainUITestLaunchConfiguration.seeded.makeApplication()
        app.launch()

        openQuickCapture(in: app)

        XCTAssertFalse(app.otherElements["voiceTranscriptPreview"].waitForExistence(timeout: 2),
                       "voiceTranscriptPreview must not appear before any voice input is processed")
        XCTAssertFalse(app.otherElements["voiceAssistantFeedback"].waitForExistence(timeout: 2),
                       "voiceAssistantFeedback must not appear before any voice input is processed")
        XCTAssertFalse(app.buttons["confirmPendingVoiceCommandButton"].exists,
                       "confirmPendingVoiceCommandButton must not appear in the initial state")
        XCTAssertFalse(app.buttons["cancelPendingVoiceCommandButton"].exists,
                       "cancelPendingVoiceCommandButton must not appear in the initial state")
    }

    /// Verifies that the voiceAssistantFeedback container exposes its child buttons via
    /// its accessibility subtree (children: .contain), so confirm and cancel are reachable
    /// both at the top level and through the container element.
    @MainActor
    func testVoiceAssistantFeedbackContainerExposesBothActionButtons() throws {
        let app = SecondBrainUITestLaunchConfiguration.quickCapturePendingEdit.makeApplication()
        app.launch()

        openQuickCapture(in: app)
        processVoiceInput(in: app)
        assertPendingEditUI(in: app)

        let feedback = app.otherElements["voiceAssistantFeedback"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))

        // Both action buttons must be reachable through the container (accessibilityElement children: .contain)
        XCTAssertTrue(feedback.buttons["confirmPendingVoiceCommandButton"].waitForExistence(timeout: 5),
                      "confirmPendingVoiceCommandButton must be contained within voiceAssistantFeedback")
        XCTAssertTrue(feedback.buttons["cancelPendingVoiceCommandButton"].waitForExistence(timeout: 5),
                      "cancelPendingVoiceCommandButton must be contained within voiceAssistantFeedback")
    }

    /// Negative case: when microphone permission is denied, tapping the record button
    /// must surface an in-app error without crashing or hanging.
    @MainActor
    func testQuickCaptureDeniedMicrophonePermissionShowsError() throws {
        let config = SecondBrainUITestLaunchConfiguration(
            dataset: .standard,
            assistant: .deterministicSearch,
            voice: .newNote,
            microphonePermission: .denied
        )
        let app = config.makeApplication()
        app.launch()

        openQuickCapture(in: app)

        let recordButton = app.buttons["recordVoiceNoteButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
        recordButton.tap()

        // The stub denies mic permission → the ViewModel sets errorMessage → an alert appears
        let permissionAlert = app.alerts["microphonePermissionErrorAlert"]
        XCTAssertTrue(permissionAlert.waitForExistence(timeout: 5),
                      "A microphonePermissionErrorAlert must appear when microphone permission is denied")

        permissionAlert.buttons["OK"].tap()

        // After dismissing the alert the Quick Capture view must still be usable
        XCTAssertTrue(app.navigationBars["Quick Capture"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func assertPendingEditUI(in app: XCUIApplication) {
        let transcriptPreview = app.otherElements["voiceTranscriptPreview"]
        XCTAssertTrue(transcriptPreview.waitForExistence(timeout: 5))
        XCTAssertTrue(transcriptPreview.staticTexts[Fixture.pendingEditTranscript].exists)

        let feedback = app.otherElements["voiceAssistantFeedback"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))
        XCTAssertTrue(feedback.staticTexts[Fixture.pendingEditMessage].exists)

        XCTAssertTrue(app.buttons["confirmPendingVoiceCommandButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["cancelPendingVoiceCommandButton"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func openShoppingList(in app: XCUIApplication) {
        let row = app.buttons["noteRow_\(Fixture.shoppingListID)"]
        if row.waitForExistence(timeout: 5) {
            row.tap()
            XCTAssertTrue(app.textFields["noteTitleField"].waitForExistence(timeout: 5))
            return
        }

        let title = app.staticTexts[Fixture.shoppingListTitle]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        XCTAssertTrue(app.textFields["noteTitleField"].waitForExistence(timeout: 5))
    }

    private func stringValue(of element: XCUIElement) -> String {
        element.value as? String ?? ""
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )

        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForLabel(
        _ label: String,
        on element: XCUIElement,
        timeout: TimeInterval = 5
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", label),
            object: element
        )

        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
